# ORIGINAL: LIVE differential rows of TAB1 TB4 (kill rows R13-R18 of the TB4 mutation list; audit D-0635 items 2-4) against swipl at the
# pin (swipl-devel 18168e62, 10.1.20), for the survivors of the batch-3 battery on the WFS code of pl-tabling.c: R13 answer completion
# (`answer_completion/2`, boot/tabling.pl:2252-2305; kernel :6172-6247), R14 an answer first conditional, then unconditional
# (`update_delay_list`), R15 `_udl_undefined` (white-box), R16 `'$tbl_wkl_is_false'/1`, R17 `'$tbl_answer_update_dl'/3` on a moded table, R18 a
# delay naming a non-ground answer (REC_DELAY / the variable-sharing record). A sibling file, test_tabling_tb4rows_swipl.jl, holds R5-R12.
# R13's two counter rows (g13a, g13b: mutants A2, A3) need TB5's `'$tbl_destroy_table'/1`: they live in test_tabling_tb4_tb5_swipl.jl.
#   * Cases `t_<id>(R)` run in order in ONE database per group, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; one program
#     text per group (`_TS_GROUPS`), the same text on both sides; the driver is test_tabling_wfs_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs: evidence/TAB1/tb4kc_verify.md keeps the commands);
#     with `swipl` on PATH the live answers are compared with the pins too; without it the pin table is checked for shape.
#   * Both sides of every row are non-empty: each pin carries an answer (`_TS_ANS` projects it through ONE extractor) and the kernel line is
#     read through the same driver function; the white-box row (R15) compares constants whose two values differ.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
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

"The program text with the cases of `cases` appended."
_ts_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ts_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb4rows2.pl")
    write(f, _ts_text(program, cases))
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

"The answer part of a line (`t_<id> <answer>`): the ONE extractor every comparison of a row goes through."
_ts_ans(line::AbstractString) = String(split(line, " "; limit=2)[2])

const _TS_G14_PROGRAM = raw"""
:- use_module(library(wfs)).
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table r14p/0, r14q/0, wy/0.
r14p :- tnot(r14q).
r14q :- tnot(r14p).
wy :- tnot(r14p).
wy.
"""

const _TS_G14_CASES = [
    ("r1401", raw"call_delays(wy, D), R = D"),
    ("r1402", raw"findall(B, answer_residual(wy, B), L), R = L"),
    ("r1403", raw"tm_yn(call_delays(wy, true), R)"),
    ("r1404", raw"call_delays(r14p, D), R = D"),
    ("r1405", raw"findall(B, answer_residual(r14p, B), L), R = L")
]

const _TS_G14_PINNED = [
    "ok",
    "t_r1401 c[116,95,114,49,52,48,49]/1(a[116,114,117,101])",
    "t_r1402 c[116,95,114,49,52,48,50]/1(c[91,124,93]/2(a[116,114,117,101],nil))",
    "t_r1403 c[116,95,114,49,52,48,51]/1(a[121,101,115])",
    "t_r1404 c[116,95,114,49,52,48,52]/1(a[114,49,52,112])",
    "t_r1405 c[116,95,114,49,52,48,53]/1(c[91,124,93]/2(c[116,110,111,116]/1(a[114,49,52,113]),nil))"
]

const _TS_G14_DISTINCT = [("r1401", "r1404"), ("r1402", "r1405")]

const _TS_G17_PROGRAM = raw"""
:- use_module(library(wfs)).
:- table m17(_, max).
m17(a, 1).
m17(a, 3).
m17(a, 2).
m17(b, 5).
:- table m17l(_, lattice(m17j/3)).
m17j(A, B, C) :- ord_union(A, B, C).
m17l(a, [1]).
m17l(a, [3]).
m17l(b, [7]).
m17_vars(K, T) :- '$tbl_variant_table'(VT), trie_gen(VT, K, T).
m17_tab(K0, T) :- m17_vars(user:K, T), K =@= K0.
"""

const _TS_G17_CASES = [
    (
        "r1701",
        raw"once(m17(_, _)), m17_tab('$m17$1'(_), T), findall(S-M, (trie_gen(T, S), '$tbl_answer_update_dl'(T, S, M)), L0), msort(L0, L), R = L"
    ),
    (
        "r1702",
        raw"once(m17l(_, _)), m17_tab('$m17l$1'(_), T), findall(S-M, (trie_gen(T, S), '$tbl_answer_update_dl'(T, S, M)), L0), msort(L0, L), R = L"
    ),
    (
        "r1703",
        raw"once(m17(_, _)), m17_tab('$m17$1'(_), T), trie_gen(T, S), S = ret(a), once('$tbl_answer_update_dl'(T, S, M)), R = M"
    ),
    (
        "r1704",
        raw"once(m17(_, _)), m17_tab('$m17$1'(_), T), trie_gen(T, S), S = ret(b), '$tbl_answer_update_dl'(T, S, M), '$tbl_delay_list'(DL), R = r(M, DL)"
    )
]

const _TS_G17_PINNED = [
    "ok",
    "t_r1701 c[116,95,114,49,55,48,49]/1(c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[97]),i3),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[98]),i5),nil)))",
    "t_r1702 c[116,95,114,49,55,48,50]/1(c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[97]),c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[98]),c[91,124,93]/2(i7,nil)),nil)))",
    "t_r1703 c[116,95,114,49,55,48,51]/1(i3)",
    "t_r1704 c[116,95,114,49,55,48,52]/1(c[114]/2(i5,nil))"
]

const _TS_G17_DISTINCT = [("r1701", "r1702"), ("r1703", "r1704")]

const _TS_G18_PROGRAM = raw"""
:- use_module(library(wfs)).
:- table g1/1, g2/1, gu/0, gv/0.
gu :- tnot(gv).
gv :- tnot(gu).
g1(f(_)) :- gu.
g2(X) :- g1(X).
"""

const _TS_G18_CASES = [
    ("r1801", raw"once(g2(_)), findall(X-B, answer_residual(g2(X), B), L), R = L"),
    ("r1802", raw"once(g2(_)), findall(X-B, answer_residual(g1(X), B), L), R = L"),
    ("r1803", raw"once(g2(_)), call_residual_program(g2(X), P), R = X-P"),
    (
        "r1804",
        raw"once(g2(_)), findall(S, (answer_residual(g2(X), B), B = g1(f(Y)), ( X == f(Y) -> S = shared ; S = apart )), L0), sort(L0, L), R = L"
    ),
    (
        "r1805",
        raw"once(g2(_)), findall(S, (answer_residual(g1(X), B), B == gu, X = f(Y), var(Y), S = open), L0), sort(L0, L), R = L"
    )
]

const _TS_G18_PINNED = [
    "ok",
    "t_r1801 c[116,95,114,49,56,48,49]/1(c[91,124,93]/2(c[45]/2(c[102]/1(V0),c[103,49]/1(c[102]/1(V0))),nil))",
    "t_r1802 c[116,95,114,49,56,48,50]/1(c[91,124,93]/2(c[45]/2(c[102]/1(V0),a[103,117]),nil))",
    "t_r1803 c[116,95,114,49,56,48,51]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(c[58,45]/2(c[103,50]/1(c[102]/1(V0)),c[103,49]/1(c[102]/1(V0))),c[91,124,93]/2(c[58,45]/2(c[103,49]/1(c[102]/1(V0)),a[103,117]),c[91,124,93]/2(c[58,45]/2(a[103,117],c[116,110,111,116]/1(a[103,118])),c[91,124,93]/2(c[58,45]/2(a[103,118],c[116,110,111,116]/1(a[103,117])),nil))))))",
    "t_r1804 c[116,95,114,49,56,48,52]/1(c[91,124,93]/2(a[115,104,97,114,101,100],nil))",
    "t_r1805 c[116,95,114,49,56,48,53]/1(c[91,124,93]/2(a[111,112,101,110],nil))"
]

const _TS_G18_DISTINCT = [("r1801", "r1802"), ("r1802", "r1803")]

const _TS_GROUPS = [
    ("g14", _TS_G14_PROGRAM, _TS_G14_CASES, _TS_G14_PINNED, _TS_G14_DISTINCT),
    ("g17", _TS_G17_PROGRAM, _TS_G17_CASES, _TS_G17_PINNED, _TS_G17_DISTINCT),
    ("g18", _TS_G18_PROGRAM, _TS_G18_CASES, _TS_G18_PINNED, _TS_G18_DISTINCT)
]

# one testset per group: the kernel's lines against the pins, in one database per group
@testset "TB4 kill rows R13-R18 as swipl's: $(grp[1])" for grp in _TS_GROUPS
    (_, program, cases, pinned, _) = grp
    gd, ld, st = _ts_load(program, cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in cases
        push!(kl, _ts_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(pinned)
    for (k, p) in zip(kl, pinned)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the TB4 rows 2 are not vacuous" begin
    @test !isempty(_TS_GROUPS)
    for (gid, _, cases, pinned, distinct) in _TS_GROUPS
        @test pinned[1] == "ok"
        @test length(pinned) == length(cases) + 1
        for (id, _) in cases
            ls = [l for l in pinned if startswith(l, "t_$id ")]
            @test length(ls) == 1
            @test !isempty(_ts_ans(only(ls)))        # the pin side is never empty
        end
        ans(id) = _ts_ans(only(filter(l -> startswith(l, "t_$id "), pinned)))
        @test !isempty(distinct)
        for (a, b) in distinct                       # two answers that a mutant would make equal
            @test ans(a) != ans(b)
        end
    end
end

@testset "the TB4 rows 2 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB4 ROWS 2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for (_, _, cases, pinned, _) in _TS_GROUPS
            @test pinned[1] == "ok"
            @test [first(split(l, " ")) for l in pinned[2:end]] ==
                ["t_$id" for (id, _) in cases]
        end
    else
        for (_, program, cases, pinned, _) in _TS_GROUPS
            f = joinpath(mktempdir(), "tb4rows2_swipl.pl")
            write(f, _ts_text(program, cases))
            @test _ts_swipl_lines(f, ["t_$id" for (id, _) in cases]) == pinned
        end
    end
end

"An opaque child key for the number `k`: an atom-tagged word (never a variable key), as test_trie_swipl.jl's `_tk`."
_ts_tk(k::Integer)::UInt64 = LK.consTagged(k, LK.TAG_ATOM | LK.STG_STATIC)

@testset "TB4K-c white-box (R15): `_udl_undefined` makes an answer undefined and answers UDL_TRUE (TB4-U6)" begin
    # update_delay_list_any's `undef:` label (a deleted trie, or `undefined` in a delay list). The Prolog route to it is not usable
    # (a table named by a running delay cannot be deleted from a Prolog body), so the state is built by hand, as the worklist rows do
    # (TB2-Q3 in test_tabling_worklist_swipl.jl): an answer trie with one answer node and a delay info on it.
    gd = LK.PL_global_data{_TS}()
    tr = LK.trie_create(_TS)
    LK.trie_serial!(gd, tr)
    nid = LK.insert_child(tr, 1, _ts_tk(7))
    old = LK.delay_info(tr.serial, UInt32(0), LK.delay_set[], LK.delay[])
    LK.set_node_delayinfo(gd, tr, nid, old)
    @test LK.node_delayinfo(gd, tr, nid) === old
    @test !LK.answer_is_conditional(gd, tr, nid)   # an empty delay set: unconditional
    @test LK.UDL_TRUE != LK.UDL_FALSE              # the two values the mutant swaps
    @test LK._udl_undefined(gd, tr, nid) == LK.UDL_TRUE   # kills TB4-U6 (UDL_FALSE)
    @test LK.node_delayinfo(gd, tr, nid) === LK.DL_UNDEFINED_INFO
    @test LK.answer_is_conditional(gd, tr, nid)    # undefined is conditional
    @test !LK.DL_IS_DELAY_LIST(LK.node_delayinfo(gd, tr, nid))
    # an answer without any delay info: the same result
    nid2 = LK.insert_child(tr, 1, _ts_tk(8))
    @test LK.node_delayinfo(gd, tr, nid2) === nothing
    @test LK._udl_undefined(gd, tr, nid2) == LK.UDL_TRUE
    @test LK.node_delayinfo(gd, tr, nid2) === LK.DL_UNDEFINED_INFO
end

@testset "TB4K-c white-box (R16): '\$tbl_wkl_is_false' is neg_delayed AND NOT has_answers (TB4-W1)" begin
    # pl-tabling.c:5399 `return wl->neg_delayed && !wl->has_answers`. A program run through the pin reaches only two of the four
    # (neg_delayed, has_answers) states (the resumption by completion: (true, false); a negation answered at once: (false, true));
    # an OR cannot tell those from the AND, so the four states are built by hand on a negative worklist.
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    ctx = LK.foreign_context{_TS}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    function is_false(wl)
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        wl.owner = ld                                  # a hand-built worklist is the thread's own (new_worklist: owner = LD)
        LK.PL_put_int64(ld, a, LK.worklist_handle(ld, wl))
        rc = LK.pl_tbl_wkl_is_false1_va(ld, a, 1, ctx)
        LK.PL_close_foreign_frame(ld, fid)
        return rc
    end
    @test LK.FTRUE != LK.FFALSE
    # (neg_delayed, has_answers) => the answer; the literal table, not the formula
    for (nd, ha, want) in (
        (true, false, LK.FTRUE), (true, true, LK.FFALSE),
        (false, false, LK.FFALSE), (false, true, LK.FFALSE)
    )
        wl = LK.tbl_worklist{_TS}()
        wl.negative = true
        wl.neg_delayed = nd
        wl.has_answers = ha
        @test is_false(wl) == want      # kills TB4-W1: (true, true) and (false, false) answer FTRUE under ||
    end
end
