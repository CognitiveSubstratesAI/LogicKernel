# TB7-ROWS2 (wip/tb7rows)

Rows: test/core_lang/test_tabling_tb7rows_swipl.jl (TR7), five groups DEPERR d01-d07, COLLECT c01-c07, LAZY l01-l09, QUEUE q01-q11, SUBMONO s01-s05 (39 rows).
Pins: gen/groups.py through swipl 10.1.20 (gen/run.py, gen/emit.py, TB7_TMP = a scratch directory), every group run twice, byte-identical; the output is pins.txt.
Mutants: tools/mutants/TB7.py, 101 entries (95 + TB7R-DE1..DE4, TB7R-CO1, TB7R-CO2), every `old` once in src/pl-tabling.jl; TARGETS and TARGETS5 carry TR7 first and the four upstream monotonic files.
Not verified: everything about the kernel (nothing compiled, no Julia run); every kill is a reading of the rows. SUBMONO uses `(subsumptive, monotonic)` and `lazy`: whether the kernel accepts them is unknown; no row is recorded as broken without proof, the run decides.
To format: test/core_lang/test_tabling_tb7rows_swipl.jl.
