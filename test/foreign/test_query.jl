# ORIGINAL: the query API's contract (decision 1) and the virtual machine's effects on the stacks, unit by unit (V4a); upstream exercises them through its C interface.
# test/foreign/test_query.jl — `PL_open_query`, `PL_next_solution`, `PL_cut_query`, `PL_close_query`,
# `PL_exception`, `PL_current_query`, as decision 1 states them and as libswipl 10.1.16 does them
# (probed live, V4a research: a C program calling the query API on these predicates):
#   * the return codes and determinism: `f(X)` over three facts answers 1, 1, then `PL_S_LAST` under
#     `PL_Q_EXT_STATUS` (1 without), then 0; one clause or an indexed call: `PL_S_LAST` at once;
#   * the supervisors the first call installs (`S_VIRGIN` → `S_STATIC`, `S_TRUSTME`, `S_LIST`,
#     `S_DYNAMIC`), and `S_VIRGIN` again after a clause is added to a static predicate;
#   * POSITIONS: the query frame at `lTop`, its CHP_TOP choice at +21, top frame at +31, frame at +39;
#     the first term reference after an answer at +63 (non-deterministic) or +45 (deterministic); after
#     a failing call of f/1 at +61 and of h/2 at +69 (`S_STATIC`'s quirk); a nested query at +63;
#   * nested queries: only the innermost may be advanced, cut or closed (`PL_S_NOT_INNER`);
#   * `PL_cut_query` keeps the answer's bindings, `PL_close_query` undoes them; after a deterministic
#     last answer the next call undoes them and fails, and no term reference can be made until the
#     query is closed;
#   * an uncaught exception: `PL_S_EXCEPTION` under `PL_Q_EXT_STATUS`, the error term from
#     `PL_exception`; `PL_Q_PASS_EXCEPTION` leaves it pending;
#   * the `except` arm re-entering the loop (`PrologThrow`), and a Julia exception ending the query;
#   * an instruction the run loop does not hold yet (a rule's `I_ENTER`, V4b) refused BY NAME — the
#     dispatch's fall-through — and the query closed;
#   * clause GC while a query runs through a retracted clause: the frame scan keeps it (erased, not
#     reclaimed, until the query is closed), and the query completes under the logical update view;
#   * the builder: reset with the argument stack — at an answer after a head failed inside a nested
#     compound, the stack is at the query's height; push and save allocate nothing (reference type).
using Test, LogicKernel
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

const _Y = lk_term_type(Union{Int64, Float64, String})
_ys(x) = lk_sym(_Y, Symbol(x))
_yg(v) = lk_gnd(_Y, v)
_yf(f, xs::_Y...) = mk_expr(_Y, _Y[_ys(f), xs...])
_yv(k::Int) = mk_var(_Y, UInt64(k))
_ylist(h, t) = _yf("[|]", h, t)

"A database with `f(a). f(b). f(c).`, `g(only).`, `h(1, a). h(2, b).`, `l([], 0). l([_|_], 1).` and dynamic `d(1). d(2). d(3).`."
function _ydb()
    db = IxDB{_Y}()
    p = Dict{Symbol, IxPred{_Y}}()
    p[:f] = ix_pred(_Y, :f, 1; db=db)
    foreach(x -> ix_assertz!(p[:f], _yf(:f, _ys(x))), (:a, :b, :c))
    p[:g] = ix_pred(_Y, :g, 1; db=db)
    ix_assertz!(p[:g], _yf(:g, _ys(:only)))
    p[:h] = ix_pred(_Y, :h, 2; db=db)
    ix_assertz!(p[:h], _yf(:h, _yg(1), _ys(:a)))
    ix_assertz!(p[:h], _yf(:h, _yg(2), _ys(:b)))
    p[:l] = ix_pred(_Y, :l, 2; db=db)
    ix_assertz!(p[:l], _yf(:l, LK.mk_nil(_Y), _yg(0)))
    ix_assertz!(p[:l], _yf(:l, _ylist(_yv(90), _yv(91)), _yg(1)))
    p[:d] = ix_pred(_Y, :d, 1; dynamic=true, db=db)
    foreach(x -> ix_assertz!(p[:d], _yf(:d, _yg(x))), 1:3)
    return db, p
end

"Open a query of `p` on `args` (terms) under `flags`, in a new foreign frame: `(qid, first argument reference, fid)`."
function _yopen(p::IxPred{_Y}, args::_Y...; flags=LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS)
    ld = p.db.ld
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, t) in enumerate(args)
        ld.slots[a + i] = t
    end
    qid = LK.PL_open_query(p.db.gd, ld, nothing, flags, p.proc, a)
    return qid, a, fid
end
_ynext(p, qid) = LK.PL_next_solution(p.db.gd, p.db.ld, qid)
_yval(p, a) = LK.resolve_term(p.db.ld, p.db.ld.slots[a + 1])

@testset "answers, determinism and the return codes" begin
    db, p = _ydb()
    X = _yv(1)
    qid, a, fid = _yopen(p[:f], X)
    rcs, xs = Int[], String[]
    for _ in 1:4
        push!(rcs, _ynext(p[:f], qid))
        push!(xs, kind(_yval(p[:f], a)) === VAR ? "_" : String(lk_name(_yval(p[:f], a))))
    end
    @test rcs == [1, 1, 2, 0] && xs == ["a", "b", "c", "_"]   # the last call undid X = c
    LK.PL_close_query(db.ld, qid)
    LK.PL_close_foreign_frame(db.ld, fid)
    qid, a, fid = _yopen(p[:f], X; flags=LK.PL_Q_NORMAL)        # without PL_Q_EXT_STATUS
    @test [_ynext(p[:f], qid) for _ in 1:4] == [1, 1, 1, 0]
    LK.PL_close_query(db.ld, qid)
    LK.PL_close_foreign_frame(db.ld, fid)
    for (pr, goal, want) in ((:g, X, [2, 0]), (:f, _ys(:b), [2, 0]), (:f, _ys(:z), [0]),
        (:l, _ylist(_ys(:x), LK.mk_nil(_Y)), [2, 0]))
        args = pr === :l ? (goal, X) : (goal,)
        qid, a, fid = _yopen(p[pr], args...)
        @test [_ynext(p[pr], qid) for _ in want] == want
        LK.PL_close_query(db.ld, qid)
        LK.PL_close_foreign_frame(db.ld, fid)
    end
    @test db.ld.query == 0 && db.ld.nqueries == 0 && db.ld.nframes == 0 &&
        db.ld.nchoices == 0
end

@testset "the supervisors: S_VIRGIN installs the predicate's on its first call" begin
    db, p = _ydb()
    for pr in (:f, :g, :l, :d)
        @test p[pr].def.codes[1] == LK.S_VIRGIN
    end
    for (pr, args) in
        ((:f, (_yv(1),)), (:g, (_yv(1),)), (:l, (_yv(1), _yv(2))), (:d, (_yv(1),)))
        qid, _, fid = _yopen(p[pr], args...)
        _ynext(p[pr], qid)
        LK.PL_close_query(db.ld, qid)
        LK.PL_close_foreign_frame(db.ld, fid)
    end
    @test [LK.codeTable(p[pr].def.codes[1]).name for pr in (:f, :g, :l, :d)] ==
        [:S_STATIC, :S_TRUSTME, :S_LIST, :S_DYNAMIC]
    ix_assertz!(p[:g], _yf(:g, _ys(:more)))                     # a static predicate changes …
    @test p[:g].def.codes[1] == LK.S_VIRGIN                     # … back to S_VIRGIN
    ix_assertz!(p[:d], _yf(:d, _yg(4)))                         # a dynamic one keeps S_DYNAMIC
    @test p[:d].def.codes[1] == LK.S_DYNAMIC
    # `$c_call_prolog/0`, the top frame's predicate, is in no module table
    @test db.gd.procedures_dc_call_prolog0.definition.arity == 0
    @test !any(pr -> pr.definition === db.gd.procedures_dc_call_prolog0.definition,
        values(LK.MODULE_user(db.gd).procedures))
end

@testset "positions are swipl's: the query frame and what an answer leaves" begin
    db, p = _ydb()
    ld = db.ld
    X = _yv(1)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    ld.slots[a + 1] = X
    top = ld.lTop
    qid = LK.PL_open_query(
        db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, p[:f].proc, a
    )
    q = ld.queries[LK.QueryFromQid(ld, qid)]
    @test qid == top                                            # at lTop: no padding
    @test ld.choices[q.choice].base - qid == 21                 # CHP_TOP
    @test ld.frames[q.top_frame].base - qid == 31 && ld.frames[q.frame].base - qid == 39
    @test ld.lTop - qid == 47 + 1                               # the frame's argument
    @test LK.PL_current_query(ld) == qid && LK.parentFrame(ld, q.top_frame) == 0
    tref(p) = (t=LK.PL_new_term_ref(ld); LK.PL_reset_term_refs(ld, t); t - qid)
    @test _ynext(p[:f], qid) == 1 && tref(p) == 63              # non-deterministic: a choice point
    @test _ynext(p[:f], qid) == 1 && tref(p) == 63
    @test _ynext(p[:f], qid) == 2 && tref(p) == 45              # deterministic: lTop to the frame
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    for (pr, args, want) in ((:f, (_ys(:z),), 61), (:h, (_ys(:q), X), 69))   # S_STATIC's quirk
        qid, _, fid = _yopen(p[pr], args...)
        @test _ynext(p[pr], qid) == 0 && tref(p) == want
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    # a query opened while another's answer is current lies 63 above it
    q1, a1, fid1 = _yopen(p[:f], X)
    @test _ynext(p[:f], q1) == 1
    q2, _, fid2 = _yopen(p[:g], _yv(2))
    @test q2 - q1 == 63 + 1 + LK.SIZEOF_FLIFRAME                # its foreign frame and argument
    LK.PL_close_query(ld, q2)
    LK.PL_close_foreign_frame(ld, fid2)
    LK.PL_close_query(ld, q1)
    LK.PL_close_foreign_frame(ld, fid1)
end

@testset "nested queries: only the innermost may be advanced, cut or closed" begin
    db, p = _ydb()
    ld = db.ld
    X, Y = _yv(1), _yv(2)
    q1, a1, fid1 = _yopen(p[:f], X)
    @test _ynext(p[:f], q1) == 1
    q2, a2, fid2 = _yopen(p[:g], Y)
    @test LK.PL_current_query(ld) == q2
    @test _ynext(p[:f], q1) == LK.PL_S_NOT_INNER
    @test LK.PL_cut_query(ld, q1) == LK.PL_S_NOT_INNER
    @test LK.PL_close_query(ld, q1) == LK.PL_S_NOT_INNER
    @test _ynext(p[:g], q2) == 2 && lk_eq(_yval(p[:g], a2), _ys(:only))
    @test LK.PL_close_query(ld, q2) == 1
    LK.PL_close_foreign_frame(ld, fid2)
    @test LK.PL_current_query(ld) == q1
    @test _ynext(p[:f], q1) == 1 && lk_eq(_yval(p[:f], a1), _ys(:b))
    @test LK.PL_cut_query(ld, q1) == 1
    @test lk_eq(_yval(p[:f], a1), _ys(:b))                      # cut keeps the bindings
    LK.PL_close_foreign_frame(ld, fid1)
    @test LK.PL_current_query(ld) == 0
end

@testset "cut keeps the bindings, close undoes them; after a deterministic last answer" begin
    db, p = _ydb()
    ld = db.ld
    X = _yv(1)
    qid, a, fid = _yopen(p[:f], X)
    @test _ynext(p[:f], qid) == 1
    @test LK.PL_close_query(ld, qid) == 1 && kind(_yval(p[:f], a)) === VAR
    LK.PL_close_foreign_frame(ld, fid)
    qid, a, fid = _yopen(p[:g], X)
    @test _ynext(p[:g], qid) == 2
    @test LK.PL_cut_query(ld, qid) == 1 && lk_eq(_yval(p[:g], a), _ys(:only))
    LK.PL_close_foreign_frame(ld, fid)
    LK.Undo!(ld, LK.mark(0))
    # the next call after a deterministic last answer undoes it and fails — and leaves no foreign
    # frame open, so no term reference can be made until the query is closed (swipl: fatal)
    qid, a, fid = _yopen(p[:g], X)
    @test _ynext(p[:g], qid) == 2
    @test _ynext(p[:g], qid) == 0 && kind(_yval(p[:g], a)) === VAR
    @test_throws ErrorException LK.PL_new_term_ref(ld)
    @test LK.PL_close_query(ld, qid) == 1
    @test LK.PL_new_term_ref(ld) > 0                            # the caller's frame is current again
    LK.PL_close_foreign_frame(ld, fid)
    # a closed query: PL_next_solution fails (its frame not reused — all upstream guarantees)
    @test _ynext(p[:g], qid) == 0
end

@testset "an uncaught exception: the error term, and PL_Q_PASS_EXCEPTION" begin
    db, p = _ydb()
    ld = db.ld
    pr = ix_pred(_Y, :oc, 2; db=db)
    X, A = _yv(101), _yv(1)
    ix_assertz!(pr, _yf(:oc, X, _yf(:f, X)))                    # oc(X, f(X)) called as oc(A, A)
    ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_ERROR
    qid, a, fid = _yopen(pr, A, A; flags=LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS)
    @test _ynext(pr, qid) == LK.PL_S_EXCEPTION
    ex = LK.PL_exception(ld, qid)
    e = LK.resolve_term(ld, ld.slots[ex + 1])
    @test lk_name(child(e, 1)) === :error &&
        lk_name(child(child(e, 2), 1)) === :occurs_check
    ctx = child(e, 3)
    @test lk_name(child(ctx, 1)) === :context && kind(child(ctx, 3)) === VAR
    @test lk_eq(child(ctx, 2), _yf("/", _ys(:oc), _yg(2)))
    @test ld.exception_term == 0                                # PL_Q_CATCH_EXCEPTION: cleared
    @test _ynext(pr, qid) == 0                                  # the query is over
    @test LK.PL_close_query(ld, qid) == 1
    LK.PL_close_foreign_frame(ld, fid)
    qid, a, fid = _yopen(pr, A, A; flags=LK.PL_Q_PASS_EXCEPTION)
    @test _ynext(pr, qid) == 0                                  # no PL_Q_EXT_STATUS: false
    @test LK.PL_exception(ld, qid) != 0 && ld.exception_term != 0    # passed on: still pending
    @test LK.PL_close_query(ld, qid) == 1
    LK.PL_close_foreign_frame(ld, fid)
    ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_FALSE
end

@testset "the except arm: re-entering the run loop with an exception pending" begin
    db, p = _ydb()
    ld = db.ld
    # the exception is raised in the caller's foreign frame (a running query's frame has none above
    # it before its first answer — PL_new_term_ref refuses there, as upstream)
    fid0 = LK.PL_open_foreign_frame(ld)
    b = LK.PL_new_term_ref(ld)
    ld.slots[b + 1] = _yf(:error, _ys(:boom), _yv(2))
    LK.PL_raise_exception(ld, b)
    @test ld.exception_term == ld.exception_bin
    qid, a, fid = _yopen(p[:f], _yv(1); flags=LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS)
    @test_throws ErrorException LK.PL_new_term_ref(ld)          # no foreign frame above the query's
    @test LK.PL_next_solution_guarded(db.gd, ld, qid, true) == LK.PL_S_EXCEPTION
    @test lk_eq(LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]),
        _yf(:error, _ys(:boom), _yv(2)))
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    LK.PL_close_foreign_frame(ld, fid0)
end

@testset "a Julia exception ends the query and is rethrown" begin
    db, p = _ydb()
    ld = db.ld
    ld.stacks_limit = ld.lMax                                   # no growth past here
    fid = LK.PL_open_foreign_frame(ld)
    LK.PL_new_term_refs(ld, ld.lMax - ld.lTop - (LK.SIZEOF_QUERYFRAME + LK.MAXARITY) - 1)
    a = LK.PL_new_term_ref(ld)
    ld.slots[a + 1] = _yv(1)
    qid = LK.PL_open_query(db.gd, ld, nothing, LK.PL_Q_NORMAL, p[:f].proc, a)
    @test qid != 0
    @test_throws LK.LocalStackOverflow LK.PL_next_solution(db.gd, ld, qid)  # S_STATIC's space
    @test ld.query == 0 && ld.lTop == qid && ld.nqueries == 0  # closed, its records dropped
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "an instruction the run loop does not hold is refused by name; the query is closed" begin
    db, p = _ydb()
    ld = db.ld
    r = ix_pred(_Y, :r, 1; db=db)
    cl = LK.compileClause(
        db.gd, _yf(:r, _yv(1)), _yf(:f, _yv(1)), r.proc, LK.MODULE_user(db.gd)
    )
    LK.assertDefinition!(db.gd, r.def, cl, LK.CL_END)       # r(X) :- f(X).   I_ENTER first
    @test LK.decode(LK.Code(cl, 1)) == LK.I_ENTER
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_ref(ld)
    qid = LK.PL_open_query(db.gd, ld, nothing, LK.PL_Q_NORMAL, r.proc, a)
    err = try
        LK.PL_next_solution(db.gd, ld, qid)
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError && occursin("I_ENTER", err.what)
    @test ld.query == 0 && ld.lTop == qid && ld.nqueries == 0  # closed, its records dropped
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "two clauses with rational first arguments: no key, S_STATIC, both answers (upstream aborts)" begin
    # docs/upstream_reports.md #4: swipl 10.1.16 ABORTS on the first call of `p(1r3, a). p(2r3, b).` —
    # pl-comp.c `arg1Key` lists H_MPZ but not H_MPQ, so `listSupervisor` reaches its `assert(0)`.
    # The kernel treats H_MPQ as H_MPZ (DIVERGES): no key, so the predicate gets S_STATIC.
    Q = lk_term_type(Union{Int64, Rational{BigInt}})
    db = IxDB{Q}()
    p = ix_pred(Q, :p, 2; db=db)
    pq(x, y) = mk_expr(Q, Q[lk_sym(Q, :p), x, y])
    ix_assertz!(p, pq(lk_gnd(Q, Rational{BigInt}(1, 3)), lk_sym(Q, :a)))
    ix_assertz!(p, pq(lk_gnd(Q, Rational{BigInt}(2, 3)), lk_sym(Q, :b)))
    pc = LK.Code(p.def.impl_clauses.first_clause.clause, 1)
    @test LK.decode(pc) == LK.H_MPQ
    @test LK.arg1Key(pc) == (false, LK.word(0))
    ans = vm_call(p, pq(mk_var(Q, UInt64(1)), mk_var(Q, UInt64(2))))
    @test [lk_name(child(t, 3)) for (t, _) in ans] == [:a, :b]
    @test last.(ans) == [false, true]                           # the last answer is deterministic
    @test p.def.codes === p.def.code_data.staticp              # no list supervisor
end

@testset "clause GC while a query runs through a retracted clause" begin
    db, p = _ydb()
    ld, gd = db.ld, db.gd
    X = _yv(1)
    qid, a, fid = _yopen(p[:d], X)
    @test _ynext(p[:d], qid) == 1 && lk_eq(_yval(p[:d], a), _yg(1))
    @test length(ix_retract!(p[:d], _yf(:d, _yg(2)); after=_ -> false)) == 1
    # A clause erased in the CURRENT generation is never garbage (`ddi_is_garbage`: erased >= start),
    # so the generation is moved past d(2)'s erasure first — after that only a frame can keep it.
    e = ix_pred(_Y, :e, 1; dynamic=true, db=db)
    ix_assertz!(e, _yf(:e, _ys(:a)))
    @test p[:d].def.impl_clauses.first_clause.next.clause.generation_erased <
        LK.global_generation(gd)
    ix_gc!(db)                                                  # the frame scan keeps d(2)
    # …in the clause list, erased but not reclaimed. The answers below cannot show this: the choice
    # point holds d(2)'s reference, and a reclaimed clause is only unlinked here, never freed.
    @test p[:d].def.impl_clauses.erased_clauses == 1
    @test _ynext(p[:d], qid) == 1 && lk_eq(_yval(p[:d], a), _yg(2))   # the logical update view
    @test _ynext(p[:d], qid) == 2 && lk_eq(_yval(p[:d], a), _yg(3))
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    ix_gc!(db)                                                  # no frame runs it now
    @test p[:d].def.impl_clauses.erased_clauses == 0            # reclaimed
    @test p[:d].def.impl_clauses.number_of_clauses == 2
    @test [lk_value(child(t, 2)) for (t, _) in vm_call(p[:d], _yf(:d, X))] == [1, 3]
end

@testset "the builder: write mode builds the compound; reset with the argument stack" begin
    db, p = _ydb()
    ld = db.ld
    w = ix_pred(_Y, :w, 2; db=db)
    ix_assertz!(
        w, _yf(:w, _yf(:f, _ys(:a), _yf(:g, _yv(101)), _ylist(_ys(:b), _yv(102))), _ys(:x))
    )
    ix_assertz!(w, _yf(:w, _yf(:f, _ys(:c), _yv(103), _yv(104)), _ys(:y)))
    X = _yv(1)
    ans = vm_call(w, _yf(:w, X, _ys(:y)))                       # clause 1 builds, then fails on x/y
    @test length(ans) == 1
    @test lk_eq(child(first(first(ans)), 2), _yf(:f, _ys(:c), _yv(103), _yv(104))) ||
        lk_name(child(child(first(first(ans)), 2), 2)) === :c
    @test ld.aTop == 0 && ld.nbframes == 0 && ld.bTop == 0      # reset, as the argument stack
    ans = vm_call(w, _yf(:w, X, _ys(:x)))
    t = child(first(first(ans)), 2)
    @test lk_name(child(t, 1)) === :f && lk_name(child(t, 2)) === :a
    @test lk_name(child(child(t, 3), 1)) === :g && kind(child(child(t, 3), 2)) === VAR
    @test is_pair(child(t, 4)) && lk_name(child(child(t, 4), 2)) === :b
    # A head failing INSIDE a nested compound, in read mode: `H_FUNCTOR`'s argument-stack entries are
    # still pushed when the head fails inside f/2, so the stack is reset at `unify_backtrack` — read at
    # the next answer, while the query is open (`restore_after_query` resets it at the close anyway).
    # The builder's heights are reset with it; no instruction can fail while a builder frame is open
    # (write mode never fails under `false`, and `true`/`error` build no frame), so they are already
    # back at that point.
    # (A repeated variable, so no index can skip clause 1: `f(A, A)` fails at `H_VAR` against `f(a, b)`.)
    v = ix_pred(_Y, :v, 2; db=db)
    ix_assertz!(v, _yf(:v, _yf(:f, _yv(201), _yv(201)), _ys(:x)))
    ix_assertz!(v, _yf(:v, _yf(:f, _yv(202), _yv(203)), _ys(:y)))
    @test LK.decode(
        LK.stepPC(LK.stepPC(LK.Code(v.def.impl_clauses.first_clause.clause, 1)))
    ) ==
        LK.H_VAR
    Y = _yv(2)
    qid, a, fid = _yopen(v, _yf(:f, _ys(:a), _ys(:b)), Y)
    @test _ynext(v, qid) == LK.PL_S_LAST && lk_eq(_yval(v, a + 1), _ys(:y))
    q = ld.queries[LK.QueryFromQid(ld, qid)]
    @test ld.aTop == q.aSave && ld.nbframes == q.bSave && ld.bTop == q.bcSave
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

LK_TERM_IMPL == "reference" &&
    @testset "warm, the argument-stack push and the register save allocate nothing" begin
        db, p = _ydb()
        ld = db.ld
        e = LK.argstack_entry{_Y}(LK.argp_t{_Y}(LK.ARGP_SLOT, 7, ld.placeholder), false, 0)
        push!(n) = (
            for _ in 1:n
                LK.pushArgumentStack(ld, e)
            end;
            ld.aTop=0;
            nothing
        )
        push!(10)
        @test @allocated(push!(10)) == 0
        qid, a, fid = _yopen(p[:f], _yv(1))
        save() = LK._save_registers!(
            ld, qid, 3, e.argp, ld.null_code.codes, ld.null_code.literals, 5
        )
        load() = (LK._load_registers!(ld, qid); nothing)
        save(), load()
        @test @allocated(save()) == 0 && @allocated(load()) == 0
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
