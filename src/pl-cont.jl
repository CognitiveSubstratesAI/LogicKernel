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
