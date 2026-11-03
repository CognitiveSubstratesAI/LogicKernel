# RD1b gate agent 1 (2026-11-03)

Pushed: gate/rd1b and mutants/RD1b at bd38a5c63ab558b908026dcf2b50d8a6daac682a (fast-forward of origin/main dd93b68, 15 commits).
CI run 41566656026, Evidence run 41566655959 (queued at the push). Mutation run for mutants/RD1b: started by the push (id not read).

## Re-stack
wip/rd1 rebased onto origin/main dd93b68 with a plain `git rebase` (no -i). Two conflicts, both "keep both sides":
- src/pl-ext.jl `foreigns`: PR1's abolish/1,2, `$c_current_predicate`/2, garbage_collect_clauses/0 and RD1's read/1, `$raw_read/1,2`, read/2.
  Order is upstream's (pl-ext.c: read 116, raw_read 117-118, abolish 125-126, c_current_predicate 132, garbage_collect_clauses 171, read/2 175); header comment has both sentences.
- test/static_analysis_manifest.jl: Q10's last entry got its comma, RD1 and RD1b entries follow. docs/architecture.md merged without a conflict.
Mutant list renamed tools/mutants/RD1.py -> RD1b.py (pre-push hook: mutants/<name> needs tools/mutants/<name>.py), path text in its header and in the architecture block.

## Gate steps run
- fmt: JuliaFormatter through `warm.sh send` over the 5 .jl files changed against main; rewrote src/pl-read.jl (5 lines) and test_read_stream_swipl.jl.
  Mutant anchors re-checked afterwards with a python3 -I checker: 33 mutants, each `old` once, ids unique, old != new.
- inventory: wrote docs/port_inventory.md (4 lines), port_check clean (253 files). docs/architecture.md unchanged by it.
- check: first run FAILED only on test_read_stream_swipl.jl (below); second run PASS in 322 s (format, port_check, manifest covers every method [3397 entries],
  term scopes, meta files, Pkg.test-way run on the 2 changed test files: test_io.jl peak 361 MiB, test_read_stream_swipl.jl peak 1525 MiB, oom_kill 0).
- test_read_stream_swipl.jl on reference, alt, alt_interned: 259/259 each. test_io.jl on the three types: 6/6 each. test/test_type_discipline.jl: 33/33.
  No SKIP, no Warning lines in these logs. `swipl` is not on PATH on this machine: the live compare ("the pins are swipl's") did not run here; it runs in CI.
- first smoke: read/1, read/2, `$raw_read/1,2` registered (two arities of one name) and answer through the foreigns dispatch (rows rt01-rt30 and rt170-rt190 pass).
- crash-term grep over `git diff origin/main..HEAD` added lines (evidence included) and all commit messages: 0 hits.
- author/committer of all 15 commits: Shivaji Gadde <11524260+sivaji1012@users.noreply.github.com>.
- pre-push: check_coverage_zero OK (2 changed src files); no refusal.

## Failures of the first check and their fixes (test side only; no src change)
Five rows ended in the kernel's EXISTING unify_location refusal (the exception that rt87-rt89 already pin: a syntax error whose stream has neither a file name nor
string-stream functions; src/pl-read.jl:1087 area, "the stream table (R2)"): rt113 and rt187 (unterminated `/* abc` on a FILE stream: swipl's context is stream(S,1,0,0),
the kernel's block-comment error has no file name), rt154 (`back_quotes(symbol_char)`), rt163 (`a +++ b.` with module(nomod)), rt169 (`x.y`), the last three over open_string/2.
The kernel answers `jlerr NotPortedError unify_location: ...`, a refusal, not a different result; same code path as the documented flag 4. The five rows moved from
_RT_CASES to _RT_KNOWN with the kernel line read from the failure output; swipl's pins unchanged (reordered to follow). Not a regression: no row reads a term or an
error differently from swipl; every refusal is the already documented one. One test bug: the KNOWN-row check wanted a swipl pin with an answer, but rt87/rt88 are
rows where swipl FAILS (pin `t_rt87` alone): now `== "t_$id" || startswith(...)`.
The risky spots of the handoff all agree with swipl without change: `op(200,fy,rtm:(<))` (rt311, rt315), PL_put_atom/PL_error signatures (rt305-rt310),
rt308/rt309 OPT_ATOM errors, and rt320/rt321 (the kernel's blob refusal line as predicted).

## Alloc pins (struct change read_data.blobs; Tier 3 but run as an alarm)
Pass counts per file (reference + alt + alt_interned = baseline sum; all exit 0, 0 fail, 0 error; the only Info lines are the old "fatop/botop not pinned on this type"):
- test_zero_exports: 81 + 79 + 79 = 239 (baseline 239)
- test_local_stack: 129 + 124 + 124 = 377 (377)
- test/foreign/test_query: 117 + 115 + 115 = 347 (347)
- test_rules_swipl: 145 + 144 + 144 = 433 (433)
All four match.

## Daemon state
The lk-f1c daemon (logickernel-warm-1efd1653) was stopped from ~/code/lk-f1c; mine runs in ~/code/lk-rd1 (unit logickernel-warm-4d22bbd8, LOGICKERNEL_WARM_SECOND=1)
since 2026-11-03 ~02:00 by the VM clock; idle after the pin runs. ~/code/lk-lb4b2-run was not touched.
