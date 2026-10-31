% string_bytes/3, encoding
su001(R) :- string_bytes("abc", R, utf8).
su002(R) :- string_bytes("é", R, utf8).
su003(R) :- string_bytes("€", R, utf8).
su004(R) :- string_bytes("é", R, iso_latin_1).
su005(R) :- string_bytes("é", R, octet).
su006(R) :- catch(string_bytes("€", _, iso_latin_1), error(E, C), R = E-C).
su007(R) :- catch(string_bytes("€", _, octet), error(E, C), R = E-C).
su008(R) :- catch(string_bytes("é", _, ascii), error(E, C), R = E-C).
su009(R) :- string_bytes("a", R, ascii).
su010(R) :- string_bytes("aé€", R, utf16le).
su011(R) :- string_bytes("aé€", R, utf16be).
su012(R) :- string_bytes("", R, utf16le).
su013(R) :- string_bytes("\U0001F600", R, utf16le).
su014(R) :- string_bytes("\U0001F600", R, utf16be).
su015(R) :- string_bytes("\U0001F600", R, utf8).
su016(R) :- string_bytes(abc, R, utf8).
su017(R) :- string_bytes([0'a, 0'b], R, octet).
su018(R) :- string_bytes([a, b], R, iso_latin_1).
su019(R) :- catch(string_bytes(12, _, utf8), error(E, C), R = E-C).
su020(R) :- catch(string_bytes(f(x), _, utf8), error(E, C), R = E-C).
su021(R) :- catch(string_bytes(_, _, utf8), error(E, C), R = E-C).
su022(R) :- catch(string_bytes("a", _, foo), error(E, C), R = E-C).
su023(R) :- catch(string_bytes("a", _, wchar_t), error(E, C), R = E-C).
su024(R) :- catch(string_bytes("a", _, 1), error(E, C), R = E-C).
su025(R) :- catch(string_bytes("a", _, _), error(E, C), R = E-C).
su026(R) :- string_bytes(abc, R, 'UTF-8').
su027(R) :- string_bytes("é", R, 'ISO-8859-1').
su028(R) :- string_bytes("é", R, utf16be), R = [_, _].
% string_bytes/3, decoding
su029(R) :- string_bytes(R, [0xe2, 0x82, 0xac], utf8).
su030(R) :- string_bytes(R, [0xc3, 0xa9], utf8), string_length(R, N).
su031(R) :- string_bytes(R, [0xff, 0xfe], utf8), string_length(R, N).
su032(R) :- string_bytes(R, [0xe2, 0x82], utf8).
su033(R) :- string_bytes(R, [0xc3, 0xa9], octet), string_length(R, N).
su034(R) :- string_bytes(R, [200], iso_latin_1).
su035(R) :- string_bytes(R, [0, 0x61, 0x20, 0xac], utf16be).
su036(R) :- string_bytes(R, [0x61, 0, 0xac, 0x20], utf16le).
su037(R) :- string_bytes(R, [0x00, 0xd8], utf16be), string_length(R, N).
su038(R) :- string_bytes(R, [0x61, 0, 0x62, 0], utf16le), string_length(R, N).
su039(R) :- catch(string_bytes(_, [1, 2, 3], utf16le), error(E, C), R = E-C).
su040(R) :- catch(string_bytes(_, [0xd8, 0, 0, 0x41], utf16be), error(E, C), R = E-C).
su041(R) :- catch(string_bytes(_, [0xd8, 0, 0xdc, 0], utf16be), error(E, C), R = E-C).
su042(R) :- catch(string_bytes(_, [0x3d, 0xd8, 0, 0xde], utf16le), error(E, C), R = E-C).
su043(R) :- catch(string_bytes(_, [300], utf8), error(E, C), R = E-C).
su044(R) :- string_bytes(R, [a], utf8).
su045(R) :- string_bytes(R, [], utf8), string(R).
su046(R) :- catch(string_bytes(_, [-1], utf8), error(E, C), R = E-C).
su047(R) :- catch(string_bytes(_, foo, utf8), error(E, C), R = E-C).
su048(R) :- catch(string_bytes(_, "abc", utf8), error(E, C), R = E-C).
su049(R) :- catch(string_bytes(_, [0'a|_], utf8), error(E, C), R = E-C).
su050(R) :- catch(string_bytes(_, _, utf8), error(E, C), R = E-C).
su051(R) :- ( string_bytes("ab", [97, 98], utf8) -> R = yes ; R = no ).
su052(R) :- ( string_bytes("ab", [97], utf8) -> R = yes ; R = no ).
su053(R) :- string_bytes("€", [0xe2, 0x82, 0xac], utf8), R = ok.
su054(R) :- catch(string_bytes(_, [0, 0, 0, 65], wchar_t), error(E, C), R = E-C).
su055(R) :- string_bytes(S, [0x41, 0, 0x42, 0], utf16le), string_codes(S, R).
% open_string/2, read_string/3
su056(R) :- open_string("hello world", S), read_string(S, 5, R).
su057(R) :- open_string("hello", S), read_string(S, L, R0), R = L-R0.
su058(R) :- open_string("hello", S), read_string(S, 0, R).
su059(R) :- open_string("hi", S), read_string(S, 5, R).
su060(R) :- open_string("", S), read_string(S, L, R0), R = L-R0.
su061(R) :- open_string(abc, S), read_string(S, 2, R).
su062(R) :- open_string([0'a, 0'b], S), read_string(S, 2, R).
su063(R) :- open_string("hello", S), read_string(S, 2, A), read_string(S, 2, B), read_string(S, 2, C), R = [A, B, C].
su064(R) :- open_string("日本", S), read_string(S, L, R0), string_length(R0, N), R = L-N.
su065(R) :- open_string("aéb", S), read_string(S, 2, R0), string_codes(R0, R).
su066(R) :- catch(open_string(f(x), _), error(E, C), R = E-C).
su067(R) :- catch(open_string(_, _), error(E, C), R = E-C).
su068(R) :- open_string("abc", S), catch(read_string(S, foo, _), error(E, C), R = E-C).
su069(R) :- open_string("abc", S), catch(read_string(S, -1, _), error(E, _), R = E).
su070(R) :- catch(read_string(no_such_stream, 1, _), error(E, _), R = E).
su071(R) :- open_string("abc", S), ( read_string(S, 2, "ab") -> R = yes ; R = no ).
su072(R) :- open_string("abc", S), ( read_string(S, 2, "xy") -> R = yes ; R = no ).
su073(R) :- open_string("abc", S), read_string(S, L, "abc"), R = L.
% read_string/5
su074(R) :- open_string("a,b,c", S), read_string(S, ",", "", D1, R1), read_string(S, ",", "", D2, R2), read_string(S, ",", "", D3, R3), R = [D1-R1, D2-R2, D3-R3].
su075(R) :- open_string("  hi  \nrest", S), read_string(S, "\n", " ", D, R0), R = D-R0.
su076(R) :- open_string("", S), read_string(S, "\n", "", D, R0), R = D-R0.
su077(R) :- open_string("abc", S), read_string(S, "", "", D, R0), R = D-R0.
su078(R) :- open_string("a;b,c", S), read_string(S, ",;", "", D, R0), R = D-R0.
su079(R) :- open_string("a,b", S), ( read_string(S, ",", "", 0',, R0) -> R = R0 ; R = no ).
su080(R) :- open_string("a,b", S), ( read_string(S, ",", "", 0';, _) -> R = yes ; R = no ).
su081(R) :- open_string("   ", S), read_string(S, ",", " ", D, R0), R = D-R0.
su082(R) :- open_string("x  ,y", S), read_string(S, ",", " ", D, R0), R = D-R0.
su083(R) :- open_string("日本,b", S), read_string(S, ",", "", D, R0), string_length(R0, N), R = D-N.
su084(R) :- open_string("aé,b", S), read_string(S, "é", "", D, R0), R = D-R0.
su085(R) :- open_string("..a..", S), read_string(S, ",", ".", D, R0), R = D-R0.
su086(R) :- open_string("abc", S), read_string(S, [0',], [0' ], D, R0), R = D-R0.
su087(R) :- catch(read_string(no_such_stream, "", "", _, _), error(E, _), R = E).
su088(R) :- open_string("abc", S), catch(read_string(S, f(x), "", _, _), error(E, C), R = E-C).
su089(R) :- open_string("abc", S), catch(read_string(S, "", f(x), _, _), error(E, C), R = E-C).
su090(R) :- open_string("ab\ncd\n", S), read_string(S, "\n", "\r", D1, R1), read_string(S, "\n", "\r", D2, R2), read_string(S, "\n", "\r", D3, R3), R = [D1-R1, D2-R2, D3-R3].
su091(R) :- open_string("aéé,b", S), read_string(S, ",", "é", D, R0), R = D-R0.
