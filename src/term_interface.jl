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
#
# THE RULES MAKE THE KERNEL FAST, NOT CORRECT. A term type may also be ABSTRACT with concrete leaves
# — Core's `Atom` (`Sym`, `Var`, `Expression`, `Grounded{T}`) is, and so is the conformance suite's
# second implementation (test/core_lang/alt_term.jl) — and the kernel must then still be correct,
# only slower. So the kernel NEVER takes the term type from `typeof(t)`, which is a leaf there: it
# asks [`term_type`](@ref). Found 2026-10-03 by the second implementation: 18 kernel methods bound
# the term type from a term argument (`f(t::T) where {T}`), and every one failed on a hierarchy.
#
# `===` ON COMPOUNDS IS CONSTANT-TIME, AND `a === b` IMPLIES THE TERMS ARE IDENTICAL; SHARED SUBTERMS
# ARE PERMITTED (user, 2026-10-03). The kernel asks whether two terms are the SAME term with `===` —
# upstream compares cell addresses (`if ( t1 == t2 )` in pl-prims.c `unify_simple_ptrs`, pl-variant.c)
# — and keys its identity maps by them (`IdDict`: the cyclic links and the occurs-check marks, where
# upstream overwrites a cell). So `===` on two compounds must be an address compare, not a walk: a
# compound is a mutable object or holds one (`Term{G}` holds its children in a `Vector`). A compound
# that is a plain immutable VALUE — children in a `Tuple` — makes `===` and `objectid` structural:
# linear in the term, exponential on shared subterms; with such compounds the live unification
# differential did not finish (2026-10-03). Sharing itself is SWI's own behaviour: `copy_term/2`
# shares ground subterms with the original, and a subterm met twice is shared in the copy
# (pl-copyterm.c, its marking table and `COPY_SHARE`) — so an implementation may return the SAME
# object for identical subterms (hash-consing), and the kernel must be correct when it does. The
# conformance suite runs a sharing implementation (`AltTerm{true}`, test/core_lang/alt_term.jl).

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
    term_type(t) -> Type

The TERM TYPE `t` belongs to: the `T` that [`mk_var`](@ref) and [`mk_expr`](@ref) take, that
[`child`](@ref) returns, and that the kernel's containers hold (`Vector{T}`, `PL_local_data{T}`).
For one concrete struct (the reference [`Term`](@ref)) it is `typeof(t)`; for an abstract hierarchy
(Core's `Atom`) it is the abstract type, never the leaf `typeof(t)` names. Every implementation
defines it — there is no default, because `typeof(t)` is exactly the wrong answer for a hierarchy.
"""
function term_type end

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

WHO OWNS WHICH KEYS (user, 2026-10-03): a CALLER's variables have keys below
[`KERNEL_VAR_BASE`](@ref) (2^63); the top half belongs to the kernel, which takes the variables it
creates — the renamed variables of a clause, which can survive in an answer — from one process-wide
counter and never reuses a key in a process. An implementation's caller-facing variable constructor
must enforce the caller half (the reference type's [`var_term`](@ref) does); [`mk_var`](@ref) is the
raw constructor the kernel builds its own variables with, and checks nothing.
"""
function var_key end

"""
    KERNEL_VAR_BASE

`2^63`: variable keys at or above it are the kernel's, below it the caller's (see [`var_key`](@ref)).
"""
const KERNEL_VAR_BASE = UInt64(1) << 63

"""
    gnd_key(t) -> Union{UInt64, Nothing}

An index key for a [`GND`](@ref) term, or `nothing` when the value cannot be keyed consistently
with [`gnd_equal`](@ref) — and `nothing` means WILDCARD, never a shared bucket.

The law: `gnd_equal(a, b)` and both keys non-`nothing` ⇒ the keys are equal. Keys may collide for
unequal values (an index only narrows), but matching values must never key apart, or an index drops
answers. The key follows the implementation's [`gnd_equal`](@ref): the reference type's follows SWI's
identity ([`gnd_value_key`](@ref)); an implementation matching by `==` (Core's MeTTa terms) must key
by `==`, where `==`, `isequal` and `hash` disagree on `0.0`/`-0.0` and on every container.
"""
function gnd_key end

"""
    gnd_equal(a, b) -> Bool

Whether two [`GND`](@ref) terms match — that is, unify. Always a strict `Bool` (never `missing`),
and the ONLY place the kernel compares grounded values for matching.

The matching is the IMPLEMENTATION's to define. The reference type ([`Term`](@ref)) follows SWI-Prolog:
two grounded values match exactly when they are IDENTICAL ([`atomic_compare`](@ref) `== 0`) — `1` and
`1.0` do not unify, `0.0` and `-0.0` do not (floats compare by bit pattern), a NaN unifies with an
identical NaN. Core's MeTTa terms match by `==` instead and supply their own `gnd_equal` and
[`gnd_key`](@ref) (user, 2026-10-03: the kernel stays SWI-faithful; MeTTa's semantics live in Core's
implementation of this interface).
"""
function gnd_equal end

"""
    atomic_compare(a, b) -> Int

The standard order of two ATOMIC terms ([`SYM`](@ref) or [`GND`](@ref), in any combination):
`-1`, `0` or `1`. Total, and `0` exactly when `a` and `b` are IDENTICAL — the same symbol, or the
same host value (integers by value, as in SWI's single integer type; otherwise the same type and
`isequal`, and for IEEE floats the same bits). `1` and `1.0` are not identical, and their order is
`1.0` before `1` as in SWI-Prolog. The reference type's [`gnd_equal`](@ref) is this identity.

The implementation supplies this because only it can see names and values; the kernel derives
the rest of the standard order ([`compareStandard`](@ref)).
"""
function atomic_compare end

"""
    mk_var(T::Type, key::UInt64) -> T

A [`VAR`](@ref) term of type `T` with `var_key(mk_var(T, key)) == key` — the RAW constructor, which
the kernel builds its own variables (keys at or above [`KERNEL_VAR_BASE`](@ref)) with; it checks
nothing. A caller creating its own variables uses its type's checked constructor ([`var_term`](@ref)
for the reference type).
"""
function mk_var end

"""
    mk_expr(T::Type, children::Vector{T}) -> T

A compound term of type `T` with the given children, head first. Takes ownership of `children`:
the caller must not mutate the vector afterwards. It MAY return an existing compound identical
to the one asked for — shared subterms are permitted (see the header).
"""
function mk_expr end

# ── THE PROLOG LAYER (Q1, user 2026-10-03) ───────────────────────────────────────────────────────
# What the compiler and the built-ins need that MeTTa-shaped terms did not: constructors for symbols
# and grounded values, SWI-7's RESERVED SYMBOLS (pl-ressymbol.c) — `[]` above all — and numbers by
# their SEMANTIC kind. A reserved symbol is a [`SYM`](@ref) with a flag, not a kind of its own (user):
# upstream gives `[]` the atom tag and makes the blob type a property of the atom, so every site that
# asks `kind(t) === SYM` (indexing, functor heads, unification) stays right for `[]`; a site that
# needs TEXT asks [`is_reserved_symbol`](@ref).

"""
    mk_sym(T::Type, name::Symbol) -> T

The TEXT atom `name`. `mk_sym(T, Symbol("[]"))` is the atom `'[]'`, NOT the empty list — that is
[`mk_nil`](@ref).
"""
function mk_sym end

"""
    mk_gnd(T::Type, v) -> T

The grounded value `v`.
"""
function mk_gnd end

"""
    mk_reserved_symbol(T::Type, name::Symbol) -> T

The RESERVED SYMBOL `name` (pl-ressymbol.c `textToReservedSymbol`): a [`SYM`](@ref) of the blob type
`reserved_symbol` — atomic but NOT an atom (`atom/1` is `isTextAtom`, pl-fli.h). Against the text
atom of the same name it has
* a different [`sym_key`](@ref) — they are two symbols, so `[] == '[]'` fails;
* the SAME [`sym_hash`](@ref) — upstream's atom hash is a hash of the TEXT, so `term_hash([])` and
  `term_hash('[]')` agree;
* in the standard order: after numbers and strings, BEFORE EVERY TEXT ATOM (`reserved_symbol.rank = 0`,
  "between normal blob and text", pl-ressymbol.c:97), two reserved symbols by `strcmp` of their names.
"""
function mk_reserved_symbol end

"""
    is_reserved_symbol(t) -> Bool

Whether `t` is a reserved symbol (pl-ressymbol.c `isReservedSymbol`); `false` for every term that
is not a [`SYM`](@ref).
"""
function is_reserved_symbol end

"""
    is_nil(t) -> Bool

Whether `t` is SWI-7's `[]` — the reserved symbol `[]` (pl-fli.c `PL_get_nil`, pl-inline `isNil`).
`false` for the text atom `'[]'` and for every term that is not a [`SYM`](@ref).
"""
function is_nil end

"""
    mk_nil(T::Type) -> T

SWI-7's `[]`: the reserved symbol `[]` (pl-fli.c `PL_put_nil`).
"""
mk_nil(::Type{T}) where {T} = mk_reserved_symbol(T, NIL_NAME)

"The name of SWI-7's `[]` (pl-atom.ih `ATOM_nil`)."
const NIL_NAME = Symbol("[]")

"""
    is_pair(t) -> Bool

Whether `t` is a LIST CELL (pl-fli.c `PL_is_pair`): a compound whose head is the TEXT atom `'[|]'`
— SWI-7's list constructor, `FUNCTOR_dot2` — with exactly two arguments, `[H|T]` and `'[|]'(H, T)`
alike. `false` for `'[|]'` with any other number of arguments, for a compound headed by `[]` or
`'[]'`, for a reserved symbol named `'[|]'`, for every compound whose head is not a symbol (a
`\$expr/n`, two arguments after its head or not), and for every term that is not a compound
(user, 2026-10-04).
"""
function is_pair end

"The name of SWI-7's list constructor `'[|]'` (pl-atom.ih `ATOM_dot`, retyped to `'[|]'` in SWI-7)."
const LIST_CONS_NAME = Symbol("[|]")

"""
    NumKind

A number's SEMANTIC kind, as SWI-Prolog's: [`NUM_INTEGER`](@ref) (any size), [`NUM_RATIONAL`](@ref),
[`NUM_FLOAT`](@ref) — and [`NUM_NONE`](@ref) for every term that is not a number. Small vs big
integer is STORAGE, not a kind: [`integer_is_int64`](@ref) says which getter to use. A HEAD integer
is `H_SMALLINT` when it fits a tagged word and `H_MPZ` otherwise (pl-comp.c `compileArgument`,
probed in swipl 10.1.16); pl-comp.c's `is_portable_smallint` decides only body arithmetic.
"""
@enum NumKind::UInt8 NUM_NONE NUM_INTEGER NUM_RATIONAL NUM_FLOAT

@doc "Not a number: a variable, a symbol, a compound, or a grounded value of another kind." NUM_NONE
@doc "An integer, of any size." NUM_INTEGER
@doc "A rational number that is not an integer." NUM_RATIONAL
@doc "A float (an IEEE double; narrower IEEE floats widen exactly)." NUM_FLOAT

"""
    number_kind(t) -> NumKind

The [`NumKind`](@ref) of `t`. Callers branch ONCE on it and then call the one typed getter that
kind has — [`int64_value`](@ref)/[`bigint_value`](@ref), [`rational_value`](@ref),
[`float_value`](@ref) — so everything after the branch is type-stable.
"""
function number_kind end

"""
    integer_is_int64(t) -> Bool

Whether `t` is an integer that fits an `Int64` — the small-integer path ([`int64_value`](@ref)).
"""
function integer_is_int64 end

"""
    int64_value(t) -> Int64

The value of an integer that fits an `Int64`; an `InexactError` for a larger one, an
`ArgumentError` for any other term.
"""
function int64_value end

"""
    bigint_value(t) -> BigInt

The value of an integer of any size; an `ArgumentError` for any other term.
"""
function bigint_value end

"""
    rational_value(t) -> Rational{BigInt}

The value of a [`NUM_RATIONAL`](@ref); an `ArgumentError` for any other term.
"""
function rational_value end

"""
    float_value(t) -> Float64

The value of a [`NUM_FLOAT`](@ref), bit for bit (`-0.0` and NaN payloads kept); an `ArgumentError`
for any other term.
"""
function float_value end

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
