# ORIGINAL: the kernel's home tree (R2 LB4 chunk a, design evidence/r2/design/loader_boot.md LD6) — no swipl-devel counterpart; the shape is cmake/InstallSource.cmake:8-25.
# test/test_home_tree.jl — tools/build_home.jl builds the tree of relative links the `home` flag names: home/boot/<f>.pl and
# home/library/<path> link each vendored file (vendor/swipl-devel), home/library/ext/plunit links packages/plunit, and
# home/library/ext/<pkg>/... links each installed file of the vendored packages (vendor/swipl-devel-extra: clpqr, paxos, chr,
# cql, pldoc, json; the layout is the one each package's CMakeLists.txt `swipl_plugin` installs). Rows: every link
# is relative and resolves to its vendored file; the set of links is EXACTLY the vendored files plus ext/plunit plus the package files (one extractor for the
# wanted set and the found set, both non-empty); a stale tree is repaired (a link with another target, a link nothing wants, a
# missing link, an ext/plunit link with another target, an empty directory left behind) and a second build changes nothing; a real file in
# the tree is an error and is not deleted.
using Test

const _HT_ROOT = joinpath(@__DIR__, "..")
include(joinpath(_HT_ROOT, "tools", "build_home.jl"))
const _HT_VENDOR = joinpath(_HT_ROOT, "vendor", "swipl-devel")
const _HT_EXTRA = joinpath(_HT_ROOT, "vendor", "swipl-devel-extra")

# The installed files of each vendored package, DERIVED from packages/<pkg>/CMakeLists.txt (`swipl_plugin(<pkg> PL_LIBS ... PL_LIB_SUBDIR
# <sub> PL_LIBS ...)`, the `set()` lists they name, `prepend(... <srcdir>/ ...)`): (pkg, link subdir under library/ext/<pkg>, source
# directory under packages/<pkg>, the file names; `link=source` where upstream copies a file under another name). NOT here: chr's two
# generated files (chr_translate.pl, guard_entailment.pl: bootstrapped by swipl, not vendored).
const _HT_PKGS = [
    ("clpqr", "", "", "clpr.pl clpq.pl"),
    ("clpqr", "clpq", "clpq", "bb_q.pl bv_q.pl fourmotz_q.pl ineq_q.pl itf_q.pl nf_q.pl store_q.pl"),
    ("clpqr", "clpr", "clpr", "bb_r.pl bv_r.pl fourmotz_r.pl ineq_r.pl itf_r.pl nf_r.pl store_r.pl"),
    ("clpqr", "clpqr", "clpqr", "class.pl dump.pl geler.pl itf.pl ordering.pl project.pl redund.pl highlight.pl"),
    ("paxos", "", "", "paxos.pl"),
    ("chr", "", "", "chr.pl=chr_swi.pl"),
    ("chr", "chr", "", "chr_runtime.pl chr_op.pl chr_debug.pl chr_messages.pl pairlist.pl clean_code.pl find.pl a_star.pl binomialheap.pl builtins.pl chr_hashtable_store.pl listmap.pl chr_compiler_options.pl chr_compiler_utility.pl chr_compiler_errors.pl chr_integertable_store.pl"),
    ("cql", "cql", "", "cql.pl sql_parser.pl sql_tokenizer.pl sql_write.pl sql_keywords.pl cql_database.pl cql_autoschema.pl cql_hooks.pl"),
    ("pldoc", "", "", "pldoc.pl doc_latex.pl doc_files.pl doc_markdown.pl doc_http.pl"),
    ("pldoc", "pldoc", "", "doc_html.pl doc_wiki.pl doc_modes.pl doc_register.pl doc_process.pl doc_index.pl doc_search.pl doc_man.pl doc_library.pl hooks.pl doc_htmlsrc.pl doc_colour.pl doc_util.pl doc_access.pl doc_pack.pl man_index.pl doc_words.pl pldoc.css pldoc.js pllisting.css pldoc.sty edit.png private.png public.png reload.png favicon.ico up.gif source.png h1-bg.png pub-bg.png multi-bg.png priv-bg.png h2-bg.png editpred.png"),
    ("json", "", "", "json.pl json_convert.pl json_grammar.pl json_rpc_common.pl json_schema.pl json_rpc_server.pl json_rpc_client.pl"),
    ("json", "http", "", "http_json.pl"),
    ("json", "http", "compat", "json.pl json_convert.pl js_grammar.pl"),
]

"The links of `_HT_PKGS` relative to `home`, `link path => (package, source path under packages/<pkg>)`."
function _ht_pkg_links()::Dict{String, Tuple{String, String}}
    out = Dict{String, Tuple{String, String}}()
    for (pkg, sub, srcdir, names) in _HT_PKGS, n in split(names)
        name, src = occursin('=', n) ? String.(split(n, '=')) : (n, n)
        out[joinpath("library", "ext", pkg, sub, name)] = (pkg, joinpath(srcdir, src))
    end
    return out
end

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

"The links the vendored tree calls for, found by this file's own extractor: boot/ and library/ files, ext/plunit and the package files."
function _ht_wanted()::Vector{String}
    want = String[]
    for top in ("boot", "library"), f in _ht_files(joinpath(_HT_VENDOR, top))
        push!(want, joinpath(top, f))
    end
    push!(want, joinpath("library", "ext", "plunit"))
    append!(want, keys(_ht_pkg_links()))
    return sort!(want)
end

mktempdir() do tmp
    home = joinpath(tmp, "home")
    want = _ht_wanted()

    @testset "the home tree: relative links, one per vendored file, ext/plunit, the packages' files" begin
        @test build_home(home) == home
        links = _ht_links(home)
        pkgs = _ht_pkg_links()
        # NON-VACUITY: 26 boot files + 210 library files + 5 INDEX.pl + ext/plunit + 100 package files
        @test length(want) == 26 + 210 + 5 + 1 + 100
        @test length(_ht_pkg_links()) == 100
        @test !isempty(links)
        @test sort!(collect(keys(links))) == want       # nothing missing, nothing extra
        for (rel, text) in links
            @test !isabspath(text)                      # relative, as cmake's symlink() makes them
            target = joinpath(home, dirname(rel), text)
            if rel == joinpath("library", "ext", "plunit")
                @test isdir(target)
                @test realpath(target) == realpath(joinpath(_HT_ROOT, "packages", "plunit"))
            elseif haskey(pkgs, rel)
                pkg, src = pkgs[rel]
                @test isfile(target)
                @test realpath(target) == realpath(joinpath(_HT_EXTRA, "packages", pkg, src))
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
        @test isfile(joinpath(home, "library", "ext", "clpqr", "clpq.pl"))
        @test isfile(joinpath(home, "library", "ext", "clpqr", "clpq", "bb_q.pl"))
        @test isfile(joinpath(home, "library", "ext", "paxos", "paxos.pl"))
        @test isfile(joinpath(home, "library", "ext", "chr", "chr.pl"))
        @test isfile(joinpath(home, "library", "ext", "chr", "chr", "chr_runtime.pl"))
        @test isfile(joinpath(home, "library", "ext", "cql", "cql", "cql.pl"))
        @test isfile(joinpath(home, "library", "ext", "pldoc", "pldoc.pl"))
        @test isfile(joinpath(home, "library", "ext", "pldoc", "pldoc", "doc_html.pl"))
        @test isfile(joinpath(home, "library", "ext", "json", "json.pl"))
        @test isfile(joinpath(home, "library", "ext", "json", "http", "http_json.pl"))
        @test isfile(joinpath(home, "library", "ext", "json", "http", "json.pl"))
        # chr's generated files are not vendored, so not linked (they come with the oracle bootstrap)
        @test !ispath(joinpath(home, "library", "ext", "chr", "chr", "chr_translate.pl"))
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

    # THE DERIVATION: every file name of the table is named by its package's CMakeLists.txt (a table that
    # lists a file upstream does not install, or misspells one, fails here), and its source is vendored.
    @testset "the package table is what the packages' CMakeLists.txt install" begin
        for (pkg, sub, srcdir, names) in _HT_PKGS, n in split(names)
            name, src = occursin('=', n) ? String.(split(n, '=')) : (n, n)
            cmake = read(joinpath(_HT_EXTRA, "packages", pkg, "CMakeLists.txt"), String)
            @test occursin(src, cmake)
            @test isfile(joinpath(_HT_EXTRA, "packages", pkg, srcdir, src))
            sub == "" || @test occursin(sub, cmake)
        end
        @test sort!(unique([r[1] for r in _HT_PKGS])) == ["chr", "clpqr", "cql", "json", "paxos", "pldoc"]
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
        paxos = joinpath(home, "library", "ext", "paxos", "paxos.pl")
        # a package link with another target, and one missing
        rm(paxos)
        symlink(joinpath("..", "..", "..", "boot", "init.pl"), paxos)
        doc_html = joinpath(home, "library", "ext", "pldoc", "pldoc", "doc_html.pl")
        rm(doc_html)
        @test readlink(paxos) != good[joinpath("library", "ext", "paxos", "paxos.pl")]
        @test !islink(doc_html)
        # a link with another target
        rm(lists)
        symlink(joinpath("..", "boot", "init.pl"), lists)
        @test readlink(lists) != good[joinpath("library", "lists.pl")]
        # a link nothing wants, in a directory nothing wants
        mkpath(joinpath(home, "library", "stale", "deeper"))
        symlink(joinpath("..", "..", "..", "boot", "init.pl"),
            joinpath(home, "library", "stale", "deeper", "x.pl"))
        symlink(joinpath("..", "library", "lists.pl"), joinpath(home, "boot", "extra.pl"))
        # a missing link, and an ext/plunit link with another target (a link to a directory: walkdir lists it in `files`, so the same removal row as any link)
        rm(init)
        rm(plunit)
        symlink(joinpath("..", "..", "boot"), plunit)
        @test !ispath(init) && !islink(init)
        @test readlink(plunit) != good[joinpath("library", "ext", "plunit")]
        @test _ht_links(home) != good
        @test build_home(home) == home
        @test _ht_links(home) == good
        @test !ispath(joinpath(home, "library", "stale"))      # the directory left empty is gone too
        @test isfile(init) && isfile(lists) && isdir(plunit) && isfile(paxos) && isfile(doc_html)
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
