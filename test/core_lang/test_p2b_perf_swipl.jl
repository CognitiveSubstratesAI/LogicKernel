# ORIGINAL: the timing row of test_p2b_swipl.jl for sub_atom_icasechk/3 (pl-prims.c 5099-5170), moved to its own file: a PERFORMANCE GUARD,
# not a mutation kill (audit D-0903 (2), D-0915 (3)(e)). P2B-I2 is declared equivalent (the answers are identical, only the work differs);
# the row measures time, so it lives outside the file tools/mutants/P2B.py runs as its targets, and the battery no longer meets it.
# UNVERIFIED on the kernel: gate decides: the best-of-3 margin (< 0.5 s against the search form's seconds).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-ins ride the term layer through PL_unify_integer and PL_get_int64_ex only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _P2B = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_p2bs(x) = lk_sym(_P2B, Symbol(x))

# PERFORMANCE GUARD, not a mutation kill (D-0903 (2), D-0915 (3)(e)); LK-ONLY (P2B-I2, q24's companion): a bound Start is read AT, not searched from. The ANSWER cannot tell the two apart (the search from
# Start finds the match AT Start first when there is one, and a later match then fails to unify with Start), so this row measures the
# work: a haystack with no match at Start is compared once, `l1` characters, where a search from Start walks every later position.
# swipl 10.1.20 answers `false` for both goals, as q24 pins; the kernel's time for the search form is orders of magnitude above the at form's.
@testset "LK-ONLY: a bound start is compared at, not searched from (P2B-I2)" begin
    gd = LK.PL_global_data{_P2B}()
    ld = LK.PL_local_data{_P2B}(gd)
    goal(h, s, n) = mk_expr(_P2B, _P2B[_p2bs(:sub_atom_icasechk), _p2bs(h), s, _p2bs(n)])
    run(h, s, n) = LK.query_answers(ld, goal(h, s, n); limit=1)
    int(i) = lk_gnd(_P2B, i)
    h = "a"^300_000
    n = "a"^2_000 * "b"                     # never matches: the run of a's is cut by the b
    @test !isempty(run("aab", int(1), "ab"))       # warm-up and control: a match AT 1
    @test isempty(run(h, int(0), n))
    @test isempty(run(h, int(1), n))
    best = minimum(@elapsed(run(h, int(1), n)) for _ in 1:3)
    @test best < 0.5                        # one pass of 2001 characters; the search from Start is 6e8 and takes seconds
end
