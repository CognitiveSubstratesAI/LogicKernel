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

## Done (commits on wip/lb2bw, off main faee65f; nothing compiled)
- 7cc0c76 plan (this file) = G0.
- 7f9bcb7 G1: `paths_CWDdir::String` last field of PL_global_data + constructor arg `""` (src/pl-global.jl). FLAGGED: struct change, alloc pins x3.
- 725a780 G2: src/os/pl-os.jl appended block "file names (pl-os.c)": PrologPath, OsPath, IsAbsolutePath, _cfn_at, canonicaliseFileName
  (0-based offsets `inp`/`out`/`start`, saveb stack, in-place on a NUL-padded copy), utf8_path_lwr, canonicalisePath(ld, path), BaseName, DirName;
  `file_name_is_iri` in src/os/pl-files.jl (after PATH_MAX).
- 0b6896d G3: pl-os.jl: takeWord, expandVars (`~user` refused by name: NotPortedError culprit `user`; HOME read each time), AbsoluteFile(ld, spec),
  PL_changed_cwd, PL_cwd(ld) (cache in gd.paths_CWDdir; no cache when ld.GD === nothing), is_cwd, ChDir(ld, path)::Int (0 or errno; -1 = AbsoluteFile failed).
- 095bdf3 G4: pl-files.jl ACCESS_* (Int), F_OK/X_OK/W_OK/R_OK, statfunc (StatStruct or negated errno), LastModifiedFile/SizeFile (value, errno),
  access_mode, AccessFile, AccessDirectory, ExistsFile, ExistsDirectory, ReadLink, DeRefLink1, DeRefLink(ld, link), SameFile(ld,f1,f2), `_ascii_lower`,
  RenameFile (errno), `_umask`, MarkExecutable(ld, name).
- 22c0114 G5: get_file_name: FILEVARS (expandVars), EXIST/READ/WRITE/EXECUTE checks, ABSOLUTE (AbsoluteFile); PL_get_file_name applies OSPATH. PL_FILE_SEARCH refused (step LB4).
- ed87eea G6: time_file, size_file, access_file, read_link, exists_file, exists_directory, is_absolute_file_name, same_file, file_base_name, file_directory_name;
  `_iri_hook_refused` (IRI args raise NotPortedError, LB4), `_is_atom_named`, `_unify_atom_chars`.
- 58dcd11 G7: delete_directory, make_directory (`_rmdir`, `_mkdir` ccalls), rename_file, $absolute_file_name, $cwd, $chdir, has_extension, file_name_extension,
  prolog_to_os_filename, $mark_executable, $my_file (getuid ccall); PL_predicates_from_files now in upstream's order, 23 entries.
- 449cc17 G8: tmp_file/2 and $tmp_file_stream/4 registered, refused by name (NotPortedError step "LB2b audit"): TemporaryFile's table GD->os.tmp_files has no
  field in PL_global_data (struct change; proposal `os_tmp_files`), Sfdopen is not in the stream layer.
- 7e6976c G9: NEW src/os/pl-glob.jl: GLOB_* codes, compile_pattern, compilePattern, match_pattern, matchPattern, wildcard_match, pl_wildcard_match2/3_va.
- G10 (committed TOGETHER with this handoff text, because the commit hook refuses a partial index; the cap hook ended the session first): the appended block of
  src/os/pl-glob.jl (un_escape, utf8_exists_file, expand, utf8casecmp, sort_expand, pl_expand_file_name2_va, pl_directory_files2_va, PL_predicates_from_glob).
  FIRST ACTION of the next agent: in `expand` delete the two unused lines `meta = false` and `meta = true` (python edit asserting count 1 each, own call), then commit
  it as a fix folded into G11's commit message.
Commit count so far 10 (plan + G1-G9 = 9 commits + handoff commits); estimate: about 20 in all.

## Done since (coder 3; nothing compiled or run, swipl only)
- 1e62c7a FIXED: pl-glob.jl expand drops the two unused meta assignments.
- ba5e03f G11: PL_predicates_from_glob after _files in _PRED_TABLES and _FOREIGN_VA (src/pl-ext.jl), include("os/pl-glob.jl") after pl-files.jl (src/LogicKernel.jl). No name clashes (named-file greps).
  NOTE for the manifest block: test/static_analysis_manifest.jl:2604 has the Y1 line `(LK._extension_sigs, Tuple{typeof(LK.PL_predicates_from_files)}, false)`; add the same for PL_predicates_from_glob (appended block).
- 19375cd G12 rows: test/files/test_lb2b_swipl.jl (+ .pl, .out beside it), evidence/LB2B/{gen_lb2b_rows.py, fixtures.sh, run_lb2b_rows.sh, test_lb2b_swipl.out}. 386 rows, swipl 10.1.19, `timeout 20`,
  two byte-identical runs (run_lb2b_rows.sh <scratch-dir>, from the repo root; it regenerates the .pl and copies the .out to test/files and evidence/LB2B). Refusals (tmp_file, $tmp_file_stream, IRI) are a second
  testset in the .jl (NotPortedError, step "LB2b audit" / "LB4"). Non-vacuity thresholds are in the .jl (counted on the .out: existence_error 27, type_error 28, instantiation_error 27, false 64, true 75).
  If a row is added: edit gen_lb2b_rows.py, rerun run_lb2b_rows.sh, `git add` the 4 generated files, thresholds stay valid.
  Facts from the swipl run worth knowing: stderr of the swipl run holds one line (`$my_file` nowhere); contexts differ per predicate (size_file/rename_file/access_file: `context(Name/Arity, Msg)` without `system:`);
  `[A-C]x` with case_sensitive(false) does not match `bx` (the set is not lower-cased); `[^a-c]` is no negation; prolog_to_os_filename(_,_) succeeds; expand_file_name('lk_lb2b_d*/sub/*') is [].
  Rows depend on a non-root user (lk_lb2b_ro write is false).

## Left / next
1. tools/mutants/LB2B.py (NOT STARTED, >= 20; format of tools/mutants/MOD3b.py; fields id, file, old, new, targets, optional equivalent). Candidate list (anchors read in the source, each `old` must be re-counted with grep -c -F):
   pl-glob.jl: `push!(out, GLOB_ANY)\n` -> GLOB_STAR (t244-246); `push!(out, GLOB_STAR)\n` -> GLOB_ANY (t238,t247); STAR branch `match_pattern(p, pi, s, si, flags) && return true` -> `false && return true` (t238);
   ALT `match_pattern(p, pi + 1, s, si, flags) && return true` -> false (needs new row wildcard_match('{a,b}c', ac)); JMP `pi += p[pi]\n        elseif c == GLOB_ALT` -> `pi += 1`; ANYOF range `c2 <= p[pi + 2]` -> `<` and `c2 >= p[pi + 1]` -> `>`
   (NEW ROWS: '[a-c]x' vs cx and ax); `if _glob_at(p, pos) == Int('-') && ce != Int(']')` -> `if false` (t250); ANY no end check `_glob_at(s, si) == 0 && return false` (NEW ROW wildcard_match('?', '')); char branch IGNCASE line (t278);
   compile `(mflags & M_IGNCASE) != 0 && (c = _glob_lower(c))` -> nothing (t276); `case_sensitive = vals[1] !== false` -> `= true` (t276); `case_sensitive || (mflags |= M_IGNCASE)` -> nothing; `"Unmatched '{'"` -> `"Unmatched '['"` (t259);
   `(c == Int('}') || c == Int(',')) && curl == GLOB_CURL` -> `false && curl == GLOB_CURL` (t256); `push!(out, c2 == 0 ? c : c2)` -> `push!(out, c)` (t261); expand `dot = startswith(patbuf, '.')` -> `dot = true` (t308);
   expand `for name in vcat([".", ".."], names)` -> `for name in names` (t310); directory_files `for e in vcat([".", ".."], names)` -> `for e in names` (t286); sort_expand `return sort(files)` -> `return files` (t298);
   expand `if last == 1 || utf8_exists_file(path)` -> `if last == 1` (t314); `if ncodeunits(s) > PATH_MAX - 1` -> `> PATH_MAX * 4` (t350).
   pl-files.jl: SizeFile `return (st.size, 0)` -> `st.size + 1` (t13); access_mode W_OK line removed (t24); ExistsFile `!(st isa Int) && isfile(st)` -> `!(st isa Int)` (t68); ExistsDirectory likewise (t84);
   DeRefLink `n = 20` -> `n = 1` (t57); `(st1 isa Int || st2 isa Int) && return false` removed (t114); get_file_name `PL_error(ld, ERR_EXISTENCE, mk_sym(T, :file), n)` -> :directory (t5);
   access_file `_is_atom_named(m, T, :none) && return FTRUE` removed (t28); `|| _is_atom_named(m, T, :search)` dropped (NEW ROW access_file(lk_lb2b_dir, search)); `if md == ACCESS_WRITE && !AccessFile(n, ACCESS_EXIST)` -> `if md == ACCESS_WRITE` (t30);
   `ExistsDirectory(dir) || return FFALSE` removed (t45); file_name_extension `startswith(e, '.') && (e = e[2:end])` removed (t153); has_extension `truePrologFlag(ld, PLFLAG_FILE_CASE) && return rest == e` -> `return true` (t156);
   delete_directory `mk_sym(T, :delete), mk_sym(T, :directory), A1` -> :remove (t364); `if SameFile(ld, o, n)` in rename_file -> `if false` (t378); mkdir mode `_mkdir(n, 0o777)` -> 0o000 (NEW MUTATING ROW: make_directory(lk_lb2b_n4), access_file(lk_lb2b_n4, write));
   file_name_is_iri `s - 1 >= 2 && s + 2 <= n` -> `s - 1 >= 1` (refusal testset: exists_file('a://x'), ACTUALLY check the anchor, 1 occurrence).
   pl-os.jl: BaseName `stop == e && b[e + 1] == UInt8('/') && return "/"` removed (t122); DirName `e == 0 && return b[1] == UInt8('/') ? "/" : "."` -> `"."` (t139,t142); AbsoluteFile `IsAbsolutePath(file) && return canonicalisePath(ld, file)` removed (t202);
   PL_cwd `cwd = buf * "/"` -> `cwd = buf` (t215); ChDir `endswith(tmp, '/') || (tmp *= "/")` removed (t219); ChDir `gd === nothing || (gd.paths_CWDdir = tmp)` -> `nothing` (t220, the logical cwd of a symlink).
   Equivalents: pl-files.jl has_extension line 1 `isempty(ext) && return true` makes `|| isempty(e)` in pl_file_name_extension3_va redundant (remove that `|| isempty(e)`); SameFile `&& st1.device == st2.device` (all fixtures on one device).
   TARGETS (D-0238): test/files/test_lb2b_swipl.jl first; the mutated code shared with other tests also lists: get_file_name/PL_get_file_name/AbsoluteFile/canonicalise*/file_name_is_iri -> test/core_lang/test_sys_swipl.jl (delete_file),
   test/files/test_open_close_swipl.jl, test/files/test_load_swipl.jl (the last grep, `grep -n -F` of the callers over named src files, was not run: the cap ended the session; do it first).
   Validate with a throwaway python3 -I + runpy checker in the private scratchpad (old once, new != old, ids unique, targets exist).
2. test/test_type_discipline.jl allowlist: `"os/pl-files.jl ccall"` 1 -> 9 (ccalls: remove, access, readlink, rename, umask, chmod, rmdir, mkdir, getuid; count them with grep -c before editing), `"os/pl-os.jl ccall"` stays 3 (verify); own commit.
3. test/static_analysis_manifest.jl appended block (new functions of pl-files.jl, pl-os.jl, pl-glob.jl incl. PL_predicates_from_glob's `_extension_sigs` line), then docs/architecture.md appended block: the LAST two commits.

## OLD notes of the G4-G8 decisions (the groups above are written; kept for the record)
- G4 pl-files.jl helpers (pl-files.c:36-420). DECIDED, not yet written: stat is `Base.stat` wrapped as
  `statfunc(path)::Union{StatStruct,Int}` (Int = -ioerrno on failure, catch `Base.IOError` whose `.code` is the negative errno);
  `LastModifiedFile`/`SizeFile` return `(value, errno)` tuples (errno 0 = ok; mtime is Julia's `sec + nsec*1e-9`, upstream `sec + nsec/1.0e9`: log as
  representation DIVERGES); ExistsFile = `isfile(st)`, ExistsDirectory = `isdir(st)`; libc ccalls (`LIBC` const, like RemoveFile) for
  access, readlink, rename, chmod, mkdir, rmdir, umask, getuid. ACCESS_READ/WRITE/EXECUTE/EXIST/FILE/DIRECTORY are pl-os.h/pl-incl.h
  constants: find the values with `git -C ~/dev-zone/swipl-devel grep -n "ACCESS_EXIST" cbf4e1896275 -- src/os src/pl-incl.h` (the grep of `define ACCESS_*` over
  `src` was the call the cap hook stopped; the Julia tree has no ACCESS_* constants yet; PL_FILE_* are in src/SWI-Prolog.jl:367-388).
  Also AccessDirectory, ReadLink, DeRefLink1/DeRefLink (20-link loop, permission_error dereference/symlink), SameFile (PLFLAG_FILE_CASE via truePrologFlag, st_ino/st_dev), RenameFile, MarkExecutable.
- G5 get_file_name flags (pl-files.c:423-540): replace the `unported` refusal in src/os/pl-files.jl `get_file_name` for ABSOLUTE, OSPATH, EXIST/READ/WRITE/EXECUTE,
  keep PL_FILE_SEARCH refused by name (Prolog `system:absolute_file_name/3`, left to LB4); expandVars under PLFLAG_FILEVARS; the `existence_error(file, N)` / `permission_error(Op, file, N)` checks.
- G6, G7, G8 (tmp_file; decide after reading pl-os.c:700-860, TemporaryFile + registry; `$tmp_file_stream` needs Sfdopen: refuse by name if the stream layer has none), G9-G12 as in the plan.
- `PL_predicates_from_files` (end of pl-files.jl) must end up in upstream's BeginPredDefs order (pl-files.c:1200-1224); delete_file/1 is the one entry now. `PL_predicates_from_glob`
  goes after `_files` in `_PRED_TABLES` and `_FOREIGN_VA` (src/pl-ext.jl:57-84); upstream's REG_PLIST order is file, files, glob, btree, ctype ... (pl-ext.c:518-520).
- test/test_type_discipline.jl `_TD_UNCHECKED_ALLOWED`: "os/pl-files.jl ccall" (now 1) gains one count per ccall added; "os/pl-os.jl ccall" stays 3 (G2/G3 added none: pwd() and cd() are Base); a shared file, change its count in its own late commit.
- Julia API facts checked (for the next agent): atoms are `mk_sym(T, Symbol(str))`; `PL_unify_atom(ld, t, atom)`; errors `PL_error(ld, ERR_REPRESENTATION, mk_sym(T,:max_path_length))`,
  `PL_error(ld, ERR_EXISTENCE, atom, term)`, `PL_error(ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, action, type, file_term, errno::Int)` (errno is an ARGUMENT),
  texts via `PL_get_text(ld, t, CVT_ALL|CVT_EXCEPTION)` then `text_string`; the database in a built-in is `ld.GD` (may be `nothing`); `truePrologFlag(ld, PLFLAG_*)`
  (FILE_CASE=9, FILEVARS=15, FILEERRORS=23 in src/pl-incl.jl); `NotPortedError{T}(culprit, what, step)`.

## UNVERIFIED (nothing is compiled)
Everything.

## Flags for the audit
1. G1 edits src/pl-global.jl (one appended field + constructor arg): needed so `$cwd`/`$chdir` keep upstream's cached logical path (a symlinked cwd stays logical).
   Option B (undecided): drop the cache and ask the OS each time (behaviour-changing for a symlinked cwd). Recommendation: keep the field.
2. src/os/pl-os.jl (an existing file, also Y1's) gets an appended block: the plan said new files; pl-os.c's functions belong there.
3. `expandVars`: `~user` refused by name (getpwnam); HOME not cached (upstream caches in GD->os.myhome): representation-only unless HOME changes after the first expansion.
4. `utf8_path_lwr` uses `lowercase(::Char)` for `PL_tolower` (pl-umap.c): only on a case-insensitive file_name_case_handling (not the Linux default).
5. PL_cwd with `ld.GD === nothing` has no cache (outside a query).
6. (G8) tmp_file/2 and `$tmp_file_stream`/4 raise NotPortedError: need a PL_global_data field `os_tmp_files` (struct change, alloc pins) and Sfdopen. Undecided: audit.
7. (G6) IRI arguments (file_name_is_iri != 0) of time_file, size_file, access_file, exists_file, exists_directory raise NotPortedError (iri_hook calls Prolog, LB4).
8. (G7) `$chdir`: when ChDir returns -1 (AbsoluteFile failed, error already raised) the predicate fails; upstream raises ERR_FILE_OPERATION over a stale errno.
9. (G10) `expand` and `directory_files` put `.` and `..` first then `readdir(sort=false)` (libuv omits them); expand skips unreadable dirs and invalid-UTF-8 names.
10. UNVERIFIED hot spots for the first compile: `Base.Filesystem.StatStruct` name, `stat` errors (ENOENT/ENOTDIR/EINVAL come as a field, others as IOError), ccall `readlink`
   return type `Int`, `_umask(um)` Cuint, `PL_scan_options(...)[1] !== false`, `PL_error(ld, "", 0, "", ERR_SYNTAX, String)`, `Int(PL_FILE_READ | PL_FILE_OSPATH)`.
12. (G8, restated) tmp_file needs a PL_global_data field `os_tmp_files` and Sfdopen in the stream layer: a second struct change; the audit's call. Flags 1-11 stay undecided.
11. Hook notes: the recursive-grep hook blocked one `grep -rn ... src` (no escape used); no allow-* escape used anywhere.

## GATE ORDER (the gate agent)
Tier 2 plus a struct change (G1): alloc pins x3. In order: fmt via `warm.sh send` (committed files); inventory; `check`; test/files/test_lb2b_swipl.jl on all three term types; test/test_type_discipline.jl;
`tools/pkgtest_way.sh test/files/test_lb2b_swipl.jl` (one at a time); push `mutants/LB2B` at the WIP SHA; branch-gate; term grep (D-0164); alloc pins x3; gate push `gate/lb2b` and `mutants/LB2B` at the SAME SHA.
