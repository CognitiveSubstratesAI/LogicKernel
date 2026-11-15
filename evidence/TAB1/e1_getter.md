# E1 (D-0810 (3)): '$idg_mono_index_deps'/4 reads the leaf as a pointer (lane 2, wip/tab1-mono, julia 1.13.3)

Runs: `tools/warm.sh file <f>` (reference, alt, alt_interned), one file at a time, lane-2 daemon. Log counts `grep -cE 'SKIP|Warning|Test Failed|Error During'`.

## Sites checked against upstream (18168e62 src/pl-tabling.c)
PL_get_pointer_ex in upstream: :2378 (tbl_node_answer-like, src :6275), :4396 (src :1676 tbl_get_pointer), :8919 (A2 leaf of '$idg_mono_index_deps'/4),
:8968 (src :9623), :10962 ('$idg_mono_empty_queue'/2 A1 mdep). PL_get_integer_ex at :10492 ('$tbl_propagate_end'/1, src :9449): stays.
So both cherry-picked sites (39da54e6) are right: `pl_idg_mono_index_deps4_va` leaf, `pl_idg_mono_empty_queue2_va` A1. No other
PL_get_integer_ex in src/pl-tabling.jl or src/pl-trie.jl reads a '$trie_gen_node' leaf (the only one left is :9449, a flag value).
`PL_get_pointer_ex` exists (src/pl-error.jl:805, `# PORT: pl-error.c PL_get_pointer_ex`, manifest test/static_analysis_manifest.jl:3386): PL_get_int64, else type_error(address, T).

## Probe of the getter (scratchpad e1/probe.jl, DefaultTerm, daemon send)
```
v=5            pointer_ex=5            integer_ex=5
v=2147483647   pointer_ex=2147483647   integer_ex=2147483647
v=2147483648   pointer_ex=2147483648   integer_ex=nothing (exception)
v=4294967303   pointer_ex=4294967303   integer_ex=nothing (exception)
v=12884914233  (3<<32 | 12345)  pointer_ex=12884914233   integer_ex=nothing (exception)
v=-1           pointer_ex=-1           integer_ex=-1
```
Below Int32 both agree; above, only the pointer getter answers. (A '$trie_gen_node'/3 leaf is `serial<<32|nid`, always >= 2^32 for serial >= 1.)

## SECOND DEFECT found at the same site (not in the brief)
With the getter swapped alone (round 1, logs r1), the exception is gone but the answers are still wrong:
- test_tabling_monotonic_swipl.jl :124 t_mono04 kernel `r([],[a-b,b-c])` vs swipl `r([],[a-b,a-c,b-c])`; t_mono05 `r(3,[a-b,b-c,c-d])` vs `r(6,[a-b,a-c,a-d,b-c,b-d,c-d])` (33 pass / 6 fail).
- cause: the deps table (`idg_mono_index_deps`, `Dict{Int,IdgMdep}`) is keyed by the NODE ID `nid` (pl-tabling.jl :8512 get(deps, nid), :8575 deps[nid] = mdep, :8773), the leaf passed in is the handle
  `trie_node_handle` = `serial<<32 | nid`; `get(deps, leaf, ...)` never hit. Fix at the same site: the serial half must be the index trie's (`idg_mono_index(n)`),
  the key is `leaf & 0xffffffff` (the precedent: `pl_trie_term2_va`, src/pl-trie.jl, `h >> 32`, `h & 0xffffffff`). The leaf encoding is unchanged.

## Rows before / after (three types each)
| file | before (first_run_report) | round 1: pointer swap only | final: swap + decode |
|---|---|---|---|
| test_tabling_monotonic_swipl.jl (:124 mono) | 33 pass / 6 fail (t_mono04, t_mono05 x3) representation_error(int) | 33 / 6 (answers wrong, above) | 39 pass / 0 fail (13 per type) |
| test_tabling_mono_subsumptive_upstream_swipl.jl (:496) | 24 fail (8 rows x3) raised(representation_error) | 105 pass / 24 fail (4+ rows existence_error prolog_stack:prolog_frame_attribute/3, 4 rows `failed`) | 129 pass / 0 fail (43 per type) |
| test_tabling_mono_reuse_upstream_swipl.jl (:380) | 12 fail (t_mr01 02 04 05 x3) | 63 / 12 (prolog_frame_attribute/3) | 75 pass / 0 fail (25 per type) |
| test_tabling_monotonic_upstream_swipl.jl (:588) | 6 fail (t_m04, t_m05 x3) | 93 / 6 (`failed`) | 99 pass / 0 fail (33 per type) |
Final logs: SKIP|Warning|Test Failed|Error During count 0 in all four; rc=0 for all four. The prolog_frame_attribute/3 rows of round 1 were the
consequence (the error path of the failed propagation), not an undefined-procedure line: they vanish with the decode.
Time: test_tabling_monotonic_swipl.jl 20m58.6s in the final run (5m56 reference, 7m54 alt, 7m08 alt_interned; fix2 run: 6m32, 7m14, 8m50), the file_times.tsv entry was 5 s
when the rows failed at once. The monotonic closure rows (t_mono05 and the file's other programs) now do their real work: NOT diagnosed; a performance
question for the dispatcher (the three other files take 10-24 s).

## Mutation proof (verdict level, test_tabling_monotonic_swipl.jl, three types)
M1: src/pl-tabling.jl:9723 `leaf = PL_get_pointer_ex(ld, PL__t0 + 1)` -> `leaf = PL_get_integer_ex(ld, PL__t0 + 1)`, rest as fixed.
Result: 33 pass / 6 fail, rc=1; t_mono04 `exc(error(representation_error(int),context(system:'$idg_mono_index_deps'/4,_)))` vs `r([],[a-b,a-c,b-c])` x3, t_mono05
`r(2,[a-b,c-d])` vs `r(6,...)` x3: KILLED. Restored (byte-identical copy), same file 39/39 green after.
M2 (no decode, = round 1 above): the swap alone, `get(deps, leaf, nothing)`: 6 fail on t_mono04/t_mono05 (answers differ): KILLED by the same rows.
Leaf below Int32: cannot arise through '$trie_gen_node'/3 (>= 2^32); the getter's answer for small values is the probe above (5, 2^31-1, -1 identical to PL_get_integer_ex).

## Gates
`tools/warm.sh fmt` (1 file rewritten, then clean), `tools/warm.sh check`: PASS in 759 s (format, port_check 373 files, manifest 5650 entries, term scopes, meta files, inert guard, source greps).
No test file changed: no Pkg.test-way run of a test file needed.
