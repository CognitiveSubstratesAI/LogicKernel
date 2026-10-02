# ORIGINAL: a LIVE differential of compareStandard against swipl's compare/3; upstream has no such test.
# test/core_lang/test_compare_swipl.jl — the ported standard order against a LIVE swipl.
#
# `src/pl-prims.jl` is a CODE port of pl-prims.c, so the judge is upstream itself, not a list
# of expected answers copied from it: swipl evaluates `compare/3` on EVERY ordered pair of a term set
# and our `compareStandard` must agree on every one. Variables are left out — SWI orders them by
# address ("not reliable", pl-prims.c), so no two systems can agree on them.
#
# swipl present ⇒ the differential runs. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1 (set by
# tools/run_tests.sh and CI's analysis job), otherwise a LOUD note plus an assertion that it was not
# required — never a silent pass.
using Test, LogicKernel

const _OT = Term{Union{Int64, Float64, String}}
_os(x) = sym_term(_OT, x)
_og(x) = gnd_term(_OT, x)
_oe(xs::_OT...) = mk_expr(_OT, _OT[xs...])

# (our term, its Prolog source). Prolog compounds need an ATOM head and ≥ 1 argument; NaN and the
# infinities are produced by `is` because their literal syntax depends on flags.
const _ORACLE_TERMS = (
    (_og(-5), "-5"), (_og(0), "0"), (_og(1), "1"), (_og(2), "2"),
    (_og(10^15), "1000000000000000"),
    (_og(-0.0), "-0.0"), (_og(0.0), "0.0"), (_og(1.0), "1.0"), (_og(1.5), "1.5"),
    (_og(2.5), "2.5"),
    (_og(-Inf), "NInf"), (_og(Inf), "PInf"), (_og(NaN), "NaN"),
    (_og(""), "\"\""), (_og("a"), "\"a\""), (_og("ab"), "\"ab\""), (_og("b"), "\"b\""),
    (_og("B"), "\"B\""),
    (_os(:a), "a"), (_os(:ab), "ab"), (_os(:b), "b"), (_os(:B), "'B'"),
    (_os(Symbol("")), "''"),
    (_os(:é), "'é'"),
    # code-point order across the BMP boundary — the cases swipl-devel tests/core_lang/test_bips.pl
    # pins (non_bmp_vs_bmp_*), here judged by swipl against every other term in the set
    (_os(Symbol("\U0001D11E")), "'\U0001D11E'"), (_os(Symbol("\u8C48")), "'\u8C48'"),
    (_os(Symbol("\uF900")), "'\uF900'"), (_os(Symbol("\uFF80")), "'\uFF80'"),
    (_oe(_os(:f), _os(:a)), "f(a)"), (_oe(_os(:f), _os(:b)), "f(b)"),
    (_oe(_os(:g), _os(:a)), "g(a)"),
    (_oe(_os(:f), _os(:a), _os(:b)), "f(a,b)"), (_oe(_os(:f), _og(1)), "f(1)"),
    (_oe(_os(:f), _og(1.0)), "f(1.0)"), (_oe(_os(:g), _oe(_os(:f), _os(:a))), "g(f(a))"),
    (_oe(_os(:h), _os(:a), _os(:b), _os(:c)), "h(a,b,c)"),
    (_oe(_os(:f), _oe(_os(:f), _oe(_os(:f), _og(-0.0)))), "f(f(f(-0.0)))"),
    (_oe(_os(:f), _oe(_os(:f), _oe(_os(:f), _og(0.0)))), "f(f(f(0.0)))"),
    (_oe(_os(:f), _og("a")), "f(\"a\")"), (_oe(_os(:f), _os(:a), _og(2.5)), "f(a,2.5)")
)

function _swipl_compare_matrix(srcs)::Matrix{Int}
    n = length(srcs)
    prog = """
    :- set_prolog_flag(double_quotes, string).
    main :- NaN is nan, PInf is inf, NInf is -inf,
            L = [$(join(srcs, ", "))],
            forall((between(1, $n, I), between(1, $n, J)),
                   ( nth1(I, L, A), nth1(J, L, B), compare(O, A, B),
                     ( O == (<) -> R = -1 ; O == (=) -> R = 0 ; R = 1 ),
                     format("~d ~d ~d~n", [I, J, R]) )).
    :- initialization((main, halt)).
    """
    out = mktempdir() do d
        f = joinpath(d, "order.pl")
        write(f, prog)
        read(`swipl -q $f`, String)
    end
    m = zeros(Int, n, n)
    seen = 0
    for l in eachline(IOBuffer(out))
        i, j, r = parse.(Int, split(l))
        m[i, j] = r
        seen += 1
    end
    seen == n * n || error("swipl produced $seen of $(n * n) comparisons:\n$out")
    return m
end

const _SWIPL = Sys.which("swipl")
const _SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _SWIPL !== nothing
    @testset "standard order == live swipl compare/3 on every pair" begin
        m = _swipl_compare_matrix(last.(_ORACLE_TERMS))
        n = length(_ORACLE_TERMS)
        bad = String[]
        for i in 1:n, j in 1:n
            ours = compareStandard(_ORACLE_TERMS[i][1], _ORACLE_TERMS[j][1])
            ours == m[i, j] || push!(
                bad,
                "$(_ORACLE_TERMS[i][2]) vs $(_ORACLE_TERMS[j][2]): ours $ours, swipl $(m[i, j])"
            )
        end
        isempty(bad) || foreach(b -> println(stderr, "  DIVERGES: ", b), bad)
        @test isempty(bad)
        @test n * n > 1000                                  # the differential saw real data
        @test count(==(-1), m) > 0 && count(==(1), m) > 0   # …and swipl really ordered it
        @info "standard order agrees with $(strip(read(`swipl --version`, String))) on $(n * n) pairs"
    end
elseif _SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the upstream differential would be skipped"
    )
else
    @info "UPSTREAM DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "swipl differential skipped only where it is not required" begin
        @test !_SWIPL_REQUIRED
    end
end
