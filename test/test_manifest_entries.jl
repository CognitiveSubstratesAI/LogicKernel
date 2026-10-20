# ORIGINAL: the static-analysis manifest's CONVERSION, unit-tested (2026-10-20) — no swipl-devel counterpart.
# test/test_manifest_entries.jl — `_manifest_entries` (test/static_analysis_manifest.jl), the function
# that turns the manifest's tuple of `(f, argument types, must_not_allocate)` into the vector the gate
# walks, checked on a small sample: every entry kept, in order, each with its OWN allocation flag. It
# needs no analysis tool, so it runs in every suite, in seconds. MEASURED 2026-10-20 (the Tooling2
# re-run): mutants of this conversion were caught only by test_static_analysis.jl's AllocCheck pass —
# and "every entry allocation-free" ran past an hour there.
using Test, LogicKernel
include(joinpath(@__DIR__, "static_analysis_manifest.jl"))

@testset "_manifest_entries: every entry, in order, with its own allocation flag" begin
    sample = (
        (sin, Tuple{Float64}, true), (push!, Tuple{Vector{Int}, Int}, false),
        (cos, Tuple{Float64}, false)
    )
    es = _manifest_entries(sample)
    @test es isa Vector{ManifestEntry} && length(es) == 3
    @test [e.f for e in es] == Any[sin, push!, cos]
    @test [e.tt for e in es] == Any[Tuple{Float64}, Tuple{Vector{Int}, Int}, Tuple{Float64}]
    @test [e.noalloc for e in es] == [true, false, false]
    (f, tt, noalloc) = es[2]                        # an entry destructures as its tuple did
    @test (f, tt, noalloc) == (push!, Tuple{Vector{Int}, Int}, false) && es[2][3] === false
    @test_throws TypeError _manifest_entries(((sin, Tuple{Float64}),))
    # the real manifest: one entry per tuple element, and both flags present
    @test length(DISPATCH_MANIFEST) == nfields(_DISPATCH_MANIFEST_TUPLE)
    @test any(e -> e.noalloc, DISPATCH_MANIFEST) && any(e -> !e.noalloc, DISPATCH_MANIFEST)
end
