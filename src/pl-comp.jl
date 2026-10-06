# UPSTREAM: swipl-devel src/pl-comp.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-comp.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE CLAUSE COMPILER, HEAD SIDE — SWI-Prolog's pl-comp.c as far as compiling the head of a clause:
# the variable analysis of HEAD AND BODY (`analyse_variables!`, `analyseVariables2!` — the body's
# control structures, the branches of `;` and the goal of `\+`, with the control functors of the
# database's global data, src/pl-funct.jl), argument compilation (`compileArgument!`, upstream's
# iterative version), the instruction merging that turns runs of `H_VOID` into `H_VOID_N` and drops
# the voids before `H_POP`/`I_ENTER`/`I_EXITFACT` (`Output_0!`, `mergeInstructions!`, the table of
# `initVMIMerge`), and `compileClause` for a fact; the clause's LITERAL TABLE its operands index
# (V1 L2, below); the head decompiler (`decompile_head!`). Then the code readers the clause index
# uses: `stepPC`, `skipArgs`, `argKey`.
#
# A CLAUSE WITH A BODY is analysed and its head compiled, up to `I_ENTER`
# (`_compile_clause_head!`), but not yet compiled into a clause: its body code (`compileBody`) is
# V2. Until then the body analysis has one caller, test/compile/test_analyse_variables_swipl.jl,
# which compares the head code, every body variable's frame slot and the frame size with swipl's.
#
# WHY THE INDEX READS CODE, NOT TERMS (user, 2026-10-02): SWI computes a clause's index keys from
# this code, and the code's shape changes the result. Reading the code as upstream does keeps the
# kernel's index SWI's — with one deliberate exception: SWI loses the key of an argument that
# directly follows two or more void arguments (`skipArgs`, LogicKernel#1), and that defect is
# FIXED here (user, 2026-10-02), so the kernel indexes those arguments where swipl 10.1.16 does not.
#
# NOT PORTED: `islocal` compilation (goal clauses for the meta-call: `subclausearg`, `argvars`,
# `link_local_var`; V9), SSU (`=>`) clauses,
# the moved head unifications (`head_unify`, `annotate_unification`, `argMoveUnify`/`argUnifiedTo`,
# `isUnifiedArg`: they come with O_COMPILE_IS's inline unification, V9 — until then the kernel
# compiles what swipl compiles with `optimise_unify` false), and singleton, multiton and branch
# warnings (the `VD_*` flags). The body compiler is ported since V2, and the instructions run in the
# VM since V4a (src/pl-wam.jl).

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

# PORT: pl-comp.c branch_var
# DIVERGES: no `saved_flags` — the flags a branch saves are the warnings' (`VD_*`, not ported).
"A variable met inside a branch of `;` or the goal of `\\+` (pl-comp.c `branch_var`)."
mutable struct branch_var
    vdef::VarDef        # Definition record
    saved_times::Int    # Times saved from left branch
end

# PORT: pl-comp.c cutInfo
"How `!` compiles in the current context (pl-comp.c `cutInfo`): `var` 0 is a clause-level cut, `I_CUT`."
struct cutInfo
    var::Int                # Variable for local cuts
    nextvar::Int
    instruction::code       # Instruction to use: C_CUT/C_LCUT
end

# PORT: pl-comp.c compileInfo
# DIVERGES: the fields the head compiler, the variable analysis and the call operands use;
# `vardefs` is upstream's LD->comp.vardefs keyed by `var_key`, `mstate_candidates`/
# `mstate_merge_pos` are `mstate`, `used_var` is the VarTable (`vartablesize` its length),
# `branch_vars` is `nothing` or the vector upstream keeps in `branch_varbuf`, `literals` the
# clause's literal table as it is built (since V1 L2), and `procedures` its procedure table (since V1). No
# `clause` (the clause is created after the code), and the fields of subsystems not yet ported:
# `islocal`, `subclausearg`, `head_unify`, `argvars`, `argvar` (V9), `singletons` and the warnings,
# `progress` (interrupts), `colon_context` and `at_context` (modules). `cut` is a clause-level cut
# (`var` 0) until the control constructs set a local one (V9). `module_` is
# upstream's `module`, a Julia keyword.
"The state of one clause compilation (pl-comp.c `compileInfo`)."
mutable struct compileInfo{T}
    const module_::module_t{T}                              # module: module to compile into
    const procedure::Procedure{T}                           # Procedure it belongs to
    arity::Int                                              # arity of top-goal
    codes::Vector{code}                                     # scratch code table
    vardefs::Dict{UInt64, VarDef}                           # variables with a slot
    used_var::BitVector                                     # boolean array of used variables
    mstate_candidates::Union{Nothing, NTuple{4, vmi_merge}} # Merge candidates
    mstate_merge_pos::Int                                   # The merge candidate location
    literals::Vector{T}                                     # the literal table being built
    procedures::Vector{Procedure{T}}                        # the procedure table being built
    branch_vars::Union{Nothing, Vector{branch_var}}         # We are in a branch
    cut::cutInfo                                            # how to compile !
end

"""
A fresh compilation, into module `m`, of a clause of procedure `proc`, whose predicate has `arity`
arguments (pl-comp.c `compileClause`).
"""
compileInfo{T}(arity::Int, m::module_t{T}, proc::Procedure{T}) where {T} =
    compileInfo{T}(
        m, proc, arity, code[], Dict{UInt64, VarDef}(), falses(0), nothing, 0, T[],
        Procedure{T}[], nothing, cutInfo(0, 0, code(0))          # ci->cut.var = 0 (c:2068)
    )

# PORT: pl-comp.c pushBranchVar
"Record that variable `v` was met in the current branch (pl-comp.c)."
function pushBranchVar!(ci::compileInfo, v::VarDef)::Nothing
    bvs = ci.branch_vars
    bvs === nothing && error("pushBranchVar: not in a branch")
    push!(bvs, branch_var(v, 0))
    return nothing
end

# PORT: pl-comp.c is_portable_smallint
# DIVERGES: takes the integer, not a cell — `isTaggedInt(w)` is then "within the tagged range" — and
# the local data explicitly, where upstream reaches `LD` for the flag.
"""
    is_portable_smallint(ld, i::Int64) -> Bool

Whether integer `i` may be an inline operand of a BODY instruction (pl-comp.c): it fits a tagged
word, and — under the `portable_vmi` flag, swipl's default — the int32 range too, so the code runs
on 32-bit VMs. Upstream uses it for `A_ADD_FC` (body arithmetic, c:3666) only. A HEAD integer is
chosen by STORAGE instead — tagged → `H_SMALLINT`, else `H_MPZ` (`_gnd_head_code`) — whatever the
flag: swipl 10.1.16's `vm_list` is identical under `portable_vmi` true and false, and puts
`2147483648` in an `h_smallint` (probed 2026-10-04).
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

# PORT: pl-comp.c is_portable_constant
# DIVERGES: takes the term, not a word — an atom is `isAtom`; a tagged integer is `isTaggedInt`, and
# under `portable_vmi` its WORD must survive int32 (`(word)(sword)(int32_t)c == w`; 64-bit, so
# `SIZEOF_CODE == SIZEOF_WORD`): the integer shifted by LMASK_BITS fits 32 bits, i.e.
# `PLMINTAGGEDINT32 <= i <= PLMAXTAGGEDINT32` (±2^24; probed, memo § 0.6).
"""
    is_portable_constant(ld, w) -> Bool

Whether `w` stays the same as an inline code operand, and in 32-bit code under `portable_vmi`
(pl-comp.c): an atom, or a tagged integer within ±2^24 under the flag, any tagged one without it.
"""
function is_portable_constant(ld::PL_local_data, w)::Bool
    isAtom(w) && return true
    if isTaggedInt(w)
        if ld.prolog_flag_portable_vmi
            return PLMINTAGGEDINT32 <= int64_value(w) <= PLMAXTAGGEDINT32
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
                Output_n!(ci, mm.merge_op, (mm.merge_av,), mm.merge_ac)
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

# PORT: pl-comp.c Output_2
"Emit instruction `c` with two operands (pl-comp.c)."
function Output_2!(ci::compileInfo, c::code, a0::code, a1::code)::Nothing
    Output_1!(ci, c, a0)
    Output_a!(ci, a1)
    return nothing
end

# PORT: pl-comp.c Output_3
"Emit instruction `c` with three operands (pl-comp.c)."
function Output_3!(ci::compileInfo, c::code, a0::code, a1::code, a2::code)::Nothing
    Output_2!(ci, c, a0, a1)
    Output_a!(ci, a2)
    return nothing
end

# PORT: pl-comp.c Output_an
# DIVERGES: `p` is a tuple of operand words where upstream passes a pointer to them.
"Emit the first `n` operand words of `p` (pl-comp.c)."
function Output_an!(ci::compileInfo, p::NTuple{N, code}, n::Int)::Nothing where {N}
    0 <= n <= N || throw(ArgumentError("Output_an: $n operands of $N"))
    for i in 1:n
        push!(ci.codes, p[i])
    end
    return nothing
end

# PORT: pl-comp.c Output_n
# DIVERGES: `p` is a tuple of operand words where upstream passes a pointer to them.
"Emit instruction `c` with the first `n` operand words of `p` (pl-comp.c)."
function Output_n!(ci::compileInfo, c::code, p::NTuple{N, code}, n::Int)::Nothing where {N}
    Output_0!(ci, c)
    Output_an!(ci, p, n)
    return nothing
end

"""
    NotPortedError{T}(culprit, what, step)

Raised where the clause compiler meets a construct whose compilation is not ported yet — `what`,
due in plan step `step` (docs/port_inventory.md) — instead of compiling it as something else:
upstream compiles each of them differently, so falling through would be wrong code.
"""
struct NotPortedError{T} <: Exception
    culprit::T
    what::String
    step::String
end

# PORT: pl-comp.c isFirstVarSet
"Mark variable slot `n` used; true when this is its first use (pl-comp.c)."
function isFirstVarSet!(vt::BitVector, n::Int)::Bool
    if vt[n + 1]
        return false
    end
    vt[n + 1] = true
    return true
end

# PORT: pl-comp.c isFirstVar
"True when variable slot `n` is not used yet (pl-comp.c)."
isFirstVar(vt::BitVector, n::Int)::Bool = !vt[n + 1]

# PORT: pl-comp.c isIndexedVarTerm
"The frame offset of the analysed variable `t`, or -1 for a void (pl-comp.c)."
function isIndexedVarTerm(ci::compileInfo, t)::Int
    vd = get(ci.vardefs, var_key(t), nothing)
    if vd === nothing
        return -1
    end
    return vd.offset
end

# PORT: pl-comp.c isFirstVarP
# DIVERGES: returns the slot, or -1 where upstream fails, instead of a flag and an out-parameter.
"""
The slot of `t` when it is a clause variable (not an argument) at its FIRST occurrence, else -1
(pl-comp.c).
"""
function isFirstVarP(ci::compileInfo, t)::Int
    kind(t) === VAR || return -1
    idx = isIndexedVarTerm(ci, t)
    if idx >= 0 && idx >= ci.arity && isFirstVar(ci.used_var, idx)
        return idx
    end
    return -1
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

# PORT: pl-comp.c MAX_VARIABLES
"Most variables a clause may have: stay safely under signed int (pl-comp.c)."
const MAX_VARIABLES = 1_000_000_000

# PORT: pl-comp.c AV_ARG_LOOP
"`av_frame` kind: general N-arg descent (pl-comp.c `av_kind`)."
const AV_ARG_LOOP = 0
# PORT: pl-comp.c AV_SEMI_AFTER_LEFT
"`av_frame` kind: `(A;B)` after A — save and reset A's variables, then B (pl-comp.c `av_kind`)."
const AV_SEMI_AFTER_LEFT = 2
# PORT: pl-comp.c AV_SEMI_AFTER_RIGHT
"`av_frame` kind: `(A;B)` after B — each variable of the branches counts as in ONE (pl-comp.c)."
const AV_SEMI_AFTER_RIGHT = 3
# PORT: pl-comp.c AV_NOT_AFTER
"`av_frame` kind: `(\\+ A)` after A (pl-comp.c `av_kind`)."
const AV_NOT_AFTER = 4

# PORT: pl-comp.c av_frame
# DIVERGES: `base`/`off`/`next` stand for `head_next`, a pointer into the arguments; `obv` is
# whether a branch buffer existed when the frame was pushed (upstream keeps the pointer); no
# `depth_before_entry` (there is no cycle check, see `analyseVariables2!`). AV_SUBCLAUSE_LOOP is
# `islocal`'s, not ported.
"A compound whose arguments the analysis is walking (pl-comp.c `av_frame`)."
struct av_frame{T}
    kind::Int               # AV_ARG_LOOP, AV_SEMI_AFTER_LEFT, AV_SEMI_AFTER_RIGHT, AV_NOT_AFTER
    base::T                 # the compound (the enclosing term `f` for SEMI/NOT)
    off::Int                # child index of its argument 0 (see `_comp_shape`)
    next::Int               # next argument (0-based)
    argn_next::Int          # argn to pass for the next iteration
    remaining::Int          # args still to process (incl. current)
    control::Bool           # control flag to pass down
    obv::Bool               # a previous ci->branch_vars existed (SEMI/NOT)
    start_vars::Int         # entries when frame was pushed (SEMI/NOT)
    at_branch_vars::Int     # entries after left branch (SEMI only)
end

"The representation error past MAX_VARIABLES (pl-comp.c `AVARS_MAX` → `compileClause`'s error)."
_max_frame_size()::Union{} = error("compileClause: representation_error(max_frame_size)")

# PORT: pl-comp.c analyseVariables2
# DIVERGES: no `islocal` (goal clauses: `subclausearg`, `argvars` and AV_SUBCLAUSE_LOOP come with
# the meta-call, V9); no leading-unification annotation (`head_unify`, `annotate_unification`:
# the moved head unifications, V9); no warnings (`VD_*` flags, `singletons`, `name`); no cycle,
# depth or interrupt check — a kernel term is a tree. A compound whose head is not a symbol has every
# child as an argument (see `compileArgument!`). Past MAX_VARIABLES it throws, where upstream returns
# `AVARS_MAX` and unwinds its stack and branch buffer: nothing outside `ci` has changed, and
# `ci` is dropped with the error. The control functors are the global data's (`gd`), where
# upstream reads `CONTROL_F` from GD's functor table (`valueFunctor`).
"""
Walk `head` giving each variable a slot — a variable standing as head argument `i` gets slot `i`,
any other the next slot above the arity — and counting its occurrences (pl-comp.c). With `control`
(a clause body), the arguments of a control functor (`gd.functors_control`) are control too, and a
variable met in the branches of a `;` counts as often as in the branch that has it more often — a
variable introduced in a branch and used once there is a void — while one introduced in the goal
of a `\\+` is not a branch variable of an enclosing `;`. Returns the number of slots above the
arity.
"""
function analyseVariables2!(
    gd::PL_global_data, ci::compileInfo, head, nvars::Int, argn::Int, control::Bool
)::Int
    cf = gd.functors_control                                   # valueFunctor(f)'s CONTROL_F
    T = term_type(head)
    stack = av_frame{T}[]
    @label next_head
    if kind(head) === VAR
        vd = get(ci.vardefs, var_key(head), nothing)
        if vd === nothing
            if argn >= 0 && argn < ci.arity
                index = argn
            else
                nvars >= MAX_VARIABLES && _max_frame_size()
                index = ci.arity + nvars
                nvars += 1
            end
            vd = VarDef(index, -1, 1)
            ci.vardefs[var_key(head)] = vd
            if ci.branch_vars !== nothing
                pushBranchVar!(ci, vd)
            end
        else
            vd.times += 1
            if vd.times == 1 && ci.branch_vars !== nothing      # vd->times++ == 0
                pushBranchVar!(ci, vd)
            end
        end
        @goto resume
    end
    if kind(head) === EXPR
        if control
            # Check for singletons in branches (A;B). These are variables introduced in a
            # branch, used only once in the branch and not used in code after the branches
            # re-unite.
            if _has_functor(head, cf.semicolon, 2)
                obv = ci.branch_vars !== nothing
                bvs = ci.branch_vars
                if bvs === nothing
                    ci.branch_vars = branch_var[]               # initBuffer(&ci->branch_varbuf)
                    start_vars = 0
                else
                    start_vars = length(bvs)
                end
                push!(
                    stack,
                    av_frame{T}(
                        AV_SEMI_AFTER_LEFT, head, 2, 0, argn, 0, control, obv, start_vars, 0
                    )
                )
                head = child(head, 2)                           # &f->arguments[0]
                @goto next_head
            end
            # check \+ Goal for singletons on Goal. These are variables introduced inside the
            # goal and only used once.
            if _has_functor(head, cf.not_provable, 1)
                obv = ci.branch_vars !== nothing
                bvs = ci.branch_vars
                if bvs === nothing
                    ci.branch_vars = branch_var[]
                    start_vars = 0
                else
                    start_vars = length(bvs)
                end
                push!(
                    stack,
                    av_frame{T}(
                        AV_NOT_AFTER, head, 2, 0, argn, 0, control, obv, start_vars, 0
                    )
                )
                head = child(head, 2)                           # &f->arguments[0]
                @goto next_head
            end
        end
        # The default term processing case
        off, ar = _comp_shape(head)
        if ar > 0
            new_control = control && _is_control(head, cf)
            next_argn = argn < 0 ? 0 : ci.arity
            push!(
                stack,
                av_frame{T}(
                    AV_ARG_LOOP, head, off, 0, next_argn, ar, new_control, false, 0, 0
                )
            )
        end
    end
    @label resume
    if isempty(stack)
        return nvars
    end
    top = stack[end]
    if top.kind == AV_ARG_LOOP
        if top.remaining > 0
            head = _comp_arg(top.base, top.off, top.next)
            argn = top.argn_next
            control = top.control
            stack[end] = av_frame{T}(
                AV_ARG_LOOP, top.base, top.off, top.next + 1, top.argn_next + 1,
                top.remaining - 1, top.control, false, 0, 0
            )
            @goto next_head
        end
        pop!(stack)
        @goto resume
    elseif top.kind == AV_SEMI_AFTER_LEFT
        bvs = ci.branch_vars::Vector{branch_var}
        at_branch_vars = length(bvs)
        for i in (top.start_vars + 1):at_branch_vars            # reset the left branch's vars
            bv = bvs[i]
            bv.saved_times = bv.vdef.times
            bv.vdef.times = 0
        end
        stack[end] = av_frame{T}(
            AV_SEMI_AFTER_RIGHT, top.base, top.off, 0, top.argn_next, 0, top.control,
            top.obv, top.start_vars, at_branch_vars
        )
        head = child(top.base, 3)                               # &f->arguments[1]
        argn = top.argn_next
        control = top.control
        @goto next_head
    elseif top.kind == AV_SEMI_AFTER_RIGHT
        bvs = ci.branch_vars::Vector{branch_var}
        at_end_vars = length(bvs)
        for i in (top.start_vars + 1):at_end_vars
            bv = bvs[i]
            vd = bv.vdef
            if vd.times < bv.saved_times
                vd.times = bv.saved_times
            end
            bv.saved_times = 0
        end
        if !top.obv
            ci.branch_vars = nothing                            # discardBuffer(ci->branch_vars)
        end
        pop!(stack)
        @goto resume
    end
    # AV_NOT_AFTER (its VD_SINGLETON marking is a warning's)
    if !top.obv
        ci.branch_vars = nothing
    else
        resize!(ci.branch_vars::Vector{branch_var}, top.start_vars)   # seekBuffer(start_vars)
    end
    pop!(stack)
    @goto resume
end

# PORT: pl-comp.c analyse_variables
# DIVERGES: `argvars` is 0 (it counts only for `islocal` goal clauses, V9), and there are no
# `$variable_names` or warnings. Returns the frame size `nv`, which `compileClause` records as the
# clause's `variables` and `prolog_vars` (upstream sets them here, through `ci->clause`); past
# MAX_VARIABLES it throws `representation_error(max_frame_size)`. The global data `gd` is passed in
# for the body's control functors (see `analyseVariables2!`).
"""
Analyse the variables of `head` and `body` (`nothing` for a fact) of a clause of the database
whose global data is `gd`: a variable that occurs once —
counting the branches of a `;` as one — becomes a void (no slot); the others get their frame offset,
walking the slots in order and COMPACTING past every void above the arity — an argument keeps its
slot whatever it holds (pl-comp.c). Returns the frame size.
"""
function analyse_variables!(
    gd::PL_global_data{T}, ci::compileInfo{T}, head::T, body::Union{Nothing, T}
)::Int where {T}
    arity = ci.arity
    argvars = 0
    body_voids = 0
    ci.branch_vars = nothing
    nvars = analyseVariables2!(gd, ci, head, 0, -1, false)
    if body !== nothing
        nvars = analyseVariables2!(gd, ci, body, nvars, arity, true)
    end
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
    nv > MAX_VARIABLES && _max_frame_size()
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

# PORT: pl-comp.c FUNCTOR_dot2
# DIVERGES: upstream's `FUNCTOR_dot2` is the handle of SWI-7's list constructor `'[|]'/2` in the
# functor table (generated from src/ATOMS; pl-comp.c uses it); the kernel has none, so it is a fixed
# functor word of its own — what `argKey` reads from `H_LIST`/`H_RLIST`/`H_LIST_FF` and `indexOfWord`
# gives every list cell (`is_pair`), distinct from the key of any other `name/2` but by chance, as
# any two keys (user, 2026-10-04). `listSupervisor` takes this key and `ATOM_nil` as IDENTITY, so a
# hashed key equal to either is excluded by construction (`_unreserved`, src/pl-index.jl; the
# divergence audit, S05).
"The key of a list cell `'[|]'/2`: what `argKey` reads from `H_LIST*` and `indexOfWord` gives `[H|T]`."
const FUNCTOR_dot2 = MK_FUNCTOR(UInt64(0x0004_c495_354e_4f43), UInt64(2))   # "LISTCONS"-ish, arity 2

# PORT: pl-comp.c compileListFF
"""
A list cell `[X|Y]` of two distinct first-occurrence clause variables compiles to ONE instruction,
`H_LIST_FF X Y` (pl-comp.c): true when it did.
"""
function compileListFF!(ci::compileInfo, arg)::Bool
    i1 = isFirstVarP(ci, child(arg, 2))
    i1 < 0 && return false
    i2 = isFirstVarP(ci, child(arg, 3))
    (i2 < 0 || i1 == i2) && return false
    isFirstVarSet!(ci.used_var, i1)
    isFirstVarSet!(ci.used_var, i2)
    Output_2!(ci, H_LIST_FF, VAROFFSET(i1), VAROFFSET(i2))
    return true
end

# ── the literal table (V1 L2) ───────────────────────────────────────────────────────────────────
# DIVERGES from upstream's operands (decision 2; user, 2026-10-04: approved). Upstream's head operand
# IS the constant: an atom handle (`H_ATOM`), a functor handle (`H_FUNCTOR`), a tagged integer
# (`H_SMALLINT`), or the number or text itself, inline in the code (`H_MPZ`, `H_MPQ`, `H_FLOAT`,
# `H_STRING`). The kernel has no atom or functor table and its terms are not cells, so a clause keeps
# the terms themselves in a per-clause LITERAL TABLE and the operand is the (1-based) index of one:
#   * `H_ATOM`, `H_SMALLINT`, `H_MPZ`, `H_MPQ`, `H_FLOAT`, `H_STRING` — `literals[op]` is the very
#     term the clause held there, so decompiling restores its exact kind (`1` and `1.0`, `[]` and
#     `'[]'` never collapse) and the VM compares by identity (`sym_key`, `gnd_equal`);
#   * `H_FUNCTOR`, `H_RFUNCTOR` — ONE packed operand, `functor_operand(i, arity)`: the literal that
#     holds the head symbol, and the arity; literal 0 for `$expr/n` (Q2), which has no head symbol;
#   * a grounded value SWI has no type for (NUM_OTHER) is an `H_ATOM` whose literal is that value —
#     an OPAQUE literal, compared by `gnd_equal`. SWI's nearest case is a blob, an atom compared by
#     handle; this one has no SWI counterpart.
# The index keys are DERIVED from the literal (`argKey` → `indexOfWord`), so they are the keys the
# kernel had before the table. An instruction merge never drops an instruction with a literal (only
# `H_VOID`, `H_VOID_N`, `H_POP` and `I_EXITFACT` merge), so the table needs no rollback.
"Append `t` to the literal table being built; its index, as an operand (V1 L2)."
function addLiteral!(ci::compileInfo{T}, t::T)::code where {T}
    push!(ci.literals, t)
    return code(length(ci.literals))
end

# ── procedure operands (V1) ─────────────────────────────────────────────────────────────────────
# DIVERGES (user, 2026-10-04): upstream's call operand (`CA1_PROC`: `I_CALL`, `I_DEPART`, `I_LCALL`,
# …) is the `Procedure` pointer itself (`ptr2code(proc)`, c:3604-3630). Here it is an index into
# the clause's PROCEDURE TABLE (`clause.procedures`, 1-based), as a literal operand indexes the
# literal table: decoding a clause's code needs nothing outside the clause. Every entry is the
# database's own procedure — the one `lookupBodyProcedure` returns — so two clauses calling `p/1`
# hold the same `Procedure`; a differential compares procedures by name and arity, never by index.
"Append `proc` to the procedure table being built; its index, as an operand (V1)."
function addProcedure!(ci::compileInfo{T}, proc::Procedure{T})::code where {T}
    push!(ci.procedures, proc)
    return code(length(ci.procedures))
end

"""
    CallableTypeError{T}(culprit)

Raised where SWI-Prolog raises `error(type_error(callable, Culprit), _)`: a body goal that is not
callable (pl-comp.c `NOT_CALLABLE`).
"""
struct CallableTypeError{T} <: Exception
    culprit::T
end

"""
The functor `(name, arity)` — the name symbol — of a callable body goal: a text atom, or a compound
whose name is a text atom or `[]`; arity -1 when the goal is not callable (pl-comp.c
`compileSubClause`, c:3464-3559). `T` is the database's term type, given — not the goal's own
type, which an implementation may make a leaf of it (`term_type`).
"""
function _body_functor(::Type{T}, goal::T)::Tuple{T, Int} where {T}
    if kind(goal) === EXPR
        nchildren(goal) >= 1 || return (goal, -1)               # `$expr/0`: no head
        h = child(goal, 1)
        kind(h) === SYM || return (goal, -1)                    # `$expr/n`: the meta-call (V9)
        # !isTextAtom(fdef->name) && fdef->name != ATOM_nil
        is_reserved_symbol(h) && !is_nil(h) && return (goal, -1)
        return (h, nchildren(goal) - 1)
    elseif kind(goal) === SYM
        is_reserved_symbol(goal) && return (goal, -1)           # isTextAtom(*arg): not `[]`
        return (goal, 0)
    end
    return (goal, -1)                                          # a number, a string, a variable
end

# PORT: pl-comp.c lookupBodyProcedure
# DIVERGES: takes the GOAL, not its functor — a goal whose head is not a symbol (`$expr/n`, Q2)
# has no functor; it is a call through the meta-call (V9), so it is refused here with
# `type_error(callable, Goal)`, as are the other goals compileSubClause finds NOT_CALLABLE (a
# number, a string, `[]`, a compound named by a reserved symbol other than `[]`; probed in swipl
# 10.1.16: `assertz((p :- 1))`, `(p :- "s")`, `(p :- [])` raise it, `(p :- '[]')` does not) (user,
# 2026-10-04). The branch that prefers an ISO system predicate is ported since V5a2, when built-ins
# came to be registered in the `system` module; there is no boot session (`GD->bootsession` is
# always false).
"""
    lookupBodyProcedure(gd, goal, tm) -> Procedure{T}

The procedure body goal `goal` calls in module `tm` of the database whose global data is `gd`: the
current one if it is defined or redefined, else the `system` module's if it is an ISO built-in,
else the one `lookupProcedure` finds or creates (pl-comp.c). Throws [`CallableTypeError`](@ref) for a goal that is not callable.
"""
function lookupBodyProcedure(
    gd::PL_global_data{T}, goal::T, tm::module_t{T}
)::Procedure{T} where {T}
    name, arity = _body_functor(T, goal)
    arity < 0 && throw(CallableTypeError{T}(goal))
    proc = isCurrentProcedure(sym_key(name), arity, tm)
    if proc !== nothing &&
        (isDefinedProcedure(gd, proc) || (proc.definition.flags & P_REDEFINED) != 0)
        return proc
    end
    if tm !== MODULE_system(gd)
        sp = isCurrentProcedure(sym_key(name), arity, MODULE_system(gd))
        if sp !== nothing && (sp.definition.flags & P_ISO) != 0      # && !GD->bootsession
            return sp
        end
    end
    return lookupProcedure(name, arity, tm)
end

const _OPERAND_HALF = code(typemax(UInt32))

"The `H_FUNCTOR`/`H_RFUNCTOR` operand naming literal `i` (0: `\$expr/n`) and `arity` (V1 L2)."
function functor_operand(i::code, arity::Int)::code
    (i <= _OPERAND_HALF && 0 <= arity && code(arity) <= _OPERAND_HALF) ||
        throw(ArgumentError("functor_operand: literal $i or arity $arity beyond 32 bits"))
    return (i << 32) | code(arity)
end
"The literal index an `H_FUNCTOR` operand names: 0 for `\$expr/n` (V1 L2)."
functor_literal(op::code)::Int = Int(op >> 32)
"The arity an `H_FUNCTOR` operand holds (V1 L2)."
functor_arity(op::code)::Int = Int(op & _OPERAND_HALF)

# From pl-comp.c compileArgument (`TAG_INTEGER`, `TAG_FLOAT`, `TAG_STRING`): the instruction of a
# grounded value, in a head or a body, each choice keyed as upstream keys it (`A_BODY` for SMALLINT
# and FLOAT, `A_HEAD` for MPZ, MPQ and STRING). A number by its SEMANTIC kind (Q1); an integer by its
# STORAGE, as upstream — tagged (`PLMINTAGGEDINT`..`PLMAXTAGGEDINT`, `STG_INLINE`) is SMALLINT, any
# other MPZ (swipl 10.1.16: 2^56-1 and -2^56 are h_smallint, 2^56, -2^56-1 and 2^63-1 h_mpz,
# probed). Anything else is STRING for a string (the kind query's NUM_STRING, user 2026-10-04); any
# other grounded value (NUM_OTHER, no SWI type) an ATOM: an opaque literal compared by `gnd_equal`.
"The instruction of grounded value `t` in a head or (`where_ & A_BODY`) a body (pl-comp.c `compileArgument`)."
function _gnd_code(t, where_::Int)::code
    nk = number_kind(t)
    body = (where_ & A_BODY) != 0
    head = (where_ & A_HEAD) != 0
    if nk === NUM_INTEGER
        if integer_is_int64(t) && PLMINTAGGEDINT <= int64_value(t) <= PLMAXTAGGEDINT
            return body ? B_SMALLINT : H_SMALLINT              # storage(*arg) == STG_INLINE
        end
        return head ? H_MPZ : B_MPZ
    elseif nk === NUM_RATIONAL
        return head ? H_MPQ : B_MPQ                            # isMPQNum(*arg)
    elseif nk === NUM_FLOAT
        return body ? B_FLOAT : H_FLOAT
    elseif nk === NUM_STRING
        return head ? H_STRING : B_STRING                      # TAG_STRING
    end
    return body ? B_ATOM : H_ATOM                              # NUM_OTHER: an opaque literal
end

# PORT: pl-comp.c compileArgument
# DIVERGES: no `islocal` (goal clauses: `link_local_var`, `argvar`, `subclausearg`; V9), no
# attributed variables, no `CL_HEAD_TERMS`/`argMoveUnify` (the moved head unifications, V9), and no
# stack-overflow returns. SWI-7's `[]` compiles to `H_NIL`/`B_NIL` (Q1), any other symbol to
# `H_ATOM`/`B_ATOM`; a grounded value to the SMALLINT/MPZ/MPQ/FLOAT/STRING instruction of its kind
# and storage (`_gnd_code`), anything else to `*_ATOM`; each operand is the index of the constant
# in the clause's LITERAL TABLE (since V1 L2). A list cell (`is_pair`, upstream's `fdef == FUNCTOR_dot2`)
# compiles to `*_LIST`/`*_RLIST`, or in a head `H_LIST_FF` when both its children are fresh clause
# variables; any other compound to `*_FUNCTOR`/`*_RFUNCTOR` with the packed operand of its head
# symbol's literal and its arity, and a compound whose head is not a symbol as `*_FUNCTOR $expr/n`
# (Q2, src/pl-ressymbol.jl) — literal 0 — with every child as an argument. Each head/body choice is
# keyed as upstream keys it (some on `A_BODY`, some on `A_HEAD`).
"""
Emit the code for argument `arg` (pl-comp.c): in a head (`A_HEAD`) the instructions that unify it,
in a body (`A_BODY`) those that build it as the next argument of a call; left to right, a
compound's last argument `A_RIGHT` (`*_RFUNCTOR`, no pop of its own), resume points on an explicit
stack.
"""
function compileArgument!(ci::compileInfo{T}, arg::T, where_::Int)::Bool where {T}
    stack = ca_frame{T}[]
    isright = false
    @label next_arg
    k = kind(arg)
    if k === VAR
        index = isIndexedVarTerm(ci, arg)
        if index < 0                                           # a void
            Output_0!(ci, (where_ & A_BODY) != 0 ? B_VOID : H_VOID)
            @goto resume
        end
        first = isFirstVarSet!(ci.used_var, index)
        if index < ci.arity                                    # variable on its own in the head
            if (where_ & A_BODY) != 0
                if (where_ & A_ARG) != 0
                    Output_0!(ci, B_ARGVAR)
                else
                    if index < 3
                        Output_0!(ci, B_VAR0 + code(index))
                        @goto resume
                    end
                    Output_0!(ci, B_VAR)
                end
            else                                               # head
                if (where_ & A_ARG) == 0
                    if first
                        Output_0!(ci, H_VOID)
                        @goto resume
                    end
                end
                Output_0!(ci, H_VAR)
            end
            Output_a!(ci, VAROFFSET(index))
            @goto resume
        end
        # normal variable (i.e. not shared in the head and non-void)
        if (where_ & A_BODY) != 0
            if (where_ & A_ARG) != 0
                Output_0!(ci, first ? B_ARGFIRSTVAR : B_ARGVAR)
            else
                if index < 3 && !first
                    Output_0!(ci, B_VAR0 + code(index))
                    @goto resume
                end
                Output_0!(ci, first ? B_FIRSTVAR : B_VAR)
            end
        else
            Output_0!(ci, first ? H_FIRSTVAR : H_VAR)
        end
        Output_a!(ci, VAROFFSET(index))
        @goto resume
    elseif k === SYM
        if is_nil(arg)                                         # isNil(*arg): SWI-7's reserved []
            Output_0!(ci, (where_ & A_BODY) != 0 ? B_NIL : H_NIL)
        else
            Output_1!(ci, (where_ & A_BODY) != 0 ? B_ATOM : H_ATOM, addLiteral!(ci, arg))
        end
        @goto resume
    elseif k === GND
        Output_1!(ci, _gnd_code(arg, where_), addLiteral!(ci, arg))
        @goto resume
    end
    # a compound
    isright = (where_ & A_RIGHT) != 0
    off, ar = _comp_shape(arg)
    if is_pair(arg)                                            # fdef == FUNCTOR_dot2
        if (where_ & A_HEAD) != 0                              # index in array!
            if compileListFF!(ci, arg)
                @goto resume
            end
            Output_0!(ci, isright ? H_RLIST : H_LIST)
        else
            Output_0!(ci, isright ? B_RLIST : B_LIST)
        end
    else
        lit = off == 2 ? addLiteral!(ci, child(arg, 1)) : code(0)    # `$expr/n`: no literal
        fdef = functor_operand(lit, ar)
        if (where_ & A_HEAD) != 0                              # index in array!
            Output_1!(ci, isright ? H_RFUNCTOR : H_FUNCTOR, fdef)
        else
            Output_1!(ci, isright ? B_RFUNCTOR : B_FUNCTOR, fdef)
        end
    end
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
        Output_0!(ci, (where_ & A_HEAD) != 0 ? H_POP : B_POP)
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
    Output_0!(ci, (frame.where_ & A_HEAD) != 0 ? H_POP : B_POP)    # CA_LAST_POP
    @goto resume
end

# ── the body: plain goals, conjunctions, the last call (pl-comp.c) ──────────────────────────────
# PORT: pl-comp.c reverse_code
# DIVERGES: positions in the code vector (1-based, `z` exclusive) instead of pointers.
"Reverse the code words `codes[a:z-1]` in place (pl-comp.c)."
function reverse_code!(codes::Vector{code}, a::Int, z::Int)::Nothing
    z -= 1
    while a < z
        t = codes[a]
        codes[a] = codes[z]
        a += 1
        codes[z] = t
        z -= 1
    end
    return nothing
end

# PORT: pl-comp.c lco
# DIVERGES: positions in the code vector (1-based) instead of pointers, so no FIX_BUFFER_SHIFT; the
# departing call's operand is an index into the clause's procedure table, and `I_LCALL` carries the
# same index, as `L_ATOM`/`L_SMALLINT` carry the `B_*` instruction's literal index (since V1: upstream
# copies the operand word too); no `B_SMALLINTW` (64-bit words) and no `PL_register_atom`.
"""
Last-call optimisation (pl-comp.c) of the goal whose argument code starts at code position `pc0`
and ends with `I_DEPART`: unless an argument cannot move into place — an instruction without
`VIF_LCO`, or a variable whose slot an earlier argument overwrites — put in front of that code an
`L_NOLCO` block that writes each argument straight into the current frame's argument slot and calls
with `I_TCALL` (the clause's own predicate) or `I_LCALL`.
"""
function lco!(ci::compileInfo, pc0::Int)::Nothing
    pcz = PC(ci)
    s0 = pc0 + 1
    s = s0
    e = pcz + 1
    oarg = 0
    ci.codes[e - 2] == I_DEPART || error("lco: the last goal does not end in I_DEPART")   # assert
    Output_1!(ci, L_NOLCO, code(0))
    while s < e - 2
        c = ci.codes[s]
        s += 1
        if (codeTable(c).flags & VIF_LCO) == 0
            resize!(ci.codes, pcz)                             # no_lco: seekBuffer(pcz)
            return nothing
        end
        if c == B_VAR0 || c == B_VAR1 || c == B_VAR2 || c == B_VAR
            if c == B_VAR
                bv = VARNUM(ci.codes[s])
                s += 1
            else
                bv = Int(c - B_VAR0)
            end
            if bv < oarg                                       # would overwrite
                resize!(ci.codes, pcz)
                return nothing
            end
            if bv != oarg
                Output_2!(ci, L_VAR, VAROFFSET(oarg), VAROFFSET(bv))
            end
        elseif c == B_VOID
            Output_1!(ci, L_VOID, VAROFFSET(oarg))
        elseif c == B_SMALLINT
            a = ci.codes[s]
            s += 1
            Output_2!(ci, L_SMALLINT, VAROFFSET(oarg), a)
        elseif c == B_ATOM
            a = ci.codes[s]
            s += 1
            Output_2!(ci, L_ATOM, VAROFFSET(oarg), a)
        elseif c == B_NIL
            Output_1!(ci, L_NIL, VAROFFSET(oarg))
        else
            error("lco: no case for $(codeTable(c).name)")     # assert(0)
        end
        oarg += 1
    end
    depart = ci.codes[e - 1]                                   # depart_proc, as its table index
    if ci.procedure === ci.procedures[depart]
        Output_0!(ci, I_TCALL)
    else
        Output_1!(ci, I_LCALL, depart)
    end
    z = length(ci.codes) + 1                                   # topBuffer
    ci.codes[e + 1] = code(z - e - 2)                          # fill L_NOLCO argument
    reverse_code!(ci.codes, s0, e)
    reverse_code!(ci.codes, e, z)
    reverse_code!(ci.codes, s0, z)
    return nothing
end

# ── the type tests compiled inline (pl-comp.c, O_COMPILE_IS), V6b ────────────────────────────────
# PORT: pl-comp.c always
# DIVERGES: `val` is a Bool for `ATOM_true`/`ATOM_false`. NOT PORTED: the style check's
# `compiler_warning` (`NOEFFECT_CHECK`) — the compiler has no warnings (see `compileClause`).
# Under `optimise` upstream emits `I_TRUE`/`I_FAIL`, V9's instructions: refused.
"""
    always(ld, ci, val, pred, arg) -> boolex_t

A goal whose outcome is known at compile time (pl-comp.c): `BOOLEX_FALSE` — compile it as a call —
unless `optimise` is on, where upstream emits `I_TRUE`/`I_FAIL` (refused: V9).
"""
function always(
    ld::PL_local_data{T}, ci::compileInfo{T}, val::Bool, pred::String, arg::T
)::boolex_t where {T}
    if ld.prolog_flag_optimise                                 # truePrologFlag(PLFLAG_OPTIMISE)
        what = string(val ? "I_TRUE" : "I_FAIL", " for ", pred, "/1 (always, optimise)")
        throw(NotPortedError{T}(arg, what, "V9"))
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyVar1
"`var/1` in a body (pl-comp.c): `I_VAR` on a variable already seen; otherwise as `always` decides."
function compileBodyVar1(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1 = child(arg, 2)                                         # argTermP(*arg, 0)
    i1 = kind(a1) === VAR ? isIndexedVarTerm(ci, a1) : -1
    if kind(a1) === VAR && i1 < 0                              # Singleton: always true
        return always(ld, ci, true, "var", a1)
    end
    if i1 >= 0
        f1 = isFirstVar(ci.used_var, i1)
        if f1                                                  # first var
            return always(ld, ci, true, "var", a1)
        end
        Output_1!(ci, I_VAR, VAROFFSET(i1))
        return BOOLEX_TRUE
    end
    return always(ld, ci, false, "var", a1)
end

# PORT: pl-comp.c compileBodyNonVar1
"`nonvar/1` in a body (pl-comp.c): `I_NONVAR` on a variable already seen; otherwise as `always` decides."
function compileBodyNonVar1(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1 = child(arg, 2)                                         # argTermP(*arg, 0)
    i1 = kind(a1) === VAR ? isIndexedVarTerm(ci, a1) : -1
    if kind(a1) === VAR && i1 < 0                              # Singleton: always false
        return always(ld, ci, false, "nonvar", a1)
    end
    if i1 >= 0
        f1 = isFirstVar(ci.used_var, i1)
        if f1
            return always(ld, ci, false, "nonvar", a1)
        end
        Output_1!(ci, I_NONVAR, VAROFFSET(i1))
        return BOOLEX_TRUE
    end
    return always(ld, ci, true, "nonvar", a1)
end

# PORT: pl-comp.c type_tests
# DIVERGES: the names are in `SubClauseNames.type_tests` (one key per database, as the other names
# compileSubClause tests); this table holds what goes with each, in the same order, and the test
# is `_type_test(k, w)` — a branch on the entry, where upstream holds a function pointer.
"pl-comp.c's `type_tests[]`: the instruction and the name of each type test compiled inline."
const type_tests = (
    (I_INTEGER, "integer"), (I_RATIONAL, "rational"), (I_FLOAT, "float"),
    (I_NUMBER, "number"),
    (I_ATOMIC, "atomic"), (I_ATOM, "atom"), (I_STRING, "string"), (I_COMPOUND, "compound"),
    (I_CALLABLE, "callable")
)

# The test of `type_tests` entry `k` on `w` (upstream's `fisInteger` … `fisCallable`).
function _type_test(k::Int, w)::Bool
    k == 1 && return isInteger(w)                              # fisInteger
    k == 2 && return isRational(w)                             # fisRational
    k == 3 && return isFloat(w)                                # fisFloat
    k == 4 && return isNumber(w)                               # fisNumber
    k == 5 && return isAtomic(w)                               # fisAtomic
    k == 6 && return isTextAtom(w)                             # fisAtom
    k == 7 && return isString(w)                               # fisString
    k == 8 && return isTerm(w)                                 # fisCompound
    return isCallable(w)                                       # fisCallable
end

# PORT: pl-comp.c compileTypeTest
# DIVERGES: the test is `type_tests` entry `k` (see there). The first-variable branch's `C_VAR` is
# V9's: refused — reached only under `optimise`, where `always` refuses first.
"""
A type test in a body (pl-comp.c): its `I_<TEST>` on a variable already seen; a void, a first
occurrence or a non-variable as `always` decides (a call unless `optimise`).
"""
function compileTypeTest(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T, k::Int
)::boolex_t where {T}
    instruction, name = type_tests[k]
    a1 = child(arg, 2)                                         # argTermP(*arg, 0)
    i1 = kind(a1) === VAR ? isIndexedVarTerm(ci, a1) : -1
    if kind(a1) === VAR && i1 < 0                              # Singleton: always false
        return always(ld, ci, false, name, a1)
    end
    if i1 >= 0
        f1 = isFirstVar(ci.used_var, i1)
        if f1
            rc = always(ld, ci, false, name, a1)
            if rc == BOOLEX_TRUE
                # isFirstVarSet(ci->used_var, i1); Output_1(ci, C_VAR, VAROFFSET(i1))
                throw(NotPortedError{T}(a1, "C_VAR (compileTypeTest, optimise)", "V9"))
            end
            return rc
        end
        Output_1!(ci, instruction, VAROFFSET(i1))
        return BOOLEX_TRUE
    end
    if _type_test(k, a1)                                       # (*test)(*a1)
        return always(ld, ci, true, name, a1)
    else
        return always(ld, ci, false, name, a1)
    end
end

# PORT: pl-comp.c compileBodyTypeTest
# DIVERGES: the goal's functor is its name's key (`name`) — the caller has checked arity 1.
"A type test `name/1` in a body (pl-comp.c): `compileTypeTest` for a `type_tests` name, else `BOOLEX_FALSE`."
function compileBodyTypeTest(
    ld::PL_local_data{T}, names::SubClauseNames, name::UInt64, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    for k in 1:length(type_tests)                              # for(tt = type_tests; …)
        if name == names.type_tests[k]
            return compileTypeTest(ld, ci, arg, k)
        end
    end
    return BOOLEX_FALSE
end

# ── the other goals compiled inline (pl-comp.c, O_COMPILE_IS), V6b2 ─────────────────────────────
# Upstream's own decision, compiler by compiler (the memo's Q-1, (a)): every emission is of an
# instruction V9 brings — `I_TRUE`, `I_FAIL`, `C_VAR`, `B_UNIFY_*`, `B_EQ_*`, `B_NEQ_*`, `B_ARG_*`,
# `I_CALLCONT`, `I_SHIFT`, `I_SHIFTCP` — and throws `NotPortedError` where upstream emits it,
# before anything is emitted; each `false` is upstream's, and compiles as a call. A void variable is
# upstream's `isVar(*a)`: a variable the analysis gave no slot. NOT PORTED: the style check's
# `compiler_warning` (`NOEFFECT_CHECK`) — the compiler has no warnings (see `compileClause`).

"Whether `a` is a void variable — upstream's `isVar(*a)` in the compiler: a variable with no slot."
_comp_void(ci::compileInfo, a)::Bool = kind(a) === VAR && isIndexedVarTerm(ci, a) < 0

"The slot of `a` if it is a variable that has one, else -1 (`isIndexedVarTerm`, pl-comp.c)."
_comp_ivar(ci::compileInfo, a)::Int = kind(a) === VAR ? isIndexedVarTerm(ci, a) : -1

# PORT: pl-comp.c compileBodyUnify
# DIVERGES: see the section header. `skippedVar`'s `C_VAR`s precede an `I_TRUE`, so they are refused
# with it. NOT PORTED: `isUnifiedArg`/`argUnifiedTo`, the unifications moved to the head
# (`optimise_unify`, V9): the kernel compiles what swipl compiles with the flag false (the file
# header), so a `Var = Term` is always compiled here — and refused.
"""
`=/2` in a body (pl-comp.c): inline — `I_TRUE` for a void side or `X = X`, `B_UNIFY_FF`/`FV`/`VF`/`VV`
for two variables, `B_UNIFY_FC`/`VC` or `B_UNIFY_FIRSTVAR`/`VAR` … `B_UNIFY_EXIT` for a variable and
a term — all refused (V9); `BOOLEX_FALSE`, a call, for `Term = Term`.
"""
function compileBodyUnify(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1, a2 = child(arg, 2), child(arg, 3)                     # argTermP(*arg, 0), …(1); deRef
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton = ? --> true
        throw(
            NotPortedError{T}(
                arg, "I_TRUE for =/2 with a void side (compileBodyUnify)", "V9"
            )
        )
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # unify two variables
        i1 == i2 &&                                            # unify a var with itself?
            throw(NotPortedError{T}(arg, "I_TRUE for X = X (compileBodyUnify)", "V9"))
        f1, f2 = isFirstVar(ci.used_var, i1), isFirstVar(ci.used_var, i2)
        instr = if f1 && f2
            "B_UNIFY_FF"
        elseif f1
            "B_UNIFY_FV"
        elseif f2
            "B_UNIFY_VF"
        else
            "B_UNIFY_VV"
        end
        throw(NotPortedError{T}(arg, instr * " (compileBodyUnify)", "V9"))
    end
    if i1 >= 0 || i2 >= 0                                      # Var = Term, (Term = Var)
        i, t = i1 >= 0 ? (i1, a2) : (i2, a1)
        first = isFirstVar(ci.used_var, i)
        instr = if is_portable_constant(ld, t)
            first ? "B_UNIFY_FC" : "B_UNIFY_VC"
        else
            (first ? "B_UNIFY_FIRSTVAR" : "B_UNIFY_VAR") * " … B_UNIFY_EXIT"
        end
        throw(NotPortedError{T}(arg, instr * " (compileBodyUnify)", "V9"))
    end
    return BOOLEX_FALSE                                        # Term = Term
end

# PORT: pl-comp.c compileBodyEQ
# DIVERGES: see the section header.
"""
`==/2` in a body (pl-comp.c): inline — `B_EQ_VV` on two variables, `B_EQ_VC` on a variable and a
portable constant (either order), each after a `C_VAR` for a first occurrence; under `optimise`,
`I_FAIL` for a void side, `I_TRUE`/`I_FAIL` for a first occurrence — all refused (V9);
`BOOLEX_FALSE`, a call, otherwise.
"""
function compileBodyEQ(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1, a2 = child(arg, 2), child(arg, 3)
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton == ?: always fail
        ld.prolog_flag_optimise && throw(
            NotPortedError{T}(
                arg, "I_FAIL for ==/2 with a void side (compileBodyEQ, optimise)", "V9"
            )
        )
        return BOOLEX_FALSE                                    # debugging: compile as normal code
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # Var1 == Var2
        f1, f2 = isFirstVar(ci.used_var, i1), isFirstVar(ci.used_var, i2)
        if (f1 || f2) && ld.prolog_flag_optimise
            what = (i1 == i2 ? "I_TRUE" : "I_FAIL") * " for ==/2 (compileBodyEQ, optimise)"
            throw(NotPortedError{T}(arg, what, "V9"))
        end
        throw(NotPortedError{T}(arg, "B_EQ_VV (compileBodyEQ)", "V9"))
    end
    if (i1 >= 0 && is_portable_constant(ld, a2)) ||           # Var == const
        (i2 >= 0 && is_portable_constant(ld, a1))               # const == Var
        throw(NotPortedError{T}(arg, "B_EQ_VC (compileBodyEQ)", "V9"))
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyNEQ
# DIVERGES: see the section header.
"""
`\\==/2` in a body (pl-comp.c): inline — `B_NEQ_VV`, `B_NEQ_VC`, as `compileBodyEQ`; under
`optimise`, `I_TRUE` for a void side, `I_FAIL`/`I_TRUE` for a first occurrence — all refused (V9);
`BOOLEX_FALSE`, a call, otherwise.
"""
function compileBodyNEQ(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1, a2 = child(arg, 2), child(arg, 3)
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton \== ?: always true
        ld.prolog_flag_optimise && throw(
            NotPortedError{T}(
                arg,
                "I_TRUE for \\==/2 with a void side (compileBodyNEQ, optimise)",
                "V9"
            )
        )
        return BOOLEX_FALSE                                    # debugging: compile as normal code
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # Var1 \== Var2
        f1, f2 = isFirstVar(ci.used_var, i1), isFirstVar(ci.used_var, i2)
        if (f1 || f2) && ld.prolog_flag_optimise
            what =
                (i1 == i2 ? "I_FAIL" : "I_TRUE") * " for \\==/2 (compileBodyNEQ, optimise)"
            throw(NotPortedError{T}(arg, what, "V9"))
        end
        throw(NotPortedError{T}(arg, "B_NEQ_VV (compileBodyNEQ)", "V9"))
    end
    if (i1 >= 0 && is_portable_constant(ld, a2)) ||           # Var \== const
        (i2 >= 0 && is_portable_constant(ld, a1))               # const \== Var
        throw(NotPortedError{T}(arg, "B_NEQ_VC (compileBodyNEQ)", "V9"))
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyArg3
# DIVERGES: see the section header.
"""
`arg/3` in a body (pl-comp.c): inline — `B_ARG_CF` for `arg(Int, Var, FirstVar)` (a tagged integer),
`B_ARG_VF` for `arg(Var, Var, FirstVar)` (both variables already seen) — refused (V9);
`BOOLEX_FALSE`, a call, for any other shape.
"""
function compileBodyArg3(ci::compileInfo{T}, arg::T)::boolex_t where {T}
    a1, a2, a3 = child(arg, 2), child(arg, 3), child(arg, 4)  # av[0..2], deRef2
    v3 = _comp_ivar(ci, a3)
    if v3 >= 0 && isFirstVar(ci.used_var, v3)
        v2 = _comp_ivar(ci, a2)
        if v2 >= 0 && !isFirstVar(ci.used_var, v2)
            isTaggedInt(a1) &&
                throw(NotPortedError{T}(arg, "B_ARG_CF (compileBodyArg3)", "V9"))
            v1 = _comp_ivar(ci, a1)
            if v1 >= 0 && !isFirstVar(ci.used_var, v1)
                throw(NotPortedError{T}(arg, "B_ARG_VF (compileBodyArg3)", "V9"))
            end
        end
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyCallContinuation
# DIVERGES: see the section header.
"`\$call_continuation/1` in a body (pl-comp.c): `I_CALLCONT` on a variable already seen — refused (V9)."
function compileBodyCallContinuation(ci::compileInfo{T}, arg::T)::boolex_t where {T}
    i1 = _comp_ivar(ci, child(arg, 2))
    if i1 >= 0 && !isFirstVar(ci.used_var, i1)
        throw(NotPortedError{T}(arg, "I_CALLCONT (compileBodyCallContinuation)", "V9"))
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyShift
# DIVERGES: see the section header.
"""
`\$shift/1` (`for_copy` false) or `\$shift_for_copy/1` (true) in a body (pl-comp.c): `I_SHIFT` or
`I_SHIFTCP` on a variable already seen — refused (V9).
"""
function compileBodyShift(ci::compileInfo{T}, arg::T, for_copy::Bool)::boolex_t where {T}
    i1 = _comp_ivar(ci, child(arg, 2))
    if i1 >= 0 && !isFirstVar(ci.used_var, i1)
        what = (for_copy ? "I_SHIFTCP" : "I_SHIFT") * " (compileBodyShift)"
        throw(NotPortedError{T}(arg, what, "V9"))
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileSimpleAddition
# DIVERGES: the integer operand is a literal, as every literal operand is (src/pl-vmi.jl). The
# clause's terms are resolved (no bindings at compile time), so `deRef` has nothing to do.
"""
`NewVar is Var +/- SmallInt` (pl-comp.c): `A_ADD_FC`, the sum's arguments swapped for `+`; false for
any other shape, which then compiles as a call.
"""
function compileSimpleAddition(
    ld::PL_local_data{T}, names::SubClauseNames, sc::T, ci::compileInfo{T}
)::Bool where {T}
    a = child(sc, 2)                                           # argTermP(*sc, 0)
    rvar = isFirstVarP(ci, a)
    if rvar >= 0                                               # NewVar is ?
        e = child(sc, 3)                                       # a++; deRef(a)
        neg = false
        if _has_functor(e, names.atom_plus, 2) ||
            (neg = _has_functor(e, names.atom_minus, 2))
            a1, a2 = child(e, 2), child(e, 3)
            swapped = 0
            while swapped < 2
                swapped += 1
                vi = kind(a1) === VAR ? isIndexedVarTerm(ci, a1) : -1
                if vi >= 0 && !isFirstVar(ci.used_var, vi) &&
                    number_kind(a2) === NUM_INTEGER && integer_is_int64(a2) &&
                    is_portable_smallint(ld, int64_value(a2))
                    i = int64_value(a2)
                    neg && (i = -i)                            # tagged int: cannot overflow
                    isFirstVarSet!(ci.used_var, rvar)
                    Output_3!(
                        ci, A_ADD_FC, VAROFFSET(rvar), VAROFFSET(vi),
                        addLiteral!(ci, mk_gnd(T, i))
                    )
                    return true
                end
                neg && break                                   # do not swap X is 10 - Y
                a1, a2 = a2, a1
            end
        end
    end
    return false
end

# PORT: pl-comp.c compileSubClause
# DIVERGES: plain goals and `!` (`I_CUT`, or a local cut's instruction once V9 sets `ci.cut`; user,
# 2026-10-05: the cut's COMPILE side with the body compiler, its execution since V6a). The meta-call (a
# variable goal, `call/N`) and the reserved atoms compiled inline (`true`, `fail`, …) throw
# `NotPortedError` BEFORE any code is emitted (V9): upstream always compiles them inline. O_COMPILE_IS's
# functors (since V6b2) and is/2 (since V8) are compiled as upstream decides, by upstream's own
# compilers in upstream's order: inline where upstream emits an instruction — each emission of an
# instruction the kernel does not execute yet throws `NotPortedError` (V9, the memo's Q-1) — and a
# call wherever upstream falls back to one. The names are the global data's (`subclause_names`). One
# module: no `I_CALLM`/`I_DEPARTM`/`I_CALLATM*`, and no colon or at context. The call operand
# indexes the clause's procedure table (since V1).
"""
Compile body goal `arg` as a call with `call` — `I_CALL`, or `I_DEPART` for the clause's last goal,
then last-call-optimised (`lco!`) — after its arguments (pl-comp.c). Returns `BOOLEX_TRUE`, or
`NOT_CALLABLE`/`MAX_ARITY_OVERFLOW` as upstream does.
"""
function compileSubClause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ci::compileInfo{T}, arg::T, call::code
)::boolex_t where {T}
    names = gd.subclause_names
    k = kind(arg)
    off, ar = 2, 0
    if k === VAR
        isIndexedVarTerm(ci, arg) >= 0 &&
            throw(NotPortedError{T}(arg, "a variable goal (the meta-call, I_CALL1)", "V9"))
        return NOT_CALLABLE                                    # a void goal
    elseif k === EXPR
        off, ar = _comp_shape(arg)
        ar > MAXARITY && return MAX_ARITY_OVERFLOW
        off == 2 || return NOT_CALLABLE                        # `$expr/n`: no text name
        h = child(arg, 1)
        # !isTextAtom(fdef->name) && fdef->name != ATOM_nil
        is_reserved_symbol(h) && !is_nil(h) && return NOT_CALLABLE
        name = sym_key(h)
        # ison(fdef, ARITH_F) && !ci->islocal (c:3474-3482; no local compilation)
        if (name, ar) in names.arith_functors
            if name == names.atom_is && compileSimpleAddition(ld, names, arg, ci)
                return BOOLEX_TRUE
            end
            # O_COMPILE_ARITH: under `optimise` upstream compiles it inline (`compileArith`): refused
            ld.prolog_flag_optimise &&
                throw(NotPortedError{T}(arg, "compileArith (optimise)", "the user's Q-AR3"))
        end
        name == names.atom_call &&
            throw(NotPortedError{T}(arg, "call/N (the meta-call)", "V9"))
        # O_COMPILE_IS (c:3484-3519; `!ci->islocal`: no local compilation): upstream's chain, in its
        # order; a `false` falls through to the call below
        rc = BOOLEX_FALSE
        if ar == 2 && name == names.atom_equals                # FUNCTOR_equals2
            rc = compileBodyUnify(ld, ci, arg)
        elseif ar == 2 && name == names.atom_strict_equal      # FUNCTOR_strict_equal2
            rc = compileBodyEQ(ld, ci, arg)
        elseif ar == 2 && name == names.atom_not_strict_equal  # FUNCTOR_not_strict_equal2
            rc = compileBodyNEQ(ld, ci, arg)
        elseif ar == 1 && name == names.atom_var               # FUNCTOR_var1
            rc = compileBodyVar1(ld, ci, arg)
        elseif ar == 1 && name == names.atom_nonvar            # FUNCTOR_nonvar1
            rc = compileBodyNonVar1(ld, ci, arg)
        elseif ar == 1 &&
            (rc = compileBodyTypeTest(ld, names, name, ci, arg)) != BOOLEX_FALSE
            return rc
        elseif ar == 1 && name == names.atom_dcall_continuation  # FUNCTOR_dcall_continuation1
            rc = compileBodyCallContinuation(ci, arg)
        elseif ar == 1 && name == names.atom_dshift            # FUNCTOR_dshift1
            rc = compileBodyShift(ci, arg, false)
        elseif ar == 1 && name == names.atom_dshift_for_copy   # FUNCTOR_dshift_for_copy1
            rc = compileBodyShift(ci, arg, true)
        elseif ar == 3 && name == names.atom_arg               # FUNCTOR_arg3
            rc = compileBodyArg3(ci, arg)
        end
        rc == BOOLEX_FALSE || return rc
    elseif k === SYM && !is_reserved_symbol(arg)               # isTextAtom(*arg)
        if sym_key(arg) == names.atom_cut                      # ATOM_cut
            if ci.cut.var != 0                                 # local cut for \+
                Output_1!(ci, ci.cut.instruction, code(ci.cut.var))
            else
                Output_0!(ci, I_CUT)
            end
            return BOOLEX_TRUE
        end
        sym_key(arg) in names.reserved_atoms &&
            throw(
                NotPortedError{T}(
                    arg, "a goal atom compiled inline (true, fail, …)", "V9"
                )
            )
    else
        return NOT_CALLABLE
    end
    pc0 = PC(ci)
    for i in 0:(ar - 1)                                        # term: there are arguments
        compileArgument!(ci, _comp_arg(arg, off, i), A_BODY)
    end
    proc = lookupBodyProcedure(gd, arg, ci.module_)
    Output_1!(ci, call, addProcedure!(ci, proc))
    if call == I_DEPART                                        # && ci->procedure: always set here
        lco!(ci, pc0)
    end
    return BOOLEX_TRUE
end

# PORT: pl-comp.c compileBody
# DIVERGES: `,` only — every other control construct (`;`, `|`, `->`, `*->`, `\+`, `$/1`, `:/2`,
# `@/2`) throws `NotPortedError` (V9), and with them the variable tables they save; the pending
# right-hand sides (upstream's CB_COMMA_RHS frames) are a Vector where upstream uses a segstack.
"""
Compile clause body `body`, its last goal called with `call` (pl-comp.c): a conjunction left to
right, every goal but the last with `I_CALL`. Returns `BOOLEX_TRUE` or the first goal's error code.
"""
function compileBody!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ci::compileInfo{T}, body::T, call::code
)::boolex_t where {T}
    cf = gd.functors_control
    stack = Tuple{T, code}[]                                   # CB_COMMA_RHS: (B, call)
    @label next_body
    if kind(body) === EXPR && _is_control(body, cf)
        if _has_functor(body, cf.comma, 2)                     # A , B
            push!(stack, (child(body, 3), call))
            body = child(body, 2)
            call = I_CALL
            @goto next_body
        end
        throw(NotPortedError{T}(body, "a control construct other than ,/2", "V9"))
    end
    rc = compileSubClause!(gd, ld, ci, body, call)
    rc == BOOLEX_TRUE || return rc
    isempty(stack) && return BOOLEX_TRUE
    body, call = pop!(stack)
    @goto next_body
end

"Whether `body` makes a rule: present and not the atom `true` (pl-comp.c `body && *body != ATOM_true`)."
_is_rule_body(gd::PL_global_data{T}, body::Union{Nothing, T}) where {T} =
    body !== nothing &&
    !(
        kind(body) === SYM && !is_reserved_symbol(body) &&
        sym_key(body) == gd.subclause_names.atom_true
    )

# From pl-comp.c compileClause (c:2049-2116): what runs before the body is compiled — the variable
# analysis of head AND body, the head arguments left to right, and for a rule `I_ENTER` (a void
# before it merges away, as before `I_EXITFACT`). No SSU (`I_CHP`, `I_SSU_*`) or module context
# (`I_CONTEXT`). A body that is `nothing` or the atom `true` makes a fact.
"""
    _compile_clause_head!(gd, ci, head, body) -> nv

Analyse the variables of `head` and `body` (`nothing` for a fact) and emit the head code of the
clause into `ci`, ending with `I_ENTER` for a rule (pl-comp.c `compileClause`), for the database
whose global data is `gd`. Returns the frame size: the clause's `prolog_vars` and `variables`.
"""
function _compile_clause_head!(
    gd::PL_global_data{T}, ci::compileInfo{T}, head::T, body::Union{Nothing, T}
)::Int where {T}
    nv = analyse_variables!(gd, ci, head, body)               # prolog_vars = variables = nv
    initMerge!(ci)
    if ci.arity > 0
        for n in 0:(ci.arity - 1)
            compileArgument!(ci, child(head, n + 2), A_HEAD)
        end
    end
    if _is_rule_body(gd, body)
        Output_0!(ci, I_ENTER)
    end
    return nv
end

# PORT: pl-comp.c compileClause
# DIVERGES: the body is `nothing` for a fact (upstream's NULL body; a body `true` makes one too, as
# upstream); the body's goals are plain goals and conjunctions (see `compileBody!`); no SSU,
# warnings, flags or resource limits; a RULE of a multifile predicate is refused (its body would
# need `I_CONTEXT`: modules are not ported), and `P_MFCONTEXT` is never set; a goal that is not
# callable, or past MAXARITY, THROWS (`CallableTypeError`, an `ErrorException`) where upstream
# raises it with `PL_error`; the clause is returned where upstream stores it through `cp`, created
# at generation 0 (`assertDefinition!` sets the rest). The
# database's global data `gd` is an argument, where upstream reaches GD — its functor table, the
# `CONTROL_F` flags the analysis reads — as a global (src/pl-global.jl); so is the compiling
# thread's local data `ld` (since V6b), where upstream's `DECL_LD` functions reach LD: its flags
# (`optimise`, `portable_vmi`) decide how a body goal compiles.
# `getProcDefinition(proc)` is `proc.definition`: no thread-local predicates.
"""
    compileClause(gd, ld, head, body, proc, m) -> Clause

Compile the clause `head :- body` (`body` `nothing` or `true` for a fact) of procedure `proc` into
module `m`, in the database whose global data is `gd`, under the flags of local data `ld`
(pl-comp.c): analyse its variables, emit the
head code argument by argument, then a fact's `I_EXITFACT`, or a rule's `I_ENTER`, its body and
`I_EXIT`. The clause keeps the code, the literal table its operands index (V1 L2) and the procedure
table its call operands index (V1). A body goal that is not callable raises
`CallableTypeError(body)` — the WHOLE body, as swipl reports it (probed in 10.1.16).
"""
function compileClause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, head::T, body::Union{Nothing, T},
    proc::Procedure{T}, m::module_t{T}
)::Clause{T} where {T}
    def = proc.definition                                      # getProcDefinition(proc)
    ci = compileInfo{T}(def.arity, m, proc)
    rule = _is_rule_body(gd, body)
    rule && (def.flags & P_MULTIFILE) != 0 &&
        throw(
            NotPortedError{T}(
                head, "a rule of a multifile predicate (I_CONTEXT)", "modules"
            )
        )
    nv = _compile_clause_head!(gd, ci, head, body)
    flags = UInt32(0)
    if rule
        bi = PC(ci)
        rc = compileBody!(gd, ld, ci, body::T, I_DEPART)
        if rc == NOT_CALLABLE
            throw(CallableTypeError{T}(body::T))
        elseif rc == MAX_ARITY_OVERFLOW
            error("compileClause: representation_error(max_procedure_arity)")
        end
        Output_0!(ci, I_EXIT)
        if ci.codes[bi + 1] == I_CUT                           # OpCode(ci, bi) == encode(I_CUT)
            flags |= COMMIT_CLAUSE
        end
    else
        flags = UNIT_CLAUSE
        Output_0!(ci, I_EXITFACT)                              # fact (for decompiler)
    end
    return Clause{T}(
        def, gen_t(0), gen_t(0), clsize_t(nv), clsize_t(nv), flags, ci.codes, ci.literals,
        ci.procedures
    )
end

# ── decompiling the head (pl-comp.c) ────────────────────────────────────────────────────────────
# PORT: pl-comp.c decompileHead
# DIVERGES: the clause's variables are one block of fresh kernel variable keys, slot `i` the key
# `base + i`, where upstream allocates `prolog_vars` term references (`di.variables`).
"""
    decompileHead!(ld, clause, head) -> Bool

Unify `head` with the head `clause`'s code describes, with fresh variables, under the bindings in
`ld` (pl-comp.c): the bindings stay on the trail for the caller to undo.
"""
function decompileHead!(ld::PL_local_data{T}, clause::Clause{T}, head::T)::Bool where {T}
    nv = Int(clause.variables)
    base = nv == 0 ? UInt64(0) : fresh_var_keys!(nv)
    return decompile_head!(ld, clause, head, base)
end

"A compound the decompiler has opened: its children so far, head symbol first (none for `\$expr/n`)."
struct DecompileFrame{T}
    kids::Vector{T}
    need::Int           # the children it has in all
    pushed::Bool        # opened by H_FUNCTOR/H_LIST — closed by its own H_POP — not by an R one
end

# PORT: pl-comp.c decompile_head
# DIVERGES: builds each head argument BOTTOM-UP from the code and unifies it with `head`'s as soon as
# it is complete (upstream's `NEXTARG`) — upstream unifies cell by cell while it decodes. A compound
# opened by `H_FUNCTOR`/`H_LIST` closes at its `H_POP`, which also closes the `H_RFUNCTOR`/`H_RLIST`
# chain of its last argument; a compound closed short of its arity gets fresh variables for the
# voids the compiler dropped before the `H_POP` (upstream's argument cells are fresh already). The
# open compounds are a stack allocated at the first one, so a head of atomic arguments allocates
# nothing here. The functor is not unified: every caller (`pl_clause!`, `retract/1`, `retractall/1`)
# passes a head of this predicate, and `definition` keeps the name's key only. No `bindings`
# (clause/3), `bvar_access` (moved unifications come from a body) or goal clauses. A literal is the
# very term of the clause's table (since V1 L2), so its kind comes back exactly; a nested void is a fresh
# variable of its own.
"""
    decompile_head!(ld, clause, head, base) -> Bool

Rebuild the head arguments of `clause` from its code and literal table — slot `i`'s variable has
key `base + i` — unifying `head`'s arguments with them in turn (pl-comp.c).
"""
function decompile_head!(
    ld::PL_local_data{T}, clause::Clause{T}, head::T, base::UInt64
)::Bool where {T}
    arity = clause.predicate.arity                              # di->arity
    arity == 0 && return true                                   # PL_unify_atom(head, name)
    argn = 0                                                    # the head argument being built
    frames::Union{Nothing, Vector{DecompileFrame{T}}} = nothing
    PC = Code(clause, 1)
    while true
        c = decode(PC)
        local v::T
        if c == I_NOP || c == I_CHP
            PC = stepPC(PC)
            continue
        elseif c == H_NIL
            v = mk_nil(T)
        elseif c == H_ATOM || c == H_SMALLINT || c == H_MPZ || c == H_MPQ || c == H_FLOAT ||
            c == H_STRING
            v = PC.literals[PC.codes[PC.pc + 1]]                # the literal, exactly
        elseif c == H_FIRSTVAR || c == H_VAR
            v = mk_var(T, base + (PC.codes[PC.pc + 1] - VAROFFSET(0)))
        elseif c == H_VOID
            v = _decompile_void(T, frames, base, argn)
        elseif c == H_VOID_N
            for _ in 1:Int(PC.codes[PC.pc + 1])
                w = _decompile_void(T, frames, base, argn)
                if frames === nothing || isempty(frames)
                    pl_unify!(ld, child(head, argn + 2), w) || return false
                    argn += 1                                   # NEXTARG
                else
                    push!(frames[end].kids, w)
                end
            end
            PC = stepPC(PC)
            continue
        elseif c == H_FUNCTOR || c == H_RFUNCTOR || c == H_LIST || c == H_RLIST
            pushed = c == H_FUNCTOR || c == H_LIST
            if frames === nothing
                frames = DecompileFrame{T}[]
            end
            if c == H_LIST || c == H_RLIST
                push!(frames, DecompileFrame{T}(T[mk_sym(T, LIST_CONS_NAME)], 3, pushed))
            else
                op = PC.codes[PC.pc + 1]
                i = functor_literal(op)
                kids = i == 0 ? T[] : T[PC.literals[i]]         # `$expr/n`: no head symbol
                push!(
                    frames,
                    DecompileFrame{T}(kids, length(kids) + functor_arity(op), pushed)
                )
            end
            PC = stepPC(PC)
            continue
        elseif c == H_POP
            fs = frames
            fs === nothing && error("decompile_head: H_POP outside a compound")
            while true                                          # the R chain, then the pushed one
                f = pop!(fs)
                while length(f.kids) < f.need
                    push!(f.kids, mk_var(T, fresh_var_keys!(1)))
                end
                v = mk_expr(T, f.kids)
                f.pushed && break
                push!(fs[end].kids, v)
            end
        elseif c == H_LIST_FF
            x = mk_var(T, base + (PC.codes[PC.pc + 1] - VAROFFSET(0)))
            y = mk_var(T, base + (PC.codes[PC.pc + 2] - VAROFFSET(0)))
            v = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), x, y])
        elseif c == I_EXITFACT || c == I_ENTER
            @assert frames === nothing || isempty(frames)
            while argn < arity                                  # trailing voids: their slots
                pl_unify!(ld, child(head, argn + 2), mk_var(T, base + UInt64(argn))) ||
                    return false
                argn += 1
            end
            return true
        else
            error(
                "decompile_head: illegal instruction in clause head: $(codeTable(c).name)"
            )
        end
        if frames === nothing || isempty(frames)
            pl_unify!(ld, child(head, argn + 2), v) || return false
            argn += 1                                           # NEXTARG
        else
            push!(frames[end].kids, v)
        end
        PC = stepPC(PC)
    end
end

"A void the decompiler meets: in an argument, its slot's variable; in a compound, a fresh one."
function _decompile_void(
    ::Type{T}, frames::Union{Nothing, Vector{DecompileFrame{T}}}, base::UInt64, argn::Int
)::T where {T}
    (frames === nothing || isempty(frames)) && return mk_var(T, base + UInt64(argn))   # FIRSTVAR
    return mk_var(T, fresh_var_keys!(1))
end

# ── reading code (pl-incl.h, pl-comp.h, pl-comp.c) ──────────────────────────────────────────────
# PORT: pl-incl.h decode
# DIVERGES: takes the position and reads the word there — upstream's `decode(*PC)`; instructions
# are not threaded, so the word IS the instruction, as with upstream's `decode(wam) (wam)`.
"The instruction at `PC` (pl-incl.h)."
decode(PC::Code)::code = PC.codes[PC.pc]

# PORT: pl-comp.h stepPC
"The position of the instruction after the one at `PC` (pl-comp.h)."
stepPC(PC::Code{T}) where {T} =
    Code{T}(PC.codes, PC.literals, PC.pc + 1 + codeTable(decode(PC)).arguments)::Code{T}

# PORT: pl-comp.c skipArgs
# DIVERGES: returns `(position, in_hvoid)` where upstream updates `*in_hvoid` through a pointer;
# and an exact landing at the end of an H_VOID_N run is FIXED (LogicKernel#1, see below).
"""
    skipArgs(PC, skip, in_hvoid) -> (Code, in_hvoid)

Skip `skip` arguments of head code from `PC` (pl-comp.c). Skipping into the middle of an
`H_VOID_N` returns the `H_VOID_N` with `in_hvoid` the voids still to skip, so the next call can
continue in small steps.
"""
function skipArgs(PC::Code{T}, skip::Int, in_hvoid::Int)::Tuple{Code{T}, Int} where {T}
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
        if c == H_FUNCTOR || c == H_LIST                        # B_FUNCTOR, B_LIST
            nested += 1
        elseif c == H_RFUNCTOR || c == H_RLIST                  # B_RFUNCTOR, B_RLIST
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
        elseif c == H_ATOM || c == H_SMALLINT || c == H_NIL || c == H_FLOAT || c == H_MPZ ||
            c == H_MPQ || c == H_STRING || c == H_FIRSTVAR || c == H_VAR || c == H_VOID ||
            c == H_LIST_FF
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
# out-parameter. The key of a literal instruction is `indexOfWord` of its literal (since V1 L2), where
# upstream reads the atom (`code2atom`) or computes one (`consInt`, `murmur_key`, `bignum_index`):
# so a grounded value without a key is not indexable, as `indexOfWord` makes it. An `H_FUNCTOR` is
# keyed by its head symbol's literal and its arity, as `indexOfWord` keys the compound — and `$expr/n`
# (literal 0, Q2, src/pl-ressymbol.jl) is a wildcard.
"""
    argKey(PC, skip) -> word

The index key of the head argument at `PC` after skipping `skip` arguments; 0 when it cannot be
indexed (pl-comp.c). Upstream keeps it consistent with `indexOfWord`.
"""
function argKey(PC::Code{T}, skip::Int)::word where {T}
    if skip > 0
        PC, _ = skipArgs(PC, skip, 0)
    end
    while true
        c = decode(PC)
        PC = Code{T}(PC.codes, PC.literals, PC.pc + 1)          # PC++
        if c == H_FUNCTOR || c == H_RFUNCTOR
            op = PC.codes[PC.pc]                                # code2functor(*PC)
            i = functor_literal(op)
            i == 0 && return word(0)                            # `$expr/n`: a wildcard
            return _functor_word(_functor_name(PC.literals[i]), functor_arity(op))
        elseif c == H_ATOM || c == H_SMALLINT || c == H_FLOAT || c == H_MPZ || c == H_MPQ ||
            c == H_STRING
            return indexOfWord(PC.literals[PC.codes[PC.pc]])   # code2atom/consInt/murmur_key/…
        elseif c == H_NIL
            return ATOM_nil                                     # *key = ATOM_nil
        elseif c == H_LIST_FF || c == H_LIST || c == H_RLIST
            return FUNCTOR_dot2                                 # *key = FUNCTOR_dot2
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

# PORT: pl-comp.c arg1Key
# DIVERGES: returns `(found, key)` where upstream returns a flag and sets an out-parameter, and keys
# a literal as `argKey` does (`indexOfWord` of the literal, since V1 L2). `$expr/n` (literal 0, Q2) has no
# functor: not found. AN UPSTREAM DEFECT FIXED: upstream's switch lists `H_MPZ` but not `H_MPQ`, which
# falls to `assert(0)` — swipl 10.1.16 aborts calling `p(1r3, a). p(2r3, b).` (probed 2026-10-05:
# `arg1Key: Assertion failed`); here `H_MPQ` is not found, as `H_MPZ` is. docs/upstream_reports.md #4.
"""
    arg1Key(PC) -> (found, key)

The key of the head argument at `PC`, precisely, or not found (pl-comp.c): `argKey` for the first
argument only and without imprecise keys, for `listSupervisor`.
"""
function arg1Key(PC::Code{T})::Tuple{Bool, word} where {T}
    while true
        c = decode(PC)
        PC = Code{T}(PC.codes, PC.literals, PC.pc + 1)          # *PC++
        if c == H_FUNCTOR || c == H_RFUNCTOR
            op = PC.codes[PC.pc]                                # code2functor(*PC)
            i = functor_literal(op)
            i == 0 && return (false, word(0))                   # `$expr/n`: no functor
            return (true, _functor_word(_functor_name(PC.literals[i]), functor_arity(op)))
        elseif c == H_ATOM || c == H_SMALLINT
            return (true, indexOfWord(PC.literals[PC.codes[PC.pc]]))
        elseif c == H_NIL
            return (true, ATOM_nil)
        elseif c == H_LIST_FF || c == H_LIST || c == H_RLIST
            return (true, FUNCTOR_dot2)
        elseif c == H_FLOAT || c == H_STRING || c == H_MPZ || c == H_MPQ ||
            c == H_FIRSTVAR ||
            c == H_VAR || c == H_VOID || c == H_VOID_N || c == I_EXITFACT || c == I_EXIT ||
            c == I_ENTER
            return (false, word(0))
        elseif c == I_NOP || c == I_CHP
            # continue
        else
            error("arg1Key: unexpected instruction $(codeTable(c).name)")    # assert(0)
        end
    end
end

# ── clause/2 (pl-comp.c) ────────────────────────────────────────────────────────────────────────
# PORT: pl-comp.c clause as pl_clause
# DIVERGES: clause/2 with an unbound clause reference only (no clause/3-4 by reference, no module
# context or protected predicates), answering for the body `true` — so only facts, as a rule's body is
# not `true` (rule bodies are V9's `decompile`); the predicate is given. Each
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
        cref = firstClause!(ld, argv_term(ld, head), gen, def, chp)
        while cref !== nothing
            clause = cref.clause::Clause{T}
            m = Mark(ld)
            try
                # a rule's body is not `true`: only a fact answers clause(Head, true)
                if (clause.flags & UNIT_CLAUSE) != 0 && decompileHead!(ld, clause, head)
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
            cref = nextClause!(ld, chp, argv_term(ld, head), gen, def)    # FRG_REDO
        end
    finally
        popped || popPredicateAccess!(ld, def)
    end
    return nothing
end
