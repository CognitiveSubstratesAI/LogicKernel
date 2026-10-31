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
    gd::PL_global_data{T}, ld::PL_local_data{T}, directive::term_t, clause::term_t, functor::Symbol
)::Bool where {T}
    d0 = PL_new_term_ref(ld)

    na = PL_get_name_arity(ld, clause)
    (na === nothing || na[2] != 1 || sym_key(na[1]) != sym_key(mk_sym(T, functor))) && return false

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
_qlf_source_file_text(ld::PL_local_data) =
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

        if directiveClause(gd, ld, directive, t, :(:-))
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
