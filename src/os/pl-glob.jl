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

# PORT: pl-glob.c isspecial
"Is the byte `c` one of the wildcard characters `[`, `{`, `?`, `*` (pl-glob.c)."
_glob_isspecial(c::UInt8)::Bool =
    c == UInt8('[') || c == UInt8('{') || c == UInt8('?') || c == UInt8('*')

# PORT: pl-glob.c un_escape
# DIVERGES: returns the bytes of `b` from the 1-based `from` up to, not including, `to` as a `String`, a `\`
# before a wildcard or `\` removed; `from[1]` is read from the whole of `b`, 0 beyond it.
"The text of `b[from:to-1]` with the `\\` escapes of wildcard characters removed (pl-glob.c)."
function un_escape(b::Vector{UInt8}, from::Int, to::Int)::String
    at(i) = (1 <= i <= length(b)) ? b[i] : 0x00
    out = UInt8[]
    while from < to
        if at(from) == UInt8('\\') && (_glob_isspecial(at(from + 1)) || at(from + 1) == UInt8('\\'))
            from += 1
        end
        push!(out, at(from))
        from += 1
    end
    return String(out)
end

# PORT: pl-glob.c utf8_exists_file
# DIVERGES: the names are UTF-8 `String`s, which is `REP_FN` in a UTF-8 locale: no conversion.
"Does the file `name` exist (pl-glob.c)."
utf8_exists_file(name::String)::Bool = AccessFile(name, ACCESS_EXIST)

# PORT: pl-glob.c expand
# DIVERGES: returns the list of names found, or `nothing` after raising the syntax error of the pattern; the
# `glob_info` buffers `files`/`strings` are one vector of `String`s, valid between `start` and `fend` as in
# upstream; `opendir`/`readdir` is `readdir(dir; sort=false)` with the entries `.` and `..` put in front (libuv
# leaves them out; the result is sorted after, so only the set matters); a directory that cannot be opened is
# skipped; a name that is not valid UTF-8 is skipped; `PL_handle_signals` is not called.
"""
    expand(ld, pattern) -> Vector{String} or nothing

The files that match the wildcard `pattern`, directory segment by directory segment, unsorted (pl-glob.c).
"""
function expand(ld::PL_local_data, pattern::String)::Union{Nothing, Vector{String}}
    mflags = truePrologFlag(ld, PLFLAG_FILE_CASE) ? 0 : M_IGNCASE
    pat = Vector{UInt8}(codeunits(pattern))
    at(i) = (1 <= i <= length(pat)) ? pat[i] : 0x00
    files = String[""]                                          # utf8_add_path("", info)
    start = 0
    fend = 1
    pos = 1
    while true
        s = pos
        head = pos
        while true
            c = at(s)
            s += 1
            if c == 0x00
                if s > pos                                      # something left and expanded
                    prefix = un_escape(pat, pos, s - 1)
                    prefix_len = ncodeunits(prefix)
                    last = fend
                    while start < last
                        entry = files[start + 1]
                        plen = ncodeunits(entry)
                        if plen + prefix_len + 2 <= PATH_MAX
                            path = entry
                            if !isempty(prefix) && plen > 0 && codeunits(path)[plen] != UInt8('/')
                                path *= "/"
                            end
                            path *= prefix
                            if last == 1 || utf8_exists_file(path)
                                push!(files, path)
                                fend += 1
                            end
                        end
                        start += 1
                    end
                end
                return files[(start + 1):fend]
            elseif c == UInt8('[') || c == UInt8('{') || c == UInt8('?') || c == UInt8('*')
                break                                           # meta characters: expand
            elseif c == UInt8('\\') && _glob_isspecial(at(s))
                s += 1
            elseif c == UInt8('/')
                head = s
            end
        end
        tail = s
        while at(tail) != 0x00 && at(tail) != UInt8('/')
            tail += 1
        end
        #  ..../meta*path/....
        #       ^        ^
        #     head     tail
        prefix = un_escape(pat, pos, head)
        patbuf = un_escape(pat, head, tail)
        prefix_len = ncodeunits(prefix)
        cp = compilePattern(ld, _glob_codes(patbuf), mflags)
        cp === nothing && return nothing                        # syntax error
        dot = startswith(patbuf, '.')                           # do dots as well
        last = fend
        while start < last
            current = files[start + 1]
            clen = ncodeunits(current)
            start += 1
            clen + prefix_len + 1 > PATH_MAX && continue
            path = current * prefix
            names = try
                readdir(isempty(path) ? "." : OsPath(path); sort=false)
            catch e
                e isa Base.IOError || rethrow()
                continue
            end
            if !isempty(path) && codeunits(path)[end] != UInt8('/')
                path *= "/"
            end
            for name in vcat([".", ".."], names)
                isvalid(name) || continue
                if (dot || codeunits(name)[1] != UInt8('.')) &&
                    matchPattern(_glob_codes(name), cp, mflags)
                    if ncodeunits(path) + ncodeunits(name) + 1 < PATH_MAX
                        push!(files, path * name)
                        fend += 1
                    end
                end
            end
        end
        pos = tail
        at(pos) == UInt8('/') && (pos += 1)
    end
end

# PORT: pl-glob.c utf8casecmp
# DIVERGES: compares the code points of two `String`s, `lowercase(::Char)` for `makeLowerW`.
"Compare two names ignoring case: negative, zero or positive (pl-glob.c)."
function utf8casecmp(s1::String, s2::String)::Int
    a = _glob_codes(s1)
    b = _glob_codes(s2)
    i = 1
    while i <= length(a) && i <= length(b)
        c1 = _glob_lower(a[i])
        c2 = _glob_lower(b[i])
        c1 != c2 && return c1 - c2
        i += 1
    end
    return (i <= length(a) && i <= length(b)) ? 0 : (i <= length(a) ? 1 : -1)
end

# PORT: pl-glob.c compareBagEntries, sort_expand
# DIVERGES: sorts the vector of names; `strcmp` is the byte order of `isless(::String, ::String)`.
"Sort the names `expand` found: bytewise when `file_name_case_handling` is case sensitive, else ignoring case (pl-glob.c)."
function sort_expand(ld::PL_local_data, files::Vector{String})::Vector{String}
    if truePrologFlag(ld, PLFLAG_FILE_CASE)
        return sort(files)
    end
    return sort(files; lt=(a, b) -> utf8casecmp(a, b) < 0)
end

# PORT: pl-glob.c expand_file_name as pl_expand_file_name2_va
# (PRED_IMPL("expand_file_name", 2, expand_file_name, 0))
"`expand_file_name(+Wildcard, -List)`: the sorted list of files matching the pattern, variables expanded (pl-glob.c)."
function pl_expand_file_name2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    txt = PL_get_text(ld, PL__t0, CVT_ALL | CVT_EXCEPTION)
    txt === nothing && return FFALSE
    s = text_string(txt)
    if ncodeunits(s) > PATH_MAX - 1
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
        return FFALSE
    end
    spec = expandVars(ld, s)
    spec === nothing && return FFALSE
    found = expand(ld, spec)
    found === nothing && return FFALSE
    l = PL_copy_term_ref(ld, PL__t0 + 1)
    head = PL_new_term_ref(ld)
    for e in sort_expand(ld, found)
        PL_unify_list(ld, l, head, l) || return FFALSE
        _unify_atom_chars(ld, head, e) || return FFALSE
    end
    return PL_unify_nil(ld, l) ? FTRUE : FFALSE
end

# PORT: pl-glob.c directory_files as pl_directory_files2_va
# (PRED_IMPL("directory_files", 2, directory_files, 0))
# DIVERGES: the entries `.` and `..` come first, then the entries `readdir(dir; sort=false)` gives (upstream: the
# order `readdir(3)` gives); `PL_handle_signals` is not called.
"`directory_files(+Dir, -Files)`: the entries of the directory as a list of atoms (pl-glob.c)."
function pl_directory_files2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    dname = PL_get_file_name(ld, A1, Int(PL_FILE_READ | PL_FILE_OSPATH))
    dname === nothing && return FFALSE
    names = try
        readdir(dname; sort=false)
    catch e
        e isa Base.IOError || rethrow()
        rc = PL_error(
            ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :open), mk_sym(T, :directory),
            A1, -Int(e.code)
        )
        return rc ? FTRUE : FFALSE
    end
    tail = PL_copy_term_ref(ld, A2)
    head = PL_new_term_ref(ld)
    for e in vcat([".", ".."], names)
        PL_put_variable(ld, head)
        PL_unify_list(ld, tail, head, tail) || return FFALSE
        _unify_atom_chars(ld, head, e) || return FFALSE
    end
    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# PORT: pl-glob.c BeginPredDefs as PL_predicates_from_glob
"pl-glob.c's registration table (`BeginPredDefs(glob)`)."
const PL_predicates_from_glob = (
    PL_extension("expand_file_name", 2, pl_expand_file_name2_va, PL_FA_VARARGS),
    PL_extension("wildcard_match", 2, pl_wildcard_match2_va, PL_FA_VARARGS),
    PL_extension("wildcard_match", 3, pl_wildcard_match3_va, PL_FA_VARARGS),
    PL_extension("directory_files", 2, pl_directory_files2_va, PL_FA_VARARGS),
)
