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

How each was found:

- **#1:** a live differential of index layouts against swipl (`test/db/test_index_swipl.jl`).
- **#2:** reading `pl-termhash.c` while porting it, then measured on swipl.
- **#3:** the live `=/2` differential (`test/core_lang/test_unify_swipl.jl`).

When one is fixed upstream, the LogicKernel side changes as follows:

- **#1:** the divergence ends, so drop `# DIVERGES` and the check that pins swipl's behaviour.
- **#2:** port the fix and flip the pin.
- **#3:** go back to one swipl process per mode.
