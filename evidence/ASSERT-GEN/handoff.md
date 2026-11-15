# ASSERT-GEN handoff (edit-only; wip/agen on b29b887d; nothing compiled or run)
- src: pl-comp.jl clause_ndet and pl-proc.jl pl_retract1_va: the `@assert dref.generation == generationFrame(frame)` is removed; the store
  `ld.frames[fr].generation = dref.generation` (pl-comp.c:7413, pl-proc.c:3180 at 18168e62) stays, the comment says so.
- test/core_lang/test_generation_swipl.{jl,pl,out}: 38 cases (the probes p1a*, p1b*, p1c* of the channel's evidence/PROBES), pins re-run with swipl
  (identical to p1_swipl.txt). The autoload group p1a12-p1a19 is plain @test + a no-exception row: the kernel's boot has the autoloader
  (p1a4, p1a17 matched in the probe), so the rows are expected to pass; if one differs, flip THAT id to @test_broken with the autoloader owner's name.
- tools/mutants/AGEN.py (4: C1 killed by the no-exception rows, C2 killed by the autoload rows, R1/R2 declared equivalent), NF2.py (C5 now killed,
  R6/G1/G2 equivalent with reasons; their `old` counts checked once each: 23 mutants).
- NOT done: parse-only check (cold-start hook blocked: 4 cold starts in the last hour), fmt, check, any test run.
