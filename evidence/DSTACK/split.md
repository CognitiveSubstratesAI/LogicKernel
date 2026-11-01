# D stack split A/B (D-0284 item 4) — EDIT-ONLY, nothing compiled or run

Base: origin/main d334065 (MOD6 landed; fetched 2026-11-01). RE-STACKED (restack3, see evidence/DSTACK/restack3.md): the SHAs and branch names below are the NEW ones, wip/dstack-a2 and wip/dstack-b2; the commit lists further down give the OLD SHAs of wip/dstack-a / wip/dstack-b (e863f77 base), the subjects are the same, `git log d334065..wip/dstack-a2` gives the new SHAs. Source of truth for the B tree before the re-stack: local wip/dstack-r3 (code SHA 31034e9; evidence 9b90480, 76e53d3).

## The two landings
| landing | local branch | tip (code, before the gate's own fmt/inventory commits) | gate branch | mutants branch |
|---|---|---|---|---|
| A = G1 + D2 | wip/dstack-a2 | 568fa9b899341a9adadffbb345bdc4d7d698d0d3 (old wip/dstack-a: 3b8f8aa) | gate/dstack-a2 | mutants/G1, mutants/D2 (D1c rides on mutants/D2) |
| B = O1B + O1A + F1b, stacked on A | wip/dstack-b2 | code SHA cc78b9af53a7481513d05b4f0b9d650caf40ee56 (old wip/dstack-b: 7f0b41e); the tip is the commit carrying this file (see `git log -1 wip/dstack-b2`); its parent chain: A tip then 62 commits | gate/dstack-b2 | mutants/O1B, mutants/O1A, mutants/F1B |

`git ls-remote --heads origin` (2026-11-01): none of gate/dstack-a2, gate/dstack-b2, mutants/G1, mutants/D2, mutants/O1B, mutants/O1A, mutants/F1B, mutants/D1c exists. Re-check before pushing.
RULE: B is built on A's tip SHA. If the A gate adds commits (fmt, inventory, fixes) the B branch is re-stacked onto the new A tip by cherry-pick under a NEW name (gate/dstack-b3, no force); B then gates after A is green, or at the same time on the first A SHA only if A needs no change.

## Tree checks done (git only)
- After the re-stack: `git diff wip/dstack-b wip/dstack-b2 -- src test tools` shows only the MOD6 delta and the pl-global.jl/pl-fli.jl merge of it (restack3.md). Before it: `git diff wip/dstack-r3 wip/dstack-b` was EMPTY over the whole tree (src, test, tools, docs, evidence), generated blocks included (r3's inventory and graph are the regenerated ones: 31034e9).
- A: `test/static_analysis_manifest.jl` brackets balance (python scan, strings and comments skipped); the G1 block and the D2 block each end `]...,`; `src/pl-ext.jl` _PRED_TABLES order ... rec, attvar, gvar, dict (as pl-ext.c) in the table AND in _FOREIGN_VA AND in the comment.
- A mutant lists (python, earlier agent): G1 20, D2 45, D1c 100: 0 bad. B (on r3 == B tip): 6 lists 0 bad.
- docs/port_inventory.md and the generated blocks of docs/architecture.md on A are STALE: the A gate runs `warm.sh inventory`. On B they equal r3's.

## Commits of A (e863f77..wip/dstack-a): G1 15, D2 13, DSTACK handoff, the A-fixup
```
3e873fd ADDED: G1 handoff — the plan for pl-gvar.c (functions, upstream lines, Julia sites)
a93743b UPSTREAM: pl-gvar.c the local data's global-variable fields (swipl-devel cbf4e189)
b58de82 ADDED: G1 handoff state and the pl-gvar.jl draft (the cap stopped the source write)
54d40b9 ADDED: pl-gvar.jl — pl-gvar.c whole (b_setval, nb_setval, nb_linkval, b_getval, nb_getval, nb_delete
0a36080 MODIFIED: pl-ext.jl — PL_predicates_from_gvar joins _PRED_TABLES and _FOREIGN_VA
8147d46 ADDED: duplicate_term(ld, in, copy) in pl-copyterm.jl, called by duplicate_term/2
27e2762 MODIFIED: setBuiltinPredicateProperties! makes user:exception/3 dynamic (G1 design D8)
e8fa08d MODIFIED: _release_frozen! returns while gvar_grefs > 0 (G1 design D7)
82b3615 ADDED: test_gvar_swipl.jl — 56 global-variable rows pinned from swipl 10.1.19 (G1)
7c5fd94 ADDED: G1 row h9 — the hook in a database with no program (design H9, D8)
7d1ec6e ADDED: G1 row g57 — nb_current does not enumerate a deleted key
257f3f2 ADDED: tools/mutants/G1.py — 20 mutants for pl-gvar.jl, D7, D8 and duplicate_term
bf1ed2d ADDED: docs/architecture.md G1 section — what pl-gvar.c ports, the struct fields, divergences a-f, D
e587b7d ADDED: static-analysis manifest block for G1 (pl-gvar.jl, duplicate_term, the gvar table)
b028548 ADDED: G1 handoff — coder 2 state, UNRUN list, skipped item 6, the gate order
5499e91 ADDED: D2 handoff — the step list of the recorded database
365354c UPSTREAM: pl-incl.h recordList/recordRef/RL_DIRTY/R_ERASED/R_DBREF, pl-rec.h record_az (swipl-devel cb
7b5fd6d UPSTREAM: pl-dbref.c record_blob/acquire_record/release_record/PL_unify_recref/PL_get_dbref/PL_get_rec
42dea28 DOC: evidence/D2/handoff.md — state at the first agent's hand-back
ebb93d2 UPSTREAM: pl-rec.c lookupRecordList/remove_record/getKeyEx/current_key/record/PL_record_az/recorda/rec
ad447de UPSTREAM: pl-rec.c erase instance PL_predicates_from_rec (swipl-devel cbf4e1896275)
5292ca1 MODIFIED: pl-global.jl record_lists, record_lists_order, record_refs, recorded_states; pl-fli.jl live_
83637f8 ADDED: D2 rows (evidence/D2) — test/db/test_record_swipl.jl, 98 pinned rows, the handoff state
5a9ab18 ADDED: D2 rows r99-r101 and the references white-box testset (evidence/D2)
0732d43 ADDED: tools/mutants/D2.py — the mutation battery of the recorded database (45 mutants)
3f5cbf6 MODIFIED: tools/mutants/D1c.py — D1-56 and D1-119 re-anchored, the equivalence dropped (D-0252)
08bde52 MODIFIED: docs/architecture.md — the D2 section (the recorded database), the pl-rec/pl-dbref/test ro
2bb9b5c DOC: evidence/D2/handoff.md — state after groups 9a, 9b, 10b, the GATE ORDER block, flags F6-F10
a0ab5ea ADDED: evidence/DSTACK/handoff.md — partial state after G1 and D2 (boundary SHAs, conflicts, field c
3b8f8aa FIXED: the A-parts of the D-stack fmt and first-run fixes (G1 and D2 only)
```
The last commit is the A-parts of the combined fix commits afdecb4, bb16a9e, dd45721, a53c6df (pl-gvar, pl-rec, pl-dbref, pl-copyterm, pl-incl whole; G1/D2 test files; evidence G1/D2 drivers; G1.py, D1c.py; hunks of architecture.md and the manifest).

## Commits of B (wip/dstack-a..wip/dstack-b): O1B (stack positions 30-38), O1A (39-61), F1b (62-80), then the DSTACK evidence, the manifest fix, s_undef.diff, and the B-parts commit
```
e143aee ADDED: O1B plan — handoff for the output redirect and with_output_to/2
8c28da6 ADDED: pl-global.jl IO_output_stack — LD->IO.output_stack for the output redirect (O1B)
269cf54 MODIFIED: pl-pro.jl callProlog takes upstream's ex out-argument (swipl-devel cbf4e1896275)
94503b3 ADDED: src/os/pl-redirect.jl — the output redirect and with_output_to/2 (pl-file.c, O1B)
5b45f40 MODIFIED: O1B handoff — reconciled with O1-A's INTERFACE TO B
15d699e FIXED: pl-redirect.jl — no assignment in an elseif condition, nothing-safe current output
7dd4a67 ADDED: tools/mutants/O1B.py — 23 mutants of the output redirect and with_output_to/2
81885c2 TEST: static-analysis manifest block for O1B — the output redirect and callProlog's ex
f585ddb MODIFIED: docs/architecture.md — O1B, the output redirect and with_output_to/2
5b31e23 ADDED: O1A plan — pl-fmt.c groups, commit estimate, INTERFACE TO B
26cf5ed ADDED: pl-fmt.jl group 1 — format_state, ERR_FORMAT, column tracking and output primitives
7932de1 ADDED: pl-fmt.jl groups 2-3 — format/2,3, format_impl, sub-format helpers, get_int_expression
18ac52b ADDED: pl-fmt.jl group 4 — do_format: the directive loop (text, number, column, literal families)
587284d ADDED: pl-fmt.jl groups 5-6 — rubber, formatInteger and the locale helpers; handoff with the open fi
684d21a FIXED: pl-fmt.jl struct rubber — field where renamed place (where is a Julia keyword)
d8515c1 ADDED: pl-fmt.jl group 7a — formatFloat's bignum 'f' and 'e' paths (pl-fmt.c :1473-1700, :1640-1737)
fcd97ff ADDED: pl-fmt.jl group 7b — formatFloat's bignum 'g' path: the mpf and its %g print (pl-fmt.c :1473-
329ff47 ADDED: pl-fmt.jl group 7c — formatFloat itself and the V_FLOAT tail (pl-fmt.c :1455-1893)
c304e64 ADDED: pl-fmt.jl group 8 — PL_predicates_from_format (pl-fmt.c BeginPredDefs(format), :1895-end) and
f987f8e MODIFIED: pl-fmt.jl ~@ calls callProlog with PL_Q_CATCH_EXCEPTION and ex as upstream (pl-fmt.c :865-88
139e9dc ADDED: test_format_swipl.jl rows and evidence/O1A generator, driver, swipl 10.1.19 pins (format/2,3)
859aa95 MODIFIED: pl-ext.jl registers PL_predicates_from_format in _PRED_TABLES and _FOREIGN_VA
99a48ad ADDED: test_format_swipl.jl rows f75-f85, e20-e21 for the mutant list
5bba25d ADDED: test_format_swipl.jl rows f86-f98, e22-e24; f83 gets letters in its digits
5c4e6d5 ADDED: test_format_swipl.jl row f99, literal text between two fill points
3fe3a94 ADDED: tools/mutants/O1A.py, 130 mutants over src/pl-fmt.jl (format/2,3)
a3117dd MODIFIED: evidence/O1A/handoff.md, state after coder 3 and the gate order
9e10de0 MODIFIED: docs/architecture.md, O1A block for format/2,3 (pl-fmt.c)
c0bdb42 MODIFIED: test/static_analysis_manifest.jl, entries for the methods of src/pl-fmt.jl
b06e194 MODIFIED: evidence/O1A/handoff.md, state after coder 4 and the gate order
58e30df MODIFIED: tools/mutants/O1A.py, test_with_output_to_swipl.jl joins the TO target list
1988ca6 ADDED: evidence/O1/handoff.md, the O1 stack (O1-B then O1-A) and its gate order
6438617 ADDED: F1B plan — evidence/F1B/handoff.md (set_prolog_flag, create_prolog_flag/3, set_flag_value, th
492c5d3 UPSTREAM: pl-prologflag.c setRationalSyntax, setVarPrefix, setUnknown, setUnknownOption, checkOnError,
639ca9b UPSTREAM: pl-prologflag.c create_oneof, set_oneof, check_oneof_flag, clean_prolog_flag, keep_flag, new
4a9dad7 UPSTREAM: pl-prologflag.c check_flag_write_access, check_create_flag, set_prolog_flag_unlocked, set_pr
fea5aa6 MODIFIED: src/os/pl-prologflag.jl header — F1b has the write side (swipl-devel cbf4e1896275 pl-prolo
eb702b1 MODIFIED: pl-comp.c, pl-wam.c, pl-write.c flag reads — truePrologFlag, PL_current_prolog_flag (swipl
a8d5300 MODIFIED: src/pl-global.jl PL_local_data — delete the five Boolean stand-in fields and prolog_flag_d
dcd2a2b MODIFIED: evidence/F1B/handoff.md — groups 4 and 5 done, state for groups 6 and 7
3b71e3c ADDED: test_set_flag_swipl.jl rows sf01-sf89 and evidence/F1B generator (group 6, swipl-devel cbf4e189
884ef12 MODIFIED: test_set_flag_swipl.jl _SF_REFUSED — values swipl 10.1.19 accepts, file_name_case_handling
0682c4b MODIFIED: src/pl-comp.jl protected_predicate — comment: the protect_static_code and iso bits are set
40ad0fa ADDED: tools/mutants/F1B.py — 23 mutants for set_flag_value, keep_flag, the validators, the mask rea
a42be31 FIXED: boot/init.jl — the optimise read of the rule rewrite goes through the mask (R2 F1b group 5 le
cdc41b3 MODIFIED: tools/mutants MOD3a.py, SSU1.py, V9f.py — anchors on the deleted local-data fields re-fit 
35ba635 ADDED: tools/bench.jl row "divide x1000, body" — the arithmetic flag reads (R2 F1b design H3)
828d604 MODIFIED: docs/architecture.md — block for writing a Prolog flag (R2 F1b), appended
413bd41 MODIFIED: evidence/F1B/handoff.md — coder 4 state, findings 9-10, the GATE ORDER block
015525e MODIFIED: test/static_analysis_manifest.jl — entries for the F1b functions (set_flag_value and its h
6deaa1a ADDED: evidence/DSTACK/handoff.md — complete stack state, boundary SHAs, conflicts, combined gate or
6fe368f MODIFIED: evidence/DSTACK/handoff.md — gate agent 1 state (fmt, port_check and manifest fixes, check
5242ca6 FIXED: pl-wam.jl S_UNDEF unknown=fail/warning branches (pl-vmi.c S_UNDEF)
fd743b1 FIXED: set_flag rows: reader takes the module's var_prefix, ld-typed flag atoms, stale programs and ro
8e8a231 MODIFIED: evidence/DSTACK/handoff.md — gate agent 3 state (fixes committed, type_discipline allowlis
a47da07 FIXED: pl-fmt.jl get_chr_from_text drops the redundant @inbounds (type-discipline allowlist); prose re
eaee882 FIXED: set_flag rows sf90 (unknown=warning) and a white-box read of the warning; S_UNDEF cites pl-vmi.
70738bd FIXED: JET Nothing union splits in formatInteger, format_ and clean_prolog_flag; inventory regenerated
a7d51d4 FIXED: O1A anchors H5 and H9 follow the formatInteger separator condition; handoff stage 2
bceed25 FIXED: static_analysis_manifest.jl re-stack join (BOOTPRED dict block closed with `]...,`, one stale O
cfe6a46 MODIFIED: evidence/DSTACK/s_undef.diff — the S_UNDEF unknown=fail/warning hunk with the pl-vmi.c cit
7f0b41e FIXED: the B-parts of the D-stack fmt and first-run fixes (O1B, O1A, F1b)
```
The four mixed fix commits are NOT picked as such: the last commit before this file sets every B file to wip/dstack-r3's version (pl-fmt.jl at src/os/pl-fmt.jl, the redirect code merged into src/os/pl-file.jl, pl-ext/pl-global/pl-write/pl-prologflag, LogicKernel.jl, the O1A/O1B mutant lists, the migrated tests, tools/bench.jl). evidence/DSTACK/handoff.md is r3's.

## Gates per landing (COMBINED gate order of the handoff stays valid inside each)
Common: `warm.sh fmt`, `warm.sh inventory`, `warm.sh check` (includes the Pkg.test-way run, D-0222), the new/changed test files x 3 term types (no Warning/SKIP grep), test/test_type_discipline.jl, FULL static (`warm.sh file test/test_static_analysis.jl reference`), then push `mutants/<STEP>` at the WIP SHA, branch-gate, term grep (D-0164), then `gate/*` + `mutants/*` at the SAME SHA. `tools/pkgtest_way.sh <file>` ONE at a time for every changed test file the check leaves to the branch-gate. No H3 bench until the dispatcher's go.

### A (G1 + D2)
- Files, x3 types: test/core_lang/test_gvar_swipl.jl, test/db/test_record_swipl.jl (the only changed test files besides the manifest). Also the mutant TARGETS of G1/D2/D1c that were not changed but exercise the code: test_copyterm_swipl.jl, test_copyterm_cells.jl, test_clause_ref_swipl.jl, test_blob.jl, test_assert_swipl.jl, test_retract_swipl.jl, test_clause_swipl.jl, test_module_path.jl, test/foreign/test_query.jl: the mutate run covers them; run any the check leaves out.
- pkgtest_way: test_gvar_swipl.jl, test_record_swipl.jl.
- Mutants (python validation first): tools/mutants/G1.py (20), D2.py (45), D1c.py (100: the D2 re-fit of 10 anchors + D1-56/D1-119 via TREC).
- Pins x3: src/pl-global.jl record fields of A (GD record_lists, record_lists_order, record_refs; LD gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states): test/test_zero_exports.jl, test/test_ball_cells.jl, test/test_type_discipline.jl.
- FULL static (JET + Aqua + AllocCheck) on the A tree.
- Struct changes (LD/GD fields): the warm daemon restarts itself.

### B (O1B + O1A + F1b), after A
- Files, x3 types: test/core_lang/test_format_swipl.jl, test_with_output_to_swipl.jl, test_set_flag_swipl.jl, test_prolog_flag_swipl.jl, test_write_cells.jl, test_det_swipl.jl, test_rules_swipl.jl, test_firstvar_swipl.jl, test_head_unify_swipl.jl, test/compile/test_body_code_swipl.jl, test_portable_smallint_swipl.jl, test/foreign/test_exceptions_swipl.jl. Module tests that call with_output_to/format: the TARGETS lists of O1B (TU, TSA) name more; the mutate run covers them.
- pkgtest_way: each of the 12, one at a time (r3 run: 14 files, exit 0, peaks <= 1.4 GB).
- Mutants: tools/mutants/O1B.py (23), O1A.py (130), F1B.py (23); also the re-fit lists MOD3a.py, SSU1.py, V9f.py (anchors on the five deleted LD fields): python validation, run them if the dispatcher wants (finding 7 of F1b).
- Pins x3: IO_output_stack (LD, O1B) and the five deleted Boolean LD fields + prolog_flag_determinism_error (F1b): test_zero_exports (239/239 on r3), test_ball_cells (87/87), test_type_discipline (33/33).
- FULL static on the B tree (the r3 run was stopped from outside at seq=198: NOT completed; JET splits already fixed in bab8069).
- S_UNDEF audit note (D-0283 item 1): evidence/DSTACK/s_undef.diff, cites pl-vmi.c:3369 / 3418-3422 and pl-wam.c:2528 at cbf4e189. Goes into the B hand-back for the auditor.
- H3 bench ("divide x1000, body" row in tools/bench.jl): waits for the dispatcher's go.

## Evidence of the unsplit run (code 31034e9, kept for reference)
check PASS (145 s); mutant lists 6 x 0 bad; rows x 3 types on 21 files exit 0 (no Warning/SKIP); pkgtest_way x14 exit 0; pins green as above; FULL static NOT completed.

## Hook notes for the next agent
- The tests-before-commit hook accepted the commit on wip/dstack-a with the tree staged and no untracked files; it refuses a commit while an untracked file is in the tree (a state file left untracked blocks it).
- Commit-message words that trip hooks: see the brief (three phrases/words); the commits above avoid them.
