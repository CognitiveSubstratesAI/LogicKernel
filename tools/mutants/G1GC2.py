# ORIGINAL: G1-GC piece G1-2's mutant list — no swipl-devel counterpart.
# tools/mutants/G1GC2.py — the mutation battery of G1-2, the safe-point audit of the stack garbage collector (docs/g1gc_safe_points.md): the hook
# `considerGC` (src/pl-gc.jl), `ensureGlobalSpace(ld, n, flags, site)` (src/pl-alloc.jl) and the 18 sites that pass ALLOW_GC (src/pl-attvar.jl,
# pl-prims.jl, pl-list.jl, pl-gvar.jl, pl-bag.jl, pl-copyterm.jl, pl-cont.jl, pl-dict.jl, pl-rec.jl, pl-fli.jl). NOT RUN when it was written (edit-only
# step, nothing compiled): the "KILL" text of each id is the assertion EXPECTED to fail, named by testset; the CI battery decides
# (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as TRIE2.py): `id`, `file`, `old` (EXACTLY once), `new`, optional `equivalent`, `targets`.
# Test files:
#   GS = test/core_lang/test_g1gc_safe_points.jl: T = the table-vs-code testset, H = the hook by hand, R = the rows (flag off, flag on, hits, heap),
#   K = the kill rows. The other files below run the mutated builtins on their own (a mutant that changes an answer fails there too).
# TARGETS (audit D-0238): GS for every mutant, and every test file found that exercises the mutated code: the stack-limit tests for the hook (every
#   ensureGlobalSpace call), the attvar tests for the pl-attvar.jl sites, the gvar, findall/bagof, copy_term, dict, record and continuation tests for theirs.
#   `length/2`, `functor/3`, `=../2` and `compound_name_*` have no test file of their own found by name (test_univ_cells.jl reads the cells of =..): the
#   rows of GS are their only target here, which the dispatcher may widen.
# A SITE MUTANT (G1GC2-S*) drops ALLOW_GC at one site: killed by the row of that site (R: `site in on_hits[i]` of `_G_REQ`), and by T when the site is the
#   only line that names it. A site that other rows also record (copyRecordToGlobal: seven call sites, six rows) is killed by the row that reaches THAT call
#   site only: g15 (bag), g16 (recorded/2, bound key), g21 (recorded/3, bound reference), g22 (instance/2), g23 (PL_recorded, through a trie).
# EQUIVALENT until G1-6 (the collector): the re-check after a collection (the placeholder `garbageCollect` never returns BOOLEX_TRUE), and the redundant
#   flag test in ensureGlobalSpace (considerGC tests the flag itself).
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC2`; no Julia ran.
#   RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GS = "test/core_lang/test_g1gc_safe_points.jl"
STK = [
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
    "test/core_lang/test_resource_error.jl",
    "test/core_lang/test_local_stack.jl",
    "test/core_lang/test_lb7_swipl.jl",
]
ATT = [
    "test/core_lang/test_attvar_store.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_trie_attvar_swipl.jl",
]
GV = "test/core_lang/test_gvar_swipl.jl"
FA = ["test/core_lang/test_findall_swipl.jl", "test/core_lang/test_bagof_swipl.jl"]
CT = ["test/core_lang/test_copyterm_cells.jl", "test/core_lang/test_copyterm_swipl.jl"]
DC = "test/core_lang/test_dict_preds_swipl.jl"
RC = "test/db/test_record_swipl.jl"
CN = ["test/core_lang/test_cont_run_swipl.jl", "test/core_lang/test_cont_boot_swipl.jl"]
UN = "test/core_lang/test_univ_cells.jl"
HOOK = [GS] + STK + [GV] + FA + CT + [DC, RC] + CN + ATT
TARGETS = HOOK + [UN]                            # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)


def m(id, old, new, targets, file, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


GC = "src/pl-gc.jl"
AL = "src/pl-alloc.jl"


def site(id, file, name, targets, kill):
    """Drop ALLOW_GC at the site `name` (its argument list `..., ALLOW_GC, :name)` becomes `..., 0, :name)`)."""
    return m(
        "G1GC2-%s %s passes no ALLOW_GC (KILL %s)" % (id, name, kill),
        "ALLOW_GC, :%s)" % name, "0, :%s)" % name, targets, file,
    )


MUTANTS = [
    # ---- the hook
    m("G1GC2-H1 considerGC ignores the flags (KILL GS H: considerGC(ld, 0, ..) under gc_force records its site)",
      "    (flags & ALLOW_GC) == 0 && return false                 # G1-GC safe point: only a site that passed ALLOW_GC\n",
      "",
      HOOK, GC),
    m("G1GC2-H2 considerGC ignores gc_force (KILL GS H: forced, ALLOW_GC: nothing recorded; R: every row misses its site)",
      "    if ld.gc_force                                          # G1-GC safe point: FAKE_GC's model\n",
      "    if false                                                # G1-GC safe point: FAKE_GC's model\n",
      HOOK, GC),
    m("G1GC2-H3 the site is not recorded (KILL GS H: gc_safe_hits == [:probe_site]; R: every row misses its site)",
      "        push!(ld.gc_safe_hits, site)\n", "        nothing\n",
      HOOK, GC),
    m("G1GC2-H4 the site recorded is the wrong one (KILL GS H: gc_safe_hits == [:probe_site]; R: every row misses its site; K)",
      "        push!(ld.gc_safe_hits, site)\n", "        push!(ld.gc_safe_hits, :wrong_site)\n",
      HOOK, GC),
    m("G1GC2-H5 a collection that declined reads as one that ran (KILL GS H: `!considerGC(..)` while the collector is blocked; re-fitted at the G1-6c merge, the call now passes `Int(reason)`)",
      "return garbageCollect(ld, Int(reason)) == BOOLEX_TRUE",
      "return garbageCollect(ld, Int(reason)) != BOOLEX_TRUE",
      HOOK, GC),
    m("G1GC2-H6 the driver answers BOOLEX_TRUE for a blocked collector (KILL GS H: `garbageCollect(ld, GC_USER) == BOOLEX_FALSE` with `blocked = 1`; re-pointed at src/pl-gcdriver.jl at the G1-6c merge, the placeholder is gone)",
      "        return BOOLEX_FALSE\n    end\n    vm0 = gc_get_vmi_state",
      "        return BOOLEX_TRUE\n    end\n    vm0 = gc_get_vmi_state",
      HOOK, "src/pl-gcdriver.jl"),
    m("G1GC2-H7 the scheduler says a collection is due while no inference ran since the last one (KILL GS H: `!considerGarbageCollect(ld)`; re-pointed at G1-1's scheduler by the G1-GC merge: the G1-2 placeholder it first targeted is gone)",
      "pol.gced_size = used                        # (*)\n                    return false\n",
      "pol.gced_size = used                        # (*)\n                    return true\n",
      HOOK, GC),
    # ---- ensureGlobalSpace
    m("G1GC2-E1 ensureGlobalSpace: gc_force no longer reaches the hook (KILL GS H: forced + ALLOW_GC records [:probe_site]; R: every row)",
      "(ld.gc_force || ld.gTop + n > length(ld.gstack) || !fits)", "(ld.gTop + n > length(ld.gstack) || !fits)",
      HOOK, AL),
    m("G1GC2-E2 ensureGlobalSpace: the flag test is inverted (KILL GS H: forced + ALLOW_GC records nothing, flags 0 reaches the hook which declines)",
      "if (flags & ALLOW_GC) != 0 && (ld.gc_force", "if (flags & ALLOW_GC) == 0 && (ld.gc_force",
      HOOK, AL),
    m("G1GC2-E3 ensureGlobalSpace: the default flags are ALLOW_GC (KILL GS H: `ensureGlobalSpace(ld, 4)` under gc_force records; R: g20, a site outside the table records)",
      "flags::Int=0, site::Symbol=:ensureGlobalSpace", "flags::Int=1, site::Symbol=:ensureGlobalSpace",
      HOOK, AL),
    m("G1GC2-E4 ensureGlobalSpace: the flag test is dropped (considerGC tests the flag itself; output equivalent)",
      "if (flags & ALLOW_GC) != 0 && (ld.gc_force", "if (ld.gc_force",
      HOOK, AL,
      eq="src/pl-alloc.jl:ensureGlobalSpace: `considerGC` (src/pl-gc.jl) opens with `(flags & ALLOW_GC) == 0 && return false`, so a call without ALLOW_GC reaches it and leaves it with false, records nothing, and `fits` is not re-read (the re-check runs only after a collection that ran). The hook is called more often, with no effect; killing it needs a test that counts calls of considerGC, which the one-line flag test of H1 already guards"),
    m("G1GC2-E5 ensureGlobalSpace: the re-check after a collection is dropped (the placeholder never collects; equivalent until G1-6)",
      "        if considerGC(ld, flags, GC_GLOBAL_OVERFLOW, site)   # G1-GC safe point: garbageCollect(GC_GLOBAL_OVERFLOW)\n",
      "        if false   # G1-GC safe point: garbageCollect(GC_GLOBAL_OVERFLOW)\n",
      HOOK, AL,
      eq="src/pl-gc.jl:garbageCollect answers BOOLEX_FALSE, so considerGC never returns true and the body of the `if` (the re-read of `fits`) never runs. DEFERRED KILL: G1-6 fills garbageCollect; its test (a collection that gains room lets a call through the limit) kills this mutant, and the declaration goes then"),
    # ---- a NEEDS-ROOT site made a safe point
    m("G1GC2-N1 bind_attvar_const passes ALLOW_GC (NEEDS-ROOT: it holds p and c across the call; KILL GS R: g20 records a site outside the table)",
      "ensureGlobalSpace(ld, 0) || return false                # if ( !hasGlobalSpace(0) )",
      "ensureGlobalSpace(ld, 0, ALLOW_GC, :bind_attvar_const) || return false                # if ( !hasGlobalSpace(0) )",
      [GS] + ATT, "src/pl-attvar.jl"),
    # ---- each SAFE site loses its ALLOW_GC
    site("S1", "src/pl-attvar.jl", "put_attr3", [GS] + ATT, "GS R g1, g3, g4, g5"),
    site("S2", "src/pl-attvar.jl", "put_attrs2", [GS] + ATT, "GS R g2"),
    site("S3", "src/pl-attvar.jl", "del_attr2", [GS] + ATT, "GS R g3"),
    site("S4", "src/pl-attvar.jl", "del_attrs1", [GS] + ATT, "GS R g4"),
    site("S5", "src/pl-attvar.jl", "attv_unify2", [GS] + ATT, "GS R g5"),
    site("S6", "src/pl-attvar.jl", "dfreeze2", [GS] + ATT, "GS R g6"),
    site("S7", "src/pl-attvar.jl", "dsuspend3", [GS] + ATT, "GS R g7"),
    site("S8", "src/pl-prims.jl", "functor3", [GS, UN], "GS R g8"),
    site("S9", "src/pl-prims.jl", "compound_name_arity3", [GS, UN], "GS R g9"),
    site("S10", "src/pl-prims.jl", "univ2", [GS, UN], "GS R g10"),
    site("S11", "src/pl-prims.jl", "compound_name_arguments3", [GS, UN], "GS R g11"),
    site("S12", "src/pl-list.jl", "length2", [GS], "GS R g12"),
    site("S13", "src/pl-gvar.jl", "setval", [GS, GV], "GS R g13, g14"),
    site("S14", "src/pl-bag.jl", "collect_findall_bag", [GS] + FA, "GS R g15"),
    site("S15", "src/pl-copyterm.jl", "copy_term_refs", [GS] + CT, "GS R g17"),
    site("S16", "src/pl-cont.jl", "put_environment", [GS] + CN, "GS R g19"),
    site("S17", "src/pl-dict.jl", "get_dict_ex", [GS, DC], "GS R g18"),
    # the call sites of copyRecordToGlobal, one mutant each
    m("G1GC2-S18 the findall bag's copy of an answer passes no ALLOW_GC (KILL GS R g15: the row's :copyRecordToGlobal)",
      "copyRecordToGlobal(ld, answer, r, ALLOW_GC)", "copyRecordToGlobal(ld, answer, r, 0)",
      [GS] + FA, "src/pl-bag.jl"),
    m("G1GC2-S19 recorded/2's copy passes no ALLOW_GC (KILL GS R g16)",
      "if !copyRecordToGlobal(ld, copy, rec.record::record{T}, ALLOW_GC)", "if !copyRecordToGlobal(ld, copy, rec.record::record{T}, 0)",
      [GS, RC], "src/pl-rec.jl"),
    m("G1GC2-S20 recorded/3's copy of a bound reference passes no ALLOW_GC (KILL GS R g21)",
      "copyRecordToGlobal(ld, copy, rec.record::record{T}, ALLOW_GC) &&", "copyRecordToGlobal(ld, copy, rec.record::record{T}, 0) &&",
      [GS, RC], "src/pl-rec.jl"),
    m("G1GC2-S21 instance/2's copy of a record passes no ALLOW_GC (KILL GS R g22)",
      "copyRecordToGlobal(ld, t, rref.record::record{T}, ALLOW_GC)", "copyRecordToGlobal(ld, t, rref.record::record{T}, 0)",
      [GS, RC], "src/pl-rec.jl"),
    m("G1GC2-S22 PL_recorded passes no ALLOW_GC (KILL GS R g23: a trie value is read by PL_recorded)",
      "copyRecordToGlobal(ld, t, r, ALLOW_GC)", "copyRecordToGlobal(ld, t, r, 0)",
      [GS, "test/core_lang/test_trie_attvar_swipl.jl", RC], "src/pl-fli.jl"),
    m("G1GC2-S23 copyRecordToGlobal drops its flags (the hook is never reached from a record; KILL GS R g15, g16, g21, g22, g23)",
      "ensureGlobalSpace(ld, r.gsize, flags, :copyRecordToGlobal)", "ensureGlobalSpace(ld, r.gsize, 0, :copyRecordToGlobal)",
      [GS, RC] + FA, "src/pl-rec.jl"),
    m("G1GC2-S24 copyRecordToGlobal records the wrong site (KILL GS R g15, g16, g21, g22, g23; T: the table names copyRecordToGlobal)",
      "ensureGlobalSpace(ld, r.gsize, flags, :copyRecordToGlobal)", "ensureGlobalSpace(ld, r.gsize, flags, :copyRecordToGlobal2)",
      [GS, RC] + FA, "src/pl-rec.jl"),
]
