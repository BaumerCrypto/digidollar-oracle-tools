#!/bin/bash
###############################################################################
# oracle-monitor-macos.sh — DGB Oracle Health Monitor with Discord + Email Alerts (macOS)
# Version: 2.7.1-macos.1
#
# macOS port of my oracle-monitor.sh v2.7.1 (Linux). Same checks, same quorum
# state machine, same anti-flap logic, same DigiDollar BIP9 pre-activation
# guard, same auto-detect for headless vs Qt wallet, same email-plus-Discord
# dual-channel alerts, same daily update check — BSD/macOS-native commands.
# Written for the stock /bin/bash 3.2 that ships with every Mac (no Homebrew
# bash needed). The only dependency is jq.
#
# Author: digibyte-maxi (Oracle ID 17) | @BaumerCrypto2.0 | https://x.com/BaumerCrypto2_0 — July 2026
readonly SCRIPT_VERSION="2.8.0-macos.1"
#
# SETUP:
#   1. Copy this script to your Mac: ~/oracle-monitor-macos.sh
#   2. chmod +x ~/oracle-monitor-macos.sh
#   3. Install jq (one time): brew install jq
#   4. Create config: mkdir -p ~/.oracle-monitor && cp config-macos.template ~/.oracle-monitor/config
#   5. Edit config: Set your Discord webhook URL, oracle settings, and
#      (optionally) email settings — see the EMAIL section in the template
#   6. Test it: ./oracle-monitor-macos.sh --dry-run
#   7. Test webhook: ./oracle-monitor-macos.sh --test
#   8. Test email (if enabled): ./oracle-monitor-macos.sh --test-email
#   9. Add to cron: crontab -e
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
#   --summary  Full status summary — always sends to Discord + email
#   --dry-run  Runs all checks, prints to terminal, skips Discord + email, no state changes
#   --watch    Live console dashboard — refreshes the full status every 60s
#              (or --watch 30 for 30s). Never alerts, never touches state:
#              safe to leave open in a Terminal window alongside cron.
#   --test     Sends a test embed to Discord to verify webhook
#   --test-email    Sends a test email to verify SMTP settings
#   --config /path  Use alternate config file (enables dual-instance monitoring)
#
# CRON SCHEDULE:
#   */5 = every 5 minutes for health checks (alerts only on problems)
#   0 */12 = every 12 hours for a full status summary (always sends)
#
# CHANGELOG:
#   v2.8.0-macos.1 — Parity with Linux v2.8.0. Peer line shows inbound/
#          outbound split + connection cap ("Peers: 41 connected (34 in /
#          7 out, cap 125)") from getnetworkinfo + the daemon conf, with
#          graceful fallback to the bare getconnectioncount total. Fixed
#          "1 Warnings"/"1 Issues Detected" singularization. Default
#          DIGIBYTE_UPDATE_TTL 86400 -> 21600 (a 24h TTL races a daily
#          summary). Reworded the getoracleprice log-volume note to the
#          mechanism (one line per block of the 24h window, ~5,760 blocks).
#   v2.7.1 — The debug.log alert now links straight to the guide. The v2.7.0
#            card ended with a bare filename ("ORACLE_HARDENING_GUIDE.md →
#            ...") that Discord and email clients won't linkify, so an
#            operator reading the alert on their phone had to go find the
#            repo by hand. It now carries the full anchor URL, landing them
#            on the exact section. Same fix on all three platforms; no
#            logic change, no new config.
#   v2.7.0-macos.1 — The disk-safety release. Matches Linux v2.7.0.
#            Root cause, measured live on my slot-17 Linux VPS in July
#            2026 and just as true on a Mac: enabling any -debug category
#            (the old oracle docs said debug=digidollar) silently disables
#            the daemon's automatic startup log-shrink, oracle boxes never
#            restart, and getoracleprice writes one category-gated line
#            per block of the 24h price window (~5,760 blocks, 4,780-5,800
#            by miss rate) — so 5-minute monitoring multiplies
#            growth (~374 MB/day measured with digidollar+net vs ~8 MB/day
#            default). Four features + one compatibility fix:
#            (1) DEBUG.LOG WATCHDOG (Check 13): size + growth/day + names
#            enabled categories via the `logging` RPC. DEBUG_LOG_WARN_MB
#            (1024).
#            (2) SAFE AUTO-ROTATION — DEFAULT ON (behavior change!). At
#            DEBUG_LOG_MAX_MB (2048): copy to debug.log.1, then truncate
#            the live file IN PLACE with `: >` — stock macOS ships no
#            truncate(1), and `: >` is the identical primitive for a file
#            the daemon holds open. Copy-first (never truncate if the copy
#            failed), ~2x threshold of newest history always on disk,
#            blue card on every rotation, red card + skip when free space
#            can't hold the safety copy, dry-run touches nothing.
#            DEBUG_LOG_ROTATE="no" opts out. DEBUG_LOG_KEEP (1).
#            (3) DISK USAGE WARNING BAND (closes #33): yellow at
#            DISK_USED_PCT_WARN (80%) while MIN_DISK_GB stays the red
#            floor.
#            (4) PRICE_CHECK_EVERY (1): run the getoracleprice check every
#            Nth pass — cut the loudest log source to 1/N on a small box.
#            (5) v9.26.5-READY (PR #429 by DigiSwarm): BIP90 burial
#            reshapes getdigidollardeploymentinfo; buried shape keeps
#            status, and an explicit {type:"buried", active:true}
#            fallback lands here too — upgrade daemon and monitor in
#            either order.
#   v2.6.3-macos.1 — Two operator-suggested additions. Matches Linux v2.6.3.
#            (1) DIGIBYTE VERSION NOW UPDATE-AWARE (caught by Baumer). The
#            node-version line compares the running version against the
#            latest DigiByte Core release on GitHub (releases/latest, cached
#            daily) and colours the icon: ✅ green when on the latest release
#            or newer, ℹ️ blue "— vX.Y.Z available" when a newer release is
#            out. Falls back to the plain ℹ️ line when GitHub is unreachable
#            or disabled; never fetches or writes its cache in --dry-run.
#            New config: DIGIBYTE_UPDATE_CHECK ("yes"), DIGIBYTE_UPDATE_TTL
#            (86400).
#            (2) LAUNCHD_LABEL="none" ESCAPE HATCH (caught by Aussie Epic on
#            Linux). Operators who deliberately run headless WITHOUT launchd
#            can set LAUNCHD_LABEL="none" (also "skip"/"disabled") to
#            replace the launchd check with an ℹ️ "check disabled" line.
#            (macOS already fell back to a green process line on an empty
#            label; this adds the explicit opt-out for parity with Linux's
#            SERVICE_NAME="none".)
#   v2.6.2-macos.1 — Three operator-suggested fixes (two cosmetic, one
#            alert-logic). Matches Linux v2.6.2.
#            (1) VERSION LINE CLEANUP. check_version now strips the
#            bitcoin-legacy /Name:Version/ user-agent wrapper that
#            getnetworkinfo → .subversion returns. Line goes from
#            "ℹ️  /DigiByte:9.26.4/" to "ℹ️  DigiByte: v9.26.4" — the
#            slashes are meaningful to network peers but noise to
#            operators reading a health summary. Handles rc builds and
#            hash suffixes correctly (/DigiByte:9.26.0rc46/ →
#            DigiByte: v9.26.0rc46).
#            (2) EMAIL TIME LINE IN UTC. Time: line in email body now
#            uses UTC ('date -u') instead of macOS-local timezone ('date').
#            Matches Discord timestamp convention (UTC internally, client
#            renders local). Operators no longer need to mentally convert
#            timezones. No config change; automatic.
#            (3) SWAP ALERT NOW PRESSURE-GATED (caught by Aussie Epic on
#            Linux). A filled swap is no longer treated as memory pressure
#            on its own — after a heavy transient the OS can leave GBs
#            parked in swap long after the pressure ended. check_swap now
#            only raises the yellow alert when RAM usage >= SWAP_MEM_HEADROOM_PCT
#            (macOS has no PSI, so RAM headroom is the sole signal). A
#            stale fill shows as an ℹ️ line and no longer inflates the
#            warning count. If RAM% can't be measured it fails safe and
#            alerts as v2.4 did. New config: SWAP_MEM_HEADROOM_PCT
#            (default 70). Real pressure still alerts exactly as before.
#   v2.6.1-macos.1 — Cosmetic fix matching Linux v2.6.1 (caught by Aussie
#            Epic). ⚠️ (U+26A0 + VS16) and ℹ️ (U+2139 + VS16) render as
#            single-width text glyphs in most terminals — the VS16
#            selector requests emoji presentation but is honored
#            inconsistently — while ✅ 🔴 💀 render as double-width
#            emoji. Net effect in the health summary: every ⚠️/ℹ️
#            line's label sat one column left of the ✅/🔴 line labels,
#            giving the summary a subtle-but-persistent "some lines
#            look squished" appearance. Every ⚠️ and ℹ️ prefix now
#            carries a second space so all status lines line up at the
#            same column regardless of the terminal's emoji-width
#            handling. Applies to DETAILS summary lines, alert titles,
#            and the top status header ("⚠️  N Warnings"). No logic
#            change; no alert path change — purely how the output
#            renders. In Discord and email the double-space is visually
#            harmless (both render these as full-width emoji so the
#            extra space reads as intentional padding). Also: the
#            update-available footer URL now includes the https://
#            scheme so email clients (including Outlook desktop and
#            corporate gateways that only linkify explicit-scheme URLs)
#            auto-linkify it universally. One-character change in
#            build_footer.
#   v2.6.0-macos.1 — Two features, one release. Matches Linux v2.6.0 line by line.
#            (1) EMAIL NOTIFICATIONS (closes #17). New send_email() fires
#            on the same triggers as Discord — red/yellow/green state
#            changes plus the 12-hour summary — via curl's built-in SMTP
#            support (no mailx/postfix/sendmail needed; curl ships with
#            SMTP on every modern macOS). Config-driven: EMAIL_ENABLED,
#            EMAIL_TO, SMTP_SERVER, SMTP_PORT, SMTP_USER, SMTP_PASS,
#            SMTP_FROM. Port 587 = STARTTLS (Gmail/Outlook/Brevo default),
#            465 = implicit TLS. Gmail requires an App Password (2FA →
#            App passwords), never the account password. Subjects carry
#            severity ([ALERT]/[WARNING]/[RESOLVED]/[INFO]) and the
#            NETWORK_LABEL prefix (dual-instance parity with v2.5.3-
#            macos.1 Discord titles, applied at the send_email
#            chokepoint). New --test-email flag verifies SMTP settings
#            with inline diagnostics for the common failure modes.
#            Backup channel if Discord is down; primary channel for
#            operators who don't use Discord/Slack/Telegram.
#            (2) UPDATE CHECK. New check_for_update() fetches this
#            script's own published header from the GitHub main branch
#            (raw.githubusercontent.com — the same URL the repo's
#            publish-verification flow already trusts), extracts the
#            published SCRIPT_VERSION, and compares via sort -V. When a
#            newer version exists, every Discord card and email gains a
#            second footer line: "⬆️ vX.Y.Z available — <repo url>".
#            No new repo files — the version source IS the shipped
#            script header, so it can never drift from what operators
#            actually download. UPDATE_CHECK="yes" by default; silent on
#            every failure mode (no curl, timeout, offline, parse failure
#            → footer simply stays one line, monitor unaffected). Result
#            cached per-instance for UPDATE_CHECK_TTL seconds (default
#            86400 = one GitHub fetch per day per instance). Never
#            fetches and never writes cache in --dry-run.
#   v2.5.6-macos.1 — Cosmetic fix matching Linux v2.5.6. The MuSig2
#          summary line now carries its own status icon (✅ complete,
#          ℹ️  in progress, ⚠️  parse failure) so it renders consistently
#          alongside the other health lines instead of floating with a
#          bare three-space indent. Redundant "✓" and "($state)" suffix
#          dropped since the icon carries that meaning. No behavior
#          change, no alert path change — purely how the line renders.
#   v2.5.5-macos.1 — Disk check enhancements, matching Linux v2.5.5 (both
#          suggested by Aussie Epic). (1) The disk line now shows total
#          size and used% next to free space — "✅ Disk: 156GB free of
#          200GB (22% used)" — using df -g column 2 (1G blocks), which
#          was always in the output but never printed. Falls back to the
#          old free-only wording if the total can't be parsed. (2) The
#          Low Disk Space alert now names your DigiByte datadir on its
#          own line so you know exactly where to clean up, via the new
#          DATADIR config variable (default "$HOME/Library/Application
#          Support/DigiByte"). No RPC returns the datadir, so it's
#          config-declared — dual-instance operators set it per config,
#          same pattern as NETWORK_LABEL. The path appears only in the
#          red alert, never the green summary line.
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
#          downgrade "no data" to standby INFO instead of red alert while
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
#   v2.6.1 — cosmetic spacing fix         v2.6.0 — email + update-check (#17)
#   v2.5.6 — MuSig2 status icon           v2.5.5 — disk total+used% + DATADIR
#   v2.5.4 — full-repo audit fixes        v2.5.3 — NETWORK_LABEL chokepoint
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
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email | --watch [seconds]]"
                exit 1
            fi
            CONFIG_ARG="$2"
            shift 2
            ;;
        --dry-run|--summary|--test|--test-email)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email | --watch [seconds]]"
                exit 1
            fi
            ACTION_FLAG="$1"
            shift
            ;;
        --watch)
            if [ -n "$ACTION_FLAG" ]; then
                echo "ERROR: Cannot combine $ACTION_FLAG and $1."
                echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email | --watch [seconds]]"
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
            echo "Usage: $0 [--config /path] [--dry-run | --summary | --test | --test-email | --watch [seconds]]"
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

# Email notifications (v2.6.0-macos.1) — set EMAIL_ENABLED=true in the
# config to activate. Fires on the same triggers as Discord. Uses curl's
# built-in SMTP support (verify with: curl --version | grep smtp —
# standard on modern macOS). See config-macos.template for Gmail App
# Password setup.
EMAIL_ENABLED=false
EMAIL_TO=""           # Recipient address
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587         # 587 = STARTTLS (Gmail/Outlook), 465 = implicit TLS
SMTP_USER=""          # SMTP login (usually your full email address)
SMTP_PASS=""          # Gmail: 16-char App Password — NOT your account password
SMTP_FROM=""          # "Display Name <you@example.com>" — empty = use SMTP_USER

# Update check (v2.6.0-macos.1) — compares this script's version against
# the published copy on GitHub main once per UPDATE_CHECK_TTL seconds.
# When a newer version exists, Discord cards and emails gain a second
# footer line. Silent on any failure. Set UPDATE_CHECK="no" to disable.
UPDATE_CHECK="yes"
UPDATE_CHECK_URL="https://raw.githubusercontent.com/BaumerCrypto/digidollar-oracle-tools/main/oracle-monitor-macos.sh"
UPDATE_CHECK_TTL=86400

# DigiByte Core version check (v2.6.3-macos.1) — compares the running
# node's version against the latest DigiByte Core release on GitHub once
# per DIGIBYTE_UPDATE_TTL seconds. The node-version line turns ✅ green
# when you're on the latest release (or newer) and stays ℹ️ blue with a
# "vX.Y.Z available" note when a newer release exists. Silent on any
# failure (blue line, no note). Set to "no" to disable.
DIGIBYTE_UPDATE_CHECK="yes"
DIGIBYTE_UPDATE_TTL=21600

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

# DigiByte datadir named in the Low Disk Space alert (v2.5.5-macos.1) so
# the operator knows exactly where to clean up. Display-only — the
# monitor never reads or deletes anything here. Dual-instance operators
# should set this per config file (see config-macos.template) so each
# instance's alert names its own datadir.
DATADIR="${HOME}/Library/Application Support/DigiByte"

# ---- v2.7.0: disk + debug.log safety net -----------------------------------

# Yellow disk band (closes #33). Fires a warning at this used-% while the
# MIN_DISK_GB red floor stays the hard alarm. Set to 0 to disable.
DISK_USED_PCT_WARN=80

# debug.log watchdog (Check 13). Yellow alert when the daemon's debug.log
# reaches this many MB. The alert names any enabled debug categories (via
# the local `logging` RPC) because enabling one — e.g. debug=digidollar
# from the old oracle setup docs — also disables the daemon's automatic
# startup log-shrink, and long-uptime oracle boxes then grow without
# bound (measured on my slot-17 VPS: ~374 MB/day with digidollar+net
# enabled vs ~8 MB/day with default logging).
DEBUG_LOG_WARN_MB=1024

# debug.log safe auto-rotation — DEFAULT ON (v2.7.0 behavior change).
# When debug.log reaches DEBUG_LOG_MAX_MB the monitor copies it to
# debug.log.1 and truncates the live file in place (the daemon keeps
# writing — no restart, no lost file handle). The previous .1 is only
# overwritten by the NEXT rotation, so ~2x DEBUG_LOG_MAX_MB of the newest
# history always survives for debugging. Every rotation posts a blue
# Discord card — never silent. Skipped (with a red card) if free space
# can't hold the safety copy. Set DEBUG_LOG_ROTATE="no" if you are
# actively capturing logs for a developer and must keep everything.
DEBUG_LOG_ROTATE="yes"
DEBUG_LOG_MAX_MB=2048
DEBUG_LOG_KEEP=1

# Run the getoracleprice freshness check (Check 5) on every Nth pass. On
# a node with debug=digidollar enabled, every getoracleprice call writes
# ~one line per block of the 24h price window (~5,760 blocks; 4,780-5,800
# by miss rate) — 3 here means one price check per 15
# minutes at the stock cron, a third of that log volume, at the cost of
# up to 10 extra minutes' stale-price alert latency. 1 (default) = every
# pass, exactly the pre-2.7.0 behavior. Summaries always check.
PRICE_CHECK_EVERY=1

# Thresholds — basic health
MIN_PEERS=3
MIN_DISK_GB=5
STALE_PRICE_MINUTES=30  # Reserved for future use — staleness currently from RPC
MEM_THRESHOLD=90
SWAP_THRESHOLD_MB=100
# v2.6.2-macos.1 — Swap "pressure" is only real when RAM is actually
# tight. A filled swap can be a stale leftover from a past heavy event
# (a reindex or verify) that macOS never released. SWAP_MEM_HEADROOM_PCT
# gates the swap alert: only alert when RAM usage is at/above this %.
# macOS has no PSI, so RAM headroom is the sole pressure signal; if it
# can't be measured the monitor fails safe and alerts.
SWAP_MEM_HEADROOM_PCT=70
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
# UPDATE CHECK (v2.6.0-macos.1)
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
# DIGIBYTE CORE VERSION CHECK (v2.6.3-macos.1)
# ============================================================================
# Fetches the latest DigiByte Core release tag from the GitHub releases API,
# cached per instance (STATE_DIR) for DIGIBYTE_UPDATE_TTL seconds. Same
# discipline as the self-update check: memoized per run, silent on failure
# (returns empty → check_version falls back to the plain ℹ️ line), and —
# because check_version runs during --dry-run — it never fetches or writes
# the cache in dry-run (serves any stale cache read-only). Matches Linux.

DIGIBYTE_LATEST=""
DIGIBYTE_CHECKED=false

get_latest_digibyte_release() {
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

    if [ -f "$cache_file" ]; then
        cached_ts=$(sed -n '1p' "$cache_file" 2>/dev/null)
        if [[ "$cached_ts" =~ ^[0-9]+$ ]] && [ $((now - cached_ts)) -lt "$ttl" ]; then
            DIGIBYTE_LATEST=$(sed -n '2p' "$cache_file" 2>/dev/null)
            printf '%s' "$DIGIBYTE_LATEST"
            return 0
        fi
    fi

    # v2.5.4 dry-run discipline: never fetch or write the cache in --dry-run.
    if [ "${DRY_RUN:-false}" = true ]; then
        [ -f "$cache_file" ] && DIGIBYTE_LATEST=$(sed -n '2p' "$cache_file" 2>/dev/null)
        printf '%s' "$DIGIBYTE_LATEST"
        return 0
    fi

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
    # v2.6.0-macos.1: footer via build_footer() — gains a second line
    # when a newer published version exists.
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
# send_email (v2.6.0-macos.1, closes #17) — plain-text email via curl SMTP.
# Same triggers as Discord. No mailx/postfix/sendmail — curl ships with
# SMTP support on modern macOS (verify: curl --version | grep smtp).
# Port 587 (default) = STARTTLS via --ssl-reqd; port 465 = smtps://.
# NETWORK_LABEL prefixes the subject at this single chokepoint, matching
# the v2.5.3-macos.1 Discord title pattern, so dual-instance operators
# can tell which daemon fired the email from the subject line alone.
# ----------------------------------------------------------------------------

send_email() {
    local subject="$1"
    local body="$2"

    [ "${EMAIL_ENABLED}" = "true" ] || return 0

    # v2.5.3-macos.1 parity: label the subject for dual-instance operators
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
    # macOS mktemp requires the template to end in a suffix-free tail
    # ending with X's — using .eml suffix like Linux is not portable to
    # BSD mktemp, so we generate the base then rename.
    local tmpfile
    tmpfile=$(mktemp -t oracle-alert 2>/dev/null) || return 1

    printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s\r\n' \
        "$from_display" "$EMAIL_TO" "$subject" "$full_body" > "$tmpfile"

    # curl on macOS supports the same options as Linux curl for SMTP.
    # --max-time (not `timeout`, which isn't in BSD) bounds total send time.
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

# v2.6.0-macos.1: each wrapper fires both channels on the same event.
# Email subjects carry the severity so inbox scanning works without
# opening.
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
# v2.8.0: inbound/outbound split + maxconnections cap. Total still drives
# the MIN_PEERS threshold; the display line gains the breakdown and cap so
# saturation is visible at a glance (connections_in serves wallets; near
# the cap it bounces them). Display-only, graceful fallback throughout.
check_peers() {
    local ni total cin cout peer_detail=""
    ni=$($CLI getnetworkinfo 2>/dev/null)
    if [ -n "$ni" ]; then
        read total cin cout < <(echo "$ni" | jq -r '"\(.connections) \(.connections_in) \(.connections_out)"' 2>/dev/null)
        [ "$total" = "null" ] && total=""
        if [ -n "$cin" ] && [ "$cin" != "null" ]; then
            local maxc
            maxc=$(peer_maxconnections)
            peer_detail=" (${cin} in / ${cout} out, cap ${maxc})"
        fi
    fi

    if [ -z "$total" ]; then
        total=$($CLI getconnectioncount 2>/dev/null)
        peer_detail=""
        if [ -z "$total" ]; then
            DETAILS+="⚠️  Peers: could not query\n"
            WARNINGS=$((WARNINGS + 1))
            return
        fi
    fi

    if [ "$total" -lt "$MIN_PEERS" ]; then
        if should_alert "low_peers"; then
            alert_yellow "⚠️  Low Peers" "Only $total peers connected (minimum: $MIN_PEERS)."
        fi
        DETAILS+="⚠️  Peers: ${total} connected${peer_detail} (low!)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "low_peers"; then
            alert_green "✅ Peers Recovered" "Peer count back to $total."
        fi
        DETAILS+="✅ Peers: ${total} connected${peer_detail}\n"
    fi
}

# maxconnections from the daemon conf; absent/commented = built-in default
# 125. macOS datadir lives under Application Support by default.
peer_maxconnections() {
    local conf="${DATADIR%/}/digibyte.conf" mc
    [ -f "$conf" ] || { echo "125"; return; }
    mc=$(grep -E '^[[:space:]]*maxconnections[[:space:]]*=' "$conf" 2>/dev/null | tail -1 | sed 's/.*=[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$mc" ] && [ "$mc" -eq "$mc" ] 2>/dev/null; then echo "$mc"; else echo "125"; fi
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
# BSD df has no -B flag. -g reports in 1G blocks; column 2 = total size,
# column 4 = available.
check_disk() {
    local df_line avail_gb total_gb used_pct size_info
    df_line=$(df -g "$DISK_PATH" 2>/dev/null | tail -1)
    avail_gb=$(echo "$df_line" | awk '{print $4}')
    total_gb=$(echo "$df_line" | awk '{print $2}')

    if [ -z "$avail_gb" ] || ! [[ "$avail_gb" =~ ^[0-9]+$ ]]; then
        DETAILS+="⚠️  Disk: could not query $DISK_PATH\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # v2.5.5: df column 2 is the volume total in 1G blocks — it was
    # always in the output, just never printed. Show it plus used% next
    # to free space. If the total is unparsable, fall back to the old
    # free-only wording rather than showing garbage.
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
    # v2.7.0 (closes #33): yellow band well before the red floor — the calm
    # heads-up while MIN_DISK_GB stays the alarm. Only evaluated when df's
    # total parsed (used_pct exists) and the band is enabled (>0).
    elif [ -n "$size_info" ] && [[ "${DISK_USED_PCT_WARN:-80}" =~ ^[0-9]+$ ]] \
         && [ "${DISK_USED_PCT_WARN:-80}" -gt 0 ] && [ "$used_pct" -ge "${DISK_USED_PCT_WARN:-80}" ]; then
        if clear_alert "low_disk"; then
            alert_green "✅ Disk Space Recovered" "Disk space back to ${avail_gb}GB free${size_info}."
        fi
        if should_alert "disk_warn"; then
            alert_yellow "⚠️  Disk Filling Up" "${used_pct}% used — ${avail_gb}GB free${size_info}. The red alert fires below ${MIN_DISK_GB}GB free."$'\n'"The usual offender on an oracle box is a grown debug.log — check the debug.log line in your health summary."$'\n'"Datadir: ${DATADIR%/}/"
        fi
        DETAILS+="⚠️  Disk: ${avail_gb}GB free${size_info} — over ${DISK_USED_PCT_WARN:-80}% warn band\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "low_disk"; then
            alert_green "✅ Disk Space Recovered" "Disk space back to ${avail_gb}GB free${size_info}."
        fi
        if clear_alert "disk_warn"; then
            alert_green "✅ Disk Usage Back Under Band" "Disk usage back under ${DISK_USED_PCT_WARN:-80}% — ${avail_gb}GB free${size_info}."
        fi
        DETAILS+="✅ Disk: ${avail_gb}GB free${size_info}\n"
    fi
}

# --- Check 13: debug.log size + growth watchdog (v2.7.0) ---
# Why this check exists: DigiByte Core inherits Bitcoin Core's
# -shrinkdebugfile default of "on unless -debug is set". The moment an
# operator enables any debug category — and the oracle setup docs
# historically said debug=digidollar — automatic startup log-shrinking
# turns OFF. Oracle boxes are exactly the machines that never restart, so
# the one built-in bound never fires. Measured on my slot-17 VPS in July
# 2026: ~374 MB/day with digidollar+net enabled (testnet26) vs ~8 MB/day
# with default logging (mainnet) — same box, same monitor. The single
# biggest amplifier is getoracleprice (~one category-gated line per block
# of the 24h price window, ~5,760 blocks; 4,780-5,800 by miss rate), so
# ordinary 5-minute monitoring multiplies the
# growth. This check makes the growth visible and names the cause;
# rotate_debuglog() below bounds it.
#
# macOS notes: file size via BSD `stat -f%z`; the datadir path contains a
# space ("Application Support") so every use is quoted; growth baseline
# lives in STATE_DIR (file: debuglog_growth, "epoch bytes", advances at
# most hourly; --dry-run reads but never writes).
check_debuglog() {
    local log_path="${DATADIR%/}/debug.log"

    if [ ! -f "$log_path" ]; then
        DETAILS+="ℹ️  debug.log: not found at ${log_path} (custom datadir? set DATADIR in config)\n"
        return
    fi

    local size_bytes size_mb
    size_bytes=$(stat -f%z "$log_path" 2>/dev/null)
    [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=$(wc -c < "$log_path" 2>/dev/null | tr -d ' ')
    if ! [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
        DETAILS+="⚠️  debug.log: could not read size\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi
    size_mb=$(( size_bytes / 1048576 ))

    # Growth-per-day from a rolling baseline. Two different windows, on
    # purpose: the rate DISPLAYS once the baseline is >=1h old (a 5-minute
    # delta is noise), but the baseline only ADVANCES every 24h. Making
    # both 1h -- as the first cut of this did -- means the */5 cron resets
    # the baseline on the first pass past each hour mark, so 11 of every
    # 12 passes have <1h elapsed and print nothing: the rate would be
    # invisible ~92% of the time, including on most summaries and on the
    # yellow alert itself (caught on live cards before this ever shipped).
    # With a 24h advance the rate shows on ~96% of passes AND measures
    # growth over up to a full day, which is what a figure labelled
    # MB/day should mean. A rotation (size < baseline) resets it at once.
    local growth_file="$STATE_DIR/debuglog_growth" rate_note=""
    local now base_ts base_bytes elapsed
    now=$(date +%s)
    if [ -f "$growth_file" ]; then
        base_ts=$(awk '{print $1}' "$growth_file" 2>/dev/null)
        base_bytes=$(awk '{print $2}' "$growth_file" 2>/dev/null)
        if [[ "$base_ts" =~ ^[0-9]+$ ]] && [[ "$base_bytes" =~ ^[0-9]+$ ]]; then
            elapsed=$(( now - base_ts ))
            if [ "$elapsed" -ge 3600 ] && [ "$size_bytes" -ge "$base_bytes" ]; then
                rate_note=$(awk -v d=$(( size_bytes - base_bytes )) -v s="$elapsed" \
                    'BEGIN{printf " (+%.1f MB/day)", d/s*86400/1048576}')
            fi
        fi
    fi
    if [ "$DRY_RUN" != true ]; then
        if [ ! -f "$growth_file" ] || ! [[ "${base_ts:-}" =~ ^[0-9]+$ ]] \
           || [ $(( now - ${base_ts:-0} )) -ge 86400 ] \
           || [ "$size_bytes" -lt "${base_bytes:-0}" ]; then
            echo "$now $size_bytes" > "$growth_file"
        fi
    fi

    local cats cats_suffix=""
    cats=$($CLI logging 2>/dev/null | jq -r '[to_entries[] | select(.value == true) | .key] | join(", ")' 2>/dev/null)
    [ -n "$cats" ] && [ "$cats" != "null" ] && cats_suffix=" — debug: ${cats}"

    if [ "$size_mb" -ge "${DEBUG_LOG_WARN_MB:-1024}" ]; then
        if should_alert "debuglog_large"; then
            local why fix
            if [ -n "$cats" ] && [ "$cats" != "null" ]; then
                why="Debug categories enabled: ${cats}. Any -debug category also disables the daemon's automatic startup log-shrink, so this file grows until rotated."
                fix="One-line fix if you're not actively debugging: remove the debug= line(s) from digibyte.conf, then restart the daemon at your next maintenance window."
            else
                why="No debug categories are enabled — this is default-logging growth (slow, but unbounded between restarts)."
                fix="The daemon truncates it automatically on the next restart (shrinkdebugfile default)."
            fi
            local rot_note
            if [ "${DEBUG_LOG_ROTATE:-yes}" = "yes" ]; then
                rot_note="Auto-rotation is ON: at ${DEBUG_LOG_MAX_MB:-2048}MB this monitor will copy to debug.log.1 and truncate in place — newest history preserved, blue card posted."
            else
                rot_note="Auto-rotation is OFF (DEBUG_LOG_ROTATE=\"no\"). Manual: cp \"${log_path}\" \"${log_path}.1\" && : > \"${log_path}\""
            fi
            alert_yellow "⚠️  debug.log Growing Large" "debug.log is ${size_mb}MB${rate_note}."$'\n'"${why}"$'\n'"${fix}"$'\n'"${rot_note}"$'\n'"Full guidance: https://github.com/BaumerCrypto/digidollar-oracle-tools/blob/main/ORACLE_HARDENING_GUIDE.md#debuglog-growth-rotation-and-the-disappearing-disk"
        fi
        DETAILS+="⚠️  debug.log: ${size_mb}MB${rate_note}${cats_suffix} (LARGE)\n"
        WARNINGS=$((WARNINGS + 1))
    else
        if clear_alert "debuglog_large"; then
            alert_green "✅ debug.log Back Under Threshold" "debug.log is ${size_mb}MB — under the ${DEBUG_LOG_WARN_MB:-1024}MB warn threshold again."
        fi
        DETAILS+="✅ debug.log: ${size_mb}MB${rate_note}${cats_suffix}\n"
    fi
}

# --- debug.log safe auto-rotation (v2.7.0) — default ON ---
# Design rules, in priority order:
#   1. NEVER destroy the only copy of recent history. Rotation is
#      copy-then-truncate: cp debug.log → debug.log.1, then truncate the
#      LIVE file to zero in place with `: >`. Stock macOS ships no
#      truncate(1) — `: > file` is the identical primitive, and the only
#      safe one here: the daemon holds the file open, so rm or mv would
#      leak the disk space until restart and orphan the write handle.
#      Nothing is lost until a SECOND rotation overwrites debug.log.1 —
#      at default thresholds that keeps ~4 GB of the newest history on
#      disk, which is what a developer actually asks for in an incident.
#   2. NEVER rotate silently. Every rotation posts a blue card.
#   3. NEVER make things worse. The copy momentarily needs as much free
#      space as the log itself; below log-size + 512MB margin the
#      rotation is SKIPPED and a red card explains the manual path
#      (state-gated: fires once, not every pass).
#   4. If the copy fails, the live file is NOT touched (rule 1).
#   5. --dry-run prints what it would do and touches nothing.
# DEBUG_LOG_KEEP: rotated copies to retain (default 1 → debug.log.1).
# Values >1 shift .1→.2→… first. 0 is treated as 1 — truncate-without-
# copy is exactly the evidence destruction this design forbids.
rotate_debuglog() {
    [ "${DEBUG_LOG_ROTATE:-yes}" = "yes" ] || return 0
    local log_path="${DATADIR%/}/debug.log"
    [ -f "$log_path" ] || return 0

    local size_bytes size_mb
    size_bytes=$(stat -f%z "$log_path" 2>/dev/null)
    [[ "$size_bytes" =~ ^[0-9]+$ ]] || size_bytes=$(wc -c < "$log_path" 2>/dev/null | tr -d ' ')
    [[ "$size_bytes" =~ ^[0-9]+$ ]] || return 0
    size_mb=$(( size_bytes / 1048576 ))
    [ "$size_mb" -ge "${DEBUG_LOG_MAX_MB:-2048}" ] || return 0

    local keep="${DEBUG_LOG_KEEP:-1}"
    [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 1 ] || keep=1

    if [ "$DRY_RUN" = true ]; then
        echo "[dry-run] debug.log is ${size_mb}MB ≥ DEBUG_LOG_MAX_MB=${DEBUG_LOG_MAX_MB:-2048}MB — would rotate (cp → debug.log.1, then truncate live file in place)."
        return 0
    fi

    # Rule 3 — free-space rail on the datadir's own volume. BSD df -m:
    # column 4 = available in 1M blocks, plain integer.
    local avail_mb
    avail_mb=$(df -m "$(dirname "$log_path")" 2>/dev/null | tail -1 | awk '{print $4}')
    if ! [[ "$avail_mb" =~ ^[0-9]+$ ]] || [ "$avail_mb" -lt $(( size_mb + 512 )) ]; then
        if should_alert "debuglog_rotate_blocked"; then
            alert_red "🔴 debug.log Rotation Blocked" "debug.log is ${size_mb}MB (≥ ${DEBUG_LOG_MAX_MB:-2048}MB rotation threshold) but only ${avail_mb:-?}MB is free — the safety copy needs ~${size_mb}MB + 512MB margin."$'\n'"Free up space, then either wait for the next pass or rotate manually:"$'\n'"cp \"${log_path}\" \"${log_path}.1\" && : > \"${log_path}\""
        fi
        return 1
    fi

    local i
    if [ "$keep" -gt 1 ]; then
        for (( i=keep-1; i>=1; i-- )); do
            [ -f "${log_path}.${i}" ] && mv -f "${log_path}.${i}" "${log_path}.$((i+1))" 2>/dev/null
        done
    fi

    # Rule 1/4 — copy first; truncate ONLY if the copy landed.
    if ! cp -f "$log_path" "${log_path}.1" 2>/dev/null; then
        if should_alert "debuglog_rotate_blocked"; then
            alert_red "🔴 debug.log Rotation Failed" "Could not copy debug.log to debug.log.1 — the live file was left untouched (evidence rule). Check permissions and free space."
        fi
        return 1
    fi
    : > "$log_path"

    clear_alert "debuglog_rotate_blocked" > /dev/null 2>&1
    clear_alert "debuglog_large" > /dev/null 2>&1

    # Rule 2 — every rotation is announced, never state-gated.
    alert_blue "🔁 debug.log Rotated" "debug.log reached ${size_mb}MB (rotation threshold: ${DEBUG_LOG_MAX_MB:-2048}MB)."$'\n'"Newest history preserved in: ${log_path}.1"$'\n'"Live file truncated in place — the daemon keeps writing, no restart needed. Nothing is lost until the NEXT rotation overwrites debug.log.1."$'\n'"Seeing this card often? A debug category is on — check the debug.log line in your health summary."
    return 0
}

# --- Price-check interval gate (v2.7.0) ---
# getoracleprice is the single loudest RPC a v9.26.4 node exposes when
# debug=digidollar is enabled (~one line per block of the 24h window,
# ~5,760 blocks; 4,780-5,800 by miss rate). N=3 with the
# stock 5-minute schedule = one price check per 15 minutes — a third of
# that log source for up to 10 extra minutes' stale-price latency.
# Default 1 = every pass, exactly the pre-2.7.0 behavior. Counter lives
# in STATE_DIR; --summary, --watch, and --dry-run route through
# send_summary's direct check_price call and always check.
maybe_check_price() {
    local n="${PRICE_CHECK_EVERY:-1}"
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -le 1 ]; then
        check_price
        return
    fi
    local cfile="$STATE_DIR/price_check_counter" count=0
    [ -f "$cfile" ] && count=$(cat "$cfile" 2>/dev/null)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    count=$(( (count + 1) % n ))
    echo "$count" > "$cfile"
    [ "$count" -eq 0 ] && check_price
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
        DETAILS+="⚠️  Memory: could not query\n"
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
        DETAILS+="⚠️  Memory: could not query\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

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
# v2.6.2 fixes a false positive Aussie Epic hit on Linux: a filled swap is
# NOT the same as memory pressure. After a heavy transient (a reindex, a
# verify pass) the OS can leave several GB parked in swap long after the
# pressure ended — stale, not a live problem. When swap is filled we now
# gate the alert on *current* pressure via RAM headroom: only alert when
# RAM usage >= SWAP_MEM_HEADROOM_PCT. macOS has no PSI (the Linux stall
# meter), so RAM headroom is the sole signal here; if it can't be measured
# we fail safe and alert as v2.4 did.
#
# macOS reports dynamic swap via `sysctl vm.swapusage`, output format:
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

    # Swap at/below threshold — definitively fine. Clear any prior alert.
    if [ "$swap_used_mb" -le "$SWAP_THRESHOLD_MB" ]; then
        if clear_alert "swap_pressure"; then
            alert_green "✅ Swap Pressure Cleared" "Swap usage back to ${swap_used_mb}MB of ${swap_total_mb}MB."
        fi
        DETAILS+="✅ Swap: ${swap_used_mb}MB / ${swap_total_mb}MB\n"
        return
    fi

    # Swap is filled. Compute RAM used% (same method as check_memory) and
    # decide whether the fill reflects real current pressure.
    local page_size total_bytes vm free_pages inactive_pages spec_pages mem_pct
    page_size=$(sysctl -n hw.pagesize 2>/dev/null)
    total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
    vm=$(vm_stat 2>/dev/null)
    free_pages=$(echo "$vm"     | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
    inactive_pages=$(echo "$vm" | awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
    spec_pages=$(echo "$vm"     | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
    [ -z "$free_pages" ] && free_pages=0
    [ -z "$inactive_pages" ] && inactive_pages=0
    [ -z "$spec_pages" ] && spec_pages=0
    mem_pct=""
    if [ -n "$page_size" ] && [ -n "$total_bytes" ] && [ -n "$vm" ]; then
        mem_pct=$(echo "$page_size $total_bytes $free_pages $inactive_pages $spec_pages" | \
            awk '{avail=($3+$4+$5)*$1; used=$2-avail; printf "%.0f", used/$2*100}')
    fi

    local pressure=0 have_signal=0 reason="" stale_note=""
    if [ -n "$mem_pct" ] && [ "$mem_pct" -ge 0 ] 2>/dev/null; then
        have_signal=1
        stale_note="RAM ${mem_pct}%"
        if [ "$mem_pct" -ge "$SWAP_MEM_HEADROOM_PCT" ] 2>/dev/null; then
            pressure=1
            reason="RAM ${mem_pct}%"
        fi
    fi

    if [ "$pressure" -eq 1 ]; then
        if should_alert "swap_pressure"; then
            alert_yellow "⚠️  Swap Pressure" "Swap usage: ${swap_used_mb}MB of ${swap_total_mb}MB with active memory pressure (${reason}). Check running processes."
        fi
        DETAILS+="⚠️  Swap: ${swap_used_mb}MB / ${swap_total_mb}MB used (pressure! — ${reason})\n"
        WARNINGS=$((WARNINGS + 1))
    elif [ "$have_signal" -eq 0 ]; then
        # RAM% unmeasurable — fail safe, alert as v2.4 did.
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

    # v2.6.3-macos.1: explicit opt-out (first branch, takes precedence) for
    # operators who deliberately run headless WITHOUT launchd.
    # LAUNCHD_LABEL="none" (or "skip"/"disabled") replaces the launchd check
    # with an informational line and skips the rest of this block.
    local launchd_disabled=false
    case "$LAUNCHD_LABEL" in
        none|None|NONE|skip|Skip|SKIP|disabled|Disabled|DISABLED) launchd_disabled=true ;;
    esac

    if [ "$launchd_disabled" = true ]; then
        DETAILS+="ℹ️  launchd: check disabled (LAUNCHD_LABEL=\"none\")\n"
    elif [ "$is_qt" = true ]; then
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
        DETAILS+="⚠️  Oracle process: $oracle_status\n"
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
    local version running_ver display_ver latest_ver
    version=$($CLI getnetworkinfo 2>/dev/null | jq -r .subversion 2>/dev/null)
    if [ -z "$version" ] || [ "$version" = "null" ]; then
        return
    fi

    # Bare numeric running version: /DigiByte:9.26.4/ -> 9.26.4
    running_ver=$(printf '%s' "$version" | sed -n 's|^/[^:]*:\(.*\)/$|\1|p')

    # v2.6.2-macos.1: strip the /Name:Version/ wrapper for display.
    # /DigiByte:9.26.4/ -> DigiByte: v9.26.4
    display_ver=$(printf '%s' "$version" | sed 's|^/\([^:]*\):\(.*\)/$|\1: v\2|')

    # v2.6.3-macos.1: compare against the latest DigiByte Core release.
    #   ✅ green — on the latest (or newer); ℹ️ blue "— vX available" when a
    #   newer release exists; ℹ️ plain blue when it can't be determined.
    latest_ver=$(get_latest_digibyte_release)

    if [ -n "$latest_ver" ] && [ -n "$running_ver" ]; then
        local newest
        newest=$(printf '%s\n%s\n' "$running_ver" "$latest_ver" | sort -V | tail -1)
        if [ "$running_ver" = "$latest_ver" ] || [ "$newest" = "$running_ver" ]; then
            DETAILS+="✅ $display_ver\n"
        else
            DETAILS+="ℹ️  $display_ver — v${latest_ver} available\n"
        fi
    else
        DETAILS+="ℹ️  $display_ver\n"
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
        DETAILS+="⚠️  NTP: could not verify (sntp query failed)\n"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    local in_range
    in_range=$(echo "$offset $NTP_MAX_OFFSET" | \
        awk '{o=$1; if (o<0) o=-o; print (o <= $2) ? "yes" : "no"}')

    if [ "$in_range" != "yes" ]; then
        if should_alert "ntp_desync"; then
            alert_yellow "⚠️  NTP Desync" "System clock is off by ${offset}s vs $NTP_SERVER. Oracle timestamps may drift. Run: sudo sntp -sS $NTP_SERVER"
        fi
        DETAILS+="⚠️  NTP: offset ${offset}s (NOT synchronized)\n"
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
# v2.7.0 / v9.26.5 SHAPE NOTE (PR #429, BIP90 burial): the burial removes
# the BIP9 *signaling* fields from getdigidollardeploymentinfo — this
# check never read those. The fields it does read
# (oracle_consensus_required, oracle_total_slots, musig2_session.*) are
# DD-roster/session data and persist in the buried shape per the v9.26.5
# release notes; every read below carries a jq fallback (// 7, // 35,
# // "?"), so a dropped field degrades to the correct mainnet constants
# or a visible ⚠️ line — never a crash, never a silent wrong alert.
#
check_quorum() {
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
    local musig_epoch musig_state musig_nonces musig_sigs musig_detail
    musig_epoch=$(echo "$deploy_info" | jq -r '.musig2_session.epoch // "?"' 2>/dev/null)
    musig_state=$(echo "$deploy_info" | jq -r '.musig2_session.state // "?"' 2>/dev/null)
    musig_nonces=$(echo "$deploy_info" | jq -r '.musig2_session.nonce_count // "?"' 2>/dev/null)
    musig_sigs=$(echo "$deploy_info" | jq -r '.musig2_session.partial_sig_count // "?"' 2>/dev/null)

    # v2.5.6-macos.1: musig_detail now carries its own status icon so
    # the line renders consistently alongside the other ✅/ℹ️/⚠️  health
    # lines instead of floating with a bare three-space indent.
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
    # This matches the dashboard's "Online Heartbeats" metric and is stable
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
    check_debuglog            # v2.7.0: Check 13 — debug.log watchdog
    rotate_debuglog           # v2.7.0: safe auto-rotation (default ON)
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
        local issue_word="Issues"; [ "$ISSUES" -eq 1 ] && issue_word="Issue"
        status="🔴 $ISSUES $issue_word Detected"
    elif [ $WARNINGS -gt 0 ]; then
        color=16776960  # yellow
        local warn_word="Warnings"; [ "$WARNINGS" -eq 1 ] && warn_word="Warning"
        status="⚠️  $WARNINGS $warn_word"
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
        # v2.6.0-macos.1: no webhook configured but email is → still email
        # the summary (email-only operators are the point of #17). Dry-run
        # is handled inside send_email (prints, sends nothing).
        if [ "$DRY_RUN" != true ] && [ "${EMAIL_ENABLED}" = "true" ]; then
            send_email "$status — Health Summary" "$desc"
        fi
        return
    fi

    # v2.6.0-macos.1: email fires alongside the Discord card. send_email
    # prefixes NETWORK_LABEL itself (chokepoint), so the subject passed
    # here is label-free to avoid doubling.
    send_email "$status — Health Summary" "$desc"

    # v2.5.4-macos.1: payload built with jq -n (matches send_discord).
    # v2.6.0-macos.1: footer via build_footer() — two lines when an
    # update exists.
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

    # v2.7.0: v9.26.5 (PR #429) buries the DigiDollar deployment (BIP90)
    # and reshapes this RPC to {enabled, type:"buried",
    # status:"active"|"defined", activation_height}. The buried shape
    # KEEPS a status field, so the primary read works for both v9.26.4
    # and v9.26.5 nodes; the fallback additionally accepts the generic
    # buried form ({type:"buried", active:true}) should status ever be
    # absent — daemon and monitor can be upgraded in either order.
    DD_SHAPE=$(echo "$deploy_info" | jq -r '.type // "bip9"' 2>/dev/null)
    DD_STATUS=$(echo "$deploy_info" | jq -r '.status // empty' 2>/dev/null)
    if [ -z "$DD_STATUS" ] || [ "$DD_STATUS" = "null" ]; then
        if [ "$DD_SHAPE" = "buried" ] && \
           [ "$(echo "$deploy_info" | jq -r '.active // false' 2>/dev/null)" = "true" ]; then
            DD_STATUS="active"
        else
            DD_STATUS="unknown"
        fi
    fi

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
    maybe_check_price         # v2.7.0: PRICE_CHECK_EVERY gate around Check 5
    check_disk
    check_debuglog            # v2.7.0: Check 13 — debug.log watchdog
    rotate_debuglog           # v2.7.0: safe auto-rotation (default ON)
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
            echo "       (Modern macOS ships with SMTP-capable curl by default.)"
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
            echo "    - macOS firewall or corporate network blocking outbound SMTP"
            exit 1
        fi
        ;;
    *)
        run_checks
        ;;
esac
