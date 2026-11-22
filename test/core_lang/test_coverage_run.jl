# ORIGINAL: a direct test of the VM-side coverage functions of pl-coverage.c (`record_coverage`, `call_site`, `clref_site`, `bump`,
# `running_static_predicate`, `Coverage`) and of `updateAlerted`'s ALERT_COVERAGE bit; no swipl counterpart (the differential of the
# collection through the VM is test_coverage_run_swipl.jl, COV1 piece C).
# test/core_lang/test_coverage_run.jl — COV1 piece A. WRITTEN BLIND (nothing compiled): the lane's first run may need fixes.
# The VM does not call the hooks yet (piece B), so the test calls them on the goal frame of a JUST-OPENED query: its parent is the query's
# top frame (static `$call_prolog`, clause `gd.clauses_top_cref`) and its `programPointer` is `Code(top_clause, 1)`, the state of the very
# first call port; no instruction has run.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

# a kernel with `cvg(1).` loaded and a query on `cvg(_)` opened (not run): returns (gd, ld, qid, goal frame index)
function open_cvg(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    path = joinpath(mktempdir(), "cvg.pl")
    write(path, "cvg(1).\n")
    st, _ = LK.load_file!(gd, ld, path)
    st === :ok || error("cvg.pl did not load")
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, :cvg)), 1, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    qf = LK.QueryFromQid(ld, qid)
    return gd, ld, qid, fid, ld.queries[qf].frame
end

function _cov_close(ld, qid, fid)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "COV1 A: the port masks and the alert bit are upstream's" begin
    @test (LK.CALL_PORT, LK.EXIT_PORT, LK.UNIFY_PORT) == (0x001, 0x002, 0x010)
    @test LK.ALERT_COVERAGE == 0x400
end

@testset "COV1 A: updateAlerted sets ALERT_COVERAGE while the collection is active" begin
    T = _TL
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    LK.updateAlerted(ld)
    @test (ld.alerted & LK.ALERT_COVERAGE) == 0
    ld.coverage.active = 1
    LK.updateAlerted(ld)
    @test (ld.alerted & LK.ALERT_COVERAGE) != 0
    ld.coverage.active = 0
    LK.updateAlerted(ld)
    @test (ld.alerted & LK.ALERT_COVERAGE) == 0
end

@testset "COV1 A: bump counts calls and exits and refuses another port" begin
    T = _TL
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    cl = gd.clauses_top_clause
    cov = LK.newCoverageData(T)
    obj = LK.clause_site(gd, cov, cl)
    @test obj !== nothing && obj.enter == 0 && obj.exits == 0
    LK.bump(obj, LK.CALL_PORT)
    LK.bump(obj, LK.CALL_PORT)
    LK.bump(obj, LK.EXIT_PORT)
    @test (obj.enter, obj.exits) == (2, 1)
    @test LK.bump(nothing, LK.CALL_PORT) === nothing
    @test_throws ErrorException LK.bump(obj, LK.UNIFY_PORT)
    @test (obj.enter, obj.exits) == (2, 1)
end

@testset "COV1 A: clref_site makes one clause site and returns it again" begin
    T = _TL
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    ld.coverage.data = LK.newCoverageData(T)
    s1 = LK.clref_site(gd, ld, gd.clauses_top_cref)
    s2 = LK.clref_site(gd, ld, gd.clauses_top_cref)
    @test s1 !== nothing && s1 === s2 && s1.type == LK.COV_CLAUSE && s1.pc == -1
    @test length(ld.coverage.data.objs) == 1
end

@testset "COV1 A: the call port at a query's first call site, the exit port, no data" begin
    T = _TL
    gd, ld, qid, fid, fr = open_cvg(T)
    f = ld.frames[fr]
    @test LK.running_static_predicate(ld.frames[f.parent])        # the top frame runs a static predicate
    # not active: nothing recorded, no data made
    LK.Coverage(gd, ld, fr, LK.CALL_PORT)
    @test ld.coverage.data === nothing
    # active, data present
    ld.coverage.data = LK.newCoverageData(T)
    ld.coverage.active = 1
    LK.Coverage(gd, ld, fr, LK.CALL_PORT)
    cov = ld.coverage.data
    @test length(cov.objs) == 1
    o = cov.objs[1]
    @test o.type == LK.COV_PC && o.pc == 0 && (o.enter, o.exits) == (1, 0)    # the return pc is the top clause's first word
    LK.Coverage(gd, ld, fr, LK.CALL_PORT)
    @test length(cov.objs) == 1 && o.enter == 2                  # the same site
    LK.Coverage(gd, ld, fr, LK.EXIT_PORT)
    @test o.exits == 1 && length(cov.objs) == 1                  # the goal frame has no clause yet: no clause site
    LK.Coverage(gd, ld, fr, LK.UNIFY_PORT)
    @test length(cov.objs) == 1 && (o.enter, o.exits) == (2, 1)
    # the same data through '$cov_data' (the kernel reads its own table)
    key = LK._cov_key(gd.clause_serials[gd.clauses_top_clause], 0)
    @test LK.lookupHTable(cov.table, key) != LK.NULL_VALUE
    # a goal frame with a clause: the unify port counts its entry, the exit port its exit and the call site's
    f.clause = gd.clauses_top_cref
    LK.record_coverage(gd, ld, fr, LK.UNIFY_PORT)
    csite = LK.clref_site(gd, ld, gd.clauses_top_cref)
    @test csite.enter == 1 && csite.exits == 0
    LK.record_coverage(gd, ld, fr, LK.EXIT_PORT)
    @test csite.enter == 1 && csite.exits == 1 && o.exits == 2
    LK.record_coverage(gd, ld, fr, LK.CALL_PORT)               # the call port counts the call site only, never the clause
    @test csite.enter == 1 && o.enter == 3
    # (a dynamic predicate's frame, and a dynamic parent, are piece C's differential rows)
    f.clause = nothing
    ld.coverage.active = 0
    _cov_close(ld, qid, fid)
end
