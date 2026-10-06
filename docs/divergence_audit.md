# The sampled divergence audit (2026-10-06)

The project owner asked for this audit (2026-10-06) once the four milestones were reached, before R1
adds a large new file. A sample of the kernel's `# DIVERGES` markers was re-read against upstream,
to find markers that are wrong or stale, and to classify them all. The classification shows how the
markers split overall: is the high divergence share a problem, or the cost of immutable terms and
slot positions?

## Method

* **Population.** Every `# DIVERGES` marker in `src/`: 336, in 28 files. Two backticked mentions
  of the marker in prose are not counted.
* **Sample.** 40 markers, stratified by file. Every file gives one, and the other ten go to files in
  proportion to their counts (`pl-wam.jl` gives four). The draw uses Python's
  `random.Random(20261006)`, so it can be reproduced.
* **Each marker** was re-read beside the code it annotates and beside upstream's code at
  `bae881a2`, and judged on five points:
  * **real:** does the code differ as the comment says?
  * **needed:** could it now follow upstream as is?
  * **reason:** is the stated reason accurate and complete?
  * **pinned:** does a test exercise the divergent behaviour?
  * **class**, one of:
    * FORCED: the representation requires it (immutable terms without cells or tagged words, slot
      positions instead of pointers, no atom or functor table);
    * PERFORMANCE;
    * EXTENSION: kernel-only features with no SWI counterpart;
    * INTERIM: a later step or a parked question removes it;
    * DEFECT-FIX;
    * OTHER.
* **Verdict:** JUSTIFIED, REWORD (the divergence is right but its comment is not), UNJUSTIFIED
  (the code should follow upstream) or MISSING-TEST.
* **How the work was done.** Four reviewers read ten markers each. Every negative finding was then
  re-checked against both sources before anything was changed.

## Results

* **Verdicts:**
  * JUSTIFIED: 18;
  * REWORD: 19;
  * MISSING-TEST: 3;
  * **UNJUSTIFIED: 0.**

  No marker hides code that could simply follow upstream.
* **Classes in the sample:** FORCED 25, OTHER 8, INTERIM 5, EXTENSION 2. There was no PERFORMANCE
  or DEFECT-FIX marker in the sample.
* **Over all 336** (each file weighted by its count):
  * FORCED about 68% (about 229 markers);
  * OTHER about 20%;
  * INTERIM about 8%;
  * EXTENSION about 3%.

  The sample's own FORCED share, 25/40, has a 95% interval of 47% to 76% (Wilson; one-marker
  strata make the weighted figure approximate).
* **The OTHER eight:**
  * subsystems the kernel has not ported and no step schedules: transactions, wrappers, threads'
    locks (4);
  * the no-module-level-state design rule (1);
  * code organisation, so the static gates can check the work (1);
  * markers that describe no divergence: a duplicate on a function that follows upstream, and an
    LP64 check that can never fire (2).

**Reading:** the divergence share is mostly the COST OF THE REPRESENTATION, not drift. About two in
three markers are forced by immutable terms, slot positions and the absence of SWI's tables. The
interim ones name the step or question that removes them. Extensions are few.

**The problem the audit found is the COMMENTS: 19 of 40 were inaccurate or incomplete,** and four
of those had gone STALE. Each was true when written and was overtaken by a later chunk:
* S02 waited for "V5" after V5b had shipped;
* S26 said built-ins do not exist (they do since V5a2);
* S29 said there was no argument stack (there is since V4a);
* S09 gave two reasons that were not upstream's.

A marker's reason rots when the code around it moves on.

## What was changed

* **The 19 REWORD comments** (and S03, whose second sentence described no divergence), rewritten
  to say what is true. The duplicate marker on `pl_variant2_va` (S35) is gone. `LOAD_REGISTERS`
  gains the marker its twin `SAVE_REGISTERS` had (S37).
* **A false inline remark** in `compare_descend` (S25) is corrected: the loop does compare the head.
  So is the `atomic_compare` docstring (noted at S28): kernel-only values sort before atoms, not
  after.
* **Two of the three missing tests added:**
  * S38: `PL_close_query` and `PL_cut_query` on a closed handle, with another query open and with
    none (test/foreign/test_query.jl).
  * S16: `MurmurHashAligned2` against upstream's own aligned function, compiled from pl-hash.c at
    `bae881a2`. All 492 known answers match: every length 0 to 40, at four alignments and three
    seeds (test/core_lang/test_termhash.jl).
* **The third, S13, is NOT TESTABLE YET, and why:** clause GC's walk over a LIVE VM frame of a
  predicate with erased clauses (`markPredicatesInEnvironments!`).
  * Clause GC runs only when Julia calls it: the tests call it between or inside `clause/2` and
    `retract/1` enumerations, which run outside the VM.
  * Reaching the frame walk needs GC to run WHILE a VM frame executes such a predicate. That takes
    a built-in calling it from a clause body, `garbage_collect_clauses/0`, not ported, or
    `retract/1` on the VM, which V9 brings.
  * The test is added with whichever comes first. Until then the frame walk is exercised by no test.

## Questions for the owner

1. **S05, a key collision that gives a wrong answer.**
   * The kernel's list-cell key `FUNCTOR_dot2` is a fixed word, and an ordinary `name/2` key is a
     hash: distinct "but by chance, as any two keys" (the owner, 2026-10-04).
   * An index tolerates a chance collision; it only narrows less. But `listSupervisor` takes the key
     (and `ATOM_nil`'s) as identity. A predicate `p([]). p(foo(_,_)).` whose `foo/2` hashed to
     `FUNCTOR_dot2` would get `S_LIST`, which fails the call `p(foo(1,2))`. The odds are about
     2^-52 per name.
   * (a) Exclude the two reserved words by construction: a hashed key equal to one of them is
     perturbed, which costs one comparison per key. (b) Keep "by chance", with the comment now
     saying what a collision costs.
   * **Recommend (a).** It is small, it is pinned by a test that feeds the colliding hash, and it
     makes the identity exact as upstream's handles are.
2. **S33, the predicate-access stack's depth limit.**
   * Upstream raises `representation_error(predicate references)` past 2^20 − 1000 nested
     references and returns NULL to callers that handle it; the kernel's stack grows without limit.
   * (a) Port it with its callers' NULL handling. (b) Leave it NOT PORTED, as the comment now says.
   * **Recommend (b) until clause enumeration moves onto the VM (V9)**, where the callers change
     anyway.
3. **A staleness check in port_check.**
   * Four stale markers in 40 suggest about 30 in the population.
   * The check: a `# DIVERGES` or `# NOT PORTED` comment that names a plan step (`V5`, `V9`, `R1`,
     …) which port_inventory marks DONE is flagged. Each chunk's preflight then lists the markers its
     own completion just made stale.
   * It needs two things: a step token the check can read, and a step that counts as done only
     when its row is wholly DONE (`V5` stays open while `V5c` is).
   * It catches the named-step kind (S02's). Rot like S26's and S29's, where a fact changed but no
     step was named, still needs each chunk to re-read the markers of the files it touches.
   * **Recommend: build it**, with the re-read as a step of each chunk's checklist.
4. **Separate "not yet ported" from "diverges".**
   * Part of the 20% OTHER are absences, not divergences: unscheduled subsystems (transactions,
     wrappers, threads' locks) and the two markers that describe nothing that differs.
   * The convention half exists: `NOT PORTED` appears on 39 lines, 10 of them standalone markers
     and 14 inside a `# DIVERGES` line.
   * The proposal: `# NOT PORTED: <what>, <why>` for an absence; `# DIVERGES` only where the kernel
     behaves, or is structured, differently from upstream. The DIVERGES share then means one thing.
   * (a) Adopt it now for new code, and migrate a file's markers when a chunk touches it,
     port_check counting the two markers apart. (b) A dedicated pass over all 336.
   * **Recommend (a)**: the staleness check (3) re-reads them as they are touched anyway.
5. **S10, a cleanup the audit made visible.** The unifier's occurs-check failure throws a Julia
   exception that a wrapper converts to `PL_error`. Upstream raises the error directly, and the
   kernel now can. **Recommend: do it** when the inline unification family comes next (it touches
   the same code).

## The sample

Line numbers are as sampled, before this audit's rewrites.

| # | marker | class | verdict |
|---|---|---|---|
| S01 | `src/SWI-Prolog.jl:97` | FORCED | REWORD |
| S02 | `src/pl-alloc.jl:32` | INTERIM | REWORD |
| S03 | `src/pl-arith.jl:368` | OTHER | JUSTIFIED |
| S04 | `src/pl-arith.jl:779` | FORCED | JUSTIFIED |
| S05 | `src/pl-comp.jl:665` | FORCED | REWORD |
| S06 | `src/pl-comp.jl:1002` | FORCED | JUSTIFIED |
| S07 | `src/pl-comp.jl:1608` | INTERIM | REWORD |
| S08 | `src/pl-error.jl:16` | FORCED | REWORD |
| S09 | `src/pl-ext.jl:92` | INTERIM | REWORD |
| S10 | `src/pl-fli.jl:257` | EXTENSION | JUSTIFIED |
| S11 | `src/pl-fli.jl:282` | FORCED | JUSTIFIED |
| S12 | `src/pl-funct.jl:41` | FORCED | JUSTIFIED |
| S13 | `src/pl-gc.jl:14` | FORCED | MISSING-TEST |
| S14 | `src/pl-global.jl:12` | OTHER | REWORD |
| S15 | `src/pl-gmp.jl:57` | FORCED | JUSTIFIED |
| S16 | `src/pl-hash.jl:26` | FORCED | MISSING-TEST |
| S17 | `src/pl-incl.jl:250` | FORCED | JUSTIFIED |
| S18 | `src/pl-incl.jl:475` | FORCED | JUSTIFIED |
| S19 | `src/pl-index.jl:2157` | FORCED | JUSTIFIED |
| S20 | `src/pl-index.jl:2207` | FORCED | REWORD |
| S21 | `src/pl-inline.jl:60` | OTHER | REWORD |
| S22 | `src/pl-inline.jl:73` | INTERIM | JUSTIFIED |
| S23 | `src/pl-modul.jl:25` | INTERIM | JUSTIFIED |
| S24 | `src/pl-prims.jl:288` | FORCED | JUSTIFIED |
| S25 | `src/pl-prims.jl:405` | FORCED | REWORD |
| S26 | `src/pl-proc.jl:74` | OTHER | REWORD |
| S27 | `src/pl-proc.jl:265` | OTHER | REWORD |
| S28 | `src/pl-ressymbol.jl:54` | EXTENSION | JUSTIFIED |
| S29 | `src/pl-setup.jl:12` | FORCED | REWORD |
| S30 | `src/pl-supervisor.jl:53` | OTHER | JUSTIFIED |
| S31 | `src/pl-termhash.jl:523` | FORCED | JUSTIFIED |
| S32 | `src/pl-termwalk.jl:16` | FORCED | REWORD |
| S33 | `src/pl-thread.jl:26` | FORCED | REWORD |
| S34 | `src/pl-trace.jl:38` | FORCED | REWORD |
| S35 | `src/pl-variant.jl:359` | OTHER | REWORD |
| S36 | `src/pl-vmi.jl:363` | FORCED | REWORD |
| S37 | `src/pl-wam.jl:652` | OTHER | REWORD |
| S38 | `src/pl-wam.jl:956` | FORCED | MISSING-TEST |
| S39 | `src/pl-wam.jl:1319` | FORCED | JUSTIFIED |
| S40 | `src/pl-wam.jl:1635` | FORCED | JUSTIFIED |

Also noted, and left as is: S21, upstream's database starts at generation 1 and the kernel's at 0
(not observable from Prolog, now in the comment). S14, nothing enforces one local data per global
data, and clause GC marks the frames of the one it is given (now in the comment). S34, the dispatch
index qualified by its table would mirror upstream's function test more closely; the name test is
equivalent today.
