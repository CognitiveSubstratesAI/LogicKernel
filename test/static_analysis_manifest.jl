# ORIGINAL: the dispatch manifest JET checks; no swipl-devel counterpart.
# test/static_analysis_manifest.jl — the concrete call signatures the JET/AllocCheck gate analyses.
#
# 🔴 EVERY method LogicKernel defines (its own functions AND its methods on Base functions) must be
# reached by an entry here, or `test_static_analysis.jl` FAILS and names the method. So a new
# function cannot land without being checked for runtime dispatch — that is the point.
#
# DISPATCH_MANIFEST: (function, Tuple{argument types...}, must_not_allocate::Bool)
#   CONCRETE argument types only — the gate analyses exactly these specialisations.
#   Written as tuples; held as a `Vector{ManifestEntry}` (see `ManifestEntry`, at the end).
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
    (sym_text, Tuple{T}, false), (LK.charCode, Tuple{T}, false),     # R1a: an atom's text
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
    # copy_term/2 (src/pl-copyterm.jl)
    (LK.copy_term, Tuple{LK.PL_local_data{T}, T, LK.cp_options}, false),
    (LK.copy_term, Tuple{LK.PL_local_data{T}, T, LK.cp_options, Dict{UInt64, T}}, false),
    (
        LK._cp_visit!,
        Tuple{LK.PL_local_data{T}, LK._cp_state{T}, Vector{LK._cp_frame{T}}, T},
        false
    ),
    (LK._cp_chain_done!, Tuple{LK._cp_state{T}, Vector{UInt64}, T}, false),
    (LK._cp_finish!, Tuple{LK.PL_local_data{T}, LK._cp_state{T}, LK._cp_frame{T}}, false),
    (LK.copy_term_refs, Tuple{LK.PL_local_data{T}, Int, LK.cp_options}, false),
    (LK._cp_atomic, Tuple{LK.PL_local_data{T}, Int}, false),
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
    (LK.nextTermAgenda!, Tuple{LK.PL_local_data{T}, LK.term_agenda{T}}, false),   # L1c: the cold export (words: L1d/L1e)
    (LK.pushWorkAgenda!, Tuple{LK.term_agenda{T}, Int, T, Int}, false),
    (LK.initTermAgendaLR!, Tuple{LK.term_agendaLR{T}, Int, T, T, Int}, true),
    (LK.clearTermAgendaLR!, Tuple{LK.term_agendaLR{T}}, true),
    (LK.nextTermAgendaLR!, Tuple{LK.term_agendaLR{T}}, true),
    (LK.pushWorkAgendaLR!, Tuple{LK.term_agendaLR{T}, Int, T, T, Int}, false),
    # bindings (src/pl-inline.jl) and unification (src/pl-prims.jl)
    (LK.PL_local_data{T}, Tuple{LK.PL_global_data{T}}, false),
    (LK.deRef, Tuple{LK.PL_local_data{T}, T}, false),   # L1c: a compound reached exports (cold), until L1d
    (LK.Trail!, Tuple{LK.PL_local_data{T}, UInt64, T}, false),
    (LK.Mark, Tuple{LK.PL_local_data{T}}, true),
    (LK.Undo!, Tuple{LK.PL_local_data{T}, LK.mark}, true),
    # L1a: cell variables on the global stack (src/pl-inline.jl, src/pl-alloc.jl)
    (LK._cell_pos, Tuple{LK.PL_local_data{T}, UInt64}, true),
    (LK._binding, Tuple{LK.PL_local_data{T}, UInt64}, false),   # L1c: the cold export
    (LK._set_binding!, Tuple{LK.PL_local_data{T}, UInt64, T}, false),
    # the trail's entries (L1b stage D)
    (LK._trail_key, Tuple{LK.PL_local_data{T}, UInt64}, true),
    (LK._untrail!, Tuple{LK.PL_local_data{T}, UInt64}, false),
    (LK._trail_truncate!, Tuple{LK.PL_local_data{T}, Int}, false),
    # the value table (L1b stage C2): a push may grow its vectors; the reads and the truncation do not
    (LK._vword!, Tuple{LK.PL_local_data{T}, T}, false),
    (LK._cell_value, Tuple{LK.PL_local_data{T}, UInt64}, false),    # L1c: a compound's cold export
    (LK._truncate_vtable!, Tuple{LK.PL_local_data{T}}, true),
    (LK._is_box, Tuple{LK.PL_local_data{T}, Int}, true),
    # the atom words (L1b stage C3): the write fills the caches; the read allocates nothing (a miss
    # only builds its error, inside the throw)
    (LK._atom_word!, Tuple{LK.PL_local_data{T}, T}, false),
    (LK._atom_value, Tuple{LK.PL_local_data{T}, UInt64}, true),
    (LK._atom_value_error, Tuple{LK.PL_local_data{T}, UInt64}, false),
    (LK._word_of!, Tuple{LK.PL_local_data{T}, T}, false),
    # compounds on the global stack (L1c): the layout grows the stack; the two cold adapters allocate
    (LK._var_ref_word, Tuple{LK.PL_local_data{T}, T}, true),
    (LK.query_answers, Tuple{LK.PL_local_data{T}, T}, false),
    # (its `limit=` keyword method: the Julia-facing form, covered as itself)
    (
        Core.kwcall,
        Tuple{
            NamedTuple{(:limit,), Tuple{Int}}, typeof(LK.query_answers),
            LK.PL_local_data{T}, T
        },
        false
    ),
    (LK._truncate_gterms!, Tuple{LK.PL_local_data{T}}, true),   # on every Undo!: in place
    (LK._export_pos, Tuple{LK.PL_local_data{T}, T}, false),      # the reverse map's lookup (L1c): an IdDict `get` is a runtime call; on the cold import path
    (LK._purge_gterm_of!, Tuple{LK.PL_local_data{T}}, false),    # … its rebuild, on the cold path
    (LK._slot_store_value!, Tuple{LK.PL_local_data{T}, Int, T}, false),
    (LK._alloc_compound!, Tuple{LK.PL_local_data{T}, UInt64, Int}, false),
    (LK._compound_term, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK._compound_word!, Tuple{LK.PL_local_data{T}, T}, false),
    (LK._import_offset, Tuple{T}, true),
    (LK._import_layout!, Tuple{LK.PL_local_data{T}, T, Vector{Tuple{T, Int}}}, false),
    # the atoms' symbols, the DATABASE's (L1b stage C6b): the read allocates nothing; a record may
    # allocate its block; the compiler's word for a literal looks its text up
    (LK._atom_word!, Tuple{LK.atoms_t, LK.atom_symbols{T}, T}, false),
    (LK.atom_symbols{T}, Tuple{}, false),
    (LK.atomSymbol, Tuple{LK.atom_symbols{T}, Int}, true),
    (LK.setAtomSymbol!, Tuple{LK.atom_symbols{T}, Int, T}, false),
    (LK.slotValue, Tuple{LK.PL_local_data{T}, Int}, false),   # L1c: the cold export
    # the slot words (L1b stage C5/C6a): reads, stores and moves allocate nothing; a fresh cell may
    # grow the global stack
    (LK._slot_atom, Tuple{LK.PL_local_data{T}, UInt64}, true),
    (LK._slot_store!, Tuple{LK.PL_local_data{T}, Int, T}, false),   # L1c: the cold import
    (LK._slot_copy!, Tuple{LK.PL_local_data{T}, Int, Int}, true),
    (LK._slot_link!, Tuple{LK.PL_local_data{T}, Int, Int}, false),  # L1c: the cold import
    (LK._slot_new_var!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK._cell_key, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK._cell_var, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.allocGlobalCells!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.setSlotValue!, Tuple{LK.PL_local_data{T}, Int, T}, false),
    (LK.putSlotValue!, Tuple{LK.PL_local_data{T}, Int, T}, false),
    (LK.putSlotValue!, Tuple{LK.PL_local_data{T}, Int, T, LK.PutVarMap}, false),
    (LK.allocGlobalVars!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK._reserveStamps!, Tuple{LK.PL_local_data{T}}, false),
    (LK._growGlobalStack!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.linkTermsCyclic!, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.exitCyclic!, Tuple{LK.PL_local_data{T}}, false),
    (LK._cyclic_deref, Tuple{LK.PL_local_data{T}, T}, false),
    (LK._unify_functor, Tuple{T, T}, true),
    (LK.unify_simple_ptrs, Tuple{LK.PL_local_data{T}, T, T}, false),
    (LK.do_unify, Tuple{LK.PL_local_data{T}, T, T}, false),
    # unification on the cells (L1c sub-commit 4): the deref and the walk allocate nothing; the
    # boundary (a term) and the agenda's growth do
    (LK._deref_loc, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK._loc_term, Tuple{LK.PL_local_data{T}, UInt8, UInt64, Int}, false),
    (
        LK.unify_simple_cells,
        Tuple{LK.PL_local_data{T}, UInt8, UInt64, Int, UInt8, UInt64, Int},
        false
    ),
    (LK._link_cells!, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK._exit_cycles!, Tuple{LK.PL_local_data{T}}, true),
    (LK._cycle_root, Tuple{LK.PL_local_data{T}, Int}, true),
    (
        LK._push_compound_pair!,
        Tuple{LK.PL_local_data{T}, LK.cell_agendaLR, Int, Int},
        false
    ),
    (LK.do_unify_cells, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK.raw_unify_cells, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK.unify_ptrs_cells, Tuple{LK.PL_local_data{T}, Int, Int}, false),
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
    # V5d: the overflow raised, the spare enabled and reserved again; the ball copied, its cycles kept
    (LK.outOfStack!, Tuple{LK.PL_local_data{T}, LK.stack_overflow_action}, false),
    (LK.push_overflow_context, Tuple{Type{T}}, false),
    (LK.enableSpareStack!, Tuple{LK.PL_local_data{T}, Bool}, true),
    (LK.enableSpareStacks!, Tuple{LK.PL_local_data{T}}, true),
    (LK.has_emergency_space, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.trim_stack!, Tuple{LK.PL_local_data{T}}, true),
    (LK.trimStacks!, Tuple{LK.PL_local_data{T}, Bool}, true),
    (LK.init_stack!, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK.allocStacks!, Tuple{LK.PL_local_data{T}}, false),
    (LK._resize_local!, Tuple{LK.PL_local_data{T}, Int}, false),
    (LK.copy_exception!, Tuple{LK.PL_local_data{T}, Int, Int}, false),
    (LK.hasLocalSpace, Tuple{LK.PL_local_data{T}, Int}, true),
    (LK.DiscardMark, Tuple{LK.PL_local_data{T}, LK.mark}, true),
    (LK.linkValI, Tuple{LK.PL_local_data{T}, T}, false),   # L1c: the cold export
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
    (LK.PL_put_term, Tuple{LK.PL_local_data{T}, Int, Int}, false),   # L1c: the cold export (words: L1d/L1e)
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
        (LK.compileInfo{T}, Tuple{GD, Int, MOD, PR}, false),
        (LK.pushBranchVar!, Tuple{CInfo, LK.VarDef}, false),
        (LK.compiler_warning, Tuple{CInfo, Symbol, Vector{T}}, false),
        (LK.push_compiler_warnings, Tuple{LD, CInfo}, false),
        (LK.get_variable_names, Tuple{CInfo}, false),
        (LK.in_branch, Tuple{Vector{LK.branch_var}, Int, Int, LK.VarDef}, true),
        (LK._max_frame_size, Tuple{}, false),
        (LK.analyseVariables2!, Tuple{GD, CInfo, T, Int, Int, Bool}, false),
        (LK.analyse_variables!, Tuple{GD, CInfo, T, Nothing}, false),
        (LK.analyse_variables!, Tuple{GD, CInfo, T, T}, false),
        (LK.analyse_variables!, Tuple{GD, CInfo, Nothing, T}, false),    # a goal clause (V9e-2)
        (LK._compile_clause_head!, Tuple{GD, CInfo, T, Nothing}, false),
        (LK._compile_clause_head!, Tuple{GD, CInfo, T, T}, false),
        (LK.compileArgument!, Tuple{CInfo, T, Int}, false),
        (LK.link_local_var!, Tuple{CInfo, T, Int}, false),
        (LK._local_cell!, Tuple{CInfo, Int, T}, false),
        (LK.reverse_code!, Tuple{Vector{UInt64}, Int, Int}, true),
        (LK.lco!, Tuple{CInfo, Int}, false),
        (LK.compileSubClause!, Tuple{GD, LD, CInfo, T, UInt64}, false),
        (LK.compileBody!, Tuple{GD, LD, CInfo, T, UInt64}, false),
        # V9d — disjunctions: the variable tables compileBody! balances, and the decompiler
        (LK.c_var, Tuple{LK.c_var_state, Int, CInfo}, false),
        (LK.balanceVars, Tuple{BitVector, BitVector, CInfo}, false),
        (LK.orVars, Tuple{BitVector, BitVector}, false),
        (LK.setVars, Tuple{CInfo, T, BitVector}, false),
        (LK.copyVarTable, Tuple{BitVector, BitVector}, false),
        (LK._cb_next, Tuple{LK.cb_frame{T}, LK.cb_kind, Int}, false),
        (LK._cb_next, Tuple{LK.cb_frame{T}, LK.cb_kind}, false),
        (LK.allocChoiceVar!, Tuple{LD, CInfo}, false),
        (LK.try_fast_condition!, Tuple{CInfo, Int}, false),
        (LK.in_continuation, Tuple{LD, Int, Int, Int}, true),
        (LK.killFrame, Tuple{LK.localFrame{T}}, true),
        (LK._dvar, Tuple{LK.decompileInfo{T}, UInt64}, false),
        (LK._dpush!, Tuple{LK.decompileInfo{T}, T}, false),
        (LK.build_term!, Tuple{LK.decompileInfo{T}, T, Int, Int}, false),
        (LK.build_term!, Tuple{LK.decompileInfo{T}, T, Int}, false),
        (LK.decompileBodyNoShift!, Tuple{LK.decompileInfo{T}, UInt64, Int}, false),
        (LK._type_test_name, Tuple{UInt64}, false),
        (LK.decompileBody!, Tuple{LD, LK.decompileInfo{T}, T, UInt64, Int}, false),
        (LK.decompile!, Tuple{LD, C, T, T}, false),
        (
            LK.decompile_head!,
            Tuple{LD, C, T, UInt64, Union{Nothing, BitVector}, Union{Nothing, Vector{T}}},
            false
        ),
        (LK.add_bvar_access!, Tuple{BitVector, Int, Int}, true),
        (LK._body_start, Tuple{C}, false),
        (LK.mark_bvar_access, Tuple{C}, false),
        (
            LK.moved_unifications!,
            Tuple{LD, C, Int, UInt64, T, BitVector, Vector{T}, Bool},
            false
        ),
        (LK.pl_clause!, Tuple{GD, LD, D, T, T, SNK}, false),
        # V6b — the type tests compiled inline (src/pl-comp.jl, pl-incl.jl, pl-fli.jl)
        (LK.always, Tuple{LD, CInfo, Bool, String, T}, false),
        (LK.alwaysFirstVar, Tuple{LD, CInfo, Bool, String, T, Int}, false),
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
        (LK.compileClause, Tuple{GD, LD, T, Nothing, PR, MOD, Int}, false),
        (LK.compileClause, Tuple{GD, LD, T, T, PR, MOD, Int}, false),
        (LK.localGoal, Tuple{GD, LD, T}, false),
        (LK.compileGoalClause, Tuple{GD, LD, T, MOD, Int}, false),
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
        (LK.indexKeyFromArgv, Tuple{CI, AT}, false),   # L1c: the cold export (words: L1d/L1e)
        (LK.indexKeyFromArgv, Tuple{CI, AF}, false),   # L1c: the cold export (words: L1d/L1e)
        (LK.is_var, Tuple{T}, true),
        (LK.is_satifies_index, Tuple{CI, AT}, false),   # L1c: the cold export (words: L1d/L1e)
        (LK.is_satifies_index, Tuple{CI, AF}, false),   # L1c: the cold export (words: L1d/L1e)
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
        # (L1c: the cold export until indexing reads words, L1c sub-commit 5)
        (LK.argv_at, Tuple{AT, Int}, false), (LK.argv_at, Tuple{AF, Int}, false),
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
            Tuple{LK.PL_local_data{T}, Vector{LK.DecompileFrame{T}}, UInt64, Int},
            false
        ),
        (LK._decompile_void, Tuple{LK.PL_local_data{T}, Nothing, UInt64, Int}, false),
        # src/pl-proc.jl
        (LK.MODULE_user, Tuple{GD}, true),
        (LK.lookupProcedure, Tuple{T, Int, MOD}, false),
        # V5c — the module path (src/pl-modul.jl, pl-proc.jl, pl-wam.jl, pl-comp.jl, pl-fli.jl,
        # pl-supervisor.jl)
        (LK.isCurrentModule, Tuple{Vector{MOD}, T}, false),
        (LK._lookupModule!, Tuple{Vector{MOD}, LK.PL_code_data, T}, false),
        (LK.lookupModule, Tuple{GD, T}, false),
        (LK.inheritUnknown, Tuple{GD, MOD}, true),
        (LK.stripModuleName, Tuple{LD, T}, false),
        (LK.stripModule, Tuple{GD, LD, T}, false),
        (LK.PL_strip_module_ex, Tuple{GD, LD, Int, Int, Int}, false),
        (LK._impl_any_defined, Tuple{D}, true),
        (LK.autoImport, Tuple{GD, T, Int, MOD}, false),
        (LK.trapUndefined, Tuple{GD, D}, false),
        (LK.createUndefSupervisor, Tuple{D}, false),
        (LK.getProcDefinedDefinition, Tuple{GD, D}, false),
        (LK.unify_functor, Tuple{Type{T}, D, Int}, false),
        (LK.unify_definition, Tuple{GD, MOD, D, Int}, false),
        # R1b — the operator tables (src/pl-op.jl) and the FLI getters op/3 uses (pl-fli.jl,
        # pl-error.jl)
        (LK.defOperator!, Tuple{GD, LD, MOD, T, UInt8, Int16, Bool}, false),
        (LK.defOperator!, Tuple{GD, Nothing, MOD, T, UInt8, Int16, Bool}, false),
        (LK.visibleOperator, Tuple{GD, MOD, UInt64, Int}, false),
        (LK.currentOperator, Tuple{GD, MOD, T, Int}, false),
        (LK.currentOperator, Tuple{GD, Nothing, T, Int}, false),
        (LK.maxOp, Tuple{LK._operator{T}, Int, Int}, true),
        (LK.scanPriorityOperator, Tuple{GD, MOD, UInt64, Int, Int}, false),
        (LK.priorityOperator, Tuple{GD, MOD, T}, false),
        (LK.priorityOperator, Tuple{GD, Nothing, T}, false),
        (LK.atomToOperatorType, Tuple{Type{T}, T}, false),
        (LK.operatorTypeToAtom, Tuple{Type{T}, UInt8}, false),
        (LK.addOpToBuffer!, Tuple{Vector{Tuple{T, UInt8, Int16}}, T, UInt8, Int16}, false),
        [
            (
                LK.addOpsFromTable!,
                Tuple{
                    Dict{UInt64, LK._operator{T}},
                    N,
                    Int,
                    UInt8,
                    Vector{Tuple{T, UInt8, Int16}}
                },
                false
            ) for N in (Nothing, T)
        ]...,
        [
            (
                LK.scanVisibleOperators!,
                Tuple{GD, MOD, N, Int, UInt8, Vector{Tuple{T, UInt8, Int16}}, Bool},
                false
            ) for N in (Nothing, T)
        ]...,
        (LK.initOperators!, Tuple{GD}, false),
        (LK.pl_op3_va, Tuple{LD, Int, Int, LK.foreign_context{T}}, false),
        (LK.PL_get_atom, Tuple{LD, Int}, false),
        (LK.PL_get_integer, Tuple{LD, Int}, false),
        (LK.PL_get_list, Tuple{LD, Int, Int, Int}, false),
        (LK.PL_get_nil, Tuple{LD, Int}, false),
        (LK.PL_is_list, Tuple{LD, Int}, false),
        (LK.PL_strip_module, Tuple{GD, LD, Int, Int, Int}, false),
        (LK.PL_get_atom_ex, Tuple{LD, Int}, false),
        (LK.PL_get_integer_ex, Tuple{LD, Int}, false),
        (LK.PL_get_list_ex, Tuple{LD, Int, Int, Int}, false),
        (LK.PL_get_nil_ex, Tuple{LD, Int}, false),
        (LK.PL_error, Tuple{LD, String, Int, String, LK.PL_error_code, T, T, Int}, false),
        # R1c — the scanner (src/pl-read.jl), atom_number/2 (pl-prims.jl): over the term type
        (LK.SkipSymbol, Tuple{Vector{UInt8}, Int64, LK.read_data{T}}, false),
        (LK._atom_from_text, Tuple{Type{T}, String}, false),
        (LK._rd_text, Tuple{LK.read_data{T}}, false),
        (LK._text_atom, Tuple{Type{T}, Vector{UInt8}, Int64, Int64}, false),
        (LK._text_term, Tuple{Type{T}, Vector{UInt8}, Symbol}, false),
        (LK.addByteToBuffer, Tuple{Int64, LK.read_data{T}}, false),
        (LK.addToBuffer, Tuple{Int64, LK.read_data{T}}, false),
        (
            LK.ascii_to_double,
            Tuple{LK.PL_local_data{T}, Vector{UInt8}, Int64, Int64},
            false
        ),
        (LK.bidi_override_error, Tuple{Int64, LK.read_data{T}}, false),
        (LK.check_no_bidi_override, Tuple{Int64, Int64, LK.read_data{T}}, false),
        (LK.clearBuffer, Tuple{LK.read_data{T}}, false),
        (LK.ensure_space, Tuple{Int64, LK.read_data{T}, Bool}, false),
        (LK.errorWarning, Tuple{String, Nothing, LK.read_data{T}}, false),
        (LK.errorWarning, Tuple{String, T, LK.read_data{T}}, false),
        (LK.errorWarningA1, Tuple{String, Nothing, Nothing, LK.read_data{T}}, false),
        (LK.errorWarningA1, Tuple{String, Nothing, T, LK.read_data{T}}, false),
        (LK.errorWarningA1, Tuple{String, String, Nothing, LK.read_data{T}}, false),
        (LK.errorWarningA1, Tuple{String, String, T, LK.read_data{T}}, false),
        (LK.escape_char, Tuple{Vector{UInt8}, Int64, Int64, Nothing}, false),
        (LK.escape_char, Tuple{Vector{UInt8}, Int64, Int64, LK.read_data{T}}, false),
        (LK.get_string, Tuple{Int64, Int64, Vector{UInt8}, LK.read_data{T}}, false),
        (LK.get_token, Tuple{Bool, LK.read_data{T}}, false),
        (
            LK.get_unicode_quoted_string,
            Tuple{Int64, Int64, Int64, Vector{UInt8}, LK.read_data{T}},
            false
        ),
        (LK.getchr__, Tuple{LK.read_data{T}}, false),
        (LK.getchrq, Tuple{LK.read_data{T}}, false),
        (LK.growToBuffer, Tuple{Int64, LK.read_data{T}}, false),
        (LK.hashVariable, Tuple{LK.variable, LK.read_data{T}}, false),
        (
            LK.init_read_data,
            Tuple{LK.PL_global_data{T}, LK.PL_local_data{T}, LK.IOSTREAM},
            false
        ),
        (LK.linkVariable, Tuple{LK.variable, LK.read_data{T}}, false),
        (LK.lookupVariable, Tuple{Int64, Int64, LK.read_data{T}}, false),
        (LK.makeErrorTerm, Tuple{String, Nothing, Nothing, LK.read_data{T}}, false),
        (LK.makeErrorTerm, Tuple{String, Nothing, T, LK.read_data{T}}, false),
        (LK.makeErrorTerm, Tuple{String, String, Nothing, LK.read_data{T}}, false),
        (LK.makeErrorTerm, Tuple{String, String, T, LK.read_data{T}}, false),
        (LK.numberError, Tuple{LK.strnumstat, LK.read_data{T}}, false),
        (
            LK.pl_atom_number2_va,
            Tuple{LK.PL_local_data{T}, Int64, Int64, LK.foreign_context{T}},
            false
        ),
        (LK.ptr_to_location, Tuple{Int64, LK.read_data{T}}, false),
        (LK.ptr_to_pos, Tuple{Int64, LK.read_data{T}}, false),
        (LK.rawSyntaxError, Tuple{String, LK.read_data{T}}, false),
        (LK.rawSyntaxError1, Tuple{String, Nothing, LK.read_data{T}}, false),
        (LK.rawSyntaxError1, Tuple{String, String, LK.read_data{T}}, false),
        (LK.raw_read, Tuple{LK.read_data{T}}, false),
        (LK.raw_read2, Tuple{LK.read_data{T}}, false),
        (LK.raw_read_identifier, Tuple{Int64, LK.read_data{T}}, false),
        (LK.raw_read_quoted, Tuple{Int64, Int64, LK.read_data{T}}, false),
        (LK.read_unicode_quote_token, Tuple{Int64, Int64, LK.read_data{T}}, false),
        (LK.rehashVariables, Tuple{LK.read_data{T}}, false),
        (LK.setCurrentSourceLocation, Tuple{LK.read_data{T}}, false),
        (LK.setErrorLocation, Tuple{Nothing, LK.read_data{T}}, false),
        (LK.setErrorLocation, Tuple{LK.IOPOS, LK.read_data{T}}, false),
        (LK.set_start_line, Tuple{LK.read_data{T}, Bool}, false),
        (
            LK.str_number,
            Tuple{LK.PL_local_data{T}, Vector{UInt8}, Int64, LK.number, UInt32},
            false
        ),
        (LK.syntaxError, Tuple{String, LK.read_data{T}}, false),
        (
            LK.to_double,
            Tuple{LK.PL_local_data{T}, Vector{UInt8}, Int64, Int64, Int64},
            false
        ),
        (LK.unify_location, Tuple{LK.source_location{T}, LK.read_data{T}}, false),
        (LK.var_from_index, Tuple{Int64, LK.read_data{T}}, false),
        # R1d — the parser (src/pl-read.jl), the quoting rule it asks (pl-write.jl), the text a
        # term holds (os/pl-text.jl, os/pl-codelist.jl), term_to_atom/2 and its kin
        (LK.raw_read_quasi_quotation, Tuple{Int64, LK.read_data{T}}, false),
        (LK.copy_op_entry, Tuple{LK.op_entry{T}}, false),
        (LK.init_term_stack, Tuple{LK.read_data{T}}, false),
        (LK.alloc_term, Tuple{LK.read_data{T}}, false),
        (LK.term_av, Tuple{Int64, LK.read_data{T}}, true),
        (LK.truncate_term_stack, Tuple{Int64, LK.read_data{T}}, true),
        (LK._setHandle!, Tuple{Int64, T, LK.read_data{T}}, false),
        (LK._ts_term, Tuple{Int64, LK.read_data{T}}, false),
        (LK.readValHandle, Tuple{Int64, LK.read_data{T}}, false),
        (LK.build_term, Tuple{T, Int64, LK.read_data{T}}, false),
        (LK._read_list_term, Tuple{Vector{T}, T}, false),
        (LK.queue_side_op, Tuple{LK.op_entry{T}, LK.read_data{T}}, false),
        (LK.side_op, Tuple{Int64, LK.read_data{T}}, false),
        (LK.pop_side_op, Tuple{LK.read_data{T}}, false),
        (LK.side_p0, Tuple{LK.read_data{T}}, true),
        (LK.queue_out_op, Tuple{Int64, LK.read_data{T}}, false),
        (LK.out_op, Tuple{Int64, LK.read_data{T}}, true),
        (LK.pop_out_op, Tuple{LK.read_data{T}}, false),
        (LK.op_name, Tuple{LK.op_entry{T}}, false),
        (LK.build_op_term, Tuple{LK.op_entry{T}, LK.read_data{T}}, false),
        (LK.copy_cterm_state, Tuple{LK.cterm_state{T}}, false),
        (LK.isOp, Tuple{LK.op_entry{T}, Int64, LK.read_data{T}}, false),
        (LK.PopOp!, Tuple{LK.cterm_state{T}}, false),
        (LK.modify_op, Tuple{LK.cterm_state{T}, Int64}, false),
        (LK.bad_operator, Tuple{Int64, LK.op_entry{T}, LK.read_data{T}}, false),
        (LK.can_reduce, Tuple{LK.op_entry{T}, Int64, Int64, LK.read_data{T}}, false),
        (LK.must_reduce, Tuple{LK.op_entry{T}, LK.op_entry{T}, LK.reduce_side}, true),
        (LK.reduce_one_op, Tuple{LK.cterm_state{T}, LK.op_entry{T}, LK.reduce_side}, false),
        (LK.reduce_op, Tuple{LK.cterm_state{T}, LK.op_entry{T}}, false),
        (LK._token_atom, Tuple{LK.token{T}}, false),
        (LK.is_name_token, Tuple{LK.token{T}, Bool, LK.read_data{T}}, false),
        (LK.name_token, Tuple{LK.token{T}, LK.op_entry{T}, LK.read_data{T}}, false),
        (LK.name_token, Tuple{LK.token{T}, Nothing, LK.read_data{T}}, false),
        (LK.prepare_op, Tuple{LK.op_entry{T}, LK.token{T}, LK.read_data{T}}, false),
        (LK.finish_block_op, Tuple{LK.op_entry{T}, LK.read_data{T}}, false),
        (LK.complex_term, Tuple{Nothing, Int64, LK.read_data{T}}, false),
        (LK.complex_term, Tuple{String, Int64, LK.read_data{T}}, false),
        (LK.read_list_elem, Tuple{LK.pframe{T}, LK.ct_request, LK.read_data{T}}, false),
        (
            LK.read_list_start,
            Tuple{LK.pframe{T}, LK.token{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (
            LK.read_list_resume_elem,
            Tuple{LK.pframe{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (LK.read_list_resume_tail, Tuple{LK.pframe{T}, LK.read_data{T}}, false),
        (
            LK.read_bracket_start,
            Tuple{LK.pframe{T}, LK.token{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (LK.read_bracket_resume, Tuple{LK.pframe{T}, LK.read_data{T}}, false),
        (LK.read_compound_end, Tuple{LK.pframe{T}, LK.token{T}, LK.read_data{T}}, false),
        (LK.read_compound_arg, Tuple{LK.pframe{T}, LK.ct_request, LK.read_data{T}}, false),
        (
            LK.read_compound_start,
            Tuple{LK.pframe{T}, LK.token{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (
            LK.read_compound_resume,
            Tuple{LK.pframe{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (LK.simple_term, Tuple{LK.token{T}, LK.read_data{T}}, false),
        (
            LK.start_pframe,
            Tuple{LK.pframe{T}, LK.token{T}, LK.ct_request, LK.read_data{T}},
            false
        ),
        (LK.resume_pframe, Tuple{LK.pframe{T}, LK.ct_request, LK.read_data{T}}, false),
        (LK.bind_variable_names, Tuple{LK.read_data{T}}, false),
        (LK.read_term, Tuple{Int64, LK.read_data{T}}, false),
        (LK.atom_to_term, Tuple{LD, Int64, Int64, Int64, Int64}, false),
        (LK.pl_atom_to_term3_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.pl_term_to_atom2_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.pl_term_string2_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.unquoted_atom, Tuple{T}, false),
        (LK.PL_get_text, Tuple{LD, Int64, UInt32}, false),
        (LK.codes_or_chars_to_buffer, Tuple{LD, Int64, Bool}, false),
        # R1e — the writer's core (src/pl-write.jl): quoting, the token layer, atoms, strings,
        # numbers, `'$VAR'`, the term state machine, `PL_write_term`
        (LK.bracketPairAtom, Tuple{T}, false),
        (LK.wframe{T}, Tuple{T}, false),
        (LK.write_options, Tuple{GD, LD, LK.IOSTREAM}, false),
        (LK._ison, Tuple{LK.write_options{T}, Int64}, true),
        (LK._is_text_atom_key, Tuple{T, UInt64}, true),
        (LK.out_var_prefix, Tuple{LK.write_options{T}}, true),
        (LK.PutComma, Tuple{LK.write_options{T}}, false),
        (LK.PutBar, Tuple{LK.write_options{T}}, false),
        (LK.PutVarName, Tuple{String, LK.write_options{T}}, false),
        (LK.PutElipsis, Tuple{Bool, LK.write_options{T}}, false),
        (LK.PutOpenBrace, Tuple{LK.write_options{T}}, false),
        (
            LK.write_chars,
            Tuple{Vector{Char}, Int64, Int64, Int64, LK.write_options{T}},
            false
        ),
        (LK.writeText, Tuple{String, Bool, Int64, LK.write_options{T}}, false),
        (LK.writeReservedSymbol, Tuple{LK.IOSTREAM, T, Int64}, false),
        (LK.writeUCSAtom, Tuple{String, LK.write_options{T}}, false),
        (LK.writeAtom, Tuple{T, LK.write_options{T}}, false),
        (LK.writeString, Tuple{T, LK.write_options{T}}, false),
        (LK.writeMPZ, Tuple{BigInt, LK.write_options{T}}, false),
        (LK.writeNumber, Tuple{T, LK.write_options{T}}, false),
        (LK.varName, Tuple{T}, false),
        (LK.writePrimitive, Tuple{T, LK.write_options{T}}, false),
        (LK.writeNumberVar, Tuple{T, LK.write_options{T}, T}, false),
        (LK.callPortray, Tuple{T, Int64, LK.write_options{T}}, false),
        (LK.isBlockOp, Tuple{T, T, LK.write_options{T}}, false),
        (
            LK.sub_term,
            Tuple{LK.wframe{T}, LK.wf_kind, LK.wsub{T}, T, Int64, Int64},
            true
        ),
        (LK._wr_arg, Tuple{LK.wframe{T}, Int64}, true),
        (LK.writeDotListHead, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeListStart, Tuple{T, LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeListElemDone, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeCloseParens, Tuple{LK.write_options{T}, LK.wframe{T}}, false),
        (LK.writeDotHeadDone, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writePrefixArg, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writePostfixOp, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeInfixArg2, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeInfixOp, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeCanonArg, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (
            LK.writeTerm2,
            Tuple{T, Int64, LK.write_options{T}, Int64, LK.wframe{T}, LK.wsub{T}},
            false
        ),
        (LK.writeTermResume, Tuple{LK.write_options{T}, LK.wframe{T}, LK.wsub{T}}, false),
        (LK.writeTerm, Tuple{T, Int64, LK.write_options{T}, Int64}, false),
        (LK.writeTopTerm, Tuple{Int64, Int64, LK.write_options{T}}, false),
        (LK.PL_write_term, Tuple{GD, LD, LK.IOSTREAM, Int64, Int64, Int64}, false),
        # R1e — the write/1 family: the predicates (src/pl-write.jl), the standard streams
        # (src/os/pl-file.jl), option lists (src/os/pl-option.jl), and their FLI helpers
        (LK._numbervars_newer, Tuple{LD, T}, false),
        (LK.pl_nl, Tuple{LD, Int64}, false),
        (LK.pl_nl1_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.pl_nl0_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.writeAttributeMask, Tuple{LD, T}, false),
        (LK.writeBlobMask, Tuple{LD, T}, false),
        (LK.BEGIN_NUMBERVARS, Tuple{LD, Bool}, false),
        (LK.END_NUMBERVARS, Tuple{LD, Bool, Int64}, false),
        (LK.bind_varnames, Tuple{LD, Int64}, false),
        (LK.pl_write_term3, Tuple{LD, Int64, Int64, Int64}, false),
        (LK.pl_write_term2_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.pl_write_term3_va, Tuple{LD, Int64, Int64, LK.foreign_context{T}}, false),
        (LK.do_write2, Tuple{LD, Int64, Int64, Int64, Bool}, false),
        (LK.pl_write2, Tuple{LD, Int64, Int64}, false),
        (LK.pl_writeln2, Tuple{LD, Int64, Int64}, false),
        (LK.pl_writeq2, Tuple{LD, Int64, Int64}, false),
        (LK.pl_print2, Tuple{LD, Int64, Int64}, false),
        (LK.pl_write, Tuple{LD, Int64}, false),
        (LK.pl_writeq, Tuple{LD, Int64}, false),
        (LK.pl_print, Tuple{LD, Int64}, false),
        (LK.pl_writeln, Tuple{LD, Int64}, false),
        (LK._print_write_options, Tuple{Type{T}}, false),
        (
            LK.PL_scan_options,
            Tuple{LD, Int64, Int64, String, typeof(LK.write_term_options)},
            false
        ),
        (
            LK.PL_scan_options,
            Tuple{LD, Int64, Int64, String, typeof(LK.read_term_options)},
            false
        ),
        (LK.get_optval, Tuple{LD, LK.PL_option_t, Int64}, false),
        (LK.setBackQuotes, Tuple{LD, T, UInt32}, false),
        (LK.atom_to_bool, Tuple{LD, T}, false),
        (LK.PL_get_stdbool, Tuple{LD, Int64}, false),
        (LK.PL_get_bool, Tuple{LD, Int64}, false),
        (LK.PL_get_stdbool_ex, Tuple{LD, Int64}, false),
        (LK.PL_get_bool_ex, Tuple{LD, Int64}, false),
        (LK.PL_unify_bool_ex, Tuple{LD, Int64, Bool}, false),
        (LK.PL_get_name_arity, Tuple{LD, Int64}, false),
        (LK._PL_get_arg, Tuple{LD, Int64, Int64, Int64}, false),
        (LK.PL_is_functor, Tuple{LD, Int64, T, Int64}, false),
        (LK.skip_list, Tuple{LD, T}, false),
        (LK.lengthList, Tuple{LD, Int64, Bool}, false),
        (LK.Suser_input, Tuple{LD}, false),
        (LK.Suser_output, Tuple{LD}, false),
        (LK.Suser_error, Tuple{LD}, false),
        (LK.Scurin, Tuple{LD}, false),
        (LK.Scurout, Tuple{LD}, false),
        (LK.standardStreamIndexFromName, Tuple{LD, T}, false),
        (LK.standardStreamIndexFromStream, Tuple{LD, LK.IOSTREAM}, false),
        (LK.initIO, Tuple{LD}, false),
        (LK._initIO, Tuple{LD}, false),
        (LK.set_standard_stream!, Tuple{LD, Int64, IOBuffer}, false),
        (LK.set_standard_stream!, Tuple{LD, Int64, IOStream}, false),
        (LK.no_stream, Tuple{LD, Int64, Symbol}, false),
        (LK.not_a_stream, Tuple{LD, Int64, Int64}, false),
        (LK.symbol_no_stream, Tuple{LD, T}, false),
        (LK.symbol_stream_wrong_mode, Tuple{LD, T, Symbol}, false),
        (LK.check_stream_mode, Tuple{LD, T, LK.IOSTREAM, Int64}, false),
        (LK.get_stream_handle, Tuple{LD, T, Int64}, false),
        (LK.checkStreamType, Tuple{LD, Int64, LK.IOSTREAM}, false),
        (LK.getOutputStream, Tuple{LD, Int64, Int64}, false),
        (LK.getTextOutputStream, Tuple{LD, Int64}, false),
        (LK.PL_unify_stream_or_alias, Tuple{LD, Int64, LK.IOSTREAM}, false),
        (LK.reportStreamError, Tuple{LD, LK.IOSTREAM}, false),
        (LK.streamStatus, Tuple{LD, LK.IOSTREAM}, false),
        # R1e — write_canonical/1,2 (pl-prims.c numberVars) and read_term_from_atom/3
        (LK.nv_options{T}, Tuple{T, Int64, LK.av_action, Int64, Bool}, false),
        (LK.do_number_vars, Tuple{LD, T, LK.nv_options{T}, Int64}, false),
        (LK.numberVars, Tuple{LD, Int64, LK.nv_options{T}, Int64}, false),
        (LK.pl_write_canonical2, Tuple{LD, Int64, Int64}, false),
        (LK.pl_write_canonical, Tuple{LD, Int64}, false),
        (LK.setDoubleQuotes, Tuple{LD, T, UInt32}, false),
        (LK.bind_variables, Tuple{LK.read_data{T}}, false),
        (LK.read_term_from_stream, Tuple{GD, LD, LK.IOSTREAM, Int64, Int64}, false),
        (
            LK.pl_read_term_from_atom3_va,
            Tuple{LD, Int64, Int64, LK.foreign_context{T}},
            false
        ),
        (LK.isCurrentProcedure, Tuple{UInt64, Int, MOD}, false),
        (LK.hasClausesDefinition, Tuple{GD, D}, true),
        (LK.isDefinedProcedure, Tuple{GD, PR}, true),
        (LK.isDefinedOrAutoloadProcedure, Tuple{GD, PR}, true),
        (LK.visibleProcedure, Tuple{GD, T, Int, MOD}, false),
        (LK.resolveProcedure, Tuple{GD, T, Int, MOD}, false),
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
        # (not allocation-free since V9g: a discarded cleanup frame runs its handler, a goal)
        (LK.discardChoicesAfter, Tuple{LD, Int, LK.finished}, false),
        (LK.dbg_discardChoicesAfter, Tuple{LD, Int, LK.finished}, false),
        (LK.queryOfFrame, Tuple{LD, Int}, true), (LK.parentFrame, Tuple{LD, Int}, true),
        (LK.setLTop!, Tuple{LD, Int}, true),
        (LK._argp_raw, Tuple{LD, ARGP}, false), (LK._argp_deref, Tuple{LD, ARGP}, false),   # L1c
        # (L1c: a store may copy a compound onto the stack — the cold import allocates)
        (LK._argp_store!, Tuple{LD, ARGP, T}, false),
        (LK._argp_add, Tuple{ARGP, Int}, true),
        (LK._argp_loc, Tuple{ARGP}, true),                      # do_unify_cells' location (L1c-4)
        (LK._argp_fresh_var!, Tuple{LD, ARGP, Int}, false),
        (LK._argp_void!, Tuple{LD, ARGP}, false),
        (LK._bind_const!, Tuple{LD, Int, UInt64}, false),       # a binding may grow the trail
        (LK._argp_deref_word, Tuple{LD, ARGP}, true),
        (LK._cell_link!, Tuple{LD, Int, Int}, false),
        (LK._slot_from_cell!, Tuple{LD, Int, Int}, true),
        (LK._h_const_word!, Tuple{LD, Int, UInt64}, false),     # a binding may grow the trail
        (LK._reset_argument_stack!, Tuple{LD, LK.queryFrame{T}}, true),
        (LK._slow_unify, Tuple{LD}, true),
        (LK._is_expr3, Tuple{T}, true),
        (
            LK._save_registers!,
            Tuple{LD, Int, Int, ARGP, Vector{LK.code}, Vector{T}, Int},
            true
        ),
        (LK._load_registers!, Tuple{LD, Int}, true),
        (LK.resumeAfterException, Tuple{LD, Bool, Bool}, false),
        (LK._reset_exception_slot!, Tuple{LD, Int, Int}, true),
        # V9f — catch/3: the catcher search and catch/3's exit position (src/pl-wam.jl)
        (LK.findCatcher, Tuple{GD, LD, Int, Int, Int, Int}, false),
        (LK.findCatchExit, Tuple{GD}, false),
        # …run with no exception pending (src/pl-attvar.jl)
        (LK.saveWakeup, Tuple{LD, Bool}, false),
        (LK.restore_exception, Tuple{LD, Int}, false),
        (LK.restoreWakeup, Tuple{LD, LK.wakeup_state}, false),
        # V9f — `$/1`, `$/0`: the determinism errors (src/pl-wam.jl, pl-comp.jl, pl-error.jl) and
        # the frame's variables made fresh before its goal is decompiled (src/pl-gc.jl)
        (LK.determinism_error, Tuple{LD, Int, Int, Symbol}, false),
        (LK.ssu_or_det_failed, Tuple{LD, Int}, false),
        (LK.frameFailed, Tuple{LD, Int}, false),
        (LK.det_goal_error, Tuple{LD, Int, Int, Symbol}, false),
        (LK.start_of_cdet, Tuple{C, Int}, false),
        (LK.decompile_body_range, Tuple{LD, Int, Int, C, Int, UInt64}, false),
        (LK.clearUninitialisedVarsFrame, Tuple{LD, Int, Vector{LK.code}, Int}, false),
        (LK._setVar!, Tuple{LD, Int, Int}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, D, T, T, T}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, Int, T, T}, false),
        # V9g — the cleanup family: the handler and its callers (src/pl-wam.jl), calling a goal
        # from foreign code and sig_atomic/1 (src/pl-pro.jl), the boot clauses (src/pl-ext.jl)
        (LK.unify_finished, Tuple{LD, Int, LK.finished}, false),
        (LK.call1, Tuple{GD, LD, Int}, false),
        (LK.call_term, Tuple{GD, LD, Int}, false),
        (LK.callCleanupHandler, Tuple{LD, Int, LK.finished}, false),
        (LK.frameFinished, Tuple{LD, Int, LK.finished}, false),
        (LK.mustBeCallable, Tuple{LD, Int}, false),
        (LK.callProlog, Tuple{GD, LD, Int, Int, UInt32}, false),
        (LK.pl_sig_atomic1_va, Tuple{LD, Int, Int, LK.control_t{T}}, false),
        (LK._boot_cleanup!, Tuple{GD}, false),
        (LK._boot_clause!, Tuple{GD, LD, Symbol, Vector{T}, T, UInt64}, false),
        (LK._boot_clause!, Tuple{GD, LD, Symbol, Vector{T}, Nothing, UInt64}, false),
        # V9g-b — the bags: recorded terms (src/pl-rec.jl), findall/3's bag (src/pl-bag.jl), the
        # sorts and '$length'/2 (src/pl-list.jl), what bagof/3 and setof/3 call of pl-prims.c, the
        # list and functor unifiers (src/pl-fli.jl), the boot clauses (src/pl-ext.jl)
        (LK.compileTermToHeap, Tuple{LD, Int}, false),
        (LK._rec_var, Tuple{LK.PL_local_data{T}, Dict{UInt64, T}, UInt64}, false),
        (LK._rec_block!, Tuple{LK.PL_local_data{T}, Dict{UInt64, T}, T}, false),
        (LK._rec_copy, Tuple{LK.PL_local_data{T}, Dict{UInt64, T}, T}, false),
        (LK.copyRecordToGlobal, Tuple{LD, Int, LK.record{T}}, false),
        (LK.current_bag, Tuple{LD}, true),
        (LK.add_findall_bag, Tuple{LD, Int, Int}, false),
        (LK._sort_compare, Tuple{LD, LK.List_Record{T}, Int, Int, LK.sort_order}, false),
        (LK.nat_sort, Tuple{LD, LK.List_Record{T}, Int, Bool, LK.sort_order}, false),
        (LK.extract_key, Tuple{LD, T, Bool}, false),
        (LK.prolog_list_to_sort_list, Tuple{LD, Int, Bool, Bool}, false),
        (LK.put_sort_list, Tuple{LD, Int, LK.List_Record{T}, Int}, false),
        (LK.pl_nat_sort, Tuple{LD, Int, Int, Bool, LK.sort_order, Bool}, false),
        (LK.ph_ground, Tuple{LD, T}, false),
        (LK.ground, Tuple{LD, T}, false),
        (
            LK.term_variables_loop,
            Tuple{LD, LK.term_agenda{T}, Int, Vector{T}, Set{UInt64}, IdDict{T, Nothing}},
            false
        ),
        (LK.term_variables_to_termv, Tuple{LD, Int, Int}, false),
        (LK.term_variables, Tuple{LD, Int, Int, Int}, false),
        (LK.free_variables_loop, Tuple{LD, T, Vector{T}}, false),
        (LK.PL_cons_list, Tuple{LD, Int, Int, Int}, false),
        (LK.PL_unify_list, Tuple{LD, Int, Int, Int}, false),
        (LK.PL_unify_nil, Tuple{LD, Int}, false),
        (LK.PL_skip_list, Tuple{LD, Int}, false),
        (LK.PL_unify_functor, Tuple{LD, Int, T, Int}, false),
        (LK.PL_unify_arg, Tuple{LD, Int, Int, Int}, false),
        (LK.PL_get_size_ex, Tuple{LD, Int}, false),
        [
            (f, Tuple{LD, Int, Int, LK.control_t{T}}, false) for f in (
                LK.pl_new_findall_bag0_va, LK.pl_add_findall_bag1_va,
                LK.pl_add_findall_bag2_va, LK.pl_collect_findall_bag2_va,
                LK.pl_destroy_findall_bag0_va, LK.pl_is_list1_va, LK.pl_dlength2_va,
                LK.pl_sort2_va, LK.pl_msort2_va, LK.pl_keysort2_va, LK.pl_ground1_va,
                LK.pl_functor3_va, LK.pl_term_variables2_va, LK.pl_term_variables3_va,
                LK.pl_free_variable_set3_va, LK.pl_skip_list3_va
            )
        ]...,
        (LK._boot_term, Tuple{Symbol, Vector{T}}, false),
        (LK._boot_conj, Tuple{Vector{T}}, false),
        (LK._boot_ite, Tuple{Type{T}, T, T, T}, false),
        (LK._boot_cons, Tuple{Type{T}, T, T}, false),
        (LK._boot_vars, Tuple{Type{T}, Int}, false),
        (LK._boot_length_error, Tuple{Type{T}, T, T}, false),
        (LK._boot_lists!, Tuple{GD}, false),
        (LK._boot_bags!, Tuple{GD}, false),
        (LK._boot_bagof!, Tuple{GD, LD}, false),
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
        (LK.PL_is_variable, Tuple{LD, Int}, false),   # L1c: the cold export (words: L1d/L1e)
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
        (LK._boot_catch3!, Tuple{GD}, false),                   # V9f: boot/init.pl's catch/3
        (LK.pl_true, Tuple{LD}, true), (LK.pl_fail, Tuple{LD}, true),   # V9f: true/0, fail/0, $fail/0
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
                LK.pl_unifiable3_va, LK.pl_throw1_va,
                LK.pl_variant2_va, LK.pl_prolog_current_choice1_va,
                LK.pl_copy_term2_va, LK.pl_copy_term_nat2_va, LK.pl_duplicate_term2_va,
                # V6b: the type checks and \\== (src/pl-prims.jl)
                LK.pl_nonvar1_va, LK.pl_var1_va, LK.pl_integer1_va, LK.pl_float1_va,
                LK.pl_rational1_va, LK.pl_string1_va, LK.pl_number1_va, LK.pl_atom1_va,
                LK.pl_atomic1_va, LK.pl_compound1_va, LK.pl_callable1_va, LK.pl_nonequal2_va
            )
        ]...,
        # (L1c: they may reach the cold export on a compound — words at L1e, the FLI over cells)
        [
            (f, Tuple{LD, Int}, false) for f in (
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
        (LK.getUnknownModule, Tuple{GD, MOD}, true),
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
        (LK.dropUnlinkedChoices!, Tuple{LD, Int}, true),
        (LK._is_newest_live_frame, Tuple{LD, Int}, true),
        (LK._call_procedure, Tuple{LD, Int, LK.code}, true),
        # V9c — assert/1, assertz/1, asserta/1 (src/pl-comp.jl, pl-proc.jl, pl-error.jl), over
        # DefaultTerm only, as V4a's: their errors build `Name/Arity` with `mk_gnd(T, ::Int)`
        (LK.assert_term!, Tuple{GD, LD, Int, Int}, false),
        # R1f — the minimal loader: the consult path of assert_term (src/pl-comp.jl), the source
        # files (pl-srcfile.jl), the stream's file name (os/pl-file.jl), the predicate attributes
        # (pl-proc.jl), read_clause and the singletons (pl-read.jl), the messages (pl-error.jl), and
        # boot/init.jl's driver
        (LK.assert_term!, Tuple{GD, LD, Int, Int, Int, Nothing, Nothing, Int}, false),
        (LK.assert_term!, Tuple{GD, LD, Int, Int, Int, T, LK.sourceloc{T}, Int}, false),
        (LK.record_clause, Tuple{LD, Int, Int, Int, Int}, false),
        (LK.pl_record_clause3_va, Tuple{LD, Int, Int, LK.foreign_context{T}}, false),
        (LK.registerSourceFile!, Tuple{GD, LK.SourceFile{T}}, false),
        (LK.indexToSourceFile, Tuple{GD, Int}, false),
        (LK.lookupSourceFile_unlocked, Tuple{GD, T, Bool}, false),
        (LK.lookupSourceFile, Tuple{GD, T, Bool}, false),
        (LK.acquireSourceFile, Tuple{LK.SourceFile{T}}, true),
        (LK.releaseSourceFile, Tuple{LK.SourceFile{T}}, false),
        (LK.hasProcedureSourceFile, Tuple{LK.SourceFile{T}, PR}, true),
        (LK.addProcedureSourceFile, Tuple{LK.SourceFile{T}, PR}, false),
        (LK.assertProcedureSource, Tuple{GD, LK.SourceFile{T}, PR, C}, false),
        (LK.assertProcedureSource, Tuple{GD, Nothing, PR, C}, false),
        (LK.associateSource, Tuple{LK.SourceFile{T}, PR}, false),
        (LK.setAttrProcedureSource, Tuple{LK.SourceFile{T}, PR, UInt64, Bool}, false),
        (LK.startConsult, Tuple{LK.SourceFile{T}}, false),
        (LK.endConsult, Tuple{LK.SourceFile{T}}, false),
        (LK.fileNameStream, Tuple{GD, LK.IOSTREAM}, false),
        (LK.setFileNameStream, Tuple{GD, LK.IOSTREAM, T}, false),
        (LK.setFileNameStream, Tuple{GD, LK.IOSTREAM, Nothing}, false),
        (LK.printMessage, Tuple{LD, Symbol, T}, false),
        (LK.PL_error, Tuple{LD, LK.PL_error_code, T, T, PR}, false),
        (LK.overruleImportedProcedure, Tuple{GD, LD, PR, MOD}, false),
        (LK.redefineProcedure, Tuple{GD, LD, PR, LK.SourceFile{T}, Int}, false),
        (LK.lookupProcedureToDefine, Tuple{GD, LD, T, Int, MOD}, false),
        (LK.attribute_mask, Tuple{LD, T}, false),
        (LK.get_bool_or_int_ex, Tuple{LD, Int}, false),
        (LK.get_procedure, Tuple{GD, LD, Int, Int}, false),
        (
            LK.pl_set_predicate_attribute3_va,
            Tuple{LD, Int, Int, LK.foreign_context{T}},
            false
        ),
        (LK.setAttrDefinition, Tuple{D, UInt64, Bool}, false),
        (LK.var_name_body, Tuple{VIEW}, true),
        (LK._cbyte, Tuple{VIEW, Int}, true),
        (LK.warn_singleton, Tuple{VIEW}, false),
        (LK.warn_multiton, Tuple{VIEW}, false),
        (LK.atom_is_named_var, Tuple{typeof(codeunits(""))}, false),
        (LK.is_singleton, Tuple{LK.variable, Int, LK.read_data{T}}, false),
        (LK.singletonWarning, Tuple{Int, String, Vector{String}, LK.read_data{T}}, false),
        (LK.check_singletons, Tuple{Int, LK.read_data{T}}, false),
        (LK.reportReadError, Tuple{LK.read_data{T}}, false),
        (LK.set_module_read_data, Tuple{LK.read_data{T}, Int}, false),
        (LK.read_clause, Tuple{GD, LD, LK.IOSTREAM, Int, Int}, false),
        (LK.load_file!, Tuple{GD, LD, String}, false),
        (LK._init_is, Tuple{LD, T, Symbol, Int}, false),
        (LK.valid_term, Tuple{LD, T}, false),
        (LK.compile_term!, Tuple{GD, LD, Int, T}, false),
        (LK._init_error, Tuple{Type{T}, T}, false),
        (LK.store_clause!, Tuple{GD, LD, Int, T}, false),
        (LK._is_error_term, Tuple{LD, T}, false),
        (LK._init_call, Tuple{GD, LD, PR, Int}, false),
        (LK.execute_directive!, Tuple{GD, LD, Int}, false),
        (LK._init_conjuncts!, Tuple{Vector{T}, LD, T}, false),
        (LK._init_solve, Tuple{GD, LD, Vector{T}, Int, MOD}, false),
        (LK.pattr_directive!, Tuple{GD, LD, T, MOD}, false),
        (LK.set_pattr!, Tuple{GD, LD, T, MOD, T}, false),
        (LK._pattr_error, Tuple{LD, T, T}, false),
        (LK._pi_head, Tuple{LD, T}, false),
        (LK._pi_error, Tuple{Type{T}, T}, false),
        (LK._redefine_indicator, Tuple{GD, D}, false),
        (LK.get_head_and_body_clause, Tuple{GD, LD, Int, Int, Int, Int}, false),
        (LK.is_neck, Tuple{LD, Int}, false),
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

const _DISPATCH_MANIFEST_TUPLE = (
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
    (LK.functor_operand, Tuple{UInt64, Int, UInt64}, false),
    (LK.functor_operand_word, Tuple{UInt64}, true),
    (LK._is_gcompound, Tuple{UInt64}, true),
    (LK.functor_literal, Tuple{UInt64}, true), (LK.functor_arity, Tuple{UInt64}, true),
    (LK.atom_operand, Tuple{UInt64, UInt64}, false),
    (LK.atom_literal, Tuple{UInt64}, true), (LK.atom_operand_word, Tuple{UInt64}, true),
    (LK.VAROFFSET, Tuple{Int}, true), (LK.VARNUM, Tuple{UInt64}, true),
    (LK.sizeofClause, Tuple{Int}, true),
    (LK.argFrameP, Tuple{Int, Int}, true), (LK.varFrameP, Tuple{Int, Int}, true),
    (LK.refFliP, Tuple{Int, Int}, true), (LK.f_hasSpace, Tuple{Int, Int, Int, Int}, true),
    (LK.NoMark, Tuple{}, true), (LK.isRealMark, Tuple{LK.mark}, true),
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
    # R1c — the scanner's term-independent parts: UTF-8 (src/os/pl-utf8.jl), the Unicode map
    # (src/pl-umap.jl), the character types (src/os/pl-ctype.jl), digitValue (src/os/pl-string.jl),
    # the streams (src/os/pl-stream.jl), the classifiers, buffers and numbers of src/pl-read.jl;
    # the classifiers are table lookups, allocation-free (`true`)
    (LK.CharTypeA, Tuple{Int64}, true),
    (LK.ISUTF8_CB, Tuple{Int64}, true),
    (LK.ISUTF8_FB2, Tuple{Int64}, true),
    (LK.ISUTF8_FB3, Tuple{Int64}, true),
    (LK.ISUTF8_FB4, Tuple{Int64}, true),
    (LK.ISUTF8_FB5, Tuple{Int64}, true),
    (LK.ISUTF8_FB6, Tuple{Int64}, true),
    (LK.ISUTF8_MB, Tuple{Int64}, true),
    (LK.IS_UTF16_SURROGATE, Tuple{Int64}, true),
    (LK.NaN_value, Tuple{Float64}, false),
    (LK.PL_ctype_flags, Tuple{Int64}, true),
    (LK.PL_nan, Tuple{}, true),
    (LK.PL_wcwidth, Tuple{Int64}, true),
    (LK.PlBlankW, Tuple{Int64}, true),
    (LK.PlCatW, Tuple{Int64}, true),
    (LK.PlDecimalW, Tuple{Int64}, true),
    (LK.PlIdContW, Tuple{Int64}, true),
    (LK.PlIdStartW, Tuple{Int64}, true),
    (LK.PlInvalidW, Tuple{Int64}, true),
    (LK.PlPunctW, Tuple{Int64}, true),
    (LK.PlSoloW, Tuple{Int64}, true),
    (LK.PlSymbolW, Tuple{Int64}, true),
    (LK.PlUpperW, Tuple{Int64}, true),
    (LK.S__close, Tuple{LK.IOSTREAM}, false),
    (LK.S__fillbuf, Tuple{LK.IOSTREAM}, false),
    (LK.S__flushbuf, Tuple{LK.IOSTREAM}, false),
    (LK.S__flushbufc, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.S__fupdatefilepos_getc, Tuple{LK.IOSTREAM, Int64}, false),
    (LK.S__memfile_nextsize, Tuple{Int64}, true),
    (LK.S__removebuf, Tuple{LK.IOSTREAM}, false),
    (LK.S__setbuf, Tuple{LK.IOSTREAM, Nothing, Int64}, false),
    (LK.S__setbuf, Tuple{LK.IOSTREAM, Vector{UInt8}, Int64}, false),
    (LK.S__seterror, Tuple{LK.IOSTREAM}, false),
    (LK.S__updatefilepos, Tuple{LK.IOSTREAM, Int64}, false),
    (LK.S__updatefilepos_getc, Tuple{LK.IOSTREAM, Int64}, false),
    (LK.S_close, Tuple{LK.IOSTREAM}, false),
    (LK.S_read, Tuple{LK.IOSTREAM, Vector{UInt8}, Int64, Int64}, false),
    (LK.S_write, Tuple{LK.IOSTREAM, Vector{UInt8}, Int64, Int64}, false),
    (LK.Scanrepresent, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.Sclearerr, Tuple{LK.IOSTREAM}, false),
    (LK.Sclose, Tuple{LK.IOSTREAM}, false),
    (LK.Sclose_julia_io, Tuple{LK.Sjulia_io}, false),
    (LK.Sclose_memfile, Tuple{LK.memfile}, false),
    (LK.Sclose_string, Tuple{LK.IOSTREAM}, false),
    (LK.Sfeof, Tuple{LK.IOSTREAM}, false),
    (LK.Sferror, Tuple{LK.IOSTREAM}, true),
    (LK.Sflush, Tuple{LK.IOSTREAM}, false),
    (LK.Sfpasteof, Tuple{LK.IOSTREAM}, true),
    (LK.Sgetc, Tuple{LK.IOSTREAM}, false),
    (LK.Sgetcode, Tuple{LK.IOSTREAM}, false),
    (LK.SkipAtomIdCont, Tuple{Vector{UInt8}, Int64}, true),
    (LK.SkipVarIdCont, Tuple{Vector{UInt8}, Int64}, true),
    (LK.Snew, Tuple{LK.memfile, UInt32, LK.IOFUNCTIONS}, false),
    (LK.Snew, Tuple{LK.Sjulia_io, UInt32, LK.IOFUNCTIONS}, false),
    (LK.Snpgetc, Tuple{LK.IOSTREAM}, false),
    (LK.Sopen_julia_io, Tuple{IOStream, String, Bool}, false),
    (LK.Sopen_julia_io, Tuple{IOBuffer, String, Bool}, false),
    (LK.Sopen_julia_io, Tuple{Base.TTY, String, Bool}, false),
    (LK.Sopen_julia_io, Tuple{Base.PipeEndpoint, String, Bool}, false),
    # R1e — the write/1 family: the standard streams over the process's IO, option tables
    (LK._std_stream, Tuple{IOBuffer, UInt32}, false),
    (LK._std_stream, Tuple{IOStream, UInt32}, false),
    (LK.HAS_OPT_MODE, Tuple{Int64, Int64}, true),
    (LK.PL_option_t, Tuple{Symbol, Int64}, false),
    (LK.Sopen_string, Tuple{Vector{UInt8}, Int64, String}, false),
    (
        LK.Sopenmem,
        Tuple{Base.RefValue{Union{Nothing, Vector{UInt8}}}, Nothing, String},
        false
    ),
    (
        LK.Sopenmem,
        Tuple{Base.RefValue{Union{Nothing, Vector{UInt8}}}, Base.RefValue{Int64}, String},
        false
    ),
    (LK.Speekcode, Tuple{LK.IOSTREAM}, false),
    (LK.Sputc, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.Sputcode, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.Sread_julia_io, Tuple{LK.Sjulia_io, Vector{UInt8}, Int64, Int64}, false),
    (LK.Sread_memfile, Tuple{LK.memfile, Vector{UInt8}, Int64, Int64}, false),
    (LK.Sread_string, Tuple{LK.IOSTREAM, Vector{UInt8}, Int64, Int64}, false),
    (LK.Sresetesc, Tuple{LK.IOPOS}, true),
    (LK.Sseek_memfile64, Tuple{LK.memfile, Int64, Int64}, false),
    (LK.Sseterr, Tuple{LK.IOSTREAM, UInt32, Nothing}, false),
    (LK.Sseterr, Tuple{LK.IOSTREAM, UInt32, String}, false),
    (LK.Sungetc, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.Supdateesc, Tuple{LK.IOPOS, Int64}, true),
    (LK.Supdatepos, Tuple{LK.IOPOS, Int64}, true),
    (LK.Swrite_julia_io, Tuple{LK.Sjulia_io, Vector{UInt8}, Int64, Int64}, false),
    (LK.Swrite_memfile, Tuple{LK.memfile, Vector{UInt8}, Int64, Int64}, false),
    (LK.Swrite_string, Tuple{LK.IOSTREAM, Vector{UInt8}, Int64, Int64}, false),
    (LK.UTF8_FBN, Tuple{Int64}, true),
    (LK.UTF8_FBV, Tuple{Int64, Int64}, true),
    (LK.U_CAT_OF, Tuple{UInt8}, true),
    (LK.U_CTYPE_OF, Tuple{UInt8}, true),
    (LK.VALID_CODE_POINT, Tuple{Int64}, true),
    (LK._PL__utf8_code_point, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK._PL__utf8_get_char, Tuple{Vector{UInt8}, Int64}, true),
    (LK._PL__utf8_put_char, Tuple{Vector{UInt8}, Int64}, false),
    (LK._atoi, Tuple{Vector{UInt8}, Int64}, true),
    (LK._byte, Tuple{Vector{UInt8}, Int64}, true),
    (LK._char_type, Tuple{Int64}, true),
    (LK._number_text, Tuple{LK.number}, false),
    (LK._same_bytes, Tuple{Vector{UInt8}, Int64, Vector{UInt8}, Int64}, false),
    (LK._strtod, Tuple{Vector{UInt8}, Int64}, false),
    (LK.addUTF8Buffer, Tuple{Vector{UInt8}, Int64}, false),
    (LK.ar_rdiv_mpz, Tuple{LK.number, LK.number, LK.number}, false),
    (LK.backSkipBlanks, Tuple{Vector{UInt8}, Int64, Int64}, false),
    (LK.backSkipUTF8, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.backskip_utf8, Tuple{Vector{UInt8}, Int64}, true),
    (LK.clearNumber, Tuple{LK.number}, false),
    (LK.decimal_weight, Tuple{Int64}, false),
    (LK.digitValue, Tuple{Int64, Int64}, true),
    (LK.float_tag, Tuple{Vector{UInt8}, Int64, String}, false),
    (LK.get_byte, Tuple{LK.IOSTREAM}, false),
    (LK.isAlpha, Tuple{Int64}, true),
    (LK.isAnonVarNameN, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.isBlank, Tuple{Int64}, true),
    (LK.isBlankW, Tuple{Int64}, true),
    (LK.isControl, Tuple{Int64}, true),
    (LK.isDecimal, Tuple{Int64, Int64}, true),
    (LK.isDigit, Tuple{Int64}, true),
    (LK.isDigitW, Tuple{Int64}, true),
    (LK.isGraph, Tuple{Int64}, true),
    (LK.isLetter, Tuple{Int64}, true),
    (LK.isLower, Tuple{Int64}, true),
    (LK.isPunct, Tuple{Int64}, true),
    (LK.isPunctW, Tuple{Int64}, true),
    (LK.isSign, Tuple{Int64}, true),
    (LK.isSolo, Tuple{Int64}, true),
    (LK.isStringStream, Tuple{LK.IOSTREAM}, true),
    (LK.isSymbol, Tuple{Int64}, true),
    (LK.isSymbolW, Tuple{Int64}, true),
    (LK.isUpper, Tuple{Int64}, true),
    (LK.isVarPrefixSymbol, Tuple{Int64}, true),
    (LK.is_bidi_override, Tuple{Int64}, true),
    (LK.is_eol_char, Tuple{Int64}, true),
    (LK.make_nan, Tuple{Float64}, true),
    (LK.matchingBracket, Tuple{Int64}, true),
    (LK.pl_cat_is_id_continue, Tuple{LK.u_category}, true),
    (LK.pl_cat_is_id_start, Tuple{LK.u_category}, true),
    (LK.pl_cat_is_solo, Tuple{LK.u_category}, true),
    (LK.pl_pair_lookup, Tuple{Int64}, true),
    (LK.points_at_decimal, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.prev_code, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.put_byte, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.put_code, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.reperror, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.scan_decimal, Tuple{Vector{UInt8}, Int64, Int64, Bool, LK.number}, false),
    (LK.scan_number, Tuple{Vector{UInt8}, Int64, Bool, Int64, LK.number}, false),
    (LK.skipSpaces, Tuple{Vector{UInt8}, Int64}, true),
    (LK.skip_decimal_separator, Tuple{Vector{UInt8}, Int64, Int64}, false),
    (LK.skip_decimals, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.skip_digit_separator, Tuple{Vector{UInt8}, Int64, Int64}, false),
    (LK.special_float, Tuple{Vector{UInt8}, Int64, Int64, LK.number}, false),
    (LK.starts_1dot, Tuple{Vector{UInt8}, Int64}, true),
    (LK.str_number_error, Tuple{LK.strnumstat}, true),
    (LK.uctypeFlagsW, Tuple{Int64}, true),
    (LK.uctypeRaw, Tuple{Int64}, true),
    (LK.uflagsRaw, Tuple{Int64}, true),
    (LK._map_entry, Tuple{String, Int64}, true),
    (LK.unget_byte, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.update_linepos, Tuple{LK.IOSTREAM, Int64}, false),
    (LK.utf8_backskip_char, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.utf8_code_bytes, Tuple{Int64}, true),
    (LK.utf8_get_char, Tuple{Vector{UInt8}, Int64}, true),
    (LK.utf8_put_char, Tuple{Vector{UInt8}, Int64}, false),
    (LK.utf8_skip_blanks, Tuple{Vector{UInt8}, Int64}, true),
    (LK.utf8_skip_char, Tuple{Vector{UInt8}, Int64}, true),
    (LK.utf8_skip_char_e, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.utf8_strlen, Tuple{Vector{UInt8}, Int64, Int64}, true),
    (LK.variableHash, Tuple{LK.variable}, false),
    # the enums R1c adds
    (Base.Enums._enum_hash, Tuple{LK.av_action, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.cb_kind, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.IOENC, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.IOFUNCTIONS, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.Sunicode_atoms_t, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.strnumstat, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.token_type, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.u_category, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.u_ctype, UInt64}, false),
    # R1d — the parser's enums, the classifiers and quoting rules (src/pl-read.jl, pl-write.jl),
    # the text conversion's (src/pl-incl.jl, os/pl-text.jl)
    (Base.Enums._enum_hash, Tuple{LK.pf_kind, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.pf_after, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.reduce_side, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.CVT_status, UInt64}, false),
    (LK.f_is_prolog_var_start, Tuple{Int64}, true),
    (LK.f_is_prolog_atom_start, Tuple{Int64}, true),
    (LK.f_is_prolog_identifier_continue, Tuple{Int64}, true),
    (LK.f_is_prolog_symbol, Tuple{Int64}, true),
    (LK.f_is_prolog_solo, Tuple{Int64}, true),
    (LK.f_is_pattern_syntax, Tuple{Int64}, true),
    (LK.f_paren_close, Tuple{Int64}, true),
    (LK.stop_matches_codepoint, Tuple{String, Int64}, true),
    (LK.isAnonVarName, Tuple{Vector{UInt8}}, true),
    (LK.wr_is_symbol, Tuple{Int64, Int64}, true),
    (LK.wr_is_solo, Tuple{Int64, Int64}, true),
    (LK.code_requires_quoted, Tuple{Int64, Nothing, Int64}, false),
    (LK.code_requires_quoted, Tuple{Int64, LK.IOSTREAM, Int64}, false),
    (LK.atomType, Tuple{String}, false),
    (LK.unquoted_text, Tuple{String, Nothing, Int64}, false),
    (LK.unquoted_text, Tuple{String, LK.IOSTREAM, Int64}, false),
    (LK.unquoted_atomW, Tuple{String, Nothing, Int64}, false),
    # R1e — the writer's core: quoting with options, the token layer (src/pl-write.jl)
    (Base.Enums._enum_hash, Tuple{LK.wf_kind, UInt64}, false),
    # V9g-b — the sorts' enums (src/pl-list.jl)
    (Base.Enums._enum_hash, Tuple{LK.sort_order, UInt64}, false),
    (Base.Enums._enum_hash, Tuple{LK.list_sort, UInt64}, false),
    (LK._signed_char, Tuple{Int64}, true),
    (LK.text_has_combining, Tuple{String}, false),
    (LK.atom_has_combining, Tuple{String}, false),
    (LK._is_ucs_text, Tuple{String}, false),
    (LK.atomType, Tuple{String, Nothing, Int64}, false),
    (LK.atomType, Tuple{String, LK.IOSTREAM, Int64}, false),
    (LK.unquoted_atomW, Tuple{String, LK.IOSTREAM, Int64}, false),
    (LK.atomIsVarName, Tuple{String, Int64}, false),
    (LK.atomIsAnyVarName, Tuple{String}, false),
    (LK.Putc, Tuple{Int64, LK.IOSTREAM}, false),
    (LK.PutString, Tuple{String, LK.IOSTREAM}, false),
    (LK.isquote, Tuple{Int64, Int64}, true),
    (LK.needSpace, Tuple{Int64, LK.IOSTREAM, Int64}, false),
    (LK.PutOpenToken, Tuple{Int64, LK.IOSTREAM, Int64}, false),
    (LK.PutToken, Tuple{String, LK.IOSTREAM, Int64}, false),
    (LK.PutCloseBrace, Tuple{LK.IOSTREAM}, false),
    (LK.unicode_quoted_escape, Tuple{Int64}, false),
    (LK.putQuoted, Tuple{Int64, Int64, Int64, LK.IOSTREAM}, false),
    (LK.separate_number, Tuple{LK.IOSTREAM, Bool, String}, false),
    # R1e's floats: pl-write.c format_float and its NaN/Inf texts
    (LK.format_float, Tuple{Float64, Int64, Char}, false),
    (LK.format_special_float, Tuple{Float64}, false),
    (LK._dtoa_mode0, Tuple{Float64}, false),
    (LK.writeNaN, Tuple{Float64}, false), (LK.writeINF, Tuple{Float64}, false),
    (LK.Sopen_text, Tuple{LK.PL_chars_t, String}, false),
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
    (Base.Enums._enum_hash, Tuple{LK.stack_overflow_action, UInt64}, false),
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
    (LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_proc)}, false),   # R1f
    # the built-ins' dispatch trees, built when src/pl-ext.jl loads
    (LK._foreign_tree, Tuple{Symbol, Int, Int, typeof(LK._va_leaf)}, false),
    (LK._foreign_tree, Tuple{Symbol, Int, Int, typeof(LK._det_leaf)}, false),
    (LK._va_leaf, Tuple{Int}, false), (LK._det_leaf, Tuple{Int}, false),
    # the atom table (L1b stage A: src/pl-atom.jl; pl-data.h's indexAtom/atomValue, pl-inline.h's
    # fetchAtomArray, pl-ressymbol.c's initReservedSymbols, pl-fli.c's lookupUCSAtom, pl-text.c)
    (LK.atoms_t, Tuple{}, false),
    (LK._blob_registration, Tuple{LK.atoms_t, LK.PL_blob_t}, false),
    (LK.PL_register_blob_type, Tuple{LK.atoms_t, LK.PL_blob_t}, false),
    (LK.PL_register_blob_type, Tuple{LK.atoms_t, LK.PL_blob_t, UInt64}, false),
    (LK.allocateAtomBlock, Tuple{LK.atoms_t, Int}, false),
    (LK.reserveAtom, Tuple{LK.atoms_t}, false),
    (LK.same_name, Tuple{LK.atom, Vector{UInt8}, Int, LK.PL_blob_t}, false),
    (LK.lookupBlob, Tuple{LK.atoms_t, Vector{UInt8}, Int, LK.PL_blob_t}, false),
    (LK.lookupAtom, Tuple{LK.atoms_t, Vector{UInt8}}, false),
    (LK.lookupAtom, Tuple{LK.atoms_t, Vector{UInt8}, Int}, false),
    (LK.rehashAtoms, Tuple{LK.atoms_t}, false),
    (LK.registerBuiltinAtoms, Tuple{LK.atoms_t}, false),
    (LK.lockAtoms, Tuple{LK.atoms_t}, true),
    (LK.builtin_atom, Tuple{String}, false),
    (LK.do_init_atoms!, Tuple{LK.atoms_t}, false),
    (LK.indexAtom, Tuple{UInt64}, true),
    (LK.atomValue, Tuple{LK.atoms_t, UInt64}, true),
    (LK.fetchAtomArray, Tuple{LK.atoms_t, Int}, true),
    (LK.ATOM_IS_FREE, Tuple{UInt32}, true), (LK.ATOM_IS_RESERVED, Tuple{UInt32}, true),
    (LK.ATOM_IS_VALID, Tuple{UInt32}, true),
    (LK.initReservedSymbols!, Tuple{LK.atoms_t}, false),
    (LK.lookupUCSAtom, Tuple{LK.atoms_t, Vector{UInt32}}, false),
    (LK.lookupUCSAtom, Tuple{LK.atoms_t, Vector{UInt32}, Int}, false),
    (LK.PL_canonicalise_text, Tuple{LK.PL_chars_t}, false),
    (LK.textToAtom, Tuple{LK.atoms_t, LK.PL_chars_t}, false),
    # the functor table (L1b stage B: src/pl-funct.jl; pl-data.h's indexFunctor/valueFunctor/
    # arityFunctor/isAtomFunctor/nameFunctor, pl-inline.h's fetchFunctorArray, os/pl-table.h's
    # pointerHashValue)
    (LK.functors_t, Tuple{}, false),
    (LK.FUNCTOR_IS_VALID, Tuple{UInt32}, true),
    (LK.pointerHashValue, Tuple{UInt64, Int}, true),
    (LK.allocateFunctorBlock, Tuple{LK.functors_t, Int}, false),
    (LK.registerFunctor, Tuple{LK.functors_t, LK.functorDef}, false),
    (LK.lookupFunctorDef, Tuple{LK.functors_t, UInt64, Int}, false),
    (LK.rehashFunctors, Tuple{LK.functors_t}, false),
    (LK.isCurrentFunctor, Tuple{LK.functors_t, UInt64, Int}, false),
    (LK.allocFunctorTable, Tuple{LK.functors_t}, false),
    (LK.registerBuiltinFunctors, Tuple{LK.functors_t}, false),
    (LK.builtin_functor, Tuple{String, Int}, false),
    (LK.registerControlFunctors!, Tuple{LK.functors_t}, false),
    (LK.registerArithFunctors!, Tuple{LK.functors_t}, false),
    (LK.initFunctors!, Tuple{LK.functors_t}, false),
    (LK.indexFunctor, Tuple{UInt64}, true),
    (LK.valueFunctor, Tuple{LK.functors_t, UInt64}, true),
    (LK._arityFunc_, Tuple{UInt64}, true),
    (LK.arityFunctor, Tuple{LK.functors_t, UInt64}, true),
    (LK.isAtomFunctor, Tuple{LK.functors_t, UInt64}, true),
    (LK.nameFunctor, Tuple{LK.functors_t, UInt64}, true),
    (LK.fetchFunctorArray, Tuple{LK.functors_t, Int}, true),
    # the words of the stacks (L1b stage C1: pl-data.h, pl-inline.h's consPtr/valPtr, pl-gmp.h's
    # size words) — pure bit operations: none allocates
    (LK._slot_word_error, Tuple{UInt64}, false),  # (builds its error: the slot words' bad case)
    (LK.tag, Tuple{UInt64}, true),
    (LK.storage, Tuple{UInt64}, true),
    (LK.valInt, Tuple{UInt64}, true),
    (LK.valUInt, Tuple{UInt64}, true),
    (LK.EXBIT, Tuple{UInt64}, true),
    (LK.isIndirect, Tuple{UInt64}, true),
    (LK.isVar, Tuple{UInt64}, true),
    # the cell agenda of do_unify_cells (L1c-4): the push may grow its stack
    (LK.initCellAgendaLR!, Tuple{LK.cell_agendaLR, Int, Int, Int, Int}, true),
    (LK.clearCellAgendaLR!, Tuple{LK.cell_agendaLR}, true),
    (LK.nextCellAgendaLR!, Tuple{LK.cell_agendaLR}, true),
    (LK.pushWorkCellAgendaLR!, Tuple{LK.cell_agendaLR, Int, Int, Int, Int}, false),
    (LK.isAtomW, Tuple{UInt64}, true),
    (LK.isRationalW, Tuple{UInt64}, true),
    (LK.isFloatW, Tuple{UInt64}, true),
    (LK.isStringW, Tuple{UInt64}, true),
    (LK.isTermW, Tuple{UInt64}, true),
    (LK.isTaggedIntW, Tuple{UInt64}, true),
    (LK.isConst, Tuple{UInt64}, true),
    (LK.isRef, Tuple{UInt64}, true),
    (LK.isAttVar, Tuple{UInt64}, true),
    (LK.needsRef, Tuple{UInt64}, true),
    (LK.wsizeofInd, Tuple{UInt64}, true),
    (LK.padHdr, Tuple{UInt64}, true),
    (LK.mpz_stack_size, Tuple{UInt64}, true),
    (LK.mpq_stack_size, Tuple{UInt64}, true),
    (LK.valPtr, Tuple{UInt64}, true),
    (LK.unRef, Tuple{UInt64}, true),
    (LK.consInt, Tuple{Int64}, true), (LK.consUInt, Tuple{UInt64}, true),
    (LK.consPtr, Tuple{Int, UInt64}, true), (LK.makeRefG, Tuple{Int}, true),
    (LK.makeRefLok, Tuple{Int}, true), (LK.mkIndHdr, Tuple{Int, UInt64}, true),
    (LK.mkPadHdr, Tuple{Int}, true), (LK.mkBlobHdr, Tuple{Int, Int, UInt64}, true),
    (LK.mpz_size_stack, Tuple{Int32}, true), (LK.mpq_size_stack, Tuple{Int32}, true),
    (LK.AtomNotRepresentableError, Tuple{Vector{UInt32}}, false),
    (LK.tagTrailPtr, Tuple{Int}, true), (LK.isTrailVal, Tuple{UInt64}, true),
    (LK.trailValP, Tuple{UInt64}, true), (LK._trail_addr, Tuple{Int, Int}, true),
    (LK._trail_stack, Tuple{UInt64}, true), (LK._trail_pos, Tuple{UInt64}, true)
)

"""
One entry of the manifest, `(f, argument types, must_not_allocate)`, as ONE concrete type.

The entries are written as tuples, and a tuple of them has a different element type per entry:
every loop and every closure over it made Julia infer that whole tuple type again. MEASURED
2026-10-11, 1,663 entries, a fresh process: ~10 s for each closure (30 in the call-path test
alone) and ~120 s for the duplicate check — 410 of the gate's 783 s, none of it analysis; a warm
daemon paid it again on every preflight, each run's closures being new. A `Vector` of one struct
type costs nothing to walk. An entry destructures and indexes as its tuple did, so the gate's code
(test/static_analysis_body.jl, `manifest_uncovered`) reads either.
"""
struct ManifestEntry
    f::Union{Function, Type}
    tt::Type
    noalloc::Bool
end
Base.iterate(e::ManifestEntry, i::Int=1) = i > 3 ? nothing : (getfield(e, i), i + 1)
Base.getindex(e::ManifestEntry, i::Int) = getfield(e, i)

"""
The entries of the tuple `t`, in order. `t` is read with `getfield` and is not specialised on, so
nothing here is inferred over its type either; an entry of another shape is a `TypeError`.
"""
function _manifest_entries(@nospecialize(t::Tuple))::Vector{ManifestEntry}
    v = ManifestEntry[]
    for i in 1:nfields(t)
        e = getfield(t, i)::Tuple{Union{Function, Type}, Type, Bool}
        push!(v, ManifestEntry(e[1], e[2], e[3]))
    end
    return v
end

const DISPATCH_MANIFEST = _manifest_entries(_DISPATCH_MANIFEST_TUPLE)

# `is_ground(t)` with an untyped argument is the interface's FALLBACK for implementations without a
# cached bit; `Term` overrides it, so no reference type reaches it. (`Tuple{Int}` names the fallback
# method by a non-term argument type — it is the method `which` selects.) Its body is
# `is_ground_walk`, which IS in the manifest.
# L1c's ALLOCATION EXEMPTIONS — a RATCHET (user, 2026-10-15): the functions whose entries were
# allocation-free before L1c and are marked allocating since, because a compound reaching them goes
# through the transitional term boundary (the cold export or import). Each names the step at which
# it is allocation-free again; the list may only SHRINK (`L1C_ALLOC_EXEMPT_MAX`, measured 25), and
# test/static_analysis_body.jl checks that each listed function is marked allocating. A NEW
# exemption joins this list, with its step — never silently.
"The steps that return an L1c exemption to allocation-free."
const L1C_STEPS = ("L1c-5", "L1d", "L1e", "L1f")
"L1c's allocation exemptions: (function, the step at which it is allocation-free again)."
const L1C_ALLOC_EXEMPT = [
    # the term reads that reach a compound's cold export: until no reader takes a term (L1f, with
    # copy_term over cells and the keyed variables gone)
    (LK.deRef, "L1f"), (LK._binding, "L1f"), (LK._cell_value, "L1f"),
    (LK.slotValue, "L1f"), (LK.linkValI, "L1f"), (LK._argp_raw, "L1f"),
    (LK._argp_deref, "L1f"),
    # the term writes that reach the cold import: until the FLI and the built-ins write cells (L1e)
    (LK._slot_store!, "L1e"), (LK._slot_link!, "L1e"), (LK._argp_store!, "L1e"),
    (LK.PL_put_term, "L1e"),
    # the FLI type checks on a compound: words at L1e
    (LK.PL_is_integer, "L1e"), (LK.PL_is_float, "L1e"), (LK.PL_is_rational, "L1e"),
    (LK.PL_is_compound, "L1e"), (LK.PL_is_callable, "L1e"), (LK.PL_is_string, "L1e"),
    (LK.PL_is_atom, "L1e"), (LK.PL_is_atomic, "L1e"), (LK.PL_is_number, "L1e"),
    (LK.PL_is_variable, "L1e"),
    # the term agenda of unification and comparison: over cells at L1d
    (LK.nextTermAgenda!, "L1d"),
    # first-argument indexing: from words at L1c sub-commit 5
    (LK.argv_at, "L1c-5"), (LK.indexKeyFromArgv, "L1c-5"), (LK.is_satifies_index, "L1c-5")
]
"The ratchet: L1c's exemptions may only fall (measured 25, 2026-10-15)."
const L1C_ALLOC_EXEMPT_MAX = 25

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
        (LK.var"@FASTCOND_FAILED", Tuple{LineNumberNode, Module}) => "a macro (pl-vmi.c FASTCOND_FAILED): it builds Exprs at load time; its expansion runs in PL_next_solution_guarded, which is checked"
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
