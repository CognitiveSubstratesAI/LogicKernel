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
5. (the next commit, from the cap-hit state) rows sa82-sa83 added, pins refilled from two byte-identical swipl 10.1.19 runs,
   plus evidence/SETARG/SETARG.py.draft and this handoff.

## LEFT (in order; a fresh agent)
a. `cp evidence/SETARG/SETARG.py.draft tools/mutants/SETARG.py`; replace the first lines by a header as tools/mutants/MOD3b.py
   (format note, anchors need a re-fit after fmt, TARGETS reason; NOT LISTED: `ensureGlobalSpace(ld, 1)` before the trailed
   assignment (only at the stack limit), `_value_word!` in `unify_vp` (a slot's side value never occurs for a Prolog goal's
   argument), the three identical `A1, A2, A3 = ...` lines); delete `evidence/SETARG/SETARG.py.draft`; validate with a
   throwaway python3 -I + runpy checker (old occurs once via count, new != old, ids unique, targets exist). 27 mutants, 2 equivalent
   (A5, E4). The anchors were NOT yet counted: expect some to fail (C2's anchor has aligned spaces; B7's trailing space).
b. docs/architecture.md: an appended block (setarg group, nshare in duplicate_term, the frozen-after-assign DIVERGES).
c. test/static_analysis_manifest.jl: entries LAST, appended: `LK.pl_setarg3_va`, `LK.pl_nb_setarg3_va`, `LK.pl_nb_linkarg3_va`
   (shape of the neighbouring `pl_*_va` entries, over T), `LK.setarg`, `LK.unify_vp`, `LK.may_share_in_duplicate`,
   `LK.duplicate_term`, `LK.share_for_duplicate_cells`, the 4-arg `LK.mark_for_duplicate_cells` (Tuple{PL_local_data{T}, Int, Int, cp_options}).
d. Stale comment: test/core_lang/test_trail_words.jl:6 says "no setarg/3" (a comment); re-word it positively in the docs commit.
Commit estimate: 3 more (mutants, docs, manifest).

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
6. Not done (not on this step): b_set_dict/nb_set_dict/nb_link_dict.

## Gate order (the rules): fmt (warm.sh send for committed files), inventory, check, rows on all three term types,
type discipline, `tools/pkgtest_way.sh test/core_lang/test_setarg_swipl.jl`, the mutants branch, branch-gate, term grep, gate push on a FRESH name.
