# %USERPROFILE%\.oracle-monitor\config.ps1 — Oracle Monitor Configuration (Windows)
#
# This file is dot-sourced by oracle-monitor.ps1 (v2.5.2-win.1+) at startup.
# Edit values below to override the built-in defaults.
# Lines starting with # are ignored.
#
# After editing, verify with:
#   .\oracle-monitor.ps1 -DryRun
#
# For dual-instance (e.g. testnet + mainnet on one PC):
#   .\oracle-monitor.ps1 -Config C:\Users\YOUR_USER\.oracle-monitor-mainnet\config.ps1 -DryRun
#
# Docs: https://github.com/BaumerCrypto/digidollar-oracle-tools

# ---- Discord Webhook (required for alerts) ----
# Get from: Server Settings > Integrations > Webhooks > Copy URL
$DISCORD_WEBHOOK = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"

# ---- Oracle Identity ----
$ORACLE_ID   = 0
$ORACLE_NAME = "my-oracle"

# ---- RPC Settings ----
# Full path to digibyte-cli.exe (or bare name if it's on your PATH).
# Typical: "C:\Program Files\DigiByte\daemon\digibyte-cli.exe"
$CLI_PATH = "C:\Program Files\DigiByte\daemon\digibyte-cli.exe"

# Network arguments passed to every CLI call.
# Testnet:  @("-testnet")        Mainnet:  @()
# Dual-instance mainnet with conf file:
#   @("-conf=C:\Users\YOUR_USER\AppData\Roaming\DigiByte\mainnet.conf")
$CLI_ARGS    = @("-testnet")
$WALLET_FLAG = "-rpcwallet=oracle"

# ---- Daemon Process Name (v2.5.2-win.1+) ----
# The monitor auto-detects either "digibyted" (headless daemon) or
# "digibyte-qt" (Qt GUI wallet). In auto-detect mode it prefers digibyted
# first, then falls back to digibyte-qt. Sets $script:DetectedDaemon to
# the actual matched name so the Discord "Node: X running" line shows
# what the monitor actually found.
#
# Leave $DAEMON_PROCESS = "" (default) for auto-detect. Set it to force
# a specific match only if you run BOTH binaries on the same PC:
#   $DAEMON_PROCESS = "digibyted"     # headless daemon
#   $DAEMON_PROCESS = "digibyte-qt"   # Qt wallet
#
# For Qt-wallet operators: leave empty — auto-detect will find it. The
# Windows Service check (Check #8) automatically skips with an INFO line
# when the Qt wallet is the detected daemon, since Qt usually runs
# outside NSSM/service wrappers.
$DAEMON_PROCESS = ""

# ---- Windows Service (optional) ----
# If you run digibyted as a Windows service (e.g. wrapped with NSSM), put
# the service name here and Check #8 will report its Running/Stopped
# state. Leave "" to fall back to a process check. Ignored automatically
# when the Qt wallet is the detected daemon (v2.5.2-win.1+).
$SERVICE_NAME = ""

# ---- Disk ----
# Drive letter where your DigiByte datadir lives. Default datadir is
# %APPDATA%\DigiByte, which normally lives on drive C.
$DISK_DRIVE = "C"

# ---- Alert Thresholds ----
$MIN_PEERS           = 3     # Minimum peer count before alerting
$MIN_DISK_GB         = 5     # Minimum free disk space (GB) before alerting
$STALE_PRICE_MINUTES = 30    # Reserved for future use — staleness currently from RPC
$MEM_THRESHOLD       = 90    # Memory usage % above which to alert
$MAX_CHAIN_BEHIND    = 10    # Blocks behind before alerting

# ---- Swap Pressure Threshold (v2.4-win.1+) ----
# Alert when page-file usage (Get-CimInstance Win32_PageFileUsage) exceeds
# this many MB.
#
# On Windows with a healthy amount of RAM, sustained page-file use signals
# real memory pressure. The default 100 MB threshold suits desktops with
# 16 GB+ RAM. Machines with less RAM or heavy browser use may show
# baseline page-file activity that needs a higher threshold.
#
# Recommended values:
#   Desktop / plenty of RAM (16GB+):     100 MB
#   Laptop with 8GB and browser tabs:    500 MB
#   Dual-daemon (testnet + mainnet):     1500 MB
#
# To calibrate: after 24h of stable operation, run:
#   Get-CimInstance Win32_PageFileUsage | Select CurrentUsage,AllocatedBaseSize
# and set the threshold ~200-500 MB above the CurrentUsage value.
$SWAP_THRESHOLD_MB   = 100

# ---- NTP Check ----
# Clock offset is measured with one `w32tm /stripchart` sample against
# this server. Locale-independent — works even when the Windows Time
# service is stopped. Oracle bundle timestamps are rejected past 3600s
# skew, so keep this tight — a drifting clock kills your signing.
$NTP_SERVER             = "time.windows.com"
$NTP_MAX_OFFSET_SECONDS = 1.0

# ---- Quorum Alert Bands (v2.0, tuned in v2.5.1) ----
# Band thresholds for network-wide oracle liveness.
# The on-chain minimum (oracle_consensus_required) comes from the chain
# via getdigidollardeploymentinfo — not configurable here (currently 7-of-35).
#
# Recommended values (v2.5.1):
#   Mainnet (production, 35-slot roster):  GREEN=12, YELLOW=10
#   Testnet26 (smaller active population): GREEN=10, YELLOW=8
#
# The v2.0-v2.4 defaults (20/12) were too permissive and fired "getting
# thin" at 15/35 fresh — more than 2x the hard 7-of-35 floor — which
# conditioned operators to ignore the check. New defaults fire only at
# meaningful risk levels.
$QUORUM_GREEN  = 12    # At or above = comfortable (no alerts)
$QUORUM_YELLOW = 10    # At or above but below green = "getting thin"

# ---- Anti-Flap (v2.1) ----
# Cooldown: minimum minutes between quorum RECOVERY alerts.
# Escalation (getting worse) always fires immediately.
# Set to 0 to disable (v2.0 behavior = alert every state change).
$QUORUM_COOLDOWN = 30

# Hysteresis: recovery requires exceeding the threshold by this buffer.
# Example: GREEN=12, HYSTERESIS=3 -> must hit 15 to recover to green.
# Prevents rapid green/yellow flapping when count hovers near boundary.
# Set to 0 to disable (v2.0 behavior = recover at exact threshold).
$QUORUM_HYSTERESIS = 3

# ---- Network Label (v2.5.1-win.1+) ----
# Identifies which chain this monitor instance is watching. Appears in
# Discord card titles, dry-run header, watch mode header, and -Test output:
#   "✅ All Systems Healthy — Testnet26 Health Summary"
#   "⚠️ 1 Warnings — Mainnet Health Summary"
#   "🔧 Mainnet Test Alert"
#   "🔭 Mainnet Monitor — watch mode (refreshes every 60s, Ctrl+C to exit)"
#
# Leave empty for the generic "Oracle" label.
$NETWORK_LABEL = ""

# ---- Dual-Instance Monitoring (v2.3-win.1+) ----
# oracle-monitor.ps1 supports -Config /path to run against a separate
# config file. This lets you monitor testnet and mainnet from one PC
# without maintaining two copies of the script.
#
# How it works:
#   - Each instance reads its own config file (CLI path, webhook, thresholds)
#   - State files (quorum_state, daemon_down, etc.) auto-separate by the
#     config file's parent directory — Split-Path -Parent derives $STATE_DIR
#
# Setup example — adding a mainnet instance alongside testnet:
#
#   mkdir $env:USERPROFILE\.oracle-monitor-mainnet
#   copy $env:USERPROFILE\.oracle-monitor\config.ps1 `
#        $env:USERPROFILE\.oracle-monitor-mainnet\config.ps1
#
#   # Edit the mainnet config to override at least:
#   #   $CLI_ARGS         = @()                          (no -testnet)
#   #   $SWAP_THRESHOLD_MB = 1500                        (dual-daemon baseline)
#   #   $QUORUM_GREEN     = 12; $QUORUM_YELLOW = 10      (tighter for production)
#   #   $NETWORK_LABEL    = "Mainnet"                    (shows in card titles)
#   #   $DISCORD_WEBHOOK  = "https://..."                (same or different webhook)
#
#   # Test:
#   .\oracle-monitor.ps1 -Config $env:USERPROFILE\.oracle-monitor-mainnet\config.ps1 -DryRun
#
#   # Add to Task Scheduler (offset by 2 minutes to avoid RPC collision):
#   schtasks /Create /SC MINUTE /MO 5 /TN "OracleMonitor-Mainnet" ^
#     /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
#          -File C:\Users\YOUR_USER\OracleMonitor\oracle-monitor.ps1 ^
#          -Config C:\Users\YOUR_USER\.oracle-monitor-mainnet\config.ps1"
