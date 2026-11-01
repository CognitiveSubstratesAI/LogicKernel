# SETARG: setarg/3, nb_setarg/3, nb_linkarg/3 (pl-prims.c, swipl-devel cbf4e1896275)

Edit-only writer (no Julia run). Branch wip/setarg off origin/main 1286e62, linear, NOT pushed.
Need: boot/bags.pl (nb_setarg/3, boot_needs.tsv) and, after this step, b_set_dict/nb_set_dict/nb_link_dict (pl-dict.c
setdict -> `setarg(ld, argn, term, value, SETARG_BACKTRACKABLE/SETARG_LINK)`; the dict agent ports those, NOT this step).

## State (commits on wip/setarg)
1. dd2b80b plan.
2. 4f0c4ba duplicate_term's nshare/share (src/pl-copyterm.jl: `cp_options(flags, nshare, share)` + `cp_options(flags)`,
   `share_for_duplicate_cells`, `mark_for_duplicate_cells` 4-arg form, `duplicate_term(ld, in, copy, nshare, share)`).
   The 3-argument `mark_for_duplicate_cells` (manifest entry on main) is kept and forwards.
3. 69272ed setarg (src/pl-prims.jl before the table): SETARG_BACKTRACKABLE/LINK, `unify_vp`, `may_share_in_duplicate`,
   `setarg(ld, argn, term, value, flags)`, `setarg_t`, `pl_setarg3_va`/`pl_nb_setarg3_va`/`pl_nb_linkarg3_va`, three table
   entries before `$skip_list`.
4. 4e0581d rows test/core_lang/test_setarg_swipl.jl (sa01-sa81) + evidence/SETARG/{gen_rows.py,setarg_rows.pl,setarg_driver.pl,setarg_rows.out}.
5. 8d29951 rows sa82-sa83 added, pins refilled from two byte-identical swipl 10.1.19 runs, the mutant draft and the first handoff.

## DONE since the cap-hit (all committed on wip/setarg, nothing pushed, nothing run)
6. b764052 tools/mutants/SETARG.py (27 mutants, 2 equivalent A5/E4, header as MOD3b.py; the draft file removed). TCOPY targets now also
   include test_same_term_swipl.jl (s_dup) and test_attvar_wakeup.jl (duplicate_term/2 on an attvar). Checked with a python3 -I + runpy
   checker: every `old` occurs once in the wip/setarg worktree, new != old, ids unique, targets exist. Anchors need a re-fit after fmt.
7. 233573e docs/architecture.md SETARG section (before "Still to come") + test_trail_words.jl:6 comment re-worded.
8. efd797f manifest block appended at the end of `_manifest_index` (test/static_analysis_manifest.jl): unify_vp, may_share_in_duplicate,
   setarg, setarg_t, share_for_duplicate_cells, 4-arg mark_for_duplicate_cells, 5-arg duplicate_term, the three `pl_*3_va`.
9. this handoff.
Nothing is left to write for SETARG. The rest is the gate (order below).

## Overlap with G1 (checked with `git diff`/`git show` on refs wip/g1 1c13c79 and wip/dstack-a3 eb6c6fc, nothing checked out)
- G1 (commit "duplicate_term" in src/pl-copyterm.jl, +8 -1) adds `duplicate_term(ld, in, copy)` (3-argument, `copy_term_refs(ld, in, copy,
  cp_options(COPY_ATTRS))`) BEFORE `pl_duplicate_term2_va`, and changes that predicate's line to call it. wip/dstack-a3 carries the same diff.
- It is NOT an equivalent of nshare/share: G1's DIVERGES comment says "no nshare/share arguments". Nothing to drop. My 5-argument
  `duplicate_term(ld, in, copy, nshare, share)` (after `pl_duplicate_term2_va`) is a second method of the same function: no name or method
  collision (different arity), and G1's `cp_options(COPY_ATTRS)` / `cp_options(0x00)` (G1-P1 mutant) use my kept 1-argument constructor.
- TEXT collision: yes, one hunk. G1's edit of `pl_duplicate_term2_va` (the `copy_term_refs(...) || return FFALSE` line, its insertion just above)
  is within 3 context lines of where 4f0c4ba inserts the 5-argument method (after the same function), so a cherry-pick / rebase of one onto the
  other conflicts in that area of src/pl-copyterm.jl. Resolution: keep both methods; G1's comment line "DIVERGES: no `nshare`/`share`" becomes stale
  and should read "the 3-argument form is duplicate_term/2's and setval_duplicate's (nshare 0)". Optional: G1's 3-argument body may forward
  to `duplicate_term(ld, in, copy, 0, 0)`; not needed.
- Stacking order: G1 FIRST (it is the older and already has CI-side batteries), then SETARG rebased on it; resolve the one hunk, and update G1's
  DIVERGES comment in the SETARG rebase (4f0c4ba). Manifest: G1 has `(LK.duplicate_term, Tuple{LD, Int, Int}, false)`; mine is
  `Tuple{LD, Int, Int, Int, Int}`: two entries, both kept. G1.py's G1-P1 `old` (`cp_options(COPY_ATTRS))`) still occurs once with my 5-argument
  method present (its call reads `cp_options(COPY_ATTRS, nshare, share))`); SETARG.py E6/E7 do not match G1's text either.
- docs/architecture.md and the manifest are shared appended files: expect textual (not semantic) conflicts at the end of `_manifest_index`
  and before "## Still to come".

## Flags for the audit
1. TIER-1 CONTACT: none in the sense of the trail itself (TrailAssignment!, Undo!, freezeGlobal! are called, not edited), BUT
   the step ASSIGNS into global cells under the trail/undo regime and moves `frozen_bar`/`mark_bar` (freezeGlobal!):
   alloc pins x3 are NOT required by the rules (no Tier-1 file or pl-global.jl changed), the pre-gate reviewer may still look.
2. DIVERGES (representation): (a) positions stay put, so `term`'s compound is not re-read after duplicate_term /
   ensureGlobalSpace; (b) `freezeGlobal!` is called AFTER `unify_vp` (assigning a side value allocates its value-table entry,
   which the frozen region must hold); (c) `storage(*v) == STG_GLOBAL` is: a compound, an attributed variable, a value-table
   word or a side word; (d) `ensureGlobalSpace(ld, 1)` for the one cell TrailAssignment! allocates.
3. `_release_frozen!` (src/pl-inline.jl) lowers frozen_bar/gTop when the outermost query ends; its comment says REVISIT at
   nb_setval. A nb_setarg value inside a term that outlives the query is not a case (terms die with the query).
4. Compile risks to read first (nothing ran): `PL_get_size_ex` returns `Union{Nothing,Int}`; `unify_ptrs_cells(ld, -(value+1), apos)`;
   the `||`/`&&` mix in `setarg`'s freeze condition; `ld.slots[share + 1] = w` in `may_share_in_duplicate`; `cp_options` is now a
   3-field struct (callers in pl-fli.jl:789,801 use the 1-arg constructor, kept); table entries `PL_extension("setarg", ...)`.
5. Rows to read first if the kernel differs: sa56-sa58 (nshare sharing), sa43-sa47 (freeze), sa68-sa77 and sa82-sa83 (attvar, cycles).
   sa51 of the first draft (nb_linkarg accumulating [X|L]) was DROPPED: it depends on bindings that backtracking undoes (undefined).
6. Not done (not on this step): b_set_dict/nb_set_dict/nb_link_dict. They follow in wip/dict (pl-dict.c setdict): call
   `setarg(ld, argn, term, value, SETARG_BACKTRACKABLE)` for b_set_dict and `SETARG_BACKTRACKABLE`/`SETARG_LINK` as the C code passes
   (nb_set_dict: 0, nb_link_dict: SETARG_LINK) once SETARG is under them in the stack.

## Gate order (the rules): fmt (warm.sh send for committed files), inventory, check, rows on all three term types,
type discipline, `tools/pkgtest_way.sh test/core_lang/test_setarg_swipl.jl`, the mutants branch, branch-gate, term grep, gate push on a FRESH name.

## UNRUN (everything): no Julia ran. Not compiled: src/pl-copyterm.jl, src/pl-prims.jl, the manifest block, the rows (81+2) on any term type,
the 27 mutants (text-count checked only), fmt, inventory. No daemon is held by this branch. Gate: SETARG after G1 in the stack (see Overlap).
