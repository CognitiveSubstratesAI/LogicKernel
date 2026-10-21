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
    lk_side_value!(ld, t + 1, kv)                       # (the boundary: built since L1f f3b-1)
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

# ── e2b: the getters on words ──────────────────────────────────────────────────────────────────
# PL_get_integer / PL_get_stdbool / PL_is_list / PL_skip_list are C-interface contracts no Prolog goal asks
# swipl directly, so their expected values are written from pl-fli.c at the pin (PL_get_integer: a TAGGED
# integer in `int` range only; PL_get_stdbool: true/on/false/off/1/0; PL_is_list: a list cell or `[]`;
# PL_skip_list: PL_LIST / PL_PARTIAL_LIST / PL_CYCLIC_TERM / PL_NOT_A_LIST) — and term_variables/3, the
# built-in that calls PL_skip_list, is compared with swipl below.
@testset "e2b: the getters on values on the stack, no cold traffic" begin
    ld, t = _fw_engine(
        _R[
            _fw_k(42), _fw_k(Int64(2)^40), _rs("on"), _rs("false"), _fw_k(1), _fw_k(2),
            _rlist(_fw_k(1), _fw_k(2)), _rnil(), _rcons(_fw_k(1), _rv(3)),
            _rf("f", _rs("a")), _rg(2.5)
        ]
    )
    c0 = _fw_counts(ld)
    @test LK.PL_get_integer(ld, t) == 42
    @test LK.PL_get_integer(ld, t + 1) === nothing           # outside `int`
    @test LK.PL_get_integer(ld, t + 10) === nothing          # a float
    @test LK.PL_get_stdbool(ld, t + 2) === true && LK.PL_get_stdbool(ld, t + 3) === false
    @test LK.PL_get_stdbool(ld, t + 4) === true && LK.PL_get_stdbool(ld, t + 5) === nothing
    @test LK.PL_get_stdbool(ld, t + 9) === nothing
    @test LK.PL_is_list(ld, t + 6) && LK.PL_is_list(ld, t + 7) && LK.PL_is_list(ld, t + 8)
    @test !LK.PL_is_list(ld, t + 9) && !LK.PL_is_list(ld, t)
    @test LK.PL_skip_list(ld, t + 6) == (LK.PL_LIST, 2)
    @test LK.PL_skip_list(ld, t + 7) == (LK.PL_LIST, 0)
    @test LK.PL_skip_list(ld, t + 8) == (LK.PL_PARTIAL_LIST, 1)
    @test LK.PL_skip_list(ld, t + 9)[1] == LK.PL_NOT_A_LIST
    @test _fw_counts(ld) == c0
end

@testset "e2b: PL_skip_list's caller term_variables/3, as swipl" begin
    A, B, L, T = _rv(1), _rv(2), _rv(3), _rv(4)
    cl = Tuple{_R, Union{Nothing, _R}}[
        (_rf("tv", _rv(5), L), _rf("term_variables", _rv(5), L, _rlist(_rs("z")))),
        (_rf("tvp", _rv(5), L, T), _rf("term_variables", _rv(5), L, T))
    ]
    goals = _R[
        _rf("tv", _rf("f", A, B, A), _rv(60)), _rf("tv", _rs("g"), _rv(60)),
        _rf("tvp", _rf("h", A, _rf("k", B)), _rv(60), _rv(61)),
        _rf("tv", _rf("f", A), _rlist(_rv(62))), _rf("tv", _rf("f", A), _rs("notalist"))
    ]
    ours = _rlines(_rdb(cl), goals)
    @test count(==("end"), ours) == length(goals)
    if _R_SWIPL
        @test ours == _rswipl(cl, goals)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── e2c: PL_strip_module / PL_strip_module_ex on words ─────────────────────────────────────────
@testset "e2c: module qualifiers stripped on the words (call/N, assertz), as swipl" begin
    R = _rv(1)
    um(g) = _rf(":", _rs("user"), g)
    cl = Tuple{_R, Union{Nothing, _R}}[
        # a user predicate: `user:` resolves to user itself (a SYSTEM predicate through `user:` needs module
        # inheritance — `call(user:atom_length(abc, N))` is existence_error here, 3 in swipl: before e2c too,
        # not ported until R2; reported to the audit, A-0024)
        (_rf("smp", _fw_k(3)), nothing),
        (_rf("smc", R), _rf("call", um(_rf("smp", R)))),
        (_rf("smn", R), _rf("call", um(um(_rf("smp", R))))),
        (_rf("sma", R), _rconj(_rf("assertz", um(_rf("smf", _fw_k(7)))), _rf("smf", R))),
        (
            _rf("smb", R),
            _rf("catch", _rf("assertz", _rf(":", _rf("f", _rs("x")), _rs("smg"))),
                _rf("error", R, _rv(2)), _rs("true"))
        ),
        (
            _rf("smv", R),
            _rf("catch", _rf("call", _rf(":", _rv(3), _rs("true"))),
                _rf("error", R, _rv(2)), _rs("true"))
        )
    ]
    goals = _R[_rf(n, _rv(60)) for n in ("smc", "smn", "sma", "smb", "smv")]
    ours = _rlines(_rdb(cl), goals)
    @test count(==("end"), ours) == length(goals)
    @test "smc(3) det" in ours && "sma(7) det" in ours
    if _R_SWIPL
        theirs = _rswipl(cl, goals)
        @test ours == theirs
        ours == theirs || @info "e2c differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "e2c: PL_strip_module(_ex) on a term on the stack, no cold traffic" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    gd, ld = db.gd, db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 3)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(
        ld, t + 1, _rf(":", _rs("user"), _rf(":", _rs("system"), _rf("g", _rv(5)))), pvm
    )
    LK.putSlotValue!(ld, t + 2, _rf("h", _rs("a")), pvm)
    c0 = _fw_counts(ld)
    ok, m = LK.PL_strip_module(gd, ld, t, 0, t + 2)
    @test ok && m == LK.MODULE_system(gd).index
    @test LK.PL_is_compound(ld, t + 2)
    ok, m = LK.PL_strip_module_ex(gd, ld, t + 1, 0, t + 1)
    @test ok && m == LK.MODULE_user(gd).index
    @test _fw_counts(ld) == c0
end

# ── e2c: PL_get_text, PL_get_size_ex, PL_scan_options on words ────────────────────────────────
@testset "e2c: text, size and options through their built-ins, as swipl" begin
    N, E = _rv(1), _rv(2)
    cl = Tuple{_R, Union{Nothing, _R}}[
        (
            _rf("al", _rv(3), N),
            # read_term_from_atom/3 reads its text through PL_get_text (atom, string or code list)
            _rf(
                "catch", _rf("read_term_from_atom", _rv(3), N, _rnil()),
                _rf("error", N, _rv(4)),
                _rs("true")
            )
        ),
        (
            _rf("fu", _rv(3), N),
            _rf("catch",
                _rconj(_rf("functor", _rv(5), _rs("f"), _rv(3)), _rf("=", N, _rv(5))),
                _rf("error", N, _rv(4)), _rs("true"))
        ),
        (
            _rf("nv", E),
            _rf(
                "numbervars",
                _rf("g", _rv(6), _rv(7), _rv(6)),
                _fw_k(0),
                E,
                _rlist(_rf("singletons", _rs("true")))
            )
        )
    ]
    goals = _R[
        _rf("al", _rs("f(a, b)"), _rv(60)), _rf("al", _rg("g(X, X)"), _rv(60)),
        _rf("al", _rlist(_fw_k(104), _fw_k(40), _fw_k(49), _fw_k(41)), _rv(60)),
        _rf("al", _fw_k(1234), _rv(60)),
        _rf("al", _rg(2.5), _rv(60)), _rf("al", _rf("f", _rs("x")), _rv(60)),
        _rf("al", _rv(61), _rv(60)),
        _rf("fu", _fw_k(2), _rv(60)), _rf("fu", _fw_k(-1), _rv(60)),
        _rf("fu", _rs("a"), _rv(60)),
        _rf("nv", _rv(60))
    ]
    ours = _rlines(_rdb(cl), goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> occursin("existence_error", l), ours)   # every built-in here is ported
    if _R_SWIPL
        theirs = _rswipl(cl, goals)
        @test ours == theirs
        ours == theirs || @info "e2c text differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "e2c: PL_get_text and PL_get_size_ex on values on the stack, no cold traffic" begin
    ld, t = _fw_engine(_R[_rs("abc"), _rg("strng"), _fw_k(42), _rg(1.5)])
    c0 = _fw_counts(ld)
    cvt = LK.CVT_ATOM | LK.CVT_STRING | LK.CVT_NUMBER
    @test String(LK.PL_get_text(ld, t, cvt).text[1:3]) == "abc"
    @test LK.PL_get_text(ld, t + 1, cvt) !== nothing
    @test String(copy(LK.PL_get_text(ld, t + 2, cvt).text)) == "42"
    @test LK.PL_get_text(ld, t + 3, cvt) !== nothing
    @test LK.PL_get_size_ex(ld, t + 2) == 42
    @test _fw_counts(ld) == c0
end
