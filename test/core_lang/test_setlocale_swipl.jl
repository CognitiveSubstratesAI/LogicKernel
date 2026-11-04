# ORIGINAL: a differential of setlocale/3 (pl-ctype.c) against swipl at the pin; test/core_lang/test_sys_swipl.jl's harness
# test/core_lang/test_setlocale_swipl.jl — setlocale/3, through a PROGRAM (the pattern of test/core_lang/test_sys_swipl.jl):
# test_setlocale_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults the program and enumerates every
# solution of every tN/1, and its lines are compared with test_setlocale_swipl.out — swipl 10.1.19's own, printed by the
# driver below (`ok`, then one line per row: its name and every solution). When `swipl` is on PATH the .out is checked
# against a live run as well, so it cannot go stale.
# The locales the rows name are the ones every glibc has: C, POSIX, '' (the environment) and C.utf8 (built into glibc
# since 2.35, installed by the locales package before it; CI and this machine are Ubuntu): an installed locale such as
# en_US.utf8 never appears in a row. What the machine decides (the environment's LANG, the locales installed) never
# reaches an answer: a row reads the names it set itself, through the environment variables it set itself, and every row
# puts the process locale and the variables back, so the rows are independent of each other and of the host.
# The error rows are swipl's formal term AND context (`setlocale` with its errno message, the encoding message).
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

const _SLC_PL = joinpath(@__DIR__, "test_setlocale_swipl.pl")
const _SLC_OUT = joinpath(@__DIR__, "test_setlocale_swipl.out")

# the rows that need an atom holding the character 0 (see the testset)
const _SLC_NUL_ROWS = ["t25", "t26", "t31"]

# the rows' names, in the order of the program
_slc_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_SLC_PL, String))])

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

# the process locale of every category, as libc answers it: the test checks that the rows put it back
const _SLC_CATS = (
    LK.LC_ALL, LK.LC_COLLATE, LK.LC_CTYPE, LK.LC_MESSAGES,
    LK.LC_MONETARY, LK.LC_NUMERIC, LK.LC_TIME
)
_slc_locales() = String[first(LK._libc_setlocale(c, nothing)) for c in _SLC_CATS]

@testset "CT1a: setlocale/3 == swipl's answers (the .out), through a program" begin
    names = _slc_names()
    expected = String.(readlines(_SLC_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) >= 30
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 3   # a locale libc does not have
    @test count(l -> occursin(_codes("domain_error"), l), expected) >= 3      # a category that is not one
    @test count(l -> occursin(_codes("representation_error"), l), expected) >= 3   # a character above 0xFF
    @test any(l -> occursin(_codes("instantiation_error"), l), expected)
    @test any(l -> occursin(_codes("type_error"), l), expected)
    @test any(l -> occursin(_codes("setlocale"), l), expected)                # the context of the errno message
    t0 = expected[findfirst(startswith("t0 "), expected)]
    for cat in ("all", "collate", "ctype", "messages", "monetary", "numeric", "time")
        @test occursin(_codes(cat), t0)                                       # every category is queried
    end

    before = _slc_locales()
    main = filter(n -> !(n in _SLC_NUL_ROWS), names)
    keep = [1; [i + 1 for i in eachindex(names) if !(names[i] in _SLC_NUL_ROWS)]]
    kl = kernel_lines(_TL, _SLC_PL, main)
    @test length(kl) == length(keep) && length(kl) == length(expected) - length(_SLC_NUL_ROWS)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[keep[i]])
    end
    @test _slc_locales() == before                                            # the rows put the locales back
    # KNOWN DIFFERENCE (pinned): the kernel's atoms are Symbols and cannot hold the character 0, so `atom_codes/2` in these
    # three rows raises the kernel's NotPortedError ("an atom containing the character 0", the term interface) before
    # setlocale/3 is reached. swipl's answers (the .out): t25 'C' (the text ends at its NUL), t26 ok, t31 the
    # representation_error(encoding) of the 0x20AC after the NUL. Each row runs in its own database (the run is cut short).
    for n in _SLC_NUL_ROWS
        @test kernel_lines(_TL, _SLC_PL, [n]) == ["ok", n * " notported"]
    end
    @test length(_SLC_NUL_ROWS) == 3 && all(n -> n in names, _SLC_NUL_ROWS)
    @test all(!isempty, before)

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "SETLOCALE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_SLC_PL, names) == expected                         # the .out is swipl's, still
    end
end
