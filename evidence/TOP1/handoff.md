# TOP1 handoff (writer, Sonnet, edit-only: nothing compiled or run)

Worktree ~/code/lk-top1, branch wip/top1, base 30fb3a16 (= gate/autoload2c: main 6941c5bd + the AUTOLOAD1 A2/A3 stack).
Pin cbf4e1896275. No daemon, no Julia, lanes.conf untouched.

## Sizing (read at the pin)
In this step (pl-pro.c:60-94 resetProlog, :147-218 query_loop and what they call):
- G1 src/pl-trace.jl: `resetTracer` (pl-trace.c:1882, over the fields the local data has), `enable_debug_on_interrupt` (pl-trace.c:2092, the flag-mask half).
- G2 src/os/pl-file.jl: `validUserStreams` (pl-file.c:1488), `PrologPrompt` (:3795), `PL_write_prompt` (:1868, clears `prompt.next`);
  src/pl-write.jl `writeAtomToStream` (pl-write.c:1318); src/pl-fli.jl `PL_prompt_next` (pl-fli.c:5345).
- G3 src/pl-pro.jl: `resetProlog` (clears autoload.nesting/.loop: the A2 DIVERGES), `halt_from_exception`, `restore_after_exception`, `query_loop`.
- G4 tests: test/core_lang/test_top1_*.jl (+ generator under tools/), tools/mutants/TOP1.py, manifest, architecture block, DIVERGES flips.
Readers of `prompt_next`: pl-pro.c:67 (G3), pl-fli.c:5349 (G2), PL_write_prompt clears it (G2). LEFT with an owner (TOP1b):
Sread_user + wrapIO + set_prolog_IO/3 (pl-file.c:5987, :6047, :6125), Sread_terminal (pl-os.c:2171-2224, :2462), `prologToplevel`/`pl_break`/
`currentBreakLevel`/`break_level` flag (needs a `break_level` field), PL_prompt_is_continuation, PL_prompt_string.

## Status
(updated per commit below)
