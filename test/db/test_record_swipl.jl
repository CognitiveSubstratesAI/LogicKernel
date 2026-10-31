# ORIGINAL: R2's D2 gate — the recorded database (pl-rec.c recorda/recordz/recorded/current_key, instance/2 and erase/1 of a record, pl-dbref.c record_blob) against swipl 10.1.19; upstream tests it through Prolog (tests/db/test_dbref.pl, unit recorded), which needs the loader and plunit (R2).
# test/db/test_record_swipl.jl — D2's gate (audit D-0230 item 2, D-0252 item 2, design evidence/r2/design/flags_rest.md §4 D11, H12):
#   * ROWS, as a program (test/core_lang/test_at_body_swipl.jl's pattern): each case is a predicate `t_<id>(R)` run IN ORDER in one
#     database, each starting with `rset` (every record erased) and wrapped in `catch(Goal, error(E, _), R = raised(E))`; the kernel
#     consults the program and enumerates the answers of every `t_<id>/1`, swipl does the same through a driver. A record reference is
#     `recref` in the answer lines, a clause reference `clref`; the written form of a reference (an address) is reduced to its shape in
#     the Prolog (`refshape/2`). Rows over an unbound key compare SORTED lists (swipl enumerates its hash table: FLG H1).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and this driver, two runs byte-identical, 2026-10-31,
#     evidence/D2/d2_rows.out); with `swipl` on PATH the live answers are compared with the pins too.
#   * D-0252 item 2: rows r65, r67, r73, r75 give `erase/1` and `instance/2` a RECORD reference, which kills D1-56 and D1-119 of
#     tools/mutants/D1c.py (a branch on the reference's type the clause-only code did not have).
#   * WHITE-BOX: the `record` blob type of the database (its rank above `clause`), the payload and the table of references, the lists
#     and their links, `erase/1` with and without a running `recorded/3` (R_ERASED, RL_DIRTY, `cleanRecordList`), the key words, and the
#     state pool (`live_states` returns to 0 after the rows).
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
# (`Bool` is a grounded value of no SWI type: the blob test must tell it from a record blob)
const _RC = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_rcs(x) = lk_sym(_RC, Symbol(x))

_rc_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"

"A term as the driver's `enc/3` writes it: `V<i>` by first occurrence, atoms and functors by their codes, a record blob `recref`, a clause blob `clref`."
function _rc_enc(t::_RC, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) &&
            return blob_type(t) === :record ? "recref" :
                   blob_type(t) === :clause ? "clref" : "blob"
        return is_nil(t) ? "nil" : "a" * _rc_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _rc_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _rc_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_rc_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_at_body_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded), a non-text blob as `recref`/`clref`/`blob`
const _RC_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- blob(T, Ty), Ty \== text, !, ( Ty == record -> write(recref) ; Ty == clause -> write(clref) ; write(blob) ).
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
function _rc_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _RC_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `d/1` is dynamic (clause references), `rset` erases every record (through recorded/3 and erase/1), `ex/2` and `exc/2`
# answer `true` or `err(Formal)` / `err(Formal, Context)`, `kd/2` describes a key (name/arity for a compound), `refshape/2` the written form
const _RC_PROGRAM = raw"""
:- dynamic d/1.
strv("abc").
rset :- recorded(_, _, R), erase(R), fail.
rset.
ex(G, R) :- catch(( G, R = true ), error(E, _), R = err(E)).
exc(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
btype(S, B) :- ( atom(S) -> B = atom ; atomic(S) -> B = atomic ; B = other ).
kd(K, D) :- ( atom(K) -> D = K ; integer(K) -> D = K ; functor(K, N, A), D = N/A ).
refshape(Ref, S) :- term_to_atom(Ref, A), ( atom_concat('<record>(0x', _, A) -> S = recordform ; S = A ).
"""

# (id, goal), run IN ORDER
const _RC_CASES = [
    # r01-r10: recorda/2,3 and recordz/2,3 — the order of a key's list (pl-rec.c PL_record_az), the reference as a `record` blob (pl-dbref.c record_blob, PL_unify_recref)
    ("r01", raw"recordz(k, 1), recordz(k, 2), findall(X, recorded(k, X), R)"),
    ("r02", raw"recorda(k, 1), recorda(k, 2), findall(X, recorded(k, X), R)"),
    ("r03", raw"recordz(k, b), recorda(k, a), recordz(k, c), findall(X, recorded(k, X), R)"),
    ("r04", raw"recorda(k, x, R)"),
    ("r05", raw"recordz(k, x, Ref), blob(Ref, T), R = T"),
    ("r06", raw"recordz(k, x, Ref), btype(Ref, B), R = B"),
    ("r07", raw"recorda(k, x, Ref), refshape(Ref, R)"),
    ("r08", raw"recordz(k, x, R1), recordz(k, x, R2), ( R1 == R2 -> R = same ; R = diff )"),
    ("r09", raw"recordz(k, x, R1), copy_term(R1, R3), ( R1 == R3 -> R = same ; R = diff )"),
    ("r10", raw"recordz(k, x, R1), recordz(k, y, R2), ( R1 = R2 -> R = unified ; R = apart )"),
    # r11-r31: the key (getKeyEx): an atom, a small integer (swipl's tagged range ends at 2^55: r16-r19), a compound by name and arity, `[]`, and what is no key (type_error(key, _), the context)
    ("r11", raw"recordz(f(a, b), x), recorded(f(_, _), R)"),
    ("r12", raw"recordz(f(a, b), x), recorded(f(c, d), R)"),
    ("r13", raw"recordz(f(a, b), x), ( recorded(f(_), _) -> R = yes ; R = no )"),
    ("r14", raw"recordz(42, x), recorded(42, R)"),
    ("r15", raw"recordz(-7, x), recorded(-7, R)"),
    ("r16", raw"X is 2^55, recordz(X, x), recorded(X, R)"),
    ("r17", raw"X is 2^56, ex(recordz(X, x), R)"),
    ("r18", raw"X is -(2^55), ex(recordz(X, x), R)"),
    ("r19", raw"X is -(2^56), ex(recordz(X, x), R)"),
    ("r20", raw"ex(recordz(1.5, x), R)"),
    ("r21", raw"strv(S), ex(recordz(S, x), R)"),
    ("r22", raw"ex(recordz(_, x), R)"),
    ("r23", raw"exc(recordz(1.5, x), R)"),
    ("r24", raw"exc(recorda(_, x, _), R)"),
    ("r25", raw"exc(recorded(1.5, _), R)"),
    ("r26", raw"exc(recorded(1.5, _, _), R)"),
    ("r27", raw"recordz([], x), recorded([], R)"),
    ("r28", raw"recordz([a|b], x), recorded([_|_], R)"),
    ("r29", raw"recordz(m:k, x), recorded(n:j, R)"),
    ("r30", raw"recordz(k, x), recordz(f, y), recordz(f(a), z), recordz(f(a, b), w), findall(X, recorded(f, X), R)"),
    ("r31", raw"recordz(5, x), recordz('5', y), findall(X, recorded(5, X), R)"),
    # r32-r34: the reference argument must be unbound (PL_uninstantiation_error)
    ("r32", raw"exc(recorda(k, x, foo), R)"),
    ("r33", raw"recorda(k, x, R1), exc(recorda(k, y, R1), R)"),
    ("r34", raw"recorda(k, x, R1), ex(recordz(k, y, R1), R)"),
    # r35-r41: the recorded term (compileTermToHeap / copyRecordToGlobal): fresh variables shared inside the term, numbers and strings, a blob inside a term (UNVERIFIED on the kernel: r40, r41 — gate decides)
    ("r35", raw"recordz(k, f(X, Y, X)), recorded(k, R)"),
    ("r36", raw"recordz(k, f(X, g(Y), Y)), recorded(k, T), T = f(A, g(B), C), ( A \== B, B == C -> R = ok ; R = bad )"),
    ("r37", raw"strv(S), Big is 2^100, recordz(k, S), recordz(k, 1.5), recordz(k, Big), findall(X, recorded(k, X), R)"),
    ("r38", raw"recordz(k, _), recorded(k, R)"),
    ("r39", raw"recordz(k, f(A)), recorded(k, T), T = f(B), ( A == B -> R = shared ; R = fresh )"),
    ("r40", raw"recordz(k, x, Ref), recordz(j, ref(Ref)), recorded(j, ref(R2)), ( R2 == Ref -> R = same ; R = diff )"),
    ("r41", raw"assertz(d(1), C), recordz(k, c(C)), recorded(k, c(C2)), ( C2 == C -> R = same ; R = diff )"),
    # r42-r52: recorded/2,3 — the term filters, the reference bound (PL_get_recref: a wrong key fails, an erased record fails, a non-record reference is type_error(db_reference, _))
    ("r42", raw"recordz(k, a), recordz(k, b), recorded(k, a), R = ok"),
    ("r43", raw"recordz(k, f(1)), recordz(k, f(2)), recorded(k, f(R))"),
    ("r44", raw"recordz(k, a), ( recorded(k, b) -> R = yes ; R = no )"),
    ("r45", raw"( recorded(nokey, _) -> R = yes ; R = no )"),
    ("r46", raw"recordz(k, a, _), recordz(k, b, R2), recorded(k, T, R2), R = T"),
    ("r47", raw"recordz(k, a, _), recordz(k, b, R2), recorded(K, T, R2), R = K-T"),
    ("r48", raw"recordz(k, a, R1), recordz(j, b, _), ( recorded(j, _, R1) -> R = yes ; R = no )"),
    ("r49", raw"recordz(k, a, R1), erase(R1), ( recorded(k, _, R1) -> R = yes ; R = no )"),
    ("r50", raw"exc(recorded(k, _, foo), R)"),
    ("r51", raw"assertz(d(1), C), exc(recorded(k, _, C), R)"),
    ("r52", raw"recordz(k, a, R1), recordz(k, b, _), findall(T, recorded(k, T, R1), R)"),
    # r53-r64: the unbound key (compared SORTED: swipl enumerates its hash table, the kernel the creation of the lists; FLG H1) and current_key/1
    ("r53", raw"recordz(ka, 1), recordz(kb, 2), recordz(ka, 3), recordz(f(x), 4), recordz(9, 5), findall(D-T, ( recorded(K, T), kd(K, D) ), L), msort(L, R)"),
    ("r54", raw"recordz(ka, 1), recordz(kb, 2), recordz(ka, 3), recordz(f(x), 4), recordz(9, 5), findall(D-T, ( recorded(K, T, _), kd(K, D) ), L), msort(L, R)"),
    ("r55", raw"recordz(ka, 1), recordz(kb, 2), recordz(f(x), 4), recordz(9, 5), findall(D, ( current_key(K), kd(K, D) ), L), msort(L, R)"),
    ("r56", raw"recordz(ka, 1), ( current_key(ka) -> R = yes ; R = no )"),
    ("r57", raw"( current_key(nokey) -> R = yes ; R = no )"),
    ("r58", raw"recordz(ka, 1, Ref), erase(Ref), ( current_key(ka) -> R = yes ; R = no )"),
    ("r59", raw"recordz(f(a), 1), ( current_key(f(_)) -> R = yes ; R = no )"),
    ("r60", raw"recordz(f(a), 1), current_key(K), functor(K, N, A), R = N/A"),
    ("r61", raw"exc(current_key(1.5), R)"),
    ("r62", raw"recordz(a, 1), recordz(b, 2), once(current_key(_)), R = ok"),
    ("r63", raw"recordz(a, 1), recordz(b, 2), recordz(c, 3), findall(K, current_key(K), L), msort(L, R)"),
    ("r64", raw"recordz(k, 1), recordz(j, 2), recorded(K, 2), R = K"),
    # r65-r72: erase/1 of a record reference — D-0252 item 2: r65 and r67 kill D1-56 (erase/1 did not check the reference names a clause)
    ("r65", raw"recordz(k, a, Ref), erase(Ref), ( recorded(k, a) -> R = yes ; R = no )"),
    ("r66", raw"recordz(k, a, Ref), erase(Ref), ( erase(Ref) -> R = again ; R = failed )"),
    ("r67", raw"recordz(k, a, Ref), erase(Ref), R = ok"),
    ("r68", raw"recordz(k, a, Ref), recordz(k, b, _), erase(Ref), findall(X, recorded(k, X), R)"),
    ("r69", raw"ex(erase(foo), R)"),
    ("r70", raw"ex(erase(_), R)"),
    ("r71", raw"exc(erase(foo), R)"),
    ("r72", raw"recordz(k, a), recorded(k, a, Ref), erase(Ref), ( recorded(k, _) -> R = yes ; R = no )"),
    # r73-r80: instance/2 of a record reference — D-0252 item 2: r73 and r75 kill D1-119 (instance/2 did not test the reference's type)
    ("r73", raw"recordz(k, f(X, Y, X), Ref), instance(Ref, R)"),
    ("r74", raw"recordz(k, g(1), Ref), ( instance(Ref, g(2)) -> R = yes ; R = no )"),
    ("r75", raw"recordz(k, g(1), Ref), instance(Ref, g(R))"),
    ("r76", raw"recordz(k, a, Ref), erase(Ref), ( instance(Ref, _) -> R = yes ; R = no )"),
    ("r77", raw"ex(instance(foo, _), R)"),
    ("r78", raw"ex(instance(_, _), R)"),
    ("r79", raw"exc(instance(foo, _), R)"),
    ("r80", raw"recordz(k, f(Z), Ref), instance(Ref, T), T = f(Q), ( Z == Q -> R = shared ; R = fresh )"),
    # r81-r85: a clause reference and a record reference side by side (D1's branch stays)
    ("r81", raw"assertz(d(1), C), instance(C, R)"),
    ("r82", raw"assertz(d(1), C), erase(C), ( d(_) -> R = yes ; R = no )"),
    ("r83", raw"assertz(d(1), C), recordz(k, x, Rf), erase(Rf), ( instance(C, _) -> R = clause_alive ; R = clause_gone )"),
    ("r84", raw"recordz(k, x, Rf), assertz(d(1), C), erase(C), ( instance(Rf, I) -> R = I ; R = gone )"),
    ("r85", raw"recordz(k, x, Rf), assertz(d(1), C), exc(recorded(k, _, C), R0), R = R0-Rf"),
    # r86-r98: the list while recorded/2,3 runs over it (RL_DIRTY, R_ERASED, the references count, FRG_CUTTED): a record added at the end is seen, an erased one is skipped
    ("r86", raw"recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X), ( X == 1 -> recordz(k, 4) ; true ) ), R)"),
    ("r87", raw"recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X, Ref), erase(Ref) ), R)"),
    ("r88", raw"recordz(k, 1), recordz(k, 2), recordz(k, 3), findall(X, ( recorded(k, X), ( X == 1 -> recorded(k, 2, R2), erase(R2) ; true ) ), R)"),
    ("r89", raw"recordz(k, 1), recordz(k, 2), ( recorded(k, _, Ref), erase(Ref), fail ; true ), recordz(k, 3), findall(X, recorded(k, X), R)"),
    ("r90", raw"recordz(k, 1), recordz(k, 2), ( recorded(k, _, Ref), erase(Ref), fail ; true ), ( current_key(k) -> R = alive ; R = gone )"),
    ("r91", raw"recordz(k, 1), recordz(k, 2), recordz(k, 3), recorded(k, R, Ref), erase(Ref)"),
    ("r92", raw"recordz(k, 1), recordz(k, 2), once(recorded(k, _, Ref)), erase(Ref), findall(X, recorded(k, X), R)"),
    ("r93", raw"recordz(k, 1), recorded(k, 1, Ref), recorda(k, 0), erase(Ref), findall(X, recorded(k, X), R)"),
    ("r94", raw"recordz(k, 1), recordz(k, 2), recorded(k, X, Ref), erase(Ref), recorded(k, Y), R = X-Y"),
    ("r95", raw"recordz(k, 1), recordz(k, 2), recordz(k, 3), recorded(k, X), X >= 2, !, R = X"),
    ("r96", raw"( between(1, 300, N), recordz(k, N), fail ; true ), findall(X, recorded(k, X), L), length(L, R)"),
    ("r97", raw"( between(1, 300, N), recorda(k, N), fail ; true ), once(recorded(k, R))"),
    ("r98", raw"recordz(k, 1), recordz(k, 2), ( recorded(k, X, Ref), erase(Ref), recorded(k, Y), R = X-Y ; R = none )"),
    # r99-r101: advance_state skips a record erased while recorded/3 runs; an emptied key is no key (unbound-key enumeration)
    ("r99", raw"recordz(k, f(1)), recordz(k, g(2)), recordz(k, g(3)), recorded(k, f(_)), recorded(k, g(2), Rg), erase(Rg), findall(X, recorded(k, g(X)), R)"),
    ("r100", raw"recordz(ka, 1, Ref), recordz(kb, 2), erase(Ref), findall(K, current_key(K), R)"),
    ("r101", raw"recordz(ka, 1, Ref), recordz(kb, 2), erase(Ref), findall(K-T, recorded(K, T), R)")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; evidence/D2/d2_rows.out)
const _RC_PINNED = [
    "ok",
    "t_r01 c[116,95,114,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_r02 c[116,95,114,48,50]/1(c[91,124,93]/2(i2,c[91,124,93]/2(i1,nil)))",
    "t_r03 c[116,95,114,48,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "t_r04 c[116,95,114,48,52]/1(recref)",
    "t_r05 c[116,95,114,48,53]/1(a[114,101,99,111,114,100])",
    "t_r06 c[116,95,114,48,54]/1(a[97,116,111,109,105,99])",
    "t_r07 c[116,95,114,48,55]/1(a[114,101,99,111,114,100,102,111,114,109])",
    "t_r08 c[116,95,114,48,56]/1(a[100,105,102,102])",
    "t_r09 c[116,95,114,48,57]/1(a[115,97,109,101])",
    "t_r10 c[116,95,114,49,48]/1(a[97,112,97,114,116])",
    "t_r11 c[116,95,114,49,49]/1(a[120])",
    "t_r12 c[116,95,114,49,50]/1(a[120])",
    "t_r13 c[116,95,114,49,51]/1(a[110,111])",
    "t_r14 c[116,95,114,49,52]/1(a[120])",
    "t_r15 c[116,95,114,49,53]/1(a[120])",
    "t_r16 c[116,95,114,49,54]/1(a[120])",
    "t_r17 c[116,95,114,49,55]/1(c[101,114,114]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],i72057594037927936)))",
    "t_r18 c[116,95,114,49,56]/1(a[116,114,117,101])",
    "t_r19 c[116,95,114,49,57]/1(a[116,114,117,101])",
    "t_r20 c[116,95,114,50,48]/1(c[101,114,114]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5)))",
    "t_r21 c[116,95,114,50,49]/1(c[101,114,114]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],s[97,98,99])))",
    "t_r22 c[116,95,114,50,50]/1(c[101,114,114]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_r23 c[116,95,114,50,51]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,122],i2)),V0)))",
    "t_r24 c[116,95,114,50,52]/1(c[101,114,114]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,97],i3)),V0)))",
    "t_r25 c[116,95,114,50,53]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,101,100],i2)),V0)))",
    "t_r26 c[116,95,114,50,54]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,101,100],i3)),V0)))",
    "t_r27 c[116,95,114,50,55]/1(a[120])",
    "t_r28 c[116,95,114,50,56]/1(a[120])",
    "t_r29 c[116,95,114,50,57]/1(a[120])",
    "t_r30 c[116,95,114,51,48]/1(c[91,124,93]/2(a[121],nil))",
    "t_r31 c[116,95,114,51,49]/1(c[91,124,93]/2(a[120],nil))",
    "t_r32 c[116,95,114,51,50]/1(c[101,114,114]/2(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,97],i3)),V0)))",
    "t_r33 c[116,95,114,51,51]/1(c[101,114,114]/2(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(recref),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,97],i3)),V0)))",
    "t_r34 c[116,95,114,51,52]/1(c[101,114,114]/1(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(recref)))",
    "t_r35 c[116,95,114,51,53]/1(c[102]/3(V0,V1,V0))",
    "t_r36 c[116,95,114,51,54]/1(a[111,107])",
    "t_r37 c[116,95,114,51,55]/1(c[91,124,93]/2(s[97,98,99],c[91,124,93]/2(f1.5,c[91,124,93]/2(i1267650600228229401496703205376,nil))))",
    "t_r38 c[116,95,114,51,56]/1(V0)",
    "t_r39 c[116,95,114,51,57]/1(a[102,114,101,115,104])",
    "t_r40 c[116,95,114,52,48]/1(a[115,97,109,101])",
    "t_r41 c[116,95,114,52,49]/1(a[115,97,109,101])",
    "t_r42 c[116,95,114,52,50]/1(a[111,107])",
    "t_r43 c[116,95,114,52,51]/1(i1) c[116,95,114,52,51]/1(i2)",
    "t_r44 c[116,95,114,52,52]/1(a[110,111])",
    "t_r45 c[116,95,114,52,53]/1(a[110,111])",
    "t_r46 c[116,95,114,52,54]/1(a[98])",
    "t_r47 c[116,95,114,52,55]/1(c[45]/2(a[107],a[98]))",
    "t_r48 c[116,95,114,52,56]/1(a[110,111])",
    "t_r49 c[116,95,114,52,57]/1(a[110,111])",
    "t_r50 c[116,95,114,53,48]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,101,100],i3)),V0)))",
    "t_r51 c[116,95,114,53,49]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],clref),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,101,100],i3)),V0)))",
    "t_r52 c[116,95,114,53,50]/1(c[91,124,93]/2(a[97],nil))",
    "t_r53 c[116,95,114,53,51]/1(c[91,124,93]/2(c[45]/2(i9,i5),c[91,124,93]/2(c[45]/2(a[107,97],i1),c[91,124,93]/2(c[45]/2(a[107,97],i3),c[91,124,93]/2(c[45]/2(a[107,98],i2),c[91,124,93]/2(c[45]/2(c[47]/2(a[102],i1),i4),nil))))))",
    "t_r54 c[116,95,114,53,52]/1(c[91,124,93]/2(c[45]/2(i9,i5),c[91,124,93]/2(c[45]/2(a[107,97],i1),c[91,124,93]/2(c[45]/2(a[107,97],i3),c[91,124,93]/2(c[45]/2(a[107,98],i2),c[91,124,93]/2(c[45]/2(c[47]/2(a[102],i1),i4),nil))))))",
    "t_r55 c[116,95,114,53,53]/1(c[91,124,93]/2(i9,c[91,124,93]/2(a[107,97],c[91,124,93]/2(a[107,98],c[91,124,93]/2(c[47]/2(a[102],i1),nil)))))",
    "t_r56 c[116,95,114,53,54]/1(a[121,101,115])",
    "t_r57 c[116,95,114,53,55]/1(a[110,111])",
    "t_r58 c[116,95,114,53,56]/1(a[110,111])",
    "t_r59 c[116,95,114,53,57]/1(a[121,101,115])",
    "t_r60 c[116,95,114,54,48]/1(c[47]/2(a[102],i1))",
    "t_r61 c[116,95,114,54,49]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[99,117,114,114,101,110,116,95,107,101,121],i1)),V0)))",
    "t_r62 c[116,95,114,54,50]/1(a[111,107])",
    "t_r63 c[116,95,114,54,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "t_r64 c[116,95,114,54,52]/1(a[106])",
    "t_r65 c[116,95,114,54,53]/1(a[110,111])",
    "t_r66 c[116,95,114,54,54]/1(a[102,97,105,108,101,100])",
    "t_r67 c[116,95,114,54,55]/1(a[111,107])",
    "t_r68 c[116,95,114,54,56]/1(c[91,124,93]/2(a[98],nil))",
    "t_r69 c[116,95,114,54,57]/1(c[101,114,114]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[102,111,111])))",
    "t_r70 c[116,95,114,55,48]/1(c[101,114,114]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_r71 c[116,95,114,55,49]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[101,114,97,115,101],i1)),V0)))",
    "t_r72 c[116,95,114,55,50]/1(a[110,111])",
    "t_r73 c[116,95,114,55,51]/1(c[102]/3(V0,V1,V0))",
    "t_r74 c[116,95,114,55,52]/1(a[110,111])",
    "t_r75 c[116,95,114,55,53]/1(i1)",
    "t_r76 c[116,95,114,55,54]/1(a[110,111])",
    "t_r77 c[116,95,114,55,55]/1(c[101,114,114]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[102,111,111])))",
    "t_r78 c[116,95,114,55,56]/1(c[101,114,114]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_r79 c[116,95,114,55,57]/1(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],a[102,111,111]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[105,110,115,116,97,110,99,101],i2)),V0)))",
    "t_r80 c[116,95,114,56,48]/1(a[102,114,101,115,104])",
    "t_r81 c[116,95,114,56,49]/1(c[58,45]/2(c[100]/1(i1),a[116,114,117,101]))",
    "t_r82 c[116,95,114,56,50]/1(a[121,101,115])",
    "t_r83 c[116,95,114,56,51]/1(a[99,108,97,117,115,101,95,97,108,105,118,101])",
    "t_r84 c[116,95,114,56,52]/1(a[120])",
    "t_r85 c[116,95,114,56,53]/1(c[45]/2(c[101,114,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,98,95,114,101,102,101,114,101,110,99,101],clref),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[114,101,99,111,114,100,101,100],i3)),V0)),recref))",
    "t_r86 c[116,95,114,56,54]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)))))",
    "t_r87 c[116,95,114,56,55]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_r88 c[116,95,114,56,56]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_r89 c[116,95,114,56,57]/1(c[91,124,93]/2(i3,nil))",
    "t_r90 c[116,95,114,57,48]/1(a[103,111,110,101])",
    "t_r91 c[116,95,114,57,49]/1(i1) c[116,95,114,57,49]/1(i2) c[116,95,114,57,49]/1(i3)",
    "t_r92 c[116,95,114,57,50]/1(c[91,124,93]/2(i2,nil))",
    "t_r93 c[116,95,114,57,51]/1(c[91,124,93]/2(i0,nil))",
    "t_r94 c[116,95,114,57,52]/1(c[45]/2(i1,i2))",
    "t_r95 c[116,95,114,57,53]/1(i2)",
    "t_r96 c[116,95,114,57,54]/1(i300)",
    "t_r97 c[116,95,114,57,55]/1(i300)",
    "t_r98 c[116,95,114,57,56]/1(c[45]/2(i1,i2)) c[116,95,114,57,56]/1(a[110,111,110,101])",
    "t_r99 c[116,95,114,57,57]/1(c[91,124,93]/2(i3,nil))",
    "t_r100 c[116,95,114,49,48,48]/1(c[91,124,93]/2(a[107,98],nil))",
    "t_r101 c[116,95,114,49,48,49]/1(c[91,124,93]/2(c[45]/2(a[107,98],i2),nil))"
]

"The program and cases as one file; the case predicates' names."
function _rc_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _RC_CASES]
    text =
        _RC_PROGRAM * join([
            "t_$(id)(R) :- rset, catch(($g), error(RcE, _), R = raised(RcE)).\n" for
            (id, g) in _RC_CASES
        ])
    f = joinpath(mktempdir(), "d2rows.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _rc_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_RC}()
    ld = LK.PL_local_data{_RC}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _rc_enc(ball::_RC)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_rcs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_RC, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _rc_enc(mk_expr(_RC, _RC[_rcs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "the recorded database == swipl's pinned answers (r01-r101)" begin
    f, names = _rc_file()
    kl, _, ld = _rc_kernel(f, names)
    @test length(kl) == length(_RC_PINNED)
    for (k, p) in zip(kl, _RC_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # every state of recorded/2,3 and current_key/1 was given back (a cut, an exhausted enumeration, an exception)
    @test LK.live_states(ld) == 0
    # not vacuous: both sides hold answers of every kind the comparison can tell apart
    @test length(_RC_PINNED) == length(_RC_CASES) + 1 && length(kl) == length(_RC_PINNED)
    @test _RC_PINNED[1] == "ok"
    @test count(l -> occursin("recref", l), _RC_PINNED) >= 2                           # a reference in an answer: r04, r33
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _RC_PINNED) >= 1        # raised(…)
    @test count(l -> occursin("c[101,114,114]/", l), _RC_PINNED) >= 12                 # err(Formal[, Context]) of ex/2, exc/2
    @test count(l -> occursin("(a[121,101,115])", l), _RC_PINNED) >= 3                 # yes
    @test count(l -> occursin("(a[110,111])", l), _RC_PINNED) >= 5                     # no
    @test count(l -> occursin("(a[111,107])", l), _RC_PINNED) >= 3                     # ok
    @test count(l -> occursin("c[91,124,93]/2(", l), _RC_PINNED) >= 8                  # lists: r01-r03, r30, r37, ...
    # a row with more than one answer is in the pins (r43, r91: the redo of recorded/2,3)
    @test count(l -> count("c[116,95,114", l) > 1, _RC_PINNED) >= 2
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_RC_PINNED) == length(_RC_CASES) + 1
    if swipl === nothing
        @info "D2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _rc_file()
        @test _rc_swipl_lines(f, names) == _RC_PINNED
    end
end

# ---- the kernel's calls, one built-in at a time (the white-box testsets)
"Call the system predicate `name` on `args`: `(status, answers)`; status `:true`, `:false` or `:exception` (the ball is the answer)."
function _rc_kcall(gd::LK.PL_global_data{T}, ld, name::String, args::Vector{T}) where {T}
    proc = LK.isCurrentProcedure(
        sym_key(lk_sym(T, Symbol(name))), length(args), LK.MODULE_system(gd)
    )
    @assert proc !== nothing "no system predicate $name/$(length(args))"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    status = :false
    ans = T[]
    rc = LK.PL_next_solution(gd, ld, qid)
    if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        status = :true
        ans = lk_answers(ld, [a + i - 1 for i in 1:length(args)]...)
    elseif rc == LK.PL_S_EXCEPTION
        status = :exception
        ans = T[lk_answer(ld, LK.PL_exception(ld, qid))]
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return status, ans
end

@testset "the record blob type is registered by the database, above clause (pl-setup.c initDBRef, pl-dbref.c record_blob)" begin
    gd = LK.PL_global_data{_RC}()
    rreg = LK._blob_registration(gd.atoms, LK.record_blob)
    creg = LK._blob_registration(gd.atoms, LK.clause_blob)
    @test rreg !== nothing && rreg.rank < 0 && rreg.padding == 0
    @test rreg.atom_name == LK.builtin_atom("record")                 # ATOM_record: no new atom
    # swipl's order is stream < clause < record < mutex: `record` is registered FIRST, so it ranks above `clause`
    @test creg.rank < rreg.rank
    # a second registration is a no-op
    n = length(gd.atoms.types)
    LK.initDBRef!(gd.atoms)
    @test length(gd.atoms.types) == n
    # no record has a reference, a list or a state yet
    @test isempty(gd.record_refs) && isempty(gd.record_lists) &&
        isempty(gd.record_lists_order)
end

@testset "the lists, the references and the blob payload: recorda/2,3, recordz/2,3 (pl-rec.c PL_record_az, pl-dbref.c PL_unify_recref)" begin
    gd = LK.PL_global_data{_RC}()
    ld = LK.PL_local_data{_RC}(gd)
    v() = mk_var(_RC, LK.fresh_var_keys!(1))
    k = _rcs("k")
    st1, a1 = _rc_kcall(gd, ld, "recordz", _RC[k, lk_gnd(_RC, 1), v()])
    st2, a2 = _rc_kcall(gd, ld, "recorda", _RC[k, lk_gnd(_RC, 2), v()])
    st3, _ = _rc_kcall(gd, ld, "recordz", _RC[k, lk_gnd(_RC, 3)])
    @test st1 === :true && st2 === :true && st3 === :true
    r1, r2 = a1[3], a2[3]
    @test is_blob(r1) && is_blob(r2) && blob_type(r1) === :record &&
        blob_type(r2) === :record
    @test blob_handle(r1) != blob_handle(r2) && blob_rank(r1) == blob_rank(r2) < 0
    # the table: two references, numbered in the order of their first blob; the payload is the number
    @test length(gd.record_refs) == 2 && length(gd.record_lists) == 1
    rr1, rr2 = LK.recref_record(gd, r1), LK.recref_record(gd, r2)
    @test rr1 isa LK.RecordRef{_RC} && rr2 isa LK.RecordRef{_RC} && rr1 !== rr2
    @test gd.record_refs[1] === rr1 && gd.record_refs[2] === rr2
    @test rr1.serial == 1 && rr2.serial == 2
    at1 = LK.atomValue(gd.atoms, blob_handle(r1))
    @test at1.type === LK.record_blob && at1.name == LK._recref_bytes(1) &&
        length(at1.name) == 8
    # the list of `k`: 2 (recorda), 1, 3 (recordz); the third has no reference (recordz/2)
    @test length(gd.record_lists_order) == 1
    l = gd.record_lists_order[1]
    @test l === only(values(gd.record_lists)) && l.references == 0 && l.flags == 0
    third = rr1.next
    @test l.firstRecord === rr2 && rr2.prev === nothing && rr2.next === rr1
    @test third !== nothing && rr1.prev === rr2 && third.prev === rr1 &&
        third.next === nothing && l.lastRecord === third
    @test rr1.list === l && rr2.list === l && third.list === l
    # the mark: a record with a database reference has R_DBREF, the third (recordz/2) none
    @test (rr1.flags & LK.R_DBREF) != 0 && (rr2.flags & LK.R_DBREF) != 0
    @test (third.flags & LK.R_DBREF) == 0 && third.serial == 0
    # PL_get_dbref: a record reference, of the record type
    kt = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, kt + 1, r1, LK.PutVarMap())
    dr = LK.PL_get_dbref(gd, ld, kt)
    @test dr !== nothing && dr[1] == LK.DB_REF_RECORD && dr[2] === rr1
    @test LK.PL_is_dbref(gd, ld, kt)
    # erase/1 of the first record: unlinked, its record dropped; the reference answers erased from now on
    @test _rc_kcall(gd, ld, "erase", _RC[r1])[1] === :true
    @test l.firstRecord === rr2 && rr2.next === third && third.prev === rr2
    @test rr1.record === nothing
    @test _rc_kcall(gd, ld, "erase", _RC[r1])[1] === :false           # an erased reference: false, no error
    @test LK.PL_get_dbref(gd, ld, kt) === nothing
    # a running recorded/3 (references > 0): erase/1 marks (R_ERASED, RL_DIRTY), the record stays linked
    l.references = 1
    @test _rc_kcall(gd, ld, "erase", _RC[r2])[1] === :true
    @test (rr2.flags & LK.R_ERASED) != 0 && (l.flags & LK.RL_DIRTY) != 0
    @test l.firstRecord === rr2 && rr2.record !== nothing
    @test LK.firstRecordRecordList(l) === third                        # an erased record is skipped
    @test _rc_kcall(gd, ld, "erase", _RC[r2])[1] === :false
    # the last recorded/3 gives up the list: cleanRecordList removes the erased record
    l.references = 0
    LK.cleanRecordList(l)
    @test l.firstRecord === third && third.prev === nothing && l.lastRecord === third
    @test rr2.record === nothing
    # the list stays when it is emptied (upstream keeps it), current_key/1 no longer shows it
    LK.remove_record(third)
    @test l.firstRecord === nothing && l.lastRecord === nothing
    @test LK.isCurrentRecordList(gd, l.key, true) === nothing
    @test LK.isCurrentRecordList(gd, l.key, false) === l
end

@testset "the key words: an atom, a small integer, a compound by name and arity (getKeyEx, lookupRecordList)" begin
    gd = LK.PL_global_data{_RC}()
    ld = LK.PL_local_data{_RC}(gd)
    f(args...) = mk_expr(_RC, _RC[_rcs("f"), args...])
    x = _rcs("x")
    for key in (_rcs("f"), lk_gnd(_RC, 5), _rcs("5"), f(x), f(x, x), f(_rcs("c"), _rcs("d")))
        @test _rc_kcall(gd, ld, "recordz", _RC[key, x])[1] === :true
    end
    # f(a,b) and f(c,d) share the list of the functor f/2: five lists for six records
    @test length(gd.record_lists) == 5 && length(gd.record_lists_order) == 5
    # the lists in the order of their creation (the enumeration of an unbound key): f, 5, '5', f/1, f/2
    @test Set(l.key for l in gd.record_lists_order) == Set(keys(gd.record_lists))
    # what is no key: a float, a string, an unbound variable: type_error(key, _) / instantiation_error
    for (bad, formal) in (
        (lk_gnd(_RC, 1.5), "c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5)"),
        (lk_gnd(_RC, "s"), "c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],s[115])"),
        (mk_var(_RC, LK.fresh_var_keys!(1)), "a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]")
    )
        st, ans = _rc_kcall(gd, ld, "recordz", _RC[bad, x])
        @test st === :exception
        @test occursin(formal, _rc_enc(ans[1]))
    end
    @test length(gd.record_lists) == 5
end

@testset "the references of a list: recorded/2,3 gives its reference back when cut or finished (recorded, free_state, advance_state, PL_get_recref)" begin
    # UNVERIFIED on the kernel: gate decides (a query closed after its first answer is FRG_CUTTED: free_state)
    gd = LK.PL_global_data{_RC}()
    ld = LK.PL_local_data{_RC}(gd)
    v() = mk_var(_RC, LK.fresh_var_keys!(1))
    k, j = _rcs("k"), _rcs("j")
    for n in 1:3
        @test _rc_kcall(gd, ld, "recordz", _RC[k, lk_gnd(_RC, n)])[1] === :true
    end
    @test _rc_kcall(gd, ld, "recordz", _RC[j, lk_gnd(_RC, 1)])[1] === :true
    @test length(gd.record_lists_order) == 2
    rlk, rlj = gd.record_lists_order
    # the first answer of recorded(k, X) leaves a choicepoint; closing the query cuts it
    @test _rc_kcall(gd, ld, "recorded", _RC[k, v()])[1] === :true
    @test rlk.references == 0 && ld.recorded_states.live == 0
    # recorded(j, X): the only record is answered, the list left at once
    @test _rc_kcall(gd, ld, "recorded", _RC[j, v()])[1] === :true
    @test rlj.references == 0 && ld.recorded_states.live == 0
    # recorded(K, X): the enumeration of the keys holds one list at a time
    @test _rc_kcall(gd, ld, "recorded", _RC[v(), v()])[1] === :true
    @test rlk.references == 0 && rlj.references == 0 && ld.recorded_states.live == 0
    # the references are 0: erase/1 unlinks at once (no mark)
    st, a = _rc_kcall(gd, ld, "recordz", _RC[k, lk_gnd(_RC, 4), v()])
    @test st === :true
    rr = LK.recref_record(gd, a[3])
    @test _rc_kcall(gd, ld, "erase", _RC[a[3]])[1] === :true
    @test rr.record === nothing && (rlk.flags & LK.RL_DIRTY) == 0
    # a reference erased while a recorded/3 runs (marked, not unlinked) is no reference: recorded(_, _, Ref) is false
    st, b = _rc_kcall(gd, ld, "recordz", _RC[k, lk_gnd(_RC, 5), v()])
    rb = LK.recref_record(gd, b[3])
    rlk.references = 1
    @test _rc_kcall(gd, ld, "erase", _RC[b[3]])[1] === :true
    @test (rb.flags & LK.R_ERASED) != 0 && rb.record !== nothing
    @test _rc_kcall(gd, ld, "recorded", _RC[v(), v(), b[3]])[1] === :false
    rlk.references = 0
end
