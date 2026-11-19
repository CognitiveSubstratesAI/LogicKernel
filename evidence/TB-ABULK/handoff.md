# TB-ABULK: test_tabling_abolish_bulk_upstream_swipl.jl states the shared-table refusals (owner TH1)

Run at b6240994 on three term types: 51 passed, 3 failed, 6 errored. Two symptoms, one cause: the first row that calls the
shared table `ss/1` (through `ps/1`, bk01) raises the kernel's named refusal (`NotPortedError`, get_answer_table, owner TH1) as a Julia
exception out of PL_next_solution; the testset stopped there (kl stayed empty), so the "thread-bound" testset saw `0 == 9`.

## What changed (test file only, no src)
- `_tt_ask`: the query loop is inside `try`; a `NotPortedError` returns the row line `t_bkNN refused(<owner>)` (owner = the error's
  `step`), other exceptions are rethrown. The open query is not closed (its kernel is discarded).
- `_tt_refused(line)`: the owner named in a refused line, or `nothing`.
- Testset 1: ONE KERNEL PER ROW (a fresh `_tt_load(main)` per row; the program files are materialized once) so a refused row leaves no
  state for the next. `@test s == "ok"` per load. Non-thread rows: answered -> `@test k == pn` as before; refused -> `@test_broken k == pn`
  with the owner on stderr (never skipped, never weakened). Thread-bound rows (bk01, bk02, bk03, bk08) stay out of this loop.
- Thread-bound testset: unchanged logic (equal to the pin passes, otherwise `@test_broken`); stderr now also names the owner. It now sees 9 lines.
- Header comment: the refusal and the one-kernel-per-row layout are stated.

## Expected run (not run: no Julia in this step)
- Load: st == "ok" on every load (the run reached row 1 before, so the `shared` declaration loads).
- bk01, bk02 (ps/1 -> ss/1, shared): `refused(TH1)` -> @test_broken in the thread-bound testset. bk03 (thread_create): the line is either
  `refused(TH1)` or a swipl-different Prolog `raised(...)`/`failed` line: @test_broken either way. bk08 (thread_create, statistics): same.
- bk04 (conditional, tnot), bk05 (monotonic), bk06 (registry: `'$idg_thread_summary'`), bk07 (incremental): UNVERIFIED, these never ran.
  If a row answers `t_bkNN c[..](a[111,107])` it passes; a named refusal is @test_broken with its owner; a Prolog-level
  difference (e.g. `raised(...)`) is a plain `@test k == pn` FAILURE that names a real divergence to read.
- The pins/swipl-live testsets are unchanged (13 + 2 passes per type).
- Risk: a row that raises a Julia exception other than `NotPortedError` still errors the testset (rethrown on purpose).
- test_type_discipline.jl and warm.sh check NOT run (fmt not run: the long comment lines follow the file's existing style).
