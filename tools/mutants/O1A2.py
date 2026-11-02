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
    # ── pl-fmt.c outchr, outstring, oututf8, update_column ──
    m("O1A-A1 outchr stores a code point above 0x7f as one byte when rubber is pending: emit_rubber decodes garbage (KILL f60)",
      r'''        if chr > 0x7f
''', r'''        if chr > 0xff
'''),
    m("O1A-A2 outchr counts no buffered character: a later fill point is placed one too early (KILL f99)",
      r'''        state.buffered += 1
    else
''', r'''        nothing
    else
'''),
    m("O1A-A3 outchr does not advance the column (KILL f58)",
      r'''    update_column(state, chr)
    return true
end
''', r'''    return true
end
'''),
    m("O1A-A4 update_column leaves the tab stop after a newline (KILL f76)",
      r'''    c == Int('\n') && (state.tab_stop = 0)
''', r'''    nothing
'''),
    m("O1A-A5 outstring buffers `len` characters as one: a later fill point is placed wrongly (KILL f52, f61)",
      r'''        state.buffered += len
''', r'''        state.buffered += 1
'''),
    m("O1A-A6 outstring does not advance the column over the bytes (KILL f50, f54)",
      r'''        update_column(state, Int(s[q]) & 0xff)
''', r'''        nothing
'''),
    m("O1A-A7 oututf8 does not advance the column when no fill point is pending (KILL f98)",
      r'''            update_column(state, chr)
''', r'''            nothing
'''),
    m("O1A-A8 oututf8 drops the code points when fill points are pending (KILL f55, f98)",
      r'''            outchr(state, chr) || return false
        end
    end
    return true
''', r'''            nothing
        end
    end
    return true
'''),
    # ── pl-fmt.c format, format_impl ──
    m("O1A-B1 format/3 does not close the redirect: the sink is never unified (KILL f01, f13)",
      r'''            rc = closeOutputRedirect(ld, ctx)
''', r'''            rc = true
''', TA),
    m("O1A-B2 format_impl takes no code list as the format text (KILL f12)",
      r'''PL_get_text(ld, format, CVT_ATOM | CVT_STRING | CVT_LIST)''',
      r'''PL_get_text(ld, format, CVT_ATOM | CVT_STRING)'''),
    m("O1A-B3 format_impl takes no string as the format text (KILL f01)",
      r'''PL_get_text(ld, format, CVT_ATOM | CVT_STRING | CVT_LIST)''',
      r'''PL_get_text(ld, format, CVT_ATOM | CVT_LIST)''', TA),
    m("O1A-B4 format_impl raises type_error(atom, …) for a text of the wrong type (KILL e22)",
      r'''ERR_TYPE, mk_sym(T, :text), format)''', r'''ERR_TYPE, mk_sym(T, :atom), format)'''),
    m("O1A-B5 format_impl never takes a non-list argument as the one argument (KILL f09, f10)",
      r'''    elseif !PL_is_pair(ld, args)
''', r'''    elseif false
''', TA),
    m("O1A-B6 format_impl collects no argument of a proper list (KILL f02, f11)",
      r'''        if argc > 0
''', r'''        if argc > 1
''', TA),
    m("O1A-B7 format_impl names the wrong type for a partial list (KILL e15)",
      r'''ERR_TYPE, mk_sym(T, :list), args)   # PL_type_error("list", args)''',
      r'''ERR_TYPE, mk_sym(T, :atom), args)'''),
    m("O1A-B8 format/3 is registered with format/2's body (KILL f13, f72)",
      r'''PL_extension("format", 3, pl_format3_va,''', r'''PL_extension("format", 3, pl_format2_va,''', TA),
    m("O1A-B9 format/2 is registered with format/3's body (KILL f72, f73)",
      r'''PL_extension("format", 2, pl_format2_va,''', r'''PL_extension("format", 2, pl_format3_va,''', TA),
    m("O1A-B10 a missing argument is not an error (KILL e01)",
      r'''    argc > 0 || (PL_format_error(ld, "not enough arguments"); false)
''', r'''    argc > -1 || (PL_format_error(ld, "not enough arguments"); false)
''', TA),
    m("O1A-B11 leftover arguments are not an error (KILL e02)",
      r'''    argc != 0 && return PL_format_error(ld, "too many arguments")
''', r'''    nothing
''', TA),
    # ── do_format: the numeric argument ──
    m("O1A-C1 a minus sign without digits is not an error (KILL e21)",
      r'''                isDigitW(c) || return PL_format_error(ld, "invalid argument")
''', r'''                nothing
'''),
    m("O1A-C2 a negative numeric argument keeps its sign off (KILL e10)",
      r'''                        neg && (arg = -arg)
''', r'''                        nothing
'''),
    m("O1A-C3 the digits of a numeric argument are not shifted (KILL f28, f56)",
      r'''arg2 = arg * 10 + dw''', r'''arg2 = arg * 10'''),
    m("O1A-C4 `*` leaves the argument it consumed on the list (KILL f26, f08)",
      r'''                argc -= 1                       # SHIFT
''', r'''                nothing
'''),
    m("O1A-C5 a backquote argument is not read (KILL f53, f57, e18)",
      r'''            elseif c == Int('`') && here < flen
''', r'''            elseif false
'''),
    m("O1A-C6 the guard `here < flen` of the backquote argument (c is the character at `here`, so it holds whenever c is a backquote)",
      r'''            elseif c == Int('`') && here < flen
''', r'''            elseif c == Int('`')
''', equivalent="src/os/pl-fmt.jl:485 (do_format's `elseif c == Int('`') && here < flen`) — read, not run: c is `get_chr_from_text(fmt, here)` (the line before the numeric-argument branch), which returns 0 for `here >= length(fmt)` (pl-fmt.jl:316-317), and 0 is no backquote, so c == '`' already implies here < flen; upstream's `here < fmt.length` is the same guard on a NUL-terminated text (pl-fmt.c)"),
    m("O1A-C8 a numeric argument past `int` is not refused: the kernel's raise of format('argument overflow') is gone (KILL k03; swipl 10.1.19 prints 1, flag k)",
      r'''                        arg2 > typemax(Int32) &&
                            return PL_format_error(ld, "argument overflow")
''', r'''                        nothing
'''),
    m("O1A-C7 the colon modifier is not recorded (KILL f77, f78, k01)",
      r'''                mod_colon = true
''', r'''                mod_colon = false
'''),
    # ── do_format: ~a ~c ~s ~i ~k ~p ~q ~w ~W ~@ ~~ ~n ~N ──
    m("O1A-D1 ~a names the wrong directive in format_argument_type (KILL e12)",
      r'''PL_format_arg_error(ld, "a", argv)''', r'''PL_format_arg_error(ld, "w", argv)'''),
    m("O1A-D2 ~Nc prints the character once (KILL f08)",
      r'''times = (arg == FMT_DEFAULT ? 1 : arg)''', r'''times = 1'''),
    m("O1A-D3 ~c accepts a code point outside the range (KILL e05)",
      r'''chr !== nothing && VALID_CODE_POINT(chr)''', r'''chr !== nothing'''),
    m("O1A-D4 ~s takes no code list (KILL f04)",
      r'''PL_get_text(ld, argv, CVT_ATOM | CVT_LIST | CVT_STRING)''', r'''PL_get_text(ld, argv, CVT_ATOM | CVT_STRING)''', TA),
    m("O1A-D5 ~s takes no string (KILL f05)",
      r'''PL_get_text(ld, argv, CVT_ATOM | CVT_LIST | CVT_STRING)''', r'''PL_get_text(ld, argv, CVT_ATOM | CVT_LIST)''', TA),
    m("O1A-D6 ~s takes no atom (KILL e09)",
      r'''PL_get_text(ld, argv, CVT_ATOM | CVT_LIST | CVT_STRING)''', r'''PL_get_text(ld, argv, CVT_LIST | CVT_STRING)''', TA),
    m("O1A-D7 ~Ns does not cut a Latin-1 text to N characters (KILL f79)",
      r'''                    elseif arg < tlen
                        tlen = arg
                        txt =''', r'''                    elseif false
                        tlen = arg
                        txt ='''),
    m("O1A-D8 ~Ns does not cut a wide text to N characters (KILL f80)",
      r'''                    elseif arg < tlen
                        tlen = arg
                    end''', r'''                    elseif false
                        tlen = arg
                    end'''),
    m("O1A-D9 ~Ns does not pad a short text (KILL f79, f80)",
      r'''                npad = arg - tlen
''', r'''                npad = 0
'''),
    m("O1A-D10 ~i does not consume its argument (KILL f06)",
      r'''            elseif c == Int('i')                # ignore
                _fmt_need_arg(ld, argc) || return false
                argc -= 1
''', r'''            elseif c == Int('i')                # ignore
                _fmt_need_arg(ld, argc) || return false
'''),
    m("O1A-D11 ~k writes with write/1 (KILL f07)",
      r'''                    pl_write_canonical(ld, argv)
''', r'''                    pl_write(ld, argv)
'''),
    m("O1A-D12 ~p writes with write/1 (KILL f03)",
      r'''                    pl_print(ld, argv)
''', r'''                    pl_write(ld, argv)
'''),
    m("O1A-D13 ~q writes with write/1 (KILL f02)",
      r'''                    pl_writeq(ld, argv)
''', r'''                    pl_write(ld, argv)
'''),
    m("O1A-D14 ~w writes with writeq/1 (KILL f02, f11)",
      r'''                    pl_write(ld, argv)
''', r'''                    pl_writeq(ld, argv)
''', TA),
    m("O1A-D15 ~W passes the term as its own options (KILL f81)",
      r'''pl_write_term3(ld, 0, argv, argv + 1)''', r'''pl_write_term3(ld, 0, argv, argv)'''),
    m("O1A-D16 ~W consumes one argument (KILL f81)",
      r'''                argc -= 2
''', r'''                argc -= 1
'''),
    m("O1A-D17 ~W accepts a single argument (KILL e23)",
      r'''                argc < 2 && return PL_format_error(ld, "not enough arguments")
''', r'''                argc < 1 && return PL_format_error(ld, "not enough arguments")
'''),
    m("O1A-D18 ~@ accepts no argument (KILL e24)",
      r'''                argc < 1 && return PL_format_error(ld, "not enough arguments")
''', r'''                argc < 0 && return PL_format_error(ld, "not enough arguments")
'''),
    m("O1A-D19 ~@ keeps the call-back's bindings: no foreign-frame rewind (KILL f86)",
      r'''                rc && PL_rewind_foreign_frame(ld, fid)
''', r'''                nothing
'''),
    m("O1A-D20 ~@ raises no call-back exception: format fails (KILL f70)",
      r'''ex[] != 0 && PL_exception(ld, 0) == 0 &&''',
      r'''false &&'''),
    m("O1A-D21 ~~ prints nothing (KILL f16)",
      r'''                outchr(state, Int('~')) || return false
''', r'''                nothing
'''),
    m("O1A-D22 ~n prints two newlines by default (KILL f16)",
      r'''                arg == FMT_DEFAULT && (arg = 1)
''', r'''                arg == FMT_DEFAULT && (arg = 2)
''', TA),
    m("O1A-D23 ~N prints a newline at column 0 too (KILL f17)",
      r'''                if COLUMN(state) != 0
''', r'''                if true
'''),
    m("O1A-D24 an unknown directive names the wrong existence_error type (KILL e08, e18)",
      r'''mk_sym(T, :format_character), ex''', r'''mk_sym(T, :format_directive), ex'''),
    # ── do_format: ~d ~D ~r ~R ~I ~e ~f ~g ~h ──
    m("O1A-E1 ~d defaults to one fraction digit (KILL f20)",
      r'''                    arg == FMT_DEFAULT && (arg = 0)
''', r'''                    arg == FMT_DEFAULT && (arg = 1)
''', TA),
    m("O1A-E2 ~D with the colon modifier groups with a comma (KILL k01)",
      r'''PL_locale(".", mod_colon ? "_" : ",", Int[3, 0])''', r'''PL_locale(".", ",", Int[3, 0])'''),
    m("O1A-E3 ~I groups by 4 by default (KILL f25)",
      r'''(arg == FMT_DEFAULT ? 3 : arg) & 0xff''', r'''(arg == FMT_DEFAULT ? 4 : arg) & 0xff'''),
    m("O1A-E4 ~r defaults to radix 10 (KILL e07)",
      r'''
                    arg == FMT_DEFAULT && (arg = 8)
''', r'''
                    arg == FMT_DEFAULT && (arg = 10)
'''),
    m("O1A-E5 ~1r is a valid radix (KILL e06)",
      r'''if arg < 2 || arg > 36''', r'''if arg < 1 || arg > 36'''),
    m("O1A-E6 ~37r is a valid radix (KILL e17)",
      r'''if arg < 2 || arg > 36''', r'''if arg < 2 || arg > 37'''),
    m("O1A-E7 the radix error names domain `base` (KILL e06, e17)",
      r'''ERR_DOMAIN, mk_sym(T, :radix), r)''', r'''ERR_DOMAIN, mk_sym(T, :base), r)'''),
    m("O1A-E8 ~R prints lowercase letters (KILL f24, f83)",
      r'''formatInteger(nothing, 0, arg, c == Int('r'), i, b)''', r'''formatInteger(nothing, 0, arg, true, i, b)'''),
    m("O1A-E9 ~e prints through the f format (KILL f30)",
      r'''rc = formatFloat(ld, l, c, arg, n, b)''', r'''rc = formatFloat(ld, l, Int('f'), arg, n, b)'''),
    # ── do_format: ~t ~| ~+ ──
    m("O1A-F1 ~`ct ignores its fill character (KILL f53, f57)",
      r'''r.pad = (arg == FMT_DEFAULT ? Int(' ') : arg)''', r'''r.pad = Int(' ')'''),
    m("O1A-F2 the 101st fill point is accepted (KILL e20)",
      r'''state.pending_rubber >= MAXRUBBER &&''', r'''state.pending_rubber > MAXRUBBER &&'''),
    m("O1A-F3 a fill point is placed at the start of the buffer (KILL f52, f54, f61)",
      r'''                r.place = state.buffered
                r.pad = (arg == FMT_DEFAULT''', r'''                r.place = 0
                r.pad = (arg == FMT_DEFAULT'''),
    m("O1A-F4 a bare ~| stops at column 8 (KILL f87)",
      r'''                if c == Int('|') && arg == FMT_DEFAULT
''', r'''                if false
'''),
    m("O1A-F5 ~N+ is relative to nothing: the stop is the argument (KILL f56, f62, f76, f85)",
      r'''stop = (c == Int('+') ? state.tab_stop + arg : arg)''', r'''stop = arg'''),
    m("O1A-F6 a bare ~+ stops 4 columns on (KILL f85)",
      r'''
                arg == FMT_DEFAULT && (arg = 8)
''', r'''
                arg == FMT_DEFAULT && (arg = 4)
'''),
    m("O1A-F7 a stop left of the column starts a new line without the colon modifier (KILL f59)",
      r'''if stop < COLUMN(state) && mod_colon''', r'''if stop < COLUMN(state)'''),
    m("O1A-F8 the re-indent after ~N:| pads with a space, not the fill character (KILL f78)",
      r'''state.rub[state.pending_rubber].pad''', r'''Int(' ')'''),
    m("O1A-F9 the re-indent line does not reset the column (KILL f77, f78)",
      r'''                    update_column(state, Int('\n'))
''', r'''                    nothing
'''),
    m("O1A-F10 a column stop does not set the column when the text overflowed it (KILL f88)",
      r'''                state.pos.linepos = stop
''', r'''                nothing
'''),
    m("O1A-F11 a column stop does not record the tab stop (KILL f56, f62)",
      r'''                state.tab_stop = stop
''', r'''                nothing
'''),
    m("O1A-F12 pending fill points are not flushed at the end of the text (KILL f89)",
      r'''    if state.pending_rubber != 0                # not closed ~t: flush out
''', r'''    if false
'''),
    # ── distribute_rubber, emit_rubber ──
    m("O1A-G1 the space is divided by one fill point more than there are (KILL f52, f57, f61)",
      r'''        s = space ÷ rn
''', r'''        s = space ÷ (rn + 1)
'''),
    m("O1A-G2 the remainder is taken off once per fill point (KILL f57)",
      r'''        space -= s * rn                         # distribute from the center
''', r'''        space -= s                              # distribute from the center
'''),
    m("O1A-G3 the remainder goes two characters at a time (KILL f57)",
      r'''            r[n].size += 1
''', r'''            r[n].size += 2
'''),
    m("O1A-G4 a space of one character is no padding (KILL f90)",
      r'''    if space > 0
        s = space ÷ rn''', r'''    if space > 1
        s = space ÷ rn'''),
    m("O1A-G5 emit_rubber writes one pad character too few (KILL f50)",
      r'''            for _ in 1:r.size
''', r'''            for _ in 1:(r.size - 1)
'''),
    m("O1A-G6 emit_rubber advances the character count by two (KILL f52, f99)",
      r'''        j += 1
''', r'''        j += 2
'''),
    m("O1A-G7 emit_rubber writes a space for every pad character (KILL f53, f57)",
      r'''Sputcode(r.pad, state.out) < 0 && return false''', r'''Sputcode(Int(' '), state.out) < 0 && return false'''),
    m("O1A-G8 emit_rubber leaves the fill points pending (KILL f55, f62)",
      r'''    state.pending_rubber = 0
    return true
''', r'''    return true
'''),
    m("O1A-G9 emit_rubber leaves the buffer in place (KILL f55, f62)",
      r'''    empty!(state.buffer)
''', r'''    nothing
'''),
    # ── formatInteger ──
    m("O1A-H1 formatInteger does not see a negative small integer (KILL f22, f23)",
      r'''            negative = n < 0
''', r'''            negative = false
'''),
    m("O1A-H2 formatInteger's digit of a negative small integer keeps its sign (KILL f22)",
      r'''-Int(rem(n, -radix))''', r'''Int(rem(n, -radix))'''),
    m("O1A-H3 formatInteger writes the decimal point first when there are no fraction digits (KILL f20)",
      r'''                    isempty(out) || lappend(locale.decimal_point, '.', out)
                    before = true
                    grouping === nothing || (gsize = grouping[gi])
                end
                dweight''', r'''                    lappend(locale.decimal_point, '.', out)
                    before = true
                    grouping === nothing || (gsize = grouping[gi])
                end
                dweight'''),
    m("O1A-H4 formatInteger prints zero with no fraction digits as nothing (KILL f93)",
      r'''if n == 0 && divv == 0''', r'''if n == 0'''),
    m("O1A-H5 formatInteger puts a separator before the first digit of a multiple-of-3 number (KILL f91)",
      r'''                if grouping !== nothing && gsize == 0 && n != 0   # gsize reaches 0 only with a grouping
''', r'''                if grouping !== nothing && gsize == 0   # gsize reaches 0 only with a grouping
'''),
    m("O1A-H6 formatInteger groups only once (KILL f21, f91)",
      r'''                    if grouping[gi + 1] == 0
                        gsize = grouping[gi]
                    elseif grouping[gi + 1] == 127      # CHAR_MAX
                        gsize = 0
                    else
                        gi += 1
                        gsize = grouping[gi]
                    end
                end
            end
            negative''', r'''                    if grouping[gi + 1] == 0
                        gsize = 0
                    elseif grouping[gi + 1] == 127      # CHAR_MAX
                        gsize = 0
                    else
                        gi += 1
                        gsize = grouping[gi]
                    end
                end
            end
            negative'''),
    m("O1A-H7 formatInteger prints a bignum's letters in lowercase for ~R (KILL f83)",
      r'''(!smll && radix > 10) && (buf = uppercase(buf))''', r'''false && (buf = uppercase(buf))'''),
    m("O1A-H8 formatInteger ignores the fraction digits of a bignum (KILL f27, f83)",
      r'''if grouping !== nothing || divv > 0''', r'''if grouping !== nothing'''),
    m("O1A-H9 formatInteger puts a separator after the minus of a negative bignum (KILL f92)",
      r'''gsize == 0 && e >= 1 && buf[e] != '-'   # as above
''', r'''gsize == 0 && e >= 1   # as above
'''),
    # ── formatFloat: arguments, bignum and rational paths ──
    m("O1A-I1 formatFloat's default for e/f/g is 3 digits (KILL f30, f31)",
      r'''arg = use_h ? 3 : 6''', r'''arg = 3'''),
    m("O1A-I2 formatFloat's default for h is 6 digits (KILL f33)",
      r'''arg = use_h ? 3 : 6''', r'''arg = 6'''),
    m("O1A-I3 formatFloat raises for a negative digit count of h (KILL f82)",
      r'''elseif arg < 0 && !use_h''', r'''elseif arg < 0'''),
    m("O1A-I4 formatFloat's negative digit count error names the wrong domain (KILL e10)",
      r'''mk_sym(T, :not_less_than_zero), a)''', r'''mk_sym(T, :positive_integer), a)'''),
    m("O1A-I5 ~h of a rational or an integer is not converted to a float first (KILL f48)",
      r'''    use_h && !promoteToFloatNumber(ld, f) && return false
''', r'''    nothing
'''),
    m("O1A-I6 formatFloat does not convert a small integer to a float (KILL f35)",
      r'''            promoteToFloatNumber(ld, f) || return false
        end
        if use_h''', r'''            nothing
        end
        if use_h'''),
    m("O1A-I7 ~H prints a lowercase exponent (KILL f33)",
      r'''how == Int('H') ? 'E' : 'e')''', r''''e')'''),
    m("O1A-I8 a bignum ~Nf scales by one power of ten too many (KILL f43, f44)",
      r'''    t1 = z * _fmt_pow10(arg)
''', r'''    t1 = z * _fmt_pow10(arg + 1)
'''),
    m("O1A-I9 print_mpz_f pads with zeros one digit short when the digits equal the fraction digits (KILL f41)",
      r'''    padding = nd <= arg ? arg - nd + 1 : 0''', r'''    padding = nd < arg ? arg - nd + 1 : 0'''),
    m("O1A-I10 print_mpz_f drops the minus of a negative number that rounded to 0 (KILL f41)",
      r'''    neg && (s = "-" * s)
''', r'''    nothing
'''),
    m("O1A-I11 print_mpz_f writes a point after ~0f (KILL f42, f43)",
      r'''    if arg > 0
        n = ncodeunits(s)''', r'''    if arg >= 0
        n = ncodeunits(s)'''),
    m("O1A-I12 a rational ~Nf rounds with a third of the denominator (KILL f42)",
      r'''    t2 = div(d, 2)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    _fmt_print_mpz_f!''', r'''    t2 = div(d, 3)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    _fmt_print_mpz_f!'''),
    m("O1A-I13 a negative rational ~Nf rounds toward zero (KILL f42)",
      r'''    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    _fmt_print_mpz_f!''', r'''    t1 = t1 + t2
    t1 = abs(div(t1, d))
    _fmt_print_mpz_f!'''),
    m("O1A-I14 print_mpz_e writes a point after ~0e (KILL f45)",
      r'''    if arg > 0
        push!(out, dpb)''', r'''    if arg >= 0
        push!(out, dpb)'''),
    m("O1A-I15 print_mpz_e gives a negative exponent the plus sign (KILL f39, f95)",
      r'''push!(out, ex < 0 ? UInt8('-') : UInt8('+'))            # "%+03d"''', r'''push!(out, UInt8('+'))'''),
    m("O1A-I16 print_mpz_e does not zero-pad the exponent (KILL f39)",
      r'''lpad(string(abs(ex)), 2, '0')''', r'''lpad(string(abs(ex)), 1, '0')'''),
    m("O1A-I17 a bignum ~Ne takes the exponent guess as exact (KILL f94)",
      r'''        _fmt_pow10(ex) > t1 && (ex -= 1)                    # correct exponent
''', r'''        nothing
'''),
    m("O1A-I18 a bignum ~Ne rounds with +4, not +5 (KILL f46)",
      r'''            t1 += 5
''', r'''            t1 += 4
'''),
    m("O1A-I19 a bignum ~Ne treats a digit count equal to the exponent as fewer (KILL f94)",
      r'''        if ex > arg
            t2 = _fmt_pow10(ex - arg - 1)''', r'''        if ex >= arg
            t2 = _fmt_pow10(ex - arg - 1)'''),
    m("O1A-I20 a rational ~Ne does not correct an exponent guess that is one too small (KILL f95)",
      r'''        t2 > abs(t1) && (ex += 1)                           # correct exponent
''', r'''        nothing
'''),
    m("O1A-I21 a rational ~Ne does not correct the exponent of an exact power of ten (KILL f39, f95)",
      r'''        t2 == abs(t1) && Rational{BigInt}(t1) == inv(q) && (ex += 1)
''', r'''        nothing
'''),
    m("O1A-I22 a rational ~Ne above 1 divides when the exponent is within the digits (KILL f40)",
      r'''    if ge1 && ex > arg
        t1 = div(n, t1)''', r'''    if ge1
        t1 = div(n, t1)'''),
    m("O1A-I23 a rational ~Ne rounds with a third of the denominator (KILL f40)",
      r'''    t2 = div(d, 2)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    if _fmt_pow10''', r'''    t2 = div(d, 3)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    if _fmt_pow10'''),
    m("O1A-I24 a rational ~Ne does not renormalise a rounded-up mantissa (KILL f40)",
      r'''    if _fmt_pow10(arg + 1) == t1
''', r'''    if false
'''),
    m("O1A-I25 the ~Ng digits are cut, not rounded (KILL f37)",
      r'''    w = v * _fmt_pow10q(P - 1 - X) + 1 // 2
''', r'''    w = v * _fmt_pow10q(P - 1 - X)
'''),
    m("O1A-I26 the ~Ng digits keep the carry's extra digit (KILL f38)",
      r'''    if ndigits(r) > P
''', r'''    if false
'''),
    m("O1A-I27 ~Ng uses the exponent form from exponent -5 down only (KILL f38)",
      r'''    if X < -4 || X >= P
        frac''', r'''    if X < -5 || X >= P
        frac'''),
    m("O1A-I28 ~Ng prints a lowercase exponent for ~G (KILL f37, f45)",
      r'''UInt8(how == Int('G') ? 'E' : 'e')''', r'''UInt8('e')'''),
    m("O1A-I29 ~0g counts as 0 significant digits (KILL f37)",
      r'''    P = max(arg, 1)
    neg && push!(out, UInt8('-'))''', r'''    P = arg
    neg && push!(out, UInt8('-'))'''),
    # ── formatFloat: the double path (C printf) ──
    m("O1A-J1 the double path prints NaN as inf (KILL f49, f96)",
      r'''s = isnan(f) ? "nan" : "inf"''', r'''s = isnan(f) ? "inf" : "nan"'''),
    m("O1A-J2 the double path prints a capital directive's NaN in lowercase (KILL f96)",
      r'''    upper = how == Int('E') || how == Int('F') || how == Int('G')
''', r'''    upper = false
'''),
    m("O1A-J3 the double path gives ~E a lowercase exponent for finite numbers (KILL f34)",
      r'''expch = UInt8(upper ? 'E' : 'e')''', r'''expch = UInt8('e')'''),
    m("O1A-J4 the double path's ~g keeps trailing zeros of the exponent form (KILL f32)",
      r'''        occursin('.', mant) && (mant = String(rstrip(rstrip(mant, '0'), '.')))
''', r'''        nothing
'''),
    m("O1A-J5 the double path's ~g switches to the exponent form from exponent -5 down only (KILL f32)",
      r'''    if X < -4 || X >= P
        mant''', r'''    if X < -5 || X >= P
        mant'''),
    m("O1A-J6 the double path's ~g prints the fixed form with a digit too many (KILL f32)",
      r'''Base.Ryu.writefixed(f, P - 1 - X)''', r'''Base.Ryu.writefixed(f, P - X)'''),
    m("O1A-J7 the double path's ~0g counts as 0 significant digits (KILL f96)",
      r'''    P = max(arg, 1)                                         # %g: precision 0 is 1''', r'''    P = arg'''),
    # ── prepare_sub_format, end_sub_format ──
    m("O1A-K1 a call-back writes straight to the stream while fill points are pending (KILL f75, f97)",
      r'''    if fstate.pending_rubber == 0 && fdp !== nothing && fdp.linepos == COLUMN(fstate)''', r'''    if true && fdp !== nothing && fdp.linepos == COLUMN(fstate)'''),
    m("O1A-K2 a call-back's string output moves the column by its length only (KILL f97)",
      r'''            state.fstate.pos.linepos = c0 + lp''', r'''            state.fstate.pos.linepos = lp'''),
    m("O1A-K3 a call-back that wrote straight to the stream does not hand its column back (KILL f67, f74)",
      r'''            p.linepos = sub.linepos
''', r'''            nothing
'''),
    m("O1A-K4 a call-back that wrote straight to the stream leaves the current output on the format stream (KILL f65, f66)",
      r'''        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = state.old_stream
''', r'''        nothing
'''),
    m("O1A-K5 a call-back's string output is dropped (KILL f97)",
      r'''            rc = oututf8(state.fstate, state.bufp[]::Vector{UInt8}, 1, state.sizep[] + 1)
''', r'''            nothing
'''),
]
