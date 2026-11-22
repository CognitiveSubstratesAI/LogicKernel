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
# `get_value` (the emitter side, `implicit_tag`) are the later pieces. Nothing here has run (no Julia process was started).
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
