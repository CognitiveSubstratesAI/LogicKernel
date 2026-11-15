% ORIGINAL: the rows of test/files/test_expand_user_swipl.jl - no swipl-devel counterpart.
% test/files/test_expand_user_swipl.pl - `~user` in the file-name expansion of expand_file_name/2 and of the file predicates under the
% file_name_variables flag (pl-os.c expandVars, the getpwnam branch, :1578-1600). Each `tN(R)` is one row, run in order. Answers:
% yes(Value) | no | ex(Formal) | ball(Ball). Pinned from swipl 10.1.20 (the pin's build). The user that exists is `root` (home /root:
% Linux, and CI is ubuntu-24.04 only), the user that does not exist is `nosuchuserxyz`. A row that changes a flag puts it back.
% UNVERIFIED on the kernel: gate decides
res(G, R) :- catch(( G -> R = yes ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
ans(G, V, R) :- catch(( G -> R = yes(V) ; R = no ), E, ( E = error(F, _) -> R = ex(F) ; R = ball(E) )).
eu(A, R) :- ans(expand_file_name(A, [X]), X, R).
withflag(F, V, G, R) :- current_prolog_flag(F, Old), set_prolog_flag(F, V), res(G, R0), set_prolog_flag(F, Old), R = R0.
withflag2(F1, V1, F2, V2, G, R) :- current_prolog_flag(F1, O1), current_prolog_flag(F2, O2), set_prolog_flag(F1, V1), set_prolog_flag(F2, V2),
    res(G, R0), set_prolog_flag(F1, O1), set_prolog_flag(F2, O2), R = R0.
t1(R) :- eu('~root', R).
t2(R) :- eu('~root/x', R).
t3(R) :- eu('~root//x', R).
t4(R) :- eu('~root/a/b', R).
t5(R) :- eu('~nosuchuserxyz', R).
t6(R) :- eu('~nosuchuserxyz/a', R).
t7(R) :- ans(( expand_file_name('~root', _), expand_file_name('~root', [X]) ), X, R).
t8(R) :- ans(( expand_file_name('~root', _), catch(expand_file_name('~nosuchuserxyz', _), _, true), expand_file_name('~root/y', [X]) ), X, R).
t9(R) :- withflag(fileerrors, false, expand_file_name('~nosuchuserxyz', _), R).
t10(R) :- withflag(fileerrors, false, expand_file_name('~nosuchuserxyz/a', _), R).
t11(R) :- withflag(file_name_variables, true, exists_directory('~root'), R).
t12(R) :- withflag(file_name_variables, true, exists_directory('~nosuchuserxyz'), R).
t13(R) :- withflag2(file_name_variables, true, fileerrors, false, exists_directory('~nosuchuserxyz'), R).
t14(R) :- res(exists_directory('~root'), R).
t15(R) :- withflag(file_name_variables, true, exists_directory('~root/'), R).
