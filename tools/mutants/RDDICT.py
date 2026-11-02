# ORIGINAL: RDDICT's mutant list — no swipl-devel counterpart.
# tools/mutants/RDDICT.py — the mutation battery of RDDICT (D-0363 item 3, D-0368; R2b): the reader's dict branch written on wip/rddict —
# src/pl-read.jl: is_key_token, read_dict_start/key/resume/end, build_dict, build_attvar, build_labeled_subterm; src/pl-dict.jl:
# dict_order_term_refs; src/os/pl-prologflag.jl: setVarTagFlag, getVarTagFlag and the current_prolog_flag `var_tag` arm — run ONCE, in
# CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as DICT.py): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. Killed by test/core_lang/test_read_dict_swipl.jl (rows rdNN, mode rows rmNN). Verdicts: not yet run.
# The `old` strings are in the repo's formatted style BEFORE `tools/warm.sh fmt`: RE-FIT any that fmt rewraps at the first battery run.
# Anchors that occur more than once in src/pl-read.jl (re-counted with a python3 -I checker) are written with their neighbouring lines:
# E3/E4 start at `pv = f.dict_pv` / `if pv != 0` (the compound's read_compound_end has the same two lines), S1 at the `ld, f.pin,
# :dict_position,` line (read_compound_start has the same tuple), S3 at `if t == TK_DICT` (read_atomic's TK_NAME arm has the same
# put-atom line), `req.positions = ...` (with `req.maxpri = 999` above).
# NOT LISTED: read_dict_key's `req.maxpri = 999` (swipl reads `_{a:x:-y}` and `_{a:b;c}` as values: rows rd144, rd145; no row tells 999
#   from 1200); build_dict's VARTAG_WARNING printMessage (no row observes the message sink); `_key_atom`'s punctuation arm (no row reaches
#   it); `f.dict_pairs` count mutations (out-of-range term-stack reads); the `=== nothing && return 0` guards after get_token.
# TARGETS (audit D-0238): the step's own file, test_read_swipl.jl (term_to_atom through the same parser), test_type_discipline.jl; the flag
# mutants take test_prolog_flag_swipl.jl instead of test_read_swipl.jl.
TD = "test/core_lang/test_read_dict_swipl.jl"
TR = "test/core_lang/test_read_swipl.jl"
TF = "test/core_lang/test_prolog_flag_swipl.jl"
TT = "test/test_type_discipline.jl"
TARGETS = [TD, TR, TT]
FTARGETS = [TD, TF, TT]
R = "src/pl-read.jl"
D = "src/pl-dict.jl"
P = "src/os/pl-prologflag.jl"
KT = "t == TK_NAME || t == TK_QNAME || t == TK_FUNCTOR || t == TK_DICT"
PH = "    pv = f.dict_pv\n\n    if pv != 0\n"
PU = PH + "        set_range_position(rd.ld, f.pin, -1, token.end_)\n        PL_unify_nil(rd.ld, pv + 1) || return 0     # P_ARG\n"
SD = "                ld, f.pin, :dict_position,          #   PL_INT64, token->start, PL_VARIABLE,\n"
CMP = "compareStandard_cells(ld, value, vp, true) != CMP_EQUAL"
MUTANTS = [
    dict(id="RDDICT-K1 is_key_token refuses a quoted name as a key (KILL `_{'a b':1}`, `_{'':1}`: rd29, rd32)", file=R, targets=TARGETS,
         old=KT, new="t == TK_NAME || t == TK_FUNCTOR || t == TK_DICT"),
    dict(id="RDDICT-K2 is_key_token refuses a functor token as a key (KILL `_{f(x):1}`: colon_expected at 2, rd60)", file=R, targets=TARGETS,
         old=KT, new="t == TK_NAME || t == TK_QNAME || t == TK_DICT"),
    dict(id="RDDICT-K3 is_key_token refuses a dict-class token as a key (KILL `_{a{}:1}`, `_{a{b:1}:2}`: rd127, rd128)", file=R, targets=TARGETS,
         old=KT, new="t == TK_NAME || t == TK_QNAME || t == TK_FUNCTOR"),
    dict(id="RDDICT-K4 is_key_token accepts `|`, `,` and the closing brackets as keys (KILL rd72, rd129, rd130, rd131)", file=R, targets=TARGETS,
         old="c == Int('}') || c == Int(']') || c == Int('|') || c == Int(',')", new="c == Int('}')"),
    dict(id="RDDICT-S1 read_dict_start: the tag's position ends at its start (KILL rd115, rd116, rd118)", file=R, targets=TARGETS,
         old=SD + "                (token.start, _POS_VARIABLE, token.start, token.end_),",
         new=SD + "                (token.start, _POS_VARIABLE, token.start, token.start),"),
    dict(id="RDDICT-S2 read_dict_start: an empty dict `{}` is read as a key (KILL rd01, rd02, rd06, rd117)", file=R, targets=TARGETS,
         old="if tstart.type == TK_NAME && sym_key(_token_atom(tstart)) == sym_key(mk_sym(T, Symbol(\"{}\")))",
         new="if false && sym_key(_token_atom(tstart)) == sym_key(mk_sym(T, Symbol(\"{}\")))"),
    dict(id="RDDICT-S3 read_dict_start: an atom tag is dropped (KILL rd04, rd06, rd08, rd35)", file=R, targets=TARGETS,
         old="    if t == TK_DICT\n        term = alloc_term(rd)\n        _setHandle!(term, _token_atom(token), rd)   # PL_put_atom(term, token->value.atom)",
         new="    if t == TK_DICT\n        term = alloc_term(rd)\n        nothing   # tag dropped"),
    dict(id="RDDICT-S4 read_dict_start: a variable tag is not tied to its variable (KILL rd150: `X{a:X}`)", file=R, targets=TARGETS,
         old="rd.term_stack.vars[term] = token.variable   # setHandle(term, token->value.variable->signature)",
         new="nothing   # variable class dropped"),
    dict(id="RDDICT-D1 read_dict_key: positions link the key list's head to the wrong cell (KILL rd115, rd116, rd121, rd123)", file=R, targets=TARGETS,
         old="!PL_unify_list(ld, pv + 1, pv, pv + 1)", new="!PL_unify_list(ld, pv + 1, pv + 2, pv + 1)"),
    dict(id="RDDICT-D2 read_dict_key: every number key is key_domain (KILL rd09, rd12, rd140, rd141)", file=R, targets=TARGETS,
         old="if n.type == V_INTEGER && valInt(consInt(n.i)) == n.i", new="if false && valInt(consInt(n.i)) == n.i"),
    dict(id="RDDICT-D3 read_dict_key: a number that is no small integer is accepted (KILL rd135, rd138, rd139: 2^56, -2^56-1)", file=R, targets=TARGETS,
         old="if n.type == V_INTEGER && valInt(consInt(n.i)) == n.i", new="if n.type == V_INTEGER"),
    dict(id="RDDICT-D4 read_dict_key: a non-integer number key answers key_expected (KILL rd58, rd59, rd135)", file=R, targets=TARGETS,
         old="syntaxError(\"key_domain\", rd)", new="syntaxError(\"key_expected\", rd)"),
    dict(id="RDDICT-D5 read_dict_key: a key that is no key token answers colon_expected (KILL rd62, rd63, rd80, rd87: key_expected pins)", file=R, targets=TARGETS,
         old="syntaxError(\"key_expected\", rd))", new="syntaxError(\"colon_expected\", rd))"),
    dict(id="RDDICT-D6 read_dict_key: any key token is a separator (KILL rd55, rd81, rd82: `_{a}`, `_{a;1}`, `_{a=1}`)", file=R, targets=TARGETS,
         old="if !is_key_token(sep, rd) || sym_key(_key_atom(sep)) != sym_key(mk_sym(T, :(:)))", new="if !is_key_token(sep, rd)"),
    dict(id="RDDICT-D7 read_dict_key: the value stops at `}` only (KILL rd04, rd05, rd15, rd16: two or more pairs)", file=R, targets=TARGETS,
         old="req.stop = \",}\"", new="req.stop = \"}\""),
    dict(id="RDDICT-D8 read_dict_key: the separator's start takes its end (KILL rd115, rd116, rd118)", file=R, targets=TARGETS,
         old="ld.gstack[p + 3] = _gnd_word!(ld, mk_gnd(T, sep.start))", new="ld.gstack[p + 3] = _gnd_word!(ld, mk_gnd(T, sep.end_))"),
    dict(id="RDDICT-D9 read_dict_key: the key's span ends at its start (KILL rd115, rd116)", file=R, targets=TARGETS,
         old="ld.gstack[q + 2] = _gnd_word!(ld, mk_gnd(T, kend))", new="ld.gstack[q + 2] = _gnd_word!(ld, mk_gnd(T, kstart))"),
    dict(id="RDDICT-D10 read_dict_key: the key's cell holds the start position (KILL rd115, rd116, rd120, rd125)", file=R, targets=TARGETS,
         old="ld.gstack[p + 5] = rd.term_stack.words[key_term]", new="ld.gstack[p + 5] = _gnd_word!(ld, mk_gnd(T, kstart))"),
    dict(id="RDDICT-D11 read_dict_key: P_VALUE is not reset for the next key (KILL rd116, rd123)", file=R, targets=TARGETS,
         old="PL_put_variable(ld, pv + 2)", new="nothing"),
    dict(id="RDDICT-D12 read_dict_key: the value's positions are not requested (KILL rd115, rd116, rd121)", file=R, targets=TARGETS,
         old="req.maxpri = 999\n    req.positions = pv != 0 ? pv + 2 : 0", new="req.maxpri = 999\n    req.positions = 0"),
    dict(id="RDDICT-E1 read_dict_resume: `}` takes the place of `,` as the pair separator (KILL rd04, rd05, rd15)", file=R, targets=TARGETS,
         old="tk.character == Int(',') && return read_dict_key(f, req, rd)", new="tk.character == Int('}') && return read_dict_key(f, req, rd)"),
    dict(id="RDDICT-E2 read_dict_resume: the pair's end is not set from the value (KILL rd115, rd116)", file=R, targets=TARGETS,
         old="set_range_position(rd.ld, pv, -1, vend)", new="set_range_position(rd.ld, pv, -1, -1)"),
    dict(id="RDDICT-E3 read_dict_end: the dict's span ends at the brace's start (KILL rd115, rd117, rd118, rd121)", file=R, targets=TARGETS,
         old=PU, new=PU.replace("token.end_", "token.start")),
    dict(id="RDDICT-E4 read_dict_end: the pair list of the positions is left open (KILL rd115, rd117)", file=R, targets=TARGETS,
         old=PU, new=PH + "        set_range_position(rd.ld, f.pin, -1, token.end_)\n"),
    dict(id="RDDICT-E5 read_dict_end: the build's result is inverted (KILL rd01, rd03: every dict read)", file=R, targets=TARGETS,
         old="return build_dict(f.dict_pairs, rd) ? 1 : 0", new="return build_dict(f.dict_pairs, rd) ? 0 : 1"),
    dict(id="RDDICT-B1 build_dict: an anonymous variable tag is no variable tag (KILL rm01, rm02, rm04, rm05 in modes error, warning, attvar, #)", file=R, targets=TARGETS,
         old="if tv == TS_UNBOUND || tv >= 0", new="if tv >= 0"),
    dict(id="RDDICT-B2 build_dict: `error` mode raises the warning's error id (KILL rm01, rm02, rm07 of mode error)", file=R, targets=TARGETS,
         old="return errorWarning(\"var_tag\", nothing, rd)", new="return errorWarning(\"warning_var_tag\", nothing, rd)"),
    dict(id="RDDICT-B3 build_dict: `attvar` mode builds a dict (KILL rm01, rm02, rm10-rm12, rm14-rm16 of mode attvar)", file=R, targets=TARGETS,
         old="elseif vartag == VARTAG_ATTVAR", new="elseif false"),
    dict(id="RDDICT-B4 build_dict: `#` and `warning` modes leave the tag a variable (KILL rm01, rm02, rm04, rm05 of those modes)", file=R, targets=TARGETS,
         old="tag = ATOM_dyndict", new="nothing"),
    dict(id="RDDICT-B5 build_dict: the duplicate is found only from the third sorted key (KILL rd57, rd78, rd83)", file=R, targets=TARGETS,
         old="if dupl != 0", new="if dupl > 1"),
    dict(id="RDDICT-B6 build_dict: the duplicate key reported is the first sorted key (KILL rd133, rd134: names b, z)", file=R, targets=TARGETS,
         old="kw = ts.words[argv + 1 + indexes[dupl + 1] * 2]", new="kw = ts.words[argv + 1 + indexes[1] * 2]"),
    dict(id="RDDICT-B7 build_dict: the duplicate key's atom-or-integer test is inverted (KILL rd57, rd78, rd84, rd85)", file=R, targets=TARGETS,
         old="key = isAtomW(kw) ? _atom_value(ld, kw) : _value_term(ld, kw)", new="key = !isAtomW(kw) ? _atom_value(ld, kw) : _value_term(ld, kw)"),
    dict(id="RDDICT-B8 build_dict: a variable-tag dict gets the tag word 0 (KILL rd01, rd03, rd05)", file=R, targets=TARGETS,
         old="if tag != 0", new="if tag == 0"),
    dict(id="RDDICT-B9 build_dict: a value takes the key's term (KILL rd03, rd04, rd05, rd09)", file=R, targets=TARGETS,
         old="readValHandle!(argv + p * 2 + 2, argp + 2 + 2 * i, rd)  # value", new="readValHandle!(argv + p * 2 + 1, argp + 2 + 2 * i, rd)  # value"),
    dict(id="RDDICT-A1 build_attvar: a pair named `=` is an attribute (KILL rm18: label_on_attvar)", file=R, targets=TARGETS,
         old="        if name == atom_equals\n            return errorWarning(\"label_on_attvar\", nothing, rd)",
         new="        if false\n            return errorWarning(\"label_on_attvar\", nothing, rd)"),
    dict(id="RDDICT-A2 build_attvar: a repeated attribute with another value is accepted (KILL rm17)", file=R, targets=TARGETS,
         old=CMP, new="false"),
    dict(id="RDDICT-A3 build_attvar: the same attribute with an equal value is a duplicate (KILL rm11)", file=R, targets=TARGETS,
         old=CMP, new=CMP.replace("!=", "==")),
    dict(id="RDDICT-A4 build_attvar: attvar_on_label is raised as label_on_attvar (KILL rm21)", file=R, targets=TARGETS,
         old="errorWarning(\"attvar_on_label\", nothing, rd)", new="errorWarning(\"label_on_attvar\", nothing, rd)"),
    dict(id="RDDICT-A5 build_attvar: `X{}` is an error (KILL rm13 of mode attvar: `X{}`)", file=R, targets=TARGETS,
         old="pairs == 0 && return true", new="pairs == 0 && return false"),
    dict(id="RDDICT-L1 build_labeled_subterm: a label on an attributed variable is accepted (KILL rm20)", file=R, targets=TARGETS,
         old="if PL_is_attvar(ld, var.variable)", new="if false"),
    dict(id="RDDICT-L2 build_labeled_subterm: a repeated label raises label_on_attvar (KILL rm19)", file=R, targets=TARGETS,
         old="errorWarning(\"duplicate_label_value\", nothing, rd)", new="errorWarning(\"label_on_attvar\", nothing, rd)"),
    dict(id="RDDICT-L3 build_labeled_subterm: the label's variable is not marked labeled (KILL rm19, rm21)", file=R, targets=TARGETS,
         old="var.labeled = true", new="nothing"),
    dict(id="RDDICT-O1 dict_order_term_refs: the keys are not sorted (KILL rd57, rd79, rd83: a duplicate that is not adjacent)", file=D, targets=[TD, TT],
         old="ord = sortperm(word[words[base + indexes[i] * 2] for i in 1:count])", new="ord = collect(1:count)"),
    dict(id="RDDICT-O2 dict_order_term_refs: the duplicate check needs three keys (KILL rd57, rd78, rd83)", file=D, targets=[TD, TT],
         old="if count > 1", new="if count > 2"),
    dict(id="RDDICT-O3 dict_order_term_refs: each key is compared with the first only (KILL rd133, rd134)", file=D, targets=[TD, TT],
         old="            k = k2\n", new="            nothing\n"),
    dict(id="RDDICT-O4 dict_order_term_refs: the duplicate's index is one too high (KILL rd57, rd78, rd133)", file=D, targets=[TD, TT],
         old="k == k2 && return i - 1 ", new="k == k2 && return i "),
    dict(id="RDDICT-V1 setVarTagFlag: `#` sets the attvar bits (KILL the var_tag setter testset)", file=P, targets=FTARGETS,
         old="        f = VARTAG_DYNDICT\n", new="        f = VARTAG_ATTVAR\n"),
    dict(id="RDDICT-V2 setVarTagFlag: the old mode's bits are kept (KILL the setter testset: `other | ERROR`)", file=P, targets=FTARGETS,
         old="    flags &= ~VARTAG_MASK\n    flags |= f\n\n    return flags", new="    flags |= f\n\n    return flags"),
    dict(id="RDDICT-V3 setVarTagFlag: the domain error names var_prefix (KILL the setter testset's enc check)", file=P, targets=FTARGETS,
         old="PL_error(ld, ERR_DOMAIN, mk_sym(T, :var_tag), value)", new="PL_error(ld, ERR_DOMAIN, mk_sym(T, :var_prefix), value)"),
    dict(id="RDDICT-V4 setVarTagFlag: a bad atom answers the flags, not `nothing` (KILL the setter testset)", file=P, targets=FTARGETS,
         old="        PL_error(ld, ERR_DOMAIN, mk_sym(T, :var_tag), value)\n        return nothing",
         new="        PL_error(ld, ERR_DOMAIN, mk_sym(T, :var_tag), value)\n        return flags"),
    dict(id="RDDICT-V5 getVarTagFlag: the error mode is named warning (KILL the getter testset, rm24 of mode error)", file=P, targets=FTARGETS,
         old="    m == VARTAG_ERROR && return mk_sym(T, :error)", new="    m == VARTAG_ERROR && return mk_sym(T, :warning)"),
    dict(id="RDDICT-V6 current_prolog_flag: var_tag answers `dict` for every module (KILL rm24 of modes error, warning, attvar, #)", file=P, targets=FTARGETS,
         old="return PL_unify_atom(ld, val, getVarTagFlag(T, mdl.flags))", new="return PL_unify_atom(ld, val, mk_sym(T, :dict))"),
]
