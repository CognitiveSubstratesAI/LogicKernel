# ORIGINAL: R2's LB2 gate — compile_predicates/1 (pl-comp.c:5289), nth_clause/3 (pl-comp.c:7527) and '$get_clause_attribute'/3 (pl-proc.c:3910); no swipl-devel counterpart.
# test/db/test_nth_clause_swipl.jl — LB2's gate for the clause predicates (audit D-0244): ROWS as a program (the pattern of
# test/db/test_source_file_swipl.jl: each case a predicate `t_<id>(R)`, the kernel consults the program, swipl runs a driver, the lines are
# compared; EVERY expected value is swipl's own answer) plus white-box testsets for what swipl cannot be asked.
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


# q1..q20/1: dynamic, three facts each (a, b, c); a row that changes one has its own (the rows share one database)
const _QP = ":- dynamic " * join(["q$i/1" for i in 1:20], ", ") * ".\n" *
            join(["q$i(a).\nq$i(b).\nq$i(c).\n" for i in 1:20])

# ---- the program: swipl's rows (`t_<id>(R)`). dN/1 are dynamic with one fact each, e1/1 dynamic and empty, s1/1 static.
const _PROGRAM = """
:- dynamic d1/1, d2/1, d3/1, d4/1, d5/1, d6/1, d8/1, d9/1, d10/1, d11/1, d12/1, e1/1, d7/3.
d1(1).
d2(1).
d3(1).
d4(1).
d5(1).
d6(1).
d8(1).
d8(2).
d9(1).
d10(1).
d11(1).
d12(1).
d7(1, 2, 3).
s1(1).
ex(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
s2(a).
s2(b).
""" * _QP

# (id, goal). `ex/2` returns `true` or `err(Formal, Context)`.
const _CASES = [
    # ---- compile_predicates/1 (pl-comp.c:5289): a dynamic predicate becomes static: assertz refuses it afterwards
    ("c01", "compile_predicates([d1/1]), ex(assertz(d1(9)), R)"),
    ("c02", "compile_predicates([s1/1]), ex(assertz(s1(9)), R)"),
    ("c03", "compile_predicates([]), R = ok"),
    ("c04", "compile_predicates(user:[d2/1]), ex(assertz(d2(9)), R)"),
    ("c05", "compile_predicates([user:d3/1]), ex(assertz(d3(9)), R)"),
    ("c06", "ex(compile_predicates([nope/1]), R)"),
    ("c07", "ex(compile_predicates([nomod:nope/1]), R)"),
    ("c08", "ex(compile_predicates([d4/a]), R)"),
    ("c09", "ex(compile_predicates([d4/(-1)]), R)"),
    ("c10", "ex(compile_predicates([foo/1/2]), R)"),
    ("c11", "ex(compile_predicates([_]), R)"),
    ("c12", "ex(compile_predicates(_), R)"),
    ("c13", "ex(compile_predicates(foo), R)"),
    ("c14", "ex(compile_predicates([1]), R)"),
    ("c15", "ex(compile_predicates([d5/1|_]), R0), ex(assertz(d5(9)), R1), R = R0-R1"),
    ("c16", "compile_predicates([d6(_)]), ex(assertz(d6(9)), R)"),
    ("c17", "compile_predicates([d7//1]), ex(assertz(d7(9, 9, 9)), R)"),
    ("c18", "compile_predicates([d8/1]), findall(X, d8(X), R)"),
    ("c19", "compile_predicates([d9/1, d9/1]), ex(assertz(d9(9)), R)"),
    ("c20", "ex(compile_predicates([atom_length/2]), R)"),
    ("c21", "compile_predicates([system:atom_length/2]), R = ok"),
    ("c22", "ex(compile_predicates([d10/1, nope/1]), R0), ex(assertz(d10(9)), R1), R = R0-R1"),
    ("c23", "compile_predicates([e1/1]), ex(assertz(e1(9)), R)"),
    ("c24", "ex(compile_predicates([d11/foo]), R)"),
    ("c25", "ex(compile_predicates(user:foo), R)"),
    ("c26", "ex(compile_predicates([d12/1|foo]), R)"),
    ("c27", "ex(compile_predicates(nomod:[nope/1]), R)"),
    ("c28", "ex(compile_predicates([d8//1]), R)"),
    # ---- nth_clause/3 (pl-comp.c:7527): enumeration, the nth clause, the reference to the nth clause and back
    ("n01", "findall(N, nth_clause(q1(_), N, _), R)"),
    ("n02", "nth_clause(q2(_), 2, Ref), erase(Ref), findall(X, q2(X), R)"),
    ("n03", "( nth_clause(q3(_), 0, _) -> R = yes ; R = no )"),
    ("n04", "( nth_clause(q3(_), 4, _) -> R = yes ; R = no )"),
    ("n05", "( nth_clause(q3(_), -1, _) -> R = yes ; R = no )"),
    ("n06", "findall(Ref, nth_clause(q3(_), a, Ref), L), length(L, R)"),
    ("n07", "ex(nth_clause(q3(_), 1.0, _), R)"),
    ("n08", "ex(nth_clause(_, 1, _), R)"),
    ("n09", "( nth_clause(nope(_), 1, _) -> R = yes ; R = no )"),
    ("n10", "ex(nth_clause(q3(_), 1, foo), R)"),
    ("n11", "nth_clause(q4(_), 2, Ref), nth_clause(P, N, Ref), R = P-N"),
    ("n12", "nth_clause(q4(_), 2, R1), nth_clause(q4(_), 2, R2), ( R1 == R2 -> R = same ; R = diff )"),
    ("n13", "nth_clause(q5(_), 2, Ref), erase(Ref), ( nth_clause(P, N, Ref) -> R = yes(P, N) ; R = no )"),
    ("n14", "retract(q6(b)), findall(N, nth_clause(q6(_), N, _), R)"),
    ("n15", "findall(N, nth_clause(s2(_), N, _), R)"),
    ("n16", "( nth_clause(atom_length(_, _), 1, _) -> R = yes ; R = no )"),
    ("n17", "( nth_clause(e1(_), 1, _) -> R = yes ; R = no )"),
    ("n18", "nth_clause(q7(_), 3, Ref), erase(Ref), findall(X, q7(X), R)"),
    ("n19", "findall(N, nth_clause(q8(a), N, _), R)"),
    ("n20", "nth_clause(user:q8(_), 2, Ref), nth_clause(P, N, Ref), R = P-N"),
    ("n21", "findall(N, ( nth_clause(q9(_), N, _), assertz(q9(z)) ), R)"),
    ("n22", "findall(N, ( nth_clause(q10(_), N, Ref), erase(Ref) ), R)"),
    ("n23", "retract(q11(a)), nth_clause(q11(_), 1, Ref), nth_clause(_, N, Ref), R = N"),
    ("n24", "ex(nth_clause(q3(_), 1, 1), R)"),
    ("n25", "nth_clause(q12(_), 3, Ref), ( nth_clause(q12(_), 2, Ref) -> R = yes ; R = no )"),
    ("n26", "nth_clause(q13(_), 2, Ref), ( nth_clause(q14(_), N, Ref) -> R = yes(N) ; R = no )"),
    ("n27", "nth_clause(q13(_), 2, Ref), nth_clause(q13(a), N, Ref), R = N"),
    ("n28", "nth_clause(q13(_), 2, Ref), nth_clause(user:q13(_), N, Ref), R = N"),
    ("n29", "nth_clause(q13(_), 2, Ref), ( nth_clause(nomod:q13(_), N, Ref) -> R = yes(N) ; R = no )"),
    ("n30", "nth_clause(q13(_), 2, Ref), ( nth_clause(system:q13(_), N, Ref) -> R = yes(N) ; R = no )"),
    ("n31", "nth_clause(q13(_), 2, Ref), nth_clause(M:q13(_), N, Ref), R = M-N"),
    ("n32", "( nth_clause(q13/1, 1, _) -> R = yes ; R = no )"),
    ("n33", "findall(Ref, nth_clause(q15(_), _, Ref), L), sort(L, S), length(S, R)"),
    ("n34", "( nth_clause(q16(_), N, _), ! ), assertz(q16(z)), findall(X, q16(X), L), R = N-L"),
    ("n35", "assertz(mq:r(1)), nth_clause(mq:r(_), 1, Ref), nth_clause(P, N, Ref), R = P-N"),
    ("n36", "( nth_clause(mq2:r(_), 1, _) -> R = yes ; R = no )"),
    ("n37", "findall(N, nth_clause(q17(_), N, _), L), L = [_|_], nth_clause(q17(_), 3, Ref), erase(Ref), findall(N2, nth_clause(q17(_), N2, _), R)"),
    ("n38", "nth_clause(q18(_), 1, Ref), erase(Ref), nth_clause(q18(_), 1, Ref2), erase(Ref2), findall(X, q18(X), R)"),
    ("n39", "nth_clause(q19(_), 2, Ref), retract(q19(b)), ( nth_clause(q19(_), N, Ref) -> R = yes(N) ; R = no )"),
    # LAST: nothing follows
    ("z01", "R = last")
]

# ---- the kernel's lines: for each case, `<name> <answers>`
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


# ---- the kernel's calls, one built-in at a time (the white-box testsets)
"Call the system predicate `name` on `args`: `(status, answers)`; status `:true`, `:false` or `:exception` (the ball is the answer)."
function kcall(gd::LK.PL_global_data{T}, ld, name::String, args::Vector{T}) where {T}
    proc = LK.isCurrentProcedure(
        sym_key(lk_sym(T, Symbol(name))), length(args), LK.MODULE_system(gd)
    )
    @assert proc !== nothing "no system predicate $name/$(length(args))"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    status = :false
    ans = T[]
    rc = LK.PL_next_solution(gd, ld, qid)
    if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        status = :true
        ans = lk_answers(ld, [a + i - 1 for i in 1:length(args)]...)
    elseif rc == LK.PL_S_EXCEPTION
        status = :exception
        ans = T[lk_answer(ld, LK.PL_exception(ld, qid))]
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return status, ans
end


_swipl() = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")


@testset "compile_predicates/1 and nth_clause/3 == live swipl, through a program" begin
    if _swipl() === nothing
        @info "NTH_CLAUSE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_CASES) >= 20 && allunique(first.(_CASES)) && _CASES[end][1] == "z01"     # the table is whole
    else
        names = ["t_$(id)" for (id, _) in _CASES]
        f = joinpath(realpath(mktempdir()), "p.pl")
        text =
            _PROGRAM *
            join(["t_$(id)(R) :- ( $g -> true ).\n" for (id, g) in _CASES])
        write(f, text)
        kl = kernel_lines(f, names)
        sw = swipl_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw)
        for (k, s) in zip(kl, sw)
            @test k == s
        end
        # not a vacuous agreement: swipl's own lines hold each kind of answer (a guard that fails on an empty side)
        # measured on swipl 10.1.19 (2026-10-29): domain c09; existence c06 c07 c20 c22 c27 c28; instantiation c11 c12 c15;
        # type c08 c10 c13 c14 c24 c25 c26 n10 n24; permission c01 c02 c04 c05 c15 c16 c17 c19 c22 (the assertz after a compile);
        # instantiation also n08

        @test count(l -> occursin(_codes("domain_error"), l), sw) == 1
        @test count(l -> occursin(_codes("existence_error"), l), sw) == 6
        @test count(l -> occursin(_codes("instantiation_error"), l), sw) == 4
        @test count(l -> occursin(_codes("type_error"), l), sw) == 9
        @test count(l -> occursin(_codes("permission_error"), l), sw) == 9
        @test any(l -> startswith(l, "t_c03 ") && occursin(_codes("ok"), l), sw)
        @test any(l -> startswith(l, "t_c18 ") && occursin("i1", l) && occursin("i2", l), sw)       # the clauses survive
        @test any(l -> startswith(l, "t_c23 ") && occursin(_codes("true"), l), sw)                  # an EMPTY dynamic predicate: assertz still works
        # nth_clause/3: the enumeration answers 1,2,3; the erased reference finds nothing; a non-integer index still enumerates (the
        # unify results are ignored upstream); the reference gives back the index and the (unqualified) head
        @test any(l -> startswith(l, "t_n01 ") && occursin("i1", l) && occursin("i2", l) && occursin("i3", l), sw)
        @test any(l -> startswith(l, "t_n06 ") && occursin("i3", l), sw)
        @test any(l -> startswith(l, "t_n11 ") && occursin("i2", l) && occursin(_codes("q4"), l), sw)
        @test any(l -> startswith(l, "t_n35 ") && occursin(_codes("mq"), l) && occursin(_codes(":"), l), sw)
        @test count(l -> occursin(_codes("no"), l), sw) >= 10
        @test startswith(last(sw), "t_z01 ")
    end
end

# ---- white-box
function _loaded(src::String)
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = joinpath(realpath(mktempdir()), "w.pl")
    write(f, src)
    st, ball, _ = LK.load_file!(gd, ld, f)
    @assert st === :ok
    return gd, ld, f
end

_f(name, args...) = mk_expr(_TL, _TL[_tls(name), args...])
_v() = mk_var(_TL, LK.fresh_var_keys!(1))
_pi(n, a) = _f("/", _tls(n), lk_gnd(_TL, a))
_list(xs...) = isempty(xs) ? mk_nil(_TL) : _f("[|]", xs[1], _list(xs[2:end]...))

@testset "compile_predicates/1 clears P_DYNAMIC and P_TRANSACT; the clauses stay; a second call changes nothing" begin
    gd, ld, f = _loaded(":- dynamic d/1.\nd(1).\nd(2).\ns(1).\n")
    d = LK.isCurrentProcedure(sym_key(_tls("d")), 1, LK.MODULE_user(gd)).definition
    s = LK.isCurrentProcedure(sym_key(_tls("s")), 1, LK.MODULE_user(gd)).definition
    @test (d.flags & LK.P_DYNAMIC) != 0 && (d.flags & LK.P_TRANSACT) != 0 && (s.flags & LK.P_DYNAMIC) == 0
    st, _ = kcall(gd, ld, "compile_predicates", _TL[_list(_pi("d", 1), _pi("s", 1))])
    @test st === :true
    @test (d.flags & (LK.P_DYNAMIC | LK.P_TRANSACT)) == 0 && (s.flags & LK.P_DYNAMIC) == 0
    @test LK.isDefinedProcedure(gd, LK.isCurrentProcedure(sym_key(_tls("d")), 1, LK.MODULE_user(gd)))
    flags1 = d.flags
    st, _ = kcall(gd, ld, "compile_predicates", _TL[_list(_pi("d", 1))])
    @test st === :true && d.flags == flags1
    # a predicate that is only in `system` is not found in `user` (GP_FINDHERE), and the culprit is the `M:Head` it built
    st, ans = kcall(gd, ld, "compile_predicates", _TL[_list(_pi("atom_length", 2))])
    @test st === :exception
    line = enc(ans[1])
    @test occursin(_codes("existence_error"), line) && occursin(_codes("atom_length"), line) && occursin(_codes("user"), line)
end

@testset "get_functor_procedure: Name//Arity adds 2, the arity limit, a head, a non-PI" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    function fp(x)
        t = LK.PL_new_term_ref(ld)
        LK.putSlotValue!(ld, t + 1, x, LK.PutVarMap())
        return LK.get_functor_procedure(ld, t)
    end
    n, a = fp(_f("/", _tls("p"), lk_gnd(_TL, 3)))
    @test sym_key(n) == sym_key(_tls("p")) && a == 3
    n, a = fp(_f("//", _tls("p"), lk_gnd(_TL, 3)))
    @test a == 5
    n, a = fp(_f("q", lk_gnd(_TL, 1), lk_gnd(_TL, 2)))
    @test sym_key(n) == sym_key(_tls("q")) && a == 2
    n, a = fp(_tls("r"))
    @test sym_key(n) == sym_key(_tls("r")) && a == 0
    n, a = fp(lk_gnd(_TL, 1))
    @test a == -1 && LK.PL_exception(ld, 0) != 0                              # type_error(predicate_indicator, 1)
    LK.PL_clear_exception(ld)
    n, a = fp(_f("/", _tls("p"), lk_gnd(_TL, LK.MAXARITY + 1)))
    @test a == -1 && LK.PL_exception(ld, 0) != 0                              # representation_error(max_procedure_arity)
end

@testset "nth_clause/3: no state or predicate reference is left behind (a cut, the last answer, a bound index, a bound reference)" begin
    gd, ld, f = _loaded(":- dynamic d/1.\nd(1).\nd(2).\nd(3).\none(1).\n")
    dh = _f("d", _v())
    nth(args...) = kcall(gd, ld, "nth_clause", _TL[args...])
    st, ans = nth(dh, _v(), _v())                                # first answer, then the query is closed: the FRG_CUTTED call
    @test st === :true && lk_value(ans[2]) == 1
    @test ld.clause_contexts.live == 0 && isempty(ld.predicate_references)
    st, ans1 = nth(_f("one", _v()), _v(), _v())                  # the last answer: the state is freed before the query is closed
    @test st === :true && lk_value(ans1[2]) == 1
    @test ld.clause_contexts.live == 0 && isempty(ld.predicate_references)
    st, ans = nth(dh, lk_gnd(_TL, 3), _v())                      # a bound index: no state at all
    @test st === :true
    @test ld.clause_contexts.live == 0 && isempty(ld.predicate_references)
    st, _ = nth(dh, lk_gnd(_TL, 4), _v())
    @test st === :false && ld.clause_contexts.live == 0 && isempty(ld.predicate_references)
    ref = ans[3]                                                 # the reference to the third clause gives back its index and head
    st, ans2 = nth(_v(), _v(), ref)
    @test st === :true && lk_value(ans2[2]) == 3 && kind(ans2[1]) === EXPR &&
          ld.clause_contexts.live == 0 && isempty(ld.predicate_references)
    # the bound head of the by-reference branch: a head of another predicate, a module that is no super module
    st, _ = nth(_f("e", _v()), _v(), ref)
    @test st === :false && isempty(ld.predicate_references)
    st, _ = nth(_f(":", _tls("nomod"), dh), _v(), ref)
    @test st === :false && isempty(ld.predicate_references)
    st, ans3 = nth(_f(":", _tls("user"), dh), _v(), ref)
    @test st === :true && lk_value(ans3[2]) == 3
end
