# ORIGINAL: LB4 b1-3's gate for the boot-image readers (src/boot_image.jl; loader_boot design LD4 tables T1 and T3) — upstream reads these tables back through Prolog (boot/syspred.pl); the kernel reads them from the database. The C predicates both sides define are compared with swipl 10.1.19's `predicate_property/2` (pins below).
# test/db/test_boot_image_readers.jl — `boot_image_predicates` (T1) and `boot_image_source_files` (T3):
#   * T1 on a database built by hand: a dynamic predicate whose clause was retracted (the VISIBLE count, pl-proc.c:3648-3658),
#     a static one, an undefined one (`number_of_clauses` absent), a dynamic one with no clause (0), a foreign one (absent),
#     one with every attribute flag set, an export (the module's public table), an import (left out of the importing
#     module's rows), and a predicate of a second module; rows sorted by module, name, arity;
#   * T3 on files made by hand: the order of `$time_source_file/3` (a file with `count == 0` skipped), the columns of
#     `$source_file_property/3`, `loaded` absent for a file with no load time;
#   * the readers change nothing, and read a copy of a database (`copy_global_data`) as they read the database;
#   * ORACLE: the pins are swipl 10.1.19-1-gcbf4e189's `predicate_property/2` for the C predicates of module system the kernel
#     also defines (evidence/LB4B1/boot_image_rows.pl, two runs byte-identical, .out committed next to it): defined, foreign,
#     dynamic, iso, transparent and number_of_clauses absent. Only the predicates swipl implements in C (`foreign=1`) are
#     compared: swipl defines halt/0, call/1, \+/1 and findall/3 as clauses of boot/*.pl, which the kernel's built-ins are not.
# NOT RUN when written (edit-only, 2026-11-01): every row is "UNVERIFIED on the kernel: gate decides".
using Test, LogicKernel
include(joinpath(@__DIR__, "index_testlib.jl"))
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))

const _P = lk_term_type(Union{Int64, Float64})
_ps(n) = lk_sym(_P, Symbol(n))
_pe(f, xs::_P...) = mk_expr(_P, _P[_ps(f), xs...])
_pg(v) = lk_gnd(_P, v)

# ONE extractor for every side of every comparison below
_pred_tuple(r::LK.BootImagePredicate) = (
    r.module_name, r.name, r.arity, r.defined, r.dynamic, r.foreign, r.locked, r.iso, r.transparent, r.meta,
    r.public, r.exported, r.number_of_clauses
)
_file_tuple(r::LK.BootImageSourceFile) = (
    r.index, r.name, r.type, r.file_time, r.load_count, r.number_of_clauses, r.resource, r.from_state, r.loaded,
    r.reloading, copy(r.modules)
)
_t1(gd) = [_pred_tuple(r) for r in LK.boot_image_predicates(gd)]
_t3(gd) = [_file_tuple(r) for r in LK.boot_image_source_files(gd)]
_row(rows, m, n, a) = (i = findfirst(r -> r.module_name == m && r.name == n && r.arity == a, rows); i === nothing ? nothing : rows[i])

# a database with the predicates and files of the rows below
function lb4b1_hand_db()
    db = IxDB{_P}()
    gd = db.gd
    user = LK.MODULE_user(gd)
    dyn = ix_pred(_P, :b1_dyn, 1; dynamic=true, db=db)
    for i in 1:3
        ix_assertz!(dyn, _pe(:b1_dyn, _pg(i)))
    end
    LK.retractClauseDefinition!(gd, dyn.def, dyn.def.impl_clauses.first_clause.clause, true)
    stat = ix_pred(_P, :b1_stat, 1; db=db)
    ix_assertz!(stat, _pe(:b1_stat, _pg(1)))
    ix_assertz!(stat, _pe(:b1_stat, _pg(2)))
    LK.lookupProcedure(_ps(:b1_undef), 1, user)
    ix_pred(_P, :b1_dyn0, 0; dynamic=true, db=db)
    foreign = LK.lookupProcedure(_ps(:b1_for), 1, user)
    foreign.definition.flags |= LK.P_FOREIGN
    flagged = LK.lookupProcedure(_ps(:b1_flags), 2, user)
    flagged.definition.flags |= LK.P_ISO | LK.P_TRANSPARENT | LK.P_META | LK.P_LOCKED | LK.P_PUBLIC
    key = (sym_key(_ps(:b1_flags)), 2)
    user.public_[key] = flagged                                     # an export
    push!(user.public_order, key)
    sysproc = LK.isCurrentProcedure(sym_key(_ps(:(=))), 2, gd.modules_system)
    user.procedures[(sym_key(_ps(:b1_alias)), 2)] = sysproc         # an import: not a row of user
    mod = LK._lookupModule!(gd.modules, gd.modules_system.code_data, _ps(:b1_mod))
    LK.lookupProcedure(_ps(:b1_m_pred), 0, mod)
    fs = Any[]
    for (name, count) in ((:b1_f1, 1), (:b1_f2, 0), (:b1_f3, 2))
        sf = LK.lookupSourceFile(gd, _ps(name), true)
        sf.count = count
        push!(fs, sf)
    end
    fs[1].isfile = true
    fs[1].mtime = 12.5
    fs[1].ltime = 7.0
    fs[1].number_of_clauses = UInt32(4)
    push!(fs[1].modules, user)
    fs[3].system = true
    fs[3].resource = true
    fs[3].from_state = true
    foreach(LK.releaseSourceFile, fs)
    return db
end

const HAND = lb4b1_hand_db()
const HGD = HAND.gd

@testset "T1: the attribute columns of hand-built predicates" begin
    rows = LK.boot_image_predicates(HGD)
    dyn = _row(rows, "user", "b1_dyn", 1)
    @test dyn !== nothing && dyn.defined && dyn.dynamic && !dyn.foreign
    @test dyn.number_of_clauses == 2                                # 3 asserted, 1 retracted: the visible count
    stat = _row(rows, "user", "b1_stat", 1)
    @test stat !== nothing && stat.defined && !stat.dynamic && stat.number_of_clauses == 2
    undef = _row(rows, "user", "b1_undef", 1)
    @test undef !== nothing && !undef.defined && !undef.dynamic && undef.number_of_clauses === nothing
    dyn0 = _row(rows, "user", "b1_dyn0", 0)
    @test dyn0 !== nothing && dyn0.defined && dyn0.dynamic && dyn0.number_of_clauses == 0
    fr = _row(rows, "user", "b1_for", 1)
    @test fr !== nothing && fr.foreign && fr.number_of_clauses === nothing
    fl = _row(rows, "user", "b1_flags", 2)
    @test fl !== nothing
    @test fl.iso && fl.transparent && fl.meta && fl.locked && fl.public && fl.exported
    @test !fl.dynamic && !fl.foreign
    for r in (dyn, stat, undef, dyn0, fr)                           # a flag set on one predicate is not set on the others
        @test !r.iso && !r.transparent && !r.meta && !r.locked && !r.public && !r.exported
    end
end

@testset "T1: an import is not a row of the importing module; other modules have rows; the order is sorted" begin
    rows = LK.boot_image_predicates(HGD)
    @test _row(rows, "user", "b1_alias", 2) === nothing
    @test _row(rows, "user", "=", 2) === nothing
    @test _row(rows, "system", "=", 2) !== nothing                  # non-vacuous: the import's own row exists
    mp = _row(rows, "b1_mod", "b1_m_pred", 0)
    @test mp !== nothing && !mp.defined && !mp.exported
    @test issorted(rows; by = r -> (r.module_name, r.name, r.arity))
    @test length(rows) > 100
    mods = Set(r.module_name for r in rows)
    @test "system" in mods && "user" in mods && "b1_mod" in mods
    @test length(unique((r.module_name, r.name, r.arity) for r in rows)) == length(rows)   # one row per predicate
end

@testset "T3: the loaded source files, in the order of \$time_source_file/3" begin
    rows = LK.boot_image_source_files(HGD)
    @test [r.name for r in rows] == ["b1_f1", "b1_f3"]              # b1_f2 has count 0: skipped
    f1, f3 = rows
    @test f1.index < f3.index
    @test f1.type === :user && f1.file_time == 12.5 && f1.load_count == 1 && f1.number_of_clauses == 4
    @test !f1.resource && !f1.from_state && f1.loaded == 7.0 && !f1.reloading && f1.modules == ["user"]
    @test f3.type === :system && f3.file_time == 0.0 && f3.load_count == 2 && f3.number_of_clauses == 0
    @test f3.resource && f3.from_state && f3.loaded === nothing && !f3.reloading && isempty(f3.modules)
    @test isempty(LK.boot_image_source_files(LK.PL_global_data{_P}()))   # a fresh database: every file has count 0
end

@testset "the readers change nothing and read a copy as they read the original" begin
    t1, t3 = _t1(HGD), _t3(HGD)
    @test length(t1) > 100 && length(t3) == 2                       # non-vacuous
    gen = LK.global_generation(HGD)
    @test _t1(HGD) == t1 && _t3(HGD) == t3                          # reading twice gives the same rows
    @test LK.global_generation(HGD) == gen
    c = LK.copy_global_data(HGD)
    @test _t1(c) == t1
    @test _t3(c) == t3
end

# swipl 10.1.19-1-gcbf4e189, evidence/LB4B1/boot_image_rows.pl (two runs byte-identical): predicate_property(system:H, P)
const _ORACLE = raw"""
(=)/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
functor/3 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
arg/3 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
atom_length/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
atom_codes/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
(\=)/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
(==)/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
var/1 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
atom/1 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
(is)/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
(<)/2 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
write/1 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
nl/0 defined=1 foreign=1 dynamic=0 iso=1 transparent=0 number_of_clauses=none
halt/0 defined=1 foreign=0 dynamic=0 iso=1 transparent=0 number_of_clauses=1
(\+)/1 defined=1 foreign=0 dynamic=0 iso=1 transparent=1 number_of_clauses=1
call/1 defined=1 foreign=0 dynamic=0 iso=1 transparent=1 number_of_clauses=1
assertz/1 defined=1 foreign=1 dynamic=0 iso=1 transparent=1 number_of_clauses=none
retract/1 defined=1 foreign=1 dynamic=0 iso=1 transparent=1 number_of_clauses=none
findall/3 defined=1 foreign=0 dynamic=0 iso=1 transparent=1 number_of_clauses=1
atom_to_term/3 defined=1 foreign=1 dynamic=0 iso=0 transparent=0 number_of_clauses=none
"""

# the oracle's rows: (name, arity) => the pinned columns
function _oracle_rows()
    out = Dict{Tuple{String, Int}, Dict{String, String}}()
    for line in split(strip(_ORACLE), '\n')
        m = match(r"^(\(?)(.+?)\)?/(\d+) (.*)$", line)
        m === nothing && continue
        cols = Dict{String, String}()
        for kv in split(m.captures[4])
            k, v = split(kv, '=')
            cols[k] = v
        end
        out[(String(m.captures[2]), parse(Int, m.captures[3]))] = cols
    end
    return out
end

@testset "ORACLE: the C predicates of module system both sides define (swipl 10.1.19 predicate_property/2)" begin
    pins = _oracle_rows()
    @test length(pins) == 20                                        # the pins were read
    rows = LK.boot_image_predicates(LK.PL_global_data{_P}())
    ncompared = 0
    for ((name, arity), cols) in sort!(collect(pins))
        cols["foreign"] == "1" || continue                          # clauses of boot/*.pl are not the kernel's built-ins
        r = _row(rows, "system", name, arity)
        r === nothing && continue                                   # UNVERIFIED on the kernel: gate decides which of these the kernel registers
        ncompared += 1
        @test r.defined == (cols["defined"] == "1")
        @test r.foreign == (cols["foreign"] == "1")
        @test r.dynamic == (cols["dynamic"] == "1")
        @test r.iso == (cols["iso"] == "1")                         # UNVERIFIED on the kernel: gate decides
        @test r.transparent == (cols["transparent"] == "1")         # UNVERIFIED on the kernel: gate decides
        @test (r.number_of_clauses === nothing) == (cols["number_of_clauses"] == "none")
    end
    @test ncompared >= 8                                            # both sides non-empty: most of the pinned C predicates exist
end
