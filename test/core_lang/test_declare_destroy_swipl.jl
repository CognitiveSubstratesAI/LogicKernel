# ORIGINAL: MOD5b's gate (lk-channel evidence/r2/design/modules.md §7) — `'$declare_module'/6` (declareModule), `'$destroy_module'/1`
# (destroyModule, acquireModule/releaseModule) and the temporary-module class, against swipl 10.1.19; the rows are tests/core_lang style.
# test/core_lang/test_declare_destroy_swipl.jl — declaring and destroying modules (pl-modul.c, MOD5b), through a PROGRAM (the pattern of
# test/core_lang/test_export_import_swipl.jl): the first declaration (class, file, line, the source module), re-declaration (same file,
# another file with and without `Redefine`, the class set before the refusal, the public table cleared, the super module replaced),
# the six classes, the argument errors, `'$destroy_module'/1` (a temporary module; every other class refused; a name of no module
# succeeds), what is left after a destroy (the name is free for a new module, the source and typein modules go back to `user`)
# and the compiler's refusal of a temporary module named in a clause body (`getTargetModule!`).
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in one database, each wrapped in
#     `catch(Goal, error(F, _), R = raised(F))` and followed by `mb_done` (the source and typein modules back to `user`).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_export_import_swipl.jl's driver; lk-channel
#     evidence/MOD5b/mb_rows.out in the MOD5b branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * Q7 (modules.md §8): re-declaring a module whose static predicates have clauses needs `abolishProcedure`, which the kernel does
#     not have: swipl's answers are pinned, the kernel refuses by name (`NotPortedError`), in its own testset below.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — export and import (src/pl-modul.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mbs(x) = lk_sym(_MB, Symbol(x))

_mb_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mb_enc(t::_MB, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mb_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mb_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mb_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mb_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_at_body_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MB_DRIVER = raw"""
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
function _mb_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# the program: mdy: a DYNAMIC dp/1 (left alone by a re-declaration); user: sup_p/1 (dynamic) and sup_s/1 (static), seen through a super module `user`, not `system`;
# mb_done restores the source and typein modules after a row.
const _MB_PROGRAM = raw"""
:- assertz(mdy:dp(1)).
:- assertz(user:sup_p(7)).
sup_s(8).
mb_done :- '$set_source_module'(user), '$set_typein_module'(user).
"""

# UNVERIFIED on the kernel: gate decides — nothing here was run on the kernel. The rows that lean on more than MOD5b's own code:
# b04 (`catch/3` inside a row that declares), c01-c02 (`class` of a module made by `'$declare_module'`), d03 (`set_module/1`
# class(temporary)), b02, b05, b06, e01 and e02 (a call into a module whose super is `system`, or into a destroyed one: the `unknown`
# flag's error), f01-f05 (a temporary module in a clause body: `getTargetModule!`).
# (id, goal), run IN ORDER
const _MB_CASES = [
    # a01-a05: the first declaration (class, file, line, the source module), the same module again from the same file, from another
    # file without and with Redefine (a bool: true, and 1, which swipl's PL_get_stdbool_ex accepts)
    (
        "a01",
        raw"'$declare_module'(mna, user, user, '/mb/f1.pl', 3, false), '$current_source_module'(S), '$module_property'(mna, class(C)), '$module_property'(mna, file(F)), '$module_property'(mna, line_count(L)), R = [S, C, F, L]"
    ),
    (
        "a02",
        raw"'$declare_module'(mna, user, user, '/mb/f1.pl', 9, false), '$module_property'(mna, line_count(L)), '$module_property'(mna, file(F)), R = L-F"
    ),
    ("a03", raw"'$declare_module'(mna, user, user, '/mb/f2.pl', 1, false), R = ok"),
    (
        "a04",
        raw"'$declare_module'(mna, library, user, '/mb/f2.pl', 2, true), '$module_property'(mna, class(C)), '$module_property'(mna, file(F)), '$module_property'(mna, line_count(L)), R = [C, F, L]"
    ),
    (
        "a05",
        raw"'$declare_module'(mna, user, user, '/mb/f3.pl', 2, 1), '$module_property'(mna, file(F)), R = F"
    ),
    # a06: the class is set BEFORE the refusal (pl-modul.c:1297-1299 against 1301)
    (
        "a06",
        raw"'$declare_module'(mnb, user, user, '/mb/f1.pl', 1, false), catch('$declare_module'(mnb, system, user, '/mb/f2.pl', 1, false), error(E, _), true), '$module_property'(mnb, class(C)), R = E-C"
    ),
    # a07: the classes (swipl does not check the atom)
    (
        "a07",
        raw"findall(Cl-C, (member(Cl, [user, system, library, test, development, temporary, weird]), atom_concat(mbc_, Cl, M), '$declare_module'(M, Cl, user, '/mb/cls.pl', 1, false), '$module_property'(M, class(C))), R)"
    ),
    # a08-a18: the arguments, in order (module, class, super, file, line, redefine)
    ("a08", raw"'$declare_module'(_, user, user, '/mb/f.pl', 1, false), R = ok"),
    ("a09", raw"'$declare_module'(1, user, user, '/mb/f.pl', 1, false), R = ok"),
    ("a10", raw"'$declare_module'(f(x), user, user, '/mb/f.pl', 1, false), R = ok"),
    ("a11", raw"'$declare_module'(mbe1, _, user, '/mb/f.pl', 1, false), R = ok"),
    ("a12", raw"'$declare_module'(mbe1, user, _, '/mb/f.pl', 1, false), R = ok"),
    ("a13", raw"'$declare_module'(mbe1, user, user, _, 1, false), R = ok"),
    ("a14", raw"'$declare_module'(mbe1, user, user, '/mb/f.pl', a, false), R = ok"),
    ("a15", raw"'$declare_module'(mbe1, user, user, '/mb/f.pl', _, false), R = ok"),
    ("a16", raw"'$declare_module'(mbe1, user, user, '/mb/f.pl', 1, maybe), R = ok"),
    ("a17", raw"'$declare_module'(mbe1, user, user, '/mb/f.pl', 1, _), R = ok"),
    ("a18", raw"'$declare_module'(mbe1, user, user, '/mb/f.pl', 1.5, false), R = ok"),
    # a19-a20: a re-declaration clears the public table; an undefined export has no clauses to abolish
    (
        "a19",
        raw"'$declare_module'(mnc, user, user, '/mb/g.pl', 1, false), export(mnc:pe/1), '$module_property'(mnc, exports(L1)), '$declare_module'(mnc, user, user, '/mb/g.pl', 2, false), '$module_property'(mnc, exports(L2)), R = L1-L2"
    ),
    (
        "a20",
        raw"export(mpr:ex/0), '$declare_module'(mpr, user, user, '/mb/j.pl', 1, false), '$module_property'(mpr, exports(L)), R = L"
    ),
    # a21: a dynamic predicate is left alone
    (
        "a21",
        raw"'$declare_module'(mdy, user, user, '/mb/i.pl', 1, false), mdy:dp(X), R = X"
    ),
    # b01-b06: the super module: the default (user) sees user's predicates; `system` does not (existence_error); the module itself is
    # a cycle; a super that does not exist is made; a later declaration replaces it. b05: the link a call made to a DYNAMIC predicate
    # of the old super SURVIVES the re-declaration (declareModule's loop skips a definition with P_DYNAMIC, and the definition tested is
    # the imported one); b06: the link to a STATIC predicate is removed (abolishProcedure's imported branch), the predicate is gone.
    (
        "b01",
        raw"'$declare_module'(mns1, user, user, '/mb/h.pl', 1, false), mns1:sup_p(X), R = X"
    ),
    (
        "b02",
        raw"'$declare_module'(mns2, user, system, '/mb/h.pl', 1, false), catch(mns2:sup_p(_), error(E, _), true), R = E"
    ),
    ("b03", raw"'$declare_module'(mns3, user, mns3, '/mb/h.pl', 1, false), R = ok"),
    (
        "b04",
        raw"'$declare_module'(mns4, user, mnsup4, '/mb/h.pl', 1, false), '$module_property'(mnsup4, class(C)), mnsup4:assertz(zz4(1)), mns4:zz4(X), R = C-X"
    ),
    (
        "b05",
        raw"'$declare_module'(mns4, user, system, '/mb/h.pl', 1, false), catch(mns4:zz4(_), error(E, _), true), R = E"
    ),
    (
        "b06",
        raw"'$declare_module'(mns5, user, user, '/mb/h.pl', 1, false), mns5:sup_s(X0), '$declare_module'(mns5, user, system, '/mb/h.pl', 1, false), catch(mns5:sup_s(_), error(E, _), true), R = X0-E"
    ),
    # c01-c03: the class of a declared module that is not destroyable, and a class changed by a later declaration
    (
        "c01",
        raw"'$declare_module'(mbsys, system, user, '/mb/t.pl', 1, false), '$module_property'(mbsys, class(C)), R = C"
    ),
    (
        "c02",
        raw"'$declare_module'(mtd10, temporary, user, '/mb/t.pl', 1, false), '$declare_module'(mtd10, user, user, '/mb/t.pl', 1, false), '$module_property'(mtd10, class(C)), R = C"
    ),
    # d01-d12: '$destroy_module'/1
    (
        "d01",
        raw"'$declare_module'(mtd1, temporary, user, '/mb/t.pl', 1, false), '$destroy_module'(mtd1), ( '$module_property'(mtd1, class(C)) -> R = still(C) ; R = gone )"
    ),
    (
        "d02",
        raw"'$declare_module'(mtd2, temporary, user, '/mb/t.pl', 1, false), '$current_source_module'(S1), '$destroy_module'(mtd2), '$current_source_module'(S2), R = S1-S2"
    ),
    (
        "d03",
        raw"set_module(mtd3:class(temporary)), '$set_typein_module'(mtd3), '$destroy_module'(mtd3), '$current_typein_module'(T), R = T"
    ),
    ("d04", raw"'$destroy_module'(mtd4nx), '$destroy_module'(mtd4nx), R = ok"),
    ("d05", raw"'$destroy_module'(mna), R = ok"),
    ("d06", raw"'$destroy_module'(user), R = ok"),
    ("d07", raw"'$destroy_module'(system), R = ok"),
    ("d08", raw"'$destroy_module'(_), R = ok"),
    ("d09", raw"'$destroy_module'(1), R = ok"),
    ("d10", raw"'$destroy_module'(mbsys), R = ok"),
    ("d11", raw"'$destroy_module'(mtd10), R = ok"),
    (
        "d12",
        raw"'$declare_module'(mtd5, temporary, user, '/mb/t.pl', 1, false), '$destroy_module'(mtd5), '$destroy_module'(mtd5), R = ok"
    ),
    # e01-e04: the procedures of a destroyed module; the name is free for a new, user-class module in another file
    (
        "e01",
        raw"'$declare_module'(mtd6, temporary, user, '/mb/t.pl', 1, false), assertz(mtd6:tp(1)), mtd6:tp(X0), '$destroy_module'(mtd6), catch(mtd6:tp(_), error(E, _), true), R = X0-E"
    ),
    (
        "e02",
        raw"'$declare_module'(mtd7, temporary, user, '/mb/t.pl', 1, false), assertz(mtd7:tq(1)), '$destroy_module'(mtd7), '$declare_module'(mtd7, user, user, '/mb/t2.pl', 1, false), '$module_property'(mtd7, class(C)), '$module_property'(mtd7, file(F)), catch(mtd7:tq(_), error(E, _), true), R = C-F-E"
    ),
    (
        "e03",
        raw"'$declare_module'(mtd11, temporary, user, '/mb/t.pl', 1, false), export(mtd11:te/1), '$destroy_module'(mtd11), '$declare_module'(mtd11, user, user, '/mb/t.pl', 1, false), '$module_property'(mtd11, exports(L)), R = L"
    ),
    (
        "e04",
        raw"'$declare_module'(mtd12, temporary, user, '/mb/t.pl', 1, false), '$declare_module'(mtd12b, temporary, mtd12, '/mb/t.pl', 1, false), '$destroy_module'(mtd12), '$module_property'(mtd12b, class(C)), R = C"
    ),
    # f01-f05: a temporary module named in a clause body is refused (pl-comp.c getTargetModule); a goal run by call/1 is not a clause;
    # once the module is destroyed its name is a plain user module again
    (
        "f01",
        raw"'$declare_module'(mtd8, temporary, user, '/mb/t.pl', 1, false), catch(assertz((mbtb :- mtd8:foo)), error(E, _), true), R = E"
    ),
    ("f02", raw"call(mtd8:true), R = ok"),
    ("f03", raw"assertz((mbtb3 :- mna:foo)), R = ok"),
    ("f04", raw"'$destroy_module'(mtd8), assertz((mbtb2 :- mtd8:foo)), R = ok"),
    (
        "f05",
        raw"'$declare_module'(mtd8, temporary, user, '/mb/t.pl', 1, false), '$module_property'(mtd8, class(C)), R = C"
    )
]

"The program and cases as one file; the case predicates' names."
function _mb_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _MB_CASES]
    text =
        _MB_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(F, _), R = raised(F)), mb_done.\n" for
            (id, g) in _MB_CASES
        ])
    f = joinpath(mktempdir(), "mb_rows.pl")
    write(f, text)
    return f, names
end

# the swipl answers: filled by evidence/MOD5b/gen_rows.py --fill
const _MB_PINNED = [
    "ok",
    "t_a01 c[116,95,97,48,49]/1(c[91,124,93]/2(a[109,110,97],c[91,124,93]/2(a[117,115,101,114],c[91,124,93]/2(a[47,109,98,47,102,49,46,112,108],c[91,124,93]/2(i3,nil)))))",
    "t_a02 c[116,95,97,48,50]/1(c[45]/2(i9,a[47,109,98,47,102,49,46,112,108]))",
    "t_a03 c[116,95,97,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,100,101,102,105,110,101],a[109,111,100,117,108,101],a[109,110,97])))",
    "t_a04 c[116,95,97,48,52]/1(c[91,124,93]/2(a[108,105,98,114,97,114,121],c[91,124,93]/2(a[47,109,98,47,102,50,46,112,108],c[91,124,93]/2(i2,nil))))",
    "t_a05 c[116,95,97,48,53]/1(a[47,109,98,47,102,51,46,112,108])",
    "t_a06 c[116,95,97,48,54]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,100,101,102,105,110,101],a[109,111,100,117,108,101],a[109,110,98]),a[115,121,115,116,101,109]))",
    "t_a07 c[116,95,97,48,55]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[117,115,101,114]),c[91,124,93]/2(c[45]/2(a[115,121,115,116,101,109],a[115,121,115,116,101,109]),c[91,124,93]/2(c[45]/2(a[108,105,98,114,97,114,121],a[108,105,98,114,97,114,121]),c[91,124,93]/2(c[45]/2(a[116,101,115,116],a[116,101,115,116]),c[91,124,93]/2(c[45]/2(a[100,101,118,101,108,111,112,109,101,110,116],a[100,101,118,101,108,111,112,109,101,110,116]),c[91,124,93]/2(c[45]/2(a[116,101,109,112,111,114,97,114,121],a[116,101,109,112,111,114,97,114,121]),c[91,124,93]/2(c[45]/2(a[119,101,105,114,100],a[119,101,105,114,100]),nil))))))))",
    "t_a08 c[116,95,97,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a09 c[116,95,97,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_a10 c[116,95,97,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_a11 c[116,95,97,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a12 c[116,95,97,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a13 c[116,95,97,49,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a14 c[116,95,97,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_a15 c[116,95,97,49,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a16 c[116,95,97,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_a17 c[116,95,97,49,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a18 c[116,95,97,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_a19 c[116,95,97,49,57]/1(c[45]/2(c[91,124,93]/2(c[47]/2(a[112,101],i1),nil),nil))",
    "t_a20 c[116,95,97,50,48]/1(nil)",
    "t_a21 c[116,95,97,50,49]/1(i1)",
    "t_b01 c[116,95,98,48,49]/1(i7)",
    "t_b02 c[116,95,98,48,50]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,110,115,50],c[47]/2(a[115,117,112,95,112],i1))))",
    "t_b03 c[116,95,98,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[97,100,100,95,105,109,112,111,114,116],a[109,111,100,117,108,101],a[109,110,115,51])))",
    "t_b04 c[116,95,98,48,52]/1(c[45]/2(a[117,115,101,114],i1))",
    "t_b05 c[116,95,98,48,53]/1(V0)",
    "t_b06 c[116,95,98,48,54]/1(c[45]/2(i8,c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,110,115,53],c[47]/2(a[115,117,112,95,115],i1)))))",
    "t_c01 c[116,95,99,48,49]/1(a[115,121,115,116,101,109])",
    "t_c02 c[116,95,99,48,50]/1(a[117,115,101,114])",
    "t_d01 c[116,95,100,48,49]/1(a[103,111,110,101])",
    "t_d02 c[116,95,100,48,50]/1(c[45]/2(a[109,116,100,50],a[117,115,101,114]))",
    "t_d03 c[116,95,100,48,51]/1(a[117,115,101,114])",
    "t_d04 c[116,95,100,48,52]/1(a[111,107])",
    "t_d05 c[116,95,100,48,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,111,100,117,108,101],a[109,110,97])))",
    "t_d06 c[116,95,100,48,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,111,100,117,108,101],a[117,115,101,114])))",
    "t_d07 c[116,95,100,48,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,111,100,117,108,101],a[115,121,115,116,101,109])))",
    "t_d08 c[116,95,100,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d09 c[116,95,100,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_d10 c[116,95,100,49,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,111,100,117,108,101],a[109,98,115,121,115])))",
    "t_d11 c[116,95,100,49,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[100,101,115,116,114,111,121],a[109,111,100,117,108,101],a[109,116,100,49,48])))",
    "t_d12 c[116,95,100,49,50]/1(a[111,107])",
    "t_e01 c[116,95,101,48,49]/1(c[45]/2(i1,c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,116,100,54],c[47]/2(a[116,112],i1)))))",
    "t_e02 c[116,95,101,48,50]/1(c[45]/2(c[45]/2(a[117,115,101,114],a[47,109,98,47,116,50,46,112,108]),c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,116,100,55],c[47]/2(a[116,113],i1)))))",
    "t_e03 c[116,95,101,48,51]/1(nil)",
    "t_e04 c[116,95,101,48,52]/1(a[116,101,109,112,111,114,97,114,121])",
    "t_f01 c[116,95,102,48,49]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,102,101,114,101,110,99,101],a[109,111,100,117,108,101],a[109,116,100,56]))",
    "t_f02 c[116,95,102,48,50]/1(a[111,107])",
    "t_f03 c[116,95,102,48,51]/1(a[111,107])",
    "t_f04 c[116,95,102,48,52]/1(a[111,107])",
    "t_f05 c[116,95,102,48,53]/1(a[116,101,109,112,111,114,97,114,121])"
]

# Q7 (modules.md §8): a module whose STATIC predicate has clauses, declared. swipl abolishes the predicate and warns (stderr);
# the kernel has no abolishProcedure and refuses by name (NotPortedError).
const _MB_Q7_PROGRAM = raw"""
mq:qs(1).
mq:qs(2).
t_q7a(R) :- '$declare_module'(mq, user, user, '/mb/q.pl', 1, false), '$set_source_module'(user), R = ok.
t_q7b(R) :- catch(findall(X, mq:qs(X), R), error(F, _), R = raised(F)).
"""
# DIVERGES (Q7, F5): swipl 10.1.19's lines are below; the kernel raises NotPortedError at t_q7a
const _MB_Q7_SWIPL = [
    "t_q7a c[116,95,113,55,97]/1(a[111,107])",
    "t_q7b c[116,95,113,55,98]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,113],c[47]/2(a[113,115],i1)))))"
]

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _mb_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MB}()
    ld = LK.PL_local_data{_MB}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mb_enc(ball::_MB)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mbs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MB, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mb_enc(mk_expr(_MB, _MB[_mbs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "declaring and destroying modules as swipl's (MOD5b rows)" begin
    f, names = _mb_file()
    kl, _, _ = _mb_kernel(f, names)
    @test length(kl) == length(_MB_PINNED)
    for (k, p) in zip(kl, _MB_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the pins hold both kinds of answer (non-vacuity)" begin
    # the comparison can pass and can fail: answers, errors and a destroyed module's lookups are all pinned
    @test length(_MB_PINNED) == length(_MB_CASES) + 1
    @test _MB_PINNED[1] == "ok"
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _MB_PINNED) >= 20      # raised(…)
    @test count(l -> occursin("c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]", l), _MB_PINNED) >= 5   # permission_error
    @test count(l -> occursin("c[45]/2(", l), _MB_PINNED) >= 8                         # X-Y answers
    @test count(l -> !occursin(" ", l), _MB_PINNED) == 1                                # only "ok" has no answer; no row fails
end

@testset "a destroyed module keeps its record; its name is free (H3)" begin
    # kernel-side: swipl cannot be asked about a module's index. UNVERIFIED on the kernel: gate decides.
    f, names = _mb_file()
    _, gd, _ = _mb_kernel(f, names)
    ms = [m for m in gd.modules if m.name == sym_key(_mbs("mtd7"))]
    @test length(ms) == 2
    old, new = ms
    @test (old.flags & LK.M_DESTROYED) != 0
    @test (new.flags & LK.M_DESTROYED) == 0
    @test new.index > old.index
    @test LK.isCurrentModule(gd.modules, _mbs("mtd7")) === new
    @test old.references == 0
    @test old.file == 0                       # unlinkSourceFilesModule released the file
    tq = old.procedures[(sym_key(_mbs("tq")), 1)]
    @test tq.definition.module_ == old.index  # the old definitions still name the old record
    @test !haskey(new.procedures, (sym_key(_mbs("tq")), 1))
    mna = LK.isCurrentModule(gd.modules, _mbs("mna"))
    @test mna !== nothing && (mna.flags & LK.M_DESTROYED) == 0 && mna.file != 0
    # b06 (abolishProcedure's imported branch): user's sup_s/1 was linked into mns5 by a call, the re-declaration removed the link:
    # a fresh definition of mns5's own, user's shared once again (UNVERIFIED on the kernel: gate decides)
    us = LK.isCurrentModule(gd.modules, _mbs("user"))
    ss = us.procedures[(sym_key(_mbs("sup_s")), 1)]
    @test ss.definition.shared == 1
    m5 = LK.isCurrentModule(gd.modules, _mbs("mns5"))
    p5 = m5.procedures[(sym_key(_mbs("sup_s")), 1)]
    @test p5.definition.module_ == m5.index && p5.definition !== ss.definition
    @test p5.definition.shared == 0                         # upstream's memset leaves it 0
    mtd8 = LK.isCurrentModule(gd.modules, _mbs("mtd8"))     # f04 destroyed it, f05 declared it again as temporary
    @test mtd8 !== nothing && sym_key(mtd8.class) == sym_key(_mbs("temporary"))
end

@testset "Q7: declaring a module whose static predicate has clauses (pinned difference)" begin
    # swipl's answers are _MB_Q7_SWIPL; the kernel refuses (declareModule: _abolishProcedure_pristine raises NotPortedError)
    f = joinpath(mktempdir(), "mb_q7.pl")
    write(f, _MB_Q7_PROGRAM)
    @test length(_MB_Q7_SWIPL) == 2 && startswith(_MB_Q7_SWIPL[1], "t_q7a ")
    # UNVERIFIED on the kernel: gate decides (the refusal reaches the caller as the exception, or the loader reports a status that is not ok)
    res = try
        _mb_kernel(f, ["t_q7a", "t_q7b"])
    catch e
        e
    end
    @test res isa LK.NotPortedError || (res isa Tuple && res[1][1] != "ok")
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "MOD5b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mb_file()
        @test _mb_swipl_lines(f, names) == _MB_PINNED
        f7 = joinpath(mktempdir(), "mb_q7.pl")
        write(f7, _MB_Q7_PROGRAM)
        @test _mb_swipl_lines(f7, ["t_q7a", "t_q7b"]) == ["ok"; _MB_Q7_SWIPL]
    end
end
