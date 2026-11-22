# ORIGINAL: FL1B's mutant list — no swipl-devel counterpart.
# tools/mutants/FL1B.py — the mutation battery of FL1b (audit D-0550), refit onto the Nov-22 source (wip/late-flag-2): pl-flag.c's
# get_flag/2 and set_flag/2 (src/pl-flag.jl) and their registration table. Run ONCE, in CI (.github/workflows/mutation.yml;
# locally tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. KILL: test/db/test_flag_swipl.jl (rows fg01-fg31 against the pin's swipl, and the LK-ONLY table
# testset). No other test file calls get_flag/2 or set_flag/2 (grep over test/ at the writing), so TARGETS is that file and the
# type-discipline test. The old list's current_flag/1 mutants (FL1B-q .. FL1B-v, FL1B-x) and the flags_order one (FL1B-c) are
# not here: pl_current_flag is not ported on this line. Not run (edit-only step): re-check the `old` strings after `warm.sh fmt`.
FG = "test/db/test_flag_swipl.jl"
TF = [FG]
TARGETS = TF + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/pl-flag.jl"
MUTANTS = [
    # ── pl-flag.c lookupFlag (lookupFlagEntry) ──
    dict(id="FL1B-a lookupFlagEntry: a new flag starts at 1, not 0 (KILL fg01, the LK-ONLY table row)",
         file=P, targets=TF,
         old="FLG_INTEGER, mk_sym(T, :none), Int64(0), 0.0)",
         new="FLG_INTEGER, mk_sym(T, :none), Int64(1), 0.0)"),
    dict(id="FL1B-b lookupFlagEntry: an existing flag is not found, each call makes a new one (KILL fg02, fg03)",
         file=P, targets=TF,
         old="    of === nothing || return of\n",
         new="    of === nothing\n"),
    # ── pl-flag.c get_flag ──
    dict(id="FL1B-d get_flag: an atom flag unifies the integer 0 (KILL fg02, fg05)",
         file=P, targets=TF,
         old="PL_unify_atom(ld, value, f.a) ",
         new="PL_unify_int64(ld, value, 0) "),
    dict(id="FL1B-e get_flag: an integer flag unifies 0 (KILL fg03, fg06)",
         file=P, targets=TF,
         old="PL_unify_int64(ld, value, f.i)",
         new="PL_unify_int64(ld, value, 0)"),
    dict(id="FL1B-f get_flag: a float flag unifies 0.0 (KILL fg04)",
         file=P, targets=TF,
         old="PL_unify_float(ld, value, f.f)",
         new="PL_unify_float(ld, value, 0.0)"),
    # ── pl-flag.c set_flag ──
    dict(id="FL1B-g set_flag: an atom value keeps the old type (KILL fg05)",
         file=P, targets=TF,
         old="f.type = FLG_ATOM ",
         new="f.type = FLG_INTEGER "),
    dict(id="FL1B-h set_flag: an integer value keeps the old type (KILL fg06)",
         file=P, targets=TF,
         old="f.type = FLG_INTEGER ",
         new="nothing "),
    dict(id="FL1B-i set_flag: a float value keeps the old type (KILL fg07)",
         file=P, targets=TF,
         old="f.type = FLG_FLOAT ",
         new="nothing "),
    dict(id="FL1B-j set_flag: no limit at the tagged range, any Int64 is stored (KILL fg18, fg19, fg29, fg31, the LK-ONLY w_big)",
         file=P, targets=TF,
         old="n.type === V_INTEGER && PLMINTAGGEDINT <= n.i <= PLMAXTAGGEDINT",
         new="n.type === V_INTEGER"),
    dict(id="FL1B-k set_flag: the lower bound of the tagged range is exclusive (KILL fg30)",
         file=P, targets=TF,
         old="PLMINTAGGEDINT <= n.i",
         new="PLMINTAGGEDINT < n.i"),
    dict(id="FL1B-l set_flag: the upper bound of the tagged range is exclusive (KILL fg28, the LK-ONLY w_max)",
         file=P, targets=TF,
         old="n.i <= PLMAXTAGGEDINT",
         new="n.i < PLMAXTAGGEDINT"),
    dict(id="FL1B-m set_flag: an integer beyond the range answers true, no representation_error (KILL fg08, fg18, the LK-ONLY w_big)",
         file=P, targets=TF,
         old="return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int64_t))",
         new="return true"),
    dict(id="FL1B-m2 set_flag: an Int64 beyond the range is not an integer error, it falls to the type error (KILL fg18, fg19, fg29, fg31)",
         file=P, targets=TF,
         old="n.type === V_MPZ || n.type === V_INTEGER",
         new="n.type === V_MPZ"),
    dict(id="FL1B-n set_flag: a float is a type error (KILL fg04, fg07)",
         file=P, targets=TF,
         old="elseif n.type === V_FLOAT ",
         new="elseif false "),
    dict(id="FL1B-o set_flag: a refused value fails without the type_error (KILL fg09, fg10, fg11)",
         file=P, targets=TF,
         old="return PL_error(ld, \"flag\", 3, \"\", ERR_TYPE, mk_sym(T, :flag_value), value)",
         new="return false"),
    dict(id="FL1B-p set_flag: the type error names flag, not flag_value (KILL fg09, fg10, fg11)",
         file=P, targets=TF,
         old="mk_sym(T, :flag_value), value)",
         new="mk_sym(T, :flag), value)"),
    # ── registration ──
    dict(id="FL1B-w get_flag/2 runs set_flag's function (KILL fg01, fg02)",
         file=P, targets=TF,
         old="PL_extension(\"get_flag\", 2, pl_get_flag2_va, PL_FA_VARARGS)",
         new="PL_extension(\"get_flag\", 2, pl_set_flag2_va, PL_FA_VARARGS)"),
]
