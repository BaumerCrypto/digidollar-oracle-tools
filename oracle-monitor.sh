#!/bin/bash
###############################################################################
# oracle-monitor.sh — DGB Oracle Health Monitor with Discord + Email Alerts
# Version: 2.6.3
#
# Monitors oracle node health and sends Discord webhook and email
# notifications when issues are detected. Designed for cron job execution.
#
# Author & Oracle: digibyte-maxi (ID 17) — VPS | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 - July 2026
readonly SCRIPT_VERSION="2.6.3"
#
# SETUP:
#   1. Copy this script to your VPS: ~/oracle-monitor.sh
#   2. chmod +x ~/oracle-monitor.sh
#   3. Create config: mkdir -p ~/.oracle-monitor && cp config.template ~/.oracle-monitor/config
#   4. Edit config: Set your Discord webhook URL, oracle settings, and
#      (optionally) email settings — see the EMAIL section in the template
#   5. Test it: ./oracle-monitor.sh --dry-run
#   6. Test webhook: ./oracle-monitor.sh --test
#   7. Test email (if enabled): ./oracle-monitor.sh --test-email
#   8. Add to cron: crontab -e
#      */5 * * * * /home/YOUR_USER/oracle-monitor.sh 2>/dev/null
#      0 */12 * * * /home/YOUR_USER/oracle-monitor.sh --summary 2>/dev/null
#
# FLAGS:
#   (none)     Normal health check — alerts only on problems/recovery
#   --summary  Full status summary — always sends to Discord + email
#   --dry-run  Runs all checks, prints to terminal, skips Discord + email, no state changes
#   --test     Sends a test embed to Discord to verify webhook
#   --test-email    Sends a test email to verify SMTP settings
#   --config /path  Use alternate config file (enables dual-instance monitoring)
#
# CRON SCHEDULE:
#   */5 = every 5 minutes for health checks (alerts only on problems)
#   0 */12 = every 12 hours for a full status summary (always sends)
#
# CHANGELOG:
#   v2.6.3 — Two operator-suggested additions.
#            (1) DIGIBYTE VERSION NOW UPDATE-AWARE (caught by Baumer). The
#            node-version line (Check 9) compares the running version
#            against the latest DigiByte Core release on GitHub
#            (releases/latest, cached daily per instance) and colours the
#            icon: ✅ green when running the latest release or newer, ℹ️
#            blue "— vX.Y.Z available" when a newer release is out. Falls
#            back to the plain ℹ️ line when GitHub is unreachable or the
#            check is disabled — never blocks a run, and never fetches or
#            writes its cache during --dry-run. Previously the line was
#            always blue regardless of whether an update existed. New
#            config: DIGIBYTE_UPDATE_CHECK ("yes"), DIGIBYTE_UPDATE_TTL
#            (86400). Uses releases/latest, which GitHub only points at a
#            real (non-prerelease) release, so operators are never nudged
#            toward an RC.
#            (2) SERVICE_NAME="none" ESCAPE HATCH (caught by Aussie Epic).
#            Operators who deliberately run headless WITHOUT systemd
#            (tmux/screen, Docker, runit, a hand-started -daemon) can set
#            SERVICE_NAME="none" (also "skip"/"disabled") to replace the
#            systemd check with an ℹ️ "check disabled" line instead of a 🔴
#            on a missing/idle unit. The daemon and oracle-process checks
#            still run — only the systemd unit lookup is suppressed.
#   v2.6.2 — Three operator-suggested fixes (two cosmetic, one alert-logic).
#            (1) VERSION LINE CLEANUP. check_version now strips the
#            bitcoin-legacy /Name:Version/ user-agent wrapper that
#            getnetworkinfo → .subversion returns. Line goes from
#            "ℹ️  /DigiByte:9.26.4/" to "ℹ️  DigiByte: v9.26.4" — the
#            slashes are meaningful to network peers but noise to
#            operators reading a health summary. Matches the format
#            oracle-network-status.sh has always used in the Gitter
#            Software section. Handles rc builds and hash suffixes
#            correctly (/DigiByte:9.26.0rc46/ → DigiByte: v9.26.0rc46).
#            (2) EMAIL TIME LINE IN UTC. Time: line in email body now
#            uses UTC ('date -u') instead of VPS-local timezone ('date').
#            Matches Discord/Slack card timestamp convention (both use
#            UTC internally, client renders to viewer-local). Operators
#            on VPS in different timezones than their home no longer
#            need to mentally convert CEST/PST/AEST — UTC is universal
#            reference. No config change; automatic.
#            (3) SWAP ALERT NOW PRESSURE-GATED (caught by Aussie Epic).
#            A filled swap is no longer treated as memory pressure on its
#            own. After a -reindex (or any heavy transient) the kernel can
#            page GBs out to swap and never page them back in; on a box
#            later upgraded from 16GB to 32GB RAM that left a permanent red
#            swap alert while RAM sat at 40% and nothing was stalling.
#            check_swap now only raises the yellow alert when there is
#            *current* pressure, judged by two independent signals (either
#            one fires): Linux PSI (/proc/pressure/memory "some avg10" >
#            PSI_SWAP_THRESHOLD) or RAM usage >= SWAP_MEM_HEADROOM_PCT.
#            A stale fill shows as an ℹ️ line ("stale — RAM 40%, PSI 0.00")
#            and no longer inflates the warning count. If neither signal
#            can be measured it fails safe and alerts as v2.4 did. New
#            config: SWAP_MEM_HEADROOM_PCT (default 70), PSI_SWAP_THRESHOLD
#            (default 5.0). Real pressure still alerts exactly as before.
#   v2.6.1 — Cosmetic fix (caught by Aussie Epic). ⚠️ (U+26A0 + VS16)
#            and ℹ️ (U+2139 + VS16) render as single-width text glyphs
#            in most terminals — the VS16 selector requests emoji
#            presentation but is honored inconsistently — while ✅ 🔴
#            💀 render as double-width emoji. Net effect in the health
#            summary: every ⚠️/ℹ️ line's label sat one column left of
#            the ✅/🔴 line labels, giving the summary a subtle-but-
#            persistent "some lines look squished" appearance. Every
#            ⚠️ and ℹ️ prefix now carries a second space so all
#            status lines line up at the same column regardless of the
#            terminal's emoji-width handling. Applies to DETAILS
#            summary lines, alert titles, and the top status header
#            ("⚠️  N Warnings"). One remaining single-space instance
#            in musig_detail (the "in progress" state added in v2.5.6)
#            is also brought in line. No logic change; no alert path
#            change — purely how the output renders. In Discord and
#            email the double-space is visually harmless (Discord
#            renders these as full-width emoji so the extra space
#            reads as intentional padding). Also: the update-available
#            footer URL now includes the https:// scheme —
#            "https://github.com/BaumerCrypto/digidollar-oracle-tools"
#            instead of the bare "github.com/..." — so email clients
#            auto-linkify it universally (Outlook desktop and some
#            corporate gateways only linkify URLs with an explicit
#            scheme). One-character change in build_footer; the Discord
#            embeds and terminal output benefit too.
#   v2.6.0 — Two features, one release.
#            (1) EMAIL NOTIFICATIONS (closes #17). New send_email() fires
#            on the same triggers as Discord — red/yellow/green state
#            changes plus the 12-hour summary — via curl's built-in SMTP
#            support (no mailx/postfix/sendmail needed; curl ships with
#            SMTP on every stock Ubuntu). Config-driven: EMAIL_ENABLED,
#            EMAIL_TO, SMTP_SERVER, SMTP_PORT, SMTP_USER, SMTP_PASS,
#            SMTP_FROM. Port 587 = STARTTLS (Gmail/Outlook default),
#            465 = implicit TLS. Gmail requires an App Password (2FA →
#            App passwords), never the account password. Subjects carry
#            severity ([ALERT]/[WARNING]/[RESOLVED]/[INFO]) and the
#            NETWORK_LABEL prefix (dual-instance parity with v2.5.3
#            Discord titles, applied at the send_email chokepoint). New
#            --test-email flag verifies SMTP settings with inline
#            diagnostics for the common failure modes. Backup channel
#            if Discord is down; primary channel for operators who
#            don't use Discord/Slack/Telegram.
#            (2) UPDATE CHECK. New check_for_update() fetches this
#            script's own published header from the GitHub main branch
#            (raw.githubusercontent.com — the same URL the repo's
#            publish-verification flow already trusts), extracts the
#            published SCRIPT_VERSION, and compares via sort -V. When a
#            newer version exists, every Discord card and email gains a
#            second footer line: "⬆️ vX.Y.Z available — <repo url>".
#            No new repo files — the version source IS the shipped
#            script header, so it can never drift from what operators
#            actually download. UPDATE_CHECK="yes" by default; silent
#            on every failure mode (no curl, timeout, offline, parse
#            failure → footer simply stays one line, monitor unaffected).
#            Result cached per-instance for UPDATE_CHECK_TTL seconds
#            (default 86400 = one GitHub fetch per day per instance).
#            Never fetches and never writes cache in --dry-run
#            (v2.5.4 dry-run-touches-nothing discipline).
#   v2.5.6 — Cosmetic fix. The MuSig2 summary line was emitted with a
#            three-space indent and no status icon, making it look
#            "broken" next to every other health line (which lead with
#            ✅/ℹ️/⚠️). It now carries its own status icon: ✅ when the
#            session is complete (matching what Discord+terminals show),
#            ℹ️  when a session is in progress (with the state name inline
#            so you still see it), ⚠️  when the session can't be parsed.
#            The redundant "✓" and parenthesized state suffix are dropped
#            since the icon now carries that meaning. No behavior change,
#            no alert path change — purely how the line renders.
#   v2.5.5 — Disk check enhancements (both suggested by Aussie Epic).
#            (1) The disk line now shows total size and used% next to
#            free space — "✅ Disk: 156GB free of 200GB (22% used)" —
#            using the total that df already returned but wasn't printed.
#            Falls back to the old free-only wording if the total can't
#            be parsed. (2) The Low Disk Space alert now names your
#            DigiByte datadir on its own line so you know exactly where
#            to clean up, via the new DATADIR config variable (default
#            $HOME/.digibyte). No RPC returns the datadir, so it's
#            config-declared — dual-instance operators set it PER CONFIG
#            (testnet: $HOME/.digibyte/testnet26, mainnet:
#            $HOME/.digibyte), same pattern as SERVICE_NAME and
#            NETWORK_LABEL, so each instance's alert names its own
#            datadir. The path appears only in the red alert, never the
#            green summary line.
#   v2.5.4 — Full-repo audit fixes (July 2026). (1) Default quorum bands
#            now actually 12/10 — the v2.5.1 changelog promised the tune
#            but this script kept 20/12 while both ports and all three
#            config templates already shipped 12/10. (2) Node Down alert
#            names the configured SERVICE_NAME instead of a hardcoded
#            digibyted.service (dual-instance operators were told to
#            check the wrong unit). (3) check_disk: new DISK_PATH config
#            knob for datadirs on non-/home mounts, plus a numeric guard
#            so a failed df reads "could not query" instead of a silent
#            green line. (4) --dry-run no longer deletes the legacy v2.0
#            quorum state files (dry-run must touch nothing). (5) Discord
#            payloads built with jq -n — a quote or backslash in
#            RPC-derived text could previously break the webhook POST
#            silently. (6) check_ntp degrades to a "could not verify"
#            warning on systems without timedatectl (containers) instead
#            of a false desync alert. (7) --test no longer double-labels
#            the card when NETWORK_LABEL is set.
#   v2.5.3 — send_discord() now prefixes every individual alert title with
#            NETWORK_LABEL (when set), not just the health summary and
#            --test alert. Fixes dual-instance operators (testnet+mainnet
#            on one VPS) getting an unlabeled "Node Down" card with no way
#            to tell which daemon fired it. Single chokepoint fix — every
#            alert_red/yellow/green/blue call routes through send_discord(),
#            so this covers all 19 individual alert types (Node Down,
#            Oracle Stopped, Chain Synced, Quorum Lost, Low Disk, etc.) at
#            once. No-op for single-instance operators without NETWORK_LABEL
#            set — zero behavior change for the common case. (caught by
#            digibyte-maxi during the v9.26.4 binary swap)
#   v2.5.2 — check_daemon() now auto-detects either digibyted (headless)
#            or digibyte-qt (GUI wallet). Sets DETECTED_DAEMON global so
#            downstream checks can branch. check_services() skips the
#            systemd check with an INFO line when the Qt wallet is running
#            outside systemd (no false red). Optional DAEMON_PROCESS
#            config override for anyone running both binaries on the same
#            box. Backports the $DAEMON_PROCESS parity that already
#            existed in the PowerShell version. (caught by Aussie Epic)
#   v2.5.1 — Add SCRIPT_VERSION constant + NETWORK_LABEL in Discord card
#            titles and dry-run/test output. Tune default quorum bands
#            from 20/12 → 12/10 (v2.0 defaults produced yellow alerts at
#            15/35 fresh — 2x the hard 7-of-35 floor — which conditioned
#            operators to ignore the check). Quorum counting stays on
#            heartbeat_status=="fresh" from v2.2.
#   v2.5 — DigiDollar BIP9 pre-activation guard. New
#          check_digidollar_active() sets DD_STATUS/DD_ACTIVE globals via
#          getdigidollardeploymentinfo, called first in both run_checks()
#          and send_summary() (--dry-run/--summary route through
#          send_summary, so the pre-flight must live in both).
#          check_oracle, check_price, check_services, check_quorum all
#          downgrade "no data" to standby INFO instead of red alert while
#          DD_ACTIVE=false. check_services now honours configurable
#          ${SERVICE_NAME:-digibyted.service}. check_version reads
#          $CLI getnetworkinfo → .subversion instead of the raw
#          `digibyted --version` (which pulled the wrong binary from
#          $PATH in dual-daemon setups).
#   v2.4 — Add swap pressure detection (Check #12). Fires a yellow
#          alert when swap usage exceeds SWAP_THRESHOLD_MB (default
#          100 MB). On a properly configured box with swappiness=10,
#          any meaningful swap usage signals real memory pressure —
#          the exact condition that silently killed daemons in the
#          PRE stale incident (June 2026). Companion to the OOM
#          protection added to the hardening guide in v1.3.
#          (fixes #26, suggested by shenger)
#   v2.3 — Add --config /path flag for dual-instance monitoring
#          (Issue #23 pattern from oracle-network-status.sh v1.4).
#          Two cron entries + two config files = independent testnet
#          and mainnet monitoring from one VPS. State files auto-
#          separate per config directory via dirname. Argument
#          parsing restructured: while loop replaces positional
#          case, handles --config + action flags in any order.
#   v2.2 — Switch quorum counting from last_price_usd (volatile —
#          resets during MuSig2 round transitions) to heartbeat_status
#          ("fresh" = online within 30 min). Matches the dashboard's
#          "Online Heartbeats" metric. Dramatically reduces false
#          alert volume during normal round cycling.
#   v2.1.1 — Fix: hysteresis now evaluates recovery band directly
#            against thresholds instead of cascading from prev_band
#            (22/35 from critical now lands on yellow, not green).
#            Default QUORUM_COOLDOWN raised 15→30 to match ~20-min
#            oracle oscillation cycle during testnet bootstrapping.
#   v2.1 — Anti-flap: cooldown timer + hysteresis buffer for quorum
#          alerts. Escalation (worse) fires immediately; recovery
#          (better) is throttled. Single quorum_state file replaces
#          three separate state files. Configurable via
#          QUORUM_COOLDOWN and QUORUM_HYSTERESIS in config.
#   v2.0 — Quorum margin tracking via getdigidollardeploymentinfo +
#          getoracles true. Configurable alert thresholds. MuSig2
#          session health in summary. (closes #6)
#   v1.5 — Replace dgb-oracle.service systemd check with listoracle
#          RPC (fixes Type=oneshot false positive, fixes #22)
#   v1.4 — RC44 warning/error differentiation per status enum
#          (active/warning/error) (fixes #21)
#   v1.3 — RC44 getoracleprice status enum fix (active not ok)
#   v1.2 — External config file, --dry-run flag, python3 → jq migration
#          (fixes #3, fixes #4, fixes #5)
#   v1.1 — Degraded consensus detection, NTP time sync check (fixes #1)
#   v1.0 — Initial release: 9 health checks, Discord webhooks, cron
#
###############################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Run: sudo apt install jq"
    exit 1
fi

# ============================================================================
# ARGUMENT PARSING (before config loading — --config must be extracted first)
# ============================================================================

ACTION_FLAG=""
CONFIG_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                echo "ERROR: --config requires a path argument."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --dry-run|--summary|--test|--test-email)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        *)
            echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email]"
            exit 1
            ;;
    esac
done

# ============================================================================
# CONFIGURATION — DEFAULTS (override in ~/.oracle-monitor/config)
# ============================================================================

# Discord webhook URL — get this from your Discord server settings
# Server Settings > Integrations > Webhooks > New Webhook > Copy URL
DISCORD_WEBHOOK=""

# Email notifications (v2.6.0) — set EMAIL_ENABLED=true in the config to
# activate. Fires on the same triggers as Discord. Uses curl's built-in
# SMTP support (verify with: curl --version | grep smtp — standard on
# Ubuntu). See config.template for Gmail App Password setup.
EMAIL_ENABLED=false
EMAIL_TO=""           # Recipient address
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587         # 587 = STARTTLS (Gmail/Outlook), 465 = implicit TLS
SMTP_USER=""          # SMTP login (usually your full email address)
SMTP_PASS=""          # Gmail: 16-char App Password — NOT your account password
SMTP_FROM=""          # "Display Name <you@example.com>" — empty = use SMTP_USER

# Update check (v2.6.0) — compares this script's version against the
# published copy on GitHub main once per UPDATE_CHECK_TTL seconds. When a
# newer version exists, Discord cards and emails gain a second footer
# line. Silent on any failure. Set UPDATE_CHECK="no" to disable.
UPDATE_CHECK="yes"
UPDATE_CHECK_URL="https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor.sh"
UPDATE_CHECK_TTL=86400

# DigiByte Core version check (v2.6.3) — compares the running node's
# version against the latest DigiByte Core release on GitHub once per
# DIGIBYTE_UPDATE_TTL seconds. The node-version line in the health summary
# turns ✅ green when you're on the latest release (or newer) and stays
# ℹ️ blue with a "vX.Y.Z available" note when a newer release exists.
# Silent on any failure (blue line, no note). Set to "no" to disable.
DIGIBYTE_UPDATE_CHECK="yes"
DIGIBYTE_UPDATE_TTL=86400

# Oracle settings
ORACLE_ID=0
ORACLE_NAME="my-oracle"
CLI="digibyte-cli -testnet"
WALLET_FLAG="-rpcwallet=oracle"

# Thresholds — basic health
MIN_PEERS=3
MIN_DISK_GB=5
STALE_PRICE_MINUTES=30
MEM_THRESHOLD=90
SWAP_THRESHOLD_MB=100
# v2.6.2 — Swap "pressure" is only real when RAM is actually tight. A
# filled swap can be a stale leftover from a past -reindex/verify/backup
# that the kernel never paged back in (common after a RAM upgrade). These
# two thresholds gate the swap alert on genuine *current* pressure:
#   SWAP_MEM_HEADROOM_PCT — only alert when RAM usage is at/above this %.
#   PSI_SWAP_THRESHOLD    — Linux only. /proc/pressure/memory "some avg10"
#                           above this = real stalls happening now. Either
#                           signal firing raises the alert; if neither can
#                           be measured the monitor fails safe and alerts.
SWAP_MEM_HEADROOM_PCT=70
PSI_SWAP_THRESHOLD="5.0"
MAX_CHAIN_BEHIND=10

# Path whose filesystem is watched for free disk space (v2.5.4).
# Set this to the mount that holds your DigiByte datadir if it isn't
# under /home (e.g. DISK_PATH="/mnt/blockchain").
DISK_PATH="/home"

# DigiByte datadir named in the Low Disk Space alert (v2.5.5) so the
# operator knows exactly where to clean up. Display-only — the monitor
# never reads or deletes anything here. Dual-instance operators should
# set this per config file (see config.template) so each instance's
# alert names its own datadir.
DATADIR="$HOME/.digibyte"

# Thresholds — quorum margin (v2.0)
# These define the alert bands for network-wide oracle liveness.
# Quorum threshold (oracle_consensus_required) comes from the chain via
# getdigidollardeploymentinfo — not hardcoded here.
#
# QUORUM_GREEN: at or above this count = comfortable, no alerts
# QUORUM_YELLOW: at or above this but below green = "getting thin" warning
# Below QUORUM_YELLOW but at/above consensus_required = red, at quorum edge
# Below consensus_required = CRITICAL — DD bundle signing may halt
#
# Defaults (tuned in v2.5.1, code fixed in v2.5.4): 12/10 for mainnet
# (35-slot roster, 7-of-35 quorum). The old 20/12 defaults produced
# yellow at 15/35 fresh — more than 2x the hard 7-of-35 floor — which
# conditioned operators to ignore the check. Override for testnet:
# GREEN=10, YELLOW=8.
QUORUM_GREEN=12
QUORUM_YELLOW=10

# Anti-flap — quorum alert throttling (v2.1)
# QUORUM_COOLDOWN: minimum minutes between quorum recovery alerts.
#   Escalation (getting worse) ALWAYS fires immediately regardless.
#   Only recovery (getting better) is throttled by this timer.
#   Set to 0 to disable cooldown (v2.0 behavior).
QUORUM_COOLDOWN=30

# QUORUM_HYSTERESIS: buffer above threshold required for recovery.
#   Prevents oscillation when the count hovers right at a boundary.
#   Example: GREEN=20, HYSTERESIS=3 → recovery to green needs 23+.
#   Set to 0 to disable hysteresis (v2.0 behavior).
QUORUM_HYSTERESIS=3

# ============================================================================
# LOAD EXTERNAL CONFIG (overrides defaults above)
# ============================================================================

# Determine config file path
if [ -n "$CONFIG_ARG" ]; then
    if [ ! -f "$CONFIG_ARG" ]; then
        echo "ERROR: Config file not found: $CONFIG_ARG"
        exit 1
    fi
    CONFIG_FILE="$CONFIG_ARG"
else
    CONFIG_FILE="${HOME}/.oracle-monitor/config"
fi

# Derive state directory from config file location
# (enables per-instance state when --config is used)
STATE_DIR=$(dirname "$CONFIG_FILE")

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

mkdir -p "$STATE_DIR"

# Runtime flag — set by --dry-run
DRY_RUN=false

# ============================================================================
# UPDATE CHECK (v2.6.0)
# ============================================================================
# Fetches the published script header from GitHub main and compares
# SCRIPT_VERSION. The version source is the shipped file itself — no
# separate VERSION file to drift. Cached per instance (STATE_DIR) for
# UPDATE_CHECK_TTL seconds. Memoized per run. Every failure mode is
# silent: the footer just stays one line and the monitor is unaffected.
# Never called in --dry-run (callers sit below the dry-run early return),
# so dry-run never fetches and never writes the cache file.

UPDATE_AVAILABLE=""
UPDATE_CHECKED=false

check_for_update() {
    [ "$UPDATE_CHECKED" = true ] && return 0
    UPDATE_CHECKED=true
    [ "${UPDATE_CHECK:-yes}" = "yes" ] || return 0

    local cache_file="${STATE_DIR}/update_check_cache"
    local now cached_ts remote_ver=""
    now=$(date +%s)

    # Serve from cache while fresh (line 1 = epoch of last attempt,
    # line 2 = version found, empty on a failed fetch)
    if [ -f "$cache_file" ]; then
        cached_ts=$(sed -n '1p' "$cache_file" 2>/dev/null)
        if [[ "$cached_ts" =~ ^[0-9]+$ ]] && [ $((now - cached_ts)) -lt "${UPDATE_CHECK_TTL:-86400}" ]; then
            remote_ver=$(sed -n '2p' "$cache_file" 2>/dev/null)
        fi
    fi

    # Cache miss or expired — fetch the published header (5s cap so a
    # GitHub outage can't stall a cron run). Cache the attempt either
    # way: a failed fetch caches empty, which stays silent and defers
    # the retry to the next TTL window instead of hammering on failure.
    if [ ! -f "$cache_file" ] || ! [[ "${cached_ts:-}" =~ ^[0-9]+$ ]] || [ $((now - ${cached_ts:-0})) -ge "${UPDATE_CHECK_TTL:-86400}" ]; then
        remote_ver=$(curl -sf --max-time 5 "$UPDATE_CHECK_URL" 2>/dev/null \
            | grep -m1 '^readonly SCRIPT_VERSION=' \
            | cut -d'"' -f2)
        printf '%s\n%s\n' "$now" "$remote_ver" > "$cache_file" 2>/dev/null
    fi

    # Newer only: sort -V picks the highest; if that isn't what we're
    # running, an update exists. Running a dev version ahead of the
    # published one correctly stays silent.
    if [ -n "$remote_ver" ] && [ "$remote_ver" != "$SCRIPT_VERSION" ]; then
        local newest
        newest=$(printf '%s\n%s\n' "$SCRIPT_VERSION" "$remote_ver" | sort -V | tail -1)
        [ "$newest" = "$remote_ver" ] && UPDATE_AVAILABLE="$remote_ver"
    fi
}

# Footer for Discord cards and emails — one line normally, two when an
# update is available. Single chokepoint so every card and email agrees.
build_footer() {
    check_for_update
    local footer="Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)"
    if [ -n "$UPDATE_AVAILABLE" ]; then
        footer="${footer}
⬆️ v${UPDATE_AVAILABLE} available — https://github.com/BaumerCrypto/digidollar-oracle-tools"
    fi
    printf '%s' "$footer"
}

# ============================================================================
# DIGIBYTE CORE VERSION CHECK (v2.6.3)
# ============================================================================
# Fetches the latest DigiByte Core release tag from the GitHub releases API
# and caches it per instance (STATE_DIR) for DIGIBYTE_UPDATE_TTL seconds.
# Same discipline as the self-update check above: memoized per run, silent
# on every failure (returns empty → check_version falls back to the plain
# ℹ️ line), and — because check_version runs during --dry-run — it never
# fetches or writes the cache in dry-run (serves any stale cache read-only).
# Uses the releases/latest endpoint, which GitHub only points at a real
# (non-prerelease) release, so operators are never nudged toward an RC.

DIGIBYTE_LATEST=""
DIGIBYTE_CHECKED=false

get_latest_digibyte_release() {
    # Memoize per run
    if [ "$DIGIBYTE_CHECKED" = true ]; then
        printf '%s' "$DIGIBYTE_LATEST"
        return 0
    fi
    DIGIBYTE_CHECKED=true

    [ "${DIGIBYTE_UPDATE_CHECK:-yes}" = "yes" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    local cache_file="${STATE_DIR}/digibyte_latest_cache"
    local ttl="${DIGIBYTE_UPDATE_TTL:-86400}"
    local now cached_ts
    now=$(date +%s)

    # Serve from cache while fresh (line 1 = epoch of last attempt,
    # line 2 = tag found, empty on a failed fetch)
    if [ -f "$cache_file" ]; then
        cached_ts=$(sed -n '1p' "$cache_file" 2>/dev/null)
        if [[ "$cached_ts" =~ ^[0-9]+$ ]] && [ $((now - cached_ts)) -lt "$ttl" ]; then
            DIGIBYTE_LATEST=$(sed -n '2p' "$cache_file" 2>/dev/null)
            printf '%s' "$DIGIBYTE_LATEST"
            return 0
        fi
    fi

    # v2.5.4 dry-run discipline: never fetch or write the cache in --dry-run.
    # Serve whatever (possibly stale) value the cache holds, read-only.
    if [ "${DRY_RUN:-false}" = true ]; then
        [ -f "$cache_file" ] && DIGIBYTE_LATEST=$(sed -n '2p' "$cache_file" 2>/dev/null)
        printf '%s' "$DIGIBYTE_LATEST"
        return 0
    fi

    # Cache miss or expired — fetch the latest release tag (8s cap so a
    # GitHub outage can't stall a cron run). Strip the leading "v" from the
    # tag ("v9.26.4" -> "9.26.4"). Cache the attempt either way: a failed
    # fetch caches empty, staying silent until the next TTL window.
    local latest
    latest=$(curl -sf --max-time 8 \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/DigiByte-Core/digibyte/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
    printf '%s\n%s\n' "$now" "$latest" > "$cache_file" 2>/dev/null

    DIGIBYTE_LATEST="$latest"
    printf '%s' "$DIGIBYTE_LATEST"
}

# ============================================================================
# NOTIFICATION FUNCTIONS — DISCORD + EMAIL
# ============================================================================

send_discord() {
    local color="$1"    # red=16711680, green=65280, yellow=16776960, blue=3447003
    local title="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # v2.5.3: prefix every individual alert title with NETWORK_LABEL (if set)
    # so dual-instance operators (e.g. testnet + mainnet on one VPS) can tell
    # which daemon fired the alert from the Discord card title alone, without
    # opening it. Single chokepoint — every alert_red/yellow/green/blue call
    # routes through here, so this covers Node Down, Oracle Stopped, Chain
    # Synced, Quorum Lost, etc. in one place instead of patching each call
    # site. No-op for single-instance operators who haven't set NETWORK_LABEL.
    if [ -n "${NETWORK_LABEL:-}" ]; then
        title="${NETWORK_LABEL} — ${title}"
    fi

    if [ "$DRY_RUN" = true ] || [ -z "$DISCORD_WEBHOOK" ]; then
        echo "[$(date)] ALERT: $title — $message"
        return
    fi

    # v2.5.4: payload built with jq -n so quotes/backslashes in
    # RPC-derived text can't silently break the webhook POST.
    # v2.6.0: footer via build_footer() — gains a second line when a
    # newer published version exists.
    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$message" \
        --argjson color "$color" \
        --arg footer "$(build_footer)" \
        --arg ts "$timestamp" \
        '{embeds: [{title: $title, description: $desc, color: $color, footer: {text: $footer}, timestamp: $ts}]}')
    curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" > /dev/null 2>&1
}

# ----------------------------------------------------------------------------
# send_email (v2.6.0, closes #17) — plain-text email via curl SMTP.
# Same triggers as Discord. No mailx/postfix/sendmail — curl ships with
# SMTP support on stock Ubuntu (verify: curl --version | grep smtp).
# Port 587 (default) = STARTTLS via --ssl-reqd; port 465 = smtps://.
# NETWORK_LABEL prefixes the subject at this single chokepoint, matching
# the v2.5.3 Discord title pattern, so dual-instance operators can tell
# which daemon fired the email from the subject line alone.
# ----------------------------------------------------------------------------

send_email() {
    local subject="$1"
    local body="$2"

    [ "${EMAIL_ENABLED}" = "true" ] || return 0

    # v2.5.3 parity: label the subject for dual-instance operators
    if [ -n "${NETWORK_LABEL:-}" ]; then
        subject="${NETWORK_LABEL} — ${subject}"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[$(date)] EMAIL would send to ${EMAIL_TO:-<not set>}: $subject"
        return 0
    fi

    # Essential fields — silently skip if not configured (mirrors the
    # empty-DISCORD_WEBHOOK behavior; --test-email diagnoses loudly)
    if [ -z "$EMAIL_TO" ] || [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ]; then
        return 0
    fi

    # Resolve display From and bare envelope address for --mail-from.
    # Handles both "Display Name <addr>" and bare "addr" formats.
    local from_display="${SMTP_FROM:-Oracle Monitor <${SMTP_USER}>}"
    local from_addr="$from_display"
    if [[ "$from_addr" == *"<"*">"* ]]; then
        from_addr="${from_addr##*<}"
        from_addr="${from_addr%%>*}"
    fi

    # Port 465 = implicit TLS (smtps://); everything else = STARTTLS
    local smtp_url
    if [ "${SMTP_PORT:-587}" = "465" ]; then
        smtp_url="smtps://${SMTP_SERVER:-smtp.gmail.com}:465"
    else
        smtp_url="smtp://${SMTP_SERVER:-smtp.gmail.com}:${SMTP_PORT:-587}"
    fi

    # Body: alert text + timestamp + the same footer the Discord cards
    # carry (including the update line when one is available)
    local full_body
    full_body="${body}

Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
$(build_footer)"

    # RFC 2822 message via temp file → curl --upload-file
    local tmpfile
    tmpfile=$(mktemp /tmp/oracle-alert-XXXXXX.eml 2>/dev/null) || return 1

    printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s\r\n' \
        "$from_display" "$EMAIL_TO" "$subject" "$full_body" > "$tmpfile"

    local curl_opts=(
        --silent
        --url "$smtp_url"
        --mail-from "$from_addr"
        --mail-rcpt "$EMAIL_TO"
        --user "${SMTP_USER}:${SMTP_PASS}"
        --upload-file "$tmpfile"
        --max-time 30
    )
    [ "${SMTP_PORT:-587}" != "465" ] && curl_opts+=(--ssl-reqd)

    curl "${curl_opts[@]}" > /dev/null 2>&1
    local exit_code=$?
    rm -f "$tmpfile"
    return $exit_code
}

# v2.6.0: each wrapper fires both channels on the same event. Email
# subjects carry the severity so inbox scanning works without opening.
alert_red()    { send_discord 16711680 "$1" "$2"; send_email "[ALERT] $1" "$2"; }
alert_yellow() { send_discord 16776960 "$1" "$2"; send_email "[WARNING] $1" "$2"; }
alert_green()  { send_discord 65280    "$1" "$2"; send_email "[RESOLVED] $1" "$2"; }
alert_blue()   { send_discord 3447003  "$1" "$2"; send_email "[INFO] $1" "$2"; }

# Only alert once per issue until it clears
# In --dry-run mode: always returns "should alert" but does NOT touch state files
should_alert() {
    local key="$1"
    local state_file="$STATE_DIR/$key"
    if [ "$DRY_RUN" = true ]; then
        return 0  # always "should alert" in dry-run, don't touch state
    fi
    if [ -f "$state_file" ]; then
        return 1  # already alerted
    fi
    touch "$state_file"
    return 0
}

# In --dry-run mode: always returns "nothing was set" and does NOT touch state files
clear_alert() {
    local key="$1"
    local state_file="$STATE_DIR/$key"
    if [ "$DRY_RUN" = true ]; then
        return 1  # pretend nothing was set, don't touch state
    fi
    if [ -f "$state_file" ]; then
        rm "$state_file"
        return 0  # was set, now cleared = recovery
    fi
    return 1  # wasn't set
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

ISSUES=0
WARNINGS=0
DETAILS=""

# --- Check 1: Is digibyted (or digibyte-qt) running? ---
# v2.5.2: Auto-detects either the headless daemon or the Qt GUI wallet.
# DAEMON_PROCESS can be set in config to force a specific match
# (e.g. DAEMON_PROCESS="digibyte-qt"). Default order: digibyted first,
# then digibyte-qt. Sets the DETECTED_DAEMON global so check_services()
# can branch — the Qt wallet typically runs outside systemd, so the
# systemd check is skipped with an INFO line when Qt is the daemon.
check_daemon() {
    local daemon_candidate

    if [ -n "${DAEMON_PROCESS:-}" ]; then
        # Explicit override from config
        if pgrep -x "$DAEMON_PROCESS" > /dev/null 2>&1; then
            DETECTED_DAEMON="$DAEMON_PROCESS"
        fi
    else
        # Auto-detect: headless daemon first, then Qt wallet
        for daemon_candidate in digibyted digibyte-qt; do
            if pgrep -x "$daemon_candidate" > /dev/null 2>&1; then
                DETECTED_DAEMON="$daemon_candidate"
                break
            fi
        done
    fi

    if [ -n "${DETECTED_DAEMON:-}" ]; then
        if clear_alert "daemon_down"; then
            alert_green "✅ Node Recovered" "$DETECTED_DAEMON is running again."
        fi
        DETAILS+="✅ Node: $DETECTED_DAEMON running\n"
    else
        if should_alert "daemon_down"; then
            alert_red "🔴 Node Down" "Neither digibyted nor digibyte-qt is running! For headless: \`sudo systemctl status ${SERVICE_NAME:-digibyted.service}\`. For Qt: launch the wallet."
        fi
        DETAILS+="🔴 Node: NOT RUNNING (checked digibyted, digibyte-qt)\n"
        ISSUES=$((ISSUES + 1))
        return 1  # skip remaining checks
    fi
    return 0
}

# --- Check 2: Is the oracle running and signing? ---
check_oracle() {
    local oracle_info
    oracle_info=$($CLI $WALLET_FLAG listoracle 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$oracle_info" ]; then
        if [ "$DD_ACTIVE" = "false" ]; then
            DETAILS+="ℹ️  Oracle: standby (DigiDollar deployment: $DD_STATUS)\n"
            return
        fi
        if should_alert "oracle_down"; then
            alert_red "🔴 Oracle Not Running" "listoracle returned no data. Oracle may need to be restarted."
        fi
        DETAILS+="🔴 Oracle: not responding\n"
        ISSUES=$((ISSUES + 1))
        return
    fi

    # Check if oracle is running (jq returns "true"/"false")
    local running
    running=$(echo "$oracle_info" | jq -r '.running // false' 2>/dev/null)

    if [ "$running" != "true" ]; then
        if should_alert "oracle_stopped"; then
            alert_red "🔴 Oracle Stopped" "Oracle ID $ORACLE_ID is loaded but not running. Check \`startoracle\`."
        fi
        DETAILS+="🔴 Oracle: stopped\n"
        ISSUES=$((ISSUES + 1))
    else
        if clear_alert "oracle_stopped"; then
            alert_green "✅ Oracle Recovered" "Oracle ID $ORACLE_ID is running and signing again."
        fi
        if clear_alert "oracle_down"; then
            alert_green "✅ Oracle Recovered" "Oracle ID $ORACLE_ID is responding again."
        fi

        # Get the price being reported
        local price
        price=$(echo "$oracle_info" | jq -r '.price_usd // "unknown"' 2>/dev/null)
        DETAILS+="✅ Oracle: running — reporting \$$price\n"
    fi
}

# --- Check 3: Chain sync status ---
check_chain() {
    local chain_info
    chain_info=$($CLI getblockchaininfo 2>/dev/null)

    if [ $? -ne 0 ]; then
        DETAILS+="⚠️  Chain: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local blocks headers chain
    blocks=$(echo "$chain_info" | jq -r '.blocks' 2>/dev/null)
    headers=$(echo "$chain_info" | jq -r '.headers' 2>/dev/null)
    chain=$(echo "$chain_info" | jq -r '.chain // "unknown"' 2>/dev/null)

    local behind=$((headers - blocks))

    if [ "$behind" -gt "$MAX_CHAIN_BEHIND" ]; then
        if should_alert "chain_behind"; then
            alert_yellow "⚠️  Chain Behind" "Node is $behind blocks behind (block $blocks / header $headers)."
        fi
        DETAILS+="⚠️  Chain: $behind blocks behind ($blocks / $headers)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "chain_behind"; then
            alert_green "✅ Chain Synced" "Node is synced at block $blocks."
        fi
        DETAILS+="✅ Chain: synced at block $blocks ($chain)\n"
    fi
}

# --- Check 4: Peer count ---
check_peers() {
    local peer_count
    peer_count=$($CLI getconnectioncount 2>/dev/null)

    if [ $? -ne 0 ]; then
        DETAILS+="⚠️  Peers: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    if [ "$peer_count" -lt "$MIN_PEERS" ]; then
        if should_alert "low_peers"; then
            alert_yellow "⚠️  Low Peers" "Only $peer_count peers connected (minimum: $MIN_PEERS)."
        fi
        DETAILS+="⚠️  Peers: $peer_count (low!)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "low_peers"; then
            alert_green "✅ Peers Recovered" "Peer count back to $peer_count."
        fi
        DETAILS+="✅ Peers: $peer_count connected\n"
    fi
}

# --- Check 5: Oracle consensus price ---
# v1.1: Also detects degraded consensus (status != "ok" with price_usd=0)
# v1.3: RC44 - handle "active" status enum in consensus check (RC43 returned "ok", RC44 returns "active")
# v1.4: RC44 - differentiate warning (notice) from error (alert) per RC44 enum (active/warning/error)
# v1.5: Replace dgb-oracle.service systemd check with listoracle RPC (fixes Type=oneshot false positive, closes #22)
# See: https://github.com/BaumerCrypto/digidollar-oracle-tools/issues/1
check_price() {
    local price_info
    price_info=$($CLI getoracleprice 2>/dev/null)

    if [ $? -ne 0 ]; then
        if [ "$DD_ACTIVE" = "false" ]; then
            DETAILS+="ℹ️  Price: pending (DigiDollar deployment: $DD_STATUS)\n"
            return
        fi
        DETAILS+="⚠️  Price: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local price_usd is_stale status oracle_count
    price_usd=$(echo "$price_info" | jq -r '.price_usd // "unknown"' 2>/dev/null)
    is_stale=$(echo "$price_info" | jq -r '.is_stale // false' 2>/dev/null)
    status=$(echo "$price_info" | jq -r '.status // "unknown"' 2>/dev/null)
    oracle_count=$(echo "$price_info" | jq -r '.oracle_count // 0' 2>/dev/null)

    # Check 5a: Stale price (v1.0)
    if [ "$is_stale" = "true" ]; then
        if should_alert "stale_price"; then
            alert_yellow "⚠️  Stale Price" "Oracle consensus price is stale. Last price: \$$price_usd"
        fi
        DETAILS+="⚠️  Price: STALE — \$$price_usd\n"
        WARNINGS=$((WARNINGS + 1))
    # Check 5b: Error status — real problem, alert operator (v1.4)
    elif [ "$status" = "error" ]; then
        if should_alert "degraded_consensus"; then
            alert_yellow "⚠️  Degraded Consensus" "Network status: $status | Price: \$$price_usd | Oracles: $oracle_count. Network aggregation is failing."
        fi
        DETAILS+="⚠️  Price: \$$price_usd (status: $status, oracles: $oracle_count)\n"
        WARNINGS=$((WARNINGS + 1))
    # Check 5c: Warning status — network notice, no Discord alert (v1.4)
    elif [ "$status" = "warning" ]; then
        DETAILS+="⚠️  Price: \$$price_usd (status: $status, oracles: $oracle_count)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "stale_price"; then
            alert_green "✅ Price Recovered" "Oracle price is fresh again: \$$price_usd"
        fi
        if clear_alert "degraded_consensus"; then
            alert_green "✅ Consensus Recovered" "Network consensus restored. Price: \$$price_usd"
        fi
        DETAILS+="✅ Price: \$$price_usd (fresh)\n"
    fi
}

# --- Check 6: Disk space ---
# v2.5.4: Watches the filesystem holding DISK_PATH (default /home) so
# datadirs on other mounts can be monitored. Numeric guard: a failed df
# now reads as "could not query" instead of a silent green line.
check_disk() {
    local df_line avail_gb total_gb used_pct size_info
    df_line=$(df -BG "${DISK_PATH:-/home}" 2>/dev/null | tail -1)
    avail_gb=$(echo "$df_line" | awk '{print $4}' | tr -d 'G')
    total_gb=$(echo "$df_line" | awk '{print $2}' | tr -d 'G')

    if [ -z "$avail_gb" ] || ! [[ "$avail_gb" =~ ^[0-9]+$ ]]; then
        DETAILS+="⚠️  Disk: could not query ${DISK_PATH:-/home}\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # v2.5.5: df column 2 is the filesystem total in 1G blocks — it was
    # always in the output, just never printed. Show it plus used% next
    # to free space. If the total is unparsable (nonstandard df), fall
    # back to the old free-only wording rather than showing garbage.
    size_info=""
    if [[ "$total_gb" =~ ^[0-9]+$ ]] && [ "$total_gb" -gt 0 ]; then
        used_pct=$(( (total_gb - avail_gb) * 100 / total_gb ))
        size_info=" of ${total_gb}GB (${used_pct}% used)"
    fi

    if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
        if should_alert "low_disk"; then
            # v2.5.5: three-line alert with hard newlines — mobile Discord
            # clients soft-wrap unpredictably without explicit breaks. The
            # datadir sits on its own line as a clean copy target. Wording
            # is generic ("old logs or unused chain data") because this
            # alert fires on mainnet too, not just testnet.
            alert_red "🔴 Low Disk Space" "Only ${avail_gb}GB free${size_info}."$'\n'"Clean up old logs or unused chain data in:"$'\n'"${DATADIR%/}/"
        fi
        DETAILS+="🔴 Disk: ${avail_gb}GB free${size_info} (LOW!)\n"
        ISSUES=$((ISSUES + 1))
    else
        if clear_alert "low_disk"; then
            alert_green "✅ Disk Space Recovered" "Disk space back to ${avail_gb}GB free${size_info}."
        fi
        DETAILS+="✅ Disk: ${avail_gb}GB free${size_info}\n"
    fi
}

# --- Check 7: Memory usage ---
check_memory() {
    local mem_pct
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

    if [ "$mem_pct" -gt "$MEM_THRESHOLD" ]; then
        if should_alert "high_memory"; then
            alert_yellow "⚠️  High Memory" "Memory usage at ${mem_pct}%."
        fi
        DETAILS+="⚠️  Memory: ${mem_pct}% used\n"
        WARNINGS=$((WARNINGS + 1))
    else
        clear_alert "high_memory" > /dev/null 2>&1
        DETAILS+="✅ Memory: ${mem_pct}% used\n"
    fi
}

# --- Check 12: Swap pressure (v2.4; pressure-gated in v2.6.2) ---
# v2.4 fired a yellow alert whenever swap usage exceeded SWAP_THRESHOLD_MB.
# v2.6.2 fixes a false positive Aussie Epic hit: a filled swap is NOT the
# same as memory pressure. After a -reindex (or any heavy transient) the
# kernel can page several GB out to swap and never page it back in — the
# fill just sits there, stale, long after the pressure ended. On a box
# later upgraded from 16GB to 32GB RAM this produced a permanent red swap
# alert while RAM sat at 40% used and nothing was actually stalling.
#
# So when swap is filled we now gate the alert on *current* pressure using
# two independent signals — either one firing raises the alert:
#   (1) PSI — /proc/pressure/memory "some avg10" > PSI_SWAP_THRESHOLD.
#       Linux 4.20+ gold standard: real stall time (%) in the last 10s.
#   (2) RAM headroom — RAM usage >= SWAP_MEM_HEADROOM_PCT.
#       Backstop for the (rare) kernel without PSI.
# If both signals are quiet, the fill is stale: shown as an ℹ️ line, not a
# warning, and any prior swap alert is cleared. If neither signal can be
# measured we fail safe and alert exactly as v2.4 did. Companion to the
# OOM protection in the hardening guide.
check_swap() {
    local swap_total_mb swap_used_mb
    swap_total_mb=$(free -m | awk '/Swap:/ {print $2}')
    swap_used_mb=$(free -m | awk '/Swap:/ {print $3}')

    # No swap configured — skip silently in normal checks, note in summary
    if [ "$swap_total_mb" -eq 0 ] 2>/dev/null; then
        DETAILS+="ℹ️  Swap: not configured\n"
        return
    fi

    # Swap at/below threshold — definitively fine. Clear any prior alert.
    if [ "$swap_used_mb" -le "$SWAP_THRESHOLD_MB" ]; then
        if clear_alert "swap_pressure"; then
            alert_green "✅ Swap Pressure Cleared" "Swap usage back to ${swap_used_mb}MB of ${swap_total_mb}MB."
        fi
        DETAILS+="✅ Swap: ${swap_used_mb}MB / ${swap_total_mb}MB\n"
        return
    fi

    # Swap is filled. Decide whether it reflects real *current* pressure.
    local mem_pct pressure=0 have_signal=0 reason="" psi_avg10="" stale_note=""

    # Signal 1: RAM headroom. RAM "used" already excludes buff/cache in
    # modern `free`, so this is genuinely-used memory, not disk cache.
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [ -n "$mem_pct" ] && [ "$mem_pct" -ge 0 ] 2>/dev/null; then
        have_signal=1
        stale_note="RAM ${mem_pct}%"
        if [ "$mem_pct" -ge "$SWAP_MEM_HEADROOM_PCT" ] 2>/dev/null; then
            pressure=1
            reason="RAM ${mem_pct}%"
        fi
    fi

    # Signal 2: PSI (Linux 4.20+). "some avg10" is a float like 0.00/12.34.
    if [ -r /proc/pressure/memory ]; then
        psi_avg10=$(awk '/^some/ {for (i=1;i<=NF;i++) if ($i ~ /^avg10=/) {sub(/avg10=/,"",$i); print $i; exit}}' /proc/pressure/memory 2>/dev/null)
        if [ -n "$psi_avg10" ]; then
            have_signal=1
            stale_note="${stale_note:+$stale_note, }PSI ${psi_avg10}"
            if awk "BEGIN{exit !($psi_avg10 > $PSI_SWAP_THRESHOLD)}" 2>/dev/null; then
                pressure=1
                reason="${reason:+$reason, }PSI some avg10=${psi_avg10}"
            fi
        fi
    fi

    if [ "$pressure" -eq 1 ]; then
        if should_alert "swap_pressure"; then
            alert_yellow "⚠️  Swap Pressure" "Swap usage: ${swap_used_mb}MB of ${swap_total_mb}MB with active memory pressure (${reason}). Check running processes."
        fi
        DETAILS+="⚠️  Swap: ${swap_used_mb}MB / ${swap_total_mb}MB used (pressure! — ${reason})\n"
        WARNINGS=$((WARNINGS + 1))
    elif [ "$have_signal" -eq 0 ]; then
        # No pressure signal measurable — fail safe, alert as v2.4 did.
        if should_alert "swap_pressure"; then
            alert_yellow "⚠️  Swap Pressure" "Swap usage: ${swap_used_mb}MB of ${swap_total_mb}MB (pressure signal unavailable). Check running processes."
        fi
        DETAILS+="⚠️  Swap: ${swap_used_mb}MB / ${swap_total_mb}MB used (filled; pressure unverifiable)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        # Filled but stale — no active pressure. Clear any prior alert.
        if clear_alert "swap_pressure"; then
            alert_green "✅ Swap Pressure Cleared" "Swap still at ${swap_used_mb}MB of ${swap_total_mb}MB but no active pressure (${stale_note}). Likely a stale fill from a past reindex/verify."
        fi
        DETAILS+="ℹ️  Swap: ${swap_used_mb}MB / ${swap_total_mb}MB used (stale — ${stale_note})\n"
    fi
}

# --- Check 8: Systemd service status ---
# v2.5: Reads SERVICE_NAME config var (defaults to digibyted.service).
#       Adds DD_ACTIVE guard for oracle process (standby → INFO not warn).
# v2.5.2: Skips systemd unit check with INFO line when the Qt wallet is
#         the running daemon (Qt typically runs outside systemd).
check_services() {
    local dgb_status oracle_status service_name
    service_name="${SERVICE_NAME:-digibyted.service}"

    # v2.6.3: explicit opt-out for operators who deliberately run headless
    # WITHOUT systemd (tmux/screen, Docker, runit, a hand-started -daemon).
    # SERVICE_NAME="none" (or "skip"/"disabled") replaces the systemd check
    # with an informational line instead of a red on a missing/idle unit.
    # The daemon and oracle-process checks still run — only the systemd
    # unit lookup is suppressed.
    case "$service_name" in
        none|None|NONE|skip|Skip|SKIP|disabled|Disabled|DISABLED)
            DETAILS+="ℹ️  Systemd: check disabled (SERVICE_NAME=\"none\")\n"
            ;;
        *)
            # v2.5.2: Skip systemd unit check when the Qt wallet is the
            # running daemon — most Qt operators launch the GUI outside
            # systemd, so `systemctl is-active` on the headless unit is a
            # misleading red.
            if [ "${DETECTED_DAEMON:-}" = "digibyte-qt" ]; then
                DETAILS+="ℹ️  Systemd: n/a — Qt wallet is the running daemon\n"
            else
                dgb_status=$(systemctl is-active "$service_name" 2>/dev/null)
                if [ "$dgb_status" = "active" ]; then
                    DETAILS+="✅ ${service_name}: active\n"
                else
                    DETAILS+="🔴 ${service_name}: $dgb_status\n"
                    ISSUES=$((ISSUES + 1))
                fi
            fi
            ;;
    esac

    oracle_status=$($CLI $WALLET_FLAG listoracle 2>/dev/null | jq -r ".running // \"unknown\"" 2>/dev/null)

    if [ "$DD_ACTIVE" = "false" ]; then
        DETAILS+="ℹ️  Oracle process: standby (DigiDollar deployment: $DD_STATUS)\n"
    elif [ "$oracle_status" = "true" ]; then
        DETAILS+="✅ Oracle process: running\n"
    else
        DETAILS+="⚠️  Oracle process: $oracle_status\n"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# --- Check 9: Node version (+ latest-release comparison, v2.6.3) ---
# v2.5: Read version via RPC (getnetworkinfo → .subversion) instead of
# `digibyted --version`. The old approach pulled whichever `digibyted`
# lived in $PATH, which read the wrong binary in dual-daemon setups.
# v2.6.2: strip the bitcoin-legacy /Name:Version/ wrapper for display.
# v2.6.3: compare the running version against the latest DigiByte Core
# release on GitHub and colour the icon accordingly:
#   ✅ green  — running the latest release (or newer, e.g. an RC ahead)
#   ℹ️ blue   — a newer release exists ("... — vX.Y.Z available")
#   ℹ️ blue   — can't determine latest (offline, API down, check disabled):
#              falls back to the plain v2.6.2 info line, no note.
check_version() {
    local version running_ver display_ver latest_ver
    version=$($CLI getnetworkinfo 2>/dev/null | jq -r .subversion 2>/dev/null)
    if [ -z "$version" ] || [ "$version" = "null" ]; then
        return
    fi

    # Bare numeric running version for comparison: /DigiByte:9.26.4/ -> 9.26.4
    running_ver=$(printf '%s' "$version" | sed -n 's|^/[^:]*:\(.*\)/$|\1|p')

    # Display label (v2.6.2): /DigiByte:9.26.4/ -> DigiByte: v9.26.4
    display_ver=$(printf '%s' "$version" | sed 's|^/\([^:]*\):\(.*\)/$|\1: v\2|')

    latest_ver=$(get_latest_digibyte_release)

    if [ -n "$latest_ver" ] && [ -n "$running_ver" ]; then
        local newest
        newest=$(printf '%s\n%s\n' "$running_ver" "$latest_ver" | sort -V | tail -1)
        if [ "$running_ver" = "$latest_ver" ] || [ "$newest" = "$running_ver" ]; then
            # running >= latest — up to date
            DETAILS+="✅ $display_ver\n"
        else
            # a newer release is out
            DETAILS+="ℹ️  $display_ver — v${latest_ver} available\n"
        fi
    else
        # can't determine latest — fail safe to the plain info line
        DETAILS+="ℹ️  $display_ver\n"
    fi
}

# --- Check 10: NTP time sync ---
# v2.5.4: degrades to "could not verify" on systems without timedatectl
# (containers, minimal images) instead of firing a false desync alert.
check_ntp() {
    if ! command -v timedatectl &>/dev/null; then
        DETAILS+="⚠️  NTP: could not verify (timedatectl not available)\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local synced
    synced=$(timedatectl status 2>/dev/null | grep -c "synchronized: yes")

    if [ "$synced" -eq 0 ]; then
        if should_alert "ntp_desync"; then
            alert_yellow "⚠️  NTP Desync" "System clock is NOT synchronized. Oracle timestamps may drift. Run: sudo timedatectl set-ntp on"
        fi
        DETAILS+="⚠️  NTP: NOT synchronized\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "ntp_desync"; then
            alert_green "✅ NTP Recovered" "System clock is synchronized again."
        fi
        DETAILS+="✅ NTP: synchronized\n"
    fi
}

# --- Quorum state machine helpers (v2.1) ---
# Maps quorum band names to numeric severity for comparison.
# Higher number = worse condition.
band_severity() {
    case "$1" in
        green)    echo 0 ;;
        yellow)   echo 1 ;;
        red)      echo 2 ;;
        critical) echo 3 ;;
        *)        echo 0 ;;
    esac
}

# --- Check 11: Quorum margin tracking (v2.0, closes #6) ---
# Counts how many oracles are actively reporting prices across the network.
# Compares against the on-chain quorum threshold from getdigidollardeploymentinfo.
# Also reports MuSig2 session health in the summary line.
#
# Alert bands (configurable via QUORUM_GREEN and QUORUM_YELLOW in config):
#   >= QUORUM_GREEN ............ Green — comfortable
#   >= QUORUM_YELLOW ........... Yellow — getting thin
#   >= consensus_required ...... Red — at quorum edge
#   < consensus_required ....... CRITICAL — DD may halt
#
# RPC FIELD NAMES (confirmed on RC44 testnet26 2026-06-09):
#   getdigidollardeploymentinfo → oracle_consensus_required, oracle_total_slots,
#     musig2_session.epoch, musig2_session.state ("complete"/other),
#     musig2_session.nonce_count, musig2_session.partial_sig_count,
#     musig2_session.creation_height
#   getoracles true → array of objects, each with heartbeat_status field
#     "reporting" = heartbeat_status == "fresh" (online + signed heartbeat
#     within the last 30 min). Stable across MuSig2 round transitions,
#     unlike last_price_usd which used to reset mid-round.
#
# Debug commands (if something looks wrong):
#   digibyte-cli -testnet getdigidollardeploymentinfo | jq .
#   digibyte-cli -testnet getoracles true | jq '.[0]'
#
check_quorum() {
    # --- Migration: clean up v2.0 state files (runs once, harmless after) ---
    # v2.5.4: skipped in dry-run — dry-run must not touch state.
    if [ "$DRY_RUN" != true ]; then
        rm -f "$STATE_DIR/quorum_yellow" "$STATE_DIR/quorum_red" "$STATE_DIR/quorum_critical"
    fi

    # --- Step 1: Get deployment info (quorum threshold + MuSig2 session) ---
    local deploy_info
    deploy_info=$($CLI getdigidollardeploymentinfo 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$deploy_info" ]; then
        DETAILS+="⚠️  Quorum: could not query deployment info\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local consensus_required total_slots
    consensus_required=$(echo "$deploy_info" | jq -r '.oracle_consensus_required // 7' 2>/dev/null)
    total_slots=$(echo "$deploy_info" | jq -r '.oracle_total_slots // 35' 2>/dev/null)

    # MuSig2 session health — included in summary line
    # Field names confirmed against RC44 testnet26 output (2026-06-09):
    #   .musig2_session.epoch             = signing epoch number
    #   .musig2_session.state             = "complete" / other (string, not boolean)
    #   .musig2_session.nonce_count       = nonces collected
    #   .musig2_session.partial_sig_count = partial sigs collected
    #   .musig2_session.creation_height   = block height when session was created
    local musig_epoch musig_state musig_nonces musig_sigs musig_detail
    musig_epoch=$(echo "$deploy_info" | jq -r '.musig2_session.epoch // "?"' 2>/dev/null)
    musig_state=$(echo "$deploy_info" | jq -r '.musig2_session.state // "?"' 2>/dev/null)
    musig_nonces=$(echo "$deploy_info" | jq -r '.musig2_session.nonce_count // "?"' 2>/dev/null)
    musig_sigs=$(echo "$deploy_info" | jq -r '.musig2_session.partial_sig_count // "?"' 2>/dev/null)

    # v2.5.6: musig_detail now carries its own status icon so the line
    # renders consistently alongside the other ✅/ℹ️/⚠️  health lines
    # instead of floating with a bare three-space indent. Icon captures
    # session state — no need for the trailing ✓ or "($state)" suffix.
    if [ "$musig_state" = "complete" ]; then
        musig_detail="✅ MuSig2: epoch $musig_epoch, ${musig_nonces}/${consensus_required} nonces, ${musig_sigs}/${consensus_required} sigs"
    elif [ "$musig_epoch" != "?" ]; then
        musig_detail="ℹ️  MuSig2: epoch $musig_epoch, ${musig_nonces}/${consensus_required} nonces, ${musig_sigs}/${consensus_required} sigs — $musig_state"
    else
        musig_detail="⚠️  MuSig2: could not parse session"
    fi

    # --- Step 2: Count reporting oracles ---
    local oracles
    oracles=$($CLI getoracles true 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$oracles" ]; then
        if [ "$DD_ACTIVE" = "false" ]; then
            DETAILS+="ℹ️  Quorum: standby (DigiDollar deployment: $DD_STATUS)\n"
            return
        fi
        DETAILS+="⚠️  Quorum: could not query oracles\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # Total oracles returned by getoracles true (active roster)
    local roster_count reporting
    roster_count=$(echo "$oracles" | jq 'length' 2>/dev/null)

    # Count oracles with fresh heartbeats as "reporting" (v2.2)
    # heartbeat_status "fresh" = online + signed heartbeat within 30 min.
    # This matches the dashboard's "Online Heartbeats" count and is stable
    # across MuSig2 round transitions (unlike last_price_usd which resets).
    reporting=$(echo "$oracles" | jq '[.[] | select(.heartbeat_status == "fresh")] | length' 2>/dev/null)

    # Fallback: if jq filter fails (field name mismatch), use roster count
    if [ -z "$reporting" ] || [ "$reporting" = "null" ]; then
        reporting="$roster_count"
        DETAILS+="⚠️  Quorum: could not count reporting oracles (heartbeat_status field missing?) — using roster count\n"
        WARNINGS=$((WARNINGS + 1))
    fi

    # --- Step 3: Determine raw quorum band ---
    local raw_band
    if [ "$reporting" -lt "$consensus_required" ]; then
        raw_band="critical"
    elif [ "$reporting" -lt "$QUORUM_YELLOW" ]; then
        raw_band="red"
    elif [ "$reporting" -lt "$QUORUM_GREEN" ]; then
        raw_band="yellow"
    else
        raw_band="green"
    fi

    # --- Step 4: Read previous state ---
    local state_file="$STATE_DIR/quorum_state"
    local prev_band="green" prev_time=0
    if [ -f "$state_file" ] && [ "$DRY_RUN" != true ]; then
        prev_band=$(awk '{print $1}' "$state_file" 2>/dev/null)
        prev_time=$(awk '{print $2}' "$state_file" 2>/dev/null)
        # Validate — default to green/0 if file is corrupt
        case "$prev_band" in green|yellow|red|critical) ;; *) prev_band="green" ;; esac
        [[ "$prev_time" =~ ^[0-9]+$ ]] || prev_time=0
    fi

    local raw_sev prev_sev now
    raw_sev=$(band_severity "$raw_band")
    prev_sev=$(band_severity "$prev_band")
    now=$(date +%s)

    # --- Step 5: Apply hysteresis to recovery ---
    # When recovering (raw is better than previous), require the count
    # to exceed the threshold by QUORUM_HYSTERESIS to actually transition.
    # This creates a dead zone that absorbs oscillation at boundaries.
    local effective_band="$raw_band"

    if [ "$raw_sev" -lt "$prev_sev" ] && [ "${QUORUM_HYSTERESIS:-0}" -gt 0 ] && [ "$DRY_RUN" != true ]; then
        local green_recover=$(( QUORUM_GREEN + QUORUM_HYSTERESIS ))
        local yellow_recover=$(( QUORUM_YELLOW + QUORUM_HYSTERESIS ))
        local red_recover=$(( consensus_required + QUORUM_HYSTERESIS ))

        # Evaluate what band the count actually clears with hysteresis applied.
        # Work from best to worst — first threshold met determines the band.
        # This correctly handles multi-band recovery (e.g. critical→green at 25/35).
        if [ "$reporting" -ge "$green_recover" ]; then
            effective_band="green"
        elif [ "$reporting" -ge "$yellow_recover" ]; then
            effective_band="yellow"
        elif [ "$reporting" -ge "$red_recover" ]; then
            effective_band="red"
        else
            effective_band="critical"
        fi
    fi

    local eff_sev
    eff_sev=$(band_severity "$effective_band")

    # --- Step 6: Decide whether to notify ---
    local should_notify=false update_state=false

    if [ "$DRY_RUN" = true ]; then
        # Dry-run: always "notify" (prints to terminal), never update state
        should_notify=true
    elif [ "$effective_band" != "$prev_band" ]; then
        if [ "$eff_sev" -gt "$prev_sev" ]; then
            # ESCALATION — always notify immediately, no cooldown
            should_notify=true
            update_state=true
        else
            # RECOVERY — check cooldown timer
            local elapsed=$(( now - prev_time ))
            local cooldown_secs=$(( ${QUORUM_COOLDOWN:-30} * 60 ))

            if [ "${QUORUM_COOLDOWN:-30}" -le 0 ] || [ "$prev_time" -eq 0 ] || [ "$elapsed" -ge "$cooldown_secs" ]; then
                should_notify=true
                update_state=true
            fi
            # If in cooldown: don't notify, don't update state.
            # Keeps "last notified" band so system doesn't silently oscillate.
        fi
    fi

    # --- Step 7: Fire alerts ---
    if [ "$should_notify" = true ] && [ "$effective_band" != "$prev_band" ]; then
        if [ "$eff_sev" -gt "$prev_sev" ]; then
            # Escalation alerts (getting worse)
            case "$effective_band" in
                critical)
                    alert_red "💀 QUORUM LOST" "Only $reporting/$total_slots oracles reporting. Need $consensus_required for consensus. DigiDollar signing may be halted!"
                    ;;
                red)
                    alert_red "🔴 Quorum At Edge" "Only $reporting/$total_slots oracles reporting (need $consensus_required). Network at risk if more drop."
                    ;;
                yellow)
                    alert_yellow "⚠️  Quorum Getting Thin" "$reporting/$total_slots oracles reporting (need $consensus_required). Comfortable is ${QUORUM_GREEN}+."
                    ;;
            esac
        else
            # Recovery alerts (getting better)
            case "$effective_band" in
                green)
                    alert_green "✅ Quorum Healthy" "$reporting/$total_slots reporting — comfortable margin."
                    ;;
                yellow)
                    alert_green "✅ Quorum Margin Improving" "$reporting/$total_slots reporting — no longer at edge."
                    ;;
                red)
                    alert_green "✅ Quorum Recovering" "Up to $reporting/$total_slots reporting (need $consensus_required). Still at edge, but improving."
                    ;;
            esac
        fi
    fi

    # --- Step 8: Update state file ---
    if [ "$update_state" = true ]; then
        echo "$effective_band $now" > "$state_file"
    fi

    # --- Step 9: Update DETAILS for summary ---
    case "$effective_band" in
        critical)
            DETAILS+="💀 Quorum: $reporting/$total_slots reporting (need $consensus_required) — CRITICAL\n"
            ISSUES=$((ISSUES + 1))
            ;;
        red)
            DETAILS+="🔴 Quorum: $reporting/$total_slots reporting (need $consensus_required) — at edge\n"
            ISSUES=$((ISSUES + 1))
            ;;
        yellow)
            DETAILS+="⚠️  Quorum: $reporting/$total_slots reporting (need $consensus_required) — getting thin\n"
            WARNINGS=$((WARNINGS + 1))
            ;;
        green)
            DETAILS+="✅ Quorum: $reporting/$total_slots reporting (need $consensus_required) — healthy\n"
            ;;
    esac
    DETAILS+="$musig_detail\n"
}

# ============================================================================
# SUMMARY REPORT (--summary and --dry-run)
# ============================================================================

send_summary() {
    check_digidollar_active   # v2.5: must run before oracle-dependent checks
    check_daemon || return
    check_oracle
    check_chain
    check_peers
    check_price
    check_disk
    check_memory
    check_swap                # v2.4
    check_services
    check_version
    check_ntp
    check_quorum

    local color=65280  # green
    local status="✅ All Systems Healthy"

    if [ $ISSUES -gt 0 ]; then
        color=16711680  # red
        status="🔴 $ISSUES Issues Detected"
    elif [ $WARNINGS -gt 0 ]; then
        color=16776960  # yellow
        status="⚠️  $WARNINGS Warnings"
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null || uptime)

    local desc
    desc=$(echo -e "$DETAILS\n⏱️ Uptime: $uptime_str")

    if [ "$DRY_RUN" = true ] || [ -z "$DISCORD_WEBHOOK" ]; then
        echo "======================================="
        echo " ${NETWORK_LABEL:-Oracle} Health Summary — $(date)"
        echo "======================================="
        echo -e "$desc"
        echo "======================================="
        # v2.6.0: no webhook configured but email is → still email the
        # summary (email-only operators are the point of #17). Dry-run
        # is handled inside send_email (prints, sends nothing).
        if [ "$DRY_RUN" != true ] && [ "${EMAIL_ENABLED}" = "true" ]; then
            send_email "$status — Health Summary" "$desc"
        fi
        return
    fi

    # v2.6.0: email fires alongside the Discord card. send_email
    # prefixes NETWORK_LABEL itself (chokepoint), so the subject passed
    # here is label-free to avoid doubling.
    send_email "$status — Health Summary" "$desc"

    # v2.5.4: payload built with jq -n (matches send_discord hardening).
    # v2.6.0: footer via build_footer() — two lines when an update exists.
    local payload
    payload=$(jq -n \
        --arg title "$status — ${NETWORK_LABEL:-Oracle} Health Summary" \
        --arg desc "$desc" \
        --argjson color "$color" \
        --arg footer "$(build_footer)" \
        --arg ts "$timestamp" \
        '{embeds: [{title: $title, description: $desc, color: $color, footer: {text: $footer}, timestamp: $ts}]}')
    curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" > /dev/null 2>&1
}

# ============================================================================
# MAIN — Normal health check (alerts only on problems/recovery)
# ============================================================================

# --- Pre-flight: DigiDollar activation status (v2.5) ---
# Sets globals DD_STATUS and DD_ACTIVE so other checks know whether to
# alert on missing oracle data (post-activation) or downgrade to info
# (pre-activation). Called first from both run_checks() and send_summary()
# — the --dry-run and --summary flags route through send_summary, so the
# pre-flight must live in both paths. Always succeeds; DD_ACTIVE defaults
# to "false" if the RPC fails or DigiDollar is not yet deployed.
check_digidollar_active() {
    local deploy_info
    deploy_info=$($CLI getdigidollardeploymentinfo 2>/dev/null)

    if [ -z "$deploy_info" ]; then
        DD_STATUS="unknown"
        DD_ACTIVE="false"
        return
    fi

    DD_STATUS=$(echo "$deploy_info" | jq -r '.status // "unknown"' 2>/dev/null)

    if [ "$DD_STATUS" = "active" ]; then
        DD_ACTIVE="true"
    else
        DD_ACTIVE="false"
    fi
}

run_checks() {
    check_digidollar_active   # v2.5: must run before oracle-dependent checks
    check_daemon || return
    check_oracle
    check_chain
    check_peers
    check_price
    check_disk
    check_memory
    check_swap                # v2.4
    check_ntp
    check_quorum
}

# ============================================================================
# ENTRY POINT
# ============================================================================

case "$ACTION_FLAG" in
    --summary)
        send_summary
        ;;
    --dry-run)
        DRY_RUN=true
        send_summary
        ;;
    --test)
        echo "Testing Discord webhook..."
        if [ -z "$DISCORD_WEBHOOK" ]; then
            echo "ERROR: DISCORD_WEBHOOK is not set."
            echo "Configure it in: $CONFIG_FILE"
            exit 1
        fi
        # v2.5.4: label lives in the title only (send_discord prefixes
        # NETWORK_LABEL) — no more "Mainnet — ... Mainnet monitor..." doubling.
        alert_blue "🔧 Test Alert" "Oracle monitor is configured and working! $(date)"
        echo "Check your Discord channel."
        if [ "${EMAIL_ENABLED}" = "true" ]; then
            echo "(Email is enabled — a test email was sent too. To test email alone: $0 --test-email)"
        fi
        ;;
    --test-email)
        echo "Testing email configuration..."
        if [ "${EMAIL_ENABLED}" != "true" ]; then
            echo "ERROR: EMAIL_ENABLED is not set to true."
            echo "       Set it in: $CONFIG_FILE"
            exit 1
        fi
        if [ -z "$EMAIL_TO" ] || [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ]; then
            echo "ERROR: EMAIL_TO, SMTP_USER, and SMTP_PASS must all be set."
            echo "       Configure them in: $CONFIG_FILE"
            exit 1
        fi
        if ! curl --version 2>/dev/null | grep -qi smtp; then
            echo "ERROR: this curl build has no SMTP support."
            echo "       Check: curl --version | grep -i smtp"
            exit 1
        fi
        echo "Sending test email to $EMAIL_TO via ${SMTP_SERVER}:${SMTP_PORT}..."
        if send_email "🔧 Test Email" "Oracle monitor email alerts are configured and working."; then
            echo "✓ Test email sent — check your inbox (and spam folder)."
        else
            echo "✗ Send failed. Check SMTP settings in: $CONFIG_FILE"
            echo "  Common issues:"
            echo "    - Gmail: SMTP_PASS must be an App Password, not your account password"
            echo "      (Google Account > Security > 2-Step Verification, then App passwords)"
            echo "    - Outlook/365: SMTP_SERVER=smtp.office365.com, SMTP_PORT=587"
            echo "    - Wrong SMTP_PORT for your provider (587=STARTTLS, 465=implicit TLS)"
            echo "    - Firewall blocking outbound port ${SMTP_PORT} (check: ufw status)"
            exit 1
        fi
        ;;
    *)
        run_checks
        ;;
esac
