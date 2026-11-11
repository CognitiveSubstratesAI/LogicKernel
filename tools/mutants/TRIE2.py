# ORIGINAL: TR2's mutant list — no swipl-devel counterpart.
# tools/mutants/TRIE2.py — the mutation battery of TR2, the enumeration of pl-trie.c ported into src/pl-trie.jl: the pruning cursor through
# the query (qcursor, qframe: skip_query!, enter_query_compound!, pop_query_frame!, concrete_ahead, peek_query, align_pruning_key!),
# the choice stack and its branches (push_choice!, pop_choice!, add_branch!, add_choice!, advance_node!, descent_node!, restore_cursor!,
# next_choice0!, next_choice!), the answer (unify_trie_path!, trie_gen_raw, trie_gen), and the four predicates TR2 registers: trie_gen/2,3,
# `$trie_gen_node`/3 and `$trie_property`/2. The list pins what is there at the gate of TR2. NOT RUN when it was written (edit-only step,
# nothing compiled): the "KILL" text of each id is the assertion that is EXPECTED to fail, named by test row; the CI battery decides
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE1.py, PIN1.py): `id`, `file`, `old`
# (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Test files:
#   TG = test/core_lang/test_trie_gen_swipl.jl: D = the differential testset (every row t0-t29 against the .out), K = the kill-row testset
#   (single rows `kl["tN"]`), R = the replay testset (every row again with ld.trie_gen_force_epoch), L = the testset that reads
#   `ld.trie_gens.live == 0` after each row. TW = test/core_lang/test_trie_swipl.jl and TP = test/core_lang/test_trie_preds_swipl.jl (TR1's
#   rows on the same trie code: the arena a delete leaves is read by the enumeration), TB = test/db/test_boot_image_swipl.jl (counts the
#   foreign rows of the kernel: a dropped registration).
# TARGETS (audit D-0238): every test file that runs the mutated code: TG, TW and TP for every mutant of the enumeration (TG calls the
#   predicates on the booted database; TW and TP run the trie they walk); the registration mutants also TB. `TARGETS` is the union
#   (mutate_ci.py plan reads it).
# THE PRUNING IS ONLY A FILTER (pl-trie.c, `unify_trie_path!` decides every answer, src/pl-trie.jl: the function of that name): a mutant that
#   prunes LESS (a cut that does not cut, a stop that stops earlier, `last` or `rest` computed wrongly towards "keep going") changes no
#   answer, only the work done. Those mutants are declared EQUIVALENT below with the reason; the killable ones are those that prune MORE
#   (a cursor that points at the wrong argument, a key compared wrongly) or break the choice stack, the state record or the answer unification.
# DEFERRED KILL (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet — no test file reads what
#   the mutant changes (a finding for a test step, not invented here). It must SURVIVE the battery; when a test step adds the row, the declaration goes.
#   * TR2-K1 (a stored variable key against a constant query, in a block without the scan bit) and TR2-K2 (the equal constant first, then the
#     variables): rows t5 and t28 query with variables only, t13 reaches the scan path; a row `trie_insert(T, f(X, Y), 1), trie_insert(T, f(a, b), 2),
#     trie_gen(T, f(a, b))` (swipl answers both) kills both.
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): TR2-Q1 .. TR2-Q8.
# Every `old` was counted EXACTLY once in its file by a python3 -I script (exec of this file, `src/pl-trie.jl`.count(old) == 1 for each of the 53
#   mutants; no Julia ran) at the commit that adds this list; `new` != `old`; no duplicate id.
#   RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TG = "test/core_lang/test_trie_gen_swipl.jl"
TW = "test/core_lang/test_trie_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TA = "test/core_lang/test_trie_attvar_swipl.jl"   # TAB1 stack: its g rows are upstream's trie_attvars tests run through trie_gen/2
TARGETS = [TG, TW, TP, TB, TA]                   # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-trie.jl"
TT = [TG, TW, TP, TA]
TR = [TG, TB]


def m(id, old, new, targets=TT, file=F, eq=None, hang=False):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    if hang:
        d["expect"] = "hang"            # a loop inside ONE call that no row can bound: "caught (hang)" past LIMIT_S
    return d


MUTANTS = [
    # ---- the pruning cursor: a mutant that prunes MORE (D: the .out rows; K: single rows)
    m("TR2-C1 skip_query! does not step the position (KILL D t29: after the first argument 1 matched, the cursor reads it again for the stored 5)",
      "    c.term = c.size != 0 ? c.term + 1 : 0\n", "    c.term = c.size != 0 ? c.term : 0\n"),
    m("TR2-C2 skip_query! does not count the argument (output equivalent)",
      "    c.size -= 1\n    c.term = c.size != 0", "    c.size -= 0\n    c.term = c.size != 0",
      eq="src/pl-trie.jl:2304-2308 skip_query!: `size` feeds only the stop of the cursor. With `size` not reaching 0 the cursor reads a stale cell: concrete_ahead (:2353-2355) then needs `term <= last` or a frame with a rest, and peek_query at a stale cell differs from `Q_DONE` only where it gives a stop (peek_query :2367-2385, align_pruning_key! :2392-2457: the `@goto stop` branches set `prune = false`). The cursor prunes less, never more, and unify_trie_path! decides every answer (TR2-Q2). Probes: the whole TG file (D 49, K 14, R 40, L 39, white box 11) is green with the mutant; the 300-row fuzz at epochs 0 and 1 gives the unmutated output"),
    m("TR2-C3 a frame resumes at the argument just entered (KILL D t6: f(g(_), 2) reads g(_) again for the stored 2 and cuts f(g(1), 2))",
      "push!(st.frames, qframe(c.term + 1, c.size - 1, c.last, rest, c.frame))", "push!(st.frames, qframe(c.term, c.size - 1, c.last, rest, c.frame))"),
    m("TR2-C4 peek_query reads the functor of a compound query wrongly (KILL D t6, t7: every compound query key is cut)",
      "        return (Q_KEY, ld.gstack[f], f)\n", "        return (Q_KEY, ld.gstack[f + 1], f)\n"),
    m("TR2-C5 peek_query reads the root query in the wrong slot (KILL D t2: the root key is read from another term reference)",
      "p = c.term != 0 ? c.term : -(st.key + 1)", "p = c.term != 0 ? c.term : -(st.key + 2)"),
    m("TR2-C6 a stored variable is cut against a constant query (KILL D t13: the query p(a, ..., b) against p(V1, ..., Vn, Vi) cuts every path)",
      "        if tagex(skey) == TAGEX_VAR || skey == qkey\n", "        if skey == qkey\n"),
    m("TR2-C7 the single-child fast path of descent_node! also runs while pruning (KILL D t7, t6: the cursor is not advanced over the child key)",
      "if is_single_child(children) && !c.prune\n", "if is_single_child(children)\n"),
    # ---- the choice stack and its branches
    # TR2-S1 is a DECLARED HANG (audit D-0524 item 1, D-0541 item 4). (a) the kill row is D t0 (test_trie_gen_swipl.jl, kernel_lines); (b) the spin site is
    # src/pl-trie.jl:2810 `while st.nch != 0` in trie_gen_raw (`nid = st.choices[st.nch].child`), inside the foreign call pl_trie_gen3_va (:2880) from
    # `_tp_row` (test_trie_gen_swipl.jl:78) under PL_next_solution: the leaf is examined again and again because pop_choice! keeps the path, in ONE
    # foreign call that no row or findnsols can stop. (c) PROGRESS, not a wall limit (a wall limit cannot tell a hang from a slow mutant): the
    # unmutated reference prints the D testset's rows and its summary; the mutant produces none, and the SIGQUIT stack at 900 s is one constant chain
    # (trie_gen_raw :2810, trie_gen :2871, pl_trie_gen3_va :2880, _fcall_va pl-ext.jl:262, PL_next_solution_guarded pl-wam.jl:5231, _tp_row TG:78):
    # evidence/TAB1/timeout_d5_handoff.md section 2, timeout_d5_s1_stack.txt. (d) the engine stop (a `next_choice! == 0 && break` at the three exits)
    # is NOT adopted: fidelity, the pin's loop is the plain `while`.
    m("TR2-S1 pop_choice! does not lower the path (KILL D t0; HANG at src/pl-trie.jl:2810, declared: see the comment above)",
      "    st.nch = chi - 1\n    return nothing\n", "    st.nch = chi\n    return nothing\n", hang=True),
    m("TR2-S2 add_branch! keeps the prune flag of a reused branch (KILL D t13, t29 expected: a branch reused after a non-pruning one restores a stale cursor)",
      "    br = st.branches[nb]\n    br.cursor.prune = false\n    return br\n", "    br = st.branches[nb]\n    return br\n"),
    m("TR2-S3 advance_node! (CH_ENUM) does not store the key (KILL D t0: the next child is taken with the key of the last)",
      "        if child != 0\n            ch.key = k\n            ch.child = child\n            return true\n", "        if child != 0\n            ch.child = child\n            return true\n"),
    m("TR2-S4 add_choice!: a constant block with the scan bit goes the CH_VARS way (KILL D t13: the variables from 32 on are never tried, 2..40 loses answers)",
      "((vmask | amask) & VMASK_SCAN) == 0\n", "((vmask | amask) & VMASK_SCAN) != 0\n"),
    m("TR2-S5 add_choice!: the child of a constant key is looked up under another key (KILL K t2, t3: f(2) and f(X) answer nothing)",
      "            child = get_child(tr, node, k)\n            if child == 0\n                pop_choice!(st, chi)\n                return 0\n            end\n            ch.child = child\n",
      "            child = get_child(tr, node, k + 1)\n            if child == 0\n                pop_choice!(st, chi)\n                return 0\n            end\n            ch.child = child\n"),
    m("TR2-S6 next_choice! stops at a leaf without a value (KILL D t0: the test of the flags is inverted)",
      "ch != 0 && !st.resume && (tr.nodes[st.choices[ch].child].flags & st.vflags) == 0\n", "ch != 0 && !st.resume && (tr.nodes[st.choices[ch].child].flags & st.vflags) != 0\n"),
    m("TR2-S7 next_choice0! does not restore the cursor before the node (output equivalent)",
      "            restore_cursor!(ld, st, ch, st.before)\n", "",
      eq="src/pl-trie.jl:2690-2696 next_choice0!: the restore result is read only through `st.before.prune` (:2693) and the cursor `cp`. Without the call `st.before` keeps its initial non-pruning value, so backtracking prunes less (align_key! :2459-2461 accepts every key of a non-pruning cursor), never more; a non-pruning kept cursor is restored to `prune = false` (restore_cursor! :2646-2649) which is that initial value. The det flag is read at the bound=true call (:2686-2688), which returns before the restore when the kept cursor prunes (:2686), so the restore cannot change it. Probes: TG file green with the mutant, fuzz equal"),
    m("TR2-S8 next_choice0! returns at every advance, not only where a cursor is kept (output equivalent)",
      "if bound && st.branches[st.choices[ch].branch].cursor.prune\n", "if bound\n",
      eq="src/pl-trie.jl:2686 next_choice0!: at a non-pruning kept cursor the real code restores (prune = false), aligns without a test (:2459-2461) and descends (descent_node! :2618-2638) to a valued leaf, so it returns nonzero exactly where the mutant returns at once: both leave a choice point (retry). A valueless leaf listed by advance_node! would differ: it is not reachable, trie_delete (:1670-1684, its only caller :2120 passes prune = true) prunes the emptied leaf from its parent (prune_node :808-818, guarded by `tr.references == 0`, written only at its init :130), TN_PINNED is tested at :812 and :855 and not found set, TN_SECONDARY is cleared (:782, :1674) and not found set, st.vflags is TN_PRIMARY for root 1 (:2213), so every inner node has a valued leaf below it. Rows t34-t37 (the det flag through call_cleanup, expected from swipl) pass with the mutant and stay as pins; revisit with TB1 (tabling sets references). Revisit when a step ports a setter of tr.references or TN_PINNED (tabling, trie_gen acquire): the equivalence holds only while nothing sets them (git grep over src: only pl-trie.jl:130 init, :223/:1675 reads, :812/:855 tests)."),
    m("TR2-S9 restore_cursor! replay: the key of the node itself is stepped over (KILL R t38: the replayed advanced choice is aligned one query argument too far; trie_gen(T, f(X, b)) over [f(a,b), f(c,b), f(d,e)] loses f(c, b); the rows t32/t33 with the query f(a, a) pass with it)",
      "        i == upto && break\n        align_key!(ld, st, c, ch.key) || (c.prune = false)\n", "        align_key!(ld, st, c, ch.key) || (c.prune = false)\n        i == upto && break\n"),
    # ---- the answer
    m("TR2-A1 unify_trie_path! leaves out the last key (KILL D t0: every answer misses its last key)",
      "    for i in 1:st.nch\n        rc = unify_key(", "    for i in 1:(st.nch - 1)\n        rc = unify_key("),
    m("TR2-A2 trie_gen_raw: a deleted leaf is answered (KILL K t30, t31: the leaf the state is positioned on is deleted at the first answer and stays in the result; t11 deletes a leaf further ahead, which next_choice! skips itself)",
      "if (n.flags & st.vflags) == 0 ", "if false "),
    m("TR2-A3 trie_gen_raw: the Value is not unified (KILL K t3: `trie_gen(T, f(2), K)` answers every key; D t18)",
      "if (Value == 0 || unify_value(ld, trs, Value, n.value)) &&", "if (true || unify_value(ld, trs, Value, n.value)) &&"),
    m("TR2-A4 trie_gen_raw: the node handle is not unified (KILL D t17: `$trie_gen_node` leaves N unbound, trie_term/2 raises)",
      "(Data == 0 || PL_unify_int64(ld, Data, trie_node_handle(trs, nid)))", "(true || PL_unify_int64(ld, Data, trie_node_handle(trs, nid)))"),
    m("TR2-A5 trie_gen_raw: a failed Value does not undo the Key (KILL K t18, t3: Key stays bound to f(b), the next leaf fails to unify)",
      "            else\n                PL_rewind_foreign_frame(ld, fid)\n            end\n", "            else\n            end\n"),
    m("TR2-A6 trie_gen_raw: the next leaf is looked for with the Key unbound and pruning (KILL D t0, t2: the Key is bound to the answer, the pruning cuts the rest)",
      "if next_choice!(ld, st, true) != 0      # Key is bound to the answer", "if next_choice!(ld, st, false) != 0      # Key is bound to the answer"),
    m("TR2-A7 trie_gen_raw: the first leaf is not descended to (KILL D t0: the first answer is an inner node)",
      "chi != 0 && (chi = descent_node!(ld, st, st.cur, chi))", "chi != 0 && (chi = chi)"),
    m("TR2-A8 trie_gen_raw: a redo does not take this activation's Key (KILL the white-box testset `a redo of trie_gen/2 keeps the Key reference of its own activation` in TG: it redoes by hand with another pair of references; through the VM the reference never changes, so no answer row sees it)",
      "        st.key = Key                                    # this activation's reference\n", ""),
    m("TR2-A9 trie_gen_raw counts no call (KILL K t20: gen_call_count is 0 after a trie_gen)",
      "        trf.gen_call += 1 ", "        trf.gen_call += 0 "),
    m("TR2-A10 trie_gen: the root of the trie is node 0 (KILL D t0: `tr.nodes[0]`)",
      "root = Root == 0 ? 1 : Root", "root = Root"),
    m("TR2-A11 init_trie_state!: the leaves of a trie are secondary (KILL D t0: nothing has TN_SECONDARY, no answer)",
      "st.vflags = root == 1 ? TN_PRIMARY : TN_SECONDARY", "st.vflags = TN_SECONDARY"),
    m("TR2-A12 init_trie_state! keeps the resume flag of the record's last use (KILL D t10, t27 expected: an enumeration cut after its first answer leaves the flag set)",
      "    st.resume = false\n    st.nch = 0\n    st.nbr = 0\n    empty!(st.frames)\n    return nothing\nend\n\n# PORT: pl-trie.c add_branch",
      "    st.nch = 0\n    st.nbr = 0\n    empty!(st.frames)\n    return nothing\nend\n\n# PORT: pl-trie.c add_branch"),
    # ---- the state record
    m("TR2-L1 the last answer keeps its state (KILL L: `ld.trie_gens.live != 0` after the row)",
      "                else\n                    clear_trie_state!(pool, k)\n                    PL_close_foreign_frame(ld, fid)\n                    return FTRUE\n",
      "                else\n                    PL_close_foreign_frame(ld, fid)\n                    return FTRUE\n"),
    m("TR2-L2 a cut enumeration keeps its state (KILL L: t9, t10, t27 leave `live == 1`)",
      "        clear_trie_state!(pool, PL_foreign_context_address(PL__ctx))\n        return FTRUE\n", "        return FTRUE\n"),
    m("TR2-L3 a failed enumeration keeps its state (KILL L: t4, t23 expected: `live` stays above 0)",
      "    clear_trie_state!(pool, k)\n    PL_close_foreign_frame(ld, fid)\n    return FFALSE\nend\n", "    PL_close_foreign_frame(ld, fid)\n    return FFALSE\nend\n"),
    # ---- the predicates ($trie_property: D t14, t19, t20, t21, t22)
    m("TR2-P1 $trie_property node_count is one more (KILL D t14, t19)",
      "return PL_unify_integer(ld, arg, tr.node_count) ? FTRUE : FFALSE", "return PL_unify_integer(ld, arg, tr.node_count + 1) ? FTRUE : FFALSE"),
    m("TR2-P2 $trie_property value_count is the node count (KILL D t14, t19)",
      "return PL_unify_integer(ld, arg, tr.value_count) ? FTRUE : FFALSE", "return PL_unify_integer(ld, arg, tr.node_count) ? FTRUE : FFALSE"),
    m("TR2-P3 $trie_property gen_call_count is the lookup count (KILL D t20: G0 is 1, not 0)",
      "return PL_unify_int64(ld, arg, tr.gen_call) ? FTRUE : FFALSE", "return PL_unify_int64(ld, arg, tr.lookups) ? FTRUE : FFALSE"),
    m("TR2-P4 $trie_property deadlock fails (KILL D t19: P7 is none, swipl answers 0)",
      "name == sym_key(mk_sym(T, :wait)) || name == sym_key(mk_sym(T, :deadlock))", "name == sym_key(mk_sym(T, :wait))"),
    m("TR2-P5 $trie_property reads a one-argument property as a two-argument one (KILL D t19, t21)",
      "(na === nothing || na[2] != 1) && return FFALSE", "(na === nothing || na[2] != 2) && return FFALSE"),
    m("TR2-P6 $trie_property compiled_size answers 0 (KILL D t21: swipl without a compiled trie fails)",
      "mk_sym(T, :compiled_size))\n        return FFALSE", "mk_sym(T, :compiled_size))\n        return PL_unify_int64(ld, arg, 0) ? FTRUE : FFALSE"),
    m("TR2-P7 $trie_property discarded is true (KILL D t19: P5 is `discarded(false)`)",
      "PL_unify_bool(ld, arg, (tr.flags & TRIE_DISCARDED) != 0)", "PL_unify_bool(ld, arg, true)"),
    m("TR2-P8 trie_gen/3 gives no Value argument (KILL D t1, K t3, t18: the third argument is never unified)",
      "PL__t0, 0, PL__t0 + 1, PL__t0 + 2, 0, 0, PL__ctx)", "PL__t0, 0, PL__t0 + 1, 0, 0, 0, PL__ctx)"),
    # ---- registration (TG: undefined predicate or a deterministic one; TB: the foreign rows of the boot image)
    m("TR2-R1 trie_gen/2 is not registered (KILL D t0: undefined; TB the foreign-row count)",
      "    PL_extension(\"trie_gen\", 2, pl_trie_gen2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),\n", "", targets=TR),
    m("TR2-R2 trie_gen/3 is deterministic (KILL D t1: one answer instead of three; TB the flag of the foreign row)",
      "PL_extension(\"trie_gen\", 3, pl_trie_gen3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS)", "PL_extension(\"trie_gen\", 3, pl_trie_gen3_va, PL_FA_VARARGS)", targets=TR),
    m("TR2-R3 $trie_gen_node/3 is deterministic (KILL D t17: one answer instead of two)",
      "\"\\$trie_gen_node\", 3, pl_trie_gen_node3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS", "\"\\$trie_gen_node\", 3, pl_trie_gen_node3_va, PL_FA_VARARGS", targets=TR),
    m("TR2-R4 $trie_property/2 is not registered (KILL D t14, t19: undefined; TB the foreign-row count)",
      "    PL_extension(\"\\$trie_property\", 2, pl_trie_property2_va, PL_FA_VARARGS)\n", "", targets=TR),
    # ---- DEFERRED KILL and EQUIVALENT
    # TR2-K1 and TR2-K2 were declared deferred kills (no row asked a constant of a block holding a variable key); the battery of 61d5e365 (run
    # 43007826638) REFUTED the claim: a program row of test_trie_gen_swipl.jl:180 (the .out answers) fails under each. Listed as kills.
    m("TR2-K1 add_choice!: the variable keys are tried first of all, the constant never (KILL TG:180, the program rows; found by the battery of 61d5e365)",
      "            br.novar = k\n", "            br.novar = word(0)\n"),
    m("TR2-K2 advance_node! (CH_VARS): the equal constant key is not tried first (KILL TG:180, as TR2-K1)",
      "        if br.novar != 0\n", "        if false\n"),
    m("TR2-Q1 skip of a nonvar query: the cut is a continuation (a cut that does not cut; output equivalent)",
      "        return false                                    # cut\n", "        @goto stepped                                   # cut\n",
      eq="src/pl-trie.jl:2325 align_pruning_key! (`return false  # cut`): pruning less changes no answer: unify_trie_path! (:2596) decides every leaf, so a path that is not cut is found and refused there; only the work differs"),
    m("TR2-Q2 concrete_ahead always true (the cursor never stops pruning; output equivalent)",
      "    return (c.size != 0 && c.last != 0 && c.term <= c.last) ||\n           (c.frame != 0 && st.frames[c.frame].rest)\n", "    return true\n",
      eq="src/pl-trie.jl:2239 concrete_ahead: it only decides when `c.prune` is cleared (align_pruning_key!, label `stop`); a cursor that keeps pruning reads `Q_DONE` and clears it there (`popn != 0 && pop_query_frame!(st, c)` or `@goto stop`); a longer prune cannot cut a path the query unifies with (a `Q_DONE` is not a cut)"),
    m("TR2-Q3 enter_query_compound!: `last` is the first nonvar argument (pruning stops earlier; output equivalent)",
      "    for a in (f + arity):-1:(f + 1)\n", "    for a in (f + 1):1:(f + arity)\n",
      eq="src/pl-trie.jl:2213 enter_query_compound!: `last` only feeds concrete_ahead (see TR2-Q2): an earlier `last` stops the pruning earlier, never cuts"),
    m("TR2-Q4 enter_query_compound!: `rest` is false (pruning stops earlier; output equivalent)",
      "        rest = (c.last != 0 && c.last > c.term) || (c.frame != 0 && st.frames[c.frame].rest)\n", "        rest = false\n",
      eq="src/pl-trie.jl:2206 enter_query_compound!: `rest` only feeds concrete_ahead (see TR2-Q2)"),
    m("TR2-Q5 restore_cursor!: a kept cursor of an older epoch is used (the epoch never moves; output equivalent)",
      "    if ubr.epoch == st.epoch\n", "    if true\n",
      eq="src/pl-trie.jl:2163 check_epoch! and :2518 restore_cursor!: the count of collections is the constant 0 and no stack shift moves a position, so a kept cursor stays valid in every epoch; the replay (the branch after) gives the same cursor (ld.trie_gen_force_epoch, testset R, checks that); only the work differs"),
    m("TR2-Q6 init_trie_state! does not reset the path and the frames (clear_trie_state! does it)",
      "    st.resume = false\n    st.nch = 0\n    st.nbr = 0\n    empty!(st.frames)\n    return nothing\nend\n\n# PORT: pl-trie.c add_branch\n",
      "    st.resume = false\n    return nothing\nend\n\n# PORT: pl-trie.c add_branch\n",
      eq="src/pl-trie.jl:2151 clear_trie_state! (`st.nch = 0`, `st.nbr = 0`, `empty!(st.frames)`) runs before every release of a record, and a record never used has nch == nbr == 0 and no frames (the constructor, src/pl-incl.jl:1558 trie_gen_state{T}()); init_trie_state! sets them again"),
    m("TR2-Q7 $trie_gen_node/3 passes data kind 0 (the argument is not read)",
      "PL__t0 + 1, 0, PL__t0 + 2, 1, PL__ctx)", "PL__t0 + 1, 0, PL__t0 + 2, 0, PL__ctx)",
      eq="src/pl-trie.jl:2620-2715 trie_gen_raw: `data_kind` is an argument and is not read in the body (the handle is unified when `Data != 0`, which pl_trie_gen_node3_va sets by passing PL__t0 + 2)"),
    m("TR2-Q8 check_epoch! counts an epoch without a collector (the epoch only matters under ld.trie_gen_force_epoch; output equivalent)",
      "        st.gc_seen = gcs\n        st.epoch += 1\n", "        st.gc_seen = gcs\n        st.epoch += 2\n",
      eq="src/pl-trie.jl:2163-2170 check_epoch!: the epoch is compared for equality with a branch's (restore_cursor!), never ordered; a step of 2 instead of 1 changes nothing"),
]
