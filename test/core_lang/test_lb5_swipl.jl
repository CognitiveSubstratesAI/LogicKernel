# ORIGINAL: a LIVE differential of LB5's stream predicates against swipl at the pin (src/os/pl-file.c, src/pl-write.c, src/pl-arith.c)
# test/core_lang/test_lb5_swipl.jl — set_stream/2 alias(user_output|user_error|user_input), current_input/1, current_output/1,
# line_count/2, line_position/2, tab/1,2, at_end_of_stream/1, get_code/2, put_code/2, put_char/1,2 and write_size/4 (lb001-lb108):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#     A stream in an error term would not encode: the rows that raise a permission_error or existence_error on a stream catch it
#     themselves and answer `perm(Action, Type)` / `ex(Type)`.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, LC_ALL=C.UTF-8, two runs byte-identical, evidence/LB5/lb5_rows.out of the
#     LB5 branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * Streams are made with open_string/2, open('/dev/null', ...) and with_output_to/2; the rows that move a standard alias
#     (al_*) put it back inside the row, so a row never leaves user_output, user_error or user_input captured
#     (the kernel does not restore a captured standard alias when the stream closes: owner S2b, docs/architecture.md).
#   * The /0 forms (at_end_of_stream/0, get_code/1, tab on user_input) read the process's standard input and are covered by the
#     mutants through the /1 and /2 forms that share their function; NOT a row here.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides. Rows whose
#     setup is the likeliest to differ: the pos_noposn pair (the kernel's open/4 option record_position(false)), the al_* rows (the
#     kernel closes a captured standard stream without restoring the alias: restoreStandardStream is S2b's).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through the stream predicates and the write family
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _LB5 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_lb5s(x) = lk_sym(_LB5, Symbol(x))


_lb5_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _lb5_enc(t::_LB5, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _lb5_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _lb5_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _lb5_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_lb5_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_style_check_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _LB5_DRIVER = raw"""
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
function _lb5_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _LB5_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(
                addenv(`swipl -q $f`, "LC_ALL" => "C.UTF-8"); stdin=devnull, stderr=devnull
            ),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: a fact, so the consult has a clause to compile (the rows read the streams, not the program)
const _LB5_PROGRAM = raw"""
lb5_p(1).
"""

# the cases, in groups: lb001-011 line_position/line_count; lb012-021 current_input/current_output; lb022-035 tab;
# lb036-043 at_end_of_stream; lb044-056 get_code; lb057-073 put_code/put_char; lb074-096 write_size; lb097-106 set_stream alias; lb107-108 write_size widest line, line_count of an alias
# (the group boundaries are the generator's: evidence/LB5/gen_rows.py reads these tuples, nothing else)
const _LB5_CASES = [
    (
        "lb001",
        raw"with_output_to(string(S), (write(abc), current_output(O), line_position(O, P), line_count(O, L))), R = S-P-L"
    ),   # pos_abc: text, then position and count of the capture stream
    (
        "lb002",
        raw"with_output_to(string(S), (write(ab), nl, write(c), current_output(O), line_position(O, P), line_count(O, L))), R = S-P-L"
    ),   # pos_nl: after a newline
    (
        "lb003",
        raw"with_output_to(string(S), (write(ab), put_char('\t'), current_output(O), line_position(O, P))), R = S-P"
    ),   # pos_tab: a tab advances to the next multiple of 8
    (
        "lb004",
        raw"open_string('ab\ncd', S), get_code(S, _), get_code(S, _), get_code(S, _), get_code(S, _), line_count(S, L), line_position(S, P), R = L-P"
    ),   # pos_in: an input string stream, 4 characters read
    ("lb005", raw"open_string(abc, S), line_count(S, L), line_position(S, P), R = L-P"),   # pos_in0: an input string stream, nothing read
    ("lb006", raw"open_string(abc, S), ( line_count(S, 2) -> R = yes ; R = no )"),   # pos_unify: the count unified with a wrong value fails
    ("lb007", raw"line_count(foo, _)"),   # pos_nostream: an unknown stream: existence_error
    ("lb008", raw"line_position(_, _)"),   # pos_inst: an unbound stream: instantiation_error
    (
        "lb009",
        raw"open_string(abc, S), close(S), catch(line_count(S, _), error(existence_error(A, _), _), R = ex(A))"
    ),   # pos_closed: a closed stream: existence_error
    (
        "lb010",
        raw"open('/dev/null', read, S, [record_position(false)]), catch((line_count(S, N), R = ok-N), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # pos_noposn: a stream without position: permission_error(property, position, S)
    (
        "lb011",
        raw"open('/dev/null', read, S, [record_position(false)]), catch((line_position(S, N), R = ok-N), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # pos_noposn2: line_position of the same
    ("lb012", raw"current_output(S), is_stream(S), R = yes"),   # cur_out: current_output yields a stream
    ("lb013", raw"current_input(S), is_stream(S), R = yes"),   # cur_in: current_input yields a stream
    ("lb014", raw"current_output(A), current_output(B), ( A == B -> R = same ; R = diff )"),   # cur_out_same: two calls give the same stream
    ("lb015", raw"current_input(A), current_output(B), ( A == B -> R = same ; R = diff )"),   # cur_in_out: input and output differ
    (
        "lb016",
        raw"current_output(O0), with_output_to(string(_), ( current_output(O1), ( O0 == O1 -> R = same ; R = diff ) ))"
    ),   # cur_out_cap: inside with_output_to the current output is another stream
    ("lb017", raw"current_output(foo)"),   # cur_out_foo: an atom that is no stream
    ("lb018", raw"current_output(1)"),   # cur_out_int: an integer
    ("lb019", raw"current_input(foo)"),   # cur_in_foo: an atom that is no stream (input)
    ("lb020", raw"open_string(abc, I), ( current_output(I) -> R = yes ; R = no )"),   # cur_out_inp: an input stream as the current output
    ("lb021", raw"current_output(O), ( current_input(O) -> R = yes ; R = no )"),   # cur_in_outp: the output stream as the current input
    ("lb022", raw"with_output_to(string(S), (write(a), tab(3), write(b))), R = S"),   # tab3: tab(3)
    ("lb023", raw"with_output_to(string(S), (write(a), tab(1+2), write(b))), R = S"),   # tab_expr: tab of an expression
    ("lb024", raw"with_output_to(string(S), (write(a), tab(0), write(b))), R = S"),   # tab0: tab(0)
    ("lb025", raw"with_output_to(string(S), (write(a), tab(-1), write(b))), R = S"),   # tab_neg: tab(-1)
    ("lb026", raw"with_output_to(string(S), tab(a)), R = S"),   # tab_atom: tab(a): the expression error
    ("lb027", raw"tab(_)"),   # tab_inst: tab(_)
    ("lb028", raw"with_output_to(string(S), tab(2.5)), R = S"),   # tab_float: tab(2.5)
    ("lb029", raw"with_output_to(string(S), tab(2.0 * 2)), R = S"),   # tab_float2: tab(2.0 * 2)
    ("lb030", raw"with_output_to(string(S), (write(a), tab(3*2), write(b))), R = S"),   # tab_mul: tab(3*2)
    ("lb031", raw"tab(1 << 70)"),   # tab_big: tab of a number past int64
    (
        "lb032",
        raw"with_output_to(string(S), (current_output(O), tab(O, 2), write(x), tab(O, 1+1), write(y))), R = S"
    ),   # tab_str: tab on a given stream, expression too
    ("lb033", raw"tab(foo, 2)"),   # tab_nostream: tab(foo, 2)
    (
        "lb034",
        raw"catch((open_string(abc, S), tab(S, 2), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # tab_instream: tab on an input stream
    (
        "lb035",
        raw"with_output_to(string(_), (tab(5), current_output(O), line_position(O, P))), R = P"
    ),   # tab_pos: the position after tab
    ("lb036", raw"open_string('', S), ( at_end_of_stream(S) -> R = eof ; R = more )"),   # eos_empty: an empty input
    ("lb037", raw"open_string(a, S), ( at_end_of_stream(S) -> R = eof ; R = more )"),   # eos_more: one character left
    (
        "lb038",
        raw"open_string(a, S), get_code(S, _), ( at_end_of_stream(S) -> R = eof ; R = more )"
    ),   # eos_read: after reading it
    (
        "lb039",
        raw"open_string(a, S), get_code(S, _), get_code(S, C), ( at_end_of_stream(S) -> R = C-eof ; R = C-more )"
    ),   # eos_past: after reading past the end
    ("lb040", raw"at_end_of_stream(foo)"),   # eos_nostream: an unknown stream
    ("lb041", raw"at_end_of_stream(_)"),   # eos_inst: an unbound stream
    (
        "lb042",
        raw"catch((current_output(O), at_end_of_stream(O), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # eos_output: an output stream
    (
        "lb043",
        raw"open_string(abc, S), close(S), catch(at_end_of_stream(S), error(existence_error(A, _), _), R = ex(A))"
    ),   # eos_closed: a closed stream
    (
        "lb044",
        raw"open_string(ab, S), get_code(S, A), get_code(S, B), get_code(S, C), R = [A, B, C]"
    ),   # get2: codes in order, then end of file
    (
        "lb045",
        raw"open_string(a, S), get_code(S, _), get_code(S, C1), get_code(S, C2), R = [C1, C2]"
    ),   # get_past: reading past the end twice
    ("lb046", raw"open_string(ab, S), ( get_code(S, 97) -> R = yes ; R = no )"),   # get_match: a matching code
    (
        "lb047",
        raw"open_string(ab, S), ( get_code(S, 98) -> X = yes ; X = no ), get_code(S, C), R = X-C"
    ),   # get_nomatch: a non-matching code consumes the character
    ("lb048", raw"open_string('é', S), get_code(S, C), R = C"),   # get_wide: a wide character
    ("lb049", raw"open_string(ab, S), get_code(S, a)"),   # get_atom: get_code(S, a)
    ("lb050", raw"open_string(ab, S), get_code(S, end_of_file)"),   # get_eofatom: get_code(S, end_of_file)
    ("lb051", raw"open_string(ab, S), get_code(S, -2)"),   # get_neg: get_code(S, -2)
    ("lb052", raw"open_string(ab, S), get_code(S, 1114112)"),   # get_big: get_code(S, 1114112)
    ("lb053", raw"get_code(foo, _)"),   # get_nostream: an unknown stream
    ("lb054", raw"get_code(_, _)"),   # get_inst: an unbound stream
    (
        "lb055",
        raw"catch((current_output(O), get_code(O, _), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # get_output: an output stream
    ("lb056", raw"open_string('', S), ( get_code(S, -1) -> R = yes ; R = no )"),   # get_eof_m1: -1 is accepted as the end-of-file answer
    (
        "lb057",
        raw"with_output_to(string(S), (put_code(97), put_code(233), put_code(0x1F600))), R = S"
    ),   # put_codes: three codes, one beyond the BMP
    ("lb058", raw"put_code(-1)"),   # put_neg: put_code(-1)
    ("lb059", raw"with_output_to(string(S), put_code(a)), R = S"),   # put_atom: put_code(a)
    ("lb060", raw"put_code(_)"),   # put_inst: put_code(_)
    ("lb061", raw"put_code(1114112)"),   # put_big: put_code(1114112)
    ("lb062", raw"put_code(97.0)"),   # put_float: put_code(97.0)
    (
        "lb063",
        raw"catch((open_string(abc, S), put_code(S, 97), R = ok), error(permission_error(A, B, _), _), R = perm(A, B))"
    ),   # put_input: put_code on an input stream
    ("lb064", raw"with_output_to(string(S), (current_output(O), put_code(O, 0))), R = S"),   # put_nul: put_code(S, 0)
    (
        "lb065",
        raw"with_output_to(string(S), (current_output(O), put_code(O, 104), put_code(O, 105))), R = S"
    ),   # put_str: put_code(S, C)
    ("lb066", raw"put_code(foo, 97)"),   # put_nostream: an unknown stream
    ("lb067", raw"with_output_to(string(S), (put_char(a), put_char('é'))), R = S"),   # char1: put_char(a)
    ("lb068", raw"put_char(ab)"),   # char_long: put_char(ab)
    ("lb069", raw"with_output_to(string(S), put_char(1)), R = S"),   # char_int: put_char(1)
    ("lb070", raw"put_char(_)"),   # char_inst: put_char(_)
    (
        "lb071",
        raw"with_output_to(string(S), (current_output(O), put_char(O, x), put_char(O, y))), R = S"
    ),   # char2: put_char(S, x)
    ("lb072", raw"put_char(foo, x)"),   # char_nostream: put_char(foo, x)
    (
        "lb073",
        raw"with_output_to(string(_), (put_code(97), put_code(10), put_code(98), current_output(O), line_position(O, P), line_count(O, L))), R = P-L"
    ),   # put_pos: the position after put_code and a newline code
    ("lb074", raw"write_size(foo(bar,baz), W, H, []), R = W-H"),   # ws_term: foo(bar,baz)
    ("lb075", raw"write_size('hello world', W, H, [quoted(true)]), R = W-H"),   # ws_quoted: quoted(true) adds the quotes
    ("lb076", raw"write_size('a\nbcd', W, H, []), R = W-H"),   # ws_nl: two lines
    ("lb077", raw"write_size('', W, H, []), R = W-H"),   # ws_empty: nothing written: 0 and 0
    ("lb078", raw"write_size('', W, H, [max_height(0)]), R = W-H"),   # ws_empty_h0: nothing written fits max_height(0)
    ("lb079", raw"write_size(abcdef, _, _, [max_width(3)])"),   # ws_wlimit: max_width passed: fails
    ("lb080", raw"write_size(abcdef, W, H, [max_width(6)]), R = W-H"),   # ws_wok: max_width met
    ("lb081", raw"write_size('a\nb', _, _, [max_height(1)])"),   # ws_hlimit: max_height passed: fails
    ("lb082", raw"write_size('a\nb', W, H, [max_height(2)]), R = W-H"),   # ws_hok: max_height met
    ("lb083", raw"write_size(x, _, _, [max_width(0)])"),   # ws_w0: max_width(0) with output
    ("lb084", raw"write_size(x, _, _, [max_height(0)])"),   # ws_h0: max_height(0) with output
    ("lb085", raw"write_size(x, _, _, [max_width(a)])"),   # ws_opt_type: max_width(a)
    ("lb086", raw"write_size(x, _, _, [max_width(1+1)])"),   # ws_opt_expr: max_width(1+1) is no integer
    ("lb087", raw"write_size(x, _, _, foo)"),   # ws_list: options that are no list
    ("lb088", raw"( write_size(x, 2, _, []) -> R = yes ; R = no )"),   # ws_unify: Width given and wrong
    ("lb089", raw"write_size('日本', W, H, []), R = W-H"),   # ws_wide: wide characters count their width
    ("lb090", raw"write_size('a\tb', W, H, []), R = W-H"),   # ws_tab: a tab in the text
    ("lb091", raw"write_size('$VAR'(1), W, H, [numbervars(true)]), R = W-H"),   # ws_var: numbervars passes through to write_term
    ("lb092", raw"write_size([1,2,3], W, H, [max_width(7)]), R = W-H"),   # ws_list3: a list
    ("lb093", raw"write_size(x, W, H, [quoted(true), max_width(1)]), R = W-H"),   # ws_wq: quoted and a limit
    (
        "lb094",
        raw"with_output_to(string(S), (write(a), write_size(bcd, W, H, []), write(e))), R = S-W-H"
    ),   # ws_ctx: the current output is untouched by write_size
    ("lb095", raw"write_size(f(x), W, H, [quoted]), R = W-H"),   # ws_bare: a bare option atom is write_term's
    ("lb096", raw"write_size(f(x), W, H, [no_such_option(1)]), R = W-H"),   # ws_unknown: an option write_term does not know
    (
        "lb097",
        raw"current_output(OO), with_output_to(string(S), ( current_output(M), set_stream(M, alias(user_output)), write(user_output, hi), set_stream(OO, alias(user_output)) )), R = S"
    ),   # al_out: user_output captured by a memory stream, then restored
    (
        "lb098",
        raw"set_stream(user_error, alias(lb5_saved_err)), with_output_to(string(S), ( current_output(M), set_stream(M, alias(user_error)), write(user_error, hi), set_stream(lb5_saved_err, alias(user_error)) )), R = S"
    ),   # al_err: user_error captured, then restored
    (
        "lb099",
        raw"open_string(xy, S), set_stream(user_input, alias(lb5_saved_in)), set_stream(S, alias(user_input)), get_code(user_input, C1), get_char(user_input, C2), set_stream(lb5_saved_in, alias(user_input)), R = C1-C2"
    ),   # al_in: user_input read from a string stream, then restored
    (
        "lb100",
        raw"open_string(xy, S), current_input(I0), set_stream(user_input, alias(lb5_saved_in2)), set_stream(S, alias(user_input)), current_input(I1), set_stream(lb5_saved_in2, alias(user_input)), ( I0 == I1 -> R = same ; R = diff )"
    ),   # al_in_cur: the current input does not move with user_input
    (
        "lb101",
        raw"current_output(OO), with_output_to(string(_), ( current_output(M), set_stream(M, alias(user_output)), set_stream(OO, alias(user_output)) )), current_output(O2), ( OO == O2 -> R = same ; R = diff )"
    ),   # al_out_cur: the current output does not move with user_output
    ("lb102", raw"set_stream(foo, alias(user_output))"),   # al_nostream: an unknown stream
    (
        "lb103",
        raw"current_output(O), set_stream(user_input, alias(lb5_saved_in3)), catch((set_stream(O, alias(user_input)), R = ok), error(Err, _), ( Err = permission_error(A, B, _) -> R = perm(A, B) ; R = Err )), set_stream(lb5_saved_in3, alias(user_input))"
    ),   # al_out_as_in: an output stream as user_input
    (
        "lb104",
        raw"open_string(x, S), current_output(OO), catch((set_stream(S, alias(user_output)), R = ok), error(Err, _), ( Err = permission_error(A, B, _) -> R = perm(A, B) ; R = Err )), set_stream(OO, alias(user_output))"
    ),   # al_in_as_out: an input stream as user_output
    ("lb105", raw"current_output(O), set_stream(O, alias(1))"),   # al_int: alias(1)
    ("lb106", raw"current_output(O), set_stream(O, alias(_))"),   # al_inst: alias(_)
    ("lb107", raw"write_size('abcd\nx', W, H, []), R = W-H"),   # ws_widest: the widest line is not the last
    ("lb108", raw"line_count(user_output, N), integer(N), R = yes")   # lc_alias: an alias names the stream
]

# the driver's whole output, one line per case after `ok`, filled by evidence/LB5/gen_rows.py --fill from swipl 10.1.19
const _LB5_PINNED = [
    "ok",
    "t_lb001 c[116,95,108,98,48,48,49]/1(c[45]/2(c[45]/2(s[97,98,99],i3),i1))",
    "t_lb002 c[116,95,108,98,48,48,50]/1(c[45]/2(c[45]/2(s[97,98,10,99],i1),i2))",
    "t_lb003 c[116,95,108,98,48,48,51]/1(c[45]/2(s[97,98,9],i8))",
    "t_lb004 c[116,95,108,98,48,48,52]/1(c[45]/2(i2,i1))",
    "t_lb005 c[116,95,108,98,48,48,53]/1(c[45]/2(i1,i0))",
    "t_lb006 c[116,95,108,98,48,48,54]/1(a[110,111])",
    "t_lb007 c[116,95,108,98,48,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb008 c[116,95,108,98,48,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb009 c[116,95,108,98,48,48,57]/1(c[101,120]/1(a[115,116,114,101,97,109]))",
    "t_lb010 c[116,95,108,98,48,49,48]/1(c[45]/2(a[111,107],i1))",
    "t_lb011 c[116,95,108,98,48,49,49]/1(c[45]/2(a[111,107],i0))",
    "t_lb012 c[116,95,108,98,48,49,50]/1(a[121,101,115])",
    "t_lb013 c[116,95,108,98,48,49,51]/1(a[121,101,115])",
    "t_lb014 c[116,95,108,98,48,49,52]/1(a[115,97,109,101])",
    "t_lb015 c[116,95,108,98,48,49,53]/1(a[100,105,102,102])",
    "t_lb016 c[116,95,108,98,48,49,54]/1(a[100,105,102,102])",
    "t_lb017 c[116,95,108,98,48,49,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb018 c[116,95,108,98,48,49,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],i1)))",
    "t_lb019 c[116,95,108,98,48,49,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb020 c[116,95,108,98,48,50,48]/1(a[110,111])",
    "t_lb021 c[116,95,108,98,48,50,49]/1(a[110,111])",
    "t_lb022 c[116,95,108,98,48,50,50]/1(s[97,32,32,32,98])",
    "t_lb023 c[116,95,108,98,48,50,51]/1(s[97,32,32,32,98])",
    "t_lb024 c[116,95,108,98,48,50,52]/1(s[97,98])",
    "t_lb025 c[116,95,108,98,48,50,53]/1(s[97,98])",
    "t_lb026 c[116,95,108,98,48,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[101,118,97,108,117,97,98,108,101],c[47]/2(a[97],i0))))",
    "t_lb027 c[116,95,108,98,48,50,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb028 c[116,95,108,98,48,50,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114,95,101,120,112,114,101,115,115,105,111,110],f2.5)))",
    "t_lb029 c[116,95,108,98,48,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114,95,101,120,112,114,101,115,115,105,111,110],c[42]/2(f2.0,i2))))",
    "t_lb030 c[116,95,108,98,48,51,48]/1(s[97,32,32,32,32,32,32,98])",
    "t_lb031 c[116,95,108,98,48,51,49]/1(c[114,97,105,115,101,100]/1(c[101,118,97,108,117,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,95,111,118,101,114,102,108,111,119])))",
    "t_lb032 c[116,95,108,98,48,51,50]/1(s[32,32,120,32,32,121])",
    "t_lb033 c[116,95,108,98,48,51,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb034 c[116,95,108,98,48,51,52]/1(c[112,101,114,109]/2(a[119,114,105,116,101],a[115,116,114,101,97,109]))",
    "t_lb035 c[116,95,108,98,48,51,53]/1(i5)",
    "t_lb036 c[116,95,108,98,48,51,54]/1(a[101,111,102])",
    "t_lb037 c[116,95,108,98,48,51,55]/1(a[109,111,114,101])",
    "t_lb038 c[116,95,108,98,48,51,56]/1(a[101,111,102])",
    "t_lb039 c[116,95,108,98,48,51,57]/1(c[45]/2(i-1,a[101,111,102]))",
    "t_lb040 c[116,95,108,98,48,52,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb041 c[116,95,108,98,48,52,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb042 c[116,95,108,98,48,52,50]/1(c[112,101,114,109]/2(a[114,101,97,100],a[115,116,114,101,97,109]))",
    "t_lb043 c[116,95,108,98,48,52,51]/1(c[101,120]/1(a[115,116,114,101,97,109]))",
    "t_lb044 c[116,95,108,98,48,52,52]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i-1,nil))))",
    "t_lb045 c[116,95,108,98,48,52,53]/1(c[91,124,93]/2(i-1,c[91,124,93]/2(i-1,nil)))",
    "t_lb046 c[116,95,108,98,48,52,54]/1(a[121,101,115])",
    "t_lb047 c[116,95,108,98,48,52,55]/1(c[45]/2(a[110,111],i98))",
    "t_lb048 c[116,95,108,98,48,52,56]/1(i233)",
    "t_lb049",
    "t_lb050",
    "t_lb051 c[116,95,108,98,48,53,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-2)))",
    "t_lb052 c[116,95,108,98,48,53,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i1114112)))",
    "t_lb053 c[116,95,108,98,48,53,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb054 c[116,95,108,98,48,53,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb055 c[116,95,108,98,48,53,53]/1(c[112,101,114,109]/2(a[114,101,97,100],a[115,116,114,101,97,109]))",
    "t_lb056 c[116,95,108,98,48,53,54]/1(a[121,101,115])",
    "t_lb057 c[116,95,108,98,48,53,55]/1(s[97,233,128512])",
    "t_lb058 c[116,95,108,98,48,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1)))",
    "t_lb059 c[116,95,108,98,48,53,57]/1(s[97])",
    "t_lb060 c[116,95,108,98,48,54,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb061 c[116,95,108,98,48,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i1114112)))",
    "t_lb062 c[116,95,108,98,48,54,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f97.0)))",
    "t_lb063 c[116,95,108,98,48,54,51]/1(c[112,101,114,109]/2(a[119,114,105,116,101],a[115,116,114,101,97,109]))",
    "t_lb064 c[116,95,108,98,48,54,52]/1(s[0])",
    "t_lb065 c[116,95,108,98,48,54,53]/1(s[104,105])",
    "t_lb066 c[116,95,108,98,48,54,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb067 c[116,95,108,98,48,54,55]/1(s[97,233])",
    "t_lb068 c[116,95,108,98,48,54,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_lb069 c[116,95,108,98,48,54,57]/1(s[1])",
    "t_lb070 c[116,95,108,98,48,55,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb071 c[116,95,108,98,48,55,49]/1(s[120,121])",
    "t_lb072 c[116,95,108,98,48,55,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb073 c[116,95,108,98,48,55,51]/1(c[45]/2(i1,i2))",
    "t_lb074 c[116,95,108,98,48,55,52]/1(c[45]/2(i12,i1))",
    "t_lb075 c[116,95,108,98,48,55,53]/1(c[45]/2(i13,i1))",
    "t_lb076 c[116,95,108,98,48,55,54]/1(c[45]/2(i3,i2))",
    "t_lb077 c[116,95,108,98,48,55,55]/1(c[45]/2(i0,i0))",
    "t_lb078 c[116,95,108,98,48,55,56]/1(c[45]/2(i0,i0))",
    "t_lb079",
    "t_lb080 c[116,95,108,98,48,56,48]/1(c[45]/2(i6,i1))",
    "t_lb081",
    "t_lb082 c[116,95,108,98,48,56,50]/1(c[45]/2(i1,i2))",
    "t_lb083",
    "t_lb084",
    "t_lb085 c[116,95,108,98,48,56,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_lb086 c[116,95,108,98,48,56,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],c[43]/2(i1,i1))))",
    "t_lb087 c[116,95,108,98,48,56,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_lb088 c[116,95,108,98,48,56,56]/1(a[110,111])",
    "t_lb089 c[116,95,108,98,48,56,57]/1(c[45]/2(i4,i1))",
    "t_lb090 c[116,95,108,98,48,57,48]/1(c[45]/2(i9,i1))",
    "t_lb091 c[116,95,108,98,48,57,49]/1(c[45]/2(i1,i1))",
    "t_lb092 c[116,95,108,98,48,57,50]/1(c[45]/2(i7,i1))",
    "t_lb093 c[116,95,108,98,48,57,51]/1(c[45]/2(i1,i1))",
    "t_lb094 c[116,95,108,98,48,57,52]/1(c[45]/2(c[45]/2(s[97,101],i3),i1))",
    "t_lb095 c[116,95,108,98,48,57,53]/1(c[45]/2(i4,i1))",
    "t_lb096 c[116,95,108,98,48,57,54]/1(c[45]/2(i4,i1))",
    "t_lb097 c[116,95,108,98,48,57,55]/1(s[104,105])",
    "t_lb098 c[116,95,108,98,48,57,56]/1(s[104,105])",
    "t_lb099 c[116,95,108,98,48,57,57]/1(c[45]/2(i120,a[121]))",
    "t_lb100 c[116,95,108,98,49,48,48]/1(a[115,97,109,101])",
    "t_lb101 c[116,95,108,98,49,48,49]/1(a[115,97,109,101])",
    "t_lb102 c[116,95,108,98,49,48,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_lb103 c[116,95,108,98,49,48,51]/1(a[111,107])",
    "t_lb104 c[116,95,108,98,49,48,52]/1(a[111,107])",
    "t_lb105 c[116,95,108,98,49,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_lb106 c[116,95,108,98,49,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_lb107 c[116,95,108,98,49,48,55]/1(c[45]/2(i4,i2))",
    "t_lb108 c[116,95,108,98,49,48,56]/1(a[121,101,115])"
]

function _lb5_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _LB5_CASES]
    text =
        _LB5_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _LB5_CASES
        ])
    f = joinpath(mktempdir(), "lb5_rows.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _lb5_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_LB5}()
    ld = LK.PL_local_data{_LB5}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _lb5_enc(ball::_LB5)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_lb5s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_LB5, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _lb5_enc(mk_expr(_LB5, _LB5[_lb5s(name), lk_answers(ld, (a:a)...)...]))
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
    return out, gd, ld
end

@testset "the LB5 stream predicates as swipl's (lb001-lb108)" begin
    f, names = _lb5_file()
    kl, _, _ = _lb5_kernel(f, names)
    @test length(kl) == length(_LB5_PINNED)
    for (k, p) in zip(kl, _LB5_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the LB5 rows are not vacuous" begin
    @test length(_LB5_PINNED) == length(_LB5_CASES) + 1
    @test _LB5_PINNED[1] == "ok"
    answered = [l for l in _LB5_PINNED[2:end] if occursin(' ', l)]
    @test length(answered) >= 95                       # the rows that answer
    # the rows with no answer (the goal failed): the two get_code type mismatches and the write_size limits
    noans = [l for l in _LB5_PINNED[2:end] if !occursin(' ', l)]
    @test noans == ["t_lb049", "t_lb050", "t_lb079", "t_lb081", "t_lb083", "t_lb084"]
    raised = _lb5_codes("raised")
    @test count(l -> occursin("c" * raised * "/1(", l), _LB5_PINNED) >= 25    # the error rows
    @test count(l -> occursin("c" * _lb5_codes("perm") * "/2(", l), _LB5_PINNED) == 4   # the permission rows
    # a few values the family stands on: the capture stream's text, position and count; the tab text; the codes; write_size
    @test any(
        l -> startswith(l, "t_lb001 ") && occursin("s" * _lb5_codes("abc") * ",i3),i1)", l),
        _LB5_PINNED
    )
    @test any(l -> startswith(l, "t_lb002 ") && endswith(l, ",i1),i2))"), _LB5_PINNED)
    @test any(
        l -> startswith(l, "t_lb022 ") && occursin("s" * _lb5_codes("a   b"), l),
        _LB5_PINNED
    )
    @test any(
        l -> startswith(l, "t_lb044 ") && occursin("i97,", l) && occursin("i-1", l),
        _LB5_PINNED
    )
    @test any(l -> startswith(l, "t_lb057 ") && occursin("128512", l), _LB5_PINNED)
    @test any(
        l ->
            startswith(l, "t_lb074 ") &&
            endswith(l, "(c" * _lb5_codes("-") * "/2(i12,i1))"),
        _LB5_PINNED
    )
    @test any(
        l ->
            startswith(l, "t_lb107 ") && endswith(l, "(c" * _lb5_codes("-") * "/2(i4,i2))"),
        _LB5_PINNED
    )
    @test any(
        l -> startswith(l, "t_lb108 ") && occursin("a" * _lb5_codes("yes"), l), _LB5_PINNED
    )
    @test any(
        l -> startswith(l, "t_lb097 ") && occursin("s" * _lb5_codes("hi"), l), _LB5_PINNED
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_LB5_PINNED) == length(_LB5_CASES) + 1
    if swipl === nothing
        @info "LB5 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _lb5_file()
        @test _lb5_swipl_lines(f, names) == _LB5_PINNED
    end
end
