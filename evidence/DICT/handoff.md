# DICT handoff (step "BOOTPRED-dict", D-0291 item 5; R2b D-0290 item 1; Q10 flag 1) — branch wip/dict off origin/main 1286e62
Mutant file name: tools/mutants/DICT.py (the plan commit created this name; the dispatcher may rename to BPDICT.py). Must land before LB4 b2.

## Table: every pl-dict.c predicate that boot/ or library/ references (pin cbf4e1896275: `git grep -F` over boot library)
"main" = origin/main 1286e62 (src/pl-dict.jl registers only is_dict/1,2, dict_create/3, put_dict/3, get_dict/3, select_dict/3).
"wip" = written on wip/dict (UPSTREAM: pl-dict.c at the pin), NOT run (no Julia here).
| predicate | referencing boot file(s) (boot_needs.tsv row) | referencing library file(s) | upstream pl-dict.c function (PRED_IMPL line) | main | wip |
|---|---|---|---|---|---|
| is_dict/1,2 | dicts, init, messages | dicts, error, explain, listing, macros, option, pprint, prolog_clause, prolog_colour, prolog_stack, random_terms, sandbox, statistics, terms, wasm | is_dict :1367/:1377 | present | - |
| dict_create/3 | dicts, init | option, pprint, prolog_pack, random_terms, sandbox, tableutil, wasm | dict_create :1542 | present | - |
| put_dict/3 | dicts, expand, init, tabling, topvars | dicts, lynx/html_text, option, prolog_codewalk, sandbox, threadutil, zip | put_dict :1673 | present | - |
| get_dict/3 | dicts, expand, init, tabling, topvars | dicts, lynx/html_text, option, pprint, prolog_colour, prolog_pack, sandbox, statistics, threadutil, wasm | get_dict (pl_get_dict) :1480 | present | - |
| select_dict/3 | init | prolog_clause, sandbox | select_dict :1853 | present | - |
| $get_dict_ex/3 | dicts | sandbox | get_dict_ex :1486 | MISSING | 1f48cec |
| get_dict/5 | dicts (listed in boot_needs.tsv top_missing) | - | get_dict :1495 | MISSING | 1f48cec |
| put_dict/4 | dicts, expand, topvars | dicts, lynx/html_text, option, prolog_codewalk, sandbox, threadutil, zip | put_dict4 :1746 | MISSING | 098e26c |
| dict_pairs/3 | topvars | dicts, dom, explain, listing, lynx/html_text, macros, option, pprint, prolog_source, prolog_stack, sandbox, statistics, terms | dict_pairs :1580 (+ pl_for_dict, put_pair) | MISSING | eebd1ac |
| del_dict/4 | - | option, prolog_pack, sandbox | del_dict :1813 | MISSING | 017da30 |
| :</2 | autoload, expand, init, messages | dicts, edit, lynx/html_text, prolog_clause, prolog_colour, prolog_coverage, prolog_jiti, prolog_pack, prolog_source, prolog_xref, record, sandbox, statistics, threadutil, wasm, dialect/xsb/source | unify_left_dict :1888 | MISSING | a61d24f |
| >:</2 | expand | dicts, lynx/html_text, prolog_pack, sandbox | punify_dict :1917 | MISSING | a61d24f |
| dict_same_keys/2 | - | dicts | dict_same_keys :1639 | MISSING | af5b11a |
| $get_dict_kv/4,6,8 | - | dicts | get_dict_kv :2003/:2010/:2017 | MISSING | af5b11a |
| b_set_dict/3 | - | prolog_pack, sandbox, statistics | b_set_dict :1785 (setdict + pl-prims.c setarg) | MISSING | BLOCKED (setarg) |
| nb_set_dict/3 | - | sandbox, statistics | nb_set_dict :1792 | MISSING | BLOCKED (setarg) |
| nb_link_dict/3 | - | sandbox | nb_link_dict :1799 | MISSING | BLOCKED (setarg) |
Defined by boot/dicts.pl in Prolog (not ours; comes with the boot, LB4): ./3, eval_dict_function, get_dict_path, put_dict_path, .put/.get.
Not predicates, not ours: is_most_general_dict (C-only), the public PL_for_dict wrapper, reader `Tag{..}` syntax, writer dict arm.
BLOCKED group: setdict() calls pl-prims.c `setarg(arg*2, dict, value, flags)` (setarg_t, :2820-2925, SETARG_BACKTRACKABLE/LINK).
setarg/3, nb_setarg/3, nb_linkarg/3: a grep for the quoted registration names `"setarg"`, `"nb_setarg"`, `"nb_linkarg"` in src/*.jl found none, and
SETARG_ constants are not in src (the next agent re-checks with `bash workflows/capability_search.sh setarg` before relying on it); b_set_dict needs a trailed
value assignment (TrailAssignment): Tier-1 contact (trail, term cells). See flag 1.

## State (commits on wip/dict, linear, not pushed)
1. 8f750f2 plan. 2. 1f48cec $get_dict_ex/3 + get_dict/5. 3. 098e26c put_dict/4. 4. eebd1ac pl_for_dict + dict_pairs/3.
5. 017da30 del_dict/4. 6. a61d24f :</2 + >:</2. 7. af5b11a dict_same_keys/2 + $get_dict_kv/4,6,8. 8. dd3530e header/table comments.
All in src/pl-dict.jl (appended before PL_predicates_from_dict; entries added to that table; pl-ext.jl already splices the table).
UNRUN: everything (no Julia). Compile risks to look at first: `_err_functor(ld, :-, 2)` in put_pair; `PL_is_variable`,
`PL_unify_list_ex`, `_PL_get_arg`, `_slot_from_cell!` use; `sort!` lt on compareStandard_cells; the 2-cell `av` global block in
get_dict/5 and put_dict/4 (a value unbound variable is linked by `_dict_link!`, put_dict then reads it through assign_in_dict).

## Left (in order)
9. Oracle rows: evidence/DICT/cases.py (written, 7 groups, ~140 goals incl. kill rows for each predicate) -> mk_rows.py (not
   written: model it on evidence/BOOTPRED/gen_rows.py; id prefix `dp`, template = test/core_lang/test_bootpred_swipl.jl: driver,
   _bp_kernel, non-vacuity testset, live-pin testset; helpers dpairs/2 and dp_mem/2 in the program) -> test/core_lang/test_dict_preds_swipl.jl;
   pins from two byte-identical swipl 10.1.19 runs. Rows mark UNVERIFIED on the kernel.
10. tools/mutants/DICT.py (format of MOD3b.py; ~2.5 per code commit = ~15-18; TARGETS: test_dict_preds_swipl.jl AND test_bootpred_swipl.jl
    AND test_type_discipline.jl as D-0238 requires for pl-dict.jl).
11. docs/architecture.md appended block, then the manifest (test/static_analysis_manifest.jl) entries, each its own LAST commits.
12. (BLOCKED group) b_set_dict/3, nb_set_dict/3, nb_link_dict/3 after setarg (pl-prims.c) exists.

## Flags for the audit
1. DESIGN QUESTION: b_set_dict/nb_set_dict/nb_link_dict (referenced by library/statistics, sandbox, prolog_pack) need pl-prims.c setarg
   (trail assignment = Tier-1). Options: (a) a separate SETARG step first (recommended: setarg/nb_setarg/nb_linkarg are also in
   boot_needs.tsv's missing set for bags.pl), then these three in one small commit; (b) port setdict here with a private setarg.
2. Representation-only DIVERGES logged in comments: get_dict/5 and put_dict/4 hand put_dict two global cells instead of two term
   refs; no Mark/Undo retry loops (ensureGlobalSpace raises). `$get_dict_ex` is registered under that name (upstream PRED_IMPL name get_dict_ex).
3. pl_dict_sort_indexes uses compareStandard_cells on the key cells (upstream cmp_dict_index: numbers before atoms, ints by value,
   atoms by compareAtoms) = same order; no behaviour change.
4. Tier-1 contact: none (no pl-wam/pl-comp/pl-supervisor/pl-fli/run loop/term representation edits). Daemon: none used.

## Gate order (after the writer): fmt (via warm.sh send of committed files), inventory, check, rows on all three term types,
## test_type_discipline, pkgtest_way (one at a time), mutants branch, branch-gate, term grep, gate push on a FRESH name.
