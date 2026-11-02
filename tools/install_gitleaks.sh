#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — INSTALLS the pinned gitleaks into tools/bin/ (audit D-0340). An explicit,
# human-or-agent-run step: no hook and no push runs it (tools/prepush.sh only CHECKS that the binary is there).
#
#   tools/install_gitleaks.sh        # exit 0: tools/bin/gitleaks is the pinned release, verified
#
# The version and both SHA-256 values are in tools/gitleaks.pin. The archive goes into its own NEW EMPTY directory;
# its SHA-256 is checked against the pin BEFORE anything is extracted; only the member `gitleaks` is extracted
# (into a second new directory); the extracted binary's SHA-256 is checked against the pin before it is installed;
# nothing is run from a download directory. Any mismatch or network failure: exit 1, nothing installed.
# Seam for tools/test_secret_scan.sh: LOGICKERNEL_GITLEAKS_BASE=<directory> takes the archive from that directory
# (instead of the GitHub release URL) and LOGICKERNEL_GITLEAKS_BIN_DIR=<directory> installs there.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/gitleaks.pin
. "$ROOT/tools/gitleaks.pin"
BIN_DIR="${LOGICKERNEL_GITLEAKS_BIN_DIR:-$ROOT/tools/bin}"
ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/$ARCHIVE"
die() { echo "install_gitleaks: $*" >&2; exit 1; }

[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || die "only linux x86_64 is pinned (tools/gitleaks.pin); this is $(uname -s)-$(uname -m)"
want_bin="$GITLEAKS_BINARY_SHA256"
if [ -x "$BIN_DIR/gitleaks" ] && [ "$(sha256sum "$BIN_DIR/gitleaks" | cut -d' ' -f1)" = "$want_bin" ]; then
    echo "install_gitleaks: $BIN_DIR/gitleaks is already the pinned $GITLEAKS_VERSION (binary SHA-256 matches)"
    exit 0
fi
D1="$(mktemp -d "${TMPDIR:-/tmp}/gitleaks_dl.XXXXXX")" || die "no temp directory"
D2="$(mktemp -d "${TMPDIR:-/tmp}/gitleaks_x.XXXXXX")" || die "no temp directory"
trap 'rm -rf "$D1" "$D2"' EXIT
if [ -n "${LOGICKERNEL_GITLEAKS_BASE:-}" ]; then
    cp "$LOGICKERNEL_GITLEAKS_BASE/$ARCHIVE" "$D1/$ARCHIVE" || die "no archive $LOGICKERNEL_GITLEAKS_BASE/$ARCHIVE"
else
    curl -fsSL --proto '=https' --tlsv1.2 -m 180 -o "$D1/$ARCHIVE" "$URL" || die "download of $URL failed"
fi
got="$(sha256sum "$D1/$ARCHIVE" | cut -d' ' -f1)"
[ "$got" = "$GITLEAKS_ARCHIVE_SHA256" ] || die "archive SHA-256 is $got, the pin says $GITLEAKS_ARCHIVE_SHA256: NOTHING extracted or installed"
tar -xzf "$D1/$ARCHIVE" -C "$D2" gitleaks || die "the archive has no member 'gitleaks'"
got="$(sha256sum "$D2/gitleaks" | cut -d' ' -f1)"
[ "$got" = "$want_bin" ] || die "binary SHA-256 is $got, the pin says $want_bin: nothing installed"
mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
install -m 755 "$D2/gitleaks" "$BIN_DIR/gitleaks" || die "cannot install into $BIN_DIR"
echo "install_gitleaks: installed gitleaks $GITLEAKS_VERSION into $BIN_DIR (archive and binary SHA-256 match the pin)"
