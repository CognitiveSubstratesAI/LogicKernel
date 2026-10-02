# `test/oracle/` — live differentials against SWI-Prolog

Each ported algorithm is checked against a RUNNING `swipl`, not against pinned literals copied from
it. When `swipl` is absent an oracle test must say so LOUDLY — and a leaf testset that asserts
nothing fails the suite (`test/inert_testset_guard.jl`), so a skipped oracle cannot read as green.
