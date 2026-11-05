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
# O1 swaps two adjacent rows of src/pl-vmi.jl's `_CODE_TABLE` (the opcode order of audit D-0407 item 3); the AUTOLOAD1 list is appended at the
# end as a regression set (D-0407 item 4: Q3a runs CI-way with it, tools/mutate_ci.py; its kills are test_autoload_trap.jl's `bootsession` row and
# test_autoload_flag_swipl.jl's Q3 testset).
# NOT LISTED (each with its reason):
#   * boot_global_data's H11 check itself (`(left != empty_at && after == left) || error(...)`) and the check of
#     boot_from_source!'s result (Q1 mutates the call itself): guards on invariants a correct boot keeps; a mutant that
#     drops one changes nothing a test sees unless the boot is broken. H11 is proved able to FAIL by H11a-H11c instead
#     (a boot leaving one frame fewer, one more, a wrong leftover count: each trips H11 at the boot).
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
import os
import runpy

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
# the continuation opcodes (writers 11-12, audit D-0363 item 2): the rows file first, then the body-code pins, then the boot
TK = _first(["test/core_lang/test_cont_boot_swipl.jl", "test/compile/test_body_code_swipl.jl",
             "test/foreign/test_query.jl"])
TKB = _first(["test/compile/test_body_code_swipl.jl", "test/core_lang/test_cont_boot_swipl.jl",
              "test/foreign/test_query.jl"])
# THE AUTOLOAD1 REGRESSION SET (audit D-0407 item 4): b2 changes the boot session the AUTOLOAD1 mutants test (trapUndefined's Q3
# branch, the compileFileList pair, the autoloader's hook calls), so the whole of AUTOLOAD1's list runs with this one, each mutant on
# its own targets, and the baseline runs the union of the files. Q3a (trapUndefined does not raise in the boot session) is killed by
# test_autoload_trap.jl's `bootsession` row and test_autoload_flag_swipl.jl's Q3 testset (tools/mutants/AUTOLOAD1.py).
_AL = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "AUTOLOAD1.py"))
_AL_TARGETS = [t for t in _AL["TARGETS"] if t not in TBOOT]
TSW = TK + ["test/core_lang/test_tabling_min_swipl.jl"]    # the opcode-order row, the body-code pins, TAB1-min's rows
GC = "src/pl-gc.jl"
TARGETS = TBOOT + _AL_TARGETS                        # the baseline's targets (mutate_ci.py plan reads TARGETS)
QL = "src/pl-qlf.jl"
GL = "src/pl-global.jl"
GT = "src/gd_template.jl"
ER = "src/pl-error.jl"
CO = "src/pl-comp.jl"
WA = "src/pl-wam.jl"
MUTANTS = [
    # ── the boot: the booted constructor, the template's copy, the registry's default build ──
    dict(id="LB4B2-Q1 the boot compiles nothing: the database is setupProlog's alone (KILL T1's common-rows count, every boot test)", file=QL, targets=TBOOT,
         old="    boot_from_source!(gd, ld, argv) ||\n        error(\"boot_global_data: the boot compilation of $initpl failed\")\n",
         new="    true ||\n        error(\"boot_global_data: the boot compilation of $initpl failed\")\n"),
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
    # ── src/pl-qlf.jl: H11, the boot's leftover as upstream's compileFile leaves it (pl-qlf.c:4726-4741) ──
    dict(id="LB4B2-H11a the end_of_file frame is discarded before the break: one frame fewer (KILL H11 at the boot, every boot test; test_qlf_swipl.jl's leftover rows)", file=QL, targets=TQ,
         old="        (eof !== nothing && sym_key(eof) == sym_key(mk_sym(T, :end_of_file))) && break\n",
         new="        (eof !== nothing && sym_key(eof) == sym_key(mk_sym(T, :end_of_file))) && (PL_discard_foreign_frame(ld, cid); break)\n"),
    dict(id="LB4B2-H11b compileFile opens one frame more before its loop (KILL H11 at the boot, every boot test; test_qlf_swipl.jl's leftover rows)", file=QL, targets=TQ,
         old="    qlfStartFile(state, sf)\n",
         new="    qlfStartFile(state, sf)\n    PL_open_foreign_frame(ld)\n"),
    dict(id="LB4B2-H11c the leftover frame counted one reference short (KILL H11 at the boot, every boot test; test_qlf_swipl.jl's leftover rows)", file=QL, targets=TQ,
         old="nfiles * (2 + SIZEOF_FLIFRAME + 2)",
         new="nfiles * (2 + SIZEOF_FLIFRAME + 1)"),
    # ── src/pl-qlf.jl + src/gd_template.jl: the boot ld's standard streams leave the template; another stream refuses it ──
    dict(id="LB4B2-S1 the boot ld's standard streams are not cleared (KILL the template's copy at every boot test: copy_global_data refuses)", file=QL, targets=TQ,
         old="    drop_boot_std_streams!(gd, ld)                                # the template keeps no stream of the dropped ld\n",
         new=""),
    dict(id="LB4B2-S2 every slot of the stream table is cleared, not the three standard ones (KILL test_qlf_swipl.jl 'another open stream still refuses the copy')", file=QL, targets=TQ,
         old="    for i in (SNO_USER_INPUT, SNO_USER_OUTPUT, SNO_USER_ERROR)\n        s = ld.IO_streams[i + 1]\n        s === nothing && continue\n        (s.flags & SIO_OUTPUT)",
         new="    fill!(gd.stream_table, nothing)\n    for i in (SNO_USER_INPUT, SNO_USER_OUTPUT, SNO_USER_ERROR)\n        s = ld.IO_streams[i + 1]\n        s === nothing && continue\n        (s.flags & SIO_OUTPUT)"),
    dict(id="LB4B2-S3 the copy takes a template holding a live stream (KILL test_qlf_swipl.jl's open-stream row, test_gd_template.jl's stream-table row)", file=GT, targets=_first(["test/files/test_qlf_swipl.jl", "test/db/test_gd_template.jl"]),
         old="        s === nothing || error(\"copy_global_data: the template holds an open stream\")\n",
         new="        nothing\n"),
    # ── src/gd_template.jl: the cached working directory is start-up state, reset in the copy (audit D-0408 item 4) ──
    dict(id="LB4B2-CWD1 paths_CWDdir keeps the template's value in the copy: the :reset entry is gone, the default :deep (KILL test_gd_template.jl 'the cached working directory is start-up state': the copy's field is A's and it answers A in B)", file=GT, targets=_first(["test/db/test_gd_template.jl"]),
         old="    paths_CWDdir=:reset              # pl-os.c:989, :1864-1866 at cbf4e189\n",
         new=""),
    dict(id="LB4B2-CWD2 the reset value is \"/\", not the constructor's \"\" (KILL the same row: the copy's field differs from setupProlog's, and PL_cwd trusts \"/\")", file=GT, targets=_first(["test/db/test_gd_template.jl"]),
         old='const GD_COPY_RESET = (paths_CWDdir="",)',
         new='const GD_COPY_RESET = (paths_CWDdir="/",)'),
    # ── src/pl-error.jl: printMessage calls print_message/2 ──
    dict(id="LB4B2-E1 printMessage never calls print_message/2, the fallback branch always (KILL test_load_swipl.jl's message_hook rows, T4)", file=ER, targets=TP,
         old="            if isDefinedProcedure(gd, pred) && ld.in_print_message <= OK_RECURSIVE\n",
         new="            if false\n"),
    dict(id="LB4B2-E2 the message term is not put in av+1: print_message/2 is not called, true returned (KILL test_load_swipl.jl's message_hook rows, T4)", file=ER, targets=TP,
         old="    rc = PL_unify(ld, av + 1, msg)              # PL_unify_termv(av+1, args)\n",
         new="    rc = false\n"),
    dict(id="LB4B2-E3 user_error taken as in error: the 'Cannot write to user_error' branch always (KILL the message_hook rows, T4)", file=ER, targets=TP,
         old="        if Sferror(Suser_error(ld)::IOSTREAM) == 0\n",
         new="        if Sferror(Suser_error(ld)::IOSTREAM) != 0\n"),
    dict(id="LB4B2-E4 the nesting count is not given back: past 10 messages on one engine print_message/2 is no longer called (KILL a file printing more than 10 messages on one engine: test_compiler_warnings_swipl.jl expected)", file=ER, targets=TP,
         old="    restoreWakeup(ld, wstate)\n    ld.in_print_message -= 1\n",
         new="    restoreWakeup(ld, wstate)\n"),
    dict(id="LB4B2-E5 the wakeup state is not restored: the foreign frame stays open and the pending exception is lost (KILL test_exceptions_swipl.jl 'printMessage gives the pending exception back and closes its frame': slice 18 measured it FAILING under this text, three assertions, and passing on the real tree)", file=ER, targets=TP,
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
    dict(id="LB4B2-L2 a load whose goal fails is reported :ok (KILL test_load_swipl.jl 'load_file! reports a load whose load_files/2 fails as :failed': a first file redefines load_files/2 in user as `fail`, the second file loads to :failed; load_files/2 of the system only succeeds or raises, init.pl:2563, but user can redefine it)", file=WA, targets=TL,
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
    # ── the continuation opcodes (writers 11-12): I_CUTCHP's run, the compile branches, the decompiler ──
    dict(id="LB4B2-K1 I_CUTCHP skips the existence test (KILL test_cont_boot_swipl.jl 'g_cut_neg', 'g_cut_far', 'g_cut_stale')", file=WA, targets=TK,
         old='        if cch_ch == 0                              # if ( !existingChoice(och) )\n',
         new='        if false\n'),
    dict(id="LB4B2-K2 I_CUTCHP takes any value word as a choice (KILL test_cont_boot_swipl.jl 'g_cut_float', 'g_cut_big')", file=WA, targets=TK,
         old='    if cch_k == DU_VALUE && isTaggedIntW(cch_w)     # isTaggedInt(*a)\n',
         new='    if cch_k == DU_VALUE     # isTaggedInt(*a)\n'),
    dict(id="LB4B2-K3 a non-integer raises existence_error, not type_error (KILL test_cont_boot_swipl.jl 'g_cut_atom', 'g_cut_cmp')", file=WA, targets=TK,
         old='    PL_error(ld, ERR_TYPE, mk_sym(T, :choice), cch_t)   # PL_error(…, ERR_TYPE, ATOM_choice, consTermRef(a))\n',
         new='    PL_error(ld, ERR_EXISTENCE, mk_sym(T, :choice), cch_t)   # PL_error(…, ERR_TYPE, ATOM_choice, consTermRef(a))\n'),
    dict(id="LB4B2-K4 I_CUTCHP cuts to the newest choice, not the one named (KILL test_cont_boot_swipl.jl 'g_cut_live', 'g_cut_mid')", file=WA, targets=TK,
         old='        cc_och = ld.choices[cch_ch].base            # VMH_GOTO(c_cut, och)\n',
         new='        cc_och = ld.choices[ld.BFR].base            # VMH_GOTO(c_cut, och)\n'),
    dict(id="LB4B2-K5 $cut compiles to I_TRUE (KILL test_cont_boot_swipl.jl 'g_cut_live'; test_body_code_swipl.jl pt9)", file=CO, targets=TK,
         old='                Output_0!(ci, I_CUTCHP)\n',
         new='                Output_0!(ci, I_TRUE)\n'),
    dict(id='LB4B2-K6 $reset compiles without I_EXITRESET (KILL test_body_code_swipl.jl pt7, the live swipl compare)', file=CO, targets=TKB,
         old='                Output_0!(ci, I_EXITRESET)\n',
         new='                nothing\n'),
    dict(id="LB4B2-K7 $call_continuation emits I_SHIFT (KILL test_body_code_swipl.jl the cc cells; test_cont_boot_swipl.jl 'rb_cc')", file=CO, targets=TKB,
         old='        Output_1!(ci, I_CALLCONT, VAROFFSET(i1))\n',
         new='        Output_1!(ci, I_SHIFT, VAROFFSET(i1))\n'),
    dict(id="LB4B2-K8 $shift_for_copy emits I_SHIFT (KILL test_body_code_swipl.jl sh3; test_cont_boot_swipl.jl 'rb_shiftcp')", file=CO, targets=TKB,
         old='        Output_1!(ci, for_copy ? I_SHIFTCP : I_SHIFT, VAROFFSET(i1))\n',
         new='        Output_1!(ci, I_SHIFT, VAROFFSET(i1))\n'),
    dict(id="LB4B2-K9 I_CUTCHP decompiles to ! (KILL test_cont_boot_swipl.jl 'rb_cut')", file=CO, targets=TK,
         old='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\\$cut"))))\n',
         new='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("!"))))\n'),
    dict(id="LB4B2-K10 I_RESET decompiles to $catch (KILL test_cont_boot_swipl.jl 'rb_reset', 'rb_tbl_reset')", file=CO, targets=TK,
         old='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\\$reset"))))\n',
         new='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\\$catch"))))\n'),
    dict(id="LB4B2-K11 I_YIELD decompiles to $reset (KILL test_cont_boot_swipl.jl 'rb_yield')", file=CO, targets=TK,
         old='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\\$yield"))))\n',
         new='            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\\$reset"))))\n'),
    dict(id="LB4B2-K12 I_SHIFT decompiles to $shift_for_copy (KILL test_cont_boot_swipl.jl 'rb_shift')", file=CO, targets=TK,
         old='    op == I_SHIFT && return Symbol("\\$shift")                  # FUNCTOR_dshift1\n',
         new='    op == I_SHIFT && return Symbol("\\$shift_for_copy")                  # FUNCTOR_dshift1\n'),
    dict(id="LB4B2-K13 I_CALLCONT decompiles to $shift (KILL test_cont_boot_swipl.jl 'rb_cc')", file=CO, targets=TK,
         old='    op == I_CALLCONT && return Symbol("\\$call_continuation")  # FUNCTOR_dcall_continuation1 (LB4 b2)\n',
         new='    op == I_CALLCONT && return Symbol("\\$shift")  # FUNCTOR_dcall_continuation1 (LB4 b2)\n'),
    dict(id="LB4B2-K14 the decompiler stops reading I_EXITRESET as nothing (KILL test_cont_boot_swipl.jl 'rb_reset')", file=CO, targets=TK,
         old='        elseif op == I_EXIT || op == I_EXITCATCH || op == I_EXITRESET  # (I_EXITRESET: LB4 b2)\n',
         new='        elseif op == I_EXIT || op == I_EXITCATCH  # (I_EXITRESET: LB4 b2)\n'),
    dict(id="LB4B2-K16 clearUninitialisedVarsFrame reads past I_EXITRESET (KILL test_cont_boot_swipl.jl 'clearUninitialisedVarsFrame stops at I_EXITRESET': a synthetic code list [B_FIRSTVAR 0, I_EXITRESET, B_FIRSTVAR 1, I_EXIT], cell 1 must stay; slice 18 measured it FAILING under this text and passing on the real tree; every compiled clause ends I_EXIT after I_EXITRESET, so only a direct call shows it)", file=GC, targets=TK,
         old='        if c == I_EXIT || c == I_EXITFACT || c == I_EXITCATCH || c == I_EXITRESET ||\n',
         new='        if c == I_EXIT || c == I_EXITFACT || c == I_EXITCATCH ||\n'),
    dict(id="LB4B2-O1 two adjacent rows of _CODE_TABLE swapped: I_YIELD and I_CUTCHP trade places (KILL test_cont_boot_swipl.jl 'the tail of the opcode table is in pl-vmi.c order': the tail names are no longer upstream's order, the row of a const is another name)", file="src/pl-vmi.jl", targets=TSW,
         old='    code_info(:I_YIELD, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),\n    code_info(:I_CUTCHP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),\n',
         new='    code_info(:I_CUTCHP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),\n    code_info(:I_YIELD, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),\n'),
]

MUTANTS = MUTANTS + _AL["MUTANTS"]                  # the AUTOLOAD1 regression set, each on its own targets
