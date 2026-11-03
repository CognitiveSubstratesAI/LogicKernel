# LB5 writer handoff (D-0386 items 1c, 2; edit-only; worktree ~/code/lk-lb5, branch wip/lb5 off 9cc76fa)

Kernel registry form: `PL_extension("name", N, fn_va, flags)` tuples; pl-file.jl's table is `PL_predicates_from_file`
(src/os/pl-file.jl ~2620). Upstream read at the pin cbf4e1896275 via `git show` (pl-file.c, pl-arith.c).

## Plan (ordered; "G" = committed group)
G1  set_stream/2 alias(Std): setStandardStream instead of the refusal (pl-file.c:2215-2227). Key fact: plunit's default
    output(on_failure) goes through library(streams) with_output_to/3 -> set_stream(S, alias(user_output)).
G2  current_input/1, current_output/1 (current_io, pl-file.c:5693-5735), line_count/2, line_position/2 (getStreamWithPosition
    pl-file.c:5524-5540, :5773-5800), tab/1,2 (pl-file.c:3809-3845; needs PL_eval_expression_to_int64_ex, pl-arith.c:5346: G2a).
G3  at_end_of_stream/0,1 (pl-file.c:5827-5860), get_code/1,2 (3626-3650), put_code/1,2 (3427-3455).
G4  write_size/4 (src/pl-write.jl; pl-write.c).
G5  rows (test/..._lb5_swipl.jl + generator), mutants tools/mutants/LB5.py, manifest, docs/architecture.md block.
Optional / may be handed on: succ/2 (pl-arith.c:274-355), peek_string/3 (needs buffer text access), seek/4 + set_stream_position/2
    (need Sseek64/Stell64: the stream layer has none), with_tty_raw/1.

## State
(see "Committed" below, updated after each commit)

## Committed
