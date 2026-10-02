# ORIGINAL: the port-provenance gate and its fixture; no swipl-devel counterpart.
# test/test_port_check.jl — the swipl-devel mirror rule, run on LogicKernel AND proven able to fail.
#
# A FIXTURE builds a fake `swipl-devel` git repo and a kernel tree laid out as its mirror, plants one
# instance of every violation `tools/port_check.jl` exists to catch next to correct ports, and
# asserts the reported set is EXACTLY the planted set — every check fires on its case, none on a
# correct file. A clean fixture must pass, and must FAIL again after one deliberate mutation.
using Test, LogicKernel

include(joinpath(@__DIR__, "..", "tools", "port_check.jl"))
# At TOP LEVEL, not inside a testset: a method defined by an `include` that runs inside already-
# executing code is "too new" for that code to call (Julia 1.12+ world-age rule — measured here).
include(joinpath(@__DIR__, "..", "tools", "upstream_drift.jl"))

function _pc_git(dir, args...)
    run(
        pipeline(
            `git -C $dir -c user.email=t@t -c user.name=t $args`;
            stdout=devnull,
            stderr=devnull
        )
    )
end

"A fake upstream checkout; returns (dir, commit)."
function _pc_fake_upstream(base)
    up = joinpath(base, "swipl-devel")
    for d in ("src", "boot", "tests/core_lang")
        mkpath(joinpath(up, d))
    end
    write(
        joinpath(up, "src", "pl-fake.c"),
        """
/*  Part of a fixture
    Copyright (c)  2001-2026, Fixture University
                              Fixture Lab b.v.
*/
int
compareFoo(int a, int b)
{ return a - b; }
void
fooBar(int *v)
{ *v = 1; }
"""
    )
    for f in ("pl-nocopy.c", "pl-badcopy.c", "pl-noclass.c")
        write(
            joinpath(up, "src", f),
            "/* Copyright (c) 2020, Someone */\nint x(void) { return 0; }\n"
        )
    end
    write(joinpath(up, "boot", "tabling.pl"), "'\$tbl_add'(X) :- true.\n")
    write(joinpath(up, "tests", "core_lang", "test_fake.pl"),
        "/* Copyright (C): Fixture Tester */\n:- begin_tests(fake).\ntest(unit_a) :- true.\n:- end_tests(fake).\n"
    )
    write(joinpath(up, "tests", "core_lang", "test_shadow.pl"), "test(x) :- true.\n")
    _pc_git(up, "init", "-q")
    _pc_git(up, "add", "-A")
    _pc_git(up, "commit", "-qm", "fixture")
    sha = strip(read(`git -C $up rev-parse HEAD`, String))
    return up, String(sha)
end

_pc_write(root, rel, text) = (p=joinpath(root, rel); mkpath(dirname(p)); write(p, text))

function _pc_inventory(root, table)
    _pc_write(
        root,
        "docs/port_inventory.md",
        "# inv\n\n$INVENTORY_BEGIN\n$table\n$INVENTORY_END\n"
    )
end

"Clean ports at their mirrored paths: a code port, a design port with `as`, a ported test unit, an ORIGINAL."
function _pc_good_files(root, sha)
    _pc_write(
        root,
        "src/pl-fake.jl",
        """
# UPSTREAM: swipl-devel src/pl-fake.c @ $sha
# CLASS: code
# COPYRIGHT: Copyright (c)  2001-2026, Fixture University
# COPYRIGHT: Fixture Lab b.v.

# PORT: pl-fake.c compareFoo
\"\"\"docstring between marker and definition\"\"\"
function compareFoo(a::Int, b::Int)::Int
    return a - b
end

# PORT: pl-fake.c fooBar
fooBar!(v::Vector{Int}) = push!(v, 1)
"""
    )
    _pc_write(
        root,
        "boot/tabling.jl",
        """
# UPSTREAM: swipl-devel boot/tabling.pl @ $sha
# CLASS: design

# PORT: tabling.pl \$tbl_add as tbl_add
tbl_add(x) = x
"""
    )
    _pc_write(
        root,
        "test/core_lang/test_fake.jl",
        """
# UPSTREAM: swipl-devel tests/core_lang/test_fake.pl @ $sha
# CLASS: code
# COPYRIGHT: Copyright (C): Fixture Tester
using Test
@testset "fake" begin
    # PORT: test_fake.pl unit_a
    @testset "unit_a" begin
        @test true
    end
end
"""
    )
    _pc_write(
        root,
        "src/orig.jl",
        """
# ORIGINAL: fixture — no upstream counterpart.
helper(x) = x
const NOT_A_MARKER = \"\"\"
# PORT: pl-fake.c compareFoo
\"\"\"
"""
    )
end

_pc_codes(vs) = sort!([
    let p = split(v)
        (p[1], basename(rstrip(split(p[2], ":")[1], '/')))
    end for v in vs
])

@testset "port_check" begin
    @testset "LogicKernel follows the swipl-devel mirror rule" begin
        r = port_check(joinpath(@__DIR__, ".."))
        @test !isempty(r.files)                         # a scan of nothing proves nothing
        isempty(r.violations) ||
            foreach(v -> println(stderr, "  port_check: ", v), r.violations)
        @test isempty(r.violations)
        isempty(r.existence_checked) &&
            @info "port_check: no upstream checkout here — structure and inventory checked, upstream existence NOT (checked on local runs with ~/dev-zone/swipl-devel)"
    end

    mktempdir() do base
        up, sha = _pc_fake_upstream(base)
        dirs = Dict("swipl-devel" => up)

        @testset "fixture: reports exactly the planted violations" begin
            root = joinpath(base, "planted")
            _pc_good_files(root, sha)
            open(joinpath(root, "src/pl-fake.jl"), "a") do io
                write(
                    io,
                    """

          # PORT: pl-fake.c compareFoo
          notCompareFoo(x) = 3

          # PORT: pl-fake.c noSuchFn
          noSuchFn() = 1

          # PORT: pl-other.c fooBar
          fooBar(x) = x

          # PORT: pl-fake.c compareFoo
          # DIVERGES:
          compareFoo(x) = 2

          # PORT: broken

          # PORT: pl-fake.c fooBar
          """
                )
            end
            _pc_write(root, "src/nohead.jl", "f(x) = x\n")
            _pc_write(
                root,
                "src/pl-wrongname.jl",
                "# UPSTREAM: swipl-devel src/pl-fake.c @ $sha\n# CLASS: design\n"
            )
            _pc_write(root, "src/pl-orig.jl", "# ORIGINAL: named like a port\n")
            _pc_write(
                root,
                "src/orig2.jl",
                "# ORIGINAL: has a port in it\n# PORT: pl-fake.c compareFoo\ncompareFoo(x) = x\n"
            )
            _pc_write(root, "src/orig3.jl", "# ORIGINAL:\n")
            _pc_write(
                root,
                "src/orig4.jl",
                "# ORIGINAL: stray divergence\n# DIVERGES: from nothing\ng(x) = x\n"
            )
            _pc_write(
                root,
                "src/pl-nocopy.jl",
                "# UPSTREAM: swipl-devel src/pl-nocopy.c @ $sha\n# CLASS: code\n"
            )
            _pc_write(
                root,
                "src/pl-badcopy.jl",
                "# UPSTREAM: swipl-devel src/pl-badcopy.c @ $sha\n# CLASS: code\n# COPYRIGHT: Copyright (c) 1999, Nobody\n"
            )
            _pc_write(
                root,
                "src/pl-gone.jl",
                "# UPSTREAM: swipl-devel src/pl-gone.c @ $sha\n# CLASS: design\n"
            )
            _pc_write(
                root,
                "src/pl-badsha.jl",
                "# UPSTREAM: swipl-devel src/pl-badsha.c @ deadbeef\n# CLASS: design\n"
            )
            _pc_write(
                root,
                "src/unknownrepo.jl",
                "# UPSTREAM: notarepo src/unknownrepo.c @ $sha\n# CLASS: design\n"
            )
            _pc_write(
                root,
                "src/pl-noclass.jl",
                "# UPSTREAM: swipl-devel src/pl-noclass.c @ $sha\n"
            )
            _pc_write(
                root,
                "src/both.jl",
                "# ORIGINAL: confused\n# UPSTREAM: swipl-devel src/pl-fake.c @ $sha\n"
            )
            _pc_write(
                root,
                "src/terms/inner.jl",
                "# ORIGINAL: in a directory swipl-devel's src/ does not have\n"
            )
            _pc_write(
                root,
                "test/conformance/test_x.jl",
                "# ORIGINAL: in a tests area swipl-devel does not have\n"
            )
            _pc_write(root, "boot/orig.jl", "# ORIGINAL: boot/ holds ports only\n")
            _pc_write(
                root,
                "test/core_lang/test_shadow.jl",
                "# ORIGINAL: shadows an upstream test file\n"
            )
            _pc_inventory(root, "| stale | row |")

            r = port_check(root; upstream_dirs=dirs)
            @test r.existence_checked == ["swipl-devel"]
            expected = sort!([
                ("HEADER-MISSING", "nohead.jl"), ("PATH-MISMATCH", "pl-wrongname.jl"),
                ("DEF-MISMATCH", "pl-fake.jl"), ("UPSTREAM-NAME-MISSING", "pl-fake.jl"),
                ("MARKER-FILE-UNKNOWN", "pl-fake.jl"), ("DIVERGES-NO-REASON", "pl-fake.jl"),
                ("MARKER-ORPHAN", "pl-fake.jl"), ("MARKER-MALFORMED", "pl-fake.jl"),
                ("ORIGINAL-PORT-NAME", "pl-orig.jl"), ("ORIGINAL-HAS-PORT", "orig2.jl"),
                ("ORIGINAL-NO-REASON", "orig3.jl"), ("DIVERGES-ORPHAN", "orig4.jl"),
                ("COPYRIGHT-ABSENT", "pl-nocopy.jl"),
                ("COPYRIGHT-MISMATCH", "pl-badcopy.jl"),
                ("UPSTREAM-FILE-MISSING", "pl-gone.jl"), ("COMMIT-MISSING", "pl-badsha.jl"),
                ("UNKNOWN-REPO", "unknownrepo.jl"), ("PATH-MISMATCH", "unknownrepo.jl"),
                ("CLASS-MISSING", "pl-noclass.jl"), ("HEADER-BOTH", "both.jl"),
                ("DIR-NOT-UPSTREAM", "terms"), ("DIR-NOT-UPSTREAM", "conformance"),
                ("ORIGINAL-PORT-NAME", "orig.jl"),
                ("ORIGINAL-SHADOWS-UPSTREAM", "test_shadow.jl"),
                ("INVENTORY-DRIFT", "port_inventory.md")
            ])
            got = _pc_codes(r.violations)
            got == expected || foreach(v -> println(stderr, "  got: ", v), r.violations)
            @test got == expected
        end

        @testset "fixture: a clean mirror passes, and one mutation fails it" begin
            root = joinpath(base, "clean")
            _pc_good_files(root, sha)
            _pc_inventory(root, "")
            write_inventory(root)
            r = port_check(root; upstream_dirs=dirs)
            r.violations == String[] ||
                foreach(v -> println(stderr, "  clean: ", v), r.violations)
            @test isempty(r.violations)
            @test length(r.files) == 4
            inv = read(joinpath(root, "docs/port_inventory.md"), String)
            @test occursin("`src/pl-fake.jl` | 2 |", inv)
            @test occursin("`boot/tabling.jl` | 1 |", inv)
            @test occursin("`test/core_lang/test_fake.jl` | 1 |", inv)   # a ported TEST unit
            p = joinpath(root, "src/pl-fake.jl")
            write(
                p,
                replace(read(p, String), "function compareFoo(" => "function compare_foo(")
            )
            @test _pc_codes(port_check(root; upstream_dirs=dirs).violations) ==
                [("DEF-MISMATCH", "pl-fake.jl")]
        end

        @testset "upstream_drift: commits since the recorded one, and coverage" begin
            root = joinpath(base, "drift")
            _pc_good_files(root, sha)
            _pc_inventory(root, "")
            write_inventory(root)
            rows0 = upstream_drift(root; upstream_dirs=dirs)
            r0 = only(filter(r -> r.path == "src/pl-fake.c", rows0))
            @test isempty(r0.commits_since)
            @test r0.upstream_names == ["compareFoo", "fooBar"]
            @test r0.ported == ["compareFoo", "fooBar"]
            open(joinpath(up, "src", "pl-fake.c"), "a") do io
                write(io, "int\nnewFn(void)\n{ return 0; }\n")
            end
            _pc_git(up, "commit", "-qam", "upstream adds newFn")
            r1 = only(
                filter(
                    r -> r.path == "src/pl-fake.c", upstream_drift(root; upstream_dirs=dirs)
                )
            )
            @test length(r1.commits_since) == 1 &&
                occursin("upstream adds newFn", r1.commits_since[1])
            @test r1.upstream_names == ["compareFoo", "fooBar", "newFn"]
            @test r1.ported == ["compareFoo", "fooBar"]            # 2 of 3: newFn is the work list
            rt = only(filter(r -> r.path == "boot/tabling.pl", rows0))
            @test rt.upstream_names == ["\$tbl_add"] && rt.ported == ["\$tbl_add"]
        end
    end

    @testset "expected_path mirrors the upstream path" begin
        @test expected_path("swipl-devel", "src/pl-prims.c") == "src/pl-prims.jl"
        @test expected_path("swipl-devel", "boot/tabling.pl") == "boot/tabling.jl"
        @test expected_path("swipl-devel", "tests/core_lang/test_bips.pl") ==
            "test/core_lang/test_bips.jl"
        @test expected_path("scryer-prolog", "src/lib/tabling.pl") ==
            "scryer-prolog/src/lib/tabling.jl"
    end
end
