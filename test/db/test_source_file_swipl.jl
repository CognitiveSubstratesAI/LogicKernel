# ORIGINAL: R2's LB2 gate — the source-file predicates of pl-srcfile.c ('$source_file'/2, '$source_file_predicates'/2, '$time_source_file'/3, '$source_file_property'/3, '$set_source_file'/3, '$start_consult'/2, '$end_consult'/1, '$fixup_reconsult'/1) and system mode against swipl 10.1.19; upstream tests them through Prolog (boot/init.pl's loader), which needs the loader (R2).
# test/db/test_source_file_swipl.jl — LB2's gate (audit D-0244, design evidence/r2/design/loader_boot.md §2.6, §3.2, §5 H5/H7/H10):
#   * ROWS, as a program (the pattern of test/db/test_clause_ref_swipl.jl): each case is a predicate `t_<id>(R)`; the kernel
#     consults the program and enumerates the answers of every `t_<id>/1`, swipl does the same through a driver, and the lines
#     are compared. EVERY expected value is swipl's own answer (the driver runs live). `@FILE@` in a goal is the program's path
#     (the source file's name in both systems), so the two systems ask about the same file;
#   * WHITE-BOX: what swipl cannot be asked — `'$source_file_property'(+Unknown, loaded, -V)` (H10: swipl dies on it), the module
#     list of a source file, the refusal of a reconsult (LB6), and system mode (H5: `access_level`, the P_LOCKED / HIDE_CHILDS
#     bits of a predicate defined in system mode, `isStaticSystemProcedure`).
# NOT HERE: `nth_clause/3` and `'$get_clause_attribute'/3` rows (test/db/test_nth_clause_swipl.jl), the module sites
# (`exportProcedureSource`, `setMetapredicateSource`: after MOD4, loader_boot.md §3.4 L3/L4), a reconsult (LB6).
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"

# the answer lines' encoding of a term (the driver's `enc/3` prints the same); a clause blob is `clref`
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
        is_blob(t) && return blob_type(t) === :clause ? "clref" : "blob"
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


# ---- the program: swipl's rows (`t_<id>(R)`). foo/1, bar/1, baz/0 are defined in that order; d/1 is declared dynamic first.
const _PROGRAM = """
:- dynamic d/1.
foo(1).
foo(2).
bar(1).
baz :- foo(_).
mem(X, [X|_]).
mem(X, [_|T]) :- mem(X, T).
ex(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
keep(L, L1) :- findall(P, ( mem(P, L), P = user:H, functor(H, N, _), mem(N, [foo,bar,baz,d]) ), L1).
:- dynamic sloc/2.
:- source_location(F, L), assertz(sloc(F, L)).
"""

# (id, goal). `ex/2` returns `true` or `err(Formal, Context)`. `@FILE@` is the program's path.
const _CASES = [
    # ---- '$source_file'/2: not transparent (the table's flags win over PRED_IMPL's), unknown module names mean `user`
    ("s01", "'\$source_file'(user:foo(_), F), ( F == '@FILE@' -> R = same ; R = F )"),
    ("s02", "( '\$source_file'(foo(_), F) -> R = F ; R = fails )"),
    ("s03", "'\$source_file'(nomod:foo(_), F), ( F == '@FILE@' -> R = same ; R = F )"),
    ("s04", "( '\$source_file'(user:nothere(_), F) -> R = F ; R = fails )"),
    ("s05", "'\$source_file'(user:d(_), F), ( F == '@FILE@' -> R = same ; R = F )"),
    ("s06", "'\$source_file'(user:baz, F), ( F == '@FILE@' -> R = same ; R = F )"),
    ("s07", "ex('\$source_file'(_, _), R)"),
    ("s08", "ex('\$source_file'(1, _), R)"),
    ("s09", "ex('\$source_file'(user:\"s\", _), R)"),
    ("s10", "( '\$source_file'(user:foo(_), 3) -> R = yes ; R = no )"),
    ("s11", "( '\$source_file'(system:atom_length(_, _), F) -> R = F ; R = fails )"),
    (
        "s12",
        "'\$source_file'(user:foo(_), F), '\$source_file'(user:bar(_), F2), ( F == F2 -> R = same ; R = diff )"
    ),
    ("s13", "( '\$source_file'(user:foo(_), '@FILE@') -> R = yes ; R = no )"),
    ("s14", "ex('\$source_file'(user:(foo/1), _), R)"),
    # ---- '$source_file_predicates'/2: the newest predicate first
    ("p01", "'\$source_file_predicates'('@FILE@', L), keep(L, L1), R = L1"),
    ("p02", "( '\$source_file_predicates'('/no/such/file', L) -> R = L ; R = fails )"),
    ("p03", "ex('\$source_file_predicates'(_, _), R)"),
    ("p04", "ex('\$source_file_predicates'(1, _), R)"),
    ("p05", "( '\$source_file_predicates'('@FILE@', [_]) -> R = yes ; R = no )"),
    ("p06", "'\$source_file_predicates'('@FILE@', L), length(L, N), N > 10, R = many"),
    ("p07", "'\$source_file_predicates'('@FILE@', [user:H|_]), functor(H, N, A), R = N/A"),
    ("p08", "'\$source_file_predicates'('@FILE@', L), mem(user:foo(X), L), var(X), R = ok"),
    ("p09", "( '\$source_file_predicates'('@FILE@', foo) -> R = yes ; R = no )"),
    # ---- '$time_source_file'/3: non-deterministic
    (
        "t01",
        "findall(Ty-K, ( '\$time_source_file'('@FILE@', T, Ty), ( float(T) -> K = flt ; K = int ) ), L), R = L"
    ),
    ("t02", "findall(x, '\$time_source_file'('@FILE@', _, _), L), length(L, N), R = N"),
    ("t03", "findall(F, ( '\$time_source_file'(F, _, user), F == '@FILE@' ), L), R = L"),
    ("t04", "( '\$time_source_file'(_, _, _), ! ; true ), R = ok"),
    ("t05", "( '\$time_source_file'('/no/such', _, _) -> R = yes ; R = no )"),
    ("t06", "( '\$time_source_file'('@FILE@', 0, _) -> R = yes ; R = no )"),
    ("t07", "( '\$time_source_file'('@FILE@', _, system) -> R = yes ; R = no )"),
    ("t08", "'\$time_source_file'('@FILE@', T, _), T > 0, R = positive"),
    ("t09", "findall(F, ( '\$time_source_file'(F, _, _), F == '@FILE@' ), L), R = L"),
    # ---- '$source_file_property'/3
    ("f01", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
    ("f02", "'\$source_file_property'('@FILE@', reloading, V), R = V"),
    ("f03", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V"),
    ("f04", "'\$source_file_property'('@FILE@', resource, V), R = V"),
    ("f05", "'\$source_file_property'('@FILE@', from_state, V), R = V"),
    (
        "f06",
        "'\$source_file_property'('@FILE@', loaded, V), ( float(V) -> R = flt ; R = V )"
    ),
    ("f07", "'\$source_file_property'('@FILE@', loaded, V), V > 0, R = positive"),
    ("f08", "ex('\$source_file_property'('@FILE@', nope, _), R)"),
    ("f09", "ex('\$source_file_property'('@FILE@', 1, _), R)"),
    ("f10", "ex('\$source_file_property'(_, load_count, _), R)"),
    ("f11", "ex('\$source_file_property'(1, load_count, _), R)"),
    ("f12", "ex('\$source_file_property'('@FILE@', _, _), R)"),
    ("f13", "'\$source_file_property'('/no/such/file', load_count, V), R = V"),
    ("f14", "'\$source_file_property'('/no/such/file', number_of_clauses, V), R = V"),
    ("f15", "'\$source_file_property'('/no/such/file', resource, V), R = V"),
    ("f16", "'\$source_file_property'('/no/such/file', from_state, V), R = V"),
    ("f17", "'\$source_file_property'('/no/such/file', reloading, V), R = V"),
    ("f18", "ex('\$source_file_property'('/no/such/file', nope, _), R)"),
    ("f19", "( '\$source_file_property'('@FILE@', load_count, 2) -> R = yes ; R = no )"),
    ("f20", "( '\$source_file_property'('@FILE@', resource, true) -> R = yes ; R = no )"),
    ("f21", "'\$source_file_property'('@FILE@', number_of_clauses, V), V > 20, R = many"),
    # ---- '$set_source_file'/3
    (
        "g01",
        "'\$set_source_file'('@FILE@', resource, true), '\$source_file_property'('@FILE@', resource, V), '\$set_source_file'('@FILE@', resource, false), '\$source_file_property'('@FILE@', resource, V2), R = V-V2"
    ),
    ("g02", "ex('\$set_source_file'('/no/such/file', resource, true), R)"),
    ("g03", "ex('\$set_source_file'('@FILE@', resource, maybe), R)"),
    ("g04", "ex('\$set_source_file'('@FILE@', load_count, 1), R)"),
    ("g05", "ex('\$set_source_file'(_, resource, true), R)"),
    ("g06", "ex('\$set_source_file'('@FILE@', _, true), R)"),
    ("g07", "ex('\$set_source_file'('/no/such/file', load_count, 1), R)"),
    ("g08", "ex('\$set_source_file'('@FILE@', resource, _), R)"),
    ("g09", "ex('\$set_source_file'(1, resource, true), R)"),
    (
        "g10",
        "'\$set_source_file'('@FILE@', resource, on), '\$source_file_property'('@FILE@', resource, V), '\$set_source_file'('@FILE@', resource, off), R = V"
    ),
    # ---- '$start_consult'/2, '$end_consult'/1, '$fixup_reconsult'/1 (each row its own file: a reconsult is LB6's)
    (
        "c01",
        "'\$start_consult'('/no/such/a', 0), '\$source_file_property'('/no/such/a', load_count, V), R = V"
    ),
    (
        "c02",
        "'\$start_consult'('/no/such/b', 1.5), findall(T, '\$time_source_file'('/no/such/b', T, _), L), R = L"
    ),
    (
        "c03",
        "'\$start_consult'('/no/such/c', 0), findall(T, '\$time_source_file'('/no/such/c', T, _), L), R = L"
    ),
    ("c04", "ex('\$start_consult'('/no/such/d', a), R)"),
    ("c05", "ex('\$start_consult'(_, 0), R)"),
    (
        "c06",
        "'\$start_consult'('/no/such/e', 5), findall(T, '\$time_source_file'('/no/such/e', T, _), L), R = L"
    ),
    ("c07", "( '\$end_consult'('/no/such/never') -> R = yes ; R = no )"),
    (
        "c08",
        "'\$start_consult'('/no/such/f', 0), ( '\$fixup_reconsult'('/no/such/f') -> R = yes ; R = no )"
    ),
    ("c09", "( '\$fixup_reconsult'('/no/such/never') -> R = yes ; R = no )"),
    (
        "c10",
        "'\$start_consult'('/no/such/g', 0), ( '\$end_consult'('/no/such/g') -> R = yes ; R = no )"
    ),
    ("c11", "ex('\$start_consult'(1, 0), R)"),
    ("c12", "ex('\$end_consult'(_), R)"),
    ("c13", "ex('\$fixup_reconsult'(1), R)"),
    (
        "c14",
        "'\$start_consult'('/no/such/h', 0), '\$source_file_property'('/no/such/h', loaded, V), ( float(V) -> R = flt ; R = V )"
    ),
    (
        "c15",
        "'\$start_consult'('/no/such/i', 0), findall(Ty, '\$time_source_file'('/no/such/i', _, Ty), L), R = L"
    ),
    (
        "c16",
        "'\$start_consult'('/no/such/j', 0), '\$source_file_property'('/no/such/j', number_of_clauses, V), R = V"
    ),
    # ---- '$start_aux'/2 and '$end_aux'/2 (pl-comp.c:5197; each row its own file; every $end_aux follows a $start_aux, as the loader does)
    ("a01", "'\$start_aux'('/no/such/a01', C), '\$end_aux'('/no/such/a01', C), R = C"),
    (
        "a02",
        "'\$start_aux'('/no/such/a02', _), '\$end_aux'('/no/such/a02', user:foo/1), '\$start_aux'('/no/such/a02', C), '\$end_aux'('/no/such/a02', C), R = C"
    ),
    # a06/a12 (an end_aux whose PI is no PI) are NOT rows: swipl leaves the error pending past the false return (it surfaces in a later
    # foreign call, "did not clear exception"); the kernel raises it at once.
    (
        "a03",
        "'\$start_aux'('/no/such/a03', _), '\$end_aux'('/no/such/a03', user:nothere/0), '\$start_aux'('/no/such/a03', C), '\$end_aux'('/no/such/a03', C), R = C"
    ),
    ("a04", "ex('\$start_aux'(_, _), R)"),
    ("a05", "ex('\$start_aux'(1, _), R)"),
    (
        "a07",
        "'\$start_aux'('/no/such/a07', _), '\$end_aux'('/no/such/a07', user:foo/1), '\$start_aux'('/no/such/a07', C), '\$end_aux'('/no/such/a07', []), '\$start_aux'('/no/such/a07', C2), '\$end_aux'('/no/such/a07', C2), R = C-C2"
    ),
    (
        "a08",
        "'\$start_aux'('/no/such/a08', _), '\$end_aux'('/no/such/a08', foo/1), '\$start_aux'('/no/such/a08', C), '\$end_aux'('/no/such/a08', C), R = C"
    ),
    (
        "a09",
        "'\$start_aux'('/no/such/a09', _), '\$end_aux'('/no/such/a09', []), ( '\$start_aux'('/no/such/a09', user:foo/1) -> R = yes ; R = no ), '\$end_aux'('/no/such/a09', [])"
    ),
    (
        "a10",
        "'\$start_aux'('/no/such/a10', _), ( '\$end_aux'('/no/such/a10', user:zork/7) -> R = yes ; R = no )"
    ),
    (
        "a11",
        "'\$start_aux'('/no/such/a11', _), '\$end_aux'('/no/such/a11', user:foo/1), '\$start_aux'('/no/such/a11', user:foo/1), '\$end_aux'('/no/such/a11', []), R = bound_ok"
    ),
    (
        "a13",
        "'\$start_aux'('/no/such/a13', _), '\$end_aux'('/no/such/a13', user:foo(_)), '\$start_aux'('/no/such/a13', C), '\$end_aux'('/no/such/a13', C), R = C"
    ),
    (
        "a14",
        "'\$start_aux'('/no/such/a14', _), '\$end_aux'('/no/such/a14', system:atom_length/2), '\$start_aux'('/no/such/a14', C), '\$end_aux'('/no/such/a14', C), R = C"
    ),
    # a15: visibleProcedure follows the default import (user:atom_length/2 -> system:atom_length/2; swipl 10.1.19)
    (
        "a15",
        "'\$start_aux'('/no/such/a15', _), '\$end_aux'('/no/such/a15', user:atom_length/2), '\$start_aux'('/no/such/a15', C), '\$end_aux'('/no/such/a15', C), R = C"
    ),
    # a16: a qualifier naming no module resolves like user (swipl 10.1.19 CREATES the module nomod, and so does the kernel's PL_strip_module)
    (
        "a16",
        "'\$start_aux'('/no/such/a16', _), '\$end_aux'('/no/such/a16', nomod:atom_length/2), '\$start_aux'('/no/such/a16', C), '\$end_aux'('/no/such/a16', C), R = C"
    ),
    # a17: `$start_aux` answers [] for a current predicate that is no longer defined: emptied and made static again (abolish/1 waits for R2; pl-proc.jl:29) (pl-comp.c:5205 isDefinedProcedure; swipl 10.1.19: [])
    (
        "a17",
        "assertz(a17p(1)), '\$start_aux'('/no/such/a17', _), '\$end_aux'('/no/such/a17', user:a17p/1), retract(a17p(1)), '\$set_predicate_attribute'(a17p(_), dynamic, false), '\$start_aux'('/no/such/a17', C), '\$end_aux'('/no/such/a17', C), R = C"
    ),
    # l01: source_location/2 inside the directive at the program's end: the file and the 1-based line (pl-file.c:5805)
    ("l01", "sloc(F, L), ( F == '@FILE@' -> R = L-same ; R = L-F )"),
    # LAST: nothing follows (the program's last row)
    ("z01", "'\$source_file_predicates'('@FILE@', [user:H|_]), functor(H, N, A), R = N/A")
]

# ---- the kernel's lines: for each case, `<name> <answers>`
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
    return out
end

# swipl's side. `enc/3` as the kernel's `enc` (a clause blob is `clref`, any other blob `blob`).
const DRIVER = raw"""
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

"Run swipl on a program file: its output lines."
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# ---- the kernel's calls, one built-in at a time (the white-box testsets)
"Call the system predicate `name` on `args`: `(status, answers)`; status `:true`, `:false` or `:exception` (the ball is the answer)."
function kcall(gd::LK.PL_global_data{T}, ld, name::String, args::Vector{T}) where {T}
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


_swipl() = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")

@testset "the source-file predicates == live swipl, through a program" begin
    if _swipl() === nothing
        @info "SOURCE FILE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_CASES) >= 96 && allunique(first.(_CASES)) && _CASES[end][1] == "z01"     # the table is whole
    else
        names = ["t_$(id)" for (id, _) in _CASES]
        f = joinpath(realpath(mktempdir()), "p.pl")
        text =
            _PROGRAM *
            join(["t_$(id)(R) :- ( $g -> true ).\n" for (id, g) in _CASES])
        write(f, replace(text, "@FILE@" => f))
        kl = kernel_lines(f, names)
        sw = swipl_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw)
        for (k, s) in zip(kl, sw)
            @test k == s
        end
        # not a vacuous agreement: each kind of answer is in swipl's own lines, and the order is the reverse one
        @test any(l -> startswith(l, "t_s01 ") && occursin(_codes("same"), l), sw)
        @test any(l -> startswith(l, "t_s02 ") && occursin(_codes("fails"), l), sw)            # not transparent
        @test any(l -> startswith(l, "t_p01 ") && occursin(_codes("baz"), l), sw)
        p01 = first(filter(l -> startswith(l, "t_p01 "), sw))
        @test findfirst(_codes("baz"), p01) !== nothing &&
            findfirst(_codes("baz"), p01) < findfirst(_codes("foo"), p01) &&
            findfirst(_codes("bar"), p01) < findfirst(_codes("foo"), p01)               # [baz, bar, foo, d]: newest first
        # measured on swipl 10.1.19 (2026-10-29): domain f08 f18 g04; existence g02 g07; instantiation s07 p03 f10 f12 g05 g06 g08 c05 c12 a04;
        # type s08 s09 p04 f09 f11 g03 g09 c04 c11 c13 a05
        @test count(l -> occursin(_codes("domain_error"), l), sw) == 3
        @test count(l -> occursin(_codes("existence_error"), l), sw) == 2
        @test count(l -> occursin(_codes("instantiation_error"), l), sw) == 10
        @test count(l -> occursin(_codes("type_error"), l), sw) == 11
        @test any(
            l ->
                startswith(l, "t_t01 ") && occursin(_codes("user"), l) &&
                occursin(_codes("flt"), l),
            sw
        )
        @test any(l -> startswith(l, "t_l01 ") && occursin(_codes("same"), l), sw)           # source_location/2 inside the directive
        @test any(l -> startswith(l, "t_a17 ") && occursin("nil", l), sw)                   # [] for the abolished current predicate
        @test any(l -> startswith(l, "t_c02 ") && occursin("f1.5", l), sw)
        @test any(l -> startswith(l, "t_c03 ") && occursin("i0", l), sw)
        @test startswith(last(sw), "t_z01 ")
    end
end

# ---- white-box: what swipl cannot be asked, or shows only through the loader
function _loaded(src::String)
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = joinpath(realpath(mktempdir()), "w.pl")
    write(f, src)
    st, ball, _ = LK.load_file!(gd, ld, f)
    @assert st === :ok
    return gd, ld, f
end

function _load_more!(gd, ld, src::String)
    f = joinpath(realpath(mktempdir()), "x.pl")
    write(f, src)
    st, _, _ = LK.load_file!(gd, ld, f)
    @assert st === :ok
    return f
end

_f(name, args...) = mk_expr(_TL, _TL[_tls(name), args...])
_v() = mk_var(_TL, LK.fresh_var_keys!(1))

@testset "the source file of a loaded file: counts, the module list, the highest index" begin
    gd, ld, f = _loaded("foo(1).\nfoo(2).\nbar(1).\n")
    sf = LK.lookupSourceFile(gd, _tls(f), false)
    @test sf !== nothing && sf.count == 1 && sf.number_of_clauses == 3 && sf.isfile
    @test !sf.system && !sf.from_state && !sf.resource                       # GD->bootsession is off: all three false
    @test LK.highSourceFileIndex(gd) == sf.index + 1 == 2
    @test LK.indexToSourceFile(gd, 0) === nothing && LK.indexToSourceFile(gd, 1) === sf
    @test isempty(sf.modules)
    m1 = LK.lookupModule(gd, _tls("lb2_m1"))
    m2 = LK.lookupModule(gd, _tls("lb2_m2"))
    @test LK.addModuleSourceFile(sf, m1) && LK.addModuleSourceFile(sf, m2) &&
        LK.addModuleSourceFile(sf, m1)
    @test sf.modules == [m1, m2]                                              # at the END, once (pl-srcfile.c:465)
    LK.releaseSourceFile(sf)
    # a boot-session database makes the files it creates system / from_state / resource files
    gd2 = LK.PL_global_data{_TL}()
    gd2.bootsession = true
    sf2 = LK.lookupSourceFile(gd2, _tls("/b"), true)
    @test sf2.system && sf2.from_state && sf2.resource
end

@testset "'\$source_file_property'(+Unknown, loaded, -V) fails (H10: swipl dies on it); the others answer their empty value" begin
    gd, ld, f = _loaded("foo(1).\n")
    for (prop, want) in (
        ("load_count", 0),
        ("number_of_clauses", 0),
        ("resource", "false"),
        ("from_state", "false"),
        ("reloading", "false")
    )
        st, ans = kcall(
            gd, ld, "\$source_file_property", _TL[_tls("/no/such"), _tls(prop), _v()]
        )
        # a count is an integer, a flag the atom true / false (PL_unify_bool)
        @test st === :true && (
            if want isa Integer
                lk_value(ans[3]) == want
            else
                sym_key(ans[3]) == sym_key(_tls(want))
            end
        )
    end
    st, _ = kcall(
        gd, ld, "\$source_file_property", _TL[_tls("/no/such"), _tls("loaded"), _v()]
    )
    @test st === :false
    st, ans = kcall(gd, ld, "\$source_file_property", _TL[_tls(f), _tls("loaded"), _v()])
    @test st === :true && lk_value(ans[3]) isa Float64 && lk_value(ans[3]) > 0
    st, ans = kcall(
        gd, ld, "\$source_file_property", _TL[_tls(f), _tls("load_count"), _v()]
    )
    @test st === :true && lk_value(ans[3]) == 1
end

@testset "'\$source_file_predicates'/2 answers the newest predicate first; '\$source_file'/2 resolves in `system` unless qualified" begin
    gd, ld, f = _loaded("foo(1).\nbar(1).\nbaz.\n")
    st, ans = kcall(gd, ld, "\$source_file_predicates", _TL[_tls(f), _v()])
    @test st === :true
    line = enc(ans[2])
    pos = [first(findfirst(_codes(n), line)) for n in ("baz", "bar", "foo")]
    @test pos == sort(pos) && allunique(pos)                                  # [user:baz, user:bar, user:foo]: the newest first
    q(m, h) = _f(":", _tls(m), h)
    st, ans = kcall(gd, ld, "\$source_file", _TL[q("user", _f("foo", _v())), _v()])
    @test st === :true && sym_key(ans[2]) == sym_key(_tls(f))
    st, _ = kcall(gd, ld, "\$source_file", _TL[_f("foo", _v()), _v()])
    @test st === :false                                                       # context `system`
    st, ans = kcall(gd, ld, "\$source_file", _TL[q("nomod", _f("foo", _v())), _v()])
    @test st === :true && sym_key(ans[2]) == sym_key(_tls(f))                 # an unknown module name is `user`
    @test LK.isCurrentModule(gd.modules, _tls("nomod")) === nothing           # and no module is created
    st, _ = kcall(gd, ld, "\$source_file", _TL[q("user", _f("qux", _v())), _v()])
    @test st === :false
end

@testset "'\$start_consult'/2 refuses a reconsult by name (LB6)" begin
    gd, ld, f = _loaded("foo(1).\n")
    e = try
        kcall(gd, ld, "\$start_consult", _TL[_tls(f), lk_gnd(_TL, 0)])
        nothing
    catch ex
        ex
    end
    @test e isa LK.NotPortedError && e.step == "LB6"
end

@testset "system mode (H5): access_level, the lock of a predicate defined in it, isStaticSystemProcedure" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    @test !LK.SYSTEM_MODE(ld)
    st, ans = kcall(gd, ld, "current_prolog_flag", _TL[_tls("access_level"), _v()])
    @test st === :true && sym_key(ans[2]) == sym_key(_tls("user"))
    # user mode: a static system procedure is found, and a new user predicate is not locked
    @test LK.isStaticSystemProcedure(gd, ld, sym_key(_tls("atom_length")), 2) !== nothing
    _load_more!(gd, ld, "lb2_u(1).\n")                      # a LOADED clause (pl-comp.c:4979 is inside `if ( loc )`: assertz does not lock)
    pu = LK.isCurrentProcedure(sym_key(_tls("lb2_u")), 1, LK.MODULE_user(gd))
    @test (pu.definition.flags & LK.P_LOCKED) == 0
    _load_more!(gd, ld, ":- dynamic lb2_e/1.\n")             # a predicate defined by a declaration alone (setAttrProcedureSource -> associateSource)
    pe = LK.isCurrentProcedure(sym_key(_tls("lb2_e")), 1, LK.MODULE_user(gd))
    @test (pe.definition.flags & LK.P_DYNAMIC) != 0 &&
        (pe.definition.flags & LK.P_LOCKED) == 0
    LK.setAccessLevel!(ld, LK.ACCESS_LEVEL_SYSTEM)
    @test LK.SYSTEM_MODE(ld)
    st, ans = kcall(gd, ld, "current_prolog_flag", _TL[_tls("access_level"), _v()])
    @test st === :true && sym_key(ans[2]) == sym_key(_tls("system"))
    @test LK.isStaticSystemProcedure(gd, ld, sym_key(_tls("atom_length")), 2) === nothing
    _load_more!(gd, ld, "lb2_s(1).\n")                      # a LOADED clause (pl-comp.c:4979 is inside `if ( loc )`: assertz does not lock)
    ps = LK.isCurrentProcedure(sym_key(_tls("lb2_s")), 1, LK.MODULE_user(gd))
    @test (ps.definition.flags & LK.P_LOCKED) != 0 &&
        (ps.definition.flags & LK.HIDE_CHILDS) != 0
    _load_more!(gd, ld, ":- dynamic lb2_d/1.\n")             # swipl 10.1.19: '\$get_predicate_attribute'(lb2_d(_), locked, 1) and hide_childs 1 (measured)
    pd = LK.isCurrentProcedure(sym_key(_tls("lb2_d")), 1, LK.MODULE_user(gd))
    @test (pd.definition.flags & LK.P_DYNAMIC) != 0 &&
        (pd.definition.flags & LK.P_LOCKED) != 0 &&
        (pd.definition.flags & LK.HIDE_CHILDS) != 0
    LK.setAccessLevel!(ld, LK.ACCESS_LEVEL_USER)
    @test !LK.SYSTEM_MODE(ld)
    st, ans = kcall(gd, ld, "current_prolog_flag", _TL[_tls("access_level"), _v()])
    @test st === :true && sym_key(ans[2]) == sym_key(_tls("user"))
end

# ---- KNOWN DIFFERENCE, TEMPORARY (owner step LB6, audit D-0248): releaseSourceFile does not destroy an unreferenced, empty file.
# swipl 10.1.19 (live, 2026-10-29):  '$start_consult'('/no/such/d01', 0), '$end_consult'('/no/such/d01')  then
#   '$source_file_property'('/no/such/d01', load_count, V)  gives V = 0, and
#   findall(F, '$time_source_file'(F, _, _), L)  has no '/no/such/d01' (so `source_file/1` does not list it either);
# the kernel keeps the record: load_count 1 and the file is enumerated. These rows PIN THE KERNEL'S CURRENT ANSWER.
# LB6: port destroySourceFile (files_array with holes), flip these rows to swipl's answers.
@testset "KNOWN DIFFERENCE (until LB6: destroySourceFile): an empty file consulted once keeps its record" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = _tls("/no/such/d01")
    st, _ = kcall(gd, ld, "\$start_consult", _TL[f, lk_gnd(_TL, 0)])
    @test st === :true
    st, _ = kcall(gd, ld, "\$end_consult", _TL[f])
    @test st === :true
    st, ans = kcall(gd, ld, "\$source_file_property", _TL[f, _tls("load_count"), _v()])
    @test st === :true && lk_value(ans[3]) == 1                               # swipl: 0
    st, ans = kcall(gd, ld, "\$time_source_file", _TL[f, _v(), _v()])
    @test st === :true                                                        # swipl: fails (the file is gone)
    st, ans = kcall(gd, ld, "\$time_source_file", _TL[_v(), _v(), _v()])
    @test st === :true && sym_key(ans[1]) == sym_key(f)                       # the enumeration (source_file/1's base) lists it; swipl: not
end

# ---- white-box: the reference count stays balanced, and a file nothing has started (count 0) is not listed
@testset "the source-file predicates release the reference they take; a count-0 file is skipped" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = _tls("/no/such/r01")
    refs() = LK.lookupSourceFile_unlocked(gd, f, false).references
    st, _ = kcall(gd, ld, "\$start_consult", _TL[f, lk_gnd(_TL, 0)])
    @test st === :true && refs() == 1                                         # startConsult's reference only
    for (name, args) in (
        ("\$source_file_property", _TL[f, _tls("load_count"), _v()]),
        ("\$source_file_property", _TL[f, _tls("loaded"), _v()]),
        ("\$set_source_file", _TL[f, _tls("resource"), _tls("true")]),
        ("\$source_file_predicates", _TL[f, _v()]),
        ("\$fixup_reconsult", _TL[f])
    )
        st, _ = kcall(gd, ld, name, args)
        @test st === :true && refs() == 1
    end
    st, _ = kcall(gd, ld, "\$set_source_file", _TL[f, _tls("nope"), _tls("true")])
    @test st === :exception && refs() == 1
    st, _ = kcall(gd, ld, "\$end_consult", _TL[f])
    @test st === :true && refs() == 0
    # a file that exists but has count 0 (looked up with create, never started) is neither listed nor asked for its predicates
    gd2 = LK.PL_global_data{_TL}()
    ld2 = LK.PL_local_data{_TL}(gd2)
    sf0 = LK.lookupSourceFile(gd2, _tls("/no/such/r02"), true)
    @test sf0.count == 0
    st, _ = kcall(gd2, ld2, "\$time_source_file", _TL[_v(), _v(), _v()])
    @test st === :false
    st, _ = kcall(gd2, ld2, "\$source_file_predicates", _TL[_tls("/no/such/r02"), _v()])
    @test st === :false
    st, _ = kcall(
        gd2, ld2, "\$source_file_property", _TL[_tls("/no/such/r02"), _tls("loaded"), _v()]
    )
    @test st === :false                                                       # pl-srcfile.c:726: ltime == 0.0 is false
    LK.releaseSourceFile(sf0)
end
