# ORIGINAL: RECSIZEINT's mutant list - pl-rec.c addUintBuffer's one-byte test, `!(val & ~0x7f)` on a size_t (no swipl-devel counterpart for the list).
# tools/mutants/RECSIZEINT.py - the mutation battery of the addSizeInt fix (src/pl-rec.jl addSizeInt: a size, variable number, offset or value index
# below 128 is one byte, every other is written in 7-bit groups). Run ONCE, in CI (.github/workflows/mutation.yml; locally one mutant by hand).
# Format: tools/mutate_drive.py's (as WRAP1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`, `targets`.
# RECSIZEINT-1 restores the old test: `~0x7f` of a bare literal is the UInt8 0x80, so for a size of 256..383, 512..639, ... (bit 7 clear) the test
# `(val & 0x80) == 0` held and `val % UInt8` wrote one wrong byte. It is aimed by the rows r102-r108 of test/db/test_record_swipl.jl
# (r102/r103/r104: a record of 256, 300, 384 variables; r105: arity 300; r106: variables numbered above 255, shared; r107: findall/3's copy; r108),
# which failed on main 281ca507 before the fix.
# `old` was counted EXACTLY once in src/pl-rec.jl (python3 -I script, at the fix). RE-FIT it if `tools/warm.sh fmt` rewraps the line.
# TARGETS (audit D-0238): every test file that runs the record compiler (compileTermToHeap: the recorded database, the findall/bagof bags,
# PL_record, the flag and slot-indirect users).
R = "test/db/test_record_swipl.jl"
TARGETS = [
    R,
    "test/core_lang/test_findall_swipl.jl",
    "test/core_lang/test_bagof_swipl.jl",
    "test/core_lang/test_slot_indirects.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/foreign/test_query.jl",
    "test/core_lang/test_fast_rec_swipl.jl",     # addSizeInt writes the external record's code too (REPLAY-7, D-0238)
]
PREC = "src/pl-rec.jl"
MUTANTS = [
    dict(id="RECSIZEINT-1 the one-byte test masks with a UInt8 (0x80): a size of 256 is written as the single byte 0 (KILL R: rows r102-r108)",
         file=PREC, targets=TARGETS,
         old="    if (val & ~Int(0x7f)) == 0\n        push!(info.code, val % UInt8)",
         new="    if (val & ~0x7f) == 0\n        push!(info.code, val % UInt8)"),
]
