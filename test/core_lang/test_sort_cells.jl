# ORIGINAL: L1d step 9 — the sort family on CELLS (pl-list.c prolog_list_to_sort_list, put_sort_list,
# pl_nat_sort and pl-prims.c skip_list as their `_cells` ports, src/pl-list.jl, src/pl-prims.jl; the
# workspace's L1_plan/stageL1d_design.md §3i). The records hold the items' and keys' positions, compared by
# the standard order on cells; the sorted list is laid out as fresh cells (upstream rewrites its records in
# place) — a representation-only DIVERGES. test/core_lang/test_sort_cells.jl — on every term type:
#   * a differential against swipl through clause bodies: sort/2, msort/2, keysort/2 on mixed types,
#     duplicates, keysort's stability, variables (the standard order of variables: by age), a variable item
#     in the result (the head a reference: binding it binds the original), a cyclic list under sort/2, and
#     the errors — a partial list, a non-list, a non-pair element;
#   * the boundary: a keyed variable's binding as an item, sorted on terms, counted;
#   * the meter: sorting a list on the stack makes no cold export, import or variable read.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_ki(i) = _rg(Int64(i))
_sf(x) = _rg(Float64(x))
_kv(k, v) = _rf("-", k, v)

_st_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("s", _rv(1), _rv(2)), _rf("sort", _rv(1), _rv(2))),
    (_rf("m", _rv(1), _rv(2)), _rf("msort", _rv(1), _rv(2))),
    (_rf("k", _rv(1), _rv(2)), _rf("keysort", _rv(1), _rv(2))),
    # variables by age: Y made after X; the sorted list holds the variables themselves
    (
        _rf("vage", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("p", _rv(2))), _rf("=", _rv(3), _rf("p", _rv(4))),
            _rf("msort", _rlist(_rv(4), _rs("a"), _rv(2), _rv(4)), _rv(5)),
            _rf("=", _rv(5), _rlist(_rv(6), _rv(7), _rv(8), _rs("a"))),
            _rf("==", _rv(6), _rv(2)), _rf("==", _rv(7), _rv(4)),
            _rf("==", _rv(8), _rv(4)),
            _rf("\\==", _rv(1), _rv(3)),         # (A, B not singletons: swipl then allocates X, Y in place)
            _rf("=", _rv(9), _rs("ok")))
    ),
    # an item that is a variable: binding the result's binds the original
    (
        _rf("vbind", _rv(1)),
        _rconj(_rf("sort", _rlist(_rs("b"), _rv(1)), _rlist(_rv(2), _rs("b"))),
            _rf("=", _rv(2), _rs("bound")))
    ),
    # sort/2 on a cyclic list
    (
        _rf("cyc", _rv(2)),
        _rconj(_rf("=", _rv(1), _rcons(_rs("a"), _rcons(_rs("b"), _rv(1)))),
            _rf("sort", _rv(1), _rv(2)))
    ),
    (_rf("partial", _rv(2)), _rf("msort", _rcons(_rs("a"), _rv(3)), _rv(2))),
    (
        _rf("long", _rv(1), _rv(9)),
        _rconj(_rf("length", _rv(2), _rv(1)),
            _rf("msort", _rv(2), _rv(9)))
    )
]

@testset "the sort family on cells, as swipl" begin
    db = _rdb(_st_clauses())
    A, B, C = _rv(50), _rv(51), _rv(52)
    goals = _R[
        _rf("s",
            _rlist(_rs("c"), _ki(2), _rs("a"), _sf(1.5), _rf("f", _rs("x")), _ki(2),
                _rs("a"),
                _ki(1)), C),
        _rf(
            "m",
            _rlist(_rs("c"), _ki(2), _rs("a"), _sf(1.5), _ki(2), _rs("a"), _ki(1), _sf(1)),
            C
        ),
        _rf(
            "s",
            _rlist(_rf("g", _rs("b")), _rf("f", _rs("b"), _rs("a")), _rf("f", _rs("a"))),
            C
        ),
        _rf("s", _rlist(), C), _rf("s", _rlist(_rs("z")), C), _rf("m", _rlist(A), C),
        _rf("k",
            _rlist(_kv(_ki(2), _rs("a")), _kv(_ki(1), _rs("b")), _kv(_ki(2), _rs("c")),
                _kv(_ki(1), _rs("d"))), C),
        # three runs, equal keys across them: the final merge of the run stack keeps the input order
        _rf("k",
            _rlist(_kv(_ki(3), _rs("a")), _kv(_ki(1), _rs("b")), _kv(_ki(2), _rs("c")),
                _kv(_ki(1), _rs("d")), _kv(_ki(2), _rs("e")), _kv(_ki(1), _rs("f"))), C),
        _rf("k", _rlist(_kv(_ki(1), _rs("a"))), C),
        _rf("k", _rlist(_kv(_ki(1), _rs("a")), _rs("oops")), C),
        _rf("s", _rs("notalist"), C), _rf("partial", C),
        _rf("vage", C), _rf("vbind", C), _rf("cyc", C), _rf("long", _ki(1500), C)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also without swipl: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test "vage(ok) det" in ours && "vbind(bound) det" in ours
    @test any(l -> startswith(l, "exception(type_error(pair,oops))"), ours)
    if _R_SWIPL
        theirs = _rswipl(_st_clauses(), goals)
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

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _st_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_st_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

@testset "the boundary: a keyed variable's binding as an item, sorted on terms, counted" begin
    ld, t = _st_engine(_R[_rs("x"), _rv(9)])
    kv = lk_var(_R, UInt64(4741))
    LK.setSlotValue!(ld, t + 1, _rlist(_rs("b"), kv, _rs("a")))
    LK.Trail!(ld, var_key(kv), _rs("c"))
    p0 = ld.cold_pairs
    @test LK.pl_nat_sort(ld, t, t + 1, true, LK.SORT_ASC, false)
    @test ld.cold_pairs > p0
    r = LK.resolve_term(ld, LK.slotValue(ld, t + 2))
    @test LK.compareStandard(r, _rlist(_rs("a"), _rs("b"), _rs("c")), true) == LK.CMP_EQUAL
end

@testset "the meter: sorting a list on the stack makes no cold export, import or variable read" begin
    X, Y = _rv(1), _rv(2)
    ld, t = _st_engine(
        _R[
            _rlist(
                _rs("c"),
                X,
                _ki(3),
                _rf("f", Y),
                _ki(1),
                _sf(2.5),
                _rs("a"),
                X,
                (_ki(i) for i in 40:-1:1)...
            ),
            _rlist((_kv(_ki(i % 7), _rs("v")) for i in 1:30)...), _rv(3), _rv(4), _rv(5)
        ]
    )
    c0 = _st_counts(ld)
    @test LK.pl_nat_sort(ld, t, t + 2, true, LK.SORT_ASC, false)
    @test LK.pl_nat_sort(ld, t, t + 3, false, LK.SORT_DESC, false)
    @test LK.pl_nat_sort(ld, t + 1, t + 4, false, LK.SORT_ASC, true)
    @test _st_counts(ld) == c0
end
