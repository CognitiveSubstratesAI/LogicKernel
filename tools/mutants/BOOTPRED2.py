# ORIGINAL: BOOTPRED's mutant list — no swipl-devel counterpart.
# tools/mutants/BOOTPRED2.py — the mutation battery of BOOTPRED (audit D-0281): `'$garbage_collect'/1` (pl-gc.c
# pl_garbage_collect), thread_self/1 (pl-thread.c pl_thread_self), with_mutex/2 (pl-mutex.c pl_with_mutex) and, in the
# groups written later, the six pl-dict.c predicates. Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_bootpred_swipl.jl (rows bp01-bp128 named in
# each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in its file at the commit that adds this list (a text count, no Julia).
# TARGETS (audit D-0238): test_bootpred_swipl.jl is the only test file that names these predicates (no other test file
# calls thread_self, with_mutex or '$garbage_collect'), so it is the whole list. The dict mutants (pl-dict.c, rows bp27-bp126)
# are killed by the same file; the two registration mutants also list test/foreign/test_builtins_swipl.jl, the one other test
# file that walks the dispatch tables (_FOREIGN_VA). The pl-dict.jl `old` strings were checked to occur once (text count).
TB = ["test/core_lang/test_bootpred_swipl.jl"]
TARGETS = TB
GC = "src/pl-gc.jl"
TH = "src/pl-thread.jl"
MX = "src/pl-mutex.jl"
EXT = "src/pl-ext.jl"
DI = "src/pl-dict.jl"
TX = TB + ["test/foreign/test_builtins_swipl.jl"]
MUTANTS = [
    # ── pl-gc.c pl_garbage_collect ──
    dict(id="BOOTPRED-G1 '$garbage_collect'/1 fails (KILL bp20-bp26)", file=GC, targets=TB,
         old="function pl_garbage_collect(ld::PL_local_data{T}, d::term_t)::foreign_t where {T}\n    return FTRUE\n",
         new="function pl_garbage_collect(ld::PL_local_data{T}, d::term_t)::foreign_t where {T}\n    return FFALSE\n"),
    dict(id="BOOTPRED-G2 '$garbage_collect' registered under another name: '$garbage_collect'(0) is unknown (KILL bp20-bp26)",
         file=EXT, targets=TB,
         old='    PL_extension("\\$garbage_collect", 1, pl_garbage_collect, 0x00),',
         new='    PL_extension("\\$garbage_collectx", 1, pl_garbage_collect, 0x00),'),
    # ── pl-thread.c pl_thread_self ──
    dict(id="BOOTPRED-T1 thread_self/1 answers another atom (KILL bp01, bp02, bp04, bp06-bp08)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return PL_unify_atom(ld, self, mk_sym(T, :other)) ? FTRUE : FFALSE\n"),
    dict(id="BOOTPRED-T2 thread_self/1 inverts its verdict: the unification result is negated (KILL bp01, bp03)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FFALSE : FTRUE\n"),
    dict(id="BOOTPRED-T3 thread_self/1 succeeds without unifying (KILL bp03, bp05)", file=TH, targets=TB,
         old="    return PL_unify_atom(ld, self, mk_sym(T, :main)) ? FTRUE : FFALSE\n",
         new="    return FTRUE\n"),
    # ── pl-mutex.c pl_with_mutex ──
    dict(id="BOOTPRED-M1 with_mutex/2 calls the mutex term instead of the goal (KILL bp09-bp16, bp19)", file=MX, targets=TB,
         old="    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)\n",
         new="    rval = callProlog(_query_gd(ld), ld, 0, mutex, PL_Q_PASS_EXCEPTION)\n"),
    dict(id="BOOTPRED-M2 with_mutex/2 does not pass the goal's exception on (KILL bp12, bp18)", file=MX, targets=TB,
         old="    rval = callProlog(_query_gd(ld), ld, 0, goal, PL_Q_PASS_EXCEPTION)\n",
         new="    rval = callProlog(_query_gd(ld), ld, 0, goal, 0)\n"),
    dict(id="BOOTPRED-M3 with_mutex/2 always succeeds (KILL bp11, bp15)", file=MX, targets=TB,
         old="    return rval ? FTRUE : FFALSE\n",
         new="    return FTRUE\n"),
    # The registration flag alone is not the mutation: PL_meta_predicate(with_mutex/2, "+0") (pl-ext.jl, the meta table; pl-proc.jl
    # isTransparentMetamask) sets P_TRANSPARENT from the mask, so dropping PL_FA_TRANSPARENT at PL_extension changes nothing (probe, audit D-0283).
    # The mask `0` -> `+` makes with_mutex/2 non-transparent: the goal runs in `system` (probe: bp17 user -> system, bp127 lists -> system).
    dict(id="BOOTPRED-M4 with_mutex/2 is not transparent: its meta spec has no 0 argument, the goal runs in the context of system (KILL bp17, bp127, bp128)",
         file=EXT, targets=TB,
         old='("with_mutex", 2, "+0")',
         new='("with_mutex", 2, "++")'),
    # ── pl-dict.c (src/pl-dict.jl) ──
    dict(id="BOOTPRED-D1 dict_lookup_ptr's binary search goes the wrong way: a key past the middle is not found (KILL bp62, bp72, bp78, bp97, bp98)",
         file=DI, targets=TB,
         old="        if p < name\n            l = m + 1\n",
         new="        if p > name\n            l = m + 1\n"),
    dict(id="BOOTPRED-D2 dict_ordered reports a descending key pair as ordered: dict_create/3 keeps [b,a] unsorted (KILL bp46)",
         file=DI, targets=TB,
         old="            elseif n1 > n2\n                ordered = PL_DICT_FALSE\n",
         new="            elseif n1 < n2\n                ordered = PL_DICT_FALSE\n"),
    dict(id="BOOTPRED-D3 dict_ordered finds a duplicate key where the keys differ (KILL bp27, bp35, bp36, bp89)",
         file=DI, targets=TB,
         old="            if n1 == n2\n                if want_dupl\n",
         new="            if n1 != n2\n                if want_dupl\n"),
    dict(id="BOOTPRED-D4 put_dict merges the two runs in the wrong order: the old key and the new key swap places (KILL bp80, bp82, bp95, bp96)",
         file=DI, targets=TB,
         old="        elseif i_name < n_name\n            push!(plan, (false, ip, i_name))\n",
         new="        elseif i_name > n_name\n            push!(plan, (false, ip, i_name))\n"),
    dict(id="BOOTPRED-D5 put_dict does not notice a changed value of an equal key: the old dict is returned (KILL bp81, bp94, bp98)",
         file=DI, targets=TB,
         old="compareStandard_cells(ld, nv, ip, true) != 0",
         new="compareStandard_cells(ld, nv, ip, true) == 0"),
    dict(id="BOOTPRED-D6 put_dict returns the old dict when it WAS modified (KILL bp81, bp94)",
         file=DI, targets=TB,
         old="        if !modified\n            return dict\n        end\n        while ip < ip_end\n",
         new="        if modified\n            return dict\n        end\n        while ip < ip_end\n"),
    dict(id="BOOTPRED-D7 select_dict gives up at a key of From before the next key of Select (KILL bp101, bp111)",
         file=DI, targets=TB,
         old="        elseif d < f\n            return word(0)\n",
         new="        elseif d > f\n            return word(0)\n"),
    dict(id="BOOTPRED-D8 select_dict's rest forgets the skipped keys of From that sort before the last selected key (KILL bp111)",
         file=DI, targets=TB,
         old="            if fin >= fe || (keep !== nothing && keep[i + 1])\n",
         new="            if fin >= fe\n"),
    dict(id="BOOTPRED-D9 select_dict's rest has the tag dict, not dyndict (KILL bp107, bp112)",
         file=DI, targets=TB,
         old="        ld.gstack[out + 1] = ATOM_dyndict\n",
         new="        ld.gstack[out + 1] = ATOM_dict\n"),
    dict(id="BOOTPRED-D10 unify_tags accepts a dyndict tag only if both are: a rest cannot be the From of a later select (KILL bp117)",
         file=DI, targets=TB,
         old="    if w1 == ATOM_dyndict || w2 == ATOM_dyndict\n",
         new="    if w1 == ATOM_dyndict && w2 == ATOM_dyndict\n"),
    dict(id="BOOTPRED-D11 is_dict/2 does not unify the tag (KILL bp58, bp60, bp119)", file=DI, targets=TB,
         old="return unify_ptrs_cells(ld, f + 1, -(A2 + 1)) ? FTRUE : FFALSE",
         new="return FTRUE"),
    dict(id="BOOTPRED-D12 get_dict/3 with an unbound key starts at the second pair (KILL bp64, bp65, bp75, bp79)",
         file=DI, targets=TB,
         old="        if k == DU_CELL || k == DU_ATTVAR           # canBind(*np)\n            i = 1\n",
         new="        if k == DU_CELL || k == DU_ATTVAR           # canBind(*np)\n            i = 3\n"),
    dict(id="BOOTPRED-D13 get_dict/3 on backtracking skips a pair (KILL bp64, bp65, bp75)",
         file=DI, targets=TB,
         old="        i = PL_foreign_context(PL__ctx) + 2\n",
         new="        i = PL_foreign_context(PL__ctx) + 4\n"),
    dict(id="BOOTPRED-D14 get_dict/3 leaves a choice point after the last pair (KILL bp118)",
         file=DI, targets=TB,
         old="                if i + 2 < arity\n",
         new="                if i + 2 <= arity\n"),
    dict(id="BOOTPRED-D15 get_dict/3 raises no type error for a key that is neither an atom nor an integer (KILL bp70, bp71)",
         file=DI, targets=TB,
         old='            if !ex\n                PL_type_error(ld, "dict-key", A1)\n',
         new='            if ex\n                PL_type_error(ld, "dict-key", A1)\n'),
    dict(id="BOOTPRED-D16 dict_create/3 does not bind the caller's tag variable to the dict's tag cell (KILL bp119)",
         file=DI, targets=TB,
         old="_bind_const!(ld, cp, makeRefG(ap))  # Trail(cp, makeRefG(ap))",
         new="nothing  # Trail(cp, makeRefG(ap))"),
    dict(id="BOOTPRED-D17 select_dict/3 is registered under another name (KILL bp101-bp117)", file=DI, targets=TX,
         old='    PL_extension("select_dict", 3, pl_select_dict3_va, PL_FA_VARARGS)',
         new='    PL_extension("select_dictx", 3, pl_select_dict3_va, PL_FA_VARARGS)'),
    dict(id="BOOTPRED-D18 put_dict/3 is registered with is_dict/2's function (KILL bp80-bp100)", file=DI, targets=TX,
         old='    PL_extension("put_dict", 3, pl_put_dict3_va, PL_FA_VARARGS),',
         new='    PL_extension("put_dict", 3, pl_select_dict3_va, PL_FA_VARARGS),'),
    # assign_in_dict links the OLDER of the cell and the value variable as the representative (upstream's direction rule): the standard order
    # of the variable against others follows its address (D-0260). Audit D-0283: not equivalent; bp120-bp126 compare/3 the value
    # variable against one created between it and the new cell.
    dict(id="BOOTPRED-D19 assign_in_dict links the older variable to the new cell: the value variable takes the standard-order place of the new cell (KILL bp120-bp126)",
         file=DI, targets=TB,
         old="        if dp < q\n",
         new="        if dp > q\n"),
]
