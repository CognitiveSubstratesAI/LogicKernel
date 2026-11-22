# ORIGINAL: W12-TMPFILES's mutant list — no swipl-devel counterpart.
# tools/mutants/W12TMP.py — the mutation battery of W12-TMPFILES (the PIN's temporary-file registry: os/pl-os.c tmp_dir,
# verify_tmp_dir, TemporaryFile, free_tmp_name, DeleteTemporaryFile, RemoveTemporaryFiles; os/pl-stream.c Sfdopen;
# os/pl-files.c tmp_file/2, $tmp_file_stream/4, delete_file/1's registry-first call; PL_cleanup's RemoveTemporaryFiles), run ONCE,
# in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` (file:line reason) and `targets`. The rows are the tNN of
# test/files/test_tmp_files_swipl.pl (t0-t16, t20-t31, t99) and the white-box testsets of test/files/test_tmp_files_swipl.jl.
# Verdicts: written by the battery, not yet run. Every `old` was counted (python3 str.count, a text count, no Julia run) at wip/w12-tmpfiles
# before this file was written (and again, replayed onto main at the pin 18168e62 as wip/tmpfile-replay: 34 of 34 once, new != old, every target
# file exists; the test files that call PL_cleanup/PL_halt (test_top1_pro.jl, test_wr2_swipl.jl) joined TH): RE-FIT any that `tools/warm.sh fmt` rewraps (mutate_drive.py refuses a string that does not occur
# exactly once).
# NOT LISTED: the printMessage warning of verify_tmp_dir (it goes to stderr, no row sees it); the close(file) of a failed unify and
# of a failed Sfdopen in $tmp_file_stream/4 (a descriptor leak no test sees); the errno return of a non-EEXIST open failure.
# W12TMP-O8 (0o600 -> 0o666) is killed only under a umask that clears group/other write bits (the usual 022: 0644 != 0600); a
# umask of 0 would leave it alive: note it if the battery's runner sets one.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. Only test_tmp_files_swipl.jl names the
# registry; delete_file/1 and get_file_name are shared with test_lb2b_swipl.jl, test_sys_swipl.jl and test_open_close_swipl.jl
# (TD); PL_cleanup is shared with the halt and first-boot files (TH).
TL = ["test/files/test_tmp_files_swipl.jl"]
TD = TL + [
    "test/files/test_lb2b_swipl.jl", "test/core_lang/test_sys_swipl.jl", "test/files/test_open_close_swipl.jl",
]                                                                                   # delete_file / get_file_name
TH = TL + [
    "test/core_lang/test_halt_swipl.jl", "test/core_lang/test_firstboot_swipl.jl", "test/core_lang/test_top1_pro.jl",
    "test/core_text/test_wr2_swipl.jl",
]                                                                                   # PL_cleanup
TARGETS = TD + TH[1:]                                                              # the baseline's (mutate_ci.py plan reads TARGETS)
O = "src/os/pl-os.jl"
S = "src/os/pl-stream.jl"
F = "src/os/pl-files.jl"
I = "src/pl-init.jl"
MUTANTS = [
    # ── pl-os.c tmp_dir, verify_tmp_dir ──
    dict(id="W12TMP-O1 tmp_dir ignores the flag: always SWIPL_TMP_DIR (KILL t14: the flag moves the directory)", file=O, targets=TL,
         old="        return SWIPL_TMP_DIR\n    return sym_text(a)\n",
         new="        return SWIPL_TMP_DIR\n    return SWIPL_TMP_DIR\n"),
    dict(id="W12TMP-O2 verify_tmp_dir accepts a missing directory: no warning, no error (KILL t15)", file=O, targets=TL,
         old="    ExistsDirectory(tmpdir) && return true\n",
         new="    return true\n"),
    dict(id="W12TMP-O3 TemporaryFile goes on after an invalid tmp_dir (KILL t15)", file=O, targets=TL,
         old="verify_tmp_dir(ld, tmpdir) || return ENOENT",
         new="verify_tmp_dir(ld, tmpdir) || nothing"),
    # ── pl-os.c TemporaryFile ──
    dict(id="W12TMP-O4 the counter steps by two (KILL the counter+1 shape rows)", file=O, targets=TL,
         old="gd.os_temp_counter += 1",
         new="gd.os_temp_counter += 2"),
    dict(id="W12TMP-O5 a base is always followed by an underscore: `swipl__<pid>_<n>` for no base (KILL t22, t23: no base)", file=O, targets=TL,
         old="sep = isempty(id) ? \"\" : \"_\"",
         new="sep = \"_\""),
    dict(id="W12TMP-O6 the extension always has a dot: `swipl_<pid>_<n>.` for none (KILL t0-t7: the shape check)", file=O, targets=TL,
         old="esep = isempty(ext) ? \"\" : \".\"",
         new="esep = \".\""),
    dict(id="W12TMP-O7 the process id of the name is 0 (KILL t0, t20: the pid of the name)", file=O, targets=TL,
         old="Libc.getpid(), \"_\", tmpid",
         new="0, \"_\", tmpid"),
    dict(id="W12TMP-O8 the file is created with mode 0666, not 0600 (KILL the 0600 white-box; see the header on umask)", file=O, targets=TL,
         old="0o600",
         new="0o666"),
    dict(id="W12TMP-O9 the PATH_MAX boundary is exclusive: a name of 4096 bytes is accepted (KILL t16, the white-box boundary)", file=O, targets=TL,
         old="ncodeunits(temp) >= PATH_MAX && return ENAMETOOLONG",
         new="ncodeunits(temp) > PATH_MAX && return ENAMETOOLONG"),
    dict(id="W12TMP-O10 the file is created without O_EXCL: an existing name is truncated and reused (KILL the EEXIST retry white-box)", file=O, targets=TL,
         old="Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_EXCL |",
         new="Base.Filesystem.JL_O_CREAT | 0 |"),
    dict(id="W12TMP-O11 the file is opened read-only (KILL t20, t21: write to the stream)", file=O, targets=TL,
         old="Base.Filesystem.JL_O_WRONLY,",
         new="Base.Filesystem.JL_O_RDONLY,"),
    dict(id="W12TMP-O12 an EEXIST is an error, not a retry (KILL the EEXIST retry white-box)", file=O, targets=TL,
         old="-e.code == EEXIST && continue",
         new="false && continue"),
    dict(id="W12TMP-O13 the new name is not entered in the registry (KILL t12, t13; the registry white-box; t99 and the halt check)", file=O, targets=TD,
         old="push!(gd.os_tmp_files, temp)",
         new="nothing"),
    # ── pl-os.c free_tmp_name, DeleteTemporaryFile, RemoveTemporaryFiles ──
    dict(id="W12TMP-O14 free_tmp_name answers the inverse: a removed file is a failure (KILL t12, t13)", file=O, targets=TD,
         old="RemoveFile(name) == 0",
         new="RemoveFile(name) != 0"),
    dict(id="W12TMP-O15 DeleteTemporaryFile deletes any name, registered or not (KILL the white-box: a plain file's name is no registry entry)", file=O, targets=TD,
         old="    name in gd.os_tmp_files || return false\n",
         new=""),
    dict(id="W12TMP-O16 DeleteTemporaryFile keeps the name in the registry (KILL the `no swipl_lk_del_ name left` check)", file=O, targets=TD,
         old="    delete!(gd.os_tmp_files, name)\n",
         new=""),
    dict(id="W12TMP-O17 RemoveTemporaryFiles leaves the registry filled (KILL the registry-after-cleanup check)", file=O, targets=TH,
         old="    empty!(gd.os_tmp_files)\n",
         new=""),
    dict(id="W12TMP-O18 RemoveTemporaryFiles removes nothing (KILL t99, the halt check and the cleanup white-box)", file=O, targets=TH,
         old="        free_tmp_name(name)\n",
         new="        nothing\n"),
    # ── pl-stream.c Sfdopen ──
    dict(id="W12TMP-S1 Sfdopen takes a negative descriptor (KILL the Sfdopen white-box: EINVAL for -1)", file=S, targets=TL,
         old="    fd < 0 && return (nothing, EINVAL)\n",
         new="    false && return (nothing, EINVAL)\n"),
    dict(id="W12TMP-S2 Sfdopen does not check that the descriptor is open (KILL the Sfdopen white-box: EBADF for a closed one)", file=S, targets=TL,
         old="        stat(RawFD(fd))\n",
         new="        nothing\n"),
    dict(id="W12TMP-S3 a binary stream is a text stream too (KILL t21)", file=S, targets=TL,
         old="(length(type) < 2 || type[2] != 'b') && (flags |= SIO_TEXT)",
         new="flags |= SIO_TEXT"),
    dict(id="W12TMP-S4 the stream does not own the descriptor (KILL the descriptor-closed check after close/1)", file=S, targets=TL,
         old="Base.fdio(\"<fd $fd>\", fd, true), true)",
         new="Base.fdio(\"<fd $fd>\", fd, false), true)"),
    dict(id="W12TMP-S5 type `r` makes an output stream (KILL the Sfdopen white-box: read mode)", file=S, targets=TL,
         old="    if c == 'r'\n        flags |= SIO_INPUT\n",
         new="    if c == 'r'\n        flags |= SIO_OUTPUT\n"),
    # ── pl-files.c tmp_file/2, $tmp_file_stream/4, delete_file/1 ──
    dict(id="W12TMP-F1 tmp_file/2 creates the file (KILL t1: the file is not created by tmp_file/2)", file=F, targets=TD,
         old="TemporaryFile(ld, text_string(txt), \"\", false)",
         new="TemporaryFile(ld, text_string(txt), \"\", true)"),
    dict(id="W12TMP-F2 $tmp_file_stream/4 does not create the file (KILL t20: the file exists after the call)", file=F, targets=TD,
         old="TemporaryFile(ld, \"\", ext, true)",
         new="TemporaryFile(ld, \"\", ext, false)"),
    dict(id="W12TMP-F3 the stream is opened for reading (KILL t20, t21)", file=F, targets=TD,
         old="    mode = \"w\"\n",
         new="    mode = \"r\"\n"),
    dict(id="W12TMP-F4 the binary stream is a text stream (KILL t21: stream_property type)", file=F, targets=TD,
         old="mode = \"wb\"",
         new="mode = \"w\""),
    dict(id="W12TMP-F5 tmp_file/2's file error names another type (KILL t15: existence_error formal)", file=F, targets=TD,
         old="mk_sym(T, :temporary_file), base, r",
         new="mk_sym(T, :tmp_file), base, r"),
    dict(id="W12TMP-F6 $tmp_file_stream/4's file error names another type (KILL the white-box invalid tmp_dir call of $tmp_file_stream/4)", file=F, targets=TD,
         old="mk_sym(T, :temporary_file), A1, r",
         new="mk_sym(T, :tmp_file), A1, r"),
    dict(id="W12TMP-F7 delete_file/1 skips the registry (KILL t12, t13: the name stays in the registry)", file=F, targets=TD,
         old="DeleteTemporaryFile(_query_gd(ld), sym_text(aname)) && return FTRUE",
         new="false && return FTRUE"),
    dict(id="W12TMP-F8 the uninstantiation error names argument 2 (KILL t31)", file=F, targets=TD,
         old="ERR_UNINSTANTIATION, 3, A3",
         new="ERR_UNINSTANTIATION, 2, A3"),
    dict(id="W12TMP-F9 the domain error names the wrong type (KILL t26, t30)", file=F, targets=TD,
         old="mk_sym(T, :encoding), A2)",
         new="mk_sym(T, :enc), A2)"),
    dict(id="W12TMP-F10 the stream keeps its default encoding (KILL t20, t23, t24: stream_property encoding)", file=F, targets=TD,
         old="    Ssetenc(s, enc)\n",
         new="    nothing\n"),
    # ── pl-init.jl PL_cleanup ──
    dict(id="W12TMP-I1 PL_cleanup does not remove the temporary files (KILL t99, the halt check, the PL_cleanup white-box)", file=I, targets=TH,
         old="    RemoveTemporaryFiles(gd) ",
         new="    nothing "),
]
