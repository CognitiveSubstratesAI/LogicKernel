# ORIGINAL: DICTREC's mutant list — no swipl-devel counterpart.
# tools/mutants/DICTREC.py — the mutation battery of DICT-REC (the three UPSTREAM commits of wip/dict-rec): pl-dict.c
# b_set_dict/3, nb_set_dict/3, nb_link_dict/3 (setdict, src/pl-dict.jl), pl-btree.c $btree_find_node/5 (src/pl-btree.jl) and pl-write.c
# $needs_quotes/1 (src/pl-write.jl) — run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as DICT.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Aimed at test/core_lang/test_dictrec_swipl.jl (rows dr01-dr131 and the LK-ONLY rows lkb1-lkb3, named in each id's "aimed by").
# Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT
# any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur exactly
# once in its file on the replay base (wip/dictset-replay, d089172d + the DICT-SET commits; a text count, python3 -I, no Julia).
# NOT LISTED (each with its reason):
#   * the `a === nothing && return FFALSE` of pl_needs_quotes1_va (a non-atom): PL_get_atom_ex has already raised the error, and what
#     the kernel does with `true` returned over a pending exception is not something a row can name, so a mutant gives no verdict.
#   * the non-term check of btree_find_node itself: with the check gone the search reads a non-compound's cells, a read no row can
#     answer for (DICTREC-B14 aims at the error's type name instead).
# TARGETS (audit D-0238): every mutant lists every test file that exercises its mutated code: the step's own file first, then
# test_dict_preds_swipl.jl (the dict cells these setters write: get_dict, put_dict and dict_pairs are its rows) and
# test_type_discipline.jl (the three term types). No other file calls b_set_dict/3, nb_set_dict/3, nb_link_dict/3,
# $btree_find_node/5 or $needs_quotes/1 on the kernel (a text search of test/ found only the two rows files).
TR = "test/core_lang/test_dictrec_swipl.jl"
TS = "test/core_lang/test_dict_set_swipl.jl"
TD = "test/core_lang/test_dict_preds_swipl.jl"
TT = "test/test_type_discipline.jl"
TARGETS = [TR, TD, TT]
TARGETS_S = [TR, TS, TD, TT]    # setdict is also DICT-SET's: test_dict_set_swipl.jl exercises it
D = "src/pl-dict.jl"
B = "src/pl-btree.jl"
W = "src/pl-write.jl"
MUTANTS = [
    # ── pl-dict.c setdict, b_set_dict, nb_set_dict, nb_link_dict ──
    dict(id="DICTREC-S1 setdict assigns the KEY cell of the pair (argument arg*2+1), not its value (aimed by dr01, dr02, dr20)", file=D, targets=TARGETS_S,
         old="return setarg(ld, r[2] * 2, dict, value, flags)",
         new="return setarg(ld, r[2] * 2 + 1, dict, value, flags)"),
    dict(id="DICTREC-S2 b_set_dict/3 is not backtrackable: the assignment survives `fail` (aimed by dr03, dr05, dr16)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE)",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0))"),
    dict(id="DICTREC-S3 b_set_dict/3 links without trailing: the assignment survives `fail` (aimed by dr03, dr05)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE)",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK)"),
    dict(id="DICTREC-S4 nb_set_dict/3 is backtrackable: `fail` undoes it (aimed by dr22, dr33)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE) ? FTRUE : FFALSE"),
    dict(id="DICTREC-S5 nb_set_dict/3 links the value instead of duplicating it: the caller's variable is shared (aimed by dr31, dr32)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK) ? FTRUE : FFALSE"),
    dict(id="DICTREC-S6 nb_link_dict/3 duplicates the value: the caller's variable is no longer shared (aimed by dr47, dr48)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK) ? FTRUE : FFALSE",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, UInt32(0)) ? FTRUE : FFALSE"),
    dict(id="DICTREC-S7 nb_link_dict/3 is backtrackable: `fail` undoes it (aimed by dr39)", file=D, targets=TARGETS_S,
         old="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_LINK) ? FTRUE : FFALSE",
         new="setdict(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, SETARG_BACKTRACKABLE) ? FTRUE : FFALSE"),
    dict(id="DICTREC-S8 setdict checks the key before the dict: a bad key and a non-dict raise the key's error (aimed by dr129, dr130, dr131)", file=D, targets=TARGETS_S,
         old="    m = get_dict_ex(ld, dict, true)\n    m === nothing && return false\n    k = get_name_ex(ld, key)\n    k === nothing && return false\n",
         new="    k = get_name_ex(ld, key)\n    k === nothing && return false\n    m = get_dict_ex(ld, dict, true)\n    m === nothing && return false\n"),
    dict(id="DICTREC-S9 the missing-key error names `value` as the thing missing (aimed by dr06, dr24, dr40)", file=D, targets=TARGETS_S,
         old="PL_existence_error3(ld, mk_sym(T, :key), key, dict)",
         new="PL_existence_error3(ld, mk_sym(T, :value), key, dict)"),
    # ── pl-btree.c btree_find_node ──
    dict(id="DICTREC-B1 the left and right argument positions are swapped: a smaller key goes right (aimed by dr54, dr55, dr67, dr68)", file=B, targets=TARGETS,
         old="Int(smaller ? lp : rp)",
         new="Int(smaller ? rp : lp)"),
    dict(id="DICTREC-B2 `smaller` is inverted: the comparison's direction is flipped (aimed by dr54, dr55, dr59, dr60, dr67)", file=B, targets=TARGETS,
         old="smaller = d == CMP_LESS",
         new="smaller = d != CMP_LESS"),
    dict(id="DICTREC-B3 the key position is read from bits 8-15 (the left position) instead of 16-23 (aimed by dr51, dr64, dr80)", file=B, targets=TARGETS,
         old="kp = (UInt32((p >> 16) & 0xff) - UInt32(1))",
         new="kp = (UInt32((p >> 8) & 0xff) - UInt32(1))"),
    dict(id="DICTREC-B4 the right position is decoded without the -1 (an argument number, not an index) (aimed by dr55, dr57, dr68)", file=B, targets=TARGETS,
         old="rp = (UInt32(p & 0xff) - UInt32(1))",
         new="rp = (UInt32(p & 0xff) - UInt32(0))"),
    dict(id="DICTREC-B5 the left position is decoded without the -1 (aimed by dr54, dr56, dr67)", file=B, targets=TARGETS,
         old="lp = (UInt32((p >> 8) & 0xff) - UInt32(1))",
         new="lp = (UInt32((p >> 8) & 0xff) - UInt32(0))"),
    dict(id="DICTREC-B6 the right position is not checked against the arity (aimed by dr95, lkb2)", file=B, targets=TARGETS,
         old="if arity <= Int(kp) || arity <= Int(lp) || arity <= Int(rp)",
         new="if arity <= Int(kp) || arity <= Int(lp)"),
    dict(id="DICTREC-B7 the left position is not checked against the arity (aimed by dr97, lkb1)", file=B, targets=TARGETS,
         old="if arity <= Int(kp) || arity <= Int(lp) || arity <= Int(rp)",
         new="if arity <= Int(kp) || arity <= Int(rp)"),
    dict(id="DICTREC-B8 the key position is not checked against the arity (aimed by dr96, lkb3)", file=B, targets=TARGETS,
         old="if arity <= Int(kp) || arity <= Int(lp) || arity <= Int(rp)",
         new="if arity <= Int(lp) || arity <= Int(rp)"),
    dict(id="DICTREC-B9 a child with another functor is searched on: the functor check is dropped (aimed by dr61, dr62)", file=B, targets=TARGETS,
         old="|| ld.gstack[valPtr(nw)] != fd   # !isTerm(*n) || f->definition != fd",
         new="|| false   # !isTerm(*n) || f->definition != fd"),
    dict(id="DICTREC-B10 the node reported is always the root: the cell holding the current node is not updated (aimed by dr52, dr53, dr54, dr65)", file=B, targets=TARGETS,
         old="        tloc = argpos                                       # t = n\n",
         new="        nothing\n"),
    dict(id="DICTREC-B11 a found key reports `<` instead of `=` (aimed by dr51, dr52, dr58, dr64)", file=B, targets=TARGETS,
         old="PL_unify_atom(ld, A5, mk_sym(T, :(=)))",
         new="PL_unify_atom(ld, A5, mk_sym(T, :<))"),
    dict(id="DICTREC-B12 a miss on the smaller side reports `>` and on the larger side `<` (aimed by dr54, dr55, dr59, dr60)", file=B, targets=TARGETS,
         old="mk_sym(T, smaller ? :< : :>)",
         new="mk_sym(T, smaller ? :> : :<)"),
    dict(id="DICTREC-B13 the `=` answer is given for a SMALLER key, and an equal key searches on to the right (aimed by dr51, dr54, dr59, dr67)", file=B, targets=TARGETS,
         old="        if d == CMP_EQUAL\n",
         new="        if d == CMP_LESS\n"),
    dict(id="DICTREC-B14 the type error of a non-term names `tree` (aimed by dr88, dr91, dr93, dr94, dr95)", file=B, targets=TARGETS,
         old="return PL_error(ld, ERR_TYPE, mk_sym(T, :btree), A2)\n    end\n    fpos",
         new="return PL_error(ld, ERR_TYPE, mk_sym(T, :tree), A2)\n    end\n    fpos"),
    dict(id="DICTREC-B15 the right position may equal the arity (a position past the compound is no longer refused) (aimed by lkb2)", file=B, targets=TARGETS,
         old="arity <= Int(lp) || arity <= Int(rp)",
         new="arity <= Int(lp) || arity < Int(rp)"),
    dict(id="DICTREC-B16 the left position may equal the arity (aimed by lkb1)", file=B, targets=TARGETS,
         old="arity <= Int(kp) || arity <= Int(lp)",
         new="arity <= Int(kp) || arity < Int(lp)"),
    dict(id="DICTREC-B17 the key position may equal the arity (aimed by lkb3)", file=B, targets=TARGETS,
         old="if arity <= Int(kp) ||",
         new="if arity < Int(kp) ||"),
    # ── pl-write.c $needs_quotes/1 ──
    dict(id="DICTREC-Q1 $needs_quotes/1 answers the opposite (aimed by dr100, dr101, dr104, dr105)", file=W, targets=TARGETS,
         old="return unquoted_atom(a) ? FFALSE : FTRUE                # return !unquoted_atom(a)",
         new="return unquoted_atom(a) ? FTRUE : FFALSE                # return !unquoted_atom(a)"),
]
