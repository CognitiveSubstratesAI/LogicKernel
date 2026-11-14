# UPSTREAM: swipl-devel src/pl-qlf.c @ 18168e629eab
# UPSTREAM: swipl-devel src/SWI-Prolog.h @ 18168e629eab
# UPSTREAM: swipl-devel src/mkvmi.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE BOOT COMPILATION (R2 LB3; design evidence/r2/design/loader_boot.md LD2, LD3): pl-qlf.c's restricted
# compilation toplevel for `-b` — `compileFile` reads a file clause by clause, runs its directives in `user`
# (`directiveClause` qualifies each with the source module), honours `:- if/else/endif` to a depth of
# `MAX_IFDEF_NEST` (`update_conditional_compilation`), runs a `'$:-'` term without recording it, and asserts
# every other term; `compileFileList` runs it over the boot files in system mode with `autoload` off.
# THE STATE FILE IS NOT WRITTEN (LD2): `LD->qlf.write_state` stays NULL (`ld.qlf_write_state`, typed `Nothing`),
# so the write steps (`qlfStartFile`, `qlfEndPart`, `addDirectiveWic`, `saveWicClause`, `writeWicHeader`,
# `writeWicTrailer`) write nothing, and the seven write-side predicates take their NULL branch — upstream's
# whole behaviour when no state is open. Of the other 15 predicates (QLF1, QLF1B) ten are real or take the NULL branch; five read a QLF body or write a state file and are
# refused by name (`NotPortedError`). A message the C loop prints with `Sdprintf` is collected on the local
# data's `messages` (`_qlf_Sdprintf!`), as printMessage's fallback branches are (src/pl-error.jl).

# ── conditional compilation (pl-qlf.c:4582-4689) ───────────────────────────────────────────────────

# PORT: pl-qlf.c directiveClause
# (swipl-devel cbf4e189, src/pl-qlf.c:4582-4608)
# DIVERGES: the functor's name is compared as a symbol (`streq(stringAtom(name), functor)`); the module is
# the source module's atom (`LD->modules.source->name`).
"""
If the term `clause` is `functor(D)` (`":-"` or `"\$:-"`), put the directive `D` into `directive`, qualified with
the source module unless it is `M:G` already, and return true (pl-qlf.c).
"""
function directiveClause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, directive::term_t, clause::term_t,
    functor::Symbol
)::Bool where {T}
    d0 = PL_new_term_ref(ld)

    na = PL_get_name_arity(ld, clause)
    (na === nothing || na[2] != 1 || sym_key(na[1]) != sym_key(mk_sym(T, functor))) &&
        return false

    _PL_get_arg(ld, 1, clause, d0)
    if PL_is_functor(ld, d0, mk_sym(T, :(:)), 2)    # PL_get_functor(d0, &f) && f == FUNCTOR_colon2
        PL_put_term(ld, directive, d0)
    else
        m = PL_new_term_ref(ld)
        m == 0 && return false
        PL_put_atom(ld, m, gd.modules[ld.modules_source].atom)   # LD->modules.source->name
        return PL_cons_functor(ld, directive, FUNCTOR_colon2, m, d0)
    end

    return true
end

# PORT: pl-qlf.c iftrue
# (swipl-devel cbf4e189, src/pl-qlf.c:4611-4615)
"The state of one `:- if` level (pl-qlf.c `iftrue`): its part is compiled (`IF_TRUE`), not yet (`IF_FALSE`), or never (`IF_ELSE_FALSE`)."
@enum iftrue::Int8 begin
    IF_FALSE
    IF_TRUE
    IF_ELSE_FALSE
end

# PORT: pl-qlf.c MAX_IFDEF_NEST
# (swipl-devel cbf4e189, src/pl-qlf.c:4617)
"The levels of `:- if` the boot compilation keeps, the file's own level 0 included (pl-qlf.c)."
const MAX_IFDEF_NEST = 3

# PORT: pl-qlf.c condc
# (swipl-devel cbf4e189, src/pl-qlf.c:4619-4622)
# DIVERGES: `ctrue` is a vector of `MAX_IFDEF_NEST` entries indexed `depth + 1` (upstream: a C array from 0).
"The conditional-compilation state of one file (pl-qlf.c `condc`): the current depth and each level's state."
mutable struct condc
    depth::Int
    const ctrue::Vector{iftrue}
end
"`condc cond = {.depth = 0, .ctrue[0] = IF_TRUE}` (pl-qlf.c compileFile)."
condc() = condc(0, iftrue[IF_TRUE, IF_FALSE, IF_FALSE])

# PORT: pl-qlf.c cond_true
# (swipl-devel cbf4e189, src/pl-qlf.c:4624-4627)
"True when terms at the current `:- if` level are compiled (pl-qlf.c)."
cond_true(cond::condc)::Bool = cond.ctrue[cond.depth + 1] == IF_TRUE

# PORT: pl-qlf.c update_conditional_compilation
# (swipl-devel cbf4e189, src/pl-qlf.c:4632-4689)
# DIVERGES: `fatalError` (upstream ends the process) is a Julia `error` naming upstream's message, which ends
# the boot (`compileFile`'s caller sees an exception, no Prolog answer exists to give).
"""
If the qualified directive `term` is `M:if(G)`, `M:else` or `M:endif`, update `cond` and return true; `if(G)`'s goal
runs in `user` when the current level is compiled (pl-qlf.c). There is no `elif`.
"""
function update_conditional_compilation(
    gd::PL_global_data{T}, ld::PL_local_data{T}, term::term_t, cond::condc
)::Bool where {T}
    PL_is_functor(ld, term, mk_sym(T, :(:)), 2) || return false   # FUNCTOR_colon2

    g = PL_new_term_ref(ld)
    _PL_get_arg(ld, 2, term, g)
    rc = false
    ctrue = cond_true(cond)

    if PL_is_functor(ld, g, mk_sym(T, :if), 1)      # FUNCTOR_if1
        cond.depth + 1 >= MAX_IFDEF_NEST && error("To deeply nested :- if")   # fatalError

        if ctrue
            arg = PL_new_term_ref(ld)
            _PL_get_arg(ld, 1, g, arg)
            if callProlog(gd, ld, MODULE_user(gd).index, arg, PL_Q_NODEBUG)
                new = IF_TRUE
            else
                new = IF_FALSE
            end
        else
            new = IF_ELSE_FALSE
        end

        cond.depth += 1
        cond.ctrue[cond.depth + 1] = new            # cond->ctrue[++cond->depth] = new
        rc = true
    else
        a = PL_get_atom(ld, g)
        if a !== nothing
            if sym_key(a) == sym_key(mk_sym(T, :else))          # a == ATOM_else
                cur = cond.ctrue[cond.depth + 1]
                if cur == IF_TRUE
                    new = IF_FALSE
                elseif cur == IF_FALSE
                    new = IF_TRUE
                else
                    new = IF_ELSE_FALSE
                end
                cond.ctrue[cond.depth + 1] = new
                rc = true
            elseif sym_key(a) == sym_key(mk_sym(T, :endif))     # a == ATOM_endif
                cond.depth == 0 && error("Too many :- endif\n") # fatalError
                cond.depth -= 1
                rc = true
            end
        end
    end

    PL_reset_term_refs(ld, g)

    return rc
end

# ── the state file's write steps, with no state (LD2) ───────────────────────────────────────────────

# ORIGINAL (LB3): upstream's `Sdprintf(fmt, …)` to `Serror` in the boot loop. The text is collected on the
# local data's `messages` as the atom of the text, severity `:error`, so a boot message is never lost (the
# design's H1). Since LB4 b2 printMessage's fallback branches (src/pl-error.jl) collect here too.
"Collect the boot loop's diagnostic `text` (upstream: `Sdprintf` to the error stream)."
function _qlf_Sdprintf!(ld::PL_local_data{T}, text::String)::Nothing where {T}
    push!(ld.messages, (:error, mk_sym(T, Symbol(text))))
    return nothing
end

# ORIGINAL (LB4 b2): upstream's `pl_write(term)` after a boot diagnostic (addClauseWic) and printMessage's
# `PL_write_term(Serror, av+1, 1200, 0)`: the term is collected on the local data's `messages`, severity `:error`,
# EXPORTED off the cells once (`export_cells`), after the `_qlf_Sdprintf!` text it follows.
"Collect the term `t` references after a boot diagnostic (upstream: written to the error stream). True."
function _qlf_pl_write!(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    push!(ld.messages, (:error, export_cells(ld, cell_export{T}(), -(t + 1))))
    return true
end

# PORT: pl-qlf.c qlfStartFile
# (swipl-devel cbf4e189, src/pl-qlf.c:4069-4078)
# DIVERGES: there is no state (LD2: `state` is `nothing`), so `closePredicateWic`, `Sputc('Q', fd)` and
# `qlfSaveSource` — the state file's writes — write nothing.
"Start the part of the state file for the source file `f` (pl-qlf.c); with no state, nothing to write."
qlfStartFile(state::Nothing, f::SourceFile)::Bool = true

# PORT: pl-qlf.c qlfEndPart
# (swipl-devel cbf4e189, src/pl-qlf.c:4081-4089)
# DIVERGES: as `qlfStartFile` (`closePredicateWic`, `Sputc('X', fd)`).
"End the current part of the state file (pl-qlf.c); with no state, nothing to write."
qlfEndPart(state::Nothing)::Bool = true

# PORT: pl-qlf.c addDirectiveWic
# (swipl-devel cbf4e189, src/pl-qlf.c:3240-3250)
# DIVERGES: as `qlfStartFile` (`closePredicateWic`, `Sputc('D', fd)`, the line, `saveQlfTerm`).
"Record the directive `term` in the state file (pl-qlf.c); with no state, nothing to write."
addDirectiveWic(state::Nothing, term::term_t)::Bool = true

# PORT: pl-qlf.c addClauseWic
# (swipl-devel cbf4e189, src/pl-qlf.c:3220-3238)
# DIVERGES: the clause is asserted as upstream's; with no state (LD2) `openPredicateWic` and `saveWicClause`
# write nothing. `pl_write(term)` after "Failed to compile: " is the term collected as an `:error` message
# (`_qlf_pl_write!`), the line end not collected.
"Assert the clause `term` read from `file` at the end of its predicate, as loading the file does (pl-qlf.c)."
function addClauseWic(
    gd::PL_global_data{T}, ld::PL_local_data{T}, state::Nothing, term::term_t, file::T
)::Bool where {T}
    loc = sourceloc{T}(file, ld.read_source.position.lineno)   # loc.file = file; loc.line = source_line_no

    clause = assert_term!(gd, ld, term, 0, CL_END, file, loc, 0)
    if clause !== nothing
        # openPredicateWic(state, clause->predicate, ATOM_development); saveWicClause(state, clause): no state
        return true
    end

    _qlf_Sdprintf!(ld, "Failed to compile: ")
    _qlf_pl_write!(ld, term)                        # pl_write(term)
    return false
end

# ── the boot loop (pl-qlf.c:4691-4820) ─────────────────────────────────────────────────────────────

# ORIGINAL (LB3): `source_file_name` (an atom, NULL_ATOM while no file is read) as the text `%s` prints.
function _qlf_source_file_text(ld::PL_local_data{T}) where {T}
    f = ld.read_source.file                         # read once: the field is mutable
    return f === nothing ? "" : String(sym_text(f))
end

# PORT: pl-qlf.c compileFile
# (swipl-devel cbf4e189, src/pl-qlf.c:4691-4780)
# DIVERGES: `AbsoluteFile` and `LastModifiedFile` (os/pl-os.c) are Julia's `abspath` and `stat` (R2 LB2b ports
# pl-os.c); `PL_unify_chars(f, PL_ATOM|REP_MB, …)` is `PL_put_atom` on a new reference; `Sdprintf` is
# `_qlf_Sdprintf!` (collected). As upstream: a syntax error's `continue` and the end of file's `break` leave that
# iteration's foreign frame open (:4738, :4741), `endConsult` is not called, and the source file's reference
# from `lookupSourceFile` is kept.
"""
Compile the file `file` the way the boot compilation does (pl-qlf.c): read it clause by clause from its own
input context; run each directive `:- D` in `user`, qualified with the source module, unless it is a
conditional-compilation one or in a part not compiled; run `'\$:-'(D)` without recording it; assert every other
term. A directive that fails is reported as `File:Line: directive failed` and the loop continues.
"""
function compileFile(
    gd::PL_global_data{T}, ld::PL_local_data{T}, state::Nothing, file::String
)::Bool where {T}
    f = PL_new_term_ref(ld)
    cond = condc()                                  # {.depth = 0, .ctrue[0] = IF_TRUE}

    path = abspath(file)                            # AbsoluteFile(file, tmp, sizeof(tmp))

    nf = mk_sym(T, Symbol(path))
    PL_put_atom(ld, f, nf)                          # PL_unify_chars(f, PL_ATOM|REP_MB, (size_t)-1, path)
    if !pl_see(ld, f)
        _qlf_Sdprintf!(ld, "Failed to open $path\n")
        return false
    end
    sf = lookupSourceFile(gd, nf, true)::SourceFile{T}
    startConsult(sf)
    st = stat(path)                                 # LastModifiedFile(path, &sf->mtime)
    if ispath(st)
        sf.mtime = st.mtime
    else
        _qlf_Sdprintf!(ld, "Failed to get time from $path\n")
    end
    qlfStartFile(state, sf)

    while true
        cid = PL_open_foreign_frame(ld)
        t = PL_new_term_ref(ld)
        directive = PL_new_term_ref(ld)

        PL_put_variable(ld, t)
        if !read_clause(gd, ld, Scurin(ld)::IOSTREAM, t, 0)   # syntax error
            _qlf_Sdprintf!(
                ld,
                "$(_qlf_source_file_text(ld)):$(ld.read_source.position.lineno): Syntax error\n"
            )
            continue
        end
        eof = PL_get_atom(ld, t)
        (eof !== nothing && sym_key(eof) == sym_key(mk_sym(T, :end_of_file))) && break

        if directiveClause(gd, ld, directive, t, Symbol(":-"))
            if !update_conditional_compilation(gd, ld, directive, cond)
                if cond_true(cond)
                    addDirectiveWic(state, directive)
                    if !callProlog(gd, ld, MODULE_user(gd).index, directive, PL_Q_NODEBUG)
                        _qlf_Sdprintf!(
                            ld,
                            "$(_qlf_source_file_text(ld)):$(ld.read_source.position.lineno): directive failed\n"
                        )
                    end
                end
            end
        elseif cond_true(cond)
            if directiveClause(gd, ld, directive, t, Symbol("\$:-"))
                callProlog(gd, ld, MODULE_user(gd).index, directive, PL_Q_NODEBUG)
            else
                addClauseWic(gd, ld, state, t, nf)
            end
        end

        PL_discard_foreign_frame(ld, cid)
    end

    qlfEndPart(state)
    pl_seen(ld)

    return true
end

# PORT: pl-qlf.c compileFileList
# (swipl-devel cbf4e189, src/pl-qlf.c:4783-4820)
# DIVERGES: `writeWicHeader` and `writeWicTrailer` write the state file's header and trailer: there is no state
# (LD2), so `fd` is no argument and both are left out; `argv` is a vector of file names. `PL_set_prolog_flag("autoload",
# PL_BOOL, …)` is the kernel's `PL_set_prolog_flag` (src/os/pl-prologflag.jl): through `set_prolog_flag`, so the
# mask bit `PLFLAG_AUTOLOAD` follows the flag (`setAutoload`; `propagateAutoload` is skipped in the boot session) —
# since AUTOLOAD1 A4; before, `setPrologFlag` wrote the atom alone. `setAccessLevel` returns nothing, so the level to
# restore is read first.
# As upstream: a false `compileFile` returns false with the access level and `autoload` not restored.
"""
Compile the boot files `argv` in system mode with `autoload` off, up to an argument `"-c"`, then call
`user:'\$load_additional_boot_files'/0` (pl-qlf.c). False when a file fails to compile, or that predicate fails or
raises.
"""
function compileFileList(
    gd::PL_global_data{T}, ld::PL_local_data{T}, state::Nothing, argv::Vector{String}
)::Bool where {T}
    alevel = ld.prolog_flag_access_level                       # alevel = setAccessLevel(ACCESS_LEVEL_SYSTEM)
    setAccessLevel!(ld, ACCESS_LEVEL_SYSTEM)
    PL_set_prolog_flag(gd, ld, "autoload", false)

    ld.qlf_write_state = state                                 # make Prolog compilation go into state
    for file in argv
        file == "-c" && break
        compileFile(gd, ld, state, file) || return false
    end

    PL_set_prolog_flag(gd, ld, "autoload", true)
    setAccessLevel!(ld, alevel)

    pred = lookupProcedure(
        mk_sym(T, Symbol("\$load_additional_boot_files")), 0, MODULE_user(gd)
    )
    rc = PL_call_predicate(gd, ld, MODULE_user(gd), PL_Q_DEBUG, pred, 0)   # PL_call_predicate(MODULE_user, true, pred, 0)

    ld.qlf_write_state = nothing
    return rc
end

# ORIGINAL (LB3): pl-init.c has no function of its own for this: it is the `GD->bootsession` branch of
# `PL_initialise` (pl-init.c:1614-1647, :1654-1666) — system mode, the boot flag on, `compileFileList` over the
# command line's files, the flag off, the style checks every later load runs under, user mode — as one call.
# DIVERGES: the resource database (`SopenZIP`, `Sclose`, `zip_close_archive`) and `PL_halt` are left out (no state
# file, LD2): a false `compileFileList` returns false where upstream halts with 1; the closing `$boot_message`
# is not called. Nothing here is registered as a predicate.
"""
Run the boot compilation over the files `argv` (see `compileFileList`) the way `PL_initialise` does in a boot session:
returns whether it succeeded; leaves `gd.bootsession` false, the style checks set and the access level `USER`.
"""
function boot_from_source!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, argv::Vector{String}
)::Bool where {T}
    setAccessLevel!(ld, ACCESS_LEVEL_SYSTEM)
    gd.bootsession = true
    rc = compileFileList(gd, ld, nothing, argv)
    gd.bootsession = false
    rc || return false

    ld.debugstatus_styleCheck =
        SINGLETON_CHECK | SEMSINGLETON_CHECK | DISCONTIGUOUS_STYLE | NOEFFECT_CHECK
    setAccessLevel!(ld, ACCESS_LEVEL_USER)
    return true
end

# ORIGINAL (R2 LB4 b2-1; loader_boot.md LD4, H11): the database the process boots once per term type, the build of the
# template registry (src/gd_template.jl). `PL_initialise`'s order (pl-init.c:1603-1666): `setupProlog`, then the boot
# session over the files the build passes, `-b HOME/boot/init.pl` (src/CMakeLists.txt:357-361), whose `'$:-'` loads
# HOME/boot/load.pl and the files it lists (init.pl:4797-4806). It runs on a LOCAL DATA OF ITS OWN, which is dropped:
# the template keeps nothing of it. H11 asserts the boot left the stacks exactly as upstream's boot leaves them
# (`compileFile_leaves`, plus the one trail entry the call of `'$load_additional_boot_files'` keeps): no other frame or
# term reference made by the boot survives it.
# DIVERGES: `threads` is false (src/os/pl-prologflag.jl, read-only), upstream's own single-thread build
# (`MULTI_THREADED=OFF`: os/pl-prologflag.c:2620-2622, CMakeLists.txt:92), where the oracle is a threaded build: the
# `:- if(current_prolog_flag(threads, true))` sections of the boot (init.pl:2557, 2720, 2735, 2754-2785, 982,
# toplevel.pl:560: `$mt_load_file`, with_mutex, message queues, thread_statistics) compile their single-thread
# branches. A scope decision about the build configuration, audit D-0354 item 3; the rows about those paths are pinned
# as DIVERGES. The build's `-O` (pl-init.c:1280, `GD->cmdline.optimise`) is not applied: `optimise` stays false during
# the boot (handoff flag F3). The `HOME` the boot reads is the `home` flag's tree (tools/build_home.jl builds it).
"""
    boot_global_data(T) -> PL_global_data{T}

A new database of term type `T` booted from the vendored boot files (`setupProlog`, then `boot_from_source!` over
`HOME/boot/init.pl`). Raises if the home tree is missing or the boot fails. Called once per process and type, by
the template registry (`gd_template`); a database is made with `PL_global_data{T}()`, the template's copy.
"""
function boot_global_data(::Type{T})::PL_global_data{T} where {T}
    gd = setupProlog(T)
    home = current_prolog_flag_atom(gd, mk_sym(T, :home))
    home === nothing && error("boot_global_data: the `home` flag has no atom value")
    initpl = joinpath(sym_text(home), "boot", "init.pl")
    isfile(initpl) || error(
        "boot_global_data: $initpl is missing: build the home tree first (julia tools/build_home.jl)"
    )
    ld = PL_local_data{T}(gd)
    argv = [initpl]
    empty_at = boot_stacks(ld)                                    # H11: as emptyStacks! left them
    boot_from_source!(gd, ld, argv) ||
        error("boot_global_data: the boot compilation of $initpl failed")
    after = boot_stacks(ld)
    # H11: compileFile's leftovers per file, then the one entry the '$load_additional_boot_files' call keeps (measured)
    left = compileFile_leaves(empty_at, length(argv)) .+ (0, 1, 0, 0)
    (left != empty_at && after == left) ||
        error(
            "boot_global_data: the boot left its stacks at $after, not $left (from $empty_at, H11)"
        )
    drop_boot_std_streams!(gd, ld)                                # the template keeps no stream of the dropped ld
    drop_boot_autoimports!(gd)                                    # nor a run-time autoImport link (src/gd_template.jl)
    return gd
end

# ORIGINAL (loader_boot.md H11): the boot ld's standard streams leave the database with it. Upstream's initIO registers
# the process's Sinput, Soutput and Serror for enumeration (swipl-devel cbf4e189 src/os/pl-file.c:547-549, run by
# setupProlog, src/pl-setup.c:173) in every process, the boot session's included; the boot session then halts
# (pl-init.c:1620-1646), and the state it writes carries no stream table: the process that loads it registers its own
# three at its own initIO. The kernel's boot ld (`initIO` the first time the boot writes, src/os/pl-file.jl) is dropped,
# so the entries of its three user streams are cleared as a close clears one (`freeStream`: the slot becomes
# `nothing`), after a flush of the output ones (upstream's halt flushes them). Only those three: any other stream the
# boot left open stays, and the template's copy refuses it (src/gd_template.jl `_copy_stream_free`).
"Clear the stream-table entries of `ld`'s three user standard streams (flushed first) from `gd`: the boot's dropped ld."
function drop_boot_std_streams!(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Nothing where {T}
    for i in (SNO_USER_INPUT, SNO_USER_OUTPUT, SNO_USER_ERROR)
        s = ld.IO_streams[i + 1]
        s === nothing && continue
        (s.flags & SIO_OUTPUT) == 0 || Sflush(s)
        if 1 <= s.context <= length(gd.stream_table) && gd.stream_table[s.context] === s
            gd.stream_table[s.context] = nothing                  # deleteHTablePP(streamContext, s), as freeStream
        end
    end
    return nothing
end

# ORIGINAL (loader_boot.md H11): the one reader of the four positions H11 compares, used on both sides.
"The stack positions H11 compares (`ld.lTop`, the trail's length, `ld.fli_context`, `ld.nfliframes`)."
boot_stacks(ld::PL_local_data{T}) where {T} =
    (ld.lTop, length(ld.trail), ld.fli_context, ld.nfliframes)::NTuple{4, Int}

# ORIGINAL (loader_boot.md H11): what `compileFile` leaves on the stacks, as upstream's does (swipl-devel cbf4e189,
# src/pl-qlf.c:4700 `f`, os/pl-file.c:4446-4485 pl_see's `mode`, pl-qlf.c:4726-4741 the per-clause frame `cid`
# with `t` and `directive`, left open by the `break` at end_of_file, before `PL_discard_foreign_frame(cid)`): per
# file, two references, then that frame (its header and two references) with the one trail entry the read of
# end_of_file makes in it (measured). Upstream's boot session halts after `compileFileList`, so the leftover is
# never freed there. A `read_clause` that fails takes the loop's `continue` and leaves one frame more (pl-qlf.c:
# 4734-4739); a syntax error under the default `syntax_errors` is reported and read past, so it takes no `continue`.
"""
    compileFile_leaves(at, nfiles) -> NTuple{4,Int}

The `boot_stacks` reading after `compileFile` ran over `nfiles` files from the reading `at`, with no `read_clause`
failure: per file 2 references and an open foreign frame of `SIZEOF_FLIFRAME` + 2, one trail entry in it.
"""
function compileFile_leaves(at::NTuple{4, Int}, nfiles::Int)::NTuple{4, Int}
    nfiles >= 1 || error("compileFile_leaves: nfiles = $nfiles, at least one file")
    ltop, trail, _, nframes = at
    return (
        ltop + nfiles * (2 + SIZEOF_FLIFRAME + 2),
        trail + nfiles,
        nframes + nfiles,
        nframes + nfiles
    )
end

# ── the predicates of pl-qlf.c (BeginPredDefs(wic), pl-qlf.c:4953-4976) ───────────────────────────────

# The eight write-side predicates take upstream's NULL-state branch (`LD->qlf.write_state` is NULL: LD2). Each is
# `PRED_IMPL(name, arity, f, flags)` with `PRED_DEF` or-ing in `PL_FA_VARARGS`: the argument terms are
# `PL__t0 + i`, none is checked on the NULL branch.

# PORT: pl-qlf.c qlf_start_module as pl_qlf_start_module1_va
# (PRED_IMPL("$qlf_start_module", 1, qlf_start_module, 0)) — pl-qlf.c:4094-4110
"`'\$qlf_start_module'(+Module)` (pl-qlf.c): start a module in the state file; with no state, true."
function pl_qlf_start_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c qlf_start_sub_module as pl_qlf_start_sub_module1_va
# (PRED_IMPL("$qlf_start_sub_module", 1, qlf_start_sub_module, 0)) — pl-qlf.c:4112-4128
"`'\$qlf_start_sub_module'(+Module)` (pl-qlf.c): as `'\$qlf_start_module'/1`; with no state, true."
function pl_qlf_start_sub_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c qlf_start_file as pl_qlf_start_file1_va
# (PRED_IMPL("$qlf_start_file", 1, qlf_start_file, 0)) — pl-qlf.c:4130-4160
"`'\$qlf_start_file'(+File)` (pl-qlf.c): start a source file's part in the state file; with no state, true."
function pl_qlf_start_file1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c qlf_include as pl_qlf_include5_va
# (PRED_IMPL("$qlf_include", 5, qlf_include, 0)) — pl-qlf.c:4174-4197
# DIVERGES: the NULL state is the only one: the five arguments are checked in upstream's order (the atoms
# `Owner`, `PN`, the integer `Line`, the atom `File`, the float `Time`), then the predicate FAILS (upstream's
# `(state=LD->qlf.write_state)` is the last conjunct, and false the fall-through). FLAG Q2 (LB4): upstream's boot
# has a state open, so init.pl's `'\$record_included'` succeeds there; here it fails on an `include/1` read by the boot.
"`'\$qlf_include'(+Owner, +PN, +Line, +File, +Time)` (pl-qlf.c): record an include in the state file; with no state, false."
function pl_qlf_include5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    PL_get_atom_ex(ld, A1) === nothing && return FFALSE         # owner
    PL_get_atom_ex(ld, A2) === nothing && return FFALSE         # pn
    PL_get_integer_ex(ld, A3) === nothing && return FFALSE      # line
    PL_get_atom_ex(ld, A4) === nothing && return FFALSE         # fn
    PL_get_float(ld, A5) === nothing && return FFALSE           # time
    return FFALSE                                               # (state=LD->qlf.write_state): NULL
end

# PORT: pl-qlf.c qlf_end_part as pl_qlf_end_part0_va
# (PRED_IMPL("$qlf_end_part", 0, qlf_end_part, 0)) — pl-qlf.c:4219-4230
"`'\$qlf_end_part'` (pl-qlf.c): end the current part of the state file; with no state, true."
function pl_qlf_end_part0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c add_directive_wic as pl_add_directive_wic1_va
# (PRED_IMPL("$add_directive_wic", 1, add_directive_wic, PL_FA_TRANSPARENT)) — pl-qlf.c:4479-4505
"`'\$add_directive_wic'(:Goal)` (pl-qlf.c): record a directive in the state file; with no state, true."
function pl_add_directive_wic1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c import_wic as pl_import_wic3_va
# (PRED_IMPL("$import_wic", 3, import_wic, 0)) — pl-qlf.c:4512-4530
# DIVERGES: the NULL state's branch only (it succeeds). The brief listed this predicate among the 15 refused by name;
# it is an EIGHTH shell because boot/init.pl calls it in wic mode through `'\$ifcompiling'` (init.pl:3794,
# `'\$import_all2'`) (FLAG Q1, audit).
"`'\$import_wic'(+Module, +PredicateIndicator, +Strength)` (pl-qlf.c): record an import in the state file; with no state, true."
function pl_import_wic3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c qlf_assert_clause as pl_qlf_assert_clause2_va
# (PRED_IMPL("$qlf_assert_clause", 2, qlf_assert_clause, 0)) — pl-qlf.c:4537-4561
"`'\$qlf_assert_clause'(+ClauseRef, +Class)` (pl-qlf.c): save a clause in the state file; with no state, true."
function pl_qlf_assert_clause2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# The 3 predicates that load a QLF body or write a state file (`$qlf_load`, `$open_wic`, `$qlf_open`) are refused by name: calling one raises `NotPortedError` with
# its indicator (LD2, Q2a; the QLF loader and writer are left to Q2a — the boot compiles from source).
"Raise `NotPortedError` for the predicate `name/arity` of pl-qlf.c's table (refused by name, LD2)."
function _qlf_refused(::Type{T}, name::String, arity::Int)::Union{} where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, Symbol(name)),
            "the QLF file predicate $name/$arity",
            "LB3: refused by name"
        )
    )
end

# ── the QLF header: versions and compatibility (pl-qlf.c:573-636, 3329-3355, 3498-3578, 3648-3680, 3802-3816, 3914-3932) ──

# PORT: SWI-Prolog.h PL_QLF_LOADVERSION
"The oldest QLF save version this system loads (SWI-Prolog.h, 18168e62)."
const PL_QLF_LOADVERSION = 68
# PORT: SWI-Prolog.h PL_QLF_VERSION
"The QLF save version this system writes (SWI-Prolog.h, 18168e62)."
const PL_QLF_VERSION = 72

# PORT: pl-qlf.c qlfMagic
# (pl-qlf.c:233)
"The magic string a QLF file starts with (the file stores it NUL terminated)."
const qlfMagic = "SWI-Prolog .qlf file\n"

# PORT: mkvmi.c VM_SIGNATURE
# DIVERGES: upstream's `VM_SIGNATURE` is generated by mkvmi.c (a MurmurHash of pl-vmi.def's synopsis, vmi-metadata.h); the
# kernel's VM is a subset with another code-word layout and no pl-vmi.def, so the constant is the value the PINNED swipl
# (18168e62, 10.1.20) answers as the current signature (`'$qlf_versions'/6`): the info predicates read a file written by
# that swipl. Nothing reads a code word (`'$qlf_load'` is refused). QLF1 question Q1, answered (a) by default.
"The VM signature a QLF file must carry to be compatible, as an unsigned 32-bit integer (pin 18168e62: 0xe5ee110c)."
const VM_SIGNATURE = 0xe5ee110c

# PORT: pl-qlf.c qlf_state
# DIVERGES: the directories and the translated paths are `String`s (upstream: `store_string` copies and a linked list of
# `path_translated` holding atoms; the list is a `Vector` of (from, to) pairs, the newest last).
"The path translation of one QLF file being read: where it was saved, where it is loaded from, the paths rewritten (pl-qlf.c)."
mutable struct qlf_state
    save_dir::String
    load_dir::String
    has_moved::Bool
    translated::Vector{Tuple{String, String}}
    previous::Union{Nothing, qlf_state}
end

# (pl-qlf.c:199-213)
# PORT: pl-qlf.c XR_REF
"The codes of the XR (cross reference) entries a QLF file holds: a reference, `[]`, the list functor's name, an atom, a functor, ... (pl-qlf.c)."
const XR_REF = 0
# PORT: pl-qlf.c XR_NIL
const XR_NIL = 1
# PORT: pl-qlf.c XR_CONS
const XR_CONS = 2
# PORT: pl-qlf.c XR_ATOM
const XR_ATOM = 3
# PORT: pl-qlf.c XR_FUNCTOR
const XR_FUNCTOR = 4
# PORT: pl-qlf.c XR_PRED
const XR_PRED = 5
# PORT: pl-qlf.c XR_INT
const XR_INT = 6
# PORT: pl-qlf.c XR_FLOAT
const XR_FLOAT = 7
# PORT: pl-qlf.c XR_STRING
const XR_STRING = 8
# PORT: pl-qlf.c XR_FILE
const XR_FILE = 9
# PORT: pl-qlf.c XR_MODULE
const XR_MODULE = 10
# PORT: pl-qlf.c XR_BLOB
const XR_BLOB = 11
# PORT: pl-qlf.c XR_BLOB_TYPE
const XR_BLOB_TYPE = 12
# PORT: pl-qlf.c XR_STRING_UTF8
const XR_STRING_UTF8 = 13
# PORT: pl-qlf.c XR_NULL
const XR_NULL = 14

# ORIGINAL: upstream's XR value is a `word` (an atom, a functor, a pointer to a module, a procedure, a source file or a blob type, a
# tagged integer, a float or a string on the global stack). The kernel's XR value is one of these records, each `T` the term
# type's atom; the table holds them as they are read, nothing is created in the database (see `loadXRc`).
"What one XR entry of a QLF file stands for: an atom, a functor, a module, a procedure, a blob type, a number, a string, a source file or NULL."
abstract type xr_entry{T} end
"An XR atom (also `[]` and the list functor's name)."
struct xr_atom{T} <: xr_entry{T}
    atom::T
end
"An XR functor: its name and arity."
struct xr_functor{T} <: xr_entry{T}
    name::T
    arity::Int
end
"An XR module: its name."
struct xr_module{T} <: xr_entry{T}
    name::T
end
"An XR procedure: its functor and module."
struct xr_pred{T} <: xr_entry{T}
    functor::xr_functor{T}
    module_::xr_module{T}
end
"An XR blob type: the type's name."
struct xr_blobtype{T} <: xr_entry{T}
    name::Symbol
end
"An XR integer."
struct xr_int{T} <: xr_entry{T}
    value::Int64
end
"An XR float."
struct xr_float{T} <: xr_entry{T}
    value::Float64
end
"An XR string (the text of the Prolog string)."
struct xr_string{T} <: xr_entry{T}
    value::String
end
"An XR source file: the (translated) name, the time and the two flags."
struct xr_file{T} <: xr_entry{T}
    name::T
    time::Float64
    system::Bool
    isfile::Bool
end
"The XR NULL (`XR_NULL`, and the `-` of `XR_FILE`)."
struct xr_null{T} <: xr_entry{T} end

# PORT: pl-qlf.c XrTable
# DIVERGES: upstream's table is a dynamic array of doubling blocks (`INIT_DYN_ARRAY`) indexed by `MSB(id)`; here one `Vector`
# indexed by the id (`nothing` for an id not stored yet, `Vector{Any}` since the table does not know the term type); `id` is
# the last id handed out (upstream `t->id`); `previous` is the table below on the stack.
"The XR table of one QLF module being read: the entries by id (pl-qlf.c `XrTable`)."
mutable struct XrTable
    id::Int
    entries::Vector{Any}
    previous::Union{Nothing, XrTable}
end

# PORT: pl-qlf.c wic_state
# DIVERGES: only the fields the info predicates read: the file name (`wicFile`), the stream (`wicFd`), the version
# the file was saved with (`saved_version`), the path translation (`load_state`) and the XR table (`XR`); the write side's fields are
# `ld.qlf_write_state`'s (always `nothing`, LD2).
"The state `qlfInfo` and `qlfIsCompatible` carry while a QLF file is read (pl-qlf.c `wic_state`)."
mutable struct wic_state
    wicFile::String
    wicFd::Union{Nothing, IOSTREAM}
    saved_version::Int
    load_state::Union{Nothing, qlf_state}
    XR::Union{Nothing, XrTable}
end
wic_state(file::String) = wic_state(file, nothing, 0, nothing, nothing)

# PORT: pl-qlf.c Qgetc
# (pl-qlf.c:62-68; the non-O_DEBUG branch: `Snpgetc`, no position recording)
@inline Qgetc(s::IOSTREAM)::Int = Snpgetc(s)

# PORT: pl-qlf.c zigzag_decode
# (pl-qlf.c:597-600)
"The signed integer the zig-zag encoded `n` stands for (pl-qlf.c)."
@inline zigzag_decode(n::UInt64)::Int64 =
    reinterpret(Int64, (n >> 1) ⊻ (UInt64(0) - (n & 0x1)))

# PORT: pl-qlf.c qlfGetInt64
# (pl-qlf.c:602-630)
# DIVERGES: a shift of 64 or more bits gives 0 in Julia (C: undefined); the debug output is dropped. An EOF (-1) has the
# 0x80 bit and the low bits 0x7f, as in C.
"A zig-zag, 7-bits-per-byte (little end first, the last byte has bit 0x80 set) integer from `s` (pl-qlf.c)."
function qlfGetInt64(s::IOSTREAM)::Int64
    c = Qgetc(s)

    if (c & 0x80) != 0
        return zigzag_decode(UInt64(c & 0x7f))
    else
        v = UInt64(c & 0x7f)
        shift = 7

        while true
            c = Qgetc(s)

            if (c & 0x80) != 0
                l = UInt64(c & 0x7f)
                v |= l << shift
                return zigzag_decode(v)
            else
                b = UInt64(c)
                v |= b << shift
                shift += 7
            end
        end
    end
end

# PORT: pl-qlf.c qlfGetInt32
# (pl-qlf.c:632-637)
"`qlfGetInt64` as a C `int`: the low 32 bits, signed (pl-qlf.c)."
qlfGetInt32(s::IOSTREAM)::Int32 = qlfGetInt64(s) % Int32

# PORT: pl-qlf.c qlfGet4BytesInt
# (pl-qlf.c:696-706)
"A big-endian four byte integer, as C's `int` (the QLF file's index entries, written by `PutInt32()`) (pl-qlf.c)."
function qlfGet4BytesInt(s::IOSTREAM)::Int32
    v = (Sgetc(s) & 0xff) << 24
    v |= (Sgetc(s) & 0xff) << 16
    v |= (Sgetc(s) & 0xff) << 8
    v |= (Sgetc(s) & 0xff)
    return v % Int32                                        # `int v`: the low 32 bits
end

# PORT: pl-qlf.c qlfGetString
# (pl-qlf.c:446-488)
# DIVERGES: only the `length == NULL` form (a file name: at most `PATH_MAX` bytes), returned as a `String` of the bytes
# (upstream: `LD->qlf.getstr_buffer`, and `NULL` when too long); the other form (a saved term's string, bounded by
# `globalStackLimit()`) belongs to the XR reader, NOT PORTED. `fatalError` (an EOF inside the string) is a Julia `error`.
"Read a length (`qlfGetInt64`) and that many bytes from `s`; `nothing` if the length is above `PATH_MAX` (pl-qlf.c)."
function qlfGetString(s::IOSTREAM)::Union{Nothing, String}
    len = qlfGetInt64(s)                                    # (size_t)qlfGetInt64(fd)
    (len < 0 || len > PATH_MAX) && return nothing           # a negative length is huge as a size_t

    buf = Vector{UInt8}(undef, len)
    for i in 1:len
        c = Qgetc(s)
        c == EOF && error("Unexpected EOF on QLF file at offset $(Stell64(s))")     # fatalError
        buf[i] = c % UInt8                                  # (char)c
    end

    return String(buf)
end

# PORT: pl-qlf.c getMagicString
# (pl-qlf.c:573-588)
# DIVERGES: returns the string up to the NUL (a `String` of the bytes), or `nothing` at EOF or when no NUL comes within
# `maxlen` bytes (upstream: a buffer and `NULL`).
"Read the NUL terminated magic string of at most `maxlen` bytes (NUL included) from `s`; `nothing` if there is none (pl-qlf.c)."
function getMagicString(s::IOSTREAM, maxlen::Int)::Union{Nothing, String}
    buf = UInt8[]

    while (maxlen -= 1) >= 0
        c = Sgetc(s)
        b = UInt8(c & 0xff)                                 # *s = (char)c
        b == 0x00 && break
        c == EOF && return nothing
        push!(buf, b)
    end

    maxlen > 0 && return String(buf)
    return nothing
end

# PORT: pl-qlf.c qlfError
# (pl-qlf.c:3329-3355)
# DIVERGES: the message is formatted by the caller; the file atom is the file name's text.
"Raise `error(qlf_format_error(File, Message), _)`, `File` the state's file; false (pl-qlf.c)."
function qlfError(ld::PL_local_data{T}, state::wic_state, message::String)::Bool where {T}
    file = isempty(state.wicFile) ? "<unknown>" : state.wicFile
    fn = _err_atom(ld, mk_sym(T, Symbol(file)))
    msg = _err_atom(ld, mk_sym(T, Symbol(message)))
    qf = _message_term(ld, :qlf_format_error, fn, msg)
    ex = new_term_ref(ld)
    PL_cons_functor(ld, ex, _err_functor(ld, :error, 2), qf, new_term_ref(ld))
    return PL_raise_exception(ld, ex)
end

# PORT: pl-qlf.c qlfVersion
# (pl-qlf.c:3802-3816)
# DIVERGES: returns the file's version, or `nothing` after raising the `qlf_format_error` (upstream: a Bool and `*vp`).
"Verify the magic string and read the file version (pl-qlf.c)."
function qlfVersion(
    ld::PL_local_data{T}, state::wic_state, exp_magic::String
)::Union{Nothing, Int} where {T}
    s = state.wicFd::IOSTREAM
    magic = getMagicString(s, 100)                          # char mbuf[100]

    if magic === nothing || magic != exp_magic
        qlfError(ld, state, "Not a $exp_magic")
        return nothing
    end

    return Int(qlfGetInt32(s))
end

# PORT: pl-qlf.c qlfIsCompatible
# (pl-qlf.c:3914-3932)
"Verify the version and VM signature of a QLF file whose magic is `magic`; else raise `qlf_format_error` (pl-qlf.c)."
function qlfIsCompatible(
    ld::PL_local_data{T}, state::wic_state, magic::String
)::Bool where {T}
    lversion = qlfVersion(ld, state, magic)
    lversion === nothing && return false
    if lversion < PL_QLF_LOADVERSION
        return qlfError(
            ld, state, "incompatible version (file: $lversion, Prolog: $PL_QLF_VERSION)"
        )
    end
    state.saved_version = lversion

    vm_signature = qlfGetInt32(state.wicFd::IOSTREAM)
    if vm_signature != reinterpret(Int32, VM_SIGNATURE)     # (int)VM_SIGNATURE
        return qlfError(
            ld,
            state,
            "incompatible VM-signature (file: 0x$(string(reinterpret(UInt32, vm_signature); base=16)); " *
            "Prolog: 0x$(string(VM_SIGNATURE; base=16)))"
        )
    end

    return true
end

# PORT: pl-qlf.c open_qlf_file
# (pl-qlf.c:3498-3530)
# DIVERGES: returns the stream, or `nothing` after raising the file error (upstream: a Bool and `*sp`); an IRI
# (`file_name_is_iri`) calls `iri_hook(file, IRI_OPEN, ATOM_read, 0, &s)`, which is NOT PORTED (LB4: init.pl's `$iri`
# hook) and raises `NotPortedError`.
"Open the QLF file `file` for reading in binary, without position recording (pl-qlf.c)."
function open_qlf_file(
    ld::PL_local_data{T}, file::String
)::Union{Nothing, IOSTREAM} where {T}
    if file_name_is_iri(file) != 0
        _iri_hook_refused(ld, file, "IRI_OPEN")
    end
    s, errno = Sopen_file(file, "rbr")
    s !== nothing && return s
    f = new_term_ref(ld)
    PL_put_atom(ld, f, mk_sym(T, Symbol(file)))
    PL_error(
        ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :open), mk_sym(T, :source_sink),
        f, errno
    )
    return nothing
end

# PORT: pl-qlf.c PATH_ISDIR
# (pl-qlf.c:424)
"`pushPathTranslation` flag: the load name is a directory, not a file."
const PATH_ISDIR = 0x1

# PORT: pl-qlf.c pushPathTranslation
# (pl-qlf.c:3818-3869)
# DIVERGES: the load name is never NULL (the one caller that passes NULL, the state loader's, is not ported); the strings
# are `Vector{UInt8}`s cut at the end of the common tail as the C buffers are; `PL_representation_error("max_path_length")`
# is `PL_error(ERR_REPRESENTATION, max_path_length)`; `store_string` is a plain copy.
"Read the path the QLF file was saved from and push the translation to the directory it is loaded from, if it moved (pl-qlf.c)."
function pushPathTranslation(
    ld::PL_local_data{T}, state::wic_state, absloadname::String, flags::Int
)::Bool where {T}
    new = qlf_state("", "", false, Tuple{String, String}[], state.load_state)
    state.load_state = new

    abssavename = qlfGetString(state.wicFd::IOSTREAM)
    abssavename === nothing && return qlfError(ld, state, "bad string")

    if absloadname != abssavename
        if ncodeunits(abssavename) + 1 > PATH_MAX || ncodeunits(absloadname) + 1 > PATH_MAX
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
        end

        new.has_moved = true

        if (flags & PATH_ISDIR) != 0
            l = Vector{UInt8}(codeunits(absloadname))
            s = Vector{UInt8}(codeunits(abssavename))
        else
            dl = DirName(absloadname)
            ds = DirName(abssavename)
            if dl === nothing || ds === nothing
                return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
            end
            l = Vector{UInt8}(codeunits(dl))
            s = Vector{UInt8}(codeunits(ds))
        end
        le = length(l)
        se = length(s)
        while le > 0 && se > 0 && l[le] == s[se]            # le[-1] == se[-1]
            if l[le] == UInt8('/')
                resize!(l, le)                              # *le = EOS
                resize!(s, se)                              # *se = EOS
            end
            le -= 1
            se -= 1
        end

        new.load_dir = String(l)
        new.save_dir = String(s)
    end

    return true
end

# PORT: pl-qlf.c popPathTranslation
# (pl-qlf.c:3871-3912)
# DIVERGES: `$translated_source/2` is looked up as `lookupProcedure` does (upstream: `_PL_predicate` with the cached
# `GD->procedures.dtranslated_source2`); the atoms are not reference counted (`PL_unregister_atom` has nothing to do).
"Pop the path translation; tell `'\$translated_source'/2` each path that was rewritten, newest first (pl-qlf.c)."
function popPathTranslation(ld::PL_local_data{T}, state::wic_state)::Nothing where {T}
    old = state.load_state
    old === nothing && return nothing
    state.load_state = old.previous

    if old.has_moved && !isempty(old.translated)
        gd = _query_gd(ld)
        fid = PL_open_foreign_frame(ld)
        av = PL_new_term_refs(ld, 2)
        pred = lookupProcedure(
            mk_sym(T, Symbol("\$translated_source")), 2, MODULE_system(gd)
        )

        for (from, to) in Iterators.reverse(old.translated)
            PL_put_atom(ld, av, mk_sym(T, Symbol(from)))
            PL_put_atom(ld, av + 1, mk_sym(T, Symbol(to)))

            if !PL_call_predicate(gd, ld, nothing, PL_Q_NORMAL, pred, av)
                _qlf_Sdprintf!(ld, "\$translated_source/2 failed~n")
            end
        end

        PL_discard_foreign_frame(ld, fid)
    end

    return nothing
end

# PORT: pl-qlf.c qlfFixSourcePath
# (pl-qlf.c:1782-1835)
# DIVERGES: returns the canonical path as a `String` (upstream: its atom); `fatalError` is a Julia `error`.
"The path `raw` as read from the QLF file, moved to where the file is loaded from and canonicalised; a rewrite is recorded (pl-qlf.c)."
function qlfFixSourcePath(
    ld::PL_local_data{T}, state::wic_state, raw::String
)::String where {T}
    ls = state.load_state::qlf_state

    if ls.has_moved && startswith(raw, ls.save_dir)
        tail = String(Vector{UInt8}(codeunits(raw))[(ncodeunits(ls.save_dir) + 1):end])

        if ncodeunits(ls.load_dir) + 1 + ncodeunits(tail) + 1 > PATH_MAX
            error("Path name too long: $raw")               # fatalError
        end
        buf = ls.load_dir * tail
    else
        if ncodeunits(raw) + 1 > PATH_MAX
            error("Path name too long: $raw")               # fatalError
        end
        buf = raw
    end

    canonical = canonicalisePath(ld, buf)
    canonical === nothing && error("Path name too long: $buf")      # fatalError

    if raw != canonical
        push!(ls.translated, (raw, canonical))
    end

    return canonical
end

# PORT: pl-qlf.c loadFileName
# (pl-qlf.c:1837-1853)
# DIVERGES: returns the path as a `String`; `fatalError` is a Julia `error`; the debug output is dropped.
"Read a source file name from the QLF file and translate it (pl-qlf.c)."
function loadFileName(ld::PL_local_data{T}, state::wic_state)::String where {T}
    str = qlfGetString(state.wicFd::IOSTREAM)
    str === nothing && error("Invalid QLF: illegal string")        # fatalError
    return qlfFixSourcePath(ld, state, str)
end

# PORT: pl-qlf.c qlfLoadFileHash
# (pl-qlf.c:1927-1933)
"The content hash of a source file, which follows its name in the QLF file since version 72; else 0 (pl-qlf.c)."
function qlfLoadFileHash(state::wic_state)::UInt64
    if state.saved_version >= 72
        return reinterpret(UInt64, qlfGetInt64(state.wicFd::IOSTREAM))
    end

    return UInt64(0)
end

# PORT: pl-qlf.c qlfSourceInfo
# (pl-qlf.c:3360-3395)
# DIVERGES: the functor is made from its name (`_err_functor`); `OsError()` is `strerror` of the stream's `io_errno`.
"Read the source entry at `offset` and add `source(File, Hash)`, `include(File, Hash)` or `dependency(File, Hash)` to the open list `list` (pl-qlf.c)."
function qlfSourceInfo(
    ld::PL_local_data{T}, state::wic_state, offset::Int, list::term_t
)::Bool where {T}
    s = state.wicFd::IOSTREAM
    head = PL_new_term_ref(ld)
    tmp = PL_new_term_ref(ld)

    if Sseek64(s, Int64(offset), SIO_SEEK_SET) != 0
        return qlfError(
            ld, state, "seek to $offset failed: " * Base.Libc.strerror(s.io_errno)
        )
    end
    c = Sgetc(s)
    if c == Int('F')
        type = :source
    elseif c == Int('L')
        type = :include
    elseif c == Int('D')
        type = :dependency
    else
        return qlfError(ld, state, "No file at offset $offset")
    end
    fname = loadFileName(ld, state)             # the hash follows the name in
    hash = qlfLoadFileHash(state)               # every one of the three

    av = PL_new_term_refs(ld, 2)
    rc = (
        PL_put_atom(ld, av, mk_sym(T, Symbol(fname))) &&
        PL_put_uint64(ld, av + 1, hash) &&
        PL_cons_functor_v(ld, tmp, _err_functor(ld, type, 2), av) &&
        PL_unify_list(ld, list, head, list) &&
        PL_unify(ld, head, tmp)
    )
    PL_reset_term_refs(ld, head)
    return rc
end

# ── the XR reader and the module record (pl-qlf.c:349-425, 436-488, 640-905, 1926-1960, 2156-2225, 3399-3497) ──

# PORT: pl-qlf.c pushXrIdTable
"Push a new, empty XR table on the state (pl-qlf.c)."
function pushXrIdTable(state::wic_state)::Nothing
    state.XR = XrTable(0, Any[], state.XR)
    return nothing
end

# PORT: pl-qlf.c popXrIdTable
# DIVERGES: nothing to release (upstream unregisters the atoms the entries hold and frees the blocks).
"Pop the XR table from the state (pl-qlf.c)."
function popXrIdTable(state::wic_state)::Nothing
    t = state.XR::XrTable
    state.XR = t.previous
    return nothing
end

# PORT: pl-qlf.c lookupXrId
# DIVERGES: an id that was never stored (upstream reads an unallocated block or a cell never written) is a format error.
"The XR entry stored under `id` in the current table (pl-qlf.c)."
function lookupXrId(::Type{T}, state::wic_state, id::Int)::xr_entry{T} where {T}
    t = state.XR::XrTable
    if id < 1 || id > length(t.entries) || t.entries[id] === nothing
        qlfLoadError(state)
    end
    return t.entries[id]::xr_entry{T}
end

# PORT: pl-qlf.c storeXrId
"Store the XR entry `value` under `id` in the current table (pl-qlf.c)."
function storeXrId(state::wic_state, id::Int, value::xr_entry)::Nothing
    t = state.XR::XrTable
    id > length(t.entries) && append!(t.entries, fill(nothing, id - length(t.entries)))
    t.entries[id] = value
    return nothing
end

# PORT: pl-qlf.c qlfLoadError_ctx
# DIVERGES: `fatalError` is a Julia `error`; the message has no source file and line of the C (the position is the stream's),
# so `file` and `line` are taken and not printed.
"Raise the format error of a QLF file at the current position (pl-qlf.c `qlfLoadError_ctx`: `fatalError`)."
function qlfLoadError_ctx(state::wic_state, file::String, line::Int)::Union{}
    pos = state.wicFd === nothing ? 0 : Stell64(state.wicFd)
    error("$(state.wicFile): QLF format error at index = $pos")
end

# ORIGINAL: pl-qlf.c's macro `qlfLoadError(state)` (`qlfLoadError_ctx(state, __FILE__, __LINE__)`), a function here: the C
# call site's file and line are not carried (see `qlfLoadError_ctx`).
"Raise the format error of a QLF file at the current position (pl-qlf.c `qlfLoadError`)."
qlfLoadError(state::wic_state)::Union{} = qlfLoadError_ctx(state, "", 0)

# PORT: pl-qlf.c qlfGetUInt32
# DIVERGES: a shift of 32 or more bits gives 0 in Julia (C: undefined); an EOF (-1) is a last byte of 0x7f, as C's `unsigned int`.
"An unsigned integer, 7 bits per byte (little end first, the last byte has bit 0x80 set) from `s` (pl-qlf.c)."
function qlfGetUInt32(s::IOSTREAM)::UInt32
    c = Qgetc(s) % UInt32

    if (c & 0x80) != 0
        return c & 0x7f
    else
        v = c & 0x7f
        shift = 7

        while true
            c = Qgetc(s) % UInt32

            if (c & 0x80) != 0
                l = c & 0x7f
                v |= l << shift
                return v
            else
                v |= c << shift
                shift += 7
            end
        end
    end
end

# PORT: pl-qlf.c qlfGetDouble
# (the little endian `double_byte_order`)
# DIVERGES: `fatalError` is a Julia `error`; the debug output is dropped.
"A double of eight bytes, the least significant first (pl-qlf.c)."
function qlfGetDouble(s::IOSTREAM)::Float64
    bits = UInt64(0)

    for i in 0:7
        c = Qgetc(s)
        c == EOF && error("Unexpected end-of-file in QLT file")
        bits |= UInt64(c & 0xff) << (8 * i)
    end

    return reinterpret(Float64, bits)
end

# PORT: pl-qlf.c qlfGetString
# (the `length != NULL` form, pl-qlf.c:446-488)
# DIVERGES: returns the bytes read (upstream: `LD->qlf.getstr_buffer` and the length), `nothing` when the length is above
# `globalStackLimit()` (the stacks' limit, in bytes: `ld.stacks_limit` is in words); the bytes are read before a buffer of
# that size is made; `fatalError` (an EOF inside the string) is a Julia `error`.
"Read a length (`qlfGetInt64`) and that many bytes from `s`, a saved term's string; `nothing` if the length is above the global stack limit (pl-qlf.c)."
function qlfGetString(
    ld::PL_local_data{T}, s::IOSTREAM
)::Union{Nothing, Vector{UInt8}} where {T}
    len = qlfGetInt64(s)                                    # (size_t)qlfGetInt64(fd)
    (len < 0 || len > Int(ld.stacks_limit) * 8) && return nothing   # length > globalStackLimit()

    buf = UInt8[]
    for _ in 1:len
        c = Qgetc(s)
        c == EOF && error("Unexpected EOF on QLF file at offset $(Stell64(s))")     # fatalError
        push!(buf, c % UInt8)                               # (char)c
    end

    return buf
end

# PORT: pl-qlf.c qlfGetStringW
# DIVERGES: returns a `String` of the code points (upstream: a buffer of `wchar_t`); `fatalError` is a Julia `error`; a
# length that is negative as an integer reads until the EOF (as a huge `size_t`); a code point that is no character
# (a surrogate, or above 0x10ffff) is an error here (upstream keeps it in the `wchar_t` buffer).
"Read a length and that many UTF-8 encoded code points from `s`, as `PL_qlf_putStringW` wrote them (pl-qlf.c)."
function qlfGetStringW(s::IOSTREAM)::String
    len = qlfGetInt64(s)
    oenc = s.encoding
    s.encoding = ENC_UTF8
    out = Char[]

    try
        i = 0
        while len < 0 || i < len
            c = Sgetcode(s)
            c < 0 && error("Unexpected EOF in UCS atom")
            isvalid(Char, c % UInt32) || error("Illegal code point $c in UCS atom")
            push!(out, Char(c % UInt32))
            i += 1
        end
    finally
        s.encoding = oenc
    end

    return String(out)
end

# PORT: pl-qlf.c getAtom
# DIVERGES: the text is the bytes read as ISO Latin-1 (what `lookupAtom` makes of them), a blob type is its name (`:text` or
# `:reserved_symbol`: the two blob types read from bytes here) where upstream passes the type; an atom holding NUL
# stays refused (`AtomNotRepresentableError`); `fatalError` is a Julia `error`.
"Read the length and bytes of an atom of the blob type `type` from `s` (pl-qlf.c)."
function getAtom(::Type{T}, s::IOSTREAM, type::Symbol)::T where {T}
    len = qlfGetInt64(s)                                    # (size_t)qlfGetInt64(fd)
    buf = UInt8[]

    for _ in 1:len
        c = Qgetc(s)
        c == EOF &&
            error("Unexpected EOF on intermediate code file at offset $(Stell64(s))")
        push!(buf, c % UInt8)
    end
    any(==(0x00), buf) && throw(AtomNotRepresentableError(UInt32[UInt32(b) for b in buf]))
    text = String(Char[Char(b) for b in buf])               # ISO Latin-1

    return if type === :reserved_symbol
        mk_reserved_symbol(T, Symbol(text))
    else
        mk_sym(T, Symbol(text))
    end
end

# PORT: pl-qlf.c getBlobType
# DIVERGES: the types a QLF file of the kernel's atoms holds are `text`, `ucs_text` and `reserved_symbol`; any other type
# is a named refusal (upstream: `PL_find_blob_type`, a type of a registered blob, not found is a NULL its caller uses).
"Read the name of an XR blob type from `s`: its entry (pl-qlf.c)."
function getBlobType(::Type{T}, s::IOSTREAM)::xr_blobtype{T} where {T}
    bytes = qlfGetString(s)
    bytes === nothing && error("Invalid blob type in QLF")                 # fatalError
    name = bytes
    if !(name in ("text", "ucs_text", "reserved_symbol"))
        throw(
            NotPortedError{T}(
                mk_sym(T, Symbol(name)), "the QLF blob type $name", "QLF3: refused by name"
            )
        )
    end

    return xr_blobtype{T}(Symbol(name))
end

# PORT: pl-qlf.c getBlob
# DIVERGES: the load function of the type (`type->load`) is `loadUCSAtom` for `ucs_text` only: a wide text atom is a text atom
# of its characters here; the other types are read by `getAtom`.
"Read a blob (an atom of a type other than plain text): its type first, then its data (pl-qlf.c)."
function getBlob(
    ld::PL_local_data{T}, state::wic_state
)::Union{Nothing, xr_entry{T}} where {T}
    tx = loadXR(ld, state)
    tx === nothing && return nothing
    tx isa xr_blobtype || qlfLoadError(state)
    fd = state.wicFd::IOSTREAM

    if tx.name === :ucs_text
        return xr_atom{T}(mk_sym(T, Symbol(qlfGetStringW(fd))))      # loadUCSAtom
    end

    return xr_atom{T}(getAtom(T, fd, tx.name))
end

# ORIGINAL: `word2atom(loadXR(state))`: the atom an XR entry is; upstream reads the word as an atom whatever it is, here an
# entry that is no atom is a format error (and a `nothing`, a failure with a pending exception, is told to the caller).
"The atom XR entry `x` stands for; a format error if it is no atom."
function _xr_atom(state::wic_state, x::xr_entry{T})::T where {T}
    x isa xr_atom || qlfLoadError(state)
    return x.atom
end

# PORT: pl-qlf.c loadXR
"Read one XR entry from the QLF file: its code, then the entry (pl-qlf.c)."
loadXR(ld::PL_local_data{T}, state::wic_state) where {T} =
    loadXRc(ld, state, Qgetc(state.wicFd::IOSTREAM))

# PORT: pl-qlf.c loadXRc
# DIVERGES: nothing is created in the database for the entries that make a module, a procedure or a source file (upstream:
# `lookupModule`, `lookupProcedure`, `lookupSourceFile` and its count): the entry holds the names; the numbers and strings are
# values (no global stack word); a failure (a string above the stack limit: the overflow is raised) is `nothing`, where upstream
# returns the word 0 (which `XR_NULL` also is: `xr_null`); an id never stored, an arity below 0, an entry that is not what its
# position needs and an unknown code are format errors (upstream reads what is there).
"Load the XR entry `c` (its code, already read) from the QLF file; `nothing` after a raised exception (pl-qlf.c)."
function loadXRc(
    ld::PL_local_data{T}, state::wic_state, c::Int
)::Union{Nothing, xr_entry{T}} where {T}
    fd = state.wicFd::IOSTREAM
    t = state.XR::XrTable
    id = 0
    xr::xr_entry{T} = xr_null{T}()

    if c == XR_REF
        return lookupXrId(T, state, Int(qlfGetUInt32(fd)))
    elseif c == XR_NIL
        return xr_atom{T}(mk_nil(T))
    elseif c == XR_CONS
        return xr_atom{T}(mk_sym(T, Symbol("[|]")))             # ATOM_dot
    elseif c == XR_ATOM
        id = (t.id += 1)
        xr = xr_atom{T}(getAtom(T, fd, :text))
    elseif c == XR_BLOB
        id = (t.id += 1)
        b = getBlob(ld, state)
        b === nothing && return nothing
        xr = b
    elseif c == XR_BLOB_TYPE
        id = (t.id += 1)
        xr = getBlobType(T, fd)
    elseif c == XR_FUNCTOR
        id = (t.id += 1)
        nx = loadXR(ld, state)
        nx === nothing && return nothing
        name = _xr_atom(state, nx)
        arity = qlfGetInt64(fd)
        arity < 0 && qlfLoadError(state)
        xr = xr_functor{T}(name, Int(arity))
    elseif c == XR_PRED
        id = (t.id += 1)
        fx = loadXR(ld, state)
        fx === nothing && return nothing
        mx = loadXR(ld, state)
        mx === nothing && return nothing
        (fx isa xr_functor && mx isa xr_module) || qlfLoadError(state)
        xr = xr_pred{T}(fx, mx)
    elseif c == XR_MODULE
        id = (t.id += 1)
        nx = loadXR(ld, state)
        nx === nothing && return nothing
        xr = xr_module{T}(_xr_atom(state, nx))
    elseif c == XR_INT
        return xr_int{T}(qlfGetInt64(fd))
    elseif c == XR_FLOAT
        return xr_float{T}(qlfGetDouble(fd))
    elseif c == XR_STRING
        bytes = qlfGetString(ld, fd)
        if bytes === nothing
            raiseStackOverflow(ld, GLOBAL_OVERFLOW)
            return nothing
        end
        return xr_string{T}(String(bytes))
    elseif c == XR_STRING_UTF8
        return xr_string{T}(qlfGetStringW(fd))
    elseif c == XR_FILE
        id = (t.id += 1)
        f = Qgetc(fd)

        if f == Int('u') || f == Int('s') || f == Int('U') || f == Int('S')
            nx = loadXR(ld, state)
            nx === nothing && return nothing
            name = _xr_atom(state, nx)
            time = qlfGetDouble(fd)
            fixed = qlfFixSourcePath(ld, state, sym_text(name))
            xr = xr_file{T}(
                mk_sym(T, Symbol(fixed)), time, f == Int('s') || f == Int('S'),
                f == Int('s') || f == Int('u')
            )
        elseif f == Int('-')
            xr = xr_null{T}()
        else
            error("Illegal XR file index $(Stell64(fd) - 1): $(Char(f % UInt8))")     # fatalError
        end
    elseif c == XR_NULL
        return xr_null{T}()
    else
        error("Illegal XR entry at index $(Stell64(fd) - 1): $c")                    # fatalError
    end

    storeXrId(state, id, xr)
    return xr
end

# PORT: pl-qlf.c qlfLoadSource
# DIVERGES: returns `(name, mtime, system, isfile)` (upstream fills a `struct sourceFile`), the name as a `String`.
"Read a source file entry (name, hash, time, type) and return what it holds (pl-qlf.c)."
function qlfLoadSource(
    ld::PL_local_data{T}, state::wic_state
)::Tuple{String, Float64, Bool, Bool} where {T}
    fd = state.wicFd::IOSTREAM
    fname = loadFileName(ld, state)
    qlfLoadFileHash(state)
    time = qlfGetDouble(fd)
    ftype = Qgetc(fd)

    return (
        fname,
        time,
        ftype == Int('s') || ftype == Int('S'),
        ftype == Int('s') || ftype == Int('u')
    )
end

# PORT: pl-qlf.c loadInclude
# DIVERGES: only the `skip` branch (what `qlfLoadIncludes(state, true)` does: the fields are read and dropped); the other (the
# `'$included'` directive and the assert) belongs to `'$qlf_load'` (Q2a), a named refusal; no foreign frame (nothing is built).
"Read an include entry of a QLF file (file, hash, owner, parent, line, time) and drop it (pl-qlf.c)."
function loadInclude(ld::PL_local_data{T}, state::wic_state, skip::Bool)::Bool where {T}
    fd = state.wicFd::IOSTREAM
    skip || throw(
        NotPortedError{T}(
            mk_sym(T, Symbol("\$qlf_load")), "loadInclude of a loaded QLF file",
            "Q2a: refused by name"
        )
    )

    if state.saved_version >= 70
        loadFileName(ld, state)
        qlfLoadFileHash(state)
        loadFileName(ld, state)
        loadFileName(ld, state)
        qlfGetInt32(fd)
        qlfGetDouble(fd)
    else
        for _ in 1:2                                        # owner, pn
            x = loadXR(ld, state)
            x === nothing && return false
            _xr_atom(state, x)
        end
        qlfGetInt32(fd)                                     # line
        x = loadXR(ld, state)                               # fn
        x === nothing && return false
        _xr_atom(state, x)
        qlfGetDouble(fd)
    end

    return true
end

# PORT: pl-qlf.c qlfLoadIncludes
# DIVERGES: a failure of `loadInclude` (a pending exception) ends the loop.
"Read the include entries `{'L' <include>}` up to the `Q` that starts the part (pl-qlf.c)."
function qlfLoadIncludes(
    ld::PL_local_data{T}, state::wic_state, skip::Bool
)::Nothing where {T}
    fd = state.wicFd::IOSTREAM

    while true
        c = Qgetc(fd)

        if c == Int('Q')
            break
        elseif c == Int('I') || c == Int('L')               # load version 68 files
            loadInclude(ld, state, skip) || break
        else
            qlfLoadError(state)
        end
    end

    return nothing
end

# ORIGINAL: pl-qlf.c `mkeys`, a static array of atoms there; the atoms belong to the database here, so the keys are made per `ld`.
"The keys of the dict `'\$qlf_module'/2` answers: `module`, `class`, `exports`, `file` (pl-qlf.c `mkeys`), as atom words."
_qlf_mkeys(ld::PL_local_data{T}) where {T} =
    word[_atom_word!(ld, mk_sym(T, k)) for k in (:module, :class, :exports, :file)]

# PORT: pl-qlf.c qlfModuleInfo
# DIVERGES: the dict's tag is `dyndict`, written as `select_dict` does (its symbol `#` is recorded first); the export list's
# elements are `Name/Arity` built here (upstream `unify_functor(head, f, GP_NAMEARITY)` of a functor word); a failed
# `loadXR` (a pending exception) is false; a super module XR is read and dropped as upstream.
"Unify `minfo` with a dict of the module (`module`, `class`, `exports`, `file`) the QLF file defines; false if it defines none (pl-qlf.c)."
function qlfModuleInfo(
    ld::PL_local_data{T}, state::wic_state, minfo::term_t
)::Bool where {T}
    fd = state.wicFd::IOSTREAM
    qlfLoadIncludes(ld, state, true)                        # Skip {'L' <include>}

    c0 = Qgetc(fd)
    if c0 == Int('M')
        mx = loadXR(ld, state)
        mx === nothing && return false
        mname = _xr_atom(state, mx)
        c = Qgetc(fd)
        av = PL_new_term_refs(ld, 4)                        # dict keys
        exports = av + 2                                    # export list
        head = PL_new_term_ref(ld)                          # tmp for building exports
        extail = PL_copy_term_ref(ld, exports)              # tail of exports
        dlen = 3                                            # #used dict keys

        PL_unify_atom(ld, av, mname)                        # XR atoms are owned by the XR table

        # deal with the source
        if c == Int('-')
            # no source
        elseif c == Int('F')
            fname, _, _, _ = qlfLoadSource(ld, state)
            PL_unify_atom(ld, av + 3, mk_sym(T, Symbol(fname))) || return false
            dlen += 1
            qlfGetInt32(fd)                                 # line
        else
            qlfLoadError(state)
        end

        # deal with the properties
        while true
            p = Qgetc(fd)
            if p == Int('C')                                # module class
                cx = loadXR(ld, state)
                cx === nothing && return false
                PL_unify_atom(ld, av + 1, _xr_atom(state, cx)) || return false
            elseif p == Int('S')                            # super
                loadXR(ld, state)
            elseif p == Int('E')
                fx = loadXR(ld, state)
                fx === nothing && return false
                fx isa xr_functor || qlfLoadError(state)
                (
                    PL_unify_list(ld, extail, head, extail) &&
                    PL_unify_functor(ld, head, mk_sym(T, :/), 2)
                ) || return false
                a = PL_new_term_ref(ld)
                (
                    _PL_get_arg(ld, 1, head, a) && PL_unify_atom(ld, a, fx.name) &&
                    _PL_get_arg(ld, 2, head, a) && PL_unify_integer(ld, a, fx.arity)
                ) || return false
            elseif p == Int('X')
                break
            else
                qlfLoadError(state)
            end
        end
        PL_unify_nil(ld, extail) || return false

        _atom_word!(ld, mk_sym(T, Symbol("#")))             # records the symbol of `dyndict` (text `#`) for readers
        rc =
            PL_put_dict(ld, head, ATOM_dyndict, dlen, _qlf_mkeys(ld), av) &&
            PL_unify(ld, minfo, head)
        PL_reset_term_refs(ld, av)
        return rc
    elseif c0 == Int('F')
        return false
    else
        qlfLoadError(state)
    end
end

# PORT: pl-qlf.c Q_VERSION
# (pl-qlf.c:3532)
"`qlfInfo` flag: unify the version information (`'\$qlf_versions'/6`) instead of checking compatibility."
const Q_VERSION = 0x01

# ORIGINAL: not upstream's (a flag for whether `files0` was passed): upstream tests the term reference for 0; a term
# reference 0 is valid here, so the caller of `'\$qlf_sources'/2` sets this flag.
"`qlfInfo` flag: unify the list of the source files recorded in the file (`'\$qlf_sources'/2`)."
const Q_FILES = 0x02

# ORIGINAL: not upstream's (a flag for whether `minfo` was passed): upstream tests the term reference for 0.
"`qlfInfo` flag: unify the module information (`'\$qlf_module'/2`)."
const Q_MODULE = 0x04

# ORIGINAL: the `files0` block of pl-qlf.c `qlfInfo` (pl-qlf.c:3532-3631, 3587-3623), split out of it.
# DIVERGES: `Sseek` is `Sseek64`; the `qlfstart` array is a `Vector{Int}`; `(size_t)` of a negative
# index entry and the `(long)` of it again give the same negative offset, which `Sseek64` refuses; the `-4 * (nqlf + 1)` is
# `Int64` (a C `int` overflows). `OsError()` is `strerror` of the stream's `io_errno`.
"The sources of the QLF file: read the index at its end and add each `source/2`, `include/2`, `dependency/2` to `files0`, a list (pl-qlf.c)."
function qlfFilesInfo(
    ld::PL_local_data{T}, state::wic_state, files0::term_t
)::Bool where {T}
    s = state.wicFd::IOSTREAM

    files = PL_copy_term_ref(ld, files0)

    if Sseek64(s, Int64(-4), SIO_SEEK_END) < 0                  # 4 bytes of PutInt32()
        return qlfError(
            ld, state, "seek to index failed: " * Base.Libc.strerror(s.io_errno)
        )
    end
    nqlf = qlfGet4BytesInt(s)
    if nqlf < 0
        return qlfError(ld, state, "invalid number of files ($nqlf)")
    end
    if Sseek64(s, Int64(-4) * (Int64(nqlf) + 1), SIO_SEEK_END) < 0
        return qlfError(
            ld, state, "seek to files failed: " * Base.Libc.strerror(s.io_errno)
        )
    end

    qlfstart = Vector{Int}(undef, nqlf)
    for i in 1:nqlf
        qlfstart[i] = Int(qlfGet4BytesInt(s))
    end

    for i in 1:nqlf
        qlfSourceInfo(ld, state, qlfstart[i], files) || return false
    end

    return PL_unify_nil(ld, files)
end

# PORT: pl-qlf.c qlfInfo
# (pl-qlf.c:3532-3631)
# DIVERGES: the arguments are `cversion`, `minload`, `fversion`, `csig`, `fsig`, `minfo`, `files0`, then the flags `Q_VERSION`,
# `Q_FILES`, `Q_MODULE` (a term reference is 0 when not used; upstream tests it for 0, here the flags say which are passed). The
# `minfo` branch is `pushXrIdTable`, `qlfModuleInfo`, `popXrIdTable`; the `files0` block is `qlfFilesInfo`.
"Open the QLF file `file`; with `Q_VERSION` unify the version information, else check compatibility; with `Q_MODULE` unify the module information, with `Q_FILES` list its sources; close it (pl-qlf.c)."
function qlfInfo(
    ld::PL_local_data{T}, file::String, cversion::term_t, minload::term_t, fversion::term_t,
    csig::term_t, fsig::term_t, minfo::term_t, files0::term_t, flags::Int
)::Bool where {T}
    state = wic_state(file)
    s = open_qlf_file(ld, file)
    s === nothing && return false
    state.wicFd = s

    ok = false
    if (flags & Q_VERSION) != 0
        # Current system QLF versions
        if PL_unify_integer(ld, cversion, PL_QLF_VERSION) &&
            PL_unify_integer(ld, minload, PL_QLF_LOADVERSION) &&
            PL_unify_int64(ld, csig, Int(VM_SIGNATURE))     # (unsigned int)VM_SIGNATURE
            lversion = qlfVersion(ld, state, qlfMagic)
            if lversion !== nothing && PL_unify_integer(ld, fversion, lversion)
                vm_signature = qlfGetInt32(s)
                ok = PL_unify_int64(ld, fsig, Int(reinterpret(UInt32, vm_signature)))
            end
        end
    else
        ok = qlfIsCompatible(ld, state, qlfMagic)
    end

    rval = false
    if ok
        rval = true
        if (flags & (Q_MODULE | Q_FILES)) != 0                      # if ( minfo || files0 )
            rval = pushPathTranslation(ld, state, file, 0)
        end
        if rval && (flags & Q_MODULE) != 0
            pushXrIdTable(state)
            rval = qlfModuleInfo(ld, state, minfo)
            popXrIdTable(state)
        end
        if rval && (flags & Q_FILES) != 0
            rval = qlfFilesInfo(ld, state, files0)
        end
    end

    (flags & (Q_MODULE | Q_FILES)) != 0 && popPathTranslation(ld, state)   # if ( minfo || files0 )
    Sclose(s)
    return rval
end

# PORT: pl-qlf.c qlf_versions as pl_qlf_versions6_va
# (PRED_IMPL("$qlf_versions", 6, qlf_versions, 0)) — pl-qlf.c:3648-3660
"`'\$qlf_versions'(+File, -CurrentVersion, -MinLoadVersion, -FileVersion, -CurrentSignature, -FileSignature)` (pl-qlf.c); does not verify compatibility."
function pl_qlf_versions6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, Int(PL_FILE_ABSOLUTE))
    name === nothing && return FFALSE                       # !PL_get_file_name(A1, &name, PL_FILE_ABSOLUTE)
    return if qlfInfo(
        ld, name, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4, PL__t0 + 5, 0, 0,
        Int(Q_VERSION)
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-qlf.c qlf_is_compatible as pl_qlf_is_compatible1_va
# (PRED_IMPL("$qlf_is_compatible", 1, qlf_is_compatible, 0)) — pl-qlf.c:3662-3680
"`'\$qlf_is_compatible'(+File)` (pl-qlf.c): raises `qlf_format_error` if File is not compatible with this version."
function pl_qlf_is_compatible1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, Int(PL_FILE_ABSOLUTE))
    name === nothing && return FFALSE
    return qlfInfo(ld, name, 0, 0, 0, 0, 0, 0, 0, 0) ? FTRUE : FFALSE
end

# PORT: pl-qlf.c qlf_sources as pl_qlf_sources2_va
# (PRED_IMPL("$qlf_sources", 2, qlf_sources, 0)) — pl-qlf.c:3686-3695
"`'\$qlf_sources'(+File, -Files)` (pl-qlf.c): `Files` is a list of `source(File, Hash)`, `include(File, Hash)`, `dependency(File, Hash)` as the QLF file records them."
function pl_qlf_sources2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, Int(PL_FILE_ABSOLUTE))
    name === nothing && return FFALSE                       # !PL_get_file_name(A1, &name, PL_FILE_ABSOLUTE)
    return qlfInfo(ld, name, 0, 0, 0, 0, 0, 0, PL__t0 + 1, Int(Q_FILES)) ? FTRUE : FFALSE
end

# PORT: pl-qlf.c FNV1A_64_OFFSET
# (pl-qlf.c:1872)
"FNV-1a 64-bit offset basis (pl-qlf.c): the content hash of a source file."
const FNV1A_64_OFFSET = 0xcbf29ce484222325
# PORT: pl-qlf.c FNV1A_64_PRIME
# (pl-qlf.c:1873)
"FNV-1a 64-bit prime (pl-qlf.c)."
const FNV1A_64_PRIME = 0x00000100000001b3

# PORT: pl-qlf.c hashStreamContent
# (pl-qlf.c:1875-1891)
# DIVERGES: the bytes come from an `Sgetc` loop on the binary stream, where upstream reads 4096-byte blocks with
# `Sfread` (not ported); the hash is the same, FNV-1a 64 over the bytes in order.
"FNV-1a 64 of the bytes `s` yields; 0 if the stream signals an error (pl-qlf.c)."
function hashStreamContent(s::IOSTREAM)::UInt64
    hash = FNV1A_64_OFFSET
    while true
        c = Sgetc(s)
        c == EOF && break
        hash = xor(hash, UInt64(c % UInt8))                 # hash ^= (uint64_t)(unsigned char)buf[i]
        hash *= FNV1A_64_PRIME
    end
    return Sferror(s) != 0 ? UInt64(0) : hash
end

# PORT: pl-qlf.c fileContentHash
# (pl-qlf.c:1892-1904)
"The content hash of the file `name`, 0 if it cannot be opened or read (pl-qlf.c)."
function fileContentHash(name::String)::UInt64
    hash = UInt64(0)
    s, _ = Sopen_file(name, "rbr")
    if s !== nothing
        hash = hashStreamContent(s)
        Sclose(s)
    end
    return hash
end

# PORT: pl-qlf.c file_hash as pl_file_hash2_va
# (PRED_IMPL("$file_hash", 2, file_hash, 0)) — pl-qlf.c:3708-3716
"`'\$file_hash'(+File, -Hash)` (pl-qlf.c): Hash is the FNV-1a 64 hash of the content of File, 0 if it cannot be read."
function pl_file_hash2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, Int(PL_FILE_ABSOLUTE))
    name === nothing && return FFALSE                       # !PL_get_file_name(A1, &name, PL_FILE_ABSOLUTE)
    return PL_unify_uint64(ld, PL__t0 + 1, fileContentHash(name)) ? FTRUE : FFALSE
end

# PORT: pl-qlf.c qlf_module as pl_qlf_module2_va
# (PRED_IMPL("$qlf_module", 2, qlf_module, 0)) — pl-qlf.c:3710-3722
"`'\$qlf_module'(+File, -Info)` (pl-qlf.c): `Info` is a dict `#{module:, file:, class:, exports:}` read from the module record of the QLF file."
function pl_qlf_module2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, Int(PL_FILE_ABSOLUTE))
    name === nothing && return FFALSE                       # !PL_get_file_name(A1, &name, PL_FILE_ABSOLUTE)
    return qlfInfo(ld, name, 0, 0, 0, 0, 0, PL__t0 + 1, 0, Int(Q_MODULE)) ? FTRUE : FFALSE
end

# PORT: pl-qlf.c qlf_load as pl_qlf_load2_va
# (PRED_IMPL("$qlf_load", 2, qlf_load, PL_FA_TRANSPARENT)) — refused by name
function pl_qlf_load2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_load", 2)
end

# PORT: pl-qlf.c qlf_current_source as pl_qlf_current_source1_va
# (PRED_IMPL("$qlf_current_source", 1, qlf_current_source, 0)) — pl-qlf.c:4150-4162
# DIVERGES: the NULL state's branch only (QLF1): `(state=LD->qlf.write_state) && (sf = state->currentSource)` is false
# and the predicate fails; no state can exist while `$open_wic`/`$qlf_open` are refused.
"`'\$qlf_current_source'(-File)` (pl-qlf.c): the source file the state file is writing; with no state, false."
function pl_qlf_current_source1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FFALSE
end

# PORT: pl-qlf.c $qlf_dependency as pl_qlf_dependency1_va
# (PRED_IMPL("$qlf_dependency", 1, $qlf_dependency, 0)) — pl-qlf.c:4200-4217
# DIVERGES: the NULL state's branch only (QLF1): `PL_get_atom_ex(A1, &file)` raises a type error for a non-atom,
# else `(state=LD->qlf.write_state)` is NULL and the predicate fails. The writer (`sourceMark`, `'D'`,
# `qlfSaveFileName`, `qlfSaveFileHash`) is unreachable until `$open_wic`/`$qlf_open` exist.
"`'\$qlf_dependency'(+File)` (pl-qlf.c): record a dependency in the state file; with no state, false."
function pl_qlf_dependency1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    PL_get_atom_ex(ld, PL__t0) === nothing && return FFALSE        # PL_get_atom_ex(A1, &file)
    return FFALSE                                                  # (state=LD->qlf.write_state): NULL
end

# PORT: pl-qlf.c qlf_open as pl_qlf_open1_va
# (PRED_IMPL("$qlf_open", 1, qlf_open, 0)) — refused by name
function pl_qlf_open1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_open", 1)
end

# PORT: pl-qlf.c qlf_close as pl_qlf_close0_va
# (PRED_IMPL("$qlf_close", 0, qlf_close, 0)) — pl-qlf.c:4251-4259
# DIVERGES: the NULL state's branch only (QLF1): `if ( (state=LD->qlf.write_state) ) return qlfClose(state)` is not
# taken and the predicate succeeds (`qlfClose`, pl-qlf.c:3776, is unreachable without a state).
"`'\$qlf_close'` (pl-qlf.c): close the state file `'\$qlf_open'/1` opened; with no state, true."
function pl_qlf_close0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c open_wic as pl_open_wic2_va
# (PRED_IMPL("$open_wic", 2, open_wic, 0)) — refused by name
function pl_open_wic2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$open_wic", 2)
end

# PORT: pl-qlf.c close_wic as pl_close_wic0_va
# (PRED_IMPL("$close_wic", 0, close_wic, 0)) — pl-qlf.c:4361-4373
# DIVERGES: the NULL state's branch only (QLF1): the `if ( (state=LD->qlf.write_state) )` body (`writeWicTrailer`, pop,
# free) is not taken and the predicate FAILS (upstream's `return false`), unlike `'\$qlf_close'/0`.
"`'\$close_wic'` (pl-qlf.c): write the trailer of the state `'\$open_wic'/2` opened; with no state, false."
function pl_close_wic0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FFALSE
end

# PORT: pl-qlf.c map_id as pl_map_id2_va
# (PRED_IMPL("$map_id", 2, map_id, 0)) — pl-qlf.c:4423-4460
# DIVERGES: the NULL state's branch only (QLF1): upstream's `else` raises `PL_permission_error("map", "identifier", A1)`
# before looking at either argument; the id table (`get_id`, `idMap`, `freeMapping`) needs a state and is unreachable.
"`'\$map_id'(+IdFrom, +IdTo)` (pl-qlf.c): map an identifier while saving a state; with no state, permission_error(map, identifier, IdFrom)."
function pl_map_id2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :map), mk_sym(T, :identifier), PL__t0)
    return FFALSE
end

# PORT: pl-qlf.c unmap_id as pl_unmap_id1_va
# (PRED_IMPL("$unmap_id", 1, unmap_id, 0)) — pl-qlf.c:4462-4478
# DIVERGES: the NULL state's branch only (QLF1): the `if ( (state=LD->qlf.write_state) )` body (`get_id`, `deleteHTable`)
# is not taken and the predicate succeeds without looking at its argument.
"`'\$unmap_id'(+IdFrom)` (pl-qlf.c): drop an identifier mapping of the state file; with no state, true."
function pl_unmap_id1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FTRUE
end

# PORT: pl-qlf.c BeginPredDefs as PL_predicates_from_wic
# DIVERGES: all 22 entries of the table, in upstream's order (pl-qlf.c:4953-4976): eighteen take the NULL-state branch or run (QLF1, QLF1B, QLF2: `$file_hash`, `$qlf_versions`, `$qlf_is_compatible`, `$qlf_sources`)
# (`'\$add_directive_wic'/1` `PL_FA_TRANSPARENT`, as the table's flags), four are refused by name. `PRED_DEF` ors in
# `PL_FA_VARARGS`.
"pl-qlf.c's registration table (`BeginPredDefs(wic)`): the shells and the refused predicates."
const PL_predicates_from_wic = (
    PL_extension("\$qlf_versions", 6, pl_qlf_versions6_va, PL_FA_VARARGS),
    PL_extension("\$qlf_is_compatible", 1, pl_qlf_is_compatible1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_sources", 2, pl_qlf_sources2_va, PL_FA_VARARGS),
    PL_extension("\$file_hash", 2, pl_file_hash2_va, PL_FA_VARARGS),
    PL_extension("\$qlf_module", 2, pl_qlf_module2_va, PL_FA_VARARGS),
    PL_extension("\$qlf_load", 2, pl_qlf_load2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension(
        "\$add_directive_wic",
        1,
        pl_add_directive_wic1_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("\$qlf_start_module", 1, pl_qlf_start_module1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_start_sub_module", 1, pl_qlf_start_sub_module1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_start_file", 1, pl_qlf_start_file1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_current_source", 1, pl_qlf_current_source1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_include", 5, pl_qlf_include5_va, PL_FA_VARARGS),
    PL_extension("\$qlf_dependency", 1, pl_qlf_dependency1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_end_part", 0, pl_qlf_end_part0_va, PL_FA_VARARGS),
    PL_extension("\$qlf_open", 1, pl_qlf_open1_va, PL_FA_VARARGS),
    PL_extension("\$qlf_close", 0, pl_qlf_close0_va, PL_FA_VARARGS),
    PL_extension("\$qlf_assert_clause", 2, pl_qlf_assert_clause2_va, PL_FA_VARARGS),
    PL_extension("\$open_wic", 2, pl_open_wic2_va, PL_FA_VARARGS),
    PL_extension("\$close_wic", 0, pl_close_wic0_va, PL_FA_VARARGS),
    PL_extension("\$map_id", 2, pl_map_id2_va, PL_FA_VARARGS),
    PL_extension("\$unmap_id", 1, pl_unmap_id1_va, PL_FA_VARARGS),
    PL_extension("\$import_wic", 3, pl_import_wic3_va, PL_FA_VARARGS)
)
