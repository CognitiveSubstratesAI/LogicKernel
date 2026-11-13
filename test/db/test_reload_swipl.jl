# ORIGINAL: R2's LB6b gate — the reload half of pl-srcfile.c at the loader (startConsult / endConsult / endReconsult / end_reconsult_proc / delete_old_predicates / flush_procedure / unloadFile / destroySourceFile / the registration table's `$unload_file/1`, `$set_source_files/1`, `$clause_from_source/4`, `$flush_predicate/1`, `$flushed_predicate/1`) against swipl 10.1.20 (pin 18168e62); upstream tests it through Prolog (test_reload.pl), which needs the loader (R2).
# test/db/test_reload_swipl.jl — LB6b's rows (evidence/R2/lb6b_handoff.md): TWO parts.
#   * SCENARIOS (S1-S7), compared with swipl: a SCENARIO is a list of steps on ONE file F — `load` (write a text, `consult`) or `unload` (`'$unload_file'(F)`) — and then a
#     program of rows `t_<id>(R)` (`@FILE@` is F) consulted and answered line by line (the design of test/db/test_source_file_swipl.jl): S1 a module reloaded from a
#     version without q/0 (the clauses, the exports, `load_count`, `number_of_clauses`, `reloading`, the module's file); S2 a user file reloaded (clauses kept, inserted,
#     removed, a predicate removed, one new; `'$clause_from_source'/4`); S3 a dynamic and a multifile predicate reloaded; S4 a file unloaded; S5 unloaded and loaded again;
#     S6 `'$flush_predicate'/1` and `'$flushed_predicate'/1` in directives of a reload; S7 the unload of an unknown file.
#   * WHITE-BOX (W1-W13): what swipl cannot be asked — `endReconsult`, `end_reconsult_proc!`, `delete_old_predicates!`, a foreign predicate and a multifile owner at the
#     end of a reload, `fix_module`, `unloadFile!`, `delModuleSourceFile`/`delAllModulesSourceFile_unlocked!`, `$unload_file` of a system file, `$set_source_files`,
#     `$clause_from_source`, `flush_procedure!`, the destroying `releaseSourceFile` and the hole it leaves in the file table, the clause reclamation that gives the source-file
#     references back (`freeClause!` through `cleanDefinition!`).
#   * EXPECTED VALUES: the scenario lines are swipl's answers, PINNED in `_PINNED` (swipl 10.1.20, pin 18168e62, 2026-11-13, LC_ALL=C; the table is written by
#     evidence/R2/gen_reload.py of the audit channel from swipl's own output); with `swipl` on PATH the live answers are compared with the pins too, WITHOUT it
#     (`LOGICKERNEL_NO_SWIPL=1`) the kernel's lines are compared with the pins, so no testset runs with zero assertions. The white-box rows are hand-derived from the
#     upstream code (pl-srcfile.c 18168e62) and carry its line where they depend on it.
#   * UNVERIFIED on the kernel: written without running it (edit-only step); the gate decides.
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "index_testlib.jl"))        # IxDB: a database's global and local data
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

# ---- the scenarios: (id, description, steps, rows). A step is `(:load, text)` or `(:unload, "")`; a row is `(id, goal)`, `@FILE@` is the file's path.
# The program the rows are consulted with: `ex/2` answers `true` or `err(Formal)`.
const _PROG = "ex(G, R) :- catch(( G, R = true ), error(E, _), R = err(E)).\n"

const _SCENS = [
    (
        "S1",
        "a module reloaded from a version without q/0",
        [(:load, ":- module(m1, [p/1, q/0]).\np(a).\np(b).\nq.\n"), (:load, ":- module(m1, [p/1]).\np(a).\np(c).\n")],
        [
            ("m01", "findall(X, m1:p(X), L), R = L"),
            ("m02", "catch(m1:q, error(E, _), R = E)"),
            ("m03", "'\$module_property'(m1, exports(L0)), msort(L0, L), R = L"),
            ("m04", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
            ("m05", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V"),
            ("m06", "'\$source_file_property'('@FILE@', reloading, V), R = V"),
            ("m07", "'\$source_file'(m1:p(_), F), ( F == '@FILE@' -> R = same ; R = F )"),
            ("m08", "( m1:p(b) -> R = yes ; R = no )"),
            ("m09", "( m1:p(c) -> R = yes ; R = no )"),
            ("m10", "'\$source_file_property'('@FILE@', loaded, V), ( float(V) -> R = flt ; R = V )"),
            ("m11", "findall(T, '\$time_source_file'('@FILE@', T, user), L), length(L, N), R = N"),
            ("m12", "( '\$source_file'(m1:q, _) -> R = yes ; R = no )"),
            ("m13", "findall(P, ( '\$source_file_predicates'('@FILE@', L0), '\$member'(m1:H, L0), functor(H, N, A), P = N/A ), L), msort(L, L1), R = L1")
        ]
    ),
    (
        "S2",
        "a user file reloaded: clauses kept, inserted, removed; a predicate removed and one new",
        [(:load, "a(1).\na(2).\na(3).\nb(1).\nc(1).\n"), (:load, "a(1).\na(3).\na(4).\nc(1).\nd(1).\n")],
        [
            ("u01", "findall(X, a(X), L), R = L"),
            ("u02", "catch(b(_), error(E, _), R = E)"),
            ("u03", "findall(X, c(X), L), R = L"),
            ("u04", "findall(X, d(X), L), R = L"),
            ("u05", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
            ("u06", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V"),
            ("u07", "findall(N/A, ( '\$source_file_predicates'('@FILE@', L0), '\$member'(user:H, L0), functor(H, N, A), '\$member'(N, [a,b,c,d]) ), L1), msort(L1, L), R = L"),
            ("u08", "( '\$clause_from_source'('@FILE@', '@FILE@', 3, L) -> length(L, N), R = N ; R = fails )"),
            ("u09", "( '\$clause_from_source'('@FILE@', '@FILE@', 0, L) -> length(L, N), R = N ; R = fails )"),
            ("u10", "( '\$clause_from_source'('@FILE@', '@FILE@', 99, L) -> length(L, N), R = N ; R = fails )"),
            ("u11", "( '\$clause_from_source'('@FILE@', '@FILE@', 2, [C]), '\$get_clause_attribute'(C, line_count, Ln), '\$get_clause_attribute'(C, file, Fl), ( Fl == '@FILE@' -> Fk = same ; Fk = Fl ) -> R = Ln-Fk ; R = fails )"),
            ("u15", "( '\$clause_from_source'('@FILE@', '@FILE@', 1, [C]), '\$get_clause_attribute'(C, line_count, Ln) -> R = Ln ; R = fails )"),
            ("u16", "( '\$clause_from_source'('@FILE@', '@FILE@', 5, [C]), '\$get_clause_attribute'(C, line_count, Ln) -> R = Ln ; R = fails )"),
            ("u12", "( '\$clause_from_source'('/no/such/owner', '@FILE@', 2, _) -> R = yes ; R = no )"),
            ("u13", "ex('\$clause_from_source'(_, '@FILE@', 2, _), R)"),
            ("u14", "( '\$source_file'(user:b(_), _) -> R = yes ; R = no )")
        ]
    ),
    (
        "S3",
        "dynamic and multifile predicates reloaded; a directive after the reload starts",
        [(:load, ":- dynamic dy/1.\n:- multifile mf/1.\n:- dynamic fl/1.\ndy(1).\nmf(1).\n:- ( '\$flushed_predicate'(dy(_)) -> assertz(fl(yes)) ; assertz(fl(no)) ).\n"), (:load, ":- dynamic dy/1.\n:- multifile mf/1.\n:- dynamic fl/1.\ndy(2).\nmf(2).\n:- ( '\$flushed_predicate'(dy(_)) -> assertz(fl(yes)) ; assertz(fl(no)) ).\n")],
        [
            ("d01", "findall(X, dy(X), L), R = L"),
            ("d02", "findall(X, mf(X), L), R = L"),
            ("d03", "findall(X, fl(X), L), R = L"),
            ("d04", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
            ("d05", "'\$get_predicate_attribute'(user:dy(_), dynamic, V), R = V"),
            ("d06", "'\$get_predicate_attribute'(user:mf(_), multifile, V), R = V"),
            ("d07", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V")
        ]
    ),
    (
        "S4",
        "a file unloaded",
        [(:load, ":- module(m4, [p/1]).\np(a).\np(b).\n"), (:unload, "")],
        [
            ("o01", "catch(m4:p(_), error(E, _), R = E)"),
            ("o02", "( '\$source_file_property'('@FILE@', load_count, V) -> R = V ; R = fails )"),
            ("o03", "( '\$time_source_file'('@FILE@', _, _) -> R = yes ; R = no )"),
            ("o04", "( '\$source_file'(m4:p(_), _) -> R = yes ; R = no )"),
            ("o05", "( '\$module_property'(m4, exports(L)) -> R = L ; R = fails )"),
            ("o06", "( '\$source_file_property'('@FILE@', number_of_clauses, V) -> R = V ; R = fails )"),
            ("o07", "( '\$module_property'(m4, file(F)) -> R = F ; R = nofile )")
        ]
    ),
    (
        "S5",
        "a file unloaded and loaded again",
        [(:load, "p(a).\np(b).\nq(1).\n"), (:unload, ""), (:load, "p(c).\n")],
        [
            ("n01", "findall(X, p(X), L), R = L"),
            ("n02", "catch(q(_), error(E, _), R = E)"),
            ("n03", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
            ("n04", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V"),
            ("n05", "'\$source_file_property'('@FILE@', reloading, V), R = V")
        ]
    ),
    (
        "S6",
        "the flush predicates during a reload",
        [(:load, ":- dynamic fl/2.\n:- ( '\$flushed_predicate'(a(_)) -> assertz(fl(f, yes)) ; assertz(fl(f, no)) ).\n:- ( '\$flush_predicate'(a(_)) -> assertz(fl(fp, yes)) ; assertz(fl(fp, no)) ).\n:- ( catch(a(_), _, fail) -> assertz(fl(a, yes)) ; assertz(fl(a, no)) ).\na(1).\na(2).\n"), (:load, ":- dynamic fl/2.\n:- ( '\$flushed_predicate'(a(_)) -> assertz(fl(f, yes)) ; assertz(fl(f, no)) ).\n:- ( '\$flush_predicate'(a(_)) -> assertz(fl(fp, yes)) ; assertz(fl(fp, no)) ).\n:- ( catch(a(_), _, fail) -> assertz(fl(a, yes)) ; assertz(fl(a, no)) ).\na(3).\n")],
        [
            ("f01", "findall(K-V, fl(K, V), L), R = L"),
            ("f02", "findall(X, a(X), L), R = L"),
            ("f03", "'\$source_file_property'('@FILE@', load_count, V), R = V"),
            ("f04", "'\$source_file_property'('@FILE@', number_of_clauses, V), R = V"),
            ("f05", "( '\$flushed_predicate'(a(_)) -> R = yes ; R = no )"),
            ("f06", "( '\$flush_predicate'(a(_)) -> R = yes ; R = no )")
        ]
    ),
    (
        "S7",
        "an unknown file unloaded",
        Tuple{Symbol, String}[],
        [
            ("k01", "( '\$unload_file'('/no/such/file') -> R = yes ; R = no )"),
            ("k02", "( '\$source_file_property'('/no/such/file', load_count, V) -> R = V ; R = fails )")
        ]
    )
]

# swipl 10.1.20 (pin 18168e62, LC_ALL=C): the lines of the driver for each scenario, from tools/gen_reload.py of the audit channel (evidence/R2/gen_reload/)
const _PINNED = Dict{String, Vector{String}}(
    "S1" => [
        "ok",
        "t_m01 c[116,95,109,48,49]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[99],nil)))",
        "t_m02 c[116,95,109,48,50]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,49],c[47]/2(a[113],i0))))",
        "t_m03 c[116,95,109,48,51]/1(c[91,124,93]/2(c[47]/2(a[112],i1),nil))",
        "t_m04 c[116,95,109,48,52]/1(i2)",
        "t_m05 c[116,95,109,48,53]/1(i2)",
        "t_m06 c[116,95,109,48,54]/1(a[102,97,108,115,101])",
        "t_m07 c[116,95,109,48,55]/1(a[115,97,109,101])",
        "t_m08 c[116,95,109,48,56]/1(a[110,111])",
        "t_m09 c[116,95,109,48,57]/1(a[121,101,115])",
        "t_m10 c[116,95,109,49,48]/1(a[102,108,116])",
        "t_m11 c[116,95,109,49,49]/1(i1)",
        "t_m12 c[116,95,109,49,50]/1(a[110,111])",
        "t_m13 c[116,95,109,49,51]/1(c[91,124,93]/2(c[47]/2(a[112],i1),nil))"
    ],
    "S2" => [
        "ok",
        "t_u01 c[116,95,117,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))))",
        "t_u02 c[116,95,117,48,50]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[98],i1)))",
        "t_u03 c[116,95,117,48,51]/1(c[91,124,93]/2(i1,nil))",
        "t_u04 c[116,95,117,48,52]/1(c[91,124,93]/2(i1,nil))",
        "t_u05 c[116,95,117,48,53]/1(i2)",
        "t_u06 c[116,95,117,48,54]/1(i5)",
        "t_u07 c[116,95,117,48,55]/1(c[91,124,93]/2(c[47]/2(a[97],i1),c[91,124,93]/2(c[47]/2(a[99],i1),c[91,124,93]/2(c[47]/2(a[100],i1),nil))))",
        "t_u08 c[116,95,117,48,56]/1(i1)",
        "t_u09 c[116,95,117,48,57]/1(a[102,97,105,108,115])",
        "t_u10 c[116,95,117,49,48]/1(i1)",
        "t_u11 c[116,95,117,49,49]/1(c[45]/2(i2,a[115,97,109,101]))",
        "t_u15 c[116,95,117,49,53]/1(i1)",
        "t_u16 c[116,95,117,49,54]/1(i5)",
        "t_u12 c[116,95,117,49,50]/1(a[110,111])",
        "t_u13 c[116,95,117,49,51]/1(c[101,114,114]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
        "t_u14 c[116,95,117,49,52]/1(a[110,111])"
    ],
    "S3" => [
        "ok",
        "t_d01 c[116,95,100,48,49]/1(c[91,124,93]/2(i2,nil))",
        "t_d02 c[116,95,100,48,50]/1(c[91,124,93]/2(i2,nil))",
        "t_d03 c[116,95,100,48,51]/1(c[91,124,93]/2(a[121,101,115],c[91,124,93]/2(a[121,101,115],nil)))",
        "t_d04 c[116,95,100,48,52]/1(i2)",
        "t_d05 c[116,95,100,48,53]/1(i1)",
        "t_d06 c[116,95,100,48,54]/1(i1)",
        "t_d07 c[116,95,100,48,55]/1(i2)"
    ],
    "S4" => [
        "ok",
        "t_o01 c[116,95,111,48,49]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[58]/2(a[109,52],c[47]/2(a[112],i1))))",
        "t_o02 c[116,95,111,48,50]/1(i1)",
        "t_o03 c[116,95,111,48,51]/1(a[121,101,115])",
        "t_o04 c[116,95,111,48,52]/1(a[110,111])",
        "t_o05 c[116,95,111,48,53]/1(nil)",
        "t_o06 c[116,95,111,48,54]/1(i0)",
        "t_o07 c[116,95,111,48,55]/1(a[110,111,102,105,108,101])"
    ],
    "S5" => [
        "ok",
        "t_n01 c[116,95,110,48,49]/1(c[91,124,93]/2(a[99],nil))",
        "t_n02 c[116,95,110,48,50]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[113],i1)))",
        "t_n03 c[116,95,110,48,51]/1(i2)",
        "t_n04 c[116,95,110,48,52]/1(i1)",
        "t_n05 c[116,95,110,48,53]/1(a[102,97,108,115,101])"
    ],
    "S6" => [
        "ok",
        "t_f01 c[116,95,102,48,49]/1(c[91,124,93]/2(c[45]/2(a[102],a[110,111]),c[91,124,93]/2(c[45]/2(a[102,112],a[110,111]),c[91,124,93]/2(c[45]/2(a[97],a[110,111]),c[91,124,93]/2(c[45]/2(a[102],a[110,111]),c[91,124,93]/2(c[45]/2(a[102,112],a[121,101,115]),c[91,124,93]/2(c[45]/2(a[97],a[110,111]),nil)))))))",
        "t_f02 c[116,95,102,48,50]/1(c[91,124,93]/2(i3,nil))",
        "t_f03 c[116,95,102,48,51]/1(i2)",
        "t_f04 c[116,95,102,48,52]/1(i1)",
        "t_f05 c[116,95,102,48,53]/1(a[121,101,115])",
        "t_f06 c[116,95,102,48,54]/1(a[121,101,115])"
    ],
    "S7" => [
        "ok",
        "t_k01 c[116,95,107,48,49]/1(a[121,101,115])",
        "t_k02 c[116,95,107,48,50]/1(i0)"
    ]
)

# ---- the kernel's calls, one built-in at a time
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

_v() = mk_var(_TL, LK.fresh_var_keys!(1))

# ---- the kernel's lines of a scenario: `ok`, then `<name> <answers>` for each row
_rows_text(rows) = _PROG * join(["t_$(id)(R) :- ( $g -> true ).\n" for (id, g) in rows])

function kernel_scen_lines(sid::String, steps, rows, dir::String)::Vector{String}
    f = joinpath(dir, "$(sid).pl")
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    for (kind_, text) in steps
        if kind_ === :load
            write(f, text)
            st, ball = LK.load_file!(gd, ld, f)
            st === :ok || return ["exc " * enc(ball::_TL)]
        else
            st, _ = kcall(gd, ld, "\$unload_file", _TL[_tls(f)])
            st === :true || return ["unload " * String(st)]
        end
    end
    rf = joinpath(dir, "$(sid)_rows.pl")
    write(rf, replace(_rows_text(rows), "@FILE@" => f))
    st, ball = LK.load_file!(gd, ld, rf)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for (id, _) in rows
        name = "t_$id"
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

# swipl's side: the driver of test_source_file_swipl.jl with the steps (`unload` is `'$unload_file'/1`, the system predicate the kernel's step calls too)
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
fz_wr(File, Text) :- setup_call_cleanup(open(File, write, S), write(S, Text), close(S)).
fz_steps(_, []).
fz_steps(F, [load(T)|Ts]) :- fz_wr(F, T), consult(F), fz_steps(F, Ts).
fz_steps(F, [unload|Ts]) :- '$unload_file'(F), fz_steps(F, Ts).
fz_scen(File, Steps, RowsFile, Ns) :-
    catch(( fz_steps(File, Steps), consult(RowsFile), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

_pl_str(s::String) = "\"" * replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n") * "\""

"Run swipl on a scenario: its output lines."
function swipl_scen_lines(sid::String, steps, rows, dir::String)::Vector{String}
    f = joinpath(dir, "$(sid)_sw.pl")
    rf = joinpath(dir, "$(sid)_sw_rows.pl")
    write(rf, replace(_rows_text(rows), "@FILE@" => f))
    st = join(
        [k === :load ? "load(" * _pl_str(t) * ")" : "unload" for (k, t) in steps], ","
    )
    out = mktempdir() do d
        drv = joinpath(d, "drv.pl")
        write(
            drv,
            DRIVER * ":- initialization((fz_scen('$f', [$st], '$rf', [" *
            join(["t_$id" for (id, _) in rows], ",") * "]), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $drv`, "LC_ALL" => "C"); stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

_swipl() = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")

@testset "the table is whole: seven scenarios, every row pinned, each kind of answer in it" begin
    @test [s[1] for s in _SCENS] == ["S1", "S2", "S3", "S4", "S5", "S6", "S7"]
    @test all(s -> haskey(_PINNED, s[1]) && length(_PINNED[s[1]]) == length(s[4]) + 1, _SCENS)
    @test allunique(vcat([[id for (id, _) in s[4]] for s in _SCENS]...))
    @test all(s -> _PINNED[s[1]][1] == "ok", _SCENS)
    # the non-vacuity of the comparison below: the answers the reload is about are in swipl's own lines
    @test occursin(_codes("existence_error"), _PINNED["S1"][3])               # m1:q is gone
    @test occursin(_codes("existence_error"), _PINNED["S2"][3])               # b/1 is gone
    @test occursin(_codes("existence_error"), _PINNED["S4"][2])               # m4:p after the unload
    @test occursin(_codes("existence_error"), _PINNED["S5"][3])               # q/1 after the unload and the load
    @test occursin("i2", _PINNED["S1"][5]) && occursin("i2", _PINNED["S5"][4])   # load_count 2
    @test occursin("i1", _PINNED["S4"][3])                                     # load_count STILL 1 after the unload
    @test count(l -> occursin(_codes("yes"), l), _PINNED["S6"]) == 3           # the flush predicates' answers
end

@testset "reload scenario $(s[1]): $(s[2]) == swipl's lines" for s in _SCENS
    sid, _, steps, rows = s
    dir = realpath(mktempdir())
    kl = kernel_scen_lines(sid, steps, rows, dir)
    pinned = _PINNED[sid]
    @test length(kl) == length(pinned)
    for (k, p) in zip(kl, pinned)
        @test k == p
    end
    if _swipl() === nothing
        @info "RELOAD DIFFERENTIAL NOT RUN ($sid): `swipl` is not on PATH (or LOGICKERNEL_NO_SWIPL=1); the kernel's lines are compared with the pins only."
    else
        sw = swipl_scen_lines(sid, steps, rows, dir)
        @test sw == pinned                                                  # the pins are swipl's own lines
    end
end

# ============================================================================================
# WHITE-BOX: term and database builders (every term-building helper takes the term type)
# ============================================================================================
_wb_expr(::Type{T}, f::Symbol, xs::T...) where {T} = mk_expr(T, T[lk_sym(T, f), xs...])
_wb_p(::Type{T}, name::Symbol, n::Integer) where {T} = _wb_expr(T, name, lk_gnd(T, Int64(n)))

"The procedure `name/arity` of the user module, created when absent."
_wb_proc(db::IxDB{T}, name::Symbol, arity::Int) where {T} =
    LK.lookupProcedure(lk_sym(T, name), arity, LK.MODULE_user(db.gd))

"The source file called `name`, created when absent (one reference is the caller's)."
_wb_sf(db::IxDB{T}, name::String) where {T} =
    LK.lookupSourceFile(db.gd, lk_sym(T, Symbol(name)), true)::LK.SourceFile{T}

"A clause for `head` of `proc` as `assert_term!` leaves a loaded one: its source file `sf`, its owner `owner` (default `sf`), the line `line`, and a reference to each file."
function _wb_clause(
    db::IxDB{T}, sf::LK.SourceFile{T}, proc::LK.Procedure{T}, head::T;
    line::Integer=1, owner::LK.SourceFile{T}=sf
)::LK.Clause{T} where {T}
    cl = LK.compileClause(
        db.gd, db.ld, head, nothing, proc, LK.MODULE_user(db.gd), 0, UInt32(0)
    )
    cl === nothing && error("compileClause refused the clause")
    cl.line_no = UInt32(line)
    cl.source_no = UInt32(sf.index)
    cl.owner_no = UInt32(owner.index)
    LK.acquireSourceFile(sf)
    owner === sf || LK.acquireSourceFile(owner)
    return cl
end

"Add the clauses with the heads `heads` to `proc` for `sf` in the first-load way; the clauses, in order. `lines`: their lines (default 1)."
function _wb_old!(
    db::IxDB{T}, sf::LK.SourceFile{T}, proc::LK.Procedure{T}, heads::Vector{T};
    owner::LK.SourceFile{T}=sf, lines::Vector{Int}=Int[]
)::Vector{LK.Clause{T}} where {T}
    LK.addProcedureSourceFile(sf, proc)
    out = LK.Clause{T}[]
    for (i, h) in enumerate(heads)
        cl = _wb_clause(db, sf, proc, h; owner=owner, line=isempty(lines) ? 1 : lines[i])
        cref = LK.assertProcedureSource(db.gd, db.ld, sf, proc, cl)
        (cref !== nothing && cref.clause === cl) || error("the clause was not added")
        push!(out, cl)
    end
    return out
end

"The clauses of `def`, in list order."
function _wb_list(def::LK.Definition{T})::Vector{LK.Clause{T}} where {T}
    out = LK.Clause{T}[]
    c = def.impl_clauses.first_clause
    while c !== nothing
        push!(out, c.clause::LK.Clause{T})
        c = c.next
    end
    return out
end

"Are `a` and `b` the same clauses, element by element, by identity?"
_wb_is(a, b) = length(a) == length(b) && all(i -> a[i] === b[i], eachindex(a))

"The clauses of `def` that are not erased."
_wb_live(def::LK.Definition) = [cl for cl in _wb_list(def) if (cl.flags & LK.CL_ERASED) == 0]

"A reload set up by hand: file `sf` with the procedures `names` (each `name/1`, the old clauses `name(1)..name(n)`), and `startReconsultFile` done."
function _wb_scene(
    ::Type{T}, names::Vector{Symbol}; n::Integer=2, multifile::Vector{Symbol}=Symbol[]
) where {T}
    db = IxDB{T}()
    sf = _wb_sf(db, "/lb6b/scene.pl")
    procs = Dict{Symbol, LK.Procedure{T}}()
    olds = Dict{Symbol, Vector{LK.Clause{T}}}()
    for nm in names
        pr = _wb_proc(db, nm, 1)
        nm in multifile && (pr.definition.flags |= LK.P_MULTIFILE)
        procs[nm] = pr
        olds[nm] = _wb_old!(db, sf, pr, T[_wb_p(T, nm, i) for i in 1:n])
    end
    LK.startReconsultFile(db.gd, db.ld, sf)
    return (db=db, sf=sf, procs=procs, olds=olds)
end

"The second pass of a reload meets the clause `name(i)` again."
function _wb_meet!(db::IxDB{T}, sf, proc, name::Symbol, i::Integer) where {T}
    cl = _wb_clause(db, sf, proc, _wb_p(T, name, i))
    return LK.assertProcedureSource(db.gd, db.ld, sf, proc, cl)
end

@testset "W1 endReconsult: the clause the reload met stays, the others are erased at ONE generation, the reload ends" begin
    s = _wb_scene(_TL, [:p]; n=3)
    db, sf, proc, olds = s.db, s.sf, s.procs[:p], s.olds[:p]
    gd, ld, def = db.gd, db.ld, proc.definition
    @test sf.number_of_clauses == 3 && all(cl -> cl.generation_erased == LK.GEN_RELOAD, olds)
    @test _wb_meet!(db, sf, proc, :p, 1).clause === olds[1]
    @test sf.reload.number_of_clauses == 1 && gd.reload_generation == LK.GEN_RELOAD &&
        ld.reload_nesting == 1
    @test LK.endReconsult(gd, ld, sf)
    @test olds[1].generation_erased == LK.GEN_MAX && (olds[1].flags & LK.CL_ERASED) == 0
    for cl in olds[2:3]
        @test (cl.flags & LK.CL_ERASED) != 0 && cl.generation_erased != LK.GEN_RELOAD &&
            cl.generation_erased != LK.GEN_MAX
    end
    @test olds[2].generation_erased == olds[3].generation_erased                  # one generation for the lot
    @test def.impl_clauses.number_of_clauses == 1
    @test _wb_is(_wb_live(def), [olds[1]])
    @test sf.reload === nothing && gd.reload_generation == LK.GEN_INVALID &&
        ld.reload_nesting == 0
    @test sf.number_of_clauses == 1                                           # the reload's count (pl-srcfile.c:1631)
    @test (def.flags & LK.P_RELOADING) == 0
    @test LK.endReconsult(gd, ld, sf)                                         # no reload context: true, nothing changes
    @test _wb_is(_wb_live(def), [olds[1]]) && sf.number_of_clauses == 1
end

@testset "W2 end_reconsult_proc!: 1 for a new predicate and for a foreign one, 0 for a predicate the reload met" begin
    s = _wb_scene(_TL, [:p]; n=1)
    db, sf, proc = s.db, s.sf, s.procs[:p]
    gd, ld = db.gd, db.ld
    nw = _wb_proc(db, :nw, 1)
    LK.addProcedureSourceFile(sf, nw)
    _wb_meet!(db, sf, nw, :nw, 1)
    rn = sf.reload.procedures[nw]
    @test (rn.flags & LK.P_NEW) != 0
    @test LK.end_reconsult_proc!(gd, ld, sf, nw, rn) == 1                     # P_NEW: the access reference is dropped (pl-srcfile.c:1585)
    fp = _wb_proc(db, :fp, 1)
    fp.definition.flags |= LK.P_FOREIGN
    rf = LK.reloadContext(gd, ld, sf, fp)
    @test (rf.flags & LK.P_NO_CLAUSES) != 0
    @test LK.end_reconsult_proc!(gd, ld, sf, fp, rf) == 1                     # P_NO_CLAUSES: also dropped
    @test _wb_meet!(db, sf, proc, :p, 1).clause === s.olds[:p][1]
    rp = sf.reload.procedures[proc]
    @test (rp.flags & (LK.P_NEW | LK.P_NO_CLAUSES)) == 0
    @test LK.end_reconsult_proc!(gd, ld, sf, proc, rp) == 0                   # met: nothing dropped here (endReconsult pops the rest)
end

@testset "W3 delete_old_predicates!: a procedure the reload did not meet loses its clauses and leaves the file; a met one stays" begin
    s = _wb_scene(_TL, [:p, :q]; n=2)
    db, sf, p, q = s.db, s.sf, s.procs[:p], s.procs[:q]
    _wb_meet!(db, sf, p, :p, 1)
    @test (q.definition.flags & LK.FILE_ASSIGNED) != 0 && length(sf.procedures) == 2
    @test all(cl -> (cl.flags & LK.CL_ERASED) == 0, s.olds[:q])
    LK.delete_old_predicates!(db.gd, sf)
    @test all(cl -> (cl.flags & LK.CL_ERASED) != 0, s.olds[:q])
    @test q.definition.impl_clauses.number_of_clauses == 0
    @test (q.definition.flags & LK.FILE_ASSIGNED) == 0                       # a static, not multifile predicate: no longer the file's
    @test length(sf.procedures) == 1 && sf.procedures[1] === p
    @test all(cl -> (cl.flags & LK.CL_ERASED) == 0, s.olds[:p])             # the met predicate is left to end_reconsult_proc!
    @test (p.definition.flags & LK.FILE_ASSIGNED) != 0
end

@testset "W4 delete_old_predicates!: a foreign predicate the reload did not meet is skipped and stays the file's" begin
    s = _wb_scene(_TL, [:p]; n=1)
    db, sf = s.db, s.sf
    fp = _wb_proc(db, :fp, 1)
    LK.addProcedureSourceFile(sf, fp)
    fp.definition.flags |= LK.P_FOREIGN
    _wb_meet!(db, sf, s.procs[:p], :p, 1)
    @test length(sf.procedures) == 2 && !haskey(sf.reload.procedures, fp)
    LK.delete_old_predicates!(db.gd, sf)
    @test length(sf.procedures) == 2 && any(pr -> pr === fp, sf.procedures)
    @test (fp.definition.flags & LK.FILE_ASSIGNED) != 0
end

@testset "W5 multifile predicate: the end of a reload erases only the reloading file's clauses; the predicate stays assigned" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    sf = _wb_sf(db, "/lb6b/m_ours.pl")
    sfo = _wb_sf(db, "/lb6b/m_other.pl")
    proc = _wb_proc(db, :m, 1)
    proc.definition.flags |= LK.P_MULTIFILE
    ours = _wb_old!(db, sf, proc, _TL[_wb_p(_TL, :m, 1), _wb_p(_TL, :m, 2)])
    theirs = _wb_old!(db, sfo, proc, _TL[_wb_p(_TL, :m, 5)])
    @test all(cl -> cl.owner_no == sf.index, ours) && theirs[1].owner_no == sfo.index
    LK.startReconsultFile(gd, ld, sf)
    @test LK.endReconsult(gd, ld, sf)                                         # the reload met no clause of m/1
    @test all(cl -> (cl.flags & LK.CL_ERASED) != 0, ours)
    @test (theirs[1].flags & LK.CL_ERASED) == 0 && theirs[1].generation_erased == LK.GEN_MAX
    @test _wb_is(_wb_live(proc.definition), [theirs[1]])
    @test (proc.definition.flags & LK.FILE_ASSIGNED) != 0                    # multifile: still assigned
    @test isempty(sf.procedures)                                              # but no longer in the list of the file that dropped it
end

@testset "W6 fix_module: an export the reloaded file did not make again is dropped from the module's public table" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    sf = _wb_sf(db, "/lb6b/fm.pl")
    m = LK.lookupModule(gd, _tls("lb6b_fm"))
    pp = LK.lookupProcedure(_tls("wp"), 1, m)
    qq = LK.lookupProcedure(_tls("wq"), 0, m)
    LK.exportProcedure(m, pp)
    LK.exportProcedure(m, qq)
    kp = (pp.definition.functor_name, pp.definition.arity)
    kq = (qq.definition.functor_name, qq.definition.arity)
    @test haskey(m.public_, kp) && haskey(m.public_, kq) && m.public_order == [kp, kq]
    LK.startReconsultFile(gd, ld, sf)
    LK.registerReloadModule(sf, m)
    @test haskey(sf.reload.modules, m) && isempty(sf.reload.modules[m].public_)
    LK.exportProcedureSource(sf, m, pp)                                       # the second pass exports p/1 only
    @test haskey(sf.reload.modules[m].public_, kp)
    LK.fix_module(m, sf.reload.modules[m])
    @test haskey(m.public_, kp) && !haskey(m.public_, kq) && m.public_order == [kp]
    # a module that is not registered in a reload gets no record, and exportProcedureSource records nothing for it
    m2 = LK.lookupModule(gd, _tls("lb6b_fm2"))
    LK.exportProcedureSource(sf, m2, LK.lookupProcedure(_tls("wr"), 1, m2))
    @test !haskey(sf.reload.modules, m2)
end

@testset "W7 unloadFile!: the file's clauses are erased (a multifile predicate's only its own), its procedures and modules unlinked" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    sf = _wb_sf(db, "/lb6b/ul.pl")
    sfo = _wb_sf(db, "/lb6b/ul_other.pl")
    sf.isfile = true
    p = _wb_proc(db, :ulp, 1)
    q = _wb_proc(db, :ulq, 1)
    mf = _wb_proc(db, :ulm, 1)
    mf.definition.flags |= LK.P_MULTIFILE
    cp = _wb_old!(db, sf, p, _TL[_wb_p(_TL, :ulp, 1), _wb_p(_TL, :ulp, 2)])
    cq = _wb_old!(db, sf, q, _TL[_wb_p(_TL, :ulq, 1)])
    cm = _wb_old!(db, sf, mf, _TL[_wb_p(_TL, :ulm, 1)])
    co = _wb_old!(db, sfo, mf, _TL[_wb_p(_TL, :ulm, 9)])
    m = LK.lookupModule(gd, _tls("lb6b_ul"))
    LK.addModuleSourceFile(sf, m)
    m.file = sf.index
    LK.exportProcedure(m, LK.lookupProcedure(_tls("ule"), 0, m))
    @test sf.number_of_clauses == 4 && length(sf.procedures) == 3 && !isempty(m.public_)
    @test LK.unloadFile!(gd, ld, sf)
    for cl in vcat(cp, cq, cm)
        @test (cl.flags & LK.CL_ERASED) != 0
    end
    @test (co[1].flags & LK.CL_ERASED) == 0                                   # another file's clause of the multifile predicate
    @test isempty(sf.procedures) && isempty(sf.modules) && !sf.isfile
    @test sf.number_of_clauses == 0                                           # minus the 4 deleted (pl-srcfile.c:822)
    @test (p.definition.flags & LK.FILE_ASSIGNED) == 0 && (q.definition.flags & LK.FILE_ASSIGNED) == 0
    @test (mf.definition.flags & LK.FILE_ASSIGNED) != 0                      # multifile: stays assigned
    @test m.file == 0 && isempty(m.public_) && isempty(m.public_order)        # delAllModulesSourceFile_unlocked!: the module that came from this file
end

@testset "W7b delModuleSourceFile and delAllModulesSourceFile_unlocked!: only a module whose file is this one loses its file and its public table" begin
    db = IxDB{_TL}()
    gd = db.gd
    sf = _wb_sf(db, "/lb6b/dm.pl")
    sf2 = _wb_sf(db, "/lb6b/dm2.pl")
    m1 = LK.lookupModule(gd, _tls("lb6b_dm1"))
    m2 = LK.lookupModule(gd, _tls("lb6b_dm2"))
    @test LK.addModuleSourceFile(sf, m1) && LK.addModuleSourceFile(sf, m2)
    @test LK.delModuleSourceFile(sf, m1) && sf.modules == [m2]
    @test !LK.delModuleSourceFile(sf, m1)                                     # no longer there
    @test LK.addModuleSourceFile(sf, m1) && sf.modules == [m2, m1]
    m1.file = sf.index
    m1.line_no = 7
    m2.file = sf2.index                                                       # defined by ANOTHER file, only listed here
    for (mm, nm) in ((m1, "dme1"), (m2, "dme2"))
        LK.exportProcedure(mm, LK.lookupProcedure(_tls(nm), 0, mm))
    end
    LK.delAllModulesSourceFile_unlocked!(sf)
    @test isempty(sf.modules)
    @test m1.file == 0 && m1.line_no == 0 && isempty(m1.public_) && isempty(m1.public_order)
    @test m2.file == sf2.index && length(m2.public_) == 1 && length(m2.public_order) == 1
end

@testset "W8 '\$unload_file' of a system file is a permission_error and leaves the file; of a file that is no file, true" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    sf = _wb_sf(db, "/lb6b/sys.pl")
    sf.system = true
    r0 = sf.references
    st, ans = kcall(gd, ld, "\$unload_file", _TL[_tls("/lb6b/sys.pl")])
    @test st === :exception
    ball = enc(ans[1])
    @test occursin(_codes("permission_error"), ball) && occursin(_codes("unload"), ball) &&
        occursin(_codes("file"), ball)
    @test sf.references == r0 && sf.magic == LK.SF_MAGIC                      # the reference taken is given back; a system file is not destroyed
    st, _ = kcall(gd, ld, "\$unload_file", _TL[_tls("/lb6b/no_such_file.pl")])
    @test st === :true
    @test LK.lookupSourceFile_unlocked(gd, _tls("/lb6b/no_such_file.pl"), false) === nothing   # and none is made
    # an ordinary file unloaded: its caller's reference is kept, the file with it
    sf2 = _wb_sf(db, "/lb6b/ord.pl")
    sf2.isfile = true
    r2 = sf2.references
    st, _ = kcall(gd, ld, "\$unload_file", _TL[_tls("/lb6b/ord.pl")])
    @test st === :true && !sf2.isfile && sf2.references == r2 && sf2.magic == LK.SF_MAGIC
end

@testset "W9 '\$set_source_files'/1: `from_state` marks every file loaded so far, `system` also as system; another property is a domain_error" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    a = _wb_sf(db, "/lb6b/ss_a.pl")
    b = _wb_sf(db, "/lb6b/ss_b.pl")
    @test !a.system && !a.from_state && !b.system && !b.from_state
    st, _ = kcall(gd, ld, "\$set_source_files", _TL[_tls("from_state")])
    @test st === :true && a.from_state && b.from_state && !a.system && !b.system
    st, _ = kcall(gd, ld, "\$set_source_files", _TL[_tls("system")])
    @test st === :true && a.system && b.system && a.from_state && b.from_state
    n = LK.highSourceFileIndex(gd) - 1
    @test all(i -> (f = LK.indexToSourceFile(gd, i); f === nothing || (f.system && f.from_state)), 1:n)
    st, ans = kcall(gd, ld, "\$set_source_files", _TL[_tls("resource")])
    @test st === :exception && occursin(_codes("domain_error"), enc(ans[1]))
end

@testset "W10 '\$clause_from_source'/4: the clauses of the file that contain the line, those that start last at or before it; an unknown owner or file fails" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    f = "/lb6b/cfs.pl"
    sf = _wb_sf(db, f)
    proc = _wb_proc(db, :cf, 1)
    cls = _wb_old!(
        db, sf, proc, _TL[_wb_p(_TL, :cf, 1), _wb_p(_TL, :cf, 2), _wb_p(_TL, :cf, 3)];
        lines=[1, 3, 3]
    )
    r0 = sf.references
    ask(owner, file, line) = kcall(
        gd, ld, "\$clause_from_source", _TL[_tls(owner), _tls(file), lk_gnd(_TL, line), _v()]
    )
    st, ans = ask(f, f, 2)
    @test st === :true && enc(ans[4]) == "c" * _codes("[|]") * "/2(clref,nil)"   # line 2: only the clause at line 1
    st, ans = ask(f, f, 3)
    @test st === :true && enc(ans[4]) == "c" * _codes("[|]") * "/2(clref,c" * _codes("[|]") * "/2(clref,nil))"   # line 3: both clauses starting at 3
    st, _ = ask(f, f, 0)
    @test st === :false                                                       # before the first clause
    st, _ = ask("/lb6b/no_such_owner.pl", f, 2)
    @test st === :false                                                       # unknown owner
    st, _ = ask(f, "/lb6b/no_such_file.pl", 2)
    @test st === :false                                                       # unknown source file
    st, ans = kcall(gd, ld, "\$clause_from_source", _TL[_v(), _tls(f), lk_gnd(_TL, 2), _v()])
    @test st === :exception && occursin(_codes("instantiation_error"), enc(ans[1]))
    @test sf.references == r0 && length(cls) == 3                             # every reference taken is given back
end

@testset "W11 flush_procedure!: a predicate the reload has not seen is flushed and becomes new; one it has seen is finalized at once; no reload: nothing" begin
    s = _wb_scene(_TL, [:p, :q]; n=2)
    db, sf, p, q = s.db, s.sf, s.procs[:p], s.procs[:q]
    gd, ld = db.gd, db.ld
    # seen: p(1) met, then flushed: the clause p(2) the reload did not meet is erased now
    @test _wb_meet!(db, sf, p, :p, 1).clause === s.olds[:p][1]
    @test LK.flush_procedure!(gd, ld, sf, p)
    @test (s.olds[:p][2].flags & LK.CL_ERASED) != 0 && (s.olds[:p][1].flags & LK.CL_ERASED) == 0
    # not seen: q's clauses go and q has a record in the reload, new
    @test !haskey(sf.reload.procedures, q)
    @test LK.flush_procedure!(gd, ld, sf, q)
    @test all(cl -> (cl.flags & LK.CL_ERASED) != 0, s.olds[:q])
    @test haskey(sf.reload.procedures, q) && (sf.reload.procedures[q].flags & LK.P_NEW) != 0
    # without a reload nothing happens, and the answer is true
    db2 = IxDB{_TL}()
    sf2 = _wb_sf(db2, "/lb6b/fl2.pl")
    p2 = _wb_proc(db2, :fl2, 1)
    c2 = _wb_old!(db2, sf2, p2, _TL[_wb_p(_TL, :fl2, 1)])
    @test LK.flush_procedure!(db2.gd, db2.ld, sf2, p2)
    @test (c2[1].flags & LK.CL_ERASED) == 0
end

@testset "W12 releaseSourceFile (three arguments): the last reference of an empty file destroys it and leaves a hole the next file reuses; the others are kept" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    a = _wb_sf(db, "/lb6b/ha.pl")
    b = _wb_sf(db, "/lb6b/hb.pl")
    c = _wb_sf(db, "/lb6b/hc.pl")
    ia, ib, ic = a.index, b.index, c.index
    @test ia < ib < ic && a.references == 1
    @test LK.releaseSourceFile(gd, ld, a)
    @test a.references == 0 && a.magic == 0
    @test LK.indexToSourceFile(gd, ia) === nothing
    @test LK.lookupSourceFile_unlocked(gd, _tls("/lb6b/ha.pl"), false) === nothing
    @test gd.files_no_hole_before == ia                                       # the hole is where the search starts
    @test LK.indexToSourceFile(gd, ib) === b && LK.indexToSourceFile(gd, ic) === c
    @test_throws ErrorException LK.releaseSourceFile(gd, ld, a)               # no reference to release (upstream's Oops)
    d = _wb_sf(db, "/lb6b/hd.pl")
    @test d.index == ia && LK.indexToSourceFile(gd, ia) === d && gd.files_no_hole_before == ia + 1
    e = _wb_sf(db, "/lb6b/he.pl")
    @test e.index > ic && e.index == length(gd.files_array)                   # no hole left: appended
    # NOT destroyed: a system file, one with a current procedure, one with a procedure, one with a module, one that still has a reference
    kept = Dict{String, LK.SourceFile{_TL}}()
    for nm in ("sys", "cur", "proc", "mod", "ref")
        kept[nm] = _wb_sf(db, "/lb6b/k_$nm.pl")
    end
    kept["sys"].system = true
    kept["cur"].current_procedure = _wb_proc(db, :hcur, 1)
    push!(kept["proc"].procedures, _wb_proc(db, :hproc, 1))
    push!(kept["mod"].modules, LK.lookupModule(gd, _tls("lb6b_hmod")))
    LK.acquireSourceFile(kept["ref"])
    for (nm, sf) in kept
        @test LK.releaseSourceFile(gd, ld, sf)
        @test sf.magic == LK.SF_MAGIC && LK.indexToSourceFile(gd, sf.index) === sf
        @test sf.references == (nm == "ref" ? 1 : 0)
    end
    # the one-argument form only counts (TEMPORARY DIVERGES of pl-srcfile.jl): an empty file stays
    g = _wb_sf(db, "/lb6b/hg.pl")
    @test LK.releaseSourceFile(g) && g.references == 0 && g.magic == LK.SF_MAGIC
end

@testset "W13 clause reclamation gives the source-file references back; the last one of an empty file destroys it" begin
    db = IxDB{_TL}()
    gd, ld = db.gd, db.ld
    sf = _wb_sf(db, "/lb6b/gc.pl")
    proc = _wb_proc(db, :gcp, 1)
    olds = _wb_old!(db, sf, proc, _TL[_wb_p(_TL, :gcp, 1), _wb_p(_TL, :gcp, 2)])
    r1 = sf.references                                                        # the lookup's, the procedure's and one per clause
    for cl in olds
        LK.retractClauseDefinition!(gd, ld, proc.definition, cl, true)
    end
    @test all(cl -> (cl.flags & LK.CL_ERASED) != 0, olds) && sf.references == r1   # erased, not yet reclaimed
    @test LK.pl_garbage_collect_clauses!(gd, ld)
    @test isempty(_wb_list(proc.definition))
    @test sf.references == r1 - 2                                             # each reclaimed clause released its reference
    # the file is destroyed through the reclamation: nothing but the clause holds it
    sf2 = _wb_sf(db, "/lb6b/gc2.pl")
    proc2 = _wb_proc(db, :gcq, 1)
    c2 = _wb_old!(db, sf2, proc2, _TL[_wb_p(_TL, :gcq, 1)])
    empty!(sf2.procedures)                                                    # the procedure is no longer the file's ...
    LK.releaseSourceFile(gd, ld, sf2)                                         # ... the lookup's reference and the procedure's are given back
    LK.releaseSourceFile(gd, ld, sf2)
    @test sf2.references == 1 && LK.lookupSourceFile_unlocked(gd, _tls("/lb6b/gc2.pl"), false) === sf2
    LK.retractClauseDefinition!(gd, ld, proc2.definition, c2[1], true)
    @test sf2.references == 1                                                 # erased, not reclaimed yet
    LK.pl_garbage_collect_clauses!(gd, ld)
    @test LK.lookupSourceFile_unlocked(gd, _tls("/lb6b/gc2.pl"), false) === nothing &&
        sf2.magic == 0 && sf2.references == 0
end
