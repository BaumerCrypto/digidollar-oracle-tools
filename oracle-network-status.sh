#!/bin/bash
###############################################################################
# oracle-network-status.sh — DGB Oracle Network Status Bot (Gitter via Matrix)
# Version: 1.6
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
#  10. Test:  ./oracle-network-status.sh --endgame-only --dry-run
#  11. Cron:  5 */12 * * * /home/YOUR_USER/oracle-network-status.sh 2>/dev/null
#
# FLAGS:
#   (none)              Collect data and post to Gitter
#   --dry-run           Collect data, print to terminal, skip Gitter post
#   --test              Send a test message to Gitter to verify Matrix API
#   --test-mention      Send a test mention to verify notifications work
#   --config /path      Use alternate config file (enables dual-instance)
#   --endgame-only      Mainnet endgame ticker (v1.6). Posts ONLY if
#                       LOCKED_IN + <24h to activation, OR ACTIVE + birth
#                       announcement not yet fired. Silent exit otherwise.
#                       Designed for hourly cron alongside regular 12hr cron.
#
# DUAL-INSTANCE EXAMPLE (testnet + mainnet on one VPS):
#   # Testnet (default config, 12hr status pulse)
#   5 */12 * * * /home/YOUR_USER/oracle-network-status.sh 2>/dev/null
#   # Mainnet (custom config, 12hr status pulse)
#   10 */12 * * * /home/YOUR_USER/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config 2>/dev/null
#   # Mainnet (hourly endgame ticker, silent outside 24h band)
#   15 * * * *   /home/YOUR_USER/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config --endgame-only 2>/dev/null
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
#   ~/.oracle-monitor/activation_state   — v1.6, one-shot dedup for DD mainnet birth
#   ~/.oracle-monitor/endgame_last_post  — v1.6, hourly endgame cadence dedup
#
# CHANGELOG:
#   v1.6 — DigiDollar mainnet activation prep (July 2026).
#          (1) Software section rewrite: shows ALL versions with compliance
#          icons (accepted list configurable via ACCEPTED_VERSIONS in config).
#          Dashboard-matching total-operator counts, not fresh-only. rc46
#          long/short hash variants collapse to one line, similar for
#          pre-release git-hash suffixes. Compliant versions render with
#          green check; non-compliant with yellow triangle. (2) New Upgrade
#          nudge section pings fresh + non-compliant operators via existing
#          MENTION_MAX cap, reuses mention_state. Stale operators are not
#          double-pinged. (3) Issue #32 pre-activation guard: when running
#          against a mainnet daemon whose DigiDollar BIP9 status is not yet
#          active, the bot posts a compact standby message with countdown
#          (blocks / time / calendar UTC), not the full network status. Runs
#          in the LOCKED_IN, STARTED and DEFINED states. Testnet always uses
#          full status (DD active since block 600). (4) Graceful countdown
#          formatting: >24h shows days+hours, 1-24h shows hours, <1h shows
#          ACTIVATION IMMINENT with minutes, 0 blocks shows Awaiting next
#          block. (5) New --endgame-only flag for hourly countdown cron in
#          the last 24 hours before activation. Silent exit outside the band
#          so hourly cron only posts when it matters. (6) One-shot mainnet
#          birth announcement fires the first cron pass after DD flips to
#          ACTIVE. State recorded in activation_state file so both endgame
#          and 12hr crons cooperate without duplicating the announcement.
#          (7) Prose throughout the bot's output is em-dash free (commas,
#          colons, periods, parentheses only). Classic list-marker em-dash
#          preserved in operator lists for continuity with prior posts.
#   v1.5 — Full-repo audit fixes (July 2026). (1) Header cron examples
#          use generic /home/YOUR_USER paths. (2) Default quorum bands
#          brought in line with oracle-monitor.sh v2.5.1+ (12/10, was
#          20/12 — the config file overrides these either way). (3)
#          --dry-run no longer resets mention_state entries: dry-run
#          must not touch state. (4) --test-mention pings your own
#          ORACLE_ID from config instead of a hardcoded slot (previously
#          every operator's test pinged slot 17), falling back to the
#          first roster entry. (5) RPC failure detection now validates
#          JSON with jq -e instead of substring-grepping for "error" —
#          an oracle name containing "error" could trip the old check.
#          (6) formatted_body is HTML-escaped and mention-pill
#          substitution is sed-safe, so operator-supplied oracle names
#          containing &, <, > or backslashes can no longer inject markup
#          into the Gitter post or corrupt the pill replacement.
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

ENDGAME_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                echo "ERROR: --config requires a path argument."
                echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention] [--endgame-only]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --endgame-only)
            ENDGAME_ONLY=true
            shift
            ;;
        --dry-run|--test|--test-mention)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention] [--endgame-only]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        *)
            echo "Usage: $0 [--config /path] [--dry-run | --test | --test-mention] [--endgame-only]"
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

# Oracle identity — used by --test-mention to ping your own slot (v1.5).
# Normally set in the shared config file (same key oracle-monitor.sh uses).
ORACLE_ID=0

# Quorum alert bands (same defaults as oracle-monitor.sh v2.5.1+):
# 12/10 for mainnet (35-slot roster, 7-of-35 quorum). Override for
# testnet: GREEN=10, YELLOW=8.
QUORUM_GREEN=12
QUORUM_YELLOW=10

# Mention settings
MENTION_MAX=6

# Network label (auto-detected from getblockchaininfo if not set)
# Override examples: "Testnet26", "Mainnet", "Testnet"
NETWORK_LABEL=""

# Accepted software versions (v1.6). Space-separated list of version strings
# whose oracles are considered compliant with the network's software rules.
# Matching uses startswith(): "v9.26.4" matches "v9.26.4" AND "v9.26.4-gABC123"
# (release builds carrying a git hash suffix pass), while "v9.26.0rc46-gABC"
# does NOT match "v9.26.4" and is flagged as non-compliant.
#
# Default rule (Bastian, Gitter 2026-07-11): "any v9.26 will do to run
# the oracle service." Update per Jared's guidance for mainnet if the
# rule tightens post-activation.
#
# Dual-instance operators override per-config: testnet may accept broader,
# mainnet may narrow to a specific release once Jared confirms.
ACCEPTED_VERSIONS="v9.26.2 v9.26.3 v9.26.4"

# Turn the Upgrade nudge section on/off. If false, non-compliant operators
# are still flagged in the Software section with the yellow icon, but no
# @-pings fire. Default true. Some operators may want this off on mainnet
# during launch stabilization.
VERSION_NUDGE_ENABLED=true

# DigiByte target block time in seconds (used for endgame countdown).
# Real network runs slightly ahead of target under high hashrate. Estimate
# is honest-approximate, not precise.
BLOCK_TIME_SECS=15

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

# v1.6: one-shot birth-announcement dedup for mainnet DD activation.
# Written after the birth post lands successfully. Any subsequent cron
# pass sees the file and skips the announcement.
ACTIVATION_STATE_FILE="${MONITOR_DIR}/activation_state"

# v1.6: last-endgame-post timestamp (soft dedup for hourly cron edge cases).
ENDGAME_LAST_POST_FILE="${MONITOR_DIR}/endgame_last_post"

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
        payload=$(jq -n --arg body "🟢 Oracle Network Monitor, test message ($(date -u +'%Y-%m-%d %H:%M UTC'))" \
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
        # v1.5: ping YOUR OWN slot (ORACLE_ID from config), falling back
        # to the first roster entry. Previously hardcoded to slot 17,
        # which pinged the tool author from every operator's test.
        TEST_ID="${ORACLE_ID:-0}"
        test_handle=""
        if [ "$TEST_ID" != "0" ]; then
            test_handle=$(get_gitter_handle "$TEST_ID")
        fi
        if [ -z "$test_handle" ]; then
            first_line=$(grep -v '^#' "$ROSTER_FILE" | grep -v '^$' | head -1)
            TEST_ID=$(echo "$first_line" | cut -d'|' -f1)
            test_handle=$(echo "$first_line" | cut -d'|' -f2)
        fi
        if [ -z "$test_handle" ]; then
            echo "ERROR: No usable handle found. Set ORACLE_ID in $CONFIG_FILE or add entries to $ROSTER_FILE."
            exit 1
        fi
        echo "Sending test mention to ${test_handle} (oracle ID ${TEST_ID})..."
        txn_id="testmention_$(date +%s)"
        mention_array=$(echo "$test_handle" | jq -R . | jq -s .)
        payload=$(jq -n \
            --arg body "🟢 Bot account test, please ignore | ${test_handle} testing 12hr Oracle Monitor Bot @ mention feature!" \
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
# v1.6 HELPERS: COUNTDOWN, STANDBY, BIRTH ANNOUNCEMENT
# ============================================================================

# pretty_number: Insert thousands separators (commas) into an integer.
# Locale-independent: works whether or not en_US.UTF-8 grouping is enabled.
# Preserves the input if it's not a positive integer.
pretty_number() {
    local n="$1"
    if [ -z "$n" ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo "$n"
        return
    fi
    local out=""
    while [ ${#n} -gt 3 ]; do
        out=",${n: -3}${out}"
        n="${n:0:${#n}-3}"
    done
    echo "${n}${out}"
}

# format_countdown_line
# Emits a single line describing time to activation, band-appropriate.
# Args:  $1 blocks_remaining   $2 secs_remaining   $3 minutes   $4 hours   $5 days
# Bands: >24h shows days+hours, 1-24h shows hours, <1h ACTIVATION IMMINENT,
#        0 blocks shows Awaiting next block.
format_countdown_line() {
    local blocks="$1"
    local secs="$2"
    local mins="$3"
    local hrs="$4"
    local days="$5"

    # Singular/plural helpers
    local day_word hr_word min_word
    if [ "$days" -eq 1 ]; then day_word="day"; else day_word="days"; fi
    if [ "$hrs" -eq 1 ]; then hr_word="hour"; else hr_word="hours"; fi
    if [ "$mins" -eq 1 ]; then min_word="minute"; else min_word="minutes"; fi

    if [ "$blocks" -le 0 ]; then
        echo "   ⏳ Awaiting next block, activation on next block..."
    elif [ "$secs" -lt 60 ]; then
        # Sub-minute case: about to hit the block, don't render "0 minutes"
        echo "   ⏰ ACTIVATION IMMINENT, any moment now"
    elif [ "$secs" -lt 3600 ]; then
        echo "   ⏰ ACTIVATION IMMINENT, ~${mins} ${min_word}"
    elif [ "$secs" -lt 86400 ]; then
        echo "   Time to activation: ~${hrs} ${hr_word}"
    else
        echo "   Time to activation: ~${days} ${day_word} ${hrs} ${hr_word}"
    fi
}

# build_standby_message
# Constructs the LOCKED_IN / STARTED / DEFINED standby post body.
# Uses globals: NETWORK_DISPLAY, TIMESTAMP, TOTAL_SLOTS, QUORUM_REQUIRED,
# BIP9_STATUS, CURRENT_HEIGHT, ACTIVATION_HEIGHT, BLOCKS_REMAINING,
# SECS_REMAINING, MINUTES, HOURS, DAYS, ETA_UTC.
build_standby_message() {
    local bip9_upper
    bip9_upper=$(echo "$BIP9_STATUS" | tr '[:lower:]' '[:upper:]')

    local countdown
    countdown=$(format_countdown_line "$BLOCKS_REMAINING" "$SECS_REMAINING" "$MINUTES" "$HOURS" "$DAYS")

    # Format numbers with thousands separator (locale-independent).
    local cur_pretty act_pretty rem_pretty
    cur_pretty=$(pretty_number "$CURRENT_HEIGHT")
    act_pretty=$(pretty_number "$ACTIVATION_HEIGHT")
    rem_pretty=$(pretty_number "$BLOCKS_REMAINING")

    local msg
    msg="🟢 Oracle Network Status, ${NETWORK_DISPLAY:-Mainnet}, ${TIMESTAMP}

📅 DigiDollar Mainnet Activation: PENDING
   Current stage: ${bip9_upper} (bit ${BIP9_BIT})
   Current block: ${cur_pretty}
   Activation block: ${act_pretty}
   Blocks remaining: ${rem_pretty}
${countdown}"

    if [ -n "$ETA_UTC" ]; then
        msg="${msg}
   Estimated activation: ${ETA_UTC}"
    fi

    msg="${msg}

Roster: ${TOTAL_SLOTS} slots configured, ${QUORUM_REQUIRED}-of-${TOTAL_SLOTS} quorum threshold
Signing status: standby, mainnet oracles begin publishing at BIP9 ACTIVE

This bot will resume full network status posts (fresh heartbeats,
consensus price, MuSig2, upgrade nudges) automatically at activation."

    echo "$msg"
}

# build_birth_message
# One-shot mainnet activation announcement, fires on first cron pass after
# DigiDollar BIP9 flips to ACTIVE. Records Jared and DigiSwarm in the
# mention arrays so they get m.mentions notifications on this post only.
# Uses global: ACTIVATION_HEIGHT.
build_birth_message() {
    local act_pretty
    act_pretty=$(pretty_number "$ACTIVATION_HEIGHT")

    # Look up Jared and DigiSwarm handles from the roster.
    # Fall back to plaintext handles if roster entries not found.
    local jared_handle digiswarm_handle jared_txt digiswarm_txt
    jared_handle=$(get_gitter_handle 0)
    digiswarm_handle=$(get_gitter_handle 15)

    if [ -n "$jared_handle" ]; then
        record_mention "$jared_handle" "JaredCTate"
        jared_txt="$jared_handle"
    else
        jared_txt="@JaredCTate"
    fi

    if [ -n "$digiswarm_handle" ]; then
        record_mention "$digiswarm_handle" "DigiSwarm"
        digiswarm_txt="$digiswarm_handle"
    else
        digiswarm_txt="@DigiSwarm"
    fi

    cat <<EOF
🎉 DigiDollar Mainnet, ACTIVATED at Block ${act_pretty} 🎉

Congratulations!! After years of design, code, and community iteration,
DigiDollar is now live on DigiByte mainnet. A native, USD-pegged,
DGB-collateralized, oracle-priced, MuSig2-secured stablecoin,
Decentralized & built directly into the base layer.
No smart contracts, no custodians, no wrapped tokens.

Deep gratitude to:
  • ${jared_txt}, the architect, protocol lead, and the many years of consensus work. Thank you ${jared_txt}.
  • ${digiswarm_txt}, the GOAT of release engineering, from testnet through v9.26.4.
  • ALL 35 mainnet oracle operators now signing price bundles.
  • DigiByte miners and pools who upgraded to v9.26.2+, signaled algolock (bit 0) to shut down the Groestl attack, and signaled DigiDollar (bit 23) through to full activation.
  • Everyone in this room who tested, questioned, and kept us honest, you all deserve a HUGE round of applause 👏

Now we prove it in the wild!

Yours Truly: digibyte-maxi (Oracle slot 17), @BaumerCrypto2.0
github.com/BaumerCrypto/digidollar-oracle-tools
EOF
}

# ============================================================================
# RPC DATA COLLECTION
# ============================================================================

echo "[$(date -u)] Collecting oracle network data..."

# --- 0. getblockchaininfo — network identification ---
CHAIN_JSON=$($CLI getblockchaininfo 2>&1)
# v1.5: validate the JSON parse (jq -e) instead of substring-grepping
# for "error" — same change applied to every RPC check below.
if [ $? -eq 0 ] && echo "$CHAIN_JSON" | jq -e . >/dev/null 2>&1; then
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
if [ $? -ne 0 ] || ! echo "$ORACLES_JSON" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: getoracles true failed: $ORACLES_JSON"
    if [ "$DRY_RUN" != true ]; then
        # Include network label in error message if available
        if [ -n "$NETWORK_DISPLAY" ]; then
            NET_ERR="${NETWORK_DISPLAY}, "
        else
            NET_ERR=""
        fi
        post_to_gitter "⚠️ Oracle Network Monitor, ${NET_ERR}$(date -u +'%Y-%m-%d %H:%M UTC')

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
if [ $PRICE_OK -eq 0 ] && echo "$PRICE_JSON" | jq -e . >/dev/null 2>&1; then
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
if [ $DEPLOY_OK -eq 0 ] && echo "$DEPLOY_JSON" | jq -e . >/dev/null 2>&1; then
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

# --- v1.6: current block height + activation height + countdown vars ---
# Current block from getblockchaininfo (already validated earlier).
CURRENT_HEIGHT=$(echo "$CHAIN_JSON" | jq -r '.blocks // 0' 2>/dev/null)
[ -z "$CURRENT_HEIGHT" ] && CURRENT_HEIGHT=0

# Activation height. For LOCKED_IN state, activation happens at the end of
# the current retarget window. Try .status_next.height first (newer schema),
# then fall back to computing .since + .statistics.period.
ACTIVATION_HEIGHT=$(echo "$DEPLOY_JSON" | jq -r '.status_next.height // empty' 2>/dev/null)
if [ -z "$ACTIVATION_HEIGHT" ] || [ "$ACTIVATION_HEIGHT" = "null" ]; then
    DD_SINCE=$(echo "$DEPLOY_JSON" | jq -r '.since // 0' 2>/dev/null)
    DD_PERIOD=$(echo "$DEPLOY_JSON" | jq -r '.statistics.period // 40320' 2>/dev/null)
    if [ "$DD_SINCE" != "0" ] && [ "$DD_SINCE" != "" ] && [ "$DD_SINCE" != "null" ]; then
        ACTIVATION_HEIGHT=$((DD_SINCE + DD_PERIOD))
    else
        ACTIVATION_HEIGHT=""
    fi
fi

# Blocks + time remaining + calendar ETA.
BLOCKS_REMAINING=0
SECS_REMAINING=0
MINUTES=0
HOURS=0
DAYS=0
ETA_UTC=""

if [ -n "$ACTIVATION_HEIGHT" ] && [ "$ACTIVATION_HEIGHT" != "N/A" ] && [ "$CURRENT_HEIGHT" -gt 0 ]; then
    BLOCKS_REMAINING=$((ACTIVATION_HEIGHT - CURRENT_HEIGHT))
    [ "$BLOCKS_REMAINING" -lt 0 ] && BLOCKS_REMAINING=0

    SECS_REMAINING=$((BLOCKS_REMAINING * BLOCK_TIME_SECS))
    DAYS=$((SECS_REMAINING / 86400))
    HOURS=$(( (SECS_REMAINING % 86400) / 3600 ))
    MINUTES=$(( (SECS_REMAINING % 3600) / 60 ))

    NOW_EPOCH=$(date +%s)
    ETA_EPOCH=$((NOW_EPOCH + SECS_REMAINING))
    ETA_UTC=$(date -u -d "@${ETA_EPOCH}" '+%Y-%m-%d ~%H:%M UTC' 2>/dev/null || echo "")
fi

# --- Last bundle signers ---
if [ $SIGNERS_OK -eq 0 ] && echo "$SIGNERS_JSON" | jq -e . >/dev/null 2>&1; then
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
# v1.6: MODE BRANCHING (STANDBY / BIRTH / ENDGAME / FULL STATUS)
# ============================================================================
#
# The bot has four operating modes, decided here based on chain, DD BIP9
# status, activation-state file, and --endgame-only flag.
#
#   1. BIRTH mode:    Mainnet + DD ACTIVE + no activation_state file.
#                     Post one-shot birth announcement, write state file,
#                     then continue to full status (regular cron path).
#   2. STANDBY mode:  Mainnet + DD not-yet-ACTIVE.
#                     Post compact countdown message, exit.
#   3. ENDGAME mode:  Same trigger conditions as STANDBY, but from the
#                     hourly --endgame-only cron. Post only when inside the
#                     24h band; silent exit otherwise. STANDBY (from the
#                     regular 12hr cron) always posts to keep operators
#                     informed regardless of band.
#   4. FULL mode:     Testnet always (DD active since block 600), or
#                     mainnet after DD activation. Regular network status
#                     (fresh/quorum/MuSig2/Software/Upgrade/Stale/Inactive).
#
# Testnet birth is NOT triggered; testnet has been active since June 2026.
# Birth is gated on CHAIN_NAME == "main".
# ============================================================================

TIMESTAMP=$(date -u +'%Y-%m-%d %H:%M UTC')

# Resolve DD status (already parsed as BIP9_STATUS from top-level of
# getdigidollardeploymentinfo). Consolidate the "active" check here for
# readability.
DD_IS_ACTIVE=false
if [ "$BIP9_STATUS" = "active" ]; then
    DD_IS_ACTIVE=true
fi

# --- BIRTH announcement (once, mainnet, first cron pass after ACTIVE) ---
BIRTH_FIRED=false
if [ "$DD_IS_ACTIVE" = true ] && [ "$CHAIN_NAME" = "main" ] && [ ! -f "$ACTIVATION_STATE_FILE" ]; then
    echo "[$(date -u)] DigiDollar mainnet ACTIVE detected, birth announcement not yet fired. Firing now."
    BIRTH_MESSAGE=$(build_birth_message)

    # Build HTML pill version for the birth post (Jared + DigiSwarm mentions
    # were recorded in build_birth_message). Otherwise reuse the plain body.
    if [ ${#ALL_MENTION_IDS[@]} -gt 0 ]; then
        BIRTH_HTML=$(printf '%s' "$BIRTH_MESSAGE" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/$/<br>/g')
        for i in "${!ALL_MENTION_IDS[@]}"; do
            b_handle="${ALL_MENTION_IDS[$i]}"
            b_display="${ALL_MENTION_NAMES[$i]}"
            b_escaped_handle=$(printf '%s' "$b_handle" | sed 's/[][\.*^$]/\\&/g')
            b_display_html=$(printf '%s' "$b_display" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
            b_pill="<a href=\"https://matrix.to/#/${b_handle}\">@${b_display_html}</a>"
            b_pill_escaped=$(printf '%s' "$b_pill" | sed -e 's/[&\\]/\\&/g')
            BIRTH_HTML=$(printf '%s' "$BIRTH_HTML" | sed "s|${b_escaped_handle}|${b_pill_escaped}|g")
        done
        BIRTH_CSV=$(IFS=','; echo "${ALL_MENTION_IDS[*]}")
    else
        BIRTH_HTML=""
        BIRTH_CSV=""
    fi

    if post_to_gitter "$BIRTH_MESSAGE" "$BIRTH_HTML" "$BIRTH_CSV"; then
        # Record the activation height so subsequent cron passes see the
        # state file and skip the announcement. Only write on real posts;
        # dry-runs must not touch state.
        if [ "$DRY_RUN" != true ]; then
            echo "$ACTIVATION_HEIGHT" > "$ACTIVATION_STATE_FILE"
            echo "[$(date -u)] Birth announcement posted. activation_state written."
        fi
        BIRTH_FIRED=true
    else
        echo "[$(date -u)] WARNING: Birth announcement post failed. State file NOT written. Next cron will retry."
    fi

    # Reset mention arrays so downstream stale/inactive sections don't
    # inherit the Jared/DigiSwarm mentions.
    ALL_MENTION_IDS=()
    ALL_MENTION_NAMES=()
    MENTIONED_HANDLES=()

    # In --endgame-only mode, exit after firing birth (this is the whole job).
    if [ "$ENDGAME_ONLY" = true ]; then
        exit 0
    fi
    # Otherwise fall through to the regular full-status post below.
fi

# --- STANDBY / ENDGAME modes (mainnet, DD not yet active) ---
if [ "$DD_IS_ACTIVE" != true ] && [ "$CHAIN_NAME" = "main" ]; then
    # In endgame-only mode, only post when inside the 24h band.
    if [ "$ENDGAME_ONLY" = true ]; then
        if [ "$SECS_REMAINING" -le 0 ] || [ "$SECS_REMAINING" -ge 86400 ]; then
            [ "$DRY_RUN" = true ] && echo "[endgame-only] Outside 24h band (SECS_REMAINING=$SECS_REMAINING). Silent exit."
            exit 0
        fi
    fi

    STANDBY_MESSAGE=$(build_standby_message)
    post_to_gitter "$STANDBY_MESSAGE" "" ""

    # Soft dedup marker for hourly cron pattern.
    if [ "$DRY_RUN" != true ]; then
        date +%s > "$ENDGAME_LAST_POST_FILE" 2>/dev/null || true
    fi
    exit 0
fi

# --- ENDGAME-ONLY on testnet or on already-active mainnet: silent exit ---
# (Endgame ticker is a mainnet-pre-activation feature. Testnet DD is active
# since block 600, so there's nothing to count down to. Already-active mainnet
# has already fired birth above and continues to full-status mode via the
# regular 12hr cron path, not the hourly endgame cron.)
if [ "$ENDGAME_ONLY" = true ]; then
    [ "$DRY_RUN" = true ] && echo "[endgame-only] Not applicable this run (chain=$CHAIN_NAME, dd_active=$DD_IS_ACTIVE). Silent exit."
    exit 0
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
    QUORUM_LABEL="LOST, below quorum"
    STATUS_EMOJI="🚨"
fi

# ============================================================================
# RESET MENTION COUNTS FOR FRESH ORACLES
# ============================================================================

# Any oracle that's currently fresh should have its ping count cleared
# (so if they go stale again later, they get a new round of pings)
# v1.5: skipped in --dry-run — dry-run must not touch mention state.
if [ -f "$MENTION_STATE_FILE" ] && [ "$DRY_RUN" != true ]; then
    while read -r fresh_id; do
        reset_mention_count "$fresh_id"
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "fresh") | .oracle_id')
fi

# ============================================================================
# FORMAT MESSAGE
# ============================================================================

# v1.6: TIMESTAMP is now set earlier in the mode-branching block.

# Build network label segment for header (v1.6: comma, not em-dash)
if [ -n "$NETWORK_DISPLAY" ]; then
    NET_SEGMENT="${NETWORK_DISPLAY}, "
else
    NET_SEGMENT=""
fi

# Build the message header (v1.6: em-dashes replaced with commas in prose)
MESSAGE="${STATUS_EMOJI} Oracle Network Status, ${NET_SEGMENT}${TIMESTAMP}

Fresh Heartbeats: ${FRESH_COUNT}/${TOTAL_SLOTS} (quorum ${QUORUM_LABEL}, threshold: ${QUORUM_REQUIRED})
Consensus price: \$${PRICE_USD} (status: ${PRICE_STATUS})
MuSig2: epoch ${MUSIG2_EPOCH}, ${MUSIG2_STATE}, ${MUSIG2_NONCES}/${QUORUM_REQUIRED} nonces, ${MUSIG2_SIGS}/${QUORUM_REQUIRED} sigs
BIP9: ${BIP9_STATUS} (bit ${BIP9_BIT})
Last bundle: block ${LAST_BUNDLE_HEIGHT}, signed by ${LAST_BUNDLE_SIGNERS} oracles"

# ============================================================================
# v1.6: SOFTWARE SECTION (all versions, dashboard totals, compliance icons)
# ============================================================================
#
# Groups all oracles by canonical display version (rc46 hash variants
# collapse to one line), counts total operators per group (matches the
# DigiByte Stats dashboard exactly), sorts descending by count.
#
# Compliance is determined by the ACCEPTED_VERSIONS config list using a
# startswith() rule so "v9.26.4-g5bcd3a8" matches "v9.26.4".
# Compliant: ✅  Non-compliant (pre-release / unknown): ⚠️
#
# Display canonicalization:
#   v9.26.4                        -> v9.26.4
#   v9.26.4-g5bcd3a8               -> v9.26.4                          (release + hash)
#   v9.26.0rc46-g873d6d068b9fe9... -> v9.26.0rc46 (pre-release)        (long hash)
#   v9.26.0rc46-873d6d068b9f       -> v9.26.0rc46 (pre-release)        (short hash)
#   v9.26.1-pre2-g47fa47f9128c...  -> v9.26.1-pre2 (pre-release)       (pre + hash)
#   null / ""                      -> No version reported

SOFTWARE_SECTION=$(echo "$ORACLES_JSON" | jq -r --arg accepted "$ACCEPTED_VERSIONS" '
  # Strip -g<hash> and long bare -<hash> suffixes for a canonical form.
  def canonical:
    if . == null or . == "" then ""
    else sub("-g[0-9a-f]+.*$"; "") | sub("-[0-9a-f]{8,}$"; "")
    end;

  # Compliance: canonical form must exactly match one of the accepted list.
  def is_compliant($ok):
    . as $sv |
    if $sv == null or $sv == "" then false
    else
      ($ok | split(" ")) as $list |
      ($sv | canonical) as $c |
      any($list[]; . == $c)
    end;

  # Display label: adds "(pre-release)" tag for rc/pre versions; special
  # label for unreported version.
  def display_label:
    . as $sv |
    if $sv == null or $sv == "" then "No version reported"
    else
      ($sv | canonical) as $c |
      if ($c | test("rc")) or ($c | test("pre")) then
        $c + " (pre-release)"
      else
        $c
      end
    end;

  # Map every oracle to {label, compliant} pairs, group by label, count.
  [.[] | {
    label: (.software_version | display_label),
    compliant: (.software_version | is_compliant($accepted))
  }] |
  group_by(.label) |
  map({
    label: .[0].label,
    count: length,
    compliant: .[0].compliant
  }) |
  sort_by(-.count) |
  .[] |
  (if .compliant then "  ✅ " else "  ⚠️ " end) +
  .label +
  ": " + (.count | tostring) +
  " operator" + (if .count == 1 then "" else "s" end)
')

if [ -n "$SOFTWARE_SECTION" ]; then
    MESSAGE="${MESSAGE}

Software (accepted: $(echo "$ACCEPTED_VERSIONS" | sed 's/ / \/ /g')):
${SOFTWARE_SECTION}"
fi

# ============================================================================
# v1.6: UPGRADE NUDGE SECTION (fresh + non-compliant, roster-handle-aware)
# ============================================================================
#
# Lists FRESH oracles whose canonical version is NOT in ACCEPTED_VERSIONS.
# Reuses the existing MENTION_MAX cap and mention_state file to avoid
# spamming operators. Stale/inactive operators are NOT included here (they
# are already pinged in the Stale/Inactive sections; version-nudging them
# on top would double-ping the same problem).

if [ "$VERSION_NUDGE_ENABLED" = "true" ]; then
    # Extract fresh + non-compliant IDs, names, and canonical labels.
    UPGRADE_ROWS=$(echo "$ORACLES_JSON" | jq -r --arg accepted "$ACCEPTED_VERSIONS" '
      def canonical:
        if . == null or . == "" then ""
        else sub("-g[0-9a-f]+.*$"; "") | sub("-[0-9a-f]{8,}$"; "")
        end;
      def is_compliant($ok):
        . as $sv |
        if $sv == null or $sv == "" then false
        else
          ($ok | split(" ")) as $list |
          ($sv | canonical) as $c |
          any($list[]; . == $c)
        end;
      [.[] |
        select(.heartbeat_status == "fresh") |
        select((.software_version | is_compliant($accepted)) | not) |
        {oid: .oracle_id, name: .name, sv: (.software_version // "")}
      ] |
      .[] | "\(.oid)|\(.name // "unknown")|\(.sv)"
    ')

    if [ -n "$UPGRADE_ROWS" ]; then
        UPGRADE_SECTION=""
        UPGRADE_COUNT=0

        while IFS='|' read -r oid oname osv; do
            [ -z "$oid" ] && continue
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))

            line="  — ID ${oid} ${oname}"

            # Roster handle + ping cap (mirrors stale-section pattern).
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

            if [ -z "$UPGRADE_SECTION" ]; then
                UPGRADE_SECTION="${line}"
            else
                UPGRADE_SECTION="${UPGRADE_SECTION}
${line}"
            fi
        done <<< "$UPGRADE_ROWS"

        if [ "$UPGRADE_COUNT" -gt 0 ]; then
            MESSAGE="${MESSAGE}

📢 Please upgrade to $(echo "$ACCEPTED_VERSIONS" | awk '{print $1}') or newer:
${UPGRADE_SECTION}"
        fi
    fi
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
    # v1.5: HTML-escape the plain message (&, <, >) BEFORE building the
    # formatted_body, so operator-supplied oracle names can't inject
    # markup into the Gitter post. Then convert newlines to <br>.
    MESSAGE_HTML=$(printf '%s' "$MESSAGE" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/$/<br>/g')

    # Replace each raw handle with an HTML mention pill
    for i in "${!ALL_MENTION_IDS[@]}"; do
        handle="${ALL_MENTION_IDS[$i]}"
        display="${ALL_MENTION_NAMES[$i]}"
        # v1.5: escape every BRE-special char in the handle (was dots
        # only), HTML-escape the display name, and escape & / \ in the
        # replacement so sed can't mangle or expand it.
        escaped_handle=$(printf '%s' "$handle" | sed 's/[][\.*^$]/\\&/g')
        display_html=$(printf '%s' "$display" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
        pill="<a href=\"https://matrix.to/#/${handle}\">@${display_html}</a>"
        pill_escaped=$(printf '%s' "$pill" | sed -e 's/[&\\]/\\&/g')
        MESSAGE_HTML=$(printf '%s' "$MESSAGE_HTML" | sed "s|${escaped_handle}|${pill_escaped}|g")
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
