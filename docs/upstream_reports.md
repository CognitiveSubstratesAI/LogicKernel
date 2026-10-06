# Upstream defects found by porting (swipl-devel)

Porting swipl-devel line by line, and checking each port against a live `swipl`, finds defects in
upstream itself. This file lists them. Each one is:

- recorded **internally first**, as a LogicKernel issue with its reproducer;
- **reported upstream later, by hand** (user, 2026-10-03). The org token cannot open issues
  outside CognitiveSubstratesAI.

An entry closes when its upstream report is filed and linked here.

| # | defect | upstream code | how LogicKernel handles it | internal record | upstream report |
|---|---|---|---|---|---|
| 1 | `skipArgs`: an exact landing loses the key after `_,_`. `p(_,_,a1..a100)` with `p(_,_,a50)` builds no index, and a walk over several arguments loses the later ones for good. | `src/pl-comp.c`, `skipArgs`, `case H_VOID_N: … if ( skip <= 0 )` | **Fixed** (`6427b3a`, `# DIVERGES`). A check fails the day swipl stops showing the defect. | [LogicKernel#1](https://github.com/CognitiveSubstratesAI/LogicKernel/issues/1). Its fix comment is still to post by hand (the token gets 403 on comments). | not filed |
| 2 | `hash_compile` never advances `data`. A piece that straddles a block hashes its own first bytes again, so its tail is never hashed. Two 310-byte atoms that differ after byte 247 get the same `variant_hash/2`. | `src/pl-termhash.c`, `hash_compile` | **Kept verbatim** (`# UPSTREAM DEFECT` in `hash_compile!`) and pinned in `test/core_lang/test_termhash.jl`. The fix is `data += copy;`. | [LogicKernel#2](https://github.com/CognitiveSubstratesAI/LogicKernel/issues/2) | not filed |
| 3 | An **abort** while raising an occurs-check error with `occurs_check=error`: `FATAL ERROR: Cannot report error: no memory`, then `Assertion failed: exception_term`, then SIGABRT. It is deterministic, but depends on what else the process has loaded and run. | runtime: `PL_error ← unify_with_occurs_check ← unify_ptrs` (`src/pl-prims.c`) | Nothing in the kernel depends on it. `test/core_lang/test_unify_swipl.jl` runs swipl in chunks and re-runs an aborted chunk pair by pair, reporting each abort as a `@warn`. | [LogicKernel#3](https://github.com/CognitiveSubstratesAI/LogicKernel/issues/3). Reproducers and a draft report are in the workspace at `docs/tracking/repros/swipl_occurs_check_error_abort/`. | not filed (draft `REPORT.md`) |
| 4 | An **abort** on the first call of a static predicate with exactly two clauses whose first arguments are rationals: `p(1r3, a). p(2r3, b).` gives `pl-comp.c:5577: arg1Key: Assertion failed: 0`. `listSupervisor` asks `arg1Key` for each clause's first-argument key; its switch lists `H_MPZ` but not `H_MPQ`, which falls to `assert(0)`. Assertions are live in Release builds by design (`cmake/BuildType.cmake`), so official binaries abort too. Seen on 10.1.16 (`10.1.16-20-gbae881a2`, Release, x86_64-linux). | `src/pl-comp.c`, `arg1Key`, `case H_MPZ:` without `case H_MPQ:` (`argKey` and `skipArgs` list both) | **Fixed** (`aa3b6bb`, `# DIVERGES` in `arg1Key`): `H_MPQ` gives no key, as `H_MPZ` does, so the predicate gets `S_STATIC`. Pinned in `test/foreign/test_query.jl` (both answers through the VM), mutation-proved: with upstream's omission restored, the kernel's `arg1Key` errors on exactly this predicate. | This file. Reproducer, captured output and a draft report in the workspace at `docs/tracking/repros/swipl_arg1key_mpq_abort/`. No LogicKernel issue opened (the user's call). | not filed (draft `REPORT.md`; the user reviews and files it) |
| 5 | A stack overflow ranks as an ordinary error. `classify_exception_p` tests a resource error's formal for the ATOM `resource_error`, where `pl-incl.h` documents `EXCEPT_RESOURCE` as `error(resource_error(_), _)`, and every resource error swipl raises has the compound formal (`FUNCTOR_resource_error1`; no file in `src/`, `boot/` or `library/` raises the atom). So nothing is `EXCEPT_RESOURCE`. Measured: `'$urgent_exception'/3` keeps a type error over a real overflow's `error(resource_error(stack), _)`. From the code: an ordinary error raised over a pending overflow replaces it. Seen on 10.1.16 (`10.1.16-20-gbae881a2`). | `src/pl-fli.c`, `classify_exception_p`, `if ( isAtom(*p) ) { if ( *p == ATOM_resource_error ) return EXCEPT_RESOURCE; }` | **Kept as is** (`# KNOWN UPSTREAM DEFECT` in `classify_exception_p`, src/pl-fli.jl). Pinned in `test/foreign/test_exceptions_swipl.jl`: the class, and every ordered pair of 14 balls against a live `'$urgent_exception'/3`, which also drives `PL_raise_exception`'s rule. Mutation-proved: with the documented shape, the kernel diverges from swipl on exactly this ball. | This file. Reproducer, captured output and a draft report in the workspace at `docs/tracking/repros/swipl_except_resource_class/`. No LogicKernel issue opened (the user's call). | not filed (draft `REPORT.md`; the user reviews and files it) |

How each was found:

- **#1:** a live differential of index layouts against swipl (`test/db/test_index_swipl.jl`).
- **#2:** reading `pl-termhash.c` while porting it, then measured on swipl.
- **#3:** the live `=/2` differential (`test/core_lang/test_unify_swipl.jl`).
- **#4:** porting `pl-supervisor.c` with `arg1Key` (V4a), then probed on swipl with the two facts.
- **#5:** porting `classify_exception_p` (V5b), against the comment on its enum; then the live
  `'$urgent_exception'/3` differential and a real stack overflow probed on swipl.

When one is fixed upstream, the LogicKernel side changes as follows:

- **#1:** the divergence ends, so drop `# DIVERGES` and the check that pins swipl's behaviour.
- **#2:** port the fix and flip the pin.
- **#3:** go back to one swipl process per mode.
- **#4:** drop the `# DIVERGES` in `arg1Key` (the code stays as it is), and add the two facts to a
  live swipl differential.
- **#5:** port the fix (the class test on `resource_error(_)`) and flip the class pin; the live
  differential then checks the fix.
