# ORIGINAL: the L1c plan's condition 3 (user, 2026-10-15) — the cold adapters are guarded MECHANICALLY: a
# hot path falling back to the term boundary fails THIS test, not just an allocation count. Upstream
# has no counterpart (its VM has no term boundary). test/core_lang/test_zero_exports.jl — on every
# term type: one call of each of swipl's benchmark programs nreverse and qsort (bench/programs/*.pl,
# as tools/bench.jl runs them) leaves all three counters of the boundary unchanged:
#   * `cold_exports` — a compound on the stack read as a term (`_compound_term`),
#   * `cold_imports` — a term copied onto the stack (`_compound_word!`; the deep index's boundary
#     descent included, sub-commit 5),
#   * `cold_vars` — a cell's variable read as a term (`_cell_var`, sub-commit 6),
#   * `cold_pairs` — a pair the cell compare decides as terms (the boundary, L1d step 1);
# and a small program that compares (==, \==, compare/3 over lists on the stack) does the same.
# The first call builds the predicates' indexes and supervisors; the asserted call is the second (and
# the first's counts are reported). The export memo's entry count over the run is reported too
# (condition 3 of the memo's approval: how much cold traffic exists).
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

_zt_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

@testset "nreverse and qsort make no cold export, import or variable read" begin
    for name in (:nreverse, :qsort)
        gd, ld = _zt_load(String(name))
        c0 = _zt_counts(ld)
        @test _zt_run(gd, ld, name) == LK.PL_S_TRUE         # the first call: indexes, supervisors
        c1 = _zt_counts(ld)
        @info "$name: the first call's boundary traffic (exports, imports, variable reads)" c1 .-
            c0
        @test _zt_run(gd, ld, name) == LK.PL_S_TRUE
        c2 = _zt_counts(ld)
        @test c2 == c1                                      # THE CONDITION: zero, all three
        c2 == c1 || @info "$name: the second call's boundary traffic" c2 .- c1
        @info "$name: export memo entries after two calls" ld.ngterm
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
# All of it is a small integer on the value table: L1d step 4 (tagged integer words) removes it and
# moves these two numbers to 0. Constant per call: nothing (the `[]` word and its index key came off
# the term path in L1c-6).
"The bytes one warm call of `name` allocates, pinned per term type (above)."
const _ZT_ALLOC_PIN = Dict(
    "reference" => Dict(:nreverse => 0, :qsort => 0),
    "alt" => Dict(:nreverse => 1440, :qsort => 10400),
    "alt_interned" => Dict(:nreverse => 1440, :qsort => 10400)
)
@testset "a warm call of nreverse and qsort allocates exactly its pin (@allocated)" begin
    for name in (:nreverse, :qsort)
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
