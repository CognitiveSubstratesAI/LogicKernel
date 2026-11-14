# ORIGINAL: PCSPLIT's mutant list — no swipl-devel counterpart.
# tools/mutants/PCSPLIT.py — the mutation battery of the split-file rule in tools/port_check.jl (audit D-0649 rule,
# D-0667 item 2): SPLIT_PORTS, port_path_ok, its call site in `port_check`, and split_parts_dangling. Run ONCE, in CI
# (.github/workflows/mutation.yml); locally one mutant at a time is fine:
#   tools/mutate.sh run tools/mutants/PCSPLIT.py test/test_port_check.jl            (the mutant worktree)
#   tools/mutate.sh run-in-tree tools/mutants/PCSPLIT.py test/test_port_check.jl    (this tree)
# tools/mutate_drive.py takes any `file` relative to the tree, and test/test_port_check.jl includes tools/port_check.jl
# afresh on every run, so a mutant in tools/ is judged exactly like one in src/. The format is mutate_drive.py's:
# `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
#
# Subject: the rule must be able to FAIL at verdict level — each mutant is one of the ways it is useless: it accepts
# every name (cannot fail), drops the mirrored path or the listed parts (refuses right files), matches by a pattern
# (the glob, forbidden), compares the wrong thing (repo, upstream path), is not consulted by port_check (never runs),
# or the dangling-part check cannot fail / fires on the right tree.
TARGETS = [
    "test/test_port_check.jl",
]
F = "tools/port_check.jl"
T = ["test/test_port_check.jl"]
OK = "port_path_ok(f.rel, f.upstreams[1].repo, f.upstreams[1].path) || push!("
MUTANTS = [
    # ── port_path_ok ──
    dict(id="PS1 the mirrored path stops being right", file=F, targets=T,
         old='''    rel == expected_path(repo, path) && return true
''',
         new=''''''),
    dict(id="PS2 every name is accepted", file=F, targets=T,
         old='''    return rel in get(SPLIT_PORTS, string(repo, " ", path), ())''',
         new='''    return true'''),
    dict(id="PS3 a pattern matches the parts (the glob)", file=F, targets=T,
         old='''    return rel in get(SPLIT_PORTS, string(repo, " ", path), ())''',
         new='''    return !isempty(get(SPLIT_PORTS, string(repo, " ", path), ())) && startswith(rel, "src/pl-gc")'''),
    dict(id="PS4 the listing ignores the repo", file=F, targets=T,
         old='''string(repo, " ", path), ())''',
         new='''string("swipl-devel", " ", path), ())'''),
    dict(id="PS5 the listing ignores the upstream path", file=F, targets=T,
         old='''string(repo, " ", path), ())''',
         new='''"swipl-devel src/pl-gc.c", ())'''),
    # ── the call site in port_check ──
    dict(id="PS6 port_check ignores the table", file=F, targets=T,
         old=OK, new='''f.rel == want || push!('''),
    dict(id="PS7 port_check accepts every path", file=F, targets=T,
         old=OK, new='''true || push!('''),
    # ── the table ──
    dict(id="PS8 a listed part dropped", file=F, targets=T,
         old='''"src/pl-gctrail.jl", "src/pl-gcwalk.jl"''',
         new='''"src/pl-gctrail.jl"'''),
    dict(id="PS9 an unlisted part added", file=F, targets=T,
         old='''"src/pl-gctrail.jl", "src/pl-gcwalk.jl"''',
         new='''"src/pl-gctrail.jl", "src/pl-gcwalk.jl", "src/pl-gcextra.jl"'''),
    dict(id="PS10 a pattern listed as a part", file=F, targets=T,
         old='''"src/pl-gcwalk.jl"''',
         new='''"src/pl-gc*.jl"'''),
    dict(id="PS11 the table is keyed on another upstream path", file=F, targets=T,
         old='''"swipl-devel src/pl-gc.c" => (''',
         new='''"swipl-devel src/pl-gc.h" => ('''),
    # ── split_parts_dangling ──
    dict(id="PS12 the dangling check is inverted", file=F, targets=T,
         old='''isfile(joinpath(root, part)) ||''',
         new='''isfile(joinpath(root, part)) &&'''),
    dict(id="PS13 the dangling check cannot fail", file=F, targets=T,
         old='''isfile(joinpath(root, part)) ||''',
         new='''true ||'''),
    dict(id="PS14 the dangling check looks in another tree", file=F, targets=T,
         old='''isfile(joinpath(root, part))''',
         new='''isfile(joinpath(@__DIR__, part))'''),
    dict(id="PS15 the dangling check reads no table entry", file=F, targets=T,
         old='''for key in sort!(collect(keys(table))), part in table[key]''',
         new='''for key in String[], part in ()'''),
]
