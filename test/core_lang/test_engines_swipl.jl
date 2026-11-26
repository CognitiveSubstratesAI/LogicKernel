# ORIGINAL: a test of the ENGINES of pl-thread.c (swipl-devel 10.1.19, 18168e62): engine_create/3,4 (boot/engines.pl over
# `$engine_create/3`), engine_next/2, engine_post/2,3, engine_fetch/1, engine_destroy/1, is_engine/1, engine_self/1, thread_self/1 inside
# an engine, engine_next_reified/2 and, behind the VM yield, engine_yield/1.
#   * NO PIN FILE, NO ORACLE RUN WHEN THIS FILE WAS WRITTEN. Every expected value below is READ FROM THE C (pl-thread.c:4097-4560 at the pin,
#     boot/engines.pl) and written as a Prolog term: a row is a clause `ck_<id>(R)` of ONE program, `Setup, (Goal -> ..), R0 =@= Expected`,
#     whose answer is `ok` or `bad(Got)`. The same program runs in the kernel (consulted by `load_file!`) and, when `swipl` is on PATH,
#     in swipl through the driver of test_event_swipl.jl: the live testset below checks that swipl answers `ok` for every row marked live.
#     A live mismatch means MY READING OF THE C WAS WRONG: the EXPECTED column is corrected, never the kernel.
#     MEASURE ON THE LANE (the first run, once): `swipl -q <driver.pl>` with `:- initialization((fz_run('<program>', [ck_en01, ...]), halt)).`
#     exactly as `_en_swipl_lines` does (write the program with `_en_program(_EN_CASES)`); every line must read `ck_<id> c[..]/1(a[111,107])`.
#     Rows I am least sure of (they read pl-error.c / pl-option.c from memory, not from this file's range): en05d (an unbound Engine is an
#     instantiation_error: PL_error ERR_TYPE on a variable), en53/en54/en56 (the option type errors of PL_scan_options/PL_get_size_ex).
#     `engine_next(main, _)`: upstream finds the alias `main` in threadTable and raises type_error(engine, main); the kernel's database
#     registers the main thread's handle at its creation (`register_main_thread!`), so it answers the same: rows mn1-mn7, MEASURED on the pin.
#   * The tp rows (thread_property/2, pl-thread.c:3404-3512, tprop_list :3355-3367) are read from the C the same way; least sure: tp05 (main's
#     properties), tp22 (debug_mode false), tp23 (main has no class: upstream's info->class of the main thread is NULL, read, not measured),
#     tp10 (findnsols over the enumeration). tp26-tp34 (system_thread_id, size, the property enumerations) are MEASURED on the pin build
#     (2026-11-22); tp23 is kernel-only (the toplevel sets main's class, see the row).
#   * Rows `live = false` are the NAMED DIVERGES (TH1) of the kernel (upstream HANGS on the engine's mutex when an engine is resumed or
#     posted to while it runs): they are never run in swipl.
#   * THE YIELD ROWS (engine_yield/1, the I_YIELD instruction and its resume) need the VM step, which is its own engine-core step. Their testset
#     starts with `@test isdefined(LK, :PL_yielded)`: it FAILS, loudly, in CI as long as the VM yield is absent; it is never skipped and
#     never a vacuous pass. Nothing is removed when the VM step lands: the rows then run.
#   * The ev rows (the thread events of pl-event.c, raised by freePrologThread, pl-thread.c:723-775, when an engine is destroyed or
#     finished) are read from the C the same way, with a PRELUDE (`_EN_EV_PRELUDE`: the log `evlog/1`, the listeners `ev_hook/1`, `ev_hook0/0`,
#     `ev_with/3`). Facts: `thread_exit` (global list) gets the engine's id (alias, else the handle) and runs IN THE ENGINE (`thread_self(S)`
#     is the engine); `this_thread_exit` (the local list of the engine's own local data: a listener made by the MAIN thread is not on it);
#     `thread_start` is raised by start_thread (pl-thread.c:2212) alone: an engine never raises it; after a failing listener the later ones are
#     not called; an exception of a hook is printed to Serror and cleared (engine_destroy still succeeds). Least sure: ev06 (thread_self in the
#     hook), ev09 (swallowed exception), ev13 (term closure).
#   * No row prints an engine handle (a blob: written `<thread>(0x..)`, `<engine>(N,0x..)` upstream): handles only meet inside `=@=`.
#   * The ti rows (the `'$thread_init'/0` goals of pl-thread.c:7003, boot/toplevel.pl:281: `thread_initialization/1` goals run in a NEW
#     ENGINE, in the engine's own local data, when the engine is created, before its goal) are measured on the oracle (pin build, probes of
#     2026-11-22: ti01-ti07 answer as written). NOT ROWS, by name: an init goal that calls thread_self/1, and an init goal that raises:
#     the pin build itself dies (a fatal signal) later in engine_destroy/1 resp. engine_next/2 on those two shapes, so there is no
#     oracle answer to copy and they are not pinned (the kernel's answer for them is unmeasured). `toplevel_thread` (set false by
#     `'$thread_init'`) is not a row: the kernel's flag table is the database's one copy (copy_local_data!), swipl's is per thread.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EN = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ens(x) = lk_sym(_EN, Symbol(x))

_en_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _en_enc(t::_EN, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _en_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _en_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _en_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_en_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _EN_DRIVER = raw"""
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

function _en_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _EN_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# A row: (id, setup, goal, expected, live). The goal sets `R0` on success; when it fails R0 is `failed`; an `error(E, _)` it raises is
# `raised(E)` (the goal is wrapped in catch/3, which undoes its bindings: the engine handles are made in SETUP, outside the catch).
const _EN_CASES = [
    # lifecycle of an engine: its answers, the last answer, the end, the destroy
    (
        "en01", "engine_create(X, member(X,[a,b,c]), E)",
        "engine_next(E,A), engine_next(E,B), engine_next(E,C), ( engine_next(E,_) -> D = yes ; D = no ), R0 = [A,B,C,D]",
        "[a,b,c,no]", true
    ),
    (
        "en02", "engine_create(X, member(X,[a,b,c]), E)",
        raw"engine_next(E,_), engine_next(E,_), engine_next(E,_), \+ engine_next(E,_), engine_destroy(E), engine_next(E,_)",
        "raised(existence_error(engine,E))", true
    ),
    (
        "en03", "engine_create(X, member(X,[a,b,c]), E)",
        "engine_next(E,A), engine_destroy(E), catch(engine_next(E,_), error(Err,_), true), R0 = A-Err",
        "a-existence_error(engine,E)", true
    ),
    (
        "en04", "engine_create(X, member(X,[a,b,c]), E)",
        "( is_engine(E) -> P1 = y ; P1 = n ), engine_destroy(E), ( is_engine(E) -> P2 = y ; P2 = n ), ( is_engine(foo) -> P3 = y ; P3 = n ), ( is_engine(1) -> P4 = y ; P4 = n ), ( is_engine(_) -> P5 = y ; P5 = n ), R0 = [P1,P2,P3,P4,P5]",
        "[y,n,n,n,n]", true
    ),
    # the errors of get_interactor (pl-thread.c get_interactor), on every predicate that takes an engine
    ("en05a", "true", "engine_next(foo,_)", "raised(existence_error(engine,foo))", true),
    ("en05b", "true", "engine_next(1,_)", "raised(type_error(engine,1))", true),
    ("en05c", "true", "engine_next(f(x),_)", "raised(type_error(engine,f(x)))", true),
    ("en05d", "true", "engine_next(_,_)", "raised(instantiation_error)", true),
    ("en05e", "true", "engine_post(foo,x)", "raised(existence_error(engine,foo))", true),
    ("en05f", "true", "engine_post(foo,x,_)", "raised(existence_error(engine,foo))", true),
    ("en05g", "true", "engine_destroy(foo)", "raised(existence_error(engine,foo))", true),
    ("en05h", "true", "engine_destroy(1)", "raised(type_error(engine,1))", true),
    (
        "en05i", "current_output(S)", "engine_next(S,_)", "raised(type_error(engine,S))",
        true
    ),
    (
        "en06", "engine_create(X, member(X,[a,b,c]), E)",
        "engine_destroy(E), engine_destroy(E)",
        "raised(existence_error(engine,E))", true
    ),
    (
        "en07", "engine_create(_, (thread_self(Me), engine_destroy(Me)), E)",
        "engine_next(E,_)", "raised(permission_error(destroy,engine,E))", true
    ),
    # engine_post/2,3 and engine_fetch/1
    (
        "en08", "engine_create(Y, (engine_fetch(X), Y is X*2), E)", "engine_post(E,21,R0)",
        "42", true
    ),
    (
        "en09", "engine_create(Y, (engine_fetch(X), Y is X*2), E)",
        "engine_post(E,21,A), ( engine_next(E,_) -> B = yes ; B = no ), R0 = A-B", "42-no",
        true
    ),
    (
        "en10", "engine_create(Y, (engine_fetch(X), Y = X), E)",
        "engine_post(E,1), engine_post(E,2)", "raised(permission_error(post_to,engine,E))",
        true
    ),
    (
        "en11", "engine_create(Y, (engine_fetch(X), Y = X), E)",
        "engine_post(E,1), engine_next(E,A), R0 = A", "1", true
    ),
    (
        "en12", "true", "engine_fetch(_)", "raised(existence_error(term,delivery,main))",
        true
    ),
    (
        "en13", "engine_create(Y, engine_fetch(Y), E)", "engine_next(E,_)",
        "raised(existence_error(term,delivery,E))", true
    ),
    (
        "en14", "engine_create(X, member(X,[a]), E)", "engine_post(E,hello,R0)", "a", true
    ),
    (
        "en15", "engine_create(X, true, E)",
        "engine_next(E,_), ( engine_post(E,t,_) -> R0 = yes ; R0 = no )", "no", true
    ),
    (
        "en16",
        "engine_create(Y, (engine_fetch(A), catch(engine_fetch(_), error(Er,_), true), Y = A-Er), E)",
        "engine_post(E,1,R0)", "1-existence_error(term,delivery,E)", true
    ),
    (
        "en17", "engine_create(Y, (engine_fetch(X), Y = X), E)",
        "engine_post(E,1), engine_post(E,2,_)",
        "raised(permission_error(post_to,engine,E))",
        true
    ),
    (
        "en18", "engine_create(X, member(X,[a,b,c]), E)",
        "engine_next(E,_), engine_next(E,_), engine_next(E,_), ( is_engine(E) -> P1 = y ; P1 = n ), engine_destroy(E), ( is_engine(E) -> P2 = y ; P2 = n ), R0 = P1-P2",
        "y-n", true
    ),
    (
        "en19", "engine_create(x, true, enalias19)",
        "engine_destroy(enalias19), engine_create(z, true, enalias19), engine_next(enalias19, A), R0 = A",
        "z", true
    ),
    # isolation: bindings do not leak, the answer is a copy, two engines interleave
    (
        "en20", "engine_create(X, X=1, E)", "engine_next(E,A), R0 = X-A", "_-1", true
    ),
    (
        "en21", "engine_create(f(Y,_,Y), true, E)", "engine_next(E,R0)", "f(V,_,V)", true
    ),
    (
        "en22",
        "engine_create(X, member(X,[1,2,3]), E1), engine_create(Y, member(Y,[a,b,c]), E2)",
        "engine_next(E1,A), engine_next(E2,B), engine_next(E1,C), engine_next(E2,D), R0 = [A,B,C,D]",
        "[1,a,2,b]", true
    ),
    (
        "en23", "engine_create(X, member(X,[1,2]), E)",
        "engine_next(E,A), engine_destroy(E), engine_create(X2, member(X2,[3,4]), E2), engine_next(E2,B), R0 = A-B",
        "1-3", true
    ),
    (
        "en24", "engine_create(X, member(X,[a,b,c]), E)",
        raw"engine_next(E,_), engine_next(E,_), engine_next(E,_), \+ engine_next(E,_), ( is_engine(E) -> P = y ; P = n ), catch(engine_next(E,_), error(Err,_), true), R0 = P-Err",
        "y-existence_error(engine,E)", true
    ),
    # exceptions and failure inside the engine
    (
        "en30", "engine_create(X, (X=1 ; throw(oops)), E)",
        "engine_next(E,A), catch(engine_next(E,_), B, true), catch(engine_next(E,_), error(Err,_), true), R0 = A-B-Err",
        "1-oops-existence_error(engine,E)", true
    ),
    (
        "en31", "engine_create(X, (X=1 ; throw(oops)), E)",
        "engine_next_reified(E,A), engine_next_reified(E,B), R0 = A-B",
        "the(1)-throw(oops)",
        true
    ),
    ("en32", "engine_create(X, fail, E)", "engine_next_reified(E,R0)", "no", true),
    (
        "en33", "engine_create(X, fail, E)",
        "( engine_next(E,_) -> A = yes ; A = no ), catch(engine_next(E,_), error(Err,_), true), R0 = A-Err",
        "no-existence_error(engine,E)", true
    ),
    # thread_self/1 and engine_self/1
    (
        "en40", "engine_create(S, engine_self(S), E)",
        "engine_next(E,A), ( A == E -> R0 = same ; R0 = diff )", "same", true
    ),
    ("en41", "true", "thread_self(X), R0 = X", "main", true),
    ("en42", "true", "( engine_self(_) -> R0 = yes ; R0 = no )", "no", true),
    # aliases and options
    (
        "en50", "engine_create(x, true, enalias50)",
        "( is_engine(enalias50) -> P = y ; P = n ), engine_next(enalias50, A), R0 = P-A",
        "y-x", true
    ),
    (
        "en51", "engine_create(x, true, enalias51)", "engine_create(y, true, enalias51)",
        "raised(permission_error(create,engine,enalias51))", true
    ),
    (
        "en52", "engine_create(x, true, E, [alias(enalias52)])",
        "engine_next(enalias52, A), R0 = E-A", "enalias52-x", true
    ),
    (
        "en53", "true", "engine_create(x, true, _, [stack_limit(foo)])",
        "raised(type_error(integer,foo))", true
    ),
    (
        "en54",
        "true",
        "engine_create(x, true, _, foo)",
        "raised(type_error(list,foo))",
        true
    ),
    (
        "en55", "true",
        "engine_create(x, true, E, [stack_limit(inf)]), engine_next(E,A), R0 = A", "x", true
    ),
    (
        "en56", "true", "engine_create(x, true, _, [alias(1)])",
        "raised(type_error(atom,1))", true
    ),
    # thread_property/2 (pl-thread.c:3404-3512, tprop_list :3355-3367): the properties of an engine, of main, the enumerations, the errors.
    # Values read from the C: an engine is `detached` (attrs = {0}: PL_THREAD_NOT_DETACHED unset, :6967), class `user` (:6981), debug true
    # (alloc_thread :1732), `suspended` while not entered (unify_engine_status :2694), `running` inside (activate_interactor :4272).
    (
        "tp01", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, engine(A)), thread_property(E, detached(B)), thread_property(E, debug(C)), thread_property(E, class(D)), thread_property(E, status(S)), R0 = [A,B,C,D,S]",
        "[true,true,true,user,suspended]", true
    ),
    (
        "tp02", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, id(I)), integer(I), I > 1, R0 = yes", "yes", true
    ),
    (
        "tp03", "engine_create(x, member(x,[a]), E, [alias(tpalias03)])",
        "thread_property(E, alias(A)), thread_property(tpalias03, engine(B)), thread_property(E, id(I)), thread_property(tpalias03, id(J)), I == J, R0 = A-B",
        "tpalias03-true", true
    ),
    (
        "tp04", "engine_create(X, member(X,[a,b]), E)",
        "( thread_property(E, alias(_)) -> R0 = y ; R0 = n )", "n", true
    ),
    (
        "tp05", "true",
        "thread_property(main, id(I)), thread_property(main, alias(A)), thread_property(main, status(S)), thread_property(main, engine(Eg)), thread_property(main, detached(D)), thread_property(main, debug(Db)), R0 = [I,A,S,Eg,D,Db]",
        "[1,main,running,false,false,true]", true
    ),
    (
        "tp06", "true",
        "thread_property(1, id(I)), thread_property(1, alias(A)), R0 = I-A", "1-main", true
    ),
    (
        "tp07", "engine_create(a, true, E1), engine_create(b, true, E2)",
        "thread_property(E1, engine(true)), \\+ thread_property(E1, engine(false)), \\+ thread_property(main, engine(true)), findall(T, thread_property(T, engine(true)), L), memberchk(E1, L), memberchk(E2, L), \\+ memberchk(main, L), R0 = yes",
        "yes", true
    ),
    (
        "tp08", "true", "thread_property(T, alias(main)), R0 = T", "main", true
    ),
    (
        "tp09", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, P), functor(P, N, 1), R0 = N", "id", true
    ),
    (
        "tp10", "engine_create(X, member(X,[a,b]), E)",
        "findnsols(4, N, (thread_property(E, P), functor(P, N, _)), L), R0 = L",
        "[id,status,detached,debug]", true
    ),
    (
        "tp11", "true", "thread_property(foo, id(_))",
        "raised(existence_error(thread,foo))", true
    ),
    ("tp12", "true", "thread_property(1.5, id(_))", "raised(type_error(thread,1.5))", true),
    (
        "tp13", "current_output(S)", "thread_property(S, id(_))",
        "raised(type_error(thread,S))", true
    ),
    (
        "tp14", "engine_create(X, member(X,[a,b]), E)", "thread_property(E, foo(_))",
        "raised(domain_error(thread_property,foo(_)))", true
    ),
    (
        "tp15",
        "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, 1)",
        "raised(type_error(thread_property,1))",
        true
    ),
    (
        "tp16",
        "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, id)",
        "raised(domain_error(thread_property,id))",
        true
    ),
    (
        "tp17", "true", "thread_property(_, foo(_))",
        "raised(domain_error(thread_property,foo(_)))", true
    ),
    (
        "tp18", "engine_create(X, member(X,[a,b]), E)",
        "engine_destroy(E), thread_property(E, id(_))",
        "raised(existence_error(thread,E))", true
    ),
    (
        "tp19", "engine_create(X, member(X,[a,b]), E)", "thread_property(E, detached(foo))",
        "raised(type_error(bool,foo))",
        true
    ),
    (
        "tp20",
        "engine_create(S, ( thread_self(Me), thread_property(Me, status(S)) ; true ), E)",
        "engine_next(E, S0), thread_property(E, status(S1)), R0 = S0-S1",
        "running-suspended",
        true
    ),
    (
        "tp21",
        "engine_create(T, ( thread_self(Me), thread_property(Me, thread(T)) ; true ), E)",
        "( thread_property(E, thread(_)) -> P = y ; P = n ), engine_next(E, T0), R0 = P-T0",
        "n-main", true
    ),
    (
        "tp22", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, debug_mode(M)), R0 = M", "false", true
    ),
    # tp23 is KERNEL-ONLY (measured on the pin build, 2026-11-22: swipl answers `console`): the class of the main thread is set by the
    # toplevel (boot/toplevel.pl:575 `set_thread(main, class(console))`), which the kernel's database never ran; upstream's `info->class`
    # of main is NULL until then, as here (a thread record's class is plain data: pl-thread.c:2499, thread_class_property :3340-3353).
    (
        "tp23", "true", "( thread_property(main, class(_)) -> R0 = y ; R0 = n )", "n", false
    ),
    (
        "tp24", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, id(I)), thread_property(I, engine(B)), R0 = B", "true", true
    ),
    (
        "tp25", "true", "thread_property(999999, id(_))",
        "raised(existence_error(thread,999999))", true
    ),
    # system_thread_id/1 and size/1 (pl-thread.c:3305-3338, system_thread_id :2041, sizeof_thread :3156), measured on the pin build 2026-11-22:
    # main has an OS thread id, an engine only while it is entered (`has_tid`, the same OS thread as main's), a size while it is running.
    (
        "tp26", "true",
        "thread_property(main, system_thread_id(I)), integer(I), I > 0, R0 = ok", "ok", true
    ),
    (
        "tp27",
        "engine_create(X, (thread_self(S), thread_property(S, system_thread_id(I)), X = I), E)",
        "engine_next(E, A), thread_property(main, system_thread_id(M)), ( A == M -> R0 = same ; R0 = diff )",
        "same", true
    ),
    (
        "tp28", "engine_create(X, member(X,[a,b]), E)",
        "( thread_property(E, system_thread_id(_)) -> R0 = y ; R0 = n )", "n", true
    ),
    (
        "tp29", "true", "thread_property(main, size(S)), integer(S), S > 0, R0 = ok", "ok",
        true
    ),
    (
        "tp30", "engine_create(X, member(X,[a,b]), E)",
        "thread_property(E, size(S)), integer(S), S > 0, R0 = ok", "ok", true
    ),
    (
        "tp31",
        "engine_create(X, ( thread_self(Me), thread_property(Me, size(S)), integer(S), S > 0, X = ok ), E)",
        "engine_next(E, R0)", "ok", true
    ),
    (
        "tp32", "true",
        "findall(N, ( thread_property(main, P), functor(P, N, _), N \\== class ), R0)",
        "[id,alias,status,detached,debug,debug_mode,engine,system_thread_id,size]", true
    ),
    (
        "tp33", "engine_create(X, member(X,[a,b]), E)",
        "findall(N, ( thread_property(E, P), functor(P, N, _) ), R0)",
        "[id,status,detached,debug,debug_mode,engine,size,class]", true
    ),
    (
        "tp34",
        "engine_create(X, ( thread_self(S), findall(N, ( thread_property(S, P), functor(P, N, _) ), X) ), E)",
        "engine_next(E, R0)",
        "[id,status,detached,debug,debug_mode,engine,thread,system_thread_id,size,class]",
        true
    ),
    # the `main` entry of the thread table (pl-init.c:1606 aliasThread(PL_thread_self(), ATOM_thread, ATOM_main); TH1 piece b), measured on the
    # pin build 2026-11-22: main's handle is in threadTable but is no interactor (its blob is no text atom): every engine predicate raises
    # type_error(engine, main); the name is taken, so an engine cannot be called main.
    (
        "mn1", "true", "engine_next(main,_)", "raised(type_error(engine,main))", true
    ),
    (
        "mn2", "true", "engine_destroy(main)", "raised(type_error(engine,main))", true
    ),
    (
        "mn3", "true", "engine_post(main,x)", "raised(type_error(engine,main))", true
    ),
    (
        "mn4", "true", "engine_post(main,x,_)", "raised(type_error(engine,main))", true
    ),
    (
        "mn5", "true", "( is_engine(main) -> R0 = y ; R0 = n )", "n", true
    ),
    (
        "mn6", "true", "engine_create(x,true,_,[alias(main)])",
        "raised(permission_error(create,engine,main))", true
    ),
    (
        "mn7", "true",
        "catch(engine_create(x,true,_,[alias(main)]), _, true), thread_property(T, alias(main)), R0 = T",
        "main", true
    ),
    # the named DIVERGES (TH1): upstream waits for the mutex of an engine that is running, on one thread: a hang. Kernel only.
    (
        "dv1", "engine_create(X, (thread_self(Me), engine_next(Me, X)), E)",
        "engine_next(E,_)", "raised(permission_error(resume,engine,E))", false
    ),
    (
        "dv2", "engine_create(X, (thread_self(Me), engine_post(Me, 1)), E)",
        "engine_next(E,_)", "raised(permission_error(post_to,engine,E))", false
    ),
    (
        "dv3",
        "engine_create(_, (thread_self(Me), engine_create(_, engine_destroy(Me), Y), engine_next(Y,_)), E)",
        "engine_next(E,_)", "raised(permission_error(destroy,engine,E))", false
    )
]

# the thread events (Q1): the prelude's log and listeners; every row's listeners are removed by `ev_with/3` (also on an error)
const _EN_EV_PRELUDE = raw"""
:- dynamic evlog/1, ev_keep/1.
ev_hook(T) :- assertz(evlog(T)).
ev_hook0 :- assertz(evlog(this)).
ev_hook_self(T) :- thread_self(S), assertz(evlog(T-S)).
ev_hook_fail(_) :- fail.
ev_hook_throw(_) :- throw(oops).
ev_tag(Tag, T) :- assertz(evlog(Tag-T)).
ev_on([], _).
ev_on([H-O|T], Ev) :- prolog_listen(Ev, H, O), ev_on(T, Ev).
ev_off([], _).
ev_off([H-_|T], Ev) :- prolog_unlisten(Ev, H), ev_off(T, Ev).
ev_with(Ev, Specs, Goal) :-
    retractall(evlog(_)),
    setup_call_cleanup(ev_on(Specs, Ev), once(Goal), ev_off(Specs, Ev)).
"""

# rows: (id, setup, goal, expected, live); `L` is the log after the goal
const _EN_EV_CASES = [
    (
        "ev01", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook-[]], ( engine_next(E,_), engine_destroy(E) )), findall(T, evlog(T), L), ( L = [E1], E1 == E -> R0 = same ; R0 = L )",
        "same", true
    ),
    (
        "ev02", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook-[]], engine_next(E,_)), findall(T, evlog(T), L), R0 = L",
        "[]", true
    ),
    (
        "ev03", "engine_create(X, X = a, E)",
        "ev_with(thread_exit, [ev_hook-[]], engine_next(E,_)), findall(T, evlog(T), L), ( L = [E1], E1 == E -> R0 = same ; R0 = L )",
        "same", true
    ),
    (
        "ev04",
        "engine_create(X, member(X,[a,b]), E1), engine_create(Y, member(Y,[a,b]), E2)",
        "ev_with(thread_exit, [ev_hook-[]], ( engine_destroy(E2), engine_destroy(E1) )), findall(T, evlog(T), L), ( L = [A,B], A == E2, B == E1 -> R0 = same ; R0 = L )",
        "same", true
    ),
    (
        "ev05", "engine_create(X, member(X,[a,b]), E, [alias(ev_al)])",
        "ev_with(thread_exit, [ev_hook-[]], engine_destroy(E)), findall(T, evlog(T), L), R0 = L",
        "[ev_al]", true
    ),
    (
        "ev06", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook_self-[]], engine_destroy(E)), findall(T, evlog(T), L), ( L = [A-B], A == E, B == E -> R0 = same ; R0 = L )",
        "same", true
    ),
    (
        "ev07", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(this_thread_exit, [ev_hook0-[]], engine_destroy(E)), findall(T, evlog(T), L), R0 = L",
        "[]", true
    ),
    (
        "ev08",
        "retractall(evlog(_)), engine_create(X, ( prolog_listen(this_thread_exit, ev_hook0), member(X,[a,b]) ), E)",
        "engine_next(E,_), engine_destroy(E), findall(T, evlog(T), L), R0 = L",
        "[this]", true
    ),
    (
        "ev09", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook_throw-[]], engine_destroy(E)), R0 = done",
        "done", true
    ),
    (
        "ev10", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook-[], ev_hook_fail-[as(first)]], engine_destroy(E)), findall(T, evlog(T), L), R0 = L",
        "[]", true
    ),
    (
        "ev11", "true",
        "ev_with(thread_start, [ev_hook-[]], ( engine_create(X, member(X,[a,b]), E), engine_next(E,_), engine_destroy(E) )), findall(T, evlog(T), L), R0 = L",
        "[]", true
    ),
    (
        "ev12", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_tag(x)-[]], engine_destroy(E)), findall(T, evlog(T), L), ( L = [x-E1], E1 == E -> R0 = same ; R0 = L )",
        "same", true
    ),
    (
        "ev13", "engine_create(X, member(X,[a,b]), E)",
        "ev_with(thread_exit, [ev_hook-[], ev_tag(y)-[as(last)]], engine_destroy(E)), findall(T, evlog(T), L), ( L = [A, y-B], A == E, B == E -> R0 = same ; R0 = L )",
        "same", true
    )
]

# the thread initialisation goals (`$thread_init`): `ti_with(Goals, Body)` registers the goals (thread_initialization/1 runs each in the
# caller too and fails for a failing goal: both are dropped), clears the log, runs `Body` once and removes every registered goal
const _EN_TI_PRELUDE = raw"""
:- dynamic ti_log/1.
ti_reg([]).
ti_reg([G|T]) :- ( thread_initialization(G) -> true ; true ), ti_reg(T).
ti_with(Goals, Body) :-
    setup_call_cleanup(ti_reg(Goals), ( retractall(ti_log(_)), once(Body) ), retractall('$toplevel':'$at_thread_initialization'(_))).
"""

# rows: (id, setup, goal, expected, live); `R0` is the answer
const _EN_TI_CASES = [
    (
        "ti01", "true",
        "ti_with([assertz(ti_log(a))], ( engine_create(x, true, E), findall(L, ti_log(L), R0), engine_destroy(E) ))",
        "[a]", true
    ),
    (
        "ti02", "true",
        "ti_with([assertz(ti_log(a)), fail, assertz(ti_log(b))], ( engine_create(x, true, E), findall(L, ti_log(L), R0), engine_destroy(E) ))",
        "[a,b]", true
    ),
    (
        "ti03", "true",
        "ti_with([assertz(ti_log(a))], ( engine_create(x, assertz(ti_log(goal)), E), findall(L, ti_log(L), R1), engine_next(E,_), findall(L, ti_log(L), R2), engine_destroy(E), R0 = R1-R2 ))",
        "[a]-[a,goal]", true
    ),
    (
        "ti04", "true",
        "ti_with([assertz(ti_log(a))], ( engine_create(x, true, E1), engine_create(x, true, E2), findall(L, ti_log(L), R0), engine_destroy(E1), engine_destroy(E2) ))",
        "[a,a]", true
    ),
    (
        "ti05", "true",
        "ti_with([assertz(ti_log(a))], ( engine_create(X, member(X,[1,2]), E), engine_next(E,_), engine_next(E,_), findall(L, ti_log(L), R0), engine_destroy(E) ))",
        "[a]", true
    ),
    (
        "ti06", "true",
        "ti_with([], ( engine_create(x, true, E), findall(L, ti_log(L), R0), engine_destroy(E) ))",
        "[]", true
    ),
    (
        "ti07", "true",
        "ti_with([nb_setval(ti_k, 7)], ( nb_delete(ti_k), engine_create(V, nb_getval(ti_k, V), E), engine_next(E,A), ( nb_current(ti_k, _) -> M = y ; M = n ), engine_destroy(E), R0 = A-M ))",
        "7-n", true
    )
]

# rows that need the VM yield (I_YIELD and its resume): their own testset, which fails loudly when the yield is absent
const _EN_YIELD_CASES = [
    (
        "yl1", "engine_create(_, (engine_yield(1), engine_yield(2), fail), E)",
        "engine_next(E,A), engine_next(E,B), ( engine_next(E,_) -> C = y ; C = n ), R0 = [A,B,C]",
        "[1,2,n]", true
    ),
    (
        "yl2", "engine_create(_, (engine_yield(a), engine_fetch(F), engine_yield(F)), E)",
        "engine_next(E,A), engine_post(E,foo,B), R0 = A-B", "a-foo", true
    )
]

"The program of `cases`: the `prelude`, then one clause `ck_<id>(R)` per row (R is `ok`, or `bad(Got)`)."
function _en_program(cases; prelude::String="")::String
    return prelude * join(
        [
        "ck_$(c[1])(R) :- $(c[2]), ( catch(($(c[3])), error(SsuE, _), R0 = raised(SsuE)) -> true ; R0 = failed ), " *
        "( R0 =@= ($(c[4])) -> R = ok ; R = bad(R0) ).\n" for c in cases
    ]
    )
end

"The line a passing row gives: the driver's `enc` of `ck_<id>(ok)`."
_en_ok_line(id) = "ck_$id c$(_en_codes("ck_$id"))/1(a[111,107])"

function _en_file(cases; prelude::String="")::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "engines.pl")
    write(f, _en_program(cases; prelude))
    return f, ["ck_$(c[1])" for c in cases]
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _en_load(path::String)
    gd = LK.PL_global_data{_EN}()
    ld = LK.PL_local_data{_EN}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _en_enc(ball::_EN))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _en_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_ens(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_EN, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _en_enc(mk_expr(_EN, _EN[_ens(pred), lk_answers(ld, (a:a)...)...])))
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
    return pred * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`."
function _en_kernel(path::String, names::Vector{String})
    gd, ld, st = _en_load(path)
    out = [st]
    for name in names
        push!(out, _en_ask(gd, ld, name))
    end
    return out, gd, ld
end

function _en_check(cases; prelude::String="")
    f, names = _en_file(cases; prelude)
    kl, gd, ld = _en_kernel(f, names)
    @test kl[1] == "ok"
    @test length(kl) == length(cases) + 1
    for (c, line) in zip(cases, kl[2:end])
        want = _en_ok_line(c[1])
        line == want ||
            println(stderr, "  row $(c[1]): ours  ", line, "\n          wanted ", want)
        @test line == want
    end
    return gd, ld
end

@testset "engines as pl-thread.c's (C-derived rows, kernel)" begin
    _en_check(_EN_CASES)
end

@testset "the thread events (C-derived rows, kernel)" begin
    _en_check(_EN_EV_CASES; prelude=_EN_EV_PRELUDE)
end

@testset "the thread initialisation goals of a new engine (C-derived rows, kernel)" begin
    _en_check(_EN_TI_CASES; prelude=_EN_TI_PRELUDE)
end

@testset "the thread events: the table and the raise paths (white-box)" begin
    # the event table of the O_ENGINES build (pl-event.c:80-95): twelve rows, in upstream's order, the id the row's index
    @test length(LK.PL_events) == 12
    @test [et.name for et in LK.PL_events] == [
        Symbol("abo", "rt"), :erase, :erase, :break, :break, :break, :break,
        :frame_finished, :untable,
        :thread_start, :thread_exit, :this_thread_exit
    ]
    @test all(i -> LK.PL_events[i].id == i - 1, 1:12)
    @test [et.argc for et in LK.PL_events][10:12] == [1, 1, 0]
    @test [et.local_ for et in LK.PL_events] == vcat(fill(false, 11), [true])
    # thread_start has no raise site for an engine: raise it by hand with an engine's record (the value `unify_thread_id` puts)
    prelude =
        _EN_EV_PRELUDE * """
ck_evs1(ok) :- retractall(evlog(_)), engine_create(X, member(X,[a,b]), E), assertz(ev_keep(E)), prolog_listen(thread_start, ev_hook).
ck_evs2(R) :- ev_keep(E), findall(T, evlog(T), L), ( L = [T1], T1 == E -> R = ok ; R = bad(L) ).
"""
    f = joinpath(mktempdir(), "evs.pl")
    write(f, prelude)
    gd, ld, st = _en_load(f)
    @test st == "ok"
    @test _en_ask(gd, ld, "ck_evs1") == _en_ok_line("evs1")
    i = findfirst(!isnothing, gd.thread.infos)
    @test i !== nothing
    info = gd.thread.infos[i]
    @test LK.callEventHook(gd, ld, LK.PLEV_THREAD_START, info)
    @test _en_ask(gd, ld, "ck_evs2") == _en_ok_line("evs2")
end

@testset "the thread events: a hook that raises is reported on the engine's messages and cleared (white-box)" begin
    prelude =
        _EN_EV_PRELUDE * """
ck_evs3a(ok) :- engine_create(X, member(X,[a,b]), E), assertz(ev_keep(E)), prolog_listen(thread_exit, ev_hook_throw).
ck_evs3b(ok) :- ev_keep(E), engine_destroy(E).
"""
    f = joinpath(mktempdir(), "evs3.pl")
    write(f, prelude)
    gd, ld, st = _en_load(f)
    @test st == "ok"
    @test _en_ask(gd, ld, "ck_evs3a") == _en_ok_line("evs3a")
    i = findfirst(!isnothing, gd.thread.infos)
    @test i !== nothing
    eld = gd.thread.infos[i].thread_data
    @test _en_ask(gd, ld, "ck_evs3b") == _en_ok_line("evs3b")        # engine_destroy/1 succeeds
    @test gd.thread.infos[i] === nothing
    @test any(
        m ->
            m[1] === :error && kind(m[2]) === SYM &&
            occursin("thread_finished", sym_text(m[2])),
        eld.messages
    )
    @test eld.exception_term == 0                                      # the exception was cleared
end

# PL_thread_at_exit and the C functions of an event list (pl-thread.c:3598-3620, pl-event.c register_event_function/call_event_list):
# C-reachable only, so there is no swipl oracle: the expected values are READ from the C (blind: correct on the lane, never the kernel).
const _EN_AE_PRELUDE =
    _EN_EV_PRELUDE * raw"""
ck_ae_new(ok) :- engine_create(X, member(X,[a,b]), E), assertz(ev_keep(E)).
ck_ae_destroy(ok) :- retract(ev_keep(E)), engine_destroy(E).
ck_ae_listen(ok) :- prolog_listen(thread_exit, ev_hook, []).
ck_ae_listen_fail(ok) :- prolog_listen(thread_exit, ev_hook_fail, []).
ck_ae_log(N) :- findall(T, evlog(T), L), length(L, N).
ck_ae_new_alias(ok) :- engine_create(X, member(X,[a,b]), E, [alias(foo)]), assertz(ev_keep(E)).
"""

function _en_ae_load()
    f = joinpath(mktempdir(), "ae.pl")
    write(f, _EN_AE_PRELUDE)
    gd, ld, st = _en_load(f)
    @test st == "ok"
    return gd, ld
end
_en_ae_nlog(n) = "ck_ae_log c$(_en_codes("ck_ae_log"))/1(i$n)"
_en_ae_place(l) = l.thread_info === nothing ? :main : :engine
_en_ae_eld(gd) = gd.thread.infos[findfirst(!isnothing, gd.thread.infos)].thread_data
# a void function that logs `(tag, closure, where it ran)`
_en_ae_fn(log, tag) = (g, l, c) -> (push!(log, (tag, c, _en_ae_place(l))); nothing)

@testset "PL_thread_at_exit and the C functions of an event list (white-box, read from the C)" begin
    # S1: a global function runs for every engine that is destroyed, in the engine, the last registered first (head of the list)
    gd, ld = _en_ae_load()
    log = Tuple{Symbol, Symbol, Symbol}[]
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :f1), :c1, true)
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :f2), :c2, true)
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    @test isempty(log)                                                  # nothing at creation
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test log == [(:f2, :c2, :engine), (:f1, :c1, :engine)]
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test length(log) == 4                                              # a second engine: the functions run again
    @test log[3:4] == [(:f2, :c2, :engine), (:f1, :c1, :engine)]

    # S2: a local function belongs to the thread that registered it: main's never runs for an engine's exit, an engine's runs once
    gd, ld = _en_ae_load()
    log = Tuple{Symbol, Symbol, Symbol}[]
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :m), :cm, false)
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    eld = _en_ae_eld(gd)
    @test LK.PL_thread_at_exit(gd, eld, _en_ae_fn(log, :e), :ce, false)
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test log == [(:e, :ce, :engine)]
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :m2), :cm2, false)
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test log == [(:e, :ce, :engine)]                                   # still only the engine's own

    # S3: a function is not gated by an earlier listener's failure (the list is [fail, function])
    gd, ld = _en_ae_load()
    log = Tuple{Symbol, Symbol, Symbol}[]
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :g), :cg, true)
    @test _en_ask(gd, ld, "ck_ae_listen_fail") == _en_ok_line("ae_listen_fail")
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test log == [(:g, :cg, :engine)]

    # S4: a void function that raises makes the rest of the list not run, and the exception is reported on the engine and cleared
    gd, ld = _en_ae_load()
    log = Tuple{Symbol, Symbol, Symbol}[]
    @test LK.PL_thread_at_exit(gd, ld, _en_ae_fn(log, :after), :cafter, true)
    raiser = (g, l, c) -> begin
        push!(log, (:raiser, c, _en_ae_place(l)))
        t = LK.PL_new_term_ref(l)
        LK.PL_put_atom(l, t, _ens(:oops))
        LK.PL_raise_exception(l, t)
        return nothing
    end
    @test LK.PL_thread_at_exit(gd, ld, raiser, :craise, true)
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    eld = _en_ae_eld(gd)
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test log == [(:raiser, :craise, :engine)]
    @test any(
        m ->
            m[1] === :error && kind(m[2]) === SYM &&
            occursin("thread_finished", sym_text(m[2])),
        eld.messages
    )
    @test eld.exception_term == 0

    # S5: a BOOL function (registered directly: C has no registrar either) returns the listener's verdict, and the Prolog listener
    # after it runs only on true
    for want in (true, false)
        gd, ld = _en_ae_load()
        log = Tuple{Symbol, Bool, Symbol}[]
        bf = (g, l, c, t) -> (push!(log, (c, t != 0, _en_ae_place(l))); want)
        @test _en_ask(gd, ld, "ck_ae_listen") == _en_ok_line("ae_listen")
        loc = LK.event_location{_EN}(LK.PLEV_THREAD_EXIT, nothing)
        @test LK.register_event_function(
            gd, ld, loc, nothing, false, bf, :b, 1, LK.EV_CALLBACK_BOOL
        )
        @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
        @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
        @test log == [(:b, true, :engine)]
        @test _en_ask(gd, ld, "ck_ae_log") == _en_ae_nlog(want ? 1 : 0)
    end
end

# the C API on thread identifiers (pl-thread.c PL_thread_self, PL_unify_thread_id, PL_get_thread_id_ex, PL_get_thread_alias): C-reachable only,
# the expected values are read from the C (blind: correct on the lane, never the kernel)
@testset "the thread identifier API of the C interface (white-box, read from the C)" begin
    gd, ld = _en_ae_load()
    selfs = Int[]
    @test LK.PL_thread_at_exit(
        gd, ld, (g, l, c) -> (push!(selfs, LK.PL_thread_self(l)); nothing), :s, true
    )
    @test LK.PL_thread_self(ld) == 1                                    # the main thread
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    info = gd.thread.infos[2]
    @test LK.PL_thread_self(info.thread_data) == 2                      # inside the engine
    # PL_unify_thread_id: an engine without an alias is its handle, main is `main`, a non-thread is -1
    t = LK.PL_new_term_ref(ld)
    @test LK.PL_unify_thread_id(gd, ld, t, 2) == 1
    a = LK.PL_get_atom(ld, t)
    @test a !== nothing && sym_key(a) == sym_key(info.symbol)
    t1 = LK.PL_new_term_ref(ld)
    @test LK.PL_unify_thread_id(gd, ld, t1, 1) == 1
    @test sym_key(LK.PL_get_atom(ld, t1)) == sym_key(_ens(:main))
    @test LK.PL_unify_thread_id(gd, ld, LK.PL_new_term_ref(ld), 0) == -1
    @test LK.PL_unify_thread_id(gd, ld, LK.PL_new_term_ref(ld), 3) == -1
    t2 = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t2, _ens(:other))
    @test LK.PL_unify_thread_id(gd, ld, t2, 2) == 0                     # a failed unification is 0, not -1
    # PL_get_thread_id_ex: handle, integer, `main`, and the errors
    @test LK.PL_get_thread_id_ex(gd, ld, t) == 2
    t3 = LK.PL_new_term_ref(ld)
    LK.PL_put_intptr(ld, t3, 2)
    @test LK.PL_get_thread_id_ex(gd, ld, t3) == 2
    @test LK.PL_get_thread_id_ex(gd, ld, t1) == 1
    @test LK.PL_exception(ld, 0) == 0
    t4 = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t4, _ens(:nosuch))
    @test LK.PL_get_thread_id_ex(gd, ld, t4) === nothing
    @test LK.PL_exception(ld, 0) != 0                                   # existence_error(thread, nosuch)
    LK.PL_clear_exception(ld)
    t5 = LK.PL_new_term_ref(ld)
    LK.PL_put_float(ld, t5, 2.5)
    @test LK.PL_get_thread_id_ex(gd, ld, t5) === nothing
    @test LK.PL_exception(ld, 0) != 0                                   # type_error(thread, 2.5)
    LK.PL_clear_exception(ld)
    # PL_get_thread_alias: none for an engine without one, `main` for 0 on the main thread and for 1, none outside the table
    @test LK.PL_get_thread_alias(gd, ld, 2) === nothing
    @test sym_key(LK.PL_get_thread_alias(gd, ld, 0)) == sym_key(_ens(:main))
    @test sym_key(LK.PL_get_thread_alias(gd, ld, 1)) == sym_key(_ens(:main))
    @test LK.PL_get_thread_alias(gd, ld, 7) === nothing
    @test LK.PL_get_thread_alias(gd, ld, -1) === nothing
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test selfs == [2]
    @test LK.PL_unify_thread_id(gd, ld, LK.PL_new_term_ref(ld), 2) == -1    # a destroyed engine is no thread
    @test LK.PL_get_thread_alias(gd, ld, 2) === nothing
    # an engine with an alias: its alias is its identifier
    @test _en_ask(gd, ld, "ck_ae_new_alias") == _en_ok_line("ae_new_alias")
    @test sym_key(LK.PL_get_thread_alias(gd, ld, 3)) == sym_key(_ens(:foo))
    t6 = LK.PL_new_term_ref(ld)
    @test LK.PL_unify_thread_id(gd, ld, t6, 3) == 1
    @test sym_key(LK.PL_get_atom(ld, t6)) == sym_key(_ens(:foo))
    t7 = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t7, _ens(:foo))
    @test LK.PL_get_thread_id_ex(gd, ld, t7) == 3
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
    @test selfs == [2, 3]
end

# thread_property's `status` of a thread record that ended (pl-thread.c:2698-2765, unify_thread_status): no engine reaches these statuses (a
# finished engine's slot is dropped), so the rows set the record's `status` and `return_value` by hand on a live engine's record.
const _EN_ST_PRELUDE =
    _EN_AE_PRELUDE * raw"""
ck_st_exited(ok) :- ev_keep(E), thread_property(E, status(exited(foo))).
ck_st_exited_none(ok) :- ev_keep(E), thread_property(E, status(exited(T))), var(T).
ck_st_exception(ok) :- ev_keep(E), thread_property(E, status(exception(foo))).
ck_st_nomem(ok) :- ev_keep(E), thread_property(E, status(exception(error(resource_error(memory), V)))), var(V).
ck_st_true(ok) :- ev_keep(E), thread_property(E, status(true)).
ck_st_false(ok) :- ev_keep(E), thread_property(E, status(false)).
ck_st_wrong(ok) :- ev_keep(E), \+ thread_property(E, status(true)), \+ thread_property(E, status(exception(_))), \+ thread_property(E, status(running)).
ck_st_size(ok) :- ev_keep(E), \+ thread_property(E, size(_)).
ck_st_listed(ok) :- ev_keep(E), thread_property(T, status(true)), T == E.
"""

@testset "thread_property: the status of a thread that ended, size and system_thread_id (white-box, read from the C)" begin
    f = joinpath(mktempdir(), "st.pl")
    write(f, _EN_ST_PRELUDE)
    gd, ld, st = _en_load(f)
    @test st == "ok"
    @test _en_ask(gd, ld, "ck_ae_new") == _en_ok_line("ae_new")
    info = gd.thread.infos[2]
    ok(n) = _en_ask(gd, ld, "ck_$n") == _en_ok_line(n)
    @test info.return_value === nothing                                 # an engine ends with no result
    r = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, r, _ens(:foo))
    # exited(T): T is the recorded result, an unbound variable when there is none (`rc` stays true)
    info.status = LK.PL_THREAD_EXITED
    @test ok("st_exited_none")
    info.return_value = LK.PL_record(ld, r)
    @test ok("st_exited")
    @test ok("st_wrong")                                                # `exited` answers no other status
    info.status = LK.PL_THREAD_EXCEPTION
    @test ok("st_exception")
    info.status = LK.PL_THREAD_NOMEM                                    # exception(error(resource_error(memory), _)), no record read
    @test ok("st_nomem")
    info.status = LK.PL_THREAD_SUCCEEDED
    @test ok("st_true")
    @test ok("st_listed")                                               # the enumeration reaches a record with a status past RUNNING
    info.status = LK.PL_THREAD_FAILED
    @test ok("st_false")
    @test ok("st_size")                                                 # `size` is 0 (a failure) unless the thread is RUNNING
    # the size of a running engine counts its record, its local data and its stacks; main's counts its own
    info.status = LK.PL_THREAD_RUNNING
    eld = info.thread_data
    sz = LK.sizeof_thread(ld, info)
    @test sz >=
        sizeof(LK.PL_thread_info{_EN}) + sizeof(LK.PL_local_data{_EN}) +
          8 * length(eld.gstack) + 8 * eld.lMax + 8 * length(eld.trail)
    @test LK.sizeof_thread(ld, nothing) >=
        sizeof(LK.PL_thread_info{_EN}) + 8 * length(ld.gstack)
    @test LK.sizeof_thread(eld, nothing) == sizeof(LK.PL_thread_info{_EN})    # main's local data is not the engine's: only the record
    info.status = LK.PL_THREAD_EXITED
    @test LK.sizeof_thread(ld, info) == 0
    info.status = LK.PL_THREAD_RUNNING
    # system_thread_id: the calling thread's id on Linux; an engine only while it is entered (`has_tid`)
    if Sys.islinux()
        @test LK.system_thread_id() == Int(ccall(:gettid, Cint, ()))
        @test LK.system_thread_id() > 0
    else
        @test LK.system_thread_id() == -1
    end
    @test _en_ask(gd, ld, "ck_ae_destroy") == _en_ok_line("ae_destroy")
end

@testset "engine_yield/1 rows (need the VM yield: FAILS until the VM step lands)" begin
    # a loud failure, never a skip: the yield is the VM's (I_YIELD, pl-vmi.c:2410-2448; resume, pl-wam.c:3870-3910; PL_yielded, :3331)
    @test isdefined(LK, :PL_yielded)
    if isdefined(LK, :PL_yielded)
        _en_check(_EN_YIELD_CASES)
    end
end

@testset "engines: white-box (handles, counters, the main thread has no record)" begin
    f, names = _en_file(filter(c -> c[1] == "en01", _EN_CASES))
    kl, gd, ld = _en_kernel(f, names)
    @test kl == ["ok", _en_ok_line("en01")]
    @test ld.thread_info === nothing                    # the main thread: no record
    @test gd.thread.engines_created == 1
    @test gd.thread.engines_finished == 1               # the last answer finished it: a later destroy does not count twice
    @test length(gd.thread.handles) == 2                # the main thread's handle (1) and the engine's (2)
    @test all(h -> h.info === nothing && !h.running, gd.thread.handles)
end

@testset "engines: white-box (the main thread's handle, the first of the database; TH1 piece b)" begin
    f, names = _en_file(filter(c -> c[1] == "mn1", _EN_CASES))
    kl, gd, ld = _en_kernel(f, names)
    @test kl == ["ok", _en_ok_line("mn1")]
    @test length(gd.thread.handles) == 1                # no engine was made: the handle of the main thread alone
    h = gd.thread.handles[1]
    @test h.info === nothing && h.engine_id == 1 && h.serial == 1 && h.flags == 0 &&
        !h.running
    @test h.alias !== nothing && sym_key(h.alias) == sym_key(_ens(:main))
    @test h.symbol !== nothing && is_blob(h.symbol)
    @test gd.thread.thread_table[sym_key(_ens(:main))] == 1
    @test gd.thread.engines_created == 0
    # get_thread by the blob of the handle, by the text alias and by the integer 1: the main thread
    t = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t, h.symbol)
    @test LK.PL_get_thread_id_ex(gd, ld, t) == 1
    t2 = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t2, _ens(:main))
    @test LK.PL_get_thread_id_ex(gd, ld, t2) == 1
    @test LK.PL_exception(ld, 0) == 0
    # registering again changes nothing; a made-up database (no copy) and a copy each have the handle, not the template's object
    LK.register_main_thread!(gd)
    @test length(gd.thread.handles) == 1 && gd.thread.handles[1] === h
    g2 = LK.PL_global_data{_EN}()
    @test length(g2.thread.handles) == 1 && g2.thread.handles[1] !== h
    @test g2.thread.handles[1].engine_id == 1 &&
        g2.thread.thread_table[sym_key(_ens(:main))] == 1
    g3 = LK.setupProlog(_EN)
    @test length(g3.thread.handles) == 1 &&
        g3.thread.thread_table[sym_key(_ens(:main))] == 1
    @test g3.thread.handles[1].engine_id == 1 && g3.thread.handles[1].info === nothing
end

@testset "engines: white-box (an engine that fails or raises is finished)" begin
    for id in ("en32", "en30")
        f, names = _en_file(filter(c -> c[1] == id, _EN_CASES))
        kl, gd, ld = _en_kernel(f, names)
        @test kl == ["ok", _en_ok_line(id)]
        @test gd.thread.engines_created == 1
        @test gd.thread.engines_finished == 1
        @test all(h -> h.info === nothing && h.interactor_query == 0, gd.thread.handles)
    end
end

@testset "the engine rows are not vacuous" begin
    allc = vcat(_EN_CASES, _EN_YIELD_CASES, _EN_EV_CASES, _EN_TI_CASES)
    ids = [c[1] for c in allc]
    @test length(unique(ids)) == length(ids)
    for c in allc
        @test !isempty(c[3]) && !isempty(c[4]) && c[4] != "_"    # a row whose expectation cannot fail
    end
    for fam in ("en0", "en1", "en2", "en3", "en4", "en5", "dv", "yl", "tp", "ev", "ti")
        @test any(startswith(id, fam) for id in ids)
    end
    @test count(c -> !c[5], _EN_CASES) == 4             # the named divergences (dv1-dv3) and tp23 (the toplevel's class of main) are the only kernel-only rows
    @test _en_ok_line("en01") == "ck_en01 c[99,107,95,101,110,48,49]/1(a[111,107])"
end

@testset "the rows are swipl's (live, when swipl is on PATH)" begin
    allc = vcat(_EN_CASES, _EN_YIELD_CASES, _EN_EV_CASES, _EN_TI_CASES)
    live = filter(c -> c[5], allc)
    f, names = _en_file(live; prelude=_EN_EV_PRELUDE * _EN_TI_PRELUDE)
    # the inert-testset guard (as in test_engine_yield_swipl.jl): what swipl is asked, asserted with or without swipl: every
    # row but the four kernel-only ones, and the program it consults has exactly one clause for each of them and none for those
    kernel_only = ("dv1", "dv2", "dv3", "tp23")
    @test names == ["ck_$(c[1])" for c in allc if !(c[1] in kernel_only)]
    program = split(read(f, String), '\n')
    @test all(n -> count(startswith("$n(R) :- "), program) == 1, names)
    @test !any(l -> any(id -> startswith(l, "ck_$id("), kernel_only), program)
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ENGINES LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        lines = _en_swipl_lines(f, names)
        @test length(lines) == length(live) + 1
        @test lines[1] == "ok"
        for (c, line) in zip(live, lines[2:end])
            line == _en_ok_line(c[1]) || println(stderr, "  swipl row $(c[1]): ", line)
            @test line == _en_ok_line(c[1])
        end
    end
end
