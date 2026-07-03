#!/bin/bash
###############################################################################
# oracle-monitor-macos.sh — DGB Oracle Health Monitor with Discord Alerts (macOS)
# Version: 2.5.4-macos.1
#
# macOS port of my oracle-monitor.sh v2.5.3 (Linux). Same checks, same quorum
# state machine, same anti-flap logic, same DigiDollar BIP9 pre-activation
# guard, same auto-detect for headless vs Qt wallet — BSD/macOS-native
# commands. Written for the stock /bin/bash 3.2 that ships with every Mac
# (no Homebrew bash needed). The only dependency is jq.
#
# Author: digibyte-maxi (Oracle ID 17) | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 — July 2026
readonly SCRIPT_VERSION="2.5.4-macos.1"
#
# SETUP:
#   1. Copy this script to your Mac: ~/oracle-monitor-macos.sh
#   2. chmod +x ~/oracle-monitor-macos.sh
#   3. Install jq (one time): brew install jq
#   4. Create config: mkdir -p ~/.oracle-monitor && cp config-macos.template ~/.oracle-monitor/config
#   5. Edit config: Set your Discord webhook URL and oracle settings
#   6. Test it: ./oracle-monitor-macos.sh --dry-run
#   7. Test webhook: ./oracle-monitor-macos.sh --test
#   8. Add to cron: crontab -e
#      */5 * * * * /Users/YOUR_USER/oracle-monitor-macos.sh 2>/dev/null
#      0 */12 * * * /Users/YOUR_USER/oracle-monitor-macos.sh --summary 2>/dev/null
#
#      macOS notes:
#      - Use the full /Users/YOURNAME path — cron does not expand ~.
#      - On first run macOS may prompt to give cron Full Disk Access
#        (System Settings > Privacy & Security > Full Disk Access > add
#        /usr/sbin/cron). Only needed if your datadir sits somewhere
#        cron can't read.
#      - Your Mac must be AWAKE for cron to fire. On a laptop, either
#        keep it plugged in with "Prevent automatic sleeping on power
#        adapter" enabled (System Settings > Battery > Options), or run
#        `caffeinate -s` in a spare terminal. A sleeping Mac = a silent
#        monitor = a dead oracle you don't hear about.
#
# FLAGS:
#   (none)     Normal health check — alerts only on problems/recovery
#   --summary  Full status summary — always sends to Discord
#   --dry-run  Runs all checks, prints to terminal, skips Discord, no state changes
#   --watch    Live console dashboard — refreshes the full status every 60s
#              (or --watch 30 for 30s). Never alerts, never touches state:
#              safe to leave open in a Terminal window alongside cron.
#   --test     Sends a test embed to Discord to verify webhook
#   --config /path  Use alternate config file (enables dual-instance monitoring)
#
# CRON SCHEDULE:
#   */5 = every 5 minutes for health checks (alerts only on problems)
#   0 */12 = every 12 hours for a full status summary (always sends)
#
# CHANGELOG:
#   v2.5.4-macos.1 — Full-repo audit fixes (July 2026), matching Linux
#          v2.5.4. (1) Discord payloads built with jq -n — a quote or
#          backslash in RPC-derived text could previously break the
#          webhook POST silently. (2) check_services launchd check now
#          matches the LaunchAgent label exactly (a substring grep could
#          false-positive on partially matching labels, e.g.
#          org.digibyte.digibyted matching org.digibyte.digibyted-main).
#          (3) --test no longer double-labels the card when
#          NETWORK_LABEL is set.
#   v2.5.3-macos.1 — send_discord() now prefixes every individual alert
#          title with NETWORK_LABEL (when set), not just the health summary
#          and --test alert. Fixes dual-instance operators (testnet+mainnet
#          on one box) getting an unlabeled "Node Down" card with no way to
#          tell which daemon fired it. Single chokepoint — every alert_red/
#          yellow/green/blue call routes through send_discord(). No-op for
#          single-instance operators without NETWORK_LABEL set. Ports the
#          fix shipped in oracle-monitor.sh v2.5.3.
#   v2.5.2-macos.1 — check_daemon() now auto-detects either digibyted
#          (headless) or the Qt GUI wallet. Tries multiple Qt process-name
#          conventions (DigiByte-Qt, Digibyte-Qt, digibyte-qt) in order —
#          first match wins. Sets DETECTED_DAEMON global so
#          check_services() can branch: the launchd check is skipped with
#          an INFO line when the Qt wallet is the detected daemon (Qt
#          typically runs outside launchd, so a "not loaded" red would be
#          a false alert). Optional DAEMON_PROCESS config override pins
#          monitoring to a specific process name. Full parity with Linux
#          v2.5.2.
#   v2.5.1-macos.1 — Add SCRIPT_VERSION constant + NETWORK_LABEL in the
#          Discord card titles, dry-run header, and --test output. Tune
#          default quorum bands from 20/12 → 12/10 (v2.0 defaults fired
#          yellow at 15/35 fresh — 2x the hard 7-of-35 floor). Quorum
#          counting stays on heartbeat_status=="fresh" from v2.2.
#   v2.5-macos.1 — DigiDollar BIP9 pre-activation guard. New
#          check_digidollar_active() sets DD_STATUS/DD_ACTIVE globals via
#          getdigidollardeploymentinfo, called first in both run_checks()
#          and send_summary() (--dry-run/--summary/--watch route through
#          send_summary, so the pre-flight must live in every entry).
#          check_oracle, check_price, check_services, check_quorum all
#          downgrade "no data" to standby INFO instead of red while
#          DD_ACTIVE=false. check_version now reads $CLI getnetworkinfo →
#          .subversion instead of a raw `digibyted --version` invocation
#          (which failed for Qt-wallet operators — no digibyted binary
#          on PATH).
#   v2.4-macos.1 — Add swap pressure detection (Check #12). Fires a
#          yellow alert when swap usage exceeds SWAP_THRESHOLD_MB (default
#          100 MB). Uses `sysctl vm.swapusage` for the read — parses used/
#          total from the standard format "vm.swapusage: total = X.XXM
#          used = Y.YYM ...". (fixes #26 on macOS, suggested by shenger)
#   v2.3-macos.1 — Add --config /path flag for dual-instance monitoring.
#          Two cron entries + two config files = independent testnet and
#          mainnet monitoring from one Mac. State files auto-separate per
#          config directory via dirname. Argument parsing restructured:
#          while loop replaces positional case, handles --config + action
#          flags in any order.
#   v2.2-macos.1 — Initial macOS port. Logic parity with Linux v2.2:
#          heartbeat-based quorum counting, anti-flap cooldown +
#          hysteresis, single quorum_state file, escalation always
#          immediate. Platform adaptations: vm_stat + sysctl replace
#          free, `df -g` replaces `df -BG`, sntp offset measurement
#          replaces timedatectl, optional launchctl label check replaces
#          systemctl. NTP green-line output matches Linux exactly
#          ("synchronized") while still measuring offset internally so a
#          drifting clock fires a yellow alert with the offset value.
#          Node version via `digibyted --version` (same full
#          string as Linux) with getnetworkinfo RPC as fallback when the
#          daemon binary isn't reachable. Process name configurable
#          (DAEMON_PROCESS) for digibyted vs DigiByte-Qt. Verified
#          bash-3.2 compatible (stock macOS /bin/bash).
#
#   Linux lineage this port tracks (see oracle-monitor.sh for details):
#   v2.5.2 — headless/Qt auto-detect      v2.5.1 — version + label + footer
#   v2.5 — DD BIP9 guard (#27)            v2.4 — swap pressure (#26)
#   v2.3 — --config dual-instance (#23)   v2.2 — heartbeat_status quorum
#   v2.1.1 — hysteresis fix               v2.1 — anti-flap
#   v2.0 — quorum margin (#6)             v1.5 — listoracle RPC (#22)
#   v1.4 — warning/error enum (#21)       v1.3 — RC44 status enum
#   v1.2 — config file, dry-run           v1.1 — degraded consensus, NTP
#   v1.0 — initial release
#
###############################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Run: brew install jq"
    exit 1
fi

# ============================================================================
# ARGUMENT PARSING (before config loading — --config must be extracted first)
# ============================================================================

ACTION_FLAG=""
CONFIG_ARG=""
WATCH_INTERVAL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                echo "ERROR: --config requires a path argument."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --watch [seconds]]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --dry-run|--summary|--test)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --watch [seconds]]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        --watch)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --watch [seconds]]"
                exit 1
            fi
            ACTION_FLAG="--watch"
            # Optional numeric interval after --watch
            if [ -n "${2:-}" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL="$2"
                shift 2
            else
                shift
            fi
            ;;
        *)
            echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --watch [seconds]]"
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

# Oracle settings
ORACLE_ID=0
ORACLE_NAME="my-oracle"
CLI="digibyte-cli -testnet"
WALLET_FLAG="-rpcwallet=oracle"

# v2.5.2: The monitor auto-detects either "digibyted" (headless) or the
# Qt GUI wallet under three known naming conventions (DigiByte-Qt,
# Digibyte-Qt, digibyte-qt). Leave DAEMON_PROCESS unset (default) for
# auto-detect. Set it in ~/.oracle-monitor/config only if you run both
# binaries on the same Mac and want to pin monitoring to one:
#   DAEMON_PROCESS="digibyted"     # headless daemon
#   DAEMON_PROCESS="DigiByte-Qt"   # Qt wallet (verify with `pgrep -x`)

# Optional: launchd label if you run digibyted via a LaunchAgent
# (e.g. "org.digibyte.digibyted"). Leave "" to use the process check.
# Ignored automatically when the Qt wallet is the detected daemon.
LAUNCHD_LABEL=""

# Path whose volume is watched for free disk space. The DigiByte datadir
# on macOS is ~/Library/Application Support/DigiByte — on most Macs that
# is the same volume as $HOME, so the default is fine.
DISK_PATH="${HOME}"

# Thresholds — basic health
MIN_PEERS=3
MIN_DISK_GB=5
STALE_PRICE_MINUTES=30  # Reserved for future use — staleness currently from RPC
MEM_THRESHOLD=90
SWAP_THRESHOLD_MB=100
MAX_CHAIN_BEHIND=10

# NTP check — measures actual clock offset against a time server with one
# sntp query (macOS has no timedatectl). Oracle bundle timestamps are
# rejected past 3600s skew, so keep this tight.
NTP_SERVER="time.apple.com"
NTP_MAX_OFFSET="1.0"

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

# Determine config file path (v2.3: --config /path overrides default)
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
# DISCORD NOTIFICATION FUNCTIONS
# ============================================================================

send_discord() {
    local color="$1"    # red=16711680, green=65280, yellow=16776960, blue=3447003
    local title="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # v2.5.3-macos.1: prefix every individual alert title with NETWORK_LABEL
    # (if set) so dual-instance operators (e.g. testnet + mainnet on one box)
    # can tell which daemon fired the alert from the Discord card title alone.
    # Single chokepoint — every alert_red/yellow/green/blue call routes
    # through here. No-op for single-instance operators without NETWORK_LABEL
    # set. Ports the same fix shipped in oracle-monitor.sh v2.5.3.
    if [ -n "${NETWORK_LABEL:-}" ]; then
        title="${NETWORK_LABEL} — ${title}"
    fi

    if [ "$DRY_RUN" = true ] || [ -z "$DISCORD_WEBHOOK" ]; then
        echo "[$(date)] ALERT: $title — $message"
        return
    fi

    # v2.5.4-macos.1: payload built with jq -n so quotes/backslashes in
    # RPC-derived text can't silently break the webhook POST.
    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$message" \
        --argjson color "$color" \
        --arg footer "Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)" \
        --arg ts "$timestamp" \
        '{embeds: [{title: $title, description: $desc, color: $color, footer: {text: $footer}, timestamp: $ts}]}')
    curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" > /dev/null 2>&1
}

alert_red()    { send_discord 16711680 "$1" "$2"; }
alert_yellow() { send_discord 16776960 "$1" "$2"; }
alert_green()  { send_discord 65280    "$1" "$2"; }
alert_blue()   { send_discord 3447003  "$1" "$2"; }

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

# --- Check 1: Is digibyted (or DigiByte-Qt) running? ---
# v2.5.2: Auto-detects either the headless daemon or the Qt GUI wallet.
# DAEMON_PROCESS can be set in config to force a specific match. Default
# order: digibyted first, then Qt wallet under three naming conventions
# (DigiByte-Qt, Digibyte-Qt, digibyte-qt) — first match wins. The macOS
# Qt process name has never been standardized across releases, so we
# try all three to make the port robust. Sets DETECTED_DAEMON to the
# actual matched name so check_services() can branch (launchd usually
# doesn't manage Qt) and so the Discord "running" line shows what the
# monitor actually found. pgrep -x requires exact match on each attempt.
check_daemon() {
    local daemon_candidate

    if [ -n "${DAEMON_PROCESS:-}" ]; then
        # Explicit override from config
        if pgrep -x "$DAEMON_PROCESS" > /dev/null 2>&1; then
            DETECTED_DAEMON="$DAEMON_PROCESS"
        fi
    else
        # Auto-detect: headless first, then Qt wallet under each known name
        for daemon_candidate in digibyted DigiByte-Qt Digibyte-Qt digibyte-qt; do
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
            alert_red "🔴 Node Down" "No DigiByte node process running! Checked: digibyted, DigiByte-Qt, Digibyte-Qt, digibyte-qt. For headless: check launchctl if you run it as a LaunchAgent. For Qt: launch the wallet app."
        fi
        DETAILS+="🔴 Node: NOT RUNNING (checked digibyted, DigiByte-Qt, Digibyte-Qt, digibyte-qt)\n"
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
        DETAILS+="⚠️ Chain: could not query\n"
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
            alert_yellow "⚠️ Chain Behind" "Node is $behind blocks behind (block $blocks / header $headers)."
        fi
        DETAILS+="⚠️ Chain: $behind blocks behind ($blocks / $headers)\n"
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
        DETAILS+="⚠️ Peers: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    if [ "$peer_count" -lt "$MIN_PEERS" ]; then
        if should_alert "low_peers"; then
            alert_yellow "⚠️ Low Peers" "Only $peer_count peers connected (minimum: $MIN_PEERS)."
        fi
        DETAILS+="⚠️ Peers: $peer_count (low!)\n"
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
# v1.3: RC44 - handle "active" status enum in consensus check
# v1.4: RC44 - differentiate warning (notice) from error (alert) per RC44 enum
# v1.5: listoracle RPC replaces service checks (#22)
check_price() {
    local price_info
    price_info=$($CLI getoracleprice 2>/dev/null)

    if [ $? -ne 0 ]; then
        if [ "$DD_ACTIVE" = "false" ]; then
            DETAILS+="ℹ️  Price: pending (DigiDollar deployment: $DD_STATUS)\n"
            return
        fi
        DETAILS+="⚠️ Price: could not query\n"
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
            alert_yellow "⚠️ Stale Price" "Oracle consensus price is stale. Last price: \$$price_usd"
        fi
        DETAILS+="⚠️ Price: STALE — \$$price_usd\n"
        WARNINGS=$((WARNINGS + 1))
    # Check 5b: Error status — real problem, alert operator (v1.4)
    elif [ "$status" = "error" ]; then
        if should_alert "degraded_consensus"; then
            alert_yellow "⚠️ Degraded Consensus" "Network status: $status | Price: \$$price_usd | Oracles: $oracle_count. Network aggregation is failing."
        fi
        DETAILS+="⚠️ Price: \$$price_usd (status: $status, oracles: $oracle_count)\n"
        WARNINGS=$((WARNINGS + 1))
    # Check 5c: Warning status — network notice, no Discord alert (v1.4)
    elif [ "$status" = "warning" ]; then
        DETAILS+="⚠️ Price: \$$price_usd (status: $status, oracles: $oracle_count)\n"
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
# BSD df has no -B flag. -g reports in 1G blocks; column 4 = available.
check_disk() {
    local avail_gb
    avail_gb=$(df -g "$DISK_PATH" 2>/dev/null | tail -1 | awk '{print $4}')

    if [ -z "$avail_gb" ] || ! [[ "$avail_gb" =~ ^[0-9]+$ ]]; then
        DETAILS+="⚠️ Disk: could not query $DISK_PATH\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
        if should_alert "low_disk"; then
            alert_red "🔴 Low Disk Space" "Only ${avail_gb}GB free. Clean up old testnet dirs or logs."
        fi
        DETAILS+="🔴 Disk: ${avail_gb}GB free (LOW!)\n"
        ISSUES=$((ISSUES + 1))
    else
        if clear_alert "low_disk"; then
            alert_green "✅ Disk Space Recovered" "Disk space back to ${avail_gb}GB free."
        fi
        DETAILS+="✅ Disk: ${avail_gb}GB free\n"
    fi
}

# --- Check 7: Memory usage ---
# macOS has no `free`. Used% is computed from vm_stat page counts against
# sysctl hw.memsize. "Available" here = free + inactive + speculative
# pages — an approximation of what macOS can hand out without swapping.
# macOS deliberately keeps RAM full of cache, so don't panic at 70-80%;
# the default 90% threshold only fires under real pressure.
check_memory() {
    local page_size total_bytes vm free_pages inactive_pages spec_pages
    page_size=$(sysctl -n hw.pagesize 2>/dev/null)
    total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
    vm=$(vm_stat 2>/dev/null)

    if [ -z "$page_size" ] || [ -z "$total_bytes" ] || [ -z "$vm" ]; then
        DETAILS+="⚠️ Memory: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    free_pages=$(echo "$vm"     | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
    inactive_pages=$(echo "$vm" | awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
    spec_pages=$(echo "$vm"     | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')

    [ -z "$free_pages" ] && free_pages=0
    [ -z "$inactive_pages" ] && inactive_pages=0
    [ -z "$spec_pages" ] && spec_pages=0

    local mem_pct
    mem_pct=$(echo "$page_size $total_bytes $free_pages $inactive_pages $spec_pages" | \
        awk '{avail=($3+$4+$5)*$1; used=$2-avail; printf "%.0f", used/$2*100}')

    if [ -z "$mem_pct" ]; then
        DETAILS+="⚠️ Memory: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    if [ "$mem_pct" -gt "$MEM_THRESHOLD" ]; then
        if should_alert "high_memory"; then
            alert_yellow "⚠️ High Memory" "Memory usage at ${mem_pct}%."
        fi
        DETAILS+="⚠️ Memory: ${mem_pct}% used\n"
        WARNINGS=$((WARNINGS + 1))
    else
        clear_alert "high_memory" > /dev/null 2>&1
        DETAILS+="✅ Memory: ${mem_pct}% used\n"
    fi
}

# --- Check 12: Swap pressure (v2.4) ---
# Fires a yellow alert when swap usage exceeds SWAP_THRESHOLD_MB.
# On a memory-tight box, any meaningful swap usage signals real pressure —
# the exact condition that silently killed daemons during the PRE stale
# incident (June 2026, on Linux). macOS reports dynamic swap via
# `sysctl vm.swapusage`, output format:
#   vm.swapusage: total = 2048.00M  used = 512.30M  free = 1535.70M  (encrypted)
# We parse the numeric part of the "total = X.XXM" and "used = X.XXM" tokens
# and round to whole MB for the threshold comparison. macOS reports zero
# total on systems with no swap file allocated (SSD-only, or SIP-restricted
# minimalist setups) — in that case we skip with an INFO line.
check_swap() {
    local swap_line swap_total_mb swap_used_mb
    swap_line=$(sysctl -n vm.swapusage 2>/dev/null)

    if [ -z "$swap_line" ]; then
        DETAILS+="ℹ️  Swap: could not query (sysctl vm.swapusage failed)\n"
        return
    fi

    # awk pulls the value that follows the "total =" / "used =" tokens,
    # strips the trailing M, and rounds to an integer MB.
    swap_total_mb=$(echo "$swap_line" | awk '{
        for (i=1;i<=NF;i++) if ($i=="total") { gsub(/M$/,"",$(i+2)); printf "%.0f", $(i+2); exit }
    }')
    swap_used_mb=$(echo "$swap_line" | awk '{
        for (i=1;i<=NF;i++) if ($i=="used") { gsub(/M$/,"",$(i+2)); printf "%.0f", $(i+2); exit }
    }')

    # Guard against empty parses (unexpected sysctl format)
    if [ -z "$swap_total_mb" ] || [ -z "$swap_used_mb" ]; then
        DETAILS+="ℹ️  Swap: could not parse sysctl output\n"
        return
    fi

    # No swap configured
    if [ "$swap_total_mb" -eq 0 ] 2>/dev/null; then
        DETAILS+="ℹ️  Swap: not configured\n"
        return
    fi

    if [ "$swap_used_mb" -gt "$SWAP_THRESHOLD_MB" ]; then
        if should_alert "swap_pressure"; then
            alert_yellow "⚠️ Swap Pressure" "Swap usage: ${swap_used_mb}MB of ${swap_total_mb}MB. Memory pressure detected — check running processes."
        fi
        DETAILS+="⚠️ Swap: ${swap_used_mb}MB / ${swap_total_mb}MB used (pressure!)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "swap_pressure"; then
            alert_green "✅ Swap Pressure Cleared" "Swap usage back to ${swap_used_mb}MB of ${swap_total_mb}MB."
        fi
        DETAILS+="✅ Swap: ${swap_used_mb}MB / ${swap_total_mb}MB\n"
    fi
}

# --- Check 8: Service status (summary only) ---
# macOS has no systemd.
# v2.5.2: Skips launchd check with INFO line when the Qt wallet is the
#         detected daemon — Qt operators usually launch the GUI outside
#         launchctl, so a "not loaded" red would be a false alert. The
#         Qt-skip triggers on any of the three known Qt process names.
# v2.5:   Adds DD_ACTIVE guard for oracle process (standby → INFO not warn).
check_services() {
    # v2.5.2: Detect whether the running daemon is a Qt-family variant
    local is_qt=false
    case "${DETECTED_DAEMON:-}" in
        DigiByte-Qt|Digibyte-Qt|digibyte-qt) is_qt=true ;;
    esac

    if [ "$is_qt" = true ]; then
        DETAILS+="ℹ️  launchd: n/a — Qt wallet is the running daemon\n"
    elif [ -n "$LAUNCHD_LABEL" ]; then
        # v2.5.4-macos.1: exact label match on launchctl's third column —
        # a substring grep could false-positive on partially matching labels.
        if launchctl list 2>/dev/null | awk '{print $3}' | grep -qx "$LAUNCHD_LABEL"; then
            DETAILS+="✅ LaunchAgent $LAUNCHD_LABEL: loaded\n"
        else
            DETAILS+="🔴 LaunchAgent $LAUNCHD_LABEL: not loaded\n"
            ISSUES=$((ISSUES + 1))
        fi
    else
        # No launchd label set — stand-in with the process check
        if [ -n "${DETECTED_DAEMON:-}" ]; then
            DETAILS+="✅ $DETECTED_DAEMON process: running\n"
        else
            DETAILS+="🔴 DigiByte node process: not running\n"
            ISSUES=$((ISSUES + 1))
        fi
    fi

    local oracle_status
    oracle_status=$($CLI $WALLET_FLAG listoracle 2>/dev/null | jq -r ".running // \"unknown\"" 2>/dev/null)

    if [ "$DD_ACTIVE" = "false" ]; then
        DETAILS+="ℹ️  Oracle process: standby (DigiDollar deployment: $DD_STATUS)\n"
    elif [ "$oracle_status" = "true" ]; then
        DETAILS+="✅ Oracle process: running\n"
    else
        DETAILS+="⚠️ Oracle process: $oracle_status\n"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# --- Check 9: Node version (summary only) ---
# v2.5: Read version via RPC (getnetworkinfo → .subversion). The old
# approach called `digibyted --version` from PATH, which failed entirely
# for Qt-wallet operators (no digibyted binary) and picked the wrong
# binary in dual-daemon setups. RPC always reports what's actually
# running and works identically for Qt and headless.
check_version() {
    local version
    version=$($CLI getnetworkinfo 2>/dev/null | jq -r .subversion 2>/dev/null)
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        DETAILS+="ℹ️  $version\n"
    fi
}

# --- Check 10: NTP time sync ---
# macOS has no timedatectl. One sntp query measures the real clock offset
# (first field of the "+/-" line, in seconds). Offsets beyond
# NTP_MAX_OFFSET trigger the desync alert. Query failure (UDP 123
# blocked, no network) is surfaced in the summary but does not fire a
# Discord alert — matches the "could not query" pattern elsewhere.
check_ntp() {
    local offset
    offset=$(sntp -t 3 "$NTP_SERVER" 2>/dev/null | awk '/\+\/-/ {print $1; exit}')

    if [ -z "$offset" ]; then
        DETAILS+="⚠️ NTP: could not verify (sntp query failed)\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local in_range
    in_range=$(echo "$offset $NTP_MAX_OFFSET" | \
        awk '{o=$1; if (o<0) o=-o; print (o <= $2) ? "yes" : "no"}')

    if [ "$in_range" != "yes" ]; then
        if should_alert "ntp_desync"; then
            alert_yellow "⚠️ NTP Desync" "System clock is off by ${offset}s vs $NTP_SERVER. Oracle timestamps may drift. Run: sudo sntp -sS $NTP_SERVER"
        fi
        DETAILS+="⚠️ NTP: offset ${offset}s (NOT synchronized)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "ntp_desync"; then
            alert_green "✅ NTP Recovered" "System clock is synchronized again (offset ${offset}s)."
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
# Counts how many oracles are actively reporting across the network.
# Compares against the on-chain quorum threshold from getdigidollardeploymentinfo.
# Also reports MuSig2 session health in the summary line.
#
# Alert bands (configurable via QUORUM_GREEN and QUORUM_YELLOW in config):
#   >= QUORUM_GREEN ............ Green — comfortable
#   >= QUORUM_YELLOW ........... Yellow — getting thin
#   >= consensus_required ...... Red — at quorum edge
#   < consensus_required ....... CRITICAL — DD may halt
#
# RPC FIELD NAMES (confirmed on RC44 testnet26 2026-06-09/11):
#   getdigidollardeploymentinfo → oracle_consensus_required, oracle_total_slots,
#     musig2_session.epoch, musig2_session.state ("complete"/other),
#     musig2_session.nonce_count, musig2_session.partial_sig_count
#   getoracles true → array of objects with heartbeat_status
#     ("fresh"/"stale"/"unknown") — "reporting" = heartbeat_status == "fresh"
#
# Debug commands (if something looks wrong):
#   digibyte-cli -testnet getdigidollardeploymentinfo | jq .
#   digibyte-cli -testnet getoracles true | jq '.[0]'
#
check_quorum() {
    # --- Step 1: Get deployment info (quorum threshold + MuSig2 session) ---
    local deploy_info
    deploy_info=$($CLI getdigidollardeploymentinfo 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$deploy_info" ]; then
        DETAILS+="⚠️ Quorum: could not query deployment info\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local consensus_required total_slots
    consensus_required=$(echo "$deploy_info" | jq -r '.oracle_consensus_required // 7' 2>/dev/null)
    total_slots=$(echo "$deploy_info" | jq -r '.oracle_total_slots // 35' 2>/dev/null)

    # MuSig2 session health — included in summary line
    local musig_epoch musig_state musig_nonces musig_sigs musig_detail
    musig_epoch=$(echo "$deploy_info" | jq -r '.musig2_session.epoch // "?"' 2>/dev/null)
    musig_state=$(echo "$deploy_info" | jq -r '.musig2_session.state // "?"' 2>/dev/null)
    musig_nonces=$(echo "$deploy_info" | jq -r '.musig2_session.nonce_count // "?"' 2>/dev/null)
    musig_sigs=$(echo "$deploy_info" | jq -r '.musig2_session.partial_sig_count // "?"' 2>/dev/null)

    if [ "$musig_state" = "complete" ]; then
        musig_detail="epoch $musig_epoch, ${musig_nonces}/${consensus_required} nonces, ${musig_sigs}/${consensus_required} sigs ✓"
    elif [ "$musig_epoch" != "?" ]; then
        musig_detail="epoch $musig_epoch, ${musig_nonces}/${consensus_required} nonces, ${musig_sigs}/${consensus_required} sigs ($musig_state)"
    else
        musig_detail="could not parse session"
    fi

    # --- Step 2: Count reporting oracles ---
    local oracles
    oracles=$($CLI getoracles true 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$oracles" ]; then
        if [ "$DD_ACTIVE" = "false" ]; then
            DETAILS+="ℹ️  Quorum: standby (DigiDollar deployment: $DD_STATUS)\n"
            return
        fi
        DETAILS+="⚠️ Quorum: could not query oracles\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # Total oracles returned by getoracles true (active roster)
    local roster_count reporting
    roster_count=$(echo "$oracles" | jq 'length' 2>/dev/null)

    # Count oracles with fresh heartbeats as "reporting" (v2.2)
    # heartbeat_status "fresh" = online + signed heartbeat within 30 min.
    # This matches the dashboard's "Online Heartbeats" metric and is stable
    # across MuSig2 round transitions (unlike last_price_usd which resets).
    reporting=$(echo "$oracles" | jq '[.[] | select(.heartbeat_status == "fresh")] | length' 2>/dev/null)

    # Fallback: if jq filter fails (field name mismatch), use roster count
    if [ -z "$reporting" ] || [ "$reporting" = "null" ]; then
        reporting="$roster_count"
        DETAILS+="⚠️ Quorum: could not count reporting oracles (heartbeat_status field missing?) — using roster count\n"
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
                    alert_yellow "⚠️ Quorum Getting Thin" "$reporting/$total_slots oracles reporting (need $consensus_required). Comfortable is ${QUORUM_GREEN}+."
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
            DETAILS+="⚠️ Quorum: $reporting/$total_slots reporting (need $consensus_required) — getting thin\n"
            WARNINGS=$((WARNINGS + 1))
            ;;
        green)
            DETAILS+="✅ Quorum: $reporting/$total_slots reporting (need $consensus_required) — healthy\n"
            ;;
    esac
    DETAILS+="   MuSig2: $musig_detail\n"
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
        status="⚠️ $WARNINGS Warnings"
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local uptime_str
    uptime_str=$(uptime)  # BSD uptime — no -p flag on macOS

    local desc
    desc=$(echo -e "$DETAILS\n⏱️ Uptime: $uptime_str")

    if [ "$DRY_RUN" = true ] || [ -z "$DISCORD_WEBHOOK" ]; then
        echo "======================================="
        echo " ${NETWORK_LABEL:-Oracle} Health Summary — $(date)"
        echo "======================================="
        echo -e "$desc"
        echo "======================================="
        return
    fi

    # v2.5.4-macos.1: payload built with jq -n (matches send_discord).
    local payload
    payload=$(jq -n \
        --arg title "$status — ${NETWORK_LABEL:-Oracle} Health Summary" \
        --arg desc "$desc" \
        --argjson color "$color" \
        --arg footer "Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)" \
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
# (pre-activation). Called first from run_checks() and send_summary() —
# --dry-run, --summary, and --watch all route through send_summary, so
# the pre-flight must live in both paths. Always succeeds; DD_ACTIVE
# defaults to "false" if the RPC fails or DigiDollar is not yet deployed.
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
    --watch)
        # Live console dashboard — full status block, refreshed in place.
        # Runs in dry-run mode internally: never sends Discord alerts and
        # never touches state files, so it's safe to leave open alongside
        # the cron-scheduled checks. Ctrl+C to exit.
        # WATCH_INTERVAL was set by the arg parser (or empty → default 60).
        if [ -z "$WATCH_INTERVAL" ]; then
            WATCH_INTERVAL=60
        fi
        DRY_RUN=true
        while true; do
            clear 2>/dev/null
            echo "🔭 ${NETWORK_LABEL:-Oracle} Monitor — watch mode (refreshes every ${WATCH_INTERVAL}s, Ctrl+C to exit)"
            ISSUES=0
            WARNINGS=0
            DETAILS=""
            send_summary
            sleep "$WATCH_INTERVAL"
        done
        ;;
    --test)
        echo "Testing Discord webhook..."
        if [ -z "$DISCORD_WEBHOOK" ]; then
            echo "ERROR: DISCORD_WEBHOOK is not set."
            echo "Configure it in: $CONFIG_FILE"
            exit 1
        fi
        # v2.5.4-macos.1: label lives in the title only (send_discord
        # prefixes NETWORK_LABEL) — no more doubled label in the card.
        alert_blue "🔧 Test Alert" "Oracle monitor is configured and working! $(date)"
        echo "Check your Discord channel."
        ;;
    *)
        run_checks
        ;;
esac
