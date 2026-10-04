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
#   |                                           |   and per ARITY for compounds (`AltExpr{H, N}`)    |
#   | `sym_key`: the `Symbol`'s address         | `sym_key`: an interned integer id, counting from 0 |
#   | `sym_hash`: `objectid` of the `Symbol`    | `sym_hash`: FNV-1a of the name's UTF-8 bytes       |
#   | a reserved symbol: a flag on the struct   | a reserved symbol: a LEAF TYPE of its own          |
#   |                                           |   (`AltRSym`), so no kernel site may assume every  |
#   |                                           |   symbol has one leaf type                         |
#   | children in a `Vector{Term{G}}`           | children in an `NTuple{N}`, in a `mutable struct`  |
#   |                                           |   (`===` on compounds must be constant-time; on a  |
#   |                                           |   plain tuple VALUE it walks the children)         |
#   | every `mk_expr` a new compound            | `AltTerm{true}` SHARES ground compounds: a struc-  |
#   |                                           |   turally identical ground compound is returned as |
#   |                                           |   the SAME object (hash-consing)                   |
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
# TWO TERM TYPES, `AltTerm{H}`: `AltTerm{false}` (selector `alt`) builds a new compound on every
# `mk_expr`; `AltTerm{true}` (selector `alt_interned`) interns GROUND compounds, so equal ground
# subterms are one object — the sharing SWI's own terms have (`copy_term/2` shares ground subterms
# with the original, pl-copyterm.c), proven safe for the kernel before pl-copyterm.c is ported (user,
# 2026-10-03). Two types, not a switch: a run of one can never leak into the other.
#
# Loaded ONCE per process, into `Main`, by test/term_under_test.jl.
module LKAltTerm

# Revise mode for the warm lane, which loads this file with `includet`: its default there,
# `:evalmeth`, revises METHOD definitions only, so an edited struct or constant here would stay
# stale; `:eval` re-evaluates every changed expression (unchanged ones, the intern tables below
# included, are left alone).
__revise_mode__ = :eval

using LogicKernel
import LogicKernel:
    kind, term_type, nchildren, child, sym_key, sym_hash, var_key, gnd_key, gnd_equal,
    atomic_compare, mk_var, mk_expr, mk_sym, mk_gnd, mk_reserved_symbol, is_reserved_symbol,
    is_nil, is_pair, number_kind, integer_is_int64, int64_value, bigint_value,
    rational_value,
    float_value

export AltTerm, alt_sym, alt_gnd, alt_var, alt_name, alt_value, alt_stats

"""
The second implementation's term types: ABSTRACT, so every term's `typeof` is a leaf. `H`: whether
ground compounds are shared (interned).
"""
abstract type AltTerm{H} end

struct AltVar{H} <: AltTerm{H}
    key::UInt64
end

struct AltSym{H} <: AltTerm{H}
    id::UInt32                       # an index into _NAMES, from 0
end

"A reserved symbol (SWI-7's `[]`, pl-ressymbol.c): a SYM, as `AltSym` is, of another leaf type."
struct AltRSym{H} <: AltTerm{H}
    id::UInt32                       # an index into _NAMES — shared with the text atoms
end

struct AltGnd{H} <: AltTerm{H}
    val::Any                         # boxed, on purpose
end

# ONE LEAF TYPE PER ARITY: with a single compound leaf, a kernel container that holds only
# compounds still worked when built from `typeof(t)` — a mutation reverting `do_compare` to
# `typeof` SURVIVED (2026-10-03). With the arity in the type, two compounds of different arities
# are two leaves, so every `typeof` site breaks.
# MUTABLE, though never mutated: `===` on compounds must be constant-time (src/term_interface.jl).
# As a plain immutable struct, `===` and `objectid` walked the children — exponential on shared
# subterms, and the live unification differential never finished (2026-10-03).
mutable struct AltExpr{H, N} <: AltTerm{H}
    const kids::NTuple{N, AltTerm{H}}
end

# ── the intern tables ────────────────────────────────────────────────────────────────────────────
const _NAMES = Symbol[]
const _IDS = Dict{Symbol, UInt32}()
const _LOCK = ReentrantLock()

"The symbol `name`, interned: separately built twins share an id."
function alt_sym(::Type{AltTerm{H}}, name::Symbol)::AltSym{H} where {H}
    id = lock(_LOCK) do
        get!(_IDS, name) do
            push!(_NAMES, name)
            UInt32(length(_NAMES) - 1)
        end
    end
    return AltSym{H}(id)
end

"The name of a symbol (the reference type's `sym_name`)."
alt_name(t::Union{AltSym, AltRSym})::Symbol = lock(() -> _NAMES[t.id + 1], _LOCK)

"The reserved symbol `name`: the text atom's id, in its own leaf type."
alt_rsym(::Type{AltTerm{H}}, name::Symbol) where {H} =
    AltRSym{H}(alt_sym(AltTerm{H}, name).id)

"The grounded value `v`, boxed."
alt_gnd(::Type{AltTerm{H}}, v) where {H} = AltGnd{H}(v)

"The host value of a grounded term (the reference type's `gnd_value`)."
alt_value(t::AltGnd) = t.val

"A CALLER's variable — checked, as the reference type's `var_term`: the top half is the kernel's."
function alt_var(::Type{AltTerm{H}}, key::UInt64)::AltVar{H} where {H}
    key < KERNEL_VAR_BASE || throw(
        ArgumentError(
            "alt_var: key $(repr(key)) is in the kernel's half of the key space (≥ 2^63)"
        )
    )
    return AltVar{H}(key)
end

# ── the term interface ───────────────────────────────────────────────────────────────────────────
kind(::AltVar) = VAR
kind(::AltSym) = SYM
kind(::AltRSym) = SYM
kind(::AltGnd) = GND
kind(::AltExpr) = EXPR
term_type(::AltTerm{H}) where {H} = AltTerm{H}  # the abstract type, never the leaf

nchildren(::AltTerm) = 0
nchildren(t::AltExpr) = length(t.kids)
child(t::AltExpr, i::Int) = t.kids[i]

sym_key(t::AltSym) = UInt64(t.id)
sym_key(t::AltRSym) = UInt64(t.id) | (UInt64(1) << 40)  # another symbol than the text atom
sym_hash(t::Union{AltSym, AltRSym}) = _fnv1a(String(alt_name(t)))   # the TEXT hash, both
var_key(t::AltVar) = t.key
gnd_key(t::AltGnd) = _gnd_key(t.val)
gnd_equal(a::AltGnd, b::AltGnd) = atomic_compare(a, b) == 0

# ── the Prolog layer (Q1) ────────────────────────────────────────────────────────────────────────
mk_sym(::Type{AltTerm{H}}, name::Symbol) where {H} = alt_sym(AltTerm{H}, name)
mk_gnd(::Type{AltTerm{H}}, v) where {H} = alt_gnd(AltTerm{H}, v)
mk_reserved_symbol(::Type{AltTerm{H}}, name::Symbol) where {H} = alt_rsym(AltTerm{H}, name)
is_reserved_symbol(::AltTerm) = false
is_reserved_symbol(::AltRSym) = true
is_nil(::AltTerm) = false
is_nil(t::AltRSym) = alt_name(t) === Symbol("[]")
is_pair(::AltTerm) = false
is_pair(t::AltExpr{H, 3}) where {H} =
    (h=t.kids[1]; h isa AltSym && alt_name(h) === Symbol("[|]"))

number_kind(::AltTerm) = NUM_NONE
function number_kind(t::AltGnd)
    v = t.val
    v isa Integer && !(v isa Bool) && return NUM_INTEGER
    v isa Rational && return NUM_RATIONAL
    v isa Base.IEEEFloat && return NUM_FLOAT
    return NUM_NONE
end
integer_is_int64(t::AltTerm) =
    number_kind(t) === NUM_INTEGER && typemin(Int64) <= t.val <= typemax(Int64)
_need(t::AltTerm, k::NumKind, what) =
    number_kind(t) === k ||
    throw(ArgumentError("$what: not a $(lowercase(string(k)[5:end]))"))
int64_value(t::AltTerm) = (_need(t, NUM_INTEGER, "int64_value"); Int64(t.val))
bigint_value(t::AltTerm) = (_need(t, NUM_INTEGER, "bigint_value"); BigInt(t.val))
rational_value(t::AltTerm) =
    (_need(t, NUM_RATIONAL, "rational_value"); Rational{BigInt}(t.val))
float_value(t::AltTerm) = (_need(t, NUM_FLOAT, "float_value"); Float64(t.val))

# Only the term type itself: a kernel that passes a LEAF type (`typeof(t)`) finds no method.
mk_var(::Type{AltTerm{H}}, key::UInt64) where {H} = AltVar{H}(key)
mk_expr(::Type{AltTerm{false}}, children::Vector{AltTerm{false}}) = _new_expr(children)
function mk_expr(::Type{AltTerm{true}}, children::Vector{AltTerm{true}})
    all(_shareable, children) || return _new_expr(children)
    h = _share_hash(children)
    return lock(_LOCK) do
        bucket = get!(() -> AltExpr{true}[], _SHARED, h)
        for e in bucket
            if _same_children(e, children)
                _STATS[:shared] += 1
                return e
            end
        end
        e = _new_expr(children)
        push!(bucket, e)
        _INTERNED[e] = nothing
        return e
    end
end

function _new_expr(children::Vector{AltTerm{H}}) where {H}
    N = length(children)
    lock(() -> _STATS[H ? :compounds_interned : :compounds_plain] += 1, _LOCK)
    return AltExpr{H, N}(NTuple{N, AltTerm{H}}(children))
end

# ── sharing (AltTerm{true}): a ground compound is built once ─────────────────────────────────────
const _SHARED = Dict{UInt64, Vector{AltExpr{true}}}()    # structural hash → the ground compounds
const _INTERNED = IdDict{AltExpr{true}, Nothing}()       # every shared compound — all are ground
const _STATS = Dict(:compounds_plain => 0, :compounds_interned => 0, :shared => 0)

"How many compounds each type built, and how often `AltTerm{true}` returned an existing one."
alt_stats() = lock(_LOCK) do
    (compounds_plain=_STATS[:compounds_plain],
        compounds_interned=_STATS[:compounds_interned],
        shared=_STATS[:shared])
end

"Ground, decided in O(1): atomic, or a compound in the intern table (only ground ones get in)."
_shareable(c::AltTerm{true}) =
    if kind(c) === VAR
        false
    else
        (kind(c) === EXPR ? lock(() -> haskey(_INTERNED, c), _LOCK) : true)
    end

_share_key(c::Union{AltSym, AltRSym}) = (0x1, sym_key(c))
_share_key(c::AltGnd) = (0x2, something(_gnd_key(c.val), UInt64(0)))   # a WILDCARD buckets at 0
_share_key(c::AltExpr) = (0x3, UInt64(objectid(c)))                     # children are shared too
_share_hash(children) =
    foldl((h, c) -> hash(_share_key(c), h), children; init=hash(length(children)))

"Identical children: shared compounds by `===`, symbols by id, grounded values by SWI's identity."
function _same_children(e::AltExpr, children)::Bool
    length(e.kids) == length(children) || return false
    for (a, b) in zip(e.kids, children)
        kind(a) === kind(b) || return false
        if kind(a) === EXPR
            a === b || return false
        elseif kind(a) === SYM
            sym_key(a) == sym_key(b) || return false    # NOT the id: `[]` and '[]' share one
        else
            atomic_compare(a, b) == 0 || return false
        end
    end
    return true
end

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

_rank(::Union{AltSym, AltRSym}) = _ATOM
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
    ra == _ATOM &&
        return compareAtoms(alt_name(a), a isa AltRSym, alt_name(b), b isa AltRSym)
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
Base.show(io::IO, t::AltSym) =
    alt_name(t) === Symbol("[]") ? print(io, "'[]'") : print(io, alt_name(t))
Base.show(io::IO, t::AltRSym) = print(io, alt_name(t))
Base.show(io::IO, t::AltGnd) = show(io, t.val)
function Base.show(io::IO, t::AltExpr)
    print(io, "(")
    join(io, (sprint(show, c) for c in t.kids), " ")
    print(io, ")")
    return nothing
end

end # module LKAltTerm
