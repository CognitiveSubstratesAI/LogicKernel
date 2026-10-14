# LogicKernel.jl

A standalone logic-programming kernel for Julia: terms, unification, a clause database, argument
indexing, term tries, SLG tabling and a clause VM — for languages in which **every matching clause
fires** and answers are multisets.

> **LogicKernel is a port of [SWI-Prolog](https://www.swi-prolog.org)** — of
> [swipl-devel](https://github.com/SWI-Prolog/swipl-devel), BSD-2-Clause — to Julia: upstream's C
> and Prolog sources translated file by file, at upstream's paths and under upstream's names, and
> checked against a live `swipl`. Every ported file records its upstream file, the commit it was
> read at and upstream's copyright lines: see [`NOTICE`](NOTICE) and
> [`docs/port_inventory.md`](docs/port_inventory.md).

## Status

**0.1.0.** What is ported so far, upstream file by upstream file and function by function, is
listed in [`docs/port_inventory.md`](docs/port_inventory.md); how it is built is in
[`docs/architecture.md`](docs/architecture.md).
The version stays **0.x until the term interface has a second implementation** in real use — until
then the interface is only as general as one implementation makes it. First real work: `src/terms/`.

**Known limits.** Variable bindings live in a store beside the terms, and it shrinks only on
backtracking: **a long deterministic run grows memory without bound** — nothing reclaims bindings
yet. SWI-Prolog's own term layout (tagged words on global, local and trail stacks, conditional
trailing) is planned as step L1, after the module system (R2), followed by a port of its garbage
collector; until then LogicKernel suits queries and rule reasoning, not long-running loops.

## The contract

* **Indexing never changes answers.** An index may only remove work. It yields a superset of the
  matching clauses, and enumerating it yields exactly the true multiset of answers, in source order.
  A value that cannot be keyed consistently with its equality is a wildcard, never a shared bucket.
* **Answers in order, duplicates kept.** The kernel has no MeTTa (or Prolog) answer semantics of its
  own; deduplication and tabling modes are options the caller selects.
* **No module-level mutable state.** Anything belonging to one evaluation lives in a value the caller
  owns. Enforced by [`tools/lint_globals.jl`](tools/lint_globals.jl), which the suite runs.
* **Standalone.** No dependency on any CognitiveSubstratesAI package; they depend on this one. The
  suite checks the `[deps]` table against an allowlist of one — PrecompileTools, for the precompile
  workload — and that no sibling package is loaded.
* **No choice points, no trail.** Nondeterminism is the sink/continuation model.

## The term interface

A compound term is a **sequence of children with the head as child 1** — not Prolog's
`functor`/`arity`, because a head may itself be a variable or a compound. The interface (`kind`,
`term_type`, `nchildren`/`child`, `sym_key`, `sym_hash`, `var_key`, `gnd_key`, `gnd_equal`,
`atomic_compare`, `mk_var`/`mk_expr`, `is_ground`, and the Prolog layer: `mk_sym`, `mk_gnd`, the
reserved symbols `mk_reserved_symbol`/`is_reserved_symbol`/`mk_nil`/`is_nil`, numbers by `number_kind`)
is specified in [`src/term_interface.jl`](src/term_interface.jl). One conformance suite runs against
every implementation: the default term type here, and a deliberately different second one in the
tests ([`test/core_lang/alt_term.jl`](test/core_lang/alt_term.jl)) — a test vehicle, not real use.

**Variable identity = handle; separate puts create new variables** (user, 2026-10-14). A Julia
value put into the engine (`putSlotValue!`) is COPIED, as SWI-Prolog copies a record onto its
stacks: every unbound variable in it becomes a fresh variable of the engine. Two separate puts of
the same Julia variable therefore make two variables; puts that should share their variables — a
goal's arguments, put slot by slot — pass one `PutVarMap()`, as one SWI record would. An answer is
read through the term references (`slotValue` of the argument slots, then `resolve_term`), never
through the caller's variables, which the engine does not bind. Sharing with a variable already in
the engine goes through its handle, as `PL_put_term(t2, t1)` does in SWI's C interface.

## Layout — a mirror of swipl-devel

A port lives at upstream's own path and keeps upstream's names: swipl-devel `src/pl-prims.c` →
`src/pl-prims.jl`, `tests/core_lang/test_bips.pl` → `test/core_lang/test_bips.jl`. Code with no
upstream counterpart says `# ORIGINAL: <why>`. The rule, the few Julia-forced deviations and the
subsystem grouping are in [`docs/architecture.md`](docs/architecture.md); every port is listed in
[`docs/port_inventory.md`](docs/port_inventory.md).

| path | what |
|---|---|
| `src/` | ports at swipl-devel's paths, plus ORIGINAL code (the term interface, `Term{G}`) |
| `boot/` | ports of swipl-devel `boot/*.pl` |
| `bench/programs/` | the standalone consumer: swipl-devel's benchmark programs (its `bench` submodule) written on the public API, beside the verbatim `.pl` |
| `test/<area>/` | tests in swipl-devel's `tests/` areas — ported upstream tests keep their names |
| `test/` root | package infrastructure: lint, port check, type discipline, static analysis |
| `tools/` | `run_tests.sh`, `warm.sh` (the warm lane), `mutate.sh` (mutants in a separate worktree), `build_oracle.sh` (swipl at the pinned commit), `port_check.jl`, `upstream_drift.jl`, `lint_globals.jl`, `repl.jl`, `jet_report.jl`, `bench.jl` |

## Testing

```bash
tools/run_tests.sh                         # full suite, real exit code, memory-capped — EVIDENCE
tools/warm.sh start                        # the warm lane: LogicKernel loaded once, under Revise
tools/warm.sh file test/core_lang/test_unify.jl   # one file, every term implementation, real exit code
tools/warm.sh bench                        # the bench in the warm daemon (no JIT in the timings)
tools/warm.sh workload off                 # skip the precompile workload in THIS checkout
tools/warm.sh preflight                    # WARM, before any full run: format, port_check, the
                                           # static-analysis gate, changed test files — and it
                                           # pre-warms the evidence workers meanwhile
tools/warm.sh pool                         # pre-warm the evidence workers for the current tree
LOGICKERNEL_SHARDS=1 tools/run_tests.sh    # the full suite in ONE process (default: sharded)
julia --project -e 'using Pkg; Pkg.test()' # what CI runs
julia --project tools/lint_globals.jl      # the module-state lint alone
julia --project -i tools/repl.jl           # dev REPL with Revise
julia --project tools/jet_report.jl        # JET sweep (minutes on first load)
```

The warm lane is for ITERATION only; commit evidence is a fresh `tools/run_tests.sh` run, never the
daemon (`tools/warm.sh evidence` starts one). A full run is SHARDED across fresh worker processes;
`tools/test_warm.sh` and `tools/test_evidence.sh` test the lane and the sharded run.

Dev tools (Revise, JET, JuliaFormatter, BenchmarkTools) are not dependencies; they come from the
global environment, which Julia stacks under `--project`. Formatting is Blue
([`.JuliaFormatter.toml`](.JuliaFormatter.toml)), enforced in CI.

## Licence

BSD-2-Clause — see [`LICENSE`](LICENSE). LogicKernel is a port of
[swipl-devel](https://github.com/SWI-Prolog/swipl-devel), which is BSD-2-Clause too: SWI-Prolog's
copyright notice and licence text are reproduced in [`NOTICE`](NOTICE), and each ported file keeps
its upstream file's copyright lines.
