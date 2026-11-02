# EV1 handoff (writer; edit-only; branch wip/ev1, STACKED ON wip/bootpred3 tip e7a0dc2 — BOOTPRED3 is paused and not yet gated)

Upstream: pl-event.c (808 lines) and pl-event.h of the pin tree ~/dev-zone/swipl-devel-cbf4e189 (10.1.19). Replaces the partial
`prolog_listen/2,3` of src/pl-event.jl (BOOTPRED3 flag 3).

## Design (decided; the DIVERGES are representation-only and must be flagged to the audit, D-0353)
- Event types (pl-event.h `pl_event_type`): an `@enum`-free set of Int constants `PLEV_*` (precedent `RECORDA`/`DB_REF_CLAUSE`: no `_enum_hash` entry
  needed). `PL_events` becomes the full table of 12 rows (id, name, argc, local) as upstream (O_ENGINES build).
- Structs, in src/pl-incl.jl BEFORE `definition` (struct cycle: `event_callback{T,D}`/`event_list{T,D}`, D = `definition{T}`, as `clause_list`):
  `fastheap_term{T}` (pl-copyterm.h; DIVERGES: the term's `record` fields gsize/nvars/code/values — upstream's relocatable cells need the word
  stacks the kernel does not have; term_to_fastheap/put_fastheap/free_fastheap are in src/pl-copyterm.jl, via compileTermToHeap/copyRecordToGlobal),
  `event_callback{T,D}` (name, module_ index, procedure, function index (0: none), closure, argc, flags), `event_list{T,D}` (DIVERGES: a Vector,
  head = first; no lock: one thread). `definition` gets ONE appended field `events` (pl-incl.h:1773) plus an outer 11-argument constructor so
  that the four positional construction sites (pl-proc.jl:59, pl-modul.jl:1319, pl-global.jl:124 and :532) stay textual.
- GD: ONE appended field `event_hook::event_hooks{T}` (GD->event.hook.on*), LD: appended block `event_hook`, `event_buffered`, `event_delay_nesting`
  (pl-global.h:302-312, 681-689). Both are appended at the END of the struct and of the positional constructor call.
- Sites: the calling side raises through `callEventHook` = `PL_call_event_hook(gd, ld, ev, args...)` (only when the list exists).

## Event raise sites in the pin tree (upstream file:line) and our kernel
WIRED (the Julia function exists): assertDefinition (pl-proc.c:1472, `_assertDefinition!`), retractClauseDefinition (:1709), erase/1 record
(pl-rec.c:2468, src/pl-rec.jl:931), frameFinished (pl-wam.c:959, src/pl-wam.jl:1083), retractall/1 (pl-proc.c:3308, :3397, src/pl-proc.jl:1937),
announceErasedClause (pl-proc.c:1773, 1850: in the clause-GC pass: check the Julia cleanDefinition!), unallocDefinition/resetProcedure
(destroy_event_list, pl-proc.c:268, 408).
DEFERRED (no Julia function yet; each gets the call when its step lands): clearBreakPointsClause + $break_at (pl-comp.c:9084-9173, DBG1),
restore_after_exception abort (pl-pro.c:105), unloadFile/endReconsult delayEvents (pl-srcfile.c:804/835, 1604/1639), reconsultFinalizePredicate
(pl-proc.c:1937), thread start/exit (pl-thread.c:762/765/2203/2489/3603, TH1), tabling untable + table_answer_event (pl-tabling.c:10156-10163,
11317), transactions (pl-transaction.c:400, 523), PL_cleanup cleanupEvents (pl-init.c:2037), freePrologLocalData (pl-setup.c:1796).

## Plan (groups; commit after each)
1. [this commit] plan.
2. Structs + fields: pl-incl.jl, pl-global.jl (appended block), pl-copyterm.jl fastheap functions.
3. pl-event.jl: the real port (link_event, get_callback, add_event_hook, get_event_list, register_event_hook, get_event_listp, prolog_listen,
   prolog_unlisten, free_event_callback, destroy_event_list, call_event_list, delayEvent(s), sendDelayedEvents, PL_call_event_hook(_va),
   predicate_update_event, table_answer_event (tabling status deferred), retractall_event); `get_procedure_resolve_namearity` in pl-proc.jl.
4. Wiring at the sites above.
5. Rows (tools: swipl 10.1.19 oracle), mutants tools/mutants/EV1.py, manifest entries, docs/architecture.md block (LAST, own commits).

## State
(see the end of this file; updated after every commit)
