# Q10: unowned stubs (LDB 3.3 / Q10, audit D-0290 item 1) -- handoff

Worktree ~/code/lk-q10, branch wip/q10 (off origin/main e0dfb4a). EDIT-ONLY writer: nothing here is compiled or run.
Pin: swipl-devel cbf4e1896275. Oracle: swipl 10.1.19.

## What is still open on main (checked against origin/main e0dfb4a, not against the brief)
| brief names | state on main | evidence |
|---|---|---|
| pl-dict.c's six (is_dict/1,2, dict_create/3, put_dict/3, select_dict/3, get_dict/3) | LANDED (BOOTPRED) | src/pl-dict.jl, `PL_predicates_from_dict` in src/pl-ext.jl; rows bp27-bp119 |
| thread_self/1 | LANDED (BOOTPRED) | src/pl-thread.jl `pl_thread_self`, src/pl-ext.jl:57 |
| with_mutex/2 | LANDED (BOOTPRED) | src/pl-mutex.jl, src/pl-ext.jl:58 |
| garbage_collect/0 | C part LANDED: `'$garbage_collect'/1` (src/pl-gc.jl). `garbage_collect/0` itself is Prolog, boot/syspred.pl:1423-1424 | nothing to port; LB4's boot load defines it |
| `'$style_check'/2` | OPEN (BOOTPRED waited for F1b, but the kernel already carries `ld.debugstatus_styleCheck`, pl-global.jl:449, read by pl-comp.jl:3153, pl-proc.jl:1110, pl-read.jl:2289; nothing waits) | pl-prims.c:6523-6537 |

So Q10's remaining work is ONE predicate. The reader and the compiler already read the field; this adds the setter/getter.

## Groups (commit order)
1. [x] this plan -- 02cfcfe
2. [x] `'$style_check'/2`: src/pl-prims.jl `pl_style_check2_va` + the table entry in `PL_predicates_from_prims` (after statistics/2) -- 5a5d6ef
3. [x] oracle rows sc01-sc20: test/core_lang/test_style_check_swipl.jl, evidence/Q10/{gen_rows.py,q10_driver.pl,q10_rows.pl,q10_rows.out} (swipl 10.1.19, two byte-identical runs) -- a0894fb
4. [x] tools/mutants/Q10.py, 8 mutants, checked by a text script (old once, new != old, ids unique, targets exist) -- 9e3414d
5. [x] test/static_analysis_manifest.jl entry -- 771426c; docs/architecture.md block -- de3488c
6. [x] this handoff update (final commit)
Commits: 6 + this one = 7 (estimate was 6-7).

## Flags for the audit
- boot/dicts.pl needs more of pl-dict.c than the six: `dict_pairs/3`, `get_dict/5`, `put_dict/4`, `del_dict/4`, `:<`/2, `>:<`/2,
  `'$get_dict_ex'/3`, `dict_same_keys/2`, the `'$get_dict_kv'` family (boot_needs.tsv dicts.pl: pl-dict.c:8; topvars.pl, expand.pl,
  tabling.pl: pl-dict.c:3 each). Not in this brief; an owner is needed before LB4.
- Still unowned, not Q10's stub list: SSU compilation, os/pl-files.c + os/pl-glob.c (LB2b).

## Unrun and the gate order
Unrun: everything on the kernel (no Julia was started). The rows are swipl's; the kernel answers are UNVERIFIED. Possible kernel
differences to watch at the gate: sc08 (`2.0` must fail: kernel PL_get_integer takes tagged ints only, as upstream's), sc10/sc13
(the Int32 bounds), sc01 (the default 202 from pl-global.jl:530).
Gate order: `warm.sh fmt` (format the committed files through `warm.sh send`: pl-prims.jl, the test file, the manifest), inventory,
`warm.sh check`, test/core_lang/test_style_check_swipl.jl on all three term types, test/test_type_discipline.jl, then
`tools/pkgtest_way.sh test/core_lang/test_style_check_swipl.jl`, push `mutants/Q10` at the WIP SHA, branch-gate, term grep, alloc pins
x3 are NOT needed (pl-prims.jl is not a Tier-1 file; confirm), then a gate push on a FRESH name. Mutant anchors need a re-fit if fmt re-flows them.
