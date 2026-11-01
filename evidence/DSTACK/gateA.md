# D stack landing A (G1 + D2): gate state at the forced hand-back (cap 150k), 2026-11-01 ~10:35Z

NOT COMMITTED: a cherry-pick is in progress in ~/code/lk-dstack (see "Tree state"), so this file is untracked.

## Done on the a2 tree (wip/dstack-a2, gate commit 05db50b = 568fa9b + fmt/inventory commit; base d334065)
- Daemon logickernel-warm-b4dc834e: in sync (acquireModule, PL_predicates_from_gvar/rec, duplicate_term, record_blob defined;
  LD tail module_enums, gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states). Arity of the hand-merged LD/GD checked by the first compile: loads.
- fmt (against origin/main): only src/pl-fli.jl live_states re-wrapped; warm.sh inventory: docs/port_inventory.md regenerated. Committed as 05db50b.
- warm.sh check PASS (130 s). Pkg.test-way left to the branch-gate for the 2 test files; run by hand: tools/pkgtest_way.sh x3 (gvar 1260 MiB, record 1323, module_enum 1218 peaks) all PASS.
- Rows x3 types, no Warning/SKIP/Failed: test_gvar_swipl 228/228, test_record_swipl 558/558, test_module_enum_swipl (MOD6) 381/381,
  test_type_discipline 33/33. Pins (test/core_lang/test_zero_exports.jl 239/239, test_ball_cells.jl 87/87): PASS (paths are under test/core_lang/).
- FULL static (JET+Aqua+AllocCheck) `warm.sh file test/test_static_analysis.jl reference`: PASS 3812/3812 in 54m53s on a2.
- Mutant list validation (python3 -I /tmp/claude-1000/g3_val.py): G1 20, D2 45, D1c 100, 0 bad.
- Crash-term grep over added lines and messages: nothing (one pre-existing comment line, context only, names a stack of linked pieces).
- NOT run: branch-gate (--summary, capped scope), term grep on the final tree, any gate/* push.

## Pushed (all at 05db50b on the OLD base d334065; these names never move)
mutants/G1 (CI run 41292700514), mutants/D2 (41292702707), mutants/D1c (41292704472). gate/dstack-a2 NOT pushed.
Battery results on 05db50b:
- G1: 19/20; SURVIVOR G1-S7 (setval_duplicate copies attvar: `|| word_is_attvar(ld, new)` dropped). Row g42 does not distinguish copy from share.
  FIX (not applied): add rows g58/g59 to test/core_lang/test_gvar_swipl.jl (raw strings, program has gv_dom:attr_unify_hook(_, _)), swipl 10.1.19 answers measured:
  g58 `put_attr(X, gv_dom, 1), nb_setval(gv_av2, X), put_attr(X, gv_dom, 2), nb_getval(gv_av2, Y), get_attr(Y, gv_dom, R)` -> 1 (copy)
  g59 `put_attr(X, gv_dom, 1), nb_setval(gv_av3, X), nb_getval(gv_av3, Y), ( Y == X -> R = same ; R = diff )` -> diff
  then evidence/G1: `python3 gen_rows.py ../../test/core_lang/test_gvar_swipl.jl`, `swipl -q gvar_driver.pl < /dev/null > gvar_rows.out`, `... --fill`;
  mutant id of G1-S7 then names g58/g59; update the "g01-g57" counts in the testset name and docs/architecture.md G1 section.
- D2: 44/45; SURVIVOR D2-30 (getKeyEx `elseif k == DU_WORD && _is_gcompound(w)` -> `elseif k == DU_WORD`). EQUIVALENT: _deref_loc returns DU_WORD only for an atom or a
  gcompound (src/pl-prims.jl:697 and :713); the first branch of getKeyEx (src/pl-rec.jl:584) takes every atom, so the elseif sees a gcompound. Add
  `equivalent="..."` with that reason to tools/mutants/D2.py and drop "(KILL r20...)" from its id; report to the audit (D-0100 file:line).
- D1c: the BASELINE (unmutated, 9 targets) is RED in CI (job 124807093623, run 41292704472; the log has no test detail, the detail is in the artifact verdict-baseline).
  D2 and G1 baselines (their targets) are green, so the failing target is among test_retract_swipl, test_retractall_swipl, test_load_swipl, test_clause_swipl,
  test_module_path (all under test/db, test/files, test/core_lang). NEXT: run those 5 files on the a3 tree with `warm.sh file <f> --summary` (one at a time), find the red one. A REAL REGRESSION until proven otherwise (stop and report if engine core).

## Re-stack (dispatcher's order: main moved to e0dfb4a, T2 landed)
Tree state RIGHT NOW in ~/code/lk-dstack: branch wip/dstack-a3 (from e0dfb4a), `git cherry-pick d334065..568fa9b` IN PROGRESS, stopped at 9d53ac9
"MODIFIED: docs/architecture.md — the D2 section" with a conflict in docs/architecture.md (both sides added a section after G1: T2 on HEAD, D2 incoming).
Resolution = keep both (T2 section first, then D2, a blank line between; no markers). I wrote a python re-join but the hook stopped it before it ran: do it by hand
(markers at lines ~5772, 5802, 5840), `git add docs/architecture.md`, `GIT_EDITOR=true git cherry-pick --continue`; expect more stops (manifest, port_inventory.md: take main's, regenerate).
Resolved so far: src/pl-ext.jl twice (HEAD side = T2's `strings`; order attvar, gvar, dict, strings in _PRED_TABLES, _FOREIGN_VA and the comment; D2's
comment text "rec (D1: erase/1; D2: the recorded database)" kept). 26 commits of d334065..568fa9b are on a3; the remaining ones follow 9d53ac9 (architecture D2, handoff docs, 3b8f8aa-equivalent 568fa9b "FIXED: the A-parts ..." ).
a3 does NOT yet contain the 05db50b fmt/inventory commit: re-pick it after 568fa9b (`git cherry-pick 05db50b`; port_inventory.md conflict -> take main's then `warm.sh inventory`), or redo
fmt via the snippet (format the diff vs origin/main) and `warm.sh inventory`.
Then, on a3 (a3 differs from a2 by T2: pl-string.jl, pl-ext.jl table, manifest, docs): apply the g58/g59 rows and the D2-30 equivalent, `warm.sh check --summary`, rows x3
(gvar, record, module_enum), pkgtest_way x3, type discipline, pins, FULL static (~55 min), mutants lists as FRESH names (mutants/G1b, D2b, D1d: copy tools/mutants/G1.py -> G1b.py etc.;
the battery name selects the file), branch-gate --summary in a capped scope, term grep, `git ls-remote --heads origin 'gate/*' 'mutants/*'`, `git fetch origin`, push gate/dstack-a3 +
mutants/G1b + mutants/D2b (+ mutants/D1d) at the SAME SHA, `tools/ci_status.sh <sha>`.
Evidence stays unpushed: commit this file on a3 ABOVE the gate SHA.

## Daemon
logickernel-warm-b4dc834e (this worktree) is IDLE since 10:26Z (static finished); lk-t2's daemon belongs to the T2 lane (T2 landed: the dispatcher decides). No agent of mine runs.
Tools notes: `ghg run view <id> --json headBranch,status,conclusion,jobs -R CognitiveSubstratesAI/LogicKernel` (flags AFTER the id, -R last) works; the job log: `bash ~/code/CognitiveSubstratesAI/workflows/ci_job_log.sh <job-id> '<ERE>'`;
a `tail --pid=PID -f /dev/null` wait is moved to the background after 180 s (no sleep loops allowed).

---
## UPDATE (gate agent 2, 2026-11-01 afternoon): state on wip/dstack-a3
- Re-stack DONE: wip/dstack-a3 = e0dfb4a + 26 picked commits + 77687bb (fmt/inventory) + 907eaf8 (rows g58/g59, D2-30 equivalent, inventory regenerated on T2)
  + 59124da (test_load_swipl fix) + eb6c6fc (mutant lists G1b, D2b, D1d). Hand-resolved: docs/architecture.md (T2 section then D2), port_inventory.md (main's, regenerated).
- Open item 1 (G1-S7): rows g58 -> 1, g59 -> diff pinned from swipl 10.1.19 (evidence/G1/gvar_rows.out); gen_rows.py now unescapes `\"` of the raw strings.
  test_gvar_swipl 234/234 (3 types). G1.py id of S7 says KILL g58, g59.
- Open item 2 (D2-30): equivalent= set in tools/mutants/D2.py with the file:line reason (pl-prims.jl:697,:713; pl-rec.jl:584).
- Open item 3 (D1c baseline red): THE RED FILE IS test/files/test_load_swipl.jl, row "a `[]` term in a file is skipped" (line 490), 3 failures = one per term type.
  CAUSE: G1 declares user:exception/3 dynamic at the boot (before any load: probe showed n procs=1 defined=1 before load_file!), the row asserted that NO user procedure is
  defined after the load. NOT an engine defect, not engine core: the test compared with the empty set. FIX: the row compares with the set defined before the load. 231/231.
  The other eight D1c targets are green on a3 (retract 282, retractall 15, clause 213, module_path 186, clause_ref 645, assert 114, blob 549).
- Gates on the tree at 59124da: fmt 0 rewritten; check PASS (182 s); rows x3: record 558, module_enum 381, gvar 234, load 231, type_discipline 33, zero_exports 239, ball_cells 87;
  pkgtest_way x4 (gvar 1496 MiB, record 1394, module_enum 1399, load 1410) all PASS. Mutant lists validated (G1b 20, D2b 45, D1d 100, 0 bad).
- Crash-term grep (added lines + messages): nothing.
- PUSHED: mutants/G1b, mutants/D2b, mutants/D1d at eb6c6fc.
- branch-gate --summary PASS (506 s, 5 files) at eb6c6fc. FULL static running on the daemon (log scratchpad/static.log; started ~15:25Z), bg task b9bnlvb1o.
- Mutant CI: runs 41301610101, 41301609960, 41301609789 (mutants/G1b, D2b, D1d at eb6c6fc; which is which: ci_status).
- Dispatcher: main is now 1286e62 (WARM3 part 2, tooling only). After static: git fetch, rebase wip/dstack-a3 onto 1286e62 (never pushed: plain rebase), warm.sh check --summary once, then push gate/dstack-a3. 
  NOTE mutants were pushed at the pre-rebase SHA eb6c6fc: src tree identical after rebase (verify `git diff eb6c6fc HEAD -- src test tools/mutants` empty); decide whether to repush mutants at the gate SHA under fresh names.
- No CI polling by model turns (D-0293): use a bg until-loop command.

## FINAL STATE at the forced hand-back (gate agent 2, 2026-11-01 ~13:10Z)
- wip/dstack-a3 REBASED onto main 1286e62: tip f1768734e752 (34 commits; src, tests, tools/mutants identical to eb6c6fc except test/test_gate_split.jl from main; NOT pushed as gate).
  Old pre-rebase tip eb6c6fc is what mutants/G1b, D2b, D1d carry.
- Green at the code: FULL static 3883/3883 (70 min, on eb6c6fc; the client timed out at 3600 s, the daemon finished; result read from .warm/out.txt), branch-gate PASS (506 s), rows x3, pkgtest_way x4, type discipline 33, pins; `warm.sh check --summary` PASS on f176873 (1045 s). Crash-term grep clean.
- Mutant CI at eb6c6fc: mutants/G1b run 41301609789 SUCCESS; mutants/D2b run 41301609960 SUCCESS; mutants/D1d run 41301610101 FAILURE in job "Verdict table" 124843429263: the table shows D1-19 SURVIVED ("PL_get_dbref names another type in its error"), maybe more rows; the baseline is NOT the failure now (many D1 rows caught). NEXT: read the table (workflows/ci_job_log.sh 124843429263 'SURVIVED' | grep -v verdict-), list every SURVIVED row: kill each with a row, or declare equivalent with file:line (D-0100); D1-19 is the first one to look at (pl-dbref.jl PL_get_dbref error type).
- Then: fix commits on wip/dstack-a3 (new names for the mutants branches again: G1c/D2c/D1e or only D1e, per the dispatcher; mutants and gate at the SAME SHA), `warm.sh fmt`+`check`, rows of any changed test x3, pkgtest_way of it, push gate/dstack-a3 + mutants at the same SHA, `tools/ci_status.sh <sha>`.
- Open items: 1 (G1-S7) CLOSED (G1b green); 2 (D2-30) CLOSED (declared equivalent, D2b green); 3 (D1c baseline) CLOSED (test_load_swipl fix, D1d baseline green) but D1d has survivors (see above).
- Daemon logickernel-warm-b4dc834e (lk-dstack) is idle since ~12:41Z; never stopped by me.
- Nothing is pushed to gate/*.

## UPDATE (gate agent 3, 2026-11-01 evening)
- D1d survivors: ONE, D1-19. Cause: its `old` text (8-space indent) occurred exactly once, but at PL_get_recref (src/pl-dbref.jl:269), not at PL_get_dbref
  (:238, 4-space indent); PL_get_recref's kill rows are in test_record_swipl.jl, outside D1d's TARGETS. Fix: D1-19 anchored on :238 with its trailing comment
  (killed by test_clause_ref_swipl.jl: 10 failures, run by hand on the reference type); new D1-120 for the recref site, TARGETS test_record_swipl.jl (rows r50, r51 pin
  type_error(db_reference, foo) from swipl; D2-44 covers dropping the error, D1-120 changing its type).
- The job log prints at most 60 matching rows of 100, so SURVIVED was grepped separately: only D1-19; 7 declared equivalents seen (D1-4, 37, 54, 95, 96, 117, 118).
- Lists renamed for the final SHA: G1b -> G1c, D2b -> D2c, D1d -> D1e (validated 20 / 45 / 101, 0 bad). tools/mutants/G1.py, D2.py, D1c.py stay in the tree (older names).
- warm.sh check --summary PASS (911 s) on 815b3e2 (only python lists changed since the green code).
