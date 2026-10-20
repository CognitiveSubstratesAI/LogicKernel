# ORIGINAL: the README's "Using it from Julia" block, run as a test so it cannot rot (2026-10-20) — no
# swipl-devel counterpart.
# test/foreign/test_readme_example.jl — on the reference type (the README's `DefaultTerm`):
#   * the block is read from README.md AS PUBLISHED (the first ```julia fence after the section's
#     heading) and run in a module of its own;
#   * every claim its comments make holds: the load's `(:ok, nothing, [])`, the answers, `limit=1`,
#     the exception's ball — and the answers are swipl's for the same file and goal.
using Test, LogicKernel
const LK = LogicKernel

const _RM_SWIPL = (get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl"))
const _RM_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

"The code of the first ```julia fence after README.md's heading `heading`."
function _rm_block(heading::String)::String
    readme = read(joinpath(@__DIR__, "..", "..", "README.md"), String)
    at = findfirst("\n" * heading * "\n", readme)
    at === nothing && error("README.md has no heading \"$heading\"")
    open_ = findnext("\n```julia\n", readme, last(at))
    close_ = findnext("\n```\n", readme, last(open_))
    return readme[(last(open_) + 1):first(close_)]
end

@testset "README: the \"Using it from Julia\" block runs, and says what it does" begin
    code = _rm_block("## Using it from Julia")
    @test occursin("query_answers(ld,", code) && occursin("load_file!(gd, ld, path)", code)
    m = Module(:ReadmeExample)
    Base.include_string(m, code, "README.md")
    @test (m.status, m.ball, m.messages) == (:ok, nothing, Tuple{Symbol, DefaultTerm}[])
    @test m.answers isa Vector{DefaultTerm} && length(m.answers) == 2
    @test [sym_text(child(a, 3)) for a in m.answers] == ["ann", "pat"]
    @test length(m.first) == 1 && sym_text(child(m.first[1], 2)) == "tom"
    @test m.err isa PrologException{DefaultTerm}
    ball = m.err.ball                                  # error(existence_error(procedure, no_such/1), _)
    formal = child(ball, 2)
    @test sym_text(child(ball, 1)) == "error" && sym_text(child(formal, 1)) == "existence_error"
    @test sym_text(child(formal, 2)) == "procedure"
    pi = child(formal, 3)
    @test sym_text(child(pi, 1)) == "/" && sym_text(child(pi, 2)) == "no_such"
    @test number_kind(child(pi, 3)) === NUM_INTEGER && int64_value(child(pi, 3)) == 1
    # the same file and goal in swipl: the README's answers are swipl's
    if _RM_SWIPL !== nothing
        out = read(
            `$_RM_SWIPL -q -g "consult('$(m.path)'), forall(grandparent(tom, Z), writeln(Z))" -t halt`,
            String
        )
        @test split(chomp(out), '\n') == ["ann", "pat"]
    else
        @test !_RM_SWIPL_REQUIRED
        @warn "test_readme_example.jl: no swipl — the README's answers checked against the kernel only"
    end
end
