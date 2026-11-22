# ORIGINAL: DICTSET's mutant list — no swipl-devel counterpart.
# tools/mutants/DICTSET.py — the mutation battery of DICT-SET: the pl-dict.c predicates b_set_dict/3, nb_set_dict/3 and
# nb_link_dict/3 written on wip/dict-set in src/pl-dict.jl (setdict, the three pl_*_va entries and their registration) — run ONCE, in
# CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as tools/mutants/DICT.py): `id`,
# `file`, `old` (must occur EXACTLY once), `new`, `targets`; no `equivalent` field. Every id names the rows that aim at it
# (test/core_lang/test_dict_set_swipl.jl, rows t0-t31 of test_dict_set_swipl.pl); the battery's verdicts are written by the battery,
# not by this file.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT
# any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur exactly
# once in src/pl-dict.jl at the wip/dict-set tip (a text count, no Julia).
# Candidate equivalent: the `|| SETARG_LINK` on b_set_dict's flags is not listed: with SETARG_BACKTRACKABLE set, setarg reads the link
# bit only in the branch the flag leaves; needs the widened run and the audit's ruling.
# NOT LISTED: the `m === nothing && return false` and `k === nothing && return false` lines (their removal reaches dict_lookup_ptr
# with `nothing`: a Julia MethodError, not a verdict the rows read).
# TARGETS (audit D-0238): the step's own file first, then test_type_discipline.jl (the three term types). test_dict_preds_swipl.jl
# names these predicates only in a comment, so it does not exercise the mutated code.
TS = "test/core_lang/test_dict_set_swipl.jl"
TT = "test/test_type_discipline.jl"
TARGETS = [TS, TT]
D = "src/pl-dict.jl"
MUTANTS = [
    # ── setdict ──
    dict(id="DICTSET-S1 setdict assigns the KEY cell of the pair (argument 2*m+1) instead of the value cell: aimed by t0, t1, t2, t29, t31", file=D, targets=TARGETS,
         old="        return setarg(ld, r[2] * 2, dict, value, flags)\n",
         new="        return setarg(ld, r[2] * 2 + 1, dict, value, flags)\n"),
    dict(id="DICTSET-S2 setdict assigns argument m (the pair's index) instead of 2*m: aimed by t0, t2, t29, t30, t31", file=D, targets=TARGETS,
         old="        return setarg(ld, r[2] * 2, dict, value, flags)\n",
         new="        return setarg(ld, r[2], dict, value, flags)\n"),
    dict(id="DICTSET-S3 setdict checks the key before the dict: a bad key and a bad dict raise the key's error: aimed by t27", file=D, targets=TARGETS,
         old="    m = get_dict_ex(ld, dict, true)\n    m === nothing && return false\n    k = get_name_ex(ld, key)\n    k === nothing && return false\n",
         new="    k = get_name_ex(ld, key)\n    k === nothing && return false\n    m = get_dict_ex(ld, dict, true)\n    m === nothing && return false\n"),
    dict(id="DICTSET-S4 setdict fails silently on a missing key, no existence_error: aimed by t23, t24", file=D, targets=TARGETS,
         old="    PL_existence_error3(ld, mk_sym(T, :key), key, dict)\n    return false\n",
         new="    return false\n"),
    dict(id="DICTSET-S5 setdict's existence_error names the dict as the key and the key as the dict: aimed by t23, t24", file=D, targets=TARGETS,
         old="    PL_existence_error3(ld, mk_sym(T, :key), key, dict)\n",
         new="    PL_existence_error3(ld, mk_sym(T, :key), dict, key)\n"),
    dict(id="DICTSET-S6 setdict's existence_error names the type dict instead of key: aimed by t23, t24", file=D, targets=TARGETS,
         old="    PL_existence_error3(ld, mk_sym(T, :key), key, dict)\n",
         new="    PL_existence_error3(ld, mk_sym(T, :dict), key, dict)\n"),
    dict(id="DICTSET-S7 setdict asks get_dict_ex for no error: a non-dict fails instead of raising the type error: aimed by t25, t27", file=D, targets=TARGETS,
         old="    m = get_dict_ex(ld, dict, true)\n",
         new="    m = get_dict_ex(ld, dict, false)\n"),
    # ── the three entries ──
    dict(id="DICTSET-E1 b_set_dict assigns without the trail (flags 0): the assignment survives backtracking: aimed by t4, t7, t8, t9, t19, t20, t21", file=D, targets=TARGETS,
         old="    ok = setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE)\n",
         new="    ok = setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0))\n"),
    dict(id="DICTSET-E2 nb_set_dict links the value instead of duplicating it: a later binding shows in the dict: aimed by t12, t13, t15, t17, t18", file=D, targets=TARGETS,
         old="    return setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE\n",
         new="    return setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK) ? FTRUE : FFALSE\n"),
    dict(id="DICTSET-E3 nb_link_dict duplicates the value instead of linking it: a later binding does not show in the dict: aimed by t13, t15, t17, t18", file=D, targets=TARGETS,
         old="    return setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK) ? FTRUE : FFALSE\n",
         new="    return setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE\n"),
    dict(id="DICTSET-E4 b_set_dict assigns the key argument as the value: aimed by t0, t1, t3, t10", file=D, targets=TARGETS,
         old="    ok = setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE)\n",
         new="    ok = setdict(ld, PL__t0, PL__t0 + 1, PL__t0, SETARG_BACKTRACKABLE)\n"),
    dict(id="DICTSET-E5 nb_set_dict swaps the dict and the value arguments: aimed by t0, t1, t25", file=D, targets=TARGETS,
         old="    return setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE\n",
         new="    return setdict(ld, PL__t0, PL__t0 + 2, PL__t0 + 1, UInt32(0)) ? FTRUE : FFALSE\n"),
    # ── the registration ──
    dict(id="DICTSET-R1 b_set_dict is registered with nb_set_dict's function: aimed by t4, t7, t8, t9, t19, t20, t21", file=D, targets=TARGETS,
         old='    PL_extension("b_set_dict", 3, pl_b_set_dict3_va, PL_FA_VARARGS),\n',
         new='    PL_extension("b_set_dict", 3, pl_nb_set_dict3_va, PL_FA_VARARGS),\n'),
    dict(id="DICTSET-R2 nb_link_dict is registered with nb_set_dict's function: aimed by t13, t15, t17, t18", file=D, targets=TARGETS,
         old='    PL_extension("nb_link_dict", 3, pl_nb_link_dict3_va, PL_FA_VARARGS),\n',
         new='    PL_extension("nb_link_dict", 3, pl_nb_set_dict3_va, PL_FA_VARARGS),\n'),
    dict(id="DICTSET-R3 nb_set_dict is registered under the arity 4: the arity-3 call is undefined: aimed by t0, t1, t2, t3, t5, t7, t9", file=D, targets=TARGETS,
         old='    PL_extension("nb_set_dict", 3, pl_nb_set_dict3_va, PL_FA_VARARGS),\n',
         new='    PL_extension("nb_set_dict", 4, pl_nb_set_dict3_va, PL_FA_VARARGS),\n'),
]
