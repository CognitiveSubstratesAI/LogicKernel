# LB4 b1 — boot-time bench note (H3; NOT RUN: edit-only writer, 2026-11-01)

What the template database (src/gd_template.jl) is for: the boot of b2 is paid once per process and term type, and a
database made after it is a COPY. The bench decides whether that holds, and gives the number D-0286 item 3 waits on (the
`bare` constructor, decided after the first boot measurement).

## What to time (per term type: the reference type, and the two others of the three-type run)
1. `PL_global_data{T}()` — the UNBOOTED constructor (the cost every test pays today, 139 call sites).
2. `gd_template(T, build)` FIRST request — build once (in b1 this equals 1; in b2 `build` is the booted constructor, so
   this is the boot time itself).
3. `copy_global_data(TMPL)` — the copy of the template (b1: of the unbooted one; b2: of the booted one, millions of objects).
4. `PL_global_data_from_template(T)` after the first request — the steady-state price of a new database.
5. Allocations of 3 and 4 (`@allocated`, bytes and count): on this VM ALLOCATIONS decide, time is a sanity check.

The decision rule: item 4 must be well under item 1 for the copy to pay; if the copy of the BOOTED template is not
under the unbooted constructor, H3's cost line is wrong and the audit decides (a lazy copy, or copy-on-write tables).

## Method (memory "bench method")
- 30 interleaved runs of 1, 3, 4 (one run of each in turn, so drift hits all alike); median and IQR; raw numbers in
  tools/bench_results/. A quiet machine (the start gate of the bench tool), no other Julia process of mine running.
- A fresh `reset_gd_templates!()` before item 2 each time it is timed; item 2 is a cold timing by construction.
- GC: `GC.gc()` before each timed call, the GC time reported separately (a deep copy of a large graph is GC-heavy).
- Only the dispatcher's go starts the bench (the alloc bench is not run by a writer or a gate agent without it).

## Not run
Nothing here was run (no Julia in a writer). The first measurement belongs to the gate agent of b1 for items 1-5 on the
unbooted template, and to b2 for the booted one.
