# RDDICT handoff 3 (rows agent, Sonnet) — branch wip/rddict in ~/code/lk-dict, linear, NOT pushed, nothing compiled or run

## Commits of this agent (on top of ba1955a)
- 9e6b396 rows rd01-rd114 + mode rows rm01-rm09 (test/core_lang/test_read_dict_swipl.jl, evidence/RDDICT/{cases.py,mk_rows.py,template.jl.in,run_swipl.sh,*.pl,*.out})
- 1aa3f01 rows rd115-rd126: subterm_positions of dicts (read_term_from_atom/3)
- a02b344 mode rows rm10-rm23: attributes and labels of the attvar mode
- the next commit (this handoff): the last rows (group "key and tag edge cases" rd127-rd152, mode row rm24 `current_prolog_flag(var_tag, R)`),
  regenerated test file and pins, mutants_draft.py, this file.

## Rows (all pins from swipl 10.1.19, `LC_ALL=C`, TWO byte-identical runs: `bash run_swipl.sh`, then `python3 mk_rows.py` fills the pins)
- 152 main rows: dicts read through term_to_atom/2 (rdd/rdv/rdw/rda/rdx), 36+ syntax errors (rds: `syn(Id, CharNo)`), the dict-dot reads
  (generic '.'/2 term: `Ctx.get(stack)`, `_{a:1}.put(b,2)`, `X.y.z`), clause bodies/heads with dict syntax in the PROGRAM (init.pl:1297 and
  autoload.pl:889 lines), positions (rdp, read_term_from_atom/3 + subterm_positions), key edge cases (small-int limit is +-2^56: swipl answers key_domain
  beyond it), duplicate-key positions, `X{a:X}` tag sharing (rdsame).
- 5 modes x 24 mode cases (rm01-rm24): swipl `:- set_prolog_flag(var_tag, M).` atop its program, the kernel sets `user.flags = setVarTagFlag(...)` before
  `load_file!`. rm10-rm23 are attvar-mode attributes/labels; rm24 = current_prolog_flag(var_tag, R).
- A final testset tests setVarTagFlag/getVarTagFlag as functions (round trip of the five atoms, other bits kept, domain_error(var_tag, foo|Dict|ERROR) read
  via `PL_exception(ld, 0)`; swipl: `set_prolog_flag(var_tag, foo)` -> domain_error(var_tag,foo); fresh flag `dict`). Not-vacuity blocks count the pins.
- All kernel answers UNVERIFIED (nothing compiled). Risks for the gate: (1) the setter testset's `PL_exception(ld, 0)` with no query; (2) the kernel's
  warning-mode `printMessage` path; (3) one loader failure on a dict clause in the PROGRAM fails every main row (`ok` line); (4) rd111-rd114 `rdh` answers
  two solutions (`yes` and `tagged`: the var tag unifies with `t`) as swipl.
- Regenerate: edit cases.py, `rm -f *.out *.out2; python3 mk_rows.py; bash run_swipl.sh; python3 mk_rows.py` (cwd evidence/RDDICT; never run `bash run_swipl.sh | head`).

## DONE by the finishing agent (Sonnet, edit-only, 2026-11-02; items 1-3 of the old NOT DONE list)
- 1f4e9b0 tools/mutants/RDDICT.py: 52 mutants (the draft's header said 51). Anchors re-counted with a throwaway `python3 -I` checker (old once in its file, new != old,
  ids unique, targets exist): FOUR had two hits (S1, S3, E3, E4) and got a neighbouring line (E3/E4 `pv = f.dict_pv` + `if pv != 0`; S1 the `ld, f.pin, :dict_position,` line;
  S3 `if t == TK_DICT`); now 52/52 once. Cited rows checked against the pins: D5 cited rd73 (cannot_start_term, never reaches key_expected) -> rd61/rd62/rd63/rd80/rd87;
  A5 -> rm13. Declared omissions kept (maxpri 999, the warning message, `_key_atom`'s punctuation arm, dict_pairs counts, get_token guards). The `old` strings are in pre-fmt style:
  RE-FIT any that `warm.sh fmt` rewraps (the multi-line ones: S1, S3, E3, E4, A1, V2, V4, O3, D12).
- d9c959e test/static_analysis_manifest.jl: 13 entries appended at the end of `_manifest_index(T)` (after the BOOTPRED-dict `]...`; the file's last lines are DISPATCH_EXEMPT, not the
  index). All `false` (may allocate). Signatures read from the sources: is_key_token(token{T}, read_data{T}), _key_atom(token{T}), read_dict_end(pframe, token, read_data),
  read_dict_key(pframe, ct_request, read_data), read_dict_start(pframe, token, ct_request, read_data), read_dict_resume(pframe, ct_request, read_data), end_range(LD, Int),
  setVarTagFlag(LD, T, UInt32), getVarTagFlag(Type{T}, UInt32), dict_order_term_refs(Vector{UInt64}, Int, Vector{Int}, Int), build_dict/build_attvar/build_labeled_subterm(Int, read_data{T}).
  Not run: the gate's `check` shows a wrong tuple.
- the docs commit (tip): docs/architecture.md block "RDDICT" appended at the end (UPSTREAM header, DIVERGES, F1b deferral, tests, mutants).
- Found, not fixed (a source edit, the gate may fold it): src/pl-read.jl:2477 (build_attvar) still says the flag's setter `setVarTagFlag` "is deferred"; it exists now
  (src/os/pl-prologflag.jl:121) and only the set_prolog_flag/2 arm is F1b's.

## NOT DONE
4. The gate (needs a daemon): fmt (`warm.sh send` of the committed files), inventory, check (the Pkg.test-way run of test_read_dict_swipl.jl:
   `tools/pkgtest_way.sh test/core_lang/test_read_dict_swipl.jl`), rows on three term types, type discipline, push mutants/RDDICT at the WIP SHA, branch-gate, term grep,
   push gate/<name> and mutants/RDDICT at the SAME SHA; first compile of all of wip/dict + rddict.
- NOTE FOR THE GATE: another agent (lk-bootfiles) already merged RDDICT, uncommitted, into ~/code/lk-lb4b2-run. Do not touch that tree; check it against wip/rddict before landing.
- Gate-agent flag: the position rows (rd115-rd126) and the mode rows were never run on the kernel; `end_range` and the positions arms are exercised only by them.
- Daemon: this agent used none. lanes.conf and agent.md untouched.
