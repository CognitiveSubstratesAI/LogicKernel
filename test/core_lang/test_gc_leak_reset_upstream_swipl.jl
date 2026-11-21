# ORIGINAL: the UPSTREAM tests/core_lang/test_gc.pl (swipl-devel 18168e62), units gc_leak (3 tests) and gc_reset (1 test), as kernel rows (G1-B2:
# the collector's leak and reset tests; the unit texts of upstream lines 53-86 (helpers), 90-103 and 126-134 are embedded VERBATIM in `_GR_PROGRAM`).
# One row `t_<id>(R)` per upstream test (gl01 det_freeze_no_space, gl02 early_reset, gl03 throw_gc, gr01 deep_reset): the body, then `R = ok`
# (a failing or raising body is `failed` / `raised(E)`); the unit option of throw_gc (`G0 == G1`) and of det_freeze_no_space (`T < 100`) are goals of
# the row. `sto(rational_trees)` is the default mode of the kernel (no occurs check): nothing to fold.
#   * Every pinned line is swipl's (the pinned build ~/.local/swipl-pin1-18168e62, two byte-identical runs) AND equals the answer the upstream
#     test expects (`_GR_UPSTREAM`: `ok`): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_gc` is `user`; plunit is not used.
#   * held out: matches the D-0164 term list (class only): two further units of the file, upstream lines 141-194 and 196-218, and their lines of
#     `test_gc/0`. They are not embedded and have no row.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _GR = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tds(x) = lk_sym(_GR, Symbol(x))

_gr_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _gr_enc(t::_GR, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gr_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gr_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gr_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_gr_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _GR_DRIVER = raw"""
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

function _gr_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _GR_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _GR_PROGRAM = raw"""
:- module_transparent
	space/3,
	nospace/1.

space(T, G) :-
	garbage_collect,
	statistics(trailused, T),
	statistics(globalused, G).

must_space(T0, G0) :-
	space(T1, G1),
	(   T0 == T1,
	    G0 == G1
	->  true
	;   T is T1-T0,
	    G is G1-G0,
	    format(user_error, 'Used ~D+~D~n', [T,G]),
	    fail
	).

space(Goal, T, G) :-
	space(T0,G0),
	Goal,
	space(T1,G1),
	T is T1-T0,
	G is G1-G0.

nospace(Goal) :-
	space(Goal, T, G),
	(   T == 0, G == 0
	->  true
	;   format(user_error, 'Used ~D+~D~n', [T,G]),
	    fail
	).

det_freeze_loop(N, T) :-
	(   succ(N2, N)
	->  freeze(X, true),
	    X = a,
	    det_freeze_loop(N2, T)
	;   garbage_collect,
	    statistics(trailused, T)
	).

early_reset :-
	early_reset(_).

early_reset(X) :- space(T,G), length(X, 10), must_space(T,G), !.
early_reset(_) :- fail.

deep_reset :-
        X = a(A),
        deep_reset(A), !,
        X == a(42).

deep_reset(A) :-
        (   A = 42, garbage_collect
        ;   true
        ).
"""

const _GR_LEFT_PROGRAM = ""

const _GR_CASES = [
    (
        "gl01",
        "gc_leak:det_freeze_no_space",
        raw"""
garbage_collect, statistics(trailused, T0), det_freeze_loop(1000, T1), T is T1 - T0, T < 100, R = ok"""
    ),
    (
        "gl02",
        "gc_leak:early_reset",
        raw"""
early_reset, R = ok"""
    ),
    (
        "gl03",
        "gc_leak:throw_gc",
        raw"""
statistics(stack_shifts, [G0,_,_]), ( between(1, 10000, _), catch(throw(foo),_, true), fail ; true ), statistics(stack_shifts, [G1,_,_]), G0 == G1, R = ok"""
    ),
    (
        "gr01",
        "gc_reset:deep_reset",
        raw"""
deep_reset, R = ok"""
    )
]

const _GR_LEFT = Tuple{String, String, String, String}[]

const _GR_PINNED = [
    "ok",
    "t_gl01 c[116,95,103,108,48,49]/1(a[111,107])",
    "t_gl02 c[116,95,103,108,48,50]/1(a[111,107])",
    "t_gl03 c[116,95,103,108,48,51]/1(a[111,107])",
    "t_gr01 c[116,95,103,114,48,49]/1(a[111,107])"
]

"The answer the UPSTREAM test expects (the row's `R = ok`), as the driver encodes it."
const _GR_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]"
]

const _GR_LEFT_PINNED = String[]

const _GR_LEFT_UPSTREAM = String[]

"The program text with the cases appended."
_gr_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _gr_load(program::String)
    f = joinpath(mktempdir(), "gc_leak_reset_upstream.pl")
    write(f, _gr_text(program, [(id, g) for (id, _, g) in _GR_CASES]))
    gd = LK.PL_global_data{_GR}()
    ld = LK.PL_local_data{_GR}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _gr_enc(ball::_GR))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _gr_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tds(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_GR, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _gr_enc(mk_expr(_GR, _GR[_tds(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_GR_UPSTREAM` holds it."
function _gr_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_gr_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_gc.pl gc_leak, gc_reset: the four tests run on the kernel and answer as swipl's pins" begin
    gd, ld, st = _gr_load(_GR_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _GR_CASES
        push!(kl, _gr_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_GR_PINNED)
    for (k, pn) in zip(kl, _GR_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _gr_corrupt(_GR_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_GR_PINNED) == length(_GR_CASES) + 1
    @test length(_GR_UPSTREAM) == length(_GR_CASES)
    @test !isempty(_GR_UPSTREAM) && all(!isempty, _GR_UPSTREAM)
    for (pn, up) in zip(_GR_PINNED[2:end], _GR_UPSTREAM)
        @test _gr_answer(pn) == up
    end
    @test length(_GR_LEFT_PINNED) == length(_GR_LEFT) == length(_GR_LEFT_UPSTREAM)
    for (pn, up) in zip(_GR_LEFT_PINNED, _GR_LEFT_UPSTREAM)
        @test _gr_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _gr_answer(_gr_corrupt(_GR_PINNED[2])) != _GR_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat(
            [(id, g) for (id, _, g) in _GR_CASES], [(id, g) for (id, _, g, _) in _GR_LEFT]
        )
        write(f, _gr_text(_GR_PROGRAM * _GR_LEFT_PROGRAM, all_cases))
        got = _gr_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_GR_PINNED, _GR_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _gr_corrupt(_GR_PINNED[2])
    end
end
