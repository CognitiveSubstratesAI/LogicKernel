# ORIGINAL: the test of tools/r2_status.jl, the generated R2 status (audit D-0370 item 1); no swipl-devel counterpart.
# test/test_r2_status.jl — the R2 generator on a small fixture tree, and both sides of each comparison non-empty on the real tree.
#
# Text only: no kernel term type is involved, so this file runs once (it is no `term_under_test` file).
using Test

include(joinpath(@__DIR__, "..", "tools", "r2_status.jl"))

"A fixture root: a vendor tree with boot files and one library file, and a kernel `src/`."
function _r2_fixture(base::AbstractString)
    boot = joinpath(base, "vendor", "swipl-devel", "boot")
    lib = joinpath(base, "vendor", "swipl-devel", "library")
    mkpath(boot)
    mkpath(lib)
    mkpath(joinpath(base, "src"))
    write(joinpath(boot, "init.pl"), """
% a comment mentioning old_pred(1,2,3)
my_helper(X) :- exists_file(X), atom_length('a b', _).
'\$memberchk'(a, b, c).
init :- sub_atom(abc, 0'a, 1, _, S), print_message(S), halt.
user_pred(X, Y) :- foo(X), bar(Y), baz.
""")
    write(joinpath(boot, "load.pl"), """
:- consult([ a, b ]).
:- if(current_prolog_flag(threads, true)).
:- consult(t).
:- endif.
:- consult([ user:c ]).
""")
    write(joinpath(boot, "a.pl"), "a_pred :- thread_self(_), time_file(f, _), my_helper(1), win_only(1).\n:- use_module(library(debug)).\n")
    write(joinpath(boot, "b.pl"), "b_pred :- exists_file(f), garbage_collect, '\$qlf_load'(x, y).\n")
    write(joinpath(boot, "c.pl"), "c_pred :- tab(2).\n")
    write(joinpath(boot, "t.pl"), "t_pred :- thread_create(g, _).\n")
    write(joinpath(lib, "debug.pl"), ":- use_module(library(lists)).\n:- autoload(library(dcg/high_order), [sequence/3]).\ndbg :- true.\n")
    write(joinpath(lib, "lists.pl"), "append(X, Y, Z) :- tab(X).\n")
    return base
end

const _R2_FIXTURE_C = """
/* a comment with PRED_IMPL("in_comment", 1, c, 0) */
PRED_IMPL("exists_file", 1, exists_file, 0)
PRED_IMPL("time_file", 2,
          time_file, 0)
PRED_IMPL("\$memberchk", 3, memberchk, 0)
PRED_IMPL("garbage_collect", 0, gc, 0)
PRED_IMPL("\$qlf_load", 2, qlf_load, 0)
#ifdef O_PLMT
PRED_IMPL("thread_self", 1, thread_self, 0)
PRED_IMPL("thread_create", 3, thread_create, 0)
#endif
#ifdef __WINDOWS__
PRED_IMPL("win_only", 1, win_only, 0)
#else
PRED_IMPL("not_win", 1, not_win, 0)
#endif
PRED_IMPL("tab", 1, tab1, 0)
PRED_IMPL("atom_length", 2, atom_length, 0)
VMI(I_ENTER, 0, 0, ())
VMI(A_ADD, 0, 0, ())
  FRG("frg_fixture", 0, pl_frg_fixture, 0),
"""

@testset "r2_status: the Prolog tokenizer and the call/head scans" begin
    toks = r2_tokenize("foo(a, [b,c], g(d)) :- bar, 0'a, 0''', X = 'it''s', 16'FF, 1.5e3, \"s(t)\".\n% c\nnext(1).\n")
    @test count(t -> t.kind == :end, toks) == 2
    cls = r2_clauses(toks)
    @test length(cls) == 2
    calls = r2_calls(cls[1])
    @test ("foo", 3, 1) in calls && ("g", 1, 1) in calls
    @test ("bar", 0, 1) in calls                               # an atom in goal position
    @test !any(c -> c[1] in ("b", "c", "d", "a"), calls)       # list elements and arguments are no goals
    @test r2_heads(cls) == Set(["foo/3", "next/1"])
    @test r2_heads(r2_clauses(r2_tokenize("x:y(1,2) :- true.\nd --> e.\nh.\n:- dynamic q/1.\n"))) == Set(["y/2", "d/2", "h/0"])
    @test r2_arity(r2_tokenize("f((a,b), c)"), 2) == (2, 10)
    # operators are calls too (:<, \=@=, is, a prefix directive operator), a clause neck is none
    oc = r2_calls(only(r2_clauses(r2_tokenize("p(X, Y) :- X :< Y, X \\=@= Y, Z is X + 1, =(X, Z), dynamic foo/1, q.\n"))))
    @test ":<" in first.(oc) && "\\=@=" in first.(oc) && ("is", 2, 1) in oc && ("=", 2, 1) in oc && ("dynamic", 1, 1) in oc
    @test !(":-" in first.(oc)) && ("q", 0, 1) in oc
end

@testset "r2_status: load.pl's consult lists, conditions and the library closure" begin
    mktempdir() do base
        _r2_fixture(base)
        files = r2_boot_files(base)
        rels = [f.rel for f in files]
        @test rels[1:2] == ["boot/init.pl", "boot/load.pl"]
        @test rels[3:6] == ["boot/a.pl", "boot/b.pl", "boot/t.pl", "boot/c.pl"]
        @test [f.loaded for f in files[3:6]] == [true, true, false, true]      # threads is false in the kernel
        @test files[5].cond == "current_prolog_flag(threads,true)"
        libs = [f.rel for f in files if f.kind == "library"]
        @test "library/debug.pl" in libs && "library/lists.pl" in libs && "library/dcg/high_order.pl" in libs
        @test !files[findfirst(f -> f.rel == "library/dcg/high_order.pl", files)].exists
        @test r2_library_deps(":- use_module(library(dcg/high_order)).\n:- autoload(library(lists), [append/3]).\nx :- y.\n") ==
              ["dcg/high_order", "lists"]
        @test r2_eval_cond("current_prolog_flag(threads, true)") === false
        @test r2_eval_cond("current_prolog_flag(threads, false)") === true
        @test r2_eval_cond("current_prolog_flag(windows, true)") === nothing
    end
end

@testset "r2_status: the upstream C scan, the registered scan, the predicate rows" begin
    up = r2_scan_c(_R2_FIXTURE_C, "src/pl-fixture.c")
    ukeys = Set(u.key for u in up if u.kind == "pred")
    @test "exists_file/1" in ukeys && "time_file/2" in ukeys && "\$memberchk/3" in ukeys   # the multi-line one too
    @test !("in_comment/1" in ukeys)
    @test "frg_fixture/0" in ukeys                                                       # FRG
    cls = Dict(u.key => u.cls for u in up if u.kind == "pred")
    @test cls["thread_self/1"] == "threads" && cls["win_only/1"] == "windows"
    @test cls["not_win/1"] == "" && cls["tab/1"] == ""                                     # `#else` and `#endif` close the class
    vmi = [u for u in r2_scan_c(_R2_FIXTURE_C, "src/pl-vmi.c") if u.kind == "vmi"]
    @test Set(u.key for u in vmi) == Set(["I_ENTER", "A_ADD"])
    @test isempty([u for u in up if u.kind == "vmi"])                                       # VMI() is read in pl-vmi.c only
    @test isempty([u for u in r2_scan_c(replace(_R2_FIXTURE_C, "VMI(" => "XMI("), "src/pl-vmi.c") if u.kind == "vmi"])
    reg = r2_registered([
        """
        const T = (
            PL_extension("exists_file", 1, f, 0),
            PL_extension(
                "\\\$memberchk", 3, g, 0
            ),
            # PL_extension("commented", 1, h, 0),
            PL_extension(     # PRED_SHARE("clause", 2, clause, META|NDET)
                "trailing_comment", 2, i, 0
            ),
        )
        """,
    ])
    @test reg == Set(["exists_file/1", "\$memberchk/3", "trailing_comment/2"])

    mktempdir() do base
        _r2_fixture(base)
        files = r2_boot_files(base)
        scan = r2_boot_scan(base, files)
        @test !isempty(scan.refs) && !isempty(scan.defined)                                # both sides non-empty
        @test "my_helper/1" in scan.defined && !("t_pred/0" in keys(scan.refs))
        @test !haskey(scan.refs, "thread_create/3")                                        # threads.pl is skipped
        rows = r2_pred_rows(scan.refs, up, reg, scan.defined)
        st = Dict(r.label => r.status for r in rows)
        @test st["exists_file/1"] == "done"
        @test st["time_file/2"] == "missing" && st["garbage_collect/0"] == "missing" && st["\$qlf_load/2"] == "missing"
        @test st["win_only/1"] == "platform"
        @test st["thread_self/1"] == "missing"
        @test !haskey(st, "my_helper/1")                                                   # defined by the boot Prolog itself
        @test !haskey(st, "foo/1")                                                         # no C definition: no row
        @test r2_counts(rows).done >= 1 && r2_counts(rows).nmissing >= 3 && r2_counts(rows).platform == 1
        ft = r2_file_table(files, rows)
        a = ft[findfirst(t -> t.rel == "boot/a.pl", ft)]
        @test a.done == 0 && a.nmissing == 2 && a.platform == 1                            # thread_self, time_file / win_only
        @test ft[findfirst(t -> t.rel == "boot/t.pl", ft)].loaded == false

        # MUTATION: registering time_file/2 moves exactly that row from missing to done
        rows2 = r2_pred_rows(scan.refs, up, union(reg, Set(["time_file/2"])), scan.defined)
        @test Dict(r.label => r.status for r in rows2)["time_file/2"] == "done"
        @test r2_counts(rows2).nmissing == r2_counts(rows).nmissing - 1
    end
end

@testset "r2_status: the committed upstream snapshot round-trips (the drift guard's input)" begin
    up = r2_scan_c(_R2_FIXTURE_C, "src/pl-vmi.c")
    text = r2_snapshot_text(up, "0123456789012345678901234567890123456789")
    back = r2_read_snapshot(text)
    @test !isempty(up) && !isempty(back)
    @test sort(back; by=u -> (u.kind, u.key)) == sort(unique(up); by=u -> (u.kind, u.key))
    @test startswith(text, "# swipl-devel 0123456789")
end

_r2_fixture_jl(; beta=true) = """
# $(R2_REFUSAL_EXCEPTION){T}(a, "in a comment", "X")
\"\"\"
doc mentioning $(R2_REFUSAL_EXCEPTION){T}(a, "in a docstring", "Y")
\"\"\"
function alpha(x::T) where {T}
    x > 0 || throw(
        $(R2_REFUSAL_EXCEPTION){T}(
            x,
            "a feature, \$(x)",
            "V9"
        )
    )
end
$(beta ? "beta(y) = throw($(R2_REFUSAL_EXCEPTION){Nothing}(y, \"other (with, comma)\", \"LB6\"))" : "")
function $(R2_QLF_REFUSAL_HELPER)(::Type{T}, name::String, arity::Int)::Union{} where {T}
    throw($(R2_REFUSAL_EXCEPTION){T}(mk_sym(T, Symbol(name)), "the QLF predicate \$name/\$arity", "LB3"))
end
function $(R2_FLAG_REFUSAL_HELPER)(key::T, effect::String) where {T}
    throw($(R2_REFUSAL_EXCEPTION){T}(key, effect, "R2 F1b"))
end
function pl_q1(ld)
    $(R2_QLF_REFUSAL_HELPER)(T, "\\\$qlf_versions", 6)
end
function pl_split(x)
    throw($(R2_REFUSAL_EXCEPTION){T}(x, "split
        what", "R2 first; " *
        "second part"))
end
function pl_dup(x)
    throw($(R2_REFUSAL_EXCEPTION){T}(x, "same", "S1")); throw($(R2_REFUSAL_EXCEPTION){T}(x, "same", "S2"))
end
"""

@testset "r2_status: the refusal sites (constructor by name, the QLF helper, comments and docstrings blanked)" begin
    rows = r2_refusal_rows(Dict("src/fix.jl" => _r2_fixture_jl()))
    @test !isempty(rows)
    labels = [r.label for r in rows]
    @test sort(labels) == sort(["a feature, \$(x)", "other (with, comma)", "QLF predicate \$qlf_versions/6", "same", "same", "split what"])
    @test all(r -> r.status == "refused" && r.cat == "refusal" && r.cfile == "src/fix.jl", rows)
    ks = [r.key for r in rows]
    @test length(unique(ks)) == length(ks)                                           # a second identical site gets a suffix
    @test "refusal:src/fix.jl::alpha::a feature, \$(x)" in ks && any(k -> startswith(k, "refusal:src/fix.jl::beta::"), ks)
    @test any(r -> r.label == "a feature, \$(x)" && occursin("step V9", r.detail), rows)
    @test "refusal:src/fix.jl::pl_dup::same #2" in ks
    # a literal split over lines (what, or a `"a; " * "b"` step) is ONE line: it must not break a TSV or Markdown row
    sp = only(r for r in rows if r.label == "split what")
    @test sp.detail == "line 25; step R2 first; second part" && all(r -> !occursin(r"[\n\t]", r.label * r.detail * r.key), rows)
    # MUTATION: one site fewer, one row fewer
    @test length(r2_refusal_rows(Dict("src/fix.jl" => _r2_fixture_jl(; beta=false)))) == length(rows) - 1
    @test r2_strip_jl("x = 1 # c\ny = 'a'  # d\nz = \"s # not a comment\"") == "x = 1    \ny = 'a'     \nz = \"s # not a comment\""
    @test r2_call_args("f(a, g(b, c), \"x,y\")", 2) == (["a", "g(b, c)", "\"x,y\""], 20)
end

@testset "r2_status: the real tree, both sides non-empty" begin
    root = abspath(joinpath(@__DIR__, ".."))
    files = r2_boot_files(root)
    rels = [f.rel for f in files]
    @test all(r -> r in rels, ["boot/init.pl", "boot/load.pl", "boot/tabling.pl", "boot/topvars.pl", "library/debug.pl"])
    @test files[findfirst(f -> f.rel == "boot/threads.pl", files)].loaded == false
    @test all(f -> f.exists, filter(f -> f.kind == "boot", files))
    scan = r2_boot_scan(root, files)
    reg = r2_registered(values(r2_kernel_texts(root)))
    @test length(scan.refs) > 500 && !isempty(scan.defined)
    @test length(reg) > 100 && "op/3" in reg && "between/3" in reg
    @test r2_pin(root) !== nothing
    rr = r2_refusal_rows(r2_kernel_texts(root))
    @test length(rr) > 40 && count(r -> r.cfile == "src/pl-qlf.jl", rr) >= 14       # the throw sites and the 14 QLF names
    @test length(unique(r.key for r in rr)) == length(rr)
end

@testset "r2_status: flags (referenced, defined, created, refused) and VM instructions" begin
    mktempdir() do base
        _r2_fixture(base)
        open(joinpath(base, "vendor", "swipl-devel", "boot", "a.pl"), "a") do io
            write(io, ":- create_prolog_flag(made_here, 1, []).\n:- set_prolog_flag(verbose, silent).\n" *
                      "q :- current_prolog_flag(bounded, B), current_prolog_flag(Var, _), B == Var.\n")
        end
        fs = r2_flag_scan(base, r2_boot_files(base))
        @test Set(keys(fs.refs)) == Set(["made_here", "verbose", "bounded", "threads"])    # threads: load.pl's own `:- if` && fs.created == Set(["made_here"])
        @test fs.refs["bounded"] == ["boot/a.pl"]
    end
    defd = r2_flags_defined([
        "setPrologFlag(gd, \"verbose\", FT_ATOM, 1)\nsetPrologFlag(\n    gd, ld, \"bounded\", FT_BOOL, x)\n# setPrologFlag(gd, \"commented\", FT_BOOL, x)\n",
    ])
    @test defd == Set(["verbose", "bounded"])
    jl = """
    function $(R2_FLAG_REFUSAL_HELPER)(key::T, effect::String) where {T}
        throw($(R2_REFUSAL_EXCEPTION){T}(key, effect, "R2 F1b"))
    end
    function setter()
        if name == "debug"
            $(R2_FLAG_REFUSAL_HELPER)(k, "debugmode")
        elseif name == "tty_control"
            val != x &&
                $(R2_FLAG_REFUSAL_HELPER)(k, "PushTty")
        end

        ci_is_flag(k) && $(R2_FLAG_REFUSAL_HELPER)(k, "ci_set_flag (pl-index.c)")
        sym_key(k) == sym_key(mk_sym(T, :autoload)) &&
            $(R2_FLAG_REFUSAL_HELPER)(k, "propagateAutoload")
    end
    """
    refusals = r2_flag_refusals(Dict("src/os/fix.jl" => jl))
    @test [(f, e) for (f, e, _, _) in refusals] ==
          [("debug", "debugmode"), ("tty_control", "PushTty"), (nothing, "ci_set_flag (pl-index.c)"), ("autoload", "propagateAutoload")]
    rows = r2_flag_rows(Dict("verbose" => ["boot/a.pl"], "ghost" => ["boot/a.pl"], "debug" => ["boot/a.pl"], "made_here" => ["boot/b.pl"]),
        Set(["made_here"]), Set(["verbose", "debug"]), refusals)
    st = Dict(r.key => r.status for r in rows)
    @test st["flag:verbose"] == "done" && st["flag:made_here"] == "done" && st["flag:ghost"] == "missing"
    @test st["flag:debug"] == "refused" && st["flag:autoload"] == "refused" && st["flag:(ci_set_flag (pl-index.c))"] == "refused"
    # MUTATION: dropping the refusal sites turns `debug` back into done (the refusal is what makes it refused)
    @test Dict(r.key => r.status for r in r2_flag_rows(Dict("debug" => ["x"]), Set{String}(), Set(["debug"]), []))["flag:debug"] == "done"

    markers = r2_vmi_markers(["# PORT: pl-vmi.c I_ENTER\n    # PORT: pl-vmi.c A_ADD as helper\nx = 1  # PORT: pl-vmi.c NOT_ON_ITS_OWN_LINE\n"])
    @test markers == Set(["I_ENTER", "A_ADD"])
    up = r2_scan_c(_R2_FIXTURE_C, "src/pl-vmi.c")
    vr = Dict(r.label => r.status for r in r2_vmi_rows(up, Set(["I_ENTER"])))
    @test vr == Dict("I_ENTER" => "done", "A_ADD" => "missing")
    @test all(==("missing"), values(Dict(r.label => r.status for r in r2_vmi_rows(up, Set{String}()))))      # MUTATION: no marker, no row done

    root = abspath(joinpath(@__DIR__, ".."))
    res = r2_collect(root, r2_upstream(root))
    fl = [r for r in res.rows if r.cat == "flag"]
    @test length(fl) > 50 && any(r -> r.status == "refused", fl) && any(r -> r.status == "done", fl) && any(r -> r.status == "missing", fl)
    @test count(r -> r.status == "refused", fl) == length(unique(r.key for r in fl if r.status == "refused"))
    vm = [r for r in res.rows if r.cat == "vmi"]
    @test length(vm) > 100 && any(r -> r.status == "done", vm) && any(r -> r.status == "missing", vm)
    @test Dict(r.label => r.status for r in vm)["I_NOP"] == "done"
end
