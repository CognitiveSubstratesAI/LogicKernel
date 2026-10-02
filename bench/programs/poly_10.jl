# UPSTREAM: swipl-bench programs/poly_10.pl @ d74163e6d756
# CLASS: design
#
# The van Roy "poly" benchmark (Ralph Haygood, after Rick McGeer, 1990): raise the polynomial
# 1 + x + y + z to the 10th power, polynomials represented as `poly(Var, [term(Exp, Coeff), …])`
# with variables ordered by the `less_than` facts. A CLIENT of LogicKernel's public API on
# `DefaultTerm` (the standalone consumer). Every predicate keeps upstream's clause ORDER: the first
# clause whose head fits and whose guard holds wins (each carries a cut), exactly as in Prolog.
module Poly10

using LogicKernel

const T = DefaultTerm
_s(n::Symbol) = sym_term(T, n)
_g(v::Int) = gnd_term(T, v)
_e(xs::T...) = mk_expr(T, T[xs...])
_nil() = _s(Symbol("[]"))
_cons(h::T, t::T) = _e(_s(Symbol("[|]")), h, t)
_isnil(t::T) = kind(t) === SYM && sym_name(t) === Symbol("[]")
_list(xs::Vector{T}) = foldr(_cons, xs; init=_nil())
_is(t::T, f::Symbol, n::Int) =
    kind(t) === EXPR && nchildren(t) == n + 1 && kind(child(t, 1)) === SYM &&
    sym_name(child(t, 1)) === f
_arg(t::T, i::Int) = child(t, i + 1)
_head(l::T) = child(l, 2)                       # [H|_]
_tail(l::T) = child(l, 3)                       # [_|T]
_poly(v::T, terms::T) = _e(_s(:poly), v, terms)
_term(e::T, c::T) = _e(_s(:term), e, c)
_same(a::T, b::T) = compareStandard(a, b) == 0  # two head occurrences of one variable: unify
_int(t::T) = gnd_value(t)::Int

# PORT: poly_10.pl top
"`top :- poly_10.`"
top() = poly_10()

# PORT: poly_10.pl poly_10
"`poly_10 :- test_poly(P), poly_exp(10, P, _).` — here returning the result."
poly_10() = poly_exp(10, test_poly())

# PORT: poly_10.pl test_poly
"`test_poly(P)`: 1 + x + y + z, built with `poly_add/3` as upstream builds it."
function test_poly()::T
    q = poly_add(_poly(_s(:x), _list([_term(_g(0), _g(1)), _term(_g(1), _g(1))])),
        _poly(_s(:y), _list([_term(_g(1), _g(1))])))
    return poly_add(_poly(_s(:z), _list([_term(_g(1), _g(1))])), q)
end

# PORT: poly_10.pl less_than
"The facts `x less_than y.`, `y less_than z.`, `x less_than z.`"
less_than(a::T, b::T)::Bool =
    kind(a) === SYM && kind(b) === SYM &&
    (sym_name(a), sym_name(b)) in ((:x, :y), (:y, :z), (:x, :z))

# PORT: poly_10.pl poly_add
"`poly_add/3`, five clauses in upstream's order."
function poly_add(a::T, b::T)::T
    pa, pb = _is(a, :poly, 2), _is(b, :poly, 2)
    if pa && pb && _same(_arg(a, 1), _arg(b, 1))                   # poly(Var,_), poly(Var,_)
        return _poly(_arg(a, 1), term_add(_arg(a, 2), _arg(b, 2)))
    elseif pa && pb && less_than(_arg(a, 1), _arg(b, 1))           # Var1 less_than Var2
        return _poly(_arg(a, 1), add_to_order_zero_term(_arg(a, 2), b))
    elseif pb                                                       # Poly, poly(Var,Terms2)
        return _poly(_arg(b, 1), add_to_order_zero_term(_arg(b, 2), a))
    elseif pa                                                       # poly(Var,Terms1), C
        return _poly(_arg(a, 1), add_to_order_zero_term(_arg(a, 2), b))
    end
    return _g(_int(a) + _int(b))                                    # C is C1+C2
end

# PORT: poly_10.pl term_add
"`term_add/3`, merging two exponent-ordered term lists."
function term_add(t1::T, t2::T)::T
    _isnil(t1) && return t2                                         # term_add([], X, X)
    _isnil(t2) && return t1                                         # term_add(X, [], X)
    a, b = _head(t1), _head(t2)
    e1, c1, e2, c2 = _arg(a, 1), _arg(a, 2), _arg(b, 1), _arg(b, 2)
    if _same(e1, e2)                                                # [term(E,C1)|_], [term(E,C2)|_]
        return _cons(_term(e1, poly_add(c1, c2)), term_add(_tail(t1), _tail(t2)))
    elseif _int(e1) < _int(e2)                                      # E1 < E2
        return _cons(a, term_add(_tail(t1), t2))
    end
    return _cons(b, term_add(t1, _tail(t2)))
end

# PORT: poly_10.pl add_to_order_zero_term
"`add_to_order_zero_term/3`: add a constant to the exponent-0 term, creating it if absent."
function add_to_order_zero_term(terms::T, c2::T)::T
    if !_isnil(terms) && _is(_head(terms), :term, 2) && _same(_arg(_head(terms), 1), _g(0))
        return _cons(_term(_g(0), poly_add(_arg(_head(terms), 2), c2)), _tail(terms))
    end
    return _cons(_term(_g(0), c2), terms)
end

# PORT: poly_10.pl poly_exp
"`poly_exp/3`: exponentiation by squaring (`M is N>>1, N is M<<1` is the evenness test)."
function poly_exp(n::Int, p::T)::T
    n == 0 && return _g(1)
    m = n >> 1
    if n == m << 1
        part = poly_exp(m, p)
        return poly_mul(part, part)
    end
    return poly_mul(p, poly_exp(n - 1, p))
end

# PORT: poly_10.pl poly_mul
"`poly_mul/3`, five clauses in upstream's order — `poly_add/3`'s shape, multiplying."
function poly_mul(a::T, b::T)::T
    pa, pb = _is(a, :poly, 2), _is(b, :poly, 2)
    if pa && pb && _same(_arg(a, 1), _arg(b, 1))
        return _poly(_arg(a, 1), term_mul(_arg(a, 2), _arg(b, 2)))
    elseif pa && pb && less_than(_arg(a, 1), _arg(b, 1))
        return _poly(_arg(a, 1), mul_through(_arg(a, 2), b))
    elseif pb
        return _poly(_arg(b, 1), mul_through(_arg(b, 2), a))
    elseif pa
        return _poly(_arg(a, 1), mul_through(_arg(a, 2), b))
    end
    return _g(_int(a) * _int(b))                                    # C is C1*C2
end

# PORT: poly_10.pl term_mul
"`term_mul/3`: every term of the first list times the whole second list, summed."
function term_mul(t1::T, t2::T)::T
    (_isnil(t1) || _isnil(t2)) && return _nil()
    return term_add(single_term_mul(t2, _head(t1)), term_mul(_tail(t1), t2))
end

# PORT: poly_10.pl single_term_mul
"`single_term_mul/3`: one term times a term list (`E is E1+E2`)."
function single_term_mul(terms::T, term::T)::T
    _isnil(terms) && return _nil()
    t = _head(terms)
    e = _g(_int(_arg(t, 1)) + _int(_arg(term, 1)))
    return _cons(
        _term(e, poly_mul(_arg(t, 2), _arg(term, 2))), single_term_mul(_tail(terms), term)
    )
end

# PORT: poly_10.pl mul_through
"`mul_through/3`: multiply every coefficient of a term list by a polynomial or constant."
function mul_through(terms::T, poly::T)::T
    _isnil(terms) && return _nil()
    t = _head(terms)
    return _cons(
        _term(_arg(t, 1), poly_mul(_arg(t, 2), poly)), mul_through(_tail(terms), poly)
    )
end

end # module Poly10
