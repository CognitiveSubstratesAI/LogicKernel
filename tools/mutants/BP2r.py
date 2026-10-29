# ORIGINAL: BP2's mutant list — no swipl-devel counterpart.
# tools/mutants/BP2r.py — the mutation battery of BP2 (the eight named backports of 2026-10-29, audit D-0221: upstream
# cd67bb35 Q12, 1582e8b3 Q5, 8b24de91 Q4, 627ecb5d Q2, 1772f406 Q7, ea1b569b Q9, 7f8024cc Q1, ace539d7 Q13), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant per decision of each fix; the `old` strings were
# written AFTER `tools/warm.sh fmt`.
# NOT listed: `LD->read_source.position = *pos` in setErrorLocation (no row reads it back); the `Sferror` returns of
# raw_read_quoted (no row reaches them).
# No mutant (D-0100, D-0240): dropping the neck test (src/pl-proc.jl `neck_ok`'s else branch, ~:1449) or the fact test (`neck_ok`'s
# if branch, ~:1446) in `pl_retract1_va`'s `matched` — implied by the SSU-flags conjunct (src/pl-proc.jl ~:1452, upstream
# pl-proc.c:3209): the flags test comes first in the same expression and already makes both hold. Q9c/Q9d mutate what the fix changes.
# D-0238: a mutant's targets list EVERY test file that exercises the mutated code (found by what each file calls, not by the
# step's own file), so an early battery with narrow targets cannot "prove" dead code.
T12 = ["test/files/test_open_close_swipl.jl"]                      # open/4's newline(Mode): only this file passes it
T5 = ["test/core_lang/test_arith_swipl.jl"]                         # powm/3: only this file
T4 = ["test/core_lang/test_bagof_swipl.jl", "test/core_lang/test_walks_cells.jl",
      "test/core_lang/test_var_identity.jl", "test/core_lang/test_sortlist_swipl.jl"]   # free_variables_loop and its users
T2 = ["test/compile/test_body_code_swipl.jl", "test/compile/test_decompile.jl", "test/db/test_clause_swipl.jl",
      "test/compile/test_ssu_compile_swipl.jl", "test/compile/test_head_code_swipl.jl", "test/db/test_assert_swipl.jl"]   # decompile of a clause body
T7 = ["test/core_lang/test_current_op_swipl.jl", "test/core_lang/test_op_swipl.jl", "test/core_text/test_op.jl"]
T9 = ["test/compile/test_ssu_compile_swipl.jl", "test/core_lang/test_ssu_swipl.jl", "test/db/test_retract_swipl.jl",
      "test/db/test_assert_swipl.jl", "test/core_lang/test_rules_swipl.jl", "test/compile/test_decompile.jl"]   # retract/1 and clause_functor
T1 = ["test/core_text/test_read.jl", "test/files/test_open_close_swipl.jl", "test/core_text/test_read_positions_swipl.jl",
      "test/core_text/test_canonical_readatom_swipl.jl", "test/core_text/test_read_term_swipl.jl",
      "test/core_text/test_reader_cells.jl", "test/core_text/test_syntax.jl"]   # the reader's raw read and error location
T13 = ["test/core_lang/test_write_cells.jl", "test/core_text/test_write_family_swipl.jl"]
# the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant names
TARGETS = sorted(set(T12 + T5 + T4 + T2 + T7 + T9 + T1 + T13))
F = "src/os/pl-file.jl"
MUTANTS = [
    # ---- Q12 (cd67bb35): open/4's newline(Mode)
    dict(id="BP2-Q12a detect is allowed on an output stream", file=F, targets=T12,
         old='''        if (flags & SIO_INPUT) == 0
            newline_domain_error(''',
         new='''        if false
            newline_domain_error('''),
    dict(id="BP2-Q12b an unknown mode is posix", file=F, targets=T12,
         old='''    newline_domain_error(ld, val, "")
    return nothing''',
         new='''    return SIO_NL_POSIX'''),
    dict(id="BP2-Q12c the culprit is [], not the mode", file=F, targets=T12,
         old='''    PL_put_atom(ld, t, val)
    return PL_error(ld, "", 0, msg, ERR_DOMAIN, mk_sym(T, :newline), t)''',
         new='''    PL_put_nil(ld, t)
    return PL_error(ld, "", 0, msg, ERR_DOMAIN, mk_sym(T, :newline), t)'''),
    dict(id="BP2-Q12d the detect error has no message", file=F, targets=T12,
         old='''newline_domain_error(ld, val, "detect only allowed for input streams")''',
         new='''newline_domain_error(ld, val, "")'''),
    dict(id="BP2-Q12e the option is looked at for binary streams", file=F, targets=T12,
         old='''    if newline !== nothing && !_sym_is(type, :binary)''',
         new='''    if newline !== nothing'''),
    dict(id="BP2-Q12f the mode is always asked as for input", file=F, targets=T12,
         old='''how[1] == 'r' ? SIO_INPUT : SIO_OUTPUT)''',
         new='''SIO_INPUT)'''),
    dict(id="BP2-Q12g the error does not stop open/4", file=F, targets=T12,
         old='''        nm === nothing && return nothing
        fnewline = nm''',
         new='''        fnewline = something(nm, SIO_NL_POSIX)'''),
    # ---- Q5 (1582e8b3): powm/3 stops at its first type error
    dict(id="BP2-Q5a powm continues after the base's type error", file="src/pl-arith.jl", targets=T5,
         old='''    intNumber(base) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), base)''',
         new='''    intNumber(base) ||
        PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), base)'''),
    dict(id="BP2-Q5b powm continues after the exponent's type error", file="src/pl-arith.jl", targets=T5,
         old='''    intNumber(exp) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), exp)''',
         new='''    intNumber(exp) ||
        PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), exp)'''),
    dict(id="BP2-Q5c powm continues after the modulus' type error", file="src/pl-arith.jl", targets=T5,
         old='''    intNumber(mod) ||
        return PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), mod)''',
         new='''    intNumber(mod) ||
        PL_error(ld, "powm", 3, "", ERR_AR_TYPE, mk_sym(T, :integer), mod)'''),
    # ---- Q4 (8b24de91): the goal after Module: is dereferenced
    dict(id="BP2-Q4a the goal after Module: is not dereferenced", file="src/pl-prims.jl", targets=T4,
         old='''                    k, w, p = _deref_loc(ld, c + 2)         # t = &f->arguments[1] (see DIVERGES)''',
         new='''                    k, w, p = (DU_WORD, ld.gstack[c + 2], c + 2)    # t = &f->arguments[1] (see DIVERGES)'''),
    # ---- Q2 (627ecb5d): clause/2's body when every moved unification became a head unification
    dict(id="BP2-Q2a last starts at 0: the early `true` never fires", file="src/pl-comp.jl", targets=T2,
         old='''    last = -1
    for i in 0:(length(bvar_access) - 1)''',
         new='''    last = 0
    for i in 0:(length(bvar_access) - 1)'''),
    dict(id="BP2-Q2b the early `true` also fires for a clause with a body", file="src/pl-comp.jl", targets=T2,
         old='''    if last < 0 && !hasbody ''',
         new='''    if last < 0 '''),
    dict(id="BP2-Q2c the early return is not taken", file="src/pl-comp.jl", targets=T2,
         old='''        return PL_unify_atom(ld, body, mk_sym(T, Symbol("true")))
    end
    for i in 0:last''',
         new='''        nothing
    end
    for i in 0:last'''),
    # ---- Q7 (1772f406): current_op/3 matches the priority when it enumerates
    dict(id="BP2-Q7a an operator of another module does not hide the one of the same kind", file="src/pl-op.jl", targets=T7,
         old='''        sym_key(n) == sym_key(name) && (ty & OP_MASK) == (type & OP_MASK) && return nothing''',
         new='''        false && return nothing'''),
    dict(id="BP2-Q7b a given priority is not checked as 1..1200", file="src/pl-op.jl", targets=T7,
         old='''            if !(pv > 0 && pv <= 1200)''',
         new='''            if false'''),
    # ---- Q9 (ea1b569b): retract/1 of an SSU clause
    dict(id="BP2-Q9a an SSU neck with the body true is a bare head", file="src/pl-proc.jl", targets=T9,
         old='''        (flags & CLAUSE_SSU_FLAGS) == 0 && bk == DU_WORD &&''',
         new='''        bk == DU_WORD &&'''),
    dict(id="BP2-Q9b clause_functor reads the commit bit only", file="src/pl-comp.jl", targets=T9,
         old='''    ssu = flags & CLAUSE_SSU_FLAGS
    ssu == 0''',
         new='''    ssu = flags & SSU_COMMIT_CLAUSE
    ssu == 0'''),
    # The neck test `clause_functor(clause) == clause_functor(flags)` is IMPLIED by the flags equality in `matched` (upstream's own
    # `(clause->flags&CLAUSE_SSU_FLAGS) == (flags&CLAUSE_SSU_FLAGS)`, pl-proc.c): dropping it, or the fact branch's
    # `(flags & CLAUSE_SSU_FLAGS) == 0`, changes nothing (measured: both survived every row). What the fix changed is WHICH neck the
    # call's term has (clause_functor(flags), not FUNCTOR_prove2), so Q9c puts the pre-fix `:-` back, and Q9d makes a fact never match
    # `Head :- Body` (a27).
    dict(id="BP2-Q9c retract/1 compares the clause's neck with :-/2 (the pre-fix FUNCTOR_prove2)", file="src/pl-proc.jl", targets=T9,
         old='''                clause_functor(ld, clause.flags) == clause_functor(ld, flags)''',
         new='''                clause_functor(ld, clause.flags) == clause_functor(ld, UInt32(0))'''),
    dict(id="BP2-Q9d a fact never matches Head :- Body", file="src/pl-proc.jl", targets=T9,
         old='''            if (clause.flags & UNIT_CLAUSE) != 0
                (flags & CLAUSE_SSU_FLAGS) == 0''',
         new='''            if (clause.flags & UNIT_CLAUSE) != 0
                false'''),
    # ---- Q1 (7f8024cc): the location of an unterminated quote or block comment
    dict(id="BP2-Q1a a string's offset is the item's, not one past it", file="src/pl-read.jl", targets=T1,
         old='''    isStringStream(rd._rb.stream) && return start + 1''',
         new='''    isStringStream(rd._rb.stream) && return start'''),
    dict(id="BP2-Q1b every stream is treated as a file's", file="src/pl-read.jl", targets=T1,
         old='''    isStringStream(rd._rb.stream) && return start + 1''',
         new='''    false && return start + 1'''),
    dict(id="BP2-Q1c a file stream's buffer is not reset", file="src/pl-read.jl", targets=T1,
         old='''    rd._rb.here = 1                                 # rb.here = rb.base''',
         new='''    nothing                                         # rb.here = rb.base''',
         equivalent="src/pl-read.jl:480 — read, not run (survived the whole T1 target list in run 40953074854): the reset is reached only for a stream that is not a string stream (:475 returns first). The error that follows (rawSyntaxErrorAt :500-507, whose addToBuffer(0) writes the EOS at rb.here) is located by makeErrorTerm (:1101, :1112) with token_start = 1 + offset = 1, and ptr_to_location (:1021) walks nothing from rd.base = 1; for a file stream unify_location (:1073) builds file(Path, L, LP, C) from start_of_term alone, and its only reader of the buffer text, _rd_text (:1060, called at :1084), sits in the string-stream branch :1081; any other stream throws NotPortedError there. clearBuffer (:368, called at :715) sets rb.here = 1 at the start of every read, so the position is not carried into the next one."),
    dict(id="BP2-Q1d a file stream's term position is not the item's", file="src/pl-read.jl", targets=T1,
         old='''        rd.start_of_term.position = copy2           # _PL_rd->start_of_term.position = *pos''',
         new='''        nothing                                     # _PL_rd->start_of_term.position = *pos'''),
    dict(id="BP2-Q1e rawSyntaxErrorAt points at the end of the buffer", file="src/pl-read.jl", targets=T1,
         old='''    rd.token_start = 1 + offset ''',
         new='''    rd.token_start = rd._rb.here - 1 '''),
    dict(id="BP2-Q1f a quoted item's start is taken after its opening quote", file="src/pl-read.jl", targets=T1,
         old='''
    start = rd._rb.here - 1 ''',
         new='''
    start = rd._rb.here '''),
    dict(id="BP2-Q1g a block comment's start is taken after its opening", file="src/pl-read.jl", targets=T1,
         old='''                start = rd._rb.here - 1             # size_t start = rb.here - rb.base''',
         new='''                start = rd._rb.here + 2             # size_t start = rb.here - rb.base'''),
    # ---- Q13 (ace539d7): an attributed variable met in its own attributes is written as its name
    dict(id="BP2-Q13a the cycle is not detected", file="src/pl-write.jl", targets=T13,
         old='''        rc = writing_attvar(ld, av, outer)
        if rc''',
         new='''        rc = writing_attvar(ld, av, outer)
        if false'''),
    dict(id="BP2-Q13b the list of attvars is not restored", file="src/pl-write.jl", targets=T13,
         old='''            options.attvars = outer
''',
         new='''            nothing
'''),
    dict(id="BP2-Q13c an inner write forgets the outer list", file="src/pl-write.jl", targets=T13,
         old='''(outer != 0 ? PL_put_term(ld, attvars, outer) : PL_put_nil(ld, attvars))''',
         new='''PL_put_nil(ld, attvars)'''),
    dict(id="BP2-Q13d writing_attvar answers for a different variable", file="src/pl-write.jl", targets=T13,
         old='''        PL_compare(ld, h, av) == 0 && return true''',
         new='''        PL_compare(ld, h, av) != 0 && return true'''),
    dict(id="BP2-Q13e the closing brace is not written", file="src/pl-write.jl", targets=T13,
         old='''                Putc(Int('{'), options.out) && writeAttributes(a, 1200, options, W_TOP) &&
                Putc(Int('}'), options.out)''',
         new='''                Putc(Int('{'), options.out) && writeAttributes(a, 1200, options, W_TOP)'''),
]
