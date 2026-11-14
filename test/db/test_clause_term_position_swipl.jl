# ORIGINAL: R2's LB5-LB7 gate — '$clause_term_position'/3 (pl-comp.c:8584-8900); no swipl-devel counterpart (its tests step through the debugger).
# test/db/test_clause_term_position_swipl.jl — the term position of a call, compared with live swipl, through a program (the pattern of
# test/db/test_nth_clause_swipl.jl: each case a predicate `t_<id>(R)`, the kernel consults the program, swipl runs a driver, the lines are
# compared; EVERY expected value is swipl's own answer). A case asks `'$clause_term_position'(Ref, PC, Pos)` for EVERY PC from 0 to 60 of one
# clause and lists `PC-Pos` for each answer, `PC-dom(Domain, Message)` for a domain error (a PC past the code, a PC inside a `\\+`), and
# nothing for a failure. The clauses use atoms and variables only: the code words per instruction are then the same on both sides.
# UNTESTED when written (nothing compiled, LB5-LB7 relay 10): a failing row here shows a gap of the port or of the code layout.
using Test, LogicKernel

const LK = LogicKernel


# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"

# the answer lines' encoding of a term (the driver's `enc/3` prints the same); a clause blob is `clref`
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
        is_blob(t) && return blob_type(t) === :clause ? "clref" : "blob"
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

# ---- the program: swipl's rows. `ctp/2` lists the answers of '$clause_term_position'/3 for PC 0..60; pN/1 are static, one clause each
const _PROGRAM = """
             :- dynamic dp1/1.
             ctp1(Ref, PC, P) :-
                 catch('\$clause_term_position'(Ref, PC, P0), error(E, C), true),
                 (   nonvar(E)
                 ->  (   E = domain_error(D, _), C = context(_, M)
                     ->  P = dom(D, M)
                     ;   P = err(E)
                     )
                 ;   P = P0
                 ).
             ctp(Ref, R) :- findall(PC-P, ( between(0, 60, PC), ctp1(Ref, PC, P) ), R).
             ex(G, R) :- catch(( G, R = true ), error(E, _), R = err(E)).
             p01(a).
             p02(X) :- q(X).
             p03(X) :- q(X), r(X), s(X).
             p04(X) :- ( q(X) ; r(X) ), s(X).
             p05(X) :- ( q(X) -> r(X) ; s(X) ), t(X).
             p06(X) :- ( q(X) *-> r(X) ; s(X) ), t(X).
             p07(X) :- ( q(X) -> r(X) ), t(X).
             p08(X) :- \\+ q(X), r(X).
             p09(X) :- X = f(Y), q(Y), r(X).
             p10(X) :- q(X), !, r(X).
             p11(X), q(X) => r(X).
             p12(X) :- ( q(X), ( r(X) ; s(X) ) -> t(X) ; u(X) ).
             mq:p13(X) :- q(X).
             p14(X) :- q(X), ( r(X) ; s(X) ).
             p15(X) :- ( q(X) -> r(X) ; s(X) ).
             p16(X) :- \\+ ( q(X), r(X) ), s(X).
             p17(X, Y) :- Y = [X|_], q(Y).
             p18(X) :- ( q(X) -> ( r(X) -> s(X) ; t(X) ) ; u(X) ), v(X).
             p19(X) :- ( q(X) -> r(X) ), ( s(X) -> t(X) ), u(X).
             p20(X) :- ( \\+ q(X) -> r(X) ; s(X) ), t(X).
             p21(X) :- ( q(X) -> ( r(X) ; s(X) ) ), t(X).
             p22(X) :- ( q(X) -> \\+ r(X), s(X) ), t(X).
             p23(X) :- ( q(X) -> ( r(X) -> s(X) ; t(X) ) ), u(X).
             p24(X) :- ( q(X) -> ( r(X) -> s(X) ) ), t(X).
             p25(X) :- ( q(X) *-> ( r(X) -> s(X) ; t(X) ) ), u(X).
             """

# (id, goal). `ex/2` returns `true` or `err(Formal)`.
const _CASES = [
    # ---- the constructs: a fact, a call, a conjunction, `;`, `->`, `*->`, `->` without else, `\\+`, unification, `!`, SSU, the nests
    ("c01", "nth_clause(p01(_), 1, Ref), ctp(Ref, R)"),
    ("c02", "nth_clause(p02(_), 1, Ref), ctp(Ref, R)"),
    ("c03", "nth_clause(p03(_), 1, Ref), ctp(Ref, R)"),
    ("c04", "nth_clause(p04(_), 1, Ref), ctp(Ref, R)"),
    ("c05", "nth_clause(p05(_), 1, Ref), ctp(Ref, R)"),
    ("c06", "nth_clause(p06(_), 1, Ref), ctp(Ref, R)"),
    ("c07", "nth_clause(p07(_), 1, Ref), ctp(Ref, R)"),
    ("c08", "nth_clause(p08(_), 1, Ref), ctp(Ref, R)"),
    ("c09", "nth_clause(p09(_), 1, Ref), ctp(Ref, R)"),
    ("c10", "nth_clause(p10(_), 1, Ref), ctp(Ref, R)"),
    ("c11", "nth_clause(p11(_), 1, Ref), ctp(Ref, R)"),
    ("c12", "nth_clause(p12(_), 1, Ref), ctp(Ref, R)"),
    ("c13", "nth_clause(mq:p13(_), 1, Ref), ctp(Ref, R)"),
    ("c14", "nth_clause(p14(_), 1, Ref), ctp(Ref, R)"),
    ("c15", "nth_clause(p15(_), 1, Ref), ctp(Ref, R)"),
    ("c16", "nth_clause(p16(_), 1, Ref), ctp(Ref, R)"),
    ("c17", "nth_clause(p17(_, _), 1, Ref), ctp(Ref, R)"),
    ("c18", "nth_clause(p18(_), 1, Ref), ctp(Ref, R)"),
    ("c19", "nth_clause(p19(_), 1, Ref), ctp(Ref, R)"),
    ("c20", "nth_clause(p20(_), 1, Ref), ctp(Ref, R)"),
    ("c21", "nth_clause(p21(_), 1, Ref), ctp(Ref, R)"),
    ("c22", "nth_clause(p22(_), 1, Ref), ctp(Ref, R)"),
    ("c23", "nth_clause(p23(_), 1, Ref), ctp(Ref, R)"),
    ("c24", "nth_clause(p24(_), 1, Ref), ctp(Ref, R)"),
    ("c25", "nth_clause(p25(_), 1, Ref), ctp(Ref, R)"),
    # ---- the arguments: a dynamic clause, an erased clause (upstream goes on: `PL_get_clref` answers -1), a bad reference, a bad PC
    ("e01", "assertz((dp1(X) :- q(X), r(X)), Ref), ctp(Ref, R)"),
    ("e02", "assertz((dp1(X) :- q(X), r(X)), Ref), erase(Ref), ctp(Ref, R)"),
    ("e03", "ex('\$clause_term_position'(foo, 0, _), R)"),
    ("e04", "nth_clause(p02(_), 1, Ref), ex('\$clause_term_position'(Ref, a, _), R)"),
    ("e05", "nth_clause(p02(_), 1, Ref), ex('\$clause_term_position'(Ref, -1, _), R)"),
    ("e06", "nth_clause(p02(_), 1, Ref), ex('\$clause_term_position'(Ref, _, _), R)"),
    ("e07", "ex('\$clause_term_position'(_, 0, _), R)"),
    ("e08", "nth_clause(p02(_), 1, Ref), ex('\$clause_term_position'(Ref, 1.5, _), R)"),
    # LAST: nothing follows
    ("z01", "R = last")
]

# ---- the kernel's lines: for each case, `<name> <answers>`
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
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

# swipl's side. `enc/3` as the kernel's `enc` (a clause blob is `clref`, any other blob `blob`).
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- blob(T, clause), !, write(clref).
enc(T, S, S) :- atom(T), blob(T, text), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- blob(T, _), !, write(blob).
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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

"Run swipl on a program file: its output lines."
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


_swipl() = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")

@testset "'\$clause_term_position'/3 == live swipl, through a program" begin
    if _swipl() === nothing
        @info "CLAUSE_TERM_POSITION DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_CASES) >= 20 && allunique(first.(_CASES)) && _CASES[end][1] == "z01"     # the table is whole
    else
        names = ["t_$(id)" for (id, _) in _CASES]
        f = joinpath(realpath(mktempdir()), "p.pl")
        text = _PROGRAM * join(["t_$(id)(R) :- ( $g -> true ).\n" for (id, g) in _CASES])
        write(f, text)
        kl = kernel_lines(f, names)
        sw = swipl_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw)
        for (k, s) in zip(kl, sw)
            @test k == s
        end
        # not a vacuous agreement: swipl's own lines hold answers (a guard that fails on an empty side)
        # the PCs past the code are domain errors (every row has them: the range is 0..60); a PC inside a `\\+` is another
        @test all(l -> !startswith(l, "t_c") || occursin(_codes("-"), l), sw)       # every construct row holds PC-Pos pairs
        @test count(l -> occursin(_codes("not in clause executable code"), l), sw) >= 25
        @test count(l -> startswith(l, "t_") && occursin(_codes("exit"), l), sw) == 27   # 25 construct rows + e01 + e02
        @test count(l -> occursin(_codes("not a possible continuation"), l), sw) == 4
        for id in ("c08", "c16", "c20", "c22")
            @test any(
                l ->
                    startswith(l, "t_$(id) ") &&
                    occursin(_codes("not a possible continuation"), l),
                sw
            )
        end
        @test any(l -> startswith(l, "t_e03 ") && occursin(_codes("db_reference"), l), sw)
        @test any(l -> startswith(l, "t_e04 ") && occursin(_codes("integer"), l), sw)
        @test any(
            l -> startswith(l, "t_e05 ") && occursin(_codes("program_counter"), l), sw
        )
        @test any(
            l -> startswith(l, "t_e06 ") && occursin(_codes("instantiation_error"), l), sw
        )
        @test any(l -> startswith(l, "t_e02 ") && occursin("i1", l), sw)           # the erased clause still answers
    end
end
