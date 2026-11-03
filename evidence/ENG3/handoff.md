# ENG3 — the foreign-environment check split out of PL_new_term_ref(s), as upstream (audit D-0379, option 1)

Writer: Opus (allow-opus D-0379), worktree ~/code/lk-eng3, branch wip/eng3 off origin/main c4c34fd. EDIT-ONLY (no Julia run).

## Upstream, read at the pin cbf4e1896275 (~/dev-zone/swipl-devel-cbf4e189)
- pl-fli.c:450-476 `PL_new_term_refs(DECL_LD size_t n)`: ensureLocalSpace + n `setVar`, no check.
- pl-fli.c:479-500 `new_term_ref(DECL_LD)` (static inline).
- pl-fli.c:503-508 `PL_new_term_ref(DECL_LD)`: ensureLocalSpace + new_term_ref(), no check.
- pl-fli.c:535-541 `API_STUB(term_t)(PL_new_term_refs)(size_t n)`: `fli_context <= environment_frame` → fatalError("PL_new_term_refs(): No foreign environment"), then the LD form.
- pl-fli.c:544-550 `API_STUB(term_t)(PL_new_term_ref)()`: the same check, "PL_new_term_ref(): No foreign environment".
- pl-fli.c:563-574 `PL_new_nil_ref(void)` (the check with PL_new_term_ref's text; the kernel has no port of it).
- pl-fli.h:72-74: inside the C kernel `PL_new_term_ref(_)` / `PL_new_term_refs(n)` are macros to the LDFUNC forms, so every
  C file that includes pl-incl.h (all callers in src/, checked file by file) calls the UNCHECKED form; only code linked
  against SWI-Prolog.h (a foreign library, an embedding host) reaches the API stubs.

## Plan (groups, one commit each)
1. src/pl-fli.jl: `PL_new_term_refs` / `PL_new_term_ref` lose the check (the LD forms, upstream's names: the ~315 internal
   callers keep their calls); new `PL_new_term_refs_api` / `PL_new_term_ref_api` (`# PORT: pl-fli.c PL_new_term_ref as
   PL_new_term_ref_api`) = the check + the LD form; the V4a DIVERGES lines go. query_answers (pl-wam.jl, the Julia host
   entry, the foreign-interface surface) calls the `_api` forms.
2. test/foreign/test_query.jl: the two foreign-caller rows call the `_api` forms with the exact error text; a new row:
   in the same no-environment state the LD forms make references at lTop.
3. tools/mutants/ENG3.py (>= 8).
4. test/static_analysis_manifest.jl: two entries (appended block).
5. docs/architecture.md: the pl-fli.jl row text and an ENG3 block at the end.
6. This handoff: the caller classification, unverified spots, the gate command list.
