% ORIGINAL: the rows of test/core_lang/test_misc1_swipl.jl (its predicates: '$notrace'/1 of pl-pro.c, '$needs_quotes'/1 of pl-write.c,
% '$local_definitions'/2 and '$addr2line'/2 of pl-proc.c, and malloc_property/1 of pl-alloc.c).
% test/core_lang/test_misc1_swipl.pl - MISC-1's rows. Each `tN(R)` is one row (a family of cases); test_misc1_swipl.out holds
% swipl 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every
% solution). Rows t0-t3 are '$needs_quotes'/1, t4-t8 '$notrace'/1, t9-t12 '$local_definitions'/2, t13 and t15 '$addr2line'/2,
% t14 malloc_property/1. Every row runs on both sides. Characters above 0x7F are written as escapes, so the file is the same
% in every encoding.

% -- '$needs_quotes'/1 -----------------------------------------------------------------------------------------------

nq_atom(abc).
nq_atom('Abc').
nq_atom('_x').
nq_atom('a b').
nq_atom('').
nq_atom(a1).
nq_atom('aB').
nq_atom(a_b).
nq_atom('1a').
nq_atom('+').
nq_atom('+-').
nq_atom('*').
nq_atom('=..').
nq_atom('\\').
nq_atom(';').
nq_atom('!').
nq_atom(',').
nq_atom('|').
nq_atom('{}').
nq_atom('[]').
nq_atom('.').
nq_atom('a.b').
nq_atom('a\nb').
nq_atom('caf\xe9\').
nq_atom('\xdc\n\xef\').
nq_atom('w\x20ac\bc').
nq_atom('\x20ac\').
nq_atom('\x3b1\').
nq_atom('\x391\').
nq_atom('\x4e2d\').
nq_atom(dynamic).
nq_atom(is).
nq_atom(mod).
nq_atom('$a').
nq_atom('a$').
nq_atom('/*').
nq_atom('%').
nq_atom('a\\b').
nq_atom('it''s').

nq_bad(1).
nq_bad(1.5).
nq_bad("s").
nq_bad(f(x)).
nq_bad([a]).
nq_bad(_).
nq_bad(a-b).
nq_bad(12345678901234567890123).

% every atom of the list: q when '$needs_quotes'/1 holds, u when it fails
t0(R) :- nq_atom(A), ( '$needs_quotes'(A) -> Q = q ; Q = u ), R = A-Q.

% the reserved symbol [] and the atom '[]' are two atoms
t1(R) :- member(A, [[], '[]']), ( '$needs_quotes'(A) -> Q = q ; Q = u ), R = A-Q.

% a non-atom: the formal part of the error, or true/false when the call answers
t2(R) :- nq_bad(T), catch(( '$needs_quotes'(T) -> S = true ; S = false ), error(F, _), S = F), R = S.

% '$needs_quotes'/1 and writeq/1 agree on every atom: q when the written form starts with a quote
t3(R) :-
    nq_atom(A), ( '$needs_quotes'(A) -> Q = q ; Q = u ),
    with_output_to(string(S), writeq(A)),
    ( sub_string(S, 0, 1, _, "'") -> W = q ; W = u ),
    R = A-Q-W.

% -- '$notrace'/1 ----------------------------------------------------------------------------------------------------

nt_helper(1).
nt_helper(2).

nt_goal(true).
nt_goal(fail).
nt_goal(_ = f(_)).
nt_goal(member(_, [a, b, c])).
nt_goal(( X = 1 ; X = 2 )).
nt_goal(( member(X, [a, b]), X == b )).
nt_goal(( member(X, [a, b]), ! )).
nt_goal(\+ fail).
nt_goal(call(atom_length, abc, _)).
nt_goal(( Y = g(Z), Z = 2 )).
nt_goal(nt_helper(_)).

% the goal runs once, its bindings kept, a failure fails
t4(R) :- nt_goal(G), findall(G, '$notrace'(G), Gs), R = Gs.

nt_ex(throw(foo)).
nt_ex(throw(error(my_err, my_ctx))).
nt_ex(atom_length(_, _)).
nt_ex(1).
nt_ex(_).
nt_ex(no_such_pred_zz).
nt_ex(( true ; throw(late) )).
nt_ex(( fail, 1 )).
nt_ex(nt_helper(2)).
nt_ex(nt_helper(3)).

% an exception is passed on: the formal part of an error(_, _), else the ball
t5(R) :-
    nt_ex(G),
    catch(( '$notrace'(G) -> S = succeeded ; S = failed ),
          B,
          ( B = error(F, _) -> S = ex(F) ; S = ex(B) )),
    R = S.

:- assertz(ntm:ntp(7)).
:- assertz(ntm2:ntp2(8)).

% the call is transparent: the goal runs in the context module of the caller
t6(R) :-
    ntm:'$notrace'(context_module(M1)),
    ntm:'$notrace'(ntp(X)),
    '$notrace'(ntm:ntp(Y)),
    catch(ntm:'$notrace'(ntp2(_)), error(F, _), true),
    '$notrace'(context_module(M2)),
    R = [M1, X, Y, F, M2].

% the debugging status: off inside the goal, back after it, also after an exception
t7(R) :-
    set_prolog_flag(debug, true),
    current_prolog_flag(debug, D0),
    '$notrace'(current_prolog_flag(debug, D1)),
    current_prolog_flag(debug, D2),
    catch('$notrace'(throw(x)), x, true),
    current_prolog_flag(debug, D3),
    ( '$notrace'(fail) -> true ; true ),
    current_prolog_flag(debug, D4),
    set_prolog_flag(debug, false),
    '$notrace'(current_prolog_flag(debug, D5)),
    current_prolog_flag(debug, D6),
    R = [D0, D1, D2, D3, D4, D5, D6].

% the saved state of '$notrace'/2 inside and outside '$notrace'/1: the debug bit (2) and the skip level
t8(R) :-
    set_prolog_flag(debug, true),
    '$notrace'(F1, S1), '$restore_trace'(F1, S1),
    '$notrace'(( '$notrace'(F2, S2), '$restore_trace'(F2, S2) )),
    '$notrace'(F3, S3), '$restore_trace'(F3, S3),
    set_prolog_flag(debug, false),
    B1 is F1 /\ 2, B2 is F2 /\ 2, B3 is F3 /\ 2,
    ( S1 == S2 -> E12 = same ; E12 = differs ),
    ( S2 == S3 -> E23 = same ; E23 = differs ),
    R = [B1, B2, B3, E12, E23].

% -- '$local_definitions'/2 --------------------------------------------------------------------------------------

:- thread_local ldp/1.
:- thread_local ldq/1.
:- thread_local lm:ldp2/1.
:- dynamic ldd/1.

ldstatic(1).

ld_list(H, L) :- ( '$local_definitions'(H, L) -> true ; L = failed ).

% the count of clauses of the thread-local predicate: [] while none, [main-N] after N assertions
t9(R) :-
    ld_list(ldp(_), L0),
    assertz(ldp(1)), assertz(ldp(2)), ld_list(ldp(_), L1),
    retract(ldp(1)), ld_list(ldp(_), L2),
    assertz(ldp(3)), ld_list(ldp(_), L3),
    retractall(ldp(_)), ld_list(ldp(_), L4),
    R = [L0, L1, L2, L3, L4].

% a static or a dynamic predicate, an undefined one, a term that is no head: the call fails
t10(R) :-
    member(H, [ldstatic(_), ldd(_), no_such_ld(_), 1, _, "s", ldp, 1.5, [a]]),
    ld_list(H, L),
    R = L.

% a bound second argument is unified with the list
t11(R) :-
    assertz(ldq(1)),
    ( '$local_definitions'(ldq(_), [main-1]) -> A = yes ; A = no ),
    ( '$local_definitions'(ldq(_), [other-1]) -> B = yes ; B = no ),
    ( '$local_definitions'(ldq(_), []) -> C = yes ; C = no ),
    ( '$local_definitions'(ldq(_), [main-N]) -> D = N ; D = no ),
    ( '$local_definitions'(ldq(_), [_|T]) -> E = T ; E = no ),
    ( '$local_definitions'(ldq(_), L) -> F = L ; F = no ),
    retractall(ldq(_)),
    R = [A, B, C, D, E, F].

% the module of the head: qualified, or the context module of the call
t12(R) :-
    assertz(lm:ldp2(1)), assertz(lm:ldp2(2)),
    ( '$local_definitions'(lm:ldp2(_), L1) -> true ; L1 = failed ),
    ( lm:'$local_definitions'(ldp2(_), L2) -> true ; L2 = failed ),
    ( '$local_definitions'(ldp2(_), L3) -> true ; L3 = failed ),
    retractall(lm:ldp2(_)),
    ( lm:'$local_definitions'(ldp2(_), L4) -> true ; L4 = failed ),
    R = [L1, L2, L3, L4].

% -- '$addr2line'/2 ------------------------------------------------------------------------------------------------

% the address must be a size_t: the formal part of the error
t13(R) :-
    member(A, [a, -1, _, 1.5, f(x), "s", 123456789012345678901234567890]),
    catch(( '$addr2line'(A, _) -> S = true ; S = false ), error(F, _), S = F),
    R = S.

% -- malloc_property/1 -------------------------------------------------------------------------------------------

% pl-alloc.c registers malloc_property/1 under tcmalloc only (initTCMalloc); the pin's allocator is ptmalloc, so the call raises existence_error(procedure, malloc_property/1), which the kernel raises as well
t14(R) :-
    catch(( malloc_property(_) -> S = true ; S = false ), error(F, _), S = F),
    R = S.

% a valid address: the call fails silently (the description of a C function address is read in a debug build only)
t15(R) :-
    member(A, [0, 1, 4096, 123456789]),
    ( '$addr2line'(A, _) -> S = true ; S = false ),
    R = A-S.
