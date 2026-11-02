# R2GEN plan: the generated R2 status block (audit D-0370 item 1, D-0371 item 5)

Tier 3 tooling, no engine code. `tools/r2_status.jl` is simple Julia over text files (no kernel loading); `tools/port_check.jl`
includes it and writes/checks the block like the code graph. Written edit-only: no daemon ran, nothing below is measured yet.

## Data sources (all mechanical)
1. BOOT FILES: `vendor/swipl-devel/boot/init.pl` (compiled first) plus the files `vendor/swipl-devel/boot/load.pl` consults, parsed
   from its `:- consult([...])` lists and `:- if(Cond)`/`:- endif` nesting; a file under a false condition (`threads`, kernel value
   false, os/pl-prologflag.jl) is listed as "conditional, skipped". LIBRARY FILES on the load path: seeds (const, `debug`: tabling.pl:119)
   plus the files their `use_module/autoload(library(X))` directives name, depth 1 (lists, prolog_stack, option, error, dcg/high_order).
2. UPSTREAM C (the pin, `git show <pin>:src/<file>` on the checkout that has the pin commit, as tools/vendor_swipl.sh does): every
   `PRED_IMPL/PRED_SHARE/PRED_DEF("name", N, ...)`, pl-ext.c `FRG(...)`, `PL_register_foreign("name", N` (multi-line), with the
   preprocessor condition stack (`#if/#ifdef/#elif/#else/#endif`) kept: windows / apple / threads rows are classed, not counted
   as plain gaps; and pl-vmi.c `VMI(NAME,` lines. Snapshot committed as `docs/r2_upstream.tsv` (kind, key, upstream file, condition),
   rewritten by `--write-inventory` and compared with the pin where a checkout with the pin is found (like the coverage block);
   the block itself is computed from the snapshot, so it is checked EVERYWHERE, CI included.
3. KERNEL: REGISTERED predicate = a `PL_extension("name", N` call in src/**/*.jl (the entries of every `PL_predicates_from_*` table
   in `_PRED_TABLES`; comment lines dropped, `\$` unescaped); VM instruction DONE = a `# PORT: pl-vmi.c NAME` marker in src/;
   flag DEFINED = `setPrologFlag(gd, [ld,] "name"` in src/os/pl-prologflag.jl.
4. REFUSED: the throw sites of the refusal exception (constructor in src/pl-comp.jl, found by name pattern, built by concatenation
   in the tool), the QLF helper's names, and the flag-setter refusals (`name == "flag"` branch that calls the flag refusal helper).
   One row per site, keyed `file::function::message-prefix` (no line numbers, they move; the line is shown, not keyed).
5. REFERENCED predicates: a loose tokenizer over the boot and library text (comments, 0'c, quoted atoms handled; `name(`+top-level
   comma count = arity; arity 0 only in goal position). Boot-Prolog heads (col-0 clause heads of boot/*.pl) are NOT gaps.
   Flags referenced: first atom argument of `current_prolog_flag/set_prolog_flag/create_prolog_flag/push_prolog_flag`.

## Status of a row
- predicate: C-defined at the pin, referenced by a boot or load-path library file, and (registered | missing). A condition class
  (windows, apple) leaves the count and prints as "platform"; threads-only prints as "threads". `refused` is for features, not
  predicates: a predicate row is done or missing.
- refusal site: always `refused` (the site is in src/); its row goes when the site goes.
- flag: done (kernel defines it, or the boot's `create_prolog_flag` defines it) | refused (setter refusal names it) | missing.
- VM instruction: done (marker) | missing.
`counts = done / refused / missing` per category and per boot file.

## Owners
`docs/r2_owners.tsv`: `key<TAB>owner step<TAB>note`; keys `pred:name/N`, `refusal:file::fn::msg`, `flag:name`, `vmi:NAME`, and
`cfile:pl-file.c` (every row of that upstream file without an exact key). A row without an owner prints `NO OWNER` and counts in
the burn-down (information, not a drift failure). The generator checks every key in the owners file exists (OWNER-STALE otherwise:
a finished feature's row leaves and the porter removes its line). Hand-edited, never generated.

## Slices (each: code + a unit test in test/test_r2_status.jl on a small fixture, both sides non-empty, the drift guard)
1. predicate part: boot list, referenced scan, upstream C scan, registered scan, per-file counts.
2. refusal sites + flag refusals.
3. flags + VM instructions.
4. rendering (table + Mermaid) + `port_check.jl` wiring, owners file, architecture.md markers, block via `--write-inventory`.
Gate agent when a slot is free: `--write-inventory` (writes the snapshot and the block), `warm.sh fmt`, `check`, the fast static
pre-check, `tools/pkgtest_way.sh test/test_r2_status.jl`, branch-gate. The test needs no kernel term types (text only).
