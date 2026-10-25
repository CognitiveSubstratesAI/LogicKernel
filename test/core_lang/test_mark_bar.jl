# ORIGINAL: unit tests of L1a's global stack of variables and upstream's conditional trailing (pl-incl.h `Mark`, `DiscardMark`, `Undo`, `NO_MARK_BAR`; pl-inline.h `Trail`); upstream exercises them only through its VM.
# test/core_lang/test_mark_bar.jl — cell variables and `mark_bar` (the workspace's L1 plan, L1a):
#   * `Mark` sets `mark_bar` to `gTop` and `DiscardMark` restores the bar it replaced; under
#     `NO_MARK_BAR` neither moves it;
#   * a cell allocated since the newest mark is bound WITHOUT a trail entry (backtracking frees the
#     cell itself), an older cell WITH one (`_bind_const!`, pl-attvar.h varBindConst);
#   * `Undo!` unbinds the trailed cells and frees the cells allocated since the mark, for reuse (until
#     L1f f3 also: a key retained past that named no cell — the keyed variables went in f3);
#   * the readers of the trail keep seeing every binding: unifiable/3 over fresh cells (`unifiable_cells`).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MB = lk_term_type(Union{Int64, Float64, String})
_mb_sym(n) = lk_sym(_MB, Symbol(n))
_mb_aw(ld, n) = LK._atom_word!(ld, _mb_sym(n))

@testset "mark_bar: Mark sets it, DiscardMark restores it" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    # emptyStacks sets LD->mark_bar = gTop BEFORE it makes the exception term references, which
    # upstream puts on the local stack and L1a on the global one — so they lie above the bar
    # exception_bin, _printed, _tmp, _pending, attvar.head, attvar.tail (AV1), then upstream's
    # TMP_PTR_SIZE temporary handles (pl-setup.c; f3b-4 — was gTop == 4; AV1 — was 4 + TMP_PTR_SIZE,
    # D-0083)
    @test ld.mark_bar == 0 && ld.gTop == 6 + LK.TMP_PTR_SIZE
    LK.allocGlobalCells!(ld, 3)
    m = LK.Mark(ld)
    @test ld.mark_bar == ld.gTop == m.globaltop
    LK.allocGlobalCells!(ld, 2)
    m2 = LK.Mark(ld)
    @test ld.mark_bar == ld.gTop == m.globaltop + 2
    LK.DiscardMark(ld, m2)
    @test ld.mark_bar == m.globaltop
    LK.DiscardMark(ld, m)
    @test ld.mark_bar == m.saved_bar
    ld.mark_bar = LK.NO_MARK_BAR                        # every assignment trailed
    m3 = LK.Mark(ld)
    @test ld.mark_bar == LK.NO_MARK_BAR                 # Mark leaves NO_MARK_BAR alone
    LK.DiscardMark(ld, m3)
    @test ld.mark_bar == LK.NO_MARK_BAR
end

@testset "Trail: a cell newer than the mark goes untrailed; an older one does not" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    old = LK.allocGlobalCells!(ld, 1)
    m = LK.Mark(ld)
    new = LK.allocGlobalCells!(ld, 1)
    a, b = _mb_aw(ld, :a), _mb_aw(ld, :b)
    t0 = length(ld.trail)
    LK._bind_const!(ld, new, a)
    @test length(ld.trail) == t0                        # newer than the mark: no entry
    # the boundary: the LAST cell before the mark (position == mark_bar) is older — trailed below
    LK._bind_const!(ld, old, b)
    @test LK._trail_pos(ld.trail[end]) == old && length(ld.trail) == t0 + 1   # (L1b D: an entry)
    @test ld.gstack[new] == a && ld.gstack[old] == b
    LK.Undo!(ld, m)
    @test length(ld.trail) == t0 && ld.gTop == m.globaltop
    @test ld.gstack[old] == 0                           # unbound again
    @test ld.gTop < new                                 # freed with everything since the mark
    reuse = LK.allocGlobalCells!(ld, 1)                 # the same position, unbound
    @test reuse == new && ld.gstack[reuse] == 0
end

@testset "one allocation's cells are consecutive, and an Undo frees them for reuse" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    p = LK.allocGlobalCells!(ld, 4)
    @test ld.gTop == p + 3
    p2 = LK.allocGlobalCells!(ld, 1)
    @test p2 == p + 4
    m = LK.Mark(ld)
    LK.Undo!(ld, m)
    p3 = LK.allocGlobalCells!(ld, 1)                    # reuses nothing (nothing was freed)…
    @test p3 == p2 + 1
    m = LK.Mark(ld)
    p4 = LK.allocGlobalCells!(ld, 1)
    LK.Undo!(ld, m)
    p5 = LK.allocGlobalCells!(ld, 1)                    # …this one reuses p4's position
    @test p5 == p4 == p3 + 1
end

@testset "the trail's readers see every binding: unifiable over fresh cells" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    t = LK.PL_new_term_refs(ld, 3)
    m = LK.Mark(ld)                                     # a choice point's mark: the bar at gTop
    X, Y = mk_var(_MB, UInt64(1)), mk_var(_MB, UInt64(2))
    f(a, b) = mk_expr(_MB, _MB[_mb_sym(:f), a, b])
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, f(X, _mb_sym(:b)), pvm)   # X and Y: cells newer than the bar
    LK.putSlotValue!(ld, t + 2, f(_mb_sym(:a), Y), pvm)
    bar = ld.mark_bar
    @test LK.unifiable_cells(ld, t, t + 1, t + 2)
    @test LK.lengthList(ld, t + 2, false) == 2         # neither binding was elided
    @test ld.mark_bar == bar                            # discarded back to the choice point's bar
    x, y = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK._PL_get_arg(ld, 1, t, x) && LK._PL_get_arg(ld, 2, t + 1, y)
    @test LK.PL_is_variable(ld, x) && LK.PL_is_variable(ld, y)    # unifiable undoes them
    LK.Undo!(ld, m)
end
