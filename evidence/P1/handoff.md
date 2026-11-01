# P1: pl-prims.c term inspection (R2 boot C predicates, audit D-0306 items 2-3) -- handoff

Worktree ~/code/lk-p1, branch wip/p1 (off main 584476f). EDIT-ONLY writer: nothing here is compiled or run.
Pin: swipl-devel cbf4e1896275 (`src/pl-prims.c` at the pin). Oracle: swipl 10.1.19. Inventory owner key: 'NEW P1'.

## Verified predicate list
Checked on origin/main (`git grep -F` over src/*.jl: only the atom names `arg` / `nonground` in pl-atom.jl,
`PL_factorize_term` (the C-API function, pl-prims.jl:1294) and `functor/3` are present; the predicates below have NO
PRED_IMPL port and no `PL_extension` entry in `PL_predicates_from_prims`, src/pl-prims.jl:3591) and that the boot
at the pin calls them (`git grep` on boot/*.pl at cbf4e1896275):

| predicate | upstream (pin) | boot caller | Julia home |
|---|---|---|---|
| arg/3 (NONDETERMINISTIC) | pl-prims.c:2704 (+ `get_arg_integer_ex` :2655) | 13 boot files | src/pl-prims.jl |
| compound_name_arity/3 | pl-prims.c:2508 | 9 boot files | src/pl-prims.jl |
| compound_name_arguments/3 | pl-prims.c:3161 | 9 boot files | src/pl-prims.jl |
| subsumes_term/2 (ISO) | pl-prims.c:3954 | dwim.pl:423, init.pl:3732, syspred.pl:1590 | src/pl-prims.jl |
| $factorize_term/3 | pl-prims.c:1485 | expand.pl:1134, toplevel.pl:2175, topvars.pl:101 | src/pl-prims.jl (over `PL_factorize_term`, :1294) |
| term_singletons/2 | pl-prims.c:3741 | expand.pl:542 | src/pl-prims.jl |
| $term_multitons/2 | pl-prims.c:3752 | toplevel.pl:1775 | src/pl-prims.jl |
| $term_size/3 | pl-prims.c:993 | topvars.pl:206 | src/pl-prims.jl |
| is_most_general_term/1 | pl-prims.c:3850 | syspred.pl:1720, tabling.pl:548, :2352 | src/pl-prims.jl |

`arg/3` in a clause body compiles inline (`B_ARG_*`, src/pl-comp.jl:2268, refused there: V9); the callable form is the
predicate, used by `call(arg, ...)`, `maplist(arg(N), ...)` and a body arg/3 that is not inline. They relate as
upstream's: the inline forms are pl-comp.c's, this is pl-prims.c's PRED_IMPL.

## Moved to R3 (the boot never reaches them; evidence: no boot/*.pl call at the pin)
nonground/2, functor/4, `$filled_array`/4 (not in the inventory), term_factorized/3,4 (pl-bisim.c): library-only.
setarg/3, nb_setarg/3, nb_linkarg/3, duplicate_term/5: the SETARG step (wip/setarg-r), not this one.

## Groups (commit order; <= 12 commits, D-0295)
1. [x] plan -- acbe3e0
2. [x] arg/3 + compound_name_arity/3 + get_arg_integer_ex + both registrations -- f4f36e8
3. [x] compound_name_arguments/3 + registration -- 9480b0f
4. [x] subsumes_term/2 (subsumes_cells) + registration -- 013827c
5. [x] $factorize_term/3 + registration -- 1d16c9f
6. [x] $term_size/3 (term_size_cells, _indirect_cells calibrated on swipl 10.1.19) + registration -- f122e53
7. [x] is_most_general_term/1 (is_most_general_term_cells, _tv_marked/_tv_mark!) + registration -- f19deef
8. [x] term_singletons/2, $term_multitons/2: TV_SINGLETON/TV_SHARED constants, term_variables_loop_first_cells,
   term_variables_to_termv_first_cells, term_variables() dispatch, 2 registrations -- the commit carrying this handoff
9. [x] rows test/core_lang/test_p1_swipl.jl p001-p176 + evidence/P1/{gen_rows.py,p1_driver.pl,p1_rows.pl,p1_rows.out} -- 8f0c9d6
   (swipl 10.1.19, two byte-identical runs; p174-p176 are the mutant-killing rows added in 4295937; the kernel-only
   `$expr/n` testset is the last testset of the file; the pins were regenerated with `python3 -I gen_rows.py <file> [--fill]`)
10. [x] tools/mutants/P1.py (39 mutants, validated: old once, new != old, targets exist; not run) -- 4295937
11. [x] this commit: FIXED: arg/3 variable rename (`rc` -> `got` in pl_arg3_va, src/pl-prims.jl) + this handoff
12. [ ] NOT STARTED, ONE commit (the cap binds: fold the two): docs/architecture.md block (append, a P1 block: the nine
    predicates, upstream lines, the 4 DIVERGES below) AND test/static_analysis_manifest.jl entries (append): pl_arg3_va,
    pl_compound_name_arity3_va, pl_compound_name_arguments3_va, pl_subsumes_term2_va, pl_factorize_term3_va,
    pl_term_size3_va, pl_term_singletons2_va, pl_term_multitons2_va, pl_is_most_general_term1_va (each over T as the
    neighbours list theirs) plus the helpers get_arg_integer_ex, subsumes_cells, term_size_cells, _indirect_cells,
    _limbs64, is_most_general_term_cells, _tv_marked, _tv_mark!, term_variables_loop_first_cells,
    term_variables_to_termv_first_cells (read how the neighbouring entries are written first).
    AFTER that commit the series is 12 commits (the cap): the dispatcher folds nothing further.

## Gate order (for the dispatcher)
fmt (committed files through `warm.sh send`), inventory, check, rows on all three term types, type discipline,
`tools/pkgtest_way.sh test/core_lang/test_p1_swipl.jl`, mutants/P1 branch, branch-gate, term grep, gate push on a fresh name.
No Tier-1 file is touched so far (pl-prims.jl only); alloc pins x3 are not needed unless that changes.

## Flags
- Tier-1 contact: none (src/pl-prims.jl only; pl-global.jl struct NOT changed: the FIRST marks of term_singletons are a
  local Set{Int}, the variable marks of is_most_general_term the existing ld.tv_seen). `term_variables()` (all callers
  of term_variables/2,3, term_attvars) gained a dispatch line: the mutants TARGETS must name their test files.
- Unrun, uncompiled: every piece. First compile may show: `number_kind`/`NUM_*`/`string_value` reachable from
  pl-prims.jl, `ld.walk_agenda` use, `PL_error(ld, ERR_REPRESENTATION, atom)` form, `unRef` on a slot word,
  `Set{Int}` push, the one-line `if ... end` forms.
- DIVERGES to judge (audit): (1) `$term_size/3` indirect sizes computed from the value-table entry (formula in
  `_indirect_cells`), representation-only; (2) term_variables_to_termv_first_cells fails when count > maxcount where upstream
  filters a reference it never made (only `$term_multitons` with a proper-list second argument shorter than the variables);
  (3) compound_name_arity/arguments on a `$expr/n` compound answer name `$expr` and all children (as PL_get_name_arity);
  (4) arg/3 does no GC/shift flags.
- arg/3 in a clause body is the inline B_ARG form (pl-comp.jl:2268, refused there: V9); this is the callable predicate.
- Moved to R3 on evidence (boot/*.pl at the pin has no call): nonground/2, functor/4, $filled_array/4, term_factorized/3,4.
- SETARG dependency: none (nothing here needs duplicate_term/5 or a SETARG helper).
- Known kernel fact: `catch((T = foo(), R = T), ...)` engine defect: build `foo()` in a helper clause in rows.

## State at the hand-back (coder 2)
- Compile re-read done (by reading the neighbouring code, nothing run): number_kind/NUM_*/string_value/rational_value/
  bigint_value/integer_is_int64/int64_value are in src/default_term.jl and used module-wide; `unRef(w::word)` is
  `valPtr(w)` (pl-inline.jl:39) so `unRef(ld.slots[..]) in firsts` reads the position of a `makeRefG` word; the
  `PL_error(ld, ERR_REPRESENTATION, atom)` form exists (pl-error.jl); `ld.walk_agenda`, `skip_list_cells` (4-tuple),
  `PL_get_name_arity`, `_PL_get_arg`, `PL_retry`, `PL_foreign_context` match their definitions. No fix was needed
  except the cosmetic `rc` -> `got` in pl_arg3_va (type stability), committed in commit 11.
- The rows file lists its own UNVERIFIED rows in a comment above the case list (cyclic terms, call_cleanup, rdiv, a
  wide string, the size_t representation error of a huge arity, `[]` as a compound name, `foo()` from a clause head).
- A swipl 10.1.19 build dependence: a bare variable as the first argument of `$term_multitons/2`, and that predicate
  with a proper list SHORTER than the variables as second argument, cannot be answered by the oracle here: neither has
  a row (the mutant list names the second as the DIVERGES case that no row reaches).
- Flags for the audit (unchanged): (1) `$term_size/3` sizes of numbers and strings come from the value-table entry
  (`_indirect_cells`), representation-only; (2) term_variables_to_termv_first_cells fails when count > maxcount
  (upstream filters a reference it never made); (3) compound_name_arity/arguments on `$expr/n` answer the name `$expr`
  and all children (kernel-only testset in the rows file); (4) arg/3 does no GC/shift flags.
- Gate order for the dispatcher: fmt (committed files through `warm.sh send`), inventory, check, rows on all three term
  types (`warm.sh file test/core_lang/test_p1_swipl.jl`), test/test_type_discipline.jl,
  `tools/pkgtest_way.sh test/core_lang/test_p1_swipl.jl`, push mutants/P1 at the WIP SHA, branch-gate, term grep, then
  gate/p1 and mutants/P1 at the SAME SHA. The mutant TARGETS name every term_variables test file (T6/T7 mutants).
  No Tier-1 file touched (pl-prims.jl only); alloc pins not needed.
