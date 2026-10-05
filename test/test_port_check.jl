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
struct foo_rec
{ int a; };
#define FOO_MAX 4
typedef enum { FOO_A, FOO_B } foo_kind;
#define foo_twice(x) ((x)*2)
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

"""
The fixture's docs: the inventory (`table` in its generated section, an empty coverage section) and
an architecture document whose "What is here now" table lists the clean src/ files and whose code
graph section is empty — `write_inventory` fills the generated sections.
"""
function _pc_inventory(root, table)
    _pc_write(
        root,
        "docs/port_inventory.md",
        "# inv\n\n$INVENTORY_BEGIN\n$table\n$INVENTORY_END\n\n$COVERAGE_BEGIN\n$COVERAGE_END\n"
    )
    _pc_write(
        root,
        "docs/architecture.md",
        """
# arch

$WHATS_HERE_HEADING

| file | what | upstream |
|---|---|---|
| `src/LogicKernel.jl` | the entry file | — |
| `src/orig.jl` | a helper | — |
| `src/pl-fake.jl` | the fake port | `src/pl-fake.c` |

## Code graph

$GRAPH_BEGIN
$GRAPH_END
"""
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

# PORT: pl-fake.c foo_rec
mutable struct foo_rec{T} <: Number
    a::T
end

# PORT: pl-fake.c FOO_MAX
"a ported constant, docstring between marker and definition"
const FOO_MAX = 4

# PORT: pl-fake.c foo_kind
"a ported enum, with a base type"
@enum foo_kind::UInt8 FOO_A FOO_B

# PORT: pl-fake.c foo_twice
"a ported C macro, as a Julia macro"
macro foo_twice(x)
    return :(2 * \$(esc(x)))
end
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
        "src/LogicKernel.jl",
        """
# ORIGINAL: fixture — the module entry file.
include("orig.jl")
include("pl-fake.jl")
"""
    )
    _pc_write(
        root,
        "src/orig.jl",
        """
# ORIGINAL: fixture — no upstream counterpart.
helper(x) = compareFoo(x, 0)
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
        # M1: with every checkout the headers name, the coverage block WAS compared — not skipped
        if issubset(["swipl-bench", "swipl-devel"], r.existence_checked)
            @test r.coverage_checked
        else
            @info "port_check: the coverage block is present and non-empty, NOT recomputed (it needs every upstream checkout)"
        end
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
                "bench/mine/x.jl",
                "# ORIGINAL: in a bench directory swipl-bench does not have\n"
            )
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
                ("DIR-NOT-UPSTREAM", "mine"),
                ("ORIGINAL-PORT-NAME", "orig.jl"),
                ("ORIGINAL-SHADOWS-UPSTREAM", "test_shadow.jl"),
                ("INVENTORY-DRIFT", "port_inventory.md")
            ])
            # M1's code-map checks have their own fixture below; here the planted set is the rest
            m1 = r"^(COVERAGE|CODE-GRAPH|WHATS-HERE|ARCHITECTURE)-"
            got = filter(c -> !occursin(m1, c[1]), _pc_codes(r.violations))
            got == expected || foreach(v -> println(stderr, "  got: ", v), r.violations)
            @test got == expected
        end

        @testset "fixture: a clean mirror passes, and one mutation fails it" begin
            root = joinpath(base, "clean")
            _pc_good_files(root, sha)
            _pc_inventory(root, "")
            write_inventory(root; upstream_dirs=dirs)
            r = port_check(root; upstream_dirs=dirs)
            r.violations == String[] ||
                foreach(v -> println(stderr, "  clean: ", v), r.violations)
            @test isempty(r.violations)
            @test length(r.files) == 5
            inv = read(joinpath(root, "docs/port_inventory.md"), String)
            @test occursin("`src/pl-fake.jl` | 6 |", inv)      # struct, const, enum, macro count
            @test occursin("`boot/tabling.jl` | 1 |", inv)
            @test occursin("`test/core_lang/test_fake.jl` | 1 |", inv)   # a ported TEST unit
            p = joinpath(root, "src/pl-fake.jl")
            write(
                p,
                replace(read(p, String), "function compareFoo(" => "function compare_foo(")
            )
            # the rename also drops the code graph's edge (orig.jl uses `compareFoo`)
            @test _pc_codes(port_check(root; upstream_dirs=dirs).violations) ==
                [("CODE-GRAPH-DRIFT", "architecture.md"), ("DEF-MISMATCH", "pl-fake.jl")]
        end

        @testset "M1: the generated code map is held to its generators" begin
            root = joinpath(base, "m1")
            _pc_good_files(root, sha)
            _pc_inventory(root, "")
            write_inventory(root; upstream_dirs=dirs)
            inv = joinpath(root, "docs/port_inventory.md")
            arch = joinpath(root, "docs/architecture.md")
            codes(; kw...) =
                _pc_codes(port_check(root; upstream_dirs=dirs, kw...).violations)
            # run `f` with `from` replaced by `to` (once, asserted) in `path`; restore the file
            function with_edit(f, path, from, to)
                t = read(path, String)
                @assert count(from, t) == 1 "fixture edit: $(repr(from)) is not in $path once"
                write(path, replace(t, from => to))
                try
                    return f()
                finally
                    write(path, t)
                end
            end
            r = port_check(root; upstream_dirs=dirs)
            @test isempty(r.violations) && r.coverage_checked
            # what the generators wrote — both sides non-empty
            @test occursin(
                "| swipl-devel `src/pl-fake.c` | `$sha` | 2 | 2 | 0 | src/pl-fake.jl |",
                read(inv, String)
            )                                                   # compareFoo, fooBar of 2
            @test occursin("`src/pl-fake.jl` | 6 | 0 |", read(inv, String))
            @test occursin("    orig --> pl_fake", read(arch, String))
            row = "| 2 | 2 | 0 | src/pl-fake.jl |"
            # a stale coverage block; without a checkout it is not recomputed, but must be there
            with_edit(inv, row, "| 1 | 2 | 0 | src/pl-fake.jl |") do
                @test codes() == [("COVERAGE-DRIFT", "port_inventory.md")]
                @test isempty(
                    port_check(root; upstream_dirs=Dict{String, String}()).violations
                )
            end
            cov = _section(read(inv, String), COVERAGE_BEGIN, COVERAGE_END)
            with_edit(inv, cov, "") do
                @test codes() == [("COVERAGE-EMPTY", "port_inventory.md")]
                @test _pc_codes(
                    port_check(root; upstream_dirs=Dict{String, String}()).violations
                ) == [("COVERAGE-EMPTY", "port_inventory.md")]
            end
            with_edit(inv, COVERAGE_BEGIN, "") do
                @test codes() == [("COVERAGE-MISSING", "port_inventory.md")]
            end
            # a stale code graph; an EMPTY generator, also against an empty block
            with_edit(arch, "    orig --> pl_fake\n", "") do
                @test codes() == [("CODE-GRAPH-DRIFT", "architecture.md")]
            end
            lk = joinpath(root, "src/LogicKernel.jl")
            with_edit(lk, "include(\"orig.jl\")\ninclude(\"pl-fake.jl\")\n", "") do
                @test codes() == [("CODE-GRAPH-EMPTY", "generator")]
                g = _section(read(arch, String), GRAPH_BEGIN, GRAPH_END)
                with_edit(arch, g, "") do               # empty == empty must not pass
                    @test codes() == [("CODE-GRAPH-EMPTY", "generator")]
                end
            end
            # the hand-kept table: a file missing, a file that does not exist, a wrong upstream
            orow = "| `src/orig.jl` | a helper | — |\n"
            with_edit(arch, orow, "") do
                @test codes() == [("WHATS-HERE-MISSING", "architecture.md")]
            end
            with_edit(arch, orow, orow * "| `src/nope.jl` | gone | — |\n") do
                @test codes() == [("WHATS-HERE-UNKNOWN", "architecture.md")]
            end
            with_edit(arch, "`src/pl-fake.c` |", "`src/pl-other.c` |") do       # a wrong file
                @test codes() == [("WHATS-HERE-UPSTREAM", "architecture.md")]
            end
            with_edit(arch, "`src/pl-fake.c` |", "`src/pl-fake.c`, `src/pl-extra.c` |") do
                @test codes() == [("WHATS-HERE-UPSTREAM", "architecture.md")]   # one too many
            end
            with_edit(arch, "| `src/pl-fake.c` |\n", "| — |\n") do     # a header left unnamed
                @test codes() == [("WHATS-HERE-UPSTREAM", "architecture.md")]
            end
            @test codes(; architecture="docs/nope.md") ==
                [("ARCHITECTURE-MISSING", "nope.md")]
        end

        @testset "upstream_drift: commits since the recorded one, and coverage" begin
            root = joinpath(base, "drift")
            _pc_good_files(root, sha)
            _pc_inventory(root, "")
            write_inventory(root; upstream_dirs=dirs)
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

    @testset "the VM inventory's `declared` column follows the pl-vmi.c PORT markers" begin
        row(n, k) = "| `$n` | 1 | — | N | $k |"
        doc(rows...) =
            "x\n$VM_INVENTORY_BEGIN -->\n| instruction | pl-vmi.c | operands | needed by | kernel |\n|---|---|---|---|---|\n" *
            join(rows, "\n") * "\n$VM_INVENTORY_END\n"
        two = doc(row("H_ATOM", "declared"), row("H_NIL", ""))
        @test vm_inventory_violations(two, Set(["H_ATOM"]), "inv") == String[]
        @test _pc_codes(vm_inventory_violations(two, Set(["H_ATOM", "H_NIL"]), "inv")) ==
            [("VM-INVENTORY-DRIFT", "inv")]                     # ported, row left blank
        @test _pc_codes(vm_inventory_violations(two, Set{String}(), "inv")) ==
            [("VM-INVENTORY-DRIFT", "inv")]                     # declared, never ported
        @test _pc_codes(vm_inventory_violations("x\n", Set(["H_ATOM"]), "inv")) ==
            [("VM-INVENTORY-MISSING", "inv")]
        @test vm_inventory_violations("x\n", Set{String}(), "inv") == String[]
        @test _pc_codes(vm_inventory_violations(doc(), Set{String}(), "inv")) ==
            [("VM-INVENTORY-MISSING", "inv")]                   # a section that parses to nothing

        # On LogicKernel itself: both sides NON-EMPTY, and one blanked row is caught BY `port_check`
        # (so the check is wired in, not only correct).
        root = joinpath(@__DIR__, "..")
        text = read(joinpath(root, "docs/port_inventory.md"), String)
        ported = Set(
            m.name for f in port_check(root).files for
            m in f.markers if m.upstream_base == "pl-vmi.c"
        )
        vm = _vm_inventory(text)
        @test vm !== nothing && vm.rows == 232                  # every VMI() of pl-vmi.c
        @test !isempty(ported) && vm.declared == ported
        blanked = replace(
            text,
            "| `H_NIL` | 528 | — | NQP | declared |" => "| `H_NIL` | 528 | — | NQP |  |"
        )
        @test blanked != text
        mktempdir() do d
            inv = joinpath(d, "port_inventory.md")
            write(inv, blanked)
            @test _pc_codes(port_check(root; inventory=inv).violations) ==
                [("VM-INVENTORY-DRIFT", "port_inventory.md")]
        end
    end

    @testset "expected_path mirrors the upstream path" begin
        @test expected_path("swipl-devel", "src/pl-prims.c") == "src/pl-prims.jl"
        @test expected_path("swipl-devel", "boot/tabling.pl") == "boot/tabling.jl"
        @test expected_path("swipl-devel", "tests/core_lang/test_bips.pl") ==
            "test/core_lang/test_bips.jl"
        @test expected_path("scryer-prolog", "src/lib/tabling.pl") ==
            "scryer-prolog/src/lib/tabling.jl"
        # swipl-devel's bench/ SUBMODULE is its own repo, mounted where swipl-devel mounts it
        @test expected_path("swipl-bench", "programs/derive.pl") ==
            "bench/programs/derive.jl"
    end
end
