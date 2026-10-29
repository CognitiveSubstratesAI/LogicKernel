# ORIGINAL: the L1c plan's condition 3 (user, 2026-10-15) — the cold adapters are guarded MECHANICALLY: a
# hot path falling back to the term boundary fails THIS test, not just an allocation count. Upstream
# has no counterpart (its VM has no term boundary). test/core_lang/test_zero_exports.jl — on every
# term type: one call of each of swipl's benchmark programs nreverse and qsort (bench/programs/*.pl,
# as tools/bench.jl runs them) leaves the boundary's counter unchanged:
#   * `cold_imports` — a term copied onto the stack (`_compound_word!`; the deep index's boundary
#     descent included, sub-commit 5);
# and a small program that compares (==, \==, compare/3 over lists on the stack) does the same. (Until
# L1f f3 also `cold_exports` — a compound read as a term, `cold_vars` — a cell's variable read as a term,
# and `cold_pairs` — a pair the cell compare decided as terms: they went with the keyed variables.)
# Since L1f F3B, one program per group of the plan (the workspace's L1_plan/stageL1f_design.md §3), at the
# end of the file: f3b-1's put of a caller's goal; f3b-2's clause/2.
# The first call builds the predicates' indexes and supervisors; the asserted call is the second (and
# the first's counts are reported).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _ZT = lk_term_type(Union{Int64, Float64, String})

"A database with bench/programs/`name`.pl loaded, and its engine."
function _zt_load(name::String)
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    st, ball, msgs = LK.load_file!(
        gd, ld, joinpath(@__DIR__, "..", "..", "bench", "programs", name * ".pl")
    )
    @test st === :ok && isempty(msgs)
    return gd, ld
end

"Run `name/0` once through the query API; the return code."
function _zt_run(gd, ld, name::Symbol)::Int
    proc = LK.lookupProcedure(lk_sym(_ZT, name), 0, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, 0)
    rc = LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return rc
end

# THE ZERO, LOCKED (user, 2026-10-16): one warm call of nreverse/0 and qsort/0 allocates NOTHING. The
# call is one function of concrete arguments (`_zt_call`, as tools/bench.jl's `_vm_nreverse`) measured
# by `@allocated` from inside another function (`_zt_allocated`), so no script-level dispatch — the
# runtime method lookup a profile at top level shows — can count.
"One call of `proc/0` through the query API, its foreign frame discarded."
function _zt_call(gd, ld, proc)::Int
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, 0)
    rc = LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return rc
end
"The bytes one WARM call of `proc/0` allocates (two calls first: indexes, supervisors, pools)."
function _zt_allocated(gd, ld, proc)::Int
    _zt_call(gd, ld, proc)
    _zt_call(gd, ld, proc)
    return @allocated _zt_call(gd, ld, proc)
end

_zt_counts(ld) = ld.cold_imports        # (the export/variable/pair meters went with the keyed variables, f3)

@testset "nreverse, qsort and poly_10 make no cold export, import or variable read" begin
    for name in (:nreverse, :qsort, :poly_10)
        gd, ld = _zt_load(String(name))
        c0 = _zt_counts(ld)
        @test _zt_run(gd, ld, name) == LK.PL_S_TRUE         # the first call: indexes, supervisors
        c1 = _zt_counts(ld)
        @info "$name: the first call's boundary traffic (imports)" c1 - c0
        @test _zt_run(gd, ld, name) == LK.PL_S_TRUE
        c2 = _zt_counts(ld)
        @test c2 == c1                                      # THE CONDITION: zero
        c2 == c1 || @info "$name: the second call's boundary traffic" c2 - c1
    end
end
# THE PIN PER TERM TYPE (user, 2026-10-16): the reference type allocates NOTHING. The alternative
# types are abstract (`AltTerm{H}`), so a term value held in a typed container is re-boxed and the
# VM's argument-pointer register (`argp_t{T}`, a term field) is boxed when passed on — and what is
# left is EXACTLY the small integers' traffic, which grows with n (scaling probe, 2026-10-16:
# nreverse 30/60 → 1440/2880, qsort 50/100 → 10400/24032; Profile.Allocs sites):
#   * B_SMALLINT stores the integer literal through `_argp_store!`: its ARGP boxed (32 bytes) and
#     the literal re-boxed into the value table (`_vword!`, 16) — one per list element: nreverse
#     30 × 48 = 1440, qsort 50 × 48 = 2400;
#   * qsort's `X =< Y` arguments: each integer copied into a slot re-boxed into `slot_values`
#     (`_slot_link!` → `_slot_store!`, 16) — 500 × 16 = 8000; 2400 + 8000 = 10400.
# All of it was a small integer on the value table: L1d step 4 (tagged integer words) removed it —
# MEASURED 2026-10-17 on step 4's tree: alt and alt_interned 0 / 0 bytes per warm call, as the reference
# type (Profile.Allocs: no LogicKernel site left). Constant per call: nothing (the `[]` word and its
# index key came off the term path in L1c-6).
# poly_10 joined the pins with arithmetic on cells (L1d §3e, MEASURED 2026-10-18): 0 bytes on every type,
# where its is/2 exported each expression and read each variable as a term before (100412 allocations).
"The bytes one warm call of `name` allocates, pinned per term type (above): zero on every type since L1d step 4."
const _ZT_ALLOC_PIN = Dict(
    "reference" => Dict(:nreverse => 0, :qsort => 0, :poly_10 => 0),
    "alt" => Dict(:nreverse => 0, :qsort => 0, :poly_10 => 0),
    "alt_interned" => Dict(:nreverse => 0, :qsort => 0, :poly_10 => 0)
)
@testset "a warm call of nreverse, qsort and poly_10 allocates exactly its pin (@allocated)" begin
    for name in (:nreverse, :qsort, :poly_10)
        gd, ld = _zt_load(String(name))
        proc = LK.lookupProcedure(lk_sym(_ZT, name), 0, LK.MODULE_user(gd))
        @test _zt_call(gd, ld, proc) == LK.PL_S_TRUE
        a = _zt_allocated(gd, ld, proc)
        pin = _ZT_ALLOC_PIN[LK_TERM_IMPL][name]
        a == pin || @info "$name: a warm call allocates" LK_TERM_IMPL a pin
        @test a == pin
    end
end

# eq_loop(N): N times build two equal lists and a third, and compare them (==, \==, compare/3)
const _ZT_EQ = """
eq_loop(0) :- !.
eq_loop(N) :- L1 = [1,2,f(a),3], L2 = [1,2,f(a),3], L3 = [1,2,f(b),3],
    L1 == L2, L1 \\== L3, compare(O, L1, L3), O == (<), N1 is N - 1, eq_loop(N1).
eq_top :- eq_loop(50).
"""

@testset "a comparing program makes no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "eq_loop.pl")
    write(f, _ZT_EQ)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    @test _zt_run(gd, ld, :eq_top) == LK.PL_S_TRUE
    c1 = _zt_counts(ld)
    @test _zt_run(gd, ld, :eq_top) == LK.PL_S_TRUE
    @test _zt_counts(ld) == c1
end

# ar_loop(N): N times evaluate expressions over values bound on the cells — is/2 (a tagged integer, a
# float past it, `[X]`), the comparisons and A_ADD_FC (`N1 is N - 1`) — L1d, arithmetic on cells (the
# workspace's L1_plan/stageL1d_design.md §3e): before it, every `is/2` exported its expression and read
# each variable as a term (poly_10: 19080 exports and 28615 variable reads per warm call).
const _ZT_AR = """
ar_loop(0) :- !.
ar_loop(N) :- A is N * 2 + 1, B is A - N, B > 0, C is (A + B) * (A - B), C >= 0,
    D is [97] + 1.5, D > A - 1000, E is D * 2, E =:= D + D, N1 is N - 1, ar_loop(N1).
ar_top :- ar_loop(50).
"""

@testset "an arithmetic program makes no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "ar_loop.pl")
    write(f, _ZT_AR)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    @test _zt_run(gd, ld, :ar_top) == LK.PL_S_TRUE
    c1 = _zt_counts(ld)
    @test _zt_run(gd, ld, :ar_top) == LK.PL_S_TRUE
    # no import (until L1f f3 also no export, variable read or boundary pair: since L1e e1 a FLOAT passed
    # as a call's own argument (`D > A - 1000`, `E =:= D + D`) reaches the slot as its value-table word
    # (`_slot_link!`, upstream's `*to = linkValI(from)`), so arithmetic reads the word; the L1d pin was
    # 100 pairs: 2 per iteration × 50, each decided on its term)
    @test _zt_counts(ld) == c1
    _zt_counts(ld) == c1 ||
        @info "ar_top: the second call's boundary traffic" _zt_counts(ld) - c1
end

# ── L1f F3B: one program per group (the workspace's L1_plan/stageL1f_design.md §3, each group's exit check
# (3): its four counters unchanged over the second call; since L1f f3 the one left, `cold_imports`) ────────────────────────────────────────────────

# f3b-1 (writers into words): a CALLER's goal put through `putSlotValue!` — its arguments with one
# `PutVarMap`, a variable shared between them — is laid on the cells directly (`_put_compound!`, as
# pl-rec.c `copy_record` lays a record): no term walk (`copy_term` read each fresh variable as a term:
# `cold_vars`), no import (`_compound_word!`: `cold_imports`), no export (the put returned the stored
# compound through `slotValue`: `cold_exports`) — each nonzero per call before f3b-1. The answer is not
# read (a reader: f3b-5); the program on the cells, as nreverse's.
const _ZT_PUT = """
pt_rev([X|L0], L) :- pt_rev(L0, L1), pt_cat(L1, [X], L).
pt_rev([], []).
pt_cat([X|L1], L2, [X|L3]) :- pt_cat(L1, L2, L3).
pt_cat([], L, L).
"""

"One call of `proc` on `args`, each put by `putSlotValue!` with ONE map, its foreign frame discarded."
function _zt_put_call(gd, ld, proc, args::Vector{_ZT})::Int
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    vm = LK.PutVarMap()
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, vm)
    end
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, a)
    rc = LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return rc
end

@testset "f3b-1: a goal put by putSlotValue! makes no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "pt_rev.pl")
    write(f, _ZT_PUT)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    s(x) = lk_sym(_ZT, Symbol(x))
    X, Y, R = lk_var(_ZT, UInt64(1)), lk_var(_ZT, UInt64(2)), lk_var(_ZT, UInt64(3))
    # [1, a, f(X, Y), 2.5, "s", X]: atoms, a small integer, a float, a string, a compound, X twice
    items = _ZT[
        lk_gnd(_ZT, Int64(1)), s(:a), mk_expr(_ZT, _ZT[s(:f), X, Y]), lk_gnd(_ZT, 2.5),
        lk_gnd(_ZT, "s"), X
    ]
    lst = foldr((h, t) -> mk_expr(_ZT, _ZT[s("[|]"), h, t]), items; init=LK.mk_nil(_ZT))
    proc = LK.lookupProcedure(s(:pt_rev), 2, LK.MODULE_user(gd))
    @test _zt_put_call(gd, ld, proc, _ZT[lst, R]) == LK.PL_S_TRUE      # indexes, supervisors
    c1 = _zt_counts(ld)
    @test _zt_put_call(gd, ld, proc, _ZT[lst, R]) == LK.PL_S_TRUE
    @test _zt_counts(ld) == c1
    _zt_counts(ld) == c1 ||
        @info "f3b-1: the second call's boundary traffic" _zt_counts(ld) - c1
end

# f3b-2 (the decompiler on the cells): clause/2 — the head and the body put by `putSlotValue!` in term
# references and each clause decompiled into them (pl-comp.c decompile: the head unified top-down into
# the cells, the body built on words, a moved unification put back — static `cl_r`: upstream moves only
# there) — makes no export, import, variable
# read or boundary pair. Until f3b-2b the clause was rebuilt as terms (keyed variables) and unified by
# the term unifier. The answer is not read (a reader: f3b-5).
const _ZT_CLAUSE = """
:- dynamic cl_f/2.
cl_f(a, g(1, [x, y])).
cl_f(b, h("s", 2.5, -7)).
cl_r(X) :- X = f(a), q(X, Y), r(Y, X).
cl_r(g(Z)) :- q(Z, W), \\+ r(W), ( W == Z -> true ; s([Z|W]) ).
"""

"clause(`head`, `body`) on `def`, both put with one map, every answer; the number of answers."
function _zt_clause_call(gd, ld, def, head::_ZT, body::_ZT)::Int
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    vm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, head, vm)
    LK.putSlotValue!(ld, t + 2, body, vm)
    n = Ref(0)
    LK.pl_clause!(gd, ld, def, t, t + 1, _ -> (n[] += 1; true))
    LK.PL_discard_foreign_frame(ld, fid)
    return n[]
end

@testset "f3b-2: clause/2 makes no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "cl.pl")
    write(f, _ZT_CLAUSE)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    s(x) = lk_sym(_ZT, Symbol(x))
    A, B, C = lk_var(_ZT, UInt64(1)), lk_var(_ZT, UInt64(2)), lk_var(_ZT, UInt64(3))
    user = LK.MODULE_user(gd)
    calls = (
        (
            LK.lookupProcedure(s(:cl_f), 2, user).definition,
            mk_expr(_ZT, _ZT[s(:cl_f), A, B])
        ),
        (LK.lookupProcedure(s(:cl_r), 1, user).definition, mk_expr(_ZT, _ZT[s(:cl_r), A]))
    )
    @test calls[2][1].impl_clauses.first_clause.clause.flags & LK.CL_HEAD_TERMS != 0  # moved: X = f(a)
    run() = [_zt_clause_call(gd, ld, def, h, C) for (def, h) in calls]
    @test run() == [2, 2]                               # indexes, supervisors
    c1 = _zt_counts(ld)
    @test run() == [2, 2]
    @test _zt_counts(ld) == c1
    _zt_counts(ld) == c1 ||
        @info "f3b-2: the second call's boundary traffic" _zt_counts(ld) - c1
end

# f3b-4 (error and message terms on the cells): each program raises one family of error at the call
# level — a type error, an instantiation error, arith's not-evaluable and one-character errors,
# op/3's protected operator, an undefined procedure, the occurs check under occurs_check=error — and
# the ball is NOT read (the query's catch, a reader:
# f3b-5b). Until f3b-4 each raise exported its culprit (`slotValue`, `_loc_term`, `_compound_term`)
# and built the ball as terms; since f3b-4 the ball is laid on the cells (`PL_cons_functor`,
# `pushWordAsTermRef`), and PL_raise_exception tests it on the words. Base (42d6205): (1, 0, 2, 0) a
# raise, at least. (The static procedure's permission error, `assertz(functor(a, b, c))`, goes through
# assert_term!'s clause readers first: f3b-5a's program.)
const _ZT_ERRORS = """
e_type :- functor(_, foo, a).
e_inst :- functor(_, _, _).
e_arith :- X is foo + 1, X > 0.
e_char :- X is [a, b] + 0, X > 0.
e_op :- op(500, xfx, system:foo).
e_undef :- no_such_predicate_xyz.
e_occ :- X = f(X).
"""

"Run `name/0` once, its exception caught by the query and not read; the return code."
function _zt_raise(gd, ld, name::Symbol)::Int
    proc = LK.lookupProcedure(lk_sym(_ZT, name), 0, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION, proc, 0)
    rc = LK.PL_next_solution(gd, ld, qid)
    raised = LK.PL_exception(ld, qid) != 0
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return raised ? -1 : rc
end

@testset "f3b-4: a raised error makes no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "errors.pl")
    write(f, _ZT_ERRORS)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_ERROR
    for name in (:e_type, :e_inst, :e_arith, :e_char, :e_op, :e_undef, :e_occ)
        @test _zt_raise(gd, ld, name) == -1                 # raised (indexes, supervisors)
        c1 = _zt_counts(ld)
        @test _zt_raise(gd, ld, name) == -1
        @test _zt_counts(ld) == c1
        _zt_counts(ld) == c1 ||
            @info "f3b-4: the second raise's boundary traffic" name _zt_counts(ld) - c1
        @test ld.tmp_top == 0                               # every temporary handle returned
    end
end

# f3b-5a (the non-VM readers on words): the static procedure's permission error — assertz/1's clause
# readers (`is_neck`, `get_head_and_body_clause`, pl-comp.c) read the clause off the cells before
# PL_error raises — makes no cold traffic. Base (f3b-4, 7f7a46f): (2, 0, 3, 0) a call.
const _ZT_STATIC = """
e_static :- assertz(functor(a, b, c)).
"""

@testset "f3b-5a: assertz of a static procedure raises with no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "static.pl")
    write(f, _ZT_STATIC)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    @test _zt_raise(gd, ld, :e_static) == -1
    c1 = _zt_counts(ld)
    @test _zt_raise(gd, ld, :e_static) == -1
    @test _zt_counts(ld) == c1
    _zt_counts(ld) == c1 ||
        @info "f3b-5a: the second raise's boundary traffic" _zt_counts(ld) - c1
end

# f3b-5b (the VM's reads on words): catch/throw with a compound ball, call/1 and call/N (both shift
# directions), the type tests, B_UNIFY_VC, setup_call_cleanup and setup_call_catcher_cleanup (exit and
# exception) — their goals read off the cells (`stripModule_cells`, `_slot_from_cell!`, the FLI type
# tests, `_unify_const_loc`, `PL_cons_functor` for the catcher) — make no cold traffic over the second
# call. Control constructs inside call/1 are left out: their goal clause is compiled from the goal's
# term (class (c), f3b-3's localGoal).
const _ZT_VM = """
m5b :- catch(throw(m5b(1, f(_))), m5b(N, T), true), N == 1, T = f(_),
       G = m5b_p(A), call(G), A == a, call(m5b_p, B), B == a,
       call(m5b_q(C), D), C-D == x-y,
       integer(N), m5b_p(Q), atom(Q), compound(T), callable(G), m5b_f(F), float(F),
       m5b_vc(V), V == foo,
       setup_call_cleanup(true, m5b_p(_), true),
       setup_call_catcher_cleanup(true, m5b_p(_), K, true), K == exit,
       catch(setup_call_catcher_cleanup(true, throw(oops), _, true), oops, true).
m5b_p(a).
m5b_q(x, y).
m5b_f(1.5).
m5b_vc(X) :- X = foo.
"""

@testset "f3b-5b: catch, metacall, type tests and cleanup make no cold export, import, variable read or boundary pair" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "vm.pl")
    write(f, _ZT_VM)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    @test _zt_run(gd, ld, :m5b) == LK.PL_S_TRUE             # indexes, supervisors
    c1 = _zt_counts(ld)
    @test _zt_run(gd, ld, :m5b) == LK.PL_S_TRUE
    @test _zt_counts(ld) == c1
    _zt_counts(ld) == c1 ||
        @info "f3b-5b: the second call's boundary traffic" _zt_counts(ld) - c1
end

# ── the bags' allocations per call (D-0140, 2026-10-24) ─────────────────────────────────────────────
# findall/3 closes its bag in a cleanup ('$destroy_findall_bag'/0, through call_term), which takes
# sync-2's fast path (pl-wam.c `call_internal_det_foreign`) once per call ('$new_findall_bag'/0 is a
# body goal of cleanup_bag/2, a VM call). That path cost +2 allocations per findall/3 and bagof/3
# call (A-0091 item 4; the bench, findall 8888 → 8890, bagof 11035 → 11037), MEASURED one each
# (2026-10-24, 32dc140): its name test built a `String` (`sym_text`; upstream reads the byte in place,
# as `sym_first_byte` does), and it made a new `foreign_context` per call (now the query's record,
# fields saved and restored). The programs are tools/bench.jl's "findall/3 ×1000" and "bagof/3 ×1000,
# 3 bags" (`BAG_PROLOG`, the same clauses), loaded from text. A COUNT (`@allocations`, as the bench's
# allocs/call), pinned on the REFERENCE type only: the alternative types are correctness vehicles that
# box every value (test/core_lang/alt_term.jl's header), so on them the call is checked and the count
# reported. The pins: main c0db435's bench counts before sync-2 — WIP, confirmed by this file's first
# run before the gate.
const _ZT_BAGS =
    join("bn($i).\n" for i in 1000:-1:1) *
    join("bk($i, $(("a", "b", "c")[i % 3 + 1])).\n" for i in 1000:-1:1) *
    "fatop :- findall(X, bn(X), _).\n" *
    "botop :- bagof(X, bk(X, K), _), K == c.\n"

"The allocations (a count) of one WARM call of `proc/0` (two calls first: indexes, supervisors, pools)."
function _zt_allocations(gd, ld, proc)::Int
    _zt_call(gd, ld, proc)
    _zt_call(gd, ld, proc)
    return @allocations _zt_call(gd, ld, proc)
end

# Re-pinned with MOD2 (D-0243; Profile.Allocs by the innermost src frame, main 7684e4d against MOD2,
# lk-channel evidence/MOD2/alloc_prof*.txt): findall 8888 → 8889 and bagof 11035 → 11037 - 3 = 11033.
# +1 each: the cleanup goal's INTERIM qualification (`_interim_mqual_cleanup`) asks `_is_colon2_word`, whose
# `mk_sym(T, :(:))` boxes a Term. -3 (bagof): the V9d condition slot is a tagged word (1598cf8, D-0231), so
# C_FASTCOND's three writes per bagof call no longer box an Int64 (`mk_gnd`).
"The allocations of a warm call of each bag program, pinned on the reference type (above)."
const _ZT_BAG_PIN = Dict(:fatop => 8889, :botop => 11033)

@testset "a warm call of findall/3 and bagof/3 allocates exactly its pin (@allocations)" begin
    gd = LK.PL_global_data{_ZT}()
    ld = LK.PL_local_data{_ZT}(gd)
    f = joinpath(mktempdir(), "bags.pl")
    write(f, _ZT_BAGS)
    st, ball, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    for name in (:fatop, :botop)
        proc = LK.lookupProcedure(lk_sym(_ZT, name), 0, LK.MODULE_user(gd))
        @test _zt_call(gd, ld, proc) == LK.PL_S_TRUE
        a = _zt_allocations(gd, ld, proc)
        if LK_TERM_IMPL == "reference"
            pin = _ZT_BAG_PIN[name]
            a == pin || @info "$name: a warm call allocates" a pin
            @test a == pin
        else
            @info "$name: a warm call allocates (not pinned on this type)" LK_TERM_IMPL a
        end
    end
end
