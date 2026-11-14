# ORIGINAL: a differential of pl-vmi.c A_IS's CHECK_WAKEUP (an attributed variable bound by `is/2` compiled under `optimise`) against swipl at the pin
# test/core_lang/test_arith_wakeup_swipl.jl — AR1's rows for the `_TS_CHECK_WAKEUP` exit of `_vmi_a_is!` (src/pl-wam.jl), through a
# PROGRAM (the pattern of test_arith_round_swipl.jl): test_arith_wakeup_swipl.pl holds the rows, each a predicate `tN(R)`, compiled
# under `:- set_prolog_flag(optimise, true)`, so `X is Expr` is `A_ENTER .. A_IS`; the kernel consults it and enumerates every
# solution of every tN/1, its lines are compared with test_arith_wakeup_swipl.out — the pin's own swipl (10.1.20, 18168e62: two
# byte-identical runs). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale.
# UNTESTED on the kernel: written without a compile, the gate decides
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
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
        # the kernel's own float writer (write/1 and ~w: format_float(f, 3, 'e'), pl-write.c format_float) = the pin's
        # format("f~w"): Julia's string(::Float64) prints 1.7976931348623157e308 where swipl prints ...e+308 (HARNESS-DIFFERS)
        v isa AbstractFloat && return "f" * LK.format_float(Float64(v), 3, 'e')
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end


const _AW_PL = joinpath(@__DIR__, "test_arith_wakeup_swipl.pl")
const _AW_OUT = joinpath(@__DIR__, "test_arith_wakeup_swipl.out")

# the rows' names, in the order of the program
_aw_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_AW_PL, String))])

# the solutions of the row `name`/1, as `enc` lines (a Julia exception, a refusal included, is not caught here)
function _aw_row(gd, ld, name::String)::Vector{String}
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
    if proc === nothing || !LK.isDefinedProcedure(gd, proc)
        return String["$name undefined"]
    end
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    try
        n = 0
        while (n += 1) <= 100
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
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
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return String["$name" * join(" " .* sols)]
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        append!(out, _aw_row(gd, ld, name))
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
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


@testset "AR1: A_IS binding an attributed variable wakes its hook as swipl does (CHECK_WAKEUP)" begin
    names = _aw_names()
    expected = String.(readlines(_AW_OUT))
    # not a vacuous agreement: a line per row, the rows' own evidence is in it (the hook's log, the foreign call after it, the throw)
    @test length(names) == 9
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(
        l -> occursin("c" * _codes("-") * "/2(a" * _codes("ai") * ",i3)", l), expected
    ) >= 4
    @test any(l -> occursin("a" * _codes("z") * ",i0)", l), expected)       # the foreign call ran after the hook
    @test any(l -> occursin("a" * _codes("boom"), l), expected)             # the hook's exception
    @test any(l -> occursin("f5.0", l), expected)                           # the float result

    # the rows are compiled to A_IS (else they would test is/2 as a call, not the instruction)
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, _ = LK.load_file!(gd, ld, _AW_PL)
    @test st === :ok
    for name in vcat(filter(!=("t5"), names), ["t5b"])      # t5's `is` is in t5b (a goal inside catch/3 is called)
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        @test proc !== nothing
        cl = proc.definition.impl_clauses.first_clause.clause
        @test LK.A_IS in cl.codes
        @test LK.A_ENTER in cl.codes
    end

    kl = kernel_lines(_AW_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(expected)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AR1 A_IS WAKEUP DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        sw = swipl_lines(_AW_PL, names)
        @test sw == expected                                       # the .out is swipl's, still
    end
end
