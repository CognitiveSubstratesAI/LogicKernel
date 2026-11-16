# R2 survivor table at 604d6acc — PARTIAL (agent 1 of the step R2-SURVIVOR-TABLE-1; handed back at the 150k cap)

State (agent 2 added PART 2 and PART 3 at the end): BISIM, P2B, CT1B, LOCALE, TAI1, CT1C done statically; Q10B, Q10C, ZIP1, P3 (survivors, the
ZIP1 does-not-load pair, the declared equivalents) NOT read yet (the P3 hang declarations ARE read, PART 3); part (B) (the evidence's words on "which process") NOT done;
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
| LC-D1, LC-I2, LC-O4, LC-O9, LC-S10, LC-U2 | (see PART 2 below) | NO | read in PART 2 | see PART 2 |

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

## PART 2 (agent 2 of R2-SURVIVOR-TABLE-2): LOCALE rest and TAI1, by reading the code at 604d6acc (src/os/pl-locale.jl, pl-tai.jl, pl-libtai.jl)

Cause (i) is NO for every row of this part (each mutant's own `targets` lists the file holding its KILL rows: LOCALE: test_locale_swipl.jl,
test_setlocale_swipl.jl, test_format_swipl.jl, test_char_type_swipl.jl, test_ctype_text_swipl.jl; TAI1: test_libtai.jl, test_tai_swipl.jl,
test_tai_format_swipl.jl; the "tz t5" row is test_tai_format_tz_swipl.pl, run by the SECOND testset of test_tai_format_swipl.jl, TZ fixed to
CET-1CEST,M3.5.0/2,M10.5.0/3 on both sides). Probes marked [py] are my own Python models of the quoted Julia code (no Julia run).

| id | (iii) finding | class |
|---|---|---|
| LC-D1 (no deleteat! on destroy) | pl-locale.jl `_locale_table_index` (:213-221) skips every table entry whose `alias === nothing` (`la === nothing && continue`), and destroy still sets `l.alias = nothing` (:825): the stale entry is invisible to every alias lookup, so t4's re-create succeeds either way. The only reader that walks the vector by position is the unbound-locale enumeration of locale_property/2 (:593 `gd.locale.table[x]`), and every row filters it with `locale_property(L, alias(A))` (t7 L2-L10), which fails for the stale entry. Catalogue "the alias is free to take again" is false while the lookup skips alias-less entries | EQUIVALENT in the rows' answers; row candidate: `findall(L, locale_property(L, decimal_point(_)), Ls), length(Ls, N)` before and after create+destroy must be equal (swipl deletes the entry; the mutant leaves N+1) |
| LC-I2 (default_locale not acquired) | the mutant only lowers the reference count of the `default` locale by one (alias 1 + current 1 instead of 3). releaseLocale frees only at 0 with no symbol and no alias (:192-197); t8 never destroys `default`, so the count never reaches 0 and `current_locale(C0)` answers the alias either way | EQUIVALENT for the rows; a kill needs `set_locale(other)`, `locale_destroy(default)`, then a read of the default (e.g. `locale_create(_, "default", ..)`): destructive for later rows of the process, so it must be the LAST row of the .pl (swipl pins it) |
| LC-O4 (no trailing 0 in grouping) | the only reader of the vector, `locale_grouping_property`, goes through `_grouping_at` (:391) which answers 0 past the end, and pl-fmt.jl uses its own `PL_locale` struct (pl-fmt.jl:55-67), not `PL_locale_rec`. For en_US `[3,3]` and `[3,3,0]` both give `[repeat(3)]`; for "C" `[]` and `[0]` both give none. Also t10's en_US branch (`lc_en`) is host-dependent (below) | EQUIVALENT in answers; host-locale dependent in the row too |
| LC-O9 (alias check dropped in `_alias_locale_table!`) | the same test is made by its only caller `alias_locale` (:251-257), which raises permission_error before `_alias_locale_table!` runs; the other caller (initLocale!, :872) runs on an empty table. t4's R1 hits the check in `alias_locale`, so the second one is dead | EQUIVALENT (redundant check) |
| LC-S10 (enumeration unifies the blob, not the alias) | t7/t8 enumerate with the locale unbound and then call `locale_property(L, alias(A))` on it, which works for an alias or a blob alike; no row tests `L == lc7a` after the enumeration. (t8's `locale_property(C1,P)` has the locale BOUND, never reaching :528) | row gap: row `locale_property(L, decimal_point(':')), locale_property(L, alias(A)), L == A` (swipl: true) |
| LC-U2 (update_locale refreshes every category) | independent of the host: `update_locale` re-reads `_read_lconv()` (LC_NUMERIC of the thread), and a ctype/time/messages/collate setlocale does not change LC_NUMERIC, which t11's first goal sets to C; the refresh writes the strings it already holds. On a host WITHOUT en_US.UTF-8 `lc_upd` answers ok before any refresh (setlocale raises). So the row cannot kill it on any host | EQUIVALENT in answers; row host-dependent |

HOST LOCALE (task item): `locale -a` on this host prints C, C.utf8, en_US.utf8, POSIX and LANG=en_US.UTF-8. The CI workflow files (.github/workflows/*.yml
and .github/actions/*) name only `runs-on: ubuntu-24.04` (mutation.yml:81,96,166,245) and install no locale: the only apt-get is the oracle action's
`cmake ninja-build libgmp-dev zlib1g-dev` (.github/actions/oracle/action.yml:29). Per the image's known contents (my knowledge; not checkable here) the runner
has C, C.utf8, POSIX and no en_US.UTF-8, so on CI `lc_en` (t10 R8) and `lc_upd` (t11 R1-R6) answer `ok` without running: the mutants whose catalogue KILL
needs the host locale are LC-U2 (t11) and LC-O4 (t10 'en_US.UTF-8'); LC-P11 (declared) also needs a host locale with a CHAR_MAX group. All other LOCALE rows
build their locales from "C" with explicit properties. Both host-dependent mutants are equivalent in answers anyway (above), so the host locale is not the cause.

Declared equivalents of LOCALE (catalogue words; none rests on a probe: all are readings of the code with file:line, "no row: count only"):
B4 the blob's reference is not taken: `l.symbol` is set on first unify and never cleared, so releaseLocale never frees it (no atom GC); D3 the alias's reference is
not dropped: a destroyed locale is unreachable by name, freeing is unobservable; D5 `l !== ol` always true: the reference of the old current locale is released
once more, frees nothing while the alias/blob holds it; O8 releaseLocale ignores the alias: the alias holds a reference so a locale with an alias never reaches 0;
P11 CHAR_MAX ends the list: reached only by a host grouping with a CHAR_MAX group followed by another; S11 FRG_CUTTED answer: the result is ignored. I checked S11:
`discardForeignFrame` calls the foreign function and returns `nothing` (pl-wam.jl:1378-1405 at 604d6acc); the catalogue cites it as pl-wam.jl:1203-1207, now a
different function: a STALE CITATION (argument still true). B4, D3, D5, O8: the arguments are sound by the count arithmetic read above.

### TAI1 (cause (iii) throughout; one row gap each, no equivalent among the seven except L1/L4)

| id | finding | class |
|---|---|---|
| F58, F59, F60, F61 (`_wrap32` dropped from `Int(tm_year)+1900`) | `tm_year` is an `Int32` (pl-tai.jl:49) already wrapped by `year % Int32` (:288, :326). Row t5's stamps 6 and 7 (67768036191676799/800, UTC year 2147485547, local year 2147485548 under TZ CET) have local year 2147485548, so tm_year = 2147483648 wraps to -2147483648 and `Int(tm_year)+1900` = -2147481748 NEEDS NO WRAP (expected line of t5: -2147481748). The wrap32 matters only when tm_year is in 2147481748..2147483647, i.e. a LOCAL year 2147483648..2147485547: t5 has no such stamp, t6's date/9 years stop at 2147483647 (tm_year 2147481747, +1900 = 2147483647). [py] year 2147485548 = tm_year 2147483648 | EQUIVALENT for every row; ONE row kills all four: stamp 67767987355891200 (year 2147484000, [py]) with %Y %C %y %G, answer from swipl |
| L1 (`m >= 2` -> `m > 2`) | for m == 2 the mutant takes the else branch (m = 12, y -= 1) and the next lines `y += m ÷ 12; m %= 12` give m = 0, y unchanged: same as the then branch. [py] model of the quoted function, 0 differences over years -3000..3000 x 12 months x 3 days; 2000-03-01 = 51604 in both | EQUIVALENT (redundant branch) |
| L4 (`y < 0` -> `y < -1`) | y == -1 left unfolded gives d += 1095 - 1461 = -366 and the folded path 1095 + 35064 + 109572 - 146097 = -366: same. [py] 0 differences, same range | EQUIVALENT |
| T12 (`fp < 0.0` -> `fp < -1.0`) | `modf` leaves fp in (-1, 0] or -0.0, so `< -1.0` never holds: the fixup is dead in the mutant. The named row t10 (test_tai_swipl.pl:35-38) has seconds `-1` (an integer): modf(-1.0) = (-0.0, -1.0), fp < 0 is false in BOTH. No row has a negative FRACTIONAL second | row gap: `date(2020,3,1,0,0,-0.5,0,-,-)` (needs a fractional negative second), answer from swipl |

TAI1 declared equivalents: F57 (`year-1` of %G cannot reach INT_MIN, tm_year+1900 >= -2147481748: arithmetic, sound as read); F71 (the 400-year rule of `__isleap`: the catalogue
says "an exhaustive comparison of every day of 1600, 2000, 2400 and the next years gives 0 differences (computed 2026-11-13)": a computation of unnamed process; my [py] model
of iso_week_days + the %G/%V branch over every day of 1599-1601, 1999-2001, 2399-2401 also gives 0 differences in 4019 days, so the claim holds); F8 (posix %a/%b read the C tables
vs strftime: "read, not run": same names in C/English locale; the tz rows t2/t3 force LC_TIME=C, so on CI it is equivalent; a non-English LC_TIME host would tell them apart).

## PART 3: CT1C (A7 survivor; A8, B1, B2 NO VERDICT) and the P3 hang declarations, by reading at 604d6acc

| id | finding | class |
|---|---|---|
| CT1c-A7 (`PL_chars_t(bytes, length(cin) + 1, ..)`) | pl-ctype-pred.jl:568. The only consumers are `PL_unify_text(.., text_type)` with PL_ATOM or PL_STRING, and both call `PL_canonicalise_text` first, which for an ENC_UTF8 text RECOMPUTES `text.length` from the bytes (pl-text.jl:277-291: `text.length = e` or `= length(cps)`), so the length passed in is overwritten before any use. Rows t0/t9 cannot see a length that nothing reads | EQUIVALENT in answers (dead argument for atom and string output) |
| CT1c-A8 (`index >= length(cps)`) | HANG, not a kill: `ctype_get_chr_from_text` (pl-ctype-pred.jl:528) now answers `(-1, index)` at the LAST character without advancing. In `write_normalize_space` (:650-668, `end_ = length(cps) + 1`) the loop `while i < end_` has `i` stuck at the last position: `skip_separators` and `copy_non_separators` both return at `c == -1` with `i` unchanged, `i < end_` stays true, and `Sputcode(' ', out)` (:664) runs every iteration: an endless loop whose output sink (an atom/string/codes buffer, or a stream) grows without bound. Every normalize_space row (t19, t24 ..) reaches it, even one-character text. The catalogue's KILL "t0, t1" is wrong: t0/t1 use a variable output, which never calls get_chr_from_text (:561-568 walks `cin` directly); the bound-output branch (t8) would answer true at the last character | HANG (iv): infinite loop with unbounded output growth, dies by memory/job limit (exit 143) before LIMIT_S 1500 |
| CT1c-B1 (`skip_separators` skips non-space) | HANG: skip_separators (:617-627) now advances over non-space and returns at the first space; copy_non_separators (unchanged) returns at once on that space, and skip_separators at the same position returns again: in `write_normalize_space` the pair makes no progress while `i < end_` and `' '` is written each pass: the same endless loop (text with a space; text without a space just ends with empty output) | HANG (iv), same site :660-664 |
| CT1c-B2 (`copy_non_separators` copies the white space) | HANG: copy_non_separators (:633-646) returns `(true, i)` at the first NON-space without advancing; skip_separators returns at the same non-space; same endless loop at :660-664 for any text with a non-space after the leading white space | HANG (iv), same site |

Hang declaration in the catalogue: NONE for A8, B1, B2: no `expect` key in CT1C.py or P3.py (checked: the key does not occur in either file), no word "hang"/"loop"/"endless" in their ids,
and the header of CT1C.py lists "`while i < end_` as `i <= end_`: an endless loop, which the battery's time-out would count as killed without evidence" under NOT LISTED, i.e. the
author knew the loop class and did not mark these three. Mutate_ci's `expect: "hang"` (verdict "caught (hang)") needs the key on each of the three, plus the site
(pl-ctype-pred.jl:660-664 `write_normalize_space`) in the id text, plus a bound shorter than the runner's life (the harness change in the method notes above: `limit` per mutant).

### P3 timeouts: does the catalogue text declare the hang? (the sites are in the mutated lines; I did not read the test rows of il03/il14/il23)

| id | text | declared? | site (the mutated line) |
|---|---|---|---|
| P3-35 (no alert bit for an inference limit) | "KILL il03: the loop is never stopped; the row would not end" | YES (the effect), no `expect`, site is the mutated line | pl-wam.jl updateAlerted mask line |
| P3-41 (the exception of an exceeded limit is not thrown) | "KILL il03: the loop runs on; the row would not end" | YES (effect) | pl-wam.jl, the `raiseInferenceLimitException ... @goto b_throw` block |
| P3-25 (a redo of `$inference_limit_true` installs no limit) | "KILL il14: the looping clause must be stopped" | by implication (a looping clause is run unbounded) | pl-prims.jl `$inference_limit_true` redo branch |
| P3-36 (a call does not look at the alert bits) | "KILL dl05, il03" | NO; il03 is the same unbounded loop as P3-35 | pl-wam.jl `depart_alerted` test |
| P3-17 (non-deterministic exit leaves no retry) | "KILL dl22 no redo ... il14" | NO; il14 is a looping row, the effect is that the deeper clause (the one that loops/needs the limit) is run differently | pl-prims.jl `PL_retry(1)` |
| P3-24 (`$inference_limit_true` leaves the old limit set) | "KILL il23: the recursion after a successful call" | NO | pl-prims.jl `ld.inference_limit_limit = olimit` |

Per D-0847 each of the six needs `expect="hang"` (or a bounded per-mutant limit) and the hang site named; P3-17, P3-24 and P3-36 also need the declaration text, since their ids do not say the effect is a hang.

## STILL TO DO (agent 3)

1. Q10B-B4 (fb08), Q10-39 (pt23, pt13), Q10-44 (cb03, cb04, cb05): (iii) reading in test/core_lang/test_q10_swipl.pl (rows NEW on the R2 line) and the mutated code; the declared equivalents Q10B A4/B8, Q10C Q10-13/-33/-34/-4/-42.
2. ZIP1-C6 (t49, t50), ZIP1-N2 (kr3-kr6), ZIP1-C5; ZIP1-T-ext / T-ext2 (why the mutated text does not load: read `old`/`new` in tools/mutants/ZIP1.py and src/pl-ext.jl).
3. P3-1 (dl01), P3-29 (il11), P3-31 (il18), P3-5 (dl03, dl04) survivors; P3-9, P3-26 declared (their written arguments are in the catalogue dump above: "the second read cannot fail on the boot's path" and "the boot calls it only on the branch where Result0 is unbound"; both are readings of the boot, no probe).
4. Part (B) (the evidence files' own words on the process of each recorded proof), the fresh-process column from the TSV (its files were empty when this agent ran), and the 10-line cause distribution.
5. Row candidates so far (for the dispatcher): LC-D1 (count of locales before/after create+destroy), LC-S10 (`L == A`), LC-I2 (last row: destroy `default`), TAI1 F58-F61 (stamp 67767987355891200 in 2147483648..2147485547), TAI1-T12 (`-0.5` second), BISIM-7, CT1b-A22, C1, C2, C3 (the previous agent's list). Equivalent by reading: LC-O4, O9, U2, B1, B3, TAI1 L1 L4, CT1c-A7, BISIM-24, P2B-I16, I17, I2, CT1b-A11, A12, A25, BISIM-13.
