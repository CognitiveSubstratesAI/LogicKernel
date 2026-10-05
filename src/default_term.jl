# ORIGINAL: the default term type — the reference implementation of the term interface; SWI's terms are tagged cells, not a Julia struct.
#
# ONE CONCRETE STRUCT WITH A KIND TAG, not an abstract hierarchy (user, 2026-10-02): an abstract
# `Term` with four subtypes makes every walk dispatch at runtime and boxes every element of a
# `Vector{Term}`. `Term{G}` is concrete for every grounded payload type `G`, so the interface
# functions compile to field reads. `G` is a type PARAMETER, not `Any`: a payload set is named
# explicitly — `Term{Float64}`, `Term{Union{Int64, Float64, String}}` ([`DefaultTerm`](@ref)),
# `Term{Vector{Float64}}`.

"""
    Term{G}

The default term type: one concrete struct with a [`Kind`](@ref) tag, whose grounded values are of
type `G` (a concrete type or a small `Union`). Build terms with [`sym_term`](@ref),
[`gnd_term`](@ref), [`mk_var`](@ref) and [`mk_expr`](@ref); read them through the term interface.

`==` and `hash` follow IDENTITY in the standard order ([`compareStandard`](@ref) `== 0`), and so does
[`gnd_equal`](@ref), as in SWI-Prolog: `1` and `1.0` are different terms and do not unify.
"""
struct Term{G}
    kind::Kind
    ground::Bool                     # no variable anywhere below — cached at construction
    keyed::Bool                      # GND: `key` holds a grounded key (else WILDCARD)
    reserved::Bool                   # SYM: a RESERVED symbol (SWI-7's `[]`, pl-ressymbol.c)
    key::UInt64                      # VAR: var key · SYM: sym key · GND: grounded key · EXPR: 0
    name::Symbol                     # SYM: the symbol · otherwise Symbol("")
    gval::Union{Nothing, G}          # GND: the value · otherwise nothing
    children::Vector{Term{G}}        # EXPR: the children, head first · otherwise empty
end

"""
    DefaultTerm

`Term{Union{Int64, Float64, String}}` — integers, floats and strings, the atomic values every
Prolog has. A small enough union that the compiler keeps every field access branch-free.
"""
const DefaultTerm = Term{Union{Int64, Float64, String}}

"The seed integers key with, so an integer and the float of the same value key apart."
const _INTEGER_KEY_SEED = UInt(0x5d1e9f6b3c2a8471)

"""
    gnd_value_key(v) -> Union{UInt64, Nothing}

A grounded key for a host value that agrees with SWI's IDENTITY — the reference type's
[`gnd_equal`](@ref) — so identical values never key apart. Integers key by value, as SWI has one
integer type (`5` and `big(5)` key alike); floats, rationals, strings, characters, symbols and
booleans key by their type and `hash`, which agrees with `isequal` — so `1` and `1.0`, and `0.0` and
`-0.0`, key apart, as they unify apart. Everything else is `nothing` (WILDCARD): a container or a
custom type need not keep `hash` consistent with how it compares. An implementation matching by `==`
(Core's MeTTa terms) needs a key that follows `==` instead.
"""
function gnd_value_key(v)::Union{UInt64, Nothing}
    if v isa Integer && !(v isa Bool)
        return UInt64(hash(v, _INTEGER_KEY_SEED))
    elseif v isa AbstractFloat || v isa Rational || v isa AbstractString ||
        v isa AbstractChar || v isa Symbol || v isa Bool
        return UInt64(hash(v, hash(typeof(v))))
    end
    return nothing
end

# SWI's canonical rationals (user, 2026-10-04; swipl 10.1.16 reads `2r1` as `2`): a `Rational` with
# denominator 1 IS the integer. Stored as an integer type the payload `G` holds — the numerator's own
# type, else Int64 when it fits, else BigInt — and refused when `G` holds none: a payload that can
# hold such a rational must be able to hold the integer it is.
_canonical_gnd(::Type{G}, v) where {G} = v
function _canonical_gnd(::Type{G}, v::Rational) where {G}
    denominator(v) == 1 || return v
    n = numerator(v)
    typeof(n) <: G && return n
    Int64 <: G && typemin(Int64) <= n <= typemax(Int64) && return Int64(n)
    BigInt <: G && return BigInt(n)
    throw(
        ArgumentError(
            "gnd_term: $v is the integer $n (SWI's canonical form), and the payload $G holds " *
            "no integer type to store it in"
        )
    )
end

_sym_key(s::Symbol)::UInt64 = UInt64(UInt(pointer_from_objref(s)))
# A reserved symbol is another symbol than the text atom of its name: the same address with the low
# bit set — an interned `Symbol` is word-aligned, so no text atom's key has that bit.
_reserved_sym_key(s::Symbol)::UInt64 = _sym_key(s) | UInt64(1)

"""
    _no_children(::Type{Term{G}}) -> Vector{Term{G}}

The ONE empty child vector of `Term{G}`, which every variable, symbol and grounded value shares — so
a leaf allocates nothing (user, 2026-10-05: an empty vector per fresh variable was 20% of nreverse).
NOTHING may mutate it: a leaf's children are read only through [`nchildren`](@ref) and
[`child`](@ref). test/core_lang/test_default_term.jl asserts the sharing, and test/runtests.jl that
it is still empty after every unit. Generated, so each term type has its own object, made when the
method is compiled.
"""
@generated _no_children(::Type{Term{G}}) where {G} = QuoteNode(Term{G}[])

"""
    sym_term(::Type{Term{G}}, name::Symbol) -> Term{G}

The symbol `name`.
"""
sym_term(::Type{Term{G}}, name::Symbol) where {G} =
    Term{G}(SYM, true, false, false, _sym_key(name), name, nothing, _no_children(Term{G}))

"""
    gnd_term(::Type{Term{G}}, v::G) -> Term{G}

The grounded value `v`, CANONICAL — a `Rational` with denominator 1 is stored as the integer, in an
integer type `G` holds (see [`mk_gnd`](@ref)); its [`gnd_key`](@ref) is computed here, once.
"""
function gnd_term(::Type{Term{G}}, v::G) where {G}
    v = _canonical_gnd(G, v)
    k = gnd_value_key(v)
    return Term{G}(
        GND, true, k !== nothing, false, k === nothing ? UInt64(0) : k, Symbol(""), v,
        _no_children(Term{G})
    )
end

mk_var(::Type{Term{G}}, key::UInt64) where {G} =
    Term{G}(VAR, false, false, false, key, Symbol(""), nothing, _no_children(Term{G}))

"""
    var_term(::Type{Term{G}}, key::UInt64) -> Term{G}

A CALLER's variable: [`mk_var`](@ref) for a key below [`KERNEL_VAR_BASE`](@ref), which it checks —
the top half of the key space is the kernel's (see [`var_key`](@ref)).
"""
function var_term(::Type{Term{G}}, key::UInt64) where {G}
    key < KERNEL_VAR_BASE || throw(
        ArgumentError(
            "var_term: key $(repr(key)) is in the kernel's half of the key space (≥ 2^63)"
        )
    )
    return mk_var(Term{G}, key)
end

function mk_expr(::Type{Term{G}}, children::Vector{Term{G}}) where {G}
    ground = true
    for c in children
        c.ground || (ground=false; break)
    end
    return Term{G}(EXPR, ground, false, false, UInt64(0), Symbol(""), nothing, children)
end

# ── the Prolog layer (src/term_interface.jl, Q1) ─────────────────────────────────────────────────
mk_sym(::Type{Term{G}}, name::Symbol) where {G} = sym_term(Term{G}, name)
mk_gnd(::Type{Term{G}}, v::G) where {G} = gnd_term(Term{G}, v)
mk_reserved_symbol(::Type{Term{G}}, name::Symbol) where {G} =
    Term{G}(
        SYM, true, false, true, _reserved_sym_key(name), name, nothing,
        _no_children(Term{G})
    )
is_reserved_symbol(t::Term)::Bool = t.kind === SYM && t.reserved
is_nil(t::Term)::Bool = t.kind === SYM && t.reserved && t.name === NIL_NAME
function is_pair(t::Term)::Bool
    (t.kind === EXPR && length(t.children) == 3) || return false
    h = t.children[1]
    return h.kind === SYM && !h.reserved && h.name === LIST_CONS_NAME
end

# A grounded value's kind follows its host type: `Integer` (not `Bool`), `Rational`, an IEEE float,
# `AbstractString`. Every other payload — a `Bool`, a `BigFloat`, a container — is NUM_OTHER.
function number_kind(t::Term)::NumKind
    t.kind === GND || return NUM_NONE
    v = t.gval
    v isa Integer && !(v isa Bool) && return NUM_INTEGER
    v isa Rational && return NUM_RATIONAL
    v isa Base.IEEEFloat && return NUM_FLOAT
    v isa AbstractString && return NUM_STRING
    return NUM_OTHER
end
function string_value(t::Term)::String
    v = t.gval
    if t.kind === GND && v isa AbstractString                 # an `if`, so `v` narrows
        return String(v)
    end
    throw(ArgumentError("string_value: not a string"))
end
function integer_is_int64(t::Term)::Bool
    t.kind === GND || return false
    v = t.gval
    return v isa Integer && !(v isa Bool) && typemin(Int64) <= v <= typemax(Int64)
end
function int64_value(t::Term)::Int64
    v = t.gval
    if t.kind === GND && v isa Integer && !(v isa Bool)                    # an `if`, so `v` narrows (JET, 2026-10-04)
        return Int64(v)
    end
    throw(ArgumentError("int64_value: not an integer"))
end
function bigint_value(t::Term)::BigInt
    v = t.gval
    if t.kind === GND && v isa Integer && !(v isa Bool)                    # an `if`, so `v` narrows (JET, 2026-10-04)
        return BigInt(v)
    end
    throw(ArgumentError("bigint_value: not an integer"))
end
function rational_value(t::Term)::Rational{BigInt}
    v = t.gval
    if t.kind === GND && v isa Rational                    # an `if`, so `v` narrows (JET, 2026-10-04)
        return Rational{BigInt}(v)
    end
    throw(ArgumentError("rational_value: not a rational"))
end
function float_value(t::Term)::Float64
    v = t.gval
    if t.kind === GND && v isa Base.IEEEFloat                    # an `if`, so `v` narrows (JET, 2026-10-04)
        return Float64(v)
    end
    throw(ArgumentError("float_value: not a float"))
end

"""
    sym_name(t::Term) -> Symbol

The name of a [`SYM`](@ref) term. Not part of the term interface — the kernel never needs names —
but a CLIENT of the default type does: printing, and recognising a functor without building one.
Found by the standalone consumer (test/test_standalone_consumer.jl), which could not otherwise read a
symbol through the public API.
"""
sym_name(t::Term)::Symbol = t.name

"""
    gnd_value(t::Term{G}) -> G

The host value of a [`GND`](@ref) term. Not part of the term interface — the kernel compares
grounded values only through [`gnd_equal`](@ref) — but a CLIENT computing with them (arithmetic in
the benchmark programs) must read them. Throws a `TypeError` on a non-`GND` term.
"""
gnd_value(t::Term{G}) where {G} = t.gval::G

kind(t::Term)::Kind = t.kind
term_type(::Term{G}) where {G} = Term{G}
nchildren(t::Term)::Int = length(t.children)
child(t::Term{G}, i::Int) where {G} = t.children[i]
sym_key(t::Term)::UInt64 = t.key
# An interned Symbol's `objectid` is computed from its NAME (measured equal across processes, while
# its address differs) — so it is stable for a given Julia version, and allocates nothing.
sym_hash(t::Term)::UInt64 = UInt64(objectid(t.name))
var_key(t::Term)::UInt64 = t.key
gnd_key(t::Term)::Union{UInt64, Nothing} = t.keyed ? t.key : nothing
is_ground(t::Term)::Bool = t.ground
# SWI's unification of atomic data: identical or nothing (pl-prims.c `unify_simple_ptrs`: `w1 == w2`,
# or `equalIndirect` on the bits of an indirect).
gnd_equal(a::Term{G}, b::Term{G}) where {G} = atomic_compare(a, b) == CMP_EQUAL

# ── atomic order: SWI's tag ladder, extended for Julia values Prolog does not have ───────────────
# Number (integer and float tags, compared jointly by value) < String < other < Atom. DIVERGES from
# SWI, which has no "other" (user, 2026-10-04): a grounded value of no SWI type — Bool, Char,
# BigFloat, containers, custom types — sorts as SWI's NON-TEXT BLOBS do (`OTHER_BLOB_RANK`, below
# the reserved symbols' and the text atoms' ranks): after every string, before `[]` and every text
# atom. The order of anything SWI can represent is untouched.
const _RANK_NUMBER = 1
const _RANK_STRING = 2
const _RANK_OTHER = 3
const _RANK_ATOM = 4

# The standard order's class of an atomic term, from the ONE kind query (user, 2026-10-04: one place
# for a grounded value's Prolog type) — before, a `Real` such as a `BigFloat` ranked as a number here
# while `number_kind` called it no number.
function _atomic_rank(t::Term)::Int
    t.kind === SYM && return _RANK_ATOM
    k = number_kind(t)
    (k === NUM_INTEGER || k === NUM_RATIONAL || k === NUM_FLOAT) && return _RANK_NUMBER
    k === NUM_STRING && return _RANK_STRING
    return _RANK_OTHER
end

"Tie-break between identical-looking values of different host types (`Int32(1)` vs `Int64(1)`)."
_cmp_types(Tx::Type, Ty::Type)::Int = _sign(cmp(string(Tx), string(Ty)))

function _compare_numbers(x::Real, y::Real)::Int
    xf, yf = x isa AbstractFloat, y isa AbstractFloat
    if xf && yf
        typeof(x) === typeof(y) && x === y && return CMP_EQUAL      # bit-identical
        if typeof(x) === typeof(y)
            return compare_neq_floats(x, y)
        end
        (isnan(x) || isnan(y)) &&
            return if isnan(x)
                (isnan(y) ? _cmp_types(typeof(x), typeof(y)) : CMP_LESS)
            else
                CMP_GREATER
            end
        x < y && return CMP_LESS
        x > y && return CMP_GREATER
        return _cmp_types(typeof(x), typeof(y))
    elseif xf != yf
        return compare_mixed_float_rational(x, y)
    end
    x < y && return CMP_LESS
    x > y && return CMP_GREATER
    x isa Integer && y isa Integer && return CMP_EQUAL      # one integer type, as in SWI
    return typeof(x) === typeof(y) ? CMP_EQUAL : _cmp_types(typeof(x), typeof(y))
end

function _compare_strings(x::AbstractString, y::AbstractString)::Int
    c = compareStrings(x, y)
    c != CMP_EQUAL && return c
    return typeof(x) === typeof(y) ? CMP_EQUAL : _cmp_types(typeof(x), typeof(y))
end

# FUNCTION BARRIER: `x == y` on two `Union{Nothing, G…}` values is a 4×4 = 16-way call — past the
# compiler's union-splitting limit (4). One union value plus the other TERM, so `y isa X` narrows `y`
# to the now-concrete type of `x` and every call below is static (JET enforces it).
function _compare_other(x::X, b::Term)::Int where {X}
    y = b.gval
    y isa X || return _cmp_types(X, typeof(y))
    isequal(x, y) && return CMP_EQUAL
    c = _sign(cmp(repr(x), repr(y)))
    c != CMP_EQUAL && return c
    return _sign(cmp(hash(x), hash(y)))                # distinct values with one repr: by hash
end

"""
    atomic_compare(a::Term{G}, b::Term{G}) -> Int

The reference atomic order: SWI-Prolog's — numbers by value with the float first on a tie, then
strings, then atoms, by character codes — and after atoms, values Prolog has no counterpart for.
"""
function atomic_compare(a::Term{G}, b::Term{G})::Int where {G}
    ra, rb = _atomic_rank(a), _atomic_rank(b)
    ra != rb && return ra < rb ? CMP_LESS : CMP_GREATER
    ra == _RANK_ATOM && return compareAtoms(a.name, a.reserved, b.name, b.reserved)
    x, y = a.gval, b.gval
    if ra == _RANK_NUMBER && x isa Real && y isa Real
        return _compare_numbers(x, y)
    elseif ra == _RANK_STRING && x isa AbstractString && y isa AbstractString
        return _compare_strings(x, y)
    end
    return _compare_other(x, b)
end

# ── Base: identity, hashing, printing ────────────────────────────────────────────────────────────
Base.:(==)(a::Term{G}, b::Term{G}) where {G} = compareStandard(a, b, true) == CMP_EQUAL

function Base.hash(t::Term, h::UInt)::UInt
    h = hash(t.kind, h)
    if t.kind === VAR || t.kind === SYM
        return hash(t.key, h)
    elseif t.kind === GND
        v = t.gval
        return hash(v, hash(typeof(v), h))
    end
    for c in t.children
        h = hash(c, h)
    end
    return h
end

function Base.show(io::IO, t::Term)
    if t.kind === VAR
        print(io, "_G", t.key)
    elseif t.kind === SYM
        # the reserved `[]` bare; a TEXT atom named `[]` quoted, so the two print apart
        !t.reserved && t.name === NIL_NAME ? print(io, "'[]'") : print(io, t.name)
    elseif t.kind === GND
        show(io, t.gval)
    else
        print(io, "(")
        for (i, c) in enumerate(t.children)
            i > 1 && print(io, " ")
            show(io, c)
        end
        print(io, ")")
    end
    return nothing
end
