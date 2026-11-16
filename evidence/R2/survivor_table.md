# R2 survivor table at 604d6acc — PARTIAL (agent 1 of the step R2-SURVIVOR-TABLE-1; handed back at the 150k cap)

State: BISIM, P2B, CT1B, LOCALE done statically (LOCALE except LC-I2, LC-O4, LC-O9, LC-S10, LC-U2 and the six declared
equivalents); TAI1, CT1C, Q10B, Q10C, ZIP1, P3 NOT read yet; part (B) (the evidence's words on "which process") NOT done;
part (C) (fresh-process proofs) RUNNING in the background (see the end). The next agent continues from this file.

Method facts (read in tools/mutate_ci.py and .github/workflows/mutation.yml at 604d6acc):
* `mutate_ci.py one`: `targets = m.get("targets") or <CLI targets>`: a mutant's OWN `targets` win; every mutant of all ten
  catalogues carries its own `targets` (BISIM, P2B, Q10B, Q10C, ZIP1: one file; CT1B, CT1C, LOCALE, TAI1: the list; P3: P3-1..P3-25
  one file test_depth_limit_swipl.jl, P3-35/-36/-41 five files). Each target is a fresh `julia --project=. --startup-file=no <file>`
  with LOGICKERNEL_TERM=reference, stopped at the first target that decides (exit 1 = caught). So the "CI targets" column below
  is the catalogue's.
* The limit: `LIMIT_S` (default 1500, workflow input `limit_s`) is a CLI argument of `one`; there is NO catalogue-level limit field
  (fields: id, file, old, new, expect, equivalent, targets). `expect: "hang"` exists (verdict "caught (hang)") and the workflow job has
  `timeout-minutes: 120`. Smallest harness change (DESCRIBED, not made): in `mutate_ci.py one`, `limit = int(m.get("limit", limit))`
  plus the same in mutate_drive.py's local loop, and a catalogue field `limit=300` on the hang-class mutants together with
  `expect="hang"`. The three CT1C jobs died with exit 143 at "Apply the mutant and run the targets" before 1500 s: a shorter per-mutant
  limit (300 s) fires first.

## Findings so far (static; (i) = KILL file missing from CI targets, (iii) = KILL row does not reach/observe the mutated effect)

In EVERY mutant read so far (i) is NO: the file holding the named KILL rows is in the mutant's own targets (CT1B C3's
"test_umap's tables check" is test_umap_swipl.jl, which IS in CT1B's TARGETS). The cause is (iii) throughout: the survivor is
EQUIVALENT in its answers by reading the code, or the row cannot observe the effect. Cause (ii) and the fresh proofs: below.

| id | named KILL | (i) | (iii) finding (file:line at 604d6acc) | class |
|---|---|---|---|---|
| BISIM-7 refine not called | t8 t20 t24 t31 t45 (test_bisim_swipl.pl) | NO | `refine(g)` runs at src/pl-bisim.jl:679 for every row, but each named row (cyclic f(f(X,a),a), f(X,a)) is stable after `split_colours` (lines 349-): a class is split by refine only when two nodes agree in functor and child colours but differ deeper. A row needs a chain of differing depth, e.g. term_minimal(h(f(f(a)), f(f(f(a)))), M) (candidate, unverified) | PLAUSIBLE: needs a row |
| BISIM-13 a class used once is named too | t1 t2 t14 | NO | `g.named` (pl-bisim.jl:1172) is only read by `factorized_size` (:1180) to reserve cells (`need = named*7+...`); build_factorized decides names itself. Effect = a larger stack reservation, no answer changes | equivalent in answers (needs a stack-limit boundary row, or a declaration) |
| BISIM-24 unbound start = type error | t61 `err(automaton_minimal(_,_),R)` | NO | the mutated `PL_type_error(ld,"compound",A)` with an UNBOUND A is `instantiation_error`: src/pl-error.jl:458-479 `PL_error(..ERR_CHARS_TYPE..)` ("`instantiation_error` when `actual` holds a variable", as pl-error.c) | EQUIVALENT (declaration) |
| P2B-I16, P2B-I17 (drop `has_offset && return FTRUE`) | q03 q23 / q36 | NO | src/pl-prims.jl:4109, 4123: with a bound Start `_icasechk_search` (:4049) returns `offset` itself (the loop breaks after the first position, :4072), so `PL_unify_integer(start, found)` unifies offset with offset: always true | EQUIVALENT |
| P2B-I2 `has_offset=false` for a bound start | q24 | NO | pl-prims.jl:4098: the search then continues past `offset`, finds a later `found != offset`, and the unify with the bound Start fails: same answer (false), only the cost differs | EQUIVALENT (answers) |
| CT1b-A11 / A12 (csym, csymf drop `\|\| chr == '_'`) | t0 t1 t10 | NO | src/os/pl-ctype.jl:104,107: `isAlpha(c) = _char_type(c) >= UC` and `isLetter = isLower\|\|isUpper`; '_' is class UC in the ASCII table, so the `_` disjunct is redundant (as pl-ctype.h) | EQUIVALENT (redundant disjunct; fresh run of A11 pending) |
| CT1b-A22 digit(W) char argument | t3 t5 | NO | pl-ctype-pred.jl:353,424: CTX_CHAR only matters in `char_type`; row t3 (test_char_type_swipl.pl:23-25) normalises `( atom(X) -> char_code(X,V) ; V = X )`, so a character W and an integer W give the same line; t5 uses code_type, where PL_unify_char in code mode is an integer. A row needs `char_type(Ch, digit(W)), integer(W)` | row gap: needs a row |
| CT1b-A25 `c == -1` shortcut (-> -2) | t11 t12 t13 | NO | pl-ctype-pred.jl:400: the table has its own class `end_of_file` (line 218, test `iseof`, :99), so the generic enumeration answers the same single `end_of_file` | EQUIVALENT (by reading; no fresh run) |
| CT1b-C1, C2 odd member of a run uses the even delta | t2 t3 t4 | NO | src/pl-umap.jl:955-: the rows' characters (a, Z, 0xe9, 0x3b1 ...) lie in runs whose two deltas are equal; t4 enumerates reverse mappings whose targets (a A 5 α Α) no alternating-run letter maps to. A row with a member of an alternating run, e.g. `code_type(0x101, to_upper(U))` (U=0x100) | needs a row |
| CT1b-C3 `hi = PL_CASE_RUNS - 2` | t2 t4 + "test_umap tables check" | NO | test_umap_swipl.jl:20-30 "tables" testset compares the GENERATED TEXT with tools/gen_umap.jl's output (and the 2nd testset every code point's CLASSES), never `pl_case_run_of`; the last run is (125218, 34) = U+1E922.. (Adlam), reached by no row. Row: `code_type(0x1e922, to_upper(U))` | needs a row |
| LC-B1 `_locale_serial!` always new number | t6 R21 `B3 == B4` | NO | src/os/pl-locale.jl:296-300, :315-: `unifyLocale` returns the cached `l.symbol` (`ls !== nothing`) after the first call, so `_locale_serial!` runs once per locale (and at :590 as a retry token): a fresh number there is invisible. Catalogue's "every unify makes a new blob" is false while the cache stays | EQUIVALENT in answers (only B1+B3 together differ) |
| LC-B3 cached blob not kept (`l.symbol` not set) | t6 | NO | :315-: without the cache `lookupBlob(bytes)` of the SAME serial gives the same blob word (bytes identical), so B3 == B4 still holds | EQUIVALENT in answers |
| LC-C2 set_chars no cut at NUL | t10 'a\0b' | NO | the NUL row is now **t12** (commit e7f13112; test_locale_swipl.pl:128-): the kernel refuses the atom of character 0 (`t12 notported`, pinned by name in test_locale_swipl.jl), so no row reaches `_cstr` with a NUL. t10 no longer holds it | row cannot run (DIVERGES: refusal of the NUL atom) |
| LC-D1, LC-I2, LC-O4, LC-O9, LC-S10, LC-U2 | t4 t9 / t8 / t10 / t4 / t7 t8 / t11 | NO | NOT YET READ. LC-U2: t11 answers `ok` when `setlocale(Cat,Old,'en_US.UTF-8')` raises (host without that locale): CHECK `locale -a` on the runner and on this host; the catalogue header says the same | UNKNOWN |

CT1B-C* / BISIM / P2B / LOCALE-B* rows above are the reading of the code; the fresh-process runs below are the proof.

## Still to do (next agent)

1. Read, per the brief, the same four items for: LC-D1 LC-I2 LC-O4 LC-O9 LC-S10 LC-U2; TAI1-F58 F59 F60 F61 L1 L4 T12 (named rows "tz t5",
   2000-03-01 = 51604, negative round trip, t10 seconds -1: find the files in test/core_text/test_tai_swipl.jl, test_tai_format_swipl.jl,
   test_libtai.jl); CT1c-A7; Q10B-B4 (fb08); Q10-39 (pt23 pt13), Q10-44 (cb03 cb04 cb05) (rows NEW on the R2 line in test_q10_swipl.jl);
   ZIP1-C6 (t49 t50), ZIP1-N2 (kr3-kr6); P3-1 (dl01) P3-29 (il11) P3-31 (il18) P3-5 (dl03 dl04) and the declared equivalents
   (LC B4 D3 D5 O8 P11 S11 are above in the catalogue with file:line reasons; BISIM-8; P2B-S8; TAI1 F57 F71 F8; Q10B A4 B8; Q10C 13 33 34 4 42;
   ZIP1-C5; P3-9 and P3-26: "`$depth_limit_true` does not read its Limit on the first call", "`$inference_limit_true` with a bound Result
   still restores"). Dump any mutant with `python3 -I <scratchpad>/dump.py <CAT>` (scratchpad below).
2. (iv): P3-17 -24 -25 (targets test_depth_limit_swipl.jl) and -35 -36 -41 (five files) and CT1c-A8 B1 B2 (targets
   test_ctype_text_swipl.jl + test_char_type_swipl.jl): read the catalogue text for the hang declaration and the hang site; none carries
   `expect="hang"` (checked: key `expect` absent in all ten dumps read so far; check P3/CT1C).
3. ZIP1-T-ext / T-ext2 (src/pl-ext.jl, targets test_zip1_swipl.jl): why `new` does not load (python3 -I syntax check of the replaced
   text; the throwaway-worktree load needs the marker `# allow-cold-start: isolated-experiment` on the same command line).
4. (B): quote the evidence's words on the process for BISIM, LOCALE, P2B, CT1B, TAI1, Q10B, Q10C, ZIP1, P3 from evidence/R2/*.md here
   (only changed_files_run.md, gate_evidence_red.md, gate_rerun_e253a38f.md exist in evidence/R2 of this worktree) and the
   lk-channel evidence/ dirs (r2land / r2s1 / r2next ... handoff files) and tools/mutants/*.log.
5. Fill the fresh column from the TSV (below), write the 10-line cause distribution, remove the two scratch worktrees, commit.

## Fresh-process proof (part C) — RUNNING when this file was written

* Two capped background runners (systemd-run scope, MemoryMax=6G), one per scratch worktree (detached 604d6acc + the untracked
  Manifest.toml and home/ copied from lk-r2land, no Julia run needed for them): ~/code/lk-mut-s1 and ~/code/lk-mut-s2.
  Runner: <scratchpad>/fresh_runner.py (resets src/ with `git checkout -q -- src` before each mutant, runs
  `python3 tools/mutate_ci.py one tools/mutants/<CAT>.py <ID> 1500 <catalogue TARGETS>` with JULIA_NUM_THREADS=4 and
  LOGICKERNEL_REQUIRE_SWIPL=1 as mutation.yml does, local swipl 10.1.20 at ~/.local/bin).
  s1: BISIM-7 P2B-I2 CT1b-A11 LC-B1 TAI1-F58 Q10B-B4 Q10-39 ZIP1-C6 P3-1 (in that order);
  s2: BISIM-24 P2B-I16 CT1b-C3 LC-D1 TAI1-L1 Q10-44 ZIP1-N2 P3-5.
* Results (TSV: cat, id, head, src state, verdict, exit, first failing line, mutant seconds, wall seconds): 
  <scratchpad>/fresh/s1.tsv and s2.tsv; logs <scratchpad>/fresh/<ID>.log; scratchpad =
  /tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/b1bc52d9-44dc-428a-a9bb-10bf805f9033/scratchpad
  (session scratch; copy the TSV into evidence/R2/ before the session ends). Background task ids: b1zohwbug (s1), bbyl8rg4t (s2).
* Expected by the reading above (to be confirmed or refuted by the TSV): BISIM-24, P2B-I16, P2B-I2, CT1b-A11, LC-B1 survive for the
  stated equivalence reasons; BISIM-7, CT1b-C3, LC-D1 survive for want of a row.
* The machine ran one foreign Julia (lane daemon, 3.3 GB) at the start; mine are the two scoped runners.
