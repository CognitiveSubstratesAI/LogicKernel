# TTY1 handoff (branch wip/tty in ~/code/lk-tty, made off c1c104f4)

## Committed
- 252ccd5e UPSTREAM: pl-term.c tty_size tty_put tty_goto tty_get_capability (swipl-devel 18168e62):
  src/pl-term.jl (new), include in src/LogicKernel.jl (before pl-ext.jl), `PL_predicates_from_term` after termhash's in
  src/pl-ext.jl (`_PRED_TABLES`, `_FOREIGN_VA`), manifest entries in test/static_analysis_manifest.jl.
- The rows' program test/core_lang/test_tty_swipl.pl (rows t0-t7 pinned, lk0-lk3 LK-ONLY) is in the second commit of this
  hand-off (WIP; the .jl and .out are NOT written yet).

## What the code is (src/pl-term.jl)
- tty_size/2: upstream (pl-term.c:403-456) reads `Sfileno(Suser_input)` (0 if < 0) and does `ioctl(fd, TIOCGWINSZ)`; NO stream
  struct field is read, so NO struct change (the audit's owner row "needs a tty_size field on the stream struct" does not match
  this upstream version; docs/r2_owners.tsv has no tty_size line to change). fd = `_std_fileno(ld, Suser_input(ld))`, -1 -> 0.
  `_tty_winsize(fd)` = ccall ioctl, returns (iorval, rows, cols, errno); `_tty_size_answer(ld, r, c, iorval, rows, cols, errno)`
  is the tail (system_error with MSG_ERRNO, else unify rows and cols): a direct call with a FAKE winsize result is the LK-ONLY
  row of the terminal path (no pty needed).
- tty_get_capability/3, tty_goto/2, tty_put/2: argument checks and error terms as upstream; `initTerm` keeps the TERM check
  (unset or >= 100 bytes: existence_error(environment,'TERM')); libtinfo calls raise `NotPortedError{T}(.., .., "TTY2")` at
  4 sites: initTerm (tgetent), lookupEntry (tgetnum/tgetflag/tgetstr), pl_tty_goto2_va (tgoto/tputs), pl_tty_put2_va (tputs).
- Named divergence: `term_initialised` state (STAT_ERROR after the first failed TERM lookup: later calls fail silently in swipl,
  tty_goto then raises existence_error(terminal_capability,cm) with context(tty_goto/2,_)) is NOT kept (GD->terminal is a struct
  change, left to TTY2): the kernel raises the TERM error on every call. Hence the pinned TERM rows are FIRST-CALL rows, one swipl
  process each (t4-t7).

## Pin facts (probed on the pin, stdin /dev/null, systemd-run scope drops TERM so TERM is unset there)
- tty_size(_,_) -> error(system_error, context(tty_size/2, 'Inappropriate ioctl for device'))
- tty_get_capability(1,string,_) -> type_error(atom,1), context(system:tty_get_capability/3,_); (foo,1,_) -> type_error(atom,1)
- tty_goto(a,1) -> type_error(integer,a), context(system:tty_goto/2,_)
- tty_put(foo(x),1) -> type_error(string,foo(x)); (abc,a) -> type_error(integer,a)
- FIRST call with TERM unset: tty_goto(1,2), tty_get_capability(co,foo,_), (co,number,_) all
  existence_error(environment,'TERM'), context(system:<pred>,_); later calls in the same process differ (state, above).
- tty_put(abc,1) writes "abc" to stdout (tputs): kept out of the pinned program (lk0/lk1 are LK-ONLY refusals).

## Left to do (in this order)
1. Pin generation: script is described here because it could not be written (cap): driver = the DRIVER text of
   test/core_lang/test_dwim_swipl.jl (copy to a scratch file); per group append `:- initialization((fz_run('<pl>', [Names]), halt)).`
   and run `systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64 env -u TERM <pin swipl> -q drv.pl < /dev/null 2>/dev/null`
   (pin: ~/.local/swipl-pin1-18168e62/bin/swipl). Groups: [t0,t1,t2,t3] with `env -u TERM`; t4, t5, t6 each alone with `env -u TERM`;
   t7 alone with `env TERM=<100 x>`. test_tty_swipl.out = group 1's lines (ok + 4 rows) then the row line of each of t4-t7
   (drop each later run's `ok`). Run it TWICE, `cmp` byte-identical, report.
2. test/core_lang/test_tty_swipl.jl modelled on test_dwim_swipl.jl: same enc/kernel_lines/DRIVER; kernel_lines per group inside
   `withenv("TERM" => nothing)` (t7: `withenv("TERM" => "x"^100)`); live swipl check via `Cmd(["env","-u","TERM",swipl,"-q",f])`
   with `pipeline(...; stdin=devnull, stderr=devnull)`; row t3 compared only when `LK._tty_winsize(0)` gives rc != 0 and errno == 25
   (else @info skip); LK-ONLY: lk0-lk3 with TERM "xterm" give `<name> notported` (kernel_lines prints that); `_tty_winsize` on an
   opened file's fd and on fd 9999 -> (-1,0,0,25) and (-1,0,0,9); `_tty_size_answer` direct call (PL_new_term_refs(ld,2), error read
   with `lk_answer(ld, LK.PL_exception(ld,0))`, success unifies (24,80), bound-mismatch fails) on all 3 term types (`lk_term_type`).
3. Mutants tools/mutants/TTY.py (format: DICTREC.py lines 1-40), TARGETS = core_lang/test_tty_swipl.jl, plus any test that
   registers the built-in tables (test_static_analysis? the manifest) ; ids unique; "aimed by <rows>"; no `equivalent=`.
4. Cost lines `core_lang/test_tty_swipl.jl<TAB>estimate` in test/pkgtest_costs.tsv and test/unit_costs.tsv (copy a neighbour's).
5. Owner rows in docs/r2_owners.tsv (4 refusal rows, owner TTY2), keys `refusal:src/pl-term.jl::<function>::<first 60 chars of what>`:
   initTerm: "tgetent() (the terminal database of libtinfo)"; lookupEntry: "tgetnum(), tgetflag() and tgetstr() (the capabilities of libtinfo)";
   pl_tty_goto2_va: "tgoto() and tputs() (the cursor motion string, libtinfo)"; pl_tty_put2_va: "tputs() (output with padding, libtinfo)".
6. Things to check at the first compile (Julia was not run): `PL_get_text(ld, A1, UInt32(CVT_ALL | CVT_EXCEPTION))`,
   `ccall((:ioctl, LIBC), ...)` (variadic called with a fixed signature), `control_t{T}` in the manifest entries; the count of
   built-ins rises by 4 (any boot-image constant of the system predicate count); tools/port_check inventory regenerates.

## Recommendation for the audit (TTY2: linking terminfo)
libtinfo from Julia: `ccall((:tgetent, "libtinfo.so.6"), Cint, (Ptr{UInt8}, Cstring), buf, term)` and tgetnum/tgetflag/tgetstr/tgoto/
tputs; tputs takes a C callback (`@cfunction` writing to `Suser_output`), needing a per-type or per-ld trampoline; the library keeps
process-global state and a 1024-byte buffer (`buf_area`, `string_area`), matching `GD->terminal` (a struct change: `initialised`,
`_capabilities` table, the two areas). Recommend TTY2 = the GD field + the state, then the ccalls; the unlinked refusal rows then
become Done rows.

## Hand-back state
test_type_discipline.jl and warm.sh check NOT run; Julia NOT run; no gate or mutants branch pushed. No daemon used or freed by me.
