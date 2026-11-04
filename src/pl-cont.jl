# UPSTREAM: swipl-devel src/pl-cont.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2016-2025, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's delimited continuations (pl-cont.c): `shift/1` collects the
# environments between the shifting frame and the `reset/3` frame it matches as a list of
# `'$cont$'(Module, Clause, PC, Slot...)` terms (`put_continuation`, `put_environment`), unifies the
# list with the continuation of `reset/3`, and returns from `reset/3` (`shift`); the VMI bodies
# `I_SHIFT` and `I_SHIFTCP` are in src/pl-wam.jl. The tabling branches (`'$tbl_reset'/6` and its
# worklists) are refused by name, owner TAB1.

# PORT: pl-cont.c FRESET_NO_FRAME
"`findReset`: no `reset/3` frame matches the ball (pl-cont.c)."
const FRESET_NO_FRAME = -1
# PORT: pl-cont.c FRESET_FINDALL
"`findReset`: the search met a `findall_loop/4` frame (pl-cont.c)."
const FRESET_FINDALL = -2

# PORT: pl-cont.c findReset
# DIVERGES: the frame is an index and the result a pair `(rc, rframe)` where upstream returns `rc`
# (`true` is 1 here) and sets `*rframe`; the frame cannot move, so there is no `consTermRef` /
# `valTermRef` round trip around the unification. A frame argument is the term reference at
# `argFrameP`. The procedure of `findall_loop/4` is looked up once, before the loop, and kept in
# `GD->procedures.findall_loop4` (`_PL_predicate`): the placeholder the global data starts with has
# arity 0.
"""
    findReset(gd, ld, fr, ball) -> (rc, rframe)

Search the frames from `fr` outwards for a `reset/3` (or `'\$tbl_reset'/6`) frame whose second
argument unifies with `ball` (pl-cont.c): `rc` is 1 and `rframe` that frame, or `FRESET_NO_FRAME`, or
`FRESET_FINDALL` when a `findall_loop/4` frame lies in between.
"""
function findReset(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::Int, ball::term_t
)::Tuple{Int, Int} where {T}
    reset3 = gd.procedures_reset3.definition                    # PROCEDURE_reset3->definition
    reset6 = gd.procedures_dtbl_reset6.definition               # PROCEDURE_dtbl_reset6->definition
    if gd.procedures_findall_loop4.definition.arity != 4        # _PL_predicate(…, &GD->procedures.findall_loop4)
        gd.procedures_findall_loop4 = lookupProcedure(
            mk_sym(T, :findall_loop), 4, lookupModule(gd, mk_sym(T, Symbol("\$bags")))
        )
    end
    proc_fl = gd.procedures_findall_loop4

    while fr != 0                                               # for(; fr; fr = fr->parent)
        f = ld.frames[fr]
        f.predicate === proc_fl.definition && return (FRESET_FINDALL, 0)

        if f.predicate === reset3 || f.predicate === reset6
            rc = PL_unify(ld, argFrameP(f.base, 1), ball)       # PL_unify(consTermRef(argFrameP(fr, 1)), ball)
            rc && return (1, fr)                                # *rframe = consTermRef(fr); return true
        end
        fr = f.parent
    end

    return (FRESET_NO_FRAME, 0)
end

# PORT: pl-cont.c env_functor
# DIVERGES: the functor table is looked up for each call, where upstream keeps the functors of
# arity below `FAST_FUNCTORS` (256) in the array `fast_functors`; no cache is kept here, the lookup
# of a functor word is a hash probe. `slots` is the clause's `variables`.
"The functor `'\$cont\$'/(slots+3)`: Context, Clause and PC, then the frame's slots (pl-cont.c)."
function env_functor(ld::PL_local_data{T}, slots::Int)::word where {T}
    arity = slots + 3                                           # Context, Clause and PC
    return lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, Symbol("\$cont\$"))), arity)
end

# ORIGINAL (CONT1): the functor word `name/arity` of a pl-cont.c constant (`FUNCTOR_catch3`,
# `FUNCTOR_call1`, …): upstream's generated table, here the functor table's lookup, as
# `_when_functor` (src/pl-attvar.jl).
"The functor word `name/arity`, looked up (made if new)."
_cont_functor(ld::PL_local_data{T}, name::Symbol, arity::Int) where {T} =
    lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, name)), arity)

# PORT: pl-cont.c put_environment
# DIVERGES: `fr` is a frame index, `pc` the INDEX of the instruction the frame resumes at in the
# clause's code (a frame that called a child resumes at the child's saved `programPointer.pc`) and
# `env` a term reference (a position). The `'$cont$'` compound is laid out in one piece at `gTop`
# (`4 + slots` cells: functor, Context, Clause, PC, one cell per slot; every slot, active or not,
# writes exactly one cell, so upstream's final `gTop = p` is the end of the piece). `PC` is stored as
# the 0-based offset `pc - cl->codes`: the index minus 1. A frame slot is never an unbound local
# variable (a slot holds a reference to a global cell), so upstream's `isVar(*vp) && vp > lBase`
# branch with `LTrail` cannot arise: every active variable is `_cell_link!` (`linkValI`). A
# choice-point slot already holds `consInt` of the choice's position (C_IFTHENELSE, C_SOFTIF, …), so
# `consInt(argFrame(fr, i))` is that word. The clause blob is not unregistered (no atom GC);
# `ensureGlobalSpace` is a call to the stack's growth. `Sdprintf` is `_qlf_Sdprintf!` (the text is
# collected on `ld.messages`); `clauseNo(cl, 0)` and `PL_backtrace(10,1)` are left to DBG1, so the
# `shift_check` text names no clause number and prints no stack.
"""
    put_environment(gd, ld, env, fr, pc, for_copy) -> Bool

Make term reference `env` hold the term \$cont\$(Context, Clause, PC, Slot...) for the environment of
frame `fr` resuming at the instruction `codes[pc]` of its clause (pl-cont.c): the slots the rest of
the clause reads (`mark_active_environment`), the others the atom `<inactive>`.
"""
function put_environment(
    gd::PL_global_data{T}, ld::PL_local_data{T}, env::term_t, fr::Int, pc::Int, for_copy::Bool
)::Bool where {T}
    f = ld.frames[fr]
    cl = f.clause.clause::Clause{T}                             # const Clause cl = fr->clause->value.clause
    slots = Int(cl.variables)
    active = falses(slots)                                      # init_bitvector(active, slots)
    mark_active_environment(ld, active, fr, cl.codes, pc)

    if !ensureGlobalSpace(ld, 1 + slots)
        return false
    end

    cref = lookup_clref(gd, cl)
    tp = _alloc_compound!(ld, env_functor(ld, slots), slots + 3)    # *p++ = env_functor(slots)
    p = tp + 1
    if (f.predicate::Definition{T}).flags & P_TRANSPARENT == 0  # isoff(fr->predicate, P_TRANSPARENT)
        ld.gstack[p] = ld.atom_nil_w                            # ATOM_nil
    else
        ld.gstack[p] = _atom_word!(ld, gd.modules[contextModule(gd, ld, fr)].atom)  # contextModule(fr)->name
    end
    ld.gstack[p + 1] = _atom_word!(ld, cref)                    # cref
    ld.gstack[p + 2] = consInt(Int64(pc - 1))                   # consInt(pc - cl->codes)
    p += 3

    inactive = _atom_word!(ld, mk_sym(T, Symbol("<inactive>")))     # ATOM_cont_inactive
    for i in 0:(Int(cl.prolog_vars) - 1)
        if active[i + 1]                                        # true_bit(active, i)
            _cell_link!(ld, p, argFrameP(f.base, i) + 1)        # *p = linkValI(vp)
        else
            ld.gstack[p] = inactive
        end
        p += 1
    end
                                        # Store choice points (*)
    for i in Int(cl.prolog_vars):(slots - 1)
        if active[i + 1]
            if for_copy
                if truePrologFlag(ld, PLFLAG_SHIFT_CHECK)
                    _qlf_Sdprintf!(
                        ld,
                        "Shift: clause of $(f.predicate.name)/$(f.predicate.arity): " *
                        "active choice-point in slot $i.  Stack:\n",
                    )
                end
                ld.gstack[p] = word(0)                          # *p++ = 0
            else
                ld.gstack[p] = ld.slots[argFrameP(f.base, i) + 1]   # consInt(argFrame(fr, i))
            end
        else
            ld.gstack[p] = word(0)                              # *p++ = 0
        end
        p += 1
    end

    ld.slots[env + 1] = consPtr(tp, TAG_COMPOUND | STG_GLOBAL)  # *valTermRef(env) = consPtr(tp, …)
    return true
end

# PORT: pl-cont.c env3_predicate
# DIVERGES: the result is a functor WORD, 0 for none; the definition is compared by identity.
"The functor `catch/3`, `reset/3` or `'\$tbl_reset'/6` of the frame predicate `def`, or 0 (pl-cont.c)."
function env3_predicate(
    gd::PL_global_data{T}, ld::PL_local_data{T}, def::Definition{T}
)::word where {T}
    if def === gd.procedures_catch3.definition
        return _cont_functor(ld, :catch, 3)                     # FUNCTOR_catch3
    end
    if def === gd.procedures_reset3.definition
        return _cont_functor(ld, :reset, 3)                     # FUNCTOR_reset3
    end
    if def === gd.procedures_dtbl_reset6.definition
        return _cont_functor(ld, Symbol("\$tbl_reset"), 6)      # FUNCTOR_dtbl_reset6
    end
    return word(0)
end

# PORT: pl-cont.c is_last_call
# DIVERGES: `PC` is a `Code` (the clause's code and the index of an instruction). The `for( ; ; PC =
# stepPC(PC) )` has no second round: every case returns or jumps, so its step is left out.
"Whether the code from `PC` is `I_EXIT` or `I_EXITFACT`, after any `C_JMP` (pl-cont.c): the continuation is empty."
function is_last_call(PC::Code{T})::Bool where {T}
    codes = PC.codes
    i = PC.pc
    c = codes[i]                                                # fetchop(PC)
    while c == C_JMP                                            # again: … PC += (int)PC[1]+2
        i += Int(codes[i + 1]) + 2
        c = codes[i]
    end
    return c == I_EXIT || c == I_EXITFACT
end
