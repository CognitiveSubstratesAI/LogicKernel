# ORIGINAL: MISS1's gate — the predicates the missing-C-predicates list left open: the legacy character I/O put/1,2 and get/1,2 of pl-file.c
# (swipl-devel 18168e62: put1/put2 :3505-3517 are put_code's function, get_nonblank :3520-3560) and '$call_no_catch'/1 (pl-pro.c:433-450), '$unload_file'/1 (pl-srcfile.c:839-885), '$sig_unblock'/0 (pl-thread.c:3897), '$leash'/2, '$visible'/2, trace/0 and tracing/0 (pl-trace.c:2287-2393)
# test/core_lang/test_miss_preds_swipl.jl — put/1,2 and get/1,2 over open_string/2 and with_output_to/2 streams, '$call_no_catch'/1:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the answer lines are the driver's `enc`oded form (test_s2a_swipl.jl's driver).
#   * The expected lines are DERIVED FROM THE C (written blind, nothing was run when they were written): get_nonblank reads codes until
#     `!isBlankW(c)` and unifies the integer with NO type check of the second argument (unlike get_code/2: `get(S, a)` just fails, the
#     consumed character stays consumed), -1 at the end of the stream; put_code evaluates `PL_get_char(chr, &c, false)` BEFORE it looks
#     at the stream (so `put(nosuch, foo)` is the type error, not the existence error). With `swipl` on PATH the live answers are
#     compared with these lines too: a hand-derived line that swipl contradicts is a test fault, to be fixed to swipl's answer.
#   * NOT a row: get/1 and put/1 on the process's standard streams (they read the process's stdin); get/1 and put/1 share the function
#     with the /2 forms (get_nonblank, put_code). MEASURE ON THE LANE: `echo ' x' | swipl -g 'get(C), print(C), nl' -t halt` (120), the
#     same with an empty stdin (-1), and `put(-1)`/`put(1114112)` against the kernel (the latter's answer is not derived here).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through the stream predicates
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MG = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mgs(x) = lk_sym(_MG, Symbol(x))

_mg_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mg_enc(t::_MG, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mg_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mg_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mg_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mg_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the expected answers' encoders (the driver's `enc` of an integer, an atom, a string, a compound)
_mgi(n::Integer) = "i$n"
_mga(s::String) = "a" * _mg_codes(s)
_mgs_(s::String) = "s" * _mg_codes(s)
_mgc(name::String, args::String...) =
    "c" * _mg_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_mgraised(f::String) = _mgc("raised", f)

# the swipl side: test_s2a_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MG_DRIVER = raw"""
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
encargs(I, A, T, S0, S) :- call(arg, I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
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
function _mg_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MG_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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

const _MG_PROGRAM = raw"""
mg_p(1).
mg_c2(1).
mg_c2(2).
mg_or(R) :- ( prolog_current_choice(C), prolog_choice_attribute(C, type, T), ( prolog_choice_attribute(C, pc, P), integer(P) -> R = T-pc ; R = T-nopc ) ; R = none ).
mg_cc(R) :- mg_c2(_), prolog_current_choice(C), prolog_choice_attribute(C, type, T), prolog_choice_attribute(C, clause, Cl), ( clause(mg_c2(X), true, Cl) -> R = T-X ; R = T-noclause ).
mg_pc(P) :- ( prolog_current_choice(C), prolog_choice_attribute(C, pc, P) ; P = none ).
:- dynamic mg_seen/1.
:- multifile user:message_hook/3.
:- dynamic user:message_hook/3.
user:message_hook(unhandled_exception(B), error, _) :- assertz(mg_seen(B)).
"""

# (id, goal, expected `enc` of R or `nothing` for "the goal failed"), run IN ORDER. Every expected value is derived from the C named in the header.
const _MG_CASES = [
    # put/2, put/1: put_code's function (pl-file.c:3505-3517): PL_get_char(chr, &c, false) first, then the stream
    ("pu01", raw"with_output_to(string(S), (put(97), put(98))), R = S", _mgs_("ab")),
    ("pu02", raw"with_output_to(string(S), put(a)), R = S", _mgs_("a")),   # a one-character atom is a character
    (
        "pu03",
        raw"with_output_to(string(S), (current_output(O), put(O, 104), put(O, 105))), R = S",
        _mgs_("hi")
    ),
    (
        "pu04",
        raw"put(-1)",
        _mgraised(_mgc("type_error", _mga("character"), _mgi(-1)))
    ),   # PL_get_char with eof=false: -1 falls through to the type error
    ("pu05", raw"put(foo)", _mgraised(_mgc("type_error", _mga("character"), _mga("foo")))),   # text of length 3
    ("pu06", raw"put(_)", _mgraised(_mga("instantiation_error"))),
    (
        "pu07",
        raw"put(nosuch, 97)",
        _mgraised(_mgc("existence_error", _mga("stream"), _mga("nosuch")))
    ),
    (
        "pu08",
        raw"put(nosuch, foo)",
        _mgraised(_mgc("type_error", _mga("character"), _mga("foo")))
    ),   # the character is checked BEFORE the stream
    (
        "pu09",
        raw"catch((open_string(abc, S), put(S, 97), R = ok), error(permission_error(A, _, _), _), R = perm(A))",
        _mgc("perm", _mga("output"))
    ),   # put on an input stream
    (
        "pu10",
        raw"with_output_to(string(S), (put(0'a), put(10), put(0'b), current_output(O), line_count(O, L), line_position(O, P))), R = S-L-P",
        _mgc("-", _mgc("-", _mgs_("a\nb"), _mgi(2)), _mgi(1))
    ),   # put(10) is the newline: the position follows the code, as for put_code
    # get/2: get_nonblank (pl-file.c:3520-3560)
    ("ge01", raw"open_string('  ab', S), get(S, C), R = C", _mgi(97)),   # blanks skipped
    (
        "ge02",
        raw"open_string('a b', S), get(S, A), get(S, B), R = A-B",
        _mgc("-", _mgi(97), _mgi(98))
    ),
    ("ge03", raw"open_string('\n\t x', S), get(S, C), R = C", _mgi(120)),   # newline and tab are blank
    ("ge04", raw"open_string('', S), get(S, C), R = C", _mgi(-1)),   # EOF: -1
    ("ge05", raw"open_string('   ', S), get(S, C), R = C", _mgi(-1)),   # only blanks, then EOF
    (
        "ge06",
        raw"open_string(a, S), get(S, A), get(S, B), R = A-B",
        _mgc("-", _mgi(97), _mgi(-1))
    ),
    ("ge07", raw"open_string('  é', S), get(S, C), R = C", _mgi(233)),   # a wide character
    (
        "ge08",
        raw"open_string(ab, S), ( get(S, 98) -> X = yes ; X = no ), get_code(S, C), R = X-C",
        _mgc("-", _mga("no"), _mgi(98))
    ),   # get(S, 98) reads `a`, the unification fails, `a` stays consumed
    ("ge09", raw"open_string(ab, S), get(S, a)", nothing),   # no type check of the second argument: plain failure (get_code/2 raises here)
    ("ge10", raw"open_string(ab, S), get(S, 97), R = ok", _mga("ok")),
    # get/1 reads the CURRENT input (the same get_nonblank, stream 0): the row switches it to a string stream and back
    (
        "ge15",
        raw"open_string('  ab', S), current_input(O), set_input(S), get(C), set_input(O), R = C",
        _mgi(97)
    ),
    ("ge16", raw"open_string('', S), current_input(O), set_input(S), get(C), set_input(O), R = C", _mgi(-1)),
    (
        "ge11",
        raw"get(nosuch, _)",
        _mgraised(_mgc("existence_error", _mga("stream"), _mga("nosuch")))
    ),
    ("ge12", raw"get(_, _)", _mgraised(_mga("instantiation_error"))),
    (
        "ge13",
        raw"catch((with_output_to(string(_), (current_output(O), get(O, _))), R = ok), error(permission_error(A, _, _), _), R = perm(A))",
        _mgc("perm", _mga("input"))
    ),   # get on an output stream
    (
        "ge14",
        raw"open_string('a\n  b', S), get(S, A), get(S, B), get(S, C), R = A-B-C",
        _mgc("-", _mgc("-", _mgi(97), _mgi(98)), _mgi(-1))
    ),
    # '$call_no_catch'/1 (pl-pro.c:433-450): callProlog with PL_Q_NORMAL; an exception is restored from and cleared, the truth value is ignored,
    # the predicate always succeeds. The printed message goes to user_error (not compared). callProlog's PL_cut_query keeps the bindings.
    ("cn01", raw"'$call_no_catch'(X = 1), R = X", _mgi(1)),
    ("cn02", raw"'$call_no_catch'(fail), R = ok", _mga("ok")),
    ("cn03", raw"'$call_no_catch'(throw(foo)), R = ok", _mga("ok")),
    ("cn04", raw"'$call_no_catch'(true), R = ok", _mga("ok")),
    ("cn05", raw"'$call_no_catch'(_), R = ok", _mga("ok")),   # callProlog's own instantiation error, also swallowed
    ("cn06", raw"'$call_no_catch'(user:(Y = a)), R = Y", _mga("a")),
    # the uncaught ball is printed (print_message(error, unhandled_exception(Ball)), reaching user:message_hook/3 of the program above) and ignored:
    # swipl's VM prints it at the throw, the kernel's print_unhandled_exception after the query (the MISS1 mutants CN5 kills this row)
    (
        "cn07",
        raw"'$call_no_catch'(throw(mg_ball)), aggregate_all(count, mg_seen(mg_ball), N), R = N",
        _mgi(1)
    ),
    # '$unload_file'/1 (pl-srcfile.c:839-885, unloadFile :796-835, delAllModulesSourceFile__unlocked :492-530): PL_get_atom_ex(A1), then
    # lookupSourceFile(name, false): an unknown name is `true` (nothing happens); a known one has its clauses removed (unloadFile) and its
    # modules detached (m->file = NULL, public table cleared). `@DIR@` is the test's temp directory (miss_u.pl: mu_p/1 with 2 clauses and
    # mu_q/1; miss_um.pl: module miss_um exporting mum_p/1). The predicate_property/module_property answers after an unload are DERIVED from the C
    # (no clauses and not dynamic = not isDefinedProcedure; m->file NULL = no file(_) property; public table cleared = exports []) and were
    # MEASURED on the pinned swipl 18168e62 (2026-11-22, by hand): ul01 2-yes-no, ul02 2, ul03 ok, ul04 instantiation_error, ul05 type_error(atom,1),
    # ul06 no-[], ul07 ok (the live test below compares every line again).
    (
        "ul01",
        raw"load_files('@DIR@/miss_u.pl', []), aggregate_all(count, mu_p(_), N0), ( predicate_property(mu_p(_), defined) -> D0 = yes ; D0 = no ), '$unload_file'('@DIR@/miss_u.pl'), ( predicate_property(mu_p(_), defined) -> D1 = yes ; D1 = no ), R = N0-D0-D1",
        _mgc("-", _mgc("-", _mgi(2), _mga("yes")), _mga("no"))
    ),   # pinned swipl 18168e62: 2-yes-no
    (
        "ul02",
        raw"load_files('@DIR@/miss_u.pl', []), '$unload_file'('@DIR@/miss_u.pl'), load_files('@DIR@/miss_u.pl', []), aggregate_all(count, mu_p(_), N), R = N",
        _mgi(2)
    ),   # an unloaded file loads again from scratch (the file is not up to date: its time and clause count are gone)
    ("ul03", raw"'$unload_file'('@DIR@/nosuchfile.pl'), R = ok", _mga("ok")),   # an unknown file: `return true`
    ("ul04", raw"'$unload_file'(_)", _mgraised(_mga("instantiation_error"))),   # PL_get_atom_ex
    (
        "ul05",
        raw"'$unload_file'(1)",
        _mgraised(_mgc("type_error", _mga("atom"), _mgi(1)))
    ),   # PL_get_atom_ex
    (
        "ul06",
        raw"load_files('@DIR@/miss_um.pl', []), '$unload_file'('@DIR@/miss_um.pl'), ( module_property(miss_um, file(_)) -> F = yes ; F = no ), module_property(miss_um, exports(E)), R = F-E",
        _mgc("-", _mga("no"), "nil")
    ),   # m->file = NULL, clearHTableWP(m->public): pinned swipl 18168e62: no-[]
    (
        "ul07",
        raw"load_files('@DIR@/miss_u.pl', []), '$unload_file'('@DIR@/miss_u.pl'), '$unload_file'('@DIR@/miss_u.pl'), R = ok",
        _mga("ok")
    ),   # the second call finds the file (still in the table) with no procedures and no modules: unloadFile does nothing, true
    # '$sig_unblock'/0 (pl-thread.c:3897): unblock_signals(); return true — always true (no thread signal is queued here or in the program)
    ("sg01", raw"'$sig_unblock', R = ok", _mga("ok")),
    ("sg02", raw"'$sig_unblock', '$sig_unblock', R = ok", _mga("ok")),
    # '$leash'/2, '$visible'/2 (pl-trace.c:2383-2393, setInteger pl-util.c:314-322): unify Old with the current port mask, then read New as a C int
    # and store it; the masks start as initTracer sets them (pl-trace.c:2081-2083: CALL|FAIL|REDO|EXIT|CUT_CALL|EXCEPTION = 0x1+0x4+0x8+0x2+0x40+0x100 =
    # 335). tracing/0 is false at start (debugstatus.tracing). The rows that SET a mask restore it. NOT a row: trace/0 (swipl would start the tracer
    # and prompt on stdin): the direct testset below. MEASURE ON THE LANE: ld01/vs01 `swipl -g "'\$leash'(O,O),print(O),nl,'\$visible'(V,V),print(V),nl" -t halt`.
    ("ld01", raw"'$leash'(O, O), R = O", _mgi(335)),
    ("ld02", raw"'$leash'(O0, 3), '$leash'(O1, O0), R = O1", _mgi(3)),   # the second call returns what the first stored, and restores
    ("ld03", raw"'$leash'(O0, 7), '$leash'(7, O0), R = ok", _mga("ok")),
    (
        "ld04",
        raw"'$leash'(O0, O0), ( '$leash'(1000, 3) -> R = yes ; '$leash'(O1, O1), ( O1 == O0 -> R = unchanged ; R = changed ) )",
        _mga("unchanged")
    ),   # Old does not unify: false, the mask is not set
    ("ld05", raw"'$leash'(_, _)", _mgraised(_mga("instantiation_error"))),   # PL_get_integer_ex(new)
    (
        "ld06",
        raw"'$leash'(_, foo)",
        _mgraised(_mgc("type_error", _mga("integer"), _mga("foo")))
    ),
    ("vs01", raw"'$visible'(O, O), R = O", _mgi(335)),
    ("vs02", raw"'$visible'(O0, 5), '$visible'(O1, O0), R = O1", _mgi(5)),
    (
        "vs03",
        raw"'$leash'(L0, L0), '$visible'(V0, 9), '$leash'(L1, L1), '$visible'(_, V0), ( L1 == L0 -> R = independent ; R = shared )",
        _mga("independent")
    ),   # the two masks are separate fields
    (
        "vs04",
        raw"'$visible'(_, bar)",
        _mgraised(_mgc("type_error", _mga("integer"), _mga("bar")))
    ),
    ("tg01", raw"( tracing -> R = on ; R = off )", _mga("off")),
    # prolog_choice_attribute/3 (pl-trace.c:2718-2762, PL_get_choice :175-190, the pin 18168e62): PL_get_choice(A1) (an integer position of a live
    # choice point, else existence_error(choice, A1); a non-integer: type_error(choice, A1), an unbound one the instantiation_error PL_error makes of
    # a type error on a variable), PL_get_atom_ex(A2), then the key: parent (skipping CHP_DEBUG; fails without one), frame, type (choice_type_atom),
    # pc (in_clause_jump's offset, else fail), clause (CHP_CLAUSE only), else domain_error(key, A2). The CURRENT choice's type depends on the surrounding
    # query, so the rows pin what holds for any answer (a type atom of the five, an integer frame, an older parent) and two exact ones
    # (mg_or: the `;`'s CHP_JUMP inside the clause, `jump` with an integer pc; mg_cc: the clause choice's NEXT clause, `clause-2`).
    # MEASURE ON THE LANE (the live test compares every line with swipl): ca09 (`jump-pc`), ca10 (`clause-2`), ca08 (instantiation_error).
    (
        "ca01",
        raw"prolog_current_choice(C), prolog_choice_attribute(C, type, T), memberchk(T, [jump, clause, top, catch, debug, foreign]), R = ok",
        _mga("ok")
    ),
    ("ca02", raw"prolog_current_choice(C), prolog_choice_attribute(C, frame, F), integer(F), R = ok", _mga("ok")),
    (
        "ca03",
        raw"prolog_current_choice(C), ( prolog_choice_attribute(C, parent, P) -> ( integer(P), P < C -> R = older ; R = other ) ; R = noparent )",
        _mga("older")
    ),
    (
        "ca04",
        raw"prolog_current_choice(C), prolog_choice_attribute(C, foo, _)",
        _mgraised(_mgc("domain_error", _mga("key"), _mga("foo")))
    ),
    (
        "ca05",
        raw"prolog_choice_attribute(foo, type, _)",
        _mgraised(_mgc("type_error", _mga("choice"), _mga("foo")))
    ),
    (
        "ca06",
        raw"prolog_choice_attribute(123456789, type, _)",
        _mgraised(_mgc("existence_error", _mga("choice"), _mgi(123456789)))
    ),
    (
        "ca07",
        raw"prolog_current_choice(C), prolog_choice_attribute(C, 1, _)",
        _mgraised(_mgc("type_error", _mga("atom"), _mgi(1)))
    ),
    ("ca08", raw"prolog_choice_attribute(_, type, _)", _mgraised(_mga("instantiation_error"))),
    ("ca09", raw"mg_or(R)", _mgc("-", _mga("jump"), _mga("pc"))),
    ("ca10", raw"mg_cc(R)", _mgc("-", _mga("clause"), _mgi(2))),
    (
        "ca11",
        raw"prolog_current_choice(C), prolog_choice_attribute(C, frame, F), prolog_frame_attribute(F, level, L), integer(L), R = ok",
        _mga("ok")
    ),
    # a non-deterministic foreign call's choice point is a CHP_JUMP whose code is I_FREDO (`foreign`); the row's own catch/3 choice is the
    # current one before any call (`catch`). MEASURE ON THE LANE: ca12 `swipl -g "between(1,3,_), prolog_current_choice(C), prolog_choice_attribute(C,type,T), print(T), nl" -t halt`
    ("ca12", raw"between(1, 3, _), prolog_current_choice(C), prolog_choice_attribute(C, type, T), R = T", _mga("foreign")),
    ("ca13", raw"prolog_current_choice(C), prolog_choice_attribute(C, type, T), R = T", _mga("catch")),
    # the `pc` key's OFFSET, pinned exactly (MISS1 mutants PC1/PC2): the code offset of mg_pc's `;` jump choice point inside its clause,
    # MEASURED against the pinned swipl 18168e62: `swipl -q` on the program, `mg_pc(P), print(P)` prints 15. The kernel's `value_pc - 1`
    # (in_clause_jump) equals it only while the kernel compiles to swipl's word layout: a kernel answer other than 15 is a layout difference
    # to be reported, not a test fault.
    ("ca14", raw"mg_pc(R)", _mgi(15)),
    # trace/0 where the kernel does NOT refuse (audit D-0768 (2): no port of PORT_MASK is visible, so the tracer cannot stop): swipl answers as the
    # kernel does, MEASURED with the pin: `'$visible'(V0, 0), trace, ( tracing -> A = on ; A = off ), notrace, ( tracing -> B = on ; B = off )`
    # gives on-off (a mask of 0 and one outside PORT_MASK, 512, alike). The rows restore the mask and the debug mode (`nodebug`: trace/0 switches the
    # debug mode on). The refusal with a port visible is kernel-only: the direct testset below (swipl enters its tracer there).
    (
        "tr01",
        raw"'$visible'(V0, 0), trace, ( tracing -> A = on ; A = off ), notrace, ( tracing -> B = on ; B = off ), nodebug, '$visible'(_, V0), R = A-B",
        _mgc("-", _mga("on"), _mga("off"))
    ),
    (
        "tr02",
        raw"'$visible'(V0, 512), trace, ( tracing -> A = on ; A = off ), notrace, ( tracing -> B = on ; B = off ), nodebug, '$visible'(_, V0), R = A-B",
        _mgc("-", _mga("on"), _mga("off"))
    ),
]

"The expected lines (the driver's output) of the rows."
_mg_expected() = vcat(
    ["ok"],
    [
        e === nothing ? "t_$id" : "t_$id " * _mgc("t_$id", e) for (id, _, e) in _MG_CASES
    ]
)

function _mg_file(dir::String)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _, _) in _MG_CASES]
    text =
        _MG_PROGRAM * join([
            "t_$(id)(R) :- catch(($(replace(g, "@DIR@" => dir))), error(SsuE, _), R = raised(SsuE)).\n"
            for (id, g, _) in _MG_CASES
        ])
    f = joinpath(dir, "miss_preds.pl")
    write(joinpath(dir, "miss_u.pl"), "mu_p(1).\nmu_p(2).\nmu_q(x).\n")        # the files '\$unload_file' rows load and unload
    write(
        joinpath(dir, "miss_um.pl"), ":- module(miss_um, [mum_p/1]).\nmum_p(7).\n"
    )
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _mg_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MG}()
    ld = LK.PL_local_data{_MG}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mg_enc(ball::_MG)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mgs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MG, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mg_enc(mk_expr(_MG, _MG[_mgs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "put/1,2, get/1,2, '\$call_no_catch'/1 and '\$unload_file'/1 as the C (pu01-pu10, ge01-ge16, cn01-cn07, ul01-ul07, sg01-sg02, ld01-ld06, vs01-vs04, tg01, ca01-ca14, tr01-tr02)" begin
    f, names = _mg_file(mktempdir())
    kl = _mg_kernel(f, names)
    ex = _mg_expected()
    @test length(kl) == length(ex)
    for (k, p) in zip(kl, ex)
        k == p || println(stderr, "  ours      ", k, "\n  expected  ", p)
        @test k == p
    end
    # not vacuous: the expectation holds raised errors, `ok` and answers, and one failing row (ge09)
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), ex) == 17    # raised(…) (7 + ul04, ul05 + ld05, ld06, vs04 + ca04-ca08)
    @test count(l -> occursin(r"^t_\w+ *$", l), ex) == 1                   # ge09 fails
    @test count(l -> occursin("i-1)", l), ex) == 6                         # -1 in an answer (pu04's character, the EOF answers, ge16)
end

@testset "the expected lines are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_mg_expected()) == length(_MG_CASES) + 1
    if swipl === nothing
        @info "MISS1 get/put LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mg_file(mktempdir())
        @test _mg_swipl_lines(f, names) == _mg_expected()
    end
end

# trace/0 (pl-trace.c:2287-2290) is `tracemode(true, NULL)`; the kernel has no tracer, so with a port of PORT_MASK visible it is refused by name
# BEFORE any state changes (audit D-0768 (2); owner row DBG2 in docs/r2_owners.tsv, mutants MISS1-TR3 and MISS1-TR4). LK-ONLY: swipl enters its tracer
# there (MEASURED with the pin: `swipl -q -g "trace, writeln(x)" -t halt < /dev/null` prints `   Call: (12) writeln(x) ? ` and exits with status 4 at EOF),
# so no row of _MG_CASES can pin the refusal. The rows tr01, tr02 pin the not-refused side against swipl.
_mg_refused(f) =
    try
        f()
        nothing
    catch e
        e isa LK.NotPortedError ? e : rethrow()
    end

@testset "trace/0, notrace/0, tracing/0 and the initial port masks, called directly (the tracer is not started)" begin
    gd = LK.PL_global_data{_MG}()
    ld = LK.PL_local_data{_MG}(gd)
    @test ld.debugstatus_leashing == 0x14f            # initTracer: CALL|FAIL|REDO|EXIT|CUT_CALL|EXCEPTION
    @test ld.debugstatus_visible == 0x14f
    @test LK.CALL_PORT | LK.FAIL_PORT | LK.REDO_PORT | LK.EXIT_PORT | LK.CUT_CALL_PORT | LK.EXCEPTION_PORT == 0x14f
    @test LK.CUT_PORT == 0xc0 && LK.PORT_MASK == 0x1ff && LK.UNIFY_PORT == 0x10 && LK.NO_PORT == 0
    @test LK.pl_tracing(ld) == LK.FFALSE
    @test !ld.debugstatus_debugging
    # the initial mask shows ports: trace/0 is refused by name, DBG2, and nothing changes
    e = _mg_refused(() -> LK.pl_trace(ld))
    @test e isa LK.NotPortedError && e.step == "DBG2" && occursin("trace/0 with a visible port", e.what)
    @test LK.pl_tracing(ld) == LK.FFALSE
    @test !ld.debugstatus_debugging
    sk = ld.debugstatus_skiplevel
    # one visible port of each kind refuses; a mask outside PORT_MASK (0x200, 0x400) or 0 shows no port: tracemode(true)
    for (v, refused) in (
        (0x001, true), (0x002, true), (0x004, true), (0x008, true), (0x010, true), (0x040, true),
        (0x080, true), (0x100, true), (0x1ff, true), (0x3ff, true), (0x200, false), (0x400, false),
        (0x000, false)
    )
        ld.debugstatus_visible = v
        ld.debugstatus_leashing = 0                    # the leashed ports play no part
        e = _mg_refused(() -> LK.pl_trace(ld))
        if refused
            @test e isa LK.NotPortedError
            @test LK.pl_tracing(ld) == LK.FFALSE && !ld.debugstatus_debugging && ld.debugstatus_skiplevel == sk
        else
            @test e === nothing
            @test LK.pl_tracing(ld) == LK.FTRUE && ld.debugstatus_debugging   # tracemode(true): the debug mode goes on with it
            @test ld.debugstatus_skiplevel == LK.SKIP_VERY_DEEP
            @test LK.pl_notrace(ld) == LK.FTRUE
            @test LK.pl_tracing(ld) == LK.FFALSE
            @test ld.debugstatus_debugging             # notrace switches the trace mode off only
            @test LK.debugmode(ld, false, nothing, UInt32(0))
            @test !ld.debugstatus_debugging
            ld.debugstatus_skiplevel = sk
        end
    end
    # trace mode already on, then a port made visible: refused again, and the mode stays on (the test comes before tracemode)
    ld.debugstatus_visible = 0x000
    @test LK.pl_trace(ld) == LK.FTRUE
    @test LK.pl_trace(ld) == LK.FTRUE                  # trace again: still on, still true
    ld.debugstatus_visible = LK.CALL_PORT
    @test _mg_refused(() -> LK.pl_trace(ld)) isa LK.NotPortedError
    @test LK.pl_tracing(ld) == LK.FTRUE
    @test LK.pl_notrace(ld) == LK.FTRUE
    @test LK.pl_tracing(ld) == LK.FFALSE
end
