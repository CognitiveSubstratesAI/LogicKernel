# ORIGINAL: the unit test of the pl-table.c port (src/os/pl-table.jl); the tables are not observable from Prolog, so no swipl row exists.
# test/core_lang/test_htable.jl — upstream's hash tables, word -> word (os/pl-table.c). UNTESTED when written (lane F, edit-only,
# nothing compiled). The expected values are DERIVED from upstream's algorithm, each with its derivation:
#   - `pointerHashValue(p, size)` is `((p >> 7) ⊻ (p >> 12) ⊻ p) & (size - 1)`, so for a key < 128 it is `key & (size - 1)`:
#     the bucket order of the keys used here is computable by hand;
#   - an insert reprobes (`stride 1`) from its bucket; a map of `len` buckets resizes when an insert has reprobed
#     `10 + (len >> 2)` times; the new length is `len << 1`, or `len << 2` once the table holds half its buckets (htable_resize).
# TERM TYPES PER CHUNK: REFERENCE — only the duplicate-add warning (`addNewHTable`) takes the local data; every type in CI and at milestones.
using Test, LogicKernel
const LK = LogicKernel

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _HT = lk_term_type(Union{Int64, Float64, String})

"Every live entry of `ht` through an enumerator, in enumeration order."
function _ht_entries(ht::LK.Table)::Vector{Tuple{UInt64, UInt64}}
    out = Tuple{UInt64, UInt64}[]
    e = LK.newTableEnum(ht)
    while true
        found, n, v = LK.advanceTableEnum(e)
        found || break
        push!(out, (n, v))
    end
    LK.freeTableEnum(e)
    return out
end

@testset "pl-table.c: put, get, add, delete, size" begin
    ht = LK.newHTable(16)
    @test ht.size == 0
    @test LK.lookupHTable(ht, UInt64(3)) == LK.NULL_VALUE
    @test LK.updateHTable(ht, UInt64(3), UInt64(30)) == UInt64(30)          # a new name: the new value
    @test LK.lookupHTable(ht, UInt64(3)) == UInt64(30)
    @test ht.size == 1
    @test LK.updateHTable(ht, UInt64(3), UInt64(31)) == UInt64(31)          # an old name: the new value (htable_put's `return value`, pl-table.c:415)
    @test LK.lookupHTable(ht, UInt64(3)) == UInt64(31)
    @test ht.size == 1
    @test LK.addHTable(ht, UInt64(3), UInt64(99)) == UInt64(31)             # add keeps the existing association
    @test LK.lookupHTable(ht, UInt64(3)) == UInt64(31)
    @test LK.addHTable(ht, UInt64(4), UInt64(40)) == UInt64(40)
    @test ht.size == 2
    @test LK.deleteHTable(ht, UInt64(3)) == UInt64(31)                      # the deleted value
    @test LK.lookupHTable(ht, UInt64(3)) == LK.NULL_VALUE
    @test LK.deleteHTable(ht, UInt64(3)) == LK.NULL_VALUE                   # nothing left to delete
    @test LK.deleteHTable(ht, UInt64(77)) == LK.NULL_VALUE                  # a name never there
    @test ht.size == 1
    @test LK.addHTable(ht, UInt64(3), UInt64(32)) == UInt64(32)             # a tombstoned name takes a value again
    @test ht.size == 2
    @test LK.sizeofTable(LK.newHTable(16)) == 32 + 40 + 16 * 16
end

@testset "pl-table.c: the enumeration order is the bucket order, with reprobing" begin
    ht = LK.newHTable(16)
    for k in (UInt64(1), UInt64(17), UInt64(2))     # 17 collides with 1 (bucket 1), takes bucket 2; 2 then takes bucket 3
        LK.updateHTable(ht, k, k * 10)
    end
    @test _ht_entries(ht) ==
        [(UInt64(1), UInt64(10)), (UInt64(17), UInt64(170)), (UInt64(2), UInt64(20))]
    ht2 = LK.newHTable(16)
    for k in UInt64(8):-1:UInt64(1)                  # inserted in reverse: still bucket order
        LK.updateHTable(ht2, k, k + 100)
    end
    @test [n for (n, _) in _ht_entries(ht2)] == collect(UInt64(1):UInt64(8))
    LK.deleteHTable(ht2, UInt64(4))
    @test [n for (n, _) in _ht_entries(ht2)] == [UInt64(1), 2, 3, 5, 6, 7, 8]   # a tombstone is skipped
    ht3 = LK.newHTable(16)                           # a tombstone in the LAST bucket ends an enumeration: nothing is found
    LK.updateHTable(ht3, UInt64(15), UInt64(150))
    LK.deleteHTable(ht3, UInt64(15))
    @test _ht_entries(ht3) == Tuple{UInt64, UInt64}[]
    e = LK.newTableEnum(ht2)                         # an enumerator counts as an access of its map until it is freed
    @test ht2.kvs.accesses == 1
    LK.freeTableEnum(e)
    @test ht2.kvs.accesses == 0
    LK.freeTableEnum(nothing)                        # a NULL enumerator is ignored
    a1 = LK.htable_alloc_kvs(4)                      # forgetting a map unlinks the map after it
    b1 = LK.htable_alloc_kvs(4)
    a1.next = b1
    b1.prev = a1
    LK.htable_free_kvs(a1)
    @test b1.prev === nothing
    @test LK.htable_cas_name(b1, 0, UInt64(0), UInt64(7)) &&
        LK.htable_name(b1, 0) == UInt64(7)
    @test !LK.htable_cas_name(b1, 0, UInt64(0), UInt64(8)) &&
        LK.htable_name(b1, 0) == UInt64(7)
    c1 = LK.htable_alloc_kvs(4)
    @test !LK.htable_cas_new_kvs(a1, c1) && a1.next === b1                       # a map that has a next one keeps it
    @test LK.htable_cas_new_kvs(c1, a1) && c1.next === a1                        # one that has none takes the new one
end

@testset "pl-table.c: a resize moves every entry into a map four times as long" begin
    ht = LK.newHTable(4)
    for k in UInt64(1):UInt64(4)
        LK.updateHTable(ht, k, k * 10)
    end
    @test ht.kvs.len == 4                            # four entries fit in four buckets
    old = ht.kvs
    LK.updateHTable(ht, UInt64(5), UInt64(50))       # reprobes 10 + (4 >> 2) = 11 times, then resizes: size 4 >= 4 >> 1: 4 << 2
    @test ht.kvs.len == 16
    @test ht.kvs.prev === old                        # the predecessor stays (htable_maybe_free_kvs keeps ht->kvs->prev)
    @test ht.size == 5
    for k in UInt64(1):UInt64(5)
        @test LK.lookupHTable(ht, k) == k * 10
    end
    @test LK.htable_value(old, 1) == LK.HTABLE_SENTINEL     # key 1 (bucket 1) moved: its old entry is dead (<K,SENTINEL>)
    @test _ht_entries(ht) == [(k, k * 10) for k in UInt64(1):UInt64(5)]
    @test LK.lookupHTable(ht, UInt64(6)) == LK.NULL_VALUE
    @test LK.htable_get(ht, old, UInt64(1)) == UInt64(10)     # asked of the OLD map: its dead entry sends the lookup to the next map
    e = LK.newTableEnum(ht)                                    # an enumerator holds the map it was made on (weakly consistent)
    LK.updateHTable(ht, UInt64(6), UInt64(60))
    @test ht.kvs.len == 16 && e.kvs === ht.kvs
    LK.freeTableEnum(e)
    ht4 = LK.newHTable(4)
    for k in UInt64(1):UInt64(4)
        LK.updateHTable(ht4, k, k * 10)
    end
    e4 = LK.newTableEnum(ht4)                                  # made on the 4-bucket map, then the table resizes under it
    LK.updateHTable(ht4, UInt64(5), UInt64(50))
    @test e4.kvs.len == 4 && ht4.kvs.len == 16
    got = Tuple{UInt64, UInt64}[]
    while true
        found, n, v = LK.advanceTableEnum(e4)
        found || break
        push!(got, (n, v))
    end
    @test sort(got) == [(k, k * 10) for k in UInt64(1):UInt64(4)]   # old-map bucket order is 4,1,2,3; its dead entries are read through the new map
    LK.freeTableEnum(e4)
end

@testset "pl-table.c: clear, free_symbol, copy, copy_symbol" begin
    freed = Tuple{UInt64, UInt64}[]
    ht = LK.newHTable(16, (n, v) -> v * 2, (n, v) -> push!(freed, (n, v)))   # the hooks are fixed at construction
    for k in UInt64(1):UInt64(3)
        LK.updateHTable(ht, k, k + 5)
    end
    LK.deleteHTable(ht, UInt64(2))
    @test isempty(freed)                             # a delete does not call free_symbol
    cp = LK.copyHTable(ht)
    @test cp.free_symbol === ht.free_symbol && cp.copy_symbol === ht.copy_symbol
    @test _ht_entries(cp) == [(UInt64(1), UInt64(12)), (UInt64(3), UInt64(16))]   # copy_symbol rewrote each live value
    @test cp.size == 2
    @test LK.lookupHTable(ht, UInt64(1)) == UInt64(6)                              # the source is as it was
    LK.PL_clear_hash_table(ht)
    @test sort(freed) == [(UInt64(1), UInt64(6)), (UInt64(3), UInt64(8))]          # the live entries, once each
    @test ht.size == 0
    @test _ht_entries(ht) == Tuple{UInt64, UInt64}[]
    @test LK.lookupHTable(ht, UInt64(1)) == LK.NULL_VALUE
    LK.updateHTable(ht, UInt64(9), UInt64(90))
    empty!(freed)
    @test LK.PL_free_hash_table(ht)
    @test freed == [(UInt64(9), UInt64(90))]
end

@testset "pl-table.c: addNewHTable warns about a name the table has, then updates" begin
    gd = LK.PL_global_data{_HT}()
    ld = LK.PL_local_data{_HT}(gd)
    ht = LK.newHTable(16)
    n0 = length(ld.messages)
    @test LK.PL_add_hash_table(ld, ht, UInt64(5), UInt64(50), LK.PL_HT_NEW) == UInt64(50)
    @test length(ld.messages) == n0                  # a new name: no warning
    @test LK.PL_add_hash_table(ld, ht, UInt64(5), UInt64(51), LK.PL_HT_NEW) == UInt64(51)    # updateHTable answers the new value
    @test length(ld.messages) == n0 + 2             # the warning, then print_backtrace_named's fallback message
    @test occursin("Race condition detected", String(lk_name(ld.messages[end - 1][2])))
    @test occursin("C-stack dumps are not supported", String(lk_name(ld.messages[end][2])))
    @test LK.lookupHTable(ht, UInt64(5)) == UInt64(51)
    @test LK.PL_add_hash_table(ld, ht, UInt64(5), UInt64(52), LK.PL_HT_UPDATE) == UInt64(52)
    @test LK.PL_add_hash_table(ld, ht, UInt64(5), UInt64(53), 0) == UInt64(52)               # no flag: add keeps the old value
    @test LK.lookupHTable(ht, UInt64(5)) == UInt64(52)
end
