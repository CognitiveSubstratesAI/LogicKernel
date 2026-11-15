# ORIGINAL: no swipl-devel twin — the `parse_check` step of the compile job of .github/workflows/ci-compile.yml
# (audit D-0704 item 4). TABTEST-REBUILD found two test files that could never have parsed (an invalid string escape,
# `"\+ goal"` in a Julia string): a test file that cannot parse has never run, and no step said so. Every `*.jl`
# under test/, tools/ and src/ of the checkout is parsed with `Meta.parseall` and the resulting tree is walked for an
# `:error` or an `:incomplete` node. Needs only Base.
#
#   julia --startup-file=no tools/check_parse.jl [ROOT]      (ROOT default: the checkout this file lives in)
#
# Output: `check_parse: path:line: [error|incomplete] message` per failing file (the first bad node of each file; the line
# is the last source line marker before it), then the count; or `check_parse: N .jl file(s) scanned, no parse error`.
# Exit status: 0 every file parses; 1 at least one does not; 2 usage, or no .jl file under test/, tools/, src/ (an empty
# scan proves nothing). Its cases: tools/test_check_parse.sh.

# the message and the source line of an error node's payload: the parser's own text (`# Error @ file:LINE:COL` and the
# `└┘ ── message` line of its report), else the payload as printed
function describe(e)
    txt = e isa AbstractString ? String(e) : sprint(showerror, e)
    ls = split(txt, '\n')
    i = findfirst(l -> occursin(r"^# Error @ .*:\d+:\d+", l), ls)
    eline = i === nothing ? 0 : parse(Int, match(r":(\d+):\d+\s*$", ls[i]).captures[1])
    j = findlast(l -> occursin(r"└[─┘]*\s*── ", l), ls)
    msg = if j === nothing
        strip(replace(txt, '\n' => ' '))
    else
        strip(match(r"└[─┘]*\s*── (.*)$", ls[j]).captures[1])
    end
    return (msg, eline)
end

# the first :error / :incomplete node under `x` as (kind, message, line); `line` is the last LineNumberNode seen before it
function first_bad(x, line::Int=0)
    x isa LineNumberNode && return (nothing, line)
    x isa Expr || return (nothing, line)
    if Meta.isexpr(x, :error) || Meta.isexpr(x, :incomplete)
        msg, eline = describe(isempty(x.args) ? "" : x.args[1])
        return ((x.head, msg, eline == 0 ? line : eline), line)
    end
    for a in x.args
        if a isa LineNumberNode
            line = a.line
            continue
        end
        r, line = first_bad(a, line)
        r === nothing || return (r, line)
    end
    return (nothing, line)
end

function jl_files(root::String)
    files = String[]
    for sub in ("test", "tools", "src")
        d = joinpath(root, sub)
        isdir(d) || continue
        for (dir, _, names) in walkdir(d)
            for n in names
                endswith(n, ".jl") && push!(files, joinpath(dir, n))
            end
        end
    end
    return sort!(files)
end

function main(args)
    length(args) <= 1 ||
        (println(stderr, "usage: julia tools/check_parse.jl [ROOT]"); return 2)
    root = isempty(args) ? dirname(@__DIR__) : abspath(args[1])
    isdir(root) || (println(stderr, "check_parse: no such directory: $root"); return 2)
    files = jl_files(root)
    if isempty(files)
        println(
            stderr,
            "check_parse: no .jl file under $root/{test,tools,src}: an empty scan proves nothing"
        )
        return 2
    end
    bad = 0
    for f in files
        ex = Meta.parseall(read(f, String); filename=f)
        r, _ = first_bad(ex)
        r === nothing && continue
        bad += 1
        kind, msg, line = r
        println(
            "check_parse: ", relpath(f, root), ":", line, ": [", kind, "] ", first(msg, 200)
        )
    end
    if bad > 0
        println(
            "check_parse: $bad of $(length(files)) .jl file(s) do not parse: such a file has never run"
        )
        return 1
    end
    println("check_parse: $(length(files)) .jl file(s) scanned, no parse error")
    return 0
end

exit(main(ARGS))
