#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the job summary of .github/workflows/ci-compile.yml (audit D-0636 item 2:
# "failures are printed as a job summary table: file, line, message").
#
#   python3 -I tools/ci_compile_summary.py LOGDIR      # markdown on stdout; the workflow appends it to $GITHUB_STEP_SUMMARY
#
# LOGDIR holds, per step, NAME.log (its output) and NAME.rc (its exit code, or `skipped`), written by
# tools/ci_compile_run.sh. The table has one row per failure found in a failed step's log: step, file, line,
# message. Recognised: `check_bool_atoms: path:line: text` (tools/check_bool_atoms.sh) and `check_where_return: path:line: text`
# (tools/check_where_return.sh); Julia `Test Failed at
# path:line` + its `Expression:` line and `Error During Test at path:line` + its exception line; an `ERROR:` line of
# a failed load/precompile with the first stack frame `@ Module path:line` under src/, test/ or tools/;
# port_check's two-space violation lines (`path:line: message` or `path: message`); the formatter's
# `diff --git a/X b/X` files. A failed step that none of these explain gets ONE row with the last non-blank line of its
# log (a failure is never silently dropped: file `-`). Exit status: 0 every step passed or skipped, 1 at least one
# failed, 2 usage or a LOGDIR with no .rc file (an empty verdict would pass by default).
#
#   python3 -I tools/ci_compile_summary.py [--title TITLE] [--expect NAME,NAME,...] LOGDIR
#
# THE STATIC JOB (CIREF2, audit D-0651): the `static-summary` job of the workflow downloads the nine shards' LOGDIRs
# (steps `sa_1` .. `sa_9`, one .log and one .rc each) into one directory and runs this with `--title` and `--expect`.
# `--expect` lists the steps that MUST have a result: one with no .rc is a FAILED row (a shard that did not run or
# whose artifact is missing is no pass by default). A failed step named `sa_<k>` is read for the findings of the
# analysis tools BY NAME, with file:line: Aqua prints a banner per failing check to stderr (`Ambiguity #N`,
# `Unbound type parameters detected:`, `Undefined exports detected:`, `Possible type-piracy detected:`,
# `Undocumented names detected:`) followed by the Methods (`sig @ Module path:line`) or Symbols; JET prints one
# `┌ sig @ Module path:line` per report, the message on the `│ text` line before its `└`. The row message begins
# `Aqua <check>:` or `JET:`. THESE SHAPES ARE READ FROM THE AQUA AND JET SOURCES, not yet from a failing CI log:
# the first red shard confirms them, and whatever they miss still gets the generic rows (Test Failed, ERROR,
# the last line): nothing is dropped.
import os
import re
import sys

MAX_ROWS_PER_STEP = 40


def cell(s):
    return re.sub(r"\s+", " ", str(s)).replace("|", "\\|").strip()[:200]


def under_tree(path):
    return bool(re.search(r"/(src|test|tools)/", path))


def short(path):
    k = path.find("/.julia/")
    if k >= 0:                       # a package of the depot (Aqua's, JET's own file): never mistaken for this tree's src/
        return path[k + 1 :]
    m = re.search(r"/((?:src|test|tools|boot|docs)/.*)$", path)
    return m.group(1) if m else path


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Aqua's banner line -> the name of the check it belongs to (Aqua.jl: ambiguities.jl, unbound_args.jl, exports.jl,
# piracies.jl, undocumented_names.jl)
AQUA_BANNERS = (
    (re.compile(r"^Ambiguity #\d+"), "Method ambiguity"),
    (re.compile(r"^\d+ ambiguities found"), "Method ambiguity"),
    (re.compile(r"^Unbound type parameters detected:"), "Unbound type parameters"),
    (re.compile(r"^Undefined exports detected:"), "Undefined exports"),
    (re.compile(r"^Possible type-piracy detected:"), "Piracy"),
    (re.compile(r"^Undocumented names detected:"), "Undocumented names"),
)
# a Method as `show` prints it: `sig @ Module path.jl:line` (optionally after a `[k] ` index)
METHOD_AT = re.compile(r"^\s*(?:\[\d+\]\s*)?(.+?) @ (\S+) (\S+?\.jl):(\d+)\s*$")
# the end of an Aqua block: another testset's report, the summary table, a JET report
AQUA_END = re.compile(r"^\s*(Test Failed at|Error During Test at|JET-test failed|Test Summary:|\s*═════)")


def parse_static(text):
    """Rows (file, line, message) of the Aqua and JET findings in one analysis shard's log, by name."""
    rows = []
    lines = [ANSI.sub("", x) for x in text.splitlines()]
    check = None
    for i, ln in enumerate(lines):
        if AQUA_END.match(ln):
            check = None
        for rx, name in AQUA_BANNERS:
            if rx.match(ln):
                check = name
                break
        else:
            if check:
                m = METHOD_AT.match(ln)
                if m:
                    rows.append((short(m.group(3)), m.group(4), "Aqua %s: %s" % (check, m.group(1))))
                    continue
                m = re.match(r"^\s+:(\S+?),?\s*$", ln)
                if m:
                    rows.append(("-", "-", "Aqua %s: :%s" % (check, m.group(1))))
                    continue
        # JET: a top-level report frame `┌ sig @ Module path:line` (nested frames start `│┌`, so they do not match)
        m = re.match(r"^\s*┌ (.+?) @ (\S+) (\S+?\.jl):(\d+)\s*$", ln)
        if m:
            msg = ""
            for x in lines[i + 1 : i + 400]:
                if re.match(r"^\s*└", x) or re.match(r"^\s*┌ ", x):
                    break
                t = re.match(r"^\s*│+ ([^┌└│].*)$", x)
                if t and "┌" not in x:
                    msg = t.group(1).strip()
            rows.append((short(m.group(3)), m.group(4), "JET: %s: %s" % (m.group(1), msg or "(no message line)")))
    seen, out = set(), []
    for r in rows:
        if r not in seen:
            seen.add(r)
            out.append(r)
    return out


def parse(step, text):
    """Rows (file, line, message) for one failed step's log."""
    rows = []
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        m = re.match(r"check_bool_atoms: (\S+?):(\d+): (.*)$", ln)
        if m:
            rows.append((m.group(1), m.group(2), "Bool is no atom: " + m.group(3)))
            continue
        m = re.match(r"check_where_return: (\S+?):(\d+): (.*)$", ln)
        if m:
            rows.append((m.group(1), m.group(2), "where binds to the return type: " + m.group(3)))
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
    if step.startswith("sa_"):
        found = parse_static(text)
        if found:
            # the tools' own findings first; of the generic rows only those in this tree (the Test Failed of
            # the testset that holds the tool call), not the ones inside Aqua's or JET's own files
            rows = found + [r for r in rows if not r[0].startswith(".julia/")]
    if not rows:
        tail = [x for x in lines if x.strip()]
        rows.append(("-", "-", tail[-1] if tail else "(the step printed nothing)"))
    return rows[:MAX_ROWS_PER_STEP]


def main(argv):
    title, expect, args, i = "CI compile check", [], [], 1
    while i < len(argv):
        if argv[i] in ("--title", "--expect") and i + 1 < len(argv):
            if argv[i] == "--title":
                title = argv[i + 1]
            else:
                expect = [x for x in argv[i + 1].split(",") if x]
            i += 2
        else:
            args.append(argv[i])
            i += 1
    if len(args) != 1 or not os.path.isdir(args[0]):
        print("usage: ci_compile_summary.py [--title TITLE] [--expect NAME,NAME,...] LOGDIR", file=sys.stderr)
        return 2
    d = args[0]
    steps = sorted(f[:-3] for f in os.listdir(d) if f.endswith(".rc"))
    if not steps and not expect:
        print("ci_compile_summary: no step recorded an exit code in " + d, file=sys.stderr)
        return 2
    missing = [e for e in expect if e not in steps]
    steps = sorted(set(steps) | set(expect), key=lambda x: (len(x), x))
    failed, out = [], ["## " + title, "", "| step | result |", "|---|---|"]
    for s in steps:
        if s in missing:
            out.append("| %s | FAILED (no result recorded) |" % s)
            failed.append(s)
            continue
        rc = open(os.path.join(d, s + ".rc")).read().strip()
        out.append("| %s | %s |" % (s, "passed" if rc == "0" else ("skipped (a step it needs failed)" if rc == "skipped" else "FAILED (exit %s)" % rc)))
        if rc not in ("0", "skipped"):
            failed.append(s)
    if not failed:
        out += ["", "No failure."]
        print("\n".join(out))
        return 0
    table = []
    for s in failed:
        if s in missing:
            table.append((s, [("-", "-", "no result: the step did not run, or its artifact is missing")]))
            continue
        p = os.path.join(d, s + ".log")
        text = open(p, errors="replace").read() if os.path.isfile(p) else ""
        table.append((s, parse(s, text)))
    tools = {"Aqua": 0, "JET": 0}
    for _, rows in table:
        for _, _, m in rows:
            for t in tools:
                if m.startswith(t + " ") or m.startswith(t + ":"):
                    tools[t] += 1
    if any(tools.values()):
        out += ["", "### Static analysis findings", "", "| tool | findings |", "|---|---|"]
        out += ["| %s | %d |" % (t, n) for t, n in tools.items()]
    out += ["", "### Failures", "", "| step | file | line | message |", "|---|---|---|---|"]
    for s, rows in table:
        for f, l, m in rows:
            out.append("| %s | %s | %s | %s |" % (cell(s), cell(f), cell(l), cell(m)))
    print("\n".join(out))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
