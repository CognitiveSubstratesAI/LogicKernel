# ORIGINAL: ToolTS's mutant list — no swipl-devel counterpart.
# tools/mutants/ToolTS.py — the mutation battery of the TOOL-TS step (audit D-0206 item 4, 2026-10-29): the
# term-scopes declarations check in `tools/warm.sh check` (4a) and the static-analysis file's 3600 s timeout
# (4b). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` (a mutant
# that must SURVIVE, with the code reason) and `targets`.
#
# Subject: a guard must be able to FAIL, so each mutant is one of the three ways a guard is useless — the
# check never runs (never called, its verdict dropped), it cannot fail (passes on nothing, accepts a bad
# declaration), or it compares the wrong thing (another tree, another count, another file's timeout).
TARGETS = [
    "test/test_gate_split.jl",
]
C = "tools/term_scopes_check.jl"
W = "tools/warm.sh"
P = "tools/pkgtest_way.sh"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    # ── tools/term_scopes_check.jl: the check itself ──
    dict(id="TT1 a missing test directory is not an error", file=C, targets=T,
         old='''    isdir(testdir) ||
        error("term scopes: $testdir is not a directory — nothing was checked")''',
         new='''    nothing'''),
    dict(id="TT2 an empty test directory passes the first guard", file=C, targets=T,
         old='''    isempty(lk_test_files(testdir)) &&
        error("term scopes: no test_*.jl file under $testdir — nothing was checked")''',
         new='''    nothing'''),
    dict(id="TT3 a tree with no term-generic file passes", file=C, targets=T,
         old='''    isempty(scopes) &&
        error(
            "term scopes: no term-generic file under $testdir — the extractor matched nothing"
        )''',
         new='''    nothing'''),
    dict(id="TT4 a named source that does not exist is never looked for", file=C, targets=T,
         old='''    triggers = lk_term_triggers(root)              # throws when an ALL declaration names a missing source''',
         new='''    triggers = String[]'''),
    dict(id="TT5 a tree with no ALL declaration passes", file=C, targets=T,
         old='''    nall > 0 ||
        error("term scopes: no ALL declaration under $testdir — no source file was checked")''',
         new='''    nothing'''),
    dict(id="TT6 the check reads another directory than the runner", file=C, targets=T,
         old='''    testdir = joinpath(root, "test")''',
         new='''    testdir = joinpath(root, "tools")'''),
    dict(id="TT7 the pass line counts the triggers as the files", file=C, targets=T,
         old='''    return "preflight: term scopes valid ($(length(scopes)) term-generic files: $nall ALL, " *''',
         new='''    return "preflight: term scopes valid ($(length(triggers)) term-generic files: $nall ALL, " *'''),
    dict(id="TT8 a failed check exits 0", file=C, targets=T,
         old='''        println(stderr, "preflight: TERM SCOPES INVALID — ", e.msg)
        exit(1)''',
         new='''        println(stderr, "preflight: TERM SCOPES INVALID — ", e.msg)
        exit(0)'''),
    dict(id="TT9 the script runs nothing as a program", file=C, targets=T,
         old='''if abspath(PROGRAM_FILE) == @__FILE__''',
         new='''if false'''),
    dict(id="TT10 the root argument is ignored", file=C, targets=T,
         old='''    root = isempty(ARGS) ? abspath(joinpath(@__DIR__, "..")) : abspath(ARGS[1])''',
         new='''    root = abspath(joinpath(@__DIR__, ".."))'''),
    # ── tools/warm.sh: the step in `check` (and so in the preflight and the branch-gate) ──
    dict(id="TT11 check never runs the term-scopes step", file=W, targets=T,
         old='''    _term_scopes_check                     # first, and the others run anyway: one run names every failure''',
         new='''    true                                   # first, and the others run anyway: one run names every failure'''),
    dict(id="TT12 the step's status is dropped", file=W, targets=T,
         old=r'''    ts=$?
    _meta_check''',
         new=r'''    ts=0
    _meta_check'''),
    dict(id="TT13 the step's status is not returned", file=W, targets=T,
         old=r'''    [ "$ts" -eq 0 ] || return "$ts"''',
         new=r'''    :'''),
    dict(id="TT14 the term-scopes pass line is not required", file=W, targets=T,
         old='''    if [ "$rc" -eq 0 ] && ! _verdict_in "$log" '^preflight: term scopes valid'; then''',
         new='''    if false; then'''),
    dict(id="TT15 the daemon's verdict is not taken", file=W, targets=T,
         old='''    rc=$?
    case "${LOGICKERNEL_PREFLIGHT_FAULT:-}" in                     # TEST SEAMS (test/test_gate_split.jl)
        scopes-empty)''',
         new='''    rc=0
    case "${LOGICKERNEL_PREFLIGHT_FAULT:-}" in                     # TEST SEAMS (test/test_gate_split.jl)
        scopes-empty)'''),
    dict(id="TT16 the snippet checks another directory than the root", file=W, targets=T,
         old='''println(Base.invokelatest(() -> m.term_scopes_check(raw"$root")))''',
         new='''println(Base.invokelatest(() -> m.term_scopes_check(raw"$root/src")))'''),
    dict(id="TT17 the term-scopes command checks nothing", file=W, targets=T,
         old=r'''        _term_scopes_check
        ;;
    meta-check''',
         new=r'''        true
        ;;
    meta-check'''),
    dict(id="TT18 the static file's timeout drops back to 1800 s", file=W, targets=T,
         old='''WARM_STATIC_TIMEOUT_S=3600''',
         new='''WARM_STATIC_TIMEOUT_S=1800'''),
    dict(id="TT19 every file gets the long timeout", file=W, targets=T,
         old='''        "$ROOT"/test/test_static_analysis.jl) echo "$WARM_STATIC_TIMEOUT_S" ;;''',
         new='''        *) echo "$WARM_STATIC_TIMEOUT_S" ;;'''),
    dict(id="TT20 the pre-check file gets the long timeout too", file=W, targets=T,
         old='''        "$ROOT"/test/test_static_analysis.jl) echo "$WARM_STATIC_TIMEOUT_S" ;;''',
         new='''        "$ROOT"/test/*static_analysis*.jl) echo "$WARM_STATIC_TIMEOUT_S" ;;'''),
    dict(id="TT21 a file run does not use the file's timeout", file=W, targets=T,
         old='''    WARM_TIMEOUT_S="$(_file_timeout "$f")" _send "$snippet" > "$out" 2>&1''',
         new='''    _send "$snippet" > "$out" 2>&1'''),
    dict(id="TT22 an explicit WARM_TIMEOUT_S no longer wins", file=W, targets=T,
         old='''    if [ -n "${WARM_TIMEOUT_S:-}" ]; then echo "$WARM_TIMEOUT_S"; return; fi''',
         new='''    :'''),
    dict(id="TT23 the default timeout changes", file=W, targets=T,
         old='''WARM_DEFAULT_TIMEOUT_S=1800''',
         new='''WARM_DEFAULT_TIMEOUT_S=600'''),
    dict(id="TT24 the wait loop ignores the timeout it was given", file=W, targets=T,
         old='''        deadline=$(( $(date +%s) + ${WARM_TIMEOUT_S:-$WARM_DEFAULT_TIMEOUT_S} ))''',
         new='''        deadline=$(( $(date +%s) + 1800 ))'''),
    # ── tools/warm.sh: the other CI-only checks moved into `check` (audit D-0214 finding 1) ──
    dict(id="TT25 check never runs the meta test files", file=W, targets=T,
         old=r"""    _meta_check
    mt=$?""",
         new=r"""    true
    mt=$?"""),
    dict(id="TT26 check never runs the inert guard", file=W, targets=T,
         old=r"""    _inert_check "${LOGICKERNEL_INERT_BUDGET_S:-120}"
    ic=$?""",
         new=r"""    true
    ic=$?"""),
    dict(id="TT27 the meta files' status is not returned", file=W, targets=T,
         old=r'''    [ "$mt" -eq 0 ] || return "$mt"''',
         new=r'''    :'''),
    dict(id="TT28 the inert guard's status is not returned", file=W, targets=T,
         old=r'''    return "$ic"''',
         new=r'''    return 0'''),
    dict(id="TT29 an empty meta list passes", file=W, targets=T,
         old=r"""    if [ "$n" -eq 0 ]; then
        echo "preflight: no meta test file ran""",
         new=r"""    if false; then
        echo "preflight: no meta test file ran"""),
    dict(id="TT30 a meta file's time is not recorded", file=W, targets=T,
         old=r'''        _record_file_time "$f" "$(( $(date +%s) - t0 ))"''',
         new=r'''        :'''),
    dict(id="TT31 test_package.jl leaves the meta list", file=W, targets=T,
         old=r'''WARM_META_FILES="test/test_package.jl test/test_commit_msg_hook.jl''',
         new=r'''WARM_META_FILES="test/test_commit_msg_hook.jl'''),
                    dict(id="TT36 the daemon's formatter version is not compared with CI's pin", file=W, targets=T,
         old=r"""    have == pin || error("preflight: JuliaFormatter ", have, " in the daemon, CI pins ", pin)""",
         new=r"""    nothing"""),
    dict(id="TT37 the pin is read from another name", file=W, targets=T,
         old=r"""'name="JuliaFormatter", version="[0-9]+""",
         new=r"""'name="JuliaFormatterX", version="[0-9]+"""),
    dict(id="TT38 a unit does not close on the shared empty vector", file=W, targets=T,
         old=r"""                @test isempty(LogicKernel._no_children(LogicKernel.DefaultTerm))""",
         new=r"""                nothing"""),
    dict(id="TT39 a tools/ change brings in no tooling test", file=W, targets=T,
         old=r"""        if printf '%s\n' "$changed" | grep -qE '^(tools/|\.github/)'; then""",
         new=r"""        if false; then"""),
    dict(id="TT40 a tools/ change brings in one tooling test only", file=W, targets=T,
         old=r"""            printf '%s\n' test/test_gate_split.jl test/test_port_check.jl""",
         new=r"""            printf '%s\n' test/test_gate_split.jl"""),
    dict(id="TT41 the branch-gate keeps the check's small inert budget", file=W, targets=T,
         old=r"""    LOGICKERNEL_INERT_BUDGET_S="${LOGICKERNEL_INERT_BUDGET_S:-600}" _checks_fresh || {""",
         new=r"""    _checks_fresh || {"""),
    # ── tools/pkgtest_way.sh and the Pkg.test-way step (audit D-0222) ──
    dict(id="TT42 the Pkg.test-way run keeps swipl", file=P, targets=T,
         old=r'''export LOGICKERNEL_NO_SWIPL=1''',
         new=r'''export LOGICKERNEL_NO_SWIPL=0'''),
    dict(id="TT43 the run inherits the daemon-shaped REQUIRE variables", file=P, targets=T,
         old=r'''unset LOGICKERNEL_REQUIRE_SWIPL LOGICKERNEL_REQUIRE_TOOLS LOGICKERNEL_TERM''',
         new=r'''unset LOGICKERNEL_TERM'''),
    dict(id="TT44 stdin is not /dev/null", file=P, targets=T,
         old=r'''"${scope[@]}" "${runner[@]}" "${cmd[@]}" < /dev/null > "$base.out"''',
         new=r'''"${scope[@]}" "${runner[@]}" "${cmd[@]}" > "$base.out"'''),
    dict(id="TT45 stdout is not a file the verdict is read from", file=P, targets=T,
         old=r'''"${cmd[@]}" < /dev/null > "$base.out" 2> "$base.err" 9>&-''',
         new=r'''"${cmd[@]}" < /dev/null 2> "$base.err" 9>&-'''),
    dict(id="TT46 stderr is not a file", file=P, targets=T,
         old=r'''"${cmd[@]}" < /dev/null > "$base.out" 2> "$base.err" 9>&-''',
         new=r'''"${cmd[@]}" < /dev/null > "$base.out" 2>&1 9>&-'''),
    dict(id="TT47 an exit 0 without the pass line is a pass", file=P, targets=T,
         old=r'''if ! grep -q "^pkgtest-way: PASS " "$base.out"; then''',
         new=r'''if false; then'''),
    dict(id="TT48 a failing exit code is not a failure", file=P, targets=T,
         old=r'''if [ "$rc" -ne 0 ]; then
    echo "pkgtest_way: FAILED''',
         new=r'''if false; then
    echo "pkgtest_way: FAILED'''),
    dict(id="TT49 the step in check does not run the file", file=W, targets=T,
         old=r'''"$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1
        prc=$?''',
         new=r'''true > "$log" 2>&1
        prc=$?'''),
    dict(id="TT50 the estimate ignores the cold factor", file=W, targets=T,
         old=r'''est=$(( est + factor * $(''',
         new=r'''est=$(( est + $('''),
    dict(id="TT51 the Pkg.test-way budget compares the wrong way", file=W, targets=T,
         old=r'''    if [ "$est" -gt "$budget" ]; then
        echo "preflight: Pkg.test-way run: over budget''',
         new=r'''    if [ "$est" -lt "$budget" ]; then
        echo "preflight: Pkg.test-way run: over budget'''),
    dict(id="TT52 a failed Pkg.test-way run does not fail the check", file=W, targets=T,
         old=r'''            rc=1
            echo "preflight: Pkg.test-way run FAILED''',
         new=r'''            echo "preflight: Pkg.test-way run FAILED'''),
    dict(id="TT53 the unrecorded-file estimate changes", file=W, targets=T,
         old=r'''${LOGICKERNEL_INERT_DEFAULT_S:-20}''',
         new=r'''${LOGICKERNEL_INERT_DEFAULT_S:-60}'''),
    dict(id="TT54 a skipped heavy tooling test file is run in check", file=W, targets=T,
         old=r'''WARM_INERT_SKIP="test/test_static_analysis.jl test/test_gate_split.jl test/test_port_check.jl"''',
         new=r'''WARM_INERT_SKIP="test/test_static_analysis.jl"'''),
    dict(id="TT55 the lane check is skipped for every command", file=W, targets=T,
         old=r'''        if [ "${LOGICKERNEL_WARM_SEND_PROBE:-}" != 1 ] && [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" != 1 ]; then''',
         new=r'''        if false; then'''),
    dict(id="TT56 the send probe no longer skips the lane check", file=W, targets=T,
         old=r'''        if [ "${LOGICKERNEL_WARM_SEND_PROBE:-}" != 1 ] && [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" != 1 ]; then''',
         new=r'''        if [ "${LOGICKERNEL_TERM_SCOPES_COLD:-}" != 1 ]; then'''),
    dict(id="TT57 a failed Pkg.test-way run hides the file's own failure lines", file=P, targets=T,
         old=r'''    grep -E -A5 'Test Failed|Error During' "$base.out" | head -n 40 >&2''',
         new=r'''    :'''),
]
