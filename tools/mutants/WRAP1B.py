# ORIGINAL: WRAP1B's mutant list — no swipl-devel counterpart.
# tools/mutants/WRAP1B.py — the mutation battery of WRAP1B (B5b): the ONE `freeCodesDefinition!(gd, def, do_linger)` of src/pl-supervisor.jl
# (the 2-argument method, which refused a wrapped predicate, is gone; every caller passes `gd`) and the callers of src/pl-proc.jl that
# reach its wrapped branch: `setDetDefinition!`, `resetProcedure!`, `abolishProcedure!`, `redefineProcedure`. Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY
# once), `new`, optional `equivalent` and `targets`.
# NOT RUN YET (written edit-only on wip/wrap1-freecodes, 2026-11-22, nothing compiled). Every KILL below is read off the rows of
# test/core_lang/test_tabling_tb5wrap_swipl.jl (TW; its rows are pinned on swipl 18168e62) and test/core_lang/test_tabling_min_swipl.jl
# (TM; rows tmc01-tmc07 and the white-box `_tm_wrapped` testset) by the code reading; marked (U) = the battery decides, nothing ran.
# THE ROWS OF TW (a wrapped predicate: wrapper count `'$wrapped_predicate'/2` and the log):
#   dyn1/dyn2/dyn3 `dynamic`, `'$set_predicate_attribute'(_, dynamic, false)`; abs1/abs2/abu1/abd1/abd2 abolish over a static, a dynamic and a
#   wrapped-before-clauses predicate; ret1-ret3 `retract`/`retractall` then static/abolish; clr1 a wrapped predicate WITHOUT clauses abolished
#   (swipl: the wrapper is gone, `none`); det1 `det` set and cleared; red1-red3 a second FILE redefines the wrapped predicate (red2: a dynamic one).
# THE LINGER FLAG: `resetProcedure!` passes `!isnew` and sets `isnew` itself for a dynamic or clause-less predicate (src/pl-proc.jl); every
# other caller passes `true`. A linger keeps the wrapper and resets the wrapped supervisor; no linger drops the wrapper (clr1 is the row).
# NOT LISTED (each with its reason):
#   * `freeCodesDefinition!(gd, def, true)` in `setThreadLocalDefinition!` (src/pl-proc.jl): no row. swipl installs `SUPERVISOR(thread_local)`
#     over a wrapped predicate (the wrapper is gone, `none`: measured 2026-11-22 with `'$set_predicate_attribute'(_, thread_local, true)`),
#     the kernel keeps the wrapper (`S_THREAD_LOCAL` is not ported, src/pl-supervisor.jl): a KNOWN DIFFERENCE owned by TH1; a row would pin it.
#   * `fix_det` and `fix_metapredicate` (src/pl-srcfile.jl): reachable only through a reload, which is not ported (LB6b: NotPortedError);
#     the white-box reload rows (test_reload_blocks_swipl.jl) call them with a hand-built reload, not with a wrapped predicate.
#   * the boot call `setDynamicDefinition!(gd, exception3.definition, true)` (src/pl-ext.jl): G1d.py (G1-E1) mutates it.
#   * `tbl_set_incremental_predicate`'s call (src/pl-tabling.jl): TAB1MIN.py lists why it has no killing row.
# TARGETS (audit D-0238): every file that runs the mutated code, the step's own file first. `freeCodesDefinition!` runs on every dynamic/static
# change, abolish, clause add and det declaration, so the supervisor mutants list the DYN files of TB5.py (the callers' test files).
TW = "test/core_lang/test_tabling_tb5wrap_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
WR = "test/core_lang/test_wrap_swipl.jl"
PRO = "test/db/test_procedures.jl"
ASS = "test/db/test_assert_swipl.jl"
LOAD = "test/files/test_load_swipl.jl"
DET = "test/core_lang/test_det_ssu_swipl.jl"
DYN = [                                                       # the files that call setDynamicDefinition!/resetProcedure! (TB5.py's DYN)
    "test/compile/test_body_code_swipl.jl",
    "test/compile/test_call_operands.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_autoload_trap.jl",
    "test/core_lang/test_module_path.jl",
    "test/core_lang/test_rules_swipl.jl",
    "test/core_lang/test_top1_pro.jl",
    "test/core_lang/test_top1b_swipl.jl",
    "test/db/test_reload_blocks_swipl.jl",
]
SUPT = [TW, TM, WR, PRO, ASS]                                 # the supervisor's wrapped branch
RESETT = [TW, TM, PRO, ASS] + DYN                             # abolish / reset
DETT = [TW, DET, TM, PRO]                                     # `det` declarations
REDT = [TW, LOAD, PRO]                                        # a second file redefining a predicate
TARGETS = [TW, TM, WR, PRO, ASS, LOAD, DET] + DYN             # every file a mutant lists (mutate_ci.py plan reads TARGETS)
SV = "src/pl-supervisor.jl"
PR = "src/pl-proc.jl"
MUTANTS = [
    # ── src/pl-supervisor.jl freeCodesDefinition! (the wrapped branch) ──
    dict(id="WRAP1B-A1 freeCodesDefinition! does not reset the wrapped supervisor (KILL TM tmc07 and the white-box c06 supervisor row: the wrapped supervisor stays as it was; (U) TW cannot see it: its wrapped predicates are virgin when reset)",
         file=SV, targets=SUPT,
         old="            resetWrappedSupervisor(gd, def, do_linger)\n",
         new="            nothing\n"),
    dict(id="WRAP1B-A2 freeCodesDefinition! drops the wrapper whatever the linger flag (KILL TW dyn1, dyn2, dyn3, abs1, abs2, abd1, abu1, abd2, det1, red1: the wrapper count `none`, no `called` in the log)",
         file=SV, targets=SUPT,
         old="            if !do_linger\n",
         new="            if true\n"),
    dict(id="WRAP1B-A3 freeCodesDefinition! without linger resets the wrapped supervisor but leaves the wrapper (KILL TW clr1: the wrapper count is 1, swipl's `none`)",
         file=SV, targets=SUPT,
         old="                def.codes = virgin\n                freeSupervisor(def, codes, do_linger)\n            end\n        else",
         new="                freeSupervisor(def, codes, do_linger)\n            end\n        else"),
    # ── src/pl-proc.jl: the callers ──
    dict(id="WRAP1B-C1 setDetDefinition! nondet --> det resets without lingering: a wrapped predicate loses its wrapper (KILL TW det1: `'$wrapped_predicate'/2` after `det` true is `none`)",
         file=PR, targets=DETT,
         old="        def.flags |= P_DET\n        freeCodesDefinition!(gd, def, true)         # reset to S_VIRGIN\n",
         new="        def.flags |= P_DET\n        freeCodesDefinition!(gd, def, false)        # reset to S_VIRGIN\n"),
    dict(id="WRAP1B-C2 setDetDefinition! det --> nondet resets without lingering: a wrapped predicate loses its wrapper (KILL TW det1: `'$wrapped_predicate'/2` after `det` false is `none`)",
         file=PR, targets=DETT,
         old="        def.flags &= ~P_DET\n        freeCodesDefinition!(gd, def, true)         # reset to S_VIRGIN\n",
         new="        def.flags &= ~P_DET\n        freeCodesDefinition!(gd, def, false)        # reset to S_VIRGIN\n"),
    dict(id="WRAP1B-D1 resetProcedure! treats a predicate without clauses as an old one: a clause-less wrapped predicate keeps its wrapper (KILL TW clr1: swipl's `none`)",
         file=PR, targets=RESETT,
         old="    if (def.flags & P_DYNAMIC) != 0 || !defined\n        isnew = true\n",
         new="    if (def.flags & P_DYNAMIC) != 0\n        isnew = true\n"),
    dict(id="WRAP1B-D2 abolishProcedure! does not make the predicate static before the reset: `resetProcedure!` sees P_DYNAMIC, takes `isnew` and drops the wrapper (KILL TW abd1, abd2, ret3: the wrapper count 1 becomes `none`)",
         file=PR, targets=RESETT,
         old="        setDynamicDefinition!(gd, def, false)\n        resetProcedure!(gd, proc, false)\n",
         new="        resetProcedure!(gd, proc, false)\n"),
    dict(id="WRAP1B-D3 abolishProcedure! resets a normal predicate as a new one: the wrapper is dropped (KILL TW abs1, abd1, abu1, abd2, red3: the wrapper count 1 becomes `none`)",
         file=PR, targets=RESETT,
         old="        setDynamicDefinition!(gd, def, false)\n        resetProcedure!(gd, proc, false)\n",
         new="        setDynamicDefinition!(gd, def, false)\n        resetProcedure!(gd, proc, true)\n"),
    dict(id="WRAP1B-E1 redefineProcedure warns but does not abolish the other file's definition (KILL TW red1, red2, red3: the answers keep the old clauses; test_load_swipl.jl `s/1` redefinition rows)",
         file=PR, targets=REDT,
         old="            return abolishProcedure!(gd, ld, proc, gd.modules[def.module_])\n        end\n    end\n    return true\nend",
         new="            return true\n        end\n    end\n    return true\nend"),
]
