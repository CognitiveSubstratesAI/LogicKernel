# W5-LBSMALL handoff

## State (W5b-FMTPRED, piece 1 DONE; piece 2 ON HOLD)
- Worktree /home/shivaji1012/code/lk-w5, branch wip/w5-lbsmall (from wip/tab-a04 6d09022d). No Julia was run for piece 1: NOTHING is compiled,
  formatted or tested on the kernel. The first step of the gate agent: `tools/warm.sh fmt`, then `check`, then the new test file on all three term types.
- Already written elsewhere (skip): `$clause_term_position/3` (wip/enc1 c4ff7e11, wip/comb1 0a67647e), iri_hook (wip/lbb 9238902d).

## Piece 1: format_predicate/2, current_format_predicate/2, the user directive of do_format (pl-fmt.c :242-325, :596-621 at 18168e62) — WRITTEN
- struct change (restarts the warm daemon): `const format_predicates::Vector{Tuple{Int, Procedure{T}}}` appended at the END of PL_global_data (src/pl-global.jl),
  `Tuple{Int, Procedure{T}}[]` at the end of the constructor call (src/pl-setup.jl). copy_global_data deep-copies it (default policy).
- src/os/pl-fmt.jl: pl_format_predicate2_va (update-or-append loop), pl_current_format_predicate2_va (NDET, `PL_retry(next index)`, no state pool),
  do_format's user-directive branch (one chain with the built-ins), the file header and the do_format DIVERGES text. No new function: no manifest row needed
  (the two pl_*_va rows exist, test/static_analysis_manifest.jl).
- DECISION TAKEN (item for the dispatcher, a behaviour question): upstream's current_format_predicate answers `(int)tv`, the entry's VALUE truncated (the low 32 bits of the predicate
  address), as its first argument (pl-fmt.c :300-304 at 18168e62), so a bound Char always fails on swipl 10.1.20 (rows t19-t21 `no`) and an unbound one gets a number that
  differs per run. The port computes the same thing from the procedure's `objectid` (one line, marked `# (int)tv`). Alternative: answer the table's key (the evident intent;
  then t19-t21 become `yes` on the kernel and swipl's `no` goes into a known-difference row). A register entry (private workspace) is to be drafted by the dispatcher; none is in this repo.
- Tests: test/core_lang/test_format_predicate_swipl.{pl,jl} (56 rows + a table white-box testset), pinned from swipl 10.1.20: `LC_ALL=C swipl -q` with the driver
  evidence/W5-LBSMALL/fp_driver.pl + `:- initialization((consult('fp.pl'), forall(between(1,56,N), run(N)), halt)).`, TWO runs byte-identical, stderr empty
  (the output is evidence/W5-LBSMALL/fp_pinned.txt, the same 56 lines as `_FP_EXPECTED`). The d09 refusal testset of test_format_swipl.jl is removed.
  Rows t24/t25 (`current_format_predicate(_, m2:fp_x(_, _))` succeeds on swipl: m2's default import is user) are the kernel's unify_definition bound-head branch: if the kernel answers
  `no`, trace unify_definition/isSuperModule, do not re-pin.
- Mutants: tools/mutants/W5LB.py, 30 mutants, every `old` counted once; TARGETS = the new test + test_format_swipl.jl (D-0238). Re-count the `old` strings after fmt (those with `\n`).
- docs/r2_owners.tsv: the format_predicate refusal line removed. docs/architecture.md (the "Refused by name" bullet) rewritten. The generated inventory block of docs/architecture.md
  (the LB5-LB7 row listing `refusal format_predicate/2 ...`) is NOT edited: tools/port_check.jl write_inventory regenerates it (needs Julia).

## Piece 2: expandVars `~user` (pl-os.c :1580-1600) — ON HOLD (D-0744 (1): a further unchecked-access allowlist entry waits for a D-entry)
Design (settled, do NOT write until a D-entry allows the ccall):
- src/os/pl-os.jl line ~393: replace the NotPortedError with: `dir = _getpwnam_dir(user)`; nothing -> if truePrologFlag(ld, PLFLAG_FILEERRORS):
  `name = PL_new_term_ref(ld); PL_put_atom(ld, name, mk_sym(T, Symbol(user))); PL_error(ld, ERR_EXISTENCE, mk_sym(T, :user), name)`; return nothing. value = dir.
  New helper `_getpwnam_dir(user::String)::Union{Nothing,String}`: `p = ccall((:getpwnam, LIBC), Ptr{Cvoid}, (Cstring,), user)`; p == C_NULL -> nothing;
  pw_dir = `unsafe_load(Ptr{Ptr{UInt8}}(p), 5)` (Linux struct passwd: name, passwd, uid+gid, gecos, dir at byte 32), `unsafe_string`; non-Linux -> keep a NotPortedError.
  The caches GD->os.fred/fredshome are left out (the DIVERGES comment already says so for myhome). Allowlist entries needed in test/test_type_discipline.jl (per file+kind:
  "os/pl-os.jl ccall" count 3 -> 4, new "os/pl-os.jl unsafe_load" 1 and "os/pl-os.jl unsafe_string" 1) = THE D-ENTRY QUESTION; manifest row `(LK._getpwnam_dir, Tuple{String}, false)`
  next to expandVars (test/static_analysis_manifest.jl:4089); update the file header NOT-PORTED text; remove the `~user` refusal line from docs/r2_owners.tsv.
- Rows (probed with the pin, LC_ALL=C): expand_file_name('~root', L) -> [/root]; ('~root/x') -> [/root/x]; ('~root//x') -> [/root//x];
  ('~nosuchuserxyz') and ('~nosuchuserxyz/a') -> error(existence_error(user, nosuchuserxyz), _); with flag fileerrors=false they FAIL;
  `set_prolog_flag(file_name_variables, true)` then exists_directory('~root') succeeds, exists_directory('~nosuchuserxyz') raises the same error.
  absolute_file_name(.., [file_name_variables(true)]) does NOT expand (do not use it). Use `~root` (home /root on Linux, CI is ubuntu-24.04 only) and say why in the file header.
  Put it in test/files/test_expand_user_swipl.{pl,jl} (the shape of test/core_lang/test_format_predicate_swipl.*: each row an atom). Probe script: ~/code/lk-w5-scratch/p1.pl.
  Mutants TARGETS: the new file + test/files/test_lb2b_swipl.jl (expandVars is also reached by expand_file_name/get_file_name).
