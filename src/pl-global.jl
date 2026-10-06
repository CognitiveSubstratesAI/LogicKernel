# UPSTREAM: swipl-devel src/pl-global.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE GLOBAL AND THREAD-LOCAL DATA the clause database reads — the fields of SWI-Prolog's
# `struct PL_global_data` (GD) and `struct PL_local_data` (LD) that the ported code uses.
#
# DIVERGES (both structs): upstream has ONE GD per process and one LD per thread, reached through
# globals. The kernel allows no module-level mutable state (tools/lint_globals.jl), so a GD and an
# LD are VALUES the caller creates and passes wherever upstream reads `GD->` or `LD->` — one pair
# per database, over one term type `T`. There are no threads: one LD per GD.

# PORT: pl-global.h PL_global_data
"""
    PL_global_data{T}()

The database-wide state (pl-global.h `struct PL_global_data`): the generation of the database,
the predicates with erased clauses, whether clause GC is running, the control functors the clause
compiler reads (pl-funct.c `registerControlFunctors`, the `CONTROL_F` flags of upstream's functor
table), registered once, when the database is created, as upstream registers them at start-up,
and the `user` module, whose procedure table holds the database's predicates. Field names are
upstream's, nesting flattened (`procedures.dirty` is `procedures_dirty`).
"""
mutable struct PL_global_data{T}
    _generation::gen_t                                          # generation of the database
    procedures_dirty::Dict{Definition{T}, dirty_def_info{T}}    # procedures.dirty
    clauses_cgc_active::Bool                                    # clauses.cgc_active: CGC running
    const functors_control::ControlFunctors                     # functors.array's CONTROL_F
    const modules_user::module_t{T}                             # modules.user: user module
    const modules_system::module_t{T}                           # modules.system: system module
    const subclause_names::SubClauseNames                       # (the ATOM_/FUNCTOR_ tables)
    const code_data::PL_code_data                               # PL_code_data (its supervisors)
    const procedures_dc_call_prolog0::Procedure{T}              # procedures.dc_call_prolog0
    const clauses_top_clause::Clause{T}                         # clauses.top_clause
    const clauses_top_cref::ClauseRef{T}                        # clauses.top_cref
    const atom_nil::T                                           # ATOM_nil, the `[]` term
    const atom_dot::T                                           # ATOM_dot, the `'[|]'` symbol
    const no_literals::Vector{T}                                # (a supervisor's literal table)
end
# DIVERGES: `subclause_names` has no upstream field — upstream's compiler reads its `ATOM_*` and
# `FUNCTOR_*` constants (src/pl-funct.jl); like the control functors, the kernel registers them once
# per database. The user module is created with the database — upstream's initModules creates it, with
# the `system` module, at start-up (pl-modul.c); since V5a2 there is a `system` module too, which the
# built-ins are registered in (`initBuildIns!`, src/pl-ext.jl). There is no module table
# (`modules.table`) and no module links (`supers`: how `user` reaches `system` is the user's open
# question Q-A, V5c) — so a body goal reaches a built-in only through `lookupBodyProcedure`'s ISO
# branch, and a query through its procedure. The shared
# supervisors are the database's (`PL_code_data`, src/pl-incl.jl). `$c_call_prolog/0`, the top
# frame's predicate, is created as `setBuiltinPredicateProperties` creates it (no clauses, flags 0,
# `SUPERVISOR(virgin)`), in the `system` module's table. `initVM` builds the top clause, and then
# the built-ins are registered — upstream registers them first (setup:158, then 160); neither reads
# the other. `atom_nil` and
# `atom_dot` are the terms the VM writes for `[]` and a list cell's head, built once — upstream's are
# constants; `no_literals` is the literal table a supervisor's code has (none).
function PL_global_data{T}() where {T}
    cd = initSupervisors()
    dc = mk_sym(T, Symbol("\$c_call_prolog"))
    dc_def = Definition{T}(
        sym_key(dc), 0, ClauseList{T}(), UInt64(0), dc, cd.virgin, ClauseRef{T}[], cd, 0
    )
    dc_proc = Procedure{T}(dc_def, UInt32(0))
    top_clause, top_cref = initVM(dc_proc)
    system = module_t{T}(
        sym_key(mk_sym(T, :system)), Dict{Tuple{UInt64, Int}, Procedure{T}}(), cd
    )
    system.procedures[(sym_key(dc), 0)] = dc_proc
    gd = PL_global_data{T}(
        gen_t(0),
        Dict{Definition{T}, dirty_def_info{T}}(),
        false,
        registerControlFunctors(T),
        module_t{T}(
            sym_key(mk_sym(T, :user)), Dict{Tuple{UInt64, Int}, Procedure{T}}(), cd
        ),
        system,
        _subclause_names(T),
        cd,
        dc_proc,
        top_clause,
        top_cref,
        mk_nil(T),
        mk_sym(T, Symbol("[|]")),
        T[]
    )
    initBuildIns!(gd)                           # setup:158 (src/pl-ext.jl)
    return gd
end

# PORT: pl-incl.h MODULE_user
"The user module of the database whose global data is `gd` (pl-incl.h `MODULE_user`)."
MODULE_user(gd::PL_global_data{T}) where {T} = gd.modules_user

# PORT: pl-incl.h MODULE_system
"The system module of the database whose global data is `gd`, where built-ins live (pl-incl.h `MODULE_system`)."
MODULE_system(gd::PL_global_data{T}) where {T} = gd.modules_system

# ── the kernel's variable keys ───────────────────────────────────────────────────────────────────
# DIVERGES: SWI's fresh variables are new cells on the global stack, unique by address. Interface
# variables are keys, so the kernel takes its own from the top half of the key space (callers own
# the bottom half — see `var_key`), from ONE PROCESS-WIDE counter: an answer retained from one
# `PL_local_data` and passed into another can carry a kernel key, which a per-instance counter
# would issue again (user, 2026-10-03). Module-level state, allowlisted in tools/lint_globals.jl:
# a monotonic source of fresh ids cannot carry behaviour from one caller to another.
# the next free kernel variable key (see `fresh_var_keys!`) — a comment, not a docstring: a docstring
# on a constant keeps a second binding to the value, which the global-state lint rightly flags
const _KERNEL_VAR_COUNTER = Threads.Atomic{UInt64}(KERNEL_VAR_BASE)

"""
    fresh_var_keys!(n) -> UInt64

Reserve `n` kernel variable keys, never issued before in this process: they are
`first, first + 1, …, first + n - 1`. Thread-safe.
"""
function fresh_var_keys!(n::Int)::UInt64
    first = Threads.atomic_add!(_KERNEL_VAR_COUNTER, UInt64(n))
    @assert first >= KERNEL_VAR_BASE && first + UInt64(n) >= first "kernel variable keys exhausted"
    return first
end

# PORT: pl-global.h PL_local_data
# DIVERGES: `index_ctx` is scratch upstream declares on the C stack in each firstClause/nextClause.
# `bindings` has no field upstream — SWI binds a variable by overwriting its cell on the
# global stack; interface variables are immutable values, so a binding is an entry keyed by
# `var_key`. `trail` is `stacks.trail` (its length is `tTop`) and holds those keys. A cyclic link or
# a visited mark is an entry in an identity map (`cycle_links`, `occurs_marked`) where upstream
# overwrites a functor cell; the stacks that restore them are upstream's (`cycle.lstack`,
# `var_occurs_in`'s `visited`). The agendas and the `visited` stack are scratch upstream keeps on
# the C stack; kept here, and emptied entry by entry, a warm unification allocates nothing.
# `stacks.local` is the cells `slots` and the pools of frame, choice-point and foreign-frame records
# (src/pl-incl.jl § the local stack); its `top` and `max` and LD's `environment`, `choicepoints` and
# `foreign_environment` are named by the macros upstream's code reads them through — `lTop`, `lMax`,
# `environment_frame`, `BFR` and `fli_context` — and the last three are pool indices (0 = NULL).
# `stacks.limit` is the local stack's alone, in positions: there is no global or trail stack to
# share it with. `query` is a query-frame index (0 = NULL). The argument stack `astack` holds
# `argstack_entry`s (upstream: `Word*`); the write-mode builder (`bcells`, `bframes`; decision 2, Q3)
# has no upstream field — it builds where upstream fills cells on the global stack. The `exception.*`
# fields are term references (`term_t`), allocated by `emptyStacks` as upstream allocates them.
"""
    PL_local_data{T}()

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see — and
the state of unification: the bindings, the trail that undoes them back to a [`mark`](@ref), the
`occurs_check` flag, and the records the unifier keeps while it walks; and the local stack — its
cells, its frames, choice points and foreign frames, and the registers that point into it. A new
one has upstream's initial local stack, emptied as `emptyStacks` leaves it: one foreign frame at
its base.
"""
mutable struct PL_local_data{T}
    predicate_references::Vector{definition_ref{T}}            # Referenced predicates
    bindings::Dict{UInt64, T}                                   # var_key → value (see above)
    trail::Vector{UInt64}                                       # stacks.trail: bound var_keys
    prolog_flag_occurs_check::occurs_check_t                    # prolog_flag.occurs_check
    prolog_flag_portable_vmi::Bool                              # truePrologFlag(PLFLAG_PORTABLE_VMI)
    prolog_flag_last_call::Bool                                 # truePrologFlag(PLFLAG_LASTCALL)
    prolog_flag_optimise::Bool                                  # truePrologFlag(PLFLAG_OPTIMISE)
    arith_f_flags::UInt32                                       # arith.f.flags (V6c)
    arith_numbers::Vector{number}                               # (the numbers' C stack, pooled)
    arith_top::Int                                              # (how many of them are in use)
    arith_frames::Vector{Tuple{T, Int}}                         # evalExpression's term_stack
    cycle_lstack::Vector{T}                                     # cycle.lstack: linked compounds
    cycle_links::IdDict{T, T}                                   # the links themselves
    occurs_visited::Vector{T}                                   # var_occurs_in's `visited`
    occurs_marked::IdDict{T, Nothing}                           # its FIRST_MASK marks
    unify_agenda::term_agendaLR{T}                              # do_unify's `agenda`
    compare_agenda::term_agendaLR{T}                            # compare_fast's `agenda`
    occurs_agenda::term_agenda{T}                               # var_occurs_in's `agenda`
    index_ctx::index_context{T}                                 # firstClause/nextClause scratch
    slots::Vector{T}                                            # stacks.local: the cells
    lTop::Int                                                   # stacks.local.top
    lMax::Int                                                   # stacks.local.max
    stacks_limit::Int                                           # stacks.limit
    frames::Vector{localFrame{T}}                               # the frame records
    nframes::Int                                                # … live: frames[1:nframes]
    choices::Vector{choice{T}}                                  # the choice-point records
    nchoices::Int                                               # … live: choices[1:nchoices]
    fliframes::Vector{fliFrame}                                 # the foreign-frame records
    nfliframes::Int                                             # … live: fliframes[1:nfliframes]
    environment_frame::Int                                      # environment: current frame
    BFR::Int                                                    # choicepoints: choice-point chain
    fli_context::Int                                            # foreign_environment
    null_code::Code{T}                                          # a NULL `Code` (no clause)
    queries::Vector{queryFrame{T}}                              # the query-frame records
    nqueries::Int                                               # … live: queries[1:nqueries]
    query::Int                                                  # query: the innermost open one
    astack::Vector{argstack_entry{T}}                           # stacks.argument
    aTop::Int                                                   # … its top (entries in use)
    bcells::Vector{T}                                           # the write-mode builder's cells
    bTop::Int                                                   # … in use: bcells[1:bTop]
    bframes::Vector{bframe{T}}                                  # … the compounds it is building
    nbframes::Int                                               # … open: bframes[1:nbframes]
    exception_term::Int                                         # exception.term (0: none)
    exception_bin::Int                                          # exception.bin
    exception_printed::Int                                      # exception.printed
    exception_tmp::Int                                          # exception.tmp
    exception_pending::Int                                      # exception.pending
    chp_scratch::ClauseChoice{T}                                # (a C-stack clause_choice)
    placeholder::T                                              # (argp_t's term but in a cursor)
end
function PL_local_data{T}() where {T}
    e = mk_expr(T, T[])                         # any term: the agendas' idle work nodes
    ld = PL_local_data{T}(
        definition_ref{T}[], Dict{UInt64, T}(), UInt64[], OCCURS_CHECK_FALSE, true,
        true,                                   # last_call_optimisation: on (pl-prologflag.c:2400)
        false,                                  # optimise: off without -O (pl-prologflag.c:2394)
        UInt32(0x0081),                         # FLT_ROUND_NEAREST|FLT_UNDERFLOW (initArith)
        number[], 0, Tuple{T, Int}[],
        T[],
        IdDict{T, T}(), T[], IdDict{T, Nothing}(),
        term_agendaLR{T}(aNodeLR{T}(e, e, 0, 0), aNodeLR{T}[]),
        term_agendaLR{T}(aNodeLR{T}(e, e, 0, 0), aNodeLR{T}[]),
        term_agenda{T}(aNode{T}(e, 0, 0), aNode{T}[]),
        # idle until a search resets it (`_index_context!`): any predicate will do
        index_context{T}(
            gen_t(0),
            Definition{T}(
                UInt64(0), 0, ClauseList{T}(), UInt64(0), e, code[], ClauseRef{T}[],
                PL_code_data(code[], code[], code[], code[], code[], code[]), 0
            ),
            nothing,
            0,
            _TOP_POSITION,
            false
        ),
        T[], 0, 0, STACK_LIMIT_DEFAULT, localFrame{T}[], 0, choice{T}[], 0, fliFrame[], 0,
        0, 0,
        0, Code{T}(code[], T[], 0),
        queryFrame{T}[], 0, 0,
        Vector{argstack_entry{T}}(undef, 64), 0,
        Vector{T}(undef, 256), 0, Vector{bframe{T}}(undef, 64), 0,
        0, 0, 0, 0, 0,
        ClauseChoice{T}(nothing, word(0)), e
    )
    growStacks!(ld, LOCAL_INITIAL)              # allocStacks: the initial local stack
    emptyStacks!(ld)
    return ld
end

# setup:1600 `minlocal = 4*SIZEOF_WORD K`: the local stack a thread starts with, here in positions.
"The positions of a new local stack (pl-setup.c `allocStacks`'s `minlocal`, in words)."
const LOCAL_INITIAL = 4096

# The `stack_limit` flag's default, 1 GiB (swipl 10.1.16: `1073741824`), here in positions.
"The default `stacks_limit`, in positions: `stack_limit`'s default of 1 GiB, in words."
const STACK_LIMIT_DEFAULT = (1 << 30) ÷ 8
