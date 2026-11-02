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

## State
(updated below after each commit)
