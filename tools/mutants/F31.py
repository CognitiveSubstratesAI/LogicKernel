# ORIGINAL: f3-1's mutant list — no swipl-devel counterpart.
# tools/mutants/F31.py — the mutation battery of f3-1 (audit D-0110 option (b); D-0107 item 3: the new invariants
# only): a slot's grounded side value is read as a value (its read-only SIDE WORD, DU_VALUE), never the boundary.
# Run once, in CI, alongside the gate's CI + Evidence (D-0105 item 2). Format: tools/mutate_drive.py's. The suite-wide
# guard (test/runtests.jl, `_DU_TERM_SIDE`) is proven separately, at verdict level (lk-channel evidence/f3/guard_proof.txt).
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/core_lang/test_slot_indirects.jl",
]
MUTANTS = [
    # _deref_loc: a GROUND side entry is a value (its side word), not the boundary
    dict(id="F1 a grounded side value is handed out as the boundary again", file="src/pl-prims.jl",
         targets=["test/core_lang/test_slot_indirects.jl"],
         old="                kind(ld.slot_values[-loc]) === GND && return (DU_VALUE, _side_word(-loc), 0)\n",
         new=""),
    # _value_word!: a writer stores the value's own word, never the read-only side word (which names the slot's entry)
    dict(id="F2 a cell is bound to the read-only side word", file="src/pl-inline.jl",
         targets=["test/core_lang/test_slot_indirects.jl"],
         old="    _is_side_word(w) ? _side_value_word!(ld, w) : w\n",
         new="    w\n"),
    # _indirect_value: a side word's value is the slot's own side entry
    dict(id="F3 a side word is read as a value-table word", file="src/pl-inline.jl",
         targets=["test/core_lang/test_slot_indirects.jl"],
         old="    _is_side_word(w) && return ld.slot_values[valPtr(w)]\n",
         new=""),
]
