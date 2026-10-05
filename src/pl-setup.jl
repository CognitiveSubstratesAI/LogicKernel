# UPSTREAM: swipl-devel src/pl-setup.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's start-up (pl-setup.c): emptying the stacks of a thread,
# which leaves one foreign frame at the base of the local stack.

# PORT: pl-setup.c emptyStacks as emptyStacks!
# DIVERGES: no global or argument stack to empty, and the trail's bindings go with it (`bindings`).
# `BFR` and `LD->query` are cleared with the stack they point into; there is no `mark_bar`. Of the
# engine's permanent term references upstream allocates in the base foreign frame, the exception's
# four are (`exception_bin`, `exception_printed`, `exception.tmp`, `exception.pending`, in
# upstream's order); the others belong to subsystems not ported (`trim.dummy`, attributed
# variables, undo hooks, tabling). So later term references lie at other absolute positions than in
# swipl: compare DIFFERENCES between positions with swipl, never absolute ones.
"Empty the local stack and the trail, then open the base foreign frame (pl-setup.c)."
function emptyStacks!(ld::PL_local_data{T})::Nothing where {T}
    ld.environment_frame = 0                    # environment_frame = NULL;
    ld.fli_context = 0                          # fli_context = NULL;
    ld.BFR = 0

    ld.lTop = 0                                 # emptyStack((Stack)&LD->stacks.local);
    ld.nframes = 0
    ld.nchoices = 0
    ld.nfliframes = 0
    ld.nqueries = 0
    ld.query = 0                                # LD->query = NULL;
    ld.aTop = 0                                 # emptyStack((Stack)&LD->stacks.argument);
    ld.bTop = 0
    ld.nbframes = 0
    empty!(ld.trail)                            # emptyStack((Stack)&LD->stacks.trail);
    empty!(ld.bindings)

    PL_open_foreign_frame(ld)
    ld.exception_term = 0
    ld.exception_bin = PL_new_term_ref(ld)
    ld.exception_printed = PL_new_term_ref(ld)
    ld.exception_tmp = PL_new_term_ref(ld)                     # LD->exception.tmp
    ld.exception_pending = PL_new_term_ref(ld)                 # LD->exception.pending
    return nothing
end
