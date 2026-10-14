# ORIGINAL: the temporary goal clause's cells and saved program pointer, read directly (V9e-2) — the mutation gate's first target; upstream has no such test.
# test/core_lang/test_goal_clause.jl — what pl-comp.c compileClause (NULL head) writes into the frame and what pl-vmi.c i_metacall_common saves, each expected value cited by upstream line
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

_rgc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
    (_rf("q", _rs("a")), nothing), (_rf("q", _rs("b")), nothing),
    (_rf("c", _rv(1)), _rf("call", _rv(1)))
]

# What the goal clause writes and saves, read directly — a broken frame here makes the VM LOOP on a
# later return rather than answer wrongly, so the answers above cannot catch it in bounded time. EVERY
# expected value below is upstream's, cited by line at the pin `ac807ba8` (not a snapshot of the
# kernel's output): pl-comp.c compileClause with a NULL head — the goal in pseudo variable 1
# (c:2030, 2040), `argvars = argvar = 1` (c:2034-2035); compileArgument's `argvar:` path — a compound
# argument stored as is in the next pseudo variable and `argvar++` (c:3170, 3181, 3189), a string
# argument the same (`case TAG_STRING: … goto argvar`, c:3065-3067), arguments left to right
# (compileSubClause's loop, c:3588-3592); a variable's offset `n + argvars` (analyse_variables,
# c:1365, numbered by first occurrence) and its cell linked to it (`link_local_var`: `*k =
# makeRefG(vd->address)`, c:2947, called at c:3085); pl-vmi.c i_metacall_common's local branch —
# `NFR->programPointer = PC` (vmi:5494) with PC past `I_CALL1`, an instruction of no operands
# (`VMI(I_CALL1, VIF_BREAK, 0, ())`, vmi:5343).
@testset "the goal clause: its cells are written; its frame saves the caller's program pointer" begin
    db = _rdb(_rgc_clauses())
    gd, ld = db.gd, db.ld
    X, Y = _rv(91), _rv(92)
    goal = _rconj(
        _rf("p", X), _rf("g5", _rf("f", _rg(1)), _rg("s"), _rf("f", _rg(3)), Y, _rs("a"))
    )
    base = ld.lTop
    cl = LK.compileGoalClause(gd, ld, goal, db.user, base)
    @test cl !== nothing && (cl.flags & LK.GOAL_CLAUSE) != 0
    cell(i) = LK.slotValue(ld, LK.varFrameP(base, Int(LK.VAROFFSET(i))) + 1)
    @test LK.compareStandard(cell(1), _rf("f", _rg(1)), true) == 0      # argvar 1 (c:2035, 3181)
    @test LK.compareStandard(cell(2), _rg("s"), true) == 0              # argvar 2: a string (c:3065)
    @test LK.compareStandard(cell(3), _rf("f", _rg(3)), true) == 0      # argvar 3 (c:3189)
    vars = [cell(i) for i in 4:5]                       # offsets argvars + n = 4, 5 (c:1365, 2947)
    @test all(v -> kind(v) === VAR, vars)
    @test Set(var_key.(vars)) == Set(var_key.((X, Y)))
    # at the FIRST answer inside the call the goal frame is live: its program pointer is the CALLER's
    # code, just past the I_CALL1 that made it (MV5: a stale pointer loops on the return, so the query
    # is closed at that answer — nothing returns through the goal frame here)
    ccl = _rproc(db, _rf("c", _rv(1))).definition.impl_clauses.first_clause.clause
    k1 = findfirst(==(LK.I_CALL1), ccl.codes)
    g = _rf("c", _rconj(_rf("p", _rv(51)), _rf("q", _rv(52))))
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, args + 1, child(g, 2))
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, g), args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == LK.PL_S_TRUE
    seen = 0
    for i in 1:(ld.nframes)
        f = ld.frames[i]
        f.predicate === gd.procedures_dcall1.definition || continue
        seen += 1
        @test f.programPointer.codes === ccl.codes && f.programPointer.pc == k1 + 1   # vmi:5494
    end
    @test seen == 1
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
