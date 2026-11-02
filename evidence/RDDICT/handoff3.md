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

## NOT DONE (the cap ended this agent at ~155k; the next agent is fresh)
1. tools/mutants/RDDICT.py: the draft is evidence/RDDICT/mutants_draft.py (51 mutants, anchors counted once in a text count EXCEPT the ones noted in its
   header that I wrote as 2-line anchors: re-count them, and re-count all with a throwaway `python3 -I` checker: old once, new != old, ids unique,
   targets exist). Copy it to tools/mutants/RDDICT.py (own commit, subject `ADDED: RDDICT mutant list ...`). Check that the cited row ids still match
   the cases (rd numbers: group 1 rd01-rd38, group 2 rd39-rd54, syntax errors rd55-rd92, dots rd93-rd105, clause rows rd106-rd114, positions rd115-rd126,
   key/tag edge rd127-rd152; `python3 mk_rows.py` numbers them in order).
2. static_analysis_manifest entries APPENDED AT THE END of test/static_analysis_manifest.jl: is_key_token, _key_atom, read_dict_end, read_dict_key,
   read_dict_start, read_dict_resume, end_range, setVarTagFlag, getVarTagFlag, dict_order_term_refs, build_dict, build_attvar, build_labeled_subterm
   (look at neighbouring entries for the type tuples); own commit.
3. docs/architecture.md block APPENDED AT THE END: UPSTREAM header names pl-read.c, pl-dict.c, os/pl-prologflag.c; DIVERGES: the build_* errors go through
   the read data (errorWarning); the set_prolog_flag/2 arm (pl-prologflag.c:1383) deferred to F1b; var_tag module default needs no struct change; own commit.
4. Then the gate (needs a daemon): fmt (`warm.sh send` of the committed files), inventory, check (the Pkg.test-way run of test_read_dict_swipl.jl:
   `tools/pkgtest_way.sh test/core_lang/test_read_dict_swipl.jl`), rows on three term types, type discipline, mutants branch, branch-gate, term grep, fresh gate name;
   first compile of all of wip/dict + rddict.
- Gate-agent flag: the position rows (rd115-rd126) and the mode rows were never run on the kernel; `end_range` and the positions arms are exercised only by them.
- Daemon: this agent used none. lanes.conf and agent.md untouched.
