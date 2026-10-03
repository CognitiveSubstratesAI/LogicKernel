# UPSTREAM: swipl-bench programs/nreverse.pl @ d74163e6d756
# CLASS: design
#
# The van Roy "nreverse" benchmark (David H. D. Warren, 1989): naive reverse of a 30-element list.
# A CLIENT of LogicKernel's public API on `DefaultTerm` (the standalone consumer). Lists are
# `'[|]'(H, T)` compounds ending in `[]`, as in SWI-Prolog 7. Clause order is preserved; a list
# that is neither `[_|_]` nor `[]` makes the predicate fail — here, an error.
module NReverse

using LogicKernel

const T = DefaultTerm
_s(n::Symbol) = sym_term(T, n)
_g(v::Int) = gnd_term(T, v)
_e(xs::T...) = mk_expr(T, T[xs...])
_nil() = mk_nil(T)                                  # SWI-7's [], a reserved symbol
_cons(h::T, t::T) = _e(_s(Symbol("[|]")), h, t)
_isnil(t::T) = is_nil(t)
_iscons(t::T) =
    kind(t) === EXPR && nchildren(t) == 3 && kind(child(t, 1)) === SYM &&
    sym_name(child(t, 1)) === Symbol("[|]")
_list(xs::Vector{T}) = foldr(_cons, xs; init=_nil())

# PORT: nreverse.pl top
"`top :- nreverse.`"
top() = nreverse()

# PORT: nreverse.pl nreverse
"`nreverse :- nreverse([1,…,30], _).` — here returning the reversed list."
nreverse() = nreverse(_list([_g(i) for i in 1:30]))

# PORT: nreverse.pl nreverse
"`nreverse([X|L0],L) :- nreverse(L0,L1), concatenate(L1,[X],L).` and `nreverse([],[]).`"
function nreverse(l::T)::T
    _iscons(l) && return concatenate(nreverse(child(l, 3)), _cons(child(l, 2), _nil()))
    _isnil(l) && return _nil()
    error("nreverse/2 fails: not a list")
end

# PORT: nreverse.pl concatenate
"`concatenate([X|L1],L2,[X|L3]) :- concatenate(L1,L2,L3).` and `concatenate([],L,L).`"
function concatenate(l1::T, l2::T)::T
    _iscons(l1) && return _cons(child(l1, 2), concatenate(child(l1, 3), l2))
    _isnil(l1) && return l2
    error("concatenate/3 fails: not a list")
end

end # module NReverse
