# ORIGINAL: a differential of the coverage COLLECTION (COV1: pl-coverage.c's `Coverage()` hooks in the run loop, pl-vmi.c at the pin, and
# '$cov_start'/1) against swipl at the pin; the harness of test/core_lang/test_coverage_swipl.jl (its enc, kernel_run and driver are copies).
# test/core_lang/test_coverage_run_swipl.jl — through a PROGRAM: test_coverage_run_swipl.pl holds the rows r0-r14, each starts a collection
# ('$cov_start'/1), runs calls through the VM, stops it and answers COUNTS (a clause's enter and exit counts, the sorted counts of a clause's
# call sites; never a pc: the kernel's offsets index the clause's code, swipl's the byte layout, cov1_design.md Q2). The kernel's lines are
# compared with swipl's, from the .out (swipl 10.1.20's own, printed by the driver below) when it exists and ALWAYS with a live swipl run when
# `swipl` is on PATH.
# MEASURE ON THE LANE (the .out was not written: nothing was run when this file was): with swipl on PATH,
#     LOGICKERNEL_MEASURE_COV_OUT=1 tools/warm.sh file test/core_lang/test_coverage_run_swipl.jl reference
# writes test/core_lang/test_coverage_run_swipl.out from swipl's own run (the driver below; the kernel's lines are never the source), and the
# test then compares both. Commit the .out after reading it (every row has a line; an `exception` or `undefined` line is a defect in the row).
# UNTESTED when written: nothing compiled.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _RUN_PL = joinpath(@__DIR__, "test_coverage_run_swipl.pl")
const _RUN_OUT = joinpath(@__DIR__, "test_coverage_run_swipl.out")

# the rows' names, in the order of the program
_run_names() =
    unique([String(m[1]) for m in eachmatch(r"^(r\d+)\(R\) :-"m, read(_RUN_PL, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions. Returns the lines and the run's local data.
function kernel_run(
    ::Type{T}, path::String, names::Vector{String}
)::Tuple{Vector{String}, LK.PL_local_data{T}} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 100
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, ld
end
# the driver swipl runs to print its lines (the .out is its output)
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(f, DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n")
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

@testset "COV1: the coverage collection through the VM == swipl's counts (the .out and a live run), through a program" begin
    names = _run_names()
    @test names == ["r$i" for i in 0:14]
    kl, ld = kernel_run(_TL, _RUN_PL, names)
    # not a vacuous run: the program loaded, every row answered, none raised or is missing; the semantics' own invariants hold
    @test kl[1] == "ok" && length(kl) == length(names) + 1
    @test all(i -> startswith(kl[i + 1], names[i] * " "), eachindex(names))
    @test !any(l -> occursin("undefined", l) || endswith(l, " exception"), kl)
    @test occursin("c[45]/2(i1,", kl[2])                            # r0: a pair `1-X`: one enter of `pf(1)`'s clause (the nesting `i1` is not it)
    @test occursin("c[45]/2(i3,", kl[10])                           # r8: a pair `3-X`: three enters of the recursive clause (the answer `i3` is not it)
    @test ld.coverage.active == 0 && LK.live_states(ld) == 0        # every row stopped what it started, every enumeration ended

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl !== nothing && get(ENV, "LOGICKERNEL_MEASURE_COV_OUT", "") == "1"
        write(_RUN_OUT, join(swipl_lines(_RUN_PL, names), "\n") * "\n")      # swipl's own lines, the one source of the .out
    end
    if isfile(_RUN_OUT)
        expected = String.(readlines(_RUN_OUT))
        @test length(expected) == length(kl)
        for i in eachindex(kl)
            i <= length(expected) && @test (i, kl[i]) == (i, expected[i])
        end
    else
        @test isfile(_RUN_OUT)                                      # MEASURE ON THE LANE (the header): the .out is absent
    end
    if swipl === nothing
        @info "COV1 DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        live = swipl_lines(_RUN_PL, names)
        @test live == kl                                            # the kernel's counts are swipl's, now
        isfile(_RUN_OUT) && @test live == String.(readlines(_RUN_OUT))   # the .out is swipl's, still
    end
end
