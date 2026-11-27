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
#     the error raised there, inside the catch/3 — a check at the next call alone would raise it outside. G1-FIX-8: the
#     `tinline` row does NOT reach B_RLIST any more, in either system: swipl raises already INSIDE length/2 (its stack shows
#     `'$length'(_,42000)`), and the kernel, since the collector is live (chunk 8), raises nothing: a KNOWN DIFFERENCE (below);
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

"A list of 2500 atoms, written out: laid out by the clause body itself (B_RLIST), no call in between (the `tinline` row never reaches it: see `_SL_KNOWN_DIFF`)."
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
tcopy_in(R) :- length(L, 25000), catch(copy_term(L, _), error(E, _), true), ( var(E) -> R = none ; R = E ).
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
    "tcopy_big", "tcopy_nop", "tcopy_in", "tmk_big", "tmk_ok", "thandler", "tint_big",
    "tint_ok"
)

"""
KNOWN DIFFERENCE (G1-FIX-8, audit D-0969 (2) option (b); owner G1-D): `tinline` (`length(L, 42000)`, then `X = [a x 2500]`).
  swipl 10.1.20:  `tinline(resource_error(stack)) det` — raised INSIDE `'\$length'(_,42000)`, not at the list.
  kernel (this pin): `tinline(none) det` — `length(_, 42000)` = 126000 words fits (4884 in use after a collection + 126000 <= 131072), the inline
  list then reaches the ALLOW_GC site, the collector frees `L` (dead: the rest of `tinl` never names it) and nothing overflows.
BOTH numbers, measured (largest N for `length(_, N)` under 1 MiB after a collection): swipl 26658 (79974 words, 61 % of the limit), kernel 42028 (126084 words, 96 %).
CAUSE: swipl's `grow_stacks` keeps a quarter free (pl-gc.c:5369-5402, GLOBAL_TRAIL_RATIO 6, `nextStackSize` :5271-5290 at the pin 18168e62); the kernel's limit is
use + spares <= limit (src/pl-gc.jl:146-162, the KEPT G1-C5 DIVERGES; src/pl-alloc.jl:163-165/183).
THIS PIN DOES NOT CLOSE THE LIMIT ARITHMETIC: the rows of test_stack_overflow_swipl.jl, test_local_stack.jl and the q10 stack-limit rows agree with swipl only
where they were measured to; no other length is claimed to overflow at the same N in both systems.
CHECKLIST (G1-D, evidence/R2/l1c_checklist.md row 4): port upstream's limit arithmetic (grow_stacks, GLOBAL_TRAIL_RATIO, nextStackSize), delete this table and
its guard; the row must then answer swipl's line. `_SL_SWIPL` stays swipl's (the live check compares it to swipl); only the kernel comparison reads `_SL_KNOWN_DIFF`.
"""
const _SL_KNOWN_DIFF = Dict{String, String}("tinline" => "tinline(none) det")

"swipl's answers for the known-difference rows (the live differential compares them with swipl's own)."
const _SL_SWIPL = Dict{String, String}("tinline" => "tinline(resource_error(stack)) det")

"`lines` (an answer list of `_rlines`: one line per goal, then `end`) with every known-difference goal's line replaced by `table[goal]`."
function _sl_swap(lines::Vector{String}, table::Dict{String, String})::Vector{String}
    out = copy(lines)
    for (g, _) in table
        i = findfirst(l -> startswith(l, g * "("), out)
        i === nothing || (out[i] = table[g])
    end
    return out
end

"A database holding `_SL_PROG`, its limit `_SL_LIMIT`."
function _sl_db()::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "sl.pl")
    write(f, _SL_PROG)
    st, _ = LK.load_file!(db.gd, db.ld, f)
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
    @test _SL_KNOWN_DIFF["tinline"] in ours                # KNOWN DIFFERENCE (G1-FIX-8, see `_SL_KNOWN_DIFF`): the kernel raises nothing, swipl does
    @test !(_SL_SWIPL["tinline"] in ours)
    @test "thandler(-(resource_error(stack),1000)) det" in ours
    @test "tcopy_in(resource_error(stack)) det" in ours     # f1b: raised INSIDE copy_term, caught there
    if _R_SWIPL
        theirs = _rswipl(
            Tuple{_R, Union{Nothing, _R}}[], goals;
            extra=":- set_prolog_flag(stack_limit, 1048576).\n" * _SL_PROG
        )
        ours_sw = _sl_swap(ours, _SL_SWIPL)                 # the known-difference rows read as swipl's pin, then compared with swipl live
        @test ours_sw == theirs
        ours_sw == theirs || @info "stack-limit differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "the known-difference table (no swipl needed): every key is a goal, the kernel's line differs from swipl's" begin
    @test Set(keys(_SL_KNOWN_DIFF)) == Set(keys(_SL_SWIPL)) && !isempty(_SL_KNOWN_DIFF)
    for (g, line) in _SL_KNOWN_DIFF
        @test g in _SL_GOALS
        @test startswith(line, g * "(") && startswith(_SL_SWIPL[g], g * "(")
        @test line != _SL_SWIPL[g]                          # equal to swipl's: not a difference, delete the entry
    end
    # must-fail: a swapped answer list is not the kernel's
    @test _sl_swap(["x det", "tinline(none) det", "end"], _SL_SWIPL) ==
        ["x det", "tinline(resource_error(stack)) det", "end"]
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
    @test ld.gTop <= ld.stacks_limit && !ld.exception_processing &&
        ld.outofstack === nothing
    LK.PL_open_foreign_frame(ld)
    room = ld.stacks_limit - LK._stacks_in_use(ld, 0)   # (D-0036: the three stacks)
    @test LK.ensureGlobalSpace(ld, room)                   # exactly at the limit: room
    @test !ld.exception_processing
    @test !LK.ensureGlobalSpace(ld, room + 1)              # one cell over: the overflow
    @test ld.exception_processing && ld.outofstack === :global
    r = lk_answer(ld, ld.exception_bin)
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
        # one cell short: raised, the head lays nothing — the cells used are the ball's own (f3b-1: five
        # global cells, `error(resource_error(stack), stack_overflow)`: error/2 is 3, resource_error/1 is 2)
        # allow-docstring-interp: line 45's `$(_SL_INLINE)` is a Prolog source string built on purpose, not a docstring
        @test _sl_head_call(db, g, n, 2) == (LK.PL_S_EXCEPTION, 5)
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
    used = LK._stacks_in_use(ld, 0)                    # (the three stacks with their spares, f1b)
    @test used ==
        (ld.lMax + ld.local_spare) + (ld.gTop + ld.global_spare) +
          (length(ld.trail) + ld.trail_spare)
    ld.stacks_limit = used + 10
    @test LK.ensureGlobalSpace(ld, 10)                 # the three stacks exactly at the limit
    @test !ld.exception_processing
    @test !LK.ensureGlobalSpace(ld, 11)                # one cell over the SUM (the global alone: far below)
    r = lk_answer(ld, ld.exception_bin)
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

# ── L1f f1a: findall's two limits, as upstream's pl-bag.c ─────────────────────────────────────────
# `'$add_findall_bag'` raises once the answers' cells and their list (`gsize + solutions*3`) pass the
# limit (swipl 10.1.18 at 1 MiB: `findall(x, repeat, _)` raises resource_error(stack) from
# '$add_findall_bag'/1, probed 2026-10-19); `'$collect_findall_bag'` ensures ALL of it before the first
# answer is copied (`ensureGlobalSpace(bag->gsize + solutions*3)`): no answer laid past the limit.
_sl_ctx() = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
_sl_bag!(ld) =
    push!(ld.bags, LK.findall_bag{_R}(LK.FINDALL_MAGIC, false, 0, 0, 0, LK.record{_R}[]))

@testset "f1a: the answers' limit at '\$add_findall_bag' — exact" begin
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ld.stacks_limit = 3 * 43690                         # the 43691st atomic answer is one over
    _sl_bag!(ld)
    t = LK.PL_new_term_ref(ld)
    ld.slots[t + 1] = LK._atom_word!(ld, _rs("x"))
    n = 0
    while !ld.exception_processing && n < 50000
        n += 1
        @assert LK.add_findall_bag(ld, t, 0) == LK.FFALSE
    end
    @test n == 43691 && ld.bags[end].solutions == 43691 && ld.outofstack === :global
    r = lk_answer(ld, ld.exception_bin)
    @test _rcanonical(r) == "error(resource_error(stack),stack_overflow)"
    # a compound answer counts its cells: f(a) is 2, so 5 words per answer
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ld.stacks_limit = 5 * 100
    _sl_bag!(ld)
    t = LK.PL_new_term_ref(ld)
    p = LK._alloc_compound!(
        ld, LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 1), 1
    )
    ld.gstack[p + 1] = LK._atom_word!(ld, _rs("a"))
    ld.slots[t + 1] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    n = 0
    while !ld.exception_processing && n < 1000
        n += 1
        LK.add_findall_bag(ld, t, 0)
    end
    @test n == 101 && ld.bags[end].gsize == 2 * 101
end

@testset "f1a: '\$collect_findall_bag' ensures every answer's cells first — none laid past the limit" begin
    for extra in (-1, 0)
        db = _sl_db()
        ld = db.ld
        LK.PL_open_foreign_frame(ld)
        _sl_bag!(ld)
        t = LK.PL_new_term_ref(ld)
        p = LK._alloc_compound!(
            ld, LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 2000), 2000
        )
        ld.slots[t + 1] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
        for _ in 1:5
            LK.add_findall_bag(ld, t, 0)
        end
        @test !ld.exception_processing && ld.bags[end].gsize == 5 * 2001
        a = LK.PL_new_term_refs(ld, 2)
        ld.slots[a + 2] = ld.atom_nil_w
        # the cell of collect's `answer` reference (PL_copy_term_ref takes none), then room for exactly
        # 5*2001 + 5*3 cells (or one fewer)
        g0 = ld.gTop
        probe = LK.PL_new_term_ref(ld)
        refcells = ld.gTop - g0
        g0 = ld.gTop
        ld.stacks_limit = LK._stacks_in_use(ld, 0) + refcells + 5 * 2001 + 5 * 3 + extra
        g1 = ld.gTop
        rc = LK.pl_collect_findall_bag2_va(ld, a, 2, _sl_ctx())
        if extra < 0
            @test rc == LK.FFALSE && ld.exception_processing
            # no answer laid (the overshoot is 0): what grew is the reference's cell and the ball's five
            # (L1f f3b-1: outOfStack! lays error(resource_error(stack), Ctx) on the global stack, as upstream)
            @test ld.gTop - g1 <= refcells + 5
        else
            @test rc == LK.FTRUE && !ld.exception_processing &&
                isempty(ld.bags[end].answers)
            @test ld.gTop <= ld.stacks_limit
        end
    end
end

# ── L1f f1b: copy_term's space — allocGlobalNoShift in the copy, copy_term_refs' loop ──────────────────
@testset "f1b: copy_term_refs at the exact limit: room for the copy, one cell fewer raises" begin
    for (room_less, share) in ((0, true), (1, true), (0, false), (1, false))
        db = _sl_db()
        ld = db.ld
        # G1-FIX-8 (audit D-0969 (1)): collect BEFORE the limit is taken. The loader leaves ~1250 dead cells; with the collector
        # live (chunk 8) makeMoreStackSpace reclaims them (pl-copyterm.c:847 -> pl-gc.c:4622-4672 garbageCollect, then the retry),
        # so the premise "one cell fewer raises" holds only when nothing is reclaimable. The new testset below keeps the garbage.
        @test LK.garbageCollect(ld, Int(LK.GC_USER); vmi_state_of=LK.get_vmi_state) ==
            LK.BOOLEX_TRUE
        LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_ref(ld)
        p = LK.allocGlobalCells!(ld, 30)                    # [_,…,_]: ten list cells, unbound heads
        for i in 0:9
            ld.gstack[p + 3i] = ld.functor_dot2
            ld.gstack[p + 3i + 2] = if i < 9
                LK.consPtr(p + 3i + 3, LK.TAG_COMPOUND | LK.STG_GLOBAL)
            else
                ld.atom_nil_w
            end
        end
        ld.slots[t + 1] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
        c = LK.PL_new_term_ref(ld)
        g0 = ld.gTop
        ld.stacks_limit = LK._stacks_in_use(ld, 0) + 1 + 30 - room_less   # dest + 10 cells × 3
        ok = LK.copy_term_refs(
            ld, t, c, LK.cp_options(share ? LK.COPY_SHARE | LK.COPY_ATTRS : LK.COPY_ATTRS)
        )
        if room_less == 0
            @test ok && !ld.exception_processing && ld.gTop - g0 == 31
        else
            # the partial copy discarded (a whole one is 31 cells): what grew is to's fresh cell and the
            # ball's five (L1f f3b-1: outOfStack! lays the ball on the global stack, as upstream)
            @test !ok && ld.exception_processing && ld.gTop - g0 < 10
            @test LK._deref_loc(ld, -(c + 1))[1] == LK.DU_CELL     # PL_put_variable(to)
            r = lk_answer(ld, ld.exception_bin)
            @test _rcanonical(r) == "error(resource_error(stack),stack_overflow)"
        end
    end
end

# G1-FIX-8 (audit D-0969 (1)): the old reading kept covered. The garbage the loader left is IN PLACE (no collection first),
# the limit is one cell short of the copy: upstream's copy_term_refs gets no space from the copy (rc < 0), calls
# makeMoreStackSpace(GLOBAL_OVERFLOW, ALLOW_SHIFT|ALLOW_GC) (pl-copyterm.c:847 at the pin 18168e62), whose garbageCollect
# (pl-gc.c:4622-4672) reclaims the dead cells, and the loop RETRIES: the copy fits, no exception. Measured (SL-DIAG): ok=true,
# gTop 1302 -> 82, one collection. Mutant SL1-R1 (tools/mutants/SL1.py: copy_term_refs without ALLOW_GC) must fail this row.
@testset "f1b: copy_term_refs one cell short, garbage left in place: a collection, the retry fits" begin
    for share in (true, false)
        db = _sl_db()
        ld = db.ld
        LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_ref(ld)
        p = LK.allocGlobalCells!(ld, 30)                    # [_,…,_]: ten list cells, unbound heads
        for i in 0:9
            ld.gstack[p + 3i] = ld.functor_dot2
            ld.gstack[p + 3i + 2] = if i < 9
                LK.consPtr(p + 3i + 3, LK.TAG_COMPOUND | LK.STG_GLOBAL)
            else
                ld.atom_nil_w
            end
        end
        ld.slots[t + 1] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
        c = LK.PL_new_term_ref(ld)
        g0 = ld.gTop
        ld.stacks_limit = LK._stacks_in_use(ld, 0) + 1 + 30 - 1   # one cell fewer than the copy needs
        c0 = ld.gc.stats.totals.collections
        ok = LK.copy_term_refs(
            ld, t, c, LK.cp_options(share ? LK.COPY_SHARE | LK.COPY_ATTRS : LK.COPY_ATTRS)
        )
        @test ok && !ld.exception_processing
        @test ld.gc.stats.totals.collections == c0 + 1          # the retry came from a collection
        @test ld.gTop < g0                                      # the dead cells below were reclaimed (SL-DIAG: 1302 -> 82)
    end
end

# ── L1f f1b: the global and trail spares (pl-setup.c init_stack, pl-alloc.c enableSpareStack, trim_stack;
# audit D-0042) — reserves in the one limit, released when an overflow leaves less room than they hold,
# reserved again when the exception is cleared ───────────────────────────────────────────────────────────
@testset "f1b: the spares — counted, released near the limit, restored after" begin
    db = _sl_db()
    ld = db.ld
    @test ld.global_spare == ld.global_def_spare == LK.GLOBAL_SPARE == 512
    @test ld.trail_spare == ld.trail_def_spare == LK.TRAIL_SPARE == 256
    @test LK._stacks_in_use(ld, 7) ==
        (ld.lMax + ld.local_spare) + (ld.gTop + 7 + 512) + (length(ld.trail) + 256)
    LK.PL_open_foreign_frame(ld)
    # a raise with room to spare: the spares stay (room >= def_spare)
    room = ld.stacks_limit - LK._stacks_in_use(ld, 0)
    @test room > 1000 && !LK.ensureGlobalSpace(ld, room + 1)
    @test ld.global_spare == 512 && ld.trail_spare == 256
    LK.PL_clear_exception(ld)
    # a raise 10 cells from the limit: both released, and reserved again by the clear (trimStacks)
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + 10
    @test !LK.ensureGlobalSpace(ld, 11)
    # the global spare released (room 10 < 512); the trail's then has 522 words of room (>= 256): kept
    @test ld.global_spare == 0 && ld.trail_spare == 256 && ld.exception_processing
    LK.PL_clear_exception(ld)
    @test ld.global_spare == 512 && ld.trail_spare == 256 && !ld.exception_processing
    # upstream's trim_stack: a reserve the room cannot hold is cut to the room, and to 0 if there is none
    # (`room < reduce`; pl-setup.c at the pin, src/pl-setup.jl `trim_stack!`) — room 100 takes 100, no room (past the
    # limit) takes nothing (until the newer pin the whole spare was taken back, 512: D-0049).
    # Written by hand: white-box, these are fields of the C stack structures, which swipl cannot be asked about.
    ld.global_spare = 0
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + 100
    LK.trim_stack_global!(ld)
    @test ld.global_spare == 100
    ld.global_spare = 0
    ld.stacks_limit = LK._stacks_in_use(ld, 0) - 100
    LK.trim_stack_global!(ld)
    @test ld.global_spare == 0
end

# ── L1f f1b: copy_exception!'s three fallbacks (pl-fli.c) — WHITE-BOX: a ball copy fails only before
# `exception_processing` is set (PL_raise_exception sets it first; upstream needs memory exhaustion — swipl
# cannot be provoked from Prolog), so copy_exception! is called directly ──────────────────────────────────
"A ball laid out on cells: `name(a, [_,…,_])`, the list of `n` cells; its term reference."
function _sl_ball(ld, name, n)
    t = LK.PL_new_term_ref(ld)
    p = LK.allocGlobalCells!(ld, 3 * n)
    for i in 0:(n - 1)
        ld.gstack[p + 3i] = ld.functor_dot2
        ld.gstack[p + 3i + 2] = if i < n - 1
            LK.consPtr(p + 3i + 3, LK.TAG_COMPOUND | LK.STG_GLOBAL)
        else
            ld.atom_nil_w
        end
    end
    b = LK.allocGlobalCells!(ld, 3)
    ld.gstack[b] = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs(name)), 2)
    ld.gstack[b + 1] = LK._atom_word!(ld, _rs("a"))
    ld.gstack[b + 2] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    ld.slots[t + 1] = LK.consPtr(b, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    return t
end
_sl_bin(ld, bin) = _rcanonical(lk_answer(ld, bin))

@testset "f1b: copy_exception!'s fallbacks — the context dropped, the global overflow, abort" begin
    # the copy fits: the ball itself
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ex, bin = _sl_ball(ld, "error", 3), LK.PL_new_term_ref(ld)
    @test LK.copy_exception!(ld, ex, bin) &&
        _sl_bin(ld, bin) == "error(a,[_,_,_])"
    # (1) error(F, Big) that does not fit: error(F, _)
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ex, bin = _sl_ball(ld, "error", 100), LK.PL_new_term_ref(ld)
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + 10
    @test LK.copy_exception!(ld, ex, bin) && _sl_bin(ld, bin) == "error(a,_)" &&
        ld.exception_processing
    # (2) a ball that is no error/2: error(resource_error(stack), global) in the spare (2 cells of it)
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ex, bin = _sl_ball(ld, "big", 100), LK.PL_new_term_ref(ld)
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + 3
    @test LK.copy_exception!(ld, ex, bin)
    @test _sl_bin(ld, bin) == "error(resource_error(stack),global)" &&
        ld.global_spare == 512 - 2
    # (3) no spare left: abort
    db = _sl_db()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    ex, bin = _sl_ball(ld, "big", 100), LK.PL_new_term_ref(ld)
    ld.global_spare = 0
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + 3
    @test LK.copy_exception!(ld, ex, bin) && _sl_bin(ld, bin) == "abort"
end

# ── KNOWN DIFFERENCE, pinned white-box (audit D-0033/D-0034; L1 checklist, group (D) beside the term-reference
# cell): a void argument passed on is a GLOBAL cell here — a slot is never an unbound variable (L1c) — where
# swipl's L_VOID sets a LOCAL frame cell. So a long deterministic recursion passing `_` lays one global cell
# per call and meets the limit:
#   kernel:       tlv(resource_error(stack))
#   swipl 10.1.18: tlv(ok)   (stack_limit 1048576, probed 2026-10-19)
# It goes when the boundary falls (f3/G1: the global stack collected, or a slot that can be unbound).
const _SL_LV = """
lv(0, _) :- !.
lv(N, _) :- N1 is N - 1, lv(N1, _).
tlv(R) :- catch(lv(200000, _), error(E, _), true), ( var(E) -> R = ok ; R = E ).
"""
@testset "KNOWN DIFFERENCE (D-0034): void arguments are global cells — a long recursion meets the limit" begin
    db = _RDB()
    f = joinpath(mktempdir(), "lv.pl")
    write(f, _SL_LV)
    st, _ = LK.load_file!(db.gd, db.ld, f)
    @assert st === :ok
    db.ld.stacks_limit = _SL_LIMIT
    @test _rlines(db, _R[_rf("tlv", _rv(60))]) == ["tlv(resource_error(stack)) det", "end"]
end
