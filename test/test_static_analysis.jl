# ORIGINAL: the JET/Aqua/AllocCheck gate; no swipl-devel counterpart.
# test/test_static_analysis.jl — JET, Aqua and AllocCheck as BLOCKING gates (user, 2026-10-02: block
# type-instability ahead of time instead of fixing it after).
#
# The tools come from the global environment, never from this package's dependencies (workspace
# policy: analysis tools are installed once and shared). So:
#   * tools/run_tests.sh sets LOGICKERNEL_REQUIRE_TOOLS=1 — a local run WITHOUT the tools is an ERROR;
#   * CI's `analysis` job installs them and sets the same variable;
#   * CI's plain `test` job (Pkg.test's isolated env) has no tools and is not required to — it says so
#     LOUDLY, and asserts that it was not required, so the skip cannot hide a requirement.
using Test, LogicKernel

const _SA_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_TOOLS", "") == "1"
const _SA_TOOLS = ("JET", "Aqua", "AllocCheck")
const _SA_MISSING = [t for t in _SA_TOOLS if Base.find_package(t) === nothing]

if isempty(_SA_MISSING)
    include(joinpath(@__DIR__, "static_analysis_body.jl"))
elseif _SA_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_TOOLS=1 but $(join(_SA_MISSING, ", ")) cannot be loaded — the static " *
        "analysis gate would be skipped. Install them in the global environment."
    )
else
    @info "STATIC ANALYSIS NOT RUN in this environment: $(join(_SA_MISSING, ", ")) unavailable " *
        "(Pkg.test's isolated env). It runs in tools/run_tests.sh and in CI's `analysis` job."
    @testset "static analysis skipped only where it is not required" begin
        @test !_SA_REQUIRED
    end
end
