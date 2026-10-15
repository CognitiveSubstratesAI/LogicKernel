# ORIGINAL: L1b stage D — the trail holds upstream's entry words (pl-data.h `TAG_TRAILADDR`/`TAG_TRAILVAL`) and `Undo!` is pl-wam.c's `__do_undo`, value branch included; upstream tests the trail only through its VM.
# test/core_lang/test_trail_words.jl — white-box, on every term type (the L1 plan's D list):
#   * the entry encoding: an address entry at global positions 1, 2^27 and the last has bit 0 clear
#     and decodes to its (stack, position); a keyed variable's entry names its `trail_keys` slot; a
#     value entry has bit 0 set and names the saved value's position;
#   * a value entry PLANTED by hand above its address entry (nothing pushes one yet: no setarg/3,
#     no attributed variables): `Undo!` restores the old value from the global stack, resets the
#     address entries below it, and leaves the trail and `gTop` at the mark (`gTop = m.globaltop`:
#     upstream's `max(frozen_bar, …)` waits for `frozen_bar`, L1e);
#   * a keyed variable's entries keep `trail_keys` in step through `Undo!` and `_trail_truncate!`;
#   * the readers that build a trailed variable decode the entry (`_trail_key`), and unifiable/3's
#     reader takes a planted value entry as its cell's pair and restores the old value, as upstream's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW = lk_term_type(Union{Int64, Float64, String})
_tw_sym(n) = lk_sym(_TW, Symbol(n))
_tw_var(k::UInt64) = mk_var(_TW, k)

@testset "the entry encoding: address and value entries, bit 0 the tag" begin
    last = Int(typemax(UInt64) >> 3)
    for p in (1, 2^27, last)
        e = LK._trail_addr(p, LK.TRAIL_GLOBAL)
        @test !LK.isTrailVal(e) && e & LK.TAG_TRAILMASK == LK.TAG_TRAILADDR
        @test LK._trail_stack(e) == LK.TRAIL_GLOBAL && LK._trail_pos(e) == p
        k = LK._trail_addr(p, LK.TRAIL_KEYED)
        @test !LK.isTrailVal(k) && LK._trail_stack(k) == LK.TRAIL_KEYED &&
            LK._trail_pos(k) == p
        v = LK.tagTrailPtr(p)
        @test LK.isTrailVal(v) && LK.trailValP(v) == p
    end
end

@testset "Trail!: a cell's entry names its position, a keyed variable's its key" begin
    ld = LK.PL_local_data{_TW}(LK.PL_global_data{_TW}())
    old = LK.allocGlobalVars!(ld, 1)
    m = LK.Mark(ld)
    LK.Trail!(ld, old, _tw_sym(:a))                        # older than the mark: trailed
    e = ld.trail[end]
    @test LK._trail_stack(e) == LK.TRAIL_GLOBAL && LK._trail_pos(e) == LK._cell_pos(ld, old)
    @test LK._trail_key(ld, e) == old
    keyed = UInt64(41)
    LK.Trail!(ld, keyed, _tw_sym(:b))
    k = ld.trail[end]
    @test LK._trail_stack(k) == LK.TRAIL_KEYED && ld.trail_keys[LK._trail_pos(k)] == keyed
    @test LK._trail_key(ld, k) == keyed
    LK.Undo!(ld, m)
    @test isempty(ld.trail_keys) && kind(LK.deRef(ld, _tw_var(keyed))) === VAR
    @test kind(LK.deRef(ld, _tw_var(old))) === VAR
end

@testset "a planted value entry: Undo! restores the old value; the trail and gTop return to the mark" begin
    ld = LK.PL_local_data{_TW}(LK.PL_global_data{_TW}())
    x = LK.allocGlobalVars!(ld, 1)
    y = LK.allocGlobalVars!(ld, 1)
    LK.Trail!(ld, x, _tw_sym(:old))                         # x's value before the assignment
    px = LK._cell_pos(ld, x)
    oldword = ld.gstack[px]
    m = LK.Mark(ld)
    LK.Trail!(ld, y, _tw_sym(:z))                           # an ordinary binding below the pair
    # TrailAssignment(p), by hand: the old value saved at gTop, then the address and value entries
    save = LK._vword!(ld, _tw_sym(:unused))                 # a word of the global stack to save in
    gsave = ld.gTop
    ld.gstack[gsave] = oldword
    push!(ld.trail, LK._trail_addr(px, LK.TRAIL_GLOBAL))
    push!(ld.trail, LK.tagTrailPtr(gsave))
    LK._set_binding!(ld, x, _tw_sym(:new))                  # the destructive assignment
    @test lk_eq(LK.deRef(ld, _tw_var(x)), _tw_sym(:new))
    LK.Undo!(ld, m)
    @test ld.gstack[px] == oldword                          # *tt->address = trailVal(p)
    @test lk_eq(LK.deRef(ld, _tw_var(x)), _tw_sym(:old))
    @test kind(LK.deRef(ld, _tw_var(y))) === VAR            # the address entry below: reset
    @test length(ld.trail) == m.trailtop && ld.gTop == m.globaltop
    @test save != 0
end

@testset "_trail_truncate! drops entries without undoing them, trail_keys in step" begin
    ld = LK.PL_local_data{_TW}(LK.PL_global_data{_TW}())
    n = length(ld.trail)
    LK.Trail!(ld, UInt64(7), _tw_sym(:a))
    LK.Trail!(ld, UInt64(8), _tw_sym(:b))
    @test length(ld.trail_keys) == 2
    LK._trail_truncate!(ld, n)
    @test length(ld.trail) == n && isempty(ld.trail_keys)
    @test lk_eq(LK.deRef(ld, _tw_var(UInt64(7))), _tw_sym(:a))   # still bound: not undone
    delete!(ld.bindings, UInt64(7))
    delete!(ld.bindings, UInt64(8))
end
