# HF1 gate agent (2026-11-03, Sonnet), lane clone ~/code/lk-halt1, branch wip/hf1 — daemon part of the gate, results

Daemon: SECOND lane (unit logickernel-warm-7460656f), started cold for this run (~7 min), left RUNNING. The other daemon
(lk-ev1, logickernel-warm-e29a7ffc) was not touched.

## Steps (READY TO RUN list of gate1.md, in order)
1. fmt snippet over the 16 changed .jl files: "fmt: 0 file(s) rewritten", nothing to commit.
   Anchor check (python3 -I evidence/HF1/anchor_check.py) repeated afterwards: "74 mutants 74 ids 5 equivalent; bad = 0".
2. `warm.sh inventory`: wrote docs/port_inventory.md (20 insertions, 16 deletions), "port_check clean (256 files)", no
   WHATS-HERE-UPSTREAM complaint, docs/architecture.md not rewritten. Committed as 0d04029.
3. `warm.sh check`: PASS in 135 s (format, port_check, manifest, term scopes, meta files, inert guard).
4. Test files, each on reference / alt / alt_interned, one `warm.sh file` call per file and type, exit 0 every time:
   - test_halt_swipl.jl: 439 pass + 11 broken per type (1317 pass, 33 broken, 0 fail over the three); 36 SKIP lines (12 per type), 0 Warning:
     10 catch/3 `unwind(_)` rows (hg01 hg02 hg03 hg08 hg09 hg10 hg15 hg16 hg28 hg29: "catch/3 refuses an unwind(_) ball (da14a14 not in this tree)"),
     1 `at_halt/1 is not defined in this tree` testset (h04, h12-h14, h22, h25), 1 catch/3 note. Exactly the two known kinds.
   - test_debug_flag_swipl.jl 117 x 3 = 351; test_set_flag_swipl.jl 130 x 3 = 390; test_push_flag_swipl.jl 71 x 3 = 213;
     test_prolog_flag_swipl.jl 460 x 3 = 1380. No SKIP, no Warning, no broken.
   - test/test_type_discipline.jl: 33/33.
   - test/static_analysis_fast.jl (Aqua + JET report_package): 14/14 in 7 m 27 s.
5. `tools/pkgtest_way.sh`, one at a time, all "passed the way Pkg.test runs it", oom_kill 0 (peak MiB): test_halt_swipl 238,
   test_debug_flag_swipl 1306, test_set_flag_swipl 1490, test_push_flag_swipl 1317, test_prolog_flag_swipl 1222.
6. Alloc pins (Tier 1), three types each, no SKIP/Warning, totals EQUAL to the expected numbers:
   test_zero_exports 81+79+79 = 239; test_local_stack 129+124+124 = 377; foreign/test_query 117+115+115 = 347; test_rules_swipl 145+144+144 = 433.
7. Crash-term grep over the added lines of `git diff origin/main..wip/hf1` and the commit messages: see the Push section.

## Not re-run
The optional extras (test_builtins, test_cleanup, test_catch, test_exceptions) were not run; the battery re-runs on this SHA (D-0374 item 3(a) failed,
see gate1.md), so mutants/HF1 decides the 69 non-equivalent mutants.
