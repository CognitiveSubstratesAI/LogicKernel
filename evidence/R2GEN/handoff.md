# R2GEN handoff (writer 3: slice 4 DONE, run, committed; gate agent next)

Worktree ~/code/lk-r2gen, branch wip/r2gen (off main 012633e), NOT pushed. Plan: evidence/R2GEN/plan.md; guard proofs:
evidence/R2GEN/guards.md. Plain `julia` over text in a capped scope:
`systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64 julia --project=. <file> > out 2>&1`.

## Commits on wip/r2gen (slices 1-3 by writers 1-2, see git log; slice 4 by writer 3)
- 36a46ba FIXED refusal rows one line each (`_r2_lit` joins `" * "` concatenations; `add!` squeezes whitespace in what/step; fixture + test)
- 2301649 ADDED docs/r2_upstream.tsv + docs/r2_owners.tsv + r2_upstream_violations / r2_owner_violations / r2_no_owner
- 4fb9788 ADDED rendering (r2_render_rows, r2_state, r2_render, `tools/r2_status.jl --render`), the block in docs/architecture.md, the
  port_check wiring (include r2_status.jl; r2_status_violations after the CODE-GRAPH block, only where src/pl-inline.jl exists;
  write_inventory rewrites the snapshot when a checkout has the pin, then the block). The hook wants the whole tree staged, so wiring
  and rendering are one commit.
- de32114 ADDED the guard test in test/test_port_check.jl
- (this commit) port_check header comment, evidence/R2GEN/guards.md, this handoff.

## FINAL COUNTS (pin cbf4e189; the block in docs/architecture.md)
predicates done 224 / refused 0 / missing 198 / platform 3; refusal sites 75; flags 59 done / 22 refused / 22 missing; VM instructions
159 done / 74 missing. NO OWNER: 109 = 1 pred (apple_current_locale_identifier/1, TSV says platform) + 61 refusal sites + 40 flags +
7 VMI (B_SMALLINTW B_THROW H_SMALLINTW L_SMALLINTW S_DET S_INCR_DYNAMIC S_THREAD_LOCAL). Owners file: 197 pred seeds + VMI families +
table_* flags + kfile:pl-qlf.jl (LB3). All equal the handoff anchors; ONE difference of reading: "1554 predicate definitions" is the
RAW match count of r2_pin_c_rows (1554 matches + 233 VMI = 1787); a definition appears several times (PRED_IMPL is matched in
several places per file), the snapshot lists each once: 873 pred lines = 801 distinct name/arity + 233 VMI. The counts of the block
are over distinct keys, as before.

## Gate agent (when a slot is free), in this order, ONE at a time
1. `julia --project=. tools/port_check.jl --write-inventory` (must change nothing: block and snapshot are committed; exit 0, no R2- line)
2. `tools/warm.sh fmt`, `tools/warm.sh check`, the fast static pre-check
3. `tools/pkgtest_way.sh test/test_r2_status.jl` (text only, one process), then test/test_port_check.jl on all three term types
   (it takes ~55 s for the R2 testset alone; the R2 guards add ~10 s to every port_check run on the real tree: r2_collect + the
   `git show` scan when a checkout has the pin)
4. branch-gate; the D-0164 term grep (the refusal exception's name appears only through R2_REFUSAL_EXCEPTION, never as one word in text)
5. check whether test/ci_slices.jl / test costs list new test files (test_r2_status.jl is new) and register it if required
6. push gate + mutants (Tier 3: ask the dispatcher). Mutants to write: r2_registered (drop a match), r2_owner_violations (never STALE),
   r2_status_violations (no EMPTY check), r2_upstream_violations (no PIN), `_r2_lit` (no join); TARGETS: test_r2_status.jl AND
   test_port_check.jl (D-0238).
Not run here: warm.sh anything, the three-type run of test_port_check.jl as a whole (only its R2 testset, standalone, 19 passed),
the fmt check (the new code follows the file's style, not formatted by the formatter).

## Ordinary use afterwards
A porter who finishes a feature: `--write-inventory` moves rows from missing to done; its owners lines turn R2-OWNER-STALE and are
removed by hand. A sync: new pin in tools/SWIPL_VERSION -> R2-UPSTREAM-PIN until `--write-inventory` (needs a checkout with the pin).
