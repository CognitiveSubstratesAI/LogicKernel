# ORIGINAL: a differential of setThreadLocalDefinition (pl-proc.c:3790-3840) under the kernel's configuration MULTI_THREADED=OFF, ENGINES=OFF
# (audit D-0740 item 2, D-0716 item 7 Q1(a), Q2(a): the kernel's `threads` flag stays false; scope: lk-channel evidence/TH1/th1_scope.md).
# Upstream (swipl-devel 18168e62) has two bodies of `setThreadLocalDefinition(def, val)`:
#   `#ifdef O_ENGINES`  (pl-proc.c:3799-3828): a predicate that already has the attribute (or lacks it, for val false) answers true; static -> local is
#                       REFUSED while the predicate has clauses (`ERR_MODIFY_STATIC_PREDICATE`); local -> static is REFUSED with the context
#                       `predicate is thread-local`; else the per-thread vector, `P_DYNAMIC|P_TRANSACT|P_VOLATILE|P_THREAD_LOCAL`, `S_THREAD_LOCAL`;
#   `#else`             (pl-proc.c:3829-3838): `setDynamicDefinition(def, val);` then `if ( val ) set(def, P_VOLATILE|P_THREAD_LOCAL); else
#                       clear(def, P_VOLATILE|P_THREAD_LOCAL); return true;` : no refusal, no early return.
# The kernel is the `#else` build, and the pinned swipl (10.1.20 at ~/.local/swipl-pin1-18168e62) is a THREADED build (threads=true, engines=true) that takes
# the first body. Where the two bodies differ, the oracle's answer differs from the kernel's intended one: a KNOWN DIFFERENCE (D-0716 Q2 (a)), the situation of
# test_event_threads_off_swipl.jl. This file pins BOTH answers per row: `_TLO_KERNEL` (what the `#else` body answers, with its line above) and `_TLO_SWIPL`
# (the oracle's answer, written by the driver below with `LC_ALL=C`, twice, byte-identical; the live check with `swipl` on PATH compares the oracle's answers with it).
# A row whose two lines are equal is a CONTROL; a row whose lines differ must be listed in `_TLO_DIVERGES` and the other way round.
#   * Controls: declaring and using a thread-local predicate (assert, retract, retractall, clause, the properties `thread_local`, `dynamic`, `volatile`, a module
#     qualification, a repeated declaration, `dynamic` and `thread_local` in either order, a non-boolean value, `thread_local` false on a predicate that has no clauses
#     or is static): the two bodies agree.
#   * Differences (tl13-tl19): `thread_local` on a predicate WITH clauses (dynamic and not thread-local, static, an erased clause still in the list: the `#else` body
#     calls `setDynamicDefinition` first and never looks at the clauses), `thread_local` false on a thread-local predicate (the `#else` body makes it static, clears
#     the flags, answers true) and on a dynamic predicate that is not thread-local (it makes it static; the other body returns at its first test).
#   * `'$local_definitions'/2` is registered only under O_ENGINES (pl-proc.c:4426-4428): the kernel has no such predicate (tl20).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written, edit-only step): every kernel answer; the gate decides. The swipl lines are
#     written by swipl 10.1.20.
#   * CHECKLIST (D-0716 Q2 (b)): after Phase 1 coding the second oracle (`-DMULTI_THREADED=OFF -DENGINES=OFF`, tools/build_oracle.sh FLAGS) is built; then `_TLO_SWIPL`
#     is regenerated from it, every row of `_TLO_DIVERGES` becomes an exact row (kernel == oracle), the set empties, and the `@test` that it is not empty is deleted.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TLO = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tlos(x) = lk_sym(_TLO, Symbol(x))

_tlo_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tlo_enc(t::_TLO, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tlo_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tlo_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tlo_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tlo_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the expected answers, written as the driver's `enc/1` writes them
_ea(s::String) = "a" * _tlo_codes(s)
_ei(n::Integer) = "i$n"
_ec(name::String, args::String...) =
    "c" * _tlo_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_el(xs::String...) = foldr((x, acc) -> _ec("[|]", x, acc), xs; init="nil")
_epi(name::String, arity::Integer) = _ec("/", _ea(name), _ei(arity))
_eraised(formal::String) = _ec("raised", formal)
_eperm_static(name::String, arity::Integer) =
    _ec("permission_error", _ea("modify"), _ea("static_procedure"), _epi(name, arity))
_eline(id::String, answer::String) = "t_$id " * _ec("t_$id", answer)

const _TLO_DRIVER = raw"""
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

function _tlo_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TLO_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: tl14/1 and tl24/1 are static predicates with a clause; every other predicate is declared by its own row (no state is shared between rows)
const _TLO_PROGRAM = raw"""
tl14(1).
tl24(1).
"""

const _TLO_CASES = [
    ("tl01", raw"thread_local(tl01/1), assertz(tl01(1)), assertz(tl01(2)), findall(X, tl01(X), R)"),
    ("tl02", raw"thread_local(tl02/1), ( predicate_property(tl02(_), thread_local) -> R = yes ; R = no )"),
    ("tl03", raw"thread_local(tl03/1), ( predicate_property(tl03(_), dynamic) -> R = yes ; R = no )"),
    ("tl04", raw"thread_local(tl04/1), ( predicate_property(tl04(_), volatile) -> R = yes ; R = no )"),
    ("tl05", raw"thread_local(tl05/1), assertz(tl05(1)), assertz(tl05(2)), retract(tl05(1)), findall(X, tl05(X), R)"),
    ("tl06", raw"thread_local(tl06/1), assertz(tl06(7)), clause(tl06(X), true), R = X"),
    ("tl07", raw"thread_local(tl07/1), ( tl07(_) -> R = yes ; R = no )"),
    ("tl08", raw"thread_local(tl08/1), thread_local(tl08/1), assertz(tl08(1)), thread_local(tl08/1), findall(X, tl08(X), R)"),
    ("tl09", raw"thread_local(tl09/1), dynamic(tl09/1), assertz(tl09(1)), findall(X, tl09(X), R)"),
    ("tl10", raw"dynamic(tl10/1), thread_local(tl10/1), assertz(tl10(1)), findall(X, tl10(X), R)"),
    ("tl11", raw"thread_local(tl11/1), assertz(tl11(1)), retractall(tl11(_)), findall(X, tl11(X), R)"),
    ("tl12", raw"thread_local(tm:tl12/1), assertz(tm:tl12(1)), findall(X, tm:tl12(X), R)"),
    ("tl13", raw"dynamic(tl13/1), assertz(tl13(1)), thread_local(tl13/1), findall(X, tl13(X), R)"),
    ("tl14", raw"thread_local(tl14/1), assertz(tl14(2)), findall(X, tl14(X), R)"),
    ("tl15", raw"assertz(tl15(1)), retract(tl15(1)), thread_local(tl15/1), assertz(tl15(2)), findall(X, tl15(X), R)"),
    ("tl16", raw"'$set_predicate_attribute'(tl16(_), thread_local, true), '$set_predicate_attribute'(tl16(_), thread_local, false), ( '$get_predicate_attribute'(tl16(_), thread_local, 1) -> R = yes ; R = no )"),
    ("tl17", raw"dynamic(tl17/1), assertz(tl17(1)), '$set_predicate_attribute'(tl17(_), thread_local, false), ( '$get_predicate_attribute'(tl17(_), dynamic, 1) -> R = yes ; R = no )"),
    ("tl18", raw"dynamic(tl18/1), assertz(tl18(1)), '$set_predicate_attribute'(tl18(_), thread_local, false), assertz(tl18(2)), findall(X, tl18(X), R)"),
    ("tl19", raw"thread_local(tl19/1), assertz(tl19(1)), '$set_predicate_attribute'(tl19(_), thread_local, false), findall(X, tl19(X), R)"),
    ("tl20", raw"'$local_definitions'(_, _), R = yes"),
    ("tl21", raw"'$set_predicate_attribute'(tl21(_), thread_local, 1), assertz(tl21(1)), findall(X, tl21(X), R)"),
    ("tl22", raw"'$set_predicate_attribute'(tl22(_), thread_local, false), R = ok"),
    ("tl23", raw"thread_local(tl23/1), assertz(tl23(1)), '$set_predicate_attribute'(tl23(_), dynamic, false), '$set_predicate_attribute'(tl23(_), thread_local, true), assertz(tl23(2)), findall(X, tl23(X), R)"),
    ("tl24", raw"'$set_predicate_attribute'(tl24(_), thread_local, false), findall(X, tl24(X), R)")
]

const _TLO_SWIPL = [
    "ok",
    "t_tl01 c[116,95,116,108,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_tl02 c[116,95,116,108,48,50]/1(a[121,101,115])",
    "t_tl03 c[116,95,116,108,48,51]/1(a[121,101,115])",
    "t_tl04 c[116,95,116,108,48,52]/1(a[121,101,115])",
    "t_tl05 c[116,95,116,108,48,53]/1(c[91,124,93]/2(i2,nil))",
    "t_tl06 c[116,95,116,108,48,54]/1(i7)",
    "t_tl07 c[116,95,116,108,48,55]/1(a[110,111])",
    "t_tl08 c[116,95,116,108,48,56]/1(c[91,124,93]/2(i1,nil))",
    "t_tl09 c[116,95,116,108,48,57]/1(c[91,124,93]/2(i1,nil))",
    "t_tl10 c[116,95,116,108,49,48]/1(c[91,124,93]/2(i1,nil))",
    "t_tl11 c[116,95,116,108,49,49]/1(nil)",
    "t_tl12 c[116,95,116,108,49,50]/1(c[91,124,93]/2(i1,nil))",
    "t_tl13 c[116,95,116,108,49,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,108,49,51],i1))))",
    "t_tl14 c[116,95,116,108,49,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,108,49,52],i1))))",
    "t_tl15 c[116,95,116,108,49,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,108,49,53],i1))))",
    "t_tl16 c[116,95,116,108,49,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,108,49,54],i1))))",
    "t_tl17 c[116,95,116,108,49,55]/1(a[121,101,115])",
    "t_tl18 c[116,95,116,108,49,56]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_tl19 c[116,95,116,108,49,57]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,108,49,57],i1))))",
    "t_tl20",
    "t_tl21 c[116,95,116,108,50,49]/1(c[91,124,93]/2(i1,nil))",
    "t_tl22 c[116,95,116,108,50,50]/1(a[111,107])",
    "t_tl23 c[116,95,116,108,50,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_tl24 c[116,95,116,108,50,52]/1(c[91,124,93]/2(i1,nil))"
]


# what the `#else` body answers (pl-proc.c:3829-3838) where it differs from the oracle; every other row's kernel answer is the oracle's line
const _TLO_KERNEL_DIFF = Dict(
    # tl13: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): `thread_local` on a dynamic predicate with a clause: `setDynamicDefinition` is a no-op, the flags are set, true (the oracle refuses: a clause, no P_THREAD_LOCAL yet)
    "tl13" => _eline("tl13", _el(_ei(1))),
    # tl14: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): a static predicate with a clause becomes dynamic (protect_static_code is false) and thread-local, the clause stays
    "tl14" => _eline("tl14", _el(_ei(1), _ei(2))),
    # tl15: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): the erased clause still in the list does not matter: only the flags are set
    "tl15" => _eline("tl15", _el(_ei(2))),
    # tl16: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): thread_local false on a thread-local predicate: setDynamicDefinition(def, false), both flags cleared, true (the oracle: permission_error, still thread-local)
    "tl16" => _eline("tl16", _ea("no")),
    # tl17: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): thread_local false on a dynamic predicate that is not thread-local makes it static (the oracle returns at its first test: still dynamic)
    "tl17" => _eline("tl17", _ea("no")),
    # tl18: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): the predicate is static and has a clause: assertz is refused as for any static predicate
    "tl18" => _eline("tl18", _eraised(_eperm_static("tl18", 1))),
    # tl19: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): thread_local false leaves the clause in a static predicate
    "tl19" => _eline("tl19", _el(_ei(1))),
    # tl20: DIVERGES vs threads=true oracle (TH1a ruling D-0716 Q1(a)): `$local_definitions/2` is registered only under O_ENGINES (pl-proc.c:4426-4428): an unknown procedure (the oracle's call fails)
    "tl20" => _eline(
        "tl20", _eraised(_ec("existence_error", _ea("procedure"), _epi("\$local_definitions", 2)))
    )
)
const _TLO_KERNEL = String[
    (
        m = match(r"^t_(tl\d+)", l);
        m === nothing ? l : get(_TLO_KERNEL_DIFF, String(m.captures[1]), l)
    ) for l in _TLO_SWIPL
]

const _TLO_DIVERGES = ["tl13", "tl14", "tl15", "tl16", "tl17", "tl18", "tl19", "tl20"]

function _tlo_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _TLO_CASES]
    text =
        _TLO_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TLO_CASES
        ])
    f = joinpath(mktempdir(), "tlo.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _tlo_load(path::String)
    gd = LK.PL_global_data{_TLO}()
    ld = LK.PL_local_data{_TLO}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tlo_enc(ball::_TLO))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tlo_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tlos(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TLO, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols, _tlo_enc(mk_expr(_TLO, _TLO[_tlos(pred), lk_answers(ld, (a:a)...)...]))
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
    return pred * join(" " .* sols)
end

@testset "thread_local in the ENGINES=OFF build: the kernel's answers" begin
    f, names = _tlo_file()
    gd, ld, st = _tlo_load(f)
    kl = String[st]
    for name in names
        push!(kl, _tlo_ask(gd, ld, name))
    end
    @test length(kl) == length(_TLO_KERNEL)
    for (k, p) in zip(kl, _TLO_KERNEL)
        k == p || println(stderr, "  ours   ", k, "\n  pinned ", p)
        @test k == p
    end
end

@testset "KNOWN DIFFERENCES: the oracle (threads=true, engines=true) takes the O_ENGINES body" begin
    @test length(_TLO_SWIPL) == length(_TLO_KERNEL) == length(_TLO_CASES) + 1
    @test _TLO_SWIPL[1] == _TLO_KERNEL[1] == "ok"
    differ = String[]
    for (id, _) in _TLO_CASES
        s = only(filter(l -> startswith(l, "t_$id"), _TLO_SWIPL))
        k = only(filter(l -> startswith(l, "t_$id"), _TLO_KERNEL))
        s == k || push!(differ, id)
    end
    @test differ == _TLO_DIVERGES
    @test length(_TLO_DIVERGES) == 8                    # tl13-tl19 (the body) and tl20 (the O_ENGINES-only predicate)
    for id in ("tl01", "tl02", "tl05", "tl08", "tl09", "tl10", "tl21", "tl22", "tl23", "tl24")
        @test !(id in _TLO_DIVERGES)                    # the controls: the same answer on both sides
    end
end

@testset "setThreadLocalDefinition!: the `#else` body called directly (pl-proc.c:3829-3838)" begin
    f = joinpath(mktempdir(), "wb.pl")
    write(f, "wb_s(1).\n:- dynamic wb_d/1.\nwb_d(1).\n")
    gd, ld, st = _tlo_load(f)
    @test st == "ok"
    both = LK.P_DYNAMIC | LK.P_TRANSACT
    tl = LK.P_VOLATILE | LK.P_THREAD_LOCAL
    s = LK.isCurrentProcedure(sym_key(_tlos("wb_s")), 1, LK.MODULE_user(gd))
    d = LK.isCurrentProcedure(sym_key(_tlos("wb_d")), 1, LK.MODULE_user(gd))
    @test s !== nothing && d !== nothing
    sd, dd = s.definition, d.definition
    @test (sd.flags & (both | tl)) == 0                 # static, one clause
    @test (dd.flags & both) == both && (dd.flags & tl) == 0
    @test LK.setThreadLocalDefinition!(ld, sd, true) === true    # a clause does not refuse it
    @test (sd.flags & (both | tl)) == (both | tl)       # setDynamicDefinition's two bits, then the two thread-local bits
    @test LK.setThreadLocalDefinition!(ld, sd, true) === true    # again: no early return needed, the same flags
    @test (sd.flags & (both | tl)) == (both | tl)
    @test LK.setThreadLocalDefinition!(ld, sd, false) === true   # local --> static: accepted
    @test (sd.flags & (both | tl)) == 0                 # all four bits cleared
    @test LK.setAttrDefinition(ld, dd, LK.P_THREAD_LOCAL, true) === true  # dynamic with a clause: accepted
    @test (dd.flags & (both | tl)) == (both | tl)
    @test LK.setAttrDefinition(ld, dd, LK.P_THREAD_LOCAL, false) === true
    @test (dd.flags & (both | tl)) == 0                 # the predicate is static now
    @test LK.setAttrDefinition(ld, dd, LK.P_THREAD_LOCAL, false) === true  # false on a static predicate: no change
    @test (dd.flags & (both | tl)) == 0
end

@testset "the oracle's lines are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TH1AA LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _tlo_file()
        @test _tlo_swipl_lines(f, names) == _TLO_SWIPL
    end
end

