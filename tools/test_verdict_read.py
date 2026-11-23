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
import hashlib
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
TOOL = os.environ.get("VERDICT_READ_UNDER_TEST") or os.path.join(HERE, "verdict_read.py")   # tools/mutate_land_check.sh points it at a mutated copy
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
        self.assertRegex(out, r"FAIL src diff: NON-EMPTY, no `src-diff <sha256>` release; sha256 [0-9a-f]{64}; numstat.*1 1 src/a.jl")
        rc, js = w.run("--json")
        self.assertFalse(json.loads(js)["landable"])

    # --- D-1006 (2): a named src-diff release ------------------------------------------------------------------
    def src_world(self):
        w = World(self)
        w.commit("src/a.jl", "a = 2\nb = 3\n", "CHANGED: src")
        self.landed(w)
        raw = subprocess.run(["git", "-C", w.repo, "diff", "--numstat", "main.." + w.sha, "--", "src"], capture_output=True).stdout
        self.assertEqual(raw, b"2\t1\tsrc/a.jl\n")          # the bytes the dispatcher hashes: `git diff --numstat ... | sha256sum`
        return w, hashlib.sha256(raw).hexdigest(), raw

    def rel(self, w, *tokens):
        return "LAND %s [ids: %s]" % (w.sha, ",".join(tokens))

    def test_a_matching_src_diff_release_passes(self):
        w, dig, _ = self.src_world()
        rc, out = w.run("--release", self.rel(w, "src-diff " + dig))
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"ok   src diff: NON-EMPTY, released by src-diff " + dig)
        self.assertIn("2 1 src/a.jl", out)                                         # the numstat is printed
        self.assertIn("sha256 " + dig, out)
        rc, js = w.run("--json", "--release", self.rel(w, "D-0950:X", "src-diff " + dig))   # beside an equivalents id
        self.assertTrue(json.loads(js)["landable"])

    def test_a_changed_numstat_fails_by_one_byte(self):
        w, dig, raw = self.src_world()
        other = hashlib.sha256(raw.replace(b"2\t1", b"3\t1")).hexdigest()           # one byte of the numstat differs
        self.assertNotEqual(other, dig)
        rc, out = w.run("--release", self.rel(w, "src-diff " + other))
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL src diff: NON-EMPTY, the release names src-diff " + other)
        self.assertIn("sha256 " + dig, out)                                         # the audit sees the tool's own digest
        last = dig[:-1] + ("0" if dig[-1] != "0" else "1")                           # and one hex digit of the release
        rc, out = w.run("--release", self.rel(w, "src-diff " + last))
        self.assertEqual(rc, 1, out)
        rc, js = w.run("--json", "--release", self.rel(w, "src-diff " + other))
        self.assertFalse(json.loads(js)["landable"])

    def test_a_missing_src_diff_release_fails(self):
        w, dig, _ = self.src_world()
        rc, out = w.run()
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL src diff: NON-EMPTY, no `src-diff <sha256>` release; sha256 " + dig)
        rc, out = w.run("--release", self.rel(w, "D-0950:X"))                         # a release that names ids only
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--release", "LAND %s" % w.sha)                               # a bare LAND
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--release", "src-diff " + dig)                               # the digest outside the ids list is no release
        self.assertEqual(rc, 1, out)

    def test_a_malformed_src_diff_release_fails(self):
        w, dig, _ = self.src_world()
        for bad in (dig.upper(), dig[:63], dig + "0", "zz" + dig[2:], ""):
            rc, out = w.run("--release", self.rel(w, "src-diff " + bad))
            self.assertEqual(rc, 1, (bad, out))
            self.assertRegex(out, r"FAIL src diff: NON-EMPTY, malformed release token")
        rc, out = w.run("--release", self.rel(w, "src-diff" + dig))                  # no space
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--release", self.rel(w, "src-diff " + dig, "src-diff " + dig))   # two tokens are one too many
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--release", self.rel(w, "src-diff " + dig, "src-diff " + "0" * 64))
        self.assertEqual(rc, 1, out)

    def test_an_empty_src_diff_passes_without_a_release(self):
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: a tools file")
        self.landed(w)
        rc, out = w.run()
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   src diff: empty", out)

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


class LocalVerdict(unittest.TestCase):
    """D-1009 (5), LAND-TOOL-2: `local: <row id> @<A-entry ref>` in the release lifts a cap-cancelled battery row."""

    def landed(self, w):
        w.other_run("CI")
        w.other_run("Evidence (three term types)")

    REF = "A-NEXT 2026-11-23 15:40Z"

    def local_world(self, rows=None, conclusion="cancelled", job_only=False, extra_jobs=()):
        """A landable commit whose battery G1GC3 has a job G1GC3-T3 that concluded `conclusion` (a NO VERDICT row of it, or no row)."""
        w = World(self)
        w.commit("tools/t.txt", "x\n", "ADDED: a tools file")
        self.landed(w)
        steps = [dict(number=1, name="Set up job", status="completed", conclusion="success"),
                 dict(number=12, name="Apply the mutant and run the targets", status="in_progress", conclusion=None)]
        jobs = [dict(id=w.nid(), name="G1GC3-T3", status="completed", conclusion=conclusion, steps=steps)] + list(extra_jobs)
        if rows is None:
            rows = [("G1GC3-T1", "caught", "one")] + ([] if job_only else [("G1GC3-T3", "NO VERDICT (no failing test)", "hung")])
        w.battery("G1GC3", rows, mutant_jobs=jobs)
        return w

    def tree(self, w):
        return sh(w.repo, "rev-parse", w.sha + "^{tree}")

    def lv(self, w, row="G1GC3-T3", tree=None, word="caught (hang)", site="pl-gc.c:1234"):
        return "LOCAL VERDICT %s tree %s %s site %s" % (row, tree or self.tree(w), word, site)

    def channel(self, w, *lines, head=None, name="agent.md"):
        """A channel file: an earlier entry, then the entry headed `head` (default REF + a title) holding `lines`, then a later one."""
        path = os.path.join(w.dir, name)
        with open(path, "w") as f:
            f.write("# agent\n\n## A-NEXT 2026-11-23 13:00Z - earlier\nno verdict here\n\n## %s\n%s\n\n## A-NEXT 2026-11-23 16:00Z - later\n" % (
                head or (self.REF + " \u2014 local verdict"), "\n".join(lines)))
        return path

    def lrel(self, w, *items):
        return "LAND %s [ids: %s]" % (w.sha, ",".join(items))

    ITEM = "local: G1GC3-T3 @" + REF

    def test_a_matching_local_verdict_releases_a_cancelled_row(self):
        w = self.local_world()
        ch = self.channel(w, "  " + self.lv(w))                                        # leading blanks allowed
        rc, out = w.run("--channel", ch)                                               # no release: the row blocks
        self.assertEqual(rc, 1, out)
        self.assertIn("NO VERDICT G1GC3 G1GC3-T3", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 0, out)
        self.assertRegex(out, r"ok   local verdict G1GC3-T3: G1GC3-T3 released: cap-cancelled in G1GC3, local verdict caught \(hang\) at tree "
                              + self.tree(w) + r", site pl-gc.c:1234")
        self.assertNotIn("NO VERDICT G1GC3 G1GC3-T3:", out)
        self.assertIn("released by a local verdict", out)
        rc, js = w.run("--json", "--channel", ch, "--release", self.lrel(w, self.ITEM))
        d = json.loads(js)
        self.assertTrue(d["landable"])
        self.assertEqual(d["released"], ["G1GC3 G1GC3-T3"])
        self.assertEqual([x["check"] for x in d["landing"]][-1], "local verdict G1GC3-T3")
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "local: G1GC3-T3 @A-NEXT 2026-11-23 15:40Z"))  # the same, spelled out
        self.assertEqual(rc, 0, out)
        # beside a D-entry id and an A-NNNN ref
        ch2 = self.channel(w, self.lv(w), head="A-0777 \u2014 x", name="agent2.md")
        rc, out = w.run("--channel", ch2, "--release", self.lrel(w, "D-0950:X", "local: G1GC3-T3 @A-0777"))
        self.assertEqual(rc, 0, out)
        ch3 = self.channel(w, self.lv(w), head="A-0777", name="agent3.md")             # a heading that is the ref alone
        rc, out = w.run("--channel", ch3, "--release", self.lrel(w, "local: G1GC3-T3 @A-0777"))
        self.assertEqual(rc, 0, out)

    def test_a_failed_job_with_no_row_is_released_the_same_way(self):
        w = self.local_world(job_only=True)
        ch = self.channel(w, self.lv(w))
        rc, out = w.run("--channel", ch)
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"JOB G1GC3: G1GC3-T3 \d+ conclusion cancelled step 12 'Apply the mutant and run the targets'")
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 0, out)
        self.assertNotIn("JOB G1GC3", out)
        self.assertIn("ok   local verdict G1GC3-T3", out)

    def test_a_wrong_tree_fails(self):
        w = self.local_world()
        tr = self.tree(w)
        other = tr[:-1] + ("0" if tr[-1] != "0" else "1")                              # one hex digit off
        ch = self.channel(w, self.lv(w, tree=other))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL local verdict G1GC3-T3: no usable `LOCAL VERDICT G1GC3-T3 tree " + tr)
        self.assertIn("tree %s is not the landing SHA's %s" % (other, tr), out)
        self.assertIn("NO VERDICT G1GC3 G1GC3-T3", out)                                # the row still blocks
        ch = self.channel(w, self.lv(w, tree=w.sha))                                   # the COMMIT sha is not the tree sha
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        rc, js = w.run("--json", "--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertFalse(json.loads(js)["landable"])

    def test_a_missing_channel_entry_or_line_fails(self):
        w = self.local_world()
        rc, out = w.run("--channel", os.path.join(w.dir, "no_such_agent.md"), "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertRegex(out, r"FAIL local verdict G1GC3-T3: the channel file .*no_such_agent.md cannot be read \(fail closed\)")
        ch = self.channel(w, self.lv(w), head="A-NEXT 2026-11-23 15:41Z - other minute")
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL local verdict G1GC3-T3: the channel file has no entry headed `%s`" % self.REF, out)
        ch = self.channel(w, "nothing to see")                                         # the entry exists, no line
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertIn("no such line", out)
        ch = self.channel(w, self.lv(w, row="G1GC3-T4"))                               # a line for another row
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        ch = self.channel(w, "x", head="A-01234 \u2014 x")                              # A-0123 is no prefix match of A-01234
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "local: G1GC3-T3 @A-0123"))
        self.assertEqual(rc, 1, out)
        self.assertIn("no entry headed `A-0123`", out)
        path = os.path.join(w.dir, "scoped.md")                                        # the line sits under a LATER entry
        with open(path, "w") as f:
            f.write("## %s \u2014 x\nnothing\n\n## A-NEXT 2026-11-23 16:00Z - later\n%s\n" % (self.REF, self.lv(w)))
        rc, out = w.run("--channel", path, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertIn("no such line", out)

    def test_a_verdict_word_other_than_caught_hang_fails(self):
        w = self.local_world()
        for word in ("TIMEOUT", "SURVIVED", "caught", "caught (hang", "Caught (hang)", "caught (error)"):
            ch = self.channel(w, self.lv(w, word=word))
            rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
            self.assertEqual(rc, 1, (word, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
            self.assertIn("not `caught (hang)`", out)
        ch = self.channel(w, self.lv(w, word="TIMEOUT"), self.lv(w))                    # one good line beside a bad one releases
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 0, out)

    def test_only_a_blocking_cap_cancelled_row_can_be_released(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w, row="G1GC3-T1"), self.lv(w, row="G1GC3-T9"))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "local: G1GC3-T1 @" + self.REF))   # a caught row: not blocked
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL local verdict G1GC3-T1: G1GC3-T1 is not exactly one blocking cap-cancelled NO VERDICT row: G1GC3: the row is caught", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "local: G1GC3-T9 @" + self.REF))   # a row that does not exist
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL local verdict G1GC3-T9: G1GC3-T9 is no blocking row or job of any battery read here", out)
        # SURVIVED (and TIMEOUT) rows, whatever their job concluded, even `cancelled`: a verdict is not a cap cancellation
        for verdict in ("SURVIVED", "TIMEOUT", "INVALID"):
            w = self.local_world(rows=[("G1GC3-T1", "caught", "one"), ("G1GC3-T3", verdict, "x")])
            ch = self.channel(w, self.lv(w))
            rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
            self.assertEqual(rc, 1, (verdict, out))
            self.assertIn("FAIL local verdict G1GC3-T3: G1GC3-T3 is not exactly one blocking cap-cancelled NO VERDICT row: G1GC3: the row is %s, not NO VERDICT" % verdict, out)
        # a NO VERDICT row of a job that FAILED (not cancelled), with a row and without
        for kw in ({}, {"job_only": True}):
            w = self.local_world(conclusion="failure", **kw)
            ch = self.channel(w, self.lv(w))
            rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
            self.assertEqual(rc, 1, (kw, out))
            self.assertRegex(out, r"FAIL local verdict G1GC3-T3: .*not cancelled")

    def test_two_local_items_are_each_checked(self):
        t4 = dict(id=9100001, name="G1GC3-T4", status="completed", conclusion="cancelled", steps=[])
        w = self.local_world(rows=[("G1GC3-T1", "caught", "one"), ("G1GC3-T3", "NO VERDICT (x)", "h"), ("G1GC3-T4", "NO VERDICT (x)", "h")],
                             extra_jobs=[t4])
        both = self.channel(w, self.lv(w), self.lv(w, row="G1GC3-T4", site="pl-gc.c:99"))
        two = self.lrel(w, self.ITEM, "local: G1GC3-T4 @" + self.REF)
        rc, out = w.run("--channel", both, "--release", two)
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   local verdict G1GC3-T3", out)
        self.assertIn("ok   local verdict G1GC3-T4", out)
        rc, out = w.run("--channel", both, "--release", self.lrel(w, self.ITEM))        # one named: the other still blocks
        self.assertEqual(rc, 1, out)
        self.assertIn("NO VERDICT G1GC3 G1GC3-T4", out)
        self.assertNotIn("NO VERDICT G1GC3 G1GC3-T3:", out)
        only3 = self.channel(w, self.lv(w))                                            # both named, one line missing: one ok, one FAIL
        rc, out = w.run("--channel", only3, "--release", two)
        self.assertEqual(rc, 1, out)
        self.assertIn("ok   local verdict G1GC3-T3", out)
        self.assertIn("FAIL local verdict G1GC3-T4", out)
        self.assertIn("NO VERDICT G1GC3 G1GC3-T4", out)
        self.assertNotIn("NO VERDICT G1GC3 G1GC3-T3:", out)
        bad4 = self.channel(w, self.lv(w), self.lv(w, row="G1GC3-T4", word="TIMEOUT"))  # the other way: T4's word is wrong
        rc, out = w.run("--channel", bad4, "--release", two)
        self.assertEqual(rc, 1, out)
        self.assertIn("ok   local verdict G1GC3-T3", out)
        self.assertIn("FAIL local verdict G1GC3-T4", out)

    def test_a_row_id_cancelled_in_two_batteries_is_ambiguous(self):
        w = self.local_world()
        steps = [dict(number=12, name="Apply the mutant and run the targets", status="in_progress", conclusion=None)]
        w.battery("G1GC4", [("G1GC3-T3", "NO VERDICT (x)", "h")],
                  mutant_jobs=[dict(id=w.nid(), name="G1GC3-T3", status="completed", conclusion="cancelled", steps=steps)])
        ch = self.channel(w, self.lv(w))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL local verdict G1GC3-T3: G1GC3-T3 is not exactly one blocking cap-cancelled NO VERDICT row: 2 such rows", out)

    def test_a_malformed_local_item_or_line_fails(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w))
        for bad in ("local: G1GC3-T3", "local: G1GC3-T3 @", "local: G1GC3-T3 @bogus", "local:G1GC3-T3 @A-0123", "local G1GC3-T3 @A-0123",
                    "local: G1GC3-T3 @A-NEXT 2026-11-23", "local: G1GC3-T3 @A-12", "local: @A-0123", "local: G1GC3-T3 @A-NEXT 2026-11-23 15:40"):
            rc, out = w.run("--channel", ch, "--release", self.lrel(w, bad))
            self.assertEqual(rc, 1, (bad, out))
            self.assertIn("FAIL local verdict: malformed item(s) " + bad, out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM, "local: G1GC3-T3 @A-0123"))   # one row twice
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL local verdict G1GC3-T3: the release names G1GC3-T3 twice", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM, "local: oops"))              # a good item and a bad one
        self.assertEqual(rc, 1, out)
        self.assertIn("malformed item(s) local: oops", out)
        tr = self.tree(w)
        for line in ("LOCAL VERDICT G1GC3-T3 tree %s caught (hang)" % tr,                 # no site
                     "LOCAL VERDICT G1GC3-T3 tree %s caught (hang) site " % tr,           # empty site
                     "LOCAL VERDICT G1GC3-T3 tree %s site pl.c:1" % tr,                   # no verdict word
                     "LOCAL VERDICT G1GC3-T3 tree %s caught (hang) site a b" % tr,        # the site is one identifier
                     "LOCAL VERDICT G1GC3-T3 tree %s caught (hang) site pl.c:1" % tr[:39],   # a 39-digit tree
                     "LOCAL VERDICT G1GC3-T3 tree %s caught (hang) site pl.c:1" % tr.upper(),
                     "LOCAL VERDICT G1GC3-T3 %s caught (hang) site pl.c:1" % tr):         # no `tree` word
            ch = self.channel(w, line)
            rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))
            self.assertEqual(rc, 1, (line, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)

    def test_local_and_src_diff_releases_work_together_and_alone(self):
        w = World(self)
        w.commit("src/a.jl", "a = 2\nb = 3\n", "CHANGED: src")
        self.landed(w)
        raw = subprocess.run(["git", "-C", w.repo, "diff", "--numstat", "main.." + w.sha, "--", "src"], capture_output=True).stdout
        dig = hashlib.sha256(raw).hexdigest()
        steps = [dict(number=12, name="Apply the mutant and run the targets", status="in_progress", conclusion=None)]
        w.battery("G1GC3", [("G1GC3-T3", "NO VERDICT (x)", "h")],
                  mutant_jobs=[dict(id=w.nid(), name="G1GC3-T3", status="completed", conclusion="cancelled", steps=steps)])
        ch = self.channel(w, self.lv(w))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "src-diff " + dig, self.ITEM))
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   src diff: NON-EMPTY, released by src-diff " + dig, out)
        self.assertIn("ok   local verdict G1GC3-T3", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))              # the local item does not release the src diff
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL src diff: NON-EMPTY, no `src-diff <sha256>` release", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, "src-diff " + dig))      # nor the src-diff the cancelled row
        self.assertEqual(rc, 1, out)
        self.assertIn("NO VERDICT G1GC3 G1GC3-T3", out)
        self.assertNotIn("local verdict", out)                                              # no item, no check row

    # ---- LAND-TOOL-3 (audit D-1012 (3)): the status route, the tree-ruling form, the two sources together ------------------------
    def statuses(self, w, desc, login="AuditBot", state="success", ctx="land/local/G1GC3-T3", name="status.json"):
        """The answer of commits/<sha>/status with one land/local status (and an unrelated one), as land_check.sh saves it."""
        path = os.path.join(w.dir, name)
        with open(path, "w") as f:
            json.dump({"state": state, "sha": w.sha, "statuses": [
                {"context": "other/thing", "state": "success", "description": "x", "creator": {"login": "AuditBot"}},
                {"context": ctx, "state": state, "description": desc, "creator": {"login": login}}]}, f)
        return path

    def approvers(self, w, *logins, name="land_approvers.txt"):
        path = os.path.join(w.dir, name)
        with open(path, "w") as f:
            f.write("# the approvers\n" + "".join(l + "\n" for l in logins))
        return path

    def auditfile(self, w, *dids, name="audit.md"):
        path = os.path.join(w.dir, name)
        with open(path, "w") as f:
            f.write("# audit\n\n" + "".join("## %s (audit, scheduled) - a ruling\nbody mentions D-9999 here\n\n" % d for d in dids))
        return path

    FOREIGN = "a" * 40

    def stat_args(self, w, desc, login="AuditBot", state="success", approvers=True, **kw):
        a = ["--statuses", self.statuses(w, desc, login=login, state=state, **kw)]
        return a + (["--approvers", self.approvers(w, "AuditBot", "Other-Approver")] if approvers else [])

    def test_a_land_local_status_releases_a_cancelled_row_without_a_channel_line(self):
        w = self.local_world()
        nochan = os.path.join(w.dir, "no_such_agent.md")
        st = self.stat_args(w, self.lv(w))
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM))              # no status given: the row blocks
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM), *st)
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   local verdict G1GC3-T3: G1GC3-T3 released: cap-cancelled in G1GC3, local verdict caught (hang) at tree %s" % self.tree(w), out)
        self.assertIn("(status, land/local/G1GC3-T3)", out)
        rc, js = w.run("--json", "--channel", nochan, "--release", self.lrel(w, self.ITEM), *st)
        self.assertEqual(rc, 0, js)
        self.assertEqual(json.loads(js)["released"], ["G1GC3 G1GC3-T3"])
        ch = self.channel(w, "nothing to see")                                                 # an entry with no line: the status releases
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM), *st)
        self.assertEqual(rc, 0, out)

    def test_either_source_alone_and_both_agreeing_release(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))                  # the channel alone (LAND-TOOL-2)
        self.assertEqual(rc, 0, out)
        self.assertIn("(channel, %s)" % self.REF, out)
        st = self.stat_args(w, self.lv(w))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM), *st)              # both, the same tree and word
        self.assertEqual(rc, 0, out)
        st2 = self.stat_args(w, self.lv(w, site="other.c:9"))                                    # another SITE is no disagreement
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM), *st2)
        self.assertEqual(rc, 0, out)

    def test_a_status_of_a_stranger_or_not_success_or_malformed_does_not_release(self):
        w = self.local_world()
        nochan = os.path.join(w.dir, "no_such_agent.md")
        for kw, want in (({"login": "stranger"}, "not in land_approvers.txt"), ({"state": "pending"}, "is pending, not success"),
                         ({"state": "failure"}, "is failure, not success")):
            rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM), *self.stat_args(w, self.lv(w), **kw))
            self.assertEqual(rc, 1, (kw, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
            self.assertIn(want, out)
        for desc in ("LOCAL VERDICT G1GC3-T3 tree %s caught (hang)" % self.tree(w), "LOCAL VERDICT G1GC3-T1 tree %s caught (hang) site x" % self.tree(w),
                     "verdict ok"):
            rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM), *self.stat_args(w, desc))
            self.assertEqual(rc, 1, (desc, out))
            self.assertIn("description is malformed", out)
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM),              # the status of ANOTHER row's context
                        *self.stat_args(w, self.lv(w), ctx="land/local/G1GC3-T1"))
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM),              # a status of another context family
                        *self.stat_args(w, self.lv(w), ctx="land/approved"))
        self.assertEqual(rc, 1, out)

    def test_the_status_route_fails_closed_without_its_inputs(self):
        w = self.local_world()
        nochan = os.path.join(w.dir, "no_such_agent.md")
        item = self.lrel(w, self.ITEM)
        path = self.statuses(w, self.lv(w))
        ap = self.approvers(w, "AuditBot")
        empty = self.approvers(w, name="empty_approvers.txt")
        for args in ((), ("--statuses", path), ("--approvers", ap), ("--statuses", path, "--approvers", empty),            # no approvers file / none named
                     ("--statuses", path, "--approvers", os.path.join(w.dir, "no_such_approvers.txt")),
                     ("--statuses", os.path.join(w.dir, "no_such_status.json"), "--approvers", ap)):
            rc, out = w.run("--channel", nochan, "--release", item, *args)
            self.assertEqual(rc, 1, (args, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
        bad = os.path.join(w.dir, "garbage.json")
        with open(bad, "w") as f:
            f.write("this is not json")
        rc, out = w.run("--channel", nochan, "--release", item, "--statuses", bad, "--approvers", ap)
        self.assertEqual(rc, 1, out)
        self.assertIn("unreadable", out)

    def test_a_status_tree_that_differs_needs_a_tree_ruling_that_exists(self):
        w = self.local_world()
        nochan = os.path.join(w.dir, "no_such_agent.md")
        foreign = self.stat_args(w, self.lv(w, tree=self.FOREIGN))
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM), *foreign)     # a wrong tree, no ruling
        self.assertEqual(rc, 1, out)
        self.assertIn("tree %s is not the landing SHA's %s" % (self.FOREIGN, self.tree(w)), out)
        self.assertIn("no tree-ruling named", out)
        ruled = self.ITEM + " tree-ruling D-1010"
        audit = self.auditfile(w, "D-1010", "D-1011")
        rc, out = w.run("--channel", nochan + os.pathsep + audit, "--release", self.lrel(w, ruled), *foreign)   # `:`-joined files
        self.assertEqual(rc, 0, out)
        self.assertIn("(ruling D-1010: landing tree %s)" % self.tree(w), out)
        rc, out = w.run("--channel", nochan, "--channel", audit, "--release", self.lrel(w, ruled), *foreign)    # repeated flag
        self.assertEqual(rc, 0, out)
        other = self.auditfile(w, "D-1011", "D-9999", name="audit2.md")                             # D-9999 is only text in the body
        rc, out = w.run("--channel", nochan, "--channel", other, "--release", self.lrel(w, ruled), *foreign)
        self.assertEqual(rc, 1, out)
        self.assertIn("names tree-ruling D-1010, but the channel has no heading `## D-1010`", out)
        rc, out = w.run("--channel", nochan, "--release", self.lrel(w, ruled), *foreign)           # no channel at all: no D-entry
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--channel", nochan, "--channel", other, "--release",                       # the ruling is named, the D-entry missing, the tree is EQUAL
                        self.lrel(w, ruled), *self.stat_args(w, self.lv(w)))
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--channel", nochan, "--channel", audit, "--release",                       # equal tree plus an existing ruling: fine
                        self.lrel(w, ruled), *self.stat_args(w, self.lv(w)))
        self.assertEqual(rc, 0, out)
        rc, out = w.run("--channel", nochan, "--channel", audit, "--release", self.lrel(w, ruled),  # a ruling does not excuse another verdict word
                        *self.stat_args(w, self.lv(w, tree=self.FOREIGN, word="TIMEOUT")))
        self.assertEqual(rc, 1, out)
        self.assertIn("not `caught (hang)`", out)

    def test_the_channel_line_takes_the_same_ruling_form(self):
        w = self.local_world()
        audit = self.auditfile(w, "D-1010")
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM))                   # LAND-TOOL-2 behaviour kept: refused
        self.assertEqual(rc, 1, out)
        self.assertIn("not the landing SHA's", out)
        rc, out = w.run("--channel", ch, "--channel", audit, "--release", self.lrel(w, self.ITEM + " tree-ruling D-1010"))
        self.assertEqual(rc, 0, out)
        self.assertIn("(channel, %s)" % self.REF, out)

    def test_sources_that_disagree_fail(self):
        w = self.local_world()
        audit = self.auditfile(w, "D-1010")
        ch = self.channel(w, self.lv(w))
        for desc, want in ((self.lv(w, word="TIMEOUT"), "DISAGREE"), (self.lv(w, tree=self.FOREIGN), "DISAGREE")):
            rc, out = w.run("--channel", ch, "--channel", audit, "--release", self.lrel(w, self.ITEM + " tree-ruling D-1010"),
                            *self.stat_args(w, desc))
            self.assertEqual(rc, 1, (desc, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
            self.assertIn(want, out)
        ch2 = self.channel(w, self.lv(w, word="TIMEOUT"), name="agent2.md")                                         # the channel bad, the status good: disagree too
        rc, out = w.run("--channel", ch2, "--release", self.lrel(w, self.ITEM), *self.stat_args(w, self.lv(w)))
        self.assertEqual(rc, 1, out)
        self.assertIn("DISAGREE", out)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM),                    # a stranger's status is ignored, not a disagreement
                        *self.stat_args(w, self.lv(w, word="TIMEOUT"), login="stranger"))
        self.assertEqual(rc, 0, out)

    def test_a_status_verdict_word_other_than_caught_hang_fails(self):
        w = self.local_world()
        nochan = os.path.join(w.dir, "no_such_agent.md")
        for word in ("TIMEOUT", "survived", "caught", "Caught (hang)"):
            rc, out = w.run("--channel", nochan, "--release", self.lrel(w, self.ITEM), *self.stat_args(w, self.lv(w, word=word)))
            self.assertEqual(rc, 1, (word, out))
            self.assertIn("not `caught (hang)`", out)

    def test_a_malformed_tree_ruling_item_fails(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w))
        audit = self.auditfile(w, "D-1010")
        for bad in (self.ITEM + " tree-ruling", self.ITEM + " tree-ruling D-10", self.ITEM + " tree-ruling d-1010", self.ITEM + " tree-ruling D-1010 x",
                    self.ITEM + " ruling D-1010", self.ITEM + " tree-ruling D-10100"):
            rc, out = w.run("--channel", ch, "--channel", audit, "--release", self.lrel(w, bad))
            self.assertEqual(rc, 1, (bad, out))
            self.assertIn("FAIL local verdict: malformed item(s)", out)

    # ---- LAND-TOOL-3b (audit D-1013 (1)): a `land/ruling/D-NNNN` status stands for the D-entry heading ------------------------------
    def rstatuses(self, w, *specs, name="rstatus.json"):
        """The answer of commits/<sha>/status with the given (context, state, login, description) statuses, plus an unrelated one."""
        path = os.path.join(w.dir, name)
        with open(path, "w") as f:
            json.dump({"state": "success", "sha": w.sha, "statuses": [
                {"context": "other/thing", "state": "success", "description": "x", "creator": {"login": "AuditBot"}}] + [
                {"context": c, "state": st, "description": d, "creator": {"login": lg}} for c, st, lg, d in specs]}, f)
        return path

    def rargs(self, w, ctx="land/ruling/D-1010", state="success", login="AuditBot", desc="D-1010 (audit): a ruling title", **kw):
        return ["--statuses", self.rstatuses(w, (ctx, state, login, desc), **kw), "--approvers", self.approvers(w, "AuditBot", "Other-Approver")]

    def test_a_land_ruling_status_releases_the_tree_ruling_without_an_audit_heading(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))                                       # the channel line, a foreign tree, no D heading anywhere
        ruled = self.lrel(w, self.ITEM + " tree-ruling D-1010")
        rc, out = w.run("--channel", ch, "--release", ruled)
        self.assertEqual(rc, 1, out)
        self.assertIn("no heading `## D-1010` and no usable land/ruling/D-1010 status", out)
        rc, out = w.run("--channel", ch, "--release", ruled, *self.rargs(w))
        self.assertEqual(rc, 0, out)
        self.assertIn("(ruling D-1010: landing tree %s)" % self.tree(w), out)
        self.assertIn("(channel, %s)" % self.REF, out)
        nochan = os.path.join(w.dir, "no_such_agent.md")                                         # both the verdict and the ruling by status
        rc, out = w.run("--channel", nochan, "--release", ruled, *self.stat_args(w, self.lv(w, tree=self.FOREIGN)),
                        "--statuses", self.rstatuses(w, ("land/local/G1GC3-T3", "success", "AuditBot", self.lv(w, tree=self.FOREIGN)),
                                                     ("land/ruling/D-1010", "success", "AuditBot", "t"), name="both.json"))
        self.assertEqual(rc, 0, out)                                                              # (the later --statuses wins; the approvers stay)
        rc, out = w.run("--channel", ch, "--release", self.lrel(w, self.ITEM + " tree-ruling D-1010"),   # an EQUAL tree, a ruling named: still needs one
                        *self.rargs(w, ctx="land/ruling/D-1011"))
        self.assertEqual(rc, 1, out)

    def test_the_land_ruling_description_is_irrelevant(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))
        ruled = self.lrel(w, self.ITEM + " tree-ruling D-1010")
        for desc in ("", "x", "LOCAL VERDICT nonsense", "D-9999 something else entirely", "a" * 300):
            rc, out = w.run("--channel", ch, "--release", ruled, *self.rargs(w, desc=desc))
            self.assertEqual(rc, 0, (desc, out))

    def test_a_land_ruling_status_of_a_stranger_or_not_success_or_missing_does_not_release(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))
        ruled = self.lrel(w, self.ITEM + " tree-ruling D-1010")
        for kw, want in (({"login": "stranger"}, "not in land_approvers.txt"), ({"state": "pending"}, "is pending, not success"),
                         ({"state": "failure"}, "is failure, not success"), ({"state": "error"}, "is error, not success")):
            rc, out = w.run("--channel", ch, "--release", ruled, *self.rargs(w, **kw))
            self.assertEqual(rc, 1, (kw, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
            self.assertIn("names tree-ruling D-1010, but the channel has no heading `## D-1010` and no usable land/ruling/D-1010 status: ", out)
            self.assertIn(want, out)
        for ctx in ("land/ruling/D-1011", "land/ruling/D-10100", "land/ruling/", "land/local/D-1010", "land/approved", "land/ruling/d-1010"):
            rc, out = w.run("--channel", ch, "--release", ruled, *self.rargs(w, ctx=ctx))
            self.assertEqual(rc, 1, (ctx, out))
        rc, out = w.run("--channel", ch, "--release", ruled,                                     # the creator check is case-blind as for land/approved
                        "--statuses", self.rstatuses(w, ("land/ruling/D-1010", "success", "AUDITBOT", "t")),
                        "--approvers", self.approvers(w, "auditbot"))
        self.assertEqual(rc, 0, out)
        rc, out = w.run("--channel", ch, "--release", ruled,                                     # a status with no creator at all
                        "--statuses", self.rstatuses(w, ("land/ruling/D-1010", "success", "", "t")), "--approvers", self.approvers(w, "AuditBot"))
        self.assertEqual(rc, 1, out)

    def test_the_land_ruling_route_fails_closed_without_its_inputs(self):
        w = self.local_world()
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))
        ruled = self.lrel(w, self.ITEM + " tree-ruling D-1010")
        path = self.rstatuses(w, ("land/ruling/D-1010", "success", "AuditBot", "t"))
        ap = self.approvers(w, "AuditBot")
        empty = self.approvers(w, name="empty_approvers.txt")
        for args in ((), ("--statuses", path), ("--approvers", ap), ("--statuses", path, "--approvers", empty),
                     ("--statuses", path, "--approvers", os.path.join(w.dir, "no_such_approvers.txt")),
                     ("--statuses", os.path.join(w.dir, "no_such_status.json"), "--approvers", ap)):
            rc, out = w.run("--channel", ch, "--release", ruled, *args)
            self.assertEqual(rc, 1, (args, out))
            self.assertIn("FAIL local verdict G1GC3-T3", out)
        bad = os.path.join(w.dir, "garbage.json")
        with open(bad, "w") as f:
            f.write("this is not json")
        rc, out = w.run("--channel", ch, "--release", ruled, "--statuses", bad, "--approvers", ap)
        self.assertEqual(rc, 1, out)
        self.assertIn("land/ruling/D-1010 status: the status route is closed: the statuses or the approvers file is unreadable", out)
        notlist = os.path.join(w.dir, "notdict.json")                                            # valid JSON that is not the status answer
        with open(notlist, "w") as f:
            f.write("[1, 2]")
        rc, out = w.run("--channel", ch, "--release", ruled, "--statuses", notlist, "--approvers", ap)
        self.assertEqual(rc, 1, out)

    def test_land_ruling_and_the_audit_heading_together(self):
        w = self.local_world()
        audit = self.auditfile(w, "D-1010")
        ch = self.channel(w, self.lv(w, tree=self.FOREIGN))
        ruled = self.lrel(w, self.ITEM + " tree-ruling D-1010")
        rc, out = w.run("--channel", ch, "--channel", audit, "--release", ruled, *self.rargs(w))                  # both present: released
        self.assertEqual(rc, 0, out)
        for kw in ({"login": "stranger"}, {"state": "failure"}, {"ctx": "land/ruling/D-1011"}):               # a refused status beside a heading: no disagreement
            rc, out = w.run("--channel", ch, "--channel", audit, "--release", ruled, *self.rargs(w, **kw))
            self.assertEqual(rc, 0, (kw, out))
        rc, out = w.run("--channel", ch, "--channel", audit, "--release", ruled,                                # a ruling status never rescues the VERDICT's disagreement
                        *self.stat_args(w, self.lv(w, word="TIMEOUT")))
        self.assertEqual(rc, 1, out)
        self.assertIn("DISAGREE", out)
        nochan = os.path.join(w.dir, "no_such_agent.md")                                                      # no verdict line anywhere: the ruling alone releases nothing
        rc, out = w.run("--channel", nochan, "--release", ruled, *self.rargs(w))
        self.assertEqual(rc, 1, out)
        self.assertIn("cannot be read", out)
        rc, out = w.run("--channel", ch, "--release", ruled, *self.stat_args(w, self.lv(w, tree=self.FOREIGN, word="TIMEOUT")))   # a ruling excuses no other word
        self.assertEqual(rc, 1, out)


class StandItem(unittest.TestCase):
    """LAND-TOOL-3 (audit D-1012 (2)): `stand: <LIST> @D-NNNN from <old sha>` lets an old-SHA battery result stand at the landing SHA."""

    def world(self, lists=("TB5", "TB7")):
        """old = a commit holding src/a.jl and the mutant lists; the landing SHA = old + a tools-only commit, CI + Evidence + battery TB4 at it."""
        w = World(self)
        for n in lists:
            w.commit("tools/mutants/%s.py" % n, "# list %s\n" % n, "ADDED: list " + n)
        self.old = w.sha
        w.commit("tools/x.txt", "x\n", "ADDED: a tools file")
        w.other_run("CI")
        w.other_run("Evidence (three term types)")
        w.battery("TB4", [("TB4-1", "caught", "one")])
        return w

    def gate(self, w, *names):
        p = os.path.join(w.dir, "gate_set.txt")
        with open(p, "w") as f:
            f.write("# the gate set\n" + "".join(n + "\n" for n in names))
        return p

    def audit(self, w, *dids):
        p = os.path.join(w.dir, "audit.md")
        with open(p, "w") as f:
            f.write("# audit\n\n" + "".join("## %s (audit, scheduled) - a ruling\nthe body names D-9999 only as text\n\n" % d for d in dids))
        return p

    def rel(self, w, *items):
        return "LAND %s [ids: %s]" % (w.sha, ",".join(items))

    def item(self, lst="TB5", did="D-1012", old=None):
        return "stand: %s @%s from %s" % (lst, did, old or self.old)

    def go(self, w, rel, names=("TB4", "TB5", "TB7"), dids=("D-1012",), extra=()):
        return w.run("--set", self.gate(w, *names), "--channel", self.audit(w, *dids), "--release", rel, *extra)

    def test_an_unchanged_old_battery_stands_and_the_set_is_complete(self):
        w = self.world()
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")))
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   stand TB5: TB5 stands: src and tools/mutants/TB5.py unchanged since %s, D-1012 exists" % self.old[:8], out)
        self.assertIn("ok   stand TB7", out)
        self.assertIn("STANDS by D-1012 from %s" % self.old, out)
        rc, js = w.run("--json", "--set", self.gate(w, "TB4", "TB5", "TB7"), "--channel", self.audit(w, "D-1012"),
                       "--release", self.rel(w, self.item("TB5"), self.item("TB7")))
        self.assertEqual(rc, 0, js)
        d = json.loads(js)
        self.assertEqual(d["stood"], {"TB5": ["D-1012", self.old], "TB7": ["D-1012", self.old]})
        self.assertTrue(d["gate_complete"] and d["landable"])

    def test_without_an_item_the_old_battery_is_uncovered(self):
        w = self.world()
        rc, out = self.go(w, self.rel(w, self.item("TB5")))                                      # TB7 has no item
        self.assertEqual(rc, 1, out)
        self.assertIn("no run and no clean read: TB7", out)
        rc, out = self.go(w, "LAND %s" % w.sha)
        self.assertEqual(rc, 1, out)
        self.assertNotIn("stand TB5", out)

    def test_a_src_change_since_the_old_sha_refuses(self):
        w = self.world()
        w.commit("src/a.jl", "a = 2\n", "CHANGED: src")
        w.other_run("CI")
        w.other_run("Evidence (three term types)")
        w.battery("TB4", [("TB4-1", "caught", "one")])
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")), extra=("--base", "main"))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: git diff --stat %s %s -- src tools/mutants/TB5.py is NOT empty" % (self.old[:8], w.sha[:8]), out)
        self.assertIn("src/a.jl", out)

    def test_a_change_of_the_list_file_refuses_but_another_list_changing_does_not(self):
        w = self.world()
        w.commit("tools/mutants/TB7.py", "# list TB7 edited\n", "CHANGED: another list")
        w.other_run("CI")
        w.other_run("Evidence (three term types)")
        w.battery("TB4", [("TB4-1", "caught", "one")])
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB7: git diff --stat", out)
        self.assertIn("tools/mutants/TB7.py", out)
        self.assertIn("ok   stand TB5", out)                                                      # TB5's own list file is untouched

    def test_the_d_entry_must_exist_as_a_heading(self):
        w = self.world()
        rc, out = self.go(w, self.rel(w, self.item("TB5", "D-1013"), self.item("TB7", "D-1013")), dids=("D-1012",))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: the channel has no heading `## D-1013`", out)
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")), dids=("D-1011",))   # D-1012 appears only as text in no heading
        self.assertEqual(rc, 1, out)
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")), dids=("D-10120",))    # a longer id is no heading match
        self.assertEqual(rc, 1, out)
        rc, out = w.run("--set", self.gate(w, "TB4", "TB5", "TB7"), "--channel", os.path.join(w.dir, "nope.md"), "--release",
                        self.rel(w, self.item("TB5"), self.item("TB7")))                           # no channel file: fail closed
        self.assertEqual(rc, 1, out)
        self.assertIn("no heading", out)

    def test_malformed_items_fail(self):
        w = self.world()
        good = self.item("TB5")
        for bad in ("stand: TB5 @D-1012", "stand: TB5 @D-1012 from " + self.old[:39], "stand: TB5 @D-1012 from " + self.old.upper(),
                    "stand: TB5 @D-12 from " + self.old, "stand: TB5 D-1012 from " + self.old, "stand TB5 @D-1012 from " + self.old,
                    "stand: TB5 @A-0123 from " + self.old, "stand: TB5 @D-1012 from " + self.old + "0", "stand: @D-1012 from " + self.old):
            rc, out = self.go(w, self.rel(w, bad, self.item("TB7")))
            self.assertEqual(rc, 1, (bad, out))
            self.assertIn("FAIL stand: malformed item(s)", out)
            rc, out = self.go(w, self.rel(w, good, bad, self.item("TB7")))                          # a good item beside a bad one
            self.assertEqual(rc, 1, (bad, out))

    def test_a_list_twice_a_list_not_in_the_set_a_list_without_a_file_and_a_list_with_a_run_fail(self):
        w = self.world()
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB5", "D-1011"), self.item("TB7")), dids=("D-1011", "D-1012"))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: the release names TB5 twice", out)
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7"), self.item("TB9")))     # TB9 is in no gate set
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB9: TB9 is not in the gate set", out)
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7"), self.item("TB8")), names=("TB4", "TB5", "TB7", "TB8"))
        self.assertEqual(rc, 1, out)                                                                # TB8 is in the set but tools/mutants/TB8.py exists nowhere
        self.assertIn("FAIL stand TB8: tools/mutants/TB8.py does not exist", out)
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7"), self.item("TB4")))     # TB4 has a run at the landing SHA
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB4: TB4 has a battery run at the landing SHA", out)

    def test_an_old_sha_that_is_no_commit_fails(self):
        w = self.world()
        rc, out = self.go(w, self.rel(w, self.item("TB5", old="b" * 40), self.item("TB7")))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: the old SHA bbbbbbbb is not a commit", out)

    def test_a_stand_item_does_not_release_a_blocked_battery_or_a_src_diff(self):
        w = self.world()
        w.battery("TB5", [("TB5-1", "SURVIVED", "x")])                                              # TB5 HAS a run here, and it is blocked
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: TB5 has a battery run", out)
        self.assertIn("SURVIVED", out)

    # ---- LAND-TOOL-3b (audit D-1013 (1)): a `land/ruling/D-NNNN` status stands for the D-entry heading -------------------------------
    def rargs(self, w, did="D-1012", state="success", login="AuditBot", ctx=None, desc="a ruling title", approvers=True):
        p = os.path.join(w.dir, "rstatus.json")
        with open(p, "w") as f:
            json.dump({"state": "success", "sha": w.sha, "statuses": [
                {"context": "other/thing", "state": "success", "description": "x", "creator": {"login": "AuditBot"}},
                {"context": ctx or "land/ruling/" + did, "state": state, "description": desc, "creator": {"login": login}}]}, f)
        ap = os.path.join(w.dir, "land_approvers.txt")
        with open(ap, "w") as f:
            f.write("# the approvers\nAuditBot\nOther-Approver\n")
        return ["--statuses", p] + (["--approvers", ap] if approvers else [])

    def test_a_land_ruling_status_stands_for_the_d_entry_heading(self):
        w = self.world()
        rel = self.rel(w, self.item("TB5"), self.item("TB7"))
        rc, out = self.go(w, rel, dids=())                                                        # no heading, no status: refused
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB5: the channel has no heading `## D-1012` and no usable land/ruling/D-1012 status", out)
        rc, out = self.go(w, rel, dids=(), extra=self.rargs(w))
        self.assertEqual(rc, 0, out)
        self.assertIn("ok   stand TB5: TB5 stands: src and tools/mutants/TB5.py unchanged since %s, D-1012 exists (land/ruling/D-1012 status)" % self.old[:8], out)
        self.assertIn("ok   stand TB7", out)
        rc, js = w.run("--json", "--set", self.gate(w, "TB4", "TB5", "TB7"), "--channel", self.audit(w), "--release", rel, *self.rargs(w))
        self.assertEqual(rc, 0, js)
        d = json.loads(js)
        self.assertEqual(d["stood"], {"TB5": ["D-1012", self.old], "TB7": ["D-1012", self.old]})
        self.assertTrue(d["gate_complete"] and d["landable"])

    def test_the_land_ruling_description_is_irrelevant_to_a_stand_item(self):
        w = self.world()
        rel = self.rel(w, self.item("TB5"), self.item("TB7"))
        for desc in ("", "x", "LOCAL VERDICT nonsense", "D-1013 another title", "b" * 300):
            rc, out = self.go(w, rel, dids=(), extra=self.rargs(w, desc=desc))
            self.assertEqual(rc, 0, (desc, out))

    def test_a_land_ruling_status_of_a_stranger_or_not_success_or_missing_does_not_stand(self):
        w = self.world()
        rel = self.rel(w, self.item("TB5"), self.item("TB7"))
        for kw, want in (({"login": "stranger"}, "not in land_approvers.txt"), ({"state": "pending"}, "is pending, not success"),
                         ({"state": "failure"}, "is failure, not success")):
            rc, out = self.go(w, rel, dids=(), extra=self.rargs(w, **kw))
            self.assertEqual(rc, 1, (kw, out))
            self.assertIn("FAIL stand TB5: the channel has no heading `## D-1012` and no usable land/ruling/D-1012 status: ", out)
            self.assertIn(want, out)
            self.assertNotIn("ok   stand TB5", out)                                              # a refused D-entry leaves no ok row and no stood entry
            rc, js = w.run("--json", "--set", self.gate(w, "TB4", "TB5", "TB7"), "--channel", self.audit(w), "--release", rel, *self.rargs(w, **kw))
            self.assertEqual(json.loads(js)["stood"], {}, (kw, js))
        for ctx in ("land/ruling/D-1011", "land/ruling/D-10120", "land/local/D-1012", "land/approved"):
            rc, out = self.go(w, rel, dids=(), extra=self.rargs(w, ctx=ctx))
            self.assertEqual(rc, 1, (ctx, out))

    def test_the_land_ruling_route_fails_closed_offline(self):
        w = self.world()
        rel = self.rel(w, self.item("TB5"), self.item("TB7"))
        good = self.rargs(w)
        empty = os.path.join(w.dir, "empty_approvers.txt")
        with open(empty, "w") as f:
            f.write("# nobody\n")
        bad = os.path.join(w.dir, "garbage.json")
        with open(bad, "w") as f:
            f.write("this is not json")
        for extra in ((), good[:2], good[2:], ["--statuses", good[1], "--approvers", empty],
                      ["--statuses", good[1], "--approvers", os.path.join(w.dir, "no_such_approvers.txt")],
                      ["--statuses", os.path.join(w.dir, "no_such_status.json"), "--approvers", good[3]], ["--statuses", bad, "--approvers", good[3]]):
            rc, out = self.go(w, rel, dids=(), extra=tuple(extra))
            self.assertEqual(rc, 1, (extra, out))
            self.assertIn("FAIL stand TB5: the channel has no heading", out)

    def test_land_ruling_and_the_heading_together_and_mixed_per_list(self):
        w = self.world()
        rel = self.rel(w, self.item("TB5"), self.item("TB7"))
        rc, out = self.go(w, rel, extra=self.rargs(w))                                            # both: released, the heading's wording
        self.assertEqual(rc, 0, out)
        self.assertIn("D-1012 exists\n", out.replace("\r", ""))
        for kw in ({"login": "stranger"}, {"state": "failure"}, {"ctx": "land/ruling/D-1011"}):     # a refused status beside a heading is no disagreement
            rc, out = self.go(w, rel, extra=self.rargs(w, **kw))
            self.assertEqual(rc, 0, (kw, out))
        rel2 = self.rel(w, self.item("TB5", "D-1012"), self.item("TB7", "D-1013"))                # TB5 by the heading, TB7 by the status
        rc, out = self.go(w, rel2, dids=("D-1012",), extra=self.rargs(w, did="D-1013"))
        self.assertEqual(rc, 0, out)
        rc, out = self.go(w, rel2, dids=("D-1012",), extra=self.rargs(w, did="D-1011"))           # TB7's D-1013 has neither
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL stand TB7: the channel has no heading `## D-1013`", out)
        self.assertIn("ok   stand TB5", out)

    def test_a_land_ruling_status_does_not_mask_the_other_stand_checks(self):
        w = self.world()
        w.commit("src/a.jl", "a = 2\n", "CHANGED: src")
        w.other_run("CI")
        w.other_run("Evidence (three term types)")
        w.battery("TB4", [("TB4-1", "caught", "one")])
        rc, out = self.go(w, self.rel(w, self.item("TB5"), self.item("TB7")), dids=(), extra=self.rargs(w) + ["--base", "main"])
        self.assertEqual(rc, 1, out)                                                              # the status supplies the D-entry, not an empty diff
        self.assertIn("FAIL stand TB5: git diff --stat", out)
        w2 = self.world()
        rc, out = self.go(w2, self.rel(w2, self.item("TB5", old="b" * 40), self.item("TB7")), dids=(), extra=self.rargs(w2))
        self.assertEqual(rc, 1, out)
        self.assertIn("is not a commit", out)


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
