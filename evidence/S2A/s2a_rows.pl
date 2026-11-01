datafile('/tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/7fed74f5-29da-4e48-90d4-1f228fe5bbba/scratchpad/s2/work/data.txt').
outfile('/tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/7fed74f5-29da-4e48-90d4-1f228fe5bbba/scratchpad/s2/work/out.txt').
ro(S) :- datafile(F), open(F, read, S).
rb(S) :- datafile(F), open(F, read, S, [type(binary)]).
ra(S, A) :- datafile(F), open(F, read, S, [alias(A)]).
wo(S) :- outfile(F), open(F, write, S).
nb(F, F1) :- F =.. [N|As], nbs(As, Bs), F1 =.. [N|Bs].
nbs([], []).
nbs([A|As], [B|Bs]) :- ( blob(A, stream) -> B = '<stream>' ; B = A ), nbs(As, Bs).
cerr(G, R) :- catch(( G -> R = ok ; R = failed ), error(F, _), ( nb(F, F1), R = raised(F1) )).
has(S, P, R) :- ( '$stream_property'(S, P) -> R = yes ; R = no ).
sp(S, P, R) :- ( '$stream_property'(S, P) -> R = P ; R = none ).
fnp(S, R) :- '$stream_property'(S, file_name(F)), datafile(D), ( F == D -> R = same ; R = F ).
mem(X, [X|_]) :- !.
mem(X, [_|T]) :- mem(X, T).
keep([], _, []).
keep([P|Ps], Ns, K) :- functor(P, N, _), ( mem(N, Ns) -> K = [P|K1] ; K = K1 ), keep(Ps, Ns, K1).
hasp([S0-_|_], S) :- S0 == S, !.
hasp([_|T], S) :- hasp(T, S).
cnt(L, N) :- '$skip_list'(N, L, _).
p1str :- prompt1("s").
fnstr(S) :- set_stream(S, file_name("str")).
ctxd(D1, D2) :-
    '$input_context'(L0), cnt(L0, N0), '$push_input_context'(ctx), '$input_context'(L1), cnt(L1, N1),
    '$pop_input_context', '$input_context'(L2), cnt(L2, N2), D1 is N1-N0, D2 is N2-N0.
ctxe(R) :-
    '$push_input_context'(ctx2), '$input_context'([E|_]), '$pop_input_context',
    functor(E, Nm, A), arg(1, E, T), R = Nm/A/T.
ctxo(T1, T2) :-
    '$push_input_context'(ca), '$push_input_context'(cb), '$input_context'([E1, E2|_]),
    '$pop_input_context', '$pop_input_context', arg(1, E1, T1), arg(1, E2, T2).
aliasbl(S, R) :- '$alias_stream'(zz1, S2), ( S2 == S -> R = same ; R = other ).
spairs(S, R) :-
    '$streams_properties'(alias(zz4), L), cnt(L, N), L = [S0-V|_], '$alias_stream'(zz4, SB),
    ( SB == S0 -> W = same ; W = other ), S = S0, R = N-W-V.
t_s001(R) :- catch((prompt(_, abc), prompt(O, def), R = O), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s002(R) :- catch((prompt(_, x), prompt(A, A), prompt(B, B), R = A-B), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s003(R) :- catch((prompt(_, 123)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s004(R) :- catch((prompt(_, f(x))), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s005(R) :- catch((prompt(_, abc), prompt(foo, N), R = N), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s006(R) :- catch((prompt(_, '|: '), prompt(O, O), R = O), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s007(R) :- catch((prompt1(abc), R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s008(R) :- catch((p1str, R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s009(R) :- catch((prompt1(12), R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s010(R) :- catch((cerr(prompt1(_), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s011(R) :- catch((prompt1(f(x))), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s012(R) :- catch((ctxd(D1, D2), R = D1-D2), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s013(R) :- catch((ctxe(R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s014(R) :- catch((ctxo(T1, T2), R = T1-T2), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s015(R) :- catch(('$push_input_context'(f(x))), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s016(R) :- catch(('$push_input_context'(_)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s017(R) :- catch((flush_output(user_output), R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s018(R) :- catch((flush_output(nosuch)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s019(R) :- catch((flush_output(_)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s020(R) :- catch((flush_output(foo(x))), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s021(R) :- catch((ro(S), cerr(flush_output(S), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s022(R) :- catch((wo(S), flush_output(S), close(S), R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s023(R) :- catch((wo(S), close(S), cerr(flush_output(S), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s024(R) :- catch((cerr(flush_output(user_input), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s025(R) :- catch((ttyflush, R = ok), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s026(R) :- catch((( is_stream(user_input) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s027(R) :- catch((( is_stream(nosuch) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s028(R) :- catch((( is_stream(_) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s029(R) :- catch((( is_stream(f(x)) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s030(R) :- catch((ro(S), ( is_stream(S) -> A = yes ; A = no ), close(S), ( is_stream(S) -> B = yes ; B = no ), R = A-B), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s031(R) :- catch((( is_stream(user_error) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s032(R) :- catch(('$alias_stream'(user_output, S), ( is_stream(S) -> R = yes ; R = no )), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s033(R) :- catch(('$alias_stream'(nosuch, _), R = found), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s034(R) :- catch(('$alias_stream'(1, _)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s035(R) :- catch(('$alias_stream'(_, _)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s036(R) :- catch((ro(S), set_stream(S, alias(zz1)), aliasbl(S, R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s037(R) :- catch((ro(S), set_stream(S, alias(zz2)), close(S), cerr('$alias_stream'(zz2, _), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s038(R) :- catch((ro(S), get_char(S, A), get_char(S, B), peek_char(S, P), get_char(S, C), close(S), R = [A, B, P, C]), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s039(R) :- catch((ro(S), get_char(S, _), get_char(S, _), get_char(S, _), get_char(S, N), close(S), R = N), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s040(R) :- catch((ro(S), skip(S, 120), get_char(S, C), close(S), R = C), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s041(R) :- catch((ro(S), skip(S, y), get_char(S, C), close(S), R = C), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s042(R) :- catch((ro(S), skip(S, 33), get_char(S, C1), get_char(S, C2), close(S), R = C1-C2), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s043(R) :- catch((ro(S), skip(S, 33), peek_char(S, C), close(S), R = C), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s044(R) :- catch((ro(S), set_stream(S, eof_action(error)), skip(S, 33), get_char(S, C1), cerr(get_char(S, _), R0), close(S), R = C1-R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s045(R) :- catch((ro(S), set_stream(S, eof_action(reset)), skip(S, 33), get_char(S, C1), get_char(S, C2), close(S), R = C1-C2), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s046(R) :- catch((ro(S), cerr(get_char(S, 1), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s047(R) :- catch((ro(S), cerr(get_char(S, ab), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s048(R) :- catch((ro(S), cerr(peek_char(S, 1), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s049(R) :- catch((ro(S), cerr(skip(S, foo), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s050(R) :- catch((ro(S), cerr(skip(S, 1.5), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s051(R) :- catch((wo(S), cerr(get_char(S, _), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s052(R) :- catch((get_char(nosuch, _)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s053(R) :- catch((get_char(_, _)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s054(R) :- catch((peek_char(nosuch, _)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s055(R) :- catch((skip(nosuch, 97)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s056(R) :- catch((ro(S), set_stream(S, type(binary)), cerr(get_char(S, _), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s057(R) :- catch((rb(S), cerr(get_char(S, _), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s058(R) :- catch((ro(S), get_char(S, _), get_char(S, _), get_char(S, _), get_char(S, _), '$stream_property'(S, position(P)), close(S), R = P), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s059(R) :- catch((ro(S), peek_char(S, _), '$stream_property'(S, position(P)), close(S), R = P), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s060(R) :- catch((ro(S), sp(S, end_of_stream(E0), _), skip(S, 33), sp(S, end_of_stream(E1), _), get_char(S, _), sp(S, end_of_stream(E2), _), close(S), R = [E0, E1, E2]), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s061(R) :- catch((ro(S), sp(S, mode(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s062(R) :- catch((ro(S), has(S, input, A), has(S, output, B), close(S), R = A-B), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s063(R) :- catch((wo(S), has(S, input, A), has(S, output, B), sp(S, mode(_), M), close(S), R = A-B-M), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s064(R) :- catch((ro(S), sp(S, eof_action(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s065(R) :- catch((ro(S), sp(S, type(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s066(R) :- catch((ro(S), sp(S, buffer(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s067(R) :- catch((ro(S), sp(S, newline(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s068(R) :- catch((ro(S), fnp(S, R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s069(R) :- catch((ra(S, zz3), sp(zz3, alias(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s070(R) :- catch((ro(S), sp(S, close_on_abort(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s071(R) :- catch((ro(S), sp(S, representation_errors(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s072(R) :- catch((ro(S), sp(S, write_errors(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s073(R) :- catch((ro(S), sp(S, unicode_atoms(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s074(R) :- catch((ro(S), sp(S, error(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s075(R) :- catch((ro(S), sp(S, position(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s076(R) :- catch((ro(S), sp(S, encoding(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s077(R) :- catch((ro(S), sp(S, buffer_size(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s078(R) :- catch((ro(S), sp(S, reposition(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s079(R) :- catch((ro(S), sp(S, timeout(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s080(R) :- catch((ro(S), '$stream_properties'(S, L), keep(L, [mode, input, eof_action, type, buffer, close_on_abort, newline, representation_errors, write_errors, unicode_atoms, end_of_stream, error], K), close(S), R = K), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s081(R) :- catch((ra(S, zz4), spairs(S0, R0), close(S0), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s082(R) :- catch(('$streams_properties'(alias(nosuch), L), R = L), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s083(R) :- catch((ro(S), '$streams_properties'(mode(read), L), ( hasp(L, S) -> A = yes ; A = no ), '$streams_properties'(mode(write), L2), ( hasp(L2, S) -> B = yes ; B = no ), close(S), R = A-B), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s084(R) :- catch((ro(S), cerr('$stream_property'(S, bogus(_)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s085(R) :- catch((cerr('$stream_property'(nosuch, mode(_)), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s086(R) :- catch((ro(S), close(S), cerr('$stream_property'(S, mode(_)), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s087(R) :- catch((cerr('$stream_properties'(nosuch, _), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s088(R) :- catch((cerr('$stream_properties'(_, _), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s089(R) :- catch((ro(S), set_stream(S, alias(zz5)), has(S, alias(zz5), A), close(S), R = A), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s090(R) :- catch((ro(S), cerr(set_stream(S, alias(_)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s091(R) :- catch((ro(S), cerr(set_stream(S, alias(1)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s092(R) :- catch((ro(S), set_stream(S, buffer(line)), sp(S, buffer(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s093(R) :- catch((ro(S), set_stream(S, buffer(false)), sp(S, buffer(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s094(R) :- catch((ro(S), set_stream(S, buffer(full)), sp(S, buffer(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s095(R) :- catch((ro(S), cerr(set_stream(S, buffer(bad)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s096(R) :- catch((wo(S), set_stream(S, buffer_size(100)), sp(S, buffer_size(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s097(R) :- catch((wo(S), cerr(set_stream(S, buffer_size(0)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s098(R) :- catch((wo(S), cerr(set_stream(S, buffer_size(a)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s099(R) :- catch((ro(S), set_stream(S, eof_action(reset)), sp(S, eof_action(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s100(R) :- catch((ro(S), cerr(set_stream(S, eof_action(bad)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s101(R) :- catch((wo(S), cerr(set_stream(S, eof_action(reset)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s102(R) :- catch((ro(S), set_stream(S, type(binary)), sp(S, type(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s103(R) :- catch((rb(S), set_stream(S, type(text)), sp(S, type(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s104(R) :- catch((ro(S), cerr(set_stream(S, type(foo)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s105(R) :- catch((ro(S), set_stream(S, close_on_abort(false)), sp(S, close_on_abort(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s106(R) :- catch((ro(S), cerr(set_stream(S, close_on_abort(foo)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s107(R) :- catch((ro(S), set_stream(S, record_position(false)), sp(S, position(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s108(R) :- catch((ro(S), set_stream(S, record_position(false)), cerr(set_stream(S, line_position(3)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s109(R) :- catch((wo(S), set_stream(S, line_position(3)), sp(S, position(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s110(R) :- catch((wo(S), cerr(set_stream(S, line_position(a)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s111(R) :- catch((ro(S), set_stream(S, record_position(false)), set_stream(S, record_position(true)), sp(S, position(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s112(R) :- catch((ro(S), set_stream(S, file_name(abc)), sp(S, file_name(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s113(R) :- catch((ro(S), fnstr(S), sp(S, file_name(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s114(R) :- catch((ro(S), cerr(set_stream(S, tty(true)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s115(R) :- catch((ro(S), cerr(set_stream(S, tty(foo)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s116(R) :- catch((ro(S), set_stream(S, encoding(octet)), sp(S, encoding(_), E), sp(S, type(_), T), close(S), R = E-T), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s117(R) :- catch((rb(S), set_stream(S, encoding(utf8)), sp(S, encoding(_), E), sp(S, type(_), T), close(S), R = E-T), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s118(R) :- catch((ro(S), cerr(set_stream(S, encoding(bogus)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s119(R) :- catch((ro(S), cerr(set_stream(S, encoding(bom)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s120(R) :- catch((ro(S), set_stream(S, unicode_atoms(error)), sp(S, unicode_atoms(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s121(R) :- catch((ro(S), cerr(set_stream(S, unicode_atoms(bogus)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s122(R) :- catch((wo(S), set_stream(S, representation_errors(xml)), sp(S, representation_errors(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s123(R) :- catch((wo(S), set_stream(S, representation_errors(prolog)), sp(S, representation_errors(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s124(R) :- catch((wo(S), cerr(set_stream(S, representation_errors(bogus)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s125(R) :- catch((wo(S), set_stream(S, write_errors(ignore)), sp(S, write_errors(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s126(R) :- catch((wo(S), cerr(set_stream(S, write_errors(bogus)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s127(R) :- catch((wo(S), set_stream(S, newline(dos)), sp(S, newline(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s128(R) :- catch((wo(S), cerr(set_stream(S, newline(bad)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s129(R) :- catch((ro(S), cerr(set_stream(S, foo(x)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s130(R) :- catch((ro(S), cerr(set_stream(S, foo), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s131(R) :- catch((ro(S), cerr(set_stream(S, 1), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s132(R) :- catch((ro(S), cerr(set_stream(S, _), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s133(R) :- catch((cerr(set_stream(_, tty(true)), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s134(R) :- catch((cerr(set_stream(nosuch, tty(true)), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s135(R) :- catch((ro(S), close(S), cerr(set_stream(S, tty(true)), R)), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s136(R) :- catch((ro(S), set_stream(S, timeout(infinite)), sp(S, timeout(_), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
t_s137(R) :- catch((ro(S), cerr(set_stream(S, timeout(foo)), R0), close(S), R = R0), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).
