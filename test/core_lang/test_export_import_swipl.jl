# ORIGINAL: MOD5a's gate (lk-channel evidence/r2/design/modules.md §7) — export/1, import/1, '$import'/2, '$undefined_export'/2 and '$def_modules'/2, against swipl 10.1.19; the rows are tests/core_lang/test_module.pl-style (pl-modul.c export_pi, import, find_modules_with_defs), mirrored from running swipl; no swipl-devel test file counterpart
# test/core_lang/test_export_import_swipl.jl — the export and import of pl-modul.c (MOD5a), through a PROGRAM (the pattern of
# test/core_lang/test_at_body_swipl.jl): `export_pi1` / `export_pi` (`export/1`: a PI, a comma list, qualified, `Name//Arity`,
# the errors of `get_functor`), `exportProcedure` (the public table), `import_` (`import/1`, `'$import'/2`: the clash, the
# already-imported, the weak and strong strength, `atomToImportStrength`, the already-done case, an undefined `old` that is re-pointed
# and the other modules sharing its definition fixed up by `fixExport`, `autoImport`), `'$undefined_export'/2` and `'$def_modules'/2`
# (`find_modules_with_defs` over the default modules):
#   * A PROGRAM consulted by the kernel's loader — directives that assert clauses into modules — and cases `t_<id>(R)` run IN ORDER
#     in one database, each wrapped in `catch(Goal, error(F, _), R = raised(F))`: a row builds on the exports and imports of the
#     rows before it (the module names are the rows' state).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_at_body_swipl.jl's driver; lk-channel
#     evidence/MOD5a/mx_rows.out in the MOD5a branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * Where the kernel's export order differs (the public table is walked in insertion order, swipl's follows its hash table,
#     D-0149), a row sorts with `msort/2` before it answers.
#   * Not observable here (and so not rows): the warnings of `import/1` (`import_private`, `ignored_weak_import`: stderr in swipl).
#     `module/2` and the loader's export of a module's list belong to MOD5b (`'$declare_module'/6`).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — export and import (src/pl-modul.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mxs(x) = lk_sym(_MX, Symbol(x))

_mx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mx_enc(t::_MX, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_at_body_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MX_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function _mx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: modules made by asserting into them. ma: pa/1 (two clauses), pb/2, pc/0; mb: pd/1; mc: a LOCAL pa/1 (the clash);
# md: pf/1, pg/1; mwq: qq/1, rr/1 (the definitions the fix-up rows import); mauto: dummy/0 (a module whose default import module is user).
const _MX_PROGRAM = raw"""
:- assertz(ma:pa(1)).
:- assertz(ma:pa(2)).
:- assertz(ma:pb(a, b)).
:- assertz(ma:pc).
:- assertz(mb:pd(x)).
:- assertz(mc:pa(local)).
:- assertz(md:pf(1)).
:- assertz(md:pg(2)).
:- assertz(mwq:qq(42)).
:- assertz(mwq:rr(5)).
:- assertz(mauto:dummy).
mx_setup :- ma:export(pdir/0).
:- mx_setup.
"""

# UNVERIFIED on the kernel: gate decides — nothing here was run on the kernel. The rows that lean on more than MOD5a's own code:
# e09 (`Name//Arity` in get_functor), e21-e23 (`'$module_property'(M, exports(_))` of a module made by export, an ISO skip, user),
# e24 (the acyclic check at depth 100), d05 (assertz/1 defined in the module `system`), d11/d12 (a head or qualified element given
# to get_functor with GP_NOT_QUALIFIED: swipl answers []), i09/i12 (`import(foo)`, a same-module import: swipl answers ok), i13,
# i15 (a call of an undefined procedure makes the procedure in the module, which fixExport then follows), d13 ('$set_source_module'/1).
# (id, goal), run IN ORDER
const _MX_CASES = [
    # e01-e10: export/1 — a qualified PI, a context-qualified one (ma:export), a comma list, the list form (swipl's answer), a
    # name/arity not seen before, '$undefined_export'/2 on it, the definition arriving, re-export, `Name//Arity`, a predicate
    # defined in the default module (not an undefined export)
    ("e01", raw"export(ma:pa/1), '$module_property'(ma, exports(L)), msort(L, R)"),
    ("e02", raw"ma:export(pb/2), '$module_property'(ma, exports(L)), msort(L, R)"),
    ("e03", raw"export(ma:(pa/1, pc/0)), '$module_property'(ma, exports(L)), msort(L, R)"),
    ("e04", raw"export(ma:[pa/1]), R = ok"),
    ("e05", raw"export(ma:brandnew/0), '$module_property'(ma, exports(L)), msort(L, R)"),
    ("e06", raw"'$undefined_export'(ma, R0), msort(R0, R)"),
    ("e07", raw"assertz(ma:brandnew), '$undefined_export'(ma, R)"),
    ("e08", raw"export(ma:undefp/3), export(ma:undefp/3), '$undefined_export'(ma, R)"),
    ("e09", raw"export(ma:dcgp//2), '$module_property'(ma, exports(L)), msort(L, R)"),
    (
        "e10",
        raw"assertz(user:pu(1)), export(ma:pu/1), '$undefined_export'(ma, R0), msort(R0, R)"
    ),
    # e11-e20: the errors of export/1 (get_functor with GF_NAMEARITY): instantiation, not a PI, a non-integer arity, an unbound
    # arity, an unbound name, a number name, a negative arity, an unbound goal under a module, an unbound element, a bad second element
    ("e11", raw"export(_), R = ok"),
    ("e12", raw"export(foo), R = ok"),
    ("e13", raw"export(foo/a), R = ok"),
    ("e14", raw"export(foo/_), R = ok"),
    ("e15", raw"export(_/1), R = ok"),
    ("e16", raw"export(1/2), R = ok"),
    ("e17", raw"export(foo/(-1)), R = ok"),
    ("e18", raw"export(ma:_), R = ok"),
    ("e19", raw"export((ma:pa/1, _)), R = ok"),
    ("e20", raw"export(ma:(pa/1, bad)), R = ok"),
    # e21-e24: a module made by naming it in export, an ISO built-in (skipped), export into user, a cyclic comma list
    ("e21", raw"export(nomx:p/1), '$module_property'(nomx, exports(R))"),
    ("e22", raw"export(ma:atom_length/2), '$module_property'(ma, exports(L)), msort(L, R)"),
    ("e23", raw"export(user:exuser/0), '$module_property'(user, exports(L)), msort(L, R)"),
    (
        "e24",
        raw"X = (ma:pa/1, X), catch(export(X), error(type_error(T, _), _), true), R = T"
    ),
    # e25: a comma list of three (the right operand is itself a comma list)
    (
        "e25",
        raw"export(ma:(n1/0, n2/0, n3/0)), '$module_property'(ma, exports(L)), msort(L, R)"
    ),
    # u01-u05: '$undefined_export'/2 — its errors (instantiation, type, no such module) and a failing unification
    ("u01", raw"'$undefined_export'(_, R)"),
    ("u02", raw"'$undefined_export'(1, R)"),
    ("u03", raw"'$undefined_export'(nomodule_zz, R)"),
    ("u04", raw"( '$undefined_export'(ma, [a]) -> R = yes ; R = no )"),
    ("u05", raw"'$undefined_export'(md, R)"),
    # d01-d13: '$def_modules'/2 — the source module (user), a qualifier, a qualifier that is no module, a `$` name (system), the
    # empty list, nothing defined, the target limit (11), the errors, a qualified element, '$set_source_module'
    ("d01", raw"'$def_modules'([pu/1, pa/1], R)"),
    ("d02", raw"'$def_modules'(ma:[pa/1, pb/2, pc/0, nosuch/0], R)"),
    ("d03", raw"'$def_modules'(mc:[pa/1, pu/1], R0), msort(R0, R)"),
    ("d04", raw"'$def_modules'(nosuchmod:[pu/1], R)"),
    ("d05", raw"'$def_modules'('$nosuch':[assertz/1], R)"),
    ("d06", raw"'$def_modules'([], R)"),
    ("d07", raw"'$def_modules'([nothing_at_all/9], R)"),
    (
        "d08",
        raw"'$def_modules'([a/1, b/1, c/1, d/1, e/1, f/1, g/1, h/1, i/1, j/1, k/1], R)"
    ),
    ("d09", raw"'$def_modules'([pu/1|_], R)"),
    ("d10", raw"'$def_modules'(foo, R)"),
    ("d11", raw"'$def_modules'([foo], R)"),
    ("d12", raw"'$def_modules'([ma:pa/1], R)"),
    # d18-d19: a procedure that exists but is undefined is no definition; a `$` qualifier that is no module is `system`, whose
    # default module list does not hold user's pu/1
    ("d18", raw"'$def_modules'(ma:[undefp/3, pu/1], R)"),
    ("d19", raw"'$def_modules'('$nosuch':[pu/1], R)"),
    (
        "d13",
        raw"'$current_source_module'(Old), '$set_source_module'(ma), '$def_modules'([pa/1, pu/1], R0), '$set_source_module'(Old), msort(R0, R)"
    ),
    # i01-i07: import/1 — into another module (context-qualified), again (already done), a predicate that is not exported, a local
    # definition in the destination (the clash), a predicate already imported from another module, into user, a doubly qualified PI
    ("i01", raw"mi:import(ma:pa/1), findall(X, mi:pa(X), R)"),
    ("i02", raw"mi:import(ma:pa/1), findall(X, mi:pa(X), R)"),
    ("i03", raw"mi:import(mb:pd/1), findall(X, mi:pd(X), R)"),
    ("i04", raw"mc:import(ma:pa/1), R = ok"),
    ("i05", raw"mi:import(mc:pa/1), R = ok"),
    ("i06", raw"import(ma:pa/1), findall(X, user:pa(X), R)"),
    ("i07", raw"import(user:ma:pb/2), findall(X-Y, pb(X, Y), R)"),
    # i08-i12: the errors of import/1 and the same-module import (swipl's answer)
    ("i08", raw"import(_), R = ok"),
    ("i09", raw"import(foo), R = ok"),
    ("i10", raw"import(foo/a), R = ok"),
    ("i11", raw"import(ma:_), R = ok"),
    ("i12", raw"import(selfimp/1), R = ok"),
    # i13-i16: an import of a predicate nobody defines (the call's error), an export followed by an import followed by the
    # definition, and `fixExport`: a third module sharing an undefined definition follows the re-pointing of its owner
    ("i13", raw"mi:import(ma:undefq/2), mi:undefq(1, 2), R = ok"),
    # u06: an exported predicate that is imported (and undefined) is not an undefined export
    ("u06", raw"export(mi:undefq/2), '$undefined_export'(mi, R)"),
    (
        "i14",
        raw"export(mx:late/1), mj:import(mx:late/1), assertz(mx:late(7)), findall(X, mj:late(X), R)"
    ),
    (
        "i15",
        raw"catch(mfx:qq(_), error(_, _), true), mfz:import(mfx:qq/1), mfx:import(mwq:qq/1), mfz:qq(A), mfx:qq(B), R = A-B"
    ),
    (
        "i16",
        raw"catch(mgx:rr(_), error(_, _), true), mgx:import(mwq:rr/1), mgx:import(mwq:rr/1), mgx:rr(R)"
    ),
    # i17: a name that the default module (user) defines, imported through a module that does not
    ("i17", raw"assertz(user:zz(11)), mhx:import(mauto:zz/1), findall(X, mhx:zz(X), R)"),
    # w01-w09: '$import'/2 — weak, over a local definition (kept), strong over it (the clash), the strength errors (domain,
    # instantiation, type), weak then strong of the same definition, strong, weak then a different strong import
    ("w01", raw"mw:'$import'(ma:pb/2, weak), findall(X-Y, mw:pb(X, Y), R)"),
    (
        "w02",
        raw"assertz(md:pa(local_md)), md:'$import'(ma:pa/1, weak), findall(X, md:pa(X), R)"
    ),
    ("w03", raw"md:'$import'(ma:pa/1, strong), R = ok"),
    ("w04", raw"'$import'(ma:pa/1, bogus), R = ok"),
    ("w05", raw"'$import'(ma:pa/1, _), R = ok"),
    ("w06", raw"'$import'(ma:pa/1, 1), R = ok"),
    (
        "w07",
        raw"mw:'$import'(ma:pb/2, weak), mw:'$import'(ma:pb/2, strong), findall(X-Y, mw:pb(X, Y), R)"
    ),
    ("w08", raw"mw2:'$import'(ma:pb/2, strong), findall(X-Y, mw2:pb(X, Y), R)"),
    ("w09", raw"mw3:'$import'(ma:pa/1, weak), mw3:import(mc:pa/1), R = ok"),
    # d14-d16: '$def_modules'/2 after the imports: the importing module holds the procedure (its definition is the exporter's)
    ("d14", raw"'$def_modules'(mi:[pa/1], R)"),
    ("d15", raw"'$def_modules'([pa/1, pb/2], R0), msort(R0, R)"),
    ("d16", raw"'$def_modules'(ma:[pa/1], R)"),
    # d20: a qualified element is not stripped (swipl's answer); user holds pa/1 by now
    ("d20", raw"'$def_modules'([ma:pa/1], R)"),
    # d17: exactly ten targets are taken (the limit is the eleventh)
    ("d17", raw"'$def_modules'([pu/1, a/1, b/1, c/1, d/1, e/1, f/1, g/1, h/1, i/1], R)"),
    # d21 (EQ2, audit D-0472 item 4; pinned from swipl 10.1.20-18168e62): '$def_modules'/2 is registered PL_FA_TRANSPARENT (pl-modul.c
    # PRED_IMPL("$def_modules", 2, def_modules, PL_FA_TRANSPARENT)), so its definition carries P_TRANSPARENT: the attribute answers 1.
    # KILLS MOD5a-R4 (registration without PL_FA_TRANSPARENT: the attribute answers 0)
    ("d21", raw"'$get_predicate_attribute'('$def_modules'(_,_), transparent, V), R = V")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/MOD5a/mx_rows.out)
const _MX_PINNED = [
    "ok",
    "t_e01 c[116,95,101,48,49]/1(c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),nil)))",
    "t_e02 c[116,95,101,48,50]/1(c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),nil))))",
    "t_e03 c[116,95,101,48,51]/1(c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),nil)))))",
    "t_e04 c[116,95,101,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil))))",
    "t_e05 c[116,95,101,48,53]/1(c[91,124,93]/2(c[47]/2(a[98,114,97,110,100,110,101,119],i0),c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),nil))))))",
    "t_e06 c[116,95,101,48,54]/1(c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[98,114,97,110,100,110,101,119],i0)),c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[112,100,105,114],i0)),nil)))",
    "t_e07 c[116,95,101,48,55]/1(c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[112,100,105,114],i0)),nil))",
    "t_e08 c[116,95,101,48,56]/1(c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[112,100,105,114],i0)),c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[117,110,100,101,102,112],i3)),nil)))",
    "t_e09 c[116,95,101,48,57]/1(c[91,124,93]/2(c[47]/2(a[98,114,97,110,100,110,101,119],i0),c[91,124,93]/2(c[47]/2(a[100,99,103,112],i4),c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),c[91,124,93]/2(c[47]/2(a[117,110,100,101,102,112],i3),nil))))))))",
    "t_e10 c[116,95,101,49,48]/1(c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[100,99,103,112],i4)),c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[112,100,105,114],i0)),c[91,124,93]/2(c[58]/2(a[109,97],c[47]/2(a[117,110,100,101,102,112],i3)),nil))))",
    "t_e11 c[116,95,101,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e12 c[116,95,101,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],a[102,111,111])))",
    "t_e13 c[116,95,101,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_e14 c[116,95,101,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e15 c[116,95,101,49,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e16 c[116,95,101,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_e17 c[116,95,101,49,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_e18 c[116,95,101,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e19 c[116,95,101,49,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e20 c[116,95,101,50,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],a[98,97,100])))",
    "t_e21 c[116,95,101,50,49]/1(c[91,124,93]/2(c[47]/2(a[112],i1),nil))",
    "t_e22 c[116,95,101,50,50]/1(c[91,124,93]/2(c[47]/2(a[98,114,97,110,100,110,101,119],i0),c[91,124,93]/2(c[47]/2(a[100,99,103,112],i4),c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),c[91,124,93]/2(c[47]/2(a[112,117],i1),c[91,124,93]/2(c[47]/2(a[117,110,100,101,102,112],i3),nil)))))))))",
    "t_e23 c[116,95,101,50,51]/1(c[91,124,93]/2(c[47]/2(a[101,120,117,115,101,114],i0),nil))",
    "t_e24 c[116,95,101,50,52]/1(a[97,99,121,99,108,105,99,95,116,101,114,109])",
    "t_e25 c[116,95,101,50,53]/1(c[91,124,93]/2(c[47]/2(a[98,114,97,110,100,110,101,119],i0),c[91,124,93]/2(c[47]/2(a[100,99,103,112],i4),c[91,124,93]/2(c[47]/2(a[110,49],i0),c[91,124,93]/2(c[47]/2(a[110,50],i0),c[91,124,93]/2(c[47]/2(a[110,51],i0),c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),c[91,124,93]/2(c[47]/2(a[112,100,105,114],i0),c[91,124,93]/2(c[47]/2(a[112,117],i1),c[91,124,93]/2(c[47]/2(a[117,110,100,101,102,112],i3),nil))))))))))))",
    "t_u01 c[116,95,117,48,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_u02 c[116,95,117,48,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_u03 c[116,95,117,48,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],a[110,111,109,111,100,117,108,101,95,122,122])))",
    "t_u04 c[116,95,117,48,52]/1(a[110,111])",
    "t_u05 c[116,95,117,48,53]/1(nil)",
    "t_d01 c[116,95,100,48,49]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil))",
    "t_d02 c[116,95,100,48,50]/1(c[91,124,93]/2(c[45]/2(a[109,97],c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),c[91,124,93]/2(c[47]/2(a[112,99],i0),nil)))),nil))",
    "t_d03 c[116,95,100,48,51]/1(c[91,124,93]/2(c[45]/2(a[109,99],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil)),c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil)))",
    "t_d04 c[116,95,100,48,52]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil))",
    "t_d05 c[116,95,100,48,53]/1(c[91,124,93]/2(c[45]/2(a[115,121,115,116,101,109],c[91,124,93]/2(c[47]/2(a[97,115,115,101,114,116,122],i1),nil)),nil))",
    "t_d06 c[116,95,100,48,54]/1(nil)",
    "t_d07 c[116,95,100,48,55]/1(nil)",
    "t_d08 c[116,95,100,48,56]/1(c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(a[116,97,114,103,101,116,95,112,114,101,100,105,99,97,116,101,115])))",
    "t_d09 c[116,95,100,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d10 c[116,95,100,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_d11 c[116,95,100,49,49]/1(nil)",
    "t_d12 c[116,95,100,49,50]/1(nil)",
    "t_d18 c[116,95,100,49,56]/1(c[91,124,93]/2(c[45]/2(a[109,97],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil)))",
    "t_d19 c[116,95,100,49,57]/1(nil)",
    "t_d13 c[116,95,100,49,51]/1(c[91,124,93]/2(c[45]/2(a[109,97],c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,117],i1),nil))),c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil)))",
    "t_i01 c[116,95,105,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_i02 c[116,95,105,48,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_i03 c[116,95,105,48,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_i04 c[116,95,105,48,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(c[105,109,112,111,114,116,95,105,110,116,111]/1(a[109,99]),a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,97],c[47]/2(a[112,97],i1)))))",
    "t_i05 c[116,95,105,48,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(c[105,109,112,111,114,116,95,105,110,116,111]/1(a[109,105]),a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,99],c[47]/2(a[112,97],i1)))))",
    "t_i06 c[116,95,105,48,54]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_i07 c[116,95,105,48,55]/1(c[91,124,93]/2(c[45]/2(a[97],a[98]),nil))",
    "t_i08 c[116,95,105,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_i09 c[116,95,105,48,57]/1(a[111,107])",
    "t_i10 c[116,95,105,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_i11 c[116,95,105,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_i12 c[116,95,105,49,50]/1(a[111,107])",
    "t_i13 c[116,95,105,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,97],c[47]/2(a[117,110,100,101,102,113],i2)))))",
    "t_u06 c[116,95,117,48,54]/1(nil)",
    "t_i14 c[116,95,105,49,52]/1(c[91,124,93]/2(i7,nil))",
    "t_i15 c[116,95,105,49,53]/1(c[45]/2(i42,i42))",
    "t_i16 c[116,95,105,49,54]/1(i5)",
    "t_i17 c[116,95,105,49,55]/1(c[91,124,93]/2(i11,nil))",
    "t_w01 c[116,95,119,48,49]/1(c[91,124,93]/2(c[45]/2(a[97],a[98]),nil))",
    "t_w02 c[116,95,119,48,50]/1(c[91,124,93]/2(a[108,111,99,97,108,95,109,100],nil))",
    "t_w03 c[116,95,119,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(c[105,109,112,111,114,116,95,105,110,116,111]/1(a[109,100]),a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,97],c[47]/2(a[112,97],i1)))))",
    "t_w04 c[116,95,119,48,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[105,109,112,111,114,116,95,116,121,112,101],a[98,111,103,117,115])))",
    "t_w05 c[116,95,119,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_w06 c[116,95,119,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_w07 c[116,95,119,48,55]/1(c[91,124,93]/2(c[45]/2(a[97],a[98]),nil))",
    "t_w08 c[116,95,119,48,56]/1(c[91,124,93]/2(c[45]/2(a[97],a[98]),nil))",
    "t_w09 c[116,95,119,48,57]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(c[105,109,112,111,114,116,95,105,110,116,111]/1(a[109,119,51]),a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,99],c[47]/2(a[112,97],i1)))))",
    "t_d14 c[116,95,100,49,52]/1(c[91,124,93]/2(c[45]/2(a[109,105],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil)),c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil)),nil)))",
    "t_d15 c[116,95,100,49,53]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,97],i1),c[91,124,93]/2(c[47]/2(a[112,98],i2),nil))),nil))",
    "t_d16 c[116,95,100,49,54]/1(c[91,124,93]/2(c[45]/2(a[109,97],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil)),c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,97],i1),nil)),nil)))",
    "t_d20 c[116,95,100,50,48]/1(nil)",
    "t_d17 c[116,95,100,49,55]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil))",
    "t_d21 c[116,95,100,50,49]/1(i1)"
]

# F5: a weak import overruled by a clause of a loaded file — swipl drops the import and makes a local definition; the kernel does the
# same (PR1b: pl-proc.jl overruleImportedProcedure calls abolishProcedure!). Not a row of the compared table.
const _MX_F5_PROGRAM = raw"""
:- assertz(mwfs:mw_wq(1)).
:- '$import'(mwfs:mw_wq/1, weak).
mw_wq(9).
t_f5(R) :- findall(X, mw_wq(X), R).
"""
# swipl 10.1.19's line (live below); the kernel's answer is the same line since PR1b (no longer a pinned difference)
const _MX_F5_SWIPL = "t_f5 c[116,95,102,53]/1(c[91,124,93]/2(i9,nil))"

# F6 (PIN1 step C, b94d7de5): abolishing an IMPORTED predicate makes a fresh definition with share count 1 (upstream `newDefinition`;
# it was 0). The count is seen through `fixExport`: mgd imports the abolished (undefined) mgm:gp/1, so the fresh definition has two
# sharers, then mgd imports mgq's defined gp/1 over it; `import` unshares the undefined one and, with a sharer left (count > 0),
# `fixExport` re-points EVERY procedure of it, mgm's own included, to mgq's definition, so mgm:gp(X) answers [1]. With the count at 0 the
# unshare ended below 1, no fixup ran, and mgm:gp/1 stayed undefined.
const _MX_F6_PROGRAM = raw"""
:- assertz(mgq:gp(1)).
:- mgq:export(gp/1).
t_f6(R) :-
    mgm:import(mgq:gp/1),
    abolish(mgm:gp/1),
    mgm:export(gp/1),
    mgd:import(mgm:gp/1),
    mgd:import(mgq:gp/1),
    catch(findall(X, mgm:gp(X), R), error(E, _), R = raised(E)).
:- assertz(mgq:gz).
:- mgq:export(gz/0).
t_f7(R) :-                                  % the same with an arity-0 predicate (no argument info in its definition)
    mgm:import(mgq:gz/0),
    abolish(mgm:gz/0),
    mgm:export(gz/0),
    mgd:import(mgm:gz/0),
    mgd:import(mgq:gz/0),
    catch(findall(x, mgm:gz, R), error(E, _), R = raised(E)).
"""
# swipl 10.1.20 (18168e62, with b94d7de5)'s line, live below
const _MX_F6_SWIPL = [
    "t_f6 c[116,95,102,54]/1(c[91,124,93]/2(i1,nil))",
    "t_f7 c[116,95,102,55]/1(c[91,124,93]/2(a[120],nil))"
]

"The program and cases as one file; the case predicates' names."
function _mx_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _MX_CASES]
    text =
        _MX_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(F, _), R = raised(F)).\n" for
            (id, g) in _MX_CASES
        ])
    f = joinpath(mktempdir(), "mx_rows.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _mx_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MX}()
    ld = LK.PL_local_data{_MX}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mx_enc(ball::_MX)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mxs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MX, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mx_enc(mk_expr(_MX, _MX[_mxs(name), lk_answers(ld, (a:a)...)...]))
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end

@testset "export and import as swipl's (MOD5a rows)" begin
    f, names = _mx_file()
    kl, _, _ = _mx_kernel(f, names)
    @test length(kl) == length(_MX_PINNED)
    for (k, p) in zip(kl, _MX_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "how many procedures share a definition (pl-incl.h definition->shared)" begin
    # swipl cannot be asked; the counts follow pl-proc.c from the rows above: lookupProcedure starts a definition at 1,
    # `import` adds one per importing procedure (shareDefinition), and `fixExport`/`autoImport` move a sharer from one
    # definition to another (share the new, unshare the old). UNVERIFIED on the kernel: gate decides.
    f, names = _mx_file()
    _, gd, _ = _mx_kernel(f, names)
    shared(m, n, a) = LK.isCurrentProcedure(
        sym_key(_mxs(n)), a, LK.isCurrentModule(gd.modules, _mxs(m))
    ).definition.shared
    @test shared("mwq", "qq", 1) == 3      # mwq's own, mfx's import (i15), and mfz's after fixExport re-pointed it
    @test shared("mwq", "rr", 1) == 2      # mwq's own and mgx's import (i16); the second import was already done
    @test shared("user", "zz", 1) == 3     # user's own, mauto's autoImport link, mhx's import (i17)
    @test shared("ma", "pa", 1) == 4       # ma own, the imports of i01 (mi), i06 (user) and w09 (mw3, weak)
end

@testset "which definition a procedure points to; the weak flag of an import (MOD5a-F1, MOD5a-S5)" begin
    # swipl cannot be asked which definition a procedure holds. UNVERIFIED on the kernel: gate decides.
    f, names = _mx_file()
    _, gd, _ = _mx_kernel(f, names)
    proc(m, n, a) = LK.isCurrentProcedure(
        sym_key(_mxs(n)), a, LK.isCurrentModule(gd.modules, _mxs(m))
    )
    # i15: mfz imported mfx's undefined qq/1, then mfx imported mwq's: fixExportModule re-points mfz's procedure to mwq's
    # definition (the call still works on the mutant, through the undefined definition's module, so only the pointer shows it)
    d = proc("mwq", "qq", 1).definition
    @test proc("mfx", "qq", 1).definition === d
    @test proc("mfz", "qq", 1).definition === d
    # w09: '$import'(ma:pa/1, weak) makes a weak link in mw3; i01 made a strong one in mi (pl-modul.c import: nproc->flags = pflags)
    @test (proc("mw3", "pa", 1).flags & LK.PROC_WEAK) != 0
    @test (proc("mi", "pa", 1).flags & LK.PROC_WEAK) == 0
    @test proc("mw3", "pa", 1).definition === proc("ma", "pa", 1).definition
end

@testset "the pins hold both kinds of answer (non-vacuity)" begin
    # the comparison can pass and can fail: answers, errors, empty answers and a failure are all pinned
    @test length(_MX_PINNED) == length(_MX_CASES) + 1
    @test _MX_PINNED[1] == "ok"
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _MX_PINNED) >= 18      # raised(…)
    @test count(l -> occursin("c[45]/2(", l), _MX_PINNED) >= 10                         # Module-List pairs and X-Y answers
    @test count(l -> occursin("c[47]/2(", l), _MX_PINNED) >= 10                         # Name/Arity
    @test count(l -> endswith(l, "]/1(nil)"), _MX_PINNED) >= 4                          # an empty list answer (e07, u05, d06, d07)
    @test count(l -> !occursin(" ", l), _MX_PINNED) == 1                                # only "ok" has no answer; no row fails
end

@testset "F5: a weak import overruled by a definition" begin
    # swipl's answer is the line in _MX_F5_SWIPL; the kernel abolishes the link (overruleImportedProcedure -> abolishProcedure!)
    f = joinpath(mktempdir(), "mx_f5.pl")
    write(f, _MX_F5_PROGRAM)
    @test startswith(_MX_F5_SWIPL, "t_f5 ")
    # UNVERIFIED on the kernel: gate decides
    res = _mx_kernel(f, ["t_f5"])
    @test res[1] == ["ok", _MX_F5_SWIPL]
end

@testset "F6: abolishing an imported predicate: share count 1 (b94d7de5)" begin
    f = joinpath(mktempdir(), "mx_f6.pl")
    write(f, _MX_F6_PROGRAM)
    @test all(startswith.(_MX_F6_SWIPL, ["t_f6 ", "t_f7 "]))
    # UNVERIFIED on the kernel: gate decides
    res, gd, _ = _mx_kernel(f, ["t_f6", "t_f7"])
    @test res == ["ok"; _MX_F6_SWIPL]
    # white box (swipl cannot be asked the count): after the row mgm's procedure was re-pointed to mgq's definition by fixExport, which
    # ran only because the abolished link's definition still had a sharer; the fresh definition a bare abolish makes starts at 1
    shared(m, n, a) = LK.isCurrentProcedure(
        sym_key(_mxs(n)), a, LK.isCurrentModule(gd.modules, _mxs(m))
    ).definition.shared
    proc(m, n, a) = LK.isCurrentProcedure(
        sym_key(_mxs(n)), a, LK.isCurrentModule(gd.modules, _mxs(m))
    )
    @test proc("mgm", "gp", 1).definition === proc("mgq", "gp", 1).definition
    @test proc("mgd", "gp", 1).definition === proc("mgq", "gp", 1).definition
    @test shared("mgq", "gp", 1) == 3                    # mgq's own, mgd's import, mgm's after fixExport
    @test shared("mgm", "gp", 1) == 3
    @test proc("mgm", "gz", 0).definition === proc("mgq", "gz", 0).definition   # the arity-0 row: the same
    @test shared("mgq", "gz", 0) == 3
end

# F2 (EQ2, audit D-0472 item 4; MOD5a-F2): `fixExport` skips a DESTROYED module. Upstream's destroyModule takes the module out of
# GD->tables.modules (pl-modul.c:438, deleteHTableWP) and fixExport walks only that table (pl-modul.c:1655-1658), so a destroyed module's
# procedures are never re-pointed. The kernel keeps the record in its module vector (a declared divergence at unallocModule) and models
# the skip with `M_DESTROYED` at fixExport. The Prolog-level answer is the same either way (the undefined definition belongs to `user`,
# whose trap resolves the call), which swipl 10.1.20 confirms: the line below is swipl's; the pointer is seen white-box.
# mftm and mftl both import user's undefined fz/0 (so they share its definition); mftm is destroyed; then user imports mfo's fz/0, whose
# fixExport re-points every sharer in the table: mftl's procedure (control: the live module) and, only under the mutant, mftm's.
const _MX_F2_PROGRAM = raw"""
:- set_module(mftm:class(temporary)).
:- set_module(mftm:base(system)).
:- set_module(mftl:class(temporary)).
:- set_module(mftl:base(system)).
:- assertz(mfo:fz).
:- mftm:import(user:fz/0).
:- mftl:import(user:fz/0).
t_f2(R) :-
    '$destroy_module'(mftm),
    user:import(mfo:fz/0),
    ( catch(mftl:fz, error(E, _), R0 = raised(E)) -> true ; R0 = failed ),
    ( var(R0) -> R = ran ; R = R0 ).
"""
# swipl 10.1.20 (18168e62)'s line, live below
const _MX_F2_SWIPL = ["t_f2 c[116,95,102,50]/1(a[114,97,110])"]

@testset "F2: a destroyed module's procedures are not re-pointed by fixExport (MOD5a-F2)" begin
    f = joinpath(mktempdir(), "mx_f2.pl")
    write(f, _MX_F2_PROGRAM)
    @test all(startswith.(_MX_F2_SWIPL, ["t_f2 "]))
    # UNVERIFIED on the kernel: gate decides
    res, gd, _ = _mx_kernel(f, ["t_f2"])
    @test res == ["ok"; _MX_F2_SWIPL]
    # white box: the destroyed module (out of the name index, M_DESTROYED, its record kept) still holds its fz/0 on the OLD, undefined definition;
    # the live module's was re-pointed to mfo's (the control: the fixup ran, and it ran only because the old definition had sharers left)
    fz = sym_key(_mxs("fz"))
    function record(name)
        i = findfirst(m -> sym_key(m.atom) == sym_key(_mxs(name)), gd.modules.modules)
        return i === nothing ? nothing : gd.modules.modules[i]
    end
    mftm, mftl, mfo = record("mftm"), record("mftl"), record("mfo")
    @test mftm !== nothing && mftl !== nothing && mfo !== nothing
    @test (mftm.flags & LK.M_DESTROYED) != 0
    @test get(gd.modules.names, mftm.name, 0) == 0
    @test (mftl.flags & LK.M_DESTROYED) == 0
    pm = LK.isCurrentProcedure(fz, 0, mftm)
    pl = LK.isCurrentProcedure(fz, 0, mftl)
    po = LK.isCurrentProcedure(fz, 0, mfo)
    pu = LK.isCurrentProcedure(fz, 0, LK.MODULE_user(gd))
    @test pm !== nothing && pl !== nothing && po !== nothing && pu !== nothing
    @test pu.definition === po.definition               # user's import went through
    @test pl.definition === po.definition               # the live sharer was re-pointed by fixExport
    @test pm.definition !== po.definition               # the destroyed module's was not (the mutant re-points it)
    @test !LK.isDefinedProcedure(gd, pm)
end

# D9 (EQ2, MOD5a-D9): a loop of default modules. Upstream's setSuperModule replaces a SINGLE super with no cycle check (pl-modul.c:645-652;
# swipl 10.1.20 accepts `set_module(a:base(b)), set_module(b:base(a))`), and find_modules_with_defs then stops at depth 100 with
# `sysError("OOPS loop in default modules???")` (pl-modul.c:1180), which ends the process: there is no swipl answer to compare, so the
# row is KERNEL-ONLY. The kernel raises an ErrorException at the same depth (pl-modul.jl find_modules_with_defs); with `l + 1` the
# recursion never ends and Julia throws a StackOverflowError instead.
@testset "a loop of default modules is a kernel error at depth 100 (MOD5a-D9, kernel-only: upstream sysErrors)" begin
    f = joinpath(mktempdir(), "mx_d9.pl")
    write(f, ":- set_module(mxl1:base(mxl2)).\n:- set_module(mxl2:base(mxl1)).\n")
    res, gd, ld = _mx_kernel(f, String[])
    @test res == ["ok"]
    m = LK.isCurrentModule(gd.modules, _mxs("mxl1"))
    @test m !== nothing
    @test LK.reachableModule(gd.modules, gd.modules[m.supers[1]], m)       # the loop is there: mxl2's super leads back to mxl1
    fid = LK.PL_open_foreign_frame(ld)
    targets = Tuple{UInt64, Int, LK.term_t}[]
    push!(targets, (sym_key(_mxs("nowhere")), 0, LK.PL_new_term_ref(ld)))
    tmp = LK.PL_new_term_refs(ld, 3)
    mlist = LK.PL_new_term_ref(ld)
    err = try
        LK.find_modules_with_defs(gd, ld, m, targets, tmp, mlist, 100)
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test err isa ErrorException && occursin("OOPS loop in default modules", err.msg)
    # the same walk over a chain that ends (no loop): no error, so the guard cannot fire at depth for a finite tree
    @test LK.find_modules_with_defs(
        gd, ld, LK.MODULE_user(gd), targets, tmp, mlist, 100
    ) === true
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_MX_PINNED) == length(_MX_CASES) + 1
    if swipl === nothing
        @info "MOD5a LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mx_file()
        @test _mx_swipl_lines(f, names) == _MX_PINNED
        f5 = joinpath(mktempdir(), "mx_f5.pl")
        write(f5, _MX_F5_PROGRAM)
        @test _mx_swipl_lines(f5, ["t_f5"]) == ["ok", _MX_F5_SWIPL]
        f6 = joinpath(mktempdir(), "mx_f6.pl")
        write(f6, _MX_F6_PROGRAM)
        @test _mx_swipl_lines(f6, ["t_f6", "t_f7"]) == ["ok"; _MX_F6_SWIPL]
        f2 = joinpath(mktempdir(), "mx_f2.pl")
        write(f2, _MX_F2_PROGRAM)
        @test _mx_swipl_lines(f2, ["t_f2"]) == ["ok"; _MX_F2_SWIPL]
    end
end
