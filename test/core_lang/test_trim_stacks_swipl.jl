# ORIGINAL: a LIVE differential of trim_stacks/0 (pl-setup.c) against swipl at the pin, in the pattern of test/core_lang/test_bootpred_swipl.jl
# test/core_lang/test_trim_stacks_swipl.jl — `trim_stacks/0` (pl-setup.c:1751, a call of trimStacks(true); TRIMST):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_bootpred_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, the pin 18168e62, the driver run twice with identical output);
#     with `swipl` on PATH the live answers are compared with the pins too.
#   * The effect on the stacks is not read by these rows (no Prolog predicate of the kernel reports a stack's size), so the white-box
#     testset reads the kernel's local data: `trim_stacks/0` gives back the room a deep recursion grew the local stack by (`trimStacks!(ld, true)`
#     takes the `resize` path: `growStacks_trim!`), where trimStacks!(ld, false) re-reserves the spares only.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer and the white-box numbers; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicate rides the term layer only through the query API; every type in CI
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

# the swipl side: test_bootpred_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
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
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: three facts (ts05, ts12, ts13) and a deep, non-tail recursion for the white-box testset
const _TS_PROGRAM = raw"""
p(1).
p(2).
p(3).
ts_deep(0).
ts_deep(N) :- N > 0, M is N - 1, ts_deep(M), true.
ts_wb_deep(R) :- ts_deep(5000), R = ok.
ts_wb_trim(R) :- trim_stacks, R = ok.
"""

const _TS_CASES = [
    ("ts01", raw"trim_stacks, R = ok"),   # the answer: true; R is bound afterwards
    ("ts02", raw"findall(a, trim_stacks, R)"),   # one answer, no choice point left
    ("ts03", raw"trim_stacks, trim_stacks, R = twice"),   # a second call
    ("ts04", raw"X = f(Y), Y = 1, trim_stacks, R = X"),   # bindings made before the call stay
    ("ts05", raw"findall(X, p(X), L), trim_stacks, R = L"),   # a list built before the call stays
    ("ts06", raw"catch(throw(oops), E, true), trim_stacks, R = E"),   # the ball caught before the call stays
    ("ts07", raw"trim_stacks(_)"),   # arity 1 is another predicate: existence_error
    ("ts08", raw"\+ \+ trim_stacks, R = ok"),   # under negation
    ("ts09", raw"call(trim_stacks), R = ok"),   # through call/1
    ("ts10", raw"lists:trim_stacks, R = ok"),   # a system predicate from another module
    ("ts11", raw"( trim_stacks, fail ; R = alt )"),   # fails nowhere: the failure after it is the body's
    ("ts12", raw"findall(X, ( p(X), trim_stacks ), R)"),   # backtracks through it: the choice point of p/1 survives
    ("ts13", raw"p(X), X >= 2, trim_stacks, R = X"),   # two answers, the second after a backtrack over it
    ("ts14", raw"once(trim_stacks), R = ok"),   # under once/1
]

# swipl 10.1.20's answers to the program and cases above (the driver's lines; the same on two runs)
const _TS_PINNED = [
    "ok",
    "t_ts01 c[116,95,116,115,48,49]/1(a[111,107])",
    "t_ts02 c[116,95,116,115,48,50]/1(c[91,124,93]/2(a[97],nil))",
    "t_ts03 c[116,95,116,115,48,51]/1(a[116,119,105,99,101])",
    "t_ts04 c[116,95,116,115,48,52]/1(c[102]/1(i1))",
    "t_ts05 c[116,95,116,115,48,53]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_ts06 c[116,95,116,115,48,54]/1(a[111,111,112,115])",
    "t_ts07 c[116,95,116,115,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[116,114,105,109,95,115,116,97,99,107,115],i1))))",
    "t_ts08 c[116,95,116,115,48,56]/1(a[111,107])",
    "t_ts09 c[116,95,116,115,48,57]/1(a[111,107])",
    "t_ts10 c[116,95,116,115,49,48]/1(a[111,107])",
    "t_ts11 c[116,95,116,115,49,49]/1(a[97,108,116])",
    "t_ts12 c[116,95,116,115,49,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_ts13 c[116,95,116,115,49,51]/1(i2) c[116,95,116,115,49,51]/1(i3)",
    "t_ts14 c[116,95,116,115,49,52]/1(a[111,107])"
]

function _ts_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _TS_CASES]
    text =
        _TS_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TS_CASES
        ])
    f = joinpath(mktempdir(), "trim_stacks.pl")
    write(f, text)
    return f, names
end

"A database with `path` consulted: `(gd, ld, the first line of the driver's output)`."
function _ts_load(path::String)
    gd = LK.PL_global_data{_TS}()
    ld = LK.PL_local_data{_TS}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ts_enc(ball::_TS))
end

"The line the driver writes for `name/1`: its name and every answer (at most 50), in database `gd`."
function _ts_run!(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tss(name)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
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
            push!(sols, _ts_enc(mk_expr(_TS, _TS[_tss(name), lk_answers(ld, (a:a)...)...])))
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
    return "$name" * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _ts_kernel(path::String, names::Vector{String})::Vector{String}
    gd, ld, head = _ts_load(path)
    return [head; [_ts_run!(gd, ld, n) for n in names]]
end

@testset "trim_stacks/0 as swipl's (ts01-ts14)" begin
    f, names = _ts_file()
    kl = _ts_kernel(f, names)
    @test length(kl) == length(_TS_PINNED)
    for (k, p) in zip(kl, _TS_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the rows that answer true hold their answers, the arity-1 row raises, the backtracking rows answer 3 and 2 times
    @test count(l -> occursin(_ts_codes("ok"), l), _TS_PINNED) == 5                  # ts01, ts08, ts09, ts10, ts14
    @test any(l -> startswith(l, "t_ts07 ") && occursin(_ts_codes("existence_error"), l), _TS_PINNED)
    ts13 = only(filter(l -> startswith(l, "t_ts13 "), _TS_PINNED))
    @test length(collect(eachmatch(r"c\[116,95,116,115,49,51\]/1", ts13))) == 2       # ts13: two answers on its line
    @test any(
        l -> startswith(l, "t_ts12 ") && occursin("i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil", l),
        _TS_PINNED
    )
end

# The effect (pl-setup.c trimStacks(true)): the local stack a deep recursion grew is given back. `stack_size()` (`ld.lMax + ld.local_spare`) is the stack's
# size (`growStacks_trim!`'s `size`); after ts_deep(5000) it is above LOCAL_INITIAL, after trim_stacks at the base it is back near it.
@testset "trim_stacks/0 shrinks the local stack a deep recursion grew (white-box)" begin
    f, _ = _ts_file()
    gd, ld, head = _ts_load(f)
    @test head == "ok"
    stack_size() = ld.lMax + ld.local_spare
    ok_line(name) = name * " c" * _ts_codes(name) * "/1(a" * _ts_codes("ok") * ")"
    @test _ts_run!(gd, ld, "ts_wb_deep") == ok_line("ts_wb_deep")
    grown = stack_size()
    @test grown > LK.LOCAL_INITIAL                                                       # the recursion grew it
    lt = ld.lTop
    @test _ts_run!(gd, ld, "ts_wb_trim") == ok_line("ts_wb_trim")
    @test ld.lTop == lt                                                                  # lTop is restored (`lTop = lSave`)
    @test stack_size() < grown                                                                 # given back
    @test ld.local_spare == ld.local_def_spare                                           # the spare is reserved again
end
