# EV1 gate agent 2 — state (forced hand-back at the 150k cap)

Lane ~/code/lk-ev1, branch wip/ev1b, base origin/main dd93b68 (not re-fetched yet). Nothing pushed.

## Daemon
Slot taken: lk-rd1's daemon stopped (`warm.sh stop`, allow-restart: RD1c pushed). MY daemon is RUNNING in ~/code/lk-ev1
(`LOGICKERNEL_WARM_SECOND=1 tools/warm.sh start`, unit logickernel-warm-e29a7ffc, FIRST-slice message printed because that slice was free; the
other slot lk-lb4b2-run, unit 17790d9d, untouched). It is idle when this file is read: the next agent uses it, or the dispatcher stops it.

## Done
1. Three NOT LISTED rows ADDED to test/core_lang/test_event_swipl.jl (cases at the END; program: ev1_ethrow/2, ev1_pair/4; both added to ev1_unl):
   ev1g02 (a listener that throws during garbage_collect_clauses: swipl answers `ev1_ball(g)` with log g-erase-gone), ev1u18 (listeners
   ev1_pair(a,b) and ev1_pair(z,c), unlisten ev1_pair(X,c): X stays unbound, only a-b is called afterwards), ev1p20 (abolish of a predicate with a
   listener, then assertz: nothing logged). Pins FROM swipl 10.1.19 by evidence/EV1/gen_rows.py (two byte-identical runs; the first 81 lines unchanged,
   the stale t_ev1p18 line gone); `--fill` done; 83 pinned lines. After `warm.sh send` formatting gen_rows.py output is still byte-identical.
   NOTE: swipl's garbage_collect_clauses collects the erased clause only when the row is not the first in the process; the new rows sit after ev1g01.
2. tools/mutants/EV1.py: +3 mutants N1 (rcp[] = false removed, KILL ev1g02), N2 (PL_rewind_foreign_frame removed, KILL ev1u18), N3
   (destroy_event_list!(def) of resetProcedure! removed, KILL ev1p20) = 51 mutants; header says so. NOT run as mutants locally: the battery decides; if N2
   survives, check whether PL_unify rolls its own bindings back on failure (then the rewind is redundant: say so with the code line).
3. PORT BUG FOUND by the alt type run (term-type genericity, an engine fix, NOT a test edit): src/pl-event.jl compared terms with `==`
   (`name == mk_sym(T, et.name)` in get_event_listp, `as == mk_sym(...)` x3 in prolog_listen, `ev.name == name` in add_event_hook); the alt types
   raise on `==`. Fixed with two helpers `event_atom_is(t, name::Symbol)` (kind SYM and sym_text) and `event_name_is(a, b)` (sym_key); manifest entries added for both.
   EV1.py / BOOTPREDSUB.py anchors re-fitted (R5, R7, C9, BP3-L1, C1, C2, C5, P1, P3 after fmt); both lists pass the anchor check (EV1 51, BOOTPREDSUB 35, 0 bad) with
   .warm/ev1chk.py in the lane clone (untracked).
4. fmt: all 18 changed .jl files formatted through `warm.sh send .warm/fmt_all.jl` (9 rewritten: pl-copyterm, pl-event, pl-global, pl-incl, pl-list, pl-proc,
   test_bootpred3, test_event, the manifest).
5. test_event_swipl.jl on THREE types after the fixes and fmt: 99/99 x3 (297), 9m31s, no SKIP/Warning lines. (The first run, before the fix: reference 99/99, alt and
   alt_interned 1 error each = the `==` bug above.)
6. test_bootpred3_swipl.jl on three types: reference 130/130; alt and alt_interned each 1 FAIL: row bp3v15 (`variant_sha1(foo, R)`): `_B3_KNOWN` pins the kernel's
   digest 5da42330... which is the REFERENCE type's (the digest hashes the term type's symbol hash, DIVERGES pl-termhash.jl); alt types answer another 40-hex digest
   (e4aa3a31...). swipl's own digest differs anyway (cee71ebc...). NOT a regression against swipl: the row is a known difference pinning a type-dependent value.
   FIX NOT YET MADE (test-only, at test/core_lang/test_bootpred3_swipl.jl:440-446 and the KNOWN testset just below): when LK_TERM_IMPL != "reference" compare the
   line with the digest's 40 codes replaced by a shape (`replace(l, r"a\[(?:\d+,){39}\d+\]" => "a[40 hex codes]")`) for the key t_bp3v15 only; comment why. The KNOWN testset
   (12 pass on alt) needs a look: it passed, so check it does not compare the digest value on alt before editing.
7. Refusal-flip grep: `prolog_listen|prolog_unlisten|destroy_event_list|event_hook|PL_call_event|callEventHook|retractall_event|predicate_update_event` hit only
   test_bootpred3_swipl.jl, test_event_swipl.jl and the manifest in test/. No other test pins an old refusal of the stack's predicates. Files that call the changed
   functions (cleanDefinition!, _assertDefinition!, retractClauseDefinition!, abolish) and still need a three-type run: test/core_lang/test_pr1_swipl.jl,
   test/db/test_update_view_gc.jl, test/db/test_jit.jl, test/db/test_index_swipl.jl, test/core_lang/test_declare_destroy_swipl.jl (abolish) and test/core_lang/test_hash.jl (comment-only change).
8. Crash-term grep over added diff lines and messages: hits are only the event NAME `abort` / field `onabort` / `PLEV_ABORT` identifiers and doc words "break/abort";
   no crash, segment, SIGSEGV, invalid term_t or dies-of text.

## UNCOMMITTED when the cap hit (commit first; stage explicit paths, then commit)
src/pl-copyterm.jl pl-event.jl pl-global.jl pl-incl.jl pl-list.jl pl-proc.jl (fmt + the event_atom_is fix), test/core_lang/test_bootpred3_swipl.jl (fmt),
test/core_lang/test_event_swipl.jl (rows + fmt), test/static_analysis_manifest.jl (fmt + 2 entries), tools/mutants/EV1.py, BOOTPREDSUB.py,
evidence/EV1/ev1_driver.pl ev1_rows.out ev1_rows.pl (regenerated), this file. If the commit hook refuses (the marker was written for a different tree), run
`warm.sh file test/core_lang/test_event_swipl.jl` again after the bp3v15 fix and commit once; never write a marker.

## LEFT TO DO (in order)
a. Fix bp3v15 as in item 6; `warm.sh send .warm/fmt_all.jl` again if a .jl file changed; rerun test_bootpred3_swipl.jl (three types, 15 s).
b. Run on three types: the callers of item 7 (one `warm.sh file` each).
c. `warm.sh inventory` (commit docs/port_inventory.md and docs changes), `warm.sh check`; then ONE call each: test/test_type_discipline.jl, test/static_analysis_fast.jl then
   test_static_analysis.jl, test_manifest_entries.jl (the helpers' entries are new; `getfield` chain flag 13 is already an if/elseif).
d. `tools/pkgtest_way.sh test/core_lang/test_event_swipl.jl`, then test_bootpred3_swipl.jl, ONE at a time, never in `timeout`.
e. Alloc pins on three types: test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433 (report the numbers).
f. EV1.py: declare C8, C9, C10 with file:line AT THE FINAL SHA (current text cites src/pl-event.jl:609, :138-139, src/pl-wam.jl:1089-1090: stale after fmt and the new helpers;
   re-read the three sites). `git mv tools/mutants/EV1.py tools/mutants/EV1c.py`; rerun the anchor check on EV1c.py (path argument).
g. Author check (Shivaji Gadde), `git fetch`; if origin/main moved past dd93b68: plain `git rebase origin/main`, `warm.sh check`. Bare pushes at the SAME SHA: gate/ev1c, mutants/EV1c; ONE ci_status; do not wait.
h. Copy this file (updated) to ~/code/lk-channel/evidence/EV1/ (stage, then commit, push).
