# ORIGINAL: package-level promises (standalone, 0.x); no swipl-devel counterpart.
# test/test_package.jl — what LogicKernel promises about ITSELF, before any subsystem lands.
#
# "Standalone" must be a tested property, not a claim about Project.toml. Two halves:
#   1. the [deps] table names nothing outside ALLOWED_DEPS — adding a dependency is a deliberate
#      act that edits this file, and a sibling package can never be one;
#   2. after `using LogicKernel`, no sibling package is LOADED — which also catches a dependency
#      that arrives some other way than the [deps] table.
# And one promise about the TESTS: every package a test file loads is declared for `Pkg.test`,
# whose environment is built from [extras] + [targets] ALONE. Locally the global environment is
# stacked under `--project=.`, so an undeclared stdlib resolves here and fails only in CI —
# measured twice: PathMap CI #87 (`Random`), and LogicKernel `8f0bead` (`Random` again).
using Test, LogicKernel

# ONE allowed dependency (user, 2026-10-03), and nothing else unless added deliberately, with a reason:
# PrecompileTools runs src/precompile_workload.jl at precompile time — a fresh process otherwise
# spent ~10 s compiling the hot paths before its first answer (measured).
const ALLOWED_DEPS = ("PrecompileTools",)
const SIBLINGS = ("MeTTaCore", "MORK", "PathMaps", "MorkSupercompiler")

"""Package names in the `[deps]` and `[extras]` tables of `file`, plus the `name`/`uuid` lines."""
function _project_deps(file::String)
    deps = String[]
    extras = String[]
    name = uuid = ""
    section = ""
    for raw in eachline(file)
        line = strip(raw)
        (isempty(line) || startswith(line, "#")) && continue
        if startswith(line, "[")
            section = line
            continue
        end
        m = match(r"^([A-Za-z0-9_]+)\s*=\s*\"([^\"]*)\"", line)
        m === nothing && continue
        if section == ""
            m[1] == "name" && (name = m[2])
            m[1] == "uuid" && (uuid = m[2])
        elseif section == "[deps]"
            push!(deps, m[1])
        elseif section == "[extras]"
            push!(extras, m[1])
        end
    end
    return (; deps, extras, name, uuid)
end

"""
The top-level packages the `using`/`import` statements in `ex` load: `using A, B: x` and
`import C.D` give `A`, `B`, `C`; a relative `using ..M` names no package.
"""
function _pkg_loads!(out::Set{Symbol}, ex)::Set{Symbol}
    ex isa Expr || return out
    if ex.head in (:using, :import)
        for a in ex.args
            p = a isa Expr && a.head === :(:) ? a.args[1] : a
            if p isa Expr && p.head === :. && !isempty(p.args) && p.args[1] isa Symbol &&
                p.args[1] !== :.
                push!(out, p.args[1])
            end
        end
        return out
    end
    foreach(a -> _pkg_loads!(out, a), ex.args)
    return out
end

"Loaded only by test/static_analysis_body.jl, which runs only where the tools are installed."
const ANALYSIS_TOOLS = (:JET, :Aqua, :AllocCheck)

@testset "package" begin
    @testset "Project.toml: no dependency on a sibling package" begin
        p = _project_deps(joinpath(pkgdir(LogicKernel), "Project.toml"))
        @test p.name == "LogicKernel"                 # parsed the RIGHT file, not an empty one
        @test occursin(r"^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", p.uuid)
        @test all(in(ALLOWED_DEPS), p.deps)
        @test isempty(intersect(p.deps, SIBLINGS))
    end

    @testset "runtime: no sibling package is loaded" begin
        loaded = Set(string(k.name) for k in keys(Base.loaded_modules))
        @test "LogicKernel" in loaded                 # positive control: the check can see a load
        @test isempty(intersect(loaded, SIBLINGS))
    end

    @testset "every package a test file loads is declared for Pkg.test" begin
        root = pkgdir(LogicKernel)
        p = _project_deps(joinpath(root, "Project.toml"))
        @test "Test" in p.extras                      # parsed the [extras] table at all
        declared = Set(
            Symbol.(vcat(p.deps, p.extras, ["LogicKernel", "Base", "Core", "Main"]))
        )
        # controls: the scan sees every form, and flags an undeclared stdlib
        @test _pkg_loads!(
            Set{Symbol}(),
            Meta.parseall("using Random\nimport Foo.Bar\nusing A: x\nusing ..M")
        ) ==
            Set([:Random, :Foo, :A])
        @test :Random in setdiff(
            _pkg_loads!(Set{Symbol}(), Meta.parseall("using Random")), Set([:Test])
        )
        bad = String[]
        nfiles = 0
        for dir in ("test", "bench"),
            (d, _, fs) in walkdir(joinpath(root, dir)),
            f in sort(fs)

            endswith(f, ".jl") || continue
            nfiles += 1
            path = joinpath(d, f)
            ok = f == "static_analysis_body.jl" ? union(declared, ANALYSIS_TOOLS) : declared
            for m in
                setdiff(_pkg_loads!(Set{Symbol}(), Meta.parseall(read(path, String))), ok)
                push!(bad, "$(relpath(path, root)): `$m` is not in [extras]")
            end
        end
        @test nfiles > 20                             # the walk saw the suite
        isempty(bad) ||
            foreach(b -> println(stderr, "  undeclared test dependency: ", b), bad)
        @test isempty(bad)
    end

    @testset "version is 0.x until the interface meets its second consumer" begin
        @test pkgversion(LogicKernel).major == 0
    end
end
