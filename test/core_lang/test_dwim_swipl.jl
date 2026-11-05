# ORIGINAL: a differential of dwim_match/3 and '$dwim_predicate'/2 (pl-dwim.c) against swipl at the pin; test/core_lang/test_setlocale_swipl.jl's harness
# test/core_lang/test_dwim_swipl.jl — dwim_match/3 and '$dwim_predicate'/2, through a PROGRAM (the pattern of
# test/core_lang/test_setlocale_swipl.jl): test_dwim_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults
# the program and enumerates every solution of every tN/1, and its lines are compared with test_dwim_swipl.out — swipl
# 10.1.19's own, printed by the driver below (`ok`, then one line per row: its name and every solution). When `swipl` is on
# PATH the .out is checked against a live run as well, so it cannot go stale.
# Rows t0-t13 are dwim_match/3 (each of the six kinds, the cases that match nothing, texts that are no atoms, the
# Latin-1 and NUL handling), rows t14-t34 '$dwim_predicate'/2 over the module dwtm the program builds (the answers are
# read as a sorted set: the order is the hash order of the module's table in swipl). The unknown=warning flow (the "However,
# there are definitions for" message) is row t34 (and a testset of test/core_lang/test_set_flag_swipl.jl).
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

const _DW_PL = joinpath(@__DIR__, "test_dwim_swipl.pl")
const _DW_OUT = joinpath(@__DIR__, "test_dwim_swipl.out")

# the rows t0-t13 are dwim_match/3, the rest '$dwim_predicate'/2
const _DW_MATCH_ROWS = 14

# the rows' names, in the order of the program
_dw_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_DW_PL, String))])

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
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_dw_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "DWIM1: dwim_match/3 and \$dwim_predicate/2 == swipl's answers (the .out), through a program" begin
    names = _dw_names()
    expected = String.(readlines(_DW_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) == 35 && names == ["t$i" for i in 0:34]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    em = expected[2:(_DW_MATCH_ROWS + 1)]     # the dwim_match/3 rows
    ep = expected[(_DW_MATCH_ROWS + 2):end]   # the '$dwim_predicate'/2 rows
    @test length(em) == _DW_MATCH_ROWS && length(ep) == length(names) - _DW_MATCH_ROWS
    kinds = (
        "equal",
        "mismatched_char",
        "transposed_char",
        "inserted_char",
        "separated",
        "transposed_word"
    )
    for k in kinds
        @test _dw_count(em, k) >= 8                                       # every kind is answered, in many pairs
    end
    @test _dw_count(em, "fail") >= 100                                    # and the pairs that match nothing
    @test _dw_count(ep, "foo_bar") >= 15 && _dw_count(ep, "foo_baz") >= 8 # procedures are answered
    @test _dw_count(ep, "decl_only") >= 1 && _dw_count(ep, "mf_pred") >= 1 &&
        _dw_count(ep, "disc_pred") >= 1
    # row t34 (unknown=warning): both warnings and the near procedure's line are in swipl's answer
    @test _dw_count(ep, "unknown_in_module_user") == 1 &&
        _dw_count(ep, "  However, there are definitions for:") == 1 &&
        _dw_count(ep, "dwim_target_pred") == 1

    kl = kernel_lines(_TL, _DW_PL, names)
    @test length(kl) == length(expected)
    # the same extractor over the kernel's lines: the kernel answers every kind, not only the same number of lines
    km = kl[2:min(_DW_MATCH_ROWS + 1, end)]
    kp = kl[min(_DW_MATCH_ROWS + 2, end + 1):end]
    for k in kinds
        @test _dw_count(km, k) == _dw_count(em, k) && _dw_count(km, k) >= 8
    end
    @test _dw_count(km, "fail") == _dw_count(em, "fail") && _dw_count(km, "fail") >= 100
    @test _dw_count(kp, "foo_bar") == _dw_count(ep, "foo_bar") &&
        _dw_count(kp, "foo_bar") >= 15
    @test _dw_count(kp, "unknown_in_module_user") == 1 &&
        _dw_count(kp, "  However, there are definitions for:") == 1 &&
        _dw_count(kp, "dwim_target_pred") == 1
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "DWIM DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_DW_PL, names) == expected                          # the .out is swipl's, still
    end
end
