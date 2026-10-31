# ORIGINAL: G1's mutant list — no swipl-devel counterpart.
# tools/mutants/G1.py — the mutation battery of G1 (global variables: pl-gvar.c setval, setval_duplicate, getval,
# auto_define_gvar, is_gval, nb_delete/1, nb_current/2; the table entries; D7 `_release_frozen!` honouring `gvar_grefs`;
# D8 `user:exception/3` dynamic from the start; pl-copyterm.c duplicate_term), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_gvar_swipl.jl (rows g01-g57 and the h9 database named
# in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are single-line anchors written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding
# agent had no daemon): RE-FIT any that fmt re-flows at the first battery run (mutate_drive.py refuses a string that does not
# occur exactly once). Every `old` was counted once in the source at wip/g1 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * `w == old && return true` in gvar_setval: assigning the value a variable already holds changes no answer (the nb branch
#     re-stores the same word and re-counts `gvar_grefs` symmetrically; the b branch trails an assignment of the same word).
#   * `ensureGlobalSpace(ld, 3) || return false`: the overflow path needs a full global stack; the rows never reach it.
#   * `_gvar_on_global`'s `|| _is_vword(w)` (flag b) and nb_delete's `gvar_grefs -= 1`: a float, string or big number counted
#     or not changes `gvar_grefs` only, which no row observes but the positive-counter test; recorded as a gap for a later
#     white-box row, not as equivalent.
#   * the `ld.exception_term != 0` early return after a hook error in gvar_getval: no row has a hook that throws.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code: the step's own file first.
# Global variables are named by test_gvar_swipl.jl alone; `_release_frozen!` runs at the end of every outermost query that
# threw (test_exception.jl, test_catch_swipl.jl, test_cleanup_swipl.jl, test_findall_swipl.jl, test/foreign/test_query.jl);
# duplicate_term/2 is named by test_copyterm_swipl.jl and test_copyterm_cells.jl; the table and
# `setBuiltinPredicateProperties!` are exercised by every database (the step's file and test_query.jl stand for them).
TG = ["test/core_lang/test_gvar_swipl.jl"]
TF = TG + [
    "test/core_lang/test_exception.jl", "test/core_lang/test_catch_swipl.jl", "test/core_lang/test_cleanup_swipl.jl",
    "test/core_lang/test_findall_swipl.jl", "test/foreign/test_query.jl"
]
TD = TG + ["test/core_lang/test_copyterm_swipl.jl", "test/core_lang/test_copyterm_cells.jl"]
TX = TG + ["test/foreign/test_query.jl"]
TARGETS = TG + TF[1:] + TD[1:]   # the baseline's (mutate_ci.py plan reads TARGETS)
G = "src/pl-gvar.jl"
MUTANTS = [
    # ── pl-gvar.c setval ──
    dict(id="G1-S1 b_setval does not trail the assignment: backtracking keeps the new value (KILL g11, g14, g43, g55)",
         file=G, targets=TG,
         old="TrailAssignment!(ld, p)",
         new="nothing"),
    dict(id="G1-S2 b_setval does not freeze the global stack below the value cell (KILL g10-g14, g43)",
         file=G, targets=TG,
         old="freezeGlobal!(ld)                       # The value location must be preserved",
         new="nothing"),
    dict(id="G1-S3 b_setval keeps the plain old word in the table, not a reference to the new cell (KILL g12, g14)",
         file=G, targets=TG,
         old="ld.gvar_nb_vars[name] = makeRefG(p)     # updateHTable(…, makeRefG(p))",
         new="ld.gvar_nb_vars[name] = old"),
    dict(id="G1-S4 nb_setval does not copy the value: it links it (KILL g17, g56)",
         file=G, targets=TG,
         old="w = setval_duplicate(ld, w, old)",
         new="w = w"),
    dict(id="G1-S5 nb_setval does not store the new word (KILL g01, g02, g38)",
         file=G, targets=TG,
         old="ld.gvar_nb_vars[name] = w                   # updateHTable(…, w)",
         new="nothing"),
    dict(id="G1-S6 a variable value is stored as its word, not as a reference to its cell: no sharing (KILL g07, g09, g18, g49)",
         file=G, targets=TG,
         old="if k == DU_CELL || k == DU_ATTVAR               # canBind(w)",
         new="if false"),
    dict(id="G1-S7 setval_duplicate copies a compound but not an attributed variable (KILL g42)",
         file=G, targets=TG,
         old="if _is_gcompound(new) || word_is_attvar(ld, new)",
         new="if _is_gcompound(new)"),
    # ── pl-gvar.c getval, auto_define_gvar, is_gval ──
    dict(id="G1-G1 getval takes a `retry` answer as `error`: the defined variable is not read (KILL g44, g48)",
         file=G, targets=TG,
         old="elseif action == gvar_retry",
         new="elseif false"),
    dict(id="G1-G2 getval tries once, not twice (KILL g44, g48)", file=G, targets=TG,
         old="for i in 0:1",
         new="for i in 0:0"),
    dict(id="G1-G3 the hook is called with another event name (KILL g44, g45, g46, g47, g48)", file=G, targets=TG,
         old="mk_sym(T, :undefined_global_variable)",
         new="mk_sym(T, :undefined_variable)"),
    dict(id="G1-G4 the hook's `fail` answer is read as `retry` (KILL g45)", file=G, targets=TG,
         old="elseif text == \"fail\"",
         new="elseif false"),
    dict(id="G1-G5 is_gval takes every word for a value: a deleted or backtracked-away variable is read (KILL g11, g22, g57)",
         file=G, targets=TG,
         old="return w != _gvar_no_value(ld)",
         new="return true"),
    # ── pl-gvar.c nb_delete, nb_current ──
    dict(id="G1-D1 nb_delete leaves the value (KILL g22, g57)", file=G, targets=TG,
         old="ld.gvar_nb_vars[name] = no_value    # updateHTable(…, ATOM_no_value)",
         new="nothing"),
    dict(id="G1-C1 nb_current enumerates a key without a value (KILL g57)", file=G, targets=TG,
         old="(val != 0 && is_gval(ld, val)) || continue",
         new="val != 0 || continue"),
    dict(id="G1-C2 nb_current of a compound key fails instead of raising (KILL g34)", file=G, targets=TG,
         old="return PL_type_error(ld, \"atom\", A1) ? FTRUE : FFALSE",
         new="return FFALSE"),
    # ── the table ──
    dict(id="G1-T1 nb_linkval is registered as nb_setval (KILL g16, g18)", file="src/pl-gvar.jl", targets=TG,
         old="PL_extension(\"nb_linkval\", 2, pl_nb_linkval2_va, PL_FA_VARARGS)",
         new="PL_extension(\"nb_linkval\", 2, pl_nb_setval2_va, PL_FA_VARARGS)"),
    dict(id="G1-T2 nb_current is registered deterministic (KILL g19, g21, g52, g53)", file="src/pl-gvar.jl", targets=TG,
         old="PL_FA_NONDETERMINISTIC | PL_FA_VARARGS)",
         new="PL_FA_VARARGS)"),
    # ── D7, D8, duplicate_term ──
    dict(id="G1-R1 _release_frozen! frees the frozen region while global variables hold values (KILL g04, g06)",
         file="src/pl-inline.jl", targets=TF,
         old="ld.exception_term != 0 || ld.gvar_grefs > 0) &&",
         new="ld.exception_term != 0) &&"),
    dict(id="G1-E1 user:exception/3 is not made dynamic before init.pl: the hook call raises an existence error (KILL h9)",
         file="src/pl-ext.jl", targets=TX,
         old="setDynamicDefinition!(exception3.definition, true)",
         new="nothing"),
    dict(id="G1-P1 duplicate_term copies an attributed variable as a plain variable (KILL g42)",
         file="src/pl-copyterm.jl", targets=TD,
         old="return copy_term_refs(ld, in, copy, cp_options(COPY_ATTRS))",
         new="return copy_term_refs(ld, in, copy, cp_options(0x00))"),
]
