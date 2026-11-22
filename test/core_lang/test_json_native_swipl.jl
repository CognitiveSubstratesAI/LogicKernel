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
_put!(ld, t::Int, x::Int) = LK.PL_put_int64(ld, t, x)
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
# `<!` as `<!` (:227-230, the handoff's earlier "a bare !" is wrong: Sfprintf(out, "u%04x", c) writes the code of the `!`), U+2028 and
# U+2029 as ` `, ` ` (:233-240); everything else is written as it is, as UTF-8 (:241-243).
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
    ("<!--", "$(Q)<$(BS)u0021--$(Q)"),                                           # <! becomes <!
    ("a!<", "$(Q)a!<$(Q)"),                                                      # ! before < is left alone
    ("<!</", "$(Q)<$(BS)u0021<$(BS)/$(Q)"),                                      # pc follows each written code, escaped or not
    ("\x7f", "$(Q)\x7f$(Q)"),                                                    # DEL is not below ' ': raw
    ("é€\U0001F600", "$(Q)é€\U0001F600$(Q)"),                # raw UTF-8 on a UTF-8 stream
    ("  ", "$(Q)$(BS)u2028$(BS)u2029$(Q)"),                            # JavaScript line terminators
    ("‧‪", "$(Q)‧‪$(Q)"),                                    # their neighbours are not
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
function _pc(pc::Int, c::Int)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    bufsize = Ref(0)
    w = LK.Sopenmem(bufp, bufsize, "w")
    w.encoding = LK.ENC_UTF8
    rc = LK.json_put_code(w, pc, c)
    return (rc, _written(w, bufp, bufsize))
end

@testset "json_put_code: the codes only a caller of the wide path reaches" begin
    # surrogates cannot be in a Julia String: json.c:233 (IS_UTF16_SURROGATE) writes the escape itself
    @test _pc(0, 0xD800) == (0, "$(BS)ud800")
    @test _pc(0, 0xDBFF) == (0, "$(BS)udbff")
    @test _pc(0, 0xDFFF) == (0, "$(BS)udfff")
    @test _pc(0, 0xD7FF) == (0, "퟿")                            # just below the range: raw
    @test _pc(0, 0xE000) == (0, "")                            # just above: raw
    @test _pc(0, 0x2028) == (0, "$(BS)u2028")
    @test _pc(0, 0x2029) == (0, "$(BS)u2029")
    @test _pc(0, 0x1F600) == (0, "\U0001F600")
    @test _pc(Int('<'), Int('/')) == (0, "$(BS)/")
    @test _pc(Int('<'), Int('!')) == (0, "$(BS)u0021")
    @test _pc(Int('a'), Int('/')) == (0, "/")                        # pc is what counts, not the code
    @test _pc(Int('<'), 0x20ac) == (0, "€")                     # c >= 128 after a < is raw
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
