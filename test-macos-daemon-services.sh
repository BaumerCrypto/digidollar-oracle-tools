#!/bin/bash
###############################################################################
# test-macos-daemon-services.sh — Isolated harness for check_daemon +
# check_services on macOS. Mirrors the Session 23 approach used for the
# Linux v2.5.2 verification. Mocks pgrep, launchctl, jq, and $CLI so we
# can drive each scenario deterministically without a real DigiByte node.
###############################################################################

set -u

SCRIPT="/home/claude/work/oracle-monitor-macos.sh"
PASS=0
FAIL=0

# Helper: run one scenario in a subshell with a controlled environment,
# then check that the DETAILS string contains an expected substring.
run_scenario() {
    local label="$1"
    local expect="$2"
    local not_expect="$3"    # optional — substring that must NOT appear
    local details

    details=$(
        # Fresh subshell — no state carries between scenarios
        # Extract only the pieces we need: check_daemon, check_services, and
        # the surrounding globals. We source the script's functions via a
        # cleaner approach: redefine bash's `pgrep`, `launchctl`, and $CLI
        # BEFORE sourcing, so the functions bind to our mocks.

        # Skip the dependency check by pre-inserting jq as a function
        jq() { echo ""; }
        export -f jq

        # Source just the function definitions we need by extracting them.
        # We can't source the whole script (it runs). So use a trick: pull
        # out check_daemon and check_services as text, plus shared helpers.
        eval "$(awk '/^# --- Check 1: Is digibyted/,/^}$/' "$SCRIPT")"
        eval "$(awk '/^# --- Check 8: Service status/,/^}$/' "$SCRIPT")"
        # Provide DETAILS/ISSUES/WARNINGS + stub helpers
        DETAILS=""
        ISSUES=0
        WARNINGS=0
        DD_ACTIVE="true"
        DD_STATUS="active"
        LAUNCHD_LABEL="${SC_LAUNCHD_LABEL:-}"
        DAEMON_PROCESS="${SC_DAEMON_PROCESS:-}"
        CLI="mock-cli"
        WALLET_FLAG=""
        # Mocks: pgrep -x → check env-provided PROCESSES list
        pgrep() {
            local search=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -x) shift; search="$1"; shift ;;
                    *) shift ;;
                esac
            done
            case " ${SC_PROCESSES:-} " in
                *" $search "*) return 0 ;;
                *) return 1 ;;
            esac
        }
        # launchctl mock — returns list based on SC_LAUNCHD_LOADED
        launchctl() {
            case "$1" in
                list) echo "${SC_LAUNCHD_LOADED:-}" ;;
            esac
        }
        # $CLI mock — returns oracle-running JSON if SC_ORACLE_RUNNING is true
        mock-cli() {
            # This is invoked as $CLI $WALLET_FLAG listoracle
            for arg in "$@"; do
                if [ "$arg" = "listoracle" ]; then
                    if [ "${SC_ORACLE_RUNNING:-false}" = "true" ]; then
                        echo '{"running":true}'
                    else
                        echo '{"running":false}'
                    fi
                fi
            done
        }
        # Stub alert helpers — silence noise
        alert_red()    { :; }
        alert_yellow() { :; }
        alert_green()  { :; }
        should_alert() { return 0; }   # dry-run behavior
        clear_alert()  { return 1; }

        check_daemon
        check_services
        # Print DETAILS for assertion
        printf '%s' "$DETAILS"
    )

    # Assertion
    local ok=true
    if [[ "$details" != *"$expect"* ]]; then
        ok=false
    fi
    if [ -n "$not_expect" ] && [[ "$details" == *"$not_expect"* ]]; then
        ok=false
    fi

    if [ "$ok" = true ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected substring: $expect"
        if [ -n "$not_expect" ]; then
            echo "  must-not-contain:   $not_expect"
        fi
        echo "  got DETAILS: $details"
        FAIL=$((FAIL + 1))
    fi
}

echo "===== macOS check_daemon + check_services scenarios ====="

# Scenario 1: only digibyted headless running — auto-detect finds it
SC_PROCESSES="digibyted"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S1: auto-detect finds digibyted headless" \
    "Node: digibyted running" \
    "NOT RUNNING"

# Scenario 2: only DigiByte-Qt running — auto-detect finds it via first Qt candidate
SC_PROCESSES="DigiByte-Qt"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S2: auto-detect finds DigiByte-Qt" \
    "Node: DigiByte-Qt running" \
    "NOT RUNNING"

# Scenario 3: only Digibyte-Qt (mixed case, second candidate) running
SC_PROCESSES="Digibyte-Qt"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S3: auto-detect finds Digibyte-Qt (mixed case)" \
    "Node: Digibyte-Qt running" \
    "NOT RUNNING"

# Scenario 4: only digibyte-qt (all lowercase, Linux-style, third fallback)
SC_PROCESSES="digibyte-qt"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S4: auto-detect finds digibyte-qt (lowercase)" \
    "Node: digibyte-qt running" \
    "NOT RUNNING"

# Scenario 5: nothing running — real Node Down fires
SC_PROCESSES=""
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="false"
run_scenario "S5: nothing running fires real Node Down" \
    "NOT RUNNING (checked digibyted, DigiByte-Qt, Digibyte-Qt, digibyte-qt)" \
    ""

# Scenario 6: DAEMON_PROCESS explicit override honored
SC_PROCESSES="DigiByte-Qt"
SC_DAEMON_PROCESS="DigiByte-Qt"
SC_LAUNCHD_LABEL=""
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S6: explicit DAEMON_PROCESS override honored" \
    "Node: DigiByte-Qt running" \
    "NOT RUNNING"

# Scenario 7: check_services skips launchd when Qt is the detected daemon
SC_PROCESSES="DigiByte-Qt"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL="org.digibyte.digibyted"
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S7: Qt detected → launchd check SKIPPED with INFO line" \
    "launchd: n/a — Qt wallet is the running daemon" \
    "not loaded"

# Scenario 8: headless daemon + LAUNCHD_LABEL loaded → green ✅
SC_PROCESSES="digibyted"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL="org.digibyte.digibyted"
SC_LAUNCHD_LOADED="12345 0 org.digibyte.digibyted"
SC_ORACLE_RUNNING="true"
run_scenario "S8: headless + LAUNCHD_LABEL loaded → green" \
    "LaunchAgent org.digibyte.digibyted: loaded" \
    "not loaded"

# Scenario 9: headless daemon + LAUNCHD_LABEL NOT loaded → red ISSUE
SC_PROCESSES="digibyted"
SC_DAEMON_PROCESS=""
SC_LAUNCHD_LABEL="org.digibyte.digibyted"
SC_LAUNCHD_LOADED=""
SC_ORACLE_RUNNING="true"
run_scenario "S9: headless + LAUNCHD_LABEL missing → red" \
    "LaunchAgent org.digibyte.digibyted: not loaded" \
    "n/a"

echo ""
echo "===== RESULT: $PASS pass / $FAIL fail ====="
[ "$FAIL" -eq 0 ]
