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

    # A leaf's children are the shared empty vector (`_no_children`; user, 2026-10-05), so no leaf
    # constructor allocates a child vector. Each still allocates the term itself — DefaultTerm is not
    # stored inline, its `value` a Union holding a String — so this cannot pass by seeing nothing.
    @testset "AllocCheck: a leaf allocates no child vector" begin
        LK = LogicKernel
        for (f, tt) in (
            (LK.mk_var, (Type{_M2}, UInt64)), (LK.var_term, (Type{_M2}, UInt64)),
            (LK.sym_term, (Type{_M2}, Symbol)),
            (LK.mk_reserved_symbol, (Type{_M2}, Symbol)),
            (LK.gnd_term, (Type{_M2}, Int64)), (LK.gnd_term, (Type{_M2}, String))
        )
            allocs = check_allocs(f, tt)
            @test any(a -> a.type === _M2, allocs)                 # the term itself is seen
            @test !any(a -> a.type === Vector{_M2}, allocs)        # …and no child vector
        end
    end

    # V4b (user, 2026-10-05: static attribution AND a warm runtime check; the runtime one is in
    # test/core_lang/test_rules_swipl.jl). The call path's labels in the run loop: (1) no allocation
    # site AllocCheck attributes to a line of `PL_next_solution_guarded` lies in their spans, read
    # from the source's `@label`s; (2) every function they call is an allocation-free manifest entry,
    # AllocChecked one by one above — sites in callees shared by several labels are reported as
    # "multiple call sites" and cannot be attributed to a label. Fresh variables and building
    # compounds allocate by nature, so `B_FIRSTVAR`, `B_VOID`, `L_VOID` and the builders are not
    # in the path; growth (`growLocalSpace`) is reached through shared callees only.
    @testset "AllocCheck: the call path's labels allocate nothing" begin
        LK = LogicKernel
        lines = readlines(joinpath(pkgdir(LogicKernel), "src", "pl-wam.jl"))
        f0 = findfirst(l -> startswith(l, "function PL_next_solution_guarded("), lines)
        fend = findnext(==("end"), lines, f0)
        labels = Tuple{Int, String}[]
        for i in (f0 + 1):(fend - 1)
            m = match(r"^\s*@label (\w+)", lines[i])
            m === nothing || push!(labels, (i, String(m[1])))
        end
        function span(n)
            k = findfirst(x -> x[2] == n, labels)
            return (labels[k][1], k < length(labels) ? labels[k + 1][1] - 1 : fend)
        end
        path = ("I_ENTER", "I_CALL", "normal_call", "depart_or_retry_continue", "I_DEPART",
            "I_EXIT", "exit_continue", "L_NOLCO", "L_VAR", "L_ATOM", "L_NIL", "L_SMALLINT",
            "I_LCALL", "I_TCALL", "B_VAR0", "B_VAR1", "B_VAR2", "B_VAR", "bvar_cont",
            "B_ARGVAR")
        @test all(n -> any(x -> x[2] == n, labels), path)
        spans = [span(n) for n in path]
        allocs = check_allocs(
            LK.PL_next_solution_guarded,
            (LK.PL_global_data{_M2}, LK.PL_local_data{_M2}, Int, Bool)
        )
        attributed = Int[]
        for a in allocs
            k = findfirst(fr -> fr.func === :PL_next_solution_guarded, a.backtrace)
            k === nothing || push!(attributed, a.backtrace[k].line)
        end
        @test !isempty(attributed)                  # the attribution sees the loop's own sites
        inpath = [l for l in attributed if any(s -> s[1] <= l <= s[2], spans)]
        isempty(inpath) ||
            println(stderr, "  allocates in the call path, pl-wam.jl lines: ", inpath)
        @test isempty(inpath)
        for c in
            (LK._call_procedure, LK.pushFrame!, LK.setNextFrameFlags, LK.setFramePredicate,
            LK.hasLocalSpace, LK.setLTop!, LK.setGenerationFrame, LK._is_newest_live_frame,
            LK.lcoSetNextFrameFlags, LK.lcoSetNextFrameFlags2, LK.copyFrameArguments,
            LK.lowerLTop!, LK.deRef, LK.tcallSetNextFrameFlags, LK.linkValI,
            LK._argp_store!,
            LK._argp_add)
            @test any(e -> e[1] === c && e[3], DISPATCH_MANIFEST)
        end
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
