#Requires -Version 5.1
###############################################################################
# oracle-monitor.ps1 — DGB Oracle Health Monitor with Discord Alerts (Windows)
# Version: 2.2-win.1
#
# Windows PowerShell port of my oracle-monitor.sh v2.2 (Linux). Same checks,
# same quorum state machine, same anti-flap logic — Windows-native commands.
# Runs on Windows PowerShell 5.1 (preinstalled on Windows 10/11) and
# PowerShell 7+. No jq needed — PowerShell parses JSON natively.
#
# Author: digibyte-maxi (Oracle ID 17) | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 — June 2026
#
# SETUP:
#   1. Save this script somewhere permanent, e.g.:
#        C:\OracleMonitor\oracle-monitor.ps1
#      IMPORTANT: keep the file encoded as UTF-8 WITH BOM (it ships that way).
#      Windows PowerShell 5.1 misreads UTF-8 files without a BOM and the
#      emoji in alerts turn to mojibake.
#   2. Create the config folder and copy the template:
#        mkdir $env:USERPROFILE\.oracle-monitor
#        copy config.template.ps1 $env:USERPROFILE\.oracle-monitor\config.ps1
#   3. Edit config.ps1: set your Discord webhook URL and oracle settings
#      (especially $CLI_PATH if digibyte-cli.exe is not on your PATH).
#   4. Allow local scripts to run (one time, current user only):
#        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#   5. Test it:        .\oracle-monitor.ps1 -DryRun
#   6. Test webhook:   .\oracle-monitor.ps1 -Test
#   7. Schedule it (run both from an elevated or normal prompt):
#        schtasks /Create /SC MINUTE /MO 5 /TN "OracleMonitor" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\OracleMonitor\oracle-monitor.ps1"
#        schtasks /Create /SC HOURLY /MO 12 /TN "OracleMonitorSummary" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\OracleMonitor\oracle-monitor.ps1 -Summary"
#      Then in Task Scheduler (taskschd.msc) open each task's Conditions tab
#      and untick "Start the task only if the computer is on AC power" if
#      this is a laptop. Your PC must be awake for the task to run.
#
# FLAGS:
#   (none)     Normal health check — alerts only on problems/recovery
#   -Summary   Full status summary — always sends to Discord
#   -DryRun    Runs all checks, prints to terminal, skips Discord, no state changes
#   -Watch     Live console dashboard — refreshes the full status every 60s
#              (-Watch -RefreshSeconds 30 for 30s). Never alerts, never
#              touches state: safe to leave a PowerShell window open with
#              this running alongside the scheduled tasks.
#   -Test      Sends a test embed to Discord to verify webhook
#
# CHANGELOG:
#   v2.2-win.1 — Initial Windows PowerShell port. Logic parity with Linux
#          v2.2: heartbeat-based quorum counting, anti-flap cooldown +
#          hysteresis, single quorum_state file, escalation always
#          immediate. Platform adaptations: Get-Process replaces pgrep,
#          Get-CimInstance Win32_OperatingSystem replaces free,
#          Get-PSDrive replaces df, w32tm /stripchart offset measurement
#          replaces timedatectl, optional Windows service check replaces
#          systemctl, Task Scheduler replaces cron, Invoke-RestMethod
#          replaces curl, native ConvertFrom-Json replaces jq (no
#          dependency to install). NTP green-line output matches Linux
#          exactly ("synchronized"); offset still measured internally so
#          a drifting clock fires a yellow alert with the offset value.
#          Node version via `digibyted --version` (same full string as
#          Linux) with getnetworkinfo RPC fallback. Process name
#          configurable ($DAEMON_PROCESS) for Qt vs headless.
#
#   Linux lineage this port tracks (see oracle-monitor.sh for details):
#   v2.2 — heartbeat_status quorum counting   v2.1.1 — hysteresis fix
#   v2.1 — anti-flap                          v2.0 — quorum margin (#6)
#   v1.5 — listoracle RPC check (#22)         v1.4 — warning/error enum (#21)
#   v1.3 — RC44 status enum                   v1.2 — config file, dry-run
#   v1.1 — degraded consensus, NTP            v1.0 — initial release
###############################################################################

param(
    [switch]$Summary,
    [switch]$DryRun,
    [switch]$Test,
    [switch]$Watch,
    [int]$RefreshSeconds = 60
)

# ============================================================================
# RUNTIME ENVIRONMENT
# ============================================================================

# Discord requires TLS 1.2+. Windows PowerShell 5.1 on older builds defaults
# to TLS 1.0 and the webhook POST fails silently without this line.
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Make emoji print correctly when run interactively (-DryRun). Harmless
# (caught) when running headless under Task Scheduler.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ============================================================================
# CONFIGURATION — DEFAULTS (override in %USERPROFILE%\.oracle-monitor\config.ps1)
# ============================================================================

# Discord webhook URL — get this from your Discord server settings
# Server Settings > Integrations > Webhooks > New Webhook > Copy URL
$DISCORD_WEBHOOK = ""

# Oracle settings
$ORACLE_ID   = 0
$ORACLE_NAME = "my-oracle"

# Path to digibyte-cli.exe. If it is on your PATH, the bare name works.
# Typical full path: "C:\Program Files\DigiByte\daemon\digibyte-cli.exe"
$CLI_PATH = "digibyte-cli.exe"

# Network + wallet arguments passed to every CLI call.
# Testnet:  @("-testnet")        Mainnet:  @()
$CLI_ARGS    = @("-testnet")
$WALLET_FLAG = "-rpcwallet=oracle"

# Process name of your node, WITHOUT .exe:
#   "digibyted"    headless daemon (recommended for oracles)
#   "digibyte-qt"  if you run the Qt wallet instead
$DAEMON_PROCESS = "digibyted"

# Optional: if you run digibyted as a Windows service (e.g. via NSSM),
# put the service name here and the summary will report its status.
# Leave "" to skip the service check.
$SERVICE_NAME = ""

# Drive letter to watch for free disk space (where your DigiByte datadir
# lives — datadir default is %APPDATA%\DigiByte on drive C).
$DISK_DRIVE = "C"

# Thresholds — basic health
$MIN_PEERS           = 3
$MIN_DISK_GB         = 5
$STALE_PRICE_MINUTES = 30    # Reserved for future use — staleness currently from RPC
$MEM_THRESHOLD       = 90
$MAX_CHAIN_BEHIND    = 10

# NTP check — measures actual clock offset against a time server using
# w32tm /stripchart (locale-independent, works even if the Windows Time
# service is stopped). Oracle bundles are rejected past 3600s skew, so
# keep this tight.
$NTP_SERVER             = "time.windows.com"
$NTP_MAX_OFFSET_SECONDS = 1.0

# Thresholds — quorum margin (v2.0)
# These define the alert bands for network-wide oracle liveness.
# Quorum threshold (oracle_consensus_required) comes from the chain via
# getdigidollardeploymentinfo — not hardcoded here.
#
# QUORUM_GREEN: at or above this count = comfortable, no alerts
# QUORUM_YELLOW: at or above this but below green = "getting thin" warning
# Below QUORUM_YELLOW but at/above consensus_required = red, at quorum edge
# Below consensus_required = CRITICAL — DD bundle signing may halt
$QUORUM_GREEN  = 20
$QUORUM_YELLOW = 12

# Anti-flap — quorum alert throttling (v2.1)
# QUORUM_COOLDOWN: minimum minutes between quorum recovery alerts.
#   Escalation (getting worse) ALWAYS fires immediately regardless.
#   Only recovery (getting better) is throttled by this timer.
#   Set to 0 to disable cooldown (v2.0 behavior).
$QUORUM_COOLDOWN = 30

# QUORUM_HYSTERESIS: buffer above threshold required for recovery.
#   Prevents oscillation when the count hovers right at a boundary.
#   Example: GREEN=20, HYSTERESIS=3 -> recovery to green needs 23+.
#   Set to 0 to disable hysteresis (v2.0 behavior).
$QUORUM_HYSTERESIS = 3

# ============================================================================
# LOAD EXTERNAL CONFIG (overrides defaults above)
# ============================================================================

$STATE_DIR   = Join-Path $env:USERPROFILE ".oracle-monitor"
$CONFIG_FILE = Join-Path $STATE_DIR "config.ps1"

if (Test-Path $CONFIG_FILE) {
    . $CONFIG_FILE
}

New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null

# Runtime flag — set by -DryRun
$script:DRY_RUN = [bool]$DryRun

# ============================================================================
# CLI WRAPPER
# ============================================================================

# Runs digibyte-cli with the configured network args plus the given RPC
# command. Returns the raw stdout string, or $null if the call failed
# (binary missing, daemon down, RPC error). Mirrors the bash pattern of
# `$CLI ... 2>/dev/null` + exit-code check.
function Invoke-DGBCli {
    param(
        [string[]]$RpcArgs,
        [switch]$UseWallet
    )
    $allArgs = @()
    $allArgs += $CLI_ARGS
    if ($UseWallet -and $WALLET_FLAG) { $allArgs += $WALLET_FLAG }
    $allArgs += $RpcArgs

    try {
        $out = & $CLI_PATH @allArgs 2>$null
    } catch {
        return $null   # binary not found / not executable
    }
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($null -eq $out) { return $null }
    return (@($out) -join "`n")
}

# ============================================================================
# DISCORD NOTIFICATION FUNCTIONS
# ============================================================================

function Send-Discord {
    param(
        [int]$Color,      # red=16711680, green=65280, yellow=16776960, blue=3447003
        [string]$Title,
        [string]$Message
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    if ($script:DRY_RUN -or [string]::IsNullOrEmpty($DISCORD_WEBHOOK)) {
        # Write-Host, not Write-Output: this function is called inside checks
        # whose return values are consumed (Check-Daemon). Write-Output here
        # would pollute those return values; Write-Host goes straight to the
        # console and leaves the output stream clean.
        Write-Host "[$(Get-Date)] ALERT: $Title — $Message"
        return
    }

    $payload = @{
        embeds = @(
            @{
                title       = $Title
                description = $Message
                color       = $Color
                footer      = @{ text = "Oracle Monitor — $ORACLE_NAME (ID $ORACLE_ID)" }
                timestamp   = $timestamp
            }
        )
    } | ConvertTo-Json -Depth 5

    # Send as UTF-8 bytes. PowerShell 5.1's Invoke-RestMethod encodes string
    # bodies as ISO-8859-1, which destroys the emoji — bytes go through raw.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    try {
        Invoke-RestMethod -Uri $DISCORD_WEBHOOK -Method Post `
            -ContentType "application/json" -Body $bytes | Out-Null
    } catch { }   # webhook hiccup must never kill the monitor run
}

function Alert-Red    { param($t, $m) Send-Discord -Color 16711680 -Title $t -Message $m }
function Alert-Yellow { param($t, $m) Send-Discord -Color 16776960 -Title $t -Message $m }
function Alert-Green  { param($t, $m) Send-Discord -Color 65280    -Title $t -Message $m }
function Alert-Blue   { param($t, $m) Send-Discord -Color 3447003  -Title $t -Message $m }

# Only alert once per issue until it clears.
# In -DryRun mode: always returns "should alert" but does NOT touch state files.
function Test-ShouldAlert {
    param([string]$Key)
    $stateFile = Join-Path $STATE_DIR $Key
    if ($script:DRY_RUN) {
        return $true   # always "should alert" in dry-run, don't touch state
    }
    if (Test-Path $stateFile) {
        return $false  # already alerted
    }
    New-Item -ItemType File -Path $stateFile -Force | Out-Null
    return $true
}

# In -DryRun mode: always returns "nothing was set" and does NOT touch state files.
function Clear-AlertState {
    param([string]$Key)
    $stateFile = Join-Path $STATE_DIR $Key
    if ($script:DRY_RUN) {
        return $false  # pretend nothing was set, don't touch state
    }
    if (Test-Path $stateFile) {
        Remove-Item $stateFile -Force
        return $true   # was set, now cleared = recovery
    }
    return $false      # wasn't set
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================
# Function names deliberately mirror the bash check_* functions 1:1 so the
# two scripts can be diffed side by side.

$script:Issues   = 0
$script:Warnings = 0
$script:Details  = New-Object System.Collections.Generic.List[string]

# --- Check 1: Is digibyted running? ---
function Check-Daemon {
    $procName = $DAEMON_PROCESS -replace '\.exe$', ''
    $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue

    if ($proc) {
        if (Clear-AlertState "daemon_down") {
            Alert-Green "✅ Node Recovered" "$DAEMON_PROCESS is running again."
        }
        $script:Details.Add("✅ ${DAEMON_PROCESS}: running")
        return $true
    } else {
        if (Test-ShouldAlert "daemon_down") {
            Alert-Red "🔴 Node Down" "$DAEMON_PROCESS is NOT running! Restart it (check Task Scheduler or your service manager if you run it as a service)."
        }
        $script:Details.Add("🔴 ${DAEMON_PROCESS}: NOT RUNNING")
        $script:Issues++
        return $false  # skip remaining checks
    }
}

# --- Check 2: Is the oracle running and signing? ---
function Check-Oracle {
    $raw = Invoke-DGBCli -RpcArgs @("listoracle") -UseWallet

    if ([string]::IsNullOrEmpty($raw)) {
        if (Test-ShouldAlert "oracle_down") {
            Alert-Red "🔴 Oracle Not Running" "listoracle returned no data. Oracle may need to be restarted."
        }
        $script:Details.Add("🔴 Oracle: not responding")
        $script:Issues++
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }

    $running = $false
    if ($null -ne $info -and $null -ne $info.PSObject.Properties['running']) {
        $running = [bool]$info.running
    }

    if (-not $running) {
        if (Test-ShouldAlert "oracle_stopped") {
            Alert-Red "🔴 Oracle Stopped" "Oracle ID $ORACLE_ID is loaded but not running. Check ``startoracle``."
        }
        $script:Details.Add("🔴 Oracle: stopped")
        $script:Issues++
    } else {
        if (Clear-AlertState "oracle_stopped") {
            Alert-Green "✅ Oracle Recovered" "Oracle ID $ORACLE_ID is running and signing again."
        }
        if (Clear-AlertState "oracle_down") {
            Alert-Green "✅ Oracle Recovered" "Oracle ID $ORACLE_ID is responding again."
        }

        # Get the price being reported
        $price = "unknown"
        if ($null -ne $info.PSObject.Properties['price_usd'] -and $null -ne $info.price_usd) {
            $price = $info.price_usd
        }
        $script:Details.Add("✅ Oracle: running — reporting `$$price")
    }
}

# --- Check 3: Chain sync status ---
function Check-Chain {
    $raw = Invoke-DGBCli -RpcArgs @("getblockchaininfo")

    if ([string]::IsNullOrEmpty($raw)) {
        $script:Details.Add("⚠️ Chain: could not query")
        $script:Warnings++
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }
    if ($null -eq $info) {
        $script:Details.Add("⚠️ Chain: could not query")
        $script:Warnings++
        return
    }

    $blocks  = [long]$info.blocks
    $headers = [long]$info.headers
    $chain   = "unknown"
    if ($null -ne $info.PSObject.Properties['chain']) { $chain = $info.chain }

    $behind = $headers - $blocks

    if ($behind -gt $MAX_CHAIN_BEHIND) {
        if (Test-ShouldAlert "chain_behind") {
            Alert-Yellow "⚠️ Chain Behind" "Node is $behind blocks behind (block $blocks / header $headers)."
        }
        $script:Details.Add("⚠️ Chain: $behind blocks behind ($blocks / $headers)")
        $script:Warnings++
    } else {
        if (Clear-AlertState "chain_behind") {
            Alert-Green "✅ Chain Synced" "Node is synced at block $blocks."
        }
        $script:Details.Add("✅ Chain: synced at block $blocks ($chain)")
    }
}

# --- Check 4: Peer count ---
function Check-Peers {
    $raw = Invoke-DGBCli -RpcArgs @("getconnectioncount")

    if ([string]::IsNullOrEmpty($raw)) {
        $script:Details.Add("⚠️ Peers: could not query")
        $script:Warnings++
        return
    }

    $peerCount = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$peerCount)) {
        $script:Details.Add("⚠️ Peers: could not query")
        $script:Warnings++
        return
    }

    if ($peerCount -lt $MIN_PEERS) {
        if (Test-ShouldAlert "low_peers") {
            Alert-Yellow "⚠️ Low Peers" "Only $peerCount peers connected (minimum: $MIN_PEERS)."
        }
        $script:Details.Add("⚠️ Peers: $peerCount (low!)")
        $script:Warnings++
    } else {
        if (Clear-AlertState "low_peers") {
            Alert-Green "✅ Peers Recovered" "Peer count back to $peerCount."
        }
        $script:Details.Add("✅ Peers: $peerCount connected")
    }
}

# --- Check 5: Oracle consensus price ---
# v1.1: Also detects degraded consensus (status != "ok" with price_usd=0)
# v1.3: RC44 - handle "active" status enum in consensus check
# v1.4: RC44 - differentiate warning (notice) from error (alert) per RC44 enum
# v1.5: listoracle RPC replaces service checks (#22)
function Check-Price {
    $raw = Invoke-DGBCli -RpcArgs @("getoracleprice")

    if ([string]::IsNullOrEmpty($raw)) {
        $script:Details.Add("⚠️ Price: could not query")
        $script:Warnings++
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }
    if ($null -eq $info) {
        $script:Details.Add("⚠️ Price: could not query")
        $script:Warnings++
        return
    }

    $priceUsd = "unknown"
    if ($null -ne $info.PSObject.Properties['price_usd'] -and $null -ne $info.price_usd) {
        $priceUsd = $info.price_usd
    }
    $isStale = $false
    if ($null -ne $info.PSObject.Properties['is_stale']) { $isStale = [bool]$info.is_stale }
    $status = "unknown"
    if ($null -ne $info.PSObject.Properties['status']) { $status = $info.status }
    $oracleCount = 0
    if ($null -ne $info.PSObject.Properties['oracle_count']) { $oracleCount = $info.oracle_count }

    # Check 5a: Stale price (v1.0)
    if ($isStale) {
        if (Test-ShouldAlert "stale_price") {
            Alert-Yellow "⚠️ Stale Price" "Oracle consensus price is stale. Last price: `$$priceUsd"
        }
        $script:Details.Add("⚠️ Price: STALE — `$$priceUsd")
        $script:Warnings++
    # Check 5b: Error status — real problem, alert operator (v1.4)
    } elseif ($status -eq "error") {
        if (Test-ShouldAlert "degraded_consensus") {
            Alert-Yellow "⚠️ Degraded Consensus" "Network status: $status | Price: `$$priceUsd | Oracles: $oracleCount. Network aggregation is failing."
        }
        $script:Details.Add("⚠️ Price: `$$priceUsd (status: $status, oracles: $oracleCount)")
        $script:Warnings++
    # Check 5c: Warning status — network notice, no Discord alert (v1.4)
    } elseif ($status -eq "warning") {
        $script:Details.Add("⚠️ Price: `$$priceUsd (status: $status, oracles: $oracleCount)")
        $script:Warnings++
    } else {
        if (Clear-AlertState "stale_price") {
            Alert-Green "✅ Price Recovered" "Oracle price is fresh again: `$$priceUsd"
        }
        if (Clear-AlertState "degraded_consensus") {
            Alert-Green "✅ Consensus Recovered" "Network consensus restored. Price: `$$priceUsd"
        }
        $script:Details.Add("✅ Price: `$$priceUsd (fresh)")
    }
}

# --- Check 6: Disk space ---
function Check-Disk {
    $drive = Get-PSDrive -Name $DISK_DRIVE -ErrorAction SilentlyContinue

    if ($null -eq $drive -or $null -eq $drive.Free) {
        $script:Details.Add("⚠️ Disk: could not query drive $DISK_DRIVE")
        $script:Warnings++
        return
    }

    $availGB = [math]::Floor($drive.Free / 1GB)

    if ($availGB -lt $MIN_DISK_GB) {
        if (Test-ShouldAlert "low_disk") {
            Alert-Red "🔴 Low Disk Space" "Only ${availGB}GB free on drive ${DISK_DRIVE}:. Clean up old testnet dirs or logs."
        }
        $script:Details.Add("🔴 Disk: ${availGB}GB free (LOW!)")
        $script:Issues++
    } else {
        if (Clear-AlertState "low_disk") {
            Alert-Green "✅ Disk Space Recovered" "Disk space back to ${availGB}GB free."
        }
        $script:Details.Add("✅ Disk: ${availGB}GB free (drive ${DISK_DRIVE}:)")
    }
}

# --- Check 7: Memory usage ---
function Check-Memory {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

    if ($null -eq $os -or -not $os.TotalVisibleMemorySize) {
        $script:Details.Add("⚠️ Memory: could not query")
        $script:Warnings++
        return
    }

    $memPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)

    if ($memPct -gt $MEM_THRESHOLD) {
        if (Test-ShouldAlert "high_memory") {
            Alert-Yellow "⚠️ High Memory" "Memory usage at ${memPct}%."
        }
        $script:Details.Add("⚠️ Memory: ${memPct}% used")
        $script:Warnings++
    } else {
        Clear-AlertState "high_memory" | Out-Null
        $script:Details.Add("✅ Memory: ${memPct}% used")
    }
}

# --- Check 8: Service status (summary only) ---
# Windows has no systemd. If $SERVICE_NAME is set (e.g. NSSM-wrapped
# digibyted), the Windows service is checked; otherwise the process check
# stands in. Oracle process state comes from listoracle, same as Linux v1.5.
function Check-Services {
    if (-not [string]::IsNullOrEmpty($SERVICE_NAME)) {
        $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq "Running") {
            $script:Details.Add("✅ Service ${SERVICE_NAME}: running")
        } else {
            $svcStatus = "not found"
            if ($null -ne $svc) { $svcStatus = $svc.Status }
            $script:Details.Add("🔴 Service ${SERVICE_NAME}: $svcStatus")
            $script:Issues++
        }
    } else {
        $procName = $DAEMON_PROCESS -replace '\.exe$', ''
        if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
            $script:Details.Add("✅ $DAEMON_PROCESS process: running")
        } else {
            $script:Details.Add("🔴 $DAEMON_PROCESS process: not running")
            $script:Issues++
        }
    }

    $oracleStatus = "unknown"
    $raw = Invoke-DGBCli -RpcArgs @("listoracle") -UseWallet
    if (-not [string]::IsNullOrEmpty($raw)) {
        try {
            $info = $raw | ConvertFrom-Json
            if ($null -ne $info.PSObject.Properties['running']) {
                $oracleStatus = "$($info.running)".ToLower()
            }
        } catch { }
    }

    if ($oracleStatus -eq "true") {
        $script:Details.Add("✅ Oracle process: running")
    } else {
        $script:Details.Add("⚠️ Oracle process: $oracleStatus")
        $script:Warnings++
    }
}

# --- Check 9: Node version (summary only) ---
# Matches the Linux script: first line of `digibyted --version` (the full
# version string incl. release candidate and git hash). Tries digibyted.exe
# next to digibyte-cli.exe first, then on PATH. Falls back to the short
# getnetworkinfo subversion over RPC if the daemon binary can't be invoked.
function Check-Version {
    $verLine = $null
    $candidates = @()
    try {
        $cliDir = Split-Path -Parent $CLI_PATH
        if ($cliDir) { $candidates += (Join-Path $cliDir "digibyted.exe") }
    } catch { }
    $candidates += ("$($DAEMON_PROCESS -replace '\.exe$', '').exe")

    foreach ($bin in $candidates) {
        try {
            $out = & $bin --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) {
                $verLine = "$(@($out)[0])"
                break
            }
        } catch { }
    }

    if ([string]::IsNullOrEmpty($verLine)) {
        $raw = Invoke-DGBCli -RpcArgs @("getnetworkinfo")
        if (-not [string]::IsNullOrEmpty($raw)) {
            try {
                $info = $raw | ConvertFrom-Json
                if ($null -ne $info.PSObject.Properties['subversion']) {
                    $verLine = ($info.subversion -replace '/', '')
                }
            } catch { }
        }
    }

    if (-not [string]::IsNullOrEmpty($verLine)) {
        $script:Details.Add("ℹ️ $verLine")
    }
}

# --- Check 10: NTP time sync ---
# Measures the real clock offset with one w32tm stripchart sample. This is
# locale-independent (the offset token is always like +00.0012345s) and
# works even when the Windows Time service is stopped. Oracle bundle
# timestamps are rejected past 3600s skew — a drifting clock kills signing.
function Check-Ntp {
    $out = $null
    try {
        $out = w32tm /stripchart /computer:$NTP_SERVER /samples:1 /dataonly 2>$null
    } catch { }

    $offset = $null
    if ($null -ne $out) {
        $joined = @($out) -join "`n"
        if ($joined -match '([-+]\d+\.\d+)s') {
            $offset = [double]$Matches[1]
        }
    }

    if ($null -eq $offset) {
        # Could not measure (no network / UDP 123 blocked / w32tm missing).
        # Surface in summary as a warning but don't fire a Discord alert —
        # matches the "could not query" pattern of the other checks.
        $script:Details.Add("⚠️ NTP: could not verify (w32tm query failed)")
        $script:Warnings++
        return
    }

    $absOffset = [math]::Abs($offset)

    if ($absOffset -gt $NTP_MAX_OFFSET_SECONDS) {
        if (Test-ShouldAlert "ntp_desync") {
            Alert-Yellow "⚠️ NTP Desync" "System clock is off by $([math]::Round($offset, 3))s vs $NTP_SERVER. Oracle timestamps may drift. Run: w32tm /resync (elevated prompt)."
        }
        $script:Details.Add("⚠️ NTP: offset $([math]::Round($offset, 3))s (NOT synchronized)")
        $script:Warnings++
    } else {
        if (Clear-AlertState "ntp_desync") {
            Alert-Green "✅ NTP Recovered" "System clock is synchronized again (offset $([math]::Round($offset, 3))s)."
        }
        $script:Details.Add("✅ NTP: synchronized")
    }
}

# --- Quorum state machine helpers (v2.1) ---
# Maps quorum band names to numeric severity for comparison.
# Higher number = worse condition.
$script:BandSeverity = @{
    green    = 0
    yellow   = 1
    red      = 2
    critical = 3
}

function Get-BandSeverity {
    param([string]$Band)
    if ($script:BandSeverity.ContainsKey($Band)) {
        return $script:BandSeverity[$Band]
    }
    return 0
}

# --- Check 11: Quorum margin tracking (v2.0, closes #6) ---
# Counts how many oracles are actively reporting across the network.
# Compares against the on-chain quorum threshold from getdigidollardeploymentinfo.
# Also reports MuSig2 session health in the summary line.
#
# Alert bands (configurable via $QUORUM_GREEN and $QUORUM_YELLOW in config):
#   >= QUORUM_GREEN ............ Green — comfortable
#   >= QUORUM_YELLOW ........... Yellow — getting thin
#   >= consensus_required ...... Red — at quorum edge
#   < consensus_required ....... CRITICAL — DD may halt
#
# RPC FIELD NAMES (confirmed on RC44 testnet26 2026-06-09/11):
#   getdigidollardeploymentinfo -> oracle_consensus_required, oracle_total_slots,
#     musig2_session.epoch, musig2_session.state ("complete"/other),
#     musig2_session.nonce_count, musig2_session.partial_sig_count
#   getoracles true -> array of objects with heartbeat_status
#     ("fresh"/"stale"/"unknown") — "reporting" = heartbeat_status == "fresh"
#
# Debug commands (PowerShell, if something looks wrong):
#   & digibyte-cli.exe -testnet getdigidollardeploymentinfo | ConvertFrom-Json
#   (& digibyte-cli.exe -testnet getoracles true | ConvertFrom-Json)[0]
#
function Check-Quorum {
    # --- Step 1: Get deployment info (quorum threshold + MuSig2 session) ---
    $rawDeploy = Invoke-DGBCli -RpcArgs @("getdigidollardeploymentinfo")

    if ([string]::IsNullOrEmpty($rawDeploy)) {
        $script:Details.Add("⚠️ Quorum: could not query deployment info")
        $script:Warnings++
        return
    }

    $deploy = $null
    try { $deploy = $rawDeploy | ConvertFrom-Json } catch { }
    if ($null -eq $deploy) {
        $script:Details.Add("⚠️ Quorum: could not query deployment info")
        $script:Warnings++
        return
    }

    $consensusRequired = 7
    if ($null -ne $deploy.PSObject.Properties['oracle_consensus_required']) {
        $consensusRequired = [int]$deploy.oracle_consensus_required
    }
    $totalSlots = 35
    if ($null -ne $deploy.PSObject.Properties['oracle_total_slots']) {
        $totalSlots = [int]$deploy.oracle_total_slots
    }

    # MuSig2 session health — included in summary line
    $musigEpoch = "?"; $musigState = "?"; $musigNonces = "?"; $musigSigs = "?"
    $session = $null
    if ($null -ne $deploy.PSObject.Properties['musig2_session']) {
        $session = $deploy.musig2_session
    }
    if ($null -ne $session) {
        if ($null -ne $session.PSObject.Properties['epoch'])             { $musigEpoch  = $session.epoch }
        if ($null -ne $session.PSObject.Properties['state'])             { $musigState  = $session.state }
        if ($null -ne $session.PSObject.Properties['nonce_count'])       { $musigNonces = $session.nonce_count }
        if ($null -ne $session.PSObject.Properties['partial_sig_count']) { $musigSigs   = $session.partial_sig_count }
    }

    if ($musigState -eq "complete") {
        $musigDetail = "epoch $musigEpoch, $musigNonces/$consensusRequired nonces, $musigSigs/$consensusRequired sigs ✓"
    } elseif ("$musigEpoch" -ne "?") {
        $musigDetail = "epoch $musigEpoch, $musigNonces/$consensusRequired nonces, $musigSigs/$consensusRequired sigs ($musigState)"
    } else {
        $musigDetail = "could not parse session"
    }

    # --- Step 2: Count reporting oracles ---
    $rawOracles = Invoke-DGBCli -RpcArgs @("getoracles", "true")

    if ([string]::IsNullOrEmpty($rawOracles)) {
        $script:Details.Add("⚠️ Quorum: could not query oracles")
        $script:Warnings++
        return
    }

    $oracles = $null
    try { $oracles = @($rawOracles | ConvertFrom-Json) } catch { }

    # PS 5.1 quirk: ConvertFrom-Json returns $null for a literal "[]", which
    # would land in the "could not query" path below. But an EMPTY roster is
    # not a query failure — it means zero oracles are active, and that must
    # flow through as reporting=0 so the QUORUM LOST critical alert fires
    # (same as the Linux script, where jq counts [] as 0).
    $rosterEmpty = ($rawOracles.Trim() -eq "[]")

    if ((-not $rosterEmpty) -and ($null -eq $oracles -or $oracles.Count -eq 0)) {
        $script:Details.Add("⚠️ Quorum: could not query oracles")
        $script:Warnings++
        return
    }

    # Total oracles returned by getoracles true (active roster)
    $rosterCount = $oracles.Count

    # Count oracles with fresh heartbeats as "reporting" (v2.2)
    # heartbeat_status "fresh" = online + signed heartbeat within 30 min.
    # This matches the dashboard's "Online Heartbeats" metric and is stable
    # across MuSig2 round transitions (unlike last_price_usd which resets).
    $hasField = @($oracles | Where-Object { $null -ne $_.PSObject.Properties['heartbeat_status'] }).Count -gt 0

    if ($rosterEmpty) {
        # Zero active oracles — flows into Step 3 as critical (QUORUM LOST)
        $reporting = 0
    } elseif (-not $hasField) {
        # Fallback: field name mismatch — use roster count (mirrors Linux v2.2)
        $reporting = $rosterCount
        $script:Details.Add("⚠️ Quorum: could not count reporting oracles (heartbeat_status field missing?) — using roster count")
        $script:Warnings++
    } else {
        $reporting = @($oracles | Where-Object { $_.heartbeat_status -eq "fresh" }).Count
    }

    # --- Step 3: Determine raw quorum band ---
    if ($reporting -lt $consensusRequired) {
        $rawBand = "critical"
    } elseif ($reporting -lt $QUORUM_YELLOW) {
        $rawBand = "red"
    } elseif ($reporting -lt $QUORUM_GREEN) {
        $rawBand = "yellow"
    } else {
        $rawBand = "green"
    }

    # --- Step 4: Read previous state ---
    $stateFile = Join-Path $STATE_DIR "quorum_state"
    $prevBand = "green"
    $prevTime = [long]0

    if ((Test-Path $stateFile) -and (-not $script:DRY_RUN)) {
        $line = Get-Content $stateFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($line) {
            $parts = "$line".Trim() -split '\s+'
            if ($parts.Count -ge 1 -and @("green","yellow","red","critical") -contains $parts[0]) {
                $prevBand = $parts[0]
            }
            $tmp = [long]0
            if ($parts.Count -ge 2 -and [long]::TryParse($parts[1], [ref]$tmp)) {
                $prevTime = $tmp
            }
        }
    }

    $rawSev  = Get-BandSeverity $rawBand
    $prevSev = Get-BandSeverity $prevBand
    $now     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # --- Step 5: Apply hysteresis to recovery ---
    # When recovering (raw is better than previous), require the count
    # to exceed the threshold by QUORUM_HYSTERESIS to actually transition.
    # This creates a dead zone that absorbs oscillation at boundaries.
    $effectiveBand = $rawBand

    if (($rawSev -lt $prevSev) -and ($QUORUM_HYSTERESIS -gt 0) -and (-not $script:DRY_RUN)) {
        $greenRecover  = $QUORUM_GREEN + $QUORUM_HYSTERESIS
        $yellowRecover = $QUORUM_YELLOW + $QUORUM_HYSTERESIS
        $redRecover    = $consensusRequired + $QUORUM_HYSTERESIS

        # Evaluate what band the count actually clears with hysteresis applied.
        # Work from best to worst — first threshold met determines the band.
        # This correctly handles multi-band recovery (e.g. critical->green at 25/35).
        if ($reporting -ge $greenRecover) {
            $effectiveBand = "green"
        } elseif ($reporting -ge $yellowRecover) {
            $effectiveBand = "yellow"
        } elseif ($reporting -ge $redRecover) {
            $effectiveBand = "red"
        } else {
            $effectiveBand = "critical"
        }
    }

    $effSev = Get-BandSeverity $effectiveBand

    # --- Step 6: Decide whether to notify ---
    $shouldNotify = $false
    $updateState  = $false

    if ($script:DRY_RUN) {
        # Dry-run: always "notify" (prints to terminal), never update state
        $shouldNotify = $true
    } elseif ($effectiveBand -ne $prevBand) {
        if ($effSev -gt $prevSev) {
            # ESCALATION — always notify immediately, no cooldown
            $shouldNotify = $true
            $updateState  = $true
        } else {
            # RECOVERY — check cooldown timer
            $elapsed      = $now - $prevTime
            $cooldownSecs = $QUORUM_COOLDOWN * 60

            if (($QUORUM_COOLDOWN -le 0) -or ($prevTime -eq 0) -or ($elapsed -ge $cooldownSecs)) {
                $shouldNotify = $true
                $updateState  = $true
            }
            # If in cooldown: don't notify, don't update state.
            # Keeps "last notified" band so system doesn't silently oscillate.
        }
    }

    # --- Step 7: Fire alerts ---
    if ($shouldNotify -and ($effectiveBand -ne $prevBand)) {
        if ($effSev -gt $prevSev) {
            # Escalation alerts (getting worse)
            switch ($effectiveBand) {
                "critical" {
                    Alert-Red "💀 QUORUM LOST" "Only $reporting/$totalSlots oracles reporting. Need $consensusRequired for consensus. DigiDollar signing may be halted!"
                }
                "red" {
                    Alert-Red "🔴 Quorum At Edge" "Only $reporting/$totalSlots oracles reporting (need $consensusRequired). Network at risk if more drop."
                }
                "yellow" {
                    Alert-Yellow "⚠️ Quorum Getting Thin" "$reporting/$totalSlots oracles reporting (need $consensusRequired). Comfortable is ${QUORUM_GREEN}+."
                }
            }
        } else {
            # Recovery alerts (getting better)
            switch ($effectiveBand) {
                "green" {
                    Alert-Green "✅ Quorum Healthy" "$reporting/$totalSlots reporting — comfortable margin."
                }
                "yellow" {
                    Alert-Green "✅ Quorum Margin Improving" "$reporting/$totalSlots reporting — no longer at edge."
                }
                "red" {
                    Alert-Green "✅ Quorum Recovering" "Up to $reporting/$totalSlots reporting (need $consensusRequired). Still at edge, but improving."
                }
            }
        }
    }

    # --- Step 8: Update state file ---
    if ($updateState) {
        "$effectiveBand $now" | Set-Content -Path $stateFile -Encoding ASCII
    }

    # --- Step 9: Update Details for summary ---
    switch ($effectiveBand) {
        "critical" {
            $script:Details.Add("💀 Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — CRITICAL")
            $script:Issues++
        }
        "red" {
            $script:Details.Add("🔴 Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — at edge")
            $script:Issues++
        }
        "yellow" {
            $script:Details.Add("⚠️ Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — getting thin")
            $script:Warnings++
        }
        "green" {
            $script:Details.Add("✅ Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — healthy")
        }
    }
    $script:Details.Add("   MuSig2: $musigDetail")
}

# ============================================================================
# SUMMARY REPORT (-Summary and -DryRun)
# ============================================================================

function Send-Summary {
    if (-not (Check-Daemon)) { return }
    Check-Oracle
    Check-Chain
    Check-Peers
    Check-Price
    Check-Disk
    Check-Memory
    Check-Services
    Check-Version
    Check-Ntp
    Check-Quorum

    $color  = 65280  # green
    $status = "✅ All Systems Healthy"

    if ($script:Issues -gt 0) {
        $color  = 16711680  # red
        $status = "🔴 $($script:Issues) Issues Detected"
    } elseif ($script:Warnings -gt 0) {
        $color  = 16776960  # yellow
        $status = "⚠️ $($script:Warnings) Warnings"
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $uptimeStr = "unknown"
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $span = (Get-Date) - $boot
        $uptimeStr = "up $($span.Days) days, $($span.Hours) hours, $($span.Minutes) minutes"
    } catch { }

    $desc = ($script:Details -join "`n") + "`n⏱️ Uptime: $uptimeStr"

    if ($script:DRY_RUN -or [string]::IsNullOrEmpty($DISCORD_WEBHOOK)) {
        Write-Output "======================================="
        Write-Output " Oracle Health Summary — $(Get-Date)"
        Write-Output "======================================="
        Write-Output $desc
        Write-Output "======================================="
        return
    }

    $payload = @{
        embeds = @(
            @{
                title       = "$status — Oracle Health Summary"
                description = $desc
                color       = $color
                footer      = @{ text = "Oracle Monitor — $ORACLE_NAME (ID $ORACLE_ID)" }
                timestamp   = $timestamp
            }
        )
    } | ConvertTo-Json -Depth 5

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    try {
        Invoke-RestMethod -Uri $DISCORD_WEBHOOK -Method Post `
            -ContentType "application/json" -Body $bytes | Out-Null
    } catch { }
}

# ============================================================================
# MAIN — Normal health check (alerts only on problems/recovery)
# ============================================================================

function Invoke-Checks {
    if (-not (Check-Daemon)) { return }
    Check-Oracle
    Check-Chain
    Check-Peers
    Check-Price
    Check-Disk
    Check-Memory
    Check-Ntp
    Check-Quorum
}

# ============================================================================
# ENTRY POINT
# ============================================================================

if ($Test) {
    Write-Output "Testing Discord webhook..."
    if ([string]::IsNullOrEmpty($DISCORD_WEBHOOK)) {
        Write-Output "ERROR: DISCORD_WEBHOOK is not set."
        Write-Output "Configure it in: $CONFIG_FILE"
        exit 1
    }
    Alert-Blue "🔧 Test Alert" "Oracle monitor is configured and working! $(Get-Date)"
    Write-Output "Check your Discord channel."
} elseif ($Watch) {
    # Live console dashboard — full status block, refreshed in place.
    # Runs in dry-run mode internally: never sends Discord alerts and never
    # touches state files, so it's safe to leave this window open alongside
    # the scheduled Task Scheduler checks. Ctrl+C to exit.
    if ($RefreshSeconds -lt 5) { $RefreshSeconds = 5 }
    $script:DRY_RUN = $true
    while ($true) {
        Clear-Host
        Write-Host "🔭 Oracle Monitor — watch mode (refreshes every ${RefreshSeconds}s, Ctrl+C to exit)"
        $script:Issues   = 0
        $script:Warnings = 0
        $script:Details.Clear()
        Send-Summary
        Start-Sleep -Seconds $RefreshSeconds
    }
} elseif ($DryRun) {
    Send-Summary
} elseif ($Summary) {
    Send-Summary
} else {
    Invoke-Checks
}
