# ORIGINAL: FLI-API group 1 (audit D-0777 (4)(a)) — the pl-fli.c API functions foreign code calls that the
# kernel did not carry: PL_put_bool, PL_put_pointer, PL_put_functor, PL_put_list, PL_get_uintptr,
# PL_get_pointer, PL_get_arg (pl-fli.c PL_get_arg_sz), PL_get_compound_name_arity (PL_get_compound_name_arity_sz),
# PL_unify_int64_ex, PL_unify_pointer (src/pl-fli.jl). test/core_lang/test_fli_api1_cells.jl — on every term type.
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
    @test _fa_counts(ld) == c0
end
