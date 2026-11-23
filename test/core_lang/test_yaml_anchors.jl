# ORIGINAL: YAML1 piece 3's gate - the anchor table of packages/yaml/yaml4pl.c (MurmurHashAligned2, new_anchor_table, rehash, add_anchor,
# find_anchor, store_anchor), src/pl-yaml.jl. NO oracle and no libyaml: every expected value is read off yaml4pl.c (packages-yaml 0ce45ecf,
# lines 384-560) and was produced by a python transcription of the C (python3 -I, scratchpad sim_anchor.py: 32-bit masks, the chains as linked
# cells, rehash walking each chain from its head) whose output is quoted in the comments. Nothing here has run (no Julia process was started
# to write this file). The ROWS THAT MATTER: the 18th add answers false (upstream's `add_anchor` reads rehash's FALSE as a failure) and the
# chain order of two cells of one name after a rehash (oldest first). MEASURE ON THE LANE: the same two behaviours on the oracle itself
# (`yaml_read` of a document with 18 anchors; one anchor name defined twice with 16 other anchors between).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _YA_DB = _rdb(Tuple{_R, Union{Nothing, _R}}[])
const _YA_LD = _YA_DB.ld

# A new term reference holding the integer `n`.
function _ya_ref(ld, n::Int)::Int
    t = LK.PL_new_term_ref(ld)
    LK.PL_put_integer(ld, t, n)
    return t
end
# The integer the reference `find` returned holds, 0 for no anchor (0 is no term reference: a value is never 0 here).
function _ya_found(ld, t::LK.yaml_htable, name::String)
    r = LK.yaml_find_anchor(t, name)
    r == 0 && return 0
    return LK.PL_get_integer(ld, r)
end

@testset "yaml_murmur_hash_aligned2 (yaml4pl.c MurmurHashAligned2, seed 0x6263533a)" begin
    h(s) = (
        b=Vector{UInt8}(codeunits(s));
        LK.yaml_murmur_hash_aligned2(b, length(b), LK.YAML_ANCHOR_SEED)
    )
    @test LK.YAML_ANCHOR_SEED === UInt32(0x6263533a)
    # every length class of the tail switch (0, 1, 2, 3 bytes) and of the 4-byte loop (4, 5, 7 bytes), a multi-byte character
    @test h("") === UInt32(2525192100)
    @test h("a") === UInt32(211805466)
    @test h("ab") === UInt32(4092239310)
    @test h("abc") === UInt32(2384057535)
    @test h("abcd") === UInt32(1773184967)
    @test h("abcde") === UInt32(1451118565)
    @test h("anchor1") === UInt32(2789330977)
    @test h("x") === UInt32(644783809)
    @test h("a1") === UInt32(2816423136)
    @test h("café") === UInt32(4141220229)            # 5 bytes, the last two >= 0x80 (the byte is never sign extended)
    # `len` limits the hash, not the vector
    @test LK.yaml_murmur_hash_aligned2(
        Vector{UInt8}(codeunits("abcdef")), 3, LK.YAML_ANCHOR_SEED
    ) === h("abc")
    # seed 0 and an empty key hash to 0 (h = 0 ^ 0, no tail, the final mixes keep 0)
    @test LK.yaml_murmur_hash_aligned2(UInt8[], 0, UInt32(0)) === UInt32(0)
    # the bucket: hash % size, 1-based (sim: mod16 / mod32 / mod64)
    for (s, b16, b32, b64) in
        (("", 4, 4, 36), ("a", 10, 26, 26), ("ab", 14, 14, 14), ("abc", 15, 31, 63),
        ("abcd", 7, 7, 7),
        ("abcde", 5, 5, 37), ("anchor1", 1, 1, 33), ("x", 1, 1, 1), ("a1", 0, 0, 32))
        @test LK._yaml_anchor_bucket(s, 16) == b16 + 1
        @test LK._yaml_anchor_bucket(s, 32) == b32 + 1
        @test LK._yaml_anchor_bucket(s, 64) == b64 + 1
    end
end

@testset "yaml anchor table: new, add, find (yaml4pl.c add_anchor, find_anchor)" begin
    ld = _YA_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.yaml_new_anchor_table()
    @test (t.count, t.size, length(t.entries)) == (0, 16, 16)
    @test all(isnothing, t.entries)
    @test LK.yaml_find_anchor(t, "a") == 0                       # an empty table finds nothing
    @test LK.yaml_add_anchor(ld, t, "a1", _ya_ref(ld, 7)) === true
    @test t.count == 1
    @test _ya_found(ld, t, "a1") == 7
    @test _ya_found(ld, t, "a") == 0                             # another name, another or the same bucket: strcmp decides
    @test LK.yaml_find_anchor(t, "nope") == 0
    # the cell sits in bucket hash % 16 (sim: "a1" -> 0), at the head of its chain
    c = t.entries[LK._yaml_anchor_bucket("a1", 16)]
    @test c !== nothing && c.name == "a1" && c.next === nothing
    # the value is a COPY of the reference: not the reference that was given
    r = _ya_ref(ld, 8)
    @test LK.yaml_add_anchor(ld, t, "b2", r) === true
    @test LK.yaml_find_anchor(t, "b2") != r
    @test _ya_found(ld, t, "b2") == 8
    # a name is cut at its first NUL, as strlen/strcmp read it
    @test LK.yaml_add_anchor(ld, t, "z\0junk", _ya_ref(ld, 9)) === true
    @test _ya_found(ld, t, "z") == 9
    @test _ya_found(ld, t, "z\0other") == 9
    @test _ya_found(ld, t, "zjunk") == 0
    # one name twice: the LATER cell is at the head, find answers it (sim: add x 1, add x 2, find x -> 2)
    t2 = LK.yaml_new_anchor_table()
    @test LK.yaml_add_anchor(ld, t2, "x", _ya_ref(ld, 1)) === true
    @test LK.yaml_add_anchor(ld, t2, "x", _ya_ref(ld, 2)) === true
    @test _ya_found(ld, t2, "x") == 2
    @test t2.count == 2
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "yaml anchor table: the 18th add rehashes and answers false (upstream's add_anchor, as is)" begin
    ld = _YA_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.yaml_new_anchor_table()
    # sim: 18 adds of n1..n18 (value 100+i) -> [True]*17 + [False], count 17, size 32
    res = [LK.yaml_add_anchor(ld, t, "n$i", _ya_ref(ld, 100 + i)) for i in 1:18]
    @test res == [trues(17); false]
    @test (t.count, t.size, length(t.entries)) == (17, 32, 32)
    @test _ya_found(ld, t, "n18") == 0                           # the 18th anchor was NOT stored
    @test _ya_found(ld, t, "n17") == 117                         # every earlier one is still found in the doubled table
    @test _ya_found(ld, t, "n1") == 101
    for i in 1:17
        @test _ya_found(ld, t, "n$i") == 100 + i
    end
    # the next add finds room: sim add n19 -> True, count 18, size 32
    @test LK.yaml_add_anchor(ld, t, "n19", _ya_ref(ld, 119)) === true
    @test (t.count, t.size) == (18, 32)
    @test _ya_found(ld, t, "n19") == 119
    # adds n20..n34 raise count to 33 (all true, size 32); n35 meets count 33 > 32: false, size 64, count stays 33 (sim)
    for i in 20:34
        @test LK.yaml_add_anchor(ld, t, "n$i", _ya_ref(ld, 100 + i)) === true
    end
    @test (t.count, t.size) == (33, 32)
    @test LK.yaml_add_anchor(ld, t, "n35", _ya_ref(ld, 135)) === false
    @test (t.count, t.size) == (33, 64)
    @test _ya_found(ld, t, "n35") == 0
    @test LK.yaml_add_anchor(ld, t, "n36", _ya_ref(ld, 136)) === true
    @test (t.count, t.size) == (34, 64)
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "yaml anchor table: rehash reverses the chain of one name (find_anchor's first match changes)" begin
    ld = _YA_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.yaml_new_anchor_table()
    # sim: x=1, x=2 (find -> 2), then f0..f14 (count 17, size 16, find x -> 2), then y: false, size 32, find x -> 1, find y -> 0
    @test LK.yaml_add_anchor(ld, t, "x", _ya_ref(ld, 1)) === true
    @test LK.yaml_add_anchor(ld, t, "x", _ya_ref(ld, 2)) === true
    @test _ya_found(ld, t, "x") == 2
    for i in 0:14
        @test LK.yaml_add_anchor(ld, t, "f$i", _ya_ref(ld, 50 + i)) === true
    end
    @test (t.count, t.size) == (17, 16)
    @test _ya_found(ld, t, "x") == 2
    @test LK.yaml_add_anchor(ld, t, "y", _ya_ref(ld, 9)) === false
    @test (t.count, t.size) == (17, 32)
    @test _ya_found(ld, t, "x") == 1                             # the older cell is now the head of the chain
    @test _ya_found(ld, t, "y") == 0
    # a new cell of that name goes to the head again: sim add x 3 -> True, find x -> 3
    @test LK.yaml_add_anchor(ld, t, "x", _ya_ref(ld, 3)) === true
    @test _ya_found(ld, t, "x") == 3
    # yaml_rehash on its own: false, doubles, keeps every cell
    t3 = LK.yaml_new_anchor_table()
    @test LK.yaml_add_anchor(ld, t3, "a", _ya_ref(ld, 11)) === true
    @test LK.yaml_rehash(t3) === false
    @test (t3.count, t3.size, length(t3.entries)) == (1, 32, 32)
    @test _ya_found(ld, t3, "a") == 11
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "yaml_store_anchor (yaml4pl.c store_anchor)" begin
    ld = _YA_LD
    fid = LK.PL_open_foreign_frame(ld)
    n = _ya_ref(ld, 5)
    # no anchor on the event: nothing stored, the table (here none) is left as it was
    @test LK.yaml_store_anchor(ld, nothing, n, nothing) == (true, nothing)
    t0 = LK.yaml_new_anchor_table()
    ok, t = LK.yaml_store_anchor(ld, t0, n, nothing)
    @test ok === true && t === t0 && t.count == 0
    # the first anchor creates the table
    ok, t = LK.yaml_store_anchor(ld, nothing, n, "first")
    @test ok === true && t isa LK.yaml_htable && t.count == 1
    @test _ya_found(ld, t, "first") == 5
    # a later one adds to the same table
    ok2, t2 = LK.yaml_store_anchor(ld, t, _ya_ref(ld, 6), "second")
    @test ok2 === true && t2 === t && t.count == 2
    @test _ya_found(ld, t, "second") == 6 && _ya_found(ld, t, "first") == 5
    # the add's answer is the result's: the 18th anchor is false, and the table is returned all the same
    for i in 3:17
        @test LK.yaml_store_anchor(ld, t, _ya_ref(ld, i), "k$i")[1] === true
    end
    @test t.count == 17
    ok3, t3 = LK.yaml_store_anchor(ld, t, _ya_ref(ld, 99), "k18")
    @test ok3 === false && t3 === t && t.size == 32
    LK.PL_discard_foreign_frame(ld, fid)
end
