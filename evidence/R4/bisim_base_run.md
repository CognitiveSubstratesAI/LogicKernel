# R4 base-run: test/core_lang/test_bisim_swipl.jl:153, `dropRecords!` assertion (audit D-0818 (5))

Verdict: OLDER than the R2 line. The failure is on every tree that holds lane F's bisim rows t63/t71, on lane F's own branch
and on main's code under it. It is not introduced by a merge of the R2 landing line.

## Runs (reference type, lane 2 daemon, LOGICKERNEL_WARM_SECOND=1, one file)
| tree | SHA | result |
| --- | --- | --- |
| lane F branch wip/lanef2 tip (lane F alone on main b29b887d, first tree that compiles) | 69d576ba | 14 passed, 1 errored, 5m32s; error at test_bisim_swipl.jl:153 (kernel_lines, test:75): `AssertionError: dropRecords!: a frame being filled above lTop (normal_call, vmi:1887) must not be dropped`, src/pl-wam.jl:126 <- lowerLTop! (158) <- restore_after_query (2690) <- _end_query (2724) <- _abandon_query (2829) <- PL_next_solution (2810) |
| R2 line tip wip/r2land-s2 (from evidence/R2/changed_files_run.md, lk-r2land) | 0c7ad830-era | 42 passed, 1 errored; same assertion, same stack shape (line numbers shifted by the merges) |

- 156b544c (the commit that added test_bisim_swipl.{jl,pl,out}) was written "UNTESTED, nothing compiled"; the first tree where lane F loads is
  6b63e89c / wip/lanef2, so wip/lanef2 tip is the earliest compiled state and was run instead. Its pass count (14) matches S1FIX-B's
  note of the same failure on gate/r2s1 (lk-channel evidence/R2/s1fix_B_handoff.md).
- No bisect over the 6 first-parent merges was needed: result 1 fails.

## Original exception (read-only probe through `tools/warm.sh send`, no src edit; probe files in the session scratchpad, not in the repo)
The probe consults a 2-line program (`err/2` and row t63) and runs one query with a Julia `catch` printing `current_exceptions()`:
```
load: ok
CAUGHT: AssertionError
AssertionError: dropRecords!: a frame being filled above lTop (normal_call, vmi:1887) must not be dropped
caused by: AssertionError: kernel variable keys exhausted
  [1] fresh_var_keys!           src/pl-global.jl:306 [inlined]
  [2] _argvar_placeholder(ld, w) src/pl-comp.jl:3377
  [3] _local_subgoal            src/pl-comp.jl:3361
  [4] localGoal                 src/pl-comp.jl:3299
  [5] compileGoalClause         src/pl-comp.jl:3407
  [6] PL_next_solution_guarded  src/pl-wam.jl:4655
```
The full-file run's log carries the same `caused by:` block (log lines 76-): the original error is
`fresh_var_keys!(0)` ("kernel variable keys exhausted", the `first + n > first` assertion needs n >= 1), reached from
`_argvar_placeholder` for a zero-arity compound `automaton()` (rows t63, t71: `compound_name_arguments(A, automaton, [])` as an argument of a
goal run through `catch/3`). The assertion at pl-wam.jl:126 is the SECOND error: the `catch` in `i_metacall_clause` unwinds the frame being filled
only for a `NotPortedError` (pl-wam.jl:4721 at the R2 tip, 4659 on lanef2), so `_abandon_query` finds the frame above lTop.

## Code identity across trees (git show <tree>:<file>)
- src/pl-comp.jl:3377 `k = fresh_var_keys!(n)`: same text at 5cae308f (older main), b29b887d (main), wip/lanef2, wip/r2land-s2.
- src/pl-global.jl `fresh_var_keys!` assertion: same text at all four.
- src/pl-wam.jl `mc_e isa NotPortedError && setLTop!(...)` and the dropRecords! assertion text: same at all four.
- Rows t63 and t71 are in the first commit of the test (156b544c, test_bisim_swipl.pl lines 85 and 93).
So the defect is main's code (an arity-0 case in a compiler helper) exposed by lane F's new rows; the R2 line adds nothing to it.

## Fix already written, not on the R2 line
S1FIX-B (evidence/R2/s1fix_B_handoff.md in lk-channel) staged `k = n == 0 ? UInt64(0) : fresh_var_keys!(n)` at pl-comp.jl:3377 in lk-def1 (gate/r2s1);
its measured result: test_bisim_swipl.jl reference PASS, 100 pass, 3 s. `git log -S` finds that text in no commit of this repository, and
wip/r2land-s2 still has the unfixed line, so the change was not carried onto the landing line. Its second proposal (unwind the frame for any
non-PrologThrow exception in i_metacall_clause, or in _abandon_query, so the real exception is the one reported) is the exception-preserving change of D-0818 (5).

## Housekeeping
Lane 2 daemon: restarted once by the tree switch (struct change), now loaded on wip/lanef2's src; this worktree is back on wip/tab1-mono 843ff54e,
so the next `warm.sh` call in lk-tbland2 reloads. Nothing in src/ or test/ was edited.
