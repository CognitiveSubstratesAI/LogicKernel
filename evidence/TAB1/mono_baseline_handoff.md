# mono_baseline_handoff (lane 2, wip/tab1-mono, base 99e5975c)

## State
- Branch wip/tab1-mono = 99e5975c + the commits listed at the end (no push, no remote).
- Daemon of lane 2 (LOGICKERNEL_WARM_SECOND=1) is running (unit logickernel-warm-78a7647c at the start; restarted by the tree switch). Released? NO, still up; it exits after 3600 s idle.
- Per-file detail: evidence/TAB1/first_run_report.md. Target-file union: evidence/TAB1/first_run_files.txt (135 files by first mutant ref, from the TARGETS of the 34 lists).

## test_tabling_monotonic_swipl.jl (the EV1T baseline red), three types: CLASS ENGINE, not fixed
Raw (log of the run, 19 min cold, each type 10 pass / 2 fail, line :124, testset "monotonic tabling as swipl's (mono)"):
```
Evaluated: "exc(error(representation_error(int),context(system:'$idg_mono_index_deps'/4,_2944)))" == "r([],[a-b,a-c,b-c])"
Evaluated: "r(2,[a-b,c-d])" == "r(6,[a-b,a-c,a-d,b-c,b-d,c-d])"
```
swipl 10.1.20 (`~/.local/bin/swipl`, two runs, md5 6c2ec356...): `r([],[a-b,a-c,b-c])` and `r(6,[a-b,a-c,a-d,b-c,b-d,c-d])`; the file's own live swipl row passes.
Cause named: src/pl-tabling.jl:9723 reads the leaf with `PL_get_integer_ex` (Int32 range, src/pl-fli.jl:504) where pl-tabling.c:8908-8925 reads `PL_get_pointer_ex(A2, &leaf)`;
the kernel's leaf is `(serial << 32) | nid` (src/pl-trie.jl:2253). The same line fails test_tabling_mono_subsumptive_upstream, mono_reuse_upstream,
monotonic_upstream (18 rows/type in all). EV1T T1/T9 stay unread until the engine line is fixed (an engine change by the dispatcher's order; allow-opus not
needed for a one-call-site fix, the dispatcher decides).

## Files run on three types (results by name)
See first_run_report.md: 20 upstream files plus abolish_bulk and min pass; 13 of the 34 new files fail (list there, with class); tb7rows fixed.

## Left
- Row-by-row diagnosis of test_tabling_idg_swipl.jl (class TEST/DRIVER, mixed with possible engine rows), idg_sets unit load status, incr_dyn_nodes t_id01/t_id02, tabling_b t_tt22,
  supervisor driver rows (:662, :682, :684), then the NEW non-upstream test_tabling_* files of the branch.
- Mutants EV1T T2-T10 were read valid by the dispatcher; T1 and T9 wait for the engine fix above.

## Commits on wip/tab1-mono
- 439908a7 FIXED: test_tabling_tb7rows_swipl.jl (extractor) + the three evidence files. Gates run for it: file on three types 633/633, tools/warm.sh fmt (0 rewritten), tools/warm.sh check PASS (949 s).
