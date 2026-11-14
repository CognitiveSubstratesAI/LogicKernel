# ORIGINAL: a LIVE differential of the tabling restraints and the dependency graph of pl-tabling.c (TAB1 TB8; audit D-0488) against
# swipl at the pin (swipl-devel 18168e62, 10.1.20): the ten restraint flags (`max_table_subgoal_size`, `max_table_answer_size`,
# `max_answers_for_subgoal`, `max_incomplete_subgoals`, `max_scc_subgoals` and their `_action` flags: `tbl_set_restraint_flag`,
# `tbl_get_restraint_flag`, `set_restraint`, `set_restraint_action`, `unify_restraint`, pl-tabling.c:11704-11800, pl-prologflag.c:1628,
# :2127), `'$tbl_incomplete'/3` and `'$tbl_sdg'/3` outside any evaluation (pl-tabling.c:9526-9820). Groups: tsd = the defaults,
# tsl = the limits, tsa = the actions, tsi = `$tbl_incomplete`, tsg = `$tbl_sdg`.
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_min_swipl.jl's (`enc`oded answers). A case that sets a flag reads it, resets it (`infinite`, `error`) and reads it again.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs); with `swipl` on PATH the live answers are compared
#     with the pins too.
#   * Left to the tests of the steps that make a table (TB1-TB6): the tripwires, the radial and answer-count restraints and the drop of
#     intermediate tables need an evaluation; the graph of a running evaluation needs worklists. Here the graph is the empty one, `[]-[]-[]`.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TG = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tgs(x) = lk_sym(_TG, Symbol(x))

_tg_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tg_enc(t::_TG, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tg_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tg_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tg_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tg_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TG_DRIVER = raw"""
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

function _tg_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TG_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _TG_COMMON = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tm_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
tm_flag(F, R) :- ( current_prolog_flag(F, V) -> R = r(V) ; R = none ).
tm_lim(F, V, R) :- set_prolog_flag(F, V), tm_flag(F, R1), set_prolog_flag(F, infinite), tm_flag(F, R2), R = a(R1, R2).
tm_act(F, V, R) :- set_prolog_flag(F, V), tm_flag(F, R1), set_prolog_flag(F, error), tm_flag(F, R2), R = a(R1, R2).
"""

const _TG_CASES = [
    ("tsd01", raw"tm_flag(max_table_subgoal_size, R)"),
    ("tsd02", raw"tm_flag(max_table_answer_size, R)"),
    ("tsd03", raw"tm_flag(max_answers_for_subgoal, R)"),
    ("tsd04", raw"tm_flag(max_incomplete_subgoals, R)"),
    ("tsd05", raw"tm_flag(max_scc_subgoals, R)"),
    ("tsd06", raw"tm_flag(max_table_subgoal_size_action, R)"),
    ("tsd07", raw"tm_flag(max_table_answer_size_action, R)"),
    ("tsd08", raw"tm_flag(max_answers_for_subgoal_action, R)"),
    ("tsd09", raw"tm_flag(max_incomplete_subgoals_action, R)"),
    ("tsd10", raw"tm_flag(max_scc_subgoals_action, R)"),
    (
        "tsd11",
        raw"findall(F-V, (current_prolog_flag(F, V), memberchk(F, [max_table_subgoal_size, max_table_subgoal_size_action, max_table_answer_size, max_table_answer_size_action, max_answers_for_subgoal, max_answers_for_subgoal_action, max_incomplete_subgoals, max_incomplete_subgoals_action, max_scc_subgoals, max_scc_subgoals_action])), L0), msort(L0, L), R = L"
    ),
    ("tsl01", raw"tm_lim(max_table_subgoal_size, 7, R)"),
    ("tsl02", raw"tm_lim(max_table_answer_size, 9, R)"),
    ("tsl03", raw"tm_lim(max_answers_for_subgoal, 5, R)"),
    ("tsl04", raw"tm_lim(max_incomplete_subgoals, 3, R)"),
    ("tsl05", raw"tm_lim(max_scc_subgoals, 4, R)"),
    ("tsl06", raw"tm_lim(max_answers_for_subgoal, 0, R)"),
    ("tsl07", raw"tm_lim(max_answers_for_subgoal, infinite, R)"),
    ("tsl08", raw"tm_lim(max_answers_for_subgoal, -1, R)"),
    ("tsl09", raw"tm_lim(max_answers_for_subgoal, a, R)"),
    ("tsl10", raw"tm_lim(max_answers_for_subgoal, 1.5, R)"),
    ("tsl11", raw"tm_lim(max_answers_for_subgoal, _, R)"),
    ("tsl12", raw"tm_lim(max_scc_subgoals, 100000000000, R)"),
    ("tsl13", raw"tm_lim(max_table_subgoal_size, \"5\", R)"),
    (
        "tsl14",
        raw"set_prolog_flag(max_answers_for_subgoal, 5), tm_flag(max_answers_for_subgoal, R0), tm_yn(current_prolog_flag(max_answers_for_subgoal, 6), R1), tm_yn(current_prolog_flag(max_answers_for_subgoal, 5), R2), set_prolog_flag(max_answers_for_subgoal, infinite), R = r(R0, R1, R2)"
    ),
    (
        "tsl15",
        raw"set_prolog_flag(max_answers_for_subgoal, 5), tm_yn(current_prolog_flag(max_answers_for_subgoal, a), R1), R = R1"
    ),
    (
        "tsl16",
        raw"set_prolog_flag(max_answers_for_subgoal, 5), tm_yn(current_prolog_flag(max_answers_for_subgoal, 5.0), R1), R = R1"
    ),
    (
        "tsl17",
        raw"set_prolog_flag(max_answers_for_subgoal, 5), set_prolog_flag(max_scc_subgoals, 6), findall(F-V, (current_prolog_flag(F, V), memberchk(F, [max_table_subgoal_size, max_table_subgoal_size_action, max_table_answer_size, max_table_answer_size_action, max_answers_for_subgoal, max_answers_for_subgoal_action, max_incomplete_subgoals, max_incomplete_subgoals_action, max_scc_subgoals, max_scc_subgoals_action])), L0), msort(L0, L), set_prolog_flag(max_answers_for_subgoal, infinite), set_prolog_flag(max_scc_subgoals, infinite), R = L"
    ),
    ("tsl18", raw"tm_flag(max_answers_for_subgoal, R)"),
    ("tsa01", raw"tm_act(max_table_subgoal_size_action, error, R)"),
    ("tsa02", raw"tm_act(max_table_subgoal_size_action, warning, R)"),
    ("tsa03", raw"tm_act(max_table_subgoal_size_action, suspend, R)"),
    ("tsa04", raw"tm_act(max_table_subgoal_size_action, abstract, R)"),
    ("tsa05", raw"tm_act(max_table_subgoal_size_action, bounded_rationality, R)"),
    ("tsa06", raw"tm_act(max_table_subgoal_size_action, fail, R)"),
    ("tsa07", raw"tm_act(max_table_subgoal_size_action, complete_soundly, R)"),
    ("tsa08", raw"tm_act(max_table_subgoal_size_action, infinite, R)"),
    ("tsa09", raw"tm_act(max_table_answer_size_action, error, R)"),
    ("tsa10", raw"tm_act(max_table_answer_size_action, warning, R)"),
    ("tsa11", raw"tm_act(max_table_answer_size_action, suspend, R)"),
    ("tsa12", raw"tm_act(max_table_answer_size_action, abstract, R)"),
    ("tsa13", raw"tm_act(max_table_answer_size_action, bounded_rationality, R)"),
    ("tsa14", raw"tm_act(max_table_answer_size_action, fail, R)"),
    ("tsa15", raw"tm_act(max_table_answer_size_action, complete_soundly, R)"),
    ("tsa16", raw"tm_act(max_answers_for_subgoal_action, error, R)"),
    ("tsa17", raw"tm_act(max_answers_for_subgoal_action, warning, R)"),
    ("tsa18", raw"tm_act(max_answers_for_subgoal_action, suspend, R)"),
    ("tsa19", raw"tm_act(max_answers_for_subgoal_action, abstract, R)"),
    ("tsa20", raw"tm_act(max_answers_for_subgoal_action, bounded_rationality, R)"),
    ("tsa21", raw"tm_act(max_answers_for_subgoal_action, fail, R)"),
    ("tsa22", raw"tm_act(max_answers_for_subgoal_action, complete_soundly, R)"),
    ("tsa23", raw"tm_act(max_incomplete_subgoals_action, error, R)"),
    ("tsa24", raw"tm_act(max_incomplete_subgoals_action, warning, R)"),
    ("tsa25", raw"tm_act(max_incomplete_subgoals_action, suspend, R)"),
    ("tsa26", raw"tm_act(max_incomplete_subgoals_action, abstract, R)"),
    ("tsa27", raw"tm_act(max_incomplete_subgoals_action, bounded_rationality, R)"),
    ("tsa28", raw"tm_act(max_incomplete_subgoals_action, fail, R)"),
    ("tsa29", raw"tm_act(max_incomplete_subgoals_action, complete_soundly, R)"),
    ("tsa30", raw"tm_act(max_scc_subgoals_action, error, R)"),
    ("tsa31", raw"tm_act(max_scc_subgoals_action, warning, R)"),
    ("tsa32", raw"tm_act(max_scc_subgoals_action, suspend, R)"),
    ("tsa33", raw"tm_act(max_scc_subgoals_action, abstract, R)"),
    ("tsa34", raw"tm_act(max_scc_subgoals_action, bounded_rationality, R)"),
    ("tsa35", raw"tm_act(max_scc_subgoals_action, fail, R)"),
    ("tsa36", raw"tm_act(max_scc_subgoals_action, complete_soundly, R)"),
    ("tsa37", raw"tm_act(max_answers_for_subgoal_action, 1, R)"),
    ("tsa38", raw"tm_act(max_answers_for_subgoal_action, _, R)"),
    ("tsa39", raw"tm_act(max_answers_for_subgoal_action, f(x), R)"),
    ("tsa40", raw"tm_act(max_scc_subgoals_action, \"error\", R)"),
    (
        "tsa41",
        raw"catch(set_prolog_flag(max_answers_for_subgoal_action, abstract), _, true), tm_flag(max_answers_for_subgoal_action, R)"
    ),
    (
        "tsa42",
        raw"set_prolog_flag(max_table_answer_size_action, complete_soundly), tm_flag(max_table_answer_size_action, R0), set_prolog_flag(max_table_answer_size_action, error), R = R0"
    ),
    ("tsi01", raw"'$tbl_incomplete'(main, A, B), R = r(A, B)"),
    ("tsi02", raw"'$tbl_incomplete'(1, A, B), R = r(A, B)"),
    ("tsi03", raw"'$tbl_incomplete'(0, _, _), R = ok"),
    ("tsi04", raw"'$tbl_incomplete'(-1, _, _), R = ok"),
    ("tsi05", raw"'$tbl_incomplete'(foo, _, _), R = ok"),
    ("tsi06", raw"'$tbl_incomplete'(2, _, _), R = ok"),
    ("tsi07", raw"'$tbl_incomplete'(f(x), _, _), R = ok"),
    ("tsi08", raw"'$tbl_incomplete'(_, _, _), R = ok"),
    ("tsi09", raw"'$tbl_incomplete'(1.0, _, _), R = ok"),
    ("tsi10", raw"'$tbl_incomplete'(\"main\", _, _), R = ok"),
    ("tsi11", raw"tm_yn('$tbl_incomplete'(main, 0, 0), R)"),
    ("tsi12", raw"tm_yn('$tbl_incomplete'(main, 1, _), R)"),
    ("tsi13", raw"tm_yn('$tbl_incomplete'(main, _, 1), R)"),
    ("tsi14", raw"'$tbl_incomplete'(main, a, _), R = ok"),
    ("tsi15", raw"'$tbl_incomplete'(main, _, a), R = ok"),
    ("tsi16", raw"'$tbl_incomplete'(main, 1.0, _), R = ok"),
    ("tsi17", raw"'$tbl_incomplete'(thread_self_alias, _, _), R = ok"),
    (
        "tsi18",
        raw"'$tbl_incomplete'(1, A, B), '$tbl_incomplete'(main, A2, B2), tm_same(A-B, A2-B2, R)"
    ),
    ("tsg01", raw"'$tbl_sdg'(A, B, C), R = r(A, B, C)"),
    ("tsg02", raw"tm_yn('$tbl_sdg'([], [], []), R)"),
    ("tsg03", raw"tm_yn('$tbl_sdg'(a, _, _), R)"),
    ("tsg04", raw"tm_yn('$tbl_sdg'(_, a, _), R)"),
    ("tsg05", raw"tm_yn('$tbl_sdg'(_, _, a), R)"),
    ("tsg06", raw"tm_yn('$tbl_sdg'([_|_], _, _), R)"),
    ("tsg07", raw"tm_yn('$tbl_sdg'(_, [_|_], _), R)"),
    ("tsg08", raw"tm_yn('$tbl_sdg'(_, _, [_|_]), R)"),
    (
        "tsg09",
        raw"'$tbl_sdg'(A, B, C), '$tbl_incomplete'(main, T, S), R = r(A, B, C, T, S)"
    ),
]

const _TG_PINNED = [
    "ok",
    "t_tsd01 c[116,95,116,115,100,48,49]/1(a[110,111,110,101])",
    "t_tsd02 c[116,95,116,115,100,48,50]/1(a[110,111,110,101])",
    "t_tsd03 c[116,95,116,115,100,48,51]/1(a[110,111,110,101])",
    "t_tsd04 c[116,95,116,115,100,48,52]/1(a[110,111,110,101])",
    "t_tsd05 c[116,95,116,115,100,48,53]/1(a[110,111,110,101])",
    "t_tsd06 c[116,95,116,115,100,48,54]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsd07 c[116,95,116,115,100,48,55]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsd08 c[116,95,116,115,100,48,56]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsd09 c[116,95,116,115,100,48,57]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsd10 c[116,95,116,115,100,49,48]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsd11 c[116,95,116,115,100,49,49]/1(c[91,124,93]/2(c[45]/2(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,105,110,99,111,109,112,108,101,116,101,95,115,117,98,103,111,97,108,115,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101,95,97,99,116,105,111,110],a[101,114,114,111,114]),nil))))))",
    "t_tsl01 c[116,95,116,115,108,48,49]/1(c[97]/2(c[114]/1(i7),a[110,111,110,101]))",
    "t_tsl02 c[116,95,116,115,108,48,50]/1(c[97]/2(c[114]/1(i9),a[110,111,110,101]))",
    "t_tsl03 c[116,95,116,115,108,48,51]/1(c[97]/2(c[114]/1(i5),a[110,111,110,101]))",
    "t_tsl04 c[116,95,116,115,108,48,52]/1(c[97]/2(c[114]/1(i3),a[110,111,110,101]))",
    "t_tsl05 c[116,95,116,115,108,48,53]/1(c[97]/2(c[114]/1(i4),a[110,111,110,101]))",
    "t_tsl06 c[116,95,116,115,108,48,54]/1(c[97]/2(c[114]/1(i0),a[110,111,110,101]))",
    "t_tsl07 c[116,95,116,115,108,48,55]/1(c[97]/2(a[110,111,110,101],a[110,111,110,101]))",
    "t_tsl08 c[116,95,116,115,108,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_tsl09 c[116,95,116,115,108,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_tsl10 c[116,95,116,115,108,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_tsl11 c[116,95,116,115,108,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tsl12 c[116,95,116,115,108,49,50]/1(c[97]/2(c[114]/1(i100000000000),a[110,111,110,101]))",
    "t_tsl13 c[116,95,116,115,108,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],s[53])))",
    "t_tsl14 c[116,95,116,115,108,49,52]/1(c[114]/3(c[114]/1(i5),a[110,111],a[121,101,115]))",
    "t_tsl15 c[116,95,116,115,108,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_tsl16 c[116,95,116,115,108,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f5.0)))",
    "t_tsl17 c[116,95,116,115,108,49,55]/1(c[91,124,93]/2(c[45]/2(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108],i5),c[91,124,93]/2(c[45]/2(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,105,110,99,111,109,112,108,101,116,101,95,115,117,98,103,111,97,108,115,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115],i6),c[91,124,93]/2(c[45]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101,95,97,99,116,105,111,110],a[101,114,114,111,114]),c[91,124,93]/2(c[45]/2(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101,95,97,99,116,105,111,110],a[101,114,114,111,114]),nil))))))))",
    "t_tsl18 c[116,95,116,115,108,49,56]/1(a[110,111,110,101])",
    "t_tsa01 c[116,95,116,115,97,48,49]/1(c[97]/2(c[114]/1(a[101,114,114,111,114]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa02 c[116,95,116,115,97,48,50]/1(c[97]/2(c[114]/1(a[119,97,114,110,105,110,103]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa03 c[116,95,116,115,97,48,51]/1(c[97]/2(c[114]/1(a[115,117,115,112,101,110,100]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa04 c[116,95,116,115,97,48,52]/1(c[97]/2(c[114]/1(a[97,98,115,116,114,97,99,116]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa05 c[116,95,116,115,97,48,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121])))",
    "t_tsa06 c[116,95,116,115,97,48,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[102,97,105,108])))",
    "t_tsa07 c[116,95,116,115,97,48,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[99,111,109,112,108,101,116,101,95,115,111,117,110,100,108,121])))",
    "t_tsa08 c[116,95,116,115,97,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[105,110,102,105,110,105,116,101])))",
    "t_tsa09 c[116,95,116,115,97,48,57]/1(c[97]/2(c[114]/1(a[101,114,114,111,114]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa10 c[116,95,116,115,97,49,48]/1(c[97]/2(c[114]/1(a[119,97,114,110,105,110,103]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa11 c[116,95,116,115,97,49,49]/1(c[97]/2(c[114]/1(a[115,117,115,112,101,110,100]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa12 c[116,95,116,115,97,49,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[97,98,115,116,114,97,99,116])))",
    "t_tsa13 c[116,95,116,115,97,49,51]/1(c[97]/2(c[114]/1(a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa14 c[116,95,116,115,97,49,52]/1(c[97]/2(c[114]/1(a[102,97,105,108]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa15 c[116,95,116,115,97,49,53]/1(c[97]/2(c[114]/1(a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa16 c[116,95,116,115,97,49,54]/1(c[97]/2(c[114]/1(a[101,114,114,111,114]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa17 c[116,95,116,115,97,49,55]/1(c[97]/2(c[114]/1(a[119,97,114,110,105,110,103]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa18 c[116,95,116,115,97,49,56]/1(c[97]/2(c[114]/1(a[115,117,115,112,101,110,100]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa19 c[116,95,116,115,97,49,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[97,98,115,116,114,97,99,116])))",
    "t_tsa20 c[116,95,116,115,97,50,48]/1(c[97]/2(c[114]/1(a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa21 c[116,95,116,115,97,50,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[102,97,105,108])))",
    "t_tsa22 c[116,95,116,115,97,50,50]/1(c[97]/2(c[114]/1(a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa23 c[116,95,116,115,97,50,51]/1(c[97]/2(c[114]/1(a[101,114,114,111,114]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa24 c[116,95,116,115,97,50,52]/1(c[97]/2(c[114]/1(a[119,97,114,110,105,110,103]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa25 c[116,95,116,115,97,50,53]/1(c[97]/2(c[114]/1(a[115,117,115,112,101,110,100]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa26 c[116,95,116,115,97,50,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[97,98,115,116,114,97,99,116])))",
    "t_tsa27 c[116,95,116,115,97,50,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121])))",
    "t_tsa28 c[116,95,116,115,97,50,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[102,97,105,108])))",
    "t_tsa29 c[116,95,116,115,97,50,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[99,111,109,112,108,101,116,101,95,115,111,117,110,100,108,121])))",
    "t_tsa30 c[116,95,116,115,97,51,48]/1(c[97]/2(c[114]/1(a[101,114,114,111,114]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa31 c[116,95,116,115,97,51,49]/1(c[97]/2(c[114]/1(a[119,97,114,110,105,110,103]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa32 c[116,95,116,115,97,51,50]/1(c[97]/2(c[114]/1(a[115,117,115,112,101,110,100]),c[114]/1(a[101,114,114,111,114])))",
    "t_tsa33 c[116,95,116,115,97,51,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[97,98,115,116,114,97,99,116])))",
    "t_tsa34 c[116,95,116,115,97,51,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121])))",
    "t_tsa35 c[116,95,116,115,97,51,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[102,97,105,108])))",
    "t_tsa36 c[116,95,116,115,97,51,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,115,116,114,97,105,110,116,95,97,99,116,105,111,110],a[99,111,109,112,108,101,116,101,95,115,111,117,110,100,108,121])))",
    "t_tsa37 c[116,95,116,115,97,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_tsa38 c[116,95,116,115,97,51,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tsa39 c[116,95,116,115,97,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_tsa40 c[116,95,116,115,97,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[101,114,114,111,114])))",
    "t_tsa41 c[116,95,116,115,97,52,49]/1(c[114]/1(a[101,114,114,111,114]))",
    "t_tsa42 c[116,95,116,115,97,52,50]/1(c[114]/1(a[98,111,117,110,100,101,100,95,114,97,116,105,111,110,97,108,105,116,121]))",
    "t_tsi01 c[116,95,116,115,105,48,49]/1(c[114]/2(i0,i0))",
    "t_tsi02 c[116,95,116,115,105,48,50]/1(c[114]/2(i0,i0))",
    "t_tsi03 c[116,95,116,115,105,48,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i0)))",
    "t_tsi04 c[116,95,116,115,105,48,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i-1)))",
    "t_tsi05 c[116,95,116,115,105,48,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[102,111,111])))",
    "t_tsi06 c[116,95,116,115,105,48,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i2)))",
    "t_tsi07 c[116,95,116,115,105,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],c[102]/1(a[120]))))",
    "t_tsi08 c[116,95,116,115,105,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tsi09 c[116,95,116,115,105,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],f1.0)))",
    "t_tsi10 c[116,95,116,115,105,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],s[109,97,105,110])))",
    "t_tsi11 c[116,95,116,115,105,49,49]/1(a[121,101,115])",
    "t_tsi12 c[116,95,116,115,105,49,50]/1(a[110,111])",
    "t_tsi13 c[116,95,116,115,105,49,51]/1(a[110,111])",
    "t_tsi14 c[116,95,116,115,105,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_tsi15 c[116,95,116,115,105,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_tsi16 c[116,95,116,115,105,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_tsi17 c[116,95,116,115,105,49,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[116,104,114,101,97,100,95,115,101,108,102,95,97,108,105,97,115])))",
    "t_tsi18 c[116,95,116,115,105,49,56]/1(a[115,97,109,101])",
    "t_tsg01 c[116,95,116,115,103,48,49]/1(c[114]/3(nil,nil,nil))",
    "t_tsg02 c[116,95,116,115,103,48,50]/1(a[121,101,115])",
    "t_tsg03 c[116,95,116,115,103,48,51]/1(a[110,111])",
    "t_tsg04 c[116,95,116,115,103,48,52]/1(a[110,111])",
    "t_tsg05 c[116,95,116,115,103,48,53]/1(a[110,111])",
    "t_tsg06 c[116,95,116,115,103,48,54]/1(a[110,111])",
    "t_tsg07 c[116,95,116,115,103,48,55]/1(a[110,111])",
    "t_tsg08 c[116,95,116,115,103,48,56]/1(a[110,111])",
    "t_tsg09 c[116,95,116,115,103,48,57]/1(c[114]/5(nil,nil,nil,i0,i0))",
]

"The program text with the cases appended."
_tg_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tg_load(program::String)
    f = joinpath(mktempdir(), "tabling_sdg.pl")
    write(f, _tg_text(program, _TG_CASES))
    gd = LK.PL_global_data{_TG}()
    ld = LK.PL_local_data{_TG}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tg_enc(ball::_TG))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tg_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tgs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TG, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tg_enc(mk_expr(_TG, _TG[_tgs(pred), lk_answers(ld, (a:a)...)...])))
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

@testset "tabling restraints and the dependency graph as swipl's (tsd, tsl, tsa, tsi, tsg)" begin
    gd, ld, st = _tg_load(_TG_COMMON)
    @test st == "ok"
    kl = String[st]
    for (id, _) in _TG_CASES
        push!(kl, _tg_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TG_PINNED)
    for (k, p) in zip(kl, _TG_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # white-box: every case reset what it set (the restraints are the defaults again, initTabling's)
    r = ld.tabling.restraint
    @test r.max_table_subgoal_size == -1 && r.max_table_answer_size == -1
    @test r.max_answers_for_subgoal == -1 && r.max_incomplete_subgoals == -1 && r.max_scc_subgoals == -1
    for act in (
        r.max_table_subgoal_size_action, r.max_table_answer_size_action, r.max_answers_for_subgoal_action,
        r.max_incomplete_subgoals_action, r.max_scc_subgoals_action
    )
        @test sym_text(act) == "error"
    end
    @test ld.tabling.incomplete_tables == 0 && ld.tabling.active_components == 0
end

@testset "the restraint and graph rows are not vacuous" begin
    @test _TG_PINNED[1] == "ok"
    @test length(_TG_PINNED) == length(_TG_CASES) + 1
    for pre in ("tsd", "tsl", "tsa", "tsi", "tsg")
        ids = [id for (id, _) in _TG_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _TG_PINNED if any(id -> startswith(l, "t_$id "), ids)]) == length(ids)
    end
    line(id) = only(filter(l -> startswith(l, "t_$id "), _TG_PINNED))
    ans(id) = split(line(id), " "; limit=2)[2]
    @test ans("tsd01") != ans("tsd06")      # a limit fails (infinite), an action reads `error`
    @test ans("tsl01") != ans("tsl08")      # a limit set, a negative one refused
    @test ans("tsl14") != ans("tsl15")      # an integer that differs fails, a non-integer is a type error
    @test ans("tsa02") != ans("tsa05")      # warning accepted, bounded_rationality refused for the subgoal size
    @test ans("tsa15") != ans("tsa07")      # complete_soundly is bounded_rationality where that is accepted
    @test ans("tsi01") != ans("tsi05")      # the thread main, a thread that does not exist
    @test ans("tsg01") != ans("tsg03")      # the empty graph, a non-list
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB8 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_swipl.pl")
        write(f, _tg_text(_TG_COMMON, _TG_CASES))
        @test _tg_swipl_lines(f, ["t_$id" for (id, _) in _TG_CASES]) == _TG_PINNED
    end
end
