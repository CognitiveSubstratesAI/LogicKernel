# BENCH-ALLOC: `bench --alloc-only` (audit D-0268 item 1d, D-0188 item 2, D-0172)

State: PREPARED on branch `wip/bench-alloc-only2` (off origin/main 07a8e01). Not pushed. No bench, no
daemon, no Julia process was started for this piece.

## What was ported
Origin: uncommitted work in `~/code/lk-bench-tool` (branch wip/bench-alloc-only, HEAD f9c214d). The two
modified files applied with `git apply --3way` WITHOUT a conflict (bench.jl and architecture.md had
drifted, the hunks still fit). Contents:
- `tools/bench.jl --alloc-only [--runs=N] [CASE...]`: per case the LogicKernel half of `sampled_times`,
  printing one `ALLOC<TAB>case<TAB>median<TAB>min<TAB>max<TAB>calls<TAB>runs` row; no swipl, no start gate
  (START_GATE's `timing` is false for the flag), no timing column, no raw file. Default 10 samples.
- `tools/bench_alloc_sets.sh <treeA> <treeB> <N> [--runs=K] [CASE...]`: alternates N fresh processes per
  side, prints each case's SET of counts (`{237x4, 239x1}`) and a verdict (identical / same set /
  mode same / MODE SHIFT). `BENCH_ALLOC_BENCH` runs a given bench.jl on a base tree without the flag.
- `tools/test_bench_alloc_only.sh [stub|real|all]`: stub = the script against fake `julia` processes (no
  Julia); real = the real flag in a fresh julia (compiles; do NOT run on a busy machine).
- `docs/architecture.md`: one table row.

## Changes made in this piece (on top of the port)
1. `bench_alloc_sets.sh`: the systemd cap is used only if `systemd-run --user --scope true` works (the
   probe `run_tests.sh`/`build_oracle.sh` use); without it a CI runner with no user manager would fail.
2. `.github/workflows/CI.yml`: a `light`-shard step `tools/test_bench_alloc_only.sh stub`, a separate
   hunk right after `tools/test_summary.sh`, same shape as its neighbours. No other registry lists
   tooling tests (6991eec and 9952080 touched only CI.yml plus the files themselves).
3. Test gaps found by the mutation run and closed (the stub part was 17 cases, now 23):
   - the "no rows" case exited 3 from an earlier `fail` stub, not from the empty process (vacuous): the
     stub is restored first;
   - a directory without Project.toml (the old missing-tree case was caught by a later check);
   - an aggregation (awk) that fails is a non-zero exit;
   - a `mode same` case (same mode, different sets) and the 4-case summary line;
   - a failing process on side A (the old case was B only; B's stub/1 had been left as comments);
   - N=3 runs and warns (`WARNING N=3 < 5`).

## What ran (all stub-only, no Julia)
- `bash -n` on both scripts; scripts are mode 755.
- `tools/test_bench_alloc_only.sh stub`: 23 passed, 0 failed; also with a `systemd-run` that fails
  (the probe path): passes.
- Hand-run mutants of `bench_alloc_sets.sh`, each restored with `cp` (file identical to the committed
  one afterwards, `cmp`): 16 of 16 killed (`evidence/BENCH-ALLOC/stub_mutants.txt`): MODE SHIFT line
  forced to "mode same", empty-rows guard removed, flag guard removed, N=0 allowed, failing B / failing A
  process ignored, "same set" and "identical" verdicts disabled, tree checks removed (nodir, no
  Project.toml), an extra process per side, aggregation exit forced to 0, modes = all values, set sort
  reversed, N<5 warning removed / reworded. Six of these first SURVIVED and led to the test additions in
  item 3 (empty-rows, nodir, aggregation exit, modes, failA, warning).
- Crash-term grep (`segment|SIGSEGV|crash|abort|invalid term_t|dies of`) over the diff and the new
  files: no hit. The commit message was checked the same way.

## UNRUN (for the gate agent)
- `tools/test_bench_alloc_only.sh real` (7 cases in the earlier notes): it starts a Julia process
  and a sleeping helper julia; needs a free daemon slot/quiet machine. Also compiles bench.jl cold.
- `tools/warm.sh fmt`, `tools/warm.sh check`, the `check` Pkg.test-way run, the tree-wide test files on
  three term types (no .jl test file changed, bench.jl is a tool), `tools/warm.sh branch-gate`.
- JET/static: bench.jl is not under src/; the tooling shard in CI covers it (`tools/test_*`).
- The bench itself (D-0172): `tools/bench_alloc_sets.sh <base-tree> <this-tree> 5` on a quiet machine,
  >= 5 fresh processes per side, compare the SETS (a delta counts only when the MODES shift). The base
  tree's own bench.jl has no flag: use `BENCH_ALLOC_BENCH=<this tree>/tools/bench.jl` if the base is
  older than this commit (the file must run against both trees' APIs).

## Gate order for the gate agent
1. `git pull`, rebase wip/bench-alloc-only2 onto current origin/main if it moved (new branch name if
   rebased; never force).
2. `tools/warm.sh fmt`, `check` (daemon needed).
3. `tools/test_bench_alloc_only.sh stub` (seconds), then `real` once with a free daemon.
4. `tools/warm.sh branch-gate`; crash-term grep over diff and message.
5. Push `gate/bench-alloc-only` and `mutants/BENCH-ALLOC` at the SAME SHA. TARGETS of a mutant of
   bench_alloc_sets.sh: `tools/test_bench_alloc_only.sh stub` (the stub part); the mutants of the
   `--alloc-only` hunk in bench.jl need the `real` part (not CI-able without Julia in the light shard):
   hand-run those on the gate lane or record them as untested by CI.
6. The dispatcher lands. Delete `~/code/lk-bench-tool`'s branch wip/bench-alloc-only afterwards (superseded).
