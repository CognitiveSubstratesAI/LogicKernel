# ORIGINAL: landing C's mutant list — no swipl-devel counterpart.
# tools/mutants/LandC.py — the mutation battery of landing C (f3: f3-1 + f3-2 + f3-3/f3-4; D-0107 item 3: its NEW
# invariants and CHANGED behaviour only — f3-1's and f3-2's own lists, F31.py and F32.py, ran in CI at their steps):
# with the keyed variables gone, a slot's grounded side value is a value read and copied as its side word (Q1 (b)),
# a head constant meets a value by value, and a cyclic Goal@Module's culprit names the goal and the module. Run once,
# in CI, alongside the gate's CI + Evidence (D-0105 item 2; .github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/core_lang/test_slot_indirects.jl",
    "test/core_lang/test_slot_words.jl",
    "test/core_lang/test_metacall_control.jl",
    "test/core_lang/test_head_unify_swipl.jl",
]
MUTANTS = [
    # _deref_loc: a slot's side value is read as its side word (DU_VALUE), the only reading left since f3
    dict(id="C1 a slot's side value is not read as its side word", file="src/pl-prims.jl",
         targets=["test/core_lang/test_slot_indirects.jl", "test/core_lang/test_slot_words.jl"],
         old="            w == SLOT_VALUE && return (DU_VALUE, _side_word(-loc), 0)  # a side value (f3-1, D-0110)\n",
         new=""),
    # _slot_link!: a side value is copied as its value, never as the bare SLOT_VALUE marker
    dict(id="C2 a side value is linked as the bare marker", file="src/pl-inline.jl",
         targets=["test/core_lang/test_slot_indirects.jl", "test/core_lang/test_slot_words.jl"],
         old="        _slot_store!(ld, to, ld.slot_values[from])\n",
         new="        ld.slots[to] = w\n"),
    # unify_simple_ptrs (constants only since f3): two values meet by value
    dict(id="C3 any two values unify", file="src/pl-prims.jl",
         targets=["test/core_lang/test_head_unify_swipl.jl", "test/core_lang/test_slot_indirects.jl"],
         old="        return gnd_equal(t1, t2) ? BOOLEX_TRUE : BOOLEX_FALSE\n",
         new="        return BOOLEX_TRUE\n"),
    # i_metacall_clause: a cyclic Goal@Module's culprit keeps the goal's functor ...
    dict(id="C4 the cyclic goal's functor is lost from the culprit", file="src/pl-wam.jl",
         targets=["test/core_lang/test_metacall_control.jl"],
         old="                    push!(mc_args, mk_expr(T, mc_ac))\n",
         new="                    push!(mc_args, mk_var(T, fresh_var_keys!(1)))\n"),
    # ... and its acyclic argument (the module) as it is
    dict(id="C5 the module is lost from a cyclic goal's culprit", file="src/pl-wam.jl",
         targets=["test/core_lang/test_metacall_control.jl"],
         old="                    push!(mc_args, export_cells(ld, mc_ex, mc_a))\n",
         new="                    push!(mc_args, mk_var(T, fresh_var_keys!(1)))\n"),
]
