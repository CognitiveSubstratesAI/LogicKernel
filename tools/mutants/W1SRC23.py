# W1SRC23: a COPY of W1SRC2.py at eb9cf64a00967fbb3127adf02936dada370f1d3e under a new ref name (audit D-0929 (5)); nothing else changed.
# ORIGINAL: W1-SRC2's mutant list — no swipl-devel counterpart.
# tools/mutants/W1SRC2.py — mutation battery of the generic get_procedure of pl-proc.c (every mode; get_module_how; GP_TYPE_QUIET
# in get_functor_procedure), run ONCE, in CI. The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent`, `targets`. NOT RUN YET (written edit-only, 2026-11-15): the verdict column is what the rows are
# DESIGNED to kill.
# TARGETS (D-0238): the FIND/FINDHERE/CREATE/RESOLVE/EXISTENCE_ERROR arms are reached ONLY by the white-box testset of
# test/db/test_clause_swipl.jl (no kernel caller uses the generic function for them: the split get_procedure_* functions are theirs).
# The GP_DEFINE arm, get_functor and the module rule are also reached by `'$set_predicate_attribute'/3`, meta_predicate/1 and
# `'$wrap_predicate'/5` (test_meta_predicate_swipl.jl, test_load_swipl.jl, test_wrap_swipl.jl, test_det_swipl.jl,
# test_autoload_flag_swipl.jl, test_debug_flag_swipl.jl); get_functor_procedure is also the split get_procedure_namearity's and
# get_procedure_resolve_namearity's (test_nth_clause_swipl.jl: compile_predicates/1, '$end_aux'/2; test_event_swipl.jl).
TC = ["test/db/test_clause_swipl.jl"]
TD = TC + [
    "test/core_lang/test_meta_predicate_swipl.jl", "test/files/test_load_swipl.jl", "test/core_lang/test_wrap_swipl.jl",
    "test/core_lang/test_det_swipl.jl", "test/core_lang/test_autoload_flag_swipl.jl", "test/core_lang/test_debug_flag_swipl.jl",
]
TF = TC + ["test/db/test_nth_clause_swipl.jl", "test/core_lang/test_event_swipl.jl", "test/core_lang/test_meta_predicate_swipl.jl"]
P = "src/pl-proc.jl"
# the union of every mutant's `targets` (mutate_ci.py plan and the pre-push hook read TARGETS; audit D-0834 era, R2 gate)
TARGETS = [
    "test/db/test_clause_swipl.jl",
    "test/core_lang/test_meta_predicate_swipl.jl",
    "test/files/test_load_swipl.jl",
    "test/core_lang/test_wrap_swipl.jl",
    "test/core_lang/test_det_swipl.jl",
    "test/core_lang/test_autoload_flag_swipl.jl",
    "test/core_lang/test_debug_flag_swipl.jl",
    "test/db/test_nth_clause_swipl.jl",
    "test/core_lang/test_event_swipl.jl",
]
MUTANTS = [
    # ---- get_module_how
    dict(id="W1-1 a GP_DEFINE qualifier names an existing module only", file=P, targets=TD,
         old='''        if hm == GP_CREATE || hm == GP_DEFINE
            return lookupModule''',
         new='''        if hm == GP_CREATE
            return lookupModule'''),
    dict(id="W1-2 a GP_CREATE qualifier names an existing module only", file=P, targets=TC,
         old='''        if hm == GP_CREATE || hm == GP_DEFINE
            return lookupModule''',
         new='''        if hm == GP_DEFINE
            return lookupModule'''),
    dict(id="W1-3 a GP_FIND qualifier creates its module", file=P, targets=TC,
         old='''            m = isCurrentModule(gd.modules, _atom_value(ld, mname))
            return m === nothing ? MODULE_user(gd) : m''',
         new='''            m = lookupModule(gd, _atom_value(ld, mname))
            return m === nothing ? MODULE_user(gd) : m'''),
    dict(id="W1-4 a missing module is `system`, not `user`", file=P, targets=TC,
         old='''            return m === nothing ? MODULE_user(gd) : m''',
         new='''            return m === nothing ? MODULE_system(gd) : m'''),
    dict(id="W1-5 an unqualified term outside a frame is looked up in `system`", file=P, targets=TC,
         old='''    return MODULE_user(gd)
end

# PORT: pl-proc.c get_procedure
''',
         new='''    return MODULE_system(gd)
end

# PORT: pl-proc.c get_procedure
'''),
    # ---- get_procedure
    dict(id="W1-6 GP_NAMEARITY is ignored", file=P, targets=TD,
         old='''    if (how & GP_NAMEARITY) != 0
        name, arity, mi = get_functor(''',
         new='''    if false
        name, arity, mi = get_functor('''),
    dict(id="W1-7 get_functor is not told GF_PROCEDURE: no arity limit", file=P, targets=TC,
         old='''descr, 0, h, GF_PROCEDURE | (how & GP_TYPE_QUIET)''',
         new='''descr, 0, h, (how & GP_TYPE_QUIET)'''),
    dict(id="W1-8 get_functor is not told GP_TYPE_QUIET", file=P, targets=TC,
         old='''descr, 0, h, GF_PROCEDURE | (how & GP_TYPE_QUIET)''',
         new='''descr, 0, h, GF_PROCEDURE'''),
    dict(id="W1-9 the plain head is not put into h", file=P, targets=TC,
         old='''        h != 0 && PL_put_term(ld, h, head)                          # if ( h ) PL_put_term(h, head)''',
         new='''        false && PL_put_term(ld, h, head)                          # if ( h ) PL_put_term(h, head)'''),
    dict(id="W1-10 get_head_functor is not told GP_TYPE_QUIET", file=P, targets=TC,
         old='''        name, arity = get_head_functor(ld, head, how)
        arity < 0 && return nothing
    end

    hm = how''',
         new='''        name, arity = get_head_functor(ld, head, 0)
        arity < 0 && return nothing
    end

    hm = how'''),
    dict(id="W1-11 GP_CREATE only looks the procedure up", file=P, targets=TC,
         old='''        return lookupBodyProcedure(gd, name, arity, m)
    elseif hm == GP_DEFINE''',
         new='''        return isCurrentProcedure(sym_key(name), arity, m)
    elseif hm == GP_DEFINE'''),
    dict(id="W1-12 GP_DEFINE only looks the procedure up", file=P, targets=TD,
         old='''        return lookupProcedureToDefine(gd, ld, name, arity, m)      # nothing: the permission error is raised''',
         new='''        return isCurrentProcedure(sym_key(name), arity, m)      # nothing: the permission error is raised'''),
    dict(id="W1-13 GP_RESOLVE creates nothing", file=P, targets=TC,
         old='''        return resolveProcedure(gd, name, arity, m)                 # creates an undefined one: no notfound''',
         new='''        return visibleProcedure(gd, name, arity, m)                 # creates an undefined one: no notfound'''),
    dict(id="W1-14 GP_FINDHERE sees the super modules", file=P, targets=TC,
         old='''    p = if hm == GP_FINDHERE
        isCurrentProcedure(sym_key(name), arity, m)''',
         new='''    p = if hm == GP_FINDHERE
        visibleProcedure(gd, name, arity, m)'''),
    dict(id="W1-15 GP_FIND sees its own module only", file=P, targets=TC,
         old='''    elseif hm == GP_FIND
        visibleProcedure(gd, name, arity, m)''',
         new='''    elseif hm == GP_FIND
        isCurrentProcedure(sym_key(name), arity, m)'''),
    dict(id="W1-16 GP_EXISTENCE_ERROR raises nothing", file=P, targets=TC,
         old='''    if (how & GP_EXISTENCE_ERROR) != 0                              # notfound:''',
         new='''    if false                                                        # notfound:'''),
    dict(id="W1-17 the existence error names the functor, not the term", file=P, targets=TC,
         old='''    if (how & GP_EXISTENCE_ERROR) != 0                              # notfound:
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), descr)''',
         new='''    if (how & GP_EXISTENCE_ERROR) != 0                              # notfound:
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), PL_new_term_ref(ld))'''),
    dict(id="W1-18 a mode of no case answers nothing, not the C's assert(0)", file=P, targets=TC,
         old='''        error("get_procedure: unknown mode $hm (assert(0) upstream)")''',
         new='''        nothing'''),
    # ---- get_functor_procedure: GP_TYPE_QUIET
    dict(id="W1-19 GP_TYPE_QUIET is ignored by get_functor_procedure", file=P, targets=TF,
         old='''        (how & GP_TYPE_QUIET) == 0 &&           # if ( how & GP_TYPE_QUIET ) return false''',
         new='''        true &&           # if ( how & GP_TYPE_QUIET ) return false'''),
    dict(id="W1-20 GP_TYPE_QUIET is inverted in get_functor_procedure", file=P, targets=TF,
         old='''        (how & GP_TYPE_QUIET) == 0 &&           # if ( how & GP_TYPE_QUIET ) return false''',
         new='''        (how & GP_TYPE_QUIET) != 0 &&           # if ( how & GP_TYPE_QUIET ) return false'''),
]
