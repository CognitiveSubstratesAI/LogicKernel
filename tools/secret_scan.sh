#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the SECRET SCAN of a gate push (audit D-0340): the pinned gitleaks
# (tools/gitleaks.pin, installed by tools/install_gitleaks.sh) over the ADDED lines of a commit range. Run by
# tools/prepush.sh (range origin/main..HEAD = the diff against the merge base) and by the CI job `Secret scan`.
#
#   tools/secret_scan.sh --check         the pinned binary is installed and its SHA-256 and version match the pin
#   tools/secret_scan.sh <range>         e.g. origin/main..HEAD; scans the patches of those commits
#
# A FINDING STOPS THE PUSH AND IS REPORTED; it is NEVER allowlisted by an agent: the configuration is the
# built-in rule set only (tools/gitleaks.toml), `gitleaks:allow` comments are not honoured, a .gitleaksignore
# or .gitleaks.toml in the scanned repository is refused, no baseline. A finding is printed REDACTED (rule, file,
# line, commit — never the secret), so the report itself carries no secret. A rotated secret still needs the
# history rewritten or the finding ruled on by the dispatcher and Shivaji, not by the agent that hit it.
# Commit MESSAGES are not scanned by gitleaks (only patches).
# Exit status: 0 clean; 1 a finding (or a refused config file); 2 the scan itself failed (fails closed);
# 3 the pinned binary is not installed or does not match the pin; 64 usage.
# Seams for tools/test_secret_scan.sh: LOGICKERNEL_SECRET_SCAN_REPO=<dir> is the repository to scan (default: this
# one), LOGICKERNEL_GITLEAKS=<file> the binary (default tools/bin/gitleaks), LOGICKERNEL_GITLEAKS_CONFIG=<file>.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/gitleaks.pin
. "$HERE/gitleaks.pin"
BIN="${LOGICKERNEL_GITLEAKS:-$HERE/bin/gitleaks}"
CONF="${LOGICKERNEL_GITLEAKS_CONFIG:-$HERE/gitleaks.toml}"
REPO="${LOGICKERNEL_SECRET_SCAN_REPO:-$(cd "$HERE/.." && pwd)}"
ARG="${1:-}"
case "$ARG" in '') echo "usage: tools/secret_scan.sh --check | <commit range, e.g. origin/main..HEAD>" >&2; exit 64 ;; esac

# (gitleaks 8.30.1 does not read GITLEAKS_BASELINE_PATH / GITLEAKS_ENABLE_RULE here and every option that matters is
# a flag below, which beats a variable; tools/test_secret_scan.sh fails if a later release reads one.)

if [ ! -x "$BIN" ]; then
    echo "secret_scan: $BIN is not installed; nothing was scanned. Run: tools/install_gitleaks.sh"
    exit 3
fi
if [ "$(sha256sum "$BIN" | cut -d' ' -f1)" != "$GITLEAKS_BINARY_SHA256" ]; then
    echo "secret_scan: $BIN does not match the pinned SHA-256 of tools/gitleaks.pin; nothing was scanned. Run: tools/install_gitleaks.sh"
    exit 3
fi
if [ "$("$BIN" version 2> /dev/null)" != "$GITLEAKS_VERSION" ]; then
    echo "secret_scan: $BIN is not gitleaks $GITLEAKS_VERSION; nothing was scanned."
    exit 3
fi
if [ "$ARG" = "--check" ]; then
    echo "secret_scan: gitleaks $GITLEAKS_VERSION installed, binary SHA-256 matches the pin"
    exit 0
fi

# the rule set may not be widened for the scan: no allowlist, no extra rule, no path or regex exclusion in the config
if [ ! -s "$CONF" ] || grep -qiE '^[[:space:]]*(\[+[^]]*(allowlist|rules|targetrules)|allowlist|paths[[:space:]]*=|regexes[[:space:]]*=|stopwords|commits[[:space:]]*=)' "$CONF"; then
    echo "secret_scan: FINDING-CONFIG: $CONF is empty or carries an allowlist/rule/exclusion; it must be the built-in rules only"
    exit 1
fi
for f in .gitleaksignore .gitleaks.toml .gitleaks.yaml .gitleaks.yml .gitleaks.json; do
    if [ -e "$REPO/$f" ]; then
        echo "secret_scan: FINDING-CONFIG: $REPO/$f exists; an agent never adds an exclusion (report the finding instead)"
        exit 1
    fi
done
git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1 || { echo "secret_scan: $REPO is not a git repository"; exit 2; }
n="$(git -C "$REPO" rev-list --count "$ARG" 2> /dev/null)" || { echo "secret_scan: '$ARG' is not a commit range of $REPO (git fetch origin?)"; exit 2; }

L="$(mktemp -d "${TMPDIR:-/tmp}/secret_scan.XXXXXX")" || { echo "secret_scan: no temp directory"; exit 2; }
trap 'rm -rf "$L"' EXIT
: > "$L/ignore"
"$BIN" git --no-banner --no-color --verbose --redact \
    --config "$CONF" --gitleaks-ignore-path "$L/ignore" --ignore-gitleaks-allow \
    --exit-code 99 --log-opts="$ARG" "$REPO" > "$L/out.txt" 2>&1
rc=$?
case "$rc" in
    0) echo "secret_scan: clean — gitleaks $GITLEAKS_VERSION, $n commit(s) in $ARG scanned" ;;
    99)
        echo "secret_scan: FINDING(S) in $ARG — STOP, report it; do NOT allowlist or ignore it (redacted):"
        grep -E '^(Finding|RuleID|File|Line|Commit|Fingerprint):' "$L/out.txt" | head -n 60
        exit 1
        ;;
    *)
        echo "secret_scan: the scan itself FAILED (exit $rc; fails closed). Last lines:"
        tail -n 8 "$L/out.txt" | cut -c1-200
        exit 2
        ;;
esac
