# ORIGINAL: a differential of the string predicates against swipl 10.1.19 (pl-string.c, and pl-prims.c's string_length/2, string_concat/3,
# sub_string/5; registered by T2, R2). Two programs of cases, as clauses of a consulted file: `stNNN(R)` rows (split_string/4, atom_string/2,
# string_codes/2, string_chars/2, text_to_string/2, string_length/2, string_concat/3, sub_string/5, string_code/3, get_string_code/3) and
# `suNNN(R)` rows (string_bytes/3, open_string/2, read_string/3, read_string/5). The kernel consults each program and enumerates every
# solution of every row, encoded as the driver's `enc/1` does; the lines are compared with swipl's own, PINNED below
# (swipl 10.1.19, the programs and the driver in this file, run twice with byte-identical output: lk-channel evidence/T2/t2_rows*.out of the
# T2 branch, generator evidence/T2/gen_rows.py); with `swipl` on PATH the live answers are compared with the pins too. The programs are ASCII
# (non-ASCII texts are `\uXXXX` escapes), so swipl reads them whatever its locale. An error row reports its formal term (`E`) or the term and
# the context (`E-C`) where the context is part of the contract. The upstream quirk of sub_atom/sub_string with the SAME variable as Before
# and After (`sub_string("abab", X, 2, X, "ab")`: the last candidate of the search is returned without its unification being checked) is
# pinned in the sub_string rows: the port is 1:1, so the kernel answers as swipl does.
# UNVERIFIED on the kernel: gate decides — nothing of this file has run on the kernel yet; the `su` rows also rest on the stream layer
# (getTextInputStream, Sgetcode, Sopenmem, PL_unify_stream) that T2 only uses. Not in the rows: the encoding `text` (ENC_ANSI, the locale:
# refused by name by the kernel) and a decode with `ascii` (swipl 10.1.19 fails an assertion in pl-text.c there).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _ST = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_st_sym(x) = lk_sym(_ST, Symbol(x))

_st_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _st_enc(t::_ST, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _st_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _st_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _st_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_st_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end


"The driver's line for the list of the integers `xs`."
_st_list(xs::Vector{Int}) = foldr((x, acc) -> "c[91,124,93]/2(i$x,$acc)", xs; init="nil")
"The driver's encoding of a compound `name/arity` up to its open parenthesis."
_st_c(name::String, arity::Int) = "c" * _st_codes(name) * "/$arity("
"The driver's encoding of the atom `name`."
_st_a(name::String) = "a" * _st_codes(name)
"The driver's line of the row `row` whose single answer is the encoded term `ans`."
_st_line(row::String, ans::String) = "$row $(_st_c(row, 1))$ans)"

# the kernel's lines: consult the file, then every solution of every row (at most 50), as the swipl driver prints them
function _st_kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_ST}()
    ld = LK.PL_local_data{_ST}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _st_enc(ball::_ST)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_st_sym(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_ST, LK.fresh_var_keys!(1)), pvm)
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
                        _st_enc(mk_expr(_ST, _ST[_st_sym(name), lk_answers(ld, (a:a)...)...]))
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

# the swipl side: consult, then every answer of each row (findnsols 50), `enc`oded; the same extractor as the kernel's
const _ST_DRIVER = raw"""
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
function _st_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _ST_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# The rows. `\uXXXX` is U+XXXX: 65E5 672C 8A9E are the characters of 日本語, 00E9 is é, 20AC is €; `\U0001F600` is an astral character.
const _ST_PROGRAM = raw"""
% split_string/4
st001(R) :- split_string("a.b.c", ".", "", R).
st002(R) :- split_string("/home//jan///nice/path", "/", "", R).
st003(R) :- split_string(" a b ", " ", "", R).
st004(R) :- split_string("  a  ", "", " ", R).
st005(R) :- split_string("//a//b//", "/", "/", R).
st006(R) :- split_string("", "", "", R).
st007(R) :- split_string("", ",", "", R).
st008(R) :- split_string("abc", "", "", R).
st009(R) :- split_string("   ", " ", " ", R).
st010(R) :- split_string("a b  c", " ", " ", R).
st011(R) :- split_string("SWI-Prolog, 7.0", ",", " ", R).
st012(R) :- string_codes(S, [0'a, 0, 0'b]), split_string(S, "", "", R).
st013(R) :- string_codes(S, [0'a, 0, 0'b]), split_string(S, "b", "", R).
st014(R) :- split_string(abc, "b", "", R).
st015(R) :- split_string([0'a, 0',, 0'b], ",", "", R).
st016(R) :- split_string("a,b", [0',], "", R).
st017(R) :- split_string("a.b", ".", "", [A|B]), R = A-B.
st018(R) :- catch(split_string(f(x), ".", "", _), error(E, C), R = E-C).
st019(R) :- catch(split_string(_, ".", "", _), error(E, _), R = E).
st020(R) :- catch(split_string("a", _, "", _), error(E, _), R = E).
st021(R) :- catch(split_string("a", ".", _, _), error(E, _), R = E).
st022(R) :- catch(split_string(123, "2", "", R), error(E, _), R = E).
st023(R) :- split_string("日本語", "本", "", R).
st024(R) :- ( split_string("a.b", ".", "", ["a", "b"]) -> R = yes ; R = no ).
st025(R) :- ( split_string("a.b", ".", "", ["a"]) -> R = yes ; R = no ).
st026(R) :- split_string("  a.b  ", ".", " ", R).
st027(R) :- split_string("abc", "abc", "", R).
st028(R) :- split_string("a  b", " ", "", R).
st029(R) :- split_string(" . ", ".", " ", R).
st030(R) :- split_string("..", ".", "", R).
st031(R) :- split_string("/home//jan///nice/path", "/", "", L), length(L, R).
st032(R) :- split_string("a.b.c", ".", "", [_, M|_]), string(M), R = M.
st033(R) :- catch(split_string("a", "b", [f(x)], _), error(E, _), R = E).
st034(R) :- split_string("abc", "", "abc", R).
st035(R) :- split_string("éaé", "a", "é", R).
% atom_string/2
st036(R) :- atom_string(abc, R).
st037(R) :- atom_string(R, "abc").
st038(R) :- atom_string(123, R).
st039(R) :- atom_string(R, "123"), atom(R).
st040(R) :- atom_string(1.5, R).
st041(R) :- atom_string("str", R).
st042(R) :- catch(atom_string(_, _), error(E, C), R = E-C).
st043(R) :- catch(atom_string(f(x), _), error(E, C), R = E-C).
st044(R) :- catch(atom_string(_, f(x)), error(E, C), R = E-C).
st045(R) :- ( atom_string(abc, "abc") -> R = yes ; R = no ).
st046(R) :- ( atom_string(abc, "abd") -> R = yes ; R = no ).
st047(R) :- ( atom_string(abc, abc) -> R = yes ; R = no ).
st048(R) :- atom_string([], R).
st049(R) :- atom_string(R, []).
st050(R) :- atom_string(R, [0'a, 0'b]).
st051(R) :- atom_string("日本", R).
st052(R) :- atom_string(R, "日本").
st053(R) :- ( atom_string(abc, 12) -> R = yes ; R = no ).
st054(R) :- atom_string(R, 12), atom(R).
st055(R) :- atom_string(A, "x y"), atom_length(A, R).
st056(R) :- atom_string(abc, S), string(S), R = S.
% string_codes/2, string_chars/2, text_to_string/2
st057(R) :- string_codes("abc", R).
st058(R) :- string_codes(R, [0'a, 0'b]), string(R).
st059(R) :- string_codes(abc, R).
st060(R) :- string_codes(12, R).
st061(R) :- catch(string_codes(_, _), error(E, C), R = E-C).
st062(R) :- string_codes(R, "ab").
st063(R) :- catch(string_codes(f(x), _), error(E, C), R = E-C).
st064(R) :- catch(string_codes(_, [a]), error(E, _), R = E).
st065(R) :- catch(string_codes(_, [-1]), error(E, _), R = E).
st066(R) :- catch(string_codes(_, [0'a|_]), error(E, _), R = E).
st067(R) :- string_codes("abc", [0'a|R]).
st068(R) :- ( string_codes("abc", [0'x|_]) -> R = yes ; R = no ).
st069(R) :- string_codes("", R).
st070(R) :- string_codes(R, []), string(R).
st071(R) :- string_codes("日本", R).
st072(R) :- string_codes(R, [26085, 26412]), string_length(R, N).
st073(R) :- string_chars("abc", R).
st074(R) :- string_chars(R, [a, b]), string(R).
st075(R) :- string_chars(abc, R).
st076(R) :- string_chars(12, R).
st077(R) :- catch(string_chars(_, _), error(E, C), R = E-C).
st078(R) :- catch(string_chars(_, [a, bc]), error(E, _), R = E).
st079(R) :- string_chars("日本", R).
st080(R) :- string_chars(R, ['日']), string_length(R, N).
st081(R) :- string_chars("abc", [a|R]).
st082(R) :- text_to_string(abc, R).
st083(R) :- text_to_string("str", R).
st084(R) :- text_to_string([0'a, 0'b], R).
st085(R) :- text_to_string([a, b], R).
st086(R) :- catch(text_to_string(12, _), error(E, C), R = E-C).
st087(R) :- catch(text_to_string(_, _), error(E, C), R = E-C).
st088(R) :- catch(text_to_string(f(x), _), error(E, C), R = E-C).
st089(R) :- text_to_string([], R).
st090(R) :- ( text_to_string(abc, "abc") -> R = yes ; R = no ).
st091(R) :- text_to_string('日本', R).
st092(R) :- text_to_string("s", S), string(S), R = S.
% string_length/2
st093(R) :- string_length("abc", R).
st094(R) :- string_length(abc, R).
st095(R) :- string_length(123, R).
st096(R) :- string_length(1.5, R).
st097(R) :- string_length([a, b, c], R).
st098(R) :- string_length([], R).
st099(R) :- string_length("", R).
st100(R) :- string_length("日本語", R).
st101(R) :- catch(string_length(f(x), _), error(E, C), R = E-C).
st102(R) :- catch(string_length(_, _), error(E, C), R = E-C).
st103(R) :- ( string_length("abc", 3) -> R = yes ; R = no ).
st104(R) :- ( string_length("abc", 4) -> R = yes ; R = no ).
st105(R) :- catch(string_length("abc", foo), error(E, _), R = E).
st106(R) :- ( string_length("abc", -1) -> R = yes ; R = no ).
st107(R) :- catch(string_length("abc", 1.5), error(E, _), R = E).
st108(R) :- string_length([0'a, 0'b], R).
st109(R) :- catch(string_length([a|_], _), error(E, _), R = E).
% string_concat/3
st110(R) :- string_concat(abc, def, R).
st111(R) :- string_concat("a", "b", R), string(R).
st112(R) :- string_concat(1, 2, R), string(R).
st113(R) :- string_concat(a, R, abc).
st114(R) :- string_concat(R, c, abc).
st115(R) :- string_concat(a, R, "abc"), string(R).
st116(R) :- findall(X-Y, string_concat(X, Y, "abc"), R).
st117(R) :- findall(X-Y, string_concat(X, Y, abc), R).
st118(R) :- ( string_concat("ab", "c", "abc") -> R = yes ; R = no ).
st119(R) :- ( string_concat(a, b, ac) -> R = yes ; R = no ).
st120(R) :- catch(string_concat(_, _, _), error(E, C), R = E-C).
st121(R) :- catch(string_concat(f(x), b, _), error(E, C), R = E-C).
st122(R) :- catch(string_concat(a, _, _), error(E, _), R = E).
st123(R) :- findall(X, string_concat(X, X, "abab"), R).
st124(R) :- findall(X, string_concat(X, X, "abc"), R).
st125(R) :- string_concat("", "", R), string_length(R, 0).
st126(R) :- catch(string_concat([0'a], [0'b], R), error(E, _), R = E).
st127(R) :- string_concat("日", "本", R), string_length(R, N).
st128(R) :- findall(X-Y, string_concat(X, Y, "日本"), L), length(L, R).
st129(R) :- string_concat(abc, R, "abcdef").
st130(R) :- ( string_concat(abc, R, "xbcdef") -> true ; R = no ).
st131(R) :- string_concat(R, "", "abc").
% sub_string/5
st132(R) :- sub_string("hello", 1, 3, A, R).
st133(R) :- sub_string("hello", B, 2, 0, R).
st134(R) :- sub_string("hello", B, L, 0, "llo"), R = B-L.
st135(R) :- findall(B-A, sub_string("hello", B, _, A, "l"), R).
st136(R) :- sub_string("hello", 0, L, 0, R).
st137(R) :- findall(B-L-A-S, sub_string("abc", B, L, A, S), R).
st138(R) :- sub_string(abc, 1, 1, 1, R).
st139(R) :- findall(B-L-A, sub_string("abc", B, L, A, ""), R).
st140(R) :- ( sub_string("abc", 4, _, _, _) -> R = yes ; R = no ).
st141(R) :- catch(( sub_string("abc", -1, _, _, _) -> R = yes ; R = no ), error(E, _), R = E).
st142(R) :- catch(sub_string("abc", foo, _, _, _), error(E, _), R = E).
st143(R) :- catch(sub_string(_, _, _, _, _), error(E, C), R = E-C).
st144(R) :- catch(sub_string(f(x), _, _, _, _), error(E, C), R = E-C).
st145(R) :- sub_string("abc", B, 1, 0, R).
st146(R) :- findall(L-A-S, sub_string("abc", 1, L, A, S), R).
st147(R) :- findall(B-A, sub_string("abab", B, 2, A, "ab"), R).
st148(R) :- findall(B-A, sub_string("aaaa", B, 2, A, "aa"), R).
st149(R) :- sub_string("abc", 0, _, 0, R).
st150(R) :- ( sub_string("abc", _, _, _, "abcd") -> R = yes ; R = no ).
st151(R) :- sub_string("abc", 3, 0, A, R), A = 0.
st152(R) :- ( sub_string("abc", 1, 5, _, _) -> R = yes ; R = no ).
st153(R) :- sub_string("日本語", 1, 1, A, S), string_length(S, N), R = A-N.
st154(R) :- findall(B, sub_string("abab", B, _, _, abab), R).
st155(R) :- findall(X, sub_string("abab", X, 2, X, "ab"), R).
st156(R) :- findall(X-S, sub_string("abab", X, 2, X, S), R).
st157(R) :- findall(X, sub_string("abcba", X, _, X, "b"), R).
st158(R) :- findall(X-L-S, sub_string("abcba", X, L, X, S), R).
st159(R) :- findall(X-S, sub_string("abc", X, 1, X, S), R).
st160(R) :- findall(X-S, sub_string("abcd", X, 1, X, S), R).
st161(R) :- findall(X, sub_string("abab", X, 2, X, "ba"), R).
st162(R) :- findall(X-Y, sub_string("abab", X, Y, X, "ab"), R).
st163(R) :- findall(X-A, sub_string("aaa", X, 1, A, "a"), R).
st164(R) :- findall(X, sub_string("abab", X, 2, X, abab), R).
st165(R) :- catch(sub_string("abc", 1, -1, _, _), error(E, _), R = E).
st166(R) :- findall(S, sub_string("ab", _, _, _, S), L), msort(L, R).
st167(R) :- sub_string(abc, B, _, 0, "c"), R = B.
st168(R) :- catch(sub_string("abc", _, _, _, f(x)), error(E, _), R = E).
st169(R) :- sub_string("abc", 1, 1, _, b), R = ok.
st170(R) :- ( sub_string("abc", _, _, _, 1) -> R = yes ; R = no ).
% string_code/3
st171(R) :- string_code(1, "abc", R).
st172(R) :- string_code(3, "abc", R).
st173(R) :- ( string_code(0, "abc", _) -> R = yes ; R = no ).
st174(R) :- ( string_code(4, "abc", _) -> R = yes ; R = no ).
st175(R) :- catch(( string_code(-1, "abc", _) -> R = yes ; R = no ), error(E, _), R = E).
st176(R) :- findall(I-C, string_code(I, "abc", C), R).
st177(R) :- string_code(I, "abc", 0'b), R = I.
st178(R) :- findall(I, string_code(I, "abca", 0'a), R).
st179(R) :- string_code(1, abc, R).
st180(R) :- string_code(2, "abc", b), R = ok.
st181(R) :- catch(string_code(_, "abc", foo), error(E, _), R = E).
st182(R) :- catch(string_code(a, "abc", _), error(E, _), R = E).
st183(R) :- catch(string_code(1, f(x), _), error(E, _), R = E).
st184(R) :- catch(string_code(_, _, _), error(E, C), R = E-C).
st185(R) :- ( string_code(1, "abc", 0'a) -> R = yes ; R = no ).
st186(R) :- ( string_code(1, "abc", 0'b) -> R = yes ; R = no ).
st187(R) :- catch(string_code(1.5, "abc", _), error(E, _), R = E).
st188(R) :- X is 1 << 70, catch(string_code(X, "abc", _), error(E, _), R = E).
st189(R) :- ( string_code(1, "abc", -1) -> R = yes ; R = no ).
st190(R) :- findall(I, string_code(I, "", _), R).
st191(R) :- findall(I-C, string_code(I, "日本", C), R).
st192(R) :- string_code(I, "abc", 0'c), R = I.
st193(R) :- ( string_code(I, "abc", 0'z) -> R = I ; R = no ).
st194(R) :- catch(string_code(0'a, "abc", _), error(E, _), R = E).
st195(R) :- string_code(1, [0'a, 0'b], R).
% get_string_code/3
st196(R) :- get_string_code(1, "abc", R).
st197(R) :- get_string_code(3, "abc", R).
st198(R) :- catch(get_string_code(5, "abc", _), error(E, C), R = E-C).
st199(R) :- catch(get_string_code(0, "abc", _), error(E, _), R = E).
st200(R) :- catch(get_string_code(-1, "abc", _), error(E, _), R = E).
st201(R) :- catch(get_string_code(a, "abc", _), error(E, _), R = E).
st202(R) :- X is 1 << 70, catch(get_string_code(X, "abc", _), error(E, _), R = E).
st203(R) :- catch(get_string_code(_, "abc", _), error(E, _), R = E).
st204(R) :- catch(get_string_code(1, f(x), _), error(E, _), R = E).
st205(R) :- get_string_code(2, abc, R).
st206(R) :- ( get_string_code(1, "abc", 0'b) -> R = yes ; R = no ).
st207(R) :- get_string_code(1, "日本", R).
st208(R) :- catch(get_string_code(1, "", _), error(E, _), R = E).
% appended after the first battery: the rows its mutants (tools/mutants/T2.py) need
st209(R) :- ( atom_string(12, "12") -> R = yes ; R = no ).
st210(R) :- ( atom_string("abc", abc) -> R = yes ; R = no ).
st211(R) :- findall(B-A-S, sub_string("abc", B, 3, A, S), R).
st212(R) :- findall(B-L-S, sub_string("abc", B, L, 1, S), R).
st213(R) :- split_string("a.,b", ".,", ",", R).
st214(R) :- split_string("a  ,b", ",", " ", R).
"""

const _ST_PROGRAM2 = raw"""
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
"""

# swipl 10.1.19's answers to the programs above (the driver's lines; lk-channel evidence/T2/t2_rows.out and t2_rows2.out of the T2 branch)
const _ST_PINNED = [
    "ok",
    "st001 c[115,116,48,48,49]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],c[91,124,93]/2(s[99],nil))))",
    "st002 c[115,116,48,48,50]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[104,111,109,101],c[91,124,93]/2(s[],c[91,124,93]/2(s[106,97,110],c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[110,105,99,101],c[91,124,93]/2(s[112,97,116,104],nil)))))))))",
    "st003 c[115,116,48,48,51]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],c[91,124,93]/2(s[],nil)))))",
    "st004 c[115,116,48,48,52]/1(c[91,124,93]/2(s[97],nil))",
    "st005 c[115,116,48,48,53]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st006 c[115,116,48,48,54]/1(c[91,124,93]/2(s[],nil))",
    "st007 c[115,116,48,48,55]/1(c[91,124,93]/2(s[],nil))",
    "st008 c[115,116,48,48,56]/1(c[91,124,93]/2(s[97,98,99],nil))",
    "st009 c[115,116,48,48,57]/1(c[91,124,93]/2(s[],nil))",
    "st010 c[115,116,48,49,48]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],c[91,124,93]/2(s[99],nil))))",
    "st011 c[115,116,48,49,49]/1(c[91,124,93]/2(s[83,87,73,45,80,114,111,108,111,103],c[91,124,93]/2(s[55,46,48],nil)))",
    "st012 c[115,116,48,49,50]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st013 c[115,116,48,49,51]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[],c[91,124,93]/2(s[],nil))))",
    "st014 c[115,116,48,49,52]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[99],nil)))",
    "st015 c[115,116,48,49,53]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st016 c[115,116,48,49,54]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st017 c[115,116,48,49,55]/1(c[45]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st018 c[115,116,48,49,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,112,108,105,116,95,115,116,114,105,110,103],i4)),V0)))",
    "st019 c[115,116,48,49,57]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st020 c[115,116,48,50,48]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st021 c[115,116,48,50,49]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st022 c[115,116,48,50,50]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],i123))",
    "st023 c[115,116,48,50,51]/1(c[91,124,93]/2(s[26085],c[91,124,93]/2(s[35486],nil)))",
    "st024 c[115,116,48,50,52]/1(a[121,101,115])",
    "st025 c[115,116,48,50,53]/1(a[110,111])",
    "st026 c[115,116,48,50,54]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))",
    "st027 c[115,116,48,50,55]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[],nil)))))",
    "st028 c[115,116,48,50,56]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[],c[91,124,93]/2(s[98],nil))))",
    "st029 c[115,116,48,50,57]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[],nil)))",
    "st030 c[115,116,48,51,48]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[],nil))))",
    "st031 c[115,116,48,51,49]/1(i8)",
    "st032 c[115,116,48,51,50]/1(s[98])",
    "st033 c[115,116,48,51,51]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],c[102]/1(a[120])))",
    "st034 c[115,116,48,51,52]/1(c[91,124,93]/2(s[],nil))",
    "st035 c[115,116,48,51,53]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[],nil)))",
    "st036 c[115,116,48,51,54]/1(s[97,98,99])",
    "st037 c[115,116,48,51,55]/1(a[97,98,99])",
    "st038 c[115,116,48,51,56]/1(s[49,50,51])",
    "st039 c[115,116,48,51,57]/1(a[49,50,51])",
    "st040 c[115,116,48,52,48]/1(s[49,46,53])",
    "st041 c[115,116,48,52,49]/1(s[115,116,114])",
    "st042 c[115,116,48,52,50]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[97,116,111,109,95,115,116,114,105,110,103],i2)),V0)))",
    "st043 c[115,116,48,52,51]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[97,116,111,109,95,115,116,114,105,110,103],i2)),V0)))",
    "st044 c[115,116,48,52,52]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[97,116,111,109,95,115,116,114,105,110,103],i2)),V0)))",
    "st045 c[115,116,48,52,53]/1(a[121,101,115])",
    "st046 c[115,116,48,52,54]/1(a[110,111])",
    "st047 c[115,116,48,52,55]/1(a[121,101,115])",
    "st048 c[115,116,48,52,56]/1(s[])",
    "st049 c[115,116,48,52,57]/1(a[])",
    "st050 c[115,116,48,53,48]/1(a[97,98])",
    "st051 c[115,116,48,53,49]/1(s[26085,26412])",
    "st052 c[115,116,48,53,50]/1(a[26085,26412])",
    "st053 c[115,116,48,53,51]/1(a[110,111])",
    "st054 c[115,116,48,53,52]/1(a[49,50])",
    "st055 c[115,116,48,53,53]/1(i3)",
    "st056 c[115,116,48,53,54]/1(s[97,98,99])",
    "st057 c[115,116,48,53,55]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "st058 c[115,116,48,53,56]/1(s[97,98])",
    "st059 c[115,116,48,53,57]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "st060 c[115,116,48,54,48]/1(c[91,124,93]/2(i49,c[91,124,93]/2(i50,nil)))",
    "st061 c[115,116,48,54,49]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,111,100,101,115],i2)),V0)))",
    "st062 c[115,116,48,54,50]/1(s[97,98])",
    "st063 c[115,116,48,54,51]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,111,100,101,115],i2)),V0)))",
    "st064 c[115,116,48,54,52]/1(V0)",
    "st065 c[115,116,48,54,53]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1))",
    "st066 c[115,116,48,54,54]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st067 c[115,116,48,54,55]/1(c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil)))",
    "st068 c[115,116,48,54,56]/1(a[110,111])",
    "st069 c[115,116,48,54,57]/1(nil)",
    "st070 c[115,116,48,55,48]/1(s[])",
    "st071 c[115,116,48,55,49]/1(c[91,124,93]/2(i26085,c[91,124,93]/2(i26412,nil)))",
    "st072 c[115,116,48,55,50]/1(s[26085,26412])",
    "st073 c[115,116,48,55,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "st074 c[115,116,48,55,52]/1(s[97,98])",
    "st075 c[115,116,48,55,53]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "st076 c[115,116,48,55,54]/1(c[91,124,93]/2(a[49],c[91,124,93]/2(a[50],nil)))",
    "st077 c[115,116,48,55,55]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,104,97,114,115],i2)),V0)))",
    "st078 c[115,116,48,55,56]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[98,99]))",
    "st079 c[115,116,48,55,57]/1(c[91,124,93]/2(a[26085],c[91,124,93]/2(a[26412],nil)))",
    "st080 c[115,116,48,56,48]/1(s[26085])",
    "st081 c[115,116,48,56,49]/1(c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil)))",
    "st082 c[115,116,48,56,50]/1(s[97,98,99])",
    "st083 c[115,116,48,56,51]/1(s[115,116,114])",
    "st084 c[115,116,48,56,52]/1(s[97,98])",
    "st085 c[115,116,48,56,53]/1(s[97,98])",
    "st086 c[115,116,48,56,54]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,101,120,116],i12),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,101,120,116,95,116,111,95,115,116,114,105,110,103],i2)),V0)))",
    "st087 c[115,116,48,56,55]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,101,120,116,95,116,111,95,115,116,114,105,110,103],i2)),V0)))",
    "st088 c[115,116,48,56,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,101,120,116],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,101,120,116,95,116,111,95,115,116,114,105,110,103],i2)),V0)))",
    "st089 c[115,116,48,56,57]/1(s[])",
    "st090 c[115,116,48,57,48]/1(a[121,101,115])",
    "st091 c[115,116,48,57,49]/1(s[26085,26412])",
    "st092 c[115,116,48,57,50]/1(s[115])",
    "st093 c[115,116,48,57,51]/1(i3)",
    "st094 c[115,116,48,57,52]/1(i3)",
    "st095 c[115,116,48,57,53]/1(i3)",
    "st096 c[115,116,48,57,54]/1(i3)",
    "st097 c[115,116,48,57,55]/1(i3)",
    "st098 c[115,116,48,57,56]/1(i0)",
    "st099 c[115,116,48,57,57]/1(i0)",
    "st100 c[115,116,49,48,48]/1(i3)",
    "st101 c[115,116,49,48,49]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,108,101,110,103,116,104],i2)),V0)))",
    "st102 c[115,116,49,48,50]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,108,101,110,103,116,104],i2)),V0)))",
    "st103 c[115,116,49,48,51]/1(a[121,101,115])",
    "st104 c[115,116,49,48,52]/1(a[110,111])",
    "st105 c[115,116,49,48,53]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111]))",
    "st106 c[115,116,49,48,54]/1(a[110,111])",
    "st107 c[115,116,49,48,55]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5))",
    "st108 c[115,116,49,48,56]/1(i2)",
    "st109 c[115,116,49,48,57]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st110 c[115,116,49,49,48]/1(s[97,98,99,100,101,102])",
    "st111 c[115,116,49,49,49]/1(s[97,98])",
    "st112 c[115,116,49,49,50]/1(s[49,50])",
    "st113 c[115,116,49,49,51]/1(s[98,99])",
    "st114 c[115,116,49,49,52]/1(s[97,98])",
    "st115 c[115,116,49,49,53]/1(s[98,99])",
    "st116 c[115,116,49,49,54]/1(c[91,124,93]/2(c[45]/2(s[],s[97,98,99]),c[91,124,93]/2(c[45]/2(s[97],s[98,99]),c[91,124,93]/2(c[45]/2(s[97,98],s[99]),c[91,124,93]/2(c[45]/2(s[97,98,99],s[]),nil)))))",
    "st117 c[115,116,49,49,55]/1(c[91,124,93]/2(c[45]/2(s[],s[97,98,99]),c[91,124,93]/2(c[45]/2(s[97],s[98,99]),c[91,124,93]/2(c[45]/2(s[97,98],s[99]),c[91,124,93]/2(c[45]/2(s[97,98,99],s[]),nil)))))",
    "st118 c[115,116,49,49,56]/1(a[121,101,115])",
    "st119 c[115,116,49,49,57]/1(a[110,111])",
    "st120 c[115,116,49,50,48]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,111,110,99,97,116],i3)),V0)))",
    "st121 c[115,116,49,50,49]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,111,110,99,97,116],i3)),V0)))",
    "st122 c[115,116,49,50,50]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st123 c[115,116,49,50,51]/1(c[91,124,93]/2(s[97,98],nil))",
    "st124 c[115,116,49,50,52]/1(nil)",
    "st125 c[115,116,49,50,53]/1(s[])",
    "st126 c[115,116,49,50,54]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[91,124,93]/2(i97,nil)))",
    "st127 c[115,116,49,50,55]/1(s[26085,26412])",
    "st128 c[115,116,49,50,56]/1(i3)",
    "st129 c[115,116,49,50,57]/1(s[100,101,102])",
    "st130 c[115,116,49,51,48]/1(a[110,111])",
    "st131 c[115,116,49,51,49]/1(s[97,98,99])",
    "st132 c[115,116,49,51,50]/1(s[101,108,108])",
    "st133 c[115,116,49,51,51]/1(s[108,111])",
    "st134 c[115,116,49,51,52]/1(c[45]/2(i2,i3))",
    "st135 c[115,116,49,51,53]/1(c[91,124,93]/2(c[45]/2(i2,i2),c[91,124,93]/2(c[45]/2(i3,i1),nil)))",
    "st136 c[115,116,49,51,54]/1(s[104,101,108,108,111])",
    "st137 c[115,116,49,51,55]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i0),i3),s[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i1),i2),s[97]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i2),i1),s[97,98]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i0,i3),i0),s[97,98,99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i0),i2),s[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i1),i1),s[98]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i1,i2),i0),s[98,99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i2,i0),i1),s[]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i2,i1),i0),s[99]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(i3,i0),i0),s[]),nil)))))))))))",
    "st138 c[115,116,49,51,56]/1(s[98])",
    "st139 c[115,116,49,51,57]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i0,i0),i3),c[91,124,93]/2(c[45]/2(c[45]/2(i1,i0),i2),c[91,124,93]/2(c[45]/2(c[45]/2(i2,i0),i1),c[91,124,93]/2(c[45]/2(c[45]/2(i3,i0),i0),nil)))))",
    "st140 c[115,116,49,52,48]/1(a[110,111])",
    "st141 c[115,116,49,52,49]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1))",
    "st142 c[115,116,49,52,50]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111]))",
    "st143 c[115,116,49,52,51]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,117,98,95,115,116,114,105,110,103],i5)),V0)))",
    "st144 c[115,116,49,52,52]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,117,98,95,115,116,114,105,110,103],i5)),V0)))",
    "st145 c[115,116,49,52,53]/1(s[99])",
    "st146 c[115,116,49,52,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i0,i2),s[]),c[91,124,93]/2(c[45]/2(c[45]/2(i1,i1),s[98]),c[91,124,93]/2(c[45]/2(c[45]/2(i2,i0),s[98,99]),nil))))",
    "st147 c[115,116,49,52,55]/1(c[91,124,93]/2(c[45]/2(i0,i2),c[91,124,93]/2(c[45]/2(i2,i0),nil)))",
    "st148 c[115,116,49,52,56]/1(c[91,124,93]/2(c[45]/2(i0,i2),c[91,124,93]/2(c[45]/2(i1,i1),c[91,124,93]/2(c[45]/2(i2,i0),nil))))",
    "st149 c[115,116,49,52,57]/1(s[97,98,99])",
    "st150 c[115,116,49,53,48]/1(a[110,111])",
    "st151 c[115,116,49,53,49]/1(s[])",
    "st152 c[115,116,49,53,50]/1(a[110,111])",
    "st153 c[115,116,49,53,51]/1(c[45]/2(i1,i1))",
    "st154 c[115,116,49,53,52]/1(c[91,124,93]/2(i0,nil))",
    "st155 c[115,116,49,53,53]/1(c[91,124,93]/2(i2,nil))",
    "st156 c[115,116,49,53,54]/1(c[91,124,93]/2(c[45]/2(i1,s[98,97]),nil))",
    "st157 c[115,116,49,53,55]/1(nil)",
    "st158 c[115,116,49,53,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i0,i5),s[97,98,99,98,97]),c[91,124,93]/2(c[45]/2(c[45]/2(i1,i3),s[98,99,98]),c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),s[99]),nil))))",
    "st159 c[115,116,49,53,57]/1(c[91,124,93]/2(c[45]/2(i1,s[98]),nil))",
    "st160 c[115,116,49,54,48]/1(nil)",
    "st161 c[115,116,49,54,49]/1(c[91,124,93]/2(i1,nil))",
    "st162 c[115,116,49,54,50]/1(c[91,124,93]/2(c[45]/2(i2,i2),nil))",
    "st163 c[115,116,49,54,51]/1(c[91,124,93]/2(c[45]/2(i0,i2),c[91,124,93]/2(c[45]/2(i1,i1),c[91,124,93]/2(c[45]/2(i2,i0),nil))))",
    "st164 c[115,116,49,54,52]/1(nil)",
    "st165 c[115,116,49,54,53]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1))",
    "st166 c[115,116,49,54,54]/1(c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[],c[91,124,93]/2(s[97],c[91,124,93]/2(s[97,98],c[91,124,93]/2(s[98],nil)))))))",
    "st167 c[115,116,49,54,55]/1(i2)",
    "st168 c[115,116,49,54,56]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])))",
    "st169 c[115,116,49,54,57]/1(a[111,107])",
    "st170 c[115,116,49,55,48]/1(a[110,111])",
    "st171 c[115,116,49,55,49]/1(i97)",
    "st172 c[115,116,49,55,50]/1(i99)",
    "st173 c[115,116,49,55,51]/1(a[110,111])",
    "st174 c[115,116,49,55,52]/1(a[110,111])",
    "st175 c[115,116,49,55,53]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1))",
    "st176 c[115,116,49,55,54]/1(c[91,124,93]/2(c[45]/2(i1,i97),c[91,124,93]/2(c[45]/2(i2,i98),c[91,124,93]/2(c[45]/2(i3,i99),nil))))",
    "st177 c[115,116,49,55,55]/1(i2)",
    "st178 c[115,116,49,55,56]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i4,nil)))",
    "st179 c[115,116,49,55,57]/1(i97)",
    "st180",
    "st181 c[115,116,49,56,49]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111]))",
    "st182 c[115,116,49,56,50]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97]))",
    "st183 c[115,116,49,56,51]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])))",
    "st184 c[115,116,49,56,52]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,99,111,100,101],i3)),V0)))",
    "st185 c[115,116,49,56,53]/1(a[121,101,115])",
    "st186 c[115,116,49,56,54]/1(a[110,111])",
    "st187 c[115,116,49,56,55]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5))",
    "st188 c[115,116,49,56,56]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116]))",
    "st189 c[115,116,49,56,57]/1(a[110,111])",
    "st190 c[115,116,49,57,48]/1(nil)",
    "st191 c[115,116,49,57,49]/1(c[91,124,93]/2(c[45]/2(i1,i26085),c[91,124,93]/2(c[45]/2(i2,i26412),nil)))",
    "st192 c[115,116,49,57,50]/1(i3)",
    "st193 c[115,116,49,57,51]/1(a[110,111])",
    "st194",
    "st195 c[115,116,49,57,53]/1(i97)",
    "st196 c[115,116,49,57,54]/1(i97)",
    "st197 c[115,116,49,57,55]/1(i99)",
    "st198 c[115,116,49,57,56]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(c[114,97,110,103,101]/2(i1,i3),i5),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[103,101,116,95,115,116,114,105,110,103,95,99,111,100,101],i3)),V0)))",
    "st199 c[115,116,49,57,57]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(c[114,97,110,103,101]/2(i1,i3),i0))",
    "st200 c[115,116,50,48,48]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(c[114,97,110,103,101]/2(i1,i3),i-1))",
    "st201 c[115,116,50,48,49]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97]))",
    "st202 c[115,116,50,48,50]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116]))",
    "st203 c[115,116,50,48,51]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114])",
    "st204 c[115,116,50,48,52]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])))",
    "st205 c[115,116,50,48,53]/1(i98)",
    "st206 c[115,116,50,48,54]/1(a[110,111])",
    "st207 c[115,116,50,48,55]/1(i26085)",
    "st208 c[115,116,50,48,56]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(c[114,97,110,103,101]/2(i1,i0),i1))",
    "st209 c[115,116,50,48,57]/1(a[121,101,115])",
    "st210 c[115,116,50,49,48]/1(a[121,101,115])",
    "st211 c[115,116,50,49,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i0,i0),s[97,98,99]),nil))",
    "st212 c[115,116,50,49,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i0,i2),s[97,98]),c[91,124,93]/2(c[45]/2(c[45]/2(i1,i1),s[98]),c[91,124,93]/2(c[45]/2(c[45]/2(i2,i0),s[]),nil))))",
    "st213 c[115,116,50,49,51]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[],c[91,124,93]/2(s[98],nil))))",
    "st214 c[115,116,50,49,52]/1(c[91,124,93]/2(s[97],c[91,124,93]/2(s[98],nil)))"
]

const _ST_PINNED2 = [
    "ok",
    "su001 c[115,117,48,48,49]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "su002 c[115,117,48,48,50]/1(c[91,124,93]/2(i195,c[91,124,93]/2(i169,nil)))",
    "su003 c[115,117,48,48,51]/1(c[91,124,93]/2(i226,c[91,124,93]/2(i130,c[91,124,93]/2(i172,nil))))",
    "su004 c[115,117,48,48,52]/1(c[91,124,93]/2(i233,nil))",
    "su005 c[115,117,48,48,53]/1(c[91,124,93]/2(i233,nil))",
    "su006 c[115,117,48,48,54]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[101,110,99,111,100,105,110,103]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),a[99,97,110,110,111,116,32,114,101,112,114,101,115,101,110,116,32,116,101,120,116,32,117,115,105,110,103,32,101,110,99,111,100,105,110,103,32,105,115,111,95,108,97,116,105,110,95,49])))",
    "su007 c[115,117,48,48,55]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[101,110,99,111,100,105,110,103]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),a[99,97,110,110,111,116,32,114,101,112,114,101,115,101,110,116,32,116,101,120,116,32,117,115,105,110,103,32,101,110,99,111,100,105,110,103,32,111,99,116,101,116])))",
    "su008 c[115,117,48,48,56]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[101,110,99,111,100,105,110,103]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),a[99,97,110,110,111,116,32,114,101,112,114,101,115,101,110,116,32,116,101,120,116,32,117,115,105,110,103,32,101,110,99,111,100,105,110,103,32,97,115,99,105,105])))",
    "su009 c[115,117,48,48,57]/1(c[91,124,93]/2(i97,nil))",
    "su010 c[115,117,48,49,48]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i233,c[91,124,93]/2(i0,c[91,124,93]/2(i172,c[91,124,93]/2(i32,nil)))))))",
    "su011 c[115,117,48,49,49]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i233,c[91,124,93]/2(i32,c[91,124,93]/2(i172,nil)))))))",
    "su012 c[115,117,48,49,50]/1(nil)",
    "su013 c[115,117,48,49,51]/1(c[91,124,93]/2(i61,c[91,124,93]/2(i216,c[91,124,93]/2(i0,c[91,124,93]/2(i222,nil)))))",
    "su014 c[115,117,48,49,52]/1(c[91,124,93]/2(i216,c[91,124,93]/2(i61,c[91,124,93]/2(i222,c[91,124,93]/2(i0,nil)))))",
    "su015 c[115,117,48,49,53]/1(c[91,124,93]/2(i240,c[91,124,93]/2(i159,c[91,124,93]/2(i152,c[91,124,93]/2(i128,nil)))))",
    "su016 c[115,117,48,49,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "su017 c[115,117,48,49,55]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil)))",
    "su018 c[115,117,48,49,56]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil)))",
    "su019 c[115,117,48,49,57]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],i12),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su020 c[115,117,48,50,48]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su021 c[115,117,48,50,49]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su022 c[115,117,48,50,50]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,110,99,111,100,105,110,103],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su023 c[115,117,48,50,51]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,110,99,111,100,105,110,103],a[119,99,104,97,114,95,116]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su024 c[115,117,48,50,52]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su025 c[115,117,48,50,53]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su026 c[115,117,48,50,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "su027 c[115,117,48,50,55]/1(c[91,124,93]/2(i233,nil))",
    "su028 c[115,117,48,50,56]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i233,nil)))",
    "su029 c[115,117,48,50,57]/1(s[8364])",
    "su030 c[115,117,48,51,48]/1(s[233])",
    "su031 c[115,117,48,51,49]/1(s[255,254])",
    "su032 c[115,117,48,51,50]/1(s[226,130])",
    "su033 c[115,117,48,51,51]/1(s[195,169])",
    "su034 c[115,117,48,51,52]/1(s[200])",
    "su035 c[115,117,48,51,53]/1(s[97,8364])",
    "su036 c[115,117,48,51,54]/1(s[97,8364])",
    "su037 c[115,117,48,51,55]/1(s[216])",
    "su038 c[115,117,48,51,56]/1(s[97,98])",
    "su039 c[115,117,48,51,57]/1(c[45]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[105,110,99,111,109,112,108,101,116,101,95,109,117,108,116,105,98,121,116,101,95,115,101,113,117,101,110,99,101]),V0))",
    "su040 c[115,117,48,52,48]/1(c[45]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[105,108,108,101,103,97,108,95,117,116,102,49,54,95,115,101,113,117,101,110,99,101]),V0))",
    "su041 c[115,117,48,52,49]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[99,111,100,101,95,112,111,105,110,116]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su042 c[115,117,48,52,50]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[99,111,100,101,95,112,111,105,110,116]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su043 c[115,117,48,52,51]/1(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[101,110,99,111,100,105,110,103]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),a[99,97,110,110,111,116,32,114,101,112,114,101,115,101,110,116,32,116,101,120,116,32,117,115,105,110,103,32,101,110,99,111,100,105,110,103,32,105,115,111,95,108,97,116,105,110,95,49])))",
    "su044 c[115,117,48,52,52]/1(s[97])",
    "su045 c[115,117,48,52,53]/1(s[])",
    "su046 c[115,117,48,52,54]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su047 c[115,117,48,52,55]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su048 c[115,117,48,52,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],s[97,98,99]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su049 c[115,117,48,52,57]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su050 c[115,117,48,53,48]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su051 c[115,117,48,53,49]/1(a[121,101,115])",
    "su052 c[115,117,48,53,50]/1(a[110,111])",
    "su053 c[115,117,48,53,51]/1(a[111,107])",
    "su054 c[115,117,48,53,52]/1(c[45]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,110,99,111,100,105,110,103],a[119,99,104,97,114,95,116]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,116,114,105,110,103,95,98,121,116,101,115],i3)),V0)))",
    "su055 c[115,117,48,53,53]/1(c[91,124,93]/2(i65,c[91,124,93]/2(i66,nil)))",
    "su056 c[115,117,48,53,54]/1(s[104,101,108,108,111])",
    "su057 c[115,117,48,53,55]/1(c[45]/2(i5,s[104,101,108,108,111]))",
    "su058 c[115,117,48,53,56]/1(s[])",
    "su059 c[115,117,48,53,57]/1(s[104,105])",
    "su060 c[115,117,48,54,48]/1(c[45]/2(i0,s[]))",
    "su061 c[115,117,48,54,49]/1(s[97,98])",
    "su062 c[115,117,48,54,50]/1(s[97,98])",
    "su063 c[115,117,48,54,51]/1(c[91,124,93]/2(s[104,101],c[91,124,93]/2(s[108,108],c[91,124,93]/2(s[111],nil))))",
    "su064 c[115,117,48,54,52]/1(c[45]/2(i2,i2))",
    "su065 c[115,117,48,54,53]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i233,nil)))",
    "su066 c[115,117,48,54,54]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[111,112,101,110,95,115,116,114,105,110,103],i2)),V0)))",
    "su067 c[115,117,48,54,55]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[111,112,101,110,95,115,116,114,105,110,103],i2)),V0)))",
    "su068 c[115,117,48,54,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,97,100,95,115,116,114,105,110,103],i3)),V0)))",
    "su069 c[115,117,48,54,57]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1))",
    "su070 c[115,117,48,55,48]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,95,115,117,99,104,95,115,116,114,101,97,109]))",
    "su071 c[115,117,48,55,49]/1(a[121,101,115])",
    "su072 c[115,117,48,55,50]/1(a[110,111])",
    "su073 c[115,117,48,55,51]/1(i3)",
    "su074 c[115,117,48,55,52]/1(c[91,124,93]/2(c[45]/2(i44,s[97]),c[91,124,93]/2(c[45]/2(i44,s[98]),c[91,124,93]/2(c[45]/2(i-1,s[99]),nil))))",
    "su075 c[115,117,48,55,53]/1(c[45]/2(i10,s[104,105]))",
    "su076 c[115,117,48,55,54]/1(c[45]/2(i-1,s[]))",
    "su077 c[115,117,48,55,55]/1(c[45]/2(i-1,s[97,98,99]))",
    "su078 c[115,117,48,55,56]/1(c[45]/2(i59,s[97]))",
    "su079 c[115,117,48,55,57]/1(s[97])",
    "su080 c[115,117,48,56,48]/1(a[110,111])",
    "su081 c[115,117,48,56,49]/1(c[45]/2(i-1,s[]))",
    "su082 c[115,117,48,56,50]/1(c[45]/2(i44,s[120]))",
    "su083 c[115,117,48,56,51]/1(c[45]/2(i44,i2))",
    "su084 c[115,117,48,56,52]/1(c[45]/2(i233,s[97]))",
    "su085 c[115,117,48,56,53]/1(c[45]/2(i-1,s[97]))",
    "su086 c[115,117,48,56,54]/1(c[45]/2(i-1,s[97,98,99]))",
    "su087 c[115,117,48,56,55]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,95,115,117,99,104,95,115,116,114,101,97,109]))",
    "su088 c[115,117,48,56,56]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,97,100,95,115,116,114,105,110,103],i5)),V0)))",
    "su089 c[115,117,48,56,57]/1(c[45]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,97,100,95,115,116,114,105,110,103],i5)),V0)))",
    "su090 c[115,117,48,57,48]/1(c[91,124,93]/2(c[45]/2(i10,s[97,98]),c[91,124,93]/2(c[45]/2(i10,s[99,100]),c[91,124,93]/2(c[45]/2(i-1,s[]),nil))))",
    "su091 c[115,117,48,57,49]/1(c[45]/2(i44,s[97]))"
]

_st_names(prog::String) = String[m.captures[1] for m in eachmatch(r"^((?:st|su)\d+)\(R\) :-"m, prog)]
function _st_file(prog::String)::String
    f = joinpath(mktempdir(), "p.pl")
    write(f, prog)
    return f
end

@testset "split_string/4, atom_string/2, string_codes/2, string_chars/2, text_to_string/2, string_length/2, string_concat/3, sub_string/5, string_code/3, get_string_code/3 as swipl's" begin
    names = _st_names(_ST_PROGRAM)
    kl = _st_kernel_lines(_st_file(_ST_PROGRAM), names)
    @test length(_ST_PINNED) == length(names) + 1 && _ST_PINNED[1] == "ok"
    @test length(kl) == length(_ST_PINNED)
    for (k, p) in zip(kl, _ST_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: both sides hold rows, error rows (an `error` formal term raised and caught), enumeration rows, empty answers
    @test length(kl) >= 200 && all(!isempty, kl) && all(!isempty, _ST_PINNED)
    P = _ST_PINNED
    @test count(l -> occursin(_st_c("type_error", 2), l), P) >= 15
    @test count(l -> occursin(_st_c("domain_error", 2), l), P) >= 2
    @test count(l -> occursin(_st_a("instantiation_error"), l), P) >= 8
    @test count(l -> endswith(l, "(nil)"), P) >= 3                              # empty answers: no solution and empty findall
    # the enumeration rows: string_concat(X, Y, abc) four splits, sub_string("abc", B, L, A, S) ten substrings
    @test startswith(P[117], "st116 ") && count("c[45]/2(", P[117]) == 4
    @test startswith(P[138], "st137 ") && count("c[45]/2(c[45]/2(c[45]/2(", P[138]) == 10
    # the upstream quirk: Before and After the same variable, the last candidate of the search is returned without its unification
    # being checked; swipl answers X = 2 for a 4-character text and a 2-character sub text, where no X fits (2 + 2 + 2 != 4)
    @test occursin("st155(R) :- findall(X, sub_string(\"abab\", X, 2, X, \"ab\"), R).", _ST_PROGRAM)
    @test P[156] == _st_line("st155", "c[91,124,93]/2(i2,nil)")
    # the same variable twice where it does fit: sub_string("abc", X, 1, X, S) is X = 1, S = "b"
    @test occursin("st159(R) :- findall(X-S, sub_string(\"abc\", X, 1, X, S), R).", _ST_PROGRAM)
    @test occursin("(i1,s[98])", P[160])
end

@testset "string_bytes/3, open_string/2, read_string/3, read_string/5 as swipl's" begin
    names = _st_names(_ST_PROGRAM2)
    kl = _st_kernel_lines(_st_file(_ST_PROGRAM2), names)
    @test length(_ST_PINNED2) == length(names) + 1 && _ST_PINNED2[1] == "ok"
    @test length(kl) == length(_ST_PINNED2)
    for (k, p) in zip(kl, _ST_PINNED2)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    @test length(kl) >= 80 && all(!isempty, kl) && all(!isempty, _ST_PINNED2)
    P = _ST_PINNED2
    @test count(l -> occursin(_st_c("representation_error", 1), l), P) >= 5
    @test count(l -> occursin(_st_c("syntax_error", 1), l), P) >= 2
    @test count(l -> occursin(_st_c("existence_error", 2), l), P) >= 2
    # the bytes of "a\u00E9\u20AC" in UTF-16 little endian (su010), and "\u20AC" decoded from its UTF-8 (su029)
    @test occursin("su010(R) :- string_bytes(\"a\\u00E9\\u20AC\", R, utf16le).", _ST_PROGRAM2)
    @test P[11] == _st_line("su010", _st_list([97, 0, 233, 0, 172, 32]))
    @test occursin("su029(R) :- string_bytes(R, [0xe2, 0x82, 0xac], utf8).", _ST_PROGRAM2)
    @test P[30] == _st_line("su029", "s[8364]")
    # a UTF-16 surrogate pair: swipl 10.1.19 raises representation_error(code_point) (pl-text.c steps one unit in the wide branch)
    @test occursin("su041(R) :- catch(string_bytes(_, [0xd8, 0, 0xdc, 0], utf16be)", _ST_PROGRAM2)
    @test occursin("c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[99,111,100,101,95,112,111,105,110,116])", P[42])
    # read_string/5 on "a,b,c": three delimiters 44 44 -1 and the strings a b c
    @test occursin("su074(R) :- open_string(\"a,b,c\", S)", _ST_PROGRAM2)
    @test occursin("i44,s[97]", P[75]) && occursin("i-1,s[99]", P[75])
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "STRING DIFFERENTIAL LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        for (prog, pins) in ((_ST_PROGRAM, _ST_PINNED), (_ST_PROGRAM2, _ST_PINNED2))
            @test _st_swipl_lines(_st_file(prog), _st_names(prog)) == pins
        end
    end
end
