# ORIGINAL: U64's mutant list - a test tool with no twin in swipl-devel.
# tools/mutants/U64.py - the mutation battery of PKG2-5 step 1 (pl-error.c pl_get_uint64 / PL_get_uint64_ex, pl-fli.c PL_get_uint64: src/pl-error.jl, src/pl-fli.jl),
# run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as PCRE1.py): `id`, `file`, `old` (EXACTLY once in
# its file), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_fli_uint64.jl, the testset named in each id (written from the file's text; NOT run:
# nothing was compiled for this list). Every `old` was checked to occur exactly once in its file and `new` != `old` (python3 -I count, no Julia).
# TARGETS (audit D-0238): the function has no caller in the kernel yet (the first is re_get_options of the pcre port), so its own test file is every target.
T = ["test/core_lang/test_fli_uint64.jl"]
TARGETS = T
E = "src/pl-error.jl"
F = "src/pl-fli.jl"
MUTANTS = [
    dict(id="U64-1 the tagged-int branch accepts a negative value (KILL the negative rows -1, -5: a UInt64 wrap)", file=E, targets=T,
         old="valInt(x) >= 0 && return UInt64(valInt(x))", new="valInt(x) >= -1 && return UInt64(valInt(x) % UInt64)"),
    dict(id="U64-2 the tagged-int branch refuses zero (KILL the row 0)", file=E, targets=T,
         old="valInt(x) >= 0 && return UInt64(valInt(x))", new="valInt(x) > 0 && return UInt64(valInt(x))"),
    dict(id="U64-3 the tagged negative raises even for the plain form (KILL the plain no-error check of -1)", file=E, targets=T,
         old="        ex && PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)\n        return nothing\n    end\n    if k == DU_VALUE\n",
         new="        PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)\n        return nothing\n    end\n    if k == DU_VALUE\n"),
    dict(id="U64-4 the tagged negative raises nothing for the _ex form (KILL the negative rows' error check)", file=E, targets=T,
         old="        ex && PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)\n        return nothing\n    end\n    if k == DU_VALUE\n",
         new="        return nothing\n    end\n    if k == DU_VALUE\n"),
    dict(id="U64-5 the int64 branch accepts a negative value (KILL the row -9223372036854775808, a value-table int64: a UInt64 wrap)", file=E, targets=T,
         old="v >= 0 && return UInt64(v)", new="v >= typemin(Int64) && return v % UInt64"),
    dict(id="U64-6 the int64 negative raises nothing (KILL the row -9223372036854775808 when it is a value-table int64)", file=E, targets=T,
         old="                v >= 0 && return UInt64(v)\n                ex && PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)\n",
         new="                v >= 0 && return UInt64(v)\n"),
    dict(id="U64-7 the bignum branch is taken for an int64 (the integer_is_int64 test negated: KILL every in-range row)", file=E, targets=T,
         old="if integer_is_int64(p)                          # case V_INTEGER", new="if !integer_is_int64(p)                          # case V_INTEGER"),
    dict(id="U64-8 status 0 is read as an error (KILL the rows 2^63 and 2^64-1)", file=E, targets=T,
         old="status == 0 && return u", new="status == 5 && return u"),
    dict(id="U64-9 a negative bignum raises representation_error (KILL the rows -9223372036854775809, -18446744073709551616)", file=E, targets=T,
         old="if status == -1\n                    PL_error(ld, ERR_DOMAIN", new="if status == 7\n                    PL_error(ld, ERR_DOMAIN"),
    dict(id="U64-10 a too-big bignum raises domain_error (KILL the rows past uint64)", file=E, targets=T,
         old="PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :uint64_t))", new="PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), t)"),
    dict(id="U64-11 the representation error names another type (KILL the rows past uint64)", file=E, targets=T,
         old="mk_sym(T, :uint64_t)", new="mk_sym(T, :int64_t)"),
    dict(id="U64-12 the bignum errors are raised for the plain form too (KILL the plain no-error checks of the bignum rows)", file=E, targets=T,
         old="            if ex\n                if status == -1", new="            if true\n                if status == -1"),
    dict(id="U64-13 a non-integer number is accepted: the isInteger test dropped (KILL the 1.5 row)", file=E, targets=T,
         old="        if isInteger(p)\n            if integer_is_int64(p)                          # case V_INTEGER",
         new="        if true\n            if integer_is_int64(p)                          # case V_INTEGER"),
    dict(id="U64-14 the type error is raised for the plain form (KILL the plain no-error checks of the type rows)", file=E, targets=T,
         old="    ex && PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)    # a variable", new="    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)    # a variable"),
    dict(id="U64-15 the type error names another type (KILL the type rows)", file=E, targets=T,
         old="    ex && PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)    # a variable", new="    ex && PL_error(ld, ERR_TYPE, mk_sym(T, :atom), t)    # a variable"),
    dict(id="U64-16 the type error is not raised for the _ex form (KILL the type rows' error check)", file=E, targets=T,
         old="    ex && PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)    # a variable", new="    false && PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)    # a variable"),
    dict(id="U64-17 PL_get_uint64_ex reads without raising (KILL every error check of the _ex form)", file=E, targets=T,
         old="PL_get_uint64_ex(ld::PL_local_data{T}, t::term_t) where {T} = pl_get_uint64(ld, t, true)",
         new="PL_get_uint64_ex(ld::PL_local_data{T}, t::term_t) where {T} = pl_get_uint64(ld, t, false)"),
    dict(id="U64-18 PL_get_uint64 raises (KILL every plain no-error check)", file=F, targets=T,
         old="PL_get_uint64(ld::PL_local_data{T}, t::term_t) where {T} = pl_get_uint64(ld, t, false)",
         new="PL_get_uint64(ld::PL_local_data{T}, t::term_t) where {T} = pl_get_uint64(ld, t, true)"),
    dict(id="U64-19 an unbound term is read as a value: the DU_VALUE test of the second branch dropped (KILL the X row)", file=E, targets=T,
         old="    if k == DU_VALUE\n        p = _value_term(ld, x)                              # PL_get_number(t, &n)",
         new="    if true\n        p = _value_term(ld, x)                              # PL_get_number(t, &n)"),
]
