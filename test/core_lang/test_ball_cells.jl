# ORIGINAL: L1e step e5 — the ball on the CELLS (pl-fli.c copy_exception + PL_raise_exception's freezeGlobal,
# pl-incl.h Undo/DiscardMark with frozen_bar; src/pl-fli.jl, src/pl-inline.jl; audit D-0029 option (b): the frozen
# region released when the outermost query ends — `_release_frozen!`, until G1's collector). The workspace's
# L1_plan/stageL1e_design.md §5. test/core_lang/test_ball_cells.jl — on every term type:
#   * a differential against swipl: an atomic ball, a compound with variables (fresh in the catcher), a CYCLIC
#     ball, a ball made after a choice point and caught below it, a nested re-throw, a built-in's error term, a
#     throw/catch loop through backtracking;
#   * white-box (D-0029 condition 3): after a throw `frozen_bar` covers the ball; an `Undo!` to an older mark keeps
#     the ball intact; after the OUTERMOST query closes the frozen bar is 0 and `gTop` is back at its base — through
#     backtracking and through recursion; A-0029's baseline pinned (recursion: 34 cells per iteration until the
#     close; backtracking: 0);
#   * condition 2: the release refuses when a live term reference points above its target.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_bl_k(i) = _rg(Int64(i))
"`name(R) :- body, R = …`"
_bl_c(name, body) = (_rf(name, _rv(9)), body)

function _bl_clauses()
    X, Y, R, B, C = _rv(1), _rv(2), _rv(9), _rv(3), _rv(4)
    th(t) = _rf("throw", t)
    ca(g, c, r) = _rf("catch", g, c, r)
    L, H, L1 = _rv(6), _rv(7), _rv(8)
    return Tuple{_R, Union{Nothing, _R}}[
        # btw/3: between/3 as clauses (the harness loads no library)
        (_rf("btw", L, H, L), _rf("=<", L, H)),
        (
            _rf("btw", L, H, X),
            _rconj(
                _rf("<", L, H), _rf("is", L1, _rf("+", L, _bl_k(1))), _rf("btw", L1, H, X)
            )
        ),
        _bl_c("ta", ca(th(_rs("a")), R, _rs("true"))),
        _bl_c(
            "tc",
            ca(th(_rf("f", X, _rf("g", X), _rlist(_bl_k(1), _bl_k(2)))), R, _rs("true"))
        ),
        # a cyclic ball: its copy is a rational tree equal to f(itself)
        _bl_c(
            "tcyc",
            _rconj(_rf("=", X, _rf("f", X)), ca(th(X), B, _rs("true")),
                _rf("=", B, _rf("f", C)),
                _rite(_rf("==", C, B), _rf("=", R, _rs("cyclic")), _rf("=", R, _rs("not")))
            )
        ),
        # made after a choice point (between/3 leaves one), caught below it
        _bl_c(
            "tcp",
            ca(
                _rconj(_rf("btw", _bl_k(1), _bl_k(3), X), _rf(">", X, _bl_k(1)),
                    th(_rf("found", X))), _rf("found", R), _rs("true"))
        ),
        _bl_c(
            "tre",
            ca(ca(th(_rs("inner")), _rs("outer"), _rf("=", R, _rs("wrong"))), _rs("inner"),
                _rf("=", R, _rs("caught_inner")))
        ),
        _bl_c(
            "terr",
            ca(
                _rf("is", X, _rf("+", _rs("foo"), _bl_k(1))),
                _rf("error", R, Y),
                _rs("true")
            )
        ),
        _bl_c(
            "tbt",
            _ror(
                _rconj(_rf("btw", _bl_k(1), _bl_k(50), X),
                    ca(th(_rf("f", Y, _rlist(_bl_k(1), _bl_k(2)))), _rv(5), _rs("true")),
                    _rs("fail")),
                _rf("=", R, _rs("done")))
        )
    ]
end

@testset "the ball on cells, as swipl" begin
    goals = _R[_rf(n, _rv(60)) for n in ("ta", "tc", "tcyc", "tcp", "tre", "terr", "tbt")]
    ours = _rlines(_rdb(_bl_clauses()), goals)
    @test count(==("end"), ours) == length(goals)
    @test "tcyc(cyclic) det" in ours && "tbt(done) det" in ours
    if _R_SWIPL
        theirs = _rswipl(_bl_clauses(), goals)
        @test ours == theirs
        ours == theirs || @info "ball differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

const _BL_LOOP = """
bl_rec(0) :- !.
bl_rec(N) :- catch(throw(f(_X, [1,2,3], g(a))), _, true), N1 is N - 1, bl_rec(N1).
bl_bt(N) :- btw(1, N, _), catch(throw(f(_X, [1,2,3], g(a))), _, true), fail.
bl_bt(_).
btw(L, H, L) :- L =< H.
btw(L, H, X) :- L < H, L1 is L + 1, btw(L1, H, X).
"""

"Run `goal(n)` as the outermost query: (rc, gTop growth at the answer, gTop growth after the close, frozen_bar after)."
function _bl_run(gd, ld, goal::Symbol, n::Int)
    proc = LK.lookupProcedure(lk_sym(_R, goal), 1, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, _bl_k(n))
    g0 = ld.gTop
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    during = ld.gTop - g0
    LK.PL_close_query(ld, qid)
    after = ld.gTop - g0
    fb = ld.frozen_bar
    LK.PL_discard_foreign_frame(ld, fid)
    return rc, during, after, fb
end

@testset "D-0029 condition 3: the frozen region released at the outermost close; A-0029's baseline pinned" begin
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    f = joinpath(mktempdir(), "bl.pl")
    write(f, _BL_LOOP)
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    for (goal, n, want_during) in
        ((:bl_rec, 100, 3400), (:bl_rec, 1000, 34000), (:bl_bt, 100, nothing),
        (:bl_bt, 1000, nothing))
        rc, during, after, fb = _bl_run(gd, ld, goal, n)
        @test rc == LK.PL_S_TRUE
        want_during === nothing || @test during == want_during     # recursion: A-0029's 34 cells/iteration
        @test after <= 0                                            # back at the base after the close
        @test fb == 0                                               # the frozen bar released
    end
end

@testset "white-box: the throw freezes the ball; an Undo! to an older mark keeps it" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    m = LK.Mark(ld)                                  # older than the ball
    t = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, t + 1, _rf("ball", _rv(1), _rlist(_bl_k(7))))
    @test !LK.PL_raise_exception(ld, t)
    @test ld.frozen_bar >= ld.gTop - 0 && ld.frozen_bar > m.globaltop
    gbin = ld.gTop
    LK.Undo!(ld, m)
    @test ld.gTop == gbin                            # max(frozen_bar, m.globaltop): the ball stays
    r = LK.resolve_term(ld, LK.slotValue(ld, ld.exception_bin + 1))
    @test kind(r) === EXPR && nchildren(r) == 3
    LK.DiscardMark(ld, m)
    @test ld.mark_bar >= ld.frozen_bar
end

@testset "D-0029 condition 2: the release refuses a live reference above its target" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    m = LK.Mark(ld)
    t = LK.PL_new_term_ref(ld)                       # a fresh cell ABOVE m.globaltop, referenced by t
    LK.freezeGlobal!(ld)
    @test ld.query == 0 && ld.exception_term == 0
    @test_throws ErrorException LK._release_frozen!(ld, m, true)
end

# ── e5b: classify_exception on the words, against the term path, every class ───────────────────
@testset "e5b: classify_exception on the words agrees with classify_exception_p; no cold traffic" begin
    balls = _R[
        _rs("a"), _rs("time_limit_exceeded"),
        _rf("error", _rf("type_error", _rs("x"), _rs("y")), _rv(1)),
        _rf("error", _rf("resource_error", _rs("memory")), _rv(2)),
        _rf("error", _rs("plain"), _rv(3)),
        _rf("time_limit_exceeded", _bl_k(1)), _rf("unwind", _rs("abort")),
        _rf("unwind", _rf("halt", _bl_k(0))), _rf("unwind", _rf("thread_exit", _rs("x"))),
        _rf("unwind", _rs("foo")), _rf("f", _rs("x")), _bl_k(42), _rv(4)
    ]
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(balls))
    pvm = LK.PutVarMap()
    for (i, b) in enumerate(balls)
        LK.putSlotValue!(ld, t + i, b, pvm)
    end
    c0 = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
    got = [LK.classify_exception(ld, t + i - 1) for i in eachindex(balls)]
    @test (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs) == c0
    want = [LK.classify_exception_p(ld, LK.slotValue(ld, t + i)) for i in eachindex(balls)]
    @test got == want
    @test got == [LK.EXCEPT_OTHER, LK.EXCEPT_TIMEOUT, LK.EXCEPT_ERROR, LK.EXCEPT_RESOURCE,
        LK.EXCEPT_ERROR,
        LK.EXCEPT_TIMEOUT, LK.EXCEPT_ABORT, LK.EXCEPT_HALT, LK.EXCEPT_THREAD_EXIT,
        LK.EXCEPT_UNWIND,
        LK.EXCEPT_OTHER, LK.EXCEPT_OTHER, LK.EXCEPT_NONE]
end
