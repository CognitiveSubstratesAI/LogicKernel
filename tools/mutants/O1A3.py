# O1A3 (audit D-0322): O1A2's list reduced to the ten mutants that had no verdict or survived, run at the final SHA with the rows
# f100-f106 (evidence/O1A/gen_rows3.py, expected values from swipl 10.1.19): C8 and E5 (runaway mutants: the CI runner is killed before a verdict
# can be written; verified locally under a 4G cap and listed here only by name, NOT in MUTANTS: evidence/O1A/runaway.md, audit D-0324 item 4),
# A1 A5 A6 D7 I2 J6 K4 (survivors of O1A2, each now killed by a named row), I21 and C6 (declared equivalent, file:line below; neither runs).
# Everything below is O1A2's header; the NOT LISTED reasons and the TARGETS note are unchanged.
# ORIGINAL: O1A's mutant list — the swipl-devel counterpart is src/os/pl-fmt.c, the Julia port is src/os/pl-fmt.jl.
# tools/mutants/O1A.py — the mutation battery of O1A (format/2,3: pl-fmt.c format, format_impl, do_format's directives
# ~a ~c ~e ~f ~g ~h ~d ~D ~r ~R ~I ~s ~i ~k ~p ~q ~w ~W ~@ ~~ ~n ~N ~t ~| ~+, the numeric and `*` and backquote arguments, the
# column machinery (distribute_rubber, emit_rubber, update_column, outchr, outstring, oututf8), formatInteger, formatFloat and its
# bignum and rational paths, prepare_sub_format/end_sub_format, the registration table), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_format_swipl.jl (rows
# f01-f99, e01-e24, k01-k03 named in each id's KILL; evidence/O1A/gen_rows.py). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon):
# RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to
# occur exactly once in src/os/pl-fmt.jl at wip/o1a (a text count, no Julia; tools/mutants/ is not read by the test files).
# The rows were generated from swipl 10.1.19, so a survivor means the kernel's format cannot be told from swipl's on that path.
# NOT LISTED (each with its reason):
#   * (nothing is NOT LISTED for do_format's `argument overflow` any more: pl-fmt.c:553-556's `int arg2 = arg*10+dw` wraps, the
#     compiled swipl 10.1.19 does not raise (`~3000000000d` of [1] prints 1), the port raises: the KNOWN DIFFERENCE row k03 pins
#     the kernel's answer with swipl's beside it, and O1A-C8 is its mutant.)
#   * formatInteger's fraction padding of a bignum with fewer digits than `div` (`UInt8('0')`): upstream reads before its buffer,
#     swipl's answer varies between runs (`~25d` of 2^64), so no row.
#   * outtext's Latin-1 branch (`outstring`) with rubber pending and a byte above 0x7f: upstream stores the raw byte and emit_rubber
#     decodes it as UTF-8 (audit flag (e)); no row pins the answer.
#   * groupDigits, countGroups, ths_to_utf8: reached only with a stream locale that has grouping (`~:f`); the kernel has none (D9),
#     the K rows pin the C-locale answer; the functions are dead for every row.
#   * formatFloat's final `if locale !== nothing` (src/os/pl-fmt.jl, the tail of formatFloat): the locale is always prolog_locale on
#     the kernel, so localizeDecimalPoint rewrites "." to "." (EQUIVALENT, read not run).
#   * format_predicate/2 and current_format_predicate/2: refused by name / failing (D9); not exercised by the rows.
# TARGETS (audit D-0238): the step's own file first (a run stops at the first target that decides). Mutants of the paths every
# `format("~w", …)` call takes (format_, format_impl, the text conversions, ~w ~d ~n ~s ~a, the arity check) list every other test
# file that calls format/2,3 or with_output_to (named by a grep of the test tree for a Prolog-level format( or with_output_to call;
# code_testlib.jl is a library included by those files and not listed); the column, rubber, float and bignum mutants are reached
# only by the rows of the own file (no other test file names a column, a float directive or a bignum one: the grep above shows
# only ~w ~d ~n ~s in them). test/core_lang/test_with_output_to_swipl.jl is O1B's file; it is in TO (added in the O1 stack, where both
# steps are on one branch: it exercises tellString/toldString, the column handling and format/3 into a with_output_to sink).
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
    # ── survivors of O1A2: kill rows f100-f106 ──
    m("O1A-A1 outchr stores a code point above 0x7f as one byte when rubber is pending: emit_rubber decodes garbage (KILL f100)",
      r'''        if chr > 0x7f
''', r'''        if chr > 0xff
'''),
    m("O1A-A5 outstring buffers `len` characters as one: a later fill point is placed wrongly (KILL f101)",
      r'''        state.buffered += len
''', r'''        state.buffered += 1
'''),
    m("O1A-A6 outstring does not advance the column over the bytes (KILL f101, f102)",
      r'''        update_column(state, Int(s[q]) & 0xff)
''', r'''        nothing
'''),
    m("O1A-D7 ~Ns does not cut a Latin-1 text to N characters (KILL f103)",
      r'''                    elseif arg < tlen
                        tlen = arg
                        txt =''', r'''                    elseif false
                        tlen = arg
                        txt ='''),
    m("O1A-I2 formatFloat's default for h is 6 digits (KILL f104)",
      r'''arg = use_h ? 3 : 6''', r'''arg = 6'''),
    m("O1A-J6 the double path's ~g prints the fixed form with a digit too many (KILL f105)",
      r'''Base.Ryu.writefixed(f, P - 1 - X)''', r'''Base.Ryu.writefixed(f, P - X)'''),
    m("O1A-K4 a call-back that wrote straight to the stream leaves the current output on the format stream (KILL f106)",
      r'''        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = state.old_stream
''', r'''        nothing
'''),
    # ── declared equivalents (read, not run) ──
    m("O1A-C6 the guard `here < flen` of the backquote argument (c is the character at `here`, so it holds whenever c is a backquote)",
      r'''            elseif c == Int('`') && here < flen
''', r'''            elseif c == Int('`')
''', equivalent="src/os/pl-fmt.jl:480 (do_format's `elseif c == Int('`') && here < flen`) — read, not run: c is `get_chr_from_text(fmt, here)` (pl-fmt.jl:433, :441, :445, :452, :479, :484, :489: the last read before the test), which returns 0 for `here >= length(fmt)` (pl-fmt.jl:311-312, the NUL terminator of upstream's C string), and 0 is no backquote, so c == '`' already implies here < flen; upstream's guard is the same test on a NUL-terminated text (audit D-0322 item 2: accepted)"),
    m("O1A-I21 a rational ~Ne does not correct the exponent of an exact power of ten (executed by f40 and f95, EQUIVALENT: see the argument)",
      r'''        t2 == abs(t1) && Rational{BigInt}(t1) == inv(q) && (ex += 1)
''', r'''        nothing
''', equivalent="src/os/pl-fmt.jl:1146 (_fmt_mpq_e!, `t2 == abs(t1) && Rational{BigInt}(t1) == inv(q) && (ex += 1)`) — EXECUTED (rows f40 and f95 reach it once each, evidence/O1A/triage.md) but the text is the same: the condition holds only for q = +1/10^k (n = 1, d = 10^k, since t1 = div(d, |n|) must equal inv(q) and a negative q makes inv(q) negative); the guess is then k+1 too small (mpz_sizeinbase10(10^k) = k+1), so t1 (pl-fmt.jl:1149-1156) is (10^(arg+k+1) + d/2) div d = 10^(arg+1) instead of 10^arg, and the renormalisation at pl-fmt.jl:1159-1162 (`_fmt_pow10(arg + 1) == t1` -> t1 div 10, ex += 1) turns it into 10^arg with ex = -k, exactly what the corrected guess gives; for q = -1/10^k the condition is false in both versions. Differential, both functions side by side: 68598 calls (+-1/10^k for k = 0..45, +-m/10^k and +-10^k/m, 3000 random rationals, arg 0..8, e and E), 0 differences (evidence/O1A/triage.md)"),
]
