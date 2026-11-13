# ORIGINAL: G1-GC G1-4's mutant list; the trail half of the collector is a port of pl-gc.c at the pin, the list itself is the kernel's own.
# tools/mutants/G1GC4.py — the mutation battery of G1-GC step G1-4, the TRAIL half of the stack collector: src/pl-gctrail.jl (the
# sentinel, tag_trail/untag_trail and the tagged word, compact_trail with its chain handler, the sweep entry list, is_dead_attvar,
# clean_attvar_chain). The early reset half (early_reset_vars, mergeTrailedAssignments) is G1-3's and is covered by G1GC3.
# NOTHING was run when this list was drafted: the kills below are read off the rows of test/core_lang/test_gc_trail.jl, the CI battery is
# the verdict. Run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC3.py): `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the testset of test/core_lang/test_gc_trail.jl (GT) that must fail, by the first words of its name:
#   RT = "tag_trail and untag_trail: the model's tagged words, and the identity round trip"
#   DE = "a deleted entry stays 0 through tag and untag; a local-stack address is a named refusal"
#   CT = "compact_trail removes exactly the deleted entries and keeps the order"
#   CH = "compact_trail hands every FIRST-marked entry to the chain handler with its destination"
#   NH = "compact_trail without a chain handler refuses a FIRST bit by name"
#   ER = "early reset, then tag, compact and untag: only the entries early reset zeroed disappear"
#   SW = "gc_trail_sweep_entries lists the entries sweep_trail chains, newest first"
#   AV = "is_dead_attvar and clean_attvar_chain drop exactly the dead links"
#   UM = "untag_trail marks the attvar cell of a trailed assignment whose saved value is an attvar"
#   CO = "deliberate corruptions FAIL the comparisons"
# TARGETS (audit D-0238): test/core_lang/test_gc_trail.jl is the only file that reaches pl-gctrail.jl (G1-5 and G1-6 call it later; a
#   file that drives the collector then adds itself here). `git grep` of the names in test/ finds no other.
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. A mutant that shortens a walk (G1GC4-C4)
#   may fail with an error (a kill) instead of a failed comparison.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC4` from the repository root;
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GT = "test/core_lang/test_gc_trail.jl"
TARGETS = [GT]
T = "src/pl-gctrail.jl"

def m(id, old, new, file=T, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=[GT])
    if eq:
        d["equivalent"] = eq
    return d

MUTANTS = [
    # ---- the sentinel and the state
    m("G1GC4-S1 gc_trail_begin!: the sentinel word is not 0 (KILL RT: `ld.trail[end] == 0`, the model with its sentinel)",
      "    push!(ld.trail, word(0))\n    ts = gc_trail_state()",
      "    push!(ld.trail, word(1))\n    ts = gc_trail_state()"),
    m("G1GC4-S2 gc_trail_end!: the sentinel is left on the trail (KILL RT: `ld.trail == orig`; ER: `length(ld.trail) == length(live)`)",
      "    pop!(ld.trail)\n    ts.top = 0",
      "    ts.top = 0"),
    # ---- the tagged word
    m("G1GC4-T1 gc_trail_tag_entry: a value entry loses its TAG_TRAILVAL bit (KILL RT: the model's `| 9`)",
      "return consPtr(trailValP(e), STG_GLOBAL | TAG_TRAILVAL)",
      "return consPtr(trailValP(e), STG_GLOBAL)"),
    m("G1GC4-T2 gc_trail_tag_entry: an address entry is tagged STG_LOCAL (KILL RT: the model's `| 8`; SW: global selection)",
      "return consPtr(_trail_pos(e), STG_GLOBAL)",
      "return consPtr(_trail_pos(e), STG_LOCAL)"),
    m("G1GC4-T3 gc_trail_tag_entry: a deleted entry is tagged like a live one (KILL DE: word 0 must stay 0)",
      "    e == 0 && return word(0)\n    if isTrailVal(e)",
      "    if isTrailVal(e)"),
    m("G1GC4-T4 gc_trail_tag_entry: the local-stack refusal never fires (KILL DE: `@test_throws LK.NotPortedError`)",
      "    if _trail_stack(e) != TRAIL_GLOBAL\n        throw(",
      "    if false\n        throw("),
    m("G1GC4-T5 gc_trail_untag_entry: a deleted entry is untagged like a live one (KILL DE: it throws on word 0)",
      "    w == 0 && return word(0)\n    p = valPtr(w)",
      "    p = valPtr(w)"),
    m("G1GC4-T6 gc_trail_untag_entry: a value entry comes back as an address entry (KILL RT: the round trip is the identity)",
      "        return tagTrailPtr(p)  ",
      "        return _trail_addr(p, TRAIL_GLOBAL)  "),
    m("G1GC4-T7 gc_trail_untag_entry: an address entry comes back as a value entry (KILL RT)",
      "    return _trail_addr(p, TRAIL_GLOBAL)\nend",
      "    return tagTrailPtr(p)\nend"),
    m("G1GC4-T8 gc_trail_tagged_pos: the position is off by one (KILL RT: `gc_trail_tagged_pos(ld.trail[tr0 + 1]) == c1`)",
      "gc_trail_tagged_pos(w::word)::Int = valPtr(w)",
      "gc_trail_tagged_pos(w::word)::Int = valPtr(w) + 1"),
    m("G1GC4-T9 gc_trail_tagged_isval: answers for address entries (KILL RT: the vector of value flags)",
      "(w & TAG_TRAILMASK) == TAG_TRAILVAL",
      "(w & TAG_TRAILMASK) == 0"),
    # ---- tag_trail / untag_trail
    m("G1GC4-U1 tag_trail: the newest entry is not tagged (KILL RT: the model's last word)",
      "    ts.values = 0\n    for i in (ts.top - 1):-1:1",
      "    ts.values = 0\n    for i in (ts.top - 2):-1:1"),
    m("G1GC4-U2 tag_trail: the value entries are counted twice (KILL RT: `ts.values == count(isTrailVal, orig)`)",
      "isTrailVal(e) && (ts.values += 1)",
      "isTrailVal(e) && (ts.values += 2)"),
    m("G1GC4-U3 untag_trail: the newest entry is not untagged (KILL RT: the round trip)",
      "    trail = ld.trail\n    for i in 1:(ts.top - 1)",
      "    trail = ld.trail\n    for i in 1:(ts.top - 2)"),
    m("G1GC4-U4 untag_trail: the trail stays flagged tagged (KILL RT: `!ts.tagged`)",
      "    ts.tagged = false\n    return nothing",
      "    ts.tagged = true\n    return nothing"),
    m("G1GC4-U5 untag_trail: the attvar cell of a kept assignment is not marked (KILL UM: `is_marked(gstack[A])`)",
      "ld.gstack[avp] = set_marked(ld.gstack[avp])",
      "ld.gstack[avp] = ld.gstack[avp]"),
    m("G1GC4-U6 untag_trail: marks the cell when it is STILL an attvar (KILL UM: B marked, A not)",
      "if !isAttVar(ld.gstack[avp])",
      "if isAttVar(ld.gstack[avp])"),
    m("G1GC4-U7 untag_trail: the address entry is read from the entry above (KILL UM: the mark lands on the wrong cell)",
      "avp = _trail_pos(trail[i - 1])",
      "avp = _trail_pos(trail[i + 1])"),
    m("G1GC4-U8 untag_trail: only a saved value that is NOT an attvar marks (KILL UM)",
      "                if isAttVar(old)",
      "                if !isAttVar(old)"),
    # ---- compact_trail
    m("G1GC4-C1 compact_trail: a deleted entry is kept (KILL CT: the trail equals the model of the non-zero entries)",
      "        if trail[current] != 0\n            trail[dest] = trail[current]",
      "        if true\n            trail[dest] = trail[current]"),
    m("G1GC4-C2 compact_trail: the kept counter is wrong (KILL CT: `ts.kept == length(keptmodel)`; ER)",
      "            ts.kept += 1",
      "            ts.kept += 2"),
    m("G1GC4-C3 compact_trail: the deleted counter is not counted (KILL CT: `ts.zeroed == nzero`; ER)",
      "            ts.zeroed += 1",
      "            ts.zeroed += 0"),
    m("G1GC4-C4 compact_trail: the loop stops one entry early (KILL CT, CH: the last entry is the sentinel's copy)",
      "    current = 1\n    while current < ts.top",
      "    current = 1\n    while current < ts.top - 1"),
    m("G1GC4-C5 compact_trail: an entry heading a relocation chain is not handed to the handler (KILL CH: `seen == expected`; NH)",
      "            urc(ld, current, dest)\n            ts.chains += 1\n        end\n        if trail[current] != 0",
      "            ts.chains += 1\n        end\n        if trail[current] != 0"),
    m("G1GC4-C6 compact_trail: the handler gets the arguments swapped (KILL CH, CO: the destination is the second argument)",
      "            urc(ld, current, dest)\n            ts.chains += 1\n        end\n        if trail[current] != 0",
      "            urc(ld, dest, current)\n            ts.chains += 1\n        end\n        if trail[current] != 0"),
    m("G1GC4-C7 compact_trail: the sentinel's chain is not unwound (KILL CH: the third record of `expected`)",
      "        urc(ld, current, dest)\n        ts.chains += 1\n    end\n    trail[dest] = trail[current]",
      "        ts.chains += 1\n    end\n    trail[dest] = trail[current]"),
    m("G1GC4-C8 compact_trail: the trail keeps one word too many (KILL CT: `length(ld.trail) == ts.top`; ER)",
      "    resize!(trail, dest)",
      "    resize!(trail, dest + 1)"),
    m("G1GC4-C9 compact_trail: the new top is one too high (KILL CT: `top == length(keptmodel) + 1`; CH: `top == dest`)",
      "    ts.top = dest",
      "    ts.top = dest + 1"),
    m("G1GC4-C10 gc_trail_no_chain: the default handler swallows the chain (KILL NH: `@test_throws LK.NotPortedError`)",
      "    throw(NotPortedError(ld.placeholder, \"update_relocation_chain of a trail entry (pl-gc.c:2647)\", \"G1-5\"))",
      "    return nothing"),
    # ---- the sweep entry list
    m("G1GC4-W1 gc_trail_sweep_entries: only value entries are listed (KILL SW: the address entries of the model)",
      "if gc_trail_tagged_isval(w) || (w & STG_MASK) == STG_GLOBAL",
      "if gc_trail_tagged_isval(w)"),
    m("G1GC4-W2 gc_trail_sweep_entries: a local-stack word is listed too (KILL SW: `!(tr0 + 5 in got)`)",
      "if gc_trail_tagged_isval(w) || (w & STG_MASK) == STG_GLOBAL",
      "if gc_trail_tagged_isval(w) || true"),
    m("G1GC4-W3 gc_trail_sweep_entries: oldest first (KILL SW: `got == model`, `issorted(got; rev = true)`)",
      "    out = Int[]\n    for i in (ts.top - 1):-1:1",
      "    out = Int[]\n    for i in 1:(ts.top - 1)"),
    # ---- the attvar chain
    m("G1GC4-A1 is_dead_attvar: the mark is not cleared (KILL AV: `MARK_MASK == 0` after the call)",
      "        ld.gstack[p] = clear_marked(w) ",
      "        ld.gstack[p] = w "),
    m("G1GC4-A2 is_dead_attvar: a marked cell is dead (KILL AV: `!is_dead_attvar(links[4])`)",
      "        return false\n    end\n    isAttVar(w) && return false",
      "        return true\n    end\n    isAttVar(w) && return false"),
    m("G1GC4-A3 is_dead_attvar: an attvar word is dead (KILL AV: `!is_dead_attvar(links[1])`)",
      "    isAttVar(w) && return false\n    return true",
      "    return true"),
    m("G1GC4-A4 clean_attvar_chain: a removed link does not unlink the chain behind it (KILL AV: `_gt_chain == survivors`)",
      "ld.gstack[last] = ld.gstack[p] ",
      "ld.gstack[last] = ld.gstack[last] "),
    m("G1GC4-A5 clean_attvar_chain: the head of the chain does not move on when the newest link is dead (KILL AV: `attvar_attvars == links[3]`)",
      "ld.attvar_attvars = nxt ",
      "ld.attvar_attvars = ld.attvar_attvars "),
    m("G1GC4-A6 clean_attvar_chain: the removed count is wrong (KILL AV: `removed == 1`)",
      "            removed += 1",
      "            removed += 2"),
    m("G1GC4-A7 clean_attvar_chain: a kept link does not become `last` (KILL AV: the link behind a kept one is dropped from the head)",
      "            last = p\n",
      "            last = 0\n"),
    m("G1GC4-A8 clean_attvar_chain: the walk stops after one link (KILL AV: `removed == 1` and the survivors)",
      "nxt = isRef(ld.gstack[p]) ? unRef(ld.gstack[p]) : 0",
      "nxt = 0"),
]
