# ORIGINAL: FL1-FLAGS (R2; audit D-0501, NOOWNER 4b9054fa) — the 24 flag rows NOOWNER gave to owner FL1, closed against swipl at the pin (18168e62, built
# 10.1.20, x86_64-linux); UNTESTED, nothing compiled (written without a Julia run: the gate decides).
# test/core_lang/test_fl1_flags_swipl.jl — what `current_prolog_flag/2` and `set_prolog_flag/2` answer for those flags after a START-UP, so after
# `$initialise` has run (the flags the Prolog of boot/toplevel.pl and boot/init.pl creates exist only then), through swipl's `main()` of the kernel
# (`PL_initialise!`, the `-g` goal, `-t halt`: the harness of test_firstboot_swipl.jl) against `swipl -f none -F none -g GOAL -t halt`.
#   * ROWS a1-a9: every answer line is swipl's, PINNED (the pin's swipl 10.1.20, LC_ALL=C, stdin devnull, each row run twice, byte-identical; the
#     machine-dependent flags (paths, pids, `associated_file`, `hyperlink_term`'s default) are checked for presence or type only, with the
#     comment saying why). With `swipl` on PATH the live answers are compared with the pins too (the last testset).
#       a1 the C flags the Linux build defines (value, and what a set of the same value answers: `file_name_case_handling` is read-only);
#       a2 the C flags the Linux build does NOT define (platform/build conditions of pl-prologflag.c: __APPLE__, __EMSCRIPTEN__, __WINDOWS__, O_DEBUG,
#          PLSHAREDHOME, `GD->options.xpce >= 0`): absent;
#       a3 `open_shared_object`: DEFINED in swipl (O_DYNAMIC_EXTENSIONS, read-only true), UNDEFINED in the kernel (audit D-0151 item 6, FLAG F8: the
#          kernel answers as the build WITHOUT dynamic extensions). A KNOWN DIFFERENCE: the kernel's exact answer is pinned in `_FL_KERNEL_DIFF`, swipl's
#          in the row (`open_shared_object-true-permission_error(modify,flag,open_shared_object)`);
#       a4 the five clause-indexing pseudo flags of pl-index.c (`ci_*`): the values read and what a same-value set answers;
#       a5 the flags Prolog creates, as they stand after start-up; a6 the same flags created the way the boot and the libraries create them, then read;
#       a7 a created bool flag answers `type_error(bool, foo)`; a8 `hyperlink_term` and `save_history` appear when their library loads.
#   * a9 is swipl's `ci_set_flag` (the flags are settable) and is NOT compared with the kernel: the kernel refuses to set them by name (`NotPortedError`,
#     src/os/pl-prologflag.jl `_flag_not_ported(k, "ci_set_flag (pl-index.c)")`: the five parameters are Julia constants of src/pl-index.jl, where
#     upstream keeps them in `GD->clause_index`); the LK-ONLY testset pins that the kernel does not answer as swipl does.
# Mutation-tested by tools/mutants/FL1F.py.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the flag table (src/os/pl-prologflag.jl) built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _FL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_fls(x) = lk_sym(_FL, Symbol(x))

# (id, what, the `-g` goal, swipl's standard output)
const _FL_ROWS = Tuple{String, String, String, String}[
    ("a1",
        "C flags defined on Linux: value and access (agc_margin, file_name_case_handling, incomparable, stack_limit, theme)",
        "forall(member(F,[agc_margin,file_name_case_handling,incomparable,stack_limit,theme]), ((current_prolog_flag(F,V) -> (catch(set_prolog_flag(F,V),error(E,_),true), (var(E)->A=ok;A=E), print(F-V-A)) ; print(F-absent)), nl))",
        "agc_margin-10000-ok\nfile_name_case_handling-case_sensitive-permission_error(modify,flag,file_name_case_handling)\nincomparable-arbitrary-ok\nstack_limit-1073741824-ok\ntheme-default-ok\n"
    ),
    ("a2",
        "C flags the Linux build does not define: absent (apple, apple_universal_binary, bundle, emscripten, prolog_debug, shared_home, windows, xpce)",
        "forall(member(F,[apple,apple_universal_binary,bundle,emscripten,prolog_debug,shared_home,windows,xpce]), ((current_prolog_flag(F,V) -> (catch(set_prolog_flag(F,V),error(E,_),true), (var(E)->A=ok;A=E), print(F-V-A)) ; print(F-absent)), nl))",
        "apple-absent\napple_universal_binary-absent\nbundle-absent\nemscripten-absent\nprolog_debug-absent\nshared_home-absent\nwindows-absent\nxpce-absent\n"
    ),
    ("a3",
        "open_shared_object: swipl defines it (O_DYNAMIC_EXTENSIONS), the kernel does not (D-0151 item 6)",
        "forall(member(F,[open_shared_object]), ((current_prolog_flag(F,V) -> (catch(set_prolog_flag(F,V),error(E,_),true), (var(E)->A=ok;A=E), print(F-V-A)) ; print(F-absent)), nl))",
        "open_shared_object-true-permission_error(modify,flag,open_shared_object)\n"),
    ("a4", "the clause-indexing pseudo flags: value and access of the five ci_* flags",
        "forall(member(F,[ci_min_speedup,ci_max_var_fraction,ci_min_speedup_ratio,ci_max_lookahead,ci_min_clauses]), ((current_prolog_flag(F,V) -> (catch(set_prolog_flag(F,V),error(E,_),true), (var(E)->A=ok;A=E), print(F-V-A)) ; print(F-absent)), nl))",
        "ci_min_speedup-1.5-ok\nci_max_var_fraction-0.10000000149011612-ok\nci_min_speedup_ratio-3.0-ok\nci_max_lookahead-100-ok\nci_min_clauses-10-ok\n"
    ),
    ("a5", "the flags Prolog creates, as they stand after start-up (-f none -F none -g)",
        "forall(member(F,[app_name,associated_file,readline,toplevel_thread,xref,hyperlink_term,save_history,saved_program_class]), ((current_prolog_flag(F,V) -> (( memberchk(F,[toplevel_thread,xref]) -> print(F-V) ; print(F-present) )) ; print(F-absent)), nl))",
        "app_name-absent\nassociated_file-absent\nreadline-absent\ntoplevel_thread-false\nxref-false\nhyperlink_term-absent\nsave_history-absent\nsaved_program_class-absent\n"
    ),
    ("a6",
        "the flags Prolog creates, created as the boot and the libraries do and read back",
        "create_prolog_flag(save_history,true,[type(boolean)]), create_prolog_flag(hyperlink_term,false,[type(boolean),keep(true)]), create_prolog_flag(saved_program_class,runtime,[]), set_prolog_flag(app_name,foo), set_prolog_flag(associated_file,'/x/y.pl'), set_prolog_flag(readline,false), set_prolog_flag(toplevel_thread,true), set_prolog_flag(xref,true), forall(member(F,[save_history,hyperlink_term,saved_program_class,app_name,associated_file,readline,toplevel_thread,xref]), (current_prolog_flag(F,V), print(F-V), nl))",
        "save_history-true\nhyperlink_term-false\nsaved_program_class-runtime\napp_name-foo\nassociated_file-'/x/y.pl'\nreadline-false\ntoplevel_thread-true\nxref-true\n"
    ),
    ("a7", "a created bool flag refuses a non-bool value: type_error(bool, foo)",
        "create_prolog_flag(save_history,true,[type(boolean)]), create_prolog_flag(hyperlink_term,false,[type(boolean),keep(true)]), forall(member(F,[save_history,hyperlink_term,xref,toplevel_thread]), (catch((set_prolog_flag(F,foo),print(F-ok)),error(E,_),print(F-E)), nl))",
        "save_history-type_error(bool,foo)\nhyperlink_term-type_error(bool,foo)\nxref-type_error(bool,foo)\ntoplevel_thread-type_error(bool,foo)\n"
    ),
    ("a8",
        "the flags a library creates: ansi_term makes hyperlink_term, prolog_history makes save_history",
        "use_module(library(ansi_term)), use_module(library(prolog_history)), forall(member(F,[hyperlink_term,save_history]), (current_prolog_flag(F,V), (V==true;V==false), print(F-bool), nl))",
        "hyperlink_term-bool\nsave_history-bool\n"),
    ("a9",
        "ci_set_flag: swipl sets the clause-indexing flags (LK-ONLY row below pins the kernel's refusal)",
        "set_prolog_flag(ci_min_clauses,20), set_prolog_flag(ci_min_speedup,2.5), forall(member(F,[ci_min_clauses,ci_min_speedup]), (current_prolog_flag(F,V), print(F-V), nl))",
        "ci_min_clauses-20\nci_min_speedup-2.5\n")
]

# the rows where the kernel's answer differs from swipl's, with the kernel's CURRENT answer (a known difference, pinned both ways)
const _FL_KERNEL_DIFF = Dict{String, String}(
    "a3" => "open_shared_object-absent\n"           # swipl: open_shared_object-true-permission_error(modify,flag,open_shared_object)
)
# the rows the kernel cannot run (a Julia refusal propagates); only swipl's side is checked
const _FL_SWIPL_ONLY = ("a9",)

"""
A run of swipl's `main()` on `-g goal -t halt` after `-f none -F none`: `(exit status, standard output, Warning: lines)`; the three standard
streams are buffers, installed before `PL_initialise!` (the `-g` goal runs inside it).
"""
function _fl_run(goal::String)
    gd = LK.PL_global_data{_FL}()
    gd.halt_exit = false
    ld = LK.PL_local_data{_FL}(gd)
    bufs = (IOBuffer(), IOBuffer(), IOBuffer())
    ui = LK.set_standard_stream!(ld, LK.SNO_USER_INPUT, bufs[1])
    uo = LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, bufs[2])
    ue = LK.set_standard_stream!(ld, LK.SNO_USER_ERROR, bufs[3])
    ok = LK.PL_initialise!(
        gd, ld, String["swipl", "-f", "none", "-F", "none", "-g", goal, "-t", "halt"]
    )
    if ok && isempty(gd.halt_exited)
        rc = LK.query_loop(gd, ld, LK.mk_sym(_FL, Symbol("\$toplevel")), true)
        isempty(gd.halt_exited) && LK.PL_halt(gd, ld, rc == 1 ? 0 : 1)
    elseif !ok && isempty(gd.halt_exited)
        LK.PL_halt(gd, ld, 1)
    end
    LK.Sflush(uo)
    LK.Sflush(ue)
    out = String(take!(bufs[2]))
    warns = String[
        l for l in split(String(take!(bufs[3])), '\n') if startswith(l, "Warning:")
    ]
    status = length(gd.halt_exited) == 1 ? gd.halt_exited[1] : -1
    return status, out, warns
end

@testset "the 24 FL1 flags: swipl's answers after start-up (rows a1-a8)" begin
    # UNVERIFIED on the kernel: gate decides (a5 and a6 need `toplevel_thread`, `xref` created by `$initialise`; a8 loads two libraries)
    for (id, what, goal, swipl_out) in _FL_ROWS
        id in _FL_SWIPL_ONLY && continue
        @testset "$id: $what" begin
            st, out, warns = _fl_run(goal)
            want = get(_FL_KERNEL_DIFF, id, swipl_out)
            out == want || println(stderr, "  ours  ", repr(out), "\n  want  ", repr(want))
            @test st == 0
            @test out == want
            @test isempty(warns)
        end
    end
end

# NOT VACUOUS: the pins hold absent AND present answers, value AND error answers, through the one extractor (the `F-...` lines)
@testset "the pins are not empty on either side" begin
    lines = String[l for (_, _, _, o) in _FL_ROWS for l in split(o, '\n'; keepempty=false)]
    @test count(l -> endswith(l, "-absent"), lines) >= 12     # a2 (8) and a5 (6)
    @test count(l -> occursin("-permission_error(", l), lines) >= 2
    @test count(l -> occursin("-type_error(bool,foo)", l), lines) == 4
    @test count(l -> endswith(l, "-ok"), lines) >= 9      # a1 (4) and a4 (5)
    @test length(_FL_ROWS) == 9 && all(r -> !isempty(r[4]), _FL_ROWS)
    @test only(filter(r -> r[1] == "a3", _FL_ROWS))[4] !=
        _FL_KERNEL_DIFF["a3"]                              # the known difference is a difference
end

# LK-ONLY: the clause-indexing flags: upstream's `ciflags` order and the kernel's refusal to set them (ci_set_flag is the one item of the 24 the kernel still refuses)
@testset "LK-ONLY: ci_* flags are known to the kernel; setting them is refused by name, not answered as swipl" begin
    # UNVERIFIED on the kernel: gate decides
    @test LK.CI_FLAG_NAMES == (
        "ci_min_speedup", "ci_max_var_fraction", "ci_min_speedup_ratio",
        "ci_max_lookahead", "ci_min_clauses"
    )
    for n in LK.CI_FLAG_NAMES
        @test LK.ci_is_flag(_fls(n))
    end
    @test !LK.ci_is_flag(_fls("ci_no_such_flag"))
    @test !LK.ci_is_flag(_fls("stack_limit"))
    a9 = only(filter(r -> r[1] == "a9", _FL_ROWS))
    r = try
        _fl_run(a9[3])
    catch e
        e
    end
    # swipl's answer is `ci_min_clauses-20` and `ci_min_speedup-2.5` (the pin): the kernel's is a NotPortedError, or at least not that
    @test r isa LK.NotPortedError || (r isa Tuple && r[2] != a9[4])
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "FL1-FLAGS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        for (id, what, goal, swipl_out) in _FL_ROWS
            live = read(
                setenv(
                    pipeline(
                        `$swipl -f none -F none -g $goal -t halt`;
                        stdin=devnull,
                        stderr=devnull
                    ),
                    "LC_ALL" => "C"
                ),
                String
            )
            live == swipl_out ||
                println(stderr, "  live  ", repr(live), "\n  pin   ", repr(swipl_out))
            @test live == swipl_out
        end
    end
end
