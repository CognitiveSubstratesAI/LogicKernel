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
function yaml_decode_event(ld::PL_local_data{T}, Event::term_t)::Union{Nothing, yaml_event} where {T}
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
function yaml_murmur_hash_aligned2(key::AbstractVector{UInt8}, len::Int, seed::UInt32)::UInt32
    m = 0x5bd1e995
    r = 24
    h = seed ⊻ (len % UInt32)
    i = 1
    while len >= 4
        k = UInt32(key[i]) | (UInt32(key[i + 1]) << 8) | (UInt32(key[i + 2]) << 16) | (UInt32(key[i + 3]) << 24)
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
function yaml_add_anchor(ld::PL_local_data{T}, t::yaml_htable, name::String, value::term_t)::Bool where {T}
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
    ld::PL_local_data{T}, anchors::Union{Nothing, yaml_htable}, node::term_t, anchor::Union{Nothing, String}
)::Tuple{Bool, Union{Nothing, yaml_htable}} where {T}
    anchor === nothing && return (true, anchors)
    anchors === nothing && (anchors = yaml_new_anchor_table())
    return (yaml_add_anchor(ld, anchors, anchor, node), anchors)
end
