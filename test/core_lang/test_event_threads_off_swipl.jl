# ORIGINAL: a differential of the event table of pl-event.c under the kernel's configuration MULTI_THREADED=OFF, ENGINES=OFF
# (audit D-0716 item 7, Q3 (a); scope: lk-channel evidence/TH1/th1_scope.md). With `O_ENGINES` unset upstream's `PL_events` has NINE rows
# (pl-event.c:81-89); the three thread events `thread_start`, `thread_exit` and `this_thread_exit` are rows 90-93 inside `#ifdef O_ENGINES`
# (swipl-devel 18168e62). `prolog_listen/2,3` and `prolog_unlisten/2` find an event by NAME in that table (`get_event_listp`,
# pl-event.c:208-238: for an arity-0 name that is no row, the fall-through `return PL_domain_error("event", type)` at :235), so in this
# build `prolog_listen(thread_start, G)` raises `domain_error(event, thread_start)`, as `prolog_listen(nosuchevent, G)` does.
#   * The pinned swipl (10.1.20 at ~/.local/swipl-pin1-18168e62) is a THREADED build (flags threads=true, engines=true): it accepts the
#     three events. So the oracle's answer differs from the kernel's intended one: a KNOWN DIFFERENCE (D-0716 Q2 (a)), the same
#     situation as test_bootpred3_swipl.jl's `_B3_KNOWN`. This file pins BOTH answers per row: `_TH_KERNEL` (what the kernel is meant to
#     answer, with the upstream line above) and `_TH_SWIPL` (the oracle's answer, written by the driver below; the live check with `swipl`
#     on PATH compares the oracle's answers with it). A row whose two lines are equal is a CONTROL (the table's other rows, the unknown
#     event, `as(middle)`, `thread_self/1`, `with_mutex/2`: the two single-thread predicates upstream's non-PLMT build keeps); a row whose
#     lines differ must be listed in `_TH_DIVERGES` (a difference cannot be silent) and the other way round.
#   * Rows th19-th21 are the existence_error side of the same ruling: pl-thread.c registers no `thread_exit/1`, `is_engine/1` or
#     `thread_property/2` without O_PLMT/O_ENGINES (BeginPredDefs(thread) pl-thread.c:8847-8906), so the kernel's call is an unknown procedure;
#     the threaded oracle answers (permission_error(exit, thread, main); failure; id 1).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides. The swipl
#     lines are written by `swipl` 10.1.20 (the driver in this file, `LC_ALL=C`, `swipl -q`).
#   * CHECKLIST (D-0716 Q2 (b)): after Phase 1 coding the second oracle (`-DMULTI_THREADED=OFF -DENGINES=OFF`, tools/build_oracle.sh FLAGS)
#     is built; then `_TH_SWIPL` is regenerated from it, every row of `_TH_DIVERGES` becomes an exact row (kernel == oracle), the set empties,
#     and the `@test` that it is not empty is deleted with it. Until then the rows stay as they are.
#   * No row for the DELIVERY of a thread event (no thread exists: `callEventHook` is only called from pl-thread.c under O_PLMT).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TH = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ths(x) = lk_sym(_TH, Symbol(x))

_th_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _th_enc(t::_TH, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _th_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _th_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _th_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_th_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TH_DRIVER = raw"""
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

function _th_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TH_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: one listener closure and the cases (no state is shared between the rows: each registers and removes nothing it later reads)
const _TH_PROGRAM = raw"""
th_cb(_).
"""

const _TH_CASES = [
    ("th01", raw"prolog_listen(thread_start, th_cb), R = yes"),
    ("th02", raw"prolog_listen(thread_exit, th_cb), R = yes"),
    ("th03", raw"prolog_listen(this_thread_exit, th_cb), R = yes"),
    ("th04", raw"prolog_listen(thread_start, th_cb, [as(last)]), R = yes"),
    ("th05", raw"prolog_listen(thread_exit, th_cb, [name(th_n1)]), R = yes"),
    ("th06", raw"prolog_listen(thread_start, th_cb), prolog_unlisten(thread_start, th_cb), R = yes"),
    ("th07", raw"prolog_unlisten(this_thread_exit, th_nosuch), R = yes"),
    ("th08", raw"prolog_unlisten(thread_exit, th_nosuch), R = yes"),
    ("th09", raw"prolog_listen(thread_start, 1), R = yes"),
    ("th10", raw"prolog_listen(thread_start, th_cb, [as(middle)]), R = yes"),
    ("th11", raw"prolog_listen(thread_start(_), th_cb), R = yes"),
    ("th12", raw"prolog_listen(untable, th_cb), R = yes"),
    ("th13", raw"prolog_listen(abort, th_cb), R = yes"),
    ("th14", raw"prolog_listen(nosuchevent, th_cb), R = yes"),
    ("th15", raw"prolog_unlisten(nosuchevent, th_cb), R = yes"),
    ("th16", raw"prolog_listen(thread_start, th_cb), prolog_listen(thread_start, th_cb), R = yes"),
    ("th17", raw"thread_self(R)"),
    ("th18", raw"with_mutex(th_m, R = yes)"),
    ("th19", raw"thread_exit(x), R = yes"),
    ("th20", raw"is_engine(_), R = yes"),
    ("th21", raw"thread_property(main, id(R))")
]

const _TH_SWIPL = [
    "ok",
    "t_th01 c[116,95,116,104,48,49]/1(a[121,101,115])",
    "t_th02 c[116,95,116,104,48,50]/1(a[121,101,115])",
    "t_th03 c[116,95,116,104,48,51]/1(a[121,101,115])",
    "t_th04 c[116,95,116,104,48,52]/1(a[121,101,115])",
    "t_th05 c[116,95,116,104,48,53]/1(a[121,101,115])",
    "t_th06 c[116,95,116,104,48,54]/1(a[121,101,115])",
    "t_th07 c[116,95,116,104,48,55]/1(a[121,101,115])",
    "t_th08 c[116,95,116,104,48,56]/1(a[121,101,115])",
    "t_th09 c[116,95,116,104,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_th10 c[116,95,116,104,49,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_th11 c[116,95,116,104,49,49]/1(a[121,101,115])",
    "t_th12 c[116,95,116,104,49,50]/1(a[121,101,115])",
    "t_th13 c[116,95,116,104,49,51]/1(a[121,101,115])",
    "t_th14 c[116,95,116,104,49,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_th15 c[116,95,116,104,49,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_th16 c[116,95,116,104,49,54]/1(a[121,101,115])",
    "t_th17 c[116,95,116,104,49,55]/1(a[109,97,105,110])",
    "t_th18 c[116,95,116,104,49,56]/1(a[121,101,115])",
    "t_th19 c[116,95,116,104,49,57]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[101,120,105,116],a[116,104,114,101,97,100],a[109,97,105,110])))",
    "t_th20",
    "t_th21 c[116,95,116,104,50,49]/1(i1)"
]

const _TH_KERNEL = [
    "ok",
    "t_th01 c[116,95,116,104,48,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,115,116,97,114,116])))",
    "t_th02 c[116,95,116,104,48,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,101,120,105,116])))",
    "t_th03 c[116,95,116,104,48,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,105,115,95,116,104,114,101,97,100,95,101,120,105,116])))",
    "t_th04 c[116,95,116,104,48,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,115,116,97,114,116])))",
    "t_th05 c[116,95,116,104,48,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,101,120,105,116])))",
    "t_th06 c[116,95,116,104,48,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,115,116,97,114,116])))",
    "t_th07 c[116,95,116,104,48,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,105,115,95,116,104,114,101,97,100,95,101,120,105,116])))",
    "t_th08 c[116,95,116,104,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,101,120,105,116])))",
    "t_th09 c[116,95,116,104,48,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,115,116,97,114,116])))",
    "t_th10 c[116,95,116,104,49,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[97,115],a[109,105,100,100,108,101])))",
    "t_th11 c[116,95,116,104,49,49]/1(a[121,101,115])",
    "t_th12 c[116,95,116,104,49,50]/1(a[121,101,115])",
    "t_th13 c[116,95,116,104,49,51]/1(a[121,101,115])",
    "t_th14 c[116,95,116,104,49,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_th15 c[116,95,116,104,49,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[110,111,115,117,99,104,101,118,101,110,116])))",
    "t_th16 c[116,95,116,104,49,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[116,104,114,101,97,100,95,115,116,97,114,116])))",
    "t_th17 c[116,95,116,104,49,55]/1(a[109,97,105,110])",
    "t_th18 c[116,95,116,104,49,56]/1(a[121,101,115])",
    "t_th19 c[116,95,116,104,49,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[116,104,114,101,97,100,95,101,120,105,116],i1))))",
    "t_th20 c[116,95,116,104,50,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[105,115,95,101,110,103,105,110,101],i1))))",
    "t_th21 c[116,95,116,104,50,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[116,104,114,101,97,100,95,112,114,111,112,101,114,116,121],i2))))"
]

const _TH_DIVERGES = ["th01", "th02", "th03", "th04", "th05", "th06", "th07", "th08", "th09", "th16", "th19", "th20", "th21"]

function _th_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _TH_CASES]
    text =
        _TH_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TH_CASES
        ])
    f = joinpath(mktempdir(), "event.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _th_load(path::String)
    gd = LK.PL_global_data{_TH}()
    ld = LK.PL_local_data{_TH}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _th_enc(ball::_TH))
end

"The driver's line for `pred/1` (every answer, at most 50), the functor written as `asname`."
function _th_ask(gd, ld, pred::String, asname::String=pred)::String
    proc = LK.isCurrentProcedure(sym_key(_ths(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$asname undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TH, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols, _th_enc(mk_expr(_TH, _TH[_ths(asname), lk_answers(ld, (a:a)...)...]))
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
    return asname * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`."
function _th_kernel(path::String, names::Vector{String})
    gd, ld, st = _th_load(path)
    out = [st]
    for name in names
        push!(out, _th_ask(gd, ld, name))
    end
    return out, gd, ld
end

@testset "the event table of the ENGINES=OFF build: the kernel's answers" begin
    f, names = _th_file()
    kl, _, _ = _th_kernel(f, names)
    @test length(kl) == length(_TH_KERNEL)
    for (k, p) in zip(kl, _TH_KERNEL)
        k == p || println(stderr, "  ours   ", k, "\n  pinned ", p)
        @test k == p
    end
end

@testset "KNOWN DIFFERENCES: the oracle (threads=true, engines=true) answers otherwise" begin
    @test length(_TH_SWIPL) == length(_TH_KERNEL) == length(_TH_CASES) + 1
    @test _TH_SWIPL[1] == _TH_KERNEL[1] == "ok"
    differ = String[]
    for (id, _) in _TH_CASES
        s = only(filter(l -> startswith(l, "t_$id"), _TH_SWIPL))
        k = only(filter(l -> startswith(l, "t_$id"), _TH_KERNEL))
        s == k || push!(differ, id)
    end
    @test differ == _TH_DIVERGES
    @test length(_TH_DIVERGES) == 13                    # th01-th09, th16 (the three events) and th19-th21 (absent predicates)
    for id in ("th10", "th11", "th12", "th13", "th14", "th15", "th17", "th18")
        @test !(id in _TH_DIVERGES)                     # the controls: the same answer on both sides
    end
end

@testset "the table has nine rows (pl-event.c:81-89), the thread events are not rows" begin
    names = [String(et.name) for et in LK.PL_events]
    @test length(LK.PL_events) == 9
    @test names == [
        "abort", "erase", "erase", "break", "break", "break", "break", "frame_finished",
        "untable"
    ]
    @test all(i -> LK.PL_events[i + 1].id == i, 0:8)    # upstream's `assert(et->id == et-PL_events)`
    @test !any(et -> et.local_, LK.PL_events)            # the only local row was this_thread_exit
    @test LK.PLEV_THREAD_START == 9 && LK.PLEV_THREAD_EXIT == 10 && LK.PLEV_THIS_THREAD_EXIT == 11   # the enum keeps them (pl-event.h:52-54)
end

@testset "the oracle's lines are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TH1A LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _th_file()
        @test _th_swipl_lines(f, names) == _TH_SWIPL
    end
end
