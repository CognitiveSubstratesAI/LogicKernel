# ORIGINAL: R2's LB6-CLAUSEPROP rows — clause_property/2 (boot/syspred.pl:1093-1111, Prolog over pl-proc.c get_clause_attribute) on a consulted file; no swipl-devel counterpart.
# test/db/test_clause_property_swipl.jl — what `clause_property(+Ref, ?Property)` answers for the clauses of a CONSULTED FILE and for asserted
# clauses, through the kernel's booted system (boot/syspred.pl is loaded from the template, `'$get_clause_attribute'/3` is LB2's
# pl-proc.jl `pl_get_clause_attribute3_va`; the loader's `'$record_clause'/4` is pl-comp.jl `record_clause`, which stores `line_no`, `source_no`,
# `owner_no` in the clause: pl-comp.jl `assert_term!`). Test_nth_clause_swipl.jl (LB2) asks `'$get_clause_attribute'/3` for a program whose clauses
# have ONE file; these rows add what only a file with an INCLUDE, a multi-line clause, a `'$source_location'(File, Line):Clause` expansion
# and an asserted clause tell apart: `file` (the source_no), `source` (the owner_no) and `line_count` (the line of the term's START).
#   * A PROGRAM `cp.pl` (+ the included `cpinc.pl`) and cases `t_<id>(R)`, each wrapped in `catch(Goal, error(E, _), R = raised(E))`; every row
#     runs IN ORDER in one database. Paths are shown as base names (`cp_base/2`: the temp directory differs per run).
#   * Every swipl answer line is PINNED (swipl 10.1.20, this program and driver, LC_ALL=C, 2026-11-14, two runs byte-identical); with `swipl` on PATH
#     the live answers are compared with the pins too. The `size` value is the kernel's own formula (LB2 DIVERGES): rows ask integer(S), S > 0.
#   * UNVERIFIED on the kernel: the gate decides (a mismatch is traced to its upstream cause, not re-pinned).
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_cps(x) = lk_sym(_CP, Symbol(x))

"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms by name, compounds `name(args)`."
function _cp_enc(t::_CP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return if is_nil(t)
            "[]"
        elseif is_blob(t)
            "<blob>"
        else
            sym_text(t)
        end
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s\"" * String(v) * "\""
        v isa Integer && return "$v"
        v isa AbstractFloat && return "$v"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "[]" : sym_text(h)) * "(" *
           join([_cp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the CONT1 driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _CP_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write('[]').
enc(T, S, S) :- atom(T), !, write(T).
enc(T, S, S) :- string(T), !, format("s\"~w\"", [T]).
enc(T, S, S) :- integer(T), !, format("~w", [T]).
enc(T, S, S) :- float(T), !, format("~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    write(N), format("(", []), encargs(1, A, T, S0, S), write(')').
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

function _cp_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the included file: its clauses have FILE `cpinc.pl`, OWNER `cp.pl`; line_count is the line in `cpinc.pl` (2, 3)
const _CP_INC = raw"""
% the included file
cp_i(1).
cp_i(2) :-
    true.
"""

# the program. LINE NUMBERS ARE THE POINT: cp_r/1 at 1, 3 (a clause of two lines) and 5; cp_s/1 (three lines) at 7; the dynamic cp_d/1 at 11 and 12;
# the include at 13 (its clauses are at lines 2 and 3 of cpinc.pl); cp_t/1 at 14; the expansion's clause cp_x2/1 is `'$source_location'(File, 77):...`
const _CP_PROGRAM = raw"""
cp_r(a).

cp_r(b) :-
    true.
cp_r(c).

cp_s(X) :-
    cp_r(X),
    true.
:- dynamic cp_d/1.
cp_d(1).
cp_d(2).
:- include(cpinc).
cp_t(z).
cp_base(F, B) :-
    (   atom(F), atom_concat(_, '/cp.pl', F) -> B = 'cp.pl'
    ;   atom(F), atom_concat(_, '/cpinc.pl', F) -> B = 'cpinc.pl'
    ;   B = F
    ).
cp_yn(G, R) :- ( call(G) -> R = y ; R = n ).
term_expansion(cp_x(N), '$source_location'('/zz/fake.pl', 77):cp_x2(N)).
cp_x(1).
"""

# (id, goal). Each answers R; the clause references come from clause/3 (the consulted clauses) or assertz/2.
const _CP_CASES = [
    # ---- line_count: the line a term STARTS at (a two-line clause: its first line)
    (
        "p01",
        raw"findall(L, (clause(cp_r(_), _, Ref), clause_property(Ref, line_count(L))), R)"
    ),
    ("p02", raw"clause(cp_s(_), _, Ref), clause_property(Ref, line_count(R))"),
    # ---- file and source (owner) of consulted clauses: the same file
    (
        "p03",
        raw"findall(B, (clause(cp_r(_), _, Ref), clause_property(Ref, file(F)), cp_base(F, B)), R)"
    ),
    (
        "p04",
        raw"findall(B, (clause(cp_r(_), _, Ref), clause_property(Ref, source(F)), cp_base(F, B)), R)"
    ),
    ("p05", raw"clause(cp_t(_), _, Ref), clause_property(Ref, line_count(R))"),
    # ---- the included file: file = the included file, source = the includer, line_count counts in the included file
    (
        "p06",
        raw"findall(L-B, (clause(cp_i(_), _, Ref), clause_property(Ref, line_count(L)), clause_property(Ref, file(F)), cp_base(F, B)), R)"
    ),
    (
        "p07",
        raw"findall(B, (clause(cp_i(_), _, Ref), clause_property(Ref, source(F)), cp_base(F, B)), R)"
    ),
    # ---- the expansion's `'$source_location'(File, Line):Clause`: the file and line it names, the owner is the loading file
    (
        "p08",
        raw"clause(cp_x2(_), _, Ref), clause_property(Ref, line_count(L)), clause_property(Ref, file(F)), clause_property(Ref, source(S)), cp_base(S, SB), R = L-F-SB"
    ),
    # ---- fact (body true: a unit clause), predicate, module
    (
        "p09",
        raw"findall(N-Y, (member(N-K, [r-cp_r(_), s-cp_s(_)]), clause(K, _, Ref), cp_yn(clause_property(Ref, fact), Y)), R)"
    ),
    ("p10", raw"clause(cp_r(a), _, Ref), clause_property(Ref, predicate(R))"),
    ("p11", raw"clause(cp_r(a), _, Ref), clause_property(Ref, module(R))"),
    # ---- erased: no before the erase, yes after; an erased reference still answers its predicate and line
    (
        "p12",
        raw"clause(cp_d(1), _, Ref), cp_yn(clause_property(Ref, erased), A), erase(Ref), cp_yn(clause_property(Ref, erased), B), R = A-B"
    ),
    (
        "p13",
        raw"clause(cp_d(2), _, Ref), erase(Ref), clause_property(Ref, line_count(L)), clause_property(Ref, predicate(P)), R = L-P"
    ),
    # ---- an asserted clause has no file, no line, no owner; its predicate and module are answered
    (
        "p14",
        raw"assertz(cp_d(3), Ref), cp_yn(clause_property(Ref, file(_)), F), cp_yn(clause_property(Ref, line_count(_)), L), cp_yn(clause_property(Ref, source(_)), S), R = F-L-S"
    ),
    (
        "p15",
        raw"assertz(cp_d(4), Ref), clause_property(Ref, predicate(P)), clause_property(Ref, module(M)), cp_yn(clause_property(Ref, fact), Fa), R = P-M-Fa"
    ),
    (
        "p16",
        raw"assertz(cpm:cp_m(1), Ref), clause_property(Ref, predicate(P)), clause_property(Ref, module(M)), R = P-M"
    ),
    (
        "p17",
        raw"assertz((cp_d(5) :- true), Ref), clause_property(Ref, predicate(P)), cp_yn(clause_property(Ref, fact), Fa), R = P-Fa"
    ),
    # ---- the enumeration of Property (the order of `'$clause_property'/2`) and size
    (
        "p18",
        raw"findall(K, (clause(cp_r(a), _, Ref), clause_property(Ref, P), functor(P, K, _)), R)"
    ),
    (
        "p19",
        raw"clause(cp_r(a), _, Ref), clause_property(Ref, size(S)), ( integer(S), S > 0 -> R = ok ; R = S )"
    ),
    (
        "p20",
        raw"assertz(cp_d(6), Ref), findall(K, (clause_property(Ref, P), functor(P, K, _)), R)"
    ),
    # ---- failures and errors
    ("p21", raw"clause(cp_r(a), _, Ref), cp_yn(clause_property(Ref, foo(_)), R)"),
    ("p22", raw"clause_property(foo, line_count(_))"),
    ("p23", raw"clause_property(_, fact)"),
    ("p24", raw"clause(cp_r(a), _, Ref), cp_yn(clause_property(Ref, line_count(99)), R)"),
    ("p25", raw"clause(cp_r(c), _, Ref), cp_yn(clause_property(Ref, line_count(5)), R)"),
    # LAST: nothing follows
    ("z01", "R = last")
]

"The program files in one directory and the case predicates' names."
function _cp_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _CP_CASES]
    d = realpath(mktempdir())
    write(joinpath(d, "cpinc.pl"), _CP_INC)
    text =
        _CP_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(E, _), R = raised(E)).\n" for
            (id, g) in _CP_CASES
        ])
    f = joinpath(d, "cp.pl")
    write(f, text)
    return f, names
end

# swipl 10.1.20, LC_ALL=C, 2026-11-14, two runs byte-identical (`swipl -q` on the driver and this program)
const _CP_PINNED = String[
    raw"ok",
    raw"t_p01 t_p01([|](1,[|](3,[|](5,[]))))",
    raw"t_p02 t_p02(7)",
    raw"t_p03 t_p03([|](cp.pl,[|](cp.pl,[|](cp.pl,[]))))",
    raw"t_p04 t_p04([|](cp.pl,[|](cp.pl,[|](cp.pl,[]))))",
    raw"t_p05 t_p05(14)",
    raw"t_p06 t_p06([|](-(2,cpinc.pl),[|](-(3,cpinc.pl),[])))",
    raw"t_p07 t_p07([|](cp.pl,[|](cp.pl,[])))",
    raw"t_p08 t_p08(-(-(77,/zz/fake.pl),cp.pl))",
    raw"t_p09 t_p09([|](-(r,y),[|](-(r,y),[|](-(r,y),[|](-(s,n),[])))))",
    raw"t_p10 t_p10(:(user,/(cp_r,1)))",
    raw"t_p11 t_p11(user)",
    raw"t_p12 t_p12(-(n,y))",
    raw"t_p13 t_p13(-(12,:(user,/(cp_d,1))))",
    raw"t_p14 t_p14(-(-(n,n),n))",
    raw"t_p15 t_p15(-(-(:(user,/(cp_d,1)),user),y))",
    raw"t_p16 t_p16(-(:(cpm,/(cp_m,1)),cpm))",
    raw"t_p17 t_p17(-(:(user,/(cp_d,1)),y))",
    raw"t_p18 t_p18([|](line_count,[|](file,[|](source,[|](size,[|](fact,[|](predicate,[|](module,[]))))))))",
    raw"t_p19 t_p19(ok)",
    raw"t_p20 t_p20([|](size,[|](fact,[|](predicate,[|](module,[])))))",
    raw"t_p21 t_p21(n)",
    raw"t_p22 t_p22(raised(type_error(db_reference,foo)))",
    raw"t_p23 t_p23(raised(instantiation_error))",
    raw"t_p24 t_p24(n)",
    raw"t_p25 t_p25(y)",
    raw"t_z01 t_z01(last)"
]

function _cp_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_CP}()
    ld = LK.PL_local_data{_CP}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cp_enc(ball::_CP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_cps(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_CP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _cp_enc(mk_expr(_CP, _CP[_cps(name), lk_answers(ld, (a:a)...)...]))
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

@testset "clause_property/2 on a consulted file and on asserted clauses (LB6-CLAUSEPROP)" begin
    f, names = _cp_file()
    kl = _cp_kernel(f, names)
    @test length(kl) == length(_CP_CASES) + 1
    for (k, p) in zip(kl, _CP_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pin table is whole (a pin per case plus "ok"), and holds the answers each row kills a mutant with
    @test length(_CP_PINNED) == length(_CP_CASES) + 1
    @test all(l -> startswith(l, "t_") || l == "ok", _CP_PINNED)
    @test !any(l -> occursin("undefined", l) || occursin("exception", l), kl)
    # line_count is the line the term STARTS at (p01 the two-line clause at 3, p02 the three-line cp_s at 7), counted in the INCLUDED file for its clauses (p06)
    @test raw"t_p01 t_p01([|](1,[|](3,[|](5,[]))))" in _CP_PINNED
    @test raw"t_p02 t_p02(7)" in _CP_PINNED
    @test raw"t_p06 t_p06([|](-(2,cpinc.pl),[|](-(3,cpinc.pl),[])))" in _CP_PINNED
    # file and source (owner) differ for an include (p06 file cpinc.pl, p07 owner cp.pl) and for a '$source_location' expansion (p08: file /zz/fake.pl, owner cp.pl)
    @test raw"t_p07 t_p07([|](cp.pl,[|](cp.pl,[])))" in _CP_PINNED
    @test raw"t_p08 t_p08(-(-(77,/zz/fake.pl),cp.pl))" in _CP_PINNED
    # an asserted clause has no file, no line and no owner (p14, p20: the enumeration has no line_count, file or source), a consulted one all of them (p18)
    @test raw"t_p14 t_p14(-(-(n,n),n))" in _CP_PINNED
    @test raw"t_p18 t_p18([|](line_count,[|](file,[|](source,[|](size,[|](fact,[|](predicate,[|](module,[]))))))))" in
        _CP_PINNED
    @test raw"t_p20 t_p20([|](size,[|](fact,[|](predicate,[|](module,[])))))" in _CP_PINNED
    # fact: the unit clauses y, the rule cp_s n (p09); erased n then y (p12), an erased reference still answers its line and predicate (p13)
    @test raw"t_p09 t_p09([|](-(r,y),[|](-(r,y),[|](-(r,y),[|](-(s,n),[])))))" in _CP_PINNED
    @test raw"t_p12 t_p12(-(n,y))" in _CP_PINNED
    @test raw"t_p13 t_p13(-(12,:(user,/(cp_d,1))))" in _CP_PINNED
    # the errors of '$get_clause_attribute'/3 reach clause_property/2 (p22 type, p23 instantiation), an unknown property fails (p21)
    @test raw"t_p22 t_p22(raised(type_error(db_reference,foo)))" in _CP_PINNED
    @test raw"t_p23 t_p23(raised(instantiation_error))" in _CP_PINNED
    @test raw"t_p21 t_p21(n)" in _CP_PINNED
    # the module and predicate of a clause asserted into another module (p16)
    @test raw"t_p16 t_p16(-(:(cpm,/(cp_m,1)),cpm))" in _CP_PINNED
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_CP_PINNED) == length(_CP_CASES) + 1
    if swipl === nothing
        @info "CLAUSE_PROPERTY LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _cp_file()
        @test _cp_swipl_lines(f, names) == _CP_PINNED
    end
end
