# RDDICT handoff (step RDDICT, D-0363 item 3) — branch wip/rddict off wip/dict a772c27 (worktree ~/code/lk-dict)
The reader's DICT branch. Pin: swipl-devel cbf4e189 (10.1.19). Edit-only; NOTHING compiled or run (no daemon slot).

## Boot dict syntax (pin boot/*.pl, grep `_{` and `Tag{`)
- boot/init.pl:1297  `'$merge_options'(_{file_type:regular}, Options1, Options2)`
- boot/syspred.pl:1529  `'$merge_options'(_{quoted:true}, Options, Options1)`
- boot/autoload.pl:889  `_{module:Module, exports:Exports, file:PlFile} :< Info.`
- boot/messages.pl:1888  `{ _{level:Level, start:Time} :< Dict`
- boot/messages.pl:256,258  text only (`_{...}` inside a quoted message): not syntax.
- boot/build_home.pl:83,86  `~w/src/swipl{,.exe,.js}` inside a quoted atom: not syntax.
(Functional notation `Dict.key` in boot/dicts.pl etc. is a later reader/expansion piece: NOT part of this step.)

## Plan (ordered groups; one commit each)
1. plan (this file).
2. UPSTREAM: pl-dict.c dict_order_term_refs (pin src/pl-dict.c:280-340) -> src/pl-dict.jl; pl-incl.h VARTAG_* constants (pin
   src/pl-incl.h:1176-1181) -> src/pl-incl.jl.
3. UPSTREAM: pl-read.c build_dict (4392-4490), build_labeled_subterm (4270-4304), build_attvar (4306-4390) -> src/pl-read.jl,
   after `build_term`.
4. UPSTREAM: pl-read.c read_dict_end/read_dict_key/read_dict_start/read_dict_resume (6072-6240), is_key_token (6043-6065),
   end_range (5567-5575), pf_kind PF_DICT frame fields (4797-4800), start_pframe/resume_pframe branches (6466, 6492);
   the refusal branch (src/pl-read.jl start_pframe PF_DICT) removed.
5. rows (evidence/RDDICT/mk_rows.py -> test/core_lang/test_read_dict_swipl.jl, swipl 10.1.19 pins) + tools/mutants/RDDICT.py.
6. docs/architecture.md block appended.  7. test/static_analysis_manifest.jl entries.
