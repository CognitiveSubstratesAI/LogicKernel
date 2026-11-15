# ORIGINAL: a differential of tty_size/2, tty_get_capability/3, tty_goto/2 and tty_put/2 (pl-term.c) against swipl at the pin; test/core_lang/test_dwim_swipl.jl's harness
# test/core_lang/test_tty_swipl.jl — the terminal predicates of pl-term.c, through a PROGRAM (the pattern of
# test/core_lang/test_dwim_swipl.jl): test_tty_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults
# the program and enumerates every solution of every tN/1, and its lines are compared with test_tty_swipl.out — swipl
# 10.1.20's own, printed by the driver below (`ok`, then one line per row: its name and every solution). When `swipl` is
# on PATH the .out is checked against a live run as well, so it cannot go stale. A run is NOT on a terminal: swipl gets
# stdin from /dev/null, the kernel's row t3 is compared only when its own stdin is no terminal either.
# Rows t0-t2 are the argument checks (answered before the terminal library is reached), row t3 is tty_size/2 on a
# descriptor that is no terminal, rows t4-t7 are the FIRST call into the terminal library of a process: swipl keeps the
# state of a failed TERM lookup (`term_initialised`), so each of t4-t7 is a swipl process of its own, with TERM unset
# (t4-t6) or of 100 bytes (t7, the size of swipl's buffer: as unset). The kernel does not keep that state (named
# divergence, src/pl-term.jl `initTerm`): its answer to a later call is the TERM error again, pinned below.
# Rows lk0-lk3 are LK-ONLY (the test's own expectations): with TERM set the calls into libtinfo are refused, owner TTY2.
# The terminal path of tty_size/2 is read through `_tty_size_answer` with a FAKE `ioctl` result (no terminal needed).
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

const _TT_PL = joinpath(@__DIR__, "test_tty_swipl.pl")
const _TT_OUT = joinpath(@__DIR__, "test_tty_swipl.out")

# the pinned rows, and LK-ONLY rows, in the order of the program
_tt_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_TT_PL, String))])
_tt_lk_names() =
    unique([String(m[1]) for m in eachmatch(r"^(lk\d+)\(R\) :-"m, read(_TT_PL, String))])

# the swipl processes of the pin run: t0-t3 share one, each of t4-t7 has its own; TERM is unset except for t7
const _TT_GROUPS = [["t0", "t1", "t2", "t3"], ["t4"], ["t5"], ["t6"], ["t7"]]
const _TT_TERM7 = "x"^100
_tt_term(g::Vector{String}) = g == ["t7"] ? _TT_TERM7 : nothing

# the message of the last refusal the kernel's run met (kernel_lines prints only `<name> notported`)
const _TT_LAST_NP = Ref{String}("")

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                _TT_LAST_NP[] = sprint(showerror, e)
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        if notported
            push!(out, "$name notported")    # the run's ld is thrown away: the query stays open
            return out
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the kernel's lines of the pinned rows: the groups of the pin run, each with its TERM (`ok` once)
function kernel_pinned(::Type{T}, path::String)::Vector{String} where {T}
    out = String[]
    for g in _TT_GROUPS
        ls = withenv("TERM" => _tt_term(g)) do
            kernel_lines(T, path, g)
        end
        append!(out, isempty(out) ? ls : ls[2:end])
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_dwim_swipl.jl's)
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

# one swipl process on a group: stdin from /dev/null, TERM unset (`env -u TERM`) or of 100 bytes
function swipl_group(swipl::String, path::String, g::Vector{String})::Vector{String}
    term = _tt_term(g)
    envargs = term === nothing ? ["-u", "TERM"] : ["TERM=" * term]
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(g, ",") *
            "]), halt)).\n"
        )
        cmd = Cmd(["env", envargs..., swipl, "-q", f])
        read(pipeline(cmd; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end
function swipl_pinned(swipl::String, path::String)::Vector{String}
    out = String[]
    for g in _TT_GROUPS
        ls = swipl_group(swipl, path, g)
        append!(out, isempty(out) ? ls : ls[2:end])
    end
    return out
end

# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_tt_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

# the answer of `_tty_size_answer` to a (fake) ioctl result: (success, error term or the two answers, exception pending)
function size_answer(
    ::Type{T}, iorval::Int, rows::Int, cols::Int, errno::Int;
    bound::Union{Nothing, Int}=nothing
)::Tuple{Bool, String, Bool} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    a = LK.PL_new_term_refs(ld, 2)
    bound === nothing || LK.PL_put_int64(ld, a, bound)
    ok = LK._tty_size_answer(ld, a, a + 1, iorval, rows, cols, errno)
    pending = ld.exception_term != 0
    text = if pending
        enc(lk_answer(ld, LK.PL_exception(ld, 0)))
    else
        join(enc.(lk_answers(ld, a, a + 1)), ",")
    end
    return (ok, text, pending)
end

_tt_syserr(msg::String) =
    "c" * _codes("error") * "/2(a" * _codes("system_error") * ",c" * _codes("context") *
    "/2(c" * _codes("/") * "/2(a" * _codes("tty_size") * ",i2),a" * _codes(msg) * "))"

@testset "TTY1: tty_size/2, tty_get_capability/3, tty_goto/2, tty_put/2 == swipl's answers (the .out), through a program" begin
    names = _tt_names()
    expected = String.(readlines(_TT_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test names == ["t$i" for i in 0:7]
    @test _tt_lk_names() == ["lk$i" for i in 0:3]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test _tt_count(expected[2:2], "tty_get_capability") >= 30      # t0: 15 answers, each names it twice
    @test _tt_count(expected[3:3], "tty_goto") >= 17
    @test _tt_count(expected[4:4], "tty_put") >= 19
    @test _tt_count(expected[5:5], "Inappropriate ioctl for device") == 5   # t3: every answer is the ioctl's
    for i in 6:9                                                    # t4-t7: the TERM error, once each
        @test _tt_count(expected[i:i], "TERM") == 1
        @test _tt_count(expected[i:i], "existence_error") == 1
    end

    kl = kernel_pinned(_TL, _TT_PL)
    @test length(kl) == length(expected)
    t3ok = let (rc, _, _, en) = LK._tty_winsize(0)
        rc != 0 && en == 25                                         # ENOTTY: stdin is no terminal
    end
    t3ok ||
        @info "TTY1 row t3 NOT COMPARED: this process's stdin is a terminal (swipl's pin run is not)"
    for i in eachindex(kl)
        i == 5 && !t3ok && continue
        @test (i, kl[i]) == (i, expected[i])
    end

    # the kernel's own answer to a LATER call with TERM unset: the TERM error again (swipl's later calls fail silently:
    # the `term_initialised` state is kept by TTY2); each answer is the first-call row t4's
    k2 = withenv("TERM" => nothing) do
        kernel_lines(_TL, _TT_PL, ["t4", "t4"])
    end
    @test k2 == ["ok", expected[6], expected[6]]

    # LK-ONLY: with TERM set the calls into libtinfo are refused, owner TTY2
    for name in _tt_lk_names()
        _TT_LAST_NP[] = ""
        lk = withenv("TERM" => "xterm") do
            kernel_lines(_TL, _TT_PL, [name])
        end
        @test lk == ["ok", "$name notported"]
        @test occursin("TTY2", _TT_LAST_NP[])
    end

    # the terminal path of tty_size/2: `_tty_winsize` on descriptors that are no terminal
    if Sys.islinux()
        mktempdir() do d
            f = joinpath(d, "plain")
            write(f, "x")
            open(f) do io
                @test LK._tty_winsize(Int(Base.fd(io).fd)) == (-1, 0, 0, 25)   # ENOTTY
            end
        end
        @test LK._tty_winsize(9999) == (-1, 0, 0, 9)                       # EBADF
    end
    # `_tty_size_answer` on a FAKE ioctl result: the error of a failed ioctl, the unified answer of a good one
    for (errno, msg) in ((25, "Inappropriate ioctl for device"), (9, "Bad file descriptor"))
        @test size_answer(_TL, -1, 0, 0, errno) == (false, _tt_syserr(msg), true)
    end
    @test size_answer(_TL, 0, 24, 80, 0) == (true, "i24,i80", false)
    @test size_answer(_TL, 0, 24, 80, 0; bound=24) == (true, "i24,i80", false)
    # a bound answer that differs: fails
    @test size_answer(_TL, 0, 24, 80, 0; bound=30) == (false, "i30,V0", false)

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TTY DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_pinned(swipl, _TT_PL) == expected                      # the .out is swipl's, still
    end
end
