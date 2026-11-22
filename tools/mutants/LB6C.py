# ORIGINAL: LB6-CLAUSEPROP's mutant list — no swipl-devel counterpart.
# tools/mutants/LB6C.py — the mutants of what clause_property/2 (boot/syspred.pl:1093-1111, Prolog) reads: the clause's `line_no`, `source_no` and
# `owner_no` that the loader stores (src/pl-comp.jl `record_clause` and `assert_term!`, pl-comp.c record_clause / assert_term) and the attribute
# reads of `'$get_clause_attribute'/3` (src/pl-proc.jl `pl_get_clause_attribute3_va`, pl-proc.c:3910). Format: tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run; nothing is declared
# equivalent now. The `old` strings were each counted in the file at wip/lb6clause (a Python count, once each); RE-FIT any that `tools/warm.sh fmt`
# rewraps. KILL names the row of test/db/test_clause_property_swipl.jl (CP) that is designed to kill the mutant; the rows are pinned from swipl 10.1.20
# (UNVERIFIED on the kernel until the gate).
# TARGETS (D-0238): CP first, then EVERY file that loads a source file through the mutated loader sites or reads a clause's source fields:
# test_nth_clause_swipl.jl (LB2's rows on the attributes), test_source_file_swipl.jl, test_load_swipl.jl, test_clause_ref_swipl.jl,
# test_cont_run_swipl.jl (reads clause_property/2), test_compiler_warnings_swipl.jl (reads the source location), test_qlf_swipl.jl (`addClauseWic`
# builds the same sourceloc), test_reload_blocks_swipl.jl (the reload walk compares owner_no). LB2-66..77 of LB2c.py mutate the attribute reads with
# a ONE-file program: LB6C-A7 and A8 are their file/owner swaps with the rows that tell the two apart (an include, an expansion naming another file).
CP = ["test/db/test_clause_property_swipl.jl"]
N = ["test/db/test_nth_clause_swipl.jl"]
T = ["test/db/test_source_file_swipl.jl"]
L = [
    "test/files/test_load_swipl.jl",
    "test/db/test_clause_ref_swipl.jl",
    "test/core_lang/test_cont_run_swipl.jl",
    "test/compile/test_compiler_warnings_swipl.jl",
    "test/files/test_qlf_swipl.jl",
    "test/db/test_reload_blocks_swipl.jl",
]
TARGETS = CP + N + T + L
C = "src/pl-comp.jl"
PR = "src/pl-proc.jl"
MUTANTS = [
    # ---- record_clause (pl-comp.c record_clause): the source location of the term read last, or `File:Line`
    dict(id="LB6C-A1 record_clause: the location of the `-` form is the line after the term's start (KILL CP p01 p02 p05 p06)", file=C, targets=CP + N + T + L,
         old="        line = ld.read_source.position.lineno\n",
         new="        line = ld.read_source.position.lineno + 1\n"),
    dict(id="LB6C-A2 record_clause: the `File:Line` form reads the line from the file argument (KILL CP p08: the expansion raises)", file=C, targets=CP + N + T + L,
         old="        _PL_get_arg(ld, 2, source, arg)                         # _PL_get_arg(2, source, arg)\n",
         new="        _PL_get_arg(ld, 1, source, arg)                         # _PL_get_arg(2, source, arg)\n"),
    dict(id="LB6C-A3 record_clause: the `File:Line` form keeps the loading file, not the named one (KILL CP p08: file /zz/fake.pl)", file=C, targets=CP + N + T + L,
         old="        loc = sourceloc{T}(file, line)\n",
         new="        loc = sourceloc{T}(ld.read_source.file::T, line)\n"),
    dict(id="LB6C-A4 record_clause: the owner is not passed on (assert_term! takes the term's file as owner) (KILL CP p07 p08)", file=C, targets=CP + N + T + L,
         old="    clause = assert_term!(gd, ld, term, 0, CL_END, a_owner, loc, 0)\n",
         new="    clause = assert_term!(gd, ld, term, 0, CL_END, nothing, loc, 0)\n"),
    # ---- assert_term! (pl-comp.c assert_term): the clause's line, file and owner
    dict(id="LB6C-A5 assert_term!: the clause line is the line after the location's (KILL CP p01 p06 p13)", file=C, targets=CP + N + T + L,
         old="        clause.line_no = UInt32(loc.line)\n",
         new="        clause.line_no = UInt32(loc.line) + UInt32(1)\n"),
    dict(id="LB6C-A6 assert_term!: the clause has no line number (KILL CP p01 p02 p05 p06 p08 p13)", file=C, targets=CP + N + T + L,
         old="        clause.line_no = UInt32(loc.line)\n",
         new="        clause.line_no = UInt32(0)\n"),
    dict(id="LB6C-A7 assert_term!: the owner of a clause is the file it is loaded from (KILL CP p07 p08)", file=C, targets=CP + N + T + L,
         old="        clause.owner_no = UInt32(of.index)\n",
         new="        clause.owner_no = UInt32(sf.index)\n"),
    dict(id="LB6C-A8 assert_term!: a missing owner argument is not the term's file but the owner is always the file (KILL CP p07 p08)", file=C, targets=CP + N + T + L,
         old="        own = owner === nothing ? loc.file : owner              # if ( !loc->file ) …: never\n",
         new="        own = loc.file                                          # if ( !loc->file ) …: never\n"),
    # ---- '$get_clause_attribute'/3 (pl-proc.c:3910): file and owner read the clause's two numbers (a one-file program cannot tell them apart)
    dict(id="LB6C-A9 get_clause_attribute: `file` reads the owner's index (KILL CP p06 p08; LB2-67's mutant with the rows that tell them apart)", file=PR, targets=CP + N,
         old="""    elseif k == sym_key(mk_sym(T, :file))
        sf = indexToSourceFile(gd, clause.source_no)""",
         new="""    elseif k == sym_key(mk_sym(T, :file))
        sf = indexToSourceFile(gd, clause.owner_no)"""),
    dict(id="LB6C-A10 get_clause_attribute: `owner` reads the source's index (KILL CP p07 p08; LB2-68's mutant with the rows that tell them apart)", file=PR, targets=CP + N,
         old="""    elseif k == sym_key(mk_sym(T, :owner))
        sf = indexToSourceFile(gd, clause.owner_no)""",
         new="""    elseif k == sym_key(mk_sym(T, :owner))
        sf = indexToSourceFile(gd, clause.source_no)"""),
    dict(id="LB6C-A11 get_clause_attribute: `line_count` answers for a clause with no line (KILL CP p14 p20: an asserted clause)", file=PR, targets=CP + N,
         old="        clause.line_no != 0 &&\n",
         new="        true &&\n"),
    dict(id="LB6C-A12 get_clause_attribute: `file` fails for a clause with a file (KILL CP p03 p06 p08 p18)", file=PR, targets=CP + N,
         old="        sf !== nothing && return PL_unify_atom(ld, value, sf.name) ? FTRUE : FFALSE\n    elseif k == sym_key(mk_sym(T, :owner))\n",
         new="        false && return PL_unify_atom(ld, value, sf.name) ? FTRUE : FFALSE\n    elseif k == sym_key(mk_sym(T, :owner))\n"),
    dict(id="LB6C-A13 get_clause_attribute: `fact` asks the clause's body instead of UNIT_CLAUSE (KILL CP p09 p15 p17)", file=PR, targets=CP + N,
         old="return PL_unify_bool(ld, value, (clause.flags & UNIT_CLAUSE) != 0) ? FTRUE : FFALSE",
         new="return PL_unify_bool(ld, value, (clause.flags & UNIT_CLAUSE) == 0) ? FTRUE : FFALSE"),
    dict(id="LB6C-A14 get_clause_attribute: `module` is `user` for every clause (KILL CP p16)", file=PR, targets=CP + N,
         old="gd.modules[clause.predicate.module_].atom",
         new="gd.modules[MODULE_user(gd)].atom"),
]
