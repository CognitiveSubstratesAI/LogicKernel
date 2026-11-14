# ORIGINAL: the UPSTREAM tests/tabling/test_answer_insert.pl (swipl-devel 18168e62, 10.1.20), unit answer_insert (11 tests: ground, ground_lookup, shared, shared_lookup, unbound, indirect, indirect_lookup, mixed, mixed_lookup, zero, wide),
# as kernel rows (TAB1, TABTEST-AI). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <module>:test(<name>...), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus the file's shared code outside the unit (the meta_predicate block, all/3, in_table/2 and the `:- table` declarations with their clauses) and the libraries the file loads (all but plunit).
#     No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_ai.txt, which also holds the plunit
#     run of the unit) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`). Nothing fails or hangs on the pin.
#   * DIVERGES from the file: plunit is not used (`<module>:test(Name...)` is called directly); the unit and the file's shared code are ONE module
#     `test_answer_insert` (the tests name `test_answer_insert:` explicitly; plunit has two modules there, the parent and `plunit_answer_insert`).
#     Tests with plunit options are test/2 clauses whose head binds the option term: the row calls the test with Options unbound and checks the
#     option AFTER the call (`Var == Value` / `Var =@= Value`) as the other upstream-test files do.
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tts(x) = lk_sym(_TT, Symbol(x))

_tt_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tt_enc(t::_TT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tt_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tt_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tt_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TT_DRIVER = raw"""
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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("answer_insert", ":- begin_tests(answer_insert).", raw"""

test(ground, L == [1,a,b,c]) :-
    abolish_all_tables,
    all(X, ground_dups(X), L).
test(ground_lookup) :-
    abolish_all_tables,
    forall(ground_dups(_), true),
    forall(member(X, [a,1,b,c]),
           assertion(in_table(test_answer_insert:ground_dups(_), ret(X)))).
test(shared, Len == 4) :-
    abolish_all_tables,
    findall(X-Y, shared(X, Y), L),
    length(L, Len),
    forall(member(E, [A-A, _-b, a-_, _-_]),
           assertion((member(E2, L), E2 =@= E))).
test(shared_lookup) :-
    abolish_all_tables,
    forall(shared(_,_), true),
    assertion(in_table(test_answer_insert:shared(_,_), ret(A,A))),
    assertion(in_table(test_answer_insert:shared(_,_), ret(a,_))),
    assertion(in_table(test_answer_insert:shared(_,_), ret(_,_))),
    assertion(\+ in_table(test_answer_insert:shared(_,_), ret(b,_))).
test(unbound, X-Y =@= _-_) :-          % bindings are undone
    abolish_all_tables,
    shared(X, Y), var(X), var(Y), X \== Y, !.
test(indirect, L == [1.5, 2.5, Big, "str"]) :-
    abolish_all_tables,
    Big is 2^100,
    all(X, indirect(X), L).
test(indirect_lookup) :-
    abolish_all_tables,
    forall(indirect(_), true),
    Big is 2^100,
    forall(member(X, [1.5, Big, "str"]),
           assertion(in_table(test_answer_insert:indirect(_), ret(X)))).
test(mixed, Len == 6) :-
    abolish_all_tables,
    findall(X, mixed(X), L),
    length(L, Len),
    forall(member(E, [_, 1, a, g(_), g(1), h(a,_)]),
           assertion((member(E2, L), E2 =@= E))).
test(mixed_lookup) :-
    abolish_all_tables,
    forall(mixed(_), true),
    forall(member(X, [1, g(1), _, g(_), h(a,_), a]),
           assertion(in_table(test_answer_insert:mixed(_), ret(X)))).
test(zero, L == [true]) :-
    abolish_all_tables,
    findall(true, zero, L).
test(wide, Len == 1) :-                 % 38 variables: generic path
    abolish_all_tables,
    length(Args, 40),
    G =.. [wide|Args],
    findall(G, G, L),
    length(L, Len),
    L = [W],
    arg(1, W, A1), arg(40, W, A40), arg(2, W, A2),
    assertion(A1 == A40),
    assertion(A2 == x).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- meta_predicate
    all(?, 0, -).

all(T, G, L) :- findall(T, G, L0), msort(L0, L).

%   in_table(:Variant, +Answer) is semidet.
%
%   True when Answer (a ret/N term) is in the answer table of Variant,
%   found using trie_lookup/3, i.e., through trie_lookup_abstract().

in_table(M:Variant, Answer) :-
    current_table(M:Variant, Trie),
    trie_lookup(Trie, Answer, _).

:- table
    ground_dups/1,
    shared/2,
    indirect/1,
    mixed/1,
    zero/0,
    wide/40.

ground_dups(X) :- member(X, [a,1,b,a,1,c,b]).

shared(X, Y) :- member(X-Y, [A-A, a-_, _-b, B-B, a-_, C-D, D-C]),
    ignore(A=A), ignore(B=B), ignore(C=C).

indirect(X) :-
    Big is 2^100,
    member(X, [1.5, Big, "str", 1.5, Big, "str", 2.5]).

mixed(X) :- member(X, [1, g(1), 1, _, g(_), g(1), h(a,_), a]).

zero :- member(_, [1,2,3]).

wide(A1,A2,A3,A4,A5,A6,A7,A8,A9,A10,A11,A12,A13,A14,A15,A16,A17,A18,A19,A20,
     A21,A22,A23,A24,A25,A26,A27,A28,A29,A30,A31,A32,A33,A34,A35,A36,A37,A38,
     A39,A40) :-
    member(_, [1,2]),
    A1 = A40, A2 = x,
    maplist(=(_), [A3,A4,A5,A6,A7,A8,A9,A10,A11,A12,A13,A14,A15,A16,A17,A18,
                   A19,A20,A21,A22,A23,A24,A25,A26,A27,A28,A29,A30,A31,A32,
                   A33,A34,A35,A36,A37,A38,A39]).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01a", "answer_insert", "(test_answer_insert:test(ground, O), O = (A == B), A == B)"),
    ("tt01b", "answer_insert", "test_answer_insert:test(ground_lookup)"),
    ("tt01c", "answer_insert", "(test_answer_insert:test(shared, O), O = (A == B), A == B)"),
    ("tt01d", "answer_insert", "test_answer_insert:test(shared_lookup)"),
    ("tt01e", "answer_insert", "(test_answer_insert:test(unbound, O), O = (A =@= B), A =@= B)"),
    ("tt01f", "answer_insert", "(test_answer_insert:test(indirect, O), O = (A == B), A == B)"),
    ("tt01g", "answer_insert", "test_answer_insert:test(indirect_lookup)"),
    ("tt01h", "answer_insert", "(test_answer_insert:test(mixed, O), O = (A == B), A == B)"),
    ("tt01i", "answer_insert", "test_answer_insert:test(mixed_lookup)"),
    ("tt01j", "answer_insert", "(test_answer_insert:test(zero, O), O = (A == B), A == B)"),
    ("tt01k", "answer_insert", "(test_answer_insert:test(wide, O), O = (A == B), A == B)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01a c[116,95,116,116,48,49,97]/1(a[111,107])",
    "t_tt01b c[116,95,116,116,48,49,98]/1(a[111,107])",
    "t_tt01c c[116,95,116,116,48,49,99]/1(a[111,107])",
    "t_tt01d c[116,95,116,116,48,49,100]/1(a[111,107])",
    "t_tt01e c[116,95,116,116,48,49,101]/1(a[111,107])",
    "t_tt01f c[116,95,116,116,48,49,102]/1(a[111,107])",
    "t_tt01g c[116,95,116,116,48,49,103]/1(a[111,107])",
    "t_tt01h c[116,95,116,116,48,49,104]/1(a[111,107])",
    "t_tt01i c[116,95,116,116,48,49,105]/1(a[111,107])",
    "t_tt01j c[116,95,116,116,48,49,106]/1(a[111,107])",
    "t_tt01k c[116,95,116,116,48,49,107]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_reeval.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(test_answer_insert, []).\n:- use_module(library(debug)).\n:- use_module(library(apply)).\n:- use_module(library(lists)).\n" * text * "\n" * _TT_TAIL
        )
    end
    main = join([":- use_module('$d/pu_$short').\n" for (short, _, _) in _TT_UNITS])
    main *= join([
        "t_$(id)(R) :- ( catch((abolish_all_tables, $g, abolish_all_tables, R = ok), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, _, g) in _TT_CASES
    ])
    write(joinpath(d, "main.pl"), main)
    return joinpath(d, "main.pl")
end

function _tt_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(f, _TT_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n")
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tt_load(main::String)
    gd = LK.PL_global_data{_TT}()
    ld = LK.PL_local_data{_TT}(gd)
    st, ball = LK.load_file!(gd, ld, main)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tt_enc(ball::_TT))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tt_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tts(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tt_enc(mk_expr(_TT, _TT[_tts(pred), lk_answers(ld, (a:a)...)...])))
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
    return pred * join(" " .* sols)
end

"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TT_UPSTREAM` holds it."
function _tt_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tt_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_answer_insert.pl units 1..1: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TT_PINNED)
    for (k, pn) in zip(kl, _TT_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "the pins are the upstream (plunit) expectations (no swipl needed)" begin
    @test length(_TT_PINNED) == length(_TT_CASES) + 1
    @test length(_TT_UPSTREAM) == length(_TT_CASES)
    @test !isempty(_TT_UPSTREAM) && all(!isempty, _TT_UPSTREAM)
    @test _TT_PINNED[1] == "ok"
    for (pn, up) in zip(_TT_PINNED[2:end], _TT_UPSTREAM)
        @test _tt_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _tt_answer(_tt_corrupt(_TT_PINNED[2])) != _TT_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        got = _tt_swipl_lines(_tt_materialize(), ["t_$id" for (id, _, _) in _TT_CASES])
        @test !isempty(got) && got == _TT_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tt_corrupt(_TT_PINNED[2])
    end
end
