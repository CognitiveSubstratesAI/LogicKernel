# UPSTREAM: swipl-bench programs/qsort.pl @ d74163e6d756
# CLASS: design
#
# The van Roy "qsort" benchmark (David H. D. Warren, 1989): quicksort of 50 integers with an
# accumulator (difference-list style). A CLIENT of LogicKernel's public API on `DefaultTerm` (the
# standalone consumer). `X =< Y` is ARITHMETIC comparison, so it reads the grounded values.
module QSort

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

const INPUT = (27, 74, 17, 33, 94, 18, 46, 83, 65, 2, 32, 53, 28, 85, 99, 47, 28, 82, 6, 11,
    55, 29, 39, 81, 90, 37, 10, 0, 66, 51, 7, 21, 85, 27, 31, 63, 75, 4, 95, 99,
    11, 28, 61, 74, 18, 92, 40, 53, 59, 8)

# PORT: qsort.pl top
"`top :- qsort.`"
top() = qsort()

# PORT: qsort.pl qsort
"`qsort :- qsort([27,74,…,8], _, []).` — here returning the sorted list."
qsort() = qsort(_list([_g(v) for v in INPUT]), _nil())

# PORT: qsort.pl qsort
"""
`qsort([X|L],R,R0) :- partition(L,X,L1,L2), qsort(L2,R1,R0), qsort(L1,R,[X|R1]).` and
`qsort([],R,R).` — `qsort(l, r0)` returns `R`: `l` sorted, followed by `r0`.
"""
function qsort(l::T, r0::T)::T
    if _iscons(l)
        x = child(l, 2)
        l1, l2 = partition(child(l, 3), x)
        r1 = qsort(l2, r0)
        return qsort(l1, _cons(x, r1))
    end
    _isnil(l) && return r0
    error("qsort/3 fails: not a list")
end

# PORT: qsort.pl partition
"""
`partition([X|L],Y,[X|L1],L2) :- X =< Y, !, partition(L,Y,L1,L2).`,
`partition([X|L],Y,L1,[X|L2]) :- partition(L,Y,L1,L2).` and `partition([],_,[],[]).`
"""
function partition(l::T, y::T)::Tuple{T, T}
    if _iscons(l)
        x = child(l, 2)
        l1, l2 = partition(child(l, 3), y)
        return gnd_value(x) <= gnd_value(y) ? (_cons(x, l1), l2) : (l1, _cons(x, l2))
    end
    _isnil(l) && return (_nil(), _nil())
    error("partition/4 fails: not a list")
end

end # module QSort
