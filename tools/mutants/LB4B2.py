# ORIGINAL: LB4 b2's mutant list — no swipl-devel counterpart (the booted constructor, load_file!'s shape and the test-side kill rows are the kernel's own; the ported pieces cite their upstream lines in src).
# tools/mutants/LB4B2.py — the mutation battery of LB4 b2 (the atomic boot): src/pl-qlf.jl `boot_global_data` and
# `_qlf_pl_write!` (pl-qlf.c:3220-3238 `pl_write(term)`), src/pl-global.jl `PL_global_data{T}()` the template's copy,
# src/gd_template.jl the registry's default build, src/pl-error.jl printMessage (pl-error.c printMessage, swipl-devel
# cbf4e189), src/pl-comp.jl the compiler's read of the global variable `$variable_names`, src/pl-wam.jl `load_file!`
# (status, ball) and b_throw_resume's unwind(_) branch (pl-vmi.c:5266-5278 at the pin), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD4.py): `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Verdicts: written by the battery,
# not yet run. The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the writer
# had no daemon): RE-FIT any that fmt rewraps. Every `old` was checked to occur exactly once at the writer's commit (a
# `python3 -I` text count). NOTHING here has run on the kernel: each KILL names the row EXPECTED to kill it.
# The deletions of b2 (boot/init.jl, the `_boot_*!` stand-ins of src/pl-ext.jl, `ld.variable_names`) remove code: no
# mutant mutates code that is gone; the boot that replaces them is mutated at its entry (Q1, G1, G2).
# NOT LISTED (each with its reason):
#   * boot_global_data's H11 check (`after == empty_at || error(...)`) and the check of boot_from_source!'s result
#     (Q1 mutates the call itself): guards on invariants a correct boot keeps; a mutant that drops one changes nothing a
#     test sees unless the boot is broken, which no row can make it be without another mutant. A guard proved by the
#     boot run (G9), recorded here instead of as two certain survivors.
#   * printMessage's `in_print_message >= OK_RECURSIVE * 3` fatal error and the `saveWakeup` failure exit: reached
#     only by 30 nested print_message/2 calls or a failing foreign-frame open; no row reaches either.
#   * b_throw_resume's emergency-space check before the wrap (`has_emergency_space_global(ld, 3) || error(...)`): the
#     global stack is never that full in a test.
# TARGETS (audit D-0238): since b2 EVERY database is a copy of the booted template (`PL_global_data{T}()`), so the boot
# mutants (Q1, G1, G2) run in every test file that makes a database (TBOOT: the test files whose text constructs one,
# directly or through test/core_lang/rules_common.jl or test/db/index_testlib.jl, or boots: 145 of the 170, plus
# test/foreign/test_readme_example.jl, which runs README.md's code). printMessage is reached by every message any of
# them prints, `$variable_names` by every clause compiled with a warning, load_file! by every file it loads and
# b_throw_resume by every catch/3: the same list, each mutant's deciding files first (a kill decides there; the
# driver stops at the first kill, run_targets).
TBOOT = [
    "test/db/test_boot_image_swipl.jl",
    "test/db/test_boot_clauses_swipl.jl",
    "test/db/test_boot_messages_swipl.jl",
    "test/files/test_load_swipl.jl",
    "test/compile/test_analyse_variables_swipl.jl",
    "test/compile/test_body_code_swipl.jl",
    "test/compile/test_call_operands.jl",
    "test/compile/test_compiler_warnings_swipl.jl",
    "test/compile/test_decompile.jl",
    "test/compile/test_head_code_swipl.jl",
    "test/compile/test_portable_smallint_swipl.jl",
    "test/compile/test_ssu_compile_swipl.jl",
    "test/core_lang/test_acyclic_cells.jl",
    "test/core_lang/test_arg_body_swipl.jl",
    "test/core_lang/test_argvar_order_swipl.jl",
    "test/core_lang/test_arith_cells.jl",
    "test/core_lang/test_arith_swipl.jl",
    "test/core_lang/test_assert_cells.jl",
    "test/core_lang/test_at_body_swipl.jl",
    "test/core_lang/test_atom_table.jl",
    "test/core_lang/test_atom_words.jl",
    "test/core_lang/test_attvar_store.jl",
    "test/core_lang/test_attvar_wakeup.jl",
    "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_bagof_swipl.jl",
    "test/core_lang/test_ball_cells.jl",
    "test/core_lang/test_between_swipl.jl",
    "test/core_lang/test_bindings.jl",
    "test/core_lang/test_bips.jl",
    "test/core_lang/test_blob.jl",
    "test/core_lang/test_bootpred_swipl.jl",
    "test/core_lang/test_builtins_cells.jl",
    "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl",
    "test/core_lang/test_colon_body_swipl.jl",
    "test/core_lang/test_compare_cells.jl",
    "test/core_lang/test_compound_cells.jl",
    "test/core_lang/test_constant_words.jl",
    "test/core_lang/test_context_module_swipl.jl",
    "test/core_lang/test_copyterm_cells.jl",
    "test/core_lang/test_copyterm_swipl.jl",
    "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_cyclic_term_swipl.jl",
    "test/core_lang/test_declare_destroy_swipl.jl",
    "test/core_lang/test_default_term.jl",
    "test/core_lang/test_det_swipl.jl",
    "test/core_lang/test_exception.jl",
    "test/core_lang/test_export_import_swipl.jl",
    "test/core_lang/test_expr_functor.jl",
    "test/core_lang/test_findall_swipl.jl",
    "test/core_lang/test_firstvar_swipl.jl",
    "test/core_lang/test_fli_unify_cells.jl",
    "test/core_lang/test_fli_words.jl",
    "test/core_lang/test_format_swipl.jl",
    "test/core_lang/test_functor_table.jl",
    "test/core_lang/test_goal_clause.jl",
    "test/core_lang/test_gvar_swipl.jl",
    "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_index_words.jl",
    "test/core_lang/test_local_stack.jl",
    "test/core_lang/test_mark_bar.jl",
    "test/core_lang/test_metacall_control.jl",
    "test/core_lang/test_metacall.jl",
    "test/core_lang/test_meta_predicate_swipl.jl",
    "test/core_lang/test_module_enum_swipl.jl",
    "test/core_lang/test_module_path.jl",
    "test/core_lang/test_module_swipl.jl",
    "test/core_lang/test_numbervars_cells.jl",
    "test/core_lang/test_occurs_cells.jl",
    "test/core_lang/test_occurs_check.jl",
    "test/core_lang/test_op_swipl.jl",
    "test/core_lang/test_p1_swipl.jl",
    "test/core_lang/test_p2_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_read_swipl.jl",
    "test/core_lang/test_repeat_swipl.jl",
    "test/core_lang/test_resource_error.jl",
    "test/core_lang/test_rules_swipl.jl",
    "test/core_lang/test_s2a_swipl.jl",
    "test/core_lang/test_same_term_swipl.jl",
    "test/core_lang/test_setarg_swipl.jl",
    "test/core_lang/test_set_flag_swipl.jl",
    "test/core_lang/test_slot_indirects.jl",
    "test/core_lang/test_slot_words.jl",
    "test/core_lang/test_softcut.jl",
    "test/core_lang/test_sort_cells.jl",
    "test/core_lang/test_sortlist_swipl.jl",
    "test/core_lang/test_ssu_swipl.jl",
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
    "test/core_lang/test_string_swipl.jl",
    "test/core_lang/test_sys_swipl.jl",
    "test/core_lang/test_tagged_ints.jl",
    "test/core_lang/test_term.jl",
    "test/core_lang/test_trail_words.jl",
    "test/core_lang/test_unifiable_cells.jl",
    "test/core_lang/test_unify_cells.jl",
    "test/core_lang/test_unify.jl",
    "test/core_lang/test_unify_swipl.jl",
    "test/core_lang/test_univ_cells.jl",
    "test/core_lang/test_variant_cells.jl",
    "test/core_lang/test_var_identity.jl",
    "test/core_lang/test_walks_cells.jl",
    "test/core_lang/test_with_output_to_swipl.jl",
    "test/core_lang/test_write_cells.jl",
    "test/core_lang/test_zero_exports.jl",
    "test/core_text/test_atom_text_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_text/test_float_write_swipl.jl",
    "test/core_text/test_io.jl",
    "test/core_text/test_op.jl",
    "test/core_text/test_reader_cells.jl",
    "test/core_text/test_read.jl",
    "test/core_text/test_read_positions_swipl.jl",
    "test/core_text/test_read_term_swipl.jl",
    "test/core_text/test_roundtrip_swipl.jl",
    "test/core_text/test_syntax.jl",
    "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_write_swipl.jl",
    "test/db/test_assert_swipl.jl",
    "test/db/test_boot_image_readers.jl",
    "test/db/test_clause_ref_swipl.jl",
    "test/db/test_clause_swipl.jl",
    "test/db/test_clause_variables.jl",
    "test/db/test_db.jl",
    "test/db/test_gd_template.jl",
    "test/db/test_index_argv.jl",
    "test/db/test_index_context.jl",
    "test/db/test_index_swipl.jl",
    "test/db/test_jit.jl",
    "test/db/test_nth_clause_swipl.jl",
    "test/db/test_procedures.jl",
    "test/db/test_record_swipl.jl",
    "test/db/test_retractall_swipl.jl",
    "test/db/test_retract_swipl.jl",
    "test/db/test_source_file_swipl.jl",
    "test/db/test_update_view_gc.jl",
    "test/files/test_open_close_swipl.jl",
    "test/files/test_qlf_swipl.jl",
    "test/foreign/test_builtins_swipl.jl",
    "test/foreign/test_exceptions_swipl.jl",
    "test/foreign/test_query_answers.jl",
    "test/foreign/test_query.jl",
    "test/foreign/test_typetests_swipl.jl",
    "test/test_type_discipline.jl",
    "test/foreign/test_readme_example.jl",
]


def _first(fs):
    """The files `fs` first, then every other boot target (D-0238)."""
    return fs + [f for f in TBOOT if f not in fs]


TQ = _first(["test/files/test_qlf_swipl.jl"])
TP = _first([
    "test/files/test_load_swipl.jl",
    "test/compile/test_compiler_warnings_swipl.jl",
    "test/db/test_boot_messages_swipl.jl",
    "test/foreign/test_exceptions_swipl.jl",
])
TW = _first(["test/compile/test_compiler_warnings_swipl.jl"])
TL = _first(["test/files/test_load_swipl.jl"])
TC = _first(["test/core_lang/test_catch_swipl.jl"])
TARGETS = TBOOT                                      # the baseline's targets (mutate_ci.py plan reads TARGETS)
QL = "src/pl-qlf.jl"
GL = "src/pl-global.jl"
GT = "src/gd_template.jl"
ER = "src/pl-error.jl"
CO = "src/pl-comp.jl"
WA = "src/pl-wam.jl"
MUTANTS = [
    # ── the boot: the booted constructor, the template's copy, the registry's default build ──
    dict(id="LB4B2-Q1 the boot compiles nothing: the database is setupProlog's alone (KILL T1's common-rows count, every boot test)", file=QL, targets=TBOOT,
         old="    boot_from_source!(gd, ld, [initpl]) || error(\"boot_global_data: the boot compilation of $initpl failed\")\n",
         new="    true || error(\"boot_global_data: the boot compilation of $initpl failed\")\n"),
    dict(id="LB4B2-G1 PL_global_data{T}() is the unbooted setupProlog database, not the template's copy (KILL T1, T2, T3)", file=GL, targets=TBOOT,
         old="PL_global_data{T}() where {T} = PL_global_data_from_template(T)\n",
         new="PL_global_data{T}() where {T} = setupProlog(T)\n"),
    dict(id="LB4B2-G2 the registry's default build is the unbooted database (KILL T1, T2, T3: the copy of an unbooted template)", file=GT, targets=TBOOT,
         old="gd_template(::Type{T}) where {T} = gd_template(T, () -> boot_global_data(T))\n",
         new="gd_template(::Type{T}) where {T} = gd_template(T, () -> setupProlog(T))\n"),
    # ── src/pl-qlf.jl: the term after a boot diagnostic ──
    dict(id="LB4B2-W1 _qlf_pl_write! collects nothing (KILL test_qlf_swipl.jl 'Failed to compile': the term after the text)", file=QL, targets=TQ,
         old="    push!(ld.messages, (:error, export_cells(ld, cell_export{T}(), -(t + 1))))\n",
         new="    nothing\n"),
    dict(id="LB4B2-W2 addClauseWic's pl_write(term) dropped (KILL test_qlf_swipl.jl 'Failed to compile': the term after the text)", file=QL, targets=TQ,
         old="    _qlf_pl_write!(ld, term)                        # pl_write(term)\n",
         new=""),
    # ── src/pl-error.jl: printMessage calls print_message/2 ──
    dict(id="LB4B2-E1 printMessage never calls print_message/2, the fallback branch always (KILL test_load_swipl.jl's message_hook rows, T4)", file=ER, targets=TP,
         old="            if isDefinedProcedure(gd, pred) && ld.in_print_message <= OK_RECURSIVE\n",
         new="            if false\n"),
    dict(id="LB4B2-E2 the message term is not put in av+1: print_message/2 is not called, true returned (KILL test_load_swipl.jl's message_hook rows, T4)", file=ER, targets=TP,
         old="    rc = PL_unify(ld, av + 1, msg)              # PL_unify_termv(av+1, args)\n",
         new="    rc = false\n"),
    dict(id="LB4B2-E3 user_error taken as in error: the 'Cannot write to user_error' branch always (KILL the message_hook rows, T4)", file=ER, targets=TP,
         old="        if Sferror(Suser_error(ld)) == 0\n",
         new="        if Sferror(Suser_error(ld)) != 0\n"),
    dict(id="LB4B2-E4 the nesting count is not given back: past 10 messages on one engine print_message/2 is no longer called (KILL a file printing more than 10 messages on one engine: test_compiler_warnings_swipl.jl expected)", file=ER, targets=TP,
         old="    restoreWakeup(ld, wstate)\n    ld.in_print_message -= 1\n",
         new="    restoreWakeup(ld, wstate)\n"),
    dict(id="LB4B2-E5 the wakeup state is not restored: the foreign frame stays open (KILL H11 at the boot if the boot prints, else the message rows' stack checks)", file=ER, targets=TP,
         old="    restoreWakeup(ld, wstate)\n    ld.in_print_message -= 1\n",
         new="    ld.in_print_message -= 1\n"),
    dict(id="LB4B2-E6 an exception raised in print_message/2 is caught, not passed on (KILL a row whose message_hook raises: test_exceptions_swipl.jl expected; SURVIVOR CANDIDATE)", file=ER, targets=TP,
         old="PL_Q_NODEBUG | PL_Q_PASS_EXCEPTION, pred, av",
         new="PL_Q_NODEBUG | PL_Q_CATCH_EXCEPTION, pred, av"),
    # ── src/pl-comp.jl: the compiler reads the global variable $variable_names (init.pl:1948-1949 sets it) ──
    dict(id="LB4B2-C1 the compiler never reads $variable_names: warnings carry no variable names (KILL test_compiler_warnings_swipl.jl's named singleton rows)", file=CO, targets=TW,
         old="        if w !== nothing\n",
         new="        if false\n"),
    # ── src/pl-wam.jl: load_file! returns (status, ball) ──
    dict(id="LB4B2-L1 an exception ending the load is reported as :failed without its ball (KILL test_load_swipl.jl's (:exception, ball) rows)", file=WA, targets=TL,
         old="        return (:exception, e.ball::T)\n",
         new="        return (:failed, nothing)\n"),
    dict(id="LB4B2-L2 a load whose goal fails is reported :ok (KILL a row with a failing load_files/2; SURVIVOR CANDIDATE: EQUIVALENT if load_files/2 only succeeds or raises, which the battery's reader must show from init.pl)", file=WA, targets=TL,
         old="    return (isempty(answers) ? :failed : :ok, nothing)\n",
         new="    return (:ok, nothing)\n"),
    dict(id="LB4B2-L3 load_file! takes an engine of another database (KILL test_load_swipl.jl 'load_file! refuses an engine made for another database')", file=WA, targets=TL,
         old="    ld.GD === gd || throw(ArgumentError(\"load_file!: the engine `ld` is not one of `gd`\"))\n",
         new="    ld.GD === gd || nothing\n"),
    # ── src/pl-wam.jl b_throw_resume: an unwind(_) ball wraps the recover goal as '$recover_and_rethrow'(Goal, Ball) ──
    dict(id="LB4B2-B1 an unwind(_) ball is caught as any ball: the recover goal runs, the ball stops (KILL test_catch_swipl.jl 'an unwind(_) ball reaching a catcher': tu raises unwind(x))", file=WA, targets=TC,
         old="        if PL_is_functor(ld, ld.exception_term, mk_sym(T, :unwind), 1)  # (w=uncachableException(exception_term))\n",
         new="        if false\n"),
    dict(id="LB4B2-B2 the wrapper's second argument is the recover goal, not the ball (KILL test_catch_swipl.jl 'an unwind(_) ball reaching a catcher': the rethrown ball)", file=WA, targets=TC,
         old="            _cell_link!(ld, br_p + 2, ld.exception_term + 1)                # p[2] = w\n",
         new="            _cell_link!(ld, br_p + 2, argFrameP(br_base, 2) + 1)                # p[2] = w\n"),
    dict(id="LB4B2-B3 the wrapper's first argument is the ball, not the recover goal (KILL test_catch_swipl.jl 'an unwind(_) ball reaching a catcher': tw(yes) twice)", file=WA, targets=TC,
         old="            _cell_link!(ld, br_p + 1, argFrameP(br_base, 2) + 1)            # p[1] = argFrame(FR, 2)\n",
         new="            _cell_link!(ld, br_p + 1, ld.exception_term + 1)            # p[1] = argFrame(FR, 2)\n"),
    dict(id="LB4B2-B4 the wrapper is built but not stored as the goal to call: the frame's old word runs (KILL test_catch_swipl.jl 'an unwind(_) ball reaching a catcher')", file=WA, targets=TC,
         old="            ld.slots[argFrameP(ld.lTop, 0) + 1] = consPtr(br_p, TAG_COMPOUND | STG_GLOBAL)  # argFrame(lTop, 0) = consPtr(p, …)\n",
         new="            nothing\n"),
]
