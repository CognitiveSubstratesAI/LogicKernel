# ORIGINAL: a LIVE differential of COMP-EXT's predicates against swipl at the pin: `'$notrace'/1` (pl-pro.c:392-410), `'$predefine_foreign'/1`
# `'$vmi_property'/2` and `'$fetch_vm'/4` (pl-comp.c:5277-5285, :8106-8206), `'$spy'/1` and `'$nospy'/1` (pl-trace.c:2342-2379); audit D-0784. Rows cx01-cx115:
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
#   * `'$fetch_vm'/4` rows (cx65-cx115): the clause references come from `clause/3` and `nth_clause/3`, the program's `vm_all/2` walks a clause
#     by `NextPC` and lists the instructions, `vm_pc/3` lists `PC-Instruction`. KNOWN DIFFERENCE (named): `h_string` and `h_mpz` are inline blocks
#     in swipl and one literal-table word in the kernel (src/pl-comp.jl `unify_vmi`, DIVERGES), so their offsets differ by design: those rows (cx70,
#     cx71) compare the instruction LISTS only (`vm_of/2`), never `NextPC`; every row with offsets (cx78-cx83, cx86-cx87, cx95, cx100-cx101, cx109)
#     is on a clause without those two instructions. The `s_trustme` operand is a clause pointer in swipl and a clause reference in the kernel:
#     the rows with a called or dynamic predicate (cx104-cx105) read the instruction NAMES only.
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
vm_all(Ref, L) :- vm_all(Ref, 0, L).
vm_all(Ref, PC, L) :- ( '$fetch_vm'(Ref, PC, N, I), N > PC -> L = [I|T], vm_all(Ref, N, T) ; L = [] ).
vm_pc(Ref, PC, L) :- ( '$fetch_vm'(Ref, PC, N, I), N > PC -> L = [PC-I|T], vm_pc(Ref, N, T) ; L = [] ).
vm_end(Ref, PC, End) :- ( '$fetch_vm'(Ref, PC, N, _), N > PC -> vm_end(Ref, N, End) ; End = PC ).
vm_of(H, L) :- clause(H, _, Ref), vm_all(Ref, L).
vm_pcs(H, L) :- clause(H, _, Ref), vm_pc(Ref, 0, L).
vc(_).
vf1(a).
vf2(1).
vf3([]).
vf4(f(X, X)).
vf5(2.5).
vf6("s").
vf7(100000000000000000000).
vf8(1).
vf8(2).
vr1(X) :- vc(X).
vr2(X) :- vc(X), !, vc(X).
vr3(X) :- Y is X+1, vc(Y).
vr4(X) :- X = foo(_, bar).
vr5(X) :- lists:append(X, [], _).
vr6(X) :- m1:vc(X), vc(X).
vr7(X) :- Y = bar, vc(Y), Y == bar, X \== bar.
vr8(X) :- vc(3), vc(X).
vr9(X) :- m1:vc(X).
vr10(X) :- X == 5, X \== 6.
vq1(1).
vq2(1).
:- dynamic vq3/1.
vq3(1).
"""
# one row: the case wrapped as described in the header (`@ID@`, `@GOAL@` replaced)
const _CX_WRAP = raw"t_@ID@(R) :- ( catch((@GOAL@), error(SsuE, _), R = raised(SsuE)) -> Ok = yes ; Ok = no ), set_prolog_flag(debug, false), Ok == yes." *
                 "\n"

# cx01-cx13: `'$notrace'/1` (the goal's answer, failure and ball pass through; the tracing bit and the skip level are what they were before, the
# debugging bit is restored too, cx07, and is off inside the goal, cx12: 13 = 15 less the debugging bit); cx14-cx21: `'$predefine_foreign'/1` (the foreign attribute, the four error forms, a qualified and a 0-arity
# predicate); cx22-cx50: `'$vmi_property'/2` (`break/1`, `argv/1` of eleven instructions, the error forms, upper-case and unknown names);
# cx51-cx64: `'$spy'/1` and `'$nospy'/1` (the attribute, the debug flag, the message on each side, the silent repeats, the errors);
# cx65-cx115: `'$fetch_vm'/4` (cx65-cx77 the instruction list of a clause: atom, small int, nil, compound with a repeated variable, float, string, big
# integer, calls, cut, `is`, head unification of a compound, `lists:`- and `m1:`-qualified calls; cx78-cx84 `PC-Instruction` pairs and `nth_clause/3`;
# cx85-cx90 a bound `NextPC` or `Instruction`; cx91-cx98 the error forms and the end of the code; cx99-cx107 the supervisor of a predicate: the head
# form, `Name/Arity`, a qualified indicator, never called, called once, dynamic, undefined); cx108-cx115 a bound zero-argument instruction (match and
# mismatch), `s_trustme(clause(_))`, body unifications and comparisons with an atom (`vr7`), `b_smallint` (`vr8`), a bound `h_functor` (match, wrong arity, wrong name).
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
    ),
    (
        "cx65",
        raw"vm_of(vf1(_), R)"
    ),
    (
        "cx66",
        raw"vm_of(vf2(_), R)"
    ),
    (
        "cx67",
        raw"vm_of(vf3(_), R)"
    ),
    (
        "cx68",
        raw"vm_of(vf4(_), R)"
    ),
    (
        "cx69",
        raw"vm_of(vf5(_), R)"
    ),
    (
        "cx70",
        raw"vm_of(vf6(_), R)"
    ),
    (
        "cx71",
        raw"vm_of(vf7(_), R)"
    ),
    (
        "cx72",
        raw"vm_of(vr1(_), R)"
    ),
    (
        "cx73",
        raw"vm_of(vr2(_), R)"
    ),
    (
        "cx74",
        raw"vm_of(vr3(_), R)"
    ),
    (
        "cx75",
        raw"vm_of(vr4(_), R)"
    ),
    (
        "cx76",
        raw"vm_of(vr5(_), R)"
    ),
    (
        "cx77",
        raw"vm_of(vr6(_), R)"
    ),
    (
        "cx78",
        raw"vm_pcs(vf1(_), R)"
    ),
    (
        "cx79",
        raw"vm_pcs(vf4(_), R)"
    ),
    (
        "cx80",
        raw"vm_pcs(vr1(_), R)"
    ),
    (
        "cx81",
        raw"vm_pcs(vr2(_), R)"
    ),
    (
        "cx82",
        raw"vm_pcs(vr3(_), R)"
    ),
    (
        "cx83",
        raw"vm_pcs(vr4(_), R)"
    ),
    (
        "cx84",
        raw"nth_clause(vf8(_), 2, Ref), vm_all(Ref, R)"
    ),
    (
        "cx85",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, 0, _, h_atom(X)), R = X"
    ),
    (
        "cx86",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, 0, N, I), R = N-I"
    ),
    (
        "cx87",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, 0, 2, h_atom(a)), R = ok"
    ),
    (
        "cx88",
        raw"clause(vf1(_), _, Ref), ( '$fetch_vm'(Ref, 0, 99, _) -> R = yes ; R = no )"
    ),
    (
        "cx89",
        raw"clause(vf1(_), _, Ref), ( '$fetch_vm'(Ref, 0, _, b_void) -> R = yes ; R = no )"
    ),
    (
        "cx90",
        raw"clause(vf1(_), _, Ref), ( '$fetch_vm'(Ref, 0, _, h_atom(b)) -> R = yes ; R = no )"
    ),
    (
        "cx91",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, -1, _, _)"
    ),
    (
        "cx92",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, 99, _, _)"
    ),
    (
        "cx93",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, a, _, _)"
    ),
    (
        "cx94",
        raw"clause(vf1(_), _, Ref), '$fetch_vm'(Ref, _, _, _)"
    ),
    (
        "cx95",
        raw"clause(vf1(_), _, Ref), vm_end(Ref, 0, End), ( '$fetch_vm'(Ref, End, _, _) -> R = yes ; R = End-no )"
    ),
    (
        "cx96",
        raw"clause(vf1(_), _, Ref), vm_end(Ref, 0, End), E1 is End+1, '$fetch_vm'(Ref, E1, _, _)"
    ),
    (
        "cx97",
        raw"'$fetch_vm'(_, 0, _, _)"
    ),
    (
        "cx98",
        raw"'$fetch_vm'(1, 0, _, _)"
    ),
    (
        "cx99",
        raw"vm_all(vq1/1, R)"
    ),
    (
        "cx100",
        raw"'$fetch_vm'(vq1(_), 0, N, I), R = N-I"
    ),
    (
        "cx101",
        raw"vm_pc(vq1/1, 0, R)"
    ),
    (
        "cx102",
        raw"( '$fetch_vm'(vq1/1, 2, _, _) -> R = yes ; R = no )"
    ),
    (
        "cx103",
        raw"'$fetch_vm'(vq1/1, 3, _, _)"
    ),
    (
        "cx104",
        raw"vq2(1), vm_all(vq2/1, L), findall(N, (member(I, L), functor(I, N, _)), R)"
    ),
    (
        "cx105",
        raw"vm_all(vq3/1, L), findall(N, (member(I, L), functor(I, N, _)), R)"
    ),
    (
        "cx106",
        raw"vm_all(vq9/1, R)"
    ),
    (
        "cx107",
        raw"vm_all(user:vq1/1, R)"
    ),
    (
        "cx108",
        raw"clause(vf3(_), _, Ref), ( '$fetch_vm'(Ref, 0, _, i_exitfact) -> R = yes ; R = no )"
    ),
    (
        "cx109",
        raw"clause(vf3(_), _, Ref), '$fetch_vm'(Ref, 0, N, h_nil), R = N"
    ),
    (
        "cx110",
        raw"vq2(1), '$fetch_vm'(vq2/1, 0, _, s_trustme(clause(_))), R = ok"
    ),
    (
        "cx111",
        raw"vm_of(vr7(_), R)"
    ),
    (
        "cx112",
        raw"vm_of(vr8(_), R)"
    ),
    (
        "cx113",
        raw"clause(vf4(_), _, Ref), ( '$fetch_vm'(Ref, 0, _, h_functor(f/3)) -> R = yes ; R = no )"
    ),
    (
        "cx114",
        raw"clause(vf4(_), _, Ref), ( '$fetch_vm'(Ref, 0, _, h_functor(g/2)) -> R = yes ; R = no )"
    ),
    (
        "cx115",
        raw"clause(vf4(_), _, Ref), '$fetch_vm'(Ref, 0, _, h_functor(f/2)), R = ok"
    ),
    (
        "cx116",
        raw"clause(vf1(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx117",
        raw"clause(vf2(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx118",
        raw"clause(vf4(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx119",
        raw"clause(vf5(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx120",
        raw"clause(vf6(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx121",
        raw"clause(vr1(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx122",
        raw"clause(vr6(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx123",
        raw"clause(vr5(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx124",
        raw"clause(vr4(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx125",
        raw"clause(vr7(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx126",
        raw"clause(vr10(_), _, Ref), findall(X, '$xr_member'(Ref, X), R)"
    ),
    (
        "cx127",
        raw"clause(vf1(_), _, Ref), ( '$xr_member'(Ref, a) -> R = yes ; R = no )"
    ),
    (
        "cx128",
        raw"clause(vf1(_), _, Ref), ( '$xr_member'(Ref, b) -> R = yes ; R = no )"
    ),
    (
        "cx129",
        raw"clause(vr10(_), _, Ref), ( '$xr_member'(Ref, 5) -> R = yes ; R = no )"
    ),
    (
        "cx130",
        raw"clause(vr8(_), _, Ref), ( '$xr_member'(Ref, 3) -> R = yes ; R = no )"
    ),
    (
        "cx131",
        raw"clause(vf4(_), _, Ref), ( '$xr_member'(Ref, f(_, _)) -> R = yes ; R = no )"
    ),
    (
        "cx132",
        raw"clause(vf4(_), _, Ref), ( '$xr_member'(Ref, f(_)) -> R = yes ; R = no )"
    ),
    (
        "cx133",
        raw"clause(vf4(_), _, Ref), ( '$xr_member'(Ref, g(_, _)) -> R = yes ; R = no )"
    ),
    (
        "cx134",
        raw"clause(vr5(_), _, Ref), ( '$xr_member'(Ref, lists) -> R = yes ; R = no )"
    ),
    (
        "cx135",
        raw"clause(vr5(_), _, Ref), ( '$xr_member'(Ref, nosuch) -> R = yes ; R = no )"
    ),
    (
        "cx136",
        raw"clause(vr1(_), _, Ref), ( '$xr_member'(Ref, user:vc(_)) -> R = yes ; R = no )"
    ),
    (
        "cx137",
        raw"clause(vr1(_), _, Ref), ( '$xr_member'(Ref, vc(_)) -> R = yes ; R = no )"
    ),
    (
        "cx138",
        raw"clause(vr9(_), _, Ref), ( '$xr_member'(Ref, m1:vc(_)) -> R = yes ; R = no )"
    ),
    (
        "cx139",
        raw"clause(vr9(_), _, Ref), ( '$xr_member'(Ref, user:vc(_)) -> R = yes ; R = no )"
    ),
    (
        "cx140",
        raw"clause(vr1(_), _, Ref), ( '$xr_member'(Ref, user:vd(_)) -> R = yes ; R = no )"
    ),
    (
        "cx141",
        raw"clause(vr5(_), _, Ref), ( '$xr_member'(Ref, lists:append(_, _, _)) -> R = yes ; R = no )"
    ),
    (
        "cx142",
        raw"clause(vr1(_), _, Ref), ( '$xr_member'(Ref, 1.5) -> R = yes ; R = no )"
    ),
    (
        "cx143",
        raw"clause(vr7(_), _, Ref), '$xr_member'(Ref, X), X = vc(_), R = X"
    ),
    (
        "cx144",
        raw"'$xr_member'(a, _), R = ok"
    ),
    (
        "cx145",
        raw"'$xr_member'(_, _), R = ok"
    ),
    (
        "cx146",
        raw"assertz(vt1(a), Ref), erase(Ref), ( '$xr_member'(Ref, _) -> R = yes ; R = no )"
    ),
    (
        "cx147",
        raw"clause(vf1(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx148",
        raw"clause(vr1(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx149",
        raw"clause(vr2(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx150",
        raw"clause(vr3(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx151",
        raw"clause(vr4(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx152",
        raw"clause(vr7(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx153",
        raw"clause(vr8(_), _, Ref), findall(S-E, '$break_pc'(Ref, S, E), R)"
    ),
    (
        "cx154",
        raw"clause(vr2(_), _, Ref), once('$break_pc'(Ref, S, E)), R = S-E"
    ),
    (
        "cx155",
        raw"clause(vr4(_), _, Ref), findall(E, '$break_pc'(Ref, 1, E), R)"
    ),
    (
        "cx156",
        raw"'$break_pc'(a, _, _), R = ok"
    ),
    (
        "cx157",
        raw"assertz(vt2(a), Ref), erase(Ref), ( '$break_pc'(Ref, _, _) -> R = yes ; R = no )"
    ),
    (
        "cx158",
        raw"clause(vr4(_), _, Ref), '$break_pc'(Ref, S, E), S > 0, R = S-E"
    ),
    (
        "cx159",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, 100000, true), R = ok"
    ),
    (
        "cx160",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, -1, true), R = ok"
    ),
    (
        "cx161",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, a, true), R = ok"
    ),
    (
        "cx162",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, 0, foo), R = ok"
    ),
    (
        "cx163",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, a, foo), R = ok"
    ),
    (
        "cx164",
        raw"'$break_at'(a, 0, true), R = ok"
    ),
    (
        "cx165",
        raw"assertz(vt3(a), Ref), erase(Ref), ( '$break_at'(Ref, 0, true) -> R = yes ; R = no )"
    ),
    (
        "cx166",
        raw"clause(vf1(_), _, Ref), catch('$break_at'(Ref, 0, false), error(existence_error(break, break(Ref2, O)), _), ( Ref2 == Ref -> R = got(O) ; R = other ))"
    ),
    (
        "cx167",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, 100000, false), R = ok"
    ),
    (
        "cx168",
        raw"clause(vf1(_), _, Ref), catch('$break_at'(Ref, 0, true), error(permission_error(set, break, break(Ref2, O)), _), ( Ref2 == Ref -> R = got(O) ; R = other ))"
    ),
    (
        "cx169",
        raw"clause(vf1(_), _, Ref), catch('$break_at'(Ref, 0, off), error(existence_error(break, break(Ref2, O)), _), ( Ref2 == Ref -> R = got(O) ; R = other ))"
    ),
    (
        "cx170",
        raw"clause(vf1(_), _, Ref), '$break_at'(Ref, 0, _), R = ok"
    ),
    (
        "cx171",
        raw"clause(vf1(_), _, Ref), catch('$break_at'(Ref, 0, on), error(permission_error(set, break, break(Ref2, O)), _), ( Ref2 == Ref -> R = got(O) ; R = other ))"
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
    "t_cx64 c[116,95,99,120,54,52]/1(c[45]/2(i1,c[91,124,93]/2(c[115,112,121]/1(c[115,112,100]/1(V0)),c[91,124,93]/2(c[110,111,115,112,121]/1(c[115,112,100]/1(V1)),nil))))",
    "t_cx65 c[116,95,99,120,54,53]/1(c[91,124,93]/2(c[104,95,97,116,111,109]/1(a[97]),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx66 c[116,95,99,120,54,54]/1(c[91,124,93]/2(c[104,95,115,109,97,108,108,105,110,116]/1(i1),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx67 c[116,95,99,120,54,55]/1(c[91,124,93]/2(a[104,95,110,105,108],c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx68 c[116,95,99,120,54,56]/1(c[91,124,93]/2(c[104,95,102,117,110,99,116,111,114]/1(c[47]/2(a[102],i2)),c[91,124,93]/2(c[104,95,102,105,114,115,116,118,97,114]/1(i1),c[91,124,93]/2(c[104,95,118,97,114]/1(i1),c[91,124,93]/2(a[104,95,112,111,112],c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil))))))",
    "t_cx69 c[116,95,99,120,54,57]/1(c[91,124,93]/2(c[104,95,102,108,111,97,116]/1(f2.5),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx70 c[116,95,99,120,55,48]/1(c[91,124,93]/2(c[104,95,115,116,114,105,110,103]/1(s[115]),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx71 c[116,95,99,120,55,49]/1(c[91,124,93]/2(c[104,95,109,112,122]/1(i100000000000000000000),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx72 c[116,95,99,120,55,50]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(c[108,95,110,111,108,99,111]/1(i2),c[91,124,93]/2(c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))",
    "t_cx73 c[116,95,99,120,55,51]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,99,117,116],c[91,124,93]/2(c[108,95,110,111,108,99,111]/1(i2),c[91,124,93]/2(c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,101,120,105,116],nil))))))))))",
    "t_cx74 c[116,95,99,120,55,52]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(c[97,95,97,100,100,95,102,99]/3(i1,i0,i1),c[91,124,93]/2(c[108,95,110,111,108,99,111]/1(i5),c[91,124,93]/2(c[108,95,118,97,114]/2(i0,i1),c[91,124,93]/2(c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[98,95,118,97,114,49],c[91,124,93]/2(c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))))",
    "t_cx75 c[116,95,99,120,55,53]/1(c[91,124,93]/2(c[104,95,102,117,110,99,116,111,114]/1(c[47]/2(a[102,111,111],i2)),c[91,124,93]/2(a[104,95,118,111,105,100],c[91,124,93]/2(c[104,95,97,116,111,109]/1(a[98,97,114]),c[91,124,93]/2(a[104,95,112,111,112],c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))",
    "t_cx76 c[116,95,99,120,55,54]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(a[98,95,110,105,108],c[91,124,93]/2(a[98,95,118,111,105,100],c[91,124,93]/2(c[105,95,100,101,112,97,114,116,109]/2(a[108,105,115,116,115],c[58]/2(a[108,105,115,116,115],c[47]/2(a[97,112,112,101,110,100],i3))),c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))",
    "t_cx77 c[116,95,99,120,55,55]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,99,97,108,108,109]/2(a[109,49],c[58]/2(a[109,49],c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[108,95,110,111,108,99,111]/1(i2),c[91,124,93]/2(c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))))",
    "t_cx78 c[116,95,99,120,55,56]/1(c[91,124,93]/2(c[45]/2(i0,c[104,95,97,116,111,109]/1(a[97])),c[91,124,93]/2(c[45]/2(i2,a[105,95,101,120,105,116,102,97,99,116]),nil)))",
    "t_cx79 c[116,95,99,120,55,57]/1(c[91,124,93]/2(c[45]/2(i0,c[104,95,102,117,110,99,116,111,114]/1(c[47]/2(a[102],i2))),c[91,124,93]/2(c[45]/2(i2,c[104,95,102,105,114,115,116,118,97,114]/1(i1)),c[91,124,93]/2(c[45]/2(i4,c[104,95,118,97,114]/1(i1)),c[91,124,93]/2(c[45]/2(i6,a[104,95,112,111,112]),c[91,124,93]/2(c[45]/2(i7,a[105,95,101,120,105,116,102,97,99,116]),nil))))))",
    "t_cx80 c[116,95,99,120,56,48]/1(c[91,124,93]/2(c[45]/2(i0,a[105,95,101,110,116,101,114]),c[91,124,93]/2(c[45]/2(i1,c[108,95,110,111,108,99,111]/1(i2)),c[91,124,93]/2(c[45]/2(i3,c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i5,a[98,95,118,97,114,48]),c[91,124,93]/2(c[45]/2(i6,c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i8,a[105,95,101,120,105,116]),nil)))))))",
    "t_cx81 c[116,95,99,120,56,49]/1(c[91,124,93]/2(c[45]/2(i0,a[105,95,101,110,116,101,114]),c[91,124,93]/2(c[45]/2(i1,a[98,95,118,97,114,48]),c[91,124,93]/2(c[45]/2(i2,c[105,95,99,97,108,108]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i4,a[105,95,99,117,116]),c[91,124,93]/2(c[45]/2(i5,c[108,95,110,111,108,99,111]/1(i2)),c[91,124,93]/2(c[45]/2(i7,c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i9,a[98,95,118,97,114,48]),c[91,124,93]/2(c[45]/2(i10,c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i12,a[105,95,101,120,105,116]),nil))))))))))",
    "t_cx82 c[116,95,99,120,56,50]/1(c[91,124,93]/2(c[45]/2(i0,a[105,95,101,110,116,101,114]),c[91,124,93]/2(c[45]/2(i1,c[97,95,97,100,100,95,102,99]/3(i1,i0,i1)),c[91,124,93]/2(c[45]/2(i5,c[108,95,110,111,108,99,111]/1(i5)),c[91,124,93]/2(c[45]/2(i7,c[108,95,118,97,114]/2(i0,i1)),c[91,124,93]/2(c[45]/2(i10,c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i12,a[98,95,118,97,114,49]),c[91,124,93]/2(c[45]/2(i13,c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1))),c[91,124,93]/2(c[45]/2(i15,a[105,95,101,120,105,116]),nil)))))))))",
    "t_cx83 c[116,95,99,120,56,51]/1(c[91,124,93]/2(c[45]/2(i0,c[104,95,102,117,110,99,116,111,114]/1(c[47]/2(a[102,111,111],i2))),c[91,124,93]/2(c[45]/2(i2,a[104,95,118,111,105,100]),c[91,124,93]/2(c[45]/2(i3,c[104,95,97,116,111,109]/1(a[98,97,114])),c[91,124,93]/2(c[45]/2(i5,a[104,95,112,111,112]),c[91,124,93]/2(c[45]/2(i6,a[105,95,101,110,116,101,114]),c[91,124,93]/2(c[45]/2(i7,a[105,95,101,120,105,116]),nil)))))))",
    "t_cx84 c[116,95,99,120,56,52]/1(c[91,124,93]/2(c[104,95,115,109,97,108,108,105,110,116]/1(i2),c[91,124,93]/2(a[105,95,101,120,105,116,102,97,99,116],nil)))",
    "t_cx85 c[116,95,99,120,56,53]/1(a[97])",
    "t_cx86 c[116,95,99,120,56,54]/1(c[45]/2(i2,c[104,95,97,116,111,109]/1(a[97])))",
    "t_cx87 c[116,95,99,120,56,55]/1(a[111,107])",
    "t_cx88 c[116,95,99,120,56,56]/1(a[110,111])",
    "t_cx89 c[116,95,99,120,56,57]/1(a[110,111])",
    "t_cx90 c[116,95,99,120,57,48]/1(a[110,111])",
    "t_cx91 c[116,95,99,120,57,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i-1)))",
    "t_cx92 c[116,95,99,120,57,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i99)))",
    "t_cx93 c[116,95,99,120,57,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_cx94 c[116,95,99,120,57,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx95 c[116,95,99,120,57,53]/1(c[45]/2(i3,a[110,111]))",
    "t_cx96 c[116,95,99,120,57,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i4)))",
    "t_cx97 c[116,95,99,120,57,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx98 c[116,95,99,120,57,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_cx99 c[116,95,99,120,57,57]/1(c[91,124,93]/2(a[115,95,118,105,114,103,105,110],c[91,124,93]/2(a[105,95,101,120,105,116],nil)))",
    "t_cx100 c[116,95,99,120,49,48,48]/1(c[45]/2(i1,a[115,95,118,105,114,103,105,110]))",
    "t_cx101 c[116,95,99,120,49,48,49]/1(c[91,124,93]/2(c[45]/2(i0,a[115,95,118,105,114,103,105,110]),c[91,124,93]/2(c[45]/2(i1,a[105,95,101,120,105,116]),nil)))",
    "t_cx102 c[116,95,99,120,49,48,50]/1(a[110,111])",
    "t_cx103 c[116,95,99,120,49,48,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i3)))",
    "t_cx104 c[116,95,99,120,49,48,52]/1(c[91,124,93]/2(a[115,95,116,114,117,115,116,109,101],nil))",
    "t_cx105 c[116,95,99,120,49,48,53]/1(c[91,124,93]/2(a[115,95,118,105,114,103,105,110],c[91,124,93]/2(a[105,95,101,120,105,116],nil)))",
    "t_cx106 c[116,95,99,120,49,48,54]/1(c[91,124,93]/2(a[115,95,118,105,114,103,105,110],c[91,124,93]/2(a[105,95,101,120,105,116],nil)))",
    "t_cx107 c[116,95,99,120,49,48,55]/1(c[91,124,93]/2(a[115,95,118,105,114,103,105,110],c[91,124,93]/2(a[105,95,101,120,105,116],nil)))",
    "t_cx108 c[116,95,99,120,49,48,56]/1(a[110,111])",
    "t_cx109 c[116,95,99,120,49,48,57]/1(i1)",
    "t_cx110 c[116,95,99,120,49,49,48]/1(a[111,107])",
    "t_cx111 c[116,95,99,120,49,49,49]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(c[98,95,117,110,105,102,121,95,102,99]/2(i1,a[98,97,114]),c[91,124,93]/2(a[98,95,118,97,114,49],c[91,124,93]/2(c[105,95,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(c[98,95,101,113,95,118,99]/2(i1,a[98,97,114]),c[91,124,93]/2(c[98,95,110,101,113,95,118,99]/2(i0,a[98,97,114]),c[91,124,93]/2(a[105,95,101,120,105,116],nil))))))))",
    "t_cx112 c[116,95,99,120,49,49,50]/1(c[91,124,93]/2(a[105,95,101,110,116,101,114],c[91,124,93]/2(c[98,95,115,109,97,108,108,105,110,116]/1(i3),c[91,124,93]/2(c[105,95,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(c[108,95,110,111,108,99,111]/1(i2),c[91,124,93]/2(c[105,95,108,99,97,108,108]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[98,95,118,97,114,48],c[91,124,93]/2(c[105,95,100,101,112,97,114,116]/1(c[47]/2(a[118,99],i1)),c[91,124,93]/2(a[105,95,101,120,105,116],nil)))))))))",
    "t_cx113 c[116,95,99,120,49,49,51]/1(a[110,111])",
    "t_cx114 c[116,95,99,120,49,49,52]/1(a[110,111])",
    "t_cx115 c[116,95,99,120,49,49,53]/1(a[111,107])",
    "t_cx116 c[116,95,99,120,49,49,54]/1(c[91,124,93]/2(a[97],nil))",
    "t_cx117 c[116,95,99,120,49,49,55]/1(nil)",
    "t_cx118 c[116,95,99,120,49,49,56]/1(c[91,124,93]/2(c[102]/2(V0,V1),nil))",
    "t_cx119 c[116,95,99,120,49,49,57]/1(nil)",
    "t_cx120 c[116,95,99,120,49,50,48]/1(nil)",
    "t_cx121 c[116,95,99,120,49,50,49]/1(c[91,124,93]/2(c[118,99]/1(V0),c[91,124,93]/2(c[118,99]/1(V1),nil)))",
    "t_cx122 c[116,95,99,120,49,50,50]/1(c[91,124,93]/2(a[109,49],c[91,124,93]/2(c[58]/2(a[109,49],c[118,99]/1(V0)),c[91,124,93]/2(c[118,99]/1(V1),c[91,124,93]/2(c[118,99]/1(V2),nil)))))",
    "t_cx123 c[116,95,99,120,49,50,51]/1(c[91,124,93]/2(a[108,105,115,116,115],c[91,124,93]/2(c[58]/2(a[108,105,115,116,115],c[97,112,112,101,110,100]/3(V0,V1,V2)),nil)))",
    "t_cx124 c[116,95,99,120,49,50,52]/1(c[91,124,93]/2(c[102,111,111]/2(V0,V1),c[91,124,93]/2(a[98,97,114],nil)))",
    "t_cx125 c[116,95,99,120,49,50,53]/1(c[91,124,93]/2(a[98,97,114],c[91,124,93]/2(c[118,99]/1(V0),c[91,124,93]/2(a[98,97,114],c[91,124,93]/2(a[98,97,114],nil)))))",
    "t_cx126 c[116,95,99,120,49,50,54]/1(c[91,124,93]/2(i5,c[91,124,93]/2(i6,nil)))",
    "t_cx127 c[116,95,99,120,49,50,55]/1(a[121,101,115])",
    "t_cx128 c[116,95,99,120,49,50,56]/1(a[110,111])",
    "t_cx129 c[116,95,99,120,49,50,57]/1(a[121,101,115])",
    "t_cx130 c[116,95,99,120,49,51,48]/1(a[110,111])",
    "t_cx131 c[116,95,99,120,49,51,49]/1(a[121,101,115])",
    "t_cx132 c[116,95,99,120,49,51,50]/1(a[110,111])",
    "t_cx133 c[116,95,99,120,49,51,51]/1(a[110,111])",
    "t_cx134 c[116,95,99,120,49,51,52]/1(a[121,101,115])",
    "t_cx135 c[116,95,99,120,49,51,53]/1(a[110,111])",
    "t_cx136 c[116,95,99,120,49,51,54]/1(a[121,101,115])",
    "t_cx137 c[116,95,99,120,49,51,55]/1(a[110,111])",
    "t_cx138 c[116,95,99,120,49,51,56]/1(a[121,101,115])",
    "t_cx139 c[116,95,99,120,49,51,57]/1(a[121,101,115])",
    "t_cx140 c[116,95,99,120,49,52,48]/1(a[110,111])",
    "t_cx141 c[116,95,99,120,49,52,49]/1(a[121,101,115])",
    "t_cx142 c[116,95,99,120,49,52,50]/1(a[110,111])",
    "t_cx143 c[116,95,99,120,49,52,51]/1(c[118,99]/1(V0))",
    "t_cx144 c[116,95,99,120,49,52,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[97])))",
    "t_cx145 c[116,95,99,120,49,52,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx146 c[116,95,99,120,49,52,54]/1(a[110,111])",
    "t_cx147 c[116,95,99,120,49,52,55]/1(nil)",
    "t_cx148 c[116,95,99,120,49,52,56]/1(c[91,124,93]/2(c[45]/2(i0,i1),c[91,124,93]/2(c[45]/2(i6,i8),c[91,124,93]/2(c[45]/2(i8,i9),nil))))",
    "t_cx149 c[116,95,99,120,49,52,57]/1(c[91,124,93]/2(c[45]/2(i0,i1),c[91,124,93]/2(c[45]/2(i2,i4),c[91,124,93]/2(c[45]/2(i4,i5),c[91,124,93]/2(c[45]/2(i10,i12),c[91,124,93]/2(c[45]/2(i12,i13),nil))))))",
    "t_cx150 c[116,95,99,120,49,53,48]/1(c[91,124,93]/2(c[45]/2(i0,i1),c[91,124,93]/2(c[45]/2(i1,i5),c[91,124,93]/2(c[45]/2(i13,i15),c[91,124,93]/2(c[45]/2(i15,i16),nil)))))",
    "t_cx151 c[116,95,99,120,49,53,49]/1(c[91,124,93]/2(c[45]/2(i6,i7),c[91,124,93]/2(c[45]/2(i7,i8),nil)))",
    "t_cx152 c[116,95,99,120,49,53,50]/1(c[91,124,93]/2(c[45]/2(i0,i1),c[91,124,93]/2(c[45]/2(i1,i4),c[91,124,93]/2(c[45]/2(i5,i7),c[91,124,93]/2(c[45]/2(i7,i10),c[91,124,93]/2(c[45]/2(i10,i13),c[91,124,93]/2(c[45]/2(i13,i14),nil)))))))",
    "t_cx153 c[116,95,99,120,49,53,51]/1(c[91,124,93]/2(c[45]/2(i0,i1),c[91,124,93]/2(c[45]/2(i3,i5),c[91,124,93]/2(c[45]/2(i10,i12),c[91,124,93]/2(c[45]/2(i12,i13),nil)))))",
    "t_cx154 c[116,95,99,120,49,53,52]/1(c[45]/2(i0,i1))",
    "t_cx155 c[116,95,99,120,49,53,53]/1(nil)",
    "t_cx156 c[116,95,99,120,49,53,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[97])))",
    "t_cx157 c[116,95,99,120,49,53,55]/1(a[110,111])",
    "t_cx158 c[116,95,99,120,49,53,56]/1(c[45]/2(i6,i7))",
    "t_cx159 c[116,95,99,120,49,53,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i100000)))",
    "t_cx160 c[116,95,99,120,49,54,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_cx161 c[116,95,99,120,49,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_cx162 c[116,95,99,120,49,54,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_cx163 c[116,95,99,120,49,54,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_cx164 c[116,95,99,120,49,54,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[97])))",
    "t_cx165 c[116,95,99,120,49,54,53]/1(a[110,111])",
    "t_cx166 c[116,95,99,120,49,54,54]/1(c[103,111,116]/1(i0))",
    "t_cx167 c[116,95,99,120,49,54,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,111,103,114,97,109,95,99,111,117,110,116,101,114],i100000)))",
    "t_cx168 c[116,95,99,120,49,54,56]/1(c[103,111,116]/1(i0))",
    "t_cx169 c[116,95,99,120,49,54,57]/1(c[103,111,116]/1(i0))",
    "t_cx170 c[116,95,99,120,49,55,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cx171 c[116,95,99,120,49,55,49]/1(c[103,111,116]/1(i0))"
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

@testset "'\$notrace'/1, '\$predefine_foreign'/1, '\$vmi_property'/2, '\$spy'/1, '\$nospy'/1 and '\$fetch_vm'/4 as swipl's (cx01-cx115)" begin
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
    answered = [l for l in _CX_PINNED if occursin(r"^t_cx\d+ ", l)]
    failed = [l for l in _CX_PINNED if occursin(r"^t_cx\d+$", l)]
    @test length(answered) >= 50                                         # most rows answer
    @test length(failed) >= 2                                            # cx40 and cx58 fail
    @test length(answered) + length(failed) == length(_CX_CASES)         # every row has a line
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
    # the `'$fetch_vm'/4` rows are read back: instructions, offsets, the error forms and the supervisor
    @test occursin("h_atom", decoded["t_cx65"]) && occursin("i_exitfact", decoded["t_cx65"])
    @test occursin("h_string", decoded["t_cx70"]) && occursin("h_mpz", decoded["t_cx71"])
    @test occursin("i_depart", decoded["t_cx72"]) && occursin("i_cut", decoded["t_cx73"])
    @test occursin("a_add_fc", decoded["t_cx74"]) && occursin("i_departm", decoded["t_cx76"])
    @test any(l -> startswith(l, "t_cx78 ") && occursin("i0,c[104", l), _CX_PINNED)           # `0-h_atom(a)`: the offsets are read back
    @test occursin("domain_error", decoded["t_cx91"]) && occursin("program_counter", decoded["t_cx91"])
    @test occursin("domain_error", decoded["t_cx92"]) && occursin("program_counter", decoded["t_cx92"])
    @test occursin("type_error", decoded["t_cx93"]) && occursin("instantiation_error", decoded["t_cx94"])
    @test occursin("domain_error", decoded["t_cx96"]) && occursin("instantiation_error", decoded["t_cx97"])
    @test occursin("s_virgin", decoded["t_cx99"]) && occursin("i_exit", decoded["t_cx99"])
    @test occursin("s_trustme", decoded["t_cx104"])
    @test occursin("b_unify_fc", decoded["t_cx111"]) && occursin("b_eq_vc", decoded["t_cx111"]) && occursin("b_neq_vc", decoded["t_cx111"])
    @test occursin("b_smallint", decoded["t_cx112"])
    @test count(l -> occursin(r"^t_cx11[345] ", l) && occursin("a[110,111])", l), _CX_PINNED) == 2   # cx113, cx114: a wrong arity or name does not match
    @test any(l -> l == "t_cx90 c[116,95,99,120,57,48]/1(a[110,111])", _CX_PINNED)          # a bound instruction that does not match fails
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
