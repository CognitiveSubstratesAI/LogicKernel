# ORIGINAL: L1f step f2 — the global-stack limit (pl-gc.h ensureGlobalSpace, pl-alloc.c outOfStack for the global
# stack; src/pl-alloc.jl, the VM's check at normal_call in src/pl-wam.jl; audit D-0029 D1 (a), D2 (a), D3 (a)). The
# workspace's L1_plan/stageL1f_design.md §1. test/core_lang/test_stack_limit.jl — on every term type:
#   * a differential against swipl run with the SAME limit (1 MiB, `stack_limit` set by a directive): length/2,
#     functor/3, =../2, findall/3 (the answers' cells, and the list's own: 62500 answers, no call after), copy_term/2, a recursion building a list, an integer too big — over the limit and
#     under it; the FORMAL compared (`resource_error(stack)`), the context not (swipl's is a dict);
#   * a built-in with no check of its own (copy_term/2), then a call to a clause that lays nothing out: only the
#     per-call check (normal_call) raises it;
#   * the handler runs and the stacks are usable after the raise (catch/3, then a list built) — also for a findall
#     whose ANSWERS alone exceed the limit (audit D-0032);
#   * a term laid out by a clause body itself, no call in between (B_RLIST: upstream's `ENSURE_GLOBAL_SPACE`, D-0032):
#     the error raised there, inside the catch/3 — a check at the next call alone would raise it outside;
#   * the context pinned: the atom `stack_overflow` (DIVERGES: swipl's dict — on the divergence list);
#   * white-box: after the raise is caught `gTop` is back below the limit; the boundary of `ensureGlobalSpace` exact;
#     while an exception is processed the limit is not applied.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"1 MiB in words: swipl's `stack_limit` of 1048576 bytes."
const _SL_LIMIT = 1_048_576 ÷ 8

"A list of 2500 atoms, written out: laid out by the clause body itself (B_RLIST), no call in between."
const _SL_INLINE = "[" * join(fill("a", 2500), ",") * "]"

const _SL_PROG = """
btw(L, H, L) :- L =< H.
btw(L, H, X) :- L < H, L1 is L + 1, btw(L1, H, X).
mk(0, []) :- !.
mk(N, [N|T]) :- N1 is N - 1, mk(N1, T).
tlen_big(ok) :- length(_, 1000000).
tlen_ok(ok) :- length(_, 1000).
tfun_big(ok) :- functor(_, f, 1000000).
tfun_ok(ok) :- functor(_, f, 100).
tuniv_big(ok) :- length(L, 35000), _ =.. [f|L].
tuniv_ok(ok) :- length(L, 100), _ =.. [f|L].
tbag_big(N) :- findall(T, (btw(1, 10, _), functor(T, f, 20000)), L), length(L, N).
tbag_list(ok) :- findall(x, (btw(1, 250, _), btw(1, 250, _)), _).
tbag_ans(E-N) :- catch(findall(T, (btw(1, 10, _), functor(T, f, 20000)), _), error(E, _), true),
    mk(1000, L), length(L, N).
tbag_ans_last(ok) :- findall(T, (btw(1, 10, _), functor(T, f, 20000)), _).
tinl(L, X) :- length(L, 42000), X = $(_SL_INLINE).
tinline(R) :- catch(tinl(_, _), error(E, _), true), ( var(E) -> R = none ; R = E ).
tbag_ok(N) :- findall(T, (btw(1, 2, _), functor(T, f, 2000)), L), length(L, N).
tcopy_big(N) :- length(L, 25000), copy_term(L, C), length(C, N).
nop.
tcopy_nop(ok) :- length(L, 25000), copy_term(L, _), nop.
tmk_big(N) :- mk(100000, L), length(L, N).
tmk_ok(N) :- mk(1000, L), length(L, N).
thandler(E-N) :- catch(length(_, 1000000), error(E, _), true), mk(1000, L), length(L, N).
tint_big(ok) :- _ is 2**10000000.
tint_ok(ok) :- 1 =:= 2**1000 - 2**1000 + 1.
tctx(C) :- catch(length(_, 1000000), error(_, C), true).
"""

const _SL_GOALS = (
    "tlen_big", "tlen_ok", "tfun_big", "tfun_ok", "tuniv_big", "tuniv_ok", "tbag_big",
    "tbag_list", "tbag_ans", "tbag_ans_last", "tinline", "tbag_ok",
    "tcopy_big", "tcopy_nop", "tmk_big", "tmk_ok", "thandler", "tint_big", "tint_ok"
)

"A database holding `_SL_PROG`, its limit `_SL_LIMIT`."
function _sl_db()::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "sl.pl")
    write(f, _SL_PROG)
    st, _, _ = LK.load_file!(db.gd, db.ld, f)
    @assert st === :ok "test_stack_limit: the program did not load: $st"
    db.ld.stacks_limit = _SL_LIMIT
    return db
end

@testset "the global-stack limit, as swipl with the same limit" begin
    goals = _R[_rf(n, _rv(60)) for n in _SL_GOALS]
    db = _sl_db()
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    over = "exception(resource_error(stack)) det"
    @test count(==(over), ours) == 10                      # every *_big, tbag_list, tbag_ans_last, tcopy_nop
    @test "tbag_ans(-(resource_error(stack),1000)) det" in ours   # D-0032: the answers alone; the handler ran
    @test "tinline(resource_error(stack)) det" in ours     # D-0032: laid out inline, caught INSIDE the catch
    @test "thandler(-(resource_error(stack),1000)) det" in ours
    if _R_SWIPL
        theirs = _rswipl(
            Tuple{_R, Union{Nothing, _R}}[], goals;
            extra=":- set_prolog_flag(stack_limit, 1048576).\n" * _SL_PROG
        )
        @test ours == theirs
        ours == theirs || @info "stack-limit differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "the context pinned: the atom stack_overflow (swipl: a dict)" begin
    db = _sl_db()
    # DIVERGES (L1f f2, D-0029 D2 (a)): swipl answers `tctx(stack_overflow{choicepoints:…, …})`
    @test _rlines(db, _R[_rf("tctx", _rv(60))]) == ["tctx(stack_overflow) det", "end"]
end

@testset "white-box: below the limit after the raise; the boundary; no limit while an exception is processed" begin
    db = _sl_db()
    ld = db.ld
    @test _rlines(db, _R[_rf("thandler", _rv(60))]) ==
        ["thandler(-(resource_error(stack),1000)) det", "end"]
    @test ld.gTop <= ld.stacks_limit && !ld.exception_processing && !ld.outofstack
    LK.PL_open_foreign_frame(ld)
    room = ld.stacks_limit - LK._stacks_in_use(ld, 0)   # (D-0036: the three stacks)
    @test LK.ensureGlobalSpace(ld, room)                   # exactly at the limit: room
    @test !ld.exception_processing
    @test !LK.ensureGlobalSpace(ld, room + 1)              # one cell over: the overflow
    @test ld.exception_processing && ld.outofstack
    r = LK.resolve_term(ld, LK.slotValue(ld, ld.exception_bin + 1))
    @test _rcanonical(r) == "error(resource_error(stack),stack_overflow)"
    @test LK.ensureGlobalSpace(ld, room + 1_000_000)       # processing: the handler's own cells
end

# ── D-0032: the head instructions' own checks, at the exact boundary ──────────────────────────────
# A head that BINDS an unbound argument lays the term out itself (H_RFUNCTOR, H_RLIST, H_LIST_FF in read
# mode on a variable: 3 cells each here); write mode jumps to B_RFUNCTOR/B_RLIST, so only this boundary
# reaches the H_ checks. White-box (swipl's limit covers all its stacks: no exact boundary to compare).
"Call `goal/n` on fresh arguments with `room` cells left: (status, cells used)."
function _sl_head_call(db::_RDB, goal::Symbol, n::Int, room::Int)
    gd, ld = db.gd, db.ld
    proc = LK.lookupProcedure(lk_sym(_R, goal), n, db.user)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, n)
    lim = ld.stacks_limit
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + room   # (D-0036: the three stacks)
    g0 = ld.gTop
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    used = ld.gTop - g0
    LK.PL_close_query(ld, qid)
    ld.stacks_limit = lim
    LK.PL_discard_foreign_frame(ld, fid)
    return rc, used
end

@testset "D-0032: H_RFUNCTOR, H_RLIST, H_LIST_FF binding a variable — exactly at the limit, one cell over" begin
    db = _RDB()
    f = joinpath(mktempdir(), "hd.pl")
    write(f, "hr([a]).\nhf(f(a, b)).\nhff([X|Y], X, Y).\n")
    @test LK.load_file!(db.gd, db.ld, f)[1] === :ok
    for (g, n) in ((:hr, 1), (:hf, 1), (:hff, 3))
        @test _sl_head_call(db, g, n, 3) == (LK.PL_S_LAST, 3)       # room for its 3 cells
        @test _sl_head_call(db, g, n, 2) == (LK.PL_S_EXCEPTION, 0)  # one cell short: raised, nothing laid
    end
end

# ── D-0036: ONE limit over the three stacks (pl-gc.c grow_stacks: `tsize + gsize + lsize > limit`) ──────
# The local stack by its size, the global by its use, the trail by its entries (`_stacks_in_use`). Each row
# fails under the old per-stack checks: the global alone against the whole limit, the local alone likewise.
@testset "D-0036: one limit over the local stack, the global stack and the trail" begin
    db = _sl_db()
    ld = db.ld
    t = LK.PL_new_term_ref(ld)                         # a cell older than the frame below: its binding
    LK.PL_open_foreign_frame(ld)                       # is trailed, so the trail term is not 0
    @test LK.PL_unify_atom(ld, t, lk_sym(_R, :a))
    @test length(ld.trail) >= 1                        # (the guard: the trail counts in this row)
    used = (ld.lMax + ld.local_spare) + ld.gTop + length(ld.trail)
    ld.stacks_limit = used + 10
    @test LK.ensureGlobalSpace(ld, 10)                 # the three stacks exactly at the limit
    @test !ld.exception_processing
    @test !LK.ensureGlobalSpace(ld, 11)                # one cell over the SUM (the global alone: far below)
    r = LK.resolve_term(ld, LK.slotValue(ld, ld.exception_bin + 1))
    @test _rcanonical(r) == "error(resource_error(stack),stack_overflow)"

    db2 = _sl_db()                                     # the local stack's share: what the others leave
    ld2 = db2.ld
    LK.PL_open_foreign_frame(ld2)
    LK.allocGlobalCells!(ld2, 50_000)                  # a global stack well above the local stack's size
    size0 = ld2.lMax + ld2.local_spare
    want = ld2.lTop + size0 + ld2.local_def_spare      # growStacks!: the request and the spare above it
    ld2.stacks_limit = want + ld2.gTop + length(ld2.trail) - 1   # the local stack's share: 1 short
    @test want <= ld2.stacks_limit                     # (alone it would fit: the old check let it grow)
    @test !LK.ensureLocalSpace(ld2, size0)
    @test ld2.lMax + ld2.local_spare == size0          # nothing grew
end
