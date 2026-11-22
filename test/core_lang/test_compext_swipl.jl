# ORIGINAL: a LIVE differential of COMP-EXT's predicates against swipl at the pin: `'$notrace'/1` (pl-pro.c:392-410), `'$predefine_foreign'/1`
# and `'$vmi_property'/2` (pl-comp.c:5277-5285, :8106-8148), `'$spy'/1` and `'$nospy'/1` (pl-trace.c:2342-2379); audit D-0784. Rows cx01-cx64:
#   * A PROGRAM of cases `t_<id>(R)` consulted by the kernel's loader and run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`, then `set_prolog_flag(debug, false)` (a row that switched the debug mode on leaves it off);
#     the driver is test_notrace_swipl.jl's (`enc`oded answers), whose state discipline the `'$notrace'/1` rows follow (save first, restore last).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20-1-g18168e62, run TWICE with the explicit pin binary, the two outputs compared:
#     evidence/COMP-EXT/gen_rows.py writes them into `_CX_PINNED`); with `swipl` on PATH the live answers are compared with the pins too.
#   * The message of `'$spy'/1` and `'$nospy'/1` (`informational`, `spy(Head)` / `nospy(Head)`) is observed on BOTH sides through the SAME program's
#     `message_hook/3` clause (it records `got(Term)`; the row reads them back), and on the kernel again by the test's own collector
#     (`lk_install_message_collector!`, the white-box testset below).
#   * Rows never call a spied predicate while its spy point is set (the kernel has no tracer, DBG1; swipl would enter it): `'$get_predicate_attribute'/3`
#     reads the attribute, `'$nospy'/1` clears it.
#   * KNOWN DIFFERENCE (named): `'$predefine_foreign'/1` takes `Name/Arity` only in these rows; the kernel's `get_procedure` also takes a head
#     (src/pl-comp.jl `pl_predefine_foreign1_va`, DIVERGES), swipl does not: the head form is not a row.
#   * NOT REPLAYED (COMPEXT-1): the LK-only row that `thread_create/3` is REFUSED by name (NotPortedError, step "TH1"): the integration tip has
#     the TH1 engines and no thread_create/3, so the refusal does not exist there (only the meta-spec was replayed, src/pl-ext.jl).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_cxs(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_cx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _cx_enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _cx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _cx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _cx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_cx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_bootpred3_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _CX_DRIVER = raw"""
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
function _cx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the message collector (informational messages only) and the predicates the rows spy on or declare foreign
const _CX_PROGRAM = raw"""
:- dynamic got/1, spd/1.
message_hook(Term, Kind, _Lines) :- Kind == informational, assertz(got(Term)).
spa(1).
spb(1).
spc(1).
spe(1).
"""
# one row: the case wrapped as described in the header (`@ID@`, `@GOAL@` replaced)
const _CX_WRAP = raw"t_@ID@(R) :- ( catch((@GOAL@), error(SsuE, _), R = raised(SsuE)) -> Ok = yes ; Ok = no ), set_prolog_flag(debug, false), Ok == yes." *
                 "\n"

# cx01-cx13: `'$notrace'/1` (the goal's answer, failure and ball pass through; the tracing bit and the skip level are what they were before, the
# debugging bit is restored too, cx07, and is off inside the goal, cx12: 13 = 15 less the debugging bit); cx14-cx21: `'$predefine_foreign'/1` (the foreign attribute, the four error forms, a qualified and a 0-arity
# predicate); cx22-cx50: `'$vmi_property'/2` (`break/1`, `argv/1` of eleven instructions, the error forms, upper-case and unknown names);
# cx51-cx64: `'$spy'/1` and `'$nospy'/1` (the attribute, the debug flag, the message on each side, the silent repeats, the errors).
const _CX_CASES = [
    (
        "cx01",
        raw"'$notrace'(true), R = ok"
    ),
    (
        "cx02",
        raw"( '$notrace'(fail) -> R = yes ; R = no )"
    ),
    (
        "cx03",
        raw"'$notrace'(X = f(Y)), R = X-Y"
    ),
    (
        "cx04",
        raw"catch('$notrace'(throw(my_ball)), B, true), R = B"
    ),
    (
        "cx05",
        raw"'$notrace'(throw(error(type_error(integer, a), _)))"
    ),
    (
        "cx06",
        raw"'$notrace'(F0, S0), '$restore_trace'(0, 0), '$notrace'('$restore_trace'(1, 3)), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"
    ),
    (
        "cx07",
        raw"'$notrace'(F0, S0), '$restore_trace'(0, 0), '$notrace'('$restore_trace'(3, 5)), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"
    ),
    (
        "cx08",
        raw"'$notrace'(F0, S0), '$restore_trace'(0, 2), '$notrace'('$restore_trace'(0, 9)), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"
    ),
    (
        "cx09",
        raw"'$notrace'(F0, S0), '$restore_trace'(0, 0), ( '$notrace'(('$restore_trace'(1, 3), fail)) -> X = yes ; X = no ), '$notrace'(F, S), '$restore_trace'(F0, S0), R = X-F-S"
    ),
    (
        "cx10",
        raw"'$notrace'(F0, S0), '$restore_trace'(0, 0), catch('$notrace'(('$restore_trace'(1, 3), throw(oops))), oops, true), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"
    ),
    (
        "cx11",
        raw"'$notrace'(F0, S0), '$restore_trace'(1, 5), '$notrace'(true), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"
    ),
    (
        "cx12",
        raw"'$notrace'(F0, S0), '$restore_trace'(15, 5), '$notrace'('$notrace'(F1, S1)), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F1-S1-F-S"
    ),
    (
        "cx13",
        raw"'$notrace'('$notrace'(X = 1)), R = X"
    ),
    (
        "cx14",
        raw"'$predefine_foreign'(pfa/2), '$get_predicate_attribute'(pfa(_, _), foreign, V), '$get_predicate_attribute'(pfa(_, _), defined, D), R = V-D"
    ),
    (
        "cx15",
        raw"'$predefine_foreign'(pfb/1), '$predefine_foreign'(pfb/1), '$get_predicate_attribute'(pfb(_), foreign, V), R = V"
    ),
    (
        "cx16",
        raw"'$predefine_foreign'(_)"
    ),
    (
        "cx17",
        raw"'$predefine_foreign'(1/2)"
    ),
    (
        "cx18",
        raw"'$predefine_foreign'(pfc/x)"
    ),
    (
        "cx19",
        raw"'$predefine_foreign'(pfc/(-1))"
    ),
    (
        "cx20",
        raw"'$predefine_foreign'(m1:pfd/1), '$get_predicate_attribute'(m1:pfd(_), foreign, V), R = V"
    ),
    (
        "cx21",
        raw"'$predefine_foreign'(pfe/0), '$get_predicate_attribute'(pfe, foreign, V), R = V"
    ),
    (
        "cx22",
        raw"'$vmi_property'(i_enter, break(B)), R = B"
    ),
    (
        "cx23",
        raw"'$vmi_property'(i_enter, argv(L)), R = L"
    ),
    (
        "cx24",
        raw"'$vmi_property'(i_call, argv(L)), R = L"
    ),
    (
        "cx25",
        raw"'$vmi_property'(i_call, break(B)), R = B"
    ),
    (
        "cx26",
        raw"'$vmi_property'(i_exit, break(B)), R = B"
    ),
    (
        "cx27",
        raw"'$vmi_property'(b_unify_var, argv(L)), R = L"
    ),
    (
        "cx28",
        raw"'$vmi_property'(b_unify_var, break(B)), R = B"
    ),
    (
        "cx29",
        raw"'$vmi_property'(h_atom, argv(L)), R = L"
    ),
    (
        "cx30",
        raw"'$vmi_property'(h_atom, break(B)), R = B"
    ),
    (
        "cx31",
        raw"'$vmi_property'(i_depart, argv(L)), R = L"
    ),
    (
        "cx32",
        raw"'$vmi_property'(h_var, argv(L)), R = L"
    ),
    (
        "cx33",
        raw"'$vmi_property'(i_fcalldetva, argv(L)), R = L"
    ),
    (
        "cx34",
        raw"'$vmi_property'(i_callatm, argv(L)), R = L"
    ),
    (
        "cx35",
        raw"'$vmi_property'(b_functor, argv(L)), R = L"
    ),
    (
        "cx36",
        raw"'$vmi_property'(h_string, argv(L)), R = L"
    ),
    (
        "cx37",
        raw"'$vmi_property'(h_float, argv(L)), R = L"
    ),
    (
        "cx38",
        raw"'$vmi_property'(i_callm, argv(L)), R = L"
    ),
    (
        "cx39",
        raw"'$vmi_property'(i_enter, break(true)), R = ok"
    ),
    (
        "cx40",
        raw"'$vmi_property'(i_enter, break(false))"
    ),
    (
        "cx41",
        raw"'$vmi_property'(i_enter, break(foo))"
    ),
    (
        "cx42",
        raw"'$vmi_property'(i_enter, nosuch(_))"
    ),
    (
        "cx43",
        raw"'$vmi_property'(i_enter, foo)"
    ),
    (
        "cx44",
        raw"'$vmi_property'(i_enter, _)"
    ),
    (
        "cx45",
        raw"'$vmi_property'(nosuch, break(_))"
    ),
    (
        "cx46",
        raw"'$vmi_property'(_, break(_))"
    ),
    (
        "cx47",
        raw"'$vmi_property'(1, break(_))"
    ),
    (
        "cx48",
        raw"'$vmi_property'('I_ENTER', break(_))"
    ),
    (
        "cx49",
        raw"'$vmi_property'(h_integer, argv(_))"
    ),
    (
        "cx50",
        raw"'$vmi_property'(i_usercall0, break(_))"
    ),
    (
        "cx51",
        raw"retractall(got(_)), '$get_predicate_attribute'(spa(_), spy, A0), '$spy'(spa(_)), '$get_predicate_attribute'(spa(_), spy, A1), current_prolog_flag(debug, D1), '$nospy'(spa(_)), '$get_predicate_attribute'(spa(_), spy, A2), current_prolog_flag(debug, D2), findall(M, got(M), Ms), R = A0-A1-D1-A2-D2-Ms"
    ),
    (
        "cx52",
        raw"retractall(got(_)), '$spy'(spb(_)), '$spy'(spb(_)), '$nospy'(spb(_)), '$nospy'(spb(_)), findall(M, got(M), Ms), R = Ms"
    ),
    (
        "cx53",
        raw"retractall(got(_)), '$nospy'(spc(_)), current_prolog_flag(debug, D), findall(M, got(M), Ms), R = D-Ms"
    ),
    (
        "cx54",
        raw"'$nospy'(nosuch)"
    ),
    (
        "cx55",
        raw"'$nospy'(nosuch(_))"
    ),
    (
        "cx56",
        raw"'$nospy'(m9:nosuch(_))"
    ),
    (
        "cx57",
        raw"( '$spy'(nosuch) -> R = yes ; R = no )"
    ),
    (
        "cx58",
        raw"'$spy'(nosuch(_))"
    ),
    (
        "cx59",
        raw"'$spy'(_)"
    ),
    (
        "cx60",
        raw"'$nospy'(_)"
    ),
    (
        "cx61",
        raw"( '$spy'(sp/1) -> R = yes ; R = no )"
    ),
    (
        "cx62",
        raw"'$nospy'(1)"
    ),
    (
        "cx63",
        raw"retractall(got(_)), '$spy'(user:spe(_)), '$nospy'(user:spe(_)), findall(M, got(M), Ms), R = Ms"
    ),
    (
        "cx64",
        raw"retractall(got(_)), '$spy'(spd(_)), '$get_predicate_attribute'(spd(_), spy, A), '$nospy'(spd(_)), findall(M, got(M), Ms), R = A-Ms"
    )
]

# swipl's answer lines, generated by evidence/COMP-EXT/gen_rows.py from the program and the cases above (two runs, compared)
const _CX_PINNED = [
    "ok",
    "t_cx01 c[116,95,99,120,48,49]/1(a[111,107])",
    "t_cx02 c[116,95,99,120,48,50]/1(a[110,111])",
    "t_cx03 c[116,95,99,120,48,51]/1(c[45]/2(c[102]/1(V0),V0))",
    "t_cx04 c[116,95,99,120,48,52]/1(a[109,121,95,98,97,108,108])",
    "t_cx05 c[116,95,99,120,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_cx06 c[116,95,99,120,48,54]/1(c[45]/2(i0,i0))",
    "t_cx07 c[116,95,99,120,48,55]/1(c[45]/2(i0,i0))",
    "t_cx08 c[116,95,99,120,48,56]/1(c[45]/2(i0,i2))",
    "t_cx09 c[116,95,99,120,48,57]/1(c[45]/2(c[45]/2(a[110,111],i0),i0))",
    "t_cx10 c[116,95,99,120,49,48]/1(c[45]/2(i0,i0))",
    "t_cx11 c[116,95,99,120,49,49]/1(c[45]/2(i1,i5))",
    "t_cx12 c[116,95,99,120,49,50]/1(c[45]/2(c[45]/2(c[45]/2(i13,i5),i15),i5))",
    "t_cx13 c[116,95,99,120,49,51]/1(i1)",
    "t_cx14 c[116,95,99,120,49,52]/1(c[45]/2(i1,i1))",
    "t_cx15 c[116,95,99,120,49,53]/1(i1)",
    "t_cx16 c[116,95,99,120,49,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx17 c[116,95,99,120,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_cx18 c[116,95,99,120,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[120])))",
    "t_cx19 c[116,95,99,120,49,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_cx20 c[116,95,99,120,50,48]/1(i1)",
    "t_cx21 c[116,95,99,120,50,49]/1(i1)",
    "t_cx22 c[116,95,99,120,50,50]/1(a[116,114,117,101])",
    "t_cx23 c[116,95,99,120,50,51]/1(nil)",
    "t_cx24 c[116,95,99,120,50,52]/1(c[91,124,93]/2(a[108,112,114,111,99],nil))",
    "t_cx25 c[116,95,99,120,50,53]/1(a[116,114,117,101])",
    "t_cx26 c[116,95,99,120,50,54]/1(a[116,114,117,101])",
    "t_cx27 c[116,95,99,120,50,55]/1(c[91,124,93]/2(a[118,97,114],nil))",
    "t_cx28 c[116,95,99,120,50,56]/1(a[116,114,117,101])",
    "t_cx29 c[116,95,99,120,50,57]/1(c[91,124,93]/2(a[100,97,116,97],nil))",
    "t_cx30 c[116,95,99,120,51,48]/1(a[102,97,108,115,101])",
    "t_cx31 c[116,95,99,120,51,49]/1(c[91,124,93]/2(a[108,112,114,111,99],nil))",
    "t_cx32 c[116,95,99,120,51,50]/1(c[91,124,93]/2(a[118,97,114],nil))",
    "t_cx33 c[116,95,99,120,51,51]/1(c[91,124,93]/2(a[102,111,114,101,105,103,110],nil))",
    "t_cx34 c[116,95,99,120,51,52]/1(c[91,124,93]/2(a[109,111,100,117,108,101],c[91,124,93]/2(a[109,111,100,117,108,101],c[91,124,93]/2(a[112,114,111,99],nil))))",
    "t_cx35 c[116,95,99,120,51,53]/1(c[91,124,93]/2(a[102,117,110,99],nil))",
    "t_cx36 c[116,95,99,120,51,54]/1(c[91,124,93]/2(a[115,116,114,105,110,103],nil))",
    "t_cx37 c[116,95,99,120,51,55]/1(c[91,124,93]/2(a[102,108,111,97,116],nil))",
    "t_cx38 c[116,95,99,120,51,56]/1(c[91,124,93]/2(a[109,111,100,117,108,101],c[91,124,93]/2(a[112,114,111,99],nil)))",
    "t_cx39 c[116,95,99,120,51,57]/1(a[111,107])",
    "t_cx40",
    "t_cx41 c[116,95,99,120,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_cx42 c[116,95,99,120,52,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[118,109,105,95,112,114,111,112,101,114,116,121],c[110,111,115,117,99,104]/1(V0))))",
    "t_cx43 c[116,95,99,120,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[118,109,105,95,112,114,111,112,101,114,116,121],a[102,111,111])))",
    "t_cx44 c[116,95,99,120,52,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx45 c[116,95,99,120,52,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,109,105],a[110,111,115,117,99,104])))",
    "t_cx46 c[116,95,99,120,52,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx47 c[116,95,99,120,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_cx48 c[116,95,99,120,52,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,109,105],a[73,95,69,78,84,69,82])))",
    "t_cx49 c[116,95,99,120,52,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,109,105],a[104,95,105,110,116,101,103,101,114])))",
    "t_cx50 c[116,95,99,120,53,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,109,105],a[105,95,117,115,101,114,99,97,108,108,48])))",
    "t_cx51 c[116,95,99,120,53,49]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(c[45]/2(i0,i1),a[116,114,117,101]),i0),a[116,114,117,101]),c[91,124,93]/2(c[115,112,121]/1(c[115,112,97]/1(V0)),c[91,124,93]/2(c[110,111,115,112,121]/1(c[115,112,97]/1(V1)),nil))))",
    "t_cx52 c[116,95,99,120,53,50]/1(c[91,124,93]/2(c[115,112,121]/1(c[115,112,98]/1(V0)),c[91,124,93]/2(c[110,111,115,112,121]/1(c[115,112,98]/1(V1)),nil)))",
    "t_cx53 c[116,95,99,120,53,51]/1(c[45]/2(a[102,97,108,115,101],nil))",
    "t_cx54 c[116,95,99,120,53,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],a[110,111,115,117,99,104])))",
    "t_cx55 c[116,95,99,120,53,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[110,111,115,117,99,104]/1(V0))))",
    "t_cx56 c[116,95,99,120,53,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,57],c[110,111,115,117,99,104]/1(V0)))))",
    "t_cx57 c[116,95,99,120,53,55]/1(a[110,111])",
    "t_cx58",
    "t_cx59 c[116,95,99,120,53,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx60 c[116,95,99,120,54,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx61 c[116,95,99,120,54,49]/1(a[110,111])",
    "t_cx62 c[116,95,99,120,54,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_cx63 c[116,95,99,120,54,51]/1(c[91,124,93]/2(c[115,112,121]/1(c[58]/2(a[117,115,101,114],c[115,112,101]/1(V0))),c[91,124,93]/2(c[110,111,115,112,121]/1(c[58]/2(a[117,115,101,114],c[115,112,101]/1(V1))),nil)))",
    "t_cx64 c[116,95,99,120,54,52]/1(c[45]/2(i1,c[91,124,93]/2(c[115,112,121]/1(c[115,112,100]/1(V0)),c[91,124,93]/2(c[110,111,115,112,121]/1(c[115,112,100]/1(V1)),nil))))"
]

function _cx_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _CX_CASES]
    text =
        _CX_PROGRAM * join([
            replace(replace(_CX_WRAP, "@ID@" => id), "@GOAL@" => g) for (id, g) in _CX_CASES
        ])
    f = joinpath(mktempdir(), "compext.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _cx_kernel(::Type{T}, path::String, names::Vector{String}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cx_enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_cxs(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _cx_enc(mk_expr(T, T[_cxs(T, name), lk_answers(ld, (a:a)...)...]))
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

@testset "'\$notrace'/1, '\$predefine_foreign'/1, '\$vmi_property'/2, '\$spy'/1 and '\$nospy'/1 as swipl's (cx01-cx64)" begin
    f, names = _cx_file()
    kl, _, _ = _cx_kernel(_CX, f, names)
    @test length(kl) == length(_CX_PINNED)
    for (k, p) in zip(kl, _CX_PINNED)
        k == p || println(stderr, "  ours  ", k, "\\n  swipl ", p)
        @test k == p
    end
end

"The atom and functor-name codes of a pin line, as text (for a substring test)."
_cx_decode(l::AbstractString) = join(
    [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"[ac]\[([\d,]+)\]", l)
    ],
    " "
)

@testset "the kernel's debugger status, spy points and foreign flags after the rows (white box)" begin
    f, names = _cx_file()
    _, gd, ld = _cx_kernel(_CX, f, names)
    # every row restored the status it found, and the wrapper switched the debug mode off
    @test !ld.debugstatus_tracing
    @test !ld.debugstatus_debugging
    @test ld.prolog_flag_mask & LK.RUN_MODE_NORMAL == LK.RUN_MODE_NORMAL
    userm = LK.MODULE_user(gd)
    for sp in ("spa", "spb", "spc", "spe", "spd")        # every spy point the rows set was cleared (`'$nospy'/1`)
        proc = LK.isCurrentProcedure(sym_key(_cxs(_CX, sp)), 1, userm)
        @test proc !== nothing
        proc === nothing || @test (proc.definition.flags & LK.SPY_ME) == 0
    end
    # `'$predefine_foreign'/1` set P_FOREIGN on the predicates of cx14, cx15 and cx21
    for (nm, ar) in (("pfa", 2), ("pfb", 1), ("pfe", 0))
        proc = LK.isCurrentProcedure(sym_key(_cxs(_CX, nm)), ar, userm)
        @test proc !== nothing
        proc === nothing || @test (proc.definition.flags & LK.P_FOREIGN) != 0
    end
end

# THE MESSAGES, read by the test's own collector (`lk_install_message_collector!`, kinds informational) on a database of its own:
# `'$spy'/1` reports `spy(Head)` once (a spy point already set is silent), `'$nospy'/1` reports `nospy(Head)` only when it cleared one.
@testset "the kernel's collected '\$spy'/1 and '\$nospy'/1 messages (white box)" begin
    T = _CX
    text = raw"""
    spw(1).
    t_spy(_) :- '$spy'(spw(_)), '$spy'(spw(_)), '$nospy'(spw(_)), '$nospy'(spw(_)), set_prolog_flag(debug, false).
    t_idle(_) :- '$nospy'(spw(_)), set_prolog_flag(debug, false).
    """
    path = joinpath(mktempdir(), "spymsg.pl")
    write(path, text)
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    lk_install_message_collector!(gd, ld; kinds=(:informational,))
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    lk_take_messages!(ld)                                          # the load's messages are not the rows'
    run(name) = LK.query_answers(
        ld,
        mk_expr(
            T,
            T[
                mk_sym(T, :(:)), mk_sym(T, :user),
                mk_expr(T, T[_cxs(T, name), _cxs(T, "x")])
            ]
        );
        limit=1
    )
    @test !isempty(run("t_spy"))
    msgs = lk_take_messages!(ld)
    spy_enc = "c" * _cx_codes("spy") * "/1(c" * _cx_codes("spw") * "/1(V0))"
    nospy_enc = "c" * _cx_codes("nospy") * "/1(c" * _cx_codes("spw") * "/1(V0))"
    @test [k for (k, _) in msgs] == [:informational, :informational]
    @test [_cx_enc(m) for (_, m) in msgs] == [spy_enc, nospy_enc]
    @test !isempty(run("t_idle"))                                   # no spy point set: no message
    @test isempty(lk_take_messages!(ld))
    @test !ld.debugstatus_debugging
end

@testset "the CX rows are not vacuous" begin
    @test length(_CX_PINNED) == length(_CX_CASES) + 1
    @test _CX_PINNED[1] == "ok"
    answered = [l for l in _CX_PINNED if occursin(r"^t_cx\d\d ", l)]
    failed = [l for l in _CX_PINNED if occursin(r"^t_cx\d\d$", l)]
    @test length(answered) >= 50                                         # most rows answer
    @test length(failed) >= 2                                            # cx40 and cx58 fail
    # the error forms are read back, not only the successes
    decoded = Dict(split(l, ' ')[1] => _cx_decode(l) for l in _CX_PINNED if startswith(l, "t_cx"))
    @test occursin("instantiation_error", decoded["t_cx16"])
    @test occursin("type_error", decoded["t_cx17"]) && occursin("atom", decoded["t_cx17"])
    @test occursin("existence_error", decoded["t_cx45"]) && occursin("vmi", decoded["t_cx45"])
    @test occursin("domain_error", decoded["t_cx42"]) && occursin("vmi_property", decoded["t_cx42"])
    @test occursin("existence_error", decoded["t_cx54"]) && occursin("procedure", decoded["t_cx54"])
    # the messages of the spy rows are read back, in order
    @test occursin("spy", decoded["t_cx51"]) && occursin("nospy", decoded["t_cx51"])
    @test count("spy", decoded["t_cx52"]) == 2 && count("nospy", decoded["t_cx52"]) == 1   # `nospy` contains `spy`: the repeats are silent
    @test any(l -> startswith(l, "t_cx22 ") && occursin("a[116,114,117,101]", l), _CX_PINNED)   # break(true) is read back
    @test any(l -> startswith(l, "t_cx14 ") && occursin("i1,i1", l), _CX_PINNED)          # foreign 1, defined 1
    @test length(unique(_CX_PINNED)) == length(_CX_PINNED)               # the rows differ from one another
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_CX_PINNED) == length(_CX_CASES) + 1
    if swipl === nothing
        @info "CX LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _cx_file()
        @test _cx_swipl_lines(f, names) == _CX_PINNED
    end
end
