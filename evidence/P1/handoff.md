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
1. [x] this plan
2. [ ] arg/3 + registration
3. [ ] compound_name_arity/3, compound_name_arguments/3 + registration
4. [ ] subsumes_term/2 + registration
5. [ ] $factorize_term/3 + registration
6. [ ] term_singletons/2, $term_multitons/2 (shared walker) + registration
7. [ ] $term_size/3, is_most_general_term/1 + registration
8. [ ] rows p01.. : test/core_lang/test_p1_swipl.jl, evidence/P1/{gen_rows.py,driver,rows,.out}
9. [ ] tools/mutants/P1.py
10. [ ] docs/architecture.md block
11. [ ] test/static_analysis_manifest.jl entries (LAST)

## Gate order (for the dispatcher)
fmt (committed files through `warm.sh send`), inventory, check, rows on all three term types, type discipline,
`tools/pkgtest_way.sh test/core_lang/test_p1_swipl.jl`, mutants/P1 branch, branch-gate, term grep, gate push on a fresh name.
No Tier-1 file is touched so far (pl-prims.jl only); alloc pins x3 are not needed unless that changes.

## Flags
(none yet)
