% ORIGINAL: the rows of test/core_lang/test_wrap_swipl.jl — no swipl-devel counterpart.
% test/core_lang/test_wrap_swipl.pl — WRAP1's rows (pl-wrap.c: wrap_predicate/4 through '$c_wrap_predicate'/5, the closure
% branch of I_CALL1/I_CALLN, S_WRAP, S_CALLWRAPPER, unwrap_predicate/2, '$wrapped_predicate'/2, '$wrapped_implementation'/3,
% '$closure_predicate'/2, write_closure). Each `tN(R)` is one row; test_wrap_swipl.out holds swipl's answers (10.1.20), as the
% test's driver prints them (`ok`, then one line per row: its name and every solution). A row never encodes a closure blob (a
% blob has no stable text): it records the NAMES, the order of the calls, and the results of the wrapped goals. Every row
% wraps predicates of its own (a wrapper stays for the rest of the run).
:- dynamic log/1.

lg(X) :- assertz(log(X)).
logs(L) :- findall(X, log(X), L), retractall(log(_)).

% t0: wrap + call of a two-clause predicate; the wrapper runs once per solution and sees the bound argument. (A wrapper
% records through lg/1, a user predicate: swipl 10.1.20 loses an `assertz/1` written directly in a wrapper's body when the
% wrapped predicate runs inside findall/3, and runs the unqualified catch/3 recovery of a wrapper in module `system` under
% an outer catch/3: unexplained, probed only, no row of its own.)
p0(1).
p0(2).
t0(R) :-
    logs(_),
    wrap_predicate(p0(X), w, W, (W, lg(X))),
    findall(Y, p0(Y), Ys),
    logs(Ss),
    R = Ys-Ss.

% t1: the same over a SINGLE-clause predicate (S_TRUSTME of the wrapped supervisor, not the wrapper's)
p1(5).
t1(R) :-
    logs(_),
    wrap_predicate(p1(X), w, W, (W, lg(X))),
    findall(Y, p1(Y), Ys),
    logs(Ss),
    R = Ys-Ss.

% t2: nested wraps: the last registered runs outermost
p2(1).
t2(R) :-
    logs(_),
    wrap_predicate(p2(_), wa, W1, (lg(a_in), W1, lg(a_out))),
    wrap_predicate(p2(_), wb, W2, (lg(b_in), W2, lg(b_out))),
    findall(Y, p2(Y), Ys),
    logs(L),
    R = Ys-L.

% t3: a second wrap of the same name replaces the wrapper body and keeps its place in the chain
p3(1).
t3(R) :-
    logs(_),
    wrap_predicate(p3(_), w1, W1, (lg(old1), W1)),
    wrap_predicate(p3(_), w2, W2, (lg(old2), W2)),
    wrap_predicate(p3(_), w1, W3, (lg(new1), W3)),
    findall(Y, p3(Y), Ys),
    logs(L),
    '$wrapped_predicate'(p3(_), Ws),
    findall(N, member(N-_, Ws), Ns),
    R = Ys-L-Ns.

% t4: unwrap_predicate/2: a named one, then `?Name` unbound removes the outermost, then it fails
p4(1).
t4(R) :-
    logs(_),
    wrap_predicate(p4(_), w1, W1, (lg(w1), W1)),
    wrap_predicate(p4(_), w2, W2, (lg(w2), W2)),
    unwrap_predicate(p4/1, w1),
    findall(Y, p4(Y), _),
    logs(L1),
    ( unwrap_predicate(p4/1, N) -> true ; N = none ),
    findall(Z, p4(Z), Zs),
    logs(L2),
    ( unwrap_predicate(p4/1, _) -> More = yes ; More = no ),
    R = L1-N-L2-Zs-More.

% t5: '$wrapped_predicate'/2 lists the wrappers OUTERMOST first; a predicate without wrapper: failure
p5(1).
p5b(1).
t5(R) :-
    wrap_predicate(p5(_), w1, W1, W1),
    wrap_predicate(p5(_), w2, W2, W2),
    wrap_predicate(p5(_), w3, W3, W3),
    '$wrapped_predicate'(p5(_), Ws),
    findall(N, member(N-_, Ws), Ns),
    ( '$wrapped_predicate'(p5b(_), _) -> Plain = wrapped ; Plain = plain ),
    R = Ns-Plain.

% t6: '$wrapped_implementation'/3: calling Wrapped calls the predicate as seen from the wrapper Name
p6(a).
p6(b).
p6z.
t6(R) :-
    wrap_predicate(p6(_), w1, W1, (lg(w1), W1)),
    wrap_predicate(p6(_), w2, W2, (lg(w2), W2)),
    logs(_),
    '$wrapped_implementation'(p6(Y), w2, G),
    findall(Y, call(G), Ys),
    logs(L2),
    '$wrapped_implementation'(p6(Y2), w1, G1),
    findall(Y2, call(G1), Y2s),
    logs(L1),
    ( '$wrapped_implementation'(p6(_), nowrapper, _) -> Q = found ; Q = none ),
    wrap_predicate(p6z, wz, WZ, (lg(wz), WZ)),
    '$wrapped_implementation'(p6z, wz, GZ),
    logs(_),
    ( call(GZ) -> Z = true ; Z = false ),
    R = Ys-L2-Y2s-L1-Q-Z.

% t7: '$closure_predicate'/2 of the closure a wrapper receives (Wrapped = call(Closure(Args...))), and its type error
p7(1).
m7:p7m(1).
t7(R) :-
    wrap_predicate(p7(_), w, W, (W = call(CC), functor(CC, C, _), '$closure_predicate'(C, PI), lg(PI), W)),
    wrap_predicate(m7:p7m(_), w, WM, (WM = call(CCM), functor(CCM, CM, _), '$closure_predicate'(CM, PIM), user:lg(PIM), WM)),
    logs(_),
    p7(_),
    m7:p7m(_),
    logs(L),
    catch('$closure_predicate'(foo, _), error(E, _), true),
    R = L-E.

% t8: the closure ATOM called with call/N (the callargs path of I_CALLN), as library(prolog_wrap)'s gcd example does
p8(X, Y) :- Y is X * 2.
t8(R) :-
    wrap_predicate(p8(_, _), w, W,
                   ( W = call(CC), CC =.. [C, A, B], call(C, A, B1), B is B1 + 1 )),
    p8(5, Y),
    R = Y.

% t9: exceptions through a wrapper: outside, inside (caught by the wrapper), and rethrown. The handlers call user:lg/1
% qualified: swipl 10.1.20 runs the unqualified goal of a wrapper's catch/3 recovery in module `system` when the wrapped
% predicate was called from inside a catch/3 (existence_error(procedure, system:lg/1)); not yet a row of its own (WRAP1 state).
p9(_) :- throw(oops).
p9b(_) :- throw(oops_b).
p9c(_) :- throw(oops_c).
t9(R) :-
    logs(_),
    wrap_predicate(p9(_), w, W, W),
    catch(p9(1), E1, true),
    wrap_predicate(p9b(_), w, Wb, catch(Wb, E, (user:lg(caught(E)), true))),
    ( p9b(1) -> R2 = succeeded ; R2 = failed ),
    wrap_predicate(p9c(_), w, Wc, catch(Wc, E3, (user:lg(rethrow(E3)), throw(again(E3))))),
    catch(p9c(1), E4, true),
    logs(L),
    R = E1-R2-E4-L.

% t10: a wrapper that fails, one that does not call the wrapped goal, and a wrapped goal that fails
p10a(1).
p10b(1).
p10c(1) :- fail.
t10(R) :-
    wrap_predicate(p10a(_), w, _, fail),
    wrap_predicate(p10b(_), w, _, lg(skipped)),
    wrap_predicate(p10c(_), w, Wc, (lg(before), Wc, lg(never))),
    logs(_),
    ( p10a(1) -> A = yes ; A = no ),
    ( p10b(1) -> B = yes ; B = no ),
    ( p10c(1) -> C = yes ; C = no ),
    logs(L),
    R = A-B-C-L.

% t11: an undefined predicate: the existence error names the WRAPPED predicate
t11(R) :-
    wrap_predicate(undef11(_), w, W, (lg(before), W)),
    logs(_),
    catch(undef11(1), error(E, _), true),
    logs(L),
    R = E-L.

% t12: a predicate changed by assert/retract after it was wrapped (the wrapped supervisor is re-created)
:- dynamic d12/1.
t12(R) :-
    wrap_predicate(d12(_), w, W, (lg(w), W)),
    logs(_),
    assertz(d12(1)),
    findall(X, d12(X), L1),
    assertz(d12(2)),
    findall(X, d12(X), L2),
    retract(d12(1)),
    findall(X, d12(X), L3),
    logs(L),
    R = L1-L2-L3-L.

% t13: call/1 of the closure compound is fine (a wrapper calls it so), call/2 of it is a type error
p13(1).
t13(R) :-
    wrap_predicate(p13(_), w, W,
                   ( catch(call(W, extra), error(type_error(T, _), _), true), lg(T), W )),
    logs(_),
    p13(_),
    logs(R).

% t14: a wrapped nondeterministic predicate yields all its solutions through the wrapper, in order
t14(R) :-
    wrap_predicate(p14(_), w, W, (lg(call), W)),
    logs(_),
    findall(X, p14(X), Xs),
    logs(L),
    R = Xs-L.
p14(1).
p14(2).
p14(3).

% t15: the printed form of a closure: <closure>(p/1) and <closure>(m:p/1) (write_closure)
p15(7).
m15:p15m(8).
t15(R) :-
    wrap_predicate(p15(_), w, W, (format(atom(S), '~w', [W]), lg(S), W)),
    wrap_predicate(m15:p15m(_), w, WM, (format(atom(SM), '~w', [WM]), lg(SM), WM)),
    logs(_),
    p15(7),
    m15:p15m(8),
    logs(R).

% t16: current_predicate_wrapper/4 and predicate_property(_, wrapped(_)) see the names
p16(1).
t16(R) :-
    wrap_predicate(p16(_), w1, W1, W1),
    wrap_predicate(p16(_), w2, W2, W2),
    findall(N, current_predicate_wrapper(p16(_), N, _, _), Ns),
    ( predicate_property(p16(_), wrapped(L)) -> true ; L = [] ),
    findall(N2, member(N2-_, L), N2s),
    unwrap_predicate(p16/1, w1),
    findall(N, current_predicate_wrapper(p16(_), N, _, _), Ns2),
    R = Ns-N2s-Ns2.

% t17: a wrapped deterministic foreign predicate (atom_length/2, a system predicate: the wrapper runs, the result stands)
t17(R) :-
    catch(( wrap_predicate(system:atom_length(_, _), w, W, (lg(w), W)), Ok = wrapped ), error(E, _), Ok = E),
    logs(_),
    ( Ok == wrapped -> atom_length(abc, N), unwrap_predicate(system:atom_length/2, w) ; N = none ),
    logs(L),
    R = Ok-N-L.

% t18: a wrapped NON-deterministic foreign predicate (between/3): every solution, in order, retried through the wrapper
t18(R) :-
    catch(( wrap_predicate(system:between(_, _, _), w, W, (lg(w), W)), Ok = wrapped ), error(E, _), Ok = E),
    logs(_),
    ( Ok == wrapped -> findall(X, between(1, 3, X), Xs), unwrap_predicate(system:between/3, w) ; Xs = none ),
    logs(L),
    R = Ok-Xs-L.

% t19: a wrapped two-clause predicate whose first arguments are `[]` and `[_|_]` (the supervisor tests them with S_LIST: its
% operands index the wrapped supervisor's side table, as S_TRUSTME's); both clauses are reached through the wrapper
p19([], nil).
p19([_|_], cons).
t19(R) :-
    logs(_),
    wrap_predicate(p19(_, _), w, W, (lg(w), W)),
    p19([], A),
    p19([x], B),
    logs(L),
    R = A-B-L.

% t20: unwrap_predicate/2 retracts the wrapper's clause: the `$wrap$p20` clauses left after each unwrap (both wrappers' clauses
% live in the one predicate `$wrap$p20`)
p20(1).
t20(R) :-
    wrap_predicate(p20(_), w1, W1, (lg(w1), W1)),
    wrap_predicate(p20(_), w2, W2, (lg(w2), W2)),
    unwrap_predicate(p20/1, w2),
    ( predicate_property('$wrap$p20'(_), number_of_clauses(N1)) -> true ; N1 = none ),
    unwrap_predicate(p20/1, w1),
    ( predicate_property('$wrap$p20'(_), number_of_clauses(N0)) -> true ; N0 = none ),
    R = N1-N0.

% t21: a goal whose name is a blob that is NOT a closure (a clause reference): a type error, as an atom (call/1), as a compound
% (call/1) and as a compound with call/2's extra argument; only the error's type is recorded (the culprit's text is an address)
t21(R) :-
    assertz(z21(1), Ref),
    compound_name_arguments(G, Ref, [x]),
    catch(call(Ref), error(type_error(T1, _), _), true),
    catch(call(G), error(type_error(T2, _), _), true),
    catch(call(G, y), error(type_error(T3, _), _), true),
    erase(Ref),
    R = T1-T2-T3.

% k22 (not a `tN` row: the driver's list and the .out leave it out; test/core_lang/test_wrap_swipl.jl reads it in its kill rows, guarded):
% the frame S_CALLWRAPPER runs the wrapper clause in belongs to the WRAPPER's predicate, '$wrap$p22'/1 (user module: unqualified; the
% answer of swipl 10.1.20, single-shot: ['$wrap$p22'/1]). The wrapper's last goal is the closure, so the frame is the clause's own.
p22(1).
k22(R) :-
    wrap_predicate(p22(_), w22, W,
                   ( prolog_current_frame(F), prolog_frame_attribute(F, predicate_indicator, PI), lg(PI), W )),
    p22(_),
    logs(L),
    R = L.
