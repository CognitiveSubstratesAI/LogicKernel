# ORIGINAL: the UPSTREAM tests/tabling/test_table_statistics.pl (swipl-devel 18168e62, 10.1.20) as kernel rows (TAB1 TB8: library(tableutil)
# `table_statistics/2,3` over the variant table, incremental tables and the dependency nodes of an incremental dynamic predicate).
# One row `t_<id>(R)` per upstream unit (dependency_nodes, answer_tables,
# plain_answers, no_tables): the body with the unit's options folded into R; `assertion/1` is defined in the program prelude.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, evidence/TAB1/w1_verify.md) AND equals the answer the upstream
#     unit expects (`_TS_UPSTREAM`): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_table_statistics` is `user`; plunit is not used (the options `Keys == ...`, `Nodes == 4`,
#     `true(Space > 0)` are folded into one `r(Keys, Nodes, positive)`).
#   * Nothing is left to another owner: all 4 units run on the kernel (they need library(tableutil) and the IDG of TB6).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tss(x) = lk_sym(_TS, Symbol(x))

_ts_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ts_enc(t::_TS, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ts_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ts_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ts_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ts_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TS_DRIVER = raw"""
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

function _ts_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TS_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TS_PROGRAM = raw"""
assertion(G) :- ( \+ \+ G -> true ; throw(assertion_failed) ).

:- use_module(library(tableutil)).
:- use_module(library(pairs), [pairs_keys/2]).
:- dynamic([ts_data/1], [incremental(true)]).
:- table ts_inc/1 as incremental.
:- table ts_plain/1.
ts_data(1).
ts_data(2).
ts_inc(X) :- ts_data(X).
ts_plain(X) :- between(1, 3, X).
fill :-
    abolish_all_tables,
    forall(ts_inc(_), true),
    forall(between(1, 3, I), ignore(ts_inc(I))),
    forall(ts_plain(_), true).
stats(Variant, Pairs) :-
    findall(K-V, table_statistics(Variant, K, V), Pairs0),
    msort(Pairs0, Pairs).
"""

const _TS_LEFT_PROGRAM = ""

const _TS_CASES = [
    ("ts01", "table_statistics:dependency_nodes", raw"""
fill, stats(user:ts_data(_), Pairs), pairs_keys(Pairs, Keys), memberchk(dependency_nodes-Nodes, Pairs), memberchk(dependency_space-Space, Pairs), ( Space > 0 -> Pos = positive ; Pos = other ), R = r(Keys, Nodes, Pos)"""),
    ("ts02", "table_statistics:answer_tables", raw"""
fill, stats(user:ts_inc(_), Pairs), memberchk(tables-Tables, Pairs), memberchk(answers-Answers, Pairs), ( \+ memberchk(dependency_nodes-_, Pairs) -> NoDep = no_dependency_nodes ; NoDep = has_dependency_nodes ), R = r(Tables-Answers, NoDep)"""),
    ("ts03", "table_statistics:plain_answers", raw"""
fill, table_statistics(user:ts_plain(_), answers, Answers), R = Answers"""),
    ("ts04", "table_statistics:no_tables", raw"""
abolish_all_tables, table_statistics(user:ts_plain(_), tables, Tables), R = Tables"""),
]

const _TS_LEFT = Tuple{String, String, String, String}[]

const _TS_PINNED = [
    "ok",
    "t_ts01 c[116,95,116,115,48,49]/1(c[114]/3(c[91,124,93]/2(a[100,101,112,101,110,100,101,110,99,121,95,110,111,100,101,115],c[91,124,93]/2(a[100,101,112,101,110,100,101,110,99,121,95,115,112,97,99,101],nil)),i4,a[112,111,115,105,116,105,118,101]))",
    "t_ts02 c[116,95,116,115,48,50]/1(c[114]/2(c[45]/2(i4,i4),a[110,111,95,100,101,112,101,110,100,101,110,99,121,95,110,111,100,101,115]))",
    "t_ts03 c[116,95,116,115,48,51]/1(i3)",
    "t_ts04 c[116,95,116,115,48,52]/1(i0)",
]

"The answer the UPSTREAM test expects, run in swipl (`x_<id>(R) :- R = Expected`), as the driver encodes it."
const _TS_UPSTREAM = [
    "c[114]/3(c[91,124,93]/2(a[100,101,112,101,110,100,101,110,99,121,95,110,111,100,101,115],c[91,124,93]/2(a[100,101,112,101,110,100,101,110,99,121,95,115,112,97,99,101],nil)),i4,a[112,111,115,105,116,105,118,101])",
    "c[114]/2(c[45]/2(i4,i4),a[110,111,95,100,101,112,101,110,100,101,110,99,121,95,110,111,100,101,115])",
    "i3",
    "i0",
]

const _TS_LEFT_PINNED = String[]

const _TS_LEFT_UPSTREAM = String[]

"The program text with the cases appended."
_ts_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n" for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ts_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _ts_text(program, [(id, g) for (id, _, g) in _TS_CASES]))
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ts_enc(ball::_TS))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _ts_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tss(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TS, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _ts_enc(mk_expr(_TS, _TS[_tss(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TS_UPSTREAM` holds it."
function _ts_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_ts_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_table_statistics.pl: table_statistics/3 on the variant table" begin
    gd, ld, st = _ts_load(_TS_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TS_CASES
        push!(kl, _ts_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TS_PINNED)
    for (k, pn) in zip(kl, _TS_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _ts_corrupt(_TS_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_TS_PINNED) == length(_TS_CASES) + 1
    @test length(_TS_UPSTREAM) == length(_TS_CASES)
    @test !isempty(_TS_UPSTREAM) && all(!isempty, _TS_UPSTREAM)
    for (pn, up) in zip(_TS_PINNED[2:end], _TS_UPSTREAM)
        @test _ts_answer(pn) == up
    end
    @test length(_TS_LEFT_PINNED) == length(_TS_LEFT) == length(_TS_LEFT_UPSTREAM)
    for (pn, up) in zip(_TS_LEFT_PINNED, _TS_LEFT_UPSTREAM)
        @test _ts_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _ts_answer(_ts_corrupt(_TS_PINNED[2])) != _TS_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat([(id, g) for (id, _, g) in _TS_CASES], [(id, g) for (id, _, g, _) in _TS_LEFT])
        write(f, _ts_text(_TS_PROGRAM * _TS_LEFT_PROGRAM, all_cases))
        got = _ts_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_TS_PINNED, _TS_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _ts_corrupt(_TS_PINNED[2])
    end
end
