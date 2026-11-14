# ORIGINAL: a differential of the debugger's state built-ins (pl-trace.c: trace/0, notrace/0, tracing/0, '$leash'/2, '$visible'/2) and
# pl-pro.c's '$call_no_catch'/1 and '$can_yield'/0 against swipl at the pin; test/core_lang/test_dbg1_swipl.jl's harness.
# test/core_lang/test_dbg1_swipl.jl — through a PROGRAM: test_dbg1_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults
# the program and enumerates every solution of every tN/1, and its lines are compared with test_dbg1_swipl.out — the pin's swipl
# 10.1.20's own, printed by the driver below (`ok`, then one line per row: its name and every solution). When `swipl` is on
# PATH the .out is checked against a live run as well, so it cannot go stale.
# Groups appended as DBG1 lands them: (a) rows t0-t23, (b) rows t24-t78 (prolog_frame_attribute/3, prolog_choice_attribute/3, the mutants' rows, the FR_WATCHED branches of the last-call instructions, Q2: the TRACE_ME flag of system and `\$` predicates) here. The kernel runs without a tracer: `trace/0` with a visible port is a NAMED
# REFUSAL (NotPortedError, step DBG1), tested on its own program below (swipl would stop in its tracer).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _DB_PL = joinpath(@__DIR__, "test_dbg1_swipl.pl")
const _DB_OUT = joinpath(@__DIR__, "test_dbg1_swipl.out")

# the rows' names, in the order of the program
_db_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_DB_PL, String))])

# the kernel runs EVERY row through the swipl driver's own wrapper chain, so the choice points and frames below a row (its `alternative`, its
# parents) are the driver's: fz_run's forall/2 over member/2 over the names, fz_pred's catch/3 over a collecting call of the row's goal, the
# solutions' forall/2. The text below is that chain in Prolog, the same for every row; the only differences from the DRIVER's: findall/3 collects
# where the driver's findnsols/4 does (findnsols/4's `'$suspend_findall_bag'` is a nondeterministic foreign predicate that pl-bag.jl's header lists as still to port: the rows are
# finite and well under 100 solutions, and both loops run the goal under a disjunction (JUMP choice point) of a system predicate), the solutions
# are asserted (fz_out/1) instead of printed, because the kernel's lines are encoded in Julia by `enc`, and fz_kact/2 runs the row named by its
# second argument only (the other names are walked past, so the choice point member/2 leaves for the rows still to come is the driver's, and a
# row that raises a NotPortedError ends only its own query). No row is named in it.
_db_kdriver(names) =
    "fz_names([" * join(names, ",") * "]).\n" * raw"""
:- dynamic fz_out/1.
fz_kact(N, T) :-
    (   N == T
    ->  functor(G, N, 1),
        catch(findall(G, G, Gs), _, Gs = [exception]),
        forall(member(S, Gs), assertz(fz_out(S)))
    ;   true
    ).
fz_krow(T) :- fz_names(Ns), retractall(fz_out(_)), forall(member(N, Ns), fz_kact(N, T)).
"""

# open a query on the arity-1 predicate `pname` of user with `arg`, call `onsol(ref)` at each solution (at most 100); :ok, :exception, :undefined, :notported
function _db_query(
    ::Type{T}, gd, ld, pname::String, arg::T, onsol::Function
)::Symbol where {T}
    proc = LK.isCurrentProcedure(sym_key(_tls(T, pname)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return :undefined
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, arg, LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    status = :ok
    n = 0
    while (n += 1) <= 100
        rc = try
            LK.PL_next_solution(gd, ld, qid)
        catch e
            e isa LK.NotPortedError || rethrow()
            return :notported                  # the run's ld is thrown away: the query stays open
        end
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            onsol(a)
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            status = :exception
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return status
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    wf = tempname() * ".pl"
    write(wf, _db_kdriver(names))
    st2, ball2 = LK.load_file!(gd, ld, wf)
    rm(wf; force=true)
    st2 === :ok || push!(out, "exc " * enc(ball2::T))
    for name in names
        status = _db_query(T, gd, ld, "fz_krow", _tls(T, name), _ -> nothing)
        if status === :notported
            push!(out, "$name notported")
            return out
        end
        sols = String[]
        if status === :ok
            _db_query(
                T, gd, ld, "fz_out", mk_var(T, LK.fresh_var_keys!(1)),
                a -> push!(
                    sols,
                    try
                        s = first(lk_answers(ld, (a:a)...))
                        if kind(s) === SYM && sym_text(s) == "exception"
                            "exception"
                        else
                            enc(s)
                        end
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
                )
            )
        else
            push!(sols, "exception")
        end
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output)
const DRIVER = raw"""
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# ONE extractor for both sides: how many times a line holds an atom or functor name (as `enc` writes it)
_db_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "DBG1 (a)+(b): tracing, \$leash, \$visible, \$call_no_catch, \$can_yield, prolog_frame_attribute/3, prolog_choice_attribute/3 == swipl's answers (the .out), through a program" begin
    names = _db_names()
    expected = String.(readlines(_DB_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test names == vcat(["t$i" for i in 0:19], ["t$i" for i in 21:78])     # t20 is not a row (see the .pl)
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test _db_count(expected, "findall_loop") == 2                          # t65 names the system frame it reads (hidden); t74 asks it for TRACE_ME
    @test _db_count(expected, "wc_ball") == 3                               # t69-t71: the listener's ball is thrown by the last-call instruction
    @test count(l -> occursin("i335", l), expected) >= 3                  # the initial masks (CALL|FAIL|REDO|EXIT|CUT_CALL|EXCEPTION)
    @test _db_count(expected, "type_error") >= 3 &&
        _db_count(expected, "representation_error") >= 2
    @test _db_count(expected, "on") >= 3 && _db_count(expected, "off") >= 5   # tracing/0 answers both ways

    kl = kernel_lines(_TL, _DB_PL, names)
    @test length(kl) == length(expected)
    # the same extractor over the kernel's lines: the kernel answers the errors and both tracing states, not only the same number of lines
    @test _db_count(kl, "findall_loop") == _db_count(expected, "findall_loop")
    @test _db_count(kl, "wc_ball") == _db_count(expected, "wc_ball")
    @test _db_count(kl, "type_error") == _db_count(expected, "type_error")
    @test _db_count(kl, "representation_error") ==
        _db_count(expected, "representation_error")
    @test _db_count(kl, "on") == _db_count(expected, "on") &&
        _db_count(kl, "off") == _db_count(expected, "off")
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "DBG1 DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_DB_PL, names) == expected                          # the .out is swipl's, still
    end
end

# the refusal: trace/0 with a port visible (the kernel has no tracer; swipl would stop in its tracer at the next call)
@testset "DBG1 (a): trace/0 with a visible port is a named refusal; with none visible it is tracemode(true)" begin
    mktempdir() do d
        f = joinpath(d, "refuse.pl")
        write(f, "t0(R) :- tracing -> R = on ; R = off.\nt1(R) :- trace, R = traced.\n")
        kl = kernel_lines(_TL, f, ["t0", "t1"])
        # t0: tracing/0 is false; t1 raises NotPortedError at trace/0 (visible ports: the initial mask), the run is ended there
        @test kl[1] == "ok"
        @test kl[2] == "t0 " * enc(mk_expr(_TL, _TL[_tls(_TL, "t0"), _tls(_TL, "off")]))
        @test kl[3] == "t1 notported"
        @test length(kl) == 3
        # one visible port of each kind refuses; a mask outside PORT_MASK (0x200) shows no port, and trace/0 is tracemode(true)
        for (v, refused) in (
            (1, true),
            (2, true),
            (4, true),
            (8, true),
            (16, true),
            (64, true),
            (128, true),
            (256, true),
            (511, true),
            (512, false),
            (0, false)
        )
            g = joinpath(d, "v$(v).pl")
            write(g, "t0(R) :- '\$visible'(_, $v), trace, tracing, notrace, R = traced.\n")
            kv = kernel_lines(_TL, g, ["t0"])
            @test kv == (
                if refused
                    ["ok", "t0 notported"]
                else
                    [
                        "ok",
                        "t0 " *
                        enc(mk_expr(_TL, _TL[_tls(_TL, "t0"), _tls(_TL, "traced")]))
                    ]
                end
            )
        end
    end
end

# I_EXITQUERY's FR_WATCHED branch (pl-vmi.c:2373 at the pin): the query's top frame, read by prolog_frame_attribute/3 (FR_NOTIFY), is finished
# when its query exits deterministically, so a frame_finished listener sees TWO events from wq1/1: its own frame's (exit_watched) and the top
# frame's. Two queries of their own: the second reads the count. No swipl answer (a Prolog row cannot see the exit of its own query's top frame):
# the 2 is read from the C (wq1's frame leaves through exit_continue -> exit_watched, the top frame through I_EXITQUERY).
@testset "DBG1 (e): the query's top frame, watched through FR_NOTIFY, is finished at its deterministic exit (I_EXITQUERY)" begin
    T = _TL
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, _ = LK.load_file!(gd, ld, _DB_PL)
    @test st === :ok
    @test _db_query(T, gd, ld, "wq1", mk_var(T, LK.fresh_var_keys!(1)), _ -> nothing) ===
        :ok
    seen = String[]
    @test _db_query(
        T, gd, ld, "wq2", mk_var(T, LK.fresh_var_keys!(1)),
        a -> push!(seen, enc(first(lk_answers(ld, (a:a)...))))
    ) === :ok
    @test seen == ["i2"]
end
