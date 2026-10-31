# ORIGINAL: the fuzz generator's shape-count guard (audit D-0267); no swipl-devel counterpart.
# test/test_fuzz_shapes.jl — tools/fuzz_gen.jl produces the variable-link shapes it is meant to, and this file can tell.
#
# THE GUARD (CLAUDE.md: a guard is useless three ways). The shapes aim at fuzz seed 300945's class (a variable first met in a
# nested compound, later as a direct argument of the outer one: B_ARGVAR/H_VAR's link direction). A generator that quietly
# stopped producing one of them would leave the nightly green and the class unfuzzed. So over a FIXED seed range the number of
# cases of every shape, family, context and attribute mode is counted, ONE extractor (`fz_tags`, which re-derives the shape
# from the term text, never from the generator's own bookkeeping) serves both the generator's output and the doctored texts
# below, and every count must reach MIN. The EXPECTED names are written out here, not read from the generator's lists, so a
# name dropped from a list is a missing count, not a smaller loop. The extractor itself is proven able to fail on doctored
# texts (a wrong shape, a missing term, an absent predicate, a stray put_attr).
using Test, Random
include(joinpath(@__DIR__, "..", "tools", "fuzz_gen.jl"))
using .FuzzGen

const _FS_SEEDS = 1000:1199          # fixed: the counts below are a property of these 200 programs
# MEASURED over these seeds (1942 shape cases = 0.243 of 8000, per seed 3..17): shapes dn 1242, inter 1290, nd 1352 (both terms);
# families 146 (eq) .. 214 (copy_term); ctx goal 1171, head 771; attr before 167, mid 167, head 231, none 1377.
# MIN is 30, a fifth of the rarest: the guard's job is "present", not a ratio.
const _FS_MIN = 30
const _FS_SHAPES = ["nd", "dn", "inter"]
const _FS_PREDS = [
    "compare",
    "compare_vars",
    "msort",
    "sort4",
    "order",
    "eq",
    "copy_term",
    "term_variables",
    "bagof",
    "setof"
]
const _FS_CTX = ["goal", "head"]
const _FS_ATTR = ["none", "before", "mid", "head"]

_fs_tags(seeds, pct=SHAPE_PCT) = vcat((fz_tags(program(s, 40, pct)[1]) for s in seeds)...)
_fs_count(vals, name) = count(==(name), vals)

@testset "fuzz generator: the shapes are produced (D-0267)" begin
    tags = _fs_tags(_FS_SEEDS)
    @testset "every tag is borne out by its program" begin
        @test !isempty(tags)
        @test all(t -> t.ok, tags)
    end
    @testset "counts over seeds $(first(_FS_SEEDS)):$(last(_FS_SEEDS))" begin
        shapes = vcat([t.shape for t in tags], [t.shape2 for t in tags])    # both terms of every case
        for s in _FS_SHAPES
            @test _fs_count(shapes, s) >= _FS_MIN
        end
        for p in _FS_PREDS
            @test _fs_count([t.pred for t in tags], p) >= _FS_MIN
        end
        for c in _FS_CTX
            @test _fs_count([t.ctx for t in tags], c) >= _FS_MIN
        end
        for a in _FS_ATTR
            @test _fs_count([t.attr for t in tags], a) >= _FS_MIN
        end
        # nothing outside the expected names (a new family needs a line above, so it is counted too)
        @test Set(shapes) == Set(_FS_SHAPES)
        @test Set(t.pred for t in tags) == Set(_FS_PREDS)
        @test Set(t.ctx for t in tags) == Set(_FS_CTX)
        @test Set(t.attr for t in tags) == Set(_FS_ATTR)
        @test Set(AV_FAMILIES) == Set(_FS_PREDS)
        @test Set(AV_SHAPES) == Set(_FS_SHAPES)
        # a head case is a head clause and an attributed case with bagof/setof does not exist
        @test all(t -> t.attr == "none" || t.pred ∉ ("bagof", "setof"), tags)
        @test all(t -> t.attr ∈ ("none", "head") || t.ctx == "goal", tags)
        # the share of shape cases among the 40 cases of a seed stays the configured one, within sampling noise
        frac = length(tags) / (40 * length(_FS_SEEDS))
        @test 0.18 < frac < 0.32
    end
end

@testset "fuzz generator: the extractor reads shapes from the term, and can fail" begin
    # av_classes: the structural reading, on terms written out
    @test av_classes("f(g(Vb),g(Va),Va)") == Set(["nd"])          # seed 300945's term
    @test av_classes("f(Va,g(Va))") == Set(["dn"])
    @test av_classes("f(k(Va),Vb,Va,k(Vb))") == Set(["nd", "dn"])
    @test av_classes("f(g(Vb),Va)") == Set{String}()              # no variable twice
    @test av_classes("[k(Va),Va]") == Set(["nd"])                 # a list's elements are its arguments
    @test av_classes("f(g(Va,c),b)") == Set{String}()
    @test av_classes("Va") == Set{String}()
    # doctored programs: each one must turn a good tag bad
    good =
        "fzh3(f(g(Vb),g(Va),Va),f(k(Vc),Vc)).\n" *
        "t3(R) :- catch((fzh3(T1,T2), compare(O, T1, T2), R = O), E, R = ex(E)).  " *
        "%fz ctx=head shape=nd shape2=nd pred=compare attr=none ord=- terms=f(g(Vb),g(Va),Va);f(k(Vc),Vc)\n"
    @test [t.ok for t in fz_tags(good)] == [true]
    @test [t.ok for t in fz_tags(replace(good, "shape=nd shape2" => "shape=dn shape2"))] ==
        [false]      # wrong shape
    @test [
        t.ok for t in fz_tags(replace(good, "shape=nd shape2" => "shape=inter shape2"))
    ] == [false]
    @test [
        t.ok for
        t in fz_tags(replace(good, "fzh3(f(g(Vb),g(Va),Va)," => "fzh3(f(g(Vb),g(Va)),"))
    ] == [false]   # term absent from the head
    @test [t.ok for t in fz_tags(replace(good, "pred=compare" => "pred=msort"))] == [false]            # family absent from the goal
    @test [t.ok for t in fz_tags(replace(good, "attr=none" => "attr=before"))] == [false]               # attr claimed, no put_attr
    @test [
        t.ok for t in fz_tags(
            replace(good, "compare(O, T1, T2)" => "put_attr(Va, fz, 1), compare(O, T1, T2)")
        )
    ] == [false]   # put_attr unclaimed
    @test isempty(fz_tags(replace(good, "  %fz " => "  %xx ")))                                          # no tag, no case
end

@testset "fuzz generator: the generic stream is the old one" begin
    for s in (300945, 5000, 5001, _FS_SEEDS[1:5]...)
        text0, names0 = program(s, 40, 0)
        text, names = program(s, 40)
        @test names0 == names
        @test isempty(fz_tags(text0)) && !occursin("fzh", text0) && !occursin("%fz", text0)
        # every untagged case line of the default program is the pct=0 line
        l0 = filter(l -> startswith(l, "t"), split(text0, '\n'))
        l1 = filter(l -> startswith(l, "t") && !occursin("%fz", l), split(text, '\n'))
        @test issubset(l1, l0)
        @test length(l1) + length(fz_tags(text)) == 40
        @test program(s, 40) == (text, names)                                    # deterministic
    end
    # seed 300945's own failing line (t16: sort/4 over h(k(h(b,Vb,7)),[[Va,foo],Va],Va)) is still in the pct=0 program
    @test occursin(
        "sort(2, @>=, [k(a, h(k(h(b,Vb,7)),[[Va,foo],Va],Va))", program(300945, 40, 0)[1]
    )
end
