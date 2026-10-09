#!/usr/bin/env bash
# ORIGINAL: the mutation runs' recovery (user, 2026-10-08) — no swipl-devel counterpart.
# tools/mutate.sh — the mutation runs' tooling. One command so far:
#
#   tools/mutate.sh recover
#
# A mutation driver (the workspace's docs/research/logickernel-step-memos/*_mutation/drive.py)
# applies each mutant to a file of THIS tree. Before it does, it saves the file as it was
# (.warm/MUTATION_ORIGINAL) and writes .warm/MUTATION_IN_PROGRESS — the file, the copy's SHA-256 and
# the mutant — and removes both after restoring the file. The commit hook
# (require-tests-before-commit.sh) refuses every commit while the sentinel exists, so a driver
# killed mid-mutant fails CLOSED. `recover` is the way out, and the only one: deleting the sentinel
# by hand is exactly the step that would let a leftover mutation into a commit.
#
# It checks the named file against the SAVED COPY — never against HEAD: mid-chunk the file holds
# the chunk's own uncommitted work, which HEAD does not have and must not be lost — and:
#   * the file equals the copy (its SHA-256): intact; the sentinel and the copy are removed (exit 0);
#   * the file differs: it is restored from the copy, the diff it undid is shown, the SHA-256 is
#     checked again, and only then the sentinel and the copy are removed (exit 0);
#   * the sentinel names no file, or the copy is missing or does not match its SHA-256: REFUSED,
#     the sentinel kept (exit 1) — restore the file by hand from its diff, then run recover again;
#   * no sentinel: nothing to recover; a stray copy is removed (exit 0).
# MUTATE_ROOT overrides the tree (its tests run on a fixture).
set -uo pipefail
ROOT="${MUTATE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SENTINEL="$ROOT/.warm/MUTATION_IN_PROGRESS"
SAVED="$ROOT/.warm/MUTATION_ORIGINAL"

_recover() {
    if [ ! -e "$SENTINEL" ]; then
        [ -e "$SAVED" ] && rm -f "$SAVED"
        echo "mutate: no mutation in progress — nothing to recover"
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
    echo "mutate: sentinel removed — commits are allowed again"
    return 0
}

case "${1:-}" in
    recover) _recover ;;
    *) sed -n '2,24p' "$0"; exit 2 ;;
esac
