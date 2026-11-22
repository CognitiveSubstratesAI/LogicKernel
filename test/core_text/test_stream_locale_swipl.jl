# ORIGINAL: a differential of open/4's locale(Locale) option, set_stream/2's locale(Locale) and the stream property locale(Locale) (pl-file.c) against swipl at the pin;
# test/core_text/test_locale_swipl.jl's harness
# test/core_text/test_stream_locale_swipl.jl — CT1 LOCALE-STREAM, through a PROGRAM: test_stream_locale_swipl.pl holds the rows, each a predicate
# `tN(R)` with ONE solution (a list of every action's result, in order); the kernel consults the program and enumerates every solution of
# every tN/1, and its lines are compared with test_stream_locale_swipl.out — swipl 10.1.20's own, printed by the driver below (`ok`, then one line per row:
# its name and its solution). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale. Every locale a row makes is
# made from the name "C" with decimal_point, thousands_sep and grouping given explicitly (the machine's locale is never read); the files are tmp_file/2
# names, written, read back and deleted by the row (no call here can block). The reference counting that swipl cannot show (open/4 gives back the
# reference getLocaleEx took) is the white-box testset at the end. UNTESTED when written (CT1-LOC-1, edit-only): the .out is swipl's (two identical
# runs), the kernel's side was never run.
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

const _SLS_PL = joinpath(@__DIR__, "test_stream_locale_swipl.pl")
const _SLS_OUT = joinpath(@__DIR__, "test_stream_locale_swipl.out")

# the rows' names, in the order of the program
_sls_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_SLS_PL, String))])

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
        while (n += 1) <= 100
            rc = LK.PL_next_solution(gd, ld, qid)
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
        read(pipeline(`swipl -q $f`; stderr=devnull, stdin=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the row's answers as the .out holds them, for the literal pins below
_sls_row(expected, name) = expected[findfirst(startswith(name * " "), expected)]
_a(s::String) = "a" * _codes(s)                                      # an atom, as `enc` prints it
function _lst(xs...)::String
    isempty(xs) && return "nil"
    return "c[91,124,93]/2(" * xs[1] * "," * _lst(xs[2:end]...) * ")"
end
_row1(name::String, arg::String) = "$name c" * _codes(name) * "/1(" * arg * ")"

@testset "CT1 LOCALE-STREAM: open/4 locale(Locale), set_stream/2 locale(Locale), stream_property locale(Locale) == swipl's answers (the .out), through a program" begin
    names = _sls_names()
    expected = String.(readlines(_SLS_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test names == ["t0", "t1", "t2", "t3", "t4", "t5"]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test all(l -> !endswith(l, " "), expected)                               # every row has an answer
    @test !any(l -> endswith(l, " exception"), expected)                      # errors are caught by the rows, none escapes

    # t0: the stream opened with locale(lcs0) answers the alias, and that locale's decimal_point and thousands_sep
    @test _sls_row(expected, "t0") == _row1("t0", _lst(_a("lcs0"), _a(","), _a(".")))
    # t1: a blob given, the alias destroyed under the open stream: the same blob answers, the locale lives on (decimal_point ;)
    @test _sls_row(expected, "t1") == _row1("t1", _lst(_a("lcs1"), _a("blob"), _a(";")))
    # t2: no option: the current locale, `default`, for a new stream and for the standard streams
    @test _sls_row(expected, "t2") ==
        _row1("t2", _lst(_a("default"), _a("default"), _a("default")))
    # t3: by alias, by set_stream/2 (alias, then blob: the alias again), the second stream untouched
    @test _sls_row(expected, "t3") ==
        _row1("t3", _lst(_a("lcs3"), _a("lcs3b"), _a("lcs3"), _a("default")))
    # t4: existence_error(locale, nosuch), type_error(locale, 1), type_error(locale, f(x)), instantiation_error, no file, then the same four of set_stream/2
    @test count(_codes("existence_error"), _sls_row(expected, "t4")) == 2
    @test count(_codes("type_error"), _sls_row(expected, "t4")) == 4
    @test count(_codes("instantiation_error"), _sls_row(expected, "t4")) == 2
    @test occursin(_codes("absent"), _sls_row(expected, "t4"))
    # t5: ~:d printed by the stream's locale, then by the locale set_stream/2 gave it: grouping [repeat(3)] with `.`, then [3,repeat(2)] with `_`
    @test _sls_row(expected, "t5") == _row1("t5", _lst(_a("1.234.567"), _a("12_34_567")))

    kl = kernel_lines(_TL, _SLS_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "STREAM-LOCALE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_SLS_PL, names) == expected                         # the .out is swipl's, still
    end
end

# THE COUNT (white-box: swipl cannot show a reference count): openStream takes the locale with getLocaleEx (+1), Ssetlocale gives the stream its own
# reference (+1), `releaseLocale` gives the first back (-1, "acquired by PL_scan_options"), and closing the stream the second (-1): an open/4 with
# locale(Alias) and its close leave the count where it was. set_stream/2 keeps getLocaleEx's reference (upstream does not release it: +1 over the
# stream's own, which Ssetlocale takes and the next change or the close gives back), so after it and the close the count is ONE higher.
const _SLS_WB = """
wb_mk :- locale_create(_, "C", [alias(slswb), decimal_point(',')]).
wb_open :- tmp_file(slswb, F), open(F, write, S, [locale(slswb)]), close(S), delete_file(F).
wb_set :- tmp_file(slswb, F), open(F, write, S, []), set_stream(S, locale(slswb)), close(S), delete_file(F).
wb_bad :- catch(( tmp_file(slswb, F), open(F, write, _, [locale(nosuchswb)]) ), error(_, _), true).
"""
function _sls_wb_once(gd, ld, name::String)::Bool
    proc = LK.isCurrentProcedure(sym_key(_tls(_TL, name)), 0, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc,
        LK.PL_new_term_refs(ld, 0)
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
end

@testset "CT1 LOCALE-STREAM: the reference count of a locale through open/4, close and set_stream/2" begin
    mktempdir() do d
        f = joinpath(d, "wb.pl")
        write(f, _SLS_WB)
        gd = LK.PL_global_data{_TL}()
        ld = LK.PL_local_data{_TL}(gd)
        st, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
        @test _sls_wb_once(gd, ld, "wb_mk")
        l = LK._locale_lookup(gd, _tls(_TL, "slswb"))::LK.PL_locale_rec{_TL}
        n0 = l.references
        @test n0 >= 1                                          # the table's own
        @test _sls_wb_once(gd, ld, "wb_open")
        @test l.references == n0                               # open + close: the count is where it was
        @test _sls_wb_once(gd, ld, "wb_open")
        @test l.references == n0
        @test _sls_wb_once(gd, ld, "wb_bad")                   # a refused open takes nothing
        @test l.references == n0
        @test _sls_wb_once(gd, ld, "wb_set")
        @test l.references == n0 + 1                           # upstream's set_stream/2 leaves getLocaleEx's reference
    end
end

# stream_locale_prop (white-box): a stream that holds no locale has no `locale` property (upstream: `if ( s->locale )`; every stream a Prolog call makes
# has one since initStreamLocale, so no row above reaches the `nothing` branch), and one that holds a locale answers the locale's ALIAS (unifyLocale(..., true)).
@testset "CT1 LOCALE-STREAM: stream_locale_prop answers nothing without a locale, the alias with one" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")::LK.IOSTREAM
    t = LK.PL_new_term_ref(ld)
    @test s.locale === nothing
    @test LK.stream_locale_prop(ld, s, t) === false
    @test LK.PL_get_atom(ld, t) === nothing                    # nothing was unified
    def = gd.locale.default_locale::LK.PL_locale_rec{_TL}
    LK.Ssetlocale(s, def)
    @test LK.stream_locale_prop(ld, s, t) === true
    a = LK.PL_get_atom(ld, t)
    @test a !== nothing && sym_text(a) == "default"            # the alias, not a blob
    LK.Sclose(s)
end
