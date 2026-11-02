# EV1 handoff 5 (writer 5; edit-only; branch wip/ev1b in ~/code/lk-ev1; supersedes handoff4's REMAINING W4: D and E are DONE)

Read handoff4.md for the design, the site lists and flags 1-11; this file adds what writer 5 did and what the gate agent must do.
NOTHING compiled or run (no daemon, no Julia process, no oracle call).

## Commits on wip/ev1b (on top of c22bcfb)
- b11dace ADDED: tools/mutants/EV1.py (48 mutants; TARGETS test_event_swipl.jl + test_bootpred3_swipl.jl).
- f9b7857 ADDED: static_analysis_manifest entries (EV1 functions and wired sites).
- ae5bb18 DOC: docs/architecture.md (the src/pl-event.jl row of "What is here now", a `## EV1` block at the END, the D2 "Not here" text, the BOOTPRED3 bullet).
- the commit carrying this file.

## D. tools/mutants/EV1.py
48 mutants: R1-R16 (registration: order, as(...), name(N) replacement, procedure arity, the `call/N` closure, list creation, event name lookup, domain_error,
table `location` of `erase`), U1-U5 (unlisten: no list, procedure compare, term unify, deletion, only-first), C1-C10 (call side: `rc = rc && ...` x2, exception `break`,
`rc = true` after a failing listener, WAKEUP_KEEP_URGENT_EXCEPTION, the clause put of erase/update events; C8-C10 EQUIVALENT), P1-P3 (retractall_event action, start/end
functor, module qualification), S1-S14 (raise sites: asserta/assertz atom, assert event, veto retract, veto result, retract atom, veto test, notify, retractall start/end/early return/result,
clause GC announce, record erase raise and result).
ANCHOR CHECK (throwaway `python3 -I` runpy script: old occurs exactly once in its file, new != old, ids unique, targets exist): 48 mutants, 0 bad.
EQUIVALENT with file:line: C10 the frameFinished raise (src/pl-wam.jl:1089-1090, nothing sets FR_NOTIFY until DBG1); C8 the rollback flag (src/pl-event.jl:609, callers pass 0);
C9 `ev.function_ == 0` (src/pl-event.jl:138-139, every callback has function_ 0 until TH1). The KILL lists are EXPECTATIONS from reading, not verdicts.
NOT LISTED, reasons in the file header (the gate agent may add a row, or record the survivor): the `copy(list.callbacks)` snapshot (needs a self-unlistening listener row),
the `rcp[] = false` of cleanDefinition! (needs a row where a listener raises during the clause GC), the `PL_rewind_foreign_frame` after a missed closure in prolog_unlisten
(needs a PARTIAL-unification row, e.g. listener `f(1,2)` and unlisten `f(X,3)`), the `destroy_event_list!(def)` of the pristine abolish (src/pl-modul.jl:1330; needs a row that
abolishes a predicate that has listeners), delay* (no caller).

## E. test/static_analysis_manifest.jl
In `_manifest_index`, after the BOOTPRED3 entries: `pl_prolog_unlisten2_va` joined the va list; the two STALE partial-port entries (`add_event_hook` with the old 6-argument
signature, `get_event_listp` with `Tuple{LD,Int}`) were REPLACED (they named methods that no longer exist: `which` would throw); `prolog_listen` and `get_callback` kept. New entries:
event_list_at, event_list_set!, link_event, add_event_hook, get_event_list!, register_event_hook, get_event_listp, prolog_unlisten, free_event_callback, destroy_event_list! x3,
cleanupEvents, call_event_list, delayEvent, delayEvents, sendDelayedEvents, callEventHook, PL_call_event_hook, PL_call_event_hook_va, predicate_update_event, table_answer_event,
retractall_event, term_to_fastheap, free_fastheap, put_fastheap, PL_put_frame, get_procedure_resolve_namearity, 5-arg _assertDefinition! (Int and ClauseRef), ld method of
retractClauseDefinition!, announceErasedClause, 6-arg cleanDefinition!. The 4-arg `_assertDefinition!`, the 4-arg `retractClauseDefinition!` and the 3-arg `cleanDefinition!` entries stay valid.
The `args...` entries use the commonest call's types (Clause); branches that assert another type are dead for that specialisation.

## F. docs/architecture.md
Row of src/pl-event.jl (pl-event.c header), `## EV1` at the END (structures, WIRED, DEFERRED with owners, DIVERGES, the known difference), D2 "Not here" text fixed (the section around the
old :5939), BOOTPRED3's prolog_listen bullet and its "Left to others" line fixed. Deferred sites disclosed: untable raise and table_answer_event's caller (TAB1),
thread events and PL_thread_at_exit (TH1), break/abort and `$break_at` (DBG1), reload delayEvents, transactions, PL_cleanup, freePrologLocalData, the full abolish.

## Crash-term grep (D-0164) over this writer's diff and messages
Only hits: the event NAME / field `abort` / `:onabort` (src/pl-event.jl identifiers) in the docs and EV1.py. No description of a crash. The gate agent repeats it over the whole stack's messages.

## FLAGS added by writer 5 (for the audit)
12. EV1.py has three EQUIVALENT mutants (C8, C9, C10) and five NOT LISTED sites (above); each needs the audit's nod, or a row.
13. The manifest replaced two stale entries; possible `test_opt` reports in `event_list_at`/`event_list_set!` (`getfield`/`setfield!` with a runtime Symbol: a runtime dispatch / a conversion
    of an `Any`). If reported: rewrite as an `if et.location === :onabort ... elseif` chain (same behaviour) or exempt with a reason; decide at the gate.
14. docs: the BOOTPRED3 text now says row bp3l33 is swipl's answer (true after commit ae1b44a).

## Gate agent runs (in order)
1. FIRST a Julia parse of test/core_lang/test_event_swipl.jl (never parsed), then of test/static_analysis_manifest.jl and src/pl-event.jl (never compiled).
2. `warm.sh fmt` (re-fit any EV1.py `old` that fmt rewraps in src; rerun the anchor check), `warm.sh inventory`, `check`.
3. Every changed or new test file on all three term types: test_event_swipl.jl, test_bootpred3_swipl.jl; test/test_type_discipline.jl; test_static_analysis.jl; test_manifest_entries.jl.
4. `tools/pkgtest_way.sh test/core_lang/test_event_swipl.jl`, then `... test_bootpred3_swipl.jl`, ONE at a time (D-0222).
5. Push `mutants/EV1` at the WIP SHA once everything above compiles (the list and its TARGETS exist), branch-gate, the crash-term grep, then `gate/ev1` and `mutants/EV1` at the SAME SHA.
6. Alloc pins x3 (GD/LD/definition struct change: Tier 1), with the dispatcher's go. Full CI + battery. Decide the NOT LISTED survivors and the three EQUIVALENT declarations.
7. Expected first-run trouble (nothing compiled): handoff4 "Possible compile traps"; the rows marked `# UNVERIFIED on the kernel: gate decides`.
Daemon: none started or held by this writer.
