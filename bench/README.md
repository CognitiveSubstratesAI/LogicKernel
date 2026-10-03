# `bench/` — benchmark programs

Logic programs with known answers, timed. The first planned use is the indexing scaling curve
against PeTTa (same program, same answers). Report three stable runs from one process, never one.

The per-PRIMITIVE report is `tools/bench.jl` (BenchmarkTools and Profile from the global env): each
ported primitive against swipl on the same terms, three runs from one process, then a flat
profile of the worst ratio. It is run for every chunk; a new primitive gets a case there.
