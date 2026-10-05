# ORIGINAL: body of the analysis gate, loaded only when the tools are present.
# test/static_analysis_body.jl — included by test/test_static_analysis.jl only when the tools
# load. Top-level `using` so the macros and functions exist before the code below is lowered.
using JET, Aqua, AllocCheck

include(joinpath(@__DIR__, "static_analysis_gates.jl"))
include(joinpath(@__DIR__, "static_analysis_manifest.jl"))

# Positive and negative controls: each gate must FAIL on a planted defect before its verdict on
# LogicKernel means anything. (`Vector{Real}` — abstract element type — dispatches on every use.)
_sa_dispatches(v::Vector{Real}) = v[1] + 1
_sa_stable(v::Vector{Int}) = v[1] + 1
_sa_allocates(n::Int) = zeros(n)
_sa_no_alloc(x::Int) = x + 1
const _SA_COVERAGE_FIXTURE = """
module SACoverage
f(x::Int) = x + 1
g(x::Int) = x - 1
end
"""

@testset "static analysis" begin
    @testset "Aqua: ambiguities, unbound args, exports, deps, compat, piracy, tasks, docs" begin
        Aqua.test_all(LogicKernel; undocumented_names=true)
    end

    @testset "JET: no errors anywhere in the package (report_package)" begin
        JET.test_package(LogicKernel; target_modules=(LogicKernel,))
    end

    @testset "JET: zero runtime dispatch on every manifest entry" begin
        for (f, tt, _) in DISPATCH_MANIFEST
            JET.test_opt(f, tt; target_modules=(LogicKernel,))
        end
        @test length(DISPATCH_MANIFEST) == length(unique(DISPATCH_MANIFEST))   # no duplicate entries
    end

    @testset "the manifest covers every method LogicKernel defines" begin
        r = manifest_uncovered(LogicKernel, DISPATCH_MANIFEST, DISPATCH_EXEMPT)
        isempty(r.uncovered) ||
            foreach(u -> println(stderr, "  NOT CHECKED for dispatch: ", u), r.uncovered)
        isempty(r.stale_exempt) ||
            foreach(u -> println(stderr, "  stale exemption: ", u), r.stale_exempt)
        @test isempty(r.uncovered)
        @test isempty(r.stale_exempt)
    end

    @testset "AllocCheck: entries marked allocation-free allocate nothing" begin
        n = 0
        for (f, tt, noalloc) in DISPATCH_MANIFEST
            noalloc || continue
            n += 1
            allocs = check_allocs(f, tt)
            isempty(allocs) || println(stderr, "  allocates: ", f, tt, " — ", first(allocs))
            @test isempty(allocs)
        end
        @test n == count(e -> e[3], DISPATCH_MANIFEST)
    end

    # The one push that grows in place (pl-incl.h `pushArgumentStack`, its `else` is
    # `f_pushArgumentStack`): AllocCheck sees the growth — so this cannot pass by seeing nothing — and
    # every allocation it reports lies inside it (V4a decision 2).
    @testset "AllocCheck: the argument stack's push allocates only where it grows" begin
        allocs = check_allocs(
            LogicKernel.pushArgumentStack,
            (LogicKernel.PL_local_data{_M2}, LogicKernel.argstack_entry{_M2})
        )
        @test !isempty(allocs)
        @test all(a -> any(f -> f.func === :f_pushArgumentStack, a.backtrace), allocs)
    end

    @testset "controls: each gate fails on a planted defect" begin
        @test !isempty(JET.get_reports(JET.report_opt(_sa_dispatches, (Vector{Real},))))
        @test isempty(JET.get_reports(JET.report_opt(_sa_stable, (Vector{Int},))))
        @test !isempty(check_allocs(_sa_allocates, (Int,)))
        @test isempty(check_allocs(_sa_no_alloc, (Int,)))
        fx = Base.include_string(Module(:SAHost), _SA_COVERAGE_FIXTURE)
        r = manifest_uncovered(fx, ((fx.f, Tuple{Int}, false),), ())
        @test length(r.uncovered) == 1 && startswith(r.uncovered[1], "g ")
        r2 = manifest_uncovered(
            fx, ((fx.f, Tuple{Int}, false),), (((fx.g, Tuple{Int}) => " "),)
        )
        @test length(r2.stale_exempt) == 1                     # an exemption needs a reason
        r3 = manifest_uncovered(
            fx, ((fx.f, Tuple{Int}, false),), (((fx.g, Tuple{Int}) => "fixture"),)
        )
        @test isempty(r3.uncovered) && isempty(r3.stale_exempt)
        # a REDEFINED method stays in the method table (Julia >= 1.12) with its world range closed;
        # only the current one is the module's — or a warm daemon's revisions read as "NOT CHECKED"
        fr = Base.include_string(Module(:SARedefHost), "module SARedef\nf(x::Int) = 1\nend")
        Core.eval(fr, :(f(x::Int) = 2))
        @test length(owned_methods(fr)) == 1 && fr.f(1) == 2
    end
end
