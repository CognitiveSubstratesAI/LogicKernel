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

## STATE (writer 1 hit the context cap after group 2; the next writer starts at group 3)
Commits on wip/ev1 (stacked on wip/bootpred3 e7a0dc2): 94b76b0 (this plan), 6a48518 (group 2: structs + fields + fast heap terms). NOTHING compiled or run.

### Group 2 DONE (6a48518), read-only verified against neighbours
- src/pl-incl.jl: `PLEV_*` Int constants 0..11, `EV_CALLBACK_*`, `P_EVENT_ROLLBACK`, `fastheap_term{T}` (gsize,nvars,code,values = a record's fields),
  `event_callback{T,D}` (name, module_ index, procedure, function_ index, closure, argc, flags), `event_list{T,D}` (callbacks::Vector, first = head),
  `definition.events` appended + outer 11-arg constructor (the four positional sites unchanged), `delayed_event{T}` after `const Procedure{T}`.
- src/pl-global.jl: `event_hooks{T}` (onabort onerase onbreak onframefinish onthreadstart onthreadexit onuntable), GD field `event_hook` appended at
  the END, LD fields `event_buffered`, `event_delay_nesting`, `event_hook_onthreadexit` appended at the END (constructor args appended).
- src/pl-copyterm.jl: `term_to_fastheap(ld,t)`, `free_fastheap`, `put_fastheap(ld,fht,t)` via compileTermToHeap/copyRecordToGlobal.

### Group 3 TO WRITE: src/pl-event.jl (rewrite; replace the partial port and its header). Design already worked out:
- `PL_events` = 12 rows `(id, name::Symbol, argc, local::Bool)` in upstream's order (pl-event.c:79-95; index = id+1; `erase`/`break` resolve to the FIRST row).
- location of a list = `struct event_location{T}(ev::Int, def::Union{Nothing,definition{T}})` (ev -1 = a predicate's `def.events`); helpers
  `event_list_at(gd,ld,loc)` (read), `get_event_list!(gd,ld,loc)` (create, pl-event.c get_event_list), `event_list_set!`; id -> hook field map:
  abort->onabort, erased clause/record->onerase, the four break ids->onbreak, framefinished->onframefinish, untable->onuntable,
  thread start->onthreadstart, thread exit->onthreadexit, this thread exit->`ld.event_hook_onthreadexit` (LEVENT).
- `callEventHook(gd,ld,ev,args...)` = pl-event.h: true when the list is nothing, else `PL_call_event_hook_va`. `PL_call_event_hook` = same (GD->halt.cleaning
  CLN_DATA check: PL_cleanup is not ported, say so).
- `PL_call_event_hook_va(gd,ld,ev,args...)`: pl-event.c:630-715 as read: delay when `ld.event_delay_nesting != 0` (`delayEvent`), `saveWakeup(ld,true)`
  (returns nothing for false), `av = PL_new_term_refs(ld, argc+1)`, per-event put (PL_put_clref(gd,ld,..), PL_unify_recref(gd,ld,..) for a
  RecordRef, break: atoms true/false/retract/exist + clref + PL_put_intptr, frame: `PL_put_frame` (WRITE it in src/pl-trace.jl after PL_unify_frame, from
  pl-trace.c:103-112: PL_put_intptr(t, base) or PL_put_atom(t, :none)), untable: `unify_definition(gd,ld,MODULE_user(gd),av+1,def,0,GP_QUALIFY|GP_NAMEARITY)`,
  THREAD events: `throw NotPortedError{T}` naming TH1 (no thread table: `unify_thread_id` is TH1's), then `call_event_list`, on failure with an exception
  `wakeup_state(w.fid, w.outofstack, w.flags | WAKEUP_KEEP_URGENT_EXCEPTION)` else rc = true, `restoreWakeup`.
- `call_event_list(gd,ld,list,argc,argv)` (pl-event.c:402-455): iterate a SNAPSHOT of the callbacks (listeners may unlisten); the C-function branch
  (`function_ != 0`: register_event_function, PL_thread_at_exit) is TH1's: rc=false there; closure branch `put_fastheap(ld,cb.closure,argv) &&
  PL_call_predicate(gd,ld,module-or-nothing,PL_Q_NODEBUG|PL_Q_PASS_EXCEPTION,cb.procedure,argv)`; else `PL_call_predicate(..., nothing, flags, cb.procedure, argv+1)`;
  break the loop when `!rc && PL_exception(ld,0) != 0`.
- `add_event_hook(gd,ld,list,name,last,closure,argc)` (pl-event.c:121-166): the named-replacement loop (`ev.name == name && function_ == 0`: swap the closure
  with `term_to_fastheap(ld, closure)` of the UNSTRIPPED closure), else a new callback: atom `t` -> `resolveProcedure(gd, pname, argc, gd.modules[m])`,
  else `lookupProcedure(mk_sym(T,:call), argc+1, MODULE_system(gd))` + closure; `link_event` = push!/pushfirst!. `register_event_hook` = get_event_list! then add.
- `get_event_listp(gd,ld,type)` returns `(event_location, argc)` or nothing; a predicate: NEW `get_procedure_resolve_namearity(gd,ld,descr)` in src/pl-proc.jl after
  `get_procedure_find_namearity` (`PL_strip_module(gd,ld,descr,0,head)`, `get_functor_procedure(ld,head)` (name,arity; arity<0 = error), `resolveProcedure(gd,name,arity,gd.modules[mi])`;
  upstream: pl-proc.c:733-790, GP_NAMEARITY|GP_RESOLVE), `(loc(-1,def), 2)`; when it fails, upstream still falls to `PL_domain_error("event", type)`: keep.
- `pl_prolog_unlisten2_va` (pl-event.c:290-345): the delete loop over `list.callbacks` (match `ev.procedure.definition === proc.definition` when the closure is an atom,
  else `put_fastheap(ld,cb.closure,tmp) && PL_unify(ld,A2,tmp)`, `PL_rewind_foreign_frame` on a miss, return false on a pending exception), register it in
  `PL_predicates_from_event` as the THIRD entry with `PL_FA_VARARGS | PL_FA_TRANSPARENT` (upstream's table uses META for it, pl-event.c:808).
  DIVERGES (representation): close the foreign frame at the return (upstream leaves it to the call).
- `delayEvent(ld,ev,args...)`, `delayEvents(ld)` (returns true only at nesting 0 -> 1, else false), `sendDelayedEvents(gd,ld,noerror)::Int` (-1 on error), pl-event.c:466-590.
- `predicate_update_event(gd,ld,def,action::T,cl,flags)`, `table_answer_event(gd,ld,def,action,answer)` (no save/restore_tabling_status: TAB1), `retractall_event(gd,ld,def,head,start::word)`:
  functors by `lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T,:name)), arity)` (`rollback/1`, `:/2`, caller's start1/end1); `PL_cons_functor(ld,h,fd,args...)`.
- `free_event_callback` (nothing to free: no atom GC), `destroy_event_list!(def)`, `cleanupEvents(gd)`.
- Remove the `NotPortedError` for a predicate listener and the "LEFT TO EV1" header text.

### Group 4 TO WRITE (wire the existing sites; pass `ld`)
- `_assertDefinition!` (pl-proc.jl ~l.484): add an `ld::Union{Nothing,PL_local_data{T}}` argument (nothing for the ld-less test overload); after `clause.generation_erased = max_generation(def)`,
  `def.events !== nothing && ld !== nothing && !predicate_update_event(gd, ld, def, mk_sym(T, where_ === CL_START ? :asserta : :assertz), clause, UInt32(0))` ->
  `retractClauseDefinition!(gd, ld, def, clause, false)`; return nothing (return type becomes Union{Nothing,ClauseRef}); upstream pl-proc.c:1472-1478. No TR_BULK (no transactions).
- `retractClauseDefinition!` (pl-proc.jl:568): ADD an `ld` method `(gd, ld, def, clause, notify)` doing `def.events !== nothing && notify && !predicate_update_event(gd, ld, def, mk_sym(T,:retract), clause, UInt32(0)) && return false`
  (pl-proc.c:1706-1712), then `retract_clause!`; switch the callers that have `ld` (pl-proc.jl 900, 979, 995, 1895; pl-rec.jl 928) to it.
- `pl_retractall1_va` (pl-proc.jl:1937; upstream pl-proc.c:3308 `retractall_event(def, thehead, FUNCTOR_start1)` before and :3397 `FUNCTOR_end1` after): read both upstream sites first.
- erase record: pl-rec.jl:931 `rc = callEventHook(gd, ld, PLEV_ERASED_RECORD, rref)` and its DIVERGES comment (pl-rec.c:2468); frameFinished (pl-wam.jl:1083, pl-wam.c:949-962: READ it, the
  `FR_NOTIFY`-style test and the call `callEventHook(PLEV_FRAMEFINISHED, fr)`), announceErasedClause (pl-proc.c:1773, 1850: in the cleanDefinition pass, `cleanDefinition!` has no ld: check whether the
  Julia pass runs where the hook can be called; else DEFERRED with the reason), `resetProcedure`/`unallocDefinition` -> `destroy_event_list!` (pl-proc.c:268, 408: Julia has no unallocDefinition; resetProcedure: find it).
- Boot: `:- initialization prolog_listen(untable, untable_reconsult)` (boot/tabling.pl:300-301) goes through `prolog_listen/2` with an atom closure `untable_reconsult` (module = context = `$tabling`/`system`):
  `resolveProcedure(gd, :untable_reconsult, 1, module)` creates an undefined procedure: matches upstream.

### Groups 5-7 TO WRITE: rows (swipl 10.1.19 oracle, LC_ALL=C, precedent ~/code/lk-q10/evidence/Q10/gen_rows.py: registration/removal, delivery order `as(first|last)`, `name(N)` replacement,
unlisten of an atom and of a closure term, predicate events on assert/retract/retractall/erase (the PI form `foo/1`, actions asserta assertz retract retractall(start/end) erase),
`erase` of a record, bad options (`as(middle)` domain_error, unknown event domain_error `event`, `prolog_listen(1, G)` type_error callable, non-callable closure type_error callable); test file
test/core_lang/test_event_swipl.jl; non-vacuity block; mutants tools/mutants/EV1.py (anchors once each; TARGETS = test_event_swipl.jl, test_bootpred3_swipl.jl (prolog_listen) and every file calling
assert/retract/retractall/erase: pick by `grep -l`), static_analysis_manifest entries, docs/architecture.md block appended LAST (own commits). Stale-pin hunt (GATE-PLAYBOOK): grep test/ for
`prolog_listen`, `NotPortedError.*EV1`, "EV1" and fix every pin that names the old partial port (test/core_lang/test_bootpred3_swipl.jl rows for a predicate listener).

### SITES SUMMARY (for the audit)
WIRED when groups 3-4 land: assertDefinition (pl-proc.c:1472), retractClauseDefinition (:1709), retractall (:3308, :3397), erase record (pl-rec.c:2468), frameFinished (pl-wam.c:959).
DEFERRED (no Julia function yet), each owned by the step that ports the function: clearBreakPointsClause and `$break_at` (pl-comp.c:9084-9173, DBG1), `restore_after_exception` abort
(pl-pro.c:105), `unloadFile`/`endReconsult` delayEvents (pl-srcfile.c:804/835, 1604/1639, reload step), `reconsultFinalizePredicate` (pl-proc.c:1937), thread start/exit/this-thread-exit and
`PL_thread_at_exit` register_event_function (pl-thread.c:762/765/2203/2489/3603, TH1), untable raise (pl-tabling.c:11317) and `table_answer_event` (pl-tabling.c:10156-10163, TAB1), transactions
(pl-transaction.c:400/523), `cleanupEvents` (pl-init.c:2037, PL_cleanup), `freePrologLocalData` (pl-setup.c:1796).

### FLAGS for the audit (D-0353: each DIVERGES needs a D-entry before it is relied on; all representation-only)
1. `fastheap_term` = the term's record (pl-copyterm.h cells need the word stacks); attributed variables in a closure: unchecked whether compileTermToHeap keeps attributes (upstream's duplicate_term keeps them).
2. `event_list` = a vector (no head/tail chain, no lock); callbacks iterated as a snapshot.
3. definition.events typed `event_list{T, definition{T}}`; positional constructor sites kept by an outer 11-arg constructor.
4. THREAD events and the C-function listener branch: TH1 (no thread table, no C function pointers).
5. The foreign frame of prolog_unlisten/2 is closed at the return.
6. Base: wip/bootpred3 is paused and not gated; this branch carries its commits.

### Gate agent runs (when groups 3-7 are done)
fmt (committed files via `warm.sh send`), `warm.sh inventory`, check, rows x3, test_type_discipline, tools/pkgtest_way.sh test/core_lang/test_event_swipl.jl, push mutants/EV1 then gate/ev1 at the same SHA,
alloc pins x3 (GD/LD/definition struct change: Tier 1), full CI + battery. Branches created by this writer: wip/ev1 only (no deletes).

## WRITER 2 STATE (hit the context cap during group 4; the next writer starts at "REMAINING" below)
Commits on wip/ev1: group 3 = the commit after 731b2ba, subject "UPSTREAM: pl-event.c event lists, prolog_listen, prolog_unlisten, call side": src/pl-event.jl REWRITTEN as the
real port (event_type, PL_events 12 rows, event_location, event_list_at/event_list_set!, link_event, get_callback, add_event_hook, get_event_list!, register_event_hook, get_event_listp(gd,ld,type)
-> (loc,argc), prolog_listen/2,3, prolog_unlisten/2 (3rd entry of PL_predicates_from_event, TRANSPARENT), free_event_callback, destroy_event_list!(gd,ld,loc|def), cleanupEvents(gd,ld),
call_event_list (snapshot), delayEvent/delayEvents/sendDelayedEvents, callEventHook, PL_call_event_hook(_va), predicate_update_event, table_answer_event, retractall_event(gd,ld,def,head,:start|:end));
PL_put_frame in src/pl-trace.jl; get_procedure_resolve_namearity in src/pl-proc.jl; LogicKernel.jl include comment. NOTHING compiled or run (read-only verified against neighbours).

### GROUP 4 (committed TOGETHER with this handoff, because the commit hook refuses a partial index; subject "MODIFIED: wire the event raise sites ..."; REMAINING item 1 is done)
- src/pl-proc.jl: `_assertDefinition!(gd, ld::Union{Nothing,PL_local_data}, def, clause, where_)` (5-arg; the 4-arg method delegates with `nothing`, so test/static_analysis_manifest.jl:1378-1379 stay valid)
  raising predicate_update_event (asserta|assertz) and, on a veto, `retractClauseDefinition!(gd, def, clause, false)` + `nothing` (pl-proc.c:1472-1478); `assertDefinition!` passes `ld`.
  NEW method `retractClauseDefinition!(gd, ld, def, clause, notify)` (pl-proc.c:1706-1712; the 4-arg without events stays); callers switched to it: pl_retract! (2 sites), pl_retractall! (2 sites), pl_retract1_va, pl-rec.jl erase.
  `pl_retractall!`: start event after the dynamic check (pl-proc.c:3308), `end` event after the pop only when rc && `send` (upstream returns early, no `end`, when there is no first clause or the clause choice ends: faithful flag `send`);
  `rc = false` when a retract fails with a pending exception (upstream `rc = retractClauseDefinition(...)`; before EV1 that could not happen). `announceErasedClause(gd,ld,clause)`; `cleanDefinition!(gd, ld, def, ddi, start, rcp::Ref{Bool})`
  (6-arg; the 3-arg method for the tests delegates), `pl_garbage_collect_clauses!` passes `rcp` and sets `rc = rcp[]` (pl-proc.c:2729).
- src/pl-rec.jl: erase of a record `rc = callEventHook(gd, ld, PLEV_ERASED_RECORD, rref)` (pl-rec.c:2468) + header comment.
- src/pl-wam.jl: frameFinished raises PLEV_FRAMEFINISHED for an FR_NOTIFY frame (pl-wam.c:959), comments of frameFinished/frameFailed updated.
Signature changes to list for the audit (flag 5): `_assertDefinition!` gains a 5-arg method, `retractClauseDefinition!` an `ld` method, `cleanDefinition!` a 6-arg method; the old methods are KEPT (no textual conflict, manifest entries valid).

### REMAINING
1. Commit the uncommitted group 4 above (check `git diff` first; `warm.sh` nothing run yet).
2. `resetProcedure`/`unallocDefinition` destroy_event_list (pl-proc.c:268, 408): `grep -n "resetProcedure\|unallocDefinition\|abolish" src/pl-proc.jl` found nothing checked yet; if Julia has no such function, list as DEFERRED (abolish step) and say so in the final list.
3. Group 5: oracle rows (swipl 10.1.19, LC_ALL=C, two identical runs; precedent ~/code/lk-q10/evidence/Q10/gen_rows.py): test/core_lang/test_event_swipl.jl (registration/removal, `as(first|last)`, `name(N)` replacement, unlisten of an atom and of a closure,
   predicate events asserta/assertz/retract/retractall(start/end: NOTE the `end` event is skipped on the early returns)/erase, record erase, bad options: as(middle) domain_error(as,middle), unknown event domain_error(event,..), non-callable closure type_error(callable,..), `foo/a` PI),
   and the `untable` event only through boot (boot/tabling.pl:300-301 must keep working: prolog_listen(untable, untable_reconsult) with an atom closure).
4. Stale-pin hunt: test/core_lang/test_bootpred3_swipl.jl is the ONLY test file naming prolog_listen/prolog_unlisten: rows pinning the NotPortedError / "hook not kept" must follow the real port (internal-identity expectation + one-line disclosure, or report).
5. tools/mutants/EV1.py (anchors once; TARGETS: test_event_swipl.jl, test_bootpred3_swipl.jl, plus every test file calling assert/retract/retractall/erase: grep -l), validate with a throwaway python3 -I + runpy checker; manifest entries (test/static_analysis_manifest.jl: the new 5-arg `_assertDefinition!`, `retractClauseDefinition!` with ld, `cleanDefinition!` 6-arg, event functions) and a docs/architecture.md block, appended at the END, each in its own commit. No `@enum` was added (no `_enum_hash` entry).
6. Verified vs read-only: all of the above is read-only (types checked against the neighbours by reading: wakeup_state, PL_call_predicate, PL_put_clref, unify_definition, FUNCTOR_colon2, Clause{T}); nothing compiled. Possible compile traps for the gate agent: `Procedure{T}` as a type assertion inside event_callback.procedure (a `procedure{definition{T}}`), `PL_new_term_refs` returns 0 on failure,
   `getfield(gd.event_hook, Symbol)` dynamic, `delayed_event{T}` constructor positional (type, clause, offset, proc).
### DEFERRED sites (no Julia function yet; each owner raises when its step lands)
breakpoint events DBG1 (pl-comp.c:9084-9173), abort raise (pl-pro.c:105), delayEvents in unloadFile/endReconsult (pl-srcfile.c:804/835, 1604/1639: reload step), reconsultFinalizePredicate (pl-proc.c:1937), thread start/exit + PL_thread_at_exit + register_event_function (TH1), untable raise (pl-tabling.c:11317) and table_answer_event call (TAB1), transactions (pl-transaction.c:400/523), cleanupEvents caller (PL_cleanup, pl-init.c:2037), freePrologLocalData (pl-setup.c:1796).
### Gate agent runs (after groups 5-7): see "Gate agent runs" above.
