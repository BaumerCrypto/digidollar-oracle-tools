#Requires -Version 5.1
###############################################################################
# test-win-daemon-services.ps1 v2 — Isolated harness for Check-Daemon +
# Check-Services on Windows PowerShell 5.1 / 7+. Mirrors the Session 24a
# macOS harness (9 scenarios pass on macOS bash). Mocks Get-Process,
# Get-Service, and Invoke-DGBCli so each scenario runs deterministically
# without a real DigiByte node or NSSM-wrapped service.
#
# v2 fix (Session 24, live-Windows verification): mock functions now use
# [CmdletBinding()] so caller-side -ErrorAction SilentlyContinue passes
# through as an auto-added common parameter instead of colliding with an
# explicitly declared $ErrorAction. Scenario state moved to $script: vars
# for guaranteed visibility from inside the mocks regardless of scope
# inheritance behavior.
#
# Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\test-win-daemon-services.ps1
###############################################################################

$SCRIPT_PATH = Join-Path (Split-Path -Parent $PSCommandPath) "oracle-monitor.ps1"
if (-not (Test-Path $SCRIPT_PATH)) {
    $SCRIPT_PATH = ".\oracle-monitor.ps1"
}

$script:Pass = 0
$script:Fail = 0

# ============================================================================
# Extract Check-Daemon and Check-Services from the main script
# ============================================================================

$scriptText = Get-Content -Raw -Path $SCRIPT_PATH -Encoding UTF8

function Extract-Function {
    param([string]$Name, [string]$Body)
    $pattern = "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?^\}\s*$"
    $m = [regex]::Match($Body, $pattern)
    if (-not $m.Success) { throw "Function $Name not found in script" }
    return $m.Value
}

$checkDaemon   = Extract-Function -Name "Check-Daemon"   -Body $scriptText
$checkServices = Extract-Function -Name "Check-Services" -Body $scriptText

# ============================================================================
# Scenario state — held in $script: scope
# ============================================================================

$script:__ScenProcs        = @()
$script:__ScenSvcName      = ""
$script:__ScenSvcStatus    = ""
$script:__ScenOracleRunning = "false"

# ============================================================================
# Scenario runner
# ============================================================================

function Run-Scenario {
    param(
        [string]$Label,
        [string]$Expect,
        [string]$NotExpect,
        [string[]]$Processes,
        [string]$DaemonProcess,
        [string]$ServiceName,
        [string]$ServiceStatus,
        [string]$OracleRunning
    )

    # Fresh per-scenario globals
    $script:Issues    = 0
    $script:Warnings  = 0
    $script:Details   = New-Object System.Collections.Generic.List[string]
    $script:DetectedDaemon = $null
    $script:DdActive  = $true
    $script:DdStatus  = "active"
    $script:DRY_RUN   = $true

    # Config-level vars that Check-Daemon and Check-Services read
    $global:DAEMON_PROCESS = $DaemonProcess
    $global:SERVICE_NAME   = $ServiceName

    # Publish scenario state to $script: for the mocks
    $script:__ScenProcs         = $Processes
    $script:__ScenSvcName       = $ServiceName
    $script:__ScenSvcStatus     = $ServiceStatus
    $script:__ScenOracleRunning = $OracleRunning

    # ---- Mocks — [CmdletBinding()] absorbs -ErrorAction as a common param
    # ---- (v2 fix: no explicit $ErrorAction declaration to collide with it)
    function global:Get-Process {
        [CmdletBinding()]
        param([string]$Name)
        if ($script:__ScenProcs -contains $Name) {
            return [pscustomobject]@{ Name = $Name; Id = 1234 }
        }
        return $null
    }

    function global:Get-Service {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -eq $script:__ScenSvcName -and -not [string]::IsNullOrEmpty($script:__ScenSvcStatus)) {
            return [pscustomobject]@{ Name = $Name; Status = $script:__ScenSvcStatus }
        }
        return $null
    }

    function global:Invoke-DGBCli {
        [CmdletBinding()]
        param(
            [string[]]$RpcArgs,
            [switch]$UseWallet
        )
        if ($RpcArgs -contains "listoracle") {
            return "{`"running`":$($script:__ScenOracleRunning)}"
        }
        return $null
    }

    # Silence alert helpers so harness output stays readable
    function global:Alert-Red    { param($t, $m) }
    function global:Alert-Yellow { param($t, $m) }
    function global:Alert-Green  { param($t, $m) }
    function global:Alert-Blue   { param($t, $m) }

    # Dry-run behavior for should/clear alert helpers
    function global:Test-ShouldAlert { param($k) return $true  }
    function global:Clear-AlertState { param($k) return $false }

    # ---- Inject the two functions under test into this scope
    Invoke-Expression $checkDaemon
    Invoke-Expression $checkServices

    # ---- Run
    $null = Check-Daemon
    Check-Services

    $details = ($script:Details -join "`n")

    # ---- Assert
    $ok = $true
    if ($details -notmatch [regex]::Escape($Expect)) { $ok = $false }
    if (-not [string]::IsNullOrEmpty($NotExpect) -and $details -match [regex]::Escape($NotExpect)) {
        $ok = $false
    }

    if ($ok) {
        Write-Host "PASS: $Label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "FAIL: $Label" -ForegroundColor Red
        Write-Host "  expected substring: $Expect"
        if (-not [string]::IsNullOrEmpty($NotExpect)) {
            Write-Host "  must-not-contain:   $NotExpect"
        }
        Write-Host "  got Details:`n$details"
        $script:Fail++
    }

    # Clean up global mocks
    Remove-Item -Path function:global:Get-Process       -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Get-Service       -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Invoke-DGBCli     -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Alert-Red         -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Alert-Yellow      -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Alert-Green       -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Alert-Blue        -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Test-ShouldAlert  -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Clear-AlertState  -ErrorAction SilentlyContinue
}

# ============================================================================
# Scenarios — same 9 as v1, with S7 expect string matching production em-dash
# ============================================================================

Write-Host "===== Windows Check-Daemon + Check-Services scenarios (v2) ====="

Run-Scenario -Label "S1: auto-detect finds digibyted headless" `
    -Expect "Node: digibyted running" -NotExpect "NOT RUNNING" `
    -Processes @("digibyted") -DaemonProcess "" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "true"

Run-Scenario -Label "S2: auto-detect falls back to digibyte-qt" `
    -Expect "Node: digibyte-qt running" -NotExpect "NOT RUNNING" `
    -Processes @("digibyte-qt") -DaemonProcess "" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "true"

Run-Scenario -Label "S3: both running -> headless preferred" `
    -Expect "Node: digibyted running" -NotExpect "digibyte-qt running" `
    -Processes @("digibyted", "digibyte-qt") -DaemonProcess "" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "true"

Run-Scenario -Label "S4: nothing running fires real Node Down" `
    -Expect "NOT RUNNING (checked digibyted, digibyte-qt)" -NotExpect "" `
    -Processes @() -DaemonProcess "" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "false"

Run-Scenario -Label "S5: explicit DAEMON_PROCESS override honored" `
    -Expect "Node: digibyte-qt running" -NotExpect "NOT RUNNING" `
    -Processes @("digibyte-qt") -DaemonProcess "digibyte-qt" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "true"

Run-Scenario -Label "S6: explicit override with wrong daemon -> real Node Down" `
    -Expect "NOT RUNNING" -NotExpect "" `
    -Processes @("digibyted") -DaemonProcess "digibyte-qt" `
    -ServiceName "" -ServiceStatus "" -OracleRunning "false"

Run-Scenario -Label "S7: Qt detected -> Windows Service check SKIPPED with INFO line" `
    -Expect "Service: n/a — Qt wallet is the running daemon" -NotExpect "not found" `
    -Processes @("digibyte-qt") -DaemonProcess "" `
    -ServiceName "DigiByte" -ServiceStatus "Running" -OracleRunning "true"

Run-Scenario -Label "S8: headless + Windows Service running -> green" `
    -Expect "Service DigiByte: running" -NotExpect "not found" `
    -Processes @("digibyted") -DaemonProcess "" `
    -ServiceName "DigiByte" -ServiceStatus "Running" -OracleRunning "true"

Run-Scenario -Label "S9: headless + Windows Service missing -> red" `
    -Expect "Service DigiByte: not found" -NotExpect "n/a" `
    -Processes @("digibyted") -DaemonProcess "" `
    -ServiceName "DigiByte" -ServiceStatus "" -OracleRunning "true"

Write-Host ""
Write-Host "===== RESULT: $($script:Pass) pass / $($script:Fail) fail ====="

if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
