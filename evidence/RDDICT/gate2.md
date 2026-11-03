# RDDICT gate agent 2 (Sonnet) - state file, updated after each step
Lane clone ~/code/lk-dict, local branch gate/rddict (dac6bf7 + uncommitted working tree). Every warm.sh call needs LOGICKERNEL_WARM_SECOND=1.

## Done
- Step 1: `# UPSTREAM: swipl-devel src/SWI-Prolog.h @ cbf4e1896275` added to src/pl-dict.jl line 3; `warm.sh inventory` rc=0 (port_check clean, 255 files);
  `warm.sh fmt` reformatted src/pl-dict.jl (3 DICT lines wrapped + header); anchor checker: 52 mutants, 0 bad.
- Host rebooted (Windows Update) during the first `inventory` re-run after fmt -> exit 137; daemon killed. EV1 daemon stopped by me (dispatcher order); lk-dict daemon restarted cold.

## Next (order)
daemon up -> inventory re-run -> warm.sh check -> branch-gate (marker) -> ONE commit early -> test rows x3 -> TD/manifest/static -> pkgtest_way -> alloc pins -> crash grep -> rebase on origin/main (9cc76fa) -> push.

## Findings so far
- test_dict_preds_swipl.jl:516 (non-vacuity testset) had a typo: yes-rows end `(a[121,101,115])` (ONE paren), the test wanted `))`. The 12 rows are there (counted in the table). Fixed in the test (never-run DICT file, test typo, not a kernel difference). Also warm.sh fmt rewrote the whole file (never formatted before).
- test_dict_preds_swipl.jl reference: PASS 182/182 (6m31s), live swipl compare ran, no SKIP/Warning.
- Pkg.test-way (via branch-gate preflight) passed: test_read_dict 1380 MiB, test_read 262, test_read_positions 1308, test_read_swipl 524, test_read_term 1224 MiB peaks.
- First branch-gate failed: dict_preds Pkg.test-way (the typo) + "NOT Blue-formatted" same file; both fixed; branch-gate re-run next.
- check PASS after manifest entry for pl_for_dict (LK.pl_for_dict, Tuple{LD,Int,Any,Int}) was added in test/static_analysis_manifest.jl (DICT's pl_for_dict was uncovered).

## Commit + rebase (done)
- branch-gate PASS (4161 s) on the pre-rebase tree; ONE commit 25cb850 (all working-tree fixes). dp rows three types 182x3 PASS (alt 6m14s, alt_interned 6m01s); read_dict 357x3; read_term 71x3; read_positions 47x3; read_swipl 45x3; read.jl 113x3; test_lint_globals 9; test_type_discipline 33 (5m05s). Left to CI by the budget: test_gate_split, test_manifest_entries, test_port_check (I run test_manifest_entries myself).
- Pkg.test-way peaks (MiB): dict_preds 1957, read_dict 1455, read 266, read_positions 1370, read_swipl 524, read_term ~1270 (all clean, no swipl, inert guard).
- origin/main moved to f08167f (EV1 landed). Rebased gate/rddict onto it: conflicts docs/architecture.md (append/append), static_analysis_manifest.jl (comma added), os/pl-prologflag.jl comment (main's F1c wording kept), docs/port_inventory.md (regenerated). range-diff: evidence/RDDICT/rangediff2.txt (23 "=", 4 "!": the architecture block, the manifest entries, pl-read.jl and pl-prologflag.jl commits = exactly the conflicted ones).
- Stale text found after the commit (the absence hook flagged the pre-existing architecture row): pl-dict.jl row and header comment said the reader refuses dict syntax / other dict predicates are not ported; rewritten in the follow-up commit.

## Second commit + push
- branch-gate PASS #2 on the rebased tree (1938 s; marker recorded): dp 182x3, read_dict 357x3, read_swipl 45x3, read 113x3, read_positions 47x3, read_term 71x3, lint_globals 9, type_discipline 33 (3m10s). Left to CI by budget: test_gate_split, test_manifest_entries (run by me: 9/9 PASS reference), test_port_check.
- static_analysis_fast.jl reference: 14/14 PASS (10 s). test_static_analysis.jl reference: see the line below.
- Commits: 3b657b6 (the one gate-fix commit, rebased), cbff230 (stale pl-dict.jl row/header comment). 29 commits on f08167f, authors all Shivaji Gadde.
- PUSHED: gate/rddict at cbff230 (pre-push hook check_coverage_zero OK). mutants/RDDICT NOT pushed (D-0384 pattern: after Evidence green). CI run 41657223656 (CI), Evidence 41657223498.
- Crash-term grep over `git diff origin/main..HEAD` added lines and the messages: hits only in evidence/RDDICT/gate1.md, gate2.md (they quote the grep pattern) and tools/mutants/DICT.py:17 ("past the shorter dict, a crash or a hang, not a verdict": the kernel's own mutant comment, no upstream detail).

## D-0390 fix IN PROGRESS (agent 2 hit the 150k cap) - state for agent 3
Evidence RED on gate/rddict cbff230 (CI 41657223656, Evidence 41657223498): static shard JET runtime dispatch in pl_for_dict (func::Any). Reproduced locally by test_static_analysis.jl reference (3 errors at pl-dict.jl:975/976/979; Aqua 12/12 ok).
UNCOMMITTED working tree (lane ~/code/lk-dict, branch gate/rddict at cbff230, on top of f08167f):
 - src/pl-dict.jl: pl_for_dict was changed to `func::F ... where {F}` and the call site to a callable struct `PutPairFn{T}` (fmt'd). That route FAILS the manifest: a callable-struct method cannot be named in the manifest (check: "NO SUCH METHOD ... PutPairFn" / "NOT IN THE MANIFEST: PutPairFn Tuple{PutPairFn,Int,Int,Bool}").
 - test/static_analysis_manifest.jl: has `(LK.pl_for_dict, Tuple{LD, Int, LK.PutPairFn{T}, Int}, false)` and `(LK.PutPairFn, Tuple{LK.PutPairFn{T}, Int, Int, Bool}, false)` (both to be replaced).
PLAN (the python edit of this was cut by the cap, NOT applied; it asserted before writing):
 1. src/pl-dict.jl: `pl_for_dict(ld, dict, func::F, closure::C, flags)::Int where {F, C}` calling `rc = func(av+0, av+1, closure, i == pairs)` (upstream's func(key,value,closure)); replace struct PutPairFn + its (f::PutPairFn)(...) method by `struct PutPairClosure{T}` (ld::PL_local_data{T}, head, tail, tmp::term_t) and a plain function `put_pair_cb(key::term_t, value::term_t, c::PutPairClosure, ::Bool)::Int = put_pair(c.ld, key, value, c.head, c.tail, c.tmp)`; call site in pl_dict_pairs3_va: `pl_for_dict(ld, dict, put_pair_cb, PutPairClosure(ld, head, tail, tmp), PL_FOR_DICT_SORTED) == 0` (the call site text was reformatted by fmt: re-read lines ~1030-1040).
 2. manifest (test/static_analysis_manifest.jl ~line 2545): `(LK.pl_for_dict, Tuple{LD, Int, typeof(LK.put_pair_cb), LK.PutPairClosure{T}, Int}, false)` and `(LK.put_pair_cb, Tuple{Int, Int, LK.PutPairClosure{T}, Bool}, false)`.
 3. `warm.sh fmt`, `warm.sh inventory`, `warm.sh check` (manifest coverage), then the JET check of the new entries: test/test_static_analysis.jl reference takes ~45 min; the fast route is a `warm.sh send` snippet running JET.report_opt on pl_for_dict with the concrete tuple (dispatches must be zero). Grep done: pl-dict.jl has no other `::Any` callbacks (the only hit was pl_for_dict's untyped func).
 4. `warm.sh branch-gate` (marker), ONE commit (fold: message names the D-0390 fix), push FRESH names gate/rddict2 (never force gate/rddict); mutants/RDDICT2 only after Evidence is green. tools/mutants/DICT.py DICT-D3 anchors on put_pair (unchanged text); re-run the anchor checker for RDDICT.py (52 mutants, 0 bad before this change).
Facts: branch-gate #2 PASS 1938 s on the rebased tree; test_manifest_entries 9/9; static_analysis_fast 14/14; Pkg.test-way clean; mutants/RDDICT NOT pushed; alloc pins (test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433) NOT run yet; daemon lk-dict (unit logickernel-warm-4b046b8f, LOGICKERNEL_WARM_SECOND=1) RUNNING and idle; EV1 daemon stopped; lk-eng3 untouched.
