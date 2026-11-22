# UPSTREAM: swipl-devel src/pl-rec.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-rec.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect.
# RECORDED TERMS (pl-rec.c), exactly these (and, since R2 F1a, the C interface over them, pl-fli.c's
# `PL_record`, `PL_recorded`, `PL_erase` and `PL_duplicate_record`, src/pl-fli.jl): `compileTermToHeap` — a term taken off the stacks, so
# that it survives backtracking — and `copyRecordToGlobal` — the term put back, its variables
# fresh. Their first caller is findall/3 (src/pl-bag.jl): an answer is recorded, the goal is
# backtracked into, and the answers are put back when it has no more.
#
# AS UPSTREAM (L1f f1a). `compile_term_to_heap` writes the term's CELLS as a byte code — a variable
# as its number among the term's variables, an atom or a functor as its word, a small integer as its
# value, a compound met again (a cycle, or a subterm met twice) as `PL_REC_CYCLE` and the offset of
# its first copy — with `gsize`, the global cells the copy takes, and `nvars`. `copy_record` lays
# the code out in ONE block of `gsize` cells at `gTop`, so a compound met twice is one compound in
# the copy, as swipl's (`same_term/2`). The visited marks are upstream's: while the term is
# compiled a variable cell holds its number as a var-link word (`TAG_ATOM|STG_GLOBAL`) and a
# compound's functor cell the offset of its copy (a tagged integer), restored after (`restoreVars`,
# `unvisit`).
#
# DIVERGES, representation only. An INDIRECT — a value-table word: a float, a string, a big
# integer, a rational — is recorded as its VALUE, in the record's `values` (`PL_REC_VALUE`, an
# ORIGINAL opcode), where upstream copies its bytes; it is put back as a new value-table entry whose
# box is one cell of the block (upstream: the indirect's header, data and header words, all in
# `gsize`). A ROOT variable takes one cell of the block, counted in `gsize`: a slot is never an
# unbound variable here (L1c), where upstream's term reference is the variable itself.
#
# THE ORDER OF THE FRESH VARIABLES is upstream's by construction: a compound's cells are laid out
# when it is met, and a variable lives in the lowest of the cells that hold it (`copy_record`'s
# "right direction"), so the standard order of two fresh variables is the order of those cells.
#
# Since R2's D1, `erase/1` and `instance/2` for a CLAUSE reference (`pl_erase1_va`, `pl_instance2_va` with
# `fixup_ssu`, below the copying: the clause blobs of src/pl-dbref.jl); since D2 the recorded database
# (`recorda/3`, `recordz/3`, `recorded/3`, `current_key/1`, `erase/1` and `instance/2` of a record, the keys
# and their lists). Since FAST-1b the EXTERNAL encoder: `compile_external_record` (the `PL_TYPE_EXT_*`,
# `PL_TYPE_INTEGER`, `PL_REC_MPZ`, `PL_REC_MPQ` opcodes, the header) and `fast_term_serialized/2`, the term to
# the string. LATER STEPS and left out: the rest of pl-rec.c — the string to the term (`PL_recorded_external`,
# `fast_term_serialized/2`'s other direction: refused, step FAST-2), `PL_record_external` (pl-rec.c:896, the C
# interface over `compile_external_record`: a later step), `fast_write/2`, `fast_read/2`, `term_complexity`,
# atom references and their marking (`markAtomsRecord`: no atom GC), dicts (`PL_TYPE_DICT` in an INTERNAL
# record: its atom keeps its word), and `freeRecord` (a record is freed by Julia's GC).
#
# ATTRIBUTED VARIABLES (AV6, as upstream's `O_ATTVAR` cases): `PL_TYPE_ATTVAR` records an attributed
# variable as a numbered variable followed by its attribute list, so findall/3 and bagof/3 give back
# the attributes; `PL_REC_ALLOCVAR` first when the record is that variable alone. While the term is
# compiled the attvar cell holds the var-link word, and `restoreVars` puts its saved word back.

# PORT: pl-rec.c PL_TYPE_VARIABLE
# DIVERGES: the opcodes of what the kernel's cells hold; an INTERNAL record's indirect is `PL_REC_VALUE`
# (ORIGINAL), not `PL_TYPE_INTEGER`, `PL_REC_MPZ`, `PL_REC_MPQ`, `PL_TYPE_FLOAT` or `PL_TYPE_STRING` (an EXTERNAL
# record's are upstream's, but for `PL_TYPE_FLOAT`: `PL_TYPE_EXT_FLOAT`).
"Record opcode: a variable, its number following (pl-rec.c)."
const PL_TYPE_VARIABLE = 0x01
"Record opcode: an atom, its word following (pl-rec.c)."
const PL_TYPE_ATOM = 0x02
"Record opcode (external): an integer that fits 64 bits, its bytes following (pl-rec.c)."
const PL_TYPE_INTEGER = 0x03
"Record opcode: a tagged integer, its value following (pl-rec.c)."
const PL_TYPE_TAGGED_INTEGER = 0x04
"Record opcode (external): a string, its byte count and bytes following (pl-rec.c)."
const PL_TYPE_STRING = 0x06
"Record opcode: a compound, its functor word following (pl-rec.c)."
const PL_TYPE_COMPOUND = 0x07
"Record opcode: a list cell (pl-rec.c)."
const PL_TYPE_CONS = 0x08
"Record opcode: `[]` (pl-rec.c)."
const PL_TYPE_NIL = 0x09
"Record opcode (external): the reserved atom `dict` (pl-rec.c)."
const PL_TYPE_DICT = 0x0a
"Record opcode (external): a Latin-1 atom, its byte count and bytes following (pl-rec.c)."
const PL_TYPE_EXT_ATOM = 0x0b
"Record opcode (external): a wide atom, its byte count and 4-byte characters following (pl-rec.c)."
const PL_TYPE_EXT_WATOM = 0x0c
"Record opcode (external): a compound, its arity and name atom following (pl-rec.c)."
const PL_TYPE_EXT_COMPOUND = 0x0d
"Record opcode (external): a float, its 8 bytes in the machine's order following (pl-rec.c)."
const PL_TYPE_EXT_FLOAT = 0x0e
"Record opcode: a compound met before, the offset of its copy following (pl-rec.c)."
const PL_REC_CYCLE = 0x11
"Record opcode: an attributed variable, its number following, then its attribute list (pl-rec.c)."
const PL_TYPE_ATTVAR = 0x0f
"Record opcode: a global cell for a root attributed variable, the `PL_TYPE_ATTVAR` following (pl-rec.c)."
const PL_REC_ALLOCVAR = 0x10
"Record opcode (external): a GMP integer, its 4-byte signed length and big-endian bytes following (pl-rec.c)."
const PL_REC_MPZ = 0x12
"Record opcode (external): a GMP rational, the two headers and the two byte strings following (pl-rec.c)."
const PL_REC_MPQ = 0x13
# ORIGINAL: see the file header.
"Record opcode: an indirect, its index in the record's `values` following."
const PL_REC_VALUE = 0x40

# PORT: pl-rec.c compile_info
# DIVERGES: `vars` holds the variable cells' positions; an attributed variable's is two entries, its
# saved word (`reinterpret`ed) under its NEGATED position (upstream: the word under `mkAttVarP(p)`, the
# pointer's low bit set); `values` the indirects (see the file
# header); `marks` is upstream's `LD->cycle.lstack` of `cycle_mark` (the functor cell's position and
# its word). NOT KEPT: `lock` (no atom GC). `econtext` is the culprit's value (upstream: `atom_t econtext[1]`).
"The state of one `compile_term_to_heap` (pl-rec.c `compile_info`)."
mutable struct compile_info{T}
    const code::Vector{UInt8}               # code buffer
    const vars::Vector{Int}                 # variable cells (positions; an attvar's: word, -position)
    const values::Vector{T}                 # (the indirects, see the file header)
    const marks::Vector{Tuple{Int, word}}   # (LD->cycle.lstack: functor cell, its word)
    size::Int                               # size on global stack
    nvars::Int                              # # variables
    const external::Bool                    # Allow for external storage
    error::Int                              # generated error (`ENONE`, `EFAST_SERIALIZE`)
    econtext::Union{Nothing, T}             # error context
end

# PORT: pl-rec.c cerror
# DIVERGES: `Int` constants (the enum's two values).
"`compile_info.error`: no error (pl-rec.c `ENONE`)."
const ENONE = 0
"`compile_info.error`: a blob cannot be serialised, `econtext` is it (pl-rec.c `EFAST_SERIALIZE`)."
const EFAST_SERIALIZE = 1

# PORT: pl-rec.c addOpCode
"Add opcode `code` (pl-rec.c)."
@inline addOpCode(info::compile_info, code::UInt8)::Nothing =
    (push!(info.code, code); nothing)

# PORT: pl-rec.c addSizeInt
# DIVERGES: `addUintBuffer` inlined. 7 bits per byte, most significant first, every byte but the
# last with its 8th bit set.
"Add the size `val` (a variable number, an offset, an index) to the code (pl-rec.c)."
function addSizeInt(info::compile_info, val::Int)::Nothing
    # upstream's `!(val & ~0x7f)` on a size_t; `~0x7f` of a bare literal is the UInt8 0x80 in Julia, so the mask is an Int: val < 128
    if (val & ~Int(0x7f)) == 0
        push!(info.code, val % UInt8)
    else
        zips = (8 * 8 + 7 - 1) ÷ 7 - 1                     # ((sizeof(val))*8+7-1)/7 - 1
        leading = true
        while zips >= 0
            d = (val >> (zips * 7)) & 0x7f
            if d != 0 || !leading
                zips != 0 && (d |= 0x80)
                push!(info.code, d % UInt8)
                leading = false
            end
            zips -= 1
        end
    end
    return nothing
end

# PORT: pl-rec.c addUintBuffer
# DIVERGES: the buffer is a `Vector{UInt8}`. The mask is `~Int(0x7f)`: `addSizeInt` above keeps `~0x7f` of the
# UInt8 `0x7f` (= `0x80`), which writes a value in 256..383, 512..639, ... as ONE byte (a separate fix branch,
# wip/rec-sizeint, corrects it; it is not changed on this branch).
"Add `val` to the buffer `b`: 7 bits per byte, most significant first, every byte but the last with its 8th bit set (pl-rec.c)."
function addUintBuffer(b::Vector{UInt8}, val::Int)::Nothing
    if (val & ~Int(0x7f)) == 0
        push!(b, val % UInt8)
    else
        zips = (8 * 8 + 7 - 1) ÷ 7 - 1                     # ((sizeof(val))*8+7-1)/7 - 1
        leading = true
        while zips >= 0
            d = (val >> (zips * 7)) & 0x7f
            if d != 0 || !leading
                zips != 0 && (d |= 0x80)
                push!(b, d % UInt8)
                leading = false
            end
            zips -= 1
        end
    end
    return nothing
end

# PORT: pl-rec.c addInt64
"Add the signed `v`: its byte count, then its bytes, most significant first (pl-rec.c)."
function addInt64(info::compile_info, v::Int64)::Nothing
    i = if v == 0
        1
    elseif v == typemin(Int64)                              # PLMININT
        8
    else
        (MSB64(v > 0 ? v : -v) + 9) ÷ 8
    end
    push!(info.code, i % UInt8)
    while (i -= 1) >= 0
        push!(info.code, (v >> (i * 8)) % UInt8)            # & 0xff
    end
    return nothing
end

# PORT: pl-rec.c addWord
# DIVERGES: the word's bytes least significant first (upstream: `memcpy`, the machine's order).
"Add the word `w` (an atom's, a functor's) to the code (pl-rec.c)."
function addWord(info::compile_info, w::word)::Nothing
    for i in 0:7
        push!(info.code, (w >> (8 * i)) % UInt8)
    end
    return nothing
end

# PORT: pl-rec.c addAtom
# DIVERGES: the atom is its word `a`. An INTERNAL record keeps a dict atom as its word (`PL_TYPE_ATOM`; upstream
# writes `PL_TYPE_DICT` in both: `copy_record` has no dict case here). A text atom is its text (`sym_text`):
# `PL_TYPE_EXT_WATOM` when a character is above 0xFF (`isUCSAtom`; 4 little-endian bytes per character, the
# `wchar_t` of the machine), else `PL_TYPE_EXT_ATOM` (one byte per character). What is no text atom (a blob; upstream's
# `PL_BLOB_TEXT` also covers a reserved symbol, `[]` and `dict`, handled above) is the error, `econtext` the atom's
# value. Left out: `lock` (no atom GC).
"Add atom `a` to the code (pl-rec.c); false, `info.error` set, for one that cannot go into an external record."
function addAtom(ld::PL_local_data{T}, info::compile_info{T}, a::word)::Bool where {T}
    if a == ld.atom_nil_w
        addOpCode(info, PL_TYPE_NIL)
    elseif info.external && a == ATOM_dict
        addOpCode(info, PL_TYPE_DICT)
    elseif info.external
        v = _atom_value(ld, a)
        if isTextAtom(v)
            text = sym_text(v)
            if _is_ucs_text(text)
                addOpCode(info, PL_TYPE_EXT_WATOM)
                addSizeInt(info, 4 * length(text))          # a->length: bytes
                for ch in text
                    c = UInt32(ch)
                    for i in 0:3
                        push!(info.code, (c >> (8 * i)) % UInt8)
                    end
                end
            else
                addOpCode(info, PL_TYPE_EXT_ATOM)
                addSizeInt(info, length(text))
                for ch in text
                    push!(info.code, UInt32(ch) % UInt8)
                end
            end
        else
            info.error = EFAST_SERIALIZE
            info.econtext = v
            return false
        end
    else
        addOpCode(info, PL_TYPE_ATOM)
        addWord(info, a)
    end
    return true
end

# PORT: pl-rec.c addFunctor
"Add functor `f` to the code (pl-rec.c); false, `info.error` set, when an external record's functor name is a blob."
function addFunctor(ld::PL_local_data{T}, info::compile_info{T}, f::word)::Bool where {T}
    if f == ld.functor_dot2
        addOpCode(info, PL_TYPE_CONS)
    elseif info.external
        addOpCode(info, PL_TYPE_EXT_COMPOUND)
        addSizeInt(info, arityFunctor(ld.functors, f))
        return addAtom(ld, info, nameFunctor(ld.functors, f))
    else
        addOpCode(info, PL_TYPE_COMPOUND)
        addWord(info, f)
    end
    return true
end

# ORIGINAL: the external record's text of a string and its size on the global stack, as the `TAG_STRING` case
# of `compile_term_to_heap` writes them. A string is its storage: a `B` and the characters (ISO Latin-1), or a
# `W`, three padding bytes and 4 little-endian bytes per character (a character above 0xFF); `n` words
# hold them and a byte more (upstream: `allocString`: always at least one padding byte), the header and the
# trailer two more.
"The bytes of string `text` as upstream's global stack holds it, and the cells it takes there (pl-rec.c, `TAG_STRING`)."
function _external_string(text::String)::Tuple{Vector{UInt8}, Int}
    b = UInt8[]
    if _is_ucs_text(text)
        push!(b, UInt8('W'), 0x00, 0x00, 0x00)
        for ch in text
            c = UInt32(ch)
            for i in 0:3
                push!(b, (c >> (8 * i)) % UInt8)
            end
        end
    else
        push!(b, UInt8('B'))
        for ch in text
            push!(b, UInt32(ch) % UInt8)
        end
    end
    return (b, (length(b) + 8) ÷ 8 + 2)                     # n = wsizeofInd; info->size += n+2
end

# ORIGINAL: the `TAG_INTEGER`, `TAG_STRING` and `TAG_FLOAT` cases of `compile_term_to_heap` for an EXTERNAL
# record, on the indirect's value `v`.
# DIVERGES: an integer that fits an `Int64` is `PL_TYPE_INTEGER` (upstream's `V_INTEGER`: the indirect int64), a
# larger one `PL_REC_MPZ`; the size accounting is upstream's global-stack cells (`wsizeofIndirect(w) + 2`: 3 for
# an int64 or a float, an mpz's limbs and `MPZ_STACK_EXTRA`, an mpq's two). A value of no SWI type (`NUM_OTHER`: no
# upstream counterpart) is refused as a blob, `econtext` the value.
"Add the indirect value `v` to an external record's code and size (pl-rec.c `compile_term_to_heap`); false, `info.error` set, for a value of no SWI type."
function addExternalIndirect(info::compile_info{T}, v::T)::Bool where {T}
    k = number_kind(v)
    if k === NUM_INTEGER
        if integer_is_int64(v)
            info.size += 1 + 2                              # wsizeofIndirect(w) + 2
            addOpCode(info, PL_TYPE_INTEGER)
            addInt64(info, int64_value(v))
        else
            z = bigint_value(v)
            info.size += mpz_wsize(z) + MPZ_STACK_EXTRA + 2
            addOpCode(info, PL_REC_MPZ)
            addMPZToBuffer(info.code, z)
        end
    elseif k === NUM_RATIONAL
        q = rational_value(v)
        info.size += mpz_wsize(numerator(q)) + mpz_wsize(denominator(q)) + 2 * MPZ_STACK_EXTRA + 2
        addOpCode(info, PL_REC_MPQ)
        addMPQToBuffer(info.code, q)
    elseif k === NUM_FLOAT
        info.size += 1 + 2                                  # WORDS_PER_DOUBLE + 2
        addOpCode(info, PL_TYPE_EXT_FLOAT)
        bits = reinterpret(UInt64, Float64(float_value(v)))
        for i in 0:7                                        # double_byte_order: the machine's, LSB first
            push!(info.code, (bits >> (8 * i)) % UInt8)
        end
    elseif k === NUM_STRING
        bytes, sz = _external_string(string_value(v))
        info.size += sz
        addOpCode(info, PL_TYPE_STRING)
        addSizeInt(info, length(bytes))                     # addChars
        append!(info.code, bytes)
    else
        info.error = EFAST_SERIALIZE
        info.econtext = v
        return false
    end
    return true
end

# PORT: pl-rec.c compile_term_to_heap
# DIVERGES: on locations (`ld.walk_agenda`, dereferenced here); the cases of the kernel's words (see
# the file header); false only for an external record's blob (`info.error`). An
# attributed variable's `goto again` on its attribute list is the inner loop.
"Compile the term of agenda `a` into `info` (pl-rec.c `compile_term_to_heap`)."
function compile_term_to_heap(
    ld::PL_local_data{T}, a::cell_agenda, info::compile_info{T}
)::Bool where {T}
    while true
        p = nextCellAgendaNoDeRef!(a)
        p == 0 && return true
        if p < 0                                            # the root: a slot
            w = ld.slots[-p]
            w == SLOT_VALUE && (w = _side_word(-p))         # a side value (f3-1): an indirect
        else
            w = ld.gstack[p]
        end
        while isRef(w)                                      # deRef(p)
            p = unRef(w)
            w = ld.gstack[p]
        end
        while isAttVar(w)                                   # TAG_ATTVAR (a global cell: p > 0)
            n = info.nvars
            info.nvars += 1
            ap = valPtr(w)                                  # Word ap = valPAttVar(w)
            if isempty(info.code)                           # isEmptyBuffer(&info->code)
                addOpCode(info, PL_REC_ALLOCVAR)            # only an attributed var
                info.size += 1
            end
            push!(info.vars, reinterpret(Int, w))           # addBuffer(&info->vars, *p, word): save value
            ld.gstack[p] = consPtr(n, TAG_ATOM | STG_GLOBAL)   # *p = (n<<7)|TAG_ATOM|STG_GLOBAL
            push!(info.vars, -p)                            # addBuffer(&info->vars, mkAttVarP(p), Word)
            addOpCode(info, PL_TYPE_ATTVAR)
            addSizeInt(info, n)
            info.size += 3
            p = ap                                          # p = ap; deRef(p); goto again
            w = ld.gstack[p]
            while isRef(w)
                p = unRef(w)
                w = ld.gstack[p]
            end
        end
        if isVar(w)                                         # TAG_VAR
            n = info.nvars
            info.nvars += 1
            ld.gstack[p] = consPtr(n, TAG_ATOM | STG_GLOBAL)   # *p = (n<<7)|TAG_ATOM|STG_GLOBAL
            push!(info.vars, p)
            addOpCode(info, PL_TYPE_VARIABLE)
            addSizeInt(info, n)
        elseif isFunctor(w)                                 # TAG_ATOM, STG_GLOBAL: a var-link
            addOpCode(info, PL_TYPE_VARIABLE)
            addSizeInt(info, Int(w >> LMASK_BITS))
        elseif isAtomW(w)                                   # TAG_ATOM: addAtom
            addAtom(ld, info, w) || return false
        elseif isTaggedIntW(w)                              # TAG_INTEGER, isTaggedInt
            addOpCode(info, PL_TYPE_TAGGED_INTEGER)
            addInt64(info, valInt(w))
        elseif _is_gcompound(w)                             # TAG_COMPOUND
            f = valPtr(w)
            fd = ld.gstack[f]
            if isTaggedIntW(fd)                             # isInteger(f->definition): met before
                addOpCode(info, PL_REC_CYCLE)
                addSizeInt(info, Int(valInt(fd)))
            else
                arity = arityFunctor(ld.functors, fd)
                push!(info.marks, (f, fd))                  # pushSegStack(&LD->cycle.lstack, mark)
                ld.gstack[f] = consUInt(UInt64(info.size))  # f->definition = consUInt(info->size)
                info.size += arity + 1
                addFunctor(ld, info, fd) || return false
                pushWorkCellAgenda!(a, arity, f + 1)
            end
        elseif _is_vword(w) || _is_side_word(w)             # an indirect (see the file header)
            if info.external                                # its bytes (upstream's TAG_INTEGER, TAG_STRING, TAG_FLOAT)
                addExternalIndirect(info, _indirect_value(ld, w)) || return false
            else
                push!(info.values, _indirect_value(ld, w))
                info.size += 1                              # (its box)
                addOpCode(info, PL_REC_VALUE)
                addSizeInt(info, length(info.values))
            end
        else
            error("compile_term_to_heap: not a cell word: $(repr(w))")   # assert(0)
        end
    end
end

# PORT: pl-rec.c unvisit
# DIVERGES: the marks are `info`'s (upstream: `LD->cycle.lstack`).
"Give every compound `compile_term_to_heap` visited its functor back (pl-rec.c)."
function unvisit(ld::PL_local_data, info::compile_info)::Nothing
    m = info.marks
    while !isempty(m)
        f, fd = pop!(m)
        ld.gstack[f] = fd                                   # mark.term->definition = mark.fdef
    end
    return nothing
end

# PORT: pl-rec.c restoreVars
# DIVERGES: an attributed variable's entry is its negated position over its saved word (see
# `compile_info`).
"Make every variable cell `compile_term_to_heap` numbered unbound again, every attributed variable's cell its word (pl-rec.c)."
function restoreVars(ld::PL_local_data, info::compile_info)::Nothing
    v = info.vars
    while !isempty(v)
        p = pop!(v)
        if p < 0                                            # if ( isAttVarP(*p) )
            ld.gstack[-p] = reinterpret(word, pop!(v))      # *addr = *(Word)p
        else
            ld.gstack[p] = word(0)                          # setVar(**p)
        end
    end
    return nothing
end

# PORT: pl-rec.c compileTermToHeap_ex as compileTermToHeap
# DIVERGES: the record is the code with `gsize`, `nvars` and the indirects (see the file header). NOT
# PORTED: `allocate` and `ctx` (the caller's allocator) and `flags` (`R_NOLOCK`, `R_DUPLICATE`,
# `R_EXTERNAL`).
"""
    compileTermToHeap(ld, t) -> record

Record the term `t` references (pl-rec.c): a byte code that no longer needs the stacks, and that
undoing the bindings it was made under does not change.
"""
function compileTermToHeap(ld::PL_local_data{T}, t::term_t)::record{T} where {T}
    info = compile_info{T}(UInt8[], Int[], T[], Tuple{Int, word}[], 0, 0, false, ENONE, nothing)    # init_cycle, initBuffer
    a = ld.walk_agenda
    initCellAgenda!(a, 1, -(t + 1))                         # initTermAgenda(&agenda, 1, valTermRef(t))
    rc = compile_term_to_heap(ld, a, info)
    clearCellAgenda!(a)
    restoreVars(ld, info)
    unvisit(ld, info)
    @assert rc                                              # (no external record: see above)
    info.code[1] == PL_TYPE_VARIABLE && (info.size += 1)    # (a root variable: its cell)
    return record{T}(info.size, info.nvars, info.code, info.values)
end

# ── external records (pl-rec.c, FAST-1b: the encoder; `PL_recorded_external` is FAST-2) ────────────
# PORT: pl-rec.c REC_32
"External record header bit: the word is 32 bits (pl-rec.c)."
const REC_32 = 0x01
# PORT: pl-rec.c REC_64
"External record header bit: the word is 64 bits (pl-rec.c)."
const REC_64 = 0x02
# PORT: pl-rec.c REC_INT
"External record header bit: the record just contains an integer (pl-rec.c)."
const REC_INT = 0x04
# PORT: pl-rec.c REC_ATOM
"External record header bit: the record just contains an atom (pl-rec.c)."
const REC_ATOM = 0x08
# PORT: pl-rec.c REC_GROUND
"External record header bit: the record is ground (pl-rec.c)."
const REC_GROUND = 0x10
# PORT: pl-rec.c REC_VMASK
"External record header: the version mask (pl-rec.c)."
const REC_VMASK = 0xe0
# PORT: pl-rec.c REC_VSHIFT
"External record header: the shift of the version (pl-rec.c)."
const REC_VSHIFT = 5
# PORT: pl-rec.c REC_HDR
# DIVERGES: always `REC_64` (the kernel's word is 64 bits).
"The first byte of an external record without its type bits: the word size and the version (pl-rec.c)."
const REC_HDR = REC_64 | (PL_REC_VERSION << REC_VSHIFT)

# PORT: pl-rec.c record_data
# DIVERGES: `info.code` and `hdr` are `Vector{UInt8}`s; the constructor makes the `compile_info` with
# `external` set (upstream: `compile_external_record` sets `data->info.external = true` and `lock = false`;
# `lock` is not kept).
"An external record being made (pl-rec.c `record_data`): the code, and the header unless it is `simple`."
mutable struct record_data{T}
    simple::Bool                            # no header
    const info::compile_info{T}
    const hdr::Vector{UInt8}
end

"A fresh `record_data{T}` for an external record."
record_data(::Type{T}) where {T} = record_data{T}(
    false, compile_info{T}(UInt8[], Int[], T[], Tuple{Int, word}[], 0, 0, true, ENONE, nothing), UInt8[]
)

# PORT: pl-rec.c rec_error
# DIVERGES: `PL_permission_error` is `PL_error(…, ERR_PERMISSION, …)` (the kernel has no wrapper); the culprit is the
# value `econtext` holds. The `default` case (`assert(0)`) is an error.
"Raise the error `info` holds (pl-rec.c): `permission_error(fast_serialize, blob, Culprit)`; false."
function rec_error(ld::PL_local_data{T}, info::compile_info{T})::Bool where {T}
    if info.error == EFAST_SERIALIZE
        t = PL_new_term_ref(ld)
        t == 0 && return false
        PL_put_atom(ld, t, info.econtext::T) || return false
        return PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :fast_serialize), mk_sym(T, :blob), t
        )
    end
    error("rec_error: no error to raise: $(info.error)")    # assert(0)
end

# PORT: pl-rec.c compile_external_record
# DIVERGES: the root is read through `_deref_loc` (an integer: a tagged word, or an indirect that fits an `Int64`: upstream's
# `get_int64`); `data` is made by the caller (`record_data`), `info.external` is already set; the compile uses
# `ld.walk_agenda`. NO `+1` for a root variable (the cell that `compileTermToHeap`, the internal record, adds). An
# atom-only record whose atom cannot be written (a blob) FAILS without an error (upstream, pl-rec.c:863: `return false`).
"Compile the term `t` references into `data`, an external record (pl-rec.c): false when it has a blob (an error raised, but for a root blob atom)."
function compile_external_record(
    ld::PL_local_data{T}, t::term_t, data::record_data{T}
)::Bool where {T}
    first = Int(REC_HDR)
    info = data.info

    k, x, _ = _deref_loc(ld, -(t + 1))                      # p = valTermRef(t); deRef(p)
    v = nothing
    if k == DU_VALUE
        if isTaggedIntW(x)
            v = valInt(x)
        else
            iv = _indirect_value(ld, x)
            isInteger(iv) && integer_is_int64(iv) && (v = int64_value(iv))
        end
    end

    if v !== nothing                                        # integer-only record
        first |= REC_INT | REC_GROUND
        addOpCode(info, first % UInt8)
        addInt64(info, Int64(v))
        data.simple = true
        return true
    elseif k == DU_WORD && isAtomW(x)                       # atom-only record
        first |= REC_ATOM | REC_GROUND
        addOpCode(info, first % UInt8)
        addAtom(ld, info, x) || return false                # (no error: pl-rec.c:863)
        data.simple = true
        return true
    end

    data.simple = false                                     # the real stuff
    info.size = 0
    info.nvars = 0

    a = ld.walk_agenda
    initCellAgenda!(a, 1, -(t + 1))                         # initTermAgenda(&agenda, 1, p)
    rc = compile_term_to_heap(ld, a, info)
    clearCellAgenda!(a)
    info.nvars == 0 && (first |= REC_GROUND)
    restoreVars(ld, info)
    unvisit(ld, info)
    rc || return rec_error(ld, info)
    scode = length(info.code)

    push!(data.hdr, first % UInt8)                          # magic code
    addUintBuffer(data.hdr, scode)                          # code size
    addUintBuffer(data.hdr, info.size)                      # size on stack
    info.nvars > 0 && addUintBuffer(data.hdr, info.nvars)   # Number of variables
    return true
end

# PORT: pl-rec.c skipSizeInt
"Advance the copy past the size at its position (pl-rec.c)."
function skipSizeInt(code::Vector{UInt8}, b::copy_info)::Nothing
    while (code[b.data] & 0x80) != 0
        b.data += 1
    end
    b.data += 1
    return nothing
end

# PORT: pl-rec.c is_external
# DIVERGES: the record is a byte vector; a record shorter than its own header says (a read past the end) is
# `false`, where upstream reads on; an unknown first byte is `false` (upstream's `assert(0)`, which a release build
# does not run). The case of an atom-only record whose atom is none of the four falls through to the header case, as upstream's.
"Whether the first `len` bytes of `rec` are one complete external record (pl-rec.c)."
function is_external(rec::Vector{UInt8}, len::Int)::Bool
    len >= 2 || return false
    info = copy_info(1, Int[], 0, 0)                        # info.data = info.base = rec
    try
        m = rec[info.data]                                  # fetchBuf(&info, &m, uchar)
        info.data += 1
        if m == (REC_HDR | REC_INT | REC_GROUND)
            bytes = Int(rec[info.data])
            info.data += 1
            return len == bytes + 2
        elseif m == (REC_HDR | REC_ATOM | REC_GROUND)
            code = rec[info.data]
            info.data += 1
            if code == PL_TYPE_NIL || code == PL_TYPE_DICT
                return len == 2
            elseif code == PL_TYPE_EXT_WATOM || code == PL_TYPE_EXT_ATOM
                bytes = fetchSizeInt(rec, info)
                return len == (info.data - 1) + bytes
            end
        elseif m != (REC_HDR | REC_GROUND) && m != REC_HDR
            return false                                    # default
        end
        codes = fetchSizeInt(rec, info)                     # REC_HDR|REC_GROUND, REC_HDR
        skipSizeInt(rec, info)                              # global stack size
        (m & REC_GROUND) == 0 && skipSizeInt(rec, info)     # # variables
        return len == (info.data - 1) + codes
    catch e
        e isa BoundsError && return false
        rethrow()
    end
end

# PORT: pl-rec.c fast_term_serialized as pl_fast_term_serialized2_va
# (PRED_IMPL("fast_term_serialized", 2, fast_term_serialized, 0))
# DIVERGES: the TERM TO STRING direction is upstream's: the text is the header and the code as ISO Latin-1
# (`PL_unify_text` with `PL_STRING`: upstream `PL_unify_string_nchars` for a simple record, a `globalBlob`
# string whose storage tag `B` precedes them otherwise: the same string). The STRING TO TERM direction checks the
# text as upstream does (`PL_get_text` with `CVT_STRING|CVT_EXCEPTION`, `is_external`) and then refuses by name:
# `NotPortedError` for `PL_recorded_external` (FAST-2); a string with a character above 0xFF too (upstream asks for
# `REP_ISO_LATIN_1`). `PL_record_external` (pl-rec.c:896, the C interface) is a later step.
"`fast_term_serialized(?Term, ?String)` (pl-rec.c): `String` is the external record of `Term`; the other direction is FAST-2."
function pl_fast_term_serialized2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    term, string = PL__t0, PL__t0 + 1                       # term_t term = A1, string = A2

    if PL_is_variable(ld, string)
        data = record_data(T)
        compile_external_record(ld, term, data) || return FFALSE
        bytes = data.simple ? data.info.code : vcat(data.hdr, data.info.code)
        text = PL_chars_t(bytes, length(bytes), ENC_ISO_LATIN_1, true)
        return PL_unify_text(ld, string, 0, text, PL_STRING) ? FTRUE : FFALSE
    end

    text = PL_get_text(ld, string, CVT_STRING | CVT_EXCEPTION)
    text === nothing && return FFALSE
    rc = PL_canonicalise_text(text)
    rc == 1 || (text_error(ld, rc); return FFALSE)
    if text.encoding === ENC_WCHAR
        throw(
            NotPortedError{T}(
                mk_sym(T, :fast_term_serialized),
                "fast_term_serialized/2 string above 0xFF (REP_ISO_LATIN_1)", "step FAST-2"
            )
        )
    end
    is_external(text.text, length(text.text)) || return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :fast_term_serialized),
            "fast_term_serialized/2 string -> term (PL_recorded_external)", "step FAST-2"
        )
    )
end

# PORT: pl-rec.c copy_info
# DIVERGES: `data` an index into the record's code; `vars` the variable cells' positions, 0 for not
# met yet. NOT KEPT: `base`, `version_map`, `dicts`, `avars`, `vars_buf` (no external records, no
# `avars`: no attributed variable's value is stored apart; the vector is the buffer).
"The state of one `copy_record` (pl-rec.c `copy_info`)."
mutable struct copy_info
    data::Int                           # the next byte of the code
    const vars::Vector{Int}             # variable cells (0: not met)
    gbase::Int                          # base of term on global stack
    gstore::Int                         # current storage location
end

# PORT: pl-rec.c fetchSizeInt
"The size at the copy's position, advanced past it (pl-rec.c)."
function fetchSizeInt(code::Vector{UInt8}, b::copy_info)::Int
    r = 0
    while true
        d = code[b.data]
        b.data += 1
        r = (r << 7) | (d & 0x7f)
        (d & 0x80) == 0 && return r
    end
end

# PORT: pl-rec.c fetchInt64
"The signed integer at the copy's position, advanced past it (pl-rec.c)."
function fetchInt64(code::Vector{UInt8}, b::copy_info)::Int64
    val = UInt64(0)
    bytes = Int(code[b.data])
    b.data += 1
    sign = UInt64(1) << (bytes * 8 - 1)
    while (bytes -= 1) >= 0
        val = (val << 8) | code[b.data]
        b.data += 1
    end
    return reinterpret(Int64, (val ⊻ sign) - sign)
end

# PORT: pl-rec.c fetchWord
"The word at the copy's position, advanced past it (pl-rec.c; see `addWord`)."
function fetchWord(code::Vector{UInt8}, b::copy_info)::word
    w = word(0)
    for i in 0:7
        w |= word(code[b.data + i]) << (8 * i)
    end
    b.data += 8
    return w
end

# ORIGINAL: `_vword!` with its box at position `p` of the block `copy_record` lays out (upstream lays
# an indirect at `gstore`), not at `gTop + 1`; the boxes stay in the order of their positions.
"The word of a new value-table entry holding `v`, boxed at global position `p`."
@inline function _vword_at!(ld::PL_local_data{T}, v::T, p::Int)::word where {T}
    push!(ld.vtable, v)
    push!(ld.vbox, p)
    w = consPtr(length(ld.vtable), TAG_COMPOUND | STG_RESERVED)
    ld.gstack[p] = w
    return w
end

# ORIGINAL: `*p = w` for `copy_record`, where location 0 is the root: the term reference's slot.
@inline function _rec_put!(ld::PL_local_data, slot::Int, p::Int, w::word)::Nothing
    if p == 0
        ld.slots[slot] = w
    else
        ld.gstack[p] = w
    end
    return nothing
end

# PORT: pl-rec.c variantRecords
# DIVERGES: the record is `record{T}` (the code vector and the indirect values): two records are variants when `gsize`, `nvars`
# and the code are equal and the indirects are equal pairwise in SWI's identity (`gnd_equal`; upstream compares the bytes after
# the header, the indirects among them). Used by the tries (TAB1 TR1).
"Whether the records `r1` and `r2` hold variant terms: a record's code numbers the variables by first occurrence (pl-rec.c)."
function variantRecords(r1::record{T}, r2::record{T})::Bool where {T}
    (r1.gsize == r2.gsize && r1.nvars == r2.nvars && r1.code == r2.code) || return false
    length(r1.values) == length(r2.values) || return false
    for i in eachindex(r1.values)
        gnd_equal(r1.values[i], r2.values[i]) || return false
    end
    return true
end

# PORT: pl-rec.c copy_record
# DIVERGES: location 0 is the root, slot `slot` (upstream's `valTermRef(copy)`): a root variable is a
# cell of the block, an indirect stored as `_slot_link_loc!` stores one; the agenda is
# `ld.walk_agenda`; the cells were laid out unbound by `allocGlobalCells!` (setVar). `goto
# right_recursion` (`PL_REC_ALLOCVAR`, `PL_TYPE_ATTVAR`) is `continue` with the new `p`. No external
# opcode; nothing allocates fallibly (no `MEMORY_OVERFLOW`).
"Lay record `r`'s code out from `b.gstore`, its root in slot `slot` (pl-rec.c `copy_record`)."
function copy_record(
    ld::PL_local_data{T}, slot::Int, r::record{T}, b::copy_info
)::Nothing where {T}
    a = ld.walk_agenda
    code = r.code
    p = 0
    is_compound = false
    while true
        tag = code[b.data]                                  # fetchOpCode(b)
        b.data += 1
        if tag == PL_TYPE_VARIABLE
            n = fetchSizeInt(code, b) + 1
            if p == 0                                       # (a root variable: its cell)
                c = b.gstore
                b.gstore += 1
                b.vars[n] = c
                ld.slots[slot] = makeRefG(c)
            elseif b.vars[n] != 0
                v = b.vars[n]
                if p > v                                    # ensure the reference is in the
                    ld.gstack[p] = makeRefG(v)              # right direction!
                else
                    ld.gstack[p] = ld.gstack[v]             # wrong way.  make sure b->vars[n]
                    ld.gstack[v] = makeRefG(p)              # stays at the real variable
                    b.vars[n] = p
                end
            else
                ld.gstack[p] = word(0)                      # setVar(*p)
                b.vars[n] = p
            end
        elseif tag == PL_REC_ALLOCVAR                       # (a root attributed variable)
            c = b.gstore
            ld.gstack[c] = word(0)                          # setVar(*b->gstore)
            _rec_put!(ld, slot, p, makeRefG(c))             # *p = makeRefG(b->gstore)
            p = c                                           # p = b->gstore++
            b.gstore += 1
            continue                                        # goto right_recursion
        elseif tag == PL_TYPE_ATTVAR
            n = fetchSizeInt(code, b) + 1
            g = b.gstore
            register_attvar(ld, g)                          # register_attvar(b->gstore)
            ld.gstack[g + 1] = consPtr(g + 2, TAG_ATTVAR | STG_GLOBAL)   # b->gstore[1] = consPtr(&b->gstore[2], …)
            _rec_put!(ld, slot, p, makeRefG(g + 1))         # *p = makeRefG(&b->gstore[1])
            b.vars[n] = p                                   # b->vars[n] = p
            p = g + 2                                       # p = &b->gstore[2]
            b.gstore += 3
            continue                                        # goto right_recursion
        elseif tag == PL_TYPE_NIL
            _rec_put!(ld, slot, p, ld.atom_nil_w)
        elseif tag == PL_TYPE_ATOM
            _rec_put!(ld, slot, p, fetchWord(code, b))
        elseif tag == PL_TYPE_TAGGED_INTEGER
            _rec_put!(ld, slot, p, consInt(fetchInt64(code, b)))
        elseif tag == PL_REC_VALUE                          # (see the file header)
            box = b.gstore
            b.gstore += 1
            w = _vword_at!(ld, r.values[fetchSizeInt(code, b)], box)
            if p == 0
                _slot_link_loc!(ld, slot, (DU_VALUE, w, box))
            else
                ld.gstack[p] = w
            end
        elseif tag == PL_REC_CYCLE
            off = fetchSizeInt(code, b)
            _rec_put!(ld, slot, p, consPtr(b.gbase + off, TAG_COMPOUND | STG_GLOBAL))
        elseif tag == PL_TYPE_COMPOUND || tag == PL_TYPE_CONS
            fdef = tag == PL_TYPE_CONS ? ld.functor_dot2 : fetchWord(code, b)
            arity = arityFunctor(ld.functors, fdef)
            c = b.gstore
            _rec_put!(ld, slot, p, consPtr(c, TAG_COMPOUND | STG_GLOBAL))
            ld.gstack[c] = fdef
            b.gstore += arity + 1
            if !is_compound
                is_compound = true
                initCellAgenda!(a, arity, c + 1)
            else
                pushWorkCellAgenda!(a, arity, c + 1)
            end
        else
            error("copy_record: opcode $tag")               # assert(0)
        end
        is_compound || break
        p = nextCellAgendaNoDeRef!(a)
        p == 0 && break
    end
    clearCellAgenda!(a)
    return nothing
end

# PORT: pl-rec.c copyRecordToGlobal
# DIVERGES: the block is `allocGlobalCells!`'s (it grows the stack on demand: `ensureGlobalSpace` is
# the limit's check, see src/pl-alloc.jl); no `flags` (`ALLOW_GC`: no collector).
"""
    copyRecordToGlobal(ld, copy, r) -> Bool

Make term reference `copy` hold the term of record `r`, its variables fresh (pl-rec.c); false, the
overflow raised, when its cells do not fit.
"""
function copyRecordToGlobal(
    ld::PL_local_data{T}, copy::term_t, r::record{T}
)::Bool where {T}
    ensureGlobalSpace(ld, r.gsize) || return false
    gbase = r.gsize > 0 ? allocGlobalCells!(ld, r.gsize) : ld.gTop + 1   # gTop += r->gsize
    b = copy_info(1, zeros(Int, r.nvars), gbase, gbase)     # init_copy_vars
    copy_record(ld, copy + 1, r, b)
    @assert b.gstore == ld.gTop + 1                         # assert(b.gstore == gTop)
    return true
end

# ── the recorded database (pl-rec.c), since R2's D2 ──────────────────────────────────────────────
# The records of a key are a `RecordList` (src/pl-incl.jl), found by the key's WORD in `gd.record_lists`
# (upstream's `GD->recorded_db.record_lists`, a hash table) and enumerated in `gd.record_lists_order`.
# DIVERGES, representation only: the enumeration is by creation of the key's list, upstream's by the hash
# table (FLG H1; the rows compare sorted answers for an unbound key). No `PL_LOCK(L_RECORD)` (one thread);
# no `free_recordlist_symbol`, `cleanupRecords` or `unallocRecordList` (`PL_cleanup`); no atom references
# for a key (no atom GC: `PL_register_atom`).

# PORT: pl-rec.c lookupRecordList
# DIVERGES: the database is the argument; a new list is appended to `gd.record_lists_order` too.
"The record list of `key` (a key word, `getKeyEx`), made if there is none (pl-rec.c)."
function lookupRecordList(gd::PL_global_data{T}, key::word)::RecordList{T} where {T}
    l = get(gd.record_lists, key, nothing)                      # lookupHTableWP(…, key)
    l !== nothing && return l
    l = RecordList{T}(nothing, nothing, key, UInt32(0), 0)      # memset(l, 0, …); l->key = key
    gd.record_lists[key] = l                                    # addNewHTableWP(…, key, l)
    push!(gd.record_lists_order, l)
    return l
end

# PORT: pl-rec.c firstRecordRecordList
"The first record of `rl` that is not erased, or `nothing` (pl-rec.c)."
function firstRecordRecordList(rl::RecordList{T})::Union{Nothing, RecordRef{T}} where {T}
    record = rl.firstRecord
    while record !== nothing
        (record.flags & R_ERASED) == 0 && return record         # isoff(record->record, R_ERASED)
        record = record.next
    end
    return nothing
end

# PORT: pl-rec.c isCurrentRecordList
# DIVERGES: the database is the argument.
"The record list of `key` if there is one — with a record that is not erased when `must_be_non_empty` — or `nothing` (pl-rec.c)."
function isCurrentRecordList(
    gd::PL_global_data{T}, key::word, must_be_non_empty::Bool
)::Union{Nothing, RecordList{T}} where {T}
    rl = get(gd.record_lists, key, nothing)
    rl === nothing && return nothing
    if must_be_non_empty
        record = firstRecordRecordList(rl)
        return record !== nothing ? rl : nothing
    end
    return rl
end

# PORT: pl-rec.c remove_record
"Unlink the record reference `r` from its list and free it (pl-rec.c)."
function remove_record(r::RecordRef{T})::Nothing where {T}
    l = r.list
    prev = r.prev
    next = r.next
    if prev !== nothing
        prev.next = next                                        # r->prev->next = r->next
    else
        l.firstRecord = next
    end
    if next !== nothing
        next.prev = prev                                        # r->next->prev = r->prev
    else
        l.lastRecord = prev
    end
    freeRecordRef(r)
    return nothing
end

# PORT: pl-rec.c cleanRecordList
"Remove the erased records of `rl` (pl-rec.c): no `recorded/3` runs over it any more."
function cleanRecordList(rl::RecordList{T})::Nothing where {T}
    r = rl.firstRecord
    while r !== nothing
        next = r.next
        (r.flags & R_ERASED) != 0 && remove_record(r)           # ison(r->record, R_ERASED)
        r = next
    end
    return nothing
end

# PORT: pl-rec.c freeRecordRef
# DIVERGES: `freeRecord` and `freeHeap` are Julia's GC: the record is dropped (`r->record = NULL`, which
# upstream does when a blob still names the reference, `R_DBREF`); a reference no blob names is reached by
# nothing after its unlinking, so the two cases answer alike.
"Free the record of `r` (pl-rec.c): a blob naming `r` answers an erased reference from now on."
function freeRecordRef(r::RecordRef{T})::Nothing where {T}
    r.record = nothing                                          # freeRecord(r->record); r->record = NULL
    return nothing
end

# PORT: pl-rec.c unifyKey
# DIVERGES: the local data is the argument; an atom key as its atom (`_atom_value`) and a small integer by
# its value (`PL_unify_integer`), where upstream unifies the word (`PL_unify_atomic`); a functor key by its
# name and arity (`PL_unify_functor`).
"Unify `key` with the key word `val` (pl-rec.c): an atom, a small integer, or a functor's most general term."
function unifyKey(ld::PL_local_data{T}, key::term_t, val::word)::Bool where {T}
    if isAtomW(val)                                             # isAtom(val)
        return PL_unify_atomic(ld, key, _atom_value(ld, val))
    elseif isTaggedIntW(val)                                    # isTaggedInt(val)
        return PL_unify_integer(ld, key, Int(valInt(val)))
    else
        name = _atom_value(ld, nameFunctor(ld.functors, val))   # PL_unify_functor(key, (functor_t) val)
        return PL_unify_functor(ld, key, name, arityFunctor(ld.functors, val))
    end
end

# PORT: pl-rec.c getKeyEx
# DIVERGES: returns the key word, or `nothing` after the error, where upstream writes `*w` and returns a
# Bool; on the WORDS (`_deref_loc`): an atom's or a small integer's word, a compound's functor word.
"The key word of `key` (pl-rec.c): an atom, a small integer or a compound's functor; else `type_error(key, Key)` and `nothing`."
function getKeyEx(ld::PL_local_data{T}, key::term_t)::Union{Nothing, word} where {T}
    k, w, _ = _deref_loc(ld, -(key + 1))                        # Word k = valTermRef(key); deRef(k)
    if (k == DU_WORD && isAtomW(w)) || (k == DU_VALUE && isTaggedIntW(w))
        return w                                                # isAtom(*k) || isTaggedInt(*k)
    elseif k == DU_WORD && _is_gcompound(w)                     # isTerm(*k)
        return ld.gstack[valPtr(w)]                             # (word)functorTerm(*k)
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :key), key)
    return nothing
end

# PORT: pl-rec.c current_key as pl_current_key1_va
# (PRED_IMPL("current_key", 1, current_key, PL_FA_NONDETERMINISTIC))
# DIVERGES: the enumeration state is the next index in `gd.record_lists_order`, handed back as an integer
# (`PL_retry`, upstream: a `TableEnum`, `ForeignRedoPtr`), so a cut has nothing to free.
"`current_key(?Key)` (pl-rec.c): `Key` is a key with a record that is not erased."
function pl_current_key1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    gd = _query_gd(ld)
    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, A1)
            e = 1                                               # e = newTableEnumWP(…)
        else
            k = getKeyEx(ld, A1)
            (k !== nothing && isCurrentRecordList(gd, k, true) !== nothing) && return FTRUE
            return FFALSE
        end
    elseif ctl == FRG_REDO
        e = PL_foreign_context(PL__ctx)                         # e = CTX_PTR
    else                                                        # FRG_CUTTED: freeTableEnum(e)
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        while e <= length(gd.record_lists_order)                # while(advanceTableEnum(e, NULL, &sv))
            rl = gd.record_lists_order[e]
            e += 1
            record = firstRecordRecordList(rl)
            if record !== nothing && unifyKey(ld, A1, rl.key)
                PL_close_foreign_frame(ld, fid)
                return PL_retry(e)                              # ForeignRedoPtr(e)
            end
            PL_rewind_foreign_frame(ld, fid)
        end
        PL_close_foreign_frame(ld, fid)
    end
    return FFALSE                                               # freeTableEnum(e)
end

# PORT: pl-rec.c record as record_term
# DIVERGES: named `record_term` (`record` is the type of a recorded term, pl-incl.h `struct record`); the
# local data is the argument; `ref` 0 is upstream's NULL (no reference wanted).
"`recorda`/`recordz`'s body (pl-rec.c `record`): record `term` under `key`, `ref` (unbound) its reference."
function record_term(
    ld::PL_local_data{T}, key::term_t, term::term_t, ref::term_t, az::Int
)::Bool where {T}
    k = getKeyEx(ld, key)
    k === nothing && return false
    if ref != 0 && !PL_is_variable(ld, ref)
        return PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, ref)   # PL_uninstantiation_error(ref)
    end
    return PL_record_az(ld, k, term, ref, az)
end

# PORT: pl-rec.c PL_record_az
# DIVERGES: the local data is the argument; no `PL_no_memory` (Julia's allocator); on a failed `ref`
# unification nothing is freed (Julia's GC: upstream's `PL_erase(copy)`, `freeHeap`).
"Record `term` under the key word `k` at the front (`RECORDA`) or the end (`RECORDZ`) of its list (pl-rec.c)."
function PL_record_az(
    ld::PL_local_data{T}, k::word, term::term_t, ref::term_t, az::Int
)::Bool where {T}
    gd = _query_gd(ld)
    copy = compileTermToHeap(ld, term)                          # compileTermToHeap(term, 0)
    r = RecordRef{T}(copy)                                      # r = allocHeapOrHalt(…); r->record = copy
    if ref != 0 && !PL_unify_recref(gd, ld, ref, r)
        return false
    end

    l = lookupRecordList(gd, k)
    r.list = l

    first = l.firstRecord
    if first === nothing                                        # if ( !l->firstRecord )
        r.next = r.prev = nothing
        l.firstRecord = l.lastRecord = r
    elseif az == RECORDA
        r.prev = nothing
        r.next = first
        first.prev = r
        l.firstRecord = r
    else
        last = l.lastRecord::RecordRef{T}
        r.next = nothing
        r.prev = last
        last.next = r
        l.lastRecord = r
    end
    return true
end

# PORT: pl-rec.c recorda as pl_recordava_va
# (PRED_IMPL("recorda", va, recorda, 0); PRED_SHARE for recorda/2 and recorda/3)
"`recorda(+Key, +Term)`, `recorda(+Key, +Term, -Ref)` (pl-rec.c): record `Term` first under `Key`."
function pl_recordava_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return if record_term(ld, PL__t0, PL__t0 + 1, PL__ac == 3 ? PL__t0 + 2 : 0, RECORDA)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-rec.c recordz as pl_recordzva_va
# (PRED_IMPL("recordz", va, recordz, 0); PRED_SHARE for recordz/2 and recordz/3)
"`recordz(+Key, +Term)`, `recordz(+Key, +Term, -Ref)` (pl-rec.c): record `Term` last under `Key`."
function pl_recordzva_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return if record_term(ld, PL__t0, PL__t0 + 1, PL__ac == 3 ? PL__t0 + 2 : 0, RECORDZ)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-rec.c save_state
# DIVERGES: the state is a pool record from the first call on (`recorded_state`), so saving it marks it and
# returns its index.
"Keep `recorded/3`'s state `k` for the redo (pl-rec.c): its pool index."
function save_state(ld::PL_local_data{T}, k::Int)::Int where {T}
    ld.recorded_states.states[k].saved = true                   # newstate->saved = true
    return k
end

# PORT: pl-rec.c free_state
# DIVERGES: the pool record is given back whether or not it was saved (see `save_state`); no `TableEnum`
# to free.
"Drop `recorded/3`'s state `k` (pl-rec.c): the list it was in loses a reference, and is cleaned at the last."
function free_state(ld::PL_local_data{T}, k::Int)::Nothing where {T}
    state = ld.recorded_states.states[k]
    r = state.r
    if r !== nothing
        rl = r.list
        rl.references -= 1
        (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
    end
    state.r = nothing
    state.e = 0
    state.saved = false
    free_foreign_state!(ld.recorded_states, k)                  # freeForeignState(state, …)
    return nothing
end

# PORT: pl-rec.c advance_state
"Set `state` to the next record that is not erased (pl-rec.c); leaving the list drops its reference and cleans it at the last."
function advance_state(state::recorded_state{T})::Union{Nothing, RecordRef{T}} where {T}
    r = state.r::RecordRef{T}
    while true
        next = r.next
        if next === nothing                                     # if ( !r->next )
            rl = r.list
            rl.references -= 1
            (rl.references == 0 && (rl.flags & RL_DIRTY) != 0) && cleanRecordList(rl)
            r = nothing
            break
        end
        r = next
        (r.flags & R_ERASED) != 0 || break                      # while ( r && ison(r->record, R_ERASED) )
    end
    state.r = r
    return r
end

# PORT: pl-rec.c recorded as pl_recordedva_va
# (PRED_IMPL("recorded", va, recorded, PL_FA_NONDETERMINISTIC); PRED_SHARE for recorded/2 and recorded/3)
# DIVERGES: the state is a pool record (`recorded_state`), allocated where upstream's `memset` clears the
# stack state; `goto next` (a new key's list found) re-enters the record loop through the outer one, as its
# condition holds; `goto error` leaves both loops (`err`). No `PL_LOCK(L_RECORD)` (one thread). The
# local `record` is `rec` (`record` is the type of the recorded term).
"`recorded(?Key, ?Term)`, `recorded(?Key, ?Term, ?Ref)` (pl-rec.c): `Term` is recorded under `Key`, `Ref` its reference."
function pl_recordedva_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    key = PL__t0                                                # term_t key  = A1
    term = PL__t0 + 1                                           # term_t term = A2
    ref = PL__ac == 3 ? PL__t0 + 2 : 0                          # term_t ref  = (CTX_ARITY == 3 ? A3 : 0)

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if ref != 0 && !PL_is_variable(ld, ref)                 # recorded(?,?,+)
            rec = PL_get_recref(gd, ld, ref)
            rec === nothing && return FFALSE
            if unifyKey(ld, key, rec.list.key)
                copy = PL_new_term_ref(ld)
                rc =
                    copyRecordToGlobal(ld, copy, rec.record::record{T}) &&
                    PL_unify(ld, term, copy)
            else
                rc = false
            end
            return rc ? FTRUE : FFALSE
        end

        if PL_is_variable(ld, key)
            k = alloc_foreign_state!(ld.recorded_states)        # memset(state, 0, sizeof(*state))
            state = ld.recorded_states.states[k]
            state.r = nothing
            state.saved = false
            state.e = 1                                         # state->e = newTableEnumWP(…)
        else
            kw = getKeyEx(ld, key)
            kw === nothing && return FFALSE
            rl = isCurrentRecordList(gd, kw, true)
            rl === nothing && return FFALSE
            k = alloc_foreign_state!(ld.recorded_states)
            state = ld.recorded_states.states[k]
            state.e = 0
            state.saved = false
            rl.references += 1
            state.r = rl.firstRecord
            ((state.r::RecordRef{T}).flags & R_ERASED) != 0 && advance_state(state)
        end
    elseif ctl == FRG_REDO
        k = PL_foreign_context_address(PL__ctx)                 # state = CTX_PTR
        state = ld.recorded_states.states[k]
    else                                                        # FRG_CUTTED
        k = PL_foreign_context_address(PL__ctx)
        free_state(ld, k)
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        answered = false
        copy = 0
        err = false

        while !answered
            while state.r !== nothing                           # for( ; state->r; advance_state(state) )
                rec = state.r::RecordRef{T}                     # next: record = state->r

                copy == 0 && (copy = PL_new_term_ref(ld))
                if !copyRecordToGlobal(ld, copy, rec.record::record{T})
                    err = true                                  # goto error
                    break
                end

                if PL_unify(ld, term, copy) &&
                    (ref == 0 || PL_unify_recref(gd, ld, ref, rec))
                    if state.e != 0 && !unifyKey(ld, key, rec.list.key)
                        err = true                              # goto error: stack overflow
                        break
                    end
                else
                    if PL_exception(ld, 0) != 0
                        err = true                              # goto error
                        break
                    end
                    PL_rewind_foreign_frame(ld, fid)
                    advance_state(state)
                    continue
                end

                answered = true

                next = rec.next
                if next !== nothing
                    state.r = next
                    PL_close_foreign_frame(ld, fid)
                    return PL_retry_address(save_state(ld, k))  # ForeignRedoPtr(save_state(state))
                end
                advance_state(state)
            end
            err && break

            if state.e != 0                                     # if ( state->e )
                found = false
                while state.e <= length(gd.record_lists_order)  # while(advanceTableEnum(state->e, NULL, &sv))
                    rl = gd.record_lists_order[state.e]
                    state.e += 1
                    r = firstRecordRecordList(rl)
                    if r !== nothing
                        rl.references += 1
                        state.r = r
                        answered && break
                        found = true                            # goto next: try next list
                        break
                    end
                end
                found && continue
            end

            if answered
                PL_close_foreign_frame(ld, fid)
                if state.e != 0
                    return PL_retry_address(save_state(ld, k))  # ForeignRedoPtr(save_state(state))
                else
                    free_state(ld, k)
                    return FTRUE
                end
            end

            break
        end

        PL_close_foreign_frame(ld, fid)                         # error:
    end

    free_state(ld, k)
    return FFALSE
end

# PORT: pl-rec.c erase as pl_erase1_va
# (PRED_IMPL("erase", 1, erase, 0))
# DIVERGES: the database is the running query's (`_query_gd`). The RECORD branch (since D2): the flags
# `R_ERASED` and `RL_DIRTY` of a list a `recorded/3` still runs over, else `remove_record`; the event hook
# (`callEventHook(PLEV_ERASED_RECORD, r)`, pl-rec.c:2468) is src/pl-event.jl's (EV1; true with no listener), and `L_RECORD` is not taken (one thread). A static predicate's clause is `permission_error(clause,
# erase, Ref)` with `erase/1` as the context's predicate (`PL_error("erase", 1, NULL, …)`: not
# `system:erase/1`, which the other errors of this predicate show); the answer for an erased clause is
# false, no error (`PL_get_dbref` returns NULL).
"`erase(+Ref)` (pl-rec.c): retract the clause `Ref` names; the predicate must be dynamic."
function pl_erase1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ref = PL__t0                                                # term_t ref = A1
    gd = _query_gd(ld)
    r = PL_get_dbref(gd, ld, ref)
    r === nothing && return FFALSE
    type, ptr = r
    if type == DB_REF_CLAUSE                                    # CLAUSE: the erase branch of a clause
        clause = ptr::Clause{T}
        def = clause.predicate
        if (def.flags & P_DYNAMIC) == 0
            PL_error(
                ld, "erase", 1, "", ERR_PERMISSION, mk_sym(T, :clause), mk_sym(T, :erase),
                ref
            )
            return FFALSE
        end
        return retractClauseDefinition!(gd, ld, def, clause, true) ? FTRUE : FFALSE
    else
        rref = ptr::RecordRef{T}
        rc = callEventHook(gd, ld, PLEV_ERASED_RECORD, rref)    # rc = callEventHook(PLEV_ERASED_RECORD, r)
        l = rref.list                                           # l = r->list
        if l.references != 0                                    # a recorded has choicepoints
            rref.flags |= R_ERASED                              # set(r->record, R_ERASED)
            l.flags |= RL_DIRTY                                 # set(l, RL_DIRTY)
        else
            remove_record(rref)
        end
        return rc ? FTRUE : FFALSE
    end
end

# PORT: pl-rec.c fixup_ssu
# DIVERGES: `PL_unify_term(out, PL_FUNCTOR, FUNCTOR_ssu_commit2, PL_TERM, head, PL_TERM, body)` is
# `PL_cons_functor` into a new reference and `PL_unify`; the atom `!` is compared by `sym_key` with the
# compiler's `ATOM_cut`. The reference arithmetic (`--g`, `g > guard`: the goals before the cut sit in
# CONSECUTIVE term references) is upstream's, AS IS: swipl 10.1.19 drops the guard goal of
# `p ?=> g1, !, b` (one goal before the cut) and repeats goals when three or more precede the cut
# (rows n04, n06 pin its answers).
"Rewrite `p ?=> g1, g2, !, body` (`in`) to `p, g1, g2 => body` and unify it with `out`; a term with no cut is unified as it is (pl-rec.c)."
function fixup_ssu(ld::PL_local_data{T}, in::term_t, out::term_t)::Bool where {T}
    gd = _query_gd(ld)
    head = PL_new_term_ref(ld)
    body = PL_new_term_ref(ld)
    guard = PL_new_term_ref(ld)
    comma = _err_functor(ld, Symbol(","), 2)                    # FUNCTOR_comma2

    _PL_get_arg(ld, 1, in, head)
    _PL_get_arg(ld, 2, in, body)

    while PL_is_functor(ld, body, mk_sym(T, Symbol(",")), 2)    # PL_is_functor(body, FUNCTOR_comma2)
        g = PL_new_term_ref(ld)
        g == 0 && return false

        _PL_get_arg(ld, 1, body, g)
        _PL_get_arg(ld, 2, body, body)

        a = PL_get_atom(ld, g)
        if a !== nothing && sym_key(a) == gd.subclause_names.atom_cut   # a == ATOM_cut
            g -= 1
            PL_put_term(ld, guard, g) || return false           # PL_put_term(guard, --g)
            while (g -= 1) > guard                              # while(--g > guard)
                PL_cons_functor(ld, guard, comma, g, guard) || return false
                PL_cons_functor(ld, head, comma, head, guard) || return false
            end

            res = PL_new_term_ref(ld)
            PL_cons_functor(ld, res, clause_functor(ld, SSU_COMMIT_CLAUSE), head, body) ||
                return false
            return PL_unify(ld, out, res)
        end
    end

    return PL_unify(ld, in, out)
end

# PORT: pl-rec.c instance as pl_instance2_va
# (PRED_IMPL("instance", 2, instance, 0))
# DIVERGES: ONE predicate with its two branches, as upstream. The CLAUSE branch is upstream's, on the two
# sides `decompile!` gives (`_rule_term` builds the clause term upstream's `decompile` returns: `Neck(h, b)`,
# or for a fact the bare head, which this branch wraps as `(h :- true)`). The RECORD branch (since D2) copies
# the record to the global stack (`copyRecordToGlobal`) and unifies it with `Term`. A goal clause (`GOAL_CLAUSE`) and a clause not visible in the frame's generation fail.
"`instance(+Ref, -Term)` (pl-rec.c): `Term` is the clause (`Head :- Body`, `Head => Body`, a fact as `Head :- true`) a reference names."
function pl_instance2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ref, term = PL__t0, PL__t0 + 1                              # term_t ref = A1, term = A2
    gd = _query_gd(ld)
    r = PL_get_dbref(gd, ld, ref)
    r === nothing && return FFALSE                              # if ( !(ptr=PL_get_dbref(ref, &type)) )
    type, ptr = r
    if type != DB_REF_CLAUSE                                    # RECORD: the instance branch of a record
        rref = ptr::RecordRef{T}
        t = PL_new_term_ref(ld)
        if copyRecordToGlobal(ld, t, rref.record::record{T})    # copyRecordToGlobal(t, rref->record, ALLOW_GC)
            return PL_unify(ld, term, t) ? FTRUE : FFALSE
        end
        return FFALSE
    end
    clause = ptr::Clause{T}
    generation = generationFrame(ld.frames[ld.environment_frame])

    if (clause.flags & GOAL_CLAUSE) != 0 || !visibleClause(ld, clause, generation)
        return FFALSE
    end

    h = PL_new_term_ref(ld)
    b = PL_new_term_ref(ld)
    if (clause.flags & UNIT_CLAUSE) != 0
        decompile!(ld, clause, h, b) || return FFALSE
        t = PL_new_term_ref(ld)
        PL_put_atom(ld, t, mk_sym(T, Symbol("true")))           # PL_ATOM, ATOM_true
        res = PL_new_term_ref(ld)
        PL_cons_functor(ld, res, _err_functor(ld, Symbol(":-"), 2), h, t) || return FFALSE
        return PL_unify(ld, term, res) ? FTRUE : FFALSE         # PL_unify_term(term, PL_FUNCTOR, FUNCTOR_prove2, …)
    elseif (clause.flags & SSU_CHOICE_CLAUSE) != 0
        decompile!(ld, clause, h, b) || return FFALSE
        tmp = _rule_term(ld, clause, h, b)                      # decompile(clause, tmp, 0)
        return fixup_ssu(ld, tmp, term) ? FTRUE : FFALSE
    else
        decompile!(ld, clause, h, b) || return FFALSE
        return PL_unify(ld, term, _rule_term(ld, clause, h, b)) ? FTRUE : FFALSE   # decompile(clause, term, 0)
    end
end

# PORT: pl-rec.c BeginPredDefs as PL_predicates_from_rec
# DIVERGES: the entries of the predicates the kernel has ported (of the fast-term family only
# `fast_term_serialized/2`, the term to the string; `fast_write/2` and `fast_read/2` are left out); `PRED_DEF` and `PRED_SHARE` or in `PL_FA_VARARGS` (the arity is
# the call's `PL__ac`: recorded/2,3, recordz/2,3 and recorda/2,3 each share ONE function over both arities).
"pl-rec.c's registration table (`BeginPredDefs(rec)`), in upstream's order: the ported entries."
const PL_predicates_from_rec = (
    PL_extension("recorded", 2, pl_recordedva_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("recorded", 3, pl_recordedva_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("recordz", 2, pl_recordzva_va, PL_FA_VARARGS),
    PL_extension("recordz", 3, pl_recordzva_va, PL_FA_VARARGS),
    PL_extension("recorda", 2, pl_recordava_va, PL_FA_VARARGS),
    PL_extension("recorda", 3, pl_recordava_va, PL_FA_VARARGS),
    PL_extension("erase", 1, pl_erase1_va, PL_FA_VARARGS),
    PL_extension("instance", 2, pl_instance2_va, PL_FA_VARARGS),
    PL_extension(
        "current_key", 1, pl_current_key1_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("fast_term_serialized", 2, pl_fast_term_serialized2_va, PL_FA_VARARGS)
)
