#!/usr/bin/env bash
# ORIGINAL: the mutation runs' lane (user, 2026-10-08 and 2026-10-11) — no swipl-devel counterpart.
# tools/mutate.sh — MUTANTS RUN IN A SEPARATE GIT WORKTREE, with a warm daemon of its own; the main
# tree is never touched (Tooling 1, 2026-10-11).
#
#   tools/mutate.sh setup                             # make or refresh the worktree
#   tools/mutate.sh run MUTANTS.py TARGET… [-- ID…]   # setup, then every mutant against the targets
#   tools/mutate.sh run-in-tree MUTANTS.py TARGET… [-- ID…]   # the same, in THIS tree (the old lane)
#   tools/mutate.sh recover                           # after a killed run: both trees
#   tools/mutate.sh status
#   tools/mutate.sh remove                            # when the chunk ends
#
# WHY. A mutant is a deliberately broken line. Applied in the working tree it sat one killed driver
# away from a commit — MEASURED 2026-10-08: a SIGTERM left a mutant in src/pl-fli.jl — and it kept
# the tree and its daemon from anything else for the whole run. So:
# * THE WORKTREE (LOGICKERNEL_MUTANTS_DIR, default ~/code/lk-mutants/worktree — outside the
#   workspace, never under /tmp) is a `git worktree` of this repository on a DETACHED HEAD, at this tree's HEAD, with
#   the chunk's uncommitted work copied over it: every file that differs from HEAD or is untracked
#   (a deleted one removed), and the two ignored files that decide what loads, Manifest.toml and
#   LocalPreferences.toml (tools/mutate_drive.py --sync).
# * THE GUARD: `setup` REFUSES unless both trees then hold the same content — the tree fingerprint
#   of tools/lib_evidence.sh over a non-empty file list, and those two files. A mutant judged on
#   other code than the chunk's proves nothing about the chunk.
# * IT NEVER COMMITS OR PUSHES: `.warm/MUTANT_WORKTREE` marks it, and tools/githooks/pre-commit and
#   pre-push refuse there.
# * ITS OWN DAEMON, in its own depot, capped at LOGICKERNEL_MUTANTS_MEM_MAX (6G): the main tree's
#   daemon, and its preflight, go on meanwhile. NOT beside an evidence run — `run` refuses while
#   one holds the main lane, and tools/run_tests.sh refuses to start one while mutants run.
# * THE DRIVER is tools/mutate_drive.py, the same for every chunk; a chunk keeps its mutant list.
# * THE SENTINEL stays, in whichever tree the mutant is applied: before a mutant the driver saves
#   the file (.warm/MUTATION_ORIGINAL) and writes .warm/MUTATION_IN_PROGRESS — the file, the copy's
#   SHA-256, the mutant — and removes both after restoring it. In the MAIN tree (`run-in-tree`) the
#   commit hook refuses every commit while it exists, so a killed driver fails CLOSED.
#
# `recover` is the way out of a killed run, in BOTH trees, and the only one: deleting a sentinel by
# hand is exactly the step that would let a leftover mutation through. For each tree it checks the
# named file against the SAVED COPY — never against HEAD: mid-chunk the file holds the chunk's own
# uncommitted work, which HEAD does not have and must not be lost — and:
#   * the file equals the copy (its SHA-256): intact; the sentinel and the copy are removed (exit 0);
#   * the file differs: it is restored from the copy, the diff it undid is shown, the SHA-256 is
#     checked again, and only then the sentinel and the copy are removed (exit 0);
#   * the sentinel names no file, or the copy is missing or does not match its SHA-256: REFUSED,
#     the sentinel kept (exit 1) — restore the file by hand from its diff, then run recover again;
#   * no sentinel: nothing to recover; a stray copy is removed (exit 0).
# MUTATE_ROOT overrides the main tree (its tests run on a fixture repository).
set -uo pipefail
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="${MUTATE_ROOT:-$(cd "$TOOLS/.." && pwd)}"
# shellcheck source=/dev/null
. "$TOOLS/lib_evidence.sh"
WT="$(_mutants_dir)"

# _ours — 0 when $WT is a worktree of $MAIN's repository, marked as its mutant worktree
_ours() {
    [ -d "$WT" ] || return 1
    local a b
    a="$(cd "$MAIN" && realpath "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)"
    b="$(cd "$WT" && realpath "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)"
    [ -n "$a" ] && [ "$a" = "$b" ] && [ "$(cat "$WT/.warm/MUTANT_WORKTREE" 2>/dev/null)" = "$MAIN" ]
}

# _same_ignored FILE — 0 when the ignored file FILE is the same in both trees, or in neither
_same_ignored() {
    if [ -f "$MAIN/$1" ]; then cmp -s "$MAIN/$1" "$WT/$1"; else [ ! -e "$WT/$1" ]; fi
}

_setup() {
    local head f n a b
    head="$(git -C "$MAIN" rev-parse --verify --quiet HEAD)" ||
        { echo "mutate: $MAIN has no HEAD" >&2; return 1; }
    if [ -e "$WT" ]; then
        if ! _ours; then
            echo "mutate: REFUSED — $WT exists and is not the mutant worktree of $MAIN" >&2
            return 1
        fi
        if [ -e "$WT/.warm/MUTATION_IN_PROGRESS" ]; then
            echo "mutate: REFUSED — a mutation was left in $WT: tools/mutate.sh recover" >&2
            return 1
        fi
        git -C "$WT" checkout -q --detach -f "$head" || return 1
        git -C "$WT" clean -q -fd || return 1              # an earlier chunk's untracked files
    else
        git -C "$MAIN" worktree add -q --detach "$WT" "$head" || return 1
        mkdir -p "$WT/.warm"
        printf '%s\n' "$MAIN" > "$WT/.warm/MUTANT_WORKTREE"
    fi
    # the chunk's uncommitted work, copied over the checkout
    n="$(python3 "$TOOLS/mutate_drive.py" --sync "$MAIN" "$WT")" || return 1
    # THE GUARD — both sides non-empty: a fingerprint over NO files is still a hash
    a="$(_tree_fp "$MAIN")"
    b="$(_tree_fp "$WT")"
    [ -n "${MUTATE_FAULT_FP:-}" ] && b="$MUTATE_FAULT_FP"      # TEST SEAM (test/test_gate_split.jl)
    if [ "$(git -C "$MAIN" ls-files -co --exclude-standard | wc -l)" -le 0 ] ||
        [ -z "$a" ] || [ "$a" != "$b" ]; then
        echo "mutate: REFUSED — the worktree does not hold the main tree's content (fingerprints ${a:0:12} and ${b:0:12}): a mutant there would be judged on other code" >&2
        return 1
    fi
    for f in Manifest.toml LocalPreferences.toml; do
        _same_ignored "$f" || { echo "mutate: REFUSED — $f differs between the trees" >&2; return 1; }
    done
    echo "mutate: worktree $WT at ${head:0:7}, detached, + $n uncommitted file(s); fingerprint ${a:0:12} on both trees"
}

# _wenv CMD… — CMD with the worktree daemon's settings: a depot of its own, its memory cap
_wenv() {
    env LOGICKERNEL_WARM_DEPOT="$WT/.warm/depot" \
        LOGICKERNEL_TEST_MEM_MAX="${LOGICKERNEL_MUTANTS_MEM_MAX:-6G}" \
        LOGICKERNEL_WARM_HEAP_HINT="${LOGICKERNEL_MUTANTS_HEAP_HINT:-4G}" "$@"
}

# _run TREE MUTANTS TARGET… [-- ID…]
_run() {
    local tree="$1" mutants
    shift
    [ $# -ge 2 ] || { echo "usage: tools/mutate.sh run MUTANTS.py TARGET… [-- ID…]" >&2; return 2; }
    [ -f "$1" ] || { echo "mutate: no such mutant list: $1" >&2; return 2; }
    mutants="$(realpath "$1")"
    shift
    if [ "$tree" = "$MAIN" ]; then
        exec "$MAIN/tools/warm.sh" locked python3 "$MAIN/tools/mutate_drive.py" "$MAIN" "$mutants" "$@"
    fi
    if _evidence_running "$MAIN"; then
        echo "mutate: REFUSED — an evidence run holds the main lane: mutants do not share the machine with it (exit 5)" >&2
        return 5
    fi
    _setup || return 1
    cd "$WT" || return 1
    _wenv tools/warm.sh start || return 1
    _wenv tools/warm.sh locked python3 "$WT/tools/mutate_drive.py" "$WT" "$mutants" "$@"
}

_status() {
    local m="no mutation in progress"
    [ -e "$MAIN/.warm/MUTATION_IN_PROGRESS" ] && m="MUTATION IN PROGRESS"
    echo "main tree:  $MAIN — $m"
    if _ours; then
        m="no mutation in progress"
        [ -e "$WT/.warm/MUTATION_IN_PROGRESS" ] && m="MUTATION IN PROGRESS"
        echo "worktree:   $WT at $(git -C "$WT" rev-parse --short HEAD) — $m"
        (cd "$WT" && tools/warm.sh status) || true
    else
        echo "worktree:   none at $WT"
    fi
}

_remove() {
    if [ ! -e "$WT" ]; then
        echo "mutate: no worktree at $WT"
        return 0
    fi
    _ours || { echo "mutate: REFUSED — $WT is not the mutant worktree of $MAIN" >&2; return 1; }
    if _lane_held "$WT"; then
        echo "mutate: REFUSED — a run holds the worktree's lane" >&2
        return 1
    fi
    (cd "$WT" && tools/warm.sh stop > /dev/null 2>&1)
    git -C "$MAIN" worktree remove --force "$WT" || return 1
    git -C "$MAIN" worktree prune
    echo "mutate: worktree $WT removed"
}

# _recover TREE
_recover() {
    local ROOT="$1"
    local SENTINEL="$ROOT/.warm/MUTATION_IN_PROGRESS" SAVED="$ROOT/.warm/MUTATION_ORIGINAL"
    if [ ! -e "$SENTINEL" ]; then
        [ -e "$SAVED" ] && rm -f "$SAVED"
        echo "mutate: $ROOT: no mutation in progress — nothing to recover"
        return 0
    fi
    local file sha mutant
    file="$(sed -n 's/^file=//p' "$SENTINEL")"
    sha="$(sed -n 's/^sha256=//p' "$SENTINEL")"
    mutant="$(sed -n 's/^mutant=//p' "$SENTINEL")"
    if [ -z "$file" ] || [ -z "$sha" ]; then
        echo "mutate: REFUSED — the sentinel names no file or no SHA-256:" >&2
        sed 's/^/    /' "$SENTINEL" >&2
        return 1
    fi
    if [ ! -e "$SAVED" ] || [ "$(sha256sum < "$SAVED" | cut -d' ' -f1)" != "$sha" ]; then
        echo "mutate: REFUSED — the copy saved before mutant '$mutant' is missing or not the one the" >&2
        echo "  sentinel records; restore $file by hand (git diff it), then run recover again." >&2
        return 1
    fi
    if [ "$(sha256sum < "$ROOT/$file" | cut -d' ' -f1)" = "$sha" ]; then
        echo "mutate: $file is intact (mutant '$mutant' was restored before the driver stopped)"
    else
        echo "mutate: $file still holds mutant '$mutant' — restoring it from the saved copy:"
        diff "$ROOT/$file" "$SAVED" | sed 's/^/    /'
        cp "$SAVED" "$ROOT/$file"
        if [ "$(sha256sum < "$ROOT/$file" | cut -d' ' -f1)" != "$sha" ]; then
            echo "mutate: REFUSED — $file does not match the saved copy after the restore" >&2
            return 1
        fi
        echo "mutate: $file restored"
    fi
    rm -f "$SENTINEL" "$SAVED"                      # first the sentinel, then the copy
    echo "mutate: $ROOT: sentinel removed"
    return 0
}

cmd="${1:-}"
shift || true
case "$cmd" in
    setup) _setup ;;
    run) _run "$WT" "$@" ;;
    run-in-tree) _run "$MAIN" "$@" ;;
    recover)
        rc=0
        _recover "$MAIN" || rc=1
        if _ours; then _recover "$WT" || rc=1; fi
        exit "$rc"
        ;;
    status) _status ;;
    remove) _remove ;;
    *) sed -n '2,11p' "$0"; exit 2 ;;
esac
