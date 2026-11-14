# ORIGINAL: a LIVE differential of the worklists, SCCs and completion of pl-tabling.c (TAB1 TB2; audit D-0477) against swipl at
# the pin (swipl-devel 18168e62, 10.1.20): tabled LEFT recursion (`tw_path/2`, a cycle a-b-c-a and an exit c-d) and MUTUAL
# recursion (`tw_ev/1` with `tw_od/1`, one SCC of two tables; `tw_r1/2` with `tw_r2/2`, left recursive through the other
# predicate). Groups: twl = left recursion, twm = mutual recursion. Each group reads the answers (order-free: msort or a test),
# a variant called twice (the complete table answers it) and the table status after the call (`complete`: the SCC was completed
# by `$tbl_table_complete_all/3` or `$tbl_leader_complete/4`).
#   * TB2K2 rows (kill rows of the ten TB2 survivors): twk = ONE cluster with two suspensions (tw_k/1), twv = a two-frame continuation (tw_n/1) and an
#     ordinary reset/3 of call_continuation/1, twq = the `$tbl_leader/5` catcher `fail` through a message_hook and the parent of a nested component; four
#     white-box testsets at the end (wl_set_component, wkl_swap_clusters, `$tbl_wkl_make_follower`, table_complete_all) read what no answer shows.
#   * Unlike test_tabling_variant_swipl.jl the program uses `:- table` itself in both systems: these rows run the tabling
#     engine end to end (`$tbl_wkl_work/6`, `$tbl_pop_worklist/2`, the completion, the `$tbl_reset/6` hooks of I_RESET and
#     I_EXITRESET, the `$tbl_leader/5` cleanup).
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver
#     is test_tabling_variant_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs, 2026-11-10); with `swipl` on PATH the live
#     answers are compared with the pins too.
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

"The program text with the cases of `cases` appended."
_tw_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tw_load(program::String)
    f = joinpath(mktempdir(), "tabling_worklist.pl")
    write(f, _tw_text(program, _TW_CASES))
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

const _TW_PROGRAM = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table tw_path/2.
tw_path(X, Y) :- tw_path(X, Z), tw_edge(Z, Y).
tw_path(X, Y) :- tw_edge(X, Y).
tw_edge(a, b).
tw_edge(b, c).
tw_edge(c, a).
tw_edge(c, d).
:- table tw_ev/1, tw_od/1.
tw_ev(0).
tw_ev(N) :- tw_od(M), N is M+1, N =< 6.
tw_od(N) :- tw_ev(M), N is M+1, N =< 6.
:- table tw_r1/2, tw_r2/2.
tw_r1(X, Y) :- tw_r2(X, Z), tw_edge(Z, Y).
tw_r1(X, Y) :- tw_edge(X, Y).
tw_r2(X, Y) :- tw_r1(X, Y).
tw_status(G, S) :- '$tbl_existing_variant_table'(0, G, T, _, _), '$tbl_table_status'(T, S).
% twk: ONE cluster with two suspensions (tw_k/1 calls itself twice in its two clauses): `wkl_next_suspension` visits member 0 too
:- table tw_k/1.
tw_k(X) :- tw_k(Y), tw_ka(Y, X).
tw_k(X) :- tw_k(Y), tw_kb(Y, X).
tw_k(0).
tw_ka(0, 1).
tw_ka(1, 2).
tw_kb(0, 10).
tw_kb(10, 20).
% twv: a continuation of TWO frames (tw_nb, then tw_na) between the tabled call and the clause: push_continuation_list order.
% No exception on either order: tw_na tests `integer(Z)` itself, so the frame run FIRST decides the answer (resumed in order, tw_nb binds Z
% and tw_na adds 1: 1,3,7,15,31; resumed reversed, tw_na sees Z unbound and answers `unbound`: 1 and unbound)
:- table tw_n/1.
tw_n(1).
tw_n(Y) :- tw_na(Y).
tw_na(Y) :- tw_nb(Z), ( integer(Z) -> Y is Z + 1 ; Y = unbound ).
tw_nb(Z) :- tw_n(Z0), integer(Z0), Z0 < 20, Z is Z0 * 2.
% twq08: the leader cleanup reports an UNEXPECTED result (message tabling(unexpected_result(_, C))) for every catcher but exit and fail
:- dynamic tw_seen/1.
:- multifile user:message_hook/3.
user:message_hook(tabling(unexpected_result(_, C)), _, _) :- assertz(tw_seen(C)).
tw_lf(R) :-
    retractall(tw_seen(_)),
    '$tbl_existing_variant_table'(0, user:tw_path(_, _), T, _, _),
    ( '$tabling':'$tbl_leader'(0, fail, w, _, T) -> true ; true ),
    findall(C, tw_seen(C), L1),
    once('$tabling':'$tbl_leader'(0, member(_, [1,2]), w, _, T)),
    findall(C, tw_seen(C), L2),
    R = L1-L2.
% twq11: the component of an inner tabled goal has the outer component as its parent
:- table tw_o1/1, tw_o2/1.
tw_o1(R) :- tw_o2(R).
tw_o2(R) :- '$tbl_scc'(S), '$tbl_scc_data'(S, scc(P, _, _, _, _)), ( P == null -> R = top ; R = nested ).
"""

const _TW_CASES = [
    ("twl01", raw"findall(X-Y, tw_path(X, Y), L0), msort(L0, L), R = L"),
    ("twl02", raw"findall(Y, tw_path(a, Y), L0), msort(L0, L), R = L"),
    ("twl03", raw"tm_yn(tw_path(c, c), R)"),
    ("twl04", raw"tm_yn(tw_path(d, _), R)"),
    ("twl05", raw"findall(x, tw_path(_, _), L), length(L, N), R = N"),
    ("twl06", raw"tw_status(user:tw_path(_, _), S), R = S"),
    ("twl07", raw"tw_status(user:tw_path(a, _), S), R = S"),
    (
        "twl08",
        raw"findall(Y, tw_path(a, Y), L1), findall(Y, tw_path(a, Y), L2), (L1 == L2 -> R = same ; R = diff)"
    ),
    ("twm01", raw"findall(N, tw_ev(N), L0), msort(L0, L), R = L"),
    ("twm02", raw"findall(N, tw_od(N), L0), msort(L0, L), R = L"),
    ("twm03", raw"tm_yn(tw_ev(3), R)"),
    (
        "twm04",
        raw"tw_status(user:tw_ev(_), S1), tw_status(user:tw_od(_), S2), R = r(S1, S2)"
    ),
    ("twm05", raw"findall(X-Y, tw_r1(X, Y), L0), msort(L0, L), R = L"),
    ("twm06", raw"findall(X-Y, tw_r2(X, Y), L0), msort(L0, L), R = L"),
    ("twm07", raw"findall(Y, tw_r1(d, Y), L), R = L"),
    (
        "twm08",
        raw"tw_status(user:tw_r1(_, _), S1), tw_status(user:tw_r2(_, _), S2), R = r(S1, S2)"
    ),
    ("twk01", raw"findall(X, tw_k(X), L0), msort(L0, L), R = L"),
    ("twv01", raw"findall(Y, tw_n(Y), L0), msort(L0, L), R = L"),
    (
        "twv02",
        raw"tm_yn(reset(call_continuation(foo), _, _), R1), tm_yn(reset(call_continuation([]), _, _), R2), R = r(R1, R2)"
    ),
    ("twq08", raw"tw_lf(R0), R = R0"),
    ("twq11", raw"findall(R0, tw_o1(R0), L), R = L")
]

const _TW_PINNED = [
    "ok",
    "t_twl01 c[116,95,116,119,108,48,49]/1(c[91,124,93]/2(c[45]/2(a[97],a[97]),c[91,124,93]/2(c[45]/2(a[97],a[98]),c[91,124,93]/2(c[45]/2(a[97],a[99]),c[91,124,93]/2(c[45]/2(a[97],a[100]),c[91,124,93]/2(c[45]/2(a[98],a[97]),c[91,124,93]/2(c[45]/2(a[98],a[98]),c[91,124,93]/2(c[45]/2(a[98],a[99]),c[91,124,93]/2(c[45]/2(a[98],a[100]),c[91,124,93]/2(c[45]/2(a[99],a[97]),c[91,124,93]/2(c[45]/2(a[99],a[98]),c[91,124,93]/2(c[45]/2(a[99],a[99]),c[91,124,93]/2(c[45]/2(a[99],a[100]),nil)))))))))))))",
    "t_twl02 c[116,95,116,119,108,48,50]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[100],nil)))))",
    "t_twl03 c[116,95,116,119,108,48,51]/1(a[121,101,115])",
    "t_twl04 c[116,95,116,119,108,48,52]/1(a[110,111])",
    "t_twl05 c[116,95,116,119,108,48,53]/1(i12)",
    "t_twl06 c[116,95,116,119,108,48,54]/1(a[99,111,109,112,108,101,116,101])",
    "t_twl07 c[116,95,116,119,108,48,55]/1(a[99,111,109,112,108,101,116,101])",
    "t_twl08 c[116,95,116,119,108,48,56]/1(a[115,97,109,101])",
    "t_twm01 c[116,95,116,119,109,48,49]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i2,c[91,124,93]/2(i4,c[91,124,93]/2(i6,nil)))))",
    "t_twm02 c[116,95,116,119,109,48,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,c[91,124,93]/2(i5,nil))))",
    "t_twm03 c[116,95,116,119,109,48,51]/1(a[110,111])",
    "t_twm04 c[116,95,116,119,109,48,52]/1(c[114]/2(a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101]))",
    "t_twm05 c[116,95,116,119,109,48,53]/1(c[91,124,93]/2(c[45]/2(a[97],a[97]),c[91,124,93]/2(c[45]/2(a[97],a[98]),c[91,124,93]/2(c[45]/2(a[97],a[99]),c[91,124,93]/2(c[45]/2(a[97],a[100]),c[91,124,93]/2(c[45]/2(a[98],a[97]),c[91,124,93]/2(c[45]/2(a[98],a[98]),c[91,124,93]/2(c[45]/2(a[98],a[99]),c[91,124,93]/2(c[45]/2(a[98],a[100]),c[91,124,93]/2(c[45]/2(a[99],a[97]),c[91,124,93]/2(c[45]/2(a[99],a[98]),c[91,124,93]/2(c[45]/2(a[99],a[99]),c[91,124,93]/2(c[45]/2(a[99],a[100]),nil)))))))))))))",
    "t_twm06 c[116,95,116,119,109,48,54]/1(c[91,124,93]/2(c[45]/2(a[97],a[97]),c[91,124,93]/2(c[45]/2(a[97],a[98]),c[91,124,93]/2(c[45]/2(a[97],a[99]),c[91,124,93]/2(c[45]/2(a[97],a[100]),c[91,124,93]/2(c[45]/2(a[98],a[97]),c[91,124,93]/2(c[45]/2(a[98],a[98]),c[91,124,93]/2(c[45]/2(a[98],a[99]),c[91,124,93]/2(c[45]/2(a[98],a[100]),c[91,124,93]/2(c[45]/2(a[99],a[97]),c[91,124,93]/2(c[45]/2(a[99],a[98]),c[91,124,93]/2(c[45]/2(a[99],a[99]),c[91,124,93]/2(c[45]/2(a[99],a[100]),nil)))))))))))))",
    "t_twm07 c[116,95,116,119,109,48,55]/1(nil)",
    "t_twm08 c[116,95,116,119,109,48,56]/1(c[114]/2(a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101]))",
    "t_twk01 c[116,95,116,119,107,48,49]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i10,c[91,124,93]/2(i20,nil))))))",
    "t_twv01 c[116,95,116,119,118,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,c[91,124,93]/2(i7,c[91,124,93]/2(i15,c[91,124,93]/2(i31,nil))))))",
    "t_twv02 c[116,95,116,119,118,48,50]/1(c[114]/2(a[110,111],a[121,101,115]))",
    "t_twq08 c[116,95,116,119,113,48,56]/1(c[45]/2(nil,c[91,124,93]/2(a[33],nil)))",
    "t_twq11 c[116,95,116,119,113,49,49]/1(c[91,124,93]/2(a[110,101,115,116,101,100],nil))"
]

@testset "tabled left and mutual recursion as swipl's (twl, twm)" begin
    gd, ld, st = _tw_load(_TW_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _) in _TW_CASES
        push!(kl, _tw_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TW_PINNED)
    for (k, p) in zip(kl, _TW_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # white-box: no component is left open and no worklist is left in the global list after the queries
    @test ld.tabling.component === nothing
end

@testset "the worklist rows are not vacuous" begin
    @test _TW_PINNED[1] == "ok"
    @test length(_TW_PINNED) == length(_TW_CASES) + 1
    for pre in ("twl", "twm", "twk", "twv", "twq")
        ids = [id for (id, _) in _TW_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _TW_PINNED if any(id -> startswith(l, "t_$id "), ids)]) ==
            length(ids)
    end
    line(id) = only(filter(l -> startswith(l, "t_$id "), _TW_PINNED))
    # the encoded answer starts with the predicate's own name `t_<id>`: compare the arguments, not the name
    ans(id) = replace(split(line(id), " "; limit=2)[2], r"^c\[[0-9,]*\]/1" => "")
    @test ans("twl03") != ans("twl04")          # a reachable pair through the cycle, a node with no exit
    @test ans("twm01") != ans("twm02")          # the two tables of one SCC hold different answers
    @test ans("twl01") == ans("twm05")          # left recursion through a second predicate gives the same closure
    @test ans("twm07") != ans("twm05")          # the empty answer set of a fresh variant, the full closure
    # twk01: BOTH chains of the two suspensions of one cluster (0-1-2 through tw_ka, 0-10-20 through tw_kb), one extractor
    @test all(occursin(v, ans("twk01")) for v in ("i1,", "i2,", "i10,", "i20,"))
    # twv01: the answers 1,3,7,15,31 pass through the two-frame continuation (tw_nb then tw_na), one extractor; the reversed order answers 1 and unbound
    @test all(occursin(v, ans("twv01")) for v in ("i1,", "i3,", "i7,", "i15,", "i31,"))
    # twv02: an ORDINARY reset/3 of call_continuation/1: a non-list fails (`no`), the empty list succeeds (`yes`)
    @test ans("twv02") == "(c[114]/2(a[110,111],a[121,101,115]))" &&
        ans("twv02") != ans("twv01")
    # twq08: the message hook saw NOTHING for the `fail` catcher (left of `-`) and the cut catcher `!` once (the positive control)
    @test ans("twq08") == "(c[45]/2(nil,c[91,124,93]/2(a[33],nil)))"
    # twq11: the inner component (tw_o2 called from tw_o1) has a parent: exactly one answer, `nested` (not `top`)
    @test ans("twq11") == "(c[91,124,93]/2(a[110,101,115,116,101,100],nil))"
    @test occursin("i12", ans("twl05"))         # 3 x 4 pairs: the cycle a-b-c-a and the exit c-d
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        @test _TW_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _TW_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _TW_CASES]
    else
        f = joinpath(mktempdir(), "tw_swipl.pl")
        write(f, _tw_text(_TW_PROGRAM, _TW_CASES))
        @test _tw_swipl_lines(f, ["t_$id" for (id, _) in _TW_CASES]) == _TW_PINNED
    end
end

# TB2K2 white-box rows: what no Prolog row reads (the scheduling of a worklist on its component, the cluster order). The values are
# upstream's code (pl-tabling.c wl_set_component :639-654, wkl_swap_clusters :4121-4138, tbl_wkl_make_follower :5305-5353), each cited at its row.
# UNVERIFIED on the kernel: nothing was compiled when these rows were written.
"A worklist of the clusters `kinds` (CLUSTER_ANSWERS / CLUSTER_SUSPENSIONS), linked in that order; `wl.riac` the rightmost answer cluster with a suspension cluster to its right."
function _tw_wl_of(kinds::Vector{Int})
    wl = LK.tbl_worklist{_TW}()
    cs = [LK.cluster{_TW}(k) for k in kinds]
    for c in cs
        LK.wkl_append_right(wl, c)
    end
    return wl, cs
end

@testset "TB2K2 white-box: wl_set_component schedules a worklist with work, once (TB2-C7)" begin
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    c = LK.tbl_component{_TW}()
    wl, (acp, scp) = _tw_wl_of([LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS])
    wl.riac = acp
    @test LK.wl_has_work(wl)                    # the non-empty side: an answer cluster left of a suspension cluster
    @test !wl.in_global_wl
    LK.wl_set_component(ld, wl, c)              # :639-654: `if (!wl->in_global_wl && wl_has_work(wl)) add_global_worklist(wl)`
    @test wl.component === c && !wl.executing
    @test wl.in_global_wl
    @test c.worklist !== nothing && length(c.worklist.members) == 1 &&
        c.worklist.members[1] === wl
    LK.wl_set_component(ld, wl, c)              # already scheduled: not queued a second time
    @test length(c.worklist.members) == 1
    # a worklist with NO work is not scheduled (the other branch of the same condition)
    c2 = LK.tbl_component{_TW}()
    wl2, _ = _tw_wl_of([LK.CLUSTER_SUSPENSIONS, LK.CLUSTER_ANSWERS])
    @test !LK.wl_has_work(wl2)
    LK.wl_set_component(ld, wl2, c2)
    @test wl2.component === c2 && !wl2.in_global_wl && c2.worklist === nothing
end

@testset "TB2K2 white-box: wkl_swap_clusters moves the answer cluster to the tail (TB2-W5)" begin
    wl, (acp, scp) = _tw_wl_of([LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS])
    wl.riac = acp
    @test wl.head === acp && wl.tail === scp    # the non-empty side: the list before the swap
    LK.wkl_swap_clusters(wl, acp, scp)          # :4121-4138: the couple trades places, `wl->tail = acp` when nothing follows
    @test wl.head === scp && wl.tail === acp
    @test scp.next === acp && acp.prev === scp
    @test acp.next === nothing && scp.prev === nothing
    @test wl.riac === nothing                   # update_riac: no answer cluster is left of `acp`
    # a cluster in front of and one behind the couple: both neighbours are re-linked, the tail stays
    wl2, (x, a2, s2, z) = _tw_wl_of([
        LK.CLUSTER_SUSPENSIONS, LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS,
        LK.CLUSTER_ANSWERS
    ])
    LK.wkl_swap_clusters(wl2, a2, s2)
    @test wl2.head === x && wl2.tail === z
    @test x.next === s2 && s2.next === a2 && a2.next === z && z.prev === a2 &&
        a2.prev === s2
end

@testset "TB2K2 white-box: '\$tbl_wkl_make_follower' sets riac and schedules (TB2-P5, TB2-P6)" begin
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    ctx = LK.foreign_context{_TW}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    function follower!(wl)
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.PL_put_int64(ld, a, LK.tbl_pointer!(ld, wl))
        rc = LK.pl_tbl_wkl_make_follower1_va(ld, a, 1, ctx)
        LK.PL_close_foreign_frame(ld, fid)
        return rc
    end
    # one answer cluster, one suspension cluster
    c = LK.tbl_component{_TW}()
    wl, (acp, scp) = _tw_wl_of([LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS])
    push!(acp.answers, 11)
    wl.component = c
    @test wl.riac === nothing && !wl.in_global_wl       # a leader: no riac yet, not scheduled
    @test follower!(wl) == LK.FTRUE
    @test wl.head === acp && wl.tail === scp && acp.next === scp
    @test wl.riac === acp                               # :5342-5345 (kills TB2-P6)
    @test LK.wl_has_work(wl)
    @test wl.in_global_wl && c.worklist !== nothing && length(c.worklist.members) == 1 &&
        c.worklist.members[1] === wl                    # :5349 (kills TB2-P5)
    # a1 s1 a2 s2: the answer clusters merge into the first, the suspension clusters into the first
    c2 = LK.tbl_component{_TW}()
    wl2, (a1, s1, a2, s2) = _tw_wl_of([
        LK.CLUSTER_ANSWERS, LK.CLUSTER_SUSPENSIONS, LK.CLUSTER_ANSWERS,
        LK.CLUSTER_SUSPENSIONS
    ])
    append!(a1.answers, [11, 12])
    append!(a2.answers, [21])
    wl2.component = c2
    @test follower!(wl2) == LK.FTRUE
    @test wl2.head === a1 && wl2.tail === s1 && a1.next === s1 && s1.next === nothing
    @test a1.answers == [11, 12, 21]
    @test wl2.riac === a1 && LK.wl_has_work(wl2)
    @test wl2.in_global_wl && length(c2.worklist.members) == 1 &&
        c2.worklist.members[1] === wl2
    # answers only: no suspension cluster, so no work and no scheduling; riac is still the answer cluster
    c3 = LK.tbl_component{_TW}()
    wl3, (a3,) = _tw_wl_of([LK.CLUSTER_ANSWERS])
    wl3.component = c3
    @test follower!(wl3) == LK.FTRUE
    @test wl3.riac === a3 && !wl3.in_global_wl && c3.worklist === nothing
end

@testset "TB2K2 white-box: table_complete_all resets has_scheduling_component of the top component (TB2-Q3)" begin
    # pl-tabling.c:6440-6533: `if (!c->parent) LD->tabling.has_scheduling_component = false`. A Prolog row cannot read it: the cleanup of
    # '$tbl_leader'/5 frees the component at once (free_component resets the flag again, pl-tabling.jl:347-349), and completing a running
    # leader's component from inside its own body is not a usable Prolog route. So the flag is read between the two, as the engine does:
    # a top component that is active and has a leader trie, no worklists, built by hand.
    gd = LK.PL_global_data{_TW}()
    ld = LK.PL_local_data{_TW}(gd)
    tr = LK.trie_create(_TW)
    LK.trie_serial!(gd, tr)
    c = LK.tbl_component{_TW}()
    c.leader = tr.serial
    ld.tabling.component = c
    ld.tabling.has_scheduling_component = true      # tbl_create_subcomponent: a leader was created
    ld.tabling.active_components = 1                # the component is active
    ld.table_flags_drop_intermediate = 0            # no drop step: the plain completion
    @test c.parent === nothing && c.status == LK.SCC_ACTIVE &&
        ld.tabling.has_scheduling_component   # the non-empty side
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.PL_put_int64(ld, a, LK.tbl_pointer!(ld, c))
    LK.PL_put_variable(ld, a + 1)
    LK.PL_put_variable(ld, a + 2)
    @test LK.table_complete_all(ld, a, a + 1, a + 2, 0)
    @test c.status == LK.SCC_COMPLETED
    @test LK.PL_unify_atom(ld, a + 1, _tws("final"))   # a top component is `final`, one with a parent `complete`
    @test !ld.tabling.has_scheduling_component         # kills TB2-Q3
    @test ld.tabling.active_components == 0
    LK.PL_close_foreign_frame(ld, fid)
end
