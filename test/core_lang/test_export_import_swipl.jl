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
:- ma:export(pdir/0).
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
    ("d17", raw"'$def_modules'([pu/1, a/1, b/1, c/1, d/1, e/1, f/1, g/1, h/1, i/1], R)")
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
    "t_d17 c[116,95,100,49,55]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],c[91,124,93]/2(c[47]/2(a[112,117],i1),nil)),nil))"
]

# F5: a weak import overruled by a clause of a loaded file — swipl drops the import and makes a local definition; the kernel refuses
# (abolishProcedure is not available: pl-proc.jl overruleImportedProcedure). Not a row of the compared table.
const _MX_F5_PROGRAM = raw"""
:- assertz(mwfs:wq(1)).
:- mwf:'$import'(mwfs:wq/1, weak).
mwf:wq(9).
t_f5(R) :- findall(X, mwf:wq(X), R).
"""
# DIVERGES (F5): abolishProcedure is not available — swipl 10.1.19's line is below, the kernel raises NotPortedError
const _MX_F5_SWIPL = "t_f5 c[116,95,102,53]/1(c[91,124,93]/2(i9,nil))"

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
    st, ball, _ = LK.load_file!(gd, ld, path)
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

@testset "F5: a weak import overruled by a definition (pinned difference)" begin
    # swipl's answer is the line in _MX_F5_SWIPL; the kernel refuses: pl-proc.jl overruleImportedProcedure keeps its NotPortedError
    f = joinpath(mktempdir(), "mx_f5.pl")
    write(f, _MX_F5_PROGRAM)
    @test startswith(_MX_F5_SWIPL, "t_f5 ")
    # UNVERIFIED on the kernel: gate decides (the refusal reaches the caller as the exception, or the loader reports a status that is not ok)
    res = try
        _mx_kernel(f, ["t_f5"])
    catch e
        e
    end
    @test res isa LK.NotPortedError || (res isa Tuple && res[1][1] != "ok")
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "MOD5a LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mx_file()
        @test _mx_swipl_lines(f, names) == _MX_PINNED
        f5 = joinpath(mktempdir(), "mx_f5.pl")
        write(f5, _MX_F5_PROGRAM)
        @test _mx_swipl_lines(f5, ["t_f5"]) == ["ok", _MX_F5_SWIPL]
    end
end
