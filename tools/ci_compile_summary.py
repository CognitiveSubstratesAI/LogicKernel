#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the job summary of .github/workflows/ci-compile.yml (audit D-0636 item 2:
# "failures are printed as a job summary table: file, line, message").
#
#   python3 -I tools/ci_compile_summary.py LOGDIR      # markdown on stdout; the workflow appends it to $GITHUB_STEP_SUMMARY
#
# LOGDIR holds, per step, NAME.log (its output) and NAME.rc (its exit code, or `skipped`), written by
# tools/ci_compile_run.sh. The table has one row per failure found in a failed step's log: step, file, line,
# message. Recognised: `check_bool_atoms: path:line: text` (tools/check_bool_atoms.sh); Julia `Test Failed at
# path:line` + its `Expression:` line and `Error During Test at path:line` + its exception line; an `ERROR:` line of
# a failed load/precompile with the first stack frame `@ Module path:line` under src/, test/ or tools/;
# port_check's two-space violation lines (`path:line: message` or `path: message`); the formatter's
# `diff --git a/X b/X` files. A failed step that none of these explain gets ONE row with the last non-blank line of its
# log (a failure is never silently dropped: file `-`). Exit status: 0 every step passed or skipped, 1 at least one
# failed, 2 usage or a LOGDIR with no .rc file (an empty verdict would pass by default).
import os
import re
import sys

MAX_ROWS_PER_STEP = 40


def cell(s):
    return re.sub(r"\s+", " ", str(s)).replace("|", "\\|").strip()[:200]


def under_tree(path):
    return bool(re.search(r"/(src|test|tools)/", path))


def short(path):
    m = re.search(r"/((?:src|test|tools|boot|docs)/.*)$", path)
    return m.group(1) if m else path


def parse(step, text):
    """Rows (file, line, message) for one failed step's log."""
    rows = []
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        m = re.match(r"check_bool_atoms: (\S+?):(\d+): (.*)$", ln)
        if m:
            rows.append((m.group(1), m.group(2), "Bool is no atom: " + m.group(3)))
            continue
        m = re.match(r"\s*Test Failed at (\S+?):(\d+)\s*$", ln)
        if m:
            expr = next((x.strip() for x in lines[i + 1 : i + 4] if x.strip().startswith("Expression:")), "")
            rows.append((short(m.group(1)), m.group(2), "Test Failed " + expr))
            continue
        m = re.match(r"\s*Error During Test at (\S+?):(\d+)\s*$", ln)
        if m:
            msg = next(
                (x.strip() for x in lines[i + 1 : i + 6] if x.strip() and not x.strip().startswith("Got exception")),
                "",
            )
            rows.append((short(m.group(1)), m.group(2), "Error During Test: " + msg))
            continue
        m = re.match(r"(?:ERROR: )+(.*)$", ln)
        if m and "Test Failed" not in ln:
            frame = None
            for x in lines[i + 1 : i + 40]:
                f = re.search(r"@ (?:\S+ )?(\S+?\.jl):(\d+)", x) or re.search(r"\bat (\S+?\.jl):(\d+)", x)
                if f and under_tree(f.group(1)):
                    frame = f
                    break
            rows.append((short(frame.group(1)) if frame else "-", frame.group(2) if frame else "-", "ERROR: " + m.group(1)))
            continue
        m = re.match(r"diff --git a/(\S+) b/\S+", ln)
        if m:
            rows.append((m.group(1), "-", "not Blue-formatted (the formatter changed it)"))
            continue
    if step == "port_check":
        for ln in lines:
            if not ln.startswith("  ") or not ln.strip():
                continue
            m = re.match(r"\s+(\S+?\.\w+):(\d+):? (.*)$", ln)
            if m:
                rows.append((m.group(1), m.group(2), m.group(3)))
                continue
            m = re.match(r"\s+(\S+?\.\w+): (.*)$", ln)
            rows.append((m.group(1), "-", m.group(2)) if m else ("-", "-", ln.strip()))
    if not rows:
        tail = [x for x in lines if x.strip()]
        rows.append(("-", "-", tail[-1] if tail else "(the step printed nothing)"))
    return rows[:MAX_ROWS_PER_STEP]


def main(argv):
    if len(argv) != 2 or not os.path.isdir(argv[1]):
        print("usage: ci_compile_summary.py LOGDIR", file=sys.stderr)
        return 2
    d = argv[1]
    steps = sorted(f[:-3] for f in os.listdir(d) if f.endswith(".rc"))
    if not steps:
        print("ci_compile_summary: no step recorded an exit code in " + d, file=sys.stderr)
        return 2
    failed, out = [], ["## CI compile check", "", "| step | result |", "|---|---|"]
    for s in steps:
        rc = open(os.path.join(d, s + ".rc")).read().strip()
        out.append("| %s | %s |" % (s, "passed" if rc == "0" else ("skipped (a step it needs failed)" if rc == "skipped" else "FAILED (exit %s)" % rc)))
        if rc not in ("0", "skipped"):
            failed.append(s)
    if not failed:
        out += ["", "No failure."]
        print("\n".join(out))
        return 0
    out += ["", "### Failures", "", "| step | file | line | message |", "|---|---|---|---|"]
    for s in failed:
        p = os.path.join(d, s + ".log")
        text = open(p, errors="replace").read() if os.path.isfile(p) else ""
        for f, l, m in parse(s, text):
            out.append("| %s | %s | %s | %s |" % (cell(s), cell(f), cell(l), cell(m)))
    print("\n".join(out))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
