#!/bin/bash
###############################################################################
# oracle-monitor.sh — DGB DigiDollar Oracle Health Monitor with Discord Alerts
#
# Monitors oracle node health and sends Discord webhook notifications
# when issues are detected. Designed for cron job execution.
#
# Created by:  digibyte-maxi (Oracle Slot 17)
# Source:      https://github.com/BaumerCrypto/digidollar-oracle-tools
# License:     MIT
#
# DISCLAIMER:  Community tool, not an official DigiByte product. Provided as-is
#              with no warranty. Always test on testnet first. You are
#              responsible for your own oracle wallet, keys, and infrastructure.
#
# Tested on:   Ubuntu 24.04 LTS + DigiByte Core v9.26.0-rc43 (testnet25)
#
# SETUP:
#   1. Copy this script to your VPS, e.g.:  ~/oracle-monitor.sh
#   2. chmod +x ~/oracle-monitor.sh
#   3. Edit the CONFIGURATION block below — set your Discord webhook,
#      oracle ID, oracle name, and (for mainnet) remove "-testnet" from CLI.
#   4. Test the webhook:   ./oracle-monitor.sh --test
#   5. Test a full check:  ./oracle-monitor.sh --summary
#   6. Add to cron:        crontab -e
#        */5 * * * * $HOME/oracle-monitor.sh 2>/dev/null
#        0 */12 * * * $HOME/oracle-monitor.sh --summary 2>/dev/null
#
# CRON SCHEDULE EXPLAINED:
#   */5    = every 5 minutes — health check (alerts only on problems/recovery)
#   0 */12 = every 12 hours  — full status summary (always sends, blue embed)
#
# RPC FIELD NAMES (RC43 — verify on newer releases):
#   listoracle      → uses "running"   (not "is_running")
#   listoracle      → uses "price_usd" (not "last_price_usd")
#   getoracleprice  → uses "price_usd" and "is_stale"
###############################################################################

# ============================================================================
# CONFIGURATION — *** EDIT THESE FOR YOUR ORACLE ***
# ============================================================================

# --- Discord webhook URL (REQUIRED) ---
# Create one in Discord: Server Settings > Integrations > Webhooks > New Webhook
# Paste the full URL between the quotes. Treat it like a password — never
# commit a real webhook URL to a public repo.
DISCORD_WEBHOOK=""

# --- Your oracle identity (REQUIRED) ---
ORACLE_ID=17                       # Your assigned oracle slot number
ORACLE_NAME="digibyte-maxi"        # Your oracle name as registered with Jared

# --- DigiByte CLI command ---
# For TESTNET use:  "digibyte-cli -testnet"
# For MAINNET use:  "digibyte-cli"
CLI="digibyte-cli -testnet"

# --- Wallet flag ---
# Change "oracle" if you named your wallet differently
WALLET_FLAG="-rpcwallet=oracle"

# --- Alert thresholds (tune to taste) ---
MIN_PEERS=3                        # Yellow alert if peer count drops below this
MIN_DISK_GB=5                      # Red alert if free disk falls below this (GB)
STALE_PRICE_MINUTES=30             # Currently informational only

# --- Where to store alert state files (prevents repeat alerts) ---
# Uses $HOME so it works for any user. Override if you want it elsewhere.
STATE_DIR="$HOME/.oracle-monitor"
mkdir -p "$STATE_DIR"

# ============================================================================
# DISCORD NOTIFICATION FUNCTIONS
# ============================================================================

send_discord() {
    local color="$1"    # red=16711680, green=65280, yellow=16776960, blue=3447003
    local title="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ -z "$DISCORD_WEBHOOK" ]; then
        echo "[$(date -u)] ALERT: $title — $message"
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
should_alert() {
    local key="$1"
    local state_file="$STATE_DIR/$key"
    if [ -f "$state_file" ]; then
        return 1  # already alerted
    fi
    touch "$state_file"
    return 0
}

clear_alert() {
    local key="$1"
    local state_file="$STATE_DIR/$key"
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

    # Check if oracle is running
    local running
    running=$(echo "$oracle_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('running', False))" 2>/dev/null)
    
    if [ "$running" != "True" ]; then
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
        price=$(echo "$oracle_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('price_usd', 'unknown'))" 2>/dev/null)
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
    blocks=$(echo "$chain_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['blocks'])" 2>/dev/null)
    headers=$(echo "$chain_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['headers'])" 2>/dev/null)
    chain=$(echo "$chain_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('chain','unknown'))" 2>/dev/null)

    local behind=$((headers - blocks))
    
    if [ "$behind" -gt 10 ]; then
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
check_price() {
    local price_info
    price_info=$($CLI getoracleprice 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        DETAILS+="⚠️ Price: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local price_usd is_stale
    price_usd=$(echo "$price_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('price_usd','unknown'))" 2>/dev/null)
    is_stale=$(echo "$price_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_stale', False))" 2>/dev/null)

    if [ "$is_stale" = "True" ]; then
        if should_alert "stale_price"; then
            alert_yellow "⚠️ Stale Price" "Oracle consensus price is stale. Last price: \$$price_usd"
        fi
        DETAILS+="⚠️ Price: STALE — \$$price_usd\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "stale_price"; then
            alert_green "✅ Price Recovered" "Oracle price is fresh again: \$$price_usd"
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
    
    if [ "$mem_pct" -gt 90 ]; then
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
    oracle_status=$(systemctl is-active dgb-oracle.service 2>/dev/null)

    if [ "$dgb_status" = "active" ]; then
        DETAILS+="✅ digibyted.service: active\n"
    else
        DETAILS+="🔴 digibyted.service: $dgb_status\n"
        ISSUES=$((ISSUES + 1))
    fi

    if [ "$oracle_status" = "active" ]; then
        DETAILS+="✅ dgb-oracle.service: active\n"
    else
        DETAILS+="⚠️ dgb-oracle.service: $oracle_status\n"
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

# ============================================================================
# SUMMARY REPORT (--summary flag)
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

    if [ -z "$DISCORD_WEBHOOK" ]; then
        echo "======================================="
        echo " Oracle Health Summary — $(date -u)"
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
    "description": $(echo "$desc" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"),
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
}

# ============================================================================
# ENTRY POINT
# ============================================================================

case "${1:-}" in
    --summary)
        send_summary
        ;;
    --test)
        echo "Testing Discord webhook..."
        alert_blue "🔧 Test Alert" "Oracle monitor is configured and working! $(date -u)"
        echo "Check your Discord channel."
        ;;
    *)
        run_checks
        ;;
esac
