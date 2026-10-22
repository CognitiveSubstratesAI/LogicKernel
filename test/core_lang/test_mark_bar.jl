# ORIGINAL: unit tests of L1a's global stack of variables and upstream's conditional trailing (pl-incl.h `Mark`, `DiscardMark`, `Undo`, `NO_MARK_BAR`; pl-inline.h `Trail`); upstream exercises them only through its VM.
# test/core_lang/test_mark_bar.jl — cell variables and `mark_bar` (the workspace's L1 plan, L1a):
#   * `Mark` sets `mark_bar` to `gTop` and `DiscardMark` restores the bar it replaced; under
#     `NO_MARK_BAR` neither moves it;
#   * a cell allocated since the newest mark is bound WITHOUT a trail entry (backtracking frees the
#     cell itself), an older cell WITH one, a keyed variable always;
#   * `Undo!` unbinds the trailed cells and frees the cells allocated since the mark; a key retained
#     past that names no cell — it is a keyed variable, not the cell that reuses its position;
#   * the readers of the trail keep seeing every binding: unifiable/3 over fresh cells.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MB = lk_term_type(Union{Int64, Float64, String})
_mb_sym(n) = lk_sym(_MB, Symbol(n))
_mb_var(k::UInt64) = mk_var(_MB, k)

@testset "mark_bar: Mark sets it, DiscardMark restores it" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    # emptyStacks sets LD->mark_bar = gTop BEFORE it makes the exception term references, which
    # upstream puts on the local stack and L1a on the global one — so they lie above the bar
    # exception_bin, _printed, _tmp, _pending, then upstream's TMP_PTR_SIZE temporary handles
    # (pl-setup.c; f3b-4 — was gTop == 4, D-0083)
    @test ld.mark_bar == 0 && ld.gTop == 4 + LK.TMP_PTR_SIZE
    LK.allocGlobalVars!(ld, 3)
    m = LK.Mark(ld)
    @test ld.mark_bar == ld.gTop == m.globaltop
    LK.allocGlobalVars!(ld, 2)
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

@testset "Trail: a cell newer than the mark goes untrailed; an older one and a keyed variable do not" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    old = LK.allocGlobalVars!(ld, 1)
    m = LK.Mark(ld)
    new = LK.allocGlobalVars!(ld, 1)
    t0 = length(ld.trail)
    LK.Trail!(ld, new, _mb_sym(:a))
    @test length(ld.trail) == t0                        # newer than the mark: no entry
    # the boundary: the LAST cell before the mark (position == mark_bar) is older — trailed below
    LK.Trail!(ld, old, _mb_sym(:b))
    @test LK._trail_key(ld, ld.trail[end]) == old && length(ld.trail) == t0 + 1   # (L1b D: an entry)
    keyed = UInt64(7)                                   # a caller's variable
    LK.Trail!(ld, keyed, _mb_sym(:c))
    @test LK._trail_key(ld, ld.trail[end]) == keyed && length(ld.trail) == t0 + 2
    @test lk_eq(LK.deRef(ld, _mb_var(new)), _mb_sym(:a))
    @test lk_eq(LK.deRef(ld, _mb_var(old)), _mb_sym(:b))
    @test lk_eq(LK.deRef(ld, _mb_var(keyed)), _mb_sym(:c))
    LK.Undo!(ld, m)
    @test length(ld.trail) == t0 && ld.gTop == m.globaltop
    @test kind(LK.deRef(ld, _mb_var(old))) === VAR      # unbound again
    @test kind(LK.deRef(ld, _mb_var(keyed))) === VAR
    @test LK._cell_pos(ld, new) == 0                    # freed: the key names no cell
    @test kind(LK.deRef(ld, _mb_var(new))) === VAR
    reuse = LK.allocGlobalVars!(ld, 1)                  # the same position, a new stamp
    @test (reuse & LK.CELL_POS_MASK) == (new & LK.CELL_POS_MASK) && reuse != new
    LK.Trail!(ld, reuse, _mb_sym(:d))
    @test kind(LK.deRef(ld, _mb_var(new))) === VAR      # the retained key is not the new cell
    @test lk_eq(LK.deRef(ld, _mb_var(reuse)), _mb_sym(:d))
end

@testset "one allocation's keys are consecutive, and keys order by allocation" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    k = LK.allocGlobalVars!(ld, 4)
    @test all(LK._cell_pos(ld, k + UInt64(i)) == LK._cell_pos(ld, k) + i for i in 0:3)
    k2 = LK.allocGlobalVars!(ld, 1)
    @test k2 > k + UInt64(3)
    m = LK.Mark(ld)
    LK.Undo!(ld, m)
    k3 = LK.allocGlobalVars!(ld, 1)                     # reuses nothing (nothing was freed)…
    @test k3 > k2
    m = LK.Mark(ld)
    k4 = LK.allocGlobalVars!(ld, 1)
    LK.Undo!(ld, m)
    k5 = LK.allocGlobalVars!(ld, 1)                     # …this one reuses k4's position
    @test k5 > k4 > k3
end

@testset "the trail's readers see every binding: unifiable over fresh cells" begin
    ld = LK.PL_local_data{_MB}(LK.PL_global_data{_MB}())
    m = LK.Mark(ld)                                     # a choice point's mark: the bar at gTop
    k = LK.allocGlobalVars!(ld, 2)                      # both newer than the bar
    X, Y = _mb_var(k), _mb_var(k + UInt64(1))
    f(a, b) = mk_expr(_MB, _MB[_mb_sym(:f), a, b])
    bar = ld.mark_bar
    pairs = LK.unifiable(ld, f(X, _mb_sym(:b)), f(_mb_sym(:a), Y))
    @test pairs !== nothing && length(pairs) == 2       # neither binding was elided
    @test ld.mark_bar == bar                            # discarded back to the choice point's bar
    @test kind(LK.deRef(ld, X)) === VAR && kind(LK.deRef(ld, Y)) === VAR    # unifiable undoes them
    LK.Undo!(ld, m)
end
