% ORIGINAL: the rows of test/core_lang/test_g1c_wiring_swipl.jl (G1-C's own program: the collector wired into the VM, pin 18168e62).
% test/core_lang/test_g1c_wiring_swipl.pl: the G1-C wiring rows (test_g1c_wiring_swipl.jl); the answers are swipl's (.out).
% w1: garbage_collect/0 succeeds (pl-gc.c:4583, GC_USER).
w1(R) :- garbage_collect, R = ok.
% w2: a long allocating loop past the initial global stack: the VM's ENSURE_GLOBAL_SPACE sites (pl-vmi.c:220-235) reach the collector
% when the stack is full; the unbound cells the head instructions bind live on the global stack (inside w/3), so a collection between a
% deref and its bind moves them (the onchange re-derives them).
w2(R) :- w2_loop(200000, 0, R).
w2_loop(0, A, A) :- !.
w2_loop(N, A0, A) :-
    w2_garb(N),
    T = w(X, Y, Z),
    w2_hf(N, X),
    w2_hl(N, Y),
    w2_hff(Z),
    arg(1, T, f(V, _)),
    Y = [V1|_],
    A1 is A0 + V + V1,
    N1 is N - 1,
    w2_loop(N1, A1, A).
w2_garb(N) :- G = g(N, N, N, N), arg(1, G, _).
w2_hf(N, f(N, g(N))).
w2_hl(N, [N, N]).
w2_hff([_|_]).
% w3: an exception caught after a deep recursion, then a collection: the ball's list and the answers are unchanged.
w3(R) :- catch(w3_rec(100000, []), ball(N, T), true), garbage_collect, length(T, Len), last(T, L), R = N-Len-L.
w3_rec(0, Acc) :- !, throw(ball(done, Acc)).
w3_rec(N, Acc) :- N1 is N - 1, w3_rec(N1, [N|Acc]), true.
% w4: the statistics keys of the collector: their shapes (the values are not deterministic).
w4(R) :-
    statistics(garbage_collection, G), length(G, NG), ( maplist(integer, G) -> IG = int ; IG = other ),
    statistics(stack_shifts, S), length(S, NS), ( maplist(integer, S) -> IS = int ; IS = other ),
    statistics(global_stack, GS), length(GS, NGS),
    R = [NG-IG, NS-IS, NGS].
% w5: garbage_collect/0 is counted by statistics(garbage_collection, [Count|_]); live data survives it.
w5(R) :-
    numlist(1, 1000, L),
    statistics(garbage_collection, [C0|_]),
    garbage_collect,
    statistics(garbage_collection, [C1|_]),
    sum_list(L, S),
    ( C1 > C0 -> D = counted ; D = not_counted ),
    R = D-S.
