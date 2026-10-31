# LB3 gate — state (gate agent 2, Sonnet, 2026-11-01)

Worktree ~/code/lk-lb3, branch `wip/lb3-r` (wip/lb3 re-stacked on origin/main 1286e62). Daemon: the lane's third daemon
logickernel-warm-13b94ed9 (idle after this gate; not restarted by gate 2).

## Decisions
- **Conjunction directives (D-0291, option c).** `compileFile` calls `callProlog`, which as upstream (pl-pro.c:476-540) calls
  `resolveProcedure(fd, module)` without `call/1`; `','/2` is a predicate upstream only because boot/init.pl defines it. So
  `:- true, true.` / `:- atom(a), atom(b).` print "directive failed" until LB4 loads init.pl. The boot row of
  test/files/test_qlf_swipl.jl (`t_q02`) PINS the kernel answer `["additional"]`, swipl's `["autoload_off", "additional"]` and the
  comment `# KNOWN DIFFERENCE until LB4 ...` stand next to it; the LB4 checklist in evidence/LB3/handoff.md carries the flip.
- **F5 equivalent (tools/mutants/LB3.py, `LB3-F5`): AGREED.** src/pl-qlf.jl:247 calls `read_clause(gd, ld, Scurin(ld), t, 0)` with
  options 0, so src/pl-read.jl `read_clause` keeps `syntax_errors = :dec10` (:4099 region); `reportReadError` (:4030) returns
  true for `:dec10` after printing, and the retry loop reads again. A syntax error therefore never makes `read_clause` return
  false; the `continue` branch of pl-qlf.jl is reached by a stream error only, which no row can produce.
- **Manifest.** gate 1's LB3 block was complete but for one method: `_qlf_source_file_text` (was `ld::PL_local_data`, an unparametrised
  UnionAll signature) now `ld::PL_local_data{T}) where {T}` with a manifest row. `check` then passes (manifest_uncovered empty;
  the `_qlf_refused` `Union{}` return needed no exemption). JET itself is CI-only (D-0220).

## Results (this worktree, this SHA's tree)
- `warm.sh check --summary`: PASS (format Blue-clean, port_check 235 files, manifest, term scopes, meta files, inert guard,
  Pkg.test-way run of test_qlf_swipl.jl clean: peak 2246 MiB, cap 3G).
- test/files/test_qlf_swipl.jl on all three term types: 276/276 (92 each).
- test/test_type_discipline.jl: 33/33.
- The Pkg.test-way run prints `LB3 LIVE CHECK NOT RUN: swipl is not on PATH here. It runs in tools/run_tests.sh and CI.` (stderr,
  .warm/pkgtest_way/test_qlf_swipl.err): the swipl rows are NOT covered by the Pkg.test-way run, only by run_tests.sh / CI.
- Alloc pins x3, branch-gate, term grep (D-0164), pushes: see the channel copy (~/code/lk-channel/evidence/LB3/gate.md) and the
  hand-back; they were run after this commit.
