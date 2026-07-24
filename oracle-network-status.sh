#!/bin/bash
###############################################################################
# oracle-network-status.sh — DGB Oracle Network Status Bot (Gitter via Matrix)
# Version: 1.7.2
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
#   #   NOTE (v1.7.2): only useful on a chain still heading TO activation.
#   #   Once a chain is active this silent-exits on every run — mainnet
#   #   activated at block 23,869,440 on 2026-07-17, so mainnet operators
#   #   can leave this line out. Keep it for a future testnet countdown.
#   15 * * * *   /home/YOUR_USER/oracle-network-status.sh --config ~/.oracle-monitor-mainnet/config --endgame-only 2>/dev/null
#
# DATA SOURCES (RPCs):
#   getblockchaininfo            — chain identification (testnet/mainnet)
#   getdeploymentinfo            — BIP9 standard deployment info (activation
#                                  height math; since+period in LOCKED_IN,
#                                  since alone in ACTIVE)
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
#   ~/.oracle-monitor/endgame_last_post  — v1.6.3, in-band dedup marker (written
#                                          on successful standby/endgame posts,
#                                          read by the 12hr standby pass)
#
# CHANGELOG:
#   v1.7.2 — Cosmetic follow-up to the v1.7.0 burial work, caught on the
#          first live v9.26.5 card. The card rendered "BIP9: active (bit
#          N/A)" instead of "(bit buried)". Cause: the deployment read
#          used `jq -r '.bit // "N/A"'`, so when the buried shape omits
#          .bit entirely, BIP9_BIT was set to the literal string "N/A" —
#          non-empty, so the display default ${BIP9_BIT:-buried} could
#          never fire. Fixed by defaulting that read to empty instead.
#          The three cases are now distinct and each correct: v9.26.4
#          returns the real bit ("bit 23"); v9.26.5's buried shape omits
#          it and renders "bit buried"; and a FAILED RPC still renders
#          "bit N/A", because there we genuinely do not know — that
#          fallback is deliberately left alone. Also flagged the hourly
#          --endgame-only cron in the header examples as post-activation
#          vestigial (it silent-exits forever on a chain that has already
#          activated) — the mode itself stays for any future chain.
#   v1.7.1 — Software rows now sort ascending BY VERSION within each
#          compliance tier, instead of by operator count descending.
#          The card reads oldest-to-newest, so the upgrade story is
#          visible at a glance (laggards at the top of the block, newest
#          at the bottom) and rows stop reshuffling every time one
#          operator moves. The v1.6.1 three-tier grouping is unchanged
#          and deliberate — compliant block on top, pre-releases in the
#          middle, "No version reported" pinned last. Sorting globally
#          ascending would lift rc46/pre2 ABOVE the compliant baseline
#          (9.26.0 < 9.26.2), which is the exact problem v1.6.1 fixed,
#          so the reorder is strictly within tiers. The key is a numeric
#          array compare, not text: v9.26.9 sorts before v9.26.10, which
#          a lexical sort gets backwards the first time a double-digit
#          patch number ships. Requires regex-enabled jq (1.5+).
#          Related, config-side (no code change): ACCEPTED_VERSIONS now
#          includes v9.26.5 on both instances — a version NEWER than the
#          whitelist previously fell through as non-compliant and drew a
#          public upgrade @-ping, which was about to hit the author of
#          that very release. A version comparison instead of a fixed
#          whitelist is the durable fix, tracked for v1.8.0.
#   v1.7.0 — v9.26.5 BIP90 burial compatibility (PR #429, DigiSwarm).
#          Burying the DigiDollar deployment reshapes both deployment
#          RPCs: getdeploymentinfo loses .deployments.digidollar.bip9
#          entirely (replaced by {type:"buried", active, height}), and
#          getdigidollardeploymentinfo swaps its top-level .since for
#          .activation_height. Both existing height sources are gated on
#          the OLD field names, so on a v9.26.5 daemon both would fail
#          and the chain would fall through to computed_from_window —
#          the next-retarget-boundary wrong-height bug the v1.6.3
#          critical fix eliminated. Two fixes: (1) new Source 1a runs
#          ahead of Source 1 and reads the authoritative buried .height,
#          confirming status from .active; (2) Source 1b extended to try
#          .activation_height when .since is absent. Status itself is
#          unaffected — getdigidollardeploymentinfo.status persists
#          through the burial. Cosmetic: the buried shape has no
#          signaling bit, so the card renders "(bit buried)" instead of
#          "(bit )". No behavior change on v9.26.4: the new branches
#          simply never match. Upgrade the bot BEFORE the daemon.
#   v1.6.5 — Widened-window fallback for last-bundle display (July 2026).
#          Fixes rare "Last bundle: block none in window, signed by 0 oracles"
#          on the FULL card during a live, healthy signing network. Root cause:
#          getoraclesigners 50 is a fixed 50-block lookback, so at collection
#          time it can slice between bundles (typical bundle cadence ~40 blocks
#          per MuSig2 epoch) and return an empty window even when signing is
#          fine — a display artifact, not a signing failure. Fix: if the
#          50-block query returns bundle_count=0, retry once with 500-block
#          lookback before rendering "none in window." Diagnosed against live
#          mainnet post-activation (bundles were healthy at cadence ~1 per 12
#          blocks in 500 window). Silent-degrade preserved: still says "none
#          in window" only when it truly is quiet.
#   v1.6.4 — DD economy line on the FULL card (July 2026, post-activation).
#          New Phase 2d: getdigidollarstats (node-level RPC, no
#          digidollarstatsindex needed; UTXO-scan totals, fine at 12h).
#          Card gains one line: DD minted, DGB locked, collateralization.
#          Silent-degrade: any RPC/parse miss omits the line, never blocks
#          the post. FIELD MAP marked VERIFY AT DEPLOY; dry-run prints raw
#          JSON head + parsed values so the map can be finalized from one
#          paste. Per-tier lock breakdown NOT included: no network-wide
#          RPC exposes it (needs digidollarstatsindex or an indexer);
#          tracked in GitHub issue. Idea credit: Bastian in Gitter.
#   v1.6.3 — Three audit fixes (July 2026, pre-mainnet-activation).
#          (1) CRITICAL, birth announcement block number: in BIP9 ACTIVE
#          state getdeploymentinfo drops the statistics object entirely
#          and bip9.since IS the activation height (verified live on
#          testnet26: status=active, since=600, statistics=null). The
#          v1.6.2 resolution chain required since+period, failed in
#          ACTIVE, and fell through to computed_from_window, which
#          reports the NEXT retarget boundary (true activation + 40,320)
#          in the one-shot birth post. Now: ACTIVE uses since directly,
#          LOCKED_IN keeps since+period. New fallback (Source 1b) reads
#          top-level .since from getdigidollardeploymentinfo when the
#          standard RPC is unavailable while active.
#          (2) Upgrade-nudge ping cap: the fresh-oracle reset loop
#          cleared the shared mention counter every run BEFORE the nudge
#          section read it, so the MENTION_MAX cap never engaged (fresh
#          non-compliant operators would be pinged every 12 hours
#          forever, not 6 times). Upgrade nudges now track in a u<id>
#          namespace inside the same state file, cleared only when the
#          operator is fresh AND compliant (an upgrade earns a fresh
#          budget for any future regression). Stale/inactive ping
#          budgets are unchanged and unaffected.
#          (3) In-band duplicate suppression: inside the final 24h band
#          the 12hr standby cron posted a countdown 5 minutes after the
#          hourly endgame ticker (near-duplicates at 00:10/00:15 and
#          12:10/12:15). The standby pass now silent-exits when the
#          endgame_last_post marker is younger than
#          STANDBY_DEDUP_WINDOW_SECS (default 3540, 59 minutes). The
#          marker was previously written but never read; it is now
#          written only on successful posts, by both paths. If the
#          hourly ticker breaks (marker older than the window), the
#          12hr standby posts as backup.
#          Also: dry-run prints the resolved activation height and its
#          source on every mode, stale/inactive operator names render
#          "unknown" instead of "null" when unreported, and
#          getdeploymentinfo joins the header RPC list (missed in the
#          v1.6.2 header).
#   v1.6.2 — Mainnet pre-activation RPC ordering fix (July 2026).
#          Discovered during v1.6.1 mainnet dry-run: getoracles/
#          getoracleprice/getoraclesigners error out with "DigiDollar is
#          not yet active on this blockchain" (code -1) on pre-activation
#          mainnet daemons, BEFORE reaching the standby-mode branching.
#          On a real cron pass (not --dry-run) this would have posted
#          "Status check failed" alerts every 12 hours until activation,
#          alarming operators when the daemon is fine and DD just isn't
#          on yet.
#          FIX: RPC calls split into two phases.
#          Phase 1 (always-safe, runs every mode): getblockchaininfo,
#          getdeploymentinfo, getdigidollardeploymentinfo. These populate
#          BIP9 status, quorum config, MuSig2 session, activation height
#          math, and network identification.
#          Phase 2 (DD-required, only if FULL branch selected):
#          getoracles true, getoracleprice, getoraclesigners 50. These
#          populate operator heartbeats, consensus price, and recent
#          bundle signers. STANDBY / BIRTH / ENDGAME-silent modes skip
#          Phase 2 entirely.
#          Also: activation height math switched from
#          getdigidollardeploymentinfo.status_next.height (null pre-
#          activation) to getdeploymentinfo.deployments.digidollar.bip9.
#          since + statistics.period (populated pre-activation, BIP9
#          standard). Fallback chain: getdeploymentinfo -> config
#          override -> compute from current height / 40320 period -> floor
#          check against min_activation_height (mainnet 23,627,520,
#          testnet26 600).
#          New optional config: ACTIVATION_HEIGHT_OVERRIDE.
#          Verified on live mainnet 2026-07-12 (block ~23,842,xxx, BIP9
#          LOCKED_IN): computed activation = 23,869,440, matches digiscope.
#   v1.6.1 — Sort polish (July 2026). Software section groups by:
#          (1) Compliant versions first (✅ block, sorted count DESC),
#          (2) Non-compliant versions with a reported version (⚠️ block,
#          sorted count DESC), (3) "No version reported" at the very end.
#          Reads like a report: healthy baseline on top, version-based
#          deviations in the middle, data-quality bucket at the bottom.
#          The "No version reported" line inflates on unhealthy networks
#          (every inactive/unresponsive node lands there regardless of
#          what they're actually running), so keeping it separate from
#          real version distribution reads cleaner.
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

# v1.6.3: in-band dedup window. Inside the final 24h before activation the
# 12hr standby pass silent-exits if the hourly endgame ticker posted within
# this many seconds. Default 3540 (59 min): the ticker fires at :15 and the
# standby at :10, a 55-minute (3300s) gap, so 3540 comfortably covers cron
# jitter and script runtime while staying under 3600, which means a broken
# or stalled hourly ticker (marker older than one hour) lets the 12hr
# standby post as backup.
STANDBY_DEDUP_WINDOW_SECS=3540

# v1.6.2: manual override for activation height. Set only if all automatic
# resolution paths fail (getdeploymentinfo -> compute-from-window). Leave
# empty to allow automatic resolution. Format: integer block height.
# Example on mainnet during LOCKED_IN: ACTIVATION_HEIGHT_OVERRIDE=23869440
ACTIVATION_HEIGHT_OVERRIDE=""

# v1.6.2: min activation height (BIP9 floor). Reject computed activation
# values below this as a sanity check. Testnet26 was set to 600, mainnet
# is 23,627,520. Overridable per-network via config if needed.
MIN_ACTIVATION_HEIGHT_MAINNET=23627520
MIN_ACTIVATION_HEIGHT_TESTNET=600

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
# RPC DATA COLLECTION — v1.6.2 TWO-PHASE STRUCTURE
# ============================================================================
#
# Phase 1 (always-safe): RPCs that work on any daemon regardless of DD state.
#   - getblockchaininfo             chain + current height
#   - getdeploymentinfo             PRIMARY source for BIP9 math (Bitcoin Core
#                                   standard, populated pre-activation)
#   - getdigidollardeploymentinfo   DGB-specific extras: BIP9 status,
#                                   quorum config, MuSig2 session, oracle seed
#                                   peers. Returns partial data pre-activation
#                                   (since/status_next/statistics null but
#                                   status/bit/quorum config populated).
#
# Phase 2 (DD-required): RPCs that error with "DigiDollar is not yet active"
# on pre-activation daemons. Called ONLY when mode branching selects FULL.
#   - getoracles true               operator heartbeat list
#   - getoracleprice                consensus price
#   - getoraclesigners 50           recent bundle signers
#
# ============================================================================

echo "[$(date -u)] Collecting oracle network data (Phase 1: safe RPCs)..."

# --- Phase 1a. getblockchaininfo — network identification + current height ---
CHAIN_JSON=$($CLI getblockchaininfo 2>&1)
# v1.5: validate the JSON parse (jq -e) instead of substring-grepping.
if [ $? -eq 0 ] && echo "$CHAIN_JSON" | jq -e . >/dev/null 2>&1; then
    CHAIN_NAME=$(echo "$CHAIN_JSON" | jq -r '.chain // ""')
else
    CHAIN_NAME=""
    # Real daemon-down case: post an error alert and exit.
    echo "ERROR: getblockchaininfo failed. Daemon likely down."
    if [ "$DRY_RUN" != true ]; then
        if [ -n "$NETWORK_LABEL" ]; then
            NET_ERR="${NETWORK_LABEL}, "
        else
            NET_ERR=""
        fi
        post_to_gitter "⚠️ Oracle Network Monitor, ${NET_ERR}$(date -u +'%Y-%m-%d %H:%M UTC')

Status check failed: could not reach DigiByte daemon. Will retry next cycle."
    fi
    exit 1
fi

# Resolve network display label. Priority: NETWORK_LABEL from config >
# auto-detect from chain field.
if [ -n "$NETWORK_LABEL" ]; then
    NETWORK_DISPLAY="$NETWORK_LABEL"
elif [ "$CHAIN_NAME" = "test" ]; then
    NETWORK_DISPLAY="Testnet"
elif [ "$CHAIN_NAME" = "main" ]; then
    NETWORK_DISPLAY="Mainnet"
elif [ "$CHAIN_NAME" = "regtest" ]; then
    NETWORK_DISPLAY="Regtest"
elif [ -n "$CHAIN_NAME" ]; then
    NETWORK_DISPLAY=$(echo "$CHAIN_NAME" | sed 's/./\U&/')
else
    NETWORK_DISPLAY=""
fi

# --- Phase 1b. getdeploymentinfo — PRIMARY BIP9 source (v1.6.2 NEW) ---
# This is the Bitcoin Core standard deployment info RPC. Fully populated
# pre-activation, unlike the DGB-custom getdigidollardeploymentinfo whose
# .since/.status_next/.statistics fields are null pre-activation. Preferred
# source for activation-height math.
DEPLOY_STD_JSON=$($CLI getdeploymentinfo 2>&1)
DEPLOY_STD_OK=$?

# --- Phase 1c. getdigidollardeploymentinfo — DGB extras ---
# Returns partial data pre-activation. Still useful for oracle_consensus_required,
# oracle_total_slots, musig2_session fields.
DEPLOY_JSON=$($CLI getdigidollardeploymentinfo 2>&1)
DEPLOY_OK=$?

# ============================================================================
# PARSE RPC DATA — v1.6.2 PHASE 1 ONLY
# ============================================================================
# Phase 2 parse (oracle heartbeats, price, bundles) happens after mode
# branching, in the FULL flow only. Standby/birth/endgame modes don't need
# that data and don't fetch it.
# ============================================================================

# --- Current block height (from getblockchaininfo, already validated) ---
CURRENT_HEIGHT=$(echo "$CHAIN_JSON" | jq -r '.blocks // 0' 2>/dev/null)
[ -z "$CURRENT_HEIGHT" ] && CURRENT_HEIGHT=0

# --- Deployment info (getdigidollardeploymentinfo, tolerates partial data) ---
if [ $DEPLOY_OK -eq 0 ] && echo "$DEPLOY_JSON" | jq -e . >/dev/null 2>&1; then
    BIP9_STATUS=$(echo "$DEPLOY_JSON" | jq -r '.status // "unknown"')
    # v1.7.2: default to EMPTY, not "N/A". Under the v9.26.5 burial this
    # RPC omits .bit entirely; an empty value lets the display default
    # ${BIP9_BIT:-buried} fire and render "bit buried". The literal "N/A"
    # is reserved for the RPC-unavailable branch below, where the bit is
    # genuinely unknown rather than known-absent.
    BIP9_BIT=$(echo "$DEPLOY_JSON" | jq -r '.bit // empty')
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

# --- v1.6.2: Activation height resolution (multi-source with fallbacks) ---
# Priority chain:
#   1. getdeploymentinfo.deployments.digidollar.bip9 (since + statistics.period)
#      Bitcoin Core standard, populated pre-activation. Preferred source.
#   2. ACTIVATION_HEIGHT_OVERRIDE from config (manual override).
#   3. Computed from current height + assumed 40320 period.
#   4. Sanity check: if result < min_activation_height floor, use floor as
#      "at least this" indicator and mark unreliable.
ACTIVATION_HEIGHT=""
ACTIVATION_HEIGHT_SOURCE="unresolved"

# Source 1a (v1.7.0): v9.26.5 BIP90 burial. PR #429 replaces
# .deployments.digidollar.bip9 with {"type":"buried","active":…,
# "height":…}. Without this branch the .bip9 gate below fails on a
# v9.26.5 daemon, Source 1 is skipped, and the chain falls through to
# computed_from_window — the next-retarget-boundary wrong-height bug the
# v1.6.3 critical fix eliminated, resurrected by the burial. The buried
# .height is authoritative: use it, confirm status from .active, and let
# the old Source 1 no-op naturally. On v9.26.4 .type is absent and this
# branch does nothing at all.
if [ $DEPLOY_STD_OK -eq 0 ] \
   && [ "$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.type // empty' 2>/dev/null)" = "buried" ]; then
    BURIED_HEIGHT=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.height // empty' 2>/dev/null)
    if [ -n "$BURIED_HEIGHT" ] && [ "$BURIED_HEIGHT" != "null" ] && [[ "$BURIED_HEIGHT" =~ ^[0-9]+$ ]]; then
        ACTIVATION_HEIGHT="$BURIED_HEIGHT"
        ACTIVATION_HEIGHT_SOURCE="getdeploymentinfo_buried"
    fi
    if [ "$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.active // false' 2>/dev/null)" = "true" ]; then
        BIP9_STATUS="active"
    fi
fi

# Source 1: getdeploymentinfo (BIP9 standard)
if [ $DEPLOY_STD_OK -eq 0 ] && echo "$DEPLOY_STD_JSON" | jq -e '.deployments.digidollar.bip9' >/dev/null 2>&1; then
    BIP9_SINCE=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.bip9.since // empty')
    BIP9_PERIOD=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.bip9.statistics.period // empty')

    # If BIP9 status here is more authoritative than DGB extras, prefer it.
    # (v1.6.3: extracted BEFORE the height math, which now branches on it.)
    STD_BIP9_STATUS=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.bip9.status // empty')
    if [ -n "$STD_BIP9_STATUS" ] && [ "$STD_BIP9_STATUS" != "null" ]; then
        BIP9_STATUS="$STD_BIP9_STATUS"
    fi
    STD_BIP9_BIT=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.bip9.bit // empty')
    if [ -n "$STD_BIP9_BIT" ] && [ "$STD_BIP9_BIT" != "null" ]; then
        BIP9_BIT="$STD_BIP9_BIT"
    fi

    # Extract min_activation_height for floor sanity check (Bitcoin Core standard).
    BIP9_MIN_ACTIVATION=$(echo "$DEPLOY_STD_JSON" | jq -r '.deployments.digidollar.bip9.min_activation_height // empty')

    # v1.6.3 CRITICAL FIX: the height math must branch on deployment state.
    # In ACTIVE state, Core drops the statistics object entirely and
    # bip9.since IS the activation height (verified live on testnet26:
    # status=active, since=600, statistics=null). The old since+period
    # requirement failed in ACTIVE and fell through to computed_from_window,
    # which reports the NEXT retarget boundary (activation + 40,320). That
    # wrong number would have headlined the one-shot birth announcement.
    if [ "$STD_BIP9_STATUS" = "active" ] \
       && [ -n "$BIP9_SINCE" ] && [ "$BIP9_SINCE" != "null" ]; then
        # ACTIVE: since is the height at which ACTIVE began = activation height.
        ACTIVATION_HEIGHT="$BIP9_SINCE"
        ACTIVATION_HEIGHT_SOURCE="getdeploymentinfo_since_active"
    elif [ -n "$BIP9_SINCE" ] && [ -n "$BIP9_PERIOD" ] \
       && [ "$BIP9_SINCE" != "null" ] && [ "$BIP9_PERIOD" != "null" ]; then
        # LOCKED_IN: activation = current window end + 1 = since + period.
        ACTIVATION_HEIGHT=$((BIP9_SINCE + BIP9_PERIOD))
        ACTIVATION_HEIGHT_SOURCE="getdeploymentinfo"
    fi
fi

# Source 1b (v1.6.3): DD reports active but the standard RPC gave us no
# height (RPC failed or fields missing). getdigidollardeploymentinfo carries
# a top-level .since that mirrors BIP9 and populates post-activation. Belt
# for the birth announcement: never announce a window-math guess while active.
if [ -z "$ACTIVATION_HEIGHT" ] && [ "$BIP9_STATUS" = "active" ]; then
    DGB_SINCE=$(echo "$DEPLOY_JSON" | jq -r '.since // empty' 2>/dev/null)
    # v1.7.0: under the v9.26.5 burial getdigidollardeploymentinfo drops
    # .since and carries .activation_height instead. Same meaning, new
    # name — try it before giving up, so this belt still works when
    # Source 1a is somehow unavailable.
    if [ -z "$DGB_SINCE" ] || [ "$DGB_SINCE" = "null" ]; then
        DGB_SINCE=$(echo "$DEPLOY_JSON" | jq -r '.activation_height // empty' 2>/dev/null)
    fi
    if [ -n "$DGB_SINCE" ] && [ "$DGB_SINCE" != "null" ] && [[ "$DGB_SINCE" =~ ^[0-9]+$ ]]; then
        ACTIVATION_HEIGHT="$DGB_SINCE"
        ACTIVATION_HEIGHT_SOURCE="digidollardeploymentinfo_since_active"
    fi
fi

# Source 2: config override
if [ -z "$ACTIVATION_HEIGHT" ] && [ -n "$ACTIVATION_HEIGHT_OVERRIDE" ]; then
    ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT_OVERRIDE"
    ACTIVATION_HEIGHT_SOURCE="config_override"
fi

# Source 3: compute from current height + assumed period.
# window_start = (current / period) * period; activation = window_start + period.
# Assumes we're already inside the LOCKED_IN window (best-guess for pre-launch).
if [ -z "$ACTIVATION_HEIGHT" ] && [ "$CURRENT_HEIGHT" -gt 0 ]; then
    ASSUMED_PERIOD=40320
    WINDOW_START=$(( (CURRENT_HEIGHT / ASSUMED_PERIOD) * ASSUMED_PERIOD ))
    ACTIVATION_HEIGHT=$((WINDOW_START + ASSUMED_PERIOD))
    ACTIVATION_HEIGHT_SOURCE="computed_from_window"
fi

# Floor sanity check: if computed value is below the network's known
# min_activation_height, replace with floor and mark unreliable. This
# catches misconfiguration (period wrong, since wrong) rather than
# reporting nonsense.
if [ -n "$ACTIVATION_HEIGHT" ] && [ "$ACTIVATION_HEIGHT" -gt 0 ]; then
    # Prefer min_activation_height from getdeploymentinfo if available;
    # else use hardcoded per-chain floor.
    FLOOR=""
    if [ -n "$BIP9_MIN_ACTIVATION" ] && [ "$BIP9_MIN_ACTIVATION" != "null" ]; then
        FLOOR="$BIP9_MIN_ACTIVATION"
    elif [ "$CHAIN_NAME" = "main" ]; then
        FLOOR="$MIN_ACTIVATION_HEIGHT_MAINNET"
    elif [ "$CHAIN_NAME" = "test" ]; then
        FLOOR="$MIN_ACTIVATION_HEIGHT_TESTNET"
    fi
    if [ -n "$FLOOR" ] && [ "$ACTIVATION_HEIGHT" -lt "$FLOOR" ]; then
        echo "[$(date -u)] WARNING: computed activation ($ACTIVATION_HEIGHT) below floor ($FLOOR). Using floor as safe fallback."
        ACTIVATION_HEIGHT="$FLOOR"
        ACTIVATION_HEIGHT_SOURCE="${ACTIVATION_HEIGHT_SOURCE}_floor_capped"
    fi
fi

# --- Blocks + time remaining + calendar ETA ---
BLOCKS_REMAINING=0
SECS_REMAINING=0
MINUTES=0
HOURS=0
DAYS=0
ETA_UTC=""

if [ -n "$ACTIVATION_HEIGHT" ] && [ "$ACTIVATION_HEIGHT" -gt 0 ] && [ "$CURRENT_HEIGHT" -gt 0 ]; then
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

# v1.6.3: surface the resolution result in dry-run on EVERY mode. This is
# the debug line that would have caught the ACTIVE-state math bug in the
# Session 31 testnet dry-run (FULL mode never displays activation height).
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Activation height: ${ACTIVATION_HEIGHT:-unresolved} (source: ${ACTIVATION_HEIGHT_SOURCE}), blocks remaining: ${BLOCKS_REMAINING}"
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
    else
        # v1.6.3: in-band duplicate suppression for the 12hr standby pass.
        # Inside the final 24h the hourly endgame ticker (:15) already posts
        # a countdown; the 12hr standby (:10) landing 55 minutes later was a
        # near-duplicate. Skip when the marker is younger than the window.
        # A marker older than the window (ticker broken/stalled) lets the
        # 12hr standby post as backup. Applies in dry-run too so dry-run
        # output matches what a real pass would do.
        if [ "$SECS_REMAINING" -gt 0 ] && [ "$SECS_REMAINING" -lt 86400 ] && [ -f "$ENDGAME_LAST_POST_FILE" ]; then
            LAST_POST_TS=$(cat "$ENDGAME_LAST_POST_FILE" 2>/dev/null)
            if [[ "$LAST_POST_TS" =~ ^[0-9]+$ ]]; then
                MARKER_AGE=$(( $(date +%s) - LAST_POST_TS ))
                if [ "$MARKER_AGE" -ge 0 ] && [ "$MARKER_AGE" -lt "$STANDBY_DEDUP_WINDOW_SECS" ]; then
                    echo "[$(date -u)] Standby suppressed: endgame ticker posted ${MARKER_AGE}s ago (< ${STANDBY_DEDUP_WINDOW_SECS}s window, marker: $ENDGAME_LAST_POST_FILE). Silent exit."
                    exit 0
                fi
            fi
        fi
    fi

    STANDBY_MESSAGE=$(build_standby_message)
    # v1.6.3: dedup marker written only when the post actually landed
    # (was unconditional). Written by both the 12hr standby and the hourly
    # endgame ticker, since both flow through this shared post path.
    if post_to_gitter "$STANDBY_MESSAGE" "" ""; then
        if [ "$DRY_RUN" != true ]; then
            date +%s > "$ENDGAME_LAST_POST_FILE" 2>/dev/null || true
        fi
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
# v1.6.2: PHASE 2 RPC COLLECTION (DD-required, FULL mode only)
# ============================================================================
# These RPCs error with "DigiDollar is not yet active" on pre-activation
# mainnet daemons. Only reached when the mode-branching above selected
# FULL flow, which requires DD_IS_ACTIVE=true. Safe to call here.
# ============================================================================

echo "[$(date -u)] Collecting oracle network data (Phase 2: DD-required RPCs)..."

# --- Phase 2a. getoracles true — per-oracle heartbeat status ---
ORACLES_JSON=$($CLI getoracles true 2>&1)
if [ $? -ne 0 ] || ! echo "$ORACLES_JSON" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: getoracles true failed unexpectedly: $ORACLES_JSON"
    if [ "$DRY_RUN" != true ]; then
        if [ -n "$NETWORK_DISPLAY" ]; then
            NET_ERR="${NETWORK_DISPLAY}, "
        else
            NET_ERR=""
        fi
        post_to_gitter "⚠️ Oracle Network Monitor, ${NET_ERR}$(date -u +'%Y-%m-%d %H:%M UTC')

Status check failed: could not reach DigiByte oracle data. Will retry next cycle."
    fi
    exit 1
fi

# --- Phase 2b. getoracleprice — consensus price + status ---
PRICE_JSON=$($CLI getoracleprice 2>&1)
PRICE_OK=$?

# --- Phase 2c. getoraclesigners 50 — recent bundle signers ---
SIGNERS_JSON=$($CLI getoraclesigners 50 2>&1)
SIGNERS_OK=$?

# v1.6.5: widened-window fallback. If the 50-block window happens to slice
# between bundles (bundles land ~every 40 blocks per MuSig2 epoch, so this
# is a real edge case, not paranoia), retry once with a 500-block lookback
# before rendering "none in window." Preserves silent-degrade: if 500 is
# also empty, the network really is quiet and the honest line stands.
SIGNERS_WIDENED=false
if [ $SIGNERS_OK -eq 0 ] && echo "$SIGNERS_JSON" | jq -e . >/dev/null 2>&1; then
    _bcount_50=$(echo "$SIGNERS_JSON" | jq -r '.bundle_count // 0')
    if [ "$_bcount_50" = "0" ]; then
        SIGNERS_JSON_WIDE=$($CLI getoraclesigners 500 2>&1)
        SIGNERS_OK_WIDE=$?
        if [ $SIGNERS_OK_WIDE -eq 0 ] && echo "$SIGNERS_JSON_WIDE" | jq -e . >/dev/null 2>&1; then
            _bcount_500=$(echo "$SIGNERS_JSON_WIDE" | jq -r '.bundle_count // 0')
            if [ "$_bcount_500" != "0" ]; then
                SIGNERS_JSON="$SIGNERS_JSON_WIDE"
                SIGNERS_WIDENED=true
            fi
        fi
    fi
fi
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] signers window: widened=${SIGNERS_WIDENED} (v1.6.5 fallback: retry with 500-block lookback if 50-block returned bundle_count=0)"
fi

# --- Phase 2d. getdigidollarstats — DD economy totals (v1.6.4) ---
# Node-level RPC (since v9.26.2), no digidollarstatsindex required: the
# index only serves historical per-height queries; current totals come
# from a UTXO-set scan inside the RPC. Fine at 12h cadence.
# Silent-degrade by design: if the RPC is missing, errors, or the field
# map below doesn't match, DD_ECON_OK stays false and the economy line
# is simply omitted from the card. Never blocks the post.
DDSTATS_JSON=$($CLI getdigidollarstats 2>&1)
DDSTATS_OK=$?

# ============================================================================
# PARSE PHASE 2 DATA
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

# --- Last bundle signers ---
if [ $SIGNERS_OK -eq 0 ] && echo "$SIGNERS_JSON" | jq -e . >/dev/null 2>&1; then
    BUNDLE_COUNT=$(echo "$SIGNERS_JSON" | jq -r '.bundle_count // 0')
    if [ "$BUNDLE_COUNT" -gt 0 ]; then
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

# --- DD economy totals (v1.6.4) ---
# FIELD MAP, VERIFY AT DEPLOY: run `getdigidollarstats` on the live
# daemon once and confirm these three jq paths against real output,
# then delete the candidates that don't apply. The alternatives below
# cover the likely namings from src/index/digidollarstatsindex
# (total_dd_supply, total_collateral) and cents-vs-usd variants seen
# in test output. Any miss leaves DD_ECON_OK=false and the line is
# omitted, so an unverified deploy degrades to the current card.
DD_ECON_OK=false
DD_SUPPLY_DISPLAY=""
DD_LOCKED_DISPLAY=""
DD_COLLAT_DISPLAY=""
if [ $DDSTATS_OK -eq 0 ] && echo "$DDSTATS_JSON" | jq -e . >/dev/null 2>&1; then
    # Supply: prefer explicit USD field; else cents/100; else raw.
    DD_SUPPLY_USD=$(echo "$DDSTATS_JSON" | jq -r '(.total_dd_supply_usd // .dd_supply_usd // empty)')
    if [ -z "$DD_SUPPLY_USD" ]; then
        DD_SUPPLY_CENTS=$(echo "$DDSTATS_JSON" | jq -r '(.total_dd_supply_cents // .dd_supply_cents // .total_dd_supply // empty)')
        if [ -n "$DD_SUPPLY_CENTS" ]; then
            DD_SUPPLY_USD=$(awk -v c="$DD_SUPPLY_CENTS" 'BEGIN{printf "%.2f", c/100}')
        fi
    fi
    # Collateral: whole DGB preferred; satoshi variant divided down.
    DD_LOCKED_DGB=$(echo "$DDSTATS_JSON" | jq -r '(.total_collateral_dgb // .total_collateral // empty)')
    if [ -z "$DD_LOCKED_DGB" ]; then
        DD_LOCKED_SATS=$(echo "$DDSTATS_JSON" | jq -r '(.total_collateral_sats // .total_collateral_satoshis // empty)')
        if [ -n "$DD_LOCKED_SATS" ]; then
            DD_LOCKED_DGB=$(awk -v s="$DD_LOCKED_SATS" 'BEGIN{printf "%.2f", s/100000000}')
        fi
    fi
    # Health / collateralization percent.
    DD_COLLAT_PCT=$(echo "$DDSTATS_JSON" | jq -r '(.health_percentage // .system_health_percent // .health_percent // .collateral_ratio_percent // .system_collateral_ratio // .system_health // empty)')

    if [ -n "$DD_SUPPLY_USD" ] && [ -n "$DD_LOCKED_DGB" ]; then
        DD_ECON_OK=true
        # Portable thousands-separator formatter: integer part gets commas
        # via sed, decimal part preserved as-is. Works regardless of locale
        # (awk %'d needs LC_NUMERIC set, printf ' varies by shell — sed is
        # deterministic).
        _fmt_thousands() {
            # $1 = numeric string like "3800.32" or "5169495.17769483"
            local n="$1" int frac
            int="${n%%.*}"
            if [ "$n" = "$int" ]; then frac=""; else frac=".${n#*.}"; fi
            # Reverse, insert comma every 3 digits, reverse back
            int=$(echo "$int" | rev | sed 's/\([0-9]\{3\}\)/\1,/g' | rev | sed 's/^,//')
            echo "${int}${frac}"
        }
        DD_SUPPLY_DISPLAY=$(_fmt_thousands "$(printf '%.2f' "$DD_SUPPLY_USD" 2>/dev/null || echo "$DD_SUPPLY_USD")")
        DD_LOCKED_DISPLAY=$(_fmt_thousands "$(printf '%.0f' "$DD_LOCKED_DGB" 2>/dev/null || echo "$DD_LOCKED_DGB")")
        if [ -n "$DD_COLLAT_PCT" ]; then
            DD_COLLAT_DISPLAY=" (${DD_COLLAT_PCT}% collateralized)"
        fi
    fi
fi
# Dry-run discovery aid: surface the raw JSON head so the field map can
# be finalized from a single dry-run paste. Never printed on live runs.
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] getdigidollarstats raw (first 400 chars): $(printf '%s' "$DDSTATS_JSON" | head -c 400)"
    echo "[DRY RUN] DD economy parsed: ok=${DD_ECON_OK} supply_usd=${DD_SUPPLY_USD:-none} locked_dgb=${DD_LOCKED_DGB:-none} collat_pct=${DD_COLLAT_PCT:-none}"
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
# v1.6.3: this loop resets the plain <id> entries (stale/inactive budgets)
# ONLY. Upgrade-nudge budgets live in the u<id> namespace below and are
# untouched here: "^9|" does not match "u9|". The v1.6.2 bug was that the
# upgrade nudge shared the plain <id> counter, which this loop wiped every
# run (upgrade targets are fresh by definition), so its MENTION_MAX cap
# never engaged and fresh non-compliant operators were pinged every cycle.
if [ -f "$MENTION_STATE_FILE" ] && [ "$DRY_RUN" != true ]; then
    while read -r fresh_id; do
        reset_mention_count "$fresh_id"
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "fresh") | .oracle_id')
fi

# v1.6.3: clear u<id> upgrade-nudge counters only for operators who are
# fresh AND running a compliant version. Upgrading earns a fresh budget
# for any future regression. Fresh non-compliant operators keep counting
# toward MENTION_MAX; non-fresh operators keep their u-counter as-is
# (they're handled by the stale/inactive flow until they return).
if [ -f "$MENTION_STATE_FILE" ] && [ "$DRY_RUN" != true ]; then
    while read -r ok_id; do
        reset_mention_count "u${ok_id}"
    done < <(echo "$ORACLES_JSON" | jq -r --arg accepted "$ACCEPTED_VERSIONS" '
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
      .[] |
      select(.heartbeat_status == "fresh") |
      select(.software_version | is_compliant($accepted)) |
      .oracle_id')
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
BIP9: ${BIP9_STATUS} (bit ${BIP9_BIT:-buried})
Last bundle: block ${LAST_BUNDLE_HEIGHT}, signed by ${LAST_BUNDLE_SIGNERS} oracles"

# v1.6.4: DD economy line — only when getdigidollarstats parsed cleanly.
# One line, health-summary density; digibyte.io/ddstats has the full view.
if [ "$DD_ECON_OK" = true ]; then
    MESSAGE="${MESSAGE}
DD economy: \$${DD_SUPPLY_DISPLAY} DD minted, ${DD_LOCKED_DISPLAY} DGB locked${DD_COLLAT_DISPLAY}"
fi

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
  # v1.6.1 three-tier sort priority, v1.7.1 within-tier ordering:
  #   0 = compliant (✅ block), sorted ASCENDING BY VERSION within
  #   1 = non-compliant WITH a reported version (⚠️ block), same
  #   2 = "No version reported" (data-quality bucket), pinned to the end
  # v1.7.1: within-tier order was count DESC (popularity), which said
  # nothing about upgrade direction and reshuffled whenever one operator
  # moved. Ascending by version reads oldest-to-newest, so laggards sit
  # at the top of each block. The key is a NUMERIC array compare
  # ([scan("[0-9]+") | tonumber]) — a text compare would sort v9.26.10
  # before v9.26.9. "No version reported" yields [] and is alone in its
  # tier, so its empty key is harmless. Needs regex-enabled jq (1.5+).
  # Reads like a report: healthy baseline on top, deviations in the
  # middle, unreported at the bottom. The unreported bucket inflates
  # on unhealthy networks (any inactive node lands there) so pinning
  # it at the end keeps real version distribution visually clean.
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
  sort_by(
    (if .compliant then 0
     elif .label == "No version reported" then 2
     else 1
     end),
    (.label | [scan("[0-9]+") | tonumber])
  ) |
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
            # v1.6.3: counts tracked as u<id> so the fresh-oracle reset loop
            # (which clears plain <id> stale budgets) can't wipe them. Same
            # state file, same MENTION_MAX cap, separate namespace.
            handle=$(get_gitter_handle "$oid")
            if [ -n "$handle" ]; then
                count=$(get_mention_count "u${oid}")
                if [ "$count" -lt "$MENTION_MAX" ]; then
                    if ! is_already_mentioned "$handle"; then
                        line="${line} ${handle}"
                        record_mention "$handle" "$oname"
                    fi
                    if [ "$DRY_RUN" != true ]; then
                        increment_mention_count "u${oid}" "$count"
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
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status == "stale") | "\(.oracle_id)|\(.name // "unknown")"')

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
    done < <(echo "$ORACLES_JSON" | jq -r '.[] | select(.heartbeat_status != "fresh" and .heartbeat_status != "stale") | "\(.oracle_id)|\(.name // "unknown")"')

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
    echo "BIP9: $BIP9_STATUS (bit ${BIP9_BIT:-buried})"
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
