# ORIGINAL: JUnit XML from a Test.DefaultTestSet tree, for Codecov Test Analytics; no swipl-devel counterpart.
#
# Codecov Test Analytics reads JUnit XML; Julia's Test writes none. This turns the suite's own result
# tree into it — no dependency. One <testsuite> per test FILE (the root's children), one <testcase>
# per test set that made assertions of its own, a <failure>/<error> per failed/errored assertion.
using Test

_jx(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
_jkids(ts::Test.DefaultTestSet) = [r for r in ts.results if r isa Test.DefaultTestSet]
# `time_end` is 0.0 until `finish` runs (Julia 1.13) — the root is still open when this is written.
_jtime(ts::Test.DefaultTestSet)::Float64 =
    max(0.0, (ts.time_end == 0.0 ? time() : ts.time_end) - ts.time_start)

function _jcases!(out::Vector{String}, counts::Vector{Int}, ts::Test.DefaultTestSet,
    suite::String,
    path::String)
    bad = [r for r in ts.results if r isa Test.Fail || r isa Test.Error]
    broken = count(r -> r isa Test.Broken, ts.results)
    if ts.n_passed > 0 || !isempty(bad) || (broken > 0 && isempty(_jkids(ts)))
        io = IOBuffer()
        print(io, "    <testcase classname=\"", _jx(suite), "\" name=\"", _jx(path),
            "\" time=\"", round(_jtime(ts); digits=3), "\">")
        for r in bad
            tag = r isa Test.Fail ? "failure" : "error"
            full = sprint(show, r)
            lines = split(full, '\n')
            print(io, "\n      <", tag, " message=\"", _jx(first(lines)), "\" type=\"", tag,
                "\">",
                _jx(join(first(lines, 30), '\n')), "</", tag, ">")
            counts[r isa Test.Fail ? 2 : 3] += 1
        end
        ts.n_passed == 0 && isempty(bad) && print(io, "\n      <skipped/>")
        print(io, isempty(bad) && ts.n_passed > 0 ? "</testcase>" : "\n    </testcase>")
        push!(out, String(take!(io)))
        counts[1] += 1
    end
    for k in _jkids(ts)
        _jcases!(out, counts, k, suite, path * " › " * k.description)
    end
    return out
end

"""
    write_junit(root::Test.DefaultTestSet, path) -> path

Write `root`'s results as JUnit XML. Call it BEFORE `Test.finish(root)`, which throws on failure.
"""
function write_junit(root::Test.DefaultTestSet, path::AbstractString)
    suites = String[]
    tot = [0, 0, 0]
    for f in _jkids(root)
        counts = [0, 0, 0]
        cases = _jcases!(String[], counts, f, f.description, f.description)
        tot .+= counts
        push!(
            suites,
            string("  <testsuite name=\"", _jx(f.description), "\" tests=\"", counts[1],
                "\" failures=\"", counts[2], "\" errors=\"", counts[3], "\" time=\"",
                round(_jtime(f); digits=3), "\">\n", join(cases, "\n"), "\n  </testsuite>")
        )
    end
    open(path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        println(io, "<testsuites name=\"", _jx(root.description), "\" tests=\"", tot[1],
            "\" failures=\"", tot[2], "\" errors=\"", tot[3], "\" time=\"",
            round(_jtime(root); digits=3), "\">")
        foreach(s -> println(io, s), suites)
        println(io, "</testsuites>")
    end
    return path
end
