# LB2b — locating files: os/pl-files.c and os/pl-glob.c (design: lk-channel evidence/r2/design/loader_boot.md rows 208, 415, Q10)
Edit-only writer (Sonnet). NOTHING COMPILED OR RUN. Branch wip/lb2bw off main faee65f (LOCAL, never pushed).
Reference: swipl-devel cbf4e1896275. Extracts: `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/os/pl-files.c`.

## Scope (from the design)
LB2b = "os/pl-files.c's name, time and access predicates, `$absolute_file_name/2`, `expand_file_name/2` (os/pl-glob.c)";
the design row 208 lists exists_file/1, exists_directory/1, access_file/2, time_file/2, file_name_extension/3,
file_directory_name/2, file_base_name/2, `$absolute_file_name/2`, `$cwd/1`, expand_file_name/2. The TSV call sites are
exists_file 3 and expand_file_name 2. The rest of the two files is ported with them (same helpers, small); anything
that has no kernel function is refused by name. pl-files.jl exists (Y1: get_file_name, delete_file/1) and is EXTENDED;
pl-glob.jl is NEW. The file-name helpers pl-files.c calls live in pl-os.c (lines below) and go to src/os/pl-os.jl
(appended; flagged: that file is not disjoint from other steps, the block is appended at its end).

## Plan: ordered groups, upstream file:line -> Julia site
G0 plan (this file).
G1 pl-global.jl (flagged, own commit, appended field): `paths_CWDdir::String` = GD->paths.CWDdir (CWDlen = its
   byte length; "" = none), pl-global.h `paths`. One constructor argument at the end of src/pl-global.jl:135-171.
   Needed so $cwd/$chdir keep upstream's cached logical path (a symlinked cwd stays logical). STRUCT CHANGE: alloc pins x3.
G2 pl-os.c file names -> src/os/pl-os.jl: OsPath/PrologPath (pl-os.c:905-940, the non-XOS identity), canonicaliseFileName
   (1295-1415, in place on a byte buffer), canonicalisePath (1471-1500; utf8_path_lwr 1420-1470 for file_name_case_sensitive
   false), IsAbsolutePath (1753), BaseName (1892), DirName (1925).
G3 pl-os.c:1544-1690 expandVars (+takeWord 1522; `~`, `$VAR`; GD->os.myhome/fred caches left out: HOME and getpwnam read each time,
   see flags), AbsoluteFile (1764), PL_changed_cwd/cwd_unlocked/PL_cwd (1790-1880), ChDir (1986-2018).
G4 pl-files.c:36-420 helpers -> pl-files.jl: LastModifiedFile (62), SizeFile (92), access_mode/AccessFile/AccessDirectory (113-150),
   ExistsFile (153), ExistsDirectory (175), ReadLink (216), DeRefLink1/DeRefLink (230-300), SameFile (302), RenameFile (352),
   MarkExecutable (378). stat is Base.stat (uv_fs_stat), the rest libc ccalls (access, readlink, rename, chmod, mkdir, rmdir, chdir).
G5 pl-files.c:423-540 get_file_name flags: PL_FILE_ABSOLUTE, OSPATH, EXIST/READ/WRITE/EXECUTE, the file_name_variables flag
   (expandVars). PL_FILE_SEARCH (calls Prolog absolute_file_name/3 of library init.pl) stays refused by name, left to LB4.
G6 pl-files.c:596-825 predicates: time_file/2, size_file/2, access_file/2, read_link/3, exists_file/1, exists_directory/1,
   is_absolute_file_name/1, same_file/2, file_base_name/2, file_directory_name/2. IRIs (file_name_is_iri, pl-file.c:3942,
   iri_hook 4046-4075 -> Prolog `$iri`:iri_hook/4) : file_name_is_iri is ported here (3942), the hook call is refused by name.
G7 pl-files.c:895-1000 + 1000-1195: delete_directory/1, make_directory/1, rename_file/2, `$absolute_file_name`/2, `$cwd`/1,
   `$chdir`/1, file_name_extension/3 (+has_extension, name_too_long), prolog_to_os_filename/2 (identity on Unix),
   `$mark_executable`/1, `$my_file`/1; BeginPredDefs(files) 1200-1224 in upstream's ORDER (the Y1 table has delete_file only).
G8 pl-files.c:827-895 + pl-os.c:733 tmp_file/2, `$tmp_file_stream`/4 (TemporaryFile and DeleteTemporaryFile registry): decided
   after reading pl-os.c:700-860 (a stream from an fd needs Sfdopen; refused by name if the stream layer has no function).
G9 pl-glob.c wildcard_match/2,3: compile (~1-420), match; src/os/pl-glob.jl NEW.
G10 pl-glob.c expand_file_name/2 (430-790), directory_files/2 (790-860), BeginPredDefs(glob) 864-869.
G11 registration: `PL_predicates_from_glob` appended after `_files` in `_PRED_TABLES` / `_FOREIGN_VA` (src/pl-ext.jl: upstream's order
   is file, files, glob, ...), include("os/pl-glob.jl") in src/LogicKernel.jl (own tiny commit).
G12 rows (test/files/test_lb2b_swipl.jl; evidence/LB2B gen + driver + .out), tools/mutants/LB2B.py (>= 20), manifest block,
   docs/architecture.md block (last two commits).

Commit estimate (first 3 commits): ~20 (G0-G11 about 14, rows 2-3, mutants 1, manifest 1, docs 1, fixes 1-2).

## Done
(nothing yet)

## Left / next
G1.

## UNVERIFIED (nothing is compiled)
Everything.

## Flags for the audit
(see below as they arise)

## GATE ORDER (the gate agent)
Tier 2 first; fmt via `warm.sh send` (committed files); inventory; `check`; test/files/test_lb2b_swipl.jl on all three term
types; test/test_type_discipline.jl; `tools/pkgtest_way.sh test/files/test_lb2b_swipl.jl` (one at a time); push
`mutants/LB2B` at the WIP SHA; branch-gate; term grep (D-0164); alloc pins x3 (pl-global.jl changed: G1); gate push
`gate/lb2b` and `mutants/LB2B` at the SAME SHA.
