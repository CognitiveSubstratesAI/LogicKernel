# `src/vm/` — clause compilation and the execution machine

Compiling clauses to instructions, frames, and the execution loop.

Port class: **as design** (SWI-Prolog `src/pl-comp.c`, `src/pl-wam.c`). SWI is ZIP-based, not the
WAM, and its compiled code decompiles back to the source clause — which this kernel needs, because
clauses stay queryable as terms. 🔴 **No choice points and no trail**: nondeterminism is the
SINK/CONTINUATION model with an explicit continuation stack.

Depends on: `unify`, `constraints`, `index`, `db`, `tabling`. Entry file when it lands: `vm.jl`.
