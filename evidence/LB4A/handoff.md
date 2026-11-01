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

## STATE
(updated after each commit)
