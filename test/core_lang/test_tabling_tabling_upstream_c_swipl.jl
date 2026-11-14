# ORIGINAL: the UPSTREAM tests/tabling/test_tabling.pl (swipl-devel 18168e62, 10.1.20), units 26..36 of 36 (tabling_yappath, tabling_minpath, tabling_maxpath, tabling_train, moded_tabling_path, mode_components1, mode_components2, pathss, bas, push_ret, no_closure),
# as kernel rows (TAB1, TABTEST-C). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <unit>:test(<name>), abolish_all_tables`
# (the unit's `cleanup(abolish_all_tables)` option and test_tabling/0's first call folded by hand), R = ok / failed / raised(E).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus the file's common tail (before/0, between/0,
#     feedback, end, has_trie_attvar_support); each unit is its own module `pu_<unit>` (plunit gives each unit a module) that uses the
#     pin's helper library test/core_lang/tabling_testlib_upstream.pl (tests/tabling/tabling_testlib.pl, verbatim) as `tabling_testlib`.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_c.txt, which also holds the plunit
#     run of the same units) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * DIVERGES from the file: plunit is not used (`pu_<unit>:test(Name)` is called directly), the unit modules are `pu_<unit>` not `plunit_<unit>`.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); expected refusals (by reading, unverified): bas (call_nth/2, digit groups (`1 000`), a DCG string literal); push_ret (digit groups (`2 000`)); no_closure ('$wrapped_implementation'/3, start_tabling(0, ..), '$tbl_variant_table'/6, test_tabling:nc).
#   * Rows with plunit options folded by hand (ROW_FOLD in gen_tabling.py, from the unit text): tabling_yappath, tabling_minpath, tabling_maxpath, tabling_train, moded_tabling_path, mode_components1, mode_components2, pathss, push_ret, no_closure: `Var op Val` options as once(Goal) then the check, `set(T == L)` as findall + sort + compare, `nondet` dropped; push_ret and no_closure call the unit's own test/2 clause (the option sits in its head) and then call the option.
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

"The pin's helper library, verbatim (tests/tabling/tabling_testlib.pl)."
const _TT_TESTLIB = joinpath(@__DIR__, "tabling_testlib_upstream.pl")

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("yappath", ":- begin_tests(tabling_yappath, [cleanup(abolish_all_tables)]).", raw"""

:- table
    path(index, index, first).

path(X, Y, N) :- path(X, Z, N1), edge(Z, Y), N is N1 + 1.
path(X, Y, 1) :- edge(X, Y).

edge(a, b).
edge(b, a).

min(A,B,C) :-
    writeln(A-B-C),
    C is min(A,B).

test(yappath, set(t(X,Y,L) == [t(a,a,2),t(a,b,1),t(b,a,1),t(b,b,2)])) :-
    path(X,Y,L).

"""),
    ("minpath", ":- begin_tests(tabling_minpath, [cleanup(abolish_all_tables)]).", raw"""
:- table connection(_,_,min).

connection(X, Y,1) :-
        connection(X, Y).
connection(X, Y,N) :-
        connection(X, Z,N1),
        connection(Z, Y),
        N is N1+1.

connection('Amsterdam', 'Schiphol').
connection('Amsterdam', 'Haarlem').
connection('Schiphol', 'Leiden').
connection('Haarlem', 'Leiden').
connection('Amsterdam', 'Leiden').

test(tabling_minpath, N =:= 1) :-
	connection('Amsterdam','Leiden',N).

"""),
    ("maxpath", ":- begin_tests(tabling_maxpath, [cleanup(abolish_all_tables)]).", raw"""
:- table connection(_,_,max).

connection(X, Y, 1) :-
        connection(X, Y).
connection(X, Y, N) :-
        connection(X, Z,N1),
        connection(Z, Y),
        N is N1+1.

connection('Amsterdam', 'Schiphol').
connection('Amsterdam', 'Haarlem').
connection('Schiphol', 'Leiden').
connection('Haarlem', 'Leiden').
connection('Amsterdam', 'Leiden').

test(tabling_maxpath, N =:= 2) :-
	connection('Amsterdam','Leiden',N).

"""),
    ("train", ":- begin_tests(tabling_train, [cleanup(abolish_all_tables)]).", raw"""
:- table train(_,_,lattice(shortest/3)).

train(X, Y, [X,Y]) :-
    train(X, Y).
train(X, Y, P) :-
    train(X, Z, P0),
    train(Z, Y),
    append(P0, [Y], P).

train('Amsterdam', 'Schiphol').
train('Amsterdam', 'Haarlem').
train('Schiphol',  'Leiden').
train('Haarlem',   'Leiden').
train('Amsterdam', 'Leiden').

shortest(P1, P2, P):-
    length(P1, L1),
    length(P2, L2),
    (   L1 < L2
    ->  P = P1
    ;   P = P2
    ).

test(tabling_train, P == ['Amsterdam','Leiden']) :-
	train('Amsterdam','Leiden', P).

"""),
    ("moded_path", ":- begin_tests(moded_tabling_path, [cleanup(abolish_all_tables)]).", raw"""
:- table
    path(_,_,lattice(or/3)),
    edge(_,_,lattice(or/3)).

path(X,X,one).
path(X,Y,C):-
    edge(X,Z,A),
    path(Z,Y,B),
    and(A,B,C).

path(A,B,zero) :-
    nonvar(A),
    nonvar(B).

edge(a,b,e(a,b)).
edge(b,e,e(b,e)).
edge(a,e,e(a,e)).

edge(A,B,zero):-
    nonvar(A),
    nonvar(B).

or(zero, B, B) :- !.
or(B, zero, B) :- !.
or(one, one, one) :- !.
or(A,A,A):-!.
or(A, B, or(A,B)).

and(zero, _, _) :- !, fail.
and(_, zero, _) :- !, fail.
and(one, B, B) :- !.
and(B, one, B) :- !.
and(A,A,A):-!.
and(A, B, and(A,B)).

test(path, nondet) :-
	path(a, e, T),
	assertion(ground(T)),
	assertion(ok_path(T)).

ok_path(or(e(a, e), and(e(a, b), e(b, e)))).
ok_path(or(and(e(a, b), e(b, e)), e(a, e))).

"""),
    ("mode_components1", ":- begin_tests(mode_components1, [cleanup(abolish_all_tables)]).", raw"""

:- table
    p2(lattice(orp/3)),
    s2(lattice(ors/3)).

orp(A,B,A+B).
ors(A,B,A-B).

p2(A) :-
    s2(A).

s2(1).
s2(2).

test(component, [A == (1-2), nondet]) :-
	p2(A).

"""),
    ("mode_components2", ":- begin_tests(mode_components2, [cleanup(abolish_all_tables)]).", raw"""

:- table
    advisedby(_,_,lattice(or/3)),
    r11(_,_,_,lattice(or/3)).

or(A,B,C):-C is A+B.

advisedby(A,B,1)  :-
    student(A), professor(B), project(C, A), project(C, B),
    r11(A, B, C,_).

r11(A, B, C,1) :-
    publication(D, A, C), publication(D, B, C).

student(harry).

professor(ben).

project(pr1, harry).
project(pr1, ben).
project(pr2, harry ).
project(pr2, ben).

publication(p1, harry, pr1).
publication(p1, ben, pr1).
publication(p2, harry, pr1).
publication(p2, ben, pr1).
publication(p3, harry, pr2).
publication(p3, ben, pr2).
publication(p4, harry, pr2).
publication(p4, ben, pr2).

test(component, [X == 2, nondet]) :-
    abolish_all_tables,
    advisedby(harry,ben,X).

"""),
    ("pathss", ":- begin_tests(pathss, [cleanup(abolish_all_tables)]).", raw"""
:- use_module(library(lists)).
:- use_module(library(apply)).

% Part of a bug report by Fabrizio Riguzzi.

:- table buys(_,lattice(merge/3)).

trusts(X,Y) :- trusts_directed(X,Y).
trusts(X,Y) :- trusts_directed(Y,X).

trusts_directed(bernd,ingo).
trusts_directed(bernd,martijn).
trusts_directed(ingo,martijn).
trusts_directed(kurt,bernd).

buys(X,[[X]]).
buys(X,Paths):-
    trusts(X,Y),
    buys(Y,Paths0),
    maplist(add_node(X),Paths0,Paths).

add_node(X,Path,[X|Path]):-
    \+ member(X,Path),!.
add_node(_,Path,Path).

merge(Paths0,Paths1,Paths):-
  foldl(add,Paths1,Paths0,Paths).

add(Path,Paths0,Paths):-
  (   member(Path0,Paths0),
      permutation(Path0,Path)
  ->  Paths = Paths0
  ;   Paths = [Path|Paths0]
  ).

test(kurt, P3 = [ [bernd, ingo, kurt],
                  [bernd, ingo, kurt, martijn],
                  [bernd, kurt], [bernd, kurt, martijn],
                  [kurt]
                ]) :-
    buys(kurt, P),
    maplist(msort, P, P2),
    sort(P2, P3).

"""),
    ("bas", ":- begin_tests(bas, [cleanup(abolish_all_tables)]).", raw"""

:- table bas/2.
bas --> "b".
bas --> bas, "a".

% tests resizing the global stack when generating answers from the
% tries.

test(bas) :-
    call_nth(( length(As,1 000),
               maplist(=(0'a),As),
               bas([0'b|As],A),
               is_list(A)
             ), 10).

"""),
    ("push_ret", ":- begin_tests(push_ret, [cleanup(abolish_all_tables)]).", raw"""

:- table posInt_CollatzSteps/2.
posInt_CollatzSteps(I,N) :-
   (  I == 1
   -> N = 0                                                % base case
   ;  1 is I /\ 1
   -> I0 is I*3+1, posInt_CollatzSteps(I0,N0), N is N0+1   % odd
   ;  I0 is I>>1,  posInt_CollatzSteps(I0,N0), N is N0+1   % even
   ).

i0_i_maxSteps0_maxSteps(I0,I,M0,M) :-
   (  I0 > I
   -> M0 = M
   ;  posInt_CollatzSteps(I0,N0),
      I1 is I0+1,
      M1 is max(M0,N0),
      i0_i_maxSteps0_maxSteps(I1,I,M1,M)
   ).

test(push_ret, MaxSteps1 == MaxSteps2) :-
    i0_i_maxSteps0_maxSteps(1,2 000,0,MaxSteps1),
    i0_i_maxSteps0_maxSteps(1,2 000,0,MaxSteps2).

"""),
    ("no_closure", ":- begin_tests(no_closure, [cleanup(abolish_all_tables)]).", raw"""

:- table nc/1.
nc(1).
nc(2).

nc_all(L) :-
    '$wrapped_implementation'(nc(X), table, Worker),
    findall(X, '$tabling':start_tabling(0, test_tabling:nc(X), Worker), L0),
    msort(L0, L).

test(start_tabling, L1-L2 == [1,2]-[1,2]) :-
    abolish_all_tables,
    nc_all(L1),                         % fresh
    nc_all(L2).                         % complete
test(variant_table, Status == complete) :-
    nc_all(_),
    '$tbl_variant_table'(0, test_tabling:nc(_), _Trie, Status, _Skel, _Mono).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
before    :- debug(tabling, 'before',  []).
before(I) :- debug(tabling, 'before ~w',  [I]).
between   :- debug(tabling, 'between', []).
feedback(Fmt) :- debug(tabling, Fmt, []).
feedback(Fmt,Args) :- debug(tabling, Fmt, Args).
end       :- debug(tabling, 'end',   []).
end(I)    :- debug(tabling, 'end ~w',   [I]).

has_trie_attvar_support :-
    trie_new(T),
    put_attr(X, x, t),
    catch(trie_insert(T, f(X)),
          error(type_error(free_of_attvar, _),_),
          fail).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt26", "yappath", "findall(t(X, Y, L), pu_yappath:path(X, Y, L), Bag), sort(Bag, S), S == [t(a,a,2), t(a,b,1), t(b,a,1), t(b,b,2)]"),
    ("tt27", "minpath", "once(pu_minpath:connection('Amsterdam', 'Leiden', N)), N =:= 1"),
    ("tt28", "maxpath", "once(pu_maxpath:connection('Amsterdam', 'Leiden', N)), N =:= 2"),
    ("tt29", "train", "once(pu_train:train('Amsterdam', 'Leiden', P)), P == ['Amsterdam', 'Leiden']"),
    ("tt30", "moded_path", "once(pu_moded_path:path(a, e, T)), ground(T), pu_moded_path:ok_path(T)"),
    ("tt31", "mode_components1", "once(pu_mode_components1:p2(A)), A == (1-2)"),
    ("tt32", "mode_components2", "abolish_all_tables, once(pu_mode_components2:advisedby(harry, ben, X)), X == 2"),
    ("tt33", "pathss", "once((pu_pathss:buys(kurt, P), maplist(msort, P, P2), sort(P2, P3))), P3 = [[bernd,ingo,kurt], [bernd,ingo,kurt,martijn], [bernd,kurt], [bernd,kurt,martijn], [kurt]]"),
    ("tt34", "bas", "pu_bas:test(bas)"),
    ("tt35", "push_ret", "pu_push_ret:test(push_ret, Opt), call(Opt)"),
    ("tt36a", "no_closure", "pu_no_closure:test(start_tabling, Opt), call(Opt)"),
    ("tt36b", "no_closure", "pu_no_closure:test(variant_table, Opt), call(Opt)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt26 c[116,95,116,116,50,54]/1(a[111,107])",
    "t_tt27 c[116,95,116,116,50,55]/1(a[111,107])",
    "t_tt28 c[116,95,116,116,50,56]/1(a[111,107])",
    "t_tt29 c[116,95,116,116,50,57]/1(a[111,107])",
    "t_tt30 c[116,95,116,116,51,48]/1(a[111,107])",
    "t_tt31 c[116,95,116,116,51,49]/1(a[111,107])",
    "t_tt32 c[116,95,116,116,51,50]/1(a[111,107])",
    "t_tt33 c[116,95,116,116,51,51]/1(a[111,107])",
    "t_tt34 c[116,95,116,116,51,52]/1(a[111,107])",
    "t_tt35 c[116,95,116,116,51,53]/1(a[111,107])",
    "t_tt36a c[116,95,116,116,51,54,97]/1(a[111,107])",
    "t_tt36b c[116,95,116,116,51,54,98]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_tabling.py pin, plunit part of pins file)."
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
    "a[111,107]",
]

"The files of the program in a fresh directory: testlib, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    cp(_TT_TESTLIB, joinpath(d, "tabling_testlib.pl"))
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n:- use_module('$d/tabling_testlib').\n" * text * "\n" * _TT_TAIL
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

@testset "upstream test_tabling.pl units 26..36: the kernel answers every row as swipl does" begin
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
