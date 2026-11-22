# ORIGINAL: L1e step e5 — the ball on the CELLS (pl-fli.c copy_exception + PL_raise_exception's freezeGlobal,
# pl-incl.h Undo/DiscardMark with frozen_bar; src/pl-fli.jl, src/pl-inline.jl; audit D-0029 option (b): the frozen
# region released when the outermost query ends — retired by G1-E, audit D-0979 (2): upstream never lowers the bar before a thread's
# end, pl-gvar.c:62-70 at 18168e62, so the rows below pin the UPSTREAM behaviour). The workspace's
# L1_plan/stageL1e_design.md §5. test/core_lang/test_ball_cells.jl — on every term type:
#   * a differential against swipl: an atomic ball, a compound with variables (fresh in the catcher), a CYCLIC
#     ball, a ball made after a choice point and caught below it, a nested re-throw, a built-in's error term, a
#     throw/catch loop through backtracking;
#   * white-box (D-0029 condition 3, G1-E): after a throw `frozen_bar` covers the ball; an `Undo!` to an older mark keeps
#     the ball intact; the OUTERMOST query's close does NOT move the bar (`frozen_bar` unchanged, `gTop == max(frozen_bar,
#     mark.globaltop)`, pl-incl.h:2253) — through backtracking and through recursion; the ball is the COLLECTOR's: a
#     collection after the close takes `gTop` back to the base; A-0029's baseline pinned (recursion: 40 cells per
#     iteration until the close — 34 before MOD4 qualified catch/3's meta-arguments);
#   * condition 2 (G1-E): a live term reference above an `Undo!`'s mark stays valid, the bar keeps its cell (nothing refuses);
#   * ENG2 (audit D-0435), G1-E: `Undo!` over a region frozen above the mark leaves `gTop` at the bar whatever the frames'
#     headers or references hold (what mark_term_refs reads is the collector's: test_gc_mark.jl).
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

"Run `goal(n)` as the outermost query: (rc, gTop growth at the answer, gTop growth after the close, frozen_bar before the close, frozen_bar after it, gTop after it)."
function _bl_run(gd, ld, goal::Symbol, n::Int)
    proc = LK.lookupProcedure(lk_sym(_R, goal), 1, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, _bl_k(n))
    g0 = ld.gTop
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    during = ld.gTop - g0
    fb_pre = ld.frozen_bar
    LK.PL_close_query(ld, qid)
    after = ld.gTop - g0
    fb = ld.frozen_bar
    gt = ld.gTop
    LK.PL_discard_foreign_frame(ld, fid)
    return rc, during, after, fb_pre, fb, gt
end

@testset "D-0029 condition 3 (G1-E): the outermost close does not move the frozen bar; A-0029's baseline pinned" begin
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    f = joinpath(mktempdir(), "bl.pl")
    write(f, _BL_LOOP)
    st, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    # G1 chunk 8 (the collector runs at the ALLOW_GC sites): A-0029's baseline is the cost of the ball WITHOUT a collection, so it is
    # measured with the flag `gc` off (the pattern of test_gc_driver.jl), above a stack the loader's dead cells no longer fill (the first
    # collection frees them: gTop 1270 -> 20, a `during` negative otherwise). The same program with the collector ON is the next row.
    @test LK.garbageCollect(ld, Int(LK.GC_USER); vmi_state_of=LK.get_vmi_state) ==
        LK.BOOLEX_TRUE
    b0 = ld.gTop                                                    # the base: what a collection leaves with nothing live
    gc_flags = ld.prolog_flag_mask
    ld.prolog_flag_mask &= ~LK.prologFlagMask(LK.PLFLAG_GC)
    c_off = ld.gc.stats.totals.collections
    for (goal, n, want_during) in
        ((:bl_rec, 100, 4000), (:bl_rec, 1000, 40000), (:bl_bt, 100, nothing),
        (:bl_bt, 1000, nothing))
        rc, during, after, fb_pre, fb, gt = _bl_run(gd, ld, goal, n)
        @test rc == LK.PL_S_TRUE
        # recursion: 40 cells/iteration. A-0029's 34 + 6 since MOD4: catch(0, ?, 0) is a declared meta-predicate
        # (init.pl / pl-wam.c S_MQUAL), so its Goal and Recovery arguments are qualified `user:Arg` per call —
        # two colon compounds of 3 cells each. Representation only.
        want_during === nothing || @test during == want_during
        # THE UPSTREAM BEHAVIOUR (G1-E; was `after <= 0` / `fb == 0`, the e5 release): a throw froze the stack at the ball (no
        # collection ran: flag `gc` off), and the close does not lower the bar (pl-gvar.c:62-70: only a thread's end does), so Undo
        # leaves gTop = max(frozen_bar, mark.globaltop) = the bar (pl-incl.h:2253, pl-wam.c:1632): the ball stays until a collection.
        @test fb_pre > 0                                            # the throw froze the region
        @test fb == fb_pre                                          # KILL E1R: the close lowers the bar
        @test gt == fb && after > 0                                 # KILL E1R-2: the close also lowers gTop to the query's mark
    end
    @test ld.gc.stats.totals.collections == c_off                   # flag `gc` off: none ran in any of the four
    ld.prolog_flag_mask = gc_flags
    # The collector ON (what a program now gets): the loop's dead balls are reclaimed INSIDE the query (upstream's frozen_bar is
    # a root the compaction relocates, not a floor under the garbage: pl-gc.c gvars_to_term_refs / sweep_frozen_bar), so far fewer
    # than 40 cells/iteration are left at the answer. The close does not move the bar (it is the collector's to relocate), and the
    # ball it leaves is the collector's too: a collection after the close, with nothing live, takes gTop back to the base.
    c0 = ld.gc.stats.totals.collections
    rc, during, after, fb_pre, fb, gt = _bl_run(gd, ld, :bl_rec, 1000)
    @test rc == LK.PL_S_TRUE
    @test ld.gc.stats.totals.collections > c0
    @test during < 40000 ÷ 4
    @test fb == fb_pre                                              # KILL E1R: the close lowers the bar (a collection may have moved it before the close, none moves it at the close)
    @test gt >= fb                                                  # gTop never below the bar (Undo's max)
    c1 = ld.gc.stats.totals.collections
    @test LK.garbageCollect(ld, Int(LK.GC_USER); vmi_state_of=LK.get_vmi_state) ==
        LK.BOOLEX_TRUE
    @test ld.gc.stats.totals.collections > c1
    # MEASURE ON THE LANE (the exact query: print `(b0, ld.gTop, ld.frozen_bar)` here): upstream's rule gives gTop == b0 (nothing the
    # loops made is live; the base prefix is rooted by mark_base_cells, G1 E1); `<=` stands until it is measured, then `==`.
    @test ld.gTop <= b0                                             # the ball reclaimed by the collector
    @test ld.frozen_bar <= ld.gTop
end

# ENG2a (audit D-0411), G1-E: on the booted copy global variables live on the global stack (`gvar_grefs > 0` after a load). Upstream
# keeps `frozen_bar` for the thread's life, so a value made by a query, one made by an earlier query, and one made inside an open
# foreign frame all stay readable across every close and discard; a throw never releases anything (was: the e5 release scanned the
# values and freed the region when none lay above the target).
const _BL_GV = """
bl_set(K) :- nb_setval(K, h(x, y)).
bl_setv(K) :- nb_setval(K, _).
bl_thr(K) :- catch(throw(f(_X, [1,2,3], g(a))), _, true), atom(K).
bl_setthr(K) :- nb_setval(K, h(x, y)), catch(throw(f(_X, [1,2,3], g(a))), _, true).
bl_get(K, V) :- length(_, 50), nb_getval(K, V).
"""

"The goal `pred(args...)` as a term of type `T`."
_bl_gv_goal(::Type{T}, pred::String, args::T...) where {T} =
    mk_expr(T, T[mk_sym(T, Symbol(pred)), args...])

"Run `goal` on `db`: (its driver lines, `gTop` growth from before the query, `frozen_bar` after, `gTop` after)."
function _bl_gv_run(db, goal)
    g0 = db.ld.gTop
    lines = _rlines(db, [goal])
    return lines, db.ld.gTop - g0, db.ld.frozen_bar, db.ld.gTop
end

@testset "ENG2a (G1-E): the bar stays across every close, the global variables' values with it (booted copy)" begin
    db = _RDB()
    f = joinpath(mktempdir(), "blgv.pl")
    write(f, _BL_GV)
    st, _ = LK.load_file!(db.gd, db.ld, f)
    @test st === :ok
    ld = db.ld
    @test ld.gvar_grefs > 0                                         # the booted copy has values on the stack
    G(p, a...) = _bl_gv_goal(_R, p, a...)
    ours = String[]
    # (1) a value made BY the query lies above its mark: the region stays (as before), the value reads back intact
    l1, grow1, fb1, gt1 = _bl_gv_run(db, G("bl_setthr", _rs("bl_k1")))
    append!(ours, l1)
    @test grow1 > 0 && fb1 > 0 && gt1 == fb1
    l1r, _, _, _ = _bl_gv_run(db, G("bl_get", _rs("bl_k1"), _rv(60)))
    append!(ours, l1r)
    @test l1r == ["bl_get(bl_k1,h(x,y)) det", "end"]
    # (2) a value made by an EARLIER query lies below the new ball: upstream keeps the ball's region too (the e5 release freed it:
    # was `grow2 <= 0 && fb2 == 0`): the bar is the throw's gTop and the close leaves gTop at it
    l2s, _, fb2s, _ = _bl_gv_run(db, G("bl_set", _rs("bl_k2")))
    append!(ours, l2s)
    l2, grow2, fb2, gt2 = _bl_gv_run(db, G("bl_thr", _rs("bl_k2")))
    append!(ours, l2)
    @test grow2 > 0 && fb2 > fb2s && gt2 == fb2                     # KILL E1R/E1R-2: the close lowers the bar / gTop
    l2r, _, _, _ = _bl_gv_run(db, G("bl_get", _rs("bl_k2"), _rv(60)))
    append!(ours, l2r)
    @test l2r == ["bl_get(bl_k2,h(x,y)) det", "end"]
    # (3) a value made inside an open foreign frame by an earlier query: kept across the frame's discard
    fid = LK.PL_open_foreign_frame(ld)
    l3s, _, _, _ = _bl_gv_run(db, G("bl_set", _rs("bl_k3")))
    append!(ours, l3s)
    p3 = ld.frozen_bar                                              # nb_setval froze the stack above its value (was `_gvar_reach(ld)`)
    l3, _, fb3, _ = _bl_gv_run(db, G("bl_thr", _rs("bl_k3")))
    append!(ours, l3)
    @test fb3 >= p3 > 0                                             # the bar still covers the value
    LK.PL_discard_foreign_frame(ld, fid)
    @test ld.gTop >= p3
    l3r, _, _, _ = _bl_gv_run(db, G("bl_get", _rs("bl_k3"), _rv(60)))
    append!(ours, l3r)
    @test l3r == ["bl_get(bl_k3,h(x,y)) det", "end"]
    # (4) the bar is the thread's: a later query that throws nothing (reads a value) closes without moving it
    # (was the boundary rows of the release: `_release_frozen!` at `p4 - 1` kept the bar, at `p4` lowered it)
    l4s, _, _, _ = _bl_gv_run(db, G("bl_setv", _rs("bl_k4")))
    append!(ours, l4s)
    fb4 = ld.frozen_bar
    @test fb4 > 0
    @test ld.query == 0 && ld.exception_term == 0 && ld.nfliframes == 1     # only emptyStacks' base frame is open
    _, _, fb4r, gt4r = _bl_gv_run(db, G("bl_get", _rs("bl_k1"), _rv(60)))   # (not in the differential: ours only)
    @test fb4r == fb4 && gt4r == fb4                                # KILL E1R/E1R-2. MEASURE ON THE LANE: `==` assumes no collection ran in bl_get (length(_, 50))
    if _R_SWIPL
        gs = _R[G("bl_setthr", _rs("bl_k1")), G("bl_get", _rs("bl_k1"), _rv(60)),
            G("bl_set", _rs("bl_k2")),
            G("bl_thr", _rs("bl_k2")), G("bl_get", _rs("bl_k2"), _rv(60)),
            G("bl_set", _rs("bl_k3")),
            G("bl_thr", _rs("bl_k3")), G("bl_get", _rs("bl_k3"), _rv(60)),
            G("bl_setv", _rs("bl_k4"))]
        theirs = _rswipl(Tuple{_R, Union{Nothing, _R}}[], gs; extra=_BL_GV)
        @test ours == theirs
        ours == theirs || @info "ENG2a differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
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
    r = lk_answer(ld, ld.exception_bin)
    @test kind(r) === EXPR && nchildren(r) == 3
    LK.DiscardMark(ld, m)
    @test ld.mark_bar >= ld.frozen_bar
end

# D-0029 condition 2 (G1-E): the e5 release REFUSED (an error) when a live term reference pointed above its target. Upstream has no
# release, so nothing refuses: a reference above an `Undo!`'s mark keeps its cell because the bar (frozen_bar) is the floor of
# `gTop` (pl-incl.h:2253, pl-wam.c:1632). The rows pin that, white-box on the cells.
@testset "D-0029 condition 2 (G1-E): a live reference above Undo!'s mark keeps its cell, the bar the floor" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    m = LK.Mark(ld)
    t = LK.PL_new_term_ref(ld)                       # a fresh cell ABOVE m.globaltop, referenced by t
    p = LK.unRef(ld.slots[t + 1])
    @test p > m.globaltop
    LK.freezeGlobal!(ld)
    @test ld.query == 0 && ld.exception_term == 0
    bar = ld.frozen_bar
    LK.Undo!(ld, m)
    @test ld.gTop == bar && ld.frozen_bar == bar     # KILL E1R-3: the bar lowered, the cell given back
    @test p <= ld.gTop
end

# ENG2 (audit D-0435 option (a)), G1-E: the e5 release read each open foreign frame's own `size` references (pl-gc.c mark_term_refs,
# :1016-1055) to decide whether it could lower gTop. Upstream's `Undo` never decides: it keeps `max(frozen_bar, mark.globaltop)`
# whatever the frames' headers, references or marks hold; the rows pin that on the same three shapes. (The collector's own reading
# of the references, mark_term_refs, is test_gc_mark.jl's.) White-box: each row reads the kernel's stacks directly.
@testset "ENG2 (G1-E): Undo! over a frozen region leaves gTop at the bar, whatever the frames' headers and references hold" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    # (1) a frame header over dead references: a rewind drops an outer frame's references, an inner frame opens on them
    fid = LK.PL_open_foreign_frame(ld)
    m = LK.Mark(ld)
    t = LK.PL_new_term_refs(ld, 3)                   # three cells above m.globaltop
    LK.PL_rewind_foreign_frame(ld, fid)              # the references dropped, gTop back at the frame's mark …
    @test ld.gTop == m.globaltop
    @test LK.unRef(ld.slots[t + 1]) > m.globaltop    # … their old words still in the slots
    fid2 = LK.PL_open_foreign_frame(ld)              # whose header spans those slots
    @test fid2 == t && ld.lTop == t + LK.SIZEOF_FLIFRAME
    LK.allocGlobalCells!(ld, 4)                      # a region above the mark, frozen (a ball's)
    LK.freezeGlobal!(ld)
    @test ld.query == 0 && ld.exception_term == 0
    bar1 = ld.frozen_bar
    LK.Undo!(ld, m)                                  # the old release freed it (no live reference above): upstream keeps it
    @test ld.frozen_bar == bar1 > m.globaltop && ld.gTop == bar1
    LK.PL_discard_foreign_frame(ld, fid2)
    @test ld.gTop == bar1
    # (2) a live reference of an OUTER open frame above the mark: its cell is kept (the old release refused with an error)
    t2 = LK.PL_new_term_ref(ld)                      # a reference of frame `fid`
    m2 = LK.Mark(ld)
    fid3 = LK.PL_open_foreign_frame(ld)              # its mark at m2's
    p2 = LK.allocGlobalCells!(ld, 2)
    ld.slots[t2 + 1] = LK.makeRefG(p2)               # the outer reference set to a cell above the mark
    LK.freezeGlobal!(ld)
    bar2 = ld.frozen_bar
    @test p2 > m2.globaltop && ld.fliframes[ld.fli_context].size == 0
    LK.Undo!(ld, m2)
    @test ld.gTop == bar2 >= p2                      # KILL E1R-3: the bar lowered to the mark, the reference's cell given back
    LK.PL_discard_foreign_frame(ld, fid3)
    LK.PL_rewind_foreign_frame(ld, fid)
    @test ld.gTop >= bar2                            # even the outermost frame's rewind never goes below the bar
    # (3) the boundary: a live reference AT the mark (its cell the last one below it): the region frozen above it is kept
    t3 = LK.PL_new_term_ref(ld)
    m3 = LK.Mark(ld)
    @test LK.unRef(ld.slots[t3 + 1]) == m3.globaltop
    LK.allocGlobalCells!(ld, 2)
    LK.freezeGlobal!(ld)
    bar3 = ld.frozen_bar
    LK.Undo!(ld, m3)
    @test ld.frozen_bar == bar3 > m3.globaltop && ld.gTop == bar3
    LK.PL_discard_foreign_frame(ld, fid)
end

# ── e5b: classify_exception on the words, every class; its answers' round trip agrees ──────────
@testset "e5b: classify_exception on the words, every class; no cold traffic" begin
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
    c0 = ld.cold_imports                       # (f3-3: the export/variable/pair meters went with the boundary)
    got = [LK.classify_exception(ld, t + i - 1) for i in eachindex(balls)]
    @test ld.cold_imports == c0
    r = LK.PL_new_term_ref(ld)                 # f3-3: the term twin classify_exception_p went; each
    want = map(lk_answers(ld, (t:(t + length(balls) - 1))...)) do b   # answer put back and classified
        LK.putSlotValue!(ld, r + 1, b)
        LK.classify_exception(ld, r)
    end
    @test got == want
    @test got == [LK.EXCEPT_OTHER, LK.EXCEPT_TIMEOUT, LK.EXCEPT_ERROR, LK.EXCEPT_RESOURCE,
        LK.EXCEPT_ERROR,
        LK.EXCEPT_TIMEOUT, LK.EXCEPT_ABORT, LK.EXCEPT_HALT, LK.EXCEPT_THREAD_EXIT,
        LK.EXCEPT_UNWIND,
        LK.EXCEPT_OTHER, LK.EXCEPT_OTHER, LK.EXCEPT_NONE]
end
