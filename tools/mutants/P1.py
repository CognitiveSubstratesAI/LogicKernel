# ORIGINAL: P1's mutant list — no swipl-devel counterpart.
# tools/mutants/P1.py — the mutation battery of P1 (pl-prims.c: arg/3 and get_arg_integer_ex, compound_name_arity/3,
# compound_name_arguments/3, subsumes_term/2 (subsumes), '$factorize_term'/3, '$term_size'/3 (term_size),
# is_most_general_term/1, term_singletons/2 and '$term_multitons'/2 (term_variables_loop with TV_SINGLETON / TV_SHARED),
# run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as
# MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by
# test/core_lang/test_p1_swipl.jl (rows p001-p176 named in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in src/pl-prims.jl at wip/p1 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * subsumes_cells' restore of the occurs-check mode (`ld.prolog_flag_occurs_check = omode`): EQUIVALENT in these rows —
#     the flag is OCCURS_CHECK_FALSE at the start (src/pl-prims.jl: the default), so the restore writes the value the
#     assignment before it wrote; only a run under occurs_check=true or error sees it, and no row sets the flag.
#   * subsumes_cells' argument order of `PL_unify(ld, general, specific)`: EQUIVALENT, unification is symmetric.
#   * term_variables_to_termv_first_cells' `if count <= maxcount` (the filter when the count is above maxcount):
#     the DIVERGES of the handoff (a `$term_multitons/2` whose second argument is a proper list shorter than the variables);
#     no row reaches it because swipl 10.1.19 cannot answer that call, so the gate's mutant would survive: not listed.
#   * pl_term_singletons2_va / pl_term_multitons2_va's `is_acyclic_cells` test turned to `true`: the walk of a cyclic term
#     is not known to stop, a hang is a TIMEOUT, not a verdict about the check: not listed.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. The predicates of this step
# are reached by name from test/core_lang/test_p1_swipl.jl only (the other test files that name compound_name_arity,
# compound_name_arguments, arg( or is_most_general_term do so in swipl-side drivers or in comments). The mutants of
# `term_variables` (the dispatch line the step added) are also run by every file that exercises term_variables/2,3 and
# term_attvars on the kernel, which are listed in TV.
TP = ["test/core_lang/test_p1_swipl.jl"]
TV = TP + [
    "test/core_lang/test_sortlist_swipl.jl", "test/core_lang/test_walks_cells.jl",
    "test/core_lang/test_attvar_wakeup.jl", "test/core_lang/test_var_identity.jl",
    "test/core_lang/test_fli_unify_cells.jl", "test/core_lang/test_fli_words.jl",
    "test/core_text/test_read_term_swipl.jl", "test/compile/test_compiler_warnings_swipl.jl",
    "test/test_fuzz_shapes.jl",
]
TARGETS = TV                                            # the baseline's (mutate_ci.py plan reads TARGETS)
P = "src/pl-prims.jl"
MUTANTS = [
    # ── arg/3, get_arg_integer_ex (pl-prims.c:2655, :2704) ──
    dict(id="P1-A1 get_arg_integer_ex takes 0 as a position: arg(0, T, A) reads the functor cell (KILL p004)", file=P, targets=TP,
         old="            v > 0 && return (1, Int(v))\n",
         new="            v >= 0 && return (1, Int(v))\n"),
    dict(id="P1-A2 get_arg_integer_ex answers a variable for 0: arg(0, T, A) enumerates (KILL p004)", file=P, targets=TP,
         old="            v == 0 && return (0, 0)\n",
         new="            v == 0 && return (-1, 0)\n"),
    dict(id="P1-A3 get_arg_integer_ex raises no domain error for a negative big integer (KILL p010)", file=P, targets=TP,
         old="            neg = integer_is_int64(p) ? int64_value(p) < 0 : bigint_value(p) < 0\n",
         new="            neg = false\n"),
    dict(id="P1-A4 arg/3 with N bound rejects N == arity (KILL p002)", file=P, targets=TP,
         old="            idx <= arity || return FFALSE\n",
         new="            idx < arity || return FFALSE\n"),
    dict(id="P1-A5 arg/3 redo restarts at the argument it answered last: the enumeration repeats it (KILL p012, p013)", file=P, targets=TP,
         old="        argn = PL_foreign_context(PL__ctx) + 1          # (unsigned)CTX_INT + 1\n",
         new="        argn = PL_foreign_context(PL__ctx)\n"),
    dict(id="P1-A6 arg/3 leaves the bindings of a failed argument unify: the next argument sees them (KILL p174)", file=P, targets=TP,
         old="        PL_rewind_foreign_frame(ld, fid)\n        argn += 1\n",
         new="        argn += 1\n"),
    dict(id="P1-A7 arg/3 leaves a choice point on the last argument (KILL p014)", file=P, targets=TP,
         old="            if argn == arity\n                rc = true\n",
         new="            if argn == arity + 1\n                rc = true\n"),
    dict(id="P1-A8 compound_name_arity/3 on a non-compound, non-variable first argument does not raise (KILL p033, p046)", file=P, targets=TP,
         old="    if !(k == DU_CELL || k == DU_ATTVAR)                # !canBind(*p)\n        return PL_error(ld, ERR_TYPE, mk_sym(T, :compound), A1) ? FTRUE : FFALSE\n",
         new="    if false\n        return PL_error(ld, ERR_TYPE, mk_sym(T, :compound), A1) ? FTRUE : FFALSE\n"),
    dict(id="P1-A9 compound_name_arity/3 builds the compound one argument short (KILL p030, p047)", file=P, targets=TP,
         old="    f = lookupFunctorDef(ld.functors, _atom_word!(ld, name), arity)   # PL_new_functor(name, arity)\n",
         new="    f = lookupFunctorDef(ld.functors, _atom_word!(ld, name), arity == 0 ? 0 : arity - 1)\n"),
    # ── compound_name_arguments/3 (pl-prims.c:3161) ──
    dict(id="P1-N1 compound_name_arguments/3 answers an improper list as an instantiation error (KILL p067)", file=P, targets=TP,
         old="            len == -1 &&\n                return PL_error(ld, ERR_TYPE, mk_sym(T, :list), list) ? FTRUE : FFALSE\n",
         new="            len == -2 &&\n                return PL_error(ld, ERR_TYPE, mk_sym(T, :list), list) ? FTRUE : FFALSE\n"),
    dict(id="P1-N2 compound_name_arguments/3 reads the arguments of a compound one short (KILL p052, p063)", file=P, targets=TP,
         old="        for n in 1:na[2]\n            (PL_unify_list_ex(ld, l, head, l) && PL_unify_arg(ld, n, t, head)) ||\n",
         new="        for n in 1:(na[2] - 1)\n            (PL_unify_list_ex(ld, l, head, l) && PL_unify_arg(ld, n, t, head)) ||\n"),
    dict(id="P1-N3 compound_name_arguments/3 builds a compound whose arguments are not unified from the list (KILL p053)", file=P, targets=TP,
         old="            PL_unify_arg(ld, n, t, head) || return FFALSE\n            n += 1\n",
         new="            n += 1\n"),
    # ── subsumes_term/2 (pl-prims.c:3954) ──
    dict(id="P1-S1 subsumes does not test the variables of the specific term for aliasing (KILL p092)", file=P, targets=TP,
         old="                if !(k == DU_CELL || k == DU_ATTVAR) || visitedWord_cells(ld, p)\n",
         new="                if !(k == DU_CELL || k == DU_ATTVAR)\n"),
    dict(id="P1-S2 subsumes_term/2 keeps the bindings of a successful unify (KILL p079)", file=P, targets=TP,
         old="    PL_discard_foreign_frame(ld, fid)\n\n    return rc ? FTRUE : FFALSE\nend\n\n# PORT: pl-prims.c nonvar as pl_nonvar1_va",
         new="    PL_close_foreign_frame(ld, fid)\n\n    return rc ? FTRUE : FFALSE\nend\n\n# PORT: pl-prims.c nonvar as pl_nonvar1_va"),
    dict(id="P1-S3 subsumes takes the variables of the general term: f(a) subsumes f(_) (KILL p072)", file=P, targets=TP,
         old="    n, v0 = term_variables_to_termv_cells(ld, specific, typemax(Int), 0)\n",
         new="    n, v0 = term_variables_to_termv_cells(ld, general, typemax(Int), 0)\n"),
    dict(id="P1-S4 subsumes with a general term of the same variable binds the specific one: no check of the specific variable's cell kind (KILL p075)", file=P, targets=TP,
         old="                k, _, p = _deref_loc(ld, -(v0 + i + 1))     # Word p = valTermRef(v0+i); deRef(p)\n",
         new="                k, _, p = _deref_loc(ld, -(v0 + 1))\n"),
    # ── $factorize_term/3 (pl-prims.c:1485) ──
    dict(id="P1-F1 $factorize_term/3 unifies the substitutions with the template (KILL p093, p094)", file=P, targets=TP,
         old="    return PL_factorize_term(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE\n",
         new="    return PL_factorize_term(ld, PL__t0, PL__t0 + 2, PL__t0 + 1) ? FTRUE : FFALSE\n"),
    dict(id="P1-F2 $factorize_term/3 fails where the factorization succeeds (KILL p093)", file=P, targets=TP,
         old="    return PL_factorize_term(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE\n",
         new="    return PL_factorize_term(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FFALSE : FTRUE\n"),
    # ── $term_size/3 (pl-prims.c:993) ──
    dict(id="P1-Z1 term_size counts a compound without its functor cell (KILL p107, p098)", file=P, targets=TP,
         old="            count += arity + 1\n",
         new="            count += arity\n"),
    dict(id="P1-Z2 $term_size/3 fails when the size equals Max (KILL p110)", file=P, targets=TP,
         old="    c > m && return FFALSE\n",
         new="    c >= m && return FFALSE\n"),
    dict(id="P1-Z3 a float takes two cells (KILL p102)", file=P, targets=TP,
         old="    nk === NUM_FLOAT && return 3\n",
         new="    nk === NUM_FLOAT && return 2\n"),
    dict(id="P1-Z4 a rational counts the limbs of its numerator only (KILL p106)", file=P, targets=TP,
         old="        return 4 + _limbs64(numerator(r)) + _limbs64(denominator(r))\n",
         new="        return 4 + _limbs64(numerator(r))\n"),
    dict(id="P1-Z5 a wide string is sized as a narrow one (KILL p108)", file=P, targets=TP,
         old="    return (wide ? (12 + 4 * n) : (n + 9)) ÷ 8 + 2\n",
         new="    return (n + 9) ÷ 8 + 2\n"),
    dict(id="P1-Z6 an unbound Max is zero (KILL p101)", file=P, targets=TP,
         old="        m = typemax(Int)                                    # (size_t)-1\n",
         new="        m = 0\n"),
    # ── is_most_general_term/1 (pl-prims.c:3850) ──
    dict(id="P1-G1 an atom is not most general (KILL p127)", file=P, targets=TP,
         old="    (k == DU_WORD && isAtomW(w)) && return true             # isAtom(*p)\n",
         new="    (k == DU_WORD && isAtomW(w)) && return false\n"),
    dict(id="P1-G2 a list head is not marked: [X,X] is most general (KILL p129)", file=P, targets=TP,
         old="            _tv_mark!(ld, hp, true)                         # set_marked(h)\n",
         new="            nothing\n"),
    dict(id="P1-G3 a compound argument is not marked: f(X,X) is most general (KILL p131)", file=P, targets=TP,
         old="        _tv_mark!(ld, ap, true)                             # set_marked(a)\n",
         new="        nothing\n"),
    dict(id="P1-G4 the marks of a compound's arguments are left behind (KILL p145)", file=P, targets=TP,
         old="        _tv_mark!(ld, ap, false)                            # clear_marked(a)\n",
         new="        nothing\n"),
    dict(id="P1-G5 the marks of a list's heads are left behind (KILL p175)", file=P, targets=TP,
         old="                _tv_mark!(ld, hp, false)                    # clear_marked(h)\n",
         new="                nothing\n"),
    dict(id="P1-G6 a list is not tested for [] at its end: [X|T] is most general (KILL p141)", file=P, targets=TP,
         old="        (tk == DU_WORD && tw == ld.atom_nil_w) || return false   # isNil(*tail)\n",
         new="        nothing\n"),
    dict(id="P1-G7 a list is walked as a compound: [X,Y] is not most general (KILL p128)", file=P, targets=TP,
         old="    if ld.gstack[c] == ld.functor_dot2                      # t->definition == FUNCTOR_dot2\n",
         new="    if false\n"),
    # ── term_singletons/2, '$term_multitons'/2 (pl-prims.c:3741, :3752), term_variables_loop's FIRST_MASK ──
    dict(id="P1-T1 a variable met again is not recorded: every variable is a singleton (KILL p148, p162)", file=P, targets=TP,
         old="                    push!(firsts, p)                        # (*p) |= FIRST_MASK\n",
         new="                    nothing\n"),
    dict(id="P1-T2 the shared variables are the ones met once (KILL p162)", file=P, targets=TP,
         old="(isfirst && (flags & TV_SHARED) != 0)\n",
         new="(!isfirst && (flags & TV_SHARED) != 0)\n"),
    dict(id="P1-T3 term_singletons keeps the maxcount of a proper list (KILL p176)", file=P, targets=TP,
         old="    (flags & TV_SINGLETON) != 0 && (maxcount = typemax(Int))   # || (flags&TV_SINGLETON): maxcount = ~0\n",
         new="    nothing\n"),
    dict(id="P1-T4 term_singletons/2 asks for the shared variables (KILL p148)", file=P, targets=TP,
         old="        return term_variables(ld, A1, A2, 0, TV_SINGLETON) ? FTRUE : FFALSE\n",
         new="        return term_variables(ld, A1, A2, 0, TV_SHARED) ? FTRUE : FFALSE\n"),
    dict(id="P1-T5 $term_multitons/2 asks for the singleton variables (KILL p162)", file=P, targets=TP,
         old="        return term_variables(ld, A1, A2, 0, TV_SHARED) ? FTRUE : FFALSE\n",
         new="        return term_variables(ld, A1, A2, 0, TV_SINGLETON) ? FTRUE : FFALSE\n"),
    dict(id="P1-T6 term_variables never takes the first-marks path: term_singletons answers every variable (KILL p148, p162)", file=P, targets=TV,
         old="    count, v0 = if (flags & (TV_SINGLETON | TV_SHARED)) != 0\n",
         new="    count, v0 = if false\n"),
    dict(id="P1-T7 term_variables takes the first-marks path always: term_variables/2 answers no variable (KILL p148; the term_variables rows of the TV files)", file=P, targets=TV,
         old="    count, v0 = if (flags & (TV_SINGLETON | TV_SHARED)) != 0\n",
         new="    count, v0 = if true\n"),
    dict(id="P1-T8 a singleton variable is kept when it is a first: the filter is inverted for TV_SINGLETON (KILL p148)", file=P, targets=TP,
         old="            if (!isfirst && (flags & TV_SINGLETON) != 0) ||",
         new="            if (isfirst && (flags & TV_SINGLETON) != 0) ||"),
]
