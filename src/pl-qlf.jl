# UPSTREAM: swipl-devel src/pl-qlf.c @ cbf4e1896275
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
# whole behaviour when no state is open. The other 15 predicates of the table read or write a QLF file and are
# refused by name (`NotPortedError`). A message the C loop prints with `Sdprintf` is collected on the local
# data's `messages` (`_qlf_Sdprintf!`), as `printMessage` collects a message (src/pl-error.jl).

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
# local data's `messages` as the atom of the text, severity `:error`, where printMessage collects a message
# (src/pl-error.jl), so a boot message is never lost (the design's H1).
"Collect the boot loop's diagnostic `text` (upstream: `Sdprintf` to the error stream)."
function _qlf_Sdprintf!(ld::PL_local_data{T}, text::String)::Nothing where {T}
    push!(ld.messages, (:error, mk_sym(T, Symbol(text))))
    return nothing
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
# (`printMessage`), the line end not collected.
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
    printMessage(ld, :error, term)                  # pl_write(term)
    return false
end

# ── the boot loop (pl-qlf.c:4691-4820) ─────────────────────────────────────────────────────────────

# ORIGINAL (LB3): `source_file_name` (an atom, NULL_ATOM while no file is read) as the text `%s` prints.
_qlf_source_file_text(ld::PL_local_data{T}) where {T} =
    ld.read_source.file === nothing ? "" : String(sym_text(ld.read_source.file))

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
# the template keeps nothing of it, and H11 asserts the boot left its stacks as it found them (no frame or term reference
# made by the boot survives it), so the copies made from the template carry none.
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
    empty_at = (ld.lTop, length(ld.trail), ld.fli_context, ld.nfliframes)   # H11: as emptyStacks! left them
    boot_from_source!(gd, ld, [initpl]) || error("boot_global_data: the boot compilation of $initpl failed")
    after = (ld.lTop, length(ld.trail), ld.fli_context, ld.nfliframes)
    after == empty_at || error("boot_global_data: the boot left its stacks at $after, not $empty_at (H11)")
    return gd
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

# The 14 predicates that read or write a QLF file are refused by name: calling one raises `NotPortedError` with
# its indicator (LD2; the QLF reader and writer are not ported — the boot compiles from source).
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

# PORT: pl-qlf.c qlf_versions as pl_qlf_versions6_va
# (PRED_IMPL("$qlf_versions", 6, qlf_versions, 0)) — refused by name
function pl_qlf_versions6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_versions", 6)
end

# PORT: pl-qlf.c qlf_is_compatible as pl_qlf_is_compatible1_va
# (PRED_IMPL("$qlf_is_compatible", 1, qlf_is_compatible, 0)) — refused by name
function pl_qlf_is_compatible1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_is_compatible", 1)
end

# PORT: pl-qlf.c qlf_sources as pl_qlf_sources2_va
# (PRED_IMPL("$qlf_sources", 2, qlf_sources, 0)) — refused by name
function pl_qlf_sources2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_sources", 2)
end

# PORT: pl-qlf.c file_hash as pl_file_hash2_va
# (PRED_IMPL("$file_hash", 2, file_hash, 0)) — refused by name
function pl_file_hash2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$file_hash", 2)
end

# PORT: pl-qlf.c qlf_module as pl_qlf_module2_va
# (PRED_IMPL("$qlf_module", 2, qlf_module, 0)) — refused by name
function pl_qlf_module2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_module", 2)
end

# PORT: pl-qlf.c qlf_load as pl_qlf_load2_va
# (PRED_IMPL("$qlf_load", 2, qlf_load, PL_FA_TRANSPARENT)) — refused by name
function pl_qlf_load2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_load", 2)
end

# PORT: pl-qlf.c qlf_current_source as pl_qlf_current_source1_va
# (PRED_IMPL("$qlf_current_source", 1, qlf_current_source, 0)) — refused by name
function pl_qlf_current_source1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_current_source", 1)
end

# PORT: pl-qlf.c $qlf_dependency as pl_qlf_dependency1_va
# (PRED_IMPL("$qlf_dependency", 1, $qlf_dependency, 0)) — refused by name
function pl_qlf_dependency1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_dependency", 1)
end

# PORT: pl-qlf.c qlf_open as pl_qlf_open1_va
# (PRED_IMPL("$qlf_open", 1, qlf_open, 0)) — refused by name
function pl_qlf_open1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_open", 1)
end

# PORT: pl-qlf.c qlf_close as pl_qlf_close0_va
# (PRED_IMPL("$qlf_close", 0, qlf_close, 0)) — refused by name
function pl_qlf_close0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$qlf_close", 0)
end

# PORT: pl-qlf.c open_wic as pl_open_wic2_va
# (PRED_IMPL("$open_wic", 2, open_wic, 0)) — refused by name
function pl_open_wic2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$open_wic", 2)
end

# PORT: pl-qlf.c close_wic as pl_close_wic0_va
# (PRED_IMPL("$close_wic", 0, close_wic, 0)) — refused by name
function pl_close_wic0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$close_wic", 0)
end

# PORT: pl-qlf.c map_id as pl_map_id2_va
# (PRED_IMPL("$map_id", 2, map_id, 0)) — refused by name
function pl_map_id2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$map_id", 2)
end

# PORT: pl-qlf.c unmap_id as pl_unmap_id1_va
# (PRED_IMPL("$unmap_id", 1, unmap_id, 0)) — refused by name
function pl_unmap_id1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _qlf_refused(T, "\$unmap_id", 1)
end

# PORT: pl-qlf.c BeginPredDefs as PL_predicates_from_wic
# DIVERGES: all 22 entries of the table, in upstream's order (pl-qlf.c:4953-4976): eight take the NULL-state branch
# (`'\$add_directive_wic'/1` `PL_FA_TRANSPARENT`, as the table's flags), 14 are refused by name. `PRED_DEF` ors in
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
