# ORIGINAL: the module table and pl-modul.c's first predicates (MOD1; audit D-0149) against a LIVE swipl 10.1.19; upstream tests the module system through Prolog (tests/core_lang/test_module.pl, test_qcall.pl, …), mirrored when plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_module_swipl.jl — MOD1's gate, through a PROGRAM (the pattern of test/db/test_retract_swipl.jl):
# each row is a predicate `t_<id>(R)`; the kernel consults the program and enumerates every solution of every t_<id>/1,
# swipl does the same through a driver, and the answers are compared as lines. EVERY expected value is swipl's own
# answer (the driver runs live): the rows are in ONE session, in order, so a row builds on the modules the rows before
# it made — and after the last row both sides print each module's CLASS and SUPER MODULES (`import_module/2` on swipl's
# side, the kernel's record on the other), which the rows can only reach through what a call resolves to. The hand-written
# values are in the white-box testsets, each with its reason: the record's fields swipl cannot answer (flags, level,
# the public table's ORDER — swipl's is its hash table's, D-0149 item 1), and what the kernel refuses by name.
#   s*  the source and typein modules ('$set_source_module'/1, '$current_source_module'/1, …); a module made by naming it
#   m*  '$module_property'/2: class, exports, file, line_count, the errors; size, program_size and
#       last_modified_generation compared by TYPE and by their relations (D-0149 MQ3: a number, not swipl's bytes)
#   c*  add_import_module/3, delete_import_module/2, set_module(base(M)): what a call resolves to as the supers change
#   k*  set_module(class(C)), p* the other properties and the errors of set_module/1, e* a clause that names a module
# `m15` needs src/pl-proc.jl to call `setLastModifiedPredicate` at its assert and retract sites (the report of MOD1 lists the
# lines): without them last_modified_generation stays 0.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))
_tlf(f, xs::_TL...) = mk_expr(_TL, _TL[_tls(f), xs...])
_tlv() = mk_var(_TL, LK.fresh_var_keys!(1))

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
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the modules both sides print after the last row: (the name as swipl writes it with ~w, the name as the kernel's atom)
const _MODS = Any[
    "user", "system", "cb1", "cb2", "cm1", "cm3", "cm4", "cm5", "cs1", "cs2", "cl1", "cl2",
    "ps1",
    "sm_a", "sm_b", "tm_a", "tm_b", "sm_new", "\$sm_sys", "[]", "pz_m", "ec_new",
    "mp_none_zz"
]
_mod_atom(n::String) = n == "[]" ? LK.mk_nil(_TL) : _tls(n)
_mod_pl(n::String) =
    if n == "[]"
        "[]"
    elseif n == "\$sm_sys"
        "'\$sm_sys'"
    else
        n
    end

"The line the kernel prints for module `name`: `m NAME CLASS SUPER…`, or `m NAME none`."
function _mod_line(gd::LK.PL_global_data{_TL}, name::String)::String
    m = LK.isCurrentModule(gd.modules, _mod_atom(name))
    m === nothing && return "m $name none"
    sup = [sym_text(gd.modules[s].atom) for s in m.supers]
    return join(["m", name, sym_text(m.class), sup...], " ")
end

"The kernel's lines: the load's outcome, one per row (every solution), then the modules' lines."
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
    append!(out, [_mod_line(gd, m) for m in _MODS])
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
fz_mod(M) :-
    ( '$module_property'(M, class(C)) -> findall(S, import_module(M, S), Ss) ; C = none, Ss = [] ),
    format("m ~w ~w", [M, C]), forall(member(S, Ss), format(" ~w", [S])), nl.
fz_run(File, Ns, Ms) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)),
    forall(member(M, Ms), fz_mod(M)).
"""

"swipl's lines for the same program: the driver consults it and runs the rows, then prints the modules."
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    mods = "[" * join((_mod_pl(m) for m in _MODS), ",") * "]"
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "], $mods), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# The program: qq/1 is `user`'s, cb1:qq(c) is asserted by c01. A row that reports an error catches it and returns
# `Formal-Context`, as the driver of rows.out printed it.
const _PROGRAM = """
qq(u).
set_class(M, C, R) :-
    catch(( set_module(M:class(C)), '\$module_property'(M, class(K)), R = K ),
          error(E, Ctx), R = E-Ctx).
"""

# (id, goal)
const _MS_CASES = [
    # ---- the source and typein modules; a module made by naming it
    ("s01", "'\$current_source_module'(R)"),
    ("s02", "'\$current_typein_module'(R)"),
    (
        "s03",
        "'\$set_source_module'(sm_a), '\$current_source_module'(A), '\$set_source_module'(user), '\$current_source_module'(B), R = A-B"
    ),
    (
        "s04",
        "'\$set_typein_module'(tm_a), '\$current_typein_module'(A), '\$set_typein_module'(user), '\$current_typein_module'(B), R = A-B"
    ),
    (
        "s05",
        "'\$set_source_module'(sm_b), '\$set_typein_module'(tm_b), '\$current_source_module'(S), '\$current_typein_module'(T), '\$set_source_module'(user), '\$set_typein_module'(user), R = S-T"
    ),
    ("s06", "catch('\$set_source_module'(_), error(E, C), true), R = E-C"),
    ("s07", "catch('\$set_source_module'(1), error(E, C), true), R = E-C"),
    ("s08", "catch('\$set_typein_module'(f(x)), error(E, C), true), R = E-C"),
    # the text atom '[]' and SWI-7's [] are two modules
    (
        "s09",
        "'\$set_source_module'('[]'), '\$current_source_module'(M), '\$set_source_module'(user), ( M == [] -> R = nil ; R = text )"
    ),
    (
        "s10",
        "'\$set_source_module'([]), '\$current_source_module'(M), '\$set_source_module'(user), ( M == [] -> R = nil ; R = text )"
    ),
    (
        "s11",
        "'\$set_source_module'(sm_new), '\$set_source_module'(user), '\$module_property'(sm_new, class(R))"
    ),
    (
        "s12",
        "'\$set_source_module'('\$sm_sys'), '\$set_source_module'(user), '\$module_property'('\$sm_sys', class(R))"
    ),
    # ---- '$module_property'/2
    ("m01", "'\$module_property'(user, class(R))"),
    ("m02", "'\$module_property'(system, class(R))"),
    ("m03", "( '\$module_property'(mp_none_zz, class(C)) -> R = C ; R = no )"),
    ("m04", "'\$module_property'(user, exports(R))"),
    ("m05", "'\$module_property'(system, exports(R))"),
    ("m06", "( '\$module_property'(user, file(_)) -> R = yes ; R = no )"),
    ("m07", "( '\$module_property'(user, line_count(_)) -> R = yes ; R = no )"),
    ("m08", "catch('\$module_property'(user, foo), error(E, C), true), R = E-C"),
    ("m09", "catch('\$module_property'(user, foo(1)), error(E, C), true), R = E-C"),
    ("m10", "catch('\$module_property'(user, _), error(E, C), true), R = E-C"),
    ("m11", "catch('\$module_property'(1, class(_)), error(E, C), true), R = E-C"),
    ("m12", "catch('\$module_property'(_, class(_)), error(E, C), true), R = E-C"),
    ("m13", "( '\$module_property'(user, program_space(_)) -> R = yes ; R = no )"),
    # size, program_size, last_modified_generation: integers (D-0149 MQ3: the byte counts are the machine's)
    (
        "m14",
        "'\$module_property'(system, size(S)), '\$module_property'(system, program_size(P)), '\$module_property'(system, last_modified_generation(G)), ( integer(S), S > 0, integer(P), P >= 0, integer(G), G >= 0 -> R = ints ; R = other )"
    ),
    # a module's clauses: program_size is 0, grows with an assertz, falls back with a retract of an equal clause;
    # last_modified_generation is 0 and rises with each assertz and retract
    (
        "m15",
        "'\$set_source_module'(pz_m), '\$set_source_module'(user), '\$module_property'(pz_m, program_size(P0)), '\$module_property'(pz_m, last_modified_generation(G0)), assertz(pz_m:f(1)), '\$module_property'(pz_m, program_size(P1)), '\$module_property'(pz_m, last_modified_generation(G1)), assertz(pz_m:f(2)), '\$module_property'(pz_m, program_size(P2)), '\$module_property'(pz_m, last_modified_generation(G2)), retract(pz_m:f(1)), '\$module_property'(pz_m, program_size(P3)), '\$module_property'(pz_m, last_modified_generation(G3)), ( P0 == 0, G0 == 0, P1 > P0, P2 > P1, P3 < P2, P3 == P1, G1 > G0, G2 > G1, G3 > G2 -> R = ok ; R = [P0,P1,P2,P3,G0,G1,G2,G3] )"
    ),
    # ---- the super modules: what a call resolves to as they change (cm1: [cb1,user], then [cb2,cb1,user], …)
    (
        "c01",
        "assertz(cb1:q(1)), assertz(cb2:q(2)), assertz(cb1:qq(c)), add_import_module(cm1, cb1, start), G = cm1:q(X), call(G), R = X"
    ),
    ("c02", "add_import_module(cm1, cb2, start), G = cm1:q(X), call(G), R = X"),
    ("c03", "add_import_module(cm1, cb1, end), G = cm1:q(X), call(G), R = X"),         # already a super: no change
    ("c04", "delete_import_module(cm1, cb2), G = cm1:q(X), call(G), R = X"),
    ("c05", "( delete_import_module(cm1, cb2) -> R = yes ; R = no )"),                # no longer one
    ("c06", "add_import_module(cm3, cb1, end), G = cm3:qq(X), call(G), R = X"),        # [user, cb1]: user's qq
    ("c07", "add_import_module(cm4, cb1, start), G = cm4:qq(X), call(G), R = X"),      # [cb1, user]: cb1's qq
    ("c08", "add_import_module(cm5, cb1, middle), G = cm5:qq(X), call(G), R = X"),     # not `start`: at the end
    ("c09", "catch(add_import_module(user, cm4, start), error(E, C), true), R = E-C"), # cm4 reaches user: a cycle
    ("c10", "catch(add_import_module(cm4, cm4, start), error(E, C), true), R = E-C"),
    ("c11", "add_import_module(cm4, user, end), G = cm4:qq(X), call(G), R = X"),       # user is one: unchanged
    ("c12", "catch(add_import_module(_, user, start), error(E, C), true), R = E-C"),
    ("c13", "catch(add_import_module(cm4, _, start), error(E, C), true), R = E-C"),
    ("c14", "catch(add_import_module(cm4, user, _), error(E, C), true), R = E-C"),
    ("c15", "catch(add_import_module(cm4, user, 1), error(E, C), true), R = E-C"),
    ("c16", "catch(add_import_module(1, user, start), error(E, C), true), R = E-C"),
    ("c17", "catch(add_import_module(system, user, start), error(E, C), true), R = E-C"),
    ("c18", "G = cm4:qq(X), call(G), R = X"),                                           # the failed adds changed nothing
    ("c19", "set_module(cs1:base(cb1)), G = cs1:qq(X), call(G), R = X"),               # one super, replaced in place
    ("c20", "set_module(cm4:base(cb2)), G = cm4:qq(X), call(G), R = X"),               # two supers: cleared, then added
    ("c21", "catch(set_module(cs1:base(cs1)), error(E, C), true), R = E-C"),
    ("c22", "catch(set_module(base(user)), error(E, C), true), R = E-C"),              # unqualified: the typein module
    (
        "c23",
        "'\$set_typein_module'(cs2), set_module(base(cb1)), '\$set_typein_module'(user), G = cs2:qq(X), call(G), R = X"
    ),
    ("c24", "( delete_import_module(cs1, cb1) -> R = yes ; R = no )"),
    ("c25", "G = cs1:qq(X), call(G), R = X"),                                           # no supers: existence_error
    # ---- set_module(class(C))
    ("k01", "set_class(cl1, library, R)"),
    ("k02", "set_class(cl1, temporary, R)"),                                           # not a user module
    ("k03", "set_class(cl1, user, R)"),
    ("k04", "set_class(cl1, temporary, R)"),                                           # empty, user: allowed
    ("k05", "assertz(cl2:f), set_class(cl2, temporary, R)"),                           # not empty
    ("k06", "set_class(cl2, foo, R)"),
    ("k07", "set_class(cl2, 1, R)"),
    ("k08", "set_class(cl2, _, R)"),
    ("k09", "set_class(cl2, test, R)"),
    ("k10", "set_class(cl2, development, R)"),
    ("k11", "set_class(cl2, system, R)"),
    ("k12", "set_class(cl2, user, R)"),
    ("k13", "catch(set_module(user:class(temporary)), error(E, C), true), R = E-C"),
    # ---- set_module/1: program_space and the errors
    (
        "p01",
        "set_module(ps1:program_space(0)), ( '\$module_property'(ps1, program_space(_)) -> R = yes ; R = no )"
    ),
    ("p02", "catch(set_module(ps1:program_space(foo)), error(E, C), true), R = E-C"),
    ("p03", "catch(set_module(ps1:program_space(-1)), error(E, C), true), R = E-C"),
    ("p04", "catch(set_module(ps1:program_space(_)), error(E, C), true), R = E-C"),
    ("p05", "catch(set_module(foo), error(E, C), true), R = E-C"),
    ("p06", "catch(set_module(foo(1)), error(E, C), true), R = E-C"),
    ("p07", "catch(set_module(_), error(E, C), true), R = E-C"),
    ("p08", "catch(set_module(cs1:class(_)), error(E, C), true), R = E-C"),
    ("p09", "catch(set_module(cs1:base(1)), error(E, C), true), R = E-C"),
    ("p10", "catch(set_module(cs1:base(_)), error(E, C), true), R = E-C"),
    ("p11", "catch(set_module(1:class(user)), error(E, C), true), R = E-C"),
    ("p12", "catch(set_module(_:class(user)), error(E, C), true), R = E-C"),
    ("p13", "catch(set_module(a:b:foo(1)), error(E, C), true), R = E-C"),
    # ---- a clause that names a module makes it, and goes into it (assert needs no context module: the name is given)
    ("e01", "assertz(ec_new:f), '\$module_property'(ec_new, class(R))"),
    ("e02", "( clause(f, _) -> R = leaked ; clause(ec_new:f, B), R = B )"),
    ("e03", "G = ec_new:f, ( call(G) -> R = yes ; R = no )")
]

@testset "the module table and pl-modul.c's predicates == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "MODULE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t_$(id)" for (id, _) in _MS_CASES]
        text = _PROGRAM * join(["t_$(id)(R) :- ($g).\n" for (id, g) in _MS_CASES])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl = kernel_lines(f, names)
        @test length(sw) == 1 + length(names) + length(_MODS) && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: every row answered (swipl's own lines, one extractor, `count` on them) …
        rows = sw[2:(1 + length(names))]
        @test count(l -> endswith(l, "undefined"), rows) == 0
        @test count(l -> endswith(l, " exception"), rows) == 1                         # c25 only
        @test count(l -> startswith(l, "t_") && length(split(l, ' ')) == 1, rows) == 0  # none FAILED (a bare name)
        # … with the shapes the rows are about: the cycle error (c09, c10, c17, c21, c22), program_size's rise (m15 is `ok`)
        @test count(
            l -> occursin(
                "119,111,117,108,100,32,99,114,101,97,116,101,32,97,32,99,121,99,108,101",
                l
            ),
            rows
        ) == 5
        @test any(l -> startswith(l, "t_m15 ") && endswith(l, "a[111,107])"), rows)
        @test any(l -> startswith(l, "t_c02 ") && endswith(l, "i2)"), rows)             # cb2's q, once cb2 is first
        # … and the modules the rows made are there with their classes (swipl's own) and supers
        mods = sw[(2 + length(names)):end]
        @test length(mods) == length(_MODS) && all(l -> startswith(l, "m "), mods)
        @test count(l -> endswith(l, " none"), mods) == 1                               # mp_none_zz, never made
        @test "m cm4 user cb2" in mods && "m cl1 temporary user" in mods &&
            "m cs1 user" in mods
    end
end

# ── the kernel's record (no swipl: the fields it cannot answer) ──────────────────────────────────────────────────

"Call the `system` predicate `name` on `args` in a fresh query: `(:true | :false | :exception, answers)`."
function _call(gd, ld, name::String, args::Vector)
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), length(args), LK.MODULE_system(gd))
    proc === nothing && error("no system predicate $name/$(length(args))")
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()
    for (i, t) in enumerate(args)
        LK.putSlotValue!(ld, a + i, t, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        (:true, lk_answers(ld, (a:(a + length(args) - 1))...))
    elseif rc == LK.PL_S_EXCEPTION
        (:exception, [lk_answer(ld, LK.PL_exception(ld, qid))])
    else
        (:false, _TL[])
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

_db() = (gd=LK.PL_global_data{_TL}(); (gd, LK.PL_local_data{_TL}(gd)))

# the syntax flags every module starts with (pl-modul.c:_lookupModule, SWI-7 syntax: !GD->options.traditional)
const _SYNTAX = LK.M_CHARESCAPE | LK.DBLQ_STRING | LK.BQ_CODES | LK.O_RATIONAL_SYNTAX

@testset "the table: creation order, a name index, the record of a created module" begin
    gd, ld = _db()
    @test gd.modules isa LK.module_table && length(gd.modules) == 2
    @test [m.index for m in gd.modules] == [1, 2]                  # gd.modules[i].index == i (design H3)
    @test LK.isCurrentModule(gd.modules, _tls(:wb_none)) === nothing &&
        length(gd.modules) == 2
    sys, user = gd.modules
    a = LK.lookupModule(gd, _tls(:wb_a))
    @test length(gd.modules) == 3 && a.index == 3 && gd.modules[3] === a
    @test LK.lookupModule(gd, _tls(:wb_a)) === a && length(gd.modules) == 3
    @test LK.isCurrentModule(gd.modules, _tls(:wb_a)) === a && gd.modules.names[a.name] == 3
    # pl-modul.c:108-120: `user`'s super is system; system has none and is class system with `unknown` = error; a name
    # starting with `$` is a system-class module under system; any other a user-class module under user. The record's
    # flags, level and counters are not answerable by swipl (class and supers are: the program's last lines).
    d = LK.lookupModule(gd, _tls("\$wb_d"))
    @test sys.level == 0 && user.level == 1 && d.level == 1 && a.level == 2
    @test sys.flags == (_SYNTAX | LK.M_SYSTEM | UInt32(LK.UNKNOWN_ERROR)) &&
        sys.supers == Int[]
    @test user.flags == _SYNTAX && user.supers == [sys.index]
    @test d.flags == (_SYNTAX | LK.M_SYSTEM) && d.supers == [sys.index]
    @test a.flags == _SYNTAX && a.supers == [user.index]
    @test lk_eq(sys.class, _tls(:system)) && lk_eq(user.class, _tls(:user))
    @test lk_eq(d.class, _tls(:system)) && lk_eq(a.class, _tls(:user))
    for m in (sys, user, d, a)
        @test m.file == 0 && m.line_no == 0 && m.code_size == 0 && m.code_limit == 0
        @test m.var_prefix == 0 && m.references == 0
        # `system` has had the stand-in boot's clauses asserted into it (setLastModifiedPredicate!); the others none
        @test m === sys ? 0 < m.last_modified <= gd._generation : m.last_modified == 0
        @test isempty(m.public_) && isempty(m.public_order)
    end
    @test LK.getUnknownModule(gd, a) == LK.UNKNOWN_ERROR           # inherited: a → user → system
    @test LK.inheritUnknown(gd, a) == LK.UNKNOWN_ERROR
    # a name's identity is its sym_key: `[]` (reserved) and '[]' (text) are two modules, as swipl's s09/s10 rows show
    nilm = LK.lookupModule(gd, LK.mk_nil(_TL))
    txtm = LK.lookupModule(gd, _tls("[]"))
    @test nilm !== txtm && length(gd.modules) == 6          # system, user, wb_a, \$wb_d, [], '[]'
    # a module is never removed from the vector, and a definition holds its index
    @test LK.lookupProcedure(_tls(:p), 1, a).definition.module_ == a.index
    @test LK.M_DESTROYED == UInt32(0x00010000)                     # pl-incl.h
end

@testset "the super modules: add, delete, set, clear, levels, cycles (pl-modul.c, by the source)" begin
    gd, ld = _db()
    ms = gd.modules
    sys, user = ms[1], ms[2]
    mk(n) = LK.lookupModule(gd, _tls(n))
    a, b, c, d = mk(:a), mk(:b), mk(:c), mk(:d)
    # 'A' prepends and 'Z' appends; a super already there is kept where it is
    @test LK.addSuperModule(ms, ld, b, a, 'Z') && b.supers == [user.index, a.index]
    @test LK.addSuperModule(ms, ld, b, c, 'A') && b.supers == [c.index, user.index, a.index]
    @test LK.addSuperModule(ms, ld, b, user, 'A') &&
        b.supers == [c.index, user.index, a.index]
    # level: one more than the highest of the supers' (updateLevelModule); a, c are user's children: level 2
    @test a.level == 2 && c.level == 2 && b.level == 3
    @test LK.addSuperModule(ms, ld, d, b, 'Z') && d.supers == [user.index, b.index] &&
        d.level == 4
    # delete: the level is recomputed; a non-super is false and changes nothing
    @test LK.delSuperModule(ms, d, b) && d.supers == [user.index] && d.level == 2
    @test !LK.delSuperModule(ms, d, b) && d.supers == [user.index]
    @test LK.addSuperModule(ms, ld, d, b, 'Z')
    # isSuperModule(s, m): s is m, a direct super, an indirect one through the LAST super (goto next) or through an
    # earlier one (the recursion)
    @test LK.isSuperModule(ms, d, d) && LK.isSuperModule(ms, b, d) &&
        LK.isSuperModule(ms, user, d)
    @test LK.isSuperModule(ms, a, d)                               # d → b (last) → a (last of b's three)
    @test LK.isSuperModule(ms, c, d)                               # d → b (last) → c (FIRST of b's: the recursion)
    @test LK.isSuperModule(ms, sys, d) && !LK.isSuperModule(ms, d, b) &&
        !LK.isSuperModule(ms, a, c)
    # a cycle is refused: false, a pending exception, nothing changed
    @test ld.exception_term == 0
    @test !LK.addSuperModule(ms, ld, a, d, 'Z') && ld.exception_term != 0
    @test a.supers == [user.index] && a.level == 2
    # setSuperModule: a module with ONE super gets the new one in its place (level = s.level + 1)…
    @test LK.setSuperModule(ms, ld, a, c) && a.supers == [c.index] && a.level == 3
    # … one with the same super is cleared and added again; one with several is cleared, and the new one added
    @test LK.setSuperModule(ms, ld, a, c) && a.supers == [c.index] && a.level == 3
    @test LK.setSuperModule(ms, ld, b, a) && b.supers == [a.index] && b.level == 4
    # the module itself: refused (and no change)
    ld2 = LK.PL_local_data{_TL}(gd)
    @test !LK.setSuperModule(ms, ld2, b, b) && ld2.exception_term != 0 &&
        b.supers == [a.index]
    # clear: no supers, level 0
    LK.clearSupersModule(d)
    @test isempty(d.supers) && d.level == 0
    LK.clearSupersModule_no_lock(b)
    @test isempty(b.supers) && b.level == 0
    # a module being created has no local data: a cycle there is a Julia error (pl-modul.c's PL_warning)
    @test_throws ErrorException LK.addSuperModule_no_lock(ms, nothing, user, a, 'A')
end

@testset "'\$module_property'/2: the fields swipl cannot set, and what the kernel stores or refuses" begin
    gd, ld = _db()
    m = LK.lookupModule(gd, _tls(:wp_m))
    # line_count and file read the record (a loader fills them: MOD5b); 0 means none
    @test _call(gd, ld, "\$module_property", [_tls(:wp_m), _tlf("line_count", _tlv())])[1] ===
        :false
    @test _call(gd, ld, "\$module_property", [_tls(:wp_m), _tlf("file", _tlv())])[1] ===
        :false
    m.line_no = 7
    sf = LK.lookupSourceFile(gd, _tls(:wp_file), true)
    m.file = sf.index
    rc, ans = _call(gd, ld, "\$module_property", [_tls(:wp_m), _tlf("line_count", _tlv())])
    @test rc === :true && lk_eq(child(ans[2], 2), lk_gnd(_TL, 7))
    rc, ans = _call(gd, ld, "\$module_property", [_tls(:wp_m), _tlf("file", _tlv())])
    @test rc === :true && lk_eq(child(ans[2], 2), _tls(:wp_file))
    # exports(L): the public table in the order its procedures were added (swipl's order is its hash table's: D-0149 item 1)
    pb = LK.lookupProcedure(_tls(:b), 2, m)
    pa = LK.lookupProcedure(_tls(:a), 1, m)
    for (k, p) in (((sym_key(_tls(:b)), 2), pb), ((sym_key(_tls(:a)), 1), pa))
        m.public_[k] = p
        push!(m.public_order, k)
    end
    rc, ans = _call(gd, ld, "\$module_property", [_tls(:wp_m), _tlf("exports", _tlv())])
    nilt = LK.mk_nil(_TL)
    cons(h, t) = mk_expr(_TL, _TL[_tls("[|]"), h, t])
    slash(n, k) = _tlf("/", _tls(n), lk_gnd(_TL, k))
    @test rc === :true &&
        lk_eq(child(ans[2], 2), cons(slash(:b, 2), cons(slash(:a, 1), nilt)))
    # exports(L) with L bound: compares — the exact list unifies; a different order, and a longer list, do not
    rc, _ = _call(
        gd, ld, "\$module_property",
        [_tls(:wp_m), _tlf("exports", cons(slash(:b, 2), cons(slash(:a, 1), nilt)))]
    )
    @test rc === :true
    rc, _ = _call(
        gd, ld, "\$module_property",
        [_tls(:wp_m), _tlf("exports", cons(slash(:a, 1), cons(slash(:b, 2), nilt)))]
    )
    @test rc === :false
    rc, _ = _call(
        gd, ld, "\$module_property",
        [
            _tls(:wp_m),
            _tlf(
                "exports", cons(slash(:b, 2), cons(slash(:a, 1), cons(slash(:c, 3), nilt)))
            )
        ]
    )
    @test rc === :false
    # program_space(S) fails without a limit (as upstream) and answers a limit that is set (only a record can set one here)
    @test _call(
        gd, ld, "\$module_property", [_tls(:wp_m), _tlf("program_space", _tlv())]
    )[1] === :false
    m.code_limit = 5000
    rc, ans = _call(
        gd, ld, "\$module_property", [_tls(:wp_m), _tlf("program_space", _tlv())]
    )
    @test rc === :true && lk_eq(child(ans[2], 2), lk_gnd(_TL, 5000))
    # last_modified_generation reads the record
    m.last_modified = 42
    rc, ans = _call(
        gd, ld, "\$module_property", [_tls(:wp_m), _tlf("last_modified_generation", _tlv())]
    )
    @test rc === :true && lk_eq(child(ans[2], 2), lk_gnd(_TL, 42))
end

@testset "the kernel's own byte counts (D-0149 MQ3): clause words × 8 plus the clause records; the erased and the imported left out" begin
    gd, ld = _db()
    m = LK.lookupModule(gd, _tls(:bc_m))
    @test LK.module_code_size(m) == 0 && LK.sizeof_module(m) == 0
    pr = LK.lookupProcedure(_tls(:f), 1, m)
    cl = LK.compileClause(gd, ld, _tlf("f", lk_gnd(_TL, 1)), nothing, pr, m)
    LK.assertDefinition!(gd, pr.definition, cl::LK.Clause{_TL}, LK.CL_END)
    # f(1) compiles to `h_smallint 1 i_exitfact`: three words; a clause is sizeofClause(words) + SIZEOF_CREF_CLAUSE words
    # of 8 bytes. HAND-WRITTEN: this is the kernel's own accounting (swipl's is C structs); 8 * (8 + 3 + 3) = 112
    @test length(cl.codes) == 3 && LK.sizeofClause(3) == 11 && LK.SIZEOF_CREF_CLAUSE == 3
    @test LK.module_code_size(m) == 112
    # a procedure record adds 16 bytes (sizeof(struct procedure)) to the module's size, not to its program size
    @test LK.sizeof_module(m) == 112 + 16
    # … and '$module_property'/2 answers them: size(S) the first, program_size(P) the second
    rc, ans = _call(gd, ld, "\$module_property", [_tls(:bc_m), _tlf("size", _tlv())])
    @test rc === :true && lk_eq(child(ans[2], 2), lk_gnd(_TL, 128))
    rc, ans = _call(
        gd, ld, "\$module_property", [_tls(:bc_m), _tlf("program_size", _tlv())]
    )
    @test rc === :true && lk_eq(child(ans[2], 2), lk_gnd(_TL, 112))
    cl2 = LK.compileClause(gd, ld, _tlf("f", lk_gnd(_TL, 2)), nothing, pr, m)
    LK.assertDefinition!(gd, pr.definition, cl2::LK.Clause{_TL}, LK.CL_END)
    @test LK.module_code_size(m) == 224
    # a procedure of ANOTHER module that this module's table holds (an import) is that module's, not counted
    other = LK.lookupModule(gd, _tls(:bc_other))
    po = LK.lookupProcedure(_tls(:g), 1, other)
    clo = LK.compileClause(gd, ld, _tlf("g", lk_gnd(_TL, 1)), nothing, po, other)
    LK.assertDefinition!(gd, po.definition, clo::LK.Clause{_TL}, LK.CL_END)
    m.procedures[(sym_key(_tls(:g)), 1)] = po
    @test LK.module_code_size(m) == 224 && LK.module_code_size(other) == 112
    # the clause erased by retract stops counting at once (upstream subtracts at retract)
    cl.flags |= LK.CL_ERASED
    @test LK.module_code_size(m) == 112
end

@testset "what the kernel refuses by name: set_module(program_space(N)) with N > 0 (D-0149 MQ3)" begin
    # swipl stores the limit (and refuses one below the module's use: permission_error(limit, program_space, M), 'Used
    # exceeds limit'); the kernel does not keep the module's code size up to date, so it raises, naming the accounting. In a
    # database of its own: a refusal abandons the query.
    gd, ld = _db()
    err = try
        _call(
            gd,
            ld,
            "set_module",
            [_tlf(":", _tls(:ps_m), _tlf("program_space", lk_gnd(_TL, 1000)))]
        )
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError{_TL} && err.step == "R2" &&
        occursin("program_space", err.what)
    @test lk_eq(err.culprit, _tls(:ps_m)) && ld.query == 0
    # the limit 0 (no limit) is stored as upstream stores it
    gd, ld = _db()
    @test _call(
        gd,
        ld,
        "set_module",
        [_tlf(":", _tls(:ps_m), _tlf("program_space", lk_gnd(_TL, 0)))]
    )[1] === :true
    @test LK.isCurrentModule(gd.modules, _tls(:ps_m)).code_limit == 0
end

@testset "MODULE_parse: the source module while loading, else the typein module" begin
    gd, ld = _db()
    mk(n) = LK.lookupModule(gd, _tls(n)).index
    ld.modules_source = mk(:src_m)
    ld.modules_typein = mk(:typ_m)
    @test !LK.ReadingSource(ld) && LK.MODULE_parse(ld) == ld.modules_typein
    ld.read_source = LK.source_location{_TL}(_tls(:a_file), LK.IOPOS(0, 0, 3, 0, 0))   # a file and line 3
    @test LK.ReadingSource(ld) && LK.MODULE_parse(ld) == ld.modules_source
    ld.read_source = LK.source_location{_TL}(nothing, LK.IOPOS(0, 0, 3, 0, 0))         # a line, no file
    @test !LK.ReadingSource(ld)
    ld.read_source = LK.source_location{_TL}(_tls(:a_file), LK.IOPOS(0, 0, 0, 0, 0))   # a file, line 0
    @test !LK.ReadingSource(ld)
end
