% ORIGINAL: the rows of test/core_lang/test_zip1_swipl.jl (its predicates are pl-zip.c's: zip_open_stream/3, zip_clone/2, zip_close_/2,
% zip_lock/1, zip_unlock/1, zipper_goto/2, zipper_open_current/3, zip_file_info_/3; no zipper can be made in the kernel, so every row
% hands a term that is no zipper, or a bad option list, to a predicate: the answers are the pin's for such arguments).
% test/core_lang/test_zip1_swipl.pl - ZIP1's rows. Each `tN(R)` is one row; test_zip1_swipl.out holds swipl 10.1.20's answers (`ok`, then
% one line per row: its name and every solution), as the test's driver prints them. An error is caught inside the row and answered as
% err(Formal), a failure as the atom `failed`. A stream (a blob whose address changes from run to run) in an error's culprit is written
% as blob(Type). The rows `kN` (kernel-only) and `krN` (the named refusals) have no line in the .out.

err(G, R) :- catch(( G -> R = true ; R = failed ), error(E, _), ( norm(E, E1), R = err(E1) )).

norm(type_error(T, V), type_error(T, V1)) :- !, nb(V, V1).
norm(existence_error(T, V), existence_error(T, V1)) :- !, nb(V, V1).
norm(domain_error(T, V), domain_error(T, V1)) :- !, nb(V, V1).
norm(permission_error(A, T, V), permission_error(A, T, V1)) :- !, nb(V, V1).
norm(E, E).
nb(V, V1) :- ( \+ var(V), blob(V, B), B \== text -> V1 = blob(B) ; V1 = V ).


% the zipper argument first: zip_clone on an atom, a variable, a number, a compound, a string and a stream
t0(R) :- err(zip_clone(foo, _), R).
t1(R) :- err(zip_clone(_, _), R).
t2(R) :- err(zip_clone(1, _), R).
t3(R) :- err(zip_clone(f(x), _), R).
t4(R) :- err(zip_clone("s", _), R).
t5(R) :- err(( current_output(S), zip_clone(S, _) ), R).

% the zipper argument first: zip_close_ on an atom, a variable, a number, a compound, a string and a stream
t6(R) :- err(zip_close_(foo, comment), R).
t7(R) :- err(zip_close_(_, comment), R).
t8(R) :- err(zip_close_(1, comment), R).
t9(R) :- err(zip_close_(f(x), comment), R).
t10(R) :- err(zip_close_("s", comment), R).
t11(R) :- err(( current_output(S), zip_close_(S, comment) ), R).

% the zipper argument first: zip_lock on an atom, a variable, a number, a compound, a string and a stream
t12(R) :- err(zip_lock(foo), R).
t13(R) :- err(zip_lock(_), R).
t14(R) :- err(zip_lock(1), R).
t15(R) :- err(zip_lock(f(x)), R).
t16(R) :- err(zip_lock("s"), R).
t17(R) :- err(( current_output(S), zip_lock(S) ), R).

% the zipper argument first: zip_unlock on an atom, a variable, a number, a compound, a string and a stream
t18(R) :- err(zip_unlock(foo), R).
t19(R) :- err(zip_unlock(_), R).
t20(R) :- err(zip_unlock(1), R).
t21(R) :- err(zip_unlock(f(x)), R).
t22(R) :- err(zip_unlock("s"), R).
t23(R) :- err(( current_output(S), zip_unlock(S) ), R).

% the zipper argument first: zipper_goto on an atom, a variable, a number, a compound, a string and a stream
t24(R) :- err(zipper_goto(foo, first), R).
t25(R) :- err(zipper_goto(_, first), R).
t26(R) :- err(zipper_goto(1, first), R).
t27(R) :- err(zipper_goto(f(x), first), R).
t28(R) :- err(zipper_goto("s", first), R).
t29(R) :- err(( current_output(S), zipper_goto(S, first) ), R).

% the zipper argument first: zip_file_info_ on an atom, a variable, a number, a compound, a string and a stream
t30(R) :- err(zip_file_info_(foo, _, _), R).
t31(R) :- err(zip_file_info_(_, _, _), R).
t32(R) :- err(zip_file_info_(1, _, _), R).
t33(R) :- err(zip_file_info_(f(x), _, _), R).
t34(R) :- err(zip_file_info_("s", _, _), R).
t35(R) :- err(( current_output(S), zip_file_info_(S, _, _) ), R).

% zip_open_stream/3: the options come first, then the stream
t36(R) :- err(zip_open_stream(foo, _, []), R).
t37(R) :- err(zip_open_stream(_, _, []), R).
t38(R) :- err(zip_open_stream(1, _, []), R).
t39(R) :- err(( current_output(S), zip_open_stream(S, _, [close_parent(maybe)]) ), R).
t40(R) :- err(( current_output(S), zip_open_stream(S, _, notalist) ), R).
t41(R) :- err(( current_output(S), zip_open_stream(S, _, _) ), R).
t42(R) :- err(zip_open_stream(foo, _, [close_parent(maybe)]), R).
t43(R) :- err(zip_open_stream(foo, _, notalist), R).
t44(R) :- err(zip_open_stream(foo, _, [close_parent(true)]), R).
t45(R) :- err(zip_open_stream(foo, _, [close_parent(_)]), R).
t46(R) :- err(zip_open_stream(f(x), _, []), R).
t47(R) :- err(zip_open_stream(foo, _, [bar|_]), R).

% zipper_open_current/3: the options (type, encoding, bom, release, reposition), then the zipper
t48(R) :- err(zipper_open_current(foo, _, [type(bar)]), R).
t49(R) :- err(zipper_open_current(foo, _, [encoding(nosuch)]), R).
t50(R) :- err(zipper_open_current(foo, _, [type(binary), encoding(utf8)]), R).
t51(R) :- err(zipper_open_current(foo, _, [type(bar), encoding(utf8)]), R).
t52(R) :- err(zipper_open_current(foo, _, [bom(maybe)]), R).
t53(R) :- err(zipper_open_current(foo, _, [foo(bar)]), R).
t54(R) :- err(zipper_open_current(foo, _, notalist), R).
t55(R) :- err(zipper_open_current(foo, _, _), R).
t56(R) :- err(zipper_open_current(foo, _, []), R).
t57(R) :- err(zipper_open_current(_, _, []), R).
t58(R) :- err(zipper_open_current(foo, _, [type(text), encoding(utf8)]), R).
t59(R) :- err(zipper_open_current(foo, _, [type(text), bom(true)]), R).
t60(R) :- err(zipper_open_current(foo, _, [type(binary), bom(true)]), R).
t61(R) :- err(zipper_open_current(foo, _, [release(maybe)]), R).
t62(R) :- err(zipper_open_current(foo, _, [reposition(maybe)]), R).
t63(R) :- err(zipper_open_current(foo, _, [encoding(1)]), R).
t64(R) :- err(zipper_open_current(foo, _, [type(1)]), R).
t65(R) :- err(zipper_open_current(foo, _, [type(_)]), R).
t66(R) :- err(zipper_open_current(foo, _, [type(text)]), R).
t67(R) :- err(zipper_open_current(foo, _, [encoding(octet)]), R).
t68(R) :- err(zipper_open_current(foo, _, [encoding(text)]), R).
t69(R) :- err(( current_output(S), zipper_open_current(S, _, []) ), R).
t70(R) :- err(zipper_open_current(foo, _, [encoding(utf8)]), R).

% KERNEL-ONLY rows (no row in the .out): '$rc_handle'/1 fails here, the kernel opens no resource database; swipl 10.1.20 (the pin) SUCCEEDS
% with the zipper blob of its boot archive (`'$rc_handle'(H), blob(H, zipper)` is true).
k0(R) :- err('$rc_handle'(_), R).
k1(R) :- ( '$rc_handle'(_) -> R = yes ; R = no ).

% kernel-only: no zipper can be made, so what reaches minizip is a named refusal (each row ends in NotPortedError, step ZIP1). The pin's
% answer on the same goal is in each comment (a single-shot query of swipl 10.1.20).
% zip_open_stream/3 on a stream: the pin makes a zipper writer on an output stream (`current_output(S), zip_open_stream(S, Z, [])`
% succeeds, `blob(Z, zipper)`); an input stream is an upstream fault there (18168e62), so its answer is not pinned.
kr0(R) :- current_output(S), zip_open_stream(S, _, []), R = x.
kr1(R) :- current_input(S), zip_open_stream(S, _, []), R = x.
kr2(R) :- current_output(S), zip_open_stream(S, _, [close_parent(false)]), R = x.
% zipper_open_new_file_in_zip/4 refuses before the zipper is read. The pin: type_error(zipper, foo), instantiation_error for an unbound
% zipper, domain_error(zip_level, 0) for [level(0)], domain_error(zip_method, bar) for [method(bar)].
kr3(R) :- zipper_open_new_file_in_zip(foo, n, _, []), R = x.
kr4(R) :- zipper_open_new_file_in_zip(_, _, _, []), R = x.
kr5(R) :- zipper_open_new_file_in_zip(foo, n, _, [level(0)]), R = x.
kr6(R) :- zipper_open_new_file_in_zip(foo, n, _, [method(bar)]), R = x.
