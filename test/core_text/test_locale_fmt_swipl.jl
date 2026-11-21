# ORIGINAL: a differential of format/2's `~:d` and `~:f` (the locale of the output stream, `fd->locale`: pl-fmt.c, pl-locale.c initStreamLocale,
# pl-stream.c Ssetlocale) and of collation_key/2 (pl-prims.c) against swipl at the pin; test/core_text/test_locale_swipl.jl's harness
# test/core_text/test_locale_fmt_swipl.jl — LOCALE-FMT-1: the per-stream locale and collation_key/2, through a PROGRAM: test_locale_fmt_swipl.pl holds
# the rows, each a predicate `tN(R)` with ONE solution; the kernel consults the program and enumerates every solution of every tN/1, and its lines are
# compared with test_locale_fmt_swipl.out — swipl 10.1.20's own (`ok`, then one line per row; two identical runs). When `swipl` is on PATH the .out is
# checked against a live run as well. The rows are upstream's tests/core_text/test_locale.pl (`group` ~:d / ~:f / ~:e, format_with_locale,
# default_decimal_point, no_locale, WCSXFRM_BUFFER_OVERRUN) plus the cases of the stream's locale (the five standard streams follow set_locale/1,
# every other stream keeps the locale it was made with) and of collation_key/2. The testset after the rows captures user_output and user_error
# (the five standard streams cannot be captured by a row) and compares them with swipl's output of the same program. Not OS dependent: every locale
# is made from "C" with explicit properties, collation_key/2 is checked by its relation and its type, not its bytes.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

# swipl writes a float in the shortest form that reads back and leaves positional notation for 1e-4 <= |v| < 1e15 (Julia's `string` goes to
# the exponent from 1e6 on: 1.23456789e6), so the text of a float is made from Julia's shortest digits by hand
function _swipl_float(v::AbstractFloat)::String
    str = string(v)
    m = match(r"^(-?)(\d+)\.(\d+)e(-?\d+)$", str)
    (m === nothing || !(1.0e-4 <= abs(v) < 1.0e15)) && return str
    ip, fp, e = String(m[2]), String(m[3]), parse(Int, m[4])
    digits = ip * fp
    pt = length(ip) + e
    body = if pt <= 0
        "0." * "0"^(-pt) * digits
    elseif pt >= length(digits)
        digits * "0"^(pt - length(digits)) * ".0"
    else
        digits[1:pt] * "." * digits[(pt + 1):end]
    end
    return m[1] * body
end

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
        v isa AbstractFloat && return "f" * _swipl_float(v)
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _LCF_PL = joinpath(@__DIR__, "test_locale_fmt_swipl.pl")
const _LCF_OUT = joinpath(@__DIR__, "test_locale_fmt_swipl.out")

# the rows' names, in the order of the program
_lcf_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_LCF_PL, String))])

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




@testset "LOCALE-FMT: format/2 ~:d ~:f and collation_key/2 == swipl's answers (the .out), through a program" begin
    names = _lcf_names()
    expected = String.(readlines(_LCF_OUT))
    # not a vacuous agreement: the .out has a line per row, every row has an answer, and the rows' own evidence is in it
    @test length(names) == 16
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test all(l -> !endswith(l, " "), expected)
    @test !any(l -> endswith(l, " exception"), expected)
    row(n) = expected[findfirst(startswith(n * " "), expected)]
    @test occursin(_codes("1,000.00"), row("t0")) &&
        occursin(_codes("1,234,567"), row("t0"))   # ~2:d, ~:d under lfa
    @test occursin(_codes("1_234_567"), row("t0"))                                              # ~:D
    @test occursin(_codes("1,234,567,890.00"), row("t1")) &&
        occursin(_codes("-0.00"), row("t1"))   # ~2:f
    @test !occursin(_codes("1,00e"), row("t2")) && occursin(_codes("1.00e+03"), row("t2"))      # ~:e does not take the locale
    @test occursin(_codes("12 345 67,89"), row("t3"))                                            # lfb
    @test occursin(_codes("1234567.89"), row("t4")) &&
        occursin(_codes("12345.67"), row("t4"))   # lfd: no grouping
    @test occursin(_codes("12345,67,89"), row("t5")) &&
        occursin(_codes("123456x789"), row("t5"))
    @test occursin(_codes("12 345 67 "), row("t9"))                                              # a stream keeps the locale it was made with
    @test occursin(_codes("12_34_56_7;50")[2:end], row("t10"))
    @test occursin(_codes("12 345 67"), row("t11")) &&
        occursin(_codes("1,234,567"), row("t11"))
    @test occursin(_codes("instantiation_error"), row("t15")) &&
        occursin(_codes("type_error"), row("t15"))

    for T in (_TL,)
        kl = kernel_lines(T, _LCF_PL, names)
        @test length(kl) == length(expected)
        for i in eachindex(kl)
            @test (i, kl[i]) == (i, expected[i])
        end
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LOCALE-FMT DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_LCF_PL, names) == expected                         # the .out is swipl's, still
    end
end

# THE FIVE STANDARD STREAMS (pl-locale.c set_locale: Ssetlocale on the first five): a row cannot capture user_output and user_error, so the program
# runs with each of them over a buffer (`set_standard_stream!`, the host's way) and the text of both is compared with swipl's own output of the same
# program (stdout and stderr). The program sets a locale, prints, sets another, prints again (set_locale/1 reaches the streams made before it), and
# prints to the current output (it IS user_output here).
const _LCF_STD = """
:- locale_create(_, "C", [alias(lfs), decimal_point(','), thousands_sep('.'), grouping([repeat(3)])]), set_locale(lfs).
:- format(user_output, '~:d|~2:d|~2:f|~2:e|~2f|~D|~2:g~n', [1234567, 1234567, 1234567.5, 1234567.5, 1234567.5, 1234567, 1234567.5]).
:- format(user_error, '~:d|~2:f~n', [1234567, 1234567.5]).
:- current_output(S), format(S, '~:d~n', [7654321]), format('~:d~n', [1234]).
:- locale_create(_, "C", [alias(lfs2), decimal_point(';'), thousands_sep('_'), grouping([1,repeat(2)])]), set_locale(lfs2).
:- format(user_output, '~:d~n', [1234567]), format(user_error, '~:d~n', [1234567]).
:- set_locale(lfs), format(user_output, '~:d~n', [1234567]).
"""

function _lcf_std_kernel(::Type{T}, path::String)::Tuple{String, String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    out, err = IOBuffer(), IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    LK.set_standard_stream!(ld, LK.SNO_USER_ERROR, err)
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    LK.Sflush(LK.Suser_output(ld))
    LK.Sflush(LK.Suser_error(ld))
    return String(take!(out)), String(take!(err))
end

@testset "LOCALE-FMT: user_output and user_error follow set_locale/1 (the five standard streams), as swipl's" begin
    mktempdir() do d
        f = joinpath(d, "std.pl")
        write(f, _LCF_STD)
        out, err = _lcf_std_kernel(_TL, f)
        # not vacuous: the locale really shows on both streams, the colonless directives and ~:e do not take it
        @test out ==
            "1.234.567|12.345,67|1.234.567,50|1.23e+06|1234567.50|1,234,567|1.2e+06\n7.654.321\n1.234\n" *
              "12_34_56_7\n1.234.567\n"
        @test err == "1.234.567|1.234.567,50\n12_34_56_7\n"
        swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
        if swipl === nothing
            @info "LOCALE-FMT STANDARD STREAMS NOT RUN LIVE: `swipl` is not on PATH here (the expected texts above were measured with swipl 10.1.20)."
        else
            ef = joinpath(d, "err.txt")
            sout = read(pipeline(`swipl -q -g halt $f`; stderr=ef), String)
            @test sout == out
            @test read(ef, String) == err
        end
    end
end

# THE READING of the stream's locale (pl-fmt.c `fd->locale`, here `_stream_locale`): nothing on a stream without one, the stream's own fields once it holds
# one (the counted reference itself is test/core_text/test_locale_stream_swipl.jl's).
@testset "LOCALE-FMT: _stream_locale reads the locale the stream holds" begin
    l = LK.new_locale(_TL, nothing)
    l.decimal_point = ","
    l.thousands_sep = "."
    l.grouping = Int[3, 0]
    LK.acquireLocale(l)
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")::LK.IOSTREAM
    @test LK._stream_locale(s) === nothing
    LK.Ssetlocale(s, l)
    let pl = LK._stream_locale(s)
        @test pl !== nothing &&
            (pl.decimal_point, pl.thousands_sep, pl.grouping) == (",", ".", Int[3, 0])
    end
    LK.Sclose(s)
    LK.releaseLocale(l)
    @test l.references == 0
end
