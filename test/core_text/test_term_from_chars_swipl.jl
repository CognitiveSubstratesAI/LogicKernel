# ORIGINAL: RD2b's gate, group 4 — the foreign-interface term readers `PL_put_term_from_chars`, `PL_chars_to_term`, `PL_wchars_to_term` (src/pl-read.jl, pl-read.c:7292-7390) against swipl 10.1.20.
# test/core_text/test_term_from_chars_swipl.jl — a WHITE-BOX test: no Prolog predicate calls these three functions, so the kernel side calls them directly
# (a fresh local data and foreign frame per row; the answer is read off `t` with `lk_answer`) and the expected value is swipl's own, PINNED:
# `read_term_from_atom(Text, T, [])` (the same reader, the same `Sopen_text`, no `M_RDSTRING_TERM`; `term_to_atom/2` sets that flag, so it answers
# `end_of_string` where these functions answer `end_of_file` for an empty text). A syntax error compares the FORMAL only (`syntax_error(X)`, child 2 of the
# error term the kernel leaves in `t`; swipl's `error(F, _)`).
#   * tf01-tf09, tf21, tf23-tf25, tf28: the number fast path (a text that starts with a digit or `-` and ends with a digit is converted by `str_number`; the answer
#     must be the reader's) and the texts that look like numbers and are not (tf10 `1 2`: digits at both ends, `str_number` stops after the `1`; swipl reads 12).
#   * tf11-tf14, tf26, tf27: syntax errors (put in `t`, `false`), the empty text, the text without an end dot, the first term only.
#   * tf15-tf17, tf22: the encoding (ISO Latin-1 / `REP_UTF8`); tf19, tf21: `len` shorter than the buffer; tf20, tf29: the text stops at its first 0 (`len` -1).
#   * tf18, tf29-tf31: `PL_wchars_to_term` (the wide text recoded as UTF-8: DIVERGES in src); tf32, tf33: `CVT_EXCEPTION` (the error is raised, `t` stays unbound);
#     tf34: `REP_MB` (refused by name, but a number needs no stream); tf35: `LD->read_source` is restored (set to line 77 before every row).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, LC_ALL=C; two identical runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel: written without running the kernel (edit-only step); the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TF = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
const _TFGD = LK.PL_global_data{_TF}()

_tf_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tf_enc(t::_TF, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) && return "stream"
        return is_nil(t) ? "nil" : "a" * _tf_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tf_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tf_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tf_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: `enc/1` of the driver of test_char_conversion_swipl.jl, then one row per text
const _TF_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- blob(T, stream), !, write(stream).
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
tf_run(Id, Codes) :-
    atom_codes(A, Codes),
    catch(( read_term_from_atom(A, T, []), format("~w ok ", [Id]), enc(T) ), error(F, _), ( format("~w raised ", [Id]), enc(F) )),
    nl.
"""

# (id, mode, data, len): the text of a row is `data` up to `len` (-1: up to its first 0); mode `:chars` PL_chars_to_term, `:l1`/`:u8`/`:mb`
# PL_put_term_from_chars with REP_ISO_LATIN_1 / REP_UTF8 / REP_MB, `:exc` ISO Latin-1 with CVT_EXCEPTION, `:wide` PL_wchars_to_term
const _TF_ROWS = Tuple{String, Symbol, Vector{UInt32}, Int}[
    ("tf01", :chars, UInt32[102, 111, 111, 40, 88, 44, 32, 89, 44, 32, 88, 41], -1),   # variables, shared
    ("tf02", :chars, UInt32[52, 50], -1),   # number fast path
    ("tf03", :chars, UInt32[45, 49, 55], -1),   # negative number
    ("tf04", :chars, UInt32[51, 46, 49, 52], -1),   # float
    ("tf05", :chars, UInt32[48, 48, 55], -1),   # leading zeros
    ("tf06", :chars, UInt32[49, 95, 48, 48, 48], -1),   # digit group
    ("tf07", :chars, UInt32[49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48], -1),   # big integer
    ("tf08", :chars, UInt32[45, 97], -1),   # minus then letter: not a number
    ("tf09", :chars, UInt32[49, 46], -1),   # end dot: reader
    ("tf10", :chars, UInt32[49, 32, 50], -1),   # digits at both ends but not a number (KILL: no end check)
    ("tf11", :chars, UInt32[49, 50, 97, 98, 99], -1),   # syntax error
    ("tf12", :chars, UInt32[102, 111, 111, 40], -1),   # syntax error
    ("tf13", :chars, UInt32[], -1),   # empty: end_of_file
    ("tf14", :chars, UInt32[88], -1),   # a variable
    ("tf15", :chars, UInt32[99, 97, 102, 233], -1),   # Latin-1 atom
    ("tf16", :l1, UInt32[39, 195, 169, 39], -1),   # UTF-8 bytes read as Latin-1: two characters
    ("tf17", :u8, UInt32[39, 195, 169, 39], -1),   # the same read as UTF-8: one character
    ("tf18", :wide, UInt32[102, 40, 955, 44, 32, 39, 955, 39, 41], -1),   # wide text
    ("tf19", :l1, UInt32[102, 111, 111, 40, 97, 41], 3),   # len shorter than the buffer
    ("tf20", :chars, UInt32[102, 111, 111, 40, 97, 41, 0, 98, 97, 114], -1),   # embedded 0: up to it
    ("tf21", :l1, UInt32[49, 50, 51, 52, 53, 54], 3),   # number fast path with len
    ("tf22", :u8, UInt32[102, 40, 206, 187, 41], -1),   # UTF-8 atom
    ("tf23", :chars, UInt32[49, 114, 51], -1),   # rational
    ("tf24", :chars, UInt32[48, 39, 49], -1),   # character code
    ("tf25", :chars, UInt32[45, 32, 49], -1),   # minus, blank, digit
    ("tf26", :chars, UInt32[102, 111, 111, 40, 97, 41], -1),   # no end dot: accepted
    ("tf27", :chars, UInt32[102, 111, 111, 40, 97, 41, 46, 32, 98, 97, 114], -1),   # the first term only
    ("tf28", :chars, UInt32[49, 46, 53, 101, 51], -1),   # float with exponent
    ("tf29", :wide, UInt32[52, 50, 0, 120], -1),   # wide: up to the first 0
    ("tf30", :wide, UInt32[102, 111, 111, 40], -1),   # wide: syntax error
    ("tf31", :wide, UInt32[97, 128512, 98], -1),   # wide: a code above the BMP (an emoji) in an unquoted text: a syntax error
    ("tf32", :exc, UInt32[102, 111, 111, 40], -1),   # CVT_EXCEPTION: raised, not put in t
    ("tf33", :exc, UInt32[102, 111, 111, 40, 97, 41], -1),   # CVT_EXCEPTION: no error
    ("tf34", :mb, UInt32[52, 50], -1),   # REP_MB: a number needs no stream
    ("tf35", :l1, UInt32[102, 40, 97, 44, 10, 10, 10, 98, 41], -1),   # read_source restored (row sets line 77 first)
    ("tf36", :l1, UInt32[39, 97, 92, 120, 52, 49, 92, 98, 39], -1),   # escape in quoted atom
]

"The code points swipl reads for a row: the bytes as Latin-1 (`:u8` decoded as UTF-8), the wide text as it is."
function _tf_text(mode::Symbol, data::Vector{UInt32}, len::Int)::Vector{Int}
    n = len
    if len == -1
        z = findfirst(==(0x00000000), data)
        n = z === nothing ? length(data) : z - 1
    end
    mode === :u8 && return Int.(collect(String(UInt8.(data[1:n]))))
    return Int.(data[1:n])
end

# swipl 10.1.20, LC_ALL=C: the lines of the driver (two identical runs)
const _TF_PINNED = [
    "tf01 ok c[102,111,111]/3(V0,V1,V0)",
    "tf02 ok i42",
    "tf03 ok i-17",
    "tf04 ok f3.14",
    "tf05 ok i7",
    "tf06 ok i1000",
    "tf07 ok i123456789012345678901234567890",
    "tf08 ok c[45]/1(a[97])",
    "tf09 ok i1",
    "tf10 ok i12",
    "tf11 raised c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])",
    "tf12 raised c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101])",
    "tf13 ok a[101,110,100,95,111,102,95,102,105,108,101]",
    "tf14 ok V0",
    "tf15 ok a[99,97,102,233]",
    "tf16 ok a[195,169]",
    "tf17 ok a[233]",
    "tf18 ok c[102]/2(a[955],a[955])",
    "tf19 ok a[102,111,111]",
    "tf20 ok c[102,111,111]/1(a[97])",
    "tf21 ok i123",
    "tf22 ok c[102]/1(a[955])",
    "tf23 ok q1r3",
    "tf24 ok i49",
    "tf25 ok c[45]/1(i1)",
    "tf26 ok c[102,111,111]/1(a[97])",
    "tf27 ok c[102,111,111]/1(a[97])",
    "tf28 ok f1500.0",
    "tf29 ok i42",
    "tf30 raised c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101])",
    "tf31 raised c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])",
    "tf32 raised c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101])",
    "tf33 ok c[102,111,111]/1(a[97])",
    "tf34 ok i42",
    "tf35 ok c[102]/2(a[97],a[98])",
    "tf36 ok a[97,65,98]"
]

"swipl's lines for the rows (live)."
function _tf_swipl_lines()::Vector{String}
    prog = _TF_DRIVER * join(["tf_row('$id', $(_tf_text(m, d, l))).\n" for (id, m, d, l) in _TF_ROWS])
    prog *= ":- initialization((forall(tf_row(I, C), tf_run(I, C)), halt)).\n"
    out = mktempdir() do dir
        f = joinpath(dir, "p.pl")
        write(f, prog)
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A source location the readers must leave alone: line 77."
_tf_loc() = LK.source_location{_TF}(nothing, LK.IOPOS(0, 0, 77, 0, 0))

"One row on the kernel: its line, and whether `LD->read_source` was left at line 77. A Julia exception is `jlerr <type>`."
function _tf_kernel(id::String, mode::Symbol, data::Vector{UInt32}, len::Int)::Tuple{String, Bool}
    ld = LK.PL_local_data{_TF}(_TFGD)
    ld.read_source = _tf_loc()
    try
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_ref(ld)
        bytes = UInt8.(data)
        rc = if mode === :chars
            LK.PL_chars_to_term(ld, bytes, t)
        elseif mode === :l1
            LK.PL_put_term_from_chars(ld, t, LK.REP_ISO_LATIN_1, len, bytes)
        elseif mode === :u8
            LK.PL_put_term_from_chars(ld, t, LK.REP_UTF8, len, bytes)
        elseif mode === :mb
            LK.PL_put_term_from_chars(ld, t, LK.REP_MB, len, bytes)
        elseif mode === :exc
            LK.PL_put_term_from_chars(ld, t, LK.REP_ISO_LATIN_1 | LK.CVT_EXCEPTION, len, bytes)
        else
            LK.PL_wchars_to_term(ld, data, t)
        end
        line = if mode === :exc && !rc
            ex = LK.PL_exception(ld, 0)
            ans = ex == 0 ? lk_answer(ld, t) : lk_answer(ld, ex)
            LK.PL_clear_exception(ld)
            "$id raised " * _tf_enc(child(ans, 2))
        elseif rc
            "$id ok " * _tf_enc(lk_answer(ld, t))
        else
            "$id raised " * _tf_enc(child(lk_answer(ld, t), 2))
        end
        LK.PL_close_foreign_frame(ld, fid)
        return (line, ld.read_source.position.lineno == 77)
    catch e
        return ("$id jlerr $(nameof(typeof(e)))", ld.read_source.position.lineno == 77)
    end
end

@testset "PL_put_term_from_chars, PL_chars_to_term, PL_wchars_to_term as swipl's reader (tf01-tf36)" begin
    @test length(_TF_PINNED) == length(_TF_ROWS)
    restored = Bool[]
    for ((id, m, d, l), p) in zip(_TF_ROWS, _TF_PINNED)
        k, ok = _tf_kernel(id, m, d, l)
        push!(restored, ok)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    @test all(restored)                                     # LD->read_source is saved and restored
    # not vacuous: numbers, a syntax error, an atom of the wide text, the Latin-1/UTF-8 difference
    @test count(l -> occursin(" ok i", l), _TF_PINNED) >= 8
    @test count(l -> occursin(" raised ", l), _TF_PINNED) >= 4
    @test any(l -> occursin("a[955]", l), _TF_PINNED)
    @test any(l -> occursin("tf16 ok a[195,169]", l), _TF_PINNED) && any(l -> occursin("tf17 ok a[233]", l), _TF_PINNED)
end

@testset "REP_MB is refused by name (a text that is no number needs the stream)" begin
    ld = LK.PL_local_data{_TF}(_TFGD)
    t = LK.PL_new_term_ref(ld)
    @test_throws LK.NotPortedError LK.PL_put_term_from_chars(ld, t, LK.REP_MB, -1, Vector{UInt8}(codeunits("foo")))
end

@testset "CVT_EXCEPTION leaves t unbound and the exception pending" begin
    ld = LK.PL_local_data{_TF}(_TFGD)
    t = LK.PL_new_term_ref(ld)
    rc = LK.PL_put_term_from_chars(
        ld, t, LK.REP_ISO_LATIN_1 | LK.CVT_EXCEPTION, -1, Vector{UInt8}(codeunits("foo("))
    )
    @test !rc
    @test LK.PL_exception(ld, 0) != 0
    @test kind(lk_answer(ld, t)) === VAR
    LK.PL_clear_exception(ld)
    @test LK.PL_exception(ld, 0) == 0
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "RD2b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        @test _tf_swipl_lines() == _TF_PINNED
    end
end
