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

## State at the PAUSE (coordinator, audit D-0360 item 1: one burner) — wip/rddict, linear on wip/dict a772c27, not pushed
Written, UNRUN (nothing compiled): group 1 plan (b484d4f); group 2 `dict_order_term_refs` (src/pl-dict.jl, before get_name_ex) +
VARTAG_* constants (src/pl-incl.jl) (6429ce6); group 3 `build_labeled_subterm`, `build_attvar`, `build_dict` (src/pl-read.jl, inserted
before the "operator queues" header, after `build_term`) — SHA in `git log` (the commit after 6429ce6).
NOT STARTED: groups 4 (read_dict_*), 5 (rows + mutants), 6 (docs), 7 (manifest).

## Pin line ranges read (pl-read.c at cbf4e189; `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/pl-read.c`)
- tokenizer TK_DICT/TK_VCLASS_DICT/TK_VOID_DICT: 3813-3817, 3844-3858, 4002-4004 — ALREADY in src/pl-read.jl (2140-2143, 2218, 2267).
- build_attvar 4306-4390, build_dict 4392-4490, build_labeled_subterm (just before 4306) — WRITTEN (group 3).
- pf_kind PF_DICT :4739, pframe union member `dict {pv, pairs}` :4797-4800 -> Julia pframe needs fields `dict_pv::term_t`, `dict_pairs::Int`
  (pframe's positional constructor call is at src/pl-read.jl `pframe{T}(` in complex_term: append two zeros).
- end_range :5567-5575 = `valInt(argTerm(*p,1))` = `get_int_arg(ld, positions, 2)` (the stub comment for end_range sits before
  "the constructs: lists, brackets, compounds" in pl-read.jl: replace it).
- is_key_token :6043-6065 (TK_NAME/QNAME/FUNCTOR/DICT true; TK_PUNCTUATION false for [ { ( ) } ] | , else true; else false).
- read_dict_end 6082-6092, read_dict_key 6101-6162, read_dict_start 6167-6217, read_dict_resume 6222-6239 (macros P_HEAD pv+0, P_ARG pv+1,
  P_VALUE pv+2). Dispatch: simple_term kind 6407-6410 (done in Julia), start_pframe 6466, resume_pframe 6492 (Julia: src/pl-read.jl start_pframe
  currently throws the refusal for PF_DICT, resume_pframe has no PF_DICT arm).
## Design notes for read_dict_* (Julia idioms checked)
- Positions: `_unify_position!(ld, f.pin, :dict_position, (token.start, _POS_VARIABLE, token.start, token.end_), (pv + 1,))` with pv=PL_new_term_refs(ld,3).
  key_value_position/7 has a nested `-`/2 and a key word: write by hand like `_unify_position!` (alloc_compound! with `_err_functor(ld, :key_value_position, 7)`,
  ints via `_gnd_word!(ld, mk_gnd(T, v))`, key cell = the key's word `ts.words[key_term]`, `-`(kstart,kend) a second compound, last cell `_cell_link!(ld, p+7, pvalue+1)`).
- Key token -> key_term = alloc_term; atom: `_setHandle!(key_term, _token_atom(key), rd)`; small int (`n.type == V_INTEGER`, `valInt(consInt(i)) == i` as pl-list.jl:456):
  `_setHandle_w!(key_term, consInt(n.i), rd)`; other numbers: syntaxError("key_domain"); other tokens: syntaxError("key_expected") (`return Int(syntaxError(..))` pattern of simple_term).
- Colon test: compare WORDS `_word_of!(ld, _token_atom(sep)) == _word_of!(ld, mk_sym(T, Symbol(":")))` (T values have no `==` used in this file); `{}` end test: tstart.type == TK_NAME and atom word == that of `mk_sym(T, Symbol("{}"))` (the tokenizer makes `{}` and `{ }` TK_NAME, pl-read.jl:2193).
- `get_token` returns the SHARED token object? CHECK (pl-read.jl:2067) — upstream saves kstart/kend before fetching `sep`; do the same.
- read_dict_key stop/max: `req.stop = ",}"; req.maxpri = 999; req.positions = pv != 0 ? pv + 2 : 0`; return CTR_SUB. read_dict_resume: `f.dict_pairs += 1`; token `,` -> read_dict_key else read_dict_end.
- An edge: a punctuation key token (paired bracket char) has no `.atom` in Julia (upstream reads a union): mirror as `mk_sym(T, Symbol(Char(c)))` and note it.
- Then edit: start_pframe's PF_DICT branch -> `read_dict_start`, resume_pframe PF_DICT -> `read_dict_resume`; fix the DIVERGES comments of pframe, start_pframe, complex_term (they say dicts are refused).
## swipl 10.1.19 probe results (expected values for rows; `term_string(T, S)`, LC_ALL=C)
`_{}`, `_{a:1}`, `T{k:v,k2:v2}` read as dicts (var tag stays a variable); `t{b:1,a:2}` prints `t{a:2,b:1}`; keys atoms, small ints, `[]`, '' ok; negative `-1` key ok;
`_{a:1,a:2}` -> syntax_error(duplicate_key(a)); `_{a}` colon_expected; `_{a:1` operator_expected (at EOF text); `_{1.5:a}` key_domain; `_{99999999999999999999:1}` key_domain;
`_{f(x):1}` colon_expected; `_{a:1,}` and `t{a:1,,b:2}` key_expected; `_{"s":1}` key_expected; `_{a:-}` colon_expected; `_{a:1}{b:2}`, `1{a:2}`, `"s"{a:2}` operator_expected;
`'x y'{a:2}` reads; `_{ }` reads as `_{}`; `t{a:1}.b` reads (functional notation: a `'$dot'`-style call term, NOT this step).
## Flags for the audit
1. VARTAG: the `var_tag` Prolog flag setter (os/pl-prologflag.c:526-560, setVarTagFlag/getVarTagFlag) is not in the kernel; build_dict's ERROR/WARNING/DYNDICT/ATTVAR arms and build_attvar are
   written but reachable only through module flags set from Julia. A separate small step ports the flag (owner: dispatcher).
2. DIVERGES (representation only, in comments): build_* errors go through the read data (`errorWarning`), as every syntax error in this reader.
3. Functional notation on dicts (`X.key` in clause bodies) is boot/expand.pl + pl-read.c dot handling: not in this step; list for the audit if boot/dicts.pl needs it at read time.
## Gate (after the writer): fmt (warm.sh send), inventory, check, rows on three term types, type discipline, pkgtest_way, mutants branch, branch-gate, term grep, FRESH gate name; first compile of all of wip/dict + rddict.

## State after the READER agent (Sonnet, audit D-0368 item 2) — wip/rddict, linear, NOT pushed, NOTHING compiled or run
Commits: 0bcfe25 (build_*), 3665757 slice 1 (dict branch), 5920f01 slice 4 (var_tag setter/getter); this handoff is the next commit.
- Slice 1 (3665757, src/pl-read.jl): `is_key_token` (pin pl-read.c 6043-6065), `read_dict_end/key/start/resume` (6072-6239),
  `end_range` (5567-5575, stub comment replaced), pframe members `dict_pv`, `dict_pairs` appended at the END of pframe (4797-4800;
  the one positional constructor call in complex_term got two zeros), start_pframe PF_DICT -> read_dict_start and resume_pframe
  PF_DICT -> read_dict_resume (6466/6492); the refusal is removed; the comments that said dicts are refused are fixed. Helper
  `_key_atom` (ORIGINAL): a punctuation key token has no `.atom` field, its atom is the character's. CHECKED: `get_token` returns the
  SHARED `rd.token`, so kstart/kend are read before `sep` is fetched. key_value_position/7 and dict_position/5 are laid out on the cells.
- Slice 2 (dict-DOT): NO CODE TO PORT. The pin's pl-read.c has no dict-specific dot handling (grep over functional/ATOM_dict/$dot/dict_ finds only
  build_dict and read_dict_*). The whole mechanism is generic and ALREADY in the kernel: (a) the `.` operator `op(100, yfx, .)` in the system module
  (pin pl-op.c:748; src/pl-op.jl:529); (b) the tokenizer: `.` followed by a non-blank is a symbol-char name token (pin pl-read.c:3931-3938;
  src/pl-read.jl:2172-2178) and the raw reader ends a clause only at `.<blank>|%|EOF` (pin :1916-1925; src/pl-read.jl:896); (c) build_op_term/
  build_term make `'.'(A,B)` (dotlists false; pin 5851-5856 = src/pl-read.jl read_compound_end). swipl 10.1.19 `term_string` + `write_canonical`:
  `Ctx.get(stack)` -> `'.'(_,get(stack))`; `_{a:1}.put(b,2)` -> `'.'(_{a:1},put(b,2))`; `X.y.z` -> `'.'('.'(_,y),z)`. The functional-notation
  EXPANSION is boot/expand.pl + boot/dicts.pl (Prolog, runs unchanged on wip/dict's `./3`, put_dict, get_dict_ex). Rows for these three reads belong
  to the rows agent.
- Slice 3 (module VARTAG read default): NO STRUCT CHANGE needed. Upstream keeps var_tag in the VARTAG_* bits of `module->flags`; `module_t.flags::UInt32`
  already exists and 0xe00 collides with no M_* flag (src/pl-incl.jl:927-990); `set_module_read_data` copies `module.flags` into `rd.flags`; a module
  starts with VARTAG_DICT = 0 (src/pl-modul.jl:220 sets only M_CHARESCAPE), so `_{..}` reads as a dict with a variable tag in every boot module,
  exactly as upstream's default. build_dict's arms read `rd.flags & VARTAG_MASK` (0bcfe25). Scan row 5 is closed by this reading (no field to add).
- Slice 4 (5920f01, src/os/pl-prologflag.jl): `setVarTagFlag` (pin os/pl-prologflag.c 526-560, domain_error(var_tag, A)), `getVarTagFlag` (562-573) wired into
  `unify_prolog_flag_value` (pin :2088); header comment fixed. NOT written: the `set_prolog_flag/2` arm (pin :1383) — the write side of the flag table is F1b's
  (no `set_prolog_flag` function exists in the kernel yet); the rows agent can test the setter/getter as functions. The two errors messages.pl:255-257 uses
  (syntax_error(var_tag), syntax_error(warning_var_tag)) are raised by build_dict.
- Struct change flag: pframe (a mutable struct in pl-read.jl) got 2 fields (dict_pv, dict_pairs) at the END: pframe is read-internal, not an alloc-pinned
  engine struct; no module_t change.
- UNVERIFIED on the kernel: gate decides, for everything above. DIVERGES (representation only, D-0365 item 3): the build_* errors go through the read data.
- NEXT agent: rows (evidence/RDDICT/mk_rows.py -> test/core_lang/test_read_dict_swipl.jl) using the probe results above plus the dot reads, the
  var_tag getter/setter rows; tools/mutants/RDDICT.py; docs/architecture.md block; static_analysis_manifest entries (new functions: is_key_token, _key_atom,
  read_dict_end, read_dict_key, read_dict_start, read_dict_resume, end_range, setVarTagFlag, getVarTagFlag, dict_order_term_refs, build_*); then the gate
  (fmt: the long `tstart.type == TK_NAME && ...` line in read_dict_start and the one-line end_range will be re-flowed by warm.sh fmt).
