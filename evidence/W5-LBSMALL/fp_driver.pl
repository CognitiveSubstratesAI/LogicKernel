pr(T) :- write_term(T, [quoted(false), ignore_ops(true)]).
run(N) :- atom_concat(t, N, Name), G =.. [Name, R], format("~w ", [Name]),
    ( catch(findall(R, G, Rs), _, Rs = [exception]) -> true ; Rs = [none] ),
    forall(member(X, Rs), (pr(X), write(' '))), nl.
