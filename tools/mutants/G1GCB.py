# ORIGINAL: G1-GC G1-B's mutant list (the foreign safe-point roots: bind_attvar_const, setarg); the list itself is the kernel's own.
# tools/mutants/G1GCB.py — the mutation battery of G1-GC step G1-B: the PushPtr!/PopPtr!/PushVal!/PopVal! twins (src/pl-fli.jl), the rooting and the
# flags of bind_attvar_const (src/pl-attvar.jl) and its callers PL_unify_functor / PL_unify_compound (src/pl-fli.jl) and functor/3,
# compound_name_arity/3 (src/pl-prims.jl), and setarg's re-derived position and its ALLOW_GC (src/pl-prims.jl). NOTHING was run when this list was
# drafted: the kills are read off the rows of test/core_lang/test_g1gc_safe_points.jl, the CI battery is the verdict. Run ONCE, in CI
# (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC6C.py): `id`, `file`, `old` (must occur EXACTLY once), `new`.
# Each id names its KILL by the first words of the testset of test_g1gc_safe_points.jl:
#   PP = "G1-B: PushPtr!/PushVal! root a position and a word over garbageCollect; the unrooted garbage is freed"
#   BA = "G1-B: bind_attvar_const with and without ALLOW_GC binds the same way"
#   SR = "G1-GC: every SAFE site is reached by its row" (rows g24, g25, g26: the required sites are recorded under gc_force, answers equal swipl's)
#   KR = "G1-GC kill rows" (the g24/g25/g26 answers and sites)
# TARGETS (audit D-0238): bind_attvar_const is exercised by test_attvar_words.jl and test_attvar_wakeup.jl, setarg by test_setarg_swipl.jl, the
# callers by test_compound_cells.jl and test_univ_cells.jl, all through the safe-point rows.
# NOT COVERED by a kill read off the rows (a lane may add): whether a collection MOVES `apos` in g26 (the heap below the compound is garbage
#   only when an earlier goal left some), so G1GCB-S1 may survive on the answer alone; it is then killed by the missing site only if it removes the flag.
# G1-B2 (the dict retry loops, src/pl-dict.jl; kills read off the rows g27-g30, NOTHING run):
#   put_dict/3 -> g27 (:put_dict3), select_dict/3 -> g28 (:select_dict3), del_dict/4 -> g29 (:del_dict4), dict_same_keys/2 -> g30 (:copy_keys_dict):
#   SR = the row records its site under gc_force (the first pass reported the overflow, the safe point ran) and the answer equals swipl's;
#   KR = the answer and `count(==(site), hits) == 1` (one safe point per call: the retry's second pass does not report again).
#   Mutants that drop the retry (`continue` -> return) make the call fail: KILL SR/KR on the answer. `Undo!` and `DiscardMark` have no mutant:
#   no helper binds or allocates before it reports, so dropping them changes neither an answer nor a heap size (EQUIVALENT: src/pl-dict.jl
#   put_dict/del_dict/copy_keys_dict report at the top; select_dict's earlier bindings are re-made equal by the retry).
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GCB` from the repository root.
SP = "test/core_lang/test_g1gc_safe_points.jl"
TARGETS = [
    SP,
    "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_setarg_swipl.jl",
    "test/core_lang/test_compound_cells.jl",
    "test/core_lang/test_univ_cells.jl",
]
TARGETS = TARGETS + [
    "test/core_lang/test_dict_preds_swipl.jl",
    "test/core_lang/test_read_dict_swipl.jl",
    "test/core_lang/test_bootpred_swipl.jl",
]
DCT = "src/pl-dict.jl"
FLI = "src/pl-fli.jl"
ATT = "src/pl-attvar.jl"
PRM = "src/pl-prims.jl"

def m(id, file, old, new):
    return dict(id=id, file=file, old=old, new=new, targets=TARGETS)

MUTANTS = [
    m("G1GCB-P1 PushPtr!: the position is not rooted (KILL PP: `p2 < p && gstack[p2] == consInt(7)` after the collection)",
      FLI,
      "ld.slots[ld.tmp_h + i + 1] = makeRefG(p)        # *valTermRef(LD->tmp.h[i]) = makeRefLG(p)",
      "ld.slots[ld.tmp_h + i + 1] = word(0)            # *valTermRef(LD->tmp.h[i]) = makeRefLG(p)"),
    m("G1GCB-P2 PopPtr!: the position is read from the wrong handle (KILL PP: the popped position names the cell)",
      FLI,
      "p = unRef(ld.slots[ld.tmp_h + ld.tmp_top])      # p = unRef(*valTermRef(LD->tmp.h[i]))",
      "p = unRef(ld.slots[ld.tmp_h + ld.tmp_top + 1])  # p = unRef(*valTermRef(LD->tmp.h[i]))"),
    m("G1GCB-V1 PushVal!: the word is not rooted (KILL PP: `valPtr(c2) < a` and the compound's functor at its new place)",
      FLI,
      "_slot_link_loc!(ld, ld.tmp_h + i + 1, (_is_vword(w) ? DU_VALUE : DU_WORD, w, 0))   # *valTermRef(LD->tmp.h[i]) = w",
      "_slot_link_loc!(ld, ld.tmp_h + i + 1, (DU_WORD, word(0), 0))   # *valTermRef(LD->tmp.h[i]) = w"),
    m("G1GCB-V2 PopVal!: the word is not read back (KILL PP: `PopVal!(ld) == consInt(5)` and the compound word)",
      FLI,
      "w = ld.slots[ld.tmp_h + ld.tmp_top]             # w = *valTermRef(LD->tmp.h[i])",
      "w = word(0)                                     # w = *valTermRef(LD->tmp.h[i])"),
    m("G1GCB-A1 bind_attvar_const: no collection even with ALLOW_GC (KILL BA, SR g24: the site is not recorded)",
      ATT,
      "    if (flags & ALLOW_GC) != 0\n        PushPtr!(ld, p) ",
      "    if false\n        PushPtr!(ld, p) "),
    m("G1GCB-A2 bind_attvar_const: `p` is not pushed (KILL BA: a pop with an empty or short stack asserts, `tmp_top == 0` after)",
      ATT,
      "        PushPtr!(ld, p)                                     # PushPtr(p)\n",
      ""),
    m("G1GCB-A3 bind_attvar_const: `c` is not pushed (KILL BA: as A2)",
      ATT,
      "        PushVal!(ld, c)                                     # PushVal(c)\n",
      ""),
    m("G1GCB-A4 bind_attvar_const: the site name is not the table's (KILL SR: `required == table`, the g24 row's site missing)",
      ATT,
      "rc = ensureGlobalSpace(ld, 0, ALLOW_GC, :bind_attvar_const)",
      "rc = ensureGlobalSpace(ld, 0, ALLOW_GC, :bind_attvar_x)"),
    m("G1GCB-B1 bindConst: `flags` is not forwarded to bind_attvar_const (KILL SR, KR: g24 and g25 record no :bind_attvar_const)",
      ATT,
      "bind_attvar_const(ld, p, c, flags)          # else return bind_attvar_const(p, c);",
      "bind_attvar_const(ld, p, c, 0)              # else return bind_attvar_const(p, c);"),
    m("G1GCB-U1 PL_unify_functor: `flags` is not forwarded (KILL SR g24)",
      FLI,
      "            bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), flags)   # bindConst(p, to)",
      "            bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), 0)   # bindConst(p, to)"),
    m("G1GCB-U2 PL_unify_compound: `flags` is not forwarded (KILL SR g25)",
      FLI,
      "\n        bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), flags)   # bindConst(p, to)",
      "\n        bindConst(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL), 0)   # bindConst(p, to)"),
    m("G1GCB-F1 functor/3: no ALLOW_GC for the binding (KILL SR, KR: g24 has no :bind_attvar_const hit)",
      PRM,
      "PL_unify_functor(ld, A1, name, arity, ALLOW_GC)",
      "PL_unify_functor(ld, A1, name, arity, 0)"),
    m("G1GCB-F2 compound_name_arity/3: no ALLOW_GC for the binding (KILL SR, KR: g25)",
      PRM,
      "PL_unify_compound(ld, A1, f, ALLOW_GC)",
      "PL_unify_compound(ld, A1, f, 0)"),
    m("G1GCB-S1 setarg: `apos` is not re-derived after the call (KILL SR g26 when the collection moves the compound; the answer then differs)",
      PRM,
      "        apos = valPtr(w) + argn                             # a = argTermP(*a, argn-1)\n        TrailAssignment!(ld, apos)",
      "        TrailAssignment!(ld, apos)"),
    m("G1GCB-S2 setarg: the check passes no ALLOW_GC (KILL SR, KR: g26 records no :setarg)",
      PRM,
      "ensureGlobalSpace(ld, 1, ALLOW_GC, :setarg)",
      "ensureGlobalSpace(ld, 1, 0, :setarg)"),
    m("G1GCB-S3 setarg: the re-derivation reads the wrong term (KILL SR g26: the answer or a type error)",
      PRM,
      "_, w, _ = _deref_loc(ld, -(term + 1))               # a = valTermRef(term); deRef(a): re-derived",
      "_, w, _ = _deref_loc(ld, -(value + 1))              # a = valTermRef(term); deRef(a): re-derived"),
    # ---- G1-B2: the dict retry loops
    m("G1GCB-D1 _dict_overflow never reports (KILL SR g27-g30: no site recorded, no retry)",
      DCT,
      "    gc || return false\n    fits = _stacks_in_use(ld, n)",
      "    return false\n    fits = _stacks_in_use(ld, n)"),
    m("G1GCB-D2 put_dict reports no overflow (KILL SR g27: no :put_dict3)",
      DCT,
      "_dict_overflow(ld, 1 + arity + 2 * npairs, gc) &&\n        return DictOverflow(1 + arity + 2 * npairs)",
      "false &&\n        return DictOverflow(1 + arity + 2 * npairs)"),
    m("G1GCB-D3 put_dict/3 retries without ALLOW_GC (KILL SR g27: no :put_dict3)",
      DCT,
      "ensureGlobalSpace(ld, new.n, ALLOW_GC, :put_dict3)",
      "ensureGlobalSpace(ld, new.n, 0, :put_dict3)"),
    m("G1GCB-D5 select_dict reports no overflow (KILL SR g28: no :select_dict3)",
      DCT,
      "_dict_overflow(ld, nsize * 2 + 2, gc) && return DictOverflow(nsize * 2 + 2)",
      "false && return DictOverflow(nsize * 2 + 2)"),
    m("G1GCB-D6 select_dict/3 retries without ALLOW_GC (KILL SR g28)",
      DCT,
      "ensureGlobalSpace(ld, r.n, ALLOW_GC, :select_dict3)",
      "ensureGlobalSpace(ld, r.n, 0, :select_dict3)"),
    m("G1GCB-D8 del_dict reports no overflow (KILL SR g29: no :del_dict4)",
      DCT,
      "_dict_overflow(ld, 1 + arity - 2, gc) && return DictOverflow(1 + arity - 2)",
      "false && return DictOverflow(1 + arity - 2)"),
    m("G1GCB-D9 del_dict/4 retries without ALLOW_GC (KILL SR g29)",
      DCT,
      "ensureGlobalSpace(ld, new.n, ALLOW_GC, :del_dict4)",
      "ensureGlobalSpace(ld, new.n, 0, :del_dict4)"),
    m("G1GCB-D11 copy_keys_dict reports no overflow (KILL SR g30: no :copy_keys_dict)",
      DCT,
      "_dict_overflow(ld, 1 + arity, gc) && return DictOverflow(1 + arity)",
      "false && return DictOverflow(1 + arity)"),
    m("G1GCB-D12 unify_dict_copy retries without ALLOW_GC (KILL SR g30)",
      DCT,
      "ensureGlobalSpace(ld, copy.n, ALLOW_GC, :copy_keys_dict)",
      "ensureGlobalSpace(ld, copy.n, 0, :copy_keys_dict)"),
    m("G1GCB-D14 unify_dict_copy keeps the stale dict word (KILL SR g30 when the collection moves the dict: the keys differ)",
      DCT,
      "_, dict, _ = _deref_loc(ld, -(dt + 1))  # p = valTermRef(dt); deRef(p); dict = *p\n",
      "# (dict not reloaded)\n"),
    m("G1GCB-D1b _dict_overflow also reports on the retry (gc ignored): the call never ends, the driver's timeout kills it",
      DCT,
      "    gc || return false\n    fits = _stacks_in_use(ld, n)",
      "    fits = _stacks_in_use(ld, n)"),
    m("G1GCB-D4 put_dict/3 does not retry (KILL SR, KR g27: the call fails)",
      DCT,
      "                gc = false\n                continue                            # goto retry",
      "                gc = false\n                return FFALSE                       # goto retry"),
    m("G1GCB-D7 select_dict/3 does not retry (KILL SR, KR g28: the call fails)",
      DCT,
      "            gc = false\n            continue                                # goto retry",
      "            gc = false\n            return FFALSE                           # goto retry"),
    m("G1GCB-D10 del_dict/4 does not retry (KILL SR, KR g29: the call fails)",
      DCT,
      "                    gc = false\n                    continue                        # goto retry",
      "                    gc = false\n                    return FFALSE                   # goto retry"),
    m("G1GCB-D13 unify_dict_copy does not retry (KILL SR, KR g30: the call fails)",
      DCT,
      "            gc = false\n            _, dict, _ = _deref_loc(ld, -(dt + 1))  # p = valTermRef(dt); deRef(p); dict = *p\n            continue",
      "            gc = false\n            _, dict, _ = _deref_loc(ld, -(dt + 1))  # p = valTermRef(dt); deRef(p); dict = *p\n            return false"),
]
