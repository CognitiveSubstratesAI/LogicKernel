# ORIGINAL: the UPSTREAM tests/tabling/test_drop_intermediate.pl (swipl-devel 18168e62, 10.1.20) as kernel rows (TAB1 TB8: the flag
# `table_drop_intermediate`, `droppable_table`, `drop_intermediate_tables` of pl-tabling.c, replaced at the stack on wip/tb8m). One row
# `t_<id>(R)` per upstream unit (off, chain, recompute, reused): the body with the unit's option folded into R (`N == 301`, `true(N < 150)`,
# no option); `assertion/1` is defined in the program prelude as `\+ \+ G`.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, evidence/TAB1/w1_verify.md) AND equals the answer the upstream
#     unit expects (`_TD_UPSTREAM`): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_drop_intermediate` is `user` (`current_table(user:V, _)`); plunit is not used.
#   * Nothing is left to another owner: all 4 units run on the kernel.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TD = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tds(x) = lk_sym(_TD, Symbol(x))

_td_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _td_enc(t::_TD, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _td_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _td_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _td_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_td_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TD_DRIVER = raw"""
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

function _td_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TD_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TD_PROGRAM = raw"""
assertion(G) :- ( \+ \+ G -> true ; throw(assertion_failed) ).

:- use_module(library(lists)).
:- use_module(library(aggregate)).
:- table nrev/2, fib/2.
nrev([], []).
nrev([H|T], R) :-
    nrev(T, RT),
    append(RT, [H], R).
fib(0, 0).
fib(1, 1).
fib(N, F) :-
    N > 1,
    N1 is N-1,
    N2 is N-2,
    fib(N1, F1),
    fib(N2, F2),
    F is F1+F2.
with_drop(F, G) :-
    current_prolog_flag(table_drop_intermediate, Old),
    setup_call_cleanup(
        set_prolog_flag(table_drop_intermediate, F),
        G,
        set_prolog_flag(table_drop_intermediate, Old)).
tables(Name, N) :-
    aggregate_all(count,
                  ( current_table(user:V, _),
                    functor(V, Name, _)
                  ), N).
"""

const _TD_LEFT_PROGRAM = ""

const _TD_CASES = [
    (
        "di01",
        "drop_intermediate:off",
        raw"""
abolish_all_tables, numlist(1, 300, L), nrev(L, Rev), assertion(reverse(L, Rev)), tables(nrev, N), R = N"""
    ),
    (
        "di02",
        "drop_intermediate:chain",
        raw"""
abolish_all_tables, numlist(1, 300, L), with_drop(10, nrev(L, R0)), assertion(reverse(L, R0)), tables(nrev, N), assertion(N > 1), assertion(current_table(user:nrev(L, _), _)), ( N < 150 -> R = ok ; R = bad(N) )"""
    ),
    (
        "di03",
        "drop_intermediate:recompute",
        raw"""
abolish_all_tables, numlist(1, 300, L), with_drop(10, nrev(L, _)), forall(between(1, 300, I), ( numlist(I, 300, S), nrev(S, R0), assertion(reverse(S, R0)) )), R = ok"""
    ),
    (
        "di04",
        "drop_intermediate:reused",
        raw"""
abolish_all_tables, with_drop(10, fib(200, F)), assertion(F =:= 280571172992510140037611932413038677189525), tables(fib, N), R = N"""
    )
]

const _TD_LEFT = Tuple{String, String, String, String}[]

const _TD_PINNED = [
    "ok",
    "t_di01 c[116,95,100,105,48,49]/1(i301)",
    "t_di02 c[116,95,100,105,48,50]/1(a[111,107])",
    "t_di03 c[116,95,100,105,48,51]/1(a[111,107])",
    "t_di04 c[116,95,100,105,48,52]/1(i201)"
]

"The answer the UPSTREAM test expects, run in swipl (`x_<id>(R) :- R = Expected`), as the driver encodes it."
const _TD_UPSTREAM = [
    "i301",
    "a[111,107]",
    "a[111,107]",
    "i201"
]

const _TD_LEFT_PINNED = String[]

const _TD_LEFT_UPSTREAM = String[]

"The program text with the cases appended."
_td_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _td_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _td_text(program, [(id, g) for (id, _, g) in _TD_CASES]))
    gd = LK.PL_global_data{_TD}()
    ld = LK.PL_local_data{_TD}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _td_enc(ball::_TD))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _td_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tds(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TD, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _td_enc(mk_expr(_TD, _TD[_tds(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TD_UPSTREAM` holds it."
function _td_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_td_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_drop_intermediate.pl: the tables of the intermediate components that are dropped" begin
    gd, ld, st = _td_load(_TD_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TD_CASES
        push!(kl, _td_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TD_PINNED)
    for (k, pn) in zip(kl, _TD_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _td_corrupt(_TD_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_TD_PINNED) == length(_TD_CASES) + 1
    @test length(_TD_UPSTREAM) == length(_TD_CASES)
    @test !isempty(_TD_UPSTREAM) && all(!isempty, _TD_UPSTREAM)
    for (pn, up) in zip(_TD_PINNED[2:end], _TD_UPSTREAM)
        @test _td_answer(pn) == up
    end
    @test length(_TD_LEFT_PINNED) == length(_TD_LEFT) == length(_TD_LEFT_UPSTREAM)
    for (pn, up) in zip(_TD_LEFT_PINNED, _TD_LEFT_UPSTREAM)
        @test _td_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _td_answer(_td_corrupt(_TD_PINNED[2])) != _TD_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat(
            [(id, g) for (id, _, g) in _TD_CASES], [(id, g) for (id, _, g, _) in _TD_LEFT]
        )
        write(f, _td_text(_TD_PROGRAM * _TD_LEFT_PROGRAM, all_cases))
        got = _td_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_TD_PINNED, _TD_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _td_corrupt(_TD_PINNED[2])
    end
end
