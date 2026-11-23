# ORIGINAL: a differential of pl-trace.c's prolog_frame_attribute/3 against swipl at the pin (the old line's DBG1b rows, the harness of its
# test/core_lang/test_dbg1_swipl.jl: `kernel_lines` runs every row through the swipl driver's own wrapper chain).
# test/core_lang/test_frameattr_swipl.jl — through a PROGRAM: test_frameattr_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel
# consults the program and enumerates every solution of every tN/1, and its lines are compared with test_frameattr_swipl.out — the pin's swipl
# 10.1.20's own, printed by the driver below (`ok`, then one line per row: its name and every solution). When `swipl` is on
# PATH the .out is checked against a live run as well, so it cannot go stale.
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

const _DB_PL = joinpath(@__DIR__, "test_frameattr_swipl.pl")
const _DB_OUT = joinpath(@__DIR__, "test_frameattr_swipl.out")

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

@testset "prolog_frame_attribute/3 == swipl's answers (the .out), through a program" begin
    names = _db_names()
    expected = String.(readlines(_DB_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test names == vcat(["t$i" for i in 24:48], ["t$i" for i in 58:65])
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test _db_count(expected, "type_error") == 4 && _db_count(expected, "domain_error") == 6
    @test _db_count(expected, "frame_reference") == 2 && _db_count(expected, "natural") == 1
    @test _db_count(expected, "findall_loop") == 1                          # t65 names the system frame it reads (hidden)
    @test _db_count(expected, "ran") == 2                                   # t62, t63: the cleanup handler of a watched frame ran

    kl = kernel_lines(_TL, _DB_PL, names)
    @test length(kl) == length(expected)
    # the same extractor over the kernel's lines: the kernel answers the errors and the frames' names, not only the same number of lines
    for w in
        ("type_error", "domain_error", "frame_reference", "natural", "findall_loop", "ran")
        @test _db_count(kl, w) == _db_count(expected, w)
    end
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "FRAMEATTR DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_DB_PL, names) == expected                          # the .out is swipl's, still
    end
end
