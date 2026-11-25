# ORIGINAL: a LIVE differential of thread_statistics/3 (pl-thread.c:7416-7459 at the pin, swipl-devel 18168e62; swipl 10.1.20) against swipl, on the
# main thread (rows ts01-ts33) and on engines (rows te01-te16), kept in ONE database in order; thread_statistics/3 is read-only, so every row
# is state-neutral. Added by B1-1 (edit-only: NOTHING was compiled or run when this file was written, the kernel's answers are UNVERIFIED).
#   * A PROGRAM-less file of cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(E, _), R = raised(E))`; the
#     driver is test_thread_ops_swipl.jl's. The VALUES of the statistics (times, sizes, counts) differ between swipl and the kernel and
#     between runs, so a row asks for the TYPE of the answer (`integer`, `float`, a list of integers) and pins that; the errors and the
#     failing rows are exact. An engine handle is never printed (a blob).
#   * Every swipl answer line is swipl's, PINNED (swipl 10.1.20, the pin binary, two runs byte-identical, evidence/B1/gen_rows.py --fill); with `swipl`
#     on PATH the live answers are compared with the pins too.
#   * AIMED ROWS (T3 battery tools/mutants/B1.py; their values are RELATIONS that hold on swipl, oracle-checked, not types): ts28/ts29 the target's clock is
#     refreshed (a later read is larger after work), ts30/ts31 a LIST value for warnings/errors fails (the arm answers before qp_statistics), ts32/ts33 the value is
#     exactly 0, te15 an engine's `inferences` grow by what the engine ran (a swap of the target's local data for the caller's reads the caller's counter),
#     te16 an engine's `stacks` are smaller than the caller's with a 100000-element list live (the list-form path reads the target's stacks).
#   * KNOWN DIFFERENCE: `warnings` and `errors` are always 0 in the kernel (`ld_statistics` does not count them); the rows ask for `integer`.
#   * REFUSED by name (TH1), kernel only: the main thread named from an engine (rf01): the kernel does not keep the main thread's local data
#     where an engine can reach it. swipl answers it; no swipl line is pinned.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — src/pl-thread.jl: all three term types: the predicates take the term type through the term interface (atoms, integers, compounds)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _B1 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_b1s(x) = lk_sym(_B1, Symbol(x))

_b1_codes(s::AbstractString) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _b1_enc(t::_B1, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _b1_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _b1_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _b1_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_b1_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end


# hand-built encodings of expected answers (never read from swipl)
_b1_a(s) = "a" * _b1_codes(s)
_b1_c(name, args...) = "c" * _b1_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_b1_list(xs) = isempty(xs) ? "nil" : _b1_c("[|]", xs[1], _b1_list(xs[2:end]))

# the swipl side: test/core_lang/test_mutex_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _B1_DRIVER = raw"""
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
function _b1_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _B1_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _B1_CASES = [
    (
        "ts01",
        raw"thread_statistics(main, cputime, X), ( float(X) -> R = float ; R = other )"
    ),
    ("ts02", raw"thread_statistics(main, runtime, [A,B]), integer(A), integer(B), R = ok"),
    (
        "ts03",
        raw"thread_statistics(main, system_time, [A,B]), integer(A), integer(B), R = ok"
    ),
    (
        "ts04",
        raw"thread_statistics(main, heapused, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "ts05",
        raw"thread_statistics(1, inferences, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "ts06",
        raw"thread_statistics(main, warnings, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "ts07",
        raw"thread_statistics(main, errors, X), ( integer(X) -> R = integer ; R = other )"
    ),
    ("ts08", raw"thread_statistics(main, nokey, _)"),
    ("ts09", raw"thread_statistics(main, _, _)"),
    ("ts10", raw"thread_statistics(main, 1, _)"),
    ("ts11", raw"thread_statistics(main, [a], _)"),
    ("ts12", raw"thread_statistics(nosuch, cputime, _)"),
    ("ts13", raw"thread_statistics(99, cputime, _)"),
    ("ts14", raw"thread_statistics(1.5, cputime, _)"),
    ("ts15", raw"thread_statistics(_, cputime, _)"),
    ("ts16", raw"thread_statistics(main, cputime, foo)"),
    ("ts17", raw"thread_statistics(main, warnings, foo)"),
    ("ts18", raw"thread_statistics(main, errors, a)"),
    ("ts19", raw"thread_statistics(main, cputime, f(_))"),
    (
        "ts20",
        raw"thread_statistics(main, threads, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "ts21",
        raw"thread_statistics(main, atoms, X), ( integer(X) -> R = integer ; R = other )"
    ),
    ("ts22", raw"thread_statistics(main, epoch, X), ( float(X) -> R = float ; R = other )"),
    (
        "ts23",
        raw"thread_statistics(main, stack_limit, X), ( integer(X) -> R = integer ; R = other )"
    ),
    ("ts24", raw"findall(X, thread_statistics(main, cputime, X), L), length(L, N), R = N"),
    ("ts25", raw"thread_statistics(main, runtime, [_])"),
    (
        "ts26",
        raw"thread_statistics(main, cputime, X), thread_statistics(1, cputime, Y), ( Y >= X -> R = mono ; R = bad )"
    ),
    ("ts27", raw"call_cleanup(thread_statistics(main, errors, _), Det = true), R = Det"),
    (
        "ts28",
        raw"thread_statistics(main, cputime, X), findall(B, (between(1,20000,B), atom_length(abc,_)), _), thread_statistics(main, cputime, Y), ( Y > X -> R = later ; R = same )"
    ),
    (
        "ts29",
        raw"thread_statistics(main, runtime, [X,_]), findall(B, (between(1,200000,B), atom_length(abc,_)), _), thread_statistics(main, runtime, [Y,_]), ( Y > X -> R = later ; R = same )"
    ),
    ("ts30", raw"thread_statistics(main, warnings, [_])"),
    ("ts31", raw"thread_statistics(main, errors, [_])"),
    ("ts32", raw"thread_statistics(main, warnings, 0), R = ok"),
    ("ts33", raw"thread_statistics(main, errors, 0), R = ok"),
    (
        "te01",
        raw"engine_create(x, true, E), thread_statistics(E, cputime, X), ( float(X) -> R = float ; R = other )"
    ),
    (
        "te02",
        raw"engine_create(x, true, E), thread_statistics(E, runtime, [A,B]), integer(A), integer(B), R = ok"
    ),
    (
        "te03",
        raw"engine_create(x, true, E), thread_statistics(E, system_time, [A,B]), integer(A), integer(B), R = ok"
    ),
    (
        "te04",
        raw"engine_create(x, true, E), thread_statistics(E, heapused, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "te05",
        raw"engine_create(x, true, E), thread_statistics(E, warnings, X), ( integer(X) -> R = integer ; R = other )"
    ),
    (
        "te06",
        raw"engine_create(x, true, E), thread_statistics(E, errors, X), ( integer(X) -> R = integer ; R = other )"
    ),
    ("te07", raw"engine_create(x, true, E), thread_statistics(E, nokey, _)"),
    ("te08", raw"engine_create(x, true, E), thread_statistics(E, cputime, foo)"),
    (
        "te09",
        raw"engine_create(x, true, E), engine_destroy(E), catch(thread_statistics(E, cputime, _), error(existence_error(T0, E2), _), ( E2 == E -> R = existence(T0) ; R = other ))"
    ),
    (
        "te10",
        raw"engine_create(x, true, E), engine_next(E, _), catch(thread_statistics(E, inferences, _), error(existence_error(T0, E2), _), ( E2 == E -> R = existence(T0) ; R = other ))"
    ),
    (
        "te11",
        raw"engine_create(x, ( thread_self(M), thread_statistics(M, errors, V), integer(V) ), E), engine_next(E, R)"
    ),
    (
        "te12",
        raw"engine_create(x, true, E), thread_statistics(E, inferences, X), ( integer(X) -> R = integer ; R = other )"
    ),
    ("te13", raw"engine_create(x, true, E), thread_statistics(E, runtime, [_])"),
    (
        "te14",
        raw"engine_create(x, ( thread_self(M), thread_statistics(M, nokey, _) ), E), catch(engine_next(E, _), error(domain_error(D, K), _), R = d(D, K))"
    ),
    (
        "te15",
        raw"engine_create(x, ( findall(Y, (between(1,3000,Y), atom_length(abc,_)), _) ; true ), E), thread_statistics(E, inferences, I0), engine_next(E, _), thread_statistics(E, inferences, I1), D is I1 - I0, ( D >= 3000 -> R = grew ; R = small )"
    ),
    (
        "te16",
        raw"numlist(1, 100000, L), statistics(stacks, [GM,_]), engine_create(x, true, E), thread_statistics(E, stacks, [GE,_]), L = [_|_], ( GE < GM -> R = less ; R = notless )"
    )
]

# the swipl lines of every case, PINNED (evidence/B1/gen_rows.py --fill writes the block)
const _B1_PINNED = [
    "ok",
    "t_ts01 c[116,95,116,115,48,49]/1(a[102,108,111,97,116])",
    "t_ts02 c[116,95,116,115,48,50]/1(a[111,107])",
    "t_ts03 c[116,95,116,115,48,51]/1(a[111,107])",
    "t_ts04 c[116,95,116,115,48,52]/1(a[105,110,116,101,103,101,114])",
    "t_ts05 c[116,95,116,115,48,53]/1(a[105,110,116,101,103,101,114])",
    "t_ts06 c[116,95,116,115,48,54]/1(a[105,110,116,101,103,101,114])",
    "t_ts07 c[116,95,116,115,48,55]/1(a[105,110,116,101,103,101,114])",
    "t_ts08 c[116,95,116,115,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,97,116,105,115,116,105,99,115,95,107,101,121],a[110,111,107,101,121])))",
    "t_ts09 c[116,95,116,115,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ts10 c[116,95,116,115,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ts11 c[116,95,116,115,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[91,124,93]/2(a[97],nil))))",
    "t_ts12 c[116,95,116,115,49,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[110,111,115,117,99,104])))",
    "t_ts13 c[116,95,116,115,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_ts14 c[116,95,116,115,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],f1.5)))",
    "t_ts15 c[116,95,116,115,49,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ts16",
    "t_ts17",
    "t_ts18",
    "t_ts19",
    "t_ts20 c[116,95,116,115,50,48]/1(a[105,110,116,101,103,101,114])",
    "t_ts21 c[116,95,116,115,50,49]/1(a[105,110,116,101,103,101,114])",
    "t_ts22 c[116,95,116,115,50,50]/1(a[102,108,111,97,116])",
    "t_ts23 c[116,95,116,115,50,51]/1(a[105,110,116,101,103,101,114])",
    "t_ts24 c[116,95,116,115,50,52]/1(i1)",
    "t_ts25 c[116,95,116,115,50,53]/1(V0)",
    "t_ts26 c[116,95,116,115,50,54]/1(a[109,111,110,111])",
    "t_ts27 c[116,95,116,115,50,55]/1(a[116,114,117,101])",
    "t_ts28 c[116,95,116,115,50,56]/1(a[108,97,116,101,114])",
    "t_ts29 c[116,95,116,115,50,57]/1(a[108,97,116,101,114])",
    "t_ts30",
    "t_ts31",
    "t_ts32 c[116,95,116,115,51,50]/1(a[111,107])",
    "t_ts33 c[116,95,116,115,51,51]/1(a[111,107])",
    "t_te01 c[116,95,116,101,48,49]/1(a[102,108,111,97,116])",
    "t_te02 c[116,95,116,101,48,50]/1(a[111,107])",
    "t_te03 c[116,95,116,101,48,51]/1(a[111,107])",
    "t_te04 c[116,95,116,101,48,52]/1(a[105,110,116,101,103,101,114])",
    "t_te05 c[116,95,116,101,48,53]/1(a[105,110,116,101,103,101,114])",
    "t_te06 c[116,95,116,101,48,54]/1(a[105,110,116,101,103,101,114])",
    "t_te07 c[116,95,116,101,48,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,97,116,105,115,116,105,99,115,95,107,101,121],a[110,111,107,101,121])))",
    "t_te08",
    "t_te09 c[116,95,116,101,48,57]/1(c[101,120,105,115,116,101,110,99,101]/1(a[116,104,114,101,97,100]))",
    "t_te10 c[116,95,116,101,49,48]/1(c[101,120,105,115,116,101,110,99,101]/1(a[116,104,114,101,97,100]))",
    "t_te11 c[116,95,116,101,49,49]/1(a[120])",
    "t_te12 c[116,95,116,101,49,50]/1(a[105,110,116,101,103,101,114])",
    "t_te13 c[116,95,116,101,49,51]/1(V0)",
    "t_te14 c[116,95,116,101,49,52]/1(c[100]/2(a[115,116,97,116,105,115,116,105,99,115,95,107,101,121],a[110,111,107,101,121]))",
    "t_te15 c[116,95,116,101,49,53]/1(a[103,114,101,119])",
    "t_te16 c[116,95,116,101,49,54]/1(a[108,101,115,115])"
]

const _B1_IDS = [id for (id, _) in _B1_CASES]
const _B1_PIN = Dict(zip(_B1_IDS, _B1_PINNED[2:end]))

"The program text: one clause `t_<id>(R)` per case."
function _b1_program()::String
    return join(
        [
        "t_$(id)(R) :- catch(($(g)), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in _B1_CASES
    ]
    )
end

"""
The kernel's lines for `names` after consulting `path`, as the driver writes swipl's, in a FRESH database. A NotPortedError ends
the run with the line `<name> notported <step> <what>` (the query is abandoned with the database).
"""
function _b1_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_B1}()
    ld = LK.PL_local_data{_B1}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _b1_enc(ball::_B1)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_b1s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_B1, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        try
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, ld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _b1_enc(mk_expr(_B1, _B1[_b1s(name), lk_answers(ld, (a:a)...)...]))
                    )
                    rc == LK.PL_S_LAST && break
                elseif rc == LK.PL_S_EXCEPTION
                    push!(sols, "exception")
                    break
                else
                    break
                end
            end
        catch e
            e isa LK.NotPortedError || rethrow()
            push!(out, "$name notported $(e.step) $(e.what)")
            return out, gd, ld, e
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld, nothing
end

function _b1_file()::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "b1_preds.pl")
    write(f, _b1_program())
    return f, ["t_$id" for id in _B1_IDS]
end

@testset "thread_statistics/3 as swipl's (ts01-ts33, te01-te16)" begin
    f, names = _b1_file()
    kl, gd, ld, e = _b1_kernel(f, names)
    @test e === nothing
    @test kl[1] == "ok"
    @test length(kl) == length(names) + 1
    for (k, id) in zip(kl[2:end], _B1_IDS)
        want = _B1_PIN[id]
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

# REFUSED by name, owner TH1, kernel only: the main thread's local data is not reachable from an engine; swipl answers the row (a float).
@testset "thread_statistics/3 of the main thread from an engine is refused by name, owner TH1 (rf01)" begin
    f = joinpath(mktempdir(), "b1_refused.pl")
    write(
        f,
        "t_rf01(R) :- engine_create(x, thread_statistics(main, cputime, _), E), engine_next(E, _), R = ok.\n"
    )   # no catch/3
    kl, _, _, e = _b1_kernel(f, ["t_rf01"])
    @test e isa LK.NotPortedError
    if e isa LK.NotPortedError
        @test e.step == "TH1"
        @test e.what == "thread_statistics/3: the main thread from an engine"
        @test sym_text(e.culprit) == "thread_statistics"
        @test kl[end] ==
            "t_rf01 notported TH1 thread_statistics/3: the main thread from an engine"
    end
end

@testset "thread_statistics/3 is registered with upstream's flags (pl-thread.c:8866)" begin
    ext = Dict((e.predicate_name, e.arity) => e for e in LK.foreigns)
    @test haskey(ext, ("thread_statistics", 3))
    if haskey(ext, ("thread_statistics", 3))
        fl = ext[("thread_statistics", 3)].flags
        @test (fl & LK.PL_FA_NONDETERMINISTIC) == 0
        @test (fl & LK.PL_FA_TRANSPARENT) == 0
        @test (fl & LK.PL_FA_ISO) == 0
    end
    # the 3-argument statistics method is statistics/2's, the 4-argument one is thread_statistics/3's
    @test hasmethod(LK.pl_statistics_ld, Tuple{LK.PL_local_data{_B1}, Int, Int})
    @test hasmethod(
        LK.pl_statistics_ld, Tuple{LK.PL_local_data{_B1}, Int, Int, LK.PL_local_data{_B1}}
    )
end

@testset "the B1 rows are not vacuous" begin
    @test _B1_PINNED[1] == "ok"
    @test length(_B1_PINNED) == length(_B1_CASES) + 1
    @test length(unique(_B1_IDS)) == length(_B1_IDS)
    errors = count(l -> occursin("[114,97,105,115,101,100]", l), _B1_PINNED)
    @test errors >= 10                                              # the raising rows
    @test count(l -> !occursin(" ", l) && startswith(l, "t_"), _B1_PINNED) >= 8    # the failing rows
    for id in ("ts01", "ts02", "ts26", "te01", "te02", "te09", "te11")
        @test any(
            l -> startswith(l, "t_$id ") && !occursin("[114,97,105,115,101,100]", l),
            _B1_PINNED
        )                                                           # an answer, not an error
    end
end

@testset "the B1 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_B1_PINNED) == length(_B1_CASES) + 1
    if swipl === nothing
        @info "B1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _b1_file()
        @test _b1_swipl_lines(f, names) == _B1_PINNED
    end
end
