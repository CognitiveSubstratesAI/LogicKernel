# F1c handoff — the `debug` flag setter and `shared_object_extension`, `version_git`, `libswipl`, `xref` (audit D-0370 item 5: FOLLOW UPSTREAM)

Worktree ~/code/lk-f1c, branch wip/f1c (off main 012633e). Writer: Sonnet, edit-only, nothing was compiled or run. Pin: swipl-devel cbf4e1896275 (V10.1.19-1-gcbf4e189).

## Plan (ordered groups, commit estimate 5)
1. THIS FILE (plan).
2. `UPSTREAM: pl-prologflag.c set_flag_value, unify_prolog_flag_value; pl-trace.c debugmode tracemode (swipl-devel cbf4e1896275)`: the setter for `debug`
   (pl-prologflag.c:1317-1323) and `debugger_show_context` (:1325-1326), the read side (:2113-2116), `debugmode` (pl-trace.c:2223-2275) and
   `tracemode` (:2133-2158) in src/pl-trace.jl; the debugger-status fields, a Tier 1 ALARM (struct): `ld.debugstatus_skiplevel/tracing/debugging/showContext`
   appended at the END of `PL_local_data` (src/pl-global.jl), initial values as `resetTracer` (pl-trace.c:1882-1892).
3. `UPSTREAM: pl-prologflag.c initPrologFlags set_libswipl, pl-version.c setGITVersion (swipl-devel cbf4e1896275)`: `shared_object_extension` (:2595), `version_git`
   (pl-version.c:44), `libswipl` (:2470-2493) in `initPrologFlags!`; `xref` stays as upstream's C leaves it (no C definition: boot/init.pl:2957 creates it).
4. `MODIFIED:` tests: test_set_flag_swipl.jl and test_push_flag_swipl.jl lose the `debug` (and `debugger_show_context`) refusal rows;
   test_prolog_flag_swipl.jl drops three names from PINNED_ONLY_SWIPL; NEW test/core_lang/test_debug_flag_swipl.jl with evidence/F1C/gen_rows.py;
   tools/mutants/F1C.py.
5. `MODIFIED:` docs/architecture.md block + test/static_analysis_manifest.jl entries (APPENDED at the end), last.

## State (forced hand-back at the context cap; the next agent continues from here)
COMMITTED on wip/f1c: d6c63a2 (this plan), 90ceae5 (group 2: setter, read side, debugmode, tracemode, 4 LD fields at the END of PL_local_data = Tier 1 ALARM:
alloc pins x3 + type discipline at the gate), 6851585 (group 3: `shared_object_extension` "so", `libswipl` = LIBPL_PATH fallback `<pkgdir>/lib/libswipl.so` (FT_ATOM, writable,
oracle's is dladdr's FF_READONLY: access differs), `version_git` = "10.1.19-1-gcbf4e189" = `git describe --match V*` of the pin cbf4e189, V cut; the oracle's own build says
10.1.19-9-ge0323664, so rows check only the prefix `10.1.19`; `xref` NOT defined in C upstream: boot/init.pl:3062-3067 creates it, left to the loader).
WRITTEN, UNCOMMITTED (stage + commit as `MODIFIED: test/core_lang/...`): test_set_flag_swipl.jl (debug, debugger_show_context out of _SF_REFUSED, threshold 18),
test_push_flag_swipl.jl (debug out of _PF_REFUSED, threshold 6, header line), test_prolog_flag_swipl.jl (libswipl, shared_object_extension, version_git out of PINNED_ONLY_SWIPL).
LEFT (groups 4-5):
 a. NEW test/core_lang/test_debug_flag_swipl.jl: copy the helpers of test_push_flag_swipl.jl (lines 15-87 driver/enc/_pf_swipl_lines, `_pf_file`, `_pf_query`, `_pf_kernel`, the two
    testsets), rename _pf/_PF/pf -> _db/_DB/db; cases t_dbNN wrapped `catch(G, error(E,_), R = raised(E)), set_prolog_flag(debug,false), set_prolog_flag(debugger_show_context,false)`;
    rows: initial values; debug true/false and on/off read-back; debugger_show_context; type_error(bool, maybe/1), instantiation; error leaves the value; last_call_optimisation
    unchanged (table value) around debug; push/pop of debug; idempotent set; `$current_prolog_flag(debug,V,_,A,T)`; shared_object_extension = so and its permission_error;
    version_git atom with prefix 10.1.19 + permission_error; libswipl atom containing libswipl.so; xref true/false round trip. Generator evidence/F1C/gen_rows.py as
    evidence/F2/gen_push_rows.py (swipl may be run: two runs byte-identical, fills PINS-BEGIN/END). Kernel-only testset (UNVERIFIED on the kernel: gate decides):
    `ld.messages` holds exactly two (:silent, debug_mode(..)) after set true/false; while debug is true `ld.debugstatus_debugging`, `!LK.truePrologFlag(ld, LK.PLFLAG_LASTCALL)`,
    `!LK.truePrologFlag(ld, LK.PLFLAG_VMI_BUILTIN)`, `ld.debugstatus_skiplevel == typemax(UInt)`; after false the bits are back; libswipl access `write`; version_git == "10.1.19-1-gcbf4e189".
 b. tools/mutants/F1C.py (format of tools/mutants/MOD3b.py; anchors once: the `rval = debugmode(` line, the `&& rval` mask guard, `clearPrologRunMode!(ld, RUN_MODE_NORMAL)`,
    `setPrologRunMode!(ld, RUN_MODE_NORMAL)` (twice in src/pl-trace.jl: use a longer anchor), `ld.debugstatus_showContext = val`, the read of `ld.debugstatus_debugging`, SO_EXT, GIT_VERSION;
    TARGETS: test_debug_flag_swipl.jl, test_set_flag_swipl.jl, test_push_flag_swipl.jl, test_prolog_flag_swipl.jl); validate with a throwaway python3 -I checker.
 c. LAST commits: docs/architecture.md block APPENDED at the end (UPSTREAM: os/pl-prologflag.c, pl-trace.c, pl-version.c; the DIVERGES below), test/static_analysis_manifest.jl entries APPENDED
    for `debugmode`, `tracemode`, `setPrologRunMode!`, `clearPrologRunMode!` (and constants if the manifest lists them).
DIVERGES, owner DBG1 (all in comments at the sites): `have_space_for_debugging`/`enlargeMinFreeStacks` (pl-trace.c:2163-2204, :2236-2241: the kernel's stacks grow by doubling), `qf->debugSave = true`
for DBG_ALL (:2246-2249; the query frame has no slot, PL_Q_NODEBUG deferred), `validUserStreams` (:2269), `LD->trace.find->searching` (tracemode). The sites in src/pl-wam.jl that read
`debugstatus.debugging` (CHP_DEBUG choice points at UNKNOWN_FAIL, lines 3252, 3763, 4545, 4610) still treat it as never set: with `debug` true the kernel differs from upstream there (DBG1).
`debug_mode(Bool)` and `trace_mode(Bool)` are `silent` messages kept in `ld.messages` (printMessage), one per change, until boot/messages.pl runs: a toplevel that sets debug on every query grows it.
Not touched: tty_control, debug_on_interrupt (still refused by name; signals/terminal). Not compiled, nothing run.
Gate agent runs: fmt, check, the 4 test files on all three term types, test/test_type_discipline.jl, pkgtest_way for each changed test file, alloc pins x3 (LD struct), inventory, mutants/F1C, branch-gate.
