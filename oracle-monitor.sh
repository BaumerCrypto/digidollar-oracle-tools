#!/bin/bash
###############################################################################
# oracle-monitor.sh — DGB Oracle Health Monitor with Discord Alerts
# Version: 2.0
#
# Monitors oracle node health and sends Discord webhook notifications
# when issues are detected. Designed for cron job execution.
#
# Author & Oracle: digibyte-maxi (ID 17) — VPS | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 - June 2026
#
# SETUP:
#   1. Copy this script to your VPS: ~/oracle-monitor.sh
#   2. chmod +x ~/oracle-monitor.sh
#   3. Create config: mkdir -p ~/.oracle-monitor && cp config.template ~/.oracle-monitor/config
#   4. Edit config: Set your Discord webhook URL and oracle settings
#   5. Test it: ./oracle-monitor.sh --dry-run
#   6. Test webhook: ./oracle-monitor.sh --test
#   7. Add to cron: crontab -e
#      */5 * * * * /home/dgboracle/oracle-monitor.sh 2>/dev/null
#      0 */12 * * * /home/dgboracle/oracle-monitor.sh --summary 2>/dev/null
#
# FLAGS:
#   (none)     Normal health check — alerts only on problems/recovery
#   --summary  Full status summary — always sends to Discord
#   --dry-run  Runs all checks, prints to terminal, skips Discord, no state changes
#   --test     Sends a test embed to Discord to verify webhook
#
# CRON SCHEDULE:
#   */5 = every 5 minutes for health checks (alerts only on problems)
#   0 */12 = every 12 hours for a full status summary (always sends)
#
# CHANGELOG:
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
# CONFIGURATION — DEFAULTS (override in ~/.oracle-monitor/config)
# ============================================================================

# Discord webhook URL — get this from your Discord server settings
# Server Settings > Integrations > Webhooks > New Webhook > Copy URL
DISCORD_WEBHOOK=""

# Oracle settings
ORACLE_ID=17
ORACLE_NAME="digibyte-maxi"
CLI="digibyte-cli -testnet"
WALLET_FLAG="-rpcwallet=oracle"

# Thresholds — basic health
MIN_PEERS=3
MIN_DISK_GB=5
STALE_PRICE_MINUTES=30
MEM_THRESHOLD=90
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

# ============================================================================
# LOAD EXTERNAL CONFIG (overrides defaults above)
# ============================================================================

STATE_DIR="${HOME}/.oracle-monitor"
CONFIG_FILE="${STATE_DIR}/config"

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
    "footer": {"text": "Oracle Monitor — $ORACLE_NAME (ID $ORACLE_ID)"},
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

# --- Check 1: Is digibyted running? ---
check_daemon() {
    if pgrep -x digibyted > /dev/null 2>&1; then
        if clear_alert "daemon_down"; then
            alert_green "✅ Node Recovered" "digibyted is running again."
        fi
        DETAILS+="✅ digibyted: running\n"
    else
        if should_alert "daemon_down"; then
            alert_red "🔴 Node Down" "digibyted is NOT running! Check systemd: \`sudo systemctl status digibyted.service\`"
        fi
        DETAILS+="🔴 digibyted: NOT RUNNING\n"
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

# --- Check 8: Systemd service status ---
check_services() {
    local dgb_status oracle_status
    dgb_status=$(systemctl is-active digibyted.service 2>/dev/null)
    oracle_status=$($CLI $WALLET_FLAG listoracle 2>/dev/null | jq -r ".running // \"unknown\"" 2>/dev/null)

    if [ "$dgb_status" = "active" ]; then
        DETAILS+="✅ digibyted.service: active\n"
    else
        DETAILS+="🔴 digibyted.service: $dgb_status\n"
        ISSUES=$((ISSUES + 1))
    fi

    if [ "$oracle_status" = "true" ]; then
        DETAILS+="✅ Oracle process: running\n"
    else
        DETAILS+="⚠️ Oracle process: $oracle_status\n"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# --- Check 9: Node version ---
check_version() {
    local version
    version=$(digibyted --version 2>/dev/null | head -1)
    if [ -n "$version" ]; then
        DETAILS+="ℹ️ $version\n"
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
#   getoracles true → array of objects, each with last_price_usd field
#     "reporting" = last_price_usd exists and > 0
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
        DETAILS+="⚠️ Quorum: could not query oracles\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # Total oracles returned by getoracles true (active roster)
    local roster_count reporting
    roster_count=$(echo "$oracles" | jq 'length' 2>/dev/null)

    # Count oracles with a non-null, non-zero last_price_usd as "reporting"
    # This filters out oracles that are in the roster but not online/producing prices
    reporting=$(echo "$oracles" | jq '[.[] | select(.last_price_usd != null and (.last_price_usd | tonumber) > 0)] | length' 2>/dev/null)

    # Fallback: if jq filter fails (field name mismatch), use roster count
    if [ -z "$reporting" ] || [ "$reporting" = "null" ]; then
        reporting="$roster_count"
        DETAILS+="⚠️ Quorum: could not count reporting oracles (field name mismatch?) — using roster count\n"
        WARNINGS=$((WARNINGS + 1))
    fi

    # --- Step 3: Alert based on quorum margin ---
    if [ "$reporting" -lt "$consensus_required" ]; then
        # CRITICAL — below quorum threshold, DD bundle signing may halt
        if should_alert "quorum_critical"; then
            alert_red "🔴 QUORUM LOST" "Only $reporting/$total_slots oracles reporting. Need $consensus_required for consensus. DigiDollar signing may be halted!"
        fi
        DETAILS+="🔴 Quorum: $reporting/$total_slots reporting (need $consensus_required) — CRITICAL\n"
        DETAILS+="   MuSig2: $musig_detail\n"
        ISSUES=$((ISSUES + 1))

    elif [ "$reporting" -lt "$QUORUM_YELLOW" ]; then
        # RED — above quorum but uncomfortably thin
        if should_alert "quorum_red"; then
            alert_red "🔴 Quorum At Edge" "Only $reporting/$total_slots oracles reporting (need $consensus_required). Network at risk if more drop."
        fi
        # Clear critical if recovering upward
        if clear_alert "quorum_critical"; then
            alert_green "✅ Quorum Recovering" "Quorum restored: $reporting/$total_slots oracles reporting (need $consensus_required)."
        fi
        DETAILS+="🔴 Quorum: $reporting/$total_slots reporting (need $consensus_required) — at edge\n"
        DETAILS+="   MuSig2: $musig_detail\n"
        ISSUES=$((ISSUES + 1))

    elif [ "$reporting" -lt "$QUORUM_GREEN" ]; then
        # YELLOW — above red threshold but below comfortable
        if should_alert "quorum_yellow"; then
            alert_yellow "⚠️ Quorum Getting Thin" "$reporting/$total_slots oracles reporting (need $consensus_required). Comfortable is ${QUORUM_GREEN}+."
        fi
        # Clear worse states if recovering upward
        if clear_alert "quorum_critical"; then
            alert_green "✅ Quorum Recovering" "Quorum restored: $reporting/$total_slots reporting."
        fi
        if clear_alert "quorum_red"; then
            alert_green "✅ Quorum Margin Improving" "$reporting/$total_slots reporting — no longer at edge."
        fi
        DETAILS+="⚠️ Quorum: $reporting/$total_slots reporting (need $consensus_required) — getting thin\n"
        DETAILS+="   MuSig2: $musig_detail\n"
        WARNINGS=$((WARNINGS + 1))

    else
        # GREEN — comfortable margin
        if clear_alert "quorum_critical"; then
            alert_green "✅ Quorum Restored" "Quorum fully recovered: $reporting/$total_slots reporting."
        fi
        if clear_alert "quorum_red"; then
            alert_green "✅ Quorum Margin Recovered" "$reporting/$total_slots reporting — comfortable margin."
        fi
        if clear_alert "quorum_yellow"; then
            alert_green "✅ Quorum Healthy" "$reporting/$total_slots reporting — back to comfortable."
        fi
        DETAILS+="✅ Quorum: $reporting/$total_slots reporting (need $consensus_required) — healthy\n"
        DETAILS+="   MuSig2: $musig_detail\n"
    fi
}

# ============================================================================
# SUMMARY REPORT (--summary and --dry-run)
# ============================================================================

send_summary() {
    check_daemon || return
    check_oracle
    check_chain
    check_peers
    check_price
    check_disk
    check_memory
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
        echo " Oracle Health Summary — $(date)"
        echo "======================================="
        echo -e "$desc"
        echo "======================================="
        return
    fi

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$status — Oracle Health Summary",
    "description": $(echo "$desc" | jq -Rs .),
    "color": $color,
    "footer": {"text": "Oracle Monitor — $ORACLE_NAME (ID $ORACLE_ID)"},
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

run_checks() {
    check_daemon || return
    check_oracle
    check_chain
    check_peers
    check_price
    check_disk
    check_memory
    check_ntp
    check_quorum
}

# ============================================================================
# ENTRY POINT
# ============================================================================

case "${1:-}" in
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
        alert_blue "🔧 Test Alert" "Oracle monitor is configured and working! $(date)"
        echo "Check your Discord channel."
        ;;
    *)
        run_checks
        ;;
esac
