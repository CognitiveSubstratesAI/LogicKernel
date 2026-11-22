# ORIGINAL: JSON1's gate - the four foreign predicates of packages/json/json.c (json_read_number/3, json_skip_ws/3, json_write_string/2, json_write_indent/3),
# PL_put_term_from_chars (pl-read.c), PL_syntax_error with a stream (pl-error.c) and `$activate_static_extension/1` (pl-load.c, the static-extension form),
# called at the Julia level on memory streams. NO oracle: every expected value is read off json.c (packages-json 8be86c19, vendored at
# vendor/swipl-devel-extra/packages/json/json.c) by hand, line by line, and the row's comment names the C line it comes from. A row whose value rests on
# what swipl's reader or the kernel's stream layer does (not on json.c) carries a `# MEASURE ON THE LANE: <query>` comment: it is a real `@test` with the
# C-derived expectation, so a wrong guess FAILS on the lane, which is the point (nothing here has run: no Julia process was started to write this file).
# MUST-FAIL arms: each checking function is fed a deliberately wrong expectation and must report it, so a checker that cannot fail is seen.
# KERNEL-ONLY: the whole file (no swipl run), the tab 0 refusal (NotPortedError, step JSON1: json.c divides by zero there).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

const BS = "\\"
const Q = "\""

_ctx(::Type{T}) where {T} = LK.foreign_context{T}(LK.FRG_FIRST_CALL, UInt(0), nothing)

# a fresh database and local data with an open foreign frame (the term references live in it)
function _env(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.PL_open_foreign_frame(ld)
    return gd, ld
end

# the argument kinds of `_run`: an output memory stream (with the text already written), an input stream on a text, an unbound
# variable (`nothing`), an atom (a `Symbol`), an integer (`Int`), a float (`Float64`)
struct Out
    pre::String
end
Out() = Out("")
struct In
    text::String
end

# a memory output stream, UTF-8, unified with the term reference `t`; `(stream, buffer, size)`
function _outstream(ld, t::Int, pre::String)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    bufsize = Ref(0)
    w = LK.Sopenmem(bufp, bufsize, "w")
    w.encoding = LK.ENC_UTF8
    LK.PL_unify_stream(ld, t, w) || error("PL_unify_stream (output)")
    for ch in pre
        LK.Sputcode(Int(ch), w)
    end
    return (w, bufp, bufsize)
end
# what the memory stream holds, after a flush
function _written(w, bufp, bufsize)::String
    LK.Sflush(w)
    return bufp[] === nothing ? "" : String(bufp[][1:bufsize[]])
end
# an input stream reading `text` (Sopen_text, UTF-8: what term_to_atom/2 reads), unified with `t`
function _instream(ld, t::Int, text::String)
    bytes = Vector{UInt8}(codeunits(text))
    s = LK.Sopen_text(LK.PL_chars_t(bytes, length(text), LK.ENC_UTF8, false), "r")
    s === nothing && error("Sopen_text")
    LK.PL_unify_stream(ld, t, s) || error("PL_unify_stream (input)")
    return s
end

_put!(ld, t::Int, ::Nothing) = true
_put!(ld::LK.PL_local_data{T}, t::Int, x::Symbol) where {T} = LK.PL_put_atom(ld, t, lk_sym(T, x))
_put!(ld, t::Int, x::Integer) = LK.PL_put_int64(ld, t, Int(x))
_put!(ld, t::Int, x::Float64) = LK.PL_put_float(ld, t, x)

_exc(ld)::Bool = LK.PL_exception(ld, 0) != 0
_exc_term(ld) = lk_answer(ld, LK.PL_exception(ld, 0))
# the functor name of the formal of the pending error(Formal, _)
function _exc_formal(ld)::String
    f = child(_exc_term(ld), 2)
    return sym_text(kind(f) === SYM ? f : child(f, 1))
end

# call the predicate `f` (a `pl_..._va`) on fresh term references holding `specs`; every observable of the call
function _run(::Type{T}, f, specs...) where {T}
    gd, ld = _env(T)
    n = length(specs)
    t = LK.PL_new_term_refs(ld, n)
    out = nothing
    ins = Any[]
    for (i, sp) in enumerate(specs)
        r = t + i - 1
        if sp isa Out
            out = _outstream(ld, r, sp.pre)
        elseif sp isa In
            push!(ins, _instream(ld, r, sp.text))
        else
            _put!(ld, r, sp) || error("_put!")
        end
    end
    rc = f(ld, t, n, _ctx(T))
    exc = _exc(ld)
    return (
        rc = rc, out = out === nothing ? "" : _written(out...), exc = exc,
        formal = exc ? _exc_formal(ld) : "", ld = ld, t = t, ins = ins,
    )
end
# the value of argument `k` (1-based) after the call, as an integer or a float; `nothing` when it holds anything else
function _val(r, k::Int)
    a = lk_answer(r.ld, r.t + k - 1)
    return kind(a) === GND ? lk_value(a) : nothing
end

# ---------------------------------------------------------------------------------------------------------------------
# json_write_string/2 (json.c:282-336) and json_put_code (json.c:202-250)

# the output and the result of json_write_string(Out, Text): TRUE with `want` written and no exception
_ws_ok(::Type{T}, text, want::String) where {T} = begin
    r = _run(T, LK.pl_json_write_string2_va, Out(), text)
    r.rc == LK.FTRUE && !r.exc && r.out == want
end

# (text, the output): json.c's escape table (:204-211, :217-219), control characters as `\u%04x` (:220-223), `</` as `<\/` (:224-226),
# `<!` as `<` + backslash + `u0021` (:227-230, the handoff's earlier "a bare !" is wrong: Sfprintf(out, "u%04x", c) writes the code of the `!`), U+2028 and
# U+2029 as `\u2028`, `\u2029` (:233-240); everything else is written as it is, as UTF-8 (:241-243).
const _WS_ROWS = [
    ("abc", "$(Q)abc$(Q)"),
    ("", "$(Q)$(Q)"),
    ("a\"b\\c", "$(Q)a$(BS)$(Q)b$(BS)$(BS)c$(Q)"),                              # the two characters that are escaped by themselves
    ("\b\f\n\r\t", "$(Q)$(BS)b$(BS)f$(BS)n$(BS)r$(BS)t$(Q)"),                    # the five letter escapes
    ("\x01\x1f", "$(Q)$(BS)u0001$(BS)u001f$(Q)"),                                # control characters: lowercase hex, four digits
    ("\0", "$(Q)$(BS)u0000$(Q)"),                                                # NUL is a control character as well
    ("a/b", "$(Q)a/b$(Q)"),                                                      # a lone / is not escaped
    ("</a", "$(Q)<$(BS)/a$(Q)"),                                                 # </ becomes <\/
    ("<<//", "$(Q)<<$(BS)//$(Q)"),                                               # only the / that FOLLOWS a < : pc is the previous code
    ("<!--", "$(Q)<$(BS)u0021--$(Q)"),                                           # <! becomes < + backslash + u0021
    ("a!<", "$(Q)a!<$(Q)"),                                                      # ! before < is left alone
    ("<!</", "$(Q)<$(BS)u0021<$(BS)/$(Q)"),                                      # pc follows each written code, escaped or not
    ("\x7f", "$(Q)\x7f$(Q)"),                                                    # DEL is not below ' ': raw
    ("\u00e9\u20ac\U0001F600", "$(Q)\u00e9\u20ac\U0001F600$(Q)"),                # raw UTF-8 on a UTF-8 stream
    ("\u2028\u2029", "$(Q)$(BS)u2028$(BS)u2029$(Q)"),                            # JavaScript line terminators
    ("\u2027\u202a", "$(Q)\u2027\u202a$(Q)"),                                    # their neighbours are not
    ("\u0080", "$(Q)\u0080$(Q)"),                                                # the first code >= 128 is raw
]

@testset "json_write_string/2: the C-derived rows" begin
    for (text, want) in _WS_ROWS
        @test _ws_ok(_TL, Symbol(text), want)
    end
    # CVT_INTEGER (json.c:300, integer keys of dicts): the integer is written as its digits, quoted
    @test _ws_ok(_TL, 42, "$(Q)42$(Q)")
    @test _ws_ok(_TL, -7, "$(Q)-7$(Q)")
    # a text written after some output: the stream is used as it is (no newline, no reset)
    r = _run(_TL, LK.pl_json_write_string2_va, Out("[ "), :a)
    @test r.rc == LK.FTRUE && r.out == "[ $(Q)a$(Q)"
end

@testset "json_write_string/2: the refusals write nothing" begin
    r = _run(_TL, LK.pl_json_write_string2_va, Out(), nothing)       # unbound text: json.c:312-313 (CVT_EXCEPTION)
    @test r.rc == LK.FFALSE && r.exc && r.formal == "instantiation_error" && r.out == ""
    r = _run(_TL, LK.pl_json_write_string2_va, Out(), 1.5)           # a float is no text
    @test r.rc == LK.FFALSE && r.exc && r.out == ""
    r = _run(_TL, LK.pl_json_write_string2_va, :foo, :a)             # PL_get_stream fails (json.c:293)
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_write_string2_va, In("x"), :a)          # an input stream is no output stream (SIO_OUTPUT)
    @test r.rc == LK.FFALSE && r.exc
end

# json_put_code on its own: the previous code `pc`, the code `c`; (the result, what was written)
function _pc(pc::Integer, c::Integer)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    bufsize = Ref(0)
    w = LK.Sopenmem(bufp, bufsize, "w")
    w.encoding = LK.ENC_UTF8
    rc = LK.json_put_code(w, Int(pc), Int(c))
    return (rc, _written(w, bufp, bufsize))
end

@testset "json_put_code: the codes only a caller of the wide path reaches" begin
    # surrogates cannot be in a Julia String: json.c:233 (IS_UTF16_SURROGATE) writes the escape itself
    @test _pc(0, 0xD800) == (0, "$(BS)ud800")
    @test _pc(0, 0xDBFF) == (0, "$(BS)udbff")
    @test _pc(0, 0xDFFF) == (0, "$(BS)udfff")
    @test _pc(0, 0xD7FF) == (0, "\ud7ff")                            # just below the range: raw
    @test _pc(0, 0xE000) == (0, "\ue000")                            # just above: raw
    @test _pc(0, 0x2028) == (0, "$(BS)u2028")
    @test _pc(0, 0x2029) == (0, "$(BS)u2029")
    @test _pc(0, 0x1F600) == (0, "\U0001F600")
    @test _pc(Int('<'), Int('/')) == (0, "$(BS)/")
    @test _pc(Int('<'), Int('!')) == (0, "$(BS)u0021")
    @test _pc(Int('a'), Int('/')) == (0, "/")                        # pc is what counts, not the code
    @test _pc(Int('<'), 0x20ac) == (0, "\u20ac")                     # c >= 128 after a < is raw
    @test _pc(0, 0x7f) == (0, "\x7f")
    @test _pc(0, 0x1f) == (0, "$(BS)u001f")
    @test _pc(0, 0x20) == (0, " ")                                   # ' ' is the first code that is not a control character
end

# ---------------------------------------------------------------------------------------------------------------------
# json_write_indent/3 (json.c:339-368): `Indent` columns as `Indent / Tab` tabs and `Indent % Tab` spaces, after a newline unless the
# stream is at a line start (`out->position && out->position->linepos == 0`); C's `/` and `%` truncate

# `pre` is what the stream holds before the call (it decides the line position); the output is `want`
_wi_ok(::Type{T}, pre::String, i, t, want::String) where {T} = begin
    r = _run(T, LK.pl_json_write_indent3_va, Out(pre), i, t)
    r.rc == LK.FTRUE && !r.exc && r.out == want
end

@testset "json_write_indent/3: the C-derived rows" begin
    # (indent, tab, output after `x`): n = indent / tab tabs, then indent % tab spaces
    for (i, t, want) in [
            (17, 8, "x\n\t\t "), (16, 8, "x\n\t\t"), (8, 8, "x\n\t"), (7, 8, "x\n       "),
            (0, 8, "x\n"), (3, 1, "x\n\t\t\t"), (5, 2, "x\n\t\t "), (9, 4, "x\n\t\t "),
            (-3, 8, "x\n"),                                          # a negative count loops zero times (n = -3/8 = 0, -3 % 8 = -3)
            (-9, 4, "x\n"),                                          # -9/4 = -2 (truncating), -9 % 4 = -1: both loops run zero times
            (3, -1, "x\n"),                                          # 3 / -1 = -3, 3 % -1 = 0
        ]
        @test _wi_ok(_TL, "x", i, t, want)
    end
    # line start: no newline (json.c:351-352, `position && linepos == 0`)
    @test _wi_ok(_TL, "x\n", 8, 8, "x\n\t")
    # MEASURE ON THE LANE: a fresh memory stream (Sopenmem with SIO_RECORDPOS) has a position with linepos 0, so `json_write_indent(S, 8, 8)` writes only a tab
    @test _wi_ok(_TL, "", 8, 8, "\t")
    # the newline is written for ANY linepos > 0, however short the indent
    @test _wi_ok(_TL, "xyz", 1, 8, "xyz\n ")
end

@testset "json_write_indent/3: no integer, no stream, tab 0" begin
    r = _run(_TL, LK.pl_json_write_indent3_va, Out("x"), :abc, 8)    # PL_get_integer fails (json.c:343): false, no error
    @test r.rc == LK.FFALSE && !r.exc && r.out == "x"
    r = _run(_TL, LK.pl_json_write_indent3_va, Out("x"), 8, :abc)
    @test r.rc == LK.FFALSE && !r.exc && r.out == "x"
    r = _run(_TL, LK.pl_json_write_indent3_va, Out("x"), 2^40, 8)    # does not fit PL_get_integer's int
    @test r.rc == LK.FFALSE && !r.exc && r.out == "x"
    r = _run(_TL, LK.pl_json_write_indent3_va, Out("x"), 8, 2^40)
    @test r.rc == LK.FFALSE && !r.exc && r.out == "x"
    r = _run(_TL, LK.pl_json_write_indent3_va, :foo, 8, 8)           # PL_get_stream fails: the error is pending
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_write_indent3_va, In("x"), 8, 8)        # an input stream: SIO_OUTPUT refused
    @test r.rc == LK.FFALSE && r.exc
end

# tab 0: json.c computes `indent/tab` (SIGFPE in C): a named refusal, culprit json_write_indent, step JSON1
function _wi_refusal(::Type{T}, i, t) where {T}
    try
        _run(T, LK.pl_json_write_indent3_va, Out("x"), i, t)
    catch e
        e isa LK.NotPortedError || rethrow()
        return (sym_text(e.culprit), e.what, e.step)
    end
    return nothing
end

@testset "json_write_indent/3: tab 0 is refused by name (KERNEL-ONLY)" begin
    r = _wi_refusal(_TL, 8, 0)
    @test r !== nothing
    @test r[1] == "json_write_indent"
    @test r[3] == "JSON1"
    @test occursin("divides by zero", r[2])
    @test _wi_refusal(_TL, 0, 0) !== nothing                         # whatever the indent
    @test _wi_refusal(_TL, 8, 8) === nothing                         # and only tab 0
end

@testset "json_write_indent/3: MUST-FAIL (the checker reports a wrong expectation)" begin
    @test !_wi_ok(_TL, "x", 17, 8, "x\n\t\t")                        # a space missing
    @test !_wi_ok(_TL, "x", 8, 8, "x\t")                             # the newline missing
    @test !_wi_ok(_TL, "x\n", 8, 8, "x\n\n\t")                       # a newline at a line start
    @test !_wi_ok(_TL, "x", 3, 1, "x\n   ")                          # spaces where tabs are written
    @test !_wi_ok(_TL, "x", :abc, 8, "x")                            # a failing call is not a success
    @test _wi_refusal(_TL, 8, 8) !== (("json_write_indent", "x", "JSON1"))   # a refusal is not the absence of one
end

@testset "json_write_string/2: MUST-FAIL (the checker reports a wrong expectation)" begin
    @test !_ws_ok(_TL, :abc, "$(Q)abd$(Q)")                         # a wrong text
    @test !_ws_ok(_TL, :abc, "abc")                                 # no quotes
    @test !_ws_ok(_TL, Symbol("</a"), "$(Q)</a$(Q)")                # the escape missing from the expectation
    @test !_ws_ok(_TL, Symbol("\x01"), "$(Q)$(BS)u0001$(Q)$(Q)")   # one quote too many
    @test !_ws_ok(_TL, nothing, "$(Q)$(Q)")                          # an unbound text is not an empty string
    @test _pc(0, 0xD800) != (0, "$(BS)uD800")                       # the hex digits are lowercase
end

# ---------------------------------------------------------------------------------------------------------------------
# json_skip_ws/3 (json.c:166-193): `c0` is read with PL_get_char_ex(.., true) (the integer -1 and `end_of_file` are -1); only when `c0` is
# white space (' ', \t, \n, \r: is_ws, json.c:166-169) is the stream looked at; codes are read until the first that is not white space, which
# is `Next` (-1 at end of file) and is CONSUMED

# json_skip_ws(In(text), c0, Next): `Next` is `want` and the next code of the stream is `after`
_sk_ok(::Type{T}, text::String, c0, want::Integer, after::Integer) where {T} = begin
    r = _run(T, LK.pl_json_skip_ws3_va, In(text), c0, nothing)
    r.rc == LK.FTRUE && !r.exc && _val(r, 3) == want && LK.Sgetcode(r.ins[1]) == after
end

@testset "json_skip_ws/3: the C-derived rows" begin
    # (text, c0, Next, the code after Next)
    for (text, c0, want, after) in [
            ("  \t\n\r xy", 32, Int('x'), Int('y')),                 # all four white space characters, then x is consumed
            ("xy", 10, Int('x'), Int('y')),                          # c0 white space, the stream starts with other
            ("xy", 13, Int('x'), Int('y')),                          # \r is white space
            ("xy", 9, Int('x'), Int('y')),                           # \t is white space
            ("  ", 32, -1, -1),                                      # end of file inside the white space: -1
            ("", 9, -1, -1),
            ("   z", Int('a'), Int('a'), 32),                        # c0 is not white space: Next = c0 and the stream is untouched
            ("   z", -1, -1, 32),                                    # the integer -1 is end of file: untouched
            ("   z", :end_of_file, -1, 32),                          # so is the atom end_of_file
            ("  q", Symbol(" "), Int('q'), -1),                      # a one-character atom is its code: white space
            ("  z", 11, 11, 32),                                     # \v (11) is NOT white space
            ("\x0bq", 32, 11, Int('q')),                             # nor is it skipped from the stream
            ("", 0x20ac, 0x20ac, -1),                                # a wide c0 that is not white space
            ("\u00a0x", 32, 0xa0, Int('x')),                         # U+00A0 stops the skipping
        ]
        @test _sk_ok(_TL, text, c0, want, after)
    end
    # a right preset Next: the unification succeeds; a wrong one fails with no error (json.c:191 returns PL_unify_integer(next, c))
    r = _run(_TL, LK.pl_json_skip_ws3_va, In("  xy"), 32, Int('x'))
    @test r.rc == LK.FTRUE && !r.exc
    r = _run(_TL, LK.pl_json_skip_ws3_va, In("  xy"), 32, Int('z'))
    @test r.rc == LK.FFALSE && !r.exc
end

@testset "json_skip_ws/3: the stream is looked at only when c0 is white space" begin
    r = _run(_TL, LK.pl_json_skip_ws3_va, :foo, Int('a'), nothing)   # not white space: the stream argument is never read
    @test r.rc == LK.FTRUE && !r.exc && _val(r, 3) == Int('a')
    r = _run(_TL, LK.pl_json_skip_ws3_va, :foo, 32, nothing)         # white space: PL_get_stream fails, the error is pending
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_skip_ws3_va, Out(), 32, nothing)        # an output stream is no input stream (SIO_INPUT)
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_skip_ws3_va, In(" x"), Symbol("ab"), nothing)   # PL_get_char_ex fails: a two-character atom
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_skip_ws3_va, In(" x"), 0x110000, nothing)       # not a code point
    @test r.rc == LK.FFALSE && r.exc
end

@testset "json_skip_ws/3: MUST-FAIL (the checker reports a wrong expectation)" begin
    @test !_sk_ok(_TL, "  xy", 32, Int('y'), Int('y'))               # the wrong Next
    @test !_sk_ok(_TL, "  xy", 32, Int('x'), Int('x'))               # the wrong next code of the stream
    @test !_sk_ok(_TL, "   z", Int('a'), Int('a'), Int('z'))         # a stream that was skipped
    @test !_sk_ok(_TL, "  ", 32, 0, -1)                              # end of file is -1, not 0
    @test !_sk_ok(_TL, " x", Symbol("ab"), 0, -1)                    # a failing call is not a success
end

# ---------------------------------------------------------------------------------------------------------------------
# json_read_number/3 (json.c:78-157): the text starts with the byte `c0 & 0xff`, then the characters of `0-9 . - + e E` are read ((c >= '0' &&
# c <= '9'), '.', '-', '+', 'e', 'E': json.c:116-123), each consumed; the text is read as a number with PL_put_term_from_chars (the number branch
# of pl-read.c:7292 when it is all digits and signs, the reader otherwise) and must be a number that unifies with the third argument. The first
# character that is none of them is only PEEKED. Not a number: syntax_error(illegal_number) with the stream's position (json.c:140-143).

# (text, c0, the number, the next code of the stream), `preset` the third argument (nothing: unbound)
_rn(::Type{T}, text::String, c0, preset=nothing) where {T} = _run(T, LK.pl_json_read_number3_va, In(text), c0, preset)
_rn_ok(::Type{T}, text::String, c0, want, after::Integer) where {T} = begin
    r = _rn(T, text, c0)
    r.rc == LK.FTRUE && !r.exc && _val(r, 3) == want && LK.Speekcode(r.ins[1]) == after
end
# a refusal: false, an exception pending, whose formal is `formal`
_rn_error(::Type{T}, text::String, c0, formal::String) where {T} = begin
    r = _rn(T, text, c0)
    r.rc == LK.FFALSE && r.exc && r.formal == formal
end

@testset "json_read_number/3: the C-derived rows" begin
    for (text, c0, want, after) in [
            ("2,x", Int('1'), 12, Int(',')),                         # the digits join, the comma is peeked
            ("5 ", Int('-'), -5, 32),                                # a leading -
            ("", Int('5'), 5, -1),                                   # end of file ends the number
            ("0}", Int('3'), 30, Int('}')),
            (".25}", Int('0'), 0.25, Int('}')),                      # a float
            ("2.5e3,x", Int('1'), 12500.0, Int(',')),                # an exponent
            ("e5,", Int('1'), 100000.0, Int(',')),                   # the `e` joins the text (1e5 reads as a float)
        ]
        @test _rn_ok(_TL, text, c0, want, after)
    end
    # json.c:133: `put_byte(&t, c)` keeps the LOW byte of c0 as a char: 0x0631's is '1' (0x31), 0x0663's is 'c' (0x63)
    @test _rn_ok(_TL, "5", 0x0631, 15, -1)
    @test _rn_error(_TL, "5", 0x0663, "syntax_error")                # the text `c5` is no number
    # the third argument: a right preset unifies, a wrong one is an illegal number (the stream's error, json.c:140-143)
    r = _rn(_TL, "2,x", Int('1'), 12)
    @test r.rc == LK.FTRUE && !r.exc
    r = _rn(_TL, "2,x", Int('1'), 13)
    @test r.rc == LK.FFALSE && r.exc && r.formal == "syntax_error"
    r = _rn(_TL, ".25}", Int('0'), 0.25)
    @test r.rc == LK.FTRUE && !r.exc
    r = _rn(_TL, "2.5e3,x", Int('1'), 12500.0)
    @test r.rc == LK.FTRUE && !r.exc
    # the characters that join: `+` and `e` (json.c:119-122); `1+1` is read as a term, not a number
    @test _rn_error(_TL, "+1", Int('1'), "syntax_error")
    @test _rn_ok(_TL, "xyz", Int('7'), 7, Int('x'))                  # x is peeked, not read
end

@testset "json_read_number/3: the arguments" begin
    r = _rn(_TL, "2", Symbol("ab"))                                  # PL_get_char_ex fails: a two-character atom
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_read_number3_va, :foo, Int('1'), nothing)       # PL_get_stream fails
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_json_read_number3_va, Out(), Int('1'), nothing)      # an output stream is no input stream
    @test r.rc == LK.FFALSE && r.exc
    r = _rn(_TL, "2", Symbol("1"))                                   # a one-character atom is its code
    @test r.rc == LK.FTRUE && _val(r, 3) == 12
end

# MEASURE ON THE LANE (rows that rest on pl-read.c's reader and str_number, read from the C text only: each is a real @test with the C-derived
# expectation; a wrong guess fails on the lane and the comment names the swipl query to compare with)
@testset "json_read_number/3: MEASURE ON THE LANE (the reader's verdict on text that is not a plain number)" begin
    # MEASURE ON THE LANE: swipl -g "term_to_atom(T,'1.'),print(T),nl" -t halt  -> 1 (the first character is a digit, the last is not: the reader
    # branch reads `1.` as the integer 1 followed by the end `.`); the `}` is only peeked
    r = _rn(_TL, ".}", Int('1'))
    @test r.rc == LK.FTRUE && !r.exc && _val(r, 3) == 1 && LK.Speekcode(r.ins[1]) == Int('}')
    # MEASURE ON THE LANE: term_to_atom(T,'-') -> T = (-), an atom: PL_is_number fails, then the stream's syntax_error(illegal_number)
    @test _rn_error(_TL, "x", Int('-'), "syntax_error")
    # MEASURE ON THE LANE: term_to_atom(T,'1.5.3') -> a syntax error (the reader's: the number branch stops at `1.5`, e != len+1)
    @test _rn_error(_TL, ".5.3", Int('1'), "syntax_error")
    # MEASURE ON THE LANE: term_to_atom(T,'1e') -> a syntax error (operator expected), raised by the reader under CVT_EXCEPTION
    @test _rn_error(_TL, "e", Int('1'), "syntax_error")
    # MEASURE ON THE LANE: term_to_atom(T,'--1') -> a syntax error (operator expected): the text is no number and no term
    @test _rn_error(_TL, "-1", Int('-'), "syntax_error")
    # MEASURE ON THE LANE: term_to_atom(T,'1E5') -> T = 100000.0 (`E` joins the text, json.c:122; str_number accepts it)
    @test _rn_ok(_TL, "E5,", Int('1'), 100000.0, Int(','))
    # MEASURE ON THE LANE: the exact error term: error(syntax_error(illegal_number), stream(S, Line, LinePos, CharNo)), with Line 1, LinePos 1 and
    # CharNo 1 after the one code `2` was read (a Sopen_text stream records its position); `stream(S)` only without a position
    r = _rn(_TL, "2", Int('1'), 13)
    loc = child(_exc_term(r.ld), 3)
    @test sym_text(child(loc, 1)) == "stream"
    @test nchildren(loc) == 5
    @test [lk_value(child(loc, k)) for k in 3:5] == [1, 1, 1]
    @test sym_text(child(child(_exc_term(r.ld), 2), 2)) == "illegal_number"      # error(syntax_error(illegal_number), _)
end

@testset "json_read_number/3: MUST-FAIL (the checker reports a wrong expectation)" begin
    @test !_rn_ok(_TL, "2,x", Int('1'), 13, Int(','))                # the wrong number
    @test !_rn_ok(_TL, "2,x", Int('1'), 12, Int('x'))                # the wrong peeked code
    @test !_rn_ok(_TL, "2,x", Int('1'), 12, -1)
    @test !_rn_ok(_TL, "+1", Int('1'), 11, -1)                       # an error is not a number
    @test !_rn_error(_TL, "2", Int('1'), "syntax_error")             # a number is not an error
    @test !_rn_error(_TL, "5", 0x0663, "type_error")                 # the wrong formal
end

# ---------------------------------------------------------------------------------------------------------------------
# PL_put_term_from_chars (pl-read.c:7292): a number when the text is all one (first character a digit or `-`, last a digit, str_number reads
# all of it), else the text read as a term; a syntax error is RAISED under CVT_EXCEPTION, else it is put into the term reference

function _ptfc(::Type{T}, bytes::Vector{UInt8}, len::Int, flags::Integer) where {T}
    gd, ld = _env(T)
    t = LK.PL_new_term_refs(ld, 1)
    rc = LK.PL_put_term_from_chars(ld, t, UInt32(flags), bytes, len)
    return (rc = rc, exc = _exc(ld), ld = ld, t = t)
end
_ptfc(::Type{T}, s::String; len::Int=sizeof(s), flags::Integer=LK.CVT_EXCEPTION) where {T} =
    _ptfc(T, Vector{UInt8}(codeunits(s)), len, flags)
_ptfc_answer(r) = lk_answer(r.ld, r.t)

# the text reads as the number `want`: the call succeeds, raises nothing and the reference holds a number equal to `want`
_num_ok(::Type{T}, s::String, want; len::Int=sizeof(s)) where {T} = begin
    r = _ptfc(T, s; len = len)
    a = _ptfc_answer(r)
    r.rc && !r.exc && kind(a) === GND && lk_value(a) == want
end
# the text reads as an atom
_atom_ok(::Type{T}, bytes::Vector{UInt8}, flags::Integer, want::String) where {T} = begin
    r = _ptfc(T, bytes, length(bytes), flags)
    a = _ptfc_answer(r)
    r.rc && !r.exc && kind(a) === SYM && sym_text(a) == want
end

@testset "PL_put_term_from_chars: numbers (the first branch) and terms (the reader)" begin
    @test _num_ok(_TL, "12", 12)
    @test _num_ok(_TL, "-7", -7)
    @test _num_ok(_TL, "2.5", 2.5)
    @test _num_ok(_TL, "0.25", 0.25)
    @test _num_ok(_TL, "123456789012345678901234567890", parse(BigInt, "123456789012345678901234567890"))
    @test _num_ok(_TL, "12345", 123; len = 3)                        # only the first `len` bytes are read
    @test _num_ok(_TL, "12345", 12345; len = 5)
    @test _atom_ok(_TL, Vector{UInt8}(codeunits("abc")), LK.CVT_EXCEPTION, "abc")
    for (text, name) in [("a-1", "-"), ("1+2", "+")]                 # first char a digit but the number ends early / not a number at all
        r = _ptfc(_TL, text)
        a = _ptfc_answer(r)
        @test r.rc && !r.exc && kind(a) !== GND && kind(a) !== SYM
        @test sym_text(child(a, 1)) == name && nchildren(a) == 3
    end
    # an encoding: REP_UTF8 reads the bytes of \u00e9 as one character; without it a byte is a Latin-1 character
    @test _atom_ok(_TL, Vector{UInt8}(codeunits("\u00e9")), LK.CVT_EXCEPTION | LK.REP_UTF8, "\u00e9")
    @test _atom_ok(_TL, UInt8[0xe9], LK.CVT_EXCEPTION, "\u00e9")
end

@testset "PL_put_term_from_chars: a syntax error is raised under CVT_EXCEPTION, put into the term otherwise" begin
    r = _ptfc(_TL, "foo("; flags = LK.CVT_EXCEPTION)
    @test !r.rc && r.exc
    @test sym_text(child(_exc_term(r.ld), 1)) == "error"
    r = _ptfc(_TL, "foo("; flags = 0)
    @test !r.rc && !r.exc
    a = _ptfc_answer(r)
    @test kind(a) !== GND && kind(a) !== SYM && sym_text(child(a, 1)) == "error"      # t holds the error term
    @test sym_text(child(child(a, 2), 1)) == "syntax_error"
end

@testset "PL_put_term_from_chars: MUST-FAIL (the checker reports a wrong expectation)" begin
    @test !_num_ok(_TL, "12", 13)
    @test !_num_ok(_TL, "12345", 12345; len = 3)
    @test !_num_ok(_TL, "foo(", 1)
    @test !_num_ok(_TL, "abc", 1)                                    # an atom is no number
    @test !_atom_ok(_TL, UInt8[0xe9], LK.CVT_EXCEPTION | LK.REP_UTF8, "\u00e9")   # a lone 0xe9 is no UTF-8
end

# ---------------------------------------------------------------------------------------------------------------------
# `$activate_static_extension/1` (pl-load.c, the static form) and the tables that register the four predicates

@testset "\$activate_static_extension/1" begin
    @test [n for (n, _) in LK.static_extensions] == ["json"]
    gd, ld = _env(_TL)
    t = LK.PL_new_term_refs(ld, 1)
    _put!(ld, t, :json)
    @test LK.pl_activate_static_extension1_va(ld, t, 1, _ctx(_TL)) == LK.FTRUE
    @test LK.pl_activate_static_extension1_va(ld, t, 1, _ctx(_TL)) == LK.FTRUE      # twice: nothing is registered twice
    @test !_exc(ld)
    @test LK.activate_static_extension(ld, "json")
    @test !LK.activate_static_extension(ld, "nosuch")
    r = _run(_TL, LK.pl_activate_static_extension1_va, :nosuch)
    @test r.rc == LK.FFALSE && r.exc && r.formal == "existence_error"
    r = _run(_TL, LK.pl_activate_static_extension1_va, 7)             # a number is no extension name: CVT_EXCEPTION
    @test r.rc == LK.FFALSE && r.exc
    r = _run(_TL, LK.pl_activate_static_extension1_va, nothing)
    @test r.rc == LK.FFALSE && r.exc && r.formal == "instantiation_error"
end

@testset "the json tables and the procedures in system" begin
    tab = LK.PL_predicates_from_json
    @test [(e.predicate_name, e.arity) for e in tab] ==
        [("json_read_number", 3), ("json_skip_ws", 3), ("json_write_string", 2), ("json_write_indent", 3)]
    @test all(e -> e.flags == LK.PL_FA_VARARGS, tab)
    @test [e.function_ for e in tab] == Any[
        LK.pl_json_read_number3_va, LK.pl_json_skip_ws3_va, LK.pl_json_write_string2_va, LK.pl_json_write_indent3_va,
    ]
    ld_tab = LK.PL_predicates_from_load
    @test [(e.predicate_name, e.arity) for e in ld_tab] == [("\$activate_static_extension", 1)]
    @test ld_tab[1].flags == (LK.PL_FA_TRANSPARENT | LK.PL_FA_VARARGS)
    gd = LK.PL_global_data{_TL}()
    m = LK.MODULE_system(gd)
    for (name, ar) in [
            ("json_read_number", 3), ("json_skip_ws", 3), ("json_write_string", 2), ("json_write_indent", 3),
            ("\$activate_static_extension", 1),
        ]
        proc = LK.isCurrentProcedure(sym_key(lk_sym(_TL, Symbol(name))), ar, m)
        @test proc !== nothing && LK.isDefinedProcedure(gd, proc)
    end
end
