# ORIGINAL: LB4 b2's T1, T3 and H12 gates, the boot image (loader_boot design §6 T1 and T3, H12) — upstream's boot compilation is the command src/CMakeLists.txt:357-361 runs (`swipl --home=HOME -q -O -o boot.prc -b HOME/boot/init.pl`); swipl-devel has no test of its boot image's tables.
# test/db/test_boot_image_swipl.jl — T1 THE PREDICATES, T3 THE SOURCE FILES, H12 NO ATTRIBUTED VARIABLE IN A CLAUSE:
#   * the kernel's side is the booted database `PL_global_data{T}()` (src/pl-global.jl: a copy of the booted template),
#     read by src/boot_image.jl's `boot_image_predicates` (T1) and `boot_image_source_files` (T3), each row printed in
#     the text of the oracle's driver, and BOTH sides read back by ONE parser (`_bi_parse`);
#   * the oracle is test_boot_image_swipl_rows.out: swipl's own boot from source, with test_boot_image_swipl_rows.pl as
#     a second file of the boot command (pl-qlf.c:4784-4806 compileFileList), whose last directive prints the rows once
#     the boot files are loaded (the driver's header says how it was run). With `swipl` on PATH the command is run again
#     here and its output must equal the .out byte for byte;
#   * T1 compares the rows of `system` and of every module whose file is a boot file: a row per predicate DEFINED there
#     (current_predicate/2 with the module bound is syspred.pl:711-715 generate_current_predicate: `defined` = 1, the
#     kernel's `defined` column), not imported; columns dynamic, foreign, system (P_LOCKED), iso, transparent, meta,
#     public, exported, number_of_clauses (`none` where upstream's attribute fails, pl-proc.c:3648-3658);
#   * T3 compares the boot files in '$time_source_file'/3 order: type, load_count, number_of_clauses, reloading,
#     from_state (true during a boot: pl-srcfile.c:310 `GD->bootsession&1`, ported at src/pl-srcfile.jl:46), modules;
#   * H12 (loader_boot.md H12: once expand.pl's '$expand_term'/4 is in, a loaded clause's variables carry attributes
#     while it is compiled): every clause of those modules decompiled by clause/2 carries no attributed variable
#     (term_attvars/2 == []), none raises, and the static clauses counted equal T1's static clause sum, on each side;
#   * non-vacuity: both sides over 1000 rows, the common rows over 1000, the module sets equal and over 20.
# DIVERGES (each with its upstream line; the rows below rewrite the ORACLE's row to what upstream's own build with that
# configuration answers, so the kernel is compared with that):
#   * `threads` is false in the kernel (audit D-0354 item 3: upstream's MULTI_THREADED=OFF build,
#     pl-prologflag.c:2620-2622; src/os/pl-prologflag.jl:1722): init.pl:2557-2564, 2720-2741, 2754-2785 and
#     toplevel.pl:560-582 compile their single-thread branches, and load.pl:78-80 does not consult boot/threads.pl
#     (FLAG F6: the same ruling, the audit's nod);
#   * `open_shared_object` is undefined in the kernel (audit D-0151 item 6: a build without O_DYNAMIC_EXTENSIONS,
#     pl-prologflag.c:2593-2606; src/os/pl-prologflag.jl:34-36): syspred.pl:485-493 and 497-589 take neither branch
#     (`current_predicate('$activate_static_extension'/1)`, :549, fails in the kernel too), so use_foreign_library/1,2,
#     use_foreign_library_noi/1 and ensure_shlib/0 are left undefined and unload_file_/1 keeps one clause (FLAG F8: the
#     boot-file consequence of D-0151).
# KNOWN DIFFERENCE (LD12, audit D-0286 item 5): tabling.pl:2356 and :2407-2411 `:- table` raise in the kernel (pl-wrap.c
# is a deferred file, D-0353 item 1), so the five `'$wrap$…'` closures swipl's wrap_predicate makes stay undefined in
# the kernel.
# NOT RUN when written (edit-only, LB4 b2 writer 6): every expectation on the kernel is UNVERIFIED on the kernel: gate
# decides; the `_BI_KERNEL_*` pins are filled from the first boot run (G9), each entry with its cause.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BI = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bis(x) = lk_sym(_BI, Symbol(x))
_bie(f, xs::_BI...) = LK.mk_expr(_BI, _BI[_bis(f), xs...])
_biv(i) = lk_var(_BI, UInt64(i))

const _BI_SWIPL = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
const _BI_OUT = joinpath(@__DIR__, "test_boot_image_swipl_rows.out")
const _BI_DRIVER = joinpath(@__DIR__, "test_boot_image_swipl_rows.pl")

# ---- ONE text for a row (the driver's `format/2` lines) and ONE parser for both sides
_bi_codes(s::AbstractString)::String = "[" * join(Int.(collect(s)), ",") * "]"
_bi_text(c::AbstractString)::String =
    c == "[]" ? "" : String(Char.(parse.(Int, split(c[2:(end - 1)], ","))))
_bi_b(x::Bool)::Char = x ? '1' : '0'

"The kernel's T1 row in the driver's text: `t1 MODULE NAME ARITY FLAGS CLAUSES` (test_boot_image_swipl_rows.pl:29)."
function _bi_t1_line(r::LK.BootImagePredicate)::String
    fl = String(
        [_bi_b(r.dynamic), _bi_b(r.foreign), _bi_b(r.locked), _bi_b(r.iso),
        _bi_b(r.transparent), _bi_b(r.meta), _bi_b(r.public), _bi_b(r.exported)]
    )
    nc = r.number_of_clauses === nothing ? "none" : string(r.number_of_clauses)
    return "t1 $(_bi_codes(r.module_name)) $(_bi_codes(r.name)) $(r.arity) $fl $nc"
end

"The kernel's T3 row in the driver's text: `t3 FILE TYPE LOADS CLAUSES RELOADING FROM_STATE [MODULES]` (rows.pl:36)."
function _bi_t3_line(r::LK.BootImageSourceFile, bootdir::String)::String
    mods = "[" * join(("'" * m * "'" for m in sort(r.modules)), ",") * "]"
    return join(
        [
            "t3", r.name[(length(bootdir) + 1):end], string(r.type), string(r.load_count),
            string(r.number_of_clauses), string(r.reloading), string(r.from_state), mods
        ],
        " "
    )
end

const _BiKey = Tuple{String, String, Int}
const _BiT1 = Tuple{String, Union{Nothing, Int}}        # (the eight flags, number_of_clauses)

"ONE parser for both sides: T1 as a Dict by (module, name, arity), T3 as its rows in order, modules unquoted."
function _bi_parse(lines::Vector{String})
    t1 = Dict{_BiKey, _BiT1}()
    t3 = Vector{Tuple{String, String, Int, Int, String, String, Vector{String}}}()
    for l in lines
        p = split(l, ' '; limit=8)
        if p[1] == "t1"
            @assert length(p) == 6 l
            key = (_bi_text(p[2]), _bi_text(p[3]), parse(Int, p[4]))
            @assert !haskey(t1, key) l
            t1[key] = (String(p[5]), p[6] == "none" ? nothing : parse(Int, p[6]))
        elseif p[1] == "t3"
            @assert length(p) == 8 l
            ms = if p[8] == "[]"
                String[]
            else
                [strip(m, '\'') for m in split(p[8][2:(end - 1)], ",")]
            end
            push!(
                t3,
                (
                    String(p[2]),
                    String(p[3]),
                    parse(Int, p[4]),
                    parse(Int, p[5]),
                    String(p[6]),
                    String(p[7]),
                    sort(String.(ms))
                )
            )
        else
            error("test_boot_image_swipl: a line that is no row: $l")
        end
    end
    return t1, t3
end

# ---- the oracle's rows rewritten to the kernel's configuration (the DIVERGES of the header; `nothing` = undefined there)
const _BI_T1_CONFIG = Dict{_BiKey, Union{Nothing, Int}}(
    # threads false (D-0354 item 3)
    ("system", "\$error_count", 2) => 1,                # init.pl:2557-2564: the thread_statistics clause is skipped
    ("system", "\$mt_load_file", 4) => 2,               # init.pl:2720-2741: the queue clause skipped, the else one taken
    ("system", "\$mt_start_load", 3) => nothing,        # init.pl:2754-2785: the block is skipped whole
    ("system", "\$mt_do_load", 5) => nothing,
    ("system", "\$mt_end_load", 1) => nothing,
    ("\$toplevel", "main_thread_init", 0) => 1,         # toplevel.pl:560-582: the else clause only
    # a dynamic fact per file load_files/2 loads (init.pl:3204-3225 `'$assert_load_context_module'`; init.pl itself is
    # compiled by compileFile, not load_files): swipl's 24 include boot/threads.pl, which load.pl:78-80 leaves out (FLAG F6)
    ("system", "\$load_context_module", 3) => 23,
    # open_shared_object undefined (D-0151 item 6; FLAG F8)
    ("\$syspreds", "unload_file_", 1) => 1,             # syspred.pl:485-493: the shlib clause is skipped
    ("\$syspreds", "use_foreign_library", 1) => nothing,     # syspred.pl:497-548, and the elif of :549-589 fails too
    ("\$syspreds", "use_foreign_library", 2) => nothing,
    ("\$syspreds", "use_foreign_library_noi", 1) => nothing,
    ("\$syspreds", "ensure_shlib", 0) => nothing,
    # KNOWN DIFFERENCE LD12: wrap_predicate's closures of tabling.pl:2356 and :2407-2411 (pl-wrap.c deferred)
    ("\$tabling", "\$wrap\$eval_subgoal_in_residual", 2) => nothing,
    ("system", "\$wrap\$answer_count_restraint", 0) => nothing,
    ("system", "\$wrap\$radial_restraint", 0) => nothing,
    ("system", "\$wrap\$tabled_call", 1) => nothing,
    ("system", "\$wrap\$undefined", 0) => nothing
)
# T3: (file => the change of its number_of_clauses in the kernel's configuration, `nothing` = not loaded): the static
# clauses of the rows above, by file (dynamic facts asserted at run time are no clause of a file)
const _BI_T3_CONFIG = Dict{String, Union{Nothing, Int}}(
    "threads.pl" => nothing,       # load.pl:78-80 (FLAG F6)
    "init.pl" => -11,              # '$error_count' -1, '$mt_load_file' -1, '$mt_start_load'/'$mt_do_load'/'$mt_end_load' -9
    "toplevel.pl" => -1,           # main_thread_init -1
    "syspred.pl" => -6             # unload_file_ -1, use_foreign_library/1,2 -2, use_foreign_library_noi -1, ensure_shlib -2
)
# The oracle's row of '$directive_mode_store'/1 (1 clause) is read INSIDE the driver's directive (init.pl:1741-1743);
# the kernel's after the boot. Kept as swipl's: UNVERIFIED on the kernel: gate decides.

# ---- THE KERNEL'S PINS (G9 fills each from the first boot run, with its cause; UNVERIFIED on the kernel: gate decides)
const _BI_KERNEL_ONLY = String[]          # rows the kernel defines that swipl's boot image does not (`t1` lines)
const _BI_KERNEL_MISSING_PROLOG = String[] # swipl's Prolog (foreign 0) rows the kernel lacks after the config rewrite
const _BI_KERNEL_COLUMNS = String[]       # rows on both sides whose columns differ: "KEY swipl-cols kernel-cols"
const _BI_KERNEL_MISSING_FOREIGN = -1     # how many of swipl's foreign rows the kernel lacks (the list only shrinks)
const _BI_KERNEL_MODULES_LACKING = String[] # swipl's T1 modules the kernel's boot has no module (or no row) for

"The oracle's T1/T3 with the configuration rows applied."
function _bi_oracle()
    t1, t3 = _bi_parse(readlines(_BI_OUT))
    for (k, n) in _BI_T1_CONFIG
        @test haskey(t1, k)                               # every rewrite names a row the oracle has
        if n === nothing
            delete!(t1, k)
        else
            t1[k] = (t1[k][1], n)
        end
    end
    files = Set(r[1] for r in t3)
    @test all(f -> f in files, keys(_BI_T3_CONFIG))
    t3c = empty(t3)
    for r in t3
        d = get(_BI_T3_CONFIG, r[1], 0)
        d === nothing && continue                         # not loaded in the kernel's configuration
        push!(t3c, (r[1], r[2], r[3], r[4] + d, r[5], r[6], r[7]))
    end
    return t1, t3c
end

"The kernel's booted database read as the driver's text, then parsed: `(t1, t3, modules)`."
function _bi_kernel(gd::LK.PL_global_data{_BI})
    home = LK.current_prolog_flag_atom(gd, LK.mk_sym(_BI, :home))
    @test home !== nothing
    bootdir = joinpath(LK.sym_text(home), "boot") * "/"
    files = [f for f in LK.boot_image_source_files(gd) if startswith(f.name, bootdir)]
    mods = Set{String}(["system"])
    foreach(f -> union!(mods, f.modules), files)          # the driver's lb4b2_module/1 (rows.pl:10-11)
    rows = [r for r in LK.boot_image_predicates(gd) if r.defined && r.module_name in mods]
    lines = vcat(
        String[_bi_t1_line(r) for r in rows], String[_bi_t3_line(f, bootdir) for f in files]
    )
    t1, t3 = _bi_parse(lines)
    return t1, t3, mods
end

_bi_key_line(k::_BiKey)::String = "$(k[1]):$(k[2])/$(k[3])"

@testset "T1: the boot image's predicates == swipl's boot (config rows applied)" begin
    o1, _ = _bi_oracle()
    k1, _, kmods = _bi_kernel(LK.PL_global_data{_BI}())
    omods = Set(k[1] for k in keys(o1))
    # non-vacuity: both sides read, over the same modules
    @test length(o1) > 2000 && length(k1) > 1000
    @test length(omods) > 20 && kmods ⊇ setdiff(omods, _BI_KERNEL_MODULES_LACKING)
    common = intersect(Set(keys(o1)), Set(keys(k1)))
    @test length(common) > 1000
    @test count(k -> o1[k][1][2] == '0', common) > 1000   # Prolog rows, not only foreign ones
    # THE GUARDS. UNVERIFIED on the kernel: gate decides.
    only_k = sort([_bi_key_line(k) for k in setdiff(keys(k1), keys(o1))])
    lacking = setdiff(Set(keys(o1)), Set(keys(k1)))
    missing_prolog = sort([_bi_key_line(k) for k in lacking if o1[k][1][2] == '0'])
    missing_foreign = count(k -> o1[k][1][2] == '1', lacking)
    cols = sort([
        "$(_bi_key_line(k)) $(o1[k][1]) $(something(o1[k][2], "none")) $(k1[k][1]) $(something(k1[k][2], "none"))"
        for k in common if o1[k] != k1[k]
    ])
    # a value that differs from its pin is printed whole, to paste (a failing `@test` would print a summary only)
    for (name, v, pin) in (
        ("_BI_KERNEL_ONLY", only_k, _BI_KERNEL_ONLY),
        ("_BI_KERNEL_MISSING_PROLOG", missing_prolog, _BI_KERNEL_MISSING_PROLOG),
        ("_BI_KERNEL_COLUMNS", cols, _BI_KERNEL_COLUMNS),
        ("_BI_KERNEL_MISSING_FOREIGN", missing_foreign, _BI_KERNEL_MISSING_FOREIGN),
        (
            "_BI_KERNEL_MODULES_LACKING",
            sort(collect(setdiff(omods, kmods))),
            _BI_KERNEL_MODULES_LACKING
        )
    )
        v == pin || println(stderr, "  PIN (", name, "): ", repr(v))
    end
    @test only_k == _BI_KERNEL_ONLY
    @test missing_prolog == _BI_KERNEL_MISSING_PROLOG
    @test cols == _BI_KERNEL_COLUMNS
    @test missing_foreign == _BI_KERNEL_MISSING_FOREIGN
    @test sort(collect(setdiff(omods, kmods))) == _BI_KERNEL_MODULES_LACKING
end

@testset "T3: the boot image's source files == swipl's boot (config rows applied)" begin
    _, o3 = _bi_oracle()
    _, k3, _ = _bi_kernel(LK.PL_global_data{_BI}())
    @test length(o3) == 24 && length(k3) > 20             # non-vacuity: 25 boot files in swipl, threads.pl left out
    @test all(r -> r[3] == 1 && r[6] == "true", o3)       # from source: loaded once, from_state (pl-srcfile.c:310)
    # THE GUARD: order, type, load_count, clauses, reloading, from_state, modules. UNVERIFIED on the kernel: gate decides.
    if k3 != o3   # printed whole, to paste: the rows that differ, `(row, kernel, swipl)`
        n = max(length(k3), length(o3))
        get3(v, i) = i <= length(v) ? v[i] : nothing
        println(
            stderr,
            "  PIN (T3): ",
            repr([
                (i, get3(k3, i), get3(o3, i)) for i in 1:n if get3(k3, i) != get3(o3, i)
            ])
        )
    end
    @test [r[1] for r in k3] == [r[1] for r in o3]
    @test k3 == o3
end

# ---- H12: the same Prolog text on both sides; the module list from the oracle's T1 rows
const _BI_H12 = raw"""
lk_h12(NS, ND, NA, NE) :-
    lk_h12_mods(Ms),
    findall(Y-R, ( lk_h12_member(M, Ms), current_predicate(_, M:H),
                   \+ predicate_property(M:H, imported_from(_)), \+ predicate_property(M:H, foreign),
                   ( predicate_property(M:H, dynamic) -> Y = d ; Y = s ),
                   catch(( clause(M:H, B), term_attvars(H-B, R) ), _, R = error) ), Rs),
    lk_h12_count(Rs, 0, NS, 0, ND, 0, NA, 0, NE).
lk_h12_count([], S, S, D, D, A, A, E, E).
lk_h12_count([Y-R|Rs], S0, S, D0, D, A0, A, E0, E) :-
    ( Y == s -> S1 is S0+1, D1 = D0 ; S1 = S0, D1 is D0+1 ),
    ( R == error -> A1 = A0, E1 is E0+1 ; R == [] -> A1 = A0, E1 = E0 ; A1 is A0+1, E1 = E0 ),
    lk_h12_count(Rs, S1, S, D1, D, A1, A, E1, E).
lk_h12_member(X, [X|_]).
lk_h12_member(X, [_|T]) :- lk_h12_member(X, T).
"""
# swipl's answer at the pin (the boot command with the text above as a second file and the directive
# `:- lk_h12(S, D, A, E), format("h12 ~d ~d ~d ~d~n", [S, D, A, E]).`, 2026-11-02, two runs identical): 3240 static and
# 192 dynamic clauses, none with an attributed variable, none raising; 3240 and 192 are the .out's T1 sums.
const _BI_H12_SWIPL = (3240, 192, 0, 0)

_bi_h12_text(mods)::String =
    "lk_h12_mods([" *
    join(("'" * replace(m, "'" => "\\'") * "'" for m in sort(collect(mods))), ",") *
    "]).\n" * _BI_H12
_bi_static_sum(t1, mods)::Int =
    sum(
        something(v[2], 0) for
        (k, v) in t1 if k[1] in mods && v[1][1] == '0' && v[1][2] == '0';
        init=0
    )

@testset "H12: no attributed variable in a booted clause (clause/2 + term_attvars/2, both sides)" begin
    o1, _ = _bi_oracle()
    omods = Set(k[1] for k in keys(o1))
    oraw, _ = _bi_parse(readlines(_BI_OUT))
    # swipl's pin is consistent with its own rows (the config rewrite is the kernel's, so the raw rows count here)
    @test _BI_H12_SWIPL[1] == _bi_static_sum(oraw, omods) && _BI_H12_SWIPL[3] == 0 &&
        _BI_H12_SWIPL[4] == 0
    gd = LK.PL_global_data{_BI}()
    ld = LK.PL_local_data{_BI}(gd)
    k1, _, _ = _bi_kernel(gd)                             # read BEFORE the load below adds its own facts
    f = joinpath(mktempdir(), "lk_h12.pl")
    write(f, _bi_h12_text(omods))
    st, ball = LK.load_file!(gd, ld, f)
    @test st === :ok && ball === nothing
    ans = LK.query_answers(
        ld,
        _bie(":", _bis(:user), _bie(:lk_h12, _biv(1), _biv(2), _biv(3), _biv(4)));
        limit=1
    )
    @test length(ans) == 1
    if length(ans) == 1
        g = LK.child(ans[1], 3)
        ns, nd, na, ne = (lk_value(LK.child(g, i))::Integer for i in 2:5)
        # THE GUARD. UNVERIFIED on the kernel: gate decides.
        @test na == 0 && ne == 0
        @test ns == _bi_static_sum(k1, omods) && ns > 1000  # every static clause decompiled (non-vacuity)
        @test nd > 0
    end
end

@testset "T1/T3/H12 oracle: swipl's boot prints the same rows again" begin
    if _BI_SWIPL === nothing
        @test_skip "swipl not on PATH (the pin: test_boot_image_swipl_rows.out, h12 $(_BI_H12_SWIPL))"
    else
        m = match(
            r"PLBASE=\"([^\"]*)\"", readchomp(`$(_BI_SWIPL) --dump-runtime-variables=sh`)
        )
        @test m !== nothing
        plbase = String(m.captures[1])
        out = mktempdir()
        initpl = joinpath(plbase, "boot", "init.pl")
        rows = joinpath(out, "rows.out")
        cmd = `$(_BI_SWIPL) --home=$plbase -q -O -o $(joinpath(out, "a.prc")) -b $initpl $(_BI_DRIVER)`
        p = run(pipeline(ignorestatus(cmd); stdout=rows, stderr=joinpath(out, "rows.err")))
        @test p.exitcode == 0 && read(joinpath(out, "rows.err"), String) == ""
        @test read(rows, String) == read(_BI_OUT, String)
        o1, _ = _bi_oracle()
        h = joinpath(out, "h12.pl")
        write(
            h,
            _bi_h12_text(Set(k[1] for k in keys(o1))) *
            ":- lk_h12(S, D, A, E), format(\"h12 ~d ~d ~d ~d~n\", [S, D, A, E]).\n"
        )
        cmd = `$(_BI_SWIPL) --home=$plbase -q -O -o $(joinpath(out, "b.prc")) -b $initpl $h`
        @test readchomp(ignorestatus(cmd)) == "h12 " * join(_BI_H12_SWIPL, " ")
    end
end
