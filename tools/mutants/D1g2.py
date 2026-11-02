# ORIGINAL: D1g's mutant list — the swipl-devel counterpart is src/pl-comp.c (clause/3 by reference), the Julia port src/pl-comp.jl.
# tools/mutants/D1g.py — the two D1f mutants that F1b (set_prolog_flag: iso and protect_static_code settable) changes, run at the
# gate of landing B (D-0291 item 2c): D1-95 (the by-reference branch of clause/3 no longer refuses a protected predicate) was declared
# equivalent while both flags were constants; row sf80 of test/core_lang/test_set_flag_swipl.jl kills it now. D1-96 stays declared
# equivalent, with its argument re-read against the migrated tree (the iso flag enters protected_predicate only).
# Same format as D1f.py (`id`, `file`, `old`, `new`, optional `equivalent` and `targets`).
T = ["test/db/test_clause_ref_swipl.jl", "test/db/test_assert_swipl.jl", "test/db/test_retract_swipl.jl",
     "test/db/test_retractall_swipl.jl", "test/core_lang/test_blob.jl", "test/files/test_load_swipl.jl"]
T8 = T + ["test/db/test_clause_swipl.jl", "test/core_lang/test_module_path.jl"]
TARGETS = T8 + ["test/core_lang/test_set_flag_swipl.jl"]
K = "src/pl-comp.jl"
MUTANTS = [
    dict(id="D1-95 the by-reference branch refuses a protected predicate no more (KILL sf80 of test_set_flag_swipl.jl, since F1b)", file=K, targets=T8 + ["test/core_lang/test_set_flag_swipl.jl"],
         old='''                protected_predicate(gd, ld, rcl.predicate) && return FFALSE
''',
         new=''''''),
    dict(id="D1-96 the by-reference clause type is not compared with the term's", file=K, targets=T8,
         old='''                (rcl.flags & CLAUSE_TYPE_MASK) != hflags && return FFALSE
''',
         new='''''',
         equivalent="the term is built by _rule_term from the clause's own flags (src/pl-comp.jl:3786-3790): UNIT_CLAUSE gives the bare "
                    "head (get_head_and_body_clause answers UNIT_CLAUSE for a non-neck, :3981), otherwise the neck of clause_functor "
                    "(:3770-3777), whose SSU bits is_neck reads back (:3948-3952); the compiler sets UNIT_CLAUSE only for a clause without "
                    "an SSU neck (:3205-3209, row c37: `e(1) => true` is SSU_COMMIT without UNIT_CLAUSE), so hflags == (flags & CLAUSE_TYPE_MASK) "
                    "always. No flag F1b made settable (iso, protect_static_code) enters this path: they decide protected_predicate "
                    "(:3564-3572), the line before"),
]
