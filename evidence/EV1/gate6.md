# EV1 gate agent 6 — state

Lane ~/code/lk-ev1, branch gate/ev1d (30 cherry-picked commits on 9cc76fa + gate5's uncommitted tree).

## C3 line verification (done, against the pin src/pl-event.c and src/pl-event.jl)
pl-event.c:420 `if ( ev->function )` ... :454 end of the C-function branch (assigns rc without &&); :455-459 term closure `rc = rc && (...)`;
:460-463 named listener `rc = rc && PL_call_predicate`; :465-466 `if ( !rc && PL_exception(0) ) break;`.
pl-event.jl:450-451 function_ != 0 -> rc = false (dead), :452-461 closure `rc = rc && (...)`, :462-469 named `rc = rc && ...`, :471 the break.
:164 `ev.function_ == 0`, :173 constructor passes function_ 0. The cited lines say what the declaration claims. C3: declared equivalent, pending audit.

## Steps
1. test_event_swipl.jl reference after the comma fix: 100/100 (parses). 
2. `warm.sh inventory` wrote docs/port_inventory.md + architecture.md (port_check clean, 259 files); architecture.md diff = the two generated mermaid
   hunks only (pl_pro --> pl_string moved), no UPSTREAM header names dropped from the pl-file/pl-event rows. NOT committed yet (one commit at the end).
   fmt snippet (.warm/fmt_all2.jl): 0 files rewritten. EV1d.py anchor checker: 51 mutants, 0 bad. `warm.sh check` started (log evidence/EV1/g5/check6.log).
3. VM froze ~09:17Z; daemon restarted (LOGICKERNEL_WARM_SECOND=1 start, ready); ONE daemon rule; check re-run.
4. `warm.sh check` PASS (485s, includes pkgtest_way test_bootpred3_swipl.jl peak 1457 MiB). D-0384: EV1d.py C3 text now cites both upstream lines and the kernel
   `rc = rc &&` lines (pl-event.jl:453-454, :464-465); TH1 named only as the reason C-function listeners do not exist. ev1chk: 51 mutants, 0 bad.
   PUSH ORDER (D-0384): gate/ev1d first, ONE ci_status; mutants/EV1d at the SAME SHA only after Evidence is green (dispatcher does/asks).
   Commit message prepared: .warm/commit6_msg.txt. Next: commit (ONE), then steps 2-4 of the brief.
