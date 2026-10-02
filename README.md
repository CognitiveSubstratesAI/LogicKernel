# LogicKernel.jl

A standalone logic-programming kernel for Julia: terms, unification, a clause database, argument
indexing, term tries, SLG tabling and a clause VM — for languages in which **every matching clause
fires** and answers are multisets.

> **Lineage.** Algorithms ported from SWI-Prolog (`swipl-devel`, Simplified BSD) and checked against
> a live `swipl`. Algorithms are ported as code; machinery (clause compilation, frames, generations)
> is re-expressed for multiset semantics, never transliterated.
> Every ported file records its upstream file and commit: see [`NOTICE`](NOTICE) and
> [`docs/port_inventory.md`](docs/port_inventory.md).

## Status

**0.1.0 — skeleton.** The layout, the suite, CI and the lint are in place; nothing is ported yet.
The version stays **0.x until the term interface has a second implementation** in real use — until
then the interface is only as general as one implementation makes it. First real work: `src/terms/`.

## The contract

* **Indexing never changes answers.** An index may only remove work. It yields a superset of the
  matching clauses, and enumerating it yields exactly the true multiset of answers, in source order.
  A value that cannot be keyed consistently with its equality is a wildcard, never a shared bucket.
* **Answers in order, duplicates kept.** The kernel has no MeTTa (or Prolog) answer semantics of its
  own; deduplication and tabling modes are options the caller selects.
* **No module-level mutable state.** Anything belonging to one evaluation lives in a value the caller
  owns. Enforced by [`tools/lint_globals.jl`](tools/lint_globals.jl), which the suite runs.
* **Standalone.** No dependency on any CognitiveSubstratesAI package; they depend on this one. The
  suite checks the `[deps]` table and that no sibling package is loaded.
* **No choice points, no trail.** Nondeterminism is the sink/continuation model.

## The term interface

A compound term is a **sequence of children with the head as child 1** — not Prolog's
`functor`/`arity`, because a head may itself be a variable or a compound. The interface (`kind`,
`nchildren`/`child`, `sym_key`, `var_key`, `gnd_key`, `gnd_equal`, `mk_var`/`mk_expr`, `is_ground`)
is specified in [`src/terms/README.md`](src/terms/README.md). One conformance suite runs against
every implementation, starting with the default term type here.

## Layout

| path | what |
|---|---|
| `src/` | one directory per subsystem; order and dependencies in [`docs/architecture.md`](docs/architecture.md) |
| `test/<subsystem>/` | that subsystem's tests — every `test_*.jl` runs, each in its own module |
| `test/conformance/` | the term-interface conformance suite, run against every implementation |
| `test/oracle/` | live differentials against `swipl` |
| `test/standalone/` | a client program using only the default term type |
| `bench/` | benchmark programs |
| `ext/` | package extensions (optional integrations) |
| `tools/` | `run_tests.sh`, `lint_globals.jl`, `repl.jl`, `jet_report.jl` |

## Testing

```bash
tools/run_tests.sh                         # full suite, real exit code, memory-capped
julia --project -e 'using Pkg; Pkg.test()' # what CI runs
julia --project tools/lint_globals.jl      # the module-state lint alone
julia --project -i tools/repl.jl           # dev REPL with Revise
julia --project tools/jet_report.jl        # JET sweep (minutes on first load)
```

Dev tools (Revise, JET, JuliaFormatter, BenchmarkTools) are not dependencies; they come from the
global environment, which Julia stacks under `--project`. Formatting is Blue
([`.JuliaFormatter.toml`](.JuliaFormatter.toml)), enforced in CI.

## Licence

BSD-2-Clause — see [`LICENSE`](LICENSE). Code ported from SWI-Prolog keeps SWI-Prolog's own BSD-2
notice and copyright lines — see [`NOTICE`](NOTICE).
