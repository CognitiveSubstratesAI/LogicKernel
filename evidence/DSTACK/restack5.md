# DSTACK restack5 - STATE FILE for the next agent (agent 2 hit ~110k after steps 1-4; nothing compiled beyond the daemon start)

Worktree ~/code/lk-dstack, branch wip/dstack-b3 (local, on origin/main b9de14d). Read restack4.md section D/E for the gate and push order;
this file says what changed since.

## Done by agent 2 (commits on the branch, newest last)
- db5f916 nine anchor re-fits (O1A-K1, MOD3a-S1/S2, SSU1-R4/S1, V9f MK4/MK16/MD7/MD21), V9f MK22 dropped, architecture.md text
  (determinism_error is a flag-table row; F1b block no longer "not yet gated"; flag k pinned by k03 and O1A-C8; O1A "131 mutants";
  the "UNVERIFIED nothing was parsed" line replaced), the grep-phrase wording in restack3/split/restack4.
  val.py (scratchpad of the dispatcher session, path in the brief) on O1A O1B F1B D1g MOD3a SSU1 V9f D1f: 0 bad anchors BEFORE fmt.
- 6b37391 REAL FINDING: the first daemon start died with "Method overwriting" for PL_get_int64_ex: main has it in src/pl-string.jl, the F1b commit
  added a second copy in src/pl-error.jl and a hand-listed manifest row `(LK.PL_get_int64_ex, Tuple{LD, Int64}, false)` that duplicates
  main's generated row (D-0298 class). Dropped the pl-error.jl copy and the hand row. PL_get_int64 (pl-fli.jl) and its row stay.
  After the fix the daemon started (cache, a few minutes): `tools/warm.sh status` = running, unit logickernel-warm-b4dc834e, pid 553064,
  ready. It runs against the tree at 6b37391 (src unchanged since; c77e4bd is evidence only).
- c77e4bd evidence/DSTACK/readf.md = D-0291 (f): redirect part of pl-file.jl and format_impl / prepare+end_sub_format / rubber of pl-fmt.jl read
  against the pin: no behaviour mismatch; do_format switch, formatInteger, formatFloat NOT read line by line (stated in the file; the audit may
  ask for it as a step). sf map by script: no dangling kill id.

## Left (in this order)
1. Optional F1B mutants (S_UNDEF fail/warning, var_prefix read, print_write_options): NOT added; list them in the F1B.py header "NOT LISTED" with
   the reason "no cheap anchor" if you do not add them. docs/architecture.md:5950 text is done; architecture.md:3231 region done.
2. Gates on the daemon (cwd ~/code/lk-dstack, own call): `warm.sh fmt` for committed files = `warm.sh send` of the changed files (HEAD-diff only);
   `warm.sh inventory` (take main's docs/port_inventory.md, regenerate); `warm.sh check --summary` with JET on the SHA (D-0282 item 2);
   rows x3 (test_format_swipl.jl incl. row k03 whose swipl answer "1" is checked live, test_with_output_to_swipl.jl, test_set_flag_swipl.jl,
   test_prolog_flag_swipl.jl incl. the 3 new rows, test_module_enum_swipl.jl); test/test_type_discipline.jl x3; `tools/pkgtest_way.sh <file>` ONE at a time;
   alloc pins x3 (numbers in ~/code/lk-channel/evidence/LB3/gate.md); branch-gate --summary (capped); term grep over diff + messages (the diff is clean as of c77e4bd);
   the DISPATCH_MANIFEST uniqueness probe on the daemon (must be empty; I only removed the one PL_get_int64_ex duplicate by reading, the probe decides);
   the local static shard run as LB3 did (D-0298 item 3; .github/workflows/evidence.yml matrix) and test_static_analysis_body on the final SHA.
3. After fmt: re-run val.py on the 8 lists (also pl-file.jl line numbers cited in the O1B equivalents: re-check after fmt).
4. Push (restack4.md E): `git ls-remote --heads origin 'gate/*' 'mutants/*'` for free names, git fetch (main moved? then rebase as a NEW branch name),
   pull the channel + new D-entries, push gate/dstack-b3 + mutants/O1A, O1B, F1B, D1g, MOD3a, SSU1, V9f at ONE SHA, ONE capped `tools/ci_wait.sh --timeout 10800 <sha>`,
   then check EACH run by name with `ghg run list --commit <sha> ...`.

## For the dispatcher (lanes.conf is yours)
Daemon logickernel-warm-b4dc834e in lk-dstack is running since ~18:05Z (cache load, no cold compile needed); lk-lb3 and lk-lb4a are the other two.
