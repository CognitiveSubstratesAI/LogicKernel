# ORIGINAL: LB4A's mutant list — no swipl-devel counterpart.
# tools/mutants/LB4A.py — the mutation battery of LB4 chunk (a), the vendored boot/ and library/ (audit D-0286 item 1): the manifest
# tools/swipl_vendor_blobs.txt, vendor/swipl-devel/{PIN,boot,library}, the five generated INDEX.pl files, the home-tree builder
# tools/build_home.jl and the `home` flag (src/os/pl-prologflag.jl). Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Verdicts: written by the battery, not yet run. Every `old` was checked to occur exactly once
# (a text count, no Julia) and the vendored files to be ASCII without CR (the driver reads and writes in text mode).
# A mutant of a VENDORED file changes the file the driver restores afterwards: no vendored file is edited by hand, ever.
# Killed by test/test_vendored_swipl.jl (A1-A8), test/test_home_tree.jl (B1-B5) and the `home` testset of
# test/core_lang/test_prolog_flag_swipl.jl (C1). The step's own files come first in every TARGETS (a run stops at the first target
# that decides); test_vendored_plunit.jl and the other files are listed as D-0238 asks, for the shared code they could exercise.
# NOT LISTED (each with its reason):
#   * "gitlink compare skipped": this chunk has no gitlink — the vendored files are plain files held to the manifest; the manifest
#     itself is compared with `git ls-tree` of the pin in the last testset of test_vendored_swipl.jl, which CI's checkout makes a
#     FAILURE when missing (mutation.yml checks the pin out for any battery that targets test_vendored_*). A manifest line dropped
#     (A3) or added (A4) is caught by the count, the presence and the blob rows even without that checkout, and by the ls-tree
#     comparison with it; a mutant of that testset's own text would mutate a test, which this list does not do.
#   * tools/vendor_swipl.sh and tools/gen_library_index.sh: scripts that WRITE the tree; no test of this chunk runs them (the test
#     reads their output), so a mutant of them is a mutant of the generator, judged by the next `vendor_swipl.sh verify`.
# EQUIVALENT: none expected.
TARGETS = [
    "test/test_vendored_swipl.jl",
    "test/test_vendored_plunit.jl",
    "test/test_home_tree.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
]
VS = [TARGETS[0], TARGETS[2]]
HT = [TARGETS[2], TARGETS[3]]
FLAG = [TARGETS[3], TARGETS[2]]
M = "tools/swipl_vendor_blobs.txt"
PIN = "vendor/swipl-devel/PIN"
H = "tools/build_home.jl"
LISTS_LINE = "100644 blob 8bdaeec875c31df6cd6d542f79a6520a81ff6787\tlibrary/lists.pl\n"
MUTANTS = [
    # ── the vendored files: one byte, a file added, a file missing ──
    dict(id="LB4A-A1 one byte of vendor/swipl-devel/boot/init.pl changed: its blob id is no longer the manifest's (KILL test_vendored_swipl.jl, the per-file blob rows)",
         file="vendor/swipl-devel/boot/init.pl", targets=VS,
         old="Author:        Jan Wielemaker", new="Author:        Jbn Wielemaker"),
    dict(id="LB4A-A2 one byte of vendor/swipl-devel/library/lists.pl changed (KILL test_vendored_swipl.jl, the per-file blob rows)",
         file="vendor/swipl-devel/library/lists.pl", targets=VS,
         old="append([], L, L).", new="append([], L, M)."),
    dict(id="LB4A-A3 the manifest drops the line of library/lists.pl: the file is ADDED to the tree (KILL test_vendored_swipl.jl: the 210-file count, the nothing-added row, and in CI the ls-tree comparison)",
         file=M, targets=VS,
         old=LISTS_LINE, new=""),
    dict(id="LB4A-A4 the manifest gains a line for library/zz_missing.pl: a file MISSING from the tree (KILL test_vendored_swipl.jl: the count, the blob row of a missing file, the nothing-missing row)",
         file=M, targets=VS,
         old=LISTS_LINE,
         new=LISTS_LINE + "100644 blob 0123456789abcdef0123456789abcdef01234567\tlibrary/zz_missing.pl\n"),
    dict(id="LB4A-A5 vendor/swipl-devel/PIN names another commit than tools/SWIPL_VERSION (KILL test_vendored_swipl.jl, the PIN row)",
         file=PIN, targets=VS,
         old="commit: cbf4e1896275a07794332fd98ad0dcb11bf51919",
         new="commit: cbf4e1896275a07794332fd98ad0dcb11bf51918"),
    dict(id="LB4A-A6 the manifest's header names another commit than the pin (KILL test_vendored_swipl.jl: header commit == pin)",
         file=M, targets=VS,
         old="SWI-Prolog/swipl-devel cbf4e1896275a07794332fd98ad0dcb11bf51919",
         new="SWI-Prolog/swipl-devel cbf4e1896275a07794332fd98ad0dcb11bf51918"),
    dict(id="LB4A-A7 an entry of library/clp/INDEX.pl names a file that is not there: a stale entry (KILL test_vendored_swipl.jl, the INDEX testset; its blob id changed too)",
         file="vendor/swipl-devel/library/clp/INDEX.pl", targets=VS,
         old="index(:(op,op(760,yfx,#<=>)), bounds, bounds).",
         new="index(:(op,op(760,yfx,#<=>)), bounds, zz_missing)."),
    dict(id="LB4A-A8 vendor/swipl-devel/PIN names another version than tools/SWIPL_VERSION (KILL test_vendored_swipl.jl, the PIN version row)",
         file=PIN, targets=VS,
         old="version: 10.1.19", new="version: 10.1.18"),
    # ── the home tree (tools/build_home.jl) ──
    dict(id="LB4A-B1 the ext/plunit link points at vendor/, not packages/plunit (KILL test_home_tree.jl: the link resolves to packages/plunit)",
         file=H, targets=HT,
         old="    want[ext] = relpath(plunit, dirname(ext))\n",
         new="    want[ext] = relpath(vendor, dirname(ext))\n"),
    dict(id="LB4A-B2 the ext/plunit link is not wanted at all (KILL test_home_tree.jl: 242 links, library/ext/plunit present)",
         file=H, targets=HT,
         old="    want[ext] = relpath(plunit, dirname(ext))\n",
         new="    nothing\n"),
    dict(id="LB4A-B3 the removal pass keeps a file link with another target or nothing wants (KILL test_home_tree.jl: the stale-tree row)",
         file=H, targets=HT,
         old='$home is not a home tree")\n                get(want, p, nothing) == readlink(p) || rm(p)\n',
         new='$home is not a home tree")\n                nothing\n'),
    dict(id="LB4A-B4 a real file in the tree is no error (KILL test_home_tree.jl: the real-file row throws and keeps the file)",
         file=H, targets=HT,
         old='                islink(p) || error("build_home: $p is a file, not a link: $home is not a home tree")\n',
         new='                islink(p) || continue\n'),
    dict(id="LB4A-B5 the removal pass keeps a link to a directory whose text is wrong (KILL test_home_tree.jl: the ext/plunit link with another target)",
         file=H, targets=HT,
         old="                if islink(p)\n                    get(want, p, nothing) == readlink(p) || rm(p)\n",
         new="                if islink(p)\n                    nothing\n"),
    dict(id="LB4A-B6 a directory left empty by the removal pass stays (KILL test_home_tree.jl: library/stale is gone)",
         file=H, targets=HT,
         old="elseif !(p in dirs) && isempty(readdir(p))",
         new="elseif false"),
    # ── the `home` flag ──
    dict(id="LB4A-C1 the `home` flag names the package directory again, not the home tree (KILL the `home` testset of test_prolog_flag_swipl.jl: h == home_dir())",
         file="src/os/pl-prologflag.jl", targets=FLAG,
         old='joinpath(dirname(dirname(@__DIR__)), "home")',
         new="dirname(dirname(@__DIR__))"),
]
