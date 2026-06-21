#!/bin/bash
###############################################################################
# oracle-network-status.sh — DGB Oracle Network Status Bot (Gitter via Matrix)
# Version: 1.4
#
# Posts automated oracle network health summaries to the DigiDollar Gitter
# channel every 12 hours. Community-facing — reports network-wide status,
# not individual node health (that's oracle-monitor.sh).
#
# Author & Oracle: digibyte-maxi (ID 17) — VPS | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0
#
# SETUP (one-time):
#   1. Create a Matrix bot account at https://app.element.io/#/register
#      (e.g. @digidollar-oracle-bot:matrix.org)
#   2. Join #digidollar:gitter.im from the bot account
#   3. Generate an access token on the VPS:
#      curl -s -X POST "https://matrix.org/_matrix/client/v3/login" \
#        -H "Content-Type: application/json" \
#        -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"YOUR_BOT_USERNAME"},"password":"YOUR_PASSWORD"}' \
#        | jq -r '.access_token'
#   4. Get the room ID (Element → Room Settings → Advanced → Internal room ID)
#      Or resolve it:
#      curl -s "https://matrix.org/_matrix/client/v3/directory/room/%23digidollar%3Agitter.im" \
#        -H "Authorization: Bearer YOUR_TOKEN" | jq -r '.room_id'
#   5. Add to ~/.oracle-monitor/config:
#      MATRIX_ACCESS_TOKEN="your_token_here"
#      MATRIX_ROOM_ID="!your_room_id:gitter.im"
#   6. For @ mentions: populate ~/.oracle-monitor/oracle-roster.conf
#      (see oracle-roster.template in the repo for format)
#   7. Test:  ./oracle-network-status.sh --dry-run
#   8. Test:  ./oracle-network-status.sh --test
#   9. Test:  ./oracle-network-status.sh --test-mention
#  10. Cron:  5 */12 * * * /home/dgboracle/oracle-network-status.sh 2>/dev/null
#
# FLAGS:
#   (none)              Collect data and post to Gitter
#   --dry-run           Collect data, print to terminal, skip Gitter post
#   --test              Send a test message to Gitter to verify Matrix API
#   --test-mention      Send a test mention to verify notifications work
#   --config /path      Use alternate config file (enables dual-instance)
#
# DUAL-INSTANCE EXAMPLE (testnet + mainnet on one VPS):
#   # Testnet (default config)
#   5 */12 * * * /home/dgboracle/oracle-network-status.sh 2>/dev/null
#   # Mainnet (custom config)
#   10 */12 * * * /home/dgboracle/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config 2>/dev/null
#
# DATA SOURCES (RPCs):
#   getblockchaininfo            — chain identification (testnet/mainnet)
#   getoracles true              — per-oracle heartbeat status (active/offline list)
#   getoracleprice               — consensus price, status, oracle count
#   getdigidollardeploymentinfo  — BIP9 status, quorum config, MuSig2 session
#   getoraclesigners 50          — recent bundle signer participation
#
# FILES:
#   ~/.oracle-monitor/config             — shared config (CLI, webhook, Matrix token)
#   ~/.oracle-monitor/oracle-roster.conf — oracle ID to Gitter handle mapping (VPS only)
#   ~/.oracle-monitor/mention_state      — ping count tracking per oracle
#
# CHANGELOG:
#   v1.4 — Network label in header: auto-detected from getblockchaininfo
#          ("test" → Testnet, "main" → Mainnet), overridable via
#          NETWORK_LABEL in config (e.g. "Testnet26"). Header now reads:
#          🟢 Oracle Network Status — Testnet26 — 2026-06-21 10:05 UTC
#          New --config /path flag for dual-instance support (Issue #23).
#          Two cron entries + two config files = independent testnet and
#          mainnet monitoring from one VPS. State files (mention_state)
#          auto-separate per config directory. Roster file shared by
#          default (same 35 operators on both networks).
#          Requested by Aussie Epic and DanGB in Gitter.
#   v1.3 — @ mention support for stale/inactive operators. Roster mapping
#          file (oracle-roster.conf) maps oracle IDs to Gitter Matrix IDs.
#          Ping cap: 6 per outage (configurable via MENTION_MAX), resets
#          when oracle returns fresh. Dual-slot dedup (Jared 0+28, LookInto
#          7+20 get one ping not two). Matrix formatted_body with HTML
#          mention pills for clean display names + m.mentions for proper
#          notifications. New flag: --test-mention. Label rename: "Not
#          connected" → "Inactive" (accurate — key/wallet issues, not
#          absent operators).
#   v1.2 — Rename "Active" → "Fresh Heartbeats" to match dashboard language.
#          Add "Software" section: aggregates software_version by operator
#          count and fresh heartbeats. Format nonces/sigs as X/X vs required.
#   v1.1 — Fix: split offline into "Stale" (was running, went down — liveness
#          concern) vs "Not connected" (never set up on this testnet). Fix
#          offline count: was stale+none (missed unknown/null), now
#          total-fresh. Matches dashboard categories.
#   v1.0 — Initial release: 4 RPCs, Matrix API, Gitter posting, cron-ready
#
###############################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

for dep in jq curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: $dep is required but not installed."
        exit 1
    fi
done

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
                echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --dry-run|--test|--test-mention)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        *)
            echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention]"
            exit 1
            ;;
    esac
done

# ============================================================================
# CONFIGURATION — DEFAULTS (override in config file)
# ============================================================================

# RPC settings (shared with oracle-monitor.sh)
CLI="digibyte-cli -testnet"

# Matrix/Gitter bot settings
MATRIX_HOMESERVER="https://matrix.org"
MATRIX_ACCESS_TOKEN=""
MATRIX_ROOM_ID=""

# Quorum alert bands (same as oracle-monitor.sh for consistency)
QUORUM_GREEN=20
QUORUM_YELLOW=12

# Mention settings
MENTION_MAX=6

# Network label (auto-detected from getblockchaininfo if not set)
# Override examples: "Testnet26", "Mainnet", "Testnet"
NETWORK_LABEL=""

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
MONITOR_DIR=$(dirname "$CONFIG_FILE")

# Default file paths — roster shared across instances, state per-instance
ROSTER_FILE="${HOME}/.oracle-monitor/oracle-roster.conf"
MENTION_STATE_FILE="${MONITOR_DIR}/mention_state"

# Load config (can override CLI, MATRIX_*, NETWORK_LABEL, ROSTER_FILE, etc.)
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Runtime flag
DRY_RUN=false

# ============================================================================
# MENTION HELPER FUNCTIONS
# ============================================================================

# Arrays for tracking mentions during this run
declare -a ALL_MENTION_IDS=()
declare -a ALL_MENTION_NAMES=()
declare -a MENTIONED_HANDLES=()

# Look up Gitter Matrix ID for an oracle slot
# Roster file format: ID|@handle:server (one per line, # comments)
get_gitter_handle() {
    local oracle_id="$1"
    if [ ! -f "$ROSTER_FILE" ]; then
        return
    fi
    grep -v '^#' "$ROSTER_FILE" | grep -v '^$' | grep "^${oracle_id}|" | head -1 | cut -d'|' -f2
}

# Get current mention count for an oracle from state file
get_mention_count() {
    local oracle_id="$1"
    if [ ! -f "$MENTION_STATE_FILE" ]; then
        echo "0"
        return
    fi
    local count
    count=$(grep "^${oracle_id}|" "$MENTION_STATE_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
    echo "${count:-0}"
}

# Update mention count for an oracle (increment by 1)
increment_mention_count() {
    local oracle_id="$1"
    local old_count="$2"
    local new_count=$((old_count + 1))
    local timestamp
    timestamp=$(date +%s)

    # Ensure state file exists
    touch "$MENTION_STATE_FILE" 2>/dev/null

    # Remove old entry, append new
    sed -i "/^${oracle_id}|/d" "$MENTION_STATE_FILE" 2>/dev/null
    echo "${oracle_id}|${new_count}|${timestamp}" >> "$MENTION_STATE_FILE"
}

# Reset mention count for an oracle (called when oracle returns fresh)
reset_mention_count() {
    local oracle_id="$1"
    if [ -f "$MENTION_STATE_FILE" ]; then
        sed -i "/^${oracle_id}|/d" "$MENTION_STATE_FILE" 2>/dev/null
    fi
}

# Check if a handle was already mentioned this run (dual-slot dedup)
is_already_mentioned() {
    local handle="$1"
    local h
    for h in "${MENTIONED_HANDLES[@]}"; do
        if [ "$h" = "$handle" ]; then
            return 0
        fi
    done
    return 1
}

# Record a mention for this run
record_mention() {
    local handle="$1"
    local display_name="$2"
    MENTIONED_HANDLES+=("$handle")
    ALL_MENTION_IDS+=("$handle")
    ALL_MENTION_NAMES+=("$display_name")
}

# ============================================================================
# ACTION FLAG DISPATCH
# ============================================================================

case "$ACTION_FLAG" in
    --dry-run)
        DRY_RUN=true
        echo "[DRY RUN] Will collect data and print — no Gitter post."
        echo "[DRY RUN] Config: $CONFIG_FILE"
        ;;
    --test)
        if [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_ROOM_ID" ]; then
            echo "ERROR: MATRIX_ACCESS_TOKEN and MATRIX_ROOM_ID must be set in $CONFIG_FILE"
            exit 1
        fi
        echo "Sending test message to Gitter..."
        txn_id="test_$(date +%s)"
        payload=$(jq -n --arg body "🟢 Oracle Network Monitor — test message ($(date -u +'%Y-%m-%d %H:%M UTC'))" \
            '{msgtype: "m.text", body: $body}')
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${txn_id}" \
            -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        if [ "$http_code" = "200" ]; then
            echo "✅ Test message sent successfully."
        else
            echo "❌ Failed (HTTP $http_code): $body"
            exit 1
        fi
        exit 0
        ;;
    --test-mention)
        if [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_ROOM_ID" ]; then
            echo "ERROR: MATRIX_ACCESS_TOKEN and MATRIX_ROOM_ID must be set in $CONFIG_FILE"
            exit 1
        fi
        if [ ! -f "$ROSTER_FILE" ]; then
            echo "ERROR: Roster file not found: $ROSTER_FILE"
            echo "Create it with oracle ID to Gitter handle mappings."
            exit 1
        fi
        # Look up slot 17 (digibyte-maxi) for the test mention
        test_handle=$(get_gitter_handle 17)
        if [ -z "$test_handle" ]; then
            echo "ERROR: No handle found for oracle ID 17 in $ROSTER_FILE"
            exit 1
        fi
        echo "Sending test mention to ${test_handle}..."
        txn_id="testmention_$(date +%s)"
        mention_array=$(echo "$test_handle" | jq -R . | jq -s .)
        payload=$(jq -n \
            --arg body "🟢 Bot account test — please ignore | ${test_handle} testing 12hr Oracle Monitor Bot @ mention feature!" \
            --argjson mentions "$mention_array" \
            '{msgtype: "m.text", body: $body, "m.mentions": {user_ids: $mentions}}')
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${txn_id}" \
            -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        if [ "$http_code" = "200" ]; then
            echo "✅ Mention sent. Check Gitter — did you get a notification?"
            echo "   Handle used: $test_handle"
            echo ""
            echo "If NO notification: the Gitter bridge may need HTML mention pills."
            echo "If YES: @ mentions are working. Ready for production."
        else
            echo "❌ Failed (HTTP $http_code): $body"
            exit 1
        fi
        exit 0
        ;;
    "")
        # Normal run — continue
        ;;
esac

# ============================================================================
# MATRIX API — POST TO GITTER
# ============================================================================

post_to_gitter() {
    local message="$1"
    local html_message="${2:-}"
    local mention_ids_csv="${3:-}"

    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════"
        echo "  MESSAGE THAT WOULD BE POSTED TO GITTER:"
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "$message"
        echo ""
        if [ -n "$mention_ids_csv" ]; then
            echo "  m.mentions user_ids: $mention_ids_csv"
            echo "  formatted_body: yes (HTML mention pills)"
        fi
        echo "═══════════════════════════════════════════════"
        return 0
    fi

    if [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_ROOM_ID" ]; then
        echo "ERROR: MATRIX_ACCESS_TOKEN and MATRIX_ROOM_ID not set. Run with --dry-run or configure."
        return 1
    fi

    local txn_id="status_$(date +%s%N)"

    # Build JSON payload with jq (handles escaping properly)
    local payload
    if [ -n "$html_message" ] && [ -n "$mention_ids_csv" ]; then
        # Full payload: plain body + HTML formatted_body with pills + m.mentions
        local mention_array
        mention_array=$(echo "$mention_ids_csv" | tr ',' '\n' | jq -R . | jq -s .)

        payload=$(jq -n \
            --arg body "$message" \
            --arg html "$html_message" \
            --argjson mentions "$mention_array" \
            '{msgtype: "m.text", body: $body, format: "org.matrix.custom.html", formatted_body: $html, "m.mentions": {user_ids: $mentions}}')
    elif [ -n "$mention_ids_csv" ]; then
        # Mentions but no HTML (fallback)
        local mention_array
        mention_array=$(echo "$mention_ids_csv" | tr ',' '\n' | jq -R . | jq -s .)

        payload=$(jq -n \
            --arg body "$message" \
            --argjson mentions "$mention_array" \
            '{msgtype: "m.text", body: $body, "m.mentions": {user_ids: $mentions}}')
    else
        payload=$(jq -n --arg body "$message" '{msgtype: "m.text", body: $body}')
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${txn_id}" \
        -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "200" ]; then
        echo "[$(date -u)] Posted network status to Gitter."
        return 0
    else
        echo "[$(date -u)] ERROR: Gitter post failed (HTTP $http_code)"
        echo "$response" | head -1
        return 1
    fi
}

# ============================================================================
# RPC DATA COLLECTION
# ============================================================================

echo "[$(date -u)] Collecting oracle network data..."

# --- 0. getblockchaininfo — network identification ---
CHAIN_JSON=$($CLI getblockchaininfo 2>&1)
if [ $? -eq 0 ] && ! echo "$CHAIN_JSON" | grep -q "error"; then
    CHAIN_NAME=$(echo "$CHAIN_JSON" | jq -r '.chain // ""')
else
    CHAIN_NAME=""
fi

# Resolve network display label
# Priority: NETWORK_LABEL from config > auto-detect from chain field
if [ -n "$NETWORK_LABEL" ]; then
    NETWORK_DISPLAY="$NETWORK_LABEL"
elif [ "$CHAIN_NAME" = "test" ]; then
    NETWORK_DISPLAY="Testnet"
elif [ "$CHAIN_NAME" = "main" ]; then
    NETWORK_DISPLAY="Mainnet"
elif [ "$CHAIN_NAME" = "regtest" ]; then
    NETWORK_DISPLAY="Regtest"
elif [ -n "$CHAIN_NAME" ]; then
    # Unknown chain value — capitalize first letter
    NETWORK_DISPLAY=$(echo "$CHAIN_NAME" | sed 's/./\U&/')
else
    NETWORK_DISPLAY=""
fi

# --- 1. getoracles true — per-oracle heartbeat status ---
ORACLES_JSON=$($CLI getoracles true 2>&1)
if [ $? -ne 0 ] || echo "$ORACLES_JSON" | grep -q "error"; then
    echo "ERROR: getoracles true failed: $ORACLES_JSON"
    if [ "$DRY_RUN" != true ]; then
        # Include network label in error message if available
        if [ -n "$NETWORK_DISPLAY" ]; then
            NET_ERR="${NETWORK_DISPLAY} — "
        else
            NET_ERR=""
        fi
        post_to_gitter "⚠️ Oracle Network Monitor — ${NET_ERR}$(date -u +'%Y-%m-%d %H:%M UTC')

Status check failed: could not reach DigiByte daemon. Will retry next cycle."
    fi
    exit 1
fi

# --- 2. getoracleprice — consensus price + status ---
PRICE_JSON=$($CLI getoracleprice 2>&1)
PRICE_OK=$?

# --- 3. getdigidollardeploymentinfo — BIP9 + MuSig2 + quorum config ---
DEPLOY_JSON=$($CLI getdigidollardeploymentinfo 2>&1)
DEPLOY_OK=$?

# --- 4. getoraclesigners 50 — recent bundle signers ---
SIGNERS_JSON=$($CLI getoraclesigners 50 2>&1)
SIGNERS_OK=$?

# ============================================================================
# PARSE RPC DATA
# ============================================================================

# --- Oracle heartbeat counts ---
TOTAL_ORACLES=$(echo "$ORACLES_JSON" | jq 'length')
FRESH_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status == "fresh")] | length')
STALE_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status == "stale")] | length')

# Inactive = everything that isn't fresh or stale (none, unknown, null, missing)
INACTIVE_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale")] | length')

# Total offline = not fresh (stale + inactive)
OFFLINE_COUNT=$((TOTAL_ORACLES - FRESH_COUNT))

# --- Consensus price ---
if [ $PRICE_OK -eq 0 ] && ! echo "$PRICE_JSON" | grep -q "error"; then
    PRICE_USD=$(echo "$PRICE_JSON" | jq -r '.price_usd // "N/A"')
    PRICE_STATUS=$(echo "$PRICE_JSON" | jq -r '.status // "unknown"')
    PRICE_STALE=$(echo "$PRICE_JSON" | jq -r '.is_stale // false')
    ORACLE_COUNT=$(echo "$PRICE_JSON" | jq -r '.oracle_count // 0')
else
    PRICE_USD="N/A"
    PRICE_STATUS="unavailable"
    PRICE_STALE="true"
    ORACLE_COUNT=0
fi

# --- Deployment info ---
if [ $DEPLOY_OK -eq 0 ] && ! echo "$DEPLOY_JSON" | grep -q "error"; then
    BIP9_STATUS=$(echo "$DEPLOY_JSON" | jq -r '.status // "unknown"')
    BIP9_BIT=$(echo "$DEPLOY_JSON" | jq -r '.bit // "N/A"')
    QUORUM_REQUIRED=$(echo "$DEPLOY_JSON" | jq -r '.oracle_consensus_required // 7')
    TOTAL_SLOTS=$(echo "$DEPLOY_JSON" | jq -r '.oracle_total_slots // 35')
    MUSIG2_EPOCH=$(echo "$DEPLOY_JSON" | jq -r '.musig2_session.epoch // "N/A"')
    MUSIG2_STATE=$(echo "$DEPLOY_JSON" | jq -r '.musig2_session.state // "unknown"')
    MUSIG2_NONCES=$(echo "$DEPLOY_JSON" | jq -r '.musig2_session.nonce_count // 0')
    MUSIG2_SIGS=$(echo "$DEPLOY_JSON" | jq -r '.musig2_session.partial_sig_count // 0')
else
    BIP9_STATUS="unavailable"
    BIP9_BIT="N/A"
    QUORUM_REQUIRED=7
    TOTAL_SLOTS=35
    MUSIG2_EPOCH="N/A"
    MUSIG2_STATE="unavailable"
    MUSIG2_NONCES=0
    MUSIG2_SIGS=0
fi

# --- Last bundle signers ---
if [ $SIGNERS_OK -eq 0 ] && ! echo "$SIGNERS_JSON" | grep -q "error"; then
    BUNDLE_COUNT=$(echo "$SIGNERS_JSON" | jq -r '.bundle_count // 0')
    if [ "$BUNDLE_COUNT" -gt 0 ]; then
        # Most recent bundle (newest first)
        LAST_BUNDLE_HEIGHT=$(echo "$SIGNERS_JSON" | jq -r '.bundles[0].height // "N/A"')
        LAST_BUNDLE_SIGNERS=$(echo "$SIGNERS_JSON" | jq -r '.bundles[0].signer_count // 0')
        LAST_BUNDLE_EPOCH=$(echo "$SIGNERS_JSON" | jq -r '.bundles[0].epoch // "N/A"')
    else
        LAST_BUNDLE_HEIGHT="none in window"
        LAST_BUNDLE_SIGNERS=0
        LAST_BUNDLE_EPOCH="N/A"
    fi
else
    BUNDLE_COUNT=0
    LAST_BUNDLE_HEIGHT="unavailable"
    LAST_BUNDLE_SIGNERS=0
    LAST_BUNDLE_EPOCH="N/A"
fi

# ============================================================================
# DETERMINE QUORUM STATUS
# ============================================================================

if [ "$FRESH_COUNT" -ge "$QUORUM_GREEN" ]; then
    QUORUM_LABEL="healthy"
    STATUS_EMOJI="🟢"
elif [ "$FRESH_COUNT" -ge "$QUORUM_YELLOW" ]; then
    QUORUM_LABEL="thin"
    STATUS_EMOJI="🟡"
elif [ "$FRESH_COUNT" -ge "$QUORUM_REQUIRED" ]; then
    QUORUM_LABEL="critical"
    STATUS_EMOJI="🔴"
else
    QUORUM_LABEL="LOST — below quorum"
    STATUS_EMOJI="🚨"
fi

# ============================================================================
# RESET MENTION COUNTS FOR FRESH ORACLES
# ============================================================================

# Any oracle that's currently fresh should have its ping count cleared
# (so if they go stale again later, they get a new round of pings)
if [ -f "$MENTION_STATE_FILE" ]; then
    while read -r fresh_id; do
        reset_mention_count "$fresh_id"
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "fresh") | .oracle_id')
fi

# ============================================================================
# FORMAT MESSAGE
# ============================================================================

TIMESTAMP=$(date -u +'%Y-%m-%d %H:%M UTC')

# Build network label segment for header
if [ -n "$NETWORK_DISPLAY" ]; then
    NET_SEGMENT="${NETWORK_DISPLAY} — "
else
    NET_SEGMENT=""
fi

# Build the message header
MESSAGE="${STATUS_EMOJI} Oracle Network Status — ${NET_SEGMENT}${TIMESTAMP}

Fresh Heartbeats: ${FRESH_COUNT}/${TOTAL_SLOTS} (quorum ${QUORUM_LABEL} — threshold: ${QUORUM_REQUIRED})
Consensus price: \$${PRICE_USD} (status: ${PRICE_STATUS})
MuSig2: epoch ${MUSIG2_EPOCH}, ${MUSIG2_STATE}, ${MUSIG2_NONCES}/${QUORUM_REQUIRED} nonces, ${MUSIG2_SIGS}/${QUORUM_REQUIRED} sigs
BIP9: ${BIP9_STATUS} (bit ${BIP9_BIT})
Last bundle: block ${LAST_BUNDLE_HEIGHT}, signed by ${LAST_BUNDLE_SIGNERS} oracles"

# Add software versions (top 2 by fresh operator count)
SOFTWARE_SECTION=$(echo "$ORACLES_JSON" | jq -r '
  [.[] | select(.heartbeat_status == "fresh") | .sv = (if .software_version == null or .software_version == "" then "unknown" else .software_version end)] |
  group_by(.sv) |
  map({version: .[0].sv, count: length}) |
  sort_by(-.count) |
  .[0:2] |
  to_entries |
  .[] |
  "  ✅ " +
  (if (.value.version | length) > 25 then (.value.version[:22] + "...") else .value.version end) +
  " : \(.value.count) operators"
')

if [ -n "$SOFTWARE_SECTION" ]; then
    MESSAGE="${MESSAGE}

Software:
${SOFTWARE_SECTION}"
fi

# ============================================================================
# BUILD STALE SECTION WITH @ MENTIONS
# ============================================================================

if [ "$STALE_COUNT" -gt 0 ]; then
    STALE_SECTION=""

    while IFS='|' read -r oid oname; do
        line="  — ID ${oid} ${oname}"

        # Look up Gitter handle and apply mention logic
        handle=$(get_gitter_handle "$oid")
        if [ -n "$handle" ]; then
            count=$(get_mention_count "$oid")
            if [ "$count" -lt "$MENTION_MAX" ]; then
                # Only add @ to message if this handle wasn't already mentioned (dual-slot dedup)
                if ! is_already_mentioned "$handle"; then
                    line="${line} ${handle}"
                    record_mention "$handle" "$oname"
                fi
                # Always increment count even if deduped — keeps dual-slot counts in sync
                if [ "$DRY_RUN" != true ]; then
                    increment_mention_count "$oid" "$count"
                fi
            fi
        fi

        if [ -z "$STALE_SECTION" ]; then
            STALE_SECTION="${line}"
        else
            STALE_SECTION="${STALE_SECTION}
${line}"
        fi
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "stale") | "\(.oracle_id)|\(.name)"')

    MESSAGE="${MESSAGE}

⚠️ Stale (${STALE_COUNT}):
${STALE_SECTION}"
fi

# ============================================================================
# BUILD INACTIVE SECTION WITH @ MENTIONS
# ============================================================================

if [ "$INACTIVE_COUNT" -gt 0 ]; then
    INACTIVE_SECTION=""

    while IFS='|' read -r oid oname; do
        line="  — ID ${oid} ${oname}"

        # Look up Gitter handle and apply mention logic
        handle=$(get_gitter_handle "$oid")
        if [ -n "$handle" ]; then
            count=$(get_mention_count "$oid")
            if [ "$count" -lt "$MENTION_MAX" ]; then
                if ! is_already_mentioned "$handle"; then
                    line="${line} ${handle}"
                    record_mention "$handle" "$oname"
                fi
                if [ "$DRY_RUN" != true ]; then
                    increment_mention_count "$oid" "$count"
                fi
            fi
        fi

        if [ -z "$INACTIVE_SECTION" ]; then
            INACTIVE_SECTION="${line}"
        else
            INACTIVE_SECTION="${INACTIVE_SECTION}
${line}"
        fi
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale") | "\(.oracle_id)|\(.name)"')

    MESSAGE="${MESSAGE}

❌ Inactive (${INACTIVE_COUNT}):
${INACTIVE_SECTION}"
fi

# ============================================================================
# BUILD HTML MESSAGE WITH MENTION PILLS
# ============================================================================

# If there are mentions, build an HTML version with clickable mention pills.
# The plain text MESSAGE (with raw handles) stays as the body fallback.
# The HTML version uses <a href="matrix.to"> pills for clean display.
MESSAGE_HTML=""

if [ ${#ALL_MENTION_IDS[@]} -gt 0 ]; then
    # Start with the plain text message, convert newlines to <br>
    MESSAGE_HTML=$(printf '%s' "$MESSAGE" | sed 's/$/<br>/g')

    # Replace each raw handle with an HTML mention pill
    for i in "${!ALL_MENTION_IDS[@]}"; do
        handle="${ALL_MENTION_IDS[$i]}"
        display="${ALL_MENTION_NAMES[$i]}"
        # Escape dots in handle for sed pattern matching
        escaped_handle=$(printf '%s' "$handle" | sed 's/\./\\./g')
        pill="<a href=\"https://matrix.to/#/${handle}\">@${display}</a>"
        MESSAGE_HTML=$(printf '%s' "$MESSAGE_HTML" | sed "s|${escaped_handle}|${pill}|g")
    done
fi

# ============================================================================
# POST OR PRINT
# ============================================================================

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "--- Parsed Data ---"
    echo "Network: ${NETWORK_DISPLAY:-"(none)"} (chain=${CHAIN_NAME:-"N/A"}, config=${NETWORK_LABEL:-"auto-detect"})"
    echo "Config file: $CONFIG_FILE"
    echo "Fresh: $FRESH_COUNT  Stale: $STALE_COUNT  Inactive: $INACTIVE_COUNT  Total: $TOTAL_ORACLES"
    echo "Quorum required: $QUORUM_REQUIRED  Status: $QUORUM_LABEL"
    echo "Price: \$$PRICE_USD ($PRICE_STATUS)  Stale: $PRICE_STALE"
    echo "BIP9: $BIP9_STATUS (bit $BIP9_BIT)"
    echo "MuSig2: epoch $MUSIG2_EPOCH, state=$MUSIG2_STATE, nonces=$MUSIG2_NONCES, sigs=$MUSIG2_SIGS"
    echo "Bundles in window: $BUNDLE_COUNT  Last: block $LAST_BUNDLE_HEIGHT ($LAST_BUNDLE_SIGNERS signers)"
    echo ""
    echo "--- Mention State ---"
    echo "Roster file: $ROSTER_FILE ($([ -f "$ROSTER_FILE" ] && echo "found" || echo "NOT FOUND — mentions disabled"))"
    echo "Mention state: $MENTION_STATE_FILE"
    echo "Mention max: $MENTION_MAX pings per outage"
    if [ ${#ALL_MENTION_IDS[@]} -gt 0 ]; then
        echo "Would mention (${#ALL_MENTION_IDS[@]}): ${ALL_MENTION_IDS[*]}"
    else
        echo "No mentions this cycle."
    fi
fi

# Build comma-separated mention IDs for m.mentions
MENTION_CSV=""
if [ ${#ALL_MENTION_IDS[@]} -gt 0 ]; then
    MENTION_CSV=$(IFS=','; echo "${ALL_MENTION_IDS[*]}")
fi

post_to_gitter "$MESSAGE" "$MESSAGE_HTML" "$MENTION_CSV"

exit 0
