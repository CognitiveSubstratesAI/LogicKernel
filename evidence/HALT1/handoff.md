# HALT1 handoff (halt/1, abort/0, the unwind raise, the process-exit path) — branch wip/halt1, worktree ~/code/lk-halt1

Edit-only: nothing here was compiled or run. Every kernel expectation is UNVERIFIED on the kernel: gate decides.

## 1. Where upstream defines it (pin tree ~/dev-zone/swipl-devel-cbf4e189, 10.1.19)
- `halt/1`: src/pl-prims.c:5554-5574 (`PRED_IMPL("halt", 1, halt, 0)`), table entry pl-prims.c:6676 (LAST entry of the prims table, after `throw/1`, `$urgent_exception/3`).
  atom `abort` -> `PL_abort_process()` (no unwinding, kills the process); other atom -> `PL_get_signum_ex` (status = 128+signal, `|= PL_CLEANUP_NO_CANCEL`); else `PL_get_integer_ex`; then `PL_halt(status|PL_HALT_WITH_EXCEPTION)`.
- `halt/0`: boot/init.pl:4653-4662 (Prolog: `'$exit_code'(Code)`, warning, `halt(Code)`); `at_halt/1` :4687-4698, `'$run_at_halt'/0` :4700-4706, `'$call_at_halt'/2` :4708-4719, `cancel_halt/1` :4727-4728. All boot text: LOADER, not written here.
- `PL_halt`: src/pl-fli.c:5084-5111 (+ `haltProlog` :5048-5066, comment :5068-5082, `PL_abort_process` :5117-5121); flags SWI-Prolog.h:1129-1132 (`PL_CLEANUP_STATUS_MASK 0xffff`, `PL_CLEANUP_NO_RECLAIM_MEMORY 0x10000`, `PL_CLEANUP_NO_CANCEL 0x20000`, `PL_HALT_WITH_EXCEPTION 0x40000`), results :1134-1137.
- `raise_halt_exception`: pl-pro.c:617-648 (raises `unwind(halt(Code))`, Code = status & 0xffff, only if `force || handles_unwind(NULL, PL_Q_EXCEPT_HALT)`).
- `halt_from_exception`: pl-pro.c:113-132 (`PL_halt(status&0xff)`), used by `query_loop` pl-pro.c:150-200 (query opened with `PL_Q_NORMAL|PL_Q_EXCEPT_HALT`, :170; main thread only :185-189). NOT written: the kernel has no toplevel (`query_loop`, `prologToplevel`) — left to the toplevel step.
- `abort/0`: pl-pro.c:613-616 (`PRED_IMPL("abort", 0, abort, 0)`), `abortProlog` :583-606 (the `unwind(abort)` ball: `PL_FUNCTOR FUNCTOR_unwind1, PL_ATOM ATOM_abort`, :592-594; table entry in pl-pro.c's BeginPredDefs).
- `handles_unwind`: pl-wam.c:2215-2232 (walk the query chain, `ison(qf, flags)`); users :2240 (thread exit), :2243 (`print_unhandled_exception`: halt), pl-pro.c:630.
- `PL_cleanup`: pl-init.c:1913-2060 (`MAX_HALT_CANCELLED` 10; `GD->halt.cleaning` states pl-incl.h:1054-1060; `exit_status` flag set :1956-1957; `$run_at_halt` through `query_loop` :1962; cancelled counter :1964-1976).
- `PL_get_signum_ex`: pl-setup.c:406-428 (integer, else atom via `signal_index` :385-398 which strips an uppercase `SIG` prefix and lowercases; table :262-360; valid 1..31, else `domain_error(signal, X)`; not integer/atom text: `type_error(signal, X)`).
- classification: `classify_exception` already in the kernel (src/pl-fli.jl:350-385, EXCEPT_ABORT/EXCEPT_HALT).
- flags involved: `exit_status` (set in PL_cleanup), `halt_grace_time` (kernel has it, pl-prologflag.jl:1966; used only by the threaded `PL_halt` branch), `on_error`/`on_warning` (in `halt/0`, boot text).

## 2. swipl 10.1.19 answers (LC_ALL=C; each row its own process `swipl -q -f none --no-tty -g G -t true`; two runs byte-identical; scratchpad rows.txt/run.sh, regenerate from this table)
| row | goal | answer |
|---|---|---|
| h01 | `catch(halt(3),E,(print(caught(E)),nl))` | handler RUNS, prints `caught(unwind(halt(3)))`, then the process exits 3 (the ball is re-raised: '$recover_and_rethrow') |
| h02 | `catch(abort,E,...)` | handler runs: `caught(unwind(abort))`; exit status 1 (the -g goal's unhandled abort) |
| h03 | `setup_call_cleanup(true,halt(3),(write(cleanup_ran),nl))` | cleanup RUNS (`cleanup_ran`), exit 3 |
| h04 | `at_halt((write(a),nl)), at_halt((write(b),nl)), halt(2)` | prints `b` then `a` (asserta: last registered runs first), exit 2 |
| h05 | `catch(halt(foo),E,...)` | `error(domain_error(signal,foo),context(system:halt/1,_))` |
| h06 | `halt(_)` | `error(instantiation_error,context(system:halt/1,_))` |
| h07 | `halt(1.5)` | `error(type_error(integer,1.5),context(system:halt/1,_))` |
| h08 | `halt(99999999999)` | `error(representation_error(int),context(system:halt/1,_))` |
| h09 | `halt(-1)` | ball `unwind(halt(65535))` (code = status & 0xffff), exit 255 |
| h10 | `halt(256)` | ball `unwind(halt(256))`, exit 0 (the process takes &0xff) |
| h23 | `halt(65536)` | ball `unwind(halt(0))`, exit 0 |
| h24 | `halt("3")` | `error(type_error(integer,"3"),context(system:halt/1,_))` |
| h11 | `halt` | exit 0 |
| h12 | `at_halt(cancel_halt(because)), halt(4)` | halting cancelled: `halt(4)` SUCCEEDS (PL_halt returns true), the goal continues, exit 0 |
| h13 | `at_halt(fail), halt(5)` | `Warning: [Thread main] Goal (at_halt) failed: user:fail`, exit 5 |
| h14 | `at_halt((current_prolog_flag(exit_status,S),...)), halt(6)` | `status(6)`, exit 6 |
| h15 | `catch(call_cleanup(halt(7),(write(c1),nl)),E,(print(E),nl))` | `c1` then `unwind(halt(7))`, exit 7 (cleanup runs, then the handler sees the ball) |
| h16 | `catch(halt(8),unwind(halt(S)),(write(got(S)),nl)), write(after)` | `got(8)`, `after` NOT printed, exit 8 |
| h17 | handler rethrows `E` | `caught(unwind(halt(9)))`, exit 9 |
| h18/h26/h27 | halt inside findall / forall / `\+ \+` | exit 10 / 15 / 16 |
| h22 | `at_halt((..., halt(12))), halt(13)` | `h1`, exit 13 (halt in a hook does not recurse) |
| h25 | `at_halt(throw(oops)), halt(14)` | `ERROR: [Thread main] Unknown message: oops`, exit 14 |
| h28 | `catch(abort,unwind(abort),(write(abort_caught),nl)), write(after_abort)` | `abort_caught`, `after_abort` NOT printed, exit 1 |
| h29 | `setup_call_cleanup(true,abort,(write(cleanup_abort),nl))` | `cleanup_abort`, exit 1 |
| g01/g02/g03 | `halt(term)` / `halt('SIGTERM')` / `halt(int)` | ball `unwind(halt(143))` / `(143)` / `(130)`; exit 143 / 143 / 130 (128+signal) |
| g04 | `halt(abort)` | no ball, exit 134 (PL_abort_process: haltProlog then abort()) |
| g05 | `halt(foo(1))` | `type_error(integer,foo(1))` |
| g06 | `halt([])` | `type_error(signal,[])` |
| h20/h21 | `halt(sigterm)`, `halt(not_a_signal)` | `domain_error(signal,...)` (lowercase `sig` prefix is not stripped) |
| g07 | `halt(0)` | ball `unwind(halt(0))` |
| g08/g09 | `catch(halt(3),_,true)` / `catch(halt(3),_,fail)` | handler runs but the ball is re-raised: exit 3, nothing after prints |
| g10 | `catch(call_cleanup(abort,true),E,...)` | `unwind(abort)`, exit 1 |
No `cancel_halt/1` row beyond h12: the pin has it (init.pl:4727). halt in a nested query: no row can be told apart on swipl through -g (the -g goal is a query under the toplevel's EXCEPT_HALT query).

## 3. Plan (ordered groups; each its own commit)
1. SRC-A (Tier 1 file pl-wam.jl, pl-global.jl; Tier 3 elsewhere): `PL_Q_EXCEPT_HALT` (SWI-Prolog.jl); halt state in GD (pl-global.jl: `halt_status`, `halt_thread`, `halt_cleaning`, `halt_cancelled`, the seam `halt_exit`); `handles_unwind` (pl-wam.jl); `abortProlog`, `raise_halt_exception`, `abort/0` (pl-pro.jl).
2. SRC-B: `PL_halt`, `haltProlog`, `PL_abort_process` (pl-fli.jl), `PL_cleanup` reduced (pl-fli.jl, marked pl-init.c: no pl-init.jl exists; the dispatcher may want a new file), `PL_get_signum_ex` (pl-setup.jl), `halt/1` (pl-prims.jl, last entry of the table).
3. TEST: test/core_lang/test_halt_swipl.jl (rows above, generator, driver) — NOT STARTED.
4. MUTANTS: tools/mutants/HALT1.py — NOT STARTED.
5. MANIFEST + DOCS: appended blocks in test/static_analysis_manifest.jl and docs/architecture.md — NOT STARTED.
