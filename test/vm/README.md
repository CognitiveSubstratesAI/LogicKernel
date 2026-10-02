# `test/vm/` — tests for `src/vm/`

Files named `test_*.jl` here run automatically (`test/runtests.jl` discovers them). Each runs in
its OWN fresh module, so it must start with `using Test, LogicKernel` and its helpers cannot collide
with another file's. Upstream's tests for a ported algorithm come WITH the port, not after it.
