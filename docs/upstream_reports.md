# Upstream differences (swipl-devel): the index

Porting swipl-devel line by line, and checking each port against a live `swipl`, finds places where
the kernel deliberately mirrors upstream as is, or deliberately differs from it. This file is the
INDEX of those places: the number the source comments and tests refer to, how the kernel handles
it, and its status. The description of each one — what, where, how to trigger it — is kept in the
project's internal records until upstream has fixed it or a public issue exists; then it is
described and linked here, as #4 and #5 are.

| # | how LogicKernel handles it | status |
|---|---|---|
| 1 | the kernel differs (`# DIVERGES`, `6427b3a`); pinned | internal record |
| 2 | mirrored as is (`# UPSTREAM DEFECT` in `hash_compile!`); pinned in `test/core_lang/test_termhash.jl` | internal record |
| 3 | nothing in the kernel depends on it; `test/core_lang/test_unify_swipl.jl` tolerates it | internal record |
| 4 | An **abort** on the first call of a static predicate with exactly two clauses whose first arguments are rationals: `p(1r3, a). p(2r3, b).` gives `pl-comp.c:5577: arg1Key: Assertion failed: 0`. `listSupervisor` asks `arg1Key` for each clause's first-argument key; its switch lists `H_MPZ` but not `H_MPQ`, which falls to `assert(0)`. Assertions are live in Release builds by design (`cmake/BuildType.cmake`), so official binaries abort too. Seen on 10.1.16 (`10.1.16-20-gbae881a2`, Release, x86_64-linux). Upstream: `src/pl-comp.c`, `arg1Key`, `case H_MPZ:` without `case H_MPQ:` (`argKey` and `skipArgs` list both) Kernel: **Fixed** (`aa3b6bb`, `# DIVERGES` in `arg1Key`): `H_MPQ` gives no key, as `H_MPZ` does, so the predicate gets `S_STATIC`. Pinned in `test/foreign/test_query.jl` (both answers through the VM), mutation-proved: with upstream's omission restored, the kernel's `arg1Key` errors on exactly this predicate. | **fixed upstream**: [97370c0e](https://github.com/SWI-Prolog/swipl-devel/commit/97370c0e796a9a1c1c6d70443602fb84652fb233) (2026-10-06; `case H_MPQ:` beside `case H_MPZ:`, and a test in `tests/rational/test_rational.pl`), after the pinned `bae881a2`: the kernel side changes at the next swipl pin bump |
| 5 | A stack overflow ranks as an ordinary error. `classify_exception_p` tests a resource error's formal for the ATOM `resource_error`, where `pl-incl.h` documents `EXCEPT_RESOURCE` as `error(resource_error(_), _)`, and every resource error swipl raises has the compound formal (`FUNCTOR_resource_error1`; no file in `src/`, `boot/` or `library/` raises the atom). So nothing is `EXCEPT_RESOURCE`. Measured: `'$urgent_exception'/3` keeps a type error over a real overflow's `error(resource_error(stack), _)`. From the code: an ordinary error raised over a pending overflow replaces it. Seen on 10.1.16 (`10.1.16-20-gbae881a2`). Upstream: `src/pl-fli.c`, `classify_exception_p`, `if ( isAtom(*p) ) { if ( *p == ATOM_resource_error ) return EXCEPT_RESOURCE; }` Kernel: **Kept as is** (`# KNOWN UPSTREAM DEFECT` in `classify_exception_p`, src/pl-fli.jl). Pinned in `test/foreign/test_exceptions_swipl.jl`: the class, and every ordered pair of 14 balls against a live `'$urgent_exception'/3`, which also drives `PL_raise_exception`'s rule. Mutation-proved: with the documented shape, the kernel diverges from swipl on exactly this ball. | filed as [swipl-devel#1535](https://github.com/SWI-Prolog/swipl-devel/issues/1535) (2026-10-06); **fixed upstream** by [85d0cc2](https://github.com/SWI-Prolog/swipl-devel/commit/85d0cc2ac510691dedc28c286d8bd8a0eab0ebea) (2026-10-06; the atom test replaced by `hasFunctor(*p, FUNCTOR_resource_error1)`), after the pinned `bae881a2`: the kernel side changes at the next swipl pin bump |
| 6 | mirrored as is (decided 2026-10-06); cannot show before V9 | internal record |
| 7 | to be mirrored as is with V9's decompiler (decided 2026-10-06) | internal record |
| 8 | the kernel differs (`# DIVERGES`, R1c); pinned in `test/core_lang/test_read_swipl.jl` | internal record |
| 9 | the kernel differs (`# DIVERGES`, R1c); pinned in `test/core_lang/test_read_swipl.jl` | internal record |
| 10 | mirrored as is (`# KNOWN UPSTREAM DEFECT` in `makeErrorTerm`, `escape_char`); pinned in `test/core_text/test_read_term_swipl.jl` | internal record |
| 11 | mirrored as is (`# KNOWN UPSTREAM DEFECT` in `writeText`, `atomType`); pinned in `test/core_text/test_write_swipl.jl` | internal record |
| 12 | mirrored as is (`# KNOWN UPSTREAM DEFECT` in `bracketPairAtom`); pinned in `test/core_text/test_write_swipl.jl` | internal record |
| 13 | not mirrored (`# DIVERGES` at `get_stream_handle`); pinned in `test/core_text/test_write_family_swipl.jl` | internal record |
| 14 | not mirrored | internal record |

When one is fixed upstream, the LogicKernel side changes as follows:

- **#4:** drop the `# DIVERGES` in `arg1Key` (the code stays as it is), and add the two facts to a
  live swipl differential.
- **#5:** port the fix (the class test on `resource_error(_)`) and flip the class pin; the live
  differential then checks the fix.

**#4 and #5 are both fixed upstream** (`97370c0e`, `85d0cc2`, 2026-10-06), after the pinned
`bae881a2`. They move at the SAME swipl pin bump, and in ONE commit the kernel code and the oracle
move together:
1. the kernel takes `97370c0e` (drop `arg1Key`'s `# DIVERGES`, port SWI's new `first_arg` test from
   `tests/rational/test_rational.pl`) and `85d0cc2` (`classify_exception_p` as fixed, the class pin
   flipped);
2. the oracle moves to a swipl build that contains both commits — the local build and CI's
   container.

If only one side moves, the 14-ball `'$urgent_exception'/3` differential fails: correctly, but
confusingly.
