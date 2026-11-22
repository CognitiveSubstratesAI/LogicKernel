# ORIGINAL: RD2a's mutant list: the comments collector, eof_action(error) at raw_read2 and the comment hook of read_clause/3 in src/pl-read.jl; no swipl-devel counterpart.
# tools/mutants/RD2a.py — the mutation battery of RD2a (pl-read.c add_comment, raw_read2's comment branches and its past-the-end error,
# callCommentHook, read_clause's comments/process_comment wiring, read_term_from_stream's comments option). The replay of wip/rd2 (5238d5e2..51dfb8fd)
# onto origin/main had NO mutant list of its own: this one is written at the replay, NOTHING WAS RUN, every kill is read off the pinned rows of
# test/core_text/test_read_comments_swipl.jl (rc01-rc21 comments(C) of read_term/3, rc30-rc36 eof_action(error), rc40-rc50 var_prefix, rc60-rc68 read_clause/3,
# rh01-rh11 the hook prolog:comment_hook/4). The CI battery is the verdict; a survivor is killed by a new row or recorded EQUIVALENT with its code reason.
# Format: tools/mutate_drive.py's (as RD2.py): `id`, `file`, `old` (EXACTLY once in `file`), `new` != `old`, optional `equivalent` and `targets`.
# TARGETS (audit D-0238): every test file that runs the mutated code: the comments file (the kill rows), test_read_term_swipl.jl (read_term/2,3 options),
# test_read_stream_swipl.jl (the stream reads and eof_action), test_read_positions_swipl.jl (term_position / subterm_positions through the same reads) and
# test_canonical_readatom_swipl.jl (term_to_atom and read_term_from_atom, which run raw_read2 on a string stream).
# Every `old` is counted exactly once by `python3 -I ~/code/lk-t27-scratch/oldscan.py RD2a` (from the repository root). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
RC = "test/core_text/test_read_comments_swipl.jl"
RT = "test/core_text/test_read_term_swipl.jl"
RS = "test/core_text/test_read_stream_swipl.jl"
RP = "test/core_text/test_read_positions_swipl.jl"
CR = "test/core_text/test_canonical_readatom_swipl.jl"
ALL = [RC, RT, RS, RP, CR]
TARGETS = ALL                                # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
R = "src/pl-read.jl"


def m(id, old, new, targets=ALL, file=R, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- add_comment
    m("RD2a-C1 add_comment: the position's character offset and line are swapped (KILL RC rc01, rc10, rc21, rc63: the `$stream_position(Char,Line,...)` of the comment)",
      "(Int64(pos.charno), Int64(pos.lineno), Int64(pos.linepos), Int64(0)), ()",
      "(Int64(pos.lineno), Int64(pos.charno), Int64(pos.linepos), Int64(0)), ()"),
    m("RD2a-C2 add_comment: a stream without positions heads the pair with another atom than `-` (KILL RC rc11, rc12, rc67)",
      "PL_put_atom(ld, m, mk_sym(T, :-))           # PL_ATOM, ATOM_minus",
      "PL_put_atom(ld, m, mk_sym(T, :nil))         # PL_ATOM, ATOM_minus"),
    m("RD2a-C3 add_comment: the list of comments is not extended (the unify is a no-op test) (KILL RC rc01, rc02, rc05, rc20: the list stays [])",
      "PL_unify_list(ld, rd.comments, head, rd.comments) || return false",
      "PL_unify_list(ld, rd.comments, head, head) || return false"),
    # ---- raw_read2: block comments
    m("RD2a-B1 raw_read2: a block comment is collected only when no comments are asked for (KILL RC rc01, rc05, rc06, rc09, rc21)",
      "collecting = rd.comments != 0          # cbuf != NULL",
      "collecting = rd.comments == 0          # cbuf != NULL"),
    m("RD2a-B2 raw_read2: the collected block comment misses its opening `*` (KILL RC rc01: `/ a */`, rc06, rc09)",
      "                    utf8_put_char(cbuf, Int('/'))\n                    utf8_put_char(cbuf, Int('*'))\n",
      "                    utf8_put_char(cbuf, Int('/'))\n"),
    m("RD2a-B3 raw_read2: a nested block comment does not count its level (KILL RC rc06: the comment ends at the first `*/`, `c */ g.` is a syntax error)",
      "last == Int('/') && (level += 1)",
      "last == Int('/') && (level += 0)"),
    m("RD2a-B4 raw_read2: the text of a block comment loses its last character before `*/` (KILL RC rc01: ` a ` loses a blank; rc05, rc09)",
      "collecting && c != EOF && utf8_put_char(cbuf, c)   # (EOF: the buffer is discarded)",
      "collecting && c != EOF && c != Int('/') && utf8_put_char(cbuf, c)   # (EOF: the buffer is discarded)"),
    # ---- raw_read2: line comments
    m("RD2a-L1 raw_read2: a run of %-lines is no longer ONE comment (KILL RC rc03, rc12: [`% a\\n% b`] becomes two comments; rc04 is the control with a gap)",
      "if c2 == Int('%')           # a run of %-lines is one comment",
      "if c2 != Int('%')           # a run of %-lines is one comment"),
    m("RD2a-L2 raw_read2: a %-comment is collected only without a comments option (KILL RC rc02, rc07, rc08, rc11)",
      "            something_read && addToBuffer(Int(' '), rd)\n            if rd.comments != 0\n",
      "            something_read && addToBuffer(Int(' '), rd)\n            if rd.comments == 0\n"),
    # ---- raw_read2: eof_action(error)
    m("RD2a-E1 raw_read2: reading past the end of a stream is not an error (KILL RC rc30, rc31, rc32, rc34, rc35: the second read must raise permission_error)",
      "            if Sfpasteof(s) != 0\n                ld = rd.ld",
      "            if Sfpasteof(s) < 0\n                ld = rd.ld"),
    m("RD2a-E2 raw_read2: the error names another action than past_end_of_stream (KILL RC rc31, rc32, rc34, rc35)",
      "ld, \"\", 0, \"\", ERR_PERMISSION, mk_sym(T, :input),\n                    mk_sym(T, :past_end_of_stream), stream",
      "ld, \"\", 0, \"\", ERR_PERMISSION, mk_sym(T, :input),\n                    mk_sym(T, :end_of_stream), stream"),
    m("RD2a-E3 raw_read2: the error's culprit is not the stream (KILL RC rc31, rc32: the third argument of the context is a fresh variable)",
      "PL_unify_stream_or_alias(ld, stream, s)\n                PL_error(",
      "PL_error("),
    # ---- read_term_from_stream, read_clause
    m("RD2a-T1 read_term_from_stream: a comments(C) that cannot unify with the list is ignored (KILL RC rc13, rc14: comments(foo) makes the read fail)",
      "            PL_unify_nil(ld, rd.comments) || (rval = false)\n",
      "            PL_unify_nil(ld, rd.comments)\n"),
    m("RD2a-T2 read_term_from_stream: the comments option is not handed to the read (KILL RC rc01, rc02, rc05, rc20, rc21: C stays [])",
      "    tcomments != 0 && (rd.comments = PL_copy_term_ref(ld, tcomments))\n    rd.subtpos",
      "    tcomments != 0 && (rd.comments = 0)\n    rd.subtpos"),
    m("RD2a-T3 read_clause: process_comment(true) is taken as false (KILL RC rh01, rh02, rh03, rc64, rc68: the hook is never called)",
      "        elseif process_comment\n            tpos == 0",
      "        elseif !process_comment\n            tpos == 0"),
    m("RD2a-T4 read_clause: the hook is called when the comment list is EMPTY (KILL RC rh01.., rc65: `elseif !PL_get_nil`)",
      "elseif !PL_get_nil(ld, comments)",
      "elseif PL_get_nil(ld, comments)"),
    m("RD2a-T5 read_clause: the comments option's variable is not unified with the collected list (KILL RC rc60, rc63, rc65, rc66, rc67)",
      "rval = PL_unify(ld, opt_comments, comments)",
      "rval = true"),
    m("RD2a-T6 read_clause: the hook's exception is swallowed (KILL RC rh10/rh11: `/* boom */` must raise out of read_clause/3)",
      "PL_exception(ld, qid) != 0\n                rc = false",
      "PL_exception(ld, qid) != 0\n                rc = true"),
    m("RD2a-H1 callCommentHook: the hook is handed the term where it wants the term position (KILL RC rh01..rh08: Pos is the term)",
      "PL_put_term(ld, av + 1, tpos)",
      "PL_put_term(ld, av + 1, term)"),
    m("RD2a-H2 callCommentHook: the variable names are not passed (KILL RC rh rows that record the fourth argument)",
      "        if varnames != 0\n            PL_put_term(ld, av + 3, varnames)",
      "        if varnames == 0\n            PL_put_term(ld, av + 3, varnames)"),
    m("RD2a-V1 read_clause: the var_prefix option is parsed but not stored (KILL RC rc40-rc50 through read_clause rows: `_Y` stays a variable name)",
      "            rd.var_prefix = c\n        end\n        comments != 0",
      "            rd.var_prefix = rd.var_prefix\n        end\n        comments != 0"),
]
