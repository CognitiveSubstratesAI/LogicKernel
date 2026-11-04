# CONT1 handoff (continuations at run time; audit D-0402 item 2d). Branch wip/cont1 off wip/lb4b2c 4e90042a.

Edit-only writer; nothing is run (no Julia). Spec: lk-channel evidence/R2/cont1_sizing.md. Upstream at the pin cbf4e1896275.

## Plan (ordered groups; upstream file:line -> Julia site; estimate)
| # | group | upstream | Julia | commits |
|---|---|---|---|---|
| C1 | five `procedures_*` fields + LOOKUPPROC; `ERR_PERMISSION_VMI` | pl-global.h:334-337,385; pl-ext.c; pl-error.c:384-391 | src/pl-global.jl, pl-setup.jl, pl-ext.jl, pl-error.jl | 1 |
| C2 | I_CALL1 `FR_INRESET` branch; I_RESET / I_EXITRESET (non-tabled) | pl-vmi.c:5529-5535, 5754-5833 | src/pl-wam.jl | 1 |
| C3 | liveness walker `mark_active_environment` / `walk_and_mark` | pl-gc.c:1709-1726, 1866-1936, 1957-2287 | src/pl-gc.jl | 2-4 |
| C4 | `findReset`, `put_environment`, `is_last_call`, `env3_predicate`, `put_continuation`, `shift`; I_SHIFT / I_SHIFTCP | pl-cont.c:74-445; pl-vmi.c:5874-5915 | new src/pl-cont.jl, pl-wam.jl, LogicKernel.jl | 2 |
| C5 | `push_continuation`; I_CALLCONT | pl-cont.c:456-548; pl-vmi.c:5839-5862 | src/pl-cont.jl, pl-wam.jl | 1 |
| C6 | I_YIELD, the non-engine branch | pl-vmi.c:2410-2418 | src/pl-wam.jl | 1 |
| C7 | flip b2's six `c_*` pin rows; remove the DIVERGES owner CONT1 block | | test files | 1 |
| C8 | mutants CONT1.py, manifest, docs (own LAST commits) | | tools/mutants, test manifest, docs/architecture.md | 2-3 |

## State
(updated after every commit below)
