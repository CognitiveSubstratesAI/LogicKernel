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
