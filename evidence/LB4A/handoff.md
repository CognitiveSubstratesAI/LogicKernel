# LB4A — vendoring swipl-devel boot/ and library/ (R2 LB4 chunk (a)). Edit-only coding. NOTHING COMPILED OR RUN.

Branch wip/lb4a off origin/main d334065. LOCAL, never pushed. Audit D-0286 items 1 and 2; plan evidence/R2/lb4_sizing.md section 1 (lk-channel).
Reference: swipl-devel cbf4e1896275 (tools/SWIPL_VERSION `commit:`). Daemon: this writer started none; lanes.conf untouched.
No Julia was run; swipl 10.1.19 (the local oracle, home ~/.local/swipl-bp2/lib/swipl) generated the INDEX.pl files.

## Plan (ordered groups; one commit each)
1. Manifest `tools/swipl_vendor_blobs.txt` (`git ls-tree -r <pin> boot library LICENSE`, plunit_blobs.txt shape) + `test/test_vendored_swipl.jl`.
2. `vendor/swipl-devel/boot/*.pl` (26 files), `LICENSE`, `PIN`. Written by `git show <pin>:<path>`, byte for byte.
3. `vendor/swipl-devel/library/` (210 files).
4. The five INDEX.pl (library, clp, dcg, unicode, lynx: src/CMakeLists.txt:120-121 SWIPL_DATA_INDEXED_DIRS) from `tools/gen_library_index.sh`
   (oracle runs make_library_index/1, cmake/LibIndex.cmake:17-28), vendored with their manifest lines.
5. Home-tree builder `tools/build_home.jl` (ORIGINAL; cmake/InstallSource.cmake:8-25) + `test/test_home_tree.jl`.
6. `home` flag at the tree (src/os/pl-prologflag.jl:781-782) + a row in test/core_lang/test_prolog_flag_swipl.jl.
7. Plumbing: `.gitattributes`, codecov/formatter ignores, workflow comments, README + NOTICE vendoring note.
8. `tools/mutants/LB4A.py`.
9. docs/architecture.md section; this handoff (final).

## Decisions (D-0286 item 1)
- Path `vendor/swipl-devel/{boot,library}`; `LICENSE` (upstream's blob) and `PIN` beside them. NO edit of a vendored file, ever.
- The manifest lists upstream's blobs (paths relative to vendor/swipl-devel, upstream's own paths) plus the five generated INDEX.pl lines.

## STATE (writer 1, forced hand-back at the 150k cap): groups 1-6 COMMITTED; 7 (plumbing) PARTLY NOT DONE; 8, 9 NOT WRITTEN. Nothing compiled or run.
Commits on wip/lb4a after d334065: 7f98820 plan; ad6fac7 g1 (tools/swipl_vendor_blobs.txt, tools/vendor_swipl.sh, test/test_vendored_swipl.jl);
131967c g2 (vendor/swipl-devel/boot 26 files + LICENSE + PIN, .gitattributes `vendor/** -text -whitespace linguist-vendored`);
eb82dc3 g3 (vendor/swipl-devel/library, 210 files; `vendor_swipl.sh verify` = 0 differences, 238 files incl. boot/LICENSE/PIN);
24ec0bb g4 (tools/gen_library_index.sh + the five INDEX.pl: library, clp, dcg, unicode, lynx; 1269 entries, each names a vendored file;
second run byte-identical; manifest GENERATED section has their 5 blob lines); cd06736 g5 (tools/build_home.jl, test/test_home_tree.jl,
.gitignore `/home/`); 8191129 g6 (src/os/pl-prologflag.jl `home` = <pkg>/home; testset "home: ..." in test/core_lang/test_prolog_flag_swipl.jl).

### LEFT TO WRITE (next agent, Sonnet, edit-only)
- g7 plumbing, ONE commit: (a) codecov.yml `ignore:` add `"vendor/**"`; (b) .JuliaFormatter.toml `ignore` add `"vendor"`; (c) .github/workflows/mutation.yml:
  the pin-checkout steps at ~102 and ~146 run only `if: ... contains(..., 'mutate_suite')`; LB4A's mutants target test/test_vendored_swipl.jl and
  test_vendored_plunit.jl, which FAIL in CI without the checkout (CI=true), so add `|| contains(format('{0} {1}', inputs.targets, needs.plan.outputs.targets), 'test_vendored')`
  to those `if:` conditions (look at `grep -n mutate_suite .github/workflows/mutation.yml`; the `plan` job may need the same); (d) comment lines in CI.yml (~81, ~250),
  evidence.yml (~65), tools/mutate_suite.sh:7 mention test/test_vendored_swipl.jl next to test_vendored_plunit.jl; (e) README: a vendoring note (what vendor/ is,
  byte-identical, never edited, tools/vendor_swipl.sh + gen_library_index.sh + build_home.jl) and NOTICE: an entry "swipl-devel boot/ and library/ — vendored unchanged"
  (BSD-2, upstream LICENSE kept at vendor/swipl-devel/LICENSE; copy the plunit block's shape at NOTICE:94-120). Aqua: nothing walks vendor/ (no .jl in it;
  test/test_package.jl walks only test/ and bench/); tools/port_check.jl scans src, boot, test, bench, scryer-prolog only.
- g8 tools/mutants/LB4A.py (format of tools/mutants/MOD3b.py; the driver text-replaces ONE occurrence in `file`, which may be any path, so data files work;
  it reads/writes in TEXT mode, so mutate only ASCII/UTF-8 files without CR: pick e.g. vendor/swipl-devel/boot/init.pl and library/lists.pl and check `grep -c -F`).
  A "file added / file missing" mutant is a mutation of the MANIFEST (tools/swipl_vendor_blobs.txt: delete a line = file added; add a line for a nonexistent path = missing).
  List: (1) one byte changed in boot/init.pl; (2) one byte in library/lists.pl; (3) manifest line dropped (added file); (4) manifest line added (missing file);
  (5) vendor/swipl-devel/PIN commit changed; (6) manifest header commit changed; (7) a library/INDEX.pl entry renamed to a missing file (stale entry; the
  manifest blob catches it too); (8) src/os/pl-prologflag.jl `home` back to the package directory; (9) tools/build_home.jl: ext/plunit link target wrong
  (`relpath(plunit, dirname(ext))` -> `relpath(vendor, dirname(ext))`); (10) tools/build_home.jl: the `ext/plunit` entry not added (`want[ext] = ...` removed);
  (11) the removal pass skipped (`get(want, p, nothing) == readlink(p) || rm(p)` -> `nothing`). TARGETS (D-0238): test/test_vendored_swipl.jl, test/test_vendored_plunit.jl,
  test/test_home_tree.jl, test/core_lang/test_prolog_flag_swipl.jl. "gitlink compare skipped" has no counterpart in this chunk (the manifest-vs-`git ls-tree` testset is
  killed by mutants 3 and 4 when an upstream checkout is there; say so). Validate with a throwaway python3 -I + runpy checker in the scratchpad (old once, new != old,
  ids unique, targets exist). Equivalents: none expected.
- g9 docs/architecture.md section (APPEND at the end: `## LB4 chunk a — the vendored boot/ and library/`), note that docs/port_inventory.md is regenerated at the gate; then the
  final handoff update.

### UNVERIFIED (nothing was run: no Julia in this step)
- test/test_vendored_swipl.jl, test/test_home_tree.jl, the new testset in test_prolog_flag_swipl.jl, tools/build_home.jl: never parsed or run. Check on first run: the
  `include` of tools/build_home.jl from two test files (identical consts); `walkdir(...; topdown=false)` removal order in build_home; `rm` of a link to a directory;
  the INDEX entry regex; fmt will re-wrap the new Julia.
- The Pkg.test-way run: tests build the tree into mktempdir (test_home_tree) but the flag testset builds at `<pkg>/home` (must be writable: a read-only installed package fails it).
- Count claims in the test: 26 boot + 210 library + 5 INDEX + ext/plunit = 242 links (checked against git ls-tree: 236 upstream files + 5 generated).
- fmt on tools/build_home.jl (margin 92) and the edited line of src/os/pl-prologflag.jl.

### QUESTIONS FOR THE AUDIT
1. The generated library/INDEX.pl (from the vendored files only) has 58 entries the Linux install's own INDEX.pl lacks (files dom.pl, help.pl, wasm.pl, win_dde `dde.pl`: upstream's
   build does not install them here). Autoload in LB5 then finds e.g. apropos/1 where the oracle does not. Keep as generated (recommended: byte-faithful to the source tree), or filter?
2. ext/plunit has no INDEX.pl in the home (the oracle's install has one for packages); autoloading run_tests/0 etc. is LB5's. packages/plunit is read-only vendored, so any index goes elsewhere.
3. Where the home tree lives for a Pkg-INSTALLED (read-only) package: g6 fixes `<pkg>/home`; LB4 b would need a writable depot/scratch location and then the `home` flag moves with it.
4. The dispatcher's crash-term grep (D-0164) over the diff will hit upstream text in vendor/ (words like abort, crash): exclude `vendor/` from the diff scanned, or the gate will report false hits.

### GATE ORDER (dispatcher / gate lane)
fmt (`warm.sh fmt` sees the HEAD diff only: format committed .jl files through `warm.sh send`), inventory (regenerate docs/port_inventory.md), check, new test files x3 term types
(test_vendored_swipl.jl, test_home_tree.jl; plus test_prolog_flag_swipl.jl), test/test_type_discipline.jl, `tools/pkgtest_way.sh` for each of the three files ONE at a time,
push mutants/LB4A at the WIP SHA once LB4A.py exists, branch-gate, term grep (exclude vendor/), gate push on a FRESH name + mutants/LB4A at the SAME SHA.
Run `tools/vendor_swipl.sh verify` first (no output = byte-identical). No struct change, no Tier-1 file touched (pl-global.jl untouched).
