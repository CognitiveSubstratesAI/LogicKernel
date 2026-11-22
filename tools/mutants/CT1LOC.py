# ORIGINAL: the CT1LOC mutant list — the port of pl-file.c's locale(Locale) of open/4 (openStream: :4204-4217, :4377-4380), of set_stream/2 (:2434-2446) and of the
# stream property locale (stream_locale_prop :5110-5116) (swipl-devel 18168e62); no swipl-devel counterpart.
# tools/mutants/CT1LOC.py — the mutation battery of the CT1-LOC-1 code (src/os/pl-file.jl: `openStream`'s locale option, `set_stream`'s `:locale` arm, `stream_locale_prop`), run ONCE,
# in CI (.github/workflows/mutation.yml; locally one mutant under debug is fine, no local list: D-0220). Format: tools/mutate_drive.py's (as B1.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`; T3's `aimed_by` field repeats the `(aimed by ...)` of the id. CT1LOC-1..6 are the T3
# candidates of `stream_locale_prop` (t3_mutant_rows.py --function stream_locale_prop, all six kept); CT1LOC-7..19 are written by hand (T3 --lines did not narrow the
# candidates of `openStream` and `set_stream` to the changed lines: 298 for the whole function; the hand rows are the changed lines' sites).
# KILL rows are rows of test/core_text/test_stream_locale_swipl.jl: t0 (locale(Alias): the alias answers), t1 (a blob given, the alias destroyed), t2 (no option and the
# standard streams: `default`), t3 (set_stream/2 by alias, then by blob, a second stream untouched), t4 (the four errors of open/4 and of set_stream/2), t5 (`~:d` by the
# stream's locale), the white-box testset "the reference count" (wb_open, wb_bad, wb_set) and the white-box testset of stream_locale_prop (a stream with no locale, then one
# with the default locale). The KILL lists are what the rows are EXPECTED to do (read, not run): the battery's verdict is the evidence. Written by a coding agent with NO
# Julia process.
# EQUIVALENT: none declared.
# TARGETS (audit D-0238): the new file, and every test file that opens a stream through open/4 with options, calls set_stream/2 or enumerates stream_property/2 on a
# stream the mutated code handles (git grep -l stream_property / set_stream over test/, the ones that open Prolog-visible streams): test_open_close_swipl.jl,
# test_stream_swipl.jl, test_streams_a_swipl.jl, test_lane_d_swipl.jl, test_s2a_swipl.jl (stream_property rows), test_locale_stream_swipl.jl and test_locale_fmt_swipl.jl (the
# stream's locale, `~:d`). The files that only OPEN a stream and never name the option leave the `nothing` arms alone: their kill is the same row of the new file.
# MAY SURVIVE (the battery decides): CT1LOC-9 (after a refused `getLocaleEx` the open goes on with the error pending: t4's E1-E4 and wb_bad should see the leftover error or the
#   file; if openStream returns the stream and the caller reads the exception first, the row survives and wb_bad needs a file-exists check).
P = "src/os/pl-file.jl"
T = [
    "test/core_text/test_stream_locale_swipl.jl",
    "test/files/test_open_close_swipl.jl",
    "test/files/test_stream_swipl.jl",
    "test/files/test_streams_a_swipl.jl",
    "test/core_lang/test_lane_d_swipl.jl",
    "test/core_lang/test_s2a_swipl.jl",
    "test/core_text/test_locale_stream_swipl.jl",
    "test/core_text/test_locale_fmt_swipl.jl",
]
TARGETS = T
MUTANTS = [
    dict(id="CT1LOC-1 cmp: `===` -> `!==` in stream_locale_prop (aimed by t0, t1, t2, t3, the white-box stream_locale_prop testset)", file=P, targets=T,
         old="    l = s.locale\n    l === nothing && return false",
         new="    l = s.locale\n    l !== nothing && return false", aimed_by="t0, t1, t2, t3, the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-2 logic: `&&` -> `||` in stream_locale_prop (aimed by t0, t1, t2, t3, the white-box stream_locale_prop testset)", file=P, targets=T,
         old="    l = s.locale\n    l === nothing && return false",
         new="    l = s.locale\n    l === nothing || return false", aimed_by="t0, t1, t2, t3, the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-3 bool: `return false` -> `return true` in stream_locale_prop (aimed by the white-box stream_locale_prop testset)", file=P, targets=T,
         old="    l = s.locale\n    l === nothing && return false",
         new="    l = s.locale\n    l === nothing && return true", aimed_by="the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-4 stmt: `l === nothing && return false` -> `nothing` in stream_locale_prop (aimed by the white-box stream_locale_prop testset)", file=P, targets=T,
         old="    l = s.locale\n    l === nothing && return false",
         new="    l = s.locale\n    nothing", aimed_by="the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-5 ret: the unifyLocale answer negated in stream_locale_prop (aimed by t0, t1, t2, t3, the white-box stream_locale_prop testset)", file=P, targets=T,
         old="unifyLocale(_query_gd(ld), ld, prop, l::PL_locale_rec{T}, true)",
         new="!(unifyLocale(_query_gd(ld), ld, prop, l::PL_locale_rec{T}, true))", aimed_by="t0, t1, t2, t3, the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-6 bool: `true` -> `false` (the alias flag of unifyLocale) in stream_locale_prop (aimed by t0, t3, the white-box stream_locale_prop testset)", file=P, targets=T,
         old="unifyLocale(_query_gd(ld), ld, prop, l::PL_locale_rec{T}, true)",
         new="unifyLocale(_query_gd(ld), ld, prop, l::PL_locale_rec{T}, false)", aimed_by="t0, t3, the white-box stream_locale_prop testset"),
    dict(id="CT1LOC-7 branch: openStream reads the locale option only when it is not given (`t13 isa Int` -> `false`) (aimed by t0, t1, t4, t5, wb_open)", file=P, targets=T,
         old="        if t13 isa Int ",
         new="        if false ", aimed_by="t0, t1, t4, t5, wb_open"),
    dict(id="CT1LOC-8 index: openStream takes the term of the `create` option (`vals[13]` -> `vals[12]`) (aimed by t0, t1, t4, t5, wb_open)", file=P, targets=T,
         old="        t13 = vals[13]\n",
         new="        t13 = vals[12]\n", aimed_by="t0, t1, t4, t5, wb_open"),
    dict(id="CT1LOC-9 stmt: openStream goes on after a refused getLocaleEx (`locale === nothing && return nothing` -> `nothing`) (aimed by t4, wb_bad)", file=P, targets=T,
         old="            locale === nothing && return nothing\n        end\n        unicode_atoms_opt",
         new="            nothing\n        end\n        unicode_atoms_opt", aimed_by="t4, wb_bad"),
    dict(id="CT1LOC-10 arg: openStream asks getLocaleEx about the mode, not the option (`t13` -> `mode`) (aimed by t0, t1, t5, wb_open)", file=P, targets=T,
         old="            locale = getLocaleEx(gd, ld, t13)\n",
         new="            locale = getLocaleEx(gd, ld, mode)\n", aimed_by="t0, t1, t5, wb_open"),
    dict(id="CT1LOC-11 cmp: openStream gives the stream the locale only when none was given (`locale !== nothing` -> `locale === nothing`) (aimed by t0, t1, t2, t5, wb_open)", file=P, targets=T,
         old="    if locale !== nothing\n        Ssetlocale(s, locale)\n",
         new="    if locale === nothing\n        Ssetlocale(s, locale)\n", aimed_by="t0, t1, t2, t5, wb_open"),
    dict(id="CT1LOC-12 stmt: openStream does not give the stream the locale (`Ssetlocale(s, locale)` -> `nothing`) (aimed by t0, t1, t5, wb_open)", file=P, targets=T,
         old="        Ssetlocale(s, locale)\n        releaseLocale(locale)",
         new="        nothing\n        releaseLocale(locale)", aimed_by="t0, t1, t5, wb_open"),
    dict(id="CT1LOC-13 stmt: openStream keeps the reference getLocaleEx acquired (`releaseLocale(locale)` -> `nothing`) (aimed by wb_open)", file=P, targets=T,
         old="        releaseLocale(locale)                                   # acquired by getLocaleEx",
         new="        nothing                                   # acquired by getLocaleEx", aimed_by="wb_open"),
    dict(id="CT1LOC-14 call: openStream takes a second reference (`releaseLocale(locale)` -> `acquireLocale(locale)`) (aimed by wb_open)", file=P, targets=T,
         old="        releaseLocale(locale)                                   # acquired by getLocaleEx",
         new="        acquireLocale(locale)                                   # acquired by getLocaleEx", aimed_by="wb_open"),
    dict(id="CT1LOC-15 branch: set_stream/2's `:locale` arm is never taken (`aname === :locale ` -> `aname === :locale_ `) (aimed by t3, t4, t5, wb_set)", file=P, targets=T,
         old="    elseif aname === :locale                        # locale(Locale)\n",
         new="    elseif aname === :locale_                       # locale(Locale)\n", aimed_by="t3, t4, t5, wb_set"),
    dict(id="CT1LOC-16 stmt: set_stream/2 goes on after a refused getLocaleEx (`val === nothing && return false` -> `nothing`) (aimed by t4)", file=P, targets=T,
         old="        val = getLocaleEx(gd, ld, a)\n        val === nothing && return false\n        Ssetlocale(s, val) ",
         new="        val = getLocaleEx(gd, ld, a)\n        nothing\n        Ssetlocale(s, val) ", aimed_by="t4"),
    dict(id="CT1LOC-17 arg: set_stream/2 asks getLocaleEx about the stream term, not the value (`a` -> `stream`) (aimed by t3, t4, t5, wb_set)", file=P, targets=T,
         old="        val = getLocaleEx(gd, ld, a)\n        val === nothing && return false\n        Ssetlocale(s, val) ",
         new="        val = getLocaleEx(gd, ld, stream)\n        val === nothing && return false\n        Ssetlocale(s, val) ", aimed_by="t3, t4, t5, wb_set"),
    dict(id="CT1LOC-18 stmt: set_stream/2 does not set the locale (`Ssetlocale(s, val)` -> `nothing`) (aimed by t3, t5)", file=P, targets=T,
         old="        Ssetlocale(s, val) ",
         new="        nothing ", aimed_by="t3, t5"),
    dict(id="CT1LOC-19 bool: set_stream/2's locale answers false (`return true` after Ssetlocale) (aimed by t3, t5, wb_set)", file=P, targets=T,
         old="        Ssetlocale(s, val)                          # upstream's `== 0` is always true here: no permission_error branch\n        return true\n",
         new="        Ssetlocale(s, val)                          # upstream's `== 0` is always true here: no permission_error branch\n        return false\n", aimed_by="t3, t5, wb_set"),
]
