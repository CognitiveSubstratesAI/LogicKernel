# ORIGINAL: the kernel's home tree (R2 LB4 chunk a, design evidence/r2/design/loader_boot.md LD6) — no swipl-devel counterpart; the shape is cmake/InstallSource.cmake:8-25.
# tools/build_home.jl — builds (or repairs) the HOME TREE the `home` flag names: a tree of relative symbolic links, as swipl's build home is
# (cmake/InstallSource.cmake `symlink`: `ln -s` of the path relative to the link's own directory), over the vendored files:
#
#     home/boot/<f>.pl          -> vendor/swipl-devel/boot/<f>.pl         (one link per file; directories are real)
#     home/library/<path>       -> vendor/swipl-devel/library/<path>      (one link per file, INDEX.pl files included)
#     home/library/ext/plunit   -> packages/plunit                        (the directory itself: library(plunit) resolves through boot/init.pl's
#                                                                          '$ext_library_directory', no file_search_path/2 clause of ours)
#
#     home/library/ext/<pkg>/<f> -> vendor/swipl-devel-extra/packages/<pkg>/<f>   (the vendored pure-Prolog packages clpqr, paxos, chr, cql,
#     home/library/ext/<pkg>/<sub>/<f> -> .../packages/<pkg>/<srcdir>/<f>         pldoc: one link per file, as the package's CMakeLists.txt
#                                                                          `swipl_plugin(... PL_LIB_SUBDIR <sub> PL_LIBS <files>)` installs it)
#
# Directories are real and files are links, because `ext/plunit` must sit INSIDE library/ without writing into vendor/.
# The tree is gitignored (/home); `build_home(dest)` brings any state to the wanted one: a missing link is made, a link to another target
# is replaced, a link nothing wants is removed, a directory left empty by that is removed. A REAL FILE in the tree is never deleted: it is
# an error (the destination is not ours). Julia 1.13, no packages; run it as `julia tools/build_home.jl [dest]`.

const _BH_ROOT = normpath(joinpath(@__DIR__, ".."))
const _BH_VENDOR = joinpath(_BH_ROOT, "vendor", "swipl-devel")
const _BH_PLUNIT = joinpath(_BH_ROOT, "packages", "plunit")
const _BH_EXTRA = joinpath(_BH_ROOT, "vendor", "swipl-devel-extra")
const _BH_DIRS = ("boot", "library")

"`names` as `link name => source name` pairs (the two are the same file name unless a row says otherwise)."
_bh_same(names::String...) = Pair{String, String}[n => n for n in names]

"""
The library layout of each vendored pure-Prolog package, read from `packages/<pkg>/CMakeLists.txt` (`swipl_plugin`): rows
`(pkg, subdir, srcdir, files)` — `home/library/ext/<pkg>/<subdir>/<link name>` links `packages/<pkg>/<srcdir>/<source name>`.
NOT linked, on purpose: chr's two GENERATED files (`chr_translate.pl`, `guard_entailment.pl`: swipl bootstraps them from the .chr
sources; they are not vendored), so `library(chr)` loads only once they exist; `chr.pl` is upstream's `chr_swi.pl` (CMake copies it);
pldoc's `doc_changes.pl`/`git_extract_changes.pl` belong to the CHANGELOG option and `doc_csssrc.pl` is not installed.
"""
const _BH_PKG_LIBS = Tuple{String, String, String, Vector{Pair{String, String}}}[
    ("clpqr", "", "", _bh_same("clpr.pl", "clpq.pl")),
    ("clpqr", "clpq", "clpq", _bh_same("bb_q.pl", "bv_q.pl", "fourmotz_q.pl", "ineq_q.pl", "itf_q.pl", "nf_q.pl", "store_q.pl")),
    ("clpqr", "clpr", "clpr", _bh_same("bb_r.pl", "bv_r.pl", "fourmotz_r.pl", "ineq_r.pl", "itf_r.pl", "nf_r.pl", "store_r.pl")),
    ("clpqr", "clpqr", "clpqr", _bh_same("class.pl", "dump.pl", "geler.pl", "itf.pl", "ordering.pl", "project.pl", "redund.pl", "highlight.pl")),
    ("paxos", "", "", _bh_same("paxos.pl")),
    ("chr", "", "", ["chr.pl" => "chr_swi.pl"]),
    ("chr", "chr", "", _bh_same("chr_runtime.pl", "chr_op.pl", "chr_debug.pl", "chr_messages.pl", "pairlist.pl", "clean_code.pl", "find.pl", "a_star.pl", "binomialheap.pl", "builtins.pl", "chr_hashtable_store.pl", "listmap.pl", "chr_compiler_options.pl", "chr_compiler_utility.pl", "chr_compiler_errors.pl", "chr_integertable_store.pl")),
    ("cql", "cql", "", _bh_same("cql.pl", "sql_parser.pl", "sql_tokenizer.pl", "sql_write.pl", "sql_keywords.pl", "cql_database.pl", "cql_autoschema.pl", "cql_hooks.pl")),
    ("pldoc", "", "", _bh_same("pldoc.pl", "doc_latex.pl", "doc_files.pl", "doc_markdown.pl", "doc_http.pl")),
    ("pldoc", "pldoc", "", _bh_same("doc_html.pl", "doc_wiki.pl", "doc_modes.pl", "doc_register.pl", "doc_process.pl", "doc_index.pl", "doc_search.pl", "doc_man.pl", "doc_library.pl", "hooks.pl", "doc_htmlsrc.pl", "doc_colour.pl", "doc_util.pl", "doc_access.pl", "doc_pack.pl", "man_index.pl", "doc_words.pl", "pldoc.css", "pldoc.js", "pllisting.css", "pldoc.sty", "edit.png", "private.png", "public.png", "reload.png", "favicon.ico", "up.gif", "source.png", "h1-bg.png", "pub-bg.png", "multi-bg.png", "priv-bg.png", "h2-bg.png", "editpred.png")),
]

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
    plunit::String=_BH_PLUNIT,
    extra::String=_BH_EXTRA
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
    for (pkg, sub, srcdir, files) in _BH_PKG_LIBS, (name, src) in files
        link = joinpath(home, "library", "ext", pkg, sub, name)
        target = joinpath(extra, "packages", pkg, srcdir, src)
        isfile(target) || error("build_home: $target is not vendored (package $pkg)")
        want[link] = relpath(target, dirname(link))
    end
    return want
end

"Build or repair the home tree at `home`; returns `home`."
function build_home(
    home::String=home_dir();
    vendor::String=_BH_VENDOR,
    plunit::String=_BH_PLUNIT,
    extra::String=_BH_EXTRA
)::String
    isdir(joinpath(vendor, "boot")) ||
        error("build_home: no $vendor/boot (the vendored swipl-devel is not there)")
    isdir(plunit) || error("build_home: no $plunit (the vendored plunit is not there)")
    isdir(extra) || error("build_home: no $extra (the vendored swipl-devel-extra is not there)")
    home = String(rstrip(abspath(home), '/'))
    want = home_links(home; vendor, plunit, extra)
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
