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

## WRITER 2 STATE (Sonnet, edit-only; forced hand-back at the 150k cap) — group 4a DONE and committed; 4b, 4c (white-box additions), 5 LEFT
COMMITTED: 4c076f6 `ADDED: test/core_lang/test_debug_flag_swipl.jl, evidence/F1C/gen_rows.py` (35 rows db01-db35, pins from two byte-identical swipl runs, LC_ALL=C, evidence/F1C/debug_rows.out;
generator regenerates the PINS region: `LC_ALL=C python3 -I evidence/F1C/gen_rows.py`; it reads cases single-line or fmt-wrapped; each case is followed by `set_prolog_flag(debug,false), set_prolog_flag(debugger_show_context,false)`).
NOT RUN: Julia was never started (no parse check of the new test file: the gate's first `warm.sh file` will show a typo).
Swipl facts probed (rows db01-db35 hold them): `set_prolog_flag(debug,1)`/`0` accepted (true/false); `$current_prolog_flag(debug,V,S,A,T)` gives [false,_,write,boolean]; shared_object_extension = so, read, atom;
version_git read-only atom (prefix 10.1.19); libswipl read, atom (swipl's value is the loaded library path, ours `<pkgdir>/lib/libswipl.so`, access WRITE); xref is a bool flag, write. Oracle: 10.1.19-9-ge0323664.
LEFT, in order:
 4b. WHITE-BOX ADDITIONS to the last testset of test_debug_flag_swipl.jl (the mutant plan below depends on them, tracemode(true) is reached by no flag path): (i) a row `r_lco(R) :- set_prolog_flag(last_call_optimisation,false),
     set_prolog_flag(debug,false), R=ok` then `LK.truePrologFlag(ld, LK.PLFLAG_LASTCALL)` is TRUE (upstream pl-trace.c:2253 `else if (!doit) setPrologRunMode`, and pl-incl.h:2853 sets the bits whatever the table says), then a row setting
     last_call_optimisation true again; (ii) direct calls with the state off: `old = Ref(false); LK.tracemode(ld, true, old)` -> true, `old[]==false`, `ld.debugstatus_tracing && ld.debugstatus_debugging`, skiplevel typemax(UInt), a `trace_mode`
     message holding `a<codes true>`; set `ld.debugstatus_skiplevel = 0` and call `LK.tracemode(ld, true, nothing)` again -> skiplevel typemax(UInt) again (the "make sure trace works inside skip" branch), `old[]` true on a Ref;
     then the query `r_off` (set_prolog_flag(debug,false)) must leave `!ld.debugstatus_tracing && !ld.debugstatus_debugging` (tracemode(false) runs first); also `LK.debugmode(ld, true, ref, UInt32(0))` writes the old mode into the Ref;
     (iii) libswipl exact value: the kernel's `joinpath(<pkgdir>, "lib", "libswipl.so")` is machine-dependent: compare only the suffix (db19 does).
 4c. tools/mutants/F1C.py (NOT written; format of tools/mutants/F2.py: `id`, `file`, `old` EXACTLY once, `new`, optional `equivalent`, `targets`). TARGETS (D-0238), every mutant: test_debug_flag_swipl.jl, test_set_flag_swipl.jl, test_prolog_flag_swipl.jl
     (test_push_flag_swipl.jl no longer sets debug; check `grep -n debug` in test_set_flag_swipl.jl and test_prolog_flag_swipl.pl before listing, list a file only if it exercises the line). Planned mutants (file; anchor -> mutant; KILL):
     setter src/os/pl-prologflag.jl: `rval = debugmode(ld, true, nothing, DBG_ALL)` -> `rval = true` (db02, white-box); `rval = tracemode(ld, false, nothing) && debugmode(ld, false, nothing, UInt32(0))` -> `rval = tracemode(ld, false, nothing)` (db02);
     the same -> `rval = debugmode(ld, false, nothing, UInt32(0))` (tracemode dropped: KILL only by 4b(ii) r_off with tracing on); `ld.debugstatus_showContext = val` -> `= !val` (db04); read side `PL_unify_bool_ex(ld, val, ld.debugstatus_debugging)` -> `false` (db02),
     `... ld.debugstatus_showContext)` -> `false` (db04). EQUIVALENT with reasons: `if f.index != 0 && rval` -> `if f.index != 0` (the `debug` flag has index 0, initPrologFlags! line ~1978 `setPrologFlag(gd, "debug", FT_BOOL, false, 0)`, and rval is always true: printMessage src/pl-error.jl:1025-1028 returns true);
     `return rval` -> `return true` (same reason); `const DBG_ALL = UInt32(0x1)` -> 0x2 (`flags` is never read by debugmode: src/pl-trace.jl debugmode body, qf->debugSave is DBG1's); `updateAlerted(ld)` removed in debugmode (src/pl-wam.jl:209-216 recomputes ld.alerted from attvar_head only).
     debugmode/tracemode src/pl-trace.jl: skiplevel assignment in debugmode (anchor with its trailing comment `# debugstatus.skiplevel = SKIP_VERY_DEEP`) -> nothing (white-box skiplevel); `clearPrologRunMode!(ld, RUN_MODE_NORMAL)        # clearPrologRunMode(RUN_MODE_NORMAL)` -> nothing;
     `setPrologRunMode!(ld, RUN_MODE_NORMAL)          # setPrologRunMode(RUN_MODE_NORMAL)` -> nothing (else branch); `    elseif !doit\n        setPrologRunMode!(ld, RUN_MODE_NORMAL)` -> `elseif !doit\n        nothing` (4b(i));
     `ld.debugstatus_debugging = doit                     # debugstatus.debugging = doit` -> `= true` (db02); `updateAlerted(ld)\n        set = true` -> `updateAlerted(ld)` (message count); `old === nothing || (old[] = ld.debugstatus_debugging)` -> `(old[] = doit)`;
     `ld, :debug_mode,` -> `ld, :trace_mode,` (message name); in tracemode: `debugmode(ld, true, nothing, UInt32(0))             # (the answer` -> `true             # (the answer`; `ld.debugstatus_tracing = doit` -> `= false`; `ld, :trace_mode,` -> `ld, :debug_mode,`;
     the `if doit                                                 # make sure trace works inside skip\n        ld.debugstatus_skiplevel = SKIP_VERY_DEEP` -> assignment dropped (4b(ii)); `old[] = ld.debugstatus_tracing` -> `old[] = doit`;
     `const SKIP_VERY_DEEP = typemax(UInt)` -> `UInt(0)`. src/os/pl-prologflag.jl run-mode: `prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)` -> LASTCALL only, -> VMI_BUILTIN only (white-box); `ld.prolog_flag_mask |= mask` -> `nothing` and
     `ld.prolog_flag_mask &= ~mask` -> `|= mask` (check each occurs once: setPrologFlagMask!/clearPrologFlagMask! are near, use the lines with `mask::UInt64` context).
     build flags: `const SO_EXT = Sys.iswindows() ? "dll" : "so"` -> `"dll"` (db15, db19); `setPrologFlag(gd, "shared_object_extension", FT_ATOM | FF_READONLY, SO_EXT)` -> without FF_READONLY (db16, db31);
     `const GIT_VERSION = "10.1.19-1-gcbf4e189"` -> `"10.1.20-1-gcbf4e189"` (db17) and -> `"10.1.19-2-gcbf4e189"` (white-box exact); `setPrologFlag(gd, "version_git", FT_ATOM | FF_READONLY, GIT_VERSION)` -> without FF_READONLY (db18, db32);
     `"lib", "libswipl." * SO_EXT)` -> `"lib", "libswipl")` (db19); `setPrologFlag(gd, "libswipl", FT_ATOM, ` -> `FT_ATOM | FF_READONLY, ` (white-box libswipl access `write`: the known difference's pin).
     Validate: a throwaway `python3 -I` script that execs F1C.py and counts each `old` in its file (must be exactly 1), run BEFORE the commit; write the count in the commit message.
 5. docs/architecture.md block APPENDED at the very end (after "## P2 ..." which ends at the file's last line; heading `## F1c — the debug flag setter and the build flags (R2, audit D-0370 item 5, written, not yet gated)`): what F1c ports
    (pl-prologflag.c set_flag_value/unify_prolog_flag_value for debug and debugger_show_context, pl-trace.c debugmode/tracemode, pl-incl.h setPrologRunMode/clearPrologRunMode/RUN_MODE_NORMAL, initPrologFlags set_libswipl/shared_object_extension, pl-version.c setGITVersion),
    the DIVERGES list owner DBG1 (copy from above) INCLUDING the CHP_DEBUG sites src/pl-wam.jl:3252, 3763, 4545, 4610 that still treat debugging as never set, `xref` left to the loader, the messages in ld.messages.
    "Known-difference checklist item (F1c, pending F8): libswipl: swipl 10.1.19's flag is read-only and holds the loaded library's path (dladdr, pl-prologflag.c:2483-2488); the kernel's is the LIBPL_PATH fallback (:2491-2493), WRITABLE, `<pkgdir>/lib/libswipl.so`; pinned in the last testset of test_debug_flag_swipl.jl."
    Also: version_git rows check the prefix only (oracle 10.1.19-9-ge0323664, pin 10.1.19-1-gcbf4e189). test/static_analysis_manifest.jl: APPEND inside `_manifest_index(T)` after the last entry `(LK.pl_style_check2_va, ...)` (add the comma; it ends line ~2400, before `)` and `end`):
    `# R2 F1c — the debug flag (pl-trace.c debugmode, tracemode; pl-incl.h run mode)`, `(LK.debugmode, Tuple{LD, Bool, Nothing, UInt32}, false)`, `(LK.debugmode, Tuple{LD, Bool, Base.RefValue{Bool}, UInt32}, false)`, `(LK.tracemode, Tuple{LD, Bool, Nothing}, false)`,
    `(LK.tracemode, Tuple{LD, Bool, Base.RefValue{Bool}}, false)`, `(LK.setPrologRunMode!, Tuple{LD, UInt64}, false)`, `(LK.clearPrologRunMode!, Tuple{LD, UInt64}, false)`. No other new method in src (consts SO_EXT, GIT_VERSION, RUN_MODE_NORMAL, DBG_ALL, SKIP_VERY_DEEP are not methods).
    `_message_term(LD, Symbol, Int)`, `_err_atom(LD, T)`, `printMessage(LD, Symbol, Int)`, `updateAlerted(LD)` are already listed.
 6. NOT touched: test/core_lang/test_prolog_flag_swipl.pl / .out (the fk/mk lists do not name libswipl, version_git, shared_object_extension; the key-set testset now expects them present). Optional: `mk(libswipl)`, `mk(version_git)`, `fk(shared_object_extension)` need the .out regenerated by swipl (the file's own message says how).
 TIER-1 ALARM FOR THE GATE: four fields appended at the END of `PL_local_data` (`debugstatus_skiplevel::UInt`, `debugstatus_tracing`, `debugstatus_debugging`, `debugstatus_showContext`::Bool; src/pl-global.jl) -> a struct change: alloc pins x3, test/test_type_discipline.jl,
 cold compile of the warm daemon (~30 min, D-0228). Append-vs-append with other writers' LD blocks (S2a prompt_*, O1B IO_output_stack): merge by position at the stack top.
 CHANGES STILL OWED to the lk-channel copy: `cp evidence/F1C/handoff.md ~/code/lk-channel/evidence/F1C/handoff.md` (pull first; an earlier copy is committed locally in lk-channel, UNPUSHED: push it with bare `git push`).

## WRITER 3 STATE (Sonnet, edit-only) — groups 4b, 4c, 5 DONE and committed; NOTHING LEFT TO WRITE, the gate agent is next
COMMITTED on wip/f1c after 091f3b4: 3a19bca (4b: white-box rows in the last testset of test_debug_flag_swipl.jl: the `elseif !doit` row via r_lco_off/r_off_again/r_lco_on, direct
LK.tracemode / LK.debugmode calls with Refs, message counts by name, the skip-level reset), fcaa3ee (4c: tools/mutants/F1C.py, 35 mutants, 4 declared equivalent; plus one more white-box
row: skiplevel lowered to 0 before debugmode(true), which kills F1C-B1), 87e617b (5: docs/architecture.md block appended at the end; manifest entries after pl_style_check2_va).
ANCHOR CHECK: a throwaway `python3 -I` script execs tools/mutants/F1C.py and counts every `old` in its file: 35 mutants, every `old` occurs EXACTLY once, ids unique, old != new, targets exist.
TARGETS (re-grepped over test/): test_debug_flag_swipl.jl, test_set_flag_swipl.jl, test_prolog_flag_swipl.jl (+ its .pl). Not listed, with reasons in the F1C.py header:
test_push_flag_swipl.jl (names debug in a comment only now), test_gate_split.jl (fake swipl), test_compiler_warnings_swipl.jl / test_qlf_swipl.jl (debugstatus_styleCheck), libswipl comments elsewhere.
NOT RUN (edit-only, no Julia): the gate agent's first `warm.sh file test/core_lang/test_debug_flag_swipl.jl` will show a typo or a wrong kernel expectation (all white-box expectations are UNVERIFIED on the kernel;
if one is wrong decide per upstream pl-trace.c:2223-2275 / 2133-2158, not by the row). The `old` strings were written in the repo's formatted style: RE-FIT any that `warm.sh fmt` rewraps
(mutate_drive.py refuses a string not occurring once). Open for the gate: tools/warm.sh fmt, check, the 4 test files x 3 term types, test_type_discipline.jl (LD struct: 4 fields at the END),
pkgtest_way.sh per changed test file (one at a time), alloc pins x3, push mutants/F1C early, branch-gate, crash-term grep, gate/f1c + mutants/F1C at the SAME SHA.
Commit shape: the branch holds the plan/evidence commits d6c63a2, 091f3b4 and this one besides the code commits; fold with GIT_SEQUENCE_EDITOR=true autosquash if the dispatcher wants fewer.
