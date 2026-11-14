# ORIGINAL: RD2's mutant list: the quasi-quotation read and the blob read of src/pl-read.jl; no swipl-devel counterpart.
# tools/mutants/RD2.py — the mutation battery of RD2 (the read of `{|Syntax||Text|}` and of `<type>(...)`): src/pl-read.jl (get_quasi_quotation,
# raw_read_quasi_quotation, parse_quasi_quotations, is_quasi_quotation_syntax, read_qq_start, read_qq_resume, the tokens TK_QQ_OPEN/TK_QQ_BAR,
# read_blob_start/resume/end/arg, the tokeniser's blob test, atom_to_blob_mode_ex, the option table and `pl_qq_open2_va` of `$qq_open/2`),
# src/pl-atom.jl (newDeadBlob, lookupLiveBlob / scanLiveBlobs, deadBlobType, `unavailable_blob`), src/pl-write.jl (write_unavailable, the
# writeAtom branch of a dead blob, blob_written_text) and src/pl-fli.jl (`blob/2`). NOTHING was run when this list was drafted: every kill
# below is read off the pinned rows of the two test files, the CI battery is the verdict.
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TRIE4.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the row that must fail: the rows of test/core_text/test_read_qq_swipl.jl (QA = qa01-qa97, QB = qb01-qb52, QK = qk01; the QB
# group loads library(quasi_quotations)) and of test/core_text/test_read_blob_swipl.jl (bl01-bl80). A kill row compares the kernel's line with swipl's
# pinned line of the same row through one extractor (`_qq_enc` / `_bl_enc`), both sides non-empty (the `count` floors of the two files).
# TARGETS (audit D-0238): every test file that runs the mutated code. The tokens, the contexts and the option wiring are shared with the readers'
# own files: test_read_term_swipl.jl (read_term/2,3 options and their errors), test_read_stream_swipl.jl (the stream reads), test_read_positions_swipl.jl
# (subterm_positions through the same frames) and test_canonical_readatom_swipl.jl (term_to_atom and read_term_from_atom, which run the tokeniser);
# every mutant therefore names all six, the kill rows being the new files' (a survivor of a narrow list proves nothing about dead code).
# EQUIVALENT mutants: none declared. Left out as not killable by a pinned row (drafted, then dropped): the `}` test of get_quasi_quotation (no row has a `}`
# inside a body), the ambiguity return of lookupLiveBlob (no two live blobs write the same text), the address read of `_blob_address` (the type scan
# finds the same stream, bl70/bl75), `bt !== unavailable_blob` of scanLiveBlobs (a dead blob writes as `<unavailable>(...)`, never as the text read).
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py RD2` at the tip of wip/rd2; `new` != `old`;
# no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
QA = "test/core_text/test_read_qq_swipl.jl"
BL = "test/core_text/test_read_blob_swipl.jl"
RT = "test/core_text/test_read_term_swipl.jl"
RS = "test/core_text/test_read_stream_swipl.jl"
RP = "test/core_text/test_read_positions_swipl.jl"
CR = "test/core_text/test_canonical_readatom_swipl.jl"
TARGETS = [QA, BL, RT, RS, RP, CR]           # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
R = "src/pl-read.jl"
A = "src/pl-atom.jl"
W = "src/pl-write.jl"
FLI = "src/pl-fli.jl"
ALL = [QA, BL, RT, RS, RP, CR]
# every mutant names ALL six files (audit D-0238: the narrow list of an early battery proves nothing about dead code); the names below stay for the reader of a row
QQ = BLOB = BLONLY = ALL

def m(id, old, new, targets=ALL, file=R, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- get_quasi_quotation, raw_read_quasi_quotation
    m("RD2-G1 get_quasi_quotation: the read goes on AT the `}` (KILL QA qa01: the text read after the quotation starts with `}`; qa70, qa71)",
      "rd.here = in + 1                        # after }", "rd.here = in                            # after }", QQ),
    m("RD2-G2 get_quasi_quotation: the text keeps its last `|` (KILL QA qa01: [121,122] becomes [121,122,124]; qa04, qa06)",
      "in -= 1                                 # Before |", "in -= 0                                 # Before |", QQ),
    m("RD2-G3 get_quasi_quotation: option and no-option swapped (KILL QA qa01: the option gets `$quasi_quotation(...)`, QB qb01: the library gets a code list)",
      "if rd.quasi_quotations != 0             # option; must return strings", "if rd.quasi_quotations == 0             # option; must return strings", QQ),
    m("RD2-G4 get_quasi_quotation: the code list of the option is read as Latin-1 (KILL QA qa05: [228,8364] becomes the bytes of its UTF-8)",
      "bytes), ENC_UTF8, false)", "bytes), ENC_ISO_LATIN_1, false)", QQ),
    m("RD2-G5 raw_read_quasi_quotation: the end of text is a plain end_of_file (KILL QA qa24, qa25, qa51, qa75: end_of_file_in_quasi_quotation)",
      'return rawSyntaxError("end_of_file_in_quasi_quotation", rd)', 'return rawSyntaxError("end_of_file", rd)', QQ),
    # ---- the tokens
    m("RD2-T1 the token `{|` ignores the flag quasi_quotations (KILL QA qa81, qa84: with the flag off `{|x` is plain punctuation)",
      "        if c == Int('{') && _byte(b, rd.here) == Int('|') &&\n            truePrologFlag(rd.ld, PLFLAG_QUASI_QUOTES)\n            rd.here += 1\n            tok.type = TK_QQ_OPEN",
      "        if c == Int('{') && _byte(b, rd.here) == Int('|')\n            rd.here += 1\n            tok.type = TK_QQ_OPEN", QQ),
    m("RD2-T2 the syntax term of a quotation ends at `,` instead of `||` (KILL QA qa01: `||` no longer ends the term, every quotation fails)",
      "stop !== nothing && first(stop) == '|' && @goto level_done", "stop !== nothing && first(stop) == ',' && @goto level_done", QQ),
    # ---- parse_quasi_quotations
    m("RD2-P1 parse_quasi_quotations: the list of quotations stays open (KILL QA qa01, qa02, qa10: Q is `[Q1|_]`, not `[Q1]`)",
      "        PL_unify_nil(ld, rd.qq_tail) || return false\n", "        true\n", QQ),
    m("RD2-P2 parse_quasi_quotations: the library is called only when the option is given (KILL QB qb01: no syntax predicate runs, the result stays a variable)",
      "        if rd.quasi_quotations == 0\n            av = PL_new_term_refs(ld, 2)", "        if rd.quasi_quotations != 0\n            av = PL_new_term_refs(ld, 2)", QQ),
    m("RD2-P3 parse_quasi_quotations: the read is not recorded in ld.read_contexts (KILL QB qb01: `$qq_open/2` raises existence_error(read_context, _) inside the library)",
      "                push!(ld.read_contexts, rd)\n", "                nothing\n", QQ),
    # ---- is_quasi_quotation_syntax
    m("RD2-I1 is_quasi_quotation_syntax: the declared flag is read the wrong way (KILL QB qb01: a declared syntax is unknown, qb11: an undeclared one is accepted)",
      "(proc.definition.flags & P_QUASI_QUOTATION_SYNTAX) != 0 && return true", "(proc.definition.flags & P_QUASI_QUOTATION_SYNTAX) == 0 && return true", QQ),
    m("RD2-I2 is_quasi_quotation_syntax: the syntax predicate is looked up with arity 3 (KILL QB qb01: syntax predicates have arity 4)",
      "resolveProcedure(gd, na[1], 4, m)", "resolveProcedure(gd, na[1], 3, m)", QQ),
    m("RD2-I3 is_quasi_quotation_syntax: any syntax is accepted without the option (KILL QA qa40, qa41, qa42: unknown_quasi_quotation_syntax)",
      "        if rd.quasi_quotations != 0\n            return true\n        else\n            proc =",
      "        if rd.quasi_quotations == 0\n            return true\n        else\n            proc =", QQ),
    m("RD2-I4 is_quasi_quotation_syntax: the module of the error is user (KILL QA qa44, QB qb12: module(lists) is the module of the error)",
      "PL_put_atom(ld, mt, m.atom)", "PL_put_atom(ld, mt, MODULE_user(gd).atom)", QQ),
    m("RD2-I5 is_quasi_quotation_syntax: the module qualification of the syntax is ignored (KILL QA qa43: `M:x` reports module `system`)",
      "    ok || return false\n    m = gd.modules[mi]", "    ok || return false\n    m = gd.modules[rd.module_]", QQ),
    # ---- read_qq_start
    m("RD2-S1 read_qq_start: the syntax term is read at priority 199 (KILL QA qa03: `M:x` is 200, qa33: `a+b` is 500)",
      '    req.stop = "|"\n    req.maxpri = OP_MAXPRIORITY + 1', '    req.stop = "|"\n    req.maxpri = 199', QQ),
    m("RD2-S2 read_qq_start: the syntax term's positions are not requested (KILL QA qa60, qa62, qa63: the position of the syntax stays unbound)",
      "req.positions = pv != 0 ? pv + 1 : 0", "req.positions = 0", QQ),
    m("RD2-S3 read_qq_start: the quotation's list is not the option's (KILL QA qa01: Q stays unbound)",
      "            rd.qq = rd.quasi_quotations\n", "            rd.qq = PL_new_term_ref(ld)\n", QQ),
    m("RD2-S4 read_qq_start: the result cell is not shared with the 4th argument (KILL QA qa01: Result is V0 in ok(V0) and in the quotation, QB qb01)",
      "    ld.slots[av + 3 + 1] = makeRefG(c)\n", "    PL_put_variable(ld, av + 3)\n", QQ),
    # ---- read_qq_resume
    m("RD2-R1 read_qq_resume: the error of a missing `||` is named bar_expected (KILL QA qa29: double_bar_expected)",
      'return Int(syntaxError("double_bar_expected", rd))', 'return Int(syntaxError("bar_expected", rd))', QQ),
    m("RD2-R2 read_qq_resume: the syntax is not checked (KILL QA qa20, qa21, qa34, qa40: invalid_ and unknown_quasi_quotation_syntax)",
      "    is_quasi_quotation_syntax(av, rd) || return 0\n", "    true || return 0\n", QQ),
    m("RD2-R3 read_qq_resume: the end of the content is one past `|}` (KILL QA qa60: the content position `5-6` pinned)",
      "Int64(token.end_), Int64(qqend - 2)", "Int64(token.end_), Int64(qqend - 1)", QQ),
    m("RD2-R4 read_qq_resume: the quotation's range ends one late (KILL QA qa60: quasi_quotation_position(0, 8, ...))",
      "set_range_position(ld, f.pin, Int64(-1), Int64(qqend))", "set_range_position(ld, f.pin, Int64(-1), Int64(qqend + 1))", QQ),
    m("RD2-R5 read_qq_resume: the variable dictionary is an unbound variable (KILL QA qa01: the pin has `nil`, qa08 and qa09: the pinned [X=_, Y=_])",
      "    PL_put_term(ld, av + 2, rd.varnames)            # Arg 2: the var dictionary", "    PL_put_variable(ld, av + 2)                     # Arg 2: the var dictionary", QQ),
    m("RD2-R6 read_qq_resume: the quotation's functor is quasi_quotations/4 (KILL QA qa01: quasi_quotation/4)",
      "_err_functor(ld, :quasi_quotation, 4)", "_err_functor(ld, :quasi_quotations, 4)", QQ),
    m("RD2-R7 read_qq_resume: a second quotation is unified with the first one (KILL QA qa02, qa10: two quotations, QB qb06)",
      "PL_unify_list(ld, rd.qq_tail, t, rd.qq_tail) && PL_unify(ld, t, av)", "PL_unify_list(ld, rd.qq, t, rd.qq_tail) && PL_unify(ld, t, av)", QQ),
    m("RD2-R8 read_qq_resume: the position of the syntax term is not unified (KILL QA qa60, qa62: `a[120]` / `u(1)` in quasi_quotation_position/5)",
      "        PL_unify(ld, pv + 0, av + 0) || return 0\n", "        true || return 0\n", QQ),
    # ---- `$qq_open/2`
    m("RD2-O1 pl_qq_open2_va: the pointer argument raises type_error(integer, _) (KILL QA qa93: type_error(address, a))",
      "PL_error(ld, ERR_TYPE, mk_sym(T, :address), arg)", "PL_error(ld, ERR_TYPE, mk_sym(T, :integer), arg)", QQ),
    m("RD2-O2 pl_qq_open2_va: a term that is no `$quasi_quotation/3` raises type_error(compound, _) (KILL QA qa90, qa92: type_error(read_context, _))",
      "PL_error(ld, ERR_TYPE, mk_sym(T, :read_context), A1)", "PL_error(ld, ERR_TYPE, mk_sym(T, :compound), A1)", QQ),
    m("RD2-O3 pl_qq_open2_va: `$quasi_quotation` is taken with arity 2 (KILL QA qa93: the pointer type error is not reached, QB qb01)",
      r'PL_is_functor(ld, A1, mk_sym(T, Symbol("\$quasi_quotation")), 3)', r'PL_is_functor(ld, A1, mk_sym(T, Symbol("\$quasi_quotation")), 2)', QQ),
    m("RD2-O4 pl_qq_open2_va: the stream starts one byte late (KILL QB qb01: the content `yz` reads as `z`)",
      "from = rd.base + start", "from = rd.base + start + 1", QQ),
    m("RD2-O5 pl_qq_open2_va: the stream decodes Latin-1 (KILL QB qb05: the content `\\xE4\\\\x20AC\\` reads as its UTF-8 bytes)",
      "s.encoding = ENC_UTF8\n                    pos = ptr_to_location(from, rd)", "s.encoding = ENC_ISO_LATIN_1\n                    pos = ptr_to_location(from, rd)", QQ),
    m("RD2-O6 pl_qq_open2_va: the stream gets no position (KILL QB qb30, qb31, qb33: the pinned line, line position and char count)",
      "if pos.position.lineno > 0", "if pos.position.lineno < 0", QQ),
    m("RD2-O7 pl_qq_open2_va: a read that does not exist raises type_error (KILL QK qk01: existence_error(read_context, _))",
      "PL_error(ld, ERR_EXISTENCE, mk_sym(T, :read_context), A1)", "PL_error(ld, ERR_TYPE, mk_sym(T, :read_context), A1)", ALL),
    # ---- the blob read
    m("RD2-B1 read_blob_end: blob(resolve) is read as blob(dead) and the other way (KILL BL bl70, bl73, bl75: a live stream resolves)",
      "        rd.blobs === :resolve\n", "        rd.blobs !== :resolve\n", BLOB),
    m("RD2-B2 read_blob_end: the text of the dead blob misses its last byte (KILL BL bl01, bl02, bl03: the `~q` text `<clause>(0x123)`)",
      "view(rd._rb.base, f.blob_start:(rd.here - 1)), rd.here - f.blob_start,", "view(rd._rb.base, f.blob_start:(rd.here - 1)), rd.here - f.blob_start - 1,", BLOB),
    m("RD2-B3 read_blob_end: the position ends one late (KILL BL bl41, bl43, bl44: the pinned `0-12`, `0-14`, `0-7`)",
      "(Int64(f.blob_pos_start), Int64(token.end_))", "(Int64(f.blob_pos_start), Int64(token.end_ + 1))", BLOB),
    m("RD2-B4 read_blob_arg: an argument ends at `)` only (KILL BL bl04, bl05: `<foo>(a, f(b))`)",
      'read_blob_arg(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}\n    req.stop = ",)"', 'read_blob_arg(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}\n    req.stop = ")"', BLOB),
    m("RD2-B5 read_blob_arg: an argument is read at priority 99 (KILL BL bl05: `a+b` is 500)",
      'read_blob_arg(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}\n    req.stop = ",)"\n    req.maxpri = 999', 'read_blob_arg(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}\n    req.stop = ",)"\n    req.maxpri = 99', BLOB),
    m("RD2-B6 read_blob_start: `<type>()` is not recognised (KILL BL bl03, bl44: the empty argument list)",
      "if tk.type == TK_PUNCTUATION && tk.character == Int(')')\n        return read_blob_end(f, tk, rd)", "if tk.type == TK_PUNCTUATION && tk.character == Int(']')\n        return read_blob_end(f, tk, rd)", BLOB),
    m("RD2-B7 read_blob_start: the first argument token is not given back (KILL BL bl02, bl04: its first token is lost)",
      "    rd._unget = true                                # unget_token()\n    return read_blob_arg(f, req, rd)", "    rd._unget = false                               # unget_token()\n    return read_blob_arg(f, req, rd)", BLOB),
    m("RD2-B8 read_blob_resume: the closing `)` is not recognised (KILL BL bl04: `<foo>(a, f(b))` ends after its second argument)",
      "tk.character == Int(')') && return read_blob_end(f, tk, rd)\n    return read_blob_arg(f, req, rd)", "tk.character == Int(']') && return read_blob_end(f, tk, rd)\n    return read_blob_arg(f, req, rd)", BLOB),
    m("RD2-B9 read_blob_start: the text starts after the `<` (KILL BL bl02: the `~q` text `<foo>(0x123)`)",
      "f.blob_start = rd.blob_start\n", "f.blob_start = rd.blob_start + 1\n", BLOB),
    m("RD2-B10 the tokeniser claims `<type>(...)` for blob(dead) only (KILL BL bl06, bl70: blob(resolve) is a syntax error)",
      "rd.blobs !== :error && blob_syntax_available(rd)", "rd.blobs !== :dead && blob_syntax_available(rd)", BLOB),
    m("RD2-B11 atom_to_blob_mode_ex: blob(resolve) stores dead (KILL BL bl70: a live stream stays dead)",
      "        rd.blobs = :resolve\n", "        rd.blobs = :dead\n", BLOB),
    m("RD2-B12 atom_to_blob_mode_ex: the domain of blob(bad) is `blobs` (KILL BL bl28: domain_error(blob, bad))",
      "PL_error(ld, ERR_DOMAIN, mk_sym(T, :blob), v)", "PL_error(ld, ERR_DOMAIN, mk_sym(T, :blobs), v)", BLOB),
    m("RD2-B13 the option table: blob/1 is named blobs (KILL BL bl01: the option is not seen, `<clause>(0x123)` is an operator_expected)",
      "PL_option_t(:unicode_atoms, OPT_ATOM),\n    PL_option_t(:blob, OPT_ATOM)\n)", "PL_option_t(:unicode_atoms, OPT_ATOM),\n    PL_option_t(:blobs, OPT_ATOM)\n)", BLOB),
    m("RD2-B14 the option table: quasi_quotations/1 is named quasi_quotation (KILL QA qa01: Q stays unbound)",
      "PL_option_t(:quasi_quotations, OPT_TERM)", "PL_option_t(:quasi_quotation, OPT_TERM)", QQ),
    # ---- src/pl-atom.jl: the dead blob
    m("RD2-A1 newDeadBlob: the dead blob is a text atom (KILL BL bl56: atom(T) holds, bl01: `atom`, bl57, bl59)",
      "    return first(lookupBlob(atoms, text, len, unavailable_blob))", "    return first(lookupBlob(atoms, text, len, text_atom))", BLONLY, A),
    m("RD2-A2 newDeadBlob: resolve is taken the wrong way round (KILL BL bl70: a live stream stays dead, bl06 `<foo>(1)`)",
      "    if resolve\n        live = lookupLiveBlob", "    if !resolve\n        live = lookupLiveBlob", BLOB, A),
    m("RD2-A3 deadBlobType: only a blob that is no dead blob has a type (KILL BL bl58: blob(T, foo), bl72: `stream`)",
      "(a.type === unavailable_blob && len >= 2 && a.name[1] == UInt8('<')) || return nothing", "(a.type !== unavailable_blob && len >= 2 && a.name[1] == UInt8('<')) || return nothing", BLONLY, A),
    m("RD2-A4 deadBlobType: the type name keeps the `<` (KILL BL bl58: the type is `foo`, bl72)",
      "return String(a.name[2:(e - 1)])", "return String(a.name[1:(e - 1)])", BLONLY, A),
    m("RD2-A5 unavailable_blob has the flag PL_BLOB_TEXT (KILL BL bl56: atom(T) holds, bl01)",
      'PL_blob_t(UInt32(0), "unavailable")', 'PL_blob_t(PL_BLOB_TEXT, "unavailable")', BLONLY, A),
    m("RD2-A6 scanLiveBlobs: a live blob is taken without comparing its text (KILL BL bl80: `<foo>` + the address of a stream is not that stream)",
      "        codeunits(out) == view(text, 1:len) || continue", "        true || continue", BLOB, A),
    # ---- src/pl-write.jl, src/pl-fli.jl
    m("RD2-W1 writeAtom: the dead blob and the live one swap their writers (KILL BL bl61, bl62, bl64: the dead blob's text; bl70)",
      "if is_blob(a) && atomValue(options.gd.atoms, blob_handle(a)).type === unavailable_blob", "if is_blob(a) && atomValue(options.gd.atoms, blob_handle(a)).type !== unavailable_blob", BLONLY, W),
    m("RD2-W2 write_unavailable: the text misses its last character (KILL BL bl61, bl62, bl64, bl65: `<foo>(0x123)`)",
      "text = String(at.name[1:(at.length)])", "text = String(at.name[1:(at.length - 1)])", BLONLY, W),
    m("RD2-W3 blob_written_text: the handle is written in decimal (KILL BL bl70, bl75: a live stream no longer writes as the text read)",
      'string(w; base=16)', 'string(w; base=10)', BLOB, W),
    m("RD2-F1 blob/2: a dead blob reports its blob type `unavailable` (KILL BL bl58: blob(T, foo), bl72)",
      "if name == unavailable_blob.name                        # dead blob: report the type it", "if name != unavailable_blob.name                        # dead blob: report the type it", BLONLY, FLI),
    m("RD2-F2 blob/2: the type read off the text is not unified (KILL BL bl58, bl72: `unavailable` for `foo`, `stream`)",
      "PL_unify_atom(ld, A2, _atom_from_text(T, dead))", "PL_unify_atom(ld, A2, mk_sym(T, Symbol(name)))", BLONLY, FLI),
]
