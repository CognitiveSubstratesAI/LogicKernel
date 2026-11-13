# UPSTREAM: swipl-devel src/pl-supervisor.c @ 18168e629eab
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
# Since V5a2, the deterministic foreign supervisors (`createForeignSupervisor`). Left out: the
# non-deterministic ones (`I_FOPENNDET` …, V9), the tabling supervisor `S_INCR_DYNAMIC` and
# `S_THREAD_LOCAL` — none of their subsystems exists (`S_TRIE_GEN`, compiled tries, is in since TR4). Since TAB1-min (T3/T4/T5) the wrapper supervisors
# (`S_CALLWRAPPER`, `S_TABLED`; src/pl-wrap.jl) are installed by `'$c_wrap_predicate'/5` and kept by `freeCodesDefinition!`;
# `S_WRAP` and the shared `wrapper` block (`PL_code_data.wrapper`) belong to the closure's copy of the wrapped predicate;
# since WRAP1 the run loop runs `S_WRAP` and `S_CALLWRAPPER`, and refuses `S_TABLED` by name (TAB1).

# PORT: pl-supervisor.c initSupervisors
# DIVERGES: returns the database's shared blocks (one `PL_code_data` per database). Each is
# upstream's `[I, I_EXIT]` without the length word; `incr_dynamic` and `thread_local` are
# left out (see above); `wrapper` is TAB1-min's (T3), `trie_gen` TR4's (the supervisor of trie_gen_compiled/2,3).
"The shared supervisor code blocks, each `[I, I_EXIT]` (pl-supervisor.c `initSupervisors`)."
function initSupervisors()::PL_code_data
    return PL_code_data(
        code[I_EXIT, I_EXIT],               # MAKE_SV1(exit, I_EXIT)
        code[S_VIRGIN, I_EXIT],             # MAKE_SV1(virgin, S_VIRGIN)
        code[S_UNDEF, I_EXIT],              # MAKE_SV1(undef, S_UNDEF)
        code[S_DYNAMIC, I_EXIT],            # MAKE_SV1(dynamic, S_DYNAMIC)
        code[S_MULTIFILE, I_EXIT],          # MAKE_SV1(multifile, S_MULTIFILE)
        code[S_STATIC, I_EXIT],             # MAKE_SV1(staticp, S_STATIC)
        code[S_WRAP, I_EXIT],               # MAKE_SV1(wrapper, S_WRAP)
        code[S_TRIE_GEN, I_EXIT]            # MAKE_SV1(trie_gen, S_TRIE_GEN) (TR4)
    )
end

# Whether `codes` is one of the database's shared blocks (upstream: its length word is 0).
function _shared_supervisor(cd::PL_code_data, codes::Vector{code})::Bool
    return codes === cd.exit || codes === cd.virgin || codes === cd.undef ||
           codes === cd.dynamic || codes === cd.multifile || codes === cd.staticp ||
           codes === cd.wrapper || codes === cd.trie_gen
end

# PORT: pl-supervisor.c freeSupervisor
# DIVERGES: a no-op. Upstream frees a non-shared block, or lingers it while another thread may still
# run it; the kernel's memory is Julia's and there are no threads.
"Release supervisor `codes` of `def` (pl-supervisor.c; a no-op here, see above)."
freeSupervisor(def::Definition, codes::Vector{code}, do_linger::Bool)::Nothing = nothing

# PORT: pl-supervisor.c freeCodesDefinition as freeCodesDefinition!
# DIVERGES: the side table is left as it is: `S_VIRGIN` has no operand to read it. The WRAPPER branch needs the closure a
# wrapper supervisor names, which is found in the database's table (`gd.closure_refs`): the method with `gd` is the whole
# function, and the method without `gd` raises a named error for a wrapped predicate. Since R2 WRAP1 every run-time caller
# passes the database (`setDynamicDefinition!(gd, ...)`, `resetProcedure!(gd, ...)`, `setThreadLocalDefinition!` through `ld.GD`);
# the methods of `setDynamicDefinition!` and `resetProcedure!` without `gd` stay for the callers that have none (tests, the
# precompile workload), and refuse a wrapped predicate by name.
"Reset `def`'s supervisor to the shared `S_VIRGIN`; a wrapped predicate keeps its wrapper and resets the wrapped supervisor (pl-supervisor.c `freeCodesDefinition`)."
function freeCodesDefinition!(
    gd::PL_global_data{T}, def::Definition{T}, do_linger::Bool
)::Nothing where {T}
    virgin = def.code_data.virgin
    if (codes = def.codes) !== virgin
        if isCallWrapper(codes[skipWrapperPrefix(codes)])   # unlikely(isCallWrapper(skipWrapperPrefix(codes)[0]))
            resetWrappedSupervisor(gd, def, do_linger)
            if !do_linger
                codes = def.codes
                def.codes = virgin
                freeSupervisor(def, codes, do_linger)
            end
        else
            def.codes = virgin
            freeSupervisor(def, codes, do_linger)
        end
    end
    return nothing
end

# PORT: pl-supervisor.c freeCodesDefinition as freeCodesDefinition!
# DIVERGES: see above: a definition with a wrapper supervisor is refused by name, never reset silently.
"Reset `def`'s supervisor to the shared `S_VIRGIN`; the method without the database refuses a wrapped predicate (pl-supervisor.c)."
function freeCodesDefinition!(def::Definition{T}, do_linger::Bool)::Nothing where {T}
    virgin = def.code_data.virgin
    if (codes = def.codes) !== virgin
        if isCallWrapper(codes[skipWrapperPrefix(codes)])
            throw(
                NotPortedError{T}(
                    def.name,
                    "freeCodesDefinition! of a wrapped predicate needs the database", "TAB1"
                )
            )
        end
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
# the predicate (`acquire_def`) — that serves clause GC across threads. DIVERGES (representation): global field standing in for
# LD->reload.generation, owner TH1 (`gd.reload_generation`: the function has the database only).
"Collect up to `max` clauses of `def` visible now into `refp`; the number visible (pl-supervisor.c)."
function getClauses(
    gd::PL_global_data{T}, def::Definition{T}, refp::Vector{ClauseRef{T}}, max::Int
)::Int where {T}
    found = 0
    empty!(refp)
    cref = def.impl_clauses.first_clause
    while cref !== nothing
        if visibleClause(
            cref.clause::Clause{T}, global_generation(gd), gd.reload_generation
        )
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
# (pl-supervisor.c:379-418 at the pin; the meta-argument branch since MOD4)
# DIVERGES: no `S_DET`: `P_DET` cannot be set here (`setAttrDefinition` refuses it). The chained supervisor
# is a new code vector (the shared block `post` is not changed, nor freed: `freeCodesMem` is Julia's); the
# side table is `post`'s, as the `CA1_CLAUSEREF` operands index it by entry, not by position. The
# argument masks are `def.impl_clauses.args` (upstream's `def->impl.any.args`, the union's common field).
"Prepend `post` with the checks the predicate's declarations need — `S_SSU_DET` for an SSU predicate, `S_MQUAL`/`S_LMQUAL` for a transparent meta-predicate (pl-supervisor.c)."
function chainPredicateSupervisor(
    def::Definition{T}, post::Tuple{Vector{code}, Vector{ClauseRef{T}}}
)::Tuple{Vector{code}, Vector{ClauseRef{T}}} where {T}
    meta = (def.flags & P_META) != 0 && (def.flags & P_TRANSPARENT) != 0
    if meta || (def.flags & P_SSU_DET) != 0         # ison(def, P_SSU_DET|P_DET) (P_DET: see above)
        codes = code[]                              # initBuffer(&buf)
        if (def.flags & P_SSU_DET) != 0
            push!(codes, S_SSU_DET)                 # addBuffer(&buf, encode(S_SSU_DET), code)
        end
        if meta && def.arity > 0                    # ison(def, P_META) && ison(def, P_TRANSPARENT)
            # (`def.arity > 0`: an arity-0 predicate has no masks, `impl_clauses.args === nothing`;
            # upstream's loop runs zero times there)
            loffset = -1
            args = def.impl_clauses.args::Vector{arg_info}
            for i in 0:(def.arity - 1)
                ma = args[i + 1].meta               # def->impl.any.args[i].meta
                if MA_NEEDS_TRANSPARENT(ma)
                    loffset = length(codes)         # entriesBuffer(&buf, code)
                    push!(codes, S_MQUAL)           # addBuffer(&buf, encode(S_MQUAL), code)
                    push!(codes, VAROFFSET(i))      # addBuffer(&buf, VAROFFSET(i), code)
                end
            end
            if loffset >= 0
                codes[loffset + 1] = S_LMQUAL       # baseBuffer(&buf, code)[loffset] = encode(S_LMQUAL)
            end
        end
        if !isempty(codes)                          # !isEmptyBuffer(&buf)
            append!(codes, post[1])                 # copySuperVisorCode(&buf, post)
            return (codes, post[2])
        end
    end
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
# DIVERGES: no lock or memory barrier (no threads). DIVERGES (representation): global field standing in for LD->reload.generation, owner TH1
# (`gd.reload_generation`, read by `update_primary_index!`).
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
            update_primary_index!(def, gd.reload_generation)
        else
            reconsiderIndexes!(def)                 # clause shape changed; re-decide
            update_primary_index!(def, gd.reload_generation)
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
# upstream's operand is the function's address (`ptr2code`). Since NF1 the non-deterministic
# supervisor is built as upstream's; since NF4 its `I_FCALLNDET<N>` (the `a1, a2, …` convention) runs
# too (`_fcall_ndet`, src/pl-ext.jl).
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
        if (def.flags & P_VARARG) != 0
            def.codes = code[I_FOPENNDET, I_FCALLNDETVA, code(f), I_FEXITNDET, I_FREDO]
        else
            def.codes = code[
                I_FOPENNDET, I_FCALLNDET0 + code(def.arity), code(f), I_FEXITNDET, I_FREDO
            ]
        end
    end
    return true
end
