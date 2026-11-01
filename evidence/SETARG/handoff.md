# SETARG: setarg/3, nb_setarg/3, nb_linkarg/3 (pl-prims.c, swipl-devel cbf4e1896275)

Edit-only writer (no Julia run). Branch wip/setarg off origin/main 1286e62, linear, not pushed.
Need: boot/bags.pl (nb_setarg/3, boot_needs.tsv) and, after this step, b_set_dict/nb_set_dict/nb_link_dict
(pl-dict.c setdict -> setarg; the dict agent ports those, NOT this step).

## Verified on origin/main (name and behaviour search, 2026-11-01)
- setarg/3, nb_setarg/3, nb_linkarg/3, `setarg(` helper and SETARG_* constants: NOT ported (one comment hit only).
- Present: `TrailAssignment!` (src/pl-wam.jl:171), `freezeGlobal!` (src/pl-inline.jl:949), `unify_ptrs_cells`
  (src/pl-prims.jl:948), `PL_get_size_ex` (src/pl-error.jl:799), `copy_term_refs` + `cp_options`
  (src/pl-copyterm.jl; duplicate_term/2 is on main, WITHOUT upstream's nshare/share).
- G1 (src/pl-gvar.jl, wip/dstack-a3): NOT needed. freezeGlobal is already in pl-inline.jl.

## Plan (upstream pl-prims.c at the pin; Julia site)
1. This plan.
2. pl-copyterm.c duplicate_term (:864) with nshare/share: `cp_options` gets `nshare`, `share` (src/pl-copyterm.jl:39),
   `mark_for_duplicate_cells` a 4-arg form that sets the ground mark on a shared term (upstream mark_for_duplicate
   :201-250, share_for_duplicate :187), `do_copy_term_cells` passes `options`, new `duplicate_term(ld, in, copy, nshare, share)`.
   Needed by setarg's `may_share_in_duplicate` (nb_setarg keeps the old value's compound shared).
3. pl-prims.c unify_vp (:2790), may_share_in_duplicate (:2810), setarg (:2825-2886), setarg_t (:2893),
   PRED_IMPL setarg/nb_setarg/nb_linkarg (:2903-2923), SETARG_BACKTRACKABLE=0x1/SETARG_LINK=0x2 (pl-prims.h:101),
   table entries before `$skip_list` (upstream order :6669-6671). Site: end of src/pl-prims.jl, before the table.
4. Oracle rows test/core_lang/test_setarg_swipl.jl (generator + driver + pins from two byte-identical swipl 10.1.19 runs).
5. tools/mutants/SETARG.py (>= 2.5 per code commit: >= 8).
6. docs/architecture.md appended block.  7. test/static_analysis_manifest.jl entries (LAST).
Commit estimate: 7 (plan, copyterm, setarg, rows, mutants, docs, manifest).
