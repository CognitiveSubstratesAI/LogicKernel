# ORIGINAL: LB4 b2's T2 gate, the booted clauses (loader_boot design §6 T2) — upstream's boot compilation is the command src/CMakeLists.txt:357-361 runs (`swipl --home=HOME -q -O -o boot.prc -b HOME/boot/init.pl`); swipl-devel has no test of its boot image's clauses.
# test/db/test_boot_clauses_swipl.jl — T2 THE BOOTED CLAUSES, EQUAL UP TO VARIANT (=@=) PER STATIC PREDICATE:
#   * ONE Prolog driver, test_boot_clauses_swipl_rows.pl, runs on both sides: per static Prolog predicate DEFINED (not
#     imported, not foreign, not dynamic) in `system` and every module of a boot file, the number of clauses clause/2
#     gives and a HASH over an encoding of each clause in which the variables are numbered by first occurrence (equal
#     encodings <=> =@=); a full-text fixture would be ~1.3 MB, the rows are 138 KB;
#   * the oracle is test_boot_clauses_swipl_rows.out: swipl's own boot from source, with the driver and a one-line main
#     file as further files of the boot command (pl-qlf.c:4784-4806 compileFileList; the driver's header gives the
#     command). With `swipl` on PATH the command is run again here and its output must equal the .out byte for byte;
#   * the kernel's side: the booted database `PL_global_data{T}()`, the driver loaded into `user` (load_file!), its rows
#     enumerated through the query API and printed in the driver's text, BOTH sides read back by ONE parser;
#   * non-vacuity: over 1300 oracle rows, over 1000 common rows, over 2000 clauses in the common rows.
# THE KERNEL'S CONFIGURATION (FLAG F3, the audit's call): the kernel's boot does not apply the build's `-O`
# (src/pl-qlf.jl boot_global_data, pl-init.c:1280 `GD->cmdline.optimise`), and `optimise` changes clause bodies
# (expand.pl:1368-1370 simplify/4, init.pl:4118). The oracle is therefore swipl's boot WITHOUT `-O`: T2 is pinned for
# the kernel's current configuration. With `-O` swipl's rows differ in 33 predicates, all in `$tabling` (pinned in the
# oracle testset below; the list is evidence/LB4B2/t2_optimise_diff.txt): if F3 rules `-O` in, the .out is regenerated
# with it.
# DIVERGES (each with its upstream line; the ORACLE's rows rewritten to what upstream's own build with that configuration
# compiles, so the kernel is compared with that; the same rows as test_boot_image_swipl.jl's T1):
#   * `threads` is false in the kernel (audit D-0354 item 3, pl-prologflag.c:2620-2622; src/os/pl-prologflag.jl:1722):
#     init.pl:2557-2564 '$error_count'/2, init.pl:2720-2741 '$mt_load_file'/4 and toplevel.pl:560-582
#     main_thread_init/0 compile their single-thread clauses; init.pl:2754-2785 is skipped whole;
#   * `open_shared_object` is undefined in the kernel (audit D-0151 item 6, pl-prologflag.c:2593-2606; FLAG F8):
#     syspred.pl:485-493 unload_file_/1 keeps one clause, syspred.pl:497-589 defines none of its predicates.
#   The kernel's hash of each rewritten row is pinned from the first boot run (G9).
# NOT RUN when written (edit-only, LB4 b2 writer 7): every expectation on the kernel is UNVERIFIED on the kernel: gate
# decides; the `_BC_KERNEL_*` pins are filled from the first boot run (G9), each entry with its cause.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BC = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bcs(x) = lk_sym(_BC, Symbol(x))
_bce(f, xs::_BC...) = LK.mk_expr(_BC, _BC[_bcs(f), xs...])
_bcv(i) = lk_var(_BC, UInt64(i))

const _BC_SWIPL = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
const _BC_OUT = joinpath(@__DIR__, "test_boot_clauses_swipl_rows.out")
const _BC_DRIVER = joinpath(@__DIR__, "test_boot_clauses_swipl_rows.pl")

# ---- ONE text for a row (the driver's `format/2` line) and ONE parser for both sides
_bc_codes(s::AbstractString)::String = "[" * join(Int.(collect(s)), ",") * "]"
_bc_text(c::AbstractString)::String =
    c == "[]" ? "" : String(Char.(parse.(Int, split(c[2:(end - 1)], ","))))
_bc_line(m, n, a, nc, h)::String = "t2 $(_bc_codes(m)) $(_bc_codes(n)) $a $nc $h"

const _BcKey = Tuple{String, String, Int}
"Rows `t2 MODULE NAME ARITY NCLAUSES HASH` -> Dict((module, name, arity) => (nclauses, hash)); a key at most once."
function _bc_parse(lines::Vector{String})::Dict{_BcKey, Tuple{Int, Int}}
    d = Dict{_BcKey, Tuple{Int, Int}}()
    for l in lines
        p = split(l, ' ')
        @test length(p) == 6 && p[1] == "t2"
        length(p) == 6 || continue
        k = (_bc_text(p[2]), _bc_text(p[3]), parse(Int, p[4]))
        @test !haskey(d, k)
        d[k] = (parse(Int, p[5]), parse(Int, p[6]))
    end
    return d
end
_bc_key_line(k::_BcKey)::String = "$(k[1]):$(k[2])/$(k[3])"

# ---- the oracle's rows in the kernel's configuration (the DIVERGES of the header)
# undefined in the kernel's configuration (the T1 rows `=> nothing` that are static Prolog predicates)
const _BC_UNDEFINED = _BcKey[
    ("system", "\$mt_start_load", 3),                    # init.pl:2754-2785 (threads)
    ("system", "\$mt_do_load", 5),
    ("system", "\$mt_end_load", 1),
    ("\$syspreds", "use_foreign_library", 1),            # syspred.pl:497-589 (open_shared_object, FLAG F8)
    ("\$syspreds", "use_foreign_library", 2),
    ("\$syspreds", "use_foreign_library_noi", 1),
    ("\$syspreds", "ensure_shlib", 0)
]
# rewritten: (the clauses of the kernel's configuration, their hash). The hash is SWIPL'S: swipl 10.1.19 encodes, with
# this file's driver (lb4b2c_enc/2, lb4b2c_hash/3), the clause texts the kernel's configuration compiles at the pin
# (the unconditional and `:- else` branches, read with term_string/2); where swipl has the same clause, its clause/2
# encoding is identical (checked for all three: evidence/LB4B2/rw.pl, 2026-11-03).
const _BC_REWRITTEN = Dict{_BcKey, Tuple{Int, Union{Nothing, Int}}}(
    ("system", "\$error_count", 2) => (1, 1528547892),       # init.pl:2557-2564: the thread_statistics clause skipped
    ("system", "\$mt_load_file", 4) => (2, 1258476312),      # init.pl:2720-2741: the queue clause skipped
    ("\$toplevel", "main_thread_init", 0) => (1, 803882513), # toplevel.pl:560-582: the else clause only
    ("\$syspreds", "unload_file_", 1) => (1, 1523927706)    # syspred.pl:485-493: the shlib clause skipped (F8)
)

# ---- THE KERNEL'S PIN (G9 fills it from the first boot run, each entry with its cause; the list only shrinks):
# the common rows outside the configuration rows whose (clauses, hash) differ: "KEY swipl-nc swipl-hash kernel-nc kernel-hash"
const _BC_KERNEL_DIFFER = String[]

"The oracle's rows with the configuration rows taken out: `(rows, the rewritten rows' oracle values)`."
function _bc_oracle()
    o = _bc_parse(readlines(_BC_OUT))
    for k in _BC_UNDEFINED
        @test haskey(o, k)                                # every rewrite names a row the oracle has
        delete!(o, k)
    end
    rw = Dict{_BcKey, Tuple{Int, Int}}()
    for k in keys(_BC_REWRITTEN)
        @test haskey(o, k) && o[k][1] > _BC_REWRITTEN[k][1]   # the oracle's has the clause(s) the kernel skips
        haskey(o, k) && (rw[k] = pop!(o, k))
    end
    return o, rw
end

"The driver's rows over the modules `mods`, run in the booted kernel and printed in the driver's text."
function _bc_kernel(mods)::Vector{String}
    gd = LK.PL_global_data{_BC}()
    ld = LK.PL_local_data{_BC}(gd)
    st, ball = LK.load_file!(gd, ld, _BC_DRIVER)
    @test st === :ok && ball === nothing
    f = joinpath(mktempdir(), "lb4b2c_kernel.pl")
    write(
        f,
        "lb4b2c_kmods([" *
        join(("'" * replace(m, "'" => "\\'") * "'" for m in sort(collect(mods))), ",") *
        "]).\n" *
        "lb4b2c_krow(M, N, A, NC, H) :- lb4b2c_kmods(Ms), lb4b2c_row(Ms, M, N, A, NC, H).\n"
    )
    st, ball = LK.load_file!(gd, ld, f)
    @test st === :ok && ball === nothing
    goal = _bce(
        ":", _bcs(:user), _bce(:lb4b2c_krow, _bcv(1), _bcv(2), _bcv(3), _bcv(4), _bcv(5))
    )
    lines = String[]
    for a in LK.query_answers(ld, goal)
        g = LK.child(a, 3)
        push!(
            lines,
            _bc_line(
                LK.sym_text(LK.child(g, 2)), LK.sym_text(LK.child(g, 3)),
                (lk_value(LK.child(g, i))::Integer for i in 4:6)...
            )
        )
    end
    return lines
end

@testset "T2: the booted clauses =@= swipl's boot, per static predicate (config rows applied)" begin
    o, orw = _bc_oracle()
    omods = Set(k[1] for k in keys(o))
    k = _bc_parse(_bc_kernel(omods))
    # non-vacuity: both sides read, the common rows carry clauses
    @test length(o) > 1300 && length(k) > 1000 && length(omods) > 20
    common = intersect(Set(keys(o)), Set(keys(k)))
    @test length(common) > 1000
    @test sum(o[c][1] for c in common; init=0) > 2000
    # THE GUARDS. UNVERIFIED on the kernel: gate decides.
    differ = sort([
        "$(_bc_key_line(c)) $(o[c][1]) $(o[c][2]) $(k[c][1]) $(k[c][2])" for
        c in common if o[c] != k[c]
    ])
    differ == _BC_KERNEL_DIFFER ||
        println(stderr, "  PIN (_BC_KERNEL_DIFFER): ", repr(differ))
    @test differ == _BC_KERNEL_DIFFER
    @test all(c -> k[c][1] >= 0, common)                  # clause/2 raised on no common row (NCLAUSES -1)
    for (c, (nc, h)) in _BC_REWRITTEN
        @test haskey(k, c)
        haskey(k, c) || continue
        k[c] == (nc, h) ||
            println(stderr, "  PIN (_BC_REWRITTEN ", _bc_key_line(c), "): ", repr(k[c]))
        @test k[c][1] == nc                               # the configuration's clause count
        @test k[c] != orw[c]                              # and not the oracle's threaded/shlib body
        @test h !== nothing && k[c][2] == h               # swipl's hash of the configuration's clauses
    end
end

# swipl's -O rows differ from the oracle's (no -O) in these many predicates, all in `$tabling` (2026-11-02, the pin)
const _BC_OPTIMISE_DIFFER = 33

@testset "T2 oracle: swipl's boot prints the same rows again (and -O changes 33 \$tabling rows)" begin
    if _BC_SWIPL === nothing
        @test_skip "swipl not on PATH (the pin: test_boot_clauses_swipl_rows.out)"
    else
        m = match(
            r"PLBASE=\"([^\"]*)\"", readchomp(`$(_BC_SWIPL) --dump-runtime-variables=sh`)
        )
        @test m !== nothing
        plbase = String(m.captures[1])
        out = mktempdir()
        initpl = joinpath(plbase, "boot", "init.pl")
        mainpl = joinpath(out, "main.pl")
        write(mainpl, ":- lb4b2c_main.\n")
        rows = joinpath(out, "rows.out")
        cmd = `$(_BC_SWIPL) --home=$plbase -q -o $(joinpath(out, "a.prc")) -b $initpl $(_BC_DRIVER) $mainpl`
        p = run(pipeline(ignorestatus(cmd); stdout=rows, stderr=joinpath(out, "rows.err")))
        @test p.exitcode == 0 && read(joinpath(out, "rows.err"), String) == ""
        @test read(rows, String) == read(_BC_OUT, String)
        # FLAG F3's measure: the same boot WITH -O
        orows = joinpath(out, "rows_O.out")
        cmd = `$(_BC_SWIPL) --home=$plbase -q -O -o $(joinpath(out, "b.prc")) -b $initpl $(_BC_DRIVER) $mainpl`
        p = run(
            pipeline(ignorestatus(cmd); stdout=orows, stderr=joinpath(out, "rows_O.err"))
        )
        @test p.exitcode == 0
        o = _bc_parse(readlines(_BC_OUT))
        oo = _bc_parse(readlines(orows))
        @test keys(o) == keys(oo)
        d = [c for c in keys(o) if o[c] != oo[c]]
        @test length(d) == _BC_OPTIMISE_DIFFER && all(c -> c[1] == "\$tabling", d)
    end
end
