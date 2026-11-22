fs(T, Cs) :- fast_term_serialized(T, S), string_codes(S, Cs).
p(T) :- fs(T, Cs), print(T), write(' -> '), print(Cs), nl.
q(E) :- N is E, X = g(a), fs(f(N,X,X), Cs), print(E), write(' -> '), print(Cs), nl.
:- initialization((
  forall(member(E, [2**56-1, 2**56, -(2**56), -(2**56)-1, 2**57, 2**60, 2**62, 2**63-1, -(2**63), 2**63, 2**64, -(2**64), 2**200, 2**31, 2**32, 2**55, 2**58]), q(E)),
  forall(member(E, [2**56-1, 2**56, 2**62, 2**63-1, -(2**63), 2**63]), (N is E, fs(N, C), print(E-C), nl)),
  halt)).
