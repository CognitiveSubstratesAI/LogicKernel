# ORIGINAL: white-box tests of the stack collector's COMPACTION (G1-GC G1-6: src/pl-gccompact.jl; upstream's pl-gc.c `compact_global`,
# `downskip_combine_garbage`, `collect_phase`, `unsweep_*`); swipl observes the compaction only through its own collector (the cells move
# inside it), so no row consults swipl and no testset can run without an assertion.
# test/core_lang/test_gc_compact.jl — the mark phase on a built heap, the trail phase, then `collect_phase` (sweeps, compaction, unsweep):
#   * an INDEPENDENT model of the heap after the compaction (plain Julia over the words, no kernel marking or chain code): the live cells
#     (those marked before the collection) in position order; the new position of a live cell is its RANK among them; a cell's word is its old
#     word with every global reference rewritten to the rank of its target; the slots, the trail entries, the marks' heights (the number of live
#     cells at or below the old height; the trail count minus the deleted entries below it) and the value-table (`vbox`) are modelled the same way;
#     ONE extractor (`_gc6_problems`) serves the passing rows and the corruption rows;
#   * `gc_trail_phase` (the trail half of the collection): the deleted entries are gone, a mark's `trailtop` names the new count + 1;
#   * white-box rows: a hand-marked heap through `compact_global` (a garbage run > 4 cells becomes a hole, a chain head in garbage is unwound),
#     `downskip_combine_garbage`, `gc_tombstone_boxes!`, `gc_truncate_vtable!`, `unsweep_mark` and its counters, the counter checks;
#   * deliberate corruptions MUST FAIL the comparison (two ranks swapped, a cell of the heap altered).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))


"An engine with the values of `vs` (at least one) put into term references of an open foreign frame: `(ld, t, n0)` — `t` the first reference, `n0` the size of the value table before."
function _gc6_engine(vs::Vector{_R})
    @assert !isempty(vs)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    n0 = length(ld.vtable)
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, LK.PutVarMap())      # the i-th value: slot t + i
    end
    return ld, t, n0
end

"The words (no gc bits) of the term references of every foreign frame, innermost first."
function _gc6_fli_roots(ld)::Vector{UInt64}
    out = UInt64[]
    fr = ld.fli_context
    while fr != 0
        f = ld.fliframes[fr]
        for k in 0:(f.size - 1)
            push!(out, ld.slots[LK.refFliP(f.base, k) + 1] & LK.VALUE_MASK)
        end
        fr = f.parent
    end
    return out
end

"The cells of the global stack reachable from the words `roots`: a plain walk by tags (no mark bit is read)."
function _gc6_reach(ld, roots::Vector{UInt64})::Set{Int}
    seen = Set{Int}()
    todo = Int[]
    function visit_word(w::UInt64)
        w &= LK.VALUE_MASK
        if LK._is_vword(w)                                  # ruling D1: the box cell only
            push!(seen, ld.vbox[LK.valPtr(w)])
        elseif LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL
            push!(todo, LK.unRef(w))
        elseif LK.isAttVar(w)
            push!(todo, LK.valPtr(w))
        elseif LK._is_gcompound(w)
            f = LK.valPtr(w)                                # the functor cell, then its arguments
            if !(f in seen)
                push!(seen, f)
                for i in 1:LK.arityFunctor(ld.functors, ld.gstack[f] & LK.VALUE_MASK)
                    push!(todo, f + i)
                end
            end
        end
        return nothing
    end
    for w in roots
        visit_word(w)
    end
    while !isempty(todo)
        p = pop!(todo)
        p in seen && continue
        push!(seen, p)
        visit_word(ld.gstack[p])
    end
    return seen
end

"A word that names a global cell (the kinds the collector follows)."
_gc6_is_global(w::UInt64)::Bool =
    (LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL) || LK.isAttVar(w) || LK._is_gcompound(w) || LK._is_vword(w)

"The positions of the global cells whose MARK bit is set."
_gc6_marked(ld)::Set{Int} = Set{Int}(p for p in 1:(ld.gTop) if LK.is_marked(ld.gstack[p]))

"The stacks as they are: global cells, slots and the trail."
_gc6_snapshot(ld) = (g = copy(ld.gstack), s = copy(ld.slots), tr = copy(ld.trail))

"Put the stacks back as `sn` took them (the trail keeps its length)."
function _gc6_restore!(ld, sn)
    length(ld.trail) == length(sn.tr) || error("_gc6_restore!: the trail length changed")
    copyto!(ld.gstack, sn.g)
    copyto!(ld.slots, sn.s)
    copyto!(ld.trail, sn.tr)
    return nothing
end

"The words the frame at index `fi` holds in its argument slots (no gc bits)."
function _gc6_frame_args(ld, fi::Int)::Vector{UInt64}
    f = ld.frames[fi]
    return UInt64[ld.slots[LK.argFrameP(f.base, n) + 1] & LK.VALUE_MASK for n in 0:(f.predicate.arity - 1)]
end

"The trail in upstream's tagged form (pl-gc.c `tag_trail`, the test's own copy): 0 stays, an address entry becomes a GLOBAL pointer, a value entry one with TAG_TRAILVAL."
function _gc6_tag_trail!(ld)::Nothing
    for i in eachindex(ld.trail)
        e = ld.trail[i]
        e == 0 && continue
        if LK.isTrailVal(e)
            ld.trail[i] = LK.consPtr(LK.trailValP(e), LK.STG_GLOBAL | LK.TAG_TRAILVAL)
        else
            LK._trail_stack(e) == LK.TRAIL_GLOBAL || error("_gc6_tag_trail!: a trail entry outside the global stack")
            ld.trail[i] = LK.consPtr(LK._trail_pos(e), LK.STG_GLOBAL)
        end
    end
    return nothing
end


# ---- the heap ----
"""
A heap with a garbage gap (dead terms, a DEAD float among them in the middle of the value table and one at its end), an easy and a
scanned mark, trailed bindings, a kept assignment and a live float in a slot; returns the engine and its handles.
The foreign frames F0 (the engine's), F1 (inside the gap), F2 (top of the gap), F3 (its top cell is marked), F4 (garbage above it).
"""
function _gc6_heap()
    X = _rv(1)
    ld, t, n0 = _gc6_engine(
        _R[
            _rf("f", _rs("a"), X, _rf("g", X, _rg(Int64(3))), _rg(1234.5678)),
            _rf("h", _rg("gs-string"), _rints(1:5), X),
            _rg(2.5),                                           # slot t + 3 holds a value-table word (ruling D1)
        ]
    )
    f0 = ld.fli_context
    c1 = LK.allocGlobalCells!(ld, 1)
    c2 = LK.allocGlobalCells!(ld, 1)
    cv = LK.allocGlobalCells!(ld, 1)
    tr = LK.PL_new_term_refs(ld, 3)
    ld.slots[tr + 1] = LK.makeRefG(c1)
    ld.slots[tr + 2] = LK.makeRefG(cv)
    LK.putSlotValue!(ld, tr + 3, _rf("old", _rg(Int64(1)), _rf("older", _rg(Int64(2)))), LK.PutVarMap())
    ld.gstack[cv] = ld.slots[tr + 3] & LK.VALUE_MASK
    ld.slots[tr + 3] = _gc6_atom(ld, "x")
    td = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, td + 1, _rf("dead", _rg(Int64(1)), _rf("dead2", _rg(Int64(2)), _rints(1:4))), LK.PutVarMap())
    ld.slots[td + 1] = _gc6_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f1 = ld.fli_context
    td2 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, td2 + 1, _rf("dead3", _rg(Int64(3)), _rg(3.75), _rints(1:6)), LK.PutVarMap())   # a dead box, NOT the last entry
    ld.slots[td2 + 1] = _gc6_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f2 = ld.fli_context
    LK._bind_const!(ld, c1, _gc6_atom(ld, "one"))
    LK._bind_const!(ld, c2, _gc6_atom(ld, "two"))
    LK.TrailAssignment!(ld, cv)
    ld.gstack[cv] = _gc6_atom(ld, "y")
    tl = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, tl + 1, _rg(8.5), LK.PutVarMap())      # a live box AFTER the dead one
    tp = LK.PL_new_term_ref(ld)
    p = LK.allocGlobalCells!(ld, 1)
    ld.slots[tp + 1] = LK.makeRefG(p)
    LK.PL_open_foreign_frame(ld)
    f3 = ld.fli_context
    td3 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, td3 + 1, _rf("dead4", _rg(Int64(4)), _rg(4.5), _rints(1:7)), LK.PutVarMap())   # the LAST value-table entry, dead
    ld.slots[td3 + 1] = _gc6_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f4 = ld.fli_context
    return (ld = ld, t = t, tl = tl, n0 = n0, f0 = f0, f1 = f1, f2 = f2, f3 = f3, f4 = f4, c1 = c1, c2 = c2, cv = cv, p = p)
end

"The real marks of the engine as `(kind, index, mark)`: the foreign frames (`:f`) and the choicepoints from `BFR` (`:c`)."
function _gc6_marks(ld; choices::Bool = false)
    out = Tuple{Symbol, Int, LK.mark}[]
    fr = ld.fli_context
    while fr != 0
        LK.isRealMark(ld.fliframes[fr].mark) && push!(out, (:f, fr, ld.fliframes[fr].mark))
        fr = ld.fliframes[fr].parent
    end
    ch = choices ? ld.BFR : 0
    while ch != 0
        push!(out, (:c, ch, ld.choices[ch].mark))
        ch = ld.choices[ch].parent
    end
    return out
end

"The mark of `(kind, index)` as it is now."
_gc6_mark_now(ld, kind::Symbol, i::Int)::LK.mark = kind === :f ? ld.fliframes[i].mark : ld.choices[i].mark

"""
The heap marked, the trail begun and tagged, the deliberate bars set; returns the handles, `st`, the roots and the reachable set `reach`
(the walk by tags), and `pre` — the stacks as the trail phase will find them (marks carry their bits).
"""
function _gc6_prepare(H)
    ld = H.ld
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    roots = _gc6_fli_roots(ld)
    for e in ld.trail
        e != 0 && LK.isTrailVal(e) && push!(roots, LK.makeRefG(LK.trailValP(e)))
    end
    reach = _gc6_reach(ld, roots)
    ts = LK.gc_trail_begin!(ld)
    LK.tag_trail(ld, ts)
    m4 = ld.fliframes[H.f4].mark                                # the saved bar above every cell: the clamp row
    ld.fliframes[H.f4].mark = LK.mark(m4.trailtop, m4.globaltop, LK.NO_MARK_BAR)
    m3 = ld.fliframes[H.f3].mark                                # a low saved bar, inside the gap
    ld.fliframes[H.f3].mark = LK.mark(m3.trailtop, m3.globaltop, ld.fliframes[H.f1].mark.globaltop)
    m0 = ld.fliframes[H.f0].mark                                # a height of 0: no cell below it
    ld.fliframes[H.f0].mark = LK.mark(m0.trailtop, m0.globaltop, 0)
    return merge(H, (st = st, ts = ts, roots = roots, reach = reach))
end

"The stacks, the value table and the marks as they are now."
_gc6_pre(ld) = (g = copy(ld.gstack), s = copy(ld.slots), tr = copy(ld.trail), gTop = ld.gTop, lTop = ld.lTop,
    vbox = copy(ld.vbox), vtable = copy(ld.vtable), marks = _gc6_marks(ld))

# ---- the independent model ----
const _GC6_BITS = UInt64(0x1f)                                  # tag (3 bits) and storage (2 bits) of a word

"`live` = the cells marked in `g`, in order; `rank` = each cell's new position (its rank among them)."
function _gc6_live(g::Vector{UInt64}, n::Int)
    live = Int[p for p in 1:n if LK.is_marked(g[p])]
    rank = Dict{Int, Int}(p => i for (i, p) in enumerate(live))
    return live, rank
end

"A word (no gc bits) with the global reference it holds rewritten to the new position of its target."
function _gc6_rewrite(w::UInt64, rank::Dict{Int, Int})::UInt64
    (_gc6_is_global(w) && !LK._is_vword(w)) || return w
    tgt = Int(w >> LK.LMASK_BITS)
    haskey(rank, tgt) || error("_gc6_rewrite: a reference to the unmarked cell $(tgt)")
    return (UInt64(rank[tgt]) << LK.LMASK_BITS) | (w & _GC6_BITS)
end

"A tagged trail entry with its position rewritten."
function _gc6_rewrite_trail(w::UInt64, rank::Dict{Int, Int})::UInt64
    pos = Int((w & LK.VALUE_MASK) >> LK.LMASK_BITS)
    haskey(rank, pos) || error("_gc6_rewrite_trail: an entry for the unmarked cell $(pos)")
    return (UInt64(rank[pos]) << LK.LMASK_BITS) | (w & _GC6_BITS)
end

"The new height of the old height `h`: the number of live cells at or below it."
_gc6_newh(live::Vector{Int}, h::Int)::Int = count(<=(h), live)

"The cells of the global stack: THE extractor of the actual side (`1:gTop`)."
_gc6_cells(ld)::Vector{UInt64} = ld.gstack[1:(ld.gTop)]

"The cells the model expects: the live cells of `g` in order, references rewritten (the model side of the one comparison)."
_gc6_expect_cells(g::Vector{UInt64}, live::Vector{Int}, rank::Dict{Int, Int})::Vector{UInt64} =
    UInt64[_gc6_rewrite(g[p] & LK.VALUE_MASK, rank) for p in live]

"The expected new count of a trail mark `c` (an entry count): the count less the deleted entries at indices `<= c`."
_gc6_newcount(tr::Vector{UInt64}, c::Int)::Int = c - count(==(UInt64(0)), view(tr, 1:min(c, length(tr))))

"""
Everything the collection must have done, against the model, as a list of problems (empty = none): the cells, the slots, the trail,
the value table, the marks, and no gc bit left anywhere. `gcatom` (optional) is the word an unmarked global-reference slot may have become.
"""
function _gc6_problems(ld, pre, live::Vector{Int}, rank::Dict{Int, Int}; gcatom = nothing)::Vector{String}
    bad = String[]
    want = _gc6_expect_cells(pre.g, live, rank)
    got = _gc6_cells(ld)
    got == want || push!(bad, "cells differ: first at $(findfirst(i -> get(got, i, 0) != get(want, i, 1), 1:max(length(got), length(want)))) of $(length(got)) vs $(length(want))")
    ld.gTop == length(live) || push!(bad, "gTop $(ld.gTop) != live cells $(length(live))")
    any(w -> LK.is_marked(w) || LK.is_first(w), got) && push!(bad, "a gc bit is left on the global stack")
    for i in 1:(pre.lTop)
        w = pre.s[i]
        exp = LK.is_marked(w) ? _gc6_rewrite(w & LK.VALUE_MASK, rank) : w
        have = ld.slots[i]
        (have == exp || (gcatom !== nothing && !LK.is_marked(w) && have == gcatom)) || push!(bad, "slot $(i): $(have) expected $(exp)")
        (LK.is_marked(have) || LK.is_first(have)) && push!(bad, "slot $(i) keeps a gc bit")
    end
    kept = UInt64[w for w in view(pre.tr, 1:(length(pre.tr) - 1)) if w != 0]
    wantt = vcat(UInt64[_gc6_rewrite_trail(w, rank) for w in kept], UInt64[0])
    ld.trail == wantt || push!(bad, "trail differs: $(length(ld.trail)) entries, expected $(length(wantt))")
    wantb = Int[p == 0 ? 0 : get(rank, p, 0) for p in pre.vbox]
    while !isempty(wantb) && wantb[end] == 0
        pop!(wantb)
    end
    ld.vbox == wantb || push!(bad, "vbox $(ld.vbox), expected $(wantb)")
    length(ld.vtable) == length(ld.vbox) || push!(bad, "vtable length $(length(ld.vtable)) != vbox length $(length(ld.vbox))")
    for (i, b) in enumerate(ld.vbox)
        b == 0 && continue
        w = ld.gstack[b]
        (LK._is_vword(w) && Int(w >> LK.LMASK_BITS) == i) || push!(bad, "box $(i) at $(b) is not its own vword")
        i <= length(pre.vtable) && ld.vtable[i] === pre.vtable[i] || push!(bad, "value $(i) changed")
    end
    for (kind, i, m0) in pre.marks
        exp = LK.mark(_gc6_newcount(pre.tr, m0.trailtop), _gc6_newh(live, m0.globaltop), _gc6_newh(live, min(m0.saved_bar, pre.gTop)))
        _gc6_mark_now(ld, kind, i) == exp || push!(bad, "mark $(kind)$(i): $(_gc6_mark_now(ld, kind, i)), expected $(exp)")
    end
    return bad
end

"The heap prepared, `gc_trail_phase` run; with `collect = true` also `collect_phase` (mark_bar set to 5 before it). Returns the handles, `pre`, `mid`, counters."
function _gc6_run(; collect::Bool = true)
    P = _gc6_prepare(_gc6_heap())
    ld = P.ld
    pre = _gc6_pre(ld)
    sw = LK.gc_sweep_counts()
    vm = LK.vm_state()
    top = LK.gc_trail_phase(ld, P.st, sw, P.ts, vm)
    mid = (tr = copy(ld.trail), marks = _gc6_marks(ld), top = top, relocated = sw.relocated_cells, cells = sw.relocation_cells,
        chains = sw.relocation_chains, alien = sw.alien_relocations)
    ld.mark_bar = 5
    nv = collect ? LK.collect_phase(ld, P.st, sw, vm) : -1
    live, rank = _gc6_live(pre.g, pre.gTop)
    return merge(P, (pre = pre, mid = mid, sw = sw, nv = nv, live = live, rank = rank, vm = vm))
end

@testset "compaction: the cells, slots, trail, value table and marks equal the model" begin
    R = _gc6_run()
    ld, pre = R.ld, R.pre
    @test R.reach == Set(R.live)                                # the model's live cells are the marked cells, both non-empty
    @test length(R.live) >= 15 && !isempty(R.roots)
    @test length(R.live) == R.st.total_marked
    @test pre.gTop - length(R.live) >= 10                       # garbage was removed
    @test count(p -> R.rank[p] != p, R.live) >= 5               # cells did move
    @test count(==(UInt64(0)), view(pre.tr, 1:(length(pre.tr) - 1))) >= 1   # early reset deleted a trail entry
    @test count(!=(UInt64(0)), view(pre.tr, 1:(length(pre.tr) - 1))) >= 3
    @test _gc6_problems(ld, pre, R.live, R.rank) == String[]
    @test ld.gTop == R.st.total_marked <= pre.gTop
    @test ld.mark_bar == 5                                      # collect_phase leaves mark_bar alone
    @test R.sw.relocation_chains == 0 && R.sw.relocated_cells == R.sw.relocation_cells > 0
    @test R.ts.top == length(ld.trail) && ld.trail[end] == 0    # the sentinel is at the new top
    @test length(ld.vbox) == length(pre.vbox) - 1               # the dead box at the end was truncated
    @test any(==(0), ld.vbox)                                   # the dead box in the middle is a tombstone
    @test count(!=(0), ld.vbox) >= 4                            # the live boxes are re-pointed
end

@testset "collect_phase returns the references to value-table boxes, which the mark phase counted" begin
    R = _gc6_run()
    pre = R.pre
    boxpos = Set(p for p in pre.vbox if p != 0)
    n = count(p -> LK._is_vword(pre.g[p] & LK.VALUE_MASK) && !(p in boxpos), R.live)    # marked cells holding a vword (not the boxes)
    n += count(w -> LK.is_marked(w) && LK._is_vword(w & LK.VALUE_MASK), view(pre.s, 1:(pre.lTop)))
    @test n >= 3                                                # compound arguments and slots: not vacuous
    @test R.nv == n
    @test R.st.needs_relocation - R.sw.relocated_cells == n
end

@testset "gc_trail_phase: deleted entries are gone, a mark's trailtop names the new count + 1" begin
    R = _gc6_run(collect = false)
    ld, pre, mid = R.ld, R.pre, R.mid
    zeroed = count(==(UInt64(0)), view(pre.tr, 1:(length(pre.tr) - 1)))
    kept = UInt64[w for w in view(pre.tr, 1:(length(pre.tr) - 1)) if w != 0]
    @test zeroed >= 1 && length(kept) >= 3
    @test mid.tr == vcat(kept, UInt64[0])                       # entries in order, the sentinel at the end
    @test mid.top == length(mid.tr) == R.ts.top
    @test R.ts.zeroed == zeroed && R.ts.kept == length(kept)
    @test !isempty(mid.marks) && length(mid.marks) >= 5
    for (kind, i, m0) in pre.marks
        w = reinterpret(UInt64, _gc6_mark_now(ld, kind, i).trailtop)
        @test LK.storage(w) == LK.STG_STATIC
        @test Int(w >> LK.LMASK_BITS) - 1 == _gc6_newcount(pre.tr, m0.trailtop)
    end
    @test R.ts.chains == length(unique(m.trailtop for (_, _, m) in pre.marks))   # one chain per distinct trail height
    @test mid.alien == length(pre.marks) && mid.relocated == mid.cells == length(pre.marks)
    @test mid.chains == 0
    @test any(m.trailtop != _gc6_newcount(pre.tr, m.trailtop) for (_, _, m) in pre.marks)   # a count really changed
end

@testset "gc_check_trail_chains: balanced counters pass, an unbalanced or open chain throws" begin
    sw = LK.gc_sweep_counts()
    @test LK.gc_check_trail_chains(sw) === nothing
    sw.relocation_cells = 2
    sw.relocated_cells = 2
    @test LK.gc_check_trail_chains(sw) === nothing
    sw.relocated_cells = 1
    @test_throws ErrorException LK.gc_check_trail_chains(sw)
    sw.relocated_cells = 2
    sw.relocation_chains = 1
    @test_throws ErrorException LK.gc_check_trail_chains(sw)
end

"A hand-marked heap: every cell an atom; the cells `live` marked, a downward and an upward reference among them, a chain head inside the garbage run (`head_top`: ON its topmost cell n - 4, which the main scan meets before any run)."
function _gc6_wb(; total::Union{Nothing, Int} = nothing, head_top::Bool = false)
    ld, t, n0 = _gc6_engine(_R[_rf("k", _rs("a"), _rv(1))])
    ld.gTop < 14 && LK.allocGlobalCells!(ld, 14 - ld.gTop)
    n = ld.gTop
    a = _gc6_atom(ld, "w")
    for p in 1:n
        ld.gstack[p] = a
    end
    live = [3, 4, n - 3, n - 2, n - 1, n]
    ld.gstack[n - 1] = LK.makeRefG(4)                           # downward
    ld.gstack[4] = LK.makeRefG(n - 2)                           # upward
    for p in live
        ld.gstack[p] = LK.set_marked(ld.gstack[p])
    end
    f = ld.fli_context
    m0 = ld.fliframes[f].mark
    ld.fliframes[f].mark = LK.mark(m0.trailtop, head_top ? n - 4 : 7, 0)   # a raw height naming a GARBAGE cell (7, or the top one n - 4)
    sw = LK.gc_sweep_counts()
    LK.alien_into_relocation_chain(ld, sw, LK._gcs_mfield(true, f, 0), LK.STG_GLOBAL)
    st = LK.gc_mark_counts()
    st.total_marked = total === nothing ? length(live) : total
    return (ld = ld, st = st, sw = sw, f = f, n = n, live = live, pre = _gc6_pre(ld))
end

@testset "compact_global on a hand-marked heap: moves, chains, hole, tombstone-free" begin
    for head_top in (false, true)                               # the head inside the run (downskip unwinds it) and on its top cell (the main scan does)
        W = _gc6_wb(head_top = head_top)
        ld, n, live = W.ld, W.n, W.live
        @test n >= 14 && W.sw.relocation_chains == 1 && W.sw.relocation_cells == 1
        lv, rank = _gc6_live(W.pre.g, W.pre.gTop)
        @test lv == live
        want = _gc6_expect_cells(W.pre.g, live, rank)
        @test length(want) == 6   # the downward (live[5], cell n-1) and the upward (live[2], cell 4) references were rewritten (non-vacuous)
        @test want[5] != (W.pre.g[n - 1] & LK.VALUE_MASK) && want[2] != (W.pre.g[4] & LK.VALUE_MASK)
        LK.compact_global(ld, W.st, W.sw)
        @test _gc6_cells(ld) == want
        @test ld.gTop == 6
        @test W.sw.relocation_chains == 0 && W.sw.relocated_cells == W.sw.relocation_cells == 3
        got = reinterpret(UInt64, ld.fliframes[W.f].mark.globaltop)  # the head in the garbage was unwound at the number of live cells below it
        @test got == (UInt64(2) << LK.LMASK_BITS) | LK.STG_GLOBAL
        @test all(==(UInt64(0)), ld.gstack[7:(n - 4)])          # the garbage run is a hole (zeroed), below the new top nothing of it is left
        @test !any(w -> LK.is_marked(w) || LK.is_first(w), _gc6_cells(ld))
    end
    W2 = _gc6_wb(total = 7)
    @test_throws ErrorException LK.compact_global(W2.ld, W2.st, W2.sw)
end

@testset "downskip_combine_garbage: the run becomes a hole only above 4 cells, the chain of its head is unwound" begin
    ld, t, n0 = _gc6_engine(_R[_rf("k", _rs("a"), _rv(1))])
    base = LK.allocGlobalCells!(ld, 12)
    @test base > 1
    a = _gc6_atom(ld, "w")
    fill!(view(ld.gstack, base:(base + 11)), a)
    ld.gstack[base - 1] = LK.set_marked(ld.gstack[base - 1])
    marked_before = ld.gstack[base - 1]
    sw = LK.gc_sweep_counts()
    @test LK.downskip_combine_garbage(ld, sw, base + 11, 5) == base
    @test all(==(UInt64(0)), ld.gstack[base:(base + 11)])       # 12 cells: a hole
    @test ld.gstack[base - 1] == marked_before                  # the marked cell below is not touched
    fill!(view(ld.gstack, base:(base + 11)), a)
    @test LK.downskip_combine_garbage(ld, sw, base + 4, 5) == base
    @test all(==(a), ld.gstack[base:(base + 11)])               # 5 cells: top - bottom = 4, no hole
    f = ld.fli_context
    m0 = ld.fliframes[f].mark
    ld.fliframes[f].mark = LK.mark(m0.trailtop, base + 7, m0.saved_bar)
    LK.alien_into_relocation_chain(ld, sw, LK._gcs_mfield(true, f, 0), LK.STG_GLOBAL)
    @test sw.relocation_chains == 1
    @test LK.downskip_combine_garbage(ld, sw, base + 11, 5) == base
    @test sw.relocation_chains == 0 && sw.relocated_cells == 1
    @test reinterpret(UInt64, ld.fliframes[f].mark.globaltop) == (UInt64(5) << LK.LMASK_BITS) | LK.STG_GLOBAL
    @test all(==(UInt64(0)), ld.gstack[base:(base + 11)])
    n = ld.gTop                                                 # garbage down to the BOTTOM of the stack: the hole starts at position 1
    fill!(view(ld.gstack, 1:n), a)
    @test n >= 12 && LK.downskip_combine_garbage(ld, sw, n, 5) == 1
    @test all(==(UInt64(0)), ld.gstack[1:n])
end

@testset "value table: tombstones for the dead boxes, the end of the table is truncated" begin
    ld, t, n0 = _gc6_engine(_R[_rg(1.5), _rg(2.5), _rg(3.5)])
    nb = length(ld.vbox)
    @test nb == n0 + 3
    mid = n0 + 2
    for i in 1:nb
        i == mid || (ld.gstack[ld.vbox[i]] = LK.set_marked(ld.gstack[ld.vbox[i]]))
    end
    before = copy(ld.vbox)
    @test LK.gc_tombstone_boxes!(ld) == 1
    @test ld.vbox[mid] == 0 && ld.vbox[[i for i in 1:nb if i != mid]] == before[[i for i in 1:nb if i != mid]]
    @test LK.gc_tombstone_boxes!(ld) == 0                       # a tombstone is skipped (no cell 0), nothing more is dead
    LK.gc_truncate_vtable!(ld)
    @test length(ld.vbox) == nb && length(ld.vtable) == nb      # the last entry is live: nothing popped
    ld.vbox[nb] = 0                                             # the end is a tombstone, and the middle one is adjacent to it: both go
    LK.gc_truncate_vtable!(ld)
    @test length(ld.vbox) == n0 + 1 && length(ld.vtable) == n0 + 1
    ld.gTop = ld.vbox[end] - 1                                  # a box above gTop is dropped too
    LK.gc_truncate_vtable!(ld)
    @test length(ld.vbox) == n0 && length(ld.vtable) == n0
end

@testset "unsweep_mark: the fields are decoded (count = valPtr - 1), counters; an unrelocated field is an error" begin
    H = _gc6_heap()
    ld = H.ld
    frs = Int[k for (kind, k, _) in _gc6_marks(ld) if kind === :f]
    @test length(frs) >= 5
    for (j, fr) in enumerate(frs)
        enc(pos, stg) = reinterpret(Int, LK.consPtr(pos, stg))
        ld.fliframes[fr].mark = LK.mark(enc(j + 1, LK.STG_STATIC), enc(10 + j, LK.STG_GLOBAL), enc(20 + j, LK.STG_GLOBAL))
    end
    @test LK.unsweep_foreign(ld) == length(frs)
    for (j, fr) in enumerate(frs)
        @test ld.fliframes[fr].mark == LK.mark(j, 10 + j, 20 + j)   # trailtop - 1, the other two as they are (a swap would show)
    end
    ld.fliframes[frs[1]].mark = LK.mark(5, 3, 2)                # raw heights: no chain left a pointer word in the field
    @test_throws ErrorException LK.unsweep_mark(ld, true, frs[1])
    for (j, fr) in enumerate(frs)                               # heights again; one frame gets a NoMark: it is no real mark, left alone and not counted
        enc(pos, stg) = reinterpret(Int, LK.consPtr(pos, stg))
        ld.fliframes[fr].mark = LK.mark(enc(j + 1, LK.STG_STATIC), enc(10 + j, LK.STG_GLOBAL), enc(20 + j, LK.STG_GLOBAL))
    end
    ld.fliframes[frs[2]].mark = LK.NoMark()
    @test LK.unsweep_foreign(ld) == length(frs) - 1
    @test ld.fliframes[frs[2]].mark == LK.NoMark() && ld.fliframes[frs[3]].mark == LK.mark(3, 13, 23)
end

@testset "gc_alien_trailtops chains the trail top of every real foreign-frame mark, not of a NoMark" begin
    P = _gc6_prepare(_gc6_heap())
    ld = P.ld
    nreal = length(_gc6_marks(ld))
    @test nreal >= 5
    ld.fliframes[P.f2].mark = LK.NoMark()
    sw = LK.gc_sweep_counts()
    LK.gc_alien_trailtops(ld, P.st, sw, LK.vm_state())
    @test sw.alien_relocations == nreal - 1
    @test sw.relocation_cells == nreal - 1 && sw.relocated_cells == 0 && sw.relocation_chains >= 1
    @test ld.fliframes[P.f2].mark == LK.NoMark()
end

@testset "live query: unsweep_environments names the query, gc_choice_indices walks the choicepoints, unsweep_choicepoints decodes them" begin
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    ]
    db = _rdb(clauses)
    ld = db.ld
    ran = Ref(0)
    _rcall(
        db, _rf("n", _rv(90));
        at = (qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            chs = Int[]
            ch = ld.BFR
            while ch != 0
                push!(chs, ch)
                ch = ld.choices[ch].parent
            end
            @test length(chs) >= 2
            cl = first(c for c in chs if ld.choices[c].type == LK.CHP_CLAUSE)
            fi = ld.choices[cl].frame
            @test fi != 0 && ld.frames[fi].parent == 0
            qf = LK.queryOfFrame(ld, fi)
            @test LK.unsweep_environments(ld, fi) == qf
            vm = LK.vm_state()
            vm.frame = fi
            vm.choice = ld.BFR
            @test LK.gc_choice_indices(ld, vm) == chs
            saved = [ld.choices[c].mark for c in chs]
            for (j, c) in enumerate(chs)
                enc(pos, stg) = reinterpret(Int, LK.consPtr(pos, stg))
                ld.choices[c].mark = LK.mark(enc(j + 1, LK.STG_STATIC), enc(10 + j, LK.STG_GLOBAL), enc(20 + j, LK.STG_GLOBAL))
            end
            @test LK.unsweep_choicepoints(ld, ld.BFR) == length(chs)
            @test all(j -> ld.choices[chs[j]].mark == LK.mark(j, 10 + j, 20 + j), eachindex(chs))
            for (j, c) in enumerate(chs)
                enc(pos, stg) = reinterpret(Int, LK.consPtr(pos, stg))
                ld.choices[c].mark = LK.mark(enc(j + 1, LK.STG_STATIC), enc(10 + j, LK.STG_GLOBAL), enc(20 + j, LK.STG_GLOBAL))
            end
            @test LK.unsweep_stacks(ld, vm) == length(chs)
            @test all(j -> ld.choices[chs[j]].mark == LK.mark(j, 10 + j, 20 + j), eachindex(chs))
            for (j, c) in enumerate(chs)
                ld.choices[c].mark = saved[j]
            end
        end,
    )
    @test ran[] >= 1
end

# NQ: a NESTED query. `q.parent == 0` ends the walk of gc_choice_indices and unsweep_stacks (pl-gccompact.jl): for a top query `saved_environment` is 0, so the
# loop ends by itself and a single-query row cannot see the `break`; a query opened while another is open (its parent) must be followed into the parent's choicepoints.
# The nested query is opened by hand at the first answer of the outer one (a foreign callback's PL_open_query); `ld.environment_frame` is the outer query's frame, set
# by hand when the engine left it 0, and put back with the nested query closed.
@testset "nested query: gc_choice_indices and unsweep_stacks continue into the choicepoints of the parent query (q.parent != 0)" begin
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    ]
    db = _rdb(clauses)
    gd, ld = db.gd, db.ld
    ran = Ref(0)
    _rcall(
        db, _rf("n", _rv(90));
        at = (qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            qf1 = ld.query
            chain(ch0) = (c = Int[]; ch = ch0; while ch != 0; push!(c, ch); ch = ld.choices[ch].parent; end; c)
            chs1 = chain(ld.BFR)                                   # the outer query's choicepoints
            @test length(chs1) >= 2 && ld.queries[qf1].parent == 0
            env0 = ld.environment_frame
            ld.environment_frame == 0 && (ld.environment_frame = ld.queries[qf1].frame)
            fid2 = LK.PL_open_foreign_frame(ld)
            args2 = LK.PL_new_term_refs(ld, 1)
            LK.putSlotValue!(ld, args2 + 1, _rv(91), LK.PutVarMap())
            qid2 = LK.PL_open_query(
                gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, _rf("n", _rv(1))), args2
            )
            @test qid2 != 0
            @test LK.PL_next_solution(gd, ld, qid2) == LK.PL_S_TRUE
            qf2 = ld.query
            q2 = ld.queries[qf2]
            @test qf2 != qf1 && q2.parent == qf1                   # the nested query's parent is the outer one
            @test q2.saved_environment != 0 && q2.saved_bfr == chs1[1]
            chs2 = chain(ld.BFR)                                   # the nested query's own choicepoints
            @test length(chs2) >= 2 && isdisjoint(chs1, chs2)
            cl = findfirst(c -> ld.choices[c].type == LK.CHP_CLAUSE, chs2)
            @test cl !== nothing
            fi2 = ld.choices[chs2[cl]].frame
            @test fi2 != 0 && LK.gc_top_query(ld, fi2) == qf2
            vm = LK.vm_state()
            vm.frame = fi2
            vm.choice = ld.BFR
            vm.pc_start_vmi = 0
            all_chs = vcat(chs2, chs1)
            @test LK.gc_choice_indices(ld, vm) == all_chs          # NQ: the walk goes on into the parent's chain (G1GC6A-W2)
            saved = [ld.choices[c].mark for c in all_chs]
            for (j, c) in enumerate(all_chs)
                enc(pos, stg) = reinterpret(Int, LK.consPtr(pos, stg))
                ld.choices[c].mark = LK.mark(enc(j + 1, LK.STG_STATIC), enc(10 + j, LK.STG_GLOBAL), enc(20 + j, LK.STG_GLOBAL))
            end
            @test LK.unsweep_stacks(ld, vm) == length(chs2) + length(chs1)    # NQ: and so does unsweep_stacks (G1GC6A-U5)
            @test all(j -> ld.choices[all_chs[j]].mark == LK.mark(j, 10 + j, 20 + j), eachindex(all_chs))
            for (j, c) in enumerate(all_chs)
                ld.choices[c].mark = saved[j]
            end
            LK.PL_close_query(ld, qid2)
            LK.PL_close_foreign_frame(ld, fid2)
            ld.environment_frame = env0
            @test ld.query == qf1
        end,
    )
    @test ran[] >= 1
end

@testset "corruptions of the comparison MUST FAIL" begin
    R = _gc6_run()
    ld, pre = R.ld, R.pre
    @test _gc6_problems(ld, pre, R.live, R.rank) == String[]    # the can-pass half
    targets = Int[]                                             # cells that a reference names
    for p in R.live
        w = pre.g[p] & LK.VALUE_MASK
        (_gc6_is_global(w) && !LK._is_vword(w)) && push!(targets, Int(w >> LK.LMASK_BITS))
    end
    ts = unique(targets)
    @test length(ts) >= 4
    rank2 = copy(R.rank)
    rank2[ts[1]], rank2[ts[2]] = rank2[ts[2]], rank2[ts[1]]     # two ranks swapped
    @test !isempty(_gc6_problems(ld, pre, R.live, rank2))
    ex = _gc6_expect_cells(pre.g, R.live, R.rank)
    k = findfirst(i -> ex[i] != ex[i + 1], 1:(length(ex) - 1))  # two neighbours whose model words differ
    @test k !== nothing
    live2 = copy(R.live)
    live2[k], live2[k + 1] = live2[k + 1], live2[k]             # two live cells in the wrong order
    @test !isempty(_gc6_problems(ld, pre, live2, R.rank))
    save = ld.gstack[3]
    ld.gstack[3] = save ⊻ (UInt64(1) << LK.LMASK_BITS)          # a cell of the compacted heap altered
    @test !isempty(_gc6_problems(ld, pre, R.live, R.rank))
    ld.gstack[3] = save
    @test _gc6_problems(ld, pre, R.live, R.rank) == String[]
end
