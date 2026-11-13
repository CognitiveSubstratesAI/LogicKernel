# ORIGINAL: kernel rows of the RESTRAINT code of pl-tabling.c that no upstream test file reaches (TAB1 TB8; swipl-devel 18168e62, 10.1.20): the
# tripwire at the limit of `max_incomplete_subgoals` (`tripwire_incomplete_subgoals`: `incomplete_tables == limit`), at the limit of
# `max_scc_subgoals` (`tripwire_scc_subgoals`: `size0 <= limit`), the retry of `get_answer_table` after a passed tripwire (`goto retry`), the answer
# count restraint of `tbl_add_answer` (`bounded_rationality`: `generalise_answer_substitution` + `add_answer_count_restraint`; a passed tripwire:
# `add_anyway`), the answer size restraint (`bounded_rationality`: `add_radial_restraint`; `fail`; `error`) and the answer flag of an incremental
# re-evaluation (`TN_IDG_ADDED`, `idg.new_answer`), and `'$tbl_sdg'/3` inside an evaluation with a COMPLETED child (`sdg_collect`). tests/tabling/test_tabling.pl and the other upstream files set these flags only with the
# action `error` below the limit or not at all, so these rows are ours: twelve programs `t_wb01..t_wb12`, each answer PINNED by running the exact
# program on swipl 10.1.20 (two byte-identical runs; evidence/TAB1/w1_verify.md, section W1d).
#   * The `prolog:tripwire/2` hook (boot/tabling.pl `tripwire/3`: `prolog:tripwire(Wire, Context)` succeeding makes the tripwire pass) lets an
#     evaluation go on past a limit without `print_message`: a row with `hooked/1` reads the wires that tripped.
#   * White-box: `generalise_answer_substitution` is a static function of pl-tabling.c that swipl cannot be asked: its atom branch (only `ret`
#     is an answer substitution; any other atom is `type_error(answer_substitution, A)`) is read at the source and pinned by hand below.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tws(x) = lk_sym(_TW, Symbol(x))

_tw_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tw_enc(t::_TW, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tw_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tw_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tw_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tw_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TW_DRIVER = raw"""
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

function _tw_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TW_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TW_PROGRAM = raw"""
:- use_module(library(lists)).
:- use_module(library(yall)).
:- use_module(library(wfs)).
:- dynamic tw/2, hook_on/0.
prolog:tripwire(W, C) :- hook_on, assertz(tw(W, C)).
:- table ch/1, lp/1, sh/1, cnt/1, big/1.
ch(N) :- N < 10, N1 is N+1, ch(N1).
ch(10).
lp(N) :- N < 10, N1 is N+1, lp(N1).
lp(_) :- lp(0).
sh(f(f(f(a)))).
sh(f(f(f(b)))).
cnt(X) :- between(1, 5, X).
big(f(a,b,c)).
big(a).
big(g(h(i))).
:- dynamic([dd/1], [incremental(true)]).
:- table ii/1 as incremental, jj/1 as incremental.
dd(1).
ii(X) :- dd(X).
jj(X) :- ii(X).
:- dynamic snapshot/1.
take :- '$tbl_sdg'(Components, Tables, Edges), assertz(snapshot(sdg(Components, Tables, Edges))).
:- table pa/0, pb/0.
pa :- pb, take.
pb.
sdg(Goal, Components, Tables, Edges) :-
    retractall(snapshot(_)), abolish_all_tables, ignore(Goal),
    snapshot(sdg(Cs, Ts, Es)), !, retractall(snapshot(_)),
    maplist(table_variant, Ts, Map),
    maplist(component(Cs, Map), Cs, Components0),
    maplist(table(Cs), Ts, Tables0),
    maplist(edge(Map), Es, Edges0),
    msort(Components0, Components), msort(Tables0, Tables), msort(Edges0, Edges).
table_variant(table(Trie, Variant, _, _, _), Trie-V) :- strip(Variant, V).
strip(_:G0, G) :- !, copy_term(G0, G), numbervars(G, 0, _).
strip(G, G).
component(Cs, Map, scc(SCC, _, Leader), Depth-L) :- depth(Cs, SCC, Depth), memberchk(Leader-L, Map).
depth(Cs, SCC, Depth) :- memberchk(scc(SCC, Parent, _), Cs),
    (   Parent == null -> Depth = 0 ; depth(Cs, Parent, Depth0), Depth is Depth0+1 ).
table(Cs, table(_, Variant, SCC, Answers, Flags0), table(V, Depth, Answers, Flags)) :-
    strip(Variant, V), depth(Cs, SCC, Depth), msort(Flags0, Flags).
edge(Map, edge(From, To, Sign, Count), edge(F, T, Sign, Count)) :- memberchk(From-F, Map), memberchk(To-T, Map).
with_limit(Flag, Limit, Action, Goal) :-
    atom_concat(Flag, '_action', ActionFlag),
    setup_call_cleanup(( set_prolog_flag(Flag, Limit), set_prolog_flag(ActionFlag, Action) ),
                       Goal,
                       ( set_prolog_flag(Flag, infinite), set_prolog_flag(ActionFlag, error) )).
hooked(Goal) :- setup_call_cleanup(assertz(hook_on), Goal, retractall(hook_on)).
tripped(Ws) :- findall(W, retract(tw(W, _)), Ws).
wire_of(error(resource_error(tripwire(W, T)), _), raised(W, K)) :- ( blob(T, trie) -> K = trie ; K = other ).
"""

const _TW_CASES = [
    ("wb01", "max_incomplete_subgoals with a passing hook trips once, at the limit (== limit)", raw"""
retractall(tw(_,_)), abolish_all_tables, hooked(with_limit(max_incomplete_subgoals, 2, error, ch(0))), tripped(Ws), R = Ws"""),
    ("wb02", "max_scc_subgoals 1: a merge of an SCC that started AT the limit trips (size0 <= limit)", raw"""
abolish_all_tables, catch(with_limit(max_scc_subgoals, 1, error, lp(0)), E, true), ( nonvar(E) -> wire_of(E, R) ; R = no_error )"""),
    ("wb03", "max_table_subgoal_size 2, hook passes: the lookup is retried unabstracted (get_answer_table goto retry)", raw"""
retractall(tw(_,_)), abolish_all_tables, hooked(with_limit(max_table_subgoal_size, 2, error, findall(X, sh(f(f(f(X)))), L))), tripped(Ws), R = L-Ws"""),
    ("wb04", "max_table_subgoal_size 2, action error: the predicate tripwire raises", raw"""
abolish_all_tables, with_limit(max_table_subgoal_size, 2, error, findall(X, sh(f(f(f(X)))), _)), R = no_error"""),
    ("wb05", "max_answers_for_subgoal 2, bounded_rationality: the general answer carries answer_count_restraint", raw"""
abolish_all_tables, with_limit(max_answers_for_subgoal, 2, bounded_rationality, findall(X-P, call_residual_program(cnt(X), P), L)), R = L"""),
    ("wb06", "max_answers_for_subgoal 2, action error: the worklist tripwire raises", raw"""
abolish_all_tables, catch(with_limit(max_answers_for_subgoal, 2, error, findall(X, cnt(X), _)), E, true), ( nonvar(E) -> wire_of(E, R) ; R = no_error )"""),
    ("wb07", "max_answers_for_subgoal 2, hook passes: the answer is added anyway (goto add_anyway)", raw"""
retractall(tw(_,_)), abolish_all_tables, hooked(with_limit(max_answers_for_subgoal, 2, error, findall(X, cnt(X), L))), tripped(Ws), R = L-Ws"""),
    ("wb08", "max_table_answer_size 0, bounded_rationality: the too deep answer is generalised and carries radial_restraint", raw"""
abolish_all_tables, with_limit(max_table_answer_size, 0, bounded_rationality, findall(X-P, call_residual_program(big(X), P), L)), R = L"""),
    ("wb09", "max_table_answer_size 0, action fail: the too deep answer is dropped", raw"""
abolish_all_tables, with_limit(max_table_answer_size, 0, fail, findall(X, big(X), L)), R = L"""),
    ("wb10", "max_table_answer_size 0, action error: the worklist tripwire raises", raw"""
abolish_all_tables, catch(with_limit(max_table_answer_size, 0, error, findall(X, big(X), _)), E, true), ( nonvar(E) -> wire_of(E, R) ; R = no_error )"""),
    ("wb11", "an incremental table whose only answer is replaced: the re-evaluation sets new_answer, the dependent table follows", raw"""
abolish_all_tables, findall(X, jj(X), L0), retract(dd(1)), assertz(dd(2)), findall(X, jj(X), L1), retract(dd(2)), assertz(dd(1)), R = L0-L1"""),
    ("wb12", "the dependency graph inside an evaluation that has a COMPLETED child component: only the active component is listed (sdg_collect)", raw"""
sdg(pa, Cs, Ts, Es), R = r(Cs, Ts, Es)"""),
]

const _TW_PINNED = [
    "ok",
    "t_wb01 c[116,95,119,98,48,49]/1(c[91,124,93]/2(a[109,97,120,95,105,110,99,111,109,112,108,101,116,101,95,115,117,98,103,111,97,108,115],nil))",
    "t_wb02 c[116,95,119,98,48,50]/1(c[114,97,105,115,101,100]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115],a[116,114,105,101]))",
    "t_wb03 c[116,95,119,98,48,51]/1(c[45]/2(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)),c[91,124,93]/2(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101],nil)))",
    "t_wb04 c[116,95,119,98,48,52]/1(c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(c[116,114,105,112,119,105,114,101]/2(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101],c[58]/2(a[117,115,101,114],c[115,104]/1(V0))))))",
    "t_wb05 c[116,95,119,98,48,53]/1(c[91,124,93]/2(c[45]/2(i1,nil),c[91,124,93]/2(c[45]/2(i2,nil),c[91,124,93]/2(c[45]/2(V0,c[91,124,93]/2(c[58,45]/2(c[99,110,116]/1(V0),a[97,110,115,119,101,114,95,99,111,117,110,116,95,114,101,115,116,114,97,105,110,116]),c[91,124,93]/2(c[58,45]/2(a[97,110,115,119,101,114,95,99,111,117,110,116,95,114,101,115,116,114,97,105,110,116],c[116,110,111,116]/1(a[97,110,115,119,101,114,95,99,111,117,110,116,95,114,101,115,116,114,97,105,110,116])),nil))),nil))))",
    "t_wb06 c[116,95,119,98,48,54]/1(c[114,97,105,115,101,100]/2(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108],a[116,114,105,101]))",
    "t_wb07 c[116,95,119,98,48,55]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil))))),c[91,124,93]/2(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108],nil)))",
    "t_wb08 c[116,95,119,98,48,56]/1(c[91,124,93]/2(c[45]/2(c[102]/3(a[97],a[98],a[99]),nil),c[91,124,93]/2(c[45]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[103]/1(V0),c[91,124,93]/2(c[58,45]/2(c[98,105,103]/1(c[103]/1(V0)),a[114,97,100,105,97,108,95,114,101,115,116,114,97,105,110,116]),c[91,124,93]/2(c[58,45]/2(a[114,97,100,105,97,108,95,114,101,115,116,114,97,105,110,116],c[116,110,111,116]/1(a[114,97,100,105,97,108,95,114,101,115,116,114,97,105,110,116])),nil))),nil))))",
    "t_wb09 c[116,95,119,98,48,57]/1(c[91,124,93]/2(c[102]/3(a[97],a[98],a[99]),c[91,124,93]/2(a[97],nil)))",
    "t_wb10 c[116,95,119,98,49,48]/1(c[114,97,105,115,101,100]/2(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101],a[116,114,105,101]))",
    "t_wb11 c[116,95,119,98,49,49]/1(c[45]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i2,nil)))",
    "t_wb12 c[116,95,119,98,49,50]/1(c[114]/3(c[91,124,93]/2(c[45]/2(i0,a[112,97]),nil),c[91,124,93]/2(c[116,97,98,108,101]/4(a[112,97],i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil),nil))",
]

"The program text with the cases appended."
_tw_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n" for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tw_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _tw_text(program, [(id, g) for (id, _, g) in _TW_CASES]))
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tw_enc(ball::_TW))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tw_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tws(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TW, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tw_enc(mk_expr(_TW, _TW[_tws(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as the pins hold it."
function _tw_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tw_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "restraint rows: the tripwires and the bounded rationality actions against the pinned answers" begin
    gd, ld, st = _tw_load(_TW_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TW_CASES
        push!(kl, _tw_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TW_PINNED)
    for (k, pn) in zip(kl, _TW_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tw_corrupt(_TW_PINNED[2])
end

@testset "the pinned table (no swipl needed)" begin
    @test length(_TW_PINNED) == length(_TW_CASES) + 1
    @test all(!isempty, _TW_PINNED)
    for ((id, _, _), pn) in zip(_TW_CASES, _TW_PINNED[2:end])
        @test startswith(pn, "t_$(id) ")
        @test !isempty(_tw_answer(pn))
    end
    # the hooked rows (wb01, wb03, wb07) read a NON-EMPTY list of tripped wires, atoms written as codes (both sides through `_tw_answer`)
    @test occursin(_tw_codes("max_incomplete_subgoals"), _tw_answer(_TW_PINNED[2]))
    @test occursin(_tw_codes("max_table_subgoal_size"), _tw_answer(_TW_PINNED[4]))
    @test occursin(_tw_codes("max_answers_for_subgoal"), _tw_answer(_TW_PINNED[8]))
    # must-fail: the corruption of a pin is not that pin
    @test _tw_answer(_tw_corrupt(_TW_PINNED[2])) != _tw_answer(_TW_PINNED[2])
end

@testset "generalise_answer_substitution: only `ret` is an atom answer substitution (white-box; pl-tabling.c static, swipl cannot be asked)" begin
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    res = Tuple{String, Bool}[]
    for name in ("ret", "foo")
        a = LK.PL_new_term_refs(ld, 2)
        @test LK.PL_put_atom(ld, a, _tws(name))
        push!(res, (name, LK.generalise_answer_substitution(ld, a, a + 1)))
        LK.PL_clear_exception(ld)
    end
    @test res == [("ret", true), ("foo", false)]
    # must-fail: the row can tell `foo` accepted from `foo` refused
    @test res != [("ret", true), ("foo", true)]
    @test !isempty(res) && all(r -> !isempty(first(r)), res)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "tw_restraint_swipl.pl")
        write(f, _tw_text(_TW_PROGRAM, [(id, g) for (id, _, g) in _TW_CASES]))
        got = _tw_swipl_lines(f, ["t_$id" for (id, _, _) in _TW_CASES])
        @test !isempty(got) && got == _TW_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tw_corrupt(_TW_PINNED[2])
    end
end
