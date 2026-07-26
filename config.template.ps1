# %USERPROFILE%\.oracle-monitor\config.ps1 — Oracle Monitor Configuration (Windows)
#
# This file is dot-sourced by oracle-monitor.ps1 (v2.5.4-win.1+) at startup.
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

# ---- Discord Webhook (required for oracle-monitor.ps1 alerts) ----
# Get from: Server Settings > Integrations > Webhooks > Copy URL
$DISCORD_WEBHOOK = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"

# ---- Email Notifications (oracle-monitor.ps1 v2.6.0-win.1+) ----
# Sends the same alerts as Discord to an email address — red/yellow/green
# state changes plus the 12-hour summary. Works as a backup channel if
# Discord goes down, or as the ONLY channel if you don't use Discord at
# all (leave $DISCORD_WEBHOOK at the placeholder and the summary still
# emails). Uses .NET's built-in System.Net.Mail.SmtpClient — nothing
# extra to install; ships in every PowerShell 5.1.
#
# GMAIL SETUP (most common):
#   1. Turn on 2-Step Verification:  Google Account > Security
#   2. Create an App Password:       Google Account > Security > App passwords
#      (search "App passwords" in the account search bar if you can't
#      find it — Google hides it until 2-Step Verification is on)
#   3. Name it "Oracle Monitor", click Generate, copy the 16-character
#      password (shown once, spaces don't matter)
#   4. $SMTP_USER = your full Gmail address
#      $SMTP_PASS = that App Password — NEVER your real account password
#
# OUTLOOK / OFFICE 365:
#   $SMTP_SERVER = "smtp.office365.com"   $SMTP_PORT = 587
#   $SMTP_USER = your address, $SMTP_PASS = account password (or an App
#   Password if your account has MFA)
#
# BREVO (recommended if your ISP blocks SMTP submission from residential IPs):
#   $SMTP_SERVER = "smtp-relay.brevo.com"  $SMTP_PORT = 587
#   $SMTP_USER = your Brevo SMTP login (looks like xyz@smtp-brevo.com)
#   $SMTP_PASS = your Brevo Standard SMTP key
#   Free tier: 300 emails/day — plenty for oracle alerts.
#
# OTHER PROVIDERS: set $SMTP_SERVER/$SMTP_PORT per their docs.
#   Port 587 = STARTTLS (only reliably supported mode in PS 5.1)
#   Port 465 = implicit TLS (NOT supported natively — use 587 instead)
#
# Note: .NET's SmtpClient in PowerShell 5.1 does not natively support
# port 465 (implicit TLS). Every major provider offers 587 STARTTLS as
# an alternative — use it.
#
# TEST: .\oracle-monitor.ps1 -TestEmail
#
$EMAIL_ENABLED = $false
$EMAIL_TO      = "you@example.com"
$SMTP_SERVER   = "smtp.gmail.com"
$SMTP_PORT     = 587
$SMTP_USER     = "your-address@gmail.com"
$SMTP_PASS     = "xxxxxxxxxxxxxxxx"
$SMTP_FROM     = "Oracle Monitor <your-address@gmail.com>"

# ---- Update Check (oracle-monitor.ps1 v2.6.0-win.1+) ----
# Once a day the monitor compares its own version against the copy
# published on GitHub main. When a newer version exists, every Discord
# card and email gains a footer line: "⬆️ vX.Y.Z available". Silent on
# any failure (offline, timeout, GitHub down) — the monitor itself is
# never affected. Set $UPDATE_CHECK = "no" to disable entirely.
$UPDATE_CHECK = "yes"
# $UPDATE_CHECK_TTL = 86400    # seconds between GitHub fetches (default 1 day)

# ---- DigiByte Core Version Check (oracle-monitor.ps1 v2.6.3+) ----
# Once a day the monitor also compares your running node's version against
# the latest DigiByte Core release on GitHub. The node-version line turns
# green when you're on the latest release (or newer), and stays blue with a
# "— vX.Y.Z available" note when a newer release is out. Silent on any
# failure (falls back to the plain blue line). Set to "no" to disable.
$DIGIBYTE_UPDATE_CHECK = "yes"
# $DIGIBYTE_UPDATE_TTL = 21600  # seconds between GitHub release checks (default 6h)
#   NOTE: keep this SHORTER than your summary interval. The version check
#   runs only inside a summary (-Summary), so if the TTL and the summary
#   cadence are both ~24h they race — the cache can expire seconds after
#   the summary reads it, and the "vX.Y.Z available" note then alternates
#   on and off day to day. 6h is safely inside any sane summary schedule.

# ---- Oracle Identity ----
$ORACLE_ID   = 0
$ORACLE_NAME = "my-oracle"

# ---- RPC Settings ----
# Full path to digibyte-cli.exe (or bare name if it's on your PATH).
# Typical: "C:\Program Files\DigiByte\daemon\digibyte-cli.exe"
$CLI_PATH = "C:\Program Files\DigiByte\daemon\digibyte-cli.exe"

# Network arguments passed to every CLI call.
# Single-chain PC:
#   Testnet:  @("-testnet")        Mainnet:  @()
#
# RUNNING BOTH CHAINS ON ONE PC? Do NOT leave $CLI_ARGS empty for the
# mainnet instance (#42). With no network argument, digibyte-cli.exe reads
# the default digibyte.conf, and on a dual-instance setup that file is the
# TESTNET conf and carries testnet=1, so the client connects to the testnet
# RPC port while your mainnet daemon runs with its own -conf= that the bare
# client never reads. Nothing errors. You get a health summary titled
# "Mainnet" reporting testnet block heights, testnet quorum, and testnet
# prices. The only visible tell is the chain name on the Chain line, e.g.
# "Chain: synced at block 178878 (test)" sitting under a Mainnet title.
# Pin the chain explicitly on BOTH instances:
#   Testnet:  @("-testnet")
#   Mainnet:  @("-conf=C:\Users\YOUR_USER\AppData\Roaming\DigiByte\mainnet.conf")
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
#
# Set $SERVICE_NAME = "none" (v2.6.3+; "skip"/"disabled" also work) to
# explicitly disable the service check — an informational "check disabled"
# line instead of a red — if you run digibyted without a service wrapper.
$SERVICE_NAME = ""
# $SERVICE_NAME = "none"       # explicitly disable the Windows service check

# ---- Disk ----
# Drive letter where your DigiByte datadir lives. Default datadir is
# %APPDATA%\DigiByte, which normally lives on drive C.
$DISK_DRIVE = "C"

# ---- DigiByte Datadir Named in Low Disk Alerts (v2.5.5-win.1+) ----
# The Low Disk Space alert prints this path on its own line so you know
# exactly where to clean up. Display-only — the monitor never reads or
# deletes anything here. Keep it on the same drive as $DISK_DRIVE. No
# RPC returns the datadir, so it's declared in config. Set it per config
# file, same pattern as $NETWORK_LABEL:
#
#   Single-instance (one daemon on this PC) — leave the default:
#     $DATADIR = "$env:APPDATA\DigiByte"
#
#   Dual-instance (testnet + mainnet via -Config) — set each config so
#   each instance's alert names its own datadir:
#     testnet config:  $DATADIR = "$env:APPDATA\DigiByte\testnet26"
#     mainnet config:  $DATADIR = "$env:APPDATA\DigiByte"
#
# Mainnet chain data lives at the datadir top level; testnet data lives
# in a subdirectory named for the current testnet reset (testnet26,
# testnet27, ...) — bump it when the testnet resets.
$DATADIR = "$env:APPDATA\DigiByte"

# ---- v2.7.0: Disk + debug.log Safety Net ----
# Yellow disk band (closes #33): warn at this used-% while $MIN_DISK_GB
# below stays the red floor. 0 disables the band.
$DISK_USED_PCT_WARN = 80

# debug.log watchdog (Check 13): yellow alert when the daemon's debug.log
# reaches this many MB. The alert names any enabled debug categories —
# enabling one (e.g. debug=digidollar from the old setup docs) also
# disables the daemon's automatic startup log-shrink, and oracle boxes
# rarely restart. Measured: ~374 MB/day with digidollar+net enabled vs
# ~8 MB/day default logging.
$DEBUG_LOG_WARN_MB = 1024

# debug.log safe auto-rotation — DEFAULT ON (v2.7.0 behavior change).
# At $DEBUG_LOG_MAX_MB: Copy-Item to debug.log.1, truncate the live file
# in place via .NET (daemon keeps writing, no restart). Previous .1 only
# overwritten by the NEXT rotation (~2x threshold of newest history
# always kept). Every rotation posts a blue card; skipped with a red
# card if free space can't hold the safety copy. If Windows file locking
# blocks the in-place truncate, one yellow card explains the durable fix
# (shrinkdebugfile=1 + restart) and re-attempts stop. "no" opts out.
# $DEBUG_LOG_KEEP = rotated copies to retain (values >1 chain .1→.2→…;
# 0 is treated as 1 — never truncate without a copy).
$DEBUG_LOG_ROTATE = "yes"
$DEBUG_LOG_MAX_MB = 2048
$DEBUG_LOG_KEEP   = 1

# Run the getoracleprice freshness check every Nth pass (Check 5). That
# RPC writes ~4,780 log lines per call when debug=digidollar is on —
# 3 = one price check per 15 min at the stock schedule (a third of that
# log volume, up to 10 extra minutes' stale-price latency). 1 = every
# pass (pre-2.7.0 behavior). Summaries always check.
$PRICE_CHECK_EVERY = 1

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

# ---- Swap Pressure Gating (v2.6.2) ----
# A filled page file is NOT the same as memory pressure. After a heavy
# transient the OS can leave a lot parked in the page file long after the
# pressure ended — a stale fill, not a live problem. v2.6.2 only raises the
# swap alert when RAM usage is at or above $SWAP_MEM_HEADROOM_PCT. (Windows
# has no PSI, the Linux stall meter, so RAM headroom is the sole signal.)
# If quiet, the fill shows as an informational "stale" line, not an alert.
# If RAM% can't be measured the monitor fails safe and alerts as before.
# Raise this toward 80-85 for a quieter alert on a busy-but-healthy box;
# lower it to be warned earlier.
$SWAP_MEM_HEADROOM_PCT = 70   # only alert on filled page file when RAM% >= this

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
# Also prefixes the Subject: line on emails (v2.6.0-win.1+), same chokepoint.
#
# Leave empty for the generic "Oracle" label.
$NETWORK_LABEL = ""

# Optional glyph in front of $NETWORK_LABEL on every alert title, email
# subject, health summary header, and the watch mode banner (v2.9.0, #41).
# Empty by default. If you run two instances, marking just one is usually
# enough: leave the production instance empty so its cards look exactly as
# they always have, and flag the test one. Requires $NETWORK_LABEL to be set.
#   Testnet:  $NETWORK_EMOJI = "🚧"
#   Mainnet:  $NETWORK_EMOJI = ""
$NETWORK_EMOJI = ""

# ---- DigiDollar Economy Line (v2.9.0-win.1+) ----
# One info line under Price on the health summary: "DD economy: $40,932.07
# DD minted, 40,461,618 DGB locked (332% collateralized)", the same wording
# the Gitter status bot uses. Summary card only, never the scheduled
# 5-minute checks. Information only: it never alerts and never changes the
# card color. Silently omitted if the RPC is unavailable, and it shows a
# standby line before DigiDollar activates on your chain.
# Set to "no" to skip the getdigidollarstats call entirely.
$DD_ECONOMY_ENABLED = "yes"

# ---- Dual-Instance Monitoring (v2.3-win.1+) ----
# oracle-monitor.ps1 supports -Config /path to run against a separate
# config file. This lets you monitor testnet and mainnet from one PC
# without maintaining two copies of the script.
#
# How it works:
#   - Each instance reads its own config file (CLI path, webhook, thresholds)
#   - State files (quorum_state, daemon_down, update_check_cache, etc.)
#     auto-separate by the config file's parent directory — Split-Path
#     -Parent derives $STATE_DIR
#
# Setup example — adding a mainnet instance alongside testnet:
#
#   mkdir $env:USERPROFILE\.oracle-monitor-mainnet
#   copy $env:USERPROFILE\.oracle-monitor\config.ps1 `
#        $env:USERPROFILE\.oracle-monitor-mainnet\config.ps1
#
#   # Edit the mainnet config to override at least:
#   #   $CLI_ARGS         = @("-conf=$env:APPDATA\DigiByte\mainnet.conf")
#   #                                                    (NOT @() - see #42)
#   #   $SWAP_THRESHOLD_MB = 1500                        (dual-daemon baseline)
#   #   $QUORUM_GREEN     = 12; $QUORUM_YELLOW = 10      (tighter for production)
#   #   $NETWORK_LABEL    = "Mainnet"                    (shows in card titles + email subjects)
#   #   $DATADIR          = "$env:APPDATA\DigiByte"      (named in Low Disk alerts —
#   #                                                     and set the TESTNET config to
#   #                                                     "$env:APPDATA\DigiByte\testnet26")
#   #   $DISCORD_WEBHOOK  = "https://..."                (same or different webhook)
#   #   $EMAIL_TO         = "you@example.com"            (same or different address —
#   #                                                     subject prefix distinguishes them)
#
#   # Test:
#   .\oracle-monitor.ps1 -Config $env:USERPROFILE\.oracle-monitor-mainnet\config.ps1 -DryRun
#
#   # Add to Task Scheduler (offset by 2 minutes to avoid RPC collision):
#   schtasks /Create /SC MINUTE /MO 5 /TN "OracleMonitor-Mainnet" ^
#     /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
#          -File C:\Users\YOUR_USER\OracleMonitor\oracle-monitor.ps1 ^
#          -Config C:\Users\YOUR_USER\.oracle-monitor-mainnet\config.ps1"
