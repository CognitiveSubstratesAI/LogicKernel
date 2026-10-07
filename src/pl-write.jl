# UPSTREAM: swipl-devel src/pl-write.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE WRITER (R1e). Since R1c only the NaN helpers the reader needs to read `1.5NaN`: a NaN's
# payload is written as the float whose exponent field is replaced (`NaN_value`), and read back by
# putting the NaN exponent into it (`make_nan`). NOT PORTED: everything else, R1e — `writeTerm2`,
# quoting, operators and spacing, `format_float`, `write/1`, `writeq/1`, `print/1`,
# `write_canonical/1`, `write_term/2,3`, `nl/0,1`.

# PORT: pl-write.c NaN_value
# DIVERGES: the exponent field is replaced on the bits (`reinterpret`), where upstream writes it
# through a union's bit-fields.
"The float whose digits stand for NaN `f`'s payload: its exponent field 0x3ff (pl-write.c)."
function NaN_value(f::Float64)::Float64
    u = reinterpret(UInt64, f)
    @assert (u >> 52) & 0x7ff == 0x7ff                  # NaN exponent
    return reinterpret(Float64, (u & ~(UInt64(0x7ff) << 52)) | (UInt64(0x3ff) << 52))
end

# PORT: pl-write.c make_nan
# DIVERGES: returns `(status, value)`, where upstream rewrites `*f`; the exponent field as in
# `NaN_value`.
"The NaN whose payload `f` writes (`1.5NaN`): `(NUM_OK, nan)`, or `(NUM_CONSTRANGE, f)` (pl-write.c)."
function make_nan(f::Float64)::Tuple{strnumstat, Float64}
    u = reinterpret(UInt64, f)
    d = reinterpret(Float64, u | (UInt64(0x7ff) << 52))  # NaN exponent
    isnan(d) && return (NUM_OK, d)
    return (NUM_CONSTRANGE, f)                          # 1.0NaN is in fact 1.0Inf
end
