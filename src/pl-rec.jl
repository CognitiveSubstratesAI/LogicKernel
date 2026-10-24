# UPSTREAM: swipl-devel src/pl-rec.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# RECORDED TERMS (pl-rec.c), exactly these: `compileTermToHeap` — a term taken off the stacks, so
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
# NOT PORTED: the rest of pl-rec.c — the recorded database (`recorda/3`, `recorded/3`, `erase/1`,
# `instance/2`, the keys and their lists), external records (`PL_record_external`, the
# `PL_TYPE_EXT_*` opcodes), `PL_record`, `PL_duplicate_record`, `variantRecords`, `term_complexity`,
# atom references and their marking (`markAtomsRecord`: no atom GC), dicts (`PL_TYPE_DICT`),
# attributed variables (`PL_TYPE_ATTVAR`, `PL_REC_ALLOCVAR`), and `freeRecord` (a record is freed
# by Julia's GC).

# PORT: pl-rec.c PL_TYPE_VARIABLE
# DIVERGES: the opcodes of what the kernel's cells hold; an indirect is `PL_REC_VALUE` (ORIGINAL),
# not `PL_TYPE_INTEGER`, `PL_REC_MPZ`, `PL_REC_MPQ`, `PL_TYPE_FLOAT` or `PL_TYPE_STRING`.
"Record opcode: a variable, its number following (pl-rec.c)."
const PL_TYPE_VARIABLE = 0x01
"Record opcode: an atom, its word following (pl-rec.c)."
const PL_TYPE_ATOM = 0x02
"Record opcode: a tagged integer, its value following (pl-rec.c)."
const PL_TYPE_TAGGED_INTEGER = 0x04
"Record opcode: a compound, its functor word following (pl-rec.c)."
const PL_TYPE_COMPOUND = 0x07
"Record opcode: a list cell (pl-rec.c)."
const PL_TYPE_CONS = 0x08
"Record opcode: `[]` (pl-rec.c)."
const PL_TYPE_NIL = 0x09
"Record opcode: a compound met before, the offset of its copy following (pl-rec.c)."
const PL_REC_CYCLE = 0x11
# ORIGINAL: see the file header.
"Record opcode: an indirect, its index in the record's `values` following."
const PL_REC_VALUE = 0x40

# PORT: pl-rec.c compile_info
# DIVERGES: `vars` holds the variable cells' positions; `values` the indirects (see the file
# header); `marks` is upstream's `LD->cycle.lstack` of `cycle_mark` (the functor cell's position and
# its word). NOT KEPT: `external`, `lock`, `error`, `econtext` (no external records, no atom GC).
"The state of one `compile_term_to_heap` (pl-rec.c `compile_info`)."
mutable struct compile_info{T}
    const code::Vector{UInt8}               # code buffer
    const vars::Vector{Int}                 # variable cells (positions)
    const values::Vector{T}                 # (the indirects, see the file header)
    const marks::Vector{Tuple{Int, word}}   # (LD->cycle.lstack: functor cell, its word)
    size::Int                               # size on global stack
    nvars::Int                              # # variables
end

# PORT: pl-rec.c addOpCode
"Add opcode `code` (pl-rec.c)."
@inline addOpCode(info::compile_info, code::UInt8)::Nothing =
    (push!(info.code, code); nothing)

# PORT: pl-rec.c addSizeInt
# DIVERGES: `addUintBuffer` inlined. 7 bits per byte, most significant first, every byte but the
# last with its 8th bit set.
"Add the size `val` (a variable number, an offset, an index) to the code (pl-rec.c)."
function addSizeInt(info::compile_info, val::Int)::Nothing
    if (val & ~0x7f) == 0
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

# PORT: pl-rec.c compile_term_to_heap
# DIVERGES: on locations (`ld.walk_agenda`, dereferenced here); the cases of the kernel's words (see
# the file header); always true (upstream fails only for an external record's blob: not ported). No
# attributed variable.
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
            if w == ld.atom_nil_w
                addOpCode(info, PL_TYPE_NIL)
            else
                addOpCode(info, PL_TYPE_ATOM)
                addWord(info, w)
            end
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
                if fd == ld.functor_dot2                    # addFunctor
                    addOpCode(info, PL_TYPE_CONS)
                else
                    addOpCode(info, PL_TYPE_COMPOUND)
                    addWord(info, fd)
                end
                pushWorkCellAgenda!(a, arity, f + 1)
            end
        elseif _is_vword(w) || _is_side_word(w)             # an indirect (see the file header)
            push!(info.values, _indirect_value(ld, w))
            info.size += 1                                  # (its box)
            addOpCode(info, PL_REC_VALUE)
            addSizeInt(info, length(info.values))
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
"Make every variable cell `compile_term_to_heap` numbered unbound again (pl-rec.c)."
function restoreVars(ld::PL_local_data, info::compile_info)::Nothing
    v = info.vars
    while !isempty(v)
        ld.gstack[pop!(v)] = word(0)                        # setVar(**p)
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
    info = compile_info{T}(UInt8[], Int[], T[], Tuple{Int, word}[], 0, 0)    # init_cycle, initBuffer
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

# PORT: pl-rec.c copy_info
# DIVERGES: `data` an index into the record's code; `vars` the variable cells' positions, 0 for not
# met yet. NOT KEPT: `base`, `version_map`, `dicts`, `avars`, `vars_buf` (no external records, no
# attributed variables; the vector is the buffer).
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

# PORT: pl-rec.c copy_record
# DIVERGES: location 0 is the root, slot `slot` (upstream's `valTermRef(copy)`): a root variable is a
# cell of the block, an indirect stored as `_slot_link_loc!` stores one; the agenda is
# `ld.walk_agenda`; the cells were laid out unbound by `allocGlobalCells!` (setVar). No attributed
# variable, no external opcode; nothing allocates fallibly (no `MEMORY_OVERFLOW`).
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
