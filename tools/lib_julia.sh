# ORIGINAL: no swipl-devel counterpart — LogicKernel's LOCAL Julia PIN (audit D-0465 items 2-3, D-0466).
# tools/lib_julia.sh — sourced by tools/warm.sh, tools/run_tests.sh, tools/pkgtest_way.sh, tools/bench.sh,
# tools/mutate.sh, tools/mutate_sa_part.sh, tools/prepush.sh, tools/test_fuzz.sh; its command line is
# tools/julia_pin.sh (the Python callers, mutate_ci.py, use it).
#
# THE RULE: every LOCAL path runs the Julia of tools/WARM_JULIA_VERSION, whatever `juliaup default` is
# (the machine setting is never touched). The bin directory of that version is looked up in juliaup's
# install directory (~/.julia/juliaup/julia-<ver>+*/bin) and put FIRST on PATH; the `julia` that PATH then
# finds must print exactly that version, else the path REFUSES (exit 7) — a gate or mutation run must
# never silently run another patch (the daemons and the local mutation runs ran 1.13.2 while CI ran
# 1.13.3, measured 2026-11-10). Not installed: refused with the `juliaup add <ver>` hint.
#   LOGICKERNEL_JULIA_PIN      exported on success: the pinned version; tools/warm_session.jl and
#                              tools/worker.jl refuse a process whose VERSION differs from it
#   LOGICKERNEL_JULIA_PIN_OFF=1   FOR TESTS ONLY: no pin (the notice is printed); REFUSED (exit 7) in every
#                              gate path: tools/prepush.sh, `warm.sh branch-gate|preflight|evidence`,
#                              tools/mutate.sh, tools/mutate_ci.py, tools/mutate_sa_part.sh — those export
#                              LOGICKERNEL_JULIA_PIN_GATE=1, which their children inherit
#   GITHUB_ACTIONS=true        CI: the pin is not applied (setup-julia resolves its own version, `version: '1.13'`)
# A BUMP is a one-line commit of tools/WARM_JULIA_VERSION (with a dated note in its comment) when CI's
# resolved version moves: tools/lib_evidence.sh `_check_julia_ci` WARNs about the difference.

# _julia_pin_want ROOT — the pinned version (stdout; status 1 when the file is missing or holds none)
_julia_pin_want() {
    local v
    v="$(sed -nE 's/^[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*(#.*)?$/\1/p' "$1/tools/WARM_JULIA_VERSION" 2> /dev/null | head -1)"
    [ -n "$v" ] || return 1
    printf '%s' "$v"
}

# _julia_pin_bindir VERSION — the bin directory of juliaup's install of VERSION (status 1: not installed)
_julia_pin_bindir() {
    local d
    for d in "$HOME/.julia/juliaup/julia-$1+0.x64.linux.gnu/bin" "$HOME/.julia/juliaup/julia-$1+"*/bin; do
        if [ -x "$d/julia" ]; then printf '%s' "$d"; return 0; fi
    done
    return 1
}

# _julia_version_of — the X.Y.Z the `julia` on PATH prints (empty when there is none)
_julia_version_of() {
    julia --version 2> /dev/null | sed -nE 's/^julia version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1
}

# _julia_pin_apply ROOT WHO [gate] — put the pinned Julia first on PATH (exported) and prove it. Messages go to
# stderr, status 0 = ok / 7 = refused. `gate` makes the path a gate path: the override is refused there.
_julia_pin_apply() {
    local root="$1" who="$2" want bin have
    [ "${3:-}" = gate ] && export LOGICKERNEL_JULIA_PIN_GATE=1
    [ "${GITHUB_ACTIONS:-}" = true ] && return 0
    if [ "${LOGICKERNEL_JULIA_PIN_OFF:-}" = 1 ]; then
        if [ "${LOGICKERNEL_JULIA_PIN_GATE:-}" = 1 ]; then
            echo "$who: REFUSED — LOGICKERNEL_JULIA_PIN_OFF=1 is for tests only and never in a gate, pre-push or mutation path: unset it (the pin is tools/WARM_JULIA_VERSION)" >&2
            return 7
        fi
        echo "$who: NOTICE — LOGICKERNEL_JULIA_PIN_OFF=1: the Julia pin is OFF, running '$(_julia_version_of)' from PATH (tests only)" >&2
        unset LOGICKERNEL_JULIA_PIN
        return 0
    fi
    want="$(_julia_pin_want "$root")" ||
        { echo "$who: REFUSED — tools/WARM_JULIA_VERSION is missing or holds no X.Y.Z version (the Julia every local path runs)" >&2; return 7; }
    bin="$(_julia_pin_bindir "$want")" ||
        { echo "$who: REFUSED — Julia $want (tools/WARM_JULIA_VERSION) is not installed: juliaup add $want" >&2; return 7; }
    PATH="$bin:$PATH"
    export PATH
    have="$(_julia_version_of)"
    if [ "$have" != "$want" ]; then
        echo "$who: REFUSED — the julia found first prints '${have:-nothing}', the pin is $want ($bin): a gate or mutation run never runs another patch" >&2
        return 7
    fi
    LOGICKERNEL_JULIA_PIN="$want"
    export LOGICKERNEL_JULIA_PIN
    return 0
}

# _julia_pid_version PID — the version of the juliaup install a running process was started from
# (/proc/PID/exe), for a daemon that predates the version record; empty when unknown
_julia_pid_version() {
    readlink "/proc/$1/exe" 2> /dev/null | sed -nE 's|.*/julia-([0-9]+\.[0-9]+\.[0-9]+)\+[^/]*/bin/julia$|\1|p'
}
