# ORIGINAL: findall/3,4 (V9g-b) — the bags of pl-bag.c under boot/bags.pl's clauses — against a LIVE swipl; upstream's tests of findall/3 are in tests/core_lang/test_bags.pl, mirrored when plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_findall_swipl.jl — pl-bag.c '$new_findall_bag'/0, '$add_findall_bag'/1,2, '$collect_findall_bag'/2, '$destroy_findall_bag'/0; pl-rec.c compileTermToHeap, copyRecordToGlobal, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `fN/1`; the differential compares its answers and their determinism.
const _RFA_N = 39
function _rfa_clauses()
    X, Y, Z, L, M, E, A, B, C, N = (_rv(i) for i in 1:10)
    O, P, T = _rv(11), _rv(12), _rv(13)
    fa(t, g, l) = _rf("findall", t, g, l)
    fa4(t, g, l, tl) = _rf("findall", t, g, l, tl)
    c3(g, k, r) = _rf("catch", g, k, r)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    T_ = _rs("true")
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("q", _rg(1), _rs("a")), nothing), (_rf("q", _rg(2), _rs("b")), nothing),
        (_rf("q", _rg(1), _rs("c")), nothing),
        (_rf("mem", X, _rcons(X, Y)), nothing),
        (_rf("mem", X, _rcons(Y, Z)), _rf("mem", X, Z)),
        (_rf("gen", X, Y, X), _rf("=<", X, Y)),
        (
            _rf("gen", X, Y, Z),
            _rconj(_rf("<", X, Y), _rf("is", A, _rf("+", X, _rg(1))), _rf("gen", A, Y, Z))
        ),
        (_rf("len", _rnil(), _rg(0)), nothing),
        (
            _rf("len", _rcons(X, Y), N),
            _rconj(_rf("len", Y, M), _rf("is", N, _rf("+", M, _rg(1))))
        ),
        (_rf("last", _rcons(X, _rnil()), X), nothing),
        (_rf("last", _rcons(X, _rcons(Y, Z)), A), _rf("last", _rcons(Y, Z), A)),
        # ── the answers, in order ──
        (_rf("f1", L), fa(X, _rf("p", X), L)),
        (_rf("f2", L), fa(X, _rs("fail"), L)),                              # none: []
        (_rf("f3", L), fa(pair(X, Y), _rf("q", X, Y), L)),
        (_rf("f4", L), fa(Y, _rf("q", _rg(1), Y), L)),
        (_rf("f5", L), fa(X, _rconj(_rf("p", X), _rf(">", X, _rg(1))), L)),
        # ── variables: fresh in every answer, shared inside one, never bound outside ──
        (_rf("f6", L), fa(_rf("f", X, Y, X), _rf("p", Y), L)),
        (_rf("f7", pair(L, Z)), fa(Z, _rf("p", X), L)),
        (_rf("f8", pair(L, X)), fa(X, _rf("p", X), L)),                     # X stays unbound
        (_rf("f9", L), _rconj(eq(Y, _rf("g", Z)), fa(pair(Y, Z), T_, L))),  # [g(A)-A]
        (_rf("f10", L), _rconj(eq(Y, _rf("g", Z)), eq(Z, _rg(1)), fa(Y, T_, L))),
        (_rf("f11", L), fa(X, _rf("mem", X, _rlist(Y, _rf("h", Z, Z), Y, _rg(1.5))), L)),
        # ── nested, and backtracked over ──
        (_rf("f12", L), fa(pair(X, M), _rconj(_rf("p", X), fa(Y, _rf("q", X, Y), M)), L)),
        (
            _rf("f13", pair(X, L)),
            _rconj(_rf("p", X), fa(Y, _rconj(_rf("p", Y), _rf(">=", Y, X)), L))
        ),
        # ── findall/4, and a list that is bound already ──
        (_rf("f14", L), fa4(X, _rf("p", X), L, _rlist(_rs("a"), _rs("b")))),
        (_rf("f15", L), fa4(X, _rf("p", X), L, T)),                         # a partial list
        (_rf("f16", L), fa4(X, _rs("fail"), L, _rs("tail"))),               # the tail itself
        (_rf("f17", X), fa(X, _rf("p", X), _rints(1:3))),
        (_rf("f18", X), fa(X, _rf("p", X), _rints(1:2))),                   # fails
        (_rf("f19", pair(A, B)), fa(X, _rf("p", X), _rcons(A, B))),
        (_rf("f20", X), fa(X, _rf("p", X), _rs("foo"))),                    # fails: no type check
        # ── the goal: control, cut, exceptions, errors ──
        (_rf("f21", L), fa(X, _rconj(_rf("p", X), _rs("!")), L)),           # the cut is local
        (_rf("f22", L), fa(X, _ror(_rf("p", X), eq(X, _rs("z"))), L)),
        (_rf("f23", L), fa(X, _rite(_rf("p", X), T_, eq(X, _rs("none"))), L)),
        (_rf("f24", L), fa(X, _rconj(_rf("p", X), _rnot(eq(X, _rg(2)))), L)),
        (
            _rf("f25", pair(E, L)),         # a ball out of the goal: the bag is closed
            _rconj(
                c3(
                    fa(
                        X,
                        _rconj(_rf("p", X), _rf(">", X, _rg(1)), _rf("throw", _rs("b"))),
                        M
                    ),
                    E,
                    T_
                ),
                fa(Y, _rf("p", Y), L)
            )
        ),
        (_rf("f26", E), c3(fa(X, Y, L), _rf("error", E, Z), T_)),           # an unbound goal
        (_rf("f27", E), c3(fa(X, _rg(1), L), _rf("error", E, Z), T_)),      # not callable
        (
            _rf("f28", E),
            c3(fa(X, _rconj(_rf("p", X), _rg(1)), L), _rf("error", E, Z), T_)
        ),
        (_rf("f29", L), fa(X, _rf(":", _rs("user"), _rf("p", X)), L)),
        # ── many answers ──
        (
            _rf("f30", pair(N, X)),
            _rconj(
                fa(Y, _rf("gen", _rg(1), _rg(300), Y), L),
                _rf("len", L, N),
                _rf("last", L, X)
            )
        ),
        # ── a rational tree is recorded as one ──
        (_rf("f31", L), _rconj(eq(X, _rf("f", X)), fa(X, T_, L))),
        (
            _rf("f32", N),
            _rconj(
                eq(X, _rf("f", X, Y)), fa(X, T_, _rlist(A)), eq(A, _rf("f", B, C)),
                eq(B, _rf("f", M, O)),
                _rite(_rf("==", C, O), eq(N, _rs("one_variable")), eq(N, _rs("two")))
            )
        ),
        # ── the standard order of the fresh variables is the order of upstream's cells (the list is
        # unified with the pattern AFTER findall/3: unified with older variables, the fresh ones
        # would be bound to those, and the order compared would be theirs) ──
        (
            _rf("f33", O),                  # the outer compound's cells come first
            _rconj(
                fa(_rf("f", _rf("g", X), Y), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", A), B))),
                _rf("compare", O, A, B)
            )
        ),
        (
            _rf("f34", pair(O, P)),         # the LAST answer is put back first
            _rconj(
                fa(X, _rf("p", Y), L), eq(L, _rlist(A, B, C)), _rf("compare", O, A, B),
                _rf("compare", P, B, C)
            )
        ),
        (
            _rf("f35", O),                  # a variable lives in its lowest cell
            _rconj(
                fa(_rf("f", _rf("g", Y, X), X, Y), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", A, B), C, N))), _rf("compare", O, A, B)
            )
        ),
        # ── the primitives ──
        (
            _rf("f36", _rf("r", L, A, B)),
            _rconj(
                _rs("\$new_findall_bag"), _rf("\$add_findall_bag", _rs("a"), A),
                _rf("\$add_findall_bag", _rf("f", X), B),
                _rf("\$collect_findall_bag", L, _rlist(_rs("t"))),
                _rs("\$destroy_findall_bag")
            )
        ),
        (
            _rf("f37", L),                  # nothing added: the tail
            _rconj(
                _rs("\$new_findall_bag"), _rf("\$collect_findall_bag", L, _rs("tail")),
                _rs("\$destroy_findall_bag")
            )
        ),
        (_rf("f38", E), c3(_rf("\$add_findall_bag", _rs("x")), E, T_)),     # no bag
        (
            _rf("f39", O),                  # a nested compound's variables come before ITS compounds'
            _rconj(
                fa(_rf("f", _rf("g", _rf("h", X), Y)), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", _rf("h", A), B)))), _rf("compare", O, A, B)
            )
        )
    ]
end

_rfa_goals() = _R[_rf("f$k", _rv(50 + k)) for k in 1:_RFA_N]

"The kernel's lines for `goals`: the pools checked, no exception pending and no bag open at every answer."
function _rfa_ours(clauses, goals)
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(
            db,
            g;
            at=(qid, k) -> (@test _rpools_live(db.ld) && db.ld.exception_term == 0 &&
                isempty(db.ld.bags))
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
        @test isempty(db.ld.bags)                   # … and none after a failure or an error
    end
    return ours, db
end

@testset "findall/3,4: answers and determinism equal swipl's" begin
    clauses = _rfa_clauses()
    goals = _rfa_goals()
    ours, db = _rfa_ours(clauses, goals)
    @test count(==("end"), ours) == length(goals)
    @test "f1([1,2,3]) det" in ours
    @test "f2([]) det" in ours
    @test "f6([f(A,1,A),f(B,2,B),f(C,3,C)]) det" in ours
    @test "f25(-(b,[1,2,3])) det" in ours
    @test "f30(-(300,300)) det" in ours
    @test count(==("cyclic det"), ours) == 1         # f31: a rational tree, as the driver writes one
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            for k in 1:max(length(ours), length(theirs))
                get(ours, k, "—") == get(theirs, k, "—") && continue
                println(stderr, "  line ", k, "\n    kernel ", get(ours, k, "—"),
                    "\n    swipl  ", get(theirs, k, "—"))
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# White box: the records. An atomic or ground answer is its own record; a record survives the
# undoing of the bindings it was made under; putting it back twice gives two terms that share no
# variable.
@testset "a record survives backtracking, and is put back with fresh variables each time" begin
    db = _RDB()
    ld = db.ld
    X, Y = _rv(1), _rv(2)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, t + 1, _rf("f", X, Y, X))
    m = LK.Mark(ld)
    # Y bound through the handle: the put copied it to a fresh variable, which is the engine's
    # (L1b boundary, user 2026-10-14: variable identity = handle; the caller's Y is never bound)
    LK.Trail!(ld, var_key(child(LK.slotValue(ld, t + 1), 3)), _rf("g", _rg(1)))
    r = LK.compileTermToHeap(ld, t)
    @test !r.ground && r.cycles === nothing
    g = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, g + 1, _rf("g", _rg(1)))
    rg = LK.compileTermToHeap(ld, g)
    @test rg.ground && rg.term === LK.slotValue(ld, g + 1)
    LK.Undo!(ld, m)
    @test length(ld.trail) == m.trailtop            # recording left nothing on the trail
    a, b = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.copyRecordToGlobal(ld, a, r) && LK.copyRecordToGlobal(ld, b, r)
    ta, tb = LK.slotValue(ld, a + 1), LK.slotValue(ld, b + 1)
    @test _rcanonical(ta) == "f(A,g(1),A)" && _rcanonical(tb) == "f(A,g(1),A)"
    @test var_key(child(ta, 2)) != var_key(child(tb, 2))        # fresh each time
    @test var_key(child(ta, 2)) != var_key(X)                   # … and not the original's
    @test child(ta, 3) === child(tb, 3)                         # the ground subterm is shared
    # a rational tree: its cyclic reference is kept in the record, not on the trail
    C = _rv(3)
    LK.Trail!(ld, var_key(C), _rf("c", C, X))
    cy = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, cy + 1, C)
    n0 = length(ld.trail)
    rc = LK.compileTermToHeap(ld, cy)
    @test length(ld.trail) == n0 && rc.cycles !== nothing && length(rc.cycles) == 1
    out = LK.PL_new_term_ref(ld)
    @test LK.copyRecordToGlobal(ld, out, rc)
    # the copy's cyclic reference is a FRESH cell above the foreign frame's bar: bound, and not
    # trailed (L1a-2, `mark_bar`) — upstream builds the copy in place on the global stack
    @test length(ld.trail) == n0
    LK.PL_close_foreign_frame(ld, fid)
end

# KNOWN DIFFERENCE, pinned (R2 checklist: "boot/bags.pl in its module `'\$bags'`"):
#   kernel: `context(system:findall_loop/4, _)` — the stand-in's clauses are `system`'s
#   swipl 10.1.18: `context('\$bags':findall_loop/4, _)` (probed)
@testset "an unbound goal: the error's context names the stand-in's module (R2)" begin
    X, Y, L, E = _rv(1), _rv(2), _rv(3), _rv(4)
    db = _rdb([
        (
        _rf("ctx", E),
        _rf("catch", _rf("findall", X, Y, L), _rf("error", _rv(5), E), _rs("true"))
    )
    ])
    @test [a for (a, _) in _rcall(db, _rf("ctx", _rv(51)))] ==
        ["ctx(context(:(system,/(findall_loop,4)),_))"]
end
