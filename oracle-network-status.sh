#!/bin/bash
###############################################################################
# oracle-network-status.sh — DGB Oracle Network Status Bot (Gitter via Matrix)
# Version: 1.2
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
#   6. Test:  ./oracle-network-status.sh --dry-run
#   7. Test:  ./oracle-network-status.sh --test
#   8. Cron:  0 */12 * * * /home/dgboracle/oracle-network-status.sh 2>/dev/null
#
# FLAGS:
#   (none)     Collect data and post to Gitter
#   --dry-run  Collect data, print to terminal, skip Gitter post
#   --test     Send a test message to Gitter to verify Matrix API
#
# DATA SOURCES (RPCs):
#   getoracles true              — per-oracle heartbeat status (active/offline list)
#   getoracleprice               — consensus price, status, oracle count
#   getdigidollardeploymentinfo  — BIP9 status, quorum config, MuSig2 session
#   getoraclesigners 10          — recent bundle signer participation
#
# CHANGELOG:
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
# CONFIGURATION — DEFAULTS (override in ~/.oracle-monitor/config)
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

# ============================================================================
# LOAD EXTERNAL CONFIG (overrides defaults above)
# ============================================================================

CONFIG_FILE="${HOME}/.oracle-monitor/config"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Runtime flag
DRY_RUN=false

# ============================================================================
# FLAG PARSING
# ============================================================================

case "${1:-}" in
    --dry-run)
        DRY_RUN=true
        echo "[DRY RUN] Will collect data and print — no Gitter post."
        ;;
    --test)
        if [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_ROOM_ID" ]; then
            echo "ERROR: MATRIX_ACCESS_TOKEN and MATRIX_ROOM_ID must be set in $CONFIG_FILE"
            exit 1
        fi
        echo "Sending test message to Gitter..."
        txn_id="test_$(date +%s)"
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${txn_id}" \
            -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"msgtype\":\"m.text\",\"body\":\"🟢 Oracle Network Monitor — test message ($(date -u +'%Y-%m-%d %H:%M UTC'))\"}")
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
    "")
        # Normal run
        ;;
    *)
        echo "Usage: $0 [--dry-run | --test]"
        exit 1
        ;;
esac

# ============================================================================
# MATRIX API — POST TO GITTER
# ============================================================================

post_to_gitter() {
    local message="$1"

    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════"
        echo "  MESSAGE THAT WOULD BE POSTED TO GITTER:"
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "$message"
        echo ""
        echo "═══════════════════════════════════════════════"
        return 0
    fi

    if [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_ROOM_ID" ]; then
        echo "ERROR: MATRIX_ACCESS_TOKEN and MATRIX_ROOM_ID not set. Run with --dry-run or configure."
        return 1
    fi

    local txn_id="status_$(date +%s%N)"
    local escaped_message
    escaped_message=$(echo "$message" | jq -Rs .)

    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${MATRIX_ROOM_ID}/send/m.room.message/${txn_id}" \
        -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"msgtype\":\"m.text\",\"body\":${escaped_message}}")

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

# --- 1. getoracles true — per-oracle heartbeat status ---
ORACLES_JSON=$($CLI getoracles true 2>&1)
if [ $? -ne 0 ] || echo "$ORACLES_JSON" | grep -q "error"; then
    echo "ERROR: getoracles true failed: $ORACLES_JSON"
    if [ "$DRY_RUN" != true ]; then
        post_to_gitter "⚠️ Oracle Network Monitor — $(date -u +'%Y-%m-%d %H:%M UTC')

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

# --- 4. getoraclesigners 10 — recent bundle signers ---
SIGNERS_JSON=$($CLI getoraclesigners 10 2>&1)
SIGNERS_OK=$?

# ============================================================================
# PARSE RPC DATA
# ============================================================================

# --- Oracle heartbeat counts ---
TOTAL_ORACLES=$(echo "$ORACLES_JSON" | jq 'length')
FRESH_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status == "fresh")] | length')
STALE_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status == "stale")] | length')

# Not connected = everything that isn't fresh or stale (none, unknown, null, missing)
NOT_CONNECTED_COUNT=$(echo "$ORACLES_JSON" | jq '[.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale")] | length')

# Total offline = not fresh (stale + not connected)
OFFLINE_COUNT=$((TOTAL_ORACLES - FRESH_COUNT))

# Build separate lists for stale (liveness concern) vs not connected (never set up)
STALE_LIST=$(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "stale") | "ID \(.oracle_id) (\(.name))"')
NOT_CONNECTED_LIST=$(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale") | "ID \(.oracle_id) (\(.name))"')

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
# FORMAT MESSAGE
# ============================================================================

TIMESTAMP=$(date -u +'%Y-%m-%d %H:%M UTC')

# Build the message
MESSAGE="${STATUS_EMOJI} Oracle Network Status — ${TIMESTAMP}

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
  (if .key == 0 then "  ✅ " else "  🔄 " end) +
  (if (.value.version | length) > 25 then (.value.version[:22] + "...") else .value.version end) +
  " : \(.value.count) operators"
')

if [ -n "$SOFTWARE_SECTION" ]; then
    MESSAGE="${MESSAGE}

Software:
${SOFTWARE_SECTION}"
fi

# Add stale list (liveness concern — were running, went down)
if [ "$STALE_COUNT" -gt 0 ]; then
    STALE_FORMATTED=$(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "stale") | "  — ID \(.oracle_id) \(.name)"')
    MESSAGE="${MESSAGE}

⚠️ Stale (${STALE_COUNT}):
${STALE_FORMATTED}"
fi

# Add not connected list (never set up on this testnet)
if [ "$NOT_CONNECTED_COUNT" -gt 0 ]; then
    NC_FORMATTED=$(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale") | "  — ID \(.oracle_id) \(.name)"')
    MESSAGE="${MESSAGE}

❌ Not connected (${NOT_CONNECTED_COUNT}):
${NC_FORMATTED}"
fi

# ============================================================================
# POST OR PRINT
# ============================================================================

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "--- Parsed Data ---"
    echo "Fresh: $FRESH_COUNT  Stale: $STALE_COUNT  Not connected: $NOT_CONNECTED_COUNT  Total: $TOTAL_ORACLES"
    echo "Quorum required: $QUORUM_REQUIRED  Status: $QUORUM_LABEL"
    echo "Price: \$$PRICE_USD ($PRICE_STATUS)  Stale: $PRICE_STALE"
    echo "BIP9: $BIP9_STATUS (bit $BIP9_BIT)"
    echo "MuSig2: epoch $MUSIG2_EPOCH, state=$MUSIG2_STATE, nonces=$MUSIG2_NONCES, sigs=$MUSIG2_SIGS"
    echo "Bundles in window: $BUNDLE_COUNT  Last: block $LAST_BUNDLE_HEIGHT ($LAST_BUNDLE_SIGNERS signers)"
    if [ "$STALE_COUNT" -gt 0 ]; then echo "Stale ($STALE_COUNT): $STALE_LIST"; fi
    if [ "$NOT_CONNECTED_COUNT" -gt 0 ]; then echo "Not connected ($NOT_CONNECTED_COUNT): $NOT_CONNECTED_LIST"; fi
fi

post_to_gitter "$MESSAGE"

exit 0
