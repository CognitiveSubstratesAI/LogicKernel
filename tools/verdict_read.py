#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the ONE-SHA VERDICT READER (audit D-0917 items 1 and 2): every GitHub Actions run of
# one commit, every mutation battery's `Verdict table` read into ONE table, the landing checks of D-0915 (1) as a second block,
# and the survivor ledger (evidence/survivors.tsv) the tool writes and merges. It replaces the several ~60-line log reads per
# battery (tools/battery_table.sh, one battery at a time) with one table of about 2 KB per commit.
#
#   python3 -I tools/verdict_read.py SHA [--base REF] [--set evidence/gate_set.txt] [--ledger] [--json]
#                                        [--budget N] [--cache DIR] [--set-row MUTANT FIELD=VALUE ...]
#
#   SHA            full 40 hex or an abbreviation, resolved against this repository (git rev-parse)
#   --base REF     the landing base (default origin/main): the src diff, the D-0164 term grep, the ancestry and the authors
#   --set FILE     the batteries of a landing set, one per line `NAME [last-clean-read-SHA]` (# comments): complete at SHA?
#   --ledger       write evidence/survivors.tsv: every survivor of the batteries read here is merged in (a row is never lost,
#                  an owner/status/D-entry a human set is never overwritten, first_seen stays, last_seen moves)
#   --set-row M F=V  with --ledger: set a field (owner, status, d_entry) of the ledger row of mutant M
#   --json         the same facts as one JSON object, `landable` included (for the auto-land workflow)
#   --budget N     at most N API requests (default 40; the anonymous API allows 60 an hour for everyone on this address)
#   --cache DIR    responses of COMPLETED runs and jobs are kept here (default $TMPDIR/lk-verdict-read-cache)
#
# DATA SOURCES. The runs of the commit: GET actions/runs?head_sha= (one call). Per battery run: its jobs (one call, one more per
# 100 jobs) and the annotations of its `Verdict table` job (one call): the notice annotations of the step `The table as
# annotations` hold the table rows, readable anonymously. The job log (tools/ci_api.sh ci_job_log, the stored token read there,
# never here) is the fallback when the annotations are cut (GitHub shows 10 per step) or empty. tools/ci_api.sh makes every
# call (a rate-limited anonymous call falls back to the stored token inside it); this file never reads a credential.
# Seam: LOGICKERNEL_CI_FIXTURE_DIR (tools/ci_api.sh): tools/test_verdict_read.py runs on saved answers.
#
# THE TABLE. Per battery: decided/total, caught, SURV(ived), TMO (TIMEOUT), ERR (BADMATCH, EQUIVALENT REFUTED, anything else),
# NOV (NO VERDICT), INV (INVALID), EQV (declared equivalents: accepted by a D-entry / declared). First the blocks that need a
# person: survivors with NO OWNER in the ledger, declared equivalents with NO D-ENTRY in evidence/equivalents.tsv, jobs that
# ended without a verdict (conclusion, the step that never completed), a battery whose Baseline failed (VOID).
# Exit status: 0 all clean, 1 a blocker or a failed landing check, 2 unreadable, 3 a run still pending, 64 usage.
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battery_table as bt  # noqa: E402  (the one parser of the Verdict table rows)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKING = ("SURVIVED", "TIMEOUT", "INVALID", "BADMATCH", "EQUIVALENT REFUTED", "NO VERDICT")
OPEN_STATES = ("open", "row committed", "candidate equivalent", "deferred kill")
STATES = OPEN_STATES + ("fresh proof", "accepted equivalent")
LEDGER_HEAD = ["battery", "mutant", "owner", "status", "d_entry", "first_seen", "last_seen"]
EQ_HEAD = ["mutant", "d_entry", "case_analysis"]
SKIP_JOBS = ("Plan", "Verdict table")
SUMMARY = re.compile(r"\*\*(\d+) of (\d+) decided; blocking: (.*?)\*\*")
DENTRY = re.compile(r"\bD-\d{4}\b")


# ------------------------------------------------------------------------------------------------ the API
class Api:
    """The reads through tools/ci_api.sh (bash), counted, cached for completed runs, capped by a budget."""

    def __init__(self, root, cache, budget):
        self.root, self.cache, self.budget = root, cache, budget
        self.requests = 0
        self.hits = 0
        self.refused = 0
        if cache:
            os.makedirs(cache, exist_ok=True)

    def _sh(self, fn, *args):
        script = 'ROOT="$1"; shift; . "$ROOT/tools/ci_api.sh"; %s "$@"' % fn
        r = subprocess.run(["bash", "-c", script, "bash", self.root] + [str(a) for a in args],
                           capture_output=True, text=True, errors="replace")
        return r.returncode, r.stdout

    def _cached(self, key, final, fetch):
        path = os.path.join(self.cache, key) if self.cache else None
        if path and os.path.isfile(path):
            self.hits += 1
            with open(path, encoding="utf-8") as f:
                return f.read()
        if self.requests >= self.budget:
            self.refused += 1
            return None
        self.requests += 1
        text = fetch()
        if path and final and text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        return text

    def runs(self, sha):
        if self.requests >= self.budget:
            self.refused += 1
            return None
        self.requests += 1
        rc, out = self._sh("ci_runs_for_sha", sha)
        return _json(out, "workflow_runs")

    def jobs(self, run):
        """All jobs of a run (one call per 100); None when the budget or the answer fails."""
        final = run.get("status") == "completed"
        jobs, page, total = [], 1, None
        while page <= 10:
            key = "jobs_%s_%s_%d.json" % (run["id"], run.get("run_attempt", 1), page)
            text = self._cached(key, final, lambda p=page: self._sh("ci_jobs_page", run["id"], p)[1])
            d = _json(text, "jobs") if text else None
            if d is None:
                return None if page == 1 else jobs
            if total is None:
                total = d.get("total_count", len(d["jobs"]))
            jobs += d["jobs"]
            if len(jobs) >= total or not d["jobs"]:
                break
            page += 1
        return jobs

    def annotations(self, job, run_id):
        final = job.get("status") == "completed"
        text = self._cached("ann_%s.json" % job["id"], final, lambda: self._sh("ci_annotations", job["id"], run_id)[1])
        try:
            d = json.loads(text) if text else None
        except ValueError:
            return None
        return d if isinstance(d, list) else None

    def log(self, job, run_id):
        if self.requests >= self.budget:
            self.refused += 1
            return None
        self.requests += 1
        rc, out = self._sh("ci_job_log", job["id"], run_id)
        return out if rc == 0 and out.strip() else None


def _json(text, key):
    try:
        d = json.loads(text)
    except (ValueError, TypeError):
        return None
    return d if isinstance(d, dict) and key in d else None


# ------------------------------------------------------------------------------------------------ the Verdict table
def table_from_annotations(anns):
    """(lines, complete) from the `verdicts i/n` notices: ordered by i; complete = every part seen and the summary line there."""
    parts = []
    for a in anns or []:
        m = re.match(r"verdicts (\d+)/(\d+)", a.get("title") or "")
        if m:
            parts.append((int(m.group(1)), int(m.group(2)), a.get("message") or ""))
    if not parts:
        return [], False
    parts.sort()
    n = parts[0][1]
    text = "\n".join(p[2] for p in parts)
    lines = text.split("\n")
    complete = len({p[0] for p in parts}) == n and any(SUMMARY.search(ln) for ln in lines)
    return lines, complete


def classify(verdict):
    v = verdict.strip()
    if v.startswith("caught"):
        return "caught"
    if v.startswith("SURVIVED"):
        return "surv"
    if v.startswith("TIMEOUT"):
        return "tmo"
    if v.startswith("NO VERDICT"):
        return "nov"
    if v.startswith("INVALID"):
        return "inv"
    if v.startswith("EQUIVALENT (declared)"):
        return "eqv"
    return "err"                                   # BADMATCH, EQUIVALENT REFUTED, anything unknown


def step_record(job):
    """The first step that did not complete in success, as text: `step 12 'name' started, no completion` / `... failure`."""
    for s in job.get("steps") or []:
        c = s.get("conclusion")
        if c in ("success", "skipped"):
            continue
        what = "started, no completion" if not c else c
        return "step %s '%s' %s" % (s.get("number"), bt.clip(s.get("name", "?"), 40), what)
    return ""


def download_note(vjob):
    """The digest-mismatch retry: the download step ran twice and the retry succeeded: not a failure of the battery."""
    steps = [s for s in (vjob.get("steps") or []) if "download-artifact" in s.get("name", "")]
    ran = [s for s in steps if s.get("conclusion") not in (None, "skipped")]
    if len(ran) >= 2 and ran[-1].get("conclusion") == "success":
        return "download retried (digest-mismatch retry), succeeded"
    if ran and all(s.get("conclusion") == "failure" for s in ran):
        return "download FAILED (every try)"
    return ""


def read_battery(api, run):
    """One battery run -> dict: branch, run, state, counts, rows, failed jobs, notes."""
    b = {"branch": run.get("head_branch", "?"), "run": run["id"], "conclusion": run.get("conclusion"),
         "status": run.get("status"), "state": "unreadable", "rows": [], "failed": [], "notes": [], "summary": ""}
    jobs = api.jobs(run)
    if jobs is None:
        b["notes"].append("jobs not read (request budget or answer)")
        b["state"] = "not read"
        return b
    vjob = bt.find(jobs, lambda n: n == "Verdict table")
    bjob = bt.find(jobs, lambda n: n.startswith("Baseline"))
    pjob = bt.find(jobs, lambda n: n == "Plan")
    mut = [j for j in jobs if j["name"] != "Plan" and j["name"] != "Verdict table" and not j["name"].startswith("Baseline")]
    b["jobs_total"], b["jobs_done"] = len(mut), sum(1 for j in mut if j.get("status") == "completed")
    for j in mut:
        if j.get("status") == "completed" and j.get("conclusion") not in ("success", "skipped"):
            b["failed"].append({"name": j["name"], "id": j["id"], "conclusion": j.get("conclusion"), "step": step_record(j)})
    if pjob and pjob.get("status") == "completed" and pjob.get("conclusion") != "success":
        b["state"] = "plan failed"
        b["notes"].append("Plan job %s %s" % (pjob["id"], pjob.get("conclusion")))
        return b
    if bjob is None:
        b["state"] = "not a battery"
        return b
    if bjob.get("status") != "completed":
        b["state"] = "pending"
        return b
    if bjob.get("conclusion") != "success":
        b["state"] = "void"
        b["notes"].append("Baseline job %s %s %s" % (bjob["id"], bjob.get("conclusion"), step_record(bjob)))
        return b
    if vjob is None or vjob.get("status") != "completed":
        b["state"] = "pending"
        return b
    b["verdict_job"] = vjob["id"]
    note = download_note(vjob)
    if note:
        b["notes"].append(note)
    lines, complete = table_from_annotations(api.annotations(vjob, run["id"]))
    if not complete:
        text = api.log(vjob, run["id"])
        if text:
            lines = [bt.TS.sub("", ln) for ln in text.splitlines()]
            b["notes"].append("table read from the job log (annotations cut or empty)")
    _, rows, summary = bt.table_of(lines)
    b["summary"] = summary
    if not rows:
        b["state"] = "unreadable"
        b["notes"].append("Verdict table job %s %s %s: no table in annotations or log" % (
            vjob["id"], vjob.get("conclusion"), step_record(vjob)))
        return b
    b["rows"] = [{"id": r[0], "verdict": r[1], "time": r[2], "what": bt.desc(r), "kind": classify(r[1])} for r in rows]
    jobs_by_name = {j["name"]: j for j in mut}
    for r in b["rows"]:
        if r["kind"] == "nov":
            j = jobs_by_name.get(r["id"])
            r["job"] = ("job %s %s %s" % (j["id"], j.get("conclusion") or j.get("status"), step_record(j)) if j
                        else "no job named %s" % r["id"]).strip()
    m = SUMMARY.search(summary or "")
    if m and int(m.group(2)) != len(rows):
        b["notes"].append("summary says %s of %s, %d rows read (table cut)" % (m.group(1), m.group(2), len(rows)))
    b["state"] = "done"
    return b


def counts(b):
    c = {"caught": 0, "surv": 0, "tmo": 0, "err": 0, "nov": 0, "inv": 0, "eqv": 0}
    for r in b["rows"]:
        c[r["kind"]] += 1
    c["total"] = len(b["rows"])
    c["decided"] = c["total"] - c["surv"] - c["tmo"] - c["err"] - c["nov"] - c["inv"]
    return c


# ------------------------------------------------------------------------------------------------ the files
def read_tsv(path, head):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return rows
    for ln in lines:
        if not ln.strip() or ln.startswith("#") or ln.split("\t")[0] == head[0]:
            continue
        f = ln.split("\t")
        f += [""] * (len(head) - len(f))
        rows.append(dict(zip(head, f[: len(head)])))
    return rows


def write_tsv(path, head, rows, comment):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# %s\n" % comment)
        f.write("\t".join(head) + "\n")
        for r in rows:
            f.write("\t".join(re.sub(r"[\t\n]", " ", r.get(h, "")) for h in head) + "\n")


def load_equivalents(path):
    """The declared equivalents by mutant id. A row whose D-entry column is not a `D-NNNN` id (`pending`, empty, free text) is
    refused with ValueError naming the row: an unratified row would turn a declared equivalent into an accepted one (D-0992)."""
    rows = read_tsv(path, EQ_HEAD)
    for r in rows:
        if not re.fullmatch(r"D-\d{4,}", r["d_entry"]):
            raise ValueError("equivalents row %s: the D-entry column is %r, not a D-NNNN id (%s)" % (r["mutant"], r["d_entry"], path))
    return {r["mutant"]: r for r in rows}


def load_ledger(path):
    return {(r["battery"], r["mutant"]): r for r in read_tsv(path, LEDGER_HEAD)}


def read_gate_set(path):
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    for ln in lines:
        ln = ln.split("#", 1)[0].strip()
        if ln:
            f = ln.split()
            out.append((f[0], f[1] if len(f) > 1 else ""))
    return out


def eq_path(what):
    m = re.search(r"pending audit: (?P<p>.*)", what)
    t = m.group("p") if m else what
    m = re.search(r"(?:src/)?(?:[\w-]+/)*pl-[\w-]+\.jl(?::\d+(?:-\d+)?)?", t)
    return m.group(0) if m else ""


def merge_ledger(ledger, batteries, eqs, sha8, sets):
    """Upsert every non-caught row of the batteries read; returns (added, moved). Nothing a human wrote is overwritten."""
    added = moved = 0
    for b in batteries:
        for r in b["rows"]:
            if r["kind"] == "caught":
                continue
            key = (b["name"], r["id"])
            row = ledger.get(key)
            if row is None:
                st = "accepted equivalent" if r["kind"] == "eqv" and r["id"] in eqs else "open"
                row = {"battery": b["name"], "mutant": r["id"], "owner": "", "status": st,
                       "d_entry": eqs.get(r["id"], {}).get("d_entry", ""), "first_seen": sha8, "last_seen": sha8}
                ledger[key] = row
                added += 1
            elif row["last_seen"] != sha8:
                row["last_seen"] = sha8
                moved += 1
    for mutant, field, value in sets:
        hits = [r for k, r in ledger.items() if k[1] == mutant]
        for r in hits:
            if field == "status" and value not in STATES:
                raise SystemExit("verdict_read: status must be one of: " + ", ".join(STATES))
            r[field] = value
        if not hits:
            raise SystemExit("verdict_read: --set-row: no ledger row of mutant %s" % mutant)
    return added, moved


# ------------------------------------------------------------------------------------------------ the landing checks
def git(root, *args, stdin=None):
    r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True, errors="replace", input=stdin)
    return r.returncode, r.stdout


def landing_checks(root, sha, base):
    """The D-0915 (1) checks as a list of (name, ok, text)."""
    out = []
    rc, st = git(root, "diff", "--shortstat", "%s..%s" % (base, sha), "--", "src")
    if rc != 0:
        out.append(("src diff", False, "git diff %s..%s failed (is %s fetched?)" % (base, sha[:8], base)))
    elif not st.strip():
        out.append(("src diff", True, "empty"))
    else:
        _, names = git(root, "diff", "--stat=90", "--stat-count=8", "%s..%s" % (base, sha), "--", "src")
        out.append(("src diff", False, "NON-EMPTY:%s | %s" % (st.rstrip("\n"), "; ".join(
            ln.split("|")[0].strip() for ln in names.splitlines()[:-1]))))
    rc, diff = git(root, "diff", "%s..%s" % (base, sha))
    _, msgs = git(root, "log", "--format=%B", "%s..%s" % (base, sha))
    added = "\n".join(ln[1:] for ln in diff.splitlines() if ln.startswith("+") and not ln.startswith("+++"))
    dterm = os.path.join(root, "tools", "githooks", "dterm.sh")
    if not os.path.isfile(dterm):
        out.append(("D-0164 term grep", False, "tools/githooks/dterm.sh cannot be read here: the grep did not run"))
    else:
        script = '. "$1"; d0164_filter | grep -iE "$TERMS164"'
        r = subprocess.run(["bash", "-c", script, "bash", dterm], input=added + "\n" + msgs, capture_output=True,
                           text=True, errors="replace")
        hits = [ln for ln in r.stdout.splitlines() if ln.strip()]
        if r.returncode == 1 and not hits:
            out.append(("D-0164 term grep", True, "clean (added lines and commit messages, tools/githooks/dterm.sh)"))
        else:
            out.append(("D-0164 term grep", False, "%d hit lines: %s" % (len(hits), " | ".join(bt.clip(h, 90) for h in hits[:3]))))
    rc, _ = git(root, "merge-base", "--is-ancestor", base, sha)
    out.append(("ancestry", rc == 0, "%s is %san ancestor of %s" % (base, "" if rc == 0 else "NOT ", sha[:8])))
    _, ids = git(root, "log", "--format=%an <%ae>|%cn <%ce>", "%s..%s" % (base, sha))
    au = sorted({ln.split("|")[0] for ln in ids.splitlines() if ln})
    co = sorted({ln.split("|")[1] for ln in ids.splitlines() if ln})
    _, n = git(root, "rev-list", "--count", "%s..%s" % (base, sha))
    ok = len(au) == 1 and len(co) == 1
    out.append(("authors", ok, "%s commits; author%s: %s; committer%s: %s" % (
        n.strip(), "s" if len(au) != 1 else "", "; ".join(au) or "none", "s" if len(co) != 1 else "", "; ".join(co) or "none")))
    return out


# ------------------------------------------------------------------------------------------------ the report
def tag(wf):
    return "CI" if wf == "CI" else "Evidence" if wf.startswith("Evidence") else wf


def build(api, sha, base, gate_set, eqs, ledger, root):
    runs = api.runs(sha)
    res = {"sha": sha, "base": base, "runs": [], "batteries": [], "other": [], "requests": 0}
    if runs is None:
        res["error"] = "the runs of %s could not be read (budget, network or rate limit)" % sha[:8]
        return res
    runs = runs["workflow_runs"]
    latest = {}
    for r in sorted(runs, key=lambda r: r.get("created_at", "")):
        latest[(r["name"], r.get("head_branch"))] = r
    res["older"] = {}
    for r in runs:
        k = (r["name"], r.get("head_branch"))
        if latest[k]["id"] != r["id"]:
            res["older"].setdefault(k, []).append("%s %s" % (r["id"], r.get("conclusion") or r.get("status")))
    for (name, branch), r in sorted(latest.items(), key=lambda kv: (kv[0][0], kv[0][1] or "")):
        if name == "Mutation battery" and (branch or "").startswith("mutants/"):
            b = read_battery(api, r)
            b["name"] = branch[len("mutants/"):]
            b["older"] = res["older"].get((name, branch), [])
            res["batteries"].append(b)
        else:
            res["other"].append({"name": name, "branch": branch, "run": r["id"], "status": r.get("status"),
                                 "conclusion": r.get("conclusion")})
    res["requests"], res["hits"], res["refused"] = api.requests, api.hits, api.refused
    return res


def judge(res, eqs, ledger, gate_set):
    """Fills the blockers: ownerless survivors, equivalents with no D-entry, failed jobs, the gate set."""
    own, noent, jobs, bad = [], [], [], []
    for b in res["batteries"]:
        b["counts"] = counts(b) if b["rows"] else None
        b["eqv_ok"] = 0
        for r in b["rows"]:
            if r["kind"] == "eqv":
                e = eqs.get(r["id"])
                if e:
                    b["eqv_ok"] += 1
                else:
                    noent.append((b["name"], r["id"], eq_path(r["what"])))
            elif r["kind"] != "caught":
                row = ledger.get((b["name"], r["id"]))
                if row is None or (not row["owner"] and row["status"] in OPEN_STATES):
                    own.append((b["name"], r["id"], r["verdict"]))
        nov = {r["id"] for r in b["rows"] if r["kind"] == "nov"}
        for f in b["failed"]:
            if f["name"] not in nov:                   # a NO VERDICT row carries its own job record
                jobs.append((b["name"], f))
        b["clean"] = (b["state"] == "done" and b["counts"]["total"] > 0 and b["counts"]["decided"] == b["counts"]["total"]
                      and b["eqv_ok"] == b["counts"]["eqv"])
        if b["state"] in ("void", "plan failed", "unreadable"):
            bad.append(b["name"])
    res["no_owner"], res["no_dentry"], res["failed_jobs"], res["bad"] = own, noent, jobs, bad
    res["pending"] = [b["name"] for b in res["batteries"] if b["state"] == "pending"] + \
        [o["name"] for o in res["other"] if o["status"] != "completed"]
    byname = {b["name"]: b for b in res["batteries"]}
    gs = []
    if gate_set is not None:
        for name, clean in gate_set:
            b = byname.get(name)
            if b is None:
                gs.append({"name": name, "state": "no run", "last_clean": clean})
            else:
                gs.append({"name": name, "state": "clean" if b["clean"] else b["state"] if b["state"] != "done" else "BLOCKED",
                           "last_clean": clean})
        res["gate_set"] = gs
        res["set_uncovered"] = [g["name"] for g in gs if g["state"] == "no run" and not g["last_clean"]]
        res["set_not_clean"] = [g["name"] for g in gs if g["state"] not in ("clean", "no run")]
    res["ci_ok"] = any(o["name"] == "CI" and o["conclusion"] == "success" for o in res["other"])
    res["ev_ok"] = any(o["name"].startswith("Evidence") and o["conclusion"] == "success" for o in res["other"])


def render(res, landing):
    L = []
    L.append("verdict_read %s  base %s  [API requests %d, cache hits %d%s]" % (
        res["sha"][:8], res["base"], res["requests"], res.get("hits", 0),
        (", REFUSED by budget %d" % res["refused"]) if res.get("refused") else ""))
    if res.get("error"):
        return L + [res["error"]]
    bl = []
    for n, m, v in res["no_owner"]:
        bl.append("NO OWNER   %s %s (%s): not in evidence/survivors.tsv with an owner" % (n, m, v))
    for n, m, p in res["no_dentry"]:
        bl.append("NO D-ENTRY %s %s declared equivalent, not in evidence/equivalents.tsv%s" % (n, m, (" (" + p + ")") if p else ""))
    for n, f in res["failed_jobs"]:
        bl.append("JOB %s: %s %s conclusion %s %s" % (n, f["name"], f["id"], f["conclusion"], f["step"]))
    for b in res["batteries"]:
        if b["state"] == "void":
            bl.append("VOID %s run %s: %s (no verdict of this run counts)" % (b["name"], b["run"], "; ".join(b["notes"])))
        elif b["state"] in ("unreadable", "plan failed", "not read"):
            bl.append("%s %s run %s: %s" % (b["state"].upper(), b["name"], b["run"], "; ".join(b["notes"]) or "-"))
        for r in b["rows"]:
            if r["kind"] == "nov":
                bl.append("NO VERDICT %s %s: %s" % (b["name"], r["id"], r.get("job", "")))
    L.append("BLOCKERS (first):" if bl else "BLOCKERS: none")
    L += ["  " + x for x in bl]
    L.append("RUNS: " + " | ".join("%s %s %s" % (tag(o["name"]), o["conclusion"] or o["status"], o["run"]) for o in res["other"]))
    L.append("%-10s %-12s %-8s %6s %4s %3s %3s %3s %3s %-5s %s" % (
        "BATTERY", "RUN", "DEC/TOT", "CAUGHT", "SURV", "TMO", "ERR", "NOV", "INV", "EQV", "STATE"))
    for b in res["batteries"]:
        c = b.get("counts")
        if c:
            state = "clean" if b["clean"] else "BLOCKED"
            L.append("%-10s %-12s %-8s %6d %4d %3d %3d %3d %3d %-5s %s" % (
                b["name"], b["run"], "%d/%d" % (c["decided"], c["total"]), c["caught"], c["surv"], c["tmo"], c["err"], c["nov"],
                c["inv"], "%d/%d" % (b["eqv_ok"], c["eqv"]), state))
        else:
            extra = ""
            if b["state"] == "pending" and "jobs_total" in b:
                extra = " (%d/%d mutant jobs done)" % (b["jobs_done"], b["jobs_total"])
            L.append("%-10s %-12s %-8s %s%s" % (b["name"], b["run"], "-", b["state"].upper(), extra))
        for r in b["rows"]:
            if r["kind"] in ("surv", "tmo", "inv", "err"):
                L.append("    %s %s: %s" % (r["verdict"], r["id"], bt.clip(r["what"], 80)))
        for n in b["notes"]:
            if not n.startswith("Baseline"):
                L.append("    note: " + n)
        if b.get("older"):
            L.append("    older runs of this ref at the SHA: " + ", ".join(b["older"]))
    acc = []
    for b in res["batteries"]:
        for r in b["rows"]:
            if r["kind"] == "eqv" and r["id"] in res["_eqs"]:
                e = res["_eqs"][r["id"]]
                acc.append("%s %s %s" % (r["id"], e["d_entry"], e["case_analysis"]))
    L.append("EQUIVALENTS accepted (id, D-entry, case-analysis path): " + ("; ".join(acc) if acc else "none"))
    if res.get("caught_open"):
        L.append("LEDGER rows now CAUGHT here (set the status): " + ", ".join(res["caught_open"]))
    if landing is not None:
        L.append("LANDING CHECKS (base %s):" % res["base"])
        for name, ok, text in landing:
            L.append("  %-4s %s: %s" % ("ok" if ok else "FAIL", name, text))
        L.append("  %-4s CI at the SHA: %s" % ("ok" if res["ci_ok"] else "FAIL", "success" if res["ci_ok"] else "no green run"))
        L.append("  %-4s Evidence (three term types) at the SHA: %s" % (
            "ok" if res["ev_ok"] else "FAIL", "success" if res["ev_ok"] else "no green run"))
    if res.get("gate_set") is not None:
        L.append("GATE SET (%d batteries):" % len(res["gate_set"]))
        for g in res["gate_set"]:
            if g["state"] == "no run":
                L.append("  %-10s no run at SHA; last clean read at %s" % (g["name"], g["last_clean"] or "none"))
            else:
                L.append("  %-10s %s at SHA" % (g["name"], g["state"]))
        L.append("  set complete at the SHA: %s" % ("yes" if res["gate_complete"] else "NO (%s)" % res["gate_why"]))
    return L


def main(argv):
    ap = argparse.ArgumentParser(prog="verdict_read.py", description="one-SHA verdict reader")
    ap.add_argument("sha")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--set", dest="gate_set")
    ap.add_argument("--ledger", action="store_true")
    ap.add_argument("--set-row", nargs=2, action="append", default=[], metavar=("MUTANT", "FIELD=VALUE"))
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--budget", type=int, default=40)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "lk-verdict-read-cache"))
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--survivors", default=None)
    ap.add_argument("--equivalents", default=None)
    ap.add_argument("--no-landing", action="store_true")
    try:
        a = ap.parse_args(argv[1:])
    except SystemExit:
        return 64
    root = a.root
    surv_path = a.survivors or os.path.join(root, "evidence", "survivors.tsv")
    eq_file = a.equivalents or os.path.join(root, "evidence", "equivalents.tsv")
    rc, full = git(root, "rev-parse", "--verify", "--quiet", a.sha + "^{commit}")
    if rc != 0:
        print("verdict_read: %s does not resolve to a commit of this repository (git fetch origin first)" % a.sha)
        return 2
    full = full.strip()
    gate_set = read_gate_set(a.gate_set if os.path.isabs(a.gate_set) or os.path.isfile(a.gate_set)
                             else os.path.join(root, a.gate_set)) if a.gate_set else None
    if a.gate_set and gate_set is None:
        print("verdict_read: the gate set file %s cannot be read" % a.gate_set)
        return 2
    try:
        eqs = load_equivalents(eq_file)
    except ValueError as e:
        print("verdict_read: %s" % e)
        return 2
    ledger = load_ledger(surv_path)
    api = Api(root, a.cache, a.budget)
    res = build(api, full, a.base, gate_set, eqs, ledger, root)
    res["_eqs"] = eqs
    if res.get("error"):
        print("\n".join(render(res, None)))
        return 2
    judge(res, eqs, ledger, gate_set)
    res["caught_open"] = sorted({r["id"] for b in res["batteries"] for r in b["rows"]
                                 if r["kind"] == "caught" and ledger.get((b["name"], r["id"]), {}).get("status") in OPEN_STATES})
    landing = None if a.no_landing else landing_checks(root, full, a.base)
    if gate_set is not None:
        res["gate_complete"] = not res["set_uncovered"] and not res["set_not_clean"]
        res["gate_why"] = "; ".join(x for x in (
            ("no run and no clean read: " + ", ".join(res["set_uncovered"])) if res["set_uncovered"] else "",
            ("not clean: " + ", ".join(res["set_not_clean"])) if res["set_not_clean"] else "") if x)
    sets = []
    for m, fv in a.set_row:
        if "=" not in fv:
            print("verdict_read: --set-row wants FIELD=VALUE")
            return 64
        f, v = fv.split("=", 1)
        if f not in ("owner", "status", "d_entry"):
            print("verdict_read: --set-row field must be owner, status or d_entry")
            return 64
        sets.append((m, f, v))
    if a.ledger:
        added, moved = merge_ledger(ledger, res["batteries"], eqs, full[:8], sets)
        write_tsv(surv_path, LEDGER_HEAD, [ledger[k] for k in sorted(ledger)],
                  "every survivor ever seen, written by tools/verdict_read.py --ledger (status: %s)" % " / ".join(STATES))
        res["ledger"] = {"added": added, "last_seen_moved": moved, "rows": len(ledger), "file": surv_path}
    landing_ok = landing is None or all(ok for _, ok, _ in landing)
    need_ci = landing is not None
    blockers = bool(res["no_owner"] or res["no_dentry"] or res["failed_jobs"] or res["bad"] or
                    any(not b["clean"] for b in res["batteries"] if b["state"] != "pending") or
                    (gate_set is not None and not res["gate_complete"]))
    res["landable"] = bool(landing_ok and (res["ci_ok"] and res["ev_ok"] or not need_ci) and not blockers
                           and not res["pending"])
    if a.json:
        out = {k: v for k, v in res.items() if k != "_eqs"}
        out["landing"] = [{"check": n, "ok": ok, "text": t} for n, ok, t in landing or []]
        print(json.dumps(out, indent=1, sort_keys=True))
    else:
        print("\n".join(render(res, landing)))
        if a.ledger:
            print("ledger %s: %d rows (%d new, %d last_seen moved)" % (
                os.path.relpath(surv_path, root), res["ledger"]["rows"], res["ledger"]["added"], res["ledger"]["last_seen_moved"]))
    if res["pending"]:
        return 3
    if res["bad"] or any(b["state"] in ("unreadable", "not read") for b in res["batteries"]):
        return 2
    return 0 if res["landable"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
