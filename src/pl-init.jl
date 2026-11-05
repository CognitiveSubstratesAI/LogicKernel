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
# DIVERGES (audit D-0403 item 5; owner TOP1b): a reduced `query_loop(.., false)`. The full `query_loop` (src/pl-pro.jl, R2 TOP1) stays as is
# beside it: switching this function to it adds `resetProlog`, `restore_after_exception` and `halt_from_exception` to the at-halt query,
# a behaviour change, taken by TOP1b and not by TOP1.
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

# ----- the command-line options (R2 LB7, plan: evidence/LB7/plan.md): the pure helpers of pl-init.c's option parser -----
# PORTED here, exactly this: `optcmp`, `is_longopt`, `is_bool_opt` (with `skip_wsep`), `on_error_style`, `is_early_define`,
# `find_define`, `initDefaultOptions`. They read and write the records `pl_options_t` and `pl_cmdline_t`
# (src/pl-global.jl) and nothing else. `parseCommandLineOptions`, `memarea_limit`, `$cmd_option_val/2` and the start-up
# tail of `PL_initialise` follow in the next commits of LB7.

# PORT: pl-init.c optcmp
# (swipl-devel cbf4e189, src/pl-init.c:127-144)
# DIVERGES (representation only): returns the rest of `av` after `opt` (and after an `=`) as a `String`, `nothing` for NULL; the
# strings are ASCII bytes, compared as upstream compares `char`.
"""
    optcmp(av, opt) -> Union{Nothing, String}

Compare the command-line word `av` with the option name `opt` up to the first `=` of `av`, a `-` of `av` matching a `_` of
`opt` and the other way round: the text after `opt` (after the `=` if there is one), or `nothing` where they differ (pl-init.c).
"""
function optcmp(av::AbstractString, opt::AbstractString)::Union{Nothing, String}
    a = codeunits(av)
    o = codeunits(opt)
    i = 1
    j = 1
    while i <= length(a) && j <= length(o) && a[i] != UInt8('=')   # *av && *opt && *av != '='
        if !(a[i] == o[j] ||
             (a[i] == UInt8('-') && o[j] == UInt8('_')) ||
             (a[i] == UInt8('_') && o[j] == UInt8('-')))
            return nothing
        end
        i += 1
        j += 1
    end
    if j > length(o)                                    # if ( !*opt )
        i <= length(a) && a[i] == UInt8('=') && (i += 1)
        return String(a[i:end])
    end
    return nothing
end

# PORT: pl-init.c is_longopt
# (swipl-devel cbf4e189, src/pl-init.c:256-264)
"The value of the long option `name` in `optstring` (`\"\"` where it carries none), `nothing` where `optstring` is another option (pl-init.c)."
function is_longopt(optstring::AbstractString, name::AbstractString)::Union{Nothing, String}
    return optcmp(optstring, name)
end

# PORT: pl-init.c skip_wsep
# (swipl-devel cbf4e189, src/pl-init.c:268-272)
"Skip one `-` or `_` at the start of `s` (pl-init.c)."
function skip_wsep(s::AbstractString)::SubString{String}
    ss = SubString(String(s), 1)
    return !isempty(ss) && (ss[1] == '-' || ss[1] == '_') ? SubString(ss, 2) : ss
end

# PORT: pl-init.c is_bool_opt
# (swipl-devel cbf4e189, src/pl-init.c:275-305)
# DIVERGES (representation only): returns `(rc, val)` where upstream returns `rc` (`1` true, `0` false, `-1` error) and
# writes `*val`; `val` is meaningful for `rc == 1`.
"""
    is_bool_opt(opt, name) -> (rc, val)

Whether `opt` is the boolean long option `name`, `--name`, `--name=true|yes|y|false|no|n` or `--no-name`: `rc` is `1`
(then `val` is its value), `0` (another option) or `-1` (a value that is no boolean) (pl-init.c).
"""
function is_bool_opt(opt::AbstractString, name::AbstractString)::Tuple{Int, Bool}
    optval = is_longopt(opt, name)
    if optval !== nothing
        lv = lowercase(optval)                         # strcasecmp
        (isempty(optval) || lv == "true" || lv == "yes" || lv == "y") && return (1, true)
        (lv == "false" || lv == "no" || lv == "n") && return (1, false)
        return (-1, false)
    elseif startswith(opt, "no")                       # strncmp(opt, "no", 2) == 0
        optval = is_longopt(skip_wsep(SubString(String(opt), 3)), name)
        if optval !== nothing
            isempty(optval) && return (1, false)
            return (-1, false)
        end
    end
    return (0, false)
end

# PORT: pl-init.c on_error_style
# (swipl-devel cbf4e189, src/pl-init.c:812-816)
"Whether `s` is a value of `--on-error` or `--on-warning`: `print`, `halt` or `status` (pl-init.c)."
on_error_style(s::AbstractString)::Bool = s == "print" || s == "halt" || s == "status"

# PORT: pl-init.c early_defines
# (swipl-devel cbf4e189, src/pl-init.c:181-187)
# DIVERGES: the names only. The flag setter of the one entry (`setFileNameCaseHandlingName`) is left to the step that ports
# `setEarlyDefines`; `-Dfile_name_case_handling=…` is dropped from `defines` as upstream drops it, and then not applied at all.
"The `-D` flags the boot depends on, which pl-init.c sets before Prolog starts and `parseCommandLineOptions` leaves out of `defines`."
const EARLY_DEFINES = ("file_name_case_handling",)

# PORT: pl-init.c is_early_define
# (swipl-devel cbf4e189, src/pl-init.c:193-202)
"Whether the `-D` argument `def` (`name` or `name=value`) names an early define (pl-init.c)."
is_early_define(def::AbstractString)::Bool = any(n -> optcmp(def, n) !== nothing, EARLY_DEFINES)

# PORT: pl-init.c find_define
# (swipl-devel cbf4e189, src/pl-init.c:211-239)
"The value of `-Dname[=value]` in the raw arguments `argv` (`\"\"` where it carries no value, the last one wins), `nothing` where absent (pl-init.c)."
function find_define(name::AbstractString, argv::AbstractVector{<:AbstractString})::Union{Nothing, String}
    value = nothing
    k = 1
    while k <= length(argv)
        a = argv[k]
        def = nothing
        a == "--" && break                              # --: end of args
        if length(a) >= 2 && a[1] == '-' && a[2] == 'D'
            if length(a) > 2
                def = SubString(a, 3)
            elseif k < length(argv)                     # -D name=value
                def = argv[k + 1]
                k += 1
            end
        end
        if def !== nothing
            v = optcmp(def, name)
            v === nothing || (value = v)
        end
        k += 1
    end
    return value
end

# PORT: pl-init.c initDefaultOptions
# (swipl-devel cbf4e189, src/pl-init.c:1073-1092)
# DIVERGES: `systemDefaults` are keyword arguments: `stack_limit` and `table_space` (DEFSTACKLIMIT, DEFTABLE: 1 GiB,
# pl-init.h:131-138), `toplevel` (`default`), `startup` (DEFSTARTUP, absent in the pinned build's configuration: `nothing`)
# and `goal` (none). The set of these is the build's, not the run's.
"Set the options to their defaults, as `initDefaultOptions` does before the command line is read (pl-init.c)."
function initDefaultOptions!(
    o::pl_options_t;
    stack_limit::Int=1 << 30,
    table_space::Int=1 << 30,
    toplevel::String="default",
    startup::Union{Nothing, String}=nothing,
    goal::Union{Nothing, String}=nothing,
)::pl_options_t
    o.stackLimit = stack_limit
    o.tableSpace = table_space
    o.sharedTableSpace = table_space                   # O_PLMT: systemDefaults.shared_table_space
    o.compileOut = "a.out"
    o.topLevel = toplevel
    o.initFile = startup
    o.saveclass = "none"
    o.on_error = "print"
    o.on_warning = "print"
    o.bootFrom = nothing
    empty!(o.scriptFiles)
    empty!(o.goals)
    goal === nothing || push!(o.goals, goal)           # opt_append(&GD->options.goals, systemDefaults.goal)
    return o
end
