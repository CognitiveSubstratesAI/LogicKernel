# UPSTREAM: swipl-devel src/pl-comp.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-comp.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-incl.h @ 8609e216cab9
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
# kernel's index SWI's. (Until the 2026-10-11 sync there was one exception: SWI lost the key of an
# argument directly after two or more void arguments — `skipArgs`, an upstream defect, fixed in
# 0728e8c — which the kernel had fixed the same way on 2026-10-02.)
#
# ASSERT (since V9c): `assert_term!`, the path of assert/1, assertz/1 and asserta/1 — the clause's
# head and body, its predicate, compiled, added — and their registration table
# (`PL_predicates_from_comp`).
#
# CONTROL CONSTRUCTS (V9d, one per step): the disjunction `;` (and `|`) since 2026-10-12 —
# `compileBody!`'s frames, with the variable tables it balances (`setVars`, `balanceVars`, `c_var`,
# `orVars`, `copyVarTable`) — and the conditionals `(A -> B ; C)`, `(A -> B)` (`allocChoiceVar!`,
# `try_fast_condition!`), `\+` and the soft-cut `*->`; and, since V9f, `$/1` (`C_DET`, with
# `det_goal_error` and `start_of_cdet` for its errors) and `$/0` (`I_DET`).
# THE DECOMPILER (since V9d): `decompile!` rebuilds `Head :- Body` from a clause's code
# (`decompile_head!`, `decompileBody!`, `decompileBodyNoShift!`, `build_term!`), and clause/2
# answers for rule bodies (`pl_clause!` with a body). A clause with a unification moved into its
# head (`CL_HEAD_TERMS`) gets it back as a goal (`mark_bvar_access`, `moved_unifications!`).
#
# NOT PORTED: `islocal` compilation (goal clauses for the meta-call: `subclausearg`, `argvars`,
# `link_local_var`; V9), SSU (`=>`) clauses,
# SSU clauses' moves (`?=>` always moves, `=>` never: no SSU).
#
# The body compiler is ported since V2, and the instructions run in the VM since V4a
# (src/pl-wam.jl). THE COMPILER'S WARNINGS are ported since R1g: the variable analysis' `VD_*`
# flags — a singleton in one branch of `;`, in the goal of `\+`, a `_Name` used twice, an
# unbalanced variable — and the body compiler's goals with no effect (`==`, `\==`, a type test
# with a known outcome), collected for a caller that asks (`compiler_warning`,
# `push_compiler_warnings`) and printed by `assert_term!` when loading a file.

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

# ── warning declarations (pl-comp.c), since R1g ─────────────────────────────────────────────────
# PORT: pl-comp.c CW_MAX_ARGC
"The most context arguments of a compiler warning (pl-comp.c)."
const CW_MAX_ARGC = 3

# PORT: pl-comp.c cw_def
"A compiler warning's declaration: its name and how many context arguments it takes (pl-comp.c `cw_def`)."
struct cw_def
    name::Symbol
    argc::Int
end

# PORT: pl-comp.c cw_defs
# DIVERGES: a tuple, without upstream's closing `CW(NULL, 0)`.
"The compiler's warnings (pl-comp.c `cw_defs`)."
const cw_defs = (
    cw_def(:eq_vv, 2),                  # Var == Var
    cw_def(:eq_singleton, 2),           # SingleTon == ?
    cw_def(:neq_vv, 2),                 # Var \== Var
    cw_def(:neq_singleton, 2),          # SingleTon \== ?
    cw_def(:unify_singleton, 2),        # SingleTon = ?
    cw_def(:always, 1),                 # always(Bool, pred(Arg))
    cw_def(:nonvar_false, 1),           # nonvar(SingleTonOrFirst)
    cw_def(:unbalanced_var, 1),         # Var initialised in some disjunctions
    cw_def(:branch_singleton, 1),       # Singleton in some branch
    cw_def(:negation_singleton, 1),     # Singleton in \+(Goal)
    cw_def(:multiton, 1),               # Multiple _Name variables
    cw_def(:integer_false, 1),          # integer(VarOrNonInt)
    cw_def(:integer_true, 1)            # integer(Integer)
)

# PORT: pl-comp.c c_warning
# DIVERGES: the context arguments are the terms themselves (`argv`), where upstream keeps their
# addresses and `push_compiler_warnings` makes term references of them (`av`); the warnings of one
# compilation are a vector in the order raised (`compileInfo.warnings`), so no `next`.
"A warning raised while compiling a clause (pl-comp.c `c_warning`)."
struct c_warning{T}
    def::cw_def         # Warning definition
    pc::Int             # PC offset in clause
    argv::Vector{T}     # context arguments
end

# ── compiler state (pl-comp.c) ──────────────────────────────────────────────────────────────────
# PORT: pl-comp.c vardef as VarDef
# DIVERGES: what the analysis needs of upstream's record — the slot, the occurrence count, the
# flags and the name. A variable is found by its `var_key` in `compileInfo.vardefs` where upstream
# overwrites the variable's cell with a reference to the record, so there is no `address` or
# `saved`: the variable of a slot is rebuilt from its key (`analyse_variables!`). `arg_value`, the
# term moved, is kept in `compileInfo.arg_value` by the argument's slot (this record has no term
# type); `arg_pos` identifies the `=/2` goal moved (see `annotate_unify!`). `name` is the atom's
# name as a `Symbol` (`nothing`: upstream's 0).
"The analysis of one variable of a clause (pl-comp.c `vardef`)."
mutable struct VarDef
    index::Int          # slot assigned by the analysis
    offset::Int         # offset in environment frame
    times::Int          # occurrences
    flags::UInt32       # VD_*
    arg_pos::Int        # the ordinal of the =/2 goal moved into the head (VD_ARGUMENT)
    name::Union{Nothing, Symbol}    # name (if available)
end

# PORT: pl-comp.c VD_MAYBE_SINGLETON
"`VarDef` flag: used once in a branch of `;`, not yet seen after it (pl-comp.c)."
const VD_MAYBE_SINGLETON = UInt32(0x01)
# PORT: pl-comp.c VD_SINGLETON
"`VarDef` flag: introduced in the goal of `\\+` and used once there (pl-comp.c)."
const VD_SINGLETON = UInt32(0x02)
# PORT: pl-comp.c VD_MAYBE_UNBALANCED
"`VarDef` flag: met in one branch of `;` and not in the other (pl-comp.c)."
const VD_MAYBE_UNBALANCED = UInt32(0x04)
# PORT: pl-comp.c VD_UNBALANCED
"`VarDef` flag: unbalanced, and used after the branches (pl-comp.c)."
const VD_UNBALANCED = UInt32(0x08)

# PORT: pl-comp.c VD_ARGUMENT
"`VarDef` flag: unified against an argument — a unification moved into the head (pl-comp.c)."
const VD_ARGUMENT = UInt32(0x10)
# PORT: pl-comp.c VD_ARGUMENT_DONE
"`VarDef` flag: the moved unification's head code was generated (pl-comp.c)."
const VD_ARGUMENT_DONE = UInt32(0x20)

# PORT: pl-comp.c branch_var
"A variable met inside a branch of `;` or the goal of `\\+` (pl-comp.c `branch_var`)."
mutable struct branch_var
    vdef::VarDef        # Definition record
    saved_times::Int    # Times saved from left branch
    saved_flags::UInt32 # Flags saved from left branch
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
# clause's literal table as it is built (since V1 L2), and `procedures` its procedure table (since V1).
# `islocal`, `subclausearg`, `argvars`, `argvar` since V9e-2 (a GOAL clause for `call/1` of a control
# construct): the pseudo variables' cells are written as the clause compiles, into the frame at
# `local_base` of the local data `local_ld` (upstream writes them at `lTop` through LD). No `clause`
# (the clause is created after the code), and the fields of subsystems not yet ported:
# `progress` (interrupts), `colon_context` and `at_context` (modules). Since R1g: `singletons`,
# `warning_list` (0: the caller wants no warnings) and `warnings` (`nothing` until the first one,
# then in the order raised — see `c_warning`); `styleCheck` is upstream's GLOBAL
# `debugstatus.styleCheck`, copied from the local data when the compilation starts, and
# `variable_names` the value of `$variable_names` then (`get_variable_names`). `cut` is a clause-level cut
# (`var` 0) until a condition sets a local one (since V9d). `variables` is `ci->clause->variables`,
# the frame size: the Prolog variables, then one slot per condition (`allocChoiceVar!`). `module_` is
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
    variables::Int                                          # (ci->clause->variables: the frame size)
    head_unify::Bool                                        # In unifications against arguments
    flags::UInt32                                           # (ci->clause's flags: CL_HEAD_TERMS)
    av_unify::Int                                           # (=/2 goals the analysis met)
    cb_unify::Int                                           # (=/2 goals the compiler met)
    arg_value::Dict{Int, T}                                 # (vardef arg_value, by argument slot)
    singletons::Int                                         # Marked singletons in disjunctions
    styleCheck::Int                                         # (debugstatus.styleCheck)
    warning_list::term_t                                    # see compiler_warning()
    warnings::Union{Nothing, Vector{c_warning{T}}}
    variable_names::Union{Nothing, T}                       # ($variable_names, resolved)
    islocal::Bool                                           # Temporary local clause
    subclausearg::Bool                                      # processing subclausearg
    argvars::Int                                            # islocal argument pseudo vars
    argvar::Int                                             # islocal current pseudo var
    local_ld::Union{Nothing, PL_local_data{T}}              # (islocal: the frame's local data)
    local_base::Int                                         # (islocal: the frame, lTop)
end

"""
A fresh compilation, into module `m`, of a clause of procedure `proc`, whose predicate has `arity`
arguments (pl-comp.c `compileClause`).
"""
compileInfo{T}(arity::Int, m::module_t{T}, proc::Procedure{T}) where {T} =
    compileInfo{T}(
        m, proc, arity, code[], Dict{UInt64, VarDef}(), falses(0), nothing, 0, T[],
        Procedure{T}[], nothing, cutInfo(0, 0, code(0)),         # ci->cut.var = 0 (c:2068)
        0, false, UInt32(0), 0, 0, Dict{Int, T}(),              # head_unify: compileClause's
        0, 0, 0, nothing, nothing,                              # no style checks, no warnings
        false, false, 0, 0, nothing, 0                          # not a goal clause
    )

# PORT: pl-comp.c pushBranchVar
"Record that variable `v` was met in the current branch (pl-comp.c)."
function pushBranchVar!(ci::compileInfo, v::VarDef)::Nothing
    bvs = ci.branch_vars
    bvs === nothing && error("pushBranchVar: not in a branch")
    push!(bvs, branch_var(v, 0, UInt32(0)))
    return nothing
end

# ── warnings (pl-comp.c), since R1g ─────────────────────────────────────────────────────────────
# PORT: pl-comp.c compiler_warning
# DIVERGES: the warning is named by a `Symbol` and its context arguments come as a vector of TERMS
# (upstream: varargs of addresses) — for `always` the value, the predicate's name and the argument,
# the first two made atoms by the caller (upstream makes them here, on the global stack, and can
# return `GLOBAL_OVERFLOW`); an undefined name is an `error` (upstream: `sysError`). Nothing is
# allocated that can fail, so it returns `true`.
"""
Record the warning `name`, with its context arguments `argv`, for the clause being compiled — when
the caller of the compiler asked for warnings (`ci.warning_list`; pl-comp.c).
"""
function compiler_warning(ci::compileInfo{T}, name::Symbol, argv::Vector{T})::Bool where {T}
    ci.warning_list == 0 && return true

    k = findfirst(d -> d.name === name, cw_defs)
    k === nothing && error("Undefined compiler warning: $name")
    def = cw_defs[k]
    @assert length(argv) == def.argc + (name === :always ? 2 : 0)

    ws = ci.warnings
    if ws === nothing
        ws = c_warning{T}[]
        ci.warnings = ws
    end
    push!(ws, c_warning{T}(def, length(ci.codes), argv))        # w->pc = entriesBuffer(&ci->codes)

    return true
end

# PORT: pl-comp.c push_compiler_warnings
# DIVERGES: the list is built from the terms (see `c_warning`) and put into the term reference; the
# warnings are in the order raised already, where upstream walks a newest-first chain and conses
# each in front (the same list). Nothing can overflow, so it returns `true`; no
# `free_compiler_warnings` (Julia's GC).
"Turn the compiler's warnings into a Prolog list in `ci.warning_list`: `[Name(Arg, …), …]` (pl-comp.c)."
function push_compiler_warnings(ld::PL_local_data{T}, ci::compileInfo{T})::Bool where {T}
    l = mk_nil(T)                                               # PL_put_nil(ci->warning_list)
    ws = ci.warnings
    if ws !== nothing
        for k in length(ws):-1:1
            cw = ws[k]
            w = mk_expr(T, T[mk_sym(T, cw.def.name); cw.argv])  # PL_cons_functor_v(tmp, f, cw->av)
            l = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), w, l])  # PL_cons_list(…)
        end
        ci.warnings = nothing                                   # free_compiler_warnings(ci)
    end
    ld.slots[ci.warning_list + 1] = l
    return true
end

# PORT: pl-comp.c get_variable_names
# DIVERGES: `$variable_names` is not a global variable here (see `PL_local_data`'s
# `variable_names`): `compileClause` resolves its value into `ci.variable_names` (`nothing`:
# `gvar_value` fails), a term without bindings as the clause is; a variable's record is found by its
# key, upstream's `isVarInfo(*v)`.
"Name the variable records that `\$variable_names` names (`[Name = Var, …]`); how many (pl-comp.c)."
function get_variable_names(ci::compileInfo{T})::Int where {T}
    found = 0

    p = ci.variable_names
    p === nothing && return found
    while is_pair(p)                                            # isList(*p)
        b = child(p, 2)
        if _hasFunctor(b, mk_sym(T, :(=)), 2)                   # FUNCTOR_equals2
            n = child(b, 2)
            v = child(b, 3)
            if kind(n) === SYM && kind(v) === VAR               # isAtom(*n) && isVarInfo(*v)
                vd = get(ci.vardefs, var_key(v), nothing)
                if vd !== nothing
                    vd.name = Symbol(sym_text(n))
                    found += 1
                end
            end
        end
        p = child(p, 3)
    end

    return found
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
# PORT: pl-comp.c AV_SUBCLAUSE_LOOP
"`av_frame` kind: the arguments of a sub-goal of a goal clause — `islocal`, not a control functor (pl-comp.c `av_kind`)."
const AV_SUBCLAUSE_LOOP = 1
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
# `depth_before_entry` (there is no cycle check, see `analyseVariables2!`).
"A compound whose arguments the analysis is walking (pl-comp.c `av_frame`)."
struct av_frame{T}
    kind::Int               # AV_ARG_LOOP, AV_SUBCLAUSE_LOOP, AV_SEMI_AFTER_LEFT, …RIGHT, AV_NOT_AFTER
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

# PORT: pl-comp.c in_branch
# DIVERGES: the entries `from+1:to` of the branch buffer (0-based bounds, as the frame keeps them);
# a variable is its record (upstream compares `vdef->address`).
"Whether the variable of record `v` is among the branch variables `from+1:to` of `bvs` (pl-comp.c)."
function in_branch(bvs::Vector{branch_var}, from::Int, to::Int, v::VarDef)::Bool
    for i in (from + 1):to
        if bvs[i].vdef === v
            return true
        end
    end

    return false
end

# PORT: pl-comp.c analyseVariables2
# DIVERGES: under `islocal` (a goal clause, V9e-2) the goal is the meta-call's term under the
# bindings, with its control skeleton and its sub-goals' arguments dereferenced first (see
# `localGoal`), where upstream dereferences each cell as it walks; no cycle,
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
            vd = VarDef(index, -1, 1, UInt32(0), 0, nothing)
            ci.vardefs[var_key(head)] = vd
            if ci.branch_vars !== nothing
                pushBranchVar!(ci, vd)
            end
            control && (ci.head_unify = false)                 # variable goal: call/1
        else
            control && (ci.head_unify = false)                 # variable goal: call/1
            vd.times += 1
            if vd.times == 1 && ci.branch_vars !== nothing      # vd->times++ == 0
                pushBranchVar!(ci, vd)
            else
                if (ci.styleCheck & VARBRANCH_CHECK) != 0
                    if (vd.flags & VD_MAYBE_UNBALANCED) != 0 &&
                        (vd.flags & VD_UNBALANCED) == 0
                        vd.flags |= VD_UNBALANCED
                        compiler_warning(ci, :unbalanced_var, T[head])  # vd->address
                    end
                end
                if (ci.styleCheck & SEMSINGLETON_CHECK) != 0
                    if (vd.flags & VD_MAYBE_SINGLETON) != 0
                        @assert vd.times > 1
                        vd.flags &= ~VD_MAYBE_SINGLETON     # Not a singleton
                        ci.singletons -= 1
                    end
                end
            end
        end
        @goto resume
    end
    if kind(head) === EXPR
        if ci.islocal
            if ci.subclausearg                                  # a compound argument: an argvar
                ci.argvars += 1
                @goto resume                                    # term done, no args processed
            elseif !_is_control(head, cf)
                soff, sar = _comp_shape(head)
                sar == 0 && @goto resume
                ci.subclausearg = true
                push!(
                    stack,
                    av_frame{T}(
                        AV_SUBCLAUSE_LOOP, head, soff, 0, ci.arity, sar, false, false, 0, 0
                    )
                )
                @goto resume
            end                                 # ci->local && control functor: the normal case
        end
        if control && !ci.islocal
            # Check for singletons in branches (A;B). These are variables introduced in a
            # branch, used only once in the branch and not used in code after the branches
            # re-unite.
            if _has_functor(head, cf.semicolon, 2)
                ci.head_unify = false
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
                ci.head_unify = false
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
        # Find leading unifications against head arguments. DIVERGES: every =/2 at a control
        # position is counted (`av_unify`), so that `annotate_unify!` can record which one it moved.
        if control
            is_eq = _has_functor(head, gd.subclause_names.atom_equals, 2)
            is_eq && (ci.av_unify += 1)
            if ci.head_unify
                if is_eq
                    annotate_unification!(ci, head)
                elseif !_has_functor(head, cf.comma, 2)
                    ci.head_unify = false
                end
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
            @goto resume
        end
    end                                                         # arity 0: term done
    # e.g. atomic goals; a VARIABLE goal never gets here (`@goto resume` above) and ends the run
    # of moved unifications in its own branches (upstream defect, fixed in 699e53c)
    if control && !(kind(head) === SYM && sym_key(head) == gd.subclause_names.atom_true)
        ci.head_unify = false
    end
    if ci.subclausearg && isString(head)                        # (no attributed variables)
        ci.argvars += 1
    end
    @label resume
    if isempty(stack)
        return nvars
    end
    top = stack[end]
    if top.kind == AV_ARG_LOOP || top.kind == AV_SUBCLAUSE_LOOP
        if top.remaining > 0
            head = _comp_arg(top.base, top.off, top.next)
            argn = top.argn_next
            control = top.control
            stack[end] = av_frame{T}(
                top.kind, top.base, top.off, top.next + 1, top.argn_next + 1,
                top.remaining - 1, top.control, false, 0, 0
            )
            @goto next_head
        end
        top.kind == AV_SUBCLAUSE_LOOP && (ci.subclausearg = false)
        pop!(stack)
        @goto resume
    elseif top.kind == AV_SEMI_AFTER_LEFT
        bvs = ci.branch_vars::Vector{branch_var}
        at_branch_vars = length(bvs)
        for i in (top.start_vars + 1):at_branch_vars            # reset the left branch's vars
            bv = bvs[i]
            bv.saved_times = bv.vdef.times
            bv.saved_flags = bv.vdef.flags
            bv.vdef.times = 0
            bv.vdef.flags = UInt32(0)
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
            if (ci.styleCheck & VARBRANCH_CHECK) != 0
                if bv.saved_times > 0 && vd.times == 0
                    vd.flags |= VD_MAYBE_UNBALANCED             # in left, not in right
                end
                if vd.times > 0 && !in_branch(bvs, top.start_vars, top.at_branch_vars, vd)
                    vd.flags |= VD_MAYBE_UNBALANCED             # in right, not in left
                end
            end
            if (ci.styleCheck & SEMSINGLETON_CHECK) != 0
                if bv.saved_times == 1 || vd.times == 1
                    if (vd.flags & VD_MAYBE_SINGLETON) == 0
                        vd.flags |= VD_MAYBE_SINGLETON          # Possible singleton
                        ci.singletons += 1
                    end
                end
            end
            if vd.times < bv.saved_times
                vd.times = bv.saved_times
            end
            vd.flags |= bv.saved_flags                          # TBD: Dubious
            bv.saved_times = 0
            bv.saved_flags = UInt32(0)
        end
        if !top.obv
            ci.branch_vars = nothing                            # discardBuffer(ci->branch_vars)
        end
        pop!(stack)
        @goto resume
    end
    # AV_NOT_AFTER
    nbvs = ci.branch_vars::Vector{branch_var}
    for i in (top.start_vars + 1):length(nbvs)                  # at_end_vars > top->start_vars
        vd = nbvs[i].vdef
        if vd.times == 1
            vd.flags |= VD_SINGLETON
            ci.singletons += 1
        end
    end
    if !top.obv
        ci.branch_vars = nothing
    else
        resize!(ci.branch_vars::Vector{branch_var}, top.start_vars)   # seekBuffer(start_vars)
    end
    pop!(stack)
    @goto resume
end

# PORT: pl-comp.c is_argument_var
"The `VarDef` of `p` if it is an argument variable — first met as a plain head argument — else `nothing` (pl-comp.c)."
function is_argument_var(ci::compileInfo{T}, p::T)::Union{Nothing, VarDef} where {T}
    kind(p) === VAR || return nothing                          # isVarInfo(*p)
    vd = get(ci.vardefs, var_key(p), nothing)
    (vd === nothing || vd.index >= ci.arity) && return nothing # index < ci->arity
    return vd
end

# PORT: pl-comp.c annotate_unify as annotate_unify!
# DIVERGES: the goal moved is recorded by its ORDINAL among the =/2 goals at control positions
# (`arg_pos`, from `ci.av_unify`), where upstream records the address of the other side
# (`arg_value`), which `isUnifiedArg` compares: the kernel's terms are values, and a term type may
# share structure (alt_interned), so two goals `X = a` could be one term (user, 2026-10-06). The
# term itself goes to `ci.arg_value`, by the argument's slot.
"""
`p1 = p2` (or the goal reversed, see `annotate_unification!`) leads the body: if `p1` is an argument
variable with no moved unification yet and `p2` is not a variable, move it into the head (pl-comp.c).
"""
function annotate_unify!(ci::compileInfo{T}, p1::T, p2::T)::Bool where {T}
    vd = is_argument_var(ci, p1)
    vd === nothing && return false
    if (vd.flags & VD_ARGUMENT) == 0 && kind(p2) !== VAR      # !isVarInfo(*p2) && !isVar(*p2)
        vd.flags |= VD_ARGUMENT
        vd.arg_pos = ci.av_unify
        ci.arg_value[vd.index] = p2                            # vd->arg_value = p2
        return true
    end
    return false
end

# PORT: pl-comp.c annotate_unification as annotate_unification!
"The leading goal `f`, a `=/2`: move it into the head, its sides tried both ways (pl-comp.c)."
annotate_unification!(ci::compileInfo{T}, f::T) where {T} =
    annotate_unify!(ci, child(f, 2), child(f, 3)) ||
    annotate_unify!(ci, child(f, 3), child(f, 2))

# PORT: pl-comp.c argUnifiedTo
"Whether argument variable `vd` had a unification moved into the head (pl-comp.c)."
argUnifiedTo(vd::VarDef)::Bool = (vd.flags & VD_ARGUMENT) != 0  # !!v->arg_value: always set

# PORT: pl-comp.c argMoveUnify as argMoveUnify!
"The term moved into argument variable `vd`'s place, the first time it is asked; else `nothing` (pl-comp.c)."
function argMoveUnify!(ci::compileInfo{T}, vd::VarDef)::Union{Nothing, T} where {T}
    if (vd.flags & VD_ARGUMENT) != 0 && (vd.flags & VD_ARGUMENT_DONE) == 0
        vd.flags |= VD_ARGUMENT_DONE
        return ci.arg_value[vd.index]
    end
    return nothing
end

# PORT: pl-comp.c analyse_variables
# DIVERGES: `head` is `nothing` for a goal clause (upstream's NULL head; V9e-2), whose pseudo variables
# `argvars` counts — slot 0 is the goal, the compound and string arguments of its sub-goals follow,
# then its Prolog variables, none a void (every one is shared with the goal and so initialised).
# Under `islocal` the variable table is all set (`trues`), where upstream has none and skips each use
# of it (`!ci->islocal`): a table in which every variable has been seen makes the same code — no
# `C_VAR`, no first-variable instruction, no jump kept for a balance. A warning's variable
# (`vd->address`) is rebuilt from the slot's key. Returns the frame size `nv`, which `compileClause` records as the
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
    gd::PL_global_data{T}, ci::compileInfo{T}, head::Union{Nothing, T},
    body::Union{Nothing, T}
)::Int where {T}
    arity = ci.arity
    body_voids = 0
    ci.branch_vars = nothing
    ci.singletons = 0
    nvars = head === nothing ? 0 : analyseVariables2!(gd, ci, head, 0, -1, false)
    if body !== nothing
        nvars = analyseVariables2!(gd, ci, body, nvars, arity, true)
    end
    argvars = ci.argvars                                       # counted by the analysis
    if ci.warning_list != 0
        get_variable_names(ci)
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
        name = vd.name
        if name !== nothing && (ci.styleCheck & SEMSINGLETON_CHECK) != 0
            named = atom_is_named_var(codeunits(String(name)))
            if (vd.flags & (VD_MAYBE_SINGLETON | VD_SINGLETON)) != 0 && named > 0
                type = if (vd.flags & VD_MAYBE_SINGLETON) != 0
                    :branch_singleton
                else
                    :negation_singleton
                end
                compiler_warning(ci, type, T[mk_var(T, key)])  # vd->address
            elseif vd.times > 1 && named < 0
                compiler_warning(ci, :multiton, T[mk_var(T, key)])
            end
        end
        if vd.times == 1 && !ci.islocal                        # ISVOID
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
    ci.used_var = ci.islocal ? trues(nv) : falses(nv)          # vartablesize (see above)
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

Thrown by `lookupBodyProcedure` for a goal that is not callable, where SWI-Prolog raises
`error(type_error(callable, Culprit), _)`. The clause compiler never meets it: `compileSubClause!`
finds such a goal `NOT_CALLABLE` first, and `compileClause` raises the error with `PL_error`.
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

# PORT: pl-comp.c link_local_var as link_local_var!
# DIVERGES: the variable's VALUE goes into the cell (a keyed variable is its own reference, decision
# 2) where upstream stores `makeRefG(vd->address)`; no LOCAL_OVERFLOW — the cells were made room for
# before the code is compiled (`compileGoalClause`).
"Link variable `v`, at slot `iv`, into its cell of the goal clause's frame (pl-comp.c)."
function link_local_var!(ci::compileInfo{T}, v::T, iv::Int)::Bool where {T}
    _local_cell!(ci, Int(VAROFFSET(iv)), v)
    return true
end

# The cell at variable offset `voffset` of the goal clause's frame (`varFrameP(lTop, voffset)`) := `t`.
function _local_cell!(ci::compileInfo{T}, voffset::Int, t::T)::Nothing where {T}
    ld = ci.local_ld::PL_local_data{T}
    ld.slots[varFrameP(ci.local_base, voffset) + 1] = t
    return nothing
end

# PORT: pl-comp.c compileArgument
# DIVERGES: under `islocal` (a goal clause, V9e-2) a compound or string argument is not compiled but
# stored in the next pseudo variable's cell and loaded by `B_VAR0+n`/`B_VAR` (`argvar`), and a
# variable is linked into its own cell (`link_local_var`) — the cells of the frame at `ci.local_base`,
# the value itself where upstream stores a reference to the variable's cell (a keyed variable IS
# its reference, decision 2). No
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
        if ci.islocal
            link_local_var!(ci, arg, index)
            if index < 3
                Output_0!(ci, B_VAR0 + code(index))
            else
                Output_1!(ci, B_VAR, VAROFFSET(index))
            end
            @goto resume
        end
        first = isFirstVarSet!(ci.used_var, index)
        if index < ci.arity                                    # variable on its own in the head
            vd = ci.vardefs[var_key(arg)]
            if (where_ & A_BODY) != 0
                argUnifiedTo(vd) && (ci.flags |= CL_HEAD_TERMS)
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
                    p = argMoveUnify!(ci, vd)
                    if p !== nothing
                        ci.flags |= CL_HEAD_TERMS              # set(ci->clause, CL_HEAD_TERMS)
                        arg = p
                        @goto next_arg                         # tail-call
                    end
                    if first
                        Output_0!(ci, H_VOID)
                        @goto resume
                    end
                end
                argUnifiedTo(vd) && (ci.flags |= CL_HEAD_TERMS)
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
        if ci.islocal && isString(arg) && (where_ & A_NOARGVAR) == 0
            @goto argvar
        end
        Output_1!(ci, _gnd_code(arg, where_), addLiteral!(ci, arg))
        @goto resume
    end
    # a compound
    if ci.islocal && (where_ & A_NOARGVAR) == 0
        @label argvar
        av_off = VAROFFSET(ci.argvar)
        _local_cell!(ci, Int(av_off), arg)                     # a copy! (no attributed variables)
        if ci.argvar < 3
            Output_0!(ci, B_VAR0 + code(ci.argvar))
        else
            Output_1!(ci, B_VAR, av_off)
        end
        ci.argvar += 1
        @goto resume
    end
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
# DIVERGES: `val` is a Bool for `ATOM_true`/`ATOM_false`; the warning's value and predicate name
# are made atoms here (see `compiler_warning`), which cannot fail.
"""
    always(ld, ci, val, pred, arg) -> boolex_t

A goal whose outcome is known at compile time (pl-comp.c): warned about (`always(Bool, Pred,
Arg)`, under the `no_effect` style check); under `optimise` `I_TRUE` or `I_FAIL`; otherwise
`BOOLEX_FALSE`, compile it as a call.
"""
function always(
    ld::PL_local_data{T}, ci::compileInfo{T}, val::Bool, pred::String, arg::T
)::boolex_t where {T}
    if (ci.styleCheck & NOEFFECT_CHECK) != 0
        compiler_warning(
            ci, :always,
            T[mk_sym(T, Symbol(val ? "true" : "false")), mk_sym(T, Symbol(pred)), arg]
        )
    end
    if ld.prolog_flag_optimise                                 # truePrologFlag(PLFLAG_OPTIMISE)
        Output_0!(ci, val ? I_TRUE : I_FAIL)
        return BOOLEX_TRUE
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c alwaysFirstVar
"""
    alwaysFirstVar(ld, ci, val, pred, arg, i) -> boolex_t

As [`always`](@ref), for a test on the FIRST occurrence of variable `i` (pl-comp.c, since upstream's
27c742f0): if the test is replaced by `I_TRUE` or `I_FAIL` the variable is still initialised
(`C_VAR`) and marked, as code after a disjunction may assume the branch with the test has set it —
notably a test inside `\\+`.
"""
function alwaysFirstVar(
    ld::PL_local_data{T}, ci::compileInfo{T}, val::Bool, pred::String, arg::T, i::Int
)::boolex_t where {T}
    rc = always(ld, ci, val, pred, arg)
    if rc == BOOLEX_TRUE
        isFirstVarSet!(ci.used_var, i)
        Output_1!(ci, C_VAR, VAROFFSET(i))
    end
    return rc
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
            return alwaysFirstVar(ld, ci, true, "var", a1, i1)
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
            return alwaysFirstVar(ld, ci, false, "nonvar", a1, i1)
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
# DIVERGES: the test is `type_tests` entry `k` (see there).
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
            return alwaysFirstVar(ld, ci, false, name, a1, i1)
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
# Upstream's own decision, compiler by compiler (the memo's Q-1, (a)). Since V9a the unification
# family is emitted and executed — `I_TRUE`, `I_FAIL`, `C_VAR`, `B_UNIFY_*`, `B_EQ_*`, `B_NEQ_*`;
# every other emission (`B_ARG_*`, `I_CALLCONT`, `I_SHIFT`, `I_SHIFTCP`) throws `NotPortedError`
# where upstream emits it, before anything is emitted (V9); each `false` is upstream's, and
# compiles as a call. A void variable is
# upstream's `isVar(*a)`: a variable the analysis gave no slot.

"Whether `a` is a void variable — upstream's `isVar(*a)` in the compiler: a variable with no slot."
_comp_void(ci::compileInfo, a)::Bool = kind(a) === VAR && isIndexedVarTerm(ci, a) < 0

"The slot of `a` if it is a variable that has one, else -1 (`isIndexedVarTerm`, pl-comp.c)."
_comp_ivar(ci::compileInfo, a)::Int = kind(a) === VAR ? isIndexedVarTerm(ci, a) : -1

# PORT: pl-comp.c skippedVar as skippedVar!
# DIVERGES: a compound's arguments are its children from `_comp_shape`'s offset (a `$expr/n`'s head
# is one of them, Q2), visited by recursion where upstream loops on the last one. NOT PORTED: the
# `islocal` test (no goal clauses, see the file header).
"""
`arg` was compiled to no code (a unification or a comparison that cannot change anything): a
`C_VAR` for each of its variables met here for the first time, so the frame's variables are
initialised as if it had run (pl-comp.c).
"""
function skippedVar!(ci::compileInfo{T}, arg::T)::Nothing where {T}
    i = _comp_ivar(ci, arg)
    if i >= 0 && isFirstVarSet!(ci.used_var, i)
        Output_1!(ci, C_VAR, VAROFFSET(i))
    end
    if kind(arg) === EXPR
        off, ar = _comp_shape(arg)
        for k in 0:(ar - 1)
            skippedVar!(ci, _comp_arg(arg, off, k))
        end
    end
    return nothing
end

# PORT: pl-comp.c isUnifiedArg
# DIVERGES: the goal is identified by its ordinal (`ci.cb_unify`, counted as `annotate_unify!`
# counts), where upstream compares the address of the other side.
"Whether the `=/2` goal being compiled was moved into the head of argument variable `vd` (pl-comp.c)."
isUnifiedArg(ci::compileInfo, vd::VarDef)::Bool =
    (vd.flags & VD_ARGUMENT) != 0 && vd.arg_pos == ci.cb_unify

# PORT: pl-comp.c compileBodyUnify
# DIVERGES: a constant operand is its literal-table index (`addLiteral!`), as every literal operand
# (src/pl-vmi.jl), and an atom constant is not registered (`PL_register_atom`: no atom garbage
# collection). The goal's ordinal is counted (`cb_unify`) for `isUnifiedArg`.
"""
`=/2` in a body (pl-comp.c): `I_TRUE` for a void side or `X = X`, after `skippedVar!`;
`B_UNIFY_FF`/`FV`/`VF`/`VV` for two variables; for a variable and a term `B_UNIFY_FC`/`VC` with a
portable constant, else `B_UNIFY_FIRSTVAR` with the term's body code or `B_UNIFY_VAR` with its head
code, then `B_UNIFY_EXIT`; `BOOLEX_FALSE`, a call, for `Term = Term`.
"""
function compileBodyUnify(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    ci.cb_unify += 1
    a1, a2 = child(arg, 2), child(arg, 3)                     # argTermP(*arg, 0), …(1); deRef
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton = ? --> true
        skippedVar!(ci, a1)
        skippedVar!(ci, a2)
        Output_0!(ci, I_TRUE)
        return BOOLEX_TRUE
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # unify two variables
        if i1 == i2                                            # unify a var with itself?
            skippedVar!(ci, a1)
            Output_0!(ci, I_TRUE)
            return BOOLEX_TRUE
        end
        f1 = isFirstVarSet!(ci.used_var, i1)
        f2 = isFirstVarSet!(ci.used_var, i2)
        if argUnifiedTo(ci.vardefs[var_key(a1)]) || argUnifiedTo(ci.vardefs[var_key(a2)])
            ci.flags |= CL_HEAD_TERMS
        end
        if f1 && f2
            Output_2!(ci, B_UNIFY_FF, VAROFFSET(i1), VAROFFSET(i2))
        elseif f1
            Output_2!(ci, B_UNIFY_FV, VAROFFSET(i1), VAROFFSET(i2))
        elseif f2                                              # same, but args swapped
            Output_2!(ci, B_UNIFY_VF, VAROFFSET(i2), VAROFFSET(i1))
        else
            Output_2!(ci, B_UNIFY_VV, VAROFFSET(i1), VAROFFSET(i2))
        end
        return BOOLEX_TRUE
    end
    # check for unifications moved to the head
    i1 >= 0 && isUnifiedArg(ci, ci.vardefs[var_key(a1)]) && return BOOLEX_TRUE
    i2 >= 0 && isUnifiedArg(ci, ci.vardefs[var_key(a2)]) && return BOOLEX_TRUE
    if i1 < 0 && i2 >= 0                                       # (Term = Var): as (Var = Term)!
        i1, a2 = i2, a1
    end
    if i1 >= 0                                                 # Var = Term
        first = isFirstVarSet!(ci.used_var, i1)
        if is_portable_constant(ld, a2)
            Output_2!(
                ci, first ? B_UNIFY_FC : B_UNIFY_VC, VAROFFSET(i1), addLiteral!(ci, a2)
            )
        else
            Output_1!(ci, first ? B_UNIFY_FIRSTVAR : B_UNIFY_VAR, VAROFFSET(i1))
            compileArgument!(ci, a2, first ? A_BODY : A_HEAD | A_ARG)
            Output_0!(ci, B_UNIFY_EXIT)
        end
        return BOOLEX_TRUE
    end
    return BOOLEX_FALSE                                        # Term = Term
end

# PORT: pl-comp.c compileBodyEQ
# DIVERGES: a constant operand is a literal-table index, and an atom constant is not registered, as
# `compileBodyUnify`'s.
"""
`==/2` in a body (pl-comp.c): `B_EQ_VV` on two variables, `B_EQ_VC` on a variable and a portable
constant (either order), each after a `C_VAR` for a first occurrence, which is then MARKED
(`isFirstVarSet`, since upstream's 7dba157e: code after a disjunction may assume the branch set
it); under `optimise`, `I_FAIL` for a void side, `I_TRUE`/`I_FAIL` for a first occurrence;
`BOOLEX_FALSE`, a call, otherwise.
"""
function compileBodyEQ(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1, a2 = child(arg, 2), child(arg, 3)
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton == ?: always fail
        if (ci.styleCheck & NOEFFECT_CHECK) != 0
            compiler_warning(ci, :eq_singleton, T[a1, a2])
        end
        if ld.prolog_flag_optimise
            skippedVar!(ci, a1)
            skippedVar!(ci, a2)
            Output_0!(ci, I_FAIL)
            return BOOLEX_TRUE
        end
        return BOOLEX_FALSE                                    # debugging: compile as normal code
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # Var1 == Var2
        f1, f2 = isFirstVar(ci.used_var, i1), isFirstVar(ci.used_var, i2)
        if f1 || f2
            if (ci.styleCheck & NOEFFECT_CHECK) != 0
                compiler_warning(ci, :eq_vv, T[a1, a2])
            end
            if ld.prolog_flag_optimise
                skippedVar!(ci, a1)
                skippedVar!(ci, a2)
                Output_0!(ci, i1 == i2 ? I_TRUE : I_FAIL)
                return BOOLEX_TRUE
            end
        end
        f1 && isFirstVarSet!(ci.used_var, i1) && Output_1!(ci, C_VAR, VAROFFSET(i1))
        f2 && isFirstVarSet!(ci.used_var, i2) && Output_1!(ci, C_VAR, VAROFFSET(i2))
        Output_2!(ci, B_EQ_VV, VAROFFSET(i1), VAROFFSET(i2))
        return BOOLEX_TRUE
    end
    if i1 >= 0 && is_portable_constant(ld, a2)                # Var == const
        isFirstVar(ci.used_var, i1) && isFirstVarSet!(ci.used_var, i1) &&
            Output_1!(ci, C_VAR, VAROFFSET(i1))
        Output_2!(ci, B_EQ_VC, VAROFFSET(i1), addLiteral!(ci, a2))
        return BOOLEX_TRUE
    end
    if i2 >= 0 && is_portable_constant(ld, a1)                # const == Var
        isFirstVar(ci.used_var, i2) && isFirstVarSet!(ci.used_var, i2) &&
            Output_1!(ci, C_VAR, VAROFFSET(i2))
        Output_2!(ci, B_EQ_VC, VAROFFSET(i2), addLiteral!(ci, a1))
        return BOOLEX_TRUE
    end
    return BOOLEX_FALSE
end

# PORT: pl-comp.c compileBodyNEQ
# DIVERGES: as `compileBodyEQ`'s.
"""
`\\==/2` in a body (pl-comp.c): `B_NEQ_VV`, `B_NEQ_VC`, as `compileBodyEQ`; under `optimise`,
`I_TRUE` for a void side, `I_FAIL`/`I_TRUE` for a first occurrence; `BOOLEX_FALSE`, a call,
otherwise.
"""
function compileBodyNEQ(
    ld::PL_local_data{T}, ci::compileInfo{T}, arg::T
)::boolex_t where {T}
    a1, a2 = child(arg, 2), child(arg, 3)
    if _comp_void(ci, a1) || _comp_void(ci, a2)                # Singleton \== ?: always true
        if (ci.styleCheck & NOEFFECT_CHECK) != 0
            compiler_warning(ci, :neq_singleton, T[a1, a2])
        end
        if ld.prolog_flag_optimise
            skippedVar!(ci, a1)
            skippedVar!(ci, a2)
            Output_0!(ci, I_TRUE)
            return BOOLEX_TRUE
        end
        return BOOLEX_FALSE                                    # debugging: compile as normal code
    end
    i1, i2 = _comp_ivar(ci, a1), _comp_ivar(ci, a2)
    if i1 >= 0 && i2 >= 0                                      # Var1 \== Var2
        f1, f2 = isFirstVar(ci.used_var, i1), isFirstVar(ci.used_var, i2)
        if f1 || f2
            if (ci.styleCheck & NOEFFECT_CHECK) != 0
                compiler_warning(ci, :neq_vv, T[a1, a2])
            end
            if ld.prolog_flag_optimise
                skippedVar!(ci, a1)
                skippedVar!(ci, a2)
                Output_0!(ci, i1 == i2 ? I_FAIL : I_TRUE)
                return BOOLEX_TRUE
            end
        end
        f1 && isFirstVarSet!(ci.used_var, i1) && Output_1!(ci, C_VAR, VAROFFSET(i1))
        f2 && isFirstVarSet!(ci.used_var, i2) && Output_1!(ci, C_VAR, VAROFFSET(i2))
        Output_2!(ci, B_NEQ_VV, VAROFFSET(i1), VAROFFSET(i2))
        return BOOLEX_TRUE
    end
    if i1 >= 0 && is_portable_constant(ld, a2)                # Var \== const
        isFirstVar(ci.used_var, i1) && isFirstVarSet!(ci.used_var, i1) &&
            Output_1!(ci, C_VAR, VAROFFSET(i1))
        Output_2!(ci, B_NEQ_VC, VAROFFSET(i1), addLiteral!(ci, a2))
        return BOOLEX_TRUE
    end
    if i2 >= 0 && is_portable_constant(ld, a1)                # const \== Var
        isFirstVar(ci.used_var, i2) && isFirstVarSet!(ci.used_var, i2) &&
            Output_1!(ci, C_VAR, VAROFFSET(i2))
        Output_2!(ci, B_NEQ_VC, VAROFFSET(i2), addLiteral!(ci, a1))
        return BOOLEX_TRUE
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
# variable goal → `I_CALL1`, `call/N` → `I_CALL1`/`I_CALLN`) as upstream compiles it, since V9e-1. The
# reserved atoms compiled inline but `true` and `fail` (`$catch`, `$reset`, …) throw `NotPortedError`
# BEFORE any code is emitted (V9): upstream always compiles them inline. `true` and `fail` compile to `I_TRUE` and `I_FAIL` (since V9a). O_COMPILE_IS's
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
    is_call = false                                            # fdef->name == ATOM_call
    if k === VAR
        if isIndexedVarTerm(ci, arg) >= 0                      # a non-void variable: I_CALL1
            # metacall: (one module: no colon or at context)
            compileArgument!(ci, arg, A_BODY | A_NOARGVAR)
            Output_0!(ci, I_CALL1)
            return BOOLEX_TRUE
        end
        return NOT_CALLABLE                                    # a void goal
    elseif k === EXPR
        off, ar = _comp_shape(arg)
        ar > MAXARITY && return MAX_ARITY_OVERFLOW
        off == 2 || return NOT_CALLABLE                        # `$expr/n`: no text name
        h = child(arg, 1)
        # !isTextAtom(fdef->name) && fdef->name != ATOM_nil
        is_reserved_symbol(h) && !is_nil(h) && return NOT_CALLABLE
        name = sym_key(h)
        is_call = name == names.atom_call
        # ison(fdef, ARITH_F) && !ci->islocal (c:3474-3482)
        if !ci.islocal && (name, ar) in names.arith_functors
            if name == names.atom_is && compileSimpleAddition(ld, names, arg, ci)
                return BOOLEX_TRUE
            end
            # O_COMPILE_ARITH: under `optimise` upstream compiles it inline (`compileArith`): refused
            ld.prolog_flag_optimise &&
                throw(NotPortedError{T}(arg, "compileArith (optimise)", "the user's Q-AR3"))
        end
        # O_COMPILE_IS (c:3484-3519), `!ci->islocal`: upstream's chain, in its order; a `false` falls
        # through to the call below; a goal clause calls them all
        rc = BOOLEX_FALSE
        if ci.islocal
            # (no inline compilation in a goal clause)
        elseif ar == 2 && name == names.atom_equals            # FUNCTOR_equals2
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
        if sym_key(arg) == names.atom_true                     # ATOM_true
            Output_0!(ci, I_TRUE)
            return BOOLEX_TRUE
        elseif sym_key(arg) == names.atom_fail                 # ATOM_fail
            Output_0!(ci, I_FAIL)
            return BOOLEX_TRUE
        elseif sym_key(arg) == names.atom_dcatch               # ATOM_dcatch: $catch (since V9f)
            Output_0!(ci, I_CATCH)
            Output_0!(ci, I_EXITCATCH)
            return BOOLEX_TRUE
        elseif sym_key(arg) == names.atom_dollar               # ATOM_dollar: $ (since V9f)
            Output_0!(ci, I_DET)
            return BOOLEX_TRUE
        end
        sym_key(arg) in names.reserved_atoms &&
            throw(
                NotPortedError{T}(
                    arg, "a goal atom compiled inline (\$catch, \$reset, …)", "V9"
                )
            )
    else
        return NOT_CALLABLE
    end
    pc0 = PC(ci)
    for i in 0:(ar - 1)                                        # term: there are arguments
        compileArgument!(ci, _comp_arg(arg, off, i), A_BODY)
    end
    if is_call
        if ar == 1                                             # (no colon or at context)
            Output_0!(ci, I_CALL1)
        else
            Output_1!(ci, I_CALLN, code(ar - 1))
        end
        return BOOLEX_TRUE
    end
    proc = lookupBodyProcedure(gd, arg, ci.module_)
    Output_1!(ci, call, addProcedure!(ci, proc))
    if call == I_DEPART && !ci.islocal                         # && ci->procedure (NULL: islocal)
        lco!(ci, pc0)
    end
    return BOOLEX_TRUE
end

# PORT: pl-comp.c c_var_state
"The run of `C_VAR`s `balanceVars` is collecting (pl-comp.c): `count` slots from offset `at`."
struct c_var_state
    at::Int
    count::Int
end

# PORT: pl-comp.c c_var
# DIVERGES: returns the new state, where upstream updates it through a pointer.
"""
Add the slot at offset `at` to the run `s`, emitting the run collected so far when `at` does not
continue it (pl-comp.c): `C_VAR` for one slot, `C_VAR_N` for more. As upstream, a slot continues a
run only when it follows the run's FIRST slot, so a run is at most two slots.
"""
function c_var(s::c_var_state, at::Int, ci::compileInfo)::c_var_state
    if s.count == 0
        return c_var_state(at, 1)
    elseif at == s.at + 1
        return c_var_state(s.at, s.count + 1)
    else
        if s.count == 1
            Output_1!(ci, C_VAR, code(s.at))
        else
            Output_2!(ci, C_VAR_N, code(s.at), code(s.count))
        end
        return c_var_state(at, 1)
    end
end

# PORT: pl-comp.c balanceVars
"""
Emit `C_VAR` for every variable that is uninitialised in `valt1` and initialised in `valt2`
(pl-comp.c): after both branches of a disjunction the same slots hold a value. Returns how many.
"""
function balanceVars(valt1::BitVector, valt2::BitVector, ci::compileInfo)::Int
    done = 0
    vstate = c_var_state(0, 0)
    for n in 0:(length(ci.used_var) - 1)                       # vartablesize
        if !valt1[n + 1] && valt2[n + 1]                       # ~(*p1) & *p2
            vstate = c_var(vstate, Int(VAROFFSET(n)), ci)
            done += 1
        end
    end
    if vstate.count != 0
        c_var(vstate, 0, ci)
    end
    return done
end

# PORT: pl-comp.c orVars
"Mark in `valt1` every variable marked in `valt2` (pl-comp.c)."
function orVars(valt1::BitVector, valt2::BitVector)::Nothing
    valt1 .|= valt2
    return nothing
end

# PORT: pl-comp.c setVars
# DIVERGES: the pending arguments are a Vector where upstream uses a segstack.
"Mark in `vt` every clause variable that appears in `t` (pl-comp.c)."
function setVars(ci::compileInfo{T}, t::T, vt::BitVector)::Nothing where {T}
    stack = T[]
    while true
        if kind(t) === VAR
            index = isIndexedVarTerm(ci, t)
            index >= 0 && isFirstVarSet!(vt, index)
        elseif kind(t) === EXPR
            n = nchildren(t)
            if n > 0
                for i in n:-1:2                                # the head is child 1
                    push!(stack, child(t, i))
                end
                t = child(t, 1)
                continue
            end
        end
        isempty(stack) && break
        t = pop!(stack)
    end
    return nothing
end

# PORT: pl-comp.c copyVarTable
"Make `to` a copy of `from` (pl-comp.c)."
function copyVarTable(to::BitVector, from::BitVector)::BitVector
    copyto!(to, from)
    return to
end

# PORT: pl-comp.c cb_kind
"What `compileBody` resumes with when a sub-compilation ends (pl-comp.c)."
@enum cb_kind::UInt8 begin
    CB_COMMA_RHS            # (A, B): compile B after A
    CB_SEMI_A               # (A ; B): resume after A
    CB_SEMI_B               # (A ; B): resume after B
    CB_ITE_COND             # (A -> B ; C): resume after A
    CB_ITE_THEN             # (A -> B ; C): resume after B
    CB_ITE_ELSE             # (A -> B ; C): resume after C
    CB_IT_COND              # (A -> B): resume after A
    CB_IT_THEN              # (A -> B): resume after B
    CB_NOT_INNER            # (\+ A) / ($ A): resume after A
end

# PORT: pl-comp.c cb_frame
# DIVERGES: the fields of the constructs ported so far (`,`, `;`, `->`, `*->`, `\+`, `$`): no
# `tmsave` (modules). The three variable tables are ONE tuple of three (`nothing` where upstream
# leaves them unset; `\+` and `$` use the first, `vsave`, alone), so a frame is a flat value.
"A pending step of `compileBody` (pl-comp.c): the state to restore and the step to run."
struct cb_frame{T}
    kind::cb_kind
    call::code                                  # 'call' passed to the pending sub-compilation
    body::T                                     # the enclosing control term (`,`: its B)
    a0::T                                       # the (A -> B) inside (;)
    var::Int                                    # choice-point variable
    tc_or::Int                                  # patch offset of C_OR / C_IFTHENELSE / ...
    tc_jmp::Int                                 # patch offset of forward C_JMP
    vars::Union{Nothing, NTuple{3, BitVector}}  # vsave, valt1, valt2
    cutsave::cutInfo
    hard::Bool                                  # -> vs *->
    isnot::Bool                                 # CB_NOT_INNER: \+ (true) vs $ (false)
end

"`frame` with another `kind` and forward-jump offset: the next step of the same construct."
_cb_next(frame::cb_frame{T}, kind::cb_kind, tc_jmp::Int=frame.tc_jmp) where {T} =
    cb_frame{T}(
        kind, frame.call, frame.body, frame.a0, frame.var, frame.tc_or, tc_jmp, frame.vars,
        frame.cutsave, frame.hard, frame.isnot
    )

# PORT: pl-comp.c allocChoiceVar
# DIVERGES: the frame size is `ci.variables` (see `compileInfo`); the error needs the local data.
"""
Reserve a frame slot for a condition's choice-point reference and return its offset (pl-comp.c);
0, with `representation_error(max_frame_size)` raised, when the frame size overflows.
"""
function allocChoiceVar!(ld::PL_local_data{T}, ci::compileInfo{T})::Int where {T}
    var = Int(VAROFFSET(ci.variables))
    ci.variables += 1
    if ci.variables % clsize_t == 0                             # ci->clause->variables == 0
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_frame_size))
        return 0
    end
    return var
end

# PORT: pl-comp.c try_fast_condition
# DIVERGES: positions are indices into `ci.codes`. Of upstream's list the kernel has the type tests
# and `==`/`\==` (the arithmetic `A_` instructions: only under `optimise`, since V6c2);
# `I_RATIONAL` is not in upstream's list, so a `rational/1` condition is not fast.
"""
Make the condition whose code starts at `tc_or` a fast one — `C_IFTHENELSE` becomes `C_FASTCOND` —
when it is only tests that cannot bind or call (pl-comp.c); true when it did.
"""
function try_fast_condition!(ci::compileInfo, tc_or::Int)::Bool
    pc = tc_or + 1                                              # &OpCode(ci, tc_or)
    while pc <= PC(ci)
        op = ci.codes[pc]
        (
            op == I_INTEGER || op == I_FLOAT || op == I_NUMBER || op == I_ATOMIC ||
            op == I_ATOM || op == I_STRING || op == I_COMPOUND || op == I_CALLABLE ||
            op == I_VAR || op == I_NONVAR || op == B_EQ_VV || op == B_EQ_VC ||
            op == B_NEQ_VV || op == B_NEQ_VC
        ) || return false
        pc += 1 + codeTable(op).arguments                       # stepPC(pc)
    end
    @assert ci.codes[tc_or - 2] == C_IFTHENELSE                 # decode(pc[-3])
    ci.codes[tc_or - 2] = C_FASTCOND
    return true
end

# PORT: pl-comp.c compileBody
# DIVERGES: `,`, `;`, `|`, `->`, `*->`, `\+` and `$/1` (since V9f) — the other control constructs
# (`:/2`, `@/2`: modules) throw `NotPortedError`, before
# anything is emitted; the pending steps (upstream's `cb_frame`s) are a Vector where upstream uses a
# segstack, so there is no MEMORY_OVERFLOW; no `islocal` (see the file header).
"""
Compile clause body `body`, its last goal called with `call` (pl-comp.c): a conjunction left to
right, every goal but the last with `I_CALL`; a disjunction as `C_OR <A> C_JMP <B>`, the
variables each branch leaves unset made fresh (`C_VAR`); `(A -> B ; C)` as
`C_IFTHENELSE <A> C_CUT <B> C_JMP <C>` — `C_FASTCOND`/`C_FASTCUT` when the condition is only
tests — and `(A -> B)` as `C_IFTHEN <A> C_CUT <B> C_END`, a `!` in the condition cutting locally;
`(A *-> B ; C)` as `C_SOFTIF <A> C_SOFTCUT <B> C_JMP <C>` and `(A *-> B)` as
`C_SOFTIFTHEN <A> C_SCUT <B> C_END`;
`\\+ A` as `C_NOT <A> C_CUT C_FAIL`, the variables A first used made fresh after it;
`\$(A)` as `C_DET <A> C_DETTRUE C_JMP <fresh variables> C_DETFALSE`.
Returns `BOOLEX_TRUE` or the first goal's error code.
"""
function compileBody!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ci::compileInfo{T}, body::T, call::code
)::boolex_t where {T}
    cf = gd.functors_control
    stack = cb_frame{T}[]
    rc = BOOLEX_TRUE
    @label next_body
    if kind(body) === EXPR && _is_control(body, cf)
        if _has_functor(body, cf.comma, 2)                     # A , B
            push!(
                stack,
                cb_frame{T}(
                    CB_COMMA_RHS, call, child(body, 3), body, 0, 0, 0, nothing, ci.cut,
                    true,
                    true
                )
            )
            body = child(body, 2)
            call = I_CALL
            @goto next_body
        elseif _has_functor(body, cf.semicolon, 2) || _has_functor(body, cf.bar, 2)
            a0 = child(body, 2)                                # A ; B and (A -> B ; C)
            vsave = copy(ci.used_var)                          # mkCopiedVarTable(ci->used_var)
            valt1 = copy(ci.used_var)
            valt2 = copy(ci.used_var)
            setVars(ci, child(body, 2), valt1)
            setVars(ci, child(body, 3), valt2)
            if _has_functor(a0, cf.ifthen, 2) ||               # A  -> B ; C
                _has_functor(a0, cf.softcut, 2)                 # A *-> B ; C
                hard = _has_functor(a0, cf.ifthen, 2)
                var = allocChoiceVar!(ld, ci)
                if var == 0
                    rc = BOOLEX_FALSE
                    @goto resume
                end
                Output_2!(ci, hard ? C_IFTHENELSE : C_SOFTIF, code(var), code(0))
                push!(
                    stack,
                    cb_frame{T}(
                        CB_ITE_COND, call, body, a0, var, PC(ci), 0, (vsave, valt1, valt2),
                        ci.cut, hard, true
                    )
                )
                # Cut locally in the condition
                ci.cut = cutInfo(var, ci.cut.nextvar, hard ? C_LCUT : C_LSCUT)
                body = child(a0, 2)
                call = I_CALL
                @goto next_body
            else                                               # A ; B
                Output_1!(ci, C_OR, code(0))
                push!(
                    stack,
                    cb_frame{T}(
                        CB_SEMI_A, call, body, body, 0, PC(ci), 0, (vsave, valt1, valt2),
                        ci.cut, true, true
                    )
                )
                body = child(body, 2)
                call = I_CALL
                @goto next_body
            end
        elseif _has_functor(body, cf.ifthen, 2) ||             # A -> B
            _has_functor(body, cf.softcut, 2)                   # A *-> B
            hard = _has_functor(body, cf.ifthen, 2)
            var = allocChoiceVar!(ld, ci)
            if var == 0
                rc = BOOLEX_FALSE
                @goto resume
            end
            Output_1!(ci, hard ? C_IFTHEN : C_SOFTIFTHEN, code(var))
            push!(
                stack,
                cb_frame{T}(
                    CB_IT_COND, call, body, body, var, 0, 0, nothing, ci.cut, hard, true
                )
            )
            ci.cut = cutInfo(var, ci.cut.nextvar, C_LCUTIFTHEN) # Cut locally in the condition
            body = child(body, 2)
            call = I_CALL
            @goto next_body
        end
        if _has_functor(body, cf.not_provable, 1) ||           # \+/1
            _has_functor(body, cf.dollar, 1)                    # $/1
            isnot = _has_functor(body, cf.not_provable, 1)
            var = allocChoiceVar!(ld, ci)
            if var == 0
                rc = BOOLEX_FALSE
                @goto resume
            end
            vsave = copy(ci.used_var)                          # mkCopiedVarTable(ci->used_var)
            Output_2!(ci, isnot ? C_NOT : C_DET, code(var), code(0))
            push!(
                stack,
                cb_frame{T}(
                    CB_NOT_INNER, call, body, body, var, PC(ci), 0, (vsave, vsave, vsave),
                    ci.cut, true, isnot
                )
            )
            ci.cut = cutInfo(var, ci.cut.nextvar, C_LCUT)
            body = child(body, 2)
            call = I_CALL
            @goto next_body
        end
        throw(
            NotPortedError{T}(
                body,
                "a control construct other than ,/2, ;/2, ->/2, *->/2, \\+/1 and \$/1",
                "modules"
            )
        )
    end
    rc = compileSubClause!(gd, ld, ci, body, call)
    @label resume
    rc == BOOLEX_TRUE || return rc
    isempty(stack) && return BOOLEX_TRUE
    frame = pop!(stack)
    if frame.kind == CB_COMMA_RHS
        body = frame.body
        call = frame.call
        @goto next_body
    elseif frame.kind == CB_SEMI_A                             # (A ; B) after A
        vsave, valt1, valt2 = frame.vars::NTuple{3, BitVector}
        balanceVars(valt1, valt2, ci)
        Output_1!(ci, C_JMP, code(0))
        tc_jmp = PC(ci)
        ci.codes[frame.tc_or] = code(PC(ci) - frame.tc_or)     # OpCode(ci, tc_or-1)
        copyVarTable(ci.used_var, vsave)
        push!(stack, _cb_next(frame, CB_SEMI_B, tc_jmp))
        body = child(frame.body, 3)
        call = frame.call
        @goto next_body
    elseif frame.kind == CB_SEMI_B                             # (A ; B) after B
        _, valt1, valt2 = frame.vars::NTuple{3, BitVector}
        balanceVars(valt2, valt1, ci)
        ci.codes[frame.tc_jmp] = code(PC(ci) - frame.tc_jmp)   # OpCode(ci, tc_jmp-1)
        orVars(valt1, valt2)
        copyVarTable(ci.used_var, valt1)
        @goto resume
    elseif frame.kind == CB_ITE_COND                           # (A -> B ; C) after A
        fast = false
        if frame.hard
            fast = try_fast_condition!(ci, frame.tc_or)
        end
        ci.cut = frame.cutsave
        Output_1!(
            ci,
            if fast
                C_FASTCUT
            elseif frame.hard
                C_CUT
            else
                C_SOFTCUT
            end,
            code(frame.var)
        )
        push!(stack, _cb_next(frame, CB_ITE_THEN))
        body = child(frame.a0, 3)
        call = frame.call
        @goto next_body
    elseif frame.kind == CB_ITE_THEN                           # (A -> B ; C) after B
        vsave, valt1, valt2 = frame.vars::NTuple{3, BitVector}
        balanceVars(valt1, valt2, ci)
        Output_1!(ci, C_JMP, code(0))
        tc_jmp = PC(ci)
        ci.codes[frame.tc_or] = code(PC(ci) - frame.tc_or)     # OpCode(ci, tc_or-1)
        copyVarTable(ci.used_var, vsave)
        push!(stack, _cb_next(frame, CB_ITE_ELSE, tc_jmp))
        body = child(frame.body, 3)
        call = frame.call
        @goto next_body
    elseif frame.kind == CB_ITE_ELSE                           # (A -> B ; C) after C
        _, valt1, valt2 = frame.vars::NTuple{3, BitVector}
        balanceVars(valt2, valt1, ci)
        ci.codes[frame.tc_jmp] = code(PC(ci) - frame.tc_jmp)   # OpCode(ci, tc_jmp-1)
        orVars(valt1, valt2)
        copyVarTable(ci.used_var, valt1)
        @goto resume
    elseif frame.kind == CB_IT_COND                            # (A -> B) after A
        ci.cut = frame.cutsave
        if frame.hard
            Output_1!(ci, C_CUT, code(frame.var))
        else
            Output_0!(ci, C_SCUT)
        end
        push!(stack, _cb_next(frame, CB_IT_THEN))
        body = child(frame.body, 3)
        call = frame.call
        @goto next_body
    elseif frame.kind == CB_IT_THEN                            # (A -> B) after B
        Output_0!(ci, C_END)
        @goto resume
    else                                                       # CB_NOT_INNER: (\+ A) / ($ A) after A
        vsave = (frame.vars::NTuple{3, BitVector})[1]
        tc_det = 0
        ci.cut = frame.cutsave
        if frame.isnot
            Output_1!(ci, C_CUT, code(frame.var))
            Output_0!(ci, C_FAIL)
        else
            Output_1!(ci, C_DETTRUE, code(frame.var))
            Output_1!(ci, C_JMP, code(0))
            tc_det = PC(ci)
        end
        if frame.isnot
            Output_1!(ci, C_JMP, code(0))
            tc_jmp = PC(ci)
            ci.codes[frame.tc_or] = code(PC(ci) - frame.tc_or) # OpCode(ci, tc_or-1)
            if balanceVars(vsave, ci.used_var, ci) > 0
                # copyVarTable(ci->used_var, vsave) is commented out upstream: see its comment
                ci.codes[tc_jmp] = code(PC(ci) - tc_jmp)       # OpCode(ci, tc_jmp-1)
            else                                               # delete the jmp
                resize!(ci.codes, tc_jmp - 2)                  # seekBuffer(&ci->codes, tc_jmp-2)
                ci.codes[frame.tc_or] = code(PC(ci) - frame.tc_or)
            end
        else                                                   # $(Goal)
            balanceVars(vsave, ci.used_var, ci)
            ci.codes[frame.tc_or] = code(PC(ci) - frame.tc_or)
        end
        if !frame.isnot
            Output_0!(ci, C_DETFALSE)
            ci.codes[tc_det] = code(PC(ci) - tc_det)           # OpCode(ci, tc_det-1)
        end
        @goto resume
    end
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
    ci.variables = nv
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
# flags or resource limits; `warnings` (since R1g) is upstream's term reference, 0 for a caller
# that wants none (the six-argument method), and the style checks and `$variable_names` are read
# from `ld` here (see `compileInfo`); a RULE of a multifile predicate is refused (its body would
# need `I_CONTEXT`: modules are not ported), and `P_MFCONTEXT` is never set; the clause is returned
# where upstream stores it through `cp` — `nothing` for upstream's failure, its error raised with
# `PL_error` as upstream raises it (since V9c) — created at generation 0 (`assertDefinition!` sets
# the rest). `head` and `body` are terms without bindings, so the analysis meets no cycle
# (`CYCLIC_HEAD`, `CYCLIC_BODY`): a caller that holds a clause under bindings checks it and resolves
# it first (`assert_term!`). `pushWordAsTermRef(body)` is a new term reference of the current
# foreign frame, released with it (no `popTermRef`). The
# database's global data `gd` is an argument, where upstream reaches GD — its functor table, the
# `CONTROL_F` flags the analysis reads — as a global (src/pl-global.jl); so is the compiling
# thread's local data `ld` (since V6b), where upstream's `DECL_LD` functions reach LD: its flags
# (`optimise`, `portable_vmi`) decide how a body goal compiles.
# `getProcDefinition(proc)` is `proc.definition`: no thread-local predicates.
"""
    compileClause(gd, ld, head, body, proc, m) -> Clause, or nothing
    compileClause(gd, ld, head, body, proc, m, warnings) -> Clause, or nothing

Compile the clause `head :- body` (`body` `nothing` or `true` for a fact) of procedure `proc` into
module `m`, in the database whose global data is `gd`, under the flags of local data `ld`
(pl-comp.c): analyse its variables, emit the
head code argument by argument, then a fact's `I_EXITFACT`, or a rule's `I_ENTER`, its body and
`I_EXIT`. The clause keeps the code, the literal table its operands index (V1 L2) and the procedure
table its call operands index (V1). A body goal that is not callable raises
`type_error(callable, Body)` — the WHOLE body, as swipl reports it (probed in 10.1.16) — and a
goal past `MAXARITY` `representation_error(max_procedure_arity)`, with `PL_error` in `ld`: the
result is then `nothing`. With a term reference `warnings`, it is set to the list of the
compiler's warnings for the clause (`[]`: none).
"""
function compileClause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, head::T, body::Union{Nothing, T},
    proc::Procedure{T}, m::module_t{T}, warnings::term_t
)::Union{Nothing, Clause{T}} where {T}
    def = proc.definition                                      # getProcDefinition(proc)
    ci = compileInfo{T}(def.arity, m, proc)
    ci.styleCheck = ld.debugstatus_styleCheck                  # (debugstatus.styleCheck)
    ci.warning_list = warnings
    ci.warnings = nothing
    if warnings != 0 && ld.variable_names != 0                 # (gvar_value(ATOM_dvariable_names))
        ci.variable_names = resolve_term(ld, ld.slots[ld.variable_names + 1])
    end
    # ci->head_unify, without SSU (`?=>` always moves, `=>` never): static code, `optimise_unify`
    ci.head_unify = (def.flags & P_DYNAMIC) == 0 && ld.prolog_flag_optimise_unify
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
        if rc != BOOLEX_TRUE
            if rc == NOT_CALLABLE
                b = new_term_ref(ld)                           # pushWordAsTermRef(body)
                ld.slots[b + 1] = body::T
                PL_error(ld, ERR_TYPE, mk_sym(T, :callable), b)
            elseif rc == MAX_ARITY_OVERFLOW
                PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_procedure_arity))
            end
            return nothing                                     # goto exit_fail
        end
        Output_0!(ci, I_EXIT)
        if ci.codes[bi + 1] == I_CUT                           # OpCode(ci, bi) == encode(I_CUT)
            flags |= COMMIT_CLAUSE
        end
    else
        flags = UNIT_CLAUSE
        Output_0!(ci, I_EXITFACT)                              # fact (for decompiler)
    end
    if ci.warning_list != 0 && !push_compiler_warnings(ld, ci)
        return nothing                                         # goto exit_fail
    end
    flags |= ci.flags                                          # CL_HEAD_TERMS, set on ci->clause
    return Clause{T}(
        def, gen_t(0), gen_t(0), clsize_t(ci.variables), clsize_t(nv), flags, ci.codes,
        ci.literals,
        ci.procedures, UInt32(0), UInt32(0), UInt32(0)     # line_no, source_no, owner_no
    )
end

compileClause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, head::T, body::Union{Nothing, T},
    proc::Procedure{T}, m::module_t{T}
) where {T} = compileClause(gd, ld, head, body, proc, m, 0)

# ── goal clauses: call/1 of a control construct (pl-comp.c compileClause, head NULL), since V9e-2 ──
# DIVERGES (no upstream function; upstream dereferences each cell as `analyseVariables2`,
# `compileBody` and `compileArgument` walk it): the meta-call's goal holds VARIABLES BOUND in the
# store, which the kernel's compiler — written for clauses without bindings — does not follow. So the
# parts of the goal the compiler inspects are dereferenced first: the children of each control
# construct, recursively, and the arguments of each sub-goal, one level. A compound or string
# argument then becomes a pseudo variable holding the term as it is (bindings and all), and an
# unbound variable its own cell: exactly what upstream's walk sees.
"The goal `goal` with its control skeleton and its sub-goals' arguments dereferenced under `ld`."
function localGoal(gd::PL_global_data{T}, ld::PL_local_data{T}, goal::T)::T where {T}
    g = deRef(ld, goal)
    kind(g) === EXPR || return g
    n = nchildren(g)
    kids = Vector{T}(undef, n)
    if _is_control(g, gd.functors_control)
        kids[1] = child(g, 1)
        for i in 2:n
            kids[i] = localGoal(gd, ld, child(g, i))
        end
    else
        for i in 1:n
            kids[i] = deRef(ld, child(g, i))
        end
    end
    return mk_expr(T, kids)
end

# PORT: pl-comp.c compileClause as compileGoalClause
# DIVERGES: upstream's `compileClause` with a NULL head (pl-comp.c:2031-2039, 2201-2266), as its own
# function: the goal is `localGoal`'s; the clause is a heap `Clause` (GOAL_CLAUSE, of `$call/1`) that
# no definition holds — upstream builds it on the local stack above the frame — and its frame size
# `variables` grows by what upstream's occupies there (`SIZEOF_CREF_CLAUSE + sizeofClause(code_size)`,
# positions), so `lTop` lands where upstream's does; the cells are made room for after the analysis
# (`ensureLocalSpace`), where upstream checks the total after compiling and retries on
# LOCAL_OVERFLOW. Returns `nothing` with the error raised as `compileClause` raises it.
"""
    compileGoalClause(gd, ld, goal, m, base) -> Clause, or nothing

Compile `goal`, under the bindings in `ld`, to a temporary clause of `'<meta-call>'/1` in module `m` for the
frame at `base` (= `lTop`), writing its pseudo variables' cells as upstream does (pl-comp.c).
"""
function compileGoalClause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goal::T, m::module_t{T}, base::Int
)::Union{Nothing, Clause{T}} where {T}
    proc = gd.procedures_dcall1
    def = proc.definition
    body = localGoal(gd, ld, goal)
    ci = compileInfo{T}(0, m, proc)
    ci.islocal = true
    ci.subclausearg = false
    ci.argvars = 1
    ci.argvar = 1
    ci.local_ld = ld
    ci.local_base = base
    ci.head_unify = false
    nv = analyse_variables!(gd, ci, nothing, body)
    ensureLocalSpace(ld, nv + LOCAL_MARGIN) || return nothing
    _local_cell!(ci, Int(VAROFFSET(1)), body)                  # *g = *body
    ci.variables = nv
    initMerge!(ci)
    bi = PC(ci)
    rc = compileBody!(gd, ld, ci, body, I_DEPART)
    if rc != BOOLEX_TRUE
        if rc == NOT_CALLABLE
            b = new_term_ref(ld)                               # pushWordAsTermRef(body)
            ld.slots[b + 1] = body
            PL_error(ld, ERR_TYPE, mk_sym(T, :callable), b)
        elseif rc == MAX_ARITY_OVERFLOW
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_procedure_arity))
        end
        return nothing                                         # goto exit_fail
    end
    Output_0!(ci, I_EXIT)
    flags = GOAL_CLAUSE
    if ci.codes[bi + 1] == I_CUT                               # OpCode(ci, bi) == encode(I_CUT)
        flags |= COMMIT_CLAUSE
    end
    @assert ci.argvars == ci.argvar "compileGoalClause: $(ci.argvars) argvars counted, $(ci.argvar) compiled"
    code_size = length(ci.codes)
    variables = ci.variables + SIZEOF_CREF_CLAUSE + sizeofClause(code_size)  # cl->variables += p-p0
    ensureLocalSpace(ld, variables + LOCAL_MARGIN + SIZEOF_CHOICE) || return nothing
    return Clause{T}(
        def, global_generation(gd), GEN_INFINITE, clsize_t(variables), clsize_t(nv), flags,
        ci.codes, ci.literals, ci.procedures, UInt32(0), UInt32(0), UInt32(0)
    )
end

# ── a definition's Prolog reference (pl-comp.c) ─────────────────────────────────────────────────
# PORT: pl-comp.c unify_functor
# DIVERGES: the term is BUILT and returned (see `unify_definition`); the functor is the definition's
# name and arity.
"`Name/Arity` (with `GP_NAMEARITY` in `how`), else a head of fresh variables, for `def` (pl-comp.c)."
function unify_functor(::Type{T}, def::Definition{T}, how::Int)::T where {T}
    if (how & GP_NAMEARITY) != 0
        return mk_expr(T, T[mk_sym(T, :/), def.name, mk_gnd(T, def.arity)])
    end
    def.arity == 0 && return def.name
    k = fresh_var_keys!(def.arity)
    return mk_expr(T, T[def.name; [mk_var(T, k + UInt64(i)) for i in 0:(def.arity - 1)]])
end

# PORT: pl-comp.c unify_definition
# DIVERGES: the head is always a FRESH reference here, so the term is built and returned — upstream's
# unbound-head branch; `thehead` (the plain head, for callers that want it) is not returned. The
# database `gd` is an argument: the definition's module is its index into `gd`'s table (src/pl-incl.jl).
# NOT PORTED: the bound-head branch, which matches a given `M:Head` against the definition (clause/3
# by reference, predicate_property/2: not ported).
"""
    unify_definition(gd, ctx, def, how) -> T

The Prolog reference of `def` as seen from module `ctx` (pl-comp.c): `Name/Arity` (`GP_NAMEARITY`) or
its head, qualified `Module:…` unless `def` is `ctx`'s, or a system module's under `GP_HIDESYSTEM`
(`GP_QUALIFY` always qualifies).
"""
function unify_definition(
    gd::PL_global_data{T}, ctx::module_t{T}, def::Definition{T}, how::Int
)::T where {T}
    m = gd.modules[def.module_]
    if (how & GP_QUALIFY) == 0 &&
        (m.index == ctx.index || ((how & GP_HIDESYSTEM) != 0 && (m.flags & M_SYSTEM) != 0))
        return unify_functor(T, def, how)
    end
    return mk_expr(T, T[mk_sym(T, :(:)), m.atom, unify_functor(T, def, how)])
end

# ── assert/1, assertz/1, asserta/1 (pl-comp.c) ───────────────────────────────────────────────
# PORT: pl-comp.c is_neck
# DIVERGES: the SSU necks `=>/2` and `?=>/2` are refused (`NotPortedError`): SSU is not ported,
# and taken for facts they would assert other clauses; so no `flags` is set.
"Whether term reference `t` holds a rule, `Head :- Body` (pl-comp.c)."
function is_neck(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    p = deRef(ld, ld.slots[t + 1])
    if isTerm(p)
        _has_functor(p, sym_key(mk_sym(T, Symbol(":-"))), 2) && return true  # FUNCTOR_prove2
        if _has_functor(p, sym_key(mk_sym(T, Symbol("=>"))), 2) ||
            _has_functor(p, sym_key(mk_sym(T, Symbol("?=>"))), 2)
            throw(NotPortedError{T}(p, "an SSU clause (=>, ?=>)", "SSU"))
        end
    end
    return false
end

# PORT: pl-comp.c get_head_and_body_clause
# DIVERGES: the module is an index into `gd`'s table, passed in and returned with the result (0 for
# upstream's NULL `m`); no `flags` — it carries SSU's necks or `UNIT_CLAUSE`, which `compileClause`
# sets itself from the body `true`; the database `gd` is an argument.
"""
    get_head_and_body_clause(gd, ld, clause, head, body, m) -> (ok, m)

Put the head and the body of the clause in term reference `clause` into `head` and `body` — a fact's
body is `true` — and return the head's module: `m`, or the one its qualifier names (pl-comp.c).
"""
function get_head_and_body_clause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, clause::term_t, head::term_t, body::term_t,
    m::Int
)::Tuple{Bool, Int} where {T}
    if is_neck(ld, clause)
        c = deRef(ld, ld.slots[clause + 1])
        ld.slots[head + 1] = child(c, 2)                         # _PL_get_arg(1, clause, head)
        ld.slots[body + 1] = child(c, 3)                         # _PL_get_arg(2, clause, body)
        ok, m = PL_strip_module_ex(gd, ld, head, m, head)
        ok || return (false, m)
    else
        ld.slots[head + 1] = ld.slots[clause + 1]               # PL_put_term(head, clause): facts
        ld.slots[body + 1] = mk_sym(T, Symbol("true"))          # PL_put_atom(body, ATOM_true)
    end
    return (true, m)
end

# PORT: pl-incl.h sourceloc
# DIVERGES: the file is its atom, the line an `Int`.
"A source location (pl-incl.h `sourceloc`): a file and a line in it."
struct sourceloc{T}
    file::T                                 # name of the file
    line::Int                               # line number
end

# PORT: pl-comp.c assert_term as assert_term!
# DIVERGES: returns the clause or `nothing`, upstream's NULL, the error raised; the database `gd` is
# an argument (upstream: GD); a module is an index into its table — `module_` 0 is upstream's NULL:
# the source module (`LD->modules.source`) when loading (`loc`), else `user` (`PL_strip_module_ex`).
# The clause is checked for cycles and RESOLVED through the bindings before it is compiled
# (`is_acyclic`, `resolve_term`), because `compileClause` takes terms without bindings:
# `representation_error(cyclic_term)` is raised here, where upstream's analysis raises it (after the
# procedure is looked up). A clause the static procedure's error rejects is left to Julia's garbage
# collector (upstream: `freeClause`). The consult path (`loc`, since R1f) is upstream's for a FIRST
# load (pl-srcfile.jl): the clause's file and line, its owner, `overruleImportedProcedure`,
# `redefineProcedure`, the source file's current procedure. NOT PORTED: `PL_CREATE_INCREMENTAL`
# and `PL_CREATE_THREAD_LOCAL` (assert/2's `flags`: no tabling, no threads); the module's assert
# hook (`O_PROLOG_HOOK`: `module_t` has no `hook`); the `CHECK_INTERRUPT` retry (no signal
# handling); system mode (no boot compilation); transactions (`assertDefinition!`'s, not ported
# there). THE COMPILER'S WARNINGS (since R1g): asked for when loading (`owner`), and printed after
# the clause is added — `compiler_warnings(Clause, Warnings)`, whose `Clause` is an UNBOUND
# VARIABLE here, where upstream passes the clause reference: the kernel has no clause references as
# terms (`'$record_clause'/4`), and boot/messages.pl ignores the argument.
"""
    assert_term!(gd, ld, term, module_, where_, owner, loc, flags) -> Clause, or nothing
    assert_term!(gd, ld, term, where_) -> Clause, or nothing

Compile the clause in term reference `term` and add it to its predicate — in the module its head
names, else `module_` (0: `user`, or the source module when loading) — of the database `gd`
(pl-comp.c). assert/1's path (`loc` nothing): at the start (`CL_START`) or the end (`CL_END`); a
predicate that is not yet defined becomes dynamic; a static one that is raises
`permission_error(modify, static_procedure, PI)`. The consult path (`loc` the clause's file and
line, `owner` the file loading it): the clause goes at the end of a static predicate the file
defines. `nothing` with the error raised when the clause is not callable, cyclic, or past
`MAXARITY`, or the predicate may not be defined.
"""
function assert_term!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, term::term_t, module_::Int, where_::Int,
    owner::Union{Nothing, T}, loc::Union{Nothing, sourceloc{T}}, flags::Int
)::Union{Nothing, Clause{T}} where {T}
    source_module = loc !== nothing ? ld.modules_source : 0
    tmp = PL_new_term_refs(ld, 4)
    tmp == 0 && return nothing
    head = tmp + 1
    body = tmp + 2
    warnings = owner !== nothing ? tmp + 3 : 0

    module_ == 0 && (module_ = source_module)

    ok, module_ = PL_strip_module_ex(gd, ld, term, module_, tmp)
    ok || return nothing
    ok, mh = get_head_and_body_clause(gd, ld, tmp, head, body, module_)
    ok || return nothing
    mhead = gd.modules[mh]
    name, arity = get_head_functor(ld, head, 0)
    arity < 0 && return nothing                                 # not callable, arity too high
    proc = isCurrentProcedure(sym_key(name), arity, mhead)
    if proc === nothing
        if checkModifySystemProc(gd, ld, sym_key(name), arity)
            proc = lookupProcedure(name, arity, mhead)
        end
        proc === nothing && return nothing
    end
    flags == 0 || throw(
        NotPortedError{T}(
            name,
            "assert_term: PL_CREATE_INCREMENTAL/THREAD_LOCAL",
            "no tabling, threads"
        )
    )
    h = deRef(ld, ld.slots[head + 1])
    b = deRef(ld, ld.slots[body + 1])
    if !is_acyclic(ld, h) || !is_acyclic(ld, b)                 # CYCLIC_HEAD, CYCLIC_BODY
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :cyclic_term))
        return nothing
    end
    clause = compileClause(
        gd, ld, resolve_term(ld, h), resolve_term(ld, b), proc, gd.modules[module_],
        warnings
    )
    clause === nothing && return nothing
    def = proc.definition                                       # getProcDefinition(proc)

    # If loc is defined, we are called from '$record_clause'/2. This code takes care of
    # reconsult, redefinition, etc.
    if loc !== nothing
        sf = lookupSourceFile(gd, loc.file, true)::SourceFile{T}
        clause.line_no = UInt32(loc.line)
        clause.source_no = UInt32(sf.index)
        own = owner === nothing ? loc.file : owner              # if ( !loc->file ) …: never
        of = if sym_key(own) == sym_key(loc.file)
            sf
        else
            lookupSourceFile(gd, own, true)::SourceFile{T}
        end
        clause.owner_no = UInt32(of.index)

        overruleImportedProcedure(gd, ld, proc, mhead) || return nothing   # error: freeClause
        def = proc.definition                                   # may be changed

        if proc !== of.current_procedure
            if _impl_any_defined(def)
                redefineProcedure(gd, ld, proc, of, 0) || return nothing
            end
            # locks predicates as system predicates in system mode: no system mode here
            if !isDefinedProcedure(gd, proc)
                def.flags &= ~HIDE_CHILDS                       # truePrologFlag(PLFLAG_DEBUGINFO)
            end
            addProcedureSourceFile(of, proc)
            of.current_procedure = proc
        end

        cref = assertProcedureSource(gd, of, proc, clause)
        clause = cref.clause

        if warnings != 0 && !PL_get_nil(ld, warnings)
            fid = PL_open_foreign_frame(ld)
            cl = PL_new_term_ref(ld)                            # PL_put_clref(cl, clause): unbound
            rc = printMessage(
                ld, :warning,
                mk_expr(
                    T,
                    T[
                        mk_sym(T, :compiler_warnings),
                        ld.slots[cl + 1],
                        ld.slots[warnings + 1]
                    ]
                )
            )
            PL_discard_foreign_frame(ld, fid)
            rc || return nothing
        end
        return clause
    end

    # assert[az]/1
    if (def.flags & P_DYNAMIC) == 0
        if isDefinedProcedure(gd, proc)
            PL_error(ld, ERR_MODIFY_STATIC_PROC, proc)
            return nothing                                      # derror: freeClause(clause)
        end
        setDynamicDefinition!(def, true) || return nothing
    end
    assertProcedure!(gd, proc, clause, where_)
    return clause                                               # cref->value.clause
end

assert_term!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, term::term_t, where_::Int
) where {T} = assert_term!(gd, ld, term, 0, where_, nothing, nothing, 0)

"The database of the running query (`ld.GD`, set by `PL_open_query`): a built-in's GD."
function _query_gd(ld::PL_local_data{T})::PL_global_data{T} where {T}
    gd = ld.GD
    gd === nothing && error("a built-in that needs the database runs outside a query")
    return gd
end

# PORT: pl-comp.c assertz1 as pl_assertz1_va
# (PRED_IMPL("assertz", 1, assertz1, PL_FA_TRANSPARENT))
"`assertz/1` and `assert/1` (pl-comp.c): add the clause at the end of its predicate."
function pl_assertz1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return assert_term!(_query_gd(ld), ld, A1, CL_END) !== nothing ? FTRUE : FFALSE
end

# PORT: pl-comp.c asserta1 as pl_asserta1_va
# (PRED_IMPL("asserta", 1, asserta1, PL_FA_TRANSPARENT))
"`asserta/1` (pl-comp.c): add the clause at the start of its predicate."
function pl_asserta1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return assert_term!(_query_gd(ld), ld, A1, CL_START) !== nothing ? FTRUE : FFALSE
end

# PORT: pl-comp.c record_clause
# DIVERGES: the database is the running query's (`_query_gd`); `ref` 0 is upstream's NULL
# (`'$record_clause'/4`, the clause reference, is not ported: no clause references as terms). The
# source `-` is the start of the term read last (`LD->read_source`: `source_file_name`,
# `source_line_no`).
"Compile the clause `term` from loading the file `owner`, at the source location `source` (pl-comp.c)."
function record_clause(
    ld::PL_local_data{T}, term::term_t, owner::term_t, source::term_t, ref::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    a_owner = PL_get_atom_ex(ld, owner)
    a_owner === nothing && return false

    a = PL_get_atom(ld, source)
    w = deRef(ld, ld.slots[source + 1])
    if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :-))
        f = ld.read_source.file
        line = ld.read_source.position.lineno
        @assert line != -1 && f !== nothing
        loc = sourceloc{T}(f, line)                             # source_file_name, source_line_no
    elseif _hasFunctor(w, mk_sym(T, :(:)), 2)                   # file:line
        arg = PL_new_term_ref(ld)
        ld.slots[arg + 1] = child(w, 2)
        file = PL_get_atom_ex(ld, arg)
        file === nothing && return false
        ld.slots[arg + 1] = child(w, 3)
        line = PL_get_integer_ex(ld, arg)
        line === nothing && return false
        loc = sourceloc{T}(file, line)
    else
        return PL_type_error(ld, "source-location", source)
    end

    clause = assert_term!(gd, ld, term, 0, CL_END, a_owner, loc, 0)
    if clause !== nothing
        ref == 0 ||
            throw(NotPortedError{T}(a_owner, "'\$record_clause'/4", "no clause references"))
        return true
    end
    return false
end

# PORT: pl-comp.c record_clause as pl_record_clause3_va
# (PRED_IMPL("$record_clause", 3, record_clause, 0))
"`'\$record_clause'(+Term, +Owner, +Source)` (pl-comp.c): compile a clause from loading a file."
function pl_record_clause3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    return record_clause(ld, A1, A2, A3, 0) ? FTRUE : FFALSE
end

# PORT: pl-comp.c BeginPredDefs as PL_predicates_from_comp
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order
# (c:9193-9223); `META` is `PL_FA_TRANSPARENT` (c:9190) and `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-comp.c's registration table (`BeginPredDefs(comp)`): the ported entries."
const PL_predicates_from_comp = (
    PL_extension("\$record_clause", 3, pl_record_clause3_va, PL_FA_VARARGS),
    PL_extension("assert", 1, pl_assertz1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension(
        "assertz", 1, pl_assertz1_va, PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS
    ),
    PL_extension(
        "asserta", 1, pl_asserta1_va, PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS
    )
)

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
# (clause/3) or goal clauses. `bvar_access` (since V9d) is a BitVector, `nothing` where upstream's
# is NULL, and `bvar_args` the terms of the moved unifications, by argument. A literal is the
# very term of the clause's table (since V1 L2), so its kind comes back exactly; a nested void is a fresh
# variable of its own.
"""
    decompile_head!(ld, clause, head, base) -> Bool
    decompile_head!(ld, clause, head, base, bvar_access, bvar_args) -> Bool

Rebuild the head arguments of `clause` from its code and literal table — slot `i`'s variable has
key `base + i` — unifying `head`'s arguments with them in turn (pl-comp.c). With `bvar_access`
(`mark_bvar_access`): an argument the body reads whose head code is not a void holds a
unification MOVED into the head — `head`'s argument is unified with the slot's variable, the term
goes to `bvar_args`, and the bit stays set; every other bit is cleared.
"""
function decompile_head!(
    ld::PL_local_data{T}, clause::Clause{T}, head::T, base::UInt64,
    bvar_access::Union{Nothing, BitVector}, bvar_args::Union{Nothing, Vector{T}}
)::Bool where {T}
    arity = clause.predicate.arity                              # di->arity
    arity == 0 && return true                                   # PL_unify_atom(head, name)
    argn = 0                                                    # the head argument being built
    frames::Union{Nothing, Vector{DecompileFrame{T}}} = nothing
    write_bvar = false                                          # this argument's term is moved
    PC = Code(clause, 1)
    while true
        c = decode(PC)
        local v::T
        if bvar_access !== nothing && !write_bvar &&
            (frames === nothing || isempty(frames)) &&
            argn < arity && bvar_access[argn + 1] && c != I_NOP && c != I_CHP
            if c != H_VOID && c != H_VOID_N && c != I_ENTER
                # Found moved var for arg: it is H_VOID; move the output to di->bvar_args
                pl_unify!(ld, child(head, argn + 2), mk_var(T, base + UInt64(argn))) ||
                    return false
                write_bvar = true
            else
                bvar_access[argn + 1] = false
            end
        end
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
                    if bvar_access !== nothing                  # not moved
                        bvar_access[argn + 1] = false
                    end
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
        elseif c == I_EXITFACT || c == I_ENTER || c == I_EXITCATCH
            @assert frames === nothing || isempty(frames)
            while argn < arity                                  # trailing voids: their slots
                if bvar_access !== nothing
                    bvar_access[argn + 1] = false
                end
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
            if write_bvar
                bvar_args === nothing &&
                    error("decompile_head: bvar_access without bvar_args")
                bvar_args[argn + 1] = v
                write_bvar = false
            else
                pl_unify!(ld, child(head, argn + 2), v) || return false
            end
            argn += 1                                           # NEXTARG
        else
            push!(frames[end].kids, v)
        end
        PC = stepPC(PC)
    end
end

decompile_head!(
    ld::PL_local_data{T}, clause::Clause{T}, head::T, base::UInt64
) where {T} = decompile_head!(ld, clause, head, base, nothing, nothing)

# PORT: pl-comp.c add_bvar_access
# DIVERGES: returns the new maximum, where upstream updates it through a pointer.
"Record that the code reads frame slot `index`, if that is a head argument (pl-comp.c)."
function add_bvar_access!(bits::BitVector, index::Int, max::Int)::Int
    if index < length(bits)                                     # index < di->arity
        bits[index + 1] = true
        if index > max
            max = index
        end
    end
    return max
end

# PORT: pl-comp.c mark_bvar_access
# DIVERGES: returns the bits — `nothing` where upstream sets `di->bvar_access` to NULL — and no
# `bvar_args` term references: `decompile!` makes that vector. An operand is one word here, so
# there is no `VM_DYNARGC`, `CA1_FLOAT` or `CA1_WORD` to step over.
"""
The head arguments the clause's code READS (pl-comp.c): by `B_VAR<N>`, by an operand that is a
variable to read, by an inline unification of two variables. One that the head code does not
leave a void holds a unification moved into the head. `nothing` when no argument is read.
"""
function mark_bvar_access(clause::Clause{T})::Union{Nothing, BitVector} where {T}
    bits = falses(clause.predicate.arity)
    max = -1
    codes = clause.codes
    pc = 1
    while pc <= length(codes)
        c = codes[pc]
        info = codeTable(c)
        if c == B_VAR0
            max = add_bvar_access!(bits, 0, max)
        elseif c == B_VAR1
            max = add_bvar_access!(bits, 1, max)
        elseif c == B_VAR2
            max = add_bvar_access!(bits, 2, max)
        elseif c == B_UNIFY_FF || c == B_UNIFY_FV || c == B_UNIFY_VF
            max = add_bvar_access!(bits, VARNUM(codes[pc + 1]), max)
            max = add_bvar_access!(bits, VARNUM(codes[pc + 2]), max)
        else
            for i in 1:Int(info.arguments)
                if info.argtype[i] == CA1_VAR                   # CA1_FVAR is a write
                    max = add_bvar_access!(bits, VARNUM(codes[pc + i]), max)
                end
            end
        end
        pc += 1 + info.arguments                                # stepPC(pc)
    end
    max < 0 && return nothing                                   # moved, but not used in the body
    return bits
end

"A void the decompiler meets: in an argument, its slot's variable; in a compound, a fresh one."
function _decompile_void(
    ::Type{T}, frames::Union{Nothing, Vector{DecompileFrame{T}}}, base::UInt64, argn::Int
)::T where {T}
    (frames === nothing || isempty(frames)) && return mk_var(T, base + UInt64(argn))   # FIRSTVAR
    return mk_var(T, fresh_var_keys!(1))
end

# ── decompiling a clause: head and body (pl-comp.c), V9d ────────────────────────────────────────
# PORT: pl-comp.c decompileInfo
# DIVERGES: `pc` is an index into the clause's code; `variables` is `base` — slot `i`'s variable has
# key `base + i`, as `decompile_head!`'s — so a variable reference IS the variable (no `makeVarRef`
# resolved later by `unifyVar`); `argp` is the decompilation stack, a Vector where upstream builds
# on top of the local stack; `frames` are the compounds being built, upstream's argument stack
# (see `decompile_head!`). No `nvars`, `arity`, `bindings` (clause/3's variable names) or
# `bvar_access` (the moved unifications: see `decompile!`).
"The state of one clause decompilation (pl-comp.c `decompileInfo`)."
mutable struct decompileInfo{T}
    const clause::Clause{T}
    pc::Int                                     # pc: pc for decompilation
    const base::UInt64                          # (variables: slot i's variable is key base + i)
    const argp::Vector{T}                       # argp: the decompilation stack
    const frames::Vector{DecompileFrame{T}}     # (the compounds being built)
    # variables, when the clause runs in a frame (`decompile_body_range`): the local stack's slots
    # and the frame's position — slot i's term is the frame's own; `nothing`: fresh variables
    const variables::Union{Nothing, Tuple{Vector{T}, Int}}
end

decompileInfo{T}(
    clause::Clause{T}, pc::Int, base::UInt64, argp::Vector{T},
    frames::Vector{DecompileFrame{T}}
) where {T} = decompileInfo{T}(clause, pc, base, argp, frames, nothing)

"The variable of the slot at frame offset `index` (upstream's `makeVarRef`, resolved at once)."
function _dvar(di::decompileInfo{T}, index::code)::T where {T}
    v = di.variables
    v === nothing && return mk_var(T, di.base + (index - VAROFFSET(0)))
    return v[1][varFrameP(v[2], Int(index)) + 1]            # the running frame's own cell
end

"Push `v`: an argument of the compound being built, or the next value on the decompilation stack (`*ARGP++ = v`)."
function _dpush!(di::decompileInfo{T}, v::T)::Nothing where {T}
    if isempty(di.frames)
        push!(di.argp, v)
    else
        push!(di.frames[end].kids, v)
    end
    return nothing
end

# PORT: pl-comp.c build_term
# DIVERGES: the functor is its name and arity; the arguments are terms already (see
# `decompileInfo`), so nothing is unified here and nothing can overflow.
"""
Build `name/arity` from the top `arity` values of the decompilation stack and push it back
(pl-comp.c): the last value is the last argument, or with `dir` 1 the first.
"""
function build_term!(
    di::decompileInfo{T}, name::T, arity::Int, dir::Int=-1
)::Nothing where {T}
    if arity == 0
        push!(di.argp, name)                                    # *ARGP++ = nameFunctor(f)
        return nothing
    end
    n = length(di.argp)
    kids = Vector{T}(undef, arity + 1)
    kids[1] = name
    for i in 1:arity
        kids[i + 1] = dir == -1 ? di.argp[n - arity + i] : di.argp[n - i + 1]
    end
    resize!(di.argp, n - arity)
    push!(di.argp, mk_expr(T, kids))
    return nothing
end

# PORT: pl-comp.c decompileBodyNoShift
# DIVERGES: every instruction the kernel's compiler emits in a body — the `H_` ones too, which
# build the other side of an inline `Var = Term` (the others raise, as upstream's
# `sysError` for an unknown instruction); a constant is the clause's literal, exactly; a compound
# under construction is a frame closed at its `B_POP`, with the `B_RFUNCTOR`/`B_RLIST` chain of its
# last argument (as `decompile_head!`); returns nothing — there is no stack to overflow, so no
# `*_OVERFLOW` and no retry loop (`decompileBody`'s). `end_` is an instruction, `code(typemax)` for
# upstream's `(code)-1`; `until` is an index, 0 for NULL. NOT PORTED: `D_BREAK` (no debugger), the
# arithmetic instructions but `A_ADD_FC`, and modules (R2).
"""
Decompile body code from `di.pc` up to the instruction `end_` or the position `until` (pl-comp.c):
each goal is built on the decompilation stack from its arguments' instructions, and the goals are
joined by `,/2`, right-nested — one term is left on the stack.
"""
function decompileBodyNoShift!(
    di::decompileInfo{T}, end_::code, until::Int
)::Nothing where {T}
    pushed = 0                                                  # Subclauses pushed on the stack
    codes = di.clause.codes
    lits = di.clause.literals
    while di.pc != until
        op = codes[di.pc]
        di.pc += 1
        if op == end_
            di.pc -= 1
            break
        end
        if op == I_NOP || op == I_CHP
            continue
        elseif op == B_ATOM || op == B_SMALLINT || op == B_FLOAT || op == B_MPZ ||
            op == B_MPQ || op == B_STRING || op == H_ATOM || op == H_SMALLINT ||
            op == H_FLOAT || op == H_MPZ || op == H_MPQ || op == H_STRING
            _dpush!(di, lits[codes[di.pc]])
            di.pc += 1
        elseif op == B_NIL || op == H_NIL
            _dpush!(di, mk_nil(T))
        elseif op == B_ARGVAR || op == B_ARGFIRSTVAR || op == B_FIRSTVAR ||
            op == B_UNIFY_VAR || op == B_UNIFY_FIRSTVAR || op == B_VAR ||
            op == H_FIRSTVAR || op == H_VAR
            _dpush!(di, _dvar(di, codes[di.pc]))
            di.pc += 1
        elseif op == B_VAR0
            _dpush!(di, _dvar(di, VAROFFSET(0)))
        elseif op == B_VAR1
            _dpush!(di, _dvar(di, VAROFFSET(1)))
        elseif op == B_VAR2
            _dpush!(di, _dvar(di, VAROFFSET(2)))
        elseif op == B_UNIFY_FF || op == B_UNIFY_FV || op == B_UNIFY_VV
            _dpush!(di, _dvar(di, codes[di.pc]))
            _dpush!(di, _dvar(di, codes[di.pc + 1]))
            di.pc += 2
            build_term!(di, mk_sym(T, Symbol("=")), 2)          # b_unify_exit
            pushed += 1
        elseif op == B_UNIFY_VF
            _dpush!(di, _dvar(di, codes[di.pc + 1]))            # ARGP[0]: the second operand
            _dpush!(di, _dvar(di, codes[di.pc]))                # ARGP[1]: the first
            di.pc += 2
            build_term!(di, mk_sym(T, Symbol("=")), 2)
            pushed += 1
        elseif op == B_UNIFY_FC || op == B_UNIFY_VC || op == B_EQ_VC || op == B_NEQ_VC
            _dpush!(di, _dvar(di, codes[di.pc]))
            _dpush!(di, lits[codes[di.pc + 1]])
            di.pc += 2
            f = if op == B_EQ_VC
                Symbol("==")
            elseif op == B_NEQ_VC
                Symbol("\\==")
            else
                Symbol("=")
            end
            build_term!(di, mk_sym(T, f), 2)
            pushed += 1
        elseif op == B_EQ_VV || op == B_NEQ_VV
            _dpush!(di, _dvar(di, codes[di.pc]))
            _dpush!(di, _dvar(di, codes[di.pc + 1]))
            di.pc += 2
            build_term!(di, mk_sym(T, op == B_EQ_VV ? Symbol("==") : Symbol("\\==")), 2)
            pushed += 1
        elseif op == B_VOID || op == H_VOID
            _dpush!(di, mk_var(T, fresh_var_keys!(1)))          # setVar(*ARGP++)
        elseif op == H_VOID_N
            for _ in 1:Int(codes[di.pc])
                _dpush!(di, mk_var(T, fresh_var_keys!(1)))
            end
            di.pc += 1
        elseif op == B_FUNCTOR || op == B_RFUNCTOR || op == H_FUNCTOR || op == H_RFUNCTOR
            w = codes[di.pc]
            di.pc += 1
            i = functor_literal(w)
            kids = i == 0 ? T[] : T[lits[i]]                    # `$expr/n`: no head symbol
            push!(
                di.frames,
                DecompileFrame{T}(
                    kids, length(kids) + functor_arity(w),
                    op == B_FUNCTOR || op == H_FUNCTOR
                )
            )
        elseif op == B_LIST || op == B_RLIST || op == H_LIST || op == H_RLIST
            push!(
                di.frames,
                DecompileFrame{T}(
                    T[mk_sym(T, LIST_CONS_NAME)], 3, op == B_LIST || op == H_LIST
                )
            )
        elseif op == H_LIST_FF
            x = _dvar(di, codes[di.pc])
            y = _dvar(di, codes[di.pc + 1])
            di.pc += 2
            _dpush!(di, mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), x, y]))
        elseif op == B_POP || op == H_POP
            local v::T
            while true                                          # the R chain, then the pushed one
                f = pop!(di.frames)
                while length(f.kids) < f.need
                    push!(f.kids, mk_var(T, fresh_var_keys!(1)))
                end
                v = mk_expr(T, f.kids)
                f.pushed && break
                push!(di.frames[end].kids, v)
            end
            _dpush!(di, v)
        elseif op == B_UNIFY_EXIT
            build_term!(di, mk_sym(T, Symbol("=")), 2)
            pushed += 1
        elseif op == A_ADD_FC
            push!(di.argp, _dvar(di, codes[di.pc]))             # rvar
            push!(di.argp, _dvar(di, codes[di.pc + 1]))         # ivar
            push!(di.argp, lits[codes[di.pc + 2]])              # consInt(add)
            di.pc += 3
            build_term!(di, mk_sym(T, Symbol("+")), 2)          # create B+<n>
            build_term!(di, mk_sym(T, :is), 2)
            pushed += 1
        elseif op == I_FAIL
            push!(di.argp, mk_sym(T, :fail))
            pushed += 1
        elseif op == I_TRUE
            push!(di.argp, mk_sym(T, Symbol("true")))
            pushed += 1
        elseif op == I_VAR || op == I_NONVAR || op == I_INTEGER || op == I_RATIONAL ||
            op == I_FLOAT || op == I_NUMBER || op == I_ATOMIC || op == I_ATOM ||
            op == I_STRING || op == I_COMPOUND || op == I_CALLABLE
            push!(di.argp, _dvar(di, codes[di.pc]))             # common_type_test
            di.pc += 1
            build_term!(di, mk_sym(T, _type_test_name(op)), 1)
            pushed += 1
        elseif op == I_CUT
            push!(di.argp, mk_sym(T, Symbol("!")))
            pushed += 1
        elseif op == I_CALL1 || op == I_CALLN
            n = op == I_CALLN ? Int(codes[di.pc]) : 0           # BUILD_TERM(FUNCTOR_call1) / callN
            op == I_CALLN && (di.pc += 1)
            build_term!(di, mk_sym(T, :call), n + 1)
            pushed += 1
        elseif op == I_DEPART || op == I_CALL
            def = di.clause.procedures[codes[di.pc]].definition
            di.pc += 1
            build_term!(di, def.name, def.arity)
            pushed += 1
        elseif op == C_VAR || op == C_JMP || op == C_CUT || op == C_FASTCUT
            di.pc += 1
        elseif op == C_LCUTIFTHEN || op == C_LSCUT || op == C_LCUT      # a `!` in a condition
            di.pc += 1
            push!(di.argp, mk_sym(T, Symbol("!")))
            pushed += 1
        elseif op == L_NOLCO
            di.pc += Int(codes[di.pc])
            di.pc += 1
        elseif op == C_VAR_N
            di.pc += 2
        elseif op == C_OR                                       # A ; B
            to_jump = Int(codes[di.pc])                         # DECOMPILETOJUMP: A
            di.pc += 1
            decompileBodyNoShift!(di, code(typemax(UInt64)), di.pc + to_jump)
            di.pc -= 1                                          # get C_JMP argument
            to_jump = Int(codes[di.pc])                         # DECOMPILETOJUMP: B
            di.pc += 1
            decompileBodyNoShift!(di, code(typemax(UInt64)), di.pc + to_jump)
            build_term!(di, mk_sym(T, Symbol(";")), 2)
            pushed += 1
        elseif op == C_IFTHENELSE || op == C_FASTCOND || op == C_SOFTIF    # A -> B ; C (ifcommon)
            icut = if op == C_FASTCOND
                C_FASTCUT
            elseif op == C_SOFTIF                               # A *-> B ; C
                C_SOFTCUT
            else
                C_CUT
            end
            arrow = op == C_SOFTIF ? Symbol("*->") : Symbol("->")
            di.pc += 1                                          # skip the 'MARK' variable
            jmp = Int(codes[di.pc])
            di.pc += 1
            adr1 = di.pc + jmp
            decompileBodyNoShift!(di, icut, 0)                  # A
            di.pc += 2                                          # skip the cut
            decompileBodyNoShift!(di, code(typemax(UInt64)), adr1)      # B
            build_term!(di, mk_sym(T, arrow), 2)
            di.pc -= 1
            to_jump = Int(codes[di.pc])                         # DECOMPILETOJUMP: C
            di.pc += 1
            decompileBodyNoShift!(di, code(typemax(UInt64)), di.pc + to_jump)
            build_term!(di, mk_sym(T, Symbol(";")), 2)
            pushed += 1
        elseif op == C_NOT                                      # \+ A
            di.pc += 2                                          # skip the two arguments
            decompileBodyNoShift!(di, C_CUT, 0)                 # A
            di.pc += 3                                          # skip C_CUT <n> and C_FAIL
            build_term!(di, mk_sym(T, Symbol("\\+")), 1)
            pushed += 1
        elseif op == C_DET                                      # $ A
            di.pc += 2                                          # skip the two arguments
            decompileBodyNoShift!(di, C_DETTRUE, 0)             # A
            while true                                          # Skip to after C_DETFALSE
                op = codes[di.pc]
                di.pc += 1 + codeTable(op).arguments            # stepPC(PC)
                op == C_DETFALSE && break
            end
            build_term!(di, mk_sym(T, Symbol("\$")), 1)
            pushed += 1
        elseif op == C_IFTHEN || op == C_SOFTIFTHEN             # A -> B, A *-> B (c_ifthen)
            cut = op == C_IFTHEN ? C_CUT : C_SCUT               # C_CUT takes 1 arg, C_SCUT 0
            di.pc += 1
            decompileBodyNoShift!(di, cut, 0)                   # A
            di.pc += cut == C_CUT ? 2 : 1                       # skip C_(S)CUT
            decompileBodyNoShift!(di, C_END, 0)                 # B
            di.pc += 1
            build_term!(di, mk_sym(T, op == C_IFTHEN ? Symbol("->") : Symbol("*->")), 2)
            pushed += 1
        elseif op == I_CATCH                                    # (since V9f)
            push!(di.argp, mk_sym(T, Symbol("\$catch")))
            pushed += 1
        elseif op == I_DET                                      # (since V9f)
            push!(di.argp, mk_sym(T, Symbol("\$")))
            pushed += 1
        elseif op == I_EXIT || op == I_EXITCATCH
            # break (out of upstream's switch): nothing
        else
            error(
                "Decompiler: unknown instruction in clause body: $(codeTable(op).name)"
            )
        end
    end

    while pushed > 1
        build_term!(di, mk_sym(T, Symbol(",")), 2)
        pushed -= 1
    end
    return nothing
end

"The name of the type test instruction `op` compiles (`type_tests`, and var/1, nonvar/1)."
function _type_test_name(op::code)::Symbol
    op == I_VAR && return :var
    op == I_NONVAR && return :nonvar
    for (instruction, name) in type_tests
        op == instruction && return Symbol(name)
    end
    error("_type_test_name: $(codeTable(op).name) is not a type test")
end

# PORT: pl-comp.c decompileBody
# DIVERGES: no foreign frame and no retry after a stack shift (see `decompileBodyNoShift!`).
"Decompile body code from `di.pc` (see `decompileBodyNoShift!`) and unify `body` with it (pl-comp.c)."
function decompileBody!(
    ld::PL_local_data{T}, di::decompileInfo{T}, body::T, end_::code, until::Int
)::Bool where {T}
    decompileBodyNoShift!(di, end_, until)
    @assert length(di.argp) == 1 && isempty(di.frames)
    return pl_unify!(ld, body, pop!(di.argp))
end

# PORT: pl-comp.c decompile
# DIVERGES: the clause term is its two sides, `head` and `body` — upstream takes `Head :- Body` or a
# bare head, and for a fact with a body unifies that with `true` first, as here; the functor of the
# head is not unified (see `decompile_head!`). The body's code starts after `I_ENTER`, found by
# stepping over the head's instructions, where upstream's head decompiler leaves `di->pc` there. No
# `bindings`; no `I_CONTEXT` (modules). A clause with `CL_HEAD_TERMS` gets its moved unifications
# back (`mark_bvar_access`, the head decompiler, `moved_unifications`): they are BUILT here, as
# `Var = Term` goals before the body's, and unified with `body` in one step — upstream unifies
# `body` conjunct by conjunct as it goes.
"""
    decompile!(ld, clause, head, body) -> Bool

Unify `head` and `body` with the clause `clause`'s code describes, with fresh variables, under the
bindings in `ld` (pl-comp.c): a fact's body is `true`. The bindings stay on the trail for the
caller to undo.
"""
function decompile!(
    ld::PL_local_data{T}, clause::Clause{T}, head::T, body::T
)::Bool where {T}
    nv = Int(clause.prolog_vars)
    base = nv == 0 ? UInt64(0) : fresh_var_keys!(nv)
    bvar_access = (clause.flags & CL_HEAD_TERMS) != 0 ? mark_bvar_access(clause) : nothing
    if bvar_access !== nothing                                  # (a rule: a fact moves nothing)
        bvar_args = Vector{T}(undef, length(bvar_access))
        decompile_head!(ld, clause, head, base, bvar_access, bvar_args) || return false
        pc = _body_start(clause)
        return moved_unifications!(
            ld, clause, pc, base, body, bvar_access, bvar_args, clause.codes[pc] != I_EXIT
        )
    end
    if (clause.flags & UNIT_CLAUSE) != 0                        # fact; deal with a :- A
        pl_unify!(ld, body, mk_sym(T, Symbol("true"))) || return false
        return decompile_head!(ld, clause, head, base)
    end
    decompile_head!(ld, clause, head, base) || return false
    pc = _body_start(clause)
    if clause.codes[pc] == I_EXIT
        return pl_unify!(ld, body, mk_sym(T, Symbol("true")))
    end
    di = decompileInfo{T}(clause, pc, base, T[], DecompileFrame{T}[])
    return decompileBody!(ld, di, body, I_EXIT, 0)
end

# PORT: pl-comp.c decompile_body_range
# DIVERGES: the frame's variables are the local stack's slots and the frame's position (see
# `decompileInfo`); `start` is an index into the clause's code.
"""
Decompile the body code of `clause` from `start` up to the instruction `end_` into term reference
`goal`, with the variables of the running frame `fr` (pl-comp.c).
"""
function decompile_body_range(
    ld::PL_local_data{T}, goal::term_t, fr::Int, clause::Clause{T}, start::Int, end_::code
)::Bool where {T}
    variables = clause.prolog_vars != 0 ? (ld.slots, ld.frames[fr].base) : nothing
    di = decompileInfo{T}(clause, start, UInt64(0), T[], DecompileFrame{T}[], variables)
    return decompileBody!(ld, di, ld.slots[goal + 1], end_, 0)
end

# PORT: pl-comp.c start_of_cdet
# DIVERGES: positions are indexes into the clause's code.
"""
The `C_DET` that starts the guarded area whose `C_DETTRUE` or `C_DETFALSE` is at `pc_error`
(pl-comp.c): walking the clause's code, a `C_DET` whose `C_DETFALSE` is the error location is it;
for a `C_DETTRUE` it is the one with only `C_JMP` and variable balancing between that and its
`C_DETFALSE`.
"""
function start_of_cdet(cl::Clause{T}, pc_error::Int)::Int where {T}
    codes = cl.codes
    pc = 1
    while pc <= length(codes)
        c = codes[pc]
        if c == C_DET
            pcfalse = pc + Int(codes[pc + 2]) + 3
            @assert codes[pcfalse] == C_DETFALSE
            pc_error == pcfalse && return pc

            if codes[pc_error] == C_DETTRUE
                pc2 = pc_error
                found = true
                while pc2 < pcfalse
                    c2 = codes[pc2]
                    if !(c2 == C_DETTRUE || c2 == C_JMP || c2 == C_VAR_N || c2 == C_VAR)
                        found = false                           # goto continue_outer
                        break
                    end
                    pc2 += 1 + codeTable(c2).arguments          # stepPC(pc2)
                end
                found && return pc
            end
        end
        pc += 1 + codeTable(c).arguments                        # stepPC(pc)
    end
    return error("start_of_cdet: no C_DET for the instruction at $pc_error")    # assert(0)
end

# PORT: pl-comp.c det_goal_error
# DIVERGES: the flag is the local data's `prolog_flag_determinism_error`; `found` is a symbol;
# `pc_error` an index into the frame's clause's code. NOT PORTED: the `DEBUG(MSG_DETERMINISM)` line.
"""
    det_goal_error(ld, fr, pc_error, found) -> Bool

The goal of a `\$/1` in frame `fr` — its `C_DETTRUE` or `C_DETFALSE` is at `pc_error` — was not
deterministic: `found` is `:nondet` or `:fail` (pl-comp.c). Under the flag `determinism_error`:
`error` raises `determinism_error(Goal, det, Found, goal)` and returns false, `warning` reports it
and returns true, `silent` returns true.
"""
function det_goal_error(
    ld::PL_local_data{T}, fr::Int, pc_error::Int, found::Symbol
)::Bool where {T}
    cl = (ld.frames[fr].clause::ClauseRef{T}).clause::Clause{T}
    pc_det = start_of_cdet(cl, pc_error)
    a = ld.prolog_flag_determinism_error
    a === :silent && return true

    if found === :fail
        clearUninitialisedVarsFrame(ld, fr, cl.codes, pc_det)
    end

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        goal = PL_new_term_ref(ld)
        rc = decompile_body_range(ld, goal, fr, cl, pc_det + 3, C_DETTRUE)
        if rc
            if a === :warning
                rc = printMessage(
                    ld,
                    :warning,
                    mk_expr(
                        T,
                        T[
                            mk_sym(T, :error),
                            mk_expr(
                                T,
                                T[
                                    mk_sym(T, :determinism_error), ld.slots[goal + 1],
                                    mk_sym(T, :det), mk_sym(T, found), mk_sym(T, :goal)
                                ]
                            ),
                            mk_var(T, fresh_var_keys!(1))
                        ]
                    )
                )
            else
                rc = PL_error(ld, ERR_DET_GOAL, goal, mk_sym(T, :det), mk_sym(T, found))
            end
        end

        PL_close_foreign_frame(ld, fid)

        return rc
    end

    return false
end

"Where a rule's body code starts: after its `I_ENTER` (upstream's `di->pc` after `decompile_head`)."
function _body_start(clause::Clause{T})::Int where {T}
    PC = Code(clause, 1)
    while decode(PC) != I_ENTER
        PC = stepPC(PC)
    end
    return PC.pc + 1
end

# PORT: pl-comp.c moved_unifications
# DIVERGES: builds the whole body — each moved unification as `Var = Term` (upstream's
# `moved_unification`), in argument order, then the body's own goals — and unifies `body` with it
# once, where upstream unifies `body` with `,/2` conjunct by conjunct and then decompiles the rest
# into what is left. With nothing to write `body` is left as it is, as upstream (upstream defect,
# see register Q2).
"""
Unify `body` with the moved unifications of the clause — `Var = Term` for each argument whose
bit `decompile_head!` left set, in order — followed by the body's own goals when it `hasbody`
(pl-comp.c).
"""
function moved_unifications!(
    ld::PL_local_data{T}, clause::Clause{T}, pc::Int, base::UInt64, body::T,
    bvar_access::BitVector, bvar_args::Vector{T}, hasbody::Bool
)::Bool where {T}
    goals = T[]
    for i in 0:(length(bvar_access) - 1)
        if bvar_access[i + 1]                                   # moved_unification(i, eq, a, di)
            push!(
                goals,
                mk_expr(
                    T,
                    T[
                        mk_sym(T, Symbol("=")),
                        mk_var(T, base + UInt64(i)),
                        bvar_args[i + 1]
                    ]
                )
            )
        end
    end
    if hasbody
        di = decompileInfo{T}(clause, pc, base, T[], DecompileFrame{T}[])
        decompileBodyNoShift!(di, I_EXIT, 0)
        @assert length(di.argp) == 1 && isempty(di.frames)
        push!(goals, pop!(di.argp))
    end
    isempty(goals) && return true                               # (see register Q2)
    full = goals[end]
    for k in (length(goals) - 1):-1:1
        full = mk_expr(T, T[mk_sym(T, Symbol(",")), goals[k], full])
    end
    return pl_unify!(ld, body, full)
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
# DIVERGES: returns `(position, in_hvoid)` where upstream updates `*in_hvoid` through a pointer.
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
                # inside the run the H_VOID_N is the target; landing exactly at its end, the
                # next instruction is (upstream defect, fixed in 0728e8c: a single `skip <= 0`
                # returned the H_VOID_N there too, and the argument after the voids read as void)
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
            c == H_POP || c == I_EXITFACT || c == I_ENTER || c == I_EXITCATCH
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
# functor: not found. `H_MPQ` is not found, as `H_MPZ` is (upstream defect, fixed in 97370c0e: the
# switch lacked `H_MPQ`, which fell to `assert(0)`; docs/upstream_reports.md #4).
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
            c == I_ENTER || c == I_EXITCATCH
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
                # an occurs-check error from the head's unification does NOT stop the scan: upstream
                # raises it in `unify_head`, after `decompile`, and checks `exception_term` only when
                # `decompile` fails. swipl 10.1.16 answers from the next clause, the error pending
                # (S10, probed 2026-10-06)
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

# PORT: pl-comp.c clause as pl_clause
# DIVERGES: as the method above, with the body: clause/2 with an unbound clause reference, every
# clause decompiled whole (`decompile!`, since V9d) — a fact's body is `true`.
"""
    pl_clause!(gd, ld, def, head, body, sink)

`clause/2` on predicate `def` (pl-comp.c): in the generation it starts in, unify `head` and `body`
with each clause in turn (`decompile!`) and call `sink(clause)` while the bindings hold; undo them
after each.
"""
function pl_clause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}, head::T, body::T,
    sink::S
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
                if decompile!(ld, clause, head, body)
                    if chp.cref === nothing             # the last one: out
                        popPredicateAccess!(ld, def)
                        popped = true
                        sink(clause)
                        return nothing
                    end
                    sink(clause) || return nothing      # FRG_CUTTED
                end
                # an occurs-check error from the head's unification does NOT stop the scan: upstream
                # raises it in `unify_head`, after `decompile`, and checks `exception_term` only when
                # `decompile` fails. swipl 10.1.16 answers from the next clause, the error pending
                # (S10, probed 2026-10-06)
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
