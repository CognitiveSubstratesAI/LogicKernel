# ORIGINAL: a differential of format_time/3 and format_time/4 (pl-tai.c) against swipl at the pin; test/core_text/test_tai_swipl.jl's harness
# test/core_text/test_tai_format_swipl.jl — the TAI1 format_time predicates, through a PROGRAM: test_tai_format_swipl.pl holds the rows, each a predicate
# `tN(R)`; the kernel consults the program and enumerates every solution of every tN/1, and its lines are compared with
# test_tai_format_swipl.out — swipl 10.1.20's own, printed by the driver below (`ok`, then one line per row: its name and every
# solution). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale. The rows use
# date/9 terms with an explicit offset and zone name, or float stamps read only by %s and %f (no host-zone dependence; no %c/%x/%X: the locale decides them).
# The second testset runs test_tai_format_tz_swipl.pl, whose rows read the HOST: both sides run with TZ set to the POSIX rule
# CET-1CEST,M3.5.0/2,M10.5.0/3 (no zoneinfo file), the rows that print %c %x %X %p %P and the names switch LC_TIME to C (and back).
# UNTESTED when written (TAI1 writer lane, edit-only): the .out files are swipl's (two identical runs), the kernel's side was never run.
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

const _TAF_PL = joinpath(@__DIR__, "test_tai_format_swipl.pl")
const _TAF_OUT = joinpath(@__DIR__, "test_tai_format_swipl.out")
const _TAFZ_PL = joinpath(@__DIR__, "test_tai_format_tz_swipl.pl")
const _TAFZ_OUT = joinpath(@__DIR__, "test_tai_format_tz_swipl.out")
const _TAFZ_TZ = "CET-1CEST,M3.5.0/2,M10.5.0/3"

# the rows' names, in the order of the program
_taf_names(pl::String=_TAF_PL) =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(pl, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
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
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
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
        if notported
            push!(out, "$name notported")    # the run's ld is thrown away: the query stays open
            return out
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
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
function swipl_lines(
    path::String, names::Vector{String}; tz::Union{Nothing, String}=nothing
)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        cmd = tz === nothing ? `swipl -q $f` : addenv(`swipl -q $f`, "TZ" => tz)
        read(pipeline(cmd; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# one differential: the program `pl`, the .out `outp`, the host zone `tz` (nothing: the rows do not read it)
function taf_check(pl::String, outp::String, tz::Union{Nothing, String})::Nothing
    names = _taf_names(pl)
    expected = String.(readlines(outp))
    # not a vacuous agreement: the .out has a line per row, and every row has at least one answer
    @test length(names) >= 10
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test all(l -> !endswith(l, " "), expected)
    @test !any(l -> endswith(l, " exception"), expected)                      # errors are caught by the rows, none escapes
    kl = tz === nothing ? kernel_lines(_TL, pl, names) :
         withenv(() -> kernel_lines(_TL, pl, names), "TZ" => tz)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TAI FORMAT DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(pl, names; tz) == expected                          # the .out is swipl's, still
    end
    return nothing
end

@testset "TAI1: format_time/3,4 == swipl's answers (the .out), through a program" begin
    expected = String.(readlines(_TAF_OUT))
    @test length(_taf_names()) >= 16
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 1
    @test count(l -> occursin(_codes("domain_error"), l), expected) >= 2
    @test count(l -> occursin(_codes("type_error"), l), expected) >= 3
    @test occursin(_codes("Thursday"), expected[findfirst(startswith("t0 "), expected)])
    @test occursin(_codes("1577934246"), expected[findfirst(startswith("t3 "), expected)])   # %s of 2020-01-02 03:04:05.5 UTC
    taf_check(_TAF_PL, _TAF_OUT, nothing)
end

@testset "TAI1: format_time/3,4 under a fixed host zone and locale == swipl's answers, through a program" begin
    expected = String.(readlines(_TAFZ_OUT))
    @test length(_taf_names(_TAFZ_PL)) == 13
    # the evidence the rows exist for: the zone names of both halves of the year, the C-locale %c, the wrapped year, the sinks
    @test occursin(_codes("CEST"), expected[findfirst(startswith("t0 "), expected)])
    @test occursin(_codes("CET"), expected[findfirst(startswith("t0 "), expected)])
    @test occursin(_codes("Thu Jan  1 01:00:00 1970"), expected[findfirst(startswith("t2 "), expected)])
    @test occursin(_codes("-2147483648"), expected[findfirst(startswith("t6 "), expected)])   # %G of year 2147483647 wraps
    @test occursin(_codes("ab"), expected[findfirst(startswith("t8 "), expected)])           # output before an error stays
    @test occursin(_codes("permission_error"), expected[findfirst(startswith("t9 "), expected)])
    @test occursin(_codes("existence_error"), expected[findfirst(startswith("t10 "), expected)])
    taf_check(_TAFZ_PL, _TAFZ_OUT, _TAFZ_TZ)
end
