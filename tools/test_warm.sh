#!/usr/bin/env bash
# tools/test_warm.sh — the warm lane's own tests (tools/warm.sh, tools/warm_session.jl), each judged
# by the EXIT CODE the lane returns, never by its printed text (user, 2026-10-03: "the lane's own
# mutation-proved tests"). Starts its own daemon and stops it.
#
#   tools/test_warm.sh          # exit 0 only if every case passes
#
# What a lane must never do, case by case: report a failure as success; run code Revise failed to
# load and present the result as fresh; run a file on fewer implementations than the suite does.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$ROOT/tools/warm.sh"
mkdir -p "$ROOT/.warm"
T="$(mktemp -d "$ROOT/.warm/test.XXXXXX")"
trap '[ -f "$T/term_interface.jl.bak" ] && cp "$T/term_interface.jl.bak" "$ROOT/src/term_interface.jl"; [ -f "$T/port_check.jl.bak" ] && cp "$T/port_check.jl.bak" "$ROOT/tools/port_check.jl"; "$W" stop >/dev/null 2>&1; rm -rf "$T"; rm -f "$ROOT"/src/_preflight_probe_*.jl "$ROOT"/test/core_lang/test_preflight_probe_*.jl' EXIT
pass=0 fail=0
check() {   # check NAME WANT_EXIT GOT_EXIT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: exit $3, want $2"; fi
}
has() {     # has NAME FILE PATTERN WANT(1 present / 0 absent)
    if grep -q "$3" "$2"; then got=1; else got=0; fi
    check "$1" "$4" "$got"
}

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

"$W" start || { echo "test_warm: the lane did not start"; exit 1; }

# preflight: a port_check violation (a src file with no header) fails it FAST, before the slow gate;
# the tree as it is passes (the pool is skipped here: LOGICKERNEL_PREFLIGHT_POOL=0)
probe_src="$ROOT/src/_preflight_probe_$$.jl"
printf 'x = 1\n' > "$probe_src"
s=$(date +%s)
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; check "preflight FAILS on a port_check violation" 1 $?
rm -f "$probe_src"
[ $(( $(date +%s) - s )) -lt 120 ]; check "…before the slow gate (fail fast)" 0 $?
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1; check "preflight passes on the tree as it is" 0 $?
has "…having run the static-analysis gate" "$T/pf" "test_static_analysis.jl" 1
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
check "stale: its NOT CHECKED restarts the daemon, and the rerun PASSES" 0 $?
has "…classified STALE" "$T/pf" "STALE (defined in no src/ file.*$stale" 1
has "…restarting the daemon once" "$T/pf" "STALE DAEMON — restarting" 1
has "…and the rerun passed" "$T/pf" "preflight: PASS" 1
printf 'isdefined(LogicKernel, :%s) && error("still there")\n' "$stale" > "$T/gone.jl"
"$W" send "$T/gone.jl" > "$T/out" 2>&1; check "…the restart cleared it" 0 $?

ti="$ROOT/src/term_interface.jl"
cp "$ti" "$T/term_interface.jl.bak"
gen="_preflight_probe_gen_$$"
printf '\n@eval $(Symbol("_preflight_probe_gen_", %s))(x::Int) = x + 1\n' "$$" >> "$ti"
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
check "real: a source method no syntax tree shows still FAILS after the restart" 1 $?
has "…the daemon was restarted once" "$T/pf" "STALE DAEMON — restarting" 1
has "…and the failure reported REAL after it" "$T/pf" "still FAILS after a daemon restart" 1
has "…naming the method" "$T/pf" "NOT CHECKED for dispatch: $gen" 1
cp "$T/term_interface.jl.bak" "$ti"

real="_preflight_probe_real_$$"
printf '\n%s(x::Int) = x + 1\n' "$real" >> "$ti"
"$W" restart > /dev/null 2>&1          # the daemon may hold the previous case's method
LOGICKERNEL_PREFLIGHT_POOL=0 "$W" preflight > "$T/pf" 2>&1
check "real: a method defined in source by name FAILS at once" 1 $?
has "…classified REAL" "$T/pf" "REAL (still defined in src/.*$real" 1
has "…with NO restart" "$T/pf" "STALE DAEMON" 0
cp "$T/term_interface.jl.bak" "$ti"
cmp -s "$T/term_interface.jl.bak" "$ti"; check "src/term_interface.jl is restored" 0 $?
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

echo "test_warm: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
