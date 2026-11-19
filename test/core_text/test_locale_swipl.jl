# ORIGINAL: a differential of locale_create/3, locale_destroy/1, locale_property/2, set_locale/1 and current_locale/1 (pl-locale.c) against swipl at the pin;
# test/core_text/test_tai_format_swipl.jl's harness
# test/core_text/test_locale_swipl.jl — the CT1 LOCALE predicates, through a PROGRAM: test_locale_swipl.pl holds the rows, each a predicate
# `tN(R)` with ONE solution (a list of every action's result, in order); the kernel consults the program and enumerates every solution of
# every tN/1, and its lines are compared with test_locale_swipl.out — swipl 10.1.20's own, printed by the driver below (`ok`, then one line per row:
# its name and its solution). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale. Every locale a row
# makes is made from the name "C" with decimal_point, thousands_sep and grouping given explicitly and is read back through locale_property/2
# (the machine's locale is never read, no format/2 ~D is used); a row that enumerates locales filters on its own aliases and sorts (the kernel's
# table is in creation order, swipl's is a hash table). UNTESTED when written (CT1 writer lane, edit-only): the .out is swipl's (two identical
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

const _LCS_PL = joinpath(@__DIR__, "test_locale_swipl.pl")
const _LCS_OUT = joinpath(@__DIR__, "test_locale_swipl.out")

# the rows' names, in the order of the program
_lcs_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_LCS_PL, String))])

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

# KNOWN DIFFERENCE, with swipl 10.1.20's own answer (evidence 2026-11-19; LC-C2 of tools/mutants/LOCALE.py waits on it, ATOM1 is the port item): swipl
# ACCEPTS the atom of length 3, [0'a, 0, 0'b]: `locale_create(L, "C", [decimal_point(A)])` stores `a` (the string is cut at the first NUL; locale_property
# gives decimal_point(a), atom_length 1), the same for thousands_sep. The kernel's exact answer here is the refusal below (the line `t12 notported`).
# (DIVERGES, settled, user 2026-10-10: src/pl-read.jl:2061-2064 `_atom_from_text`): swipl's atoms hold the
# character 0, the kernel's do not and it REFUSES one (`NotPortedError`: "an atom containing the character 0"), whether the
# reader makes it from program text (`'a\000\b'` loses the whole consult) or atom_codes/2 makes it at run time. t12 is the row
# of a decimal_point holding the character 0 (it was part of t10); its atom is built at run time, so only t12 meets the
# refusal: the kernel's line is `t12 notported`, swipl's answer is in the .out. t12 is the last row of the program, and
# a refused row ends one run (its ld is thrown away): `kernel_lines_all` continues after it on a fresh engine.
const _LCS_NUL_ROWS = ("t12",)

# `kernel_lines`, continued after every refused row on a fresh engine (the lines of the rows that follow)
function kernel_lines_all(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    out = kernel_lines(T, path, names)
    while length(out) - 1 < length(names) && endswith(out[end], " notported")
        out = vcat(out, kernel_lines(T, path, names[(length(out)):end])[2:end])
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


@testset "CT1 LOCALE: locale_create/3, locale_property/2, locale_destroy/1, set_locale/1, current_locale/1 == swipl's answers (the .out), through a program" begin
    names = _lcs_names()
    expected = String.(readlines(_LCS_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) >= 10
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test all(l -> !endswith(l, " "), expected)                               # every row has an answer
    @test !any(l -> endswith(l, " exception"), expected)                      # errors are caught by the rows, none escapes
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 4
    @test count(l -> occursin(_codes("domain_error"), l), expected) >= 2
    @test count(l -> occursin(_codes("type_error"), l), expected) >= 4
    @test count(l -> occursin(_codes("permission_error"), l), expected) >= 1
    @test count(l -> occursin(_codes("representation_error"), l), expected) >= 1
    @test occursin(
        _codes("digit_group_size"), expected[findfirst(startswith("t2 "), expected)]
    )
    @test occursin(_codes("digit_groups"), expected[findfirst(startswith("t1 "), expected)])
    @test occursin(_codes("repeat"), expected[findfirst(startswith("t0 "), expected)])
    @test occursin(_codes("lc7b"), expected[findfirst(startswith("t7 "), expected)])
    @test occursin(_codes("default"), expected[findfirst(startswith("t8 "), expected)])      # the initial current locale's alias
    @test !occursin(_codes("bad"), expected[findfirst(startswith("t11 "), expected)])         # setlocale/3 refreshes the default locale (or the host has no en_US.UTF-8)

    # t13: the destroyed locale leaves the table (one more locale while it lives, the same again after), t14: the enumeration answers the alias atom
    let t13 = expected[findfirst(startswith("t13 "), expected)],
        t14 = expected[findfirst(startswith("t14 "), expected)]

        @test occursin(
            "/1(c[91,124,93]/2(i1,c[91,124,93]/2(i0,c[91,124,93]/2(c[91,124,93]/2(a[108,99,49,51],nil),",
            t13
        )    # +1 while it lives, +0 after
        @test endswith(
            t13, "c[91,124,93]/2(a[102,97,108,115,101],c[91,124,93]/2(i0,nil))))))))"
        )    # its alias is gone: false; the table the same again: 0
        @test count("a[97,108,105,97,115]", t14) == 3 && !occursin("a[98,108,111,98]", t14)
    end

    # t15: the default locale's alias destroyed under another current locale: true, true, then no locale named default, the current one unchanged
    @test expected[findfirst(startswith("t15 "), expected)] ==
        "t15 c[116,49,53]/1(c[91,124,93]/2(a[100,101,102,97,117,108,116],c[91,124,93]/2(a[116,114,117,101],c[91,124,93]/2(a[116,114,117,101]," *
          "c[91,124,93]/2(a[102,97,108,115,101],c[91,124,93]/2(a[102,97,108,115,101],c[91,124,93]/2(a[59],nil)))))))"

    @test all(r -> r in names, _LCS_NUL_ROWS)                                 # the known-difference rows are rows
    @test occursin(_codes("true"), expected[findfirst(startswith("t12 "), expected)])  # swipl answers: the decimal point was made

    kl = kernel_lines_all(_TL, _LCS_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        row = i == 1 ? "ok" : names[i - 1]
        if row in _LCS_NUL_ROWS
            @test kl[i] == row * " notported"                                 # the refusal, by name
            @test_broken kl[i] == expected[i]                                 # swipl answers (the .out)
        else
            @test (i, kl[i]) == (i, expected[i])
        end
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LOCALE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_LCS_PL, names) == expected                         # the .out is swipl's, still
    end
end

# LC-U2 (update_locale refreshes ONLY for LC_NUMERIC and LC_ALL, pl-locale.c updateLocale): the default locale is made from the ENVIRONMENT's
# locale when the database is created; the process's LC_NUMERIC is the C library's own until a setlocale/3 on numeric or all. A refresh on any
# other category would copy the PROCESS numeric strings into the default locale: it shows only where the two differ. The row makes them
# differ on purpose (the process LC_NUMERIC is set by the C library call, behind the kernel's back) for each of three names, whatever LANG
# the host has, and asks that a ctype/time/collate/messages update leaves the default locale's strings as they were. A name the host has no
# locale for is skipped (setlocale answers NULL; the "C" name always exists); the row is vacuous on a host whose locales all share one set
# of numeric conventions (no locale-gen'd en_US or de_DE).
@testset "CT1 LOCALE: updateLocale of a non-numeric category leaves the default locale's strings alone" begin
    gd = LK.PL_global_data{_TL}()
    dl = gd.locale.default_locale::LK.PL_locale_rec{_TL}
    strs() = (dl.decimal_point, dl.thousands_sep, copy(dl.grouping))
    p0 = strs()
    saved = unsafe_string(
        ccall(:setlocale, Cstring, (Cint, Cstring), LK.LC_NUMERIC, C_NULL)
    )
    tried = 0
    try
        for name in ("C", "en_US.UTF-8", "de_DE.UTF-8")
            ccall(:setlocale, Cstring, (Cint, Cstring), LK.LC_NUMERIC, name) == C_NULL &&
                continue
            tried += 1
            for cat in (LK.LC_CTYPE, LK.LC_TIME, LK.LC_COLLATE, LK.LC_MESSAGES)
                LK.updateLocale(gd, cat, nothing)
                @test strs() == p0
            end
        end
    finally
        ccall(:setlocale, Cstring, (Cint, Cstring), LK.LC_NUMERIC, saved)
    end
    @test tried >= 1
end

# LC-B1 / LC-B3 (the handle of a locale, pl-locale.c unifyLocale + the blob's payload): upstream's blob payload IS the locale pointer, so a locale
# has ONE blob key for its whole life and `l->symbol` keeps that blob (`PL_get_atom(b, &l->symbol)`), so every later unifyLocale answers the
# kept atom without a lookup. The kernel's payload is the locale's number in `gd.locale.refs` (the pointer's stand-in): a locale gets its number
# once (`_locale_serial!`), and unifyLocale keeps the blob in `l.symbol`. What swipl answers cannot show either (two blobs for one locale would
# unify by atom identity as one, since lookupBlob finds the first by its key): t6's `B3 == B4` holds in the mutants. So the row is white-box: the
# registry size and the kept blob, read from the database after the program has asked for the same locale many ways.
const _LCS_WB = """
wb_mk :- locale_create(_, "C", [alias(lcwb), decimal_point(','), thousands_sep('.'), grouping([3])]).
wb_ask :- locale_property(lcwb, decimal_point(_)), locale_property(lcwb, grouping(_)), locale_property(lcwb, thousands_sep(_)).
wb_blob :- locale_property(B, alias(lcwb)), locale_property(B, decimal_point(_)).
wb_same :- locale_property(B1, alias(lcwb)), locale_property(B2, alias(lcwb)), B1 == B2, B1 \\== lcwb.
wb_destroy :- locale_destroy(lcwb).
"""
function _lcs_wb_once(gd, ld, name::String)::Bool
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

@testset "CT1 LOCALE: a locale keeps ONE number and its blob however often it is asked for" begin
    mktempdir() do d
        f = joinpath(d, "wb.pl")
        write(f, _LCS_WB)
        gd = LK.PL_global_data{_TL}()
        ld = LK.PL_local_data{_TL}(gd)
        st, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
        @test _lcs_wb_once(gd, ld, "wb_mk")
        n0 = length(gd.locale.refs)
        for _ in 1:3
            @test _lcs_wb_once(gd, ld, "wb_ask")            # asks the bound alias: the locale gets its number
        end
        @test length(gd.locale.refs) == n0 + 1               # ONE number for the locale, however often it was asked
        l = gd.locale.refs[end]
        @test l.serial == n0 + 1
        @test l.symbol === nothing                           # no blob has been made yet
        @test _lcs_wb_once(gd, ld, "wb_blob")                # the first blob (an unbound locale found by its alias)
        @test _lcs_wb_once(gd, ld, "wb_blob")
        @test _lcs_wb_once(gd, ld, "wb_same")
        @test length(gd.locale.refs) == n0 + 1               # still the one number
        @test l.serial == n0 + 1
        @test l.symbol !== nothing                           # the blob is kept (`l->symbol`)
        @test _lcs_wb_once(gd, ld, "wb_destroy")
    end
end

# LC-I2 (pl-locale.c initLocale: `GD->locale.default_locale = acquireLocale(def)`): the default locale is held by its alias, by the current locale and
# by default_locale itself. Row t15 (swipl: true, true, no locale named default) takes the alias's reference with locale_destroy/1 and the current
# locale's with set_locale/1, so only default_locale's own reference keeps it. Without that reference the locale is freed there (free_locale: the
# strings emptied, magic 0), and nothing in Prolog can name it any more (a blob of it holds a reference of its own): the free shows only in the
# database. So this runs the row's sequence and reads `gd.locale.default_locale`.
const _LCS_WB2 = """
wb2_seq :- locale_create(_, "C", [alias(lcwb2), decimal_point(';')]), set_locale(lcwb2), locale_destroy(default).
wb2_gone :- \\+ locale_property(default, alias(_)).
"""
@testset "CT1 LOCALE: the default locale outlives its alias and the current locale (default_locale holds a reference of its own)" begin
    mktempdir() do d
        f = joinpath(d, "wb2.pl")
        write(f, _LCS_WB2)
        gd = LK.PL_global_data{_TL}()
        ld = LK.PL_local_data{_TL}(gd)
        st, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
        dl = gd.locale.default_locale::LK.PL_locale_rec{_TL}
        @test dl.references == 3 && dl.alias !== nothing                 # the alias, the current locale and default_locale itself
        @test gd.locale.current === dl
        @test _lcs_wb_once(gd, ld, "wb2_seq")
        @test _lcs_wb_once(gd, ld, "wb2_gone")                           # no locale named default any more
        @test gd.locale.default_locale === dl && gd.locale.current !== dl
        @test dl.alias === nothing && dl.references == 1                 # only default_locale's own reference is left
        @test dl.magic == LK.LOCALE_MAGIC                                # not freed
        @test dl.decimal_point != ""                                     # its strings are kept
    end
end
