# ORIGINAL: E1R's mutant list; the code is the retirement of the e5 stand-in `_release_frozen!` (G1-E, audit D-0979 (2)): upstream never lowers
# `frozen_bar` before a thread's end (pl-gvar.c:62-70 at 18168e62: `destroyGlobalVars` sets it to NULL; the only other writers are freezeGlobal,
# pl-gvar.c:53-56, and the collector's relocation, pl-gc.c:1135-1159 and :5082), so an outermost query's close leaves
# gTop = max(frozen_bar, mark.globaltop) (pl-incl.h:2253 `Undo`, pl-wam.c:1632) and the ball is the collector's.
# tools/mutants/E1R.py -- three mutants, each LOWERS THE BAR: the e5 release's effect put back as mutations (E1R-1: only the bar at the outermost
# close; E1R-2: the whole old body of the release, the bar, mark_bar, gTop, the attvar chain and the value table; E1R-3: the bar lowered by Undo!).
# Format: tools/mutate_drive.py's (as SL1.py): `id`, `file`, `old` (must occur EXACTLY once in its file; checked with python3 -I at the tip),
# `new` != `old`, `targets`. Killed by test/core_lang/test_ball_cells.jl (named in each id's KILL); the rest of TARGETS are the other files that
# run an outermost query with a throw or an Undo! over a frozen region (audit D-0238): ENG2.py's list at the step's parent.
# RETIRED WITH THE FUNCTION (the catalogues that mutated its code are DELETED in the same commit; each mutant's kill meaning and where it went):
#   ENG2A.py ENG2A-M1..M5 (the early return while a global variable sat on the stack, the scan of the values, its `>` boundary, the open foreign
#     frames' marks, the base frame): they guarded the release's own decision when a global variable's value lay above its target. Upstream has
#     no such decision: the value is below the bar whatever it is, so the meaning "a global variable's value survives the close" is pinned by
#     test_ball_cells.jl's ENG2a rows (1)-(4) (values read back across closes and discards) and killed by E1R-1/E1R-2 (the close lowering
#     the bar and gTop cuts the value's region).
#   ENG2.py ENG2-M1..M8 (the release's reading of each open foreign frame's references): upstream's reader is the collector's mark_term_refs
#     (pl-gc.c:1016-1055), mutated by G1GC3.py (G1GC3-R2: the last reference of every frame is skipped; the ENG2-M4 meaning). The other
#     seven (header words read, the walk's start and stop, the slot index, the `>=` refusal, the refusal removed) mutated a refusal that does
#     not exist upstream; the refusal's meaning "a live reference above a mark is not cut" is pinned by test_ball_cells.jl's condition-2 and
#     ENG2 rows and killed by E1R-3 (the bar lowered by Undo!).
#   AV1.py AV1-C4 (the release keeps the chain's links above its target): the release's reclaim_attvars is gone; Undo!'s own cut stays mutated
#     by AV1-C2/C3.
# Verdicts: written by the battery, not yet run (G1-E was edit-only).
TB = "test/core_lang/test_ball_cells.jl"
TF = [
    TB, "test/core_lang/test_stack_limit.jl", "test/core_lang/test_gvar_swipl.jl", "test/foreign/test_query_answers.jl",
    "test/core_lang/test_attvar_words.jl", "test/core_lang/test_exception.jl", "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_findall_swipl.jl", "test/foreign/test_query.jl",
    "test/files/test_qlf_swipl.jl", "test/core_lang/test_firstboot_swipl.jl", "test/core_lang/test_unify_swipl.jl"
]
TARGETS = TF


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("E1R-1 the outermost close lowers the frozen bar to 0 (KILL ball_cells condition 3: `fb == fb_pre` in the four collector-off loops and the collector-on row; ENG2a (2), (4): `fb4r == fb4`)",
      "src/pl-wam.jl",
      "        restore_after_query(ld, qf)             # (upstream's bar stays: nothing lowers it at the outermost close, G1-E)\n",
      "        restore_after_query(ld, qf)             # (upstream's bar stays: nothing lowers it at the outermost close, G1-E)\n"
      "        ld.query == 0 && ld.exception_term == 0 && (ld.frozen_bar = 0)\n",
      TF),
    m("E1R-2 the outermost close does what the retired release did: bar, mark_bar and gTop lowered to the query's mark, the attvar chain and the value table with it (KILL ball_cells condition 3: `gt == fb && after > 0`; ENG2a (2): `grow2 > 0 && fb2 > fb2s && gt2 == fb2`)",
      "src/pl-wam.jl",
      "        restore_after_query(ld, qf)             # (upstream's bar stays: nothing lowers it at the outermost close, G1-E)\n",
      "        qm = ld.choices[q.choice].mark\n"
      "        restore_after_query(ld, qf)             # (upstream's bar stays: nothing lowers it at the outermost close, G1-E)\n"
      "        if ld.query == 0 && ld.exception_term == 0 && ld.frozen_bar != 0\n"
      "            ld.frozen_bar = 0\n"
      "            ld.mark_bar = qm.saved_bar\n"
      "            if close && ld.gTop > qm.globaltop\n"
      "                reclaim_attvars(ld, qm.globaltop)\n"
      "                ld.gTop = qm.globaltop\n"
      "                _truncate_vtable!(ld)\n"
      "            end\n"
      "        end\n",
      TF),
    m("E1R-3 Undo! lowers the bar to the mark before it takes max(frozen_bar, mark) (KILL ball_cells condition 2: `ld.gTop == bar && ld.frozen_bar == bar`, ENG2 (1)-(3); the white-box 'Undo! to an older mark keeps it'; test_attvar_words' frozen-region row)",
      "src/pl-inline.jl",
      "    ngtop = max(ld.frozen_bar, m.globaltop)     # Word ngtop = max(LD->frozen_bar, m->globaltop.as_ptr)\n",
      "    ld.frozen_bar = min(ld.frozen_bar, m.globaltop)\n"
      "    ngtop = max(ld.frozen_bar, m.globaltop)     # Word ngtop = max(LD->frozen_bar, m->globaltop.as_ptr)\n",
      TF),
]
