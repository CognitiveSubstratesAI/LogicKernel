# ORIGINAL: WHITE-BOX kill row of TAB1 TB4 mutant S5 (tools/mutants/TB4.py `TB4-S5`; audit D-0653, D-0681, D-0685 item 1):
# `table_has_no_answers` (src/pl-tabling.jl, PORT of pl-tabling.c:2086-2096 table_has_no_answers: `if (atrie->value_count == 0) return true;`),
# read on a trie that HAS a value, must answer false (the trie has no IDG node, so the reevaluating branch is not involved).
#   * Its own file, FIRST in the mutant's TARGETS: with the mutant (`value_count >= 0 && return true`) the function reads true for every trie
#     and `simplify_component` (a Julia `while true` with no tick) never ends on the first program row of test_tabling_wfs_swipl.jl that
#     completes a negative component. A failing testset inside the including testset (warm.sh, Pkg.test) does not stop the including file, so
#     the row cannot be a first testset of that file: mutate_drive.py `run_targets` stops at the first failing target instead.
#   * DEADLINE CHOICE: none is needed, by construction. The row calls ONLY `table_has_no_answers`, a straight-line read of one field, never
#     `simplify_component` or any loop; on the mutant it FAILS BY VALUE (the second `@test`) in well under a second. A thread-and-`timedwait`
#     deadline cannot stop a spinning pure-Julia loop (a Task cannot be killed on a single thread, a spawned thread cannot be stopped at all), so
#     it would leave a spinning thread in the warm daemon; a subprocess is heavy. Neither is used: no spinning body exists in this file, so the
#     daemon is never left with a spinning thread after the mutated run. LIMIT: the row proves the read, not the loop; the loop's end is
#     proved by the program rows of test_tabling_wfs_swipl.jl on the unmutated tree.
#   * NO Prolog route and no swipl oracle: `table_has_no_answers` is an internal C function (not a predicate) of a trie that is hand-built here,
#     so the expectations are hand-written from the C source above (true with value_count 0, false with one value).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the trie is built by hand from kernel structs; the term type only parameterises it
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TS5 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

@testset "table_has_no_answers reads the value count (TB4-S5, white-box)" begin
    tr = LK.trie_create(_TS5)
    @test tr.value_count == 0
    @test LK.table_has_no_answers(tr)          # no value: true (pl-tabling.c:2090)
    tr.value_count = 1
    @test !LK.table_has_no_answers(tr)         # a value, IDG === nothing: false (pl-tabling.c:2092-2095 falls through)
    tr.value_count = 0
    @test LK.table_has_no_answers(tr)
end
