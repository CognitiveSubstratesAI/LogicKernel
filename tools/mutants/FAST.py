# ORIGINAL: FAST's mutant list (the external-record encoder of pl-rec.c fast_term_serialized/2).
# tools/mutants/FAST.py — the mutation battery of the fast_term_serialized/2 encoder (src/pl-rec.jl: addUintBuffer, addAtom,
# addFunctor, _external_string, addExternalIndirect, compile_external_record, is_external, pl_fast_term_serialized2_va; src/pl-gmp.jl:
# add_mpz_size_buffer, add_mpz_bits_buffer, addMPZToBuffer) — run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). Format: tools/mutate_drive.py's (as DICTREC.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, `targets`. An `old` of
# several lines is written with explicit newlines: mutate_drive.py counts the raw text (`s.count(m["old"])`).
# Aimed at test/core_lang/test_fast_rec_swipl.jl (the kernel rows t0-t66 of test_fast_rec_swipl.pl, named in each id's "aimed by").
# Verdicts: written by the battery, not yet run; this file was never compiled or run.
# Every `old` was checked to occur exactly once in its file at the wip/dict-rec tip (a text count, python3 -I, no Julia); a line that
# appears twice takes the deeper indentation or the variable name (`c` in addAtom's `info.code`, `b` in _external_string) to stay unique.
# CANDIDATE EQUIVALENTS are marked in a comment ("candidate equivalent: <reason>; needs the widened run and the audit's ruling"); the
# battery gives the verdict.
# The idea `len == bytes + 2` of is_external is listed as FAST-M36, a candidate equivalent: rows t64-t66 do not reach it with a valid
# root-int record, so the entry waits for a row (or the audit's ruling).
# TARGETS (audit D-0238): every mutant lists every test file that exercises its mutated code: the step's own file first, then the
# files with findall/nb_setval/PL_record rows (a count by grep -c on each named file: test_findall_swipl.jl, test_bagof_swipl.jl,
# test_gvar_swipl.jl, test_slot_indirects.jl, test_p2_swipl.jl, test_dictrec_swipl.jl) and test_type_discipline.jl (the three term
# types). test_copyterm_swipl.jl and test_assert_cells.jl have none of these rows.
TF = "test/core_lang/test_fast_rec_swipl.jl"
TARGETS = [
    TF,
    "test/core_lang/test_findall_swipl.jl",
    "test/core_lang/test_bagof_swipl.jl",
    "test/core_lang/test_gvar_swipl.jl",
    "test/core_lang/test_slot_indirects.jl",
    "test/core_lang/test_p2_swipl.jl",
    "test/core_lang/test_dictrec_swipl.jl",
    "test/db/test_record_swipl.jl",          # the internal record shares addAtom, addFunctor, addSizeInt, compile_term_to_heap (REPLAY-7: D-0238 both ways)
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/foreign/test_query.jl",
    "test/test_type_discipline.jl",
]
R = "src/pl-rec.jl"
G = "src/pl-gmp.jl"
MUTANTS = [
    # ── addUintBuffer ──
    dict(id="FAST-M01 addUintBuffer keeps the narrow mask: a size in 256..383, 512..639 is ONE byte (aimed by t47, t41: header sizes 674/480/478)", file=R, targets=TARGETS,
         old="    if (val & ~Int(0x7f)) == 0\n        push!(b, val % UInt8)",
         new="    if (val & ~0x7f) == 0\n        push!(b, val % UInt8)"),
    # ── addAtom ──
    dict(id="FAST-M02 addAtom writes a wide atom as a Latin-1 atom opcode (aimed by t9, t13)", file=R, targets=TARGETS,
         old="addOpCode(info, PL_TYPE_EXT_WATOM)",
         new="addOpCode(info, PL_TYPE_EXT_ATOM)"),
    dict(id="FAST-M03 addAtom writes a wide character's four bytes most significant first (aimed by t9, t13)", file=R, targets=TARGETS,
         old="push!(info.code, (c >> (8 * i)) % UInt8)",
         new="push!(info.code, (c >> (8 * (3 - i))) % UInt8)"),
    dict(id="FAST-M04 addAtom counts two bytes a wide character in the length (aimed by t9, t13)", file=R, targets=TARGETS,
         old="addSizeInt(info, 4 * length(text))",
         new="addSizeInt(info, 2 * length(text))"),
    dict(id="FAST-M05 addAtom writes [] as a text atom (aimed by t10, t43, t45, t46)", file=R, targets=TARGETS,
         old="if a == ld.atom_nil_w",
         new="if false"),
    dict(id="FAST-M06 addAtom writes the reserved dict atom as a text atom (aimed by t55, t56, t57)", file=R, targets=TARGETS,
         old="elseif info.external && a == ATOM_dict",
         new="elseif info.external && false && a == ATOM_dict"),
    dict(id="FAST-M07 addAtom writes the user atom with the text `dict` as PL_TYPE_DICT too (aimed by t10, t42)", file=R, targets=TARGETS,
         old="elseif info.external && a == ATOM_dict",
         new='elseif info.external && (a == ATOM_dict || (isTextAtom(_atom_value(ld, a)) && sym_text(_atom_value(ld, a)) == "dict"))'),
    # ── addFunctor ──
    dict(id="FAST-M08 addFunctor writes the arity one too high (aimed by t42, t44)", file=R, targets=TARGETS,
         old="addSizeInt(info, arityFunctor(ld.functors, f))",
         new="addSizeInt(info, arityFunctor(ld.functors, f) + 1)"),
    dict(id="FAST-M09 addFunctor writes a list cell as an ordinary compound (aimed by t42, t45, t46, t52)", file=R, targets=TARGETS,
         old="if f == ld.functor_dot2",
         new="if false"),
    # ── _external_string ──
    dict(id="FAST-M10 _external_string tags a Latin-1 string `b` (aimed by t0, t2, t24)", file=R, targets=TARGETS,
         old="UInt8('B')",
         new="UInt8('b')"),
    dict(id="FAST-M11 _external_string pads the W tag with two bytes (aimed by t1, t25)", file=R, targets=TARGETS,
         old="UInt8('W'), 0x00, 0x00, 0x00",
         new="UInt8('W'), 0x00, 0x00"),
    dict(id="FAST-M12 _external_string wide bytes most significant first (aimed by t1, t25, t28, t33)", file=R, targets=TARGETS,
         old="push!(b, (c >> (8 * i)) % UInt8)",
         new="push!(b, (c >> (8 * (3 - i))) % UInt8)"),
    dict(id="FAST-M13 _external_string rounds the cells with +7 (only the wide string \"α\", length 8, tells it from +8: aimed by t33)", file=R, targets=TARGETS,
         old="(length(b) + 8) ÷ 8 + 2",
         new="(length(b) + 7) ÷ 8 + 2"),
    dict(id="FAST-M14 _external_string rounds the cells with +1 (aimed by t0, t6)", file=R, targets=TARGETS,
         old="(length(b) + 8) ÷ 8 + 2",
         new="(length(b) + 1) ÷ 8 + 2"),
    # ── addExternalIndirect ──
    dict(id="FAST-M15 addExternalIndirect writes a string one byte short (aimed by t0, t24, t27, t28)", file=R, targets=TARGETS,
         old="addSizeInt(info, length(bytes))",
         new="addSizeInt(info, length(bytes) - 1)"),
    dict(id="FAST-M16 addExternalIndirect counts an mpq's two MPZ_STACK_EXTRA as one (aimed by t3, t32)", file=R, targets=TARGETS,
         old="+ 2 * MPZ_STACK_EXTRA + 2",
         new="+ MPZ_STACK_EXTRA + 2"),
    dict(id="FAST-M17 addExternalIndirect leaves MPZ_STACK_EXTRA out of an mpz's cells (aimed by t4, t32)", file=R, targets=TARGETS,
         old="info.size += mpz_wsize(z) + MPZ_STACK_EXTRA + 2",
         new="info.size += mpz_wsize(z) + 2"),
    dict(id="FAST-M18 addExternalIndirect counts a float as two cells (aimed by t5, t23, t33)", file=R, targets=TARGETS,
         old="info.size += 1 + 2                                  # WORDS_PER_DOUBLE + 2",
         new="info.size += 1 + 1                                  # WORDS_PER_DOUBLE + 2"),
    dict(id="FAST-M19 addExternalIndirect writes a float's bytes most significant first (aimed by t20, t21)", file=R, targets=TARGETS,
         old="push!(info.code, (bits >> (8 * i)) % UInt8)",
         new="push!(info.code, (bits >> (8 * (7 - i))) % UInt8)"),
    # ── pl-gmp.jl ──
    dict(id="FAST-M20 add_mpz_size_buffer writes the magnitude for a negative number (aimed by t16, t19, t31)", file=G, targets=TARGETS,
         old="hdrsize = mpz < 0 ? -size : size",
         new="hdrsize = size"),
    # candidate equivalent: the third header byte `(hdrsize >> 8)` becomes `>> 16`, which agrees for every byte count under 256 (the
    # integers of the rows have at most 32 bytes); needs the widened run and the audit's ruling.
    dict(id="FAST-M21 add_mpz_size_buffer writes the third header byte from bits 16.. (candidate equivalent: equal for byte counts under 256; needs the widened run and the audit's ruling; aimed by t16, t19)", file=G, targets=TARGETS,
         old="push!(b, ((hdrsize >> 8) & 0xff) % UInt8)",
         new="push!(b, ((hdrsize >> 16) & 0xff) % UInt8)"),
    dict(id="FAST-M22 addMPZToBuffer rounds the byte count with +8 (aimed by t16: 2**63 has 64 bits)", file=G, targets=TARGETS,
         old="size = (ndigits(abs(mpz); base=2) + 7) ÷ 8",
         new="size = (ndigits(abs(mpz); base=2) + 8) ÷ 8"),
    dict(id="FAST-M23 add_mpz_bits_buffer writes the bytes least significant first (aimed by t4, t16, t19, t29)", file=G, targets=TARGETS,
         old="append!(b, UInt8.(reverse(digits(abs(mpz); base=256, pad=size))))",
         new="append!(b, UInt8.(digits(abs(mpz); base=256, pad=size)))"),
    # ── compile_external_record: the root ──
    dict(id="FAST-M24 the root integer record is not marked ground (aimed by t14, t15)", file=R, targets=TARGETS,
         old="first |= REC_INT | REC_GROUND",
         new="first |= REC_INT"),
    dict(id="FAST-M25 the root atom record is not marked ground (aimed by t7, t8, t9, t10, t11)", file=R, targets=TARGETS,
         old="first |= REC_ATOM | REC_GROUND",
         new="first |= REC_ATOM"),
    dict(id="FAST-M26 the root tagged integer is written one too high (aimed by t14, t15)", file=R, targets=TARGETS,
         old="v = valInt(x)",
         new="v = valInt(x) + 1"),
    dict(id="FAST-M27 an int64 root in an indirect is no integer-only record (aimed by t15)", file=R, targets=TARGETS,
         old="isInteger(iv) && integer_is_int64(iv) &&",
         new="isInteger(iv) && false &&"),
    dict(id="FAST-M28 a term with variables is marked ground (aimed by the rows with variables, t35-t41)", file=R, targets=TARGETS,
         old="info.nvars == 0 && (first |= REC_GROUND)",
         new="info.nvars == 0 || (first |= REC_GROUND)"),
    dict(id="FAST-M29 the variable count is written for a ground term too (aimed by the ground rows, t0-t34)", file=R, targets=TARGETS,
         old="info.nvars > 0 && addUintBuffer(data.hdr, info.nvars)",
         new="info.nvars >= 0 && addUintBuffer(data.hdr, info.nvars)"),
    dict(id="FAST-M30 the header's stack size is one too high (aimed by t0)", file=R, targets=TARGETS,
         old="addUintBuffer(data.hdr, info.size)",
         new="addUintBuffer(data.hdr, info.size + 1)"),
    dict(id="FAST-M31 the variables stay marked and the walked cells stay visited after a blob error (restoreVars and unvisit after the error check: aimed by t60, t61)", file=R, targets=TARGETS,
         old="    restoreVars(ld, info)\n    unvisit(ld, info)\n    rc || return rec_error(ld, info)",
         new="    rc || return rec_error(ld, info)\n    restoreVars(ld, info)\n    unvisit(ld, info)"),
    dict(id="FAST-M32 rec_error names another formal (aimed by t58, t59)", file=R, targets=TARGETS,
         old="mk_sym(T, :fast_serialize), mk_sym(T, :blob), t",
         new="mk_sym(T, :other), mk_sym(T, :blob), t"),
    dict(id="FAST-M33 a root blob atom raises the permission error (the pin fails silently: aimed by t62)", file=R, targets=TARGETS,
         old="addAtom(ld, info, x) || return false",
         new="addAtom(ld, info, x) || return rec_error(ld, info)"),
    # ── is_external ──
    dict(id="FAST-M34 is_external reads one byte more of the code of a header record (aimed by t65, t66)", file=R, targets=TARGETS,
         old="return len == (info.data - 1) + codes",
         new="return len == (info.data - 1) + codes + 1"),
    dict(id="FAST-M35 the string argument is read without CVT_EXCEPTION (aimed by t63)", file=R, targets=TARGETS,
         old="PL_get_text(ld, string, CVT_STRING | CVT_EXCEPTION)",
         new="PL_get_text(ld, string, CVT_STRING)"),
    # candidate equivalent: no row reaches is_external with a valid root-int record (t64-t66 do not); `len == bytes + 2` becomes
    # `bytes + 1` and the answer differs only for a record of that shape; needs the widened run and the audit's ruling.
    dict(id="FAST-M36 is_external wants one byte less of a root-int record (candidate equivalent: no row reaches it; needs the widened run and the audit's ruling; aimed by none)", file=R, targets=TARGETS,
         old="return len == bytes + 2",
         new="return len == bytes + 1"),
]
