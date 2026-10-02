# ORIGINAL: the term interface — settled by the user 2026-10-02 for MeTTa-shaped terms (head as child 1); Prolog has no such interface.
#
# A COMPOUND TERM IS A SEQUENCE OF CHILDREN WITH THE HEAD AS CHILD 1 — not Prolog's functor/arity,
# because a head may itself be a variable or a compound. Prolog's f(a, b) is [f, a, b], so nothing
# is lost; functor and arity are `child(t, 1)` and `nchildren(t) - 1` where a caller wants them.
#
# The kernel only ever touches terms through these functions. Two rules make that cheap:
#   1. every function returns a CONCRETE type (`Kind`, `Int`, `UInt64`, `Bool`, or the term type);
#   2. an implementation defines them on its CONCRETE term types,
# so the kernel's loops compile without dynamic dispatch. test/test_static_analysis.jl enforces it
# for the default term type with JET; test/core_lang/test_term_interface.jl checks the semantics.

"""
    Kind

The four kinds of term: [`VAR`](@ref) (a variable), [`SYM`](@ref) (a symbol), [`GND`](@ref) (a
grounded host value) and [`EXPR`](@ref) (a compound: a sequence of children, head first).
"""
@enum Kind::UInt8 VAR SYM GND EXPR

@doc "A variable term. Its identity is [`var_key`](@ref)." VAR
@doc "A symbol term. Its identity is [`sym_key`](@ref)." SYM
@doc "A grounded term: a host value, compared only through [`gnd_equal`](@ref)." GND
@doc "A compound term: [`nchildren`](@ref) children, the head as child 1." EXPR

"""
    kind(t) -> Kind

Which of [`VAR`](@ref), [`SYM`](@ref), [`GND`](@ref), [`EXPR`](@ref) the term `t` is.
"""
function kind end

"""
    nchildren(t) -> Int

The number of children of a compound term — the head counts. `0` for every non-[`EXPR`](@ref) term,
and for the empty expression `()`.
"""
function nchildren end

"""
    child(t, i::Int) -> term

Child `i` of a compound term, `1 ≤ i ≤ nchildren(t)`. The head is `child(t, 1)`; it may be any kind
of term, a variable or a compound included.
"""
function child end

"""
    sym_key(t) -> UInt64

The identity of a [`SYM`](@ref) term: equal exactly when the two symbols are the same symbol.
Process-local — never persist it.
"""
function sym_key end

"""
    sym_hash(t) -> UInt64

A hash of a [`SYM`](@ref) term that is the SAME IN EVERY PROCESS — derived from the symbol's name,
not from where it lives — for keys whose LAYOUT must be reproducible: the clause index keys atoms
and functors with it. Equal for the same symbol; distinct symbols MAY collide, so it is a key,
never an identity — identity is [`sym_key`](@ref). Added 2026-10-02 (user): with `sym_key` an
address, the index's bucket order and last-ulp speedups differed from run to run.
"""
function sym_hash end

"""
    var_key(t) -> UInt64

The identity of a [`VAR`](@ref) term: equal exactly when the two terms are the same variable.
"""
function var_key end

"""
    gnd_key(t) -> Union{UInt64, Nothing}

An index key for a [`GND`](@ref) term, or `nothing` when the value cannot be keyed consistently
with [`gnd_equal`](@ref) — and `nothing` means WILDCARD, never a shared bucket.

The law: `gnd_equal(a, b)` and both keys non-`nothing` ⇒ the keys are equal. Keys may collide for
unequal values (an index only narrows), but equal values must never key apart, or an index drops
answers. `==`, `isequal` and `hash` disagree on `0.0`/`-0.0` and on every container, which is why
the key is not simply `hash`; see [`gnd_value_key`](@ref).
"""
function gnd_key end

"""
    gnd_equal(a, b) -> Bool

Whether two [`GND`](@ref) terms match — `==` on their values by default, always a strict `Bool`
(never `missing`). The ONLY place the kernel compares grounded values.
"""
function gnd_equal end

"""
    atomic_compare(a, b) -> Int

The standard order of two ATOMIC terms ([`SYM`](@ref) or [`GND`](@ref), in any combination):
`-1`, `0` or `1`. Total, and `0` exactly when `a` and `b` are IDENTICAL — the same symbol, or the
same host value (same type and `isequal`; for IEEE floats, the same bits). Identity is stricter
than [`gnd_equal`](@ref): `1` and `1.0` match, but they are not identical, and their order is
`1.0` before `1` as in SWI-Prolog.

The implementation supplies this because only it can see names and values; the kernel derives
the rest of the standard order ([`compareStandard`](@ref)).
"""
function atomic_compare end

"""
    mk_var(T::Type, key::UInt64) -> T

A [`VAR`](@ref) term of type `T` with `var_key(mk_var(T, key)) == key`.
"""
function mk_var end

"""
    mk_expr(T::Type, children::Vector{T}) -> T

A compound term of type `T` with the given children, head first. Takes ownership of `children`:
the caller must not mutate the vector afterwards.
"""
function mk_expr end

"""
    is_ground(t) -> Bool

Whether `t` contains no variable. This default walks the term; an implementation may answer from a
cached bit instead, and must then agree with [`is_ground_walk`](@ref).
"""
is_ground(t) = is_ground_walk(t)

"""
    is_ground_walk(t) -> Bool

Groundness recomputed by walking `t` through the interface — the reference [`is_ground`](@ref)
must agree with.
"""
function is_ground_walk(t)::Bool
    k = kind(t)
    k === VAR && return false
    k === EXPR || return true
    for i in 1:nchildren(t)
        is_ground_walk(child(t, i)) || return false
    end
    return true
end
