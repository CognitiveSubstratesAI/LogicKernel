# ORIGINAL: a LIVE differential of the well-founded semantics of pl-tabling.c (TAB1 TB4; audit D-0477) against swipl at the pin
# (swipl-devel 18168e62, 10.1.20): the global delay list (`'$tbl_delay_list'/1`, `'$tbl_set_delay_list'/1`,
# `'$tbl_add_global_delays'/2`, pl-tabling.c:1593-1740), the worklist negation (`'$tbl_wkl_negative'/1`, `'$tbl_wkl_is_false'/1`,
# :5374-5403), the answer completion predicates (`'$tbl_force_truth_value'/3`, `'$tbl_set_answer_completed'/1`,
# `'$tbl_is_answer_completed'/1`), `'$tbl_answer_update_dl'/2` (:7229-7256) and library(wfs) on undefined answers
# (`call_delays/2`, `answer_residual/2`, `call_residual_program/2`). Groups: wf0x/wf1x = the predicates on their own (the delay list,
# the type errors), wf2x/wf3x = a WFS program (`wp :- tnot(wq). wq :- tnot(wp).`, `wr :- tnot(wr).`, a positive delay `wv :- wp.`).
#   * Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_variant_swipl.jl's (TB1; `enc`oded answers). The program is the same text on both sides (real tabling: the rows
#     from wf20 on need the whole TAB1 stack, TB1 to TB5).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs); with `swipl` on PATH the live answers are
#     compared with the pins too. A trie blob is never printed: wf32 projects the delay `ATrie+Data` to same/diff and int (swipl's
#     data of a ground answer is the node's address, the kernel's the node id: docs/architecture.md "TAB1 TB4").
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _WF = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_wfs(x) = lk_sym(_WF, Symbol(x))

_wf_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _wf_enc(t::_WF, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _wf_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _wf_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _wf_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_wf_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _WF_DRIVER = raw"""
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

function _wf_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _WF_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_wf_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _wf_load(program::String)
    f = joinpath(mktempdir(), "tabling_wfs.pl")
    write(f, _wf_text(program, _WF_CASES))
    gd = LK.PL_global_data{_WF}()
    ld = LK.PL_local_data{_WF}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _wf_enc(ball::_WF))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _wf_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_wfs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_WF, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _wf_enc(mk_expr(_WF, _WF[_wfs(pred), lk_answers(ld, (a:a)...)...])))
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

const _WF_PROGRAM = raw"""
:- use_module(library(wfs)).
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table wp/0, wq/0, wr/0, ws/1, wu/0, wv/0.
wp :- tnot(wq).
wq :- tnot(wp).
wr :- tnot(wr).
ws(X) :- member(X, [1, 2]), tnot(wu).
wu :- fail.
wv :- wp.
"""

const _WF_CASES = [
    ("wf01", raw"'$tbl_delay_list'(L), R = L"),
    (
        "wf02",
        raw"'$tbl_set_delay_list'([x]), '$tbl_delay_list'(L), '$tbl_set_delay_list'([]), R = L"
    ),
    ("wf03", raw"'$tbl_add_global_delays'([a], D), R = D"),
    (
        "wf04",
        raw"'$tbl_set_delay_list'([g]), '$tbl_add_global_delays'([a], D), '$tbl_set_delay_list'([]), R = D"
    ),
    ("wf05", raw"'$tbl_add_global_delays'([], D), R = D"),
    ("wf06", raw"'$tbl_wkl_negative'(foo), R = ok"),
    ("wf07", raw"'$tbl_wkl_is_false'(foo), R = ok"),
    ("wf08", raw"'$tbl_is_answer_completed'(foo), R = ok"),
    ("wf09", raw"'$tbl_set_answer_completed'(foo), R = ok"),
    ("wf10", raw"'$tbl_force_truth_value'(foo, true, C), R = C"),
    ("wf11", raw"'$tbl_answer_update_dl'(foo, _), R = ok"),
    ("wf20", raw"call_delays(wp, D), R = D"),
    ("wf21", raw"call_delays(wq, D), R = D"),
    ("wf22", raw"call_delays(wr, D), R = D"),
    ("wf23", raw"findall(X-D, call_delays(ws(X), D), L), R = L"),
    ("wf24", raw"call_delays(wv, D), R = D"),
    ("wf25", raw"tm_yn(wp, R)"),
    ("wf26", raw"tm_yn(wu, R)"),
    ("wf27", raw"findall(B, answer_residual(wp, B), L), R = L"),
    ("wf28", raw"call_residual_program(wv, P0), msort(P0, P), R = P"),
    ("wf29", raw"tm_yn(call_delays(wp, true), R)"),
    (
        "wf30",
        raw"'$tbl_existing_variant_table'(0, user:wp, T, _, _), tm_yn('$tbl_is_answer_completed'(T), R)"
    ),
    (
        "wf31",
        raw"'$tbl_existing_variant_table'(0, user:wv, T, _, _), findall(S, '$tbl_answer_update_dl'(T, S), L), '$tbl_delay_list'(DL), R = r(L, DL)"
    ),
    (
        "wf32",
        raw"'$tbl_existing_variant_table'(0, user:wv, T, _, _), '$tbl_answer_update_dl'(T, S), '$tbl_delay_list'([A+D]), ( A == T -> X = same ; X = diff ), ( integer(D) -> Y = int ; Y = D ), R = r(S, X, Y)"
    ),
    (
        "wf33",
        raw"'$tbl_existing_variant_table'(0, user:ws(_), T, _, _), findall(S, '$tbl_answer_update_dl'(T, S), L0), msort(L0, L), '$tbl_delay_list'(DL), R = r(L, DL)"
    )
]

const _WF_PINNED = [
    "ok",
    "t_wf01 c[116,95,119,102,48,49]/1(nil)",
    "t_wf02 c[116,95,119,102,48,50]/1(c[91,124,93]/2(a[120],nil))",
    "t_wf03 c[116,95,119,102,48,51]/1(c[91,124,93]/2(a[97],nil))",
    "t_wf04 c[116,95,119,102,48,52]/1(c[91,124,93]/2(a[103],c[91,124,93]/2(a[97],nil)))",
    "t_wf05 c[116,95,119,102,48,53]/1(nil)",
    "t_wf06 c[116,95,119,102,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[119,111,114,107,108,105,115,116],a[102,111,111])))",
    "t_wf07 c[116,95,119,102,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[119,111,114,107,108,105,115,116],a[102,111,111])))",
    "t_wf08 c[116,95,119,102,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[102,111,111])))",
    "t_wf09 c[116,95,119,102,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[102,111,111])))",
    "t_wf10 c[116,95,119,102,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,100,100,114,101,115,115],a[102,111,111])))",
    "t_wf11 c[116,95,119,102,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[102,111,111])))",
    "t_wf20 c[116,95,119,102,50,48]/1(a[119,112])",
    "t_wf21 c[116,95,119,102,50,49]/1(a[119,113])",
    "t_wf22 c[116,95,119,102,50,50]/1(a[119,114])",
    "t_wf23 c[116,95,119,102,50,51]/1(c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),nil)))",
    "t_wf24 c[116,95,119,102,50,52]/1(a[119,118])",
    "t_wf25 c[116,95,119,102,50,53]/1(a[121,101,115])",
    "t_wf26 c[116,95,119,102,50,54]/1(a[110,111])",
    "t_wf27 c[116,95,119,102,50,55]/1(c[91,124,93]/2(c[116,110,111,116]/1(a[119,113]),nil))",
    "t_wf28 c[116,95,119,102,50,56]/1(c[91,124,93]/2(c[58,45]/2(a[119,112],c[116,110,111,116]/1(a[119,113])),c[91,124,93]/2(c[58,45]/2(a[119,113],c[116,110,111,116]/1(a[119,112])),c[91,124,93]/2(c[58,45]/2(a[119,118],a[119,112]),nil))))",
    "t_wf29 c[116,95,119,102,50,57]/1(a[110,111])",
    "t_wf30 c[116,95,119,102,51,48]/1(a[110,111])",
    "t_wf31 c[116,95,119,102,51,49]/1(c[114]/2(c[91,124,93]/2(a[114,101,116],nil),nil))",
    "t_wf32 c[116,95,119,102,51,50]/1(c[114]/3(a[114,101,116],a[115,97,109,101],a[105,110,116]))",
    "t_wf33 c[116,95,119,102,51,51]/1(c[114]/2(c[91,124,93]/2(c[114,101,116]/1(i1),c[91,124,93]/2(c[114,101,116]/1(i2),nil)),nil))"
]

@testset "WFS and the delay list as swipl's (wf0, wf1, wf2, wf3)" begin
    gd, ld, st = _wf_load(_WF_PROGRAM)
    @test st == "ok"
    @test ld.tabling.delay_list != 0                          # init_delay_list at emptyStacks! (pl-setup.c:1558)
    kl = String[st]
    for (id, _) in _WF_CASES
        push!(kl, _wf_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_WF_PINNED)
    for (k, p) in zip(kl, _WF_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the WFS rows are not vacuous" begin
    @test _WF_PINNED[1] == "ok"
    @test length(_WF_PINNED) == length(_WF_CASES) + 1
    for pre in ("wf0", "wf1", "wf2", "wf3")
        ids = [id for (id, _) in _WF_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _WF_PINNED if any(id -> startswith(l, "t_$id "), ids)]) ==
            length(ids)
    end
    ans(id) = split(only(filter(l -> startswith(l, "t_$id "), _WF_PINNED)), " "; limit=2)[2]
    @test ans("wf01") != ans("wf02")          # the empty delay list, then one set
    @test ans("wf03") != ans("wf04")          # Delays0 alone, then the global list in front of it
    @test ans("wf20") != ans("wf23")          # an undefined answer has its delay, an unconditional one `true`
    @test ans("wf25") != ans("wf26")          # undefined succeeds, false fails
    @test ans("wf31") != ans("wf33")          # a conditional answer extends the delay list, unconditional ones do not
end

@testset "the WFS pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB4 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        @test _WF_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _WF_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _WF_CASES]
    else
        f = joinpath(mktempdir(), "wf_swipl.pl")
        write(f, _wf_text(_WF_PROGRAM, _WF_CASES))
        @test _wf_swipl_lines(f, ["t_$id" for (id, _) in _WF_CASES]) == _WF_PINNED
    end
end
