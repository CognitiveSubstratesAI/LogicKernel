# ORIGINAL: L1e step e2 — the FLI readers on WORDS (pl-fli.c PL_is_float, PL_is_rational, PL_is_compound,
# PL_is_callable, PL_is_atomic, … as `_deref_loc` word paths, src/pl-fli.jl; the workspace's
# L1_plan/stageL1e_design.md §2). test/core_lang/test_fli_words.jl — on every term type:
#   * a differential against swipl through the type-test built-ins that call them (float/1, rational/1,
#     atomic/1, compound/1, callable/1): atoms, `[]`, small and big integers, floats, strings, compounds,
#     lists, variables — passed directly and bound through a clause body (a cell), and a `$expr` compound
#     is not callable;
#   * the boundary: a keyed variable's binding read on terms, COUNTED, with the right answer;
#   * the meter: a loop of these built-ins on values on the stack makes no cold export, import, variable
#     read or boundary pair.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_fw_k(i) = _rg(Int64(i))
const _FW_TESTS = ("float", "rational", "atomic", "compound", "callable")

"One clause per type test: `t_<name>(X, R)` — R = yes when the test holds of X, no otherwise; and the same
with X bound through a cell (`c_<name>`)."
function _fw_clauses()
    X, R, Y = _rv(1), _rv(2), _rv(3)
    cl = Tuple{_R, Union{Nothing, _R}}[]
    for n in _FW_TESTS
        push!(
            cl,
            (
                _rf("t_" * n, X, R),
                _rite(_rf(n, X), _rf("=", R, _rs("yes")), _rf("=", R, _rs("no")))
            )
        )
        push!(
            cl,
            (_rf("c_" * n, X, R),
                _rconj(_rf("=", Y, _rf("w", X)), _rf("=", Y, _rf("w", _rv(4))),
                    _rite(_rf(n, _rv(4)), _rf("=", R, _rs("yes")), _rf("=", R, _rs("no")))))
        )
    end
    return cl
end

@testset "the type tests on words, as swipl" begin
    db = _rdb(_fw_clauses())
    vals = _R[
        _rs("a"), _rnil(), _fw_k(3), _rg(2.5), _rg(-0.0), _rf("f", _rs("x")),
        _rlist(_fw_k(1), _fw_k(2)),
        _rv(50), _rf("f", _rv(51))
    ]
    goals = _R[
        _rf(p * "_" * n, v, _rv(60)) for n in _FW_TESTS for p in ("t", "c") for v in vals
    ]
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    @test "t_float(2.5,yes) det" in ours && "c_compound(f(x),yes) det" in ours
    if _R_SWIPL
        theirs = _rswipl(_fw_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            for i in eachindex(ours)
                if i > length(theirs) || ours[i] != theirs[i]
                    @info "first difference" i ours[i] get(theirs, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"An engine with the values of `vs` put into term references; `(ld, t)`."
function _fw_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_fw_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
_fw_all(ld, t) = (
    LK.PL_is_float(ld, t), LK.PL_is_rational(ld, t), LK.PL_is_atomic(ld, t),
    LK.PL_is_compound(ld, t),
    LK.PL_is_callable(ld, t)
)

@testset "the boundary: a keyed variable's binding, read on terms, counted" begin
    ld, t = _fw_engine(_R[_rs("x")])
    kv = lk_var(_R, UInt64(4741))
    LK.setSlotValue!(ld, t + 1, kv)
    LK.Trail!(ld, var_key(kv), _rg(1.25))
    p0 = ld.cold_pairs
    @test _fw_all(ld, t) == (true, false, true, false, false)
    @test ld.cold_pairs > p0
end

@testset "the meter: the type tests on values on the stack make no cold traffic" begin
    ld, t = _fw_engine(_R[_rs("a"), _fw_k(7), _rg(1.5), _rf("f", _rv(1)), _rnil(), _rv(2)])
    c0 = _fw_counts(ld)
    want = (
        (false, false, true, false, true), (false, true, true, false, false),
        (true, false, true, false, false),
        (false, false, false, true, true), (false, false, true, false, false),
        (false, false, false, false, false)
    )
    for i in 1:6
        @test _fw_all(ld, t + i - 1) == want[i]
    end
    @test _fw_counts(ld) == c0
    # a compound with a variable head is the kernel's `$expr/n` (no swipl counterpart): a compound, not callable
    ld2, t2 = _fw_engine(_R[mk_expr(_R, _R[_rv(9), _rs("a")])])
    @test _fw_all(ld2, t2) == (false, false, false, true, false)
end
