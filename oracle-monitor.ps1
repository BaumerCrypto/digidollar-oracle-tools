#Requires -Version 5.1
###############################################################################
# oracle-monitor.ps1 — DGB Oracle Health Monitor with Discord + Email Alerts (Windows)
# Version: 2.6.2-win.1
#
# Windows PowerShell port of my oracle-monitor.sh v2.6.2 (Linux). Same checks,
# same quorum state machine, same anti-flap logic, same DigiDollar BIP9
# pre-activation guard, same auto-detect for headless vs Qt wallet, same
# email-plus-Discord dual-channel alerts, same daily update check — all
# Windows-native commands. Runs on Windows PowerShell 5.1 (preinstalled on
# Windows 10/11) and PowerShell 7+. No jq needed — PowerShell parses JSON
# natively.
#
# Author: digibyte-maxi (Oracle ID 17) | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 — July 2026
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
#   3. Edit config.ps1: set your Discord webhook URL, oracle settings
#      (especially $CLI_PATH if digibyte-cli.exe is not on your PATH), and
#      (optionally) email settings — see the EMAIL section in the template.
#   4. Allow local scripts to run (one time, current user only):
#        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#   5. Test it:             .\oracle-monitor.ps1 -DryRun
#   6. Test webhook:        .\oracle-monitor.ps1 -Test
#   7. Test email (if enabled):  .\oracle-monitor.ps1 -TestEmail
#   8. Schedule it (run both from an elevated or normal prompt):
#        schtasks /Create /SC MINUTE /MO 5 /TN "OracleMonitor" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\YOUR_USER\OracleMonitor\oracle-monitor.ps1"
#        schtasks /Create /SC HOURLY /MO 12 /TN "OracleMonitorSummary" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\YOUR_USER\OracleMonitor\oracle-monitor.ps1 -Summary"
#      Then in Task Scheduler (taskschd.msc) open each task's Conditions tab
#      and untick "Start the task only if the computer is on AC power" if
#      this is a laptop. Your PC must be awake for the task to run.
#
# FLAGS:
#   (none)         Normal health check — alerts only on problems/recovery
#   -Summary       Full status summary — always sends to Discord + email
#   -DryRun        Runs all checks, prints to terminal, skips Discord + email, no state changes
#   -Watch         Live console dashboard — refreshes the full status every 60s
#                  (-Watch -RefreshSeconds 30 for 30s). Never alerts, never
#                  touches state: safe to leave a PowerShell window open with
#                  this running alongside the scheduled tasks.
#   -Test          Sends a test embed to Discord to verify webhook
#   -TestEmail     Sends a test email to verify SMTP settings
#   -Config /path  Use alternate config file (enables dual-instance monitoring)
#
# CHANGELOG:
#   v2.6.2-win.1 — Three operator-suggested fixes (two cosmetic, one
#            alert-logic). Matches Linux v2.6.2.
#            (1) VERSION LINE CLEANUP. Check-Version now strips the
#            bitcoin-legacy /Name:Version/ user-agent wrapper that
#            getnetworkinfo → .subversion returns. Line goes from
#            "ℹ️  /DigiByte:9.26.4/" to "ℹ️  DigiByte: v9.26.4" — the
#            slashes are meaningful to network peers but noise to
#            operators reading a health summary. Handles rc builds and
#            hash suffixes correctly (/DigiByte:9.26.0rc46/ →
#            DigiByte: v9.26.0rc46).
#            (2) EMAIL TIME LINE IN UTC. Time: line in email body now
#            uses UTC ((Get-Date).ToUniversalTime()) instead of the
#            Windows-local timezone (Get-Date zzz). Matches Discord
#            timestamp convention (UTC internally, client renders local).
#            No config change; automatic.
#            (3) SWAP ALERT NOW PRESSURE-GATED (caught by Aussie Epic on
#            Linux). A filled page file / swap is no longer treated as
#            memory pressure on its own — after a heavy transient the OS
#            can leave a lot parked in the page file long after the
#            pressure ended. Check-Swap now only raises the yellow alert
#            when RAM usage >= $SWAP_MEM_HEADROOM_PCT (Windows has no PSI,
#            so RAM headroom is the sole signal). A stale fill shows as an
#            ℹ️ line and no longer inflates the warning count. If RAM%
#            can't be measured it fails safe and alerts as v2.4 did. New
#            config: $SWAP_MEM_HEADROOM_PCT (default 70). Real pressure
#            still alerts exactly as before.
#   v2.6.1-win.1 — Cosmetic fix matching Linux v2.6.1 (caught by Aussie
#            Epic). ⚠️ (U+26A0 + VS16) and ℹ️ (U+2139 + VS16) render as
#            single-width text glyphs in most terminals — the VS16
#            selector requests emoji presentation but is honored
#            inconsistently — while ✅ 🔴 💀 render as double-width
#            emoji. Net effect in the health summary: every ⚠️/ℹ️
#            line's label sat one column left of the ✅/🔴 line labels,
#            giving the summary a subtle-but-persistent "some lines
#            look squished" appearance. Every ⚠️ and ℹ️ prefix now
#            carries a second space so all status lines line up at the
#            same column regardless of the terminal's emoji-width
#            handling. Applies to Details summary lines, alert titles,
#            and the top status header ("⚠️  N Warnings"). No logic
#            change; no alert path change — purely how the output
#            renders. In Discord and email the double-space is visually
#            harmless (both render these as full-width emoji so the
#            extra space reads as intentional padding). Also: the
#            update-available footer URL now includes the https://
#            scheme so email clients (including Outlook desktop and
#            corporate gateways that only linkify explicit-scheme URLs)
#            auto-linkify it universally. One-character change in
#            Build-Footer.
#   v2.6.0-win.1 — Two features, one release. Matches Linux v2.6.0 line by line.
#            (1) EMAIL NOTIFICATIONS (closes #17). New Send-Email fires
#            on the same triggers as Discord — red/yellow/green state
#            changes plus the 12-hour summary — via .NET's built-in
#            System.Net.Mail.SmtpClient (no external module needed;
#            ships in every PowerShell 5.1). Config-driven: $EMAIL_ENABLED,
#            $EMAIL_TO, $SMTP_SERVER, $SMTP_PORT, $SMTP_USER, $SMTP_PASS,
#            $SMTP_FROM. Port 587 = STARTTLS via EnableSsl (Gmail/Outlook/
#            Brevo default and the recommended setting for PS 5.1). Port
#            465 (implicit TLS) is not natively supported by .NET's
#            SmtpClient in PS 5.1 — use 587 instead. Gmail requires an
#            App Password (2FA -> App passwords), never the account
#            password. Subjects carry severity ([ALERT]/[WARNING]/
#            [RESOLVED]/[INFO]) and the $NETWORK_LABEL prefix (dual-
#            instance parity with v2.5.3-win.1 Discord titles, applied
#            at the Send-Email chokepoint). New -TestEmail flag verifies
#            SMTP settings with inline diagnostics for the common
#            failure modes. Backup channel if Discord is down; primary
#            channel for operators who don't use Discord/Slack/Telegram.
#            (2) UPDATE CHECK. New Check-ForUpdate fetches this script's
#            own published header from the GitHub main branch
#            (raw.githubusercontent.com), extracts the published
#            $SCRIPT_VERSION, and compares via [System.Version] on the
#            base (with -win.N suffix as a tie-breaker). When a newer
#            version exists, every Discord card and email gains a second
#            footer line: "⬆️ vX.Y.Z available — <repo url>". No new
#            repo files — the version source IS the shipped script
#            header, so it can never drift from what operators actually
#            download. $UPDATE_CHECK="yes" by default; silent on every
#            failure mode (no network, timeout, offline, parse failure
#            -> footer simply stays one line, monitor unaffected).
#            Result cached per-instance for $UPDATE_CHECK_TTL seconds
#            (default 86400 = one GitHub fetch per day per instance).
#            Never fetches and never writes cache in -DryRun.
#   v2.5.6-win.1 — Cosmetic fix matching Linux v2.5.6. The MuSig2
#          summary line now carries its own status icon (✅ complete,
#          ℹ️  in progress, ⚠️  parse failure) so it renders consistently
#          alongside the other health lines instead of floating with a
#          bare three-space indent. Redundant "✓" and "($state)" suffix
#          dropped since the icon carries that meaning. No behavior
#          change, no alert path change — purely how the line renders.
#   v2.5.5-win.1 — Disk check enhancements, matching Linux v2.5.5 (both
#          suggested by Aussie Epic). (1) The disk line now shows total
#          size and used% next to free space — "✅ Disk: 156GB free of
#          200GB (22% used, drive C:)". Get-PSDrive returns Free and Used
#          natively; total = Free + Used. (2) The Low Disk Space alert
#          now names your DigiByte datadir on its own line so you know
#          exactly where to clean up, via the new $DATADIR config
#          variable (default "$env:APPDATA\DigiByte"). No RPC returns
#          the datadir, so it's config-declared — dual-instance operators
#          set it per config, same pattern as $NETWORK_LABEL. The path
#          appears only in the red alert, never the green summary line.
#   v2.5.4-win.1 — Full-repo audit fixes (July 2026), matching Linux
#          v2.5.4. (1) $NETWORK_LABEL now declared in the defaults block
#          ("" = auto) so the script is StrictMode-safe and the defaults
#          list matches the config template. (2) Combined action flags
#          (e.g. -DryRun -Summary) are now rejected with a clear error —
#          previously one silently won — matching the bash ports, which
#          have always errored on combined flags. (3) -Test no longer
#          double-labels the card when $NETWORK_LABEL is set (the label
#          lives in the title only, added by Send-Discord).
#   v2.5.3-win.1 — Send-Discord now prefixes every individual alert title
#          with $NETWORK_LABEL (when set), not just the health summary and
#          -Test alert. Fixes dual-instance operators (testnet+mainnet on
#          one box) getting an unlabeled "Node Down" card with no way to
#          tell which daemon fired it. Single chokepoint — every Alert-Red/
#          Yellow/Green/Blue call routes through Send-Discord(). No-op for
#          single-instance operators without $NETWORK_LABEL set. Ports the
#          fix shipped in oracle-monitor.sh v2.5.3.
#   v2.5.2-win.1 — Check-Daemon() now auto-detects either digibyted
#          (headless) or digibyte-qt (Qt wallet). Prefers headless first,
#          falls back to Qt via a candidate loop. Sets $script:DetectedDaemon
#          global so Check-Services() can branch: the Windows Service check
#          is skipped with an INFO line when the Qt wallet is the running
#          daemon (Qt operators typically run outside NSSM/service wrappers).
#          Optional $DAEMON_PROCESS config override pins monitoring to a
#          specific process name. Full parity with Linux v2.5.2.
#   v2.5.1-win.1 — Add $SCRIPT_VERSION constant + $NETWORK_LABEL in the
#          Discord card titles, dry-run header, watch header, and -Test
#          output. Tune default quorum bands from 20/12 -> 12/10 (v2.0
#          defaults fired yellow at 15/35 fresh — 2x the hard 7-of-35
#          floor). Quorum counting stays on heartbeat_status=="fresh"
#          from v2.2.
#   v2.5-win.1 — DigiDollar BIP9 pre-activation guard. New
#          Check-DigidollarActive() sets $script:DdStatus / $script:DdActive
#          globals via getdigidollardeploymentinfo, called first in both
#          Invoke-Checks and Send-Summary (-DryRun / -Summary / -Watch all
#          route through Send-Summary, so the pre-flight lives in both
#          paths). Check-Oracle, Check-Price, Check-Services, Check-Quorum
#          all downgrade "no data" to standby INFO instead of red while
#          $DdActive=false. Check-Version now reads getnetworkinfo ->
#          .subversion via RPC instead of `digibyted --version` (which
#          failed for Qt-wallet operators with no digibyted.exe on PATH).
#   v2.4-win.1 — Add swap pressure detection (Check #12). Fires a yellow
#          alert when page-file usage exceeds $SWAP_THRESHOLD_MB (default
#          100 MB). Uses Get-CimInstance Win32_PageFileUsage for the read.
#          On Windows with a healthy amount of RAM, sustained page-file
#          use signals real memory pressure. (fixes #26 on Windows,
#          suggested by shenger)
#   v2.3-win.1 — Add -Config /path parameter for dual-instance monitoring.
#          Two scheduled tasks + two config files = independent testnet and
#          mainnet monitoring from one PC. State files auto-separate per
#          config directory via Split-Path -Parent.
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
#   v2.6.1 — cosmetic spacing fix           v2.6.0 — email + update-check (#17)
#   v2.5.6 — MuSig2 status icon             v2.5.5 — disk total+used% + DATADIR
#   v2.5.4 — full-repo audit fixes          v2.5.3 — NETWORK_LABEL chokepoint
#   v2.5.2 — headless/Qt auto-detect        v2.5.1 — version + label + footer
#   v2.5 — DD BIP9 guard (#27)              v2.4 — swap pressure (#26)
#   v2.3 — --config dual-instance (#23)     v2.2 — heartbeat_status quorum
#   v2.1.1 — hysteresis fix                 v2.1 — anti-flap
#   v2.0 — quorum margin (#6)               v1.5 — listoracle RPC (#22)
#   v1.4 — warning/error enum (#21)         v1.3 — RC44 status enum
#   v1.2 — config file, dry-run             v1.1 — degraded consensus, NTP
#   v1.0 — initial release
###############################################################################

param(
    [switch]$Summary,
    [switch]$DryRun,
    [switch]$Test,
    [switch]$TestEmail,
    [switch]$Watch,
    [int]$RefreshSeconds = 60,
    [string]$Config = ""
)

$SCRIPT_VERSION = "2.6.2-win.1"

# v2.5.4-win.1: reject combined action flags (parity with the bash ports,
# which error on e.g. --dry-run --summary; previously one silently won).
# v2.6.0-win.1: -TestEmail joins the set.
$__actionFlags = @($Summary, $DryRun, $Test, $TestEmail, $Watch) | Where-Object { $_ }
if (@($__actionFlags).Count -gt 1) {
    Write-Output "ERROR: Use only one of -Summary, -DryRun, -Test, -TestEmail, -Watch."
    exit 1
}

# ============================================================================
# RUNTIME ENVIRONMENT
# ============================================================================

# Discord requires TLS 1.2+. Windows PowerShell 5.1 on older builds defaults
# to TLS 1.0 and the webhook POST fails silently without this line.
# The SMTP send in v2.6.0-win.1 shares the same requirement — Brevo/Gmail
# reject STARTTLS handshakes below TLS 1.2.
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

# Email notifications (v2.6.0-win.1) — set $EMAIL_ENABLED=$true in the
# config to activate. Fires on the same triggers as Discord. Uses .NET's
# built-in System.Net.Mail.SmtpClient — nothing extra to install. See
# config.template.ps1 for Gmail App Password setup and other providers.
# Port 587 (STARTTLS) is the recommended and default setting on Windows —
# .NET's SmtpClient in PS 5.1 does not natively support port 465
# (implicit TLS). Brevo, Gmail, Outlook all default to 587.
$EMAIL_ENABLED = $false
$EMAIL_TO      = ""                      # Recipient address
$SMTP_SERVER   = "smtp.gmail.com"
$SMTP_PORT     = 587                     # 587 = STARTTLS (only supported mode on PS 5.1)
$SMTP_USER     = ""                      # SMTP login (usually your full email address)
$SMTP_PASS     = ""                      # Gmail: 16-char App Password — NOT your account password
$SMTP_FROM     = ""                      # "Display Name <you@example.com>" — empty = use SMTP_USER

# Update check (v2.6.0-win.1) — compares this script's version against
# the copy published on GitHub main once per $UPDATE_CHECK_TTL seconds.
# When a newer version exists, Discord cards and emails gain a second
# footer line. Silent on any failure. Set $UPDATE_CHECK="no" to disable.
$UPDATE_CHECK     = "yes"
$UPDATE_CHECK_URL = "https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor.ps1"
$UPDATE_CHECK_TTL = 86400

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

# v2.5.2: Node process name (WITHOUT .exe).
# The monitor auto-detects either "digibyted" (headless) or "digibyte-qt"
# (Qt GUI wallet). Leave this empty (default) for auto-detect. Set it to
# force a specific match only if you run BOTH binaries on the same PC:
#   $DAEMON_PROCESS = "digibyted"     # headless daemon
#   $DAEMON_PROCESS = "digibyte-qt"   # Qt wallet
$DAEMON_PROCESS = ""

# Optional: if you run digibyted as a Windows service (e.g. via NSSM),
# put the service name here and the summary will report its status.
# Leave "" to skip the service check. Ignored automatically when the Qt
# wallet is the detected daemon (v2.5.2+).
$SERVICE_NAME = ""

# Network label shown in Discord card titles (v2.5.1+). Leave "" for no
# label; set e.g. "Testnet26" or "Mainnet" for dual-instance setups.
# (Declared here since v2.5.4-win.1 so the defaults block is complete
# and the script runs clean under Set-StrictMode.)
$NETWORK_LABEL = ""

# Drive letter to watch for free disk space (where your DigiByte datadir
# lives — datadir default is %APPDATA%\DigiByte on drive C).
$DISK_DRIVE = "C"

# DigiByte datadir named in the Low Disk Space alert (v2.5.5-win.1) so
# the operator knows exactly where to clean up. Display-only — the
# monitor never reads or deletes anything here. Keep it on the same
# drive as $DISK_DRIVE. Dual-instance operators should set it per
# config file (see config.template.ps1) so each instance's alert names
# its own datadir. (Declared here so the defaults block is complete and
# the script runs clean under Set-StrictMode.)
$DATADIR = "$env:APPDATA\DigiByte"

# Thresholds — basic health
$MIN_PEERS           = 3
$MIN_DISK_GB         = 5
$STALE_PRICE_MINUTES = 30    # Reserved for future use — staleness currently from RPC
$MEM_THRESHOLD       = 90
$SWAP_THRESHOLD_MB   = 100   # v2.4 — page-file usage MB threshold
# v2.6.2-win.1 — Page-file fill is only real pressure when RAM is tight.
# A filled page file can be a stale leftover from a past heavy event.
# Only alert when RAM usage is at/above this %. Windows has no PSI, so
# RAM headroom is the sole pressure signal; if it can't be measured the
# monitor fails safe and alerts.
$SWAP_MEM_HEADROOM_PCT = 70
$MAX_CHAIN_BEHIND    = 10

# NTP check — measures actual clock offset against a time server using
# w32tm /stripchart (locale-independent, works even if the Windows Time
# service is stopped). Oracle bundles are rejected past 3600s skew, so
# keep this tight.
$NTP_SERVER             = "time.windows.com"
$NTP_MAX_OFFSET_SECONDS = 1.0

# Thresholds — quorum margin (v2.0, tuned in v2.5.1)
# These define the alert bands for network-wide oracle liveness.
# Quorum threshold (oracle_consensus_required) comes from the chain via
# getdigidollardeploymentinfo — not hardcoded here.
#
# QUORUM_GREEN: at or above this count = comfortable, no alerts
# QUORUM_YELLOW: at or above this but below green = "getting thin" warning
# Below QUORUM_YELLOW but at/above consensus_required = red, at quorum edge
# Below consensus_required = CRITICAL — DD bundle signing may halt
#
# Defaults (v2.5.1): 12/10 for mainnet (35-slot roster, 7-of-35 quorum).
# The old 20/12 defaults produced yellow at 15/35 fresh — more than 2x
# the hard 7-of-35 floor — which conditioned operators to ignore the
# check. Override for testnet: GREEN=10, YELLOW=8.
$QUORUM_GREEN  = 12
$QUORUM_YELLOW = 10

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

# v2.3: -Config /path parameter overrides the default location.
# State dir is derived from Split-Path so per-instance state auto-separates.
if (-not [string]::IsNullOrEmpty($Config)) {
    if (-not (Test-Path $Config)) {
        Write-Output "ERROR: Config file not found: $Config"
        exit 1
    }
    $CONFIG_FILE = $Config
} else {
    $CONFIG_FILE = Join-Path $env:USERPROFILE ".oracle-monitor\config.ps1"
}

$STATE_DIR = Split-Path -Parent $CONFIG_FILE

if (Test-Path $CONFIG_FILE) {
    . $CONFIG_FILE
}

New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null

# Runtime flag — set by -DryRun
$script:DRY_RUN = [bool]$DryRun

# ============================================================================
# UPDATE CHECK (v2.6.0-win.1)
# ============================================================================
# Fetches the published script header from GitHub main and compares
# $SCRIPT_VERSION. The version source is the shipped file itself — no
# separate VERSION file to drift. Cached per instance ($STATE_DIR) for
# $UPDATE_CHECK_TTL seconds. Memoized per run. Every failure mode is
# silent: the footer just stays one line and the monitor is unaffected.
# Never called in -DryRun (callers sit inside Build-Footer, which is
# only reached from Send-Discord / Send-Email / Send-Summary in non-dry-
# run paths), so dry-run never fetches and never writes the cache file.

$script:UpdateAvailable = ""
$script:UpdateChecked   = $false

function Check-ForUpdate {
    if ($script:UpdateChecked) { return }
    $script:UpdateChecked = $true
    if ("$UPDATE_CHECK" -ne "yes") { return }

    $cacheFile = Join-Path $STATE_DIR "update_check_cache"
    $now       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $remoteVer = ""
    $cachedTs  = $null
    $ttl       = if ($UPDATE_CHECK_TTL) { [long]$UPDATE_CHECK_TTL } else { 86400 }

    # Serve from cache while fresh (line 1 = epoch of last attempt,
    # line 2 = version found, empty on a failed fetch)
    if (Test-Path $cacheFile) {
        try {
            $lines = @(Get-Content $cacheFile -ErrorAction SilentlyContinue)
            $parsed = [long]0
            if ($lines.Count -ge 1 -and [long]::TryParse("$($lines[0])".Trim(), [ref]$parsed)) {
                $cachedTs = $parsed
                if (($now - $cachedTs) -lt $ttl) {
                    if ($lines.Count -ge 2) {
                        $remoteVer = "$($lines[1])".Trim()
                    }
                }
            }
        } catch { }
    }

    # Cache miss or expired — fetch the published header (5s cap so a
    # GitHub outage can't stall a scheduled run). Cache the attempt
    # either way: a failed fetch caches empty, which stays silent and
    # defers the retry to the next TTL window instead of hammering on
    # failure.
    $needFetch = $true
    if ($null -ne $cachedTs -and ($now - $cachedTs) -lt $ttl) {
        $needFetch = $false
    }

    if ($needFetch) {
        try {
            $resp = Invoke-WebRequest -Uri $UPDATE_CHECK_URL -TimeoutSec 5 `
                -UseBasicParsing -ErrorAction Stop
            $lines = @($resp.Content -split "`r?`n")
            foreach ($line in $lines) {
                if ($line -match '^\s*\$SCRIPT_VERSION\s*=\s*"([^"]+)"') {
                    $remoteVer = $Matches[1]
                    break
                }
            }
        } catch {
            $remoteVer = ""
        }

        try {
            "$now`n$remoteVer" | Set-Content -Path $cacheFile -Encoding ASCII -ErrorAction SilentlyContinue
        } catch { }
    }

    # Newer only. Version strings look like "2.6.0-win.1". Split off the
    # -win.N suffix; compare the numeric base with [System.Version], then
    # use the suffix as a tie-breaker. Running a dev version ahead of
    # the published one correctly stays silent.
    if (-not [string]::IsNullOrEmpty($remoteVer) -and $remoteVer -ne $SCRIPT_VERSION) {
        $localBase  = ($SCRIPT_VERSION -replace '-.*$', '')
        $remoteBase = ($remoteVer -replace '-.*$', '')
        $localSuffix  = 0
        $remoteSuffix = 0
        if ($SCRIPT_VERSION -match '-win\.(\d+)$') { $localSuffix  = [int]$Matches[1] }
        if ($remoteVer     -match '-win\.(\d+)$') { $remoteSuffix = [int]$Matches[1] }

        $newer = $false
        try {
            $lv = [System.Version]$localBase
            $rv = [System.Version]$remoteBase
            if ($rv -gt $lv) {
                $newer = $true
            } elseif ($rv -eq $lv -and $remoteSuffix -gt $localSuffix) {
                $newer = $true
            }
        } catch {
            # Version parse failed — fall back to plain string compare
            if ($remoteVer -gt $SCRIPT_VERSION) { $newer = $true }
        }

        if ($newer) { $script:UpdateAvailable = $remoteVer }
    }
}

# Footer for Discord cards and emails — one line normally, two when an
# update is available. Single chokepoint so every card and email agrees.
function Build-Footer {
    Check-ForUpdate
    $footer = "Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)"
    if (-not [string]::IsNullOrEmpty($script:UpdateAvailable)) {
        $footer = "$footer`n⬆️ v$($script:UpdateAvailable) available — https://github.com/BaumerCrypto/digidollar-oracle-tools"
    }
    return $footer
}

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
# NOTIFICATION FUNCTIONS — DISCORD + EMAIL
# ============================================================================

function Send-Discord {
    param(
        [int]$Color,      # red=16711680, green=65280, yellow=16776960, blue=3447003
        [string]$Title,
        [string]$Message
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # v2.5.3-win.1: prefix every individual alert title with NETWORK_LABEL
    # (when set) so dual-instance operators (e.g. testnet + mainnet on one
    # box) can tell which daemon fired the alert from the Discord card title
    # alone. Single chokepoint — every Alert-Red/Yellow/Green/Blue call routes
    # through here. No-op for single-instance operators without NETWORK_LABEL
    # set. Ports the same fix shipped in oracle-monitor.sh v2.5.3.
    if (-not [string]::IsNullOrEmpty($NETWORK_LABEL)) {
        $Title = "$NETWORK_LABEL — $Title"
    }

    if ($script:DRY_RUN -or [string]::IsNullOrEmpty($DISCORD_WEBHOOK)) {
        # Write-Host, not Write-Output: this function is called inside checks
        # whose return values are consumed (Check-Daemon). Write-Output here
        # would pollute those return values; Write-Host goes straight to the
        # console and leaves the output stream clean.
        Write-Host "[$(Get-Date)] ALERT: $Title — $Message"
        return
    }

    # v2.6.0-win.1: footer via Build-Footer — gains a second line when a
    # newer published version exists.
    $payload = @{
        embeds = @(
            @{
                title       = $Title
                description = $Message
                color       = $Color
                footer      = @{ text = (Build-Footer) }
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

# ----------------------------------------------------------------------------
# Send-Email (v2.6.0-win.1, closes #17) — plain-text email via .NET's
# System.Net.Mail.SmtpClient (no external module needed; ships in every
# PS 5.1). Same triggers as Discord. Port 587 STARTTLS is the only
# reliably supported mode in PS 5.1 — .NET's SmtpClient does not natively
# handle port 465 (implicit TLS). Brevo, Gmail, Outlook all default to 587.
# NETWORK_LABEL prefixes the subject at this single chokepoint, matching
# the v2.5.3-win.1 Discord title pattern, so dual-instance operators can
# tell which daemon fired the email from the subject line alone.
# Returns $true on success, $false on failure (used by -TestEmail).
# ----------------------------------------------------------------------------

function Send-Email {
    param(
        [string]$Subject,
        [string]$Body
    )

    # $EMAIL_ENABLED may be either the boolean $true or the string "true"
    # (both are valid PowerShell truthy in the config file; the bash
    # parity check accepts either).
    if (-not ($EMAIL_ENABLED -eq $true -or "$EMAIL_ENABLED" -eq "true")) {
        return $false
    }

    # v2.5.3-win.1 parity: label the subject for dual-instance operators
    if (-not [string]::IsNullOrEmpty($NETWORK_LABEL)) {
        $Subject = "$NETWORK_LABEL — $Subject"
    }

    if ($script:DRY_RUN) {
        $toDisplay = if ([string]::IsNullOrEmpty($EMAIL_TO)) { "<not set>" } else { $EMAIL_TO }
        Write-Host "[$(Get-Date)] EMAIL would send to ${toDisplay}: $Subject"
        return $true
    }

    # Essential fields — silently skip if not configured (mirrors the
    # empty-DISCORD_WEBHOOK behavior; -TestEmail diagnoses loudly)
    if ([string]::IsNullOrEmpty($EMAIL_TO) -or `
        [string]::IsNullOrEmpty($SMTP_USER) -or `
        [string]::IsNullOrEmpty($SMTP_PASS)) {
        return $false
    }

    # Resolve display From. Handles both "Display Name <addr>" and bare
    # "addr" formats; System.Net.Mail.MailAddress parses either.
    $fromDisplay = if ([string]::IsNullOrEmpty($SMTP_FROM)) { "Oracle Monitor <$SMTP_USER>" } else { $SMTP_FROM }

    # Body: alert text + timestamp + the same footer the Discord cards
    # carry (including the update line when one is available)
    $fullBody = "${Body}`n`nTime: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC`n$(Build-Footer)"

    $mail = $null
    $smtp = $null
    $ok   = $false
    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = New-Object System.Net.Mail.MailAddress($fromDisplay)
        $mail.To.Add($EMAIL_TO) | Out-Null
        $mail.Subject         = $Subject
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mail.Body            = $fullBody
        $mail.BodyEncoding    = [System.Text.Encoding]::UTF8
        $mail.IsBodyHtml      = $false

        $smtp = New-Object System.Net.Mail.SmtpClient($SMTP_SERVER, [int]$SMTP_PORT)
        $smtp.EnableSsl   = $true      # STARTTLS on 587 (Brevo/Gmail/Outlook)
        $smtp.Credentials = New-Object System.Net.NetworkCredential($SMTP_USER, $SMTP_PASS)
        $smtp.Timeout     = 30000      # 30s, matches Linux curl --max-time 30

        $smtp.Send($mail)
        $ok = $true
    } catch {
        $ok = $false
    } finally {
        if ($null -ne $mail) { $mail.Dispose() }
        if ($null -ne $smtp) { $smtp.Dispose() }
    }
    return $ok
}

# v2.6.0-win.1: each wrapper fires both channels on the same event. Email
# subjects carry the severity so inbox scanning works without opening.
# Return values suppressed via Out-Null so callers that consume return
# values (Check-Daemon) don't see the boolean from Send-Email.
function Alert-Red    { param($t, $m)
    Send-Discord -Color 16711680 -Title $t -Message $m
    Send-Email -Subject "[ALERT] $t" -Body $m | Out-Null
}
function Alert-Yellow { param($t, $m)
    Send-Discord -Color 16776960 -Title $t -Message $m
    Send-Email -Subject "[WARNING] $t" -Body $m | Out-Null
}
function Alert-Green  { param($t, $m)
    Send-Discord -Color 65280 -Title $t -Message $m
    Send-Email -Subject "[RESOLVED] $t" -Body $m | Out-Null
}
function Alert-Blue   { param($t, $m)
    Send-Discord -Color 3447003 -Title $t -Message $m
    Send-Email -Subject "[INFO] $t" -Body $m | Out-Null
}

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

# --- Check 1: Is digibyted (or digibyte-qt) running? ---
# v2.5.2: Auto-detects either the headless daemon or the Qt GUI wallet.
# $DAEMON_PROCESS can be set in config to force a specific match. Default
# order: digibyted first, then digibyte-qt. Sets the $script:DetectedDaemon
# global so Check-Services() can branch — the Qt wallet typically runs
# outside NSSM/service wrappers, so the Windows Service check is skipped
# with an INFO line when Qt is the detected daemon.
function Check-Daemon {
    $script:DetectedDaemon = $null

    if (-not [string]::IsNullOrEmpty($DAEMON_PROCESS)) {
        # Explicit override from config
        $procName = $DAEMON_PROCESS -replace '\.exe$', ''
        if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
            $script:DetectedDaemon = $procName
        }
    } else {
        # Auto-detect: headless daemon first, then Qt wallet
        foreach ($candidate in @("digibyted", "digibyte-qt")) {
            if (Get-Process -Name $candidate -ErrorAction SilentlyContinue) {
                $script:DetectedDaemon = $candidate
                break
            }
        }
    }

    if ($null -ne $script:DetectedDaemon) {
        if (Clear-AlertState "daemon_down") {
            Alert-Green "✅ Node Recovered" "$($script:DetectedDaemon) is running again."
        }
        $script:Details.Add("✅ Node: $($script:DetectedDaemon) running")
        return $true
    } else {
        if (Test-ShouldAlert "daemon_down") {
            Alert-Red "🔴 Node Down" "Neither digibyted nor digibyte-qt is running! For headless: restart your service or launch digibyted.exe. For Qt: launch the DigiByte wallet."
        }
        $script:Details.Add("🔴 Node: NOT RUNNING (checked digibyted, digibyte-qt)")
        $script:Issues++
        return $false  # skip remaining checks
    }
}

# --- Check 2: Is the oracle running and signing? ---
function Check-Oracle {
    $raw = Invoke-DGBCli -RpcArgs @("listoracle") -UseWallet

    if ([string]::IsNullOrEmpty($raw)) {
        if ($script:DdActive -eq $false) {
            $script:Details.Add("ℹ️  Oracle: standby (DigiDollar deployment: $($script:DdStatus))")
            return
        }
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
        $script:Details.Add("⚠️  Chain: could not query")
        $script:Warnings++
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }
    if ($null -eq $info) {
        $script:Details.Add("⚠️  Chain: could not query")
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
            Alert-Yellow "⚠️  Chain Behind" "Node is $behind blocks behind (block $blocks / header $headers)."
        }
        $script:Details.Add("⚠️  Chain: $behind blocks behind ($blocks / $headers)")
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
        $script:Details.Add("⚠️  Peers: could not query")
        $script:Warnings++
        return
    }

    $peerCount = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$peerCount)) {
        $script:Details.Add("⚠️  Peers: could not query")
        $script:Warnings++
        return
    }

    if ($peerCount -lt $MIN_PEERS) {
        if (Test-ShouldAlert "low_peers") {
            Alert-Yellow "⚠️  Low Peers" "Only $peerCount peers connected (minimum: $MIN_PEERS)."
        }
        $script:Details.Add("⚠️  Peers: $peerCount (low!)")
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
        if ($script:DdActive -eq $false) {
            $script:Details.Add("ℹ️  Price: pending (DigiDollar deployment: $($script:DdStatus))")
            return
        }
        $script:Details.Add("⚠️  Price: could not query")
        $script:Warnings++
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }
    if ($null -eq $info) {
        $script:Details.Add("⚠️  Price: could not query")
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
            Alert-Yellow "⚠️  Stale Price" "Oracle consensus price is stale. Last price: `$$priceUsd"
        }
        $script:Details.Add("⚠️  Price: STALE — `$$priceUsd")
        $script:Warnings++
    # Check 5b: Error status — real problem, alert operator (v1.4)
    } elseif ($status -eq "error") {
        if (Test-ShouldAlert "degraded_consensus") {
            Alert-Yellow "⚠️  Degraded Consensus" "Network status: $status | Price: `$$priceUsd | Oracles: $oracleCount. Network aggregation is failing."
        }
        $script:Details.Add("⚠️  Price: `$$priceUsd (status: $status, oracles: $oracleCount)")
        $script:Warnings++
    # Check 5c: Warning status — network notice, no Discord alert (v1.4)
    } elseif ($status -eq "warning") {
        $script:Details.Add("⚠️  Price: `$$priceUsd (status: $status, oracles: $oracleCount)")
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
        $script:Details.Add("⚠️  Disk: could not query drive $DISK_DRIVE")
        $script:Warnings++
        return
    }

    $availGB = [math]::Floor($drive.Free / 1GB)

    # v2.5.5-win.1: Get-PSDrive returns Free and Used natively —
    # total = Free + Used. Show total and used% next to free space.
    # used% is computed from the same rounded GB integers that are
    # displayed, so the numbers in the line are self-consistent.
    $totalGB  = [math]::Floor(($drive.Free + $drive.Used) / 1GB)
    $sizeInfo = ""
    if ($null -ne $drive.Used -and $totalGB -gt 0) {
        $usedPct  = [math]::Floor((($totalGB - $availGB) * 100) / $totalGB)
        $sizeInfo = " of ${totalGB}GB (${usedPct}% used)"
    }

    if ($availGB -lt $MIN_DISK_GB) {
        if (Test-ShouldAlert "low_disk") {
            # v2.5.5-win.1: three-line alert with hard newlines (`n) —
            # mobile Discord clients soft-wrap unpredictably without
            # explicit breaks. The datadir sits on its own line as a
            # clean copy target. Wording is generic ("old logs or unused
            # chain data") because this alert fires on mainnet too.
            $datadirLine = $DATADIR.TrimEnd('\') + '\'
            Alert-Red "🔴 Low Disk Space" "Only ${availGB}GB free${sizeInfo}.`nClean up old logs or unused chain data in:`n${datadirLine}"
        }
        $script:Details.Add("🔴 Disk: ${availGB}GB free${sizeInfo} (LOW!)")
        $script:Issues++
    } else {
        if (Clear-AlertState "low_disk") {
            Alert-Green "✅ Disk Space Recovered" "Disk space back to ${availGB}GB free${sizeInfo}."
        }
        # Summary line keeps the drive letter the Windows version has
        # always shown, folded into the same parens as used%.
        if ($sizeInfo -ne "") {
            $script:Details.Add("✅ Disk: ${availGB}GB free of ${totalGB}GB (${usedPct}% used, drive ${DISK_DRIVE}:)")
        } else {
            $script:Details.Add("✅ Disk: ${availGB}GB free (drive ${DISK_DRIVE}:)")
        }
    }
}

# --- Check 7: Memory usage ---
function Check-Memory {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

    if ($null -eq $os -or -not $os.TotalVisibleMemorySize) {
        $script:Details.Add("⚠️  Memory: could not query")
        $script:Warnings++
        return
    }

    $memPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)

    if ($memPct -gt $MEM_THRESHOLD) {
        if (Test-ShouldAlert "high_memory") {
            Alert-Yellow "⚠️  High Memory" "Memory usage at ${memPct}%."
        }
        $script:Details.Add("⚠️  Memory: ${memPct}% used")
        $script:Warnings++
    } else {
        Clear-AlertState "high_memory" | Out-Null
        $script:Details.Add("✅ Memory: ${memPct}% used")
    }
}

# --- Check 12: Swap pressure (v2.4; pressure-gated in v2.6.2) ---
# v2.4 fired a yellow alert whenever page-file usage exceeded
# $SWAP_THRESHOLD_MB. v2.6.2 fixes a false positive Aussie Epic hit on
# Linux: a filled page file / swap is NOT the same as memory pressure.
# After a heavy transient the OS can leave a lot parked in the page file
# long after the pressure ended — stale, not a live problem. When the
# page file is filled we now gate the alert on *current* pressure via RAM
# headroom: only alert when RAM usage >= $SWAP_MEM_HEADROOM_PCT. Windows
# has no PSI (the Linux stall meter), so RAM headroom is the sole signal;
# if it can't be measured we fail safe and alert as v2.4 did.
# Uses Get-CimInstance Win32_PageFileUsage which reports CurrentUsage
# and AllocatedBaseSize in MB. Sums across multiple page files if the
# system has more than one (unusual but supported).
function Check-Swap {
    $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue

    if ($null -eq $pf) {
        # No page file configured, or CIM query failed. Windows without a
        # page file is rare but valid — skip with an INFO line.
        $script:Details.Add("ℹ️  Swap: not configured (or Win32_PageFileUsage unavailable)")
        return
    }

    # Sum across all page files (in case there are multiple)
    $swapUsedMb  = 0
    $swapTotalMb = 0
    foreach ($p in @($pf)) {
        if ($null -ne $p.CurrentUsage)        { $swapUsedMb  += [int]$p.CurrentUsage }
        if ($null -ne $p.AllocatedBaseSize)   { $swapTotalMb += [int]$p.AllocatedBaseSize }
    }

    if ($swapTotalMb -eq 0) {
        $script:Details.Add("ℹ️  Swap: not configured")
        return
    }

    # Page-file use at/below threshold — definitively fine. Clear any prior alert.
    if ($swapUsedMb -le $SWAP_THRESHOLD_MB) {
        if (Clear-AlertState "swap_pressure") {
            Alert-Green "✅ Swap Pressure Cleared" "Page file usage back to ${swapUsedMb}MB of ${swapTotalMb}MB."
        }
        $script:Details.Add("✅ Swap: ${swapUsedMb}MB / ${swapTotalMb}MB")
        return
    }

    # Page file is filled. Gate on real current pressure via RAM headroom
    # (same RAM% method as Check-Memory).
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $memPct = $null
    if ($null -ne $os -and $os.TotalVisibleMemorySize) {
        $memPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)
    }

    $pressure   = $false
    $haveSignal = $false
    $reason     = ""
    $staleNote  = ""
    if ($null -ne $memPct) {
        $haveSignal = $true
        $staleNote  = "RAM ${memPct}%"
        if ($memPct -ge $SWAP_MEM_HEADROOM_PCT) {
            $pressure = $true
            $reason   = "RAM ${memPct}%"
        }
    }

    if ($pressure) {
        if (Test-ShouldAlert "swap_pressure") {
            Alert-Yellow "⚠️  Swap Pressure" "Page file usage: ${swapUsedMb}MB of ${swapTotalMb}MB with active memory pressure (${reason}). Check running processes."
        }
        $script:Details.Add("⚠️  Swap: ${swapUsedMb}MB / ${swapTotalMb}MB used (pressure! — ${reason})")
        $script:Warnings++
    } elseif (-not $haveSignal) {
        # RAM% unmeasurable — fail safe, alert as v2.4 did.
        if (Test-ShouldAlert "swap_pressure") {
            Alert-Yellow "⚠️  Swap Pressure" "Page file usage: ${swapUsedMb}MB of ${swapTotalMb}MB (pressure signal unavailable). Check running processes."
        }
        $script:Details.Add("⚠️  Swap: ${swapUsedMb}MB / ${swapTotalMb}MB used (filled; pressure unverifiable)")
        $script:Warnings++
    } else {
        # Filled but stale — no active pressure. Clear any prior alert.
        if (Clear-AlertState "swap_pressure") {
            Alert-Green "✅ Swap Pressure Cleared" "Page file still at ${swapUsedMb}MB of ${swapTotalMb}MB but no active pressure (${staleNote}). Likely a stale fill from a past heavy job."
        }
        $script:Details.Add("ℹ️  Swap: ${swapUsedMb}MB / ${swapTotalMb}MB used (stale — ${staleNote})")
    }
}

# --- Check 8: Service status (summary only) ---
# Windows has no systemd.
# v2.5.2: Skips Windows Service check with an INFO line when the Qt wallet
#         is the detected daemon — Qt operators typically run outside
#         NSSM/service wrappers, so a "not found" red would be misleading.
# v2.5:   Adds DD_ACTIVE guard for oracle process (standby → INFO not warn).
function Check-Services {
    # v2.5.2: Qt-skip
    if ($script:DetectedDaemon -eq "digibyte-qt") {
        $script:Details.Add("ℹ️  Service: n/a — Qt wallet is the running daemon")
    } elseif (-not [string]::IsNullOrEmpty($SERVICE_NAME)) {
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
        # No service name set — stand in with the process check
        if ($null -ne $script:DetectedDaemon) {
            $script:Details.Add("✅ $($script:DetectedDaemon) process: running")
        } else {
            $script:Details.Add("🔴 DigiByte node process: not running")
            $script:Issues++
        }
    }

    if ($script:DdActive -eq $false) {
        $script:Details.Add("ℹ️  Oracle process: standby (DigiDollar deployment: $($script:DdStatus))")
        return
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
        $script:Details.Add("⚠️  Oracle process: $oracleStatus")
        $script:Warnings++
    }
}

# --- Check 9: Node version (summary only) ---
# v2.5: Read version via RPC (getnetworkinfo → .subversion). The old
# approach probed `digibyted --version` from a candidate path list, which
# failed entirely for Qt-wallet operators (no digibyted.exe present) and
# picked the wrong binary in dual-daemon setups. RPC always reports what's
# actually running and works identically for Qt and headless.
function Check-Version {
    $verLine = $null
    $raw = Invoke-DGBCli -RpcArgs @("getnetworkinfo")
    if (-not [string]::IsNullOrEmpty($raw)) {
        try {
            $info = $raw | ConvertFrom-Json
            if ($null -ne $info.PSObject.Properties['subversion']) {
                $verLine = $info.subversion
            }
        } catch { }
    }

    if (-not [string]::IsNullOrEmpty($verLine)) {
        # v2.6.2-win.1: strip bitcoin-legacy /Name:Version/ user-agent wrapper.
        # /DigiByte:9.26.4/ -> DigiByte: v9.26.4. The slashes are meaningful
        # to network peers but noise to operators reading a health summary.
        if ($verLine -match '^/([^:]+):(.+)/$') {
            $verLine = "$($Matches[1]): v$($Matches[2])"
        }
        $script:Details.Add("ℹ️  $verLine")
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
        $script:Details.Add("⚠️  NTP: could not verify (w32tm query failed)")
        $script:Warnings++
        return
    }

    $absOffset = [math]::Abs($offset)

    if ($absOffset -gt $NTP_MAX_OFFSET_SECONDS) {
        if (Test-ShouldAlert "ntp_desync") {
            Alert-Yellow "⚠️  NTP Desync" "System clock is off by $([math]::Round($offset, 3))s vs $NTP_SERVER. Oracle timestamps may drift. Run: w32tm /resync (elevated prompt)."
        }
        $script:Details.Add("⚠️  NTP: offset $([math]::Round($offset, 3))s (NOT synchronized)")
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
        $script:Details.Add("⚠️  Quorum: could not query deployment info")
        $script:Warnings++
        return
    }

    $deploy = $null
    try { $deploy = $rawDeploy | ConvertFrom-Json } catch { }
    if ($null -eq $deploy) {
        $script:Details.Add("⚠️  Quorum: could not query deployment info")
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

    # v2.5.6-win.1: musigDetail now carries its own status icon so the
    # line renders consistently alongside the other ✅/ℹ️/⚠️  health
    # lines instead of floating with a bare three-space indent.
    if ($musigState -eq "complete") {
        $musigDetail = "✅ MuSig2: epoch $musigEpoch, $musigNonces/$consensusRequired nonces, $musigSigs/$consensusRequired sigs"
    } elseif ("$musigEpoch" -ne "?") {
        $musigDetail = "ℹ️  MuSig2: epoch $musigEpoch, $musigNonces/$consensusRequired nonces, $musigSigs/$consensusRequired sigs — $musigState"
    } else {
        $musigDetail = "⚠️  MuSig2: could not parse session"
    }

    # --- Step 2: Count reporting oracles ---
    $rawOracles = Invoke-DGBCli -RpcArgs @("getoracles", "true")

    if ([string]::IsNullOrEmpty($rawOracles)) {
        if ($script:DdActive -eq $false) {
            $script:Details.Add("ℹ️  Quorum: standby (DigiDollar deployment: $($script:DdStatus))")
            return
        }
        $script:Details.Add("⚠️  Quorum: could not query oracles")
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
        $script:Details.Add("⚠️  Quorum: could not query oracles")
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
        $script:Details.Add("⚠️  Quorum: could not count reporting oracles (heartbeat_status field missing?) — using roster count")
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
                    Alert-Yellow "⚠️  Quorum Getting Thin" "$reporting/$totalSlots oracles reporting (need $consensusRequired). Comfortable is ${QUORUM_GREEN}+."
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
            $script:Details.Add("⚠️  Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — getting thin")
            $script:Warnings++
        }
        "green" {
            $script:Details.Add("✅ Quorum: $reporting/$totalSlots reporting (need $consensusRequired) — healthy")
        }
    }
    $script:Details.Add("$musigDetail")
}

# ============================================================================
# SUMMARY REPORT (-Summary and -DryRun)
# ============================================================================

function Send-Summary {
    Check-DigidollarActive   # v2.5: must run before oracle-dependent checks
    if (-not (Check-Daemon)) { return }
    Check-Oracle
    Check-Chain
    Check-Peers
    Check-Price
    Check-Disk
    Check-Memory
    Check-Swap               # v2.4
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
        $status = "⚠️  $($script:Warnings) Warnings"
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $uptimeStr = "unknown"
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $span = (Get-Date) - $boot
        $uptimeStr = "up $($span.Days) days, $($span.Hours) hours, $($span.Minutes) minutes"
    } catch { }

    $desc = ($script:Details -join "`n") + "`n⏱️ Uptime: $uptimeStr"

    $label = if ([string]::IsNullOrEmpty($NETWORK_LABEL)) { "Oracle" } else { $NETWORK_LABEL }

    if ($script:DRY_RUN -or [string]::IsNullOrEmpty($DISCORD_WEBHOOK)) {
        Write-Output "======================================="
        Write-Output " $label Health Summary — $(Get-Date)"
        Write-Output "======================================="
        Write-Output $desc
        Write-Output "======================================="
        # v2.6.0-win.1: no webhook configured but email is → still email
        # the summary (email-only operators are the point of #17).
        # Dry-run is handled inside Send-Email (prints, sends nothing).
        if ((-not $script:DRY_RUN) -and ($EMAIL_ENABLED -eq $true -or "$EMAIL_ENABLED" -eq "true")) {
            Send-Email -Subject "$status — Health Summary" -Body $desc | Out-Null
        }
        return
    }

    # v2.6.0-win.1: email fires alongside the Discord card. Send-Email
    # prefixes NETWORK_LABEL itself (chokepoint), so the subject passed
    # here is label-free to avoid doubling.
    Send-Email -Subject "$status — Health Summary" -Body $desc | Out-Null

    # v2.6.0-win.1: footer via Build-Footer — two lines when an update exists.
    $payload = @{
        embeds = @(
            @{
                title       = "$status — $label Health Summary"
                description = $desc
                color       = $color
                footer      = @{ text = (Build-Footer) }
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

# --- Pre-flight: DigiDollar activation status (v2.5) ---
# Sets globals $script:DdStatus and $script:DdActive so other checks know
# whether to alert on missing oracle data (post-activation) or downgrade
# to info (pre-activation). Called first from both Invoke-Checks and
# Send-Summary — -DryRun, -Summary, and -Watch all route through
# Send-Summary, so the pre-flight lives in both paths. Always succeeds;
# $DdActive defaults to $false if the RPC fails or DigiDollar isn't
# yet deployed.
function Check-DigidollarActive {
    $raw = Invoke-DGBCli -RpcArgs @("getdigidollardeploymentinfo")

    if ([string]::IsNullOrEmpty($raw)) {
        $script:DdStatus = "unknown"
        $script:DdActive = $false
        return
    }

    $info = $null
    try { $info = $raw | ConvertFrom-Json } catch { }
    if ($null -eq $info) {
        $script:DdStatus = "unknown"
        $script:DdActive = $false
        return
    }

    $script:DdStatus = "unknown"
    if ($null -ne $info.PSObject.Properties['status']) {
        $script:DdStatus = "$($info.status)"
    }
    $script:DdActive = ($script:DdStatus -eq "active")
}

function Invoke-Checks {
    Check-DigidollarActive   # v2.5: must run before oracle-dependent checks
    if (-not (Check-Daemon)) { return }
    Check-Oracle
    Check-Chain
    Check-Peers
    Check-Price
    Check-Disk
    Check-Memory
    Check-Swap               # v2.4
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
    # v2.5.4-win.1: label lives in the title only (Send-Discord prefixes
    # $NETWORK_LABEL) — no more doubled label in the card.
    Alert-Blue "🔧 Test Alert" "Oracle monitor is configured and working! $(Get-Date)"
    Write-Output "Check your Discord channel."
    if ($EMAIL_ENABLED -eq $true -or "$EMAIL_ENABLED" -eq "true") {
        Write-Output "(Email is enabled — a test email was sent too. To test email alone: .\oracle-monitor.ps1 -TestEmail)"
    }
} elseif ($TestEmail) {
    Write-Output "Testing email configuration..."
    if (-not ($EMAIL_ENABLED -eq $true -or "$EMAIL_ENABLED" -eq "true")) {
        Write-Output "ERROR: `$EMAIL_ENABLED is not set to `$true."
        Write-Output "       Set it in: $CONFIG_FILE"
        exit 1
    }
    if ([string]::IsNullOrEmpty($EMAIL_TO) -or `
        [string]::IsNullOrEmpty($SMTP_USER) -or `
        [string]::IsNullOrEmpty($SMTP_PASS)) {
        Write-Output "ERROR: `$EMAIL_TO, `$SMTP_USER, and `$SMTP_PASS must all be set."
        Write-Output "       Configure them in: $CONFIG_FILE"
        exit 1
    }
    if ([int]$SMTP_PORT -eq 465) {
        Write-Output "WARNING: port 465 (implicit TLS) is not natively supported by .NET's SmtpClient in PowerShell 5.1."
        Write-Output "         Most providers (Brevo, Gmail, Outlook) accept port 587 STARTTLS — change `$SMTP_PORT to 587 in the config."
    }
    Write-Output "Sending test email to $EMAIL_TO via ${SMTP_SERVER}:${SMTP_PORT}..."
    if (Send-Email -Subject "🔧 Test Email" -Body "Oracle monitor email alerts are configured and working.") {
        Write-Output "✓ Test email sent — check your inbox (and spam folder)."
    } else {
        Write-Output "✗ Send failed. Check SMTP settings in: $CONFIG_FILE"
        Write-Output "  Common issues:"
        Write-Output "    - Gmail: `$SMTP_PASS must be an App Password, not your account password"
        Write-Output "      (Google Account > Security > 2-Step Verification, then App passwords)"
        Write-Output "    - Outlook/365: `$SMTP_SERVER=`"smtp.office365.com`", `$SMTP_PORT=587"
        Write-Output "    - Wrong `$SMTP_PORT for your provider (587=STARTTLS)"
        Write-Output "    - Windows Firewall blocking outbound port ${SMTP_PORT} for powershell.exe"
        Write-Output "    - Corporate proxy: PS 5.1's SmtpClient does not honor proxy settings — talk to your admin"
        exit 1
    }
} elseif ($Watch) {
    # Live console dashboard — full status block, refreshed in place.
    # Runs in dry-run mode internally: never sends Discord alerts and never
    # touches state files, so it's safe to leave this window open alongside
    # the scheduled Task Scheduler checks. Ctrl+C to exit.
    if ($RefreshSeconds -lt 5) { $RefreshSeconds = 5 }
    $script:DRY_RUN = $true
    $label = if ([string]::IsNullOrEmpty($NETWORK_LABEL)) { "Oracle" } else { $NETWORK_LABEL }
    while ($true) {
        Clear-Host
        Write-Host "🔭 $label Monitor — watch mode (refreshes every ${RefreshSeconds}s, Ctrl+C to exit)"
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
