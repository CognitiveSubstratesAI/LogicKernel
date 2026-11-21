# ORIGINAL: white-box tests of the TRAIL half of the stack collector (G1-GC G1-4: src/pl-gctrail.jl, upstream's pl-gc.c
# `tag_trail`, `untag_trail`, `compact_trail`, `is_dead_attvar`, `clean_attvar_chain`); swipl observes the tagged trail only through its own collector.
# test/core_lang/test_gc_trail.jl — each result compared with an INDEPENDENT model written here in plain Julia arithmetic:
#   * the tagged word of an entry is computed by literal shifts (`(pos << 7) | 8` for an address, `| 9` for a value entry: storage
#     bits 3-4, TAG_TRAILVAL = bit 0), never by the kernel's `consPtr`; tag then untag is the identity (also when the MARK and FIRST
#     bits were set meanwhile), a deleted entry (word 0) stays 0;
#   * `compact_trail` keeps exactly the non-zero entries in order (the model filters a copy), counts them, hands every FIRST-marked
#     entry (the heads of relocation chains, also the sentinel) to its handler with the destination index the model computes;
#   * early reset (G1-3) followed by tag/compact/untag removes exactly the entries early reset zeroed;
#   * `clean_attvar_chain` drops exactly the links whose attvar cell is neither an attvar word nor kept by a trailed assignment;
#     `untag_trail` marks the cell of such an assignment;
#   * deliberate corruptions MUST FAIL the comparisons (a live entry deleted, a tag bit flipped, a stray entry in the sweep list).
# No row consults swipl (nothing here is observable through it), so no testset can run without an assertion.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_gt_atom(ld, n) = LK._atom_word!(ld, _rs(n))

"The model of one tagged entry: literal shifts (position at bit 7, STG_GLOBAL = 8, TAG_TRAILVAL = 1); 0 stays 0."
function _gt_tag_model(e::UInt64)::UInt64
    e == 0 && return UInt64(0)
    return ((e & 1) == 1 ? (((e >> 3) << 7) | 0x09) : (((e >> 3) << 7) | 0x08))
end

"The model of an untagged entry from a tagged word: position at bit 7, bit 0 the value tag."
_gt_untag_model(w::UInt64)::UInt64 = (w & 1) == 1 ? (((w >> 7) << 3) | 1) : ((w >> 7) << 3)

"An engine with a trail of: an address entry per bound cell c1, c2, a trailed assignment (the pair) on cv, an address entry c3. `(ld, cells, tr0)`."
function _gt_engine()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    c1 = LK.allocGlobalCells!(ld, 1)
    c2 = LK.allocGlobalCells!(ld, 1)
    cv = LK.allocGlobalCells!(ld, 1)
    c3 = LK.allocGlobalCells!(ld, 1)
    ld.gstack[cv] = _gt_atom(ld, "old")
    fid = LK.PL_open_foreign_frame(ld)                          # the cells are older than this frame's bar
    tr0 = length(ld.trail)
    LK._bind_const!(ld, c1, _gt_atom(ld, "one"))                # a trail entry each
    LK._bind_const!(ld, c2, _gt_atom(ld, "two"))
    LK.TrailAssignment!(ld, cv)                                 # the pair: the address entry, then the value entry
    ld.gstack[cv] = _gt_atom(ld, "new")
    LK._bind_const!(ld, c3, _gt_atom(ld, "three"))
    return ld, (c1=c1, c2=c2, cv=cv, c3=c3), tr0
end

@testset "tag_trail and untag_trail: the model's tagged words, and the identity round trip" begin
    ld, cells, tr0 = _gt_engine()
    @test length(ld.trail) == tr0 + 5                           # c1, c2, the pair, c3: non-vacuous
    @test count(LK.isTrailVal, ld.trail) >= 1                   # a value entry is among them
    orig = copy(ld.trail)
    ts = LK.gc_trail_begin!(ld)
    @test ts.top == length(orig) + 1 && ld.trail[end] == 0      # the sentinel
    LK.tag_trail(ld, ts)
    @test ts.tagged
    model = vcat(UInt64[_gt_tag_model(e) for e in orig], UInt64[0])
    @test ld.trail == model                                     # entry for entry, sentinel left alone
    @test ts.values == count(LK.isTrailVal, orig) >= 1
    @test all(w -> w == 0 || LK.gc_trail_tagged_pos(w) >= 1, ld.trail)
    @test [LK.gc_trail_tagged_isval(w) for w in ld.trail[1:(end - 1)]] ==
        [LK.isTrailVal(e) for e in orig]
    @test LK.gc_trail_tagged_pos(ld.trail[tr0 + 1]) == cells.c1
    # the gc bits are free in the tagged form: set MARK and FIRST on every entry, untag still gives the original
    for i in 1:(ts.top - 1)
        ld.trail[i] = LK.set_first(LK.set_marked(ld.trail[i]))
    end
    LK.untag_trail(ld, ts)
    @test !ts.tagged
    @test ld.trail[1:(end - 1)] == orig && ld.trail[end] == 0
    LK.gc_trail_end!(ld, ts)
    @test ld.trail == orig                                      # the sentinel is gone, nothing else changed
    @test_throws ErrorException LK.untag_trail(ld, LK.gc_trail_begin!(ld))      # untagged trail: refused
    pop!(ld.trail)
end

@testset "a deleted entry stays 0 through tag and untag; a local-stack address is a named refusal" begin
    ld, cells, tr0 = _gt_engine()
    orig = copy(ld.trail)
    ld.trail[tr0 + 2] = 0                                       # c2's entry deleted (early reset)
    deleted = copy(ld.trail)
    @test count(==(0), deleted) >= 1 && count(!=(0), deleted) >= 4
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    @test ld.trail[tr0 + 2] == 0
    @test ld.trail == vcat(UInt64[_gt_tag_model(e) for e in deleted], UInt64[0])
    LK.untag_trail(ld, ts)
    @test ld.trail[1:(end - 1)] == deleted
    LK.gc_trail_end!(ld, ts)
    @test orig != deleted && length(orig) == length(deleted)
    ld.trail[tr0 + 1] = LK._trail_addr(cells.c1, 1)             # stack code 1: a local-stack address
    ts2 = LK.gc_trail_begin!(ld)
    @test_throws LK.NotPortedError LK.tag_trail(ld, ts2)
    pop!(ld.trail)
end

@testset "compact_trail removes exactly the deleted entries and keeps the order" begin
    ld, cells, tr0 = _gt_engine()
    ld.trail[tr0 + 2] = 0                                       # delete c2's entry and the whole pair
    ld.trail[tr0 + 3] = 0
    ld.trail[tr0 + 4] = 0
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    tagged = copy(ld.trail)
    keptmodel = UInt64[w for w in tagged[1:(end - 1)] if w != 0]
    nzero = count(==(0), tagged[1:(end - 1)])
    @test nzero == 3 && length(keptmodel) >= 2
    top = LK.compact_trail(ld, ts)
    @test top == length(keptmodel) + 1 == ts.top
    @test ld.trail == vcat(keptmodel, UInt64[0])                # the order is kept, the sentinel sits at the new top
    @test ts.zeroed == nzero && ts.kept == length(keptmodel) && ts.chains == 0
    LK.untag_trail(ld, ts)
    @test length(ld.trail) == ts.top
    @test ld.trail[1:(end - 1)] == UInt64[_gt_untag_model(w) for w in keptmodel]
    LK.gc_trail_end!(ld, ts)
end

@testset "compact_trail hands every FIRST-marked entry to the chain handler with its destination" begin
    ld, cells, tr0 = _gt_engine()
    ld.trail[tr0 + 2] = 0                                       # one deleted entry before the marked ones
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    first_at = [tr0 + 1, tr0 + 5, ts.top]                       # a kept entry, the last entry, and the sentinel (a mark's chain head)
    for i in first_at
        ld.trail[i] = LK.set_first(ld.trail[i])
    end
    tagged = copy(ld.trail)
    expected = Tuple{Int, Int}[]
    dest = 1
    for cur in 1:(ts.top)                                       # the model: dest counts the kept entries before `cur`
        if (tagged[cur] & LK.FIRST_MASK) != 0
            push!(expected, (cur, dest))
        end
        cur < ts.top && tagged[cur] != 0 && (dest += 1)
    end
    @test length(expected) == 3
    seen = Tuple{Int, Int}[]
    handler = function (ld2, current, dst)                      # the chain's unwinding: clear FIRST, as update_relocation_chain
        push!(seen, (current, dst))
        ld2.trail[current] = LK.clear_first(ld2.trail[current])
        return nothing
    end
    top = LK.compact_trail(ld, ts, handler)
    @test seen == expected
    @test ts.chains == 3
    @test !any(LK.is_first, ld.trail)
    @test top == dest                                           # tTop = dest
    keptwords = UInt64[LK.clear_first(w) for w in tagged[1:(end - 1)] if w != 0]
    @test !isempty(keptwords) && ld.trail[1:(top - 1)] == keptwords
    @test ld.trail[top] == 0                                    # the sentinel's word, restored by the handler
end

@testset "compact_trail without a chain handler refuses a FIRST bit by name" begin
    ld, cells, tr0 = _gt_engine()
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    ld.trail[tr0 + 1] = LK.set_first(ld.trail[tr0 + 1])
    @test_throws LK.NotPortedError LK.compact_trail(ld, ts)
    @test_throws ErrorException LK.compact_trail(ld, LK.gc_trail_state())   # untagged state: refused
end

@testset "early reset, then tag, compact and untag: only the entries early reset zeroed disappear" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    ld.slots[t + 1] = _gt_atom(ld, "a")
    c1 = LK.allocGlobalCells!(ld, 1)
    c2 = LK.allocGlobalCells!(ld, 1)
    fid = LK.PL_open_foreign_frame(ld)
    tr0 = length(ld.trail)
    LK._bind_const!(ld, c1, _gt_atom(ld, "one"))
    LK._bind_const!(ld, c2, _gt_atom(ld, "two"))
    t2 = LK.PL_new_term_ref(ld)
    ld.slots[t2 + 1] = LK.makeRefG(c1)                          # c1 reachable, c2 not
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())                        # early reset zeroes c2's entry
    @test st.trailcells_deleted == 1
    @test ld.trail[tr0 + 2] == 0 && ld.trail[tr0 + 1] != 0
    after_mark = copy(ld.trail)
    live = UInt64[e for e in after_mark if e != 0]
    @test length(live) == length(after_mark) - 1 >= 1           # one entry is gone, the others are live
    LK.gc_clear_marks!(ld)
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    LK.compact_trail(ld, ts)
    @test ts.zeroed == 1 && ts.kept == length(live)
    @test ld.trail == vcat(UInt64[_gt_tag_model(e) for e in live], UInt64[0])
    LK.untag_trail(ld, ts)
    @test ld.trail[1:(end - 1)] == live
    LK.gc_trail_end!(ld, ts)
    @test length(ld.trail) == length(live)
end

@testset "gc_trail_sweep_entries lists the entries sweep_trail chains, newest first" begin
    ld, cells, tr0 = _gt_engine()
    ld.trail[tr0 + 1] = 0                                       # a deleted entry is not listed
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    ld.trail[tr0 + 5] = (UInt64(7) << 7) | 0x10                 # STG_LOCAL (2 << 3), tag 0: not a global pointer, not a value
    model = Int[
        i for i in (ts.top - 1):-1:1 if
        ld.trail[i] != 0 && ((ld.trail[i] & 1) == 1 || (ld.trail[i] & 0x18) == 0x08)
    ]
    got = LK.gc_trail_sweep_entries(ld, ts)
    @test !isempty(got) && !isempty(model)
    @test got == model
    @test !(tr0 + 5 in got) && !(tr0 + 1 in got) && (tr0 + 3 in got) &&
        issorted(got; rev=true)
    @test_throws ErrorException LK.gc_trail_sweep_entries(ld, LK.gc_trail_state())   # untagged: refused
end

"The attvar cells (positions of the cells on the chain whose words are attvars, by tag bits) from the newest link, with the link cells."
function _gt_chain(ld)
    links = Int[]
    p = ld.attvar_attvars
    while p != 0
        push!(links, p)
        p = (ld.gstack[p] & 7) == 7 ? Int(ld.gstack[p] >> 7) : 0
    end
    return links
end

@testset "is_dead_attvar and clean_attvar_chain drop exactly the dead links" begin
    ld, cells, tr0 = _gt_engine()
    ps = [LK.allocGlobalCells!(ld, 1) for _ in 1:4]
    for p in ps
        LK.make_new_attvar(ld, p)
    end
    links = _gt_chain(ld)
    @test length(links) == 4                                    # newest first
    avcell(l) = l + 1
    @test all(l -> (ld.gstack[avcell(l)] & 7) == 1, links)      # TAG_ATTVAR = 1
    ld.gstack[avcell(links[2])] = _gt_atom(ld, "bound")         # dead: bound, no trailed assignment
    ld.gstack[avcell(links[4])] = LK.set_marked(_gt_atom(ld, "kept"))   # bound, but kept by a trailed assignment (the mark)
    dead_model = [
        l for l in links if
        (ld.gstack[avcell(l)] & 7) != 1 && (ld.gstack[avcell(l)] & LK.MARK_MASK) == 0
    ]
    @test dead_model == [links[2]]
    @test LK.is_dead_attvar(ld, avcell(links[2]))
    @test !LK.is_dead_attvar(ld, avcell(links[1]))
    @test !LK.is_dead_attvar(ld, avcell(links[4]))              # reads and clears the mark
    @test (ld.gstack[avcell(links[4])] & LK.MARK_MASK) == 0
    @test LK.is_dead_attvar(ld, avcell(links[4]))               # now an unmarked non-attvar: dead
    ld.gstack[avcell(links[4])] = LK.set_marked(_gt_atom(ld, "kept"))   # restore the kept state
    removed = LK.clean_attvar_chain(ld)
    @test removed == 1
    @test _gt_chain(ld) == [links[1], links[3], links[4]]       # the survivors, in order
    @test (ld.gstack[avcell(links[4])] & LK.MARK_MASK) == 0     # the mark was read and cleared
    @test ld.attvar_attvars == links[1]
    ld.gstack[avcell(links[1])] = _gt_atom(ld, "head")          # the newest link dead: the head moves on
    @test LK.clean_attvar_chain(ld) == 2                        # links[1] (bound) and links[4] (unmarked non-attvar now)
    @test _gt_chain(ld) == [links[3]]
    @test ld.attvar_attvars == links[3]
    ld.gstack[avcell(links[3])] = _gt_atom(ld, "last")
    @test LK.clean_attvar_chain(ld) == 1 && ld.attvar_attvars == 0 && isempty(_gt_chain(ld))
    @test LK.clean_attvar_chain(ld) == 0                        # an empty chain
end

@testset "untag_trail marks the attvar cell of a trailed assignment whose saved value is an attvar" begin
    ld, cells, tr0 = _gt_engine()
    pa = LK.allocGlobalCells!(ld, 1)
    pb = LK.allocGlobalCells!(ld, 1)
    LK.make_new_attvar(ld, pa)
    LK.make_new_attvar(ld, pb)
    A = LK.unRef(ld.gstack[pa])
    B = LK.unRef(ld.gstack[pb])
    @test (ld.gstack[A] & 7) == 1 && (ld.gstack[B] & 7) == 1
    ga = LK.allocGlobalCells!(ld, 1)
    gb = LK.allocGlobalCells!(ld, 1)
    ld.gstack[ga] = ld.gstack[A]                                # the saved old values: attvar words
    ld.gstack[gb] = ld.gstack[B]
    ld.gstack[A] = _gt_atom(ld, "assigned")                     # A was assigned (no longer an attvar); B was not
    push!(ld.trail, LK._trail_addr(A, LK.TRAIL_GLOBAL))
    push!(ld.trail, LK.tagTrailPtr(ga))
    push!(ld.trail, LK._trail_addr(B, LK.TRAIL_GLOBAL))
    push!(ld.trail, LK.tagTrailPtr(gb))
    orig = copy(ld.trail)
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    @test !LK.is_marked(ld.gstack[A]) && !LK.is_marked(ld.gstack[B])
    LK.untag_trail(ld, ts)
    @test ld.trail[1:(end - 1)] == orig
    @test LK.is_marked(ld.gstack[A])                            # the assignment keeps A on the chain
    @test !LK.is_marked(ld.gstack[B])                           # B is still an attvar: nothing to keep
    LK.gc_trail_end!(ld, ts)
    @test LK.clean_attvar_chain(ld) == 0                        # A is kept by its mark, B is an attvar
    @test !LK.is_marked(ld.gstack[A])
    @test A - 1 in _gt_chain(ld) && B - 1 in _gt_chain(ld)
end

@testset "deliberate corruptions FAIL the comparisons" begin
    # a live entry deleted before the compaction: the kept entries no longer equal the model of the undamaged trail
    ld, cells, tr0 = _gt_engine()
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    model = UInt64[w for w in ld.trail[1:(end - 1)] if w != 0]
    @test !isempty(model)
    ld.trail[tr0 + 1] = 0                                       # the corruption
    LK.compact_trail(ld, ts)
    @test ld.trail != vcat(model, UInt64[0])                    # MUST differ
    @test length(ld.trail) == length(model)                     # one entry short (the sentinel counts)
    # a flipped tag bit: the round trip is no longer the identity
    ld2, cells2, tr02 = _gt_engine()
    orig2 = copy(ld2.trail)
    ts2 = LK.gc_trail_begin!(ld2)
    LK.tag_trail(ld2, ts2)
    vi = findfirst(w -> LK.gc_trail_tagged_isval(w), ld2.trail)
    @test vi !== nothing
    ld2.trail[vi] &= ~LK.TAG_TRAILMASK                          # the corruption: a value entry becomes an address entry
    LK.untag_trail(ld2, ts2)
    @test ld2.trail[1:(end - 1)] != orig2                       # MUST differ
    @test ld2.trail[1:(end - 1)][vi] == (orig2[vi] & ~UInt64(1))
    # a wrong destination model: the handler's record differs from a model shifted by one
    ld3, cells3, tr03 = _gt_engine()
    ld3.trail[tr03 + 1] = 0
    ts3 = LK.gc_trail_begin!(ld3)
    LK.tag_trail(ld3, ts3)
    ld3.trail[tr03 + 3] = LK.set_first(ld3.trail[tr03 + 3])
    seen3 = Tuple{Int, Int}[]
    LK.compact_trail(
        ld3,
        ts3,
        (l, c, d) -> (push!(seen3, (c, d)); l.trail[c]=LK.clear_first(l.trail[c]); nothing)
    )
    @test seen3 == [(tr03 + 3, tr03 + 2)]                       # one deleted entry before it: dest = current - 1
    @test seen3 != [(tr03 + 3, tr03 + 3)]                       # the uncompacted destination is wrong
end
