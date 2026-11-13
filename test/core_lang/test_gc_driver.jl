# ORIGINAL: white-box tests of the stack collector's DRIVER (G1-GC G1-6c: src/pl-gcdriver.jl; upstream's pl-gc.c `garbageCollect`, `gcEnsureSpace`,
# `get_vmi_state`, `restore_vmi_state`, `tight`, `shiftTightStacks`); swipl shows a collection only through its own statistics, so nothing here consults swipl.
# allow-new-artifact: G1-6c, the test of the driver (src/pl-gcdriver.jl), after test/core_lang/test_gc_mark.jl and test_gc_sweep.jl
# test/core_lang/test_gc_driver.jl — `garbageCollect` on live engines, each result compared with an INDEPENDENT reader:
#   * the reader (`_gd_view`) walks the heap words from a root slot with TAGS ONLY (no mark bit, no kernel collector code) and names a variable by its
#     first occurrence, so the view of a term is the same before and after the cells moved; every comparison reads both sides through that ONE extractor,
#     both non-empty (the views have nodes), and a deliberate corruption of a live cell MUST change the view (the comparison can fail);
#   * a term built BELOW the live ones and then dropped is the dead list: `gTop` shrinks by at least its cells, the live views are identical, exactly one
#     statistics record is written (the ring index advances once, one more collection in the totals, `global_after < global_before`), a second collection
#     of the collected heap moves nothing;
#   * the flags: `mark_bar` (`NO_MARK_BAR` restored, a bar below the new top kept, a bar above it clamped), the pending `SIG_GC` cleared and `SIG_TUNE_GC`
#     kept, `blocked`/`active`/`lTop`/the foreign-frame chain as they were, `gc.inferences`;
#   * the declines (blocked, the `gc` flag off, a query inside the VM without G1-2b's `vmi_state_of` callback) answer `BOOLEX_FALSE` and leave every word
#     and the statistics ring as they were; with a callback a live query collects and its answers stay those of a run without a collection;
#   * `gc_force` (FAKE_GC's model) at the audited safe points of a small program: the answers are the same with and without it;
#   * `gcEnsureSpace`, `tight`, `growStacks_tight!`, `shiftTightStacks!`, `clear_unused_stack` and the VM state, by the numbers of their upstream formulas;
#   * a corrupted engine (an environment frame no query owns) MUST make the driver throw, and the engine stays unblocked.
# No row consults swipl, so no testset can run without an assertion.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_gd_atom(ld, n) = LK._atom_word!(ld, _rs(n))

# ---- the independent reader: tags only, variables numbered by first occurrence ----
"The term the word `w` names, as nested tuples: `(:var, k)`, `(:val, value)`, `(:cmp, functor word, [args])`, `(:w, word)` (an atom or a small integer)."
function _gd_word(ld, w::UInt64, vars::Dict{Int, Int}, depth::Int)
    depth > 400 && error("_gd_word: deeper than 400 (a cycle?)")
    w &= LK.VALUE_MASK
    if LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL
        return _gd_cell(ld, LK.unRef(w), vars, depth + 1)
    elseif LK._is_vword(w)
        return (:val, lk_value(ld.vtable[LK.valPtr(w)]))
    elseif LK._is_gcompound(w)
        f = LK.valPtr(w)
        fw = ld.gstack[f] & LK.VALUE_MASK
        n = LK.arityFunctor(ld.functors, fw)
        return (:cmp, fw, Any[_gd_cell(ld, f + i, vars, depth + 1) for i in 1:n])
    elseif LK.isAtomW(w) || LK.isTaggedIntW(w)
        return (:w, w)
    end
    return (:other, w)
end

"The term the global cell `p` holds: an unbound cell (zero, or a self reference) is a variable named by its first occurrence."
function _gd_cell(ld, p::Int, vars::Dict{Int, Int}, depth::Int)
    c = ld.gstack[p] & LK.VALUE_MASK
    if c == 0 || c == LK.makeRefG(p)
        return (:var, get!(vars, p, length(vars) + 1))
    end
    return _gd_word(ld, c, vars, depth)
end

"The views of the `n` term references from `t` (slots `t + 1 .. t + n`), one variable numbering over all of them."
function _gd_views(ld, t::Int, n::Int)::Vector{Any}
    vars = Dict{Int, Int}()
    return Any[_gd_word(ld, ld.slots[t + i], vars, 0) for i in 1:n]
end

"The number of nodes of a view."
_gd_nodes(v)::Int = v[1] === :cmp ? 1 + sum(_gd_nodes, v[3]; init = 0) : 1

"The stacks as they are: every word, the tops, the bar, the foreign-frame chain."
_gd_snap(ld) = (
    gtop = ld.gTop, g = copy(ld.gstack), s = copy(ld.slots), tr = copy(ld.trail), vbox = copy(ld.vbox),
    nvt = length(ld.vtable), ltop = ld.lTop, bar = ld.mark_bar, fli = ld.fli_context, nf = ld.nframes,
)

"An engine with a DEAD term built first (its only root dropped) and the values of `vs` above it: `(ld, t, n0, dead_cells)`."
function _gd_engine(dead::_R, vs::Vector{_R})
    @assert !isempty(vs)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    n0 = length(ld.vtable)
    LK.PL_open_foreign_frame(ld)
    pvm = LK.PutVarMap()
    td = LK.PL_new_term_ref(ld)
    g0 = ld.gTop
    LK.putSlotValue!(ld, td + 1, dead, pvm)
    g1 = ld.gTop
    ld.slots[td + 1] = _gd_atom(ld, "gone")                     # the only root of the dead term dropped
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm2 = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm2)
    end
    return ld, t, n0, (g0 + 1):g1
end

"The standard heap of the rows: a dead term (a float, a string, nested compounds, a list) below two live roots sharing a variable."
function _gd_heap()
    dead = _rf("dead", _rg(Int64(1)), _rf("dead2", _rg(7.25), _rg("gd-dead-string")), _rints(1:6))
    X = _rv(1)
    live = _R[
        _rf("f", _rs("a"), X, _rf("g", X, _rg(Int64(3))), _rg(1234.5678)),
        _rf("h", _rg("gd-live"), _rints(1:5), X),
    ]
    return _gd_engine(dead, live)
end

"The compound a root word names (through references): its functor cell position."
function _gd_functor_cell(ld, w::UInt64)::Int
    w &= LK.VALUE_MASK
    while LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL
        w = ld.gstack[LK.unRef(w)] & LK.VALUE_MASK
    end
    @assert LK._is_gcompound(w)
    return LK.valPtr(w)
end

const _GD_GC = Int(LK.GC_USER)

@testset "dead list: gTop shrinks, the live views are identical, one statistics record, the stacks check" begin
    ld, t, n0, dead_cells = _gd_heap()
    @test length(dead_cells) >= 10
    before = _gd_views(ld, t, 2)
    @test length(before) == 2 && all(v -> v[1] === :cmp && _gd_nodes(v) >= 7, before)
    @test any(v -> v[1] === :var, Iterators.flatten(Any[b[3] for b in before]))      # the shared variable is read
    gtop0 = ld.gTop
    ltop0, fli0, nf0 = ld.lTop, ld.fli_context, ld.nframes
    st = ld.gc.stats
    i0, c0 = st.last_index, st.totals.collections
    @test LK.check_stacks!(ld) > 0
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.gTop < gtop0
    @test ld.gTop <= gtop0 - length(dead_cells)                 # every cell of the dropped term (and its reference cell) is gone
    after = _gd_views(ld, t, 2)
    @test !isempty(after) && after == before                    # the live terms read the same through the moved cells
    @test st.last_index == LK.STAT_NEXT_INDEX(i0)               # one record
    @test st.totals.collections == c0 + 1
    rec = LK.last_gc_stats(st)
    @test rec.global_before > 0 && rec.global_after < rec.global_before
    @test rec.reason == UInt64(LK.GC_USER)
    @test ld.gc.status.blocked == 0 && !ld.gc.status.active
    @test ld.shift_status.blocked == 0
    @test (ld.lTop, ld.fli_context, ld.nframes) == (ltop0, fli0, nf0)       # the frames the collection opened are closed
    @test LK.check_stacks!(ld) > 0                              # the collected heap is well formed
    @test !any(LK.is_marked, view(ld.gstack, 1:(ld.gTop)))      # no mark bit is left
    # a second collection of a collected heap moves nothing and writes its own record
    gtop1 = ld.gTop
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.gTop == gtop1
    @test _gd_views(ld, t, 2) == before
    @test st.last_index == LK.STAT_NEXT_INDEX(LK.STAT_NEXT_INDEX(i0)) && st.totals.collections == c0 + 2
    # the comparison can fail: one live cell changed makes the views differ
    f = _gd_functor_cell(ld, ld.slots[t + 1])
    saved = ld.gstack[f + 1]
    ld.gstack[f + 1] = _gd_atom(ld, "gd-changed")
    @test _gd_views(ld, t, 2) != before
    ld.gstack[f + 1] = saved
    @test _gd_views(ld, t, 2) == before
end

@testset "a dead float and string leave the value table with their box cells, a live one stays readable" begin
    dead = _rf("d", _rg(2.5), _rg("gd-box-dead"), _rg(3.5))
    live = _R[_rf("l", _rg(1234.5678), _rg("gd-box-live"))]
    ld, t, n0, dead_cells = _gd_engine(dead, live)
    nv0 = length(ld.vtable)
    @test nv0 - n0 >= 5                                         # three dead boxes and two live ones
    before = _gd_views(ld, t, 1)
    @test _gd_nodes(before[1]) == 3 && count(a -> a[1] === :val, before[1][3]) == 2
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test length(ld.vtable) <= nv0
    @test _gd_views(ld, t, 1) == before                         # the values are read through the (possibly renumbered) table
    @test count(!=(0), ld.vbox) >= 2                            # the two live boxes are still listed
    @test all(b -> b == 0 || LK._is_vword(ld.gstack[b] & LK.VALUE_MASK), ld.vbox)   # every box cell is where the table says (tombstones are 0)
    @test LK.check_stacks!(ld) > 0
end

@testset "the global variables are roots: an nb_ value survives and is relocated" begin
    ld, t, n0, dead_cells = _gd_heap()
    key = _gd_atom(ld, "gd_var")
    ld.gvar_nb_vars[key] = ld.slots[t + 2] & LK.VALUE_MASK       # the value of the second root is also a global variable's value
    @test LK.gc_count_gvar_refs(ld) == 1
    before = _gd_views(ld, t, 2)
    gv0 = _gd_word(ld, ld.gvar_nb_vars[key], Dict{Int, Int}(), 0)
    @test gv0[1] === :cmp && _gd_nodes(gv0) >= 5
    gtop0 = ld.gTop
    # drop the root: only the global variable keeps the term alive
    ld.slots[t + 2] = _gd_atom(ld, "dropped")
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.gTop < gtop0
    gv1 = _gd_word(ld, ld.gvar_nb_vars[key], Dict{Int, Int}(), 0)
    @test gv1[1] === :cmp && gv1[2] == gv0[2] && _gd_nodes(gv1) == _gd_nodes(gv0)
    @test _gd_views(ld, t, 1)[1] == before[1]                   # root 1's variable is numbered first, so it reads the same once the second root goes
    @test LK.check_stacks!(ld) > 0
end

@testset "mark_bar: NO_MARK_BAR is restored, a bar below the new top is kept, a bar above it is clamped" begin
    # NO_MARK_BAR before and after
    ld, t, n0, dead_cells = _gd_heap()
    ld.mark_bar = LK.NO_MARK_BAR
    before = _gd_views(ld, t, 2)
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.mark_bar == LK.NO_MARK_BAR
    @test _gd_views(ld, t, 2) == before
    # a bar of 1 stays 1
    ld, t, n0, dead_cells = _gd_heap()
    ld.mark_bar = 1
    before = _gd_views(ld, t, 2)
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.gTop > 1 && ld.mark_bar == 1
    @test _gd_views(ld, t, 2) == before
    # a bar at the old top is clamped to the new, lower top
    ld, t, n0, dead_cells = _gd_heap()
    gtop0 = ld.gTop
    ld.mark_bar = gtop0
    before = _gd_views(ld, t, 2)
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.gTop < gtop0
    @test ld.mark_bar == ld.gTop && ld.mark_bar < gtop0
    @test _gd_views(ld, t, 2) == before
    # a bar between the new and the old top is clamped as well
    ld, t, n0, dead_cells = _gd_heap()
    gtop0 = ld.gTop
    ld.mark_bar = gtop0 - 1
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test ld.mark_bar == min(gtop0 - 1, ld.gTop)
    @test ld.mark_bar <= ld.gTop
    @test ld.gc.status.blocked == 0 && !ld.gc.status.active
end

@testset "signals and counters: SIG_GC is cleared, SIG_TUNE_GC kept, gc.inferences is the inference count" begin
    ld, t, n0, dead_cells = _gd_heap()
    LK.raiseGcSignal!(ld, LK.SIG_GC)
    LK.raiseGcSignal!(ld, LK.SIG_TUNE_GC)
    @test LK.pendingGcSignal(ld, LK.SIG_GC) && LK.pendingGcSignal(ld, LK.SIG_TUNE_GC)
    ld.statistics.inferences = 424242
    ld.gc.inferences = 0
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE
    @test !LK.pendingGcSignal(ld, LK.SIG_GC)
    @test LK.pendingGcSignal(ld, LK.SIG_TUNE_GC)                # only SIG_GC is cleared
    @test ld.gc.inferences == ld.statistics.inferences == 424242
    # a collection that declines clears nothing
    ld2, t2, _, _ = _gd_heap()
    ld2.gc.status.blocked = 1
    LK.raiseGcSignal!(ld2, LK.SIG_GC)
    ld2.gc.inferences = 7
    ld2.statistics.inferences = 99
    @test LK.garbageCollect(ld2, _GD_GC) == LK.BOOLEX_FALSE
    @test LK.pendingGcSignal(ld2, LK.SIG_GC) && ld2.gc.inferences == 7
end

@testset "declines: blocked and the gc flag off leave every word and the statistics ring as they were" begin
    ld, t, n0, dead_cells = _gd_heap()
    sn = _gd_snap(ld)
    st = ld.gc.stats
    i0, c0 = st.last_index, st.totals.collections
    @test !isempty(sn.g) && sn.gtop > 0 && !isempty(sn.s)
    ld.gc.status.blocked = 1
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_FALSE
    @test _gd_snap(ld) == sn
    @test st.last_index == i0 && st.totals.collections == c0
    @test ld.gc.status.blocked == 1                              # not unblocked by the decline
    ld.gc.status.blocked = 0
    mask0 = ld.prolog_flag_mask
    @test LK.truePrologFlag(ld, LK.PLFLAG_GC)
    ld.prolog_flag_mask &= ~LK.prologFlagMask(LK.PLFLAG_GC)     # flag `gc` off: never
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_FALSE
    @test _gd_snap(ld) == sn
    @test st.last_index == i0 && st.totals.collections == c0
    ld.prolog_flag_mask = mask0
    @test LK.garbageCollect(ld, _GD_GC) == LK.BOOLEX_TRUE        # flag back on and unblocked: it collects
    @test ld.gTop < sn.gtop && st.last_index == LK.STAT_NEXT_INDEX(i0)
end

# a live query: the three clauses of n/1 of the sweep tests, the callback of G1-2b stood in for by the vm_state of the first choicepoint's frame
const _GD_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
]

"Run `n(V)` and call `f(ld)` at the first answer (the query open): `(ld, answers, f's result)`."
function _gd_live_run(f)
    db = _rdb(copy(_GD_CLAUSES))
    ld = db.ld
    res = Ref{Any}(nothing)
    ans = _rcall(db, _rf("n", _rv(90)); at = (qid, k) -> (k == 1 && (res[] = f(ld)); nothing))
    return ld, ans, res[]
end

"The vm_state of the frame of the innermost clause choicepoint, as the sweep tests build it (`G1-2b`'s callback stand-in)."
function _gd_vm_of_clause(ld)
    cl = 0
    ch = ld.BFR
    while ch != 0
        c = ld.choices[ch]
        (c.type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
        ch = c.parent
    end
    cl == 0 && error("_gd_vm_of_clause: no clause choicepoint")
    vm = LK.vm_state()
    vm.frame = ld.choices[cl].frame
    vm.choice = ld.BFR
    vm.pc_start_vmi = 0
    vm.lSave = ld.lTop
    return vm
end

@testset "a live query: the decline without a callback, the VM state, the collection with one" begin
    _, base, _ = _gd_live_run(ld -> nothing)
    @test length(base) == 3 && all(a -> !isempty(a[1]), base)

    # (1) inside the VM, no callback: BOOLEX_FALSE, nothing touched, no record
    ld, ans, res = _gd_live_run(
        function (ld)
            @test ld.query != 0
            q = ld.queries[ld.query]
            old = q.registers_fr
            q.registers_fr = 1                                    # the query is inside the VM
            sn = _gd_snap(ld)
            st = ld.gc.stats
            i0, c0 = st.last_index, st.totals.collections
            r = LK.garbageCollect(ld, _GD_GC)
            ok = r == LK.BOOLEX_FALSE && _gd_snap(ld) == sn && st.last_index == i0 && st.totals.collections == c0 &&
                ld.gc.status.blocked == 0 && !ld.gc.status.active
            nostate = LK.gc_get_vmi_state(ld, ld.query, nothing) === nothing
            sv = LK.vm_state()
            same = LK.gc_get_vmi_state(ld, ld.query, (l, qi) -> sv) === sv      # the callback's own object
            other = LK.gc_get_vmi_state(ld, 0, (l, qi) -> sv)                  # no query: the else arm, never the callback
            q.registers_fr = old
            return (ok, nostate, same, other !== sv && other.lSave == ld.lTop && other.choice == ld.BFR && !other.save_argp && !other.in_body)
        end
    )
    @test res !== nothing && res == (true, true, true, true)
    @test ans == base                                             # the query was not disturbed

    # (2) inside the VM with the callback: the collection runs, the answers stay those of the run without one
    called = Ref(0)
    ld, ans, res = _gd_live_run(
        function (ld)
            q = ld.queries[ld.query]
            old = q.registers_fr
            q.registers_fr = 1
            st = ld.gc.stats
            i0, c0 = st.last_index, st.totals.collections
            cb = (l, qi) -> (called[] += 1; _gd_vm_of_clause(l))
            r = LK.garbageCollect(ld, _GD_GC; vmi_state_of = cb)
            q.registers_fr = old
            return (r == LK.BOOLEX_TRUE, st.last_index == LK.STAT_NEXT_INDEX(i0), st.totals.collections == c0 + 1,
                ld.gc.status.blocked == 0 && !ld.gc.status.active)
        end
    )
    @test called[] >= 1
    @test res !== nothing && res == (true, true, true, true)
    @test ans == base                                             # answers 2 and 3 are read after the collection
    @test length(ans) == 3
end

@testset "gc_force at the audited safe points of a small program: the answers are the same (the collector declines inside the VM without G1-2b's callback)" begin
    prog = Tuple{_R, Union{Nothing, _R}}[
        (_rf("gd8", _rv(1)), _rconj(_rf("functor", _rv(2), _rs("foo"), _rg(3)), _rf("=", _rv(1), _rv(2)))),
        (_rf("gd10", _rv(1)), _rconj(_rf("=..", _rv(2), _rlist(_rs("f"), _rs("a"), _rs("b"))), _rf("=", _rv(1), _rv(2)))),
        (_rf("gd12", _rv(1)), _rconj(_rf("\$length", _rv(2), _rg(3)), _rf("=", _rv(1), _rv(2)))),
    ]
    names = ["gd8", "gd10", "gd12"]
    function _run(force::Bool)
        db = _rdb(copy(prog))
        db.ld.gc_force = force
        out = Vector{Tuple{String, Bool}}[_rcall(db, _rf(n, _rv(90))) for n in names]
        return out, copy(db.ld.gc_safe_hits), db.ld.gc.status.blocked, db.ld.gc.status.active
    end
    off, hits_off, b0, a0 = _run(false)
    on, hits_on, b1, a1 = _run(true)
    @test all(a -> length(a) == 1 && !isempty(a[1][1]), off)
    @test on == off
    @test isempty(hits_off)
    @test !isempty(hits_on)                                       # the sites were reached
    @test b0 == 0 && b1 == 0 && !a0 && !a1
end

@testset "clear_unused_stack writes nothing (a release build of swipl)" begin
    ld, t, n0, dead_cells = _gd_heap()
    sn = _gd_snap(ld)
    @test !isempty(sn.g) && !isempty(sn.s)
    @test LK.clear_unused_stack(ld) === nothing
    @test _gd_snap(ld) == sn
end

@testset "gc_get_vmi_state and gc_restore_vmi_state: the state of no query, lTop put back" begin
    ld, t, n0, dead_cells = _gd_heap()
    @test ld.query == 0
    vm = LK.gc_get_vmi_state(ld, 0, nothing)
    @test vm isa LK.vm_state
    @test vm.choice == ld.BFR && vm.lSave == ld.lTop && vm.frame == ld.environment_frame
    @test !vm.save_argp && !vm.in_body && vm.pc == 0 && vm.pc_start_vmi == 0 && vm.adepth == 0 && vm.lNext == 0 && vm.new_args == 0
    lt0 = ld.lTop
    # lSave below lTop: lowered; above: raised; equal: unchanged
    ld.lTop = lt0 + 5
    vm.lSave = lt0
    LK.gc_restore_vmi_state(ld, vm)
    @test ld.lTop == lt0
    vm.lSave = lt0 + 3
    LK.gc_restore_vmi_state(ld, vm)
    @test ld.lTop == lt0 + 3
    LK.gc_restore_vmi_state(ld, vm)
    @test ld.lTop == lt0 + 3
    ld.lTop = lt0
end

@testset "gc_count_gvar_refs counts the global-stack values of the nb_ variables only" begin
    ld, t, n0, dead_cells = _gd_heap()
    @test LK.gc_count_gvar_refs(ld) == 0
    ld.gvar_nb_vars[_gd_atom(ld, "gd_v1")] = ld.slots[t + 1] & LK.VALUE_MASK     # a compound (or a reference to one)
    @test LK.gc_count_gvar_refs(ld) == 1
    ld.gvar_nb_vars[_gd_atom(ld, "gd_v2")] = _gd_atom(ld, "plain")              # an atom: not a global value
    @test LK.gc_count_gvar_refs(ld) == 1
    ld.gvar_nb_vars[_gd_atom(ld, "gd_v3")] = ld.slots[t + 2] & LK.VALUE_MASK
    @test LK.gc_count_gvar_refs(ld) == 2
end

@testset "gcEnsureSpace: the terms of lneeded, the spare arm, the growing arm, the overflow" begin
    scratch() = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld
    # nothing needed: untouched
    ld = scratch()
    lm0, sp0 = ld.lMax, ld.local_spare
    @test sp0 > 0
    vm = LK.gc_get_vmi_state(ld, 0, nothing)
    @test LK.gcEnsureSpace(ld, vm) == LK.BOOLEX_TRUE
    @test (ld.lMax, ld.local_spare) == (lm0, sp0)
    # the global variables: SIZEOF_FLIFRAME + n + 2, n the larger of the hint and the real count; exact fit uses nothing, one more uses the spare
    for (hint, real) in ((5, 0), (0, 1), (3, 1))
        n = max(hint, real)
        need = LK.SIZEOF_FLIFRAME + n + 2
        for (extra, spare_used) in ((0, false), (1, true))
            ld = scratch()
            ld.gvar_grefs = hint
            for i in 1:real
                ld.gvar_nb_vars[_gd_atom(ld, "gd_k$i")] = LK.makeRefG(1)          # a global reference value
            end
            lm0, sp0 = ld.lMax, ld.local_spare
            ld.lTop = lm0 - need + extra
            vm = LK.gc_get_vmi_state(ld, 0, nothing)
            @test LK.gcEnsureSpace(ld, vm) == LK.BOOLEX_TRUE
            @test (ld.local_spare == 0) == spare_used
            @test ld.lMax == (spare_used ? lm0 + sp0 : lm0)
        end
    end
    # the frozen bar: one more position
    for (fb, spare_used) in ((0, false), (1, true))
        ld = scratch()
        ld.frozen_bar = fb
        lm0, sp0 = ld.lMax, ld.local_spare
        ld.lTop = lm0
        vm = LK.gc_get_vmi_state(ld, 0, nothing)
        @test LK.gcEnsureSpace(ld, vm) == LK.BOOLEX_TRUE
        @test (ld.local_spare == 0) == spare_used
    end
    # the argument stack: SIZEOF_FLIFRAME + aTop + 1 when the VM state saves ARGP
    for (sa, spare_used) in ((false, false), (true, true))
        ld = scratch()
        lm0, sp0 = ld.lMax, ld.local_spare
        ld.lTop = lm0 - (LK.SIZEOF_FLIFRAME + ld.aTop)
        vm = LK.gc_get_vmi_state(ld, 0, nothing)
        vm.save_argp = sa
        @test LK.gcEnsureSpace(ld, vm) == LK.BOOLEX_TRUE
        @test (ld.local_spare == 0) == spare_used
    end
    # past the spare: the stack grows, the caller is told to build the VM state again (BOOLEX_FALSE), and lTop is kept
    ld = scratch()
    ld.gvar_grefs = 100_000
    lt0 = ld.lTop
    vm = LK.gc_get_vmi_state(ld, 0, nothing)
    @test LK.gcEnsureSpace(ld, vm) == LK.BOOLEX_FALSE
    @test ld.lMax + ld.local_spare > 100_000 && ld.lTop == lt0
    # past the limit: the overflow code
    ld = scratch()
    ld.gvar_grefs = 100_000
    ld.stacks_limit = 1000
    vm = LK.gc_get_vmi_state(ld, 0, nothing)
    @test LK.gcEnsureSpace(ld, vm) == LK.LOCAL_OVERFLOW
end

@testset "tight, growStacks_tight!, shiftTightStacks!: the formula of pl-gc.c tight() in positions" begin
    scratch() = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld
    ld = scratch()
    @test LK.tight(ld, :local) == 0 && LK.tight(ld, :global) == 0 && LK.tight(ld, :trail) == 0
    @test LK.GROW_TIGHT != 0
    size = ld.lMax + ld.local_spare
    gap = ld.local_def_spare - ld.local_spare
    mr = max(size ÷ 3, LK.LOCAL_MARGIN)
    @test mr == size ÷ 3 > 0
    # the boundary: room == min_room + gap is not tight, one less is
    ld.lTop = ld.lMax - (mr + gap)
    @test LK.tight(ld, :local) == 0
    ld.lTop += 1
    @test LK.tight(ld, :local) == LK.GROW_TIGHT
    # the global stack and the trail are never tight
    @test LK.tight(ld, :global) == 0 && LK.tight(ld, :trail) == 0
    # the spare gap moves the boundary
    ld = scratch()
    ld.local_spare = ld.local_def_spare - 7
    size = ld.lMax + ld.local_spare
    mr = max(size ÷ 3, LK.LOCAL_MARGIN)
    ld.lTop = ld.lMax - (mr + 7)
    @test LK.tight(ld, :local) == 0
    ld.lTop += 1
    @test LK.tight(ld, :local) == LK.GROW_TIGHT
    # the floor: a small stack's third is below LOCAL_MARGIN, which then decides
    ld = scratch()
    ld.lMax = 300
    ld.local_spare = 0
    ld.local_def_spare = 0
    ld.lTop = 0
    @test 300 ÷ 3 < LK.LOCAL_MARGIN
    @test LK.tight(ld, :local) == LK.GROW_TIGHT                   # room 300 < LOCAL_MARGIN
    # not tight: growStacks_tight! and shiftTightStacks! change nothing
    ld = scratch()
    lm0, sp0 = ld.lMax, ld.local_spare
    @test LK.growStacks_tight!(ld, 0) == LK.BOOLEX_TRUE
    @test LK.shiftTightStacks!(ld) == LK.BOOLEX_TRUE
    @test (ld.lMax, ld.local_spare) == (lm0, sp0)
    # tight: the stack grows to the next size
    ld = scratch()
    lm0, sp0 = ld.lMax, ld.local_spare
    before = lm0 + sp0
    ld.lTop = lm0 - 10
    @test LK.tight(ld, :local) == LK.GROW_TIGHT
    @test LK.shiftTightStacks!(ld) == LK.BOOLEX_TRUE
    @test ld.lMax + ld.local_spare == 2 * before
    @test LK.tight(ld, :local) == 0                              # no longer tight
    # tight and the limit refuses: the overflow code, nothing grown
    ld = scratch()
    lm0, sp0 = ld.lMax, ld.local_spare
    ld.lTop = lm0 - 10
    ld.stacks_limit = 1
    @test LK.shiftTightStacks!(ld) == LK.LOCAL_OVERFLOW
    @test ld.lMax + ld.local_spare == lm0 + sp0
    @test LK.growStacks_tight!(ld, LK.GROW_TIGHT) == LK.LOCAL_OVERFLOW
end

@testset "a corrupted engine MUST make the driver throw, and the flags are put back" begin
    ld, t, n0, dead_cells = _gd_heap()
    @test ld.query == 0 && ld.environment_frame == 0
    ld.environment_frame = 1                                       # an environment frame no query owns: the walk reaches no query frame
    ld.mark_bar = LK.NO_MARK_BAR
    @test_throws Exception LK.garbageCollect(ld, _GD_GC)
    @test ld.gc.status.blocked == 0 && !ld.gc.status.active       # the finally ran
    @test ld.shift_status.blocked == 0
    @test ld.mark_bar == LK.NO_MARK_BAR                            # and restored the bar
    ld.environment_frame = 0
    # the same engine, uncorrupted, collects: the throw was the corruption's
    ld2, t2, _, _ = _gd_heap()
    @test LK.garbageCollect(ld2, _GD_GC) == LK.BOOLEX_TRUE
end
