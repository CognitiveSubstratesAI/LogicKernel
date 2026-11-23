# CLASS: code
# COPYRIGHT: Copyright (c)  2018-2023, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: packages/yaml C port (Phase 1), the carrier-independent part: a pure-function piece of yaml4pl.c
#
# YAML1 piece 1 (packages/yaml/yaml4pl.c, packages-yaml 0ce45ecf at swipl-devel af9e2e7e; the file is not vendored yet,
# read from the submodule's object store): the SCALAR CLASSIFIER of yaml4pl.c (lines 154-342), which decides what a YAML
# scalar without a tag is: an integer, a float, null, a boolean, a special float, or a string. It looks at the bytes of
# the scalar and at nothing else: it needs no libyaml, no term and no stream, so it is the same whichever carrier
# (a hand port of libyaml, see evidence/R2/pkg2_plan.md in the channel) the parser and emitter end up on.
# NO `# UPSTREAM:` header line: `packages/yaml` is a gitlink at the pin, not a blob of swipl-devel (as src/pl-json.jl).
# NOT registered anywhere, nothing calls it yet: `put_scalar` (needs `PL_put_term_from_chars`, `PL_unify_chars`) and
# `get_value` (the emitter side, `implicit_tag`) is piece 2 at the end of this file. Nothing here has run (no Julia process was started).
#
# DIVERGES (file-wide):
#   1. The scalar is a byte vector and its length is `length(s)`; upstream's `const char *s, size_t len` is NUL
#      terminated (libyaml terminates every scalar), and `is_number` reads that NUL where the C text says `*s` at the end.
#      `_yaml_byte` returns 0 past the end, so the reading is the same. `implicit_tag` takes upstream's
#      NUL-terminated string: its length is the index of the first NUL (`strlen`), as in C.
#   2. The enum `ntype` is three Int constants (`YAML_N_NONE`, `YAML_N_INT`, `YAML_N_FLOAT`): the kernel's `@enum`s carry
#      a manifest row each (`_enum_hash`) and this one is private to the file.
#   3. `is_special_float` returns the value (`nothing` for false) where C returns a bool and writes `*d`.

# PORT: packages/yaml/yaml4pl.c enum ntype
# DIVERGES: see the file header, 2.
"The result of `yaml_is_number` (yaml4pl.c `enum ntype`): not a number, an integer, a float."
const YAML_N_NONE = 0
const YAML_N_INT = 1
const YAML_N_FLOAT = 2

# The byte at 1-based position `i` of `s`, 0 beyond its end (C reads the terminating NUL there): see the file header, 1.
@inline _yaml_byte(s::AbstractVector{UInt8}, i::Int)::Int =
    (i >= 1 && i <= length(s)) ? Int(s[i]) : 0

# PORT: packages/yaml/yaml4pl.c is_digit
@inline _yaml_is_digit(c::Int)::Bool = c >= Int('0') && c <= Int('9')

# PORT: packages/yaml/yaml4pl.c is_nonzero_digit
@inline _yaml_is_nonzero_digit(c::Int)::Bool = c >= Int('1') && c <= Int('9')

# PORT: packages/yaml/yaml4pl.c is_odigit
@inline _yaml_is_odigit(c::Int)::Bool = c >= Int('0') && c <= Int('7')

# PORT: packages/yaml/yaml4pl.c is_xdigit
@inline _yaml_is_xdigit(c::Int)::Bool =
    (c >= Int('0') && c <= Int('9')) || (c >= Int('a') && c <= Int('f')) ||
    (c >= Int('A') && c <= Int('F'))

# PORT: packages/yaml/yaml4pl.c is_number
# DIVERGES: see the file header, 1. `p` is `s` and `e` is the pointer one past the last byte, both 1-based indices.
# The text follows https://yaml.org/spec/1.2.2/#10214-floating-point as upstream does ("0." is NOT a number here, as
# upstream's comment says).
"Whether the scalar `s` is an integer (`YAML_N_INT`), a float (`YAML_N_FLOAT`) or neither (`YAML_N_NONE`) (yaml4pl.c)."
function yaml_is_number(s::AbstractVector{UInt8})::Int
    len = length(s)
    len > 0 || return YAML_N_NONE
    p = 1
    e = len + 1
    isfloat = false

    if e > p && _yaml_byte(s, p) == Int('-')                # -?
        p += 1
    end

    if e - p >= 3 && _yaml_byte(s, p) == Int('0')           # 0oN+$ or 0xN+$
        p += 1
        c = _yaml_byte(s, p)
        if c == Int('o')
            p += 1
            if p < e
                while _yaml_is_odigit(_yaml_byte(s, p))
                    p += 1
                end
            end
            return p == e ? YAML_N_INT : YAML_N_NONE
        elseif c == Int('x')
            p += 1
            if p < e
                while _yaml_is_xdigit(_yaml_byte(s, p))
                    p += 1
                end
            end
            return p == e ? YAML_N_INT : YAML_N_NONE
        end
        p -= 1
    end

    e == p && return YAML_N_NONE

    c = _yaml_byte(s, p)
    if c == Int('0')                                        # ( 0 | ([1-9]+ [0-9]*) )
        p += 1
    elseif _yaml_is_nonzero_digit(c)
        p += 1
        while _yaml_is_digit(_yaml_byte(s, p))
            p += 1
        end
    else
        return YAML_N_NONE
    end

    if e > p && _yaml_byte(s, p) == Int('.')                # ( \. [0-9]* )
        p += 1
        if e > p && _yaml_is_digit(_yaml_byte(s, p))
            while e > p && _yaml_is_digit(_yaml_byte(s, p))
                p += 1
            end
            isfloat = true
        else
            return YAML_N_NONE
        end
    end

    if e > p && (_yaml_byte(s, p) == Int('e') || _yaml_byte(s, p) == Int('E'))  # ( [eE] [-+]? [0-9]+ )?
        p += 1
        if e > p && (_yaml_byte(s, p) == Int('+') || _yaml_byte(s, p) == Int('-'))
            p += 1
        end
        if e > p && _yaml_is_digit(_yaml_byte(s, p))
            p += 1
            while e > p && _yaml_is_digit(_yaml_byte(s, p))
                p += 1
            end
        else
            return YAML_N_NONE
        end
        isfloat = true
    end

    p == e && return isfloat ? YAML_N_FLOAT : YAML_N_INT
    return YAML_N_NONE
end

# PORT: packages/yaml/yaml4pl.c is_null
"Whether the scalar `s` is `null`, `Null`, `NULL` or `~` (yaml4pl.c)."
function yaml_is_null(s::AbstractVector{UInt8})::Bool
    len = length(s)
    if len == 4 && (s == b"null" || s == b"Null" || s == b"NULL")
        return true
    end
    return len == 1 && s[1] == UInt8('~')
end

# PORT: packages/yaml/yaml4pl.c is_true
"Whether the scalar `s` is `true`, `True` or `TRUE` (yaml4pl.c)."
function yaml_is_true(s::AbstractVector{UInt8})::Bool
    return length(s) == 4 && (s == b"true" || s == b"True" || s == b"TRUE")
end

# PORT: packages/yaml/yaml4pl.c is_false
"Whether the scalar `s` is `false`, `False` or `FALSE` (yaml4pl.c)."
function yaml_is_false(s::AbstractVector{UInt8})::Bool
    return length(s) == 5 && (s == b"false" || s == b"False" || s == b"FALSE")
end

# PORT: packages/yaml/yaml4pl.c is_special_float
# DIVERGES: see the file header, 3. A sign is accepted before `.inf` only (as upstream: `.nan` is tested first and
# unsigned).
"The value of the scalar `s` if it is `.nan`, `.NaN`, `.NAN` or an optionally signed `.inf`, `.Inf`, `.INF`; else `nothing` (yaml4pl.c)."
function yaml_is_special_float(s::AbstractVector{UInt8})::Union{Nothing, Float64}
    len = length(s)
    if len == 4 && (s == b".nan" || s == b".NaN" || s == b".NAN")
        return NaN
    end
    neg = false
    from = 1
    c = _yaml_byte(s, 1)
    if c == Int('-') || c == Int('+')
        neg = c == Int('-')
        from = 2
        len -= 1
    end
    if len == 4
        t = view(s, from:(from + 3))
        if t == b".inf" || t == b".Inf" || t == b".INF"
            return neg ? -Inf : Inf
        end
    end
    return nothing
end

# PORT: packages/yaml/yaml4pl.c implicit_tag
# DIVERGES: see the file header, 1 (the length is `strlen`, the index of the first NUL); the result is a `String`
# (`nothing` for NULL).
"The tag YAML's core schema gives the plain scalar `s`: `\"float\"`, `\"int\"`, `\"null\"`, `\"bool\"`, or `nothing` (yaml4pl.c)."
function yaml_implicit_tag(s::AbstractVector{UInt8})::Union{Nothing, String}
    z = findfirst(==(0x00), s)
    t = z === nothing ? s : view(s, 1:(z - 1))
    nt = yaml_is_number(t)
    if nt != YAML_N_NONE
        return nt == YAML_N_FLOAT ? "float" : "int"
    elseif yaml_is_null(t)
        return "null"
    elseif yaml_is_true(t) || yaml_is_false(t)
        return "bool"
    elseif yaml_is_special_float(t) !== nothing
        return "float"
    else
        return nothing
    end
end

# ======================================================================================================================
# YAML1 piece 2 (yaml4pl.c lines 982-1230): the EVENT-TERM DECODING of `yaml_emit_event/2`. The C reads the Prolog event term
# (`stream_start`, `scalar(Value, Tag, Anchor, Style)`, ...), calls one of libyaml's `yaml_*_event_initialize` functions and hands the
# event to `yaml_emitter_emit`. Here the reading is `yaml_decode_event`, which returns a `yaml_event` (the fields of libyaml's
# `yaml_event_t` that yaml4pl.c ever sets); the carrier (a libyaml port, evidence/R2/pkg2_plan.md Q2) takes the event from there, and
# `yaml_emit_error` is the failure branch of `emit_event` (`error(yaml_error(Code, Problem), _)`). Nothing here has run (no Julia
# process was started); it needs the term API of the kernel (`PL_get_name_arity`, `_PL_get_arg`, `PL_get_text`, ...) and an `ld`.
#
# DIVERGES (piece 2):
#   4. No `yaml_*_event_initialize` call, so no `ok == 0` branch (`PL_resource_error("memory")` on a failed allocation): a Julia
#      allocation does not fail like that. The event's strings are `String`s, `nothing` for C's NULL.
#   5. The C functions return a bool and write through pointers: here `yaml_get_string_arg` returns `(ok, string)`, `yaml_get_value`
#      `(ok, value, tag)`, `yaml_get_bool_arg` the Bool or `nothing`, `yaml_decode_event` the event or `nothing`; "false" always has
#      its exception raised, as in C. A C string ends at its first NUL, so `get_string_arg`'s result is cut there (`_yaml_cstring`).
#   6. Atoms are compared by their text (`sym_text`), where upstream compares the `atom_t`s `MKATOM` made at install time.
#   7. The numbers of the libyaml enums are counted from /usr/include/yaml.h (libyaml 0.2.5): the enumerators have no initialisers, so
#      the number is the position. MEASURE ON THE LANE: nothing, they are fixed by the header, but a libyaml port that keeps its own
#      numbering must keep these.

# libyaml's yaml_event_type_t, yaml_encoding_t, yaml_scalar_style_t, yaml_sequence_style_t, yaml_mapping_style_t (yaml.h)
const YAML_NO_EVENT = 0
const YAML_STREAM_START_EVENT = 1
const YAML_STREAM_END_EVENT = 2
const YAML_DOCUMENT_START_EVENT = 3
const YAML_DOCUMENT_END_EVENT = 4
const YAML_ALIAS_EVENT = 5
const YAML_SCALAR_EVENT = 6
const YAML_SEQUENCE_START_EVENT = 7
const YAML_SEQUENCE_END_EVENT = 8
const YAML_MAPPING_START_EVENT = 9
const YAML_MAPPING_END_EVENT = 10
const YAML_ANY_ENCODING = 0
const YAML_UTF8_ENCODING = 1
const YAML_ANY_SCALAR_STYLE = 0
const YAML_PLAIN_SCALAR_STYLE = 1
const YAML_SINGLE_QUOTED_SCALAR_STYLE = 2
const YAML_DOUBLE_QUOTED_SCALAR_STYLE = 3
const YAML_LITERAL_SCALAR_STYLE = 4
const YAML_FOLDED_SCALAR_STYLE = 5
const YAML_BLOCK_SEQUENCE_STYLE = 1
const YAML_BLOCK_MAPPING_STYLE = 1

# PORT: packages/yaml/yaml4pl.c yaml_event_t (the fields yaml4pl.c sets)
# DIVERGES: see the piece 2 header, 4. `implicit` is the `implicit` of the document and sequence/mapping events and the
# `plain_implicit` of a scalar; `quoted_implicit` is a scalar's; a scalar's `length` is always -1 (`strlen`) and not kept.
"The event `yaml_decode_event` hands to the emitter (libyaml's `yaml_event_t`): its type, strings, flags and style."
mutable struct yaml_event
    type::Int
    anchor::Union{Nothing, String}
    tag::Union{Nothing, String}
    value::Union{Nothing, String}
    implicit::Bool
    quoted_implicit::Bool
    style::Int
    encoding::Int
end

"A `yaml_event` of type `type` with every other field unset (what `yaml_event_t event` is before its `_initialize`)."
yaml_event(type::Int) = yaml_event(type, nothing, nothing, nothing, false, false, 0, 0)

# `s` up to its first NUL: what the C `char *` of a text reads (the text is NUL terminated).
function _yaml_cstring(s::String)::String
    z = findfirst(==('\0'), s)
    return z === nothing ? s : s[1:(z - 1)]
end

# PORT: packages/yaml/yaml4pl.c get_string_arg
# DIVERGES: see the piece 2 header, 5. Argument `i` of `ev`: a variable is `nothing` (C: NULL), else its text (CVT_ATOMIC: an atom, a
# string or a number); anything else raises (CVT_EXCEPTION).
"`(ok, s)`: the text of argument `i` of the event `ev` (`nothing` for a variable); `ok` false with the error raised (yaml4pl.c)."
function yaml_get_string_arg(
    ld::PL_local_data{T}, i::Int, ev::term_t, tmp::term_t
)::Tuple{Bool, Union{Nothing, String}} where {T}
    if _PL_get_arg(ld, i, ev, tmp)
        if PL_is_variable(ld, tmp)
            return (true, nothing)
        end
        txt = PL_get_text(ld, tmp, CVT_ATOMIC | CVT_EXCEPTION)
        if txt !== nothing
            return (true, _yaml_cstring(text_string(txt)))
        end
    end
    return (false, nothing)
end

# PORT: packages/yaml/yaml4pl.c get_value
# DIVERGES: see the piece 2 header, 5 and file header 1. `tag` is in and out (`yaml_char_t **tag`); `len` is the byte length of the
# UTF-8 text and the NUL test is `strlen(s) < len`. The floats' text is the kernel's `PL_get_text(CVT_FLOAT)`.
"`(ok, value, tag)`: the scalar text of the term `t`, and `tag` (given in) set to the str tag if `t` is a string that would read as another type (yaml4pl.c)."
function yaml_get_value(
    ld::PL_local_data{T}, t::term_t, tag::Union{Nothing, String}
)::Tuple{Bool, Union{Nothing, String}, Union{Nothing, String}} where {T}
    txt = nothing
    if PL_is_integer(ld, t)
        txt = PL_get_text(ld, t, CVT_INTEGER | CVT_EXCEPTION)
    else
        d = PL_get_float(ld, t)
        if d !== nothing
            if isnan(d)
                return (true, ".nan", tag)
            elseif isinf(d)
                return (true, d < 0 ? "-.inf" : ".inf", tag)
            else
                txt = PL_get_text(ld, t, CVT_FLOAT | CVT_EXCEPTION)
            end
        elseif PL_is_string(ld, t)
            txt = PL_get_text(ld, t, CVT_STRING | CVT_EXCEPTION)
            if txt !== nothing && tag === nothing &&
                yaml_implicit_tag(codeunits(text_string(txt))) !== nothing
                tag = "tag:yaml.org,2002:str"
            end
        elseif PL_is_atom(ld, t)
            txt = PL_get_text(ld, t, CVT_ATOM | CVT_EXCEPTION)
        else
            PL_type_error(ld, "yaml_scalar", t)
        end
    end

    txt === nothing && return (false, nothing, tag)
    s = text_string(txt)
    if findfirst(==('\0'), s) !== nothing                    # strlen(s) < len
        PL_domain_error(ld, "string_without_nul", t)
        return (false, nothing, tag)
    end
    return (true, s, tag)
end

# PORT: packages/yaml/yaml4pl.c get_bool_arg
# DIVERGES: see the piece 2 header, 5.
"The Boolean argument `i` of the event `ev`, or `nothing` with the error raised (yaml4pl.c)."
function yaml_get_bool_arg(
    ld::PL_local_data{T}, i::Int, ev::term_t, tmp::term_t
)::Union{Nothing, Bool} where {T}
    _PL_get_arg(ld, i, ev, tmp) || return nothing
    return PL_get_bool_ex(ld, tmp)
end

# PORT: packages/yaml/yaml4pl.c emit_event
# DIVERGES: see the piece 2 header, 4, 5 and 6. Only the decoding: the call of `yaml_emitter_emit` and its error term
# (`yaml_emit_error`) are the carrier's. The order of the reads and of the errors is the C's: a `scalar/4` reads Tag (arg 2),
# Value (arg 1, which may set the tag), Anchor (arg 3), then the style.
"The `yaml_event` the event term `Event` stands for, or `nothing` with the exception raised: `domain_error(yaml_event, Event)` for an unknown event (yaml4pl.c)."
function yaml_decode_event(
    ld::PL_local_data{T}, Event::term_t
)::Union{Nothing, yaml_event} where {T}
    na = PL_get_name_arity(ld, Event)
    na === nothing && (PL_domain_error(ld, "yaml_event", Event); return nothing)
    name = sym_text(na[1])
    arity = na[2]
    tmp = PL_new_term_ref(ld)

    if name == "stream_start" && arity == 0
        ev = yaml_event(YAML_STREAM_START_EVENT)
        ev.encoding = YAML_UTF8_ENCODING
        return ev
    elseif name == "stream_end" && arity == 0
        return yaml_event(YAML_STREAM_END_EVENT)
    elseif name == "document_start" && arity <= 1
        implicit = false
        if arity == 1
            b = yaml_get_bool_arg(ld, 1, Event, tmp)
            b === nothing && return nothing
            implicit = b
        end
        ev = yaml_event(YAML_DOCUMENT_START_EVENT)
        ev.implicit = implicit
        return ev
    elseif name == "document_end" && arity <= 1
        implicit = false
        if arity == 1
            b = yaml_get_bool_arg(ld, 1, Event, tmp)
            b === nothing && return nothing
            implicit = b
        end
        ev = yaml_event(YAML_DOCUMENT_END_EVENT)
        ev.implicit = implicit
        return ev
    elseif name == "mapping_start" && arity == 2
        ok1, anchor = yaml_get_string_arg(ld, 1, Event, tmp)
        ok1 || return nothing
        ok2, tag = yaml_get_string_arg(ld, 2, Event, tmp)
        ok2 || return nothing
        ev = yaml_event(YAML_MAPPING_START_EVENT)
        ev.anchor = anchor
        ev.tag = tag
        ev.implicit = false
        ev.style = YAML_BLOCK_MAPPING_STYLE
        return ev
    elseif name == "mapping_end" && arity == 0
        return yaml_event(YAML_MAPPING_END_EVENT)
    elseif name == "sequence_start" && arity == 2
        ok1, anchor = yaml_get_string_arg(ld, 1, Event, tmp)
        ok1 || return nothing
        ok2, tag = yaml_get_string_arg(ld, 2, Event, tmp)
        ok2 || return nothing
        ev = yaml_event(YAML_SEQUENCE_START_EVENT)
        ev.anchor = anchor
        ev.tag = tag
        ev.implicit = false
        ev.style = YAML_BLOCK_SEQUENCE_STYLE
        return ev
    elseif name == "sequence_end" && arity == 0
        return yaml_event(YAML_SEQUENCE_END_EVENT)
    elseif name == "scalar" && arity == 4
        ok1, tag = yaml_get_string_arg(ld, 2, Event, tmp)
        ok1 || return nothing
        _PL_get_arg(ld, 1, Event, tmp) || return nothing
        ok2, value, tag = yaml_get_value(ld, tmp, tag)
        ok2 || return nothing
        ok3, anchor = yaml_get_string_arg(ld, 3, Event, tmp)
        ok3 || return nothing

        _PL_get_arg(ld, 4, Event, tmp) || return nothing
        style_a = PL_get_atom_ex(ld, tmp)
        style_a === nothing && return nothing
        style_name = sym_text(style_a)
        style = if style_name == "plain"
            YAML_PLAIN_SCALAR_STYLE
        elseif style_name == "single_quoted"
            YAML_SINGLE_QUOTED_SCALAR_STYLE
        elseif style_name == "double_quoted"
            YAML_DOUBLE_QUOTED_SCALAR_STYLE
        elseif style_name == "literal"
            YAML_LITERAL_SCALAR_STYLE
        elseif style_name == "folded"
            YAML_FOLDED_SCALAR_STYLE
        else
            PL_domain_error(ld, "yaml_scalar_style", tmp)
            return nothing
        end

        ev = yaml_event(YAML_SCALAR_EVENT)
        ev.anchor = anchor
        ev.tag = tag
        ev.value = value
        ev.implicit = tag === nothing
        ev.quoted_implicit = tag === nothing
        ev.style = style
        return ev
    elseif name == "alias" && arity == 1
        ok1, alias = yaml_get_string_arg(ld, 1, Event, tmp)
        ok1 || return nothing
        ev = yaml_event(YAML_ALIAS_EVENT)
        ev.anchor = alias
        return ev
    end
    PL_domain_error(ld, "yaml_event", Event)
    return nothing
end

# PORT: packages/yaml/yaml4pl.c emit_event
# DIVERGES: see the piece 2 header, 5. The failure branch of `yaml_emitter_emit` (and, with the parser's `parser->error` and
# `parser->problem`, of parse_document's error exit, yaml4pl.c 625-634): raise `error(yaml_error(Code, Problem), _)`; false.
# `PL_unify_term(PL_STRING, problem)` is a string term here (`mk_gnd(T, problem)`: BLIND CODE, to be confirmed on the lane).
"Raise `error(yaml_error(Code, Problem), _)`, `Code` the emitter's or parser's integer error and `Problem` a string; returns false (yaml4pl.c)."
function yaml_emit_error(ld::PL_local_data{T}, code::Int, problem::String)::Bool where {T}
    ex = PL_new_term_ref(ld)
    a = PL_new_term_ref(ld)
    b = PL_new_term_ref(ld)
    if PL_unify_functor(ld, ex, mk_sym(T, :error), 2) &&
        PL_unify_arg(ld, 1, ex, a) &&
        PL_unify_functor(ld, a, mk_sym(T, :yaml_error), 2) &&
        PL_unify_arg(ld, 1, a, b) && PL_unify_integer(ld, b, code) &&
        PL_unify_arg(ld, 2, a, b) && PL_unify_atomic(ld, b, mk_gnd(T, problem))
        PL_raise_exception(ld, ex)
    end
    return false
end

# ---------------------------------------------------------------------------------------------------------------------------------
# YAML1 piece 3 (packages/yaml/yaml4pl.c, packages-yaml 0ce45ecf, lines 384-560): the ANCHOR TABLE the parser keeps while it reads one
# document: a chained hash table from an anchor's name to the term that stands for the node (`&name` stores it, `*name` finds it).
# Ported as it is: the same hash (MurmurHashAligned2 with the seed 0x6263533a, 32-bit arithmetic), the same 16 buckets that double,
# the same chains (a new cell is put at the HEAD of its chain; `rehash` walks every old chain from its head and puts each cell at the
# head of its new one, which REVERSES the order of the cells of one name that share a chain: `find_anchor` returns the first match, so
# the cell it finds depends on this order, and a Dict would not reproduce that). `store_anchor` is the glue the three parser cases
# (sequence start, mapping start, and the alias lookup) call. Needs `PL_copy_term_ref` (an `ld`); nothing else of the term layer.
# Nothing here has run (no Julia process was started).
#
# DIVERGES (piece 3):
#   8. `free_anchor_table` is not ported (the garbage collector frees the cells); `new_anchor_table` and `rehash` have no
#      `PL_resource_error("memory")` branch (a Julia allocation does not fail like that), so `new_anchor_table` cannot fail.
#   9. A name is a `String`; the C's `strlen`/`strcmp` stop at the first NUL, so `_yaml_cstring` cuts the name there, once, where the C
#      reads it: the hash is taken over the bytes of that cut name. Buckets are 1-based in `entries`: bucket `k` of the C is
#      `entries[k + 1]`. `find_anchor` returns the term reference, 0 when there is none (as C: `term_t` is an `Int` here).
#  10. `rehash`'s return value is read as upstream's `add_anchor` reads it (`if ( !rehash(t) ) return FALSE;`, rehash answering
#      FALSE when it succeeded): see the comment at `yaml_add_anchor`, and the lane run list of the handoff.

# PORT: packages/yaml/yaml4pl.c ANCHOR_TABLE_SIZE, SEED
const YAML_ANCHOR_TABLE_SIZE = 16
const YAML_ANCHOR_SEED = 0x6263533a

# PORT: packages/yaml/yaml4pl.c hcell
"One cell of an anchor table's chain: the next cell, the anchor's name and the term reference of its node (yaml4pl.c `hcell`)."
mutable struct yaml_hcell
    next::Union{Nothing, yaml_hcell}
    name::String
    value::Int
end

# PORT: packages/yaml/yaml4pl.c htable
"The anchor table (yaml4pl.c `htable`): the number of cells added, the number of buckets, the chains."
mutable struct yaml_htable
    count::Int
    size::Int
    entries::Vector{Union{Nothing, yaml_hcell}}
end

# PORT: packages/yaml/yaml4pl.c new_anchor_table
# DIVERGES: see the piece 3 header, 8.
"A new anchor table, `YAML_ANCHOR_TABLE_SIZE` empty buckets (yaml4pl.c)."
function yaml_new_anchor_table()::yaml_htable
    return yaml_htable(0, YAML_ANCHOR_TABLE_SIZE, fill(nothing, YAML_ANCHOR_TABLE_SIZE))
end

# PORT: packages/yaml/yaml4pl.c MurmurHashAligned2
# DIVERGES: `key[1:len]` for C's `(key, len)`; every `unsigned int` is a UInt32 (wrapping), C's `data[i] << n` (an `int` shift of an
# unsigned char) is the same bits as the UInt32 shift. `len` is cut to 32 bits where C casts `(unsigned int)len`.
"MurmurHashAligned2 of the first `len` bytes of `key` (yaml4pl.c, the seed `seed`)."
function yaml_murmur_hash_aligned2(
    key::AbstractVector{UInt8}, len::Int, seed::UInt32
)::UInt32
    m = 0x5bd1e995
    r = 24
    h = seed ⊻ (len % UInt32)
    i = 1
    while len >= 4
        k =
            UInt32(key[i]) | (UInt32(key[i + 1]) << 8) | (UInt32(key[i + 2]) << 16) |
            (UInt32(key[i + 3]) << 24)
        k *= m
        k ⊻= k >> r
        k *= m
        h *= m
        h ⊻= k
        i += 4
        len -= 4
    end
    if len == 3
        h ⊻= UInt32(key[i + 2]) << 16
    end
    if len >= 2
        h ⊻= UInt32(key[i + 1]) << 8
    end
    if len >= 1
        h ⊻= UInt32(key[i])
        h *= m
    end
    h ⊻= h >> 13
    h *= m
    h ⊻= h >> 15
    return h
end

# `MurmurHashAligned2(name, strlen(name), SEED) % size`, as a 1-based bucket number (DIVERGES 9).
function _yaml_anchor_bucket(name::String, size::Int)::Int
    b = codeunits(name)
    return Int(yaml_murmur_hash_aligned2(b, length(b), YAML_ANCHOR_SEED) % UInt32(size)) + 1
end

# PORT: packages/yaml/yaml4pl.c rehash
# DIVERGES: see the piece 3 header, 8 and 10. Returns false, as the C does when the new array was allocated.
"Double the bucket count of `t`, re-linking every cell at the head of its new chain; returns false (yaml4pl.c's answer on success)."
function yaml_rehash(t::yaml_htable)::Bool
    newsize = t.size * 2
    new = Vector{Union{Nothing, yaml_hcell}}(nothing, newsize)
    for i in 1:(t.size)
        c = t.entries[i]
        while c !== nothing
            k = _yaml_anchor_bucket(c.name, newsize)
            n = c.next
            c.next = new[k]
            new[k] = c
            c = n
        end
    end
    t.size = newsize
    t.entries = new
    return false
end

# PORT: packages/yaml/yaml4pl.c add_anchor
# DIVERGES: see the piece 3 header, 8, 9 and 10. UPSTREAM AS IS: when `count > size` the table is rehashed and the function then
# returns false WITHOUT adding the cell (the C reads rehash's false as a failure), whatever rehash answered; the next add finds room.
"Add the anchor `name` for the node `value` (a copy of the reference) to `t`; false when `t` was rehashed instead (yaml4pl.c)."
function yaml_add_anchor(
    ld::PL_local_data{T}, t::yaml_htable, name::String, value::term_t
)::Bool where {T}
    s = _yaml_cstring(name)
    if t.count > t.size
        if !yaml_rehash(t)
            return false
        end
    end
    k = _yaml_anchor_bucket(s, t.size)
    t.entries[k] = yaml_hcell(t.entries[k], s, PL_copy_term_ref(ld, value))
    t.count += 1
    return true
end

# PORT: packages/yaml/yaml4pl.c find_anchor
# DIVERGES: see the piece 3 header, 9.
"The term reference stored for the anchor `name` (the first cell of its chain with that name), 0 when there is none (yaml4pl.c)."
function yaml_find_anchor(t::yaml_htable, name::String)::Int
    s = _yaml_cstring(name)
    c = t.entries[_yaml_anchor_bucket(s, t.size)]
    while c !== nothing
        c.name == s && return c.value
        c = c.next
    end
    return 0
end

# PORT: packages/yaml/yaml4pl.c store_anchor
# DIVERGES: see the piece 3 header, 5 (results as tuples) and 8. `anchors` is C's `htable **` (nothing until the first anchor) and the
# result's second element is its new value; `anchor` is the event's `data.alias.anchor` (the same field of a sequence or mapping start).
"`(ok, anchors)`: store the node `node` under the event's `anchor` (when it has one), creating the table on the first (yaml4pl.c)."
function yaml_store_anchor(
    ld::PL_local_data{T}, anchors::Union{Nothing, yaml_htable}, node::term_t,
    anchor::Union{Nothing, String}
)::Tuple{Bool, Union{Nothing, yaml_htable}} where {T}
    anchor === nothing && return (true, anchors)
    anchors === nothing && (anchors = yaml_new_anchor_table())
    return (yaml_add_anchor(ld, anchors, anchor, node), anchors)
end

# ======================================================================================================================
# YAML1 piece B1 (packages/yaml/yaml4pl.c, packages-yaml 0ce45ecf, lines 62-152, 344-376, 562-610): the PARSE-SIDE TERM LAYER, with no libyaml
# in it. The parser (piece B2) walks libyaml's events and builds the Prolog term of the document with these: the stack of open containers
# (`node`: `push`, `pop`, `extend`), the scalar (`put_scalar`, which makes the term of one scalar event: a tagged one, a number, null,
# true/false, a special float, or a string/atom), the mapping and sequence terms (`create_mapping`, `create_sequence`: `mapping(List, ...)`/
# `sequence(List, ...)`, wrapped in `tag(Tag, ...)` when the event has a tag) and the two readers that find the list inside one of them
# again (`get_mapping_mapping`, `get_sequence_list`). They run over the `yaml_event` of piece 2 (the fields of libyaml's `yaml_event_t`
# that yaml4pl.c reads), over piece 1's classifier and the term API of the kernel. Nothing here has run (no Julia process was started).
#
# DIVERGES (piece B1; the file's own numbering goes on):
#  11. The node enum is three Int constants `YAML_NODE_TOP/MAPPING/SEQUENCE` (0, 1, 2; the names are `N_TOP`/`N_MAPPING`/`N_SEQUENCE`; `N_NONE`,
#      `N_INT`, `N_FLOAT` of `ntype` are piece 1's `YAML_N_*`). `node` is the mutable struct `yaml_node`; its `parent` is `nothing` for NULL and a
#      term reference `0` is C's `term_t 0`: `key == 0` is the C's `state->key == NULL` test (`0` is never a term reference). The stack is a
#      `Base.RefValue{Union{Nothing, yaml_node}}` (C's `node **stack`). `push` has no `malloc` and so no `PL_resource_error("memory")` branch,
#      `pop` and `free` leave the nodes to the garbage collector. The two `assert(0)` branches (`pop` on an empty stack, `extend` on an unknown
#      type) are `return false` as C compiled with NDEBUG answers.
#  12. `PL_put_functor(t, f)` (a fresh compound of fresh arguments in `t`) is not in the kernel's FLI: it is `PL_put_variable` + `PL_unify_functor`
#      (`_yaml_put_functor`; the functor is its name and arity, as `PL_unify_functor`'s). The `FUNCTOR_*` constants are `_err_functor(ld, name, arity)`
#      (the functor WORD); `PL_is_functor` takes the name and arity, so `tag`/2 is `mk_sym(T, :tag)`.
#  13. `PL_unify_term(tmp, PL_FUNCTOR, FUNCTOR_eq2, PL_TERM, key, PL_TERM, v)` of `extend` is `PL_cons_functor` of a new reference (`=`/2 over `key`
#      and `v`) + `PL_unify` + `PL_reset_term_refs` of that reference (C's `PL_unify_term` makes no reference): the same term, a fresh `=`/2 or the
#      existing one checked.
#  14. The event's strings are Julia `String`s (`nothing` for NULL) and the scalar's `len` is `ncodeunits(value)`, upstream's `event->data.scalar.length`
#      (libyaml's count, which also counts a NUL byte inside the text): the classifier and `PL_put_term_from_chars` get `codeunits(value)`, so a NUL
#      byte survives into the term as in C. `PL_unify_chars(t, REP_UTF8|type, len, s)` is `_yaml_unify_chars` (`PL_unify_text` of an `ENC_UTF8` text,
#      as pl-pcre.jl's `re_put_chars` does for `PL_put_chars`). A scalar event with `value === nothing` (libyaml never makes one) reads as "".
#  15. `PL_unify_atom_chars(tmp, tag)` and `PL_put_atom_chars(tag, ...)` read the C string as ISO Latin-1, byte per character, and stop at the first NUL
#      (`_yaml_latin1_sym`): a tag with a byte >= 0x80 is NOT decoded as UTF-8, as upstream (libyaml's tag text is UTF-8: that is upstream's own mixing).
#      `HUGE_VAL` is `Inf`. `PL_clear_exception()` takes `ld`.

# PORT: packages/yaml/yaml4pl.c N_TOP, N_MAPPING, N_SEQUENCE
# DIVERGES: see the piece B1 header, 11.
const YAML_NODE_TOP = 0
const YAML_NODE_MAPPING = 1
const YAML_NODE_SEQUENCE = 2

# PORT: packages/yaml/yaml4pl.c node
# DIVERGES: see the piece B1 header, 11.
"One open container of the parse (yaml4pl.c `node`): its parent, its type `YAML_NODE_*`, the key just read (0: none) and the document tail (term references)."
mutable struct yaml_node
    parent::Union{Nothing, yaml_node}
    type::Int
    key::Int
    doc::Int
end

# PORT: packages/yaml/yaml4pl.c push
# DIVERGES: see the piece B1 header, 11. Returns the new node, which is also `stack[]` now.
"Push a copy of `old` on `stack`; returns the new top, whose `parent` is the old top (yaml4pl.c)."
function yaml_push(stack::Base.RefValue{Union{Nothing, yaml_node}}, old::yaml_node)::yaml_node
    n = yaml_node(stack[], old.type, old.key, old.doc)        # *n = *old; n->parent = *stack
    stack[] = n                                               # *stack = n
    return n
end

# PORT: packages/yaml/yaml4pl.c pop
# DIVERGES: see the piece B1 header, 11. `old` receives a copy of the popped top, `parent` included (`*old = *n`).
"Pop the top of `stack` into `old`; false (the C `assert(0)`) when the stack is empty (yaml4pl.c)."
function yaml_pop(stack::Base.RefValue{Union{Nothing, yaml_node}}, old::yaml_node)::Bool
    n = stack[]
    if n !== nothing
        old.parent = n.parent                                 # *old = *n
        old.type = n.type
        old.key = n.key
        old.doc = n.doc
        stack[] = n.parent                                    # *stack = n->parent
        return true
    end
    return false
end

# PORT: packages/yaml/yaml4pl.c extend
# DIVERGES: see the piece B1 header, 11 and 13.
"Add the value `v` to the container `state`: unify it (top), append it to the list (sequence), or hold it as the key / complete the `Key=Value` (mapping) (yaml4pl.c)."
function yaml_extend(ld::PL_local_data{T}, state::yaml_node, tmp::term_t, v::term_t)::Bool where {T}
    if state.type == YAML_NODE_TOP
        return PL_unify(ld, state.doc, v)
    elseif state.type == YAML_NODE_SEQUENCE
        return PL_unify_list(ld, state.doc, tmp, state.doc) && PL_unify(ld, tmp, v)
    elseif state.type == YAML_NODE_MAPPING
        if state.key != 0
            key = state.key
            state.key = 0
            PL_unify_list(ld, state.doc, tmp, state.doc) || return false
            pair = PL_new_term_ref(ld)
            rc = PL_cons_functor(ld, pair, _err_functor(ld, Symbol("="), 2), key, v) && PL_unify(ld, tmp, pair)
            PL_reset_term_refs(ld, pair)
            return rc
        else
            state.key = v
            return true
        end
    end
    return false
end

# PORT: packages/yaml/yaml4pl.c PL_put_functor (as yaml4pl.c's put_scalar, create_mapping and create_sequence use it)
# DIVERGES: see the piece B1 header, 12.
"Put a new compound `name`/`arity` of fresh variables into `t` (kernel stand-in for `PL_put_functor(t, f)`)."
function _yaml_put_functor(ld::PL_local_data{T}, t::term_t, name::Symbol, arity::Int)::Bool where {T}
    PL_put_variable(ld, t)
    return PL_unify_functor(ld, t, mk_sym(T, name), arity)
end

# PORT: packages/yaml/yaml4pl.c PL_unify_chars (as yaml4pl.c's put_scalar uses it)
# DIVERGES: see the piece B1 header, 14.
"Unify `t` with the first `len` bytes of `s` (UTF-8) made a `type` (`PL_ATOM` or `PL_STRING`) (kernel stand-in for `PL_unify_chars(t, REP_UTF8|type, len, s)`)."
function _yaml_unify_chars(ld::PL_local_data{T}, t::term_t, type::Int, len::Int, s::AbstractVector{UInt8})::Bool where {T}
    txt = PL_chars_t(Vector{UInt8}(s[1:len]), len, ENC_UTF8, false)
    return PL_unify_text(ld, t, 0, txt, type)
end

# PORT: packages/yaml/yaml4pl.c PL_unify_atom_chars, PL_put_atom_chars (as yaml4pl.c's put_scalar, create_mapping and create_sequence use them)
# DIVERGES: see the piece B1 header, 15.
"The atom name the C string `s` makes through `PL_*_atom_chars`: its bytes up to the first NUL, each one an ISO Latin-1 character."
_yaml_latin1_sym(s::String)::Symbol = Symbol(String(Char.(codeunits(_yaml_cstring(s)))))

# PORT: packages/yaml/yaml4pl.c put_scalar
# DIVERGES: see the piece B1 header, 12, 14 and 15. `iskey` is a Bool (C `int`). `t` must be a fresh variable, as the C callers pass one.
"""
Put the term of the scalar event `event` into `t` (yaml4pl.c): `tag(Tag, Text)` when it has a tag, else (by the classifier of piece 1) a number,
`null`/`true`/`false`, a special float, or a string (an atom when `iskey`). Float overflow reads as `inf`/`-inf`.
"""
function yaml_put_scalar(ld::PL_local_data{T}, t::term_t, iskey::Bool, event::yaml_event)::Bool where {T}
    value = event.value === nothing ? "" : event.value
    s = codeunits(value)                                      # char *s = event->data.scalar.value
    len = ncodeunits(value)                                   # size_t len = event->data.scalar.length
    type = iskey ? PL_ATOM : PL_STRING                        # flags = iskey ? PL_ATOM|REP_UTF8 : PL_STRING|REP_UTF8

    if event.tag !== nothing
        tmp = PL_new_term_ref(ld)
        return _yaml_put_functor(ld, t, :tag, 2) &&
               _PL_get_arg(ld, 1, t, tmp) &&
               PL_unify_atom(ld, tmp, mk_sym(T, _yaml_latin1_sym(event.tag))) &&
               _PL_get_arg(ld, 2, t, tmp) &&
               _yaml_unify_chars(ld, tmp, type, len, s)
    end

    nt = yaml_is_number(s)
    if nt != YAML_N_NONE
        if PL_put_term_from_chars(ld, t, UInt32(REP_UTF8 | CVT_EXCEPTION), s, len)
            return true
        end
        if nt == YAML_N_FLOAT                                 # float overflow: YAML wants a float
            PL_clear_exception(ld)
            return PL_put_float(ld, t, _yaml_byte(s, 1) == Int('-') ? -Inf : Inf)
        end
        return false
    elseif yaml_is_null(s)
        return PL_unify_atom(ld, t, mk_sym(T, :null))
    elseif yaml_is_true(s)
        return PL_unify_atom(ld, t, mk_sym(T, Symbol("true")))
    elseif yaml_is_false(s)
        return PL_unify_atom(ld, t, mk_sym(T, Symbol("false")))
    end
    d = yaml_is_special_float(s)
    if d !== nothing
        return PL_unify_float(ld, t, d)
    end
    return _yaml_unify_chars(ld, t, type, len, s)
end

# PORT: packages/yaml/yaml4pl.c create_mapping
# DIVERGES: see the piece B1 header, 12 and 15. The tag of the mapping-start event is `event.tag`.
"Put `mapping(_, _, _)` into `t`, wrapped in `tag(Tag, ...)` when the event has a tag (yaml4pl.c)."
function yaml_create_mapping(ld::PL_local_data{T}, t::term_t, event::yaml_event)::Bool where {T}
    _yaml_put_functor(ld, t, :mapping, 3) || return false

    if event.tag !== nothing
        tag = PL_new_term_ref(ld)
        if !PL_put_atom(ld, tag, mk_sym(T, _yaml_latin1_sym(event.tag))) ||
           !PL_cons_functor(ld, t, _err_functor(ld, :tag, 2), tag, t)
            return false
        end
    end

    return true
end

# PORT: packages/yaml/yaml4pl.c get_mapping_mapping
# DIVERGES: see the piece B1 header, 12.
"Replace `t`, a term made by `yaml_create_mapping`, by the first argument of its `mapping/3` (through `tag/2` when tagged) (yaml4pl.c)."
function yaml_get_mapping_mapping(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    if PL_is_functor(ld, t, mk_sym(T, :tag), 2)
        _PL_get_arg(ld, 2, t, t)
    end
    _PL_get_arg(ld, 1, t, t)                                  # mapping

    return true
end

# PORT: packages/yaml/yaml4pl.c create_sequence
# DIVERGES: see the piece B1 header, 12 and 15. The tag of the sequence-start event is `event.tag`.
"Put `sequence(_, _, _)` into `t`, wrapped in `tag(Tag, ...)` when the event has a tag (yaml4pl.c)."
function yaml_create_sequence(ld::PL_local_data{T}, t::term_t, event::yaml_event)::Bool where {T}
    _yaml_put_functor(ld, t, :sequence, 3) || return false

    if event.tag !== nothing
        tag = PL_new_term_ref(ld)
        if !PL_put_atom(ld, tag, mk_sym(T, _yaml_latin1_sym(event.tag))) ||
           !PL_cons_functor(ld, t, _err_functor(ld, :tag, 2), tag, t)
            return false
        end
    end

    return true
end

# PORT: packages/yaml/yaml4pl.c get_sequence_list
# DIVERGES: see the piece B1 header, 12.
"Replace `t`, a term made by `yaml_create_sequence`, by the first argument of its `sequence/3` (through `tag/2` when tagged) (yaml4pl.c)."
function yaml_get_sequence_list(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    if PL_is_functor(ld, t, mk_sym(T, :tag), 2)
        _PL_get_arg(ld, 2, t, t)
    end
    _PL_get_arg(ld, 1, t, t)

    return true
end

# ---------------------------------------------------------------------------------------------------------------------------------
# YAML1 piece A (packages/yaml/yaml4pl.c, packages-yaml 0ce45ecf at swipl-devel af9e2e7e; evidence/R2/yaml_plan.md sections 1, 2 and 5 A): THE CARRIER BINDING.
# D-1004 (Shivaji: LibYAML_jll approved, same carrier rule as PCRE2_jll, D-1002): libyaml is reached by `ccall` into LibYAML_jll (a REGISTRY JLL, not a
# stdlib one: the first `Pkg.resolve` needs the network once). Below: the libyaml enum numbers the tests need that piece 2 does not hold (the error codes),
# the sizes and field offsets of `yaml_event_t`, `yaml_parser_t` and `yaml_emitter_t` (x86-64, MEASURED by a gcc probe against libyaml 0.2.5's yaml.h: the
# plan's section 1; the JLL is pinned to `=0.2.5` in Project.toml and the first test compares `yaml_get_version_string()` with "0.2.5"), the 21 libyaml
# entry points yaml4pl.c calls plus `yaml_get_version_string`/`yaml_get_version` as typed wrappers (C line numbers in each comment), `calloc`/`free` helpers
# for the three structs and the accessors that read the only fields yaml4pl.c reads (event type, scalar value/length/tag/anchor, the collection tag, the
# parser's and emitter's `error`/`problem`). The `yaml_read_handler`/`yaml_write_handler` callbacks (C 758-815, 823-855) are NOT here: `yaml_parser_set_input`
# and `yaml_emitter_set_output` take the raw function pointer, and the `@cfunction` handlers with their registry are the parse driver's piece (B2) and the
# emitter's (D). Nothing here has run (no Julia process was started, and LibYAML_jll is not in the depot yet).
#
# DIVERGES (piece A; the file's own numbering goes on):
#  16. The wrappers are typed: C `int` flags (`implicit`, `canonical`, `unicode`) are `Bool` and `Cint(x)` at the call; an enum is an `Int`; a `const char *`
#      string argument is `Union{Nothing,String}` (`nothing` = NULL) passed as `pointer(s)` under `GC.@preserve` (a Julia `String` is NUL terminated, and the
#      C's `value` of a scalar goes with its explicit `len`, -1 = `strlen`, as the C calls it). libyaml copies every string it is given, so the Julia String
#      need not outlive the call. `yaml_document_start_event_initialize` takes only `implicit`: yaml4pl.c always passes NULL for the version directive
#      and the two tag directive pointers (C 1134), so the wrapper passes NULL, NULL, NULL.
#  17. A libyaml struct is a raw `Ptr{Cvoid}` to `calloc`'d memory (`yaml_event_alloc`/`yaml_parser_alloc`/`yaml_emitter_alloc`; C_NULL when out of memory,
#      freed with `yaml_free`), and a field is read at its measured offset (`yaml_cev_*` for a C event, to tell it from piece 2's `yaml_event`). The C
#      reads a union member (`event->data.alias.anchor`) for a sequence- and a mapping-start event too (`store_anchor`, C 549-557): the four members share
#      offset 8, so `yaml_cev_anchor` is ONE read at 8 and the caller must call it only for an alias, scalar, sequence-start or mapping-start event.
#  18. Strings are copied out of libyaml's memory as Julia `String`s (`nothing` for NULL); the parser's and the emitter's `problem` is `libyaml`'s static
#      text, copied as well. `yaml_get_version` answers a tuple `(major, minor, patch)` where C writes three `int *`.
using LibYAML_jll: libyaml

"The libyaml error codes (`yaml_error_type_t`) that the parser and emitter put in `error`; yaml4pl.c hands them to Prolog as `yaml_error(Code, _)`."
const YAML_NO_ERROR = 0
const YAML_MEMORY_ERROR = 1
const YAML_READER_ERROR = 2
const YAML_SCANNER_ERROR = 3
const YAML_PARSER_ERROR = 4
const YAML_COMPOSER_ERROR = 5
const YAML_WRITER_ERROR = 6
const YAML_EMITTER_ERROR = 7

# `sizeof` of the three structs (gcc probe, libyaml 0.2.5, x86-64) and the field offsets yaml4pl.c reads (17).
const YAML_EVENT_SIZE = 104
const YAML_PARSER_SIZE = 480
const YAML_EMITTER_SIZE = 432
const YAML_EVENT_TYPE_OFFSET = 0               # yaml_event_t.type (enum, 4 bytes)
const YAML_EVENT_DATA_OFFSET = 8               # yaml_event_t.data (the union)
const YAML_EVENT_ANCHOR_OFFSET = 8             # data.alias.anchor = data.scalar.anchor = data.sequence_start.anchor = data.mapping_start.anchor
const YAML_EVENT_TAG_OFFSET = 16               # data.scalar.tag = data.sequence_start.tag = data.mapping_start.tag
const YAML_EVENT_SCALAR_VALUE_OFFSET = 24      # data.scalar.value (yaml_char_t *)
const YAML_EVENT_SCALAR_LENGTH_OFFSET = 32     # data.scalar.length (size_t)
const YAML_EVENT_SCALAR_PLAIN_IMPLICIT_OFFSET = 40
const YAML_EVENT_SCALAR_QUOTED_IMPLICIT_OFFSET = 44
const YAML_EVENT_SCALAR_STYLE_OFFSET = 48
const YAML_EVENT_COLLECTION_IMPLICIT_OFFSET = 24   # data.sequence_start.implicit = data.mapping_start.implicit
const YAML_EVENT_COLLECTION_STYLE_OFFSET = 28      # data.sequence_start.style = data.mapping_start.style
const YAML_EVENT_STREAM_ENCODING_OFFSET = 8        # data.stream_start.encoding
const YAML_EVENT_DOCUMENT_START_IMPLICIT_OFFSET = 32
const YAML_EVENT_DOCUMENT_END_IMPLICIT_OFFSET = 8
const YAML_PARSER_ERROR_OFFSET = 0             # yaml_parser_t.error (enum)
const YAML_PARSER_PROBLEM_OFFSET = 8           # yaml_parser_t.problem (const char *)
const YAML_EMITTER_ERROR_OFFSET = 0            # yaml_emitter_t.error (enum)
const YAML_EMITTER_PROBLEM_OFFSET = 8          # yaml_emitter_t.problem (const char *)

# PORT: packages/yaml/yaml4pl.c yaml_event_t event, yaml_parser_t parser, yaml_emitter_t emitter (stack locals), release_emitter's free (880)
# DIVERGES: see the piece A header, 17.
"A zeroed block of `size` bytes from `calloc` (C_NULL when out of memory): what a C local `yaml_event_t`/`yaml_parser_t`/`yaml_emitter_t` is before its `_initialize`."
yaml_alloc(size::Int)::Ptr{Cvoid} = Libc.calloc(1, size)

"Free a block made by `yaml_alloc` (after the matching `yaml_*_delete`); C_NULL is a no-op."
function yaml_free(p::Ptr{Cvoid})::Nothing
    Libc.free(p)
    return nothing
end

"A zeroed `yaml_event_t` (104 bytes)."
yaml_event_alloc()::Ptr{Cvoid} = yaml_alloc(YAML_EVENT_SIZE)

"A zeroed `yaml_parser_t` (480 bytes)."
yaml_parser_alloc()::Ptr{Cvoid} = yaml_alloc(YAML_PARSER_SIZE)

"A zeroed `yaml_emitter_t` (432 bytes)."
yaml_emitter_alloc()::Ptr{Cvoid} = yaml_alloc(YAML_EMITTER_SIZE)

# The NUL-terminated bytes of `s`, or NULL for `nothing` (16); the caller keeps `s` alive with `GC.@preserve`.
@inline _yaml_cstr(s::Union{Nothing, String})::Ptr{UInt8} = s === nothing ? Ptr{UInt8}(C_NULL) : pointer(s)

# A `char *` field copied out as a Julia String, `nothing` for NULL (18).
@inline function _yaml_load_cstring(p::Ptr{Cvoid}, offset::Int)::Union{Nothing, String}
    s = unsafe_load(Ptr{Ptr{UInt8}}(p + offset))
    return s == C_NULL ? nothing : unsafe_string(s)
end

@inline _yaml_load_cint(p::Ptr{Cvoid}, offset::Int)::Cint = unsafe_load(Ptr{Cint}(p + offset))

# PORT: packages/yaml/yaml4pl.c yaml_get_version_string, yaml_get_version (libyaml; no call in the C: the first-run check of evidence/R2/yaml_plan.md 2.4)
# DIVERGES: see the piece A header, 18.
"libyaml's version text, e.g. \"0.2.5\" (`yaml_get_version_string`, a static string)."
function yaml_get_version_string()::String
    return unsafe_string(ccall((:yaml_get_version_string, libyaml), Ptr{UInt8}, ()))
end

"libyaml's `(major, minor, patch)` (`yaml_get_version`)."
function yaml_get_version()::Tuple{Cint, Cint, Cint}
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    ccall((:yaml_get_version, libyaml), Cvoid, (Ref{Cint}, Ref{Cint}, Ref{Cint}), major, minor, patch)
    return (major[], minor[], patch[])
end

# PORT: packages/yaml/yaml4pl.c yaml_parse_stream (743, 749, 751), parse_document (625): yaml_parser_initialize/_set_input/_delete/_parse
# DIVERGES: see the piece A header, 17. `yaml_parser_set_input` takes the RAW handler pointer (`@cfunction`, the parse driver's piece) and its data pointer.
"Initialize the zeroed parser `parser` (yaml4pl.c `yaml_parse_stream`): 1, or 0 when out of memory."
function yaml_parser_initialize(parser::Ptr{Cvoid})::Cint
    return ccall((:yaml_parser_initialize, libyaml), Cint, (Ptr{Cvoid},), parser)
end

"Set the parser's read handler and its data pointer (yaml4pl.c `yaml_parse_stream`)."
function yaml_parser_set_input(parser::Ptr{Cvoid}, handler::Ptr{Cvoid}, data::Ptr{Cvoid})::Nothing
    ccall((:yaml_parser_set_input, libyaml), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), parser, handler, data)
    return nothing
end

"Read the next event into `event`: 1, or 0 on an error (`parser->error` and `->problem`; yaml4pl.c `parse_document`)."
function yaml_parser_parse(parser::Ptr{Cvoid}, event::Ptr{Cvoid})::Cint
    return ccall((:yaml_parser_parse, libyaml), Cint, (Ptr{Cvoid}, Ptr{Cvoid}), parser, event)
end

"Free the parser's buffers (yaml4pl.c `yaml_parse_stream`); the struct itself is freed by `yaml_free`."
function yaml_parser_delete(parser::Ptr{Cvoid})::Nothing
    ccall((:yaml_parser_delete, libyaml), Cvoid, (Ptr{Cvoid},), parser)
    return nothing
end

# PORT: packages/yaml/yaml4pl.c parse_document (716, 718, 725): yaml_event_delete
"Free the strings of a parsed or initialized event (yaml4pl.c `parse_document`); copy the strings out first."
function yaml_event_delete(event::Ptr{Cvoid})::Nothing
    ccall((:yaml_event_delete, libyaml), Cvoid, (Ptr{Cvoid},), event)
    return nothing
end

# PORT: packages/yaml/yaml4pl.c yaml_emitter_create (967, 973, 983, 990, 995), release_emitter (880, 1006): yaml_emitter_initialize/_set_output/_set_canonical/_set_unicode/_delete
# DIVERGES: see the piece A header, 16 and 17. `yaml_emitter_set_output` takes the RAW handler pointer (the emitter piece's `@cfunction`) and its data pointer.
"Initialize the zeroed emitter `emitter` (yaml4pl.c `yaml_emitter_create`): 1, or 0 when out of memory."
function yaml_emitter_initialize(emitter::Ptr{Cvoid})::Cint
    return ccall((:yaml_emitter_initialize, libyaml), Cint, (Ptr{Cvoid},), emitter)
end

"Set the emitter's write handler and its data pointer (yaml4pl.c `yaml_emitter_create`)."
function yaml_emitter_set_output(emitter::Ptr{Cvoid}, handler::Ptr{Cvoid}, data::Ptr{Cvoid})::Nothing
    ccall((:yaml_emitter_set_output, libyaml), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), emitter, handler, data)
    return nothing
end

"Set the emitter's canonical flag (yaml4pl.c `yaml_emitter_create`)."
function yaml_emitter_set_canonical(emitter::Ptr{Cvoid}, canonical::Bool)::Nothing
    ccall((:yaml_emitter_set_canonical, libyaml), Cvoid, (Ptr{Cvoid}, Cint), emitter, Cint(canonical))
    return nothing
end

"Set the emitter's unicode flag (yaml4pl.c `yaml_emitter_create`)."
function yaml_emitter_set_unicode(emitter::Ptr{Cvoid}, unicode::Bool)::Nothing
    ccall((:yaml_emitter_set_unicode, libyaml), Cvoid, (Ptr{Cvoid}, Cint), emitter, Cint(unicode))
    return nothing
end

"Free the emitter's buffers (yaml4pl.c `release_emitter`, `yaml_emitter_create`'s error exit); the struct itself is freed by `yaml_free`."
function yaml_emitter_delete(emitter::Ptr{Cvoid})::Nothing
    ccall((:yaml_emitter_delete, libyaml), Cvoid, (Ptr{Cvoid},), emitter)
    return nothing
end

# PORT: packages/yaml/yaml4pl.c emit_event (1201): yaml_emitter_emit
"Emit `event` (the emitter takes its ownership): 1, or 0 on an error (`emitter->error` and `->problem`; yaml4pl.c `emit_event`)."
function yaml_emitter_emit(emitter::Ptr{Cvoid}, event::Ptr{Cvoid})::Cint
    return ccall((:yaml_emitter_emit, libyaml), Cint, (Ptr{Cvoid}, Ptr{Cvoid}), emitter, event)
end

# PORT: packages/yaml/yaml4pl.c emit_event (1125, 1127, 1134, 1141, 1147, 1150, 1156, 1159, 1189, 1196): the ten yaml_*_event_initialize
# DIVERGES: see the piece A header, 16. Each returns 1, or 0 when out of memory or (a string argument) not valid UTF-8; `event` is a zeroed `yaml_event_t`.
"Make a STREAM-START event with `encoding` (`YAML_UTF8_ENCODING`; yaml4pl.c `emit_event`)."
function yaml_stream_start_event_initialize(event::Ptr{Cvoid}, encoding::Int)::Cint
    return ccall((:yaml_stream_start_event_initialize, libyaml), Cint, (Ptr{Cvoid}, Cint), event, encoding)
end

"Make a STREAM-END event (yaml4pl.c `emit_event`)."
function yaml_stream_end_event_initialize(event::Ptr{Cvoid})::Cint
    return ccall((:yaml_stream_end_event_initialize, libyaml), Cint, (Ptr{Cvoid},), event)
end

"Make a DOCUMENT-START event with no version and no tag directives, `implicit` as given (yaml4pl.c `emit_event`)."
function yaml_document_start_event_initialize(event::Ptr{Cvoid}, implicit::Bool)::Cint
    return ccall(
        (:yaml_document_start_event_initialize, libyaml), Cint,
        (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Cint),
        event, C_NULL, C_NULL, C_NULL, Cint(implicit)
    )
end

"Make a DOCUMENT-END event (yaml4pl.c `emit_event`)."
function yaml_document_end_event_initialize(event::Ptr{Cvoid}, implicit::Bool)::Cint
    return ccall((:yaml_document_end_event_initialize, libyaml), Cint, (Ptr{Cvoid}, Cint), event, Cint(implicit))
end

"Make a MAPPING-START event with `anchor` and `tag` (`nothing` = NULL), `implicit` and `style` (yaml4pl.c `emit_event`)."
function yaml_mapping_start_event_initialize(
        event::Ptr{Cvoid}, anchor::Union{Nothing, String}, tag::Union{Nothing, String}, implicit::Bool, style::Int
    )::Cint
    GC.@preserve anchor tag begin
        return ccall(
            (:yaml_mapping_start_event_initialize, libyaml), Cint,
            (Ptr{Cvoid}, Ptr{UInt8}, Ptr{UInt8}, Cint, Cint),
            event, _yaml_cstr(anchor), _yaml_cstr(tag), Cint(implicit), style
        )
    end
end

"Make a MAPPING-END event (yaml4pl.c `emit_event`)."
function yaml_mapping_end_event_initialize(event::Ptr{Cvoid})::Cint
    return ccall((:yaml_mapping_end_event_initialize, libyaml), Cint, (Ptr{Cvoid},), event)
end

"Make a SEQUENCE-START event with `anchor` and `tag` (`nothing` = NULL), `implicit` and `style` (yaml4pl.c `emit_event`)."
function yaml_sequence_start_event_initialize(
        event::Ptr{Cvoid}, anchor::Union{Nothing, String}, tag::Union{Nothing, String}, implicit::Bool, style::Int
    )::Cint
    GC.@preserve anchor tag begin
        return ccall(
            (:yaml_sequence_start_event_initialize, libyaml), Cint,
            (Ptr{Cvoid}, Ptr{UInt8}, Ptr{UInt8}, Cint, Cint),
            event, _yaml_cstr(anchor), _yaml_cstr(tag), Cint(implicit), style
        )
    end
end

"Make a SEQUENCE-END event (yaml4pl.c `emit_event`)."
function yaml_sequence_end_event_initialize(event::Ptr{Cvoid})::Cint
    return ccall((:yaml_sequence_end_event_initialize, libyaml), Cint, (Ptr{Cvoid},), event)
end

"Make a SCALAR event: `value` of `len` bytes (-1: up to its first NUL, as the C passes it), the two implicit flags and `style` (yaml4pl.c `emit_event`)."
function yaml_scalar_event_initialize(
        event::Ptr{Cvoid}, anchor::Union{Nothing, String}, tag::Union{Nothing, String}, value::String, len::Int,
        plain_implicit::Bool, quoted_implicit::Bool, style::Int
    )::Cint
    GC.@preserve anchor tag value begin
        return ccall(
            (:yaml_scalar_event_initialize, libyaml), Cint,
            (Ptr{Cvoid}, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}, Cint, Cint, Cint, Cint),
            event, _yaml_cstr(anchor), _yaml_cstr(tag), pointer(value), len, Cint(plain_implicit), Cint(quoted_implicit), style
        )
    end
end

"Make an ALIAS event for `anchor` (yaml4pl.c `emit_event`)."
function yaml_alias_event_initialize(event::Ptr{Cvoid}, anchor::String)::Cint
    GC.@preserve anchor begin
        return ccall((:yaml_alias_event_initialize, libyaml), Cint, (Ptr{Cvoid}, Ptr{UInt8}), event, pointer(anchor))
    end
end

# PORT: packages/yaml/yaml4pl.c parse_document (638, 715, 717, 346-356, 550, 556, 567-570, 592-595, 689): the event fields the C reads
# DIVERGES: see the piece A header, 17 and 18. `yaml_cev_anchor` is for an alias, scalar, sequence-start or mapping-start event; `yaml_cev_tag` for a scalar,
# sequence-start or mapping-start event; `yaml_cev_value` and the `scalar_*` readers for a scalar event; the `collection_*` readers for a sequence- or mapping-start event.
"The event's `type` (`YAML_*_EVENT`; yaml4pl.c `parse_document`)."
yaml_cev_type(event::Ptr{Cvoid})::Int = Int(_yaml_load_cint(event, YAML_EVENT_TYPE_OFFSET))

"The anchor of an alias, scalar, sequence-start or mapping-start event, `nothing` when it has none."
yaml_cev_anchor(event::Ptr{Cvoid})::Union{Nothing, String} = _yaml_load_cstring(event, YAML_EVENT_ANCHOR_OFFSET)

"The tag of a scalar, sequence-start or mapping-start event, `nothing` when it has none."
yaml_cev_tag(event::Ptr{Cvoid})::Union{Nothing, String} = _yaml_load_cstring(event, YAML_EVENT_TAG_OFFSET)

"The byte count of a scalar event's value (libyaml's `length`, which counts a NUL inside the text)."
yaml_cev_scalar_length(event::Ptr{Cvoid})::Int = Int(unsafe_load(Ptr{Csize_t}(event + YAML_EVENT_SCALAR_LENGTH_OFFSET)))

"The value of a scalar event, its `length` bytes copied out (`nothing` if the pointer is NULL; yaml4pl.c `put_scalar` reads `value` with `length`)."
function yaml_cev_value(event::Ptr{Cvoid})::Union{Nothing, String}
    s = unsafe_load(Ptr{Ptr{UInt8}}(event + YAML_EVENT_SCALAR_VALUE_OFFSET))
    s == C_NULL && return nothing
    return unsafe_string(s, yaml_cev_scalar_length(event))
end

"A scalar event's `plain_implicit` flag."
yaml_cev_plain_implicit(event::Ptr{Cvoid})::Bool = _yaml_load_cint(event, YAML_EVENT_SCALAR_PLAIN_IMPLICIT_OFFSET) != 0

"A scalar event's `quoted_implicit` flag."
yaml_cev_quoted_implicit(event::Ptr{Cvoid})::Bool = _yaml_load_cint(event, YAML_EVENT_SCALAR_QUOTED_IMPLICIT_OFFSET) != 0

"A scalar event's `style` (`YAML_*_SCALAR_STYLE`)."
yaml_cev_scalar_style(event::Ptr{Cvoid})::Int = Int(_yaml_load_cint(event, YAML_EVENT_SCALAR_STYLE_OFFSET))

"A sequence- or mapping-start event's `implicit` flag."
yaml_cev_collection_implicit(event::Ptr{Cvoid})::Bool = _yaml_load_cint(event, YAML_EVENT_COLLECTION_IMPLICIT_OFFSET) != 0

"A sequence- or mapping-start event's `style` (`YAML_BLOCK_SEQUENCE_STYLE`/`YAML_BLOCK_MAPPING_STYLE`)."
yaml_cev_collection_style(event::Ptr{Cvoid})::Int = Int(_yaml_load_cint(event, YAML_EVENT_COLLECTION_STYLE_OFFSET))

"A stream-start event's `encoding` (`YAML_UTF8_ENCODING`)."
yaml_cev_encoding(event::Ptr{Cvoid})::Int = Int(_yaml_load_cint(event, YAML_EVENT_STREAM_ENCODING_OFFSET))

"A document-start event's `implicit` flag."
yaml_cev_document_start_implicit(event::Ptr{Cvoid})::Bool = _yaml_load_cint(event, YAML_EVENT_DOCUMENT_START_IMPLICIT_OFFSET) != 0

"A document-end event's `implicit` flag."
yaml_cev_document_end_implicit(event::Ptr{Cvoid})::Bool = _yaml_load_cint(event, YAML_EVENT_DOCUMENT_END_IMPLICIT_OFFSET) != 0

# PORT: packages/yaml/yaml4pl.c parse_document (631-632), emit_event (1209-1210): parser->error/problem, emitter->error/problem
# DIVERGES: see the piece A header, 17 and 18.
"The parser's error code after `yaml_parser_parse` returned 0 (`YAML_*_ERROR`; yaml4pl.c `parse_document`)."
yaml_parser_error(parser::Ptr{Cvoid})::Int = Int(_yaml_load_cint(parser, YAML_PARSER_ERROR_OFFSET))

"The parser's problem text after an error, `nothing` if NULL (yaml4pl.c `parse_document`)."
yaml_parser_problem(parser::Ptr{Cvoid})::Union{Nothing, String} = _yaml_load_cstring(parser, YAML_PARSER_PROBLEM_OFFSET)

"The emitter's error code after `yaml_emitter_emit` returned 0 (`YAML_*_ERROR`; yaml4pl.c `emit_event`)."
yaml_emitter_error(emitter::Ptr{Cvoid})::Int = Int(_yaml_load_cint(emitter, YAML_EMITTER_ERROR_OFFSET))

"The emitter's problem text after an error, `nothing` if NULL (yaml4pl.c `emit_event`)."
yaml_emitter_problem(emitter::Ptr{Cvoid})::Union{Nothing, String} = _yaml_load_cstring(emitter, YAML_EMITTER_PROBLEM_OFFSET)
