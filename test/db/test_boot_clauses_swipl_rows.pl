% LB4 b2 driver for T2 (the booted clauses, loader_boot design §6 T2): ONE Prolog text that runs on both sides and
% prints a HASH per static Prolog predicate (a full-text fixture would be ~1.3 MB: 3432 clauses, ~380 bytes a line).
% The oracle is swipl's OWN BOOT FROM SOURCE, the command src/CMakeLists.txt:357-361 runs, with this file and a
% one-line main file as further files to compile (pl-qlf.c:4784-4806 compileFileList), WITHOUT `-O`:
%   printf ':- lb4b2c_main.\n' > SCRATCH/main.pl
%   swipl --home=PLBASE -q -o SCRATCH/boot.prc -b PLBASE/boot/init.pl test_boot_clauses_swipl_rows.pl SCRATCH/main.pl \
%     > test_boot_clauses_swipl_rows.out
% (swipl 10.1.19-1-gcbf4e189, 2026-11-02, two runs byte-identical, stderr empty). `-O` is left out because the
% kernel's boot does not apply it (src/pl-qlf.jl boot_global_data: `optimise` stays false, handoff flag F3), and
% `optimise` changes clause bodies (expand.pl:1368-1370 simplify/4, init.pl:4118): the pin is for the kernel's
% current configuration. The boot runs with autoload false (pl-qlf.c:4797) and an undefined predicate is fatal
% there, so this file calls boot and C predicates only (its own member/2, append/3, length/2).
% The kernel loads this file into `user` after its boot (load_file!) and enumerates lb4b2c_row/6 (the test file).
% A row: `t2 MODULE NAME ARITY NCLAUSES HASH` (MODULE and NAME as code lists, as T1's rows), one per predicate DEFINED
% (not imported) in a module of the list that is neither foreign nor dynamic (dynamic = boot state with this
% machine's paths; T1 counts their clauses). NCLAUSES is -1 where clause/2 raises.
% HASH folds H = (H*257 + C) mod 2147483647 over the codes of each clause's encoding, the code 10 between clauses.
% The encoding of a clause (H :- B): variables numbered by first occurrence (so equal text <=> =@=), every atom,
% string and functor name as its code list with a tag, a number as number_codes/2 writes it; a functor name that is
% not an atom (a dict's C'dict', pl-dict.c) as format/3's ~w text with the tag `r`.
lb4b2c_enc(T, Cs) :- lb4b2c_enc(T, [], _, Cs, []).
lb4b2c_enc(V, S0, S, Cs, T) :- var(V), !,
    ( lb4b2c_vidx(S0, V, 0, I) -> S = S0 ; lb4b2c_len(S0, 0, I), lb4b2c_app(S0, [V], S) ),
    number_codes(I, IC), Cs = [0'V|C1], lb4b2c_app(IC, T, C1).
lb4b2c_enc(X, S, S, [0'n|T], T) :- X == [], !.
lb4b2c_enc(X, S, S, Cs, T) :- atom(X), !, atom_codes(X, AC), lb4b2c_codes(0'a, AC, Cs, T).
lb4b2c_enc(X, S, S, Cs, T) :- string(X), !, string_codes(X, SC), lb4b2c_codes(0's, SC, Cs, T).
lb4b2c_enc(X, S, S, Cs, T) :- number(X), !, number_codes(X, NC), Cs = [0'#|C1], lb4b2c_app(NC, T, C1).
lb4b2c_enc(X, S, S, Cs, T) :- \+ compound(X), !, format(codes(RC), "~w", [X]), lb4b2c_codes(0'r, RC, Cs, T).
lb4b2c_enc(X, S0, S, Cs, T) :- compound_name_arity(X, N, A),
    ( atom(N) -> atom_codes(N, NC), Tag = 0'c ; format(codes(NC), "~w", [N]), Tag = 0'r ),
    lb4b2c_codes(Tag, NC, Cs, C1),
    number_codes(A, AC), C1 = [0'/|C2], lb4b2c_app(AC, [0'(|C3], C2), lb4b2c_args(1, A, X, S0, S, C3, [0')|T]).
lb4b2c_args(I, A, _, S, S, T, T) :- I > A, !.
lb4b2c_args(I, A, X, S0, S, Cs, T) :- arg(I, X, Y), lb4b2c_enc(Y, S0, S1, Cs, C1),
    ( I < A -> C1 = [0',|C2] ; C2 = C1 ), I1 is I+1, lb4b2c_args(I1, A, X, S1, S, C2, T).
lb4b2c_codes(Tag, Codes, [Tag, 0'[|Cs], T) :- lb4b2c_numlist(Codes, Cs, [0']|T]).
lb4b2c_numlist([], T, T).
lb4b2c_numlist([C|Cs], Out, T) :- number_codes(C, NC), lb4b2c_app(NC, R, Out),
    ( Cs == [] -> R = R1 ; R = [0',|R1] ), lb4b2c_numlist(Cs, R1, T).
lb4b2c_vidx([X|_], V, I, I) :- X == V, !.
lb4b2c_vidx([_|Xs], V, I0, I) :- I1 is I0+1, lb4b2c_vidx(Xs, V, I1, I).
lb4b2c_len([], N, N).
lb4b2c_len([_|T], N0, N) :- N1 is N0+1, lb4b2c_len(T, N1, N).
lb4b2c_app([], L, L).
lb4b2c_app([H|T], L, [H|R]) :- lb4b2c_app(T, L, R).
lb4b2c_member(X, [X|_]).
lb4b2c_member(X, [_|T]) :- lb4b2c_member(X, T).
lb4b2c_fold([], H, H).
lb4b2c_fold([C|Cs], H0, H) :- H1 is (H0*257 + C) mod 2147483647, lb4b2c_fold(Cs, H1, H).
lb4b2c_hash([], H, H).
lb4b2c_hash([Cs|Css], H0, H) :- lb4b2c_fold(Cs, H0, H1),
    ( Css == [] -> H2 = H1 ; H2 is (H1*257 + 10) mod 2147483647 ), lb4b2c_hash(Css, H2, H).
% one row per static Prolog predicate DEFINED in a module of Ms, predicates sorted by Name/Arity
lb4b2c_row(Ms, M, N, A, NC, H) :-
    lb4b2c_member(M, Ms),
    findall(N0/A0, ( current_predicate(_, M:H0), \+ predicate_property(M:H0, imported_from(_)),
                     \+ predicate_property(M:H0, foreign), \+ predicate_property(M:H0, dynamic),
                     functor(H0, N0, A0) ), PIs0),
    sort(PIs0, PIs), lb4b2c_member(N/A, PIs), functor(Hd, N, A),
    catch(( findall(Cs, ( clause(M:Hd, B), lb4b2c_enc((Hd :- B), Cs) ), Css), lb4b2c_len(Css, 0, NC),
            lb4b2c_hash(Css, 0, H) ),
          _, ( NC = -1, H = 0 )).
% swipl's side: the modules of T1 (test_boot_image_swipl_rows.pl:13-16), system and every module of a boot file
lb4b2c_bootdir(D) :- current_prolog_flag(home, H), atom_concat(H, '/boot/', D).
lb4b2c_module(system).
lb4b2c_module(M) :- '$time_source_file'(F, _, _), lb4b2c_bootdir(D), atom_concat(D, _, F), module_property(M, file(F)).
lb4b2c_main :-
    findall(M, lb4b2c_module(M), Ms0), sort(Ms0, Ms),
    forall(lb4b2c_row(Ms, M, N, A, NC, H),
           ( atom_codes(M, MC), atom_codes(N, NN), format("t2 ~w ~w ~d ~d ~d~n", [MC, NN, A, NC, H]) )).
