# ORIGINAL: the kernel's home tree (R2 LB4 chunk a, design evidence/r2/design/loader_boot.md LD6) — no swipl-devel counterpart; the shape is cmake/InstallSource.cmake:8-25.
# test/test_home_tree.jl — tools/build_home.jl builds the tree of relative links the `home` flag names: home/boot/<f>.pl and
# home/library/<path> link each vendored file (vendor/swipl-devel), home/library/ext/plunit links packages/plunit. Rows: every link
# is relative and resolves to its vendored file; the set of links is EXACTLY the vendored files plus ext/plunit (one extractor for the
# wanted set and the found set, both non-empty); a stale tree is repaired (a link with another target, a link nothing wants, a
# missing link, a missing ext/plunit link, an empty directory left behind) and a second build changes nothing; a real file in
# the tree is an error and is not deleted.
using Test

const _HT_ROOT = joinpath(@__DIR__, "..")
include(joinpath(_HT_ROOT, "tools", "build_home.jl"))
const _HT_VENDOR = joinpath(_HT_ROOT, "vendor", "swipl-devel")

"Every file under `dir`, relative to it, as a sorted `/`-joined list (links are not followed)."
function _ht_files(dir::String)::Vector{String}
    out = String[]
    for (d, _, files) in walkdir(dir)
        append!(out, relpath(joinpath(d, f), dir) for f in files)
    end
    return sort!(out)
end

"Every link under `home` (a link to a directory included, not followed): relative path => the link's text."
function _ht_links(home::String)::Dict{String, String}
    out = Dict{String, String}()
    for (d, dirs, files) in walkdir(home)
        for e in vcat(dirs, files)
            p = joinpath(d, e)
            islink(p) && (out[relpath(p, home)] = readlink(p))
        end
    end
    return out
end

"The links the vendored tree calls for, found by this file's own extractor: boot/ and library/ files, and ext/plunit."
function _ht_wanted()::Vector{String}
    want = String[]
    for top in ("boot", "library"), f in _ht_files(joinpath(_HT_VENDOR, top))
        push!(want, joinpath(top, f))
    end
    push!(want, joinpath("library", "ext", "plunit"))
    return sort!(want)
end

mktempdir() do tmp
    home = joinpath(tmp, "home")
    want = _ht_wanted()

    @testset "the home tree: relative links, one per vendored file, ext/plunit" begin
        @test build_home(home) == home
        links = _ht_links(home)
        # NON-VACUITY: 26 boot files + 210 library files + 5 INDEX.pl + ext/plunit
        @test length(want) == 26 + 210 + 5 + 1
        @test !isempty(links)
        @test sort!(collect(keys(links))) == want       # nothing missing, nothing extra
        for (rel, text) in links
            @test !isabspath(text)                      # relative, as cmake's symlink() makes them
            target = joinpath(home, dirname(rel), text)
            if rel == joinpath("library", "ext", "plunit")
                @test isdir(target)
                @test realpath(target) == realpath(joinpath(_HT_ROOT, "packages", "plunit"))
            else
                @test isfile(target)                    # the link resolves
                @test realpath(target) == realpath(joinpath(_HT_VENDOR, rel))
            end
        end
        # the files init.pl finds through its own search paths
        @test isfile(joinpath(home, "boot", "init.pl"))
        @test isfile(joinpath(home, "library", "lists.pl"))
        @test isfile(joinpath(home, "library", "INDEX.pl"))
        @test isfile(joinpath(home, "library", "dcg", "basics.pl"))
        @test isfile(joinpath(home, "library", "ext", "plunit", "plunit.pl"))
        # the content read through the tree is the vendored file's
        @test read(joinpath(home, "boot", "init.pl")) ==
            read(joinpath(_HT_VENDOR, "boot", "init.pl"))
        # directories are real: nothing was written into vendor/
        @test !islink(joinpath(home, "library")) && !islink(joinpath(home, "boot"))
        vendored = String[
            joinpath(top, f) for top in ("boot", "library") for
            f in _ht_files(joinpath(_HT_VENDOR, top))
        ]
        @test _ht_files(_HT_VENDOR) == sort!(vcat(vendored, ["LICENSE", "PIN"]))
    end

    @testset "a second build changes nothing" begin
        before = _ht_links(home)
        @test build_home(home) == home
        @test _ht_links(home) == before
    end

    @testset "a stale tree is repaired" begin
        good = _ht_links(home)
        @test !isempty(good)
        lists = joinpath(home, "library", "lists.pl")
        init = joinpath(home, "boot", "init.pl")
        plunit = joinpath(home, "library", "ext", "plunit")
        # a link with another target
        rm(lists)
        symlink(joinpath("..", "boot", "init.pl"), lists)
        @test readlink(lists) != good[joinpath("library", "lists.pl")]
        # a link nothing wants, in a directory nothing wants
        mkpath(joinpath(home, "library", "stale", "deeper"))
        symlink(joinpath("..", "..", "..", "boot", "init.pl"),
            joinpath(home, "library", "stale", "deeper", "x.pl"))
        symlink(joinpath("..", "library", "lists.pl"), joinpath(home, "boot", "extra.pl"))
        # a missing link, a missing ext/plunit link
        rm(init)
        rm(plunit)
        @test !ispath(init) && !islink(init)
        @test !islink(plunit)
        @test _ht_links(home) != good
        @test build_home(home) == home
        @test _ht_links(home) == good
        @test !ispath(joinpath(home, "library", "stale"))      # the directory left empty is gone too
        @test isfile(init) && isfile(lists) && isdir(plunit)
        @test realpath(lists) == realpath(joinpath(_HT_VENDOR, "library", "lists.pl"))
    end

    @testset "a real file in the tree is an error and is kept" begin
        mine = joinpath(home, "library", "mine.pl")
        write(mine, "% not ours\n")
        @test_throws ErrorException build_home(home)
        @test isfile(mine) && !islink(mine)
        rm(mine)
        @test build_home(home) == home
    end

    @testset "the default place is home in the package directory" begin
        @test home_dir() == normpath(joinpath(_HT_ROOT, "home"))
    end
end
