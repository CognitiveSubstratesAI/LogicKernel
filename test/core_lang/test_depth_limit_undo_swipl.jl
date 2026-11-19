# ORIGINAL: a LIVE differential of the MERGED `depart_alerted` order (src/pl-wam.jl; pl-vmi.c at the pin: the autoloader's exit, the
# scheduled undo goals, the depth limit, the inference limit) -- the one place TAB1's undo branch (TX1e) and P3's depth-limit and
# inference-limit block meet (audit D-0933 (3)(ii)). test/core_lang/test_depth_limit_undo_swipl.jl: du01-du19 against swipl 10.1.20 (the pin
# 18168e62):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver and the encoder are test_depth_limit_swipl.jl's.
#   * Every case registers an undo goal (`undo/1`) in a disjunction branch and backtracks over it (`du_bt`, `du_btx`, `du_btl`), so the goal is
#     SCHEDULED; it runs at the next call's alert point, with a depth limit or an inference limit installed. The log of what ran (`du_log/1`,
#     a global variable, newest last) and the limit's answer are the row's answer: the undo goal's execution and the limit check meet at one
#     alert point, in upstream's order.
#   * Every answer line is swipl's, PINNED (the pin's swipl, ~/.local/swipl-pin1-18168e62/bin/swipl, two identical runs, 2026-11-19); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * Rows worth reading: du03 (limit 6) runs the undo goal and then trips the limit; du04/du05 (limits 5, 3) lose the undo goal to the limit
#     (its call is over the limit, the goal fails silently and the log stays empty); du08/du09 (inference limits 12, 8) place the undo goal
#     before and after the limit; du12-du16 let the undo goal throw, with the limit tripping first (du14, du16) or not (du12, du13, du15).
#   * The kernel agrees with swipl on all 19 rows (reference, alt, alt_interned; 2026-11-19): the merged `depart_alerted` order is swipl's.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DU = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_dus(x) = lk_sym(_DU, Symbol(x))


_du_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _du_enc(t::_DU, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _du_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _du_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _du_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_du_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _DU_DRIVER = raw"""
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
function _du_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _DU_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `du_log/1` appends to a global variable (so the entry survives backtracking); `du_bt*` register an undo goal in a branch that
# fails, which schedules it; `du_loop` is a COUNTED loop (200000 steps), so a kernel whose inference limit is broken answers a wrong value
# instead of hanging
const _DU_PROGRAM = raw"""
du_log(X) :- nb_getval(du_log, L), nb_setval(du_log, [X|L]).
du_reset :- nb_setval(du_log, []).
du_get(L) :- nb_getval(du_log, L0), reverse(L0, L).
du_chain(0) :- !.
du_chain(N) :- N1 is N-1, du_chain(N1), true.
du_tail(0) :- !.
du_tail(N) :- N1 is N-1, du_tail(N1).
du_loop :- du_tail(200000).
du_ex :- throw(du_ball).
du_bt :- ( undo(du_log(u)), fail ; true ).
du_btx :- ( undo(throw(du_undo_ball)), fail ; true ).
du_btl :- ( undo(du_loop), fail ; true ).
"""

const _DU_CASES = [
    (
        "du01",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_chain(5), du_log(after)), 100, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # depth limit 100: the undo goal runs at the call after the backtrack, nothing trips,
    (
        "du02",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_chain(5), du_log(after)), 7, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # limit 7: undo goal and the chain both fit,
    (
        "du03",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_chain(5), du_log(after)), 6, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # limit 6: the undo goal runs, then the chain trips the limit at the same alert point's next call,
    (
        "du04",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_chain(5), du_log(after)), 5, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # limit 5: the undo goal's own call is over the limit (swipl: it fails silently, the log stays empty) and the chain trips,
    (
        "du05",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_log(after)), 3, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # limit 3, no chain: the undo goal is lost to the limit, the later goal is not,
    (
        "du06",
        raw"du_reset, catch((call_with_depth_limit((du_bt, du_ex), 100, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # the undo goal runs, then an exception: the log keeps it,
    (
        "du07",
        raw"du_reset, catch((call_with_inference_limit((du_bt, du_tail(3), du_log(after)), 20, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # inference limit 20: undo goal, tail loop, after, all within,
    (
        "du08",
        raw"du_reset, catch((call_with_inference_limit((du_bt, du_tail(3), du_log(after)), 12, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # inference limit 12: the undo goal runs, the limit trips later,
    (
        "du09",
        raw"du_reset, catch((call_with_inference_limit((du_bt, du_tail(3), du_log(after)), 8, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # inference limit 8: the limit trips before the undo goal runs,
    (
        "du10",
        raw"du_reset, catch((call_with_depth_limit(call_with_inference_limit((du_bt, du_loop), 100, R1), 100, R2), R0 = R1-R2), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an inference limit nested in a depth limit, with a pending undo goal,
    (
        "du11",
        raw"du_reset, catch((call_with_depth_limit(call_with_depth_limit((du_bt, du_chain(8)), 3, R1), 100, R2), R0 = R1-R2), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # a depth limit nested in a depth limit, the inner one trips with a pending undo goal,
    (
        "du12",
        raw"du_reset, catch((call_with_depth_limit((du_btx, du_chain(5), du_log(after)), 100, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that throws, depth limit 100: the ball is the answer, the later goals do not run,
    (
        "du13",
        raw"du_reset, catch((call_with_depth_limit((du_btx, du_chain(5), du_log(after)), 6, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that throws, limit 6: the same ball,
    (
        "du14",
        raw"du_reset, catch((call_with_depth_limit((du_btx, du_chain(5), du_log(after)), 3, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that throws, limit 3: the limit wins,
    (
        "du15",
        raw"du_reset, catch((call_with_inference_limit((du_btx, du_tail(3), du_log(after)), 20, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that throws, inference limit 20: the ball,
    (
        "du16",
        raw"du_reset, catch((call_with_inference_limit((du_btx, du_tail(3), du_log(after)), 5, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that throws, inference limit 5: the limit wins,
    (
        "du17",
        raw"du_reset, catch((call_with_inference_limit((du_btl, du_log(after)), 100, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that loops, inference limit 100: the limit trips inside the undo goal,
    (
        "du18",
        raw"du_reset, catch((call_with_depth_limit((du_btl, du_log(after)), 100, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # an undo goal that loops, depth limit 100: it runs to its end,
    (
        "du19",
        raw"du_reset, catch((call_with_inference_limit((du_bt, du_bt, du_tail(3), du_log(after)), 30, R0)), B, R0 = ex(B)), du_get(L), R = R0-L"
    )   # two pending undo goals, inference limit 30
]

# the driver's whole output, one line per case after `ok`, from swipl at the pin
const _DU_PINNED = [
    "ok",
    "t_du01 c[116,95,100,117,48,49]/1(c[45]/2(i7,c[91,124,93]/2(a[117],c[91,124,93]/2(a[97,102,116,101,114],nil))))",
    "t_du02 c[116,95,100,117,48,50]/1(c[45]/2(i7,c[91,124,93]/2(a[117],c[91,124,93]/2(a[97,102,116,101,114],nil))))",
    "t_du03 c[116,95,100,117,48,51]/1(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],c[91,124,93]/2(a[117],nil)))",
    "t_du04 c[116,95,100,117,48,52]/1(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],nil))",
    "t_du05 c[116,95,100,117,48,53]/1(c[45]/2(i4,c[91,124,93]/2(a[97,102,116,101,114],nil)))",
    "t_du06 c[116,95,100,117,48,54]/1(c[45]/2(c[101,120]/1(a[100,117,95,98,97,108,108]),c[91,124,93]/2(a[117],nil)))",
    "t_du07 c[116,95,100,117,48,55]/1(c[45]/2(a[33],c[91,124,93]/2(a[117],c[91,124,93]/2(a[97,102,116,101,114],nil))))",
    "t_du08 c[116,95,100,117,48,56]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],c[91,124,93]/2(a[117],nil)))",
    "t_du09 c[116,95,100,117,48,57]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],c[91,124,93]/2(a[117],nil)))",
    "t_du10 c[116,95,100,117,49,48]/1(c[45]/2(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],i97),c[91,124,93]/2(a[117],nil)))",
    "t_du11 c[116,95,100,117,49,49]/1(c[45]/2(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],i2),nil))",
    "t_du12 c[116,95,100,117,49,50]/1(c[45]/2(c[101,120]/1(a[100,117,95,117,110,100,111,95,98,97,108,108]),nil))",
    "t_du13 c[116,95,100,117,49,51]/1(c[45]/2(c[101,120]/1(a[100,117,95,117,110,100,111,95,98,97,108,108]),nil))",
    "t_du14 c[116,95,100,117,49,52]/1(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],nil))",
    "t_du15 c[116,95,100,117,49,53]/1(c[45]/2(c[101,120]/1(a[100,117,95,117,110,100,111,95,98,97,108,108]),nil))",
    "t_du16 c[116,95,100,117,49,54]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],nil))",
    "t_du17 c[116,95,100,117,49,55]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],nil))",
    "t_du18 c[116,95,100,117,49,56]/1(c[45]/2(i101,c[91,124,93]/2(a[97,102,116,101,114],nil)))",
    "t_du19 c[116,95,100,117,49,57]/1(c[45]/2(a[33],c[91,124,93]/2(a[117],c[91,124,93]/2(a[117],c[91,124,93]/2(a[97,102,116,101,114],nil)))))"
]

function _du_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _DU_CASES]
    text =
        _DU_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DU_CASES
        ])
    f = joinpath(mktempdir(), "depth_limit_undo.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _du_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_DU}()
    ld = LK.PL_local_data{_DU}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _du_enc(ball::_DU)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_dus(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_DU, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _du_enc(mk_expr(_DU, _DU[_dus(name), lk_answers(ld, (a:a)...)...]))
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
    return out, gd, ld
end

@testset "the undo goal and the depth/inference limit at one alert point as swipl's (du01-du19)" begin
    f, names = _du_file()
    kl, _, _ = _du_kernel(f, names)
    @test length(kl) == length(_DU_PINNED)
    for (k, p) in zip(kl, _DU_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  want  ", p)
        @test k == p
    end
end

@testset "the undo-with-limit rows are not vacuous" begin
    @test _DU_PINNED[1] == "ok"
    @test length(_DU_PINNED) == length(_DU_CASES) + 1
    for (id, _) in _DU_CASES
        @test any(l -> startswith(l, "t_$id "), _DU_PINNED)
    end
    u = "c[91,124,93]/2(a[117]"       # a log that holds `u`: the undo goal ran
    @test count(l -> occursin(u, l), _DU_PINNED) == 9                # du01-du03, du06-du10, du19
    @test count(l -> occursin(_du_codes("depth_limit_exceeded"), l), _DU_PINNED) == 4    # du03, du04, du11, du14
    @test count(l -> occursin(_du_codes("inference_limit_exceeded"), l), _DU_PINNED) == 5   # du08-du10, du16, du17
    @test count(l -> occursin(_du_codes("du_undo_ball"), l), _DU_PINNED) == 3          # du12, du13, du15
    # the undo goal and the limit genuinely meet: a row where the undo goal ran and the limit then tripped (du03), one where the limit
    # tripped and the undo goal never ran (du04)
    @test any(
        l ->
            startswith(l, "t_du03 ") && occursin(_du_codes("depth_limit_exceeded"), l) &&
            occursin(u, l),
        _DU_PINNED
    )
    @test any(
        l ->
            startswith(l, "t_du04 ") && occursin(_du_codes("depth_limit_exceeded"), l) &&
            !occursin(u, l),
        _DU_PINNED
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_DU_PINNED) == length(_DU_CASES) + 1
    if swipl === nothing
        @info "DEPTH-LIMIT-UNDO LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _du_file()
        @test _du_swipl_lines(f, names) == _DU_PINNED
    end
end
