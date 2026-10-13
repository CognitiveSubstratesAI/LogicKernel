# ORIGINAL: the preflight's fast static pre-check (user, 2026-10-12); no swipl-devel counterpart.
# test/static_analysis_fast.jl — Aqua and JET's `report_package` ALONE, run by `tools/warm.sh
# preflight` before its long stages (the full static-analysis file, a quarter of an hour on a loaded
# machine): a type or ambiguity defect should cost seconds, not a preflight. Not a `test_*.jl` file,
# so the suite never runs it; the same two gates run, with the rest, in test_static_analysis.jl.
using Test, LogicKernel, JET, Aqua

@testset "pre-check: Aqua" begin
    Aqua.test_all(LogicKernel; undocumented_names=true)
end

@testset "pre-check: JET report_package" begin
    JET.test_package(LogicKernel; target_modules=(LogicKernel,))
end
