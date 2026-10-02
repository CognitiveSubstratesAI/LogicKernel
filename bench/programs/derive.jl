# UPSTREAM: swipl-bench programs/derive.pl @ d74163e6d756
# CLASS: design
#
# The van Roy "deriv" benchmark (David H. D. Warren, 1989): symbolic differentiation of three
# expressions. Re-expressed as a CLIENT of LogicKernel's public API on `DefaultTerm` — the standalone
# consumer (test/test_standalone_consumer.jl). The kernel has no unification yet, so each Prolog
# clause is one branch, tried in clause order; the head's shape is the branch's test, and the cut
# that every clause carries makes the first match final. The verbatim upstream program sits beside
# this file (derive.pl), and the consumer test runs it in swipl and compares the answers.
module Derive

using LogicKernel

const T = DefaultTerm
_s(n::Symbol) = sym_term(T, n)
_g(v::Int) = gnd_term(T, v)
_e(xs::T...) = mk_expr(T, T[xs...])
"`t` is a compound `f(a1, …, an)` with `f` named `f` and arity `n`."
_is(t::T, f::Symbol, n::Int) =
    kind(t) === EXPR && nchildren(t) == n + 1 && kind(child(t, 1)) === SYM &&
    sym_name(child(t, 1)) === f
_arg(t::T, i::Int) = child(t, i + 1)
_x() = _s(:x)

# PORT: derive.pl top
"`top :- ops8, log10, divide10.` — here returning the three derivatives."
top() = (ops8(), log10(), divide10())

# PORT: derive.pl ops8
"`d((x+1)*((^(x,2)+2)*(^(x,3)+3)), x, _)`"
ops8() = d(ops8_input(), _x())
ops8_input() = _e(_s(:*), _e(_s(:+), _x(), _g(1)),
    _e(_s(:*), _e(_s(:+), _e(_s(:^), _x(), _g(2)), _g(2)),
        _e(_s(:+), _e(_s(:^), _x(), _g(3)), _g(3))))

# PORT: derive.pl log10
"`d(log(log(log(log(log(log(log(log(log(log(x)))))))))), x, _)`"
log10() = d(log10_input(), _x())
log10_input() = foldl((t, _) -> _e(_s(:log), t), 1:10; init=_x())

# PORT: derive.pl divide10
"`d(((((((((x/x)/x)/x)/x)/x)/x)/x)/x)/x, x, _)`"
divide10() = d(divide10_input(), _x())
divide10_input() = foldl((t, _) -> _e(_s(:/), t, _x()), 1:9; init=_x())

# PORT: derive.pl d
"""
    d(u, x) -> the derivative of `u` with respect to `x`

`d/3`, clause by clause in upstream's order. The `^` clause cuts BEFORE `integer(N)`, so a
non-integer exponent makes `d/3` FAIL rather than fall through — here, an error.
"""
function d(u::T, x::T)::T
    if _is(u, :+, 2)                                     # d(U+V,X,DU+DV)
        return _e(_s(:+), d(_arg(u, 1), x), d(_arg(u, 2), x))
    elseif _is(u, :-, 2)                                 # d(U-V,X,DU-DV)
        return _e(_s(:-), d(_arg(u, 1), x), d(_arg(u, 2), x))
    elseif _is(u, :*, 2)                                 # d(U*V,X,DU*V+U*DV)
        U, V = _arg(u, 1), _arg(u, 2)
        return _e(_s(:+), _e(_s(:*), d(U, x), V), _e(_s(:*), U, d(V, x)))
    elseif _is(u, :/, 2)                                 # d(U/V,X,(DU*V-U*DV)/(^(V,2)))
        U, V = _arg(u, 1), _arg(u, 2)
        return _e(_s(:/), _e(_s(:-), _e(_s(:*), d(U, x), V), _e(_s(:*), U, d(V, x))),
            _e(_s(:^), V, _g(2)))
    elseif _is(u, :^, 2)                                 # d(^(U,N),X,DU*N*(^(U,N1)))
        U, N = _arg(u, 1), _arg(u, 2)
        (kind(N) === GND && gnd_value(N) isa Int) ||
            error("d/3 fails: exponent is not an integer")
        return _e(_s(:*), _e(_s(:*), d(U, x), N), _e(_s(:^), U, _g(gnd_value(N)::Int - 1)))
    elseif _is(u, :-, 1)                                 # d(-U,X,-DU)
        return _e(_s(:-), d(_arg(u, 1), x))
    elseif _is(u, :exp, 1)                               # d(exp(U),X,exp(U)*DU)
        return _e(_s(:*), u, d(_arg(u, 1), x))
    elseif _is(u, :log, 1)                               # d(log(U),X,DU/U)
        return _e(_s(:/), d(_arg(u, 1), x), _arg(u, 1))
    elseif compareStandard(u, x) == 0                    # d(X,X,1)
        return _g(1)
    end
    return _g(0)                                         # d(_,_,0)
end

end # module Derive
