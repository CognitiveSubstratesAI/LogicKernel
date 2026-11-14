#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the WHERE-BOUND-RETURN-TYPE check of .github/workflows/ci-compile.yml (audit
# D-0651 item 3; the CIFIX1 class, 2026-11-13). In an ONE-LINE method
#     visibleClause(c::Clause{T})::Bool where {T} = ...
# the `where` binds to the RETURN TYPE (`::(Bool where {T})`), not to the method: `T` of the argument annotation is
# then unbound — an UndefVarError at precompile, or Aqua's "unbound type parameters". The correct forms are
#     visibleClause(c::Clause{T}) where {T} = ...                        (no return type, or)
#     function visibleClause(c::Clause{T})::Bool where {T} ... end       (the multi-line `function`, where the
#                                                                         `where` covers the whole signature)
#
#   tools/check_where_return.sh [--changed] [ROOT]
#
# Plain bash around python3 -I (the standard library only), no julia. Scans ROOT/src and ROOT/test (default: this
# checkout), *.jl. `--changed`: only the .jl files under src/ and test/ that differ from `origin/main` (git diff
# against the work tree, and the untracked ones; ROOT must be a git checkout with an origin/main), for the branch's own diff. A finding is
#     <head>(<args>)::<R> where <vars> = <body>        where one of <vars> occurs in the ANNOTATION of an argument
# (the part after a top-level `::` of an argument or keyword argument, or of the callable-object head
# `(::Type{T})(...)`); the `=` after the where clause is what makes it a one-line method, so a multi-line
# `function ...::R where {T}` (no `=` after the clause) is never a finding, and neither is a `where` variable that is
# used only in the return type. Comments (`#`, `#= =#`), strings and docstrings are blanked before the scan (a comment
# that quotes the bad form is no finding); the variable is matched as a WORD (`T` is not in `Tuple`).
# Output: `check_where_return: path:line: <signature line>` per finding (the line of the argument list's `(`), then the
# count. Exit status: 0 no finding; 1 at least one; 2 usage, no git base for --changed, or a tree with no .jl file
# under src/ and test/ (an empty scan would pass by default; `--changed` with no changed .jl file is exit 0, saying so).
# Its cases: tools/test_check_where_return.sh.
set -u
MODE=tree
if [ "${1:-}" = "--changed" ]; then
    MODE=changed
    shift
fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "check_where_return: no such directory: $ROOT" >&2; exit 2; }
dirs=()
for d in src test; do [ -d "$ROOT/$d" ] && dirs+=("$ROOT/$d"); done
[ "${#dirs[@]}" -gt 0 ] || { echo "check_where_return: $ROOT has neither src/ nor test/" >&2; exit 2; }
files=()
if [ "$MODE" = changed ]; then
    git -C "$ROOT" rev-parse --verify --quiet origin/main > /dev/null || { echo "check_where_return: --changed needs an origin/main in $ROOT" >&2; exit 2; }
    while IFS= read -r f; do
        case "$f" in src/*.jl | test/*.jl) [ -f "$ROOT/$f" ] && files+=("$ROOT/$f") ;; esac
    done < <({ git -C "$ROOT" diff --name-only --diff-filter=ACMR origin/main -- src test; git -C "$ROOT" ls-files --others --exclude-standard -- src test; } | sort -u)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "check_where_return: no .jl file under src/ or test/ differs from origin/main: nothing to check"
        exit 0
    fi
else
    while IFS= read -r f; do files+=("$f"); done < <(find "${dirs[@]}" -name '*.jl' | sort)
    [ "${#files[@]}" -gt 0 ] || { echo "check_where_return: no .jl file under ${dirs[*]}: an empty scan proves nothing" >&2; exit 2; }
fi
exec python3 -I - "$ROOT" "${files[@]}" << 'PY'
import re
import sys

root, files = sys.argv[1].rstrip("/"), sys.argv[2:]


def blank(text):
    """TEXT with comments, strings, docstrings and character literals replaced by spaces (newlines kept)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            if text.startswith("#=", i):                       # a block comment, nested
                depth, j = 1, i + 2
                while j < n and depth:
                    if text.startswith("#=", j):
                        depth, j = depth + 1, j + 2
                    elif text.startswith("=#", j):
                        depth, j = depth - 1, j + 2
                    else:
                        j += 1
            else:                                              # a line comment
                j = text.find("\n", i)
                j = n if j < 0 else j
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif c == "'" and not (i > 0 and (text[i - 1].isalnum() or text[i - 1] in "_)]}'")):
            m = re.match(r"'(?:\\.[^']*|[^'\\\n])'", text[i:])      # a character literal, not a transpose
            if m:
                out.append(" " * len(m.group(0)))
                i += len(m.group(0))
            else:
                out.append(c)
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


OPEN, CLOSE = "([{", ")]}"


def match_forward(s, i):
    """Index of the bracket closing the one at s[i], or -1."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] in OPEN:
            depth += 1
        elif s[j] in CLOSE:
            depth -= 1
            if depth == 0:
                return j
    return -1


def match_backward(s, i):
    """Index of the parenthesis opening the one closed at s[i], or -1."""
    depth = 0
    for j in range(i, -1, -1):
        if s[j] in CLOSE:
            depth += 1
        elif s[j] in OPEN:
            depth -= 1
            if depth == 0:
                return j
    return -1


def split_top(s, seps=",;"):
    """S cut at its top-level separators."""
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in OPEN:
            depth += 1
        elif ch in CLOSE:
            depth -= 1
        if depth == 0 and ch in seps:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def annotations(args):
    """The annotation of every argument of the argument list ARGS: the text after its first top-level `::`."""
    out = []
    for seg in split_top(args):
        k = None
        depth = 0
        for p, ch in enumerate(seg):
            if ch in OPEN:
                depth += 1
            elif ch in CLOSE:
                depth -= 1
            elif depth == 0 and seg.startswith("::", p):
                k = p + 2
                break
        if k is not None:
            out.append(seg[k:])
    return out


def where_vars(clean, j):
    """(the variable names, the index after the clause) of the where clause that begins at clean[j] (after `where`)."""
    n = len(clean)
    while j < n and clean[j] in " \t":
        j += 1
    if j < n and clean[j] == "{":
        e = match_forward(clean, j)
        if e < 0:
            return [], j
        inner, j = clean[j + 1 : e], e + 1
        names = []
        for part in split_top(inner, ","):
            m = re.match(r"\s*([A-Za-z_]\w*)", part)
            if m:
                names.append(m.group(1))
        return names, j
    m = re.match(r"([A-Za-z_]\w*)[^=\n]*?(?=[ \t]*=)", clean[j:])      # `where T`, `where T<:X`
    if m:
        return [m.group(1)], j + m.end()
    return [], j


findings = []
scanned = 0
for path in files:
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("check_where_return: cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(2)
    scanned += 1
    clean = blank(raw)
    rawlines = raw.split("\n")
    for m in re.finditer(r"\bwhere\b", clean):
        ls = clean.rfind("\n", 0, m.start()) + 1
        seg = clean[ls : m.start()]
        mm = re.match(r"^(.*\))[ \t]*::[ \t]*([^()=]*?)[ \t]*$", seg)
        if not mm:
            continue                                   # not `...)::R where`
        close = ls + len(mm.group(1)) - 1
        names, j = where_vars(clean, m.end())
        # a one-line method: the clause is followed by `=` (not `==`, not `=>`)
        k = j
        while k < len(clean) and clean[k] in " \t":
            k += 1
        if not (k < len(clean) and clean[k] == "=" and clean[k + 1 : k + 2] not in ("=", ">")):
            continue
        groups, c = [], close
        head_first = None
        while c >= 0 and clean[c] == ")":
            o = match_backward(clean, c)
            if o < 0:
                break
            groups.append(clean[o + 1 : c])
            head_first = o
            c = o - 1                                  # a callable-object head: `(::Type{T})(...)`
            if c < 0 or clean[c] != ")":
                break
        annot = [a for g in groups for a in annotations(g)]
        used = [v for v in names if any(re.search(r"(?<![\w.])" + re.escape(v) + r"(?!\w)", a) for a in annot)]
        if used and head_first is not None:
            line = clean.count("\n", 0, head_first) + 1
            sig = rawlines[line - 1].strip()
            rel = path[len(root) + 1 :] if path.startswith(root + "/") else path
            findings.append((rel, line, sig))

if findings:
    for rel, line, sig in findings:
        print("check_where_return: %s:%d: %s" % (rel, line, sig[:200]))
    print(
        "check_where_return: %d finding(s): in a one-line method `::R where {T} = ...` the `where` binds to the return "
        "type; write `f(x::C{T}) where {T} = ...` or a multi-line `function`" % len(findings)
    )
    sys.exit(1)
print("check_where_return: %d .jl file(s) scanned, no where-bound return type" % scanned)
PY
