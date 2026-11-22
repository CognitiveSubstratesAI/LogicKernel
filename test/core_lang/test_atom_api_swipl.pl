% ORIGINAL: the rows of test/core_lang/test_atom_api_swipl.jl (its predicates are pl-atom.c's: $complete_atom/3, blob_type_property/2,
% set_blob_type/2, blob_released/1, current_atom/1).
% test/core_lang/test_atom_api_swipl.pl - ATOM-API's rows. Each `aaNN(R)` is one row; test_atom_api_swipl.out holds swipl
% 10.1.20's answers to them, as the test's driver prints them (`ok`, then one line per row: its name and every solution).
%   aa01-aa21  '$complete_atom'/3 over the atoms THIS PROGRAM holds (aa_fact/1 below and the two long atoms at its end) and
%              string, code list and atom prefixes; the answers are code lists, never an atom made at run time (an atom made
%              at run time is not offered by swipl once collected and is global in the kernel: the rows keep clear of it).
%   aa22-aa50  blob_type_property/2 over the types `text`, `ucs_text` and `reserved_symbol`, the errors, the statistics.
%   aa51-aa64  set_blob_type/2 (set and read back, every error in the order of the checks).
%   aa65-aa78  blob_released/1 and current_atom/1 (aa78: the program holds the atom `unregistered`, for aa15).
% The enumeration of ALL blob types is not a row: swipl registers more types (mutex, thread, stream ...) than the kernel.

aa_fact(qzx_alpha_one).
aa_fact(qzx_alpha_two).
aa_fact(qzx_beta_one).
aa_fact(qzx_gamma_one).
aa_unregistered(unregistered(0)).

aa_e(G, R) :- catch(G, error(E, _), R = raised(E)).
aa_ca(P, R) :- '$complete_atom'(P, C, U), R = C-U.
aa_cal(P, R) :- '$complete_atom'(P, C, U), length(C, N), R = N-U.
aa_rep(0, []) :- !.
aa_rep(N, [0'a|T]) :- N1 is N-1, aa_rep(N1, T).
aa_wide(W) :- atom_codes(W, [945, 98]).
aa_prop(T, F) :- findall(P, blob_type_property(T, P), Ps), aa_names(Ps, F).
aa_names([], []).
aa_names([P|Ps], [F|Fs]) :- functor(P, F, _), aa_names(Ps, Fs).

% '$complete_atom'/3: the prefix, then the answer (the code list of prefix + common text) and unique/not_unique
aa01(R) :- aa_e(aa_ca("qzx_alp", R), R).
aa02(R) :- aa_e(aa_ca("qzx_alpha_o", R), R).
aa03(R) :- aa_e(aa_ca("qzx_alpha_one", R), R).
aa04(R) :- aa_e(aa_ca("qzx_nomatch", R), R).
aa05(R) :- aa_e(aa_ca(qzx_gamma_one, R), R).
aa06(R) :- aa_e(aa_ca([0'q, 0'z, 0'x, 0'_, 0'b, 0'e], R), R).
aa07(R) :- aa_e(aa_ca([], R), R).
aa08(R) :- aa_e((string_codes(S, [945, 946]), aa_ca(S, R)), R).
aa09(R) :- aa_e(aa_ca(12, R), R).
aa10(R) :- aa_e(aa_ca(1.5, R), R).
aa11(R) :- aa_e(aa_ca(_, R), R).
aa12(R) :- aa_e(aa_ca(f(x), R), R).
aa13(R) :- aa_e((aa_rep(1100, L), string_codes(S, L), aa_ca(S, R)), R).
aa14(R) :- aa_e((string_codes(S, [0'q, 0'z, 0'x, 0'_, 0'a, 0'l, 0'p, 0, 0'z]), aa_ca(S, R)), R).
aa15(R) :- aa_e(aa_ca("unregist", R), R).
aa16(R) :- aa_e(aa_ca("qzx_", R), R).
aa17(R) :- aa_e(aa_ca("qzx_alpha_t", R), R).
aa18(R) :- aa_e(aa_ca("qzx_alpha_one_", R), R).
aa19(R) :- aa_e(aa_cal("aa_lg_", R), R).
aa20(R) :- aa_e(aa_ca("qzx_alpha_", R), R).
aa21(R) :- aa_e(aa_ca("", R), R).

% blob_type_property/2 of `text`: the properties in upstream's order, and each value
aa22(R) :- aa_e(aa_prop(text, R), R).
aa23(R) :- aa_e(blob_type_property(text, rank(R)), R).
aa24(R) :- aa_e(blob_type_property(text, padding(R)), R).
aa25(R) :- aa_e(blob_type_property(text, gc_margin(R)), R).
aa26(R) :- aa_e(blob_type_property(text, unregistered(R)), R).
aa27(R) :- aa_e(blob_type_property(text, non_garbage(R)), R).
aa28(R) :- aa_e((blob_type_property(text, live(N)), integer(N), N > 0, R = yes), R).
aa29(R) :- aa_e((blob_type_property(text, space(N)), integer(N), N > 0, R = yes), R).
aa30(R) :- aa_e((blob_type_property(text, unique), R = yes), R).
aa31(R) :- aa_e((blob_type_property(text, wchar), R = yes), R).
aa32(R) :- aa_e((blob_type_property(text, nocopy), R = yes), R).
aa33(R) :- aa_e(findall(T, (blob_type_property(T, text), T == text), R), R).
aa34(R) :- aa_e(findall(T, (blob_type_property(T, unique), T == text), R), R).
% ucs_text (made at the first wide atom) and reserved_symbol
aa35(R) :- aa_e((aa_wide(_), blob_type_property(ucs_text, wchar), R = yes), R).
aa36(R) :- aa_e((aa_wide(_), blob_type_property(ucs_text, rank(R))), R).
aa37(R) :- aa_e((aa_wide(_), blob_type_property(ucs_text, padding(R))), R).
aa38(R) :- aa_e((aa_wide(_), findall(T, (blob_type_property(T, wchar), T == ucs_text), R)), R).
aa39(R) :- aa_e((blob_type_property(reserved_symbol, unique), R = yes), R).
aa40(R) :- aa_e((blob_type_property(reserved_symbol, text), R = yes), R).
% errors and both-given answers
aa41(R) :- aa_e(blob_type_property(nosuch, unique), R).
aa42(R) :- aa_e(blob_type_property(f(x), unique), R).
aa43(R) :- aa_e(blob_type_property(1, unique), R).
aa44(R) :- aa_e((blob_type_property(f(x), _), R = yes), R).
aa45(R) :- aa_e((blob_type_property(text, rank(1)), R = yes), R).
aa46(R) :- aa_e((blob_type_property(text, rank(2)), R = yes), R).
aa47(R) :- aa_e((blob_type_property(text, foo(1)), R = yes), R).
% the statistics follow the atoms made: a new atom counts, the same name again does not
aa48(R) :- aa_e((blob_type_property(text, live(N0)), atom_codes(_, [0'a, 0'a, 0'_, 0'l, 0'v, 0'_, 0'1]),
                 blob_type_property(text, live(N1)), ( N1 > N0 -> R = grew ; R = same )), R).
aa49(R) :- aa_e((blob_type_property(text, space(N0)), atom_codes(_, [0'a, 0'a, 0'_, 0'l, 0'v, 0'_, 0'2, 0'x]),
                 blob_type_property(text, space(N1)), ( N1 >= N0 + 8 -> R = grew ; R = short )), R).
aa50(R) :- aa_e((atom_codes(_, [0'a, 0'a, 0'_, 0'l, 0'v, 0'_, 0'3]), blob_type_property(text, live(N0)),
                 atom_codes(_, [0'a, 0'a, 0'_, 0'l, 0'v, 0'_, 0'3]), blob_type_property(text, live(N1)),
                 ( N1 =:= N0 -> R = same ; R = grew )), R).
% set_blob_type/2: set, read back, reset; the errors in the order of the checks
aa51(R) :- aa_e((set_blob_type(text, gc_margin(7)), blob_type_property(text, gc_margin(M)),
                 set_blob_type(text, gc_margin(0)), R = M), R).
aa52(R) :- aa_e((set_blob_type(text, gc_margin(0)), R = yes), R).
aa53(R) :- aa_e(set_blob_type(text, gc_margin(-1)), R).
aa54(R) :- aa_e(set_blob_type(text, gc_margin(a)), R).
aa55(R) :- aa_e(set_blob_type(text, gc_margin(1.5)), R).
aa56(R) :- aa_e(set_blob_type(text, foo), R).
aa57(R) :- aa_e(set_blob_type(text, f(x)), R).
aa58(R) :- aa_e(set_blob_type(_, gc_margin(1)), R).
aa59(R) :- aa_e(set_blob_type(nosuch, gc_margin(1)), R).
aa60(R) :- aa_e(set_blob_type(text, gc_margin(_)), R).
aa61(R) :- aa_e(set_blob_type(text, _), R).
aa62(R) :- aa_e(set_blob_type(1, gc_margin(1)), R).
aa63(R) :- aa_e(set_blob_type(text, 1), R).
aa64(R) :- aa_e(set_blob_type(text, gc_margin(1, 2)), R).
% blob_released/1 and current_atom/1
aa65(R) :- aa_e((blob_released(foo), R = yes), R).
aa66(R) :- aa_e((blob_released(_), R = yes), R).
aa67(R) :- aa_e((blob_released(1), R = yes), R).
aa68(R) :- aa_e((blob_released("s"), R = yes), R).
aa69(R) :- aa_e((blob_released([]), R = yes), R).
aa70(R) :- aa_e((current_atom(foo), R = yes), R).
aa71(R) :- aa_e((current_atom(1), R = yes), R).
aa72(R) :- aa_e((current_atom([]), R = yes), R).
aa73(R) :- aa_e((current_atom("s"), R = yes), R).
aa74(R) :- aa_e((current_atom(f(x)), R = yes), R).
aa75(R) :- aa_e((once(current_atom(A)), atom(A), R = yes), R).
aa76(R) :- aa_e(findall(x, (current_atom(A), A == qzx_gamma_one), R), R).
aa77(R) :- aa_e((aa_wide(W), current_atom(W), R = yes), R).
aa78(R) :- aa_e((aa_unregistered(P), blob_type_property(text, P), R = yes), R).

% two atoms of 1023 and 1024 bytes (strlen < LINESIZ = 1024: only the first is offered by '$complete_atom'/3), row aa19
aa_long('aa_lg_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx').
aa_long('aa_lg_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy').
