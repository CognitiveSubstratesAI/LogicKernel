% ORIGINAL: the swipl side of test_read_positions_swipl.jl (LB1: term positions in the reader,
% read_clause/3 registered) -- no swipl-devel counterpart. The Julia file generates the calls and
% runs this driver with `swipl -q -g <goal> -t halt test_read_positions_swipl.pl`; every answer it
% compares comes from here, never written by hand.
%
%   pa(Codes)          read_term_from_atom/3 of the text with term_position(TP) and
%                      subterm_positions(P): `TP-P` encoded, `fails`, or `err <ball>`
%   rc(Codes, Opts)    read_clause/3 on open_string/2 of the text, clause after clause up to
%                      end_of_file: one line `Clause-Opts` each (or `fails` / `err <ball>`),
%                      then a line `.`
%   re(Goal)           any goal: the goal after it succeeded, `fails`, or `err <ball>`
%   gen_texts(N)       N random terms over SWI-7's default operators, written by writeq/1,
%                      one line of codes each (the operator-term generator of
%                      test_read_term_swipl.jl, seeded the same way)
%
% The encoding is test_read_term_swipl.jl's `enc/1`: `V<n>` the n-th variable by first
% occurrence, `nil` for [], `a[codes]` an atom, `s[codes]` a string, `i<n>`, `q<n>r<d>`,
% `f<float>`, `c[codes]/<arity>(args)` (`c[]` for a compound named []).

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

pa(Cs) :-
    atom_codes(A, Cs),
    catch(( read_term_from_atom(A, _, [term_position(TP), subterm_positions(P)])
          -> enc(TP-P)
          ;  write(fails)
          ),
          E, (write('err '), enc(E))),
    nl.

rc(Cs, Opts0) :-
    string_codes(S, Cs),
    open_string(S, In),
    catch(rc_loop(In, Opts0, 0), E, (write('err '), enc(E), nl)),
    close(In),
    write('.'), nl.

rc_loop(In, Opts0, N) :-
    copy_term(Opts0, Opts),
    (   read_clause(In, T, Opts)
    ->  enc(T-Opts), nl,
        (   T == end_of_file
        ->  true
        ;   N < 50
        ->  N1 is N+1,
            rc_loop(In, Opts0, N1)
        ;   true
        )
    ;   write(fails), nl
    ).

re(G0) :-
    copy_term(G0, G),
    catch(( call(G) -> enc(G) ; write(fails) ), E, (write('err '), enc(E))),
    nl.

bin([+,-,*,/,//,^,**,=,\=,==,\==,@<,@>,=..,is,<,>,=<,>=,=:=,=\=,:-,-->,',',;,'|',->,'*->',:,mod,rem,xor,>>,<<,/\,\/,rdiv,div,as,>:<,:<,?=,:=]).
pre([-,+,\,\+,?-,:-,dynamic,discontiguous,initialization,meta_predicate,multifile,public,table]).
leaf(L) :- random_member(L, [a, b, 'A', [], '[]', {}, 1, -1, 0, -0.0, 1.5, "s", 1r3, f(a), [a,b], [a|b], {a}, -, +, ',', '|', :-, \+, *, ^, dynamic, 'a b']).
gen(0, T, Vs) :- !, ( random(0, 4, 0) -> random_member(T, Vs) ; leaf(T) ).
gen(D, T, Vs) :- D1 is D-1, random(0, 7, K), gen(K, D1, T, Vs).
gen(0, D, T, Vs) :- bin(Os), random_member(O, Os), gen(D, A, Vs), gen(D, B, Vs), T =.. [O, A, B].
gen(1, D, T, Vs) :- pre(Os), random_member(O, Os), gen(D, A, Vs), T =.. [O, A].
gen(2, D, f(A, B), Vs) :- gen(D, A, Vs), gen(D, B, Vs).
gen(3, D, [A, B|C], Vs) :- gen(D, A, Vs), gen(D, B, Vs), gen(D, C, Vs).
gen(4, D, {A}, Vs) :- gen(D, A, Vs).
gen(5, D, -(A), Vs) :- gen(D, A, Vs).
gen(6, _, T, Vs) :- gen(0, T, Vs).
one :- Vs = [_, _, _], gen(4, T, Vs), with_output_to(codes(Cs), writeq(T)), format("~w~n", [Cs]).
gen_texts(N) :- set_random(seed(20261025)), forall(between(1, N, _), one).
