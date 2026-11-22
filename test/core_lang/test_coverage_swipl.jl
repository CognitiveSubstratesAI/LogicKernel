# ORIGINAL: a differential of pl-coverage.c's predicates ('$cov_add'/3, '$cov_data'/3, '$cov_reset'/0, '$cov_stop'/1, '$cov_active'/1)
# against swipl at the pin; test/core_lang/test_bisim_swipl.jl's harness
# test/core_lang/test_coverage_swipl.jl — through a PROGRAM: test_coverage_swipl.pl holds the rows, each a predicate `tN(R)` or `wN(R)`;
# the kernel consults it and enumerates every solution of every row, and its lines are compared with test_coverage_swipl.out — swipl
# 10.1.20's own (the pin's), printed by the driver below. When `swipl` is on PATH the .out is checked against a live run as well.
# Pass 1 (rows t0-t40) runs on a clean state: the inactive answers, the order of '$cov_add'/3's checks, clause and call sites read back
# by the ground lookup and the enumeration, the type and clause restrictions of a pattern, the reset. Pass 2 (rows w0-w7) runs with the
# collection ACTIVE TWICE: swipl's driver starts it twice, the kernel's `setup` sets `ld.coverage.active = 2`; the rows are cumulative
# ('$cov_stop'/1's nesting, the permission error of '$cov_reset'/0 while active). `'$cov_start'/1` is ported since COV1 (the collection is
# in test_coverage_run_swipl.jl): the row `tcs` and a separate testset run it as the kernel's own row. UNTESTED when written: nothing compiled.
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

const _CV_PL = joinpath(@__DIR__, "test_coverage_swipl.pl")
const _CV_OUT = joinpath(@__DIR__, "test_coverage_swipl.out")

# the rows' names, in the order of the program: the `prefix` ones (t: pass 1, w: pass 2; `tcs` is no pass-1 row)
_cv_names(prefix::String) =
    unique([
        String(m[1]) for
        m in eachmatch(Regex("^(" * prefix * "\\d+)\\(R\\) :-", "m"), read(_CV_PL, String))
    ])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions; `setup` runs after the load, before the rows.
# Returns the lines and the run's local data (the last row's query stays open after a named refusal: the data is thrown away).
function kernel_run(
    ::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing
)::Tuple{Vector{String}, LK.PL_local_data{T}} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    setup(gd, ld)
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
            push!(out, "$name notported")    # the query stays open: the caller reads `ld` and drops it
            return out, ld
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, ld
end
kernel_lines(
    ::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing
) where {T} =
    first(kernel_run(T, path, names, setup))

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
fz_cov_run(File, Ns1, Ns2) :-
    fz_run(File, Ns1),
    '$cov_start'(_), '$cov_start'(_),
    forall(member(N, Ns2), fz_pred(N)).
"""
function swipl_lines(
    path::String, names1::Vector{String}, names2::Vector{String}
)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_cov_run('$path', [" * join(names1, ",") *
            "], [" *
            join(names2, ",") * "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_cv_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "COVERAGE: pl-coverage.c's predicates == swipl's answers (the .out), through a program" begin
    names1 = _cv_names("t")
    names2 = _cv_names("w")
    names = vcat(names1, names2)
    expected = String.(readlines(_CV_OUT))
    # not a vacuous agreement: the .out has `ok` and a line per row, and the rows' own evidence is in it
    @test names1 == ["t$i" for i in 0:40] && names2 == ["w$i" for i in 0:7]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    body = expected[2:end]
    for w in (
        "type_error",
        "instantiation_error",
        "domain_error",
        "permission_error",
        "existence_error",
        "failed",
        "same"
    )
        @test _cv_count(body, w) >= 1
    end
    @test _cv_count(body, "-") >= 5 && _cv_count(body, "true") >= 2

    # pass 1: a clean state; pass 2: the collection active twice (the kernel's setup sets the count: the rows only read and lower it)
    kl1, ld1 = kernel_run(_TL, _CV_PL, names1)
    kl2, ld2 = kernel_run(_TL, _CV_PL, names2, (gd, ld) -> (ld.coverage.active = 2))
    @test kl2[1] == "ok"
    kl = vcat(kl1, kl2[2:end])
    @test length(kl) == length(expected)
    for w in (
        "type_error",
        "instantiation_error",
        "domain_error",
        "permission_error",
        "existence_error",
        "failed",
        "same"
    )
        @test _cv_count(kl[2:min(end, length(expected))], w) == _cv_count(body, w)
    end
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end
    @test LK.live_states(ld1) == 0 && LK.live_states(ld2) == 0         # every '$cov_data' enumeration ended or was cut
    @test ld2.coverage.active == 0                                      # w6 left the collection

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "COVERAGE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_CV_PL, names1, names2) == expected               # the .out is swipl's, still
    end
end

# '$cov_start'/1 answers the nesting 1, makes the data, counts the collection active and sets the alert bit (COV1; the counts it then collects are
# test_coverage_run_swipl.jl's)
@testset "COVERAGE: '\$cov_start'/1 starts the collection" begin
    kl, ld = kernel_run(_TL, _CV_PL, ["tcs"])
    @test kl == ["ok", "tcs c" * _codes("tcs") * "/1(i1)"]
    @test ld.coverage.active == 1 && ld.coverage.data !== nothing
    @test (ld.alerted & LK.ALERT_COVERAGE) != 0
end

# a call site's pc offset outside 0..2^32-2 has no table key here (src/pl-incl.jl): a named refusal, swipl accepts it
@testset "COVERAGE: a pc offset outside the key is refused by name" begin
    for row in ("tcp", "tcq")
        kl, ld = kernel_run(_TL, _CV_PL, [row])
        @test kl == ["ok", "$row notported"]
    end
end
