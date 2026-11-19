# TAB1-D0083-VERIFY: the three D-0083 files on the upstream creation point

Tree: wip/tab1-mono at 7f415a15 (36f08764 moved the creation of '$syspreds' to run_undo_hooks, pl-undo.c:232, and reverted
2933e730 and 893902f0). No source or test file edited. Lane-2 daemon (unit logickernel-warm-78a7647c), run one file at a time:
`LOGICKERNEL_WARM_SECOND=1 WARM_TIMEOUT_S=9000 tools/warm.sh file <f>`, exit code 0 for all three. Julia 1.13.3.

Summary lines of the logs (grep -E 'Pass|Fail|Error|Broken|file run'; no Fail, Error or Broken column printed, so none occurred):

| file | type | Pass | Fail | Error | Broken | Total | Time |
|---|---|---|---|---|---|---|---|
| test/core_lang/test_module_path.jl | reference | 62 | 0 | 0 | 0 | 62 | 2.2s |
| | alt | 62 | 0 | 0 | 0 | 62 | 3m40.2s |
| | alt_interned | 62 | 0 | 0 | 0 | 62 | 4m30.9s |
| | file run | 186 | 0 | 0 | 0 | 186 | 8m13.3s |
| test/core_lang/test_module_swipl.jl | reference | 96 | 0 | 0 | 0 | 96 | 5m18.9s |
| | alt | 96 | 0 | 0 | 0 | 96 | 2m04.0s |
| | alt_interned | 96 | 0 | 0 | 0 | 96 | 2m06.3s |
| | file run | 288 | 0 | 0 | 0 | 288 | 9m29.2s |
| test/db/test_clause_ref_swipl.jl | reference | 234 | 0 | 0 | 0 | 234 | 5m14.2s |
| | alt | 234 | 0 | 0 | 0 | 234 | 10.1s |
| | alt_interned | 234 | 0 | 0 | 0 | 234 | 12.0s |
| | file run | 702 | 0 | 0 | 0 | 702 | 5m36.3s |

grep `SKIP|Warning|Test Failed|Error During`:
- test_module_path.jl: no match.
- test_module_swipl.jl: no match.
- test_clause_ref_swipl.jl: 18 `Warning:` lines, all Prolog messages of the test program (swipl's load-time
  `Singleton variables: [B]`/`[Y]`/`[X]` warnings for /tmp/jl_*/p.pl lines 69, 98, 103, 105, 106, 115, once per type:
  three temp dirs, six warnings each). No Julia warning, no SKIP, no Test Failed, no Error During.

Counts against the earlier record: the file-run totals 186 / 288 / 702 equal the sums of the pre-fix first run at 5bdaa2d9
(test_module_path 168+18, test_module_swipl 267+21, test_clause_ref 699+3), i.e. the original expectations with no pin changed
and the rank-chain row b07cc1b1 kept. The gate_list.md "NOW GREEN" cells for the first two files (189/0, 63 per type; 291/0,
97 per type) are not what this tree measures: 186 (62 per type) and 288 (96 per type). 36f08764's diff removes 14 `@test` lines
and adds 12 in the two module files, which is consistent with the lower counts; the gate_list cells were written before the
final revert and want a correction.
