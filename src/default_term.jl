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

`==` and `hash` follow IDENTITY in the standard order ([`compareStandard`](@ref) `== 0`): `1` and
`1.0` are different terms, although [`gnd_equal`](@ref) matches them.
"""
struct Term{G}
    kind::Kind
    ground::Bool                     # no variable anywhere below — cached at construction
    keyed::Bool                      # GND: `key` holds a grounded key (else WILDCARD)
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

"""
    gnd_value_key(v) -> Union{UInt64, Nothing}

A grounded key for a host value that agrees with `==`: equal values never key apart. Keys only the
types where `==`, `isequal` and `hash` are known to agree once `-0.0` is folded into `0.0` —
integers, rationals, floats, strings, characters and symbols — and returns `nothing` (WILDCARD) for
everything else: containers compare elements with `==` but hash through `isequal`, so `[0.0]` and
`[-0.0]` are `==` with different hashes. Usable by any implementation of the interface.
"""
function gnd_value_key(v)::Union{UInt64, Nothing}
    if v isa AbstractFloat
        return UInt64(v == 0 ? hash(0.0) : hash(v))       # 0.0 == -0.0; and hash(0.0) == hash(0)
    elseif v isa Integer || v isa Rational || v isa AbstractString || v isa AbstractChar ||
        v isa Symbol
        return UInt64(hash(v))
    end
    return nothing
end

_sym_key(s::Symbol)::UInt64 = UInt64(UInt(pointer_from_objref(s)))

"""
    sym_term(::Type{Term{G}}, name::Symbol) -> Term{G}

The symbol `name`.
"""
sym_term(::Type{Term{G}}, name::Symbol) where {G} =
    Term{G}(SYM, true, false, _sym_key(name), name, nothing, Term{G}[])

"""
    gnd_term(::Type{Term{G}}, v::G) -> Term{G}

The grounded value `v`; its [`gnd_key`](@ref) is computed here, once.
"""
function gnd_term(::Type{Term{G}}, v::G) where {G}
    k = gnd_value_key(v)
    return Term{G}(
        GND, true, k !== nothing, k === nothing ? UInt64(0) : k, Symbol(""), v, Term{G}[]
    )
end

mk_var(::Type{Term{G}}, key::UInt64) where {G} =
    Term{G}(VAR, false, false, key, Symbol(""), nothing, Term{G}[])

function mk_expr(::Type{Term{G}}, children::Vector{Term{G}}) where {G}
    ground = true
    for c in children
        c.ground || (ground=false; break)
    end
    return Term{G}(EXPR, ground, false, UInt64(0), Symbol(""), nothing, children)
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
nchildren(t::Term)::Int = length(t.children)
child(t::Term{G}, i::Int) where {G} = t.children[i]
sym_key(t::Term)::UInt64 = t.key
var_key(t::Term)::UInt64 = t.key
gnd_key(t::Term)::Union{UInt64, Nothing} = t.keyed ? t.key : nothing
is_ground(t::Term)::Bool = t.ground
gnd_equal(a::Term{G}, b::Term{G}) where {G} = _gnd_eq(a.gval, b)
# FUNCTION BARRIER: `a.gval == b.gval` on two `Union{Nothing, G…}` values is a 4×4 = 16-way call —
# past the compiler's union-splitting limit (4), so for DefaultTerm it would dispatch at runtime.
# Passing the second TERM (a concrete type) and reading its value inside, where `x` is already
# concrete, keeps every call at most 4-way. JET enforces this (test/test_static_analysis.jl).
_gnd_eq(x, b::Term)::Bool = (x == b.gval) === true

# ── atomic order: SWI's tag ladder, extended for Julia values Prolog does not have ───────────────
# Number (integer and float tags, compared jointly by value) < String < Atom < other host value.
# "Other" — Bool, Char, Symbol payloads, containers, custom types — has no Prolog counterpart, so it
# sorts AFTER every Prolog atomic kind and before compounds: the order of anything SWI can represent
# is untouched.
const _RANK_NUMBER = 1
const _RANK_STRING = 2
const _RANK_ATOM = 3
const _RANK_OTHER = 4

_is_number(v)::Bool = v isa Real && !(v isa Bool)

function _atomic_rank(t::Term)::Int
    t.kind === SYM && return _RANK_ATOM
    v = t.gval
    _is_number(v) && return _RANK_NUMBER
    v isa AbstractString && return _RANK_STRING
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
    return typeof(x) === typeof(y) ? CMP_EQUAL : _cmp_types(typeof(x), typeof(y))
end

function _compare_strings(x::AbstractString, y::AbstractString)::Int
    c = compareStrings(x, y)
    c != CMP_EQUAL && return c
    return typeof(x) === typeof(y) ? CMP_EQUAL : _cmp_types(typeof(x), typeof(y))
end

# FUNCTION BARRIER (see `_gnd_eq`): one union value plus the other TERM, so `y isa X` narrows `y`
# to the now-concrete type of `x` and every call below is static.
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
    ra == _RANK_ATOM && return compareAtoms(a.name, b.name)
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
        print(io, t.name)
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
