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

### State after agent 1 (hand-back at the context cap)
Committed on wip/o1a (all in src/pl-fmt.jl, not yet included by LogicKernel.jl, NO Julia run, nothing parsed):
- 7f05923 group 1 (state, PL_format_error/PL_format_arg_error, update_column, outchr, outstring, oututf8, outtext)
- 20c47f2 groups 2-3 (format_predicate refused by name, current_format_predicate fails, format_impl, format_, pl_format2_va/pl_format3_va,
  sub_state/prepare_sub_format/end_sub_format, get_int_expression)
- 0bb1387 group 4 (do_format whole: all directives)
- NEXT COMMIT (this one) groups 5-6: distribute_rubber, emit_rubber, formatInteger, lappend, digitName, countGroups, ths_to_utf8,
  utf8_dp, find_decimal_point, localizeDecimalPoint, groupDigits.

### MUST FIX FIRST (known, not yet applied; the cap hook stopped the agent mid-fix)
1. `where` is a Julia keyword: the `rubber` struct field `where::Int` and every `.where` (do_format `r.where = ...` x3, `emit_rubber`
   `state.rub[ri].where == j`) must be renamed (suggest `place`). One sed: `s/\.where\b/.place/g` and the field line in `mutable struct rubber`.
2. `formatFloat(ld, locale, how, arg, f::number, out::Vector{UInt8})::Bool` is CALLED by do_format but NOT WRITTEN (group 7, pl-fmt.c
   :1455-1893: the GMP paths for V_MPZ/V_MPQ 'f','e','g' are 330 lines; the V_FLOAT path is the tail; pl-write.jl:74-96 `format_float` is the dtoa base;
   `promoteToFloatNumber` for `~h`). It must raise ERR_DOMAIN `not_less_than_zero` for arg<0 (not 'h'), call localizeDecimalPoint(locale, out)
   (and groupDigits for 'f'/'F' when the colon form), and append NO terminating NUL. Read pl-fmt.c from `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/os/pl-fmt.c`.
3. `PL_predicates_from_format` table (group 8) is NOT written: format/2,3 (PL_FA_TRANSPARENT | PL_FA_VARARGS), format_predicate/2 (TRANSPARENT|VARARGS),
   current_format_predicate/2 (NONDETERMINISTIC|TRANSPARENT|VARARGS), as in PL_predicates_from_system.
4. Names I could not verify (no Julia run): `redir_context`, `setupOutputRedirect`, `closeOutputRedirect`, `discardOutputRedirect`, `tellString`,
   `toldString` (B's, see INTERFACE TO B); `PL_is_pair`, `PL_put_integer`, `PL_get_integer` returns Union{Nothing,Int} (checked), `pl_write_term3(ld, 0, t, opts)`;
   `PL_Q_PASS_EXCEPTION` for `~@` (callProlog has no `ex` out: DIVERGES, flag for the audit); `PL_error(ld,"",0,"",ERR_DOMAIN,atom,term)`.
5. `format("a~")` (NUL as the unknown directive): swipl raises existence_error(format_character,'\0'); `codeToAtom(T,0)` is refused (NotPortedError) in the kernel. FLAG.
6. The `~D`/`~I`/`~:d` locale: no stream locale (D9). `format_predicate/2` refused by name (NotPortedError, step "LB5" in the message). Field request for pl-global.jl: NONE.

### STILL TO DO (in order)
group 7 formatFloat (3 commits; see 2) -> group 8 table -> rows (generator `evidence/O1A/gen_rows.py` + `driver.pl` + `.out` via swipl 10.1.19, test/core_lang/test_format_swipl.jl,
prefix `_FM`/`_fm_`; directives ~a ~w ~q ~p ~d ~D ~s ~e ~f ~g ~i ~k ~r ~R ~c ~n ~t ~| ~+ ~`ct ~* ~~, errors; swipl results checked so far:
`format("a~")` -> existence_error(format_character,'\0'); `format("~a")` -> error(format('not enough arguments'),_); `format("~a",[x,y])` -> format('too many arguments');
`format("~d",[a])` -> type_error(evaluable,a/0); `format("~d",[1.0])` -> format_argument_type(d,1.0); `format("~c",[-1])` -> format_argument_type(c,-1);
`format("~1r",[10])` -> domain_error(radix,1); `format("~s",[a])` prints a) -> mutants `tools/mutants/O1A.py` (>= 25, TARGETS test_format_swipl.jl plus every test file that calls format) -> docs and manifest LAST.
Estimated commits left: 3 (float) + 1 (table) + 2 (rows) + 1 (mutants) + 1-2 (docs/manifest) = 8-9. Gate order: WRITER_RULES.md.
Julia was never run on this file: the first gate run will find syntax/name errors; expect a fix commit.
