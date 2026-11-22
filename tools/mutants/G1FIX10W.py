# ORIGINAL: G1-FIX-10's own (D-0971 item 4 follow-up): the mutant that the time-free handled-signal rows of test_g1c_wiring_swipl.jl
# (`_handled_signals_exact`, `handled == n_pending + (gc_percentage > 0.2 ? 1 : 0)`) must catch; the code is a port of pl-setup.c handleSignals
# (`done` counted per handled signal, pl-setup.c:1225-1270 at the pin 18168e62). Run by hand with
# `tools/mutate.sh run-in-tree tools/mutants/G1FIX10W.py test/core_lang/test_g1c_wiring_swipl.jl -- G1FIX10W-H1`.
# H1: handleSignals reports one signal fewer than it handled. KILL: the two rows `@test handled == want && handled >= 1` of the testset
#   "G1-C: raiseGcSignal!, handleSignals and PL_handle_signals" (both, one per call: handleSignals and PL_handle_signals).
# MEASURED (G1-FIX-10, reference, W alone): BOTH rows fail under H1, test_g1c_wiring_swipl.jl:271 (handleSignals) and :278 (PL_handle_signals),
#   `Expression: handled == want && handled >= 1`; the unmutated file is 103/103 on reference, alt and alt_interned.
# TARGETS (audit D-0238): the files that call handleSignals / PL_handle_signals or serve a signal through them (as G1C.py's SIG list).
# `old` counted EXACTLY once in src/pl-setup.jl; `new` != `old`; no duplicate id. RE-FIT `old` if `tools/warm.sh fmt` rewraps.
W = "test/core_lang/test_g1c_wiring_swipl.jl"
TARGETS = [
    W,
    "test/core_lang/test_g1gc_safe_points.jl",
    "test/core_lang/test_gc_driver.jl",
    "test/core_lang/test_gc_vmi_state.jl",
    "test/core_lang/test_gc_frames.jl",
    "test/core_lang/test_gc_upstream_swipl.jl",
    "test/core_lang/test_gc_stats_swipl.jl",
    "test/core_lang/test_goal_clause.jl",
    "test/core_lang/test_metacall_control.jl",
    "test/core_lang/test_assert_cells.jl",
    "test/db/test_db.jl",
]


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("G1FIX10W-H1 handleSignals reports one signal fewer than it handled (KILL W: both `handled == want` rows of the G1-C signals testset)",
      "src/pl-setup.jl",
      "    done != 0 && updateAlerted(ld)                  # if ( done ) updateAlerted(LD);\n    return done\n",
      "    done != 0 && updateAlerted(ld)                  # if ( done ) updateAlerted(LD);\n    return done - 1\n",
      TARGETS),
]
