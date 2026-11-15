# TERMHASH handoff (LogicKernel, edit-only; worktree ~/code/lk-termhash, branch wip/termhash, base c1c104f4)

## State at the first agent's hand-back (context cap hit)
- COMMITTED: nothing before this file. UNCOMMITTED in the worktree: `src/pl-error.jl` gained `PL_get_int64_ex`
  (after `PL_get_long_ex`; returns `Union{Nothing,Int}`, errors representation_error(int64_t) / type_error(integer, T)).
- NOT STARTED in the tree: every edit of `src/pl-termhash.jl`, `src/pl-prims.jl`, the rows, mutants, cost lines.
- Scratch (outside the repo, may be gone): scratchpad dir of session b1bc52d9 holds Python models (`mm.py`, `vs.py`,
  `t*.py`) that REPRODUCE every swipl value listed below; upstream sources dumped there (`pl-termhash.c`, `pl-prims.c`,
  `pl-gmp.c`). Re-dump with `git -C ~/dev-zone/swipl-devel show 18168e62:src/<file> > <scratch>`.

## Findings (all checked against ~/.local/bin/swipl 10.1.20 with a Python model, values equal)
- Existing kernel: `src/pl-termhash.jl` has `termHashValue`/`th_*`/`pl_term_hash`, the SHA-1 and incremental Murmur
  ports, `variant_sha1_walk!`, `variant_hash`, `pl_variant_hash`, `pl_variant_sha1_2_va`; the table
  `PL_predicates_from_termhash` has only `variant_sha1/2`. Its values are NOT swipl's (atoms hash `sym_hash`, numbers
  `gnd_key`; test_bootpred3_swipl.jl row bp3v15 lists variant_sha1's digest as a KNOWN difference: pin line 365 is swipl's
  `cee71ebc1d023af131e3461b322e4251b2e5a510`, `_B3_KNOWN` line ~375 is the kernel's; when the values equal swipl's, that
  known row must be removed from `_B3_KNOWN` and the header comment line 10 reworded).
- The interface (src/term_interface.jl) gives everything needed: `sym_text`, `is_blob`, `blob_type`,
  `is_reserved_symbol`, `number_kind` (NUM_INTEGER/RATIONAL/FLOAT/STRING/OTHER), `integer_is_int64`, `int64_value`,
  `bigint_value`, `rational_value`, `float_value`, `string_value`. So the swipl values ARE reachable (no forced divergence)
  except BLOB atoms (no text) and NUM_OTHER.
- `export_cells` (pl-comp.jl:508) makes an attributed variable a plain variable and throws ArgumentError on a cycle.
  Cells helpers: `is_acyclic_cells(ld, -(A1+1))` (pl-prims.jl:1071), `term_variables_to_termv_cells(ld, t, maxcount, flags)`
  -> `(count, v0)` with `TV_ATTVAR` (pl-prims.jl:3772/3731). `term_canonical_form` is pl-bisim.c (not in the kernel).
- Refusal pattern: `throw(NotPortedError{T}(culprit::T, what::String, step::String))` (struct in pl-comp.jl:796).
- upstream: term_hash/2, variant_hash/2, variant_sha1/2 in pl-termhash.c (table order variant_sha1, variant_hash, term_hash);
  term_hash/4 = `term_hash4` in pl-prims.c (O_TERMHASH is defined), table entry after `unifiable/3`.

## Formulas (Murmur = MurmurHashAligned2 of pl-hash.jl; SEED = MURMUR_SEED; all validated)
- atom hash_value = Murmur(text bytes, SEED); text bytes = Latin-1 if every code <= 0xff, else UCS-4 little endian
  (4 bytes per code). `[]` (reserved symbol) hashes as its text "[]" (same as the text atom '[]').
- term_hash/2: primitive = Murmur over the bytes into the RUNNING hash. atom: the 4 bytes of hash_value; small int
  (PLMINTAGGEDINT <= v <= PLMAXTAGGEDINT, i.e. -2^56..2^56-1): 8 bytes int64; any other integer: words
  [2*s] ++ limbs (s = signed limb count of |v|, 64-bit limbs little endian), as bytes; rational (not integer): words
  [(2*sn)|1, (2*nd)|1] ++ num limbs ++ den limbs, sn signed, `(sn<<1)|1` in two's complement; float: 8 bytes of the double;
  string: Latin-1 bytes if all codes <= 0xff, else UTF-8 bytes. 0 and 0.0 hash equal (swipl: term_hash(0)=754250009).
  compound: h0 = Murmur(4 bytes of atom hash of the functor NAME, SEED); each primitive argument folds into h; a compound
  argument's finished hash folds in as 4 bytes. The existing th_* structure already does this: only
  `primitiveHashValue` (atom: `_atom_hash` instead of sym_hash; GND by number_kind) and `th_start_term` (name = atom hash)
  change. Pins: foo 4132911164, a 45085902, '' 17268846, [] 1269818963, 0 754250009, 1 3261798158, -1 2513478484,
  42 1220239556, 1.5 3768511644, "abc" 3642536006, "" 1747181055, "é" 1955271470, é 1745793758, 日本 2415530588,
  "日本" 1530431058, f(a) 591282682, f(a,b) 3162476597, [a,b] 3640712072, f(g(h(a))) 4144289781,
  foo(bar,"baz",1,2.0) 3657889658, 2^56-1 -> 4113862117, -2^56 -> 2329647695, -2^56-1 -> 1361206487,
  2^63 -> 2106756840, 2^70 -> 1859486738, 1r3 3386870198. A variable anywhere: term_hash/2 leaves A2 unbound (succeeds).
- variant_sha1 bytes (SHA-1) / variant_hash (Murmur stream, 256-byte blocks as the existing hash_state, result
  `& PLMAXTAGGEDINT32` = 24 bits): variable `V` + u64((i<<7)|MARK(1<<5)) (existing code); atom `A` + u64(len bytes) +
  text bytes + type name ("text", "ucs_text" for a wide atom, "reserved_symbol" for []; a blob: its type name and, as
  payload, the 8 bytes of sym_hash: DIVERGES); small int `i` + 8 bytes; other integer `I` + mpz words; rational `I` +
  mpq words; float `F` + 8 bytes; string `S` + data = ('B' + Latin-1 bytes) or ('W',0,0,0 + UCS-4 LE), zero-padded to
  `lw*8` bytes with `lw = (len+8) div 8`; compound with symbol head `T` + u64(len name bytes) + name bytes + u64(arity)
  (no type name); $expr head keeps `C` + arity (DIVERGES). Pins: foo cee71ebc1d023af131e3461b322e4251b2e5a510, "abc"
  81e8bef6281596b8c6e313bfa6dbbe646f7de396, 日本 atom 09f44177826f274efdd4eb55a847c3918edf617e, "日本"
  0217ac88dce085c311bda55689e3badb55e8e46d, f(a,b) 0389c875125382d77ac0aa20c137af5a56ce289a, 2^63
  0bbdf5fed8abf9596db201c1756af08d74bbc3d8, 1r3 aae1086f595813f43783c391cb20b568fe6fb664, numlist(1,40) list
  6105ed8851e8ac3a2acf5a0907d5367cc9aaf027 (variant_hash 3959081), foo variant_hash 2798916.
- Errors: variant_sha1 of a term with an attributed variable (anywhere in the term, attributes not walked):
  `type_error(free_of_attvar, Term)` (E_ATTVAR); variant_hash/2 hashes an attvar as a plain variable. A CYCLIC argument
  upstream hashes its canonical form (pl-bisim.c `term_canonical_form`, absent from the kernel): refuse by name,
  `NotPortedError{T}(mk_sym(T,:term_canonical_form), "...", "R2 ...")`, after an `is_acyclic_cells` test. term_hash/2 of a
  cyclic term: CYCLE_CONST path, same refusal (owner R2). Probe the cyclic and attvar cases in swipl BEFORE writing rows
  (not probed yet). A cyclic row stops the kernel's run at that row (the harness returns on notported): put cyclic rows
  LAST, pin swipl's answer in the .out and expect `tN notported` from the kernel (known difference, comment with swipl's).
- term_hash/4 (pl-prims.c): depth via `PL_get_int64_ex` (A2), `depth < -1` -> `domain_error(not_less_than_zero, A2)`;
  range via `PL_get_integer_ex` (A3), `range < 1` -> `domain_error(not_less_than_one, A2)` (sic: A2, the DEPTH);
  `depth != 0`: hash with termHashValue (variable -> succeed without binding), result `hraw % range`; depth 0 -> SEED % range.
  Compound: `atom_hashvalue = name hash + arity` as 8 bytes (size_t, no 32-bit wrap) folded into the running hash, then
  `--depth != 0` descends into the arguments with the decremented depth (-1 never reaches 0); primitives as /2 except a
  wide string (swipl itself has undefined behaviour there: no row; kernel hashes UTF-8, DIVERGES, wording without the
  D-0164 terms). Iterative walk planned with five parallel stacks (term, off, arity, next index, depth).
  Pins (depth, range): foo 1 100 -> 64; f(a,b) -1 1000 -> 910; f(a,b) 1 1000 -> 159; f(a,g(b,c)) 2 1000000 -> 604359,
  1 -> 674159, 0 -> 132426, 3 -> 906817; f(X,g(b,c)) -1 -> unbound; X 0 10 -> 6; X 1 10 -> unbound; "abc" 1 1000 -> 6;
  1.5 -> 644; 42 -> 556; foo 1 2147483647 -> 1985427517; [a,b,c] -1 1000000 -> 107381; g(h(i(j))) 2 1000000 -> 1790;
  foo 0 1 -> 0. Errors: depth -2 domain_error(not_less_than_zero,-2); range 0 or -5 domain_error(not_less_than_one,1);
  depth a type_error(integer,a); range b type_error(integer,b); depth 1.0 type_error(integer,1.0); unbound depth/range
  instantiation_error; depth 10^20 representation_error(int64_t); range 10^11 or 2^31 representation_error(int);
  A4 = x: fails.

## PLAN (next agent; edit-only, no julia)
1. src/pl-termhash.jl: replace the DIVERGES header (text drafted in the first agent's head: atomic data now SWI's except
   blobs and NUM_OTHER; cyclic argument refused, attvar error raised by the registration); add helpers `_text_is_latin1`,
   `_push_le!`, `_atom_text_bytes`, `_atom_hash`, `_atom_payload` (bytes, type name), `_limbs`, `_mpz_words`, `_mpq_words`,
   `_words_bytes`, `_string_data` (variant form), `_gnd_data(p)` -> `(tag::Char, bytes)` or nothing; rewrite
   `primitiveHashValue`, `th_start_term`, the `variant_sha1_walk!` branches (SYM, GND, EXPR with symbol head), simplify
   `_HASH_str!`; add `_hash_export` (acyclic test + export_cells, refusal), `_variant_arg` (SHA1: attvar test through
   `term_variables_to_termv_cells(ld, A1, 1, TV_ATTVAR)` then `PL_error(ld, ERR_TYPE, mk_sym(T,:free_of_attvar), A1)`),
   `pl_term_hash_2_va`, `pl_variant_hash_2_va`, make `pl_variant_sha1_2_va` use `_variant_arg`; the table in upstream order
   variant_sha1, variant_hash, term_hash with the DIVERGES line of the table removed. Each with `# PORT: pl-termhash.c <name>`.
2. src/pl-prims.jl: `termHashValue4` (iterative) + `pl_term_hash_4_va` before the `# PORT: pl-prims.c BeginPredDefs` comment
   (line ~4662), table entry `PL_extension("term_hash", 4, pl_term_hash_4_va, PL_FA_VARARGS)` after `unifiable`.
3. test/core_lang/test_bootpred3_swipl.jl: drop the bp3v15 known row (line ~375 and the header comment), keep the pin.
   Check test/core_lang/test_hash.jl (not read) for assertions that expect the old divergent values.
4. Rows: test/core_lang/test_termhash_preds_swipl.jl/.pl/.out (model test_dwim_swipl.jl: DRIVER, `kernel_lines`, compare;
   run swipl twice under `systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64`, outputs
   byte-identical; rows for the pins above + errors + attvar (put_attr) + cyclic last).
5. Manifest entries (test/static_analysis_manifest.jl), tools/mutants/TERMHASHP.py (format of DICTREC.py lines 1-40), cost
   lines in test/pkgtest_costs.tsv and test/unit_costs.tsv. Commits: `UPSTREAM: pl-termhash.c term_hash variant_hash
   (swipl-devel 18168e62)`, `TEST: TERMHASH rows`, `TEST: TERMHASH mutants and cost lines`; bodies 3-6 lines with
   "test_type_discipline.jl and warm.sh check NOT run"; end with the Co-Authored-By line from the brief.
- Hook facts seen: the empty-result PostToolUse hook warns on a zero-hit grep (advisory). The 150k cap hook blocks every
  Bash call; it also blocked the first python edit of pl-termhash.jl (nothing was written).

## STATE after TERMHASH2 piece 1 (second agent; stopped on audit D-0794, no new code until the weekly reset)
- COMMITTED (wip/termhash 92269d16): src/pl-termhash.jl complete for item 1: header DIVERGES rewritten; helpers
  `_text_is_latin1`, `_push_le!`, `_atom_text_bytes`, `_atom_hash`, `_atom_payload`, `_limbs`, `_signed_word`, `_mpz_words`,
  `_mpq_words`, `_words_bytes`, `_string_data`, `_string_hash_bytes`, `_gnd_data(p, variant)`; `primitiveHashValue`,
  `th_start_term`, `_HASH_bytes!`/`_HASH_str!`, `variant_sha1_walk!` rewritten; `_variant_arg(ld, A1, sha1)` (cyclic refusal naming
  term_canonical_form; TV_ATTVAR scan inside a foreign frame, `type_error(free_of_attvar, A1)`), `_term_hash_arg(ld, A1)`
  (cyclic refusal, culprit `term_hash`), `pl_variant_hash_2_va`, `pl_term_hash_2_va`, `pl_variant_sha1_2_va` via `_variant_arg`,
  table `PL_predicates_from_termhash` = variant_sha1, variant_hash, term_hash. Nothing was run (no julia; the file has never been
  parsed by Julia: first `warm.sh check` may find typos).
- NOT STARTED (items 2-5): `termHashValue4` + `pl_term_hash_4_va` in src/pl-prims.jl (before `# PORT: pl-prims.c BeginPredDefs`, table entry
  after `unifiable`); design is settled: iterative walk, five parallel stacks (term, off, arity, next, depth); entering a compound
  folds 8 bytes `UInt64(_atom_hash(name)) + arity` (name 0 for a non-symbol head, `_comp_shape` gives `(off, arity)`), then `d -= 1`, and
  arguments are walked only when `d != 0`; primitives via `primitiveHashValue` (wide string = UTF-8: DIVERGES comment worded "swipl's
  wide-string case gives no stable answer to pin"); the registration uses `PL_get_int64_ex(A2)`, `depth < -1` -> `PL_domain_error(ld,
  "not_less_than_zero", A2)`, `PL_get_integer_ex(A3)`, `range < 1` -> `PL_domain_error(ld, "not_less_than_one", A2)`, `depth != 0` ->
  `termHashValue4(_term_hash_arg(ld, A1), depth)` (nothing = unbound variable: succeed), result `hraw % UInt32(range)`, `PL_unify_integer(A4)`.
  Then: remove row bp3v15 and reword the header comment (~line 10) in test/core_lang/test_bootpred3_swipl.jl; `grep -n` term_hash /
  variant_hash in test/core_lang/test_hash.jl for assertions on the old values (list, do not change); manifest entries in
  test/static_analysis_manifest.jl (near line 85-92 and 3912; new: `_atom_hash`, `_atom_payload`, `_gnd_data`, `_variant_arg`,
  `_term_hash_arg`, `pl_variant_hash_2_va`, `pl_term_hash_2_va`, the other helpers, `termHashValue4`, `pl_term_hash_4_va`); owner rows in
  docs/r2_owners.tsv: keys `refusal:src/pl-termhash.jl::_variant_arg::the digest of a cyclic term (its canonical form, pl-bisim.c term_c`
  and `refusal:src/pl-termhash.jl::_term_hash_arg::the hash of a cyclic term (pl-termhash.c CYCLE_CONST, pl-prims.c visited)` (first 60
  chars of each `what`: verify by `grep -n` in src/pl-termhash.jl before writing), owner R2.
- In my head only: nothing beyond the above (the formulas are in this file). A note: the type_error attvar test and refusals use
  `mk_sym(T, ...)`; Python model check of a 7-char string's variant_sha1 padding (`(len+8) div 8`, len incl. the B tag byte) matched swipl.
