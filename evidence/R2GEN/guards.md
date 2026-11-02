# R2GEN guard proofs (slice 4, writer 3)

Every guard must be able to PASS and FAIL, both sides non-empty through ONE extractor. Two layers:
(A) test/test_port_check.jl "the R2 status: snapshot, owners, rendering" (fixture tree: pass, then one mutation per code, exact
code list asserted) and test/test_r2_status.jl (snapshot drift with a fixture git checkout, owners, rendering); (B) verdict level
on the REAL tree: `julia --project=. tools/port_check.jl` (exit code + violation lines) after a mutation of one committed file,
restored with `git checkout -- docs` (script run in a capped scope, output below, 2026-11-02, tip de32114).

| guard | code | mutation (real tree) | verdict |
|---|---|---|---|
| none | - | base | exit 0, 0 violations |
| block drift | R2-STATUS-DRIFT | architecture.md: `**total** \| 442` -> 443 | exit 1, R2-STATUS-DRIFT |
| block empty | R2-STATUS-EMPTY | markers kept, block deleted | exit 1, R2-STATUS-EMPTY |
| block missing | R2-STATUS-MISSING | BEGIN marker deleted | exit 1, R2-STATUS-MISSING |
| owner stale | R2-OWNER-STALE | owners: `pred:op/3` (a done predicate) appended | exit 1, R2-OWNER-STALE only |
| owners missing | R2-OWNER-MISSING | owners file deleted | exit 1, R2-OWNER-MISSING + R2-STATUS-DRIFT (every NO OWNER count changes the block) |
| NO OWNER count | (information) | owners: the `pred:succ/2` line removed | exit 1, R2-STATUS-DRIFT only: the count is in the block, a silent change cannot land |
| snapshot drift | R2-UPSTREAM-DRIFT | snapshot: `pred succ/2` -> `succ/3`, checkout present | exit 1, R2-UPSTREAM-DRIFT + R2-OWNER-STALE + R2-STATUS-DRIFT |
| snapshot pin | R2-UPSTREAM-PIN | snapshot header cbf4e189 -> cbf4e188 | exit 1, R2-UPSTREAM-PIN + R2-STATUS-DRIFT (the pin is printed in the block) |
| snapshot missing | R2-UPSTREAM-MISSING | snapshot deleted | exit 1, R2-UPSTREAM-MISSING |
| restored | - | `git checkout -- docs` | exit 0, 0 violations |

Fixture-level only (no src/ edit allowed on the real tree): a kernel src with one more registered predicate -> R2-STATUS-DRIFT +
R2-OWNER-STALE; no refusal site in src -> R2-STATUS-EMPTY (a category with no row: the scan found nothing, the table of zeros
would otherwise pass); R2-OWNER-DUP / -BAD (test_r2_status.jl + test_port_check.jl); R2-UPSTREAM-EMPTY.
NO OWNER non-empty on the real rows (109 = 1 pred + 61 refusal + 40 flag + 7 vmi) and 0 on the fixture
where every row has an owner, through the same `r2_no_owner`.
ONE-SIDED BY DESIGN: R2-UPSTREAM-DRIFT needs a checkout with the pin (CI has none, so there the snapshot is the source and the
block is checked against it; the drift is caught wherever a checkout exists, i.e. the local branch-gate and `--write-inventory`).
