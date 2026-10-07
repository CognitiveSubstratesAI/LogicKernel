# ORIGINAL: R1c's gate — the reader's scanner (src/pl-read.jl) against swipl 10.1.16; upstream's reader units (tests/core_text/test_read.pl, test_syntax.pl, test_op.pl) read whole terms: ported with the parser (R1d), in test/core_text/.
# test/core_lang/test_read_swipl.jl — R1c's gate (port_inventory row R1; user, 2026-10-07: SWI-7's
# default syntax, the tests covering `1r3`, `0'c`, the escapes, `{}`, `[]` vs `'[]'`):
#   * NUMBERS: `atom_number/2` through the query API on every syntax `str_number` reads or refuses
#     (radix, digit groups, `0'c`, rationals, floats with Inf and NaN, other scripts' digits) and
#     on generated texts; every outcome — the number to the bit, `fails`, the error — as swipl's;
#   * THE RAW TEXT: `raw_read` on a memory stream against swipl's `'$raw_read'/2` on
#     `open_string/2` (also a memory stream): comments become blanks, `0'c` and quoted items stay as
#     written, the full stop ends the term;
#   * RAW SYNTAX ERRORS on a string stream (as term_to_atom/2 reads), the whole error term —
#     `syntax_error(Id)` and `string(Text, CharNo)` — as swipl's term_to_atom/2 raises it;
#   * ESCAPES in quoted atoms and strings: the text read, or the error, as swipl's;
#   * TOKENS: `[]` (the reserved name) and `'[]'` (a quoted text atom), `{}`, a string, a variable,
#     `_`, `0'c`, `1r3`, `-1` as a number but `- 1` an operator, the full stop.
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RD = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rds(x) = lk_sym(_RD, Symbol(x))
const _RD_GD = LK.PL_global_data{_RD}()
const _RD_LD = LK.PL_local_data{_RD}()

"A number term as the differential compares it: `i…`, `q…r…`, a float's bits `F…`, a NaN's sign and payload."
function _rd_num(t::_RD)::String
    n = LK.number()
    LK.get_number(t, n)
    n.type === LK.V_INTEGER && return "i$(n.i)"
    n.type === LK.V_MPZ && return "i$(n.mpz)"
    n.type === LK.V_MPQ && return "q$(numerator(n.mpq))r$(denominator(n.mpq))"
    isnan(n.f) && return "nan:$(signbit(n.f) ? -1 : 1):$(LK.NaN_value(n.f))"
    return "F" * string(reinterpret(UInt64, n.f); base=16)
end

"`atom_number(Text, N)` through the query API: the number (`_rd_num`), `fails`, or `err <formal>`."
function _rd_atom_number(text::String)::String
    gd, ld = _RD_GD, _RD_LD
    proc = LK.isCurrentProcedure(sym_key(_rds(:atom_number)), 2, LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    ld.slots[a + 1] = _rds(text)
    ld.slots[a + 2] = mk_var(_RD, LK.fresh_var_keys!(1))
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        _rd_num(LK.resolve_term(ld, ld.slots[a + 2]))
    elseif rc == LK.PL_S_EXCEPTION
        f = child(LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]), 2)   # error(F, _)
        "err " * string(lk_name(kind(f) === SYM ? f : child(f, 1)))
    else
        "fails"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

# A stream on `text`: a memory stream (open_string/2's kind), or a string stream (term_to_atom/2's).
function _rd_stream(text::String, kind::Symbol)
    bytes = Vector{UInt8}(codeunits(text))
    if kind === :memory
        return LK.Sopenmem(
            Ref{Union{Nothing, Vector{UInt8}}}(bytes), Ref(length(bytes)), "r"
        )
    end
    s = LK.Sopen_string(bytes, length(bytes), "r")
    s.encoding = LK.ENC_UTF8                               # Sopen_text: the text's encoding
    return s
end

"The raw text of the first term of `text`, stripped as `'\$raw_read'/2` strips it, or `err <the error>`."
function _rd_raw(text::String, kind::Symbol)::String
    gd, ld = _RD_GD, _RD_LD
    fid = LK.PL_open_foreign_frame(ld)
    s = _rd_stream(text, kind)
    rd = LK.init_read_data(gd, ld, s)
    ok, e = LK.raw_read(rd)
    out = if ok
        b = rd._rb.base
        # pl_raw_read2: strip the full stop and the blanks around the text
        top = LK.backSkipBlanks(b, 1, e - 1)
        t2, chr = LK.backSkipUTF8(b, 1, top)
        chr == Int('.') && (top = LK.backSkipBlanks(b, 1, t2))
        if top < e && top - 2 >= 1 && b[top - 1] == UInt8('\'') && b[top - 2] == UInt8('0')
            top += 1                                        # watch for "0' ."
        end
        st = LK.skipSpaces(b, 1)
        String(b[st:(top - 1)])
    else
        "err " * _rd_write(LK.resolve_term(ld, ld.slots[rd.exception + 1]))
    end
    LK.Sclose(s)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"A term as swipl's `print/1` with `quoted(true)` writes these error terms (atoms quoted as needed)."
function _rd_write(t::_RD)::String
    k = kind(t)
    if k === SYM
        n = String(lk_name(t))
        return if all(c -> islowercase(c) || c == '_' || isdigit(c), n) && !isempty(n) &&
            islowercase(n[1])
            n
        else
            lk_atom_text(t)
        end
    elseif k === GND
        v = lk_value(t)
        v isa String && return repr(v)
        return string(v)
    end
    return _rd_write(child(t, 1)) * "(" *
           join((_rd_write(child(t, i)) for i in 2:nchildren(t)), ",") * ")"
end

"The first token of `text` (a string stream): `TYPE(value)`, or `err <the error>`."
function _rd_tokens(text::String)::Vector{String}
    gd, ld = _RD_GD, _RD_LD
    fid = LK.PL_open_foreign_frame(ld)
    s = _rd_stream(text, :string)
    rd = LK.init_read_data(gd, ld, s)
    ok, e = LK.raw_read(rd)
    toks = String[]
    if !ok
        push!(toks, "err " * _rd_write(LK.resolve_term(ld, ld.slots[rd.exception + 1])))
    else
        rd.here = 1
        rd.end_ = e
        while length(toks) < 64
            tk = LK.get_token(false, rd)
            if tk === nothing
                push!(
                    toks,
                    "err " * _rd_write(LK.resolve_term(ld, ld.slots[rd.exception + 1]))
                )
                break
            end
            ty = string(tk.type)[4:end]
            v = if tk.type in (LK.TK_NAME, LK.TK_FUNCTOR, LK.TK_QNAME, LK.TK_DICT)
                is_nil(tk.atom) ? "[]" : lk_atom_text(tk.atom)
            elseif tk.type == LK.TK_NUMBER
                _rd_num(LK.put_number(_RD, tk.number))
            elseif tk.type == LK.TK_PUNCTUATION
                string(Char(tk.character))
            elseif tk.type == LK.TK_STRING
                _rd_write(tk.term_value)
            elseif tk.type == LK.TK_VARIABLE
                String(LK.var_from_index(tk.variable, rd).name)
            else
                ""
            end
            push!(toks, "$ty($v)")
            tk.type == LK.TK_FULLSTOP && break
        end
    end
    LK.Sclose(s)
    LK.PL_close_foreign_frame(ld, fid)
    return toks
end

"The first token of `text` as the escapes test compares it: `a[codes]` for a quoted atom, `s[codes]` for a string, or `err <formal>`."
function _rd_first_text(text::String)::String
    gd, ld = _RD_GD, _RD_LD
    fid = LK.PL_open_foreign_frame(ld)
    s = _rd_stream(text, :string)
    rd = LK.init_read_data(gd, ld, s)
    ok, e = LK.raw_read(rd)
    tk = nothing
    if ok
        rd.here = 1
        rd.end_ = e
        tk = LK.get_token(false, rd)
    end
    out = if tk === nothing
        "err " * _rd_write(child(LK.resolve_term(ld, ld.slots[rd.exception + 1]), 2))
    elseif tk.type == LK.TK_QNAME || tk.type == LK.TK_NAME
        "a[" * join(Int.(collect(String(lk_name(tk.atom)))), ",") * "]"
    elseif tk.type == LK.TK_STRING
        "s[" * join(Int.(collect(lk_value(tk.term_value))), ",") * "]"
    else
        string(tk.type)
    end
    LK.Sclose(s)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

@testset "const_nan is what str_number reads for 1.5NaN (nan15)" begin
    b = Vector{UInt8}(codeunits("1.5NaN"))
    push!(b, 0x00)
    n = LK.number()
    rc, _ = LK.str_number(_RD_LD, b, 1, n, UInt32(0))
    @test rc == LK.NUM_OK && reinterpret(UInt64, n.f) == reinterpret(UInt64, LK.const_nan)
    # a stored NaN is the canonical one, whatever its sign and payload (put_double)
    m = LK.number()
    m.type = LK.V_FLOAT
    m.f = reinterpret(Float64, 0xfff8000000000001)
    @test reinterpret(UInt64, lk_value(LK.put_number(_RD, m))) ==
        reinterpret(UInt64, LK.const_nan)
end

@testset "tokens: [] and '[]', {}, strings, variables, numbers, operators" begin
    @test _rd_tokens("foo([], '[]', {}, \"s\", `b`, X, _, 0'c, 1r3, -1, a- 1).") == [
        "FUNCTOR(foo)", "PUNCTUATION(()", "NAME([])", "PUNCTUATION(,)", "QNAME('[]')",
        "PUNCTUATION(,)", "NAME('{}')", "PUNCTUATION(,)", "STRING(\"s\")", "PUNCTUATION(,)",
        "STRING('[|]'(98,[]))", "PUNCTUATION(,)", "VARIABLE(X)", "PUNCTUATION(,)", "VOID()",
        "PUNCTUATION(,)", "NUMBER(i99)", "PUNCTUATION(,)", "NUMBER(q1r3)", "PUNCTUATION(,)",
        "NUMBER(i-1)", "PUNCTUATION(,)", "NAME(a)", "NAME('-')", "NUMBER(i1)",
        "PUNCTUATION())",
        "FULLSTOP()"]
    # `[ ]` and `{ }` with layout inside are the same names; `[` alone is punctuation
    @test _rd_tokens("[ ] { } [a].")[1:4] ==
        ["NAME([])", "NAME('{}')", "PUNCTUATION([)", "NAME(a)"]
    # a string stream ends its text with " . ", so a term needs no full stop (term_to_atom/2: `x`)
    @test _rd_raw("x", :string) == "x"
    # a dict tag is its own token (the parser refuses dicts, R1d)
    @test _rd_tokens("point{x: 1}.")[1] == "DICT(point)"
    # a quoted functor, a symbol atom, a solo character
    @test _rd_tokens("'hello world'(x) =.. ! ;.")[1:6] ==
        ["FUNCTOR('hello world')", "PUNCTUATION(()", "NAME(x)", "PUNCTUATION())",
        "NAME('=..')",
        "NAME('!')"]
    # Unicode: an uppercase letter starts a variable, a lowercase one an atom
    @test _rd_tokens("Ébc ébc.")[1:2] == ["VARIABLE(Ébc)", "NAME('ébc')"]
    # an atom holding the character 0: swipl reads `'a\0\b'` as [97,0,98]; a Symbol cannot hold
    # it, so the kernel refuses it explicitly (DIVERGES, src/pl-read.jl `_atom_from_text`) — this
    # pin fails when the term interface can represent it
    @test_throws LK.NotPortedError _rd_tokens("'a\\0\\b'.")
end

const _RD_SWIPL = Sys.which("swipl")
const _RD_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

const _RD_DRIVER = raw"""
num(X) :- integer(X), !, write(i), write(X).
num(X) :- rational(X, N, D), !, format("q~wr~w", [N, D]).
num(X) :- X =\= X, !, S is copysign(1.0, X), ( S < 0 -> Sg = -1 ; Sg = 1 ),
    format(atom(A), "~w", [X]), sub_atom(A, B, _, 0, 'NaN'), sub_atom(A, 0, B, _, P),
    format("nan:~w:~w", [Sg, P]).
num(X) :- float(X), !, write(f), write(X).
an(Cs) :- atom_codes(A, Cs),
    catch((atom_number(A, N) -> num(N) ; write(fails)), error(F, _), (functor(F, Fn, _), write('err '), write(Fn))),
    nl.
raw(Cs) :- string_codes(S, Cs), open_string(S, In),
    catch(('$raw_read'(In, A), atom_codes(A, Out), atom_codes(R, Out), write(R)), error(F, _), (write('err '), writeq(F))),
    close(In), nl.
rawerr(Cs) :- atom_codes(A, Cs),
    catch((term_to_atom(_, A), write(ok)), E, (write('err '), write_term(E, [quoted(true), max_depth(0)]))),
    nl.
txt(Cs) :- atom_codes(A, Cs),
    catch((term_to_atom(T, A), ( atom(T) -> atom_codes(T, Out), format("a~w", [Out]) ; string(T) -> string_codes(T, Out), format("s~w", [Out]) ; write(other) )), error(F, _), (write('err '), writeq(F))),
    nl.
"""

# The number texts: every syntax str_number reads, the near misses it refuses, and generated ones.
const _RD_NUMBERS = [
    "0", "1", "-1", "+1", "- 1", "+ 1", "007", "1_000", "1_000_000", "1 000", "1_ 000",
    "1__0",
    "1_", "_1", "9223372036854775807", "9223372036854775808", "-9223372036854775808",
    "-9223372036854775809", "123456789012345678901234567890",
    "1_000_000_000_000_000_000_000",
    "0x1F", "0xff", "0XFF", "0x", "0x_1", "0x1_F", "0o17", "0o8", "0b101", "0b2", "0b1_0",
    "16'FF", "16'ff", "2'1010", "36'ZZ", "37'1", "1'1", "0'1", "16'", "16'G", "-16'FF",
    "16'FF'", "8'777", "10'99", "0'a", "0'\\n", "0''", "0'''", "0' ", "0'é", "0'\U0001D11E",
    "-0'a", "0'\\\\", "0'\\x41\\", "1r3", "-1r3", "2r4", "1r0", "0r5", "1r", "r3", "1R3",
    "1/3",
    "1_0r3", "1r3_0", "123456789012345678901234567890r7", "1.0", "-1.0", "1.5e10", "1.5E10",
    "1.5e+10", "1.5e-10", "1e10", "1.0e400", "1.0e-400", "1.0e-320", "4.9e-324",
    "1.7976931348623157e308", "1.7976931348623159e308", "0.1", ".5", "1.", "1.e5", "1.0e",
    "1.0e+", "1.0Inf", "-1.0Inf", "1.5NaN", "1.0NaN", "-1.5NaN", "2.0Inf", "1.0Infinity",
    "1.0inf", "1.5NaNx", "1_000.5", "1.0_1", "٣", "٣٤", "١٫٥", "०१२", "１２", "", " 1",
    "1 ",
    "a", "1a", "--1", "0x1G", "1e", "e1", "1.0.0", "-0.0", "0.0", "1.0e-308",
    "2.2250738585072014e-308"
]

"Generated number texts: digits, groups, signs, radix, rationals and exponents, mixed."
function _rd_gen_numbers(rng, n)
    pieces = ["0", "1", "9", "12", "007", "_", " ", "_ ", ".", "e", "E", "+", "-", "r", "'",
        "0x",
        "0o", "0b", "f", "F", "Inf", "NaN", "٣", "0'", "\\", "x", "ab", "36", "2",
        "9999999999"]
    return [join(rand(rng, pieces, rand(rng, 1:5))) for _ in 1:n]
end

const _RD_RAW = [
    "foo(X, Y).", "  a /* c */ + b . ", "a % c\n+ b.", "0'a.", "0''.", "0'''.", "'it''s'.",
    "\"x\\ny\".", "a.b.", "- 1.", "a :- b.%x", "[a|b]. c.", "x /* a\n b */ y.", "0' .",
    "'a\\\nb'.", "`abc`.", "f(/* nested /* two */ x */ ).", "a\t\tb.", "é.", "'\\x41\\'.",
    "a.\u00a0b."                                  # a full stop before a non-ASCII blank (isBlankW)
]

const _RD_RAWERR = [
    "'abc", "\"abc", "`abc", "0'", "a /* x", "/* x", "f(/* nested /* not */ x)."
]

const _RD_ESCAPES = [
    "'a\\nb'", "'\\x41\\'", "'\\101\\'", "'\\u00e9'", "'\\U0001D11E'", "'a\\c   b'",
    "'\\e'",
    "'\\s'", "'\\z'", "'\\\\'", "'\\''", "'it''s'", "\"\\t\"", "'\\x41'", "'\\u00'",
    "'\\uD800'",
    "'\\1234567\\'", "'\\a\\b\\f\\v\\'", "\"\\0\\\"", "'\\\n'", "'a\\\n   b'"
]

if _RD_SWIPL !== nothing
    @testset "atom_number/2 == swipl: every number syntax, and generated texts" begin
        texts = vcat(_RD_NUMBERS, _rd_gen_numbers(Xoshiro(20261007), 400))
        ours = [_rd_atom_number(t) for t in texts]
        prog = IOBuffer()
        print(prog, _RD_DRIVER, "run :- ")
        for t in texts
            print(prog, "an([", join(Int.(collect(t)), ","), "]), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "n.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        fbits(m) = "F" * string(reinterpret(UInt64, parse(Float64, m[2:end])); base=16)
        theirs = String[]
        for l in split(chomp(text), '\n')
            l = String(l)
            l = if l == "f1.0Inf"
                "F" * string(reinterpret(UInt64, Inf); base=16)
            elseif l == "f-1.0Inf"
                "F" * string(reinterpret(UInt64, -Inf); base=16)
            elseif occursin(r"^f-?[0-9]", l)
                fbits(l)
            else
                l
            end
            if startswith(l, "nan:")                      # nan:Sign:Payload text → as ours
                _, sg, p = split(l, ':')
                l = "nan:$sg:$(parse(Float64, p))"
            end
            push!(theirs, l)
        end
        @test length(theirs) == length(ours)
        bad = [
            (texts[k], ours[k], theirs[k]) for k in 1:min(length(ours), length(theirs))
            if ours[k] != theirs[k]
        ]
        for (t, o, s) in bad[1:min(end, 8)]
            println(
                stderr,
                "  DIVERGES: atom_number(",
                repr(t),
                ")\n    kernel ",
                o,
                "\n    swipl  ",
                s
            )
        end
        @test isempty(bad)
        @test count(startswith("i"), ours) > 0 && count(startswith("q"), ours) > 0 &&
            count(startswith("F"), ours) > 0 && count(startswith("nan"), ours) > 0 &&
            count(==("fails"), ours) > 0
    end

    @testset "raw_read == swipl's \$raw_read/2 on a memory stream" begin
        ours = [_rd_raw(t, :memory) for t in _RD_RAW]
        prog = IOBuffer()
        print(prog, _RD_DRIVER, "run :- ")
        for t in _RD_RAW
            print(prog, "raw([", join(Int.(collect(t)), ","), "]), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "r.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        # each answer is one line, but a raw text may hold newlines: split by the texts' own count
        theirs = split(chomp(text), '\n'; keepempty=true)
        joined = join(ours, "\n")
        @test joined == chomp(text)
        joined == chomp(text) ||
            println(stderr, "  kernel:\n", joined, "\n  swipl:\n", chomp(text))
    end

    @testset "raw syntax errors on a string stream == swipl's term_to_atom/2" begin
        ours = [_rd_raw(t, :string) for t in _RD_RAWERR]
        prog = IOBuffer()
        print(prog, _RD_DRIVER, "run :- ")
        for t in _RD_RAWERR
            print(prog, "rawerr([", join(Int.(collect(t)), ","), "]), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "e.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        theirs = split(chomp(text), '\n')
        @test length(theirs) == length(ours)
        for (t, o, s) in zip(_RD_RAWERR, ours, theirs)
            if t == "/* x"
                # DIVERGES (src/pl-read.jl `clearBuffer`): swipl's text is a stale buffer byte
                @test startswith(
                    s, "err error(syntax_error(end_of_file_in_block_comment),string("
                )
                @test o ==
                    "err error(syntax_error(end_of_file_in_block_comment),string(\"\",0))"
            else
                @test o == s
                o == s || println(
                    stderr,
                    "  DIVERGES: ",
                    repr(t),
                    "\n    kernel ",
                    o,
                    "\n    swipl  ",
                    s
                )
            end
        end
    end

    @testset "escapes in quoted text == swipl" begin
        ours = [_rd_first_text(t * ".") for t in _RD_ESCAPES]
        prog = IOBuffer()
        print(prog, _RD_DRIVER, "run :- ")
        for t in _RD_ESCAPES
            print(prog, "txt([", join(Int.(collect(t)), ","), "]), ")
        end
        println(prog, "true.\n:- initialization((run, halt)).")
        text = mktempdir() do d
            f = joinpath(d, "x.pl")
            write(f, String(take!(prog)))
            # swipl warns of `\\<newline><layout>` on stderr (the kernel does not print it: its DIVERGES)
            read(pipeline(`swipl -q $f`; stderr=devnull), String)
        end
        theirs = String.(split(chomp(text), '\n'))
        @test length(theirs) == length(ours)
        for (t, o, sw) in zip(_RD_ESCAPES, ours, theirs)
            @test o == sw
            o == sw || println(
                stderr, "  DIVERGES: ", repr(t), "\n    kernel ", o, "\n    swipl  ", sw
            )
        end
    end
elseif _RD_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the reader differential would be skipped"
    )
else
    @info "READER DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "reader differential skipped only where it is not required" begin
        @test !_RD_SWIPL_REQUIRED
    end
end
