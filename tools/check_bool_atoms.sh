#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the tree-wide BOOL-AS-ATOM grep of .github/workflows/ci-compile.yml
# (audit D-0636 item 2; the stack-1 findings of R2 writers, 2026-11-12/13). In Julia `:true`, `:false` and
# `:nothing` are NOT Symbols (`:true isa Bool`, `:nothing === nothing`'s name), so
#     mk_sym(T, :true)        lk_sym(T, :false)        mk_sym(T, :nothing)
# builds an atom from a Bool / a Symbol that is not the atom the writer meant. The atoms are
# `Symbol("true")`, `Symbol("false")`, `Symbol("nothing")`. Each of those cost a shard-hour to find.
#
#   tools/check_bool_atoms.sh [ROOT]     scan ROOT/src and ROOT/test (default: this checkout), *.jl only
#
# Plain bash + grep, no julia. A line is a hit when it matches one of
#     mk_sym\(<identifier>, :(true|false|nothing)\)       (any term-type variable, not only `T`)
#     lk_sym\(.*:(true|false)\)
# and is not a comment line (its first non-blank character is `#`). Output: `check_bool_atoms: path:line: text`
# per hit, then the count. Exit status: 0 no hit; 1 at least one hit; 2 usage, or a tree with no .jl file under
# src/ and test/ (an empty scan would pass by default). Its cases: tools/test_check_bool_atoms.sh.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "check_bool_atoms: no such directory: $ROOT" >&2; exit 2; }
dirs=()
for d in src test; do [ -d "$ROOT/$d" ] && dirs+=("$ROOT/$d"); done
[ "${#dirs[@]}" -gt 0 ] || { echo "check_bool_atoms: $ROOT has neither src/ nor test/" >&2; exit 2; }
n="$(find "${dirs[@]}" -name '*.jl' | wc -l)"
[ "$n" -gt 0 ] || { echo "check_bool_atoms: no .jl file under ${dirs[*]}: an empty scan proves nothing" >&2; exit 2; }
PAT='mk_sym\([A-Za-z_][A-Za-z0-9_]*, *:(true|false|nothing)\)|lk_sym\(.*:(true|false)\)'
hits="$(grep -rnE --include='*.jl' -e "$PAT" "${dirs[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | sed "s|^$ROOT/||")"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed -E 's/^([^:]+):([0-9]+):[[:space:]]*(.*)$/check_bool_atoms: \1:\2: \3/' | cut -c1-240
    echo "check_bool_atoms: $(printf '%s\n' "$hits" | wc -l) hit(s): \`:true\`/\`:false\`/\`:nothing\` is no Symbol — write Symbol(\"true\") etc."
    exit 1
fi
echo "check_bool_atoms: $n .jl file(s) scanned, no Bool-as-atom"
exit 0
