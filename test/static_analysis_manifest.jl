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
    (kind, Tuple{T}, true), (term_type, Tuple{T}, true),
    # …and its Prolog layer (Q1)
    (mk_sym, Tuple{Type{T}, Symbol}, false),
    (mk_reserved_symbol, Tuple{Type{T}, Symbol}, false),
    (mk_nil, Tuple{Type{T}}, false),
    (is_reserved_symbol, Tuple{T}, true), (is_nil, Tuple{T}, true),
    (is_pair, Tuple{T}, true),
    (LK.isReservedSymbol, Tuple{T}, true), (LK._functor_name, Tuple{T}, true),
    (number_kind, Tuple{T}, true), (integer_is_int64, Tuple{T}, true),
    (int64_value, Tuple{T}, false), (bigint_value, Tuple{T}, false),
    (rational_value, Tuple{T}, false), (float_value, Tuple{T}, false),
    (string_value, Tuple{T}, false),
    (LK.is_portable_smallint, Tuple{LK.PL_local_data{T}, Int64}, true),
    (nchildren, Tuple{T}, true), (child, Tuple{T, Int}, true),
    (sym_key, Tuple{T}, true), (sym_hash, Tuple{T}, true), (var_key, Tuple{T}, true),
    (gnd_key, Tuple{T}, true),
    (is_ground, Tuple{T}, true),
    (is_ground_walk, Tuple{T}, false),
    (gnd_equal, Tuple{T, T}, false), (atomic_compare, Tuple{T, T}, false),
    (mk_var, Tuple{Type{T}, UInt64}, false), (var_term, Tuple{Type{T}, UInt64}, false),
    (LK._no_children, Tuple{Type{T}}, true),
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
    # =@= (src/pl-variant.jl)
    (LK.push_start_args, Tuple{T, T}, false),
    (LK.push_args!, Tuple{LK.argPairs{T}, T, T, Int, Int}, false),
    (LK.variant_next_arg!, Tuple{LK.argPairs{T}}, false),
    (LK._variant_functor, Tuple{T, T}, true),
    (LK.variant, Tuple{LK.argPairs{T}}, false),
    (LK.is_variant_ptr, Tuple{T, T}, false),
    # =@= and the standard order UNDER BINDINGS (V5a; src/pl-variant.jl, src/pl-prims.jl)
    (LK.variant_buffer{T}, Tuple{}, false),
    (LK.var_id, Tuple{LK.variant_buffer{T}, T}, false),
    (LK.term_id, Tuple{LK.variant_buffer{T}, T}, false),
    (LK.Root, Tuple{LK.variant_buffer{T}, Int}, true),
    (LK._variant_same_atomic, Tuple{T, T}, false),
    (LK.isomorphic, Tuple{LK.PL_local_data{T}, LK.variant_buffer{T}, Int, Int}, false),
    (LK.variant, Tuple{LK.PL_local_data{T}, LK.argPairs{T}, LK.variant_buffer{T}}, false),
    (LK.is_variant_ptr, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.do_compare, Tuple{LK.PL_local_data{T}, T, T, Bool, Int}, false),
    (LK.compare_fast, Tuple{LK.PL_local_data{T}, T, T, Int}, false),
    (LK.compare_descend, Tuple{LK.PL_local_data{T}, T, T, Int}, false),
    (LK.ph_acyclic_mark, Tuple{LK.PL_local_data{T}, T}, false),
    (LK.is_acyclic, Tuple{LK.PL_local_data{T}, T}, false),
    (LK.compare_std, Tuple{LK.PL_local_data{T}, T, T, Int}, false),
    (compareStandard, Tuple{LK.PL_local_data{T}, T, T, Bool}, false),
    # the pre-order term walk (src/pl-termwalk.jl)
    (LK.ac_initTermAgenda, Tuple{T}, false),
    (LK.ac_nextTermAgenda, Tuple{LK.ac_term_agenda{T}}, false),
    (LK.ac_pushTermAgenda, Tuple{LK.ac_term_agenda{T}, T}, false),
    # term_hash, variant_sha1, variant_hash (src/pl-termhash.jl)
    (LK.primitiveHashValue, Tuple{T, UInt32}, true),
    (LK.th_start_term, Tuple{T, Int}, false),
    (LK.th_next_arg!, Tuple{Base.RefValue{Int}, Vector{LK.th_data{T}}}, true),
    (LK.termHashValue, Tuple{T}, false), (LK.pl_term_hash, Tuple{T}, false),
    (LK.variant_sha1_walk!, Tuple{LK.ac_term_agenda{T}, LK.sha1_state}, false),
    (LK.variant_hash_walk, Tuple{T, LK.hash_algo}, false),
    (LK.variant_hash, Tuple{T, LK.hash_algo}, false),
    (LK.pl_variant_sha1, Tuple{T}, false), (LK.pl_variant_hash, Tuple{T}, false),
    # the plain and two-term agendas (src/pl-termwalk.jl)
    (LK.initTermAgenda!, Tuple{LK.term_agenda{T}, Int, T, Int}, true),
    (LK.clearTermAgenda!, Tuple{LK.term_agenda{T}}, true),
    (LK.nextTermAgendaNoDeRef!, Tuple{LK.term_agenda{T}}, true),
    (LK.nextTermAgenda!, Tuple{LK.PL_local_data{T}, LK.term_agenda{T}}, true),
    (LK.pushWorkAgenda!, Tuple{LK.term_agenda{T}, Int, T, Int}, false),
    (LK.initTermAgendaLR!, Tuple{LK.term_agendaLR{T}, Int, T, T, Int}, true),
    (LK.clearTermAgendaLR!, Tuple{LK.term_agendaLR{T}}, true),
    (LK.nextTermAgendaLR!, Tuple{LK.term_agendaLR{T}}, true),
    (LK.pushWorkAgendaLR!, Tuple{LK.term_agendaLR{T}, Int, T, T, Int}, false),
    # bindings (src/pl-inline.jl) and unification (src/pl-prims.jl)
    (LK.PL_local_data{T}, Tuple{}, false),
    (LK.deRef, Tuple{LK.PL_local_data{T}, T}, true),
    (LK.Trail!, Tuple{LK.PL_local_data{T}, UInt64, T}, false),
    (LK.Mark, Tuple{LK.PL_local_data{T}}, true),
    (LK.Undo!, Tuple{LK.PL_local_data{T}, LK.mark}, true),
    (LK.linkTermsCyclic!, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.exitCyclic!, Tuple{LK.PL_local_data{T}}, false),
    (LK._cyclic_deref, Tuple{LK.PL_local_data{T}, T}, false),
    (LK._unify_functor, Tuple{T, T}, true),
    (LK.unify_simple_ptrs, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.do_unify, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.raw_unify_ptrs, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.unify_ptrs, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.can_unify, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK._same_cell, Tuple{T, T}, true),
    (LK.var_occurs_in, Tuple{LK.PL_local_data{T}, T, T}, false),
    (
        LK.failed_unify_with_occurs_check,
        Tuple{LK.PL_local_data{T}, T, T, LK.occurs_check_t},
        false
    ),
    (
        LK.unify_with_occurs_check!,
        Tuple{LK.PL_local_data{T}, T, T, LK.occurs_check_t},
        false
    ),
    (LK.pl_unify!, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.pl_not_unify, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.pl_unify_with_occurs_check!, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.pl_can_compare, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.unifiable_occurs_check, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.unify_all_trail_ptrs, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.unifiable, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.pl_unifiable, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.resolve_term, Tuple{LK.PL_local_data{T}, T}, false),
    # the local stack (V3): growing allocates; the record discipline, choice points and foreign
    # frames do not
    (LK.growStacks!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK._grow_pool!, Tuple{LK.PL_local_data{T}, Vector{LK.localFrame{T}}, Int}, false),
    (LK._grow_pool!, Tuple{LK.PL_local_data{T}, Vector{LK.choice{T}}, Int}, false),
    (LK._grow_pool!, Tuple{LK.PL_local_data{T}, Vector{LK.fliFrame}, Int}, false),
    (LK.growLocalSpace, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK.ensureLocalSpace, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.raiseStackOverflow, Tuple{LK.PL_local_data{T}, LK.boolex_t}, false),
    (LK.hasLocalSpace, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.DiscardMark, Tuple{LK.PL_local_data{T}, LK.mark}, true),
    (LK.linkValI, Tuple{LK.PL_local_data{T}, T}, true),
    (LK.pushFrame!, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.pushChoice!, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.pushFliFrame!, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.fliFrameOfFid, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.dropRecords!, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.lowerLTop!, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.newChoice, Tuple{LK.PL_local_data{T}, LK.choice_type, Int}, true),
    (LK.copyFrameArguments, Tuple{LK.PL_local_data{T}, Int, Int, Int}, true),
    (LK.open_foreign_frame, Tuple{LK.PL_local_data{T}}, true),
    (LK.PL_close_foreign_frame, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.PL_open_foreign_frame, Tuple{LK.PL_local_data{T}}, false),
    (LK.PL_rewind_foreign_frame, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.PL_discard_foreign_frame, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.PL_new_term_refs, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.new_term_ref, Tuple{LK.PL_local_data{T}}, false),
    (LK.PL_new_term_ref, Tuple{LK.PL_local_data{T}}, false),
    (LK.PL_reset_term_refs, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.PL_copy_term_ref, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.PL_put_term, Tuple{LK.PL_local_data{T}, Int, Int}, true),
    (LK.emptyStacks!, Tuple{LK.PL_local_data{T}}, false),
    (LK.levelFrame, Tuple{LK.localFrame{T}}, true),
    (LK.setLevelFrame, Tuple{LK.localFrame{T}, UInt32}, true),
    (LK.setNextFrameFlags, Tuple{LK.localFrame{T}, LK.localFrame{T}}, true),
    (LK.lcoSetNextFrameFlags2, Tuple{LK.localFrame{T}, LK.localFrame{T}}, true),
    (LK.lcoSetNextFrameFlags, Tuple{LK.localFrame{T}}, true),
    (LK.tcallSetNextFrameFlags, Tuple{LK.localFrame{T}}, true),
    (LK.setFramePredicate, Tuple{LK.localFrame{T}, LK.Definition{T}}, true),
    # Base methods on the default type
    (Base.:(==), Tuple{T, T}, false), (Base.hash, Tuple{T, UInt}, false),
    (Base.show, Tuple{IOBuffer, T}, false)
)

# A concrete stand-in for the sink `pl_retract!` and `pl_clause!` take: a singleton function type,
# as a real caller's is.
_manifest_sink(cl) = true

# The clause index, its head compiler and the clause database (src/pl-incl.jl, pl-funct.jl,
# pl-global.jl, pl-inline.jl, pl-vmi.jl, pl-comp.jl, pl-index.jl, pl-thread.jl, pl-gc.jl,
# pl-proc.jl), every method once, over term type T. The entry points are also checked for the other two payload
# types (`_index_entry_points`); JET follows their callees.
function _manifest_index(T)
    D, C, CL = LK.Definition{T}, LK.Clause{T}, LK.ClauseList{T}
    CR, CB, CI = LK.ClauseRef{T}, LK.ClauseBucket{T}, LK.ClauseIndex{T}
    CH, CTX = LK.ClauseChoice{T}, LK.index_context{T}
    GD, LD, DDI = LK.PL_global_data{T}, LK.PL_local_data{T}, LK.dirty_def_info{T}
    SNK = typeof(_manifest_sink)
    CIP = Vector{Union{Nothing, CI}}
    NT4, NT8, NTW = NTuple{4, UInt8}, NTuple{8, UInt8}, NTuple{4, UInt64}
    CInfo, HA, HH = LK.compileInfo{T}, LK.hash_assessment, LK.hash_hints
    PR, MOD = LK.Procedure{T}, LK.module_t{T}
    PCd = LK.Code{T}
    AT, AF = LK.argv_term{LK.PL_local_data{T}, T}, LK.argv_frame{LK.PL_local_data{T}}
    ARGP, ASE = LK.argp_t{T}, LK.argstack_entry{T}
    VIEW = typeof(view(UInt8[], 1:0))
    return (
        # src/pl-comp.jl — the head compiler, its literal table and the code readers
        (LK.PC, Tuple{CInfo}, true), (LK.initMerge!, Tuple{CInfo}, true),
        (LK.mergeInstructions!, Tuple{CInfo, NTuple{4, LK.vmi_merge}, UInt64}, false),
        (LK.Output_0!, Tuple{CInfo, UInt64}, false),
        (LK.Output_a!, Tuple{CInfo, UInt64}, false),
        (LK.Output_1!, Tuple{CInfo, UInt64, UInt64}, false),
        (LK.Output_2!, Tuple{CInfo, UInt64, UInt64, UInt64}, false),
        (LK.Output_3!, Tuple{CInfo, UInt64, UInt64, UInt64, UInt64}, false),
        (LK.Output_an!, Tuple{CInfo, NTuple{1, UInt64}, Int}, false),
        (LK.Output_n!, Tuple{CInfo, UInt64, NTuple{1, UInt64}, Int}, false),
        (LK.addLiteral!, Tuple{CInfo, T}, false),
        (LK.addProcedure!, Tuple{CInfo, PR}, false),
        (LK._body_functor, Tuple{Type{T}, T}, true),
        (LK.lookupBodyProcedure, Tuple{GD, T, MOD}, false),
        (LK.Code, Tuple{C, Int}, true),
        (LK.decode, Tuple{PCd}, true), (LK.stepPC, Tuple{PCd}, true),
        (LK.skipArgs, Tuple{PCd, Int, Int}, true), (LK.argKey, Tuple{PCd, Int}, true),
        (LK.indexableCompound, Tuple{PCd}, true),
        (LK.isIndexedVarTerm, Tuple{CInfo, T}, false),
        (LK._comp_arg, Tuple{T, Int, Int}, true),
        (LK._comp_shape, Tuple{T}, true), (LK._gnd_code, Tuple{T, Int}, true),
        (LK.isFirstVarP, Tuple{CInfo, T}, true),
        (LK.compileListFF!, Tuple{CInfo, T}, false),
        (LK.compileInfo{T}, Tuple{Int, MOD, PR}, false),
        (LK.pushBranchVar!, Tuple{CInfo, LK.VarDef}, false),
        (LK._max_frame_size, Tuple{}, false),
        (LK.analyseVariables2!, Tuple{GD, CInfo, T, Int, Int, Bool}, false),
        (LK.analyse_variables!, Tuple{GD, CInfo, T, Nothing}, false),
        (LK.analyse_variables!, Tuple{GD, CInfo, T, T}, false),
        (LK._compile_clause_head!, Tuple{GD, CInfo, T, Nothing}, false),
        (LK._compile_clause_head!, Tuple{GD, CInfo, T, T}, false),
        (LK.compileArgument!, Tuple{CInfo, T, Int}, false),
        (LK.reverse_code!, Tuple{Vector{UInt64}, Int, Int}, true),
        (LK.lco!, Tuple{CInfo, Int}, false),
        (LK.compileSubClause!, Tuple{GD, LD, CInfo, T, UInt64}, false),
        (LK.compileBody!, Tuple{GD, LD, CInfo, T, UInt64}, false),
        # V6b — the type tests compiled inline (src/pl-comp.jl, pl-incl.jl, pl-fli.jl)
        (LK.always, Tuple{LD, CInfo, Bool, String, T}, false),
        (LK.compileBodyVar1, Tuple{LD, CInfo, T}, false),
        (LK.compileBodyNonVar1, Tuple{LD, CInfo, T}, false),
        (LK._type_test, Tuple{Int, T}, true),
        (LK.compileTypeTest, Tuple{LD, CInfo, T, Int}, false),
        (LK.compileBodyTypeTest, Tuple{LD, LK.SubClauseNames, UInt64, CInfo, T}, false),
        # V6b2 — the other goals compiled inline (src/pl-comp.jl, pl-incl.jl); since V9a the
        # unification family emits (`skippedVar!` too), the others refuse (V9); the tests allocate
        # nothing
        (LK._comp_void, Tuple{CInfo, T}, true), (LK._comp_ivar, Tuple{CInfo, T}, true),
        (LK.compileBodyUnify, Tuple{LD, CInfo, T}, false),
        (LK.compileBodyEQ, Tuple{LD, CInfo, T}, false),
        (LK.compileBodyNEQ, Tuple{LD, CInfo, T}, false),
        (LK.compileBodyArg3, Tuple{CInfo, T}, false),
        (LK.compileBodyCallContinuation, Tuple{CInfo, T}, false),
        (LK.compileBodyShift, Tuple{CInfo, T, Bool}, false),
        (LK.skippedVar!, Tuple{CInfo, T}, false),
        # V9b — the unifications moved into the head (src/pl-comp.jl)
        (LK.is_argument_var, Tuple{CInfo, T}, false),
        (LK.annotate_unify!, Tuple{CInfo, T, T}, false),
        (LK.annotate_unification!, Tuple{CInfo, T}, false),
        (LK.argUnifiedTo, Tuple{LK.VarDef}, true),
        (LK.argMoveUnify!, Tuple{CInfo, LK.VarDef}, false),
        (LK.isUnifiedArg, Tuple{CInfo, LK.VarDef}, true),
        (LK.is_portable_constant, Tuple{LD, T}, true),
        (LK.isAtom, Tuple{T}, true), (LK.isTaggedInt, Tuple{T}, true),
        # V6c2 — arithmetic in a body (src/pl-comp.jl, pl-funct.jl)
        (LK.compileSimpleAddition, Tuple{LD, LK.SubClauseNames, T, CInfo}, false),
        (LK.canBind, Tuple{T}, true), (LK.isTextAtom, Tuple{T}, true),
        (LK.isCallableAtom, Tuple{T}, true),
        (LK.isRational, Tuple{T}, true), (LK.isFloat, Tuple{T}, true),
        (LK.isString, Tuple{T}, true), (LK.isTerm, Tuple{T}, true),
        (LK.isInteger, Tuple{T}, true), (LK.isNumber, Tuple{T}, true),
        (LK.isAtomic, Tuple{T}, true), (LK.isCallable, Tuple{T}, true),
        (LK._is_rule_body, Tuple{GD, Nothing}, true),
        (LK._is_rule_body, Tuple{GD, T}, true),
        (LK.compileClause, Tuple{GD, LD, T, Nothing, PR, MOD}, false),
        (LK.compileClause, Tuple{GD, LD, T, T, PR, MOD}, false),
        # src/pl-funct.jl — the control functors the global data holds
        (LK.registerControlFunctors, Tuple{Type{T}}, false),
        (LK._subclause_names, Tuple{Type{T}}, false),
        (LK._name_key, Tuple{Type{T}, String}, false),
        (LK._arith_functors, Tuple{Type{T}}, false),
        (LK._has_functor, Tuple{T, UInt64, Int}, true),
        (LK._is_control, Tuple{T, LK.ControlFunctors}, true),
        # src/pl-index.jl
        (LK.STATIC_RELOADING, Tuple{D}, true), (LK.cref_matches, Tuple{CR, UInt64}, true),
        (LK.is_clean_predicate, Tuple{D}, true), (LK.visibleClause, Tuple{C, UInt64}, true),
        (LK.visibleClauseCNT, Tuple{C, UInt64}, true),
        (LK.canIndex, Tuple{T}, true), (LK.indexOfWord, Tuple{T}, true),
        (LK.ISDEADCI, Tuple{CI}, true), (LK.ISDEADCI, Tuple{Nothing}, true),
        (LK.next_clause_unindexed!, Tuple{CTX}, true),
        (LK.next_clause_primary_index!, Tuple{CTX}, true),
        (LK.nextClauseFromList!, Tuple{CI, AT, CTX}, false),
        (LK.nextClauseFromList!, Tuple{CI, AF, CTX}, false),
        (LK.nextClauseFromBucket!, Tuple{CI, AT, CTX}, false),
        (LK.nextClauseFromBucket!, Tuple{CI, AF, CTX}, false),
        (LK.setClauseChoice!, Tuple{CR, CTX}, true),
        (LK.setClauseChoice!, Tuple{Nothing, CTX}, true),
        (LK.indexKeyFromArgv, Tuple{CI, AT}, true),
        (LK.indexKeyFromArgv, Tuple{CI, AF}, true),
        (LK.is_var, Tuple{T}, true),
        (LK.is_satifies_index, Tuple{CI, AT}, true),
        (LK.is_satifies_index, Tuple{CI, AF}, true),
        (LK.existing_hash, Tuple{CIP, AT}, false),
        (LK.existing_hash, Tuple{CIP, AF}, false),
        (LK.createIndex!, Tuple{AT, Int, CL, CI, CTX}, false),
        (LK.createIndex!, Tuple{AT, Int, CL, Nothing, CTX}, false),
        (LK.createIndex!, Tuple{AF, Int, CL, CI, CTX}, false),
        (LK.createIndex!, Tuple{AF, Int, CL, Nothing, CTX}, false),
        (LK.first_clause_guarded!, Tuple{AT, Int, CL, CTX}, false),
        (LK.first_clause_guarded!, Tuple{AF, Int, CL, CTX}, false),
        (LK.firstClause!, Tuple{LD, AT, UInt64, D, CH}, false),
        (LK.firstClause!, Tuple{LD, AF, UInt64, D, CH}, false),
        (LK.nextClause!, Tuple{LD, CH, AT, UInt64, D}, true),
        (LK.nextClause!, Tuple{LD, CH, AF, UInt64, D}, true),
        (LK.argv_at, Tuple{AT, Int}, true), (LK.argv_at, Tuple{AF, Int}, true),
        (LK._index_context!, Tuple{LK.index_context{T}, UInt64, D, CH}, true),
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
        (LK.bestHash!, Tuple{AT, Int, CL, Nothing, HH, CTX}, false),
        (LK.bestHash!, Tuple{AT, Int, CL, CI, HH, CTX}, false),
        (LK.bestHash!, Tuple{AF, Int, CL, Nothing, HH, CTX}, false),
        (LK.bestHash!, Tuple{AF, Int, CL, CI, HH, CTX}, false),
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
        # removing clauses from indexes, clause GC of index buckets (src/pl-index.jl)
        (LK.shrunkpow2!, Tuple{D}, true), (LK.gcClauseList!, Tuple{CL, DDI, UInt64}, true),
        (LK.gcClauseBucket!, Tuple{D, CB, UInt32, Bool, DDI, UInt64}, true),
        (LK.cleanClauseIndex!, Tuple{D, CL, CI, DDI, UInt64}, false),
        (LK.cleanClauseIndexes!, Tuple{D, CL, DDI, UInt64}, false),
        (LK.deleteActiveClauseFromBucket!, Tuple{CB, UInt64}, true),
        (LK.deleteActiveClauseFromIndex!, Tuple{CI, C}, true),
        (LK.deleteActiveClauseFromIndexes!, Tuple{D, C}, false),
        # src/pl-incl.jl, src/pl-inline.jl
        (LK.GLOBALLY_VISIBLE_CLAUSE, Tuple{C, UInt64}, true),
        (LK.global_generation, Tuple{GD}, true),
        (LK.current_generation, Tuple{GD, D}, true),
        (LK.next_generation!, Tuple{GD, D}, true), (LK.max_generation, Tuple{D}, true),
        (LK.setGenerationFrame, Tuple{GD, D}, true),
        # src/pl-thread.jl, src/pl-gc.jl
        (LK.cgcActivatePredicate!, Tuple{GD, D, UInt64}, false),
        (LK.pushPredicateAccessObj!, Tuple{LD, GD, D}, false),
        (LK.popPredicateAccess!, Tuple{LD, D}, false),
        (LK.markAccessedPredicates!, Tuple{LD, GD}, false),
        (LK.markPredicatesInEnvironments!, Tuple{LD, GD}, false),
        # clause/2 (src/pl-comp.jl)
        (LK.pl_clause!, Tuple{GD, LD, D, T, SNK}, false),
        (LK.decompileHead!, Tuple{LD, C, T}, false),
        (LK.decompile_head!, Tuple{LD, C, T, UInt64}, false),
        (
            LK._decompile_void,
            Tuple{Type{T}, Vector{LK.DecompileFrame{T}}, UInt64, Int},
            false
        ),
        (LK._decompile_void, Tuple{Type{T}, Nothing, UInt64, Int}, false),
        # src/pl-proc.jl
        (LK.MODULE_user, Tuple{GD}, true),
        (LK.lookupProcedure, Tuple{T, Int, MOD}, false),
        (LK.isCurrentProcedure, Tuple{UInt64, Int, MOD}, false),
        (LK.hasClausesDefinition, Tuple{GD, D}, true),
        (LK.isDefinedProcedure, Tuple{GD, PR}, true),
        (LK.setDynamicDefinition!, Tuple{D, Bool}, true),
        (LK.newClauseRef, Tuple{C, UInt64}, false),
        (LK.assertDefinition!, Tuple{GD, D, C, Int}, false),
        (LK.assertDefinition!, Tuple{GD, D, C, CR}, false),
        (LK.retract_clause!, Tuple{GD, C, UInt64}, false),
        (LK.retractClauseDefinition!, Tuple{GD, D, C, Bool}, false),
        (LK.find_prev, Tuple{D, CR, CR}, true), (LK.find_prev, Tuple{D, Nothing, CR}, true),
        (LK.cleanDefinition!, Tuple{D, DDI, UInt64}, false),
        (LK.mustCleanDefinition, Tuple{D}, true), (LK.ddi_new, Tuple{D}, false),
        (LK.ddi_reset!, Tuple{DDI}, true), (LK.ddi_contains_gen, Tuple{DDI, UInt64}, true),
        (LK.ddi_to_intervals!, Tuple{DDI, UInt64}, true),
        (LK.ddi_interval_add_access_gen!, Tuple{DDI, UInt64}, true),
        (LK.ddi_add_access_gen!, Tuple{DDI, UInt64}, true),
        (LK.ddi_is_garbage, Tuple{DDI, UInt64, C}, true),
        (LK.ddi_oldest_generation, Tuple{DDI}, true),
        (LK.registerDirtyDefinition!, Tuple{GD, D}, false),
        (LK.unregisterDirtyDefinition!, Tuple{GD, D}, false),
        (LK.maybeUnregisterDirtyDefinition!, Tuple{GD, D}, false),
        (LK.pl_garbage_collect_clauses!, Tuple{GD, LD}, false),
        (LK.pl_retract!, Tuple{GD, LD, D, T, SNK}, false),
        (LK.allVars, Tuple{T}, false),
        (LK.pl_retractall!, Tuple{GD, LD, D, T}, false),
        (LK.mode_arg_is_unbound, Tuple{D, Int}, true),
        # the supervisors (src/pl-supervisor.jl): selecting one builds its code, so allocates
        (LK.arg1Key, Tuple{PCd}, true),
        (LK._shared_supervisor, Tuple{LK.PL_code_data, Vector{LK.code}}, true),
        (LK.freeSupervisor, Tuple{D, Vector{LK.code}, Bool}, true),
        (LK.freeCodesDefinition!, Tuple{D, Bool}, true),
        (
            LK.equalSupervisors,
            Tuple{
                LK.PL_code_data, Vector{LK.code}, Vector{CR}, Vector{LK.code}, Vector{CR}
            },
            true
        ),
        (LK.getClauses, Tuple{GD, D, Vector{CR}, Int}, false),
        (LK.undefSupervisor, Tuple{D}, false),
        (LK.singleClauseSupervisor, Tuple{GD, D}, false),
        (LK.listSupervisor, Tuple{GD, D}, false), (LK.dynamicSupervisor, Tuple{D}, false),
        (LK.multifileSupervisor, Tuple{D}, false), (LK.staticSupervisor, Tuple{D}, false),
        (LK.chainPredicateSupervisor, Tuple{D, Tuple{Vector{LK.code}, Vector{CR}}}, true),
        (LK.createSupervisor, Tuple{GD, D}, false),
        (LK.setDefaultSupervisor, Tuple{GD, D}, false),
        # V4a — the run loop and the query API (src/pl-wam.jl, pl-inline.jl, pl-alloc.jl, pl-fli.jl,
        # pl-error.jl, pl-gc.jl), over DefaultTerm only: `PL_error` builds `Name/Arity` with
        # `mk_gnd(T, ::Int)`, which a payload without integers (`Term{Float64}`) cannot hold; the
        # other implementations run it in the suites. The ARGP value, the register save and load and
        # the record discipline allocate nothing (decision 2); the argument stack's push allocates
        # only where it grows — checked by its own AllocCheck test (static_analysis_body.jl).
        (LK.generationFrame, Tuple{LK.localFrame{T}}, true),
        (LK.isFrame, Tuple{LK.localFrame{T}}, true),
        (LK.setGenerationFrame, Tuple{GD, LD, Int}, true),
        (LK.QueryFromQid, Tuple{LD, Int}, true), (LK.QidFromQuery, Tuple{LD, Int}, true),
        (LK.pushArgumentStack, Tuple{LD, ASE}, false),
        (LK.f_pushArgumentStack, Tuple{LD, ASE}, false),
        (LK.pushQuery!, Tuple{LD, Int}, true),
        (LK._grow_pool!, Tuple{LD, Vector{LK.queryFrame{T}}, Int}, false),
        (LK.is_exception_finish, Tuple{LK.finished}, true),
        (LK.leaveFrame, Tuple{LD, Int}, true), (LK.discardFrame, Tuple{LD, Int}, true),
        (LK.discardChoicesAfter, Tuple{LD, Int, LK.finished}, true),
        (LK.dbg_discardChoicesAfter, Tuple{LD, Int, LK.finished}, true),
        (LK.queryOfFrame, Tuple{LD, Int}, true), (LK.parentFrame, Tuple{LD, Int}, true),
        (LK.setLTop!, Tuple{LD, Int}, true),
        (LK._argp_raw, Tuple{LD, ARGP}, true), (LK._argp_deref, Tuple{LD, ARGP}, true),
        (LK._argp_store!, Tuple{LD, ARGP, T}, true), (LK._argp_add, Tuple{ARGP, Int}, true),
        (LK._reset_argument_stack!, Tuple{LD, LK.queryFrame{T}}, true),
        (LK._bopen!, Tuple{LD, Int, T, Bool, Int, Int, T}, false),
        (LK._bclose!, Tuple{LD}, false),
        (LK._fresh_compound, Tuple{Type{T}, T, Bool, Int}, false),
        (LK._slow_unify, Tuple{LD}, true),
        (LK._is_expr3, Tuple{T}, true),
        (
            LK._save_registers!,
            Tuple{LD, Int, Int, ARGP, Vector{LK.code}, Vector{T}, Int},
            true
        ),
        (LK._load_registers!, Tuple{LD, Int}, true),
        (LK.resumeAfterException, Tuple{LD, Bool}, false),
        (LK.initVM, Tuple{PR}, false),
        (LK.PL_open_query, Tuple{GD, LD, Nothing, UInt32, PR, Int}, false),
        (LK.PL_open_query, Tuple{GD, LD, MOD, UInt32, PR, Int}, false),
        (LK.discard_query, Tuple{LD, Int}, false),
        (LK.restore_after_query, Tuple{LD, Int}, false),
        (LK._end_query, Tuple{LD, Int, Bool}, false),
        (LK.PL_cut_query, Tuple{LD, Int}, false),
        (LK.PL_close_query, Tuple{LD, Int}, false),
        (LK.PL_exception, Tuple{LD, Int}, false), (LK.PL_current_query, Tuple{LD}, true),
        (LK.PL_next_solution, Tuple{GD, LD, Int}, false),
        (LK.PL_next_solution_guarded, Tuple{GD, LD, Int, Bool}, false),
        (LK._abandon_query, Tuple{LD, Int}, false),
        (LK._check_foreign_environment, Tuple{LD, String}, true),
        (LK.PL_raise_exception, Tuple{LD, Int}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, T, T}, false),
        # V5a2 — the built-in call path (src/pl-ext.jl, pl-trace.jl, pl-error.jl, pl-fli.jl,
        # pl-supervisor.jl, pl-wam.jl, pl-prims.jl, pl-variant.jl), over DefaultTerm only, as V4a's
        (LK.PL_error, Tuple{LD, LK.PL_error_code}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, T, Int}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, String, Int}, false),
        (LK._PL_error_open, Tuple{LD}, false),
        (LK._PL_error_close!, Tuple{LD, Union{Nothing, D}, Int, Int, Int, Int}, false),
        (LK.PL_type_error, Tuple{LD, String, Int}, false),
        (LK.PL_domain_error, Tuple{LD, String, Int}, false),
        (LK.PL_is_variable, Tuple{LD, Int}, true),
        (LK.PL_unify, Tuple{LD, Int, Int}, false),
        (LK.PL_unify_atomic, Tuple{LD, Int, T}, false),
        (LK.PL_unify_atom, Tuple{LD, Int, T}, false),
        (LK.PL_unify_integer, Tuple{LD, Int, Int}, false),
        (LK.PL_put_intptr, Tuple{LD, Int, Int}, false),
        (LK.PL_compare, Tuple{LD, Int, Int}, false),
        (LK.PL_clear_exception, Tuple{LD}, false),
        (LK.PL_clear_foreign_exception, Tuple{LD, Int}, false),
        (LK.vmi_fopen, Tuple{LD, Int, D}, true),
        (LK.error_foreign_return_code, Tuple{LD, UInt}, false),
        (LK.createForeignSupervisor!, Tuple{D, Int}, false),
        (LK.builtin_pred_flags, Tuple{UInt8, UInt64}, true),
        (LK.registerBuiltins!, Tuple{GD, Vector{Tuple{String, Int, UInt8}}, Int}, false),
        (LK.initBuildIns!, Tuple{GD}, false),
        (LK.setBuiltinPredicateProperties!, Tuple{GD}, false),
        (LK._fcall_va, Tuple{Int, LD, Int, Int, LK.foreign_context{T}}, false),
        (LK._fcall_det, Tuple{Int, LD, Int}, false),
        (LK.MODULE_system, Tuple{GD}, true),
        (LK.PL_unify_frame, Tuple{LD, Int, Int}, false),
        (LK.PL_unify_choice, Tuple{LD, Int, Int}, false),
        (LK.pl_prolog_current_frame, Tuple{LD, Int}, false),
        (LK.can_unify, Tuple{LD, T, T, Int}, false),
        (LK.unifiable, Tuple{LD, Int, Int, Int}, false),
        [
            (f, Tuple{LD, Int, Int, LK.foreign_context{T}}, false) for f in (
                LK.pl_unify2_va, LK.pl_not_unify2_va, LK.pl_unify_with_occurs_check2_va,
                LK.pl_equal2_va, LK.pl_compare3_va, LK.pl_can_compare2_va,
                LK.pl_unifiable3_va,
                LK.pl_variant2_va, LK.pl_prolog_current_choice1_va,
                # V6b: the type checks and \\== (src/pl-prims.jl)
                LK.pl_nonvar1_va, LK.pl_var1_va, LK.pl_integer1_va, LK.pl_float1_va,
                LK.pl_rational1_va, LK.pl_string1_va, LK.pl_number1_va, LK.pl_atom1_va,
                LK.pl_atomic1_va, LK.pl_compound1_va, LK.pl_callable1_va, LK.pl_nonequal2_va
            )
        ]...,
        [
            (f, Tuple{LD, Int}, true) for f in (
                LK.PL_is_integer, LK.PL_is_float, LK.PL_is_rational, LK.PL_is_compound,
                LK.PL_is_callable, LK.PL_is_string, LK.PL_is_atom, LK.PL_is_atomic,
                LK.PL_is_number
            )
        ]...,
        # V5b — the exception path's entries (src/pl-error.jl, pl-fli.jl, pl-modul.jl), over
        # DefaultTerm only, as V4a's: the undefined procedure's error and the exception classes
        (LK.PL_error, Tuple{LD, LK.PL_error_code, D, Union{Nothing, D}}, false),
        (LK._hasFunctor, Tuple{T, T, Int}, true),
        (LK.classify_exception_p, Tuple{LD, T}, false),
        (LK.classify_exception, Tuple{LD, Int}, false),
        (LK.getUnknownModule, Tuple{MOD}, true),
        # V6c — arithmetic (src/pl-gmp.jl, pl-arith.jl, pl-error.jl), over DefaultTerm only, as V4a's:
        # its big results raise (the interim for Q-AR1), folded at compile time (`_holds_payload`)
        [
            (f, Tuple{T, LK.number}, false) for f in (LK.get_rational, LK.get_number)
        ]...,
        (LK.put_mpz, Tuple{Type{T}, BigInt}, false),
        (LK._put_big, Tuple{Type{T}, BigInt}, false),
        (LK._put_big, Tuple{Type{T}, Rational{BigInt}}, false),
        (LK.put_number, Tuple{Type{T}, LK.number}, false),
        (LK.PL_unify_number, Tuple{LD, Int, LK.number}, false),
        (LK.promoteToMPZNumber, Tuple{LK.number}, false),
        (LK.promoteToMPQNumber, Tuple{LD, LK.number}, false),
        (LK.promoteToFloatNumber, Tuple{LD, LK.number}, false),
        (LK.promoteNumber, Tuple{LD, LK.number, LK.numtype}, false),
        (LK.make_same_type_numbers, Tuple{LD, LK.number, LK.number}, false),
        (LK.same_type_numbers, Tuple{LD, LK.number, LK.number}, false),
        (LK._mpz_get_d, Tuple{BigInt}, false), (LK._mpz_tstbit, Tuple{BigInt, Int}, false),
        (LK._sa_minus_scan1, Tuple{BigInt, Int}, false),
        (LK.mpz_to_double, Tuple{BigInt}, false),
        (LK.mpz_fdiv, Tuple{BigInt, BigInt}, false),
        (LK.mpq_to_double, Tuple{Rational{BigInt}}, false),
        (LK.cmpFloatNumbers, Tuple{LK.number, LK.number}, false),
        (LK.cmpNumbers, Tuple{LD, LK.number, LK.number}, false),
        (LK._holds_payload, Tuple{Type{T}, Type{BigInt}}, true),
        (LK._number_alloc!, Tuple{LD}, false), (LK._number_free!, Tuple{LD, Int}, true),
        (LK.cpNumber, Tuple{LK.number, LK.number}, true),
        (LK.check_float, Tuple{LD, LK.number}, false),
        (LK.check_mpq, Tuple{LK.number}, true),
        (LK.check_int_bits, Tuple{LD, UInt64}, true),
        # V8 — the integer size checks (GMP aborts where upstream does not check), A_ADD_FC's slow
        # path, the shifts and ERR_AR_TYPE
        (LK.int_too_big, Tuple{LD}, false),
        (LK.int_bits_ok, Tuple{LD, UInt64}, true),
        (LK.maxBigIntSize, Tuple{LD}, true),
        (LK.ar_add_si, Tuple{LD, LK.number, Int64}, false),
        (LK.double_in_int64_range, Tuple{Float64}, true),
        (LK.toIntegerNumber, Tuple{LD, LK.number, Int}, false),
        (LK.ar_sign_i, Tuple{LK.number}, true),
        (LK.shift_to_far, Tuple{LD, LK.number, LK.number, Int}, false),
        (LK.MSB64, Tuple{Int64}, true),
        (LK.ar_shift, Tuple{LD, LK.number, LK.number, LK.number, Int}, false),
        [
            (f, Tuple{LD, LK.number, LK.number, LK.number}, false) for
            f in (LK.ar_shift_left, LK.ar_shift_right)
        ]...,
        (
            LK.PL_error,
            Tuple{LD, String, Int, String, LK.PL_error_code, T, LK.number},
            false
        ),
        (LK.promoteIntNumber, Tuple{LK.number}, false),
        [
            (f, Tuple{LD, LK.number, LK.number, LK.number}, false) for
            f in (LK.pl_ar_add, LK.ar_minus, LK.ar_mul)
        ]...,
        (LK.mul64, Tuple{Int64, Int64}, true),
        (LK.ar_u_minus, Tuple{LK.number, LK.number}, false),
        (LK.ar_u_plus, Tuple{LK.number, LK.number}, true),
        (LK.isCurrentArithFunction, Tuple{Type{T}, UInt64, Int}, false),
        (LK._ar_call2, Tuple{LD, Int, LK.number, LK.number, LK.number}, false),
        (LK._ar_call1, Tuple{Int, LK.number, LK.number}, false),
        (LK.arithChar, Tuple{LD, T}, false),
        (LK.getCharExpression, Tuple{LD, T, LK.number}, false),
        (LK._len_not_one, Tuple{LD, T}, false),
        (LK.evalExpression, Tuple{LD, Int, LK.number}, false),
        (LK._ar_type_error, Tuple{LD, Symbol, T}, false),
        (LK.valueExpression, Tuple{LD, Int, LK.number}, false),
        (LK.ar_compare, Tuple{LD, LK.number, LK.number, Int}, false),
        (LK.compareNumbers, Tuple{LD, Int, Int, Int}, false),
        [
            (f, Tuple{LD, Int, Int, LK.foreign_context{T}}, false) for f in (
                LK.pl_is2_va, LK.pl_lt2_va, LK.pl_gt2_va, LK.pl_leq2_va, LK.pl_geq2_va,
                LK.pl_neq2_va, LK.pl_eq2_va
            )
        ]...,
        (LK.PL_error, Tuple{LD, LK.PL_error_code, Tuple{T, Int}}, false),
        (
            LK.PL_error,
            Tuple{LD, String, Int, String, LK.PL_error_code, T, Int},
            false
        ),
        (
            LK._PL_error_close!,
            Tuple{LD, Union{Nothing, D}, Int, Int, Int, Int, String, Int, String},
            false
        ),
        # V4b — the call path's helpers: the record checks and the procedure a call names allocate
        # nothing; the run loop's call-path labels are checked by their own test (static_analysis_body.jl)
        (LK._drop_unfilled_frame!, Tuple{LD, Int}, true),
        (LK._no_record_above, Tuple{LD, Int}, true),
        (LK._is_newest_live_frame, Tuple{LD, Int}, true),
        (LK._call_procedure, Tuple{LD, Int, LK.code}, true),
        # V9c — assert/1, assertz/1, asserta/1 (src/pl-comp.jl, pl-proc.jl, pl-error.jl), over
        # DefaultTerm only, as V4a's: their errors build `Name/Arity` with `mk_gnd(T, ::Int)`
        (LK.assert_term!, Tuple{GD, LD, Int, Int}, false),
        (LK.get_head_and_body_clause, Tuple{GD, LD, Int, Int, Int}, false),
        (LK.is_neck, Tuple{LD, Int}, false),
        (LK._strip_module_refused, Tuple{GD, LD, Int}, false),
        (LK._query_gd, Tuple{LD}, false),
        (LK.get_head_functor, Tuple{LD, Int, Int}, false),
        (LK.checkModifySystemProc, Tuple{GD, LD, UInt64, Int}, false),
        (LK.isStaticSystemProcedure, Tuple{GD, UInt64, Int}, false),
        (LK.assertProcedure!, Tuple{GD, PR, C, Int}, false),
        (LK.rewrite_callable, Tuple{LD, T, Int}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, T}, false),
        (LK.PL_error, Tuple{LD, String, Int, String, LK.PL_error_code, T}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, PR}, false),
        [
            (f, Tuple{LD, Int, Int, LK.foreign_context{T}}, false) for
            f in (LK.pl_assertz1_va, LK.pl_asserta1_va)
        ]...
    )
end

"The index's entry points, checked for every payload type."
_index_entry_points(T) = (
    (
        LK.compileClause,
        Tuple{
            LK.PL_global_data{T}, LK.PL_local_data{T}, T, Nothing, LK.Procedure{T},
            LK.module_t{T}
        },
        false
    ),
    (
        LK.compileClause,
        Tuple{
            LK.PL_global_data{T}, LK.PL_local_data{T}, T, T, LK.Procedure{T},
            LK.module_t{T}
        },
        false
    ),
    (LK.lookupBodyProcedure, Tuple{LK.PL_global_data{T}, T, LK.module_t{T}}, false),
    (
        LK.assertDefinition!,
        Tuple{LK.PL_global_data{T}, LK.Definition{T}, LK.Clause{T}, Int},
        false
    ),
    (
        LK.pl_retract!,
        Tuple{
            LK.PL_global_data{T}, LK.PL_local_data{T}, LK.Definition{T}, T,
            typeof(_manifest_sink)
        },
        false
    ),
    (
        LK.pl_garbage_collect_clauses!,
        Tuple{LK.PL_global_data{T}, LK.PL_local_data{T}},
        false
    ),
    (
        LK.firstClause!,
        Tuple{
            LK.PL_local_data{T}, LK.argv_term{LK.PL_local_data{T}, T}, UInt64,
            LK.Definition{T},
            LK.ClauseChoice{T}
        },
        false
    ),
    (
        LK.nextClause!,
        Tuple{
            LK.PL_local_data{T}, LK.ClauseChoice{T},
            LK.argv_term{LK.PL_local_data{T}, T}, UInt64,
            LK.Definition{T}
        },
        true
    ),
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
    (LK._le_byte, Tuple{Vector{UInt8}, Int}, true),
    (LK.MurmurHashAligned2, Tuple{NTuple{4, UInt64}, Int, UInt32}, true),
    (LK.MurmurHashAligned2, Tuple{NTuple{1, UInt64}, Int, UInt32}, true),
    (LK.MurmurHashAligned2, Tuple{Vector{UInt8}, Int, UInt32}, true),
    # SHA-1 and the incremental MurmurHash (src/pl-termhash.jl)
    (LK.sha1_ctx, Tuple{}, false), (LK.rotl32, Tuple{UInt32, Int}, true),
    (LK.rotr32, Tuple{UInt32, Int}, true), (LK.bswap_32, Tuple{UInt32}, true),
    (LK.bsw_32!, Tuple{Vector{UInt32}, Int}, true),
    (LK.sha1_ch, Tuple{UInt32, UInt32, UInt32}, true),
    (LK.sha1_parity, Tuple{UInt32, UInt32, UInt32}, true),
    (LK.sha1_maj, Tuple{UInt32, UInt32, UInt32}, true),
    (LK.sha1_hf!, Tuple{Vector{UInt32}, Int}, true),
    (LK.sha1_compile!, Tuple{LK.sha1_ctx}, true),
    (LK.sha1_begin!, Tuple{LK.sha1_ctx}, true),
    (LK.sha1_hash!, Tuple{Vector{UInt8}, Int, LK.sha1_ctx}, true),
    (LK._sha1_memcpy!, Tuple{LK.sha1_ctx, Int, Vector{UInt8}, Int, Int}, true),
    (LK.sha1_end!, Tuple{Vector{UInt8}, LK.sha1_ctx}, false),
    (LK.hash_state, Tuple{}, false), (LK.hash_init!, Tuple{LK.hash_state}, true),
    (LK.hash_compile!, Tuple{LK.hash_state, Vector{UInt8}, Int}, true),
    (LK.hash_end, Tuple{LK.hash_state}, true), (LK.sha1_state, Tuple{LK.hash_algo}, false),
    (LK.HASH!, Tuple{LK.sha1_state, Vector{UInt8}, Int}, false),
    (LK._HASH_char!, Tuple{LK.sha1_state, Char}, false),
    (LK._HASH_word!, Tuple{LK.sha1_state, UInt64}, false),
    (LK._HASH_str!, Tuple{LK.sha1_state, String}, false),
    (LK._precompile_workload, Tuple{}, false),
    (LK.FLAG64, Tuple{Int}, true), (LK.tagex, Tuple{UInt64}, true),
    (LK.isFunctor, Tuple{UInt64}, true), (LK.MK_ATOM, Tuple{UInt64}, true),
    (LK.MK_FUNCTOR, Tuple{UInt64, UInt64}, true), (LK.codeTable, Tuple{UInt64}, true),
    (LK.initVMIMerge, Tuple{UInt64}, true),
    (LK.functor_operand, Tuple{UInt64, Int}, false),
    (LK.functor_literal, Tuple{UInt64}, true), (LK.functor_arity, Tuple{UInt64}, true),
    (LK.VAROFFSET, Tuple{Int}, true), (LK.VARNUM, Tuple{UInt64}, true),
    (LK.argFrameP, Tuple{Int, Int}, true), (LK.varFrameP, Tuple{Int, Int}, true),
    (LK.refFliP, Tuple{Int, Int}, true), (LK.f_hasSpace, Tuple{Int, Int, Int, Int}, true),
    (LK.NoMark, Tuple{}, true), (LK.isRealMark, Tuple{LK.mark}, true),
    (Base.showerror, Tuple{IOBuffer, LK.LocalStackOverflow}, false),
    (LK.isFirstVarSet!, Tuple{BitVector, Int}, true),
    (LK.isFirstVar, Tuple{BitVector, Int}, true),
    (LK.MSB, Tuple{Int}, true), (LK.MSB, Tuple{UInt32}, true),
    (LK.clean_index_key, Tuple{UInt64}, true), (LK.hashIndex, Tuple{UInt64, UInt32}, true),
    (LK._functor_word, Tuple{UInt64, Int}, true),
    # the reserved index keys, by construction (the divergence audit, S05)
    (LK._unreserved, Tuple{UInt64}, true), (LK._atom_key, Tuple{UInt64}, true),
    (LK._functor_key, Tuple{UInt64, Int}, true), (LK._gnd_index_key, Tuple{UInt64}, true),
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
    (LK.best_assessment!, Tuple{Vector{LK.hash_assessment}, Int, Int}, false),
    (LK.cp_hints_from_arg_info!, Tuple{LK.hash_hints, Int, LK.arg_info}, true),
    (LK.cp_hints_from_assessment!, Tuple{LK.hash_hints, LK.hash_assessment}, true),
    (LK.cmp_assessment, Tuple{LK.hash_assessment, LK.hash_assessment}, true),
    # payload-specific entry points
    (gnd_term, Tuple{Type{_M1}, Float64}, false),
    (gnd_term, Tuple{Type{_M2}, Int64}, false), (gnd_term, Tuple{Type{_M2}, String}, false),
    (gnd_term, Tuple{Type{_M3}, Vector{Float64}}, false),
    (LK._canonical_gnd, Tuple{Type{Float64}, Float64}, true),
    (LK._canonical_gnd, Tuple{Type{Union{Int64, Rational{Int64}}}, Rational{Int64}}, false),
    (mk_gnd, Tuple{Type{_M1}, Float64}, false),
    (mk_gnd, Tuple{Type{_M2}, Int64}, false), (mk_gnd, Tuple{Type{_M2}, String}, false),
    (mk_gnd, Tuple{Type{_M3}, Vector{Float64}}, false),
    (LK._compare_other, Tuple{Vector{Float64}, _M3}, false),
    (LK._compare_other, Tuple{Int64, _M2}, false),
    (gnd_value_key, Tuple{Float64}, false), (gnd_value_key, Tuple{Int64}, false),
    (gnd_value_key, Tuple{String}, false), (gnd_value_key, Tuple{Vector{Float64}}, false),
    (gnd_value_key, Tuple{BigInt}, false), (gnd_value_key, Tuple{Bool}, false),
    # leaf comparisons and helpers
    (LK._sign, Tuple{Int}, true), (LK._tag_rank, Tuple{Kind}, true),
    (LK._sym_key, Tuple{Symbol}, true),
    (LK.compareAtoms, Tuple{Symbol, Symbol}, true),
    (LK.compareAtoms, Tuple{Symbol, Bool, Symbol, Bool}, true),
    (LK.compareReservedSymbol, Tuple{Symbol, Symbol}, true),
    (LK._reserved_sym_key, Tuple{Symbol}, true),
    (LK.compareStrings, Tuple{String, String}, false),
    (LK._nan_value, Tuple{Float64}, true), (LK._nan_value, Tuple{BigFloat}, false),
    (LK.compare_neq_floats, Tuple{Float64, Float64}, true),
    (LK.compare_mixed_float_rational, Tuple{Float64, Int64}, true),
    (LK._cmp_types, Tuple{DataType, DataType}, false),
    (LK._compare_numbers, Tuple{Int64, Float64}, false),
    (LK._compare_numbers, Tuple{Float64, Float64}, false),
    (LK._compare_strings, Tuple{String, String}, false),
    # generated by `@enum Kind` (Julia 1.13) — found by the coverage gate, not by reading; checked
    # rather than exempted because checking it costs nothing
    (Base.Enums._enum_hash, Tuple{Kind, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{NumKind, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.hash_algo, UInt64}, false),
    (LK.fresh_var_keys!, Tuple{Int}, false),
    (Base.Enums._enum_hash, Tuple{LK.boolex_t, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.occurs_check_t, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.choice_type, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.unify_mode, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.finished, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.PL_error_code, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.except_class, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.numtype, UInt64}, false),
    (LK._holds_payload, Tuple{Type, Type}, false),   # not a dispatch tuple: JET only
    (LK.number, Tuple{}, false),
    # term-type-independent parts of the VM (V4a)
    (LK.StackMagic, Tuple{Int}, true), (LK.initSupervisors, Tuple{}, false),
    (LK._vmi_dispatch_tree, Tuple{Symbol, Vector{Tuple{UInt64, Symbol}}}, false),
    # the registration tables (V5a2, src/pl-ext.jl), each read as `(name, arity, flags)`
    (LK._extension_sigs, Tuple{typeof(LK.foreigns)}, false),
    (LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_prims)}, false),
    (LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_variant)}, false),
    (LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_trace)}, false),
    # the built-ins' dispatch trees, built when src/pl-ext.jl loads
    (LK._foreign_tree, Tuple{Symbol, Int, Int, typeof(LK._va_leaf)}, false),
    (LK._foreign_tree, Tuple{Symbol, Int, Int, typeof(LK._det_leaf)}, false),
    (LK._va_leaf, Tuple{Int}, false), (LK._det_leaf, Tuple{Int}, false)
)

# `is_ground(t)` with an untyped argument is the interface's FALLBACK for implementations without a
# cached bit; `Term` overrides it, so no reference type reaches it. (`Tuple{Int}` names the fallback
# method by a non-term argument type — it is the method `which` selects.) Its body is
# `is_ground_walk`, which IS in the manifest.
const DISPATCH_EXEMPT = (
    (
        (is_ground, Tuple{Int}) => "interface fallback; Term overrides it, and its body is_ground_walk is checked"
    ),
    (
        (
            LK.var"@one_cycle",
            Tuple{LineNumberNode, Module, Int, Int, Int, Int, Int, Any, Any, Any}
        ) => "a macro (pl-termhash.c one_cycle): it builds Exprs at load time; its expansion runs in sha1_compile!, which is checked"
    ),
    (
        (LK.var"@five_cycle", Tuple{LineNumberNode, Module, Any, Any, Int}) => "a macro (pl-termhash.c five_cycle): it builds Exprs at load time; its expansion runs in sha1_compile!, which is checked"
    ),
    (
        (LK.var"@SAVE_REGISTERS", Tuple{LineNumberNode, Module, Any}) => "a macro (pl-wam.c SAVE_REGISTERS): it builds Exprs at load time; its expansion runs in PL_next_solution_guarded, which is checked, and its work is _save_registers!, which is checked"
    ),
    (
        (LK.var"@LOAD_REGISTERS", Tuple{LineNumberNode, Module, Any}) => "a macro (pl-wam.c LOAD_REGISTERS): it builds Exprs at load time; its expansion runs in PL_next_solution_guarded, which is checked, and its work is _load_registers!, which is checked"
    ),
    (
        (LK.var"@TYPE_TEST", Tuple{LineNumberNode, Module, Any}) => "a macro (pl-vmi.c TYPE_TEST): it builds Exprs at load time; its expansion runs in PL_next_solution_guarded, which is checked, and its tests (isInteger … isCallable) are checked"
    ),
    (
        (LK.var"@ENSURE_LOCAL_SPACE", Tuple{LineNumberNode, Module, Any}) => "a macro (pl-vmi.c ENSURE_LOCAL_SPACE): it builds Exprs at load time; its expansion runs in PL_next_solution_guarded, which is checked"
    ),
    (
        (LK.var"@vmi_dispatch", Tuple{LineNumberNode, Module, Any, Symbol}) => "a macro (the run loop's dispatch tree): it builds Exprs at load time, with _vmi_dispatch_tree, which is checked; its expansion runs in PL_next_solution_guarded, which is checked"
    ),
    (
        (LK.var"@_fcall_va_body", Tuple{LineNumberNode, Module}) => "a macro (the built-ins' dispatch tree, V5a2): it builds Exprs at load time; its expansion is _fcall_va, which is checked"
    ),
    (
        (LK.var"@_fcall_det_body", Tuple{LineNumberNode, Module}) => "a macro (the FRG built-ins' dispatch tree, V5a2): it builds Exprs at load time; its expansion is _fcall_det, which is checked"
    )
)
