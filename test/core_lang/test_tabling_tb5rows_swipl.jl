# ORIGINAL: kill rows for the TB4 survivors whose owner is TB5 (TB4-S4, TB4-A3) and for the TB5 mutants of tools/mutants/TB5.py that no row of
# test_tabling_abolish_swipl.jl asserts (TB5-E10, TB5-E11), against swipl at the pin (swipl-devel 18168e62, 10.1.20); STEP TB5-ROWS.
#   * Groups A3N, A3P, A3Q (TB4-A3: has_positive_dl counts a negative delay; pl-tabling.c:2290 has_positive_dl, :2316 is_ac_candidate_wl). The
#     older row (test_tabling_tb4_tb5_swipl.jl group G13B) cannot kill it: its program makes NO simplification (the component {a13, f13} completes
#     alone; e13 and c13 never share a component with it) and answer completion is called only for `undefined && scc->simplifications`
#     (pl-tabling.c:2195, the kernel's simplify_component). Here ONE component holds a simplification (`le :- lp, fail.` is empty and tnot'd
#     inside the component, `lp :- tnot(lq), tnot(le).` loses its `tnot(le)` member) and an undefined loop lp <-> lq whose dependents hold NEGATIVE
#     delay elements only: swipl makes ZERO calls of '$tabling':answer_completion/2 (A3N), the mutant (`return true` for a negative element) calls
#     it. Controls, both pinned from swipl: A3P adds `lq :- lp.` (a positive element: ONE call, so the counter works in this program), A3Q is A3P
#     without `le` (no simplification: ZERO calls, so the 0 of A3N is not "answer completion never runs").
#   * Groups S4A, S4B (TB4-S4: simplify_component stops after one pass): the model of a component with two worklists decided by propagation and
#     an answer that turns true (se). Ground answers give pass 1 nothing to do (every removal of a conditional answer pushes its own propagation,
#     pl-tabling.c:1846-1866), so these rows PIN the model (a regression guard of the simplification chain) and do NOT kill TB4-S4.
#   * Group S4C (KILLS TB4-S4, STEP S3z-2): the second scan block of simplify_component (pl-tabling.c:2149-2168) walks `wl->pos_undefined`, the
#     positive delay elements on NON-GROUND answers (add_to_wl_pos_undefined, :1425-1479). `sa(_)` is called with its variable open, `sa(a)` is the
#     answer; `sb(_) :- tnot(sb(a)), sa(_)` and `sa(a) :- sb(X), X = a` close a positive loop through the table of `sb(_)`, and `sc :- tnot(sa(a)), sd`
#     / `se :- tnot(sc)` hang a negative chain onto it. In pass 0 the scan of the worklist holding the loop finds three `pos_undefined` entries
#     still conditional (kept), and a worklist scanned LATER removes or resolves their answers; pass 1's scan is the first to find them no longer
#     conditional and to push their propagation (`push_propagate(wl, r, value != 0)`: count 3, pos_undefined emptied, answer and delay-set state
#     changed). With the break after pass 0 (TB4-S4) that propagation never runs and the table of `sa(_)` ends without its answer: s406 reads the
#     one delay `sa(a)` on swipl (pinned, swipl 10.1.20), the mutant none; s407 reads `[a]` against `[]`, s408 `undefined` for `sa(_)` and `sa(a)`
#     against `false`.
#   * Group L2 (TB5-L2: delayed_destroy_table sets TRIE_ABOLISH_ON_COMPLETE; pl-tabling.c:4495 delayed_destroy_table, :6477 the completion that
#     deletes the table): a tabled goal calls `abolish_all_tables` inside its own evaluation (boot/tabling.pl abolish_all_tables:
#     '$tbl_abolish_local_tables' fails while an evaluation runs, so each table goes through '$tbl_destroy_table', pl-tabling.c abolish_table,
#     and the incomplete table is only FLAGGED). swipl: the flagged table is deleted when the evaluation completes (`current_table/2` finds
#     none, the second call evaluates again: counter 2); the mutant keeps it (a table, counter 1). l204/l205 are the control: the same goal
#     without the abolish keeps its table and is not evaluated twice.
#   * Groups A7 and O5 (TB5-A7 abolish_table deletes the orphan dynamic children, TB5-O5 the sweep collects the orphans, pl-tabling.c:4533-4610,
#     :4870-4921): `_T5_GROUPS_ENG1`, pinned from swipl and checked against it live, run on the kernel since ENG1: delete_dynamic_table
#     (src/pl-tabling.jl) used to reach `reset_answer_table`'s IDG refusal for every real orphan (an orphan has its IDG node), evidence/TAB1/
#     defkill_inventory.md ENGINE FINDING; it now runs `reset_answer_table_idg` before the trie_delete, as swipl's release chain does
#     (`_T5_GROUPS_RUN = vcat(_T5_GROUPS, _T5_GROUPS_ENG1)`). A7: swipl deletes the dependent-less dynamic table `ad` together
#     with the incremental table `ap` that held it (a704: no table left), keeps it while `ap` stays (a703: the abolish of `ad` alone). O5: 1100
#     dynamic variants lose their only dependent in two reevaluations (events 2200 >= 1024 and >= the 1104 variants), the sweep of the next
#     completed root component (`dm(d)`) deletes them: 6 tables left (swipl), the mutant keeps 1106.
#   * Testset "clear_variant_table releases the IDG registry" (TB5-E10, TB5-E11): LK-only white-box; the thread's registry holds one reference
#     per node plus the thread's; after clear_variant_table none is left (empty_variant_table: idg_registry_release_n(registry, idg_nodes + 1)).
#   * Cases `t_<id>(R)` run in order in ONE database per group, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; a case that
#     fails is the bare `t_<id>` line. Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs); with `swipl` on PATH the
#     live answers are compared with the pins too.
#   * Testset "clearThreadTablingData resets the global worklist of the component" (TB5-H4): LK-only white-box (no Prolog route: '$tbl_abolish_local_tables'
#     runs only without an evaluation, and then `ld.tabling.component` is empty).
#   * TB5-E9 has NO row: empty_variant_table's else branch runs only for a variant table with `value_count == 0` (its only caller passes
#     `delays_done = false` whenever the table has no reader), a table without a value has no table to visit (tools/mutants/TB5.py, the entry).
#   * UNVERIFIED on the kernel (edit-only step, nothing compiled): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T5_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_T5_sym(x) = lk_sym(_T5_T, Symbol(x))

_T5_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _T5_enc(t::_T5_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _T5_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _T5_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _T5_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_T5_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _T5_DRIVER = raw"""
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

function _T5_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _T5_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The program text with the cases of `cases` appended."
_T5_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _T5_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb5rows.pl")
    write(f, _T5_text(program, cases))
    gd = LK.PL_global_data{_T5_T}()
    ld = LK.PL_local_data{_T5_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _T5_enc(ball::_T5_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _T5_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_T5_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T5_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _T5_enc(mk_expr(_T5_T, _T5_T[_T5_sym(pred), lk_answers(ld, (a:a)...)...]))
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


const _T5_CNT = raw"""
:- use_module(library(prolog_wrap)).
:- nb_setval(acc13, 0).
:- wrap_predicate('$tabling':answer_completion(_, _), cnt13, W,
       ( nb_current(inac13, true) -> W
       ; nb_getval(acc13, N0), N is N0+1, nb_setval(acc13, N), nb_setval(inac13, true), call_cleanup(W, nb_setval(inac13, false)) )).
"""
const _T5_TRUTH = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tr_truth(G, T) :- ( call_delays(G, Delays) -> ( Delays == true -> T = true ; T = undefined ) ; T = false ).
"""
const _T5_PROG_A3N = ":- use_module(library(wfs)).\n" * _T5_CNT * raw"""
:- table lp/0, lq/0, le/0.
lp :- tnot(lq), tnot(le).
lq :- tnot(lp).
le :- lp, fail.
"""
const _T5_PROG_A3P = ":- use_module(library(wfs)).\n" * _T5_CNT * raw"""
:- table lp/0, lq/0, le/0.
lp :- tnot(lq), tnot(le).
lq :- tnot(lp).
lq :- lp.
le :- lp, fail.
"""
const _T5_PROG_A3Q = ":- use_module(library(wfs)).\n" * _T5_CNT * raw"""
:- table lp/0, lq/0.
lp :- tnot(lq).
lq :- tnot(lp).
lq :- lp.
"""
const _T5_PROG_S4A = ":- use_module(library(wfs)).\n" * _T5_TRUTH * raw"""
:- table sp/0, sa/0, sb/0, se/0.
sp :- tnot(sa).
sa :- tnot(sb).
sa :- se.
sb :- sp, fail.
se :- tnot(sp).
"""
const _T5_PROG_S4B = ":- use_module(library(wfs)).\n" * _T5_TRUTH * raw"""
:- table sp/0, sa/0, sb/0, se/0.
sp :- tnot(sa).
sa :- se.
sa :- tnot(sb).
sb :- sp, fail.
se :- tnot(sp).
"""

const _T5_PROG_S4C = ":- use_module(library(wfs)).\n" * _T5_TRUTH * raw"""
:- table sa/1, sb/1, sc/0, sd/0, se/0.
sa(_) :- tnot(se).
sa(a) :- sb(X), X = a.
sb(_) :- tnot(sb(a)), sa(_).
sc :- tnot(sa(a)), sd.
sd :- fail.
se :- tnot(sc).
"""

const _T5_PROG_L2 = raw"""
:- nb_setval(cntl2, 0).
:- table l2p/1, l2q/1.
l2p(X) :- nb_getval(cntl2, N0), N is N0+1, nb_setval(cntl2, N), abolish_all_tables, X = 1.
l2q(X) :- nb_getval(cntl2, N0), N is N0+1, nb_setval(cntl2, N), X = 1.
l2_has(G, R) :- ( current_table(G, _) -> R = present ; R = absent ).
"""
const _T5_PROG_A7 = raw"""
:- table ap/1 as incremental.
:- dynamic ad/1 as incremental.
ad(1).
ad(2).
ap(X) :- ad(X).
a7_names(R) :- '$tbl_variant_table'(VT), findall(N, (trie_gen(VT, user:K, _), functor(K, N, _)), Ns), msort(Ns, R).
"""
const _T5_PROG_O5 = raw"""
:- table orr/0 as incremental.
:- table dm/1.
:- dynamic off/0 as incremental.
:- dynamic of/1 as incremental.
orr :- ( off -> true ; forall(between(1, 1100, I), (of(I) ; true)) ).
of(0).
dm(_).
o5_count(C) :- '$tbl_variant_table'(VT), aggregate_all(count, trie_gen(VT, _, _), C).
o5_cyc(K, C) :- ( orr -> true ; true ), dm(K), o5_count(C).
"""

const _T5_GROUPS = [
    (
        key="A3N",
        label="A3: a simplification and an undefined loop of negative delays only, answer completion not called (TB4-A3)",
        program=_T5_PROG_A3N,
        cases=[
            ("a301", raw"call_delays(lp, D), nb_getval(acc13, N), R = N-D"),
            ("a302", raw"call_delays(lq, D), nb_getval(acc13, N), R = N-D")
        ],
        pins=[
            "ok",
            "t_a301 c[116,95,97,51,48,49]/1(c[45]/2(i0,a[108,112]))",
            "t_a302 c[116,95,97,51,48,50]/1(c[45]/2(i0,a[108,113]))"
        ]
    ),
    (
        key="A3P",
        label="A3 control: the same plus a positive delay element, answer completion called once",
        program=_T5_PROG_A3P,
        cases=[
            ("a303", raw"call_delays(lp, D), nb_getval(acc13, N), R = N-D"),
            ("a304", raw"call_delays(lq, D), nb_getval(acc13, N), R = N-D")
        ],
        pins=[
            "ok",
            "t_a303 c[116,95,97,51,48,51]/1(c[45]/2(i1,a[108,112]))",
            "t_a304 c[116,95,97,51,48,52]/1(c[45]/2(i1,a[108,113]))"
        ]
    ),
    (
        key="A3Q",
        label="A3 control: a positive delay element but no simplification, answer completion not called",
        program=_T5_PROG_A3Q,
        cases=[("a305", raw"call_delays(lp, D), nb_getval(acc13, N), R = N-D")],
        pins=["ok", "t_a305 c[116,95,97,51,48,53]/1(c[45]/2(i0,a[108,112]))"]
    ),
    (
        key="S4A",
        label="S4: the model of the component with two decided worklists, clause order a (TB4-S4 regression pin)",
        program=_T5_PROG_S4A,
        cases=[
            ("s401", raw"sp, R = yes"),
            (
                "s402",
                raw"findall(G=T, (member(G, [sp, sa, sb, se]), tr_truth(G, T)), M), R = M"
            ),
            ("s403", raw"call_delays(se, D), R = D")
        ],
        pins=[
            "ok",
            "t_s401",
            "t_s402 c[116,95,115,52,48,50]/1(c[91,124,93]/2(c[61]/2(a[115,112],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,97],a[116,114,117,101]),c[91,124,93]/2(c[61]/2(a[115,98],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,101],a[116,114,117,101]),nil)))))",
            "t_s403 c[116,95,115,52,48,51]/1(a[116,114,117,101])"
        ]
    ),
    (
        key="S4B",
        label="S4: the same, clause order b",
        program=_T5_PROG_S4B,
        cases=[
            (
                "s404",
                raw"findall(G=T, (member(G, [sp, sa, sb, se]), tr_truth(G, T)), M), R = M"
            ),
            ("s405", raw"call_delays(se, D), R = D")
        ],
        pins=[
            "ok",
            "t_s404 c[116,95,115,52,48,52]/1(c[91,124,93]/2(c[61]/2(a[115,112],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,97],a[116,114,117,101]),c[91,124,93]/2(c[61]/2(a[115,98],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,101],a[116,114,117,101]),nil)))))",
            "t_s405 c[116,95,115,52,48,53]/1(a[116,114,117,101])"
        ]
    ),
    (
        key="S4C",
        label="S4: pass 1 propagates the pos_undefined entries of non-ground answers (kills TB4-S4)",
        program=_T5_PROG_S4C,
        cases=[
            ("s406", raw"findall(D, call_delays(sa(_), D), L), R = L"),
            ("s407", raw"findall(X, sa(X), L), R = L"),
            (
                "s408",
                raw"findall(G=T, (member(G, [sa(_), sa(a), sb(_), sb(a), sc, sd, se]), tr_truth(G, T)), M), R = M"
            )
        ],
        pins=[
            "ok",
            "t_s406 c[116,95,115,52,48,54]/1(c[91,124,93]/2(c[115,97]/1(a[97]),nil))",
            "t_s407 c[116,95,115,52,48,55]/1(c[91,124,93]/2(a[97],nil))",
            "t_s408 c[116,95,115,52,48,56]/1(c[91,124,93]/2(c[61]/2(c[115,97]/1(a[97]),a[117,110,100,101,102,105,110,101,100]),c[91,124,93]/2(c[61]/2(c[115,97]/1(a[97]),a[117,110,100,101,102,105,110,101,100]),c[91,124,93]/2(c[61]/2(c[115,98]/1(V0),a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(c[115,98]/1(a[97]),a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,99],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,100],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[115,101],a[116,114,117,101]),nil))))))))"
        ]
    ),
    (
        key="L2",
        label="L2: abolish_all_tables inside the evaluation flags the incomplete table, it is deleted on completion (TB5-L2)",
        program=_T5_PROG_L2,
        cases=[
            ("l201", raw"findall(X, l2p(X), L), R = L"),
            ("l202", raw"l2_has(l2p(_), R)"),
            ("l203", raw"findall(X, l2p(X), L), nb_getval(cntl2, C), R = L-C"),
            ("l204", raw"findall(X, l2q(X), L), l2_has(l2q(_), H), R = L-H"),
            ("l205", raw"findall(X, l2q(X), L), nb_getval(cntl2, C), R = L-C")
        ],
        pins=[
            "ok",
            "t_l201 c[116,95,108,50,48,49]/1(c[91,124,93]/2(i1,nil))",
            "t_l202 c[116,95,108,50,48,50]/1(a[97,98,115,101,110,116])",
            "t_l203 c[116,95,108,50,48,51]/1(c[45]/2(c[91,124,93]/2(i1,nil),i2))",
            "t_l204 c[116,95,108,50,48,52]/1(c[45]/2(c[91,124,93]/2(i1,nil),a[112,114,101,115,101,110,116]))",
            "t_l205 c[116,95,108,50,48,53]/1(c[45]/2(c[91,124,93]/2(i1,nil),i3))"
        ]
    )
]

# pinned from swipl, checked live, run on the kernel since ENG1 (see the header): delete_dynamic_table destroys the orphan's IDG node as swipl does
const _T5_GROUPS_ENG1 = [
    (
        key="A7",
        label="A7: abolishing an incremental table deletes the dynamic table it alone depended on (TB5-A7)",
        program=_T5_PROG_A7,
        cases=[
            ("a701", raw"findall(X, ap(X), L), R = L"),
            ("a702", raw"a7_names(R)"),
            ("a703", raw"abolish_table_subgoals(ad(_)), a7_names(R)"),
            ("a704", raw"abolish_table_subgoals(ap(_)), a7_names(R)")
        ],
        pins=[
            "ok",
            "t_a701 c[116,95,97,55,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
            "t_a702 c[116,95,97,55,48,50]/1(c[91,124,93]/2(a[97,100],c[91,124,93]/2(a[97,112],nil)))",
            "t_a703 c[116,95,97,55,48,51]/1(c[91,124,93]/2(a[97,100],c[91,124,93]/2(a[97,112],nil)))",
            "t_a704 c[116,95,97,55,48,52]/1(nil)"
        ]
    ),
    (
        key="O5",
        label="O5: 1100 dynamic tables that lost their dependent are swept at the completion of a root component (TB5-O5)",
        program=_T5_PROG_O5,
        cases=[
            ("o501", raw"o5_cyc(a, C), R = C"),
            ("o502", raw"assertz(off), o5_cyc(b, C), R = C"),
            ("o503", raw"retractall(off), o5_cyc(c, C), R = C"),
            ("o504", raw"assertz(off), o5_cyc(d, C), R = C")
        ],
        pins=[
            "ok",
            "t_o501 c[116,95,111,53,48,49]/1(i1103)",
            "t_o502 c[116,95,111,53,48,50]/1(i1104)",
            "t_o503 c[116,95,111,53,48,51]/1(i1105)",
            "t_o504 c[116,95,111,53,48,52]/1(i6)"
        ]
    )
]
"The groups the kernel run covers: ENG1's joined it when `delete_dynamic_table` could delete an orphan (src/pl-tabling.jl, `reset_answer_table_idg`)."
const _T5_GROUPS_RUN = vcat(_T5_GROUPS, _T5_GROUPS_ENG1)
const _T5_GROUPS_LIVE = vcat(_T5_GROUPS, _T5_GROUPS_ENG1)

# kills TB4-A3 (A3N: the answer completion counter is 0, the mutant calls it); A3P and A3Q pin the controls; S4A/S4B are the S4 regression pins,
# S4C kills TB4-S4 (s406: swipl reads the delay `sa(a)`, the break after pass 0 leaves none);
# L2 kills TB5-L2 (l202: no table is left, l203: evaluated twice)
@testset "TB5-ROWS simplification, answer completion and abolish as swipl's: $(g.label)" for g in
                                                                                             _T5_GROUPS_RUN

    gd, ld, st = _T5_load(g.program, g.cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _T5_ask(gd, ld, "t_$id"))
    end
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_T5_ask`
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for (k, p) in zip(kl, g.pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _T5_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end

_T5_group(key) = only(filter(g -> g.key == key, _T5_GROUPS_LIVE))
"The answer part of the pinned line of case `id` in group `key`."
function _T5_ans(key, id)
    g = _T5_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

@testset "the TB5-ROWS pins are not vacuous" begin
    for g in _T5_GROUPS_LIVE
        @test g.pins[1] == "ok"
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id"), g.pins) == 1
        end
    end
    # A3: zero calls with negative delays only, one with a positive element, zero without a simplification
    @test startswith(split(_T5_ans("A3N", "a301"), "(")[3], "i0,")
    @test startswith(split(_T5_ans("A3P", "a303"), "(")[3], "i1,")
    @test startswith(split(_T5_ans("A3Q", "a305"), "(")[3], "i0,")
    @test _T5_ans("A3N", "a301") != _T5_ans("A3P", "a303")         # the counter distinguishes the two programs
    @test _T5_atoms(_T5_ans("A3N", "a301")) == ["lp"] &&
        _T5_atoms(_T5_ans("A3P", "a303")) == ["lp"]
    # S4: the model sp false, sa true, sb false, se true, in both clause orders
    @test _T5_atoms(_T5_ans("S4A", "s402")) ==
        ["sp", "false", "sa", "true", "sb", "false", "se", "true"]
    @test _T5_ans("S4A", "s402")[(findfirst('(', _T5_ans("S4A", "s402"))):end] ==
        _T5_ans("S4B", "s404")[(findfirst('(', _T5_ans("S4B", "s404"))):end]
    @test _T5_atoms(_T5_ans("S4A", "s403")) == ["true"]
    @test !occursin("a[", split(_T5_group("S4A").pins[2], " ")[end])          # `sp` fails: the bare line
    # S4C: sa(_) keeps ONE conditional answer sa(a) (undefined), sb false, se true; the delay of s406 is `sa(a)` itself
    @test _T5_atoms(_T5_ans("S4C", "s406")) == ["a"]
    @test _T5_atoms(_T5_ans("S4C", "s407")) == ["a"]
    @test _T5_atoms(_T5_ans("S4C", "s408")) ==
        [
        "a",
        "undefined",
        "a",
        "undefined",
        "false",
        "a",
        "false",
        "sc",
        "false",
        "sd",
        "false",
        "se",
        "true"
    ]
    @test !endswith(_T5_ans("S4C", "s406"), "(nil)")           # not the empty delay list of the mutant
    # L2: the abolished incomplete table is gone and evaluated twice; the control keeps its table and is evaluated once
    @test _T5_atoms(_T5_ans("L2", "l202")) == ["absent"]
    @test _T5_atoms(_T5_ans("L2", "l204")) == ["present"]
    @test endswith(_T5_ans("L2", "l203"), ",i2))") &&
        endswith(_T5_ans("L2", "l205"), ",i3))")
    @test _T5_ans("L2", "l202") != _T5_ans("L2", "l204")
    # A7: the orphan goes with its dependent, stays while the dependent stays; O5: the sweep leaves 6 of the 1105 tables
    @test _T5_atoms(_T5_ans("A7", "a702")) == _T5_atoms(_T5_ans("A7", "a703")) ==
        ["ad", "ap"]
    @test endswith(_T5_ans("A7", "a704"), "(nil)")
    @test _T5_ans("O5", "o504") != _T5_ans("O5", "o503") &&
        endswith(_T5_ans("O5", "o504"), "(i6)")
    @test all(
        endswith(_T5_ans("O5", id), r"\(i1[0-9]{3}\)") for id in ("o501", "o502", "o503")
    )
    # ENG1: every pinned group runs on the kernel
    @test Set(g.key for g in _T5_GROUPS_RUN) == Set(g.key for g in _T5_GROUPS_LIVE)
end

@testset "the TB5-ROWS pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB5-ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        for g in _T5_GROUPS_LIVE
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _T5_GROUPS_LIVE
            f = joinpath(mktempdir(), "tb5rows_swipl.pl")
            write(f, _T5_text(g.program, g.cases))
            @test _T5_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end

# TB5-E10, TB5-E11 (tools/mutants/TB5.py): LK-only white-box; no swipl pin (the registry is the kernel's own bookkeeping, pl-idgset.jl
# idg_registry_new / idg_registry_add). UNVERIFIED on the kernel (nothing was compiled): the thread's registry is assumed to hold one
# reference per node plus the thread's own (idg_registry_new starts at 1, idg_registry_add adds 1), and `reset_table_bulk` is assumed not
# to delete nodes from the registry; with the correct code `reg.references == 0` holds either way, E10 (no release) leaves it at
# `length(nodes) + 1` and E11 (no node counted) leaves it at `length(nodes)`.
const _T5_WB = raw"""
t5_p(1).
t5_p(2).
t5_q(1).
:- '$set_predicate_attribute'(t5_p(_), tabled, true).
:- '$set_predicate_attribute'(t5_q(_), tabled, true).
"""

"The definition of `name/1` in the user module of `gd`."
function _T5_def(gd, name::String)
    proc = LK.isCurrentProcedure(sym_key(_T5_sym(name)), 1, LK.MODULE_user(gd))
    @assert proc !== nothing
    return proc.definition
end

"""
Three complete tables (`t5_p(1)`, `t5_p(_)`, `t5_q(1)`; a copy of `_ab_tables!` of test_tabling_abolish_swipl.jl): the answer tries, in that order.
"""
function _T5_tables!(gd, ld)
    tries = []
    for (name, ground) in (("t5_p", true), ("t5_p", false), ("t5_q", true))
        def = _T5_def(gd, name)
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_refs(ld, 2)
        arg = ground ? lk_gnd(_T5_T, 1) : mk_var(_T5_T, LK.fresh_var_keys!(1))
        v = mk_expr(
            _T5_T,
            _T5_T[_T5_sym(":"), _T5_sym("user"), mk_expr(_T5_T, _T5_T[_T5_sym(name), arg])]
        )
        LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
        atrie = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
        @assert atrie !== nothing
        atrie.flags |= LK.TRIE_COMPLETE
        push!(tries, atrie)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return tries
end

@testset "clear_variant_table releases the IDG registry: no reference is left (TB5-E10, TB5-E11)" begin
    gd, ld, st = _T5_load(_T5_WB, [("w01", raw"R = ok")])
    @test st == "ok"
    atries = _T5_tables!(gd, ld)
    nodes = [LK.idg_new(ld, a) for a in atries]
    @test all(n -> n !== nothing, nodes)
    for (a, n) in zip(atries, nodes)
        a.IDG = n
    end
    reg = ld.tabling.idg_registry
    @test reg !== nothing && all(n -> n.registry === reg, nodes)
    @test reg.references >= length(nodes) + 1                  # the premise: one per node and the thread's own
    @test LK.clear_variant_table(ld) === nothing
    @test ld.tabling.idg_registry === nothing                  # detached before the resets
    @test reg.references == 0                                  # TB5-E10 leaves length(nodes) + 1, TB5-E11 leaves length(nodes)
end

# TB5-H4 (tools/mutants/TB5.py): LK-only white-box; no swipl pin and no Prolog route ('$tbl_abolish_local_tables' runs only when no evaluation is
# active, and `LD->tabling.component` is then empty), so the state is built by hand: a component of the thread with a scheduled worklist set (empty:
# `reset_global_worklist` frees the SET, pl-tabling.c:873-881). With the correct code the component keeps no worklist set after the clear; TB5-H4
# (the call dropped) leaves `c.worklist === wls`. UNVERIFIED on the kernel (nothing was compiled).
@testset "clearThreadTablingData resets the global worklist of the thread's component (TB5-H4)" begin
    gd, ld, st = _T5_load(_T5_WB, [("w01", raw"R = ok")])
    @test st == "ok"
    c = LK.tbl_component{_T5_T}()
    wls = LK.worklist_set{LK.tbl_worklist{_T5_T}}()
    c.worklist = wls
    ld.tabling.component = c
    @test c.worklist === wls                                   # the premise: the component holds its worklist set
    @test LK.clearThreadTablingData(ld, false) === nothing
    @test c.worklist === nothing                               # TB5-H4 leaves the set
    ld.tabling.component = nothing
end
