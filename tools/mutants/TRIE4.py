# ORIGINAL: TR4's mutant list — no swipl-devel counterpart.
# tools/mutants/TRIE4.py — the mutation battery of TR4, the compiled tries: the compile block of src/pl-trie.jl (compile_trie and its emitters
# add_else!/fixup_else!/add_literal!/add_smallint!/add_vmi_else_i!, compile_trie_node, compile_trie_value, create_trie_clause, the clause
# reference kept in `trie.clause_cref`, trie_discard_clause, trie_table_size, `initTries!(gd)` and `pl_trie_compile2_va`), its one boot call
# (src/pl-setup.jl), and the VM side in src/pl-wam.jl: S_TRIE_GEN, T_TRIE_GEN2/3 (`t_trie_gen`), T_VALUE, the T_TRY_* entries, T_FUNCTOR,
# T_POP/T_POPN, T_VAR, T_STRING/T_MPZ, `t_const`, T_CHECKWAKEUP and the `_trie_*` state helpers; one row of the code table of src/pl-vmi.jl. The list pins
# what is there at the gate of TR4 (NOTHING was run when it was drafted: the kills below are read off the rows, the CI battery is the verdict).
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE1.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the row that must fail: TC = test/core_lang/test_trie_compiled_swipl.jl: its `tN` rows (the program
#   test_trie_compiled_swipl.pl, answers in test_trie_compiled_swipl.out: swipl's, and the kill testset by row name) or its kernel-only
#   testset KD-1; TW = test/core_lang/test_trie_swipl.jl (white-box rows on LK.* internals: trie_discard_clause :161-164 and `_tr_discard_clause_rows` at the end of the file, trie_table_size
#   :746/:755), TP = test/core_lang/test_trie_preds_swipl.jl, TO = test/core_lang/test_cont_boot_swipl.jl (the opcode order of the tail of
#   the code table), TB = test/db/test_boot_image_swipl.jl (the boot-module predicate rows).
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. The compile block runs through `$trie_compile` and
#   `trie_gen_compiled/2,3` (TC); trie_discard_clause also under TW (rows :161-164) and through every trie change TP makes; the VM bodies and the `_trie_*`
#   helpers run only in TC's rows; a dropped registration (`initTries!`, its call in src/pl-setup.jl) also TB, a reordered code table TO. The
#   `TARGETS` variable is the union (mutate_ci.py plan reads it).
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. TR4-I1, TR4-I3 and TR4-B1 are BOOT-PATH mutants (`initTries!(gd)` runs
#   while the database boots, before any test row; `PL_global_data{T}()` copies a template built once per process, src/gd_template.jl): the warm daemon cannot
#   judge them, only `tools/mutate_ci.py one` (one process per mutant) or the CI battery does (audit D-0451 item 1, as TRIE1 N1/N2).
# TIMEOUT: a mutant that leaves an else slot open or loops the code stream may hang the VM run; no mutant of this list is meant to run unbounded, a timeout is NO
#   verdict, never caught.
# DEFERRED KILL (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet (no test reads what the mutant changes); it must
#   SURVIVE the battery and its owner step adds the row:
#   * TR4-N21, TR4-N23, TR4-S5 are KILL since DEFKILL5: N21 and N23 by the testset `compile_trie_node: a flagged node ...` of TW (white-box tries, `cl.codes`;
#     TW joined their targets); S5 by the testset `TR4-S5: ...` at the end of TC (a trie with an IDG node, `tr.clause` stays 0; TB6 gave the node).
#   (TR4-D3, the retract of the discarded clause, is no longer deferred: the row `_tr_discard_clause_rows` of TW reads the erased flag of the clause: it kills TR4-D3, TR4-D4, TR4-D5.)
#   Drafted and left out of this list as not worth a CI slot: the attributed-variable choices and `compounds -= popn` (TR3), TN_DELAYINFO and the `error` atom
#   (TB4, TR2), the empty-children path and trie_table_size of a compiled trie (TR2, TB3): each has the same owner and the same reason as a row above.
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): TR4-E9 (c2 is never emitted), TR4-N2 (T_POPN 1 is T_POP),
#   TR4-K4 (the cached `fail` atom), TR4-S4 (compile_trie answers `fail` for an empty trie), TR4-D6 (the `::Clause{T}` assertion of trie_discard_clause).
# Every `old` was counted EXACTLY once in its file by a python3 -I script at the tip of wip/tr4 when this file was written (no Julia ran); `new` != `old`; no duplicate
#   id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TC = "test/core_lang/test_trie_compiled_swipl.jl"
TW = "test/core_lang/test_trie_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TO = "test/core_lang/test_cont_boot_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TARGETS = [TC, TW, TP, TO, TB]               # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-trie.jl"
W = "src/pl-wam.jl"
V = "src/pl-vmi.jl"
SETUP = "src/pl-setup.jl"
TT = [TC]                                    # the compile block and the VM bodies
TD = [TC, TW, TP]                            # discard: every trie change reaches it


def m(id, old, new, targets=TT, file=F, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


def try_entry(label, outlined=False):
    """(old, new) of a T_TRY_* entry in src/pl-wam.jl: the choice point resumes one code too far. An outlined entry (T27) passes
    `tt_skip` to `_vmi_t_try!`, which makes the choice point at `PC + tt_skip`."""
    if outlined:
        head = (f"    @label {label}\n    tt_skip = Int(PCc[PC])                          # intptr_t skip = *PC++\n    PC += 1\n"
                f"    ts_st = _vmi_t_try!(ld, QID, FR, ARGP, PCc, PCl, PC, tt_skip)")
        return head, head.replace("PC, tt_skip)", "PC, tt_skip + 1)")
    head = (f"    @label {label}\n    tt_skip = Int(PCc[PC])                          # intptr_t skip = *PC++\n    PC += 1\n"
            f"    @ENSURE_LOCAL_SPACE(SIZEOF_CHOICE)\n    _trie_try!(ld, FR, PC + tt_skip)")
    return head, head.replace("PC + tt_skip", "PC + tt_skip + 1")


MUTANTS = [
    # ---- the emitters (TC rows t0, t7, t8, t10-t12)
    m("TR4-E1 add_else!: the else slot chain is not linked (KILL TC t7/t8: nested else slots, fixup_else! restores a 0 chain)",
      "    push!(st.codes, code(st.else_loc))\n", "    push!(st.codes, code(0))\n"),
    m("TR4-E3 fixup_else!: the distance is one too long (KILL TC t0: the skip of every T_TRY_* lands one code late)",
      "    st.codes[el + 1] = code(pc - el - 1)", "    st.codes[el + 1] = code(pc - el)"),
    m("TR4-E4 fixup_else!: the chain is not popped (KILL TC t8: after an inner fixup the outer else slot is lost; the assert of compile_trie)",
      "    st.else_loc = Int(st.codes[el + 1])", "    st.else_loc = 0"),
    m("TR4-E5 add_literal!: the literal index is 0-based (KILL TC t10: T_STRING/T_FLOAT/T_MPZ read PCl[0])",
      "    return code(length(st.literals))\n", "    return code(length(st.literals) - 1)\n"),
    m("TR4-E6 add_smallint!: the operand is not the tagged word (KILL TC t11, t48: T_SMALLINT compares another integer)",
      "add_smallint!(st::trie_compile_state, c1::code, c2::code, w::word)::Nothing =\n    add_vmi_d!(st, c1, code(w))",
      "add_smallint!(st::trie_compile_state, c1::code, c2::code, w::word)::Nothing =\n    add_vmi_d!(st, c1, code(w + word(1)))"),
    m("TR4-E7 add_vmi_else_i!: the operand is not the tagged word (KILL TC t11, t12: T_TRY_SMALLINT)",
      "    add_else!(st)\n    push!(st.codes, code(w))\n", "    add_else!(st)\n    push!(st.codes, code(w + word(1)))\n"),
    m("TR4-E9 add_smallint!: the instruction is c2 (EQUIVALENT: every call passes the same code twice)",
      "add_smallint!(st::trie_compile_state, c1::code, c2::code, w::word)::Nothing =\n    add_vmi_d!(st, c1, code(w))",
      "add_smallint!(st::trie_compile_state, c1::code, c2::code, w::word)::Nothing =\n    add_vmi_d!(st, c2, code(w))",
      eq="src/pl-trie.jl:2297, :2371 and :2405 call it with (T_SMALLINT, T_SMALLINT, w), the W form c2 is never emitted (CODES_PER_WORD == 1, the DIVERGES note of add_smallint!)"),
    # ---- compile_trie_node (TC rows)
    m("TR4-N1 POP key: popn == 2 chooses T_POP (KILL TC t8: `f(g(h(1)), ...)` pops two with one T_POP)",
      "                popn == 1 ? add_vmi!(st, T_POP) : add_vmi_d!(st, T_POPN, code(popn))\n            elseif isFunctor(key)",
      "                popn == 2 ? add_vmi!(st, T_POP) : add_vmi_d!(st, T_POPN, code(popn))\n            elseif isFunctor(key)"),
    m("TR4-N2 POP key: always T_POPN (EQUIVALENT: T_POPN with n == 1 is T_POP)",
      "                popn == 1 ? add_vmi!(st, T_POP) : add_vmi_d!(st, T_POPN, code(popn))\n            elseif isFunctor(key)",
      "                add_vmi_d!(st, T_POPN, code(popn))\n            elseif isFunctor(key)",
      eq="src/pl-wam.jl:3775-3785 (T_POPN: save the state, pop n times, TrieNextArg) does what src/pl-wam.jl:3767-3772 (T_POP) does for n == 1; only the code stream differs"),
    m("TR4-N3 functor key: no T_TRY_FUNCTOR for a non-last child (KILL TC t0: the first alternative's mismatch fails the clause, f(2) is lost)",
      "                if st.try_\n                    add_vmi_else_d!(st, T_TRY_FUNCTOR, code(key))\n                else\n                    add_vmi_d!(st, T_FUNCTOR, code(key))\n                end",
      "                add_vmi_d!(st, T_FUNCTOR, code(key))"),
    m("TR4-N4 atom key: no T_TRY_ATOM (KILL TC t11, t12: f(x) before f(y))",
      "                if st.try_\n                    add_vmi_else_d!(st, T_TRY_ATOM, code(key))\n                else\n                    add_vmi_d!(st, T_ATOM, code(key))\n                end",
      "                add_vmi_d!(st, T_ATOM, code(key))"),
    m("TR4-N5 string key: no T_TRY_STRING (KILL TC t10: \"abc\" before \"abd\")",
      "                    if st.try_\n                        add_vmi_else_d!(st, T_TRY_STRING, lit)\n                    else\n                        add_vmi_d!(st, T_STRING, lit)\n                    end",
      "                    add_vmi_d!(st, T_STRING, lit)"),
    m("TR4-N7 small integer key: no T_TRY_SMALLINT (KILL TC t11: f(-1), f(0), f(1) ...)",
      "                if st.try_\n                    add_vmi_else_i!(st, T_TRY_SMALLINT, T_TRY_SMALLINT, key)\n                else\n                    add_smallint!(st, T_SMALLINT, T_SMALLINT, key)\n                end",
      "                add_smallint!(st, T_SMALLINT, T_SMALLINT, key)"),
    m("TR4-N8 variable key: T_VAR with an else slot (KILL TC t6, t34: a variable beside an atom reads the skip as the index)",
      "                    c = if tx == TAGEX_VAR\n                        T_TRY_VAR\n",
      "                    c = if tx == TAGEX_VAR\n                        T_VAR\n"),
    m("TR4-N12 the last child is compiled with the previous child's try flag (KILL TC t0: its else slot stays open, the assert of compile_trie)",
      "                st.try_ = nxt != 0\n", "                st.try_ = true\n"),
    m("TR4-N13 a single child keeps the try flag (KILL TC t0: g(a) is compiled as T_TRY_ATOM with no fixup)",
      "                st.try_ = false\n                n = single_child(children)", "                st.try_ = true\n                n = single_child(children)"),
    m("TR4-N15 a map trie emits no T_VALUE (KILL TC t1: the value argument reads the key's cell)",
      "                add_vmi!(st, T_VALUE)\n                v = node.value", "                v = node.value"),
    m("TR4-N18 a compound value is read as a plain value (KILL TC t37, t38, t47, t48: the record walk is skipped)",
      "                if !isRecord(v)\n", "                if true\n"),
    m("TR4-N19 no T_CHECKWAKEUP (KILL TC t50: the hook of the attributed call variable does not run, both answers stay)",
      "            add_vmi!(st, T_CHECKWAKEUP)\n", "            nothing\n"),
    m("TR4-N21 a value-less leaf does not end the code with I_EXIT (KILL TW, the testset `compile_trie_node: a flagged node ...`: a path ending in a value-less leaf compiles to code ending I_FAIL, I_EXIT)",
      "            add_vmi!(st, I_FAIL)\n            st.last_is_fail = true", "            add_vmi!(st, I_FAIL)\n            st.last_is_fail = false", targets=[TC, TW]),
    m("TR4-N23 the TN_PRIMARY/TN_SECONDARY test is dropped (KILL TW, the same testset: a TN_PRIMARY node with a child compiles to the code of the trie without the child)",
      "        if children != 0 && (node.flags & (TN_PRIMARY | TN_SECONDARY)) == 0", "        if children != 0", targets=[TC, TW]),
    # ---- compile_trie_value (TC t47-t49)
    m("TR4-V1 a variable of a value takes the next index (KILL TC t47: v(X, X, _) reads another cell)",
      "            add_vmi_d!(st, T_VAR, code(index))\n        elseif isAttVar(w)", "            add_vmi_d!(st, T_VAR, code(index + 1))\n        elseif isAttVar(w)"),
    m("TR4-V2 the variable is not marked in the value (KILL TC t47: the repeated X is a new variable, A == B fails)",
      "                p > 0 && (ld.gstack[p] = consTagged(index, TAGEX_VAR))\n            else\n                index = Int(valTagged(w))",
      "                nothing\n            else\n                index = Int(valTagged(w))"),
    m("TR4-V4 the bigint of a value is an atom (KILL TC t49: w(\"str\", 2.5, 10^20, x))",
      "                T_STRING\n            else\n                T_MPZ\n", "                T_STRING\n            else\n                T_ATOM\n"),
    # ---- clause creation, compile_trie, '$trie_compile'
    m("TR4-C1 the clause holds no variable slots (KILL TC t6, t35, t47: the T_VAR cells lie outside the frame)",
      "    nvars = clsize_t(TRIE_VAR_OFFSET + st.maxvar)", "    nvars = clsize_t(TRIE_VAR_OFFSET)"),
    m("TR4-K1 compile_trie compiles again (KILL TC t51: two '$trie_compile' give two clauses, C1 == C2 fails)",
      "    dbref != 0 && return dbref\n", "    nothing\n"),
    m("TR4-K2 an empty trie is compiled when it holds one value (KILL TC t21, t29, t4: the atom fail for an empty trie)",
      "    if tr.value_count == 0\n        dbref = _atom_word!", "    if tr.value_count == 1\n        dbref = _atom_word!"),
    m("TR4-K3 the generator instruction by the wrong arity (KILL TC t0, t1: T_TRIE_GEN3 for key-only)",
      "    gen = def.arity == 2 ? T_TRIE_GEN2 : T_TRIE_GEN3", "    gen = def.arity == 3 ? T_TRIE_GEN2 : T_TRIE_GEN3"),
    m("TR4-K4 the cached `fail` atom is not kept (EQUIVALENT: compile_trie answers the same atom again)",
      "        dbref = _atom_word!(ld, mk_sym(T, :fail))\n        tr.clause = dbref\n", "        dbref = _atom_word!(ld, mk_sym(T, :fail))\n",
      eq="src/pl-trie.jl:2467-2471: an empty trie answers `fail` again on the next call (t21, t29 see the same atom), S_TRIE_GEN backtracks on it (src/pl-wam.jl:3646); trie_discard_clause (:173) clears the word only to retract a clause, none exists for `fail`"),
    m("TR4-K5 the clause reference is not kept (KILL TC t0: S_TRIE_GEN's `_trie_clause_cref` is `nothing`, a TypeError)",
      "            tr.clause_cref = cref ", "            tr.clause_cref = nothing "),
    m("TR4-K6 the clause word is not kept (KILL TC t51: every call compiles a new clause)",
      "            dbref = blob_handle(lookup_clref(gd, cl))\n            tr.clause = dbref\n", "            dbref = blob_handle(lookup_clref(gd, cl))\n"),
    m("TR4-K8 '$trie_compile' of a map trie uses trie_gen_compiled/2 (KILL TC t24, t25: T_TRIE_GEN2 with T_VALUE)",
      "            gd.procedures_trie_gen_compiled3\n        else\n            gd.procedures_trie_gen_compiled2", "            gd.procedures_trie_gen_compiled2\n        else\n            gd.procedures_trie_gen_compiled3"),
    # ---- discard and size
    m("TR4-D1 trie_discard_clause keeps the clause word (KILL TC t16, t17: the next call runs the old clause; TW :161-164)",
      "        tr.clause = word(0)                                     # COMPARE_AND_SWAP_ATOM(&trie->clause, dbref, 0)\n",
      "        nothing                                                 # COMPARE_AND_SWAP_ATOM(&trie->clause, dbref, 0)\n", targets=TD),
    m("TR4-D2 trie_discard_clause keeps the clause reference (KILL TW :164: `tr4.clause_cref === nothing`)",
      "        tr.clause_cref = nothing\n        if gd.halt_cleaning == CLN_NORMAL", "        nothing\n        if gd.halt_cleaning == CLN_NORMAL", targets=TD),
    m("TR4-D3 the discarded clause is not retracted (KILL TW `_tr_discard_clause_rows`: `cl.flags & CL_ERASED != 0` after trie_destroy)",
      "                retractClauseDefinition!(gd, cl.predicate::Definition{T}, cl, false)", "                nothing", targets=TD),
    m("TR4-D4 trie_discard_clause retracts under the wrong halt state (KILL TW `_tr_discard_clause_rows`: the clause is not erased after trie_destroy, and is erased under CLN_DATA)",
      "        if gd.halt_cleaning == CLN_NORMAL                       # otherwise reclaims clause",
      "        if gd.halt_cleaning != CLN_NORMAL                       # otherwise reclaims clause", targets=TD),
    m("TR4-D5 trie_discard_clause: the guard on the kept reference is inverted (KILL TW `_tr_discard_clause_rows`: no retract after trie_destroy; the `fail` row :161-164 reads `nothing.clause`)",
      "            if cref !== nothing                                 # ClauseRef cref = clause_clref(dbref)",
      "            if cref === nothing                                 # ClauseRef cref = clause_clref(dbref)", targets=TD),
    m("TR4-D6 trie_discard_clause drops the `::Clause{T}` assertion (EQUIVALENT at run time: the reference always holds its clause)",
      "                cl = cref.clause::Clause{T}                     # cref->value.clause",
      "                cl = cref.clause                                # cref->value.clause", targets=TD,
      eq="src/pl-proc.jl:514-515 newClauseRef makes the cell `ClauseRef{T}(nothing, key, clause, nothing)` with a `Clause{T}`, src/pl-trie.jl:3441-3445 compile_trie keeps only that cell (`tr.clause_cref = cref`), and no site sets `cref.clause = nothing`: the assertion cannot raise, and without it the same clause is read (a static-analysis finding: JET sees a `Union{Nothing, Clause{T}}`; pin pl-trie.c:283 reads `cref->value.clause` with no test)"),
    # ---- the registration (BOOT PATH: judged by tools/mutate_ci.py one)
    m("TR4-I1 trie_gen_compiled/2 has no supervisor (KILL TB: the boot-module row of system:trie_gen_compiled/2; TC every row)",
      "    def.codes = gd.code_data.trie_gen                           # SUPERVISOR(trie_gen)\n    gd.procedures_trie_gen_compiled2 = proc",
      "    gd.procedures_trie_gen_compiled2 = proc", targets=[TC, TB]),
    m("TR4-I3 trie_gen_compiled/2 is not locked (KILL TC t0: asserting the compiled clause resets the supervisor, src/pl-supervisor.jl:315)",
      "    def.flags |= P_LOCKED_SUPERVISOR | P_VOLATILE\n    def.codes = gd.code_data.trie_gen                           # SUPERVISOR(trie_gen)\n    gd.procedures_trie_gen_compiled2 = proc",
      "    def.flags |= P_VOLATILE\n    def.codes = gd.code_data.trie_gen                           # SUPERVISOR(trie_gen)\n    gd.procedures_trie_gen_compiled2 = proc", targets=[TC, TB]),
    m("TR4-B1 setupProlog does not call initTries!(gd) (KILL TB: the foreign-row count; TC every row)",
      "    initTries!(gd)                              # initTries (setup:149), its tail: trie_gen_compiled/2,3 (TR4, src/pl-trie.jl)",
      "    nothing                                     # (the tail of initTries dropped)", targets=[TC, TB], file=SETUP),
    # ---- S_TRIE_GEN (src/pl-wam.jl)
    m("TR4-S1 S_TRIE_GEN: the atom fail is no failure (KILL TC t29: trie_gen_compiled(fail, _) raises a type_error)",
      "    stg_w == stg_fail && @goto deep_backtrack       # if ( dbref == ATOM_fail ) FRAME_FAILED\n", "    nothing\n", file=W),
    m("TR4-S2 S_TRIE_GEN: a non-trie atom is no type error (KILL TC KD-1 k1, k2: a FieldError for `foo`)",
      "        stg_tr === nothing && @goto trie_gen_type_error     # if ( !(t = symbol_trie(dbref)) )", "        false && @goto trie_gen_type_error                  # if ( !(t = symbol_trie(dbref)) )", file=W),
    m("TR4-S4 S_TRIE_GEN: an empty trie is not left at once (EQUIVALENT: compile_trie answers `fail`, the next line backtracks)",
      "            stg_tr.value_count == 0 && @goto deep_backtrack # FRAME_FAILED\n", "            nothing\n", file=W,
      eq="src/pl-trie.jl:2467-2471: compile_trie answers `fail` for value_count == 0, and src/pl-wam.jl:3646 `stg_w == stg_fail && @goto deep_backtrack` leaves the frame the same way (t4, t5 see no difference)"),
    m("TR4-S5 S_TRIE_GEN: the single-answer shortcut is taken for arity 3 (KILL TC, the testset `TR4-S5: ...`: a table trie with an IDG node and one answer is not compiled, `tr.clause` stays 0)",
      "            if DEF.arity == 2                       # if ( DEF->functor->arity == 2 && (answer=tbl_single_answer(t)) )", "            if DEF.arity == 3                       # if ( DEF->functor->arity == 2 && (answer=tbl_single_answer(t)) )", file=W),
    # ---- T_TRIE_GEN2/3 (t_trie_gen), T_VALUE
    m("TR4-G1 T_TRIE_GEN2 builds +/2 (KILL TC t0: the key is unified with the wrong argument)",
      "    _slot_new_var!(ld, argFrameP(tg_base, 2) + 1)  # setVar(argFrame(FR, 2))\n    tg_ar = 1", "    _slot_new_var!(ld, argFrameP(tg_base, 2) + 1)  # setVar(argFrame(FR, 2))\n    tg_ar = 2", file=W),
    m("TR4-G2 T_TRIE_GEN3 builds +/1 (KILL TC t1: the value argument is never unified)",
      "    tg_ar = 2\n    @goto t_trie_gen", "    tg_ar = 1\n    @goto t_trie_gen", file=W),
    m("TR4-G3 the TrieOffset starts at 2 (KILL TC t0: T_FUNCTOR reads the cell after the key)",
      "    ld.gstack[tg_s + 1] = consInt(1)                # *TrieOffset = consInt(1)", "    ld.gstack[tg_s + 1] = consInt(2)                # *TrieOffset = consInt(1)", file=W),
    m("TR4-H1 T_VALUE: the offset is not moved to the value argument (KILL TC t1, t3: the value is read from the key's cell)",
      "    ld.gstack[_trie_state_cell(ld, FR, 1)] = consInt(2)    # *TrieOffset = consInt(2)", "    ld.gstack[_trie_state_cell(ld, FR, 1)] = consInt(1)    # *TrieOffset = consInt(2)", file=W),
    m("TR4-H2 T_VALUE: the arg stack is not unwound (KILL TC t1, t3: `+(Key, Value)` is not the current term)",
      "    @label T_VALUE\n    _trie_unwind_argp!(ld, FR)                      # UnwindTrieArgP()", "    @label T_VALUE\n    nothing                                         # UnwindTrieArgP()", file=W),
    # ---- the T_TRY_* entries: the jump distance of the choice point (the label's lines are unique)
    m("TR4-Y1 T_TRY_FUNCTOR: the choice point resumes one code too far (KILL TC t0: f(2) after f(1))",
      *try_entry("T_TRY_FUNCTOR", outlined=True), file=W),
    m("TR4-Y2 T_TRY_VAR: the choice point resumes one code too far (KILL TC t6, t34)",
      *try_entry("T_TRY_VAR", outlined=True), file=W),
    m("TR4-Y3 T_TRY_ATOM: the choice point resumes one code too far (KILL TC t11, t12)",
      *try_entry("T_TRY_ATOM", outlined=True), file=W),
    # ---- T_FUNCTOR, T_POP, T_POPN, T_VAR, T_STRING, t_const, T_CHECKWAKEUP
    m("TR4-F1 T_FUNCTOR: any compound matches (KILL TC t2, t30: f(X) against g(a))",
      "        if ld.gstack[valPtr(tf_w)] == tf_f          # if ( term->definition == f )", "        if true                                     # if ( term->definition == f )", file=W),
    m("TR4-F2 T_POP: no TrieNextArg (KILL TC t32, t33: the next argument is read again)",
      "    _trie_pop_argp!(ld, FR)                         # TriePopArgP()\n    _trie_next_arg!(ld, FR)                         # TrieNextArg()\n    @goto next_instruction\n\n    # PORT: pl-vmi.c T_POPN",
      "    _trie_pop_argp!(ld, FR)                         # TriePopArgP()\n    @goto next_instruction\n\n    # PORT: pl-vmi.c T_POPN", file=W),
    m("TR4-F3 T_POPN: one pop too few (KILL TC t8, t48: the term stack stays inside the nested compound)",
      "    while tpn_n > 0                                 # while(n-->0) TriePopArgP()", "    while tpn_n > 1                                 # while(n-->0) TriePopArgP()", file=W),
    m("TR4-F4 T_VAR: a bound variable cell is bound again (KILL TC t6, t47: the repeated variable is not compared)",
      "    if isVar(ld.gstack[tv_v])                       # if ( isVar(*vp) )", "    if !isVar(ld.gstack[tv_v])                      # if ( isVar(*vp) )", file=W),
    m("TR4-F6 t_const: an unbound location is not bound (KILL TC t0, t2, t12: the key stays unbound)",
      "    if tk_k == DU_CELL || tk_k == DU_ATTVAR         # if ( canBind(*k) )\n        bindConst(ld, tk_p, tk_c)", "    if tk_k == DU_ATTVAR                            # if ( canBind(*k) )\n        bindConst(ld, tk_p, tk_c)", file=W),
    m("TR4-F7 T_CHECKWAKEUP: no wakeup (KILL TC t50: the hook does not prune the answer 2)",
      "    @label T_CHECKWAKEUP\n    (ld.alerted & ALERT_WAKEUP) != 0 && @goto check_wakeup     # CHECK_WAKEUP", "    @label T_CHECKWAKEUP\n    false && @goto check_wakeup                                # CHECK_WAKEUP", file=W),
    # ---- the state helpers
    m("TR4-U1 TrieSaveState does not trail the term stack (KILL TC t7, t8: a backtrack restores a stale TrieArgStackP)",
      "            TrailAssignment!(ld, _trie_state_cell(ld, fr, 2))   # TrailAssignment(TrieArgStackP)\n", "            nothing                                             # TrailAssignment(TrieArgStackP)\n", file=W),
    m("TR4-U3 TrieNextArg steps by two (KILL TC t32, t33: f(a, b, c) skips an argument)",
      "    ld.gstack[o] = consInt(Int(valInt(ld.gstack[o])) + 1)  # *TrieOffset = consInt(valInt(*TrieOffset)+1)", "    ld.gstack[o] = consInt(Int(valInt(ld.gstack[o])) + 2)  # *TrieOffset = consInt(valInt(*TrieOffset)+1)", file=W),
    m("TR4-U4 TriePushArgP saves offset 1 (KILL TC t52: a compound at the second argument returns to the first)",
      "    ld.gstack[a + 2] = ld.gstack[_trie_state_cell(ld, fr, 1)]   # _astack[2] = *TrieOffset", "    ld.gstack[a + 2] = consInt(1)                   # _astack[2] = *TrieOffset", file=W),
    m("TR4-U5 TRIE_TRY does not save the offset (KILL TC t0, t32: the alternative reads from the offset it was left at)",
      "    ld.choices[ch].trie_offset = ld.gstack[_trie_state_cell(ld, fr, 1)]    # ch->value.jump.trie_offset = *TrieOffset", "    ld.choices[ch].trie_offset = word(0)                                   # ch->value.jump.trie_offset = *TrieOffset", file=W),
    # ---- the code table (src/pl-vmi.jl; TO reads the tail's order against pl-vmi.c at the pin)
    m("TR4-O1 T_POP and T_POPN swapped in the code table (KILL TO: the tail is not in pl-vmi.c's order)",
      "    code_info(:T_POP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),\n    code_info(:T_POPN, 0x00, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),\n",
      "    code_info(:T_POPN, 0x00, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),\n    code_info(:T_POP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),\n", targets=[TO], file=V),
]
