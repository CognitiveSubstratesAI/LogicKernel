# ORIGINAL: an ENGINE FINDING recorded as a NAMED ROW, EXPECTED-FAILING (audit D-0659 item 3, D-0660 item 4): no swipl-devel counterpart.
# COPY ON THIS BRANCH (wip/tab-int) ONLY: DROP THIS FILE'S COMMIT BEFORE ANY GATE PUSH; it has no owner row yet. Owner row pending: engine-core slot after AR1.
# The finding (found by the TB4FIX-B reduction, evidence/TAB1/b4fix_handoff.md): an exception raised out of the CLEANUP goal of a `call_cleanup/2` that is the
# cleanup of `'$tabling':answer_completion/2`, itself called from C (`call_answer_completion`, src/pl-tabling.jl), breaks the engine
# (`AssertionError: newChoice: BFR is not older`, src/pl-wam.jl, from C_OR; `tabling(unexpected_result(...))`). swipl raises the exception to the caller as any other.
# The reduction there threw an existence_error from `abolish_table_subgoals/1`, the cleanup of boot/tabling.pl `answer_completion/2`
# (call_cleanup(answer_completion_guarded(...), abolish_table_subgoals(eval_subgoal_in_residual(_,_)))), because the tree had no `'$tbl_destroy_table'/1`.
# THIS reproducer needs no missing builtin: `wrap_predicate('$tabling':abolish_table_subgoals(_), ..., throw(error(ef_cleanup_thrown, _)))` makes THAT cleanup
# goal throw. The program is the 6-predicate positive loop of the reduction (every smaller subset of its six clauses never reaches answer completion on swipl:
# python3 over the 63 subsets, 10.1.20), called as `re`; `rf` is asked after it.
#   * group EF0, the CONTROL, the same program without the wrap: swipl `re` -> no, `rf` -> yes. It must PASS on the kernel (answer completion runs, nothing throws).
#   * group EF1, the FINDING, with the throwing wrap: swipl answers `raised(ef_cleanup_thrown)` for BOTH goals (10.1.20, two byte-identical runs; the driver of
#     test_tabling_tb4_tb5_swipl.jl, `t_<id>(R) :- catch(Goal, error(SsuE, _), R = raised(SsuE))`).
# CONVENTION: the repo's known-difference rows pin the kernel's CURRENT answer with swipl's in a comment (docs/architecture.md "KNOWN DIFFERENCE"). That cannot be
# done here: the kernel's current behaviour is a Julia exception (an AssertionError) that never becomes an answer line, and nothing could be run when this was
# written. So the row asserts SWIPL's pin (`@test kl == g.pins`, no @test_skip, no @test_broken) and FAILS today for the real reason: on a failure the kernel's
# first line is printed ("ours" is `julia exception: ...` or the answer). The lane's first run reads that line: (a) `julia exception: AssertionError ... BFR is not
# older` = the finding; (b) `t_ef01 ...a[110,111]` (= the control's `no`) = the wrap did not take on a `$tabling` predicate (then the row proves nothing: rebuild it
# on `answer_completion` itself); (c) swipl's pin = the finding is gone and the row is a plain row. Then this header says so.
# On origin/main the same Prolog text is vendored (vendor/swipl-devel/boot/tabling.pl:2252-2260), but the C side (`call_answer_completion`, `$tbl_wkl_work`) is only on
# the tabling branches: the finding cannot arise on main.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EF_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_EF_sym(x) = lk_sym(_EF_T, Symbol(x))

_EF_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _EF_enc(t::_EF_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _EF_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _EF_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _EF_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_EF_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _EF_DRIVER = raw"""
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

function _EF_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _EF_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_EF_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _EF_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_ef_cleanup.pl")
    write(f, _EF_text(program, cases))
    gd = LK.PL_global_data{_EF_T}()
    ld = LK.PL_local_data{_EF_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _EF_enc(ball::_EF_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _EF_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_EF_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_EF_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _EF_enc(mk_expr(_EF_T, _EF_T[_EF_sym(pred), lk_answers(ld, (a:a)...)...]))
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

const _EF_BODY = raw"""
:- table ra/0, rb/0, rc/0, rd/0, re/0, rf/0.
ra :- rf.
rc :- rd, rc.
rd :- re.
re :- tnot(ra).
re :- rd.
rf :- tnot(rc).
"""
const _EF_HEAD = raw"""
:- use_module(library(wfs)).
"""
const _EF_WRAP = raw"""
:- use_module(library(prolog_wrap)).
:- wrap_predicate('$tabling':abolish_table_subgoals(_), thr_ef, _W, throw(error(ef_cleanup_thrown, _))).
"""

const _EF_CASES = [
    ("ef01", raw"( re -> R = yes ; R = no )"),
    ("ef02", raw"( rf -> R = yes ; R = no )")
]

const _EF_PINS_CTL = [
    "ok",
    "t_ef01 c[116,95,101,102,48,49]/1(a[110,111])",
    "t_ef02 c[116,95,101,102,48,50]/1(a[121,101,115])"
]

const _EF_PINS_THR = [
    "ok",
    "t_ef01 c[116,95,101,102,48,49]/1(c[114,97,105,115,101,100]/1(a[101,102,95,99,108,101,97,110,117,112,95,116,104,114,111,119,110]))",
    "t_ef02 c[116,95,101,102,48,50]/1(c[114,97,105,115,101,100]/1(a[101,102,95,99,108,101,97,110,117,112,95,116,104,114,111,119,110]))"
]

const _EF_GROUPS = [
    (
        key="EF0",
        label="control: the 6-predicate loop without the throwing wrap, answers as swipl's",
        program=_EF_HEAD * _EF_BODY,
        pins=_EF_PINS_CTL
    ),
    (
        key="EF1",
        label="ENGINE FINDING (EXPECTED-FAILING until the engine-core fix; owner row pending: engine-core slot after AR1): an exception out of the cleanup goal of answer_completion/2",
        program=_EF_HEAD * _EF_WRAP * _EF_BODY,
        pins=_EF_PINS_THR
    )
]

"The driver lines of one group on the kernel; a Julia exception becomes ONE line `julia exception: <first line>` (it is the finding)."
function _EF_run(g)::Vector{String}
    try
        gd, ld, st = _EF_load(g.program, _EF_CASES)
        kl = String[st]
        for (id, _) in _EF_CASES
            push!(kl, _EF_ask(gd, ld, "t_$id"))
        end
        return kl
    catch e
        return ["julia exception: " * first(split(sprint(showerror, e), '\n'))]
    end
end

@testset "the pins are non-empty and shaped like the driver's lines" begin
    for g in _EF_GROUPS
        @test !isempty(g.pins) && g.pins[1] == "ok"
        @test length(g.pins) == length(_EF_CASES) + 1
        @test [first(split(l, " ")) for l in g.pins[2:end]] ==
            ["t_$id" for (id, _) in _EF_CASES]
        @test all(
            l -> length(split(l, " "; limit=2)) == 2 && !isempty(split(l, " "; limit=2)[2]),
            g.pins[2:end]
        )
    end
    @test _EF_GROUPS[1].pins != _EF_GROUPS[2].pins            # the control and the finding differ
end

@testset "$(g.label)" for g in _EF_GROUPS
    kl = _EF_run(g)
    for (k, p) in zip(kl, g.pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
    end
    @test kl == g.pins
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ENGINE FINDING ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        for g in _EF_GROUPS
            f = joinpath(mktempdir(), "ef_swipl.pl")
            write(f, _EF_text(g.program, _EF_CASES))
            @test _EF_swipl_lines(f, ["t_$id" for (id, _) in _EF_CASES]) == g.pins
        end
    end
end
