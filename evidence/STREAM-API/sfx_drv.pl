pos(S, R) :- stream_property(S, position(P)),
    stream_position_data(byte_count, P, B), stream_position_data(char_count, P, C),
    stream_position_data(line_count, P, L), stream_position_data(line_position, P, LP),
    R = [B,C,L,LP].
wc(Codes, R) :- tmp_file(sf, F), open(F, write, O, [encoding(utf8)]), forall(member(X, Codes), put_char(O, X)), pos(O, R), close(O), delete_file(F).
run :- forall(member(Cs, [[a,b,'\n',c,d,'\t',e], ['\n','\n',x], [x,'\b',y], [a,'\r',b]]), (wc(Cs, R), format("wc ~q ~w~n", [Cs, R]))).
:- initialization((run, halt)).
