# `bench/` — benchmark programs

Logic programs with known answers, timed. The first planned use is the indexing scaling curve
against PeTTa (same program, same answers).

The per-PRIMITIVE report is `tools/bench.jl` (BenchmarkTools and Profile from the global env): each
ported primitive against swipl on the same terms — ≥ 30 runs per side (`--runs=N`), swipl and
LogicKernel interleaved run by run, median and IQR (user, 2026-10-15) — then a flat profile of the
worst ratio. The raw numbers of every run go to `tools/bench_results/` (one file per run, machine,
commit and date in its header). A timed run REFUSES to start while the 1-minute load average is
above 0.5 or any other julia process runs (the VS Code language server included), and records both
checks in that header. It is run for every chunk; a new primitive gets a case there.
