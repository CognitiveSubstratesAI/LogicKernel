# ORIGINAL: white-box rows for SYNC-F, the pl-index.c slice of the sync to swipl-devel cf6960c2; upstream tests SWI against itself.
# test/db/test_index_sync_f.jl — every row is TARGET-ONLY: pin when the oracle moves to cf6960c2. The local swipl is the pin (18168e62),
# which has none of these behaviours, and none of them is an answer swipl gives (a hash bucket, an assessment, a code walk, an array's
# order): the expectations are written by hand from the TARGET's pl-index.c and, for the bucket values, computed with a Python
# transcription of the target's `hashIndex` (`CELL_VAL_SHIFT` = this kernel's `LMASK_BITS` = 7).
using Test, LogicKernel
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "index_testlib.jl"))
const _SF = lk_term_type(Union{Int64, Float64, String})

# TARGET-ONLY: pin when the oracle moves to cf6960c2. pl-index.c:177-186 `hashIndex`.
@testset "SYNC-F: hashIndex shifts the tag bits out of the key first (swipl-devel cf6960c2, TARGET-ONLY)" begin
    @test LK.LMASK_BITS == 7                  # the expected buckets below are for this layout
    ak(i) = (UInt64(i) << LK.LMASK_BITS) | UInt64(0x23)       # any tag bits: they are shifted out
    # consecutive values land in distinct buckets, in the target's order (16 buckets)
    @test [LK.hashIndex(ak(i), UInt32(16)) for i in 1:8] == UInt32[9, 3, 13, 7, 1, 11, 5, 15]
    @test LK.hashIndex(ak(100), UInt32(16)) == 12
    @test LK.hashIndex(ak(1000), UInt32(16)) == 0
    @test [LK.hashIndex(ak(i), UInt32(64)) for i in 1:3] == UInt32[39, 15, 54]
    @test [LK.hashIndex(ak(i), UInt32(4)) for i in 1:3] == UInt32[2, 0, 3]
    # the low LMASK_BITS bits do not matter: the same value under every tag hashes alike
    base = UInt64(37) << LK.LMASK_BITS
    for low in UInt64(0):UInt64(2^LK.LMASK_BITS - 1), b in (4, 16, 64, 1024)
        @test LK.hashIndex(base | low, UInt32(b)) == LK.hashIndex(base, UInt32(b))
    end
end

# TARGET-ONLY: pin when the oracle moves to cf6960c2. pl-index.c:2673-2686 `assess_remove_duplicates`.
@testset "SYNC-F: assess_remove_duplicates keeps a small table with a catch-all clause indexable (cf6960c2, TARGET-ONLY)" begin
    ia = ntuple(i -> i == 1 ? UInt8(1) : UInt8(0), LK.MAX_MULTI_INDEX)
    function assess(var_count::Int, counts::Vector{Int}, clause_count::Int)
        ks = LK.key_asm[
            LK.key_asm(UInt64(0x100 * i), UInt32(c), UInt32(0)) for (i, c) in enumerate(counts)
        ]
        a = LK.hash_assessment(ia, length(ks), length(ks), var_count, 0, 0.0f0, 0.0f0, false, ks)
        return LK.assess_remove_duplicates!(a, clause_count), a
    end
    # p(a), p(b), p(_): 1 variable clause, 2 keys, 3 clauses. 0.5 > MAX_VAR_FRAC, but 1*2 <= 3: an index
    ok, a = assess(1, [1, 1], 3)
    @test ok && a.size == 2 && a.speedup == 1.5f0 && !a.list        # 3*2 / (3-1+1*2)
    # the boundary: var_count*size == clause_count is still an index (the target's test is `>`)
    ok, a = assess(2, [1, 1], 4)
    @test ok && a.speedup == Float32(8) / Float32(6)                # 4*2 / (4-2+2*2)
    # more space than the clauses: not an index, speedup 0
    ok, a = assess(3, [1, 1], 5)                                    # 3*2 = 6 > 5
    @test !ok && a.speedup == 0.0f0
    # no variable clause: unchanged, an index
    ok, a = assess(0, [1, 1], 2)
    @test ok && a.speedup == 2.0f0
end

# TARGET-ONLY: pin when the oracle moves to cf6960c2. pl-index.c:2826-2840 `indexableCompound`.
@testset "SYNC-F: indexableCompound ends an H_R* last argument's list at the clause exit (cf6960c2, TARGET-ONLY)" begin
    fnc(c) = LK.Code{_SF}(LK.code[LK.H_RFUNCTOR, LK.code(0), LK.H_VOID, LK.H_VOID, c], _SF[], 1)
    # the argument list ends at H_POP and at every instruction that follows an H_R* last argument
    for op in (
        LK.H_POP, LK.I_EXITCATCH, LK.I_EXITRESET, LK.I_EXITFACT, LK.I_EXIT, LK.I_ENTER,
        LK.I_SSU_COMMIT, LK.I_SSU_CHOICE
    )
        @test !LK.indexableCompound(fnc(op))
    end
    # a non-variable argument makes it indexable
    @test LK.indexableCompound(fnc(LK.H_ATOM))
    @test LK.indexableCompound(
        LK.Code{_SF}(LK.code[LK.H_FUNCTOR, LK.code(0), LK.H_VOID, LK.H_ATOM], _SF[], 1)
    )
end

# TARGET-ONLY: pin when the oracle moves to cf6960c2. pl-index.c:3462-3496 `get_existing_index`, `sort_indexes`.
@testset "SYNC-F: get_existing_index searches from the start; sort_indexes! orders by speedup (cf6960c2, TARGET-ONLY)" begin
    p = ix_pred(_SF, :p, 2)
    ctx = LK.index_context{_SF}(
        LK.gen_t(0), p.def, nothing, 0, LK._TOP_POSITION, false, LK.GEN_INVALID
    )
    mk(k, speedup) = LK.newClauseIndexTable(
        LK.hash_hints(Float32(speedup), false, UInt8(2), (UInt8(k), 0x00, 0x00, 0x00)), false,
        ctx
    )
    hints(args...) = LK.hash_hints(0.0f0, false, UInt8(2), (UInt8.(args)..., ntuple(_ -> 0x00, 4 - length(args))...))
    CI = LK.ClauseIndex{_SF}
    CIP = Vector{Union{Nothing, CI}}
    ci1, ci2, ci3 = mk(1, 1.0), mk(2, 1.0), LK.newClauseIndexTable(
        LK.hash_hints(1.0f0, false, UInt8(2), (0x01, 0x02, 0x00, 0x00)), false, ctx
    )
    org = CIP([ci1, nothing, ci2, ci3])                             # a dead slot between
    @test LK.get_existing_index(org, hints(2)) === ci2
    @test LK.get_existing_index(org, hints(2)) === ci2              # no position is carried between calls
    @test LK.get_existing_index(org, hints(1)) === ci1
    @test LK.get_existing_index(org, hints(1, 2)) === ci3
    @test LK.get_existing_index(org, hints(3)) === nothing
    @test LK.get_existing_index(nothing, hints(1)) === nothing
    @test LK.get_existing_index(CIP([nothing, ci1]), hints(1)) === ci1

    # decreasing speedup, equal ones keep their order, only the first `count` slots are looked at
    cip = CIP([mk(1, 1.0), mk(2, 3.0), mk(3, 2.0), mk(4, 3.0), mk(5, 9.0)])
    LK.sort_indexes!(cip, 4)
    @test [Int(c.args[1]) for c in cip] == [2, 4, 3, 1, 5]
    @test [c.speedup for c in cip[1:4]] == Float32[3.0, 3.0, 2.0, 1.0]
    @test LK.isSortedIndexes(cip[1:4]) && !LK.isSortedIndexes(cip)
    LK.sort_indexes!(cip, 5)
    @test [Int(c.args[1]) for c in cip] == [5, 2, 4, 3, 1] && LK.isSortedIndexes(cip)
    one = CIP([mk(1, 1.0)])
    LK.sort_indexes!(one, 1)
    @test Int(one[1].args[1]) == 1
    LK.sort_indexes!(CIP(), 0)                                      # nothing to do
end
