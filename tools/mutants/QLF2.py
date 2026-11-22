# ORIGINAL: QLF2's mutant list — the counterpart is pl-qlf.c (qlfInfo files0 block, qlfSourceInfo, qlfFixSourcePath,
# pushPathTranslation, popPathTranslation, qlfGet4BytesInt, qlfGetString) at the pin 18168e62.
# tools/mutants/QLF2.py — the mutation battery of QLF2 row 10 (`'$qlf_sources'/2`), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate_ci.py one). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Every mutant is killed by a named testset of test/files/test_qlf_swipl.jl:
#   * SRC = the testset "'$qlf_sources'/2 lists the sources a QLF file records" (three entries, the hash above Int64, the empty
#     index, version 68, the bound lists, the errors, the too-long name);
#   * MOV = the testset "'$qlf_sources'/2 of a QLF file that has moved" (the translated paths, the order of the
#     `$translated_source/2` calls, the shared directory tail of its last rows).
# NOT LISTED (each with its reason):
#   * `absloadname != abssavename` of pushPathTranslation: with equal names the scan strips both directories to `/`, whose
#     prefix test and rewrite give every path back unchanged, so the answer and the recorded rewrites are the same;
#   * `ls.has_moved &&` in qlfFixSourcePath: with no move `save_dir` is the empty string, a prefix of everything, and the tail
#     is the whole path (same answer);
#   * `Sseek64(...) < 0` of the index seek (`seek to index failed`): a QLF file that got past the header check is longer than
#     4 bytes, so no row reaches that error; the PATH_ISDIR branch (`flags` is 0 from every caller) and the `qlfGetString`
#     `length != NULL` form (left to the XR reader, QLF3) have no caller yet;
#   * the `fatalError` of an end of file inside a name and of a name above PATH_MAX after a move: no row builds them.
# TARGETS (audit D-0238): the code is reached by `'$qlf_sources'/2` (`qlfInfo`'s Q_VERSION and compatibility branches are
# the other callers and share the same file); test_qlf_stale_swipl.jl calls it too (`'$qlf_out_of_date'/3`, qlf_needs_rebuild/1,
# a real qcompile'd file's index, the version bytes of the header), so both files are the list.
TARGETS = ["test/files/test_qlf_swipl.jl", "test/files/test_qlf_stale_swipl.jl"]
T = TARGETS
Q = "src/pl-qlf.jl"
F = "src/pl-fli.jl"
MUTANTS = [
    # ---- the four byte index entries and the count at the end of the file
    dict(id="QLF2-1 qlfGet4BytesInt shifts the first byte by 16: a count of 0xffffffff reads as 0xffffff, not -1 (KILL SRC: the negcount row's message)",
         file=Q, targets=T,
         old="v = (Sgetc(s) & 0xff) << 24",
         new="v = (Sgetc(s) & 0xff) << 16"),
    dict(id="QLF2-2 qlfGet4BytesInt keeps the low 31 bits: the sign is lost, a negative count is a huge one (KILL SRC: the negcount row)",
         file=Q, targets=T,
         old="return v % Int32",
         new="return Int32(v & 0x7fffffff)"),
    dict(id="QLF2-3 an index of no entries is refused: `nqlf < 0` becomes `nqlf <= 0` (KILL SRC: the empty row, `[]` and the bound `[]`)",
         file=Q, targets=T,
         old="if nqlf < 0",
         new="if nqlf <= 0"),
    dict(id="QLF2-4 the seek to the index counts one entry too few: `-4 * nqlf` for `-4 * (nqlf + 1)` (KILL SRC: the three-entry row reads the wrong offsets)",
         file=Q, targets=T,
         old="Int64(-4) * (Int64(nqlf) + 1)",
         new="Int64(-4) * Int64(nqlf)"),
    dict(id="QLF2-5 the count is read three bytes from the end, not four (KILL SRC: every row with an index)",
         file=Q, targets=T,
         old="if Sseek64(s, Int64(-4), SIO_SEEK_END) < 0",
         new="if Sseek64(s, Int64(-3), SIO_SEEK_END) < 0"),
    dict(id="QLF2-6 a failed seek to the index entries is not an error (`> 0` for `< 0`): the garbage offset's own error comes instead (KILL SRC: the short row's message)",
         file=Q, targets=T,
         old="if Sseek64(s, Int64(-4) * (Int64(nqlf) + 1), SIO_SEEK_END) < 0",
         new="if Sseek64(s, Int64(-4) * (Int64(nqlf) + 1), SIO_SEEK_END) > 0"),
    # ---- qlfSourceInfo
    dict(id="QLF2-7 the seek to an entry counts a success as the failure (`== 0` for `!= 0`) (KILL SRC: every row with an entry)",
         file=Q, targets=T,
         old="if Sseek64(s, Int64(offset), SIO_SEEK_SET) != 0",
         new="if Sseek64(s, Int64(offset), SIO_SEEK_SET) == 0"),
    dict(id="QLF2-8 an `F` entry is an include (KILL SRC: the three-entry row's functors, the version-68 row)",
         file=Q, targets=T,
         old="type = :source",
         new="type = :include"),
    dict(id="QLF2-9 a `D` entry is not a kind: \"No file at offset\" (KILL SRC: the three-entry row's dependency)",
         file=Q, targets=T,
         old="c == Int('D')",
         new="c == Int('X')"),
    dict(id="QLF2-10 the hash is read since version 73, not 72 (KILL SRC: the three-entry row, version 72 with a hash)",
         file=Q, targets=T,
         old="if state.saved_version >= 72",
         new="if state.saved_version > 72"),
    dict(id="QLF2-11 the hash is the absolute value of the signed integer, not its bits (KILL SRC: the hash above Int64 of the second entry)",
         file=Q, targets=T,
         old="return reinterpret(UInt64, qlfGetInt64(state.wicFd::IOSTREAM))",
         new="return UInt64(abs(qlfGetInt64(state.wicFd::IOSTREAM)))"),
    dict(id="QLF2-12 PL_put_uint64 puts a hash above Int64 as the negative signed integer (KILL SRC: the second entry's 9223372036854775813)",
         file=F, targets=T,
         old="""    PL_put_variable(ld, t)
    return PL_unify_uint64(ld, t, i)""",
         new="""    PL_put_variable(ld, t)
    return PL_put_int64(ld, t, reinterpret(Int64, i))"""),
    dict(id="QLF2-13 a file name above 2 * PATH_MAX is the first to be refused: 5000 bytes run into the end of the file (KILL SRC: the too-long row's message)",
         file=Q, targets=T,
         old="(len < 0 || len > PATH_MAX)",
         new="(len < 0 || len > 2 * PATH_MAX)"),
    dict(id="QLF2-14 the list is unified with the entry as a tail on the temporary (`tmp` for `list`): the second entry meets the first's cell (KILL SRC: the three-entry row, the bound-list rows)",
         file=Q, targets=T,
         old="PL_unify_list(ld, list, head, list) &&",
         new="PL_unify_list(ld, list, head, tmp) &&"),
    dict(id="QLF2-15 the list is not closed: the answer is a partial list (KILL SRC: the three-entry row; the bound `right` list and `[]` of the empty file)",
         file=Q, targets=T,
         old="return PL_unify_nil(ld, files)",
         new="return true"),
    # ---- the path translation
    dict(id="QLF2-16 a moved file is not marked moved: no path is rewritten (KILL MOV: the first row)",
         file=Q, targets=T,
         old="new.has_moved = true",
         new="new.has_moved = false"),
    dict(id="QLF2-17 every path is rewritten, whatever its prefix (`has_moved` alone): /elsewhere/b.pl loses its first bytes (KILL MOV)",
         file=Q, targets=T,
         old="if ls.has_moved && startswith(raw, ls.save_dir)",
         new="if ls.has_moved"),
    dict(id="QLF2-18 the tail after the saved directory starts one byte late (KILL MOV: /old/place#/x/a.pl becomes <dir>x/a.pl)",
         file=Q, targets=T,
         old="[(ncodeunits(ls.save_dir) + 1):end]",
         new="[(ncodeunits(ls.save_dir) + 2):end]"),
    dict(id="QLF2-19 every path is recorded as rewritten, even when it was not (KILL MOV: `/elsewhere/b.pl`, `/keep/d.pl` in tr_seen)",
         file=Q, targets=T,
         old="if raw != canonical",
         new="if true"),
    dict(id="QLF2-20 the rewrites are told oldest first (KILL MOV: tr_seen's order, newest first)",
         file=Q, targets=T,
         old="for (from, to) in Iterators.reverse(old.translated)",
         new="for (from, to) in old.translated"),
    dict(id="QLF2-21 popPathTranslation tells nothing (KILL MOV: tr_seen stays empty)",
         file=Q, targets=T,
         old="if old.has_moved && !isempty(old.translated)",
         new="if false"),
    dict(id="QLF2-22 qlfInfo does not pop the translation after a Q_FILES run (KILL MOV: tr_seen stays empty)",
         file=Q, targets=T,
         old="(flags & (Q_MODULE | Q_FILES)) != 0 && popPathTranslation(ld, state)",      # since QLF3 the guard also names Q_MODULE
         new="(flags & Q_MODULE) != 0 && popPathTranslation(ld, state)"),
    dict(id="QLF2-23 the scan of the common directory tail never runs: the whole directories are replaced (KILL MOV: the shared-tail rows, /old#/place/other/b.pl)",
         file=Q, targets=T,
         old="while le > 0 && se > 0 && l[le] == s[se]",
         new="while false && le > 0 && se > 0 && l[le] == s[se]"),
    dict(id="QLF2-24 the common tail is not cut at its first `/`: the directories keep `place/sub` (KILL MOV: the shared-tail rows)",
         file=Q, targets=T,
         old="if l[le] == UInt8('/')",
         new="if false"),
    dict(id="QLF2-25 only the load directory is cut at the `/`, the saved one keeps its tail (KILL MOV: /old#/place/sub/a.pl becomes <dir>/a.pl, not <dir>/place/sub/a.pl)",
         file=Q, targets=T,
         old="resize!(s, se)",
         new="se = se"),
]
