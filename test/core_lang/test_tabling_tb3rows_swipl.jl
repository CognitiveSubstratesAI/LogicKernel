# ORIGINAL: kill rows for TB3-U2 and TB3-F7 of tools/mutants/TB3.py against swipl at the pin (swipl-devel 18168e62, 10.1.20); STEP TAB1 F7 (audit D-0906 (2)).
#   * Group U2 (pl-tabling.c update_delay_list :1786-1791 `return wl->ground ? UDL_COMPLETE : UDL_TRUE`, tbl_add_answer_found :5124-5132 `complete = true`,
#     tbl_reset_add_answer :5225 `rcadd == TBL_ANSWER_COMPLETE` (line numbers of the checkout read; the DEBUG(TABLING_NO_EARLY_COMPLETION) switch at :1788 is swipl's own knob for this),
#     boot/tabling.pl delim/4 :680-696: '$tbl_reset'/6 "fails after adding an answer, after pruning the choice points of Worker if the answer completes
#     the table"). The early completion of a GROUND tabled call only prunes the worker's remaining clauses and solutions; no answer differs (a ground
#     variant has at most one answer), but a SIDE EFFECT of a pruned clause is observable. The program counts `assertz` side effects in `ux_seen/1`.
#     swipl 10.1.20 decides every count below (two byte-identical runs, nothing assumed):
#       u01/u02  ug1(1): `ug1(1). ug1(1) :- assertz(ux_seen(g1)).`  count g1 = 0: the second clause is pruned after the first answer (the second call
#                reads the complete table, still 0);
#       u03      ug2(1): the side-effect clause FIRST, `ug2(1) :- assertz(ux_seen(g2)). ug2(1).`  count g2 = 1: it runs before any answer exists (control);
#       u04      ug3(1): two clauses, each with its own side effect: only the first runs (1-0);
#       u05      the NON-ground contrast, `ut(X)` with `ut(1). ut(1) :- assertz(ux_seen(t)).`: the answer 1 is the same, the side effect RUNS (count 1,
#                no early completion: update_delay_list answers UDL_TRUE for a call with a variable);
#       u06      uh(1) :- between(1, 3, _), assertz(...): ONE solution of the clause is run, count 1 (the other two are pruned);
#       u07      uhn(X) :- X = 1, between(1, 3, _), assertz(...): the non-ground control, all three solutions run, count 3.
#     Kills: TB3-U2 (`return UDL_TRUE`: u01 count 1, u04 1-1, u06 count 3) and TB3-F7 (`complete = false`: the same three rows; the leader reads
#     TBL_ANSWER_COMPLETE in tbl_reset_add_answer, src/pl-tabling.jl:1791). TB3-W1 is NOT killed here: the `!` of `'$tbl_wkl_add_answer'/4` is read by the
#     debug-mode delim/4 only (boot/tabling.pl :680-696 under `prolog_debug`), the route of these rows is '$tbl_reset'/6.
#   * Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; a case that fails is the bare
#     `t_<id>` line. Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs; evidence/TAB1/f7_handoff.md); with `swipl` on PATH
#     the live answers are compared with the pins too.
#   * UNRUN on the kernel (edit-only step, nothing compiled): every kernel answer; the lane run decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T3R_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_T3R_sym(x) = lk_sym(_T3R_T, Symbol(x))

_T3R_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _T3R_enc(t::_T3R_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _T3R_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _T3R_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _T3R_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_T3R_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _T3R_DRIVER = raw"""
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

function _T3R_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _T3R_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_T3R_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _T3R_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb3rows.pl")
    write(f, _T3R_text(program, cases))
    gd = LK.PL_global_data{_T3R_T}()
    ld = LK.PL_local_data{_T3R_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _T3R_enc(ball::_T3R_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _T3R_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_T3R_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T3R_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _T3R_enc(
                    mk_expr(_T3R_T, _T3R_T[_T3R_sym(pred), lk_answers(ld, (a:a)...)...])
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


const _T3R_PROG_U2 = raw"""
:- dynamic ux_seen/1.
:- table ug1/1, ug2/1, ug3/1, ut/1, uh/1, uhn/1.
ug1(1).
ug1(1) :- assertz(ux_seen(g1)).
ug2(1) :- assertz(ux_seen(g2)).
ug2(1).
ug3(1) :- assertz(ux_seen(g3a)).
ug3(1) :- assertz(ux_seen(g3b)).
ut(1).
ut(1) :- assertz(ux_seen(t)).
uh(1) :- between(1, 3, _), assertz(ux_seen(h)).
uhn(X) :- X = 1, between(1, 3, _), assertz(ux_seen(hn)).
ux_n(Tag, N) :- aggregate_all(count, ux_seen(Tag), N).
"""

const _T3R_GROUPS = [
    (
        key="U2",
        label="U2: ground tabled calls complete early after the first answer, a side effect of a later clause is not run (TB3-U2, TB3-F7)",
        program=_T3R_PROG_U2,
        cases=[
            ("u01", raw"ug1(1), ux_n(g1, N), R = N"),
            ("u02", raw"ug1(1), ux_n(g1, N), R = N"),
            ("u03", raw"ug2(1), ux_n(g2, N), R = N"),
            ("u04", raw"ug3(1), ux_n(g3a, A), ux_n(g3b, B), R = A-B"),
            ("u05", raw"findall(X, ut(X), L), ux_n(t, N), R = L-N"),
            ("u06", raw"uh(1), ux_n(h, N), R = N"),
            ("u07", raw"findall(X, uhn(X), L), ux_n(hn, N), R = L-N")
        ],
        pins=[
            "ok",
            "t_u01 c[116,95,117,48,49]/1(i0)",
            "t_u02 c[116,95,117,48,50]/1(i0)",
            "t_u03 c[116,95,117,48,51]/1(i1)",
            "t_u04 c[116,95,117,48,52]/1(c[45]/2(i1,i0))",
            "t_u05 c[116,95,117,48,53]/1(c[45]/2(c[91,124,93]/2(i1,nil),i1))",
            "t_u06 c[116,95,117,48,54]/1(i1)",
            "t_u07 c[116,95,117,48,55]/1(c[45]/2(c[91,124,93]/2(i1,nil),i3))"
        ]
    )
]

# kills TB3-U2 and TB3-F7 (u01, u04, u06); u02, u03, u05, u07 pin the controls
@testset "TB3-ROWS as swipl's: $(g.label)" for g in _T3R_GROUPS
    gd, ld, st = _T3R_load(g.program, g.cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _T3R_ask(gd, ld, "t_$id"))
    end
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_T3R_ask`
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for (k, p) in zip(kl, g.pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

"The answer part of the pinned line of case `id` in group U2."
function _T3R_ans(id)
    g = only(_T3R_GROUPS)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

@testset "the TB3-ROWS pins are not vacuous" begin
    g = only(_T3R_GROUPS)
    @test g.pins[1] == "ok"
    @test all(!isempty, g.pins)
    for (id, goal) in g.cases
        @test !isempty(goal)
        @test count(l -> startswith(l, "t_$id "), g.pins) == 1
    end
    # a ground call is cut after its first answer: the later clause's side effect is not run (0), a solution-producing clause runs once (1);
    # the mutants TB3-U2 / TB3-F7 run the pruned clauses (1, and 3 for the three solutions of `between/3`)
    @test endswith(_T3R_ans("u01"), "(i0)") && endswith(_T3R_ans("u02"), "(i0)")
    @test endswith(_T3R_ans("u04"), "(c[45]/2(i1,i0))")
    @test endswith(_T3R_ans("u06"), "(i1)")
    # the controls: the side effect FIRST runs; a non-ground call runs every clause and solution
    @test endswith(_T3R_ans("u03"), "(i1)")
    @test endswith(_T3R_ans("u05"), "(c[45]/2(c[91,124,93]/2(i1,nil),i1))")
    @test endswith(_T3R_ans("u07"), "(c[45]/2(c[91,124,93]/2(i1,nil),i3))")
    @test _T3R_ans("u01") != _T3R_ans("u03")                  # the ground call and the side-effect-first control differ
    @test _T3R_ans("u06") != _T3R_ans("u07")                  # the same body, ground vs non-ground: 1 vs 3 side effects
end

@testset "the TB3-ROWS pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    g = only(_T3R_GROUPS)
    if swipl === nothing
        @info "TB3-ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test g.pins[1] == "ok"
        @test [first(split(l, " ")) for l in g.pins[2:end]] ==
            ["t_$id" for (id, _) in g.cases]
    else
        f = joinpath(mktempdir(), "tb3rows_swipl.pl")
        write(f, _T3R_text(g.program, g.cases))
        @test _T3R_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
    end
end
