# tools/r2_status.jl — the R2 chain status, GENERATED (audit D-0370 item 1, D-0371 item 5; plan: evidence/R2GEN/plan.md).
#
#   julia --project=. tools/r2_status.jl            # print the counts and the per-file table (read-only)
#
# For the files boot/load.pl consults (and the library files on the load path), at the pin, which C predicates, flags
# and VM instructions do they reach, and which of those has the kernel: registered / refused / missing, with an owner step
# from docs/r2_owners.tsv. SIMPLE JULIA OVER TEXT FILES: no kernel is loaded, no daemon runs, nothing is executed from the
# kernel. tools/port_check.jl includes this file and holds the rendered block (docs/architecture.md) to it.
#
# ⚠️ Every scan below is LOOSE on purpose (a tokenizer, not a Prolog or C parser): it ranks and counts, the way
# evidence/R2/boot_features.md and missing_c_preds.md did by hand. A count is "what the scan finds", never a proof.

# ── the Prolog tokenizer (comments, quoted atoms, 0'c, radix numbers) ────────────────────────────────

struct R2Tok
    kind::Symbol          # :atom :qatom :var :num :str :sym :punct :end
    text::String
    line::Int
    adj::Bool             # no layout between the previous token and this one (`name(` is a compound)
end

const _R2_SYMCH = Set("+-*/\\^<>=~:.?@#&\$")

_r2_isalnum(c::Char)::Bool = isletter(c) || isdigit(c)

"The tokens of Prolog source `text` (comments dropped)."
function r2_tokenize(text::AbstractString)::Vector{R2Tok}
    cs = collect(String(text))
    n = length(cs)
    out = R2Tok[]
    i, line, lastend = 1, 1, 0
    while i <= n
        c = cs[i]
        if c == '\n'
            line += 1
            i += 1
        elseif isspace(c)
            i += 1
        elseif c == '%'
            while i <= n && cs[i] != '\n'
                i += 1
            end
        elseif c == '/' && i < n && cs[i + 1] == '*'
            i += 2
            while i < n && !(cs[i] == '*' && cs[i + 1] == '/')
                cs[i] == '\n' && (line += 1)
                i += 1
            end
            i += 2
        else
            start, l0 = i, line
            adj = lastend == i - 1
            if c in ('\'', '"', '`')
                q = c
                i += 1
                buf = IOBuffer()
                while i <= n
                    d = cs[i]
                    if d == '\\' && i < n
                        cs[i + 1] == '\n' && (line += 1)
                        write(buf, d, cs[i + 1])
                        i += 2
                    elseif d == q
                        if i < n && cs[i + 1] == q
                            write(buf, q)
                            i += 2
                        else
                            break
                        end
                    else
                        d == '\n' && (line += 1)
                        write(buf, d)
                        i += 1
                    end
                end
                i += 1
                push!(out, R2Tok(q == '\'' ? :qatom : :str, String(take!(buf)), l0, adj))
            elseif isdigit(c)
                while i <= n && (isdigit(cs[i]) || cs[i] == '_')
                    i += 1
                end
                if i <= n && cs[i] == '\'' && i < n
                    if String(cs[start:(i - 1)]) == "0"       # 0'c, 0'\n, 0'''
                        i += 1
                        if cs[i] == '\\' && i < n
                            i += 2
                        elseif cs[i] == '\'' && i < n && cs[i + 1] == '\''
                            i += 2
                        else
                            i += 1
                        end
                    elseif _r2_isalnum(cs[i + 1])                 # radix: 2'0001, 16'FF
                        i += 1
                        while i <= n && _r2_isalnum(cs[i])
                            i += 1
                        end
                    end
                elseif i < n && cs[i] == 'x' && start == i - 1 && cs[start] == '0'
                    i += 1
                    while i <= n && isxdigit(cs[i])
                        i += 1
                    end
                else
                    if i < n && cs[i] == '.' && isdigit(cs[i + 1])
                        i += 1
                        while i <= n && isdigit(cs[i])
                            i += 1
                        end
                        if i < n && (cs[i] == 'e' || cs[i] == 'E') &&
                            (
                                isdigit(cs[i + 1]) ||
                                (i + 1 < n && cs[i + 1] in "+-" && isdigit(cs[i + 2]))
                            )
                            i += 2
                            while i <= n && isdigit(cs[i])
                                i += 1
                            end
                        end
                    end
                end
                push!(out, R2Tok(:num, String(cs[start:(i - 1)]), l0, adj))
            elseif isletter(c) || c == '_'
                while i <= n && (_r2_isalnum(cs[i]) || cs[i] == '_')
                    i += 1
                end
                w = String(cs[start:(i - 1)])
                push!(out, R2Tok((isuppercase(c) || c == '_') ? :var : :atom, w, l0, adj))
            elseif c in _R2_SYMCH
                while i <= n && cs[i] in _R2_SYMCH
                    i += 1
                end
                w = String(cs[start:(i - 1)])
                isend = w == "." && (i > n || isspace(cs[i]) || cs[i] == '%')
                push!(out, R2Tok(isend ? :end : :sym, w, l0, adj))
            else
                i += 1
                push!(out, R2Tok(:punct, string(c), l0, adj))
            end
            lastend = i - 1
        end
    end
    return out
end

"The clauses of a token vector: one vector per clause, the end token dropped."
function r2_clauses(toks::Vector{R2Tok})::Vector{Vector{R2Tok}}
    out = Vector{R2Tok}[]
    cur = R2Tok[]
    for t in toks
        if t.kind == :end
            isempty(cur) || push!(out, cur)
            cur = R2Tok[]
        else
            push!(cur, t)
        end
    end
    isempty(cur) || push!(out, cur)
    return out
end

"The atom a token names (`'a b'` → `a b`), or `nothing` for a non-atom token."
function r2_atom_name(t::R2Tok)::Union{String, Nothing}
    t.kind == :atom && return t.text
    t.kind == :qatom && return replace(t.text, "\\\\" => "\\", "\\'" => "'")
    return nothing
end

"The arity of the compound whose `(` is at `toks[i]`, and the index of its `)`."
function r2_arity(toks::Vector{R2Tok}, i::Int)::Tuple{Int, Int}
    depth, commas, seen = 0, 0, false
    for j in i:length(toks)
        t = toks[j]
        if t.kind == :punct && t.text in ("(", "[", "{")
            depth += 1
            j > i && (seen = true)
        elseif t.kind == :punct && t.text in (")", "]", "}")
            depth -= 1
            depth == 0 && return (seen ? commas + 1 : 0, j)
        elseif t.kind == :punct && t.text == "," && depth == 1
            commas += 1
        else
            j > i && (seen = true)
        end
    end
    return (0, length(toks))
end

# Operators are calls too: `A :< B` is `:<`(A, B), `:- dynamic foo/1` is `dynamic(foo/1)`. Only a key that matches a C-defined
# predicate counts later, so an arithmetic `+` between two operands is harmless. Neither the clause neck nor the DCG arrow is a call.
const _R2_NOT_INFIX = (":-", "?-", "-->", "=>", "?=>", ":")
const R2_PREFIX_GOALS = (
    "dynamic", "discontiguous", "initialization", "meta_predicate", "module_transparent",
    "multifile", "public",
    "thread_local", "thread_initialization", "volatile", "table"
)
_r2_operand_end(t::R2Tok)::Bool =
    t.kind in (:atom, :qatom, :var, :num, :str) ||
    (t.kind == :punct && t.text in (")", "]", "}"))
_r2_operand_start(t::R2Tok)::Bool =
    t.kind in (:atom, :qatom, :var, :num, :str) ||
    (t.kind == :punct && t.text in ("(", "[", "{"))

const _R2_GOAL_PREV = (":-", "?-", ",", "(", ";", "->", "*->", "\\+", "|", "{")
const _R2_GOAL_NEXT = (",", ")", ";", "->", "*->", "|", "}")

"""
The goals a clause calls, loosely: `(name, arity, line)` for each `name(` compound, plus an atom in goal position (arity 0:
after `:-`, `,`, `(`, `;`, `->`, `\\+` and before `,`, `)`, `;`, `->`, the end; not inside `[ … ]`, nor directly among a compound's
arguments: the meta-arguments of `catch/3`, `findall/3` … are seen only as parenthesised control terms).
"""
function r2_calls(clause::Vector{R2Tok})::Vector{Tuple{String, Int, Int}}
    out = Tuple{String, Int, Int}[]
    stack = String[]
    for (k, t) in enumerate(clause)
        if t.kind == :punct && t.text == "("
            push!(
                stack,
                (k > 1 && t.adj && clause[k - 1].kind in (:atom, :qatom, :var)) ? "c" : "("
            )   # "c": a compound's arguments
        elseif t.kind == :punct && t.text in ("[", "{")
            push!(stack, t.text)
        elseif t.kind == :punct && t.text in (")", "]", "}")
            isempty(stack) || pop!(stack)
        end
        nxt = k < length(clause) ? clause[k + 1] : nothing
        if t.kind == :sym                                  # `=(A, B)` or the infix `A :< B`, `A \\=@= B`
            if nxt !== nothing && nxt.kind == :punct && nxt.text == "(" && nxt.adj
                push!(out, (t.text, first(r2_arity(clause, k + 1)), t.line))
            elseif !(t.text in _R2_NOT_INFIX) && k > 1 && nxt !== nothing &&
                _r2_operand_end(clause[k - 1]) && _r2_operand_start(nxt)
                push!(out, (t.text, 2, t.line))
            end
            continue
        end
        name = r2_atom_name(t)
        name === nothing && continue
        if nxt !== nothing && nxt.kind == :punct && nxt.text == "(" && nxt.adj
            push!(out, (name, first(r2_arity(clause, k + 1)), t.line))
        elseif t.kind == :atom && name == "is" && k > 1 && nxt !== nothing &&
            _r2_operand_end(clause[k - 1]) && _r2_operand_start(nxt)
            push!(out, (name, 2, t.line))                  # `X is Expr`
        elseif t.kind == :atom && name in R2_PREFIX_GOALS && nxt !== nothing &&
            _r2_operand_start(nxt) &&
            !(k > 1 && _r2_operand_end(clause[k - 1]))
            push!(out, (name, 1, t.line))                  # `:- dynamic foo/1.`
        else
            prev = k > 1 ? clause[k - 1] : nothing
            isempty(stack) || !(last(stack) in ("[", "c")) || continue
            pok =
                prev !== nothing && prev.kind in (:sym, :punct) &&
                prev.text in _R2_GOAL_PREV
            nok =
                nxt === nothing || (nxt.kind in (:sym, :punct) && nxt.text in _R2_GOAL_NEXT)
            pok && nok && push!(out, (name, 0, t.line))
        end
    end
    return out
end

"The `name/arity` heads the clauses of a Prolog text define (module-qualified heads and DCG rules included)."
function r2_heads(clauses::Vector{Vector{R2Tok}})::Set{String}
    out = Set{String}()
    for cl in clauses
        (isempty(cl) || (cl[1].kind == :sym && cl[1].text in (":-", "?-"))) && continue
        k = 1
        if length(cl) > 2 && cl[2].kind == :sym && cl[2].text == ":" &&
            cl[1].kind in (:atom, :qatom)
            k = 3
        end
        k <= length(cl) || continue
        name = r2_atom_name(cl[k])
        name === nothing && continue
        nxt = k < length(cl) ? cl[k + 1] : nothing
        if nxt !== nothing && nxt.kind == :punct && nxt.text == "(" && nxt.adj
            a, close = r2_arity(cl, k + 1)
            after = close < length(cl) ? cl[close + 1] : nothing
            dcg = after !== nothing && after.kind == :sym && after.text == "-->"
            push!(out, "$name/$(a + (dcg ? 2 : 0))")
        elseif nxt === nothing || (nxt.kind == :sym && nxt.text in (":-", "-->"))
            push!(out, "$name/$(nxt !== nothing && nxt.text == "-->" ? 2 : 0)")
        end
    end
    return out
end

# ── the boot list: boot/load.pl's consults and their `:- if(…)` conditions ───────────────────────────

const _R2LoadEntry = @NamedTuple{file::String, cond::String, loaded::Bool}
const _R2FileCounts = @NamedTuple{
    rel::String, loaded::Bool, exists::Bool, done::Int, nmissing::Int, platform::Int
}

"What the kernel's flags say about the conditions of load.pl (os/pl-prologflag.jl: `threads` is false in the kernel)."
const R2_KERNEL_FLAGS = Dict("threads" => "false")

"`true`/`false` for a `current_prolog_flag(F, V)` condition on a flag in `R2_KERNEL_FLAGS`; `nothing` when undecided."
function r2_eval_cond(cond::AbstractString)::Union{Bool, Nothing}
    m = match(r"^current_prolog_flag\(\s*(\w+)\s*,\s*(\w+)\s*\)$", strip(cond))
    m === nothing && return nothing
    haskey(R2_KERNEL_FLAGS, m[1]) || return nothing
    return R2_KERNEL_FLAGS[m[1]] == m[2]
end

"""
The files `load.pl` consults, in order: `(file = "gc", cond = "", loaded = true)` — `cond` is the `:- if(…)` text in force
(`""` when none), `loaded` false when the kernel's flags make it false.
"""
function r2_load_list(load_pl::AbstractString)
    out = _R2LoadEntry[]
    stack = Tuple{String, Bool}[]                         # (cond text, value the branch needs; nothing → true)
    for cl in r2_clauses(r2_tokenize(load_pl))
        (length(cl) >= 2 && cl[1].kind == :sym && cl[1].text == ":-") || continue
        head = r2_atom_name(cl[2])
        head === nothing && continue
        if head == "if" && length(cl) >= 4
            push!(stack, (join(t.text for t in cl[4:(end - 1)]), true))
        elseif head == "else" && !isempty(stack)
            stack[end] = (stack[end][1], !stack[end][2])
        elseif head == "endif" && !isempty(stack)
            pop!(stack)
        elseif head in ("consult", "ensure_loaded", "load_files")
            names = String[]
            for k in 3:length(cl)
                nm = r2_atom_name(cl[k])
                nm === nothing && continue
                k < length(cl) && cl[k + 1].kind == :sym && cl[k + 1].text == ":" &&
                    continue   # `user:` prefix
                push!(names, nm)
            end
            cond = join((s[2] ? s[1] : "!(" * s[1] * ")" for s in stack), " && ")
            vals = [r2_eval_cond(s[1]) for s in stack]
            loaded = all(((v, s),) -> v === nothing || v == s[2], zip(vals, stack))
            for nm in names
                push!(out, (; file=nm, cond, loaded))
            end
        end
    end
    return out
end

"The `library(X)` names a Prolog text's `use_module`/`autoload`/`ensure_loaded`/`reexport` directives name."
function r2_library_deps(text::AbstractString)::Vector{String}
    out = String[]
    for cl in r2_clauses(r2_tokenize(text))
        (length(cl) >= 2 && cl[1].kind == :sym && cl[1].text == ":-") || continue
        r2_atom_name(cl[2]) in ("use_module", "autoload", "ensure_loaded", "reexport") ||
            continue
        for k in 3:(length(cl) - 2)
            if r2_atom_name(cl[k]) == "library" && cl[k + 1].kind == :punct &&
                cl[k + 1].text == "("
                j = k + 2
                parts = String[]
                while j <= length(cl) && !(cl[j].kind == :punct && cl[j].text == ")")
                    push!(parts, something(r2_atom_name(cl[j]), cl[j].text))
                    j += 1
                end
                isempty(parts) || push!(out, join(parts))
            end
        end
    end
    return unique!(out)
end

"Library files the boot always reaches at load time (evidence/R2/boot_features.md: `library(debug)` at tabling.pl:119)."
const R2_LIBRARY_SEEDS = ("debug",)

# ── the pin's C: predicates and VM instructions ───────────────────────────────────────────────────────

"One definition at the pin: `kind` \"pred\" (`key` = `name/arity`) or \"vmi\" (`key` = the instruction), its file, its condition."
struct R2Up
    kind::String
    key::String
    file::String
    cls::String            # \"\" | \"threads\" | \"other\" | \"apple\" | \"windows\" (the preprocessor conditions in force)
    cond::String
end

const _R2_CLS_RANK = Dict(
    "" => 0, "threads" => 1, "other" => 2, "apple" => 3, "windows" => 4
)

"The class of a preprocessor condition stack: the worst entry (windows > apple > other > threads), a negated entry counts for nothing."
function r2_cond_class(stack::Vector{String})::String
    cls = ""
    for e in stack
        (startswith(e, "!") || e in ("1", "0", "")) && continue
        c = if occursin(r"\b(__WINDOWS__|_WIN32|WIN32|__MINGW32__)\b", e)
            "windows"
        elseif occursin(r"\b(__APPLE__|__MACH__)\b", e)
            "apple"
        elseif occursin(r"\bO_PLMT\b", e)
            "threads"
        else
            "other"
        end
        _R2_CLS_RANK[c] > _R2_CLS_RANK[cls] && (cls = c)
    end
    return cls
end

"C comments removed from `text`, one entry per source line (a line inside a block comment is empty)."
function r2_strip_c(text::AbstractString)::Vector{String}
    out = String[]
    incomment = false
    for line in split(String(text), '\n')
        line = String(line)
        if incomment
            j = findfirst("*/", line)
            if j === nothing
                push!(out, "")
                continue
            end
            line = line[(last(j) + 1):end]
            incomment = false
        end
        line = replace(line, r"/\*.*?\*/" => " ")
        j = findfirst("/*", line)
        if j !== nothing
            line = line[1:(first(j) - 1)]
            incomment = true
        end
        push!(out, String(replace(line, r"//.*$" => "")))
    end
    return out
end

_r2_unescape(s::AbstractString)::String = String(replace(s, r"\\(.)" => s"\1"))

const _R2_RX_NAME = "\"((?:[^\"\\\\]|\\\\.)*)\""
const _R2_RX_PRED = Regex(
    "^\\s*(?:PRED_IMPL|PRED_SHARE|PRED_DEF|FRG)\\(\\s*$(_R2_RX_NAME)\\s*,\\s*(\\d+)\\s*,"
)
const _R2_RX_REGF = Regex(
    "PL_register_foreign(?:_in_module)?\\(\\s*(?:$(_R2_RX_NAME)\\s*,\\s*)?$(_R2_RX_NAME)\\s*,\\s*(\\d+)\\s*,"
)
const _R2_RX_VMI = r"^\s*VMI\(\s*(\w+)\s*,"

"The predicate and VM-instruction definitions in one upstream C file's text (loose: a first-line pattern, a 3-line window)."
function r2_scan_c(text::AbstractString, file::AbstractString)::Vector{R2Up}
    out = R2Up[]
    lines = r2_strip_c(text)
    stack = String[]
    for (i, line) in enumerate(lines)
        m = match(r"^\s*#\s*(ifdef|ifndef|if|elif|else|endif)\b\s*(.*)$", line)
        if m !== nothing
            d, arg = m[1], strip(m[2])
            if d == "if"
                push!(stack, arg)
            elseif d == "ifdef"
                push!(stack, "defined($arg)")
            elseif d == "ifndef"
                push!(stack, "!defined($arg)")
            elseif d == "elif" && !isempty(stack)
                stack[end] = arg
            elseif d == "else" && !isempty(stack)
                stack[end] = "!(" * stack[end] * ")"
            elseif d == "endif" && !isempty(stack)
                pop!(stack)
            end
            continue
        end
        window = join(@view(lines[i:min(i + 2, end)]), " ")
        cls, cond = r2_cond_class(stack), join(stack, " && ")
        mp = match(_R2_RX_PRED, window)
        if mp !== nothing
            push!(out, R2Up("pred", _r2_unescape(mp[1]) * "/" * mp[2], file, cls, cond))
        end
        mr = match(_R2_RX_REGF, window)
        if mr !== nothing && mr[2] !== nothing && occursin("PL_register_foreign", line)
            push!(out, R2Up("pred", _r2_unescape(mr[2]) * "/" * mr[3], file, cls, cond))
        end
        mv = match(_R2_RX_VMI, line)
        if mv !== nothing && endswith(file, "pl-vmi.c")
            push!(out, R2Up("vmi", mv[1], file, cls, cond))
        end
    end
    return out
end

"The snapshot file's text (`docs/r2_upstream.tsv`): one definition per line, sorted, with a header naming the pin."
function r2_snapshot_text(rows::Vector{R2Up}, pin::AbstractString)::String
    body = sort!(
        unique!([join((r.kind, r.key, r.file, r.cls, r.cond), '\t') for r in rows])
    )
    return "# swipl-devel $pin: the predicate and VM-instruction definitions of src/**/*.c, generated by tools/port_check.jl --write-inventory — do not hand-edit\n" *
           "# kind\tkey\tfile\tclass\tcondition\n" * join(body, '\n') * "\n"
end

"The definitions a snapshot's text holds."
function r2_read_snapshot(text::AbstractString)::Vector{R2Up}
    out = R2Up[]
    for l in split(String(text), '\n')
        (isempty(l) || startswith(l, "#")) && continue
        f = split(l, '\t')
        length(f) >= 4 || continue
        push!(out, R2Up(f[1], f[2], f[3], f[4], length(f) >= 5 ? f[5] : ""))
    end
    return out
end

"The pinned commit of `tools/SWIPL_VERSION` (the `commit:` line), or `nothing`."
function r2_pin(root::AbstractString)::Union{String, Nothing}
    f = joinpath(root, "tools", "SWIPL_VERSION")
    isfile(f) || return nothing
    for l in eachline(f)
        m = match(r"^commit:\s*([0-9a-f]{40})\s*$", l)
        m === nothing || return String(m[1])
    end
    return nothing
end

"A swipl-devel checkout that has the pin commit (LOGICKERNEL_UPSTREAM_SWIPL_DEVEL, ~/dev-zone/swipl-devel-<pin8>, ~/dev-zone/swipl-devel), or `nothing`."
function r2_pin_checkout(pin::AbstractString)::Union{String, Nothing}
    cands = String[]
    haskey(ENV, "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL") &&
        push!(cands, ENV["LOGICKERNEL_UPSTREAM_SWIPL_DEVEL"])
    push!(cands, joinpath(homedir(), "dev-zone", "swipl-devel-" * pin[1:8]))
    push!(cands, joinpath(homedir(), "dev-zone", "swipl-devel"))
    for d in cands
        isdir(d) || continue
        success(
            pipeline(
                `git -C $d cat-file -e $(pin * "^{commit}")`; stdout=devnull, stderr=devnull
            )
        ) &&
            return d
    end
    return nothing
end

"Every predicate and VM-instruction definition of `src/**/*.c` at `pin` in the checkout `up` (read with `git show`, never the working tree)."
function r2_pin_c_rows(up::AbstractString, pin::AbstractString)::Vector{R2Up}
    files = split(
        read(`git -C $up ls-tree -r --name-only $pin src`, String), '\n'; keepempty=false
    )
    rows = R2Up[]
    for f in sort!(String.(filter(f -> endswith(f, ".c"), files)))
        text = String(read(`git -C $up show $(pin * ":" * f)`))
        isvalid(text) ||
            (text = String(map(b -> b < 0x80 ? b : UInt8('?'), codeunits(text))))
        append!(rows, r2_scan_c(text, f))
    end
    return rows
end

# ── the kernel's side ────────────────────────────────────────────────────────────────────────────────

"The `src/**/*.jl` texts of the kernel (path relative to `root` → text)."
function r2_kernel_texts(root::AbstractString)::Dict{String, String}
    out = Dict{String, String}()
    for (d, _, fs) in walkdir(joinpath(root, "src")), f in fs
        endswith(f, ".jl") &&
            (out[relpath(joinpath(d, f), root)] = read(joinpath(d, f), String))
    end
    return out
end

"`name/arity` of every `PL_extension(\"name\", N, …)` call (the entries of the `PL_predicates_from_*` tables); comments (also trailing ones) blanked first."
function r2_registered(texts)::Set{String}
    out = Set{String}()
    rx = Regex("PL_extension\\(\\s*$(_R2_RX_NAME)\\s*,\\s*(\\d+)")
    for t in texts
        body = r2_strip_jl(t)                            # comments blanked, strings kept: `PL_extension(  # note` then the name
        for m in eachmatch(rx, body)
            push!(out, _r2_unescape(m[1]) * "/" * m[2])
        end
    end
    return out
end

"Predicates the clause compiler compiles inline, with no callable predicate behind them (evidence/R2/missing_c_preds_recount.md: C_CUT)."
const R2_COMPILED_INLINE = ("!/0",)

# ── the boot side: which files, which references ─────────────────────────────────────────────────────

"One boot or load-path library file: `rel` (path under the vendor tree), `kind` boot|library, `loaded`, the `:- if` text in force."
struct R2File
    rel::String
    kind::String
    loaded::Bool
    cond::String
    exists::Bool
end

"""
The files the boot reaches, in order: boot/init.pl, boot/load.pl, the files load.pl consults (a file under a false
condition is listed with `loaded = false` and not scanned), then the load-path library files: `R2_LIBRARY_SEEDS` and the
`library(X)` names of the loaded boot files' directives, and the names the seeds' own directives name (depth 1).
"""
function r2_boot_files(root::AbstractString)::Vector{R2File}
    vend = joinpath(root, "vendor", "swipl-devel")
    out = R2File[]
    for f in ("init", "load")
        rel = "boot/$f.pl"
        push!(out, R2File(rel, "boot", true, "", isfile(joinpath(vend, rel))))
    end
    isfile(joinpath(vend, "boot", "load.pl")) || return out
    for l in r2_load_list(read(joinpath(vend, "boot", "load.pl"), String))
        rel = "boot/$(l.file).pl"
        push!(out, R2File(rel, "boot", l.loaded, l.cond, isfile(joinpath(vend, rel))))
    end
    libs = String[collect(R2_LIBRARY_SEEDS)...]
    for f in out
        (f.kind == "boot" && f.loaded && f.exists) || continue
        append!(libs, r2_library_deps(read(joinpath(vend, f.rel), String)))
    end
    unique!(libs)
    for l in copy(libs)
        p = joinpath(vend, "library", l * ".pl")
        isfile(p) && append!(libs, r2_library_deps(read(p, String)))
    end
    for l in unique!(libs)
        rel = "library/$l.pl"
        push!(out, R2File(rel, "library", true, "", isfile(joinpath(vend, rel))))
    end
    return out
end

"""
`(refs, defined)` of the files that are loaded and exist: `refs` maps `name/arity` to the file `rel`s that call it
(`r2_calls`), `defined` is the set of heads the boot Prolog files define themselves (those are no C gap).
"""
function r2_boot_scan(root::AbstractString, files::Vector{R2File})
    vend = joinpath(root, "vendor", "swipl-devel")
    refs = Dict{String, Vector{String}}()
    defined = Set{String}()
    for f in files
        (f.loaded && f.exists) || continue
        cls = r2_clauses(r2_tokenize(read(joinpath(vend, f.rel), String)))
        f.kind == "boot" && union!(defined, r2_heads(cls))
        seen = Set{String}()
        for cl in cls, (name, a, _) in r2_calls(cl)
            k = "$name/$a"
            k in seen && continue
            push!(seen, k)
            push!(get!(refs, k, String[]), f.rel)
        end
    end
    return (; refs, defined)
end

# ── rows ─────────────────────────────────────────────────────────────────────────────────────────────

"""
One line of the status table. `cat`: pred | refusal | flag | vmi. `key`: the owner key (`pred:name/N`, …). `status`: done |
refused | missing | platform (a Windows/macOS-only definition: out of the count). `refs`: the boot and library files that
reach it. `cfile`: the upstream C file (pred, vmi) or the kernel file (refusal). `cls`: the C condition class.
"""
struct R2Row
    cat::String
    key::String
    label::String
    status::String
    cfile::String
    cls::String
    refs::Vector{String}
    detail::String
end

"""
The predicate rows: every C-defined predicate (at the pin) that a boot or library file calls and the boot Prolog does not
define itself — done when registered in the kernel (or compiled inline), else missing; platform-only ones leave the count.
"""
function r2_pred_rows(
    refs::Dict{String, Vector{String}}, up::Vector{R2Up}, registered::Set{String},
    defined::Set{String}
)::Vector{R2Row}
    best = Dict{String, R2Up}()
    for u in up
        u.kind == "pred" || continue
        haskey(refs, u.key) || continue
        (!haskey(best, u.key) || _R2_CLS_RANK[u.cls] < _R2_CLS_RANK[best[u.key].cls]) &&
            (best[u.key] = u)
    end
    rows = R2Row[]
    for k in sort!(collect(keys(best)))
        k in defined && continue
        u = best[k]
        st = if k in registered || k in R2_COMPILED_INLINE
            "done"
        elseif u.cls in ("windows", "apple")
            "platform"
        else
            "missing"
        end
        push!(rows, R2Row("pred", "pred:" * k, k, st, u.file, u.cls, sort(refs[k]), u.cond))
    end
    return rows
end

"Per file (in boot order): `(rel, loaded, done, missing, platform)` over the predicate rows its calls reach."
function r2_file_table(files::Vector{R2File}, rows::Vector{R2Row})
    out = _R2FileCounts[]
    for f in files
        mine = [r for r in rows if r.cat == "pred" && f.rel in r.refs]
        push!(
            out,
            (;
                rel=f.rel, loaded=f.loaded, exists=f.exists,
                done=count(r -> r.status == "done", mine),
                nmissing=count(r -> r.status == "missing", mine),
                platform=count(r -> r.status == "platform", mine)
            )
        )
    end
    return out
end

"The status counts of rows: `(done, refused, missing, platform)`."
function r2_counts(rows::Vector{R2Row})
    return (;
        done=count(r -> r.status == "done", rows),
        refused=count(r -> r.status == "refused", rows),
        nmissing=count(r -> r.status == "missing", rows),
        platform=count(r -> r.status == "platform", rows)
    )
end

# ── the refusals: what the kernel raises instead of doing a thing (slice 2) ──────────────────────────

# The refusal exception's name and the helpers that raise it, built by concatenation: the tool finds the sites by NAME
# pattern (the constructor `Name{T}(culprit, what, step)`), exactly as the scan of evidence/R2/boot_features.md did.
const R2_REFUSAL_EXCEPTION = "Not" * "Ported" * "Error"
const R2_FLAG_REFUSAL_HELPER = "_flag_" * "not" * "_ported"
const R2_QLF_REFUSAL_HELPER = "_qlf_refused"

"""
`text` of a Julia source with every comment and every triple-quoted string (docstring) blanked, byte for byte: the offsets
and the line breaks stay, so a pattern found in the result sits at the same place in the original. Plain strings stay.
"""
function r2_strip_jl(text::AbstractString)::String
    cs = collect(String(text))
    out = copy(cs)
    n, i = length(cs), 1
    while i <= n
        c = cs[i]
        if c == '#'
            while i <= n && cs[i] != '\n'
                out[i] = ' '
                i += 1
            end
        elseif c == '"'
            if i + 2 <= n && cs[i + 1] == '"' && cs[i + 2] == '"'
                j = i + 3
                while j + 2 <= n && !(cs[j] == '"' && cs[j + 1] == '"' && cs[j + 2] == '"')
                    cs[j] == '\\' && (j += 1)
                    j += 1
                end
                for k in (i + 3):min(j - 1, n)
                    cs[k] != '\n' && (out[k] = ' ')
                end
                i = j + 3
            else
                j = i + 1
                while j <= n && cs[j] != '"'
                    cs[j] == '\\' && (j += 1)
                    j += 1
                end
                i = j + 1
            end
        elseif c == '\'' && i + 2 <= n
            prev = i > 1 ? cs[i - 1] : ' '
            if _r2_isalnum(prev) || prev in ")]}'.!_"                 # a transpose, not a character
                i += 1
            elseif cs[i + 1] == '\\'
                j = i + 2
                while j <= n && cs[j] != '\''
                    j += 1
                end
                i = j + 1
            elseif cs[i + 2] == '\''
                i += 3
            else
                i += 1
            end
        else
            i += 1
        end
    end
    return String(out)
end

"The top-level arguments of the call whose `(` is at byte `p` of `s` (strings and brackets respected), and the index of its `)`."
function r2_call_args(s::String, p::Int)::Tuple{Vector{String}, Int}
    args = String[]
    depth, a = 0, p + 1
    j = p
    n = ncodeunits(s)
    while j <= n
        b = codeunit(s, j)
        if b == UInt8('"')
            j += 1
            while j <= n && codeunit(s, j) != UInt8('"')
                codeunit(s, j) == UInt8('\\') && (j += 1)
                j += 1
            end
        elseif b in (UInt8('('), UInt8('['), UInt8('{'))
            depth += 1
        elseif b in (UInt8(')'), UInt8(']'), UInt8('}'))
            depth -= 1
            if depth == 0
                push!(args, strip(s[a:(j - 1)]))
                return (filter!(!isempty, args), j)
            end
        elseif b == UInt8(',') && depth == 1
            push!(args, strip(s[a:(j - 1)]))
            a = j + 1
        end
        j += 1
    end
    return (args, n)
end

"The content of a string literal `\"…\"` argument, or the argument text itself when it is no literal."
function _r2_lit(arg::AbstractString)::String
    arg = replace(arg, r"\"\s*\*\s*\"" => "")            # `"a; " * newline "b"`: a literal split over lines is one literal
    m = match(r"^\"(.*)\"$"s, arg)
    return m === nothing ? String(arg) : String(m[1])
end

"The enclosing top-level function of byte `pos`: the last `function name` / `name(…) =` at column 0 before it (`\"(top)\"` if none)."
function _r2_enclosing(funcs::Vector{Tuple{Int, String}}, pos::Int)::String
    name = "(top)"
    for (p, f) in funcs
        p <= pos || break
        name = f
    end
    return name
end

"The `(byte offset, name)` of every function the stripped source `s` defines at column 0."
function r2_functions(s::String)::Vector{Tuple{Int, String}}
    out = Tuple{Int, String}[]
    for m in eachmatch(r"^function\s+([\w.!]+)"m, s)
        push!(out, (m.offset, String(m[1])))
    end
    for m in eachmatch(r"^([\w!]+)\([^\n]*\)\s*(?:::[^=\n]+)?=\s"m, s)
        push!(out, (m.offset, String(m[1])))
    end
    return sort!(out)
end

"A line number of byte `pos` in `s`."
_r2_line(s::String, pos::Int)::Int =
    1 + count(==(UInt8('\n')), codeunits(s)[1:max(pos - 1, 0)])

"""
The refusal rows of the kernel texts (path → text): one per throw site of the refusal exception (the helpers' own constructor
excepted) and one per name passed to the QLF helper. `key` = `refusal:file::function::what` (no line number: it moves), `label`
the `what` text, `detail` `line N; step S` as the site names it. The flag-setter refusals are `r2_flag_refusals` (category flag).
"""
function r2_refusal_rows(texts::AbstractDict{String, String})::Vector{R2Row}
    rows = R2Row[]
    seen = Dict{String, Int}()
    ctor = Regex(R2_REFUSAL_EXCEPTION * "\\{[^}]*\\}\\(")
    qlf = Regex(
        R2_QLF_REFUSAL_HELPER * "\\(\\s*T\\s*,\\s*$(_R2_RX_NAME)\\s*,\\s*(\\d+)\\s*\\)"
    )
    helpers = (R2_FLAG_REFUSAL_HELPER, R2_QLF_REFUSAL_HELPER)
    squeeze(x) = strip(replace(x, r"\s+" => " "))
    function add!(file, fn, what, step, line)
        what, step = squeeze(what), squeeze(step)          # a literal split over two lines would break a TSV or Markdown row
        base = "refusal:$file::$fn::" * first(what, 60)
        k = if (seen[base] = get(seen, base, 0) + 1) == 1
            base
        else
            base * " #" * string(seen[base])
        end
        push!(
            rows,
            R2Row(
                "refusal", k, what, "refused", file, "", String[], "line $line; step $step"
            )
        )
    end
    for file in sort!(collect(keys(texts)))
        s = r2_strip_jl(texts[file])
        funcs = r2_functions(s)
        for m in eachmatch(ctor, s)
            fn = _r2_enclosing(funcs, m.offset)
            fn in helpers && continue
            args, _ = r2_call_args(s, m.offset + ncodeunits(m.match) - 1)
            what = length(args) >= 2 ? _r2_lit(args[2]) : "?"
            step = length(args) >= 3 ? _r2_lit(args[3]) : "?"
            add!(file, fn, what, step, _r2_line(s, m.offset))
        end
        for m in eachmatch(qlf, s)
            add!(
                file,
                R2_QLF_REFUSAL_HELPER,
                "QLF predicate $(_r2_unescape(m[1]))/$(m[2])",
                "LB3",
                _r2_line(s, m.offset)
            )
        end
    end
    return rows
end

# ── the flags (slice 3) ──────────────────────────────────────────────────────────────────────────────

const R2_FLAG_PREDS = (
    "current_prolog_flag", "set_prolog_flag", "create_prolog_flag", "push_prolog_flag"
)

"""
`(refs, created)` over the loaded boot and library files: `refs` maps a flag name (the first argument of
`current_/set_/create_/push_prolog_flag`, when it is an atom) to the files `rel` that name it, `created` is the set of
flags a boot or library `create_prolog_flag` defines itself (those are no kernel gap).
"""
function r2_flag_scan(root::AbstractString, files::Vector{R2File})
    vend = joinpath(root, "vendor", "swipl-devel")
    refs = Dict{String, Vector{String}}()
    created = Set{String}()
    for f in files
        (f.loaded && f.exists) || continue
        for cl in r2_clauses(r2_tokenize(read(joinpath(vend, f.rel), String)))
            for k in 1:(length(cl) - 2)
                cl[k].kind == :atom && cl[k].text in R2_FLAG_PREDS || continue
                cl[k + 1].kind == :punct && cl[k + 1].text == "(" && cl[k + 1].adj ||
                    continue
                flag = r2_atom_name(cl[k + 2])
                flag === nothing && continue
                v = get!(refs, flag, String[])
                f.rel in v || push!(v, f.rel)
                cl[k].text == "create_prolog_flag" && push!(created, flag)
            end
        end
    end
    return (; refs, created)
end

"The flags the kernel defines: `setPrologFlag(gd, [ld,] \"name\", …)` in src/**/*.jl (comments blanked, multi-line calls read)."
function r2_flags_defined(texts)::Set{String}
    out = Set{String}()
    rx = Regex("\\bsetPrologFlag\\(\\s*gd\\s*,\\s*(?:ld\\s*,\\s*)?$(_R2_RX_NAME)")
    for t in texts, m in eachmatch(rx, r2_strip_jl(t))
        push!(out, _r2_unescape(m[1]))
    end
    return out
end

"""
The flag-setter refusals: one `(flag, effect, file, line)` per call of the flag refusal helper. `flag` is the `name == "X"` (or
`sym_key(k) == sym_key(mk_sym(T, :X))`) of the three lines before the call, or `nothing` (a refusal by predicate, e.g.
`ci_is_flag(k) && …`): such a row is keyed by its effect text.
"""
function r2_flag_refusals(texts::AbstractDict{String, String})
    out = Tuple{Union{String, Nothing}, String, String, Int}[]
    call = Regex("(?<!function )\\b" * R2_FLAG_REFUSAL_HELPER * "\\(")
    byname = r"name\s*==\s*\"([^\"]*)\"|sym_key\(k\)\s*==\s*sym_key\(mk_sym\(T,\s*:(\w+)\)\)"
    for file in sort!(collect(keys(texts)))
        s = r2_strip_jl(texts[file])
        lines = split(s, '\n')
        for m in eachmatch(call, s)
            args, _ = r2_call_args(s, m.offset + ncodeunits(m.match) - 1)
            effect = length(args) >= 2 ? _r2_lit(args[2]) : "?"
            ln = _r2_line(s, m.offset)
            ctx = join(lines[max(1, ln - 3):ln], '\n')
            hits = collect(eachmatch(byname, ctx))
            flag = isempty(hits) ? nothing : String(something(last(hits)[1], last(hits)[2]))
            push!(out, (flag, effect, file, ln))
        end
    end
    return out
end

"""
The flag rows (category `flag`, key `flag:NAME`): every flag the boot reaches plus every flag a setter refuses. refused (the
setter refuses it; the row's detail names the effect) | done (the kernel or the boot defines it) | missing.
"""
function r2_flag_rows(
    refs, created::Set{String}, defined::Set{String}, refusals
)::Vector{R2Row}
    refused = Dict{String, Tuple{String, String, Int}}()
    rows = R2Row[]
    for (flag, effect, file, ln) in refusals
        if flag === nothing
            push!(
                rows,
                R2Row(
                    "flag",
                    "flag:(" * effect * ")",
                    effect,
                    "refused",
                    file,
                    "",
                    String[],
                    "line $ln; setter refusal by predicate"
                )
            )
        elseif !haskey(refused, flag)
            refused[flag] = (effect, file, ln)
        end
    end
    for k in sort!(collect(union(keys(refs), keys(refused))))
        rs = sort(get(refs, k, String[]))
        if haskey(refused, k)
            e, file, ln = refused[k]
            push!(
                rows, R2Row("flag", "flag:" * k, k, "refused", file, "", rs, "line $ln; $e")
            )
        else
            push!(
                rows,
                R2Row(
                    "flag",
                    "flag:" * k,
                    k,
                    (k in defined || k in created) ? "done" : "missing",
                    "",
                    "",
                    rs,
                    ""
                )
            )
        end
    end
    return rows
end

# ── the VM instructions (slice 3) ────────────────────────────────────────────────────────────────────

"The `# PORT: pl-vmi.c NAME` markers of the kernel texts (RAW text: they are comment lines)."
function r2_vmi_markers(texts)::Set{String}
    out = Set{String}()
    for t in texts, m in eachmatch(r"^[ \t]*#[ \t]*PORT:[ \t]*pl-vmi\.c[ \t]+(\w+)"m, t)
        push!(out, String(m[1]))
    end
    return out
end

"One row per VM instruction of pl-vmi.c at the pin: done when a marker names it, else missing."
function r2_vmi_rows(up::Vector{R2Up}, markers::Set{String})::Vector{R2Row}
    rows = R2Row[]
    for k in sort!(unique!([u.key for u in up if u.kind == "vmi"]))
        u = first(u for u in up if u.kind == "vmi" && u.key == k)
        push!(
            rows,
            R2Row(
                "vmi",
                "vmi:" * k,
                k,
                k in markers ? "done" : "missing",
                u.file,
                u.cls,
                String[],
                u.cond
            )
        )
    end
    return rows
end

# ── everything ────────────────────────────────────────────────────────────────────────────────────────

"The upstream definitions: the committed snapshot `docs/r2_upstream.tsv` when it exists, else the pin's checkout."
function r2_upstream(root::AbstractString)::Vector{R2Up}
    snap = joinpath(root, "docs", "r2_upstream.tsv")
    isfile(snap) && return r2_read_snapshot(read(snap, String))
    pin = r2_pin(root)
    pin === nothing && error("r2_status: no commit: line in tools/SWIPL_VERSION")
    co = r2_pin_checkout(pin)
    co === nothing &&
        error("r2_status: no docs/r2_upstream.tsv and no swipl-devel checkout with $pin")
    return r2_pin_c_rows(co, pin)
end

"All rows (predicates, refusal sites, flags, VM instructions) and the files of the boot, for the tree at `root`."
function r2_collect(root::AbstractString, up::Vector{R2Up})
    texts = r2_kernel_texts(root)
    files = r2_boot_files(root)
    scan = r2_boot_scan(root, files)
    fscan = r2_flag_scan(root, files)
    rows = R2Row[]
    preds = r2_pred_rows(scan.refs, up, r2_registered(values(texts)), scan.defined)
    append!(rows, preds)
    append!(rows, r2_refusal_rows(texts))
    append!(
        rows,
        r2_flag_rows(
            fscan.refs,
            fscan.created,
            r2_flags_defined(values(texts)),
            r2_flag_refusals(texts)
        )
    )
    append!(rows, r2_vmi_rows(up, r2_vmi_markers(values(texts))))
    return (; rows, files, preds)
end

# ── the snapshot file and its guards (slice 4) ───────────────────────────────────────────────────────

"The committed snapshot of the pin's definitions."
const R2_SNAPSHOT = "docs/r2_upstream.tsv"
"The hand-edited owners file."
const R2_OWNERS = "docs/r2_owners.tsv"

"The pin a snapshot's header line names (`# swipl-devel <40 hex>: …`), or `nothing`."
function r2_snapshot_pin(text::AbstractString)::Union{String, Nothing}
    m = match(r"^# swipl-devel ([0-9a-f]{40}):", text)
    return m === nothing ? nothing : String(m[1])
end

"""
The snapshot's violations: MISSING (no file), EMPTY (no definition read), BAD-PIN (its header names another commit than
tools/SWIPL_VERSION — a sync that did not regenerate it), and DRIFT against the pin's C where a checkout with the pin is found
(`git show`, never the working tree; CI has none, so there the block is checked against the snapshot only).
"""
function r2_upstream_violations(root::AbstractString)::Vector{String}
    snap = joinpath(root, R2_SNAPSHOT)
    isfile(snap) || return [
        "R2-UPSTREAM-MISSING $R2_SNAPSHOT: run tools/port_check.jl --write-inventory"
    ]
    text = read(snap, String)
    v = String[]
    isempty(r2_read_snapshot(text)) &&
        push!(v, "R2-UPSTREAM-EMPTY $R2_SNAPSHOT: no definition in it")
    pin = r2_pin(root)
    have = r2_snapshot_pin(text)
    if pin !== nothing && have != pin
        push!(
            v,
            "R2-UPSTREAM-PIN $R2_SNAPSHOT: header names $(have === nothing ? "no commit" : have[1:8]), tools/SWIPL_VERSION $(pin[1:8]) — run tools/port_check.jl --write-inventory"
        )
        return v
    end
    co = pin === nothing ? nothing : r2_pin_checkout(pin)
    if co !== nothing && r2_snapshot_text(r2_pin_c_rows(co, pin), pin) != text
        push!(
            v,
            "R2-UPSTREAM-DRIFT $R2_SNAPSHOT: differs from src/*.c at $(pin[1:8]) — run tools/port_check.jl --write-inventory"
        )
    end
    return v
end

"Rewrite the snapshot from the pin's checkout; returns its path. An error when no checkout has the pin."
function r2_write_snapshot(root::AbstractString)::String
    pin = r2_pin(root)
    pin === nothing && error("r2_status: no commit: line in tools/SWIPL_VERSION")
    co = r2_pin_checkout(pin)
    co === nothing && error(
        "r2_status: no swipl-devel checkout with $pin (LOGICKERNEL_UPSTREAM_SWIPL_DEVEL)"
    )
    path = joinpath(root, R2_SNAPSHOT)
    write(path, r2_snapshot_text(r2_pin_c_rows(co, pin), pin))
    return path
end

# ── the owners (slice 4) ─────────────────────────────────────────────────────────────────────────────

"""
The owners file: `(owners, bad)`. `owners` maps a key to `(owner, note)`, `bad` are the violations (a line with fewer than two
fields, an empty key or owner, a key twice). Keys: `pred:`, `flag:`, `vmi:`, `refusal:` exact; `cfile:<upstream C basename>`
(every pred and vmi row of that file without an exact key); `kfile:<kernel file basename>` (every refusal row of that file).
"""
function r2_owners_parse(text::AbstractString)
    owners = Dict{String, Tuple{String, String}}()
    bad = String[]
    for (n, l) in enumerate(split(String(text), '\n'))
        (isempty(strip(l)) || startswith(l, "#")) && continue
        f = split(l, '\t')
        if length(f) < 2 || isempty(strip(f[1])) || isempty(strip(f[2]))
            push!(bad, "R2-OWNER-BAD $R2_OWNERS:$n: want `key<TAB>owner<TAB>note`")
        elseif haskey(owners, String(f[1]))
            push!(bad, "R2-OWNER-DUP $R2_OWNERS:$n: key $(f[1]) twice")
        else
            owners[String(f[1])] = (
                String(strip(f[2])), length(f) >= 3 ? String(strip(f[3])) : ""
            )
        end
    end
    return (; owners, bad)
end

"The file keys a row falls back to when it has no exact owner key."
function r2_file_key(r::R2Row)::String
    base = basename(r.cfile)
    (isempty(base) || !(r.cat in ("pred", "vmi", "refusal"))) && return ""
    return (r.cat == "refusal" ? "kfile:" : "cfile:") * base
end

"The owner of a row: its exact key, else its file key, else \"\" (NO OWNER). Only rows that are not done owe one."
function r2_owner_of(r::R2Row, owners)::String
    haskey(owners, r.key) && return owners[r.key][1]
    fk = r2_file_key(r)
    (!isempty(fk) && haskey(owners, fk)) && return owners[fk][1]
    return ""
end

"Rows that owe an owner: missing or refused (done and platform rows are out of the burn-down)."
r2_owes(r::R2Row) = r.status in ("missing", "refused")

"The rows without an owner that owe one."
r2_no_owner(rows::Vector{R2Row}, owners) =
    [r for r in rows if r2_owes(r) && isempty(r2_owner_of(r, owners))]

"""
The owners file against the rows: BAD / DUP from the parse, STALE for a key that names no row that owes an owner (a finished
feature's row left: the porter removes its line; a typo).
"""
function r2_owner_violations(rows::Vector{R2Row}, text::AbstractString)::Vector{String}
    (; owners, bad) = r2_owners_parse(text)
    v = copy(bad)
    live = Set{String}()
    for r in rows
        r2_owes(r) || continue
        push!(live, r.key)
        fk = r2_file_key(r)
        isempty(fk) || push!(live, fk)
    end
    for k in sort!(collect(keys(owners)))
        k in live ||
            push!(v, "R2-OWNER-STALE $R2_OWNERS: key $k names no missing or refused row")
    end
    return v
end

# ── the rendering (slice 4) ──────────────────────────────────────────────────────────────────────────

const R2_BEGIN = "<!-- BEGIN GENERATED R2 status by tools/port_check.jl --write-inventory — do not hand-edit -->"
const R2_END = "<!-- END GENERATED R2 status -->"

const R2_CATS = (
    ("pred", "predicates (C-defined, reached by the boot)"), ("refusal", "refusal sites"),
    ("flag", "Prolog flags"), ("vmi", "VM instructions")
)

"A cell of a Markdown table: one line, `|` escaped."
_r2_cell(x::AbstractString) =
    replace(strip(replace(String(x), r"\s+" => " ")), "|" => "\\|")

"A row as a short code span for the by-owner list (the owner key without its category prefix for predicates and VM instructions)."
function _r2_short(r::R2Row)::String
    t = if r.cat == "flag"
        "flag " * r.label
    elseif r.cat == "refusal"
        "refusal " * first(r.label, 40) * (length(r.label) > 40 ? "…" : "")
    else
        r.label
    end
    return "`" * _r2_cell(replace(t, "`" => "'")) * "`"
end

"""
The block between `R2_BEGIN` and `R2_END`: counts per category, per boot file, the remaining rows by owner, the Mermaid chart.
`pin` and `nup` (the snapshot's pin and its number of definitions) are in the first line, so a snapshot change shows.
"""
function r2_render_rows(
    rows::Vector{R2Row},
    files::Vector{R2File},
    preds::Vector{R2Row},
    owners,
    pin::AbstractString,
    nup::Int
)::String
    io = IOBuffer()
    println(
        io,
        "Generated from `docs/r2_upstream.tsv` (swipl-devel `",
        first(pin, 8),
        "`: ",
        nup,
        " definitions), `docs/r2_owners.tsv` and the kernel's `src/`."
    )
    println(
        io,
        "A row is **done** (registered, defined or marked in the kernel), **refused** (the kernel raises the refusal on purpose), **missing**,"
    )
    println(
        io,
        "or **platform** (a Windows or macOS definition: out of the count). **NO OWNER** counts missing and refused rows no step owns yet."
    )
    println(io)
    println(io, "| category | done | refused | missing | platform | NO OWNER |")
    println(io, "|---|---:|---:|---:|---:|---:|")
    tot = [0, 0, 0, 0, 0]
    perc = Dict{String, NamedTuple}()
    for (cat, name) in R2_CATS
        rs = [r for r in rows if r.cat == cat]
        c = r2_counts(rs)
        no = length(r2_no_owner(rs, owners))
        perc[cat] = (; c..., no)
        println(
            io,
            "| ",
            name,
            " | ",
            c.done,
            " | ",
            c.refused,
            " | ",
            c.nmissing,
            " | ",
            c.platform,
            " | ",
            no,
            " |"
        )
        tot .+= [c.done, c.refused, c.nmissing, c.platform, no]
    end
    println(io, "| **total** | ", join(tot, " | "), " |")
    println(io)
    println(io, "#### The boot and library files")
    println(io)
    println(
        io,
        "Predicate rows each file's calls reach (a predicate several files call counts in each, so the columns do not add up to the table above)."
    )
    println(io)
    println(io, "| file | state | done | missing | platform |")
    println(io, "|---|---|---:|---:|---:|")
    for t in r2_file_table(files, preds)
        t.exists || continue
        state = t.loaded ? "loaded" : "skipped (conditional)"
        println(
            io,
            "| `",
            t.rel,
            "` | ",
            state,
            " | ",
            t.done,
            " | ",
            t.nmissing,
            " | ",
            t.platform,
            " |"
        )
    end
    println(io)
    println(io, "#### What is left, by owner")
    println(io)
    byowner = Dict{String, Vector{R2Row}}()
    for r in rows
        r2_owes(r) || continue
        o = r2_owner_of(r, owners)
        push!(get!(byowner, isempty(o) ? "NO OWNER" : o, R2Row[]), r)
    end
    order = sort!(collect(keys(byowner)); by=o -> (o == "NO OWNER", -length(byowner[o]), o))
    println(io, "| owner | rows | missing | refused | which (first 8) |")
    println(io, "|---|---:|---:|---:|---|")
    catrank = Dict("pred" => 1, "vmi" => 2, "flag" => 3, "refusal" => 4)
    for o in order
        rs = sort(byowner[o]; by=r -> (catrank[r.cat], r.key))
        which =
            join(_r2_short.(first(rs, 8)), ", ") *
            (length(rs) > 8 ? ", … +" * string(length(rs) - 8) : "")
        println(
            io,
            "| ",
            o,
            " | ",
            length(rs),
            " | ",
            count(r -> r.status == "missing", rs),
            " | ",
            count(r -> r.status == "refused", rs),
            " | ",
            which,
            " |"
        )
    end
    println(io)
    println(io, "#### Missing and refused per category")
    println(io)
    top = maximum(max(perc[c].nmissing, perc[c].refused) for (c, _) in R2_CATS)
    ymax = max(10, cld(top, 50) * 50)
    println(io, "```mermaid")
    println(io, "xychart-beta")
    println(io, "    title \"R2: missing (bars) and refused (line) rows\"")
    println(
        io, "    x-axis [\"predicates\", \"refusal sites\", \"flags\", \"VM instructions\"]"
    )
    println(io, "    y-axis \"rows\" 0 --> ", ymax)
    println(io, "    bar [", join((perc[c].nmissing for (c, _) in R2_CATS), ", "), "]")
    println(io, "    line [", join((perc[c].refused for (c, _) in R2_CATS), ", "), "]")
    println(io, "```")
    return String(take!(io))
end

"""
Everything the status is computed from, for the tree at `root`: the committed snapshot (`up`, `pin`, `nup`), the owners file
(`owners`, `otext`, `nothing` when the file is missing) and the rows. The snapshot must exist.
"""
function r2_state(root::AbstractString)
    snap = joinpath(root, R2_SNAPSHOT)
    isfile(snap) || error("r2_status: no $R2_SNAPSHOT")
    stext = read(snap, String)
    up = r2_read_snapshot(stext)
    owf = joinpath(root, R2_OWNERS)
    otext = isfile(owf) ? read(owf, String) : nothing
    owners = if otext === nothing
        Dict{String, Tuple{String, String}}()
    else
        r2_owners_parse(otext).owners
    end
    res = r2_collect(root, up)
    return (;
        res..., owners, otext, pin=something(r2_snapshot_pin(stext), "0"^40),
        nup=length(unique((u.kind, u.key) for u in up))
    )
end

"The block for the tree at `root`, computed from the committed snapshot and owners file (so CI, with no checkout, checks it)."
function r2_render(root::AbstractString)::String
    st = r2_state(root)
    return r2_render_rows(st.rows, st.files, st.preds, st.owners, st.pin, st.nup)
end

if abspath(PROGRAM_FILE) == @__FILE__
    root = abspath(joinpath(@__DIR__, ".."))
    if "--render" in ARGS
        print(r2_render(root))
        exit(0)
    end
    res = r2_collect(root, r2_upstream(root))
    for cat in ("pred", "refusal", "flag", "vmi")
        println(rpad(cat, 8), r2_counts([r for r in res.rows if r.cat == cat]))
    end
    for t in r2_file_table(res.files, res.preds)
        println(
            rpad(t.rel, 28),
            " loaded=",
            t.loaded,
            " done=",
            t.done,
            " missing=",
            t.nmissing,
            " platform=",
            t.platform
        )
    end
end
