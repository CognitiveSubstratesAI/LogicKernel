# PORT: pl-prims.c setarg, setarg_t (the mutant list of SETARG; swipl-devel cbf4e1896275).
# tools/mutants/SETARG.py — the mutation battery of SETARG (setarg/3, nb_setarg/3, nb_linkarg/3: pl-prims.c setarg's
# trail/duplicate/link/freeze branches, unify_vp, may_share_in_duplicate, setarg_t's argument checks, the predicate
# table; pl-copyterm.c duplicate_term's nshare/share: share_for_duplicate, mark_for_duplicate), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by
# test/core_lang/test_setarg_swipl.jl (rows sa01-sa83 named in each id's KILL). Verdicts: written by the battery, not
# yet run. 27 mutants, 2 EQUIVALENT (A5, E4), each with its file:line reason.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps at the first battery run (mutate_drive.py refuses a string that does not occur
# exactly once). Every `old` was checked to occur exactly once in the source at wip/setarg (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * `ensureGlobalSpace(ld, 1)` before the trailed assignment: the call changes behaviour only at the global-stack
#     limit, a state no row reaches.
#   * `_value_word!` in `unify_vp`: a slot's side value never occurs as a Prolog goal's argument, so the branch is read
#     by no row.
#   * the three identical `A1, A2, A3 = ...` argument lines of the three predicates: one mutant per line would repeat
#     D2-D4's kill rows.
# TARGETS (audit D-0238): the step's own file first (a run stops at the first target that decides). The pl-prims.jl
# mutants run test_setarg_swipl.jl only (the only file naming setarg/3, nb_setarg/3 or nb_linkarg/3); the pl-copyterm.jl
# mutants (duplicate_term, the cp_options struct, mark_for_duplicate_cells) also run the files that exercise
# duplicate_term/2 and the copy: test_copyterm_swipl.jl, test_copyterm_cells.jl, test_catch_swipl.jl (the ball is
# copied through copy_term_refs), test_exception.jl, test_same_term_swipl.jl (s_dup) and
# test_attvar_wakeup.jl (duplicate_term/2 on an attributed variable).
TS = ["test/core_lang/test_setarg_swipl.jl"]
TCOPY = TS + [
    "test/core_lang/test_copyterm_swipl.jl",
    "test/core_lang/test_copyterm_cells.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_exception.jl",
    "test/core_lang/test_same_term_swipl.jl",       # duplicate_term/2 shares nothing (s_dup)
    "test/core_lang/test_attvar_wakeup.jl",         # duplicate_term/2 copies an attributed variable
]
TARGETS = TCOPY      # the baseline's (mutate_ci.py plan reads TARGETS)
P = "src/pl-prims.jl"
C = "src/pl-copyterm.jl"
MUTANTS = [
    dict(id="SETARG-A1 the old argument is not trailed: setarg/3 is not undone on backtracking (KILL sa03, sa05, sa06, sa41, sa70)",
         file=P, targets=TS,
         old="        TrailAssignment!(ld, apos)\n",
         new="        nothing\n"),
    dict(id="SETARG-A2 a variable argument is not unified with the value: the call succeeds and assigns nothing (KILL sa07-sa14)",
         file=P, targets=TS,
         old="            return unify_ptrs_cells(ld, -(value + 1), apos)\n",
         new="            return true\n"),
    dict(id="SETARG-A3 the branch test is inverted: nb_setarg/3 trails and setarg/3 does not (KILL sa03, sa05, sa40, sa41)",
         file=P, targets=TS,
         old="    if (flags & SETARG_BACKTRACKABLE) != 0\n",
         new="    if (flags & SETARG_BACKTRACKABLE) == 0\n"),
    dict(id="SETARG-A4 the last argument is out of range: argn >= arity fails (KILL sa02, sa04, sa49, sa60)",
         file=P, targets=TS,
         old="(argn == 0 || argn > arity) && return false",
         new="(argn == 0 || argn >= arity) && return false"),
    dict(id="SETARG-A5 setarg_t lets argument 0 through to setarg(), which refuses it as well (EQUIVALENT)",
         file=P, targets=TS,
         old="(argn === nothing || argn == 0) && return false",
         new="argn === nothing && return false",
         equivalent="src/pl-prims.jl `setarg`: its own `argn == 0 ||` test returns false for the same input, so the predicates' answer is unchanged (upstream has both tests too, pl-prims.c:2831 and :2896); only a direct caller of `setarg` sees the difference, and there is none"),
    dict(id="SETARG-A6 the type error names another type: type_error(callable, T) (KILL sa23, sa25, sa26, sa27, sa32, sa37)",
         file=P, targets=TS,
         old="PL_error(ld, ERR_TYPE, mk_sym(T, :compound), term)",
         new="PL_error(ld, ERR_TYPE, mk_sym(T, :callable), term)"),
    dict(id="SETARG-B1 a compound value is never duplicated: nb_setarg/3 links as nb_linkarg/3 (KILL sa54, sa59, sa60, sa76)",
         file=P, targets=TS,
         old="if kv == DU_WORD && (flags & SETARG_LINK) == 0",
         new="if kv == DU_WORD && false"),
    dict(id="SETARG-B2 nb_linkarg/3 duplicates its value too (KILL sa55)",
         file=P, targets=TS,
         old="if kv == DU_WORD && (flags & SETARG_LINK) == 0",
         new="if kv == DU_WORD"),
    dict(id="SETARG-B3 the global stack is never frozen: nb_setarg/3's value is freed by the undo (KILL sa43-sa47, sa82, sa83)",
         file=P, targets=TS,
         old="    freeze && freezeGlobal!(ld)\n",
         new="    nothing\n"),
    dict(id="SETARG-B4 only compounds freeze: a float, string or big integer value is lost by the undo (KILL sa44, sa45, sa46)",
         file=P, targets=TS,
         old="(kv == DU_VALUE && (_is_vword(wv) || _is_side_word(wv)))",
         new="false"),
    dict(id="SETARG-B5 an attributed variable value does not freeze: its cell is freed by the undo (KILL sa82)",
         file=P, targets=TS,
         old="|| kv == DU_ATTVAR ||",
         new="|| false ||"),
    dict(id="SETARG-B6 the old argument's compound is not offered for sharing: nshare is 0 (KILL sa56, sa57, sa58)",
         file=P, targets=TS,
         old="nshare = keep != 0 ? 1 : 0",
         new="nshare = 0"),
    dict(id="SETARG-B7 may_share_in_duplicate stores no compound in the new reference: nothing is shared (KILL sa56, sa57, sa58)",
         file=P, targets=TS,
         old="        ld.slots[share + 1] = w ",
         new="        ld.slots[share + 1] = word(0) "),
    dict(id="SETARG-C1 a variable value binds the other way round: the younger is not linked to the older (KILL sa12, sa79, sa80, sa81)",
         file=P, targets=TS,
         old="        if v < vp\n",
         new="        if v > vp\n"),
    dict(id="SETARG-C2 an attributed variable value is stored as a plain value word, not as a reference to it (KILL sa68, sa69, sa72, sa82)",
         file=P, targets=TS,
         old="    elseif k == DU_ATTVAR                                   # else if ( isAttVar(*val) )\n",
         new="    elseif false\n"),
    dict(id="SETARG-D1 SETARG_LINK is SETARG_BACKTRACKABLE: nb_linkarg/3 is undone on backtracking (KILL sa51, sa55)",
         file=P, targets=TS,
         old="const SETARG_LINK = UInt32(0x2)",
         new="const SETARG_LINK = UInt32(0x1)"),
    dict(id="SETARG-D2 nb_linkarg/3 passes no flag: it duplicates and does not link (KILL sa55)",
         file=P, targets=TS,
         old="return setarg_t(ld, A1, A2, A3, SETARG_LINK) ? FTRUE : FFALSE",
         new="return setarg_t(ld, A1, A2, A3, UInt32(0)) ? FTRUE : FFALSE"),
    dict(id="SETARG-D3 setarg/3 passes no flag: it is nb_setarg/3 (KILL sa03, sa05, sa53)",
         file=P, targets=TS,
         old="return setarg_t(ld, A1, A2, A3, SETARG_BACKTRACKABLE) ? FTRUE : FFALSE",
         new="return setarg_t(ld, A1, A2, A3, UInt32(0)) ? FTRUE : FFALSE"),
    dict(id="SETARG-D4 nb_setarg/3 is registered with nb_linkarg/3's code (KILL sa54, sa56-sa60)",
         file=P, targets=TS,
         old="PL_extension(\"nb_setarg\", 3, pl_nb_setarg3_va, PL_FA_VARARGS)",
         new="PL_extension(\"nb_setarg\", 3, pl_nb_linkarg3_va, PL_FA_VARARGS)"),
    dict(id="SETARG-D5 setarg/3 is registered under another name: every setarg row is undefined (KILL sa01-sa27)",
         file=P, targets=TS,
         old="PL_extension(\"setarg\", 3, pl_setarg3_va, PL_FA_VARARGS)",
         new="PL_extension(\"setarg_\", 3, pl_setarg3_va, PL_FA_VARARGS)"),
    dict(id="SETARG-E1 a shared term is never recognised: the share loop tests inequality (KILL sa56, sa57, sa58)",
         file=C, targets=TCOPY,
         old="_is_gcompound(w) && valPtr(w) == c && return true",
         new="_is_gcompound(w) && valPtr(w) != c && return true"),
    dict(id="SETARG-E2 the share loop skips the first term: with one shared term nothing is shared (KILL sa56, sa57, sa58)",
         file=C, targets=TCOPY,
         old="for i in 0:(options.nshare - 1)",
         new="for i in 1:(options.nshare - 1)"),
    dict(id="SETARG-E3 a shared term is marked visited, not ground: it is copied (KILL sa56, sa57, sa58)",
         file=C, targets=TCOPY,
         old="ld.gstack[c] = f | FIRST_MASK           # set_ground(t->definition)",
         new="ld.gstack[c] = f | MARK_MASK            # set_ground(t->definition)"),
    dict(id="SETARG-E4 the share test is run even for nshare 0 (EQUIVALENT)",
         file=C, targets=TCOPY,
         old="if options.nshare != 0 && share_for_duplicate_cells(ld, c, options)",
         new="if share_for_duplicate_cells(ld, c, options)",
         equivalent="src/pl-copyterm.jl `share_for_duplicate_cells`: its loop `0:(options.nshare - 1)` is empty for nshare 0 and returns false, the same answer as the short-circuit (upstream's `options->nshare &&` is the same optimisation, pl-copyterm.c:228)"),
    dict(id="SETARG-E5 the copy is run without the options: mark_for_duplicate shares nothing (KILL sa56, sa57, sa58)",
         file=C, targets=TCOPY,
         old="mark_for_duplicate_cells(ld, src, fl, options)\n",
         new="mark_for_duplicate_cells(ld, src, fl)\n"),
    dict(id="SETARG-E6 duplicate_term passes nshare 0 to the copy (KILL sa56, sa57, sa58)",
         file=C, targets=TCOPY,
         old="cp_options(COPY_ATTRS, nshare, share))",
         new="cp_options(COPY_ATTRS, 0, share))"),
    dict(id="SETARG-E7 duplicate_term copies without attributes: an attributed variable becomes plain (KILL sa72, sa83)",
         file=C, targets=TCOPY,
         old="cp_options(COPY_ATTRS, nshare, share))",
         new="cp_options(0, nshare, share))"),
]
