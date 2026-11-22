# ORIGINAL: R2 LB6b-2's gate - a source file loaded again (a reconsult, `startConsult` -> `startReconsultFile` ... `endConsult` -> `endReconsult`) against swipl-devel 18168e62 (pl-srcfile.c startReconsultFile :900-953, delete_old_predicates, end_reconsult_proc, endReconsult, fix_module, registerReloadModule; pl-proc.c reconsultFinalizePredicate; pl-modul.c declareModule's reload arm); upstream tests it through Prolog (src/Tests/core/test_reload.pl and tests/unprotected/reload), which needs the loader.
# test/db/test_reload_swipl.jl - rl01-rl12, scenarios of ONE file (or two) loaded in turn on a fresh database, then probed:
#   * STEPS: (scenario, file, text) loaded in order with `load_file!` (the kernel) and `consult/1` (swipl: the driver writes the same text to the same path first);
#     a second load of a path is a reload. The printed `ld <id> <n> ok` lines say each load succeeded (a ball is `exc <enc>`).
#   * PROBES: a program `t_<id>(R)` consulted last, every answer encoded as the driver's `enc/1` (test_miss_preds_swipl.jl's pattern). EVERY expected
#     line is the pinned swipl's own answer (swipl 10.1.20 at 18168e62, run live when the rows were written; the same driver compares them live below).
#   * rl01 clause list after a reload (changed/removed/added clauses), the file's clause count and load count; rl02 a predicate the reload drops (defined yes -> no, the
#     existence error); rl03 a predicate the reload adds; rl04 an identical reload keeps the clauses (the same clause references); rl05 discontiguous and an order change;
#     rl06 a module reload (exports shrink; the user's import of a dropped export); rl07 dynamic / static / dynamic across three versions; rl08 a multifile predicate
#     (the other file's clauses stay); rl09 a tabled predicate whose `:- table` is dropped; rl10 a reload that only declares the predicate `dynamic`; rl11 the `untable` event
#     of a dropped table; rl12 a table kept: no event.
#   * WHITE-BOX: after the loads no reload context is left (`sf.reload`, `gd.reload_generation`, `ld.reload_nesting`).
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - the reload rides the term layer through the loader
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rls(x) = lk_sym(_RL, Symbol(x))

_rl_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _rl_enc(t::_RL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _rl_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _rl_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _rl_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_rl_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: load each step (write, consult), consult the probe program, then every answer of each t_<id>/1, `enc`oded
const _RL_DRIVER = raw"""
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
encargs(I, A, T, S0, S) :- call(arg, I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_step(step(Id, I, File, Codes)) :-
    setup_call_cleanup(open(File, write, O), format(O, "~s", [Codes]), close(O)),
    catch(( consult(File), St = ok ), E, St = exc(E)),
    format("ld ~w ~w ", [Id, I]),
    ( St == ok -> writeln(ok) ; St = exc(B), write('exc '), enc(B), nl ).
fz_run(Steps, Probe, Ns) :-
    forall(member(S, Steps), fz_step(S)),
    catch(( consult(Probe), P = ok ), E, P = exc(E)),
    ( P == ok -> writeln(probe_ok) ; P = exc(B), write('probe_exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

# (scenario, file, text), loaded IN ORDER; the second load of a file is the reload
const _RL_STEPS = [
    ("rl01", "rl01.pl", "rl01_p(1).\nrl01_p(2).\nrl01_p(3).\n"),
    ("rl01", "rl01.pl", "rl01_p(1).\nrl01_p(3).\nrl01_p(4).\n"),
    ("rl02", "rl02.pl", "rl02_a(1).\nrl02_b(2).\n"),
    ("rl02", "rl02.pl", "rl02_a(3).\n"),
    ("rl03", "rl03.pl", "rl03_a(1).\n"),
    ("rl03", "rl03.pl", "rl03_a(1).\nrl03_b(2).\nrl03_b(3).\n"),
    ("rl04", "rl04.pl", "rl04_p(1).\nrl04_p(2).\n:- nth_clause(rl04_p(_), 1, R), assertz(rl04_ref1(R)).\n"),
    ("rl04", "rl04.pl", "rl04_p(1).\nrl04_p(2).\n:- nth_clause(rl04_p(_), 1, R), assertz(rl04_ref1(R)).\n"),
    ("rl05", "rl05.pl", ":- discontiguous rl05_p/1.\nrl05_p(1).\nrl05_q(a).\nrl05_p(2).\n"),
    ("rl05", "rl05.pl", "rl05_p(2).\nrl05_p(1).\n"),
    ("rl06", "rl06.pl", ":- module(rl06, [rl06_a/1, rl06_b/1]).\nrl06_a(1).\nrl06_b(2).\n"),
    ("rl06", "rl06.pl", ":- module(rl06, [rl06_a/1]).\nrl06_a(3).\n"),
    ("rl07", "rl07.pl", ":- dynamic rl07_p/1.\nrl07_p(1).\n:- ( predicate_property(rl07_p(_), dynamic) -> assertz(rl07_log(1, dyn)) ; assertz(rl07_log(1, st)) ).\n"),
    ("rl07", "rl07.pl", "rl07_p(2).\n:- ( predicate_property(rl07_p(_), dynamic) -> assertz(rl07_log(2, dyn)) ; assertz(rl07_log(2, st)) ).\n"),
    ("rl07", "rl07.pl", ":- dynamic rl07_p/1.\nrl07_p(3).\n:- ( predicate_property(rl07_p(_), dynamic) -> assertz(rl07_log(3, dyn)) ; assertz(rl07_log(3, st)) ).\n"),
    ("rl08", "rl08a.pl", ":- multifile rl08_m/1.\nrl08_m(a1).\nrl08_m(a2).\n"),
    ("rl08", "rl08b.pl", ":- multifile rl08_m/1.\nrl08_m(b1).\n"),
    ("rl08", "rl08a.pl", ":- multifile rl08_m/1.\nrl08_m(a3).\nrl08_m(a1).\n"),
    ("rl09", "rl09.pl", ":- table rl09_t/1.\nrl09_t(1).\nrl09_t(2).\n"),
    ("rl09", "rl09.pl", "rl09_t(1).\n"),
    ("rl10", "rl10.pl", "rl10_p(1).\nrl10_p(2).\n"),
    ("rl10", "rl10.pl", ":- dynamic rl10_p/1.\n"),
    ("rl11", "rl11h.pl", ":- dynamic rl11_seen/1.\nrl11_ev(E) :- assertz(rl11_seen(E)).\n:- prolog_listen(untable, rl11_ev).\n"),
    ("rl11", "rl11.pl", ":- table rl11_t/1.\nrl11_t(1).\nrl11_t(2).\n"),
    ("rl11", "rl11.pl", "rl11_t(1).\n"),
    ("rl12", "rl12h.pl", ":- dynamic rl12_seen/1.\nrl12_ev(E) :- assertz(rl12_seen(E)).\n:- prolog_listen(untable, rl12_ev).\n"),
    ("rl12", "rl12.pl", ":- table rl12_t/1.\nrl12_t(1).\nrl12_t(2).\n"),
    ("rl12", "rl12.pl", ":- table rl12_t/1.\nrl12_t(5).\n"),
]

# (id, goal binding R): the probe program's `t_<id>(R)`
const _RL_CASES = [
    ("rl01", "findall(X, rl01_p(X), L), predicate_property(rl01_p(_), number_of_clauses(N)), predicate_property(rl01_p(_), file(F)), '\$source_file_property'(F, number_of_clauses, SN), '\$source_file_property'(F, load_count, C), R = L-N-SN-C"),
    ("rl02", "( predicate_property(rl02_a(_), defined) -> A = yes ; A = no ), ( predicate_property(rl02_b(_), defined) -> B = yes ; B = no ), findall(X, rl02_a(X), L), R = A-B-L"),
    ("rl02e", "catch(( rl02_b(_), R = succeeded ), error(E, _), R = E)"),
    ("rl03", "findall(X, rl03_a(X), L1), findall(X, rl03_b(X), L2), predicate_property(rl03_b(_), file(F)), file_base_name(F, B), R = L1-L2-B"),
    ("rl04", "findall(X, rl04_p(X), L), findall(S, ( rl04_ref1(A), rl04_ref1(B), ( A == B -> S = same ; S = diff ) ), Ss), R = L-Ss"),
    ("rl05", "findall(X, rl05_p(X), L), ( predicate_property(rl05_p(_), discontiguous) -> D = yes ; D = no ), ( predicate_property(rl05_q(_), defined) -> Q = yes ; Q = no ), R = L-D-Q"),
    ("rl06", "module_property(rl06, exports(E0)), msort(E0, E), findall(X, rl06:rl06_a(X), L), catch(( rl06:rl06_b(_), B = succeeded ), error(Er, _), B = Er), R = E-L-B"),
    ("rl06u", "catch(( rl06_b(_), R = succeeded ), error(E, _), R = E)"),
    ("rl07", "findall(V-K, rl07_log(V, K), Log), findall(X, rl07_p(X), L), ( predicate_property(rl07_p(_), dynamic) -> D = dyn ; D = st ), R = Log-L-D"),
    ("rl08", "findall(X, rl08_m(X), L), predicate_property(rl08_m(_), number_of_clauses(N)), R = L-N"),
    ("rl09", "findall(X, rl09_t(X), L), ( predicate_property(rl09_t(_), tabled) -> T = yes ; T = no ), R = L-T"),
    ("rl10", "findall(X, rl10_p(X), L), predicate_property(rl10_p(_), number_of_clauses(N)), ( predicate_property(rl10_p(_), dynamic) -> D = dyn ; D = st ), R = L-N-D"),
    ("rl11", "findall(E, rl11_seen(E), Es), findall(X, rl11_t(X), L), ( predicate_property(rl11_t(_), tabled) -> T = yes ; T = no ), R = Es-L-T"),
    ("rl12", "findall(E, rl12_seen(E), Es), findall(X, rl12_t(X), L), ( predicate_property(rl12_t(_), tabled) -> T = yes ; T = no ), R = Es-L-T"),
]

# swipl's answers (pinned 18168e62, run live): `ld` lines, `probe_ok`, then `t_<id>` and its encoded answer
const _RL_EXPECTED = [
    "ld rl01 1 ok",
    "ld rl01 2 ok",
    "ld rl02 1 ok",
    "ld rl02 2 ok",
    "ld rl03 1 ok",
    "ld rl03 2 ok",
    "ld rl04 1 ok",
    "ld rl04 2 ok",
    "ld rl05 1 ok",
    "ld rl05 2 ok",
    "ld rl06 1 ok",
    "ld rl06 2 ok",
    "ld rl07 1 ok",
    "ld rl07 2 ok",
    "ld rl07 3 ok",
    "ld rl08 1 ok",
    "ld rl08 2 ok",
    "ld rl08 3 ok",
    "ld rl09 1 ok",
    "ld rl09 2 ok",
    "ld rl10 1 ok",
    "ld rl10 2 ok",
    "ld rl11 1 ok",
    "ld rl11 2 ok",
    "ld rl11 3 ok",
    "ld rl12 1 ok",
    "ld rl12 2 ok",
    "ld rl12 3 ok",
    "probe_ok",
    "t_rl01 c[116,95,114,108,48,49]/1(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),i3),i3),i2))",
    "t_rl02 c[116,95,114,108,48,50]/1(c[45]/2(c[45]/2(a[121,101,115],a[110,111]),c[91,124,93]/2(i3,nil)))",
    "t_rl02e c[116,95,114,108,48,50,101]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[114,108,48,50,95,98],i1)))",
    "t_rl03 c[116,95,114,108,48,51]/1(c[45]/2(c[45]/2(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),a[114,108,48,51,46,112,108]))",
    "t_rl04 c[116,95,114,108,48,52]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[115,97,109,101],c[91,124,93]/2(a[115,97,109,101],c[91,124,93]/2(a[115,97,109,101],c[91,124,93]/2(a[115,97,109,101],nil))))))",
    "t_rl05 c[116,95,114,108,48,53]/1(c[45]/2(c[45]/2(c[91,124,93]/2(i2,c[91,124,93]/2(i1,nil)),a[110,111]),a[110,111]))",
    "t_rl06 c[116,95,114,108,48,54]/1(c[45]/2(c[45]/2(c[91,124,93]/2(c[47]/2(a[114,108,48,54,95,97],i1),nil),c[91,124,93]/2(i3,nil)),c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[114,108,48,54],c[47]/2(a[114,108,48,54,95,98],i1)))))",
    "t_rl06u c[116,95,114,108,48,54,117]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[114,108,48,54],c[47]/2(a[114,108,48,54,95,98],i1))))",
    "t_rl07 c[116,95,114,108,48,55]/1(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(i1,a[100,121,110]),c[91,124,93]/2(c[45]/2(i2,a[100,121,110]),c[91,124,93]/2(c[45]/2(i3,a[100,121,110]),nil))),c[91,124,93]/2(i3,nil)),a[100,121,110]))",
    "t_rl08 c[116,95,114,108,48,56]/1(c[45]/2(c[91,124,93]/2(a[97,51],c[91,124,93]/2(a[97,49],c[91,124,93]/2(a[98,49],nil))),i3))",
    "t_rl09 c[116,95,114,108,48,57]/1(c[45]/2(c[91,124,93]/2(i1,nil),a[110,111]))",
    "t_rl10 c[116,95,114,108,49,48]/1(c[45]/2(c[45]/2(nil,i0),a[100,121,110]))",
    "t_rl11 c[116,95,114,108,49,49]/1(c[45]/2(c[45]/2(c[91,124,93]/2(c[58]/2(a[117,115,101,114],c[47]/2(a[114,108,49,49,95,116],i1)),nil),c[91,124,93]/2(i1,nil)),a[110,111]))",
    "t_rl12 c[116,95,114,108,49,50]/1(c[45]/2(c[45]/2(nil,c[91,124,93]/2(i5,nil)),a[121,101,115]))",
]

_rl_probe_program() = join(
    [
    "t_$(id)(R) :- catch(($(g)), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in _RL_CASES
]
)

# the step number of each load within its scenario (1, 2, 3...), in the order of `_RL_STEPS`
function _rl_numbers()::Vector{Int}
    seen = Dict{String, Int}()
    return [(seen[id] = get(seen, id, 0) + 1) for (id, _, _) in _RL_STEPS]
end

function _rl_swipl_lines(dir::String)::Vector{String}
    probe = joinpath(dir, "rl_probe.pl")
    write(probe, _rl_probe_program())
    nums = _rl_numbers()
    steps = join(
        [
            "step($id,$n,'$(joinpath(dir, f))',$(_rl_codes(t)))" for
            ((id, f, t), n) in zip(_RL_STEPS, nums)
        ],
        ","
    )
    names = join(["t_$(id)" for (id, _) in _RL_CASES], ",")
    drv = joinpath(dir, "drv.pl")
    write(drv, _RL_DRIVER * ":- initialization((fz_run([$steps], '$probe', [$names]), halt)).\n")
    out = read(
        pipeline(
            addenv(`swipl -q $drv`, "LC_ALL" => "C.UTF-8"); stdin=devnull, stderr=devnull
        ),
        String
    )
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The kernel's lines: the loads, the probe program, then the answers of every `t_<id>/1`, as the driver writes swipl's. Also the database and the engine."
function _rl_kernel(dir::String)
    gd = LK.PL_global_data{_RL}()
    ld = LK.PL_local_data{_RL}(gd)
    out = String[]
    for ((id, f, t), n) in zip(_RL_STEPS, _rl_numbers())
        path = joinpath(dir, f)
        write(path, t)
        st, ball = LK.load_file!(gd, ld, path)
        push!(out, "ld $id $n " * (st === :ok ? "ok" : "exc " * _rl_enc(ball::_RL)))
    end
    probe = joinpath(dir, "rl_probe.pl")
    write(probe, _rl_probe_program())
    st, ball = LK.load_file!(gd, ld, probe)
    push!(out, st === :ok ? "probe_ok" : "probe_exc " * _rl_enc(ball::_RL))
    for (id, _) in _RL_CASES
        name = "t_$(id)"
        proc = LK.isCurrentProcedure(sym_key(_rls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_RL, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _rl_enc(mk_expr(_RL, _RL[_rls(name), lk_answers(ld, (a:a)...)...]))
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
        push!(out, "$name" * join(" " .* sols))
    end
    return gd, ld, out
end

@testset "a reloaded file as swipl (rl01-rl12: clauses, predicates dropped and added, identity, discontiguous, modules, dynamic, multifile, tables)" begin
    dir = realpath(mktempdir())
    gd, ld, kl = _rl_kernel(dir)
    @test length(kl) == length(_RL_EXPECTED)
    for (k, p) in zip(kl, _RL_EXPECTED)
        k == p || println(stderr, "  ours      ", k, "\n  expected  ", p)
        @test k == p
    end
    # not vacuous: every load, the probe program and every scenario's answer are in the expectation, and the answers are not all one
    @test count(startswith("ld "), _RL_EXPECTED) == length(_RL_STEPS)
    @test count(startswith("t_rl"), _RL_EXPECTED) == length(_RL_CASES)
    @test length(unique(_RL_EXPECTED)) == length(_RL_EXPECTED)
    # white-box: every file loaded twice or more has its reload finished, and no reload state is left in the database or the engine
    for f in unique([f for (_, f, _) in _RL_STEPS])
        sf = LK.lookupSourceFile(gd, _rls(joinpath(dir, f)), false)
        @test sf !== nothing && sf.reload === nothing && sf.count >= 1
    end
    @test gd.reload_generation == LK.GEN_INVALID && ld.reload_nesting == 0
    # the reloaded files were loaded as many times as the steps say (rl01.pl twice, rl07.pl three times, rl11.pl twice)
    counts = Dict{String, Int}()
    for (_, f, _) in _RL_STEPS
        counts[f] = get(counts, f, 0) + 1
    end
    for (f, c) in counts
        @test LK.lookupSourceFile(gd, _rls(joinpath(dir, f)), false).count == c
    end
end

@testset "the expected lines are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "RL reload LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        @test _rl_swipl_lines(realpath(mktempdir())) == _RL_EXPECTED
    end
end
