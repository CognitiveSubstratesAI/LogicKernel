#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the PARSER of tools/battery_table.sh (audit D-0327 item 2). Run as
# `python3 -I tools/battery_table.py ids|report DIR RUN`; DIR holds jobs_<page>.json and <job id>.log.
#   ids DIR RUN      "<verdict job id>\t<baseline job id>" (an empty field when the job is missing)
#   report DIR RUN   the table, at most MAXLINES lines
import glob
import json
import os
import re
import sys

MAXLINES = 60
TS = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ?")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
ROW = re.compile(r"^\| (?P<id>\S+) \| (?P<verdict>[^|]+?) \| (?P<time>[^|]*?) \| (?P<what>.*)$")
BASE = re.compile(r"^Baseline \(unmutated targets\): \*\*(?P<state>.*?)\*\*,? ?(?P<secs>[\d.]+ s)?")


def load_jobs(d):
    jobs = []
    for f in sorted(glob.glob(os.path.join(d, "jobs_*.json")), key=lambda p: int(re.findall(r"jobs_(\d+)", p)[0])):
        jobs += json.load(open(f)).get("jobs", [])
    return jobs


def lines_of(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    return [TS.sub("", ANSI.sub("", ln.replace("﻿", ""))) for ln in text.splitlines()]


def clip(s, n):
    s = s.strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def find(jobs, pred):
    hits = [j for j in jobs if pred(j["name"])]
    return hits[-1] if hits else None


def last_error(lines):
    errs = [ln[len("##[error]"):].strip() for ln in lines if ln.startswith("##[error]")]
    return errs[-1] if errs else ""


def line_before_last_error(lines):
    idx = [i for i, ln in enumerate(lines) if ln.startswith("##[error]")]
    for ln in reversed(lines[: idx[-1]] if idx else []):
        if ln.strip():
            return ln.strip()
    return ""


def table_of(lines):
    """(baseline line, rows, summary line) of the FIRST table (the annotate step prints it a second time)."""
    base, rows, summary, intable = "", [], "", False
    for ln in lines:
        if not base and BASE.match(ln):
            base = ln
        if ln.startswith("| mutant | verdict"):
            if rows:
                break
            intable = True
            continue
        if intable and re.match(r"^\|-+", ln):
            continue
        if intable:
            m = ROW.match(ln)
            if m:
                rows.append((m.group("id"), m.group("verdict").strip(), m.group("time").strip(), m.group("what")))
            elif rows and ln.strip():
                if ln.startswith("**"):
                    summary = ln.strip()
                break
    if not summary:
        for ln in lines:
            if re.match(r"^\*\*.*\*\*$", ln.strip()) and re.search(r"decided|survived|caught", ln):
                summary = ln.strip()
                break
    return base, rows, summary


def desc(r):
    """The row's `what it breaks` text: the row without its last column (`first failing test line`)."""
    return r[3].rsplit(" | ", 1)[0]


def ids(d, run):
    jobs = load_jobs(d)
    v = find(jobs, lambda n: n == "Verdict table")
    b = find(jobs, lambda n: n.startswith("Baseline"))
    print("%s\t%s" % (v["id"] if v else "", b["id"] if b else ""))
    return 0


def report(d, run):
    jobs = load_jobs(d)
    if not jobs:
        return ["battery_table: run %s: no jobs read (unknown run, or no network)" % run], 2
    j0 = jobs[0]
    head = "battery_table: run %s  %s  %s" % (run, j0.get("workflow_name", "?"), j0.get("head_branch", "?"))
    v = find(jobs, lambda n: n == "Verdict table")
    b = find(jobs, lambda n: n.startswith("Baseline"))
    if b is None:
        return [head, "no Baseline job in this run: not a mutation battery (or the plan failed)"], 2
    if b.get("status") != "completed":
        return [head, "PENDING: the Baseline job is %s" % b.get("status")], 3
    vlines = lines_of(os.path.join(d, "%s.log" % v["id"])) if v else []
    base_line, rows, summary = table_of(vlines)
    if b.get("conclusion") != "success":
        blines = lines_of(os.path.join(d, "%s.log" % b["id"]))
        why = last_error(blines) or clip(BASE.sub(r"\g<state>", base_line), 120) or "(no ##[error] line in the baseline log)"
        before = line_before_last_error(blines)
        why = why + (" (the line before: %s)" % clip(before, 80) if before else "")
        return [head, "VOID: baseline failed (job %s, conclusion %s): %s" % (b["id"], b.get("conclusion"), clip(why, 200)),
                "no verdict of this run counts; fix the unmutated tree and run the battery again"], 2
    if v is None or v.get("status") != "completed":
        return [head, "PENDING: the Verdict table job is %s" % (v.get("status") if v else "missing")], 3
    if not rows:
        return [head, "the Verdict table job's log holds no table (unreadable)"], 2
    bm = BASE.match(base_line)
    out = [head, "baseline: %s%s" % (bm.group("state") if bm else "?", ", " + bm.group("secs") if bm and bm.group("secs") else "")]
    kinds = {}
    for r in rows:
        kinds.setdefault(r[1], []).append(r)
    caught = len(kinds.get("caught", []))
    surv = kinds.get("SURVIVED", [])
    eq = kinds.get("EQUIVALENT (declared)", [])
    nov = kinds.get("NO VERDICT", [])
    other = [r for r in rows if r[1] not in ("caught", "SURVIVED", "EQUIVALENT (declared)", "NO VERDICT")]
    out.append("%d mutants: caught %d, SURVIVED %d, EQUIVALENT (declared) %d, NO VERDICT %d%s" % (
        len(rows), caught, len(surv), len(eq), len(nov), (", other %d" % len(other)) if other else ""))
    if summary:
        out.append(clip(summary.strip("*"), 200))
    for r in surv:
        out.append("SURVIVED  %s  %s" % (r[0], clip(desc(r), 110)))
    for r in eq:
        out.append("EQUIVALENT %s  %s" % (r[0], clip(desc(r), 300)))
    for r in nov:
        j = find(jobs, lambda n, i=r[0]: n == i)
        err = ""
        if j is not None:
            err = last_error(lines_of(os.path.join(d, "%s.log" % j["id"])))
            if not err:
                err = "(job %s, no ##[error] line in its log)" % j.get("conclusion")
        else:
            err = "(no job named %s)" % r[0]
        out.append("NO VERDICT %s  %s  | job: %s" % (r[0], clip(desc(r), 70), clip(err, 150)))
    for r in other:
        out.append("OTHER     %s  %s  %s" % (r[0], r[1], clip(desc(r), 80)))
    if len(out) > MAXLINES:
        out = out[: MAXLINES - 1] + ["... %d more lines cut (the %d-line cap)" % (len(out) - MAXLINES + 1, MAXLINES)]
    clean = not surv and not eq and not nov and not other and v.get("conclusion") == "success"
    return out, 0 if clean else 1


def main(argv):
    if len(argv) >= 4 and argv[1] == "ids":
        return ids(argv[2], argv[3])
    if len(argv) >= 4 and argv[1] == "report":
        lines, rc = report(argv[2], argv[3])
        print("\n".join(lines))
        return rc
    print("usage: battery_table.py ids|report DIR RUN", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
