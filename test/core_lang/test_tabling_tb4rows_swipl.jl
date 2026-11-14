# ORIGINAL: LIVE kill rows for the well-founded semantics of pl-tabling.c (TAB1 TB4, batch 3; audit D-0635) against swipl at the pin
# (swipl-devel 18168e62, 10.1.20). Companion of test_tabling_wfs_swipl.jl (the first rows wf01-wf33); this file holds the rows its
# header left open, one program text per group, each group in a FRESH database (rows R5-R12 of tools/mutants/TB4.py):
#   * R5, R6: `'$tbl_add_global_delays'/2` with a two-element and a one-element global list and with a [] argument (mutants P5, P6).
#   * R9, R10 (simplification of a conditional answer to false and to true; mutants S1, S3, S4) are NOT here: they run answer completion to its
#     end, whose cleanup calls TB5's `'$tbl_destroy_table'/1`; they live in test_tabling_tb4_tb5_swipl.jl (the integration branch, with TB5).
#   * R11: `'$tbl_set_answer_completed'/1` then `'$tbl_is_answer_completed'/1` on a table inside its own evaluation (a worklist exists)
#     and on a complete one (mutant C2).
#   * R12: `'$tbl_force_truth_value'/3` on the answer node of an undefined pair, true and false (the count it returns, the two
#     truths afterwards: mutants S6, S7); an answer whose node id is above 65535 (D8); forty conditional answers of one fresh
#     database whose residuals must each name their own answer (D5).
#   * Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_variant_swipl.jl's (`enc`oded answers), the program text the same on both sides.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs); with `swipl` on PATH the live answers are
#     compared with the pins too. A trie blob is never printed.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the verifier runs each row
#     against its mutant (evidence/TAB1/tb4kb_verify.md).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TR_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_TR_sym(x) = lk_sym(_TR_T, Symbol(x))

_TR_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _TR_enc(t::_TR_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _TR_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _TR_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _TR_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_TR_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TR_DRIVER = raw"""
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

function _TR_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TR_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_TR_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _TR_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb4rows.pl")
    write(f, _TR_text(program, cases))
    gd = LK.PL_global_data{_TR_T}()
    ld = LK.PL_local_data{_TR_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _TR_enc(ball::_TR_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _TR_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_TR_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TR_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _TR_enc(mk_expr(_TR_T, _TR_T[_TR_sym(pred), lk_answers(ld, (a:a)...)...]))
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


const _TR_PROG_LIST = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
"""

const _TR_CASES_LIST = [
    (
        "r05",
        raw"'$tbl_set_delay_list'([g, h]), '$tbl_add_global_delays'([a], D), '$tbl_set_delay_list'([]), R = D"
    ),
    (
        "r06",
        raw"'$tbl_set_delay_list'([g]), '$tbl_add_global_delays'([], D), '$tbl_set_delay_list'([]), R = D"
    ),
    (
        "r07",
        raw"'$tbl_set_delay_list'([g, h, i]), '$tbl_add_global_delays'([a, b], D), '$tbl_set_delay_list'([]), R = D"
    )
]

const _TR_PINS_LIST = [
    "ok",
    "t_r05 c[116,95,114,48,53]/1(c[91,124,93]/2(a[103],c[91,124,93]/2(a[104],c[91,124,93]/2(a[97],nil))))",
    "t_r06 c[116,95,114,48,54]/1(c[91,124,93]/2(a[103],nil))",
    "t_r07 c[116,95,114,48,55]/1(c[91,124,93]/2(a[103],c[91,124,93]/2(a[104],c[91,124,93]/2(a[105],c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil))))))"
]

const _TR_PROG_ACOMP = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table r11a/1, r11b/0.
r11a(R) :- '$tbl_existing_variant_table'(0, user:r11a(_), T, _, _), tm_yn('$tbl_is_answer_completed'(T), R0), '$tbl_set_answer_completed'(T), tm_yn('$tbl_is_answer_completed'(T), R1), R = r(R0, R1).
r11b.
"""

const _TR_CASES_ACOMP = [
    ("r11a", raw"r11a(X), R = X"),
    (
        "r11b",
        raw"r11b, '$tbl_existing_variant_table'(0, user:r11b, T, _, _), tm_yn('$tbl_is_answer_completed'(T), R0), '$tbl_set_answer_completed'(T), tm_yn('$tbl_is_answer_completed'(T), R1), R = r(R0, R1)"
    )
]

const _TR_PINS_ACOMP = [
    "ok",
    "t_r11a c[116,95,114,49,49,97]/1(c[114]/2(a[110,111],a[121,101,115]))",
    "t_r11b c[116,95,114,49,49,98]/1(c[114]/2(a[121,101,115],a[121,101,115]))"
]

const _TR_PROG_FORCE = raw"""
:- use_module(library(wfs)).
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table f1a/0, f1b/0, f2a/0, f2b/0.
f1a :- tnot(f1b).
f1b :- tnot(f1a).
f2a :- tnot(f2b).
f2b :- tnot(f2a).
"""

const _TR_CASES_FORCE = [
    (
        "r12a",
        raw"tm_yn(f1a, R0), '$tbl_existing_variant_table'(0, user:f1a, T, _, Sk), '$trie_gen_node'(T, Sk, Leaf), '$tbl_force_truth_value'(Leaf, true, C), call_delays(f1a, DA), tm_yn(f1b, YB), R = r(R0, C, DA, YB)"
    ),
    (
        "r12b",
        raw"tm_yn(f2a, R0), '$tbl_existing_variant_table'(0, user:f2a, T, _, Sk), '$trie_gen_node'(T, Sk, Leaf), '$tbl_force_truth_value'(Leaf, false, C), tm_yn(f2a, YA), call_delays(f2b, DB), R = r(R0, C, YA, DB)"
    )
]

const _TR_PINS_FORCE = [
    "ok",
    "t_r12a c[116,95,114,49,50,97]/1(c[114]/4(a[121,101,115],i2,a[116,114,117,101],a[110,111]))",
    "t_r12b c[116,95,114,49,50,98]/1(c[114]/4(a[121,101,115],i2,a[110,111],a[116,114,117,101]))"
]

const _TR_PROG_BIG = raw"""
:- use_module(library(wfs)).
:- table d8a/1, d8n/0, d8m/0.
d8a(L) :- numlist(1, 40000, L), tnot(d8n).
d8n :- tnot(d8m).
d8m :- tnot(d8n).
"""

const _TR_CASES_BIG = [
    (
    "r12c",
    raw"d8a(_), call_delays(d8a(L0), D0), ( D0 == true -> R0 = true ; R0 = cond ), '$tbl_existing_variant_table'(0, user:d8a(_), T, _, Sk), '$trie_gen_node'(T, Sk, Leaf), '$tbl_force_truth_value'(Leaf, true, C), call_delays(d8a(L), D), ( D == true -> R1 = true ; R1 = cond ), length(L0, N0), length(L, N), R = r(R0, C, R1, N0, N)"
)
]

const _TR_PINS_BIG = [
    "ok",
    "t_r12c c[116,95,114,49,50,99]/1(c[114]/5(a[99,111,110,100],i1,a[116,114,117,101],i40000,i40000))"
]

const _TR_PROG_REF = raw"""
:- use_module(library(wfs)).
:- table d5c/1, d5b/1, d5p/0, d5q/0.
d5p :- tnot(d5q).
d5q :- tnot(d5p).
d5c(X) :- numlist(1, 40, L), member(X, L), d5p.
d5b(X) :- d5c(X).
"""

const _TR_CASES_REF = [
    (
    "r12d",
    raw"findall(X, d5b(X), L1), length(L1, N1), findall(X, ( answer_residual(d5b(X), B), B == d5c(X) ), Good), length(Good, N), R = r(N1, N)"
)
]

const _TR_PINS_REF = [
    "ok",
    "t_r12d c[116,95,114,49,50,100]/1(c[114]/2(i40,i40))"
]

const _TR_GROUPS = [
    (
        key="LIST",
        label="R5, R6: the global delay list of `'\$tbl_add_global_delays'/2` (P5, P6)",
        program=_TR_PROG_LIST,
        cases=_TR_CASES_LIST,
        pins=_TR_PINS_LIST
    ),
    (
        key="ACOMP",
        label="R11: `'\$tbl_set_answer_completed'/1` on a table with a worklist (C2)",
        program=_TR_PROG_ACOMP,
        cases=_TR_CASES_ACOMP,
        pins=_TR_PINS_ACOMP
    ),
    (
        key="FORCE",
        label="R12: `'\$tbl_force_truth_value'/3` true and false on an undefined pair (S6, S7)",
        program=_TR_PROG_FORCE,
        cases=_TR_CASES_FORCE,
        pins=_TR_PINS_FORCE
    ),
    (
        key="BIG",
        label="R12: an answer node above 65535 (D8)",
        program=_TR_PROG_BIG,
        cases=_TR_CASES_BIG,
        pins=_TR_PINS_BIG
    ),
    (
        key="REF",
        label="R12: forty conditional answers of one fresh database (D5)",
        program=_TR_PROG_REF,
        cases=_TR_CASES_REF,
        pins=_TR_PINS_REF
    )
]


@testset "TB4 rows R5-R12 as swipl's: $(g.label)" for g in _TR_GROUPS
    gd, ld, st = _TR_load(g.program, g.cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _TR_ask(gd, ld, "t_$id"))
    end
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_TR_ask`
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for (k, p) in zip(kl, g.pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _TR_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end

_TR_group(key) = only(filter(g -> g.key == key, _TR_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _TR_ans(key, id)
    g = _TR_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

@testset "the TB4 rows are not vacuous" begin
    for g in _TR_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
        end
    end
    # R5, R6: the order of the global list in front of the argument, a list a reversal would change
    @test _TR_atoms(_TR_ans("LIST", "r05")) == ["g", "h", "a"]
    @test _TR_atoms(_TR_ans("LIST", "r06")) == ["g"]
    @test _TR_atoms(_TR_ans("LIST", "r07")) == ["g", "h", "i", "a", "b"]
    # R11: set on a table with a worklist (no, then yes), a complete table is yes either way
    @test _TR_atoms(_TR_ans("ACOMP", "r11a")) == ["no", "yes"]
    @test _TR_atoms(_TR_ans("ACOMP", "r11b")) == ["yes", "yes"]
    @test _TR_ans("ACOMP", "r11a") != _TR_ans("ACOMP", "r11b")
    # R12: two answers changed on both sides of the undefined pair; the truths are mirrored
    @test _TR_atoms(_TR_ans("FORCE", "r12a")) == ["yes", "true", "no"]
    @test _TR_atoms(_TR_ans("FORCE", "r12b")) == ["yes", "no", "true"]
    @test occursin("i2", _TR_ans("FORCE", "r12a"))
    @test occursin("i2", _TR_ans("FORCE", "r12b"))
    @test _TR_ans("FORCE", "r12a") != _TR_ans("FORCE", "r12b")
    @test _TR_atoms(_TR_ans("BIG", "r12c")) == ["cond", "true"]
    @test occursin("i1,", _TR_ans("BIG", "r12c"))          # the count of answers made unconditional
    @test endswith(_TR_ans("BIG", "r12c"), "i40000,i40000))")   # `_TR_ans` is the case's whole pinned answer: `t_r12c` wrapping the r/5 term
    @test _TR_ans("REF", "r12d") == "c[116,95,114,49,50,100]/1(c[114]/2(i40,i40))"   # the same: `t_r12d` wrapping r(40, 40)
end

@testset "the TB4 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB4 ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _TR_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _TR_GROUPS
            f = joinpath(mktempdir(), "tb4rows_swipl.pl")
            write(f, _TR_text(g.program, g.cases))
            @test _TR_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
