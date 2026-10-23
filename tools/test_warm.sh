#!/usr/bin/env bash
# tools/test_warm.sh — the warm lane's own tests (tools/warm.sh, tools/warm_session.jl), each judged
# by the EXIT CODE the lane returns, never by its printed text (user, 2026-10-03: "the lane's own
# mutation-proved tests"). Starts its own daemon and stops it.
#
#   tools/test_warm.sh          # exit 0 only if every case passes
#   tools/test_warm.sh rss      # the daemon's-memory cases alone
#   tools/test_warm.sh structs  # the struct gate's cases alone
#   tools/test_warm.sh fast     # the fast static pre-check's planted-defect cases alone
#   tools/test_warm.sh cap      # the task-ceiling cases alone (no daemon)
#   tools/test_warm.sh guard    # the daemon guard alone: one daemon at a time, the idle exit, the budget
#   tools/test_warm.sh bgfiles  # the branch-gate's file selection alone (no daemon)
#   tools/test_warm.sh gatebase # the gate base: committed changes selected (no daemon)
#   tools/test_warm.sh srcmap   # the source-to-test map: a changed src definition selects its tests (no daemon)
#   tools/test_warm.sh noswipl  # the no-swipl pass: CI's Pkg.test condition, the inert guard on
#   tools/test_warm.sh bgbudget # the branch-gate's time budget alone (no daemon)
#   tools/test_warm.sh stale    # the stale-daemon recovery cases alone
#   tools/test_warm.sh refuse   # the pkgdir assertion's refusal alone (no daemon)
#   tools/test_warm.sh inventory # the upstream forwarding and the `inventory` cases alone
#   tools/test_warm.sh main     # the whole flow EXCEPT the cases that are modes of their own (below)
#   tools/test_warm.sh shard NAME # one CI shard (tools/test_warm_shards.tsv): its modes in turn, totals summed
#
# THE SHARDS (D-0059, 2026-10-20): CI runs the suite as several jobs, one `shard NAME` each. The default
# run (no argument) is `main` + every other mode in one process, so the shards' passes sum to the default
# run's by construction; tools/test_warm_shards.tsv declares the shards and that total, and
# tools/evidence_ci.py `warm` fails a run with a shard missing, empty or red, or the sum off.
#
# What a lane must never do, case by case: report a failure as success; run code Revise failed to
# load and present the result as fresh; run a file on fewer implementations than the suite does.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$ROOT/tools/warm.sh"
# (user, 2026-10-16) every preflight here STUBS the full static-analysis file (warm.sh's test seam):
# these cases check the preflight's logic, and the file is 25–28 min on a cold daemon, ~2 min warm —
# the suite must finish in minutes either way. The fast pre-check stays real; the full file is the
# pre-push step (`warm.sh file test/test_static_analysis.jl reference`).
export LOGICKERNEL_PREFLIGHT_STUB_STATIC=1
# (2026-10-17) the selection cases below were written for a gate base of HEAD (the working tree's own
# changes); the gate's default is the merge base with origin/main (`_gate_base`), which on a branch of
# committed steps names more — `_gatebase_cases` checks that side
export LOGICKERNEL_GATE_BASE=HEAD
# (2026-10-18) the preflight's CI check reads GitHub's verdict on origin/main — another commit's state,
# not this tree's: with main red, every preflight case here failed on it (886e761's own CI, the fix for
# that red main — a deadlock). The check itself is covered hermetically (test/test_gate_split.jl's stubs)
export LOGICKERNEL_CI_CHECK=off
if [ "${1:-}" = shard ]; then                        # one CI shard: its modes in turn, the totals summed
    name="${2:-}"
    # TEST SEAMS (test/test_gate_split.jl): the declaration and the runner of a mode, which are this
    # script and the repository's tsv unless planted
    groups="$(awk -F'\t' -v n="$name" '$1 == "shard" && $2 == n { print $3 }' "${LOGICKERNEL_TEST_WARM_SHARDS:-$ROOT/tools/test_warm_shards.tsv}")"
    [ -n "$groups" ] || { echo "test_warm: no shard '$name' in tools/test_warm_shards.tsv"; exit 2; }
    sp=0 sf=0
    for m in $groups; do
        out="$("${LOGICKERNEL_TEST_WARM_RUNNER:-$0}" "$m" 2>&1)"; rc=$?
        printf '%s\n' "$out"
        line="$(printf '%s\n' "$out" | grep -E '^test_warm( \([a-z]+\))?: [0-9]+ passed, [0-9]+ failed$' | tail -1)"
        if [ -z "$line" ]; then
            echo "test_warm (shard $name): mode $m printed no totals (exit $rc)"; sf=$((sf + 1)); continue
        fi
        sp=$((sp + $(printf '%s' "$line" | sed -E 's/.*: ([0-9]+) passed, ([0-9]+) failed/\1/')))
        mf=$(printf '%s' "$line" | sed -E 's/.*: ([0-9]+) passed, ([0-9]+) failed/\2/')
        sf=$((sf + mf))
        [ "$rc" -eq 0 ] || [ "$mf" -gt 0 ] || sf=$((sf + 1))
    done
    echo "test_warm (shard $name): $sp passed, $sf failed"
    [ "$sf" -eq 0 ]; exit $?
fi
MAIN_ONLY=0; [ "${1:-}" = main ] && MAIN_ONLY=1       # `main`: the cases that are modes of their own are skipped
_unless_main() { [ "$MAIN_ONLY" = 1 ] || "$@"; }
mkdir -p "$ROOT/.warm"
T="$(mktemp -d "$ROOT/.warm/test.XXXXXX")"
trap '[ -f "$T/rules_common.jl.bak" ] && cp "$T/rules_common.jl.bak" "$ROOT/test/core_lang/rules_common.jl"; [ -f "$T/term_interface.jl.bak" ] && cp "$T/term_interface.jl.bak" "$ROOT/src/term_interface.jl"; [ -f "$T/manifest.bak" ] && cp "$T/manifest.bak" "$ROOT/test/static_analysis_manifest.jl"; [ -f "$T/port_check.jl.bak" ] && cp "$T/port_check.jl.bak" "$ROOT/tools/port_check.jl"; "$W" stop >/dev/null 2>&1; rm -rf "$T"; rm -f "$ROOT"/src/_preflight_probe_*.jl "$ROOT"/src/_struct_probe_*.jl "$ROOT"/test/core_lang/test_preflight_probe_*.jl' EXIT
pass=0 fail=0
check() {   # check NAME WANT_EXIT GOT_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $3, want $2"; fi
}
has() {     # has NAME FILE PATTERN WANT(1 present / 0 absent)
    if grep -q "$3" "$2"; then got=1; else got=0; fi
    check "$1" "$4" "$got"
}

# THE DAEMON'S MEMORY (2026-10-11): a gate cycle starts by reading the daemon's resident set — under
# the limit it is kept, over it RESTARTED (a new pid) with the reason printed — and every reading
# goes to the log (a temporary one here, LOGICKERNEL_WARM_RSS_LOG). The size is planted
# (LOGICKERNEL_WARM_RSS_FAKE_KB); the preflight behind
# it is cut short by a planted fault, so each case costs seconds.
_rss_cases() {
    export LOGICKERNEL_WARM_RSS_LOG="$T/rss.log"        # planted sizes stay out of the real record
    pid0=$(cat "$ROOT/.warm/ready")
    LOGICKERNEL_WARM_RSS_FAKE_KB=1048576 LOGICKERNEL_PREFLIGHT_FAULT=format-empty LOGICKERNEL_PREFLIGHT_POOL=0 \
        "$W" preflight > "$T/pf" 2>&1
    [ "$(cat "$ROOT/.warm/ready")" = "$pid0" ]; check "rss: a daemon under the limit is kept" 0 $?
    has "…its size printed" "$T/pf" "daemon rss 1.0 GB (limit 5 GB)" 1
    tail -2 "$T/rss.log" > "$T/rss"
    has "…and logged at the gate's start" "$T/rss" "preflight.start.1.0 GB.kept" 1
    has "…and at its end" "$T/rss" "preflight.end.1.0 GB.exit 1" 1
    LOGICKERNEL_WARM_RSS_FAKE_KB=7864320 LOGICKERNEL_PREFLIGHT_FAULT=format-empty LOGICKERNEL_PREFLIGHT_POOL=0 \
        "$W" preflight > "$T/pf" 2>&1
    [ "$(cat "$ROOT/.warm/ready")" != "$pid0" ]; check "rss: a daemon over the limit is RESTARTED" 0 $?
    has "…with its reason" "$T/pf" "restarting the daemon — rss 7.5 GB > 5 GB" 1
    tail -2 "$T/rss.log" > "$T/rss"
    has "…and the restart logged" "$T/rss" "restarted (rss 7.5 GB > 5 GB)" 1
    "$W" send "$T/ok.jl" > /dev/null 2>&1; check "…and the new daemon answers" 0 $?
    pid1=$(cat "$ROOT/.warm/ready")
    LOGICKERNEL_WARM_RSS_MAX_GB=9 LOGICKERNEL_WARM_RSS_FAKE_KB=7864320 LOGICKERNEL_PREFLIGHT_FAULT=format-empty \
        LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
    [ "$(cat "$ROOT/.warm/ready")" = "$pid1" ]; check "rss: the limit is LOGICKERNEL_WARM_RSS_MAX_GB" 0 $?
    unset LOGICKERNEL_WARM_RSS_LOG
}
# THE STRUCT GATE (2026-10-12): before a snippet is sent, a struct the daemon loaded whose definition
# CHANGED, or went away, restarts the daemon (a new pid), the reason printed and logged — "struct
# changed: <name>"; a NEW struct, a comment or a re-indentation restarts nothing. The probe struct
# is a file under src/ that LogicKernel does not include: the gate reads the source, so the daemon
# need not load it, and nothing else sees it.
_struct_cases() {
    probe="$ROOT/src/_struct_probe_$$.jl"
    pid() { cat "$ROOT/.warm/ready"; }
    sendok() { "$W" send "$T/ok.jl" > "$T/so" 2> "$T/se"; }
    rm -f "$ROOT/.warm/restart.log"
    sendok; check "structs: a send on an unchanged tree" 0 $?
    p0=$(pid)
    printf 'struct WarmStructProbe\n    a::Int\nend\n' > "$probe"
    sendok; check "structs: a NEW struct — the send passes" 0 $?
    [ "$(pid)" = "$p0" ]; check "…and the daemon is KEPT" 0 $?
    has "…with no restart announced" "$T/se" "struct changed" 0
    printf 'struct WarmStructProbe\n    a::Int\n    b::Int\nend\n' > "$probe"
    sendok; check "structs: a field ADDED — the send passes" 0 $?
    [ "$(pid)" != "$p0" ]; check "…on a RESTARTED daemon" 0 $?
    has "…with its reason" "$T/se" "restarting the daemon — struct changed: WarmStructProbe$" 1
    has "…and the reason logged" "$ROOT/.warm/restart.log" "struct changed: WarmStructProbe$" 1
    has "…the snippet's own output intact" "$T/so" "^ok$" 1
    p1=$(pid)
    sendok; [ "$(pid)" = "$p1" ]; check "structs: the next send restarts nothing" 0 $?
    printf '# a comment\nstruct WarmStructProbe\n    a::Int      # the first\n\n    b::Int\nend\n' > "$probe"
    sendok; [ "$(pid)" = "$p1" ]; check "structs: a comment, a blank line, spacing — KEPT" 0 $?
    printf 'struct WarmStructProbe\n    a::Int\n    b::Float64\nend\n' > "$probe"
    sendok; [ "$(pid)" != "$p1" ]; check "structs: a field's TYPE changed — RESTARTED" 0 $?
    p2=$(pid)
    printf 'mutable struct WarmStructProbe\n    a::Int\n    b::Float64\nend\n' > "$probe"
    sendok; [ "$(pid)" != "$p2" ]; check "structs: made mutable — RESTARTED" 0 $?
    p3=$(pid)
    printf 'mutable struct WarmStructProbe\n    a::Int\n    b::Float64\nend\nstruct WarmStructProbe2 x::Int end\n' > "$probe"
    sendok; [ "$(pid)" = "$p3" ]; check "structs: a second, new struct beside it — KEPT" 0 $?
    rm -f "$probe"
    sendok; check "structs: the structs REMOVED — the send passes" 0 $?
    [ "$(pid)" != "$p3" ]; check "…on a RESTARTED daemon" 0 $?
    has "…naming both" "$T/se" "struct changed: WarmStructProbe,WarmStructProbe2$" 1
    [ "$(grep -c 'struct changed' "$ROOT/.warm/restart.log")" = 4 ]; check "…four restarts logged in all" 0 $?
    "$W" file test/test_package.jl reference > /dev/null 2>&1; check "…and the lane still runs a test file" 0 $?
    # the snapshot is taken WHEN THE DAEMON STARTS, not at its first snippet: a struct changed
    # between the two is a change
    printf 'struct WarmStructProbe\n    a::Int\nend\n' > "$probe"
    "$W" stop > /dev/null 2>&1
    "$W" start > /dev/null 2>&1; check "structs: a fresh start with the probe in the tree" 0 $?
    p4=$(pid)
    printf 'struct WarmStructProbe\n    a::Int\n    c::Int\nend\n' > "$probe"
    sendok; [ "$(pid)" != "$p4" ]; check "…changed before the FIRST snippet — RESTARTED" 0 $?
    rm -f "$probe"
    sendok; check "…and removed again" 0 $?
    # (2026-10-17) a top-level CONST is in the snapshot too: Revise does not re-evaluate a changed one (a
    # daemon missed new entries of the `PL_extension` table, and `@<` was no built-in to it)
    cprobe="$ROOT/src/_const_probe_$$.jl"
    pc0=$(pid)
    printf 'const WARM_CONST_PROBE = (\n    1,\n    2\n)\n' > "$cprobe"
    sendok; [ "$(pid)" = "$pc0" ]; check "consts: a NEW const — KEPT" 0 $?
    printf 'const WARM_CONST_PROBE = (\n    1,\n    2,\n    3\n)\n' > "$cprobe"
    sendok; [ "$(pid)" != "$pc0" ]; check "consts: its VALUE changed (an entry added) — RESTARTED" 0 $?
    has "…naming it" "$T/se" "struct changed: const:WARM_CONST_PROBE$" 1
    pc1=$(pid)
    printf '# a table\nconst WARM_CONST_PROBE = (\n    1,    # one\n    2,\n\n    3\n)\n' > "$cprobe"
    sendok; [ "$(pid)" = "$pc1" ]; check "consts: a comment, a blank line, spacing — KEPT" 0 $?
    rm -f "$cprobe"
    sendok; [ "$(pid)" != "$pc1" ]; check "consts: REMOVED — RESTARTED" 0 $?
}
_fast_cases() {
    local ti="$ROOT/src/term_interface.jl" man="$ROOT/test/static_analysis_manifest.jl" rc s
    [ -f "$T/term_interface.jl.bak" ] || cp "$ti" "$T/term_interface.jl.bak"
    [ -f "$T/manifest.bak" ] || cp "$man" "$T/manifest.bak"
    # plant_exempt FUNC TUPLE… — the planted probe's manifest exemption, first in DISPATCH_EXEMPT
    # (Blue-stable there: one line, a trailing comma), so the manifest's coverage — in the fast
    # check since 1dada85, BEFORE the pre-check — passes and the planted defect reaches the stage
    # each case tests (measured 2026-10-14: without it both cases failed at the manifest instead)
    plant_exempt() {
        local f="$1" t n
        shift
        for t in "$@"; do
            n=$(grep -c '^const DISPATCH_EXEMPT = ($' "$man")
            [ "$n" = 1 ] || { echo "  FAIL plant_exempt: the DISPATCH_EXEMPT anchor is there $n times"; fail=$((fail + 1)); return; }
            awk -v l="    ((LK.$f, $t) => \"planted (test_warm)\")," '{ print } /^const DISPATCH_EXEMPT = \($/ { print l }' \
                "$man" > "$man.tmp" && mv "$man.tmp" "$man"
        done
    }

    # THE FAST STATIC PRE-CHECK (user, 2026-10-12): a formatter violation, a JET error and an Aqua
# ambiguity each STOP the preflight within seconds, before the static-analysis stage starts. One
# planted defect per stage (the control; no mutation run).
    fast_case() {   # fast_case NAME EXPECT_PATTERN — the preflight just ran into $T/pf
    check "$1: the preflight FAILS" 1 "$2"
    has "…at the pre-check, naming it" "$T/pf" "$3" 1
    has "…before the static-analysis stage" "$T/pf" "preflight: the static-analysis gate" 0
}
fmt_probe="$ROOT/test/core_lang/test_preflight_probe_fmt_$$.jl"
printf 'x   =   [1,2,\n   3]\nfunction f( a,b )\n a+b end\n' > "$fmt_probe"
s=$(date +%s)
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; rc=$?
rm -f "$fmt_probe"
fast_case "fast pre-check, formatter" "$rc" "NOT Blue-formatted"
[ $(( $(date +%s) - s )) -lt 120 ]; check "…in under two minutes" 0 $?
jet="_preflight_probe_jet_$$"
printf '\n%s(x::Int) = %s_undefined(x)\n' "$jet" "$jet" >> "$ti"
plant_exempt "$jet" "Tuple{Int}"
s=$(date +%s)
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; rc=$?
cp "$T/term_interface.jl.bak" "$ti"
cp "$T/manifest.bak" "$man"
fast_case "fast pre-check, JET" "$rc" "FAIL (fast static pre-check)"
has "…the JET report names the planted function" "$ROOT/.warm/preflight_static_fast.log" "$jet" 1
# (2026-10-18, tooling 2) the BRANCH-GATE runs the same pre-check as its step 0, in the warm daemon: the same
# planted JET defect stops it there, before any test file (the CI check off: this case is about step 0).
# A branch-gate on main or a detached HEAD refuses itself (exit 2) — and CI checks a push to main out ON
# main (2026-10-18: 0c4d9fa red on its main push, green on its gate push) — so off a branch it runs on a
# scratch branch at HEAD, and the checkout goes back to where it was
bg_head=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null)
bg_sha=$(git -C "$ROOT" rev-parse HEAD)
bg_scratch=""
case "$bg_head" in
    "" | main | master)
        bg_scratch="test-warm-bg-$$"
        git -C "$ROOT" switch -q -c "$bg_scratch"
        ;;
esac
printf '\n%s(x::Int) = %s_undefined(x)\n' "$jet" "$jet" >> "$ti"
plant_exempt "$jet" "Tuple{Int}"
LOGICKERNEL_CI_CHECK=off "$W" branch-gate > "$T/bgf" 2>&1; rc=$?
cp "$T/term_interface.jl.bak" "$ti"
cp "$T/manifest.bak" "$man"
if [ -n "$bg_scratch" ]; then
    if [ -n "$bg_head" ]; then git -C "$ROOT" switch -q "$bg_head"; else git -C "$ROOT" switch -q --detach "$bg_sha"; fi
    git -C "$ROOT" branch -q -D "$bg_scratch"
fi
# ALWAYS a case, so the suite has the same number of them on every ref (the sharded gather compares the
# total — tools/test_warm_shards.tsv; MEASURED 2026-10-21: this check ran only on main or a detached HEAD, a
# push to main passed 212 cases against 211 on a gate branch)
[ "$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2> /dev/null)" = "$bg_head" ] &&
    [ "$(git -C "$ROOT" rev-parse HEAD)" = "$bg_sha" ]
check "…the checkout is where it was (back from a scratch branch off main or a detached HEAD, or never left)" 0 $?
check "branch-gate step 0, JET: the gate FAILS" 1 "$rc"
has "…at the fast pre-check" "$T/bgf" "branch-gate: FAIL (fast static pre-check)" 1
has "…before any test file" "$T/bgf" "^branch-gate: test/" 0
has "…the JET report names the planted function" "$ROOT/.warm/branch_gate_static_fast.log" "$jet" 1
amb="_preflight_probe_amb_$$"
printf '\n%s(::Int, ::Any) = 1\n%s(::Any, ::Int) = 2\n' "$amb" "$amb" >> "$ti"
plant_exempt "$amb" "Tuple{Int, Any}" "Tuple{Any, Int}"
s=$(date +%s)
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; rc=$?
cp "$T/pf" "$T/pf_amb"
cp "$T/term_interface.jl.bak" "$ti"
cp "$T/manifest.bak" "$man"
fast_case "fast pre-check, Aqua" "$rc" "FAIL (fast static pre-check)"
has "…the failure is Aqua's ambiguity test" "$ROOT/.warm/preflight_static_fast.log" "ambig" 1
cmp -s "$T/term_interface.jl.bak" "$ti"; check "src/term_interface.jl is restored after the pre-check cases" 0 $?
cmp -s "$T/manifest.bak" "$man"; check "…and the manifest" 0 $?
    # the steady state: a clean tree, the daemon warm (the first run after an edit pays a Revise and a
    # JET recompile — minutes; measured 137 s, then 9 s)
    "$W" file test/static_analysis_fast.jl > /dev/null 2>&1; check "the pre-check passes on the restored tree" 0 $?
    s=$(date +%s); "$W" file test/static_analysis_fast.jl > /dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] && [ $(( $(date +%s) - s )) -lt 60 ]; check "…and a second run takes under a minute (warm: seconds)" 0 $?

}
# THE TASK CEILING (user, 2026-10-14): warm.sh and run_tests.sh re-run themselves in a scope with
# TasksMax, so their own forks are bounded — the 1558-process fork chain (the backtick cases) ran
# outside every unit. Read the
# ceiling of the cgroup a command run BY warm.sh is in. Only where user systemd exists (not in CI).
# THE BRANCH-GATE'S FILES (user, 2026-10-14): a changed HELPER (a test/ `.jl` not named `test_*`)
# brings in every test file that includes it, directly or through other helpers — its dependents had
# been skipped twice (L1a-1; L1b 1b's dropped PutVarMap, which 13 of them passed without). Each
# case plants a change in a tracked helper and restores it; the baselines are asserted on the
# helper unchanged. No daemon: the selection alone (`branch-gate-files`).
_bgfiles_cases() {
    local rc_f="$ROOT/test/core_lang/rules_common.jl" man_f="$ROOT/test/static_analysis_manifest.jl"
    if git -C "$ROOT" diff --quiet HEAD -- "$rc_f" "$man_f"; then
        "$W" branch-gate-files > "$T/bg0" 2>&1; check "bgfiles: the list is produced" 0 $?
        has "…the tree-wide gates in it" "$T/bg0" '^test/test_type_discipline.jl$' 1
        has "bgfiles: baseline — an unchanged helper's dependent is NOT listed" "$T/bg0" \
            '^test/core_lang/test_rules_swipl.jl$' 0
    else
        check "bgfiles: the planted helpers must be unchanged in this tree" 0 1
    fi
    cp "$rc_f" "$T/rules_common.jl.bak"
    echo "# bgfiles probe" >> "$rc_f"
    "$W" branch-gate-files > "$T/bg1" 2>&1; check "bgfiles: listed with a changed helper" 0 $?
    cp "$T/rules_common.jl.bak" "$rc_f"
    has "bgfiles: a changed helper brings in its UNCHANGED dependent" "$T/bg1" \
        '^test/core_lang/test_rules_swipl.jl$' 1
    has "…every one (test_softcut.jl)" "$T/bg1" '^test/core_lang/test_softcut.jl$' 1
    has "…but not the helper itself (it is no test file)" "$T/bg1" 'rules_common' 0
    has "…nor a file that does not include it" "$T/bg1" '^test/core_lang/test_unify.jl$' 0
    cp "$man_f" "$T/manifest.bak"
    echo "# bgfiles probe" >> "$man_f"
    LOGICKERNEL_BRANCH_GATE_CI_ONLY=none "$W" branch-gate-files > "$T/bg2" 2>&1
    "$W" branch-gate-files > "$T/bg3" 2>&1
    cp "$T/manifest.bak" "$man_f"; rm -f "$T/manifest.bak"
    has "bgfiles: TRANSITIVE — manifest → static_analysis_body.jl → test_static_analysis.jl" \
        "$T/bg2" '^test/test_static_analysis.jl$' 1
    has "…which the gate leaves to CI (JET, Aqua, AllocCheck)" "$T/bg3" '^test/test_static_analysis.jl$' 0
}

# THE BRANCH-GATE'S TIME BUDGET (user, 2026-10-14 night): the selection is estimated from each
# file's last recorded time; within the budget it runs in full, over it the gate keeps the tree-wide
# gates and the directly changed test files and logs how many it left to CI. A planted helper
# change makes the selection large (as `_bgfiles_cases`); the times are planted (LOGICKERNEL_FILE_TIMES).
_bgbudget_cases() {
    local rc_f="$ROOT/test/core_lang/rules_common.jl" full nfull ndirect
    # the selection against HEAD, so the planted line is the ONLY change: against merge-base(origin/main) a branch
    # that itself edits test_rules_swipl.jl keeps it as a DIRECT change, and "an unchanged dependent trimmed" cannot
    # hold — the case would then test the branch, not the trimming
    local -x LOGICKERNEL_GATE_BASE=HEAD
    cp "$rc_f" "$T/rules_common.jl.bak"
    echo "# bgbudget probe" >> "$rc_f"
    : > "$T/times"
    "$W" branch-gate-files > "$T/bb_all" 2>&1
    nfull=$(grep -c . "$T/bb_all")
    LOGICKERNEL_FILE_TIMES="$T/times" LOGICKERNEL_BRANCH_GATE_DEFAULT_S=1 LOGICKERNEL_BRANCH_GATE_BUDGET_S=100000 \
        "$W" branch-gate-plan > "$T/bb_in" 2> "$T/bb_in_err"
    check "bgbudget: under budget, the plan is produced" 0 $?
    cmp -s "$T/bb_all" "$T/bb_in"; check "bgbudget: …and runs the whole selection ($nfull files)" 0 $?
    has "…saying it is within the budget" "$T/bb_in_err" "within the 100000s budget: all of them" 1
    LOGICKERNEL_FILE_TIMES="$T/times" LOGICKERNEL_BRANCH_GATE_DEFAULT_S=60 LOGICKERNEL_BRANCH_GATE_BUDGET_S=10 \
        "$W" branch-gate-plan > "$T/bb_over" 2> "$T/bb_over_err"
    check "bgbudget: over budget, the plan is produced" 0 $?
    has "bgbudget: …the tree-wide gates kept" "$T/bb_over" '^test/test_type_discipline.jl$' 1
    has "…a helper's unchanged dependent trimmed" "$T/bb_over" '^test/core_lang/test_rules_swipl.jl$' 0
    ndirect=$(grep -c . "$T/bb_over")
    has "…and the count left to CI logged ($((nfull - ndirect)))" "$T/bb_over_err" \
        "over budget: $((nfull - ndirect)) files left to CI" 1
    has "…naming each" "$T/bb_over_err" "left to CI: test/core_lang/test_rules_swipl.jl" 1
    # the estimate reads the RECORDED time: one planted record makes an otherwise small plan exceed it
    printf 'test/core_lang/test_rules_swipl.jl\t5000\n' > "$T/times"
    LOGICKERNEL_FILE_TIMES="$T/times" LOGICKERNEL_BRANCH_GATE_DEFAULT_S=1 LOGICKERNEL_BRANCH_GATE_BUDGET_S=1000 \
        "$W" branch-gate-plan > "$T/bb_rec" 2> "$T/bb_rec_err"
    has "bgbudget: a recorded 5000 s puts the plan over a 1000 s budget" "$T/bb_rec_err" "over budget" 1
    cp "$T/rules_common.jl.bak" "$rc_f"
}

# THE DAEMON GUARD (user, 2026-10-14, after the machine stalled with four daemons up, three idle for
# hours in other worktrees): `start` REFUSES while another checkout's daemon runs and names it; a
# daemon EXITS after LOGICKERNEL_WARM_IDLE_S with no request; every daemon and capped run sits in ONE
# slice, lk-warm.slice (10G, no swap), where the kernel kills past the budget and the rest survives.
# Another checkout's daemon is a DECOY: a unit by the daemons' name, run in $T.
_guard_cases() {
    systemctl --user show-environment > /dev/null 2>&1 || { echo "  (guard: no user systemd here — skipped)"; return 0; }
    local unit decoy="logickernel-warm-decoy$$" dpid cg
    unit="logickernel-warm-$(printf '%s' "$ROOT" | md5sum | cut -c1-8)"
    echo 'println("ok")' > "$T/ok.jl"
    # LOCAL ONLY (user, 2026-10-14): on a GitHub runner the budget is OFF — no slice, and a 1 GB
    # budget that would cut the workers to 1 does not bound them; switched on, it does
    local lib=". \"$ROOT/tools/lib_evidence.sh\""
    [ -z "$(env -u LOGICKERNEL_SHARED_BUDGET GITHUB_ACTIONS=true bash -c "$lib; _lk_slice")" ]
    check "budget: OFF on a GitHub runner — no slice" 0 $?
    env -u LOGICKERNEL_SHARED_BUDGET GITHUB_ACTIONS=true LOGICKERNEL_SLICE_MEM_MAX=1G \
        bash -c "$lib; _shard_count" > "$T/sc1" 2>&1
    has "budget: …and the worker count is not bounded by it" "$T/sc1" "budget off" 1
    LOGICKERNEL_SHARED_BUDGET=1 GITHUB_ACTIONS=true LOGICKERNEL_SLICE_MEM_MAX=1G \
        bash -c "$lib; _shard_count" > "$T/sc2" 2>&1
    has "budget: LOGICKERNEL_SHARED_BUDGET=1 turns it on there — the count bounded by the budget" \
        "$T/sc2" "budget -\?[0-9]* (shared budget headroom" 1
    tail -1 "$T/sc2" > "$T/sc2n"
    has "…to 1 worker" "$T/sc2n" "^1$" 1
    export LOGICKERNEL_SHARED_BUDGET=1                   # the rest exercises it, on a runner too
    "$W" stop > /dev/null 2>&1
    systemd-run --user --unit="$decoy" --collect --quiet --working-directory="$T" sleep 600
    dpid=$(systemctl --user show "$decoy" -p MainPID --value)
    "$W" start > "$T/g1" 2>&1; check "guard: start is REFUSED while another checkout's daemon runs (exit 6)" 6 $?
    has "…naming its pid" "$T/g1" "pid $dpid," 1
    has "…its worktree" "$T/g1" "worktree $T," 1
    has "…its age and rss" "$T/g1" "age [0-9:-]*, rss [0-9.]* GB" 1
    systemctl --user is-active --quiet "$decoy"; check "…the other daemon is NOT stopped" 0 $?
    ! systemctl --user is-active --quiet "$unit"; check "…and this one is not started" 0 $?
    # PARALLEL MUTANT WORKERS (D-0077 item 6): the opt-in LOGICKERNEL_WARM_SIBLING_MUTANTS=1 excuses only a
    # daemon that sits in a MUTANT worktree (its .warm/MUTANT_WORKTREE marker), never an ordinary checkout's
    LOGICKERNEL_WARM_SIBLING_MUTANTS=1 "$W" start > /dev/null 2>&1
    check "guard: the sibling opt-in does not excuse an ordinary checkout's daemon (exit 6)" 6 $?
    # A SECOND DAEMON (audit D-0114): LOGICKERNEL_WARM_SECOND=1 lets this checkout's daemon start beside
    # ONE other, only with LOGICKERNEL_WARM_SECOND_MIN_GB available, in a slice of its own (lk-warm2.slice)
    LOGICKERNEL_WARM_SECOND=1 LOGICKERNEL_WARM_SECOND_MIN_GB=100000 "$W" start > "$T/g2" 2>&1
    check "second: refused without the memory it needs (exit 6)" 6 $?
    has "…saying how much it needs" "$T/g2" "needs 100000 GB available" 1
    systemd-run --user --unit="${decoy}two" --collect --quiet --working-directory="$T" sleep 600
    LOGICKERNEL_WARM_SECOND=1 LOGICKERNEL_WARM_SECOND_MIN_GB=0 "$W" start > "$T/g3" 2>&1
    check "second: refused beside TWO other daemons, never a third (exit 6)" 6 $?
    systemctl --user stop "${decoy}two" > /dev/null 2>&1
    LOGICKERNEL_WARM_SECOND=1 LOGICKERNEL_WARM_SECOND_MIN_GB=0 "$W" start > "$T/g4" 2>&1
    check "second: starts beside ONE other daemon with the memory there" 0 $?
    has "…saying so, naming the other" "$T/g4" "SECOND daemon (D-0114)" 1
    [ "$(systemctl --user show "$unit" -p Slice --value)" = lk-warm2.slice ]
    check "second: …in its own slice, lk-warm2.slice, so pressure kills it before the first lane" 0 $?
    "$W" stop > /dev/null 2>&1
    systemctl --user stop "$decoy" > /dev/null 2>&1
    mkdir -p "$T/sibling/.warm"; echo "$ROOT" > "$T/sibling/.warm/MUTANT_WORKTREE"
    systemd-run --user --unit="${decoy}sib" --collect --quiet --working-directory="$T/sibling" sleep 600
    env -u LOGICKERNEL_WARM_SIBLING_MUTANTS "$W" start > /dev/null 2>&1
    check "guard: a mutant worktree's daemon refuses a start WITHOUT the opt-in (exit 6)" 6 $?
    LOGICKERNEL_WARM_SIBLING_MUTANTS=1 "$W" start > /dev/null 2>&1
    check "guard: …and does not refuse a parallel mutant worker WITH it" 0 $?
    "$W" stop > /dev/null 2>&1
    systemctl --user stop "${decoy}sib" > /dev/null 2>&1
    systemctl --user stop "$decoy" > /dev/null 2>&1
    "$W" start > /dev/null 2>&1; check "guard: once it is stopped, start succeeds" 0 $?
    "$W" start > /dev/null 2>&1; check "guard: …and THIS checkout's running daemon is not refused" 0 $?
    # the shared budget: the daemon in the slice, the slice's limits effective in its cgroup
    [ "$(systemctl --user show "$unit" -p Slice --value)" = lk-warm.slice ]
    check "budget: the daemon runs in lk-warm.slice" 0 $?
    cg=$(systemctl --user show lk-warm.slice -p ControlGroup --value)
    [ -n "$cg" ] && [ "$(cat "/sys/fs/cgroup$cg/memory.max")" = 10737418240 ]
    check "budget: …whose memory.max is 10G" 0 $?
    [ -n "$cg" ] && [ "$(cat "/sys/fs/cgroup$cg/memory.swap.max")" = 0 ]
    check "budget: …with no swap" 0 $?
    # past a slice's budget the kernel kills INSIDE it, and the shell that started the job survives.
    # A small nested slice (lk-warm-probe.slice sits inside lk-warm.slice); the control: the same
    # job, outside it, completes.
    cat > "$T/hog.sh" <<'SH'
. "$1/tools/lib_evidence.sh"
s=$(_lk_slice) || exit 90
[ "$2" = in ] || s=""
# shellcheck disable=SC2086
systemd-run --user --scope --quiet $s -p MemorySwapMax=0 python3 -I -c 'b = b"x" * (600 << 20); print(len(b))'
echo "rc=$?"
SH
    LOGICKERNEL_SLICE=lk-warm-probe.slice LOGICKERNEL_SLICE_MEM_MAX=200M bash "$T/hog.sh" "$ROOT" out > "$T/g3" 2>&1
    has "budget: the control — 600 MB outside the slice completes" "$T/g3" "rc=0" 1
    LOGICKERNEL_SLICE=lk-warm-probe.slice LOGICKERNEL_SLICE_MEM_MAX=200M bash "$T/hog.sh" "$ROOT" in > "$T/g3" 2>&1
    check "budget: the shell that started an over-budget job SURVIVES" 0 $?
    has "budget: …and the job, 600 MB in a 200 MB slice, is KILLED (137)" "$T/g3" "rc=137" 1
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/lk-warm-probe.slice"
    systemctl --user daemon-reload
    # the idle exit: a daemon with a 3 s limit serves a request, then exits by itself
    "$W" stop > /dev/null 2>&1
    local log0                                          # session.log is appended: read only this run's
    log0=$(wc -l < "$ROOT/.warm/session.log" 2>/dev/null || echo 0)
    LOGICKERNEL_WARM_IDLE_S=3 "$W" start > /dev/null 2>&1; check "idle: a daemon starts with a 3 s idle limit" 0 $?
    "$W" send "$T/ok.jl" > /dev/null 2>&1; check "idle: …serves a request" 0 $?
    for _ in $(seq 1 60); do systemctl --user is-active --quiet "$unit" || break; sleep 1; done
    ! systemctl --user is-active --quiet "$unit"; check "idle: …then EXITS by itself" 0 $?
    tail -n +"$((log0 + 1))" "$ROOT/.warm/session.log" > "$T/g4"
    has "…saying why (in this run's log lines)" "$T/g4" "WARM LANE IDLE EXIT: no request for 3 s" 1
    [ ! -f "$ROOT/.warm/ready" ]; check "…and leaves no ready marker" 0 $?
    "$W" start > /dev/null 2>&1; check "idle: …and the lane starts again" 0 $?
    unset LOGICKERNEL_SHARED_BUDGET
}

_cap_cases() {
    systemd-run --user --scope true > /dev/null 2>&1 || { echo "  (cap: no user systemd here — skipped)"; return 0; }
    _pids='cat /sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/pids.max'
    check "cap: warm.sh's own work runs under TasksMax 512" 0 \
        "$([ "$(env -u LOGICKERNEL_TASKS_CAPPED "$W" locked bash -c "$_pids")" = 512 ]; echo $?)"
    check "cap: …LOGICKERNEL_TASKS_MAX sets it" 0 \
        "$([ "$(env -u LOGICKERNEL_TASKS_CAPPED LOGICKERNEL_TASKS_MAX=37 "$W" locked bash -c "$_pids")" = 37 ]; echo $?)"
    check "cap: …a nested call stays in the outer scope" 0 \
        "$([ "$(env -u LOGICKERNEL_TASKS_CAPPED LOGICKERNEL_TASKS_MAX=37 "$W" locked "$W" locked bash -c "$_pids")" = 37 ]; echo $?)"
    # run_tests.sh runs no command of ours, so a systemd-run shim on PATH records how it re-ran itself
    mkdir -p "$T/shim"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$T/shim.log" "$(command -v systemd-run)" > "$T/shim/systemd-run"
    chmod +x "$T/shim/systemd-run"
    : > "$T/shim.log"
    env -u LOGICKERNEL_TASKS_CAPPED LOGICKERNEL_TASKS_MAX=37 PATH="$T/shim:$PATH" \
        "$ROOT/tools/run_tests.sh" /nonexistent.jl > /dev/null 2>&1
    has "cap: …and run_tests.sh re-runs itself under TasksMax" "$T/shim.log" "scope --quiet -p TasksMax=37 .*tools/run_tests.sh /nonexistent.jl" 1
}

_stale_cases() {
# preflight RECOVERS from a stale daemon (user, 2026-10-04: "make the gate recover, not just
# detect") — and never suppresses a NOT CHECKED. Both ways:
#   (a) a method the daemon holds but no src/ file defines (as Revise leaves a deleted one): STALE,
#       the daemon restarts, the preflight reruns once — and PASSES;
#   (b) a method loaded FROM SOURCE under a name no syntax tree shows (`@eval` of a built name): the
#       classifier calls it STALE, the daemon restarts — and it is still NOT CHECKED: a REAL failure;
#   (c) a method defined in source by name: REAL at once, the preflight FAILS, and no restart.
stale="_preflight_probe_stale_$$"
printf 'Core.eval(LogicKernel, :(%s(x::Int) = x))\nisdefined(LogicKernel, :%s) || error("not planted")\n' \
    "$stale" "$stale" > "$T/stale.jl"
"$W" send "$T/stale.jl" > "$T/out" 2>&1; check "stale: a daemon-only method is planted" 0 $?
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
# Since 1dada85 the manifest's coverage runs in the fast check, BEFORE the static gate: a
# daemon-only method is caught there, as a leftover (defined in no src/ file — the same STALE rule),
# and the restart happens there (_checks_fresh). Measured 2026-10-14: before that rule the fast
# check called it NOT IN THE MANIFEST and nothing restarted — these cases failed, 13 of them.
check "stale: a daemon-only method restarts the daemon, and the rerun PASSES" 0 $?
has "…classified a leftover" "$T/pf" "A DAEMON LEFTOVER (defined in no src/ file.*$stale" 1
has "…restarting the daemon once" "$T/pf" "DAEMON LEFTOVERS .*restarting the warm lane once" 1
has "…and the rerun passed" "$T/pf" "preflight: PASS" 1
printf 'isdefined(LogicKernel, :%s) && error("still there")\n' "$stale" > "$T/gone.jl"
"$W" send "$T/gone.jl" > "$T/out" 2>&1; check "…the restart cleared it" 0 $?

ti="$ROOT/src/term_interface.jl"
cp "$ti" "$T/term_interface.jl.bak"
gen="_preflight_probe_gen_$$"
printf '\n@eval $(Symbol("_preflight_probe_gen_", %s))(x::Int) = x + 1\n' "$$" >> "$ti"
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
check "real: a source method no syntax tree shows still FAILS after the restart" 1 $?
has "…the daemon was restarted once" "$T/pf" "DAEMON LEFTOVERS .*restarting the warm lane once" 1
has "…and the failure reported REAL after it" "$T/pf" "still FAILS after a daemon restart" 1
has "…naming the method" "$T/pf" "still there after a daemon restart.*$gen" 1
cp "$T/term_interface.jl.bak" "$ti"

real="_preflight_probe_real_$$"
printf '\n%s(x::Int) = x + 1\n' "$real" >> "$ti"
"$W" restart > /dev/null 2>&1          # the daemon may hold the previous case's method
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
check "real: a method defined in source by name FAILS at once" 1 $?
has "…classified REAL (not in the manifest, no leftover)" "$T/pf" "  NOT IN THE MANIFEST: $real" 1
has "…with NO restart" "$T/pf" "restarting the warm lane once" 0
cp "$T/term_interface.jl.bak" "$ti"
cmp -s "$T/term_interface.jl.bak" "$ti"; check "src/term_interface.jl is restored" 0 $?
}

# (user, 2026-10-16) the daemon REFUSES to start when LogicKernel loads from ANOTHER checkout
# (warm_session.jl's pkgdir assertion — a Manifest path elsewhere would serve this tree's requests
# with that tree's src/): a second root — this tree's tools/, a Project.toml of its own, its
# Manifest's LogicKernel entry pointing at $ROOT — refuses by the assertion's own verdict, and the
# client exits non-zero as soon as the unit dies (the fixture pays two loads: the precompile check
# and the daemon's own, ~40 s; the bound is on the client's detection, not on Julia). A mutation
# target: the comparison made always-true leaves a daemon up, and the case fails.
_refuse_cases() {
    mkdir -p "$T/root2/tools"
    cp "$ROOT"/tools/*.sh "$ROOT"/tools/*.jl "$ROOT/tools/SWIPL_VERSION" "$T/root2/tools/"
    ln -s "$ROOT/packages" "$T/root2/packages"       # the swipl pin's plunit check runs first (line 70)
    printf '[deps]\nLogicKernel = "%s"\n' "$(sed -n 's/^uuid = "\(.*\)"$/\1/p' "$ROOT/Project.toml")" > "$T/root2/Project.toml"
    # this tree's Manifest with ITS OWN LogicKernel entry (if any — a locally developed one has
    # `path = "."`; CI's, freshly instantiated, has none) replaced by one at $ROOT: both sides
    awk '/^\[\[deps\.LogicKernel\]\]$/ {skip = 1; next} skip && /^\[/ {skip = 0} !skip' "$ROOT/Manifest.toml" > "$T/root2/Manifest.toml"
    _r2_deps=$(sed -n '/^\[deps\]$/,/^$/p' "$ROOT/Project.toml" | sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*) *=.*/"\1"/p' | paste -sd, -)
    printf '\n[[deps.LogicKernel]]\ndeps = [%s]\npath = "%s"\nuuid = "%s"\nversion = "%s"\n' "$_r2_deps" "$ROOT" \
        "$(sed -n 's/^uuid = "\(.*\)"$/\1/p' "$ROOT/Project.toml")" "$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROOT/Project.toml")" \
        >> "$T/root2/Manifest.toml"
    [ "$(grep -c '^\[\[deps\.LogicKernel\]\]$' "$T/root2/Manifest.toml")" = 1 ]; check "refuse: the fixture's Manifest has ONE LogicKernel entry" 0 $?
    grep -q "^path = \"$ROOT\"\$" "$T/root2/Manifest.toml"; check "…pointing at this checkout" 0 $?
    local s; s=$(date +%s)
    "$T/root2/tools/warm.sh" start > "$T/r2" 2>&1; check "start REFUSES a LogicKernel loaded from another checkout" 1 $?
    [ $(( $(date +%s) - s )) -lt 120 ]; check "…and the client fails fast (under 120 s, two loads included)" 0 $?
    has "…by the assertion's own verdict" "$T/root2/.warm/session.log" "REFUSED to start — LogicKernel was loaded from" 1
    has "…which the client shows" "$T/r2" "REFUSED to start" 1
    echo 'println("x")' > "$T/s2.jl"
    "$T/root2/tools/warm.sh" send "$T/s2.jl" > /dev/null 2>&1; check "…and starts no daemon" 3 $?
    "$T/root2/tools/warm.sh" stop > /dev/null 2>&1            # a mutant that started one: no daemon left behind
    rm -rf "$T/root2"
}

# (2026-10-17) the daemon sees the UPSTREAM CHECKOUTS its caller names (`LOGICKERNEL_UPSTREAM_<REPO>`):
# a unit gets only what it is passed, and CI's daemon saw none — `inventory` failed there on the
# coverage block ("needs every upstream checkout the headers name") while every local run passed.
# The probe variable is set on the start; the daemon must read it back. Then the inventory cases.
_inventory_cases() {
    "$W" stop > /dev/null 2>&1
    LOGICKERNEL_UPSTREAM_TESTPROBE=forwarded "$W" start > /dev/null ||
        { check "upstream: the lane starts" 0 1; return; }
    echo 'println("upstream probe: ", get(ENV, "LOGICKERNEL_UPSTREAM_TESTPROBE", "absent"))' > "$T/up.jl"
    "$W" send "$T/up.jl" > "$T/up" 2>&1; check "upstream: the probe snippet runs" 0 $?
    has "upstream: the daemon sees the caller's LOGICKERNEL_UPSTREAM_* variables" "$T/up" "upstream probe: forwarded" 1
# (user, 2026-10-16) `inventory` rewrites the generated blocks IN THE DAEMON and runs port_check after:
# on a tree whose inventory is current it exits 0, says so, and changes no generated file
    _inv_before=$(cat docs/port_inventory.md docs/architecture.md | md5sum)
    "$W" inventory > "$T/inv" 2>&1; _inv_rc=$?; check "inventory: exits 0 on a current tree" 0 $_inv_rc
    [ "$_inv_rc" -eq 0 ] || { echo "       inventory said:"; grep -vE '^\s+@|^Stacktrace|^\s*\[' "$T/inv" | tail -6 | sed 's/^/       | /'; }
    has "…runs port_check after the rewrite" "$T/inv" "inventory: port_check clean" 1
    [ "$(cat docs/port_inventory.md docs/architecture.md | md5sum)" = "$_inv_before" ]; check "…and changes no generated file" 0 $?
}

if [ "${1:-}" = inventory ]; then                    # the upstream forwarding + the inventory cases alone
    _inventory_cases
    "$W" stop > /dev/null 2>&1
    echo "test_warm (inventory): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
if [ "${1:-}" = refuse ]; then                       # the pkgdir assertion's refusal alone (no daemon)
    _refuse_cases
    echo "test_warm (refuse): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
if [ "${1:-}" = stale ]; then                        # the stale-daemon recovery cases alone
    "$W" stop > /dev/null 2>&1
    "$W" start > /dev/null || { echo "test_warm: the lane did not start"; exit 1; }
    _stale_cases
    echo "test_warm (stale): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
# _probe_commit TREE MESSAGE — a commit object of TREE for the selection cases, with an identity of its own: a
# CI runner has none (2026-10-18: `commit-tree` failed there, "empty ident name", the base came out EMPTY and
# the gate fell back to its default base — one case red, the other green for the wrong reason)
_probe_commit() {
    GIT_AUTHOR_NAME="test_warm probe" GIT_AUTHOR_EMAIL="probe@test-warm.invalid" \
        GIT_COMMITTER_NAME="test_warm probe" GIT_COMMITTER_EMAIL="probe@test-warm.invalid" \
        git -C "$ROOT" commit-tree "$1" -m "$2"
}
# (2026-10-17) THE GATE BASE: a gate branch of COMMITTED steps runs what its commits changed. A synthetic
# base commit — HEAD's tree with ONE test file's blob replaced (no history needed: a CI checkout at depth 1
# has none) — brings that file into the selection; HEAD as the base leaves it out (both sides)
_gatebase_cases() {
    local f=test/core_lang/test_sort.jl idx="$T/gb.idx" blob tree base
    git -C "$ROOT" diff --quiet HEAD -- "$f" || { check "gatebase: $f must be unchanged in this tree" 0 1; return; }
    blob=$(printf '# a different blob\n' | git -C "$ROOT" hash-object -w --stdin)
    GIT_INDEX_FILE="$idx" git -C "$ROOT" read-tree HEAD
    GIT_INDEX_FILE="$idx" git -C "$ROOT" update-index --cacheinfo "100644,$blob,$f"
    tree=$(GIT_INDEX_FILE="$idx" git -C "$ROOT" write-tree)
    base=$(_probe_commit "$tree" "gatebase probe")
    rm -f "$idx"
    [ -n "$base" ]; check "gatebase: the synthetic base commit is made" 0 $?
    [ -n "$base" ] || return
    LOGICKERNEL_GATE_BASE="$base" "$W" branch-gate-files > "$T/gb1" 2>&1; check "gatebase: the list is produced" 0 $?
    has "gatebase: a file a commit changed is selected" "$T/gb1" "^$f\$" 1
    LOGICKERNEL_GATE_BASE=HEAD "$W" branch-gate-files > "$T/gb0" 2>&1
    has "…and not with HEAD as the base" "$T/gb0" "^$f\$" 0
    has "…the tree-wide gates in both" "$T/gb0" '^test/test_type_discipline.jl$' 1
}

# (2026-10-17, audit D-0001) THE NO-SWIPL PASS: LOGICKERNEL_NO_SWIPL=1 runs a file as CI's Pkg.test does —
# every test file's swipl check yields nothing, swipl is not required, the inert-testset guard is on. A testset
# asserting only inside its swipl branch FAILS that pass by the guard's verdict, and passes a normal run.
_noswipl_cases() {
    local probe="$ROOT/test/core_lang/test_zz_noswipl_probe_$$.jl"
    cat > "$probe" <<'JLP'
using Test
const _NSP_SWIPL = (get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl"))
@testset "a differential that asserts only beside swipl" begin
    if _NSP_SWIPL !== nothing
        @test 1 + 1 == 2
    end
end
JLP
    "$W" file "$probe" > "$T/ns1" 2>&1; check "noswipl: the probe passes a normal run" 0 $?
    LOGICKERNEL_NO_SWIPL=1 "$W" file "$probe" > "$T/ns2" 2>&1; check "noswipl: …and FAILS the no-swipl pass" 1 $?
    has "…by the inert-testset guard" "$T/ns2" "INERT TESTSETS" 1
    has "…saying it ran without swipl" "$T/ns2" "WITHOUT swipl (LOGICKERNEL_NO_SWIPL=1)" 1
    rm -f "$probe"
    LOGICKERNEL_NO_SWIPL=1 "$W" file test/core_lang/test_compare_cells.jl > "$T/ns3" 2>&1
    check "noswipl: a file that asserts on the kernel side too passes it" 0 $?
}

if [ "${1:-}" = noswipl ]; then                      # the no-swipl pass alone
    "$W" start > /dev/null || { echo "test_warm: the lane did not start"; exit 1; }
    _noswipl_cases
    echo "test_warm (noswipl): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
# (2026-10-18) THE SOURCE-TO-TEST MAP: a src definition the diff since the gate base touches selects the test files
# that NAME it. A synthetic base — HEAD's tree with src/pl-prims.jl's `compareStandard_cells` definition line
# altered — must select test_compare_cells.jl (it names the function), and HEAD as the base must not
_srcmap_cases() {
    local src=src/pl-prims.jl f=test/core_lang/test_compare_cells.jl idx="$T/sm.idx" blob tree base
    git -C "$ROOT" diff --quiet HEAD -- "$src" "$f" || { check "srcmap: $src and $f must be unchanged in this tree" 0 1; return; }
    [ "$(git -C "$ROOT" show "HEAD:$src" | grep -c '^compareStandard_cells(')" = 1 ] ||
        { check "srcmap: the definition anchor is there once" 0 1; return; }
    blob=$(git -C "$ROOT" show "HEAD:$src" | sed 's/^compareStandard_cells(\(.*\)$/compareStandard_cells(\1   # an older text/' |
        git -C "$ROOT" hash-object -w --stdin)
    GIT_INDEX_FILE="$idx" git -C "$ROOT" read-tree HEAD
    GIT_INDEX_FILE="$idx" git -C "$ROOT" update-index --cacheinfo "100644,$blob,$src"
    tree=$(GIT_INDEX_FILE="$idx" git -C "$ROOT" write-tree)
    base=$(_probe_commit "$tree" "srcmap probe")
    rm -f "$idx"
    [ -n "$base" ]; check "srcmap: the synthetic base commit is made" 0 $?
    [ -n "$base" ] || return
    LOGICKERNEL_GATE_BASE="$base" "$W" branch-gate-files > "$T/sm1" 2>&1; check "srcmap: the list is produced" 0 $?
    has "srcmap: a test naming a changed src definition is selected" "$T/sm1" "^$f\$" 1
    has "…and it is not itself changed" "$T/sm1" "^$src\$" 0
    LOGICKERNEL_GATE_BASE=HEAD "$W" branch-gate-files > "$T/sm0" 2>&1
    has "…not with HEAD as the base" "$T/sm0" "^$f\$" 0
}

if [ "${1:-}" = srcmap ]; then                       # the source-to-test map alone (no daemon)
    _srcmap_cases
    echo "test_warm (srcmap): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
if [ "${1:-}" = gatebase ]; then                     # the gate base's selection alone (no daemon)
    _gatebase_cases
    echo "test_warm (gatebase): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
if [ "${1:-}" = bgfiles ]; then                      # the branch-gate's file selection alone (no daemon)
    _bgfiles_cases
    echo "test_warm (bgfiles): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]; exit $?
fi
if [ "${1:-}" = bgbudget ]; then                     # the branch-gate's time budget alone (no daemon)
    trap '[ -f "$T/rules_common.jl.bak" ] && cp "$T/rules_common.jl.bak" "$ROOT/test/core_lang/rules_common.jl"; rm -rf "$T"' EXIT
    _bgbudget_cases
    echo "test_warm (bgbudget): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
if [ "${1:-}" = guard ]; then                        # the daemon guard alone: one daemon, idle exit, budget
    _guard_cases
    echo "test_warm (guard): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
if [ "${1:-}" = cap ]; then                          # the task-ceiling cases alone (no daemon)
    trap 'rm -rf "$T"' EXIT                            # nothing to stop: these never start the lane
    _cap_cases
    echo "test_warm (cap): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
if [ "${1:-}" = fast ]; then                         # the fast pre-check's planted-defect cases alone
    "$W" stop > /dev/null 2>&1
    "$W" start > /dev/null || { echo "test_warm: the lane did not start"; exit 1; }
    _fast_cases
    echo "test_warm (fast): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
if [ "${1:-}" = structs ]; then                      # the struct gate's cases alone (a mutation target)
    "$W" stop > /dev/null 2>&1
    "$W" start > /dev/null || { echo "test_warm: the lane did not start"; exit 1; }
    echo 'println("ok")' > "$T/ok.jl"
    _struct_cases
    echo "test_warm (structs): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi
if [ "${1:-}" = rss ]; then                          # the memory cases alone (a mutation target)
    "$W" stop > /dev/null 2>&1
    "$W" start > /dev/null || { echo "test_warm: the lane did not start"; exit 1; }
    echo 'println("ok")' > "$T/ok.jl"
    _rss_cases
    echo "test_warm (rss): $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
    exit
fi

"$W" stop >/dev/null 2>&1
echo 'println("x")' > "$T/s.jl"
"$W" send "$T/s.jl" > /dev/null 2>&1; check "no daemon: send exits 3" 3 $?

# the daemon's differentials judge against the swipl on its PATH: a swipl that is not the pin
# (a fake one first on PATH) refuses the start, and no daemon is left behind
mkdir -p "$T/fakebin"
printf '#!/bin/sh\necho "SWI-Prolog version 0.0.1 for x86_64-linux"\n' > "$T/fakebin/swipl"
chmod +x "$T/fakebin/swipl"
PATH="$T/fakebin:$PATH" "$W" start > /dev/null 2>&1; check "start REFUSES a swipl that is not the pin" 1 $?
"$W" send "$T/s.jl" > /dev/null 2>&1; check "…and starts no daemon" 3 $?

_unless_main _refuse_cases                           # the pkgdir assertion (user, 2026-10-16)

"$W" start || { echo "test_warm: the lane did not start"; exit 1; }

# preflight: a port_check violation (a src file with no header) fails it FAST, before the slow gate;
# the tree as it is passes (the pool is skipped here: LOGICKERNEL_PREFLIGHT_POOL=0)
probe_src="$ROOT/src/_preflight_probe_$$.jl"
printf 'x = 1\n' > "$probe_src"
s=$(date +%s)
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; check "preflight FAILS on a port_check violation" 1 $?
rm -f "$probe_src"
[ $(( $(date +%s) - s )) -lt 120 ]; check "…before the slow gate (fail fast)" 0 $?
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; _pf_rc=$?; check "preflight passes on the tree as it is" 0 $_pf_rc
[ "$_pf_rc" -eq 0 ] || { echo "       the preflight said:"; tail -15 "$T/pf" | sed 's/^/       | /'; }
has "…reaching the static-analysis gate (stubbed here: the tooling seam)" "$T/pf" "test_static_analysis.jl STUBBED" 1
has "…after a REAL fast static pre-check" "$T/pf" "fast static pre-check clean" 1
# the preflight runs the CURRENT tools/port_check.jl: an edit to the checker made after an earlier
# preflight (above) loaded it is seen — the checker's inventory end marker, renamed in place, makes
# it report the inventory section missing — and FAILS the next preflight BY THAT VERDICT (a daemon
# that kept the first checker passed M1's docs against the pre-M1 inventory format, 2026-10-04).
# The edit keeps the file Blue-formatted: a planted line that is not would fail the format check
# first, which proves nothing about this one (measured: the first version of this case did).
cp "$ROOT/tools/port_check.jl" "$T/port_check.jl.bak"
n=$(grep -c '^const INVENTORY_END = "<!-- END GENERATED -->"$' "$ROOT/tools/port_check.jl")
[ "$n" = 1 ]; check "…the checker edit's anchor is there once" 0 $?
sed -i 's/^const INVENTORY_END = "<!-- END GENERATED -->"$/const INVENTORY_END = "<!-- END GENERATED PROBE -->"/' "$ROOT/tools/port_check.jl"
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; check "preflight FAILS on an edited checker (no stale port_check)" 1 $?
has "…by the edited checker's own verdict" "$T/pf" "INVENTORY-MISSING.*END GENERATED PROBE" 1
has "…past the format check" "$T/pf" "preflight: Blue-clean" 1
cp "$T/port_check.jl.bak" "$ROOT/tools/port_check.jl" && rm -f "$T/port_check.jl.bak"
# a CHANGED test file that fails (an untracked one) is run, and fails the preflight — BY ITS OWN
# VERDICT: the file carries a valid header, so port_check passes and the failure is the test's
# (a first version had none, and passed through port_check alone: mutation MP3 survived)
probe_test="$ROOT/test/core_lang/test_preflight_probe_$$.jl"
printf '# ORIGINAL: a planted failing test (tools/test_warm.sh); never committed.\nusing Test\n@testset "planted" begin\n    @test 1 + 1 == 3\nend\n' > "$probe_test"
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; check "preflight FAILS on a failing changed test file" 1 $?
rm -f "$probe_test"
has "…past format and port_check" "$T/pf" "port_check clean" 1
has "…by that file's own failure" "$T/pf" "planted: Test Failed" 1

_unless_main _stale_cases

_unless_main _fast_cases
rm -f "$T/term_interface.jl.bak"
"$W" restart > /dev/null 2>&1

cat > "$T/ok.jl" <<'JL'
using Test
@testset "passes" begin @test 1 + 1 == 2 end
JL
"$W" send "$T/ok.jl" > "$T/out" 2>&1; check "a passing snippet exits 0" 0 $?

cat > "$T/bad.jl" <<'JL'
using Test
@testset "fails" begin @test 1 + 1 == 3 end
JL
"$W" send "$T/bad.jl" > "$T/out" 2>&1; check "a FAILING snippet exits 1" 1 $?
"$W" send "$T/ok.jl" > /dev/null 2>&1; check "…and the next one is judged afresh" 0 $?

# Revise: an edit to a tracked file is live in the NEXT snippet, with no restart
printf 'module LKWarmProbe\nf() = 1\nend\n' > "$T/probe.jl"
printf 'Revise.includet(raw"%s")\nLKWarmProbe.f() == 1 || error("stale")\n' "$T/probe.jl" > "$T/use1.jl"
"$W" send "$T/use1.jl" > "$T/out" 2>&1; check "a tracked file loads" 0 $?
sleep 1                                          # a new mtime for the file watcher
printf 'module LKWarmProbe\nf() = 2\nend\n' > "$T/probe.jl"
echo 'LKWarmProbe.f() == 2 || error("STALE: the edit was not revised")' > "$T/use2.jl"
"$W" send "$T/use2.jl" > "$T/out" 2>&1; check "an edit is revised before the next snippet" 0 $?
# (a same-signature redefinition is logged as a method DELETION plus its replacement, so any
# non-zero action count is the evidence — measured through the lane itself)
has "…and Revise's audit trail reports it" "$T/out" "revised: \([1-9][0-9]* eval\|0 eval(s), [1-9]\)" 1

# what Revise cannot propagate — a macro, a @generated function, a type alias — is detected, so the
# daemon re-evaluates the whole module; plain methods and value constants are not
printf 'macro m(x)\n    x\nend\n' > "$T/c_macro.jl"
printf '@generated g(x) = :(x)\n' > "$T/c_gen.jl"
printf 'const Clause{T} = clause{T, definition{T}}\n' > "$T/c_alias.jl"
printf 'f(x) = x + 1\nconst N = 3\nconst S = "a{b}"\n' > "$T/c_plain.jl"
cat > "$T/cls.jl" <<JL
Main._needs_module_revise(raw"$T/c_macro.jl") || error("a macro was not detected")
Main._needs_module_revise(raw"$T/c_gen.jl") || error("@generated was not detected")
Main._needs_module_revise(raw"$T/c_alias.jl") || error("a type alias was not detected")
Main._needs_module_revise(raw"$T/c_plain.jl") && error("plain methods and constants were flagged")
JL
"$W" send "$T/cls.jl" > "$T/out" 2>&1; check "macros, @generated and aliases force a module revise" 0 $?

# a FAILED revision refuses the snippet: it must not run at all
sleep 1
printf 'module LKWarmProbe\nf() = (\nend\n' > "$T/probe.jl"
echo 'println("SNIPPET RAN")' > "$T/ran.jl"
"$W" send "$T/ran.jl" > "$T/out" 2>&1; check "a failed revision exits 1" 1 $?
has "…says REVISE FAILED" "$T/out" "REVISE FAILED" 1
has "…and the snippet did NOT run" "$T/out" "SNIPPET RAN" 0
sleep 1
printf 'module LKWarmProbe\nf() = 3\nend\n' > "$T/probe.jl"
echo 'LKWarmProbe.f() == 3 || error("stale after the fix")' > "$T/use3.jl"
"$W" send "$T/use3.jl" > "$T/out" 2>&1; check "once fixed, the next snippet runs fresh" 0 $?

# `file`: a real term-generic test file runs on EVERY implementation, as the suite runs it
"$W" file test/core_lang/test_sort.jl > "$T/out" 2>&1; check "file: a passing test file exits 0" 0 $?
for impl in reference alt alt_interned; do
    has "file: …ran on [$impl]" "$T/out" "test_sort.jl \[$impl\]" 1
done
mkdir -p "$T/core_lang"
cat > "$T/core_lang/test_wfail.jl" <<'JL'
using Test, LogicKernel
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
@testset "wfail" begin @test kind(lk_sym(lk_term_type(Int64), :a)) === VAR end
JL
cp "$ROOT/test/term_under_test.jl" "$T/term_under_test.jl"
mkdir -p "$T/core_lang" && cp "$ROOT/test/core_lang/alt_term.jl" "$T/core_lang/alt_term.jl"
"$W" file "$T/core_lang/test_wfail.jl" > "$T/out" 2>&1; check "file: a FAILING test file exits 1" 1 $?

# THE LANE LOCK (2026-10-07): a RUN (preflight, evidence, `locked CMD`) holds the lane for its WHOLE
# run; its own calls pass, from subshells too, and anyone else's are REFUSED (exit 5) — a probe
# between a preflight's steps would change the daemon under it.
_wait_owner() {     # _wait_owner PID — until the lane's owner is PID (at most 30 s)
    for _ in $(seq 1 150); do
        [ "$(cat "$ROOT/.warm/run.owner" 2>/dev/null)" = "$1" ] && return 0
        sleep 0.2
    done
    return 1
}
"$W" locked sleep 20 > /dev/null 2>&1 &
holder=$!
_wait_owner "$holder"; check "lane: a run takes it" 0 $?
"$W" send "$T/ok.jl" > "$T/out" 2>&1; check "lane: a probe while a run holds it is REFUSED (exit 5)" 5 $?
has "…saying so" "$T/out" "REFUSED" 1
WARM_LOCK_OWNER=99999 "$W" send "$T/ok.jl" > "$T/out" 2>&1
check "lane: …and a forged owner marker bypasses nothing" 5 $?
WARM_RUN_LOCK_WAIT_S=2 "$W" locked true > "$T/out" 2>&1; check "lane: a second run is REFUSED too" 5 $?
wait "$holder"
"$W" send "$T/ok.jl" > "$T/out" 2>&1; check "lane: once the run ends, a probe runs" 0 $?
"$W" locked bash -c '"$0" send "$1" && ( "$0" send "$1" )' "$W" "$T/ok.jl" > "$T/out" 2>&1
check "lane: inside a run its own sends pass, from a subshell too (no self-deadlock)" 0 $?
LOGICKERNEL_PREFLIGHT_FAULT=format-empty LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1 &
pf=$!
_wait_owner "$pf"; check "lane: a preflight takes it" 0 $?
"$W" send "$T/ok.jl" > "$T/out" 2>&1; check "lane: a probe mid-preflight is REFUSED (exit 5)" 5 $?
wait "$pf"; check "…and the preflight's verdict is its own (the planted fault: exit 1)" 1 $?
has "…NO VERDICT, as planted" "$T/pf" "preflight: NO VERDICT" 1

# THE SEND LOCK (2026-10-07): two concurrent senders each get their OWN verdict and output — without
# it, the second overwrote the first's snippet and the first waited for a run never made (R1d: a
# preflight step "passed" with an empty log). A short timeout makes a lost run FAIL, not hang.
printf 'sleep(3); println("A-OUT")\n' > "$T/la.jl"
printf 'println("B-OUT")\n' > "$T/lb.jl"
( WARM_TIMEOUT_S=90 "$W" send "$T/la.jl" > "$T/la.out" 2>&1; echo $? > "$T/la.rc" ) &
sleep 1
WARM_TIMEOUT_S=90 "$W" send "$T/lb.jl" > "$T/lb.out" 2>&1; check "lock: the second of two concurrent senders gets its verdict" 0 $?
wait
check "lock: …and so does the first" 0 "$(cat "$T/la.rc")"
has "…the first its own output" "$T/la.out" "A-OUT" 1
has "…the second its own output" "$T/lb.out" "B-OUT" 1
has "…and not the first's" "$T/lb.out" "A-OUT" 0

# FAIL CLOSED (2026-10-07, after R1d's false green: a step "passed" with an EMPTY log, its run never
# made): a step whose output is empty, or lacks its own end marker, is a FAILURE whatever its exit
# code — `file` exits 4 (NO VERDICT), and the preflight fails. Faults injected by the TEST SEAMS
# (LOGICKERNEL_WARM_FAULT, LOGICKERNEL_PREFLIGHT_FAULT) after a real, passing run.
for fault in empty cut; do
    LOGICKERNEL_WARM_FAULT=$fault "$W" file test/core_lang/test_sort.jl > "$T/out" 2>&1
    check "file: a passing run whose output is $fault is NO VERDICT (exit 4)" 4 $?
    has "…saying so" "$T/out" "NO VERDICT" 1
done
"$W" file test/core_lang/test_sort.jl > "$T/out" 2>&1; check "…and the same run, whole, passes" 0 $?
for fault in format-empty format-cut; do
    s=$(date +%s)
    LOGICKERNEL_PREFLIGHT_FAULT=$fault LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
    check "preflight FAILS on a step log that is $fault" 1 $?
    has "…saying NO VERDICT" "$T/pf" "preflight: NO VERDICT" 1
    [ $(( $(date +%s) - s )) -lt 120 ]; check "…before the slow gate" 0 $?
done

_unless_main _rss_cases
_unless_main _noswipl_cases
echo 'println("ok")' > "$T/ok.jl"
_unless_main _struct_cases

# NO BACKTICK IN AN UNQUOTED HEREDOC (measured 2026-10-14): the snippets tools/warm.sh writes with
# `<<JL` expand `$ROOT`, so a backtick in their Julia text is COMMAND SUBSTITUTION. A comment naming
# `_checks_fresh` in backticks made expanding the snippet RUN that function, which expands the
# snippet again: a fork chain of 1558 processes before it was killed. Count them in every <<JL body.
_bt=$(awk '/<<JL$/{f=1; next} /^JL$/{f=0} f && /`/{n++} END{print n+0}' "$ROOT/tools/warm.sh")
check "no backtick inside an unquoted <<JL heredoc of tools/warm.sh (found $_bt)" 0 "$_bt"
_bt_fixture=$(printf 'cat > f <<JL\n# a `name` here\nJL\n' | awk '/<<JL$/{f=1; next} /^JL$/{f=0} f && /`/{n++} END{print n+0}')
check "…the count sees a planted backtick (the control)" 1 "$_bt_fixture"

# (user, 2026-10-16) an alternative type asked for a file that is not term-generic is REFUSED, never
# silently run on the reference type
"$W" file test/test_lint_globals.jl alt > "$T/ng" 2>&1; check "file: alt on a non-generic file is refused" 2 $?
has "…saying why" "$T/ng" "is not term-generic" 1

_unless_main _inventory_cases

# (user, 2026-10-16) `fmt` formats the changed .jl files IN PLACE (write mode): an untracked file
# written unformatted comes back Blue-formatted, and a second run rewrites nothing
_fm_probe="$ROOT/tools/zz_fmt_probe.jl"
printf 'f(x)=x+1\n' > "$_fm_probe"
"$W" fmt > "$T/fmt" 2>&1; check "fmt: exits 0" 0 $?
# (measured 2026-10-16: JuliaFormatter 2.14.0 keeps the source's spacing around `+`, cold and warm, under
# every style — `x+1` stays; a hand-written `x + 1` here failed two runs identically. Expected = measured.)
[ "$(cat "$_fm_probe")" = 'f(x) = x+1' ]; _fm_rc=$?; check "…and rewrote the changed file in place" 0 $_fm_rc
[ "$_fm_rc" -eq 0 ] || echo "       probe now: '$(cat "$_fm_probe")'; fmt said: $(tr '\n' '|' < "$T/fmt")"
has "…naming it" "$T/fmt" "fmt: formatted tools/zz_fmt_probe.jl" 1
"$W" fmt > "$T/fmt2" 2>&1; check "fmt: a second run exits 0" 0 $?
has "…and rewrites nothing" "$T/fmt2" "fmt: 0 file(s) rewritten" 1
rm -f "$_fm_probe"

_unless_main _guard_cases
_unless_main _cap_cases
_unless_main _bgfiles_cases
_unless_main _gatebase_cases
_unless_main _srcmap_cases
_unless_main _bgbudget_cases

if [ "$MAIN_ONLY" = 1 ]; then echo "test_warm (main): $pass passed, $fail failed"
else echo "test_warm: $pass passed, $fail failed"; fi
[ "$fail" -eq 0 ]
