# ORIGINAL: TR3's mutant list - no swipl-devel counterpart.
# tools/mutants/TRIE3.py - the mutation battery of TR3, attributed variables in tries (pl-trie.c O_TRIE_ATTVAR, defined at the pin,
# pl-incl.h:256): the attvar branches of `trie_lookup_abstract` (the attvar numbered with TAGEX_TRIE_ATTVAR, the pair in `vars`, the attribute
# list walked as a compound that ends with POP and TAGEX_TRIE_ATTVAR_END, the restore loop) and of `unify_key` (the functor key against an
# attvar, the keys TAGEX_TRIE_ATTVAR and TAGEX_TRIE_ATTVAR_END, `ukey_state.attrs`), all in src/pl-trie.jl. The list pins what is there at the gate
# of TR3. Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE1.py): `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the assertion that must fail:
#   TW = test/core_lang/test_trie_swipl.jl (white-box rows: the keys a term with an attvar makes, `vars`, the restored cells; the testset "trie
#   lookup: an attributed variable (TR3)", TW:1046-1159), TP = test/core_lang/test_trie_preds_swipl.jl (rows t77-t86, answers swipl's, from its .out;
#   kill rows `row("t77")`.. TP:331-340), TA = test/core_lang/test_trie_attvar_swipl.jl (rows a1-a17 and the kill rows `row("aN")` TA:184-189; the g rows
#   run once TR2 is stacked), TM = test/core_lang/test_tabling_min_swipl.jl (the lookup is on the tabling path; audit D-0238).
# TARGETS (audit D-0238): the trie_lookup_abstract mutants: TW, TP, TA, TM; the unify_key mutants: TP, TA, TM (TW's unify rows have no attvar key, except `_tr_unify_attvar_write_rows`, which TR3-U6 needs: U6 runs TT),
#   (each mutant carries its own `targets`). The `TARGETS` variable is the union (mutate_ci.py plan reads it).
# TIMEOUT: none of these can loop: each mutates a key, a counter or an index inside a walk bounded by the term.
# EQUIVALENT mutants (declared with their reason, file:line in the `equivalent` text): TR3-U1 and TR3-U2 (the write mode of an attvar's fresh cells).
# NOT HERE: the pl-trie.c trie_gen branches (owner TR2), the compiled-trie keys T_ATTVARA/Z/ZT (owner TR4), unify_trie_ret (owner TB).
# Every `old` was counted EXACTLY once in src/pl-trie.jl by a python3 -I script (the working tree of wip/tr3 after the TR3 commits; no Julia ran);
#   `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TW = "test/core_lang/test_trie_swipl.jl"
TP = "test/core_lang/test_trie_preds_swipl.jl"
TA = "test/core_lang/test_trie_attvar_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
TG = "test/core_lang/test_trie_gen_swipl.jl"   # TAB1 stack: trie_gen (TR2) runs unify_key and inserts through trie_lookup_abstract
TARGETS = [TW, TP, TA, TM, TG]                   # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-trie.jl"
TT = [TW, TP, TA, TM, TG]
UT = [TP, TA, TM, TG]


def m(id, old, new, targets=TT, file=F, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


END_INNER = "                    w = consTagged(\n                        valTagged(ld.gstack[attvars[end][2]]), TAGEX_TRIE_ATTVAR_END\n                    )\n                    pop!(attvars)\n"
END_TOP = "                    w = consTagged(\n                        valTagged(ld.gstack[attvars[end][2]]), TAGEX_TRIE_ATTVAR_END\n                    )\n                    node = follow_node(tr, node, TRIE_KEY_POP(popn), add)\n"

MUTANTS = [
    # ---- trie_lookup_abstract (TW _tr_lookup_attvar_rows 1046, _value_rows 1079, _shared_rows 1102, _more_rows 1123; TP t77-t86; TA a1-a17)
    m("TR3-L1 a shared attvar is opened again (KILL TW:1114, the second occurrence of f(Y, Y) is not ATTVAR 1 again; TP t82; TA a5)",
      "            if tagex(w) != TAGEX_TRIE_ATTVAR                    # the first encounter: open the attvar\n",
      "            if tagex(w) == TAGEX_TRIE_ATTVAR                    # the first encounter: open the attvar\n"),
    m("TR3-L2 the attribute list is no compound level (KILL TW:1062: no POP(2)/END keys, TW:1114, 1134)",
      "                    compounds += 1\n                    pushWorkCellAgenda_P0!(agenda, 1, ap)\n",
      "                    pushWorkCellAgenda_P0!(agenda, 1, ap)\n"),
    m("TR3-L3 the attribute list's POP merges with the last argument's (KILL TW:1062: POP(3) instead of POP(2); TW:1134)",
      "pushWorkCellAgenda_P0!(agenda, 1, ap)", "pushWorkCellAgenda_P!(agenda, 1, ap)"),
    m("TR3-L4 the inner END key is a plain ATTVAR key (KILL TW:1062, 1114, 1134)",
      END_INNER, END_INNER.replace("TAGEX_TRIE_ATTVAR_END\n", "TAGEX_TRIE_ATTVAR\n")),
    m("TR3-L5 the toplevel END key is a plain ATTVAR key (KILL TW:1147: the attvar as the term itself; TP t77, TA a2)",
      END_TOP, END_TOP.replace("TAGEX_TRIE_ATTVAR_END\n", "TAGEX_TRIE_ATTVAR\n")),
    m("TR3-L6 the attvar's end is not popped from `attvars` (KILL TW:1134: f(Y{a}, g(b), c) gets a second END key at the POP(1) of g)",
      "                    pop!(attvars)\n", "                    nothing\n"),
    m("TR3-L7 the toplevel POP key of an attvar term is omitted (KILL TW:1147)",
      "                    node = follow_node(tr, node, TRIE_KEY_POP(popn), add)\n                    node == 0 || (node = follow_node(tr, node, w, add))\n",
      "                    node == 0 || (node = follow_node(tr, node, w, add))\n"),
    m("TR3-L8 the toplevel END key of an attvar term is omitted (KILL TW:1147)",
      "                    node == 0 || (node = follow_node(tr, node, w, add))\n", "                    nothing\n"),
    m("TR3-L9 an attvar takes no number (KILL TW:1062: ATTVAR 1 instead of 2 after V1; TW:1066)",
      "                var_number += 1\n                push!(vl, p)\n", "                push!(vl, p)\n"),
    m("TR3-L10 the attribute list's location is not in vars (KILL TW:1066, 1119: vars == [.., ap]; the restore reads past the pair)",
      "                push!(vl, ap)\n", "                nothing\n"),
    m("TR3-L11 the attvar's cell keeps its word (KILL TW:1114: the second occurrence of f(Y, Y) opens it again; TP t82; TA a5)",
      "                ld.gstack[p] = w\n                node = follow_node(tr, node, w, add)\n", "                node = follow_node(tr, node, w, add)\n"),
    m("TR3-L12 the attvar is registered at the wrong depth (KILL TW:1062: no END key at all)",
      "                    push!(attvars, (compounds, p))\n", "                    push!(attvars, (compounds + 1, p))\n"),
    m("TR3-L13 a shared attvar's number is not followed (KILL TW:1114: the key after the END is missing; TP t82; TA a5, a15)",
      "            else                                                # a shared attvar\n                node = follow_node(tr, node, w, add)\n",
      "            else                                                # a shared attvar\n                nothing\n"),
    m("TR3-L14 the restore does not give the attvar's cell back (KILL TW:1067, 1075, 1119: ld.gstack[yp] == yw; TP t77 after the first lookup)",
      "            elseif tagex(c) == TAGEX_TRIE_ATTVAR\n", "            elseif false\n"),
    m("TR3-L15 the restore does not skip the attribute list's entry (KILL TW:1067: the attvar cell is rebuilt from the wrong location)",
      "                i += 1\n                ld.gstack[vp] = consPtr(vl[i], TAG_ATTVAR | STG_GLOBAL)", "                ld.gstack[vp] = consPtr(vl[i], TAG_ATTVAR | STG_GLOBAL)"),
    m("TR3-L16 an attvar opens its attribute list only without `add` (KILL TW:1062: the keys after ATTVAR are missing on an adding lookup)",
      "                node = follow_node(tr, node, w, add)\n                if node != 0\n                    attvars === nothing",
      "                node = follow_node(tr, node, w, add)\n                if node != 0 && !add\n                    attvars === nothing"),
    # ---- unify_key (TP t77-t86, TA a1-a17; no TW row has an attvar key: the oracle rows are the kill)
    m("TR3-U1 an attvar's first occurrence in read mode stays in read mode (EQUIVALENT)",
      "                st.write = true                                 # wait for the TAGEX_TRIE_ATTVAR_END key\n",
      "                nothing                                         # wait for the TAGEX_TRIE_ATTVAR_END key\n", targets=UT,
      eq="src/pl-trie.jl:1827-1836 (unify_key): the cells after the attvar key are the attribute list's, made fresh by allocGlobalCells! (:1827, every cell 0, an unbound variable), so a read-mode functor key meets an unbound variable (the `isVar` branch :1764-1771: write mode set there, `_bind_const!` of an untrailed fresh cell), an atom or integer key binds it (:1816-1818), an indirect key unifies it (:1810), a variable key records it (:1798-1803) and a repeated one unifies it with the recorded location (:1802), as write mode would write it; the mode returns to the saved one at the POP key (:1748-1751); only the trail differs (nothing is trailed: the cells are above the mark bar)"),
    m("TR3-U2 a functor key meeting an attvar does not enter write mode (EQUIVALENT)",
      "        elseif isAttVar(w)\n            st.write = true\n", "        elseif isAttVar(w)\n            nothing\n", targets=UT,
      eq="src/pl-trie.jl:1772-1779 (unify_key): the arguments of the new compound are fresh unbound cells (`allocGlobalNoShift` :1774 -> allocGlobalCells! src/pl-alloc.jl:166-169, setVar :193), so read-mode keys on them take the same bindings write mode writes, as TR3-U1 (:1764-1771 is the plain variable's branch, which sets write only for the same reason); the saved mode is restored at the POP key"),
    m("TR3-U3 a functor key meeting an attvar binds it without the wakeup (KILL TP:333 t79: the hook does not run; TA a1-a16 where an attvar is met)",
      "            assignAttVar(ld, pp, (DU_WORD, consPtr(t, TAG_COMPOUND | STG_GLOBAL), 0))\n",
      "            _bind_const!(ld, pp, consPtr(t, TAG_COMPOUND | STG_GLOBAL))\n", targets=UT),
    m("TR3-U4 the attvar's cell for later occurrences is the attribute list (KILL TP:336 t82, TA:185 a5: A == B)",
      "            st.attrs[index] = gp + 1\n", "            st.attrs[index] = gp + 2\n", targets=UT),
    m("TR3-U5 the first occurrence does not record the variable's location (KILL TP:336 t82, TA:185 a5: the second occurrence is a first again)",
      "            st.vars[index] = p\n            st.attrs[index] = gp + 1\n", "            st.attrs[index] = gp + 1\n", targets=UT),
    m("TR3-U6 a later occurrence in write mode refers to the term's location (KILL TW `_tr_unify_attvar_write_rows`: the two argument cells of f(Y, Y) built by unify_trie_term hold the same reference; no Prolog row sees a reference chain, TP t82 and TA a5 reach the line and survive it)",
      "            ld.gstack[p] = makeRefG(st.attrs[index])\n        else\n            unify_ptrs_cells(ld, st.vars[index], p) || return BOOLEX_FALSE\n",
      "            ld.gstack[p] = makeRefG(st.vars[index])\n        else\n            unify_ptrs_cells(ld, st.vars[index], p) || return BOOLEX_FALSE\n", targets=TT),
    m("TR3-U7 a later occurrence in read mode is not unified (KILL TA:187 a17: f(X, X) against f(2, 3) must fail)",
      "            unify_ptrs_cells(ld, st.vars[index], p) || return BOOLEX_FALSE\n        end\n    elseif tx == TAGEX_TRIE_ATTVAR_END\n",
      "            unify_ptrs_cells(ld, st.vars[index], p)\n        end\n    elseif tx == TAGEX_TRIE_ATTVAR_END\n", targets=UT),
    m("TR3-U8 the END key decides on the wrong test (KILL TP:339 t85, TA:186 a6, a7: the frozen goal does not run on 2, a 1 is not refused)",
      "            if k != DU_CELL\n                if (st.tr.flags & TRIE_ISTABLE) != 0\n",
      "            if k == DU_CELL\n                if (st.tr.flags & TRIE_ISTABLE) != 0\n", targets=UT),
    m("TR3-U9 the END key assigns the term's variable, not the new attvar (KILL TP:339 t85: hooked(b) does not run; TA:189 a16)",
      "                    assignAttVar(ld, st.attrs[index], (k, w, p2))\n", "                    assignAttVar(ld, st.vars[index], (k, w, p2))\n", targets=UT),
    m("TR3-U10 the END key unifies the attribute list with itself (KILL TP:340 t86, TA a1-a5: no attribute comes back)",
      "                unify_ptrs_cells(ld, st.attrs[index], st.vars[index]) || return BOOLEX_FALSE\n",
      "                unify_ptrs_cells(ld, st.attrs[index], st.attrs[index]) || return BOOLEX_FALSE\n", targets=UT),
    m("TR3-U11 the attvar's first occurrence leaves read mode unsaved (KILL TP:331-340, TA a1-a5: the POP key restores a wrong mode)",
      "            push!(st.astack, (p > 0 ? p + 1 : p, st.write))\n            gp = allocGlobalCells!(ld, 3)",
      "            push!(st.astack, (p > 0 ? p + 1 : p, true))\n            gp = allocGlobalCells!(ld, 3)", targets=UT),
    m("TR3-U12 find_var! does not grow attrs (KILL: a BoundsError in every attvar row, TP t79-t86, TA a1-a17)",
      "        push!(st.attrs, 0)\n", "        nothing\n", targets=UT),
]
