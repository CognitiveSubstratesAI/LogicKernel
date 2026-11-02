% LB4 b2 oracle for T1 (boot_image_predicates) and T3 (boot_image_source_files), run as
%   swipl -q -f none --no-packs -g lb4b2_main -t halt test_boot_image_swipl_rows.pl > test_boot_image_swipl_rows.out   (swipl 10.1.19-1-gcbf4e189,
%   2026-11-02, two runs byte-identical; the rows are a RESTORED boot state: load_count 2, from_state, file times are
%   the state's, so T3 compares neither)
% T1: one row per predicate DEFINED (not imported) in system or in a module whose file is a boot file (PLBASE/boot/).
% T3: one row per '$time_source_file'/3 answer of a boot file, in its order, with '$source_file_property'/3's columns.
lb4b2_bootdir(D) :- current_prolog_flag(home, H), atom_concat(H, '/boot/', D).
lb4b2_bootfile(F, R) :- lb4b2_bootdir(D), atom_concat(D, R, F).
lb4b2_module(system).
lb4b2_module(M) :- '$time_source_file'(F, _, _), lb4b2_bootfile(F, _), module_property(M, file(F)).   % current_module/1 skips system-class modules
lb4b2_flag(M, H, P, V) :- ( predicate_property(M:H, P) -> V = 1 ; V = 0 ).
lb4b2_t1(M) :-
    findall(N/A, ( current_predicate(_, M:H), \+ predicate_property(M:H, imported_from(_)), functor(H, N, A) ), PIs0),
    sort(PIs0, PIs),
    forall(member(N/A, PIs), lb4b2_t1_row(M, N, A)).
lb4b2_t1_row(M, N, A) :-
    functor(H, N, A),
    lb4b2_flag(M, H, dynamic, Y), lb4b2_flag(M, H, foreign, F), lb4b2_flag(M, H, system, L), lb4b2_flag(M, H, iso, I),
    lb4b2_flag(M, H, transparent, T), lb4b2_flag(M, H, meta_predicate(_), Me), lb4b2_flag(M, H, public, P),
    lb4b2_flag(M, H, exported, E),
    ( predicate_property(M:H, number_of_clauses(C)) -> true ; C = none ),
    atom_codes(M, MC), atom_codes(N, NC),
    format("t1 ~w ~w ~d ~w~w~w~w~w~w~w~w ~w~n", [MC, NC, A, Y, F, L, I, T, Me, P, E, C]).
lb4b2_t3 :-
    forall(( '$time_source_file'(F, _, Type), lb4b2_bootfile(F, R) ), lb4b2_t3_row(F, R, Type)).
lb4b2_t3_row(F, R, Type) :-
    '$source_file_property'(F, load_count, LC), '$source_file_property'(F, number_of_clauses, NC),
    '$source_file_property'(F, reloading, RL),
    findall(M, module_property(M, file(F)), Ms0), sort(Ms0, Ms),
    format("t3 ~w ~w ~d ~d ~w ~q~n", [R, Type, LC, NC, RL, Ms]).
lb4b2_main :-
    findall(M, lb4b2_module(M), Ms0), sort(Ms0, Ms),
    forall(member(M, Ms), lb4b2_t1(M)),
    lb4b2_t3.
