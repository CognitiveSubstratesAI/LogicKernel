#!/usr/bin/env bash
# ORIGINAL: the whole suite as ONE mutation target (2026-10-20) — no swipl-devel counterpart.
# tools/mutate_suite.sh — test/runtests.jl on the reference term type, for a mutant list's TARGETS
# (`sh:tools/mutate_suite.sh`: a target holds no blank). A mutant it catches is caught by SOME test
# file, and the driver keeps the first failing test line, which names the file; one it does not catch
# is caught by none. In CI, .github/workflows/mutation.yml checks swipl-devel out at the pin for it
# (test/test_vendored_plunit.jl needs it). ~20 min a mutant in CI.
LOGICKERNEL_TERM_ONLY=reference exec julia --project=. --startup-file=no test/runtests.jl
