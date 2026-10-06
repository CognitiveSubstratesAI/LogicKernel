# LogicKernel architecture

## The rulebook: swipl-devel, as is

Decided 2026-10-03 (user): **LogicKernel follows swipl-devel as is — its logic, its data structures,
its semantics.** Where SWI uses a mechanism, the kernel uses that mechanism; a departure is a
`# DIVERGES:` with its reason, never a design preference. Two consequences that differ from Core:

* **Bindings use SWI's trail with marks.** Unification binds in a mutable binding store and records
  each binding on a trail; `Mark` before an attempt, `Undo` back to it afterwards — `pl-prims.c`'s
  `do_unify` and `pl-wam.c`'s `do_undo`, under upstream's names. The workspace's execution rules
  (sink/continuations, no choice points, no trail) govern **Core**, not the kernel's internals.
* **Grounded values unify by SWI's identity, not by `==`.** In the reference term type, `1 = 1.0`
  fails, `0.0 = -0.0` fails (floats compare by bit pattern), and a NaN unifies with an identical NaN.
  MeTTa's `==` matching belongs to Core's implementation of the term interface, which supplies its own
  `gnd_equal`/`gnd_key` — the separation the interface exists for.

## Commit messages follow SWI's categories

Decided 2026-10-03 (user), from that date on (history is not rewritten). Every commit message starts
with a category, as SWI-Prolog's history does, so the history can generate a changelog and match
ports against upstream:

* `ADDED:`, `FIXED:`, `ENHANCED:`, `MODIFIED:`, `DOC:`, `TEST:`, `CLEANUP:`.
* `UPSTREAM:` for a commit that ports or syncs code from swipl-devel (or scryer-prolog, swipl-bench).
  It names the upstream file(s), the functions and the upstream commit, e.g.
  `UPSTREAM: pl-wam.c PL_open_query/PL_next_solution (swipl-devel bae881a2)`. It is never `PORT:`,
  which in SWI means a platform port.

**Enforced by git itself** (since 2026-10-03): `tools/githooks/commit-msg` refuses a message without a
known prefix. Git hands it the final message file however the message was supplied, and it applies to
every committer. Install it once per clone with `git config core.hooksPath tools/githooks`;
`tools/run_tests.sh` refuses a full run without it. Its contract, both sides, is
`test/test_commit_msg_hook.jl`. It replaces a workspace-side check of the command text, which is now
retired.

## A full run of `tools/run_tests.sh` is the commit gate

Besides the suite, a FULL run first refuses to start unless:
* the commit-msg hook above is installed;
* the tree is Blue-formatted, checked as CI's Format job checks it (`format(".")` without writing),
  with the JuliaFormatter version CI pins — read from `.github/workflows/CI.yml`, so the two cannot
  drift.

So a formatting slip stops the commit locally instead of turning CI red afterwards. A single-file
run (`tools/run_tests.sh test/x.jl`) is for iteration and skips both checks; it is never evidence.

**The warm lane is for iteration, never evidence (user, 2026-10-03).** `tools/warm.sh` keeps one
daemon with LogicKernel loaded under Revise (`tools/warm_session.jl`) for single files on every term
implementation, mutation proofs, the bench and probes. A long-lived process is where state leaks
hide — values of a type's old layout, test residue, an update that failed partway (in Core a
setting left off in a daemon faked a green result, and a polluted daemon made a bisect name the wrong
file) — so evidence is a process that started clean. The daemon follows Revise's own documentation:
* it starts from the last precompile cache and revises it to the source (`Revise.stale_load`),
  instead of re-precompiling; revision is manual (`JULIA_REVISE=manual`), before every snippet;
* a struct edit needs no restart (Julia ≥ 1.12 redefines types); the second implementation is
  tracked in `:eval` mode, so its structs and constants revise too;
* an edit to a file defining a macro, a `@generated` function or a type alias (`const Clause{T} =
  clause{…}`) re-evaluates the whole module, which Revise would not propagate otherwise;
* a failed update, a queued Revise error or a cache rewritten by another process REFUSES the
  snippet; snippets run through `invokelatest`; Revise's audit trail (`debug_logger`) is reported
  with every snippet, and a `src/` Revise is not watching refuses the daemon's start;
* `start` PRECOMPILES the current source into the daemon's depot first (no daemon is running then,
  so no cache can be refused), and `stale_load` starts from a cache that IS the source. Evidence
  compiles elsewhere, so that cache had only aged: measured, a start revised 445 methods;
* the static-analysis gate's method walk counts only methods CURRENT in this world
  (`_current_method`): since Julia 1.12 a redefined method stays in the table with its world range
  closed, and a revised daemon showed every one of them as "NOT CHECKED" (a control pins it);
* a checkout COPY (parallel mutation proofs) runs its own daemon with `LOGICKERNEL_WARM_DEPOT`: a
  depot of its own and a normal load, since `stale_load` would take the original's cache and watch
  ITS `src/` (the "not watching" guard refused exactly that, measured);
* **`tools/warm.sh preflight`, before every full run (user, 2026-10-04: "do not waste time on cold
  starts"):**
  * the fast checks fail fast: Blue formatting, as CI checks it, and `port_check`;
  * then, while the evidence workers pre-warm for the tree (`pool`): the static-analysis gate (26 s
    warm, against ~200 s in a cold worker) and every test file changed since HEAD, on every
    implementation.
  MEASURED the day it was built: two of three cold runs (~11 min each) had failed on exactly those
  checks, port_check and JET;
  * **it RECOVERS from a stale daemon** (user, 2026-10-04: "make the gate recover, not just
    detect"). Revise can leave a deleted method alive in the daemon: Julia's method table keeps it,
    and the manifest gate's live-method filter (`which(m.sig) === m`) cannot tell it from a live one,
    so the gate reports it NOT CHECKED. That is a daemon condition, not a code failure: evidence
    runs are fresh processes and never see it (measured in V1 L2: `_decompiled!`).
    * Each NOT CHECKED name is classified from the SYNTAX TREE of every file under `src/`
      (port_check's `definitions`): STALE when no file defines it, REAL otherwise.
    * When that gate's coverage test is the preflight's ONLY failure and every name is STALE, the
      daemon restarts and the preflight reruns ONCE. The rerun's verdict is the verdict; a failure
      after the restart is reported REAL.
    * It never suppresses a NOT CHECKED: the only way to pass is a clean rerun in a fresh daemon.
      Any other failure, or a REAL name, fails at once, with the names classified;
* evidence processes compile into their own depot, `.warm/evidence-depot`, ahead of the user's
  (`_evidence_depot_path`; a bare trailing `:` would DROP `~/.julia`, measured). So a precompile for
  evidence never rewrites the cache the daemon loaded — which the daemon rightly refuses to revise
  past — and the pool warms while the daemon works;
* the daemon starts only under the PINNED swipl (tools/SWIPL_VERSION), checked in the daemon itself
  (`tools/swipl_pin.jl`); it runs with its caller's PATH, as a systemd service would otherwise start
  from systemd's own (see the evidence run below);
* the include list of src/LogicKernel.jl stays LITERAL `include("…")` lines: Revise notices a removed
  include only for a literal path (any generated list, M1's included, must write literal lines).
`tools/test_warm.sh` tests all of it (the preflight fails fast on a planted port_check violation,
fails BY THE TEST'S OWN VERDICT on a planted failing changed test file, and passes on the tree as it
is). Its stale-daemon cases go both ways:
* a daemon-only method is STALE, and the restarted rerun PASSES;
* a method loaded from source under a name no syntax tree shows (`@eval` of a built name) is
  classified STALE, but still fails after the restart, so it is REAL;
* a method defined in source by name is REAL at once, with no restart.

The verdict, Revise's refusal, Revise itself, the daemon's pin check and the PATH it is given are
mutation-proved.

**Evidence: a SHARDED run in fresh processes (user, 2026-10-03).** The suite is single-threaded and
this machine's CPU is old (a 2012 i7-3630QM, 4 cores): a full run took 10–16 min on one core, 2m44s
in CI. A full `tools/run_tests.sh` now splits it across fresh worker processes (`tools/worker.jl`,
count from cores and memory — 3 here; `LOGICKERNEL_SHARDS` overrides, `=1` the old single process):
* a unit is one test file on one term implementation; workers CLAIM units, costliest first, by an
  atomic `mkdir` in a directory made fresh for the run (`.evidence/<run id>/`), so they balance
  themselves and a killed run's claims can never make a later one skip units;
* each worker logs the exact sequence it ran; `LOGICKERNEL_REPLAY=.evidence/<run>/seq_<k>.tsv
  tools/run_tests.sh` replays one in order, in one process — never evidence;
* one precompile before any worker; workers run with `JULIA_PKG_PRECOMPILE_AUTO=0`;
* workers never load Revise, run once, and REFUSE a run whose tree fingerprint differs from the one
  they started with; `tools/warm.sh pool` pre-warms them for the current tree;
* each worker USES JET and AllocCheck once on a function of no package before it reports `ready`:
  their own compilation (18.7 s in a fresh process, measured) is then paid while the worker waits in
  the pool, not inside the timed run; nothing of LogicKernel is analysed early;
* 🔴 each worker checks the PINNED swipl where it runs (`tools/swipl_pin.jl`), refusing to start
  (exit 4) under any other, and runs with the coordinator's PATH. A `systemd-run --user` SERVICE
  starts from systemd's own environment, not its caller's: MEASURED 2026-10-04, that PATH found
  `/usr/local/bin/swipl` 10.1.12 while the coordinator's shell found the pinned 10.1.16, so the
  coordinator checked the pin in one environment and every differential of `18b0829`'s evidence run
  ran in the other — against 10.1.12. (CI, which installs 10.1.16, was green on that commit. Single-
  process runs use `--scope`, which inherits the caller's environment, so earlier evidence was
  against the pin.)
* only the coordinator gives the verdict — every shard green, every unit run EXACTLY once, the
  second implementation exercised across all shards (`_check_run`, tools/lib_evidence.sh) — and only
  it writes evidence, against the tree fingerprint taken at launch;
* each unit's COMPILE time is recorded beside its wall time (Julia's own counter, as `@time`), and
  the summary prints the run's compile share — what threads in one process would compile once, where
  three cold workers compile it three times (user, 2026-10-04: "are we using Julia multi threading");
* the summary records what the MACHINE did (user, 2026-10-04: a slow run must say whether it was
  the host): a fixed single-core probe timed before and after (about 2.0 s quiet), the steal share,
  and the clock. This VM reported 0 steal over 16 h and a fixed 2394.569 MHz, so here the probe is
  the signal.
MEASURED: 6m05s wall for the whole run (3 workers, 321/313/314 s of units each), against 16m07s in
one process just before. The longest unit is the static-analysis gate (217 s); the rest are at most
~54 s. `tools/test_evidence.sh` tests the coordinator's verdict on fixture runs (a unit skipped, run
twice, twice-and-another-never, an empty run, no sharing), a real worker refusing a changed tree
a real worker refusing a swipl that is not the pin, the machine numbers' helpers, and a worker
loading from the evidence depot (22 cases); the duplicate check, the AltTerm
check, the worker's two refusals and the PATH it is given are mutation-proved.

**The precompile workload** (`src/precompile_workload.jl`, PrecompileTools — the one allowlisted
dependency): the hot paths on `DefaultTerm`, compiled at precompile time. MEASURED (three fresh
processes each, a quiet machine): the first call of the workload in a fresh process fell from
10.0–13.3 s to 0.52–0.73 s; `using` rose from 0.02 s to 0.05 s; one precompile after a `src` edit costs
16.2 s with it against 6.0 s without — so `tools/warm.sh workload off` turns it off for one checkout
(the gitignored `LocalPreferences.toml`); CI and fresh clones keep it.

## The layout mirrors swipl-devel

Decided 2026-10-02: LogicKernel is a **full mirror** of [swipl-devel](https://github.com/SWI-Prolog/swipl-devel)
(first priority) with [scryer-prolog](https://github.com/mthom/scryer-prolog) as the second reference,
so comparing with upstream — and tracking it commit by commit — stays a mechanical job.

| upstream | LogicKernel |
|---|---|
| swipl-devel `src/pl-prims.c` | `src/pl-prims.jl` |
| swipl-devel `boot/tabling.pl` | `boot/tabling.jl` |
| swipl-devel `tests/core_lang/test_bips.pl` | `test/core_lang/test_bips.jl` |
| swipl-devel `bench/programs/derive.pl` (the `bench` submodule, repo `swipl-bench`) | `bench/programs/derive.jl` |
| scryer-prolog `src/lib/tabling.pl` | `scryer-prolog/src/lib/tabling.jl` |

* A ported **file** lives at upstream's path; a ported **function** or **test unit** keeps upstream's
  name (`!` appended when it mutates an argument). Each carries a `# PORT:` marker.
* Code with **no upstream counterpart** opens with `# ORIGINAL: <why>` and lives in the nearest SWI
  area: `src/` for source, `test/<SWI tests area>/` for its tests, `test/` root for package
  infrastructure. It may never sit at a path that shadows an upstream file, and never in `boot/`.
* Directories exist only where swipl-devel has them.

`tools/port_check.jl` enforces every rule above in the suite (with a fixture proving each check can
fail), and the workspace hook `require-logickernel-port-header.sh` catches the common mistakes at
write time. The generated table in [`port_inventory.md`](port_inventory.md) lists every port;
`tools/upstream_drift.jl` reports what changed upstream since each one.

**Where Julia forces a different name** (the only deviations, each required by the language):

| swipl-devel | LogicKernel | why |
|---|---|---|
| `tests/` | `test/` | `Pkg.test` runs `test/runtests.jl` |
| `tests/test.pl` (driver) | `test/runtests.jl` | same |
| — | `src/LogicKernel.jl` | a package's entry file must be `src/<Name>.jl` |
| — | `ext/` | Julia package extensions |
| `doc/`, `man/` | `docs/` | Julia documentation convention |

Porting this way finds defects in swipl-devel itself; they are recorded in
[`upstream_reports.md`](upstream_reports.md) — LogicKernel issues first, reported upstream later.

## What is here now

| file | what | upstream |
|---|---|---|
| `src/LogicKernel.jl` | the module entry file: the include order (the code graph below follows it) and the exports (ORIGINAL) | — |
| `src/term_interface.jl` | the term interface (ORIGINAL — settled 2026-10-02; `term_type` added 2026-10-03, found by the second implementation) | — |
| `src/pl-prims.jl` | the standard order of terms: `compareStandard` and its chain — for resolved terms, and under bindings (`ld`, V5a1) with upstream's cyclic machinery (`linkTermsCyclic` in `do_compare`, `compare_descend`, `is_acyclic`); UNIFICATION — `do_unify` (pair agenda, cyclic links), the `occurs_check` flag's three modes, `=`, `\=`, `unify_with_occurs_check/2`, `?=`, `unifiable/3`, and `resolve_term` to copy an answer out | `src/pl-prims.c`, `src/pl-incl.h` |
| `src/default_term.jl` | `Term{G}`, the reference implementation (ORIGINAL) | — |
| `test/core_lang/test_bips.jl` | SWI's own `ground/1`, `compare/3`, `==/2` tests | `tests/core_lang/test_bips.pl` |
| `test/core_lang/test_compare_swipl.jl` | live differential: `compare/3` on every pair vs `swipl` | — |
| `test/core_lang/test_term_interface.jl` | the conformance suite, run on BOTH implementations | — |
| `test/core_lang/alt_term.jl` | `AltTerm`, the SECOND implementation of the term interface (ORIGINAL), deliberately unlike `Term{G}` — an abstract type with a leaf per kind and per compound ARITY, interned symbol ids from 0, children in an `NTuple` inside a mutable struct, boxed values, fewer grounded keys, `==`/`hash` that throw; `AltTerm{true}` also shares (hash-conses) ground compounds. A correctness vehicle, not a performance one | — |
| `test/term_under_test.jl` | the implementation a TERM-GENERIC test runs on (`lk_term_type`, `lk_sym`, …); `test/runtests.jl` runs every file that includes it once per implementation, the others as `<file> [alt]` and `<file> [alt_interned]` | — |
| `bench/programs/{derive,nreverse,qsort,poly_10}.jl` | the STANDALONE CONSUMER: four of SWI's benchmark programs written on `DefaultTerm` with exported names only, beside the verbatim `.pl` files | swipl-bench `programs/*.pl` |
| `test/test_standalone_consumer.jl` | runs them: only exported names (checked by parsing), independent oracles, and identical `write_canonical` output to swipl running the upstream programs | — |
| `src/pl-index.jl` | just-in-time clause indexing, function by function: lookup, index creation, assessment, candidate indexes, the primary index, deep (list) indexes, the `indexed` property | `src/pl-index.c` |
| `src/pl-incl.jl` | the structs the clause store and its indexes are built from (`clause`, `clause_ref`, `clause_index`, `clause_list`, `definition`, …), the predicate table's (`procedure`, `module` as `module_t`) and the word layout of keys; THE LOCAL STACK's layout (V3): positions and upstream's struct widths, `VAROFFSET`, the frame, choice-point and foreign-frame records, the frame flags and their macros; V4a's query frame (`queryFrame`, upstream's 47 words), the argument-pointer value `argp_t`, the argument-stack entry and the builder frame, a definition's supervisor and the database's shared supervisor blocks (`PL_code_data`) | `src/pl-incl.h`, `src/pl-data.h`, `src/pl-global.h`, `src/pl-builtin.h`, `src/SWI-Prolog.h` |
| `src/pl-comp.jl` | the head side of the clause compiler — the variable analysis of head AND body (control constructs, the branches of `;`, the goal of `\+`; V1), `compileArgument`, the `H_VOID_N` merging, the clause's literal table (V1 L2) — the head decompiler (`decompileHead`, `decompile_head`), and the code readers the index uses (`skipArgs`, `argKey`) | `src/pl-comp.c`, `src/pl-comp.h`, `src/pl-incl.h` |
| `src/pl-funct.jl` | the control functors (`registerControlFunctors`, upstream's `CONTROL_F` set) and the names compileSubClause treats specially (`SubClauseNames`: `true`, `call`, the goals compiled inline), registered once per database into the global data, which the clause compiler reads them from | `src/pl-funct.c` |
| `src/pl-vmi.jl` | the VM instructions clauses compile to — head, body, calls, the LCO block — with upstream's flags (`VIF_*`) and operand kinds (`CA1_*`), in pl-vmi.c's order (declarations only) | `src/pl-vmi.c`, `src/pl-incl.h`, `src/pl-codetable.c` |
| `src/pl-proc.jl` | the clause database: predicates (`lookupProcedure` in the user module's procedure table, `isCurrentProcedure`, `isDefinedProcedure`, `setDynamicDefinition!`), assert with generations, retract (the logical update view), clause garbage collection, `retract/1`, `retractall/1` | `src/pl-proc.c`, `src/pl-proc.h` |
| `src/pl-global.jl` | the database state — upstream's GD and LD, as values the caller passes; GD holds the control functors the clause compiler reads and the `user` module (`MODULE_user`), LD the bindings, the trail, the `occurs_check` flag and the local stack (its cells, record pools and registers) | `src/pl-global.h`, `src/pl-incl.h` |
| `src/pl-inline.jl` | clause visibility, the database generation, key cleaning; the binding primitives `deRef`, `linkValI`, `Trail!`, `Mark`, `DiscardMark`, `NoMark`, `Undo!`; `hasLocalSpace` | `src/pl-inline.h`, `src/pl-incl.h`, `src/pl-data.h` |
| `src/pl-thread.jl`, `src/pl-gc.jl` | the predicate references an enumeration registers, so clause GC keeps what it can still see; growing the local stack (`growLocalSpace`, `growStacks`, `ensureLocalSpace` — the only allocating path) | `src/pl-thread.c`, `src/pl-gc.c`, `src/pl-gc.h` |
| `src/pl-alloc.jl` | raising a local-stack overflow (`raiseStackOverflow`; a Julia `LocalStackOverflow` until V5) | `src/pl-alloc.c` |
| `src/pl-wam.jl` | the local stack's operations (V3): `newChoice`, `copyFrameArguments`, the foreign frames; the record discipline — pushing a record (upstream's casts of a position), dropping the records above a lowered `lTop`; THE RUN LOOP (V4a): `PL_next_solution_guarded`, one function holding pl-vmi.c's head, exit and supervisor instructions and its backtracking and throw paths as labels, inside one `try` (`PL_next_solution`); the query API (`PL_open_query`, `PL_next_solution`, `PL_cut_query`, `PL_close_query`, `PL_exception`, `PL_current_query`); RULES (V4b): the calls and last calls (`I_ENTER`, `I_CALL`, `normal_call`, `I_DEPART`, the `L_*` block, `I_LCALL`, `I_TCALL`) and the body arguments (`B_*`, through the head's builder) | `src/pl-wam.c`, `src/pl-vmi.c`, `src/pl-incl.h`, `src/pl-gc.c` |
| `src/pl-fli.jl` | term references: positions on the local stack inside the innermost foreign frame (`PL_new_term_refs`, `PL_reset_term_refs`, `PL_copy_term_ref`, `PL_put_term`), with the foreign-environment check; `PL_raise_exception`; since V5a2 the subset built-ins use (`PL_unify`, `PL_unify_atomic`/`_atom`/`_integer`, `PL_is_variable`, `PL_put_intptr`, `PL_compare`, `PL_clear_exception`, `PL_clear_foreign_exception`) | `src/pl-fli.c`, `src/pl-fli.h` |
| `src/SWI-Prolog.jl` | the query API's flags (`PL_Q_*`) and return codes (`PL_S_*`); the foreign interface's types (`term_t`, `fid_t`, `foreign_t`), registration flags (`PL_FA_*`) and record (`PL_extension`) | `src/SWI-Prolog.h` |
| `src/pl-supervisor.jl` | supervisors: the code a call enters first — `S_VIRGIN` installing `S_UNDEF`, `S_DYNAMIC`, `S_MULTIFILE`, `S_TRUSTME`, `S_LIST` or `S_STATIC` (`createSupervisor`, `setDefaultSupervisor`), reset when the clauses change (`freeCodesDefinition!`) | `src/pl-supervisor.c` |
| `src/pl-error.jl` | building and raising an ISO error term for the running predicate (`PL_error`, one typed method per code family: instantiation, type, domain and occurs-check errors; `PL_type_error`, `PL_domain_error`) | `src/pl-error.c`, `src/pl-error.h` |
| `src/pl-ext.jl` | registering the built-ins in the `system` module (`initBuildIns!`, `registerBuiltins!`, `builtin_pred_flags`; pl-ext.c's FRG table `foreigns`) and their DISPATCH: sorted branch trees over the tables by call shape (`_fcall_va`, `_fcall_det`; decision 5, measured against a typed function pointer) | `src/pl-ext.c` |
| `src/pl-trace.jl` | `prolog_current_frame/1` and `prolog_current_choice/1` (`PL_unify_frame`, `PL_unify_choice`) — the positions V3's oracle compares | `src/pl-trace.c` |
| `src/pl-setup.jl` | `emptyStacks`: a new local data's stacks, with one foreign frame at the base | `src/pl-setup.c` |
| `test/core_lang/test_rules_swipl.jl` | V4b's gate: nreverse and an execution differential over random rule clauses identical to swipl (answers and determinism), the body family covered; a call failing before its frame is filled; positions after deterministic exits (MQ6) pinned and live, with the record pools held to the live records; flatness of the last-call optimisation (and its absence growing the stack); open/next/close cycles at their baseline; warm, calls and exits allocate nothing | — |
| `test/foreign/test_query.jl` | V4a's query API: answers, return codes and determinism; the supervisors; positions identical to swipl's; nested queries; cut against close; a closed `qid`; exceptions caught and passed; a Julia exception closing the query; clause GC under a running query; warm allocation | — |
| `test/core_lang/test_head_unify_swipl.jl` | V4a's differential: head unification of random and pinned fact queries identical to swipl under `occurs_check` false, true and error (the error term included), every head instruction exercised in each mode | — |
| `test/db/test_index_argv.jl` | a bound argument narrows the index through both argument views (frame and term), dereferenced | — |
| `test/core_lang/test_local_stack.jl` | V3's tests: positions identical to swipl's (frame and choice-point placement, pinned and live), the record discipline, foreign frames and term references, growth, and that the primitives allocate nothing warm | — |
| `src/pl-hash.jl` | MurmurHash2, for multi-argument keys and the term hashes | `src/pl-hash.c`, `src/pl-hash.h` |
| `src/pl-variant.jl` | `=@=` (`is_variant_ptr`): the argument agenda and the two-way variable correspondence; under bindings (`ld`, V5a1) upstream's node numbering — `var_id`, `term_id`, `Root`, `isomorphic` | `src/pl-variant.c` |
| `src/pl-ressymbol.jl` | reserved symbols (SWI-7's `[]`): `isReservedSymbol`, `compareReservedSymbol`, their rank, `ATOM_nil`'s index key; the reserved set and what is not ported; and Q2's reserved functor `$expr/n` (literal 0 in `H_FUNCTOR`'s operand since V1 L2, DIVERGES) | `src/pl-ressymbol.c` |
| `test/db/test_procedures.jl` | V1's predicate table: one procedure per functor and database, `[]` apart from `'[]'`, `:- dynamic`, defined = a `PROC_DEFINED` flag or a clause visible now | — |
| `test/compile/test_body_code_swipl.jl` | V2's differential: whole-clause code (operands by kind, the LCO label) identical to swipl's on pinned clauses, 400 random rule clauses, and nreverse and qsort as swipl consults them; V2's refusals and swipl's `type_error(callable, Body)`; clause/2 and retract/1 on rules | — |
| `test/compile/test_call_operands.jl` | V1's call operands: `lookupBodyProcedure` (the database's procedure; non-callable goals refused as swipl refuses them, `$expr/n` too), the clause's procedure table, `Output_3`/`Output_n` | — |
| `test/compile/test_decompile.jl` | V1 L2's own tests: each literal decompiled exactly, kind included; random heads back as variants; the table referenced once per literal and `argKey == indexOfWord`; `NUM_OTHER` as an opaque literal | — |
| `test/core_lang/test_expr_functor.jl` | Q2's own tests: `$expr/n`'s standard order, its head code, the index keeping it a wildcard (top level and among same-functor clauses), unification and `=@=` child by child | — |
| `test/core_lang/test_sort.jl` | SWI's own `reserved` unit: `[]` sorts before text atoms | `tests/core_lang/test_sort.pl` |
| `test/compile/test_portable_smallint_swipl.jl` | `is_portable_smallint` under `portable_vmi`, and the tagged-integer range against a live swipl's flags | — |
| `src/pl-termwalk.jl` | the term agendas: the pre-order walk the variant digests use, the plain one `var_occurs_in` uses, the two-term one `do_unify` uses | `src/pl-termwalk.c` |
| `test/core_lang/test_unify.jl` | SWI's own `unify`, `can_compare` and `unifiable` units (rational trees included) but unify_fv and gc_1 | `tests/core_lang/test_unify.pl` |
| `test/core_lang/test_occurs_check.jl` | SWI's own occurs-check units in all three modes but the attributed-variable ones | `tests/core_lang/test_occurs_check.pl` |
| `test/rational/test_ieee754.jl` | SWI's identity and standard-order assertions on IEEE floats (`0.0 \== -0.0`, `nan == nan`, the order of NaN, ±Inf, ±0.0) | `tests/rational/test_ieee754.pl` |
| `test/core_lang/test_bindings.jl` | the trail (`Mark`/`Undo!`, marks nest), the unifier's divergences, `resolve_term`, and that a warm attempt allocates nothing (on the reference type) | — |
| `test/core_lang/test_unify_swipl.jl` | live differential: `=/2` on 1500 hard random pairs in each `occurs_check` mode, outcomes and bindings identical to swipl's | — |
| `src/pl-termhash.jl` | `term_hash/2`, `variant_sha1/2`, `variant_hash/2`; Gladman's SHA-1 and the incremental MurmurHash — atoms hash by `sym_hash` and grounded values by `gnd_key`, so the digests are reproducible across processes but are not SWI's values | `src/pl-termhash.c`, `src/pl-termhash.h` |
| `test/core_lang/test_term.jl` | SWI's own `variant` (`=@=`) tests but the rational-tree and attvar ones | `tests/core_lang/test_term.pl` |
| `test/core_lang/test_hash.jl` | SWI's own `variant_sha1`, `variant_hash`, `term_hash2` tests (term_hash's pinned values as the properties they stand for) | `tests/core_lang/test_hash.pl` |
| `test/core_lang/test_termhash.jl` | SHA-1 against FIPS 180 and Julia's SHA stdlib, the kept `hash_compile` defect, digests identical in another process, digest equality ⇔ `=@=` on interface-only shapes | — |
| `test/core_lang/test_variant_swipl.jl` | live differential: `=@=` and the digests on 2000 random hard pairs vs swipl | — |
| `tools/bench.jl` | the per-chunk performance report: each primitive against swipl on the same terms (three runs, one process), then a profile of the worst | — |
| `tools/warm.sh`, `tools/warm_session.jl`, `tools/test_warm.sh` | the warm lane — a Revise daemon for iteration (never evidence), and its own tests | — |
| `tools/worker.jl`, `tools/lib_evidence.sh`, `tools/test_evidence.sh` | the sharded evidence run — fresh workers, the coordinator's verdict, and their own tests | — |
| `tools/swipl_pin.jl` | the pinned-swipl check a worker and the warm daemon make WHERE THEY RUN | — |
| `src/precompile_workload.jl` | the precompile workload: the hot paths on `DefaultTerm` (ORIGINAL; PrecompileTools) | — |
| `test/db/test_jit.jl` | SWI's own JIT-indexing tests (`jit`, `jit_static`), every unit but the static-determinism checks of supervisors — on one shared `d/2`, as upstream | `tests/db/test_jit.pl` |
| `test/db/test_db.jl` | SWI's own `retract` and `retractall` tests that need no clause bodies, modules or threads | `tests/db/test_db.pl` |
| `test/db/test_clause_variables.jl` | clause variables: renamed apart from the goal's, kernel keys unique across attempts and databases (a retained answer moves between databases), `var_term` rejecting the kernel's half, a sink's bindings gone after it — also when it throws | — |
| `test/db/test_update_view_gc.jl` | the logical update view under clause GC: an enumeration still sees a clause retracted and collected after it started — pinned and live against swipl | — |
| `test/db/test_index_swipl.jl` | the indexing contract, LogicKernel#1's fix pinned, and a live differential: random programs give identical answers to swipl for every call, and identical determinism, indexes and primary indexes wherever the fix cannot apply | — |
| `test/compile/test_head_code_swipl.jl` | live differential: compiled heads are instruction-for-instruction swipl's `vm_list`, frame-slot operands included (slots compacted past voids above the arity, 2026-10-03), with three hand-pinned heads and their frame sizes | — |
| `test/compile/test_analyse_variables_swipl.jl` | live differential of the variable analysis of clauses WITH A BODY (V1): head code to `i_enter`, the slot of every body variable occurrence (swipl's `clause_vm/2`), and the frame size (the `$cont$` frame a `shift/1` captures), on 600 random and 18 pinned clauses | — |
| `test/compile/code_testlib.jl` | how both code differentials write an instruction, the kernel's and swipl's alike: operands by meaning, literals by value | — |
| `tools/githooks/commit-msg` | git's commit-msg hook: a commit message must start with a category (`ADDED:` … `UPSTREAM:`); installed with `git config core.hooksPath tools/githooks` | — |
| `test/test_commit_msg_hook.jl` | the commit-msg hook's contract, both sides (26 cases) | — |

## Code graph — src/, generated (M1)

The source files in include order (src/LogicKernel.jl) and an edge `a --> b` wherever `a` uses a
name `b` defines at top level — the whole package is one module, so a use may point at a file
included later (late binding). Regenerated by `tools/port_check.jl --write-inventory`; `port_check`
holds this block to its generator, here and in CI. The subsystem graph below groups upstream files;
this one is the code.

<!-- BEGIN GENERATED code graph by tools/port_check.jl --write-inventory — do not hand-edit -->
```mermaid
graph LR
    term_interface["term_interface.jl"]
    default_term["default_term.jl"]
    pl_hash["pl-hash.jl"]
    pl_incl["pl-incl.jl"]
    SWI_Prolog["SWI-Prolog.jl"]
    pl_termwalk["pl-termwalk.jl"]
    pl_vmi["pl-vmi.jl"]
    pl_index["pl-index.jl"]
    pl_funct["pl-funct.jl"]
    pl_global["pl-global.jl"]
    pl_inline["pl-inline.jl"]
    pl_prims["pl-prims.jl"]
    pl_ressymbol["pl-ressymbol.jl"]
    pl_comp["pl-comp.jl"]
    pl_variant["pl-variant.jl"]
    pl_termhash["pl-termhash.jl"]
    pl_thread["pl-thread.jl"]
    pl_gc["pl-gc.jl"]
    pl_alloc["pl-alloc.jl"]
    pl_wam["pl-wam.jl"]
    pl_fli["pl-fli.jl"]
    pl_error["pl-error.jl"]
    pl_setup["pl-setup.jl"]
    pl_proc["pl-proc.jl"]
    pl_supervisor["pl-supervisor.jl"]
    pl_trace["pl-trace.jl"]
    pl_ext["pl-ext.jl"]
    precompile_workload["precompile_workload.jl"]
    term_interface --> default_term
    default_term --> term_interface
    default_term --> pl_prims
    pl_hash --> default_term
    pl_incl --> default_term
    pl_termwalk --> term_interface
    pl_termwalk --> default_term
    pl_termwalk --> pl_inline
    pl_termwalk --> pl_comp
    pl_vmi --> pl_incl
    pl_vmi --> pl_wam
    pl_index --> term_interface
    pl_index --> default_term
    pl_index --> pl_hash
    pl_index --> pl_incl
    pl_index --> pl_vmi
    pl_index --> pl_inline
    pl_index --> pl_ressymbol
    pl_index --> pl_comp
    pl_index --> pl_wam
    pl_index --> pl_proc
    pl_funct --> term_interface
    pl_funct --> default_term
    pl_global --> term_interface
    pl_global --> default_term
    pl_global --> pl_incl
    pl_global --> pl_termwalk
    pl_global --> pl_index
    pl_global --> pl_funct
    pl_global --> pl_gc
    pl_global --> pl_wam
    pl_global --> pl_setup
    pl_global --> pl_supervisor
    pl_global --> pl_ext
    pl_inline --> term_interface
    pl_inline --> default_term
    pl_inline --> pl_incl
    pl_inline --> pl_global
    pl_inline --> pl_alloc
    pl_prims --> term_interface
    pl_prims --> default_term
    pl_prims --> pl_incl
    pl_prims --> SWI_Prolog
    pl_prims --> pl_termwalk
    pl_prims --> pl_global
    pl_prims --> pl_inline
    pl_prims --> pl_ressymbol
    pl_prims --> pl_comp
    pl_prims --> pl_variant
    pl_prims --> pl_wam
    pl_prims --> pl_fli
    pl_prims --> pl_error
    pl_ressymbol --> term_interface
    pl_ressymbol --> default_term
    pl_ressymbol --> pl_incl
    pl_ressymbol --> pl_prims
    pl_comp --> term_interface
    pl_comp --> default_term
    pl_comp --> pl_incl
    pl_comp --> pl_vmi
    pl_comp --> pl_index
    pl_comp --> pl_funct
    pl_comp --> pl_global
    pl_comp --> pl_inline
    pl_comp --> pl_prims
    pl_comp --> pl_ressymbol
    pl_comp --> pl_thread
    pl_comp --> pl_wam
    pl_comp --> pl_proc
    pl_variant --> term_interface
    pl_variant --> default_term
    pl_variant --> pl_incl
    pl_variant --> SWI_Prolog
    pl_variant --> pl_global
    pl_variant --> pl_inline
    pl_variant --> pl_prims
    pl_variant --> pl_comp
    pl_termhash --> term_interface
    pl_termhash --> default_term
    pl_termhash --> pl_hash
    pl_termhash --> pl_incl
    pl_termhash --> pl_termwalk
    pl_termhash --> pl_comp
    pl_thread --> pl_incl
    pl_thread --> pl_global
    pl_thread --> pl_inline
    pl_thread --> pl_proc
    pl_gc --> default_term
    pl_gc --> pl_incl
    pl_gc --> pl_global
    pl_gc --> pl_inline
    pl_gc --> pl_thread
    pl_gc --> pl_alloc
    pl_gc --> pl_proc
    pl_alloc --> default_term
    pl_alloc --> pl_incl
    pl_alloc --> pl_global
    pl_wam --> term_interface
    pl_wam --> default_term
    pl_wam --> pl_incl
    pl_wam --> SWI_Prolog
    pl_wam --> pl_vmi
    pl_wam --> pl_index
    pl_wam --> pl_global
    pl_wam --> pl_inline
    pl_wam --> pl_prims
    pl_wam --> pl_comp
    pl_wam --> pl_gc
    pl_wam --> pl_alloc
    pl_wam --> pl_fli
    pl_wam --> pl_error
    pl_wam --> pl_supervisor
    pl_wam --> pl_ext
    pl_fli --> term_interface
    pl_fli --> default_term
    pl_fli --> pl_incl
    pl_fli --> SWI_Prolog
    pl_fli --> pl_global
    pl_fli --> pl_inline
    pl_fli --> pl_prims
    pl_fli --> pl_gc
    pl_fli --> pl_wam
    pl_error --> term_interface
    pl_error --> default_term
    pl_error --> pl_incl
    pl_error --> SWI_Prolog
    pl_error --> pl_global
    pl_error --> pl_wam
    pl_error --> pl_fli
    pl_setup --> pl_global
    pl_setup --> pl_wam
    pl_setup --> pl_fli
    pl_proc --> term_interface
    pl_proc --> default_term
    pl_proc --> pl_incl
    pl_proc --> pl_index
    pl_proc --> pl_global
    pl_proc --> pl_inline
    pl_proc --> pl_comp
    pl_proc --> pl_thread
    pl_proc --> pl_gc
    pl_proc --> pl_supervisor
    pl_supervisor --> default_term
    pl_supervisor --> pl_incl
    pl_supervisor --> pl_vmi
    pl_supervisor --> pl_index
    pl_supervisor --> pl_global
    pl_supervisor --> pl_inline
    pl_supervisor --> pl_ressymbol
    pl_supervisor --> pl_comp
    pl_supervisor --> pl_wam
    pl_supervisor --> pl_proc
    pl_trace --> term_interface
    pl_trace --> default_term
    pl_trace --> pl_incl
    pl_trace --> SWI_Prolog
    pl_trace --> pl_global
    pl_trace --> pl_wam
    pl_trace --> pl_fli
    pl_ext --> term_interface
    pl_ext --> default_term
    pl_ext --> pl_incl
    pl_ext --> SWI_Prolog
    pl_ext --> pl_global
    pl_ext --> pl_prims
    pl_ext --> pl_variant
    pl_ext --> pl_proc
    pl_ext --> pl_supervisor
    pl_ext --> pl_trace
    precompile_workload --> term_interface
    precompile_workload --> default_term
    precompile_workload --> pl_incl
    precompile_workload --> SWI_Prolog
    precompile_workload --> pl_global
    precompile_workload --> pl_inline
    precompile_workload --> pl_prims
    precompile_workload --> pl_comp
    precompile_workload --> pl_variant
    precompile_workload --> pl_termhash
    precompile_workload --> pl_wam
    precompile_workload --> pl_fli
    precompile_workload --> pl_proc
```
<!-- END GENERATED code graph -->

## Subsystems — a grouping of upstream files, not directories

The kernel is built in this order; each subsystem is the set of SWI files it ports. An arrow reads
"depends on".

```mermaid
graph TD
    unify --> terms
    constraints --> unify
    trie --> terms
    trie --> unify
    index --> terms
    db --> terms
    db --> index
    tabling --> unify
    tabling --> trie
    tabling --> db
    vm --> unify
    vm --> constraints
    vm --> index
    vm --> db
    vm --> tabling
```

| subsystem | port class | swipl-devel files | notes |
|---|---|---|---|
| `terms` | design + code | `src/pl-prims.c` (standard order) | the interface is ORIGINAL; compounds are children with the head as child 1 |
| `unify` | code | `src/pl-variant.c`, `src/pl-termhash.c`, unification in `src/pl-prims.c` | variant checking and term hashing ported 2026-10-03 (finite trees: no cycle marking, no attributed variables); unification ported 2026-10-03 as SWI's: a binding store and a trail with marks, the occurs-check modes, rational trees through bindings |
| `constraints` | code | `src/pl-attvar.c` | attributed-variable hooks |
| `trie` | code | `src/pl-trie.c` | answer and variant tables, variables keyed by first occurrence |
| `index` | code | `src/pl-index.c` | ported 2026-10-02, verbatim: keys are read from compiled head code as upstream reads them — with ONE deliberate divergence: `skipArgs`'s H_VOID_N defect is fixed ([LogicKernel#1](https://github.com/CognitiveSubstratesAI/LogicKernel/issues/1)), so an argument right after `_,_` is indexed where swipl 10.1.16 does not; see the contract below |
| `db` | code | `src/pl-proc.c` | clauses in source order, generations (logical update view), clause GC — ported 2026-10-02 with retract/1, retractall/1, clause/2, which unify with the kernel's unification since 2026-10-03; since V1 L2 (2026-10-04) each attempt DECOMPILES the head from the clause's code and literal table (`decompile_head`, as upstream) — a clause stores no head term. Not yet: abolish, reload, transactions |
| `tabling` | code (WFS) | `src/pl-tabling.c`, `boot/tabling.pl`; scryer `src/lib/tabling.pl` | SLG: suspension, SCC completion, WFS delays; scryer's is the delimited-control design |
| `vm` | design | `src/pl-comp.c`, `src/pl-wam.c` | SWI is ZIP-based, not the WAM; compiled clauses decompile back to terms. The head side of pl-comp.c is ported — the head instructions as swipl selects them (V1 L1), the clause's literal table and the head decompiler (V1 L2), the variable analysis of head and body (V1, pl-funct.c's control functors with it); body code and the instructions' execution are not |

## Invariants every subsystem keeps

1. **Indexing never changes answers.** Any narrowing yields a superset; enumeration yields exactly
   the true multiset, in source order. A flag that disables narrowing must disable EVERY narrowing.
   SWI's deep (list) indexes keep this by construction, so the port needs no extra step:
   `addClauseBucket` puts a variable clause into EVERY functor's clause list and starts each new
   list with the variable clauses already there, and `addClauseToIndex` refuses a variable clause
   into a list index (the index is dropped instead). An earlier note here, written before
   pl-index.c was read in full, claimed the opposite (corrected 2026-10-02).
2. **A grounded key follows the term type's `gnd_equal`** — SWI's identity in the reference type
   (`1` and `1.0`, `0.0` and `-0.0` unify apart and key apart); a type matching by `==` (Core's)
   keys by `==`. Where agreement cannot be guaranteed, the key is `nothing` — a wildcard, never a
   shared bucket. `gnd_equal` is the only grounded matching in the kernel.
3. **Answers in order, duplicates kept.** Deduplication and tabling modes are caller options.
4. **No module-level mutable state** (`tools/lint_globals.jl`, run by the suite).
5. **No runtime dispatch, no abstract fields, no `Any`** — enforced by the suite with JET, Aqua,
   AllocCheck and the type-discipline gates; every method must be in the dispatch manifest. These
   are checked on the REFERENCE term type: they make the kernel fast on a concrete term type, and
   say nothing about correctness — that is invariant 8.
   **No unchecked memory access beyond an allowlist, and a bounds-checked run** (user, 2026-10-04,
   on Julia 1.13: `Pkg.test` no longer forces `--check-bounds=yes`, so an out-of-range index
   inside `@inbounds` would corrupt memory silently instead of failing a test — and the VM's stacks
   are where it would hurt most):
   * `test/test_type_discipline.jl` (run everywhere) lists every `@inbounds`, `@boundscheck`,
     `@propagate_inbounds`, `unsafe_*` call and `ccall` in `src/` from the PARSED code. They must
     equal an allowlist, each entry with its reason; a new one fails until a measured performance
     step justifies it, and a listed one that is gone fails too. Today there are two, both in
     src/pl-termhash.jl: SHA-1's message schedule (`@inbounds`, every index masked `& 15`) and
     `_sha1_memcpy!`'s `unsafe_copyto!` — which is unchecked in EVERY bounds mode, so it now
     checks its byte range first, tested;
   * CI's `test` jobs run bounds-checked: julia-runtest passes `--check-bounds=yes` (its
     `check_bounds` input, now stated in CI.yml — measured in the logs, its own precompile cache),
     and `test/test_check_bounds.jl` FAILS those jobs if it is not really on
     (`LOGICKERNEL_REQUIRE_CHECK_BOUNDS=1`): `JLOptions().check_bounds`, and an out-of-range read
     inside `@inbounds` throwing.
6. **SWI's execution model inside the kernel; the caller's sink at the boundary** (user, 2026-10-03).
   The VM is ported as is — frames, choice points and the trail included — and bindings follow SWI:
   a binding store and a trail with marks. Answers leave the kernel through upstream's own query API
   (`PL_open_query`/`PL_next_solution`/`PL_cut_query`/`PL_close_query`, pl-wam.c), with a sink (and an
   iterator) as thin conveniences on top; until the VM lands, retract/1, retractall/1 and clause/2
   call a sink per answer and undo its bindings when it returns. Core's execution rules (no choice
   points, no trail) govern Core, not the kernel's internals.
7. **Standalone.** No dependency on any CognitiveSubstratesAI package. One allowlisted ecosystem
   dependency, PrecompileTools (user, 2026-10-03); any other is a deliberate act with a reason.
8. **Correct on ANY implementation of the term interface** (2026-10-03). A term type may be an
   abstract hierarchy — Core's `Atom` is — so the kernel never takes the term type from `typeof(t)`
   (a leaf there) but asks `term_type(t)`, and never compares or hashes terms outside the interface
   (Base `==`/`hash`). `===` on compounds is constant-time and `a === b` implies the terms are
   identical; SHARED subterms are permitted, as SWI's own `copy_term/2` shares ground subterms
   (pl-copyterm.c). Every TERM-GENERIC test runs on the reference `Term{G}` and on the
   deliberately different `AltTerm` (test/core_lang/alt_term.jl), both plain (`AltTerm{false}`) and
   SHARING ground compounds (`AltTerm{true}`, hash-consed); `test/runtests.jl` holds a floor on how
   many files that is, and checks each variant built its own compounds and the sharing one shared. What the second implementation found (its first run: 6516 passed,
   2002 failed, 43 errored on it; the reference unaffected):
   * 18 kernel methods bound the term type from a term argument (`f(t::T) where {T}`) — the
     standard-order chain by a DIAGONAL signature `(t1::T, t2::T)`, which never matches two leaves,
     the rest building agendas, renamed heads and hash nodes with a leaf type. Fixed with
     `term_type`; `compareStandard` and `is_variant_ptr` now refuse two term types explicitly,
     which the diagonal signature used to do implicitly;
   * `atomic_compare` is the implementation's, but SWI's leaf orders it is built from
     (`compareAtoms`, `compareStrings`, `compare_neq_floats`, `compare_mixed_float_rational`)
     were internal. Exported;
   * the kernel's "same term" test (`===`, upstream's cell-address compare) and its identity
     maps (`IdDict`) need `===` on compounds to be CHEAP. `AltTerm`'s first compounds were
     immutable tuple values, so `===` walked them — exponentially on shared subterms — and the
     live unification differential never finished. First stated as "a compound has object
     identity, twins are never `===`" — too strong: it forbade the sharing SWI's terms have, and
     failed on `AltTerm{true}` at `()`. Restated (user): constant-time, `a === b` ⇒ identical,
     sharing permitted — with conformance properties for both halves (a 2^24-path DAG's twins;
     `===` against the standard order over every sample pair, and near misses like `f(1)`/`f(1.0)`);
   * in the tests: ported `==/2` checks written as Base `==` on terms — 13 sites in test_jit.jl and
     test_db.jl; `bigint` exposed the first (a boxed `BigInt` is not `===`), and making `AltTerm`'s
     `==` THROW found the rest; they use `lk_eq` now — containers whose element type was inferred
     from a leaf, and an allocation property in a term-generic file (now the reference's only);
   * and in itself: with ONE compound leaf, a mutation reverting `do_compare` to `typeof` SURVIVED
     (its agenda holds only compounds). `AltExpr{N}` puts the arity in the type, and the standard-
     order samples nest two arities, so the conformance suite catches it;
   * SHARING, proven before pl-copyterm.c arrives: `AltTerm{true}` interns ground compounds, and all
     19 term-generic files pass on it (31375 assertions), so nothing reached by the suite assumes a
     different occurrence is a different object. The runner prints how much was shared;
   * a timing guard written `@elapsed(a === b)` measured NOTHING — the compiler deletes an unused
     `===` — and passed with structural compounds (mutation-proved). Now `_timed` keeps the result
     (`Base.donotdelete`), at depths measured to fail in under a second;
   * the two-term-type check runs once, at the public entries (`compareStandard`,
     `is_variant_ptr`); the variant walk calls the unchecked chain (`compare_std`).

## The VM — five design decisions (DECIDED 2026-10-03 — audited by the user)

Invariant 6 decided the model: SWI's frames, choice points and trail inside the kernel, upstream's
query API at the boundary. These five decisions say HOW (COMPILER_PLAN 3h). The user audited them
against `pl-vmi.c`, `pl-wam.c`, `pl-inline.h` and `pl-comp.c` at `bae881a2` and approved them, with
the answers and conditions in § "Decided answers and conditions" at the end of this section — those
take precedence over the text above them where they differ. The inventory, the measurement and the step plan (V1–V9) are in
[`port_inventory.md`](port_inventory.md) § "The VM". Each decision cites upstream at `bae881a2`:
`wam:` = `src/pl-wam.c`, `vmi:` = `src/pl-vmi.c`, `c:` = `src/pl-comp.c`, `incl:` = `src/pl-incl.h`.

### Decision 1 — the boundary is upstream's query API, nested queries included

* **Ported as is, under upstream's names:** `PL_open_query`, `PL_next_solution`, `PL_cut_query`,
  `PL_close_query`, `PL_exception` (wam:2882-3258).
* **Query setup, as upstream:**
  * a `queryFrame` with a dummy `top_frame`;
  * the real frame, whose return address is the one-instruction clause `I_EXITQUERY` built at start-up
    (`initVM`, wam:3790);
  * an embedded `CHP_TOP` choice point holding the query's `Mark`.
* **Flags kept:** `PL_Q_NORMAL`, `PL_Q_NODEBUG`, `PL_Q_CATCH_EXCEPTION`, `PL_Q_PASS_EXCEPTION`,
  `PL_Q_EXT_STATUS`. **Not ported:** the yield, halt and thread-exit flags.
* **Return protocol, upstream's integers:** `TRUE`, `FALSE`, `PL_S_LAST` (a deterministic last answer
  under `EXT_STATUS`), `PL_S_EXCEPTION`, `PL_S_NOT_INNER`.
* **`qid_t`:** the position of the query frame on the local stack, checked by a magic field as upstream
  checks it. Upstream mallocs a `{engine, offset}`; this kernel has one engine.
* **Answers:** an answer is read from the bindings while it is current. Two rules carry over:
  * calling `PL_next_solution` again after a deterministic last answer undoes it (wam:3653-3659);
  * `PL_cut_query` keeps the bindings and `PL_close_query` undoes them — unless the query ended in an
    exception it passes on (`qf->exception && PL_Q_PASS_EXCEPTION`, wam:3159). That is the only
    difference between the two.
* **Nested queries, upstream's rules:**
  * queries form a stack (`LD->query`, `qf->parent`);
  * only the innermost query may be advanced, cut or closed — anything else returns `PL_S_NOT_INNER`
    (wam:3110, 3144, 3650);
  * a query opens only inside an open foreign frame (asserted, wam:2904-2905), which the CALLER provides —
    a built-in runs inside its own (`vmi_fopen`), and `callCleanupHandler` opens one (wam:834, 879). A
    built-in that calls back into Prolog does what `call1`/`call_term` do (wam:737-806): open a query with
    `PL_Q_PASS_EXCEPTION` or `PL_Q_CATCH_EXCEPTION`, take one solution, cut it.
* **Exceptions crossing Julia (DIVERGES — the only one in this decision):** upstream's `PL_throw` longjmps
  to a `setjmp` in `PL_next_solution` (wam:3551-3580).
  * Here, built-ins raise the way most upstream built-ins already do: `PL_raise_exception` plus a `FALSE`
    return.
  * `PL_next_solution` holds the one `try`/`catch` — the `setjmp`'s place. It turns the kernel's own
    `PL_throw` exception type into the `b_throw` path.
  * Any other Julia exception (a bug, an interrupt) restores the query to closed and is rethrown, never
    swallowed.
  * The ball must survive `Undo`. Upstream freezes the global stack under it (`freezeGlobal`,
    pl-fli.c:4757; `frozen_bar`, wam:1569). Here the ball is resolved through the bindings when it is
    raised (`resolve_term`), so it no longer depends on the binding store.
* **`# ORIGINAL` conveniences on top, nothing more:**
  * a sink — `f(ld)` is called for each answer while its bindings are live; returning `false` cuts the
    query;
  * a do-block iterator that yields RESOLVED answers (`resolve_term`) and closes the query however the
    block exits. A plain Julia iterator cannot know when it is abandoned.
* **The existing sink-based `retract/1`, `retractall/1` and `clause/2`** stay as they are until V9. There
  they become what they are upstream: non-deterministic foreign predicates.

### Decision 2 — the data model: immutable terms, a binding store, and mutable frame slots

SWI builds terms cell by cell on a mutable global stack. A variable is a cell, and a binding is a write
to that cell (trailed when the cell is older than the newest choice point). The kernel has:

* **immutable terms** (the interface; `mk_expr` takes a finished children vector);
* **variables as keys**, bound in `LD.bindings` and recorded on the trail — every binding trailed, as
  today;
* **mutable frame slots:** the local stack's cells, each holding a term.

Writing a slot is not a binding, and upstream does not trail it either (vmi:741-747, 1607-1628).

| instruction family | upstream (cells) | kernel |
|---|---|---|
| frame slots (arguments = slots `0..arity-1`, then clause variables) | words after the frame header, `argFrameP`/`varFrameP` (incl:1192-1202) | positions on the local stack: `slots::Vector{T}`, each a term (an unbound variable is a `VAR` term) |
| head, READ mode (`H_ATOM`, `H_SMALLINT`, `H_NIL`, `H_FUNCTOR`, `H_LIST`, …) | `deRef(ARGP)`, compare the cell; descend with `ARGP = argTermP` | `deRef` through the store; compare by IDENTITY (`sym_key`, `gnd_equal`, head + arity); descend with a cursor `(term, child index)` |
| head, WRITE mode (the caller's argument is unbound) | allocate `f(_,…,_)` on the global stack, bind the argument to it (trailed), then later `H_*` fill the cells in place, untrailed (vmi:782-812). `H_VAR` in write mode COPIES only under `occurs_check=false`; otherwise it unifies the slot with the cell, against the argument ALREADY bound to the partial term (vmi:680-736) | **under `occurs_check=false`, a builder:** later `H_*`/`B_*` write children into a scratch frame, and the closing `H_POP` (or the end of an `R`-chain) builds `mk_expr` and binds the argument (trailed). That is observably the same as binding first: `p(X, f(X))` called as `p(A, A)` gives `A = f(A)` both ways. **Under `true`/`error` it is NOT** — swipl fails `p(A,A)` (`true`), and for `p3(X,Y,f(Y,X))` called as `p3(A,A,A)` raises `occurs_check(_A,f(_A,_B))` (`error`), which a late bind would report as `occurs_check(A,f(A,A))`. So at write-mode entry the builder reads `LD.prolog_flag_occurs_check` as vmi:680 does: under `true`/`error` it takes upstream's order for that compound — `mk_expr` with fresh-variable children, bind the argument (trailed), then `pl_unify!` each `H_VAR` child. The builder state is reset on `CLAUSE_FAILED`, as `unify_backtrack` resets `aTop` (vmi:6467-6469); trailing voids the compiler omits (`f(a,g(_))` ends in `h_rfunctor(g/1) h_pop`) become fresh variables. **For your audit.** |
| body arguments (`B_ATOM`, `B_SMALLINT`, `B_NIL`, `B_VAR*`, `B_ARGVAR`, `B_FUNCTOR`, `B_LIST`, `B_POP`, …) | `*ARGP++ = cell`, straight into the next frame's argument cells above `lTop` (vmi:1783), or into a compound being built | slot writes above `lTop`; compounds through the same builder |
| first occurrences (`H_FIRSTVAR`, `B_FIRSTVAR`, `B_ARGFIRSTVAR`, `B_VOID`) | `H_FIRSTVAR` in READ mode stores the caller's child in the slot (vmi:755); otherwise a fresh global cell, or `setVar` of a cell, with the slot pointing at it | read mode: the caller's child, stored in the slot; otherwise a fresh variable key (`fresh_var_keys!`) stored in the slot (and in the child being built) |
| variable reads (`B_VAR`, `B_ARGVAR`, `H_VAR` in write mode) | `linkValI`, `globaliseVar`, and **binding direction chosen by address** (`k > ARGP`, `ARGP < k`; vmi:683, 1050) | `deRef(slot)` copied. **The address rules disappear:** they exist because a global cell may not point into the local stack, and keyed variables live in neither stack |
| `H_VAR` in read mode, `B_UNIFY_*` | `do_unify`/`unify_ptrs` (pl-prims.c) | `pl_unify!` — already ported |
| constants (`H_ATOM`, `B_ATOM`, …) | the operand IS the atom or the small integer | the operand indexes a per-clause **literal table** (`Vector{T}`): `B_ATOM` PUTs the term and `H_ATOM` compares by identity. `argKey` derives the index key from the literal (`sym_hash`/`gnd_key`, as today), so the indexes do not change. This replaces today's hash operand, which cannot be decompiled and is not identity — for `H_FUNCTOR`/`B_FUNCTOR` too (`B_FUNCTOR` must construct the head symbol). Only symbols and small integers become `B_ATOM`/`B_SMALLINT` literals: floats, big integers and strings keep `B_FLOAT`/`B_MPZ`/`B_STRING`, which are not `VIF_LCO`, so `lco()` (c:3744) refuses them as upstream does (needs Q1) |
| LCO (`L_VAR`, `L_*`, `copyFrameArguments`) | raw copies between a frame's own cells (vmi:2415; wam:2410) | slot copies — safe for the same reason as upstream: nothing refers INTO a slot |
| choice point `Mark` | `{trailtop, globaltop, saved_bar}`; `Undo` resets the trail and `gTop` (wam:1538-1578) | `{trailtop}`; `Undo!` deletes the trailed keys from the store. Julia's GC reclaims what `gTop` would |
| trail elision (`LD->mark_bar`) | a GLOBAL cell newer than the newest choice point is not trailed; a local-stack cell always is (pl-inline.h:536-543) | **not ported — every binding is trailed** (the existing `Trail!` DIVERGES). A key has no age that `Undo` could truncate, so an untrailed binding would leave a stale store entry after backtracking: a leak, not a wrong answer |
| `term_t` (decision 5) | a word offset into the local stack (incl:2213) | a slot position |

**Where a flat term store would change this:**
* write mode would fill cells in place, so no builder;
* a `Mark` would regain `globaltop`, and `Undo` would truncate the store — which brings back `mark_bar`
  trail elision;
* constants would be cells;
* building a compound would be a bump allocation instead of a `Vector` per `mk_expr`.

The instruction semantics, frames, choice points and query API above are independent of that choice.

### Decision 3 — frames and choice points: vector-backed stacks, integer positions

* **One position space, as upstream's one local stack.**
  * `lTop::Int`.
  * A frame and a choice point each record their `base` position.
  * `FR`, `BFR` and `parent` are integer indices into `LD.frames` / `LD.choices` (vectors of concrete
    immutable records: `localFrame{T}` with `programPointer` as clause + index, `parent`, `clause`,
    `predicate`, `generation`, `level`, `flags`; `choice` with `type`, `parent`, `mark`, `frame` and the
    `ClauseChoice` or the jump target).
* **Every age test upstream makes by address compares `base` positions** (`BFR <= FR`, `fr <= ch`,
  `FR > catcher`; wam:2040, 2624; vmi:2039, 2174, 2398, 2575, 5127). Frames are reused by LCO and popped
  by an exit, so this is a stack HEIGHT, not a timestamp — the same as upstream.
* **Upstream's stack moves, carried over:**
  * a deterministic exit sets `lTop` to the frame's base and drops the records above it (vmi:2174-2179);
  * LCO reuses the frame record in place (vmi:2036-2077);
  * the `memmove` of a `CHP_CLAUSE` choice point to just above the next clause's variables (vmi:6503-6507)
    becomes an update of its `base`.
* **Registers and state, as upstream splits them.** `FR`, `NFR`, `ARGP`, `DEF`, `PC` are run-loop
  locals (wam:3323-3350). `BFR` is NOT a register: it is `LD->choicepoints` (wam:76). `CL` is
  `FR->clause` (wam:3334). `environment_frame` is written on every call and exit (vmi:1879, 2194),
  because built-ins and nested queries read it (wam:2953, 2980-2982). The kernel keeps `BFR`,
  `environment_frame` and `lTop` in `LD` — or syncs them before every foreign call.
* **FliFrames and query frames are records in the same position space.** FliFrames (`fli_context`,
  `{size, mark, parent}`) are compared with frames by address (wam:2904, 2968, 3247; pl-fli.c:537-568;
  vmi:4425, 4503, 5139), and a query's `choice` sits below its `top_frame` and `frame`
  (pl-incl.h:1911-1916). **Every** assignment that lowers `lTop` drops the records above it, not only a
  deterministic exit: `I_CUT` (vmi:2591), shallow and deep backtracking (vmi:6490, 6520, 6618),
  `restore_after_query` (wam:3086).
* **Allocation:**
  * the stacks are pre-sized at `PL_local_data` creation;
  * `growLocalSpace` (upstream's name) is the ONLY allocating path;
  * the AllocCheck gate checks the call, exit and supervisor paths and admits allocation sites only
    inside it;
  * a warmed run at capacity must allocate nothing on those paths, apart from the compounds the program
    builds;
  * upstream raises `resource_error` at the stack limit (vmi:1886-1890). That needs V5's exception path;
    until then, a limit on `growLocalSpace` raises a Julia error rather than letting runaway recursion
    exhaust memory.

### Decision 4 — determinism detection, ported with the run loop

Upstream's own mechanisms, as is:

* **No choice point when there is no alternative:**
  * `S_TRUSTME` for a single clause, and `S_LIST` for a `[]`/`[_|_]` pair, which dispatches without the
    index;
  * `S_STATIC` creates `CHP_CLAUSE` only when `firstClause` leaves a candidate (vmi:3362-3381);
  * shallow backtracking pops the choice point BEFORE the last alternative runs (vmi:6520-6525).
* **Deterministic exit:** `I_EXIT` with `BFR <= FR` pops the frame (`lTop = FR`, vmi:2174-2179).
* **Last-call frame reuse:**
  * `I_DEPART`'s LCO (`BFR <= FR`, the `last_call` flag and a defined target, vmi:2039-2042;
    `copyFrameArguments`);
  * the compiler's in-place block `L_NOLCO …; I_TCALL | I_LCALL` (vmi:2380-2557; c:3715-3812).
* **`I_CUT`:** a no-op when `BFR <= FR`, otherwise `discardChoicesAfter` (vmi:2572-2598).

Measured above: for the bench's calls (first argument always a bound list), `nreverse` runs on
`S_TRUSTME` and `S_LIST` alone, so it creates no clause choice point. `S_LIST` falls into `S_STATIC` on an
unbound argument (vmi:3605-3608): `concatenate(A,B,[1])` is non-deterministic, as in swipl.

**The gate:**
* (a) `concatenate/3` on lists of 10³, 10⁴ and 10⁵ elements reaches the same local-stack high-water mark;
* (b) a failure-driven loop of `nreverse` returns the trail, the binding store and both stacks to their
  baseline on every iteration;
* (c) determinism per answer (`PL_S_LAST`) equals swipl's on every differential query.

### Decision 5 — the built-in interface: upstream's foreign-predicate protocol, Julia functions

* **Calling convention:** a built-in is a Julia function with upstream's signature —
  `pl_<fname><arity>_va(ld, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t)::foreign_t`, where `fname` is
  upstream's C name (`unify`, `variant`, …; `PRED_SHARE` gives `pl_<fname>va_va`, as for `clause/2`) —
  with a `# PORT:` marker. `A1`…`An` are `PL__t0 + i`, and **`term_t` is a slot position, so a
  built-in's handles ARE its frame's argument slots** (vmi:4319, 4350).
* **The FLI it needs is ported from pl-fli.c under upstream's names** and works on `(ld, term_t)`:
  `PL_new_term_ref(s)`, `PL_get_*`, `PL_put_*`, `PL_unify_*`. Upstream's built-in bodies (`is/2` at
  pl-arith.c:4772: `valueExpression(A2)`, then `PL_unify_number(A1)`) then port nearly line for line.
* **Registration as upstream:** `PRED_DEF` tables (`PL_predicates_from_<file>`), `registerBuiltins` at
  `PL_global_data` creation (pl-ext.c:302-563), and `createForeignSupervisor` giving
  `I_FCALLDETVA <f>` for a `PRED_DEF` built-in (pl-supervisor.c:143-182). The FRG table
  (pl-ext.c:96-190) is not VARARGS and gets `I_FCALLDET<N>, I_FEXITDET`.
* **Dispatch (DIVERGES — the reason is invariant 5):** upstream stores a C function pointer in the
  operand.
  * A Julia function stored in a container is called by DYNAMIC dispatch, which the zero-dispatch gate
    rejects.
  * So the system tables are compiled into ONE generated dispatcher: an `if`/`elseif` over the table index
    whose every branch is a static call.
  * The operand is the table index.
  * User registration (`PL_register_foreign`) is deferred until a consumer needs it, and will need its
    own typed design.
* **Return protocol, upstream's `I_FEXITDET`:** `TRUE` exits, `FALSE` fails — or throws if an exception
  is pending — and any other value is a domain error (vmi:4422-4442).
* **Non-deterministic built-ins** (V9) use upstream's sequence `I_FOPENNDET, I_FCALLNDET*, I_FEXITNDET,
  I_FREDO`:
  * a `CHP_JUMP` choice point and `control_t` with `FRG_FIRST_CALL`/`FRG_REDO`/`FRG_CUTTED`;
  * the redo context kept in the frame's own field rather than overloading `clause` (upstream tags it into
    `FR->clause`, vmi:4647);
  * `REDO_INT` contexts first. `REDO_PTR` needs a typed context store, designed when the first such
    built-in is ported.
* **First users:**
  * the ALREADY-PORTED predicates, registered as upstream registers them (V5): pl-prims.c's table
    (pl-prims.c:6570-6623) and `=@=` (pl-variant.c:544);
  * then pl-arith.c (V6);
  * then `clause/2` and `retract/1`, which upstream implements as non-deterministic foreign predicates
    (V9).

### The questions put to the user (answered below)

The read surfaced three things the settled term interface cannot express. Each changes what the
compiler can emit.

1. **Q1 — reserved symbols and numbers.**
   * **What upstream needs:**
     * the compiler dispatches on reserved symbols — `,` `;` `->` `*->` `\+` `!` `true` `fail` `call` `is`
       `=` `==`, `[]` and `'[|]'` (c:2465-2652, 3474-3560);
     * the choice of instructions depends on them: `H_NIL`/`B_NIL`, `H_LIST`/`H_LIST_FF`/`B_LIST`,
       `H_SMALLINT`/`B_SMALLINT`, `S_LIST`, `A_ADD_FC`;
     * built-ins need number values and constructors (`is/2` builds its result; type tests like
       `I_INTEGER`; errors build `error(type_error(…), …)`).
   * **What the interface has:** no symbol constructor, no grounded constructor and no number access —
     only `mk_var` and `mk_expr`.
   * **Proposal:** a small Prolog layer in the interface, `# ORIGINAL`:
     * `mk_sym(T, name)` and `mk_gnd(T, v)`;
     * one numeric accessor for integers and floats;
     * the reserved symbols built once per `PL_global_data`.

     Without it, the compiler emits `B_ATOM`/`B_FUNCTOR` for `[]` and lists. That changes no answer and
     no LCO decision (both are LCO-able, or both are not). But it loses `H_LIST_FF` and `S_LIST` — so
     `nreverse` would run on `S_STATIC` with indexing — and poly_10 cannot get `A_ADD_FC`. And `is/2`,
     type tests and error terms cannot be written at all.
2. **Q2 — compounds whose head is not a symbol** (MeTTa's variable and compound heads; SWI has none).
   * **Today:** they compile as `H_FUNCTOR 0` with every child as an argument (`src/pl-comp.jl:382`). That
     is enough for the index, but **unsound to execute** (no arity check) and cannot be decompiled.
   * **Proposal:** a reserved functor `$expr/n`, where `n = nchildren`, whose arguments are all the
     children, the head included — `# DIVERGES`, since SWI has no such terms.
3. **Q3 — the builder in write mode** (decision 2). The proposal is BOTH, chosen by the `occurs_check`
   flag, as upstream itself branches on it (vmi:680): the builder under `false` (the default, and the hot
   path), and upstream's order under `true`/`error` — `mk_expr` with fresh-variable children first, bind
   the argument, then unify each `H_VAR` child — because only that order gives swipl's failures and error
   terms there (verified by probe, decision 2). The alternative is upstream's order always: one store
   entry and one trail entry per cell, and longer `deRef` chains, on every write-mode compound.

### Decided answers and conditions (user, 2026-10-03)

**Q1 — a small Prolog layer in the interface: APPROVED**, on two conditions:
* **SWI-7's `[]`, exactly.** `[]` is a reserved constant distinct from the atom `'[]'` (`[] == '[]'` is
  false), and lists are `'[|]'/2`. Pinned with SWI's own tests for `[]` and `'[|]'`, not with
  assumptions.
* **The numeric accessor preserves the KIND** — small integer, big integer, float (and rational if
  ported) — because SWI's instruction choice (`H_SMALLINT` / `H_MPZ` / `H_FLOAT`) and the standard order
  depend on it. **REFINED (user, 2026-10-03):** the kinds are SWI's SEMANTIC ones — integer (any size),
  rational, float; "small vs big integer" is storage and instruction selection, decided by upstream's own
  `is_portable_smallint` (pl-comp.c), a separate helper. *(Corrected in V1's L1, 2026-10-04, by
  upstream's source and a probe: a HEAD integer is chosen by tagged STORAGE in `compileArgument` —
  `H_SMALLINT` up to ±2^56, `H_MPZ` beyond, identically under `portable_vmi` true and false;
  `is_portable_smallint` serves body arithmetic, `A_ADD_FC`, alone. There is no `H_INTEGER` or
  `H_INT64` in 10.1.16.)* And the accessor is a kind query plus one
  TYPED getter per representation (`Int64`, `BigInt`, `Rational{BigInt}`, `Float64`), so a caller
  branches once and stays type-stable.

**Q1 — BUILT (2026-10-03), on all three term implementations.** The decisions taken while building it
(user):
* **A reserved symbol is a `SYM` with a flag** (`is_reserved_symbol`), not a kind of its own: upstream
  gives `[]` the atom tag and makes the blob type a property of the atom, and every `kind === SYM` site
  (indexing, functor heads, unification) stays right for `[]`. Proven by `AltTerm`, whose reserved
  symbols are a LEAF TYPE of their own.
* **The surface**: `mk_sym`, `mk_gnd`, `mk_reserved_symbol` / `is_reserved_symbol` (pl-ressymbol.c),
  `mk_nil` / `is_nil` (the foreign interface's `PL_put_nil` / `PL_get_nil`), `NumKind` with
  `number_kind`, `integer_is_int64`, `int64_value`, `bigint_value`, `rational_value`, `float_value`
  (and, since V1 L1, `NUM_STRING`/`NUM_OTHER` with `string_value` — below).
* **The reserved set** is upstream's: `[]`, and four atoms the same init retypes (`dict`, `trienode`,
  `no_value`, `term_t_free`) — those four NOT PORTED, with their subsystems (src/pl-ressymbol.jl).
* **What swipl 10.1.16 says, probed, and where each fact is pinned** (`[]` against the text atom `'[]'`):

  | fact | pinned by |
  |---|---|
  | `[] == '[]'` and `[] = '[]'` fail | conformance (distinct `sym_key`); the `=/2` differential (each the other's near twin) |
  | `[]` sorts before every text atom, `''` included, after strings; `'[\|]'` is a text atom | conformance; `test_sort.jl` (`reserved`, SWI's own unit); the `compare/3` differential (`[]`, `'[]'`, `'[\|]'`, `[a]`, `[a\|b]`, `f([])`, `f('[]')`) |
  | `'[\|]'(a, []) == [a]`; `[a\|b] =.. ['[\|]', a, b]`; `'.'(a, [])` is not `[a]` | the `compare/3` differential (lists are `'[\|]'/2` of a text atom) |
  | `term_hash([]) == term_hash('[]')` (atoms hash by TEXT); `variant_sha1`/`variant_hash` differ (they add the blob type's name) | test_termhash.jl; conformance (`sym_hash` equal) |
  | `[]` compiles to `H_NIL`, keyed `ATOM_nil` — apart from `'[]'` | the head-code differential (`[]` in its random heads); the index differential (profile `nil_vs_quoted`) |
  | `atom([])` fails, `atomic([])` succeeds | `is_reserved_symbol` — awaits the type-test built-ins (V5) |
  | `atom_length([], 0)` (a code list, CVT_LIST); `atom_codes([], C)` raises `type_error(atom, [])`; `term_to_atom([], '[]')`; `write_canonical` writes `[]` and `'[]'` | NOT YET TESTABLE: recorded here for when the text built-ins and the writer arrive |
* **The audit of every `SYM` site** (user): identity sites (`sym_key`: unification, `\=`, `=@=`, functor
  matching) were already right, as `[]` and `'[]'` have different keys; `compileArgument!` now takes
  upstream's `isNil` branch (`H_NIL`), and `skipArgs`/`argKey`/`indexOfWord` key `[]` as `ATOM_nil`;
  `variant_sha1`/`variant_hash` hash the blob type's name, as upstream; `term_hash` keeps the text hash,
  as upstream. Every test-side writer goes through one `lk_atom_text` (`[]` bare, `'[]'` quoted), and
  the standalone consumer's writer and benchmark programs recognise `[]` by `is_nil`, not by its name.
* **Not in Q1**: `H_LIST`/`H_RLIST`/`H_LIST_FF` (the `'[|]'/2` case of `H_FUNCTOR`) and the numeric
  head instructions come with the literal and compound operands, the next V1 step (done: L1 below).

**V1, L1 — the head instructions, as swipl selects them: BUILT (2026-10-04), on all three term
implementations.** V1's "literal operands" step is split in two: L1 selects the instructions (this);
L2 gives the operands decision 2's per-clause literal table.
* **Probed first** (swipl 10.1.16, `vm_list`, 2026-10-04):
  * integers go by tagged storage, not `is_portable_smallint`: `2^56-1` and `-2^56` are
    `h_smallint`; `2^56`, `-2^56-1` and `2^63-1` are `h_mpz`. The listing is identical under
    `portable_vmi` true and false, and `4r2` is `h_smallint(2)`;
  * `1r3` → `h_mpq`, `2.5` → `h_float`, `"abc"` → `h_string`, `[]` → `h_nil`, `'[]'` → `h_atom`;
  * lists: `[a,b,c]` → `h_list h_atom h_rlist h_atom h_rlist h_atom h_nil h_pop`;
    `p([X|Y], f(X,Y))` → `h_list_ff(2,3)`; `[X|X]` → `h_list h_firstvar h_var`; `f([X|Y])` with
    singletons → `h_functor h_rlist h_pop`.
* **The interface gains `is_pair`** (user, 2026-10-04: SWI's `PL_is_pair`, chosen over a per-type
  cached key or an operand on `H_LIST`). It is true exactly for a compound whose head is the TEXT atom
  `'[|]'` with two arguments, pinned by conformance on all three implementations.
  * `FUNCTOR_dot2` is a kernel constant, like `ATOM_nil`.
  * `compileArgument!` emits `H_LIST`/`H_RLIST`, or `H_LIST_FF` (`compileListFF`, `isFirstVarP`),
    where upstream tests `fdef == FUNCTOR_dot2`.
  * `argKey` reads `FUNCTOR_dot2` from all three, `indexOfWord` gives it to every list cell, and
    nothing is carried through the index readers — as upstream.
* **Numbers and strings:** `H_SMALLINT`/`H_MPZ`/`H_MPQ`/`H_FLOAT`/`H_STRING` by `number_kind` and
  tagged storage (`_gnd_head_code`). Each holds ONE operand: the index key, and since L2 the index
  of its literal in the clause's table.
* **Every code reader** handles the new instructions as upstream does: `skipArgs`, `argKey`,
  `skipToTerm` (an `H_LIST_FF` reads upstream's two-void dummy, `H_LIST_FF_VOIDS`, allowlisted as
  the read-only mirror of its `static code var[2]`), `indexableCompound` and `addClauseToIndex`.
  `pl-vmi.jl` now loads before `pl-index.jl`.
* **Pinned:**
  * the head-code differential compares instruction names EXACTLY (the `h_smallint`→`h_atom` mapping
    is gone) on a second random sample of literal and list heads, with `h_list_ff`'s slots;
  * the user's three list spellings `[a|T]`, `'[|]'(a,T)` and `[a,b]`, plus `H_LIST_FF`, `f(a,[b])`
    and the ±2^56 edges, by value and live against swipl;
  * the index differential's `_xlit` keys a predicate by every new instruction, dynamic and static.
* **Open, for the user:**
  * ~~`H_STRING` needs a string kind in the interface~~ — RESOLVED (user, 2026-10-04): the kind
    query is the ONE place for a grounded value's Prolog type. `NumKind` gains `NUM_STRING` (SWI's
    `TAG_STRING`, any `AbstractString`; its typed getter `string_value` returns a `String`) and
    `NUM_OTHER` (a grounded value SWI has no type for: a `Bool`, a `BigFloat`, a container);
    `NUM_NONE` now means "not grounded".
    * A string compiles to `H_STRING`, as swipl does (`"abc"` → `h_string`), keyed by its
      `gnd_key` until L2. A `NUM_OTHER` value stays `H_ATOM` until L2 makes it an opaque literal
      compared by `gnd_equal` (`# DIVERGES` there).
    * The standard order's class is DERIVED from the kind query in both implementations
      (`_atomic_rank`, `_rank`). Before, it used `v isa Real`, so a `BigFloat` sorted as a number
      while `number_kind` called it no number; it now sorts as other.
    * **Where "other" sorts is LogicKernel's decision, `# DIVERGES`** (user, 2026-10-04): SWI has no
      such value, so it follows SWI's nearest analogue, the NON-TEXT BLOBS. The order is
      number < string < other < `[]` < text atom < compound. pl-atom.c gives each non-text blob
      type a rank below 0 (`--nontext_rank`), the reserved symbols 0 and the text types above 0.
      `OTHER_BLOB_RANK` = -1 is written beside those ranks (src/pl-ressymbol.jl), and
      `compare_primitives` and `atomic_compare`'s contract state it. Until then "other" sorted
      after every atom, a choice made with the first terms commit (`1a0bb75`) and never decided.
      * swipl 10.1.16, probed: a stream, a clause reference and a mutex sort after `"str"` and
        before `[]` and `''`.
      * Pinned on all three implementations by conformance ("a value of no SWI type sorts as a
        non-text blob": after numbers and strings, before `[]`, `''`, text atoms and compounds),
        and LIVE by the compare differential: a kernel value of no SWI type compares with every
        oracle term exactly as swipl's stream, clause and mutex blobs do.
      * Mutation-proved (O1–O3): "other" last again, on the reference and on `AltTerm`, and
        "other" first.
    * Pinned by conformance (each kind and `string_value` on all three implementations; "the
      standard order's class follows the kind query", pairwise over every host value plus atoms), by
      the head-code differential (strings in its random heads, `h_string` live against swipl) and by
      the index differential (`_xlit` keys a predicate by strings). Mutation-proved: strings left
      as other, both ranks back on `v isa Real` (caught through `big"1.5"`), and no `H_STRING`;
  * ~~a `Rational` with denominator 1 is `NUM_RATIONAL`~~ — RESOLVED (user, 2026-10-04):
    CANONICALISED at construction. `mk_gnd` stores a denominator-1 `Rational` as the integer, in
    both implementations, so identity, order and hashing agree by construction. swipl 10.1.16
    (`prefer_rationals=false`, its default) probed: `2r1 == 2`, `integer(2r1)`,
    `compare(=, 2r1, 2)`, equal `term_hash` and `variant_sha1`; `-3r1`, `4 rdiv 2` and `6r3` are
    integers too.
    * The reference type stores it in an integer type its payload holds (the numerator's own, else
      `Int64` when it fits, else `BigInt`), and refuses when there is none.
    * Pinned by conformance (Int64 and BigInt cases) and by test_default_term.jl (each branch).
    * Arithmetic (3i/V6) must canonicalise its results the same way.

**V1, L2 — the literal table: BUILT (2026-10-04), on all three term implementations.** Decision 2,
approved by the user and marked `# DIVERGES` (src/pl-comp.jl § the literal table).
* **The table.** A clause keeps the terms its literal operands stand for, `clause.literals`, each the
  very term the clause held; `compileInfo` builds it and `Code` carries it, so `argKey(PC, skip)`
  keeps upstream's signature.
  * `H_ATOM`, `H_SMALLINT`, `H_MPZ`, `H_MPQ`, `H_FLOAT` and `H_STRING` hold a (1-based) index into
    it, where upstream's operand IS the atom, the tagged integer or the inline number or text.
  * `H_FUNCTOR`/`H_RFUNCTOR` hold ONE packed operand, `functor_operand(i, arity)`: the literal of
    the head symbol and the arity. `$expr/n` is literal 0, which no symbol-headed compound has.
  * A grounded value SWI has no type for (`NUM_OTHER`) is an `H_ATOM` whose literal is the value: an
    OPAQUE literal, matched by `gnd_equal` (`# DIVERGES`; SWI's nearest case, a blob, is an atom).
* **Index keys are derived from the literal** (`argKey` → `indexOfWord`), so the indexes are the
  ones the kernel had: `argKey` and `indexOfWord` agree on every argument, pinned over random heads.
* **Q2's marking bit is retired** (user, 2026-10-04): `expr_functor`, `isExprFunctor`,
  `EXPR_FUNCTOR_MASK` and `FIRST_MASK` (added only for it) are gone. `$expr/n` is still a WILDCARD
  in the index on all three implementations: the index mutation proof, re-pointed, keys literal 0
  in `argKey` and is caught on each of them.
* **The decompiler is ported** (pl-comp.c `decompileHead`/`decompile_head`). The clause rebuilds
  its head from the CODE and the table, as upstream, so the clause no longer stores its head term
  or its variables (`head`, `head_vars` and the renaming helpers are gone).
  * `# DIVERGES`: it builds each argument bottom-up and unifies `head`'s arguments with them, where
    upstream unifies cell by cell. A compound closes at its `H_POP`, which also closes the `R` chain
    of its last argument, and gets fresh variables for the voids dropped before it. The functor is
    not unified, since every caller passes a head of the predicate and `definition` keeps the name's
    key only.
  * Variables: one block of fresh kernel keys, one per slot, and one key per nested void.
* **Pinned:**
  * the head-code differential compares every literal BY VALUE. swipl's `vm_list` operands are read
    back as terms by swipl itself and written by kind: atoms and strings as code lists, integers
    and rationals by value, floats by their BITS through `~h`, functors as name and arity. Indices
    are never compared. The float sample gains `0.1` and `5.0e-324`;
  * test/compile/test_decompile.jl, on all three implementations:
    * the user's pairs come back exact, kind included, at the top, in a compound and in a list:
      `1`/`1.0`, `[]`/`'[]'`, `"abc"`/`abc`, `-0.0`/`0.0`, `2^56-1`/`2^56`, `2^70`/`2.0^70`,
      `1r3`/`1/3`, `true`/`1`, `[1.0]`/`1.0`, `""`/`''`;
    * 500 random heads come back as variants (`=@=`), with voids, shared variables, lists,
      `$expr/n` and every kind of literal;
    * every literal is referenced exactly once, and `argKey == indexOfWord` at every argument;
    * `NUM_OTHER` gets its own tests: the opaque literal, its key, and `true`/`1` and `[1.0]`/`1.0`
      kept apart by the index;
  * test_expr_functor.jl: the bit's testset is replaced by literal 0 against every symbol head's own
    literal.
* **Mutation-proved (M1–M8):** a wrong literal index; a wrong functor arity; `argKey` keying
  `$expr/n`, caught three times, once per implementation; `indexOfWord` keying it; the decompiler
  collapsing `[]` into `'[]'`; nested voids sharing a slot; `argKey` returning the raw index;
  `NUM_OTHER` not on `H_ATOM`.
* **Found while building it:** `AltTerm{true}` shares a ground compound with an IDENTICAL one built
  earlier, so a head written with the `Int64` `2^56` may hold the `BigInt` `2^56` that another test
  interned. They are the same SWI integer. The decompiler returns exactly the term the head holds;
  exactness is pinned against the head's own term, identity against the value written.

**V1 — the variable analysis of a clause WITH A BODY: BUILT (2026-10-04), on all three term
implementations** (src/pl-comp.jl `analyseVariables2!`, `analyse_variables!`; pl-comp.c c:839-1375).
* **What it is.** `analyse_variables!(ci, head, body)` walks the head (`argn = -1`, not control) and
  then the body (`argn = arity`, control), as upstream:
  * a body variable gets the next slot ABOVE the arity, even as a goal's direct argument;
  * the arguments of a CONTROL functor are control too, and those of any other compound are not.
    The set is pl-funct.c's `registerControlFunctors`: `,/2`, `;/2`, `|/2`, `->/2`, `*->/2`, `\+/1`,
    `:/2`, `$/1`, `@/2`. It is `# DIVERGES`: there is no functor table, so the set holds the
    `sym_key`s of the names, resolved per term type for a clause with a body. A fact never builds it.
    **Superseded the same day:** the set is registered once per database, in the global data (see
    "the control functors in the global data" below);
  * **`;` (control only):** a variable INTRODUCED in a branch counts as often as in the branch that
    uses it more — `times = max`, through `branch_var`'s saved counts. So `(q(Y) ; r(Y))` makes `Y`
    a void, while a variable met before the branches keeps its sum;
  * **`\+` (control only):** the variables introduced in its goal are taken back out of the
    enclosing branch's list (upstream's `seekBuffer`), so `(\+ q(Y) ; r(Y))` keeps `Y`;
  * then, unchanged, the slot walk: a variable met once is a void, the rest compacted past the voids
    above the arity. The frame size `nv` is the clause's `prolog_vars` and `variables`. Past
    `MAX_VARIABLES` it throws `representation_error(max_frame_size)` instead of unwinding — nothing
    outside `ci` has changed.
* **The head of a clause with a body** compiles through `_compile_clause_head!`, shared with the fact
  path (`compileClause`). It ends with `I_ENTER`, which a trailing void merges into, as upstream's
  table does. The body code (`compileBody`, `I_EXIT`) is V2. Until then this path has ONE caller,
  the differential below, and `compileClause` stays fact-only.
* **Not ported, and where each comes:**
  * `islocal` goal clauses (`subclausearg`, `argvars`, AV_SUBCLAUSE_LOOP, `link_local_var`) arrive
    with the meta-call (V9). They have no clean oracle before then: a goal clause's `variables` also
    counts the clause's own words in the frame (c:2257);
  * the moved head unifications (`head_unify`, `annotate_unification`, `argMoveUnify`,
    `argUnifiedTo`, `isUnifiedArg`) arrive with O_COMPILE_IS's inline unification (V9). Until then
    the kernel compiles what swipl compiles with `optimise_unify` false. **Probed for V9:** an
    `assertz` to a FRESH predicate moves the unification too (`assertz((d1(X) :- X = f(Y), q(Y)))`
    compiles `h_functor(f/1)`), so the predicate's state at compile time decides it, not "dynamic";
  * warnings: singletons, multitons and unbalanced branch variables (`VD_*` flags, `singletons`).
* **Pinned — test/compile/test_analyse_variables_swipl.jl (new, ORIGINAL, term-generic), live
  against swipl 10.1.16:**
  * the head code to `i_enter`, written by test/compile/code_testlib.jl, which the head-code
    differential now shares;
  * the slot of EVERY body variable occurrence, left to right, from swipl's `clause_vm/2`. Every
    `L_*` instruction is skipped: when a last call's arguments can move, swipl compiles them twice,
    the `L_*` moves first and then plain `B_*` code that has each occurrence once (probed). An
    instruction it does not classify fails the comparison;
  * the frame size, for a FRAMED clause `H :- shift(k), B, zz`: the arity of the `$cont$` frame
    `shift/1` captures, minus 3 (pl-cont.c `put_environment`), minus the choice variables that
    `allocChoiceVar` adds for each `->`, `*->` and `\+`. Those are read off the c_* operands and
    checked to be numbered from the Prolog variables up;
  * BARE clauses `H :- B` cover the shape a framed one cannot: a top-level goal whose direct
    arguments are numbered above the arity;
  * 400 framed and 200 bare random clauses, over `,`, `;`, `->`, `*->` (with and without an else),
    `\+`, variable goals, and control functors used as DATA in arguments; 18 pinned clauses, each
    probed;
  * a coverage check that branch voids, bare top goals and slots past 2 all occur in the sample.
* **Mutation-proved, M1–M6, at verdict level:**
  * M1, a branch counted as a sum;
  * M2, no `\+` seek-back;
  * M3, control passed into a goal's arguments;
  * M4, `->` not a control functor;
  * M5, branches keeping the lower count;
  * M6, body variables numbered as arguments. It SURVIVED the framed clauses alone, because their
    top term is always `,`. The bare clauses were added for it.
* **Found on the way, for V2:**
  * swipl refuses a clause whose variable goal is a void: `p :- q, _` is a `type_error(callable, …)`
    (`NOT_CALLABLE`, c:3472). The generator draws a variable goal as `(V, gv(V))` until V2 compiles
    bodies and pins this itself;
  * `report_package` proved that a `cf::ControlFunctors` assert throws in the head walk's
    `cf::Nothing` specialisation. One check at entry now covers every control walk, and
    `cf !== nothing` narrows where `cf` is read. **Superseded the same day:** the walk reads the set
    from the global data, so there is no `Nothing` case, no check and no narrowing.

**V1 — the control functors in the global data: BUILT (2026-10-04)** (user's review of `5276b3a`;
src/pl-funct.jl, src/pl-global.jl).
* **Once per database.** `registerControlFunctors` moved to its upstream file, src/pl-funct.jl, with
  the same PORT marker; its DIVERGES note now says when it runs. `PL_global_data{T}()` registers the
  set into the `const` field `functors_control`, as upstream's `initFunctors` flags `CONTROL_F` on
  its functor table at start-up. The file is included before src/pl-global.jl, which needs the type.
* **Passed in, as upstream reaches its functor table through GD:** `compileClause(gd, def, head)`,
  `_compile_clause_head!(gd, ci, head, body)`, `analyse_variables!(gd, ci, head, body)` and
  `analyseVariables2!(gd, ci, head, nvars, argn, control)`. The head walk now reads the same set and
  never consults it (`control` is false), so the `Union{Nothing, ControlFunctors}` argument is gone.
* **Every caller in the same commit, none building a set of its own:** tools/bench.jl, the
  precompile workload, the test helpers (each test file compiles in one database of its own; the
  analysis differential's coverage check reads `functors_control`), and the static-analysis
  manifest.
* **Bench: no allocation drop, because there was none to drop.** `rule head + analysis` is 32
  allocations / 2528 bytes before and after, and `compileClause fact` is 22 / 1312. Probed in the
  warm daemon on the reference type: building the set allocates nothing, because the nine `mk_sym`s
  are elided when only `sym_key` is used, and takes about 8 ns, against about 2 ns to read the field.
  That saving is below the case's noise (about 1.5 µs). The change stands on upstream's timing and on
  there being one set per database, not on speed.

**V5a2 — the built-in call path: BUILT (2026-10-05)** (port_inventory row V5, its split; decision 5;
src/pl-ext.jl, src/pl-trace.jl NEW; src/pl-wam.jl, src/pl-vmi.jl, src/pl-incl.jl, src/SWI-Prolog.jl,
src/pl-fli.jl, src/pl-error.jl, src/pl-supervisor.jl, src/pl-comp.jl, src/pl-global.jl,
src/pl-prims.jl, src/pl-variant.jl). Built from the call-path memo and decision 5; only genuinely new
questions parked (session-log §0: Q-A..Q-D).
* **Ported:**
  * the types and flags — `term_t`, `fid_t`, `foreign_t`, `FTRUE`/`FFALSE`, `PL_FA_*`,
    `PL_extension`, `frg_code`, `foreign_context`/`control_t` (on the query record, pooled: upstream's
    is a C local of the run loop), the `P_*` bits `registerBuiltins` sets, `definition`'s
    `impl_foreign_function`;
  * registration as upstream registers — `builtin_pred_flags`, `registerBuiltins!`, `initBuildIns!`
    (FRG first, then prims, variant, trace), into a `system` module record (with `$c_call_prolog/0`,
    where `setBuiltinPredicateProperties` puts it), `createForeignSupervisor!`: `I_FCALLDETVA f`, or
    `I_FCALLDET<n> f I_FEXITDET`;
  * the instructions — `I_FCALLDETVA`, `I_FCALLDET0..10`, `I_FEXITDET` (asserting) and its helper
    `helper_I_FEXITDET` (upstream's switch-build label), `vmi_fopen`, `error_foreign_return_code`,
    `discardFrame`'s foreign branch, `SAVE_REGISTERS`/`LOAD_REGISTERS` at upstream's points;
  * `lookupBodyProcedure`'s ISO branch — a body goal binds an ISO built-in at compile time;
  * the FLI subset — `PL_unify` (an occurs-check error RAISED, never a Julia exception out of a
    built-in), `PL_unify_atomic`/`_atom`/`_integer`, `PL_is_variable`, `PL_put_intptr`, `PL_compare`,
    `PL_clear_exception`, `PL_clear_foreign_exception`; `PL_error` as one typed method per code family
    (`ERR_INSTANTIATION`, `ERR_TYPE`, `ERR_CHARS_TYPE`, `ERR_DOMAIN`, `ERR_OCCURS_CHECK`; upstream's
    `instantiation_error` rule for an unbound culprit), `PL_type_error`, `PL_domain_error`;
  * the first users' PRED_IMPLs, line for line over term references — `=`, `\=` (with
    `can_unify(…, ex)`), `unify_with_occurs_check/2`, `==`, `compare/3`, `?=`, `unifiable/3`, `=@=` —
    and the position built-ins `prolog_current_frame/1` (FRG) and `prolog_current_choice/1`.
* **The dispatch — MEASURED, decision 5's condition 2** (src/pl-ext.jl, the numbers in its header):
  the generated branch tree against a typed function pointer (FunctionWrappers' mechanism, written
  locally — the memos' Q3). The tree is as fast as a direct call at V5's table size (99 ns vs the
  pointer's 170 ns, a ~70 ns harness included); the pointer is opaque to AllocCheck ("dynamic
  dispatch") and allocates 192 bytes a call; 785 tree leaves compile in 10.8 s, 785 pointers in
  19.3 s. The tree was kept, the pointer removed.
* **Gate — test/foreign/test_builtins_swipl.jl** (three term types): registration (system module,
  flags, supervisors); the first users as queries against a LIVE swipl, 600 random goals × the three
  `occurs_check` modes — every outcome identical (true with bindings, false, cyclic, or the error's
  formal and the context's predicate), the context's module stripped and counted (swipl qualifies
  every built-in context: Q-A); the ISO ones from clause bodies, a non-last call and a last call,
  identical to the direct call; the position built-ins as queries pinned to libswipl's (probed:
  frame at the handle + 31, choice + 21); a built-in's foreign frame leaves every pool and the trail
  as they were over 10^4 queries, raising ones included. test/core_lang/test_bips.jl: SWI's
  `iso_8_4_2_3_a/b` (compare/3's type and domain errors) ported, through the built-in.
* **Static (static_analysis_body.jl):** every new method in the manifest — JET finds no dispatch in
  the run loop with the foreign labels, nor in the dispatch trees, which are built at load time
  from named leaf builders; and a FOREIGN call's own path allocates nothing — every allocation site
  in the foreign labels' spans lies inside the built-in it calls or on an error path (a bad return
  value, the "false alarm"), the check seeing the built-ins' own allocations so it cannot pass by
  seeing nothing.
* **Found while building it:** kernel code had used `sym_name`, which only the reference term type
  has — the AltTerm runs failed at once (the same lesson as V4a's `_body_functor`): a symbol is
  identified by `sym_key` through the interface. And a gate run after a struct change read stale
  methods from Revise's old world (`@world(...)` in the uncovered list): the daemon was restarted,
  as the warm lane's rule says.
* **Mutation-proved — 12 of 12 caught at verdict level** (baseline 14 s after a restart, limit 240 s): the exit helper taking a failure for success and an error for a failure, `vmi_fopen` not raising `lTop`, the foreign frames not popped (by the timeout), the ISO branch removed, the dispatch tree calling the next entry (a restart BEFORE the run: Revise would not re-expand the macro), `\=` swallowing its error, `compare/3` taking any atom for `<`, `unify_with_occurs_check/2` not restoring the flag, `prolog_current_frame` not skipping its own frame, `prolog_current_choice` skipping the newest choice point. **One was BLIND until a direct test was added:** `ERR_DOMAIN` without upstream's instantiation rule — no first user passes an unbound culprit (`compare/3` tests `canBind` first), so the rule is now tested on `PL_error` itself.**
* **Not here:** module resolution — `user`'s super module, `autoImport` for the non-ISO built-ins,
  qualified error contexts (V5c, Q-A); `S_UNDEF`'s `existence_error` and the stack limit's
  `resource_error` (V5b); non-deterministic built-ins (V9); `PL_register_foreign`.

**V5a1 — the standard order and `=@=` under bindings: BUILT (2026-10-05)** (port_inventory row V5,
its split; src/pl-prims.jl, src/pl-variant.jl, src/pl-global.jl). The first step of V5, from the two
V5 research memos: a built-in reads its arguments from slots whose variables may be BOUND (decision
2), and upstream's `compareStandard` and `is_variant_ptr` take `DECL_LD` and dereference at every
step — the kernel's took terms alone. Settled by "SWI as is" (the memos' Q1): both now have an `ld`
entry, and since through bindings a term can be a RATIONAL TREE, the port takes upstream's cyclic
machinery with them. The entries without `ld` stay, for resolved (finite) terms, unchanged.
* **Ported:** `do_compare` with `linkTermsCyclic` (only pairs reached through a binding, as
  `do_unify` and for the same reason), `compare_fast`, `compare_descend` (Brent's cycle detection),
  `ph_acyclic_mark`/`is_acyclic` (the temporary and permanent marks as two identity maps),
  `compare_std`'s fallback to the descent, `compareStandard(ld, …)`; pl-variant.c's `node`, `var_id`,
  `term_id`, `Root`, `isomorphic`, `variant` and `is_variant_ptr(ld, …)` — a compound numbered by
  IDENTITY where upstream numbers its cell (the same answer: argued at `variant_buffer`).
  `compare_primitives` gained upstream's first test, `w1 == w2` (the same term is equal at once).
* **NOT PORTED:** the `incomparable` flag's `error` value — it raises a ball holding the cyclic pair,
  which `PL_raise_exception` cannot copy yet (it resolves the ball) — so an incomparable pair keeps
  the fast order, as swipl's default `incomparable=arbitrary` does; `CMP_MODE_PARTIAL`.
* **Found, not guessed — the missing `w1 == w2`:** the first differential run did not finish. A
  backtrace taken from the running daemon (SIGUSR1) showed it in `_cyclic_deref`, from the new
  `do_compare`: two sides reaching the SAME compound object, with no link followed, were linked to
  each other — a self-link, followed forever. Upstream never links such a pair: `compare_primitives`
  returns equal for identical words first.
* **Gate — test/core_lang/test_unify_swipl.jl, live swipl, three term types:**
  * the unify differential (2000 pairs × 3 modes) now also compares the pool's six variables pairwise
    after every unification, under its bindings — `==`, `=@=`, and `compare/3` when both are ground —
    identical to swipl's on every outcome (among the rational trees: 9 identical pairs, 3566 variant
    but not identical, 10 ordered; the tests require about half of each);
  * ground rational trees: 1500 families of three variables bound to compounds over themselves, the
    three pairs `==`/`=@=`/`compare/3` identical to swipl's (39 identical, 2309 `<`, 2152 `>`);
  * the descent: 25 pairs where the FAST order is wrong — searched for, about one family in 1300 —
    and `compare/3`'s answer identical to swipl's on all 25.
  * test/core_lang/test_term.jl: SWI's own rational-tree variant tests — `cyclic` ×4, `cycle`,
    `ground`, `sharing_cycles`, `cycle_with_prefix` — ported, each `fail` case asserting that its
    setup unifies, so that `=@=` is what fails.
* **Mutation-proved — 8 of 9 caught:** by the differentials, the descent never taken, `is_acyclic`
  always true, `isomorphic` always true; by NON-TERMINATION (the 240 s limit, the baseline 23 s
  after a restart, or the daemon killed at its memory limit), the missing `w1 == w2`, no cyclic link
  followed, the descent's cycle never detected, a compound's partner ignored, `isomorphic` never
  uniting. **Two were BLIND until the targeted case was added** (the descent never taken; `is_acyclic`
  always true): the fixed corpus met no pair whose fast order is wrong. **Equivalent, argued:** a
  variable's right-to-left link not checked — `node[i].a` and `node[j].b` are written only together,
  in the one branch that requires both zero, so `m == j` implies `n == i`.

**V4b — rules: calls, last calls and body arguments → MILESTONE `nreverse`: BUILT (2026-10-05)**
(port_inventory row V4b; src/pl-wam.jl, src/pl-incl.jl, src/pl-global.jl). Plan: two research
memos — the call path (every instruction with its vmi lines and the kernel mapping) and the gate
(MQ6/MQ18, flatness, the nreverse oracle; swipl and libswipl probed live) — whose questions went to
the user.
* **Decided by the user (2026-10-05):**
  1. **Body compounds use the SAME builder as the head's write mode**, with the frame slot as a
     third destination (`bframe.slot`; decision 2: "compounds through the same builder"). `B_FUNCTOR`
     / `B_LIST` push an entry, `B_RFUNCTOR` / `B_RLIST` open a builder into the slot or the parent
     cell, `B_POP` closes the builders opened since its entry — the outermost into its slot,
     untrailed (above `lTop`, upstream's "this is above the stack anyway").
  2. **A frame whose call fails before it is filled** — `S_LIST` takes `FRAME_FAILED` before any
     supervisor raises `lTop` over the frame `normal_call` built above it (vmi:3607-3608) — is
     dropped where `deep_backtrack` leaves it (`_drop_unfilled_frame!`): the ONE allowed drop of a
     frame being filled, on the failure path of its own call; `dropRecords!` still refuses every other
     (the user's narrowing of V3's assertion, which was too strict). No position moves. The research
     memo found it by reading; the gate's `p42 :- q42(foo). p42.` with `q42([]). q42([_|_]).` runs it.
  3. **A call operand reaches its procedure through the running clause** (`_call_procedure`,
     upstream's `CL`, wam:3334).
  4. **`last_call_optimisation`** is an LD field, on by default (pl-prologflag.c:2400), read at run
     time by `I_DEPART` and `L_NOLCO` as upstream does (Q-14).
  5. **Last-call reuse ASSERTS that the frame is the newest live record** (`_is_newest_live_frame`)
     at `I_DEPART` and at `L_NOLCO`'s fall-through.
  6. **The whole body family now**, driven by an execution differential over random rule clauses.
  7. **MQ18 is recorded as an equivalent mutant**, with the argument (when the failing frame owns the
     youngest choice point, every path that removed a younger one also lowered `lTop`, so nothing
     lives above it), an `@assert` beside the drop so every run checks the claim, and two REACHABLE
     mutants beside it (MR2 `deep_backtrack`'s drop, MR3 the choice point not moved).
  8. **`HIDE_CHILDS` is not ported**: no test here could observe it. Its only effect is the frame bit
     `FR_HIDE_CHILDS`, which only the debugger reads (pl-trace.c:227-274), and what sets it — system
     mode, `debuginfo=false` at a predicate's first definition, foreign predicates — does not exist
     here either. Listed (port_inventory § "Not ported: nothing here can set or observe it"), as
     `TRY_CLAUSE` is.
  9. **`B_ARGFIRSTVAR` and `B_VOID` make a fresh variable**, as upstream's `setVar`.
  10. **MQ6's oracle**: stand-in FACTS named `prolog_current_frame/1` and `prolog_current_choice/1`
      in the kernel, on the very clause text swipl runs with the real built-ins, plus libswipl's
      query-API positions, pinned. V5 replaces the stand-ins (port_inventory row V5).
  11. **The high-water mark is TEST instrumentation**: a sentinel fill of the slots and growth turned
      into an error (`stacks_limit = lMax`), no production field.
  12. **AllocCheck on the call path's labels both ways** — static attribution and a warm runtime check.
  13. **The bench quotes ratios only on a machine MEASURED quiet**: CPU idle over a few seconds and no
      other busy julia or swipl process; the load average is context only (it misleads here: 97% idle
      at a load of 3).
* **Ported** (src/pl-wam.jl, each a label of the run loop and a name in `VMI_RUN` — the one list
  the dispatch tree is built from and the refusal test reads): `I_ENTER`,
  `I_CALL`, `normal_call`, `I_DEPART` with last-call reuse, the last-call block `L_NOLCO`, `L_VAR`,
  `L_VOID`, `L_ATOM`, `L_NIL`, `L_SMALLINT`, the tail calls `I_LCALL` and `I_TCALL`, and the body
  family `B_ARGVAR`, `B_VAR0`, `B_VAR1`, `B_VAR2`, `B_VAR`, `bvar_cont`, `B_ARGFIRSTVAR`, `B_FIRSTVAR`,
  `B_VOID`, `B_FUNCTOR`, `B_LIST`, `B_POP` (`B_RFUNCTOR`/`B_RLIST` gained the slot); the `NFR`
  register. Quirks kept (memo Q-1..Q-14): the new frame built above `lTop`; `I_DEPART`'s non-LCO
  branch uses `lcoSetNextFrameFlags2`; `I_LCALL` sets `lTop` itself and `setFramePredicate` twice;
  every call and tail call re-stamps the frame's generation. NOT PORTED where they stand: the
  alerted blocks (debugger, coverage, signals, limits), `FR_WATCHED` (asserted absent), the context
  module and `P_TRANSPARENT` (one module), `getProcDefinedDefinition` (V5), `pushVolatileAtom`,
  `globaliseVar` and the global-stack checks (decision 2 — a keyed variable lives in no cell).
* **Gate — test/core_lang/test_rules_swipl.jl** (term-generic: the three types):
  * nreverse's answer and its determinism identical to swipl's, the next term reference at +45 as
    libswipl's;
  * an execution differential over 12 random programs (layered facts and rules, fixed rules for the
    last-call forms and for a variable first seen inside a body compound, 156 queries, 313 answers —
    174 non-deterministic, one cyclic, written `cyclic` on both sides): every answer and its
    determinism identical to swipl's; the corpus compiles every instruction of the family; a query is
    stopped at 10,000 answers, so a regression that answers without end fails instead of hanging;
  * the frame failing before it is filled, against swipl;
  * a tail call's `lTop`: `I_LCALL` into a failing `S_LIST`, the next term reference pinned to
    libswipl's 54 (probed, V4b); the logical update view PER CALL: a clause retracted between two
    answers is not seen by the later call (swipl live, the retract inside the query);
  * POSITIONS after deterministic exits (MQ6): the seven clauses of the memo, identical to swipl's
    differences pinned and live (20, 20, 20, 23, 10, 24, 23), libswipl's query-API positions pinned
    (p6 70→45, p6det 45, k 67→45, s 66→45), and at every answer the record pools hold exactly the
    live records (the `BFR` chain; the frames on the parent chains);
  * FLATNESS: concatenate/3 on 10^3, 10^4, 10^5 elements reaches the same high-water mark, qid+52
    (swipl's bottom frame is equally flat, +24), with N+1 trail entries and N+1 binding-store entries
    at the answer, reported — they grow until the store's collector exists (G1); with
    `last_call_optimisation` off the mark grows with the list, so the check can fail;
  * 10^4 open/next/close cycles of nreverse leave every stack, the trail and the store at their
    baseline;
  * warm, a query of calls and exits allocates nothing; statically, no allocation site lies in the
    call path's labels and every function they call is an allocation-free manifest entry
    (static_analysis_body.jl).
* **The refusal test CHOOSES its instruction** (test/foreign/test_query.jl; user, 2026-10-05): V4a's
  named a rule's `I_ENTER`, which V4b runs — the first evidence run found it, not the preflight, as
  the file had not changed. It now takes any declared instruction outside `VMI_RUN` (today `I_NOP`,
  `I_CHP`, `I_CUT`) and fails with "this test has served its purpose — retire it" when none is left.
  Mutant MQ20 (the refusal no longer names the instruction): caught, by this testset.
* **Mutation-proved — 18 of 19 caught at verdict level** (MR1-MR19; every test file passes unmutated
  first, timed; every revert restores the tree byte for byte): V4a's MQ6 (`exit_continue` not
  lowering `lTop`), `deep_backtrack`'s drop and the choice point not moved (MQ18's reachable
  stand-ins), the unfilled frame not dropped and every frame dropped as unfilled, the last-call flag
  ignored at `L_NOLCO` and at `I_DEPART`, last-call reuse without moving the arguments, `L_VAR`
  reading its target, `L_NOLCO` never jumping, `B_POP` not closing, `B_ARGFIRSTVAR` and `B_FIRSTVAR`
  not writing the slot, `normal_call` not saving the return point, `I_LCALL` not setting `lTop`, a
  call not re-stamping its generation, and an allocation in `I_CALL` (the warm runtime check and the
  static per-label check).
  * **Four tests were BLIND until their mutants survived, and were fixed:** a frame failing before
    it is filled happens only on a call AFTER the supervisor is installed (the first goes through
    `S_VIRGIN`, which raises `lTop`); `I_LCALL`'s `lTop` is observable only when the callee's `S_LIST`
    fails and `CHP_TOP` opens the answer's foreign frame there (pinned to libswipl's 54); a call's
    generation only when the database changes between two calls (a retract between answers); a
    variable first seen inside a body compound only when a later call routes it into the answer.
  * **Timeouts, TRACED (user, 2026-10-05: println to the root cause, and a timeout counts only far
    inside the limit).** Five mutants first timed out; a call trace, an instruction cap, a `deRef`
    cap and an answer log found three different causes. MR9 is a genuine FLAT infinite tail
    recursion — the same frame re-entered, its level climbing — and is the only one still caught by
    the timeout (the baseline takes 24 s after a daemon restart, the limit 240 s). MR8 answered
    without end (12,596 answers to one query in 400 s); the test now caps a query at 10,000 answers,
    so it fails fast and says why. MR10-MR12 never hung: the driver had restarted the daemon BEFORE
    restoring the file, so it loaded the previous mutant; fixed, they fail in seconds.
  * **Survives, with the reason:** MR17 (`bvar_cont` storing the slot's term undereferenced) is
    equivalent: every reader dereferences, and a binding undone by backtracking takes the callee's
    frame with it. MQ18 is equivalent by its argument, asserted.
* **Bench:** tools/bench.jl's `nreverse` — the query opened, its one answer, closed — beside swipl's
  own `nreverse` from bench/programs/nreverse.pl; a ratio is quoted only when the machine is
  MEASURED quiet (`quiet_check`: at least 90% of the CPUs idle over 3 s, no other julia or swipl
  process using more than 5% of one). The numbers of each run are in its commit message.
* **After V4b, before V5 (user, 2026-10-05):**
  * **Leaves share ONE empty child vector per term type** (`_no_children`, src/default_term.jl) —
    nreverse's profile charged 20% to `mk_var`, an empty vector per fresh variable. Nothing may push to
    it: test_default_term.jl asserts the sharing, test/runtests.jl that it is still empty after EVERY
    unit, and the static gate that no leaf constructor allocates a child vector. Mutation-proved:
    a push is caught by the dedicated test and — on a unit whose own tests pass with it — by the
    runner's check alone; the sharing undone is caught by the identity test and the static gate.
    MEASURED: a leaf still allocates ITSELF — `DefaultTerm` is not stored inline (its `value` is a
    Union holding a `String`), and an integer leaf also boxes the integer; that is the term
    representation, for phase 2's flat store.
  * **The bench measures both sides with ONE statistic** (tools/bench.jl `julia_times`,
    `swipl_times`): N calls per run, N doubled until a run takes `RUN_S` (0.5 s; 0.1 s was short
    enough that one collection doubled a run), a full collection before each run and every collection
    during it counted, WALL time per call, the minimum of three. The machine is measured before and
    after the runs, the bench's own process excluded from the load and the busiest other process
    named; a ratio is quoted only if both checks are quiet.
* **Not here:** `I_CUT`'s execution (V6) — so qsort runs at V7, with `=</2` (V5/V6); a call reaching a
  built-in, `S_UNDEF`'s `existence_error` (V5); `C_*`, the meta-call, catch/3 (V9).

**V4a — the run loop and the query API, over facts: BUILT (2026-10-05)** (port_inventory row V4a;
src/pl-wam.jl, src/pl-supervisor.jl, src/pl-error.jl, src/SWI-Prolog.jl, src/pl-incl.jl,
src/pl-global.jl, src/pl-inline.jl, src/pl-alloc.jl, src/pl-fli.jl, src/pl-gc.jl, src/pl-proc.jl,
src/pl-index.jl, src/pl-vmi.jl). Plan: two research memos (the head instructions; the query API and
the supervisors), every claim cited by line; libswipl probed live through its C query API for the
return codes, the positions and the closed handle; the open questions went to the user.
* **Corrections accepted (user, 2026-10-05):** `enterDefinition`/`leaveDefinition` are `(void)0`
  upstream (pl-incl.h:1302-1303), so entering and leaving a predicate does nothing; `I_EXIT` and
  `exit_continue` are V4a's, and so are the write-mode body instructions `H_*` jump to (`B_ATOM`,
  `B_SMALLINT`, `B_NIL`, `B_FLOAT`, `B_MPZ`, `B_MPQ`, `B_STRING`, `B_RFUNCTOR`, `B_RLIST`);
  **`argv_at` not dereferencing was a real defect** — a bound argument reached the index as the
  variable it was bound through, so it narrowed nothing. Fixed: one argument view per source (the
  frame's slots, a call term), both dereferencing (pl-index.jl `argv_frame`, `argv_term`), with a
  test where a bound argument must narrow (test_index_argv.jl) and the determinism differential
  confirming it.
* **Decided by the user (2026-10-05):**
  1. **The run loop: one function with labels — upstream's switch build.** `PL_next_solution_guarded`
     holds pl-vmi.c's instructions and helpers as `@label`s, each under its `# PORT: pl-vmi.c NAME`
     marker, over typed register locals (`FR`, `ARGP`, `PC`, `DEF`, `UMODE`, …). `@goto` cannot
     leave a `try`, so the split is upstream's (wam:3552-3580): the whole loop inside one `try` in
     `PL_next_solution`, the handler outside, re-entering through ONE entry — `except = true` for a
     `PrologThrow` (the kernel's `longjmp`), and any other Julia exception closes the query
     (`_abandon_query`) and is rethrown. **The dispatch, MEASURED:** LLVM makes no single jump table
     of an `if`/`elseif` chain over the 36 opcodes — it makes four partial ones (opcodes 1-4, 8-21,
     …), broken wherever neighbouring arms share a target, so `S_LIST` was reached after nine
     decisions. Hence the agreed fallback, a SORTED BRANCH TREE (`@vmi_dispatch`, generated from
     the instruction list): ⌈log2 n⌉ compares and one equality test to any instruction, a code not
     listed falling through to `NotPortedError` by name. On the fact queries the two measured the
     same within noise (four alternating runs in one process: tree 339-349 µs, chain 345-357 µs for
     1000 answers); the tree was kept because its depth grows as log n where V4b adds ~100
     instructions, and the chain's late arms grow linearly. Compile time and first-call latency are
     in the bench (fresh process); the precompile workload runs a query, so a fresh process does
     not compile the loop for `DefaultTerm`.
  2. **`ARGP` is one concrete immutable value** `argp_t{T}(form, position, term)`: a slot (body
     mode), a cursor into a caller's compound (head read mode) or a builder cell (head write mode).
     The register, the argument-stack entry and the saved registers hold the same type. JET finds
     no dispatch in the loop; AllocCheck confirms the register save and load, the argument pointer's
     operations and the record discipline allocate nothing, and that the argument stack's push
     allocates only where it grows (static_analysis_body.jl).
  3. **Write mode under `occurs_check` `true`/`error`: read mode over a freshly built compound**
     (`_fresh_compound`, `# DIVERGES`): the variable is bound to a compound of fresh variables at
     once and the rest of the head reads it, so the occurs check runs where unification runs. Under
     `false` the builder writes as upstream does (`_bopen!`/`_bclose!`: every argument cell starts as
     a fresh variable — upstream `setVar`s each cell it allocates — so `H_VOID` in write mode leaves
     one). The condition is met: the three-mode differential exercises EVERY head instruction under
     `true` and `error`, the list forms and `H_FIRSTVAR` included (coverage asserted per mode).
  4. **Exceptions: upstream's no-catcher path, now.** `H_VAR` under `occurs_check=error` raises
     `error(occurs_check(V, T), context(Name/Arity, _))` (`PL_error`, pl-error.c, for the running
     predicate) through `PL_raise_exception`; `b_throw` finds no catcher (catch/3 is V9) and the query
     returns `PL_S_EXCEPTION` under `PL_Q_CATCH_EXCEPTION`, the ball in `exception_bin`, read with
     `PL_exception`; `PL_Q_PASS_EXCEPTION` leaves it pending. The gate compares the complete term.
  5. **Clause GC: `markPredicatesInEnvironments`' frame scan, ported** (pl-gc.c): every live frame
     below `lTop` records its generation, so a clause retracted while a query runs through it is not
     reclaimed until the query is done.
  6. **`[H|T]` and `'[|]'(H,T)` match the same way whichever instruction** (Q2): `H_LIST`,
     `H_RLIST` and `H_LIST_FF` accept a `$expr/3` whose head unifies with `'[|]'`, and `S_LIST`
     given a `$expr/3` first argument falls through to `S_STATIC` as for an unbound one. The pinned
     pair now covers a list head and an `S_LIST` predicate, both directions.
  * Defaults agreed: a query handle is the query frame's bare position (a closed one answers 0 —
    only what upstream guarantees is pinned); `$c_call_prolog/0` lives in the global data, outside
    the user table; query records in a pool; a supervisor's clause references in a side table
    (`codes_crefs`); the builder flat and reset with the argument stack (`aSave`, at every site
    upstream resets `aTop`); one dereferencing argument view per source; quirks kept (`S_STATIC`'s
    `ARGP + arity` adds whole frames — `8·arity` positions, probed); `NOT PORTED` markers for the
    debugger, the alerted blocks and the profiler; `PL_new_term_ref`'s foreign-environment check;
    bindings compared up to renaming; `CHP_TOP` leaves its dead frames for `restore_after_query`.
* **Ported:**
  * the run loop (`PL_next_solution`, `PL_next_solution_guarded`): `depart_or_retry_continue`; the
    supervisors `S_VIRGIN`, `S_UNDEF`, `S_STATIC`, `S_DYNAMIC`, `S_MULTIFILE`, `S_TRUSTME`,
    `TRUST_CLAUSE`, `S_LIST`; every `H_*` read and write (`h_const` included), the `B_*` they jump
    to; `I_EXIT`, `exit_continue`, `I_EXITFACT`, `exit_checking_wakeup`, `I_EXITQUERY`; backtracking
    — `unify_backtrack`, `shallow_backtrack` (the choice point moves, the failed attempt's records
    dropped first), `deep_backtrack` (`CHP_CLAUSE`, `CHP_TOP`); `b_throw` to `b_throw_resume`
    without a catcher; `SAVE_REGISTERS`, `LOAD_REGISTERS`, `ENSURE_LOCAL_SPACE`;
  * the query API (pl-wam.c): `initVM` (the top clause, `I_EXITQUERY`), `PL_open_query`,
    `PL_next_solution`, `PL_cut_query`, `PL_close_query`, `discard_query`, `restore_after_query`,
    `PL_exception`, `PL_current_query`; `leaveFrame`, `discardFrame`, `discardChoicesAfter`,
    `dbg_discardChoicesAfter`, `resumeAfterException`; `queryOfFrame`, `parentFrame`;
    `QueryFromQid`, `QidFromQuery`, `pushArgumentStack`/`f_pushArgumentStack`; the `queryFrame`
    record (upstream's 47 words: choice at +21, saved environment +30, top frame +31, frame +39);
    the flags and return codes (SWI-Prolog.h);
  * the supervisors (pl-supervisor.c): `initSupervisors`, `createSupervisor` and its selectors,
    `setDefaultSupervisor`, `freeCodesDefinition` (a changed predicate returns to `S_VIRGIN`),
    `equalSupervisors`, `getClauses`; `chainPredicateSupervisor` is the identity (no det, SSU or
    meta-predicate declarations exist); `arg1Key` (pl-comp.c);
  * `PL_error` for `ERR_OCCURS_CHECK` and `PL_raise_exception`; `markPredicatesInEnvironments`'
    frame scan; `setGenerationFrame`'s frame-writing form.
* **AN UPSTREAM DEFECT, FIXED here:** pl-comp.c `arg1Key` lists `H_MPZ` but not `H_MPQ`, which falls
  to `assert(0)`: swipl 10.1.16 ABORTS on the first call of `p(1r3, a). p(2r3, b).` (two clauses —
  the list supervisor's test runs; probed: `arg1Key: Assertion failed`). The kernel treats `H_MPQ`
  as `H_MPZ` (not found), `# DIVERGES`. Recorded as #4 in `docs/upstream_reports.md`, pinned in
  test/foreign/test_query.jl; the upstream report is drafted, for the user to file.
* **Gate:**
  * test/foreign/test_query.jl (term-generic: the three types): answers, return codes and
    determinism as libswipl's (1, 1, `PL_S_LAST` under `PL_Q_EXT_STATUS`, then 0); the supervisors
    each call installs; POSITIONS identical to libswipl's — the query frame, its choice point, top
    frame and frame at upstream's offsets, the first term reference after an answer at +63
    (non-deterministic) or +45 (deterministic), after a failing call of f/1 at +61 and of h/2 at +69
    (the `S_STATIC` quirk), a nested query at +63; nested queries (`PL_S_NOT_INNER`); cut keeps the
    bindings and close undoes them; after a deterministic last answer the next call fails and no
    term reference can be made; a closed handle answers 0; an uncaught exception, caught and passed;
    the `except` arm; a Julia exception closing the query; an instruction the loop does not hold yet
    refused by name; clause GC while a query runs through a retracted clause (erased, not reclaimed,
    until the query is closed); the argument stack and the builder back at the query's height at an
    answer after a head failed inside a nested compound;
    warm, the push and the register save allocate nothing;
  * test/core_lang/test_head_unify_swipl.jl (term-generic): 400 random clause heads and goals plus pinned
    cases under `occurs_check` `false`, `true` and `error` — bindings up to renaming, failures and
    the complete error term identical to swipl's, every head instruction exercised in each mode;
  * test/db/test_index_swipl.jl: the VM answers every call as the index path does, and its
    determinism is swipl's; test/db/test_index_argv.jl: a bound argument narrows the index through
    both views; test/core_lang/test_expr_functor.jl: the pinned `$expr` pair, wired to the VM and
    turned from `@test_broken` into `@test`, extended to a list head and an `S_LIST` predicate,
    both directions;
  * the static gate: every new method in the manifest (JET, no dispatch), AllocCheck on the
    allocation-free ones and on the argument stack's push.
* **Mutation-proved — 16 of 18 caught at verdict level (MQ1-MQ18; the driver asserts every replacement
  matches once and the tree is byte-identical after each revert):** `argv_at` not dereferencing, no
  frame scan, `_bopen!` leaving the cells as they were, `S_LIST` failing on a `$expr/3`, `H_RFUNCTOR`
  ignoring the `$expr` rule, `I_EXITQUERY` never deterministic, `PL_S_LAST` without
  `PL_Q_EXT_STATUS`, `S_STATIC`'s quirk as `+ arity`, `PL_error` without its context, no reset at
  `unify_backtrack`, `PL_new_term_ref`'s check removed, `deep_backtrack` past the top frame, the
  dispatch tree's leaves without their equality test, and port_check's two changes (a `@label` is a
  definition; the VM inventory compares its rows only).
  * **Two tests were BLIND until the mutants said so, and were fixed:** (1) the clause-GC test passed
    without the frame scan — a reclaimed clause is only unlinked here, the choice point still holds
    it, so the answers cannot show it; and a clause erased in the CURRENT generation is never garbage
    (`ddi_is_garbage`), so the generation, not the scan, had kept it. The test now moves the
    generation past the erasure and reads `erased_clauses` (1 while the query runs, 0 after it is
    closed). (2) the reset test read the heights after the close, which resets them anyway; it now
    reads them at an answer after a head failed INSIDE a nested compound — a repeated variable
    (`f(A, A)` against `f(a, b)`), since a deep index skips a clause that differs at a constant.
  * **Survive, with the reason:** MQ6 (`exit_continue` not lowering `lTop`) and MQ18
    (`shallow_backtrack` not dropping the failed attempt's records) — facts cannot reach them: every
    exit returns to `I_EXITQUERY`, which sets `lTop` itself, and a fact's attempt leaves no records.
    Both are written into V4b's gate. MQ15 (the builder's heights not reset) — no instruction can fail
    while a builder frame is open: write mode never fails under `false`, and `true`/`error` build no
    frame. The reset stays (the user's default: the builder is reset with the argument stack).
* **Not here:** rules (`I_ENTER`, `I_CALL`, `I_DEPART`, the remaining `B_*`, `L_*`): V4b; `I_CUT`'s
  execution: V6; catch/3 and the catcher search: V9; foreign predicates and `S_UNDEF`'s
  `existence_error`: V5 (`S_UNDEF` raises `NotPortedError` by name until then).

**V3 — machine state: BUILT (2026-10-05)** (port_inventory row V3; src/pl-incl.jl § the local stack,
src/pl-global.jl, src/pl-inline.jl, src/pl-gc.jl, src/pl-alloc.jl, src/pl-wam.jl, src/pl-fli.jl,
src/pl-setup.jl). Plan: two research memos (subagents), one on upstream's structs and one on its
operations, every claim cited by line and the decisive ones re-read; their open questions went to
the user.
* **Decided by the user (2026-10-05):**
  1. **Header widths: upstream's word sizes** — frame 8, choice point 9, foreign frame 6 (the default
     x86_64 Linux build: `O_PROFILE` on, `O_DEBUG` off). So a position is swipl's own, and
     `prolog_current_frame/1` and `prolog_current_choice/1` are the oracle for frame placement, reuse
     and popping — compared as DIFFERENCES, since swipl's base holds its own toplevel frames.
  2. **Decision 3's drop rule, refined four ways** (upstream's actual behaviour):
     * dropping lowers a count; a dropped record stays readable until a push reuses it —
       `exit_continue` reads `FR->programPointer` and `FR->parent` after `lTop = FR` (vmi:2178-2194);
     * backtracking drops the records above the resumed choice point BEFORE moving it, because
       `lTop` can rise over dead records there (vmi:6503-6528, 6712) — V4a's;
     * nothing drops a frame being filled above `lTop` (`normal_call`, vmi:1869) — ASSERTED;
     * query and foreign-frame handles stay positions, found by walking their chains.
  3. **Clause choice points: a pool per slot.** Each choice-point record owns its `clause_choice`, as
     upstream embeds the struct and passes a pointer to it; `newChoice` resets it; allocation is
     measured after the pool has grown, and growth is the only allocating path.
  4. **The V3/V4a boundary:** V3 tests its own primitives; `restore_after_query`, `PL_open_query` and
     instruction-level behaviour (an exit, last-call reuse) come with V4a.
  * Defaults agreed: a function unreachable upstream is NOT ported (`TRY_CLAUSE`: port_inventory §
    "Not ported: unreachable upstream", re-checked by tools/upstream_drift.jl); upstream's no-ops and
    quirks inside ported functions are kept as written, each with a comment (`f_hasSpace`'s unsigned
    division, `DiscardMark`); omitted fields still count in the widths; the flag and magic values
    verbatim; dropped records not cleared; bounds checks on until V4's flatness gate.
* **Choice made while building (told to the user the same day):** the records are MUTABLE,
  preallocated and reused per index, where decision 3 said immutable. Upstream writes their fields
  one at a time (`normal_call`, the last-call branch, `ch->value.clause = chp`); the kernel already
  ports such structs as mutable (`clause_ref`, `definition`, `clause_choice`); and the pool keeps
  growth the only allocating path. Positions, indices and the rest of decision 3 are as decided.
* **Ported:**
  * the layout — `SIZEOF_*`, `ARGOFFSET`, `VAROFFSET`/`VARNUM` (moved from pl-comp.jl), `MAXARITY`,
    `MINFOREIGNSIZE`, `LOCAL_MARGIN`, `argFrameP`/`varFrameP`/`refFliP`;
  * the records `localFrame`, `choice`, `fliFrame` and `choice_type`; the `FR_*` flags and
    `setNextFrameFlags`, `lcoSetNextFrameFlags2`, `lcoSetNextFrameFlags`, `tcallSetNextFrameFlags`,
    `setFramePredicate`, `levelFrame`, `setLevelFrame`;
  * `newChoice`; `copyFrameArguments`; `open_foreign_frame` and `PL_open_foreign_frame`,
    `PL_close_foreign_frame`, `PL_rewind_foreign_frame`, `PL_discard_foreign_frame`;
  * `PL_new_term_refs`, `new_term_ref`, `PL_new_term_ref`, `PL_reset_term_refs`, `PL_copy_term_ref`,
    `PL_put_term`, `linkValI`;
  * `f_hasSpace`, `hasLocalSpace`, `growLocalSpace`, `growStacks` (the local stack only: nothing moves,
    so upstream's shifting has no counterpart), `ensureLocalSpace`, `raiseStackOverflow` (a Julia
    `LocalStackOverflow` until V5's exception path);
  * `emptyStacks` — the base foreign frame, so no `term_t` or `fid_t` is 0; the engine's permanent
    term references are not allocated (their subsystems are not ported);
  * `DiscardMark` (a no-op: no `mark_bar`), `NoMark`, `isRealMark`, and `Undo!` refusing a `NoMark`;
  * LD's local stack: the cells, the three record pools, and the registers under upstream's macro
    names (`lTop`, `lMax`, `BFR`, `environment_frame`, `fli_context`); its initial size upstream's
    `minlocal` (4096 positions) and its limit `stack_limit`'s default (1 GiB, in words).
* **The record discipline** (src/pl-wam.jl): `pushFrame!`, `pushChoice!` and `pushFliFrame!` are
  upstream's casts of a position to a record, each asserting that no live record of its kind lies at
  or above the position (a missed drop is caught there); `dropRecords!` and `lowerLTop!` drop on every
  lowering, asserting that nothing dropped lies at or above `lTop`; `fliFrameOfFid` is the cast of a
  handle.
* **`VAROFFSET` is slot + 8 now.** swipl's `vm_list` prints `VARNUM`, so the V2 differential could not
  see the change, and it passes unchanged. One test printed `VAROFFSET(slot)` as if it were the slot
  (test_analyse_variables_swipl.jl); it agreed with swipl only because the identity hid the
  difference, and now prints the slot.
* **Gate — test/core_lang/test_local_stack.jl** (term-generic: 281 assertions on the three types):
  * POSITIONS ARE SWIPL'S — a callee's frame `8 + variables` above its caller's and a
    non-deterministic callee's choice point `8 + variables` above the callee's frame, from the
    KERNEL's compiled `clause.variables`, on 9 caller/callee pairs (voids, arguments only, many body
    variables, a head compound; facts and rules as first clauses): identical to swipl 10.1.16's
    differences, pinned and live;
  * every lowering drops the records at or above it and a dropped record stays readable (an exit's
    frame read after it); a frame being filled above `lTop` is never dropped; a missed drop is caught
    at the next push, for each kind; a reused choice point carries nothing over; foreign frames
    (close keeps bindings, rewind and discard undo them, a bad handle is refused); term references;
    `copyFrameArguments`; the frame flags; growth, the limit, `f_hasSpace`'s quirk;
  * warm, a frame + choice point + foreign frame cycle and 1000 nested frames with choice points
    allocate nothing; growth does. The static gate (test_static_analysis.jl) checks the same claims
    — `must_not_allocate` on `newChoice`, the pushes, the drops and the foreign frames — and every new
    method for runtime dispatch.
* **Mutation-proved:** MV1–MV16, each caught at its own test — `lowerLTop!` not dropping, the pooled
  `clause_choice` not reset, the in-construction assertion removed, a 7-word frame and an 8-word
  choice point (the swipl positions), `f_hasSpace` without its quirk, `newChoice`'s `BFR` assertion
  and `pushFrame!`'s guard removed, the choice pool not growing, a close leaving `lTop`, a rewind not
  undoing, `copyFrameArguments` reversed, a drop clearing its frame, `newChoice` allocating,
  `emptyStacks` without its base frame, and the unreachable check counting a definition as a use.
  The first allocation mutant (`length(copy(trail))` on an empty trail) SURVIVED because the compiler
  elides it — no allocation happened; the mutant that allocates into LD was caught.
* **Moved to V4a** (port_inventory row V4a): `queryFrame`, `initVM` and `$c_call_prolog/0`,
  `discard_query`/`restore_after_query`, `SAVE_REGISTERS`/`LOAD_REGISTERS` with `ARGP`'s two forms,
  the backtracking drop, `chp` copied into the pooled `clause_choice`, `firstClause!`/`nextClause!`
  on the frame's slots, and `setGenerationFrame`'s frame-writing form.

**V2 — `!` compiled: BUILT (2026-10-05)** (the user's answer to V2's choice Q1: the COMPILE side
belongs with the body compiler, execution stays in V6; src/pl-comp.jl, src/pl-vmi.jl, src/pl-incl.jl,
src/pl-funct.jl).
* **Ported as is:**
  * compileSubClause's `ATOM_cut` branch (c:3521-3526): `I_CUT`, or `cut.instruction` on `cut.var`
    when a local cut is set;
  * `cutInfo` (c:372-375) and `compileInfo`'s `cut`, zeroed per clause (c:2068-2069). Only V9's
    control constructs set a local cut (`\+`, `->`, `*->`; c:2522, 2570, 2606), so today it is
    always zero;
  * `COMMIT_CLAUSE` (pl-incl.h) on the clause when its body's first instruction is `I_CUT`
    (c:2165-2167, `OpCode(ci, bi)`);
  * `I_CUT` declared (pl-vmi.c:2572, `VIF_BREAK`, no operands), numbered after the instructions
    already declared. Its execution, `discardChoicesAfter`, is V6.
* **Gate — test/compile/test_body_code_swipl.jl:**
  * all six qsort clauses identical to swipl, partition/4 clause 1 (`X =< Y, !, …`) included;
  * four more pinned live clauses: a cut first, last, mid-body, and `p :- !` — 427 clauses in all;
  * the random generator draws `!` goals, and the coverage check requires `i_cut`;
  * `COMMIT_CLAUSE` set exactly when the body starts with `!`: pinned both ways, qsort's clause
    included (its `X =< Y` comes first);
  * MC1–MC3 caught at verdict level: `!` compiled as a call to `!/0`, `COMMIT_CLAUSE` never set,
    `COMMIT_CLAUSE` set for a cut anywhere in the body.
* **Recorded for V6, the user's obligation:** V2 refuses an inline-compiled goal whole (Q5). V6 ports
  upstream's inline-vs-call decision AS IS, case by case, with the differential covering each branch
  (port_inventory row V6).

**V2 — the body compiler: BUILT (2026-10-05)** (port_inventory row V2; src/pl-comp.jl, src/pl-vmi.jl,
src/pl-funct.jl). Plan: a research memo on upstream's code paths (subagent), with its open questions
Q0–Q14. The user was asleep and had said to continue without asking, taking SWI as is and listing
every choice for review — the choices are in the list below.
* **Ported:**
  * the body side of `compileArgument` — every head/body choice keyed as upstream keys it, `H_LIST_FF`
    only in a head, `B_POP` in a body;
  * `compileSubClause` for plain goals, `compileBody` for `,`, `reverse_code`, `lco`;
  * the rule path of `compileClause`: `I_ENTER`, the body, `I_EXIT`; a body `true` makes a fact.
  * 31 instructions declared with upstream's flags and operand kinds (`code_info` gains `flags` and
    `argtype`; `codeTable` is a tuple lookup); `VARNUM`, `MAXARITY`, `NOT_CALLABLE`,
    `MAX_ARITY_OVERFLOW`.
* **Gate — test/compile/test_body_code_swipl.jl, live against swipl 10.1.16, all three term types:**
  * whole-clause code, operands by kind and the `L_NOLCO` label, IDENTICAL to swipl's on 423 clauses:
    6 pinned with swipl's code written in the file, 17 pinned live, 400 random rule clauses;
  * nreverse and qsort as swipl CONSULTS bench/programs, each clause tied to the kernel's by `=@=`;
  * coverage: every declared body instruction occurs, LCO with `I_TCALL` and with `I_LCALL`, an empty
    L-block, LCO abandoned;
  * MB1–MB18 caught at verdict level (the plan's 16, plus clause/2 and retract/1 answering rules).
* **Choices made, for the user's review (V2 plan Q0–Q14):**
  * Q0: M1 first, as planned (done, `2c04b1e`).
  * **Q1, `!`: NOT compiled in V2** — the inventory put `I_CUT` in V6, and moving it was a plan
    change. **Answered (user, 2026-10-05): compile it now, execute it in V6** — done, § "V2 — `!`
    compiled" above.
  * Q3: compileSubClause's names in the global data, once per database (`subclause_names`), like the
    control functors.
  * Q4: a construct not yet ported throws `NotPortedError(culprit, what, step)` before any code.
  * Q5: an inline-compiled functor (`=`, `==`, `\==`, `var`, `nonvar`, the nine type tests, `arg/3`,
    `$call_continuation/1`, `$shift/1`, `$shift_for_copy/1`) and `is/2` are refused whole —
    upstream's inline compilers sometimes fall back to a call, but refusing never emits wrong code.
    **Answered (user, 2026-10-05): fine as an interim**, with an obligation on V6 to port upstream's
    decision as is (port_inventory row V6).
  * Q6: `type_error(callable, Body)` — the WHOLE body, probed in swipl (`p :- q, 1` reports
    `(q,1)`). `lookupBodyProcedure` keeps its own refusal; compileSubClause returns NOT_CALLABLE
    before reaching it, as upstream.
  * Q7: `L_ATOM`/`L_SMALLINT` and `I_LCALL` copy the `B_*`/`I_DEPART` operand word, as upstream.
  * Q8: opcodes renumbered in pl-vmi.c's order (`B_VAR0 + index` needs them consecutive).
  * Q9: `code_info` carries `flags` and `argtype` verbatim.
  * Q10: clause/2 and retract/1 answer for the body `true`, so they skip rules; retractall/1 takes
    them (it decompiles only the head).
  * Q11: `MAXARITY` now. Q12: `compileClause`'s body is `Union{Nothing, T}`. Q13: the program tie
    via swipl's consult and `=@=`. Q14: a rule of a multifile predicate is refused (`I_CONTEXT`).
* **Kernel-only, pinned:** `$expr/n` as data in a body is `B_FUNCTOR $expr/n` (literal 0, its
  children every argument); a value SWI has no type for is an opaque `B_ATOM` literal, moved by
  `L_ATOM` with the same index; `$expr/n` as a goal is `type_error(callable, Body)`.

**M1 — the code map, generated: BUILT (2026-10-04)** (port_inventory row M1; tools/port_check.jl).
* **One tool.** `tools/port_check.jl --write-inventory` writes three generated blocks:
  * the inventory table, now with a `diverging` column;
  * a COVERAGE block in port_inventory.md;
  * the CODE GRAPH (§ "Code graph" above).
  `port_check` holds each block to its generator, running both sides through ONE extractor
  (`_section`). Both sides must be non-empty: an empty generator is a violation, even against an
  empty block.
* **Coverage** is per upstream file AT ITS RECORDED COMMIT: functions ported, of how many, how many
  diverge. Upstream's functions come from `upstream_names`' heuristic (moved here from
  tools/upstream_drift.jl; it now also counts pl-vmi.c's `VMI(NAME, …)` instructions). Counting
  needs the checkouts, so the block is compared where every checkout it names is found — the local
  suite asserts that it WAS compared — and otherwise must be present and non-empty, as in CI. That
  follows port_check's existing split for upstream existence.
  `# choice made for the user's review:` upstream DRIFT (commits since) is not a block, because it
  moves whenever the checkout is pulled; it stays `tools/upstream_drift.jl`'s report.
* **The code graph** covers src/ in include order, with an edge wherever a file uses a name another
  file defines. It is checked everywhere.
* **The hand-kept "What is here now" table is CHECKED, not replaced:**
  * every src/ and bench/ file must be listed;
  * every listed file must exist;
  * each row's upstream column must name exactly its files' UPSTREAM headers.
  Its first run found five rows whose upstream column had drifted from the headers (pl-index,
  pl-comp, pl-vmi, pl-global, pl-hash) and the missing `src/LogicKernel.jl` row; all are fixed.
* **First numbers:** 276 of 1541 upstream functions ported, 91 diverging. **Read the total as a
  per-file measure** (user, 2026-10-05): 1541 counts the functions of the upstream files the kernel
  already touches (the coverage block's rows), not of the engine. pl-wam.c, pl-arith.c, pl-fli.c and
  the tabling files have no row yet, and a file like pl-thread.c counts all 267 of its functions for
  the 4 ported. The ratio says how far each touched file is ported, not how far the port is.
* **Gate:** test/test_port_check.jl's M1 fixture covers each block stale, empty, missing, an empty
  generator against an empty block, and every "What is here now" failure. MM1-MM7 are caught: a
  stale block never reported, no empty-generator guard, an unlisted file passing, extra upstream
  names passing, coverage counting every marker, a graph without edges, coverage computed but not
  compared.
* **Found while building it — the preflight used a STALE CHECKER.** `tools/warm.sh preflight`
  loaded tools/port_check.jl into the daemon once (`isdefined(Main, :port_check) || include`), so
  every later preflight in that daemon held the tree to the FIRST checker it had loaded. M1's own
  docs failed against the pre-M1 inventory format. It now loads the current checker into a fresh
  module each run, at both sites (the port_check step and the stale-method classifier).
  tools/test_warm.sh gained a case: after an earlier preflight, the checker's inventory end marker
  is renamed in place (a Blue-neutral edit), and the next preflight must fail BY THAT VERDICT. A
  first version planted an unformatted line and failed on the format check instead, which the
  verdict assertion caught. Mutation-proved: with the old load restored, the verdict assertion
  fails (43/44). The bare exit-code assertion does NOT discriminate here: a changed
  test_port_check.jl makes the preflight fail through the changed-test path anyway.

**V1 — procedures and call operands: BUILT (2026-10-04)** (user's decisions, same day; src/pl-incl.jl,
src/pl-global.jl, src/pl-proc.jl, src/pl-comp.jl).
* **One way to get a predicate, as upstream.** `lookupProcedure(name, arity, m)` is pl-proc.c's
  lookup-or-create in the module's procedure table, keyed by the FUNCTOR (the name's `sym_key` and
  the arity). It returns a `Procedure{T}` (pl-incl.h `struct procedure`, wrapping the definition).
  `:- dynamic` is `setDynamicDefinition!` on the found definition. The old flags argument is gone, and
  a test that needs a FRESH predicate uses a fresh database (no escape hatch in the API).
* **Modelled as a module, with one.** `module_t{T}` (pl-incl.h `struct module`; `module` is a Julia
  keyword, `module_t` is SWI-Prolog.h's own name) holds the name `user` and the procedure table; GD
  holds it as `modules_user`, reached through `MODULE_user(gd)`. `# DIVERGES`: one module per
  database, no `system` module until built-ins are registered there (V5).
* **`isCurrentProcedure`, `hasClausesDefinition`, `isDefinedProcedure`** are ported. "Defined" is a
  `PROC_DEFINED` flag or a clause visible in the current generation.
* **`lookupBodyProcedure(gd, goal, tm)`** takes the GOAL, not its functor (`# DIVERGES`). A goal whose
  head is not a symbol (`$expr/n`) has no functor: it is a call through the meta-call (V9), and it is
  refused with `CallableTypeError` (`type_error(callable, Goal)`). So are the other goals
  compileSubClause finds `NOT_CALLABLE` (c:3464-3559), probed in swipl 10.1.16: a number, a string,
  `[]`; `'[]'` and a compound named `[]` are callable. The branch preferring an ISO `system`
  predicate is deferred to V5.
* **Call operands index the clause's PROCEDURE TABLE** (`clause.procedures`, built by
  `addProcedure!`, 1-based), as literal operands index the literal table (`# DIVERGES`: upstream's
  operand is the `Procedure` pointer). Decoding stays local to the clause. A differential compares
  procedures by name and arity, never by index. Nothing emits `I_CALL` until V2.
* **`compileClause(gd, head, body, proc, m)`** now has upstream's parameters: the procedure and the
  module, and `body` (`nothing`: the rule path is V2). `compileInfo` gains upstream's `module`
  (`module_`) and `procedure`.
* **`Output_3!`, `Output_an!`, `Output_n!` in full:** the operands are a tuple where upstream passes
  a pointer.
* **`B_FUNCTOR`'s literal needs nothing new.** Upstream gives `B_FUNCTOR`/`B_RFUNCTOR` the SAME
  functor operand as `H_FUNCTOR`; only the opcode follows `where & A_HEAD` (c:3208-3213). L2's
  operand already names the literal that holds the head SYMBOL TERM, which is what construction
  needs. `$expr/n` (literal 0) constructs from its n children, the head being argument 0. EMITTING
  `B_FUNCTOR` is the body side of `compileArgument`, which is V2: alone it would leave the children
  compiled as `H_*`.
* **The remaining `compileInfo`/`clause` fields** belong to subsystems not yet ported. `compileInfo`
  lacks `islocal`, `subclausearg`, `head_unify`, `argvars`, `argvar` (V9), the warnings,
  `progress` and the module contexts. `clause` lacks the source-file fields, `references` and
  `tr_erased_no`; `code_size` is `length(codes)`.

**Q2 — a reserved `$expr/n` functor: APPROVED**, marked `# DIVERGES`. Its standard-order position is
defined explicitly: with the other compounds, by arity then name, as `compareStandard` already orders
them. It stays OUT of the swipl differentials (SWI cannot express it) and has its own tests.

**Q2 — BUILT (2026-10-03), on all three term implementations** (src/pl-ressymbol.jl § `$expr/n`).
* **The functor.** A compound whose head is not a symbol — a variable, a grounded value, a compound,
  or none (`()`) — has the functor `$expr/n`, `n` its number of children, every child an argument.
  Its name is RESERVED, as upstream's reserved symbol `dict` names the dict functor (pl-dict.c
  `FUNCTOR_dict`): `'$expr'(X, a)` is another functor. No term is the symbol `$expr`.
* **Standard order** (`compare_functors`): arity first — `f(a) @< (X a)`, `(X a b) @> f(a, b)` —
  then `$expr` before every symbol name of the same arity (a reserved name before text atoms, and
  `$` before `[` by `strcmp`), then the children left to right. Before Q2 the kernel ordered by
  the number of CHILDREN, so `(X a) @< f(a)`.
* **Head code**: `H_FUNCTOR $expr/n` (`expr_functor(n)`, one operand per `n`) where it was
  `H_FUNCTOR 0` — the arity is in the code. The word is a hashed functor word like every other
  until V1's functor table; it carries `FIRST_MASK`'s bit, which no upstream key or operand
  carries, so `isExprFunctor` is exact. **Superseded by V1 L2:** the operand is
  `functor_operand(0, n)`, literal 0, which no symbol-headed compound has, and the bit and its
  helpers are gone.
* **Unification is unchanged and decides the index**: `$expr/n` unifies with ANY compound of `n`
  children, child by child (`(X a) = f(a)` binds `X = f`; `_unify_functor`). So `argKey` and
  `indexOfWord` key it as a WILDCARD, as a variable. Among same-functor clauses it then keeps the
  index from going deep, as `q(_)` does in swipl (10.1.16, probed) — where a deep key would read
  its arguments misaligned with theirs. The VM must match the same way (V2–V4): `H_FUNCTOR $expr/n`
  against any compound of `n` children, `H_FUNCTOR f/k` against a `$expr/(k+1)`.
* **Reviewed (user, 2026-10-04): all three choices approved** — the reserved name; child-by-child
  unification with the index wildcard; the marking bit. Two requirements came with them, both done:
  * the VM's obligation is pinned NOW, in both directions, as expected failures (`@test_broken`)
    until V4a: `H_FUNCTOR $expr/n` against any compound of n children, and `H_FUNCTOR f/k` against
    a `$expr/(k+1)` argument. `ok1 == ok2` fails a VM that does one side only, and a
    `PL_next_solution` in the kernel without the test wired to it fails too (V4a's gate);
  * the bit (`EXPR_FUNCTOR_MASK` = upstream's `FIRST_MASK`) is documented beside the word layout
    (src/pl-incl.jl) and tested: no `name/arity` word over 20000 random names and arities, no
    symbol-headed head's operand, and no all-ones `MK_FUNCTOR`/`MK_ATOM` input carries it.
    (Retired in V1 L2, with the test re-pointed to literal 0.)
* **`=@=` and the hashes** already treated it as one functor (same number of children; name hash 0;
  `C` and the child count) — now named so.
* **Pinned failing first** (test/core_lang/test_expr_functor.jl, 48 assertions on each
  implementation): 4 standard-order and 3 head-code assertions failed before. The index assertions
  passed before (key 0) and are mutation-proved: keying `$expr/n` by its word drops the answer of
  `p(f(a))` from `p((X a))`.
* **Found while building it — Q1's `[]` as a FUNCTOR name:** functor words named a symbol by its
  `sym_hash`, a text hash, so `[](K)` and `'[]'(K)` shared a key that swipl's two atom handles never
  share (`[](a) \== '[]'(a)`, probed). The index differential pins it (`nqf_d`, `nqf_s`: before the
  fix, `nqf_d('[]'(3), 58)` was nondet where swipl is det, and the assessment differed). Now a functor
  named `[]` is named by `ATOM_nil`, as the atom `[]` is keyed (`_functor_name`).

**Q3 — the builder under `false`, upstream's order under `true`/`error`: APPROVED.** Upstream confirms the
split: under `false`, `H_VAR` in write mode copies (or trails a local-stack variable to the new cell) and
continues; otherwise it falls through to `do_unify`/`unify_ptrs` against the already-bound structure.
Two additions:
* the builder is a **stack** (write mode nests — an `H_FUNCTOR` inside a structure being built) and is
  reset on every `CLAUSE_FAILED`;
* the three-mode differential extends to **head unification** in V4a: random clause heads called with
  random goals under all three `occurs_check` modes, comparing bindings, failures and error terms with
  swipl.

**Condition 1 — memory outside the local stack.** Upstream keeps deterministic programs small two ways:
trail elision (`Trail()` skips global cells newer than `mark_bar`) and garbage collection of the global
stack. The kernel trails every binding and shrinks the binding store only by backtracking to a mark, so
a long deterministic run (`concatenate/3` on 10⁵ elements, an agent loop) grows the trail and the store
linearly even with a flat local stack — and a local-stack gate cannot see it.
* Trail length and store size join the flatness measurements, so the growth is VISIBLE and measured.
* **Design item, recorded now: a binding-store collector** — the analogue of `pl-gc.c`'s marking from
  frames and choice points — designed before any long-running workload uses the VM.
* Correction to decision 2's reasoning: a key DOES have an age. Kernel-issued keys come from a monotonic
  counter, so a key's value is its age, and a choice point can record the counter at creation. That
  makes `mark_bar`-style elision possible — but an untrailed binding then needs the collector to reclaim
  its entry. Both routes lead to the same collector; which one is decided when it is designed.

**Condition 2 — decision 5's dispatch: typed function pointers are a candidate.** Every built-in has the
same signature, so a `FunctionWrappers.jl`-style typed wrapper (one concrete type per term type `T`)
stores a callable pointer in a table without dynamic dispatch — what upstream does with C function
pointers. It would make `PL_register_foreign` the same mechanism instead of a deferred separate design,
and avoid one very large generated function. V5 measures both (call overhead, JET, compile latency) and
takes the faster one that passes the zero-dispatch gate.

**Condition 3 — registers mirror upstream's `SAVE_REGISTERS`/`LOAD_REGISTERS` exactly.** Of decision 3's
two options, the second: run-loop locals for speed, written back to `LD` and reloaded at exactly the
places upstream calls `SAVE_REGISTERS(QID)`/`LOAD_REGISTERS(QID)`, under those names — so the port stays
line-for-line comparable and a missing sync shows as a missing macro.

**Condition 4 — V9 is split** into separate steps, each with its own gate, when it is reached.

**Decision 3, refined when V3 was built (user, 2026-10-05):** upstream's struct widths, so positions
are swipl's; four refinements of the drop rule; a per-slot `clause_choice` pool; mutable pooled
records — § "V3 — machine state" below. They take precedence over decision 3's text where they differ.

## Still to come

* **A test-time cost, not a defect (found 2026-10-03).** The reference type orders two Julia-only
  host types by `string(T)` (`_cmp_types` in src/default_term.jl), and printing a type searches
  every loaded module for an alias (`make_typealias`), so its cost grows with the modules loaded —
  one per test file per implementation. Production payloads (`Int64`, `Float64`, `String`) never
  reach it; the conformance suite's exotic values do, in its O(n³) transitivity loop (profiled).
  A cheaper reproducible order on types would remove it.
* ✅ **The standalone consumer** — done (four swipl-bench programs, above). It found a real gap on
  the way: a client could not read a symbol's NAME or a grounded VALUE through the public API, so
  `Term{G}` gained `sym_name` and `gnd_value` (the interface rightly has neither — the kernel never
  needs them). Each new subsystem extends the consumer with what it makes possible.
* ✅ **The clause database** — generations, retract, clause GC, `retract/1`, `retractall/1`,
  `clause/2` — done, with test_jit.pl's `remove`/`retract`/`retract2`/`clause` and test_db.pl's
  `retract`/`retractall` units.
* ✅ **Variant checking and term hashing** (`=@=`, `term_hash/2`, `variant_sha1/2`,
  `variant_hash/2`) — done 2026-10-03. Measured by `tools/bench.jl` on 8191-cell trees against
  swipl 10.1.16: `=@=` 0.2–0.4× swipl's time, `term_hash` 0.45×, `variant_sha1` 1.3–1.9×,
  `variant_hash` 1.5–2.1×. The variant digests' remaining cost is the variable-numbering map, which
  upstream does not pay — it overwrites each variable's cell in place, and interface terms cannot
  be marked.
* ✅ **Unification** (`=`, `\=`, `unify_with_occurs_check/2`, `?=`, `unifiable/3`, the `occurs_check`
  flag) — done 2026-10-03, SWI's design: bindings in a store with a trail, undone to a mark. Against
  swipl 10.1.16 on 8191-cell trees (`tools/bench.jl`): 2.4–5.5× swipl's time, no allocation. The
  first version linked every compound pair for cycle detection as upstream does and was 27–38×
  slower — the link is one pointer write upstream and an identity-map entry here — so only pairs
  reached through a binding are linked (DIVERGES in `do_unify`). The rest is the store itself: a
  `Dict` entry per binding where SWI writes a cell. The differential found a swipl abort in the
  occurs-check error path (`docs/tracking/repros/swipl_occurs_check_error_abort/` in the workspace).
  ✅ retract/1, retractall/1 and clause/2 use it (2026-10-03): a mark per candidate clause, the
  answer's bindings live while the caller's sink runs, undone after it (in a `finally`: ≲ 0.1 µs).
  Variable keys: a caller owns those below 2^63 (`var_term` checks), the kernel takes its own from
  one process-wide counter. `clause/2` over 1000 facts: 0.55× swipl's time. Found on the way and
  fixed next: `nextClause!` allocated an `index_context` per call (upstream: the C stack); it now
  resets one scratch context in the local data and is gated allocation-free.
* **The canonical-encoding property** — the kernel's variant key of a term equals MORK's De Bruijn
  bytes for it. It arrives with variant canonicalisation (`unify`) and a PathMap extension.
