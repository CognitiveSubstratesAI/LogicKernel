# ORIGINAL: T1's mutant list — no swipl-devel counterpart.
# tools/mutants/T1.py — the mutation battery of T1 (R2: the atom and text built-ins — atom_length/2, the `x_chars` family,
# char_code/2, atom_concat/3 and atomic_concat/3 — and pl-text.c's unify/compare/concat; audit D-0149 item 3), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old`
# (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. T1 is the first user of `REDO_INT` (NF1's list left its
# decode out, "no REDO_INT user until NF4"): T1-1 and T1-3 are the decode, T1-4 and T1-5 the encode of `PL_retry`, T1-6 and T1-7
# `ForeignRedoInt(at_n+1)` in `concat`; T1-2 (discardForeignFrame's decode) is declared equivalent for these built-ins. Then one mutant
# per decision of `concat`, `x_chars`, `PL_cmp_text`, `PL_concat_text`, `PL_unify_text` and `PL_get_text`'s `CVT_VARNOFAIL`.
# EQUIVALENT, with the reason: T1-2; the end-of-text results of `PL_cmp_text` (T1-E1/E2: every caller tests `== 0`);
# `char_code/2`'s equal-codes shortcut (T1-E3); `unify_text_between`'s one-character atom (T1-E4).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does
# not occur exactly once).
TARGETS = ["test/core_text/test_atom_text_swipl.jl"]
T = TARGETS
P = "src/pl-prims.jl"
X = "src/os/pl-text.jl"
F = "src/pl-fli.jl"
W = "src/pl-wam.jl"
E = "src/pl-error.jl"
MUTANTS = [
    # ---- the REDO_INT context (src/pl-wam.jl, src/pl-fli.jl, concat)
    dict(id="T1-1 I_FREDO's REDO_INT decode keeps the tag bits", file=W, targets=T,
         old='''        fd_ctx.context = reinterpret(UInt, reinterpret(Int, fd_wcl) >> FRG_REDO_BITS)''',
         new='''        fd_ctx.context = reinterpret(UInt, reinterpret(Int, fd_wcl))'''),
    dict(id="T1-2 discardForeignFrame's REDO_INT decode keeps the tag bits", file=W, targets=T,
         old='''        context.context = wcl >> FRG_REDO_BITS      # (uintptr_t)(wcl >> FRG_REDO_BITS): `word`, unsigned''',
         new='''        context.context = wcl      # (uintptr_t)(wcl >> FRG_REDO_BITS): `word`, unsigned''',
         equivalent="concat answers FRG_CUTTED before it reads its arguments or its context (src/pl-prims.jl:2561, "
                    "`PL_foreign_control(ctx) == FRG_CUTTED && return FTRUE`), so the context decoded at src/pl-wam.jl:1065 for a cut is never "
                    "read; no other built-in of this target's list has a REDO_INT context"),
    dict(id="T1-3 a redo reads the context one too high", file=P, targets=T,
         old='''            at_n = PL_foreign_context(ctx)''',
         new='''            at_n = PL_foreign_context(ctx) + 1'''),
    dict(id="T1-4 PL_retry tags the context REDO_PTR", file=F, targets=T,
         old='''PL_retry(v::Int)::foreign_t = (reinterpret(UInt, v) << FRG_REDO_BITS) | REDO_INT''',
         new='''PL_retry(v::Int)::foreign_t = (reinterpret(UInt, v) << FRG_REDO_BITS) | REDO_PTR'''),
    dict(id="T1-5 PL_retry does not shift the context past the tag", file=F, targets=T,
         old='''PL_retry(v::Int)::foreign_t = (reinterpret(UInt, v) << FRG_REDO_BITS) | REDO_INT''',
         new='''PL_retry(v::Int)::foreign_t = reinterpret(UInt, v) | REDO_INT'''),
    dict(id="T1-6 concat retries with the position two on", file=P, targets=T,
         old='''            return PL_retry(at_n + 1)                   # ForeignRedoInt(at_n+1)''',
         new='''            return PL_retry(at_n + 2)                   # ForeignRedoInt(at_n+1)'''),
    dict(id="T1-7 concat retries past the end of the text", file=P, targets=T,
         old='''        if at_n < l3
            return PL_retry(at_n + 1)''',
         new='''        if at_n <= l3
            return PL_retry(at_n + 1)'''),
    dict(id="T1-8 concat does not answer FRG_CUTTED first", file=P, targets=T,
         old='''    PL_foreign_control(ctx) == FRG_CUTTED && return FTRUE''',
         new='''    false && return FTRUE'''),
    # ---- concat (src/pl-prims.jl)
    dict(id="T1-9 concat: sharing variables are not told", file=P, targets=T,
         old='''            if PL_same_term(ld, a1, a2)                 # sharing variables''',
         new='''            if false                                    # sharing variables'''),
    dict(id="T1-10 concat: an odd length can split into two equal halves", file=P, targets=T,
         old='''                if l3 % 2 != 0''',
         new='''                if l3 % 2 == 0'''),
    dict(id="T1-11 concat: the half is one too long", file=P, targets=T,
         old='''                    at_n = l3 ÷ 2''',
         new='''                    at_n = l3 ÷ 2 + 1'''),
    dict(id="T1-12 concat: the lengths of +,+,+ are not compared", file=P, targets=T,
         old='''                l1 + l2 == l3 &&
                PL_cmp_text(t1, 0, t3, 0, l1) == 0 &&''',
         new='''                PL_cmp_text(t1, 0, t3, 0, l1) == 0 &&'''),
    dict(id="T1-13 concat: +,+,- unifies a string", file=P, targets=T,
         old='''            return PL_unify_text(ld, a3, 0, c, otype) ? FTRUE : FFALSE''',
         new='''            return PL_unify_text(ld, a3, 0, c, PL_STRING) ? FTRUE : FFALSE'''),
    dict(id="T1-14 concat: -,+,+ drops one character too many", file=P, targets=T,
         old='''            return PL_unify_text_range(ld, a1, t3, 0, l3 - l2, otype) ? FTRUE : FFALSE''',
         new='''            return PL_unify_text_range(ld, a1, t3, 0, l3 - l2 - 1, otype) ? FTRUE : FFALSE'''),
    dict(id="T1-15 concat: +,-,+ starts the rest one too late", file=P, targets=T,
         old='''            return PL_unify_text_range(ld, a2, t3, l1, l3 - l1, otype) ? FTRUE : FFALSE''',
         new='''            return PL_unify_text_range(ld, a2, t3, l1 + 1, l3 - l1, otype) ? FTRUE : FFALSE'''),
    dict(id="T1-16 concat: atomic_concat's mode instantiates", file=P, targets=T,
         old='''    inmode = bidirectional ? CVT_VARNOFAIL : UInt32(0)''',
         new='''    inmode = UInt32(0)'''),
    # ---- pl-text.jl: compare, concatenate, unify
    dict(id="T1-17 PL_cmp_text: characters are not compared", file=X, targets=T,
         old='''            c1 != c2 && return c1 > c2 ? CMP_GREATER : CMP_LESS      # CMP_CHARS''',
         new='''            false && return c1 > c2 ? CMP_GREATER : CMP_LESS         # CMP_CHARS'''),
    dict(id="T1-18 PL_cmp_text: the second text starts at the first's offset", file=X, targets=T,
         old='''        q = s2
''',
         new='''        q = s1
'''),
    dict(id="T1-19 PL_cmp_text: the length is not counted", file=X, targets=T,
         old='''            len == 0 && return CMP_EQUAL                    # CMP_LENGTH: len-- == 0''',
         new='''            false && return CMP_EQUAL                       # CMP_LENGTH: len-- == 0'''),
    dict(id="T1-E1 PL_cmp_text: the first text ends first and is the greater", file=X, targets=T,
         old='''            s >= e1 && return CMP_LESS''',
         new='''            s >= e1 && return CMP_GREATER''',
         equivalent="every caller tests the result `== 0` (src/pl-prims.jl:2583, 2584, 2597: `PL_cmp_text(...) == 0`), and a text ending "
                    "first (src/os/pl-text.jl:351) is never equal either way"),
    dict(id="T1-E2 PL_cmp_text: the second text ends first and is the lesser", file=X, targets=T,
         old='''            q >= e2 && return CMP_GREATER''',
         new='''            q >= e2 && return CMP_LESS''',
         equivalent="every caller tests the result `== 0` (src/pl-prims.jl:2583, 2584, 2597: `PL_cmp_text(...) == 0`), and a text ending "
                    "first (src/os/pl-text.jl:352) is never equal either way"),
    dict(id="T1-20 PL_concat_text: a wide text is demoted to ISO Latin-1", file=X, targets=T,
         old='''        if latin && !can_demote(t)''',
         new='''        if false && !can_demote(t)'''),
    dict(id="T1-21 PL_unify_text: a character list is a code list", file=X, targets=T,
         old='''                if type == PL_CODE_LIST                             # EXTEND_SEQ_CODES''',
         new='''                if true                                             # EXTEND_SEQ_CODES'''),
    dict(id="T1-22 PL_unify_text: a string is made an atom", file=X, targets=T,
         old='''        return PL_unify_atomic(ld, term, mk_gnd(T, _text_string(text)))''',
         new='''        return PL_unify_atom(ld, term, _atom_from_text(T, _text_string(text)))'''),
    dict(id="T1-E4 unify_text_between: a one-character atom is made through its sub-text", file=X, targets=T,
         old='''    if len == 1 && type == PL_ATOM && upto > from''',
         new='''    if false && len == 1 && type == PL_ATOM && upto > from''',
         equivalent="the sub-text of one code point made an atom is the atom `codeToAtom` gives (src/os/pl-text.jl:602 against "
                    "the general path at :606-611, `PL_unify_text` of the sub-text): upstream's branch is a shortcut (pl-text.c unify_text_between)"),
    # ---- PL_get_text's CVT_VARNOFAIL
    dict(id="T1-23 PL_get_text: an unbound term is an error under CVT_VARNOFAIL", file=X, targets=T,
         old='''    k == DU_CELL && (flags & CVT_VARNOFAIL) != 0 && return PL_init_text()      # canBind(w): GT_ISVAR''',
         new='''    nothing                                                                    # canBind(w): GT_ISVAR'''),
    dict(id="T1-24 PL_get_text: a partial list is an error under CVT_VARNOFAIL", file=X, targets=T,
         old='''        (flags & CVT_VARNOFAIL) != 0 && result.status == CVT_partial &&
            return PL_init_text()  # GT_ISVAR''',
         new='''        nothing  # GT_ISVAR'''),
    # ---- x_chars and the predicates on it (src/pl-prims.jl)
    dict(id="T1-25 x_chars: the second pass raises on a partial list", file=P, targets=T,
         old='''        flags2 |= CVT_VARNOFAIL''',
         new='''        flags2 |= UInt32(0)'''),
    dict(id="T1-26 x_chars: the text is not canonicalised for the number", file=P, targets=T,
         old='''        PL_canonicalise_text_ex(ld, stext) || return false''',
         new='''        nothing'''),
    dict(id="T1-27 x_chars: leading layout is not skipped", file=P, targets=T,
         old='''                s = utf8_skip_blanks(b, s)''',
         new='''                s = s'''),
    dict(id="T1-28 x_chars: trailing text after the number is accepted", file=P, targets=T,
         old='''                if q == length(b)                       # q == stext.text.t + stext.length''',
         new='''                if true                                 # q == stext.text.t + stext.length'''),
    dict(id="T1-29 x_chars: name/2 raises on a text that is no number", file=P, targets=T,
         old='''        if mode == X_AUTO
            @goto case_atom''',
         new='''        if false
            @goto case_atom'''),
    dict(id="T1-30 x_chars: number_string/2 raises a syntax error", file=P, targets=T,
         old='''            if (how & X_NO_SYNTAX_ERROR) == 0''',
         new='''            if true'''),
    dict(id="T1-31 x_chars: a wide text is never read as a number", file=P, targets=T,
         old='''                if PlDecimalW(c)                        # f_is_decimal(c)''',
         new='''                if false                                # f_is_decimal(c)'''),
    dict(id="T1-32 x_chars: a wide text's sign is not skipped", file=P, targets=T,
         old='''                if c == Int('-') || c == Int('+')''',
         new='''                if false'''),
    dict(id="T1-33 x_chars: a wide text's leading layout is not skipped", file=P, targets=T,
         old='''                    if isBlankW(text_get_char(stext, ws))''',
         new='''                    if false'''),
    dict(id="T1-34 x_chars: number_codes/2 names the wrong type", file=P, targets=T,
         old='''        elseif mode == X_NUMBER
            :number''',
         new='''        elseif mode == X_NUMBER
            :atom'''),
    dict(id="T1-35 x_chars: a character list is made a code list", file=P, targets=T,
         old='''        out_type = if (how & X_CHARS) != 0
            PL_CHAR_LIST''',
         new='''        out_type = if (how & X_CHARS) != 0
            PL_CODE_LIST'''),
    dict(id="T1-36 char_code: any integer is a character code", file=P, targets=T,
         old='''        if !VALID_CODE_POINT(n)''',
         new='''        if false'''),
    dict(id="T1-E3 char_code: equal codes unify the integer instead", file=P, targets=T,
         old='''    achr == cchr && return FTRUE''',
         new='''    nothing''',
         equivalent="with both bound and equal (src/pl-prims.jl:2495), the next branch (:2499, `PL_unify_integer(ld, chr, achr)`) unifies "
                    "`chr` with `achr`, the same integer"),
    dict(id="T1-37 atom_length: the text of a number is refused", file=P, targets=T,
         old='''    flags = truePrologFlag(ld, PLFLAG_ISO) ? CVT_ATOM | CVT_STRING : CVT_ALL''',
         new='''    flags = CVT_ATOM | CVT_STRING'''),
    dict(id="T1-38 atom_length: a length that is no integer fails", file=P, targets=T,
         old='''        return unify_int64_ex(ld, len, PL_text_length(txt), true)      # PL_unify_int64_ex''',
         new='''        return unify_int64_ex(ld, len, PL_text_length(txt), false)     # PL_unify_int64_ex'''),
    # ---- the syntax error (src/pl-error.jl)
    dict(id="T1-39 PL_error: a syntax error is a domain error", file=E, targets=T,
         old='''        ld, formal, _err_functor(ld, :syntax_error, 1),''',
         new='''        ld, formal, _err_functor(ld, :domain_error, 1),'''),
]
