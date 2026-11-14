# ORIGINAL: white-box tests of the VM-state provider of the stack collector (G1-GC G1-2b: src/pl-gcdriver.jl `gc_vmi_state_of`, `setStartOfVMI`,
# `gc_walk_start_of_vmi!`; upstream's pl-gc.c `get_vmi_state` (the registers.fr arm) and `setStartOfVMI`); swipl shows a collection only through its own
# statistics, so the only rows that consult swipl are the answers of programs (the collector must not change them).
# allow-new-artifact: G1-2b, the test of the provider (src/pl-gcdriver.jl), after test/core_lang/test_gc_driver.jl
# test/core_lang/test_gc_vmi_state.jl — the provider the safe points pass to `garbageCollect`:
#   * a collection at a FOREIGN-CALL safe point (functor/3, =../2, '$length'/2: the saved registers name the foreign frame) now RUNS: the statistics
#     totals rise, the answers equal the run without a collection, the engine is unblocked afterwards;
#   * live arguments survive: programs that build a dead structure, then live compounds sharing sub-terms, then the foreign call; the answers (views of
#     the argument handles through an independent reader: tags only) equal collection-off, and the answer text equals the PINNED swipl's;
#   * the provider on an open query: the frame, the choice, `lSave`, `argp`, `save_argp`, the body-mode `new_args`/`lNext`/`lTop` raise and the
#     argument-stack walk, the guard `pcc === codes`, the dcall1 `in_body`;
#   * the walk `gc_walk_start_of_vmi!` over compiled clauses, every instruction start and the pc inside it, against a second implementation in this
#     file and a hand-pinned table for a head with a compound;
#   * a state whose frame no pool owns MUST make the provider throw, and a wrong `lSave` MUST change `lTop` after the restore;
#   * the decline of a caller that passes no callback stays; with `gc_vmi_state_of` the same call collects.
# Every comparison reads both sides through ONE extractor, both non-empty; a testset runs at least one assertion with or without swipl.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _GV_GC = Int(LK.GC_USER)

# ---- the independent reader: tags only, variables numbered by first occurrence (as test_gc_driver.jl's, file-local) ----
"The term the word `w` names, as nested tuples: `(:var, k)`, `(:val, value)`, `(:cmp, functor word, [args])`, `(:w, word)` (an atom or a small integer)."
function _gv_word(ld, w::UInt64, vars::Dict{Int, Int}, depth::Int)
    depth > 400 && error("_gv_word: deeper than 400 (a cycle?)")
    w &= LK.VALUE_MASK
    if LK.isRef(w) && LK.storage(w) == LK.STG_GLOBAL
        return _gv_cell(ld, LK.unRef(w), vars, depth + 1)
    elseif LK._is_vword(w)
        return (:val, lk_value(ld.vtable[LK.valPtr(w)]))
    elseif LK._is_gcompound(w)
        f = LK.valPtr(w)
        fw = ld.gstack[f] & LK.VALUE_MASK
        n = LK.arityFunctor(ld.functors, fw)
        return (:cmp, fw, Any[_gv_cell(ld, f + i, vars, depth + 1) for i in 1:n])
    elseif LK.isAtomW(w) || LK.isTaggedIntW(w)
        return (:w, w)
    end
    return (:other, w)
end

"The term the global cell `p` holds: an unbound cell (zero, or a self reference) is a variable named by its first occurrence."
function _gv_cell(ld, p::Int, vars::Dict{Int, Int}, depth::Int)
    c = ld.gstack[p] & LK.VALUE_MASK
    if c == 0 || c == LK.makeRefG(p)
        return (:var, get!(vars, p, length(vars) + 1))
    end
    return _gv_word(ld, c, vars, depth)
end

"The views of the `n` term references from `t` (slots `t + 1 .. t + n`), one variable numbering over all of them."
function _gv_views(ld, t::Int, n::Int)::Vector{Any}
    vars = Dict{Int, Int}()
    return Any[_gv_word(ld, ld.slots[t + i], vars, 0) for i in 1:n]
end

"The number of nodes of a view."
_gv_nodes(v)::Int = v[1] === :cmp ? 1 + sum(_gv_nodes, v[3]; init=0) : 1

# ---- the programs ----
# fn1..fn3: the three foreign calls of the safe-point audit; gv1..gv4: live compounds sharing sub-terms around a foreign call (gv4: `garbage_collect/0`)
const _GV_PROG = Tuple{_R, Union{Nothing, _R}}[
    (
        _rf("fn1", _rv(1)),
        _rconj(_rf("functor", _rv(2), _rs("foo"), _rg(3)), _rf("=", _rv(1), _rv(2)))
    ),
    (
        _rf("fn2", _rv(1)),
        _rconj(
            _rf("=..", _rv(2), _rlist(_rs("f"), _rs("a"), _rs("b"))), _rf("=", _rv(1), _rv(2))
        )
    ),
    (
        _rf("fn3", _rv(1)),
        _rconj(_rf("\$length", _rv(2), _rg(3)), _rf("=", _rv(1), _rv(2)))
    ),
    (
        _rf("gv1", _rv(1)),
        _rconj(
            _rf("=", _rv(9), _rf("k", _rg(1), _rg(2), _rg(3), _rg(4), _rg(5), _rg(6))),
            _rf("=", _rv(2), _rf("f", _rf("g", _rg(1), _rg(2)), _rf("h", _rg(3)))),
            _rf("=", _rv(3), _rf("foo", _rv(2), _rv(2))),
            _rf("functor", _rv(4), _rs("bar"), _rg(3)),
            _rf("=", _rv(1), _rf("r", _rv(2), _rv(3), _rv(4)))
        )
    ),
    (
        _rf("gv2", _rv(1)),
        _rconj(
            _rf("=", _rv(2), _rf("f", _rf("g", _rg(1), _rg(2)), _rf("h", _rg(3)))),
            _rf("=..", _rv(3), _rlist(_rs("baz"), _rv(2), _rf("g", _rs("x")))),
            _rf("=", _rv(1), _rf("s", _rv(2), _rv(3)))
        )
    ),
    (
        _rf("gv3", _rv(1)),
        _rconj(
            _rf("=", _rv(2), _rf("f", _rf("g", _rg(1), _rg(2)))),
            _rf("\$length", _rv(3), _rg(3)),
            _rf("=", _rv(1), _rf("t", _rv(2), _rv(3)))
        )
    ),
    (
        _rf("gv4", _rv(1)),
        _rconj(
            _rf("=", _rv(2), _rf("f", _rf("g", _rg(1), _rg(2)), _rf("h", _rg(3)))),
            _rf("=", _rv(3), _rf("foo", _rv(2), _rv(2))),
            _rs("garbage_collect"),
            _rf("=", _rv(1), _rf("r", _rv(2), _rv(3)))
        )
    )
]

"A database of `_GV_PROG`, `gc_force` set to `force`."
function _gv_db(force::Bool)
    db = _rdb(copy(_GV_PROG))
    db.ld.gc_force = force
    return db
end

"One run of `name(V)`: `(answers, safe-point hits, collections it made, blocked, active)`."
function _gv_run(name::String, force::Bool)
    db = _gv_db(force)
    ld = db.ld
    c0 = ld.gc.stats.totals.collections
    out = _rcall(db, _rf(name, _rv(90)))
    return out, copy(ld.gc_safe_hits), ld.gc.stats.totals.collections - c0,
    ld.gc.status.blocked, ld.gc.status.active
end

"The views of the argument handles at the first answer of `goal` (the query closed after it): the independent reader's view of the answer."
function _gv_answer_views(db, goal::_R)::Vector{Any}
    ld = db.ld
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()
    for i in 1:n
        LK.putSlotValue!(ld, args + i, child(goal, i + 1), pvm)
    end
    qid = LK.PL_open_query(
        db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), args
    )
    rc = LK.PL_next_solution(db.gd, ld, qid)
    ok = rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    views = ok ? _gv_views(ld, args, n) : Any[]
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return views
end

@testset "foreign safe points run: functor/3, =../2 and '\$length'/2 collect, the answers stay those of a run without a collection" begin
    total_on = 0
    for name in ["fn1", "fn2", "fn3"]
        off, hits_off, coll_off, b0, a0 = _gv_run(name, false)
        on, hits_on, coll_on, b1, a1 = _gv_run(name, true)
        @info "gc_force foreign row" name coll_on coll_off hits_on     # diagnostic only: the assertions below are strict
        @test length(off) == 1 && !isempty(off[1][1])                  # the control answered
        @test on == off                                                # the same answers through ONE extractor (_rcall)
        @test isempty(hits_off) && !isempty(hits_on)                   # the safe point was reached only when forced
        @test coll_on >= 1 && coll_on >= coll_off                      # the provider lets the collector RUN (before G1-2b it declined)
        @test b0 == 0 && b1 == 0 && !a0 && !a1
        total_on += coll_on
    end
    @test total_on >= 3
end

# the answers of the programs of live compounds, as `_R_DRIVER` writes them (swipl 10.1.20, the pinned binary, two identical runs)
const _GV_GOALS = [_rf(n, _rv(90)) for n in ["gv1", "gv2", "gv3", "gv4"]]
const _GV_PINNED = [
    "gv1(r(f(g(1,2),h(3)),foo(f(g(1,2),h(3)),f(g(1,2),h(3))),bar(_,_,_))) det",
    "end",
    "gv2(s(f(g(1,2),h(3)),baz(f(g(1,2),h(3)),g(x)))) det",
    "end",
    "gv3(t(f(g(1,2)),[_,_,_])) det",
    "end",
    "gv4(r(f(g(1,2),h(3)),foo(f(g(1,2),h(3)),f(g(1,2),h(3))))) det",
    "end"
]

@testset "live arguments survive a collection at a foreign call: answers, views and the pinned swipl text" begin
    lines_off = _rlines(_gv_db(false), _GV_GOALS)
    db_on = _gv_db(true)
    c0 = db_on.ld.gc.stats.totals.collections
    lines_on = _rlines(db_on, _GV_GOALS)
    @test length(_GV_PINNED) == 8 && !isempty(lines_off) && !isempty(lines_on)
    @test lines_off == _GV_PINNED                                  # the kernel without a collection is swipl's
    @test lines_on == lines_off                                    # and with one
    @test db_on.ld.gc.stats.totals.collections - c0 >= 4           # a collection per program at least (gv4: also garbage_collect/0)
    if _R_SWIPL
        @test _rswipl(_GV_PROG, _GV_GOALS) == _GV_PINNED           # the pinned text is what swipl prints now
    end
    # the independent reader on the answer handles: the shared A is still one structure of the same shape, the dead k(1..6) is not in the answer
    for g in _GV_GOALS
        voff = _gv_answer_views(_gv_db(false), g)
        don = _gv_db(true)
        c1 = don.ld.gc.stats.totals.collections
        von = _gv_answer_views(don, g)
        @test length(voff) == 1 && _gv_nodes(voff[1]) >= 6         # non-empty, a compound with sub-terms
        @test von == voff
        @test don.ld.gc.stats.totals.collections > c1
        @test don.ld.gc.status.blocked == 0 && !don.ld.gc.status.active
    end
end

# ---- the provider on an open query ----
const _GV_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    # a clause with a body whose frame stays below n/1's: `bd(X) :- n(X), X = p(_, _)` (n/1 is called with I_CALL, not as the last call)
    (
        _rf("bd", _rv(1)),
        _rconj(_rf("n", _rv(1)), _rf("=", _rv(1), _rf("p", _rv(2), _rv(3))))
    )
]

"Run `bd(V)` and call `f(db)` at the first answer (the query open): `(ld, answers, f's result)`."
function _gv_live(f)
    db = _rdb(copy(_GV_CLAUSES))
    res = Ref{Any}(nothing)
    ans = _rcall(
        db, _rf("bd", _rv(90)); at=(qid, k) -> (k == 1 && (res[] = f(db)); nothing)
    )
    return db.ld, ans, res[]
end

"The frame of the innermost clause choicepoint (n/1's frame)."
function _gv_clause_frame(ld)::Int
    cl = 0
    ch = ld.BFR
    while ch != 0
        c = ld.choices[ch]
        (c.type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
        ch = c.parent
    end
    cl == 0 && error("_gv_clause_frame: no clause choicepoint")
    return ld.choices[cl].frame
end

"The start index of every instruction of clause `cl` (the clause's own `stepPC`)."
function _gv_starts(cl)::Vector{Int}
    out = Int[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        push!(out, pc.pc)
        pc = LK.stepPC(pc)
    end
    return out
end

"The provider's checks on an open query: a vector of `(name, ok)`; every register of the query that is touched is put back."
function _gv_provider_rows(db)
    ld = db.ld
    q = ld.queries[ld.query]
    nfr = _gv_clause_frame(ld)
    bfr = ld.frames[nfr].parent
    ndef = _rproc(db, _rf("n", _rv(1))).definition
    bdef = _rproc(db, _rf("bd", _rv(1))).definition
    ph = ld.placeholder
    rows = Tuple{String, Bool}[]
    chk!(name, ok) = push!(rows, (name, ok === true))
    saved = (q.registers_fr, q.registers_argp, q.registers_pc, q.next_environment, q.aSave)
    atop0, ltop0 = ld.aTop, ld.lTop
    nframe_clause = ld.frames[nfr].clause
    bframe_pred = ld.frames[bfr].predicate
    try
        chk!("premise: n's frame and its parent bd's frame",
            ld.frames[nfr].predicate === ndef && bframe_pred === bdef &&
            ld.frames[bfr].clause !== nothing && ld.frames[nfr].clause !== nothing)

        # (a) an ordinary clause frame, pc 0: the state of the exit of a call
        empty = LK.Code{_R}(LK.code[], _R[], 0)
        q.registers_fr = nfr
        q.registers_pc = empty
        q.next_environment = 0
        vm = LK.gc_vmi_state_of(ld, ld.query)
        chk!("frame is registers_fr", vm.frame == nfr)
        chk!("choice is BFR", vm.choice == ld.BFR && ld.BFR != 0)
        chk!("lSave is lTop, lTop untouched", vm.lSave == ltop0 && ld.lTop == ltop0)
        chk!("argp is the frame's first argument slot",
            vm.argp == LK.argFrameP(ld.frames[nfr].base, 0))
        chk!("save_argp of a frame with a clause", vm.save_argp == true)
        chk!("no VMI, no body, no new arguments",
            vm.pc == 0 && vm.pc_start_vmi == 0 && !vm.in_body && vm.new_args == 0 &&
            vm.lNext == 0 && vm.adepth == 0 && vm.argp0 == 0)

        # (b) the frame of a foreign call stood in for: no clause, so no walk, `save_argp` false (even with a pc)
        ld.frames[nfr].clause = nothing
        q.registers_pc = LK.Code{_R}(LK.code[0], _R[], 3)
        vmf = LK.gc_vmi_state_of(ld, ld.query)
        ld.frames[nfr].clause = nframe_clause
        chk!("foreign frame: save_argp false", vmf.save_argp == false)
        chk!("foreign frame: no VMI start, not in body, argp at its first slot",
            vmf.pc_start_vmi == 0 && !vmf.in_body && vmf.new_args == 0 &&
            vmf.argp == LK.argFrameP(ld.frames[nfr].base, 0))

        # (c) the frame of bd/1 inside its body (just inside the first I_CALL)
        bcl = (ld.frames[bfr].clause::LK.ClauseRef{_R}).clause
        starts = _gv_starts(bcl)
        ie = findfirst(s -> bcl.codes[s] == LK.I_ENTER, starts)
        ic = findfirst(s -> bcl.codes[s] == LK.I_CALL, starts)
        chk!("premise: bd's code has I_ENTER before I_CALL",
            ie !== nothing && ic !== nothing && ie < ic)
        pc = starts[ic] + 1
        q.registers_fr = bfr
        q.registers_pc = LK.Code(bcl, pc)
        lt = ld.lTop
        newbase = LK.argFrameP(lt, 0)                                # next_environment == 0: qlTop = lTop
        slot(p) = LK.argp_t{_R}(LK.ARGP_SLOT, p, ph)
        q.registers_argp = slot(newbase + 2)
        vmb = LK.gc_vmi_state_of(ld, ld.query)
        chk!("body: in_body, the VMI is the I_CALL", vmb.in_body && vmb.pc_start_vmi == starts[ic])
        chk!("body: two new arguments above the next frame",
            vmb.new_args == 2 && vmb.lNext == lt)
        chk!("body: lTop is raised to the argument pointer", ld.lTop == newbase + 2 && vmb.lSave == lt)
        LK.gc_restore_vmi_state(ld, vmb)
        chk!("body: restore puts lTop back to lSave", ld.lTop == lt)

        q.registers_argp = slot(newbase)                             # at the next frame's first argument: nothing new
        vme = LK.gc_vmi_state_of(ld, ld.query)
        chk!("body: ap == argFrameP(qlTop, 0) holds no new argument",
            vme.in_body && vme.new_args == 0 && vme.lNext == 0 && ld.lTop == lt)
        q.registers_argp = slot(newbase - 1)
        vml = LK.gc_vmi_state_of(ld, ld.query)
        chk!("body: ap below it holds none either",
            vml.new_args == 0 && vml.lNext == 0 && ld.lTop == lt)

        # (d) the argument stack: the registers hold a global ARGP, the entry below holds the local one
        LK.pushArgumentStack(ld, LK.argstack_entry{_R}(slot(newbase + 3), false))
        q.registers_argp = LK.argp_t{_R}(LK.ARGP_GLOBAL, 1, ph)
        q.aSave = ld.aTop - 1                                         # the entry is above the query's own height
        vma = LK.gc_vmi_state_of(ld, ld.query)
        chk!("argument stack: the local ARGP under a global one is found",
            vma.new_args == 3 && vma.lNext == lt && ld.lTop == newbase + 3)
        LK.gc_restore_vmi_state(ld, vma)
        q.aSave = ld.aTop                                             # nothing above the query's height: no entry may be read
        vmn = LK.gc_vmi_state_of(ld, ld.query)
        chk!("argument stack: an entry at or below aSave is not read",
            vmn.in_body && vmn.new_args == 0 && vmn.lNext == 0 && ld.lTop == lt)
        ld.aTop = atop0

        # (d2) next_environment is the frame itself: qlTop is not above the frame, so it is the end of the frame's arguments
        q.registers_argp = slot(newbase)
        q.registers_pc = LK.Code(bcl, pc)
        q.next_environment = bfr
        bar = LK.argFrameP(ld.frames[bfr].base, bdef.arity)           # qlTop = argFrameP(frame, arity)
        q.registers_argp = slot(LK.argFrameP(bar, 0) + 1)
        vm2 = LK.gc_vmi_state_of(ld, ld.query)
        chk!("next_environment == frame: qlTop is argFrameP(frame, arity)",
            vm2.in_body && vm2.new_args == 1 && vm2.lNext == bar)
        LK.gc_restore_vmi_state(ld, vm2)

        # (d3) next_environment is a frame above: qlTop is its base
        q.next_environment = nfr
        nb = ld.frames[nfr].base
        q.registers_argp = slot(LK.argFrameP(nb, 0) + 2)
        vm3 = LK.gc_vmi_state_of(ld, ld.query)
        chk!("next_environment above: qlTop is that frame's base",
            vm3.in_body && vm3.new_args == 2 && vm3.lNext == nb)
        LK.gc_restore_vmi_state(ld, vm3)
        q.next_environment = 0
        chk!("lTop is back after the two rows", ld.lTop == lt)

        # (e) the guard: the code of the registers must be THE clause's code
        q.registers_argp = slot(newbase)
        q.registers_pc = LK.Code{_R}(copy(bcl.codes), bcl.literals, pc)
        vmc = LK.gc_vmi_state_of(ld, ld.query)
        chk!("another vector of code finds no VMI", vmc.pc_start_vmi == 0 && !vmc.in_body)
        q.registers_pc = LK.Code(bcl, 0)                             # the clause's code but pc NULL: no walk
        vmz = LK.gc_vmi_state_of(ld, ld.query)
        chk!("pc 0 of the clause's code finds no VMI", vmz.pc == 0 && vmz.pc_start_vmi == 0 && !vmz.in_body)

        # (f) `<meta-call>`/1 has no head code: in_body from the first instruction on
        ld.frames[bfr].predicate = (ld.GD::LK.PL_global_data{_R}).procedures_dcall1.definition
        q.registers_pc = LK.Code(bcl, 2)
        vmd = LK.gc_vmi_state_of(ld, ld.query)
        ld.frames[bfr].predicate = bframe_pred
        chk!("dcall1 frame: in_body at once, the VMI is the first", vmd.in_body && vmd.pc_start_vmi == 1)
        ld.frames[bfr].predicate = _rproc(db, _rf("functor", _rv(1), _rv(2), _rv(3))).definition
        q.registers_pc = LK.Code(bcl, pc)
        vmo = LK.gc_vmi_state_of(ld, ld.query)
        ld.frames[bfr].predicate = bframe_pred
        chk!("a foreign predicate's frame is not walked", vmo.pc_start_vmi == 0 && !vmo.in_body)
        chk!("the same pc of an ordinary frame is not in the body",
            (q.registers_pc = LK.Code(bcl, 2); !LK.gc_vmi_state_of(ld, ld.query).in_body))
    finally
        ld.frames[nfr].clause = nframe_clause
        ld.frames[bfr].predicate = bframe_pred
        q.registers_fr, q.registers_argp, q.registers_pc, q.next_environment, q.aSave = saved
        ld.aTop = atop0
        ld.lTop = ltop0
    end
    return rows
end

@testset "the provider on an open query: frame, choice, lSave, argp, body mode, the argument stack, the guards" begin
    _, base, _ = _gv_live(db -> nothing)
    @test length(base) == 3 && all(a -> !isempty(a[1]), base)
    ld, ans, rows = _gv_live(_gv_provider_rows)
    @test rows !== nothing && length(rows) >= 25
    for (nm, ok) in rows
        @testset "provider: $nm" begin
            @test ok
        end
    end
    @test ans == base                                                # the query was not disturbed
end

# ---- the walk, over compiled clauses ----
# the second implementation: the pin's rule table, written here from the `setStartOfVMI` text, over the clause's own `stepPC`
const _GV_ONE_ARG = (
    LK.H_STRING, LK.H_MPZ, LK.H_MPQ, LK.H_LIST_FF, LK.H_FIRSTVAR, LK.H_VAR, LK.H_ATOM,
    LK.H_SMALLINT, LK.H_NIL, LK.H_FLOAT, LK.H_VOID
)

"`(pc_start_vmi, adepth, argp, argp0, in_body)` the pin's rule table gives for the register pc `pc` of clause `cl` whose frame starts at `base`."
function _gv_expect(cl, base::Int, pc::Int)
    codes = cl.codes
    starts = _gv_starts(cl)
    ad, ap, a0, body = 0, LK.argFrameP(base, 0), 0, false
    for (k, s) in enumerate(starts)
        nxt = k < length(starts) ? starts[k + 1] : length(codes) + 1
        nxt >= pc && return (s, ad, ap, a0, body)
        op = codes[s]
        if op in _GV_ONE_ARG
            ad == 0 && (ap += 1)
        elseif op == LK.H_VOID_N
            ad == 0 && (ap += Int(codes[s + 1]))
        elseif op == LK.B_UNIFY_VAR || op == LK.B_UNIFY_FIRSTVAR
            ap = LK.varFrameP(base, Int(codes[s + 1]))
        elseif op == LK.H_FUNCTOR || op == LK.H_LIST
            if ad == 0
                a0 = ap
                ap += 1
            end
            ad += 1
        elseif op == LK.B_FUNCTOR || op == LK.B_LIST
            ad += 1
        elseif op == LK.H_POP || op == LK.B_POP
            ad -= 1
            ad == 0 && (a0 = 0)
        elseif op == LK.I_ENTER || op == LK.I_SSU_COMMIT || op == LK.I_SSU_CHOICE
            body = true
        end
    end
    return (0, ad, ap, a0, body)
end

"Run the kernel's walk for register pc `pc`: the same tuple as `_gv_expect`."
function _gv_walk(cl, base::Int, pc::Int)
    vm = LK.vm_state()
    vm.pc = pc
    vm.argp = LK.argFrameP(base, 0)
    LK.gc_walk_start_of_vmi!(vm, cl.codes, base)
    return (vm.pc_start_vmi, vm.adepth, vm.argp, vm.argp0, vm.in_body)
end

@testset "the walk gc_walk_start_of_vmi!: every instruction start and the pc inside it, against the rule table" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    base = 100
    A, B, D = _rv(1), _rv(2), _rv(3)
    clauses = Dict{String, Any}(
        "head with a compound" => _radd!(
            db, _rf("w1", _rf("f", _rs("a"), B), _rs("c"), D), nothing
        ),
        "void run" => _radd!(db, _rf("w2", _rv(1), _rv(2), _rv(3), _rs("a")), nothing),
        "list head, body" => _radd!(
            db,
            _rf("w3", A, _rcons(B, D)),
            _rf("q", A, B, D)
        ),
        "unify var, compound in the body" => _radd!(
            db,
            _rf("w4", A),
            _rconj(_rf("=", A, _rf("f", B, _rf("g", B))), _rf("q", B))
        )
    )
    checked = 0
    bad = String[]
    seen = Set{UInt64}()
    for (nm, cl) in clauses
        starts = _gv_starts(cl)
        @test length(starts) >= 3                                    # non-empty: instructions to walk
        union!(seen, Set(cl.codes[s] for s in starts))
        pcs = unique(vcat(starts, starts .+ 1, [length(cl.codes) + 1, length(cl.codes) + 7]))
        for pc in pcs
            got = _gv_walk(cl, base, pc)
            want = _gv_expect(cl, base, pc)
            checked += 1
            got == want || push!(bad, "$nm pc=$pc got=$got want=$want")
        end
    end
    @test checked > 40
    @test isempty(bad)
    # the table covers the rules: each family of the pin's switch is reached by one of the clauses
    @test LK.H_FUNCTOR in seen && LK.H_POP in seen && LK.I_ENTER in seen
    @test LK.H_VOID_N in seen
    @test (LK.B_UNIFY_VAR in seen || LK.B_UNIFY_FIRSTVAR in seen) && LK.B_FUNCTOR in seen
    @test LK.H_LIST in seen || LK.H_LIST_FF in seen

    # the hand-pinned table of `w1(f(a,B), c, D)`: instructions H_FUNCTOR H_ATOM H_VOID H_POP H_ATOM H_VOID I_EXITFACT; the state BEFORE each of them
    cl1 = clauses["head with a compound"]
    st = _gv_starts(cl1)
    ops = [cl1.codes[s] for s in st]
    @test ops == UInt64[
        LK.H_FUNCTOR, LK.H_ATOM, LK.H_VOID, LK.H_POP, LK.H_ATOM, LK.H_VOID, LK.I_EXITFACT
    ]
    depth = [0, 1, 1, 1, 0, 0, 0]
    argoff = [0, 1, 1, 1, 1, 2, 3]
    arg0off = [0, 0, 0, 0, 0, 0, 0]
    for k in eachindex(st)
        g = _gv_walk(cl1, base, st[k] + 1)
        @test g[1] == st[k] && g[2] == depth[k]
        @test g[3] == LK.argFrameP(base, argoff[k])
        @test g[4] == (depth[k] > 0 ? LK.argFrameP(base, arg0off[k]) : 0)
        @test !g[5]
    end
    # a pc that is the start of an instruction stops at the one BEFORE it (the `>=` of `next >= state->pc`)
    for k in 2:length(st)
        @test _gv_walk(cl1, base, st[k])[1] == st[k - 1]
    end
    # past the end: no instruction holds it
    @test _gv_walk(cl1, base, length(cl1.codes) + 3)[1] == 0
    # in_body flips at I_ENTER: the state before the I_ENTER is outside the body, the state after it is inside
    cl3 = clauses["list head, body"]
    s3 = _gv_starts(cl3)
    i3 = findfirst(s -> cl3.codes[s] == LK.I_ENTER, s3)
    @test i3 !== nothing && i3 < length(s3)
    @test !_gv_walk(cl3, base, s3[i3] + 1)[5]
    @test _gv_walk(cl3, base, s3[i3 + 1] + 1)[5]
end

# ---- the corruption row, the restore, the decline premise ----
@testset "a frame no pool owns MUST make the provider throw; a wrong lSave MUST change lTop at the restore" begin
    ld, ans, res = _gv_live(
        function (db)
            ld = db.ld
            q = ld.queries[ld.query]
            old = q.registers_fr
            ltop0 = ld.lTop
            q.registers_fr = length(ld.frames) + 1
            thrown = try
                LK.gc_vmi_state_of(ld, ld.query)
                false
            catch e
                e isa BoundsError
            end
            thrown_gc = try
                LK.garbageCollect(ld, _GV_GC; vmi_state_of=LK.gc_vmi_state_of)
                false
            catch
                true
            end
            q.registers_fr = old
            unblocked = ld.gc.status.blocked == 0 && !ld.gc.status.active && ld.lTop == ltop0
            # a wrong lSave: restoring it moves lTop, a right one leaves it
            vm = LK.vm_state()
            vm.lSave = ltop0 + 5
            LK.gc_restore_vmi_state(ld, vm)
            moved = ld.lTop == ltop0 + 5
            vm2 = LK.vm_state()
            vm2.lSave = ltop0
            LK.gc_restore_vmi_state(ld, vm2)
            return (thrown, thrown_gc, unblocked, moved, ld.lTop == ltop0)
        end
    )
    @test res !== nothing && res == (true, true, true, true, true)
    @test length(ans) == 3 && all(a -> !isempty(a[1]), ans)
end

@testset "the decline of a caller without a callback stays; with gc_vmi_state_of the same call collects" begin
    _, base, _ = _gv_live(db -> nothing)
    @test length(base) == 3 && all(a -> !isempty(a[1]), base)
    ld, ans, res = _gv_live(
        function (db)
            ld = db.ld
            q = ld.queries[ld.query]
            old = (q.registers_fr, q.registers_pc, q.next_environment)
            q.registers_fr = _gv_clause_frame(ld)
            q.registers_pc = LK.Code{_R}(LK.code[], _R[], 0)
            q.next_environment = 0
            st = ld.gc.stats
            i0, c0 = st.last_index, st.totals.collections
            r0 = LK.garbageCollect(ld, _GV_GC)                       # no callback: declines, no record
            declined = r0 == LK.BOOLEX_FALSE && st.last_index == i0 && st.totals.collections == c0
            r1 = LK.garbageCollect(ld, _GV_GC; vmi_state_of=LK.gc_vmi_state_of)
            ran = r1 == LK.BOOLEX_TRUE && st.last_index == LK.STAT_NEXT_INDEX(i0) &&
                  st.totals.collections == c0 + 1
            q.registers_fr, q.registers_pc, q.next_environment = old
            return (declined, ran, ld.gc.status.blocked == 0 && !ld.gc.status.active)
        end
    )
    @test res !== nothing && res == (true, true, true)
    @test ans == base                                                # answers 2 and 3 are read after the collection
end
