# allow-new-artifact: pl-init.c mirror, HALT1
# UPSTREAM: swipl-devel src/pl-init.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2012-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-init.c, exactly this: `PL_cleanup`, the clean-up `halt/1` ends with (HALT1), in a reduced
# form (below). NOT PORTED: the command line and the start-up (`PL_initialise`, `parseCommandLineOptions`,
# `script_argv`, the saved states), `run_on_halt` and the foreign hook lists (`PL_on_halt`, `PL_exit_hook`:
# the kernel has none), `qlfCleanup`, `RemoveTemporaryFiles`, `cleanupSignals` and the memory reclaim of
# `cleanupProlog` (the host process's memory is the host's).

# PORT: pl-init.c MAX_HALT_CANCELLED
"The number of times a halt may be cancelled by `cancel_halt/1`, before it goes ahead regardless (pl-init.c)."
const MAX_HALT_CANCELLED = 10

# PORT: pl-init.c PL_cleanup
# DIVERGES (HALT1, for the audit): a reduced `PL_cleanup`. (1) `query_loop(PL_new_atom("$run_at_halt"), false)` is
# the query `system:'$run_at_halt'/0` opened with `PL_Q_NORMAL|PL_Q_EXCEPT_HALT`, run once and cut, and run only
# where the loader has defined it; the toplevel step ports `query_loop`. A raised exception is cleared and
# does not cancel the halt (the hooks `'$call_at_halt'/2` runs catch their own). (2) Left out: the debug-mode
# switch, `emptyStacks` on an overflow, the foreign hook list (`run_on_halt(&GD->os.on_halt_list)`: the kernel
# has none), `exitPrologThreads` (one thread), `qlfCleanup`, `unload_all_foreign_libraries`,
# `RemoveTemporaryFiles`, `cleanupSignals` and the reclaim of memory (`reclaim_memory`: `PL_halt` passes
# `PL_CLEANUP_NO_RECLAIM_MEMORY`). (3) `dieIO` is the flush of the standard output and error streams. (4) The
# stages `CLN_PROLOG`, `CLN_FOREIGN`, `CLN_IO`, `CLN_SHARED` and `CLN_DATA` are passed in upstream's order and the
# state stays `CLN_DATA` on return, as upstream (the process ends); `PL_halt` returns it to `CLN_NORMAL` where the
# seam `gd.halt_exit` (src/pl-global.jl) is off, so a test that embeds the kernel can halt again.
"""
    PL_cleanup(gd, ld, status) -> Int

Clean up for a halt with `status` (its low 16 bits the exit status, the rest `PL_CLEANUP_*` flags): set the flag
`exit_status`, run `'\$run_at_halt'/0` (`at_halt/1` hooks, which `cancel_halt/1` can veto) and flush the standard
streams. `PL_CLEANUP_SUCCESS`, or `PL_CLEANUP_CANCELED` (a hook vetoed, and the halt may be cancelled 10 times),
or `PL_CLEANUP_RECURSIVE` (a clean-up is running already) (pl-init.c).
"""
function PL_cleanup(gd::PL_global_data{T}, ld::PL_local_data{T}, status::Int)::Int where {T}
    rval = status & PL_CLEANUP_STATUS_MASK

    gd.halt_cleaning != CLN_NORMAL && return PL_CLEANUP_RECURSIVE

    gd.halt_cleaning = CLN_PROLOG

    setPrologFlag(gd, "exit_status", FT_INTEGER, rval)  # PL_set_prolog_flag("exit_status", PL_INTEGER, rval)
    if !_query_run_at_halt(gd, ld) && (status & PL_CLEANUP_NO_CANCEL) == 0
        gd.halt_cancelled += 1
        if gd.halt_cancelled < MAX_HALT_CANCELLED       # if ( ++GD->halt.cancelled < MAX_HALT_CANCELLED )
            gd.halt_cleaning = CLN_NORMAL
            return PL_CLEANUP_CANCELED
        end
    end

    gd.halt_cleaning = CLN_FOREIGN                      # (run_on_halt(&GD->os.on_halt_list): the kernel has none)

    gd.halt_cleaning = CLN_IO
    for s in (Suser_output(ld), Suser_error(ld))        # dieIO(): standard I/O is only flushed
        s === nothing || Sflush(s)
    end

    gd.halt_cleaning = CLN_SHARED                       # (unload_all_foreign_libraries: none)
    gd.halt_cleaning = CLN_DATA                         # (RemoveTemporaryFiles, cleanupSignals: none)

    return PL_CLEANUP_SUCCESS
end

# `query_loop(PL_new_atom("$run_at_halt"), false)` reduced (see `PL_cleanup`): true where the one query
# `system:'$run_at_halt'/0` succeeded, raised, or was not run (the loader has not defined it); false where it
# failed — `cancel_halt/1` vetoed the halt.
function _query_run_at_halt(gd::PL_global_data{T}, ld::PL_local_data{T})::Bool where {T}
    proc = lookupProcedure(mk_sym(T, Symbol("\$run_at_halt")), 0, MODULE_system(gd))
    isDefinedProcedure(gd, proc) || return true

    rval = true
    fid = PL_open_foreign_frame(ld)
    qid = PL_open_query(
        gd, ld, MODULE_system(gd), PL_Q_NORMAL | PL_Q_EXCEPT_HALT, proc,
        PL_new_term_refs(ld, 0)
    )
    if qid != 0
        rval = PL_next_solution(gd, ld, qid) != 0 || PL_exception(ld, qid) != 0
        PL_cut_query(ld, qid)
    end
    PL_clear_exception(ld)
    PL_close_foreign_frame(ld, fid)

    return rval
end
