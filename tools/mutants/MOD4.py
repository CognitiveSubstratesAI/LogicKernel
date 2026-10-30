# ORIGINAL: MOD4's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD4.py — the mutation battery of MOD4 (meta-predicate qualification: pl-vmi.c S_MQUAL, S_LMQUAL;
# pl-wam.c m_qualify_argument, mustBeCallable, callCleanupHandler's module; pl-supervisor.c chainPredicateSupervisor's
# S_MQUAL/S_LMQUAL prefix; pl-proc.c isTransparentMetamask, meta_declaration; the stand-ins' meta_predicate masks,
# `_boot_meta!` after boot/init.pl, boot/bags.pl, boot/attvar.pl, library/when.pl), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD2.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Killed by test/core_lang/test_meta_predicate_swipl.jl (rows named in each id's KILL).
# TARGETS (D-0238): S_MQUAL runs in front of every transparent meta-predicate (call/N, catch/3, findall/3,4, bagof/3,
# setof/3, the cleanup family, freeze/2, when/2, call_residue_vars/2), so the qualification mutants target EVERY test
# file that calls one (TS_ALL: the test files whose text names one of them; test/test_gate_split.jl left out, its
# `call(` is Julia's). meta_declaration and isTransparentMetamask are reached only through meta_predicate/1 and
# mode/1 (src/pl-proc.jl:1346, :1361, :1364): TS_MP. The meta_predicate file is first: a kill decides there.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once).
# NOT LISTED (each with its reason):
#   * m_qualify_argument's depth check deleted (`depth == 0 && !is_acyclic_cells`): the walk over a cyclic `a:a:...`
#     chain never ends (src/pl-wam.jl:1054-1071, the loop's only exit on a cycle) — a HANG, not a verdict; Q5 below
#     mutates the error the check raises instead.
TS_MP = ["test/core_lang/test_meta_predicate_swipl.jl"]
TS_ALL = TS_MP + [
    "test/core_lang/test_context_module_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_findall_swipl.jl",
    "test/core_lang/test_bagof_swipl.jl",
    "test/core_lang/test_colon_body_swipl.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_attvar_store.jl",
    "test/core_lang/test_exception.jl",
    "test/core_lang/test_metacall.jl",
    "test/core_lang/test_metacall_control.jl",
    "test/core_lang/test_module_swipl.jl",
    "test/core_lang/test_ssu_swipl.jl",
    "test/core_lang/test_rules_swipl.jl",
    "test/core_lang/test_sortlist_swipl.jl",
    "test/charset/test_umap_swipl.jl",
    "test/compile/test_body_code_swipl.jl",
    "test/compile/test_ssu_compile_swipl.jl",
    "test/core_lang/test_arith_swipl.jl",
    "test/core_lang/test_assert_cells.jl",
    "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_ball_cells.jl",
    "test/core_lang/test_between_swipl.jl",
    "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_cyclic_term_swipl.jl",
    "test/core_lang/test_fli_unify_cells.jl",
    "test/core_lang/test_fli_words.jl",
    "test/core_lang/test_goal_clause.jl",
    "test/core_lang/test_hash.jl",
    "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_numbervars_cells.jl",
    "test/core_lang/test_occurs_cells.jl",
    "test/core_lang/test_op_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_read_swipl.jl",
    "test/core_lang/test_repeat_swipl.jl",
    "test/core_lang/test_same_term_swipl.jl",
    "test/core_lang/test_slot_words.jl",
    "test/core_lang/test_softcut.jl",
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
    "test/core_lang/test_sys_swipl.jl",
    "test/core_lang/test_unify_swipl.jl",
    "test/core_lang/test_write_cells.jl",
    "test/core_lang/test_zero_exports.jl",
    "test/core_text/test_atom_text_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_text/test_read.jl",
    "test/core_text/test_read_term_swipl.jl",
    "test/core_text/test_roundtrip_swipl.jl",
    "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_write_swipl.jl",
    "test/db/test_assert_swipl.jl",
    "test/db/test_clause_swipl.jl",
    "test/db/test_db.jl",
    "test/db/test_index_swipl.jl",
    "test/db/test_jit.jl",
    "test/db/test_retractall_swipl.jl",
    "test/db/test_retract_swipl.jl",
    "test/db/test_update_view_gc.jl",
    "test/files/test_load_swipl.jl",
    "test/foreign/test_builtins_swipl.jl",
    "test/foreign/test_query.jl",
    "test/foreign/test_typetests_swipl.jl",
]
TARGETS = TS_ALL                                     # the baseline's targets (mutate_ci.py plan reads TARGETS)
W = "src/pl-wam.jl"
S = "src/pl-supervisor.jl"
P = "src/pl-proc.jl"
E = "src/pl-ext.jl"
# The cleanup goal at I_CALLCLEANUP is always `Module:Goal` with an atom Module and a callable Goal: every cleanup frame
# is made by I_CALLCLEANUP (src/pl-wam.jl:3622), which first passes the LAST argument through mustBeCallable
# (src/pl-wam.jl:3614); that argument is declared `0` in every member of the cleanup family (src/pl-ext.jl:267-268), so
# S_MQUAL/S_LMQUAL (src/pl-supervisor.jl:232-239) have made it `Context:Goal` (src/pl-wam.jl:1046-1051) or kept an
# existing `M:G` (src/pl-wam.jl:1052-1072) before the clause body runs. A user clause that runs `'$call_cleanup'`
# itself (no meta declaration) is the one other way in: there mustBeCallable rejects the unqualified cleanup goal
# before any cleanup frame exists (row a25, swipl's answer type_error(callable, true)), so the handler still only
# ever sees `Module:Goal` — C1 stays equivalent, C2 is killed by a25.
_CLEANUP_QUALIFIED = ("every cleanup frame passed mustBeCallable first (src/pl-wam.jl:3614, :3622), so the cleanup "
                      "goal the handler calls is always `Module:Goal` with an atom Module (src/pl-wam.jl:1098-1118)")
MUTANTS = [
    # ── pl-wam.c m_qualify_argument ──
    dict(id="MOD4-Q1 m_qualify_argument builds Context:Arg but does not store it: an unqualified argument stays bare (KILL a01-a06, a11, a17, a22)", file=W, targets=TS_ALL,
         old="        ld.slots[i] = consPtr(p2, TAG_COMPOUND | STG_GLOBAL)    # *k = consPtr(p2, STG_GLOBAL|TAG_COMPOUND)\n",
         new="        nothing\n"),
    dict(id="MOD4-Q2 m_qualify_argument qualifies with user, not the frame's context module (KILL a01-a06: m2)", file=W, targets=TS_ALL,
         old="        ld.gstack[p2 + 1] = _atom_word!(ld, gd.modules[contextModule(gd, ld, fr)].atom)  # p2[1] = contextModule(fr)->name\n",
         new="        ld.gstack[p2 + 1] = _atom_word!(ld, gd.modules[MODULE_user(gd).index].atom)\n"),
    dict(id="MOD4-Q3 m_qualify_argument never walks an a:b:g chain: the outer qualifier is kept (KILL a13, a14, a16)", file=W, targets=TS_ALL,
         old="                w = aw                              # p = ap\n",
         new="                break\n"),
    dict(id="MOD4-Q4 m_qualify_argument walks past a non-atom qualifier: V:m1:x becomes m1:x (KILL a15)", file=W, targets=TS_ALL,
         old="                (mk == DU_WORD && isAtomW(mw)) || break     # if (! isAtom(*a1)) break\n",
         new="                nothing\n"),
    dict(id="MOD4-Q5 a cyclic qualifier chain raises type_error(callable, _), not acyclic_term (KILL a19)", file=W, targets=TS_ALL,
         old="                    PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), t)\n",
         new="                    PL_error(ld, ERR_TYPE, mk_sym(T, :callable), t)\n"),
    # ── pl-vmi.c S_MQUAL, S_LMQUAL ──
    dict(id="MOD4-Q6 S_MQUAL ignores m_qualify_argument's failure: a cyclic chain in a non-last meta argument does not throw there (KILL a24)", file=W, targets=TS_ALL,
         old="    mq_rc || @goto b_throw                          # if ( !rc ) THROW_EXCEPTION\n",
         new="    nothing\n"),
    dict(id="MOD4-Q7 S_LMQUAL ignores m_qualify_argument's failure (KILL a19)", file=W, targets=TS_ALL,
         old="    lmq_rc || @goto b_throw                         # if ( !rc ) THROW_EXCEPTION\n",
         new="    nothing\n"),
    dict(id="MOD4-Q8 S_LMQUAL does not reset the frame's context to its predicate's module (KILL a10, b01, b02)", file=W, targets=TS_ALL,
         old="    setContextModule!(ld.frames[FR], (ld.frames[FR].predicate::Definition{T}).module_)  # setContextModule(FR, FR->predicate->module)\n",
         new="    nothing\n"),
    # ── pl-supervisor.c chainPredicateSupervisor ──
    dict(id="MOD4-S1 chainPredicateSupervisor qualifies every argument of a transparent meta-predicate, `?`/`+`/`-` too (KILL a01, a10, catch/3's catcher)", file=S, targets=TS_ALL,
         old="                if MA_NEEDS_TRANSPARENT(ma)\n                    loffset = length(codes)",
         new="                if true\n                    loffset = length(codes)"),
    dict(id="MOD4-S2 chainPredicateSupervisor never emits S_LMQUAL: no context reset after the last qualification (KILL a10, b01, b02)", file=S, targets=TS_ALL,
         old="                codes[loffset + 1] = S_LMQUAL       # baseBuffer(&buf, code)[loffset] = encode(S_LMQUAL)\n",
         new="                nothing\n"),
    # ── pl-proc.c isTransparentMetamask, meta_declaration (reached only through meta_predicate/1, mode/1) ──
    dict(id="MOD4-T1 isTransparentMetamask never answers true: a declared meta-predicate is not transparent (KILL a01-a06, white-box P_TRANSPARENT)", file=P, targets=TS_MP,
         old="        if MA_NEEDS_TRANSPARENT(ma)\n            transparent = true\n",
         new="        if MA_NEEDS_TRANSPARENT(ma)\n            transparent = false\n"),
    dict(id="MOD4-M1 meta_declaration accepts 10 as a meta-argument specifier (KILL e01)", file=P, targets=TS_MP,
         old='            e > 9 && return PL_domain_error(ld, "meta_argument_specifier", arg)\n',
         new='            e > 10 && return PL_domain_error(ld, "meta_argument_specifier", arg)\n'),
    dict(id="MOD4-M2 meta_declaration reads `:` as `?`: the argument is not qualified (KILL a06, a20-a23)", file=P, targets=TS_MP,
         old="            elseif mk == sym_key(mk_sym(T, :(:)))\n                MA_META\n",
         new="            elseif mk == sym_key(mk_sym(T, :(:)))\n                MA_ANY\n"),
    dict(id="MOD4-M3 mode/1 accepts the meta-only specifiers (KILL e08: domain_error(mode, :))", file=P, targets=TS_MP,
         old='            elseif !ismeta\n                return PL_domain_error(ld, "mode", arg)\n',
         new='            elseif false\n                return PL_domain_error(ld, "mode", arg)\n'),
    dict(id="MOD4-M4 meta_predicate/1 on a compound specifier raises type_error(mode, _) (KILL e03)", file=P, targets=TS_MP,
         old='            return PL_type_error(ld, "meta_argument_specifier", arg)\n',
         new='            return PL_type_error(ld, "mode", arg)\n'),
    # ── the stand-ins' masks (pl-ext.jl _boot_meta!) ──
    dict(id="MOD4-B1 call/2 declared call(?,?): not transparent, its goal is not qualified (KILL b02)", file=E, targets=TS_ALL,
         old='("call", 2, "1?")',
         new='("call", 2, "??")'),
    dict(id="MOD4-B2 bagof/3 declared bagof(?,0,-) for bagof(?,^,-)", file=E, targets=TS_ALL,
         old='("bagof", 3, "?^-")',
         new='("bagof", 3, "?0-")',
         equivalent="MA_HAT and 0 are read alike: every reader of a mask is MA_NEEDS_TRANSPARENT (src/pl-incl.jl:300, true "
                    "for both; src/pl-supervisor.jl:232, src/pl-proc.jl:1418) or the MA_VAR test (src/pl-proc.jl:982); "
                    "m_qualify_argument reads no mask (src/pl-wam.jl:1041-1075)"),
    # ── pl-wam.c callCleanupHandler, mustBeCallable ──
    dict(id="MOD4-C1 callCleanupHandler calls the cleanup goal in user, not the frame's context", file=W, targets=TS_ALL,
         old="                rval = call_term(gd, ld, contextModule(gd, ld, fr), clean)  # call_term(contextModule(fr), clean)\n",
         new="                rval = call_term(gd, ld, MODULE_user(gd).index, clean)\n",
         equivalent=_CLEANUP_QUALIFIED + "; call_term's module is the default of an unqualified goal only, a `Module:Goal` "
                    "runs in Module"),
    dict(id="MOD4-C2 mustBeCallable accepts a goal that is not `_:_` (MOD2's interim acceptance back) (KILL a25)", file=W, targets=TS_ALL,
         old=('    _is_colon2_word(ld, k, w) ||                            # !hasFunctor(*p, FUNCTOR_colon2)\n'
              '        return PL_error(ld, ERR_TYPE, mk_sym(T, :callable), call)\n'),
         new="    _is_colon2_word(ld, k, w) || return true\n"),
]
