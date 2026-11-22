#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the tests of tools/verdict_read.py (audit D-0917 items 1 and 2) and of the
# `ci_annotations` function of tools/ci_api.sh. Run as `python3 -I tools/test_verdict_read.py` (or tools/test_verdict_read.sh).
#
# SAVED real answers: tools/fixtures/verdict_read/ (the runs of one commit, the jobs of its battery run, the annotations of
# that run's `Verdict table` job). Every other case is built here from the same shapes, in a temp directory: caught /
# survived / equivalent rows, a NO VERDICT row of a cancelled job, a failed job, a VOID battery, a pending one, a second
# jobs page, the download retry, annotations cut (the log is the fallback), the budget, the cache, the gate set, the
# ledger merge, and the landing checks on a throwaway git repository. No case reaches the network: the answers come
# through LOGICKERNEL_CI_FIXTURE_DIR and a fake `curl` on PATH leaves a mark that fails the run when it is called.
# Both sides of every guard: a clean battery and a blocked one, an owner and none, a D-entry and none, each landing check
# passing and failing. Strong terms of the D-0164 grep are assembled from pieces, so this file does not match its own grep.
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.dirname(HERE)
TOOL = os.path.join(HERE, "verdict_read.py")
FIX = os.path.join(HERE, "fixtures", "verdict_read")
REAL_SHA = "24ee66ab14cfc1e243b5a55ccc964dde96035222"
TERM = "cra" "sh"
sys.path.insert(0, HERE)


def sh(cwd, *args, env=None):
    e = dict(os.environ)
    e.update({"GIT_AUTHOR_NAME": "A One", "GIT_AUTHOR_EMAIL": "a@x.test", "GIT_COMMITTER_NAME": "A One",
              "GIT_COMMITTER_EMAIL": "a@x.test", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull})
    e.update(env or {})
    r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, env=e)
    assert r.returncode == 0, (args, r.stderr)
    return r.stdout.strip()


class World:
    """A throwaway repository (with the two files the tool sources), a fixture directory, a cache, a fake curl."""

    def __init__(self, testcase):
        self.dir = tempfile.mkdtemp(prefix="verdict_read_test.")
        testcase.addCleanup(shutil.rmtree, self.dir, True)
        self.repo = os.path.join(self.dir, "repo")
        self.fix = os.path.join(self.dir, "fix")
        self.cache = os.path.join(self.dir, "cache")
        self.bin = os.path.join(self.dir, "bin")
        self.mark = os.path.join(self.dir, "net_mark")
        for d in (self.repo, self.fix, self.bin, os.path.join(self.repo, "tools", "githooks"), os.path.join(self.repo, "src")):
            os.makedirs(d, exist_ok=True)
        shutil.copy(os.path.join(HERE, "ci_api.sh"), os.path.join(self.repo, "tools"))
        shutil.copy(os.path.join(HERE, "githooks", "dterm.sh"), os.path.join(self.repo, "tools", "githooks"))
        with open(os.path.join(self.bin, "curl"), "w") as f:
            f.write('#!/usr/bin/env bash\necho "curl called" >> "%s"\nexit 7\n' % self.mark)
        os.chmod(os.path.join(self.bin, "curl"), 0o755)
        sh(self.repo, "init", "-q", "-b", "main")
        self.write("src/a.jl", "a = 1\n")
        sh(self.repo, "add", "-A")
        sh(self.repo, "commit", "-q", "-m", "base")
        self.base = sh(self.repo, "rev-parse", "HEAD")
        sh(self.repo, "checkout", "-q", "-b", "feat")               # main stays at the base: the landing diff is main..SHA
        self.n = 0
        self.runs = []
        self.sha = self.base

    def write(self, rel, text):
        p = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)

    def commit(self, rel, text, msg, env=None):
        self.write(rel, text)
        sh(self.repo, "add", "-A")
        sh(self.repo, "commit", "-q", "-m", msg, env=env)
        self.sha = sh(self.repo, "rev-parse", "HEAD")
        return self.sha

    def nid(self):
        self.n += 1
        return 9000000 + self.n

    # --- the saved answers ---------------------------------------------------------------------------------
    def put(self, rel, obj):
        p = os.path.join(self.fix, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            if isinstance(obj, str):
                f.write(obj)
            else:
                json.dump(obj, f)

    def flush_runs(self):
        self.put("runs_%s.json" % self.sha, {"total_count": len(self.runs), "workflow_runs": self.runs})

    def other_run(self, name, conclusion="success", status="completed", branch="gate/x"):
        r = {"id": self.nid(), "name": name, "head_branch": branch, "head_sha": self.sha, "status": status,
             "conclusion": conclusion, "run_attempt": 1, "created_at": "2026-11-18T10:00:00Z"}
        self.runs.append(r)
        return r

    def battery(self, name, rows, base="success", verdict_job=True, extra_steps=None, split=None, parts=None,
                mutant_jobs=None, run_status="completed", created="2026-11-18T10:00:00Z", log=None, jobs_pages=None):
        """rows: (id, verdict, what). A battery run with its jobs and annotation parts; returns the run dict."""
        run = {"id": self.nid(), "name": "Mutation battery", "head_branch": "mutants/" + name, "head_sha": self.sha,
               "status": run_status, "conclusion": "success" if run_status == "completed" else None, "run_attempt": 1,
               "created_at": created}
        self.runs.append(run)
        jobs = [dict(id=self.nid(), name="Plan", status="completed", conclusion="success", steps=[])]
        jobs.append(dict(id=self.nid(), name="Baseline (unmutated)", status="completed" if base != "running" else "in_progress",
                         conclusion=None if base == "running" else base, steps=[]))
        for rid, _, _ in rows:
            jobs.append(dict(id=self.nid(), name=rid, status="completed", conclusion="success", steps=[]))
        for j in (mutant_jobs or []):
            jobs = [x for x in jobs if x["name"] != j["name"]] + [j]
        if verdict_job:
            steps = [dict(number=1, name="Set up job", status="completed", conclusion="success")] + (extra_steps or [])
            jobs.append(dict(id=self.nid(), name="Verdict table", status="completed", conclusion="success", steps=steps))
        run["jobs"] = jobs
        if jobs_pages:
            for page, js in jobs_pages(jobs).items():
                self.put("%d/jobs_%d.json" % (run["id"], page), js)
        else:
            self.put("%d/jobs_1.json" % run["id"], {"total_count": len(jobs), "jobs": jobs})
        table = ["## Mutation battery — tools/mutants/%s.py" % name, "Baseline (unmutated targets): **green**, 100 s",
                 "| mutant | verdict | time | what it breaks | first failing test line |", "|---|---|---|---|---|"]
        for rid, verdict, what in rows:
            table.append("| %s | %s | 12 s | %s | [reached 3 times] |" % (rid, verdict, what))
        blocking = [rid for rid, v, _ in rows if not v.startswith("caught") and v != "EQUIVALENT (declared)"]
        decided = len(rows) - len(blocking)
        summary = "**%d of %d decided; blocking: %s**" % (decided, len(rows), ", ".join(blocking) or "none")
        vj = jobs[-1] if verdict_job else None
        if vj:
            if parts is None:
                parts = [table + [summary]]
            self.put("%d/ann_%d.json" % (run["id"], vj["id"]), [
                dict(path=".github", annotation_level="notice", title="verdicts %d/%d" % (j, len(parts)), message="\n".join(p))
                for j, p in enumerate(parts, 1)])
            if log:
                self.put("%d/%d.log" % (run["id"], vj["id"]), log)
        return run

    # --- the call -------------------------------------------------------------------------------------------
    def run(self, *args, cache=True, sha=None):
        self.flush_runs()
        env = dict(os.environ)
        env["LOGICKERNEL_CI_FIXTURE_DIR"] = self.fix
        env["PATH"] = self.bin + os.pathsep + env["PATH"]
        cmd = [sys.executable, "-I", TOOL, sha or self.sha, "--root", self.repo, "--base", "main"]
        if cache:
            cmd += ["--cache", self.cache]
        r = subprocess.run(cmd + list(args), capture_output=True, text=True, env=env, cwd=self.dir)
        assert not os.path.exists(self.mark), "a case reached the network"
        return r.returncode, r.stdout + r.stderr


def survivors(world, rows):
    p = os.path.join(world.repo, "evidence", "survivors.tsv")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write("battery\tmutant\towner\tstatus\td_entry\tfirst_seen\tlast_seen\n")
        for r in rows:
            f.write("\t".join(r) + "\n")


def equivalents(world, rows):
    p = os.path.join(world.repo, "evidence", "equivalents.tsv")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write("mutant\td_entry\tcase_analysis\n")
        for r in rows:
            f.write("\t".join(r) + "\n")


class RealShapes(unittest.TestCase):
    """The saved answers of the real battery run 44353157006 (ENG1D4: one declared equivalent)."""

    def world(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        shutil.copytree(os.path.join(FIX, "44353157006"), os.path.join(w.fix, "44353157006"))
        with open(os.path.join(FIX, "runs_%s.json" % REAL_SHA)) as f:
            runs = json.load(f)
        for r in runs["workflow_runs"]:
            r["head_sha"] = w.sha
        w.put("runs_%s.json" % w.sha, runs)
        w.flush_runs = lambda: None
        return w

    def test_real_equivalent_with_a_d_entry_is_clean(self):
        w = self.world()
        equivalents(w, [("ENG1-D4", "D-0911", "src/pl-tabling.jl")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertIn("BLOCKERS: none", out)
        self.assertRegex(out, r"ENG1D4\s+44353157006\s+1/1\s+0\s+0\s+0\s+0\s+0\s+0\s+1/1\s+clean")
        self.assertIn("ENG1-D4 D-0911 src/pl-tabling.jl", out)
        self.assertIn("API requests 3", out)

    def test_real_equivalent_without_a_d_entry_blocks_first(self):
        w = self.world()
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 1, out)
        first = out.splitlines()[2]
        self.assertTrue(first.strip().startswith("NO D-ENTRY ENG1D4 ENG1-D4"), first)
        self.assertIn("(src/pl-tabling.jl)", first)
        self.assertRegex(out, r"ENG1D4\s+44353157006\s+1/1.*0/1\s+BLOCKED")


class Batteries(unittest.TestCase):
    def test_all_caught_is_clean_and_landable_json(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B1", [("B1-1", "caught", "one"), ("B1-2", "caught (hang)", "two")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"B1\s+\d+\s+2/2\s+2\s+0\s+0\s+0\s+0\s+0\s+0/0\s+clean")
        rc, js = w.run("--no-landing", "--json")
        self.assertEqual(rc, 0, js)
        self.assertTrue(json.loads(js)["landable"])

    def test_survivor_blocks_and_has_no_owner_first(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B2", [("B2-1", "caught", "one"), ("B2-2", "SURVIVED", "the survivor"), ("B2-3", "TIMEOUT", "the hang")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 1, out)
        lines = out.splitlines()
        self.assertTrue(lines[2].strip().startswith("NO OWNER   B2 B2-2"), lines[2])
        self.assertIn("NO OWNER   B2 B2-3 (TIMEOUT)", out)
        self.assertLess(out.index("NO OWNER"), out.index("BATTERY"))
        self.assertRegex(out, r"B2\s+\d+\s+1/3\s+1\s+1\s+1\s+0\s+0\s+0\s+0/0\s+BLOCKED")
        rc, js = w.run("--no-landing", "--json")
        self.assertFalse(json.loads(js)["landable"])
        self.assertEqual(rc, 1)

    def test_an_owner_in_the_ledger_removes_the_no_owner_line_not_the_block(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B2", [("B2-1", "caught", "one"), ("B2-2", "SURVIVED", "the survivor")])
        survivors(w, [("B2", "B2-2", "S9", "open", "", "aaaa", "aaaa")])
        rc, out = w.run("--no-landing")
        self.assertNotIn("NO OWNER", out)
        self.assertIn("BLOCKERS: none", out)               # no person-blocker line: the survivor still blocks the row
        self.assertRegex(out, r"B2\s+\d+\s+1/2.*BLOCKED")
        self.assertEqual(rc, 1)

    def test_equivalent_declared_with_a_d_entry_both_sides(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B3", [("B3-1", "caught", "one"), ("B3-E", "EQUIVALENT (declared)", "declared equivalent, pending audit: src/pl-x.jl:12-14")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 1, out)
        self.assertIn("NO D-ENTRY B3 B3-E declared equivalent, not in evidence/equivalents.tsv (src/pl-x.jl:12-14)", out)
        equivalents(w, [("B3-E", "D-0999", "src/pl-x.jl:12-14")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertIn("B3-E D-0999 src/pl-x.jl:12-14", out)
        self.assertRegex(out, r"B3\s+\d+\s+2/2.*1/1\s+clean")

    def test_no_verdict_of_a_cancelled_job_names_the_step(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        steps = [dict(number=1, name="Set up job", status="completed", conclusion="success"),
                 dict(number=12, name="Run the mutant tests", status="in_progress", conclusion=None)]
        jid = w.nid()
        w.battery("B4", [("B4-1", "caught", "one"), ("B4-2", "NO VERDICT (no failing test)", "cancelled")],
                  mutant_jobs=[dict(id=jid, name="B4-2", status="completed", conclusion="cancelled", steps=steps)])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 1, out)
        self.assertIn("NO VERDICT B4 B4-2: job %d cancelled step 12 'Run the mutant tests' started, no completion" % jid, out)
        self.assertEqual(out.count("B4-2 %d" % jid), 0, "a NO VERDICT row carries its job record once, not as a JOB line")
        self.assertRegex(out, r"B4\s+\d+\s+1/2\s+1\s+0\s+0\s+0\s+1\s+0")

    def test_a_failed_job_without_a_row_is_a_job_blocker(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        steps = [dict(number=3, name="Checkout", status="completed", conclusion="failure")]
        jid = w.nid()
        w.battery("B5", [("B5-1", "caught", "one"), ("B5-2", "caught", "two")],
                  mutant_jobs=[dict(id=jid, name="B5-2", status="completed", conclusion="failure", steps=steps)])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 1, out)
        self.assertIn("JOB B5: B5-2 %d conclusion failure step 3 'Checkout' failure" % jid, out)

    def test_baseline_failure_makes_the_battery_void(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B6", [("B6-1", "caught", "one")], base="failure", verdict_job=False)
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 2, out)
        self.assertIn("VOID B6 run", out)
        self.assertRegex(out, r"B6\s+\d+\s+-\s+VOID")

    def test_a_running_baseline_is_pending_exit_3(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B7", [("B7-1", "caught", "one")], base="running", verdict_job=False, run_status="in_progress")
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 3, out)
        self.assertRegex(out, r"B7\s+\d+\s+-\s+PENDING")

    def test_pagination_reads_the_second_jobs_page(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        rows = [("B8-%d" % i, "caught", "m%d" % i) for i in range(1, 149)]

        def pages(jobs):
            return {1: {"total_count": len(jobs), "jobs": jobs[:100]}, 2: {"total_count": len(jobs), "jobs": jobs[100:]}}
        w.battery("B8", rows, jobs_pages=pages)
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"B8\s+\d+\s+148/148\s+148")           # the Verdict table job sits on page 2
        self.assertIn("API requests 4", out)                          # runs, jobs 1, jobs 2, annotations

    def test_download_retry_is_a_note_not_a_failure(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        dl = "Run actions/download-artifact@abc"
        steps = [dict(number=3, name=dl, status="completed", conclusion="failure"),
                 dict(number=4, name=dl, status="completed", conclusion="success")]
        w.battery("B9", [("B9-1", "caught", "one")], extra_steps=steps)
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertIn("note: download retried (digest-mismatch retry), succeeded", out)

    def test_download_failing_every_try_is_noted(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        dl = "Run actions/download-artifact@abc"
        steps = [dict(number=3, name=dl, status="completed", conclusion="failure"),
                 dict(number=4, name=dl, status="completed", conclusion="failure")]
        w.battery("B9", [("B9-1", "caught", "one")], extra_steps=steps)
        rc, out = w.run("--no-landing")
        self.assertIn("download FAILED (every try)", out)
        import verdict_read as vr
        self.assertEqual(vr.download_note({"steps": []}), "")

    def test_cut_annotations_fall_back_to_the_job_log(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        head = ["## Mutation battery — tools/mutants/B10.py", "Baseline (unmutated targets): **green**, 100 s",
                "| mutant | verdict | time | what it breaks | first failing test line |", "|---|---|---|---|---|"]
        rows = ["| B10-1 | caught | 12 s | one | [reached 3 times] |", "| B10-2 | caught | 12 s | two | [reached 3 times] |"]
        log = "\n".join("2026-11-18T10:00:00.0000000Z " + ln for ln in head + rows + ["**2 of 2 decided; blocking: none**"]) + "\n"
        w.battery("B10", [("B10-1", "caught", "one"), ("B10-2", "caught", "two")],
                  parts=[head + rows[:1]], log=log)                    # one part, no summary line: cut
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertIn("note: table read from the job log (annotations cut or empty)", out)
        self.assertRegex(out, r"B10\s+\d+\s+2/2\s+2")

    def test_budget_and_cache(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B11", [("B11-1", "caught", "one")])
        rc, out = w.run("--no-landing", "--budget", "1")
        self.assertEqual(rc, 2, out)
        self.assertIn("REFUSED by budget", out)
        self.assertIn("NOT READ", out)
        rc, out = w.run("--no-landing")                                # fills the cache (completed run)
        self.assertIn("API requests 3, cache hits 0", out)
        rc, out = w.run("--no-landing")
        self.assertIn("API requests 1, cache hits 2", out)             # only the runs of the commit are asked again
        self.assertEqual(rc, 0, out)

    def test_unresolvable_sha_is_exit_2_and_bad_usage_64(self):
        w = World(self)
        rc, out = w.run("--no-landing", sha="0" * 40)
        self.assertEqual(rc, 2, out)
        self.assertIn("does not resolve to a commit", out)
        rc, _ = w.run("--no-such-flag")
        self.assertEqual(rc, 64)


class GateSet(unittest.TestCase):
    def test_set_complete_only_when_every_name_has_a_clean_run_or_a_clean_read(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("S1", [("S1-1", "caught", "one")])
        w.battery("S2", [("S2-1", "SURVIVED", "s")])
        gs = os.path.join(w.dir, "set.txt")
        with open(gs, "w") as f:
            f.write("# set: T\nS1\nS3 deadbeef\nS4\n")
        rc, out = w.run("--no-landing", "--set", gs)
        self.assertIn("S1         clean at SHA", out)
        self.assertIn("S3         no run at SHA; last clean read at deadbeef", out)
        self.assertIn("S4         no run at SHA; last clean read at none", out)
        self.assertIn("set complete at the SHA: NO (no run and no clean read: S4)", out)
        with open(gs, "w") as f:
            f.write("S1\nS3 deadbeef\n")
        rc, out = w.run("--no-landing", "--set", gs)
        self.assertIn("set complete at the SHA: yes", out)
        with open(gs, "w") as f:
            f.write("S1\nS2\n")
        rc, out = w.run("--no-landing", "--set", gs)
        self.assertIn("set complete at the SHA: NO (not clean: S2)", out)
        rc, js = w.run("--no-landing", "--set", gs, "--json")
        self.assertFalse(json.loads(js)["landable"])
        rc, out = w.run("--no-landing", "--set", os.path.join(w.dir, "nowhere.txt"))
        self.assertEqual(rc, 2, out)


class Ledger(unittest.TestCase):
    def text(self, w):
        with open(os.path.join(w.repo, "evidence", "survivors.tsv")) as f:
            return f.read()

    def read(self, w):
        rows = {}
        for ln in self.text(w).splitlines():
            if ln.startswith("#") or ln.startswith("battery\t"):
                continue
            f = ln.split("\t")
            rows[f[1]] = f
        return rows

    def test_merge_keeps_rows_and_human_fields_and_moves_last_seen(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("L1", [("L1-1", "caught", "one"), ("L1-2", "SURVIVED", "two"), ("L1-3", "SURVIVED", "three")])
        survivors(w, [("L1", "L1-2", "OWNER1", "candidate equivalent", "D-0900", "oldsha", "oldsha"),
                      ("L0", "L0-9", "OWN0", "open", "", "oldsha", "oldsha")])
        rc, out = w.run("--no-landing", "--ledger")
        rows = self.read(w)
        self.assertIn("ledger evidence/survivors.tsv: 3 rows (1 new, 1 last_seen moved)", out)
        self.assertEqual(rows["L1-2"][2:5], ["OWNER1", "candidate equivalent", "D-0900"])   # nothing a human wrote moves
        self.assertEqual(rows["L1-2"][5:], ["oldsha", w.sha[:8]])                          # first_seen stays, last_seen moves
        self.assertEqual(rows["L1-3"][2:5], ["", "open", ""])
        self.assertEqual(rows["L1-3"][5], w.sha[:8])
        self.assertEqual(rows["L0-9"][6], "oldsha")                                         # a row not read here is kept
        rc, out = w.run("--no-landing", "--ledger")
        self.assertIn("(0 new, 0 last_seen moved)", out)

    def test_set_row_sets_a_field_and_refuses_a_bad_status(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("L1", [("L1-3", "SURVIVED", "three")])
        rc, out = w.run("--no-landing", "--ledger", "--set-row", "L1-3", "owner=S7", "--set-row", "L1-3", "status=fresh proof")
        self.assertEqual(self.read(w)["L1-3"][2:4], ["S7", "fresh proof"])
        before = self.text(w)
        rc, out = w.run("--no-landing", "--ledger", "--set-row", "L1-3", "status=bogus")
        self.assertNotEqual(rc, 0)
        self.assertIn("status must be one of", out)
        self.assertEqual(self.text(w), before)
        rc, out = w.run("--no-landing", "--ledger", "--set-row", "L9-9", "owner=x")
        self.assertIn("no ledger row of mutant L9-9", out)
        rc, out = w.run("--no-landing", "--set-row", "L1-3", "color=red")
        self.assertEqual(rc, 64, out)

    def test_an_open_ledger_row_that_is_caught_now_is_listed(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("L2", [("L2-1", "caught", "one"), ("L2-2", "caught", "two")])
        survivors(w, [("L2", "L2-1", "O", "open", "", "a", "a"), ("L2", "L2-2", "O", "fresh proof", "", "a", "a")])
        rc, out = w.run("--no-landing")
        self.assertIn("LEDGER rows now CAUGHT here (set the status): L2-1", out)
        self.assertNotIn("L2-1, L2-2", out)


class Landing(unittest.TestCase):
    def landed(self, w):
        w.other_run("CI")
        w.other_run("Evidence (three term types)")

    def test_all_checks_ok_is_landable(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: a tools file\n\nbody")
        self.landed(w)
        rc, out = w.run()
        self.assertEqual(rc, 0, out)
        for name in ("src diff: empty", "D-0164 term grep: clean", "ancestry: main is an ancestor", "authors: 1 commits; author: A One",
                     "CI at the SHA: success", "Evidence (three term types) at the SHA: success"):
            self.assertIn(name, out)
        self.assertNotIn("FAIL", out)
        rc, js = w.run("--json")
        d = json.loads(js)
        self.assertTrue(d["landable"])
        self.assertTrue(all(x["ok"] for x in d["landing"]))
        self.assertEqual([x["check"] for x in d["landing"]], ["src diff", "D-0164 term grep", "ancestry", "authors"])

    def test_a_src_diff_fails(self):
        w = World(self)
        w.commit("src/a.jl", "a = 2\n", "CHANGED: src")
        self.landed(w)
        rc, out = w.run()
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL src diff: NON-EMPTY: 1 file changed.*src/a.jl")
        rc, js = w.run("--json")
        self.assertFalse(json.loads(js)["landable"])

    def test_a_strong_term_in_a_message_or_an_added_line_fails(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: t\n\nthe run ends in a %s" % TERM)
        self.landed(w)
        rc, out = w.run()
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL D-0164 term grep: 1 hit lines: .*%s" % TERM)
        w2 = World(self)
        w2.commit("tools/t.txt", "a line about a %s\n" % TERM, "ADDED: t\n\nclean message")
        self.landed(w2)
        rc, out = w2.run()
        self.assertRegex(out, r"FAIL D-0164 term grep: 1 hit lines")

    def test_an_allowlisted_token_alone_is_not_a_hit(self):
        w = World(self)
        w.commit("tools/t.txt", "the token %s%s is a name\n" % ("abo", "rted"), "ADDED: t")
        self.landed(w)
        rc, out = w.run()
        self.assertIn("ok   D-0164 term grep: clean", out)

    def test_a_non_ancestor_fails(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: t")
        sh(w.repo, "checkout", "-q", "-b", "other", w.base)
        w.commit("tools/u.txt", "y\n", "ADDED: u")
        sh(w.repo, "checkout", "-q", "main")
        w.commit("tools/v.txt", "z\n", "ADDED: v")            # this commit is on main now                      # main moved on: the SHA on `other` is not a descendant
        sha = sh(w.repo, "rev-parse", "other")
        w.sha = sha
        self.landed(w)
        rc, out = w.run(sha=sha)
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL ancestry: main is NOT an ancestor of")

    def test_two_authors_fail(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: t")
        w.commit("tools/u.txt", "y\n", "ADDED: u", env={"GIT_AUTHOR_NAME": "B Two", "GIT_AUTHOR_EMAIL": "b@x.test",
                                                         "GIT_COMMITTER_NAME": "B Two", "GIT_COMMITTER_EMAIL": "b@x.test"})
        self.landed(w)
        rc, out = w.run()
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL authors: 2 commits; authors: A One <a@x.test>; B Two <b@x.test>; committers:")

    def test_a_missing_ci_or_evidence_run_fails(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: t")
        w.other_run("CI")
        w.other_run("Evidence (three term types)", conclusion="failure")
        rc, out = w.run()
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL Evidence (three term types) at the SHA: no green run", out)
        self.assertIn("ok   CI at the SHA: success", out)

    def test_a_pending_run_is_exit_3_even_when_the_checks_pass(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: t")
        self.landed(w)
        w.other_run("Other", conclusion=None, status="in_progress")
        rc, out = w.run()
        self.assertEqual(rc, 3, out)
        rc, js = w.run("--json")
        self.assertFalse(json.loads(js)["landable"])


class Units(unittest.TestCase):
    def test_table_from_annotations_orders_the_parts_and_needs_the_summary(self):
        import verdict_read as vr
        a = [dict(title="verdicts 2/2", message="| r2 | caught | 1 s | w | x |\n**2 of 2 decided; blocking: none**"),
             dict(title="verdicts 1/2", message="| r1 | caught | 1 s | w | x |"), dict(title="other", message="q")]
        lines, complete = vr.table_from_annotations(a)
        self.assertEqual(lines[0][:6], "| r1 |")
        self.assertTrue(complete)
        _, complete = vr.table_from_annotations(a[:1])
        self.assertFalse(complete)
        self.assertEqual(vr.table_from_annotations([]), ([], False))

    def test_classify(self):
        import verdict_read as vr
        got = {v: vr.classify(v) for v in ("caught", "caught (hang)", "SURVIVED", "TIMEOUT", "INVALID", "BADMATCH",
                                           "EQUIVALENT (declared)", "EQUIVALENT REFUTED", "NO VERDICT (does not load)")}
        self.assertEqual(got, {"caught": "caught", "caught (hang)": "caught", "SURVIVED": "surv", "TIMEOUT": "tmo",
                               "INVALID": "inv", "BADMATCH": "err", "EQUIVALENT (declared)": "eqv",
                               "EQUIVALENT REFUTED": "err", "NO VERDICT (does not load)": "nov"})

    def test_eq_path(self):
        import verdict_read as vr
        self.assertEqual(vr.eq_path("x, declared equivalent, pending audit: src/pl-tabling.jl `f` reads"), "src/pl-tabling.jl")
        self.assertEqual(vr.eq_path("see src/os/pl-libtai.jl:66-73 here"), "src/os/pl-libtai.jl:66-73")
        self.assertEqual(vr.eq_path("no path"), "")

    def test_seed_files_are_well_formed(self):
        import verdict_read as vr
        eq = vr.load_equivalents(os.path.join(REAL, "evidence", "equivalents.tsv"))
        self.assertGreaterEqual(len(eq), 20)
        self.assertTrue(all(re.fullmatch(r"D-\d{4}", r["d_entry"]) and r["case_analysis"].startswith("src/") for r in eq.values()))
        led = vr.load_ledger(os.path.join(REAL, "evidence", "survivors.tsv"))
        self.assertGreaterEqual(len(led), 60)
        self.assertTrue(all(r["status"] in vr.STATES and r["owner"] for r in led.values()))
        gs = vr.read_gate_set(os.path.join(REAL, "evidence", "gate_set.txt"))
        self.assertEqual(len(gs), 26)
        self.assertTrue(all(re.fullmatch(r"[0-9a-f]{8}|", c) for _, c in gs))

    def test_load_equivalents_refuses_a_row_without_a_d_entry(self):
        # D-0992: both tables non-empty, read through the ONE extractor (load_equivalents); only the D-entry of one row differs
        import verdict_read as vr
        d = tempfile.mkdtemp(prefix="verdict_read_eq.")
        self.addCleanup(shutil.rmtree, d, True)

        def table(entry):
            p = os.path.join(d, "eq_%s.tsv" % re.sub(r"\W", "_", entry or "empty"))
            with open(p, "w") as f:
                f.write("# c\nmutant\td_entry\tcase_analysis\nX-1\tD-0903\tsrc/pl-a.jl:1\nLD6-9\t%s\tsrc/os/pl-stream.jl Ssize\n" % entry)
            return p

        with self.assertRaises(ValueError) as cm:                        # (a) a `pending` row is refused, the message names it
            vr.load_equivalents(table("pending"))
        self.assertIn("LD6-9", str(cm.exception))
        self.assertIn("pending", str(cm.exception))
        for bad in ("", "D-12", "see D-0992", "d-0992"):                 # empty, short, free text, lower case: refused too
            with self.assertRaises(ValueError, msg=bad):
                vr.load_equivalents(table(bad))
        ok = vr.load_equivalents(table("D-0992"))                        # (b) the same table, ratified: accepted, both rows
        self.assertEqual(sorted(ok), ["LD6-9", "X-1"])
        self.assertEqual(ok["LD6-9"]["d_entry"], "D-0992")
        shipped = vr.load_equivalents(os.path.join(REAL, "evidence", "equivalents.tsv"))   # (c) the shipped file loads, non-empty,
        self.assertGreaterEqual(len(shipped), 20)                                         # and holds the two ratified rows
        self.assertEqual({k: shipped[k]["d_entry"] for k in ("LD6-2", "LD6-3")}, {"LD6-2": "D-0992", "LD6-3": "D-0992"})

    def test_the_entry_point_refuses_an_unratified_equivalents_row(self):
        # the verdict level: tools/verdict_read.py itself exits 2 naming the row; the ratified table passes the same gate
        w = World(self)
        w.commit("tools/t.txt", "x\n", "tools only")
        w.battery("B3", [("B3-E", "EQUIVALENT (declared)", "src/pl-x.jl:12-14")])
        equivalents(w, [("B3-E", "pending", "src/pl-x.jl:12-14")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 2, out)
        self.assertIn("equivalents row B3-E", out)
        equivalents(w, [("B3-E", "D-0992", "src/pl-x.jl:12-14")])
        rc, out = w.run("--no-landing")
        self.assertEqual(rc, 0, out)
        self.assertIn("B3-E D-0992 src/pl-x.jl:12-14", out)

    def test_ci_annotations_seam(self):
        w = World(self)
        w.put("77/ann_5.json", [{"title": "t"}])
        env = dict(os.environ, LOGICKERNEL_CI_FIXTURE_DIR=w.fix, PATH=w.bin + os.pathsep + os.environ["PATH"])
        run = lambda *a: subprocess.run(["bash", "-c", '. "$1/tools/ci_api.sh"; ci_annotations "$2" "$3"', "bash", w.repo] + list(a),
                                        capture_output=True, text=True, env=env).stdout
        self.assertEqual(json.loads(run("5", "77")), [{"title": "t"}])
        self.assertEqual(json.loads(run("6", "77")), [])               # no saved file: an empty list


if __name__ == "__main__":
    unittest.main(verbosity=1)
