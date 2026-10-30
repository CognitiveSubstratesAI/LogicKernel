# ORIGINAL: regression rows for fuzz seed 300945 (audit D-0260) — pl-vmi.c B_ARGVAR's link direction, and H_VAR's in write mode; no upstream unit.
# test/core_lang/test_argvar_order_swipl.jl — pl-vmi.c:1045-1067 (B_ARGVAR) and :675-700 (H_VAR, write mode), the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# THE DEFECT THESE GUARD. A variable met a second time as an argument of a compound under construction
# (`B_ARGVAR`, or `H_VAR` in write mode) is a reference one way or the other, and swipl chooses by
# ADDRESS: an unbound cell ABOVE the argument cell is bound to a reference to it (`ARGP < k`, pl-vmi.c
# B_ARGVAR; `k > ARGP`, H_VAR), so the variable's identity — its address, which standard order compares
# (pl-prims.c compareStandard) — is the LOWER cell. The kernel pointed the argument cell UP at the
# variable always, so two fresh variables compared in the other order: `foo(f(g(Vb),g(Va),Va)),
# compare(O,Vb,Va)` gave `<` where swipl gives `>`, and `msort/2` ordered a list of such terms
# differently (fuzz seed 300945, run 41061140828). The cases are the reproducer, the shapes that
# agreed all along (the argument cell in `f` is not what makes Va live: `g(Va)` is), the same terms
# built by a HEAD in write mode, the seed's own msort term, and the seed's t16 line.

function _rav_clauses()
    O, B, A, C, L = (_rv(k) for k in 1:5)
    foo = (x) -> _rf("foo", x)
    f(xs...) = _rf("f", xs...)
    g(xs...) = _rf("g", xs...)
    cmp = _rf("compare", O, B, A)
    return Tuple{_R, Union{Nothing, _R}}[
        (foo(_rv(30)), nothing),
        # the reproducer: b_argfirstvar in g(Vb), b_argfirstvar in g(Va), b_argvar(Va) in f's own cell
        (_rf("rep", O), _rconj(foo(f(g(B), g(A), A)), cmp)),
        # the shapes that agreed with swipl before the fix
        (_rf("var1", O), _rconj(foo(f(g(B), A, A)), cmp)),
        (_rf("var2", O), _rconj(foo(f(g(B), g(A), g(A))), cmp)),
        (_rf("var3", O), _rconj(foo(f(g(B), A)), cmp)),
        # H_VAR in write mode: the head builds the term for an unbound argument
        (_rf("hvw", f(g(B), g(A), A), B, A), nothing),
        (_rf("hrep", O), _rconj(_rf("hvw", _rv(40), B, A), cmp)),
        # the same head with nothing else to bind its variables: the term it builds keeps them, so the cell
        # H_VAR links decides the order (hrep's args 2 and 3 unify with older variables and hide it)
        (_rf("hvw1", f(g(B), g(A), A)), nothing),
        (_rf("hrep2", O), _rconj(_rf("hvw1", C), _rf("=", C, f(g(B), _rv(7), A)), cmp)),
        # a variable whose slot reaches its cell through a CHAIN (its first cell, in g(A), was bound to w's second argument cell,
        # which lies above f's second argument cell): the direction test follows the chain, so A is f's cell, below B
        (
            _rf("chain", O),
            _rconj(foo(f(_rf("w", g(A), A), A, B)), cmp)
        ),
        # the seed's term in msort/2, and the seed's t16 line (sort/4 on key 2, descending, no duplicates dropped)
        (
            _rf("ms1", L),
            _rf(
                "msort",
                _rlist(f(_rf("k", B), g(A), A), g(B, _rs("c")), g(A, _rs("x"))), L
            )
        ),
        (
            _rf("seed", L),
            _rconj(
                _rf(
                    "sort", _rg(2), _rs("@>="),
                    _rlist(
                        _rf(
                            "k", _rs("a"),
                            _rf(
                                "h", _rf("k", _rf("h", _rs("b"), B, _rg(7))),
                                _rlist(_rlist(A, _rs("foo")), A), A
                            )
                        ),
                        _rf("k", _rs("b"), _rcons(B, _rs("c"))),
                        _rf(
                            "k",
                            _rs("c"),
                            _rlist(A, _rcons(C, _rcons(_rg(0), _rcons(_rg(0), B))))
                        )
                    ),
                    _rv(6)
                ),
                _rf("=", L, _rv(6))
            )
        )
    ]
end

const _RAV_GOALS = _R[
    _rf("rep", _rv(1)), _rf("var1", _rv(1)), _rf("var2", _rv(1)), _rf("var3", _rv(1)),
    _rf("hrep", _rv(1)), _rf("hrep2", _rv(1)), _rf("chain", _rv(1)), _rf("ms1", _rv(1)),
    _rf("seed", _rv(1))
]

# swipl 10.1.19's answers, kept as text so the rows are checked where swipl is not installed (CI's
# Pkg.test); the differential below compares the kernel with swipl itself when it is.
const _RAV_SWIPL = [
    "rep(>) det", "end",
    "var1(>) det", "end",
    "var2(<) det", "end",
    "var3(>) det", "end",
    "hrep(<) det", "end",
    "hrep2(>) det", "end",
    "chain(>) det", "end",
    "ms1([g(A,x),g(B,c),f(k(B),g(A),A)]) det", "end",
    "seed([k(a,h(k(h(b,A,7)),[[B,foo],B],B)),k(b,[A|c]),k(c,[B,[_,0,0|A]])]) det", "end"
]

@testset "B_ARGVAR / H_VAR write mode: the lower cell is the variable (fuzz seed 300945)" begin
    db = _rdb(_rav_clauses())
    ours = _rlines(db, _RAV_GOALS)
    @test length(ours) == length(_RAV_SWIPL)
    @test ours == _RAV_SWIPL
    ours == _RAV_SWIPL ||
        println(stderr, "    kernel ", ours, "\n    swipl  ", _RAV_SWIPL)
    if _R_SWIPL
        theirs = _rswipl(_rav_clauses(), _RAV_GOALS)
        @test theirs == _RAV_SWIPL   # the pinned text IS swipl's
        @test ours == theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end
