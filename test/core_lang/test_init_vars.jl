# ORIGINAL: the defensive initialisation of a clause's listed cells (see register Q3) and its clause-entry coverage check — split out of test_rules_swipl.jl (user, 2026-10-12: mutants target the smallest
# test file holding the killing assertion). test/core_lang/test_init_vars.jl
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# ── defensive initialisation ────────────────────────────────────────────────────────────────────
# Defensive initialisation; see register Q3 (user, 2026-10-12). The cells a clause's `init_vars`
# lists hold fresh variables from the moment the clause gets its frame (`_init_clause_vars!`); its
# other cells are left as they were. Each `fv…` predicate below is called with equal arguments —
# it answers, and `prolog_current_frame/1` gives the frame's position — and then with different
# ones, a value planted over the stack above `lTop` first: it fails at `A == B`, before any goal
# on its other variables, and their cells are read from the stack. One predicate per point that
# hands a frame to a clause.
"The clauses: `D` and `E` are listed in `init_vars`, `G` is not."
function _rinit_clauses()
    F, A, B, D, E, G = (_rv(k) for k in 1:6)
    eq(v, i) = _rf("==", v, _rg(i))
    body = _rconj(
        _rf("prolog_current_frame", F), _rf("==", A, B),
        _rnot(_rconj(eq(D, 1), eq(D, 2), eq(E, 1), eq(E, 2), _rf("==", A, _rs("zz")))),
        _rf("=", G, _rg(1)), _rf("\\==", G, _rg(2))
    )
    h(name) = _rf(name, F, A, B)
    other(name) = _rf(name, _rv(7), _rv(8), _rv(9))
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("one", _rg(2)), nothing),
        (h("fvtrust"), body),                                       # its only clause
        (h("fvfirst"), body),                                       # the first of two
        (_rf("fvfirst", _rs("zz"), _rs("zz"), _rs("zz")), nothing),
        (other("fvshallow"), _rs("fail")),                          # fails in its own frame
        (h("fvshallow"), body),
        (other("fvdeep"), _rf("one", _rg(1))),                      # fails in a frame below
        (h("fvdeep"), body)
    ]
end

@testset "defensive initialisation: the cells a clause lists start as fresh variables" begin
    db = _rdb(_rinit_clauses())
    ld = db.ld
    planted = _rs("planted")
    arity = 3
    for name in ("fvtrust", "fvfirst", "fvshallow", "fvdeep")
        pr = _rproc(db, _rf(name, _rv(81), _rv(82), _rv(83)))
        cref = pr.definition.impl_clauses.first_clause
        lists = Vector{Int32}[]
        nvars = 0
        while cref !== nothing
            isempty(cref.clause.init_vars) || push!(lists, cref.clause.init_vars)
            isempty(cref.clause.init_vars) || (nvars = Int(cref.clause.prolog_vars))
            cref = cref.next
        end
        @test length(lists) == 1 && length(lists[1]) == 2          # one clause lists D and E
        @test nvars == arity + 3                                    # the arguments, D, E and G
        listed = Int.(lists[1])
        @test listed == [arity, arity + 1]          # D and E, the first two after the arguments; not A
        rest = setdiff(arity:(nvars - 1), listed)                   # G
        @test length(rest) == 1
        ans = _rcall(db, _rf(name, _rv(90), _rs("x"), _rs("x")))
        m = match(r"^\w+\((\d+),x,x\)$", ans[1][1])                 # the first answer: name(F,x,x)
        @test m !== nothing
        base = parse(Int, m[1])
        top = ld.lTop + 400
        length(ld.slots) < top && resize!(ld.slots, top)
        fill!(view(ld.slots, (ld.lTop + 1):top), planted)
        @test isempty(_rcall(db, _rf(name, _rv(90), _rs("x"), _rs("y"))))
        cells = [LK.argFrameP(base, v) + 1 for v in listed]
        @test all(c -> isassigned(ld.slots, c), cells)
        d = LK.resolve_term(ld, ld.slots[cells[1]])
        e = LK.resolve_term(ld, ld.slots[cells[2]])
        @test kind(d) === VAR && kind(e) === VAR                    # fresh, and unbound (resolve is the var)
        @test var_key(d) != var_key(e)                              # two variables, not one
        rest_cell = ld.slots[LK.argFrameP(base, rest[1]) + 1]       # the cell not listed: untouched
        @test LK.compareStandard(rest_cell, planted, true) == 0
    end
end

# Coverage (user, 2026-10-12): one place hands a frame to a clause and must initialise its listed
# cells. The check ties the two together in src/pl-wam.jl — every assignment of a clause to the
# running frame (`ld.frames[FR].clause = <cl>`, other than the `nothing` of frame teardown) is a
# clause entry, and each must be matched by a `_init_clause_vars!` call. A new entry point that
# sets the frame's clause without the call makes the counts diverge, and this fails. Goes with the
# initialisation when upstream fixes Q3.
@testset "every clause-entry point initialises the clause's cells (Q3 coverage)" begin
    src = read(joinpath(@__DIR__, "..", "..", "src", "pl-wam.jl"), String)
    lines = split(src, '\n')
    code(l) = strip(first(split(l, '#')))                       # the line without its comment
    entries = [
        l for l in lines if occursin(r"\bframes\[FR\]\.clause\s*=", code(l)) &&
            !occursin(r"=\s*nothing\b", code(l))
    ]
    inits = [l for l in lines if occursin(r"_init_clause_vars!\(ld,", code(l))]
    @test !isempty(entries) && !isempty(inits)                  # both sides non-empty
    @test length(entries) == length(inits)                      # no entry bypasses the call
    # and the known four are present by name, so a rename cannot hollow the check out
    for cl in ("ss_cl", "tc_cref", "sb_cl", "db_cl")
        @test any(l -> occursin("frames[FR].clause = $cl", code(l)), entries)
    end
    for v in ("ss_clause", "tc_clause", "sb_clause", "db_clause")
        @test any(
            l -> occursin("_init_clause_vars!(ld, ld.frames[FR].base, $v)", code(l)), inits
        )
    end
end
