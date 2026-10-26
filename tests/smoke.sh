#!/bin/bash
# Smoke test for menu.sh: build every menu, run every action string, flag shell-level breakage.
#
# Usage: tests/smoke.sh [-v] [-t SECONDS] [PATTERN]
#   -v          also list passing options
#   -t SECONDS  per-action timeout (default 30; env SMOKE_TIMEOUT)
#   PATTERN     only run options whose path matches this grep -E regex, e.g. 'Network'
#
# Actions are read-only, but some are slow (full-filesystem scans) and some use the network
# (Public IP, Tailscale netcheck, dnf check-update). Run under sudo to exercise root-only paths.
# Exit status: 0 if nothing FAILed, 1 otherwise. TIMEOUT and EMPTY are warnings.
set -uo pipefail

MENU="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/menu.sh"
TIMEOUT="${SMOKE_TIMEOUT:-30}"
VERBOSE=0
while getopts "vt:" opt; do
    case "$opt" in
        v) VERBOSE=1 ;;
        t) TIMEOUT="$OPTARG" ;;
        *) sed -n '2,11s/^# \{0,1\}//p' "$0"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
FILTER="${1:-}"

# Text that means the action string itself is broken, not that a tool is missing or the
# result is empty (those print fallback messages by design).
BROKEN='command not found|unbound variable|syntax error|bad substitution|unexpected EOF|bad array subscript|ambiguous redirect'

# shellcheck source=../menu.sh
source "$MENU"
set +e
trap - INT

# Record triples on fd 3 instead of running the menu loop; silence the menu's own output.
run_submenu() {
    shift
    while [[ $# -gt 0 ]]; do
        printf '%s\0%s\0%s\0' "$1" "$2" "$3" >&3
        shift 3
    done
}
check_deps() { :; }
warn_not_root() { :; }

is_menu() {
    declare -f "$1" 2>/dev/null | grep -q 'run_submenu'
}

declare -a PATHS=() LABELS=() ACTIONS=()
declare -A SEEN=()
pass=0 fail=0 warn=0

report() {   # status, path, detail
    case "$1" in
        PASS) pass=$((pass + 1)); [[ $VERBOSE -eq 1 ]] || return 0 ;;
        FAIL) fail=$((fail + 1)) ;;
        *)    warn=$((warn + 1)) ;;
    esac
    printf '%-7s %s%s\n' "$1" "$2" "${3:+  — $3}"
}

# Build a menu in a subshell (set -u, as in menu.sh) and queue its options.
build_menu() {   # function, path
    local err triples
    err=$(mktemp)
    mapfile -d '' triples < <(set -u; "$1" 3>&1 >/dev/null 2>"$err")
    wait $! 2>/dev/null
    if [[ -s "$err" || ${#triples[@]} -eq 0 ]]; then
        report FAIL "$2" "menu failed to build: $(head -1 "$err")"
        rm -f "$err"
        return
    fi
    rm -f "$err"
    local i
    for ((i = 0; i + 2 < ${#triples[@]}; i += 3)); do
        [[ -z "${triples[i+1]}" ]] && continue   # empty label: skipped by run_submenu too
        PATHS+=("$2 > ${triples[i]} ${triples[i+1]}")
        LABELS+=("${triples[i+1]}")
        ACTIONS+=("${triples[i+2]}")
    done
}

# Run one action the way run_submenu would, in a fresh shell, with paging disabled.
run_action() {   # action -> sets OUT, RC
    OUT=$(timeout "$TIMEOUT" bash -c 'source "$1"; less() { cat; }; run_cmd "$2"' _ "$MENU" "$1" </dev/null 2>&1)
    RC=$?
}

build_menu mainmenu "Main"
SEEN[mainmenu]=1

declare -A CACHE_STATUS=() CACHE_DETAIL=()
for ((n = 0; n < ${#ACTIONS[@]}; n++)); do
    path="${PATHS[n]}" action="${ACTIONS[n]}"
    case "$action" in
        fn_bye|return_to|run_custom_command) continue ;;
    esac
    if is_menu "$action"; then
        if [[ -z "${SEEN[$action]:-}" ]]; then
            SEEN[$action]=1
            build_menu "$action" "$path"
        fi
        continue
    fi
    [[ -n "$FILTER" ]] && ! grep -qE -- "$FILTER" <<<"$path" && continue

    if [[ -z "${CACHE_STATUS[$action]:-}" ]]; then
        run_action "$action"
        if [[ $RC -eq 124 ]]; then
            status=TIMEOUT detail="no result after ${TIMEOUT}s"
        elif [[ $RC -ne 0 ]]; then
            status=FAIL detail="exit $RC: $(tail -1 <<<"$OUT")"
        elif hit=$(grep -m1 -E "$BROKEN" <<<"$OUT"); then
            status=FAIL detail="$hit"
        elif [[ -z "${OUT//[[:space:]]/}" ]]; then
            status=EMPTY detail="printed nothing"
        else
            status=PASS detail=""
        fi
        CACHE_STATUS[$action]=$status CACHE_DETAIL[$action]=$detail
    fi
    report "${CACHE_STATUS[$action]}" "$path" "${CACHE_DETAIL[$action]}"
done

echo
echo "$pass passed, $fail failed, $warn warnings ($(is_root && echo root || echo non-root), timeout ${TIMEOUT}s)"
[[ $fail -eq 0 ]]
