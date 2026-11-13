# ORIGINAL: white-box tests of the stack collector's MARK PHASE (G1-GC G1-3: src/pl-gcmark.jl, src/pl-gcwalk.jl; upstream's
# pl-gc.c `mark_phase`, which only marks: it moves and frees nothing); swipl observes these bits only through its own collector (the marks are internal bits).
# test/core_lang/test_gc_mark.jl — `mark_phase` on live engines, each result compared with an INDEPENDENT reachability walk:
#   * the walk (`_gm_reach`) is plain Julia over the heap words — tags only, no mark bit, no kernel marking code — from roots the
#     test lists itself (`_gm_fli_roots`: the term references of every foreign frame; the frame arguments of the choicepoints; the
#     argument stack; the global variables; the attributed-variable chain; the trailed old values of the kept assignments);
#     the set of cells whose MARK bit is set after the phase must be EQUAL to it, both sets non-empty, and `total_marked` equals both;
#   * dead cells (a term whose only root was dropped) are NOT marked; a float, string or bigint marks its BOX cell only (ruling D1);
#   * the pointer reversal leaves every word as it was (the value bits), `gc_clear_marks!` removes the bits, `unmark_stacks` the
#     frame flags; early reset resets an unreachable trailed cell and keeps the marked ones, a kept assignment marks its old value;
#   * deliberate corruptions MUST FAIL the comparison (a cleared live mark, a stray mark, a root class left out).
# No row consults swipl (nothing here is observable through it), so no testset can run without an assertion.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_gm_atom(ld, n) = LK._atom_word!(ld, _rs(n))

"An engine with the values of `vs` (at least one) put into term references of an open foreign frame: `(ld, t, n0)` — `t` the first reference, `n0` the size of the value table before."
function _gm_engine(vs::Vector{_R})
    @assert !isempty(vs)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    n0 = length(ld.vtable)
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)                 # the i-th value: slot t + i
    end
    return ld, t, n0
end

"The words (no gc bits) of the term references of every foreign frame, innermost first."
function _gm_fli_roots(ld)::Vector{UInt64}
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
function _gm_reach(ld, roots::Vector{UInt64})::Set{Int}
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
_gm_is_global(w::UInt64)::Bool =
    (LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL) || LK.isAttVar(w) || LK._is_gcompound(w) || LK._is_vword(w)

"The positions of the global cells whose MARK bit is set."
_gm_marked(ld)::Set{Int} = Set{Int}(p for p in 1:(ld.gTop) if LK.is_marked(ld.gstack[p]))

"The mark bits agree with the reachability walk from `roots`."
_gm_agree(ld, roots::Vector{UInt64})::Bool = _gm_reach(ld, roots) == _gm_marked(ld)

"The stacks as they are: global cells, slots and the trail."
_gm_snapshot(ld) = (g=copy(ld.gstack), s=copy(ld.slots), tr=copy(ld.trail))

"Put the stacks back as `sn` took them (the trail keeps its length: the caller undid what grew it)."
function _gm_restore!(ld, sn)
    length(ld.trail) == length(sn.tr) || error("_gm_restore!: the trail length changed")
    copyto!(ld.gstack, sn.g)
    copyto!(ld.slots, sn.s)
    copyto!(ld.trail, sn.tr)
    return nothing
end

"The words the frame at index `fi` holds in its argument slots (no gc bits)."
function _gm_frame_args(ld, fi::Int)::Vector{UInt64}
    f = ld.frames[fi]
    return UInt64[ld.slots[LK.argFrameP(f.base, n) + 1] & LK.VALUE_MASK for n in 0:(f.predicate.arity - 1)]
end

"A heap with compounds, a shared variable, a nested compound, two floats and a string (the checker's heap)."
function _gm_heap()
    X = _rv(1)
    return _gm_engine(
        _R[
            _rf("f", _rs("a"), X, _rf("g", X, _rg(Int64(3))), _rg(1234.5678), _rg(8765.4321)),
            _rf("h", _rg("gm-string-A"), _rints(1:5), X),
        ]
    )
end

@testset "term references: exactly the reachable cells are marked, and nothing else moves" begin
    ld, t, n0 = _gm_heap()
    @test ld.gTop >= 20                                         # a non-trivial heap: not vacuous
    @test length(ld.vtable) - n0 >= 3                           # two floats and a string: value-table boxes
    roots = _gm_fli_roots(ld)
    model = _gm_reach(ld, roots)
    @test length(model) >= 15
    @test !isempty(roots)
    sn = _gm_snapshot(ld)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test !isempty(marked)
    @test marked == model                                       # the marks ARE the reachable cells
    @test st.total_marked == length(model) == length(marked)
    @test st.local_marked > 0                                   # the term-reference slots were marked as starts
    @test all(i -> ld.vbox[i] in marked, (n0 + 1):length(ld.vtable))    # D1: every box of this heap
    @test !any(LK.is_first, view(ld.gstack, 1:(ld.gTop)))       # the pointer reversal left no FIRST bit
    @test (ld.gstack .& LK.VALUE_MASK) == (sn.g .& LK.VALUE_MASK)   # ...and put every word back
    @test (ld.slots .& LK.VALUE_MASK) == (sn.s .& LK.VALUE_MASK)
    @test ld.gstack != sn.g                                     # the bits differ: the phase did something
    LK.gc_clear_marks!(ld)
    @test ld.gstack == sn.g && ld.slots == sn.s                 # bit for bit as before
    @test isempty(_gm_marked(ld))
    st2 = LK.gc_mark_counts()                                   # a second run gives the same marks
    LK.mark_phase(ld, st2, LK.vm_state())
    @test _gm_marked(ld) == model && st2.total_marked == st.total_marked
end

@testset "dead cells stay unmarked; a shared and a cyclic term are marked once" begin
    X = _rv(1)
    ld, t, n0 = _gm_engine(_R[_rf("live", X, _rf("k", X, _rs("a")))])
    g0 = ld.gTop
    pvm = LK.PutVarMap()
    t2 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, t2 + 1, _rf("dead", _rg(Int64(1)), _rf("dead2", _rg(Int64(2)), _rints(1:4))), pvm)
    g1 = ld.gTop
    ld.slots[t2 + 1] = _gm_atom(ld, "gone")                     # the only root of the dead term dropped
    dead_cells = (g0 + 1):g1
    @test length(dead_cells) >= 8
    roots = _gm_fli_roots(ld)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test _gm_agree(ld, roots)
    @test !isempty(marked) && st.total_marked == length(marked)
    @test all(p -> !(p in marked), dead_cells)                  # every cell the dropped term (and its reference cell) occupies
    @test count(p -> LK.isFunctor(ld.gstack[p]), dead_cells) >= 2
    @test all(p -> LK.isFunctor(ld.gstack[p]) ? !(p in marked) : true, dead_cells)
    # a cyclic term: the argument of f(_) bound to f itself
    ldc, tc, _ = _gm_engine(_R[_rf("cyc", _rv(1), _rs("z"))])
    fcell = LK.valPtr(ldc.slots[tc + 1] & LK.VALUE_MASK)        # the compound word of the first reference: its functor cell
    if LK._is_gcompound(ldc.slots[tc + 1] & LK.VALUE_MASK)
        ldc.gstack[fcell + 1] = ldc.slots[tc + 1] & LK.VALUE_MASK   # arg 1 := the term itself
    else                                                        # (a reference to a cell holding it)
        q = LK.unRef(ldc.slots[tc + 1] & LK.VALUE_MASK)
        fcell = LK.valPtr(ldc.gstack[q])
        ldc.gstack[fcell + 1] = ldc.gstack[q]
    end
    rootsc = _gm_fli_roots(ldc)
    modelc = _gm_reach(ldc, rootsc)
    @test length(modelc) >= 3
    stc = LK.gc_mark_counts()
    LK.mark_phase(ldc, stc, LK.vm_state())                      # must terminate
    @test _gm_marked(ldc) == modelc
    @test stc.total_marked == length(modelc)
end

@testset "an indirect value marks its box cell only (ruling D1)" begin
    ld, t, n0 = _gm_engine(_R[_rg(1234.5678), _rg(8765.4321), _rg("gm-string-B")])
    boxes = Set(ld.vbox[(n0 + 1):length(ld.vtable)])
    @test length(boxes) == 3
    ld.slots[t + 2] = _gm_atom(ld, "dropped")                   # keep the first float and the string; drop the second float
    roots = _gm_fli_roots(ld)
    model = _gm_reach(ld, roots)
    @test !isempty(model)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test marked == model
    @test length(intersect(boxes, marked)) == 2                 # two boxes marked, the dropped float's not
    @test st.total_marked == length(marked)
    @test length(setdiff(boxes, marked)) == 1                   # the dropped float's box stays unmarked
end

@testset "attributed variables: the attvar cell and its attributes; the chain only under call_residue_vars" begin
    ld, t, n0 = _gm_engine(_R[_rs("a")])
    p = LK.allocGlobalCells!(ld, 1)                             # newer than the frame's bar: bound without a trail entry
    LK.make_new_attvar(ld, p)
    @test LK.isRef(ld.gstack[p])
    A = LK.unRef(ld.gstack[p])
    @test LK.isAttVar(ld.gstack[A])
    @test ld.attvar_attvars != 0 && ld.attvar_attvars == A - 1  # the chain's newest link cell lies just below the attvar cell
    t2 = LK.PL_new_term_ref(ld)
    ld.slots[t2 + 1] = LK.makeRefG(p)
    roots = _gm_fli_roots(ld)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test _gm_agree(ld, roots)
    @test p in marked && A in marked && (A + 1) in marked       # the variable cell, the attvar cell and its attribute value
    @test !((A - 1) in marked)                                  # the link cell is no root without call_residue_vars
    @test st.total_marked == length(marked)
    LK.gc_clear_marks!(ld)
    # under call_residue_vars/3 the chain is protected: link_attvars makes the attvar cells term references
    ld.slots[t2 + 1] = _gm_atom(ld, "forget")
    ld.attvar_call_residue_vars_count = 1
    fid = LK.link_attvars(ld)
    @test fid != 0
    @test LK.count_need_protection_attvars(ld) == 1
    chain = UInt64[]
    cp = ld.attvar_attvars
    while cp != 0
        LK.isAttVar(ld.gstack[cp + 1]) && push!(chain, LK.makeRefG(cp + 1))
        cp = LK.isRef(ld.gstack[cp]) ? LK.unRef(ld.gstack[cp]) : 0
    end
    @test length(chain) == 1
    roots2 = _gm_fli_roots(ld)                                  # the link frame's term references are in the chain of frames
    @test chain[1] in roots2
    st2 = LK.gc_mark_counts()
    LK.mark_phase(ld, st2, LK.vm_state())
    marked2 = _gm_marked(ld)
    @test _gm_agree(ld, roots2)
    @test A in marked2 && (A + 1) in marked2
    @test !(p in marked2)                                       # nothing roots the variable cell any more
    LK.gc_clear_marks!(ld)
    LK.restore_attvars(ld, fid)
    ld.attvar_call_residue_vars_count = 0
    @test LK.link_attvars(ld) == 0                              # not under call_residue_vars: no frame
end

@testset "global variables (nb_setval) are roots; the saved frozen bar is restored" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    keep = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, keep + 1, _rf("keep", _rg(Int64(1))), LK.PutVarMap())
    fid0 = LK.PL_open_foreign_frame(ld)                         # a frame of its own for the assignment, closed again below
    tt = LK.PL_new_term_refs(ld, 2)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, tt + 1, _rs("gm_key"), pvm)
    LK.putSlotValue!(ld, tt + 2, _rf("val", _rg(Int64(5)), _rf("w", _rg(8.5), _rints(1:3))), pvm)
    @test LK.gvar_setval(ld, tt, tt + 1, UInt32(0))             # nb_setval(gm_key, val(...)): a COPY on the global stack
    LK.PL_close_foreign_frame(ld, fid0)                         # the source term and the copy's temporary references are dead now
    @test !isempty(ld.gvar_nb_vars)
    gvals = UInt64[w for w in values(ld.gvar_nb_vars) if _gm_is_global(w)]
    @test any(LK._is_gcompound, gvals)                          # our compound value: a global root
    fli_before = _gm_fli_roots(ld)
    roots = vcat(fli_before, gvals)                             # the roots as the test lists them: frames + the variables
    model = _gm_reach(ld, roots)
    model_fli_only = _gm_reach(ld, fli_before)
    @test length(model) > length(model_fli_only)                # the variable's copy adds cells: it is not vacuous
    bar0 = ld.frozen_bar
    fid, sb = LK.gvars_to_term_refs(ld)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test marked == model
    @test st.total_marked == length(model) == length(marked)
    @test all(w -> LK._is_gcompound(w) ? LK.valPtr(w) in marked : true, gvals)   # each copy's functor cell
    LK.gc_clear_marks!(ld)
    LK.term_refs_to_gvars(ld, fid, sb)
    @test ld.frozen_bar == bar0                                 # the saved bar is back
    @test UInt64[w for w in values(ld.gvar_nb_vars) if _gm_is_global(w)] == gvals    # no relocation yet: the same words
end

@testset "early reset: an unreachable trailed variable is reset and its entry deleted; a marked one is kept" begin
    ld, t, n0 = _gm_engine(_R[_rs("a")])
    c1 = LK.allocGlobalCells!(ld, 1)                            # older than the frame opened below
    c2 = LK.allocGlobalCells!(ld, 1)
    fid = LK.PL_open_foreign_frame(ld)                          # the mark: the bar at gTop
    tr0 = length(ld.trail)
    LK._bind_const!(ld, c1, _gm_atom(ld, "one"))                # older than the bar: a trail entry each
    LK._bind_const!(ld, c2, _gm_atom(ld, "two"))
    @test length(ld.trail) == tr0 + 2
    t2 = LK.PL_new_term_ref(ld)
    ld.slots[t2 + 1] = LK.makeRefG(c1)                          # c1 is reachable, c2 is not
    roots = _gm_fli_roots(ld)
    model = _gm_reach(ld, roots)
    @test c1 in model && !(c2 in model)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    @test _gm_marked(ld) == model
    @test ld.gstack[c2] == 0                                    # reset: setVar
    @test (ld.gstack[c1] & LK.VALUE_MASK) == _gm_atom(ld, "one")    # kept
    @test ld.trail[tr0 + 2] == 0                                # c2's entry deleted (zeroed: the compaction removes it)
    @test ld.trail[tr0 + 1] != 0 && LK._trail_pos(ld.trail[tr0 + 1]) == c1
    @test st.trailcells_deleted == 1
end

@testset "early reset: a kept assignment marks the old value it saved" begin
    ld, t, n0 = _gm_engine(_R[_rs("a"), _rs("b")])
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, _rf("old", _rg(Int64(1)), _rf("older", _rg(Int64(2)))), pvm)
    cv = LK.allocGlobalCells!(ld, 1)
    ld.gstack[cv] = ld.slots[t + 1] & LK.VALUE_MASK             # the cell holds the old value
    ld.slots[t + 1] = _gm_atom(ld, "x")                         # the direct root dropped
    ld.slots[t + 2] = LK.makeRefG(cv)                           # the cell itself is a root
    fid = LK.PL_open_foreign_frame(ld)                          # cv is older than this frame's bar
    tr0 = length(ld.trail)
    LK.TrailAssignment!(ld, cv)                                 # the old value saved in a new cell above, the pair on the trail
    @test length(ld.trail) == tr0 + 2 && LK.isTrailVal(ld.trail[tr0 + 2])
    gp = LK.trailValP(ld.trail[tr0 + 2])
    @test ld.gstack[gp] == ld.gstack[cv]                        # the saved copy
    ld.gstack[cv] = _gm_atom(ld, "y")                           # the assignment
    roots = _gm_fli_roots(ld)
    without = _gm_reach(ld, roots)
    with = _gm_reach(ld, vcat(roots, UInt64[LK.makeRefG(gp)]))  # the trail keeps the saved value alive
    @test length(with) > length(without) && cv in without && !(gp in without)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    marked = _gm_marked(ld)
    @test marked == with
    @test gp in marked && cv in marked
    @test ld.trail[tr0 + 1] != 0 && ld.trail[tr0 + 2] != 0      # the pair is kept
    @test st.trailcells_deleted == 0
    @test st.total_marked == length(with)
end

@testset "the argument stack and the choicepoints and frames of a live query are roots" begin
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
        at=(qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            sn = _gm_snapshot(ld)
            n_tr = length(ld.trail)
            # --- the choicepoint chain: a CHP_CLAUSE with a frame (the alternatives of n/1) ---
            cl = 0
            ch = ld.BFR
            while ch != 0
                c = ld.choices[ch]
                (c.type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
                ch = c.parent
            end
            @test cl != 0
            fi = ld.choices[cl].frame
            @test fi != 0 && ld.frames[fi].parent == 0          # the query's top frame of n/1
            vm = LK.vm_state()
            vm.frame = fi
            vm.choice = ld.BFR
            vm.pc_start_vmi = 0                                 # no VM resume point: the arguments of the frame are the roots
            frames = Int[]
            ch = ld.BFR
            while ch != 0
                c = ld.choices[ch]
                c.frame != 0 && c.type == LK.CHP_CLAUSE && push!(frames, c.frame)
                ch = c.parent
            end
            qf = LK.queryOfFrame(ld, fi)
            se = ld.queries[qf].saved_environment
            se != 0 && push!(frames, se)
            roots = _gm_fli_roots(ld)
            for f in unique(vcat(fi, frames))
                append!(roots, _gm_frame_args(ld, f))
            end
            model = _gm_reach(ld, roots)
            dead = setdiff(Set(1:(ld.gTop)), model)
            @test length(model) >= 8
            @test !isempty(dead)                                # cells nothing reaches exist (the unused answer cells)
            st = LK.gc_mark_counts()
            LK.mark_phase(ld, st, vm)
            marked = _gm_marked(ld)
            @test marked == model
            @test st.total_marked == length(model) == length(marked)
            @test isdisjoint(dead, marked)                      # dead cells are not marked
            @test (ld.frames[fi].flags & LK.FR_MARKED) != 0     # the walk flagged the frame
            @test all(p -> (ld.gstack[p] & LK.VALUE_MASK) == (sn.g[p] & LK.VALUE_MASK), model)   # the reversal put the live words back
            # unmark: the frame flags, then (until the sweep exists) the cell bits
            LK.unmark_stacks(ld, fi, ld.BFR, LK.FR_MARKED)
            @test all(i -> (ld.frames[i].flags & LK.FR_MARKED) == 0, 1:(ld.nframes))
            LK.gc_clear_marks!(ld)
            @test all(p -> (ld.gstack[p] & LK.GC_MASK) == 0, 1:(ld.gTop))
            @test all(p -> (ld.slots[p] & LK.GC_MASK) == 0, 1:(ld.lTop))
            _gm_restore!(ld, sn)                                # the query goes on from its own heap
            @test length(ld.trail) == n_tr
        end
    )
    @test length(ans) == 3 && ran[] == 1                        # the query was not disturbed
end

@testset "the argument stack's global entries are term references of the collection" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[(_rf("n", _rg(Int64(1))), nothing), (_rf("n", _rg(Int64(2))), nothing)])
    ld = db.ld
    ran = Ref(0)
    ans = _rcall(
        db, _rf("n", _rv(90));
        at=(qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            sn = _gm_snapshot(ld)
            a0 = ld.aTop
            fid = LK.PL_open_foreign_frame(ld)
            t = LK.PL_new_term_ref(ld)
            LK.putSlotValue!(ld, t + 1, _rf("keep", _rg(Int64(7)), _rf("deep", _rg(8.125))), LK.PutVarMap())
            c = LK.allocGlobalCells!(ld, 1)
            ld.gstack[c] = ld.slots[t + 1] & LK.VALUE_MASK
            ld.slots[t + 1] = _gm_atom(ld, "gone")              # only the argument stack reaches the term now
            LK.pushArgumentStack(
                ld, LK.argstack_entry{_R}(LK.argp_t{_R}(LK.ARGP_GLOBAL, c, ld.placeholder), false)
            )
            roots = _gm_fli_roots(ld)
            for i in 1:(ld.aTop)
                e = ld.astack[i]
                e.argp.form == LK.ARGP_GLOBAL && push!(roots, LK.makeRefG(e.argp.pos))
            end
            model = _gm_reach(ld, roots)
            without = _gm_reach(ld, _gm_fli_roots(ld))
            @test c in model && !(c in without)
            @test length(model) > length(without)
            vm = LK.vm_state()
            vm.save_argp = true
            fid2 = LK.argument_stack_to_term_refs(ld, vm)
            @test fid2 != 0
            st = LK.gc_mark_counts()
            LK.mark_phase(ld, st, LK.vm_state())
            marked = _gm_marked(ld)
            @test marked == model
            @test c in marked && st.total_marked == length(marked)
            LK.gc_clear_marks!(ld)
            LK.term_refs_to_argument_stack(ld, vm, fid2)
            @test ld.aTop == a0 + 1                             # the pushed entry only: the registers' one was popped
            @test ld.astack[ld.aTop].argp.pos == c && !ld.astack[ld.aTop].uwrite
            ld.aTop = a0
            _gm_restore!(ld, sn)
            LK.PL_discard_foreign_frame(ld, fid)
        end
    )
    @test length(ans) == 2 && ran[] == 1
end

@testset "mark_alt_clauses marks only the arguments the alternative clauses read" begin
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("m", _rs("a"), _rf("p", _rg(Int64(1)))), nothing),
        (_rf("m", _rs("b"), _rv(1)), nothing),                  # reads argument 1, ignores argument 2 (a void)
    ]
    db = _rdb(clauses)
    ld = db.ld
    ran = Ref(0)
    ans = _rcall(
        db, _rf("m", _rv(90), _rv(91));
        at=(qid, k) -> begin
            k == 1 || return nothing
            ran[] += 1
            sn = _gm_snapshot(ld)
            cl = 0
            ch = ld.BFR
            while ch != 0
                (ld.choices[ch].type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
                ch = ld.choices[ch].parent
            end
            @test cl != 0
            c = ld.choices[cl]
            fi = c.frame
            f = ld.frames[fi]
            @test f.predicate.arity == 2
            @test c.value_clause.cref !== nothing
            sp = LK.argFrameP(f.base, 0)
            w0 = ld.slots[sp + 1] & LK.VALUE_MASK
            w1 = ld.slots[sp + 2] & LK.VALUE_MASK
            @test !LK.is_marked(ld.slots[sp + 1]) && !LK.is_marked(ld.slots[sp + 2])
            st = LK.gc_mark_counts()
            LK.mark_alt_clauses(ld, st, fi, c.value_clause.cref)
            @test LK.is_marked(ld.slots[sp + 1])                # argument 1 is read by the alternative `m(b, _)`
            @test !LK.is_marked(ld.slots[sp + 2])               # argument 2 is a void there
            model = _gm_reach(ld, UInt64[w0])
            marked = _gm_marked(ld)
            @test !isempty(model) && marked == model
            @test st.total_marked == length(marked)
            @test LK.isRef(w1) ? !(LK.unRef(w1) in marked) : true
            LK.gc_clear_marks!(ld)
            _gm_restore!(ld, sn)
        end
    )
    @test length(ans) == 2 && ran[] == 1
end

@testset "deliberate corruptions FAIL the comparison" begin
    ld, t, n0 = _gm_heap()
    roots = _gm_fli_roots(ld)
    model = _gm_reach(ld, roots)
    st = LK.gc_mark_counts()
    LK.mark_phase(ld, st, LK.vm_state())
    @test _gm_agree(ld, roots)                                  # the guard CAN pass...
    marked0 = _gm_marked(ld)
    fcells = sort!([p for p in marked0 if LK.isFunctor(ld.gstack[p])])
    @test length(fcells) >= 3
    p = fcells[1]
    ld.gstack[p] = LK.clear_marked(ld.gstack[p])                # an unmarked LIVE cell
    @test !_gm_agree(ld, roots)                                 # ...and CAN fail
    @test setdiff(model, _gm_marked(ld)) == Set([p])            # naming exactly the cell
    ld.gstack[p] = LK.set_marked(ld.gstack[p])
    @test _gm_agree(ld, roots)
    dead = setdiff(Set(1:(ld.gTop)), model)
    @test !isempty(dead)
    d = first(sort!(collect(dead)))
    ld.gstack[d] = LK.set_marked(ld.gstack[d])                  # a stray mark on a DEAD cell
    @test !_gm_agree(ld, roots)
    ld.gstack[d] = LK.clear_marked(ld.gstack[d])
    @test _gm_agree(ld, roots)

    # a root class left out: the stacks walk alone (no term references) marks nothing of the heap
    ld2, t2, _ = _gm_heap()
    roots2 = _gm_fli_roots(ld2)
    model2 = _gm_reach(ld2, roots2)
    st2 = LK.gc_mark_counts()
    LK.mark_stacks(ld2, st2, LK.vm_state())
    @test !_gm_agree(ld2, roots2)
    @test isempty(_gm_marked(ld2)) && !isempty(model2) && st2.total_marked == 0
end
