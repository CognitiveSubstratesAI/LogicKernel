#!/usr/bin/env bash
# ORIGINAL: the vendoring of swipl-devel's boot/ and library/ (R2 LB4 chunk a, audit D-0286 item 1) — no swipl-devel counterpart.
# tools/vendor_swipl.sh — writes vendor/swipl-devel from the pinned swipl-devel commit, byte for byte:
#
#   tools/vendor_swipl.sh manifest      tools/swipl_vendor_blobs.txt: `git ls-tree -r <pin> boot library LICENSE`
#                                       (the generated INDEX.pl lines, below its GENERATED marker, are kept)
#   tools/vendor_swipl.sh boot          vendor/swipl-devel/boot/*.pl, LICENSE and PIN
#   tools/vendor_swipl.sh library       vendor/swipl-devel/library/**
#   tools/vendor_swipl.sh verify [PATH…]  every vendored file's (or those under the PATHs) `git hash-object --no-filters` against `git ls-tree`
#   tools/vendor_swipl.sh extra CLASS   vendor/swipl-devel-extra/<upstream path> + tools/swipl_extra_blobs/CLASS.txt; CLASS is tests (tests/),
#                                       top (app/ customize/ demo/), bench (the submodule) or pkg-NAME (the submodule packages/NAME, read
#                                       from its own object store at the pin's gitlink: `<up>/.git/modules/packages/NAME`); modes 100644 and 100755 kept
#   tools/vendor_swipl.sh verify-extra [CLASS…]  each class (all manifests when none): every file's blob id against upstream's tree, nothing added or missing
#

# THE PIN is `commit:` of tools/SWIPL_VERSION; the upstream checkout is ~/dev-zone/swipl-devel or
# LOGICKERNEL_UPSTREAM_SWIPL_DEVEL (its HEAD is NOT the pin: every file is read with `git show <pin>:<path>`, never from the working tree).
# A vendored file is NEVER edited (test/test_vendored_swipl.jl holds each to the manifest): a fix goes in the port, or in a D-entry naming the
# upstream change. A BUMP of the pin re-runs this script, then tools/gen_library_index.sh, in the sync's own commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
up="${LOGICKERNEL_UPSTREAM_SWIPL_DEVEL:-$HOME/dev-zone/swipl-devel}"
pin="$(sed -n 's/^commit:[[:space:]]*//p' "$root/tools/SWIPL_VERSION" | tr -d '[:space:]')"
version="$(sed -n 's/^version:[[:space:]]*//p' "$root/tools/SWIPL_VERSION" | tr -d '[:space:]')"
dest="$root/vendor/swipl-devel"
manifest="$root/tools/swipl_vendor_blobs.txt"
marker='# GENERATED'

[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo "vendor_swipl: no commit: in tools/SWIPL_VERSION" >&2; exit 2; }
git -C "$up" cat-file -e "$pin^{commit}" || { echo "vendor_swipl: $up has no commit $pin" >&2; exit 2; }

# the upstream blobs of one pathspec: `mode blob id<TAB>path`
tree() { git -C "$up" ls-tree -r "$pin" -- "$@"; }

# write one upstream path into the vendor tree, binary-safe (no EOL conversion, no filters)
put() {
    local path="$1"
    mkdir -p "$dest/$(dirname "$path")"
    git -C "$up" show "$pin:$path" > "$dest/$path"
}

# ---- the extra classes (tests, top, bench, pkg-NAME): vendor/swipl-devel-extra, one manifest per class ----------------------------------
edest="$root/vendor/swipl-devel-extra"
emanifests="$root/tools/swipl_extra_blobs"

# extra_class CLASS: sets x_kind (super|sub), x_paths (super: the pathspecs), x_sub (sub: the submodule's path), x_rev, x_gd
extra_class() {
    x_kind=""; x_paths=(); x_sub=""; x_rev="$pin"; x_gd=""
    case "$1" in
    tests) x_kind=super; x_paths=(tests) ;;
    top) x_kind=super; x_paths=(app customize demo) ;;
    bench) x_kind=sub; x_sub=bench ;;
    pkg-?*) x_kind=sub; x_sub="packages/${1#pkg-}" ;;
    *) echo "vendor_swipl: unknown class '$1' (tests, top, bench, pkg-NAME)" >&2; exit 2 ;;
    esac
    if [[ "$x_kind" == sub ]]; then
        x_rev="$(git -C "$up" ls-tree "$pin" -- "$x_sub" | awk '$2=="commit"{print $3}')"
        [[ "$x_rev" =~ ^[0-9a-f]{40}$ ]] || { echo "vendor_swipl: $x_sub is not a gitlink at $pin" >&2; exit 2; }
        x_gd="$up/.git/modules/$x_sub"
        [[ -d "$x_gd" ]] || { echo "vendor_swipl: no submodule object store $x_gd (never run submodule update in the upstream checkout)" >&2; exit 2; }
        git --git-dir="$x_gd" cat-file -e "$x_rev^{commit}" || { echo "vendor_swipl: $x_gd has no commit $x_rev" >&2; exit 2; }
    fi
}
x_git() { if [[ "$x_kind" == super ]]; then git -C "$up" "$@"; else git --git-dir="$x_gd" "$@"; fi; }
# upstream's tree of the class, `mode blob id<TAB>upstream path`; a mode other than 100644/100755 (a symlink, a nested gitlink) is an error
x_tree() {
    local out
    if [[ "$x_kind" == super ]]; then
        out="$(x_git ls-tree -r "$x_rev" -- "${x_paths[@]}")"
    else
        out="$(x_git ls-tree -r "$x_rev" | sed "s#	#	$x_sub/#")"
    fi
    [[ -n "$out" ]] || { echo "vendor_swipl: the class lists no file" >&2; exit 2; }
    if grep -v -E '^100(644|755) blob [0-9a-f]{40}	[A-Za-z0-9_./+-]+$' <<< "$out" > /dev/null; then
        echo "vendor_swipl: an entry that is not a plain blob with a plain name:" >&2
        grep -v -E '^100(644|755) blob [0-9a-f]{40}	[A-Za-z0-9_./+-]+$' <<< "$out" >&2
        exit 2
    fi
    printf '%s\n' "$out"
}
# x_show UPSTREAM-PATH
x_show() { if [[ "$x_kind" == super ]]; then x_git show "$x_rev:$1"; else x_git show "$x_rev:${1#"$x_sub"/}"; fi; }
# x_present: the files under the class's roots in the vendored tree, as upstream paths, sorted
x_present() {
    local r
    for r in "${x_paths[@]}" ${x_sub:+"$x_sub"}; do
        [[ -d "$edest/$r" ]] && (cd "$edest" && find "$r" -type f)
    done | LC_ALL=C sort
}

case "${1:-}" in
manifest)
    keep=""
    if [[ -f "$manifest" ]] && grep -qF "$marker" "$manifest"; then
        keep="$(sed -n "/^$marker/,\$p" "$manifest")"
    fi
    {
        echo "# SWI-Prolog/swipl-devel $pin — every file vendored at vendor/swipl-devel, as \`git ls-tree -r\` lists it: mode, type, blob id,"
        echo "# path (upstream's own path: boot/, library/, LICENSE). Written by tools/vendor_swipl.sh; test/test_vendored_swipl.jl holds the"
        echo "# vendored files to these blob ids (git's SHA-1 of \"blob <size>\\0<content>\")."
        tree boot library LICENSE
        if [[ -n "$keep" ]]; then
            echo "$keep"
        else
            echo "$marker — not in upstream's tree: the five INDEX.pl files (tools/gen_library_index.sh)"
        fi
    } > "$manifest"
    ;;
boot)
    tree boot | cut -f2 | while read -r p; do put "$p"; done
    put LICENSE
    {
        echo "# The upstream commit the files beside this one were copied from, byte for byte (tools/vendor_swipl.sh)."
        echo "commit: $pin"
        echo "version: $version"
        echo "upstream: https://github.com/SWI-Prolog/swipl-devel"
    } > "$dest/PIN"
    ;;
library)
    tree library | cut -f2 | while read -r p; do put "$p"; done
    ;;
verify)
    bad=0
    while IFS=$'\t' read -r meta path; do
        id="$(awk '{print $3}' <<< "$meta")"
        got="$(git hash-object --no-filters "$dest/$path" 2>/dev/null || echo missing)"
        [[ "$got" == "$id" ]] || { echo "DIFFERS: $path ($got, upstream $id)"; bad=1; }
    done < <(shift; if (($# )); then tree "$@"; else tree boot library LICENSE; fi)
    exit $bad
    ;;
extra)
    cls="${2:?usage: vendor_swipl.sh extra CLASS}"
    extra_class "$cls"
    mkdir -p "$emanifests"
    listing="$(x_tree)"
    {
        echo "# SWI-Prolog/swipl-devel $pin class $cls — every file vendored at vendor/swipl-devel-extra, as \`git ls-tree -r\` lists it: mode, type, blob id,"
        echo "# path (upstream's own path). Written by tools/vendor_swipl.sh extra $cls; the files are upstream's bytes, never edited."
        if [[ "$x_kind" == super ]]; then
            echo "# source: super $pin ${x_paths[*]}"
        else
            echo "# source: sub $x_sub $x_rev"
        fi
        printf '%s\n' "$listing"
    } > "$emanifests/$cls.txt"
    while IFS=$'\t' read -r meta path; do
        mkdir -p "$edest/$(dirname "$path")"
        x_show "$path" > "$edest/$path"
        if [[ "${meta%% *}" == 100755 ]]; then chmod 755 "$edest/$path"; else chmod 644 "$edest/$path"; fi
    done <<< "$listing"
    echo "vendor_swipl: class $cls: $(wc -l <<< "$listing") files"
    ;;
verify-extra)
    shift
    classes=("$@")
    if ((${#classes[@]} == 0)); then
        for m in "$emanifests"/*.txt; do classes+=("$(basename "$m" .txt)"); done
    fi
    bad=0
    for cls in "${classes[@]}"; do
        extra_class "$cls"
        listing="$(x_tree)"
        while IFS=$'\t' read -r meta path; do
            id="$(awk '{print $3}' <<< "$meta")"
            got="$(git hash-object --no-filters "$edest/$path" 2>/dev/null || echo missing)"
            [[ "$got" == "$id" ]] || { echo "DIFFERS: $path ($got, upstream $id)"; bad=1; }
            if [[ "${meta%% *}" == 100755 && ! -x "$edest/$path" ]]; then echo "MODE: $path is not executable (upstream 100755)"; bad=1; fi
        done <<< "$listing"
        # nothing added: every file present under the class's roots is upstream's
        extra_files="$(comm -13 <(cut -f2 <<< "$listing" | LC_ALL=C sort) <(x_present))"
        [[ -z "$extra_files" ]] || { echo "ADDED to class $cls:"; echo "$extra_files"; bad=1; }
        # the manifest is upstream's tree
        if ! diff -q <(grep -v '^#' "$emanifests/$cls.txt") <(printf '%s\n' "$listing") > /dev/null; then
            echo "MANIFEST of class $cls differs from upstream's tree"; bad=1
        fi
        echo "verify-extra: class $cls: $(wc -l <<< "$listing") files checked"
    done
    exit $bad
    ;;
*)
    sed -n '2,17p' "${BASH_SOURCE[0]}" >&2
    exit 2
    ;;
esac
