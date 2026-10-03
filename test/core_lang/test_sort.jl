# UPSTREAM: swipl-devel tests/core_lang/test_sort.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (C): 1985-2015, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# The unit of swipl-devel's test_sort.pl that exercises what LogicKernel has ported: `reserved` —
# SWI-7's reserved symbol `[]` sorts before text atoms ("blobs sort before text": pl-ressymbol.c
# ranks the reserved-symbol type 0, below every text type, and pl-prims.c `compareAtoms` orders
# atoms of different types by rank). The order is stated through `compareStandard`, the order
# sort/2 uses.
#
# NOT PORTED from this file, and why:
#   sort: empty, unique, instantiation, type, cyclic   sort/2 itself (pl-list.c) is not ported —
#                                                       its deduplication, argument and list
#                                                       checks, and cyclic-list handling
#   msort, keysort, sort4 (every unit)                  the same built-ins; sort4's dict units
#                                                       also need dicts
using Test, LogicKernel

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _ST = lk_term_type(Union{Int64, Float64, String})

"`sort/2`'s order of `xs`: the standard order (no duplicates among these, so none to remove)."
_ssort(xs::Vector) = sort(xs; lt=(x, y) -> compareStandard(x, y) < 0)

@testset "sort" begin
    # PORT: test_sort.pl reserved
    @testset "reserved" begin
        a = lk_sym(_ST, :a)
        w = lk_sym(_ST, Symbol(String(Char[Char(1040), Char(1041)])))  # atom_codes(W, [1040,1041])
        nil = mk_nil(_ST)
        r = _ssort(_ST[a, nil, w])                                      # sort([a,[],W], R)
        @test lk_eq(r, _ST[nil, a, w])                                   # R == [[],a,W]
    end
end
