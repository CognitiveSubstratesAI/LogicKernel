# ORIGINAL: L1b stage D — the trail holds upstream's entry words (pl-data.h `TAG_TRAILADDR`/`TAG_TRAILVAL`) and `Undo!` is pl-wam.c's `__do_undo`, value branch included; upstream tests the trail only through its VM.
# test/core_lang/test_trail_words.jl — white-box, on every term type (the L1 plan's D list):
#   * the entry encoding: an address entry at global positions 1, 2^27 and the last has bit 0 clear
#     and decodes to its (stack, position); a value entry has bit 0 set and names the saved value's
#     position (until L1f f3 also a keyed variable's entry, naming its `trail_keys` slot);
#   * a value entry PLANTED by hand above its address entry (nothing pushes one yet: no setarg/3,
#     no attributed variables): `Undo!` restores the old value from the global stack, resets the
#     address entries below it, and leaves the trail and `gTop` at the mark (`gTop = m.globaltop`:
#     upstream's `max(frozen_bar, …)` waits for `frozen_bar`, L1e);
#   * a bound cell's entry names its position (`_bind_const!`); the keyed variables' entries and
#     `trail_keys` went in L1f f3.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW = lk_term_type(Union{Int64, Float64, String})
_tw_sym(n) = lk_sym(_TW, Symbol(n))
_tw_aw(ld, n) = LK._atom_word!(ld, _tw_sym(n))

@testset "the entry encoding: address and value entries, bit 0 the tag" begin
    last = Int(typemax(UInt64) >> 3)
    for p in (1, 2^27, last)
        e = LK._trail_addr(p, LK.TRAIL_GLOBAL)
        @test !LK.isTrailVal(e) && e & LK.TAG_TRAILMASK == LK.TAG_TRAILADDR
        @test LK._trail_stack(e) == LK.TRAIL_GLOBAL && LK._trail_pos(e) == p
        v = LK.tagTrailPtr(p)
        @test LK.isTrailVal(v) && LK.trailValP(v) == p
    end
end

@testset "a bound cell's entry names its position" begin
    ld = LK.PL_local_data{_TW}(LK.PL_global_data{_TW}())
    old = LK.allocGlobalCells!(ld, 1)
    m = LK.Mark(ld)
    LK._bind_const!(ld, old, _tw_aw(ld, :a))               # older than the mark: trailed
    e = ld.trail[end]
    @test LK._trail_stack(e) == LK.TRAIL_GLOBAL && LK._trail_pos(e) == old
    LK.Undo!(ld, m)
    @test ld.gstack[old] == 0
end

@testset "a planted value entry: Undo! restores the old value; the trail and gTop return to the mark" begin
    ld = LK.PL_local_data{_TW}(LK.PL_global_data{_TW}())
    x = LK.allocGlobalCells!(ld, 1)
    y = LK.allocGlobalCells!(ld, 1)
    LK._bind_const!(ld, x, _tw_aw(ld, :old))               # x's value before the assignment
    oldword = ld.gstack[x]
    m = LK.Mark(ld)
    LK._bind_const!(ld, y, _tw_aw(ld, :z))                 # an ordinary binding below the pair
    # TrailAssignment(p), by hand: the old value saved at gTop, then the address and value entries
    gsave = LK.allocGlobalCells!(ld, 1)                    # a word of the global stack to save in
    ld.gstack[gsave] = oldword
    push!(ld.trail, LK._trail_addr(x, LK.TRAIL_GLOBAL))
    push!(ld.trail, LK.tagTrailPtr(gsave))
    ld.gstack[x] = _tw_aw(ld, :new)                        # the destructive assignment
    LK.Undo!(ld, m)
    @test ld.gstack[x] == oldword                          # *tt->address = trailVal(p)
    @test ld.gstack[y] == 0                                # the address entry below: reset
    @test length(ld.trail) == m.trailtop && ld.gTop == m.globaltop
end
