# ORIGINAL: a differential of Y1's system predicates (pl-sys.c, pl-prims.c statistics/2, pl-files.c delete_file/1) against swipl at the pin
# test/core_lang/test_sys_swipl.jl — getenv/2, setenv/2, unsetenv/1, get_time/1, sleep/1, statistics/2 and delete_file/1,
# through a PROGRAM (the pattern of test/core_lang/test_between_swipl.jl): test_sys_swipl.pl holds the rows, each a predicate
# `tN(R)`; the kernel consults the program and enumerates every solution of every tN/1, and its lines are compared with
# test_sys_swipl.out — swipl 10.1.19's own, printed by the driver below (`ok`, then one line per row: its name and
# every solution). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale.
# The values the machine decides — the time, the CPU, the stacks, the environment — are compared by TYPE or by an
# order in the rows themselves; the error rows are swipl's formal term AND context, the message of `errno` included.
# The program works in a fresh directory that holds the files delete_file/1 removes (lk_y1_victim, lk_y1_emptydir) and
# one it cannot (lk_y1_nonempty_dir); after the kernel's run the test checks what is left on the disk.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
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

const _SYS_PL = joinpath(@__DIR__, "test_sys_swipl.pl")
const _SYS_OUT = joinpath(@__DIR__, "test_sys_swipl.out")

# the rows' names, in the order of the program
_sys_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_SYS_PL, String))])

# the files the delete_file/1 rows work on, in the current directory
function _sys_prepare()
    write("lk_y1_victim", "")
    mkdir("lk_y1_emptydir")
    mkdir("lk_y1_nonempty_dir")
    write(joinpath("lk_y1_nonempty_dir", "inner"), "")
    return nothing
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 100
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
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
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
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

# run `f` in a fresh directory with the files the rows work on; the directory is removed afterwards
function _in_prepared_dir(f::Function)
    return mktempdir() do d
        cd(d) do
            _sys_prepare()
            f(d)
        end
    end
end

@testset "Y1: the system predicates == swipl's answers (the .out), through a program" begin
    names = _sys_names()
    expected = String.(readlines(_SYS_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) >= 90
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 6   # delete_file's, and one of them a context
    @test count(l -> occursin(_codes("No such file or directory"), l), expected) >= 6
    @test any(l -> occursin(_codes("Invalid argument"), l), expected)         # setenv/2, unsetenv/1 (errno)
    @test any(l -> occursin(_codes("statistics_key"), l), expected)
    @test any(l -> occursin(_codes("permission_error"), l), expected)         # a directory that is not empty
    @test any(l -> occursin(_codes("max_path_length"), l), expected)          # a name of 5000 characters

    kl = _in_prepared_dir() do d
        lines = kernel_lines(_SYS_PL, names)
        # the file system after the run: the victim and the empty directory are gone, the other directory stays
        @test !ispath("lk_y1_victim") && !ispath("lk_y1_emptydir")
        @test isdir("lk_y1_nonempty_dir") && isfile(joinpath("lk_y1_nonempty_dir", "inner"))
        lines
    end
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end
    for k in ("lk_y1_a",)                                          # (the rows' own variable)
        delete!(ENV, k)
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "SYSTEM-PREDICATE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        sw = _in_prepared_dir(d -> swipl_lines(_SYS_PL, names))
        @test sw == expected                                       # the .out is swipl's, still
    end
end
