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
# UNDER CI (`CI=true`) A MISSING TOOL IS AN ERROR, whatever LOGICKERNEL_REQUIRE_TOOLS says (2026-10-20):
# the skip is allowed only in a job that NAMES it, `LOGICKERNEL_STATIC_ANALYSIS_OPTOUT=pkg-test` (CI.yml's
# Pkg.test job alone). MEASURED that day: mutation.yml ran this file without the tools and it passed in
# 1 s, so four mutants "survived" a gate that never ran. And every CI run says which way it went, as an
# ANNOTATION on its job (readable through the API without a token, unlike the log): `::notice` that the
# analysis RAN with the tools' versions, or `::warning` that it was skipped under the opt-out.
using Test, LogicKernel

const _SA_CI = get(ENV, "CI", "") == "true"
const _SA_OPTOUT = get(ENV, "LOGICKERNEL_STATIC_ANALYSIS_OPTOUT", "") == "pkg-test"
const _SA_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_TOOLS", "") == "1" || (_SA_CI && !_SA_OPTOUT)
const _SA_TOOLS = ("JET", "Aqua", "AllocCheck")
const _SA_MISSING = [t for t in _SA_TOOLS if Base.find_package(t) === nothing]

if isempty(_SA_MISSING)
    include(joinpath(@__DIR__, "static_analysis_body.jl"))
    _SA_CI && println(
        "::notice title=static analysis::RAN — ",
        join(["$t $(pkgversion(getfield(@__MODULE__, Symbol(t))))" for t in _SA_TOOLS], ", ")
    )
elseif _SA_REQUIRED
    _SA_CI && println("::error title=static analysis::REQUIRED but missing: $(join(_SA_MISSING, ", "))")
    error(
        "the static analysis gate is required here (LOGICKERNEL_REQUIRE_TOOLS=1, or CI without the " *
        "pkg-test opt-out) but $(join(_SA_MISSING, ", ")) cannot be loaded — it would be skipped. " *
        "Install them in the global environment."
    )
else
    _SA_CI && println(
        "::warning title=static analysis::SKIPPED under LOGICKERNEL_STATIC_ANALYSIS_OPTOUT=pkg-test ",
        "(missing: $(join(_SA_MISSING, ", ")))"
    )
    @info "STATIC ANALYSIS NOT RUN in this environment: $(join(_SA_MISSING, ", ")) unavailable " *
        "(Pkg.test's isolated env). It runs in tools/run_tests.sh and in CI's `analysis` job."
    @testset "static analysis skipped only where it is not required" begin
        @test !_SA_REQUIRED
    end
end
