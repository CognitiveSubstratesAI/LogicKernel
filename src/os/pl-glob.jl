# UPSTREAM: swipl-devel src/os/pl-glob.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# GLOB (pl-glob.c), LB2b: Unix wildcard matching (`wildcard_match/2,3`), `expand_file_name/2` and
# `directory_files/2`. The pattern is compiled into a vector of code points and control codes (the
# `matchcode` buffer of upstream, a `Vector{Int}` here) and matched by the same recursive matcher;
# strings are vectors of Unicode code points (upstream walks UTF-8 bytes with `PL_utf8_code_point`), read as
# 0 beyond their end (upstream reads the terminating NUL).

# PORT: pl-glob.c CBASE
const GLOB_CBASE = 0x80000000
# PORT: pl-glob.c ANY
const GLOB_ANY = GLOB_CBASE + 1
# PORT: pl-glob.c STAR
const GLOB_STAR = GLOB_CBASE + 2
# PORT: pl-glob.c ALT
const GLOB_ALT = GLOB_CBASE + 3
# PORT: pl-glob.c JMP
const GLOB_JMP = GLOB_CBASE + 4
# PORT: pl-glob.c ANYOF
const GLOB_ANYOF = GLOB_CBASE + 5
# PORT: pl-glob.c ANYRANGE
const GLOB_ANYRANGE = GLOB_CBASE + 6
# PORT: pl-glob.c EXIT
const GLOB_EXIT = GLOB_CBASE + 7
# PORT: pl-glob.c NOCURL
const GLOB_NOCURL = 0
# PORT: pl-glob.c CURL
const GLOB_CURL = 1
# PORT: pl-glob.c M_IGNCASE
const M_IGNCASE = 0x01

# ORIGINAL (LB2b): the code points of `s` up to the first NUL, the C string upstream compiles and matches.
_glob_codes(s::String)::Vector{Int} = Int[Int(c) for c in Iterators.takewhile(!=('\0'), s)]

# ORIGINAL (LB2b): the code point at the 1-based index `i`, 0 beyond the end (the NUL of the C string).
_glob_at(b::Vector{Int}, i::Int)::Int = (1 <= i <= length(b)) ? b[i] : 0

# PORT: pl-glob.c makeLowerW
# DIVERGES: `lowercase(::Char)` (Julia's simple Unicode case mapping) stands in for `PL_tolower`
# (pl-umap.c), as in `utf8_path_lwr`.
_glob_lower(c::Int)::Int = c == 0 ? 0 : Int(lowercase(Char(c)))

# PORT: pl-glob.c compile_pattern
# DIVERGES: `p` is the vector of code points of the pattern and `pos` the 1-based index of the next one;
# returns the index after the part compiled, or `nothing` after raising the syntax error. `Output` appends to
# `out`; `Here()` is `length(out)` and `CodeAt(o)` is `out[o + 1]`. The reserved-character check
# (a code point of `CBASE` or more) cannot arise: a code point is below 0x110000.
function compile_pattern(
    ld::PL_local_data, out::Vector{Int}, p::Vector{Int}, pos::Int, curl::Int, mflags::Int
)::Union{Nothing, Int}
    while true
        c = _glob_at(p, pos)
        pos += 1
        if c == 0
            pos -= 1
        elseif c == Int('\\')
            c2 = _glob_at(p, pos)
            pos += 1
            push!(out, c2 == 0 ? c : c2)
            c2 == 0 || continue
        elseif c == Int('?')
            push!(out, GLOB_ANY)
            continue
        elseif c == Int('*')
            push!(out, GLOB_STAR)
            continue
        elseif c == Int('[')
            push!(out, GLOB_ANYOF)
            mapsize_at = length(out)
            push!(out, 0)
            while true
                c = _glob_at(p, pos)
                pos += 1
                if c == 0
                    PL_error(ld, "", 0, "", ERR_SYNTAX, "Unmatched '['")
                    return nothing
                elseif c == Int('\\')
                    c2 = _glob_at(p, pos)
                    pos += 1
                    if c2 == 0
                        PL_error(ld, "", 0, "", ERR_SYNTAX, "Unmatched '['")
                        return nothing
                    end
                    push!(out, c2)
                elseif c == Int(']')
                    out[mapsize_at + 1] = length(out) - (mapsize_at + 1)
                    break
                else
                    ce = _glob_at(p, pos + 1)
                    if _glob_at(p, pos) == Int('-') && ce != Int(']')
                        push!(out, GLOB_ANYRANGE)
                        push!(out, c)
                        push!(out, ce)
                        pos += 2
                    else
                        push!(out, c)
                    end
                end
            end
            continue
        elseif c == Int('{')
            aj = -1
            ai = 0
            while true
                push!(out, GLOB_ALT)
                ai = length(out)
                push!(out, 0)
                pos2 = compile_pattern(ld, out, p, pos, GLOB_CURL, mflags)
                pos2 === nothing && return nothing
                pos = pos2
                aj > 0 && (out[aj + 1] = length(out) - aj)
                if _glob_at(p, pos) == Int(',')
                    push!(out, GLOB_JMP)
                    aj = length(out)
                    push!(out, 0)
                    out[ai + 1] = length(out) - ai
                    push!(out, GLOB_ALT)
                    ai = length(out)
                    push!(out, 0)
                    pos += 1
                elseif _glob_at(p, pos) == Int('}')
                    pos += 1
                    break
                else
                    PL_error(ld, "", 0, "", ERR_SYNTAX, "Unmatched '{'")
                    return nothing
                end
            end
            continue
        else
            if (c == Int('}') || c == Int(',')) && curl == GLOB_CURL
                pos -= 1
                return pos
            end
            (mflags & M_IGNCASE) != 0 && (c = _glob_lower(c))
            push!(out, c)
            continue
        end
        push!(out, GLOB_EXIT)
        return pos
    end
end

# PORT: pl-glob.c compilePattern
# DIVERGES: returns the compiled pattern, or `nothing` after raising the syntax error.
"The compiled form of the wildcard pattern `p` (a vector of code points), or `nothing` (pl-glob.c)."
function compilePattern(
    ld::PL_local_data, p::Vector{Int}, flags::Int
)::Union{Nothing, Vector{Int}}
    out = Int[]
    compile_pattern(ld, out, p, 1, GLOB_NOCURL, flags) === nothing && return nothing
    return out
end

# PORT: pl-glob.c match_pattern
# DIVERGES: `p` is the compiled pattern with the 1-based index `pi` of the next code, `s` the code points of
# the string with the 1-based index `si`; the jumps `p += *p` are relative to the cell, as in C.
function match_pattern(p::Vector{Int}, pi::Int, s::Vector{Int}, si::Int, flags::Int)::Bool
    while true
        c = p[pi]
        pi += 1
        if c == GLOB_EXIT
            return _glob_at(s, si) == 0
        elseif c == GLOB_ANY                                    # ?
            _glob_at(s, si) == 0 && return false
            si += 1
        elseif c == GLOB_ANYOF                                  # [...]
            sz = p[pi]
            pi += 1
            anyend = pi + sz
            c2 = _glob_at(s, si)
            si += 1
            (flags & M_IGNCASE) != 0 && (c2 = _glob_lower(c2))
            found = false
            while pi < anyend
                if p[pi] == GLOB_ANYRANGE
                    if c2 >= p[pi + 1] && c2 <= p[pi + 2]
                        found = true
                        break
                    end
                    pi += 3
                else
                    if p[pi] == c2
                        found = true
                        break
                    end
                    pi += 1
                end
            end
            found || return false
            pi = anyend
        elseif c == GLOB_STAR                                   # *
            while true
                match_pattern(p, pi, s, si, flags) && return true
                c2 = _glob_at(s, si)
                si += 1
                c2 == 0 && break
            end
            return false
        elseif c == GLOB_JMP                                    # { ... }
            pi += p[pi]
        elseif c == GLOB_ALT
            match_pattern(p, pi + 1, s, si, flags) && return true
            pi += p[pi]
        else                                                    # character
            c2 = _glob_at(s, si)
            si += 1
            (flags & M_IGNCASE) != 0 && (c2 = _glob_lower(c2))
            c == c2 || return false
        end
    end
end

# PORT: pl-glob.c matchPattern
"Does the compiled pattern match the string `s` (a vector of code points) (pl-glob.c)."
matchPattern(s::Vector{Int}, cbuf::Vector{Int}, flags::Int)::Bool =
    match_pattern(cbuf, 1, s, 1, flags)

# PORT: pl-glob.c wildcard_options
const wildcard_options = (PL_option_t(:case_sensitive, OPT_BOOL),)

# PORT: pl-glob.c wildcard_match
# DIVERGES: `options` is `nothing` for upstream's NULL.
"""
    wildcard_match(ld, pattern, string, options) -> Bool

Match the text of the term reference `string` against the wildcard pattern of `pattern` (`?`, `*`, `[a-z]`,
`{p1,p2}`, `\\` escapes), the option `case_sensitive(Bool)` of `options` (pl-glob.c).
"""
function wildcard_match(
    ld::PL_local_data{T}, pattern::term_t, string::term_t, options::Union{Nothing, term_t}
)::Bool where {T}
    mflags = 0
    case_sensitive = true
    if options !== nothing
        vals = PL_scan_options(ld, options, 0, "wildcard_option", wildcard_options)
        vals === nothing && return false
        case_sensitive = vals[1] !== false
    end
    case_sensitive || (mflags |= M_IGNCASE)
    ptxt = PL_get_text(ld, pattern, CVT_ALL | CVT_EXCEPTION)
    ptxt === nothing && return false
    stxt = PL_get_text(ld, string, CVT_ALL | CVT_EXCEPTION)
    stxt === nothing && return false
    buf = compilePattern(ld, _glob_codes(text_string(ptxt)), mflags)
    buf === nothing && return false
    return matchPattern(_glob_codes(text_string(stxt)), buf, mflags)
end

# PORT: pl-glob.c wildcard_match as pl_wildcard_match2_va
# (PRED_IMPL("wildcard_match", 2, wildcard_match, 0))
"`wildcard_match(+Pattern, +String)`: String matches the wildcard Pattern (pl-glob.c)."
function pl_wildcard_match2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return wildcard_match(ld, PL__t0, PL__t0 + 1, nothing) ? FTRUE : FFALSE
end

# PORT: pl-glob.c wildcard_match as pl_wildcard_match3_va
# (PRED_IMPL("wildcard_match", 3, wildcard_match, 0))
"`wildcard_match(+Pattern, +String, +Options)`: as wildcard_match/2, option `case_sensitive(Bool)` (pl-glob.c)."
function pl_wildcard_match3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return wildcard_match(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE
end
