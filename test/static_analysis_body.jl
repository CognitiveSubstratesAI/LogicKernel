# ORIGINAL: body of the analysis gate, loaded only when the tools are present.
# test/static_analysis_body.jl — included by test/test_static_analysis.jl only when the tools
# load. Top-level `using` so the macros and functions exist before the code below is lowered.
using JET, Aqua, AllocCheck

include(joinpath(@__DIR__, "static_analysis_gates.jl"))
include(joinpath(@__DIR__, "static_analysis_manifest.jl"))
include(joinpath(@__DIR__, "ci_slices.jl"))

# THE SHARDS (D-0059, 2026-10-20; test/ci_slices.jl): LOGICKERNEL_SA_SHARD=k/N runs every N-th entry of
# the per-entry gates (JET's dispatch check, AllocCheck) from the k-th, and the k-th of every N of the
# one-off gates below (`_SA_PARTS`: Aqua runs in exactly one shard). Unset, it is 1/1: everything. Each
# shard writes what it analysed to LOGICKERNEL_SA_COUNTS_OUT, counted where the analysis RUNS, and
# tools/evidence_ci.py checks that the shards' counts sum to the full ones and every part ran once.
const _SA_SHARD = lk_slice("LOGICKERNEL_SA_SHARD")
const _SA_PARTS = (
    "aqua", "jet_package", "dispatch_claims", "coverage", "argstack_push", "leaf_alloc",
    "call_path", "controls"
)
const _SA_RAN = Dict{String, Int}()               # part or per-entry gate → what this shard ran
"Whether one-off gate `part` runs in this shard (and the record that it did)."
function _sa_part(part::String)::Bool
    j = findfirst(==(part), _SA_PARTS)
    j === nothing && error("static analysis: no such part $(repr(part))")
    lk_in_slice(j, _SA_SHARD) || return false
    _SA_RAN[part] = get(_SA_RAN, part, 0) + 1
    return true
end
"The dispatch check's entries: the manifest less those analysed inside a caller (the manifest)."
const _SA_DISPATCH = [
    e for e in DISPATCH_MANIFEST if !haskey(JET_ANALYSED_THROUGH, (e[1], e[2]))
]
"AllocCheck's entries: those marked allocation-free."
const _SA_NOALLOC = [e for e in DISPATCH_MANIFEST if e[3]]

# Positive and negative controls: each gate must FAIL on a planted defect before its verdict on
# LogicKernel means anything. (`Vector{Real}` — abstract element type — dispatches on every use.)
_sa_dispatches(v::Vector{Real}) = v[1] + 1
_sa_stable(v::Vector{Int}) = v[1] + 1
_sa_allocates(n::Int) = zeros(n)
_sa_no_alloc(x::Int) = x + 1
# the span checks' fixture (D-0142): `shared` allocates and has two call sites, `quiet` does not
const _SA_SPAN_FIXTURE = """
module SASpan
@noinline shared(x::Int) = length(string(x))
@noinline quiet(x::Int) = x + 1
function root(x::Int, k::Int)
    k == 1 && @goto a
    k == 2 && @goto b
    k == 3 && @goto c
    return quiet(x)
    @label a
    return shared(x)
    @label b
    return shared(x + 1) + quiet(x)
    @label c
    return quiet(x)
end
end
"""
"""
The call-site pass (D-0142) over `callees` (`span_callees`): each callee AllocChecked on its own, a
site a violation unless the callee is in `exempt` (`SPAN_CALLEE_EXEMPT`) — a `:growth` one's sites each under a
`SPAN_GROWTH_FRAMES` frame, a `:builtin` one called from `fspans` only. One line per violation.
"""
function _sa_span_violations(callees, fspans; exempt=SPAN_CALLEE_EXEMPT)::Vector{String}
    out = String[]
    for (mi, ls) in callees
        c = callee_call(mi)
        if c === nothing
            push!(out, "$mi (lines $(unique(ls))): not one call, cannot be checked")
            continue
        end
        k = findfirst(e -> e[1] === c[1], exempt)
        kind = k === nothing ? :none : exempt[k][2]
        if kind === :builtin
            all(l -> any(s -> s[1] <= l <= s[2], fspans), ls) ||
                push!(
                    out,
                    "$mi (lines $(unique(ls))): a built-in's dispatch outside the foreign path"
                )
            continue
        end
        kind in (:cold, :error) && continue
        bad = [
            s for s in check_allocs(c...)
            if kind !== :growth || !any(fr -> fr.func in SPAN_GROWTH_FRAMES, s.backtrace)
        ]
        isempty(bad) || push!(
            out,
            "$mi (lines $(unique(ls))): $(length(bad)) site(s), first: " *
            join(
                [
                    "$(fr.func)@$(basename(string(fr.file))):$(fr.line)" for
                    fr in first(bad).backtrace
                ],
                " <- "
            )
        )
    end
    return out
end
const _SA_COVERAGE_FIXTURE = """
module SACoverage
f(x::Int) = x + 1
g(x::Int) = x - 1
end
"""

@testset "static analysis" begin
    _sa_part("aqua") &&
        @testset "Aqua: ambiguities, unbound args, exports, deps, compat, piracy, tasks, docs" begin
            Aqua.test_all(LogicKernel; undocumented_names=true)
        end

    _sa_part("jet_package") &&
        @testset "JET: no errors anywhere in the package (report_package)" begin
            JET.test_package(LogicKernel; target_modules=(LogicKernel,))
        end

    @testset "JET: zero runtime dispatch on every manifest entry (this shard's)" begin
        n = 0
        for (i, (f, tt, _)) in enumerate(_SA_DISPATCH)
            lk_in_slice(i, _SA_SHARD) || continue
            JET.test_opt(f, tt; target_modules=(LogicKernel,))
            n += 1
        end
        _SA_RAN["dispatch"] = n
        @test n == count(i -> lk_in_slice(i, _SA_SHARD), eachindex(_SA_DISPATCH))
        @test n > 0                                  # a slice that analyses nothing is no slice
    end

    _sa_part("dispatch_claims") && @testset "the dispatch check's skips lose nothing" begin
        @test length(DISPATCH_MANIFEST) == length(unique(DISPATCH_MANIFEST))   # no duplicate entries
        # the dedup's claim, both halves: each skipped entry and its caller are manifest entries, the caller
        # itself analysed; and the caller REACHES it — query_answers' body calls PL_next_solution, which
        # calls PL_next_solution_guarded (their lowered code), so the skip loses no coverage
        calls(f, tt, name) = any(
            x -> x isa GlobalRef && x.name === name, first(code_lowered(f, tt)).code
        )
        for ((f, tt), (cf, ctt)) in JET_ANALYSED_THROUGH
            @test any(e -> e[1] === f && e[2] == tt, DISPATCH_MANIFEST)
            @test any(e -> e[1] === cf && e[2] == ctt, DISPATCH_MANIFEST)
            @test !haskey(JET_ANALYSED_THROUGH, (cf, ctt))
        end
        qa = Base.bodyfunction(
            which(
                LK.query_answers,
                Tuple{LK.PL_local_data{LK.DefaultTerm}, LK.DefaultTerm}
            )
        )
        @test any(
            m -> any(
                x -> x isa GlobalRef && x.name === :PL_next_solution,
                Base.uncompressed_ast(m).code
            ),
            methods(qa)
        )
        @test calls(
            LK.PL_next_solution,
            Tuple{LK.PL_global_data{LK.DefaultTerm}, LK.PL_local_data{LK.DefaultTerm}, Int},
            :PL_next_solution_guarded
        )
    end

    _sa_part("coverage") &&
        @testset "the manifest covers every method LogicKernel defines" begin
            r = manifest_uncovered(LogicKernel, DISPATCH_MANIFEST, DISPATCH_EXEMPT)
            isempty(r.uncovered) ||
                foreach(
                    u -> println(stderr, "  NOT CHECKED for dispatch: ", u), r.uncovered
                )
            isempty(r.stale_exempt) ||
                foreach(u -> println(stderr, "  stale exemption: ", u), r.stale_exempt)
            @test isempty(r.uncovered)
            @test isempty(r.stale_exempt)
        end

    @testset "AllocCheck: entries marked allocation-free allocate nothing (this shard's)" begin
        n = 0
        for (i, (f, tt, _)) in enumerate(_SA_NOALLOC)
            lk_in_slice(i, _SA_SHARD) || continue
            n += 1
            allocs = check_allocs(f, tt)
            isempty(allocs) || println(stderr, "  allocates: ", f, tt, " — ", first(allocs))
            @test isempty(allocs)
        end
        _SA_RAN["alloc"] = n
        @test n == count(i -> lk_in_slice(i, _SA_SHARD), eachindex(_SA_NOALLOC))
        @test n > 0
    end

    # The one push that grows in place (pl-incl.h `pushArgumentStack`, its `else` is
    # `f_pushArgumentStack`): AllocCheck sees the growth — so this cannot pass by seeing nothing — and
    # every allocation it reports lies inside it (V4a decision 2).
    _sa_part("argstack_push") &&
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
    _sa_part("leaf_alloc") && @testset "AllocCheck: a leaf allocates no child vector" begin
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
    # in the path; growth (`growLocalSpace`) is reached through shared callees only. (2) was a LIST,
    # not the callees the spans really call: since D-0142 (3) the call-site pass reads them from the
    # optimized code (`span_callees`) and AllocChecks each, minus `SPAN_CALLEE_EXEMPT`.
    _sa_part("call_path") &&
        @testset "AllocCheck: the call path's labels allocate nothing" begin
            LK = LogicKernel
            spans_of = label_spans(
                readlines(joinpath(pkgdir(LogicKernel), "src", "pl-wam.jl")),
                "function PL_next_solution_guarded("
            )
            path = ("I_ENTER", "I_CALL", "normal_call", "depart_or_retry_continue",
                "I_DEPART",
                "I_EXIT", "exit_continue", "L_NOLCO", "L_VAR", "L_ATOM", "L_NIL",
                "L_SMALLINT",
                "I_LCALL", "I_TCALL", "I_CUT", "B_VAR0", "B_VAR1", "B_VAR2", "B_VAR",
                "bvar_cont", "B_ARGVAR", "I_VAR", "I_NONVAR", "I_INTEGER", "I_RATIONAL",
                "I_FLOAT", "I_NUMBER", "I_ATOMIC", "I_ATOM", "I_STRING", "I_COMPOUND",
                "I_CALLABLE")
            @test all(n -> haskey(spans_of, n), path)
            spans = [spans_of[n] for n in path]
            loop_tt = (LK.PL_global_data{_M2}, LK.PL_local_data{_M2}, Int, Bool)
            allocs = check_allocs(LK.PL_next_solution_guarded, loop_tt)
            # V5c: resolving an UNDEFINED predicate (`getProcDefinedDefinition` → `trapUndefined` →
            # `autoImport`, which may create a procedure, or `S_UNDEF`'s supervisor) runs once per
            # predicate, at its first call — the cold path upstream takes from `I_LCALL` too — so its
            # sites are not the call path's; every other site in the spans still is (the BOUNDARY's
            # out-of-line frames, exempt here since L1c-6, went with the keyed variables in L1f f3-3)
            cold(a) = any(fr -> fr.func === :getProcDefinedDefinition, a.backtrace)
            @test any(cold, allocs)                     # the exemption matches real sites
            attributed = Int[]
            for a in allocs
                cold(a) && continue
                k = findfirst(fr -> fr.func === :PL_next_solution_guarded, a.backtrace)
                k === nothing || push!(attributed, a.backtrace[k].line)
            end
            @test !isempty(attributed)                  # the attribution sees the loop's own sites
            inpath = [l for l in attributed if any(s -> s[1] <= l <= s[2], spans)]
            isempty(inpath) ||
                println(stderr, "  allocates in the call path, pl-wam.jl lines: ", inpath)
            @test isempty(inpath)
            # (`discardChoicesAfter` left this list with V9g: a cut that discards a CLEANUP frame runs
            # its handler — a goal — so the function is no longer allocation-free as a whole; the
            # spans above still hold the cut's own sites to "allocates nothing")
            # L1c's allocation exemptions: a ratchet, each naming its step (static_analysis_manifest.jl)
            @test length(L1C_ALLOC_EXEMPT) <= L1C_ALLOC_EXEMPT_MAX
            @test length(unique(first.(L1C_ALLOC_EXEMPT))) == length(L1C_ALLOC_EXEMPT)
            for (f, step, kind) in L1C_ALLOC_EXEMPT
                @test step in L1C_STEPS
                @test kind in L1C_EXEMPT_KINDS
                es = [e for e in DISPATCH_MANIFEST if e[1] === f]
                @test !isempty(es) && all(e -> !e[3], es)   # listed ⇒ marked allocating
            end
            for c in
                (LK._call_procedure, LK.pushFrame!, LK.setNextFrameFlags,
                LK.setFramePredicate,
                LK.hasLocalSpace, LK.setLTop!, LK.setGenerationFrame,
                LK._is_newest_live_frame,
                LK.lcoSetNextFrameFlags, LK.lcoSetNextFrameFlags2, LK.copyFrameArguments,
                LK.lowerLTop!, LK.tcallSetNextFrameFlags,
                # (L1c: `deRef`, `linkValI` and `_argp_store!` left this list — they reach the cold
                # adapters on a compound; the call path moves WORDS (`_slot_link!`, `_slot_copy!`),
                # its own sites stay checked by the spans above, and nreverse/qsort's zero-export test
                # guards the hot path)
                LK._argp_add, LK._save_registers!, LK._load_registers!,
                LK.canBind, LK.isInteger, LK.isRational, LK.isFloat, LK.isNumber,
                LK.isAtomic,
                LK.isTextAtom, LK.isString, LK.isTerm, LK.isCallable)
                @test any(e -> e[1] === c && e[3], DISPATCH_MANIFEST)
            end
            # V5a2: a FOREIGN call's own path allocates nothing — a built-in may (it builds terms), so
            # every site in the foreign labels' spans must come from inside the built-in it calls
            # (`_fcall_va`, `_fcall_det`) or from an error path: a bad return value
            # (`error_foreign_return_code`), or success with an exception still pending, the "false alarm"
            # (`PL_clear_foreign_exception`, which resets the ball).
            fpath = ("I_FCALLDETVA", "I_FCALLDET0", "fcall_detn", "helper_I_FEXITDET")
            @test all(n -> haskey(spans_of, n), fpath)
            fspans = [spans_of[n] for n in fpath]
            inside = (
                :_fcall_va, :_fcall_det, :error_foreign_return_code,
                :PL_clear_foreign_exception
            )
            stray = [
                a.backtrace[k].line for a in allocs
                for
                k in (findfirst(fr -> fr.func === :PL_next_solution_guarded, a.backtrace),)
                if
                k !== nothing && any(s -> s[1] <= a.backtrace[k].line <= s[2], fspans) &&
                    !any(fr -> fr.func in inside, a.backtrace)
            ]
            isempty(stray) ||
                println(
                    stderr,
                    "  a foreign call allocates outside its built-in, pl-wam.jl lines: ",
                    stray
                )
            @test isempty(stray)
            # …and the check sees the built-ins' own allocations, so it cannot pass by seeing nothing
            @test any(
                a -> any(fr -> fr.func === :_fcall_va, a.backtrace), allocs
            )
            @test any(e -> e[1] === LK.vmi_fopen && e[3], DISPATCH_MANIFEST)
            # D-0142: the checks above attribute a site to a span by the run loop's frame in its
            # backtrace, which a callee with several callers does not carry — they are blind to it.
            # The call-site pass: every callee the spans do not inline, AllocChecked on its own.
            callees = span_callees(
                LK.PL_next_solution_guarded, loop_tt, "pl-wam.jl", vcat(spans, fspans)
            )
            viol = _sa_span_violations(callees, fspans)
            foreach(v -> println(stderr, "  a span callee allocates: ", v), viol)
            @test isempty(viol)
            seen = [
                c[1] for c in (callee_call(mi) for mi in keys(callees)) if c !== nothing
            ]
            @test all(e -> e[2] in SPAN_CALLEE_KINDS, SPAN_CALLEE_EXEMPT)
            @test length(unique(first.(SPAN_CALLEE_EXEMPT))) == length(SPAN_CALLEE_EXEMPT)
            stale = [e[1] for e in SPAN_CALLEE_EXEMPT if !any(f -> f === e[1], seen)]
            isempty(stale) || println(stderr, "  span exemption no span calls: ", stale)
            @test isempty(stale)
            # …and the pass sees the loop's callees and checks some, so it cannot pass by seeing nothing
            @test length(seen) > count(e -> e[2] !== :growth, SPAN_CALLEE_EXEMPT)
        end

    _sa_part("controls") && @testset "controls: each gate fails on a planted defect" begin
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
        # the span checks (D-0142): an allocation in a callee with TWO call sites — the backtrace
        # attribution sees the site but no frame of the caller; the call-site pass finds it, and a
        # span calling only an allocation-free callee stays clean
        fs = Base.include_string(
            Module(:SASpanHost), _SA_SPAN_FIXTURE, "sa_span_fixture.jl"
        )
        sps = label_spans(String.(split(_SA_SPAN_FIXTURE, '\n')), "function root(")
        a = Base.invokelatest(check_allocs, fs.root, (Int, Int))
        @test !isempty(a)
        @test !any(s -> any(fr -> fr.func === :root, s.backtrace), a)    # the old attribution: blind
        for (lab, bad) in (("a", 1), ("c", 0))
            cs = Base.invokelatest(
                span_callees, fs.root, (Int, Int), "sa_span_fixture.jl", [sps[lab]]
            )
            @test length(cs) == 1
            @test length(Base.invokelatest(_sa_span_violations, cs, Tuple{Int, Int}[])) == bad
        end
        # an exemption's kind decides: `:growth` still checks the sites (none lies under a growth
        # frame), `:cold` does not check them
        ca = Base.invokelatest(
            span_callees, fs.root, (Int, Int), "sa_span_fixture.jl", [sps["a"]]
        )
        for (kind, bad) in ((:growth, 1), (:cold, 0))
            ex = [(fs.shared, kind, "fixture")]
            @test length(
                Base.invokelatest(_sa_span_violations, ca, Tuple{Int, Int}[]; exempt=ex)
            ) == bad
        end
    end
end

# What this shard analysed — the per-entry gates' counts beside the full ones, and the parts it ran —
# for tools/evidence_ci.py's sums (CI); nothing is written without the variable
let out = get(ENV, "LOGICKERNEL_SA_COUNTS_OUT", "")
    isempty(out) || open(out, "w") do io
        println(io, "shard\t", _SA_SHARD[1], '\t', _SA_SHARD[2])
        println(io, "parts\t", join(_SA_PARTS, ','))
        foreach(p -> haskey(_SA_RAN, p) && println(io, "part\t", p), _SA_PARTS)
        println(io, "dispatch\t", get(_SA_RAN, "dispatch", 0), '\t', length(_SA_DISPATCH))
        println(io, "alloc\t", get(_SA_RAN, "alloc", 0), '\t', length(_SA_NOALLOC))
    end
end
