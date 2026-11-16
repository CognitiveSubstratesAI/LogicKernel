# TAB1-SYSPREDS probe: when does '$syspreds' come into being

Upstream (git -C ~/dev-zone/swipl-devel show 18168e62:<file>):
- pl-setup.c:146-155 setupProlog: initDBRef, initRecords, initTries, initZip, initUndo, initWrap run in that order; initUndo
  (pl-undo.c:249-251) only registers the undo blob type: PL_register_blob_type(&undo_blob). No module is made there.
- pl-undo.c:224-241 run_undo_hooks: `_PL_predicate("$run_undo", 1, "$syspreds", &GD->procedures.drun_undo1)` at its first
  call. That is the only place in src/ (outside pl-thread.c:3866, signal_is_blocked/1) naming "$syspreds" as a module string.
- So the undo blob is registered at init (setupProlog), the module '$syspreds' is made lazily at the first run_undo_hooks.

Kernel before this step: pl-ext.jl (setBuiltinPredicateProperties!) made lookupProcedure('$run_undo', 1, lookupModule('$syspreds'))
at setup, so the module existed after setupProlog (index 3). Only run_undo_hooks (src/pl-undo.jl) reads
gd.procedures_drun_undo1. Fix (a): created at the first call, arity-0 placeholder check as findReset does for findall_loop/4.

## Pin (swipl 10.1.20, ~/.local/bin/swipl), the same two questions at start-up (after boot)
    swipl -g "current_module('$syspreds') ..., current_predicate('$syspreds':'$run_undo'/1) ..." -t halt
    pin_current_module_syspreds_yes
    pin_run_undo_defined_yes
The unbooted module table, a module's index and the blob registration order are not observable in swipl (current_module/1
enumerates a hash table; test_clause_ref_swipl.jl:527ff says the same of blob ranks): the pin can say that the module exists
once boot has loaded syspred.pl, the source lines say when upstream makes it before that.

## Kernel, evidence/TAB1/syspreds_probe.jl (reference type; the file is not term-generic, the module table is type-independent)
    PROBE unbooted modules: ["system", "user"] n=2
    PROBE drun_undo1 arity before first run_undo_hooks: 0
    PROBE run_undo_hooks rc: false
    PROBE modules after first run_undo_hooks: ["system", "user", "$syspreds"] n=3
    PROBE drun_undo1 arity after: 1
(rc false: '$run_undo'/1 has no clause in an unbooted database; what matters is the module table before and after.)
Same run on the parent tip (eager creation): the commits 2933e730 / 893902f0 measured n=3 straight after setupProlog.
