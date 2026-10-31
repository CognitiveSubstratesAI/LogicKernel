# O1A — src/pl-fmt.jl (writer A of two for O1; edit-only; branch wip/o1a off main faee65f)

Upstream: swipl-devel src/os/pl-fmt.c at cbf4e1896275 (1898 lines). Writer B (wip/o1b) owns the redirect part of
pl-file.c and src/pl-global.jl's redirect fields. This file is O1A's only source file: `src/pl-fmt.jl`.

## PLAN (ordered groups; C line ranges; commits)
| # | group | pl-fmt.c | commits |
|---|---|---|---|
| 0 | this plan | | 1 |
| 1 | state, errors (ERR_FORMAT/ERR_FORMAT_ARG as functions), output primitives: update_column, outchr, outstring, oututf8, outtext | :36-247 | 1 |
| 2 | format_predicate/2, current_format_predicate/2 (D9: table kept, empty until set) | :249-325 | 1 |
| 3 | format_impl, format/2,3, sub_format helpers (prepare/end), get_int_expression | :327-506 | 2 |
| 4 | do_format: text args (a c s i k p q w W @ \*), numbers (d D r R I e f g h), column (t \| +), literals (n N ~) | :508-1017 | 4 |
| 5 | rubber: distribute_rubber, emit_rubber | :1018-1110 | 1 |
| 6 | formatInteger, grouping, decimal point (C locale only, D9) | :1110-1440 | 2 |
| 7 | formatFloat e f g h | :1455-1893 | 3 |
| 8 | PL_predicates_from_format table | :1895-end | with 7 |
| 9 | rows (test/core_lang/test_format_swipl.jl + evidence/O1A generator/driver/.out), mutants tools/mutants/O1A.py | | 2 |
| 10 | docs + manifest (appended blocks), LAST | | 1-2 |

## INTERFACE TO B (what pl-fmt.c needs from pl-file.c; B provides these under these names; Julia signatures chosen to match `Sopenmem`)
Upstream (pl-file.h:104-121):
- `bool tellString(char **s, size_t *size, IOENC enc);`  pl-file.c:2629 — Sopenmem(s,size,"w"), stream->encoding=enc, pushOutputContext
  Julia: `tellString(ld, bufp::Base.RefValue{Union{Nothing,Vector{UInt8}}}, sizep::Base.RefValue{Int}, enc::IOENC)::Bool`
- `bool toldString(void);`  pl-file.c:2642 — pops the output context and closes a memory stream
  Julia: `toldString(ld)::Bool`
- `redir_context` (pl-file.h) with field `.stream::IOSTREAM`:
  `setupOutputRedirect(ld, to::term_t, ctx::redir_context, redir::Bool)::Bool`  pl-file.c:1708 (`to == 0`: current output)
  `closeOutputRedirect(ld, ctx::redir_context)::Bool`  pl-file.c:1774
  `discardOutputRedirect(ld, ctx::redir_context)::Nothing`  pl-file.c:1826
  `redir_context()` zero-argument constructor.
- Scurout is already `Scurout(ld)` / `ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = s` (src/os/pl-file.jl:123, as pl-write.jl:1299 sets it).
- `fd->locale` (format `~:d`, `~:f`): the stream has no locale field; O1A uses the C locale for the colon form too (D9).
Include order for src/LogicKernel.jl (dispatcher): `include("pl-fmt.jl")` AFTER pl-write.jl and pl-file.jl's redirect, BEFORE pl-ext.jl;
O1A does NOT edit LogicKernel.jl, pl-ext.jl or pl-global.jl; the registration table `PL_predicates_from_format` is the
hook for pl-ext.jl (dispatcher wires it, as for PL_predicates_from_system).

## STATE (updated per commit)
(see the log below)

## LOG
