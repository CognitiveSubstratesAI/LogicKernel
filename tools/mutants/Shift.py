# ORIGINAL: Shift's mutant list — no swipl-devel counterpart.
# tools/mutants/Shift.py — the mutation battery of the shift fix (audit D-0127 item 1: ar_shift reads a negated
# amount as UNSIGNED, as upstream's size_t / mp_bitcnt_t; 2026-10-23), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Subject: `1 >> -9223372036854775808` and kin (resource_error(stack), group F's fuzzer finding) and the left shift
# by LONG_MIN (0, or -1 for a negative base), in test/core_lang/test_arith_swipl.jl (_A_TOOBIG; the V8 testset).
TARGETS = ["test/core_lang/test_arith_swipl.jl"]
A = "src/pl-arith.jl"
T = TARGETS
MUTANTS = [
    dict(id="SH1 'shift >= 64' compares the amount signed", file=A, targets=T,
         old='''                reinterpret(UInt64, shift) >= 64 ? (n1.i >= 0 ? 0 : -1) : n1.i >> shift''',
         new='''                shift >= 64 ? (n1.i >= 0 ? 0 : -1) : n1.i >> shift'''),
    dict(id="SH2 the left shift's bit count ignores the amount", file=A, targets=T,
         old='''            bits = reinterpret(UInt64, shift) + UInt64(''',
         new='''            bits = UInt64(0) + UInt64('''),
    dict(id="SH3 the size check ignores the amount", file=A, targets=T,
         old='''        msb = UInt64(ndigits(n1.mpz; base=2)) + reinterpret(UInt64, shift)''',
         new='''        msb = UInt64(ndigits(n1.mpz; base=2)) + UInt64(0)'''),
]
