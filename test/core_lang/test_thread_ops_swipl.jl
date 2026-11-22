# ORIGINAL: a LIVE differential of the THREAD OPERATIONS of pl-thread.c against swipl at the pin (swipl-devel 18168e62; swipl 10.1.20):
# is_thread/1, thread_join/2, thread_detach/1, set_thread/2 and debug_reset_from_class/0, on the main thread (rows tp51-tp102, ids kept from
# the THREADPROP rows) and on engines (rows te01-te30), with the state-changing rows of the main thread (sc01-sc21, aq01-aq07) LAST.
#   * A PROGRAM-less file of cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(E, _), R = raised(E))`;
#     the driver is test_mutex_swipl.jl's (`enc`oded answers). An engine handle is never printed (a blob): rows compare `C == E` and print `same`.
#   * Every swipl answer line is swipl's, PINNED (swipl 10.1.20, the pin binary, two runs byte-identical, evidence/THREADOPS/gen_rows.py
#     --fill); with `swipl` on PATH the live answers are compared with the pins too.
#   * ORDER = the order of `_TO_CASES`: the state-NEUTRAL rows come first, the state-CHANGING rows last (a row that sets the class,
#     debug flags or detach state of the main thread changes the later rows' answers in swipl).
#   * KNOWN DIFFERENCE (kd01, kd02): swipl's main thread has the class `console` from the start (the toplevel sets it); the kernel's has none,
#     `thread_property(main, class(_))` FAILS until `set_thread(main, class(console))`. The kernel's exact answer is pinned in `_TO_KD`, swipl's
#     in `_TO_PINNED`; every row that reads or sets the class comes after sc01 (`set_thread(main, class(console))`), where both agree.
#   * ALIAS QUIRK (aq01-aq07, pl-thread.c set_thread): `set_thread(E, alias(A))` of an engine without an alias aliases the CALLER, here the
#     main thread: `thread_self(X)` then gives A, `thread_property(main, alias(_))` gives A, the name `main` still names the thread, the
#     owner of a locked mutex is A.
#   * REFUSED by name (TH1), kernel only (never run in swipl: joining the main thread from an engine would hang there): rf01-rf04, each its own
#     database (a NotPortedError ends the run); each asserts the exception's step and `what`.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: all three: the predicates take the term type through the term interface (atoms, integers, compounds)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TO = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tos(x) = lk_sym(_TO, Symbol(x))

_to_codes(s::AbstractString) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _to_enc(t::_TO, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _to_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _to_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _to_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_to_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end


# hand-built encodings of expected answers (never read from swipl)
_to_a(s) = "a" * _to_codes(s)
_to_c(name, args...) = "c" * _to_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_to_list(xs) = isempty(xs) ? "nil" : _to_c("[|]", xs[1], _to_list(xs[2:end]))

# the swipl side: test/core_lang/test_mutex_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _TO_DRIVER = raw"""
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
function _to_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TO_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# tp51-tp62 is_thread/1, tp63-tp70 thread_join/2, tp71-tp74 thread_detach/1, tp75-tp99 set_thread/2, tp100-tp102 debug_reset_from_class/0
# (main thread, state-neutral); te01-te30 engines (neutral for the main thread); kd01-kd02 the known difference (main's class);
# sc01-sc21 and aq01-aq07 change the main thread's class, debug flag, detach state and alias: LAST.
const _TO_CASES = [
    ("tp51", raw"is_thread(main), R = yes"),
    ("tp52", raw"is_thread(1), R = yes"),
    ("tp53", raw"is_thread(foo), R = yes"),
    ("tp54", raw"is_thread(_), R = yes"),
    ("tp55", raw"is_thread(99), R = yes"),
    ("tp56", raw"is_thread(0), R = yes"),
    ("tp57", raw"is_thread(1.5), R = yes"),
    ("tp58", raw"is_thread(f(x)), R = yes"),
    ("tp59", raw"is_thread(\"str\"), R = yes"),
    ("tp60", raw"is_thread([]), R = yes"),
    ("tp61", raw"findall(x, is_thread(main), R)"),
    ("tp62", raw"call_cleanup(is_thread(main), Det = true), R = Det"),
    ("tp63", raw"thread_join(main, _)"),
    ("tp64", raw"thread_join(1, _)"),
    ("tp65", raw"thread_join(nosuch, _)"),
    ("tp66", raw"thread_join(1.5, _)"),
    ("tp67", raw"thread_join(_, _)"),
    ("tp68", raw"thread_join(f(x), _)"),
    ("tp69", raw"thread_join(99, _)"),
    ("tp70", raw"thread_join(main, foo)"),
    ("tp71", raw"thread_detach(nosuch)"),
    ("tp72", raw"thread_detach(1.5)"),
    ("tp73", raw"thread_detach(99)"),
    ("tp74", raw"thread_detach(_)"),
    ("tp75", raw"set_thread(main, alias(foo))"),
    ("tp76", raw"set_thread(main, alias(_))"),
    ("tp77", raw"set_thread(main, alias(1))"),
    ("tp78", raw"set_thread(main, bogus(1))"),
    ("tp79", raw"set_thread(main, 1)"),
    ("tp80", raw"set_thread(main, foo)"),
    ("tp81", raw"set_thread(main, foo(1, 2))"),
    ("tp82", raw"set_thread(main, _)"),
    ("tp83", raw"set_thread(nosuch, alias(x))"),
    ("tp84", raw"set_thread(99, alias(x))"),
    ("tp85", raw"set_thread(1.5, alias(x))"),
    ("tp86", raw"set_thread(_, alias(x))"),
    ("tp87", raw"set_thread(main, class(1))"),
    ("tp88", raw"set_thread(main, class(_))"),
    ("tp89", raw"set_thread(main, debug(maybe))"),
    ("tp90", raw"set_thread(main, debug(_))"),
    ("tp91", raw"set_thread(main, debug_mode(maybe))"),
    ("tp92", raw"set_thread(main, debug_mode(_))"),
    ("tp93", raw"set_thread(main, debug_mode(false)), R = ok"),
    ("tp94", raw"set_thread(1, debug_mode(false)), R = ok"),
    ("tp95", raw"set_thread(self, debug_mode(false)), R = ok"),
    ("tp96", raw"set_thread(self, bogus(1))"),
    ("tp97", raw"set_thread(self, 1)"),
    ("tp98", raw"set_thread(self, alias(foo))"),
    ("tp99", raw"set_thread(main, debug_mode(false)), thread_property(main, debug_mode(X)), R = X"),
    ("tp100", raw"debug_reset_from_class, R = ok"),
    ("tp101", raw"findall(x, debug_reset_from_class, R)"),
    ("tp102", raw"debug_reset_from_class, thread_property(main, status(X)), R = X"),
    # engines: the engine handle E is a blob, `C == E` prints `same`
    ("te01", raw"engine_create(x, true, E), catch(thread_join(E, _), error(permission_error(J, T, C), context(Cx, M)), true), ( C == E -> S = same ; S = other ), R = J-T-S-Cx-M"),
    ("te02", raw"engine_create(x, true, E), thread_detach(E), R = ok"),
    ("te03", raw"engine_create(x, true, E), thread_property(E, detached(R))"),
    ("te04", raw"engine_create(x, true, E), is_thread(E), R = yes"),
    ("te05", raw"engine_create(x, true, E), set_thread(E, debug(false)), thread_property(E, debug(R))"),
    ("te06", raw"engine_create(x, true, E), set_thread(E, debug(true)), thread_property(E, debug(R))"),
    ("te07", raw"engine_create(x, true, E), set_thread(E, class(foo)), thread_property(E, class(C)), thread_property(E, debug_mode(D)), R = C-D"),
    ("te08", raw"engine_create(x, true, E), thread_property(E, class(R))"),
    ("te09", raw"engine_create(x, true, E), set_thread(E, class(user)), thread_property(E, class(R))"),
    ("te10", raw"engine_create(x, true, E), set_thread(E, debug_mode(maybe))"),
    ("te11", raw"engine_create(x, true, E), set_thread(E, bogus(1))"),
    ("te12", raw"engine_create(x, true, E, [alias(teal12)]), catch(set_thread(E, alias(teal12b)), error(permission_error(A, B, C), _), true), ( C == E -> S = same ; S = other ), R = A-B-S"),
    ("te13", raw"engine_create(x, true, _, [alias(teal13)]), set_thread(teal13, alias(teal13b))"),
    ("te14", raw"engine_create(x, true, E), set_thread(E, class(_))"),
    ("te15", raw"engine_create(x, true, E), set_thread(E, class(1))"),
    ("te16", raw"engine_create(x, true, E), set_thread(E, debug(maybe))"),
    ("te17", raw"engine_create(C, (thread_self(Me), set_thread(self, class(zz17)), thread_property(Me, class(C))), E), engine_next(E, R)"),
    ("te18", raw"engine_create(R0, (thread_self(Me), catch(thread_join(Me, _), error(permission_error(J, T, _), context(_, M)), true), R0 = J-T-M), E), engine_next(E, R)"),
    ("te19", raw"engine_create(ok, (thread_self(Me), thread_detach(Me)), E), engine_next(E, R)"),
    ("te20", raw"engine_create(ok, debug_reset_from_class, E), engine_next(E, R)"),
    ("te21", raw"engine_create(A, (set_thread(self, alias(zz21)), thread_self(A)), E), engine_next(E, R)"),
    ("te23", raw"engine_create(x, true, E), engine_destroy(E), catch(is_thread(E), error(Er, _), true), ( var(Er) -> R = answered ; Er =.. [N|_], R = raised(N) )"),
    ("te24", raw"engine_create(x, true, E), engine_destroy(E), catch(thread_detach(E), error(Er, _), true), ( var(Er) -> R = answered ; Er =.. [N|_], R = raised(N) )"),
    ("te25", raw"engine_create(R0, (thread_self(Me), is_thread(Me), R0 = yes), E), engine_next(E, R)"),
    ("te26", raw"engine_create(R0, (thread_self(Me), set_thread(Me, debug(false)), thread_property(Me, debug(R0))), E), engine_next(E, R)"),
    # the join error of the main thread names the thread as given and its message (the C order: detached, else self)
    ("te27", raw"catch(thread_join(main, _), error(permission_error(J, T, C), context(Cx, M)), true), R = J-T-C-Cx-M"),
    ("te28", raw"catch(thread_join(1, _), error(permission_error(J, T, C), context(Cx, M)), true), R = J-T-C-Cx-M"),
    ("te29", raw"catch(thread_detach(nosuch), error(E, context(Cx, _)), true), R = E-Cx"),
    ("te30", raw"catch(set_thread(main, alias(foo)), error(E, context(Cx, _)), true), R = E-Cx"),
    # the known difference: main's class
    ("kd01", raw"thread_property(main, class(R))"),
    ("kd02", raw"findall(C, thread_property(main, class(C)), R)"),
    # state-changing rows of the main thread
    ("sc01", raw"set_thread(main, class(console)), R = ok"),
    ("sc02", raw"thread_property(main, class(R))"),
    ("sc03", raw"set_thread(main, class(console)), thread_property(main, class(R))"),
    ("sc04", raw"debug_reset_from_class, thread_property(main, debug_mode(R))"),
    ("sc05", raw"engine_create(ok, set_thread(main, class(console)), E), engine_next(E, R)"),
    ("sc06", raw"set_thread(main, class(foo)), thread_property(main, class(R))"),
    ("sc07", raw"set_thread(main, class(console)), thread_property(main, class(C)), thread_property(main, debug_mode(D)), R = C-D"),
    ("sc08", raw"set_thread(main, debug(false)), thread_property(main, debug(R))"),
    ("sc09", raw"set_thread(main, debug(true)), thread_property(main, debug(R))"),
    ("sc10", raw"set_thread(1, debug(false)), thread_property(main, debug(R))"),
    ("sc11", raw"thread_property(main, detached(R))"),
    ("sc12", raw"engine_create(ok, thread_detach(main), E), engine_next(E, R)"),
    ("sc13", raw"thread_property(main, detached(R))"),
    ("sc14", raw"thread_detach(main), R = ok"),
    ("sc15", raw"thread_detach(1), R = ok"),
    ("sc16", raw"catch(thread_join(main, _), error(permission_error(J, T, C), context(Cx, M)), true), R = J-T-C-Cx-M"),
    ("sc17", raw"thread_join(main, _)"),
    ("sc18", raw"engine_create(R0, (catch(thread_join(main, _), error(permission_error(J, T, C), context(_, M)), true), R0 = J-T-C-M), E), engine_next(E, R)"),
    ("sc19", raw"thread_property(main, status(R))"),
    ("sc20", raw"engine_create(R0, (thread_self(Me), set_thread(Me, debug(false)), set_thread(main, debug(true)), thread_property(main, debug(R0))), E), engine_next(E, R)"),
    ("sc21", raw"debug_reset_from_class, R = ok"),
    # the alias quirk: set_thread(E, alias(A)) of an engine without an alias aliases the CALLER (main)
    ("aq01", raw"engine_create(x, true, E), set_thread(E, alias(zz)), R = ok"),
    ("aq02", raw"thread_self(R)"),
    ("aq03", raw"thread_property(main, alias(R))"),
    ("aq04", raw"thread_property(zz, alias(R))"),
    ("aq05", raw"thread_property(zz, id(R))"),
    ("aq06", raw"thread_property(main, id(R))"),
    ("aq07", raw"thread_property(T, alias(zz)), R = T"),
    ("aq08", raw"is_thread(zz), is_thread(main), R = yes"),
    ("aq09", raw"mutex_create(mxaq9), mutex_lock(mxaq9), mutex_property(mxaq9, status(R))"),
    ("aq10", raw"catch(set_thread(main, alias(other)), error(E, _), true), R = E"),
    ("aq11", raw"catch(set_thread(zz, alias(other)), error(E, _), true), R = E"),
    ("aq12", raw"set_thread(self, alias(other))"),
    ("aq13", raw"engine_create(R0, (thread_self(Me), ( Me == zz -> R0 = same ; R0 = other )), E), engine_next(E, R)"),
    # debug_mode(true): the VM in debug mode, LAST
    ("dm01", raw"engine_create(x, true, E), set_thread(E, debug_mode(true)), thread_property(E, debug_mode(R))"),
    ("dm02", raw"engine_create(x, true, E), set_thread(E, debug_mode(true)), set_thread(E, debug_mode(false)), thread_property(E, debug_mode(R))")
]

# swipl 10.1.20's answers (the driver's lines): `ok`, then one line per case (filled by evidence/THREADOPS/gen_rows.py --fill)
const _TO_PINNED = [
    "ok",
    "t_tp51 c[116,95,116,112,53,49]/1(a[121,101,115])",
    "t_tp52 c[116,95,116,112,53,50]/1(a[121,101,115])",
    "t_tp53",
    "t_tp54",
    "t_tp55",
    "t_tp56",
    "t_tp57",
    "t_tp58",
    "t_tp59",
    "t_tp60",
    "t_tp61 c[116,95,116,112,54,49]/1(c[91,124,93]/2(a[120],nil))",
    "t_tp62 c[116,95,116,112,54,50]/1(a[116,114,117,101])",
    "t_tp63 c[116,95,116,112,54,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[106,111,105,110],a[116,104,114,101,97,100],a[109,97,105,110])))",
    "t_tp64 c[116,95,116,112,54,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[106,111,105,110],a[116,104,114,101,97,100],i1)))",
    "t_tp65 c[116,95,116,112,54,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[110,111,115,117,99,104])))",
    "t_tp66 c[116,95,116,112,54,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],f1.5)))",
    "t_tp67 c[116,95,116,112,54,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp68 c[116,95,116,112,54,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],c[102]/1(a[120]))))",
    "t_tp69 c[116,95,116,112,54,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_tp70 c[116,95,116,112,55,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[106,111,105,110],a[116,104,114,101,97,100],a[109,97,105,110])))",
    "t_tp71 c[116,95,116,112,55,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[110,111,115,117,99,104])))",
    "t_tp72 c[116,95,116,112,55,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],f1.5)))",
    "t_tp73 c[116,95,116,112,55,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_tp74 c[116,95,116,112,55,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp75 c[116,95,116,112,55,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[109,97,105,110])))",
    "t_tp76 c[116,95,116,112,55,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp77 c[116,95,116,112,55,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_tp78 c[116,95,116,112,55,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[116,104,114,101,97,100,95,112,114,111,112,101,114,116,121],c[98,111,103,117,115]/1(i1))))",
    "t_tp79 c[116,95,116,112,55,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,111,112,101,114,116,121],i1)))",
    "t_tp80 c[116,95,116,112,56,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,111,112,101,114,116,121],a[102,111,111])))",
    "t_tp81 c[116,95,116,112,56,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,111,112,101,114,116,121],c[102,111,111]/2(i1,i2))))",
    "t_tp82 c[116,95,116,112,56,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp83 c[116,95,116,112,56,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[110,111,115,117,99,104])))",
    "t_tp84 c[116,95,116,112,56,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],i99)))",
    "t_tp85 c[116,95,116,112,56,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],f1.5)))",
    "t_tp86 c[116,95,116,112,56,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp87 c[116,95,116,112,56,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_tp88 c[116,95,116,112,56,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp89 c[116,95,116,112,56,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_tp90 c[116,95,116,112,57,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp91 c[116,95,116,112,57,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_tp92 c[116,95,116,112,57,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tp93 c[116,95,116,112,57,51]/1(a[111,107])",
    "t_tp94 c[116,95,116,112,57,52]/1(a[111,107])",
    "t_tp95 c[116,95,116,112,57,53]/1(a[111,107])",
    "t_tp96 c[116,95,116,112,57,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[116,104,114,101,97,100,95,112,114,111,112,101,114,116,121],c[98,111,103,117,115]/1(i1))))",
    "t_tp97 c[116,95,116,112,57,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,111,112,101,114,116,121],i1)))",
    "t_tp98 c[116,95,116,112,57,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[115,101,108,102])))",
    "t_tp99 c[116,95,116,112,57,57]/1(a[102,97,108,115,101])",
    "t_tp100 c[116,95,116,112,49,48,48]/1(a[111,107])",
    "t_tp101 c[116,95,116,112,49,48,49]/1(c[91,124,93]/2(a[120],nil))",
    "t_tp102 c[116,95,116,112,49,48,50]/1(a[114,117,110,110,105,110,103])",
    "t_te01 c[116,95,116,101,48,49]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),a[115,97,109,101]),c[47]/2(a[116,104,114,101,97,100,95,106,111,105,110],i2)),a[67,97,110,110,111,116,32,106,111,105,110,32,100,101,116,97,99,104,101,100,32,116,104,114,101,97,100]))",
    "t_te02 c[116,95,116,101,48,50]/1(a[111,107])",
    "t_te03 c[116,95,116,101,48,51]/1(a[116,114,117,101])",
    "t_te04 c[116,95,116,101,48,52]/1(a[121,101,115])",
    "t_te05 c[116,95,116,101,48,53]/1(a[102,97,108,115,101])",
    "t_te06 c[116,95,116,101,48,54]/1(a[116,114,117,101])",
    "t_te07 c[116,95,116,101,48,55]/1(c[45]/2(a[102,111,111],a[102,97,108,115,101]))",
    "t_te08 c[116,95,116,101,48,56]/1(a[117,115,101,114])",
    "t_te09 c[116,95,116,101,48,57]/1(a[117,115,101,114])",
    "t_te10 c[116,95,116,101,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_te11 c[116,95,116,101,49,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[116,104,114,101,97,100,95,112,114,111,112,101,114,116,121],c[98,111,103,117,115]/1(i1))))",
    "t_te12 c[116,95,116,101,49,50]/1(c[45]/2(c[45]/2(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100]),a[115,97,109,101]))",
    "t_te13 c[116,95,116,101,49,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[116,101,97,108,49,51])))",
    "t_te14 c[116,95,116,101,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_te15 c[116,95,116,101,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_te16 c[116,95,116,101,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_te17 c[116,95,116,101,49,55]/1(a[122,122,49,55])",
    "t_te18 c[116,95,116,101,49,56]/1(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),a[67,97,110,110,111,116,32,106,111,105,110,32,100,101,116,97,99,104,101,100,32,116,104,114,101,97,100]))",
    "t_te19 c[116,95,116,101,49,57]/1(a[111,107])",
    "t_te20 c[116,95,116,101,50,48]/1(a[111,107])",
    "t_te21 c[116,95,116,101,50,49]/1(a[122,122,50,49])",
    "t_te23",
    "t_te24 c[116,95,116,101,50,52]/1(c[114,97,105,115,101,100]/1(a[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]))",
    "t_te25 c[116,95,116,101,50,53]/1(a[121,101,115])",
    "t_te26 c[116,95,116,101,50,54]/1(a[102,97,108,115,101])",
    "t_te27 c[116,95,116,101,50,55]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),a[109,97,105,110]),c[47]/2(a[116,104,114,101,97,100,95,106,111,105,110],i2)),a[67,97,110,110,111,116,32,106,111,105,110,32,115,101,108,102]))",
    "t_te28 c[116,95,116,101,50,56]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),i1),c[47]/2(a[116,104,114,101,97,100,95,106,111,105,110],i2)),a[67,97,110,110,111,116,32,106,111,105,110,32,115,101,108,102]))",
    "t_te29 c[116,95,116,101,50,57]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[116,104,114,101,97,100],a[110,111,115,117,99,104]),c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[116,104,114,101,97,100,95,100,101,116,97,99,104],i1))))",
    "t_te30 c[116,95,116,101,51,48]/1(c[45]/2(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[109,97,105,110]),c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[115,101,116,95,116,104,114,101,97,100],i2))))",
    "t_kd01 c[116,95,107,100,48,49]/1(a[99,111,110,115,111,108,101])",
    "t_kd02 c[116,95,107,100,48,50]/1(c[91,124,93]/2(a[99,111,110,115,111,108,101],nil))",
    "t_sc01 c[116,95,115,99,48,49]/1(a[111,107])",
    "t_sc02 c[116,95,115,99,48,50]/1(a[99,111,110,115,111,108,101])",
    "t_sc03 c[116,95,115,99,48,51]/1(a[99,111,110,115,111,108,101])",
    "t_sc04 c[116,95,115,99,48,52]/1(a[102,97,108,115,101])",
    "t_sc05 c[116,95,115,99,48,53]/1(a[111,107])",
    "t_sc06 c[116,95,115,99,48,54]/1(a[102,111,111])",
    "t_sc07 c[116,95,115,99,48,55]/1(c[45]/2(a[99,111,110,115,111,108,101],a[102,97,108,115,101]))",
    "t_sc08 c[116,95,115,99,48,56]/1(a[102,97,108,115,101])",
    "t_sc09 c[116,95,115,99,48,57]/1(a[116,114,117,101])",
    "t_sc10 c[116,95,115,99,49,48]/1(a[102,97,108,115,101])",
    "t_sc11 c[116,95,115,99,49,49]/1(a[102,97,108,115,101])",
    "t_sc12 c[116,95,115,99,49,50]/1(a[111,107])",
    "t_sc13 c[116,95,115,99,49,51]/1(a[116,114,117,101])",
    "t_sc14 c[116,95,115,99,49,52]/1(a[111,107])",
    "t_sc15 c[116,95,115,99,49,53]/1(a[111,107])",
    "t_sc16 c[116,95,115,99,49,54]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),a[109,97,105,110]),c[47]/2(a[116,104,114,101,97,100,95,106,111,105,110],i2)),a[67,97,110,110,111,116,32,106,111,105,110,32,100,101,116,97,99,104,101,100,32,116,104,114,101,97,100]))",
    "t_sc17 c[116,95,115,99,49,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[106,111,105,110],a[116,104,114,101,97,100],a[109,97,105,110])))",
    "t_sc18 c[116,95,115,99,49,56]/1(c[45]/2(c[45]/2(c[45]/2(a[106,111,105,110],a[116,104,114,101,97,100]),a[109,97,105,110]),a[67,97,110,110,111,116,32,106,111,105,110,32,100,101,116,97,99,104,101,100,32,116,104,114,101,97,100]))",
    "t_sc19 c[116,95,115,99,49,57]/1(a[114,117,110,110,105,110,103])",
    "t_sc20 c[116,95,115,99,50,48]/1(a[116,114,117,101])",
    "t_sc21 c[116,95,115,99,50,49]/1(a[111,107])",
    "t_aq01 c[116,95,97,113,48,49]/1(a[111,107])",
    "t_aq02 c[116,95,97,113,48,50]/1(a[122,122])",
    "t_aq03 c[116,95,97,113,48,51]/1(a[122,122])",
    "t_aq04 c[116,95,97,113,48,52]/1(a[122,122])",
    "t_aq05 c[116,95,97,113,48,53]/1(i1)",
    "t_aq06 c[116,95,97,113,48,54]/1(i1)",
    "t_aq07 c[116,95,97,113,48,55]/1(a[122,122])",
    "t_aq08 c[116,95,97,113,48,56]/1(a[121,101,115])",
    "t_aq09 c[116,95,97,113,48,57]/1(c[108,111,99,107,101,100]/2(a[122,122],i1))",
    "t_aq10 c[116,95,97,113,49,48]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[109,97,105,110]))",
    "t_aq11 c[116,95,97,113,49,49]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[122,122]))",
    "t_aq12 c[116,95,97,113,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,45,97,108,105,97,115],a[116,104,114,101,97,100],a[115,101,108,102])))",
    "t_aq13 c[116,95,97,113,49,51]/1(a[111,116,104,101,114])",
    "t_dm01 c[116,95,100,109,48,49]/1(a[116,114,117,101])",
    "t_dm02 c[116,95,100,109,48,50]/1(a[102,97,108,115,101])"
]

# the rows where the kernel answers differently from swipl (id => the kernel's exact line); swipl's line is in `_TO_PINNED`
const _TO_KD = Dict{String, String}(
    # swipl: class(console) (pl-thread.c: the toplevel sets main's class); the kernel: no class, the property fails
    "kd01" => "t_kd01",
    # swipl: [console]; the kernel: []
    "kd02" => "t_kd02 c[116,95,107,100,48,50]/1(nil)"
)

const _TO_IDS = [id for (id, _) in _TO_CASES]
const _TO_PIN = Dict(zip(_TO_IDS, _TO_PINNED[2:end]))

"The program text: one clause `t_<id>(R)` per case."
function _to_program()::String
    return join(
        [
            "t_$(id)(R) :- catch(($(g)), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TO_CASES
        ]
    )
end

function _to_file()::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "thread_ops.pl")
    write(f, _to_program())
    return f, ["t_$id" for id in _TO_IDS]
end

"""
The kernel's lines for `names` after consulting `path`, as the driver writes swipl's, in a FRESH database. A NotPortedError ends
the run with the line `<name> notported <step> <what>` (the query is abandoned with the database).
"""
function _to_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_TO}()
    ld = LK.PL_local_data{_TO}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _to_enc(ball::_TO)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tos(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_TO, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        try
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, ld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _to_enc(mk_expr(_TO, _TO[_tos(name), lk_answers(ld, (a:a)...)...]))
                    )
                    rc == LK.PL_S_LAST && break
                elseif rc == LK.PL_S_EXCEPTION
                    push!(sols, "exception")
                    break
                else
                    break
                end
            end
        catch e
            e isa LK.NotPortedError || rethrow()
            push!(out, "$name notported $(e.step) $(e.what)")
            return out, gd, ld, e
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld, nothing
end

@testset "thread operations as swipl's (tp51-tp102, te01-te30, sc01-sc21, aq01-aq13, dm01-dm02)" begin
    f, names = _to_file()
    kl, _, _, e = _to_kernel(f, names)
    @test e === nothing
    @test kl[1] == "ok"
    @test length(kl) == length(names) + 1
    for (k, id) in zip(kl[2:end], _TO_IDS)
        want = get(_TO_KD, id, _TO_PIN[id])
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

@testset "the KNOWN DIFFERENCE rows: main's class is `console` in swipl from the start, unset in the kernel (kd01-kd02)" begin
    # swipl's answers, from the pin
    @test _TO_PIN["kd01"] == "t_kd01 " * _to_c("t_kd01", _to_a("console"))
    @test _TO_PIN["kd02"] == "t_kd02 " * _to_c("t_kd02", _to_list([_to_a("console")]))
    # the kernel's, pinned exactly: `class(_)` fails (no answer), the findall is empty
    @test _TO_KD["kd01"] == "t_kd01"
    @test _TO_KD["kd02"] == "t_kd02 " * _to_c("t_kd02", "nil")
    for id in keys(_TO_KD)
        @test _TO_KD[id] != _TO_PIN[id]
    end
    @test sort(collect(keys(_TO_KD))) == ["kd01", "kd02"]
end

# REFUSED by name, owner TH1, kernel only (id, goal, `what`): the kernel has no local data of the main thread to reach from an engine,
# and a blob atom is no class. swipl carries the operation out (or, for the join, would hang): no swipl line is pinned.
const _TO_REFUSED = [
    ("rf01", raw"engine_create(x, thread_join(main, _), E), engine_next(E, _)", "thread_join/2: joining the main thread from an engine"),
    ("rf02", raw"engine_create(x, set_thread(main, debug_mode(true)), E), engine_next(E, _)", "set_thread/2: debug_mode(Bool) of the main thread from an engine"),
    ("rf03", raw"engine_create(x, set_thread(main, class(zzz)), E), engine_next(E, _)", "set_thread/2: class(Class) of the main thread from an engine"),
    ("rf04", raw"engine_create(x, true, E), set_thread(main, class(E))", "set_thread/2: class(Class) with a blob atom")
]

@testset "the four named refusals of the thread operations, owner TH1 (rf01-rf04)" begin
    for (id, g, what) in _TO_REFUSED
        f = joinpath(mktempdir(), "thread_ops_refused.pl")
        write(f, "t_$(id)(R) :- $(g), R = ok.\n")        # no catch/3: a NotPortedError is a Julia exception
        kl, _, _, e = _to_kernel(f, ["t_$id"])
        @test e isa LK.NotPortedError
        e isa LK.NotPortedError || continue
        @test e.step == "TH1"
        @test e.what == what
        @test sym_text(e.culprit) in ("thread_join", "set_thread")
        @test kl[end] == "t_$id notported TH1 $what"
    end
    @test length(_TO_REFUSED) == 4
end

@testset "the five thread operations are registered with upstream's flags (pl-thread.c:8849-8904)" begin
    ext = Dict((e.predicate_name, e.arity) => e for e in LK.foreigns)
    for (name, ar) in (
        ("is_thread", 1), ("thread_join", 2), ("thread_detach", 1), ("set_thread", 2),
        ("debug_reset_from_class", 0)
    )
        @test haskey(ext, (name, ar))
        haskey(ext, (name, ar)) || continue
        @test (ext[(name, ar)].flags & LK.PL_FA_NONDETERMINISTIC) == 0
        @test (ext[(name, ar)].flags & LK.PL_FA_TRANSPARENT) == 0
    end
    @test (ext[("thread_detach", 1)].flags & LK.PL_FA_ISO) != 0
    for (name, ar) in (
        ("is_thread", 1), ("thread_join", 2), ("set_thread", 2), ("debug_reset_from_class", 0)
    )
        @test (ext[(name, ar)].flags & LK.PL_FA_ISO) == 0
    end
end

@testset "the THREADOPS rows are not vacuous" begin
    @test _TO_PINNED[1] == "ok"
    @test length(_TO_PINNED) == length(_TO_CASES) + 1
    @test length(unique(_TO_IDS)) == length(_TO_IDS)
    errors = count(l -> occursin("[114,97,105,115,101,100]", l), _TO_PINNED)
    @test errors >= 35                                              # the raising rows
    @test count(l -> !occursin(" ", l) && startswith(l, "t_"), _TO_PINNED) >= 1   # a failing row
    for id in ("tp51", "tp93", "te02", "te17", "sc01", "sc12", "aq01", "aq02", "aq09")
        @test any(
            l -> startswith(l, "t_$id ") && !occursin("[114,97,105,115,101,100]", l),
            _TO_PINNED
        )                                                           # an answer, not an error
    end
end

@testset "the THREADOPS pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_TO_PINNED) == length(_TO_CASES) + 1
    if swipl === nothing
        @info "THREADOPS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _to_file()
        @test _to_swipl_lines(f, names) == _TO_PINNED
    end
end
