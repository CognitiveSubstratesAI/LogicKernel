#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the PARSER of tools/ci_triage.sh (audit D-0327 item 1). Run as
# `python3 -I tools/ci_triage.py failed|report DIR [RUN]`; DIR holds jobs_<page>.json and <job id>.log.
#   failed DIR       one line per job that is neither success nor skipped: "<id>\t<name>"
#   report DIR RUN   the triage, at most MAXLINES lines
import glob
import json
import os
import re
import sys

MAXLINES = 40
OK = ("success", "skipped", "neutral")
TS = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ?")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
HEAD = re.compile(r"^(?:(.*): )?(Test Failed|Error During Test|JET-test failed) at (\S+?)(?::(\d+))?\s*$")
CASE = re.compile(r"^\s+FAIL (\S.*)$")
PREFIX = "/home/runner/work/LogicKernel/LogicKernel/"


def load_jobs(d):
    jobs = []
    for f in sorted(glob.glob(os.path.join(d, "jobs_*.json")), key=lambda p: int(re.findall(r"jobs_(\d+)", p)[0])):
        jobs += json.load(open(f)).get("jobs", [])
    return jobs


def failed(jobs):
    return [j for j in jobs if j.get("status") == "completed" and j.get("conclusion") not in OK]


def lines_of(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    return [TS.sub("", ANSI.sub("", ln.replace("﻿", ""))) for ln in text.splitlines()]


def clip(s, n):
    s = s.strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def where(loc, line):
    if loc.startswith(PREFIX):
        loc = loc[len(PREFIX):]
    elif loc.startswith("/home/runner/"):
        loc = os.path.basename(loc)
    return loc + (":" + line if line else "")


def jet_target(expr):
    """The function a JET expression analyses: `(JET.report_opt)(LogicKernel.f, Tuple{…` -> f; a keyword call -> f(kw)."""
    m = re.search(r"report_\w+\)\(([\w.!?]+)", expr)
    t = m.group(1).replace("LogicKernel.", "") if m else (clip(expr, 60) or "(no Expression line)")
    k = re.search(r"typeof\((\w+)\)", expr)
    return "%s(%s)" % (k.group(1), "kw") if t == "Core.kwcall" and k else t


def tests_of(lines):
    """The failures in one log: (kind, desc, where, expression-key) -> (expression, evaluated, error)."""
    found = {}
    for i, ln in enumerate(lines):
        m = HEAD.match(ln)
        c = CASE.match(ln)
        if m:
            desc, kind, loc, line = m.group(1) or "", m.group(2), m.group(3), m.group(4)
            expr = evald = err = ""
            for nx in lines[i + 1: i + 7]:
                s = nx.strip()
                if not s or HEAD.match(nx):
                    break
                if s.startswith("Expression:") and not expr:
                    expr = s[len("Expression:"):].strip()
                elif s.startswith("Evaluated:") and not evald:
                    evald = s[len("Evaluated:"):].strip()
                elif kind == "Error During Test" and not err and not s.startswith(("Got exception", "Stacktrace")):
                    err = s
            w = where(loc, line)
            key = (kind, desc, w, "")
            if kind == "JET-test failed":
                found.setdefault(key, ([], "", ""))[0].append(jet_target(expr))
            else:
                found.setdefault(key, (expr, evald, err))
        elif c:
            found.setdefault(("case FAIL", c.group(1).strip(), "", ""), ("", "", ""))
    return found


def first_error(lines):
    for ln in lines:
        if ln.startswith("##[error]"):
            return ln[len("##[error]"):].strip()
    return ""


def names(js, n=3):
    shown = ", ".join(js[:n])
    return shown + (" +%d" % (len(js) - n) if len(js) > n else "")


def report(d, run):
    jobs = load_jobs(d)
    if not jobs:
        return ["ci_triage: run %s: no jobs read (unknown run, or no network)" % run], 2
    bad = failed(jobs)
    j0 = jobs[0]
    out = ["ci_triage: run %s  %s  %s  %s: %d of %d jobs not green" % (
        run, j0.get("workflow_name", "?"), j0.get("head_branch", "?"), (j0.get("head_sha") or "?")[:7], len(bad), len(jobs))]
    if not bad:
        out.append("no failed job (still running, or green)")
        return out, 0
    out.append("failed jobs: " + clip("; ".join(j["name"] for j in bad), 230))
    errs, tests = {}, {}
    for j in bad:
        lines = lines_of(os.path.join(d, "%s.log" % j["id"]))
        if not lines:
            errs.setdefault("(log not readable)", []).append(j["name"])
            continue
        e = first_error(lines)
        errs.setdefault(e or "(no ##[error] line)", []).append(j["name"])
        for key, val in tests_of(lines).items():
            if key[0] == "JET-test failed" and key in tests:
                tests[key][0][0].extend(val[0])
            tests.setdefault(key, [val, []])[1].append(j["name"])
    for e, js in list(errs.items())[:3]:
        out.append("first ##[error]: %s  [%s]" % (clip(e, 150), names(js)))
    if len(errs) > 3:
        out.append("first ##[error]: %d more distinct lines in the other jobs" % (len(errs) - 3))
    if tests:
        out.append("distinct failing tests: %d" % len(tests))
    for n, (key, (val, js)) in enumerate(tests.items(), 1):
        kind, desc, w, _ = key
        if kind == "JET-test failed":
            targets = sorted(set(val[0]))
            out.append("%2d. [%s] %s  %s" % (n, kind, w, clip(desc, 110)))
            out.append("      analysed %d: %s" % (len(targets), clip("; ".join(targets), 200)))
            out.append("      in: " + names(js, 9))
            continue
        if kind == "case FAIL":
            out.append("%2d. [FAIL] %s  [%s]" % (n, clip(desc, 170), names(js)))
            continue
        out.append("%2d. [%s] %s  %s" % (n, kind, w, clip(desc, 110)))
        if val[0]:
            out.append("      Expression: " + clip(val[0], 160))
        if val[1]:
            out.append("      Evaluated: " + clip(val[1], 160))
        if val[2]:
            out.append("      Error: " + clip(val[2], 160))
        out.append("      in: " + names(js))
    if len(out) > MAXLINES:
        out = out[: MAXLINES - 1] + ["... %d more lines cut (the 40-line cap); fetch the job log for the rest" % (len(out) - MAXLINES + 1)]
    return out, 1


def main(argv):
    if len(argv) >= 3 and argv[1] == "failed":
        for j in failed(load_jobs(argv[2])):
            print("%s\t%s" % (j["id"], j["name"]))
        return 0
    if len(argv) >= 4 and argv[1] == "report":
        lines, rc = report(argv[2], argv[3])
        print("\n".join(lines))
        return rc
    print("usage: ci_triage.py failed DIR | report DIR RUN", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
