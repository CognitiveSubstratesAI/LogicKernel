# ORIGINAL: the dispatch manifest JET checks; no swipl-devel counterpart.
# test/static_analysis_manifest.jl — the concrete call signatures the JET/AllocCheck gate analyses.
#
# 🔴 EVERY method LogicKernel defines (its own functions AND its methods on Base functions) must be
# reached by an entry here, or `test_static_analysis.jl` FAILS and names the method. So a new
# function cannot land without being checked for runtime dispatch — that is the point.
#
# DISPATCH_MANIFEST: (function, Tuple{argument types...}, must_not_allocate::Bool)
#   CONCRETE argument types only — the gate analyses exactly these specialisations.
# DISPATCH_EXEMPT:   (function, Tuple{...}) => "reason"   — a method that legitimately cannot be
#   called with the reference types. An empty reason, or an entry naming no method of LogicKernel,
#   fails the gate.
#
# Three instantiations of the default term type, chosen to cover the three payload shapes:
#   one concrete type · a union of 3 (+ Nothing = 4, the compiler's union-splitting limit) · a container.
const _M1 = Term{Float64}
const _M2 = DefaultTerm
const _M3 = Term{Vector{Float64}}

const LK = LogicKernel

_manifest_per_type(T) = (
    # the term interface — field reads, must not allocate
    (kind, Tuple{T}, true), (nchildren, Tuple{T}, true), (child, Tuple{T, Int}, true),
    (sym_key, Tuple{T}, true), (sym_hash, Tuple{T}, true), (var_key, Tuple{T}, true),
    (gnd_key, Tuple{T}, true),
    (is_ground, Tuple{T}, true),
    (is_ground_walk, Tuple{T}, false),
    (gnd_equal, Tuple{T, T}, false), (atomic_compare, Tuple{T, T}, false),
    (mk_var, Tuple{Type{T}, UInt64}, false),
    (mk_expr, Tuple{Type{T}, Vector{T}}, false),
    (sym_term, Tuple{Type{T}, Symbol}, false), (sym_name, Tuple{T}, true),
    (gnd_value, Tuple{T}, false),
    # the standard order — the ported chain, every link
    (compareStandard, Tuple{T, T}, false), (compareStandard, Tuple{T, T, Bool}, false),
    (LK.compare_std, Tuple{T, T, Int}, false),
    (LK.compare_fast, Tuple{T, T, Int}, false),
    (LK.do_compare, Tuple{T, T, Int}, false),
    (LK.compare_primitives, Tuple{T, T, Int}, false),
    (LK.compare_functors, Tuple{T, T, Int}, false), (LK._atomic_rank, Tuple{T}, false),
    # Base methods on the default type
    (Base.:(==), Tuple{T, T}, false), (Base.hash, Tuple{T, UInt}, false),
    (Base.show, Tuple{IOBuffer, T}, false)
)

# The clause index and its head compiler (src/pl-incl.jl, pl-vmi.jl, pl-comp.jl, pl-index.jl,
# pl-proc.jl), every method once, over term type T. The entry points are also checked for the
# other two payload types (`_index_entry_points`); JET follows their callees.
function _manifest_index(T)
    D, C, CL = LK.Definition{T}, LK.Clause{T}, LK.ClauseList{T}
    CR, CB, CI = LK.ClauseRef{T}, LK.ClauseBucket{T}, LK.ClauseIndex{T}
    CH, CTX = LK.ClauseChoice{T}, LK.index_context{T}
    CIP = Vector{Union{Nothing, CI}}
    NT4, NT8, NTW = NTuple{4, UInt8}, NTuple{8, UInt8}, NTuple{4, UInt64}
    CInfo, HA, HH = LK.compileInfo, LK.hash_assessment, LK.hash_hints
    VIEW = typeof(view(UInt8[], 1:0))
    return (
        # src/pl-comp.jl — the head compiler and the code readers
        (LK.isIndexedVarTerm, Tuple{CInfo, T}, false),
        (LK._comp_arg, Tuple{T, Int, Int}, true),
        (LK._comp_shape, Tuple{T}, true),
        (LK.analyseVariables2!, Tuple{CInfo, T, Int, Int}, false),
        (LK.analyse_variables!, Tuple{CInfo, T}, false),
        (LK.compileArgument!, Tuple{CInfo, T, Int}, false),
        (LK.compileClause, Tuple{D, T}, false),
        # src/pl-index.jl
        (LK.STATIC_RELOADING, Tuple{D}, true), (LK.cref_matches, Tuple{CR, UInt64}, true),
        (LK.is_clean_predicate, Tuple{D}, true), (LK.visibleClause, Tuple{C, UInt64}, true),
        (LK.visibleClauseCNT, Tuple{C, UInt64}, true), (LK.argv_at, Tuple{T, Int}, true),
        (LK.canIndex, Tuple{T}, true), (LK.indexOfWord, Tuple{T}, true),
        (LK.ISDEADCI, Tuple{CI}, true), (LK.ISDEADCI, Tuple{Nothing}, true),
        (LK.next_clause_unindexed!, Tuple{CTX}, true),
        (LK.next_clause_primary_index!, Tuple{CTX}, true),
        (LK.nextClauseFromList!, Tuple{CI, T, CTX}, false),
        (LK.nextClauseFromBucket!, Tuple{CI, T, CTX}, false),
        (LK.setClauseChoice!, Tuple{CR, CTX}, true),
        (LK.setClauseChoice!, Tuple{Nothing, CTX}, true),
        (LK.indexKeyFromArgv, Tuple{CI, T}, true), (LK.is_var, Tuple{T}, true),
        (LK.is_satifies_index, Tuple{CI, T}, true),
        (LK.existing_hash, Tuple{CIP, T}, false),
        (LK.createIndex!, Tuple{T, Int, CL, CI, CTX}, false),
        (LK.createIndex!, Tuple{T, Int, CL, Nothing, CTX}, false),
        (LK.first_clause_guarded!, Tuple{T, Int, CL, CTX}, false),
        (LK.firstClause!, Tuple{T, UInt64, D, CH}, false),
        (LK.nextClause!, Tuple{CH, T, UInt64, D}, false),
        (LK.realize_clause_index!, Tuple{CI}, false),
        (LK.newClauseIndexTable, Tuple{HH, Bool, CTX}, false),
        (LK.newClauseListRef, Tuple{Type{T}, UInt64}, false),
        (LK.addToClauseList!, Tuple{CR, C, UInt64, Int}, false),
        (LK.addClauseToListIndexes!, Tuple{D, CL, C, Int}, false),
        (LK.insertIntoSparseList!, Tuple{CR, CR, CR, Int}, true),
        (LK.insertIntoSparseList!, Tuple{CR, CR, CR, CR}, true),
        (LK.addClauseBucket!, Tuple{CB, C, UInt64, UInt64, Int, Bool}, false),
        (LK.clearTriedIndexes!, Tuple{D}, true), (LK.reconsiderIndexes!, Tuple{D}, true),
        (LK.has_pow2_clauses, Tuple{D}, true), (LK.reconsider_index!, Tuple{D}, true),
        (LK.indexKeyFromClause, Tuple{CI, C}, true),
        (LK.addClauseToIndex!, Tuple{CI, C, Int}, false),
        (LK.addClauseToIndexes!, Tuple{D, C, Int}, false),
        (LK.wait_for_index!, Tuple{CI, CL, CTX}, false),
        (LK.wait_for_index!, Tuple{CI, CL, Nothing}, false),
        (LK.completed_index!, Tuple{CI}, true),
        (LK.fill_clause_index!, Tuple{CI, CL, CTX}, false),
        (LK.hashDefinition!, Tuple{CL, HH, CTX}, false),
        (LK.copyIndex, Tuple{CIP, CI}, false),
        (LK.copyIndex, Tuple{CIP, Nothing}, false), (LK.cmp_indexes, Tuple{CI, CI}, true),
        (LK.cmp_indexes, Tuple{Nothing, CI}, true), (LK.sortIndexes!, Tuple{CIP}, false),
        (LK.sortIndexes!, Tuple{Nothing}, true), (LK.isSortedIndexes, Tuple{CIP}, true),
        (LK.isSortedIndexes, Tuple{Nothing}, true),
        (LK.setIndexes!, Tuple{D, CL, CIP}, true),
        (LK.setIndexes!, Tuple{D, CL, Nothing}, true),
        (LK.replaceIndex!, Tuple{D, CL, CIP, Int, CI}, false),
        (LK.replaceIndex!, Tuple{D, CL, CIP, Int, Nothing}, false),
        (LK.deleteIndexP!, Tuple{D, CL, CIP, Int}, false),
        (LK.deleteIndex!, Tuple{D, CL, CI}, false),
        (LK.next_clause_index, Tuple{CIP, Int}, true),
        (LK.insertIndex!, Tuple{D, CL, CI}, false),
        (LK.best_hash_assessment, Tuple{UInt8, UInt8, CL}, true),
        (LK.sort_assessments!, Tuple{CL, Vector{UInt8}, Int}, false),
        (LK.skipToTerm, Tuple{C, NT8, Int}, true),
        (LK.assess_scan_clauses!, Tuple{CL, Int, Vector{HA}, Int, CTX}, false),
        (LK.assess_candidate_indexes!, Tuple{Int, CL, LK.assessment_set, CTX}, false),
        (LK.ensure_arg_info!, Tuple{CL, Int}, false),
        (LK.better_index, Tuple{CI, Float32, Float32}, true),
        (LK.better_index, Tuple{Nothing, Float32, Float32}, true),
        (LK.bestHash!, Tuple{T, Int, CL, Nothing, HH, CTX}, false),
        (LK.bestHash!, Tuple{T, Int, CL, CI, HH, CTX}, false),
        (
            LK.find_multi_argument_hash!,
            Tuple{Int, CL, Vector{UInt8}, Int, Nothing, HH, CTX},
            false
        ),
        (LK.assess_all_arguments!, Tuple{Int, CL, CTX}, false),
        (
            LK.create_good_indexes!,
            Tuple{CL, Vector{UInt8}, Int, Vector{HH}, Int, Int},
            false
        ),
        (LK.create_deep_indexes!, Tuple{CL, VIEW, Int, Vector{HH}, Int, Int}, false),
        (LK.candidate_indexes!, Tuple{Int, CL, Vector{HH}, Int, CTX}, false),
        (LK.get_existing_index, Tuple{CIP, Int, HH}, false),
        (LK.get_existing_index, Tuple{Nothing, Int, HH}, true),
        (LK.set_candidate_indexes!, Tuple{D, CL, Int, Bool}, false),
        (LK.can_be_primary_index, Tuple{CL, Int}, true),
        (LK.preferred_primary_index, Tuple{D}, true),
        (LK.modify_primary_index_arg!, Tuple{D, Int}, true),
        (LK.update_primary_index!, Tuple{D}, false), (LK.collisionCount, Tuple{CI}, true),
        (LK.unify_clause_index, Tuple{CI}, false),
        (LK.add_deep_indexes!, Tuple{Vector{LK.index_property}, CI}, false),
        (LK.unify_index_pattern, Tuple{D}, false),
        # src/pl-proc.jl
        (LK.lookupProcedure, Tuple{Type{T}, UInt64, Int, UInt64}, false),
        (LK.newClauseRef, Tuple{C, UInt64}, false),
        (LK.assertDefinition!, Tuple{D, C, Int}, false),
        (LK.assertDefinition!, Tuple{D, C, CR}, false),
        (LK.mode_arg_is_unbound, Tuple{D, Int}, true)
    )
end

"The index's entry points, checked for every payload type."
_index_entry_points(T) = (
    (LK.compileClause, Tuple{LK.Definition{T}, T}, false),
    (LK.assertDefinition!, Tuple{LK.Definition{T}, LK.Clause{T}, Int}, false),
    (LK.firstClause!, Tuple{T, UInt64, LK.Definition{T}, LK.ClauseChoice{T}}, false),
    (LK.nextClause!, Tuple{LK.ClauseChoice{T}, T, UInt64, LK.Definition{T}}, false),
    (LK.unify_index_pattern, Tuple{LK.Definition{T}}, false),
    (LK.indexOfWord, Tuple{T}, true)
)

const DISPATCH_MANIFEST = (
    _manifest_per_type(_M1)...,
    _manifest_per_type(_M2)...,
    _manifest_per_type(_M3)...,
    _manifest_index(_M2)...,
    _index_entry_points(_M1)...,
    _index_entry_points(_M3)...,
    # term-type-independent parts of the index and its head compiler
    (LK._le_byte, Tuple{NTuple{4, UInt64}, Int}, true),
    (LK.MurmurHashAligned2, Tuple{NTuple{4, UInt64}, Int, UInt32}, true),
    (LK.FLAG64, Tuple{Int}, true), (LK.tagex, Tuple{UInt64}, true),
    (LK.isFunctor, Tuple{UInt64}, true), (LK.MK_ATOM, Tuple{UInt64}, true),
    (LK.MK_FUNCTOR, Tuple{UInt64, UInt64}, true), (LK.codeTable, Tuple{UInt64}, true),
    (LK.initVMIMerge, Tuple{UInt64}, true), (LK.PC, Tuple{LK.compileInfo}, true),
    (LK.initMerge!, Tuple{LK.compileInfo}, true),
    (LK.mergeInstructions!, Tuple{LK.compileInfo, NTuple{4, LK.vmi_merge}, UInt64}, false),
    (LK.Output_0!, Tuple{LK.compileInfo, UInt64}, false),
    (LK.Output_a!, Tuple{LK.compileInfo, UInt64}, false),
    (LK.Output_1!, Tuple{LK.compileInfo, UInt64, UInt64}, false),
    (LK.Output_n!, Tuple{LK.compileInfo, UInt64, UInt64, Int}, false),
    (LK.VAROFFSET, Tuple{Int}, true), (LK.isFirstVarSet!, Tuple{BitVector, Int}, true),
    (LK.decode, Tuple{LK.Code}, true), (LK.stepPC, Tuple{LK.Code}, true),
    (LK.skipArgs, Tuple{LK.Code, Int, Int}, true), (LK.argKey, Tuple{LK.Code, Int}, true),
    (LK.MSB, Tuple{Int}, true), (LK.MSB, Tuple{UInt32}, true),
    (LK.clean_index_key, Tuple{UInt64}, true), (LK.hashIndex, Tuple{UInt64, UInt32}, true),
    (LK._functor_word, Tuple{UInt64, Int}, true),
    (LK.join_multi_arg_keys, Tuple{NTuple{4, UInt64}, Int}, true),
    (LK.consider_better_index, Tuple{Float32, UInt32}, true),
    (LK.cmp_iarg, Tuple{UInt8, UInt8}, true),
    (LK.canonicalHap, Tuple{NTuple{4, UInt8}}, true),
    (LK.copytpos, Tuple{NTuple{8, UInt8}}, true), (LK.init_assessment_set, Tuple{}, false),
    (LK.alloc_assessment!, Tuple{LK.assessment_set, NTuple{4, UInt8}}, false),
    (LK.compar_keys, Tuple{LK.key_asm, LK.key_asm}, true),
    (LK.perfect_size, Tuple{LK.hash_assessment}, true),
    (LK.assess_remove_duplicates!, Tuple{LK.hash_assessment, Int}, false),
    (LK.assessAddKey!, Tuple{LK.hash_assessment, UInt64, Bool}, false),
    (LK._put_key!, Tuple{LK.hash_assessment, UInt64, Bool}, true),
    (LK.indexableCompound, Tuple{LK.Code}, true),
    (LK.best_assessment!, Tuple{Vector{LK.hash_assessment}, Int, Int}, false),
    (LK.cp_hints_from_arg_info!, Tuple{LK.hash_hints, Int, LK.arg_info}, true),
    (LK.cp_hints_from_assessment!, Tuple{LK.hash_hints, LK.hash_assessment}, true),
    (LK.cmp_assessment, Tuple{LK.hash_assessment, LK.hash_assessment}, true),
    # payload-specific entry points
    (gnd_term, Tuple{Type{_M1}, Float64}, false),
    (gnd_term, Tuple{Type{_M2}, Int64}, false), (gnd_term, Tuple{Type{_M2}, String}, false),
    (gnd_term, Tuple{Type{_M3}, Vector{Float64}}, false),
    (LK._gnd_eq, Tuple{Float64, _M1}, false), (LK._gnd_eq, Tuple{Int64, _M2}, false),
    (LK._gnd_eq, Tuple{Vector{Float64}, _M3}, false),
    (LK._compare_other, Tuple{Vector{Float64}, _M3}, false),
    (LK._compare_other, Tuple{Int64, _M2}, false),
    (gnd_value_key, Tuple{Float64}, false), (gnd_value_key, Tuple{Int64}, false),
    (gnd_value_key, Tuple{String}, false), (gnd_value_key, Tuple{Vector{Float64}}, false),
    # leaf comparisons and helpers
    (LK._sign, Tuple{Int}, true), (LK._tag_rank, Tuple{Kind}, true),
    (LK._sym_key, Tuple{Symbol}, true),
    (LK.compareAtoms, Tuple{Symbol, Symbol}, true),
    (LK.compareStrings, Tuple{String, String}, false),
    (LK._nan_value, Tuple{Float64}, true), (LK._nan_value, Tuple{BigFloat}, false),
    (LK.compare_neq_floats, Tuple{Float64, Float64}, true),
    (LK.compare_mixed_float_rational, Tuple{Float64, Int64}, true),
    (LK._is_number, Tuple{Float64}, true),
    (LK._cmp_types, Tuple{DataType, DataType}, false),
    (LK._compare_numbers, Tuple{Int64, Float64}, false),
    (LK._compare_numbers, Tuple{Float64, Float64}, false),
    (LK._compare_strings, Tuple{String, String}, false),
    # generated by `@enum Kind` (Julia 1.13) — found by the coverage gate, not by reading; checked
    # rather than exempted because checking it costs nothing
    (Base.Enums._enum_hash, Tuple{Kind, UInt64}, false)
)

# `is_ground(t)` with an untyped argument is the interface's FALLBACK for implementations without a
# cached bit; `Term` overrides it, so no reference type reaches it. (`Tuple{Int}` names the fallback
# method by a non-term argument type — it is the method `which` selects.) Its body is
# `is_ground_walk`, which IS in the manifest.
const DISPATCH_EXEMPT = (
    (
    (is_ground, Tuple{Int}) => "interface fallback; Term overrides it, and its body is_ground_walk is checked"
),
)
