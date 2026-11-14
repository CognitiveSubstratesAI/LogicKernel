# ORIGINAL: SYNC-R's mutant list — no swipl-devel counterpart (the code is src/os/pl-fmt.c, ported in src/os/pl-fmt.jl).
# tools/mutants/SYNCR.py — the mutation battery of SYNC-R (the pl-fmt.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. The behaviour change of the slice is the size limits of format/2
# (MAX_PRECISION, MAX_COLUMN, FMT_ARG_MAX in `~c ~n ~s ~d ~D ~I ~| ~+` and formatFloat); the rows are `_FM_TARGET` (r01-r20, b01-b03)
# of test/core_lang/test_format_swipl.jl, written by hand from the target's C. Mutants are killed by that file; TARGETS (the
# baseline's) is O1A's: every file that exercises format/2 or pl-fmt.jl (D-0238).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (an exact once-count; the SYNC-R agent checked
# each against src/os/pl-fmt.jl with a Python count, no Julia).
# NOT LISTED: `arg > MAX_PRECISION` in formatFloat as `>=` (a row at exactly 1000000 digits prints a million digits through the
# bignum and Ryu paths: too slow for a row); `~1000000c` and `~1000000s` as boundary rows (the three share `_fmt_arg_max`, whose `>=`
# mutant R2 b01 kills).
TF = ["test/core_lang/test_format_swipl.jl"]
TO = [
    "test/charset/test_umap_swipl.jl", "test/compile/test_analyse_variables_swipl.jl",
    "test/compile/test_body_code_swipl.jl", "test/compile/test_compiler_warnings_swipl.jl",
    "test/compile/test_head_code_swipl.jl", "test/compile/test_portable_smallint_swipl.jl",
    "test/compile/test_ssu_compile_swipl.jl", "test/core_lang/test_arith_swipl.jl",
    "test/core_lang/test_at_body_swipl.jl", "test/core_lang/test_attvar_store.jl",
    "test/core_lang/test_attvar_wakeup.jl", "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_between_swipl.jl", "test/core_lang/test_blob.jl",
    "test/core_lang/test_colon_body_swipl.jl", "test/core_lang/test_compare_swipl.jl",
    "test/core_lang/test_context_module_swipl.jl", "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_cyclic_term_swipl.jl", "test/core_lang/test_export_import_swipl.jl",
    "test/core_lang/test_hash.jl", "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_meta_predicate_swipl.jl", "test/core_lang/test_module_swipl.jl",
    "test/core_lang/test_op_swipl.jl", "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_read_swipl.jl", "test/core_lang/test_repeat_swipl.jl",
    "test/core_lang/test_ssu_swipl.jl", "test/core_lang/test_stack_overflow_swipl.jl",
    "test/core_lang/test_sys_swipl.jl", "test/core_lang/test_unify_swipl.jl",
    "test/core_lang/test_variant_swipl.jl", "test/core_lang/test_var_identity.jl",
    "test/core_lang/test_with_output_to_swipl.jl",
    "test/core_text/test_atom_text_swipl.jl", "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_text/test_io.jl", "test/core_text/test_read_term_swipl.jl",
    "test/core_text/test_roundtrip_swipl.jl", "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_write_swipl.jl", "test/db/test_clause_ref_swipl.jl",
    "test/db/test_clause_swipl.jl", "test/db/test_index_swipl.jl",
    "test/db/test_nth_clause_swipl.jl", "test/db/test_retractall_swipl.jl",
    "test/db/test_retract_swipl.jl", "test/db/test_source_file_swipl.jl",
    "test/files/test_load_swipl.jl", "test/files/test_open_close_swipl.jl",
    "test/files/test_stream_swipl.jl", "test/foreign/test_builtins_swipl.jl",
    "test/foreign/test_exceptions_swipl.jl", "test/foreign/test_typetests_swipl.jl",
]
TA = TF + TO
TARGETS = TA   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/os/pl-fmt.jl"


def m(id, old, new, targets=TF, equivalent=None):
    d = dict(id=id, file=W, old=old, new=new, targets=targets)
    if equivalent is not None:
        d["equivalent"] = equivalent
    return d


MUTANTS = [
    m("SR-1 _fmt_arg_max raises no error (KILL r01-r07)",
      r'''    !(arg != FMT_DEFAULT && arg > max) || (PL_format_error(ld, msg); false)
''', r'''    true
'''),
    m("SR-2 _fmt_arg_max raises AT the limit (KILL b01)",
      r'''    !(arg != FMT_DEFAULT && arg > max) || (PL_format_error(ld, msg); false)
''', r'''    !(arg != FMT_DEFAULT && arg >= max) || (PL_format_error(ld, msg); false)
'''),
    m("SR-3 ~c has no count limit (KILL r01)",
      r'''            elseif c == Int('c')                # ~c: character code
                _fmt_arg_max(ld, arg, MAX_COLUMN, "repeat count too large") || return false
''', r'''            elseif c == Int('c')                # ~c: character code
'''),
    m("SR-4 ~s has no column limit (KILL r04)",
      r'''                _fmt_arg_max(ld, arg, MAX_COLUMN, "column too large") || return false
''', r''''''),
    m("SR-5 ~n has no count limit (KILL r02, r03)",
      r'''            elseif c == Int('n')                # \n
                _fmt_arg_max(ld, arg, MAX_COLUMN, "repeat count too large") || return false
''', r'''            elseif c == Int('n')                # \n
'''),
    m("SR-6 ~d and ~D have no precision limit (KILL r05-r07)",
      r'''                    _fmt_arg_max(ld, arg, MAX_PRECISION, "precision too large") ||
                        return false
''', r'''                    nothing
'''),
    m("SR-7 ~I accepts a group size of exactly CHAR_MAX (KILL r08)",
      r'''(arg < 0 || arg >= typemax(Int8))''', r'''(arg < 0 || arg > typemax(Int8))'''),
    m("SR-8 ~I accepts a negative group size (KILL r09)",
      r'''(arg < 0 || arg >= typemax(Int8))''', r'''(arg >= typemax(Int8))'''),
    m("SR-9 ~I with no argument is refused (KILL f25, b03)",
      r'''elseif c == Int('I') && arg != FMT_DEFAULT &&
''', r'''elseif c == Int('I') &&
'''),
    m("SR-10 ~| and ~+ do not test the argument itself (KILL r12)",
      r'''                arg > MAX_COLUMN && return PL_format_error(ld, "column too large")
''', r''''''),
    m("SR-11 ~| and ~+ do not test the stop (KILL r13)",
      r'''                stop > MAX_COLUMN && return PL_format_error(ld, "column too large")
''', r''''''),
    m("SR-12 ~| and ~+ refuse a column of exactly MAX_COLUMN (KILL b02)",
      r'''                stop > MAX_COLUMN && return''', r'''                stop >= MAX_COLUMN && return'''),
    m("SR-13 ~| and ~+ refuse an argument of exactly MAX_COLUMN (KILL b02)",
      r'''                arg > MAX_COLUMN && return''', r'''                arg >= MAX_COLUMN && return'''),
    m("SR-14 formatFloat has no precision limit (KILL r14-r19)",
      r'''    elseif arg > MAX_PRECISION
        return PL_format_error(ld, "precision too large")
    end
''', r'''    end
'''),
]
