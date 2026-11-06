# allow-new-artifact: pl-init.c mirror, HALT1
# UPSTREAM: swipl-devel src/pl-init.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2012-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PORTED FROM pl-init.c: `PL_cleanup`, the clean-up `halt/1` ends with (HALT1), in a reduced form (below); and,
# from R2 LB7, the command line and the start-up of the Prolog part: `parseCommandLineOptions` and its helpers,
# `usage`, `defaultSystemInitFile`, the option records' defaults (`initDefaultOptions`) and the tail of
# `PL_initialise` that runs `'$initialise'` (`PL_initialise!`; the database it starts is the booted template's copy).
# LEFT OUT: `script_argv`, the saved states and the resource database, `findHome`/`initPaths` apart from the system
# init file name, `giveVersionInfo`, `run_on_halt` and the foreign hook lists (`PL_on_halt`, `PL_exit_hook`: the
# kernel has none), `qlfCleanup`, `RemoveTemporaryFiles`, `cleanupSignals` and the memory reclaim of
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

    checkPrologFlagsAccess(gd, ld)

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
# (src/pl-global.jl) and nothing else; below them `memarea_limit` and `parseCommandLineOptions`. `$cmd_option_val/2` and the
# start-up tail of `PL_initialise` follow in the next commits of LB7.

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
        if !(
            a[i] == o[j] ||
            (a[i] == UInt8('-') && o[j] == UInt8('_')) ||
            (a[i] == UInt8('_') && o[j] == UInt8('-'))
        )
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

# PORT: pl-init.c early_defines as EARLY_DEFINES
# (swipl-devel cbf4e189, src/pl-init.c:181-187)
# DIVERGES: the names only. The flag setter of the one entry (`setFileNameCaseHandlingName`) is left to the step that ports
# `setEarlyDefines`; `-Dfile_name_case_handling=…` is dropped from `defines` as upstream drops it, and then not applied at all.
"The `-D` flags the boot depends on, which pl-init.c sets before Prolog starts and `parseCommandLineOptions` leaves out of `defines`."
const EARLY_DEFINES = ("file_name_case_handling",)

# PORT: pl-init.c is_early_define
# (swipl-devel cbf4e189, src/pl-init.c:193-202)
"Whether the `-D` argument `def` (`name` or `name=value`) names an early define (pl-init.c)."
is_early_define(def::AbstractString)::Bool =
    any(n -> optcmp(def, n) !== nothing, EARLY_DEFINES)

# PORT: pl-init.c find_define
# (swipl-devel cbf4e189, src/pl-init.c:211-239)
"The value of `-Dname[=value]` in the raw arguments `argv` (`\"\"` where it carries no value, the last one wins), `nothing` where absent (pl-init.c)."
function find_define(
    name::AbstractString, argv::AbstractVector{<:AbstractString}
)::Union{Nothing, String}
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
    goal::Union{Nothing, String}=nothing
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

# PORT: pl-init.c memarea_limit
# (swipl-devel cbf4e189, src/pl-init.c:780-806; MEMAREA_INVALID_SIZE :780)
# DIVERGES: the size is an `Int` and `MEMAREA_INVALID_SIZE` is `nothing`. A negative number and a number above 64 bits are
# invalid here; upstream casts them to `size_t` (a huge limit, or a read of the unused part of the `number` union).
"""
    memarea_limit(ld, s) -> Union{Nothing, Int}

The size in bytes of `s`: an integer and an optional suffix `k`/`K` (KiB), `m`/`M` (MiB), `g`/`G` (GiB) or `b`/`B` (bytes),
`nothing` where `s` is anything else (pl-init.c).
"""
function memarea_limit(
    ld::PL_local_data{T}, s::AbstractString
)::Union{Nothing, Int} where {T}
    b = UInt8[codeunits(s); 0x00]                        # the C string, EOS-terminated
    n = number()
    rc, q = str_number(ld, b, 1, n, UInt32(0))
    if rc == NUM_OK && n.type === V_INTEGER && n.i >= 0
        c = b[q]                                         # *q
        clearNumber(n)
        c == 0x00 && return n.i
        (c == UInt8('k') || c == UInt8('K')) && return n.i * 1024
        (c == UInt8('m') || c == UInt8('M')) && return n.i * 1024 * 1024
        (c == UInt8('g') || c == UInt8('G')) && return n.i * 1024 * 1024 * 1024
        (c == UInt8('b') || c == UInt8('B')) && return n.i
        return nothing
    end
    clearNumber(n)
    return nothing
end

# PORT: pl-init.c parseCommandLineOptions
# (swipl-devel cbf4e189, src/pl-init.c:1113-1347; the macros optionString and optionList :100-117)
# DIVERGES: (1) the records `o` and `cmd` (`GD->options`, `GD->cmdline`) and the databases are arguments; the arguments left over
# (`argvleft`) are the value and `nothing` is upstream's `-1`. (2) `-d topic` (debug topics, `prolog_debug_from_string`) takes its
# word and is ignored: the kernel has no debug topics (owner DBG1; ruling Q7, audit D-0416 item 4). (3) `--traditional` (`setTraditional`) raises a
# `NotPortedError`: the kernel is SWI-7 only (`resetListAtoms` is not ported). (4) `--sigalert=N` is checked (0..31) and
# ignored: the kernel has no signal-alert thread. (5) `--no-tty`/`--tty` go through `PL_set_prolog_flag("tty_control", ...)` as
# upstream and so raise where the flag's value changes (os/pl-prologflag.jl: no terminal control). (6) `-b` sets
# `gd.bootsession`. (7) the `-tty` warning (`Sdprintf`) is collected on `ld.messages` (`_qlf_Sdprintf!`).
# The options are read before `$initialise` runs: the Prolog flags the mask bits feed
# (`debug`, `signals`, `debug_on_interrupt`) are re-read from the mask by `apply_options_to_flags!`.
"""
    parseCommandLineOptions(gd, ld, o, cmd, argv) -> Union{Nothing, Vector{String}}

Read the options of the command line `argv` (without the program name) into `o` and `cmd`, up to the first word that is not an
option or the word `--` (which stays, with everything after it, in the answer): the arguments left for the application, or `nothing`
for an error (an unknown or incomplete option, a bad value) (pl-init.c).
"""
function parseCommandLineOptions(
    gd::PL_global_data{T}, ld::PL_local_data{T}, o::pl_options_t, cmd::pl_cmdline_t,
    argv0::AbstractVector{<:AbstractString}
)::Union{Nothing, Vector{String}} where {T}
    argvleft = String[]
    o.xpce = -1
    n = length(argv0)
    k = 1
    while k <= n && startswith(argv0[k], '-')            # argv[0][0] == '-'
        s = SubString(String(argv0[k]), 2)               # &argv[0][1]
        if startswith(s, '-')                            # long options
            s = SubString(s, 2)
            isempty(s) && break                          # swipl <plargs> -- <app-args>
            rc = _parse_long_option!(gd, ld, o, cmd, s)
            rc < 0 && return nothing
            rc > 0 && !o.compile && push!(argvleft, String(argv0[k]))
            k += 1
            continue
        end
        if s == "tty"
            _qlf_Sdprintf!(ld, "Warning: `-tty` is deprecated.  Please use `--no-tty`\n")
            PL_set_prolog_flag(gd, ld, "tty_control", false)
            k += 1
            continue
        end
        if startswith(s, 'D')
            def = SubString(s, 2)
            if isempty(def)                              # -D name=value
                k < n || return nothing
                def = argv0[k + 1]
                k += 1
            end
            is_early_define(def) || push!(o.defines, String(def))   # setEarlyDefines() did these
            k += 1
            continue
        end
        atfirst = true
        for c in s
            if c == 'd'
                k < n || return nothing                  # -d topic (ignored: DIVERGES 2)
                k += 1
            elseif c == 'p'
                k < n || return nothing
                k += 1
                push!(o.search_paths, String(argv0[k]))
            elseif c == 'O'
                cmd.optimise = true
            elseif c == 'x'
                k < n || return nothing
                k += 1
                o.bootFrom = String(argv0[k])
            elseif c == 'o'
                k < n || return nothing
                k += 1
                o.compileOut = String(argv0[k])
            elseif c == 'f'
                k < n || return nothing
                k += 1
                o.initFile = String(argv0[k])
            elseif c == 'F'
                k < n || return nothing
                k += 1
                o.systemInitFile = String(argv0[k])
            elseif c == 'l' || c == 's'
                k < n || return nothing
                k += 1
                push!(o.scriptFiles, String(argv0[k]))
            elseif c == 'g'
                k < n || return nothing
                k += 1
                push!(o.goals, String(argv0[k]))
            elseif c == 't'
                k < n || return nothing
                k += 1
                o.topLevel = String(argv0[k])
            elseif c == 'c'
                o.compile = true
            elseif c == 'b'
                gd.bootsession = true
            elseif c == 'q'
                o.silent = true
            else
                atfirst || return nothing                  # a letter after others: error
                push!(argvleft, String(argv0[k]))        # an unknown option stays for the application
                break
            end
            atfirst = false
        end
        k += 1
    end
    while k <= n                                         # for(; argc>0; ...) the rest
        push!(argvleft, String(argv0[k]))
        k += 1
    end
    return argvleft
end

# The chain of `if ( rc=is_bool_opt(...) ) ... else if ( optval=is_longopt(...) )` of the long options of
# `parseCommandLineOptions`: `0` the option was taken, `1` it is none of these (the caller leaves it for the application),
# `-1` an error.
function _parse_long_option!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, o::pl_options_t, cmd::pl_cmdline_t,
    s::AbstractString
)::Int where {T}
    rc, b = is_bool_opt(s, "quiet")
    if rc != 0
        rc == 1 || return -1
        b && (o.silent = true)
        return 0
    end
    rc, b = is_bool_opt(s, "debug_on_interrupt")
    if rc != 0
        rc == 1 || return -1
        b && setPrologFlagMask!(ld, PLFLAG_DEBUG_ON_INTERRUPT)
        return 0
    end
    rc, b = is_bool_opt(s, "debug")
    if rc != 0
        rc == 1 || return -1
        b || clearPrologFlagMask!(ld, PLFLAG_DEBUGINFO)
        return 0
    end
    rc, b = is_bool_opt(s, "signals")
    if rc != 0
        rc == 1 || return -1
        if !b
            clearPrologFlagMask!(ld, PLFLAG_SIGNALS)
            o.nosignals = true
        end
        return 0
    end
    rc, b = is_bool_opt(s, "threads")
    if rc != 0
        rc == 1 || return -1
        b || (o.nothreads = true)
        return 0
    end
    rc, b = is_bool_opt(s, "tty")
    if rc != 0
        rc == 1 || return -1
        PL_set_prolog_flag(gd, ld, "tty_control", b)
        return 0
    end
    rc, b = is_bool_opt(s, "pce")
    if rc != 0
        rc == 1 || return -1
        o.xpce = b ? 1 : 0
        return 0
    end
    rc, b = is_bool_opt(s, "packs")
    if rc != 0
        rc == 1 || return -1
        cmd.packs = b
        return 0
    end
    optval = is_longopt(s, "pldoc")
    if optval !== nothing
        o.pldoc_server = optval
        return 0
    end
    is_longopt(s, "home") !== nothing && return 0        # already handled
    if is_longopt(s, "traditional") !== nothing
        throw(
            NotPortedError{T}(
                mk_sym(T, :traditional),
                "--traditional (setTraditional, resetListAtoms): the kernel is SWI-7 only",
                "R2 LB7"
            )
        )
    end
    optval = is_longopt(s, "sigalert")
    if optval !== nothing
        sig = tryparse(Int, optval)
        (sig !== nothing && sig >= 0 && sig < 32) || return -1   # DIVERGES 4: checked, no signal-alert thread
        return 0
    end
    optval = is_longopt(s, "stack_limit")
    if optval !== nothing
        size = memarea_limit(ld, optval)
        size === nothing && return -1
        o.stackLimit = size
        return 0
    end
    optval = is_longopt(s, "table_space")
    if optval !== nothing
        size = memarea_limit(ld, optval)
        size === nothing && return -1
        o.tableSpace = size
        return 0
    end
    optval = is_longopt(s, "shared_table_space")
    if optval !== nothing
        size = memarea_limit(ld, optval)
        size === nothing && return -1
        o.sharedTableSpace = size
        return 0
    end
    optval = is_longopt(s, "dump-runtime-variables")
    if optval !== nothing
        o.config = optval
        return 0
    end
    optval = is_longopt(s, "on-error")
    if optval !== nothing
        on_error_style(optval) || return -1
        o.on_error = optval
        return 0
    end
    optval = is_longopt(s, "on-warning")
    if optval !== nothing
        on_error_style(optval) || return -1
        o.on_warning = optval
        return 0
    end
    return 1
end

# ----- '$usage'/0 (R2 LB7): the text of `swipl --help` -----
# PORT: pl-init.c usage as USAGE_TEXT
# (swipl-devel cbf4e189, src/pl-init.c:1699-1769)
# DIVERGES: the lines in the pinned build's configuration (O_PLMT: `--shared-table-space`; no O_DEBUG: no `-d topic`; not Windows),
# one text, `%s` the program name. The program name is `swipl` always: upstream's `if ( os_argc <= 0 || (prog = BaseName(...)) )
# prog = "swipl"` assigns it where the BaseName call succeeds too (the condition is true either way), so `prog` is `swipl`
# whatever `os_argv[0]` is; the measured output of swipl 10.1.19 is this text with `swipl` (evidence/LB7/usage.txt).
const USAGE_TEXT = """%s: Usage:
    1) %s [options] prolog-file ... [-- arg ...]
    2) %s [options] [-o executable] -c prolog-file ...
    3) %s app ...        Use "%s app list" for available apps
    4) %s --help         Display this message
    5) %s --version      Display version information
    6) %s --abi-version  Display ABI version key
    7) %s --arch         Display architecture
    8) %s --dump-runtime-variables[=format]
                            Dump link info in sh(1) format

Options:
    -x state                 Start from state (must be first)
    -g goal                  Run goal (may be repeated)
    -t toplevel              Toplevel goal
    -f file                  User initialisation file
    -F file                  Site initialisation file
    -l file                  Script source file
    -s file                  Script source file
    -p alias=path            Define file search path 'alias'
    -Dname[=value]           Set a Prolog flag (may be repeated)
    -O                       Optimised compilation
    --on-error=style         One of print, halt or status
    --on-warning=style       One of print, halt or status
    --tty[=bool]             (Dis)allow tty control
    --packs[=bool]           Do (not) attach add-ons
    --signals[=bool]         Do (not) modify signal handling
    --sigalert[=num]         Use signal num for alerting threads
    --threads[=bool]         Do (not) allow for threads
    --debug[=bool]           Do (not) generate debug info
    --debug-on-interrupt[=bool] Trap the debugger on interrupt
    --quiet[=bool] (-q)      Do (not) suppress informational messages
    --traditional            Disable extensions of version 7
    --home[=DIR]             Print home or use DIR as SWI-Prolog home
    --stack-limit=size[BKMG] Specify maximum size of Prolog stacks
    --table-space=size[BKMG] Specify maximum size of SLG tables
    --shared-table-space=size[BKMG] Maximum size of shared SLG tables
    --pce[=bool]             Make the xpce gui available
    --pldoc[=port]           Start PlDoc server [at port]

Boolean options may be written as --name=bool, --name, --no-name or --noname.
Both '-' or '_' are accepted as word-separator for long options.
"""

"The text `usage()` writes to `user_error`: `USAGE_TEXT` with the program name `swipl` (pl-init.c)."
usage_text()::String = replace(USAGE_TEXT, "%s" => "swipl")

"Write the usage text to `user_error` (pl-init.c `usage`). True."
function usage(ld::PL_local_data)::Bool
    s = Suser_error(ld)::IOSTREAM               # open from the engine's creation (`initIO`), as in printMessage
    PutString(usage_text(), s)
    Sflush(s)
    return true
end

# PORT: pl-init.c usage as pl_usage0_va
# (PRED_IMPL("$usage", 0, usage, 0), pl-init.c:1771-1776 at the pin)
"`'\$usage'`: write the usage text to `user_error` (pl-init.c); reached by `argv_prolog_files` on an unknown option word."
function pl_usage0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    usage(ld)
    return FTRUE
end

# PORT: pl-init.c BeginPredDefs(init) as PL_predicates_from_init
# DIVERGES: `$usage/0` only; `$run_state/1` (saved states) is left to the step that ports them.
"pl-init.c's registration table (`BeginPredDefs(init)`): the ported entries."
const PL_predicates_from_init = (PL_extension("\$usage", 0, pl_usage0_va, PL_FA_VARARGS),)

# ----- the system init file name and the flags the options feed (R2 LB7) -----
# PORT: pl-init.c defaultSystemInitFile
# (swipl-devel cbf4e189, src/pl-init.c:738-759; called by `initPaths`, :881)
# DIVERGES: the program name is a `String`; the 255-character buffer limit (`--limit`) is kept; a path `PrologPath` refuses (too long) is
# `swipl` (upstream hands the NULL to `BaseName`).
"""
    defaultSystemInitFile(a0) -> String

The default name of the system init file (`-F`), from the program name `a0`: the leading letters and `-` of its base name, `swipl`
where there are none (pl-init.c).
"""
function defaultSystemInitFile(a0::AbstractString)::String
    plp = PrologPath(String(a0))
    base = plp === nothing ? nothing : BaseName(plp)
    if base !== nothing
        buf = UInt8[]
        limit = 256
        for c in codeunits(base)                        # *base && (isAlpha(*base) || *base == '-') && --limit > 0
            (isAlpha(Int(c)) || c == UInt8('-')) || break
            (limit -= 1) > 0 || break
            push!(buf, c)
        end
        !isempty(buf) && limit > 0 && return String(buf)
    end
    return "swipl"
end

# ORIGINAL (LB7): upstream reads `GD->options` and `GD->cmdline` where `initPrologFlags` defines each flag (pl-prologflag.c:2561,
# 2582, 2640-2641, 2706, 2776, 2812-2813), once, before any Prolog runs. The kernel's flag table exists when the command line is read
# (the booted template), so the same values are written after the parse; the mask bits `-q`-style options set on the local data
# (`--debug`, `--signals`, `--debug-on-interrupt`, `-O`) go to the database's mask too (`setPrologFlag` writes the database's; the local
# data keeps its own copy).
# DIVERGES: (1) `verbose` is written only for `-q` (`FF_KEEP`: upstream keeps a value `-Dverbose=...` set earlier; the early defines
# are not applied here). (2) `threads` is not written (read-only `false`, the single-thread configuration) and `xpce` and
# `shared_table_space` are not defined (those flags exist in upstream's threaded configuration only). (3) The stack limit goes to the
# local data in words (`ld.stacks_limit`, upstream's `LD->stacks.limit` is bytes). (4) `os_argv` is the whole command line, `argv` the
# arguments the parser left (the program name is dropped: pl-init.c:1537).
"""
    apply_options_to_flags!(gd, ld)

Write the command-line options (`gd.options`, `gd.cmdline`) into the Prolog flags and the masks they feed: `optimise`,
`generate_debug_info`, `debug_on_interrupt`, `signals`, `validate_api` (flags and mask bits), `verbose` (for `-q`), `on_error`, `on_warning`,
`packs`, `table_space`, `stack_limit`, `os_argv` and `argv`.
"""
function apply_options_to_flags!(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Nothing where {T}
    o = gd.options
    cmd = gd.cmdline

    for (name, bit, val) in (
        ("optimise", PLFLAG_OPTIMISE, cmd.optimise),                              # pl-prologflag.c:2561
        ("generate_debug_info", PLFLAG_DEBUGINFO, truePrologFlag(ld, PLFLAG_DEBUGINFO)),
        (
            "debug_on_interrupt",
            PLFLAG_DEBUG_ON_INTERRUPT,
            truePrologFlag(ld, PLFLAG_DEBUG_ON_INTERRUPT)
        ),
        ("signals", PLFLAG_SIGNALS, truePrologFlag(ld, PLFLAG_SIGNALS)),
        # `validate_api` is `!GD->cmdline.optimise` (swipl-devel V10.1.20 pl-prologflag.c:2695-2698): initPrologFlags! has run before the options
        ("validate_api", PLFLAG_VALIDATE_API, !cmd.optimise)
    )
        setPrologFlag(gd, name, FT_BOOL, val, bit)
        val ? setPrologFlagMask!(ld, bit) : clearPrologFlagMask!(ld, bit)
    end

    setPrologFlag(gd, "table_space", FT_INTEGER, o.tableSpace)                    # :2582
    setPrologFlag(gd, "stack_limit", FT_INTEGER, o.stackLimit)
    ld.stacks_limit = o.stackLimit ÷ 8                                            # initPrologStacks(GD->options.stackLimit)
    o.on_error === nothing || setPrologFlag(gd, "on_error", FT_ATOM, o.on_error::String)       # :2640
    o.on_warning === nothing ||
        setPrologFlag(gd, "on_warning", FT_ATOM, o.on_warning::String) # :2641
    o.silent && setPrologFlag(gd, "verbose", FT_ATOM, "silent")                   # :2706
    setPrologFlag(gd, "packs", FT_BOOL, cmd.packs, 0)                             # :2776
    _set_argv_prolog_flag!(gd, ld, "os_argv", cmd.os_argv)                        # :2812
    _set_argv_prolog_flag!(gd, ld, "argv", cmd.appl_argv)                         # :2813
    return nothing
end

# ----- PL_initialise: the part that starts the Prolog side (R2 LB7) -----
# PORT: pl-init.c PL_initialise as PL_initialise_tail!
# (swipl-devel cbf4e189, src/pl-init.c:1483-1682; the tail :1599-1682)
# DIVERGES: (1) the database is the booted template's copy: `setupProlog` and the loading of the boot state (`zip_open_archive`,
# `SopenZIP`, `loadWicFromStream`) have been done by the build of the template, so this runs the command-line part (:1501-1597,
# without `initOs`, `initDefaults`, `setEarlyDefines`, `initPaths`' paths, `giveVersionInfo`, the saved-state options), then
# `apply_options_to_flags!` where upstream's `initPrologFlags` read the options, then the tail. (2) `GD->initialised` is not stored
# (the database is new at each call, the early return `if GD->initialised` has no case). (3) `-c` (`GD->options.compile`) and
# `--config` (`$compile`, `$config`) raise `NotPortedError` by name. (4) `query_loop(goal, false)` is upstream's own path (`prologToplevel`, pl-pro.c:663-676, its `loop == false`
# branch: `$initialise` is neither `$query_loop` nor `$toplevel`, so `break_level` is not touched); owner TOP1b only for what the kernel's
# reduced `query_loop` leaves out of it (audit D-0416 item 4). (5) `initialiseForeign`, `registerForeignLicenses`, the resource
# database flag and `enableThreads` have nothing to do (no foreign libraries, no resource database, one thread).
"""
    PL_initialise_tail!(gd, ld) -> Bool

The end of `PL_initialise`: system access level while the options settle, the style checks every later load runs under, user access
level, then the Prolog goal `'\$initialise'` (`initialise_prolog`), whose success is the answer (pl-init.c).
"""
function PL_initialise_tail!(gd::PL_global_data{T}, ld::PL_local_data{T})::Bool where {T}
    o = gd.options
    setAccessLevel!(ld, ACCESS_LEVEL_SYSTEM)                       # :1614
    o.nosignals && clearPrologFlagMask!(ld, PLFLAG_SIGNALS)       # :1615-1617

    ld.debugstatus_styleCheck =                                    # :1663
        SINGLETON_CHECK | SEMSINGLETON_CHECK | DISCONTIGUOUS_STYLE | NOEFFECT_CHECK
    setAccessLevel!(ld, ACCESS_LEVEL_USER)                         # :1666

    if o.config !== nothing
        throw(NotPortedError{T}(mk_sym(T, :config), "--config (\$config)", "R2 LB7"))
    elseif o.compile
        throw(NotPortedError{T}(mk_sym(T, :compile), "-c (\$compile)", "R2 LB7"))
    end
    return query_loop(gd, ld, mk_sym(T, Symbol("\$initialise")), false) == 1   # prologToplevel("$initialise")
end

"""
    PL_initialise!(gd, ld, argv) -> Bool

`PL_initialise(argc, argv)` on the database `gd` with local data `ld`: `argv[1]` is the program name. Reads the options
(`parseCommandLineOptions`; an error writes the usage text to `user_error` and answers false), feeds the flags
(`apply_options_to_flags!`) and runs `'\$initialise'` (`PL_initialise_tail!`) (pl-init.c).
"""
function PL_initialise!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, argv::AbstractVector{<:AbstractString}
)::Bool where {T}
    o = gd.options
    cmd = gd.cmdline
    cmd.os_argv = String[String(a) for a in argv]                   # :1501-1503
    cmd.packs = true
    o.systemInitFile = isempty(argv) ? "none" : defaultSystemInitFile(argv[1])   # initPaths, :881
    initDefaultOptions!(o)                                          # :1524

    args = String[String(a) for a in argv[(firstindex(argv) + 1):end]]   # argc--; argv++
    argvleft = parseCommandLineOptions(gd, ld, o, cmd, args)
    if argvleft === nothing
        usage(ld)
        return false
    end
    cmd.appl_argv = argvleft                                        # :1591-1592
    apply_options_to_flags!(gd, ld)
    return PL_initialise_tail!(gd, ld)
end

"""
    PL_initialise!(T, argv) -> (gd, ld, ok)

A new database of term type `T` (the booted template's copy) and a local data, started by `PL_initialise!(gd, ld, argv)`;
`ok` is its answer (pl-init.c).
"""
function PL_initialise!(::Type{T}, argv::AbstractVector{<:AbstractString}) where {T}
    gd = PL_global_data{T}()
    ld = PL_local_data{T}(gd)
    ok = PL_initialise!(gd, ld, argv)
    return (gd, ld, ok)
end
