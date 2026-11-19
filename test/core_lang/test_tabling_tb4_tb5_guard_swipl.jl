# ORIGINAL: GUARD of the five TB4 rows that need TB5's `'$tbl_destroy_table'/1` (audit D-0659 item 2, D-0660 item 2): no swipl-devel counterpart.
# The rows (TB4-S1, S3, S4, A2, A3: groups SIMP, G13A, G13B of test_tabling_tb4_tb5_swipl.jl, TX in tools/mutants/TB4.py) cannot run where the builtin
# is not defined: boot/tabling.pl `answer_completion/2` ends with a cleanup that calls it. The guard FAILS (never skips) once the builtin is defined
# and the five rows are not pinned, and passes with the dependency named where the builtin is undefined:
#   * builtin DEFINED (asked of a set-up database: module `system`, `'$tbl_destroy_table'/1`): the groups of the rows file must be exactly SIMP, G13A,
#     G13B, naming exactly the five mutants S1, S3, S4, A2, A3 in their labels, with exactly the cases r09a-r09d, r10a-r10c, r1301, r1302, r1303, r1304,
#     each case with ONE pin line `t_<id> <answer>` of a non-empty answer behind the leading `ok`;
#   * builtin UNDEFINED: the verdict is `ok` with the dependency named (an @info line); the guard cannot skip.
# The rows file is PARSED, never run: only its `const _TR_PROG_*`, `_TR_CASES_*`, `_TR_PINS_*` and `_TR_GROUPS` are evaluated (in a module of their own), so
# the guard reads the same constants the rows read. The verdict function is proven on synthetic groups too (the guard CAN fail, and fails for each reason
# alone); the mutants of tools/mutants/TB4TB5G.py break the guard and the pins, each killed by a row named there.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the one symbol the registration query needs goes through the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TG_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_TG_sym(x) = lk_sym(_TG_T, Symbol(x))

const _TG_ROWS_FILE = joinpath(@__DIR__, "test_tabling_tb4_tb5_swipl.jl")
const _TG_BUILTIN = ("\$tbl_destroy_table", 1)

# the five mutants' rows: (group key, its cases in order, the mutants its label names)
const _TG_EXPECTED = [
    ("SIMP", ["r09a", "r09b", "r09c", "r09d", "r10a", "r10b", "r10c"], ["S1", "S3", "S4"]),
    ("G13A", ["r1301", "r1302"], ["A2"]),
    ("G13B", ["r1303", "r1304"], ["A3"])
]

const _TG_DEPENDENCY =
    "the five TB4 rows (TB4-S1, S3, S4, A2, A3) need the TB5 builtin '\$tbl_destroy_table'/1, " *
    "which is not defined here: they cannot run (owner TAB1, step TB5); the guard passes on the dependency"

"Is `name/arity` a defined procedure of module `system` in the set-up database `gd`?"
function _TG_defined(gd, name::String, arity::Int)::Bool
    proc = LK.isCurrentProcedure(sym_key(_TG_sym(name)), arity, LK.MODULE_system(gd))
    return proc !== nothing && LK.isDefinedProcedure(gd, proc)
end

"The groups of the rows file `path`: it is PARSED and only the constants of the groups are evaluated, in a module of their own."
function _TG_read_groups(path::String)
    ex = Meta.parseall(read(path, String))
    m = Module(:_TG_rows)
    for e in ex.args
        (e isa Expr && e.head === :const) || continue
        a = e.args[1]
        (a isa Expr && a.head === :(=) && a.args[1] isa Symbol) || continue
        n = String(a.args[1])
        if startswith(n, "_TR_PROG_") || startswith(n, "_TR_CASES_") ||
            startswith(n, "_TR_PINS_") || n == "_TR_GROUPS"
            Core.eval(m, e)
        end
    end
    return Core.eval(m, :_TR_GROUPS)
end

"""
The guard's verdict `(ok, path, msg)` for `groups` (the rows file's `_TR_GROUPS`): with the builtin undefined, `ok` and the dependency named;
with it defined, `ok` only when the five rows are pinned as `_TG_EXPECTED` says, else `msg` lists what is wrong.
"""
function _TG_judge(builtin::Bool, groups)::NamedTuple
    builtin || return (ok=true, path=:dependency, msg=_TG_DEPENDENCY)
    problems = String[]
    isempty(groups) && push!(problems, "no group at all")
    gkeys = [g.key for g in groups]
    sort(gkeys) == sort([e[1] for e in _TG_EXPECTED]) ||
        push!(problems, "the groups are $(gkeys), not the three of the five mutants")
    named = sort(
        reduce(
            vcat,
            [
                String[String(m.match) for m in eachmatch(r"\b[SA][0-9]\b", g.label)] for
                g in groups
            ];
            init=String[]
        )
    )
    named == sort(reduce(vcat, [e[3] for e in _TG_EXPECTED])) ||
        push!(problems, "the labels name $(named), not S1, S3, S4, A2, A3 once each")
    for e in _TG_EXPECTED
        gs = filter(g -> g.key == e[1], groups)
        length(gs) == 1 || continue                   # reported by the key check above
        g = only(gs)
        [c[1] for c in g.cases] == e[2] ||
            push!(
                problems, "$(e[1]): the cases are $([c[1] for c in g.cases]), not $(e[2])"
            )
        isempty(g.pins) && push!(problems, "$(e[1]): no pins")
        isempty(g.pins) || g.pins[1] == "ok" ||
            push!(problems, "$(e[1]): the first pin is not `ok`")
        for id in e[2]
            ls = filter(l -> startswith(l, "t_$id "), g.pins)
            (length(ls) == 1 && length(ls[1]) > length("t_$id ")) ||
                push!(problems, "$(e[1]) $(id): not exactly one pin line with an answer")
        end
    end
    return (ok=isempty(problems), path=:rows_checked, msg=join(problems, "; "))
end

"Synthetic groups shaped as `_TR_GROUPS`; `f` may change them."
function _TG_fixture()
    return [
        (
            key=k,
            label="rows of " * join(ms, ", "),
            cases=[(id, "true") for id in ids],
            pins=vcat(["ok"], ["t_$id answer" for id in ids])
        ) for (k, ids, ms) in _TG_EXPECTED
    ]
end

@testset "the guard's check sees a registered predicate and an unregistered one" begin
    gd = LK.setupProlog(_TG_T)
    @test _TG_defined(gd, "between", 3)                     # a registered built-in of `system`
    @test !_TG_defined(gd, "no_such_predicate_tg", 9)       # nothing of that name
end

@testset "the guard's verdict: builtin defined and the rows pinned, the one fault at a time" begin
    good = _TG_fixture()
    r = _TG_judge(true, good)
    @test r.ok && r.path === :rows_checked && isempty(r.msg)
    # each fault alone fails the verdict (the guard CAN fail)
    @test !_TG_judge(true, typeof(good[1])[]).ok                                  # no group at all
    @test !_TG_judge(true, good[1:2]).ok                                          # group list truncated
    @test !_TG_judge(true, vcat(good, good[1:1])).ok                              # a group twice
    @test !_TG_judge(
        true,
        [i == 1 ? merge(g, (label="rows of S1, S3",)) : g for (i, g) in enumerate(good)]
    ).ok                                                                          # a label drops S4
    @test !_TG_judge(
        true, [i == 3 ? merge(g, (pins=String[],)) : g for (i, g) in enumerate(good)]
    ).ok                                                                          # pins emptied
    @test !_TG_judge(
        true, [i == 2 ? merge(g, (pins=g.pins[1:2],)) : g for (i, g) in enumerate(good)]
    ).ok                                                                          # a case without its pin
    @test !_TG_judge(
        true,
        [
            i == 2 ? merge(g, (pins=["ok", "t_r1301 ", "t_r1302 "],)) : g for
            (i, g) in enumerate(good)
        ]
    ).ok                                                                          # pin lines with an empty answer
    @test !_TG_judge(
        true,
        [
            i == 3 ? merge(g, (pins=vcat(["fail"], g.pins[2:end]),)) : g for
            (i, g) in enumerate(good)
        ]
    ).ok                                                                          # the load line is not `ok`
    @test !_TG_judge(
        true,
        [i == 3 ? merge(g, (cases=g.cases[1:1],)) : g for (i, g) in enumerate(good)]
    ).ok                                                                          # a case dropped
    @test !_TG_judge(
        true, [i == 3 ? merge(g, (key="G13C",)) : g for (i, g) in enumerate(good)]
    ).ok                                                                          # a group renamed
    # the message names what is wrong
    @test occursin(
        "no pins",
        _TG_judge(
            true, [i == 3 ? merge(g, (pins=String[],)) : g for (i, g) in enumerate(good)]
        ).msg
    )
end

@testset "the guard's verdict: builtin undefined, the dependency named, never a skip" begin
    for groups in (_TG_fixture(), typeof(_TG_fixture()[1])[])
        r = _TG_judge(false, groups)
        @test r.ok
        @test r.path === :dependency
        @test occursin("\$tbl_destroy_table", r.msg) && occursin("TB5", r.msg)
    end
end

@testset "the five TB4 rows are pinned wherever '\$tbl_destroy_table'/1 is defined" begin
    gd = LK.setupProlog(_TG_T)
    present = _TG_defined(gd, _TG_BUILTIN...)
    groups = _TG_read_groups(_TG_ROWS_FILE)
    @test !isempty(groups)                                    # the extractor found the groups: the guard does not pass on nothing
    @test length(groups) == length(_TG_EXPECTED)
    res = _TG_judge(present, groups)
    present || @info "TB4/TB5 GUARD: " * res.msg
    @test res.path === (present ? :rows_checked : :dependency)
    res.ok || println(stderr, "  guard: ", res.msg)
    @test res.ok
end
