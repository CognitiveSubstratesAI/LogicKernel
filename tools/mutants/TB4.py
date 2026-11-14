# ORIGINAL: TB4's mutant list - no swipl-devel counterpart.
# tools/mutants/TB4.py - the mutation battery of TAB1 TB4 (WFS: delay infos, delay lists, simplification, answer completion, t_delay!, the ten WFS
# predicates; src/pl-tabling.jl blocks "TAB1 TB4: WFS and delays" and "TB4b", emptyStacks! in src/pl-setup.jl). Run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TB0.py): `id`, `file`, `old` (EXACTLY once in its file at wip/tb4 378c01b3, counted by a
# python3 -I script), `new`, optional `equivalent` and `targets`. NOT RUN: written edit-only on wip/tb4 (2026-11-10), nothing compiled or run. Every KILL below
# is PREDICTED from the code and the pinned rows (a row file the id names), never observed; the first hand-run replaces this header with the true verdicts.
# Each id names its KILL as `WF = test/core_lang/test_tabling_wfs_swipl.jl`: its first testset (WF:206-219) runs the rows `_WF_CASES` (WF:149-174) and compares
# each answer line with `_WF_PINNED` (WF:177-203) at `@test k == p` (WF:217), the row named by its id (wf01-wf05 the delay list alone, wf06-wf11 the type errors,
# wf20-wf33 the program `_WF_PROGRAM` WF:134-143); WF:209 is `ld.tabling.delay_list != 0`.
# STACK-ONLY KILLS: the rows wf20-wf33 call tabled goals, so they run only with TB1-TB5 AND the run-loop arm of T_DELAY stacked (TR4 declares the instruction;
# docs/architecture.md "TAB1 TB4", Stack edits). On wip/tb4 alone only wf01-wf11 and WF:209 can judge. Ids marked [STACK] are judged at the stack's mutation run.
# wf10 (TB4e, f72ca93d): the row pins swipl's `type_error(address, foo)` for `$tbl_force_truth_value(foo, true, C)` (pl-tabling.c:2378 PL_get_pointer_ex); the kernel
# now reads the pointer with `PL_get_pointer_ex` (src/pl-error.jl, pl-error.c:1335), which raises `address`; TB4-P7 below is the mutant on it (TARGETS: only TW runs it).
# DEFERRED KILLS (owner TB4-ROWS = the gate agent of TB4, who adds rows on the stack, pinning each from swipl 10.1.20): the code below runs only when a derivation
# is SIMPLIFIED or a table is abolished or a global delay list has two elements; none of the 25 rows does. Each names the row to add:
#   R5 two-element global list: `'$tbl_set_delay_list'([g,h]), '$tbl_add_global_delays'([a], D)` (the order g,h,a)
#   R6 non-empty global list and a [] argument: `'$tbl_set_delay_list'([g]), '$tbl_add_global_delays'([], D)`
#   R7 (WRITTEN: wf34, kills PD3) a body with two delayed goals `wz :- tnot(wp), tnot(wq).`: answer_residual(wz, B) = `(tnot wq,tnot wp)`
#   R8 (WRITTEN: wf35 kills PD4; wf36 `wd :- tnot(wp). wd :- tnot(wp).` kills S2) two derivations of one answer `wm :- tnot(wp). wm :- tnot(wq).`
#   R9 simplification to false `sa :- tnot(sb). sb :- tnot(sa). sb.`: `tm_yn(sa, R)` = no, `tm_yn(sb, R)` = yes   (propagate_to_answer, remove_conditional_answer, table_has_no_answers)
#   R10 simplification to true: a program of test_wfs.pl whose undefined answer becomes true when its negated goal fails; the row pins `tm_yn(p, R)` and `call_delays(p, D)` = true
#   R11 `'$tbl_set_answer_completed'(T)` then `'$tbl_is_answer_completed'(T)` on a table with a worklist, and on a complete one (`TRIE_COMPLETE`)
#   R12 `'$tbl_force_truth_value'(Ptr, true|false, C)` with Ptr the answer reference of a conditional answer (C = the count of simplified answers)
#   R14 an answer first conditional, then unconditional `wy :- tnot(wp). wy.`: call_delays(wy, D) = true   (update_delay_list's fast path and update_delay_list_any's nil/nil branch)
#   R15 a deleted or abolished table named in a delay (owner TB5, abolish rows): `_udl_undefined`, `answer_set_general_undefined`, DL_UNDEFINED_INFO
#   R16 `$tbl_wkl_negative/1`, `$tbl_wkl_is_false/1` on a negative worklist (owner TB2's rows at the stack: the same code as wip/tb2's)
#   R17 `$tbl_answer_update_dl/3` on a moded table (`:- table mp(_, lattice(or/3))`) (owner TB4-ROWS; its redo/cut path is TB3's `pl_tbl_answer_c4_va` pattern)
#   R19 put_delay_set's variable-sharing record and moded `Ret/ModeArgs` branches (TB4-PD rows; needs R18's program): `unify_delay_info` of a non-ground conditional answer
#   R18 a delay naming a non-ground answer (variable sharing): REC_DELAY slots, has_share_records, `ground_cells` (test_wfs.pl's non-ground conditional answers)
#   R13 answer completion: a positive loop `ac1 :- ac2. ac2 :- ac1, tnot(ac3). ac2 :- ac2b. ...` (test_wfs.pl's answer-completion programs): the positive-loop answer is false
TW = "test/core_lang/test_tabling_wfs_swipl.jl"
TV = "test/core_lang/test_tabling_variant_swipl.jl"     # TB1 (wip/tb1): the variant tables the WFS rows run through
TA = "test/core_lang/test_tabling_answers_swipl.jl"     # TB3 (wip/tb3): the answer predicates that call update_delay_list
TB = "test/db/test_boot_image_swipl.jl"                 # the boot-image count: a registration row removed changes 364
TM = "test/core_lang/test_tabling_min_swipl.jl"         # PL_predicates_from_tabling's table
TT = "test/core_lang/test_tabling_state_swipl.jl"       # TB0: DV_DELETED, DL_UNDEFINED, the freed lists
TR = "test/core_lang/test_tabling_tb4rows_swipl.jl"     # TB4K-b: the kill rows R5, R6, R9-R12 (groups of programs, one fresh database each)
TR2 = "test/core_lang/test_tabling_tb4rows2_swipl.jl"      # the kill rows R13-R18 (TB4K-c): answer completion, R14, R15 white-box, R16-R18
A1G = "test/core_lang/test_tabling_a1_guard.jl"         # TB4K-d: the white-box row of TB4-A1 (its recursion guard has no Prolog route)
TX = "test/core_lang/test_tabling_tb4_tb5_swipl.jl"   # TAB1 INT3 (wip/tab-int): the rows R9, R10, g13a, g13b that need TB5's `$tbl_destroy_table`: they kill TB4-S1, S3, S4, A2, A3
TARGETS = [TW, TV, TA, TB, TM, TT, TR, TR2, A1G, TX]        # every file a mutant lists
TAB = "src/pl-tabling.jl"
SET = "src/pl-setup.jl"
MUTANTS = [
    dict(id='TB4-D1 node_delayinfo tests the TN_DELAYINFO flag inverted (KILL WF:217 rows wf20-wf24, wf27, wf28, wf31, wf32 [STACK]: no conditional answer finds its delay info, every answer reads unconditional)',
         file=TAB, targets=[TW, TV, TA],
         old='    if (atrie.nodes[nid].flags & TN_DELAYINFO) != 0\n        return get(',
         new='    if (atrie.nodes[nid].flags & TN_DELAYINFO) == 0\n        return get('),
    dict(id='TB4-D2 set_node_delayinfo clears the flag instead of setting it (KILL wf20 [STACK]: the delay info is stored but node_delayinfo never sees the flag, `wp` reads unconditional, call_delays gives true)',
         file=TAB, targets=[TW, TV, TA],
         old='        n.flags |= TN_DELAYINFO\n',
         new='        n.flags &= ~TN_DELAYINFO\n'),
    dict(id='TB4-D3 set_node_delayinfo does not store the delay info (KILL wf20 [STACK]: the flag is set, the table has no entry, node_delayinfo answers nothing)',
         file=TAB, targets=[TW, TV, TA],
         old='        gd.tabling_answer_delay_infos[answer_ref(atrie.serial, nid)] = di\n',
         new='        nothing\n'),
    dict(id="TB4-D4 answer_is_conditional: a delay info with delay sets reads unconditional (KILL wf31, wf32 [STACK]: wv's answer is conditional, `$tbl_answer_update_dl` pushes nothing, the delay list stays [])",
         file=TAB, targets=[TW, TA],
         old='(di === DL_UNDEFINED_INFO || !isempty(di.delay_sets))',
         new='(di === DL_UNDEFINED_INFO || isempty(di.delay_sets))'),
    dict(id='TB4-D5 answer_ref without the shift, `serial | nid` (KILL TR rows r12a, r12b, r12d: the answer node handle of `$trie_gen_node` loses its serial, `$tbl_force_truth_value` cannot find the table; r12d holds forty conditional answers of two tries in a fresh database, each residual must name its own answer)',
         file=TAB, targets=[TW, TA, TR],
         old='@inline answer_ref(serial::Int, nid::Int)::Int = (serial << 32) | nid\n',
         new='@inline answer_ref(serial::Int, nid::Int)::Int = serial | nid\n'),
    dict(id='TB4-D6 answer_ref adds instead of ORs, `(serial << 32) + nid` (EQUIVALENT)',
         file=TAB, targets=[TW],
         old='@inline answer_ref(serial::Int, nid::Int)::Int = (serial << 32) | nid\n',
         new='@inline answer_ref(serial::Int, nid::Int)::Int = (serial << 32) + nid\n',
         equivalent="pl-tabling.jl:399 with :403: `answer_ref_node` masks 0xffffffff, so a node id at or above 2^32 could not be read back at all; a node id is an index into one trie's `nodes` vector (Int32 range in pl-trie.c's allocation), always below 2^32, so `|` and `+` agree on every value `answer_ref` is called with."),
    dict(id='TB4-D7 answer_ref_trie reads 31 bits, `r >> 31` (KILL wf20 [STACK]: t_delay! decodes its operand with answer_ref_trie, the trie of the answer is wrong, `gd.tries[...]` is another trie or out of range)',
         file=TAB, targets=[TW, TA],
         old='@inline answer_ref_trie(r::Int)::Int = r >> 32\n',
         new='@inline answer_ref_trie(r::Int)::Int = r >> 31\n'),
    dict(id='TB4-D8 answer_ref_node masks 16 bits (KILL TR row r12c: one conditional answer of a 40000-element list has a node id above 65535, `$tbl_force_truth_value` on it must count 1 and make it unconditional)',
         file=TAB, targets=[TW, TA, TR],
         old='@inline answer_ref_node(r::Int)::Int = r & 0xffffffff\n',
         new='@inline answer_ref_node(r::Int)::Int = r & 0xffff\n'),
    dict(id='TB4-P1 `$tbl_delay_list/1` unifies the whole `-(List)` term, not its argument (KILL WF:217 row wf01: swipl answers [], the mutant `-([])`; wf02, wf03 follow)',
         file=TAB, targets=[TW],
         old='return (_PL_get_arg(ld, 1, dl, a) && PL_unify(ld, A1, a)) ? FTRUE : FFALSE',
         new='return PL_unify(ld, A1, dl) ? FTRUE : FFALSE'),
    dict(id='TB4-P2 `$tbl_set_delay_list/1` unifies nothing (KILL wf02: the list stays [], swipl answers [x])',
         file=TAB, targets=[TW],
         old='        unify_vp(ld, p, -(A1 + 1))\n',
         new='        nothing\n'),
    dict(id='TB4-P3 `$tbl_add_global_delays/2` with an empty global list unifies A2 with the global list (KILL wf03: swipl gives [a], the mutant [])',
         file=TAB, targets=[TW],
         old='    if PL_get_nil(ld, dl)\n        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE',
         new='    if PL_get_nil(ld, dl)\n        return PL_unify(ld, A2, dl) ? FTRUE : FFALSE'),
    dict(id='TB4-P4 `$tbl_add_global_delays/2` builds the copy onto A2, not A1 (KILL wf04: swipl gives [g,a], the mutant [g|_])',
         file=TAB, targets=[TW],
         old='tail = PL_copy_term_ref(ld, A1)',
         new='tail = PL_copy_term_ref(ld, A2)'),
    dict(id="TB4-P5 `$tbl_add_global_delays/2` builds the copy forwards, the global list reversed (KILL TR row r05, r07: a global list of two and of three elements in front of the argument, wf04's has ONE element and cannot show a reversal; pinned [g,h,a], the mutant gives [h,g,a])",
         file=TAB, targets=[TW, TV, TR],
         old='        for i in length(heads):-1:1\n',
         new='        for i in 1:length(heads)\n'),
    dict(id="TB4-P6 `$tbl_add_global_delays/2` with a [] argument returns the global list's tail, A2 unified with A1 (KILL TR row r06: a one-element global list and a [] argument, pinned [g], the mutant gives [])",
         file=TAB, targets=[TW, TV, TR],
         old='    elseif PL_get_nil(ld, A1)\n        return PL_unify(ld, A2, dl) ? FTRUE : FFALSE',
         new='    elseif PL_get_nil(ld, A1)\n        return PL_unify(ld, A2, A1) ? FTRUE : FFALSE'),
    dict(id='TB4-I1 init_delay_list starts the list at 0 instead of [] (KILL wf01: `$tbl_delay_list` answers 0, swipl [])',
         file=TAB, targets=[TW],
         old='    PL_put_nil(ld, a)\n    PL_cons_functor_v(\n',
         new='    PL_put_integer(ld, a, 0)\n    PL_cons_functor_v(\n'),
    dict(id='TB4-I2 emptyStacks! leaves the delay list at 0 (KILL WF:209 `ld.tabling.delay_list != 0`, and wf01-wf05: every reader derefs 0)',
         file=SET, targets=[TW],
         old='    ld.tabling.delay_list = init_delay_list(ld)',
         new='    ld.tabling.delay_list = 0'),
    dict(id="TB4-I3 init_delay_list's wrapper functor is +/1, not -/1 (EQUIVALENT)",
         file=TAB, targets=[TW],
         old='mk_sym(T, :-)), 1), a\n',
         new='mk_sym(T, :+)), 1), a\n',
         equivalent="pl-tabling.jl:811-819 with :822-830, :832-840, :845-856, :864-880, :947-960: the wrapper is only ever read and written through `_PL_get_arg(ld, 1, dl, ...)` and `valPtr(w) + 1`; no reader tests its name or prints it, and no row prints the term (swipl's `-/1` is likewise only read through argTermP)."),
    dict(id="TB4-T1 t_delay! pushes a delay for an answer without a delay info (KILL wf40-wf43, testset `the compiled clause's T_DELAY` in TW: xa is compiled while undefined, then forced true WITHOUT touching its clause (wf41); swipl's call_delays through that clause is `true` and the delay list stays [] (wf42, wf43), the mutant pushes the dropped delay; wf23 never runs a T_DELAY: an unconditional answer gets none, pl-trie.c:5008-5010)",
         file=TAB, targets=[TW, TA],
         old='        (at.nodes[nid].flags & TN_DELAYINFO) == 0 && return nothing',
         new='        false && return nothing'),
    dict(id='TB4-T2 t_delay! names the nil atom instead of the answer trie (KILL wf20, wf24 [STACK]: the delay is `[]+Id`, call_delays cannot read it)',
         file=TAB, targets=[TW],
         old='        atrie = trie_symbol(gd, at)\n    else',
         new='        atrie = ld.atom_nil_w\n    else'),
    dict(id="TB4-T3 delay_to_data: a ground answer's data is 0, the negative delay (KILL wf20, wf24 [STACK]: wp's positive delay in wv reads `tnot(wp)`; wf32 reads `integer(D)` and does not see it)",
         file=TAB, targets=[TW],
         old='    elseif is_ground_trie_node(at, answer)\n        PL_put_integer(ld, out, trie_node_handle(at, answer))',
         new='    elseif is_ground_trie_node(at, answer)\n        PL_put_integer(ld, out, 0)'),
    dict(id="TB4-T4 delay_to_data: the negative delay's data is 1 (KILL wf45 and its white-box step, testset `the compiled clause's T_DELAY` in TW: answer 0 is reached only by t_delay! with a NULL node operand (set_trie_clause_general_undefined makes it so), delay `[]+0`; negative delays are plain `ATrie` elements built in unify_dependency and never go through delay_to_data, so wf20-wf22, wf27, wf28 cannot see it; wf45's expectation is hand-derived from pl-vmi.c:6240-6248 and pl-tabling.c:1660, swipl cannot be asked)",
         file=TAB, targets=[TW],
         old='    if answer == 0 || at === nothing\n        PL_put_integer(ld, out, 0)',
         new='    if answer == 0 || at === nothing\n        PL_put_integer(ld, out, 1)'),
    dict(id="TB4-U1 answer_update_delay_list pushes a delay for every answer (KILL wf33 [STACK]: ws(X)'s answers are unconditional, swipl's list stays []; wf33 reads the delay list INSIDE the findall, `S-DL` per answer: the old row read it after the findall, whose backtracking undoes the trailed list, so it could not fail)",
         file=TAB, targets=[TW],
         old='    if answer_is_conditional(gd, tr, nid)\n        tbl_push_delay(',
         new='    if true\n        tbl_push_delay('),
    dict(id="TB4-U2 TRIE_GEN_UPDATE_DL equals TRIE_GEN_DELAY_INFO (2) (KILL wf31 [STACK]: TR2's trie_gen_raw selects TB3's delay-info arm, not answer_update_delay_list)",
         file=TAB, targets=[TW, TA],
         old='const TRIE_GEN_UPDATE_DL = 4\n',
         new='const TRIE_GEN_UPDATE_DL = 2\n'),
    dict(id='TB4-U3 update_delay_list_any: a delay `A+Data` is not recognised (KILL wf20, wf24 [STACK]: type_error(delay_list, ...), the answer is not added)',
         file=TAB, targets=[TW, TA],
         old='elseif PL_is_functor(ld, h, mk_sym(T, :+), 2)',
         new='elseif PL_is_functor(ld, h, mk_sym(T, :*), 2)'),
    dict(id='TB4-U4 word_to_answer reads 0: a positive delay becomes negative (KILL wf24 [STACK]: wv :- wp, `call_delays(wv, D)` = wv in swipl)',
         file=TAB, targets=[TW, TA],
         old='word_to_answer(w::word)::Int = Int(valInt(w)) & 0xffffffff\n',
         new='word_to_answer(w::word)::Int = 0\n'),
    dict(id="TB4-U5 update_delay_list's fast path ignores an existing delay info (KILL TR2 group g14, rows r1401 + r1402: `wy :- tnot(r14p). wy.` pins call_delays `true` and answer_residual `[true]`; the mutant leaves the answer conditional on r14p)",
         file=TAB, targets=[TW, TA, TR2],
         old='    if PL_get_nil(ld, delays) && PL_get_nil(ld, gdl) &&\n        node_delayinfo(gd, atrie, answer) === nothing &&\n',
         new='    if PL_get_nil(ld, delays) && PL_get_nil(ld, gdl) &&\n'),
    dict(id='TB4-U6 `_udl_undefined` fails after setting the answer undefined (KILL TR2 white-box testset R15: the state is built by hand, `_udl_undefined(gd, tr, nid) == UDL_TRUE` and the node is DL_UNDEFINED_INFO; the Prolog route to this branch is not usable. The other effect of the mutant, the `udl == UDL_FALSE` return of update_delay_list, has no usable Prolog route and no row)',
         file=TAB, targets=[TW, TA, TR2],
         old='    set_node_delayinfo(gd, atrie, nid, DL_UNDEFINED_INFO)\n    return UDL_TRUE',
         new='    set_node_delayinfo(gd, atrie, nid, DL_UNDEFINED_INFO)\n    return UDL_FALSE'),
    dict(id='TB4-U7 update_delay_list_any: a variable-sharing delay is never recorded, `tshare` skipped (KILL TR2 group g18, rows r1801, r1803, r1804: g2(X) :- g1(X) over the conditional non-ground answer g1(f(_)); swipl shares the variable (`f(V0)-g1(f(V0))`, `shared`), the mutant leaves it apart)',
         file=TAB, targets=[TW, TA, TR2],
         old='            if !isempty(tshare)\n                n = length(tshare)',
         new='            if false\n                n = length(tshare)'),
    dict(id='TB4-S2 simplify_delay_set never finds a duplicate set (KILL wf36 in TW: `wd :- tnot(wp). wd :- tnot(wp).`, `answer_residual(wd, B)` gives swipl 10.1.20 ONE set `[tnot wp]`: simplify_delay_set pops the DUPLICATE set, the mutant keeps two; the earlier plan R8 (`wm`) has no equal delay sets and cannot kill it; the audit D-0635 table calls this R8 of TB4K-b, the row is written with wf34/wf35 in TB4K-a)',
         file=TAB, targets=[TW],
         old='        if equal_delay_set(di.delays, base, ds)\n',
         new='        if false\n'),
    dict(id="TB4-S5 table_has_no_answers: a table with answers reads empty (KILL the white-box testset `table_has_no_answers reads the value count (TB4-S5, white-box)`, the FIRST testset of TW: `value_count = 1` must read false; it fails in seconds and, as a top-level testset, stops the file before any program row runs: with the mutant the program rows would never end, simplify_component's Julia loop has no tick; classification: not a hang, a fail-fast)",
         file=TAB, targets=[TW],
         old='    atrie.value_count == 0 && return true\n',
         new='    atrie.value_count >= 0 && return true\n'),
    dict(id='TB4-S6 make_answer_unconditional does not count the answer, `agenda.done += 1` dropped (KILL TR row r12a, r12b: the count of `$tbl_force_truth_value/3` on an undefined pair, pinned 2 on both sides)',
         file=TAB, targets=[TW, TR],
         old='        agenda.done += 1\n        wl.undefined -= 1\n        isempty(wl.delays) || push_propagate(agenda, wl, answer_ref(at.serial, nid), true)',
         new='        wl.undefined -= 1\n        isempty(wl.delays) || push_propagate(agenda, wl, answer_ref(at.serial, nid), true)'),
    dict(id='TB4-S7 `$tbl_force_truth_value/3` swaps true and false (KILL TR rows r12a, r12b: forcing true makes the answer unconditional and removes the other answer of the pair, forcing false the mirror image; wf10 raises before the branch)',
         file=TAB, targets=[TW, TR],
         old='                rc = if truth\n                    make_answer_unconditional(gd, agenda, atrie, answer)\n                else\n                    remove_conditional_answer(gd, agenda, atrie, answer)\n',
         new='                rc = if truth\n                    remove_conditional_answer(gd, agenda, atrie, answer)\n                else\n                    make_answer_unconditional(gd, agenda, atrie, answer)\n'),
    dict(id='TB4-A1 answer_completion runs inside answer completion (KILL WHITE-BOX, test_tabling_a1_guard.jl first testset: no Prolog route found in ~1050 programs; white-box. With `in_answer_completion` set and a candidate worklist the guarded call returns true and keeps the flag; the mutant calls the candidate: the flag is reset and the call answers false (the hand-built trie has no variant) or raises)',
         file=TAB, targets=[TW, TR2, A1G],
         old='    ld.tabling.in_answer_completion && return true',
         new='    false && return true'),
    dict(id="TB4-C1a `$tbl_is_answer_completed/1` reads a worklist's flag inverted (KILL wf30 [STACK] when wp's table still holds a worklist: swipl answers no; of C1a/C1b exactly one is judged by wf30, the other DEFERRED KILL TB4-ROWS R11)",
         file=TAB, targets=[TW],
         old='        wl isa worklist && return wl.answer_completed ? FTRUE : FFALSE\n',
         new='        wl isa worklist && return wl.answer_completed ? FFALSE : FTRUE\n'),
    dict(id="TB4-C1b `$tbl_is_answer_completed/1` reads TRIE_COMPLETE inverted (KILL wf30 [STACK]: wf30 = r(no, yes, yes) over wp, wu, ws(_): wu and ws(_) are TRIE_COMPLETE without a worklist (`yes`, the branch this mutant inverts), wp has a worklist and reads `no` (the other branch); the old row held only wp; the pair rule of C1a)",
         file=TAB, targets=[TW],
         old='        return (tr.flags & TRIE_COMPLETE) != 0 ? FTRUE : FFALSE\n',
         new='        return (tr.flags & TRIE_COMPLETE) != 0 ? FFALSE : FTRUE\n'),
    dict(id='TB4-C2 `$tbl_set_answer_completed/1` sets the flag false (KILL TR row r11a: inside its own evaluation the table has a worklist, set then is gives no then yes, the mutant stays no)',
         file=TAB, targets=[TW, TR],
         old='            wl.answer_completed = true\n',
         new='            wl.answer_completed = false\n'),
    dict(id="TB4-W1 `$tbl_wkl_is_false/1` ORs where upstream ANDs (KILL TR2 white-box testset R16: the four (neg_delayed, has_answers) states built by hand; (true, true) and (false, false) answer FTRUE under the OR, no program run through the pin reaches them)",
         file=TAB, targets=[TW, TR2],
         old='        return (wl.neg_delayed && !wl.has_answers) ? FTRUE : FFALSE',
         new='        return (wl.neg_delayed || !wl.has_answers) ? FTRUE : FFALSE'),
    dict(id='TB4-W2 `$tbl_answer_update_dl/3` takes the redo path on the first call (KILL TR2 group g17, rows r1701-r1704: the moded answers below a bound skeleton of a max and a lattice table, once/1 and the delay list; the first call must look the skeleton up)',
         file=TAB, targets=[TW, TR2],
         old='    if PL_foreign_control(PL__ctx) != FRG_FIRST_CALL   # FRG_CUTTED: clear_trie_gen_state(CTX_PTR); FRG_REDO\n        return trie_gen_raw(ld, nothing, 0, A3, 0, A3, TRIE_GEN_UPDATE_DL, PL__ctx)',
         new='    if PL_foreign_control(PL__ctx) == FRG_FIRST_CALL   # FRG_CUTTED: clear_trie_gen_state(CTX_PTR); FRG_REDO\n        return trie_gen_raw(ld, nothing, 0, A3, 0, A3, TRIE_GEN_UPDATE_DL, PL__ctx)'),
    dict(id='TB4-P7 PL_get_pointer_ex raises type_error(integer, T) like PL_get_int64_ex (KILL WF:217 row wf10: swipl 10.1.20 raises type_error(address, foo))',
         file="src/pl-error.jl", targets=[TW],
         old='    PL_error(ld, ERR_TYPE, mk_sym(T, :address), t)',
         new='    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)'),
    # ---- put_delay_set / unify_delay_info's delay-list loop (pl-tabling.c:6952-7097; TAB1 stack batch 3, item d). PREDICTED kills, never observed [STACK]: the rows
    # wf27 (`answer_residual(wp, B)` = `tnot(wq)`) and wf28 (the residual program) reach the negative delay and a single delay set through `$tbl_answer`/3.
    dict(id='TB4-PD1 put_delay_set: a negative delay is not wrapped in tnot/1 (KILL WF:217 rows wf27, wf28 [STACK]: the residual body reads `wq`, the pin is `tnot(wq)`)',
         file=TAB, targets=[TW, TA],
         old='            PL_cons_functor(ld, c1, tnot1, c1) || return false\n',
         new='            nothing\n'),
    dict(id='TB4-PD2 put_delay_set: the first delay is joined too, `count >= 0` (KILL WF:217 row wf27 [STACK]: the condition of the single delay is `,(tnot(wq), tnot(wq))`)',
         file=TAB, targets=[TW, TA],
         old='        if count > 0                                    # count++ > 0\n            PL_cons_functor(ld, cond, FUNCTOR_comma2, c1, cond) || return false\n',
         new='        if count >= 0                                   # count++ > 0\n            PL_cons_functor(ld, cond, FUNCTOR_comma2, c1, cond) || return false\n'),
    dict(id='TB4-PD3 put_delay_set: the delays of one set are joined by `;`, FUNCTOR_semicolon2 for FUNCTOR_comma2 (KILL wf34 in TW: `wz :- tnot(wp), tnot(wq).` and `answer_residual(wz, B)` give swipl 10.1.20 `[(tnot wq,tnot wp)]`; the mutant joins the two delays of the set by `;`. SURVIVOR of the TB4 battery, the earlier EQUIVALENT claim withdrawn, audit D-0635 item 4)',
         file=TAB, targets=[TW, TA],
         old='            PL_cons_functor(ld, cond, FUNCTOR_comma2, c1, cond) || return false\n',
         new='            PL_cons_functor(ld, cond, FUNCTOR_semicolon2, c1, cond) || return false\n'),
    dict(id='TB4-PD4 unify_delay_info: two delay sets are joined by `,`, FUNCTOR_comma2 for FUNCTOR_semicolon2 (KILL wf35 in TW: `wm :- tnot(wp). wm :- tnot(wq).` and `answer_residual(wm, B)` give swipl 10.1.20 `[(tnot wq;tnot wp)]`; the mutant joins the two delay sets by `,`. SURVIVOR of the TB4 battery, the earlier EQUIVALENT claim withdrawn, audit D-0635 item 4)',
         file=TAB, targets=[TW, TA],
         old='                    PL_cons_functor_v(ld, cond, FUNCTOR_semicolon2, av) || return false\n',
         new='                    PL_cons_functor_v(ld, cond, FUNCTOR_comma2, av) || return false\n'),
    # TB4-S1, S3, S4, A2, A3 were OPEN SURVIVORS at batch 3 (D-0659/D-0660): their rows run answer completion to its end, whose cleanup calls TB5's
    # `'$tbl_destroy_table'/1`, absent from batch 3's tree. On wip/tab-int (TB5 present) the rows are in TX = test_tabling_tb4_tb5_swipl.jl and the
    # mutants carry targets=[TW, TX]: real kills, judged by the integration battery (TAB1 INT3). Not judged yet.
    dict(id='TB4-S1 add_to_delay_set does not count an active delay (KILL TX group SIMP rows r09a-r09d, r10a-r10c, wip/tab-int with the TB5 builtin `$tbl_destroy_table/1`: rows r09a-r09d, r10a-r10c: `ds.active` reaches 0 at the first removed member, the answer turns unconditional too early; the model of the stale-delay program and `sb :- tnot(sa). sb.` with sa false)',
         file=TAB, targets=[TW, TX],
         old='    variant != 0 && (ds.active += UInt32(1))\n',
         new='    variant != 0 && (ds.active += UInt32(0))\n'),
    dict(id='TB4-S3 propagate_to_answer: a true result removes the conjunction (KILL TX group SIMP rows r10a, r10b, wip/tab-int with the TB5 builtin `$tbl_destroy_table/1`: rows r10a, r10b: `k10 :- tnot(n10).` with n10 ending without an answer, call_delays(k10, true) pinned yes)',
         file=TAB, targets=[TW, TX],
         old='                        if res                                  # remove member from conjunction',
         new='                        if !res                                 # remove member from conjunction'),
    dict(id='TB4-S4 simplify_component stops after one pass (KILL TX group SIMP row r09a, wip/tab-int with the TB5 builtin `$tbl_destroy_table/1`: row r09a: the stale-delay program a..f called from f needs several passes of simplify_component, pinned model a,f true and b..e false)',
         file=TAB, targets=[TW, TX],
         old='        (count == 0 || undefined == 0) && break\n',
         new='        break\n'),
    dict(id='TB4-A2 is_ac_candidate_wl asks only `wl.undefined != 0` (KILL TX group G13A rows r1301 + r1302, wip/tab-int with the TB5 builtin `$tbl_destroy_table/1`: group g13a, rows r1301 + r1302: a prolog_wrap counter on the answer completion pins ONE call for the program, the mutant also calls it on the worklists already marked answer completed)',
         file=TAB, targets=[TW, TX],
         old='    if wl.undefined != 0 && !wl.answer_completed && !isempty(wl.delays)\n',
         new='    if wl.undefined != 0\n'),
    dict(id='TB4-A3 has_positive_dl counts a negative delay (KILL TX group G13B rows r1303 + r1304, wip/tab-int with the TB5 builtin `$tbl_destroy_table/1`: group g13b, rows r1303 + r1304: the same counter pins ZERO calls for a program whose delays are all negative, the mutant calls the answer completion)',
         file=TAB, targets=[TW, TX],
         old='                    d.answer != 0 && return true\n',
         new='                    return true\n'),
]
