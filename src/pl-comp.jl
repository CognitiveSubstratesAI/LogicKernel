# UPSTREAM: swipl-devel src/pl-comp.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-comp.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE CLAUSE COMPILER, HEAD SIDE — SWI-Prolog's pl-comp.c as far as compiling the head of a fact:
# the variable analysis (`analyse_variables!`, `analyseVariables2!`), argument compilation
# (`compileArgument!`, upstream's iterative version), the instruction merging that turns runs of
# `H_VOID` into `H_VOID_N` and drops the voids before `H_POP`/`I_EXITFACT` (`Output_0!`,
# `mergeInstructions!`, the table of `initVMIMerge`), and `compileClause` for a fact. Then the
# code readers the clause index uses: `stepPC`, `skipArgs`, `argKey`.
#
# WHY THE INDEX READS CODE, NOT TERMS (user, 2026-10-02): SWI computes a clause's index keys from
# this code, and the code's shape changes the result. Reading the code as upstream does keeps the
# kernel's index SWI's — with one deliberate exception: SWI loses the key of an argument that
# directly follows two or more void arguments (`skipArgs`, LogicKernel#1), and that defect is
# FIXED here (user, 2026-10-02), so the kernel indexes those arguments where swipl 10.1.16 does not.
#
# NOT PORTED: bodies (`compileBody` and everything it reaches), `islocal` compilation, SSU (`=>`)
# clauses, the moved head unifications (`argMoveUnify`/`argUnifiedTo` — they come from a body),
# singleton and branch warnings, and the instruction bodies (head unification), which arrive with
# the VM.

# ── argument positions (pl-comp.c) ──────────────────────────────────────────────────────────────
# PORT: pl-comp.c A_HEAD
"`compileArgument!`: argument in head (pl-comp.c)."
const A_HEAD = Int(0x01)
# PORT: pl-comp.c A_BODY
"`compileArgument!`: argument in body (pl-comp.c)."
const A_BODY = Int(0x02)
# PORT: pl-comp.c A_ARG
"`compileArgument!`: sub-argument (pl-comp.c)."
const A_ARG = Int(0x04)
# PORT: pl-comp.c A_RIGHT
"`compileArgument!`: rightmost argument (pl-comp.c)."
const A_RIGHT = Int(0x08)
# PORT: pl-comp.c A_NOARGVAR
"`compileArgument!`: do not compile using ci->argvar (pl-comp.c)."
const A_NOARGVAR = Int(0x10)

# ── instruction merging (pl-incl.h, pl-comp.c) ──────────────────────────────────────────────────
# PORT: pl-incl.h VMI_REPLACE
"Merge by replacing the previous instruction (pl-incl.h `vmi_merge_type`)."
const VMI_REPLACE = 0
# PORT: pl-incl.h VMI_STEP_ARGUMENT
"Merge by incrementing the previous instruction's argument (pl-incl.h `vmi_merge_type`)."
const VMI_STEP_ARGUMENT = 1

# PORT: pl-incl.h vmi_merge
"How an instruction merges with the one before it (pl-incl.h `vmi_merge`)."
struct vmi_merge
    code::code              # Code to merge with
    how::Int                # How to merge?
    merge_op::code          # Opcode of merge
    merge_ac::Int           # #arguments of merged code
    merge_av::code          # Argument vector — upstream's `merge_av[1]`
end

# PORT: pl-comp.c initVMIMerge
# DIVERGES: a constant table read through a function instead of `merge_def[]` filled at start-up
# (no module-level mutable state); the SSU entries are absent with the SSU instructions.
"""
The merges of instruction `c1` with the instruction that follows it (pl-comp.c `initVMIMerge`):
`H_VOID H_VOID` → `H_VOID_N 2`, `H_VOID_N H_VOID` → count + 1, and a void before `I_ENTER`,
`I_EXITFACT` or `H_POP` disappears.
"""
function initVMIMerge(c1::code)::Union{Nothing, NTuple{4, vmi_merge}}
    if c1 == H_VOID_N
        return (
            vmi_merge(H_VOID, VMI_STEP_ARGUMENT, code(0), 0, code(0)),  # mergeStep(H_VOID_N, H_VOID)
            vmi_merge(I_ENTER, VMI_REPLACE, I_ENTER, 0, code(0)),
            vmi_merge(I_EXITFACT, VMI_REPLACE, I_EXITFACT, 0, code(0)),
            vmi_merge(H_POP, VMI_REPLACE, H_POP, 0, code(0))
        )
    elseif c1 == H_VOID
        return (
            vmi_merge(H_VOID, VMI_REPLACE, H_VOID_N, 1, code(2)),     # mergeSeq(H_VOID, H_VOID, H_VOID_N, 1, 2)
            vmi_merge(I_ENTER, VMI_REPLACE, I_ENTER, 0, code(0)),
            vmi_merge(I_EXITFACT, VMI_REPLACE, I_EXITFACT, 0, code(0)),
            vmi_merge(H_POP, VMI_REPLACE, H_POP, 0, code(0))
        )
    end
    return nothing
end

# ── compiler state (pl-comp.c) ──────────────────────────────────────────────────────────────────
# PORT: pl-comp.c vardef as VarDef
# DIVERGES: what the analysis needs of upstream's record — the slot and the occurrence count. A
# variable is found by its `var_key` in `compileInfo.vardefs` where upstream overwrites the
# variable's cell with a reference to the record.
"The analysis of one variable of a clause (pl-comp.c `vardef`)."
mutable struct VarDef
    index::Int          # slot assigned by the analysis
    offset::Int         # offset in environment frame
    times::Int          # occurrences
end

# PORT: pl-comp.c compileInfo
# DIVERGES: the fields the head compiler uses; `vardefs` is upstream's LD->comp.vardefs keyed by
# `var_key`, `mstate_candidates`/`mstate_merge_pos` are `mstate`, `used_var` is the VarTable.
"The state of one clause compilation (pl-comp.c `compileInfo`)."
mutable struct compileInfo
    arity::Int                                              # arity of top-goal
    codes::Vector{code}                                     # scratch code table
    vardefs::Dict{UInt64, VarDef}                           # variables with a slot
    used_var::BitVector                                     # boolean array of used variables
    mstate_candidates::Union{Nothing, NTuple{4, vmi_merge}} # Merge candidates
    mstate_merge_pos::Int                                   # The merge candidate location
end

# PORT: pl-comp.c is_portable_smallint
# DIVERGES: takes the integer, not a cell — `isTaggedInt(w)` is then "within the tagged range" — and
# the local data explicitly, where upstream reaches `LD` for the flag.
"""
    is_portable_smallint(ld, i::Int64) -> Bool

Whether integer `i` may be an inline operand (pl-comp.c): it fits a tagged word, and — under the
`portable_vmi` flag, swipl's default — the int32 range too, so the code runs on 32-bit VMs. The
compiler's instruction choice; the term interface gives only the number's kind and value (Q1).
"""
function is_portable_smallint(ld::PL_local_data, i::Int64)::Bool
    if PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT                # isTaggedInt(w)
        if ld.prolog_flag_portable_vmi
            return typemin(Int32) <= i <= typemax(Int32)    # INT32_MIN <= i <= INT32_MAX
        end
        return true
    end
    return false
end

# PORT: pl-comp.c PC
"The position of the next instruction: the number of codes emitted (pl-comp.c `PC(ci)`)."
PC(ci::compileInfo)::Int = length(ci.codes)

# PORT: pl-comp.c initMerge
"No merge candidate (pl-comp.c)."
function initMerge!(ci::compileInfo)::Nothing
    ci.mstate_candidates = nothing
    return nothing
end

# PORT: pl-comp.c mergeInstructions
"Merge `c` with the candidate instruction if a merge says how; true when merged (pl-comp.c)."
function mergeInstructions!(ci::compileInfo, m::NTuple{4, vmi_merge}, c::code)::Bool
    for mm in m
        if mm.code == c
            if mm.how == VMI_REPLACE
                resize!(ci.codes, ci.mstate_merge_pos)          # seekBuffer(&ci->codes, merge_pos)
                ci.mstate_candidates = nothing
                Output_n!(ci, mm.merge_op, mm.merge_av, mm.merge_ac)
                return true
            elseif mm.how == VMI_STEP_ARGUMENT
                ci.codes[ci.mstate_merge_pos + 2] += 1         # OpCode(ci, merge_pos+1)++
                return true
            end
            break
        end
    end
    return false
end

# PORT: pl-comp.c Output_0
"Emit instruction `c`, merging it with the previous one where a merge applies (pl-comp.c)."
function Output_0!(ci::compileInfo, c::code)::Nothing
    m = ci.mstate_candidates
    if m !== nothing
        if mergeInstructions!(ci, m, c)
            return nothing
        end
        ci.mstate_candidates = nothing
    end
    m2 = initVMIMerge(c)                                       # merge_def[c]
    if m2 !== nothing
        ci.mstate_candidates = m2
        ci.mstate_merge_pos = PC(ci)
    end
    push!(ci.codes, c)                                         # encode(c)
    return nothing
end

# PORT: pl-comp.c Output_a
"Emit an operand word (pl-comp.c)."
function Output_a!(ci::compileInfo, c::code)::Nothing
    push!(ci.codes, c)
    return nothing
end

# PORT: pl-comp.c Output_1
"Emit instruction `c` with one operand (pl-comp.c)."
function Output_1!(ci::compileInfo, c::code, a::code)::Nothing
    Output_0!(ci, c)
    Output_a!(ci, a)
    return nothing
end

# PORT: pl-comp.c Output_n
# DIVERGES: at most one operand — the only merge with an operand is `H_VOID_N 2`.
"Emit instruction `c` with `n` (0 or 1) operands (pl-comp.c)."
function Output_n!(ci::compileInfo, c::code, p::code, n::Int)::Nothing
    Output_0!(ci, c)
    if n == 1
        Output_a!(ci, p)
    end
    return nothing
end

# PORT: pl-incl.h VAROFFSET
# DIVERGES: there is no frame layout yet, so a variable's offset is its slot.
"The frame offset of variable slot `var` (pl-incl.h)."
VAROFFSET(var::Int)::code = code(var)

# PORT: pl-comp.c isFirstVarSet
"Mark variable slot `n` used; true when this is its first use (pl-comp.c)."
function isFirstVarSet!(vt::BitVector, n::Int)::Bool
    if vt[n + 1]
        return false
    end
    vt[n + 1] = true
    return true
end

# PORT: pl-comp.c isIndexedVarTerm
"The frame offset of the analysed variable `t`, or -1 for a void (pl-comp.c)."
function isIndexedVarTerm(ci::compileInfo, t)::Int
    vd = get(ci.vardefs, var_key(t), nothing)
    if vd === nothing
        return -1
    end
    return vd.offset
end

# ── analysing variables (pl-comp.c) ─────────────────────────────────────────────────────────────
"An argument of a compound: its children from `off` on (2 below a symbol head, 1 otherwise)."
_comp_arg(t, off::Int, i::Int) = child(t, off + i)

"""
`(offset of argument 0, arity)` of a compound as the compiler sees it: below a symbol head, the
children after it; below any other head (a variable, a grounded value or a compound) or none, every
child — the functor `\$expr/n` (Q2, src/pl-ressymbol.jl).
"""
_comp_shape(t)::Tuple{Int, Int} =
    if nchildren(t) >= 1 && kind(child(t, 1)) === SYM
        (2, nchildren(t) - 1)
    else
        (1, nchildren(t))
    end

# PORT: pl-comp.c av_frame
"A compound whose arguments the analysis is walking (pl-comp.c `av_frame`, `AV_ARG_LOOP`)."
struct av_frame{T}
    base::T             # the compound
    off::Int            # child index of its argument 0 (see `_comp_shape`)
    next::Int           # next argument (0-based)
    argn_next::Int      # argn to pass for the next iteration
    remaining::Int      # args still to process (incl. current)
end

# PORT: pl-comp.c analyseVariables2
# DIVERGES: the head side only — no control constructs, branches, `islocal` or cycle check. A
# compound whose head is not a symbol has every child as an argument (see `compileArgument!`).
"""
Walk `head` giving each variable a slot — a variable standing as head argument `i` gets slot `i`,
any other the next slot above the arity — and counting its occurrences. Returns the number of
slots above the arity (pl-comp.c).
"""
function analyseVariables2!(ci::compileInfo, head, nvars::Int, argn::Int)::Int
    T = term_type(head)
    stack = av_frame{T}[]
    @label next_head
    if kind(head) === VAR
        vd = get(ci.vardefs, var_key(head), nothing)
        if vd === nothing
            if argn >= 0 && argn < ci.arity
                index = argn
            else
                index = ci.arity + nvars
                nvars += 1
            end
            ci.vardefs[var_key(head)] = VarDef(index, -1, 1)
        else
            vd.times += 1
        end
        @goto resume
    end
    if kind(head) === EXPR
        off, ar = _comp_shape(head)
        if ar > 0
            next_argn = argn < 0 ? 0 : ci.arity
            push!(stack, av_frame{T}(head, off, 0, next_argn, ar))
        end
    end
    @label resume
    if isempty(stack)
        return nvars
    end
    top = stack[end]
    if top.remaining > 0
        head = _comp_arg(top.base, top.off, top.next)
        argn = top.argn_next
        stack[end] = av_frame{T}(
            top.base, top.off, top.next + 1, top.argn_next + 1, top.remaining - 1
        )
        @goto next_head
    end
    pop!(stack)
    @goto resume
end

# PORT: pl-comp.c analyse_variables
# DIVERGES: the head only (no body yet), and `argvars` is 0 (it counts only for `islocal` clauses,
# which are not compiled yet). Returns the frame size `nv`, which `compileClause` records as the
# clause's `variables` and `prolog_vars` (upstream sets them here, through `ci->clause`).
"""
Analyse the variables of `head`: a variable that occurs once becomes a void (no slot); the others
get their frame offset, walking the slots in order and COMPACTING past every void above the arity —
an argument keeps its slot whatever it holds (pl-comp.c). Returns the frame size.
"""
function analyse_variables!(ci::compileInfo, head)::Int
    nvars = analyseVariables2!(ci, head, 0, -1)
    arity = ci.arity
    argvars = 0
    body_voids = 0
    # upstream walks LD->comp.vardefs[n] for n in slot order; here the records are keyed by
    # `var_key`, so index them by slot first (a slot without a variable is `!vd->address`)
    slot_key = zeros(UInt64, arity + nvars)
    slot_used = falses(arity + nvars)
    for (key, vd) in ci.vardefs
        slot_key[vd.index + 1] = key
        slot_used[vd.index + 1] = true
    end
    for n in 0:(arity + nvars - 1)
        slot_used[n + 1] || continue
        key = slot_key[n + 1]
        vd = ci.vardefs[key]
        if vd.times == 1                                       # ISVOID
            delete!(ci.vardefs, key)
            if n >= arity                                      # an argument keeps its slot
                body_voids += 1
            end
        else
            vd.offset = n + argvars - body_voids
        end
    end
    nv = nvars + arity + argvars - body_voids
    ci.used_var = falses(nv)                                   # vartablesize
    return nv
end

# ── compiling an argument (pl-comp.c) ───────────────────────────────────────────────────────────
# PORT: pl-comp.c CA_MIDDLE
"`ca_frame` kind: iterating args[0..N-2] of a compound (pl-comp.c)."
const CA_MIDDLE = 0
# PORT: pl-comp.c CA_LAST_POP
"`ca_frame` kind: emit H_POP/B_POP after the last arg (pl-comp.c)."
const CA_LAST_POP = 1

# PORT: pl-comp.c ca_frame
"A resume point of `compileArgument!` (pl-comp.c `ca_frame`)."
struct ca_frame{T}
    kind::Int           # CA_MIDDLE or CA_LAST_POP
    where_::Int         # args' where flag (A_ARG set)
    isright::Bool       # isright from OLD where
    args_base::T        # for CA_MIDDLE: the compound
    off::Int            # for CA_MIDDLE: child index of args[0] (see `_comp_shape`)
    next_idx::Int       # for CA_MIDDLE: next arg index
    last_idx::Int       # for CA_MIDDLE: arity-1
end

# PORT: pl-comp.c compileArgument
# DIVERGES: the head side (`where` without A_BODY, no `islocal`). SWI-7's `[]` compiles to `H_NIL`
# (Q1), any other symbol to `H_ATOM`; a grounded value compiles to `H_ATOM` whose operand is its
# index key — `clean_index_key(gnd_key)`, 0 when it has none (no H_SMALLINT/H_FLOAT/H_STRING/H_MPZ
# yet: V1's literal operands); a list cell is the compound it is (no H_LIST/H_RLIST/H_LIST_FF yet —
# the index reads those the same way); a functor operand is a hashed word (`_functor_word`), not a
# functor-table handle; and a compound whose head is not a symbol compiles as `H_FUNCTOR $expr/n`
# (Q2, `expr_functor`, src/pl-ressymbol.jl) with every child as an argument.
"""
Emit the head code for argument `arg` (pl-comp.c): left to right, a compound's last argument
`A_RIGHT` (`H_RFUNCTOR`, no `H_POP` of its own), resume points on an explicit stack.
"""
function compileArgument!(ci::compileInfo, arg, where_::Int)::Bool
    T = term_type(arg)
    stack = ca_frame{T}[]
    isright = false
    @label next_arg
    k = kind(arg)
    if k === VAR
        index = isIndexedVarTerm(ci, arg)
        if index < 0                                           # a void
            Output_0!(ci, H_VOID)
            @goto resume
        end
        first = isFirstVarSet!(ci.used_var, index)
        if index < ci.arity                                    # variable on its own in the head
            if (where_ & A_ARG) == 0
                if first
                    Output_0!(ci, H_VOID)
                    @goto resume
                end
            end
            Output_0!(ci, H_VAR)
            Output_a!(ci, VAROFFSET(index))
            @goto resume
        end
        # normal variable (i.e. not shared in the head and non-void)
        Output_0!(ci, first ? H_FIRSTVAR : H_VAR)
        Output_a!(ci, VAROFFSET(index))
        @goto resume
    elseif k === SYM
        if is_nil(arg)                                         # isNil(*arg): SWI-7's reserved []
            Output_0!(ci, H_NIL)
        else
            Output_1!(ci, H_ATOM, MK_ATOM(sym_hash(arg)))
        end
        @goto resume
    elseif k === GND
        g = gnd_key(arg)
        Output_1!(ci, H_ATOM, g === nothing ? word(0) : clean_index_key(g))
        @goto resume
    end
    # a compound
    isright = (where_ & A_RIGHT) != 0
    off, ar = _comp_shape(arg)
    fdef = off == 2 ? _functor_word(_functor_name(child(arg, 1)), ar) : expr_functor(ar)
    Output_1!(ci, isright ? H_RFUNCTOR : H_FUNCTOR, fdef)
    where_ &= ~(A_RIGHT | A_NOARGVAR)
    where_ |= A_ARG
    if ar >= 2
        push!(stack, ca_frame{T}(CA_MIDDLE, where_, isright, arg, off, 1, ar - 1))
        arg = _comp_arg(arg, off, 0)                           # recurse on args[0]
        @goto next_arg
    end
    if ar == 1                                                 # only one arg = last arg
        arg = _comp_arg(arg, off, 0)
        @goto last_arg
    end
    if !isright
        Output_0!(ci, H_POP)
    end
    @goto resume
    @label last_arg
    where_ |= A_RIGHT
    if kind(arg) === VAR && (where_ & (A_BODY | A_ARG)) == 0
        if !isright
            Output_0!(ci, H_POP)
        end
        @goto resume
    end
    if isright
        @goto next_arg                                         # tail-jump on last arg
    end
    push!(stack, ca_frame{T}(CA_LAST_POP, where_, false, arg, 0, 0, 0))
    @goto next_arg
    @label resume
    if isempty(stack)
        return true
    end
    frame = pop!(stack)
    if frame.kind == CA_MIDDLE
        idx = frame.next_idx
        arg = _comp_arg(frame.args_base, frame.off, idx)
        where_ = frame.where_
        isright = frame.isright
        if idx < frame.last_idx                                # still a middle arg
            push!(
                stack,
                ca_frame{T}(
                    CA_MIDDLE, frame.where_, frame.isright, frame.args_base, frame.off,
                    idx + 1, frame.last_idx
                )
            )
            @goto next_arg
        end
        @goto last_arg                                         # idx == last_idx
    end
    Output_0!(ci, H_POP)                                       # CA_LAST_POP
    @goto resume
end

# PORT: pl-comp.c compileClause
# DIVERGES: a fact only (no body: `I_EXITFACT`, `UNIT_CLAUSE`), and no module, warnings or
# resource limits. The clause is created at generation 0; `assertDefinition!` sets the rest.
"""
    compileClause(def, head) -> Clause

Compile the fact `head` of predicate `def`: analyse its variables, emit the code for each
argument left to right, end with `I_EXITFACT` (pl-comp.c).
"""
function compileClause(def::Definition{T}, head::T)::Clause{T} where {T}
    ci = compileInfo(def.arity, code[], Dict{UInt64, VarDef}(), falses(0), nothing, 0)
    nv = analyse_variables!(ci, head)                          # prolog_vars = variables = nv
    initMerge!(ci)
    if ci.arity > 0
        for n in 0:(ci.arity - 1)
            compileArgument!(ci, child(head, n + 2), A_HEAD)
        end
    end
    Output_0!(ci, I_EXITFACT)                                  # fact (for decompiler)
    return Clause{T}(
        def, gen_t(0), gen_t(0), clsize_t(nv), clsize_t(nv), UNIT_CLAUSE, ci.codes, head,
        _head_vars(head)
    )
end

"The distinct variables of `head`, as keys, by first occurrence (pre-order, left to right)."
function _head_vars(head)::Vector{UInt64}
    T = term_type(head)
    out = UInt64[]
    is_ground(head) && return out
    stack = T[head]
    while !isempty(stack)
        t = pop!(stack)
        if kind(t) === VAR
            var_key(t) in out || push!(out, var_key(t))
        elseif kind(t) === EXPR && !is_ground(t)
            for i in nchildren(t):-1:1                  # pushed right to left: popped in order
                push!(stack, child(t, i))
            end
        end
    end
    return out
end

"""
`head` with variable `vars[i]` replaced by a variable of key `base + i - 1`: a copy with fresh
variables. Ground subterms are shared, not copied; a ground head is returned as it is.
"""
function _rename_head(head, vars::Vector{UInt64}, base::UInt64)
    T = term_type(head)
    isempty(vars) && return head
    kind(head) === EXPR || return _renamed(head, vars, base)
    stack = Tuple{T, Vector{T}}[(head, T[])]            # (compound, its children copied so far)
    while true
        node, kids = stack[end]
        i = length(kids) + 1
        if i > nchildren(node)
            pop!(stack)
            r = mk_expr(T, kids)
            isempty(stack) && return r
            push!(stack[end][2], r)
            continue
        end
        c = child(node, i)
        if kind(c) === EXPR && !is_ground(c)
            push!(stack, (c, T[]))
        else
            push!(kids, _renamed(c, vars, base))
        end
    end
end

"Variable `t` as its renamed copy (key `base + i - 1` for `vars[i]`); any other term unchanged."
function _renamed(t, vars::Vector{UInt64}, base::UInt64)
    kind(t) === VAR || return t
    i = findfirst(==(var_key(t)), vars)
    i === nothing &&
        error("_rename_head: variable $(var_key(t)) is not one of the clause's")
    return mk_var(term_type(t), base + UInt64(i - 1))
end

# PORT: pl-comp.c decompileHead
# DIVERGES: INTERIM, until pl-comp.c's body side and pl-vmi.c are ported. Upstream rebuilds the head
# from the clause's CODE, with fresh variables on the global stack, and unifies it with `head`;
# here the clause's stored head is copied with fresh kernel variable keys (`fresh_var_keys!`) and
# unified — one copy per attempt where a call in SWI copies nothing (its compiled head code runs
# against fresh frame slots). A ground head is not copied.
"""
    decompileHead!(ld, clause, head) -> Bool

Unify `head` with a fresh copy of `clause`'s head under the bindings in `ld` (pl-comp.c): the
bindings stay on the trail for the caller to undo.
"""
function decompileHead!(ld::PL_local_data{T}, clause::Clause{T}, head::T)::Bool where {T}
    vars = clause.head_vars
    renamed =
        if isempty(vars)
            clause.head
        else
            _rename_head(clause.head, vars, fresh_var_keys!(length(vars)))
        end
    return pl_unify!(ld, head, renamed)
end

# ── reading code (pl-incl.h, pl-comp.h, pl-comp.c) ──────────────────────────────────────────────
# PORT: pl-incl.h decode
# DIVERGES: takes the position and reads the word there — upstream's `decode(*PC)`; instructions
# are not threaded, so the word IS the instruction, as with upstream's `decode(wam) (wam)`.
"The instruction at `PC` (pl-incl.h)."
decode(PC::Code)::code = PC.codes[PC.pc]

# PORT: pl-comp.h stepPC
"The position of the instruction after the one at `PC` (pl-comp.h)."
stepPC(PC::Code)::Code = Code(PC.codes, PC.pc + 1 + codeTable(decode(PC)).arguments)

# PORT: pl-comp.c skipArgs
# DIVERGES: returns `(position, in_hvoid)` where upstream updates `*in_hvoid` through a pointer;
# and an exact landing at the end of an H_VOID_N run is FIXED (LogicKernel#1, see below).
"""
    skipArgs(PC, skip, in_hvoid) -> (Code, in_hvoid)

Skip `skip` arguments of head code from `PC` (pl-comp.c). Skipping into the middle of an
`H_VOID_N` returns the `H_VOID_N` with `in_hvoid` the voids still to skip, so the next call can
continue in small steps.
"""
function skipArgs(PC::Code, skip::Int, in_hvoid::Int)::Tuple{Code, Int}
    nested = 0
    if in_hvoid != 0
        @assert decode(PC) == H_VOID_N
        if skip > in_hvoid
            skip -= in_hvoid
            in_hvoid = 0
        else
            in_hvoid -= skip
            if in_hvoid == 0
                return (stepPC(PC), in_hvoid)
            end
            return (PC, in_hvoid)
        end
    end
    while true
        c = decode(PC)
        nextPC = stepPC(PC)
        if c == H_FUNCTOR                                       # H_LIST, B_FUNCTOR, B_LIST
            nested += 1
        elseif c == H_RFUNCTOR                                  # H_RLIST, B_RFUNCTOR, B_RLIST
        # continue
        elseif c == H_POP                                       # B_POP
            nested -= 1
            if nested == 0
                skip -= 1
                if skip == 0
                    return (nextPC, in_hvoid)
                end
            end
            if nested < 0
                return (PC, in_hvoid)
            end
        elseif c == H_ATOM || c == H_NIL || c == H_FIRSTVAR || c == H_VAR || c == H_VOID
            if nested == 0
                skip -= 1
                if skip == 0
                    return (nextPC, in_hvoid)
                end
            end
        elseif c == H_VOID_N
            if nested == 0
                skip -= Int(PC.codes[PC.pc + 1])
                # DIVERGES (LogicKernel#1, fixed 2026-10-02): upstream's single `skip <= 0` also
                # catches an EXACT landing (skip == 0) and returns the H_VOID_N itself with
                # in_hvoid 0, so the argument after the voids reads as a void and a later
                # skipArgs counts the run twice. Inside the run the H_VOID_N is right; at its end
                # the target is the next instruction.
                if skip < 0
                    in_hvoid = -skip
                    return (PC, in_hvoid)
                elseif skip == 0
                    return (nextPC, in_hvoid)
                end
            end
        elseif c == I_EXITFACT || c == I_ENTER                  # I_EXIT, T_TRIE_GEN*, I_SSU_*
            return (PC, in_hvoid)
        elseif c == I_NOP || c == I_CHP
            # continue
        else
            error("skipArgs: unexpected instruction $(codeTable(c).name)")   # assert(0)
        end
        PC = nextPC
    end
end

# PORT: pl-comp.c argKey
# DIVERGES: returns the key — 0 where upstream returns false — instead of a flag and an
# out-parameter; an `H_ATOM` holding 0 (a grounded value without a key) is not indexable, and an
# `H_FUNCTOR` of `$expr/n` (Q2, src/pl-ressymbol.jl) is a wildcard, as `indexOfWord` keys it.
"""
    argKey(PC, skip) -> word

The index key of the head argument at `PC` after skipping `skip` arguments; 0 when it cannot be
indexed (pl-comp.c). Upstream keeps it consistent with `indexOfWord`.
"""
function argKey(PC::Code, skip::Int)::word
    if skip > 0
        PC, _ = skipArgs(PC, skip, 0)
    end
    while true
        c = decode(PC)
        PC = Code(PC.codes, PC.pc + 1)                          # PC++
        if c == H_FUNCTOR || c == H_RFUNCTOR
            w = PC.codes[PC.pc]                                 # code2functor(*PC)
            return isExprFunctor(w) ? word(0) : w
        elseif c == H_ATOM
            return PC.codes[PC.pc]                              # code2atom(*PC)
        elseif c == H_NIL
            return ATOM_nil                                     # *key = ATOM_nil
        elseif c == H_FIRSTVAR || c == H_VAR || c == H_VOID || c == H_VOID_N ||
            c == H_POP || c == I_EXITFACT || c == I_ENTER
            return word(0)
        elseif c == I_NOP || c == I_CHP
            # continue
        else
            error("argKey: unexpected instruction $(codeTable(c).name)")     # assert(0)
        end
    end
end

# ── clause/2 (pl-comp.c) ────────────────────────────────────────────────────────────────────────
# PORT: pl-comp.c clause as pl_clause
# DIVERGES: clause/2 with an unbound clause reference only (no clause/3-4 by reference, no module
# context or protected predicates), on facts (the body is `true`); the predicate is given. Each
# answer is a call of `sink(clause)::Bool` (false to cut) with the head's bindings in place in
# `ld`: a sink keeps what it needs with `resolve_term`, because the bindings are undone when it
# returns — where SWI's backtracking would undo them.
"""
    pl_clause!(gd, ld, def, head, sink)

`clause/2` on predicate `def` with head `head` (pl-comp.c): in the generation it starts in, unify
`head` with each clause in turn (`decompileHead!`) and call `sink(clause)` while the bindings hold;
undo them after each.
"""
function pl_clause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::T, sink::S
)::Nothing where {T, S}
    dref = pushPredicateAccessObj!(ld, gd, def)
    popped = false
    try
        gen = dref.generation                           # setGenerationFrameVal()
        chp = ClauseChoice{T}(nothing, word(0))
        cref = firstClause!(ld, head, gen, def, chp)
        while cref !== nothing
            clause = cref.clause::Clause{T}
            m = Mark(ld)
            try
                if decompileHead!(ld, clause, head)
                    if chp.cref === nothing             # the last one: out
                        popPredicateAccess!(ld, def)
                        popped = true
                        sink(clause)
                        return nothing
                    end
                    sink(clause) || return nothing      # FRG_CUTTED
                end
            finally
                Undo!(ld, m)                            # backtracking undoes the answer
            end
            cref = nextClause!(ld, chp, head, gen, def)    # FRG_REDO
        end
    finally
        popped || popPredicateAccess!(ld, def)
    end
    return nothing
end
