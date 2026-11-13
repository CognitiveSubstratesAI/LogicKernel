# ORIGINAL: white-box tests of the stack collector's SWEEP and its RELOCATION CHAINS (G1-GC G1-5: src/pl-gcsweep.jl; upstream's
# pl-gc.c `sweep_foreign`, `sweep_trail`, `sweep_stacks`, `into_relocation_chain`, `update_relocation_chain`); swipl observes the chains only
# through its own collector (they are internal pointer reversals), so no row consults swipl and no testset can run without an assertion.
# test/core_lang/test_gc_sweep.jl — the mark phase on a built heap, then the three sweeps IN UPSTREAM'S ORDER (foreign frames, trail, stacks):
#   * the chains are compared with an INDEPENDENT model (`_GSModel`): from the reachable cells (a plain walk by tags, no mark bit), the
#     frames, the trail and the marks as the test reads them, the model lists for every marked cell the referrers it must get, in the order
#     the sweep visits them; a chain is read back with the test's OWN decode of the pointer words (`_gs_decode`, `_gs_chain`);
#     ONE extractor (`_gs_problems`) serves the rows and the corruption rows;
#   * unwinding with the identity destination restores every word; with another destination every referrer holds the new position and
#     keeps its tag; the fillers of the skipped garbage regions and the new height of every mark are compared with the model;
#   * a corruption of a chain (a cleared FIRST bit, the wrong order) MUST FAIL the comparison.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_gs_atom(ld, n) = LK._atom_word!(ld, _rs(n))

"An engine with the values of `vs` (at least one) put into term references of an open foreign frame: `(ld, t, n0)` — `t` the first reference, `n0` the size of the value table before."
function _gs_engine(vs::Vector{_R})
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
function _gs_fli_roots(ld)::Vector{UInt64}
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
function _gs_reach(ld, roots::Vector{UInt64})::Set{Int}
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
_gs_is_global(w::UInt64)::Bool =
    (LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL) || LK.isAttVar(w) || LK._is_gcompound(w) || LK._is_vword(w)

"The positions of the global cells whose MARK bit is set."
_gs_marked(ld)::Set{Int} = Set{Int}(p for p in 1:(ld.gTop) if LK.is_marked(ld.gstack[p]))

"The stacks as they are: global cells, slots and the trail."
_gs_snapshot(ld) = (g = copy(ld.gstack), s = copy(ld.slots), tr = copy(ld.trail))

"Put the stacks back as `sn` took them (the trail keeps its length)."
function _gs_restore!(ld, sn)
    length(ld.trail) == length(sn.tr) || error("_gs_restore!: the trail length changed")
    copyto!(ld.gstack, sn.g)
    copyto!(ld.slots, sn.s)
    copyto!(ld.trail, sn.tr)
    return nothing
end

"The words the frame at index `fi` holds in its argument slots (no gc bits)."
function _gs_frame_args(ld, fi::Int)::Vector{UInt64}
    f = ld.frames[fi]
    return UInt64[ld.slots[LK.argFrameP(f.base, n) + 1] & LK.VALUE_MASK for n in 0:(f.predicate.arity - 1)]
end

"The trail in upstream's tagged form (pl-gc.c `tag_trail`, the test's own copy): 0 stays, an address entry becomes a GLOBAL pointer, a value entry one with TAG_TRAILVAL."
function _gs_tag_trail!(ld)::Nothing
    for i in eachindex(ld.trail)
        e = ld.trail[i]
        e == 0 && continue
        if LK.isTrailVal(e)
            ld.trail[i] = LK.consPtr(LK.trailValP(e), LK.STG_GLOBAL | LK.TAG_TRAILVAL)
        else
            LK._trail_stack(e) == LK.TRAIL_GLOBAL || error("_gs_tag_trail!: a trail entry outside the global stack")
            ld.trail[i] = LK.consPtr(LK._trail_pos(e), LK.STG_GLOBAL)
        end
    end
    return nothing
end

# ---- the pointer words, decoded by the test itself ----
const _GS_MFIELD = 2^41                                         # a mark field's position (the design constant of the addressing)

"A pointer word as a descriptor: `(:g, cell)`, `(:t, trail index)`, `(:s, slot)` or `(:m, isfli, i, field)` (a mark field: 0 globaltop, 1 saved_bar, 2 trailtop)."
function _gs_decode(w::UInt64)
    pos = Int((w & LK.VALUE_MASK) >> LK.LMASK_BITS)
    s = LK.storage(w)
    s == LK.STG_GLOBAL && return (:g, pos)
    s == LK.STG_STATIC && return (:t, pos)
    if pos >= _GS_MFIELD
        k = pos - _GS_MFIELD
        return (:m, (k & 4) != 0, k >> 3, k & 3)
    end
    return (:s, pos)
end

"The word (as stored) at a descriptor; a mark field is its Int reinterpreted."
function _gs_word(ld, d)::UInt64
    d[1] === :s && return ld.slots[d[2]]
    d[1] === :t && return ld.trail[d[2]]
    d[1] === :g && return ld.gstack[d[2]]
    m = d[2] ? ld.fliframes[d[3]].mark : ld.choices[d[3]].mark
    f = d[4]
    return reinterpret(UInt64, f == 0 ? m.globaltop : f == 1 ? m.saved_bar : m.trailtop)
end

"Store `w` at a descriptor (a mark field is rebuilt as a new `mark`)."
function _gs_setword!(ld, d, w::UInt64)::Nothing
    if d[1] === :s
        ld.slots[d[2]] = w
    elseif d[1] === :t
        ld.trail[d[2]] = w
    elseif d[1] === :g
        ld.gstack[d[2]] = w
    else
        i = d[3]
        m = d[2] ? ld.fliframes[i].mark : ld.choices[i].mark
        v = reinterpret(Int, w)
        nm = d[4] == 0 ? LK.mark(m.trailtop, v, m.saved_bar) : d[4] == 1 ? LK.mark(m.trailtop, m.globaltop, v) : LK.mark(v, m.globaltop, m.saved_bar)
        if d[2]
            ld.fliframes[i].mark = nm
        else
            ld.choices[i].mark = nm
        end
    end
    return nothing
end

"The chain whose head holds the word `head_word`, read back: the referrers, newest first."
function _gs_chain_word(ld, head_word::UInt64)::Vector{Any}
    out = Any[]
    cur = _gs_decode(head_word)
    for _ in 1:100_000
        push!(out, cur)
        w = _gs_word(ld, cur)
        LK.is_first(w) || return out
        cur = _gs_decode(w)
    end
    error("_gs_chain_word: a runaway chain")
end

"The chain of the head cell `h` read back from the stacks: the referrers, newest first."
_gs_chain(ld, h::Int)::Vector{Any} = _gs_chain_word(ld, ld.gstack[h])

# ---- the independent model of what the sweep must do ----
mutable struct _GSModel
    order::Dict{Int, Vector{Any}}                               # head cell => its referrers, in the order the sweep visits them (oldest first)
    newh::Dict{Tuple{Bool, Int, Int}, Int}                      # (isfli, i, field) of a swept height => its new height (the cell it chains to, 0 = none)
    region::Dict{Int, Int}                                      # a garbage cell that gets a filler => the cell the filler names
    stray::Vector{Any}                                          # referrers whose cell the mark phase left unmarked (must stay empty)
    garb::Vector{Int}                                           # slots that must become `garbage_collected`
    bad::Vector{String}                                         # what the model itself found out of order
    needs::Int
    marks::Int
    alien::Int
    cells::Int
    easy::Int
    scan::Int
    wrote::Int
    fstop::Int
    _GSModel() = new(Dict{Int, Vector{Any}}(), Dict{Tuple{Bool, Int, Int}, Int}(), Dict{Int, Int}(), Any[], Int[], String[], 0, 0, 0, 0, 0, 0, 0, 0)
end

function _gs_add!(M::_GSModel, head::Int, desc)::Nothing
    push!(get!(M.order, head, Any[]), desc)
    M.cells += 1
    return nothing
end

"A height `h` held in a mark field: the highest reachable cell at or below it is the new height and the chain's head; the garbage between gets a filler."
function _gs_model_field!(M::_GSModel, reach::Set{Int}, isfli::Bool, i::Int, fld::Int, h::Int)::Nothing
    gm = 0
    if h < 1
        gm = 0
    elseif h in reach
        gm = h
        M.easy += 1
    else
        M.scan += 1
        q = h
        while q >= 1
            if q in reach
                gm = q
                for p in (gm + 1):h
                    M.region[p] = gm
                end
                M.wrote += 1
                break
            end
            if haskey(M.region, q)
                gm = M.region[q]
                M.fstop += 1
                break
            end
            q -= 1
        end
    end
    M.newh[(isfli, i, fld)] = gm
    if gm >= 1
        M.needs += 1
        M.alien += 1
        _gs_add!(M, gm, (:m, isfli, i, fld))
    end
    return nothing
end

"A slot at index `idx`: a referrer when marked and a global reference but no value-table word; `env` slots left unmarked become `garbage_collected`."
function _gs_model_slot!(M::_GSModel, ld, reach::Set{Int}, idx::Int, env::Bool)::Nothing
    w = ld.slots[idx]
    v = w & LK.VALUE_MASK
    if LK.is_marked(w)
        if _gs_is_global(v) && !LK._is_vword(v)
            h = Int(v >> LK.LMASK_BITS)
            h in reach || push!(M.stray, (:s, idx))
            _gs_add!(M, h, (:s, idx))
        end
    elseif env
        _gs_is_global(v) && push!(M.garb, idx)
    else
        push!(M.bad, "foreign slot $(idx) is not marked after the mark phase")
    end
    return nothing
end

"The model of `sweep_foreign`, `sweep_trail` and (when `stacks` is given) `sweep_stacks`, from the state after the mark phase and the trail tagging."
function _gs_model(ld, reach::Set{Int}; stacks = nothing)::_GSModel
    M = _GSModel()
    fr = ld.fli_context                                         # sweep_foreign: innermost frame first
    while fr != 0
        f = ld.fliframes[fr]
        if LK.isRealMark(f.mark)
            M.marks += 1
            _gs_model_field!(M, reach, true, fr, 0, f.mark.globaltop)
            _gs_model_field!(M, reach, true, fr, 1, min(f.mark.saved_bar, ld.gTop))
        end
        for k in 0:(f.size - 1)
            _gs_model_slot!(M, ld, reach, LK.refFliP(f.base, k) + 1, false)
        end
        fr = f.parent
    end
    for i in length(ld.trail):-1:1                              # sweep_trail: newest entry first
        w = ld.trail[i]
        w == 0 && continue
        if (w & LK.TAG_TRAILMASK) == LK.TAG_TRAILVAL || (w & LK.STG_MASK) == LK.STG_GLOBAL
            M.needs += 1
            h = Int((w & LK.VALUE_MASK) >> LK.LMASK_BITS)
            h in reach || push!(M.stray, (:t, i))
            _gs_add!(M, h, (:t, i))
        end
    end
    stacks === nothing || stacks(M)
    return M
end

"The chains of the stacks as read back, against the model; ONE extractor for the rows and the corruption rows. `reversed = false` compares against the WRONG order."
function _gs_problems(ld, sn, M::_GSModel; reversed::Bool = true)::Vector{String}
    bad = String[]
    for h in sort!(collect(keys(M.order)))
        ord = M.order[h]
        want = reversed ? reverse(ord) : ord
        ch = _gs_chain(ld, h)
        ch == want || push!(bad, "chain of cell $(h): $(ch), expected $(want)")
        LK.is_first(ld.gstack[h]) || push!(bad, "the head $(h) lost its FIRST bit")
        oldest = _gs_word(ld, first(ord))
        (oldest & LK.VALUE_MASK) == (sn.g[h] & LK.VALUE_MASK) || push!(bad, "the oldest referrer of $(h) does not hold the head's value")
    end
    nfirst = count(p -> LK.is_first(ld.gstack[p]), 1:(ld.gTop))
    nfirst == length(M.order) || push!(bad, "$(nfirst) FIRST bits on the global stack, $(length(M.order)) heads")
    return bad
end

"The counters of the sweep against the model."
function _gs_counter_problems(st, sw, M::_GSModel, n0::Int)::Vector{String}
    bad = String[]
    sw.relocation_chains == length(M.order) || push!(bad, "relocation_chains $(sw.relocation_chains) != $(length(M.order))")
    sw.relocation_cells == M.cells || push!(bad, "relocation_cells $(sw.relocation_cells) != $(M.cells)")
    sw.alien_relocations == M.alien || push!(bad, "alien_relocations $(sw.alien_relocations) != $(M.alien)")
    sw.marks_swept == M.marks || push!(bad, "marks_swept $(sw.marks_swept) != $(M.marks)")
    st.needs_relocation - n0 == M.needs || push!(bad, "needs_relocation grew by $(st.needs_relocation - n0) != $(M.needs)")
    return bad
end

"The tag of the word a referrer held before the sweep."
function _gs_orig_tag(sn, d)::UInt64
    d[1] === :s && return LK.tag(sn.s[d[2]])
    d[1] === :t && return LK.tag(sn.tr[d[2]])
    return UInt64(0)                                            # a mark field: tag 0
end

# ---- the heap ----
"""
A heap with a garbage gap, an easy and a scanned mark, trailed bindings and a kept assignment; returns the engine and its handles.
The foreign frames F0 (the engine's), F1 (inside the gap), F2 (top of the gap), F3 (the top cell is marked), F4 (garbage above it).
"""
function _gs_heap()
    X = _rv(1)
    ld, t, n0 = _gs_engine(
        _R[
            _rf("f", _rs("a"), X, _rf("g", X, _rg(Int64(3))), _rg(1234.5678)),
            _rf("h", _rg("gs-string"), _rints(1:5), X),
            _rg(2.5),                                           # slot t + 3 holds a value-table word (ruling D1)
        ]
    )
    f0 = ld.fli_context
    c1 = LK.allocGlobalCells!(ld, 1)                            # older than every mark below
    c2 = LK.allocGlobalCells!(ld, 1)
    cv = LK.allocGlobalCells!(ld, 1)
    tr = LK.PL_new_term_refs(ld, 3)
    ld.slots[tr + 1] = LK.makeRefG(c1)
    ld.slots[tr + 2] = LK.makeRefG(cv)
    LK.putSlotValue!(ld, tr + 3, _rf("old", _rg(Int64(1)), _rf("older", _rg(Int64(2)))), LK.PutVarMap())
    ld.gstack[cv] = ld.slots[tr + 3] & LK.VALUE_MASK            # the cell holds the old value
    ld.slots[tr + 3] = _gs_atom(ld, "x")                        # the direct root dropped
    td = LK.PL_new_term_ref(ld)                                 # a dead term: the garbage gap
    LK.putSlotValue!(ld, td + 1, _rf("dead", _rg(Int64(1)), _rf("dead2", _rg(Int64(2)), _rints(1:4))), LK.PutVarMap())
    ld.slots[td + 1] = _gs_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f1 = ld.fli_context                                         # F1: its height lies inside the gap
    td2 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, td2 + 1, _rf("dead3", _rg(Int64(3)), _rints(1:6)), LK.PutVarMap())
    ld.slots[td2 + 1] = _gs_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f2 = ld.fli_context                                         # F2: the top of the gap
    LK._bind_const!(ld, c1, _gs_atom(ld, "one"))                # older than the bar: a trail entry each
    LK._bind_const!(ld, c2, _gs_atom(ld, "two"))
    LK.TrailAssignment!(ld, cv)                                 # the old value saved above, the pair on the trail
    ld.gstack[cv] = _gs_atom(ld, "y")
    tp = LK.PL_new_term_ref(ld)                                 # its variable cell is garbage...
    p = LK.allocGlobalCells!(ld, 1)                             # ...then the cell that is the top
    ld.slots[tp + 1] = LK.makeRefG(p)
    LK.PL_open_foreign_frame(ld)
    f3 = ld.fli_context                                         # F3: its top cell p is marked (the easy case)
    td3 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, td3 + 1, _rf("dead4", _rg(Int64(4)), _rints(1:7)), LK.PutVarMap())
    ld.slots[td3 + 1] = _gs_atom(ld, "gone")
    LK.PL_open_foreign_frame(ld)
    f4 = ld.fli_context                                         # F4: garbage above p again
    return (ld = ld, t = t, n0 = n0, f0 = f0, f1 = f1, f2 = f2, f3 = f3, f4 = f4, c1 = c1, c2 = c2, cv = cv, p = p)
end

"""
The heap marked, its trail tagged, the deliberate bars set, the model taken, then `sweep_foreign`, `sweep_trail`, `sweep_stacks` in upstream's order.
Returns the handles plus `st`, `sw`, `sn` (the stacks just before the sweep), `M`, `n0` (needs_relocation before the sweep) and `reach`.
"""
function _gs_run()
    H = _gs_heap()
    ld = H.ld
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    roots = _gs_fli_roots(ld)
    for e in ld.trail                                           # the roots as the test lists them: frames + the saved values of the kept assignments
        e != 0 && LK.isTrailVal(e) && push!(roots, LK.makeRefG(LK.trailValP(e)))
    end
    reach = _gs_reach(ld, roots)
    marks_agree = _gs_marked(ld) == reach
    early_reset = any(==(UInt64(0)), ld.trail) && any(!=(UInt64(0)), ld.trail)
    _gs_tag_trail!(ld)
    m4 = ld.fliframes[H.f4].mark                                # the saved bar above every cell: the clamp row
    ld.fliframes[H.f4].mark = LK.mark(m4.trailtop, m4.globaltop, LK.NO_MARK_BAR)
    m3 = ld.fliframes[H.f3].mark                                # a low saved bar, inside the gap
    ld.fliframes[H.f3].mark = LK.mark(m3.trailtop, m3.globaltop, ld.fliframes[H.f1].mark.globaltop)
    m0 = ld.fliframes[H.f0].mark                                # a height of 0: no cell below it, no chain
    ld.fliframes[H.f0].mark = LK.mark(m0.trailtop, m0.globaltop, 0)
    sn = _gs_snapshot(ld)
    M = _gs_model(ld, reach)
    sw = LK.gc_sweep_counts()
    n0 = st.needs_relocation
    LK.sweep_foreign(ld, st, sw)
    LK.sweep_trail(ld, st, sw)
    LK.sweep_stacks(ld, st, sw, LK.vm_state())
    return merge(H, (st = st, sw = sw, sn = sn, M = M, n0 = n0, reach = reach, marks_agree = marks_agree, early_reset = early_reset))
end

"An engine with a few terms, for the reference tables (a value-table word among them)."
function _gs_heap_pair()
    return _gs_engine(
        _R[_rf("k", _rs("a"), _rg(1.5), _rf("m", _rg(Int64(2)), _rv(1))), _rg("gs-box-2"), _rints(1:4)]
    )
end

@testset "the chains equal the model, the counters agree, and the sweep consumed every mark" begin
    R = _gs_run()
    ld, M, sn = R.ld, R.M, R.sn
    @test R.marks_agree                                         # the model's roots reproduce the marks
    @test R.early_reset                                         # early reset zeroed c2's entry and kept others
    @test !isempty(M.order)                                     # not vacuous: both sides non-empty through one extractor
    @test M.cells >= 12
    @test M.easy >= 1 && M.scan >= 3
    @test M.alien >= 4
    @test isempty(M.stray) && isempty(M.bad)
    tags = Set(_gs_orig_tag(sn, d) for h in keys(M.order) for d in M.order[h])
    @test length(tags) >= 3                                     # reference, compound/trail value/address: several tags
    @test _gs_problems(ld, sn, M) == String[]
    @test _gs_counter_problems(R.st, R.sw, M, R.n0) == String[]
    @test R.st.local_marked == 0
    @test !any(LK.is_marked, view(ld.slots, 1:(ld.lTop)))       # no slot keeps its MARK bit
    vslot = R.t + 3                                             # the value-table word: marked, never chained
    @test LK._is_vword(sn.s[vslot] & LK.VALUE_MASK)
    @test (ld.slots[vslot] & LK.VALUE_MASK) == (sn.s[vslot] & LK.VALUE_MASK)
    @test all(h -> !((:s, vslot) in M.order[h]), keys(M.order))
    @test length(ld.vtable) - R.n0 >= 3
    @test all(i -> !LK.is_first(ld.gstack[ld.vbox[i]]), (R.n0 + 1):length(ld.vtable))   # a box cell has no chain
    @test M.newh[(true, R.f0, 1)] == 0                          # a height of 0 stays 0
    @test ld.fliframes[R.f0].mark.saved_bar == 0
    @test M.newh[(true, R.f3, 0)] == R.p                        # the easy case: the top cell itself is the head
end

@testset "fillers: the garbage between a mark and the cell below is named for the next scan" begin
    R = _gs_run()
    ld, M, sn = R.ld, R.M, R.sn
    @test !isempty(M.region)
    @test M.wrote >= 1 && M.fstop >= 1                          # a scan that wrote fillers, a scan that stopped on one
    bad = Int[p for (p, gm) in M.region if ld.gstack[p] != LK.consTagged(gm, LK.TAGEX_VAR)]
    @test bad == Int[]
    heads = Set(keys(M.order))
    untouched = Int[p for p in 1:(ld.gTop) if !haskey(M.region, p) && !(p in heads) && ld.gstack[p] != sn.g[p]]
    @test untouched == Int[]                                    # no other cell was written
    @test count(p -> !haskey(M.region, p) && !(p in heads), 1:(ld.gTop)) > 10
    @test all(gm -> gm in R.reach, values(M.region))            # a filler names a live cell
    @test M.newh[(true, R.f4, 1)] == M.newh[(true, R.f4, 0)]    # the clamped saved bar reaches the same cell as the top
    @test M.newh[(true, R.f4, 0)] >= R.p
end

@testset "unwinding with the identity destination restores every word" begin
    R = _gs_run()
    ld, M, sn, sw = R.ld, R.M, R.sn, R.sw
    heads = sort!(collect(keys(M.order)))
    @test !isempty(heads)
    for h in heads
        LK.update_relocation_chain(ld, sw, h, h)
    end
    @test sw.relocation_chains == 0
    @test sw.relocated_cells == sw.relocation_cells > 0
    LK.gc_clear_marks!(ld)
    badg = Int[]
    for p in 1:(ld.gTop)
        want = haskey(M.region, p) ? LK.consTagged(M.region[p], LK.TAGEX_VAR) : (sn.g[p] & LK.VALUE_MASK)
        ld.gstack[p] == want || push!(badg, p)
    end
    @test badg == Int[]
    @test (ld.slots .& LK.VALUE_MASK) == (sn.s .& LK.VALUE_MASK)
    @test ld.trail == sn.tr
    badm = Any[]
    for ((isfli, i, fld), gm) in M.newh
        want = gm == 0 ? UInt64(0) : (UInt64(gm) << LK.LMASK_BITS) | LK.STG_GLOBAL
        _gs_word(ld, (:m, isfli, i, fld)) == want || push!(badm, (isfli, i, fld))
    end
    @test badm == Any[]
    @test !isempty(M.newh) && count(v -> v != 0, values(M.newh)) >= 4
end

@testset "unwinding to a new position: every referrer holds it and keeps its tag" begin
    R = _gs_run()
    ld, M, sn, sw = R.ld, R.M, R.sn, R.sw
    heads = sort!(collect(keys(M.order)))
    for h in heads
        LK.update_relocation_chain(ld, sw, h, h + 1000)
    end
    @test sw.relocation_chains == 0
    bad = Any[]
    checked = 0
    for h in heads, d in M.order[h]
        checked += 1
        want = LK.consPtr(h + 1000, _gs_orig_tag(sn, d) | LK.STG_GLOBAL)
        (_gs_word(ld, d) & LK.VALUE_MASK) == want || push!(bad, d)
    end
    @test bad == Any[]
    @test checked == M.cells > 0
    badh = Int[h for h in heads if (ld.gstack[h] & LK.VALUE_MASK) != (sn.g[h] & LK.VALUE_MASK)]
    @test badh == Int[]                                         # the heads got their own value back
    @test !any(h -> LK.is_first(ld.gstack[h]), heads)
end

@testset "the trail height of a mark: the chain starts at the entry after the last one" begin
    ld, t, n0 = _gs_engine(_R[_rs("a")])
    fr = ld.fli_context
    c = length(ld.trail)
    push!(ld.trail, UInt64(0))                                  # the zero sentinel the trail compaction pushes
    m = ld.fliframes[fr].mark
    ld.fliframes[fr].mark = LK.mark(c, m.globaltop, m.saved_bar)
    sw = LK.gc_sweep_counts()
    LK.alien_into_relocation_chain(ld, sw, LK._gcs_mfield(true, fr, 2), LK.STG_STATIC)
    @test LK.is_first(ld.trail[c + 1])                          # the head is the entry c + 1
    @test _gs_chain_word(ld, ld.trail[c + 1]) == Any[(:m, true, fr, 2)]
    @test sw.alien_relocations == 1 && sw.relocation_chains == 1 && sw.relocation_cells == 1
    LK.update_relocation_chain(ld, sw, LK.GC_TRAIL_BASE + c + 1, LK.GC_TRAIL_BASE + 3)
    @test reinterpret(UInt64, ld.fliframes[fr].mark.trailtop) == LK.consPtr(3, LK.STG_STATIC)
    @test ld.trail[c + 1] == 0                                  # the sentinel is itself again
    @test sw.relocation_chains == 0
end

@testset "unit table: makePtr round trip, offset_word, make_gc_hole, gc_box_index, is_downward_ref / is_upward_ref" begin
    cases = Tuple{Int, UInt64}[
        (5, LK.STG_GLOBAL),
        (LK.GC_TRAIL_BASE + 7, LK.STG_STATIC),
        (-9, LK.STG_LOCAL),
        (LK._gcs_mfield(true, 3, 2), LK.STG_LOCAL),
        (LK._gcs_mfield(false, 2, 1), LK.STG_LOCAL),
    ]
    for (a, stg) in cases
        w = LK.makePtr(a, LK.TAG_COMPOUND)
        @test LK._gcs_unptr(w) == a
        @test LK.storage(w) == stg
        @test LK.tag(w) == LK.TAG_COMPOUND
    end
    @test length(cases) == 5
    @test LK.offset_word(UInt64(0)) == 0 && LK.offset_word(LK.consPtr(77, LK.TAG_COMPOUND | LK.STG_GLOBAL)) == 0

    ld, t, n0 = _gs_engine(_R[_rs("a"), _rg(2.5), _rg("gs-box")])
    base = LK.allocGlobalCells!(ld, 12)
    function fill_cells!()
        for p in base:(base + 11)
            ld.gstack[p] = _gs_atom(ld, "w")
        end
        return nothing
    end
    fill_cells!()
    @test LK.make_gc_hole(ld, base, base + 9) == base           # top - bottom = 9: a hole, bottom..top inclusive
    @test all(p -> ld.gstack[p] == 0, base:(base + 9))
    @test all(p -> ld.gstack[p] == _gs_atom(ld, "w"), (base + 10):(base + 11))
    fill_cells!()
    @test LK.make_gc_hole(ld, base, base + 4) == base           # top - bottom = 4: not a hole
    @test all(p -> ld.gstack[p] == _gs_atom(ld, "w"), base:(base + 11))
    @test LK.make_gc_hole(ld, base, base + 5) == base           # top - bottom = 5: a hole
    @test all(p -> ld.gstack[p] == 0, base:(base + 5))
    @test ld.gstack[base + 6] == _gs_atom(ld, "w")

    @test LK.gc_box_index(ld, ld.vbox[n0 + 1]) != 0             # a box cell
    @test LK.gc_box_index(ld, base + 6) == 0                    # a plain cell
    ld2, t2, n02 = _gs_heap_pair()
    q = LK.allocGlobalCells!(ld2, 3)
    ld2.gstack[q] = LK.makeRefG(q + 2)                          # up
    ld2.gstack[q + 1] = LK.makeRefG(q)                          # down
    ld2.gstack[q + 2] = _gs_atom(ld2, "z")                      # neither
    ups = Int[]
    downs = Int[]
    for p in 1:(ld2.gTop)
        w = ld2.gstack[p] & LK.VALUE_MASK
        ref = (_gs_is_global(w) && !LK._is_vword(w)) ? Int(w >> LK.LMASK_BITS) : 0
        ref > p && push!(ups, p)
        (0 < ref < p) && push!(downs, p)
    end
    @test !isempty(ups) && !isempty(downs)
    @test q in ups && (q + 1) in downs && !(q + 2 in ups) && !(q + 2 in downs)
    @test Int[p for p in 1:(ld2.gTop) if LK.is_upward_ref(ld2, p)] == ups
    @test Int[p for p in 1:(ld2.gTop) if LK.is_downward_ref(ld2, p)] == downs
    boxes = Int[ld2.vbox[i] for i in (n02 + 1):length(ld2.vtable)]
    @test !isempty(boxes)
    @test all(p -> LK._is_vword(ld2.gstack[p]) && !LK.is_upward_ref(ld2, p) && !LK.is_downward_ref(ld2, p), boxes)
end

@testset "a live query: the environments and choicepoints are swept, an unmarked slot becomes garbage_collected" begin
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
        (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    ]
    db = _rdb(clauses)
    ld = db.ld
    ran = Ref(0)
    ans = _rcall(
        db, _rf("n", _rv(90));
        at = (qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            sn0 = _gs_snapshot(ld)
            cl = 0
            ch = ld.BFR
            saved_c = Tuple{Int, LK.mark}[]
            while ch != 0
                c = ld.choices[ch]
                (c.type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
                push!(saved_c, (ch, c.mark))
                ch = c.parent
            end
            saved_f = Tuple{Int, LK.mark}[]
            fl = ld.fli_context
            while fl != 0
                push!(saved_f, (fl, ld.fliframes[fl].mark))
                fl = ld.fliframes[fl].parent
            end
            @test cl != 0
            fi = ld.choices[cl].frame
            @test fi != 0 && ld.frames[fi].parent == 0
            qf = LK.queryOfFrame(ld, fi)
            @test ld.queries[qf].parent == 0
            vm = LK.vm_state()
            vm.frame = fi
            vm.choice = ld.BFR
            vm.pc_start_vmi = 0
            frames = Int[]
            ch = ld.BFR
            while ch != 0
                c = ld.choices[ch]
                c.frame != 0 && c.type == LK.CHP_CLAUSE && push!(frames, c.frame)
                ch = c.parent
            end
            se = ld.queries[qf].saved_environment
            se != 0 && push!(frames, se)
            roots = _gs_fli_roots(ld)
            for f in unique(vcat(fi, frames))
                append!(roots, _gs_frame_args(ld, f))
            end
            st = LK.gc_mark_counts()
            LK.mark_phase(ld, st, vm)
            for e in ld.trail
                e != 0 && LK.isTrailVal(e) && push!(roots, LK.makeRefG(LK.trailValP(e)))
            end
            reach = _gs_reach(ld, roots)
            @test length(reach) >= 8
            @test _gs_marked(ld) == reach
            _gs_tag_trail!(ld)
            sn = _gs_snapshot(ld)
            done = Set{Int}()
            function env!(M, f)
                (f != 0 && (ld.frames[f].flags & LK.FR_MARKED) != 0 && !(f in done)) || return nothing
                push!(done, f)
                ld.frames[f].parent == 0 || push!(M.bad, "frame $(f) has a parent")
                base = LK.argFrameP(ld.frames[f].base, 0)
                for i in 0:(ld.frames[f].predicate.arity - 1)
                    _gs_model_slot!(M, ld, reach, base + i + 1, true)
                end
                return nothing
            end
            function stacks!(M)
                env!(M, fi)
                c2 = ld.BFR
                while c2 != 0
                    c = ld.choices[c2]
                    c.type == LK.CHP_JUMP && push!(M.bad, "a CHP_JUMP choicepoint: its pc is not modelled")
                    env!(M, c.frame)
                    M.marks += 1
                    _gs_model_field!(M, reach, false, c2, 0, c.mark.globaltop)
                    _gs_model_field!(M, reach, false, c2, 1, min(c.mark.saved_bar, ld.gTop))
                    c2 = c.parent
                end
                return nothing
            end
            M = _gs_model(ld, reach; stacks = stacks!)
            sw = LK.gc_sweep_counts()
            n0 = st.needs_relocation
            LK.sweep_foreign(ld, st, sw)
            LK.sweep_trail(ld, st, sw)
            LK.sweep_stacks(ld, st, sw, vm)
            @test !isempty(M.order) && M.cells >= 1
            @test isempty(M.bad) && isempty(M.stray)
            @test _gs_problems(ld, sn, M) == String[]
            @test _gs_counter_problems(st, sw, M, n0) == String[]
            @test st.local_marked == 0
            @test all(i -> (ld.frames[i].flags & LK.FR_MARKED) == 0, 1:(ld.nframes))
            gc_atom = _gs_atom(ld, "garbage_collected")
            @test all(idx -> (ld.slots[idx] & LK.VALUE_MASK) == gc_atom, M.garb)
            # restore, then sweep_frame with NOTHING marked: every global-reference argument becomes garbage_collected
            _gs_restore!(ld, sn0)
            for (i, m) in saved_c
                ld.choices[i].mark = m
            end
            for (i, m) in saved_f
                ld.fliframes[i].mark = m
            end
            args = _gs_frame_args(ld, fi)
            want = UInt64[_gs_is_global(w) ? gc_atom : w for w in args]
            @test !isempty(want) && any(_gs_is_global, args)
            st3 = LK.gc_mark_counts()
            sw3 = LK.gc_sweep_counts()
            LK.sweep_frame(ld, st3, sw3, fi, ld.frames[fi].predicate.arity)
            @test _gs_frame_args(ld, fi) == want
            @test sw3.relocation_cells == 0
            _gs_restore!(ld, sn0)
        end
    )
    @test length(ans) == 3 && ran[] == 1                        # the query was not disturbed
end

@testset "deliberate corruptions of a chain FAIL the comparison" begin
    R = _gs_run()
    ld, M, sn = R.ld, R.M, R.sn
    @test _gs_problems(ld, sn, M) == String[]                   # the guard CAN pass...
    heads = sort!(collect(keys(M.order)))
    @test !isempty(heads)
    h1 = first(heads)
    w1 = ld.gstack[h1]
    ld.gstack[h1] = LK.clear_first(w1)                          # ...a head loses its FIRST bit
    @test !isempty(_gs_problems(ld, sn, M))                     # ...and CAN fail
    ld.gstack[h1] = w1
    @test _gs_problems(ld, sn, M) == String[]
    multi = Int[h for h in heads if length(M.order[h]) >= 2]
    @test !isempty(multi)                                       # a head with two referrers exists: not vacuous
    h2 = first(multi)
    newest = last(M.order[h2])
    w2 = _gs_word(ld, newest)
    @test LK.is_first(w2)                                       # the newest of >= 2 continues the chain
    _gs_setword!(ld, newest, LK.clear_first(w2))                # the chain is cut after its newest referrer
    bad = _gs_problems(ld, sn, M)
    @test !isempty(bad)
    @test any(s -> occursin("chain of cell $(h2)", s), bad)
    _gs_setword!(ld, newest, w2)
    @test _gs_problems(ld, sn, M) == String[]
    @test !isempty(_gs_problems(ld, sn, M; reversed = false))   # the unreversed order is wrong
end
