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

## STATE (writer 2): ALL NINE GROUPS COMMITTED on wip/lb4a (HEAD = the commit after this file's own). Edit-only: nothing compiled or run, nothing pushed.
Commits on wip/lb4a after d334065: 7f98820 plan; ad6fac7 g1 (manifest, vendor_swipl.sh, test_vendored_swipl.jl); 131967c g2 (boot, LICENSE, PIN, .gitattributes);
eb82dc3 g3 (library, 210 files); 24ec0bb g4 (gen_library_index.sh + five INDEX.pl); cd06736 g5 (build_home.jl, test_home_tree.jl); 8191129 g6 (`home` flag + testset);
c0aec44 g7 (plumbing: codecov `vendor/**`, formatter `vendor`, mutation.yml pin checkout also for `test_vendored`, comments in CI.yml/evidence.yml/mutate_suite.sh,
README note + layout rows, NOTICE entry; test_home_tree.jl stale row now gives ext/plunit ANOTHER target, which reaches the link-to-directory removal branch);
eb6b3b1 g8 (tools/mutants/LB4A.py, 15 mutants); 31a0274 g9 (docs/architecture.md section, inserted before "Still to come"); then this handoff.
Daemon: this writer started none; lanes.conf untouched (it never held a daemon).

### Mutant list validation (python3 -I, throwaway checker in the writer's scratchpad: runpy, count(old)==1 in the file, new != old, replace changes the text, ids unique, targets exist, no CR)
`15 mutants, 15 unique ids, 4 baseline targets, BAD=0`. UTF-8 em dashes (comments) only in tools/swipl_vendor_blobs.txt, tools/build_home.jl, src/os/pl-prologflag.jl; the vendored
files used (boot/init.pl, library/lists.pl, clp/INDEX.pl, PIN) are ASCII without CR. A1-A8 (vendored side), B1-B6 (build_home.jl), C1 (flag). None equivalent.
The brief's "gitlink compare skipped" has no mutant: this chunk holds no gitlink; the manifest-vs-`git ls-tree` testset is what kills A3/A4 in CI (the count and presence rows kill them without the checkout too).
B3 and B5 depend on the test_home_tree.jl stale row (B5 only since g7). Survivors to look at first, if any: B6 (needs the `stale/deeper` directory left empty), B4.

### UNVERIFIED (nothing was run: no Julia in this step)
- test/test_vendored_swipl.jl, test/test_home_tree.jl (incl. the g7 edit: `symlink("../../boot", plunit)`, then `readlink(plunit) != good[...]`), the new testset in test_prolog_flag_swipl.jl,
  tools/build_home.jl: never parsed or run. Check on first run: the `include` of tools/build_home.jl from two test files (identical consts, a redefinition warning is possible);
  `walkdir(...; topdown=false)` removal order in build_home; `rm` of a link to a directory (and whether walkdir lists a link to a directory under `dirs` or `files`);
  the INDEX entry regex; fmt will re-wrap the new Julia.
- Pkg.test-way run: tests build the tree into mktempdir (test_home_tree) but the flag testset builds at `<pkg>/home` (must be writable: a read-only installed package fails it).
- Count claims in the test: 26 boot + 210 library + 5 INDEX + ext/plunit = 242 links (checked against git ls-tree: 236 upstream files + 5 generated).
- fmt on tools/build_home.jl (margin 92) and the edited line of src/os/pl-prologflag.jl; docs/port_inventory.md not regenerated (gate step).
- mutation.yml `if:` edit (two places): expression syntax not run by GitHub; read as `A || B`, both `contains(format(...), ...)`.
- The harness reads files in text mode with the default encoding: tools/build_home.jl and src/os/pl-prologflag.jl hold UTF-8 dashes, as the files other lists already mutate do.

### QUESTIONS FOR THE AUDIT
1. The generated library/INDEX.pl (from the vendored files only) has 58 entries the Linux install's own INDEX.pl lacks (files dom.pl, help.pl, wasm.pl, win_dde `dde.pl`: upstream's
   build does not install them here), so LB5's autoload finds e.g. apropos/1 where the oracle does not. Options: (a) keep as generated: byte-faithful to the source tree and reproducible
   by the one script; (b) filter the four files out: matches the Linux install, but a filtered file is a hand edit of a generated artifact and the script grows a list to keep in step with
   upstream. RECOMMENDATION: (a). A difference from the install shows when it matters (an autoload test) and then gets a KNOWN DIFFERENCE row; filtering can be added in LB5 with a measurement.
2. ext/plunit has no INDEX.pl in the home (the oracle's install has one for packages); autoloading run_tests/0 etc. is LB5's. packages/plunit is read-only vendored, so any index goes elsewhere. No action in (a).
3. Where the home tree lives for a Pkg-INSTALLED (read-only) package: g6 fixes `<pkg>/home`, which a read-only depot cannot build. For LB4 b, options: (a) a writable scratch location
   (a Scratch.jl space or a depot `scratchspaces/<uuid>/home`) built at first use, the `home` flag then names it; (b) build the tree at package build time into the package directory
   (also needs write access at install); (c) a tree of copies shipped in the package (no links, but vendor/ is duplicated). RECOMMENDATION: (a) with `home` computed at load time;
   until then development and CI run from a checkout, where `<pkg>/home` is writable. LB4 b decides; the flag line and test_home_tree.jl's default-place row move with it.
4. The dispatcher's D-0164 term scan over the diff hits upstream text in vendor/: the scan must EXCLUDE `vendor/` (pathspec `-- . ':(exclude)vendor'`),
   plus the commit messages (this writer's avoid the listed words); the gate's own script carries the pattern.

### GATE ORDER (dispatcher / gate lane)
0. `tools/vendor_swipl.sh verify` first (needs the upstream checkout; no output = byte-identical, 238 files).
1. fmt (`warm.sh fmt` sees the HEAD diff only: format committed .jl files through `warm.sh send`; vendor/ is ignored by the formatter), inventory (regenerate docs/port_inventory.md),
   check (includes the Pkg.test-way run, D-0222).
2. New/changed test files x3 term types: test/test_vendored_swipl.jl, test/test_home_tree.jl, test/core_lang/test_prolog_flag_swipl.jl; then test/test_type_discipline.jl.
3. `tools/pkgtest_way.sh <file>` for each of the three files, ONE at a time (~3 GB peak).
4. Push `mutants/LB4A` at the WIP SHA (LB4A.py exists; its TARGETS name test_vendored_*, so mutation.yml checks the pin out).
5. branch-gate; term scan EXCLUDING vendor/ (question 4); then the gate push on a FRESH name and `mutants/LB4A` at the SAME SHA.
No struct change, no Tier-1 file touched (pl-global.jl untouched). Never edit a vendored file: a mutant edits one only through the harness's text replace, restored after the run.

## GATE AGENT STATE (2026-11-01 ~13:30Z)
wip/lb4a2 = rebased onto main 1286e62 (T2 section kept beside LB4 a), review findings 1-4 applied (660eaa7), fmt pass 768753f.
Done: vendor verify clean, fmt, inventory (no change), check PASS (239s), test_vendored_swipl.jl (1543) and test_home_tree.jl (755) pass.
mutants/LB4A pushed at 768753f (from local gate/lb4a, same SHA). Daemon logickernel-warm-2e3734af in lk-warm2.slice (6G cap kept, D-0287 permanent rule).
Running: warm.sh file test/core_lang/test_prolog_flag_swipl.jl (3 term types). Left: type discipline, pkgtest_way x3, branch-gate, term scan excl vendor/, gate/lb4a push.
