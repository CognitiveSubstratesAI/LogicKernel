# UPSTREAM: swipl-devel src/pl-supervisor.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SUPERVISORS (pl-supervisor.c): the code a call of a predicate enters first (`def->codes`). A new
# or changed predicate has `S_VIRGIN`, which installs the real one on the next call
# (`setDefaultSupervisor`): `S_UNDEF` for no clauses, `S_DYNAMIC` or `S_MULTIFILE` by the
# predicate's flags, `S_TRUSTME` for one clause, `S_LIST` for a `[]`/`[_|_]` pair, else `S_STATIC`.
#
# REPRESENTATION (DIVERGES): a supervisor is its code (`codes::Vector{code}`) and a side table of the
# clause references its `CA1_CLAUSEREF` operands index (`codes_crefs`), as a clause's code keeps its
# literals in a table; upstream's operand IS the `ClauseRef` pointer. A shared block (`SUPERVISOR(name)`,
# `PL_code_data`) is known by identity, where upstream reads its length word 0. Memory is Julia's, so
# freeing a supervisor and lingering it for other threads do not exist. The database's global data
# is passed in where upstream reads `global_generation()`.
#
# Since V5a2, the deterministic foreign supervisors (`createForeignSupervisor`). NOT PORTED: the
# non-deterministic ones (`I_FOPENNDET` …, V9), the wrapper supervisors
# (`S_CALLWRAPPER`, `wrap_predicate/4`), the tabling supervisors (`S_INCR_DYNAMIC`, `S_TRIE_GEN`) and
# `S_THREAD_LOCAL` — none of their subsystems exists.

# PORT: pl-supervisor.c initSupervisors
# DIVERGES: returns the database's shared blocks (one `PL_code_data` per database). Each is
# upstream's `[I, I_EXIT]` without the length word; `incr_dynamic`, `thread_local`, `wrapper` and
# `trie_gen` are not ported (see above).
"The shared supervisor code blocks, each `[I, I_EXIT]` (pl-supervisor.c `initSupervisors`)."
function initSupervisors()::PL_code_data
    return PL_code_data(
        code[I_EXIT, I_EXIT],               # MAKE_SV1(exit, I_EXIT)
        code[S_VIRGIN, I_EXIT],             # MAKE_SV1(virgin, S_VIRGIN)
        code[S_UNDEF, I_EXIT],              # MAKE_SV1(undef, S_UNDEF)
        code[S_DYNAMIC, I_EXIT],            # MAKE_SV1(dynamic, S_DYNAMIC)
        code[S_MULTIFILE, I_EXIT],          # MAKE_SV1(multifile, S_MULTIFILE)
        code[S_STATIC, I_EXIT]              # MAKE_SV1(staticp, S_STATIC)
    )
end

# Whether `codes` is one of the database's shared blocks (upstream: its length word is 0).
function _shared_supervisor(cd::PL_code_data, codes::Vector{code})::Bool
    return codes === cd.exit || codes === cd.virgin || codes === cd.undef ||
           codes === cd.dynamic || codes === cd.multifile || codes === cd.staticp
end

# PORT: pl-supervisor.c freeSupervisor
# DIVERGES: a no-op. Upstream frees a non-shared block, or lingers it while another thread may still
# run it; the kernel's memory is Julia's and there are no threads.
"Release supervisor `codes` of `def` (pl-supervisor.c; a no-op here, see above)."
freeSupervisor(def::Definition, codes::Vector{code}, do_linger::Bool)::Nothing = nothing

# PORT: pl-supervisor.c freeCodesDefinition as freeCodesDefinition!
# DIVERGES: no wrapper supervisors (`S_CALLWRAPPER`), so the wrapper branch is not ported. The side
# table is left as it is: `S_VIRGIN` has no operand to read it.
"Reset `def`'s supervisor to the shared `S_VIRGIN` (pl-supervisor.c `freeCodesDefinition`)."
function freeCodesDefinition!(def::Definition, do_linger::Bool)::Nothing
    virgin = def.code_data.virgin
    if (codes = def.codes) !== virgin
        def.codes = virgin
        freeSupervisor(def, codes, do_linger)
    end
    return nothing
end

# PORT: pl-supervisor.c equalSupervisors
# DIVERGES: compares the code AND the clause references of the side table, where upstream's
# `memcmp` compares the reference pointers inside the code; a shared block equals only itself.
"Whether supervisor (`c1`, `r1`) is the same code as (`c2`, `r2`) (pl-supervisor.c)."
function equalSupervisors(
    cd::PL_code_data, c1::Vector{code}, r1::Vector{R}, c2::Vector{code}, r2::Vector{R}
)::Bool where {R}
    if c1 !== c2
        if !_shared_supervisor(cd, c1) && !_shared_supervisor(cd, c2) && c1 == c2 &&
            length(r1) == length(r2) && all(i -> r1[i] === r2[i], eachindex(r1))
            return true
        end
        return false
    end
    return true
end

# PORT: pl-supervisor.c getClauses
# DIVERGES: fills `refp` (emptied first) with up to `max` clause references; no reference count on
# the predicate (`acquire_def`) — that serves clause GC across threads.
"Collect up to `max` clauses of `def` visible now into `refp`; the number visible (pl-supervisor.c)."
function getClauses(
    gd::PL_global_data{T}, def::Definition{T}, refp::Vector{ClauseRef{T}}, max::Int
)::Int where {T}
    found = 0
    empty!(refp)
    cref = def.impl_clauses.first_clause
    while cref !== nothing
        if visibleClause(cref.clause::Clause{T}, global_generation(gd))
            if found < max
                push!(refp, cref)
            end
            found += 1
        end
        cref = cref.next
    end
    return found
end

# The result of a supervisor selector: a supervisor's code and its side table, or `nothing`.
const _SV{T} = Union{Nothing, Tuple{Vector{code}, Vector{ClauseRef{T}}}}

# PORT: pl-supervisor.c undefSupervisor
"`S_UNDEF` for a predicate with no clauses that is not defined otherwise (pl-supervisor.c)."
function undefSupervisor(def::Definition{T})::_SV{T} where {T}
    if def.impl_clauses.number_of_clauses == 0 && (def.flags & PROC_DEFINED) == 0
        return (def.code_data.undef, ClauseRef{T}[])
    end
    return nothing
end

# PORT: pl-supervisor.c createUndefSupervisor
"Install `S_UNDEF` as `def`'s supervisor, if it has no clauses and is not defined otherwise (pl-supervisor.c)."
function createUndefSupervisor(def::Definition{T})::Bool where {T}
    sv = undefSupervisor(def)
    if sv !== nothing
        def.codes, def.codes_crefs = sv
        return true
    end
    return false
end

# PORT: pl-supervisor.c singleClauseSupervisor
"`S_TRUSTME <cref>` for a predicate with exactly one visible clause (pl-supervisor.c)."
function singleClauseSupervisor(gd::PL_global_data{T}, def::Definition{T})::_SV{T} where {T}
    if def.impl_clauses.number_of_clauses == 1
        cref = ClauseRef{T}[]
        found = getClauses(gd, def, cref, 1)

        if found == 1
            codes = code[S_TRUSTME, code(1)]        # codes[1] = ptr2code(cref): table entry 1
            return (codes, cref)
        end
    end
    return nothing
end

# PORT: pl-supervisor.c listSupervisor
"`S_LIST <arg> <nil clause> <list clause>` for a `[]`/`[_|_]` pair of clauses (pl-supervisor.c)."
function listSupervisor(gd::PL_global_data{T}, def::Definition{T})::_SV{T} where {T}
    arity = def.arity

    if def.impl_clauses.number_of_clauses == 2 && arity > 0
        cref = ClauseRef{T}[]
        found = getClauses(gd, def, cref, 2)

        if found == 2
            pc1 = Code(cref[1].clause::Clause{T}, 1)
            pc2 = Code(cref[2].clause::Clause{T}, 1)
            h_void1 = 0
            h_void2 = 0

            for arg in 0:(arity - 1)
                if !mode_arg_is_unbound(def, arg)
                    ok1, c1 = arg1Key(pc1)
                    ok2, c2 = arg1Key(pc2)
                    if ok1 && ok2 &&
                        (
                            (c1 == ATOM_nil && c2 == FUNCTOR_dot2) ||
                            (c2 == ATOM_nil && c1 == FUNCTOR_dot2)
                        )
                        codes = code[S_LIST, code(arg), code(1), code(2)]
                        if c1 == ATOM_nil
                            return (codes, ClauseRef{T}[cref[1], cref[2]])
                        else
                            return (codes, ClauseRef{T}[cref[2], cref[1]])
                        end
                    end
                end
                pc1, h_void1 = skipArgs(pc1, 1, h_void1)
                pc2, h_void2 = skipArgs(pc2, 1, h_void2)
            end
        end
    end
    return nothing
end

# PORT: pl-supervisor.c dynamicSupervisor
# DIVERGES: no incremental tabling, so never `SUPERVISOR(incr_dynamic)`.
"`S_DYNAMIC` for a dynamic predicate (pl-supervisor.c)."
function dynamicSupervisor(def::Definition{T})::_SV{T} where {T}
    if (def.flags & P_DYNAMIC) != 0
        return (def.code_data.dynamic, ClauseRef{T}[])
    end
    return nothing
end

# PORT: pl-supervisor.c multifileSupervisor
"`S_MULTIFILE` for a multifile predicate (pl-supervisor.c)."
function multifileSupervisor(def::Definition{T})::_SV{T} where {T}
    if (def.flags & P_MULTIFILE) != 0
        return (def.code_data.multifile, ClauseRef{T}[])
    end
    return nothing
end

# PORT: pl-supervisor.c staticSupervisor
"`S_STATIC`, the general supervisor (pl-supervisor.c)."
function staticSupervisor(
    def::Definition{T}
)::Tuple{Vector{code}, Vector{ClauseRef{T}}} where {T}
    return (def.code_data.staticp, ClauseRef{T}[])
end

# PORT: pl-supervisor.c chainPredicateSupervisor
# DIVERGES: returns `post`. Upstream prepends `S_SSU_DET`, `S_DET` or the meta-argument module
# qualification (`S_MQUAL`/`S_LMQUAL`) for a predicate flagged `P_SSU_DET`, `P_DET` or
# `P_META`+`P_TRANSPARENT`; the kernel has none of those flags (SSU rules, det declarations and
# meta-predicates are not ported), so its condition cannot hold.
"Prepend `post` with the checks the predicate's declarations need (pl-supervisor.c)."
function chainPredicateSupervisor(
    def::Definition{T}, post::Tuple{Vector{code}, Vector{ClauseRef{T}}}
)::Tuple{Vector{code}, Vector{ClauseRef{T}}} where {T}
    return post
end

# PORT: pl-supervisor.c createSupervisor
"The supervisor `def` needs now: its code and its side table (pl-supervisor.c)."
function createSupervisor(
    gd::PL_global_data{T}, def::Definition{T}
)::Tuple{Vector{code}, Vector{ClauseRef{T}}} where {T}
    codes = undefSupervisor(def)
    codes === nothing && (codes = dynamicSupervisor(def))
    codes === nothing && (codes = multifileSupervisor(def))
    codes === nothing && (codes = singleClauseSupervisor(gd, def))
    codes === nothing && (codes = listSupervisor(gd, def))
    sv = codes === nothing ? staticSupervisor(def) : codes
    return chainPredicateSupervisor(def, sv)
end

# PORT: pl-supervisor.c setDefaultSupervisor
# DIVERGES: no lock or memory barrier (no threads).
"""
    setDefaultSupervisor(gd, def) -> Bool

Install the supervisor `def` needs now, re-deciding its indexes when it changed; keep the old one
when it is the same code (pl-supervisor.c). A locked supervisor (`P_LOCKED_SUPERVISOR`) is kept.
"""
function setDefaultSupervisor(gd::PL_global_data{T}, def::Definition{T})::Bool where {T}
    if (def.flags & P_LOCKED_SUPERVISOR) == 0
        old, oldrefs = def.codes, def.codes_crefs
        codes, crefs = createSupervisor(gd, def)
        if equalSupervisors(def.code_data, old, oldrefs, codes, crefs)
            freeSupervisor(def, codes, false)
            update_primary_index!(def)
        else
            reconsiderIndexes!(def)                 # clause shape changed; re-decide
            update_primary_index!(def)
            def.codes = codes
            def.codes_crefs = crefs
            freeSupervisor(def, old, true)
        end
    end

    return true
end

# PORT: pl-supervisor.c MAX_FLI_ARGS
"The most arguments a foreign predicate with the `a1, a2, …` convention takes (pl-supervisor.c)."
const MAX_FLI_ARGS = 10

# PORT: pl-supervisor.c createForeignSupervisor as createForeignSupervisor!
# DIVERGES: `f` is the built-in's index in its dispatch table (decision 5; src/pl-ext.jl), where
# upstream's operand is the function's address (`ptr2code`). The non-deterministic supervisor
# (`I_FOPENNDET`, `I_FCALLNDET*`, `I_FEXITNDET`, `I_FREDO`) is V9's: refused by name.
"Give foreign predicate `def` its supervisor calling built-in `f` (pl-supervisor.c)."
function createForeignSupervisor!(def::Definition{T}, f::Int)::Bool where {T}
    @assert (def.flags & P_FOREIGN) != 0
    if (def.flags & P_VARARG) == 0 && def.arity > MAX_FLI_ARGS
        error(
            "Too many arguments to foreign function $(repr(def.name))/$(def.arity) (>$MAX_FLI_ARGS)"
        )
    end
    if (def.flags & P_NONDET) == 0
        if (def.flags & P_VARARG) != 0
            def.codes = code[I_FCALLDETVA, code(f)]
        else
            def.codes = code[I_FCALLDET0 + code(def.arity), code(f), I_FEXITDET]
        end
    else
        throw(
            NotPortedError{T}(
                def.name, "a non-deterministic foreign predicate's supervisor", "V9"
            )
        )
    end
    return true
end
