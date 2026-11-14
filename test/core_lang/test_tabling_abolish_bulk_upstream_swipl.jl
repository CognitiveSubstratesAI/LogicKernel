# ORIGINAL: the UPSTREAM tests/tabling/test_abolish_bulk.pl (swipl-devel 18168e62, 10.1.20), unit abolish_bulk (8 tests), as
# kernel rows (TAB1, TABTEST-AB). One row `t_bk<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E). Bulk release of private tables (abolish_private_tables/0, abolish_all_tables/0, thread exit): shared tables, conditional answers, monotonic
# tables and the IDG registry stay consistent afterwards.
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * Layout as plunit's: the module of the file, `test_abolish_bulk` (the file's text between its run_tests clause and begin_tests: the dynamic predicates and tables of the private-over-shared, conditional, monotonic and incremental examples with their update helpers, plus `threads/0`; the unit holds only the tests and `space/0`, `agc_settled/3`),
#     and the unit as its own module `plunit_abolish_bulk` with `:- set_module(base(test_abolish_bulk))` (plunit's default import module of a unit; the
#     test text between `begin_tests` and `end_tests` verbatim). The unit loads with `catch(use_module(..), _, true)`, so a unit the kernel
#     refuses leaves only ITS rows undefined (the pin loads it, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/2 clause directly). The options are folded by hand: the options `[S1,P1,S2,P2] == [..]`, `Count == 0`, `[Status,L] == [..]`, `L1-L2 == ..`, `L == [..]` are called after the body; registry's
#     `true(N1 > 1000), N2-E2 == 0-0, true(N3 > 1000)` and space's `true(After*10 < Before)` likewise (the row binds the option list to
#     `[true(C1), C2, true(C3)]` / `[condition(threads), true(C)]`). The unit option `cleanup(abolish_all_tables)` is the driver's abolish_all_tables
#     after the row. The four `condition(threads)` options are NOT folded: the body runs, so a kernel without threads shows the refusal.
#   * THREAD-BOUND: private_over_shared, shared_edges_removed, thread_exit, space (`condition(threads)`; shared tables and threads) are pinned
#     on swipl in their own testset "thread-bound: expected refusal on the kernel": a kernel line that differs from the pin is recorded as
#     @test_broken (visible in the summary), one that equals it passes.
#   * Expected refusals on the kernel (by reading, unverified): `:- table ss/1 as (shared, incremental)` (shared tables; thread-bound rows), `abolish_private_tables/0`, `thread_create/2`,
#     `thread_join/2`, `'$idg_edge'/3`, `'$idg_thread_summary'/3`, `statistics(table_space_used, _)`, `garbage_collect_atoms/0`, `table (..) as monotonic`,
#     `tnot/1` loops. The parent module is loaded with use_module/1 without catch: a refusal of the `shared` table declaration there may leave
#     every row of this file undefined, so then move ss/1 and the four thread-bound rows into their own module, never weaken a pin. Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_bk.txt, which also holds the plunit
#     run: 8 of 8 tests passed, none failed or hung on the pin) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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
    ("abolish_bulk", "begin_tests(abolish_bulk)", raw"""
test(private_over_shared, [ condition(threads),
                            [S1,P1,S2,P2] == [[1,2],[1,2],[1,2],[1,2]]
                          ]) :-
    abolish_and_query(S1, P1),
    abolish_and_query(S2, P2).
test(shared_edges_removed, [condition(threads), Count == 0]) :-
    set_sd([1]),
    findall(X, ps(X), _),
    abolish_private_tables,
    shared_affected(Count).
test(thread_exit, [ condition(threads),
                    [Status,L] == [true, [1,2,3]]
                  ]) :-
    set_sd([1,2]),
    thread_create(findall(X, ps(X), _), Id),
    thread_join(Id, Status),
    add_sd(3),
    findall(X, ss(X), L0), msort(L0, L).
test(conditional, [L1-L2 == [cv(1),cv(2)]-[cv(1),cv(2)]]) :-
    abolish_all_tables,
    findall(cv(X), cv(X), L10), msort(L10, L1),
    abolish_all_tables,
    findall(cv(X), cv(X), L20), msort(L20, L2),
    abolish_all_tables.
test(monotonic, [L1-L2 == [1,2]-[1,2,3]]) :-
    set_md([1]),
    abolish_all_tables,
    findall(X, mq(X), _),
    add_md(2),
    findall(X, mq(X), L10), msort(L10, L1),
    abolish_all_tables,
    findall(X, mq(X), _),
    add_md(3),
    findall(X, mq(X), L20), msort(L20, L2),
    abolish_all_tables,
    set_md([]).
test(registry, [ true(N1 > 1000),
                 N2-E2 == 0-0,
                 true(N3 > 1000)
               ]) :-
    thread_self(Me),
    fill(1000),
    '$idg_thread_summary'(Me, N1, _),
    abolish_all_tables,
    '$idg_thread_summary'(Me, N2, E2),
    fq(1000),
    '$idg_thread_summary'(Me, N3, _),
    abolish_all_tables.
test(update_after_abolish, [L == [fp(1),fp(2)]]) :-
    fill(10),
    abolish_all_tables,
    findall(fp(I), (between(1,2,I), fp(I)), _),
    add_fd(2),
    findall(fp(I), (between(1,2,I), fp(I)), L),
    del_fd(2).
test(space, [condition(threads), true(After*10 < Before)]) :-
    thread_create(space, Id),
    thread_join(Id, exited(Before-After)).

space :-
    fill(1000),
    statistics(table_space_used, Before),
    abolish_all_tables,
    agc_settled(Before, 100, After),
    thread_exit(Before-After).

%   agc_settled(+Before, +N, -After)
%
%   Atom-GC frees the answer tries.  Wait at most N tenths of a second
%   until it did.

agc_settled(Before, N, After) :-
    garbage_collect_atoms,
    statistics(table_space_used, Used),
    (   ( Used*10 < Before ; N == 0 )
    ->  After = Used
    ;   sleep(0.1),
        N2 is N-1,
        agc_settled(Before, N2, After)
    ).
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
threads :-
    current_prolog_flag(threads, true).

%   A private incremental table over a shared incremental table.  The
%   IDG node of ps/1 has a shared child.

:- dynamic sd/1 as incremental.
:- table ss/1 as (shared, incremental).
:- table ps/1 as incremental.

sd(1).

ss(X) :- sd(X).
ps(X) :- ss(X).

%   The updates are in this module: assert/1 in a test adds to the
%   module of the unit.

set_sd(L) :-
    retractall(sd(_)),
    forall(member(X, L), assertz(sd(X))).
add_sd(X) :-
    assertz(sd(X)).

%   Conditional answers that delay on other tables

:- table cu/1, cw/0, cv/1.

cu(X) :- member(X, [1,2]), tnot(cw).
cw :- tnot(cw).
cv(X) :- cu(X).

%   Monotonic tables

:- dynamic md/1 as monotonic.
:- table (mp/1, mq/1) as monotonic.

mp(X) :- md(X).
mq(X) :- mp(X).

set_md(L) :-
    retractall(md(_)),
    forall(member(X, L), assertz(md(X))).
add_md(X) :-
    assertz(md(X)).

%   Many incremental tables over dynamic calls

:- dynamic fd/1 as incremental.
:- table (fp/1, fq/1) as incremental.

fd(1).

fp(I) :- fd(X), X >= 0, I >= 0.
fq(N) :- forall(between(1, N, I), fp(I)).

fill(N) :-
    abolish_all_tables,
    fq(N).

add_fd(X) :-
    assertz(fd(X)).
del_fd(X) :-
    retract(fd(X)).

%   abolish_and_query(-Shared, -Private)
%
%   Abolish the private tables and update the shared table that a
%   private table depended on.

abolish_and_query(Shared, Private) :-
    set_sd([1]),
    findall(X, ps(X), _),
    abolish_private_tables,
    add_sd(2),
    findall(X, ss(X), Shared0), msort(Shared0, Shared),
    findall(X, ps(X), Private0), msort(Private0, Private).

shared_affected(Count) :-
    current_table(test_abolish_bulk:V, T),
    V = ss(_),
    !,
    aggregate_all(count, '$idg_edge'(T, affected, _), Count).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("bk01", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(private_over_shared, [condition(threads), C]), call(C)), true)"),
    ("bk02", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(shared_edges_removed, [condition(threads), C]), call(C)), true)"),
    ("bk03", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(thread_exit, [condition(threads), C]), call(C)), true)"),
    ("bk04", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(conditional, [C]), call(C)), true)"),
    ("bk05", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(monotonic, [C]), call(C)), true)"),
    ("bk06", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(registry, [true(C1), C2, true(C3)]), call(C1), call(C2), call(C3)), true)"),
    ("bk07", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(update_after_abolish, [C]), call(C)), true)"),
    ("bk08", "abolish_bulk", "setup_call_cleanup(true, (plunit_abolish_bulk:test(space, [condition(threads), true(C)]), call(C)), true)"),
]


"The thread-bound rows (upstream `condition(threads)`): pinned on swipl; the kernel's line is compared to the pin, and a line that differs is @test_broken, never a silent pass."
const _TT_THREAD_IDS = ["bk01", "bk02", "bk03", "bk08"]
const _TT_KL = Ref{Vector{String}}(String[])


const _TT_PINNED = [
    "ok",
    "t_bk01 c[116,95,98,107,48,49]/1(a[111,107])",
    "t_bk02 c[116,95,98,107,48,50]/1(a[111,107])",
    "t_bk03 c[116,95,98,107,48,51]/1(a[111,107])",
    "t_bk04 c[116,95,98,107,48,52]/1(a[111,107])",
    "t_bk05 c[116,95,98,107,48,53]/1(a[111,107])",
    "t_bk06 c[116,95,98,107,48,54]/1(a[111,107])",
    "t_bk07 c[116,95,98,107,48,55]/1(a[111,107])",
    "t_bk08 c[116,95,98,107,48,56]/1(a[111,107])",
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
]

"The files of the program in a fresh directory: the parent module file, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    write(joinpath(d, "test_abolish_bulk.pl"), ":- module(test_abolish_bulk, []).\n" * _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_abolish_bulk)).\n" * text
        )
    end
    main = ":- use_module('$d/test_abolish_bulk').\n" * join([":- catch(use_module('$d/plunit_$short'), _, true).\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_abolish_bulk.pl: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    _TT_KL[] = kl
    @test length(kl) == length(_TT_PINNED)
    @test _TT_PINNED[1] == st
    for (i, (k, pn)) in enumerate(zip(kl, _TT_PINNED))
        i > 1 && _TT_CASES[i - 1][1] in _TT_THREAD_IDS && continue
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "thread-bound: expected refusal on the kernel (upstream tests with condition(threads))" begin
    kl = _TT_KL[]
    @test length(kl) == length(_TT_PINNED)
    for id in _TT_THREAD_IDS
        j = findfirst(c -> c[1] == id, _TT_CASES)::Int
        k, pn = kl[j + 1], _TT_PINNED[j + 1]
        @test _tt_answer(pn) == _TT_UPSTREAM[j]
        @test k != _tt_corrupt(pn)  # must-fail: the comparison can fail
        if k == pn
            @test true
        else
            println(stderr, "  thread-bound ", id, "\n  ours  ", k, "\n  swipl ", pn)
            @test_broken k == pn
        end
    end
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
