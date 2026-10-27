# ORIGINAL: LB1's mutant list — no swipl-devel counterpart.
# tools/mutants/LB1.py — the mutation battery of LB1 (term positions in the reader, read_clause/3 registered; the R2
# design loader_boot.md §7, audit D-0149), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. One mutant per position decision: the start and the end of each position term at each
# term kind (atomic, string, list with and without a tail, brace and parentheses, compound, operator of each kind and
# a block operator), the places a construct's end is written (`set_range_position`), the level's own position
# (`complex_term`), the term position of a stream (`unify_read_term_position`), the option handling and the stream
# check of read_clause/3. No mutant is declared equivalent.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string
# that does not occur exactly once).
TP = ["test/core_text/test_read_positions_swipl.jl"]
TU = ["test/core_text/test_read.jl"]
TARGETS = TP + TU                                   # the baseline's targets (mutate_ci.py plan reads TARGETS)
R = "src/pl-read.jl"
F = "src/os/pl-file.jl"
MUTANTS = [
    # ---- the position terms
    dict(id="LB1-1 an atomic token's position is not unified", file=R, targets=TP + TU,
         old='''    return _unify_position!(ld, positions, :-, (token.start, token.end_), ())  # FUNCTOR_minus2''',
         new='''    return true                                     # FUNCTOR_minus2'''),
    dict(id="LB1-2 a string's position is From-To", file=R, targets=TP + TU,
         old='''    return _unify_position!(ld, positions, :string_position, (token.start, token.end_), ())''',
         new='''    return _unify_position!(ld, positions, :-, (token.start, token.end_), ())'''),
    dict(id="LB1-3 an atomic token's end is its start", file=R, targets=TP + TU,
         old='''    return _unify_position!(ld, positions, :-, (token.start, token.end_), ())  # FUNCTOR_minus2''',
         new='''    return _unify_position!(ld, positions, :-, (token.start, token.start), ())  # FUNCTOR_minus2'''),
    dict(id="LB1-4 a position term's integers are left unbound", file=R, targets=TP + TU,
         old='''        v == _POS_VARIABLE && continue              # PL_VARIABLE''',
         new='''        continue                                    # PL_VARIABLE'''),
    dict(id="LB1-5 get_int_arg reads the next argument", file=R, targets=TP + TU,
         old='''    _, a, _ = _deref_loc(ld, valPtr(w) + n)         # argTerm(*p, n-1)''',
         new='''    _, a, _ = _deref_loc(ld, valPtr(w) + n + (n == 1 ? 1 : 0))  # argTerm(*p, n-1)'''),
    # ---- operators (opPos, build_op_term, modify_op, complex_term)
    dict(id="LB1-6 an infix operator term starts at its right operand", file=R, targets=TP + TU,
         old='''        s = get_int_arg(ld, q[args].tpos, 1)
        e = get_int_arg(ld, q[args + 1].tpos, 2)''',
         new='''        s = get_int_arg(ld, q[args + 1].tpos, 1)
        e = get_int_arg(ld, q[args + 1].tpos, 2)'''),
    dict(id="LB1-7 an infix block operator keeps its name's range", file=R, targets=TP,
         old='''            l = _position_list(ld, (op.tpos, q[args].tpos, q[args + 1].tpos))
            _unify_position!(ld, r, :term_position, (s, e, 0, 0), (l,)) || return 0''',
         new='''            l = _position_list(ld, (op.tpos, q[args].tpos, q[args + 1].tpos))
            _unify_position!(ld, r, :term_position, (s, e, fs, fe), (l,)) || return 0'''),
    dict(id="LB1-8 a prefix operator term starts at its operand", file=R, targets=TP + TU,
         old='''        if op.kind == OP_PREFIX
            s = fs''',
         new='''        if op.kind == OP_PREFIX
            s = get_int_arg(ld, q[args].tpos, 1)'''),
    dict(id="LB1-9 a postfix operator term ends at its operand", file=R, targets=TP,
         old='''            s = get_int_arg(ld, q[args].tpos, 1)
            e = fe''',
         new='''            s = get_int_arg(ld, q[args].tpos, 1)
            e = get_int_arg(ld, q[args].tpos, 2)'''),
    dict(id="LB1-10 a prefix or postfix block operator keeps its name's range", file=R, targets=TP + TU,
         old='''            l = _position_list(ld, (op.tpos, q[args].tpos))
            _unify_position!(ld, r, :term_position, (s, e, 0, 0), (l,)) || return 0''',
         new='''            l = _position_list(ld, (op.tpos, q[args].tpos))
            _unify_position!(ld, r, :term_position, (s, e, fs, fe), (l,)) || return 0'''),
    dict(id="LB1-11 an operator term keeps its first operand's position", file=R, targets=TP + TU,
         old='''    if op.tpos != 0                                 # …unless op->tpos: e->tpos = opPos(op, e)''',
         new='''    if false                                        # …unless op->tpos: e->tpos = opPos(op, e)'''),
    dict(id="LB1-12 a prefix operator taken as an atom loses its position", file=R, targets=TP,
         old='''            queue_out_op(0, op.tpos, rd)''',
         new='''            queue_out_op(0, 0, rd)'''),
    dict(id="LB1-13 an operator's name gets no position of its own", file=R, targets=TP + TU,
         old='''        in_op.tpos = pin''',
         new='''        in_op.tpos = in_op.tpos'''),
    # ---- complex_term's levels
    dict(id="LB1-14 a level's term is not unified with its positions", file=R, targets=TP + TU,
         old='''            rc = PL_unify(rd.ld, positions, rd.op.out_queue[e].tpos) ? 1 : 0''',
         new='''            rc = 1'''),
    dict(id="LB1-15 a lone operator's position is not unified", file=R, targets=TP,
         old='''            rc = PL_unify(rd.ld, positions, op.tpos) ? 1 : 0''',
         new='''            rc = 1'''),
    dict(id="LB1-16 a construct's own position is not restored", file=R, targets=TP + TU,
         old='''    positions = frame.positions
    pin = frame.pin''',
         new='''    positions = frame.positions'''),
    dict(id="LB1-17 a subterm is read with its parent's positions", file=R, targets=TP + TU,
         old='''    maxpri = req.maxpri
    positions = req.positions''',
         new='''    maxpri = req.maxpri'''),
    # ---- the constructs
    dict(id="LB1-18 a construct's end is not written", file=R, targets=TP + TU,
         old='''    end_ >= 0 && (ld.gstack[p + 2] = _gnd_word!(ld, mk_gnd(T, end_)))      # p[1] = consInt(end)''',
         new='''    nothing                                                                 # p[1] = consInt(end)'''),
    dict(id="LB1-19 a list element gets no position", file=R, targets=TP + TU,
         old='''    if pv != 0 && !PL_unify_list(rd.ld, pv + 1, pv, pv + 1)    # P_LIST, P_ELEM, P_LIST''',
         new='''    if false                                                # P_LIST, P_ELEM, P_LIST'''),
    dict(id="LB1-20 a list without a tail keeps its tail position open", file=R, targets=TP + TU,
         old='''                PL_unify_atom(ld, pv + 2, mk_sym(T, :none))         # P_TAIL, ATOM_none''',
         new='''                true                                                # P_TAIL, ATOM_none'''),
    dict(id="LB1-21 a list's tail gets no position", file=R, targets=TP + TU,
         old='''        req.positions = pv != 0 ? pv + 2 : 0            # P_TAIL''',
         new='''        req.positions = 0                               # P_TAIL'''),
    dict(id="LB1-22 a list with a tail does not end at its `]`", file=R, targets=TP + TU,
         old='''    pv = f.list_pv
    if pv != 0
        set_range_position(rd.ld, f.pin, -1, tk.end_)''',
         new='''    pv = f.list_pv
    if pv != 0
        set_range_position(rd.ld, f.pin, -1, tk.end_ - 1)'''),
    dict(id="LB1-23 a list's start is the first element's", file=R, targets=TP + TU,
         old='''                (token.start, _POS_VARIABLE), (pv + 1, pv + 2)  #   PL_TERM, P_LIST, PL_TERM, P_TAIL''',
         new='''                (token.end_, _POS_VARIABLE), (pv + 1, pv + 2)  #   PL_TERM, P_LIST, PL_TERM, P_TAIL'''),
    dict(id="LB1-24 a parenthesised term is a brace term", file=R, targets=TP,
         old='''        fpos = :parentheses_term_position           # FUNCTOR_parentheses_term_position3''',
         new='''        fpos = :brace_term_position                 # FUNCTOR_parentheses_term_position3'''),
    dict(id="LB1-25 a bracketed term does not end at its close", file=R, targets=TP + TU,
         old='''    f.pin != 0 && set_range_position(rd.ld, f.pin, -1, tk.end_)''',
         new='''    nothing'''),
    dict(id="LB1-26 a bracketed term's argument gets no position", file=R, targets=TP + TU,
         old='''    req.maxpri = OP_MAXPRIORITY + 1
    req.positions = pa''',
         new='''    req.maxpri = OP_MAXPRIORITY + 1
    req.positions = 0'''),
    dict(id="LB1-27 a compound's name range is its start only", file=R, targets=TP + TU,
         old='''                (token.start, _POS_VARIABLE, token.start, token.end_),  # PL_INT64 ×2,''',
         new='''                (token.start, _POS_VARIABLE, token.start, token.start),  # PL_INT64 ×2,'''),
    dict(id="LB1-28 a compound's argument list is left open", file=R, targets=TP + TU,
         old='''        PL_unify_nil(rd.ld, pv + 1) || return 0     # P_ARG''',
         new='''        true || return 0                            # P_ARG'''),
    dict(id="LB1-29 a compound's argument gets no position", file=R, targets=TP + TU,
         old='''    req.positions = pv                              # P_HEAD''',
         new='''    req.positions = 0                               # P_HEAD'''),
    dict(id="LB1-30 a string stream is read without its position record", file=R, targets=TP + TU,
         old='''    rd.subtpos != 0 && (s.position = s.posbuf)     # s->position = &s->posbuf''',
         new='''    nothing                                         # s->position = &s->posbuf'''),
    # ---- term_position and read_clause/3
    dict(id="LB1-31 read_clause leaves term_position unbound", file=R, targets=TP,
         old='''        rval && tpos != 0 && (rval = unify_read_term_position(ld, tpos))''',
         new='''        nothing'''),
    dict(id="LB1-32 a stream without line numbers gets a term position", file=R, targets=TP,
         old='''    if tpos != 0 && p.lineno > 0                    # source_line_no > 0''',
         new='''    if tpos != 0 && p.lineno >= 0                   # source_line_no > 0'''),
    dict(id="LB1-33 '$stream_position' has the line before the character", file=R, targets=TP,
         old='''            (Int64(p.charno), Int64(p.lineno), Int64(p.linepos), Int64(p.byteno)), ()''',
         new='''            (Int64(p.lineno), Int64(p.charno), Int64(p.linepos), Int64(p.byteno)), ()'''),
    dict(id="LB1-34 read_clause's stream may be an output stream", file=F, targets=TP,
         old='''    tp = if (s.flags & SIO_INPUT) == 0                  # ok:''',
         new='''    tp = if false                                       # ok:'''),
    dict(id="LB1-35 read_clause's unknown stream fails silently", file=F, targets=TP,
         old='''            s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS | SH_INPUT)''',
         new='''            s = get_stream_handle(ld, a, SH_ALIAS | SH_INPUT)'''),
]
