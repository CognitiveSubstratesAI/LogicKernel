# UPSTREAM: swipl-devel src/pl-cont.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2016-2025, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's delimited continuations (pl-cont.c): `shift/1` collects the
# environments between the shifting frame and the `reset/3` frame it matches as a list of
# `'$cont$'(Module, Clause, PC, Slot...)` terms (`put_continuation`, `put_environment`), unifies the
# list with the continuation of `reset/3`, and returns from `reset/3` (`shift`); `push_continuation`
# makes the frame of one such environment again, for `call_continuation/1`. The VMI bodies `I_SHIFT`,
# `I_SHIFTCP` and `I_CALLCONT` are in src/pl-wam.jl. The tabling branches (`'$tbl_reset'/6` and its
# worklists) are refused by name, owner TAB1; `push_continuation_list` (tabling only) is left to TAB1.

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

# ORIGINAL (CONT1): upstream's `predicateName(def)` (pl-util.c), the text of a predicate in the
# `shift_check` message of `put_environment`: `name/arity`, prefixed by `module:` unless the module
# is `user` or the predicate is locked and also visible in `user`. AUTOLOAD1 A3 writes the same helper
# (`_autoload_predicate_name`, src/pl-proc.jl, not on this branch); the two merge when both have landed.
"The text `[module:]name/arity` of `def` in a message (pl-util.c `predicateName`)."
function _cont_predicate_name(gd::PL_global_data{T}, def::Definition{T})::String where {T}
    user = MODULE_user(gd)
    prefix = ""
    if def.module_ != user.index
        usersys =
            (def.flags & P_LOCKED) != 0 &&
            isCurrentProcedure(sym_key(def.name), def.arity, user) !== nothing
        usersys || (prefix = string(sym_text(gd.modules[def.module_].atom), ":"))
    end
    return string(prefix, sym_text(def.name), "/", def.arity)
end

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
    # The PC of the term is the 0-based offset, the index minus 1: `push_continuation` (C5) must add
    # the 1 back (`codes[offset + 1]`) when it restarts the clause.
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
                        "Shift: clause of $(_cont_predicate_name(gd, f.predicate::Definition{T})): " *
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

# PORT: pl-cont.c put_continuation
# DIVERGES: frames are pool indices and never move, so upstream's `reset_ref` / `fr_ref` round trips
# (`consTermRef` / `valTermRef`, which survive a stack shift) are left out; `pc` is a `Code` (the clause's
# code and the index of the instruction the frame resumes at, `pc.pc`, which `put_environment` takes).
# A frame argument is the term reference at `argFrameP`. The test `onStackArea(local, cl)` and its
# `PL_representation_error("continuation")` are left out: a clause is a Julia object, it is never
# a value on the local stack. `PL_new_term_refs(av)` is tested (upstream passes a failed 0 on).
"""
    put_continuation(gd, ld, cont, resetfr, fr, pc, for_copy) -> Bool

Make term reference `cont` hold `call_continuation(List)`, the list of the `'\$cont\$'` terms of the
frames from `fr` (resuming at `pc`) up to, not including, `resetfr` (pl-cont.c): a frame whose
remaining code is `I_EXIT` adds none, a `catch/3`, `reset/3` or `'\$tbl_reset'/6` frame adds the goal
`call(catch(...))` (`env3_predicate`) after the list so far.
"""
function put_continuation(
    gd::PL_global_data{T}, ld::PL_local_data{T}, cont::term_t, resetfr::Int, fr::Int,
    pc::Code{T}, for_copy::Bool
)::Bool where {T}
    depth = 0

    fr2 = fr
    while fr2 != resetfr                                        # for(fr2=fr; fr2 != resetfr; fr2=fr2->parent)
        depth += 1
        fr2 = ld.frames[fr2].parent
    end
    contv = PL_new_term_refs(ld, depth)
    if contv == 0
        return false
    end

    depth = 0
    while fr != resetfr                                         # for( depth=0; fr != resetfr; … )
        f = ld.frames[fr]

        if !is_last_call(pc)
            env_f = env3_predicate(gd, ld, f.predicate::Definition{T})
            if env_f != word(0)                                 # (env_f=env3_predicate(fr->predicate))
                arity = arityFunctor(ld.functors, env_f)
                av = PL_new_term_refs(ld, arity)
                if av == 0
                    return false
                end

                for i in 1:(arity - 1)
                    PL_put_term(ld, av + i, argFrameP(f.base, i))
                end

                if PL_cons_list_v(ld, contv, depth, contv) &&
                    PL_cons_functor(
                    ld, av, _cont_functor(ld, :call_continuation, 1), contv
                ) &&
                    PL_cons_functor_v(ld, contv, env_f, av) &&
                    PL_cons_functor(ld, contv, _cont_functor(ld, :call, 1), contv)
                    depth = 0
                else
                    return false
                end
            elseif !put_environment(gd, ld, contv + depth, fr, pc.pc, for_copy)
                return false
            end

            depth += 1
        end

        pc = f.programPointer                                   # pc = fr->programPointer
        fr = f.parent                                           # fr = fr->parent
    end

    return PL_cons_list_v(ld, cont, depth, contv) &&
           PL_cons_functor_v(ld, cont, _cont_functor(ld, :call_continuation, 1), cont)
end

# PORT: pl-cont.c shift
# DIVERGES: the result is the `Code` the parent of `reset/3` resumes at, `nothing` for upstream's
# NULL (an error is pending). The frames are indices, so the `valTermRef` reloads after each call that
# could shift a stack are left out. The trim of `lTop` is `setLTop!`: the records of the frames above
# the new `lTop` (the continuation's frames, the shifting frame, the foreign frame of the caller's
# `shift_common`) are dropped with it, where upstream leaves their words as garbage on the stack
# (`BFR` is never 0 here: the query's `CHP_TOP`, so `LD->choicepoints` is `choices[BFR]`). The
# `DEBUG(MSG_CONTINUE, …)` and `CHK_SECURE` lines are debug output only. The reset frame's record is
# read after the trim, as upstream reads it: a dropped record stays readable until a push reuses it.
"""
    shift(gd, ld, ball, for_copy) -> Union{Nothing, Code{T}}

Collect the continuation of `ball`'s `reset/3` (pl-cont.c): search the frames for the `reset/3` whose
ball unifies, put the continuation list into its `Cont` argument, trim `lTop`, and return the program
counter `reset/3` returns to, `environment_frame` being its parent. An existence error when no
`reset/3` matches, or when a `findall_loop/4` lies in between; `nothing` with an error pending.
"""
function shift(
    gd::PL_global_data{T}, ld::PL_local_data{T}, ball::term_t, for_copy::Bool
)::Union{Nothing, Code{T}} where {T}
    rc, reset = findReset(gd, ld, ld.environment_frame, ball)
    if rc == 1
        cont = PL_new_term_ref(ld)
        PL_put_nil(ld, cont)
        resetfr = reset
        envf = ld.frames[ld.environment_frame]
        if !put_continuation(gd, ld, cont, resetfr, envf.parent, envf.programPointer, for_copy)
            return nothing                                      # resource error
        end

        if !PL_unify(ld, argFrameP(ld.frames[resetfr].base, 2), cont)
            if PL_exception(ld, 0) == 0
                PL_error(
                    ld, "", 0, "", ERR_UNINSTANTIATION, 0, argFrameP(ld.frames[resetfr].base, 1)
                )
            end
            return nothing
        end

        fr = envf.parent                                        # Find parent to keep and trim lTop
        while true
            f = ld.frames[fr]
            if f.base <= ld.choices[ld.BFR].base                # fr <= (LocalFrame)LD->choicepoints
                setLTop!(ld, ld.choices[ld.BFR].base + SIZEOF_CHOICE)   # found newer choicepoint
                break
            elseif fr == resetfr
                fr = f.parent
                pf = ld.frames[fr]
                setLTop!(
                    ld,
                    argFrameP(pf.base, Int(((pf.clause::ClauseRef{T}).clause::Clause{T}).variables))
                )
                break
            end
            @assert fr > resetfr                                # frame indices ascend with their bases
            fr = f.parent
        end
                                                                # return as from reset/3
        rf = ld.frames[resetfr]
        ld.environment_frame = rf.parent
        return rf.programPointer
    end

    msg = ("No matching reset/3 call", "Cannot catch continuation through findall/3")
    PL_error(ld, "shift", 1, msg[-rc], ERR_EXISTENCE, mk_sym(T, :reset), ball)
    return nothing
end

# PORT: pl-cont.c push_continuation
# DIVERGES: `continuation` is a term reference, `pfr` a frame index and the result a `Code`, or
# `nothing` with the exception raised. The new frame is the record pushed at `lTop` (`pushFrame!`),
# upstream's cast of `top`. The words of the term are read dereferenced; a context that is not an
# atom, a clause that is not a blob, a PC that is not an integer or an arity below 3 raise the
# `type_error(continuation, _)` of a non-matching arity. `clause_clref` gives the `Clause` for any
# serial of the append-only table, erased or not, as upstream's blob keeps the clause. Left out: the
# blob word upstream stores below the frame (it only protects the blob from atom GC; there is none)
# and the `DEBUG(MSG_CONTINUE)` output. The room asked for is the frame, its slots and `LOCAL_MARGIN`
# (upstream's margin is the stack's own spare); growing the local stack moves nothing, so there is no
# `retry`. A slot is linked from its global cell (`_slot_from_cell!`, `linkValI`); a choice-point slot
# keeps the word `consInt(position)` that `put_environment` copied, when that position is still a
# choice point of the chain (upstream's `chp > ch` walk compares addresses; positions here), else it
# names the newest choice point. The PC of the term is the 0-based offset: the index is offset + 1.
"""
    push_continuation(gd, ld, continuation, pfr, pcret) -> Union{Nothing, Code}

Push the frame of the environment `'\$cont\$'(Context, Clause, PC, Slot...)` in term reference
`continuation` above frame `pfr`, returning into `pcret`, and give the code to resume it at
(pl-cont.c); `nothing` with an exception when it is no environment.
"""
function push_continuation(
    gd::PL_global_data{T}, ld::PL_local_data{T}, continuation::term_t, pfr::Int, pcret::Code{T}
)::Union{Nothing, Code{T}} where {T}
    ck, cw, _ = _deref_loc(ld, -(continuation + 1))             # cont = valTermRef(continuation); deRef(cont)
    if !(ck == DU_WORD && _is_gcompound(cw))                    # isTerm(*cont)
        PL_type_error(ld, "continuation", continuation)
        return nothing
    end
    cp = valPtr(cw)                                             # Functor f = valueTerm(*cont)
    arity = arityFunctor(ld.functors, ld.gstack[cp])
    mk, mw, _ = arity >= 3 ? _deref_loc(ld, cp + 1) : (DU_CELL, word(0), 0)
    bk, bw, _ = arity >= 3 ? _deref_loc(ld, cp + 2) : (DU_CELL, word(0), 0)
    pk, pw, _ = arity >= 3 ? _deref_loc(ld, cp + 3) : (DU_CELL, word(0), 0)
    cl = nothing
    if mk == DU_WORD && isAtomW(mw) && bk == DU_WORD && isAtomW(bw) && pk == DU_VALUE && isTaggedIntW(pw)
        cl = clause_clref(gd, _atom_value(ld, bw))
    end
    if cl === nothing || arity != Int(cl.variables) + 3
        PL_type_error(ld, "continuation", continuation)
        return nothing
    end
    cl = cl::Clause{T}
    mname = _atom_value(ld, mw)                                 # atom_t mname = word2atom(*ep++)
    pcoffset = Int(valInt(pw))                                  # pcoffset = (size_t)valInt(*ep++)

    ensureLocalSpace(ld, SIZEOF_LOCALFRAME + Int(cl.variables) + LOCAL_MARGIN) || return nothing

    nfr = pushFrame!(ld, ld.lTop)                               # fr = (LocalFrame)top
    f = ld.frames[nfr]
    ap = argFrameP(f.base, 0)
    ep = cp + 4                                                 # the first slot of the term
    nvars = Int(cl.variables)
    for i in 0:(Int(cl.prolog_vars) - 1)
        _slot_from_cell!(ld, ap + i + 1, ep + i)                # *ap = linkValI(ep)
    end
    for i in Int(cl.prolog_vars):(nvars - 1)
        c = ld.gstack[ep + i]
        newest = consInt(Int64(ld.choices[ld.BFR].base))        # consTermRef(LD->choicepoints)
        if isTaggedIntW(c)
            ichp = Int(valInt(c))
            chp = ld.BFR
            while chp != 0 && ld.choices[chp].base > ichp       # for ( chp = LD->choicepoints; chp > ch; ...)
                chp = ld.choices[chp].parent
            end
            ld.slots[ap + i + 1] = (chp != 0 && ld.choices[chp].base == ichp) ? c : newest
        else
            ld.slots[ap + i + 1] = newest
        end
    end
    setLTop!(ld, argFrameP(f.base, nvars))                      # lTop = top

    f.programPointer = pcret                                    # fr->programPointer = pcret
    f.parent = pfr                                              # fr->parent = pfr
    setNextFrameFlags(f, ld.frames[pfr])
    f.clause = ClauseRef{T}(nothing, word(0), cl, nothing)      # fr->clause = cref
    f.fctx = UInt(0)
    setFramePredicate(f, cl.predicate)
    if is_nil(mname)                                            # mname == ATOM_nil
        f.context = (f.predicate::Definition{T}).module_        # fr->context = fr->predicate->module
    else
        setContextModule!(f, lookupModule(gd, mname).index)     # fr->context = lookupModule(mname); set(fr, FR_CONTEXT)
    end
    setGenerationFrame(gd, ld, nfr)
    ld.environment_frame = nfr
    return Code{T}(cl.codes, cl.literals, pcoffset + 1)         # cl->codes + pcoffset
end
