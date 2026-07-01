#!/bin/bash
###############################################################################
# oracle-monitor.sh — DGB Oracle Health Monitor with Discord Alerts
# Version: 2.5.2
#
# Monitors oracle node health and sends Discord webhook notifications
# when issues are detected. Designed for cron job execution.
#
# Author & Oracle: digibyte-maxi (ID 17) — VPS | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 - July 2026
readonly SCRIPT_VERSION="2.5.2"
#
# SETUP:
#   1. Copy this script to your VPS: ~/oracle-monitor.sh
#   2. chmod +x ~/oracle-monitor.sh
#   3. Create config: mkdir -p ~/.oracle-monitor && cp config.template ~/.oracle-monitor/config
#   4. Edit config: Set your Discord webhook URL and oracle settings
#   5. Test it: ./oracle-monitor.sh --dry-run
#   6. Test webhook: ./oracle-monitor.sh --test
#   7. Add to cron: crontab -e
#      */5 * * * * /home/YOUR_USER/oracle-monitor.sh 2>/dev/null
#      0 */12 * * * /home/YOUR_USER/oracle-monitor.sh --summary 2>/dev/null
#
# FLAGS:
#   (none)     Normal health check — alerts only on problems/recovery
#   --summary  Full status summary — always sends to Discord
#   --dry-run  Runs all checks, prints to terminal, skips Discord, no state changes
#   --test     Sends a test embed to Discord to verify webhook
#   --config /path  Use alternate config file (enables dual-instance monitoring)
#
# CRON SCHEDULE:
#   */5 = every 5 minutes for health checks (alerts only on problems)
#   0 */12 = every 12 hours for a full status summary (always sends)
#
# CHANGELOG:
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
#          PRE stale incident (Session 19). Companion to the OOM
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
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --dry-run|--summary|--test)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        *)
            echo "Usage: $0 [--config /path] [--dry-run | --summary | --test]"
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

# Thresholds — basic health
MIN_PEERS=3
MIN_DISK_GB=5
STALE_PRICE_MINUTES=30
MEM_THRESHOLD=90
SWAP_THRESHOLD_MB=100
MAX_CHAIN_BEHIND=10

# Thresholds — quorum margin (v2.0)
# These define the alert bands for network-wide oracle liveness.
# Quorum threshold (oracle_consensus_required) comes from the chain via
# getdigidollardeploymentinfo — not hardcoded here.
#
# QUORUM_GREEN: at or above this count = comfortable, no alerts
# QUORUM_YELLOW: at or above this but below green = "getting thin" warning
# Below QUORUM_YELLOW but at/above consensus_required = red, at quorum edge
# Below consensus_required = CRITICAL — DD bundle signing may halt
QUORUM_GREEN=20
QUORUM_YELLOW=12

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
# DISCORD NOTIFICATION FUNCTIONS
# ============================================================================

send_discord() {
    local color="$1"    # red=16711680, green=65280, yellow=16776960, blue=3447003
    local title="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$DRY_RUN" = true ] || [ -z "$DISCORD_WEBHOOK" ]; then
        echo "[$(date)] ALERT: $title — $message"
        return
    fi

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$title",
    "description": "$message",
    "color": $color,
    "footer": {"text": "Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)"},
    "timestamp": "$timestamp"
  }]
}
EOF
)
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
            alert_red "🔴 Node Down" "Neither digibyted nor digibyte-qt is running! For headless: \`sudo systemctl status digibyted.service\`. For Qt: launch the wallet."
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
check_disk() {
    local avail_gb
    avail_gb=$(df -BG /home | tail -1 | awk '{print $4}' | tr -d 'G')

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
check_memory() {
    local mem_pct
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

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
# On a properly configured box with swappiness=10, any meaningful swap
# usage signals real memory pressure — the exact condition that silently
# killed daemons during the PRE stale incident (Session 19). Companion to
# the OOM protection in the hardening guide.
check_swap() {
    local swap_total_mb swap_used_mb
    swap_total_mb=$(free -m | awk '/Swap:/ {print $2}')
    swap_used_mb=$(free -m | awk '/Swap:/ {print $3}')

    # No swap configured — skip silently in normal checks, note in summary
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

# --- Check 8: Systemd service status ---
# v2.5: Reads SERVICE_NAME config var (defaults to digibyted.service).
#       Adds DD_ACTIVE guard for oracle process (standby → INFO not warn).
# v2.5.2: Skips systemd unit check with INFO line when the Qt wallet is
#         the running daemon (Qt typically runs outside systemd).
check_services() {
    local dgb_status oracle_status service_name
    service_name="${SERVICE_NAME:-digibyted.service}"

    # v2.5.2: Skip systemd unit check when the Qt wallet is the running
    # daemon — most Qt operators launch the GUI outside systemd, so a
    # `systemctl is-active` on the headless unit is a misleading red.
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

# --- Check 9: Node version ---
# v2.5: Read version via RPC (getnetworkinfo → .subversion) instead of
# `digibyted --version`. The old approach pulled whichever `digibyted`
# lived in $PATH, which read the wrong binary in dual-daemon setups.
check_version() {
    local version
    version=$($CLI getnetworkinfo 2>/dev/null | jq -r .subversion 2>/dev/null)
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        DETAILS+="ℹ️  $version\n"
    fi
}

# --- Check 10: NTP time sync ---
check_ntp() {
    local synced
    synced=$(timedatectl status 2>/dev/null | grep -c "synchronized: yes")

    if [ "$synced" -eq 0 ]; then
        if should_alert "ntp_desync"; then
            alert_yellow "⚠️ NTP Desync" "System clock is NOT synchronized. Oracle timestamps may drift. Run: sudo timedatectl set-ntp on"
        fi
        DETAILS+="⚠️ NTP: NOT synchronized\n"
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
    rm -f "$STATE_DIR/quorum_yellow" "$STATE_DIR/quorum_red" "$STATE_DIR/quorum_critical"

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
    # This matches the dashboard's "Online Heartbeats" count and is stable
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
    uptime_str=$(uptime -p 2>/dev/null || uptime)

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

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$status — ${NETWORK_LABEL:-Oracle} Health Summary",
    "description": $(echo "$desc" | jq -Rs .),
    "color": $color,
    "footer": {"text": "Oracle Monitor v${SCRIPT_VERSION} — $ORACLE_NAME (ID $ORACLE_ID)"},
    "timestamp": "$timestamp"
  }]
}
EOF
)
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
        alert_blue "🔧 ${NETWORK_LABEL:-Oracle} Test Alert" "${NETWORK_LABEL:-Oracle} monitor is configured and working! $(date)"
        echo "Check your Discord channel."
        ;;
    *)
        run_checks
        ;;
esac
