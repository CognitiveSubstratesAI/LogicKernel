# ORIGINAL: a LIVE differential of the atom and text built-ins (pl-prims.c, "ATOMS"; pl-text.c; registered by T1, R2, audit D-0149)
# test/core_text/test_atom_text_swipl.jl — atom_length/2, name/2, atom_codes/2, atom_chars/2, number_codes/2, number_chars/2,
# number_string/2, char_code/2, atom_concat/3 and atomic_concat/3 against swipl at the pin, through a PROGRAM (the pattern of
# test/core_lang/test_between_swipl.jl): each case is a predicate `rNNN(R)`; the kernel consults the program and enumerates every
# solution of every rNNN/1, swipl does the same through a driver, and the answers are compared as lines. EVERY expected value is
# swipl's own answer (the driver runs live); the white-box testset at the end has the few hand-derived values, each with its
# reason. The program is ASCII (non-ASCII texts are `\uXXXX` escapes), so swipl reads it whatever its locale. An error row reports
# its formal term, and the rows that name a predicate's context report it too (`pred/arity` or `system:pred/arity`, which one
# depends on whether upstream passes the name to `PL_error`). The groups: atom_length (the `iso`-flag-free ISO modes, text of a
# number, a list, `[]`), the `x_chars` family in every mode and error (instantiation, type, partial list, syntax errors, layout
# and signs, Unicode decimal digits through the `ENC_WCHAR` path), char_code/2, atom_concat/3 in all eight modes with the
# `REDO_INT` enumeration (a cut after the 2nd answer, an exception after a redo, shared variables, wide texts), atomic_concat/3.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"                       # (1.5 and -1.5 only: the same text in both)
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the kernel's lines
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# The rows. Each is `rNNN(R) :- Goal.` and has one solution list; a row that raises has the formal term in it. `\uXXXX` is
# U+XXXX: 65E5 65E5 672C are the two characters of 日本, 00E9 is é, 0661–0663 are the Arabic-Indic digits 1 2 3.
const _T1_PROGRAM = raw"""
% atom_length/2
r001(R) :- atom_length(abc, R).
r002(R) :- atom_length('', R).
r003(R) :- atom_length(123, R).
r004(R) :- atom_length(1.5, R).
r005(R) :- atom_length("héllo", R).
r006(R) :- atom_length([a,b,c], R).
r007(R) :- atom_length([], R).
r008(R) :- catch(atom_length(_, _), error(E, _), R = E).
r009(R) :- catch(atom_length(f(x), _), error(E, C), R = E-C).
r010(R) :- catch(atom_length(abc, foo), error(E, _), R = E).
r011(R) :- ( atom_length(abc, 3) -> R = yes ; R = no ).
r012(R) :- ( atom_length(abc, 4) -> R = yes ; R = no ).
r013(R) :- ( atom_length(abc, -1) -> R = yes ; R = no ).
r014(R) :- atom_length('日本語', R).
r015(R) :- atom_length(100000000000000000000, R).
r016(R) :- catch(atom_length(_, 3), error(E, _), R = E).
r017(R) :- catch(atom_length([a|_], _), error(E, _), R = E).
r018(R) :- catch(atom_length(abc, 1.5), error(E, _), R = E).
r019(R) :- atom_length("", R).
% atom_codes/2
r020(R) :- atom_codes(abc, R).
r021(R) :- atom_codes(R, [0'a, 0'b]).
r022(R) :- atom_codes(R, "abc").
r023(R) :- atom_codes(123, R).
r024(R) :- catch(atom_codes(_, _), error(E, C), R = E-C).
r025(R) :- catch(atom_codes(f(x), _), error(E, C), R = E-C).
r026(R) :- catch(atom_codes(_, [a|_]), error(E, _), R = E).
r027(R) :- catch(atom_codes(_, [0'a|b]), error(E, _), R = E).
r028(R) :- catch(atom_codes(_, [-1]), error(E, _), R = E).
r029(R) :- atom_codes(abc, [0'a|R]).
r030(R) :- ( atom_codes(abc, "abd") -> R = yes ; R = no ).
r031(R) :- atom_codes(abc, [X|Y]), R = X-Y.
r032(R) :- atom_codes('日本', R).
r033(R) :- atom_codes(R, [26085, 26412]).
r034(R) :- atom_codes('', R).
r035(R) :- atom_codes(R, []).
r036(R) :- ( atom_codes(abc, [0'x|_]) -> R = yes ; R = no ).
r037(R) :- atom_codes(1.5, R).
r038(R) :- atom_codes("str", R).
r039(R) :- atom_codes(R, "12"), atom(R).
r040(R) :- catch(atom_codes(_, [0'a, foo]), error(E, _), R = E).
r041(R) :- ( atom_codes(abc, [0'a, 0'b]) -> R = yes ; R = no ).
r042(R) :- ( atom_codes(abc, [0'a, 0'b, 0'c, 0'd]) -> R = yes ; R = no ).
r043(R) :- catch(atom_codes(abc, [0'a|foo]), error(E, _), R = E).
r044(R) :- catch(atom_codes([], _), error(E, _), R = E).
% atom_chars/2
r045(R) :- atom_chars(R, [a, b]).
r046(R) :- atom_chars(R, ['1', '2']), atom(R).
r047(R) :- atom_chars(123, R).
r048(R) :- atom_chars(abc, R).
r049(R) :- catch(atom_chars(_, [a, bc]), error(E, _), R = E).
r050(R) :- catch(atom_chars(_, _), error(E, _), R = E).
r051(R) :- catch(atom_chars(_, [a|_]), error(E, _), R = E).
r052(R) :- atom_chars('日本', R).
r053(R) :- atom_chars(R, ['日', '本']).
r054(R) :- atom_chars(abc, [a|R]).
r055(R) :- atom_chars(_, [0'a]), R = ok.
r056(R) :- catch(atom_chars(_, ["a"]), error(E, _), R = E).
r057(R) :- atom_chars(1.5, R).
r058(R) :- ( atom_chars(abc, [a, b, d]) -> R = yes ; R = no ).
% name/2
r059(R) :- name(R, "123"), integer(R).
r060(R) :- name(R, "abc").
r061(R) :- name(R, "12abc").
r062(R) :- name(R, " 12").
r063(R) :- name(123, R).
r064(R) :- name(foo, R).
r065(R) :- name(R, []).
r066(R) :- name(R, "1.5"), float(R).
r067(R) :- name(R, "0x1F").
r068(R) :- name(R, "-12").
r069(R) :- name(R, "0'a").
r070(R) :- name(R, "12 ").
r071(R) :- catch(name(_, _), error(E, _), R = E).
r072(R) :- catch(name(f(x), _), error(E, C), R = E-C).
r073(R) :- name(R, "1r3").
r074(R) :- name(R, "-").
r075(R) :- name(R, "+5").
r076(R) :- name(R0, "1e10"), ( float(R0), R0 =:= 1.0e10 -> R = ok ; R = bad ).
r077(R) :- name(R, "١٢٣").
r078(R) :- name(R, "abc١").
r079(R) :- name("str", R).
r080(R) :- name(R, "0b101").
r081(R) :- name(R, "1_000").
r082(R) :- name(R, "١x").
r083(R) :- name(R, "-١").
r084(R) :- name(R, "日本").
% number_codes/2
r085(R) :- number_codes(R, "42").
r086(R) :- number_codes(R, " 42").
r087(R) :- number_codes(R, "0x1F").
r088(R) :- catch(number_codes(_, "3x"), error(E, C), R = E-C).
r089(R) :- catch(number_codes(_, ""), error(E, _), R = E).
r090(R) :- number_codes(R, "-1").
r091(R) :- catch(number_codes(_, "- 1"), error(E, _), R = E).
r092(R) :- number_codes(R, "+1").
r093(R) :- number_codes(42, R).
r094(R) :- number_codes(1.5, R).
r095(R) :- catch(number_codes(abc, _), error(E, C), R = E-C).
r096(R) :- catch(number_codes(_, _), error(E, _), R = E).
r097(R) :- number_codes(R0, "1e10"), ( float(R0), R0 =:= 1.0e10 -> R = ok ; R = bad ).
r098(R) :- number_codes(1r3, R).
r099(R) :- number_codes(R, "1r3").
r100(R) :- number_codes(R, "١٢٣").
r101(R) :- number_codes(R, "0'a").
r102(R) :- number_codes(R, "  \n 7").
r103(R) :- catch(number_codes(_, "7 "), error(E, _), R = E).
r104(R) :- catch(number_codes(_, "٣x"), error(E, _), R = E).
r105(R) :- number_codes(-3, R).
r106(R) :- catch(number_codes(_, [0'1|_]), error(E, _), R = E).
r107(R) :- number_codes(R, "100000000000000000000").
r108(R) :- number_codes(R0, "1.0Inf"), ( float(R0), R0 > 1.0e308 -> R = inf ; R = other ).
r109(R) :- ( number_codes(12, "12") -> R = yes ; R = no ).
r110(R) :- ( number_codes(12, "13") -> R = yes ; R = no ).
r111(R) :- catch(number_codes(12, "abc"), error(E, C), R = E-C).
r112(R) :- number_codes(R, "-١٢").
r113(R) :- number_codes(R, " ١").
r114(R) :- number_codes(R, "+١").
r115(R) :- catch(number_codes(_, "- ١"), error(E, _), R = E).
r116(R) :- catch(number_codes(_, "日"), error(E, _), R = E).
r117(R) :- catch(number_codes(_, "é"), error(E, _), R = E).
r118(R) :- number_codes(R, "0'é").
% number_chars/2
r119(R) :- number_chars(R, ['4', '2']).
r120(R) :- number_chars(R, [' ', '4']).
r121(R) :- catch(number_chars(_, ['4', x]), error(E, C), R = E-C).
r122(R) :- catch(number_chars(_, ['4'|_]), error(E, _), R = E).
r123(R) :- number_chars(42, R).
r124(R) :- number_chars(R, ['-', '1', '.', '5']).
r125(R) :- catch(number_chars(_, ['1'|b]), error(E, _), R = E).
r126(R) :- catch(number_chars(_, [a|_]), error(E, _), R = E).
r127(R) :- catch(number_chars(_, ['1', 2]), error(E, _), R = E).
r128(R) :- number_chars(R, ['0', '''', a]).
r129(R) :- catch(number_chars(_, _), error(E, C), R = E-C).
r130(R) :- number_chars(1r3, R).
% number_string/2
r131(R) :- number_string(R, "42").
r132(R) :- ( number_string(R, " 42") -> true ; R = no ).
r133(R) :- ( number_string(R, "42 ") -> true ; R = no ).
r134(R) :- ( number_string(R, "abc") -> true ; R = no ).
r135(R) :- number_string(42, R).
r136(R) :- catch(number_string(_, _), error(E, _), R = E).
r137(R) :- catch(number_string(_, foo), error(E, _), R = E).
r138(R) :- ( number_string(R, "") -> true ; R = no ).
r139(R) :- number_string(R, "1.5"), float(R).
r140(R) :- number_string(R, [0'4, 0'2]).
r141(R) :- catch(number_string(abc, _), error(E, C), R = E-C).
r142(R) :- number_string(R, "-7").
r143(R) :- ( number_string(R, "- 7") -> true ; R = no ).
r144(R) :- ( number_string(7, "07") -> R = yes ; R = no ).
r145(R) :- catch(number_string(_, [a|_]), error(E, _), R = E).
r146(R) :- number_string(R, "٣").
r147(R) :- ( number_string(R, " ٣") -> true ; R = no ).
r148(R) :- number_string(-3, R).
r149(R) :- ( number_string(R, "日") -> true ; R = no ).
% char_code/2
r150(R) :- char_code(a, R).
r151(R) :- char_code(R, 0'a).
r152(R) :- ( char_code(a, 0'a) -> R = yes ; R = no ).
r153(R) :- ( char_code(a, 0'b) -> R = yes ; R = no ).
r154(R) :- catch(char_code(_, _), error(E, C), R = E-C).
r155(R) :- catch(char_code(ab, _), error(E, C), R = E-C).
r156(R) :- catch(char_code(_, -1), error(E, C), R = E-C).
r157(R) :- catch(char_code(_, a), error(E, C), R = E-C).
r158(R) :- catch(char_code(_, 1114112), error(E, _), R = E).
r159(R) :- char_code(R, 0x1F600).
r160(R) :- char_code('日', R).
r161(R) :- catch(char_code(1, _), error(E, _), R = E).
r162(R) :- catch(char_code(a, b), error(E, _), R = E).
r163(R) :- catch(char_code(_, 1.5), error(E, _), R = E).
r164(R) :- catch(char_code(_, 55296), error(E, _), R = E).
r165(R) :- catch(char_code([], _), error(E, _), R = E).
r166(R) :- catch(char_code(_, 100000000000000000000), error(E, _), R = E).
r168(R) :- char_code(R, 233).
% atom_concat/3: the modes
r169(R) :- atom_concat(abc, def, R).
r170(R) :- atom_concat(abc, R, abcdef).
r171(R) :- atom_concat(R, def, abcdef).
r172(R) :- findall(A-B, atom_concat(A, B, abc), R).
r173(R) :- findall(A-B, atom_concat(A, B, ''), R).
r174(R) :- ( atom_concat(abc, def, abcdef) -> R = yes ; R = no ).
r175(R) :- ( atom_concat(abc, def, abcdeg) -> R = yes ; R = no ).
r176(R) :- ( atom_concat(abc, def, abcdefg) -> R = yes ; R = no ).
r177(R) :- ( atom_concat(abc, def, abcde) -> R = yes ; R = no ).
r178(R) :- findall(X, atom_concat(X, X, abab), R).
r179(R) :- findall(X, atom_concat(X, X, abc), R).
r180(R) :- findall(X, atom_concat(X, X, abba), R).
r181(R) :- atom_concat(1, 2, R), atom(R).
r182(R) :- atom_concat(a, 1.5, R).
r183(R) :- atom_concat("a", "b", R), atom(R).
r184(R) :- catch(atom_concat(_, _, _), error(E, C), R = E-C).
r185(R) :- catch(atom_concat(_, b, _), error(E, _), R = E).
r186(R) :- catch(atom_concat(f(x), b, _), error(E, C), R = E-C).
r187(R) :- catch(atom_concat(a, b, f(x)), error(E, _), R = E).
r188(R) :- ( atom_concat(abc, _, ab) -> R = yes ; R = no ).
r189(R) :- ( atom_concat(_, abc, ab) -> R = yes ; R = no ).
r190(R) :- ( atom_concat(abc, _, abd) -> R = yes ; R = no ).
r191(R) :- ( atom_concat(_, abc, xbc) -> R = yes ; R = no ).
r192(R) :- atom_concat('日', R, '日本').
r193(R) :- findall(A-B, atom_concat(A, B, '日本語'), R).
r194(R) :- findall(A-B, atom_concat(A, B, 123), R).
% atom_concat/3: the REDO_INT enumeration
r195(R) :- ( atom_concat(A, B, abc), A == a -> R = A-B ; R = none ).
r196(R) :- ( atom_concat(A, B, abcd), atom_length(A, 2) -> R = A-B ; R = none ).
r197(R) :- catch(( atom_concat(A, B, abc), A == ab, throw(stop(B)) ), stop(Y), R = Y).
r198(R) :- atom_concat(A, B, abc), A \== '', B \== '', R = A-B.
r199(R) :- findall(A-B-C-D, ( atom_concat(A, B, ab), atom_concat(C, D, cd) ), R).
r200(R) :- atom_concat(abc, '', R).
r201(R) :- atom_concat('', '', R).
r202(R) :- catch(atom_concat([], a, _), error(E, C), R = E-C).
r203(R) :- findall(A-B, atom_concat(A, B, '[]'), R).
r204(R) :- atom_concat(R, '日本', 'abc日本').
r205(R) :- atom_concat('日', '本', R).
r206(R) :- ( atom_concat('日', '本', '日本') -> R = yes ; R = no ).
r207(R) :- findall(A, atom_concat(A, _, ab), R).
r208(R) :- findall(B, atom_concat(_, B, ab), R).
r209(R) :- atom_concat(1, R, '12'), atom(R).
r210(R) :- atom_concat(R, 2, 12), atom(R).
r211(R) :- catch(atom_concat(a, _, _), error(E, _), R = E).
r212(R) :- catch(atom_concat(_, a, _), error(E, _), R = E).
r213(R) :- catch(atom_concat(a, f(x), _), error(E, C), R = E-C).
r214(R) :- catch(atom_concat([a], b, _), error(E, _), R = E).
r215(R) :- findall(A-B, atom_concat(A, B, 'é日'), R).
r216(R) :- findall(X, ( atom_concat(X, Y, abcd), atom_concat(Y, Z, abcd), X == Z ), R).
r217(R) :- atom_concat(A, B, abc), atom_length(A, 1), R = A-B.
r218(R) :- ( atom_concat(X, Y, ab), Y == b -> R = X ; R = none ).
r219(R) :- ( atom_concat(X, Y, abc), X == ab, Y == c -> R = yes ; R = no ).
r220(R) :- findall(A-B, atom_concat(A, B, "ab"), R).
r221(R) :- findall(A-B, ( atom_concat(A, B, ab), ! ), R).
r222(R) :- atom_concat(abc, X, abc), R = X.
r223(R) :- findall(X, atom_concat(X, abc, abc), R).
r224(R) :- findall(A-B, atom_concat(A, B, abcdefghij), R).
r225(R) :- findall(A-B, ( atom_concat(A, B, abcd), atom_length(A, N), N > 1 ), R).
r226(R) :- catch(( atom_concat(A, B, abc), A == ab, B = c, throw(found) ), found, R = ok).
% atomic_concat/3 (deterministic: -,-,+ is an instantiation error)
r227(R) :- atomic_concat(a, b, R).
r228(R) :- catch(atomic_concat(a, _, _), error(E, C), R = E-C).
r229(R) :- catch(atomic_concat(_, _, abc), error(E, _), R = E).
r230(R) :- ( atomic_concat(a, b, ab) -> R = yes ; R = no ).
r231(R) :- ( atomic_concat(a, b, ac) -> R = yes ; R = no ).
r232(R) :- atomic_concat(1, 2, R), atom(R).
"""

@testset "the atom and text built-ins == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ATOM-TEXT DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = String[m.captures[1] for m in eachmatch(r"^(r\d+)\(R\) :-"m, _T1_PROGRAM)]
        f = joinpath(mktempdir(), "p.pl")
        write(f, _T1_PROGRAM)
        sw = swipl_lines(f, names)
        kl = kernel_lines(f, names)
        @test length(names) >= 200
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        # compared per row, so a failure names its case
        @test length(kl) == length(sw)
        for i in 1:min(length(kl), length(sw))
            @test (i, kl[i]) == (i, sw[i])
        end
        # not a vacuous agreement: error rows, enumeration rows, a syntax error and a cut are in swipl's own lines
        nerr = count(
            l ->
                occursin("101,114,114,111,114", l) ||
                occursin("115,121,110,116,97,120", l) ||
                occursin("105,110,115,116,97,110,116", l) || occursin("116,121,112,101", l),
            sw)
        @test nerr >= 40                                        # …rror / syntax… / instantiation… / type_error atoms
        @test any(l -> startswith(l, "r172 ") && count("c[45]/2(", l) == 4, sw)  # atom_concat(A, B, abc): four splits
        @test any(l -> startswith(l, "r178 ") && occursin("a[97,98]", l), sw)    # atom_concat(X, X, abab): X = ab
        @test any(l -> startswith(l, "r097 ") && occursin("a[111,107]", l), sw)  # number_codes: 1e10 is a float
        @test count(l -> occursin(" exception", l), sw) == 0                      # no row leaks an exception
    end
end

# The white-box side of atom_concat/3's REDO_INT context (pl-prims.c `concat`, `ForeignRedoInt(at_n+1)`), queried directly. The
# values are derived from the upstream code, which no swipl query can show: after the answer for the split at position at_n the
# context is at_n+1, and the answer for at_n == length(Text) is the last (no `ForeignRedoInt`), so a deterministic exit.
@testset "atom_concat/3 queried directly: the retry carries the next position as REDO_INT" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.isCurrentProcedure(sym_key(_tls("atom_concat")), 3, LK.MODULE_system(gd))
    @test proc !== nothing
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 3, _tls("abc"), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    d = proc.definition
    # atom_concat/3 is PRED_IMPL (VARARGS), non-deterministic: upstream's five-word supervisor (pl-supervisor.c)
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDETVA,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    got = Tuple{String, String}[]
    rcs = Int[]
    ctxs = Int[]
    while length(got) < 10
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(rcs, rc)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        ans = lk_answers(ld, a, a + 1)
        push!(got, (String(sym_text(ans[1])), String(sym_text(ans[2]))))
        rc == LK.PL_S_LAST && break
        c = ld.choices[ld.BFR]
        @test c.type == LK.CHP_JUMP
        fctx = ld.frames[c.frame].fctx
        @test (fctx & LK.FRG_REDO_MASK) == LK.REDO_INT
        push!(ctxs, Int(fctx >> LK.FRG_REDO_BITS))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test ctxs == [1, 2, 3]
    @test rcs == [LK.PL_S_TRUE, LK.PL_S_TRUE, LK.PL_S_TRUE, LK.PL_S_LAST]
    # the splits, in order: the same four as swipl's r172 (the differential above compares them to swipl's own)
    @test [x[1] * x[2] for x in got] == fill("abc", 4)
    @test [length(x[1]) for x in got] == [0, 1, 2, 3]
end

# The same, closing the query with the REDO_INT frame live: FRG_CUTTED is called with the context, which `concat` never reads, and
# the frame's context is cleared (pl-wam.c discardForeignFrame).
@testset "atom_concat/3: a query closed after the first answer discards its REDO_INT frame" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.isCurrentProcedure(sym_key(_tls("atom_concat")), 3, LK.MODULE_system(gd))
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 3, _tls("abc"), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    fr = ld.choices[ld.BFR].frame
    @test ld.frames[fr].fctx != 0 && (ld.frames[fr].fctx & LK.FRG_REDO_MASK) == LK.REDO_INT
    LK.discardFrame(ld, fr)
    @test ld.frames[fr].fctx == 0
    LK.discardFrame(ld, fr)                                 # a second discard is a no-op
    @test ld.frames[fr].fctx == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
