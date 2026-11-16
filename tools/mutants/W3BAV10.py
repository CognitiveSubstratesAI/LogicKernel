# ORIGINAL: W3b-AV10's mutant list — no swipl-devel counterpart.
# tools/mutants/W3BAV10.py — the mutation battery of W3b-AV10 (pl-write.c writeAttVar's `attributes(portray)` arm: the call of
# '$attvar':portray_attvar/1 with the stream, the wakeup state and the portray nesting set aside), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur
# EXACTLY once), `new`, `targets`, optional `equivalent`. Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY
# once in src/pl-write.jl at the commit that adds this list (a text count by a python3 -I checker, no Julia); RE-FIT any `old` that
# `tools/warm.sh fmt` rewraps. NOTHING here has run on the kernel: each KILL names the row EXPECTED to kill it, the battery decides.
# KILL: test/core_lang/test_write_cells.jl, the testset "an attributed variable written with attributes(portray)" (rows at15-at27,
# pinned from swipl 10.1.20; the older at01-at14 rows hold the other attributes(...) modes and the default flag).
# TARGETS (audit D-0238): the mutated arm runs only where a write has the `portray` attribute mode: a search of test/*/*.jl and tools/
# for `attributes(portray)`, `portray_attvar` and the write_attributes flag finds test_write_cells.jl (the rows above) and
# test_set_flag_swipl.jl, test_prolog_flag_swipl.pl, which set or read the FLAG only and never write an attributed variable. The
# ignore-mode and print/1 rows of the same file (at03, at05, at11, at24) run the branch's guard, so the guard mutant (W3B-G1) has them too.
# NOT MUTATED (no row can reach it, with the reason):
#   * the `rc = true` conversion after a call that fails without an exception: boot/attvar.pl's portray_attvar/1 has no failing path
#     (its attribute walk and the `~w = ...` fallback always succeed or raise), and it is a system predicate no program redefines.
#   * `halt_cleaning <= CLN_PROLOG`: no row writes an attributed variable during the halt sequence (the halt rows of test_wr2_swipl.jl
#     write no attributed variable).
#   * `restoreWakeup(ld, wstate)`: a foreign frame left open is seen by no row (as in WR2C's writeAtom portray branch).
#   * `wstate === nothing && return false` (saveWakeup's out-of-memory answer): no row reaches it.
TW = ["test/core_lang/test_write_cells.jl"]
TARGETS = TW
W = "src/pl-write.jl"
MUTANTS = [
    dict(id="W3B-M1 the predicate is looked up in `user`, not `$attvar` (existence error; every portray row)", file=W, targets=TW,
         old='mk_sym(T, :portray_attvar), 1, lookupModule(gd, mk_sym(T, Symbol("\\$attvar")))',
         new='mk_sym(T, :portray_attvar), 1, lookupModule(gd, mk_sym(T, :user))'),
    dict(id="W3B-M2 the call does not pass its exception (PL_Q_PASS_EXCEPTION dropped; at21)", file=W, targets=TW,
         old="        rc = PL_call_predicate(\n            gd, ld, nothing, PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION, pred, av\n        )\n",
         new="        rc = PL_call_predicate(\n            gd, ld, nothing, PL_Q_NODEBUG, pred, av\n        )\n"),
    dict(id="W3B-M3 the hook's output stays on the current output, not the write's stream (at26, at27)", file=W, targets=TW,
         old="        old = Scurout(ld)\n        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = options.out    # Scurout = options->out\n",
         new="        old = Scurout(ld)\n"),
    dict(id="W3B-M4 the current output is not put back after the call (at27: write(done) goes to the closed null stream)", file=W, targets=TW,
         old="        end\n        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = old",
         new="        end\n        old"),
    dict(id="W3B-M5 the portray nesting is not left (the counter keeps every earlier row's call: at25 reaches the limit before 100 nested braces)", file=W, targets=TW,
         old="        leavePortray(ld)\n        return rc\n",
         new="        return rc\n"),
    dict(id="W3B-M6 the portray nesting is not entered (at25: the recursion has no limit; the verdict is a timeout or a stack error)", file=W, targets=TW,
         old="        enterPortray(ld) || return false\n        wstate = saveWakeup(ld, true)\n",
         new="        wstate = saveWakeup(ld, true)\n"),
    dict(id="W3B-M7 the result is true whatever the call answered (at21: the thrown oops does not stop the write)", file=W, targets=TW,
         old="        leavePortray(ld)\n        return rc\n",
         new="        leavePortray(ld)\n        return true\n"),
    dict(id="W3B-G1 the portray arm is entered in every mode (the ignore rows at03, at05, at24 call portray_attvar/1)", file=W, targets=TW,
         old="    elseif _ison(options, PL_WRT_ATTVAR_PORTRAY) && options.gd.halt_cleaning <= CLN_PROLOG\n",
         new="    elseif options.gd.halt_cleaning <= CLN_PROLOG\n"),
]
