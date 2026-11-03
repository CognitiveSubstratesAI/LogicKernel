% LB4 b2 oracle for T1 (boot_image_predicates) and T3 (boot_image_source_files): swipl's OWN BOOT FROM SOURCE, the
% command src/CMakeLists.txt:357-361 runs, with this file as a second file to compile (pl-qlf.c:4784-4806
% compileFileList compiles every file of the list in turn; this file's last directive prints the rows at the point
% where the boot's files are all loaded, before `'$load_additional_boot_files'`, which loads nothing without `-c`,
% init.pl:4782-4790):
%   swipl --home=PLBASE -q -O -o SCRATCH/boot.prc -b PLBASE/boot/init.pl test_boot_image_swipl_rows.pl > test_boot_image_swipl_rows.out
% (swipl 10.1.19-1-gcbf4e189, 2026-11-02; regenerated 2026-11-03 after the `locked` column's fix, two runs
% byte-identical, stderr empty). The boot runs with autoload false
% (pl-qlf.c:4797) and an undefined predicate is fatal there, so this file calls boot predicates only (its own member/2).
% The rows are read inside this file's directive: `'$directive_mode_store'/1` holds one clause then (init.pl:1741-1743).
% T1: one row per predicate DEFINED (not imported) in system or in a module whose file is a boot file (PLBASE/boot/).
% T3: one row per '$time_source_file'/3 answer of a boot file, in its order, with '$source_file_property'/3's columns
%   (load_count, number_of_clauses, reloading, from_state) and the sorted modules whose file it is.
lb4b2_bootdir(D) :- current_prolog_flag(home, H), atom_concat(H, '/boot/', D).
lb4b2_bootfile(F, R) :- lb4b2_bootdir(D), atom_concat(D, R, F).
lb4b2_module(system).
lb4b2_module(M) :- '$time_source_file'(F, _, _), lb4b2_bootfile(F, _), module_property(M, file(F)).   % current_module/1 skips system-class modules
lb4b2_flag(M, H, P, V) :- ( predicate_property(M:H, P) -> V = 1 ; V = 0 ).
% the `locked` column reads the predicate's P_LOCKED attribute itself (pl-proc.c:3472-3473, `system` an alias of
% `locked`): syspred.pl's '$predicate_property'/2 (822-907) defines no `system` property, so predicate_property(_,
% system) fails for every predicate (it is `built_in` there, syspred.pl:826-827); the first .out read 0 in every row.
lb4b2_locked(M, H, V) :- ( '$get_predicate_attribute'(M:H, system, 1) -> V = 1 ; V = 0 ).
lb4b2_t1(M) :-
    findall(N/A, ( current_predicate(_, M:H), \+ predicate_property(M:H, imported_from(_)), functor(H, N, A) ), PIs0),
    sort(PIs0, PIs),
    forall(lb4b2_member(N/A, PIs), lb4b2_t1_row(M, N, A)).
lb4b2_t1_row(M, N, A) :-
    functor(H, N, A),
    lb4b2_flag(M, H, dynamic, Y), lb4b2_flag(M, H, foreign, F), lb4b2_locked(M, H, L), lb4b2_flag(M, H, iso, I),
    lb4b2_flag(M, H, transparent, T), lb4b2_flag(M, H, meta_predicate(_), Me), lb4b2_flag(M, H, public, P),
    lb4b2_flag(M, H, exported, E),
    ( predicate_property(M:H, number_of_clauses(C)) -> true ; C = none ),
    atom_codes(M, MC), atom_codes(N, NC),
    format("t1 ~w ~w ~d ~w~w~w~w~w~w~w~w ~w~n", [MC, NC, A, Y, F, L, I, T, Me, P, E, C]).
lb4b2_t3 :-
    forall(( '$time_source_file'(F, _, Type), lb4b2_bootfile(F, R) ), lb4b2_t3_row(F, R, Type)).
lb4b2_t3_row(F, R, Type) :-
    '$source_file_property'(F, load_count, LC), '$source_file_property'(F, number_of_clauses, NC),
    '$source_file_property'(F, reloading, RL), '$source_file_property'(F, from_state, FS),
    findall(M, module_property(M, file(F)), Ms0), sort(Ms0, Ms),
    format("t3 ~w ~w ~d ~d ~w ~w ~q~n", [R, Type, LC, NC, RL, FS, Ms]).
lb4b2_main :-
    findall(M, lb4b2_module(M), Ms0), sort(Ms0, Ms),
    forall(lb4b2_member(M, Ms), lb4b2_t1(M)),
    lb4b2_t3.
lb4b2_member(X, [X|_]).
lb4b2_member(X, [_|T]) :- lb4b2_member(X, T).
:- lb4b2_main.
