# ORIGINAL: chooses which implementation of the term interface a term-generic test file runs on; Prolog has one term representation.
# test/term_under_test.jl — the term implementation under test, for a TERM-GENERIC test file.
#
# A test that reaches the kernel only through the term interface is TERM-GENERIC: it must pass on
# EVERY implementation, not only on the one it was written against — otherwise the interface is
# whatever that one implementation happens to do. Such a file starts with
#
#     include(joinpath(@__DIR__, "..", "term_under_test.jl"))
#     const _UT = lk_term_type(Union{Int64, Float64, String})    # the payload the file needs
#
# and builds and reads terms only with `lk_sym`/`lk_gnd`/`lk_var`/`lk_name`/`lk_value` and the
# interface itself. test/runtests.jl finds such files BY THAT INCLUDE and runs each once per
# implementation in `LK_TERM_IMPLS`, setting LOGICKERNEL_TERM. Run alone, a file reads the same
# variable, default `reference`:
#
#     LOGICKERNEL_TERM=alt tools/run_tests.sh test/core_lang/test_unify.jl
#
# The implementations: `reference` — `Term{G}` (src/default_term.jl), for the payload `G` the file
# asks for; `alt` — `AltTerm` (test/core_lang/alt_term.jl), deliberately unlike it, which takes any
# payload. A file that is NOT term-generic (it tests one type's own behaviour, like
# test/core_lang/test_default_term.jl) does not include this.
using LogicKernel

const LK_TERM_IMPLS = ("reference", "alt")
const LK_TERM_IMPL = get(ENV, "LOGICKERNEL_TERM", "reference")
LK_TERM_IMPL in LK_TERM_IMPLS || error(
    "LOGICKERNEL_TERM=$(repr(LK_TERM_IMPL)): expected one of $(join(LK_TERM_IMPLS, ", "))"
)

isdefined(Main, :LKAltTerm) ||
    Base.include(Main, joinpath(@__DIR__, "core_lang", "alt_term.jl"))
using Main.LKAltTerm: AltTerm, alt_sym, alt_gnd, alt_var, alt_name, alt_value

"The term type under test, for a file whose grounded payload is `G`."
lk_term_type(::Type{G}) where {G} = LK_TERM_IMPL == "reference" ? Term{G} : AltTerm

"The symbol `name`."
lk_sym(::Type{Term{G}}, name::Symbol) where {G} = sym_term(Term{G}, name)
lk_sym(::Type{AltTerm}, name::Symbol) = alt_sym(name)

"The grounded value `v`."
lk_gnd(::Type{Term{G}}, v) where {G} = gnd_term(Term{G}, v)
lk_gnd(::Type{AltTerm}, v) = alt_gnd(v)

"A CALLER's variable — checked: keys at or above `KERNEL_VAR_BASE` are the kernel's."
lk_var(::Type{Term{G}}, key::UInt64) where {G} = var_term(Term{G}, key)
lk_var(::Type{AltTerm}, key::UInt64) = alt_var(key)

"The name of a symbol."
lk_name(t::Term) = sym_name(t)
lk_name(t::AltTerm) = alt_name(t)

"The host value of a grounded term."
lk_value(t::Term) = gnd_value(t)
lk_value(t::AltTerm) = alt_value(t)

"""
`==/2`: two terms are identical in the standard order (`compareStandard(a, b, true) == 0`), and two
vectors of terms elementwise. A term-generic test compares terms with this, never with Base `==`,
which is the reference type's own convenience — `AltTerm`'s throws.
"""
lk_eq(a, b)::Bool = compareStandard(a, b, true) == 0
lk_eq(a::AbstractVector, b::AbstractVector)::Bool =
    length(a) == length(b) && all(((x, y),) -> lk_eq(x, y), zip(a, b))
