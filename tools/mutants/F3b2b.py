# ORIGINAL: F3b2's mutant list — no swipl-devel counterpart.
# tools/mutants/F3b2b.py — the mutation battery of F3B step f3b-2's second landing (D-0095 item 4, 2026-10-22):
# the decompiler in upstream's shape — the head unified top-down into cells, the body built on words, the
# clause's variables term references (pl-comp.c 5790-7155 at 8e1bc111; design: lk-channel
# evidence/f3b-2/decompiler_design.md, "Refinement"). Run ONCE, at the step's close, in CI
# (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's. The compare/varName mutants are F3b2a's.
#
# EQUIVALENT, with the code reason (src/pl-comp.jl at the f3b-2b commit):
#   FD2 — every `build_term!` caller passes the default `dir` -1 (pl-comp.jl:3776-3970); upstream's `dir` 1
#         callers (BUILD_TERM_REV: A_ADD, A_MUL, A_FUNC*) are NOT PORTED (decompileBodyNoShift's header).
#   FD8 — a NEXTARG past the last argument is always followed by the pair's reset before any read: H_POP's
#         `PL_reset_term_refs(argp)`, the exit's (whose loop runs only while `argn < arity`), or the end of
#         an H_VOID_N run; an R-form reads the pair at the LAST argument, reached by the NEXTARG before it.
#   FD10 — every `var` unifyVar gets is a global cell this decompilation allocated (build_term!'s compound,
#         `_dput_functor!`'s, vbody's fresh cell), younger than every cell a clause variable dereferences
#         to (its own cell from `PL_new_term_refs`, or an older one it was bound to: the caller's head cells,
#         a running frame's), so `pv < p` holds on every call and the undereferenced `-(slot) < var` takes the
#         same branch. The claim is asserted in unifyVar (`pv > 0 && p > 0`, `pv < p`; D-0100) and FD12
#         (the assert flipped) is caught by it firing.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/compile/test_decompile.jl",
    "test/compile/test_body_code_swipl.jl",
    "test/db/test_clause_variables.jl",
    "test/db/test_db.jl",           # retract/1, retractall/1, clause/2 through index_testlib.jl
    "test/db/test_index_swipl.jl",  # the same against swipl, clause/2 and retract/1 on bound arguments
    "test/core_lang/test_expr_functor.jl",  # Q2: `$expr/n` heads through the decompiler
]
CMP = "src/pl-comp.jl"
MUTANTS = [
    # unifyVar (pl-comp.c 5884): two unbound cells, the younger bound to the older (`v < var`); seen by the
    # order of two decompiled body variables against swipl and their printed names (obligation 1)
    dict(id="FD1 unifyVar binds the older cell to the younger", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="        if pv < p                                               # v < var\n",
         new="        if pv > p                                               # v < var\n"),
    # build_term (7114): `dir` 1 fills the arguments first to last — EQUIVALENT (above)
    dict(id="FD2 build_term! ignores dir", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="    a = dir == 1 ? a + 1 : a + arity                            # now a points to last argument\n",
         new="    a = a + arity                                               # now a points to last argument\n",
         equivalent="src/pl-comp.jl build_term! callers (decompileBodyNoShift!, decompileBody!): every one passes the default dir -1; the BUILD_TERM_REV callers (A_ADD, A_MUL, A_FUNC*) are NOT PORTED"),
    # set_bvar_argp (5849): a moved argument's output goes to bvar_args, argp redirected to the fresh cell
    dict(id="FD3 the moved argument is not redirected to bvar_args", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="                argp = t2\n                write_bvar = true\n",
         new="                write_bvar = true\n"),
    # decompileBodyNoShift var_common (6526): nested -> unifyVar into the argument cell at once
    dict(id="FD4 a variable inside a body compound written as a var-ref word", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="        unifyVar(di.ld, di.argpos, di.variables, index) ||\n"
             "            error(\"Decompiler: unifyVar failed\")\n"
             "        di.argpos += 1                                          # ARGP++\n",
         new="        _dpush!(di, makeVarRef(index))\n"),
    # decompile_head H_VOID (6071): only an UNPUSHED void unifies with its argument's slot variable
    dict(id="FD5 a void inside a head compound given the argument's slot variable", file=CMP,
         targets=["test/compile/test_decompile.jl", "test/db/test_clause_variables.jl"],
         old="        elseif c == H_VOID\n            if pushed == 0                                      # FIRSTVAR in the head\n",
         new="        elseif c == H_VOID\n            if pushed >= 0                                      # FIRSTVAR in the head\n"),
    # moved_unifications (6216): every set bit, the last one too (`i <= last`)
    dict(id="FD6 moved_unifications! skips the last moved argument", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="    for i in 0:last\n",
         new="    for i in 0:(last - 1)\n"),
    # decompile_head (5955): PL_unify_functor(head, functor); a head of another functor fails
    dict(id="FD7 the head's functor not unified", file=CMP,
         targets=["test/compile/test_decompile.jl"],
         old="        PL_unify_compound(ld, head, f) || return false\n",
         new="        true || return false\n"),
    # next_arg_ref (5836): no step past the last argument — EQUIVALENT (above)
    dict(id="FD8 next_arg_ref steps past the last argument", file=CMP,
         targets=["test/compile/test_decompile.jl"],
         old="    if ld.slots[argp + 1] != ld.slots[argp + 2]\n",
         new="    if true\n",
         equivalent="src/pl-comp.jl decompile_head!: a NEXTARG past the last argument is followed by H_POP's PL_reset_term_refs, the exit (its loop runs only while argn < arity) or the end of an H_VOID_N run before any read of the pair"),
    # the callers' clause search on the head's argument cells (`argTermP(*p, 0)` of the head's compound): the
    # index handed a copy of the cells ROTATED by one, argument i keyed by argument i+1. (A plain `+ 1` shift
    # reads past the compound: the precompile workload's clause/2 crashes and the battery gets no verdict —
    # its first run, 2026-10-22.)
    dict(id="FD9 clause/2 and retract/1 index on the wrong cells", file=CMP,
         targets=["test/db/test_index_swipl.jl", "test/db/test_db.jl"],
         old="        return argv_cells(ld, valPtr(w))\n",
         new="        q = valPtr(w); n = arityFunctor(ld.functors, ld.gstack[q])\n"
             "        a = _alloc_compound!(ld, ld.gstack[q], n)\n"
             "        for i in 1:n; ld.gstack[a + i] = ld.gstack[q + 1 + i % n]; end\n"
             "        return argv_cells(ld, a)\n"),
    # unifyVar's claim (design "Obligations" 1): the locations compared before `_deref_loc` — EQUIVALENT (above)
    dict(id="FD10 unifyVar compares the undereferenced locations", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl"],
         old="        if pv < p                                               # v < var\n",
         new="        if -(variables + Int(i) + 1) < var                      # v < var\n",
         equivalent="src/pl-comp.jl unifyVar callers (_dvar!, build_term!, decompileBody!): var is always a global cell allocated by this decompilation, younger than any cell a clause variable dereferences to, so pv < p always and -(slot) < var takes the same branch"),
    # unifyVar's invariant (audit D-0100): the clause variable's cell is the older — the assert flipped must fire
    dict(id="FD12 unifyVar's invariant assert flipped", file=CMP,
         targets=["test/compile/test_body_code_swipl.jl", "test/compile/test_decompile.jl"],
         old='        @assert pv < p "unifyVar: the clause variable\'s cell younger than the one bound"',
         new='        @assert pv > p "unifyVar: the clause variable\'s cell younger than the one bound"'),
    # Q2 in the head decompiler (`_head_compound!`): `$expr/n` against a compound of n children, child by child
    dict(id="FD11 the head decompiler drops Q2", file=CMP,
         targets=["test/core_lang/test_expr_functor.jl"],
         old="    a = _alloc_compound!(ld, f, arityFunctor(ld.functors, f))\n    tmp = PL_new_term_ref(ld)\n",
         new="    return 0\n    a = _alloc_compound!(ld, f, arityFunctor(ld.functors, f))\n    tmp = PL_new_term_ref(ld)\n"),
]
