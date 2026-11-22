# ORIGINAL: FLI-API group 1 (audit D-0777 (4)(a)) — the pl-fli.c API functions foreign code calls that the
# kernel did not carry: PL_put_bool, PL_put_pointer, PL_put_functor, PL_put_list, PL_get_uintptr,
# PL_get_pointer, PL_get_arg (pl-fli.c PL_get_arg_sz), PL_get_compound_name_arity (PL_get_compound_name_arity_sz),
# PL_unify_int64_ex, PL_unify_pointer (src/pl-fli.jl); group 2: PL_new_atom, PL_new_atom_mbchars, PL_new_functor_sz,
# PL_new_functor, PL_functor_name, PL_functor_arity, PL_atom_chars, PL_atom_nchars, PL_atom_wchars, PL_atom_mbchars,
# PL_get_atom_chars; group 3: PL_context, PL_new_module, PL_pred, PL_predicate, PL_predicate_info (resolveModule: skipped, wip/clib1 defines it).
# group E1: PL_put_atom_chars, PL_put_atom_nchars, PL_put_string_chars, PL_put_string_nchars, PL_put_chars,
# PL_put_list_ncodes, PL_put_list_codes, PL_put_list_nchars, PL_put_list_chars, PL_unify_atom_chars, PL_unify_atom_nchars,
# PL_unify_string_chars, PL_unify_string_nchars, PL_unify_list_ncodes, PL_unify_list_codes, PL_unify_list_nchars,
# PL_unify_list_chars (PL_unify_chars: skipped, wip/clib-uri and wip/clib1 define it); group E2: PL_cvt_i_schar,
# PL_cvt_i_uchar, _PL_cvt_i_short, PL_cvt_i_int64, PL_cvt_i_uint64, PL_get_list_nchars, PL_get_nchars, PL_get_chars,
# PL_cvt_encoding, uncachedCodeToAtom, cleanupCodeToAtom (PL_get_wchars, PL_unify_wchars, PL_unify_wchars_diff: skipped,
# wip/clib-uri defines them).
# group D: initUCSAtoms, isUCSAtom, get_atom_ptr_text, get_atom_text, get_string_text, compareUCSAtom, saveUCSAtom, loadUCSAtom,
# blob_write_usc_atom, is_text_value, get_value_text, PL_get_text_as_atom.
# group F: PL_get_module, _PL_get_atomic, _PL_put_atomic, put_xpce_ref_arg, PL_term_type, PL_unify_output, PL_unify_termv,
# PL_unify_term (their text tags call PL_unify_chars and PL_unify_wchars of wip/clib-uri / wip/clib1: rows on those tags need that merge).
# test/core_lang/test_fli_api1_cells.jl — on every term type.
# LK-ONLY rows: these are C-interface contracts no Prolog goal asks swipl directly (a foreign function calls them;
# the kernel's built-ins reach them only through the writers already compared in test_fli_unify_cells.jl), so each
# expected value is written from pl-fli.c at the pin (swipl-devel 18168e62), the line cited per row. The meter
# row: the readers and writers on terms on the stack make no cold import.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_fa_k(i) = _rg(Int64(i))

"An engine with the values of `vs` put into term references; `(ld, t)` — the value `vs[i]` in reference `t + i - 1`."
function _fa_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_fa_counts(ld) = ld.cold_imports

"The functor word of `name/arity` on `ld`."
_fa_functor(ld, name::String, arity::Int) =
    LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs(name)), arity)

# LK-ONLY (pl-fli.c:3053-3059): PL_put_bool puts the atom true for a non-zero value, false for zero.
@testset "LK-ONLY: PL_put_bool (pl-fli.c:3053)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2)])
    @test LK.PL_put_bool(ld, t, true)
    @test LK.PL_put_bool(ld, t + 1, false)
    @test lk_name(LK.PL_get_atom(ld, t)) === Symbol("true")
    @test lk_name(LK.PL_get_atom(ld, t + 1)) === Symbol("false")
    @test LK.PL_get_stdbool(ld, t) === true && LK.PL_get_stdbool(ld, t + 1) === false
end

# LK-ONLY (pl-fli.c:3275-3281, :2461-2475, :2376-2394, :3810-3815; pl-inline.h:843-860): a pointer is an integer;
# on a 64-bit platform pointerToInt and intToPointer are the identity, so a pointer's bits are an int64_t.
# PL_get_uintptr refuses a negative integer (:2386); PL_get_pointer does not (the bits of a high address).
@testset "LK-ONLY: the pointer API reads and writes an integer (pl-fli.c PL_put_pointer, PL_get_pointer, PL_unify_pointer)" begin
    hi = typemax(UInt)                       # the int64_t -1
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rs("a"), _fa_k(4096), _fa_k(-5)])
    @test LK.PL_put_pointer(ld, t, UInt(4096))
    @test LK.PL_get_int64(ld, t) == 4096
    @test LK.PL_get_pointer(ld, t) === UInt(4096)
    @test LK.PL_put_pointer(ld, t + 1, hi)
    @test LK.PL_get_int64(ld, t + 1) == -1
    @test LK.PL_get_pointer(ld, t + 1) === hi
    @test LK.PL_get_pointer(ld, t + 3) === nothing           # an atom is no pointer
    @test LK.PL_get_pointer(ld, t + 2) === nothing           # nor a variable
    # PL_get_uintptr: a non-negative integer, as size_t
    @test LK.PL_get_uintptr(ld, t) === UInt(4096)
    @test LK.PL_get_uintptr(ld, t + 1) === nothing           # val < 0
    @test LK.PL_get_uintptr(ld, t + 5) === nothing
    @test LK.PL_get_uintptr(ld, t + 3) === nothing
    # PL_unify_pointer: a variable is bound to the integer, an integer must be equal
    @test LK.PL_unify_pointer(ld, t + 2, UInt(4096))
    @test LK.PL_get_pointer(ld, t + 2) === UInt(4096)
    @test LK.PL_unify_pointer(ld, t + 4, UInt(4096))
    @test !LK.PL_unify_pointer(ld, t + 4, UInt(4097))
    @test !LK.PL_unify_pointer(ld, t + 3, UInt(4096))        # an atom: no unification, no exception
    @test LK.PL_unify_pointer(ld, t + 5, reinterpret(UInt, -5))
end

# LK-ONLY (pl-fli.c:3740-3744, unify_int64_ex at :3690-3735 with ex = true): a non-integer, bound, is a type error
# where PL_unify_int64 (ex = false) just fails; a variable and an equal integer succeed, an unequal one fails.
@testset "LK-ONLY: PL_unify_int64_ex (pl-fli.c:3740)" begin
    ld, t = _fa_engine(_R[_rv(1), _fa_k(7)])
    @test LK.PL_unify_int64_ex(ld, t, 12) && LK.PL_get_integer(ld, t) == 12
    @test LK.PL_unify_int64_ex(ld, t + 1, 7)
    @test !LK.PL_unify_int64_ex(ld, t + 1, 8)
    ld2, t2 = _fa_engine(_R[_rs("a")])
    @test !LK.PL_unify_int64(ld2, t2, 3)
    @test ld2.exception_term == 0                            # PL_unify_int64: no exception
    @test !LK.PL_unify_int64_ex(ld2, t2, 3)
    @test ld2.exception_term != 0                            # type_error(integer, a)
end

# LK-ONLY (pl-fli.c:3298-3319, :3322-3335): PL_put_functor puts a term of the functor with fresh variable
# arguments, or the atom for arity 0; PL_put_list puts a list cell with two fresh variables.
@testset "LK-ONLY: PL_put_functor and PL_put_list put terms of fresh variables (pl-fli.c:3298, :3322)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4)])
    @test LK.PL_put_functor(ld, t, _fa_functor(ld, "f", 3))
    @test LK.PL_is_functor(ld, t, _rs("f"), 3)
    a = LK.PL_new_term_ref(ld)
    for i in 1:3
        @test LK.PL_get_arg(ld, i, t, a) && LK.PL_is_variable(ld, a)
    end
    # the three arguments are three DISTINCT variables: binding the first leaves the others unbound
    b = LK.PL_new_term_ref(ld)
    @test LK.PL_get_arg(ld, 1, t, a) && LK.PL_unify_atom(ld, a, _rs("x"))
    @test LK.PL_get_arg(ld, 2, t, b) && LK.PL_is_variable(ld, b)
    # arity 0: the atom the functor names (:3306)
    @test LK.PL_put_functor(ld, t + 1, _fa_functor(ld, "g", 0))
    @test LK.PL_is_atom(ld, t + 1) && lk_name(LK.PL_get_atom(ld, t + 1)) === :g
    # a list cell
    @test LK.PL_put_list(ld, t + 2)
    @test LK.PL_is_pair(ld, t + 2) && !LK.PL_is_list(ld, t + 2)   # a partial list: the tail is unbound
    h, tl = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.PL_get_list(ld, t + 2, h, tl)
    @test LK.PL_is_variable(ld, h) && LK.PL_is_variable(ld, tl)
    @test LK.PL_unify_nil(ld, tl) && LK.PL_is_list(ld, t + 2)
end

# LK-ONLY (pl-fli.c:2637-2656, :2521-2538): PL_get_arg is false for a term that is no compound, for index 0 and for
# an index past the arity; PL_get_compound_name_arity reads a compound only, where PL_get_name_arity also reads an atom.
@testset "LK-ONLY: PL_get_arg and PL_get_compound_name_arity (pl-fli.c:2637, :2521)" begin
    ld, t = _fa_engine(
        _R[_rf("f", _rs("a"), _fa_k(2), _rv(3)), _rs("atom"), _fa_k(9), _rv(4), _rlist(_fa_k(1)), _rnil()]
    )
    a = LK.PL_new_term_ref(ld)
    @test LK.PL_get_arg(ld, 1, t, a) && lk_name(LK.PL_get_atom(ld, a)) === :a
    @test LK.PL_get_arg(ld, 2, t, a) && LK.PL_get_integer(ld, a) == 2
    @test LK.PL_get_arg(ld, 3, t, a) && LK.PL_is_variable(ld, a)
    @test !LK.PL_get_arg(ld, 0, t, a)                        # index > 0
    @test !LK.PL_get_arg(ld, 4, t, a)                        # --index < arity
    @test !LK.PL_get_arg(ld, -1, t, a)                       # no argument (upstream's wrapper: a fatal error)
    @test !LK.PL_get_arg(ld, 1, t + 1, a)                    # an atom
    @test !LK.PL_get_arg(ld, 1, t + 2, a) && !LK.PL_get_arg(ld, 1, t + 3, a)
    @test LK.PL_get_arg(ld, 1, t + 4, a) && LK.PL_get_integer(ld, a) == 1    # a list cell: '[|]'(1, [])
    @test LK.PL_get_arg(ld, 2, t + 4, a) && LK.PL_get_nil(ld, a)
    @test !LK.PL_get_arg(ld, 1, t + 5, a)                    # [] is no compound
    n, ar = LK.PL_get_compound_name_arity(ld, t)
    @test lk_name(n) === :f && ar == 3
    @test LK.PL_get_compound_name_arity(ld, t + 1) === nothing       # an atom (PL_get_name_arity reads it)
    @test LK.PL_get_name_arity(ld, t + 1) !== nothing
    @test LK.PL_get_compound_name_arity(ld, t + 2) === nothing
    @test LK.PL_get_compound_name_arity(ld, t + 3) === nothing
    n, ar = LK.PL_get_compound_name_arity(ld, t + 4)
    @test lk_name(n) === Symbol("[|]") && ar == 2
    # a compound whose head is no symbol (the kernel's `$expr/n`): named $expr, all its children its arguments
    ld2, t2 = _fa_engine(_R[mk_expr(_R, _R[_rv(9), _rs("a")])])
    n, ar = LK.PL_get_compound_name_arity(ld2, t2)
    @test lk_name(n) === Symbol("\$expr") && ar == 2
    a2 = LK.PL_new_term_ref(ld2)
    @test LK.PL_get_arg(ld2, 2, t2, a2) && lk_name(LK.PL_get_atom(ld2, a2)) === :a
    @test !LK.PL_get_arg(ld2, 3, t2, a2)
end

# LK-ONLY (pl-fli.c:683-688): PL_new_atom is lookupAtom(s, strlen(s)) — the text up to the first 0, as ISO Latin-1 bytes;
# one text is one atom, so the atom of the byte 0xe9 is the atom of the character U+00E9 (a text atom of one byte).
@testset "LK-ONLY: PL_new_atom (pl-fli.c:683)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    a = LK.PL_new_atom(ld, Vector{UInt8}("hello"))
    @test lk_name(a) === :hello
    @test LK._atom_word!(ld, a) == LK._atom_word!(ld, _rs("hello"))
    @test lk_name(LK.PL_new_atom(ld, UInt8[0x61, 0x00, 0x62])) === :a           # strlen: cut at the first 0
    @test lk_name(LK.PL_new_atom(ld, UInt8[])) === Symbol("")
    e = LK.PL_new_atom(ld, UInt8[0xe9])
    @test lk_name(e) === Symbol("é")
    @test LK._atom_word!(ld, e) == LK._atom_word!(ld, _rs("é"))
    @test LK.PL_put_atom(ld, t, a) && lk_name(LK.PL_get_atom(ld, t)) === :hello
end

# LK-ONLY (pl-fli.c:703-722): PL_new_atom_mbchars reads len bytes (len -1: strlen) as UTF-8 with REP_UTF8, else as ISO
# Latin-1 (:712-713); REP_MB would be ENC_ANSI, unwritten (refused by name). textToAtom canonicalises, so the UTF-8
# text of U+00E9 is the atom of the byte 0xe9, and a text with a code point past 0xff is a wide atom.
# A NUL in the text is the kernel's refusal (a symbol cannot hold it), raised before the atom is made.
@testset "LK-ONLY: PL_new_atom_mbchars (pl-fli.c:703)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    u8 = Int(LK.REP_UTF8)
    @test lk_name(LK.PL_new_atom_mbchars(ld, u8, 2, UInt8[0xc3, 0xa9])) === Symbol("é")
    @test LK._atom_word!(ld, LK.PL_new_atom_mbchars(ld, u8, 2, UInt8[0xc3, 0xa9])) ==
          LK._atom_word!(ld, LK.PL_new_atom(ld, UInt8[0xe9]))
    # no REP_UTF8: the same two bytes are two Latin-1 characters
    @test lk_name(LK.PL_new_atom_mbchars(ld, 0, 2, UInt8[0xc3, 0xa9])) === Symbol("Ã©")
    @test lk_name(LK.PL_new_atom_mbchars(ld, u8, 3, UInt8[0xe2, 0x82, 0xac])) === Symbol("€")
    @test lk_name(LK.PL_new_atom_mbchars(ld, u8, 2, Vector{UInt8}("abc"))) === :ab        # len bytes
    @test lk_name(LK.PL_new_atom_mbchars(ld, u8, -1, UInt8[0x61, 0x62, 0x00, 0x63])) === :ab    # len == (size_t)-1: strlen
    @test lk_name(LK.PL_new_atom_mbchars(ld, 0, 0, UInt8[])) === Symbol("")
    @test_throws LK.AtomNotRepresentableError LK.PL_new_atom_mbchars(ld, u8, 3, UInt8[0x61, 0x00, 0x62])
    @test_throws LK.AtomNotRepresentableError LK.PL_new_atom_mbchars(ld, 0, 1, UInt8[0])
    @test_throws LK.NotPortedError LK.PL_new_atom_mbchars(ld, Int(LK.REP_MB), 1, UInt8[0x61])
    # REP_UTF8 wins where both are asked (:712)
    @test lk_name(LK.PL_new_atom_mbchars(ld, u8 | Int(LK.REP_MB), 2, UInt8[0xc3, 0xa9])) === Symbol("é")
end

# LK-ONLY (pl-fli.c:747-788): PL_new_functor_sz and PL_new_functor are lookupFunctorDef (one functor per name and
# arity); PL_new_functor refuses an arity below 0 (:763, fatalError) — here an error, also past INT_MAX (VALID_INT_ARITY,
# :119); PL_functor_name and PL_functor_arity read the name and the arity back.
@testset "LK-ONLY: PL_new_functor_sz, PL_new_functor, PL_functor_name and PL_functor_arity (pl-fli.c:747-788)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    f3 = _fa_functor(ld, "f", 3)
    @test LK.PL_new_functor_sz(ld, _rs("f"), 3) == f3
    @test LK.PL_new_functor(ld, _rs("f"), 3) == f3
    @test LK.PL_new_functor(ld, _rs("f"), 2) != f3 && LK.PL_new_functor(ld, _rs("g"), 3) != f3
    @test lk_name(LK.PL_functor_name(ld, f3)) === :f
    @test LK.PL_functor_arity(ld, f3) == 3
    f0 = LK.PL_new_functor(ld, _rs("k"), 0)
    @test lk_name(LK.PL_functor_name(ld, f0)) === :k && LK.PL_functor_arity(ld, f0) == 0
    @test lk_name(LK.PL_functor_name(ld, ld.functor_dot2)) === Symbol("[|]")
    @test LK.PL_functor_arity(ld, ld.functor_dot2) == 2
    @test_throws ErrorException("Arity out of range: -1") LK.PL_new_functor(ld, _rs("f"), -1)
    @test_throws ErrorException("Arity out of range: 2147483648") LK.PL_new_functor(ld, _rs("f"), Int(typemax(Int32)) + 1)
    # a functor from PL_new_functor builds the term PL_put_functor puts
    @test LK.PL_put_functor(ld, t, LK.PL_new_functor(ld, _rs("h"), 2))
    @test LK.PL_is_functor(ld, t, _rs("h"), 2)
end

# LK-ONLY (pl-fli.c:1033-1081, :2074-2102, :871-893): PL_atom_chars is the atom's name bytes (stringAtom), a wide atom's
# being 4 bytes a code point; PL_atom_nchars is NULL for a wide atom; PL_atom_wchars widens a narrow text atom with a
# terminating 0 and is NULL for a non-textual atom (the reserved `[]`).
@testset "LK-ONLY: PL_atom_chars, PL_atom_nchars and PL_atom_wchars (pl-fli.c:1033-1081)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    abc, e, euro, empty, nil = _rs("abc"), _rs("é"), _rs("€"), _rs(""), _rnil()
    @test LK.PL_atom_chars(ld, abc) == Vector{UInt8}("abc")
    @test LK.PL_atom_nchars(ld, abc) == (Vector{UInt8}("abc"), 3)
    @test LK.PL_atom_wchars(ld, abc) == (UInt32[0x61, 0x62, 0x63, 0x00], 3)
    @test LK.PL_atom_chars(ld, e) == UInt8[0xe9]                            # ISO Latin-1, one byte
    @test LK.PL_atom_nchars(ld, e) == (UInt8[0xe9], 1)
    @test LK.PL_atom_wchars(ld, e) == (UInt32[0xe9, 0x00], 1)
    @test LK.PL_atom_chars(ld, euro) == collect(reinterpret(UInt8, UInt32[0x20ac]))   # wide: the wchar_t bytes
    @test LK.PL_atom_nchars(ld, euro) === nothing                           # type == &ucs_atom
    @test LK.PL_atom_wchars(ld, euro) == (UInt32[0x20ac, 0x00], 1)          # length in wchars
    @test LK.PL_atom_chars(ld, empty) == UInt8[]
    @test LK.PL_atom_nchars(ld, empty) == (UInt8[], 0)
    @test LK.PL_atom_wchars(ld, empty) == (UInt32[0x00], 0)
    @test LK.PL_atom_wchars(ld, nil) === nothing                            # not PL_BLOB_TEXT
    @test LK.PL_atom_nchars(ld, nil) == (Vector{UInt8}("[]"), 2)                # NULL only for ucs_atom
end

# LK-ONLY (pl-fli.c:2035-2050): PL_get_atom_chars reads the name of an atom of a PL_BLOB_TEXT type — a wide atom too,
# as its wchar_t bytes — and refuses anything else: an integer, a variable, a compound, the reserved `[]`.
@testset "LK-ONLY: PL_get_atom_chars (pl-fli.c:2035)" begin
    ld, t = _fa_engine(_R[_rs("abc"), _fa_k(5), _rv(1), _rnil(), _rf("f", _rs("a")), _rs("€"), _rs("")])
    @test LK.PL_get_atom_chars(ld, t) == Vector{UInt8}("abc")
    @test LK.PL_get_atom_chars(ld, t + 1) === nothing
    @test LK.PL_get_atom_chars(ld, t + 2) === nothing
    @test LK.PL_get_atom_chars(ld, t + 3) === nothing
    @test LK.PL_get_atom_chars(ld, t + 4) === nothing
    @test LK.PL_get_atom_chars(ld, t + 5) == collect(reinterpret(UInt8, UInt32[0x20ac]))
    @test LK.PL_get_atom_chars(ld, t + 6) == UInt8[]
end

# LK-ONLY (pl-fli.c:2075-2102): PL_atom_mbchars recodes the atom's text (REP_UTF8) and answers the bytes and their count;
# for an atom that is no text it is false, with type_error(atom, A) raised where CVT_EXCEPTION is set (:2081-2086).
# A target other than REP_UTF8 is refused by name (PL_mb_text: REP_MB and Latin-1 targets are unwritten).
@testset "LK-ONLY: PL_atom_mbchars (pl-fli.c:2075)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    u8 = LK.REP_UTF8
    @test LK.PL_atom_mbchars(ld, _rs("abc"), u8) == (Vector{UInt8}("abc"), 3)
    @test LK.PL_atom_mbchars(ld, _rs("é"), u8) == (UInt8[0xc3, 0xa9], 2)     # the length is in bytes
    @test LK.PL_atom_mbchars(ld, _rs("€"), u8) == (UInt8[0xe2, 0x82, 0xac], 3)
    @test LK.PL_atom_mbchars(ld, _rs(""), u8) == (UInt8[], 0)
    @test LK.PL_atom_mbchars(ld, _rnil(), u8) === nothing
    @test ld.exception_term == 0                                             # no CVT_EXCEPTION: no exception
    @test_throws LK.NotPortedError LK.PL_atom_mbchars(ld, _rs("abc"), UInt32(0))
    ld2, _ = _fa_engine(_R[_rv(1)])
    @test LK.PL_atom_mbchars(ld2, _rnil(), u8 | LK.CVT_EXCEPTION) === nothing
    @test ld2.exception_term != 0                                            # type_error(atom, [])
    # the atom of PL_new_atom_mbchars reads back
    a = LK.PL_new_atom_mbchars(ld, Int(u8), 3, UInt8[0xe2, 0x82, 0xac])
    @test LK.PL_atom_mbchars(ld, a, u8) == (UInt8[0xe2, 0x82, 0xac], 3)
end

"The UTF-8 bytes of `s`."
_fa_b(s::String) = Vector{UInt8}(s)
"The message of the error `f` raises, \"\" where it raises none."
_fa_msg(f) = try
    f()
    ""
catch e
    e isa ErrorException ? e.msg : "not an ErrorException: $(typeof(e))"
end
"A fresh database: `(gd, ld)`."
function _fa_db()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    return db.gd, db.ld
end

# LK-ONLY (pl-fli.c:4692-4709): PL_context is the context module — `user` outside a frame (:4696) — and PL_new_module is
# lookupModule: the module named, created if new, the one index for one name; the reserved `user` and `system` exist.
@testset "LK-ONLY: PL_context and PL_new_module (pl-fli.c:4692, :4704)" begin
    gd, ld = _fa_db()
    @test ld.environment_frame == 0
    @test LK.PL_context(gd, ld) == LK.MODULE_user(gd).index
    @test LK.PL_new_module(gd, _rs("user")) == LK.MODULE_user(gd).index
    @test LK.PL_new_module(gd, _rs("system")) == LK.MODULE_system(gd).index
    m1 = LK.PL_new_module(gd, _rs("m1"))
    @test m1 != LK.MODULE_user(gd).index && m1 != LK.MODULE_system(gd).index && m1 > 0
    @test LK.PL_new_module(gd, _rs("m1")) == m1                              # created once
    @test LK.PL_new_module(gd, _rs("m2")) != m1
    @test lk_name(gd.modules[m1].atom) === :m1
end

# LK-ONLY (pl-fli.c:4733-4744): PL_pred is lookupProcedure of the functor in the module, the context module for NULL (0);
# one procedure for one name, arity and module; an arity above MAXARITY is an error (:4738-4739), MAXARITY itself is not.
@testset "LK-ONLY: PL_pred (pl-fli.c:4733)" begin
    gd, ld = _fa_db()
    u = LK.MODULE_user(gd).index
    m1 = LK.PL_new_module(gd, _rs("m1"))
    f = _fa_functor(ld, "p", 2)
    pr = LK.PL_pred(gd, ld, f, 0)                                            # NULL: PL_context()
    @test pr.definition.module_ == u && pr.definition.arity == 2 && lk_name(pr.definition.name) === :p
    @test LK.PL_pred(gd, ld, f, u) === pr && LK.PL_pred(gd, ld, f, 0) === pr   # one procedure per functor and module
    pm = LK.PL_pred(gd, ld, f, m1)
    @test pm !== pr && pm.definition.module_ == m1 && pm.definition.arity == 2
    @test LK.PL_pred(gd, ld, _fa_functor(ld, "p", 3), m1) !== pm              # another arity
    @test LK.PL_pred(gd, ld, _fa_functor(ld, "k", 0), 0).definition.arity == 0
    @test LK.PL_pred(gd, ld, _fa_functor(ld, "b", LK.MAXARITY), 0).definition.arity == LK.MAXARITY
    @test_throws ErrorException("invalid arity $(LK.MAXARITY + 1) (out of range)") LK.PL_pred(
        gd, ld, _fa_functor(ld, "b", LK.MAXARITY + 1), 0
    )
end

# LK-ONLY (pl-fli.c:4747-4776): PL_predicate takes a name and a module (NULL module: the context, :4773), an arity out of
# 0..MAXARITY is an error (:4751-4752). Both texts reach PL_new_atom_mbchars as the flag word ENC_UTF8 (:4754, :4765), a
# value that has neither REP_UTF8 nor REP_MB set (SWI-Prolog.h:1037-1038), so the bytes are read as ISO Latin-1 (:712-713):
# no byte string is invalid (:4755-4758, :4766-4769 are unreachable). The procedure is the one PL_pred finds.
@testset "LK-ONLY: PL_predicate (pl-fli.c:4747)" begin
    gd, ld = _fa_db()
    u = LK.MODULE_user(gd).index
    pr = LK.PL_predicate(gd, ld, _fa_b("p"), 2, nothing)
    @test pr === LK.PL_pred(gd, ld, _fa_functor(ld, "p", 2), 0) && pr.definition.module_ == u
    pm = LK.PL_predicate(gd, ld, _fa_b("p"), 2, _fa_b("m1"))
    @test pm !== pr && lk_name(gd.modules[pm.definition.module_].atom) === :m1
    @test pm === LK.PL_pred(gd, ld, _fa_functor(ld, "p", 2), LK.PL_new_module(gd, _rs("m1")))
    @test LK.PL_predicate(gd, ld, _fa_b("p"), 2, _fa_b("user")) === pr
    latin1(s) = Symbol(String(map(Char, codeunits(s))))                      # each byte one character
    pe = LK.PL_predicate(gd, ld, _fa_b("é€"), 1, _fa_b("ü"))                # the UTF-8 bytes, read as Latin-1
    @test lk_name(pe.definition.name) === latin1("é€") && lk_name(pe.definition.name) !== Symbol("é€")
    @test lk_name(gd.modules[pe.definition.module_].atom) === latin1("ü")
    @test LK.PL_predicate(gd, ld, UInt8[0x61, 0x62, 0x00, 0x63, 0x64], 0, nothing) === LK.PL_predicate(gd, ld, _fa_b("ab"), 0, nothing)  # strlen
    @test LK.PL_predicate(gd, ld, _fa_b("b"), LK.MAXARITY, nothing).definition.arity == LK.MAXARITY
    @test _fa_msg(() -> LK.PL_predicate(gd, ld, _fa_b("p"), -1, nothing)) == "invalid arity -1 (out of range)"
    @test _fa_msg(() -> LK.PL_predicate(gd, ld, _fa_b("p"), LK.MAXARITY + 1, nothing)) ==
          "invalid arity $(LK.MAXARITY + 1) (out of range)"
    pf = LK.PL_predicate(gd, ld, UInt8[0xff, 0xfe], 1, UInt8[0xff])         # no byte string is invalid as Latin-1
    @test lk_name(pf.definition.name) === Symbol("\u00ff\u00fe")
    @test lk_name(gd.modules[pf.definition.module_].atom) === Symbol("\u00ff")
    @test ld.exception_term == 0
end

# LK-ONLY (pl-fli.c:4782-4794): PL_predicate_info answers true with the name, the arity and the module of the definition.
@testset "LK-ONLY: PL_predicate_info (pl-fli.c:4782)" begin
    gd, ld = _fa_db()
    m1 = LK.PL_new_module(gd, _rs("m1"))
    ok, name, arity, m = LK.PL_predicate_info(LK.PL_pred(gd, ld, _fa_functor(ld, "p", 3), m1))
    @test ok === true && lk_name(name) === :p && arity == 3 && m == m1
    ok, name, arity, m = LK.PL_predicate_info(LK.PL_predicate(gd, ld, _fa_b("q"), 0, nothing))
    @test ok === true && lk_name(name) === :q && arity == 0 && m == LK.MODULE_user(gd).index
end


"The text the term reference `t` holds as an atom, a string or a code/character list, `nothing` for none."
function _fa_text(ld, t)
    x = LK.PL_get_text(ld, t, LK.CVT_ATOM | LK.CVT_STRING | LK.CVT_LIST)
    return x === nothing ? nothing : LK._text_string(x)
end
"The elements of the list term reference `t` holds, each read by `read1(ld, ref)`; `nothing` if it is no proper list."
function _fa_list(ld, t, read1)
    out = Any[]
    h = LK.PL_new_term_ref(ld)
    l = LK.PL_copy_term_ref(ld, t)
    while LK.PL_get_list(ld, l, h, l)
        push!(out, read1(ld, h))
    end
    return LK.PL_get_nil(ld, l) ? out : nothing
end
_fa_codes(ld, t) = _fa_list(ld, t, (ld, h) -> LK.PL_get_integer(ld, h))
_fa_chars(ld, t) = _fa_list(ld, t, (ld, h) -> lk_name(LK.PL_get_atom(ld, h)))
"The name of the atom term reference `t` holds."
_fa_atom(ld, t) = lk_name(LK.PL_get_atom(ld, t))

# LK-ONLY (pl-fli.c:3063-3088): PL_put_atom_chars puts the atom of the bytes before the first 0 (ISO Latin-1); PL_put_atom_nchars
# the atom of `len` bytes. DIVERGES (forced): -1 is strlen; a 0 byte inside the text raises AtomNotRepresentableError.
@testset "LK-ONLY: PL_put_atom_chars and PL_put_atom_nchars (pl-fli.c:3063, :3076)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4), _rv(5)])
    @test LK.PL_put_atom_chars(ld, t, _fa_b("abc"))
    @test LK.PL_is_atom(ld, t) && _fa_atom(ld, t) === :abc
    @test LK.PL_put_atom_chars(ld, t + 1, UInt8[0x61, 0x62, 0x00, 0x63])          # strlen: cut at the first 0
    @test _fa_atom(ld, t + 1) === :ab
    @test LK.PL_put_atom_chars(ld, t + 2, UInt8[0xe9])                            # Latin-1, not UTF-8
    @test _fa_atom(ld, t + 2) === Symbol("é")
    @test LK.PL_put_atom_nchars(ld, t + 3, 2, _fa_b("abcd"))
    @test _fa_atom(ld, t + 3) === :ab
    @test LK.PL_put_atom_nchars(ld, t + 4, 0, _fa_b("abcd"))
    @test _fa_atom(ld, t + 4) === Symbol("")
    @test LK.PL_put_atom_nchars(ld, t, -1, UInt8[0x61, 0x62, 0x00, 0x63])         # -1: strlen
    @test _fa_atom(ld, t) === :ab
    @test LK.PL_put_atom_nchars(ld, t, 3, _fa_b("€")) && _fa_atom(ld, t) === Symbol("â\u0082¬")
    @test_throws LK.AtomNotRepresentableError LK.PL_put_atom_nchars(ld, t, 3, UInt8[0x61, 0x00, 0x63])
end

# LK-ONLY (pl-fli.c:3092-3118): PL_put_string_chars puts the string of the bytes before the first 0, PL_put_string_nchars
# the string of `len` bytes (ISO Latin-1, globalString); a string is no atom.
@testset "LK-ONLY: PL_put_string_chars and PL_put_string_nchars (pl-fli.c:3092, :3106)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4)])
    @test LK.PL_put_string_chars(ld, t, _fa_b("abc"))
    @test LK.PL_is_string(ld, t) && !LK.PL_is_atom(ld, t) && _fa_text(ld, t) == "abc"
    @test LK.PL_put_string_chars(ld, t + 1, UInt8[0x61, 0x00, 0x62])
    @test _fa_text(ld, t + 1) == "a"
    @test LK.PL_put_string_chars(ld, t + 2, UInt8[0xe9])
    @test _fa_text(ld, t + 2) == "é"
    @test LK.PL_put_string_nchars(ld, t + 3, 2, _fa_b("abcd"))
    @test LK.PL_is_string(ld, t + 3) && _fa_text(ld, t + 3) == "ab"
    @test LK.PL_put_string_nchars(ld, t, 3, UInt8[0x61, 0x00, 0x62, 0x63])        # the 0 byte is a character
    @test _fa_text(ld, t) == "a\0b"
    @test LK.PL_put_string_nchars(ld, t, 0, _fa_b("abcd"))
    @test LK.PL_is_string(ld, t) && _fa_text(ld, t) == ""
    @test LK.PL_put_string_nchars(ld, t, -1, UInt8[0x61, 0x00, 0x62])             # -1: strlen
    @test _fa_text(ld, t) == "a"
end

# LK-ONLY (pl-fli.c:3122-3161): PL_put_chars puts the text as the type in the flags says (PL_ATOM, PL_STRING, PL_CODE_LIST,
# PL_CHAR_LIST) read in the representation they say (ISO Latin-1, REP_UTF8); -1 is strlen (:3129); REP_MB is refused by name.
@testset "LK-ONLY: PL_put_chars (pl-fli.c:3122)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4)])
    euro = _fa_b("€")                                                             # e2 82 ac
    @test LK.PL_put_chars(ld, t, LK.PL_ATOM, 3, _fa_b("abc"))
    @test LK.PL_is_atom(ld, t) && _fa_atom(ld, t) === :abc
    @test LK.PL_put_chars(ld, t + 1, Int(LK.PL_ATOM | LK.REP_UTF8), 3, euro)
    @test _fa_atom(ld, t + 1) === Symbol("€")
    @test LK.PL_put_chars(ld, t + 1, LK.PL_ATOM, 3, euro)                         # Latin-1: three characters
    @test _fa_atom(ld, t + 1) === Symbol("â\u0082¬")
    @test LK.PL_put_chars(ld, t + 2, LK.PL_STRING, 3, _fa_b("abc"))
    @test LK.PL_is_string(ld, t + 2) && !LK.PL_is_atom(ld, t + 2) && _fa_text(ld, t + 2) == "abc"
    @test LK.PL_put_chars(ld, t + 2, Int(LK.PL_STRING | LK.REP_UTF8), 3, euro)
    @test LK.PL_is_string(ld, t + 2) && _fa_text(ld, t + 2) == "€"
    @test LK.PL_put_chars(ld, t + 3, LK.PL_CODE_LIST, 2, _fa_b("hi"))
    @test _fa_codes(ld, t + 3) == [104, 105]
    @test LK.PL_put_chars(ld, t + 3, LK.PL_CHAR_LIST, 2, _fa_b("hi"))
    @test _fa_chars(ld, t + 3) == [:h, :i]
    @test LK.PL_put_chars(ld, t + 3, Int(LK.PL_CODE_LIST | LK.REP_UTF8), 3, euro)
    @test _fa_codes(ld, t + 3) == [0x20ac]
    @test LK.PL_put_chars(ld, t + 3, LK.PL_CODE_LIST, 0, _fa_b("hi"))             # the empty text: []
    @test LK.PL_get_nil(ld, t + 3)
    @test LK.PL_put_chars(ld, t, LK.PL_ATOM, -1, UInt8[0x61, 0x62, 0x00, 0x63])   # -1: strlen
    @test _fa_atom(ld, t) === :ab
    @test LK.PL_put_chars(ld, t, LK.PL_STRING, -1, UInt8[0x61, 0x62, 0x00, 0x63])
    @test _fa_text(ld, t) == "ab"
    @test_throws LK.NotPortedError LK.PL_put_chars(ld, t, Int(LK.PL_ATOM | LK.REP_MB), 3, _fa_b("abc"))
    @test _fa_msg(() -> LK.PL_put_chars(ld, t, 0, 3, _fa_b("abc"))) == "PL_put_chars: unknown type 0"
end

# LK-ONLY (pl-fli.c:3165-3189, :3193): PL_put_list_ncodes puts the list of the `len` bytes as integer codes, [] for 0; the
# bytes are read unsigned (`& 0xff`); PL_put_list_codes is strlen of it. The last tail is [] (a proper list).
@testset "LK-ONLY: PL_put_list_ncodes and PL_put_list_codes (pl-fli.c:3165, :3193)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4)])
    @test LK.PL_put_list_ncodes(ld, t, 2, _fa_b("hi"))
    @test LK.PL_is_pair(ld, t) && _fa_codes(ld, t) == [104, 105]
    @test LK.PL_put_list_ncodes(ld, t + 1, 3, _fa_b("hello"))
    @test _fa_codes(ld, t + 1) == [104, 101, 108] && LK.PL_skip_list(ld, t + 1) == (LK.PL_LIST, 3)
    @test LK.PL_put_list_ncodes(ld, t + 2, 0, _fa_b("hello"))
    @test LK.PL_get_nil(ld, t + 2)
    @test LK.PL_put_list_ncodes(ld, t + 2, 3, UInt8[0x00, 0xe9, 0xff])            # unsigned bytes
    @test _fa_codes(ld, t + 2) == [0, 233, 255]
    @test LK.PL_put_list_codes(ld, t + 3, _fa_b("hello"))
    @test _fa_codes(ld, t + 3) == [104, 101, 108, 108, 111]
    @test LK.PL_put_list_codes(ld, t + 3, UInt8[0x61, 0x00, 0x62])                # strlen
    @test _fa_codes(ld, t + 3) == [97]
    @test LK.PL_put_list_codes(ld, t + 3, UInt8[])
    @test LK.PL_get_nil(ld, t + 3)
end

# LK-ONLY (pl-fli.c:3199-3226, :3231): PL_put_list_nchars puts the list of the bytes as one-character atoms; PL_put_list_chars
# is strlen of it.
@testset "LK-ONLY: PL_put_list_nchars and PL_put_list_chars (pl-fli.c:3199)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3)])
    @test LK.PL_put_list_nchars(ld, t, 2, _fa_b("hi"))
    @test LK.PL_is_pair(ld, t) && _fa_chars(ld, t) == [:h, :i]
    @test LK.PL_put_list_nchars(ld, t + 1, 3, _fa_b("hello"))
    @test _fa_chars(ld, t + 1) == [:h, :e, :l] && LK.PL_skip_list(ld, t + 1) == (LK.PL_LIST, 3)
    @test LK.PL_put_list_nchars(ld, t + 2, 0, _fa_b("hello"))
    @test LK.PL_get_nil(ld, t + 2)
    @test LK.PL_put_list_nchars(ld, t + 2, 1, UInt8[0xe9])                        # Latin-1
    @test _fa_chars(ld, t + 2) == [Symbol("é")]
    @test LK.PL_put_list_chars(ld, t + 2, UInt8[0x61, 0x62, 0x00, 0x63])          # strlen
    @test _fa_chars(ld, t + 2) == [:a, :b]
end

# LK-ONLY (pl-fli.c:3506-3528): PL_unify_atom_chars and PL_unify_atom_nchars unify with the atom of the bytes: a variable
# is bound, an atom must be the same one, anything else fails.
@testset "LK-ONLY: PL_unify_atom_chars and PL_unify_atom_nchars (pl-fli.c:3506, :3519)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rs("abc"), _fa_k(5), _rg("abc")])
    @test LK.PL_unify_atom_chars(ld, t, _fa_b("abc")) && _fa_atom(ld, t) === :abc
    @test LK.PL_unify_atom_chars(ld, t + 3, _fa_b("abc"))
    @test !LK.PL_unify_atom_chars(ld, t + 3, _fa_b("abd"))
    @test !LK.PL_unify_atom_chars(ld, t + 4, _fa_b("abc"))                        # an integer
    @test !LK.PL_unify_atom_chars(ld, t + 5, _fa_b("abc"))                        # a string is no atom
    @test LK.PL_unify_atom_chars(ld, t + 1, UInt8[0x61, 0x00, 0x62]) && _fa_atom(ld, t + 1) === :a   # strlen
    @test LK.PL_unify_atom_nchars(ld, t + 2, 2, _fa_b("abc")) && _fa_atom(ld, t + 2) === :ab
    @test LK.PL_unify_atom_nchars(ld, t + 3, 3, _fa_b("abcd"))
    @test !LK.PL_unify_atom_nchars(ld, t + 3, 2, _fa_b("abcd"))
    @test LK.PL_unify_atom_nchars(ld, t + 3, -1, _fa_b("abc"))                    # -1: strlen
end

# LK-ONLY (pl-fli.c:3003-3024): PL_unify_string_chars and PL_unify_string_nchars unify with the string of the bytes: a
# variable is bound, a string must be equal, an atom of the same text is no string.
@testset "LK-ONLY: PL_unify_string_chars and PL_unify_string_nchars (pl-fli.c:3003, :3015)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rg("abc"), _rs("abc")])
    @test LK.PL_unify_string_chars(ld, t, _fa_b("abc"))
    @test LK.PL_is_string(ld, t) && _fa_text(ld, t) == "abc"
    @test LK.PL_unify_string_chars(ld, t + 3, _fa_b("abc"))
    @test !LK.PL_unify_string_chars(ld, t + 3, _fa_b("abd"))
    @test !LK.PL_unify_string_chars(ld, t + 4, _fa_b("abc"))                      # an atom
    @test LK.PL_unify_string_chars(ld, t + 1, UInt8[0x61, 0x00, 0x62]) && _fa_text(ld, t + 1) == "a"   # strlen
    @test LK.PL_unify_string_nchars(ld, t + 2, 2, _fa_b("abc"))
    @test LK.PL_is_string(ld, t + 2) && _fa_text(ld, t + 2) == "ab"
    @test LK.PL_unify_string_nchars(ld, t + 3, 3, _fa_b("abcd"))
    @test !LK.PL_unify_string_nchars(ld, t + 3, 2, _fa_b("abcd"))
end

# LK-ONLY (pl-fli.c:3599-3629): PL_unify_list_ncodes unifies with the list of the bytes as codes: a variable is bound to it
# (put + unify, :3602-3606), a partial or a proper list is unified cell by cell (:3608-3621); PL_unify_list_codes is strlen.
@testset "LK-ONLY: PL_unify_list_ncodes and PL_unify_list_codes (pl-fli.c:3599, :3627)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4), _rv(5)])
    @test LK.PL_unify_list_ncodes(ld, t, 2, _fa_b("hi"))                          # a variable
    @test _fa_codes(ld, t) == [104, 105]
    @test LK.PL_unify_list_ncodes(ld, t, 2, _fa_b("hi"))                          # the same list
    @test !LK.PL_unify_list_ncodes(ld, t, 2, _fa_b("ho"))                         # another element
    @test !LK.PL_unify_list_ncodes(ld, t, 1, _fa_b("hi"))                         # a shorter list
    @test !LK.PL_unify_list_ncodes(ld, t, 3, _fa_b("hij"))                        # a longer list
    h, tl = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.PL_unify_list(ld, t + 1, h, tl)                                      # t+1 is now [A|B], A, B variables
    @test LK.PL_unify_list_ncodes(ld, t + 1, 2, _fa_b("hi"))                      # a partial list
    @test _fa_codes(ld, t + 1) == [104, 105]
    @test LK.PL_put_nil(ld, t + 4)
    @test LK.PL_unify_list_ncodes(ld, t + 4, 0, _fa_b("hi"))                      # [] with the empty text
    @test !LK.PL_unify_list_ncodes(ld, t + 4, 1, _fa_b("hi"))
    @test LK.PL_unify_list_ncodes(ld, t + 2, 0, _fa_b("hi")) && LK.PL_get_nil(ld, t + 2)   # a variable: []
    @test LK.PL_put_list_codes(ld, t + 3, _fa_b("ab"))
    @test LK.PL_unify_list_codes(ld, t + 3, _fa_b("ab")) && !LK.PL_unify_list_codes(ld, t + 3, _fa_b("abc"))
    @test LK.PL_unify_list_codes(ld, t + 3, UInt8[0x61, 0x62, 0x00, 0x63])        # strlen
end

# LK-ONLY (pl-fli.c:3633-3663): PL_unify_list_nchars unifies with the list of the bytes as one-character atoms, as
# PL_unify_list_ncodes does with codes; PL_unify_list_chars is strlen.
@testset "LK-ONLY: PL_unify_list_nchars and PL_unify_list_chars (pl-fli.c:3633, :3661)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4)])
    @test LK.PL_unify_list_nchars(ld, t, 2, _fa_b("hi"))
    @test _fa_chars(ld, t) == [:h, :i]
    @test LK.PL_unify_list_nchars(ld, t, 2, _fa_b("hi"))
    @test !LK.PL_unify_list_nchars(ld, t, 2, _fa_b("ho"))
    @test !LK.PL_unify_list_nchars(ld, t, 1, _fa_b("hi"))
    @test !LK.PL_unify_list_nchars(ld, t, 3, _fa_b("hij"))
    h, tl = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.PL_unify_list(ld, t + 1, h, tl)
    @test LK.PL_unify_list_nchars(ld, t + 1, 2, _fa_b("hi"))
    @test _fa_chars(ld, t + 1) == [:h, :i]
    @test LK.PL_unify_list_chars(ld, t + 2, _fa_b("ab"))
    @test _fa_chars(ld, t + 2) == [:a, :b]
    @test LK.PL_unify_list_chars(ld, t + 2, UInt8[0x61, 0x62, 0x00, 0x63])        # strlen
    @test !LK.PL_unify_list_chars(ld, t + 2, _fa_b("abc"))
end

"The error `f(ld, t)` raises on an engine holding `v` in `t`: `(result, nothing)` for none, else `(result, (formal name, atom of its first argument or nothing))`."
function _fa_err(v::_R, f)
    ld, t = _fa_engine(_R[v])
    r = f(ld, t)
    ex = ld.exception_term
    ex == 0 && return (r, nothing)
    fm, a = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    LK.PL_get_arg(ld, 1, ex, fm) || return (r, :malformed)          # error(Formal, Context)
    na = LK.PL_get_name_arity(ld, fm)
    na === nothing && return (r, :malformed)
    n, ar = na
    if ar >= 1 && LK.PL_get_arg(ld, 1, fm, a) && LK.PL_is_atom(ld, a)
        return (r, (lk_name(n), _fa_atom(ld, a)))
    end
    return (r, (lk_name(n), nothing))
end

# LK-ONLY (pl-fli.c:1166-1205): _PL_cvt_i_char reads an integer in the range (:1172) or a one-character ISO Latin-1 text — an
# atom, a string, a code or a character list (:1178) — as the byte; PL_cvt_i_schar reads the byte signed, PL_cvt_i_uchar unsigned;
# an integer out of range is representation_error(char) / (uchar) (:1191), anything else type_error(integer, X) (:1193).
@testset "LK-ONLY: PL_cvt_i_schar and PL_cvt_i_uchar (pl-fli.c:1166, :1198, :1203)" begin
    ld, t = _fa_engine(_R[_fa_k(-5), _fa_k(200), _fa_k(-128), _fa_k(127), _fa_k(255), _fa_k(0)])
    @test LK.PL_cvt_i_schar(ld, t) === Int8(-5)
    @test LK.PL_cvt_i_schar(ld, t + 2) === Int8(-128) && LK.PL_cvt_i_schar(ld, t + 3) === Int8(127)
    @test LK.PL_cvt_i_uchar(ld, t + 1) === 0xc8 && LK.PL_cvt_i_uchar(ld, t + 4) === 0xff
    @test LK.PL_cvt_i_uchar(ld, t + 5) === 0x00 && LK.PL_cvt_i_schar(ld, t + 5) === Int8(0)
    @test ld.exception_term == 0
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4), _rv(5)])
    @test LK.PL_put_atom_chars(ld, t, _fa_b("a")) && LK.PL_cvt_i_uchar(ld, t) === 0x61
    @test LK.PL_put_string_chars(ld, t + 1, _fa_b("b")) && LK.PL_cvt_i_uchar(ld, t + 1) === 0x62
    @test LK.PL_put_list_codes(ld, t + 2, _fa_b("c")) && LK.PL_cvt_i_uchar(ld, t + 2) === 0x63
    @test LK.PL_put_list_chars(ld, t + 3, _fa_b("d")) && LK.PL_cvt_i_schar(ld, t + 3) === Int8(100)
    @test LK.PL_put_atom_chars(ld, t + 4, UInt8[0xe9])                            # Latin-1 byte 0xe9
    @test LK.PL_cvt_i_uchar(ld, t + 4) === 0xe9 && LK.PL_cvt_i_schar(ld, t + 4) === Int8(-23)
    @test ld.exception_term == 0
    schar(ld, t) = LK.PL_cvt_i_schar(ld, t)
    uchar(ld, t) = LK.PL_cvt_i_uchar(ld, t)
    @test _fa_err(_fa_k(128), schar) == (nothing, (:representation_error, :char))
    @test _fa_err(_fa_k(-129), schar) == (nothing, (:representation_error, :char))
    @test _fa_err(_fa_k(256), uchar) == (nothing, (:representation_error, :uchar))
    @test _fa_err(_fa_k(-1), uchar) == (nothing, (:representation_error, :uchar))
    @test _fa_err(_fa_k(1 << 40), schar) == (nothing, (:representation_error, :char))   # not a C int: still an integer
    @test _fa_err(_rs("ab"), schar) == (nothing, (:type_error, :integer))                # two characters
    @test _fa_err(_rs("€"), uchar) == (nothing, (:type_error, :integer))                 # one character, not Latin-1
    @test _fa_err(_rg(1.5), uchar) == (nothing, (:type_error, :integer))
    @test _fa_err(_rv(1), uchar) == (nothing, (:instantiation_error, nothing))
end

# LK-ONLY (pl-fli.c:1215-1230): _PL_cvt_i_short reads an integer in mn..mx (the C int range first: :1220), an integer out of it is
# representation_error(short) (mn < 0) or (ushort), anything else type_error(integer, X).
@testset "LK-ONLY: _PL_cvt_i_short (pl-fli.c:1215)" begin
    ld, t = _fa_engine(_R[_fa_k(7), _fa_k(-32768), _fa_k(32767), _fa_k(65535), _fa_k(0)])
    @test LK._PL_cvt_i_short(ld, t, -32768, 32767) === 7
    @test LK._PL_cvt_i_short(ld, t + 1, -32768, 32767) === -32768
    @test LK._PL_cvt_i_short(ld, t + 2, -32768, 32767) === 32767
    @test LK._PL_cvt_i_short(ld, t + 3, 0, 65535) === 65535
    @test LK._PL_cvt_i_short(ld, t + 4, 0, 65535) === 0
    @test ld.exception_term == 0
    short(ld, t) = LK._PL_cvt_i_short(ld, t, -32768, 32767)
    ushort(ld, t) = LK._PL_cvt_i_short(ld, t, 0, 65535)
    @test _fa_err(_fa_k(32768), short) == (nothing, (:representation_error, :short))
    @test _fa_err(_fa_k(-32769), short) == (nothing, (:representation_error, :short))
    @test _fa_err(_fa_k(65536), ushort) == (nothing, (:representation_error, :ushort))
    @test _fa_err(_fa_k(-1), ushort) == (nothing, (:representation_error, :ushort))
    @test _fa_err(_fa_k(1 << 40), short) == (nothing, (:representation_error, :short))
    @test _fa_err(_rs("a"), short) == (nothing, (:type_error, :integer))               # no text conversion, unlike char
    @test _fa_err(_rg(2.0), ushort) == (nothing, (:type_error, :integer))
end

# LK-ONLY (pl-fli.c:1291-1299): PL_cvt_i_int64 is PL_get_int64_ex, PL_cvt_i_uint64 is PL_get_uint64_ex: the value in range,
# else an error. The pin's PL_get_uint64_ex (pl-error.c) is not in the kernel: the negative / too large / not an integer
# errors are written as PL_get_size_ex's with uint64_t's range.
@testset "LK-ONLY: PL_cvt_i_int64 and PL_cvt_i_uint64 (pl-fli.c:1291, :1296)" begin
    ld, t = _fa_engine(_R[_fa_k(7), _fa_k(-7), _fa_k(typemax(Int64)), _fa_k(typemin(Int64)), _fa_k(0)])
    @test LK.PL_cvt_i_int64(ld, t) === 7 && LK.PL_cvt_i_int64(ld, t + 1) === -7
    @test LK.PL_cvt_i_int64(ld, t + 2) === typemax(Int64) && LK.PL_cvt_i_int64(ld, t + 3) === typemin(Int64)
    @test LK.PL_cvt_i_uint64(ld, t) === UInt64(7) && LK.PL_cvt_i_uint64(ld, t + 4) === UInt64(0)
    @test LK.PL_cvt_i_uint64(ld, t + 2) === UInt64(typemax(Int64))
    @test ld.exception_term == 0
    i64(ld, t) = LK.PL_cvt_i_int64(ld, t)
    u64(ld, t) = LK.PL_cvt_i_uint64(ld, t)
    @test _fa_err(_rs("a"), i64) == (nothing, (:type_error, :integer))
    @test _fa_err(_rg(big(2)^64), i64) == (nothing, (:representation_error, :int64_t))
    @test _fa_err(_rs("a"), u64) == (nothing, (:type_error, :integer))
    @test _fa_err(_rg(1.5), u64) == (nothing, (:type_error, :integer))
    @test _fa_err(_rv(1), u64) == (nothing, (:instantiation_error, nothing))
    @test _fa_err(_fa_k(-1), u64) == (nothing, (:domain_error, :not_less_than_zero))
    @test _fa_err(_fa_k(typemin(Int64)), u64) == (nothing, (:domain_error, :not_less_than_zero))
    @test _fa_err(_rg(-big(2)^70), u64) == (nothing, (:domain_error, :not_less_than_zero))
    @test _fa_err(_rg(big(2)^64), u64) == (nothing, (:representation_error, :uint64_t))
    ld2, t2 = _fa_engine(_R[_rg(big(2)^64 - 1), _rg(big(2)^63)])
    @test LK.PL_cvt_i_uint64(ld2, t2) === typemax(UInt64)
    @test LK.PL_cvt_i_uint64(ld2, t2 + 1) === UInt64(2)^63
    @test ld2.exception_term == 0
end

# LK-ONLY (pl-fli.c:2126-2151): PL_get_list_nchars reads a code or character list of Latin-1 characters as its bytes (and their
# count), nothing for a partial list, a wide character, or no list.
@testset "LK-ONLY: PL_get_list_nchars (pl-fli.c:2126)" begin
    ld, t = _fa_engine(_R[_rv(1), _rv(2), _rv(3), _rv(4), _rv(5), _rv(6), _rv(7)])
    @test LK.PL_put_list_codes(ld, t, _fa_b("hi"))
    @test LK.PL_get_list_nchars(ld, t, UInt32(0)) == (_fa_b("hi"), 2)
    @test LK.PL_put_list_chars(ld, t + 1, _fa_b("abc"))
    @test LK.PL_get_list_nchars(ld, t + 1, UInt32(0)) == (_fa_b("abc"), 3)
    @test LK.PL_put_list_ncodes(ld, t + 2, 0, _fa_b("x"))                         # []
    @test LK.PL_get_list_nchars(ld, t + 2, UInt32(0)) == (UInt8[], 0)
    @test LK.PL_put_list_ncodes(ld, t + 3, 2, UInt8[0xe9, 0xff])                  # codes up to 255
    @test LK.PL_get_list_nchars(ld, t + 3, UInt32(0)) == (UInt8[0xe9, 0xff], 2)
    @test LK.PL_put_atom_chars(ld, t + 4, _fa_b("hi"))                            # an atom is no list
    @test LK.PL_get_list_nchars(ld, t + 4, UInt32(0)) === nothing
    @test LK.PL_put_list(ld, t + 5)                                               # [_|_]: partial
    @test LK.PL_get_list_nchars(ld, t + 5, UInt32(0)) === nothing
    h, tl = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)                        # the code list [0x20ac]
    @test LK.PL_unify_list(ld, t + 6, h, tl) && LK.PL_unify_integer(ld, h, 0x20ac % Int) && LK.PL_unify_nil(ld, tl)
    @test LK.PL_get_list_nchars(ld, t + 6, UInt32(0)) === nothing                 # a code above 255: wide = false
    @test LK.PL_get_list_nchars(ld, t, UInt32(LK.CVT_EXCEPTION)) == (_fa_b("hi"), 2)
end

# LK-ONLY (pl-fli.c:2184-2209): PL_get_nchars reads the text the CVT_* flags allow (PL_get_text), recoded as REP_UTF8 asks
# (PL_mb_text), as its bytes and their count; PL_get_chars the bytes. A flag that does not allow the term's type gives
# nothing; CVT_EXCEPTION raises. REP_ISO_LATIN_1 and REP_MB targets are refused by name (PL_mb_text's).
@testset "LK-ONLY: PL_get_nchars and PL_get_chars (pl-fli.c:2184, :2207)" begin
    ld, t = _fa_engine(_R[_rv(1), _rs("€"), _rv(3), _rv(4), _rv(5), _fa_k(42)])
    u8 = LK.CVT_ATOM | LK.CVT_STRING | LK.CVT_LIST | LK.REP_UTF8
    @test LK.PL_put_atom_chars(ld, t, _fa_b("abc"))
    @test LK.PL_get_nchars(ld, t, u8) == (_fa_b("abc"), 3)
    @test LK.PL_get_chars(ld, t, u8) == _fa_b("abc")
    @test LK.PL_get_nchars(ld, t + 1, u8) == (_fa_b("€"), 3)                      # three bytes, one character
    @test LK.PL_put_atom_chars(ld, t + 2, UInt8[0xe9])
    @test LK.PL_get_nchars(ld, t + 2, u8) == (UInt8[0xc3, 0xa9], 2)               # Latin-1 é recoded as UTF-8
    @test LK.PL_put_string_chars(ld, t + 3, _fa_b("hi"))
    @test LK.PL_get_nchars(ld, t + 3, LK.CVT_STRING | LK.REP_UTF8) == (_fa_b("hi"), 2)
    @test LK.PL_get_nchars(ld, t + 3, LK.CVT_ATOM | LK.REP_UTF8) === nothing      # a string is no atom for the flags
    @test LK.PL_get_chars(ld, t + 3, LK.CVT_ATOM | LK.REP_UTF8) === nothing
    @test LK.PL_put_list_codes(ld, t + 4, _fa_b("ok"))
    @test LK.PL_get_nchars(ld, t + 4, u8) == (_fa_b("ok"), 2)
    @test LK.PL_get_nchars(ld, t + 4, LK.CVT_ATOM | LK.REP_UTF8) === nothing
    @test LK.PL_get_nchars(ld, t + 5, LK.CVT_INTEGER | LK.REP_UTF8) == (_fa_b("42"), 2)
    @test LK.PL_get_nchars(ld, t + 5, u8) === nothing
    @test ld.exception_term == 0
    @test_throws LK.NotPortedError LK.PL_get_nchars(ld, t, LK.CVT_ATOM)           # REP_ISO_LATIN_1: PL_mb_text refuses
    @test_throws LK.NotPortedError LK.PL_get_chars(ld, t, LK.CVT_ATOM | LK.REP_MB)
    r, e = _fa_err(_fa_k(7), (ld, t) -> LK.PL_get_nchars(ld, t, LK.CVT_ATOM | LK.CVT_EXCEPTION | LK.REP_UTF8))
    @test r === nothing && e !== nothing
end

# LK-ONLY (pl-fli.c:1132-1134, :1113): PL_cvt_encoding is sp_encoding, REP_UTF8 until PL_cvt_set_encoding changes it.
@testset "LK-ONLY: PL_cvt_encoding (pl-fli.c:1132)" begin
    @test LK.PL_cvt_encoding() === LK.REP_UTF8
    @test LK.PL_cvt_encoding() != LK.REP_ISO_LATIN_1 && LK.PL_cvt_encoding() != LK.REP_MB
end

# LK-ONLY (pl-fli.c:3531-3595): uncachedCodeToAtom makes the one-character atom of a code (a byte below 256: Latin-1; above: the
# wide character); codeToAtom is end_of_file for EOF (:3555) and else that atom — the code cache (:3560-3577) is a named DIVERGES
# (Symbol atoms, see the PORT comment in src/pl-fli.jl) and cleanupCodeToAtom (:3584) has nothing to free.
@testset "LK-ONLY: uncachedCodeToAtom, codeToAtom and cleanupCodeToAtom (pl-fli.c:3532, :3552, :3584)" begin
    @test lk_name(LK.uncachedCodeToAtom(_R, 97)) === :a
    @test lk_name(LK.uncachedCodeToAtom(_R, 233)) === Symbol("é")
    @test lk_name(LK.uncachedCodeToAtom(_R, 0x20ac)) === Symbol("€")
    @test lk_name(LK.uncachedCodeToAtom(_R, 0x1f600)) === Symbol("😀")              # past the BMP
    @test lk_name(LK.codeToAtom(_R, 97)) === :a && lk_name(LK.codeToAtom(_R, 0x20ac)) === Symbol("€")
    @test lk_name(LK.codeToAtom(_R, 0x1f600)) === Symbol("😀")
    @test lk_name(LK.codeToAtom(_R, -1)) === :end_of_file
    @test LK.cleanupCodeToAtom() === nothing
    @test lk_name(LK.codeToAtom(_R, 98)) === :b                                   # still the same atom after the cleanup
end

"The atom value (`atom`) of the symbol `s` on `ld`."
_fa_av(ld, s) = LK.atomValue(ld.atoms, LK._atom_word!(ld, _rs(s)))

# LK-ONLY (pl-fli.c:832-840, :877-901): initUCSAtoms registers the blob type of wide text atoms (once, whatever the number of
# calls); isUCSAtom tells a wide atom from a narrow or a reserved one; get_atom_ptr_text and get_atom_text give the canonical text
# of a text atom — a wide one ENC_WCHAR with its length in code points, any other ISO Latin-1 — and nothing for a non-text atom.
@testset "LK-ONLY: initUCSAtoms, isUCSAtom, get_atom_ptr_text and get_atom_text (pl-fli.c:832, :838, :877, :897)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    @test LK.initUCSAtoms(ld.atoms) === nothing
    @test LK.initUCSAtoms(ld.atoms) === nothing                              # registering again adds nothing
    reg = LK._blob_registration(ld.atoms, LK.ucs_atom)
    @test reg !== nothing && reg.type === LK.ucs_atom && reg.padding == 4
    @test count(r -> r.type === LK.ucs_atom, ld.atoms.types) == 1
    wide, narrow, e = _fa_av(ld, "€"), _fa_av(ld, "abc"), _fa_av(ld, "é")
    nilw = LK._atom_word!(ld, _rnil())
    @test LK.isUCSAtom(wide) && !LK.isUCSAtom(narrow) && !LK.isUCSAtom(e)
    @test !LK.isUCSAtom(LK.atomValue(ld.atoms, nilw))                        # the reserved [] is no wide atom
    tx = LK.get_atom_ptr_text(wide)
    @test tx.encoding === LK.ENC_WCHAR && tx.length == 1 && tx.canonical && collect(reinterpret(UInt32, tx.text)) == UInt32[0x20ac]
    tx = LK.get_atom_ptr_text(narrow)
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 3 && tx.canonical && tx.text == Vector{UInt8}("abc")
    tx = LK.get_atom_text(ld.atoms, LK._atom_word!(ld, _rs("é")))
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 1 && tx.text == UInt8[0xe9]
    tx = LK.get_atom_text(ld.atoms, LK._atom_word!(ld, _rs("")))
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 0
    @test LK.get_atom_ptr_text(LK.atomValue(ld.atoms, nilw)) === nothing     # not PL_BLOB_TEXT
    @test LK.get_atom_text(ld.atoms, nilw) === nothing
end

# LK-ONLY (pl-fli.c:905-917): get_string_text is the canonical text of a string: ISO Latin-1 where every character is below
# 0x100 (isBString), else ENC_WCHAR; the length is in characters (swipl: string_length("a€", 2)).
@testset "LK-ONLY: get_string_text (pl-fli.c:905)" begin
    tx = LK.get_string_text(_rg("abc"))
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 3 && tx.canonical && tx.text == Vector{UInt8}("abc")
    tx = LK.get_string_text(_rg("é"))
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 1 && tx.text == UInt8[0xe9]
    tx = LK.get_string_text(_rg("a€"))
    @test tx.encoding === LK.ENC_WCHAR && tx.length == 2 && tx.canonical
    @test collect(reinterpret(UInt32, tx.text)) == UInt32[0x61, 0x20ac]
    tx = LK.get_string_text(_rg(""))
    @test tx.encoding === LK.ENC_ISO_LATIN_1 && tx.length == 0
    @test_throws ErrorException LK.get_string_text(_rs("abc"))               # no string: an error (DIVERGES, forced)
end

# LK-ONLY (pl-fli.c:921-947): compareUCSAtom orders two wide atoms by code point, then by length. Each expected sign is
# swipl's compare/3 (10.1.20) on the same atoms; the last row is decided by the first code point, not by the lengths.
@testset "LK-ONLY: compareUCSAtom (pl-fli.c:921)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    @test LK.compareUCSAtom(_fa_av(ld, "€a"), _fa_av(ld, "€b")) == -1
    @test LK.compareUCSAtom(_fa_av(ld, "€b"), _fa_av(ld, "€a")) == 1
    @test LK.compareUCSAtom(_fa_av(ld, "€a"), _fa_av(ld, "€a")) == 0
    @test LK.compareUCSAtom(_fa_av(ld, "€"), _fa_av(ld, "€a")) == -1         # a prefix is the smaller
    @test LK.compareUCSAtom(_fa_av(ld, "€a"), _fa_av(ld, "€")) == 1
    @test LK.compareUCSAtom(_fa_av(ld, "Ā"), _fa_av(ld, "€")) == -1          # U+0100 < U+20AC
    @test LK.compareUCSAtom(_fa_av(ld, "😀"), _fa_av(ld, "€")) == 1          # U+1F600 > U+20AC
    @test LK.compareUCSAtom(_fa_av(ld, "€z"), _fa_av(ld, "😀")) == -1        # the first code point, not the length
end

# LK-ONLY (pl-fli.c:951-974): saveUCSAtom and loadUCSAtom write and read the .qlf form of a wide atom; the QLF reader and writer
# are refused by name (owner LD2), so each raises NotPortedError naming it.
@testset "LK-ONLY: saveUCSAtom and loadUCSAtom are refused by name (pl-fli.c:951, :963)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    @test_throws LK.NotPortedError LK.saveUCSAtom(_fa_av(ld, "€"), nothing)
    @test_throws LK.NotPortedError LK.loadUCSAtom(nothing)
    e1 = try
        LK.saveUCSAtom(_fa_av(ld, "€"), nothing)
    catch e
        e
    end
    e2 = try
        LK.loadUCSAtom(nothing)
    catch e
        e
    end
    @test e1 isa LK.NotPortedError && occursin("LD2", e1.step) && occursin("saveUCSAtom", e1.what)
    @test e2 isa LK.NotPortedError && occursin("LD2", e2.step) && occursin("loadUCSAtom", e2.what)
end

"`(rc, text)` of `blob_write_usc_atom(name, options)` with write `flags` on a memory stream (`rc`, the bytes written)."
function _fa_ucs_out(gd, ld, name::String, flags::Int)
    buf = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sz = Ref(0)
    s = LK.Sopenmem(buf, sz, "w")
    s.encoding = LK.ENC_UTF8
    opts = LK.write_options(gd, ld, s)
    opts.flags = flags
    rc = LK.blob_write_usc_atom(name, opts)
    LK.Sclose(s)
    return rc, String(copy(buf[][1:sz[]]))
end

# LK-ONLY (pl-fli.c:809-814): blob_write_usc_atom is writeUCSAtom with 1 for success and -1 for failure. The texts are those of
# swipl 10.1.20: write/1 gives a€, writeq/1 gives 'a€', '€a' and 'ab c€'; a stream that cannot be written to is the failure.
@testset "LK-ONLY: blob_write_usc_atom (pl-fli.c:809)" begin
    gd, ld = _fa_db()
    @test _fa_ucs_out(gd, ld, "a€", 0) == (1, "a€")
    @test _fa_ucs_out(gd, ld, "a€", LK.PL_WRT_QUOTED) == (1, "'a€'")
    @test _fa_ucs_out(gd, ld, "€a", LK.PL_WRT_QUOTED) == (1, "'€a'")
    @test _fa_ucs_out(gd, ld, "ab c€", LK.PL_WRT_QUOTED) == (1, "'ab c€'")
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(UInt8[0x61]), Ref(1), "r")     # an input stream
    s.encoding = LK.ENC_UTF8
    @test LK.blob_write_usc_atom("a€", LK.write_options(gd, ld, s)) == -1
end

# LK-ONLY (pl-fli.c:1721-1733): is_text_value is true for a string, for an atom where CVT_ATOM is set, and for an integer or a
# rational where CVT_FLOAT is not set; false for any other type (a float is 5, a variable 1).
@testset "LK-ONLY: is_text_value (pl-fli.c:1721)" begin
    f0, fa, ff = UInt32(0), LK.CVT_ATOM, LK.CVT_FLOAT
    @test LK.is_text_value(LK.PL_STRING, f0) && LK.is_text_value(LK.PL_STRING, ff)
    @test !LK.is_text_value(LK.PL_ATOM, f0) && LK.is_text_value(LK.PL_ATOM, fa) && !LK.is_text_value(LK.PL_ATOM, ff)
    @test LK.is_text_value(LK.PL_INTEGER, f0) && LK.is_text_value(LK.PL_INTEGER, fa) && !LK.is_text_value(LK.PL_INTEGER, ff)
    @test LK.is_text_value(LK.PL_RATIONAL, f0) && !LK.is_text_value(LK.PL_RATIONAL, ff | fa)
    @test !LK.is_text_value(5, f0 | fa) && !LK.is_text_value(1, fa | LK.CVT_INTEGER)   # PL_FLOAT, PL_VARIABLE
    @test !LK.is_text_value(7, f0)                                           # PL_TERM
end

# LK-ONLY (pl-fli.c:1739-1753): get_value_text converts the term reference as the flags with the CVT bits REPLACED by `cvt` say
# (`(flags & ~CVT_MASK) | cvt`): the CVT bits the caller's flags carry are dropped, REP_UTF8 stays. The answer is the UTF-8 bytes
# and their count; nothing where the type is not among `cvt`.
@testset "LK-ONLY: get_value_text (pl-fli.c:1739)" begin
    ld, t = _fa_engine(_R[_rs("abc"), _rg("héllo"), _fa_k(42), _rf("f", _rs("a")), _rs("é")])
    u8 = LK.REP_UTF8
    both = LK.CVT_ATOM | LK.CVT_STRING | u8
    @test LK.get_value_text(ld, t, LK.CVT_ATOM, u8) == (Vector{UInt8}("abc"), 3)
    @test LK.get_value_text(ld, t, LK.CVT_STRING, both) === nothing          # the caller's CVT_ATOM is dropped
    @test LK.get_value_text(ld, t + 1, LK.CVT_STRING, u8) == (Vector{UInt8}("héllo"), 6)   # the length is in bytes
    @test LK.get_value_text(ld, t + 1, LK.CVT_ATOM, both) === nothing        # a string is no atom
    @test LK.get_value_text(ld, t + 2, LK.CVT_INTEGER, u8) == (Vector{UInt8}("42"), 2)
    @test LK.get_value_text(ld, t + 2, LK.CVT_ATOM, both) === nothing
    @test LK.get_value_text(ld, t + 3, LK.CVT_ATOM | LK.CVT_STRING | LK.CVT_INTEGER, u8) === nothing   # a compound
    @test LK.get_value_text(ld, t + 4, LK.CVT_ATOM, u8) == (UInt8[0xc3, 0xa9], 2)
    @test_throws LK.NotPortedError LK.get_value_text(ld, t, LK.CVT_ATOM, UInt32(0))   # PL_mb_text: only REP_UTF8
end

# LK-ONLY (pl-fli.c:2213-2236): PL_get_text_as_atom is the atom itself for an atom (whatever the flags), else the atom of the
# text the flags allow — one text, one atom, a wide one above 0xff — and nothing for a variable, a compound or a type the
# flags do not allow. DIVERGES (forced): a text with the character 0 raises AtomNotRepresentableError.
@testset "LK-ONLY: PL_get_text_as_atom (pl-fli.c:2213)" begin
    ld, t = _fa_engine(_R[_rs("abc"), _rg("xyz"), _fa_k(42), _rv(1), _rf("f", _rs("a")), _rg("a€"), _rnil(), _rv(2), _rv(3)])
    @test LK.PL_put_list_codes(ld, t + 7, _fa_b("hi"))
    @test LK.PL_put_string_nchars(ld, t + 8, 3, UInt8[0x61, 0x00, 0x62])
    f0 = UInt32(0)
    @test lk_name(LK.PL_get_text_as_atom(ld, t, f0)) === :abc                # an atom: itself, no flag needed
    @test LK.PL_get_text_as_atom(ld, t + 6, f0) == LK.PL_get_atom(ld, t + 6)  # [] too
    @test lk_name(LK.PL_get_text_as_atom(ld, t + 1, LK.CVT_STRING)) === :xyz
    @test LK.PL_get_text_as_atom(ld, t + 1, LK.CVT_ATOM) === nothing         # a string, CVT_STRING not set
    @test lk_name(LK.PL_get_text_as_atom(ld, t + 1, LK.CVT_STRING)) === lk_name(LK.PL_new_atom(ld, _fa_b("xyz")))   # one text, one atom
    @test lk_name(LK.PL_get_text_as_atom(ld, t + 2, LK.CVT_INTEGER)) === Symbol("42")
    @test LK.PL_get_text_as_atom(ld, t + 2, LK.CVT_ATOM | LK.CVT_STRING) === nothing
    @test LK.PL_get_text_as_atom(ld, t + 3, LK.CVT_ALL) === nothing          # a variable
    @test LK.PL_get_text_as_atom(ld, t + 4, LK.CVT_ALL) === nothing          # a compound
    w = LK.PL_get_text_as_atom(ld, t + 5, LK.CVT_STRING)
    @test lk_name(w) === Symbol("a€") && LK.isUCSAtom(LK.atomValue(ld.atoms, LK._atom_word!(ld, w)))
    @test lk_name(LK.PL_get_text_as_atom(ld, t + 7, LK.CVT_LIST)) === :hi    # a code list
    @test LK.PL_get_text_as_atom(ld, t + 7, LK.CVT_STRING) === nothing
    @test_throws LK.AtomNotRepresentableError LK.PL_get_text_as_atom(ld, t + 8, LK.CVT_STRING)   # a\0b
    ex = try
        LK.PL_get_text_as_atom(ld, t + 8, LK.CVT_STRING)
    catch e
        e
    end
    @test ex isa LK.AtomNotRepresentableError && ex.codes == UInt32[0x61, 0x00, 0x62]
end

# ── group F (pl-fli.c): PL_get_module, _PL_get_atomic, _PL_put_atomic, put_xpce_ref_arg, PL_term_type, PL_unify_output,
# PL_unify_termv, PL_unify_term ─────────────────────────────────────────────────────────────────────────────────

"An engine with a database: `(gd, ld, t)` — the value `vs[i]` in term reference `t + i - 1` (as `_fa_engine`)."
function _fa_gengine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return db.gd, ld, t
end

"Whether `t` holds the text atom `name`."
_fa_is_atom(ld, t, name::Symbol) = LK.PL_is_atom(ld, t) && _fa_atom(ld, t) === name

# LK-ONLY (pl-fli.c:2588-2599): PL_get_module is lookupModule of the atom the term reference holds — the module the name gives
# (created if new, one index for one name) — and fails for anything but an atom.
@testset "LK-ONLY: PL_get_module (pl-fli.c:2588)" begin
    gd, ld, t = _fa_gengine(_R[_rs("m9"), _rs("user"), _fa_k(5), _rf("f", _rs("a")), _rv(1)])
    m = LK.PL_get_module(gd, ld, t)
    @test m isa Int && m > 0 && m == LK.PL_new_module(gd, _rs("m9"))
    @test lk_name(gd.modules[m].atom) === :m9
    @test LK.PL_get_module(gd, ld, t) == m                                   # the same index again
    @test LK.PL_get_module(gd, ld, t + 1) == LK.MODULE_user(gd).index
    @test LK.PL_get_module(gd, ld, t + 2) === nothing                        # an integer
    @test LK.PL_get_module(gd, ld, t + 3) === nothing                        # a compound
    @test LK.PL_get_module(gd, ld, t + 4) === nothing                        # a variable
end

# LK-ONLY (pl-fli.c:4347-4366): _PL_get_atomic is the word the term reference holds (valHandle), _PL_put_atomic makes another
# reference hold that word: the atom or the integer comes back from the second reference.
@testset "LK-ONLY: _PL_get_atomic and _PL_put_atomic (pl-fli.c:4347, :4362)" begin
    ld, t = _fa_engine(_R[_rs("abc"), _fa_k(77), _rv(1), _rv(2)])
    w = LK._PL_get_atomic(ld, t)
    @test w == LK._atom_word!(ld, _rs("abc"))
    @test LK._PL_put_atomic(ld, t + 2, w) === nothing
    @test _fa_is_atom(ld, t + 2, :abc)
    @test LK._PL_put_atomic(ld, t + 3, LK._PL_get_atomic(ld, t + 1)) === nothing
    @test LK.PL_get_integer(ld, t + 3) == 77
end

# LK-ONLY (pl-fli.c:4278-4289): put_xpce_ref_arg is the tagged integer of an integer reference, the word of the atom of an
# atom reference; an integer the tag cannot hold raises representation_error(pce_reference) and gives the word 0.
@testset "LK-ONLY: put_xpce_ref_arg (pl-fli.c:4278)" begin
    ld, t = _fa_engine(_R[_rv(1)])
    @test LK.put_xpce_ref_arg(ld, LK.xpceref_t{_R}(LK.PL_INTEGER, 5, nothing)) == LK.consInt(Int64(5))
    @test LK.put_xpce_ref_arg(ld, LK.xpceref_t{_R}(LK.PL_INTEGER, -3, nothing)) == LK.consInt(Int64(-3))
    @test LK.put_xpce_ref_arg(ld, LK.xpceref_t{_R}(LK.PL_ATOM, 0, _rs("obj"))) == LK._atom_word!(ld, _rs("obj"))
    @test ld.exception_term == 0
    @test LK.put_xpce_ref_arg(ld, LK.xpceref_t{_R}(LK.PL_INTEGER, typemax(Int64), nothing)) == 0
    @test ld.exception_term != 0
    fm = LK.PL_new_term_ref(ld)
    @test LK.PL_get_arg(ld, 1, ld.exception_term, fm)
    @test LK.PL_get_name_arity(ld, fm) !== nothing && lk_name(LK.PL_get_name_arity(ld, fm)[1]) === :representation_error
end

# LK-ONLY (pl-fli.c:4539-4569): PL_term_type — a variable PL_VARIABLE, a text atom PL_ATOM, `[]` PL_NIL, an integer PL_INTEGER
# (a big one too), a float PL_FLOAT, a string PL_STRING, a compound PL_TERM, a list cell PL_LIST_PAIR, a `dict` compound PL_DICT.
@testset "LK-ONLY: PL_term_type (pl-fli.c:4539)" begin
    ld, t = _fa_engine(_R[_rv(1), _rs("abc"), _rnil(), _fa_k(5), _rg(2.5), _rg("s"), _rf("f", _rs("a")),
                          _rlist(_fa_k(1)), _rf("dict", _rs("t"), _fa_k(1), _rs("k")), _rg(big(2)^70)])
    @test LK.PL_term_type(ld, t) == LK.PL_VARIABLE == 1
    @test LK.PL_term_type(ld, t + 1) == LK.PL_ATOM == 2
    @test LK.PL_term_type(ld, t + 2) == LK.PL_NIL == 8
    @test LK.PL_term_type(ld, t + 3) == LK.PL_INTEGER == 3
    @test LK.PL_term_type(ld, t + 4) == LK.PL_FLOAT == 5
    @test LK.PL_term_type(ld, t + 5) == LK.PL_STRING == 6
    @test LK.PL_term_type(ld, t + 6) == LK.PL_TERM == 7
    @test LK.PL_term_type(ld, t + 7) == LK.PL_LIST_PAIR == 10
    @test LK.PL_term_type(ld, t + 8) == LK.PL_DICT == 44
    @test LK.PL_term_type(ld, t + 9) == LK.PL_INTEGER
end

# LK-ONLY (pl-fli.c:4601-4614): PL_unify_output binds a variable to a bound value (an atom, a compound, an integer) and
# otherwise is PL_unify: equal values unify, different ones do not, two variables become one.
@testset "LK-ONLY: PL_unify_output (pl-fli.c:4601)" begin
    ld, t = _fa_engine(_R[_rv(1), _rs("a"), _rv(2), _rf("f", _rs("x")), _rv(3), _fa_k(42), _rs("b"), _rv(4), _rv(5)])
    @test LK.PL_unify_output(ld, t, t + 1) && _fa_atom(ld, t) === :a
    @test LK.PL_unify_output(ld, t + 2, t + 3)
    @test LK.PL_get_name_arity(ld, t + 2) !== nothing && lk_name(LK.PL_get_name_arity(ld, t + 2)[1]) === :f
    @test LK.PL_unify_output(ld, t + 4, t + 5) && LK.PL_get_integer(ld, t + 4) == 42
    @test LK.PL_unify_output(ld, t, t + 1)                                   # bound to the same atom
    @test !LK.PL_unify_output(ld, t, t + 6)                                  # bound to another
    @test LK.PL_unify_output(ld, t + 7, t + 8) && LK.PL_unify_atom(ld, t + 8, _rs("z")) && _fa_atom(ld, t + 7) === :z
end

"The elements of the integer list term reference `t` holds (`nothing` for no proper list)."
_fa_ints(ld, t) = _fa_codes(ld, t)

# LK-ONLY (pl-fli.c:4009-4070): PL_unify_termv reads each tag and its values in order: PL_VARIABLE leaves the term alone, PL_ATOM,
# PL_BOOL (any non-zero is true), the integer tags, PL_POINTER, PL_FLOAT/PL_DOUBLE, PL_STRING, PL_CHARS, PL_NCHARS, PL_TERM.
@testset "LK-ONLY: PL_unify_term, atomic tags (pl-fli.c:4009)" begin
    gd, ld, t = _fa_gengine(_R[_rv(i) for i in 1:14])
    U = LK.PL_unify_term
    @test U(gd, ld, t, LK.PL_VARIABLE) && LK.PL_is_variable(ld, t)
    @test U(gd, ld, t + 1, LK.PL_ATOM, _rs("a")) && _fa_atom(ld, t + 1) === :a
    @test U(gd, ld, t + 2, LK.PL_BOOL, 7) && _fa_atom(ld, t + 2) === :true
    @test U(gd, ld, t + 3, LK.PL_BOOL, 0) && _fa_atom(ld, t + 3) === :false
    @test U(gd, ld, t + 4, LK.PL_LIST, 7, LK.PL_SHORT, 1, LK.PL_INT, 2, LK.PL_LONG, 3, LK.PL_INTEGER, 4,
            LK.PL_INT64, 5, LK.PL_INTPTR, 6, LK.PL_SWORD, 7) && _fa_ints(ld, t + 4) == [1, 2, 3, 4, 5, 6, 7]
    @test U(gd, ld, t + 5, LK.PL_POINTER, 4096) && LK.PL_get_pointer(ld, t + 5) === UInt(4096)
    @test U(gd, ld, t + 6, LK.PL_FLOAT, 2.5) && LK.PL_get_float(ld, t + 6) == 2.5
    @test U(gd, ld, t + 7, LK.PL_DOUBLE, -0.5) && LK.PL_get_float(ld, t + 7) == -0.5
    @test U(gd, ld, t + 8, LK.PL_STRING, _fa_b("abc")) && LK.PL_is_string(ld, t + 8) && _fa_text(ld, t + 8) == "abc"
    @test U(gd, ld, t + 9, LK.PL_CHARS, _fa_b("abc")) && _fa_atom(ld, t + 9) === :abc
    @test U(gd, ld, t + 10, LK.PL_NCHARS, 2, _fa_b("abc")) && _fa_atom(ld, t + 10) === :ab
    @test LK.PL_unify_atom(ld, t + 11, _rs("q"))
    @test U(gd, ld, t + 12, LK.PL_TERM, t + 11) && _fa_atom(ld, t + 12) === :q
    @test U(gd, ld, t + 13, LK.PL_INT64, typemax(Int64)) && LK.PL_get_integer(ld, t + 13) === nothing
end

# LK-ONLY (pl-fli.c:4065-4140): the text tags — UTF-8 atom and string, UTF-8 with a length (atom, code list, string), wide
# characters with a length (atom, code list, string); the multibyte tags reach the refusal of PL_unify_chars (REP_MB).
@testset "LK-ONLY: PL_unify_term, text tags (pl-fli.c:4065)" begin
    if !(isdefined(LK, :PL_unify_chars) && isdefined(LK, :PL_unify_wchars))
        # the text tags call PL_unify_chars and PL_unify_wchars, which this branch SKIPS (wip/clib-uri, wip/clib1 define
        # them): the rows run once a clib branch is merged under this one; until then they are visibly Broken, not absent.
        @test_broken false
    else
        gd, ld, t = _fa_gengine(_R[_rv(i) for i in 1:11])
        U = LK.PL_unify_term
        e = Vector{UInt8}("é")
        @test U(gd, ld, t, LK.PL_UTF8_CHARS, e) && LK.PL_is_atom(ld, t) && _fa_atom(ld, t) === Symbol("é")
        @test U(gd, ld, t + 1, LK.PL_UTF8_STRING, e) && LK.PL_is_string(ld, t + 1) && _fa_text(ld, t + 1) == "é"
        @test U(gd, ld, t + 2, LK.PL_NUTF8_CHARS, 2, _fa_b("abc")) && _fa_atom(ld, t + 2) === :ab
        @test U(gd, ld, t + 3, LK.PL_NUTF8_CODES, 3, _fa_b("abc")) && _fa_codes(ld, t + 3) == [97, 98, 99]
        @test U(gd, ld, t + 4, LK.PL_NUTF8_STRING, 1, _fa_b("abc")) && LK.PL_is_string(ld, t + 4) && _fa_text(ld, t + 4) == "a"
        w = UInt32[0x61, 0x20ac, 0x62]
        @test U(gd, ld, t + 5, LK.PL_NWCHARS, 2, w) && _fa_atom(ld, t + 5) === Symbol("a€")
        @test U(gd, ld, t + 6, LK.PL_NWCODES, 3, w) && _fa_codes(ld, t + 6) == [0x61, 0x20ac, 0x62]
        @test U(gd, ld, t + 7, LK.PL_NWSTRING, -1, w) && LK.PL_is_string(ld, t + 7) && _fa_text(ld, t + 7) == "a€b"
        @test_throws LK.NotPortedError U(gd, ld, t + 8, LK.PL_MBCHARS, _fa_b("abc"))
        @test_throws LK.NotPortedError U(gd, ld, t + 9, LK.PL_MBCODES, _fa_b("abc"))
        @test_throws LK.NotPortedError U(gd, ld, t + 10, LK.PL_MBSTRING, _fa_b("abc"))
    end
end

# LK-ONLY (pl-fli.c:4141-4233): PL_FUNCTOR_CHARS (name and arity) and PL_FUNCTOR (a functor word) unify the functor and the
# following tags fill its arguments left to right, a nested functor's arguments before the next argument of its parent;
# PL_LIST n takes n elements and ends in []; a term already bound is compared, not rebuilt.
@testset "LK-ONLY: PL_unify_term, functors and lists (pl-fli.c:4141)" begin
    gd, ld, t = _fa_gengine(_R[_rv(i) for i in 1:8])
    U = LK.PL_unify_term
    a1, a2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test U(gd, ld, t, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 2, LK.PL_ATOM, _rs("a"), LK.PL_INT, 5)
    na = LK.PL_get_name_arity(ld, t)
    @test na !== nothing && lk_name(na[1]) === :f && na[2] == 2
    @test LK.PL_get_arg(ld, 1, t, a1) && _fa_atom(ld, a1) === :a
    @test LK.PL_get_arg(ld, 2, t, a2) && LK.PL_get_integer(ld, a2) == 5
    ft = _fa_functor(ld, "g", 2)
    @test U(gd, ld, t + 1, LK.PL_FUNCTOR, ft, LK.PL_VARIABLE, LK.PL_ATOM, _rs("x"))
    @test LK.PL_get_arg(ld, 1, t + 1, a1) && LK.PL_is_variable(ld, a1)
    @test LK.PL_get_arg(ld, 2, t + 1, a2) && _fa_atom(ld, a2) === :x
    @test U(gd, ld, t + 2, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 2, LK.PL_FUNCTOR_CHARS, _fa_b("g"), 1, LK.PL_INT, 1, LK.PL_INT, 2)
    @test LK.PL_get_arg(ld, 1, t + 2, a1) && LK.PL_get_arg(ld, 1, a1, a2) && LK.PL_get_integer(ld, a2) == 1
    @test LK.PL_get_arg(ld, 2, t + 2, a2) && LK.PL_get_integer(ld, a2) == 2
    @test U(gd, ld, t + 3, LK.PL_LIST, 3, LK.PL_INT, 1, LK.PL_INT, 2, LK.PL_INT, 3) && _fa_ints(ld, t + 3) == [1, 2, 3]
    @test U(gd, ld, t + 4, LK.PL_LIST, 0) && LK.PL_get_nil(ld, t + 4)
    @test U(gd, ld, t + 5, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 2, LK.PL_LIST, 2, LK.PL_INT, 1, LK.PL_INT, 2, LK.PL_ATOM, _rs("x"))
    @test LK.PL_get_arg(ld, 1, t + 5, a1) && _fa_ints(ld, a1) == [1, 2]
    @test LK.PL_get_arg(ld, 2, t + 5, a2) && _fa_atom(ld, a2) === :x
    @test U(gd, ld, t + 6, LK.PL_FUNCTOR_CHARS, _fa_b("c"), 0) && _fa_atom(ld, t + 6) === :c    # arity 0: the atom
    @test U(gd, ld, t, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 2, LK.PL_ATOM, _rs("a"), LK.PL_INT, 5)   # compared, not rebuilt
    @test !U(gd, ld, t, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 2, LK.PL_ATOM, _rs("a"), LK.PL_INT, 6)
    @test !U(gd, ld, t, LK.PL_FUNCTOR_CHARS, _fa_b("g"), 2, LK.PL_ATOM, _rs("a"), LK.PL_INT, 5)
end

# LK-ONLY (pl-fli.c:4189-4247): a _PL_PREDICATE_INDICATOR is Name/Arity of the predicate (qualified when its module is not user);
# a failure resets the term references made on the way (4231, 4237); an unknown tag fails (4196-4198); a list longer than the
# bound one fails. DIVERGES (forced): upstream's PL_LIST with a failing PL_unify_list repeats the call; here it fails.
@testset "LK-ONLY: PL_unify_term, predicates, failure (pl-fli.c:4189)" begin
    gd, ld, t = _fa_gengine(_R[_rv(1), _rv(2), _rs("a"), _rlist(_fa_k(1)), _rv(3), _rlist(_fa_k(1), _fa_k(2))])
    U = LK.PL_unify_term
    a1, a2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    p = LK.PL_pred(gd, ld, _fa_functor(ld, "p", 2), 0)
    @test U(gd, ld, t, LK._PL_PREDICATE_INDICATOR, p)
    na = LK.PL_get_name_arity(ld, t)
    @test na !== nothing && lk_name(na[1]) === :/ && na[2] == 2
    @test LK.PL_get_arg(ld, 1, t, a1) && _fa_atom(ld, a1) === :p
    @test LK.PL_get_arg(ld, 2, t, a2) && LK.PL_get_integer(ld, a2) == 2
    m = LK.PL_new_module(gd, _rs("m1"))
    q = LK.PL_pred(gd, ld, _fa_functor(ld, "p", 2), m)
    @test U(gd, ld, t + 1, LK._PL_PREDICATE_INDICATOR, q)
    na = LK.PL_get_name_arity(ld, t + 1)
    @test na !== nothing && lk_name(na[1]) === :(:) && na[2] == 2
    before = LK.PL_new_term_refs(ld, 0)
    @test !U(gd, ld, t + 2, LK.PL_ATOM, _rs("b"))
    @test !U(gd, ld, t + 2, LK.PL_FUNCTOR_CHARS, _fa_b("f"), 1, LK.PL_ATOM, _rs("a"))
    @test !U(gd, ld, t + 3, LK.PL_LIST, 2, LK.PL_INT, 1, LK.PL_INT, 2)
    @test !U(gd, ld, t + 5, LK.PL_LIST, 1, LK.PL_INT, 1)                     # the list is longer: the tail is not []
    @test !U(gd, ld, t + 4, 999)
    @test LK.PL_new_term_refs(ld, 0) == before
    @test LK.PL_is_variable(ld, t + 4)
end

# LK-ONLY: PL_unify_termv takes the vector the variadic call collects; PL_unify_term is its variadic form.
@testset "LK-ONLY: PL_unify_termv (pl-fli.c:3997)" begin
    gd, ld, t = _fa_gengine(_R[_rv(1), _rv(2)])
    @test LK.PL_unify_termv(gd, ld, t, Any[LK.PL_ATOM, _rs("v")]) && _fa_atom(ld, t) === :v
    @test LK.PL_unify_termv(gd, ld, t + 1, [LK.PL_INT, 9]) && LK.PL_get_integer(ld, t + 1) == 9
end

@testset "the meter: the readers and writers on terms on the stack make no cold traffic" begin
    ld, t = _fa_engine(_R[_rf("f", _rs("a"), _rv(1)), _rv(2), _rv(3), _rv(4), _fa_k(77)])
    a = LK.PL_new_term_ref(ld)
    fk = _fa_functor(ld, "k", 2)
    c0 = _fa_counts(ld)
    @test LK.PL_get_arg(ld, 1, t, a) && LK.PL_get_compound_name_arity(ld, t) !== nothing
    @test LK.PL_put_functor(ld, t + 1, fk)
    @test LK.PL_put_list(ld, t + 2)
    @test LK.PL_put_bool(ld, t + 3, true)
    @test LK.PL_put_pointer(ld, a, UInt(4096)) && LK.PL_get_pointer(ld, a) === UInt(4096)
    @test LK.PL_get_uintptr(ld, t + 4) === UInt(77)
    @test LK.PL_unify_pointer(ld, t + 4, UInt(77)) && LK.PL_unify_int64_ex(ld, t + 4, 77)
    @test LK.PL_functor_arity(ld, fk) == 2 && LK.PL_functor_name(ld, fk) isa _R
    @test _fa_counts(ld) == c0
end
