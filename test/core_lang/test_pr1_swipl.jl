# ORIGINAL: a LIVE differential of PR1's abolish/1,2, current_predicate/1, `$c_current_predicate`/2 and
# `$get_predicate_attribute`/3 (pl-proc.c) against swipl at the pin — rows pr01-pr127 against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(E, _), R = raised(E))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, two byte-identical runs, evidence/PR1/gen_rows.py
#     --fill: the generator reads THIS file's program, cases and driver, the one extractor of both sides); with `swipl`
#     on PATH the live answers are compared with the pins too.
#   * Rows over unordered answers (enumeration of modules or predicates) compare msort-ed lists, filtered by a name.
#   * Each row works on predicates of its own (the database is shared by the rows).
#   * UNVERIFIED on the kernel: gate decides — nothing was compiled when these rows were written: every kernel answer;
#     `size` and `last_modified_generation` are the kernel's own counts (checked by type, pr99/pr100), `indexed` raises
#     NotPortedError (left out of the rows).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — abolish and the predicate enumerations ride the term layer through PL_unify_* and PL_get_* only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _PR = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_prs(x) = lk_sym(_PR, Symbol(x))


_pr_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _pr_enc(t::_PR, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _pr_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _pr_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _pr_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_pr_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _PR_DRIVER = raw"""
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
_pr_swipl_lines(path::String, names::Vector{String}) = _pr_swipl_lines([path], names)
function _pr_swipl_lines(paths::Vector{String}, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        files = if length(paths) == 1
            "'$(paths[1])'"
        else
            "[" * join(["'$p'" for p in paths], ",") * "]"
        end
        write(
            f,
            _PR_DRIVER * ":- initialization((fz_run($files, [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: static predicates the rows abolish or read (one per row), helpers `pr_try/2` and `pr_cp/2`
const _PR_PROGRAM = raw"""
pr_s1(1).
pr_s1(2).
pr_s2(1).
pr_s3(1).
pr_s4(1).
pr_s5(1).
pr_s6(1).
pr_s7(1).
pr_t(X, Y) :- pr_s1(X), pr_s1(Y).
pr_u.
pr_try(G, R) :- catch(( G -> R = yes ; R = no ), error(E, _), R = err(E)).
pr_cp(S, L) :- findall(S, current_predicate(S), L0), msort(L0, L).
pr_ld1(1).
pr_ld1(2).
:- abolish(pr_ld1/1).
:- asserta((pr_ld1(X) :- X = 3)).
pr_ld2(a).
:- abolish(pr_ld2/1).
pr_ld3(1).
:- abolish(pr_ld3/1).
pr_ld3(2).
pr_ld4(1).
pr_ld4(2).
:- abolish(pr_ld4, 1).
:- asserta(pr_ld4(7)), assertz(pr_ld4(8)).
:- assertz(prws:pr_wq(1)).
:- '$import'(prws:pr_wq/1, weak).
pr_wq(9).
mrq:qs(1).
mrq:qs(2).
"""

# pr01-pr08 abolish/1 on a dynamic and on a static predicate, abolish/2
# pr09-pr15 abolish/1,2: the unknown predicate, the system predicate, the module-qualified forms
# pr16-pr25 abolish/1,2: bad arguments
# pr26-pr28 abolish/1 under the iso flag, and an abolished predicate's flags
# pr29-pr31 abolish/1 of an imported link
# pr32-pr33 garbage_collect_clauses
# pr34-pr42 current_predicate/1: Name/Arity, an unbound arity or name, a name that has no predicate
# pr43-pr52 current_predicate/1: modules and the super chain
# pr53-pr62 current_predicate/1: //, bad specifications
# pr63-pr72 $c_current_predicate/2
# pr73-pr105 $get_predicate_attribute/3
# pr106-pr117 abolish after a retract, of rules, of a meta-predicate; the cut of an enumeration; the arity limit; the
# enumeration and the counts of an abolished predicate; size, last_modified_generation, primary_index
# pr118-pr124 abolish/1,2 as a DIRECTIVE of the file that defined the predicate (boot/load.pl:47-49: abolish, then asserta), a
#             weak import overruled by a definition (overruleImportedProcedure -> abolishProcedure)
# pr125-pr126 a module redeclared whose static predicate has clauses (declareModule -> abolishProcedure)
# pr127 the rule count of an abolished predicate that held a rule and two facts (removeClausesPredicate): 0 after a fact is added, 1 after
#       a rule is added (num_visible_clauses walks a dynamic predicate's clauses once the stored count is above 0, so a wrong stored
#       count shows only as 0 where a rule is visible)
const _PR_CASES = [
    (
        "pr01",
        raw"assertz(pr_a1(1)), assertz(pr_a1(2)), abolish(pr_a1/1), pr_try(pr_a1(_), R)"
    ),
    (
        "pr02",
        raw"assertz(pr_a2(1)), abolish(pr_a2/1), pr_try(current_predicate(pr_a2/1), R)"
    ),
    ("pr03", raw"abolish(pr_s7/1), pr_try(pr_s7(_), R)"),
    ("pr04", raw"abolish(pr_s2, 1), pr_try(current_predicate(pr_s2/1), R)"),
    ("pr05", raw"assertz(pr_a3(1)), abolish(pr_a3, 1), pr_try(pr_a3(_), R)"),
    (
        "pr06",
        raw"assertz(pr_a4(1)), abolish(pr_a4/1), assertz(pr_a4(2)), findall(X, pr_a4(X), R)"
    ),
    (
        "pr07",
        raw"assertz(pr_a5(1)), abolish(pr_a5/1), '$get_predicate_attribute'(pr_a5(_), dynamic, V), R = V"
    ),
    (
        "pr08",
        raw"assertz(pr_a6(1)), '$get_predicate_attribute'(pr_a6(_), dynamic, V0), abolish(pr_a6/1), pr_try('$get_predicate_attribute'(pr_a6(_), dynamic, _), R0), R = V0-R0"
    ),
    ("pr09", raw"abolish(pr_nosuch/3), R = ok"),
    ("pr10", raw"abolish(pr_nosuch2, 3), R = ok"),
    ("pr11", raw"abolish(atom_length/2)"),
    ("pr12", raw"abolish(atom_length, 2)"),
    (
        "pr13",
        raw"assertz(pr_m1:pr_q(1)), abolish(pr_m1:pr_q/1), pr_try(current_predicate(pr_m1:pr_q/1), R)"
    ),
    (
        "pr14",
        raw"assertz(pr_m1:pr_q2(1)), abolish(pr_m1:pr_q2, 1), pr_try(pr_m1:pr_q2(_), R)"
    ),
    (
        "pr15",
        raw"assertz(pr_m1:pr_q3(1)), abolish(pr_m1:pr_q3/1), pr_try(current_predicate(pr_q3/1), R)"
    ),
    ("pr16", raw"abolish(foo)"),
    ("pr17", raw"abolish(pr_x/(-1))"),
    ("pr18", raw"abolish(pr_x, -1)"),
    ("pr19", raw"abolish(_)"),
    ("pr20", raw"abolish(_/1)"),
    ("pr21", raw"abolish(pr_x/a)"),
    ("pr22", raw"abolish(1/1)"),
    ("pr23", raw"abolish(pr_x/_)"),
    ("pr24", raw"abolish(pr_x, 99999999999)"),
    ("pr25", raw"abolish(pr_x, 1.5)"),
    (
        "pr26",
        raw"catch(( set_prolog_flag(iso, true), abolish(pr_s3/1) ), error(E, _), true), set_prolog_flag(iso, false), R = E"
    ),
    (
        "pr27",
        raw"assertz(pr_a7(1)), catch(( set_prolog_flag(iso, true), abolish(pr_a7/1), E = ok ), error(E, _), true), set_prolog_flag(iso, false), R = E"
    ),
    ("pr28", raw"pr_try(pr_s3(_), R)"),
    (
        "pr29",
        raw"assertz(pr_m2:pr_i(1)), pr_m3:import(pr_m2:pr_i/1), abolish(pr_m3:pr_i/1), pr_try(pr_m3:pr_i(_), R)"
    ),
    (
        "pr30",
        raw"assertz(pr_m2:pr_i2(1)), pr_m3:import(pr_m2:pr_i2/1), abolish(pr_m3:pr_i2/1), findall(X, pr_m2:pr_i2(X), R)"
    ),
    (
        "pr31",
        raw"assertz(pr_m2:pr_i3(1)), pr_m3:import(pr_m2:pr_i3/1), abolish(pr_m3:pr_i3/1), pr_try('$get_predicate_attribute'(pr_m3:pr_i3(_), imported, _), R)"
    ),
    (
        "pr32",
        raw"assertz(pr_g(1)), assertz(pr_g(2)), assertz(pr_g(3)), retract(pr_g(2)), garbage_collect_clauses, findall(X, pr_g(X), R)"
    ),
    ("pr33", raw"garbage_collect_clauses, R = ok"),
    ("pr34", raw"current_predicate(pr_s4/1), R = yes"),
    ("pr35", raw"current_predicate(pr_s4/2), R = yes"),
    ("pr36", raw"findall(A, current_predicate(pr_t/A), R)"),
    ("pr37", raw"findall(N, ( current_predicate(N/2), N == pr_t ), R)"),
    ("pr38", raw"current_predicate(pr_nosuch/_), R = yes"),
    ("pr39", raw"current_predicate(pr_u/0), R = yes"),
    ("pr40", raw"pr_cp(pr_s5/_, R)"),
    ("pr41", raw"catch(pr_und, _, true), pr_try(current_predicate(pr_und/0), R)"),
    ("pr42", raw"current_predicate(atom_length/2), R = yes"),
    ("pr43", raw"assertz(pr_m5:pr_zz(1)), current_predicate(pr_m5:pr_zz/1), R = yes"),
    ("pr44", raw"assertz(pr_m5:pr_zz2(1)), current_predicate(pr_nomod:pr_zz2/1), R = yes"),
    (
        "pr45",
        raw"assertz(pr_m6:pr_e(1)), assertz(pr_e(1)), findall(M, ( current_predicate(M:pr_e/1), ( M == user ; M == pr_m1 ; M == pr_m2 ; M == pr_m3 ; M == pr_m5 ; M == pr_m6 ) ), Ms), msort(Ms, R)"
    ),
    (
        "pr46",
        raw"assertz(pr_m6:pr_e2(1)), assertz(pr_m6:pr_e2(2)), assertz(pr_e2(1)), findall(M-A, current_predicate(M:pr_e2/A), Ms), msort(Ms, R)"
    ),
    (
        "pr47",
        raw"assertz(pr_m6:pr_e3(1)), findall(M, current_predicate(M:pr_e3/_), Ms), msort(Ms, R)"
    ),
    ("pr48", raw"pr_m7:current_predicate(pr_s6/1), R = yes"),
    ("pr49", raw"findall(A, pr_m7:current_predicate(pr_s6/A), R)"),
    ("pr50", raw"assertz(pr_m8:pr_s6(1)), findall(A, pr_m8:current_predicate(pr_s6/A), R)"),
    (
        "pr51",
        raw"assertz(pr_m8:pr_lc(1)), findall(N, ( pr_m8:current_predicate(N/1), N == pr_lc ), R)"
    ),
    ("pr52", raw"pr_try(current_predicate(pr_m6:pr_s6/1), R)"),
    ("pr53", raw"assertz(pr_dc(a, _, _)), current_predicate(pr_dc//1), R = yes"),
    ("pr54", raw"assertz(pr_dc2(a, _, _)), findall(A, current_predicate(pr_dc2//A), R)"),
    ("pr55", raw"assertz(pr_dc3(a, _)), pr_try(current_predicate(pr_dc3//1), R)"),
    ("pr56", raw"current_predicate(foo)"),
    ("pr57", raw"current_predicate(1/2)"),
    ("pr58", raw"current_predicate(pr_s1/a)"),
    ("pr59", raw"current_predicate(pr_s1/(-1))"),
    ("pr60", raw"pr_try(current_predicate(_), R)"),
    ("pr61", raw"current_predicate(pr_s1/1/2)"),
    (
        "pr62",
        raw"findall(M, ( current_predicate(M:pr_s1/1), ( M == user ; M == pr_m1 ; M == pr_m2 ; M == pr_m3 ; M == pr_m5 ; M == pr_m6 ; M == pr_m7 ; M == pr_m8 ) ), Ms), msort(Ms, R)"
    ),
    ("pr63", raw"'$c_current_predicate'(pr_s1, user:pr_s1(_)), R = yes"),
    ("pr64", raw"'$c_current_predicate'(N, user:pr_t(_, _)), R = N"),
    ("pr65", raw"findall(F, '$c_current_predicate'(pr_t, user:F), R)"),
    ("pr66", raw"'$c_current_predicate'(_, pr_nomod2:pr_s1(_)), R = yes"),
    ("pr67", raw"'$c_current_predicate'(a, user:pr_s1(_)), R = yes"),
    ("pr68", raw"'$c_current_predicate'(1, user:_), R = yes"),
    ("pr69", raw"findall(N, '$c_current_predicate'(N, user:pr_s1(_)), R)"),
    ("pr70", raw"findall(N-F, ( '$c_current_predicate'(N, user:F), N == pr_t ), R)"),
    ("pr71", raw"'$c_current_predicate'(_, user:1), R = yes"),
    (
        "pr72",
        raw"assertz(pr_m10:pr_cc(1)), findall(N, ( '$c_current_predicate'(N, pr_m10:_), N == pr_cc ), R)"
    ),
    ("pr73", raw"'$get_predicate_attribute'(pr_s1(_), defined, V), R = V"),
    ("pr74", raw"'$get_predicate_attribute'(pr_t(_, _), number_of_rules, V), R = V"),
    ("pr75", raw"'$get_predicate_attribute'(pr_t(_, _), number_of_clauses, V), R = V"),
    ("pr76", raw"'$get_predicate_attribute'(pr_s1(_), number_of_clauses, V), R = V"),
    ("pr77", raw"'$get_predicate_attribute'(pr_s1(_), number_of_rules, V), R = V"),
    ("pr78", raw"'$get_predicate_attribute'(pr_s1(_), dynamic, V), R = V"),
    (
        "pr79",
        raw"assertz(pr_ga1(1)), assertz(pr_ga1(2)), retract(pr_ga1(1)), '$get_predicate_attribute'(pr_ga1(_), number_of_clauses, V), R = V"
    ),
    (
        "pr80",
        raw"assertz(pr_m2:pr_gi(1)), pr_m3:import(pr_m2:pr_gi/1), '$get_predicate_attribute'(pr_m3:pr_gi(_), imported, V), R = V"
    ),
    ("pr81", raw"pr_try('$get_predicate_attribute'(pr_s1(_), imported, _), R)"),
    ("pr82", raw"'$get_predicate_attribute'(pr_m9:pr_s1(_), imported, V), R = V"),
    (
        "pr83",
        raw"assertz(pr_m11:pr_ex(1)), pr_m11:export(pr_ex/1), '$get_predicate_attribute'(pr_m11:pr_ex(_), exported, V), R = V"
    ),
    ("pr84", raw"'$get_predicate_attribute'(pr_s1(_), exported, V), R = V"),
    ("pr85", raw"'$get_predicate_attribute'(system:atom_length(_, _), foreign, V), R = V"),
    ("pr86", raw"'$get_predicate_attribute'(pr_s1(_), foreign, V), R = V"),
    (
        "pr87",
        raw"pr_try('$get_predicate_attribute'(system:atom_length(_, _), number_of_clauses, _), R)"
    ),
    ("pr88", raw"'$get_predicate_attribute'(pr_s1(_), line_count, V), R = V"),
    (
        "pr89",
        raw"'$get_predicate_attribute'(system:atom_length(_, _), line_count, V), R = V"
    ),
    (
        "pr90",
        raw"assertz(pr_mp(_, _, _, _, _, _, _, _)), meta_predicate(pr_mp(0, :, ^, //, +, -, ?, 2)), '$get_predicate_attribute'(pr_mp(_, _, _, _, _, _, _, _), meta_predicate, V), R = V"
    ),
    ("pr91", raw"pr_try('$get_predicate_attribute'(pr_s1(_), meta_predicate, _), R)"),
    (
        "pr92",
        raw"'$get_predicate_attribute'(system:findall(_, _, _), meta_predicate, V), R = V"
    ),
    ("pr93", raw"pr_try('$get_predicate_attribute'(pr_s1(_), tabled, _), R)"),
    ("pr94", raw"pr_try('$get_predicate_attribute'(pr_s1(_), nosuchkey, _), R)"),
    ("pr95", raw"'$get_predicate_attribute'(pr_s1(_), 1, _)"),
    ("pr96", raw"'$get_predicate_attribute'(pr_s1(_), _, _)"),
    ("pr97", raw"pr_try('$get_predicate_attribute'(pr_nosuch(_), defined, _), R)"),
    ("pr98", raw"pr_try('$get_predicate_attribute'(_, defined, _), R)"),
    ("pr99", raw"'$get_predicate_attribute'(pr_s1(_), size, V), integer(V), V > 0, R = ok"),
    (
        "pr100",
        raw"'$get_predicate_attribute'(pr_s1(_), last_modified_generation, V), integer(V), R = ok"
    ),
    ("pr101", raw"'$get_predicate_attribute'(system:atom_length(_, _), locked, V), R = V"),
    ("pr102", raw"'$get_predicate_attribute'(pr_s1(_), transparent, V), R = V"),
    (
        "pr103",
        raw"assertz(pr_pi(1)), assertz(pr_pi(2)), assertz(pr_pi(3)), pr_pi(2), pr_try('$get_predicate_attribute'(pr_pi(_), primary_index, _), R)"
    ),
    (
        "pr104",
        raw"assertz(pr_ga2(1)), '$get_predicate_attribute'(pr_ga2(_), defined, V), R = V"
    ),
    ("pr105", raw"pr_u, '$get_predicate_attribute'(pr_u, number_of_clauses, V), R = V"),
    (
        "pr106",
        raw"assertz(pr_a8(1)), assertz(pr_a8(2)), retract(pr_a8(1)), abolish(pr_a8/1), assertz(pr_a8(3)), '$get_predicate_attribute'(pr_a8(_), number_of_clauses, V), findall(X, pr_a8(X), L), R = V-L"
    ),
    (
        "pr107",
        raw"assertz((pr_a9(X) :- X > 0)), assertz(pr_a9(1)), abolish(pr_a9/1), assertz(pr_a9(5)), '$get_predicate_attribute'(pr_a9(_), number_of_rules, V), R = V"
    ),
    (
        "pr108",
        raw"assertz(pr_a10(_, _)), meta_predicate(pr_a10(0, ?)), abolish(pr_a10/2), assertz(pr_a10(1, 2)), pr_try('$get_predicate_attribute'(pr_a10(_, _), meta_predicate, _), R)"
    ),
    ("pr109", raw"pr_try(current_predicate(_:pr_s1/1), R)"),
    ("pr110", raw"pr_try('$c_current_predicate'(_, user:_), R)"),
    ("pr111", raw"abolish(pr_x, 1000000)"),
    (
        "pr112",
        raw"assertz(pr_a11(1)), abolish(pr_a11/1), findall(A, current_predicate(pr_a11/A), R)"
    ),
    ("pr113", raw"pr_try('$get_predicate_attribute'(pr_s7(_), number_of_clauses, _), R)"),
    ("pr114", raw"pr_try('$get_predicate_attribute'(pr_s7(_), number_of_rules, _), R)"),
    (
        "pr115",
        raw"assertz(pr_sz(1)), '$get_predicate_attribute'(pr_sz(_), size, S1), assertz(pr_sz(2)), assertz(pr_sz(3)), '$get_predicate_attribute'(pr_sz(_), size, S3), S3 > S1, R = ok"
    ),
    (
        "pr116",
        raw"pr_try('$get_predicate_attribute'(system:atom_length(_, _), last_modified_generation, _), R)"
    ),
    (
        "pr117",
        raw"assertz(pr_pi2(1, a)), assertz(pr_pi2(2, b)), assertz(pr_pi2(3, c)), pr_pi2(2, _), '$get_predicate_attribute'(pr_pi2(_, _), primary_index, V), R = V"
    ),
    ("pr118", raw"findall(X, pr_ld1(X), R)"),
    ("pr119", raw"pr_try('$get_predicate_attribute'(pr_ld1(_), dynamic, _), R)"),
    ("pr120", raw"pr_try(pr_ld2(_), R)"),
    ("pr121", raw"findall(X, pr_ld3(X), R)"),
    ("pr122", raw"findall(X, pr_ld4(X), R)"),
    ("pr123", raw"findall(X, pr_wq(X), R)"),
    ("pr124", raw"pr_try('$get_predicate_attribute'(pr_wq(_), imported, _), R)"),
    (
        "pr125",
        raw"'$declare_module'(mrq, user, user, '/pr/q.pl', 1, false), '$set_source_module'(user), pr_try(mrq:qs(_), R)"
    ),
    ("pr126", raw"pr_try('$get_predicate_attribute'(mrq:qs(_), defined, _), R)"),
    (
        "pr127",
        raw"assertz((pr_a12(X) :- X > 0)), assertz(pr_a12(1)), assertz(pr_a12(2)), abolish(pr_a12/1), assertz(pr_a12(5)), '$get_predicate_attribute'(pr_a12(_), number_of_rules, V0), assertz((pr_a12(Y) :- Y > 1)), '$get_predicate_attribute'(pr_a12(_), number_of_rules, V1), R = [V0, V1]"
    )
]

# the driver's whole output, one line per case after `ok`, filled by evidence/PR1/gen_rows.py --fill from swipl 10.1.19
const _PR_PINNED = [
    "ok",
    "t_pr01 c[116,95,112,114,48,49]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[112,114,95,97,49],i1))))",
    "t_pr02 c[116,95,112,114,48,50]/1(a[110,111])",
    "t_pr03 c[116,95,112,114,48,51]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[112,114,95,115,55],i1))))",
    "t_pr04 c[116,95,112,114,48,52]/1(a[110,111])",
    "t_pr05 c[116,95,112,114,48,53]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[112,114,95,97,51],i1))))",
    "t_pr06 c[116,95,112,114,48,54]/1(c[91,124,93]/2(i2,nil))",
    "t_pr07 c[116,95,112,114,48,55]/1(i0)",
    "t_pr08 c[116,95,112,114,48,56]/1(c[45]/2(i1,a[121,101,115]))",
    "t_pr09 c[116,95,112,114,48,57]/1(a[111,107])",
    "t_pr10 c[116,95,112,114,49,48]/1(a[111,107])",
    "t_pr11 c[116,95,112,114,49,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,95,108,101,110,103,116,104],i2))))",
    "t_pr12 c[116,95,112,114,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,95,108,101,110,103,116,104],i2))))",
    "t_pr13 c[116,95,112,114,49,51]/1(a[110,111])",
    "t_pr14 c[116,95,112,114,49,52]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[112,114,95,109,49],c[47]/2(a[112,114,95,113,50],i1)))))",
    "t_pr15 c[116,95,112,114,49,53]/1(a[110,111])",
    "t_pr16 c[116,95,112,114,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],a[102,111,111])))",
    "t_pr17 c[116,95,112,114,49,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_pr18 c[116,95,112,114,49,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_pr19 c[116,95,112,114,49,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pr20 c[116,95,112,114,50,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pr21 c[116,95,112,114,50,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_pr22 c[116,95,112,114,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_pr23 c[116,95,112,114,50,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pr24 c[116,95,112,114,50,52]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_pr25 c[116,95,112,114,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_pr26 c[116,95,112,114,50,54]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[112,114,95,115,51],i1)))",
    "t_pr27 c[116,95,112,114,50,55]/1(a[111,107])",
    "t_pr28 c[116,95,112,114,50,56]/1(a[121,101,115])",
    "t_pr29 c[116,95,112,114,50,57]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[112,114,95,109,51],c[47]/2(a[112,114,95,105],i1)))))",
    "t_pr30 c[116,95,112,114,51,48]/1(c[91,124,93]/2(i1,nil))",
    "t_pr31 c[116,95,112,114,51,49]/1(a[110,111])",
    "t_pr32 c[116,95,112,114,51,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)))",
    "t_pr33 c[116,95,112,114,51,51]/1(a[111,107])",
    "t_pr34 c[116,95,112,114,51,52]/1(a[121,101,115])",
    "t_pr35",
    "t_pr36 c[116,95,112,114,51,54]/1(c[91,124,93]/2(i2,nil))",
    "t_pr37 c[116,95,112,114,51,55]/1(c[91,124,93]/2(a[112,114,95,116],nil))",
    "t_pr38",
    "t_pr39 c[116,95,112,114,51,57]/1(a[121,101,115])",
    "t_pr40 c[116,95,112,114,52,48]/1(c[91,124,93]/2(c[47]/2(a[112,114,95,115,53],i1),nil))",
    "t_pr41 c[116,95,112,114,52,49]/1(a[110,111])",
    "t_pr42 c[116,95,112,114,52,50]/1(a[121,101,115])",
    "t_pr43 c[116,95,112,114,52,51]/1(a[121,101,115])",
    "t_pr44",
    "t_pr45 c[116,95,112,114,52,53]/1(c[91,124,93]/2(a[112,114,95,109,49],c[91,124,93]/2(a[112,114,95,109,50],c[91,124,93]/2(a[112,114,95,109,51],c[91,124,93]/2(a[112,114,95,109,53],c[91,124,93]/2(a[112,114,95,109,54],c[91,124,93]/2(a[117,115,101,114],nil)))))))",
    "t_pr46 c[116,95,112,114,52,54]/1(c[91,124,93]/2(c[45]/2(a[112,114,95,109,54],i1),c[91,124,93]/2(c[45]/2(a[117,115,101,114],i1),nil)))",
    "t_pr47 c[116,95,112,114,52,55]/1(c[91,124,93]/2(a[112,114,95,109,54],nil))",
    "t_pr48 c[116,95,112,114,52,56]/1(a[121,101,115])",
    "t_pr49 c[116,95,112,114,52,57]/1(c[91,124,93]/2(i1,nil))",
    "t_pr50 c[116,95,112,114,53,48]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i1,nil)))",
    "t_pr51 c[116,95,112,114,53,49]/1(c[91,124,93]/2(a[112,114,95,108,99],nil))",
    "t_pr52 c[116,95,112,114,53,50]/1(a[121,101,115])",
    "t_pr53 c[116,95,112,114,53,51]/1(a[121,101,115])",
    "t_pr54 c[116,95,112,114,53,52]/1(c[91,124,93]/2(i1,nil))",
    "t_pr55 c[116,95,112,114,53,53]/1(a[110,111])",
    "t_pr56 c[116,95,112,114,53,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],a[102,111,111])))",
    "t_pr57 c[116,95,112,114,53,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],c[47]/2(i1,i2))))",
    "t_pr58 c[116,95,112,114,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],c[47]/2(a[112,114,95,115,49],a[97]))))",
    "t_pr59 c[116,95,112,114,53,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_pr60 c[116,95,112,114,54,48]/1(a[121,101,115])",
    "t_pr61 c[116,95,112,114,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],c[47]/2(c[47]/2(a[112,114,95,115,49],i1),i2))))",
    "t_pr62 c[116,95,112,114,54,50]/1(c[91,124,93]/2(a[112,114,95,109,49],c[91,124,93]/2(a[112,114,95,109,50],c[91,124,93]/2(a[112,114,95,109,51],c[91,124,93]/2(a[112,114,95,109,53],c[91,124,93]/2(a[112,114,95,109,54],c[91,124,93]/2(a[112,114,95,109,55],c[91,124,93]/2(a[112,114,95,109,56],c[91,124,93]/2(a[117,115,101,114],nil)))))))))",
    "t_pr63 c[116,95,112,114,54,51]/1(a[121,101,115])",
    "t_pr64 c[116,95,112,114,54,52]/1(a[112,114,95,116])",
    "t_pr65 c[116,95,112,114,54,53]/1(c[91,124,93]/2(c[112,114,95,116]/2(V0,V1),nil))",
    "t_pr66",
    "t_pr67",
    "t_pr68",
    "t_pr69 c[116,95,112,114,54,57]/1(c[91,124,93]/2(a[112,114,95,115,49],nil))",
    "t_pr70 c[116,95,112,114,55,48]/1(c[91,124,93]/2(c[45]/2(a[112,114,95,116],c[112,114,95,116]/2(V0,V1)),nil))",
    "t_pr71",
    "t_pr72 c[116,95,112,114,55,50]/1(c[91,124,93]/2(a[112,114,95,99,99],nil))",
    "t_pr73 c[116,95,112,114,55,51]/1(i1)",
    "t_pr74 c[116,95,112,114,55,52]/1(i1)",
    "t_pr75 c[116,95,112,114,55,53]/1(i1)",
    "t_pr76 c[116,95,112,114,55,54]/1(i2)",
    "t_pr77 c[116,95,112,114,55,55]/1(i0)",
    "t_pr78 c[116,95,112,114,55,56]/1(i0)",
    "t_pr79 c[116,95,112,114,55,57]/1(i1)",
    "t_pr80 c[116,95,112,114,56,48]/1(a[112,114,95,109,50])",
    "t_pr81 c[116,95,112,114,56,49]/1(a[110,111])",
    "t_pr82 c[116,95,112,114,56,50]/1(a[117,115,101,114])",
    "t_pr83 c[116,95,112,114,56,51]/1(i1)",
    "t_pr84 c[116,95,112,114,56,52]/1(i0)",
    "t_pr85 c[116,95,112,114,56,53]/1(i1)",
    "t_pr86 c[116,95,112,114,56,54]/1(i0)",
    "t_pr87 c[116,95,112,114,56,55]/1(a[110,111])",
    "t_pr88 c[116,95,112,114,56,56]/1(i1)",
    "t_pr89",
    "t_pr90 c[116,95,112,114,57,48]/1(c[112,114,95,109,112]/8(i0,a[58],a[94],a[47,47],a[43],a[45],a[63],i2))",
    "t_pr91 c[116,95,112,114,57,49]/1(a[110,111])",
    "t_pr92 c[116,95,112,114,57,50]/1(c[102,105,110,100,97,108,108]/3(a[63],i0,a[45]))",
    "t_pr93 c[116,95,112,114,57,51]/1(a[110,111])",
    "t_pr94 c[116,95,112,114,57,52]/1(c[101,114,114]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,112,114,111,112,101,114,116,121],a[110,111,115,117,99,104,107,101,121])))",
    "t_pr95 c[116,95,112,114,57,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_pr96 c[116,95,112,114,57,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pr97 c[116,95,112,114,57,55]/1(a[110,111])",
    "t_pr98 c[116,95,112,114,57,56]/1(a[110,111])",
    "t_pr99 c[116,95,112,114,57,57]/1(a[111,107])",
    "t_pr100 c[116,95,112,114,49,48,48]/1(a[111,107])",
    "t_pr101 c[116,95,112,114,49,48,49]/1(i1)",
    "t_pr102 c[116,95,112,114,49,48,50]/1(i0)",
    "t_pr103 c[116,95,112,114,49,48,51]/1(a[121,101,115])",
    "t_pr104 c[116,95,112,114,49,48,52]/1(i1)",
    "t_pr105 c[116,95,112,114,49,48,53]/1(i1)",
    "t_pr106 c[116,95,112,114,49,48,54]/1(c[45]/2(i1,c[91,124,93]/2(i3,nil)))",
    "t_pr107 c[116,95,112,114,49,48,55]/1(i0)",
    "t_pr108 c[116,95,112,114,49,48,56]/1(a[110,111])",
    "t_pr109 c[116,95,112,114,49,48,57]/1(a[121,101,115])",
    "t_pr110 c[116,95,112,114,49,49,48]/1(a[121,101,115])",
    "t_pr111 c[116,95,112,114,49,49,49]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[109,97,120,95,112,114,111,99,101,100,117,114,101,95,97,114,105,116,121])))",
    "t_pr112 c[116,95,112,114,49,49,50]/1(nil)",
    "t_pr113 c[116,95,112,114,49,49,51]/1(a[110,111])",
    "t_pr114 c[116,95,112,114,49,49,52]/1(a[110,111])",
    "t_pr115 c[116,95,112,114,49,49,53]/1(a[111,107])",
    "t_pr116 c[116,95,112,114,49,49,54]/1(a[110,111])",
    "t_pr117 c[116,95,112,114,49,49,55]/1(i1)",
    "t_pr118 c[116,95,112,114,49,49,56]/1(c[91,124,93]/2(i3,nil))",
    "t_pr119 c[116,95,112,114,49,49,57]/1(a[121,101,115])",
    "t_pr120 c[116,95,112,114,49,50,48]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[112,114,95,108,100,50],i1))))",
    "t_pr121 c[116,95,112,114,49,50,49]/1(c[91,124,93]/2(i2,nil))",
    "t_pr122 c[116,95,112,114,49,50,50]/1(c[91,124,93]/2(i7,c[91,124,93]/2(i8,nil)))",
    "t_pr123 c[116,95,112,114,49,50,51]/1(c[91,124,93]/2(i9,nil))",
    "t_pr124 c[116,95,112,114,49,50,52]/1(a[110,111])",
    "t_pr125 c[116,95,112,114,49,50,53]/1(c[101,114,114]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,114,113],c[47]/2(a[113,115],i1)))))",
    "t_pr126 c[116,95,112,114,49,50,54]/1(a[121,101,115])",
    "t_pr127 c[116,95,112,114,49,50,55]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i1,nil)))"
]

function _pr_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _PR_CASES]
    text =
        _PR_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(E, _), R = raised(E)).\n" for
            (id, g) in _PR_CASES
        ])
    f = joinpath(mktempdir(), "pr1.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
_pr_kernel(path::String, names::Vector{String}) = _pr_kernel([path], names)
function _pr_kernel(paths::Vector{String}, names::Vector{String})
    gd = LK.PL_global_data{_PR}()
    ld = LK.PL_local_data{_PR}(gd)
    st, ball = :ok, nothing
    for path in paths                                    # a file after another, as `consult/1` of a list does
        st, ball = LK.load_file!(gd, ld, path)
        st === :ok || break
    end
    out = [st === :ok ? "ok" : "exc " * _pr_enc(ball::_PR)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_prs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_PR, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _pr_enc(mk_expr(_PR, _PR[_prs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "abolish/1,2, current_predicate/1, '\$c_current_predicate'/2, '\$get_predicate_attribute'/3 as swipl's (pr01-pr127)" begin
    f, names = _pr_file()
    kl, _, ld = _pr_kernel(f, names)
    @test length(kl) == length(_PR_PINNED)
    @test LK.live_states(ld) == 0                  # no enumeration state of a cut `once/1` is left (pr60, pr109, pr110); UNVERIFIED on the kernel
    for (k, p) in zip(kl, _PR_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

# PR1b: a predicate another file defined, redefined by a second file (redefineProcedure -> abolishProcedure): the
# `Redefined static procedure` warning, the first file's clauses gone; a dynamic one made static; a thread-local one refused.
const _PR_RD_A = raw"""
pr_rd1(1).
pr_rd1(2).
pr_rd2(1).
:- assertz(pr_rd3(1)).
:- '$set_predicate_attribute'(pr_tl(_), thread_local, true).
pr_tl(1).
"""
const _PR_RD_B = raw"""
pr_rd1(9).
pr_rd2(5).
pr_rd2(6).
pr_rd3(2).
pr_tl(2).
t_rd1(R) :- findall(X, pr_rd1(X), R).
t_rd2(R) :- findall(X, pr_rd2(X), R).
t_rd3(R) :- findall(X, pr_rd3(X), R).
t_rd4(R) :- '$get_predicate_attribute'(pr_rd1(_), number_of_clauses, R).
t_rd5(R) :- ( '$get_predicate_attribute'(pr_rd3(_), dynamic, _) -> R = yes ; R = no ).
t_rd6(R) :- findall(X, pr_tl(X), R).
t_rd7(R) :- ( '$get_predicate_attribute'(pr_tl(_), thread_local, _) -> R = yes ; R = no ).
"""
const _PR_RD_NAMES = ["t_rd1", "t_rd2", "t_rd3", "t_rd4", "t_rd5", "t_rd6", "t_rd7"]
const _PR_RD_PINNED = [
    "ok",
    "t_rd1 c[116,95,114,100,49]/1(c[91,124,93]/2(i9,nil))",
    "t_rd2 c[116,95,114,100,50]/1(c[91,124,93]/2(i5,c[91,124,93]/2(i6,nil)))",
    "t_rd3 c[116,95,114,100,51]/1(c[91,124,93]/2(i2,nil))",
    "t_rd4 c[116,95,114,100,52]/1(i1)",
    "t_rd5 c[116,95,114,100,53]/1(a[121,101,115])",
    "t_rd6 c[116,95,114,100,54]/1(c[91,124,93]/2(i1,nil))",
    "t_rd7 c[116,95,114,100,55]/1(a[121,101,115])"
]

"Write the two files of the PR1b rows into a fresh directory."
function _pr_rd_files()::Vector{String}
    d = mktempdir()
    fa = joinpath(d, "pr1_rd_a.pl")
    fb = joinpath(d, "pr1_rd_b.pl")
    write(fa, _PR_RD_A)
    write(fb, _PR_RD_B)
    return [fa, fb]
end

@testset "redefinition from a second file as swipl's (PR1b)" begin
    kl, _, _ = _pr_kernel(_pr_rd_files(), _PR_RD_NAMES)
    @test length(kl) == length(_PR_RD_PINNED)
    for (k, p) in zip(kl, _PR_RD_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    @test _PR_RD_PINNED[1] == "ok"                       # both files loaded
    @test any(l -> startswith(l, "t_rd4 ") && endswith(l, "(i1)"), _PR_RD_PINNED)  # the first file's clauses are gone
end

@testset "the PR1 rows are not vacuous (pr01-pr127)" begin
    # the program loaded (`ok`); both sides of each guard are non-empty: raised rows, rows with no answer, enumerations
    raised = "c[114,97,105,115,101,100]/1("
    cons = "c[91,124,93]/2("
    @test _PR_PINNED[1] == "ok"
    @test count(l -> occursin(raised, l), _PR_PINNED) >= 14
    for id in ("pr118", "pr121", "pr122", "pr123")        # the directive-abolish and weak-import rows answer with a list
        @test any(l -> startswith(l, "t_$id ") && occursin(cons, l), _PR_PINNED)
    end
    for id in ("pr120", "pr125")                          # an abolished predicate is unknown: existence_error
        @test any(
            l -> startswith(l, "t_$id ") && occursin("c[101,114,114]/1(", l), _PR_PINNED
        )
    end
    for id in (
        "pr11",
        "pr12",
        "pr16",
        "pr17",
        "pr18",
        "pr19",
        "pr20",
        "pr21",
        "pr22",
        "pr23",
        "pr24",
        "pr25",
        "pr111",
        "pr56",
        "pr57",
        "pr58",
        "pr59",
        "pr61",
        "pr95",
        "pr96"
    )
        @test any(l -> startswith(l, "t_$id ") && occursin(raised, l), _PR_PINNED)   # the bad argument was raised
    end
    noans = ("pr35", "pr38", "pr44", "pr66", "pr67", "pr68", "pr71", "pr89")
    for id in noans
        @test any(l -> l == "t_$id", _PR_PINNED)                                      # no answer: the row failed
    end
    @test count(l -> startswith(l, "t_pr") && !occursin(' ', l), _PR_PINNED) ==
        length(noans)
    for id in (
        "pr36",
        "pr40",
        "pr45",
        "pr46",
        "pr47",
        "pr49",
        "pr50",
        "pr51",
        "pr62",
        "pr65",
        "pr69",
        "pr70",
        "pr72"
    )
        @test any(l -> startswith(l, "t_$id ") && occursin(cons, l), _PR_PINNED)      # an enumeration with answers
    end
    @test any(
        l ->
            startswith(l, "t_pr01 ") &&
            occursin("c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(", l),
        _PR_PINNED
    )  # an abolished predicate is gone
    @test any(l -> startswith(l, "t_pr06 ") && occursin("i2", l), _PR_PINNED)         # and can be defined again
    for id in (
        "pr73",
        "pr74",
        "pr75",
        "pr76",
        "pr79",
        "pr80",
        "pr83",
        "pr85",
        "pr90",
        "pr92",
        "pr99",
        "pr100",
        "pr106",
        "pr107",
        "pr108",
        "pr115",
        "pr127",
        "pr117"
    )
        @test any(l -> startswith(l, "t_$id "), _PR_PINNED)                           # an attribute was read
    end
end

# White-box (PR1-B1, PR1-A1): what no row reads. `removeClausesPredicate!` counts an erased clause once (`erased_clauses`;
# a clause retracted before the abolish is not counted again); `deleteIndexes!` of an abolished STATIC predicate marks every
# slot of its index array dead (`isnew` false), and drops the array of a predicate that is new or dynamic.
@testset "abolish: an erased clause is counted once; a static predicate's index slots are dead (PR1-B1, PR1-A1)" begin
    d = mktempdir()
    f1 = joinpath(d, "wb1.pl")
    write(
        f1,
        ":- assertz(wb_w(1)), assertz(wb_w(2)), retract(wb_w(1)), abolish(wb_w/1).\n" *
        join(["wb_i($k, c$k).\n" for k in 1:12]) * ":- wb_i(_, c12), wb_i(_, c3).\n"
    )
    gd = LK.PL_global_data{_PR}()
    ld = LK.PL_local_data{_PR}(gd)
    st, _ = LK.load_file!(gd, ld, f1)
    @test st === :ok
    proc(n, a) = LK.isCurrentProcedure(sym_key(_prs(n)), a, LK.MODULE_user(gd))
    pw = proc("wb_w", 1)
    @test pw !== nothing
    clw = pw.definition.impl_clauses
    @test clw.erased_clauses == 2                  # B1: the clause retracted before is counted once, not twice
    @test clw.number_of_clauses == 0
    gens = UInt64[]
    c = clw.first_clause
    while c !== nothing
        push!(gens, c.clause.generation_erased)
        c = c.next
    end
    @test length(gens) == 2 && gens[1] < gens[2]   # the retract erased clause 1 first; the abolish erased only clause 2
    pix = proc("wb_i", 2)
    @test pix !== nothing
    cli = pix.definition.impl_clauses
    @test cli.clause_indexes !== nothing           # the directive built an index on the second argument (non-vacuity)
    @test any(ci -> ci !== nothing, cli.clause_indexes)
    f2 = joinpath(d, "wb2.pl")
    write(f2, ":- abolish(wb_i/2).\n")
    st, _ = LK.load_file!(gd, ld, f2)
    @test st === :ok
    cip = cli.clause_indexes
    @test cip !== nothing                          # A1: kept as an array of dead slots, not dropped
    @test !isempty(cip) && all(ci -> ci === nothing, cip)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_PR_PINNED) == length(_PR_CASES) + 1
    if swipl === nothing
        @info "PR1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _pr_file()
        @test _pr_swipl_lines(f, names) == _PR_PINNED
        @test _pr_swipl_lines(_pr_rd_files(), _PR_RD_NAMES) == _PR_RD_PINNED
    end
end
