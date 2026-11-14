# ORIGINAL: kill rows of TAB1 TB3 for two mutants that the first three-type battery on the extended target list left alive
# (tools/mutants/TB3.py `TB3-F3`, `TB3-U2`; their `equivalent` text said only the truthiness of `'$tbl_wkl_add_answer'/4` is read, and that
# no row calls it that way: this file calls it as a predicate and reads both its success and its 4th argument).
#   * `'$tbl_wkl_add_answer'/4` (pl-tabling.c:4885-4899) ends `return !!rc`, with `rc == TBL_ANSWER_COMPLETE` first binding
#     the 4th argument to `!` (`PL_unify_atom(A4, ATOM_cut)`, :4893-4894): a DIRECT caller sees the result.
#   * TB3-F3 (kernel src/pl-tabling.jl, `tbl_add_answer_found`: `return 0  # already in trie` -> `return TBL_ANSWER_NEW`; C
#     pl-tabling.c:4821 `return false; /* already in trie */`, after the TN_IDG_DELETED and the conditional-answer tests :4809-4820): a variant answer is not new, the predicate FAILS. Killed by tbf01 (the
#     same answer twice: swipl `[ok(_), no]`; the mutant `[ok(_), ok(_)]`) and tbf02 (the variant comes third); tbf03 is the control (two
#     distinct answers: both succeed under the mutant too), tbu02 also ends on a variant answer.
#   * TB3-U2 (`update_delay_list`: `return wl.ground ? UDL_COMPLETE : UDL_TRUE` -> `return UDL_TRUE`; C pl-tabling.c:1544-1559: `return
#     wl->ground ? UDL_COMPLETE : UDL_TRUE` at :1559, inside `isNil(*ldlp) && isNil(*gdlp) && !node_delayinfo(answer)`): a new answer of a GROUND call with an empty delay list completes the table early, the 4th
#     argument is `!` (kernel :4316-4318). Killed by tbu01 (swipl `[ok(!)]`; the mutant `[ok(_)]`) and tbu02 (`[ok(!), no]`); tbf01-tbf03 call
#     a NON-ground variant: the first answer is `ok(_)` (UDL_TRUE) in swipl, so `!` is not what every call answers.
#   * The rows are NOT white-box: ONE program consulted by swipl and the kernel, every answer line is swipl's, PINNED (pinned swipl 18168e62,
#     `LC_ALL=C swipl -q`, the driver of test_tabling_answers_swipl.jl, TWO byte-identical runs; evidence/TAB1/tb3_killrows_note.md), and with
#     `swipl` on PATH the live answers are compared with the pins too. The worklist is built the way the TB3-S9 rows build it
#     (test_tabling_answers_swipl.jl tbw01-tbw03): an outermost wrapper (`'$c_wrap_predicate'/5`) whose body asks
#     `'$tbl_variant_table'/6` for a FRESH variant of a plain table `t3_wg(_, _)` and adds answers to its worklist; the wrapper leaves the
#     table incomplete, so each row has its OWN key (f1-f3, u1, u2). A ground variant (`t3_wg(u1, 5)`) gets `wl.ground` from the `ret` skeleton
#     (pl-tabling.c `tbl_variant_table` `WL_GROUND`, kernel :3518-3526, `new_worklist` :1322).
#   * TB3-C8 (`tbl_complete_answer_clause`: the `set_start_node` call dropped; the list called it a performance cache, and it also PINS the cached
#     node: `set_start_node` does `tr.nodes[nid].flags |= TN_PINNED`, kernel :3135, upstream pl-tabling.c:12448 `set(node, TN_PINNED)`, the
#     comment :12352 "Cached nodes are pinned, such that abolishing the tables of a predicate does not prune them"). A pinned node stops
#     `prune_node` (kernel pl-trie.jl:917, :960; pl-trie.c:1464, :1524). Row tbc01 reads it through the variant table: after `p(_)` is called
#     TWICE (the start node is cached from the SECOND call on: the first finds no path) `trie_delete` of the `p(_)` entry of
#     `'$tbl_local_variant_table'/1` removes ONE node (the entry) and keeps the pinned `p/1` functor node: delta 1 in swipl; the mutant pins
#     nothing and prunes the functor node too: delta 2 (predicted, not run). Row tbc02 is the control: `p(_)` called ONCE (nothing cached,
#     nothing pinned): delta 2 in swipl, and under the mutant too; the two pins differ. Each row has its OWN program/kernel: the variant
#     table is global. Pinned swipl, two byte-identical runs of each. ASSUMPTION (predicted, not run): on the kernel `trie_gen/3` finds
#     ONE `p(_)` entry and the deltas are 1 and 2, as swipl's.
#   * UNVERIFIED on the kernel when written (nothing was compiled or run): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T3R = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_t3rs(x) = lk_sym(_T3R, Symbol(x))

_t3r_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _t3r_enc(t::_T3R, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _t3r_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _t3r_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _t3r_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_t3r_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
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

function _t3r_swipl_lines(path::String, names::Vector{String})::Vector{String}
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

"The program text with the cases appended."
_t3r_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _t3r_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_answers.pl")
    write(f, _t3r_text(program, cases))
    gd = LK.PL_global_data{_T3R}()
    ld = LK.PL_local_data{_T3R}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _t3r_enc(ball::_T3R))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _t3r_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_t3rs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T3R, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _t3r_enc(mk_expr(_T3R, _T3R[_t3rs(pred), lk_answers(ld, (a:a)...)...]))
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

"Every row of the file, asked of one kernel in order: `(program loaded line, row lines)`."

const _T3R_PROGRAM = raw"""
:- dynamic t3_res/2.
:- table t3_wg(_, _).
t3_wg(_, _).
t3_steps(f1, [ret(1), ret(1)]).
t3_steps(f2, [ret(1), ret(2), ret(1)]).
t3_steps(f3, [ret(1), ret(2)]).
t3_steps(u1, [ret]).
t3_steps(u2, [ret, ret]).
t3_add(K, X, Closure) :-
    '$tbl_variant_table'(Closure, t3_wg(K, X), Trie, Status, Skel, _Mono),
    (   Status = fresh(_SCC, WL)
    ->  '$tbl_set_delay_list'([]),
        t3_steps(K, Steps),
        t3_job(Steps, WL, Skel, Rs),
        findall(S-C, '$tbl_answer'(Trie, S, C), L0),
        msort(L0, L),
        assertz(t3_res(K, r(Rs, L)))
    ;   assertz(t3_res(K, notfresh))
    ).
t3_job([], _, _, []).
t3_job([A|As], WL, Skel, [R|Rs]) :-
    copy_term(Skel, S),
    S = A,
    catch(( '$tbl_wkl_add_answer'(WL, S, [], C) -> R = ok(C) ; R = no ), E, R = ex(E)),
    t3_job(As, WL, Skel, Rs).
:- '$c_wrap_predicate'(user:t3_wg(_, _), t3_w, Closure, _W,
       user:('$wrap$t3_wg'(K, X) :- t3_add(K, X, Closure))).
t3_run(K, X, R) :- ( t3_wg(K, X) -> true ; true ), t3_res(K, R).
"""

const _T3R_CASES = [
    ("tbf01", raw"t3_run(f1, _, R)"),
    ("tbf02", raw"t3_run(f2, _, R)"),
    ("tbf03", raw"t3_run(f3, _, R)"),
    ("tbu01", raw"t3_run(u1, 5, R)"),
    ("tbu02", raw"t3_run(u2, 5, R)")
]

# swipl 18168e62 (10.1.20), `LC_ALL=C swipl -q`, the file's driver, two byte-identical runs (evidence/TAB1/tb3_killrows_note.md)
# decoded: tbf01 = r([ok(_), no], [ret(1)-true]); tbf02 = r([ok(_), ok(_), no], [ret(1)-true, ret(2)-true]);
# tbf03 = r([ok(_), ok(_)], [ret(1)-true, ret(2)-true]); tbu01 = r([ok(!)], [ret-true]); tbu02 = r([ok(!), no], [ret-true])
const _T3R_PINNED = [
    "ok",
    "t_tbf01 c[116,95,116,98,102,48,49]/1(c[114]/2(c[91,124,93]/2(c[111,107]/1(V0),c[91,124,93]/2(a[110,111],nil)),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i1),a[116,114,117,101]),nil)))",
    "t_tbf02 c[116,95,116,98,102,48,50]/1(c[114]/2(c[91,124,93]/2(c[111,107]/1(V0),c[91,124,93]/2(c[111,107]/1(V1),c[91,124,93]/2(a[110,111],nil))),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i1),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i2),a[116,114,117,101]),nil))))",
    "t_tbf03 c[116,95,116,98,102,48,51]/1(c[114]/2(c[91,124,93]/2(c[111,107]/1(V0),c[91,124,93]/2(c[111,107]/1(V1),nil)),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i1),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i2),a[116,114,117,101]),nil))))",
    "t_tbu01 c[116,95,116,98,117,48,49]/1(c[114]/2(c[91,124,93]/2(c[111,107]/1(a[33]),nil),c[91,124,93]/2(c[45]/2(a[114,101,116],a[116,114,117,101]),nil)))",
    "t_tbu02 c[116,95,116,98,117,48,50]/1(c[114]/2(c[91,124,93]/2(c[111,107]/1(a[33]),c[91,124,93]/2(a[110,111],nil)),c[91,124,93]/2(c[45]/2(a[114,101,116],a[116,114,117,101]),nil)))"
]

const _T3R_CACHE = Ref{Any}(nothing)
"The kernel's lines of the program: `(program loaded line, one line per case)`, computed once."
function _t3r_kernel()
    if _T3R_CACHE[] === nothing
        gd, ld, st = _t3r_load(_T3R_PROGRAM, _T3R_CASES)
        _T3R_CACHE[] = (st, String[_t3r_ask(gd, ld, "t_$id") for (id, _) in _T3R_CASES])
    end
    return _T3R_CACHE[]
end

@testset "TB3-F3, TB3-U2: '\$tbl_wkl_add_answer'/4 as a predicate: a variant answer fails, a ground call's first answer binds `!` (kills TB3-F3, TB3-U2)" begin
    @test _t3r_kernel()[1] == "ok"
    @test length(_t3r_kernel()[2]) + 1 == length(_T3R_PINNED)
    @test !isempty(_t3r_kernel()[2])
    for (i, (id, _)) in enumerate(_T3R_CASES)
        k, p = _t3r_kernel()[2][i], _T3R_PINNED[i + 1]
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    pin(id) = only(filter(l -> startswith(l, "t_$id "), _T3R_PINNED))
    no = "a[110,111]"                       # the atom `no`: the call FAILED
    ok1 = "c[111,107]/1("                   # `ok(`: the call succeeded
    bang = "c[111,107]/1(a[33])"            # `ok(!)`: the 4th argument is bound to `!`
    # not vacuous, both sides non-empty: TB3-F3 -- a variant answer FAILS: the `no` is the last result of tbf01, tbf02 and tbu02, and appears
    # nowhere in the control tbf03 and the single answer tbu01; the successes come first
    @test count(no, pin("tbf01")) == 1 && count(ok1, pin("tbf01")) == 1
    @test count(no, pin("tbf02")) == 1 && count(ok1, pin("tbf02")) == 2
    @test occursin(
        ok1 * "V0),c[91,124,93]/2(" * ok1 * "V1),c[91,124,93]/2(" * no, pin("tbf02")
    )      # the variant is the THIRD call
    @test count(no, pin("tbf03")) == 0 && count(ok1, pin("tbf03")) == 2
    @test count(no, pin("tbu02")) == 1 && count(no, pin("tbu01")) == 0
    # the MUST-FAIL corruption of TB3-F3 (a variant answer succeeds: the `no` becomes `ok(V<n>)`): the corrupted line differs from the pin for
    # tbf01, tbf02, tbu02 and not for the controls, so a kernel line that succeeded on the variant answer cannot pass `k == p`
    f3(l) = replace(l, no => ok1 * "V9)"; count=1)
    @test f3(pin("tbf01")) != pin("tbf01") && f3(pin("tbf02")) != pin("tbf02")
    @test f3(pin("tbu02")) != pin("tbu02")
    @test f3(pin("tbf03")) == pin("tbf03") && f3(pin("tbu01")) == pin("tbu01")
    # TB3-U2 -- the first answer of the GROUND call is `ok(!)`; the first answers of the non-ground calls are `ok(V0)`, never `!`
    @test occursin(bang, pin("tbu01")) && occursin(bang, pin("tbu02"))
    @test !occursin(bang, pin("tbf01")) && !occursin(bang, pin("tbf02")) &&
        !occursin(bang, pin("tbf03"))
    # the MUST-FAIL corruption of TB3-U2 (no early completion: the 4th argument stays unbound, `ok(!)` becomes `ok(V0)`)
    u2(l) = replace(l, bang => ok1 * "V0)"; count=1)
    @test u2(pin("tbu01")) != pin("tbu01") && u2(pin("tbu02")) != pin("tbu02")
    @test u2(pin("tbf01")) == pin("tbf01")
end

@testset "TB3-F3, TB3-U2: the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB3-F3/TB3-U2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test _T3R_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _T3R_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _T3R_CASES]
    else
        f = joinpath(mktempdir(), "tb3rows_swipl.pl")
        write(f, _t3r_text(_T3R_PROGRAM, _T3R_CASES))
        @test _t3r_swipl_lines(f, ["t_$id" for (id, _) in _T3R_CASES]) == _T3R_PINNED
    end
end

const _T3C_TEMPLATE = raw"""
:- table t3c_p/1, t3c_q/1.
t3c_p(1).
t3c_p(2).
t3c_q(a).
t3c_del(R) :-
    once(t3c_q(_)),
    once(t3c_q(_)),
@PCALLS@    '$tbl_local_variant_table'(VT),
    findall(K-V, (trie_gen(VT, K, V), K = _:t3c_p(_)), L),
    trie_property(VT, node_count(N0)),
    forall(member(K1-V1, L), trie_delete(VT, K1, V1)),
    trie_property(VT, node_count(N1)),
    length(L, Len),
    D is N0 - N1,
    R = r(Len, D).
"""

"The TB3-C8 program: `t3c_p(_)` is called `pcalls` times before the variant table is read."
_t3c_program(pcalls::Int) =
    replace(_T3C_TEMPLATE, "@PCALLS@" => "    once(t3c_p(_)),\n"^pcalls)

# (p calls, cases, pins): tbc01 = `p(_)` twice, tbc02 = once (the control); swipl 18168e62 as above
# decoded: tbc01 = r(1, 1) (one entry deleted, delta 1); tbc02 = r(1, 2) (delta 2)
const _T3C_RUNS = [
    (
        2,
        [("tbc01", raw"t3c_del(R)")],
        ["ok", "t_tbc01 c[116,95,116,98,99,48,49]/1(c[114]/2(i1,i1))"]
    ),
    (
        1,
        [("tbc02", raw"t3c_del(R)")],
        ["ok", "t_tbc02 c[116,95,116,98,99,48,50]/1(c[114]/2(i1,i2))"]
    )
]

const _T3C_CACHE = Dict{Int, Any}()
"The kernel's lines of the TB3-C8 program with `pcalls` calls: `(program loaded line, one line per case)`, computed once."
function _t3c_kernel(pcalls::Int, cases)
    get!(_T3C_CACHE, pcalls) do
        gd, ld, st = _t3r_load(_t3c_program(pcalls), cases)
        (st, String[_t3r_ask(gd, ld, "t_$id") for (id, _) in cases])
    end
end

@testset "TB3-C8: the cached start node stays pinned, a prune of the variant table keeps its functor node (kills TB3-C8)" begin
    for (pcalls, cases, pins) in _T3C_RUNS
        st, lines = _t3c_kernel(pcalls, cases)
        @test st == "ok"
        @test length(lines) + 1 == length(pins)
        @test !isempty(lines)
        for (i, (id, _)) in enumerate(cases)
            k, p = lines[i], pins[i + 1]
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    # not vacuous, both sides non-empty: ONE entry was deleted in both rows (`i1` first), the deltas are 1 (cached and pinned) and 2 (not
    # cached), and they DIFFER: the mutant (nothing pinned) gives the control's delta 2 in tbc01
    p1, p2 = _T3C_RUNS[1][3][2], _T3C_RUNS[2][3][2]
    @test endswith(p1, "c[114]/2(i1,i1))") && endswith(p2, "c[114]/2(i1,i2))")
    @test p1 != p2
    c8(l) = replace(l, "c[114]/2(i1,i1))" => "c[114]/2(i1,i2))"; count=1)
    @test c8(p1) != p1 && c8(p2) == p2
end

@testset "TB3-C8: the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    for (pcalls, cases, pins) in _T3C_RUNS
        if swipl === nothing
            @info "TB3-C8 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
            @test pins[1] == "ok"
            @test [first(split(l, " ")) for l in pins[2:end]] ==
                ["t_$id" for (id, _) in cases]
        else
            f = joinpath(mktempdir(), "tb3rows_c8_swipl.pl")
            write(f, _t3r_text(_t3c_program(pcalls), cases))
            @test _t3r_swipl_lines(f, ["t_$id" for (id, _) in cases]) == pins
        end
    end
end
