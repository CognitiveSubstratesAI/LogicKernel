% test/core_lang/test_prolog_flag_swipl.pl -- the rows of test_prolog_flag_swipl.jl (R2 F1a: current_prolog_flag/2 and
% '$current_prolog_flag'/5, the read side of pl-prologflag.c). The kernel and swipl 10.1.19 consult THIS FILE and enumerate every
% solution of every t_<id>/1; the answers are compared as lines. test_prolog_flag_swipl.out is swipl's output for it, kept beside it.
%
% Nothing here is an expected value: a row is a QUESTION, and the answer is swipl's. The hand-written parts are the questions and,
% for the float flags, the reference constants a float is compared with (a float's text differs between the two systems; the
% verdict `eq`/`ne` is each system's own).
%
% fk/1 are the flags the kernel defines whose value does not depend on the machine or on how swipl was started; mk/1 the ones that do
% (their TYPE and access are compared; `verbose` is `normal` in the kernel and `silent` in the oracle, which is started with -q). `threads` and `gc_thread` are the two known differences (no threads in the kernel:
% design D1) and are in neither; they are pinned in the .jl.

fk(access_level).
fk(agc_close_streams).
fk(agc_margin).
fk(allow_dot_in_atom).
fk(allow_variable_name_as_functor).
fk(atom_normalize_hook).
fk(autoload).
fk(back_quotes).
fk(bounded).
fk(char_conversion).
fk(character_escapes).
fk(character_escapes_unicode).
fk(ci_max_lookahead).
fk(ci_max_var_fraction).
fk(ci_min_clauses).
fk(ci_min_speedup).
fk(ci_min_speedup_ratio).
fk(colon_sets_calling_context).
fk(debug).
fk(debug_on_error).
fk(debug_on_interrupt).
fk(debugger_show_context).
fk(determinism_error).
fk(dialect).
fk(dir_sep).
fk(double_quotes).
fk(editor).
fk(epilog).
fk(error_ambiguous_stream_pair).
fk(file_name_variables).
fk(fileerrors).
fk(float_max).
fk(float_max_integer).
fk(float_min).
fk(float_overflow).
fk(float_rounding).
fk(float_undefined).
fk(float_underflow).
fk(float_zero_div).
fk(gc).
fk(generate_debug_info).
fk(halt_grace_time).
fk(heartbeat).
fk(incomparable).
fk(integer_rounding_function).
fk(iso).
fk(large_files).
fk(last_call_optimisation).
fk(linux).
fk(max_answers_for_subgoal_action).
fk(max_arity).
fk(max_char_code).
fk(max_procedure_arity).
fk(max_rational_size_action).
fk(max_table_answer_size_action).
fk(max_table_subgoal_size_action).
fk(max_tagged_integer).
fk(min_tagged_integer).
fk(mitigate_spectre).
fk(occurs_check).
fk(optimise).
fk(optimise_unify).
fk(packs).
fk(path_sep).
fk(portable_vmi).
fk(prefer_rationals).
fk(protect_static_code).
fk(quasi_quotations).
fk(rational_syntax).
fk(rationals).
fk(report_error).
fk(sandboxed_load).
fk(shift_check).
fk(signals).
fk(source).
fk(source_search_working_directory).
fk(stack_limit).
fk(stream_type_check).
fk(table_compile_threshold).
fk(table_drop_intermediate).
fk(table_incremental).
fk(table_monotonic).
fk(table_shared).
fk(table_space).
fk(table_subsumptive).
fk(theme).
fk(toplevel_name_variables).
fk(toplevel_print_anon).
fk(toplevel_prompt).
fk(toplevel_var_size).
fk(trace_gc).
fk(traditional).
fk(unicode_atoms).
fk(unicode_syntax_version).
fk(unix).
fk(unknown).
fk(unknown_option).
fk(unload_foreign_libraries).
fk(user_flags).
fk(var_prefix).
fk(var_tag).
fk(verbose_autoload).
fk(verbose_file_search).
fk(verbose_load).
fk(version).
fk(version_data).
fk(vmi_builtin).
fk(warn_override_implicit_import).
fk(write_attributes).
fk(xdg).

mk(arch).
mk(executable).
mk(home).
mk(compiled_at).
mk(pid).
mk(cpu_count).
mk(path_max).
mk(address_bits).
mk(tmp_dir).
mk(timezone).
mk(gmp_version).
mk(argv).
mk(os_argv).
mk(encoding).
mk(tty_control).
mk(file_name_case_handling).
mk(on_error).
mk(on_warning).
mk(posix_shell).
mk(verbose).

fref(ci_min_speedup, 1.5).
fref(ci_max_var_fraction, 0.10000000149011612).
fref(ci_min_speedup_ratio, 3.0).
fref(float_min, 2.2250738585072014e-308).
fref(float_max, 1.7976931348623157e308).
fref(float_max_integer, 9007199254740992.0).
fref(halt_grace_time, 1.0).

nv(K, V, flt(eq)) :- float(V), fref(K, R), V =:= R, !.
nv(_, V, flt(ne)) :- float(V), !.
nv(_, V, V).

ty([], term) :- !.
ty(V, bool) :- ( V == true ; V == false ), !.
ty(V, atom) :- atom(V), !.
ty(V, integer) :- integer(V), !.
ty(V, float) :- float(V), !.
ty(V, term) :- compound(V), !.
ty(_, other).

cat(G, R) :- catch(( call(G) -> R = yes(G) ; R = no ), E, R = ex(E)).

sorted(G, K, L) :- findall(K, G, L0), msort(L0, L).

% ---- the defaults: every portable flag through '$current_prolog_flag'/5 (value, access, type), one answer per flag, in fk/1's order
t_defaults(K-r(V1, A, T)) :- fk(K), '$current_prolog_flag'(K, V, _, A, T), nv(K, V, V1).
t_machine(K-r(Ty, A, T)) :- mk(K), '$current_prolog_flag'(K, V, _, A, T), ty(V, Ty).
% current_prolog_flag/2 and '$current_prolog_flag'/5 agree, and every portable flag is enumerated
t_same(L) :- findall(K, ( fk(K), \+ ( current_prolog_flag(K, V), '$current_prolog_flag'(K, W, _, _, _), V == W ) ), L).
t_missing(L) :- findall(K, ( fk(K), \+ ( current_prolog_flag(L0, _), L0 == K ) ), L).
t_count(N) :- findall(K, ( current_prolog_flag(K, _), fk(K) ), L), length(L, N).
t_machine_count(N) :- findall(K, ( current_prolog_flag(K, _), mk(K) ), L), length(L, N).

% ---- errors, failures, the key
t_e01(R) :- cat(current_prolog_flag(1, _), R).
t_e02(R) :- cat(current_prolog_flag(f(x), _), R).
t_e03(R) :- cat(current_prolog_flag("iso", _), R).
t_e04(R) :- cat(current_prolog_flag(nosuchflag, _), R).
t_e05(R) :- cat(current_prolog_flag(iso, 1), R).
t_e06(R) :- cat(current_prolog_flag(iso, on), R).
t_e07(R) :- cat(current_prolog_flag(iso, foo), R).
t_e08(R) :- cat(current_prolog_flag(iso, false), R).
t_e09(R) :- cat(current_prolog_flag(bounded, true), R).
t_e10(R) :- cat(current_prolog_flag(user:double_quotes, _), R).
t_e11(R) :- cat(current_prolog_flag(system:double_quotes, _), R).
t_e12(R) :- cat(current_prolog_flag(_:iso, _), R).
t_e13(R) :- cat(current_prolog_flag(max_integer, _), R).
t_e14(R) :- cat(current_prolog_flag(min_integer, _), R).
t_e15(R) :- cat(current_prolog_flag(break_level, _), R).
t_e16(R) :- cat(current_prolog_flag(max_rational_size, _), R).
t_e17(R) :- cat(current_prolog_flag(max_integer_size, _), R).
t_e18(R) :- cat(current_prolog_flag(max_table_subgoal_size, _), R).
t_e19(R) :- cat(current_prolog_flag(max_table_answer_size, _), R).
t_e20(R) :- cat(current_prolog_flag(max_answers_for_subgoal, _), R).
t_e21(R) :- cat(current_prolog_flag(max_rational_size_action, _), R).
t_e22(R) :- cat(current_prolog_flag(debug, 1), R).
t_e23(R) :- cat(current_prolog_flag(debug, foo), R).
t_e24(R) :- cat(current_prolog_flag(float_rounding, to_nearest), R).
t_e25(R) :- cat(current_prolog_flag(float_overflow, infinity), R).
t_e26(R) :- cat(current_prolog_flag(ci_min_clauses, 10), R).
t_e27(R) :- cat(current_prolog_flag(ci_min_clauses, 11), R).
t_e28(R) :- cat(current_prolog_flag(ci_min_speedup, 1.5), R).
t_e29(R) :- cat(current_prolog_flag(stack_limit, 1073741824), R).
t_e30(R) :- cat(current_prolog_flag(version_data, swi(10, _, _, _)), R).
t_e31(R) :- cat(current_prolog_flag(user:unknown, _), R).
t_e32(R) :- cat(current_prolog_flag(system:unknown, _), R).
t_e33(R) :- cat(current_prolog_flag(user:character_escapes, _), R).
t_e34(R) :- cat(current_prolog_flag(user:back_quotes, _), R).
t_e35(R) :- cat(current_prolog_flag(user:rational_syntax, _), R).
t_e36(R) :- cat(current_prolog_flag(user:access_level, _), R).

% ---- '$current_prolog_flag'/5: the scope, access and type arguments
t_s01(R) :- cat('$current_prolog_flag'(iso, _, _, _, _), R).
t_s02(R) :- cat('$current_prolog_flag'(iso, _, local, _, _), R).
t_s03(R) :- cat('$current_prolog_flag'(_, _, nosuch, _, _), R).
t_s04(R) :- cat('$current_prolog_flag'(_, _, 1, _, _), R).
t_s05(R) :- cat('$current_prolog_flag'(_, _, global, bad, _), R).
t_s06(R) :- cat('$current_prolog_flag'(1, _, _, _, _), R).
t_s07(R) :- cat('$current_prolog_flag'(double_quotes, _, _, _, _), R).
t_s08(R) :- cat('$current_prolog_flag'(ci_min_speedup_ratio, _, _, _, _), R).
t_s09(R) :- cat('$current_prolog_flag'(stack_limit, _, _, _, _), R).
t_s10(R) :- cat('$current_prolog_flag'(version_data, _, _, _, _), R).
t_s11(R) :- cat('$current_prolog_flag'(iso, _, _, read, _), R).
t_s12(R) :- cat('$current_prolog_flag'(bounded, _, _, read, boolean), R).
t_s13(R) :- cat('$current_prolog_flag'(bounded, _, _, write, boolean), R).
t_s14(R) :- cat('$current_prolog_flag'(bounded, _, _, _, atom), R).

% ---- enumeration: the keys of the portable flags, sorted (a multi-answer row: the order is the table's)
t_enum_true(L) :- sorted(( current_prolog_flag(K, true), fk(K) ), K, L).
t_enum_false(L) :- sorted(( current_prolog_flag(K, false), fk(K) ), K, L).
t_enum_error(L) :- sorted(( current_prolog_flag(K, error), fk(K) ), K, L).
t_enum_one(L) :- sorted(( current_prolog_flag(K, 1), fk(K) ), K, L).
t_enum_foo(L) :- sorted(( current_prolog_flag(K, foo), fk(K) ), K, L).
t_enum_1000(L) :- sorted(( current_prolog_flag(K, 1000), fk(K) ), K, L).
t_enum_string(L) :- sorted(( current_prolog_flag(user:K, string), fk(K) ), K, L).
t_enum_system(L) :- sorted(( current_prolog_flag(system:K, string), fk(K) ), K, L).
t_enum_read(L) :- sorted(( '$current_prolog_flag'(K, _, _, read, _), fk(K) ), K, L).
t_enum_write(L) :- sorted(( '$current_prolog_flag'(K, _, _, write, _), fk(K) ), K, L).
t_enum_boolean(L) :- sorted(( '$current_prolog_flag'(K, _, _, _, boolean), fk(K) ), K, L).
t_enum_atom(L) :- sorted(( '$current_prolog_flag'(K, _, _, _, atom), fk(K) ), K, L).
t_enum_integer(L) :- sorted(( '$current_prolog_flag'(K, _, _, _, integer), fk(K) ), K, L).
t_enum_float(L) :- sorted(( '$current_prolog_flag'(K, _, _, _, float), fk(K) ), K, L).
t_enum_term(L) :- sorted(( '$current_prolog_flag'(K, _, _, _, term), fk(K) ), K, L).
t_enum_global(N) :- findall(K, ( '$current_prolog_flag'(K, _, global, _, _), fk(K) ), L), length(L, N).
t_enum_scope(S) :- findall(K-X, ( '$current_prolog_flag'(K, _, X, _, _), K == iso ), S).

% ---- a cut after one answer (FRG_CUTTED frees the state: the .jl counts the live states after every row)
t_cut1(K) :- current_prolog_flag(K, _), K == iso, !.
t_cut2(K) :- '$current_prolog_flag'(K, _, _, _, _), K == double_quotes, !.
t_cut3(K) :- current_prolog_flag(K, true), K == gc, !.
t_cut4(N) :- findall(x, ( current_prolog_flag(_, _), ! ), L), length(L, N).
t_cut5(R) :- ( current_prolog_flag(K, V), K == iso -> R = K-V ; R = none ).
t_cut6(R) :- \+ ( current_prolog_flag(K, _), K == nosuchflag ), R = ok.
t_cut7(R) :- catch(( current_prolog_flag(K, _), K == iso, throw(done(K)) ), done(X), R = X).

% ---- the flags the arithmetic reads (`iso`, `prefer_rationals`: bits of the mask): the same rows run by the .jl after the flag is
% set (swipl: set_prolog_flag/2; the kernel: the mask bit, until R2 F1b ports set_prolog_flag/2)
cat_is(X, R) :- catch(R is X, E, R = ex(E)).
t_h3a(R) :- cat_is(4/2, R).
t_h3b(R) :- cat_is(7/2, R).
t_h3c(R) :- cat_is(1/3, R).
t_h3d(R) :- cat_is(2 ** -1, R).
t_h3e(R) :- cat_is(2 ^ -1, R).
t_h3f(R) :- cat_is(-4/2, R).
t_h3g(R) :- cat_is(2 ** 3, R).
t_h3h(R) :- cat_is(2 ** 3.0, R).

% ---- the arithmetic flags read the local data's float state (`arith_f_flags`): the .jl sets all four on both sides, then asks
afk(float_overflow).
afk(float_zero_div).
afk(float_undefined).
afk(float_underflow).
afk(float_rounding).
t_arith(L) :- findall(K-V, ( afk(K), current_prolog_flag(K, V) ), L).

% ---- the flags the reader and the compiler read (`iso`, `quasi_quotations`, `protect_static_code`: bits of the mask). t_h4a, t_h4b and t_psc
% run in the default run; the v_ rows only after the .jl has set the flag (a default run would ask the reader about quasi quotations)
cat_t(A, R) :- catch(( term_to_atom(T, A), R = T ), error(E, _), R = ex(E)).
t_h4a(R) :- cat_t('foo(/* a /* b */ c */ x)', R).
t_h4b(R) :- cat_t('f(a:-b)', R).
t_h4c(R) :- catch(( read_term_from_atom(a, T, [foo]) -> R = yes(T) ; R = no ), error(E, _), R = ex(E)).
v_qq1(R) :- cat_t('{|a||b|}', R).
v_qq2(R) :- cat_t('[a||b]', R).
h5s(a).
t_psc(R) :- catch(( clause(h5s(X), B) -> R = yes(X, B) ; R = no ), error(E, _), R = ex(E)).
