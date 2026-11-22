fs(T, Cs) :- fast_term_serialized(T, S), string_codes(S, Cs).
p(T) :- fs(T, Cs), print(T), write(' -> '), print(Cs), nl.
:- initialization((
  p(f("abc")), p(f("")), p(f("\xe9\")), p(f("\x3b1\")), p(f("\x3b1\\x3b2\")), p(f("a\x3b1\b")),
  p(f(1r3)), p(f(-2r7)), p(f(100000000000000000000)), 
  X = g(a), p(f(1r3,X,X)), p(f(100000000000000000000,X,X)), p(f("abc",X,X)), p(f(1.5,X,X)), p(f(5,X,X)),
  p(f(4611686018427387904,X,X)), p(f(2**70, X, X)),
  halt)).
