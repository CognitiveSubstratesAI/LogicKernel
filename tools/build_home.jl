# ORIGINAL: the kernel's home tree (R2 LB4 chunk a, design evidence/r2/design/loader_boot.md LD6) — no swipl-devel counterpart; the shape is cmake/InstallSource.cmake:8-25.
# tools/build_home.jl — builds (or repairs) the HOME TREE the `home` flag names: a tree of relative symbolic links, as swipl's build home is
# (cmake/InstallSource.cmake `symlink`: `ln -s` of the path relative to the link's own directory), over the vendored files:
#
#     home/boot/<f>.pl          -> vendor/swipl-devel/boot/<f>.pl         (one link per file; directories are real)
#     home/library/<path>       -> vendor/swipl-devel/library/<path>      (one link per file, INDEX.pl files included)
#     home/library/ext/plunit   -> packages/plunit                        (the directory itself: library(plunit) resolves through boot/init.pl's
#                                                                          '$ext_library_directory', no file_search_path/2 clause of ours)
#
# Directories are real and files are links, because `ext/plunit` must sit INSIDE library/ without writing into vendor/.
# The tree is gitignored (/home); `build_home(dest)` brings any state to the wanted one: a missing link is made, a link to another target
# is replaced, a link nothing wants is removed, a directory left empty by that is removed. A REAL FILE in the tree is never deleted: it is
# an error (the destination is not ours). Julia 1.13, no packages; run it as `julia tools/build_home.jl [dest]`.

const _BH_ROOT = normpath(joinpath(@__DIR__, ".."))
const _BH_VENDOR = joinpath(_BH_ROOT, "vendor", "swipl-devel")
const _BH_PLUNIT = joinpath(_BH_ROOT, "packages", "plunit")
const _BH_DIRS = ("boot", "library")

"The home tree's default place: `home` in the package directory (src/os/pl-prologflag.jl's `home` flag names the same path)."
home_dir()::String = joinpath(_BH_ROOT, "home")

"Every file under `dir`, relative to it (links are not followed)."
function _bh_files(dir::String)::Vector{String}
    out = String[]
    for (d, _, files) in walkdir(dir)
        for f in files
            push!(out, relpath(joinpath(d, f), dir))
        end
    end
    return sort!(out)
end

"The wanted links: absolute link path => the link's text (the target relative to the link's directory)."
function home_links(
    home::String;
    vendor::String=_BH_VENDOR,
    plunit::String=_BH_PLUNIT
)::Dict{String, String}
    want = Dict{String, String}()
    for top in _BH_DIRS
        for rel in _bh_files(joinpath(vendor, top))
            link = joinpath(home, top, rel)
            want[link] = relpath(joinpath(vendor, top, rel), dirname(link))
        end
    end
    ext = joinpath(home, "library", "ext", "plunit")
    want[ext] = relpath(plunit, dirname(ext))
    return want
end

"Build or repair the home tree at `home`; returns `home`."
function build_home(
    home::String=home_dir();
    vendor::String=_BH_VENDOR,
    plunit::String=_BH_PLUNIT
)::String
    isdir(joinpath(vendor, "boot")) ||
        error("build_home: no $vendor/boot (the vendored swipl-devel is not there)")
    isdir(plunit) || error("build_home: no $plunit (the vendored plunit is not there)")
    home = String(rstrip(abspath(home), '/'))
    want = home_links(home; vendor, plunit)
    dirs = Set{String}([home])
    for link in keys(want)
        d = dirname(link)
        while d != home && !(d in dirs)
            push!(dirs, d)
            d = dirname(d)
        end
    end
    if ispath(home)
        # 1. remove what nothing wants: a link with another text, a link not wanted, a directory not wanted and empty
        for (d, subdirs, files) in walkdir(home; topdown=false)
            for e in files
                p = joinpath(d, e)
                islink(p) ||
                    error("build_home: $p is a file, not a link: $home is not a home tree")
                get(want, p, nothing) == readlink(p) || rm(p)
            end
            # walkdir (follow_symlinks=false) lists EVERY symlink in `files`, a link to a directory included: `subdirs`
            # holds real directories only
            for e in subdirs
                p = joinpath(d, e)
                if !(p in dirs) && isempty(readdir(p))
                    rm(p)
                end
            end
        end
    end
    # 2. make what is missing
    mkpath(home)
    for (link, text) in sort!(collect(want))
        islink(link) && continue
        ispath(link) && error("build_home: $link is in the way of a link")
        mkpath(dirname(link))
        symlink(text, link)
    end
    return home
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(build_home(ARGS...))
end
