# ORIGINAL: the UPSTREAM tests/tabling/test_trie_attvars.pl (swipl-devel 18168e62, 10.1.20), unit trie_attvars (30 tests: simple, simple_compiled, plain, plain_compiled, nesting, nesting_compiled, nesting2, nesting2_compiled, shared, shared_compiled, unify_true, unify_true_compiled, unify_fail_1, unify_fail_1_compiled, unify_fail_2, unify_fail_2_compiled, unify_shared, unify_shared_compiled, unify_shared, unify_shared_compiled, unify_shared, unify_shared_compiled, unify_multi, unify_multi_compiled, unify_beside_constants, unify_beside_constants_compiled, unify_beside_constants_fail, unify_beside_constants_fail_compiled, unify_beside_variable, unify_beside_variable_compiled),
# as kernel rows (TAB1, TABTEST-TR). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <module>:test(<name>...), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus every line outside the unit (the parent module) and the libraries the file loads (all but plunit).
#     No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_av.txt, which also holds the plunit
#     run of the unit) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`). Nothing fails or hangs on the pin.
#   * DIVERGES from the file: plunit is not used (`<unit module>:test(Name...)` is called directly). The file's parent module is `test_trie_attvars`: every
#     line outside the unit, upstream's text (the module header, the libraries, the helper predicates and upstream's term_expansion of
#     the file), in a file of its own, loaded first; the unit is its own module file `plunit_<unit>` (the name plunit gives it) with
#     `:- set_module(base(test_trie_attvars))`, the default import module plunit gives a unit. Tests with plunit options are test/2 clauses whose head
#     is the option: the row calls the test with the option unbound and checks it AFTER the call (`Var == Value` / `Var =@= Value`;
#     `fail`: the call fails; `error(F)`: the call raises error(F, _); `set(Var == List)`: findall + sort/2 + `==`; `nondet`, `sto(..)`
#     and `true`: the call succeeds). A test whose name occurs twice is called through `nth_clause/3` + `clause/3` (the n-th test clause),
#     as plunit runs each clause as its own test. The unit option `condition(..)` is not evaluated (it holds on the pin).
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
    ("trie_attvars", ":- begin_tests(trie_attvars, [condition(has_trie_attvar_support)]).", raw"""

test(simple, V == v) :-
    create_trie(T, [ f(_{a:v}) ]),
    trie_gen(T, f(Y)),
    get_attr(Y, a, V).
test(plain, V == v) :-
    create_trie(T, [ _{a:v} ]),
    trie_gen(T, Y),
    get_attr(Y, a, V).
test(nesting, V == v) :-
    create_trie(T, [ f(_{a:v}, a) ]),
    trie_gen(T, f(Y, Z)),
    assertion(Z == a),
    get_attr(Y, a, V).
test(nesting2, V == v) :-
    create_trie(T, [ f(X{a:v}, g(X,a)) ]),
    trie_gen(T, f(Y, Z)),
    assertion(Z == g(Y,a)),
    get_attr(Y, a, V).
test(shared, V == v) :-
    create_trie(T, [ f(X{a:v}, X) ]),
    trie_gen(T, f(Y, Z)),
    assertion(Y == Z),
    get_attr(Y, a, V).
test(unify_true, true) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}) ]),
    trie_gen(T, f(2)).
test(unify_fail_1, fail) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}) ]),
    trie_gen(T, f(1)).
test(unify_fail_2, fail) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}) ]),
    trie_gen(T, f(Y)),
    Y = 1.
test(unify_shared, Y == 2) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}, X) ]),
    trie_gen(T, f(2, Y)).
test(unify_shared, Y == 2) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}, X) ]),
    trie_gen(T, f(Y, 2)).
test(unify_shared, Z == z) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}, X) ]),
    freeze(B, Z=z),
    trie_gen(T, f(2, B)),
    assertion(B == 2).
test(unify_multi, true) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))},
                       Y{call:freeze(Y, odd(Y))})
                   ]),
    trie_gen(T, f(2, 1)).
% A stored attributed variable beside constants in a hashed node is
% found for a bound key.
test(unify_beside_constants, nondet) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}), f(b), f(c) ]),
    trie_gen(T, f(2)).
test(unify_beside_constants_fail, fail) :-
    create_trie(T, [ f(X{call:freeze(X, even(X))}), f(b), f(c) ]),
    trie_gen(T, f(1)).
test(unify_beside_variable, N == 2) :-
    create_trie(T, [ f(_), f(X{call:freeze(X, even(X))}), f(b) ]),
    aggregate_all(count, trie_gen(T, f(2)), N).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- module(test_trie_attvars,
          [ test_trie_attvars/0,
            create_trie/2
          ]).
:- use_module(library(apply)).
:- use_module(library(dicts)).
:- use_module(library(terms)).
:- use_module(library(debug)).

test_trie_attvars :-
    run_tests([ trie_attvars
              ]).

has_trie_attvar_support :-
    trie_new(T),
    put_attr(X, x, t),
    catch(trie_insert(T, f(X)),
          error(type_error(free_of_attvar, _),_),
          fail).

% Execute all tests with trie_gen/2 and trie_gen_compiled/2.
term_expansion((test(Id,Attrs) :- Body),
               [ (test(Id,Attrs) :- Body),
                 (test(CId,Attrs) :- CBody)
               ]) :-
    mapsubterms(map_to_compiled, Body, CBody),
    CBody \== Body,
    atom_concat(Id, '_compiled', CId).

map_to_compiled(trie_gen(Trie, To),
                trie_gen_compiled(Trie, To)).




create_trie(Trie, Values) :-
    trie_new(Trie),
    maplist(insert_value(Trie), Values).

insert_value(Trie, Value0) :-
    mapsubterms(to_attvar, Value0, Value),
    trie_insert(Trie, Value).

to_attvar(Dict, Var) :-
    is_dict(Dict, Var),
    var(Var),
    !,
    mapdict(add_attr(Var), Dict).

add_attr(_Var, call, Goal) =>
    call(Goal).
add_attr(Var, Key, Value) =>
    put_attr(Var, Key, Value).

even(X) :-
    X mod 2 =:= 0.

odd(X) :-
    X mod 2 =:= 1.
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01n01", "trie_attvars", "(plunit_trie_attvars:test(simple, O), O = (A == B), A == B)"),
    ("tt01n02", "trie_attvars", "(plunit_trie_attvars:test(simple_compiled, O), O = (A == B), A == B)"),
    ("tt01n03", "trie_attvars", "(plunit_trie_attvars:test(plain, O), O = (A == B), A == B)"),
    ("tt01n04", "trie_attvars", "(plunit_trie_attvars:test(plain_compiled, O), O = (A == B), A == B)"),
    ("tt01n05", "trie_attvars", "(plunit_trie_attvars:test(nesting, O), O = (A == B), A == B)"),
    ("tt01n06", "trie_attvars", "(plunit_trie_attvars:test(nesting_compiled, O), O = (A == B), A == B)"),
    ("tt01n07", "trie_attvars", "(plunit_trie_attvars:test(nesting2, O), O = (A == B), A == B)"),
    ("tt01n08", "trie_attvars", "(plunit_trie_attvars:test(nesting2_compiled, O), O = (A == B), A == B)"),
    ("tt01n09", "trie_attvars", "(plunit_trie_attvars:test(shared, O), O = (A == B), A == B)"),
    ("tt01n10", "trie_attvars", "(plunit_trie_attvars:test(shared_compiled, O), O = (A == B), A == B)"),
    ("tt01n11", "trie_attvars", "plunit_trie_attvars:test(unify_true, _)"),
    ("tt01n12", "trie_attvars", "plunit_trie_attvars:test(unify_true_compiled, _)"),
    ("tt01n13", "trie_attvars", "\+ plunit_trie_attvars:test(unify_fail_1, _)"),
    ("tt01n14", "trie_attvars", "\+ plunit_trie_attvars:test(unify_fail_1_compiled, _)"),
    ("tt01n15", "trie_attvars", "\+ plunit_trie_attvars:test(unify_fail_2, _)"),
    ("tt01n16", "trie_attvars", "\+ plunit_trie_attvars:test(unify_fail_2_compiled, _)"),
    ("tt01n17", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 17, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n18", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 18, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n19", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 19, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n20", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 20, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n21", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 21, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n22", "trie_attvars", "((nth_clause(plunit_trie_attvars:test(_, _), 22, Rf), clause(plunit_trie_attvars:test(_, O), Bd, Rf), plunit_trie_attvars:Bd), O = (A == B), A == B)"),
    ("tt01n23", "trie_attvars", "plunit_trie_attvars:test(unify_multi, _)"),
    ("tt01n24", "trie_attvars", "plunit_trie_attvars:test(unify_multi_compiled, _)"),
    ("tt01n25", "trie_attvars", "plunit_trie_attvars:test(unify_beside_constants, _)"),
    ("tt01n26", "trie_attvars", "plunit_trie_attvars:test(unify_beside_constants_compiled, _)"),
    ("tt01n27", "trie_attvars", "\+ plunit_trie_attvars:test(unify_beside_constants_fail, _)"),
    ("tt01n28", "trie_attvars", "\+ plunit_trie_attvars:test(unify_beside_constants_fail_compiled, _)"),
    ("tt01n29", "trie_attvars", "(plunit_trie_attvars:test(unify_beside_variable, O), O = (A == B), A == B)"),
    ("tt01n30", "trie_attvars", "(plunit_trie_attvars:test(unify_beside_variable_compiled, O), O = (A == B), A == B)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01n01 c[116,95,116,116,48,49,110,48,49]/1(a[111,107])",
    "t_tt01n02 c[116,95,116,116,48,49,110,48,50]/1(a[111,107])",
    "t_tt01n03 c[116,95,116,116,48,49,110,48,51]/1(a[111,107])",
    "t_tt01n04 c[116,95,116,116,48,49,110,48,52]/1(a[111,107])",
    "t_tt01n05 c[116,95,116,116,48,49,110,48,53]/1(a[111,107])",
    "t_tt01n06 c[116,95,116,116,48,49,110,48,54]/1(a[111,107])",
    "t_tt01n07 c[116,95,116,116,48,49,110,48,55]/1(a[111,107])",
    "t_tt01n08 c[116,95,116,116,48,49,110,48,56]/1(a[111,107])",
    "t_tt01n09 c[116,95,116,116,48,49,110,48,57]/1(a[111,107])",
    "t_tt01n10 c[116,95,116,116,48,49,110,49,48]/1(a[111,107])",
    "t_tt01n11 c[116,95,116,116,48,49,110,49,49]/1(a[111,107])",
    "t_tt01n12 c[116,95,116,116,48,49,110,49,50]/1(a[111,107])",
    "t_tt01n13 c[116,95,116,116,48,49,110,49,51]/1(a[111,107])",
    "t_tt01n14 c[116,95,116,116,48,49,110,49,52]/1(a[111,107])",
    "t_tt01n15 c[116,95,116,116,48,49,110,49,53]/1(a[111,107])",
    "t_tt01n16 c[116,95,116,116,48,49,110,49,54]/1(a[111,107])",
    "t_tt01n17 c[116,95,116,116,48,49,110,49,55]/1(a[111,107])",
    "t_tt01n18 c[116,95,116,116,48,49,110,49,56]/1(a[111,107])",
    "t_tt01n19 c[116,95,116,116,48,49,110,49,57]/1(a[111,107])",
    "t_tt01n20 c[116,95,116,116,48,49,110,50,48]/1(a[111,107])",
    "t_tt01n21 c[116,95,116,116,48,49,110,50,49]/1(a[111,107])",
    "t_tt01n22 c[116,95,116,116,48,49,110,50,50]/1(a[111,107])",
    "t_tt01n23 c[116,95,116,116,48,49,110,50,51]/1(a[111,107])",
    "t_tt01n24 c[116,95,116,116,48,49,110,50,52]/1(a[111,107])",
    "t_tt01n25 c[116,95,116,116,48,49,110,50,53]/1(a[111,107])",
    "t_tt01n26 c[116,95,116,116,48,49,110,50,54]/1(a[111,107])",
    "t_tt01n27 c[116,95,116,116,48,49,110,50,55]/1(a[111,107])",
    "t_tt01n28 c[116,95,116,116,48,49,110,50,56]/1(a[111,107])",
    "t_tt01n29 c[116,95,116,116,48,49,110,50,57]/1(a[111,107])",
    "t_tt01n30 c[116,95,116,116,48,49,110,51,48]/1(a[111,107])",
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
    write(joinpath(d, "test_trie_attvars.pl"), _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_trie_attvars)).\n" * text
        )
    end
    main = ":- use_module('$d/test_trie_attvars').\n" * join([":- use_module('$d/plunit_$short').\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_trie_attvars.pl units 1..1: the kernel answers every row as swipl does" begin
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
