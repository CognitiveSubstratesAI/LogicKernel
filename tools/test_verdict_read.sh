#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — runs tools/test_verdict_read.py (the tests of tools/verdict_read.py, audit D-0917).
# Python and git only, no Julia, a few seconds: exit 0 only if every case passes.
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/test_verdict_read.py" "$@"
