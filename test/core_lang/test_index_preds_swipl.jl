# ORIGINAL: a LIVE differential of the index and source-file wrappers against swipl at the pin — `'$candidate_indexes'/3` and
# `'$set_candidate_indexes'/2` (pl-index.c, hash_info dicts: the answers are read back with dict_pairs/3), `'$set_source_files'/1`,
# `'$clause_from_source'/4`, `'$flush_predicate'/1` and `'$flushed_predicate'/1` (pl-srcfile.c), and `redefine_system_predicate/1`
# and `'$predefine_foreign'/1` (pl-comp.c); WRAPPERS-4. Rows ipc, ipsc, ipss, ipfl, ipdf_, ipcf, iprs, ippd:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test/db/test_source_file_swipl.jl's (`enc`oded answers; a clause
#     blob is `clref`). The directive rows `ipdir(Id, G)` record the answer of `G` DURING the load (`ip_dir/2`), rows ipdf_<id> read it back.
#     `@FILE@` in a goal is the program's path, `@L(marker)+k@` the line of the program's first line starting with `marker`, plus k.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20 at the pin, two byte-identical runs, lk-channel evidence/R2/wrappers3/
#     pins.txt); with `swipl` on PATH the live answers are compared with the pins too.
#   * The state changers of `'$set_source_files'/1` (rows ipss10-ipss16) come LAST. Foreign predicates have no pinned row (rows
#     ipk01-ipk09, kernel only, pin swipl cannot answer (process exits)); their expected lines are written by hand below.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these wrappers ride the term layer through the FLI (unify, get, strip module, dicts)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _IP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ips(x) = lk_sym(_IP, Symbol(x))

_ip_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes, a clause blob `clref`."
function _ip_enc(t::_IP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) && return blob_type(t) === :clause ? "clref" : "blob"
        return is_nil(t) ? "nil" : "a" * _ip_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ip_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ip_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ip_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/db/test_source_file_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _IP_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- blob(T, clause), !, write(clref).
enc(T, S, S) :- atom(T), blob(T, text), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- blob(T, _), !, write(blob).
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
function _ip_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _IP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: big/2 (40 clauses) and pair/3 (36) dynamic, p/q/v/one/zero/fa static, the directive rows of the flush predicates,
# the clauses cf/cg whose lines the `$clause_from_source` rows address (by marker, never by a hard-coded number)
const _IP_PROGRAM = raw"""
:- dynamic ip_dir/2, big/2, pair/3.
ipdir(Id, G) :- catch(( G -> R = yes ; R = no ), error(E, _), R = raised(E)), assertz(ip_dir(Id, R)).
ip_hs([], []).
ip_hs([D|Ds], [Tag-Ps|Rs]) :- dict_pairs(D, Tag, Ps), ip_hs(Ds, Rs).
ip_h(PI, Max, R) :- '$candidate_indexes'(PI, L, Max), ip_hs(L, R).
ip_cl(Cs, R) :- findall(H-B, ( member(C, Cs), clause(H, B, C) ), R).
ip_pr(H, R) :- findall(P, ( member(P, [defined, foreign, static, dynamic]), predicate_property(H, P) ), R).
:- forall(between(1, 40, I), assertz(big(I, x))).
:- forall(( between(0, 5, I), between(0, 5, J) ), assertz(pair(I, J, x))).
p(a, 1). p(b, 2). p(c, 3).
q(a, x). q(b, x). q(c, y). q(d, y). q(e, y).
v(_, 1). v(_, 2). v(_, 3). v(_, 4). v(_, 5).
one(a).
zero.
fa(f(1), a). fa(f(2), b). fa(f(3), c). fa(f(4), d). fa(f(5), e). fa(f(6), g).
ip_st(1).
:- dynamic ip_dy/1.
ip_dy(1).
:- ipdir(fp1, '$flush_predicate'(fs/1)).
:- ipdir(fl1, '$flushed_predicate'(fs(_))).
fs(a).
:- ipdir(fp2, '$flush_predicate'(fs/1)).
:- ipdir(fp3, '$flush_predicate'(fs(_))).
:- ipdir(fp4, '$flush_predicate'(nope/1)).
:- ipdir(fp5, '$flush_predicate'(user:fs/1)).
:- ipdir(fp6, '$flush_predicate'(_)).
:- ipdir(fp7, '$flush_predicate'(1)).
:- ipdir(fp8, '$flush_predicate'(foo:fs/1)).
:- ipdir(fp9, '$flush_predicate'(system:atom_length/2)).
:- ipdir(fp10, '$flush_predicate'(atom_length/2)).
:- ipdir(fl2, '$flushed_predicate'(fs(_))).
:- ipdir(fl3, '$flushed_predicate'(nope(_))).
:- ipdir(fl4, '$flushed_predicate'(user:fs(_))).
:- ipdir(fl5, '$flushed_predicate'(foo:fs(_))).
:- ipdir(fl6, '$flushed_predicate'(_)).
:- ipdir(fl7, '$flushed_predicate'(1)).
:- ipdir(fl8, '$flushed_predicate'(system:atom_length(_, _))).
:- ipdir(fl9, '$flushed_predicate'(atom_length(_, _))).
:- ipdir(fl10, '$flushed_predicate'(ip_dir(_, _))).
:- ipdir(fl11, '$flushed_predicate'(fs/1)).
:- ipdir(fl12, '$flushed_predicate'(later(_))).
:- ipdir(fp11, '$flush_predicate'(later/1)).
later(1).
:- ipdir(fl13, '$flushed_predicate'(later(_))).
:- dynamic dd/1.
:- ipdir(fl14, '$flushed_predicate'(dd(_))).
:- ipdir(fp12, '$flush_predicate'(dd/1)).
cf(a). cf(b).
cf(c).
cg(1) :-
    true.
cg(2).
"""

# ipc: '$candidate_indexes'/3; ipsc: '$set_candidate_indexes'/2; ipss: '$set_source_files'/1 (state changers last); ipfl: the flush
# predicates after the load; ipdf_: the answers they gave DURING the load; ipcf: '$clause_from_source'/4; iprs: redefine_system_predicate/1;
# ippd: '$predefine_foreign'/1. q/2's speedup is a Float32 (rows ipc12 and ipc36 carry 1.6666666269302368); an integer above int32 is a
# representation error (rows ipc44, ipc45, ipsc17: the FLI's int32 reading).
const _IP_CASES = [
    ("ipc01", raw"ip_h(p/2, 2, R)"),
    ("ipc02", raw"ip_h(p/2, 4, R)"),
    ("ipc03", raw"ip_h(big/2, 4, R)"),
    ("ipc04", raw"ip_h(user:big/2, 4, R)"),
    ("ipc05", raw"ip_h(ip_m:big/2, 4, R)"),
    ("ipc06", raw"ip_h(big/2, 1, R)"),
    ("ipc07", raw"ip_h(big/2, 3, R)"),
    ("ipc08", raw"ip_h(big/2, 0, R)"),
    ("ipc09", raw"ip_h(nope/2, 4, R)"),
    ("ipc10", raw"ip_h(foo, 4, R)"),
    ("ipc11", raw"ip_h(big, 4, R)"),
    ("ipc12", raw"ip_h(q/2, 4, R)"),
    ("ipc13", raw"ip_h(v/2, 4, R)"),
    ("ipc14", raw"ip_h(one/1, 4, R)"),
    ("ipc15", raw"ip_h(zero/0, 4, R)"),
    ("ipc16", raw"ip_h(zero, 4, R)"),
    ("ipc17", raw"ip_h(pair/3, 4, R)"),
    ("ipc18", raw"ip_h(pair/3, 1, R)"),
    ("ipc19", raw"ip_h(pair/3, 2, R)"),
    ("ipc20", raw"ip_h(fa/2, 4, R)"),
    ("ipc21", raw"ip_h(fa/2, 1, R)"),
    ("ipc22", raw"ip_h(pair/3, 100, R)"),
    ("ipc23", raw"ip_h(pair/3, 1000000, R)"),
    ("ipc24", raw"ip_h(f(x), 4, R)"),
    ("ipc25", raw"'$candidate_indexes'(big/2, [a|_], 4), R = yes"),
    ("ipc26", raw"'$candidate_indexes'(big/2, foo, 4), R = yes"),
    ("ipc27", raw"'$candidate_indexes'(big/2, [_,_|_], 4), R = yes"),
    ("ipc28", raw"'$candidate_indexes'(pair/3, [_,_], 3), R = yes"),
    ("ipc29", raw"'$candidate_indexes'(pair/3, [_,_,_], 3), R = yes"),
    ("ipc30", raw"'$candidate_indexes'(pair/3, [_,_,_,_], 3), R = yes"),
    ("ipc31", raw"'$candidate_indexes'(one/1, [], 3), R = yes"),
    ("ipc32", raw"'$candidate_indexes'(pair/3, [x], 3), R = yes"),
    ("ipc33", raw"dict_pairs(D, hash_info, [arguments-[1,2], list-false, ln_buckets-5, speedup-36.0]), '$candidate_indexes'(pair/3, [D|_], 3), R = yes"),
    ("ipc34", raw"dict_pairs(D, hash_info, [arguments-[2,1], list-false, ln_buckets-5, speedup-36.0]), '$candidate_indexes'(pair/3, [D|_], 3), R = yes"),
    ("ipc35", raw"'$candidate_indexes'(big/2, L, 4), L = [D], get_dict(speedup, D, S), R = S"),
    ("ipc36", raw"'$candidate_indexes'(q/2, L, 4), L = [D], get_dict(speedup, D, S), ( S =:= 5/3 -> R = exact ; R = widened )"),
    ("ipc37", raw"'$candidate_indexes'(big/2, L, -1), R = L"),
    ("ipc38", raw"'$candidate_indexes'(big/2, L, a), R = L"),
    ("ipc39", raw"'$candidate_indexes'(big/2, L, 1.5), R = L"),
    ("ipc40", raw"'$candidate_indexes'(big/2, L, _), R = L"),
    ("ipc41", raw"'$candidate_indexes'(_, L, 4), R = L"),
    ("ipc42", raw"'$candidate_indexes'(big/_, L, 4), R = L"),
    ("ipc43", raw"'$candidate_indexes'(1, L, 4), R = L"),
    ("ipc44", raw"'$candidate_indexes'(big/2, L, 2147483648), R = L"),
    ("ipc45", raw"'$candidate_indexes'(big/2, L, 99999999999999999999), R = L"),
    ("ipc46", raw"'$candidate_indexes'(big/2/3, L, 1), R = L"),
    ("ipc47", raw"'$candidate_indexes'(\"big\"/2, L, 1), R = L"),
    ("ipc48", raw"'$candidate_indexes'(big/2.0, L, 1), R = L"),
    ("ipc49", raw"'$candidate_indexes'(big/(-1), L, 1), R = L"),
    ("ipc50", raw"'$candidate_indexes'(_, L, a), R = L"),
    ("ipc51", raw"'$candidate_indexes'(1, L, -1), R = L"),
    ("ipc52", raw"'$candidate_indexes'(nope/2, L, a), R = L"),
    ("ipc53", raw"findall(x, '$candidate_indexes'(big/2, _, 4), L), R = L"),
    ("ipsc01", raw"'$set_candidate_indexes'(big/2, 4), R = yes"),
    ("ipsc02", raw"'$set_candidate_indexes'(big/2, 4), ip_h(big/2, 4, R)"),
    ("ipsc03", raw"'$set_candidate_indexes'(big/2, 0), R = yes"),
    ("ipsc04", raw"'$set_candidate_indexes'(p/2, 4), R = yes"),
    ("ipsc05", raw"'$set_candidate_indexes'(nope/2, 4), R = yes"),
    ("ipsc06", raw"'$set_candidate_indexes'(foo, 4), R = yes"),
    ("ipsc07", raw"'$set_candidate_indexes'(user:big/2, 4), R = yes"),
    ("ipsc08", raw"'$set_candidate_indexes'(ip_m:big/2, 4), R = yes"),
    ("ipsc09", raw"'$set_candidate_indexes'(big/2, a), R = yes"),
    ("ipsc10", raw"'$set_candidate_indexes'(big/2, 1.0), R = yes"),
    ("ipsc11", raw"'$set_candidate_indexes'(big/2, _), R = yes"),
    ("ipsc12", raw"'$set_candidate_indexes'(_, 3), R = yes"),
    ("ipsc13", raw"'$set_candidate_indexes'(big/a, 3), R = yes"),
    ("ipsc14", raw"'$set_candidate_indexes'(big/_, 3), R = yes"),
    ("ipsc15", raw"'$set_candidate_indexes'(big/(-1), 1), R = yes"),
    ("ipsc16", raw"'$set_candidate_indexes'(1, 1), R = yes"),
    ("ipsc17", raw"'$set_candidate_indexes'(big/2, 2147483648), R = yes"),
    ("ipsc18", raw"'$set_candidate_indexes'(pair/3, 100), R = yes"),
    ("ipsc19", raw"'$set_candidate_indexes'(pair/3, 1), ip_h(pair/3, 4, R)"),
    ("ipsc20", raw"'$set_candidate_indexes'(q/2, 1), ip_h(q/2, 4, R)"),
    ("ipsc21", raw"'$set_candidate_indexes'(zero, 3), R = yes"),
    ("ipsc22", raw"'$set_candidate_indexes'(one/1, 3), R = yes"),
    ("ipsc23", raw"'$set_candidate_indexes'(fa/2, 3), ip_h(fa/2, 4, R)"),
    ("ipsc24", raw"'$set_candidate_indexes'(_, a), R = yes"),
    ("ipsc25", raw"'$set_candidate_indexes'(pair/3, 4), pair(2, 3, Z), findall(J, pair(2, J, _), Js), R = Z-Js"),
    ("ipsc26", raw"'$set_candidate_indexes'(1, a), R = yes"),
    ("ipsc27", raw"findall(x, '$set_candidate_indexes'(big/2, 4), L), R = L"),
    ("ipss01", raw"'$set_source_files'(foo), R = yes"),
    ("ipss02", raw"'$set_source_files'(_), R = yes"),
    ("ipss03", raw"'$set_source_files'(1), R = yes"),
    ("ipss04", raw"'$set_source_files'(f(x)), R = yes"),
    ("ipss05", raw"'$set_source_files'(\"system\"), R = yes"),
    ("ipfl01", raw"'$flushed_predicate'(fs(_)), R = yes"),
    ("ipfl02", raw"'$flushed_predicate'(user:fs(_)), R = yes"),
    ("ipfl03", raw"'$flushed_predicate'(nomod:fs(_)), R = yes"),
    ("ipfl04", raw"'$flushed_predicate'(dd(_)), R = yes"),
    ("ipfl05", raw"'$flushed_predicate'(nope(_)), R = yes"),
    ("ipfl06", raw"'$flushed_predicate'(foo), R = yes"),
    ("ipfl07", raw"'$flushed_predicate'(atom_length(_, _)), R = yes"),
    ("ipfl08", raw"'$flushed_predicate'(system:atom_length(_, _)), R = yes"),
    ("ipfl09", raw"'$flushed_predicate'(_), R = yes"),
    ("ipfl10", raw"'$flushed_predicate'(1), R = yes"),
    ("ipfl11", raw"'$flushed_predicate'(fs/1), R = yes"),
    ("ipfl12", raw"'$flushed_predicate'(\"s\"), R = yes"),
    ("ipfl13", raw"'$flush_predicate'(fs/1), R = yes"),
    ("ipfl14", raw"'$flush_predicate'(fs(_)), R = yes"),
    ("ipfl15", raw"'$flush_predicate'(nope/1), R = yes"),
    ("ipfl16", raw"'$flush_predicate'(_), R = yes"),
    ("ipfl17", raw"'$flush_predicate'(1), R = yes"),
    ("ipfl18", raw"'$flush_predicate'(user:fs/1), R = yes"),
    ("ipfl19", raw"findall(x, '$flushed_predicate'(fs(_)), L), R = L"),
    ("ipdf_fp1", raw"ip_dir(fp1, R)"),
    ("ipdf_fl1", raw"ip_dir(fl1, R)"),
    ("ipdf_fp2", raw"ip_dir(fp2, R)"),
    ("ipdf_fp3", raw"ip_dir(fp3, R)"),
    ("ipdf_fp4", raw"ip_dir(fp4, R)"),
    ("ipdf_fp5", raw"ip_dir(fp5, R)"),
    ("ipdf_fp6", raw"ip_dir(fp6, R)"),
    ("ipdf_fp7", raw"ip_dir(fp7, R)"),
    ("ipdf_fp8", raw"ip_dir(fp8, R)"),
    ("ipdf_fp9", raw"ip_dir(fp9, R)"),
    ("ipdf_fp10", raw"ip_dir(fp10, R)"),
    ("ipdf_fl2", raw"ip_dir(fl2, R)"),
    ("ipdf_fl3", raw"ip_dir(fl3, R)"),
    ("ipdf_fl4", raw"ip_dir(fl4, R)"),
    ("ipdf_fl5", raw"ip_dir(fl5, R)"),
    ("ipdf_fl6", raw"ip_dir(fl6, R)"),
    ("ipdf_fl7", raw"ip_dir(fl7, R)"),
    ("ipdf_fl8", raw"ip_dir(fl8, R)"),
    ("ipdf_fl9", raw"ip_dir(fl9, R)"),
    ("ipdf_fl10", raw"ip_dir(fl10, R)"),
    ("ipdf_fl11", raw"ip_dir(fl11, R)"),
    ("ipdf_fl12", raw"ip_dir(fl12, R)"),
    ("ipdf_fp11", raw"ip_dir(fp11, R)"),
    ("ipdf_fl13", raw"ip_dir(fl13, R)"),
    ("ipdf_fl14", raw"ip_dir(fl14, R)"),
    ("ipdf_fp12", raw"ip_dir(fp12, R)"),
    ("ipcf01", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(a))@, Cs), ip_cl(Cs, R)"),
    ("ipcf02", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(c))@, Cs), ip_cl(Cs, R)"),
    ("ipcf03", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cg(1))@, Cs), ip_cl(Cs, R)"),
    ("ipcf04", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cg(1))+1@, Cs), ip_cl(Cs, R)"),
    ("ipcf05", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cg(2))@, Cs), ip_cl(Cs, R)"),
    ("ipcf06", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cg(2))+1@, Cs), length(Cs, R)"),
    ("ipcf07", raw"'$clause_from_source'('@FILE@', '@FILE@', 1000, Cs), length(Cs, R)"),
    ("ipcf08", raw"'$clause_from_source'('@FILE@', '@FILE@', 0, Cs), ip_cl(Cs, R)"),
    ("ipcf09", raw"'$clause_from_source'('@FILE@', '@FILE@', -1, Cs), ip_cl(Cs, R)"),
    ("ipcf10", raw"'$clause_from_source'('@FILE@', '@FILE@', 1, Cs), ip_cl(Cs, R)"),
    ("ipcf11", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(a))-1@, Cs), ip_cl(Cs, R)"),
    ("ipcf12", raw"'$clause_from_source'('@FILE@', '@FILE@', a, Cs), R = Cs"),
    ("ipcf13", raw"'$clause_from_source'(_, '@FILE@', 1, Cs), R = Cs"),
    ("ipcf14", raw"'$clause_from_source'('@FILE@', _, 1, Cs), R = Cs"),
    ("ipcf15", raw"'$clause_from_source'('@FILE@', '@FILE@', _, Cs), R = Cs"),
    ("ipcf16", raw"'$clause_from_source'('@FILE@', '/no/such', 1000, Cs), R = Cs"),
    ("ipcf17", raw"'$clause_from_source'('/no/such', '@FILE@', 1000, Cs), R = Cs"),
    ("ipcf18", raw"'$clause_from_source'(1, '@FILE@', 1000, Cs), R = Cs"),
    ("ipcf19", raw"'$clause_from_source'('@FILE@', 1, 1000, Cs), R = Cs"),
    ("ipcf20", raw"'$clause_from_source'('@FILE@', '@FILE@', 1000, [C]), clause(H, _, C), functor(H, N, A), R = N/A"),
    ("ipcf21", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(c))@, [_,_]), R = yes"),
    ("ipcf22", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(c))@, foo), R = yes"),
    ("ipcf23", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(c))@, []), R = yes"),
    ("ipcf24", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(a))@, [_,_]), R = yes"),
    ("ipcf25", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cf(a))@, []), R = yes"),
    ("ipcf26", raw"'$clause_from_source'('@FILE@', '@FILE@', 1.5, Cs), R = Cs"),
    ("ipcf27", raw"findall(x, '$clause_from_source'('@FILE@', '@FILE@', 1000, _), L), R = L"),
    ("ipcf28", raw"'$clause_from_source'('@FILE@', '@FILE@', @L(cg(1))@, [C]), ( clause(cg(1), true, C) -> R = body ; R = other )"),
    ("iprs01", raw"redefine_system_predicate(ip_zz(_)), R = yes"),
    ("iprs02", raw"redefine_system_predicate(user:ip_ww(_, _)), R = yes"),
    ("iprs03", raw"redefine_system_predicate(_), R = yes"),
    ("iprs04", raw"redefine_system_predicate(1), R = yes"),
    ("iprs05", raw"redefine_system_predicate(foo:_), R = yes"),
    ("iprs06", raw"redefine_system_predicate(foo:1), R = yes"),
    ("iprs07", raw"redefine_system_predicate(\"s\"), R = yes"),
    ("iprs08", raw"redefine_system_predicate(ip_z0), R = yes"),
    ("iprs09", raw"redefine_system_predicate(ip_f(1, 2, 3)), R = yes"),
    ("iprs10", raw"assertz(ip_m1:atom_length(a, b)), R = yes"),
    ("iprs11", raw"redefine_system_predicate(ip_m2:atom_length(_, _)), assertz(ip_m2:atom_length(c, d)), ip_m2:atom_length(c, X), R = X"),
    ("iprs12", raw"ip_m2:atom_length(abc, X), R = X"),
    ("iprs13", raw"redefine_system_predicate(ip_m3:atom_length(_, _)), ip_m3:atom_length(abc, X), R = X"),
    ("iprs14", raw"assertz(ip_m4:ip_foo(1)), redefine_system_predicate(ip_m4:ip_foo(_)), ip_m4:ip_foo(X), R = X"),
    ("iprs15", raw"redefine_system_predicate(ip_st(_)), ip_st(X), R = X"),
    ("iprs16", raw"redefine_system_predicate(ip_dy(_)), ip_dy(X), R = X"),
    ("iprs17", raw"predicate_property(ip_m2:atom_length(_, _), number_of_clauses(N)), R = N"),
    ("iprs18", raw"findall(x, redefine_system_predicate(ip_zz(_)), L), R = L"),
    ("ippd01", raw"'$predefine_foreign'(ip_pf/2), R = yes"),
    ("ippd02", raw"ip_pr(ip_pf(_, _), R)"),
    ("ippd03", raw"'$predefine_foreign'(user:ip_pg/1), R = yes"),
    ("ippd04", raw"'$predefine_foreign'(ip_pg/1), R = yes"),
    ("ippd05", raw"'$predefine_foreign'(_), R = yes"),
    ("ippd06", raw"'$predefine_foreign'(ip_pf/_), R = yes"),
    ("ippd07", raw"'$predefine_foreign'(_/2), R = yes"),
    ("ippd08", raw"'$predefine_foreign'(1), R = yes"),
    ("ippd09", raw"'$predefine_foreign'(ip_f0), R = yes"),
    ("ippd10", raw"'$predefine_foreign'(ip_x/a), R = yes"),
    ("ippd11", raw"'$predefine_foreign'(ip_x/(-1)), R = yes"),
    ("ippd12", raw"'$predefine_foreign'(atom_length/2), R = yes"),
    ("ippd13", raw"'$predefine_foreign'(ip_m6:atom_length/2), R = yes"),
    ("ippd14", raw"'$predefine_foreign'(ip_f1(a)), R = yes"),
    ("ippd15", raw"ip_pr(ip_pg(_), R)"),
    ("ippd16", raw"ip_pr(ip_f0, R)"),
    ("ippd17", raw"findall(x, '$predefine_foreign'(ip_pf/2), L), R = L"),
    ("ipss10", raw"'$source_file_property'('@FILE@', from_state, V), R = V"),
    ("ipss11", raw"'$set_source_files'(from_state), R = yes"),
    ("ipss12", raw"'$source_file_property'('@FILE@', from_state, V), R = V"),
    ("ipss13", raw"'$time_source_file'('@FILE@', _, Ty), R = Ty"),
    ("ipss14", raw"'$set_source_files'(system), R = yes"),
    ("ipss15", raw"'$time_source_file'('@FILE@', _, Ty), R = Ty"),
    ("ipss16", raw"findall(x, '$set_source_files'(system), L), R = L")
]

# KERNEL-ONLY rows: foreign predicates have no hash information, and a set on one is accepted; pin swipl cannot answer (process exits)
const _IP_KONLY = [
    ("ipk01", raw"ip_h(true/0, 4, R)"),
    ("ipk02", raw"ip_h(atom_length/2, 4, R)"),
    ("ipk03", raw"ip_h(atom_length/2, 0, R)"),
    ("ipk04", raw"ip_h(system:atom_length/2, 2, R)"),
    ("ipk05", raw"'$set_candidate_indexes'(atom_length/2, 0), R = yes"),
    ("ipk06", raw"'$set_candidate_indexes'(atom_length/2, 4), R = yes"),
    ("ipk07", raw"'$set_candidate_indexes'(true/0, 0), R = yes"),
    ("ipk08", raw"'$set_candidate_indexes'(true/0, 4), R = yes"),
    ("ipk09", raw"'$set_candidate_indexes'(big/2, -1), R = yes")
]

_ip_a(s) = "a" * _ip_codes(s)
_ip_c(n, args...) = "c" * _ip_codes(n) * "/$(length(args))(" * join(args, ",") * ")"
_ip_line(id, ans) = "t_$id " * _ip_c("t_$id", ans)
# the expected kernel lines of _IP_KONLY, in order
const _IP_KONLY_EXPECTED = [
    _ip_line("ipk01", "nil"),
    _ip_line("ipk02", "nil"),
    _ip_line("ipk03", "nil"),
    _ip_line("ipk04", "nil"),
    _ip_line("ipk05", _ip_a("yes")),
    _ip_line("ipk06", _ip_a("yes")),
    _ip_line("ipk07", _ip_a("yes")),
    _ip_line("ipk08", _ip_a("yes")),
    _ip_line(
        "ipk09",
        _ip_c(
            "raised",
            _ip_c("domain_error", _ip_a("not_less_than_zero"), "i-1")
        )
    )
]

# swipl's answer lines, PINNED: "ok" (the load) then one line per row (a failing row is its id alone)
const _IP_PINNED = [
    "ok",
    "t_ipc01 c[116,95,105,112,99,48,49]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f3.0),nil))))),nil))",
    "t_ipc02 c[116,95,105,112,99,48,50]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f3.0),nil))))),nil))",
    "t_ipc03 c[116,95,105,112,99,48,51]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipc04 c[116,95,105,112,99,48,52]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipc05 c[116,95,105,112,99,48,53]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipc06 c[116,95,105,112,99,48,54]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipc07 c[116,95,105,112,99,48,55]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipc08 c[116,95,105,112,99,48,56]/1(nil)",
    "t_ipc09 c[116,95,105,112,99,48,57]/1(nil)",
    "t_ipc10 c[116,95,105,112,99,49,48]/1(nil)",
    "t_ipc11 c[116,95,105,112,99,49,49]/1(nil)",
    "t_ipc12 c[116,95,105,112,99,49,50]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i1),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f1.6666666269302368),nil))))),nil))",
    "t_ipc13 c[116,95,105,112,99,49,51]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f5.0),nil))))),nil))",
    "t_ipc14 c[116,95,105,112,99,49,52]/1(nil)",
    "t_ipc15 c[116,95,105,112,99,49,53]/1(nil)",
    "t_ipc16 c[116,95,105,112,99,49,54]/1(nil)",
    "t_ipc17 c[116,95,105,112,99,49,55]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil))))",
    "t_ipc18 c[116,95,105,112,99,49,56]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),nil))",
    "t_ipc19 c[116,95,105,112,99,49,57]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil)))",
    "t_ipc20 c[116,95,105,112,99,50,48]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i4),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[116,114,117,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i0),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f1.0),nil))))),nil)))",
    "t_ipc21 c[116,95,105,112,99,50,49]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i4),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil))",
    "t_ipc22 c[116,95,105,112,99,50,50]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil))))",
    "t_ipc23 c[116,95,105,112,99,50,51]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil))))",
    "t_ipc24 c[116,95,105,112,99,50,52]/1(nil)",
    "t_ipc25",
    "t_ipc26",
    "t_ipc27",
    "t_ipc28",
    "t_ipc29 c[116,95,105,112,99,50,57]/1(a[121,101,115])",
    "t_ipc30",
    "t_ipc31 c[116,95,105,112,99,51,49]/1(a[121,101,115])",
    "t_ipc32",
    "t_ipc33 c[116,95,105,112,99,51,51]/1(a[121,101,115])",
    "t_ipc34",
    "t_ipc35 c[116,95,105,112,99,51,53]/1(f40.0)",
    "t_ipc36 c[116,95,105,112,99,51,54]/1(a[119,105,100,101,110,101,100])",
    "t_ipc37 c[116,95,105,112,99,51,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ipc38 c[116,95,105,112,99,51,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ipc39 c[116,95,105,112,99,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_ipc40 c[116,95,105,112,99,52,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipc41 c[116,95,105,112,99,52,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipc42 c[116,95,105,112,99,52,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipc43 c[116,95,105,112,99,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ipc44 c[116,95,105,112,99,52,52]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_ipc45 c[116,95,105,112,99,52,53]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_ipc46 c[116,95,105,112,99,52,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[47]/2(a[98,105,103],i2))))",
    "t_ipc47 c[116,95,105,112,99,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[98,105,103])))",
    "t_ipc48 c[116,95,105,112,99,52,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f2.0)))",
    "t_ipc49 c[116,95,105,112,99,52,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ipc50 c[116,95,105,112,99,53,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipc51 c[116,95,105,112,99,53,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ipc52 c[116,95,105,112,99,53,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ipc53 c[116,95,105,112,99,53,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_ipsc01 c[116,95,105,112,115,99,48,49]/1(a[121,101,115])",
    "t_ipsc02 c[116,95,105,112,115,99,48,50]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f40.0),nil))))),nil))",
    "t_ipsc03 c[116,95,105,112,115,99,48,51]/1(a[121,101,115])",
    "t_ipsc04 c[116,95,105,112,115,99,48,52]/1(a[121,101,115])",
    "t_ipsc05 c[116,95,105,112,115,99,48,53]/1(a[121,101,115])",
    "t_ipsc06 c[116,95,105,112,115,99,48,54]/1(a[121,101,115])",
    "t_ipsc07 c[116,95,105,112,115,99,48,55]/1(a[121,101,115])",
    "t_ipsc08 c[116,95,105,112,115,99,48,56]/1(a[121,101,115])",
    "t_ipsc09 c[116,95,105,112,115,99,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ipsc10 c[116,95,105,112,115,99,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_ipsc11 c[116,95,105,112,115,99,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipsc12 c[116,95,105,112,115,99,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipsc13 c[116,95,105,112,115,99,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ipsc14 c[116,95,105,112,115,99,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipsc15 c[116,95,105,112,115,99,49,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ipsc16 c[116,95,105,112,115,99,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ipsc17 c[116,95,105,112,115,99,49,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116])))",
    "t_ipsc18 c[116,95,105,112,115,99,49,56]/1(a[121,101,115])",
    "t_ipsc19 c[116,95,105,112,115,99,49,57]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i5),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f36.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i2),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),nil))))",
    "t_ipsc20 c[116,95,105,112,115,99,50,48]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i1),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f1.6666666269302368),nil))))),nil))",
    "t_ipsc21 c[116,95,105,112,115,99,50,49]/1(a[121,101,115])",
    "t_ipsc22 c[116,95,105,112,115,99,50,50]/1(a[121,101,115])",
    "t_ipsc23 c[116,95,105,112,115,99,50,51]/1(c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[102,97,108,115,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i4),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f6.0),nil))))),c[91,124,93]/2(c[45]/2(a[104,97,115,104,95,105,110,102,111],c[91,124,93]/2(c[45]/2(a[97,114,103,117,109,101,110,116,115],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[108,105,115,116],a[116,114,117,101]),c[91,124,93]/2(c[45]/2(a[108,110,95,98,117,99,107,101,116,115],i0),c[91,124,93]/2(c[45]/2(a[115,112,101,101,100,117,112],f1.0),nil))))),nil)))",
    "t_ipsc24 c[116,95,105,112,115,99,50,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipsc25 c[116,95,105,112,115,99,50,53]/1(c[45]/2(a[120],c[91,124,93]/2(i0,c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil))))))))",
    "t_ipsc26 c[116,95,105,112,115,99,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ipsc27 c[116,95,105,112,115,99,50,55]/1(c[91,124,93]/2(a[120],nil))",
    "t_ipss01 c[116,95,105,112,115,115,48,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,112,114,111,112,101,114,116,121],a[102,111,111])))",
    "t_ipss02 c[116,95,105,112,115,115,48,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipss03 c[116,95,105,112,115,115,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ipss04 c[116,95,105,112,115,115,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_ipss05 c[116,95,105,112,115,115,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[115,121,115,116,101,109])))",
    "t_ipfl01 c[116,95,105,112,102,108,48,49]/1(a[121,101,115])",
    "t_ipfl02 c[116,95,105,112,102,108,48,50]/1(a[121,101,115])",
    "t_ipfl03",
    "t_ipfl04 c[116,95,105,112,102,108,48,52]/1(a[121,101,115])",
    "t_ipfl05",
    "t_ipfl06",
    "t_ipfl07",
    "t_ipfl08 c[116,95,105,112,102,108,48,56]/1(a[121,101,115])",
    "t_ipfl09 c[116,95,105,112,102,108,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipfl10 c[116,95,105,112,102,108,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_ipfl11",
    "t_ipfl12 c[116,95,105,112,102,108,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],s[115])))",
    "t_ipfl13 c[116,95,105,112,102,108,49,51]/1(a[121,101,115])",
    "t_ipfl14 c[116,95,105,112,102,108,49,52]/1(a[121,101,115])",
    "t_ipfl15 c[116,95,105,112,102,108,49,53]/1(a[121,101,115])",
    "t_ipfl16 c[116,95,105,112,102,108,49,54]/1(a[121,101,115])",
    "t_ipfl17 c[116,95,105,112,102,108,49,55]/1(a[121,101,115])",
    "t_ipfl18 c[116,95,105,112,102,108,49,56]/1(a[121,101,115])",
    "t_ipfl19 c[116,95,105,112,102,108,49,57]/1(c[91,124,93]/2(a[120],nil))",
    "t_ipdf_fp1 c[116,95,105,112,100,102,95,102,112,49]/1(a[110,111])",
    "t_ipdf_fl1 c[116,95,105,112,100,102,95,102,108,49]/1(a[110,111])",
    "t_ipdf_fp2 c[116,95,105,112,100,102,95,102,112,50]/1(a[121,101,115])",
    "t_ipdf_fp3 c[116,95,105,112,100,102,95,102,112,51]/1(a[121,101,115])",
    "t_ipdf_fp4 c[116,95,105,112,100,102,95,102,112,52]/1(a[110,111])",
    "t_ipdf_fp5 c[116,95,105,112,100,102,95,102,112,53]/1(a[121,101,115])",
    "t_ipdf_fp6 c[116,95,105,112,100,102,95,102,112,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipdf_fp7 c[116,95,105,112,100,102,95,102,112,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ipdf_fp8 c[116,95,105,112,100,102,95,102,112,56]/1(a[110,111])",
    "t_ipdf_fp9 c[116,95,105,112,100,102,95,102,112,57]/1(a[121,101,115])",
    "t_ipdf_fp10 c[116,95,105,112,100,102,95,102,112,49,48]/1(a[110,111])",
    "t_ipdf_fl2 c[116,95,105,112,100,102,95,102,108,50]/1(a[121,101,115])",
    "t_ipdf_fl3 c[116,95,105,112,100,102,95,102,108,51]/1(a[110,111])",
    "t_ipdf_fl4 c[116,95,105,112,100,102,95,102,108,52]/1(a[121,101,115])",
    "t_ipdf_fl5 c[116,95,105,112,100,102,95,102,108,53]/1(a[110,111])",
    "t_ipdf_fl6 c[116,95,105,112,100,102,95,102,108,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipdf_fl7 c[116,95,105,112,100,102,95,102,108,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_ipdf_fl8 c[116,95,105,112,100,102,95,102,108,56]/1(a[121,101,115])",
    "t_ipdf_fl9 c[116,95,105,112,100,102,95,102,108,57]/1(a[110,111])",
    "t_ipdf_fl10 c[116,95,105,112,100,102,95,102,108,49,48]/1(a[121,101,115])",
    "t_ipdf_fl11 c[116,95,105,112,100,102,95,102,108,49,49]/1(a[110,111])",
    "t_ipdf_fl12 c[116,95,105,112,100,102,95,102,108,49,50]/1(a[110,111])",
    "t_ipdf_fp11 c[116,95,105,112,100,102,95,102,112,49,49]/1(a[110,111])",
    "t_ipdf_fl13 c[116,95,105,112,100,102,95,102,108,49,51]/1(a[121,101,115])",
    "t_ipdf_fl14 c[116,95,105,112,100,102,95,102,108,49,52]/1(a[121,101,115])",
    "t_ipdf_fp12 c[116,95,105,112,100,102,95,102,112,49,50]/1(a[121,101,115])",
    "t_ipcf01 c[116,95,105,112,99,102,48,49]/1(c[91,124,93]/2(c[45]/2(c[99,102]/1(a[97]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[99,102]/1(a[98]),a[116,114,117,101]),nil)))",
    "t_ipcf02 c[116,95,105,112,99,102,48,50]/1(c[91,124,93]/2(c[45]/2(c[99,102]/1(a[99]),a[116,114,117,101]),nil))",
    "t_ipcf03 c[116,95,105,112,99,102,48,51]/1(c[91,124,93]/2(c[45]/2(c[99,103]/1(i1),a[116,114,117,101]),nil))",
    "t_ipcf04 c[116,95,105,112,99,102,48,52]/1(c[91,124,93]/2(c[45]/2(c[99,103]/1(i1),a[116,114,117,101]),nil))",
    "t_ipcf05 c[116,95,105,112,99,102,48,53]/1(c[91,124,93]/2(c[45]/2(c[99,103]/1(i2),a[116,114,117,101]),nil))",
    "t_ipcf06 c[116,95,105,112,99,102,48,54]/1(i1)",
    "t_ipcf07 c[116,95,105,112,99,102,48,55]/1(i1)",
    "t_ipcf08",
    "t_ipcf09",
    "t_ipcf10",
    "t_ipcf11 c[116,95,105,112,99,102,49,49]/1(c[91,124,93]/2(c[45]/2(c[108,97,116,101,114]/1(i1),a[116,114,117,101]),nil))",
    "t_ipcf12 c[116,95,105,112,99,102,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ipcf13 c[116,95,105,112,99,102,49,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipcf14 c[116,95,105,112,99,102,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipcf15 c[116,95,105,112,99,102,49,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ipcf16",
    "t_ipcf17",
    "t_ipcf18 c[116,95,105,112,99,102,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ipcf19 c[116,95,105,112,99,102,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ipcf20 c[116,95,105,112,99,102,50,48]/1(c[47]/2(a[116,95,105,112,115,115,49,54],i1))",
    "t_ipcf21",
    "t_ipcf22",
    "t_ipcf23 c[116,95,105,112,99,102,50,51]/1(a[121,101,115])",
    "t_ipcf24 c[116,95,105,112,99,102,50,52]/1(a[121,101,115])",
    "t_ipcf25 c[116,95,105,112,99,102,50,53]/1(a[121,101,115])",
    "t_ipcf26 c[116,95,105,112,99,102,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_ipcf27 c[116,95,105,112,99,102,50,55]/1(c[91,124,93]/2(a[120],nil))",
    "t_ipcf28 c[116,95,105,112,99,102,50,56]/1(a[98,111,100,121])",
    "t_iprs01 c[116,95,105,112,114,115,48,49]/1(a[121,101,115])",
    "t_iprs02 c[116,95,105,112,114,115,48,50]/1(a[121,101,115])",
    "t_iprs03 c[116,95,105,112,114,115,48,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_iprs04 c[116,95,105,112,114,115,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_iprs05 c[116,95,105,112,114,115,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_iprs06 c[116,95,105,112,114,115,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_iprs07 c[116,95,105,112,114,115,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],s[115])))",
    "t_iprs08 c[116,95,105,112,114,115,48,56]/1(a[121,101,115])",
    "t_iprs09 c[116,95,105,112,114,115,48,57]/1(a[121,101,115])",
    "t_iprs10 c[116,95,105,112,114,115,49,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,95,108,101,110,103,116,104],i2))))",
    "t_iprs11 c[116,95,105,112,114,115,49,49]/1(i1)",
    "t_iprs12",
    "t_iprs13 c[116,95,105,112,114,115,49,51]/1(i3)",
    "t_iprs14 c[116,95,105,112,114,115,49,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[105,112,95,109,52],c[47]/2(a[105,112,95,102,111,111],i1)))))",
    "t_iprs15 c[116,95,105,112,114,115,49,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[105,112,95,115,116],i1))))",
    "t_iprs16 c[116,95,105,112,114,115,49,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[105,112,95,100,121],i1))))",
    "t_iprs17 c[116,95,105,112,114,115,49,55]/1(i1)",
    "t_iprs18 c[116,95,105,112,114,115,49,56]/1(c[91,124,93]/2(a[120],nil))",
    "t_ippd01 c[116,95,105,112,112,100,48,49]/1(a[121,101,115])",
    "t_ippd02 c[116,95,105,112,112,100,48,50]/1(c[91,124,93]/2(a[100,101,102,105,110,101,100],c[91,124,93]/2(a[102,111,114,101,105,103,110],c[91,124,93]/2(a[115,116,97,116,105,99],nil))))",
    "t_ippd03 c[116,95,105,112,112,100,48,51]/1(a[121,101,115])",
    "t_ippd04 c[116,95,105,112,112,100,48,52]/1(a[121,101,115])",
    "t_ippd05 c[116,95,105,112,112,100,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ippd06 c[116,95,105,112,112,100,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ippd07 c[116,95,105,112,112,100,48,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ippd08 c[116,95,105,112,112,100,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[112,114,101,100,105,99,97,116,101,95,105,110,100,105,99,97,116,111,114],i1)))",
    "t_ippd09 c[116,95,105,112,112,100,48,57]/1(a[121,101,115])",
    "t_ippd10 c[116,95,105,112,112,100,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ippd11 c[116,95,105,112,112,100,49,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ippd12 c[116,95,105,112,112,100,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,95,108,101,110,103,116,104],i2))))",
    "t_ippd13 c[116,95,105,112,112,100,49,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97,116,111,109,95,108,101,110,103,116,104],i2))))",
    "t_ippd14 c[116,95,105,112,112,100,49,52]/1(a[121,101,115])",
    "t_ippd15 c[116,95,105,112,112,100,49,53]/1(c[91,124,93]/2(a[100,101,102,105,110,101,100],c[91,124,93]/2(a[102,111,114,101,105,103,110],c[91,124,93]/2(a[115,116,97,116,105,99],nil))))",
    "t_ippd16 c[116,95,105,112,112,100,49,54]/1(c[91,124,93]/2(a[100,101,102,105,110,101,100],c[91,124,93]/2(a[102,111,114,101,105,103,110],c[91,124,93]/2(a[115,116,97,116,105,99],nil))))",
    "t_ippd17 c[116,95,105,112,112,100,49,55]/1(c[91,124,93]/2(a[120],nil))",
    "t_ipss10 c[116,95,105,112,115,115,49,48]/1(a[102,97,108,115,101])",
    "t_ipss11 c[116,95,105,112,115,115,49,49]/1(a[121,101,115])",
    "t_ipss12 c[116,95,105,112,115,115,49,50]/1(a[116,114,117,101])",
    "t_ipss13 c[116,95,105,112,115,115,49,51]/1(a[117,115,101,114])",
    "t_ipss14 c[116,95,105,112,115,115,49,52]/1(a[121,101,115])",
    "t_ipss15 c[116,95,105,112,115,115,49,53]/1(a[115,121,115,116,101,109])",
    "t_ipss16 c[116,95,105,112,115,115,49,54]/1(c[91,124,93]/2(a[120],nil))"
]

"The program with `@L(marker)+k@` replaced by that line number; `@FILE@` is replaced by `path` in the cases' goals."
function _ip_lines_of(prog::String, g::String)::String
    plines = split(prog, '\n')
    return replace(
        g,
        r"@L\((.*?)\)([+-]\d+)?@" => function (m)
            mm = match(r"@L\((.*?)\)([+-]\d+)?@", m)
            v = findfirst(l -> startswith(l, mm.captures[1]), plines)
            v === nothing && error("no marker $(mm.captures[1])")
            return string(v + (mm.captures[2] === nothing ? 0 : parse(Int, mm.captures[2])))
        end
    )
end

function _ip_file(cases, path::String)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in cases]
    text =
        _IP_PROGRAM * join([
            "t_$(id)(R) :- catch(($(replace(_ip_lines_of(_IP_PROGRAM, g), "@FILE@" => path))), error(SsuE, _), R = raised(SsuE)).\n"
            for (id, g) in cases
        ])
    write(path, text)
    return path, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _ip_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_IP}()
    ld = LK.PL_local_data{_IP}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ip_enc(ball::_IP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_ips(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_IP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ip_enc(mk_expr(_IP, _IP[_ips(name), lk_answers(ld, (a:a)...)...]))
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

@testset "the index and source-file wrappers as swipl's (ipc, ipsc, ipss, ipfl, ipdf_, ipcf, iprs, ippd)" begin
    path, names = _ip_file(
        vcat(_IP_CASES, _IP_KONLY), joinpath(mktempdir(), "indexpreds.pl")
    )
    kl = _ip_kernel(path, names)
    @test length(kl) == length(_IP_PINNED) + length(_IP_KONLY)
    for (k, p) in zip(kl, _IP_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    for (k, p) in zip(kl[(length(_IP_PINNED) + 1):end], _IP_KONLY_EXPECTED)
        k == p || println(stderr, "  ours  ", k, "\n  want  ", p)
        @test k == p
    end
end

@testset "the index-predicate rows are not vacuous" begin
    @test _IP_PINNED[1] == "ok"
    @test length(_IP_PINNED) == length(_IP_CASES) + 1
    @test length(_IP_CASES) == 200
    fam(re) = [id for (id, _) in _IP_CASES if occursin(re, id)]
    for re in (r"^ipc\d", r"^ipsc", r"^ipss", r"^ipfl", r"^ipdf_", r"^ipcf", r"^iprs", r"^ippd")
        ids = fam(re)
        answered = [l for l in _IP_PINNED if any(id -> startswith(l, "t_$id "), ids)]
        failed = [l for l in _IP_PINNED if any(id -> l == "t_$id", ids)]
        @test !isempty(ids)
        @test !isempty(answered)                                           # some rows answer
        re in (r"^ipc\d", r"^ipfl", r"^ipcf", r"^iprs") && @test !isempty(failed)  # some rows fail
    end
    for kindname in (
        "domain_error", "type_error", "instantiation_error", "representation_error",
        "permission_error", "existence_error"
    )
        @test any(l -> occursin(_ip_codes(kindname), l), _IP_PINNED)     # every error kind has a row
    end
    @test any(l -> occursin(_ip_codes("hash_info"), l), _IP_PINNED)      # the answer dicts are read back
    @test any(l -> startswith(l, "t_ipcf06 ") && endswith(l, "(i1)"), _IP_PINNED)  # one clause on the line
    @test length(_IP_KONLY) == length(_IP_KONLY_EXPECTED)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_IP_PINNED) == length(_IP_CASES) + 1
    if swipl === nothing
        @info "INDEX-PREDICATE LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ip_file(_IP_CASES, joinpath(mktempdir(), "indexpreds.pl"))
        @test _ip_swipl_lines(f, names) == _IP_PINNED
    end
end
