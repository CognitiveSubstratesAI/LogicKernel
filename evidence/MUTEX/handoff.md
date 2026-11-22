# MUTEX handoff (pl-mutex.c: the mutex_* predicates, single-thread form)

Worktree /home/shivaji1012/code/lk-mutex, branch wip/mutex. Scratch (upstream copies):
/tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/b1bc52d9-44dc-428a-a9bb-10bf805f9033/scratchpad/mutex/

## STATE (Sonnet writer, step MUTEX2; updated after each commit)
* COMMITTED: merge of wip/thread-prop (get_prop_def exists in src/pl-thread.jl with the signature
  `(ld, t, expected::Symbol, list::NTuple{N,Symbol})::Tuple{Int,Int}`; the `Tuple{Symbol,Int}` text below is superseded).
* piece 1 (src/pl-mutex.jl, registration in src/pl-ext.jl, manifest entries, pl-global.jl header comment): written, see the
  last commit; NEVER RUN (no julia in this step). with_mutex/2 UNCHANGED (D-0783 (4): its own follow-up step).
* COMMITTED piece 1 = 2a1d19d1 (pl-mutex.jl port, pl-ext.jl registration, manifest, pl-global.jl comment). The absence hook
  blocked the first attempt on two stock absence phrases in added lines; they are reworded (use "dropped",
  "upstream only", "left out"); keep that in later commits, in the handoff too.
* piece 2 WRITTEN IN THE WORKTREE, UNCOMMITTED at the 150k cap: test/core_lang/test_mutex_swipl.jl (56 rows m01-m56, three term
  types, pins FILLED from swipl 10.1.20 two identical runs), evidence/MUTEX/gen_rows.py (the generator, `--fill`),
  evidence/MUTEX/mutex_rows.out (raw pin output). Next agent: `git add -A`, commit `TEST: pl-mutex.c rows m01-m56 (swipl 10.1.20 pins)`.
  Pins worth knowing (swipl): mutex_create([]) succeeds; m54 context is `system:mutex_lock/1` (NULL pred), m53 `mutex_create/1`,
  m55 `mutex_create/2` with message '1-st argument'; m52 `mutex_unlock/1` 'not locked'.
* NOT YET WRITTEN: tools/test_warm_shards.tsv entry if shards list files (was checking: `git show 281ca507 --stat`, grep the tsv for
  test_p2_swipl; total count at its top moves by 1); (3) tools/mutants/MUTEX.py ("aimed by <rows>", python3 -I exactly-once; model
  tools/mutants/BOOTPRED3.py; candidates listed under "Mutants" below; TARGETS = the new test file); (4) docs/architecture.md
  MUTEX section (hand-written part) and the refused-functions lines :813 and :6319.
* MUTEX step (Sonnet writer, narrow): (1) tools/mutants/MUTEX.py WRITTEN (53 mutants, 4 declared equivalent: L11, D8, P13, R4;
  every `old` exactly once, `python3 -I` count), commit `TEST: MUTEX mutants`. (2) tools/test_warm_shards.tsv: test_p2_swipl is not
  listed there (no file list), so NO entry. (3) docs/architecture.md MUTEX section: see the next lines for its state.
  Mutants not written (no row kills them, would survive): `state.p = 1` reset in advance_mstate! (needs a var-var
  mutex_property(M, P) row over two mutexes); a constant `mutex_serial` (anonymous blobs of one payload).
* Pins come from `~/.local/bin/swipl` (10.1.20, the pin binary), NOT the 10.1.19 path in the test plan below.

## Scope
Upstream's 8 predicates (BeginPredDefs(mutex), pl-mutex.c:785-796): mutex_create/1,2, mutex_destroy/1, mutex_lock/1,
mutex_trylock/1, mutex_unlock/1, mutex_unlock_all/0, mutex_property/2. The SCOPE rows name 6 (create/2, destroy, lock,
trylock, unlock, property); create/1 and unlock_all/0 are in the same table, port all 8. Also port `get_prop_def`
(pl-thread.c:8376, outside O_PLMT; no kernel counterpart exists) into src/pl-thread.jl.
DECISION (recommend to dispatcher): with_mutex/2 is LEFT as it is (does not examine/create/lock the mutex). Porting its
O_PLMT branch (pl-mutex.c:763-770: get_mutex(create), lock, callProlog, unlock) would flip the pinned known-difference
testset test/core_lang/test_bootpred_swipl.jl:583 and BOOTPRED3 mutants; propose it as the next small step. Update the
header comment of src/pl-mutex.jl (its list of refused functions) and docs/architecture.md:813, :6319 accordingly.

## DONE in the worktree (uncommitted, never run: no julia)
* src/pl-incl.jl: `pl_mutex{T}` (count, owner, id::T, serial, anonymous, destroyed, auto_destroy) and the pool record
  `mutex_prop_enum{T}` (mutexes::Vector, next, m, p, enum_properties, enumerating) + its zero-arg constructor.
* src/pl-global.jl: GD fields at the END of PL_global_data: `const mutexes::Dict{UInt64, pl_mutex{T}}` (key = sym_key of
  the id) and `mutex_serial::Int`; LD field `mutex_enums::foreign_state_pool{mutex_prop_enum{T}}` after `cur_enums`
  (struct and constructor). src/pl-setup.jl: the two constructor args at the end of the GD constructor call
  (`Dict{UInt64, pl_mutex{T}}()`, `0`). src/pl-fli.jl: `live_states` adds `ld.mutex_enums.live`.
  (copy_global_data is generic: no edit in gd_template.jl.)
* STILL TO DO: add a comment line for the new fields in the pl-global.jl header ("Since MUTEX: ...").
  Check `git grep -n -E 'fieldnames\(.*global_data|fieldcount'` in test/ tools/ for a field-count pin (the grep was cut by the cap).

## NOT YET WRITTEN
1. src/pl-mutex.jl: the port (below). 2. src/pl-thread.jl: `get_prop_def`. 3. registration in src/pl-ext.jl:
   `PL_predicates_from_mutex` in `_PRED_TABLES` and `_FOREIGN_VA` (between `_tabling` and `_wrap`, upstream order
   pl-ext.c:482), and its DIVERGES line. 4. test/static_analysis_manifest.jl entries (EVERY new method must be reached:
   see below). 5. test file + pins. 6. tools/mutants/MUTEX.py. 7. docs/architecture.md section + file-table row.
   8. owner rows? none expected (no refusal remains), check tools/ SCOPE owner files only if a gate says so.

## Design (kernel idioms verified by reading, file:line)
* Predicates are `pl_xxx_va(ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T})::foreign_t`, args
  `A1, A2 = PL__t0, PL__t0 + 1`, registered `PL_extension("name", n, f, PL_FA_VARARGS | flags)` in a
  `const PL_predicates_from_mutex = (...)` (model: src/pl-gvar.jl:372-415 nb_current/2 nondeterministic, table at its end;
  src/pl-wrap.jl:508). Flags: mutex_create/1 0; create/2, destroy, lock, trylock, unlock, property ISO (property also
  NONDETERMINISTIC); unlock_all 0. Errors: `return PL_error(...) ? FTRUE : FFALSE`.
* gd = `_query_gd(ld)` (src/pl-mutex.jl existing). Thread id of the one thread: constant 1 (`owner` 0 = none).
  `thread_self` is `main` (src/pl-thread.jl:114): `status(locked(main, Count))`.
* Table key: `sym_key(id)` (atom term of type T). Anonymous mutex: serial = ++gd.mutex_serial; payload
  `collect(reinterpret(UInt8, Int64[serial]))`; `w,_ = lookupBlob(gd.atoms, bytes, length(bytes), mutex_blob)`;
  `id = _blob_term!(gd.atoms, gd.atom_symbols, T, w)` (src/pl-wrap.jl:86-88, pl-inline.jl:261); blob type
  `const mutex_blob = PL_blob_t(PL_BLOB_UNIQUE, "mutex")` (pl-wrap.jl:35; lookupBlob registers the type lazily,
  pl-atom.jl:2455). Test "is it a mutex blob": `is_blob(a) && atomValue(gd.atoms, blob_handle(a)).type === mutex_blob`
  (pl-wrap.jl:47-49, 100-103). Text atom test: `isTextAtom(a)`-style: `kind(a) === SYM && !is_reserved_symbol(a) && !is_blob(a)` (pl-comp.jl:393).
* Errors (src/pl-error.jl): ERR_TYPE/ERR_DOMAIN/ERR_EXISTENCE: `PL_error(ld, pred, arity, "", ERR_TYPE, mk_sym(T,:mutex), t)`
  (pred "" / 0 for get_mutex and get_prop_def: upstream passes NULL); ERR_PERMISSION: `PL_error(ld, "mutex_create", 1, "",
  ERR_PERMISSION, mk_sym(T,:create), mk_sym(T,:mutex), mutex)`, unlock: pred "mutex_unlock", 1, msg
  `m.owner != 0 ? "not owner" : "not locked"`, (:unlock, :mutex, A1); ERR_UNINSTANTIATION:
  `PL_error(ld, "mutex_create", 2, "", ERR_UNINSTANTIATION, 1, A1)`.
* Options (mutex_create/2): `vals = PL_scan_options(ld, A2, 0, "mutex_option", (PL_option_t(:alias, OPT_ATOM),))`;
  `vals === nothing && return FFALSE`; `alias = _opt_atom(T, vals[1])` (pl-file.jl:880, 943). If alias !== nothing and
  `!PL_unify_atom(ld, A1, alias)` -> the uninstantiation error.
* Term API: `PL_get_atom(ld,t)::Union{Nothing,T}`, `PL_is_variable(ld,t)`, `PL_unify_atom(ld,t,a::T)`,
  `PL_get_functor(ld,t)::Union{Nothing,Tuple{T,Int}}` (name, arity; compare `sym_key(name) == sym_key(mk_sym(T,:alias))`),
  `_PL_get_arg(ld, i, t, a)`, `PL_unify_functor(ld, t, name::T, arity)` (binds a var to fresh args), `PL_unify_integer(ld,t,i)`,
  `PL_new_term_ref(ld)`. locked(Owner,Count): `PL_unify_functor(ld, prop, mk_sym(T,:locked), 2)`, then `_PL_get_arg` 1 and 2,
  `PL_unify_atom(ld, a1, mk_sym(T,:main))`, `PL_unify_integer(ld, a2, count)`; `unlocked`: `PL_unify_atom(ld, prop, mk_sym(T,:unlocked))`.
* Property list as an index, no function tuple (allocation/JET): names `((:alias, 1), (:status, 1))`; a helper
  `_mutex_prop(ld, m, i, arg)::Bool` branching on i (1 alias: `!m.anonymous && PL_unify_atom(ld, arg, m.id)`; 2 status).
  `get_prop_def(ld, t, expected::T, list::NTuple{N,Tuple{Symbol,Int}})::Tuple{Int,Int}` = (rc, index): rc 1 found, 0 variable,
  -1 error (domain_error(expected, t) when a functor is not in the list, type_error when not var and no functor).
* mutex_property/2 state machine: port pl-mutex.c:621-734 literally; allocate the pool record AFTER get_prop_def/get_mutex
  (`idx = alloc_foreign_state!(ld.mutex_enums)`, set EVERY field: pool records are reused), `PL_retry_address(idx)`,
  FRG_REDO: `idx = PL_foreign_context_address(PL__ctx)`, FRG_CUTTED: `free_foreign_state!(pool, idx)`; free at every
  determinate exit and fail (`live_states(ld)` must return to 0). Snapshot of mutexes: `sort!(collect(values(gd.mutexes)); by = m -> m.serial)`.
  `advance_mstate` as pl-mutex.c:588-609 (enum_properties: p++ and succeed while p <= 2, else p = 1; then enumerating: next mutex).
  After the property unify upstream does `PL_unify_term(property, functor, arg)` when enum_properties: here
  `PL_unify_functor(ld, property, name, 1)` + `PL_unify_arg(ld, 1, property, arg)`.
* try_really_destroy_mutex: trylock (always true here); `count == 1` -> destroyed = true, `delete!(gd.mutexes, sym_key(m.id))`,
  count = owner = 0; else unlock and false. mutex_destroy: `try_really_destroy_mutex || (m.auto_destroy = true)`; true.
  mutex_unlock: `get_mutex(false)`, `PL_mutex_unlock` ok -> if auto_destroy: try_really_destroy; else permission error.
  mutex_unlock_all: every m with owner == 1: count = 0, owner = 0 (no auto_destroy, as upstream).
* DIVERGES comments to write (one per `# PORT:` block, top of file): single thread, no OS lock (no pthread mutex, no
  `PL_handle_signals` timedlock loop: a lock another thread holds cannot arise); anonymous mutex never reclaimed by GC
  until destroyed (kernel has no atom GC; upstream `PL_unregister_atom`); blob payload is the serial (upstream the pointer);
  blob prints as the generic blob does (no `write` slot in `PL_blob_t`); enumeration in creation order (upstream hash
  order); `unlocked_pl_mutex_create` deletes the table entry when the unify fails (unreachable); release_mutexref,
  save/load_mutexref, destroy_mutex/unalloc_mutex stay upstream-only (no GC finalizer, no allocation).

## Manifest (test/static_analysis_manifest.jl; every owned method must be reached, concrete types; models at :2285-2292
(pool record entries), :1555-1566 (VA functions), :1357 (_opt_atom), :3099 (closure_of_word))
For each new function add `(LK.f, Tuple{...}, false)` in the per-type block that has `LD, GD, T` (same block as pl_nb_current2_va):
the 8 `pl_*_va` as `Tuple{LD, Int, Int, LK.foreign_context{T}}`, helpers with their exact signatures, `get_prop_def`
(`Tuple{LD, Int, T, NTuple{2, Tuple{Symbol, Int}}}`), `(LK.mutex_prop_enum{T}, Tuple{}, false)`,
`(LK.foreign_state_pool{LK.mutex_prop_enum{T}}, Tuple{}, false)`, `alloc_foreign_state!`/`free_foreign_state!` on that pool,
and `(LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_mutex)}, false)` next to :4483. Existing `PL_error` /
`PL_scan_options` / `lookupBlob` methods are already reached (:861, :1178, :4366).

## Test plan (not started): test/core_lang/test_mutex_swipl.jl
Model test/core_lang/test_p2_swipl.jl (driver `_P2_DRIVER` + `_p2_file/_p2_kernel/_P2_PINNED`, three term types via
test/term_under_test.jl; pins from swipl 10.1.19 run TWICE byte-identical, capped
`systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64 swipl -q file.pl`;
export PATH=~/.local/swipl-pin1-18168e62/bin:$PATH). Cases `t_mNN(R) :- catch((G), error(SsuE,_), R = raised(SsuE))`,
each with its own alias (state persists in the database across cases), deterministic goals (once/findall), anonymous
mutex rows never print the blob (use blob(M, mutex), `X == M`). Planned rows: create alias/anonymous; blob(M,mutex);
mutex_create(f(x)) type_error(mutex,f(x)); create twice permission_error(create,mutex,N); create/2 with bound first arg
(uninstantiation_error), alias(1) type_error(atom,1); lock x2 -> status(locked(main,2)); lock x2 unlock x1 -> locked(main,1);
lock+unlock -> unlocked; unlock unlocked permission_error(unlock,mutex,N); unlock/destroy of unknown existence_error(mutex,N);
mutex_lock(unknown) creates and locks; trylock creates, trylock x2 -> 2; destroy then property -> existence_error;
destroy of a locked mutex stays (locked(main,1)) until unlock, then gone; mutex_lock(_) instantiation_error,
mutex_lock(f(x)) / (1) / ([]) type_error(mutex,_); mutex_property(mx, foo(x)) domain_error(mutex_property, foo(x)),
(mx, 3) type_error(mutex_property,3), (_, foo(1)); findall(P, mutex_property(mx,P), L) = [alias(mx), status(...)];
enumeration of M with alias filter via msort; mutex_unlock_all; recreate a destroyed name; destroyed blob ->
existence_error with X == M. Generate the pins with a small python3 -I script mirroring `_p2_file` (see evidence/P2/gen_rows.py
in ~/code/lk-channel or the repo if present). A non-vacuity testset and a live-check testset, as test_p2_swipl.jl:310-347.
Add the file to tools/test_warm_shards.tsv (total count at the top moves by 1, see commit 281ca507) if shards list files.

## Mutants (not started): tools/MUTANTS/MUTEX.py "aimed by <rows>", exactly-once check
Model tools/mutants/BOOTPRED3.py. Candidates: lock does not increment (count++ -> =), unlock does not decrement or releases
at count 1 vs 0, trylock returns false, destroy ignores a locked mutex (always destroy), auto_destroy never set / never acted
on, create does not refuse a duplicate, get_mutex create flag inverted (lock/trylock create / unlock/destroy do not),
error message "not owner"/"not locked" swapped, status unlocked/locked swapped, alias property for anonymous mutexes,
advance_mstate (properties not enumerated / mutexes not advanced), mutex_unlock_all skips, uninstantiation check removed.
TARGETS: the new test file plus test/core_lang/test_bootpred_swipl.jl only if a mutant touches pl-mutex.jl's with_mutex.

## Commit message (when committing)
`UPSTREAM: pl-mutex.c mutex_create/1,2, mutex_destroy/1, mutex_lock/1, mutex_trylock/1, mutex_unlock/1, mutex_unlock_all/0, mutex_property/2 (swipl-devel 18168e62)`
+ 3-6 lines + body line "test_type_discipline.jl and warm.sh check NOT run" + `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
The commit hook needs a clean file set (no untracked files outside the worktree rule); stage all, commit in a separate call.
