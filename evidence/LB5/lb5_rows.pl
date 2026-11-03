lb5_p(1).
t_lb001(R) :- catch((with_output_to(string(S), (write(abc), current_output(O), line_position(O, P), line_count(O, L))), R = S-P-L), error(SsuE, _), R = raised(SsuE)).
t_lb002(R) :- catch((with_output_to(string(S), (write(ab), nl, write(c), current_output(O), line_position(O, P), line_count(O, L))), R = S-P-L), error(SsuE, _), R = raised(SsuE)).
t_lb003(R) :- catch((with_output_to(string(S), (write(ab), put_char('\t'), current_output(O), line_position(O, P))), R = S-P), error(SsuE, _), R = raised(SsuE)).
t_lb004(R) :- catch((open_string('ab\ncd', S), get_code(S, _), get_code(S, _), get_code(S, _), get_code(S, _), line_count(S, L), line_position(S, P), R = L-P), error(SsuE, _), R = raised(SsuE)).
t_lb005(R) :- catch((open_string(abc, S), line_count(S, L), line_position(S, P), R = L-P), error(SsuE, _), R = raised(SsuE)).
t_lb006(R) :- catch((open_string(abc, S), ( line_count(S, 2) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb007(R) :- catch((line_count(foo, _)), error(SsuE, _), R = raised(SsuE)).
t_lb008(R) :- catch((line_position(_, _)), error(SsuE, _), R = raised(SsuE)).
t_lb009(R) :- catch((open_string(abc, S), close(S), catch(line_count(S, _), error(existence_error(A, _), _), R = ex(A))), error(SsuE, _), R = raised(SsuE)).
t_lb010(R) :- catch((open('/dev/null', read, S, [record_position(false)]), catch((line_count(S, N), R = ok-N), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb011(R) :- catch((open('/dev/null', read, S, [record_position(false)]), catch((line_position(S, N), R = ok-N), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb012(R) :- catch((current_output(S), is_stream(S), R = yes), error(SsuE, _), R = raised(SsuE)).
t_lb013(R) :- catch((current_input(S), is_stream(S), R = yes), error(SsuE, _), R = raised(SsuE)).
t_lb014(R) :- catch((current_output(A), current_output(B), ( A == B -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_lb015(R) :- catch((current_input(A), current_output(B), ( A == B -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_lb016(R) :- catch((current_output(O0), with_output_to(string(_), ( current_output(O1), ( O0 == O1 -> R = same ; R = diff ) ))), error(SsuE, _), R = raised(SsuE)).
t_lb017(R) :- catch((current_output(foo)), error(SsuE, _), R = raised(SsuE)).
t_lb018(R) :- catch((current_output(1)), error(SsuE, _), R = raised(SsuE)).
t_lb019(R) :- catch((current_input(foo)), error(SsuE, _), R = raised(SsuE)).
t_lb020(R) :- catch((open_string(abc, I), ( current_output(I) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb021(R) :- catch((current_output(O), ( current_input(O) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb022(R) :- catch((with_output_to(string(S), (write(a), tab(3), write(b))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb023(R) :- catch((with_output_to(string(S), (write(a), tab(1+2), write(b))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb024(R) :- catch((with_output_to(string(S), (write(a), tab(0), write(b))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb025(R) :- catch((with_output_to(string(S), (write(a), tab(-1), write(b))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb026(R) :- catch((with_output_to(string(S), tab(a)), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb027(R) :- catch((tab(_)), error(SsuE, _), R = raised(SsuE)).
t_lb028(R) :- catch((with_output_to(string(S), tab(2.5)), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb029(R) :- catch((with_output_to(string(S), tab(2.0 * 2)), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb030(R) :- catch((with_output_to(string(S), (write(a), tab(3*2), write(b))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb031(R) :- catch((tab(1 << 70)), error(SsuE, _), R = raised(SsuE)).
t_lb032(R) :- catch((with_output_to(string(S), (current_output(O), tab(O, 2), write(x), tab(O, 1+1), write(y))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb033(R) :- catch((tab(foo, 2)), error(SsuE, _), R = raised(SsuE)).
t_lb034(R) :- catch((catch((open_string(abc, S), tab(S, 2), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb035(R) :- catch((with_output_to(string(_), (tab(5), current_output(O), line_position(O, P))), R = P), error(SsuE, _), R = raised(SsuE)).
t_lb036(R) :- catch((open_string('', S), ( at_end_of_stream(S) -> R = eof ; R = more )), error(SsuE, _), R = raised(SsuE)).
t_lb037(R) :- catch((open_string(a, S), ( at_end_of_stream(S) -> R = eof ; R = more )), error(SsuE, _), R = raised(SsuE)).
t_lb038(R) :- catch((open_string(a, S), get_code(S, _), ( at_end_of_stream(S) -> R = eof ; R = more )), error(SsuE, _), R = raised(SsuE)).
t_lb039(R) :- catch((open_string(a, S), get_code(S, _), get_code(S, C), ( at_end_of_stream(S) -> R = C-eof ; R = C-more )), error(SsuE, _), R = raised(SsuE)).
t_lb040(R) :- catch((at_end_of_stream(foo)), error(SsuE, _), R = raised(SsuE)).
t_lb041(R) :- catch((at_end_of_stream(_)), error(SsuE, _), R = raised(SsuE)).
t_lb042(R) :- catch((catch((current_output(O), at_end_of_stream(O), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb043(R) :- catch((open_string(abc, S), close(S), catch(at_end_of_stream(S), error(existence_error(A, _), _), R = ex(A))), error(SsuE, _), R = raised(SsuE)).
t_lb044(R) :- catch((open_string(ab, S), get_code(S, A), get_code(S, B), get_code(S, C), R = [A, B, C]), error(SsuE, _), R = raised(SsuE)).
t_lb045(R) :- catch((open_string(a, S), get_code(S, _), get_code(S, C1), get_code(S, C2), R = [C1, C2]), error(SsuE, _), R = raised(SsuE)).
t_lb046(R) :- catch((open_string(ab, S), ( get_code(S, 97) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb047(R) :- catch((open_string(ab, S), ( get_code(S, 98) -> X = yes ; X = no ), get_code(S, C), R = X-C), error(SsuE, _), R = raised(SsuE)).
t_lb048(R) :- catch((open_string('é', S), get_code(S, C), R = C), error(SsuE, _), R = raised(SsuE)).
t_lb049(R) :- catch((open_string(ab, S), get_code(S, a)), error(SsuE, _), R = raised(SsuE)).
t_lb050(R) :- catch((open_string(ab, S), get_code(S, end_of_file)), error(SsuE, _), R = raised(SsuE)).
t_lb051(R) :- catch((open_string(ab, S), get_code(S, -2)), error(SsuE, _), R = raised(SsuE)).
t_lb052(R) :- catch((open_string(ab, S), get_code(S, 1114112)), error(SsuE, _), R = raised(SsuE)).
t_lb053(R) :- catch((get_code(foo, _)), error(SsuE, _), R = raised(SsuE)).
t_lb054(R) :- catch((get_code(_, _)), error(SsuE, _), R = raised(SsuE)).
t_lb055(R) :- catch((catch((current_output(O), get_code(O, _), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb056(R) :- catch((open_string('', S), ( get_code(S, -1) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb057(R) :- catch((with_output_to(string(S), (put_code(97), put_code(233), put_code(0x1F600))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb058(R) :- catch((put_code(-1)), error(SsuE, _), R = raised(SsuE)).
t_lb059(R) :- catch((with_output_to(string(S), put_code(a)), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb060(R) :- catch((put_code(_)), error(SsuE, _), R = raised(SsuE)).
t_lb061(R) :- catch((put_code(1114112)), error(SsuE, _), R = raised(SsuE)).
t_lb062(R) :- catch((put_code(97.0)), error(SsuE, _), R = raised(SsuE)).
t_lb063(R) :- catch((catch((open_string(abc, S), put_code(S, 97), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))), error(SsuE, _), R = raised(SsuE)).
t_lb064(R) :- catch((with_output_to(string(S), (current_output(O), put_code(O, 0))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb065(R) :- catch((with_output_to(string(S), (current_output(O), put_code(O, 104), put_code(O, 105))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb066(R) :- catch((put_code(foo, 97)), error(SsuE, _), R = raised(SsuE)).
t_lb067(R) :- catch((with_output_to(string(S), (put_char(a), put_char('é'))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb068(R) :- catch((put_char(ab)), error(SsuE, _), R = raised(SsuE)).
t_lb069(R) :- catch((with_output_to(string(S), put_char(1)), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb070(R) :- catch((put_char(_)), error(SsuE, _), R = raised(SsuE)).
t_lb071(R) :- catch((with_output_to(string(S), (current_output(O), put_char(O, x), put_char(O, y))), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb072(R) :- catch((put_char(foo, x)), error(SsuE, _), R = raised(SsuE)).
t_lb073(R) :- catch((with_output_to(string(_), (put_code(97), put_code(10), put_code(98), current_output(O), line_position(O, P), line_count(O, L))), R = P-L), error(SsuE, _), R = raised(SsuE)).
t_lb074(R) :- catch((write_size(foo(bar,baz), W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb075(R) :- catch((write_size('hello world', W, H, [quoted(true)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb076(R) :- catch((write_size('a\nbcd', W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb077(R) :- catch((write_size('', W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb078(R) :- catch((write_size('', W, H, [max_height(0)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb079(R) :- catch((write_size(abcdef, _, _, [max_width(3)])), error(SsuE, _), R = raised(SsuE)).
t_lb080(R) :- catch((write_size(abcdef, W, H, [max_width(6)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb081(R) :- catch((write_size('a\nb', _, _, [max_height(1)])), error(SsuE, _), R = raised(SsuE)).
t_lb082(R) :- catch((write_size('a\nb', W, H, [max_height(2)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb083(R) :- catch((write_size(x, _, _, [max_width(0)])), error(SsuE, _), R = raised(SsuE)).
t_lb084(R) :- catch((write_size(x, _, _, [max_height(0)])), error(SsuE, _), R = raised(SsuE)).
t_lb085(R) :- catch((write_size(x, _, _, [max_width(a)])), error(SsuE, _), R = raised(SsuE)).
t_lb086(R) :- catch((write_size(x, _, _, [max_width(1+1)])), error(SsuE, _), R = raised(SsuE)).
t_lb087(R) :- catch((write_size(x, _, _, foo)), error(SsuE, _), R = raised(SsuE)).
t_lb088(R) :- catch((( write_size(x, 2, _, []) -> R = yes ; R = no )), error(SsuE, _), R = raised(SsuE)).
t_lb089(R) :- catch((write_size('日本', W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb090(R) :- catch((write_size('a\tb', W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb091(R) :- catch((write_size('$VAR'(1), W, H, [numbervars(true)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb092(R) :- catch((write_size([1,2,3], W, H, [max_width(7)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb093(R) :- catch((write_size(x, W, H, [quoted(true), max_width(1)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb094(R) :- catch((with_output_to(string(S), (write(a), write_size(bcd, W, H, []), write(e))), R = S-W-H), error(SsuE, _), R = raised(SsuE)).
t_lb095(R) :- catch((write_size(f(x), W, H, [quoted]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb096(R) :- catch((write_size(f(x), W, H, [no_such_option(1)]), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb097(R) :- catch((current_output(OO), with_output_to(string(S), ( current_output(M), set_stream(M, alias(user_output)), write(user_output, hi), set_stream(OO, alias(user_output)) )), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb098(R) :- catch((set_stream(user_error, alias(lb5_saved_err)), with_output_to(string(S), ( current_output(M), set_stream(M, alias(user_error)), write(user_error, hi), set_stream(lb5_saved_err, alias(user_error)) )), R = S), error(SsuE, _), R = raised(SsuE)).
t_lb099(R) :- catch((open_string(xy, S), set_stream(user_input, alias(lb5_saved_in)), set_stream(S, alias(user_input)), get_code(user_input, C1), get_char(user_input, C2), set_stream(lb5_saved_in, alias(user_input)), R = C1-C2), error(SsuE, _), R = raised(SsuE)).
t_lb100(R) :- catch((open_string(xy, S), current_input(I0), set_stream(user_input, alias(lb5_saved_in2)), set_stream(S, alias(user_input)), current_input(I1), set_stream(lb5_saved_in2, alias(user_input)), ( I0 == I1 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_lb101(R) :- catch((current_output(OO), with_output_to(string(_), ( current_output(M), set_stream(M, alias(user_output)), set_stream(OO, alias(user_output)) )), current_output(O2), ( OO == O2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_lb102(R) :- catch((set_stream(foo, alias(user_output))), error(SsuE, _), R = raised(SsuE)).
t_lb103(R) :- catch((current_output(O), set_stream(user_input, alias(lb5_saved_in3)), catch((set_stream(O, alias(user_input)), R = ok), error(Err, _), ( Err = permission_error(A, B, _) -> R = perm(A, B) ; R = Err )), set_stream(lb5_saved_in3, alias(user_input))), error(SsuE, _), R = raised(SsuE)).
t_lb104(R) :- catch((open_string(x, S), current_output(OO), catch((set_stream(S, alias(user_output)), R = ok), error(Err, _), ( Err = permission_error(A, B, _) -> R = perm(A, B) ; R = Err )), set_stream(OO, alias(user_output))), error(SsuE, _), R = raised(SsuE)).
t_lb105(R) :- catch((current_output(O), set_stream(O, alias(1))), error(SsuE, _), R = raised(SsuE)).
t_lb106(R) :- catch((current_output(O), set_stream(O, alias(_))), error(SsuE, _), R = raised(SsuE)).
t_lb107(R) :- catch((write_size('abcd\nx', W, H, []), R = W-H), error(SsuE, _), R = raised(SsuE)).
t_lb108(R) :- catch((line_count(user_output, N), integer(N), R = yes), error(SsuE, _), R = raised(SsuE)).
