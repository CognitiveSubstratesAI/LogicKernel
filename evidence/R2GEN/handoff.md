# R2GEN handoff (agent 1, forced hand-back at the 150k cap; EDIT-ONLY, nothing was run, no daemon used)

Worktree ~/code/lk-r2gen, branch wip/r2gen (off main 012633e), not pushed. Plan: evidence/R2GEN/plan.md (committed).

## Commits
1. plan.md (docs only).
2. slice 1: tools/r2_status.jl + test/test_r2_status.jl: Prolog tokenizer (`r2_tokenize`, `r2_calls`, `r2_heads`), load.pl list with `:- if`
   conditions (`r2_load_list`, kernel flag `threads=false`), library closure depth 1 (`r2_boot_files`), pin C scan (`r2_scan_c`: PRED_IMPL/
   PRED_SHARE/PRED_DEF/FRG/PL_register_foreign + `VMI(` + the preprocessor condition class windows/apple/threads/other), snapshot text
   (`r2_snapshot_text`/`r2_read_snapshot`, planned file docs/r2_upstream.tsv), registered scan (`r2_registered`: `PL_extension("n", N`),
   rows (`r2_pred_rows`: done/missing/platform), per-file counts (`r2_file_table`), `r2_counts`.
3. slice 2 (WIP, committed with this handoff if the hook let it; check `git status`): `r2_strip_jl`, `r2_call_args`, `r2_functions`,
   `r2_refusal_rows` (constructor sites by name pattern built by concatenation, the QLF helper's names; one row per site keyed
   `refusal:file::function::what`, `detail` = `line N; step S` as the site names it, i.e. a free owner hint) + a testset in the test file.
   TWO KNOWN TEST FIXES, not applied (cap): in the `r2_strip_jl` assertion the expected second line is `y = 'a'` followed by FIVE spaces
   (it has four); in the `r2_call_args` assertion the closing index is 20 (it says 21).

## Not yet run anything: first job of the next agent (needs a free slot; plain `julia` over text, no kernel)
`julia --project=. tools/r2_status.jl` (prints counts + per-file table; with no docs/r2_upstream.tsv it needs a checkout with the pin:
~/dev-zone/swipl-devel-cbf4e189 is found), then `julia --project=. test/test_r2_status.jl`. Expect to debug typos/regex slips: the code
was written blind. Things to check first: `r2_tokenize` on boot/init.pl (counts of :end tokens vs `grep -c`), `@NamedTuple` aliases,
`r2_scan_c` on pl-proc.c/pl-ext.c (the FRG owner file is pl-ext.c, not the defining file: the owners TSV can use exact `pred:` keys).

## Remaining slices
3. flags + VM instructions: flags referenced = first atom arg of current/set/create/push_prolog_flag in the loaded boot+library tokens
   (`r2_calls` gives names; read the first argument from the token vector); kernel DEFINES = `setPrologFlag(gd, [ld,] "name"` in
   src/os/pl-prologflag.jl (regex over `r2_strip_jl` text); REFUSED = `R2_FLAG_REFUSAL_HELPER(k, "effect")` calls, the flag is the nearest
   preceding `name == "X"` (or `name in (...)`) line (os/pl-prologflag.jl:1197-1270 shape); a boot `create_prolog_flag` also defines.
   VM instruction rows from the snapshot's `vmi` kind: done = a `# PORT: pl-vmi.c NAME` marker in src/ (comment lines, so read the RAW
   text), else missing; owner keys `vmi:NAME`. Snapshot-driven, so checked everywhere.
4. rendering + wiring: `docs/r2_owners.tsv` (key, owner, note; keys `pred:`, `refusal:`, `flag:`, `vmi:`, `cfile:`; OWNER-STALE for a key with
   no row; rows without owner print `NO OWNER`, counted), `docs/r2_upstream.tsv` snapshot (written by `--write-inventory`, compared with the
   pin where a checkout with it is found, R2-UPSTREAM-DRIFT), markers in docs/architecture.md next to the code graph
   (`<!-- BEGIN GENERATED R2 status by tools/port_check.jl --write-inventory — do not hand-edit -->` … `<!-- END GENERATED R2 status -->`),
   rendering = a counts table per category (done / refused / missing / platform / NO OWNER), a per-boot-file table (`r2_file_table`), a
   missing-by-owner list, and a Mermaid `xychart-beta` bar of missing per category with a line of refused; hook into `port_check.jl`
   (`include("r2_status.jl")` at top level, `_block_violations("R2-STATUS", ...)`, `_write_section` in `write_inventory`), and a test that
   mutates a snapshot/owners line and sees DRIFT / OWNER-STALE. Words to avoid in text and commit messages: the refusal exception's name
   as one word, and its two-word and underscore forms (the tool builds them by concatenation: `R2_REFUSAL_EXCEPTION`).

## What the gate agent runs when a slot is free (after slice 4)
`julia --project=. tools/port_check.jl --write-inventory` (writes the snapshot + the block), `tools/warm.sh fmt`, `warm.sh check`, the fast
static pre-check, `tools/pkgtest_way.sh test/test_r2_status.jl` (ONE at a time), branch-gate, crash-term grep, push gate + mutants branches at
one SHA if the dispatcher wants a battery (Tier 3: probably no battery; ask).
