#!/usr/bin/env bash
# tools/warm.sh — LogicKernel's WARM LANE: one daemon with LogicKernel loaded under Revise
# (tools/warm_session.jl), for ITERATION (user, 2026-10-03).
#
#   tools/warm.sh start | stop | restart | status          # status prints the daemon's memory too;
#                                                          # start exits 6 while ANOTHER checkout's
#                                                          # daemon runs, naming it (user, 2026-10-14);
#                                                          # LOGICKERNEL_WARM_SECOND=1: a SECOND daemon
#                                                          # beside one other (audit D-0114, below);
#                                                          # a daemon exits after LOGICKERNEL_WARM_IDLE_S
#                                                          # (3600) with no request; all of them share
#                                                          # lk-warm.slice (tools/lib_evidence.sh)
#   tools/warm.sh file test/core_lang/test_unify.jl [impl]   # one test file, REAL exit code: a term-
#                                                            # generic file on every implementation
#                                                            # (or just `impl`), swipl REQUIRED;
#                                                            # exit 4 = NO VERDICT (fail closed)
#   tools/warm.sh send snippet.jl          # any snippet (or stdin); exit 0 ok · 1 threw · 2 timeout · 3 no daemon
#   tools/warm.sh bench [bench.jl args]    # tools/bench.jl in the daemon: no JIT in the timings
#   tools/warm.sh check                    # the formatter, port_check, the manifest and the term-scopes
#                                          # declarations (seconds): after an edit to a header, a marker,
#                                          # the inventory or a test file's TERM TYPES PER CHUNK line
#   tools/warm.sh meta-check | inert-check [BUDGET_S]   # two more of `check`'s CI-parity steps, alone
#   tools/warm.sh fmt-pin                  # the JuliaFormatter version CI's Format job pins (`check` compares it)
#   tools/warm.sh term-scopes              # the declarations alone (tools/term_scopes_check.jl, CI's
#                                          # Pkg.test check, audit D-0206 4a)
#   tools/warm.sh static                   # the static-analysis gate (test/test_static_analysis.jl: JET, Aqua,
#                                          # AllocCheck) WARM, on the reference type
#   tools/warm.sh check|file|static|branch-gate … --summary
#                                          # SUMMARY MODE (D-0178): the same run, its full output in
#                                          # .warm/summary_<name>.log, <= 10 lines printed (verdict,
#                                          # counts, seconds, failing file:line, the log's path); the
#                                          # exit status is the run's own (tools/summarize_log.sh)
#   tools/warm.sh fmt                      # the formatter in WRITE mode on the changed .jl files, WARM —
#                                          # run before check/branch-gate
#   tools/warm.sh inventory                # port_check.jl --write-inventory, WARM: the generated blocks
#                                          # rewritten, then port_check (no cold julia)
#   tools/warm.sh preflight                # WARM: what a full run would fail on, BEFORE one (exit 0/1);
#                                          # a stale daemon (a deleted method it kept) is restarted
#                                          # and the preflight rerun once
#   tools/warm.sh branch-gate              # WARM: a BRANCH commit's evidence (never main's) — the
#                                          # fast check, then the tree-wide files and every changed
#                                          # test file on every term type; CI's full run is the gate
#   tools/warm.sh branch-gate-files        # the test files a branch-gate would run, one per line
#   tools/warm.sh evidence                 # a FRESH tools/run_tests.sh — the commit gate's run
#   tools/warm.sh locked CMD [ARGS…]       # run CMD holding the lane for its WHOLE run (a mutation
#                                          # driver): its own warm.sh calls pass, everyone else's are
#                                          # REFUSED (exit 5)
#   tools/warm.sh pool                     # pre-warm the evidence workers for THIS tree
#   tools/warm.sh workload on|off          # the precompile workload, for THIS checkout only
#
# 🔴 ITERATION ONLY, NEVER EVIDENCE (user, 2026-10-03): a long-lived daemon is where state leaks
# hide, so commit evidence is a process that started clean — `evidence` runs tools/run_tests.sh,
# which shares nothing with the daemon. A CHANGED STRUCT restarts the daemon by itself, with the
# reason printed, "struct changed: <name>" (`_struct_gate`, user 2026-10-12): Revise redefines the
# type, but a method it does not re-evaluate stays compiled for the old one. `restart` also clears
# what a long-lived process accumulates — values of a type's old layout, test residue, an update
# that failed partway — and recovers from a refused revision.
#
# Exit codes are the snippet's own (Core's tools/warm_send.sh, whose two silent-success bugs this
# keeps fixed): a missing verdict is a FAILURE, and a timeout prints no output — it would be the
# previous run's — and exits 2, distinct from a failure.
set -uo pipefail
# 🔴 A TASK CEILING ON THIS SCRIPT'S OWN WORK (user, 2026-10-14). The daemon and the evidence workers
# run in capped units, but this shell and what it forks did not: MEASURED that day, a backtick in an
# unquoted heredoc made a `check` run itself recursively — a 1558-process fork chain, outside every
# unit, while the background-job hook exempted warm.sh as "self-capped". So, where user systemd
# exists, the script re-runs itself in a scope with a task ceiling (LOGICKERNEL_TASKS_MAX, 512), as
# tools/build_oracle.sh does: a runaway is one killed scope. The PID is kept (systemd-run --scope
# execs in place), so the lane lock's owner checks hold; a nested call inherits the scope. No
# memory ceiling here: the heavy work is in its own units, each with its own.
if [ -z "${LOGICKERNEL_TASKS_CAPPED:-}" ] && command -v systemd-run > /dev/null 2>&1 &&
    systemd-run --user --scope true > /dev/null 2>&1; then
    exec env LOGICKERNEL_TASKS_CAPPED=1 systemd-run --user --scope --quiet \
        -p TasksMax="${LOGICKERNEL_TASKS_MAX:-512}" "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.warm"
# shellcheck source=/dev/null
. "$ROOT/tools/lib_evidence.sh"
UNIT="logickernel-warm-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)"   # one daemon per checkout

_running() { systemctl --user is-active --quiet "$UNIT" && [ -f "$DIR/ready" ]; }

# ONE WARM DAEMON AT A TIME (user, 2026-10-14). MEASURED that evening: the machine stalled and was
# reset with four daemons up, three of them idle for hours in OTHER worktrees. So `start` REFUSES
# (exit 6) while another checkout's daemon runs, and names it — pid, worktree, age, rss — so it can
# be stopped. It never stops one itself: that could be another session's, mid-job. With the idle
# exit (tools/warm_session.jl) and the shared slice (tools/lib_evidence.sh `_lk_slice`).
# _other_daemons — one line per OTHER checkout's active warm daemon
_other_daemons() {
    local u pid wd age rss
    for u in $(systemctl --user list-units 'logickernel-warm-*.service' --state=active,activating \
        --no-legend --plain 2>/dev/null | awk '{print $1}'); do
        [ "$u" = "$UNIT.service" ] && continue
        pid=$(systemctl --user show "$u" -p MainPID --value 2>/dev/null)
        wd=$(systemctl --user show "$u" -p WorkingDirectory --value 2>/dev/null)
        # PARALLEL MUTANT WORKERS (D-0077 item 6, 2026-10-21): `tools/mutate.sh run-parallel` starts one
        # daemon per mutant worktree and sets LOGICKERNEL_WARM_SIBLING_MUTANTS=1 for them, so a daemon
        # that sits in another MUTANT worktree (its .warm/MUTANT_WORKTREE marker) is not "another
        # checkout" to them. Only then, and only those: any other checkout's daemon still refuses.
        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 1 ] && [ -n "$wd" ] &&
            [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue
        age=$(ps -o etime= -p "${pid:-0}" 2>/dev/null | tr -d ' ')
        rss=$(awk '/^VmRSS:/ {printf "%.1f GB", $2 / 1048576}' "/proc/${pid:-0}/status" 2>/dev/null)
        echo "unit $u, pid ${pid:-?}, worktree ${wd:-?}, age ${age:-?}, rss ${rss:-?}"
    done
}

# A SECOND DAEMON (audit D-0114, 2026-10-23): with LOGICKERNEL_WARM_SECOND=1, `start` may run this
# checkout's daemon beside ONE other checkout's — never a third, never two on one tree (the unit is
# per checkout) — and only while MemAvailable is at least LOGICKERNEL_WARM_SECOND_MIN_GB (8). The
# second daemon gets a slice of its own beside `lk-warm.slice` (lk-warm2.slice, MemoryMax
# LOGICKERNEL_WARM_SECOND_MEM_MAX, 6G), so when memory runs short the SECOND lane is the one the
# kernel kills, never the first (D-0114 item 1: the landing closest to main keeps its daemon). A
# timeout while both run is rerun once alone before it counts (D-0114 item 3).
# _second_ok OTHERS — whether a second daemon may start beside OTHERS (one line each); says why not
_second_ok() {
    local n avail_kb min_gb="${LOGICKERNEL_WARM_SECOND_MIN_GB:-8}"
    n=$(printf '%s\n' "$1" | grep -c .)
    if [ "$n" -gt 1 ]; then
        echo "warm lane: REFUSED — LOGICKERNEL_WARM_SECOND allows ONE other daemon, $n are running" >&2
        return 1
    fi
    avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    if [ "${avail_kb:-0}" -lt $((min_gb * 1048576)) ]; then
        echo "warm lane: REFUSED — a second daemon needs ${min_gb} GB available, $((${avail_kb:-0} / 1048576)) GB are (D-0114)" >&2
        return 1
    fi
    return 0
}

_start() {
    if _running; then echo "warm lane: running (unit $UNIT, pid $(cat "$DIR/ready"))"; return 0; fi
    local others second=0
    others="$(_other_daemons)"
    if [ -n "$others" ] && [ "${LOGICKERNEL_WARM_SECOND:-}" = 1 ]; then
        _second_ok "$others" || return 6
        second=1
        export LOGICKERNEL_SLICE=lk-warm2.slice
        export LOGICKERNEL_SLICE_MEM_MAX="${LOGICKERNEL_WARM_SECOND_MEM_MAX:-6G}"
        echo "warm lane: SECOND daemon (D-0114) beside:"
        printf '%s\n' "$others" | sed 's/^/  /'
        others=""
    fi
    if [ -n "$others" ]; then
        {
            echo "warm lane: REFUSED — another checkout's warm daemon is running (one at a time, user 2026-10-14):"
            printf '%s\n' "$others" | sed 's/^/  /'
            echo "  stop it first, in its worktree: tools/warm.sh stop   (# allow-restart: <reason>)"
        } >&2
        return 6
    fi
    mkdir -p "$DIR"
    rm -f "$DIR/ready" "$DIR/done" "$DIR/status" "$DIR/in.jl"
    # remembered for `_restart`: an automatic restart (the struct gate, the rss gate, the manifest check's
    # leftover restart) must not drop the second-daemon opt-in the start was made with (A-0079 item 5)
    if [ "$second" = 1 ]; then : > "$DIR/second"; else rm -f "$DIR/second"; fi
    local julia slice
    julia="$(command -v julia)" || { echo "warm lane: no julia on PATH" >&2; return 1; }
    slice="$(_lk_slice)" || return 1                    # the shared budget (tools/lib_evidence.sh)
    local in_slice=()
    [ -n "$slice" ] && in_slice=(systemd-run --user --scope --quiet "$slice" -p MemorySwapMax=0)
    # PRECOMPILE the current source into the daemon's depot first — no daemon is running, so nothing
    # can refuse a rewritten cache — so `stale_load` starts from a cache that IS the source. Evidence
    # compiles elsewhere (the evidence depot), so this cache only aged: measured 2026-10-04, a start
    # revised 445 methods, and the static-analysis gate then saw each replaced one as unchecked.
    # (JULIA_DEPOT_PATH only when a copy has its own depot: an EMPTY value leaves Julia with no depot)
    local depot_env=()
    [ -n "${LOGICKERNEL_WARM_DEPOT:-}" ] &&
        depot_env=("JULIA_DEPOT_PATH=$LOGICKERNEL_WARM_DEPOT:$HOME/.julia:")
    (cd "$ROOT" && "${in_slice[@]}" env "${depot_env[@]}" \
        "$julia" --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) ||
        { echo "warm lane: LogicKernel does not precompile" >&2; return 1; }
    # the same ceiling and flags as tools/run_tests.sh. A service starts from systemd's own PATH, not
    # ours, so it gets ours — the swipl its differentials judge against; the daemon checks the pin.
    # A checkout COPY (parallel mutation proofs, user 2026-10-04) gives its daemon a depot of its own,
    # LOGICKERNEL_WARM_DEPOT, and a normal load: the original checkout's cache is not this copy's.
    local copy_env=()
    if [ -n "${LOGICKERNEL_WARM_DEPOT:-}" ]; then
        copy_env=(-E "JULIA_DEPOT_PATH=$LOGICKERNEL_WARM_DEPOT:$HOME/.julia:"
            -E LOGICKERNEL_WARM_NO_STALE_LOAD=1)
    fi
    # The UPSTREAM CHECKOUTS port_check reads (`LOGICKERNEL_UPSTREAM_<REPO>`, tools/port_check.jl) reach the
    # daemon too (2026-10-17): a unit gets only what is passed, so CI's daemon saw NO checkout — `inventory`
    # failed there ("the coverage block needs every upstream checkout the headers name") while every local
    # run passed — and a local daemon read ~/dev-zone's swipl-devel instead of the one the caller named.
    local _uv
    for _uv in $(compgen -e | grep '^LOGICKERNEL_UPSTREAM_' || :); do
        copy_env+=(-E "$_uv=${!_uv}")
    done
    # shellcheck disable=SC2086                          # $slice: empty without user systemd
    systemd-run --user --unit="$UNIT" --collect --quiet $slice -p MemoryMax="${LOGICKERNEL_TEST_MEM_MAX:-8G}" \
        -p MemorySwapMax=0 --working-directory="$ROOT" -E "PATH=$PATH" "${copy_env[@]}" \
        -E JULIA_REVISE=manual -E LOGICKERNEL_WARM_IDLE_S="${LOGICKERNEL_WARM_IDLE_S:-3600}" \
        /bin/bash -c "exec '$julia' --project=. --threads=\"\${JULIA_TEST_THREADS:-4}\" --heap-size-hint=${LOGICKERNEL_WARM_HEAP_HINT:-6G} tools/warm_session.jl >> '$DIR/session.log' 2>&1" ||
        { echo "warm lane: systemd-run failed" >&2; return 1; }
    local deadline=$(( $(date +%s) + ${WARM_START_TIMEOUT_S:-600} ))
    until [ -f "$DIR/ready" ]; do
        systemctl --user is-active --quiet "$UNIT" ||
            { echo "warm lane: the daemon died while starting — $DIR/session.log:" >&2; tail -20 "$DIR/session.log" >&2; return 1; }
        [ "$(date +%s)" -ge "$deadline" ] && { echo "warm lane: not ready after ${WARM_START_TIMEOUT_S:-600}s" >&2; return 1; }
        sleep 1
    done
    _struct_snapshot > "$DIR/structs"               # what this daemon loaded (`_struct_gate`)
    echo "warm lane: ready (unit $UNIT, pid $(cat "$DIR/ready"))"
}

_stop() {
    systemctl --user stop "$UNIT" 2>/dev/null
    rm -f "$DIR/ready"
    echo "warm lane: stopped"
}

# _restart — stop the daemon and start it again, AS A SECOND DAEMON when it was one (A-0079 item 5, D-0130
# item 2): a struct change restarts the daemon by itself, and a plain `_start` there found another checkout's
# daemon running, without the LOGICKERNEL_WARM_SECOND the user's `start` had carried, and REFUSED — the second
# lane died at its first changed struct. `.warm/second` (written by `_start`) is the memory; only a deliberate
# `stop` forgets it, and a plain `start` after a crash never reads it (the guard stays: one at a time).
_restart() {
    local second="${LOGICKERNEL_WARM_SECOND:-}"
    [ -f "$DIR/second" ] && second=1
    _stop
    LOGICKERNEL_WARM_SECOND="$second" _start
}

# THE DAEMON'S MEMORY (user, 2026-10-11). MEASURED that day: after eight runs of the static-analysis
# gate the daemon held 7.5 GB, and the evidence run that followed got two workers instead of three
# — its shard count is read from free memory — and took 33 min instead of about 25. So a gate
# cycle starts by reading the daemon's resident set: above LOGICKERNEL_WARM_RSS_MAX_GB (5) it is
# restarted, with the reason printed, "rss <n> GB > 5 GB". Every reading goes to .warm/rss.log —
# when, which gate, start or end, the size, kept or restarted — so the growth is on record: a
# daemon that grows WITHIN one run has a leak to find; the restart only keeps it from costing a
# worker meanwhile.
# _daemon_rss_kb — the daemon process's resident set in kB; 0 when it cannot be read
_daemon_rss_kb() {
    if [ -n "${LOGICKERNEL_WARM_RSS_FAKE_KB:-}" ]; then      # TEST SEAM (tools/test_warm.sh)
        echo "$LOGICKERNEL_WARM_RSS_FAKE_KB"
        return
    fi
    awk '/^VmRSS:/ {print $2; f = 1} END {if (!f) print 0}' \
        "/proc/$(cat "$DIR/ready" 2>/dev/null)/status" 2>/dev/null || echo 0
}
_gb() { awk -v kb="$1" 'BEGIN { printf "%.1f", kb / 1048576 }'; }
# _rss_log GATE WHEN KB ACTION — one line of the growth record (LOGICKERNEL_WARM_RSS_LOG: another
# file — the lane's own tests plant sizes, and those do not belong in the record)
_rss_log() {
    printf '%s\t%s\t%s\t%s GB\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" "$2" "$(_gb "$3")" "$4" \
        >> "${LOGICKERNEL_WARM_RSS_LOG:-$DIR/rss.log}"
}
# _rss_gate GATE — at a gate's start: log the daemon's size, and restart it when it is too big
_rss_gate() {
    _running || return 0
    local kb max
    kb="$(_daemon_rss_kb)"
    max="${LOGICKERNEL_WARM_RSS_MAX_GB:-5}"
    if awk -v kb="$kb" -v max="$max" 'BEGIN { exit !(kb > max * 1048576) }'; then
        echo "warm lane: restarting the daemon — rss $(_gb "$kb") GB > $max GB"
        _rss_log "$1" start "$kb" "restarted (rss $(_gb "$kb") GB > $max GB)"
        _restart > /dev/null || { echo "warm lane: the daemon did not restart" >&2; return 1; }
    else
        echo "warm lane: daemon rss $(_gb "$kb") GB (limit $max GB)"
        _rss_log "$1" start "$kb" kept
    fi
}

# THE STRUCT GATE (user, 2026-10-12). MEASURED twice that night (V9d): a field added to a struct
# (`choice`, then `PL_local_data`) left the daemon with a method compiled for the OLD type beside
# the one for the new — src/pl-op.jl's `defOperator!`, whose signature holds the type inside a
# `Union`, which Revise did not re-evaluate — and every call failed as AMBIGUOUS (`MethodError`).
# It was found by running the tests and reading the error, twice. So before a snippet is sent, the
# struct definitions of src/ — and its top-level CONSTS (2026-10-17: Revise does not re-evaluate a changed
# `const`; `const:<name>` in the snapshot) — are compared with the ones the daemon started from: a definition that
# CHANGED or went away restarts the daemon, the reason printed — "struct changed: <name>[,<name>…]"
# — and written to .warm/restart.log. A NEW struct restarts nothing (no method can be stale for
# it); nor does a comment or a blank inside one.
# _struct_snapshot — `name<TAB>hash` for every struct src/ defines, comments and layout left out
_struct_snapshot() { python3 "$ROOT/tools/struct_snapshot.py" "$ROOT/src"; }
# _struct_gate — before a snippet: restart the daemon when a struct it loaded has changed
_struct_gate() {
    _running || return 0
    local now changed
    now="$(_struct_snapshot)" && [ -n "$now" ] || {
        echo "warm lane: the struct snapshot failed (tools/struct_snapshot.py) — not sending" >&2
        return 1
    }
    if [ ! -f "$DIR/structs" ]; then                # a daemon started before this gate existed
        printf '%s\n' "$now" > "$DIR/structs"
        return 0
    fi
    [ "$now" = "$(cat "$DIR/structs")" ] && return 0
    # the names the daemon loaded whose definition is gone or different now
    changed="$(printf '%s\n' "$now" | awk -F'\t' 'NR == FNR { h[$1] = $2; next }
        !($1 in h) || h[$1] != $2 { print $1 }' - "$DIR/structs" | paste -sd, -)"
    if [ -z "$changed" ]; then                      # only new structs: nothing can be stale
        printf '%s\n' "$now" > "$DIR/structs"
        return 0
    fi
    echo "warm lane: restarting the daemon — struct changed: $changed" >&2
    printf '%s\tstruct changed: %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$changed" >> "$DIR/restart.log"
    _restart > /dev/null || {
        echo "warm lane: the daemon did not restart after a struct change — fix the load error, then tools/warm.sh start" >&2
        return 1
    }
}

# THE LANE LOCK (2026-10-07, after R1d). A RUN — preflight, evidence, or `locked CMD` (a mutation
# driver) — takes $DIR/run.lock EXCLUSIVELY for its whole run and exports WARM_LOCK_OWNER=<its pid>:
# its own subshells and child warm.sh calls inherit it and pass. Every other command takes the lock
# SHARED and non-blocking, so while a run holds the lane it is REFUSED (exit 5): a probe between a
# preflight's steps could define a method, load a file or trigger Revise, and a later step would test
# a daemon the preflight did not set up. Plain senders still queue among themselves, per snippet
# (`_send`'s own lock). The marker counts only for the run that holds the lane NOW (its pid in
# run.owner, alive, and the lock held): a stale or inherited one bypasses nothing.
_lane_owned() {
    [ -n "${WARM_LOCK_OWNER:-}" ] && [ "$(cat "$DIR/run.owner" 2>/dev/null)" = "$WARM_LOCK_OWNER" ] &&
        kill -0 "$WARM_LOCK_OWNER" 2>/dev/null && ! flock -n -s "$DIR/run.lock" true 2>/dev/null
}

# _run_lock — take the lane for this whole run; 5 when another run keeps it past WARM_RUN_LOCK_WAIT_S.
_run_lock() {
    _lane_owned && return 0                             # a run inside our own run
    mkdir -p "$DIR"
    exec 8>"$DIR/run.lock"
    if ! flock -w "${WARM_RUN_LOCK_WAIT_S:-120}" 8; then
        echo "warm lane: REFUSED — another run holds the lane (pid $(cat "$DIR/run.owner" 2>/dev/null || echo '?')): a preflight, an evidence or a mutation run must have it alone (exit 5)" >&2
        return 5
    fi
    echo "$$" > "$DIR/run.owner"
    export WARM_LOCK_OWNER=$$
}

# _lane_check — a command outside any run: refused (5) while a run holds the lane.
_lane_check() {
    _lane_owned && return 0
    mkdir -p "$DIR"
    exec 8>"$DIR/run.lock"
    flock -n -s 8 && return 0
    echo "warm lane: REFUSED — a run holds the lane (pid $(cat "$DIR/run.owner" 2>/dev/null || echo '?')): a preflight, an evidence or a mutation run; a probe now would change the daemon under it (exit 5)" >&2
    return 5
}

# THE CLIENT'S TIMEOUT per send (audit D-0206 item 4b, 2026-10-29): 1800 s for any snippet, and 3600 s for a
# `file` run of test/test_static_analysis.jl ALONE — SSU1 measured that file at 32 min (JET + Aqua + AllocCheck),
# past the 1800 s default, so a green run was reported as a TIMEOUT. An explicit WARM_TIMEOUT_S still wins
# (tools/mutate_drive.py sets one per mutant). `_file_timeout` is the one place the two numbers live;
# test/test_gate_split.jl fails when the static file's drops back.
WARM_DEFAULT_TIMEOUT_S=1800
WARM_STATIC_TIMEOUT_S=3600
# _file_timeout ABSPATH — the seconds a send of this test file may take
_file_timeout() {
    if [ -n "${WARM_TIMEOUT_S:-}" ]; then echo "$WARM_TIMEOUT_S"; return; fi
    case "$1" in
        "$ROOT"/test/test_static_analysis.jl) echo "$WARM_STATIC_TIMEOUT_S" ;;
        *) echo "$WARM_DEFAULT_TIMEOUT_S" ;;
    esac
}

# _send FILE — run the snippet in the daemon; print its output; exit with its verdict.
_send() {
    # TEST SEAM (test/test_gate_split.jl): print the timeout this send would run under, send nothing — the
    # timeout of a `file` run is judged WITHOUT a daemon (and without running the file)
    if [ "${LOGICKERNEL_WARM_SEND_PROBE:-}" = 1 ]; then
        echo "send: timeout ${WARM_TIMEOUT_S:-$WARM_DEFAULT_TIMEOUT_S}s"
        return 0
    fi
    _running || { echo "warm lane: not running — tools/warm.sh start" >&2; return 3; }
    _struct_gate || return 3
    # ONE SNIPPET AT A TIME. Two senders race on in.jl, seq and out.txt, and one of them can read
    # the other's verdict: MEASURED 2026-10-07 (R1d), a probe sent during a preflight made the
    # preflight's test_read_term_swipl.jl step "pass" with an EMPTY log, its run never made. The
    # lock covers ONE snippet — write, wait, read its verdict — in a subshell that holds fd 9, and
    # is released when it exits. NOT for a whole process: a lock kept by the process (the first
    # version) deadlocked the preflight's own rerun, which sends from a SUBSHELL, against its parent.
    (
        flock 9
        seq=$(( $(cat "$DIR/seq" 2>/dev/null || echo 0) + 1 ))
        cat "${1:-/dev/stdin}" > "$DIR/in.jl"
        rm -f "$DIR/status"                       # never inherit the previous run's verdict
        echo "$seq" > "$DIR/seq"
        deadline=$(( $(date +%s) + ${WARM_TIMEOUT_S:-$WARM_DEFAULT_TIMEOUT_S} ))
        while [ "$(cat "$DIR/done" 2>/dev/null)" != "$seq" ]; do
            if ! systemctl --user is-active --quiet "$UNIT"; then
                echo "warm lane: the daemon DIED during seq=$seq — $DIR/session.log" >&2; exit 2
            fi
            if [ "$(date +%s)" -ge "$deadline" ]; then
                echo "warm lane: TIMEOUT after ${WARM_TIMEOUT_S:-$WARM_DEFAULT_TIMEOUT_S}s on seq=$seq — it may still be running;" >&2
                echo "           output NOT printed (it would be the previous run's)" >&2
                exit 2
            fi
            sleep 0.2
        done
        cat "$DIR/out.txt"
        exit "$(cat "$DIR/status" 2>/dev/null || echo 1)"     # a missing verdict is a FAILURE
    ) 9>"$DIR/send.lock"
}

# _file PATH [IMPL] — one test file in a fresh module, as test/runtests.jl runs it.
_file() {
    local f="$1" impl="${2:-}"
    case "$f" in /*) ;; *) f="$ROOT/$f" ;; esac
    [ -f "$f" ] || { echo "warm lane: no such file: $f" >&2; return 2; }
    local impls='("",)'
    if grep -qE '^include\(joinpath\(@__DIR__, "\.\.", "term_under_test\.jl"\)\)' "$f"; then
        impls='("reference", "alt", "alt_interned")'
        [ -n "$impl" ] && impls="(\"$impl\",)"
    elif [ -n "$impl" ] && [ "$impl" != reference ]; then
        # (user, 2026-10-16) a non-generic file has ONE run, on the reference type: an alternative
        # type asked for it was dropped without a word — the run claimed a type it never used
        echo "warm lane: $f is not term-generic (it does not include ../term_under_test.jl as test/term_scope.jl reads it): a '$impl' run is impossible — it would run on the reference type only (exit 2)" >&2
        return 2
    fi
    local snippet="$DIR/file_snippet.jl" out="$DIR/file_out.$$" rc
    # (2026-10-17, audit D-0001) LOGICKERNEL_NO_SWIPL=1: the file runs as CI's Pkg.test runs it, without swipl
    # (every test file's swipl check yields nothing then), swipl not required, and with the suite's
    # inert-testset guard — a testset that asserts only inside its swipl branch asserts NOTHING there, and
    # stopped Pkg.test twice that night while every warm run passed
    local swenv='"LOGICKERNEL_REQUIRE_SWIPL" => "1"' inert=""
    if [ "${LOGICKERNEL_NO_SWIPL:-}" = 1 ]; then
        swenv='"LOGICKERNEL_NO_SWIPL" => "1", "LOGICKERNEL_REQUIRE_SWIPL" => nothing'
        inert="let g = Module(:WarmInertGuard)
        Base.include(g, raw\"$ROOT/test/inert_testset_guard.jl\")
        Base.invokelatest(g.assert_no_inert_testsets, ts)
    end"
        echo "warm lane: $f WITHOUT swipl (LOGICKERNEL_NO_SWIPL=1), the inert-testset guard on" >&2
    fi
    cat > "$snippet" <<JL
let f = raw"$f", ts = Test.DefaultTestSet("warm: " * basename(f); verbose=true)
    Test.@with_testset ts begin
        for impl in $impls
            label = isempty(impl) ? basename(f) : "\$(basename(f)) [\$impl]"
            @testset "\$label" begin
                m = Core.eval(Main, Expr(:module, true, gensym(:LKWarm), Expr(:block)))
                env = Pair{String, Any}[$swenv]
                isempty(impl) || push!(env, "LOGICKERNEL_TERM" => impl)
                withenv(() -> Base.include(m, f), env...)
                # as test/runtests.jl closes every unit: the leaves' ONE shared empty child vector is still
                # empty (a test that pushed to it fails the unit in Pkg.test, and passed a warm run)
                @test isempty(LogicKernel._no_children(LogicKernel.DefaultTerm))
            end
        end
    end
    $inert
    Test.finish(ts)                          # throws on any failure or error: the verdict
end
JL
    WARM_TIMEOUT_S="$(_file_timeout "$f")" _send "$snippet" > "$out" 2>&1
    rc=$?
    case "${LOGICKERNEL_WARM_FAULT:-}" in                          # TEST SEAMS (tools/test_warm.sh)
        empty) : > "$out" ;;                                        # a lost run: nothing at all
        cut) head -n 1 "$out" > "$out.cut" && mv "$out.cut" "$out" ;;   # a run cut off early
    esac
    cat "$out"
    # FAIL CLOSED: a pass must SHOW its verdict — the summary line Test.finish prints for this file.
    # An empty or truncated output is NO VERDICT, whatever the exit code (exit 4): MEASURED
    # 2026-10-07 (R1d), a probe sent during a preflight left a step with an EMPTY log and exit 0. The
    # lock in _send fixes that cause; this check stops any other (a crash, a killed process).
    if [ "$rc" -eq 0 ] && ! _verdict_in "$out" "^warm: $(basename "$f") +\\|"; then
        echo "warm lane: NO VERDICT — the output for $(basename "$f") is empty or lacks its test summary; a FAILURE (exit 4)" >&2
        rc=4
    fi
    rm -f "$out"
    return "$rc"
}

# _verdict_in FILE PATTERN — FILE is non-empty and holds a line matching PATTERN (grep -E): a step's
# own end marker, without which its exit code is not taken as a pass.
_verdict_in() { [ -s "$1" ] && grep -qE "$2" "$1"; }

_bench() {
    # --ungated: the daemon is a julia process tools/bench.sh's start gate would refuse; the
    # report says UNGATED in its header (a warm run is for iteration, tools/bench.sh for numbers)
    local snippet="$DIR/bench_snippet.jl" args="\"--ungated\", "
    for a in "$@"; do args+="\"$a\", "; done
    cat > "$snippet" <<JL
let m = Core.eval(Main, Expr(:module, true, gensym(:LKBench), Expr(:block)))
    empty!(ARGS); append!(ARGS, String[$args])
    Base.include(m, raw"$ROOT/tools/bench.jl")
end
JL
    _send "$snippet"
}

# _pool — pre-warm the evidence workers (tools/worker.jl) for the CURRENT tree: fresh processes that
# have loaded LogicKernel and the analysis tools and run nothing. tools/run_tests.sh uses them only
# if the tree is still the one they started with; workers for another tree are discarded here.
_pool() {
    local n fp k w u
    n=$(_shard_count)
    fp="$(_tree_fp "$ROOT")"
    mkdir -p "$DIR/pool"
    for w in "$DIR"/pool/w*; do
        [ -d "$w" ] || continue
        # another tree, claimed, or DEAD (a reboot leaves `ready` and a matching `fp` behind)
        if [ "$(cat "$w/fp" 2>/dev/null)" != "$fp" ] || [ -d "$w/claimed" ] ||
            { [ -f "$w/unit" ] && ! _unit_active "$(cat "$w/unit")"; }; then
            systemctl --user stop "$(cat "$w/unit" 2>/dev/null)" 2>/dev/null
            rm -rf "$w"
        fi
    done
    (cd "$ROOT" && JULIA_DEPOT_PATH="$(_evidence_depot_path "$ROOT")" \
        julia --project=. --startup-file=no -e 'using LogicKernel' < /dev/null) || return 1
    _oracle_env "$ROOT" "$(_oracle_pool_stats "$ROOT")"   # the workers consult the oracle cache too
    for k in $(seq 1 "$n"); do
        w="$DIR/pool/w$k"
        [ -f "$w/fp" ] && continue                       # already warming for this tree
        u="lk-pool-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)-$k"
        systemctl --user stop "$u" 2>/dev/null
        _spawn_worker "$ROOT" "$w" "$fp" "$u" || return 1
        echo "$u" > "$w/unit"
    done
    echo "pool: $n workers warming for tree ${fp:0:12} — tools/run_tests.sh uses them while the tree is unchanged"
}

# _checks_fresh — `_format_port_check`, and once more on a FRESH daemon when the first run found
# DAEMON LEFTOVERS (user, 2026-10-14: a restart costs less than a failed 13-minute preflight).
# ROOT CAUSE of the leftovers L1a-1 lost two preflights to, FOUND and FIXED the same day: Revise
# DOES delete the old method of a re-signed function, but the gate's live-method filter
# (test/static_analysis_gates.jl `_current_method`) counted a deleted method as live. What this
# still catches is a method Revise genuinely failed to delete (the documented suspect: a precompile
# in another process rewriting the cache it diffs against, tools/warm_session.jl). Logged.
_checks_fresh() {
    local rc ts mt ic
    _term_scopes_check                     # first, and the others run anyway: one run names every failure
    ts=$?
    _meta_check
    mt=$?
    _inert_check "${LOGICKERNEL_INERT_BUDGET_S:-120}"
    ic=$?
    _format_port_check
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q 'A DAEMON LEFTOVER' "$DIR/preflight_format_port_check.log" 2> /dev/null; then
        echo "check: DAEMON LEFTOVERS (old signatures of re-signed functions) — restarting the warm lane once, then checking again"
        echo "$(date -u +%FT%TZ) restart: daemon leftovers found by the manifest check" >> "$DIR/restarts.log"
        _restart > /dev/null || return 1
        _format_port_check 1
        rc=$?
        [ "$rc" -eq 0 ] || echo "check: still FAILS after a daemon restart — a REAL failure (the method needs its manifest entry)"
    fi
    [ "$rc" -eq 0 ] || return "$rc"
    [ "$ts" -eq 0 ] || return "$ts"
    [ "$mt" -eq 0 ] || return "$mt"
    return "$ic"
}

# THE CI-ONLY CHECKS THAT ARE CHEAP (audit D-0214 finding 1, 2026-10-29): two classes of CI red in two days were
# checks a warm run never made. The list of every check CI runs and `check`/`branch-gate` did not, with what moved
# here and why each other stays in CI: evidence/TOOL-TS/handoff.md (the A-entry). Moved: the term-scope
# declarations (_term_scopes_check, above), the tree-wide meta test files (_meta_check), the inert-testset guard
# without swipl on the changed test files (_inert_check), the closing assertion of every unit (_file), CI's
# formatter pin (_format_port_check) and the tooling job's trigger files (_branch_gate_files).
#
# _meta_check — the package-level test files Pkg.test runs and the branch-gate's tree-wide list did not:
# test/test_package.jl (every package a test file loads is declared for Pkg.test: "an undeclared stdlib resolves
# here and fails only in CI", measured twice), the commit-message hook's contract, the JUnit writer. Seconds each;
# every run records its time (`_record_file_time`) so a file that grows past a minute is seen and moved out of
# WARM_META_FILES (LOGICKERNEL_META_FILES: a TEST SEAM, test/test_gate_split.jl). 0 only if at least one ran.
WARM_META_FILES="test/test_package.jl test/test_commit_msg_hook.jl test/test_junit_report.jl"
_meta_check() {
    local f log t0 rc=0 n=0 files="${LOGICKERNEL_META_FILES-$WARM_META_FILES}"
    for f in $files; do
        if [ ! -f "$ROOT/$f" ]; then
            echo "preflight: meta test file $f is listed in tools/warm.sh and does not exist"
            rc=1
            continue
        fi
        log="$DIR/check_meta_$(basename "$f" .jl).log"
        t0=$(date +%s)
        _file "$f" reference > "$log" 2>&1 || {
            rc=1
            echo "preflight: meta test file FAILED — $f ($log)"
            grep -E "Test Failed|Error During|NO VERDICT" "$log"
        }
        _record_file_time "$f" "$(( $(date +%s) - t0 ))"
        n=$(( n + 1 ))
    done
    if [ "$n" -eq 0 ]; then
        echo "preflight: no meta test file ran — nothing was checked"
        return 1
    fi
    [ "$rc" -ne 0 ] || echo "preflight: meta test files pass ($n files)"
    return "$rc"
}

# _inert_check [BUDGET_S] — each changed test file run THE WAY Pkg.test RUNS IT (audit D-0214 1, D-0222): a fresh
# julia (tools/pkgtest_way.sh) with LOGICKERNEL_NO_SWIPL=1, stdin from /dev/null, stdout and stderr to pipes, and
# test/inert_testset_guard.jl over the result. A warm run has swipl and the daemon's stdio, so three reds were CI-only:
# a testset asserting nothing without swipl (SSU2 ca51c2a), a table empty without swipl and `Suser_output(ld)` no
# IOSTREAM under redirected stdio (S1's test_open_close_swipl.jl). A cold process compiles, so the estimate is the file's
# last recorded warm time (20 s for a file with none, LOGICKERNEL_INERT_DEFAULT_S) times LOGICKERNEL_INERT_FACTOR (3):
# over the budget the files are named and left to the branch-gate, which raises the budget (LOGICKERNEL_INERT_BUDGET_S).
# One file at a time, so at most one extra julia beside the daemons. LOGICKERNEL_INERT_FILES replaces the
# changed-file list: a TEST SEAM.
# MEMORY (audit D-0242 item 2, A-0148): each run is its OWN scope, MemoryMax 3G (LOGICKERNEL_INERT_MEM_MAX), NESTED in
# this checkout's lane slice (`_lane_slice`), run after the previous one and never beside the daemon's own file run
# (these steps are sequential in one warm.sh process, which holds or respects the lane); a runaway test process is
# killed and named, not the daemon. Each run's PEAK memory goes to the log (stdout, so into the branch-gate's).
WARM_INERT_SKIP="test/test_static_analysis.jl test/test_gate_split.jl test/test_port_check.jl"
# _lane_slice — the slice this checkout's daemon runs in (the second daemon's is lk-warm2.slice, `_start`); nothing
# where the shared budget is off (CI) or user systemd is missing
_lane_slice() {
    _lk_budget_on || return 0
    systemctl --user show-environment > /dev/null 2>&1 || return 0
    if [ -n "${LOGICKERNEL_SLICE:-}" ]; then echo "$LOGICKERNEL_SLICE"
    elif [ -f "$DIR/second" ]; then echo lk-warm2.slice
    else echo lk-warm.slice; fi
}
_inert_check() {
    local budget="${1:-120}" files f est=0 rc=0 prc n=0 log factor="${LOGICKERNEL_INERT_FACTOR:-3}"
    if [ -n "${LOGICKERNEL_INERT_FILES+x}" ]; then
        files="$LOGICKERNEL_INERT_FILES"
    else
        files=$(_changed_files | grep -E '^test/(.*/)?test_[^/]*\.jl$')
    fi
    # never here: the static-analysis file (Evidence's shards run it, D-0220) and the tooling test files, whose
    # fixtures start worktrees and shells for minutes and depend on neither swipl nor the process's stdio
    # (test_gate_split.jl, test_port_check.jl: the branch-gate runs them warm, CI's tooling job as a whole)
    files=$(for f in $files; do
        case " $WARM_INERT_SKIP " in *" $f "*) continue ;; esac
        [ -f "$ROOT/$f" ] && echo "$f"
    done)
    if [ -z "$files" ]; then
        echo "preflight: Pkg.test-way run: no changed test file"
        return 0
    fi
    for f in $files; do est=$(( est + factor * $(LOGICKERNEL_BRANCH_GATE_DEFAULT_S="${LOGICKERNEL_INERT_DEFAULT_S:-20}" _file_time "$f") )); done
    if [ "$est" -gt "$budget" ]; then
        echo "preflight: Pkg.test-way run: over budget (estimate ${est}s > ${budget}s) — left to the branch-gate:"
        printf '  %s\n' $files
        return 0
    fi
    for f in $files; do
        log="$DIR/check_inert_$(basename "$f" .jl).log"
        LOGICKERNEL_INERT_SLICE="$(_lane_slice)" "$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1
        prc=$?                                   # one run at a time: the next starts when this one has ended
        grep -h '^pkgtest_way: .* peak ' "$log"  # each process's PEAK memory, pass or fail: the branch-gate log carries it
        if [ "$prc" -ne 0 ]; then
            rc=1
            echo "preflight: Pkg.test-way run FAILED — $f ($log)"
            # the file's own failure lines first (pkgtest_way.sh), then the exception; a KILLED run names its cap
            grep -v '^pkgtest_way: .* peak ' "$log" | head -n 60
        fi
        n=$(( n + 1 ))
    done
    [ "$rc" -ne 0 ] || echo "preflight: Pkg.test-way run clean ($n changed test files: no swipl, stdio pipes, inert guard)"
    return "$rc"
}

# _term_scopes_check — test/term_scope.jl's `# TERM TYPES PER CHUNK:` declarations of every term-generic test
# file, judged HERE as Pkg.test judges them in CI (audit D-0206 item 4a; BLOB's test_blob.jl named no src/
# file, passed the branch-gate, failed CI — A-0140). tools/term_scopes_check.jl calls the runner's own
# extractor; 0 only when its pass line was SHOWN (fail closed, as _format_port_check). LOGICKERNEL_TERM_SCOPES_ROOT
# (a planted tree) and LOGICKERNEL_TERM_SCOPES_COLD=1 (a plain julia process in place of the daemon: the
# snippet needs Base only) are TEST SEAMS (test/test_gate_split.jl).
_term_scopes_check() {
    local rc root="${LOGICKERNEL_TERM_SCOPES_ROOT:-$ROOT}" snippet="$DIR/term_scopes_snippet.jl" log="$DIR/preflight_term_scopes.log"
    mkdir -p "$DIR"
    cat > "$snippet" <<JL
let m = Module(:PreflightTermScopes)
    Base.include(m, raw"$ROOT/tools/term_scopes_check.jl")
    try
        println(Base.invokelatest(() -> m.term_scopes_check(raw"$root")))
    catch e
        println("preflight: TERM SCOPES INVALID — ", e isa ErrorException ? e.msg : sprint(showerror, e))
        rethrow()
    end
end
JL
    if [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" = 1 ]; then
        julia --startup-file=no "$snippet" > "$log" 2>&1 < /dev/null
    else
        _send "$snippet" > "$log" 2>&1
    fi
    rc=$?
    case "${LOGICKERNEL_PREFLIGHT_FAULT:-}" in                     # TEST SEAMS (test/test_gate_split.jl)
        scopes-empty) : > "$log" ;;
        scopes-cut) grep -v '^preflight: term scopes valid' "$log" > "$log.cut"; mv "$log.cut" "$log" ;;
    esac
    cat "$log"
    if [ "$rc" -eq 0 ] && ! _verdict_in "$log" '^preflight: term scopes valid'; then
        echo "preflight: NO VERDICT — the term-scopes output is empty or lacks its pass line"
        rc=4
    fi
    return "$rc"
}

# _format_port_check — the formatter (as CI's Format job checks it) and port_check, in the warm
# daemon: the preflight's first step, and `tools/warm.sh check` on its own (user, 2026-10-13: a
# documentation slip is then found seconds after the edit, without starting a preflight). Prints
# both pass lines; 0 only when both were SHOWN (fail closed).
# _fmt_pin — the JuliaFormatter version CI.yml's Format job installs (one value, or nothing)
_fmt_pin() {
    local p
    p=$(grep -hoE 'name="JuliaFormatter", version="[0-9]+\.[0-9]+\.[0-9]+"' "$ROOT"/.github/workflows/CI.yml 2> /dev/null |
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)
    [ "$(printf '%s\n' "$p" | grep -c .)" -eq 1 ] && printf '%s\n' "$p"
}
_format_port_check() {   # _format_port_check [1 = the check after a leftover restart]
    local rc snippet="$DIR/preflight_snippet.jl" fmtlog="$DIR/preflight_format_port_check.log"
    local after_restart="${1:-0}" fmt_pin
    fmt_pin="$(_fmt_pin)"
    cat > "$snippet" <<JL
using JuliaFormatter
# CI's Format job installs ONE pinned JuliaFormatter (tools/run_tests.sh refuses another too): a daemon
# with another version formats differently, and a file its check passes fails CI's (audit D-0214 1)
let pin = raw"$fmt_pin", have = string(pkgversion(JuliaFormatter))
    isempty(pin) && error("preflight: no single JuliaFormatter version is pinned in .github/workflows/CI.yml")
    have == pin || error("preflight: JuliaFormatter ", have, " in the daemon, CI pins ", pin)
end
if !format("."; overwrite=false)
    bad = String[]
    for (dir, dirs, files) in walkdir(".")
        filter!(d -> !(d in (".git", ".warm", ".evidence", "build")), dirs)
        for f in files
            endswith(f, ".jl") && !format(joinpath(dir, f); overwrite=false) &&
                push!(bad, joinpath(dir, f))
        end
    end
    error("preflight: NOT Blue-formatted: ", join(bad, ", "), " — tools/run_tests.sh shows each diff")
end
println("preflight: Blue-clean (JuliaFormatter ", pkgversion(JuliaFormatter), ")")
# the CURRENT tools/port_check.jl, in a fresh module every time: a daemon that kept the first one
# it loaded would check an edited tree with an old checker (measured 2026-10-04: M1's own docs were
# held to the pre-M1 inventory format)
let pc = Module(:PreflightPortCheck)
    Base.include(pc, raw"$ROOT/tools/port_check.jl")
    r = Base.invokelatest(() -> pc.port_check(raw"$ROOT"))   # the binding too: latest world
    foreach(x -> println("  ", x), r.violations)
    isempty(r.violations) || error("preflight: port_check found violations")
    mk = r.markers                                     # the gate split of markers (user, 2026-10-06)
    println("preflight: port_check clean (", length(r.files), " files; markers: ", mk.diverges,
        " DIVERGES, ", mk.not_ported, " NOT PORTED, ", mk.both, " DIVERGES lines still saying NOT PORTED)")
end
# THE MANIFEST, in seconds (user, 2026-10-14): every entry of test/static_analysis_manifest.jl names
# exactly one method (which), and every method LogicKernel defines is reached by an entry or
# exempted — the static-analysis gate's coverage test, without JET, so a new or re-signed function
# without its entry fails HERE, not after ~13 minutes of analysis (V9g-a, L1a-1). Fresh module,
# current files, every time.
let sa = Module(:PreflightManifest)
    Core.eval(sa, :(using LogicKernel))
    Base.include(sa, raw"$ROOT/test/static_analysis_gates.jl")
    Base.include(sa, raw"$ROOT/test/static_analysis_manifest.jl")
    entries = Base.invokelatest(() -> sa.DISPATCH_MANIFEST)
    exempt = Base.invokelatest(() -> sa.DISPATCH_EXEMPT)
    stale = String[]
    for (f, tt, _) in entries
        try
            which(f, tt)
        catch
            push!(stale, string(f, tt))
        end
    end
    foreach(x -> println("  NO SUCH METHOD (stale manifest entry): ", x), stale)
    isempty(stale) || error("preflight: the manifest names methods that do not exist")
    r = Base.invokelatest(() -> sa.manifest_uncovered(LogicKernel, entries, exempt))
    # An uncovered method at the file and line of ANOTHER live method of the same function is the
    # old signature of a re-signed function that Revise failed to delete: no manifest entry fixes
    # it, a restart does (_checks_fresh, in tools/warm.sh).
    owned = Base.invokelatest(() -> sa.owned_methods(LogicKernel))
    # ...and so is a method whose function NO src/ file defines (the static gate's STALE rule,
    # _preflight_stale: port_check's own definitions): Revise kept it after its definition was
    # deleted (FIXED 2026-10-14 — it read NOT IN THE MANIFEST and nothing restarted the daemon).
    # After that one restart, whatever is still uncovered is REAL: it needs its manifest entry.
    pcd = Module(:PreflightManifestDefs)
    Base.include(pcd, raw"$ROOT/tools/port_check.jl")
    defined = Set{String}()
    for (dir, _, fs) in walkdir(raw"$ROOT/src"), f in fs
        endswith(f, ".jl") || continue
        p = joinpath(dir, f)
        foreach(d -> push!(defined, d[2]), Base.invokelatest(() -> pcd.definitions(read(p, String), p)))
    end
    isempty(defined) && error("preflight: no definitions found under src/ — cannot classify")
    resigned = Set(
        "\$(m.name) \$(m.sig)  (\$(m.file):\$(m.line))" for m in owned if
        count(n -> n.name === m.name && n.file === m.file && n.line == m.line, owned) > 1
    )
    deleted = Set(
        "\$(m.name) \$(m.sig)  (\$(m.file):\$(m.line))" for m in owned if !(String(m.name) in defined)
    )
    for u in r.uncovered
        println($after_restart == 1 ?
                "  NOT IN THE MANIFEST (still there after a daemon restart — a REAL method: add its entry): " :
            u in resigned ? "  A DAEMON LEFTOVER (the old signature of a re-signed function — " *
                            "tools/warm.sh restart, with its reason): " :
            u in deleted ? "  A DAEMON LEFTOVER (defined in no src/ file — a method Revise kept): " :
            "  NOT IN THE MANIFEST: ", u)
    end
    foreach(u -> println("  stale exemption: ", u), r.stale_exempt)
    (isempty(r.uncovered) && isempty(r.stale_exempt)) ||
        error("preflight: the manifest does not cover LogicKernel (test/static_analysis_manifest.jl)")
    println("preflight: manifest covers every method (", length(entries), " entries)")
end
JL
    _send "$snippet" > "$fmtlog" 2>&1
    rc=$?
    case "${LOGICKERNEL_PREFLIGHT_FAULT:-}" in                     # TEST SEAMS (tools/test_warm.sh)
        format-empty) : > "$fmtlog" ;;
        format-cut) grep -v '^preflight: port_check clean' "$fmtlog" > "$fmtlog.cut"; mv "$fmtlog.cut" "$fmtlog" ;;
    esac
    cat "$fmtlog"
    # FAIL CLOSED (see _file): both checks must SHOW their pass lines, or the step failed
    if [ "$rc" -eq 0 ] && { ! _verdict_in "$fmtlog" '^preflight: Blue-clean' ||
        ! _verdict_in "$fmtlog" '^preflight: port_check clean' ||
        ! _verdict_in "$fmtlog" '^preflight: manifest covers every method'; }; then
        echo "preflight: NO VERDICT — the format/port_check/manifest output is empty or lacks its pass lines"
        rc=4
    fi
    return "$rc"
}

# _preflight — what a full run would fail on, checked WARM before the cold evidence run (user,
# 2026-10-04: "do not waste time on cold starts .. make use of possible solutions to run warm").
# MEASURED that day: two of three cold runs (~11 min each) failed on port_check and on JET — each
# answer this gives in about a minute. Fast checks first, failing fast: Blue formatting (as
# run_tests.sh and CI check it) and port_check. Then, while the evidence workers pre-warm for this
# tree (`pool`, in the evidence depot, so the daemon's cache is untouched): the static-analysis gate
# (JET/Aqua/AllocCheck — ~26 s warm, against ~200 s in a cold worker) and every test file changed
# since HEAD, on every implementation. Exit 0 only if all of it passed; the cold run that follows is
# then the evidence, and starts from loaded workers. LOGICKERNEL_PREFLIGHT_POOL=0 skips the pool.
_preflight_once() {
    _running || _start > /dev/null || return 1
    local t0 rc=0 f files pooled=""
    PF_SA_FAIL=0 PF_OTHER_FAIL=0                       # which steps failed, for _preflight
    t0=$(date +%s)
    # THE GATE SPLIT'S CONDITION (user, 2026-10-06): a gate cycle starts by reading the previous
    # push's CI — red, or unreadable, stops it here (tools/lib_evidence.sh `_ci_gate`)
    _ci_gate "$ROOT" 0 || {
        PF_OTHER_FAIL=1
        echo "preflight: FAIL — the previous push's CI (tools/ci_status.sh)"
        return 1
    }
    _checks_fresh
    rc=$?
    [ "$rc" -eq 0 ] || {
        PF_OTHER_FAIL=1
        echo "preflight: FAIL (format/port_check/manifest/term scopes/meta/inert) in $(( $(date +%s) - t0 ))s"
        return 1
    }
    # THE FAST STATIC PRE-CHECK (user, 2026-10-12): Aqua and JET's report_package alone, in the warm
    # daemon, BEFORE the long stages — a JET error cost a 14-minute preflight on V9e-1. The long
    # stages (and the pool's workers) start only if both are clean.
    echo "preflight: the fast static pre-check (Aqua, JET report_package)"
    local fastlog="$DIR/preflight_static_fast.log"
    _file test/static_analysis_fast.jl > "$fastlog" 2>&1 || {
        PF_OTHER_FAIL=1
        grep -E "Test Failed|Error During|JET-test failed|Aqua|ambigu|no matching method|possible error" "$fastlog" | head -20
        echo "preflight: FAIL (fast static pre-check) in $(( $(date +%s) - t0 ))s — $fastlog"
        return 1
    }
    echo "preflight: fast static pre-check clean in $(( $(date +%s) - t0 ))s"
    if [ "${LOGICKERNEL_PREFLIGHT_POOL:-1}" != "0" ]; then
        _pool > "$DIR/preflight_pool.log" 2>&1 &
        pooled=$!
    fi
    echo "preflight: the static-analysis gate"
    local log="$DIR/preflight_test_static_analysis.log"
    if [ "${LOGICKERNEL_PREFLIGHT_STUB_STATIC:-}" = 1 ]; then       # TEST SEAM (tools/test_warm.sh)
        # (user, 2026-10-16) the tooling tests check the preflight's LOGIC, not JET's verdict on the
        # engine: the full file is 25–28 min on a daemon started cold, ~2 min warm — the same case
        # passed or failed on the daemon's warmth, and ran past the send's 1800 s that afternoon.
        # The fast pre-check above stays real; the full file is the pre-push step. No marker (below).
        echo "preflight: test/test_static_analysis.jl STUBBED (LOGICKERNEL_PREFLIGHT_STUB_STATIC: the tooling tests only) — no evidence"
    else
        _file test/test_static_analysis.jl > "$log" 2>&1 || { rc=1; PF_SA_FAIL=1; echo "preflight: FAILED — $log"; }
        grep -E "\.jl \[|\.jl  *\||Test Failed|Error During|NOT CHECKED|allocates:" "$log"
    fi
    # The TREE-WIDE gates run on every preflight, changed or not: they check src/, so a src edit can
    # fail them while their own file is unchanged (V4a, MEASURED: an `@inbounds` in pl-inline.jl
    # passed the preflight and failed test_type_discipline.jl in the cold evidence run).
    files=$( {
        printf '%s\n' test/test_type_discipline.jl test/test_lint_globals.jl
        _changed_files | grep -E '^test/(.*/)?test_[^/]*\.jl$'
    } | sort -u)
    for f in $files; do
        [ -f "$ROOT/$f" ] && [ "$f" != test/test_static_analysis.jl ] || continue
        echo "preflight: $f"
        log="$DIR/preflight_$(basename "$f" .jl).log"
        _file "$f" > "$log" 2>&1 || { rc=1; PF_OTHER_FAIL=1; echo "preflight: FAILED — $log"; }
        grep -E "\.jl \[|\.jl  *\||Test Failed|Error During" "$log"
    done
    if [ -n "$pooled" ]; then
        wait "$pooled" || echo "preflight: the pool did not start — $DIR/preflight_pool.log"
        tail -1 "$DIR/preflight_pool.log"
    fi
    echo "preflight: $([ "$rc" -eq 0 ] && echo PASS || echo FAIL) in $(( $(date +%s) - t0 ))s"
    return "$rc"
}

# _preflight_stale LOG — classify each method the static-analysis gate reported NOT CHECKED in LOG:
# `STALE name` when no file under src/ defines that name any more (port_check's `definitions`, read
# from the SYNTAX TREE, not by grep), `REAL name` otherwise. Errors when src/ yields no definitions at
# all: an empty set would call every method stale.
_preflight_stale() {
    local snippet="$DIR/preflight_stale.jl"
    cat > "$snippet" <<JL
let pc = Module(:PreflightStale), log = read(raw"$1", String)
    Base.include(pc, raw"$ROOT/tools/port_check.jl")         # the current one (see above)
    names = unique([String(m[1]) for m in eachmatch(r"NOT CHECKED for dispatch: (\S+)", log)])
    defined = Set{String}()
    for (dir, _, fs) in walkdir(raw"$ROOT/src"), f in fs
        endswith(f, ".jl") || continue
        p = joinpath(dir, f)
        foreach(d -> push!(defined, d[2]), Base.invokelatest(() -> pc.definitions(read(p, String), p)))
    end
    isempty(defined) && error("preflight: no definitions found under src/ — cannot classify")
    foreach(n -> println(n in defined ? "REAL " : "STALE ", n), names)
end
JL
    _send "$snippet" | grep -E '^(REAL|STALE) '
}

# _preflight — _preflight_once, RECOVERING from a stale daemon (user, 2026-10-04: "make the gate
# recover, not just detect"). A method Revise failed to delete outlives its source in the daemon, and
# the manifest gate reports it NOT CHECKED: a daemon condition, not a code failure — evidence runs
# are fresh processes and never see it. So when the ONLY failure of a preflight is that gate's
# coverage test, and every method it names is STALE (defined in no file under src/), the daemon is
# restarted and the preflight rerun ONCE; the rerun's verdict is the verdict, and a failure after the
# restart is reported as REAL. It never suppresses a NOT CHECKED: the only way to PASS is a clean
# rerun in a fresh daemon. Any other failure beside it — or a REAL name — fails at once, with the
# names classified so a stale one is not mistaken for a code failure.
_preflight() {
    local rc log="$DIR/preflight_test_static_analysis.log" cls nfail ncov
    if [ "${LOGICKERNEL_PREFLIGHT_RETRY:-0}" != 1 ]; then          # once per cycle, not on the rerun
        _rss_gate preflight || return 1
    fi
    _preflight_once; rc=$?
    _running && _rss_log preflight end "$(_daemon_rss_kb)" "exit $rc"
    [ "$rc" -eq 0 ] && return 0
    if [ "${LOGICKERNEL_PREFLIGHT_RETRY:-0}" = 1 ]; then
        echo "preflight: still FAILS after a daemon restart — a REAL failure"
        return "$rc"
    fi
    [ "$PF_SA_FAIL" = 1 ] && grep -q "NOT CHECKED for dispatch:" "$log" || return "$rc"
    cls=$(_preflight_stale "$log")
    [ -n "$cls" ] || { echo "preflight: could not classify the NOT CHECKED methods"; return "$rc"; }
    printf '%s\n' "$cls" | sed 's/^STALE /preflight:   STALE (defined in no src\/ file — a daemon leftover) /;
        s/^REAL /preflight:   REAL (still defined in src\/ — add it to the manifest) /'
    nfail=$(grep -c -E "Test Failed at|Error During Test|JET-test failed" "$log")
    ncov=$(grep -c "the manifest covers every method LogicKernel defines: Test Failed" "$log")
    if [ "$PF_OTHER_FAIL" = 0 ] && [ "$nfail" -eq 1 ] && [ "$ncov" -eq 1 ] &&
        ! grep -q "stale exemption:" "$log" && ! printf '%s\n' "$cls" | grep -q '^REAL '; then
        echo "preflight: STALE DAEMON — restarting the daemon and rerunning the preflight once"
        _restart > /dev/null || { echo "preflight: the daemon did not restart"; return 1; }
        LOGICKERNEL_PREFLIGHT_RETRY=1 LOGICKERNEL_PREFLIGHT_POOL=0 _preflight
        return $?
    fi
    return "$rc"
}

# _branch_gate_files — the test files a branch commit's evidence runs, one per line: the tree-wide
# gates (they check src/, so a src edit can fail them while their own file is unchanged), every test
# file changed since HEAD or new, and every test file that INCLUDES a changed HELPER — a `.jl` under
# test/ not named `test_*` — directly or through other helpers (user, 2026-10-14: a changed helper's
# unchanged dependents were skipped twice, L1a-1 and L1b 1b's dropped `PutVarMap`, which 13 of
# them passed without). A helper is matched by its file name in an `include(` line, so two helpers
# of one name select both sets: a superset, never a miss. EXCEPT the static-analysis gate
# (test_static_analysis.jl: JET, Aqua, AllocCheck), which every manifest change would bring in
# through static_analysis_body.jl: CI's full run judges it, as below
# (LOGICKERNEL_BRANCH_GATE_CI_ONLY replaces that exclusion: tools/test_warm.sh bgfiles).
# _gate_base — the commit a gate's file selection diffs against (2026-10-17): the MERGE BASE with origin/main,
# so a gate branch made of COMMITTED steps runs what its commits changed. Before, the selection was the
# working tree against HEAD — on a branch of committed steps nothing differed, and the gate ran the
# tree-wide files only (batch 1 and 2 of L1d: three stale pins unrun, found by CI or by hand). HEAD where
# there is no origin/main (a CI checkout at depth 1); LOGICKERNEL_GATE_BASE names one outright (the tests).
_gate_base() {
    if [ -n "${LOGICKERNEL_GATE_BASE:-}" ]; then
        echo "$LOGICKERNEL_GATE_BASE"
        return
    fi
    git -C "$ROOT" merge-base origin/main HEAD 2> /dev/null || echo HEAD
}
# _changed_files — the files a gate treats as changed: tracked ones differing from the base (committed or
# not) and untracked ones
_changed_files() {
    (cd "$ROOT" && { git diff --name-only "$(_gate_base)"; git ls-files -o --exclude-standard; }) | sort -u
}
# _src_named_tests — THE SOURCE-TO-TEST MAP (2026-10-18; tooling 2): the test files that NAME a function whose
# top-level definition the src/ diff since the gate base adds, changes or removes. L1d's batches broke tests
# that had not changed themselves (the allocation pins, test_atom_words' value-table case, an inert ladder):
# a src edit selected none of them. A definition line is a top-level `function NAME(`, `@inline function
# NAME(` or `NAME(...) … =` line; a name shorter than 4 characters is skipped; at most 40 files.
_src_named_tests() {
    local base names n
    base="$(_gate_base)"
    names=$(cd "$ROOT" && git diff -U0 "$base" -- src 2> /dev/null |
        sed -nE 's/^[-+]((@inline|@noinline) +)?(function +)?([A-Za-z_][A-Za-z0-9_!]*)(\{[^}]*\})?\(.*/\4/p' |
        grep -vxE 'function|end|if|for|while|let|begin|return|const|struct|mutable|module|using|import|export' |
        awk 'length($0) >= 4' | sort -u)
    [ -n "$names" ] || return 0
    for n in $names; do
        (cd "$ROOT" && grep -rlwF --include='test_*.jl' -- "$n" test 2> /dev/null) || :
    done | sort -u | head -40
}
_branch_gate_files() {
    local changed helpers more h re f
    changed=$(_changed_files)
    helpers=$(printf '%s\n' "$changed" | grep -E '^test/(.*/)?[^/]*\.jl$' | grep -vE '(^|/)test_[^/]*\.jl$')
    while :; do                                         # helpers that include a changed helper
        more=""
        for h in $helpers; do
            re=$(basename "$h" | sed 's/\./\\./g')
            for f in $(cd "$ROOT" && grep -rlE --include='*.jl' "include\(.*[\"/]$re\"" test 2> /dev/null); do
                case "$(basename "$f")" in test_*) continue ;; esac
                printf '%s\n' $helpers $more | grep -qxF "$f" || more="$more $f"
            done
        done
        [ -z "$more" ] && break
        helpers="$helpers $more"
    done
    {
        printf '%s\n' test/test_type_discipline.jl test/test_lint_globals.jl
        printf '%s\n' "$changed" | grep -E '^test/(.*/)?test_[^/]*\.jl$'
        # CI's tooling job runs when tools/, .github/ or either of these two files changed; the gate's two tests of
        # the tooling must run on the same condition (a CI.yml or tools/ edit that breaks them was CI-only)
        if printf '%s\n' "$changed" | grep -qE '^(tools/|\.github/)'; then
            printf '%s\n' test/test_gate_split.jl test/test_port_check.jl
        fi
        _src_named_tests                                # the source-to-test map (above)
        for h in $helpers; do
            re=$(basename "$h" | sed 's/\./\\./g')
            (cd "$ROOT" && grep -rlE --include='test_*.jl' "include\(.*[\"/]$re\"" test 2> /dev/null) ||
                [ $? -eq 1 ]        # no includer is fine; grep's 2 (a bad pattern, a missing file) still fails
        done                        # (under pipefail the LAST grep's status was the list's: exit 1 for a helper
                                    # no test file includes — user, 2026-10-16)
    } | grep -vxF "${LOGICKERNEL_BRANCH_GATE_CI_ONLY-test/test_static_analysis.jl}" | sort -u
}

# THE BRANCH-GATE'S TIME BUDGET (user, 2026-10-14 night): the helper rule (above) made C2's gate
# 69 files on three term types — 48 min on the W530 per commit, while CI runs the same suite in
# parallel in less, and `main` moves only on CI's green anyway: a long local gate added delay, not
# safety. So the selection is estimated from the LAST RECORDED time of each file (`_file_time`,
# kept in .warm/file_times.tsv by every warm file run; a file with none counts
# LOGICKERNEL_BRANCH_GATE_DEFAULT_S, 60), and when the estimate exceeds the budget
# (LOGICKERNEL_BRANCH_GATE_BUDGET_S, 600 s) the gate runs the fast check, the tree-wide gates and
# the DIRECTLY changed test files only, and says what it left to CI. CI's full run stays the gate
# for main.
_times_file() { echo "${LOGICKERNEL_FILE_TIMES:-$DIR/file_times.tsv}"; }
# _record_file_time FILE SECONDS — the file's last time, replacing its older one
_record_file_time() {
    local tf
    tf="$(_times_file)"
    mkdir -p "$(dirname "$tf")"
    { grep -vF "$(printf '%s\t' "$1")" "$tf" 2> /dev/null; printf '%s\t%s\n' "$1" "$2"; } > "$tf.new" &&
        mv "$tf.new" "$tf"
}
# _file_time FILE — its last recorded seconds, or the default
_file_time() {
    local t
    t=$(awk -F '\t' -v f="$1" '$1 == f { s = $2 } END { if (s != "") print s }' "$(_times_file)" 2> /dev/null)
    echo "${t:-${LOGICKERNEL_BRANCH_GATE_DEFAULT_S:-60}}"
}
# _branch_gate_direct — the tree-wide gates and the test files changed since the gate base (`_gate_base`) or new
_branch_gate_direct() {
    {
        printf '%s\n' test/test_type_discipline.jl test/test_lint_globals.jl
        _changed_files | grep -E '^test/(.*/)?test_[^/]*\.jl$'
    } | grep -vxF "${LOGICKERNEL_BRANCH_GATE_CI_ONLY-test/test_static_analysis.jl}" | sort -u
}
# _branch_gate_plan — the files this branch-gate runs, one per line (stdout); the estimate, and what
# an over-budget selection leaves to CI, on stderr
_branch_gate_plan() {
    local all direct est=0 n budget f left
    all=$(_branch_gate_files)
    budget="${LOGICKERNEL_BRANCH_GATE_BUDGET_S:-600}"
    for f in $all; do est=$(( est + $(_file_time "$f") )); done
    n=$(printf '%s\n' $all | grep -c .)
    if [ "$est" -le "$budget" ]; then
        echo "branch-gate: $n file(s), estimate ${est}s within the ${budget}s budget: all of them" >&2
        printf '%s\n' $all
        return 0
    fi
    direct=$(_branch_gate_direct)
    left=$(printf '%s\n' $all | grep -vxF -f <(printf '%s\n' $direct) | grep -c .)
    echo "branch-gate: over budget — $n file(s), estimate ${est}s > ${budget}s: the directly changed test files and the tree-wide gates only; over budget: $left files left to CI" >&2
    printf '%s\n' $all | grep -vxF -f <(printf '%s\n' $direct) | sed 's/^/  left to CI: /' >&2
    printf '%s\n' $direct
}

# _branch_gate — THE BRANCH-GATE (user, approved 2026-10-14): commits are made off `main`, and a
# branch commit's evidence is the fast check (`check`: format, port_check, manifest, term scopes) plus the
# tree-wide gates and every test file changed since HEAD, each on EVERY term type (`_file` with no
# implementation). `main` moves only to a commit whose full CI run is green (the commit hook refuses
# a commit on `main` in this repo; tools/githooks/pre-push refuses `main` without that run). Not the
# preflight: no JET/Aqua/AllocCheck here — CI's full run judges those.
_branch_gate() {
    _running || _start > /dev/null || return 1
    local t0 rc=0 f files log
    t0=$(date +%s)
    _ci_gate "$ROOT" 0 || { echo "branch-gate: FAIL — the previous push's CI (tools/ci_status.sh)"; return 1; }
    LOGICKERNEL_INERT_BUDGET_S="${LOGICKERNEL_INERT_BUDGET_S:-600}" _checks_fresh || { echo "branch-gate: FAIL (format/port_check/manifest/term scopes/meta/inert) in $(( $(date +%s) - t0 ))s"; return 1; }
    # STEP 0, GATE PARITY (2026-10-18; tooling 2): the fast static pre-check — Aqua, JET's report_package — IN
    # THE WARM DAEMON, as the preflight runs it, before any test file: a JET error or an ambiguity stops the
    # gate in seconds. MEASURED 2026-10-18: 142 s the first run of a daemon (JET compiles once), 8 s after; a
    # fresh process paid 732 s — never run it cold here (user, 2026-10-17)
    echo "branch-gate: the fast static pre-check (Aqua, JET report_package)"
    log="$DIR/branch_gate_static_fast.log"
    _file test/static_analysis_fast.jl > "$log" 2>&1 || {
        grep -E "Test Failed|Error During|JET-test failed|Aqua|ambigu|no matching method|possible error" "$log" | head -20
        echo "branch-gate: FAIL (fast static pre-check) in $(( $(date +%s) - t0 ))s — $log"
        return 1
    }
    files=$(_branch_gate_plan)                          # within the time budget (above)
    local f0
    for f in $files; do
        [ -f "$ROOT/$f" ] || continue
        echo "branch-gate: $f"
        log="$DIR/branch_gate_$(basename "$f" .jl).log"
        f0=$(date +%s)
        _file "$f" > "$log" 2>&1 || { rc=1; echo "branch-gate: FAILED — $log"; }
        _record_file_time "$f" "$(( $(date +%s) - f0 ))"
        grep -E "\.jl \[|\.jl  *\||Test Failed|Error During" "$log"
    done
    echo "branch-gate: $([ "$rc" -eq 0 ] && echo PASS || echo FAIL) in $(( $(date +%s) - t0 ))s"
    return "$rc"
}

# _marker_lib — the workspace's evidence marker (workflows/test_marker.sh); in a standalone clone none
_marker_lib() {
    # shellcheck source=/dev/null
    . "$ROOT/../workflows/test_marker.sh" 2>/dev/null ||
        . "${LOGICKERNEL_WORKSPACE:-$HOME/code/CognitiveSubstratesAI}/workflows/test_marker.sh" 2>/dev/null || true
}

_workload() {
    local v
    case "${1:-}" in on) v=true ;; off) v=false ;; *) echo "usage: tools/warm.sh workload on|off" >&2; return 2 ;; esac
    # PrecompileTools' own switch, a LOCAL preference (LocalPreferences.toml, gitignored): CI and
    # fresh clones keep the workload (user, 2026-10-03)
    (cd "$ROOT" && julia --startup-file=no --project=. -e \
        "import PrecompileTools, LogicKernel; PrecompileTools.Preferences.set_preferences!(LogicKernel, \"precompile_workload\" => $v; force=true)" < /dev/null) &&
        echo "precompile workload: $1 (this checkout; restart the lane to recompile)"
}

# SUMMARY MODE (audit D-0178 item 1, D-0166/D-0155: cut the dispatcher's context): `--summary` after
# check | file | static | branch-gate runs the SAME command with its whole output in $DIR/summary_<…>.log
# and prints tools/summarize_log.sh's <= 10 lines instead. The exit status is the command's own: it is
# captured from the plain run (a redirect, no pipeline) and re-raised after the summary.
case "${1:-}" in
    check | file | static | branch-gate)
        _sm_args=() _sm_on=0
        for _sm_a in "$@"; do
            if [ "$_sm_a" = --summary ]; then _sm_on=1; else _sm_args+=("$_sm_a"); fi
        done
        if [ "$_sm_on" = 1 ]; then
            mkdir -p "$DIR"
            _sm_name="$1"
            [ "$1" = file ] && _sm_name="file_$(basename "${2:-x}" .jl)"
            _sm_log="$DIR/summary_${_sm_name}.log"
            _sm_t0=$(date +%s)
            "$0" "${_sm_args[@]}" > "$_sm_log" 2>&1
            _sm_rc=$?
            "$ROOT/tools/summarize_log.sh" "$1" "$_sm_log" "$_sm_rc" "$(( $(date +%s) - _sm_t0 ))"
            exit "$_sm_rc"
        fi
        ;;
esac

cmd="${1:-status}"; shift || true
case "$cmd" in
    status) ;;
    preflight | evidence | locked | branch-gate)
        if [ "$cmd" = branch-gate ]; then
            _bg_br="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null)"
            case "$_bg_br" in
                "" | main | master)
                    echo "branch-gate: REFUSED — it is evidence for a BRANCH commit, and this checkout is on '${_bg_br:-a detached HEAD}': commit on a branch, push it as gate/<name>, and fast-forward main to it once CI is green (exit 2)" >&2
                    exit 2
                    ;;
            esac
        fi
        _run_lock || exit 5
        echo "$cmd" > "$DIR/run.kind"                   # tools/lib_evidence.sh `_evidence_running`
        ;;
    *)
        # TEST SEAMS send nothing to the daemon (the send probe, the cold term-scopes snippet), so the lane's
        # reason to refuse — a probe changing the daemon under a run — does not apply: test/test_gate_split.jl
        # runs these inside the branch-gate, which holds the lane
        if [ "${LOGICKERNEL_WARM_SEND_PROBE:-}" != 1 ] && [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" != 1 ]; then
            _lane_check || exit 5
        fi
        ;;
esac
case "$cmd" in
    start) _start ;;
    stop) _stop; rm -f "$DIR/second" ;;                   # a deliberate stop forgets the second-daemon opt-in
    restart) _restart ;;
    status) if _running; then echo "warm lane: running (unit $UNIT, pid $(cat "$DIR/ready"), rss $(_gb "$(_daemon_rss_kb)") GB)"; else echo "warm lane: not running"; exit 3; fi ;;
    send) _send "${1:-}" ;;
    branch-gate-files) _branch_gate_files ;;     # the files a branch-gate would run (no daemon)
    branch-gate-plan) _branch_gate_plan ;;       # … within its time budget (no daemon)
    file)
        [ $# -ge 1 ] || { echo "usage: tools/warm.sh file PATH [impl]" >&2; exit 2; }
        _fl_t0=$(date +%s)
        _file "$@"
        _fl_rc=$?
        # a whole-file run (every term type) is the branch-gate's estimate (`_file_time`)
        [ $# -eq 1 ] && _record_file_time "${1#"$ROOT"/}" "$(( $(date +%s) - _fl_t0 ))"
        (exit "$_fl_rc")
        ;;
    bench) _bench "$@" ;;
    fmt-pin) _fmt_pin ;;                               # the JuliaFormatter version CI.yml pins
    term-scopes)                                       # the declarations check alone (seconds; no formatter)
        [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" = 1 ] || _running || _start > /dev/null || exit 1
        _term_scopes_check
        ;;
    meta-check)                                        # one of `check`'s CI-parity steps alone
        [ "${LOGICKERNEL_WARM_SEND_PROBE:-}" = 1 ] || _running || _start > /dev/null || exit 1
        _meta_check
        ;;
    inert-check) _inert_check "${1:-120}" ;;           # the Pkg.test-way run alone: a fresh julia, no daemon
    static)
        # the static-analysis gate (JET, Aqua, AllocCheck) on the reference type, WARM — what the notes
        # called `warm.sh file test/test_static_analysis.jl reference` (like `file`: the daemon must run)
        _file test/test_static_analysis.jl reference
        ;;
    check)
        _running || _start > /dev/null || exit 1
        _ck_t0=$(date +%s)
        _check_julia_ci "$ROOT" check                   # a WARN only (tools/lib_evidence.sh, audit D-0026)
        _checks_fresh
        _ck_rc=$?
        echo "check: $([ "$_ck_rc" -eq 0 ] && echo PASS || echo FAIL) (format, port_check, manifest, term scopes, meta files, inert guard) in $(( $(date +%s) - _ck_t0 ))s"
        (exit "$_ck_rc")
        ;;
    fmt)
        # (user, 2026-10-16) the formatter in WRITE mode on the CHANGED files, in the warm daemon — run it
        # before `check`/`branch-gate`, so the check never fails on format (three such failures that
        # day, each a hand-wrapped line and a lost cycle). Changed = tracked .jl files differing from
        # HEAD (added, copied, modified, renamed) and untracked ones, as `check` would find them.
        _fm_files=$(
            {
                git -C "$ROOT" diff --name-only --diff-filter=ACMR HEAD -- '*.jl'
                git -C "$ROOT" ls-files --others --exclude-standard -- '*.jl'
            } | sort -u
        )
        if [ -z "$_fm_files" ]; then
            echo "fmt: no changed .jl file"
            exit 0
        fi
        _running || _start > /dev/null || exit 1
        {
            echo 'using JuliaFormatter'
            echo 'let n = 0'
            while IFS= read -r _fm_f; do
                printf '    format(raw"%s/%s") || (n += 1; println("fmt: formatted %s"))\n' "$ROOT" "$_fm_f" "$_fm_f"
            done <<< "$_fm_files"
            echo '    println("fmt: ", n, " file(s) rewritten; every changed file is Blue-clean")'
            echo 'end'
        } > "$DIR/fmt_snippet.jl"
        _send "$DIR/fmt_snippet.jl"
        ;;
    inventory)
        # (user, 2026-10-16) `port_check.jl --write-inventory` in the WARM daemon: the generated blocks
        # (docs/port_inventory.md, the coverage and the code graph in docs/architecture.md) rewritten,
        # then port_check run — the current checker in a fresh module, as `check` loads it. A cold
        # `julia tools/port_check.jl --write-inventory` needed the workspace hook's cold-start marker.
        _running || _start > /dev/null || exit 1
        cat > "$DIR/inventory_snippet.jl" <<JL
let pc = Module(:WarmInventory)
    Base.include(pc, raw"$ROOT/tools/port_check.jl")
    println("inventory: wrote ", Base.invokelatest(() -> pc.write_inventory(raw"$ROOT")))
    r = Base.invokelatest(() -> pc.port_check(raw"$ROOT"))
    foreach(x -> println("  ", x), r.violations)
    isempty(r.violations) || error("inventory: port_check found violations after the rewrite")
    println("inventory: port_check clean (", length(r.files), " files)")
end
JL
        _send "$DIR/inventory_snippet.jl"
        ;;
    preflight)
        # A PASSED PREFLIGHT IS EVIDENCE FOR A BRANCH COMMIT (user, 2026-10-13: the gate is CI's —
        # commit on a branch after the local preflight, push it as gate/<name>, evidence.yml judges
        # it, `main` is fast-forwarded). The workspace's marker records it, bound to this tree as
        # it was when the preflight STARTED, under a label the commit hook reads: it accepts a
        # preflight on a branch and refuses it on `main`. In a standalone clone: no helper, no marker.
        _marker_lib
        _pf_fp=""
        command -v start_marker >/dev/null 2>&1 && _pf_fp="$(start_marker "$ROOT")"
        _preflight
        _pf_rc=$?
        # a preflight whose static-analysis step was STUBBED (the tooling tests' seam) is no evidence
        if [ "${LOGICKERNEL_PREFLIGHT_STUB_STATIC:-}" != 1 ]; then
            command -v write_marker >/dev/null 2>&1 &&
                write_marker "$ROOT" "$_pf_rc" "preflight (warm, the chunk's term types: evidence for a BRANCH commit, never for main)" "$_pf_fp"
        fi
        (exit "$_pf_rc")
        ;;
    branch-gate)
        # the marker is bound to the tree as it was when the run STARTED, under the label the commit
        # hook reads: `branch-gate…` is accepted on a branch, refused on main (as a preflight is)
        _marker_lib
        _bg_fp=""
        command -v start_marker > /dev/null 2>&1 && _bg_fp="$(start_marker "$ROOT")"
        _branch_gate
        _bg_rc=$?
        command -v write_marker > /dev/null 2>&1 &&
            write_marker "$ROOT" "$_bg_rc" "branch-gate (warm: the fast check + the tree-wide and changed test files on every term type — evidence for a BRANCH commit, never for main)" "$_bg_fp"
        (exit "$_bg_rc")
        ;;
    evidence)
        # the evidence run reads its worker count from free memory: an oversized daemon goes first
        _rss_gate evidence || exit 1
        exec "$ROOT/tools/run_tests.sh"
        ;;
    locked) [ $# -ge 1 ] || { echo "usage: tools/warm.sh locked CMD [ARGS…]" >&2; exit 2; }; "$@" ;;
    pool) _pool ;;
    workload) _workload "${1:-}" ;;
    *) sed -n '2,25p' "$0"; exit 2 ;;
esac
