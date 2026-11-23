# ORIGINAL: the UPSTREAM GC test programs of swipl-devel 18168e62 that no other kernel test file embeds, as kernel rows (inventory item 11, W11-G1G):
# allow-new-artifact: W11-G1G, the upstream GC test programs as rows, after test/core_lang/test_gc_frames.jl and test_gc_leak_reset_upstream_swipl.jl
# tests/core_lang/test_gc.pl units gc_mark (4 tests) and agc (1 test), tests/GC/test_gc_alt_clause.pl (1), tests/GC/test_gc_1.pl (its test1, test2 and the
# entry test_gc_1/0), tests/GC/test_clause_gc.pl (test_clause_gc/0) and tests/GC/test_agc_copyterm.pl (1): 11 rows. ALREADY ROWS elsewhere (not repeated here):
# test_ch_shift.pl and test_cleanup_shift.pl in test_gc_frames.jl; gc_leak and gc_reset of test_gc.pl in test_gc_leak_reset_upstream_swipl.jl.
# One row `t_<id>(R)` per test, R = ok / failed / raised(E); the unit text is upstream's, verbatim, each unit its own module `pu_<unit>` (plunit gives each
# unit one; `:- discontiguous test/1, test/2.` stands for plunit's term expansion); the licence blocks are not embedded (the D-0164 word scan of the embedded
# text: no hit).
#   * DIVERGES from the files: plunit is not used (`pu_<unit>:test(Name, O)` is called directly): the `true` option of gc_mark's tests is folded by hand
#     (`pu:test(N, O), O == true`), the `Var == Value` option of agc's usercall is `A == Ok` after the body, the `set(X == [1,2,3])` option of alt_rat is
#     `findall` + `sort` + `== [1,2,3]` and the unit's `condition(current_prolog_flag(bounded, false))` is the first goal of its row. The entry predicates of test_gc_1.pl
#     and test_clause_gc.pl are called as they are. The module of each file is `pu_<unit>` instead of its own name.
#   * BOUNDED (audit D-0747 item 3): every row runs inside `with_limit(16000000, Goal)` (the program's own helper: `stack_limit` set to 16 MB around the goal, restored
#     after), so a row that grows the stacks cannot take the machine; test_clause_gc/0 sets 2 000 000 itself inside that. Measured at swipl: every row finishes in
#     under 2 s and well inside the limit. No row needs `tools/warm.sh file ... --memmax`.
#   * HELD OUT (listed, not rowed; the reason is what the kernel lacks, not the test): tests/core_lang/test_agc_margin.pl (blob_type_property/set_blob_type, atom-GC margins),
#     tests/db/test_cgc.pl (units cgc: threads; erased: predicate_property erased_clauses/erased_clause_space), tests/GC/test_cgc_1.pl (threads), tests/GC/test_tracer_callback.pl
#     (the tracer hook prolog_trace_interception), tests/thread/{agc,agc2,agc3,queue_gc,test_agc_callback,test_agc_deadlock,test_gc_thread_startup,thread_agc,
#     thread_agc_findall,thread_agc_queue}.pl (threads), tests/xsb/** (the XSB table suites matched by the name filter, not GC programs); the two further
#     units of test_gc.pl (its upstream lines 141-218) stay held out as in test_gc_leak_reset_upstream_swipl.jl (the D-0164 term class).
#   * Pins: swipl 10.1.20 (the pinned build ~/.local/swipl-pin1-18168e62), two byte-identical runs of the driver below with LC_ALL=C (stdout AND stderr identical, stderr
#     empty). A row's pin is `ok` for every test: each passes at swipl.
#   * KNOWN DIFFERENCE (G1-FIX-5, `_GU_KNOWN_DIFF`): t_cg01 raises existence_error(procedure, pu_clause_gc:succ/2) (AR1 owns succ/2; swipl: ok).
#   * UNVERIFIED on the kernel (pinned from swipl twice; not run on the kernel): every kernel answer. The kernel may lack `stack_limit` handling, `garbage_collect_atoms/0`,
#     `atomics_to_string/3` or `statistics(globalused|trailused, _)`: a row then fails alone and the line says which.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE; these built-ins ride the term layer through the FLI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _GU_TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_gu_tts(x) = lk_sym(_GU_TT, Symbol(x))

_gu_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _gu_enc(t::_GU_TT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gu_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gu_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gu_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_gu_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _GU_DRIVER = raw"""
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

"The units: `(short name, export list, extra directives, unit text verbatim, the file's code after the unit)`."
const _GU_UNITS = [
    ("gc_mark", "[]", raw"""""", raw"""
test(s_list, true) :-			% S_NEXTCLAUSE must mark args of next
	length(_List, N),		% clause (broken in 5.7.0)
	garbage_collect,
	N == 4, !.
test(s_fredo, true) :-
	A = a(1,2,3,4,5,6),
	arg(_I, A, N),
	garbage_collect,
	N == 5, !.
test(c_ifthen, true) :-			% Scanning C_NOT should not end due
	A = {null},			% to the C_CUT of (a->b)
	garbage_collect,
	\+ (  true,
	      \+ ( ( true ->
		     true
		   ; otherwise ->
		     true
		   ),
		   A == {null}
		 )
	   ).
test(b_neq_vv, true) :-
	numlist(1, 100, X),
	numlist(1, 100, Y),
	garbage_collect,
	\+ (X \== Y),
	a(Y).

a(Y) :- length(Y,_).

""", raw""""""),
    ("agc", "[]", raw"""""", raw"""
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Verify marking atoms from temporary clauses  for meta-calling. Using the
enhanced garbage collector access through  the   variables  is no longer
guaranteed.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- dynamic
	v/1.

test :-
        atom_concat(abcd, efgh, A),
        Goal = ( garbage_collect,
                 garbage_collect_atoms,
                 make_atoms,
		 assert_atom(A)
               ),
	test_c(Goal).

test_c(Goal) :-
        Goal.

assert_atom(A) :-
	assert(v(A)).

make_atoms :-
        forall(between(1, 10000, X),
               atom_concat(foo, X, _)).

test(usercall, A == Ok) :-
	retractall(v(_)),
	test,
	retract(v(A)),
	atom_concat(abcd, efgh, Ok).

""", raw""""""),
    ("gc_alt_clause", "[]", raw"""""", raw"""
alt(_X) :- garbage_collect, fail.
alt(X)  :- rat(Rat), use(Rat), X = 1.
alt(X)  :- use("hello"),       X = 2.
alt(X)  :- use(42.0),          X = 3.

:- if(current_prolog_flag(bounded, false)).
rat(R) :-
    R is rdiv(1, 3).
:- else.
rat(0.33).
:- endif.


use(_).

test(alt_rat, set(X == [1,2,3])) :-
    alt(X).

""", raw""""""),
    (
        "gc_1",
        "[test_gc_1/0]",
        raw"""""",
        raw"""""",
        raw"""

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Test submitted by Keri Harris. This is a   bit hard to describe, but the
rough story is related to discardChoicesAfter()  and C_CUT. Both had the
discardFrame() done in a separate loop  not   to  confuse  GC due to the
reset LocalFrame->clause pointer.

This test shows that the Undo() in discardChoicesAfter() if an exception
is pending can destroy a choice-point and   most likely also other vital
structures. The current implementation fixes  the   issue  by moving the
discardFrame() into the primary loop, but set   BFR such that old frames
cannot be reached.

We keep this test as it is  a nice example of trick setup_call_cleanup/3
usage.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

test_gc_1 :-
	test1,
	test2.

loop(0) :- !.

loop(N) :-
       setup_call_catcher_cleanup(
           true,
           catch(setup_call_cleanup(true,
                                    ( between(1, 2, _), foo ),
                                    garbage_collect),
                 _,
                 true),
           Reason,
           Reason == exit),
       N2 is N - 1,
       loop(N2).

test1 :-
        loop(2), !.

test2 :-
        loop(2) -> true.



:-dynamic my_context/4.

foo :-
        retractall(my_context(foo, bar, baz, qux)),
        assert(my_context(foo, bar, baz, qux)),

        Sql = 'UPDATE sc_450 SET sc_450.record_status=? FROM se_counterparty sc_450 WHERE sc_450.cp_code = ?',

        setup_call_cleanup(true,
                           (
                             get_my_context(_, _, _, _),
                             between(1,2,_),
                             setup_call_cleanup(assert(Sql),
                                                true,
                                                retract(Sql))
                           ),
                           true),

        throw(error(application_error)).

get_my_context(TransactionId,
               TrxId,
               AccessToken,
               TransactionTimestamp) :-
        ( my_context(TransactionId_, TrxId_, AccessToken_, TransactionTimestamp_) ->
            TransactionId = TransactionId_,
            TrxId = TrxId_,
            AccessToken = AccessToken_,
            TransactionTimestamp = TransactionTimestamp_

        ; otherwise ->
            throw(no_context)
        ).
"""
    ),
    (
        "clause_gc",
        "[test_clause_gc/0, test_clause_gc/1]",
        raw"""""",
        raw"""""",
        raw"""

%!  test_clause_gc
%
%   This test runs a loop that builds a list and for each iteration runs
%   clause/2 on a term that contains all relevant programing constructs.
%   The idea is to trigger GC  and   shifts  at  different parts of this
%   process.

test_clause_gc :-
    setup_call_cleanup(( current_prolog_flag(stack_limit, SavedLimit),
                         set_prolog_flag(stack_limit, 2_000_000),
                         gspace(Cells),
                         MaxLen is max(10000, (Cells//4)//3)),
                       test_clause_gc(MaxLen),
                       set_prolog_flag(stack_limit, SavedLimit)).

test_clause_gc(N) :-
    catch(run(N, L), error(resource_error(stack), _), L=[]),
    is_list(L).			% avoid L from being GC'ed

run(N, L) :-
    functor(H, cl, 8),
    clause(H, B),
    run(N, H, B, L).

run(N, H, B, [x|L]) :-
    succ(N2, N), !,
    functor(H2, cl, 8),
    clause(H2, B2),
    H =@= H2,
    B =@= B2,
    run(N2, H, B, L).
run(_, _, _, []).

:- dynamic cl/8.			% make sure we can use clause/2

cl(a,
   A, A,
   1,
   1.2,
   1000000000000000000,
   100000000000000000000000000000000000000000000000000000,
   x(0,1,2,3,4,5,6,7)) :-
	a(a),
	a(B,B),
	a(1),
	a(1.2),
	a(1000000000000000000),
	a(100000000000000000000000000000000000000000000000000000),
	a(x(0,1,2,3,4,5,6,7)).

a(_).
a(_,_).

		 /*******************************
		 *	       UTIL		*
		 *******************************/

gspace(Cells) :-
    garbage_collect,
    current_prolog_flag(stack_limit, Limit),
    statistics(globalused, GUsed),
    statistics(localused, LUsed),
    statistics(trailused, TUsed),
    Used is GUsed+LUsed+TUsed,
    current_prolog_flag(address_bits, Wlen),
    Cells is (Limit-Used)//(Wlen//8).
"""
    ),
    ("agc_copyterm", "[]", raw""":- use_module(library(debug)).
""", raw"""
test(copy) :-
    go(3).

go(0) :-
    !.
go(N) :-
    functor(Result, a, 1000),
    (   between(1, 1000, I),
        functor(Term, t, 100),
        set_atoms(1, 100, I, Term),
        nb_setarg(I, Result, Term),
        fail
    ;   check_result(Result, 1, 1000)
    ),
    N2 is N - 1,
    go(N2).

set_atoms(From, To, I, Term) :-
    From =< To,
    !,
    atomic_list_concat([a,I,From], '_', Atom),
    arg(From, Term, Atom),
    F2 is From+1,
    set_atoms(F2, To, I, Term).
set_atoms(_, _, _, _).


check_result(Result, From, To) :-
    forall(between(From, To, I),
           (   arg(I, Result, T),
               check_term(T, 1, 100, I)
           )).

check_term(Result, From, To, C) :-
    between(From, To, I),
    arg(I, Result, Atom),
    atomics_to_string([a,C,From], '_', String),
    assertion(atom_string(Atom, String)).

""", raw"""""")
]

"One row per upstream test: `(id, goal)`; the goal runs inside `with_limit/2` of the main file."
const _GU_CASES = [
    ("gm01", raw"""pu_gc_mark:test(s_list, O), O == true"""),
    ("gm02", raw"""pu_gc_mark:test(s_fredo, O), O == true"""),
    ("gm03", raw"""pu_gc_mark:test(c_ifthen, O), O == true"""),
    ("gm04", raw"""pu_gc_mark:test(b_neq_vv, O), O == true"""),
    (
        "ga01",
        raw"""current_prolog_flag(bounded, false), findall(X, pu_gc_alt_clause:test(alt_rat, set(X == _)), L0), sort(L0, L), L == [1,2,3]"""
    ),
    ("g101", raw"""pu_gc_1:test1"""),
    ("g102", raw"""pu_gc_1:test2"""),
    ("g103", raw"""pu_gc_1:test_gc_1"""),
    ("cg01", raw"""pu_clause_gc:test_clause_gc"""),
    ("ac01", raw"""pu_agc_copyterm:test(copy)"""),
    ("ag01", raw"""pu_agc:test(usercall, A == Ok), A == Ok""")
]

const _GU_PINNED = [
    "ok",
    "t_gm01 c[116,95,103,109,48,49]/1(a[111,107])",
    "t_gm02 c[116,95,103,109,48,50]/1(a[111,107])",
    "t_gm03 c[116,95,103,109,48,51]/1(a[111,107])",
    "t_gm04 c[116,95,103,109,48,52]/1(a[111,107])",
    "t_ga01 c[116,95,103,97,48,49]/1(a[111,107])",
    "t_g101 c[116,95,103,49,48,49]/1(a[111,107])",
    "t_g102 c[116,95,103,49,48,50]/1(a[111,107])",
    "t_g103 c[116,95,103,49,48,51]/1(a[111,107])",
    "t_cg01 c[116,95,99,103,48,49]/1(a[111,107])",
    "t_ac01 c[116,95,97,99,48,49]/1(a[111,107])",
    "t_ag01 c[116,95,97,103,48,49]/1(a[111,107])"
]

"""
KNOWN DIFFERENCE (premise, owner AR1; G1-FIX-5): `t_cg01` (pu_clause_gc:test_clause_gc). The unit's `run/4` calls `succ/2` (upstream tests/GC/test_clause_gc.pl),
which the kernel does not define at this base (`succ/2` is AR1's: docs/r2_owners.tsv `pred:succ/2 AR1`, pl-arith.c `succ`). The call is resolved in the unit's
module (`pu_clause_gc`, importing from `user` then `system`), so the error names `pu_clause_gc:succ/2`: NOT a missing dynamic `cl/8` (functor/3 and clause/2 on it
run before the first `succ/2`; the program's `:- dynamic cl/8` is honoured). Kernel: `raised(existence_error(procedure, pu_clause_gc:succ/2))`; swipl: `ok`.
`test_clause_gc/1` only catches `resource_error(stack)`, so the error leaves the row.
CHECKLIST (AR1): when `succ/2` lands, delete this entry; the row must then answer `ok` (`=@=`, `clause/2` on `cl/8` and the 2 MB stack limit run after it: untested).
The swipl pins in `_GU_PINNED` stay swipl's (the live check compares them to swipl); only the kernel comparison reads this table.
"""
const _GU_KNOWN_DIFF = Dict{String, String}(
    "t_cg01" => "t_cg01 c[116,95,99,103,48,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[112,117,95,99,108,97,117,115,101,95,103,99],c[47]/2(a[115,117,99,99],i2)))))"
)

"The answer plunit expects of every row: the test passes, so `R = ok`."
const _GU_UPSTREAM = [
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
    "a[111,107]"
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _gu_materialize()::String
    d = realpath(mktempdir())
    for (short, exports, extra, text, tail) in _GU_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, $exports).\n:- discontiguous test/1, test/2.\n" * extra *
            text *
            "\n" * tail * "\n"
        )
    end
    main = join([":- use_module('$d/pu_$short').\n" for (short, _, _, _, _) in _GU_UNITS])
    main *=
        "with_limit(Limit, Goal) :-\n" *
        "    setup_call_cleanup(( current_prolog_flag(stack_limit, Old), set_prolog_flag(stack_limit, Limit) ),\n" *
        "                       once(Goal),\n" *
        "                       set_prolog_flag(stack_limit, Old)).\n"
    main *= join([
        "t_$(id)(R) :- ( catch((with_limit(16000000, ($g)), R = ok), error(E, _), R = raised(E)) -> true ; R = failed ).\n"
        for (id, g) in _GU_CASES
    ])
    write(joinpath(d, "main.pl"), main)
    return joinpath(d, "main.pl")
end

function _gu_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _GU_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _gu_load(main::String)
    gd = LK.PL_global_data{_GU_TT}()
    ld = LK.PL_local_data{_GU_TT}(gd)
    st, ball = LK.load_file!(gd, ld, main)
    return gd, ld, (st === :ok ? "ok" : "exc " * _gu_enc(ball::_GU_TT))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _gu_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_gu_tts(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_GU_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _gu_enc(
                    mk_expr(_GU_TT, _GU_TT[_gu_tts(pred), lk_answers(ld, (a:a)...)...])
                )
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
    return pred * join(" " .* sols)
end

"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_GU_UPSTREAM` holds it."
function _gu_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_gu_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]


@testset "upstream GC programs (gc_mark, agc, gc_alt_clause, gc_1, clause_gc, agc_copyterm): the kernel answers every row as swipl does" begin
    gd, ld, st = _gu_load(_gu_materialize())
    @test st == "ok"
    kl = String[]
    for (id, _) in _GU_CASES
        push!(kl, _gu_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_GU_PINNED) - 1 == length(_GU_CASES)
    for (k, pn) in zip(kl, _GU_PINNED[2:end])
        # a known difference is compared with the kernel's pinned current answer (see `_GU_KNOWN_DIFF`), every other row with swipl's pin
        want = get(_GU_KNOWN_DIFF, first(split(pn)), pn)
        k == want || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == want
    end
    # must-fail: a corrupted pin is not the kernel's line
    @test length(kl) > 1
    @test kl[1] != _gu_corrupt(_GU_PINNED[2])
end

@testset "the pins are the upstream (plunit) expectations (no swipl needed)" begin
    @test length(_GU_PINNED) == length(_GU_CASES) + 1
    @test length(_GU_UPSTREAM) == length(_GU_CASES) == 11
    @test !isempty(_GU_UPSTREAM) && all(!isempty, _GU_UPSTREAM)
    @test _GU_PINNED[1] == "ok"
    for (pn, up) in zip(_GU_PINNED[2:end], _GU_UPSTREAM)
        @test _gu_answer(pn) == up
    end
    # every upstream test of the six units has a row: counts of the unit texts
    @test length(_GU_UNITS) == 6
    @test count(c -> startswith(c[1], "gm"), _GU_CASES) == 4
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _gu_answer(_gu_corrupt(_GU_PINNED[2])) != _GU_UPSTREAM[1]
    # the known-difference table: every key is a pinned row, every entry differs from swipl's pin (else it is not a difference: delete it)
    for (key, line) in _GU_KNOWN_DIFF
        pins = filter(p -> first(split(p)) == key, _GU_PINNED)
        @test length(pins) == 1
        @test !isempty(pins) && line != only(pins)
        @test startswith(line, key * " ")
    end
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test !isempty(_GU_PINNED) && length(_GU_PINNED) == length(_GU_CASES) + 1
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        got = _gu_swipl_lines(_gu_materialize(), ["t_$id" for (id, _) in _GU_CASES])
        @test !isempty(got) && got == _GU_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _gu_corrupt(_GU_PINNED[2])
    end
end
