# UPSTREAM: swipl-devel src/pl-dwim.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2006, University of Amsterdam
#
# DO WHAT I MEAN (pl-dwim.c), since DWIM1: the string comparison the "unknown procedure" message uses to name
# near-miss predicates — `dwim_match/3` and `'$dwim_predicate'/2`. `dwim_match/2` is Prolog (boot/syspred.pl),
# `'$similar_module'/2` and the walk along the super-modules are Prolog (boot/dwim.pl): this file holds the C only.
#
# Two strings are meant identical iff they ARE identical, one character differs (spy == spu), one is inserted or
# deleted (debug == deug), two adjacent characters are transposed (trace == tarce), the sub-words are separated
# wrong (aB == a_b == ab) or two sub-words are transposed (exists_file == file_exists).
#
# A C string is a NUL-terminated `Vector{UInt8}` and a C pointer into it a 1-based `Int` index, so `s[0]` is
# `s[i]`, `s[1]` is `s[i + 1]` and `&s[1]` is `i + 1`. `char` is signed in C and the `is*` macros answer false for
# a byte of 0x80 or more (src/os/pl-ctype.jl), as a `UInt8` does here.

# ORIGINAL (DWIM1): the `streq(s, q)` macro of pl-incl.h (`strcmp(s, q) == 0`) over two C strings and their indexes.
"Whether the C strings `s1` from `i1` and `s2` from `i2` are equal up to their NULs (`streq`, pl-incl.h)."
function _dwim_streq(s1::Vector{UInt8}, i1::Int, s2::Vector{UInt8}, i2::Int)::Bool
    while true
        c1 = s1[i1]
        c1 == s2[i2] || return false
        c1 == 0x00 && return true
        i1 += 1
        i2 += 1
    end
end

# ORIGINAL (DWIM1): libc's `strlen` over a C string from index `i`.
"The number of bytes of the C string `s` from index `i` to its NUL (`strlen`)."
function _dwim_strlen(s::Vector{UInt8}, i::Int)::Int
    n = 0
    while s[i + n] != 0x00
        n += 1
    end
    return n
end

# PORT: pl-dwim.c oneTypo
# (swipl-devel cbf4e189, src/pl-dwim.c:52-57)
"Whether the C strings differ in their first character only (pl-dwim.c)."
function oneTypo(s1::Vector{UInt8}, i1::Int, s2::Vector{UInt8}, i2::Int)::Bool
    if s1[i1 + 1] == 0x00 || _dwim_streq(s1, i1 + 1, s2, i2 + 1)    # s1[1] == EOS || streq(&s1[1], &s2[1])
        return true
    end
    return false
end

# PORT: pl-dwim.c twoTransposed
# (swipl-devel cbf4e189, src/pl-dwim.c:59-65)
"Whether the C strings differ in their first two characters, transposed (pl-dwim.c)."
function twoTransposed(s1::Vector{UInt8}, i1::Int, s2::Vector{UInt8}, i2::Int)::Bool
    if s1[i1 + 1] != 0x00 && s1[i1] == s2[i2 + 1] && s1[i1 + 1] == s2[i2] &&
        (s1[i1 + 2] == 0x00 || _dwim_streq(s1, i1 + 2, s2, i2 + 2))
        return true
    end
    return false
end

# PORT: pl-dwim.c oneInserted
# (swipl-devel cbf4e189, src/pl-dwim.c:67-72)
"Whether `s2` is `s1` with one character inserted at its start (pl-dwim.c)."
function oneInserted(s1::Vector{UInt8}, i1::Int, s2::Vector{UInt8}, i2::Int)::Bool
    if _dwim_streq(s1, i1, s2, i2 + 1)
        return true
    end
    return false
end

# PORT: pl-dwim.c differentSeparated
# (swipl-devel cbf4e189, src/pl-dwim.c:74-99)
"Whether the C strings are the same words, written with a different separation: `_` or a change to upper case (pl-dwim.c)."
function differentSeparated(s1::Vector{UInt8}, s2::Vector{UInt8})::Bool
    i1 = 1
    i2 = 1
    if s1[i1] != s2[i2] || s1[i1] == 0x00                   # *s1 != *s2 || *s1 == EOS
        return false
    end

    i1 += 1
    i2 += 1
    c1 = Int(s1[i1])                                        # c1 = *++s1, c2 = *++s2
    c2 = Int(s2[i2])
    while c1 != 0 && c1 == c2
        i1 += 1
        c1 = Int(s1[i1])
        if c1 == Int('_')                                   # if ((c1 = *++s1) == '_')
            i1 += 1
            c1 = Int(s1[i1])
        else
            if isLower(Int(s1[i1 - 1])) && isUpper(c1)
                c1 = makeLower(c1)
            end
        end
        i2 += 1
        c2 = Int(s2[i2])
        if c2 == Int('_')                                   # if ((c2 = *++s2) == '_')
            i2 += 1
            c2 = Int(s2[i2])
        else
            if isLower(Int(s2[i2 - 1])) && isUpper(c2)
                c2 = makeLower(c2)
            end
        end
    end
    if c1 == 0 && c2 == 0                                   # c1 == EOS && c2 == EOS
        return true
    end
    return false
end

# PORT: pl-dwim.c subWord
# (swipl-devel cbf4e189, src/pl-dwim.c:101-121)
# DIVERGES(representation): C stack buffer, overflow for >1023 bytes (`store` is a growing vector, NUL-terminated).
"Copy the sub-word of the C string `s` at index `i` into `store` (first character lower-cased); the index after it (pl-dwim.c)."
function subWord(s::Vector{UInt8}, i::Int, store::Vector{UInt8})::Int
    resize!(store, 0)
    push!(store, UInt8(makeLower(Int(s[i]))))               # *store++ = makeLower(*s)
    i += 1

    while true
        if s[i] == 0x00                                     # *s == EOS
            push!(store, 0x00)
            return i
        end
        if s[i] == UInt8('_')
            push!(store, 0x00)
            return i + 1
        end
        if isLower(Int(s[i - 1])) && isUpper(Int(s[i]))
            push!(store, 0x00)
            return i
        end
        push!(store, s[i])                                  # *store++ = *s++
        i += 1
    end
end

# PORT: pl-dwim.c subwordsTransposed
# (swipl-devel cbf4e189, src/pl-dwim.c:123-143)
# DIVERGES(representation): C stack buffer, overflow for >1023 bytes (the four sub-word buffers are vectors).
"Whether the C strings are made of the same sub-words, two of them swapped (pl-dwim.c)."
function subwordsTransposed(s1::Vector{UInt8}, s2::Vector{UInt8})::Bool
    sw1a = UInt8[]
    sw1b = UInt8[]
    sw2a = UInt8[]
    sw2b = UInt8[]
    i1 = 1
    i2 = 1

    while s1[i1] != 0x00 && s2[i2] != 0x00                  # while(*s1 && *s2)
        i1 = subWord(s1, i1, sw1a)
        i2 = subWord(s2, i2, sw2a)
        if !_dwim_streq(sw1a, 1, sw2a, 1)
            if s1[i1] == 0x00 || s2[i2] == 0x00
                return false
            end
            i1 = subWord(s1, i1, sw1b)
            i2 = subWord(s2, i2, sw2b)
            if !_dwim_streq(sw1a, 1, sw2b, 1) || !_dwim_streq(sw1b, 1, sw2a, 1)
                return false
            end
        end
    end
    if s1[i1] == 0x00 && s2[i2] == 0x00
        return true
    end
    return false
end

# PORT: pl-dwim.c dwimMatch
# (swipl-devel cbf4e189, src/pl-dwim.c:146-171)
# DIVERGES: the answer is the kind as a `Symbol` (`equal`, `mismatched_char`, `transposed_char`, `inserted_char`,
# `separated`, `transposed_word`), where upstream's is the atom `ATOM_*` or 0; `nothing` is the failure.
"How the C strings `str1` and `str2` match in the DWIM sense, as the name of the kind, or `nothing` (pl-dwim.c)."
function dwimMatch(str1::Vector{UInt8}, str2::Vector{UInt8})::Union{Nothing, Symbol}
    cl = 0
    s1 = 1
    s2 = 1

    while str1[s1] != 0x00 && str1[s1] == str2[s2]          # delete common part
        s1 += 1
        s2 += 1
        cl += 1
    end
    l2 = _dwim_strlen(str2, s2)
    l1 = _dwim_strlen(str1, s1)

    if abs(l1 - l2) > 5                                     # speed up a bit
        return nothing
    end

    if l1 == 0 && l2 == 0
        return :equal
    end
    if cl + l1 < 3 || cl + l2 < 3
        return nothing
    end
    if l1 == l2 && oneTypo(str1, s1, str2, s2)
        return :mismatched_char
    end
    if l1 == l2 && twoTransposed(str1, s1, str2, s2)
        return :transposed_char
    end
    if (l2 == l1 + 1 && oneInserted(str1, s1, str2, s2)) ||
        (l1 == l2 + 1 && oneInserted(str2, s2, str1, s1))
        return :inserted_char
    end
    if differentSeparated(str1, str2)
        return :separated
    end
    if subwordsTransposed(str1, str2)
        return :transposed_word
    end

    return nothing
end

# ORIGINAL (DWIM1): `PL_get_chars(t, &s, CVT_ALL|BUF_STACK)` — the text of an atom, string, number or code list as
# the bytes of a C string: ISO Latin-1 (no `REP_*` flag), the string ending at its first NUL. A term that is no
# text answers `nothing`, and so does a character above 0xFF (`PL_demote_text`, os/pl-text.c): both silent, as
# there is no `CVT_EXCEPTION` flag.
"The Latin-1 bytes of the text the term reference `t` holds (`CVT_ALL`), NUL-terminated, or `nothing`."
function _dwim_chars(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Vector{UInt8}} where {T}
    txt = PL_get_text(ld, t, CVT_ALL)
    txt === nothing && return nothing
    b = UInt8[]
    for c in text_string(txt)
        UInt32(c) > 0xff && return nothing
        push!(b, UInt8(c))
    end
    i = findfirst(==(0x00), b)
    i === nothing || resize!(b, i - 1)
    push!(b, 0x00)
    return b
end

# ORIGINAL (DWIM1): `stringAtom(a)` of pl-atom.h — the name of the atom as a C string. An atom of ISO Latin-1
# characters is that text; a wide-character atom is a `wchar_t` array that the C code reads as a `char` string:
# four bytes a character (UTF-32LE, Linux), cut at the first NUL.
# (swipl's answers on rows t32 and t33 of test_dwim_swipl.pl agree with this reading.)
"The name of the atom `a` as the bytes `stringAtom` gives a C reader, NUL-terminated."
function _dwim_stringAtom(a::T)::Vector{UInt8} where {T}
    s = sym_text(a)
    wide = false
    for c in s
        UInt32(c) > 0xff && (wide = true)
    end
    b = UInt8[]
    for c in s
        u = UInt32(c)
        if wide
            push!(b, UInt8(u & 0xff), UInt8((u >> 8) & 0xff))
            push!(b, UInt8((u >> 16) & 0xff), UInt8(u >> 24))
        else
            push!(b, UInt8(u))
        end
    end
    i = findfirst(==(0x00), b)
    i === nothing || resize!(b, i - 1)
    push!(b, 0x00)
    return b
end

# ORIGINAL (DWIM1): `PL_get_functor(t, &f)` as pl-fli.c has it: the functor of a compound, or of an atom that is
# text or a reserved symbol (`[]`); a number, a string or a variable has none. (`_cp_get_functor`, src/pl-proc.jl,
# refuses `[]`, and the kernel's `PL_get_functor` reads the functor of any word that is no compound.)
"The `(name, arity)` the term reference `t` names as `PL_get_functor` reads it, or `nothing`."
function _dwim_get_functor(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    PL_is_compound(ld, t) && return PL_get_functor(ld, t)
    a = PL_get_atom(ld, t)
    a === nothing && return nothing
    (isTextAtom(a) || is_reserved_symbol(a)) || return nothing
    return PL_get_functor(ld, t)
end

# PORT: pl-dwim.c pl_dwim_match
# (swipl-devel cbf4e189, src/pl-dwim.c:178-191)
# (FRG("dwim_match", 3, pl_dwim_match, 0), pl-ext.c:155)
"`dwim_match(+Atom1, +Atom2, -Difference)`: how two texts match in the DWIM sense (pl-dwim.c)."
function pl_dwim_match(
    ld::PL_local_data{T}, a1::term_t, a2::term_t, mm::term_t
)::foreign_t where {T}
    s1 = _dwim_chars(ld, a1)
    s1 === nothing && return FFALSE
    s2 = _dwim_chars(ld, a2)
    s2 === nothing && return FFALSE
    type = dwimMatch(s1, s2)
    type === nothing && return FFALSE
    return PL_unify_atom(ld, mm, mk_sym(T, type)) ? FTRUE : FFALSE
end

# PORT: pl-dwim.c pl_dwim_predicate
# (swipl-devel cbf4e189, src/pl-dwim.c:199-244)
# (FRG("\$dwim_predicate", 2, pl_dwim_predicate, NDET), pl-ext.c:156)
# DIVERGES: as `pl_current_predicate` (src/pl-proc.jl): the state is a record of the local data's pool
# (`ld.cur_pred_enums`), its index the `REDO_PTR` context; the procedures are the keys of the module's table at the
# first call, in its order (upstream's hash order), each looked up again when its turn comes. The cut is answered
# before the term reference `head` is made (a cut call has all arguments 0).
"`'\$dwim_predicate'(+Term, -Dwim)`: the predicates of the module `Term` names that match its name in the DWIM sense (pl-dwim.c)."
function pl_dwim_predicate(
    ld::PL_local_data{T}, pred::term_t, dwim::term_t, ctx::control_t{T}
)::foreign_t where {T}
    pool = ld.cur_pred_enums
    ctl = PL_foreign_control(ctx)
    if ctl == FRG_CUTTED                                    # e = ForeignContextPtr(h); freeTableEnum(e)
        free_foreign_state!(pool, PL_foreign_context_address(ctx))
        return FTRUE
    end

    gd = _query_gd(ld)
    head = PL_new_term_ref(ld)

    ok, mi = PL_strip_module(gd, ld, pred, 0, head)
    ok || return FFALSE
    m = gd.modules[mi]
    fdef = _dwim_get_functor(ld, head)
    fdef === nothing && return FFALSE                       # silent: leave errors for later

    if ctl == FRG_FIRST_CALL
        idx = alloc_foreign_state!(pool)                    # e = newTableEnumWP(module->procedures)
        e = pool.states[idx]
        resize!(e.keys, 0)
        append!(e.keys, keys(m.procedures))
        e.next = 1
    else                                                    # FRG_REDO: e = ForeignContextPtr(h)
        idx = PL_foreign_context_address(ctx)
        e = pool.states[idx]
    end

    while e.next <= length(e.keys)                          # advanceTableEnum(e, NULL, &val)
        key = e.keys[e.next]
        e.next += 1
        proc = get(m.procedures, key, nothing)
        proc === nothing && continue
        def = proc.definition
        name = _dwim_stringAtom(def.name)                   # name = stringAtom(def->functor->name)

        if dwimMatch(_dwim_stringAtom(fdef[1]), name) !== nothing &&
            isDefinedProcedure(gd, proc) &&
            (name[1] != UInt8('$') || SYSTEM_MODE(ld))
            if !PL_unify_functor(ld, dwim, def.name, def.arity)
                continue
            end

            return PL_retry_address(idx)                    # ForeignRedoPtr(e)
        end
    end

    free_foreign_state!(pool, idx)                          # freeTableEnum(e)
    return FFALSE
end
