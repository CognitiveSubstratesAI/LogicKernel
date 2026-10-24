# ORIGINAL: a LIVE differential of retractall/1 (pl-proc.c; registered 2026-10-24, audit D-0127 item 2, D-0130 item 3)
# test/db/test_retractall_swipl.jl — retractall/1 against swipl at the pin, through a PROGRAM: each case is a predicate
# `tN(R)` whose body asserts clauses, calls retractall/1 and reports what is left (or the error it raised, as the formal
# term); the kernel consults the program and enumerates every solution of every tN/1, swipl does the same through a
# driver, and the answers are compared as lines. The white-box side (generations, the occurs check, the bindings undone)
# is test_clause_variables.jl and test/db/index_*.jl. The cases include a head with a repeated variable, a rule, a
# predicate never seen (created dynamic), a static one and a built-in (permission errors), a non-callable and an unbound head.
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
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# error contexts the kernel and swipl name differently for the same call are NOT normalised here: they are mismatches.
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                # a term the kernel cannot export (a cycle) is a line of its own, never a throw that ends the file
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
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
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



const _RA_PROGRAM = """
:- dynamic q/1, p/2, f/2, g/1, e/0.
st(1).
st(2).
"""
const _RA_CASES = [
    "assertz(q(1)), assertz(q(2)), retractall(q(_)), findall(X, q(X), R)",
    "assertz(p(1, a)), assertz(p(2, b)), assertz(p(1, c)), retractall(p(1, _)), findall(X-Y, p(X, Y), R)",
    "retractall(nd(_)), ( catch(nd(1), error(E, _), true) -> R = hit(E) ; R = no )",
    "catch(retractall(st(_)), error(E, _), true), R = E",
    "retractall(foo), ( catch(foo, error(E, _), true) -> R = hit(E) ; R = no )",
    "catch(retractall(3), error(E, _), true), R = E",
    "catch(retractall(_), error(E, _), true), R = E",
    "assertz(f(1, 1)), assertz(f(1, 2)), assertz(f(2, 2)), retractall(f(Z, Z)), findall(X-Y, f(X, Y), R)",
    "catch(retractall(atom(_)), error(E, _), true), R = E",
    "assertz((g(X) :- X > 1)), assertz(g(5)), retractall(g(_)), findall(X, g(X), R)",
    "assertz(e), assertz(e), retractall(e), ( e -> R = still ; R = gone )",
    "retractall(q(_)), retractall(q(_)), findall(X, q(X), R)",
    "assertz(p(a, 1)), assertz(p(b, 2)), retractall(p(c, _)), findall(X-Y, p(X, Y), R0), msort(R0, R)",
    "assertz(p(f(1), x)), assertz(p(f(2), y)), retractall(p(f(_), x)), findall(X-Y, p(X, Y), R)",
    "catch(retractall(\"str\"), error(E, _), true), R = E",
    "catch(retractall(f(_, _, _)), error(E, _), true), ( var(E) -> R = ok ; R = E )"
]

@testset "retractall/1 == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "RETRACTALL DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t$(i - 1)" for i in eachindex(_RA_CASES)]
        text =
            _RA_PROGRAM *
            join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(_RA_CASES)])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: swipl answered every case, and some by an error, some by a list
        @test count(l -> occursin("114,114,111,114", l), sw) >= 4         # an `…rror` atom: the error cases
        @test count(l -> occursin("c[91,124,93]/2", l), sw) >= 4         # a list: what was left
    end
end
