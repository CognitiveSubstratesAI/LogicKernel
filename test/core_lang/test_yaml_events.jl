# ORIGINAL: YAML1 piece 2's gate - the event-term decoding of packages/yaml/yaml4pl.c (get_string_arg, get_value, get_bool_arg, emit_event's
# decoding half, and the error term of the emitter's failure branch), src/pl-yaml.jl (`yaml_decode_event` and friends). NO oracle and no
# libyaml: every expected value is read off yaml4pl.c (packages-yaml 0ce45ecf, lines 982-1230) by hand, and each row names the branch it
# exercises. The event terms are read from text with PL_put_term_from_chars. Nothing here has run (no Julia process was started to write
# this file): BLIND RISKS the lane settles are named where they bear (the text of a float, the default of double_quotes, the kernel's own
# error terms of PL_get_bool_ex / PL_get_text, which the rows pin only as far as the C text fixes them).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _YE_DB = _rdb(Tuple{_R, Union{Nothing, _R}}[])
const _YE_LD = _YE_DB.ld

# The term the text reads as, in a new term reference.
function _ye_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
    return t
end

# The pending error(Formal, _) as (Formal's name, [its arguments: an atomic's text, a compound's name/arity, else ?]); clears it.
function _ye_exc(ld)
    ex = LK.PL_exception(ld, 0)
    ex == 0 && return nothing
    f = LK.PL_new_term_ref(ld)
    a = LK.PL_new_term_ref(ld)
    r = nothing
    if LK._PL_get_arg(ld, 1, ex, f)
        na = LK.PL_get_name_arity(ld, f)
        if na !== nothing
            args = String[]
            for i in 1:na[2]
                LK._PL_get_arg(ld, i, f, a)
                txt = LK.PL_get_text(ld, a, LK.CVT_ATOMIC)
                if txt !== nothing
                    push!(args, LK.text_string(txt))
                else
                    nb = LK.PL_get_name_arity(ld, a)
                    push!(args, nb === nothing ? "?" : string(LK.sym_text(nb[1]), "/", nb[2]))
                end
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

# Decode `text` inside a foreign frame: (the event's fields or nothing, the error or nothing).
function _ye_decode(text::String)
    ld = _YE_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = _ye_term(ld, text)
    ev = LK.yaml_decode_event(ld, t)
    exc = _ye_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    fields = ev === nothing ? nothing :
        (ev.type, ev.anchor, ev.tag, ev.value, ev.implicit, ev.quoted_implicit, ev.style, ev.encoding)
    return (fields, exc)
end

const _YE_N = nothing
# (type, anchor, tag, value, implicit, quoted_implicit, style, encoding)
const _YE_STR_TAG = "tag:yaml.org,2002:str"

@testset "yaml_decode_event: the structure events (yaml4pl.c emit_event)" begin
    @test _ye_decode("stream_start") == ((LK.YAML_STREAM_START_EVENT, _YE_N, _YE_N, _YE_N, false, false, 0, LK.YAML_UTF8_ENCODING), _YE_N)
    @test _ye_decode("stream_end") == ((LK.YAML_STREAM_END_EVENT, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
    @test _ye_decode("mapping_end") == ((LK.YAML_MAPPING_END_EVENT, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
    @test _ye_decode("sequence_end") == ((LK.YAML_SEQUENCE_END_EVENT, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
    # document_start / document_end: arity 0 or 1, the argument a Boolean, `implicit` false when absent
    for (nm, ty) in (("document_start", LK.YAML_DOCUMENT_START_EVENT), ("document_end", LK.YAML_DOCUMENT_END_EVENT))
        @test _ye_decode(nm) == ((ty, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
        @test _ye_decode("$nm(true)") == ((ty, _YE_N, _YE_N, _YE_N, true, false, 0, 0), _YE_N)
        @test _ye_decode("$nm(false)") == ((ty, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
        # a non-Boolean: PL_get_bool_ex raises (the kernel's type_error(bool, maybe)), the decoding fails
        r = _ye_decode("$nm(maybe)")
        @test r[1] === nothing && r[2] == ("type_error", ["bool", "maybe"])
        # arity 2 is no event of this name
        @test _ye_decode("$nm(true, false)") == (_YE_N, ("domain_error", ["yaml_event", "$nm/2"]))
    end
    # mapping_start / sequence_start: arity 2 (Anchor, Tag), variables are NULL, atomics are text, block style, implicit 0
    for (nm, ty) in (("mapping_start", LK.YAML_MAPPING_START_EVENT), ("sequence_start", LK.YAML_SEQUENCE_START_EVENT))
        @test _ye_decode("$nm(_, _)") == ((ty, _YE_N, _YE_N, _YE_N, false, false, LK.YAML_BLOCK_MAPPING_STYLE, 0), _YE_N)
        @test _ye_decode("$nm(a1, 'tag:x')") == ((ty, "a1", "tag:x", _YE_N, false, false, 1, 0), _YE_N)
        @test _ye_decode("$nm(1, 2.5)") == ((ty, "1", "2.5", _YE_N, false, false, 1, 0), _YE_N)   # CVT_ATOMIC: numbers are text (2.5: the kernel's float text)
        @test _ye_decode("$nm(a1)") == (_YE_N, ("domain_error", ["yaml_event", "$nm/1"]))
        # a C string ends at its first NUL: get_string_arg reads the atom a<NUL>b as "a" (no strlen check there, unlike get_value)
        @test _ye_decode("$nm('a\\x0\\b', _)")[1][2] == "a"
        r = _ye_decode("$nm(f(x), _)")                 # not atomic: the text conversion raises
        @test r[1] === nothing && r[2] !== nothing
    end
    @test LK.YAML_BLOCK_MAPPING_STYLE == LK.YAML_BLOCK_SEQUENCE_STYLE == 1
end

@testset "yaml_decode_event: scalar/4 (yaml4pl.c get_value, the styles, the implicit flags)" begin
    # a plain atom: its text, no tag, implicit both ways
    @test _ye_decode("scalar(hello, _, _, plain)") == ((LK.YAML_SCALAR_EVENT, _YE_N, _YE_N, "hello", true, true, LK.YAML_PLAIN_SCALAR_STYLE, 0), _YE_N)
    # integers (CVT_INTEGER) and floats (CVT_FLOAT: the kernel's float text)
    @test _ye_decode("scalar(42, _, _, plain)")[1][4] == "42"
    @test _ye_decode("scalar(-7, _, _, plain)")[1][4] == "-7"
    @test _ye_decode("scalar(123456789012345678901234567890, _, _, plain)")[1][4] == "123456789012345678901234567890"
    @test _ye_decode("scalar(1.5, _, _, plain)")[1][4] == "1.5"
    # the special floats are fixed texts, whatever the kernel would print
    @test _ye_decode("scalar(1.0Inf, _, _, plain)")[1][4] == ".inf"
    @test _ye_decode("scalar(-1.0Inf, _, _, plain)")[1][4] == "-.inf"
    @test _ye_decode("scalar(1.5NaN, _, _, plain)")[1][4] == ".nan"
    # a STRING that would read as another type gets the str tag (when no tag was given), so the emitter quotes it; implicit false then
    for s in ("true", "12", "null", "1.5", ".inf", "0x1F", "False")
        @test _ye_decode("scalar(\"$s\", _, _, plain)") == ((LK.YAML_SCALAR_EVENT, _YE_N, _YE_STR_TAG, s, false, false, 1, 0), _YE_N)
    end
    # a string that does not: no tag. (BLIND: double_quotes is `string` in the kernel's default as in swipl's)
    @test _ye_decode("scalar(\"hello\", _, _, plain)")[1][3] === nothing
    @test _ye_decode("scalar(\"hello\", _, _, plain)")[1][5] === true
    # a given tag is kept: the string rule is `*tag == NULL`
    @test _ye_decode("scalar(\"12\", 'my:tag', _, plain)")[1][3] == "my:tag"
    # an ATOM that reads as another type gets NO tag (only strings are checked): pinned quirk of the C
    @test _ye_decode("scalar('12', _, _, plain)")[1][3] === nothing
    @test _ye_decode("scalar('true', _, _, plain)")[1][4] == "true"
    # tag, anchor and the five styles
    for (st, want) in (("plain", 1), ("single_quoted", 2), ("double_quoted", 3), ("literal", 4), ("folded", 5))
        r = _ye_decode("scalar(foo, 'my:tag', a1, $st)")
        @test r == ((LK.YAML_SCALAR_EVENT, "a1", "my:tag", "foo", false, false, want, 0), _YE_N)
    end
    @test (LK.YAML_PLAIN_SCALAR_STYLE, LK.YAML_SINGLE_QUOTED_SCALAR_STYLE, LK.YAML_DOUBLE_QUOTED_SCALAR_STYLE,
           LK.YAML_LITERAL_SCALAR_STYLE, LK.YAML_FOLDED_SCALAR_STYLE) == (1, 2, 3, 4, 5)
    # errors: an unknown style, a style that is no atom, a compound value, a value with a NUL
    @test _ye_decode("scalar(foo, _, _, fancy)") == (_YE_N, ("domain_error", ["yaml_scalar_style", "fancy"]))
    r = _ye_decode("scalar(foo, _, _, 1)")
    @test r[1] === nothing && r[2] !== nothing                  # PL_get_atom_ex: the kernel's type_error(atom, 1)
    @test _ye_decode("scalar(f(x), _, _, plain)") == (_YE_N, ("type_error", ["yaml_scalar", "f/1"]))
    @test _ye_decode("scalar(\"a\\x0\\b\", _, _, plain)")[2] !== nothing   # strlen(s) < len: domain_error(string_without_nul, _)
    # the ORDER of the reads: Tag (arg 2) first, so a bad Tag is reported before a bad Value
    r = _ye_decode("scalar(f(x), g(y), _, plain)")
    @test r[1] === nothing && r[2] !== nothing && r[2][2][end] == "g/1"
    # alias(Anchor)
    @test _ye_decode("alias(a1)") == ((LK.YAML_ALIAS_EVENT, "a1", _YE_N, _YE_N, false, false, 0, 0), _YE_N)
    @test _ye_decode("alias(_)") == ((LK.YAML_ALIAS_EVENT, _YE_N, _YE_N, _YE_N, false, false, 0, 0), _YE_N)
end

@testset "yaml_decode_event: unknown events (domain_error(yaml_event, Event))" begin
    @test _ye_decode("foo") == (_YE_N, ("domain_error", ["yaml_event", "foo"]))
    @test _ye_decode("scalar(a, b, c)") == (_YE_N, ("domain_error", ["yaml_event", "scalar/3"]))
    @test _ye_decode("stream_start(1)") == (_YE_N, ("domain_error", ["yaml_event", "stream_start/1"]))
    @test _ye_decode("stream_end(1)") == (_YE_N, ("domain_error", ["yaml_event", "stream_end/1"]))
    @test _ye_decode("alias") == (_YE_N, ("domain_error", ["yaml_event", "alias"]))           # alias needs arity 1
    @test _ye_decode("mapping_end(1)") == (_YE_N, ("domain_error", ["yaml_event", "mapping_end/1"]))
    @test _ye_decode("42") == (_YE_N, ("domain_error", ["yaml_event", "42"]))                # PL_get_name_arity fails on a number
end

@testset "yaml_emit_error: error(yaml_error(Code, Problem), _) (yaml4pl.c emit_event's failure branch)" begin
    ld = _YE_LD
    fid = LK.PL_open_foreign_frame(ld)
    @test LK.yaml_emit_error(ld, 7, "did not find expected <document start>") === false
    @test _ye_exc(ld) == ("yaml_error", ["7", "did not find expected <document start>"])
    @test LK.yaml_emit_error(ld, 0, "") === false
    @test _ye_exc(ld) == ("yaml_error", ["0", ""])
    LK.PL_discard_foreign_frame(ld, fid)
end
