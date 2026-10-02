# test/test_package.jl — what LogicKernel promises about ITSELF, before any subsystem lands.
#
# "Standalone" must be a tested property, not a claim about Project.toml. Two halves:
#   1. the [deps] table names nothing outside ALLOWED_DEPS — adding a dependency is a deliberate
#      act that edits this file, and a sibling package can never be one;
#   2. after `using LogicKernel`, no sibling package is LOADED — which also catches a dependency
#      that arrives some other way than the [deps] table.
using Test, LogicKernel

const ALLOWED_DEPS = ()    # none: the kernel depends on nothing
const SIBLINGS = ("MeTTaCore", "MORK", "PathMaps", "MorkSupercompiler")

"""Package names in the `[deps]` table of `file`, plus the `name`/`uuid` lines seen."""
function _project_deps(file::String)
    deps = String[]
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
        end
    end
    return (; deps, name, uuid)
end

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

    @testset "version is 0.x until the interface meets its second consumer" begin
        @test pkgversion(LogicKernel).major == 0
    end
end
