# ORIGINAL: TAG1-KEEPS-1's mutant list — no swipl-devel counterpart.
# tools/mutants/TAG1KEEPS1.py — the mutation battery of the declared keeps in tools/port_check.jl (KEPT_NAMES: markers
# whose names upstream removed; the table is empty now, the mechanism stays). Run ONCE, in CI (.github/workflows/mutation.yml); locally one mutant at a time:
#   tools/mutate.sh run tools/mutants/TAG1KEEPS1.py test/test_port_check.jl          (the mutant worktree)
# The format is mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and
# `targets`.
#
# Subject: the declared keeps must not become a hole in the name check. Each mutant drops the table or its default,
# widens the match (by name, by file, by path, to every tree), stops one half of the stale check from failing or
# running, or loses the count. test/test_port_check.jl judges each on fixture trees, so no swipl-devel checkout is
# needed: TK3-TK12 are judged with fixture rows passed as `kept_names`. TK1 and TK2 change which default table a tree
# gets, and the real table is empty, so they are equivalent until it has a row again.
TARGETS = [
    "test/test_port_check.jl",
]
F = "tools/port_check.jl"
T = ["test/test_port_check.jl"]
MATCH = '''row.file == f.rel && row.name == m.name && row.upstream == u.path,'''
EMPTY = ("the real table is empty (tools/port_check.jl `const KEPT_NAMES = KeptName[]`), so both branches of the default "
         "give an empty table: no tree can tell them apart")
MUTANTS = [
    # ── the table and its default ──
    dict(id="TK1 the list is dropped", file=F, targets=T,
         old='''        KEPT_NAMES
    else
''',
         new='''        KeptName[]
    else
''',
         equivalent=EMPTY),
    dict(id="TK2 the default rows apply to every tree", file=F, targets=T,
         old='''    elseif isfile(joinpath(root, "src", "pl-inline.jl"))
''',
         new='''    elseif true
''',
         equivalent=EMPTY),
    # ── the match ──
    dict(id="TK3 the match is name-only", file=F, targets=T,
         old=MATCH, new='''row.name == m.name,'''),
    dict(id="TK4 the match ignores the kernel file", file=F, targets=T,
         old=MATCH, new='''row.name == m.name && row.upstream == u.path,'''),
    dict(id="TK5 the match ignores the upstream path", file=F, targets=T,
         old=MATCH, new='''row.file == f.rel && row.name == m.name,'''),
    dict(id="TK6 the match ignores the name", file=F, targets=T,
         old=MATCH, new='''row.file == f.rel && row.upstream == u.path,'''),
    # ── the stale checks ──
    dict(id="TK7 a name found upstream is never stale", file=F, targets=T,
         old='''                    i === nothing ||
''',
         new='''                    true ||
'''),
    dict(id="TK8 the rows are never held to the tree", file=F, targets=T,
         old='''    for e in keeps
''',
         new='''    for e in KeptName[]
'''),
    dict(id="TK9 a missing marker is never stale", file=F, targets=T,
         old='''        if !marked
''',
         new='''        if false
'''),
    dict(id="TK10 any marker of the upstream file satisfies a row", file=F, targets=T,
         old='''m -> m.name == e.name && m.upstream_base == basename(e.upstream),''',
         new='''m -> m.upstream_base == basename(e.upstream),'''),
    dict(id="TK11 any header line satisfies a row", file=F, targets=T,
         old='''            u -> u.path == e.upstream,
''',
         new='''            u -> true,
'''),
    # ── the count ──
    dict(id="TK12 the kept names are not reported", file=F, targets=T,
         old='''markers=marker_counts(root, srcs), kept=kept''',
         new='''markers=marker_counts(root, srcs), kept=String[]'''),
]
