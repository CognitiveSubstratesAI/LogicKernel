# ORIGINAL: the declarations check of the fast pre-check (audit D-0206 item 4a) — no swipl-devel counterpart.
#
#   julia --startup-file=no tools/term_scopes_check.jl [ROOT]   # prints the pass line, exit 1 on a bad declaration
#
# `Pkg.test` stops on a bad `# TERM TYPES PER CHUNK:` declaration (test/runtests.jl reads every test file's
# through test/term_scope.jl), and the branch-gate did not: BLOB's test_blob.jl named no src/ file, passed the
# branch-gate and the fast check, and failed in CI (A-0140). `tools/warm.sh check` — and with it the preflight
# and the branch-gate, which run the same fast check — now runs `term_scopes_check` first.
#
# ONE extractor: this file adds no rule of its own. It calls the runner's functions (`lk_term_scopes`,
# `lk_term_triggers`), so what stops the suite stops this check and nothing else does. What it adds is the
# guard against the three ways a guard is useless: it must not pass on nothing (an empty test directory, no
# term-generic file, no ALL file), it must look at the same tree and files as the runner (`<root>/test`,
# `test_*.jl`, recursively), and its pass line carries the counts so a run that checked nothing is visible.
Base.include(@__MODULE__, joinpath(@__DIR__, "..", "test", "term_scope.jl"))   # not `include`: Module(:X) has none

"""
    term_scopes_check(root) -> pass line

Throws unless every term-generic test file under `<root>/test` declares its term types per chunk exactly
as test/term_scope.jl demands: one line, a known kind, an ALL one naming src/ files that exist.
"""
function term_scopes_check(root::AbstractString)::String
    testdir = joinpath(root, "test")
    isdir(testdir) ||
        error("term scopes: $testdir is not a directory — nothing was checked")
    isempty(lk_test_files(testdir)) &&
        error("term scopes: no test_*.jl file under $testdir — nothing was checked")
    scopes = lk_term_scopes(testdir)               # throws on a missing, doubled or unknown declaration
    isempty(scopes) &&
        error(
            "term scopes: no term-generic file under $testdir — the extractor matched nothing"
        )
    triggers = lk_term_triggers(root)              # throws when an ALL declaration names a missing source
    nall = count(v -> v[1] === :all, values(scopes))
    nall > 0 ||
        error("term scopes: no ALL declaration under $testdir — no source file was checked")
    return "preflight: term scopes valid ($(length(scopes)) term-generic files: $nall ALL, " *
           "$(length(scopes) - nall) REFERENCE; $(length(triggers)) triggers)"
end

if abspath(PROGRAM_FILE) == @__FILE__
    root = isempty(ARGS) ? abspath(joinpath(@__DIR__, "..")) : abspath(ARGS[1])
    try
        println(term_scopes_check(root))
    catch e
        e isa ErrorException || rethrow()
        println(stderr, "preflight: TERM SCOPES INVALID — ", e.msg)
        exit(1)
    end
end
