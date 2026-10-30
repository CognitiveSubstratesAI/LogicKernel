# ORIGINAL: R2's D1 gate — clause references as blobs (pl-dbref.c), assert/2, asserta/2, assertz/2, erase/1 and the Ref of '$record_clause'/4 against swipl 10.1.19; upstream tests them through Prolog (tests/db/test_dbref.pl, unit assert2), which needs the loader and plunit (R2).
# test/db/test_clause_ref_swipl.jl — D1's gate (audit D-0227 item 6, design evidence/r2/design/flags_rest.md §4 D11):
#   * ROWS, as a program (the pattern of test/files/test_open_close_swipl.jl): each case is a predicate `t_<id>(R)`;
#     the kernel consults the program and enumerates the answers of every `t_<id>/1`, swipl does the same through
#     a driver, and the lines are compared. EVERY expected value is swipl's own answer (the driver runs live). A
#     clause reference is `clref` in the answer lines, and the atom `term_to_atom/2` makes of one is compared by
#     its SHAPE, `<clause>(0x…)`: the address is no value anyone compares. The `assert2` unit of tests/db/test_dbref.pl
#     is rows b01-b04 (bound, erase, double_erase, retract_erase) under those names; the `recorded` unit is D2's;
#   * WHITE-BOX: the clause blob type is registered by the database (its rank below `mutex`, above `stream`), the
#     payload and the clause table, `acquire_clause_blob`/`release_clause_blob` and the `DBREF_CLAUSE` mark,
#     `lookup_clref`/`clause_clref` and their inverse, `PL_get_dbref`/`PL_get_clref`/`PL_is_dbref` on a live, an
#     erased and a foreign term, `erase/1` and the blob form on a term type with a small payload, the Ref of
#     `'$record_clause'/4` and the clause reference `compiler_warnings/2` carries.
# NOT HERE (waits for clause/3, nth_clause/3 and `instance/2`): two references to one clause (`clause(H, B, Ref)`
# twice), the Ref of '$record_clause'/4 read by `clause/2`-family predicates (loader_boot.md H7), `instance/2`.
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
# (`Bool` is a grounded value of no SWI type: the blob test must tell it from a clause blob)
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

# An atom that is a clause reference's written form is compared by its shape: swipl's address and the kernel's differ.
function _norm(line::AbstractString)::String
    return replace(
        String(line),
        r"a\[([0-9,]+)\]" => function (m)
            try
                txt = String(Char.(parse.(Int, split(m[3:(end - 1)], ','))))
                return if occursin(r"^<clause>\(0x[0-9a-f]+\)$", txt)
                    "aclauseform"
                else
                    String(m)
                end
            catch
                return String(m)
            end
        end
    )
end

# ---- the program: swipl's rows (`t_<id>(R)`). `st/1` is static; `d/1` and `e/1` are dynamic and emptied before each row
const _PROGRAM = """
:- dynamic d/1, e/1.
st(1).
rset :- retractall(d(_)), retractall(e(_)).
ex(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
btype(S, B) :- ( atom(S) -> B = atom ; atomic(S) -> B = atomic ; B = other ).
"""

# (id, goal). `ex/2` returns `true` or `err(Formal, Context)`.
const _CASES = [
    # ---- assert/2, asserta/2, assertz/2: the reference
    ("a01", "assertz(d(1), Ref), btype(Ref, B), R = B"),
    ("a02", "asserta(d(1), Ref), blob(Ref, T), R = T"),
    ("a03", "assert(d(1), Ref), blob(Ref, T), R = T"),
    ("a04", "assertz(d(1), Ref), term_to_atom(Ref, A), R = A"),
    ("a05", "assertz(d(1), R1), assertz(d(1), R2), ( R1 == R2 -> R = same ; R = diff )"),
    (
        "a06",
        "assertz(d(1), R1), R2 = R1, ( R1 == R2 -> R0 = same ; R0 = diff ), copy_term(R1, R3), ( R1 == R3 -> R3o = same ; R3o = diff ), R = R0-R3o"
    ),
    (
        "a07",
        "assertz(d(1), R1), assertz(d(2), R2), ( R1 = R2 -> R = unified ; R = apart )"
    ),
    ("a08", "ex(assertz(d(1), foo), R)"),
    ("a09", "ex(assertz(d(1), 1), R)"),
    ("a10", "ex(asserta(d(1), \"s\"), R)"),
    ("a11", "assertz(d(1), Ref), ex(assertz(d(2), Ref), R)"),
    ("a12", "ex(assertz(_, _), R)"),
    ("a13", "ex(assertz(1, _), R)"),
    ("a14", "ex(asserta((foo :- 1), _), R)"),
    ("a15", "ex(assertz(st(2), _), R)"),
    ("a16", "ex(assert(st(2), _), R)"),
    ("a17", "asserta(e(1), _), asserta(e(2), _), assertz(e(3), _), findall(X, e(X), L), R = L"),
    (
        "a18",
        "assertz((e(X) :- X > 1), _), ( e(2) -> R0 = yes ; R0 = no ), ( e(1) -> R1 = yes ; R1 = no ), R = R0-R1"
    ),
    (
        "a19",
        "assertz(d(1), Ref), compare(O1, Ref, a), compare(O2, Ref, \"a\"), compare(O3, Ref, 1), compare(O4, Ref, []), compare(O5, Ref, f(x)), compare(O6, Ref, Ref), R = [O1,O2,O3,O4,O5,O6]"
    ),
    (
        "a20",
        "assertz(d(1), Ref), ( atom(Ref) -> A = atom ; A = notatom ), ( atomic(Ref) -> B = atomic ; B = notatomic ), ( callable(Ref) -> C = callable ; C = notcallable ), ( compound(Ref) -> D = compound ; D = notcompound ), ( var(Ref) -> E = var ; E = nonvar ), R = [A,B,C,D,E]"
    ),
    (
        "a21",
        "assertz(d(1), Ref), assertz(e(Ref), _), e(X), ( X == Ref -> R = same ; R = diff )"
    ),
    (
        "a22",
        "assertz(d(1), Ref), findall(Ref, d(_), L), L = [X], ( X == Ref -> R = same ; R = diff )"
    ),
    ("a23", "assertz(d(1), Ref), ex(atom_length(Ref, _), R)"),
    ("a24", "assertz(d(1), Ref), msort([Ref, a, 1, \"s\", f(x), []], L), R = L"),
    ("a25", "assertz(m1:q(1), Ref), blob(Ref, T), erase(Ref), R = T"),
    ("a26", "assertz((e(1) :- true), Ref), erase(Ref), ( e(1) -> R = yes ; R = no )"),
    # ---- erase/1: the assert2 unit of tests/db/test_dbref.pl (b01-b04), and the rest
    ("b01", "ex(assert(d(a), noref), R)"),
    ("b02", "assert(d(a), Ref), erase(Ref), ( d(a) -> R = still ; R = gone )"),
    ("b03", "assert(d(a), Ref), erase(Ref), ( erase(Ref) -> R = again ; R = no )"),
    ("b04", "assert(d(a), Ref), retractall(d(_)), ( erase(Ref) -> R = yes ; R = no )"),
    ("e01", "ex(erase(foo), R)"),
    ("e02", "ex(erase(_), R)"),
    ("e03", "ex(erase(1), R)"),
    ("e04", "ex(erase(\"s\"), R)"),
    ("e05", "ex(erase(f(x)), R)"),
    ("e06", "ex(erase([]), R)"),
    ("e07", "assertz(d(1), Ref), erase(Ref), blob(Ref, T), R = T"),
    ("e08", "assertz(d(1), Ref), erase(Ref), term_to_atom(Ref, A), R = A"),
    (
        "e09",
        "assertz(d(1), Ref), erase(Ref), assertz(d(1), Ref2), ( Ref == Ref2 -> R = same ; R = diff )"
    ),
    ("e10", "assertz(d(1), Ref), retract(d(1)), ( erase(Ref) -> R = yes ; R = no )"),
    ("e11", "assertz(d(1), Ref), erase(Ref), ( retract(d(1)) -> R = yes ; R = no )"),
    (
        "e12",
        "assertz(d(1), _), assertz(d(2), R2), ( d(_), erase(R2), fail ; true ), findall(Y, d(Y), L), R = L"
    ),
    (
        "e13",
        "assertz(e(1), _), assertz(e(2), R2), findall(X, ( e(X), erase(R2) ), L), R = L"
    ),
    (
        "e14",
        "assertz(e(1), R1), assertz(e(2), R2), erase(R1), findall(X, e(X), L1), erase(R2), findall(Y, e(Y), L2), R = L1-L2"
    ),
    (
        "e15",
        "assertz(d(1), R1), assertz(d(2), R2), erase(R2), ( erase(R1) -> A = yes ; A = no ), findall(X, d(X), L), R = A-L"
    ),
    # ---- the Ref of '$record_clause'/4: a clause of a file that is loading in neither system (source File:Line)
    (
        "r01",
        "'\$record_clause'(rs1(1), o, f:3, Ref), blob(Ref, T), R = T"
    ),
    ("r02", "'\$record_clause'(rs2(1), o, f:3, Ref), ex(erase(Ref), R)"),
    (
        "r03",
        "'\$record_clause'(rs3(1), o, f:3, R1), '\$record_clause'(rs4(1), o, f:3, R2), ( R1 == R2 -> R = same ; R = diff )"
    ),
    (
        "r04",
        "( '\$record_clause'(rs5(1), o, f:3, foo) -> R0 = yes ; R0 = no ), ( rs5(1) -> R1 = defined ; R1 = missing ), R = R0-R1"
    ),
    (
        "r05",
        "'\$record_clause'(rs6(1), o, f:3, Ref), ( rs6(X) -> R = X ; R = none ), blob(Ref, _)"
    ),
    ("r06", "ex('\$record_clause'(rs7(1), 1, f:3, _), R)"),
    ("r07", "ex('\$record_clause'(rs8(1), o, 3, _), R)"),
    # boot/init.pl:1887,1901 (`'$open_source'`/`'$close_source'`): a stream blob in a dynamic fact, asserta/2's Ref erased
    (
        "i01",
        "open('/dev/null', read, S), asserta(e(S), Ref), e(X), ( X == S -> R0 = same ; R0 = diff ), erase(Ref), ( e(_) -> R1 = left ; R1 = gone ), close(S), R = R0-R1"
    ),
    # LAST: nothing follows (the program's last row)
    ("z01", "assertz(d(1), Ref), blob(Ref, T), R = T")
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

@testset "clause references == live swipl, through a program: assert/2, erase/1, '\$record_clause'/4" begin
    if _swipl() === nothing
        @info "CLAUSE REFERENCE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_CASES) >= 50 && allunique(first.(_CASES)) && _CASES[end][1] == "z01"     # the table is whole
    else
        names = ["t_$(id)" for (id, _) in _CASES]
        text =
            _PROGRAM *
            join(["t_$(id)(R) :- rset, ( $g -> true ).\n" for (id, g) in _CASES])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        kl = kernel_lines(f, names)
        sw = swipl_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw)
        for (k, s) in zip(kl, sw)
            @test (_norm(k)) == (_norm(s))
        end
        # not a vacuous agreement: each kind of answer is in swipl's own lines
        @test count(l -> occursin("aclauseform", _norm(l)), sw) >= 2             # a04, e08: the written form
        @test count(l -> occursin("clref", l), sw) >= 4                          # a reference inside an answer (a11, a23, a24, r02)
        @test count(l -> occursin(_codes("db_reference"), l), sw) == 5           # e01, e03-e06
        @test count(l -> occursin(_codes("uninstantiation_error"), l), sw) == 5  # a08-a11, b01
        @test count(l -> occursin(_codes("permission_error"), l), sw) >= 3       # a15, a16, r02
        @test count(l -> occursin(_codes("instantiation_error"), l), sw) >= 2    # a12, e02
        @test any(l -> startswith(l, "t_a17 ") && occursin("i2", l), sw)         # asserta's order
        @test any(l -> startswith(l, "t_b02 ") && occursin(_codes("gone"), l), sw)
        @test any(l -> startswith(l, "t_b03 ") && occursin(_codes("no"), l), sw)
        @test count(l -> occursin(_codes("clause"), l), sw) >= 6                 # blob/2 answers: a02, a03, a25, e07, r01, z01
        @test startswith(last(sw), "t_z01 ")
    end
end

@testset "the clause blob type is registered by the database, below mutex and above stream (pl-setup.c initDBRef)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    reg = LK._blob_registration(gd.atoms, LK.clause_blob)
    @test reg !== nothing && reg.rank < 0 && reg.padding == 0
    @test reg.atom_name == LK.builtin_atom("clause")                  # ATOM_clause: no new atom
    # a stream blob type is registered at the first stream (S1), after the database: lower rank, sorts first
    LK.lookupBlob(gd.atoms, UInt8[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 16, LK.stream_blob)
    sreg = LK._blob_registration(gd.atoms, LK.stream_blob)
    @test sreg.rank < reg.rank
    # the type is the one the registration table holds once (a second registration is a no-op)
    n = length(gd.atoms.types)
    LK.initDBRef!(gd.atoms)
    @test length(gd.atoms.types) == n
end

@testset "the payload, the clause table and the mark: lookup_clref, clause_clref, acquire/release" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    v() = mk_var(_TL, LK.fresh_var_keys!(1))
    d(n) = mk_expr(_TL, _TL[_tls("d"), lk_gnd(_TL, n)])
    @test isempty(gd.clause_refs) && isempty(gd.clause_serials)
    st, a1 = kcall(gd, ld, "assertz", _TL[d(1), v()])
    st2, a2 = kcall(gd, ld, "asserta", _TL[d(2), v()])
    @test st === :true && st2 === :true
    r1, r2 = a1[2], a2[2]
    @test is_blob(r1) && is_blob(r2) && blob_type(r1) === :clause && blob_type(r2) === :clause
    @test blob_handle(r1) != blob_handle(r2) && blob_rank(r1) == blob_rank(r2) < 0
    # the table: two clauses, numbered in the order of their first reference; the payload is the number
    @test length(gd.clause_refs) == 2 && length(gd.clause_serials) == 2
    c1, c2 = LK.clause_clref(gd, r1), LK.clause_clref(gd, r2)
    @test c1 isa LK.Clause{_TL} && c2 isa LK.Clause{_TL} && c1 !== c2
    @test gd.clause_refs[1] === c1 && gd.clause_refs[2] === c2
    @test gd.clause_serials[c1] == 1 && gd.clause_serials[c2] == 2
    at1 = LK.atomValue(gd.atoms, blob_handle(r1))
    @test at1.type === LK.clause_blob && at1.name == LK._clref_bytes(1) && length(at1.name) == 8
    # one atom per clause: looking it up again gives the same blob, no new table entry
    @test blob_handle(LK.lookup_clref(gd, c1)) == blob_handle(r1)
    @test sym_key(LK.lookup_clref(gd, c2)) == sym_key(r2)
    @test length(gd.clause_refs) == 2
    # the clause is the one asserted: `d(1)` was added at the end, `d(2)` at the start of the same predicate
    @test c1.predicate === c2.predicate
    @test c1.predicate.impl_clauses.first_clause.clause === c2
    @test c1.predicate.impl_clauses.last_clause.clause === c1
    # the mark: set by the first reference (`acquire_clause_blob`), cleared by `release_clause_blob`
    @test (c1.flags & LK.DBREF_CLAUSE) != 0 && (c2.flags & LK.DBREF_CLAUSE) != 0
    @test LK.release_clause_blob(gd, r1) === true
    @test (c1.flags & LK.DBREF_CLAUSE) == 0 && (c2.flags & LK.DBREF_CLAUSE) != 0
    LK.lookup_clref(gd, c1)                                    # the atom exists: found, not created, so no acquire
    @test (c1.flags & LK.DBREF_CLAUSE) == 0
    LK.acquire_clause_blob(gd, r1)
    @test (c1.flags & LK.DBREF_CLAUSE) != 0
    # a term that is no clause blob names no clause: a text atom, `[]`, a number, a blob of another type
    @test LK.clause_clref(gd, _tls(:clause)) === nothing
    @test LK.clause_clref(gd, mk_nil(_TL)) === nothing
    @test LK.clause_clref(gd, lk_gnd(_TL, 1)) === nothing
    otype = LK.PL_blob_t(LK.PL_BLOB_UNIQUE, "d1_other")
    ow, _ = LK.lookupBlob(gd.atoms, UInt8[1, 0, 0, 0, 0, 0, 0, 0], 8, otype)
    @test LK.clause_clref(gd, LK._blob_term!(gd.atoms, gd.atom_symbols, _TL, ow)) === nothing
    # the stream blob type is another type with the same payload shape: not a clause
    sw, _ = LK.lookupBlob(gd.atoms, UInt8[1, 0, 0, 0, 0, 0, 0, 0], 8, LK.stream_blob)
    @test LK.clause_clref(gd, LK._blob_term!(gd.atoms, gd.atom_symbols, _TL, sw)) === nothing
end

@testset "PL_get_dbref, PL_get_clref and PL_is_dbref: a live clause, an erased one, and what is no reference" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    v() = mk_var(_TL, LK.fresh_var_keys!(1))
    d(n) = mk_expr(_TL, _TL[_tls("d"), lk_gnd(_TL, n)])
    st, a1 = kcall(gd, ld, "assertz", _TL[d(1), v()])
    @test st === :true
    r1 = a1[2]
    c1 = LK.clause_clref(gd, r1)
    ref(x) = (t = LK.PL_new_term_refs(ld, 1); LK.putSlotValue!(ld, t + 1, x, LK.PutVarMap()); t)
    t = ref(r1)
    @test LK.PL_is_dbref(gd, ld, t)
    got = LK.PL_get_dbref(gd, ld, t)
    @test got !== nothing && got[1] == LK.DB_REF_CLAUSE && got[2] === c1
    rc, cl = LK.PL_get_clref(gd, ld, t)
    @test rc == 1 && cl === c1
    # not a reference: PL_get_dbref and PL_get_clref raise type_error(db_reference, T) (context: none, outside a query)
    for bad in (_tls(:foo), lk_gnd(_TL, "s"), mk_nil(_TL))
        tb = ref(bad)
        @test LK.PL_get_dbref(gd, ld, tb) === nothing
        ball = lk_answer(ld, LK.PL_exception(ld, 0))
        @test occursin("c" * _codes("type_error") * "/2(a" * _codes("db_reference") * ",", enc(ball))
        LK.PL_clear_exception(ld)
        @test LK.PL_get_clref(gd, ld, tb) == (0, nothing)
        ball = lk_answer(ld, LK.PL_exception(ld, 0))
        @test occursin("c" * _codes("type_error") * "/2(a" * _codes("db_reference") * ",", enc(ball))
        LK.PL_clear_exception(ld)
    end
    tv = ref(v())                                             # an unbound variable: instantiation_error
    @test LK.PL_get_dbref(gd, ld, tv) === nothing
    @test occursin(_codes("instantiation_error"), enc(lk_answer(ld, LK.PL_exception(ld, 0))))
    LK.PL_clear_exception(ld)
    # …and PL_is_dbref is false, quietly
    @test !LK.PL_is_dbref(gd, ld, ref(_tls(:clause)))
    @test !LK.PL_is_dbref(gd, ld, ref(lk_gnd(_TL, 1)))
    @test !LK.PL_is_dbref(gd, ld, ref(v()))
    # the clause is erased (by erase/1): PL_get_clref says -1 and keeps the clause, PL_get_dbref is NULL (no error)
    st, _ = kcall(gd, ld, "erase", _TL[r1])
    @test st === :true && (c1.flags & LK.CL_ERASED) != 0
    rc, cl = LK.PL_get_clref(gd, ld, t)
    @test rc == -1 && cl === c1
    @test LK.PL_get_dbref(gd, ld, t) === nothing
    @test LK.PL_is_dbref(gd, ld, t)                                  # still a clause blob: erased clauses are named
    # erase/1 of it again fails; of a non-reference raises; the mark is still set (no release without atom GC)
    @test first(kcall(gd, ld, "erase", _TL[r1])) === :false
    @test first(kcall(gd, ld, "erase", _TL[_tls(:foo)])) === :exception
    @test first(kcall(gd, ld, "erase", _TL[lk_gnd(_TL, "s")])) === :exception
    @test (c1.flags & LK.DBREF_CLAUSE) != 0
end

@testset "erase/1 of a clause of a static predicate: permission_error(clause, erase, Ref), context erase/1" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    v() = mk_var(_TL, LK.fresh_var_keys!(1))
    src(f, l) = mk_expr(_TL, _TL[_tls(":"), _tls(f), lk_gnd(_TL, l)])
    # the consult path of '$record_clause'/4 defines a STATIC predicate; its Ref is a clause blob
    st, a = kcall(
        gd, ld, "\$record_clause",
        _TL[mk_expr(_TL, _TL[_tls("rs"), lk_gnd(_TL, 1)]), _tls(:o), src("f", 3), v()]
    )
    @test st === :true && is_blob(a[4]) && blob_type(a[4]) === :clause
    cl = LK.clause_clref(gd, a[4])
    @test cl isa LK.Clause{_TL} && (cl.predicate.flags & LK.P_DYNAMIC) == 0 &&
        (cl.flags & LK.DBREF_CLAUSE) != 0
    st, ball = kcall(gd, ld, "erase", _TL[a[4]])
    @test st === :exception
    e = enc(ball[1])
    @test occursin("c" * _codes("permission_error") * "/3(a" * _codes("clause") * ",a" * _codes("erase") * ",clref)", e)
    @test occursin("c" * _codes("/") * "/2(a" * _codes("erase") * ",i1)", e)       # context(erase/1, _): not system:erase/1
    @test (cl.flags & LK.CL_ERASED) == 0                                          # nothing was erased
    # the Ref is not unified when it is bound to something else: the clause is added, the call fails (pl-comp.c record_clause)
    st, _ = kcall(
        gd, ld, "\$record_clause",
        _TL[mk_expr(_TL, _TL[_tls("rs"), lk_gnd(_TL, 2)]), _tls(:o), src("f", 3), _tls(:foo)]
    )
    @test st === :false
    nclauses = length(gd.clause_refs)
    @test nclauses == 2                                                           # the failing call made its blob too (PL_unify_clref looks it up first)
    # /3 makes no reference
    st, _ = kcall(
        gd, ld, "\$record_clause",
        _TL[mk_expr(_TL, _TL[_tls("rs"), lk_gnd(_TL, 3)]), _tls(:o), src("f", 3)]
    )
    @test st === :true && length(gd.clause_refs) == nclauses
end

@testset "assert/2 on a term type with a small payload: the blob is an atom, no payload type needed" begin
    T0 = lk_term_type(Union{Int64, Float64, String})
    gd = LK.PL_global_data{T0}()
    ld = LK.PL_local_data{T0}(gd)
    v() = mk_var(T0, LK.fresh_var_keys!(1))
    st, a = kcall(gd, ld, "assertz", T0[mk_expr(T0, T0[lk_sym(T0, :d), lk_gnd(T0, 1)]), v()])
    @test st === :true && is_blob(a[2]) && blob_type(a[2]) === :clause
    st, _ = kcall(gd, ld, "erase", T0[a[2]])
    @test st === :true
    st, _ = kcall(gd, ld, "erase", T0[a[2]])
    @test st === :false
end

@testset "compiler_warnings/2 carries the clause reference (pl-comp.c PL_put_clref)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    path = joinpath(mktempdir(), "w.pl")
    write(path, "p(X).\n")                                            # a singleton variable
    st, ball, msgs = LK.load_file!(gd, ld, path)
    @test st === :ok
    ws = [
        m for (k, m) in msgs if kind(m) === EXPR && kind(child(m, 1)) === SYM &&
        !is_blob(child(m, 1)) && sym_text(child(m, 1)) == "compiler_warnings"
    ]
    @test length(ws) == 1
    cref = child(ws[1], 2)
    @test is_blob(cref) && blob_type(cref) === :clause
    cl = LK.clause_clref(gd, cref)
    @test cl isa LK.Clause{_TL} && (cl.flags & LK.DBREF_CLAUSE) != 0
    @test cl.predicate === LK.isCurrentProcedure(sym_key(_tls("p")), 1, LK.MODULE_user(gd)).definition
end
