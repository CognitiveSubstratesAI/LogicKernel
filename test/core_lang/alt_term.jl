# ORIGINAL: a SECOND implementation of the term interface, deliberately unlike Term{G}; Prolog has one term representation, so there is nothing upstream to port.
# test/core_lang/alt_term.jl — `AltTerm`, the second implementation (user, 2026-10-03).
#
# ITS JOB IS TO DIFFER. The interface was settled with one implementation, so anything `Term{G}`
# happens to do could have become part of the interface without anyone deciding it. Every
# representation choice here is the opposite of the reference type's, on purpose:
#
#   | `Term{G}` (src/default_term.jl)           | `AltTerm` (here)                                   |
#   |-------------------------------------------|----------------------------------------------------|
#   | ONE concrete struct with a kind tag       | an ABSTRACT type with a concrete leaf per kind —   |
#   |                                           |   and per ARITY for compounds (`AltExpr{N}`)       |
#   | `sym_key`: the `Symbol`'s address         | `sym_key`: an interned integer id, counting from 0 |
#   | `sym_hash`: `objectid` of the `Symbol`    | `sym_hash`: FNV-1a of the name's UTF-8 bytes       |
#   | children in a `Vector{Term{G}}`           | children in an `NTuple{N}`, in a `mutable struct`: |
#   |                                           |   the interface requires a compound to have object |
#   |                                           |   identity, and a plain tuple VALUE has none       |
#   | the value in `Union{Nothing, G}`          | the value BOXED (an `Any` field); any host value   |
#   | `gnd_key` for integers, floats, rationals,| `gnd_key` for integers (by decimal text), IEEE     |
#   |   strings, chars, symbols and booleans    |   floats (by bits), rationals and strings — every- |
#   |                                           |   thing else is a WILDCARD                         |
#   | `is_ground` cached at construction        | `is_ground` walks (the interface's default)        |
#   | `==` and `hash` follow the standard order | `==` and `hash` THROW: code that compares or       |
#   |                                           |   hashes terms outside the interface fails loudly  |
#   |                                           |   (Base's `===` fallback would pass by accident    |
#   |                                           |   wherever the payload happens to be bits)         |
#
# 🔴 A CORRECTNESS VEHICLE, NOT A PERFORMANCE ONE (user, 2026-10-03). It dispatches at run time,
# boxes every value and allocates freely. The zero-dispatch JET gate (test/test_static_analysis.jl)
# and the AllocCheck manifest apply to the REFERENCE type only. Do not "fix" this into a copy of
# `Term{G}`: each difference above is what lets it find where the interface is quietly shaped by
# the reference type.
#
# What it shares with `Term{G}` is SEMANTICS, never representation: SWI's identity for grounded
# values and SWI's standard order, built from the kernel's ports of SWI's leaf comparisons.
#
# The intern table is module state. That is allowed here because this is test code: the kernel's
# no-module-state contract, and the lint enforcing it, cover the `LogicKernel` module.
#
# Loaded ONCE per process, into `Main`, by test/term_under_test.jl.
module LKAltTerm

using LogicKernel
import LogicKernel:
    kind, term_type, nchildren, child, sym_key, sym_hash, var_key, gnd_key, gnd_equal,
    atomic_compare, mk_var, mk_expr

export AltTerm, alt_sym, alt_gnd, alt_var, alt_name, alt_value

"The second implementation's term type: ABSTRACT, so every term's `typeof` is one of four leaves."
abstract type AltTerm end

struct AltVar <: AltTerm
    key::UInt64
end

struct AltSym <: AltTerm
    id::UInt32                       # an index into _NAMES, from 0
end

struct AltGnd <: AltTerm
    val::Any                         # boxed, on purpose
end

# ONE LEAF TYPE PER ARITY: with a single compound leaf, a kernel container that holds only
# compounds still worked when built from `typeof(t)` — a mutation reverting `do_compare` to
# `typeof` SURVIVED (2026-10-03). With the arity in the type, two compounds of different arities
# are two leaves, so every `typeof` site breaks.
# MUTABLE, though never mutated: a compound must have object identity (src/term_interface.jl). As a
# plain immutable struct, `===` and `objectid` walked the children — exponential on shared subterms,
# and the live unification differential never finished (2026-10-03).
mutable struct AltExpr{N} <: AltTerm
    const kids::NTuple{N, AltTerm}
end

# ── the intern table ─────────────────────────────────────────────────────────────────────────────
const _NAMES = Symbol[]
const _IDS = Dict{Symbol, UInt32}()
const _LOCK = ReentrantLock()

"The symbol `name`, interned: separately built twins share an id."
function alt_sym(name::Symbol)::AltSym
    id = lock(_LOCK) do
        get!(_IDS, name) do
            push!(_NAMES, name)
            UInt32(length(_NAMES) - 1)
        end
    end
    return AltSym(id)
end

"The name of a symbol (the reference type's `sym_name`)."
alt_name(t::AltSym)::Symbol = lock(() -> _NAMES[t.id + 1], _LOCK)

"The grounded value `v`, boxed."
alt_gnd(v)::AltGnd = AltGnd(v)

"The host value of a grounded term (the reference type's `gnd_value`)."
alt_value(t::AltGnd) = t.val

"A CALLER's variable — checked, as the reference type's `var_term`: the top half is the kernel's."
function alt_var(key::UInt64)::AltVar
    key < KERNEL_VAR_BASE || throw(
        ArgumentError(
            "alt_var: key $(repr(key)) is in the kernel's half of the key space (≥ 2^63)"
        )
    )
    return AltVar(key)
end

# ── the term interface ───────────────────────────────────────────────────────────────────────────
kind(::AltVar) = VAR
kind(::AltSym) = SYM
kind(::AltGnd) = GND
kind(::AltExpr) = EXPR
term_type(::AltTerm) = AltTerm                  # the abstract type, never the leaf

nchildren(::AltTerm) = 0
nchildren(t::AltExpr) = length(t.kids)
child(t::AltExpr, i::Int) = t.kids[i]

sym_key(t::AltSym) = UInt64(t.id)
sym_hash(t::AltSym) = _fnv1a(String(alt_name(t)))
var_key(t::AltVar) = t.key
gnd_key(t::AltGnd) = _gnd_key(t.val)
gnd_equal(a::AltGnd, b::AltGnd) = atomic_compare(a, b) == 0

# Only the term type itself: a kernel that passes a LEAF type (`typeof(t)`) finds no method.
mk_var(::Type{AltTerm}, key::UInt64) = AltVar(key)
mk_expr(::Type{AltTerm}, children::Vector{AltTerm}) =
    AltExpr{length(children)}(NTuple{length(children), AltTerm}(children))

"FNV-1a, 64-bit — a process-independent hash of a name, unlike the reference's `objectid`."
function _fnv1a(s::String)::UInt64
    h = 0xcbf29ce484222325
    for b in codeunits(s)
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return h
end

"""
A grounded key that follows SWI's identity: identical values never key apart. Integers by their
decimal text (`2` and `big(2)` are identical in SWI), IEEE floats by type and bits (`0.0` and
`-0.0` differ), rationals by value, strings by text. Everything else is a WILDCARD.
"""
function _gnd_key(v)::Union{UInt64, Nothing}
    if v isa Integer && !(v isa Bool)
        return UInt64(hash(string(v), UInt(1)))
    elseif v isa Base.IEEEFloat
        return UInt64(hash(reinterpret(Unsigned, v), hash(typeof(v), UInt(2))))
    elseif v isa Rational
        return UInt64(hash((numerator(v), denominator(v)), UInt(3)))
    elseif v isa AbstractString
        return UInt64(hash(String(v), UInt(4)))
    end
    return nothing
end

# ── SWI's atomic order: Number < String < Atom, then values Prolog has no counterpart for ─────────
const _NUMBER, _STRING, _ATOM, _OTHER = 1, 2, 3, 4

_rank(::AltSym) = _ATOM
function _rank(t::AltGnd)::Int
    v = t.val
    v isa Real && !(v isa Bool) && return _NUMBER
    v isa AbstractString && return _STRING
    return _OTHER
end

_sgn(x::Integer)::Int = x < 0 ? -1 : (x > 0 ? 1 : 0)
_by_type(x, y)::Int = _sgn(cmp(string(typeof(x)), string(typeof(y))))

function atomic_compare(a::AltTerm, b::AltTerm)::Int
    ra, rb = _rank(a), _rank(b)
    ra != rb && return ra < rb ? -1 : 1
    ra == _ATOM && return compareAtoms(alt_name(a), alt_name(b))
    x, y = (a::AltGnd).val, (b::AltGnd).val
    ra == _NUMBER && return _compare_numbers(x, y)
    if ra == _STRING
        c = compareStrings(x, y)
        return c != 0 ? c : (typeof(x) === typeof(y) ? 0 : _by_type(x, y))
    end
    typeof(x) === typeof(y) || return _by_type(x, y)
    isequal(x, y) && return 0
    c = _sgn(cmp(repr(x), repr(y)))
    return c != 0 ? c : _sgn(cmp(hash(x), hash(y)))
end

function _compare_numbers(x::Real, y::Real)::Int
    xf, yf = x isa AbstractFloat, y isa AbstractFloat
    if xf && yf
        typeof(x) === typeof(y) &&
            return x === y ? 0 : compare_neq_floats(x, y)
        # two float types (Float32 against Float64): no SWI counterpart — by value, then by type
        fx, fy = Float64(x), Float64(y)
        return fx === fy ? _by_type(x, y) : compare_neq_floats(fx, fy)
    elseif xf != yf
        return compare_mixed_float_rational(x, y)
    end
    x < y && return -1
    x > y && return 1
    x isa Integer && y isa Integer && return 0          # SWI has one integer type
    return typeof(x) === typeof(y) ? 0 : _by_type(x, y)
end

# ── no identity outside the interface ────────────────────────────────────────────────────────────
Base.:(==)(::AltTerm, ::AltTerm) = error(
    "AltTerm: `==` on terms — compare through the interface (`compareStandard(a, b, true) == 0`)"
)
Base.hash(::AltTerm, ::UInt) =
    error("AltTerm: `hash` on terms — hash through the interface")

# ── printing, for failure messages only ──────────────────────────────────────────────────────────
Base.show(io::IO, t::AltVar) = print(io, "_A", t.key)
Base.show(io::IO, t::AltSym) = print(io, alt_name(t))
Base.show(io::IO, t::AltGnd) = show(io, t.val)
function Base.show(io::IO, t::AltExpr)
    print(io, "(")
    join(io, (sprint(show, c) for c in t.kids), " ")
    print(io, ")")
    return nothing
end

end # module LKAltTerm
