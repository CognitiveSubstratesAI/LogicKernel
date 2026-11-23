# ORIGINAL: W12-TMPFILES's gate — the temporary-file registry (pl-os.c TemporaryFile, DeleteTemporaryFile, RemoveTemporaryFiles; pl-stream.c Sfdopen;
# pl-files.c tmp_file/2, `$tmp_file_stream`/4, delete_file/1 on a temporary name) against swipl 10.1.20
# test/files/test_tmp_files_swipl.jl — the rows of test_tmp_files_swipl.pl, as a PROGRAM (the pattern of test_lb2b_swipl.jl): the kernel consults it and
# enumerates every solution of every tN/1; the lines are compared with test_tmp_files_swipl.out, swipl's own (evidence/W12-TMPFILES/run_rows.sh: two runs
# with LC_ALL=C, byte-identical, `timeout 20`). WHAT IS PINNED, AND WHY BY SHAPE: a temporary name is <tmp_dir>/swipl_<Id>[_]<pid>_<n>[.<Ext>]; the process
# number and the counter differ per run (and per database: the kernel's counter is the database's), so a row takes the name apart (`shape/4` in the .pl)
# and answers `ok`/`bad`; what is pinned is the directory (the flag tmp_dir), the prefix, the id (atom, string, number and code list alike; none for ''),
# the extension, a counter that goes up by one per name (tmp_file/2 and `$tmp_file_stream`/4 share it), that tmp_file/2 makes no file and
# `$tmp_file_stream`/4 makes one (open for writing, no file_name property, the encoding given, `binary` = octet), that delete_file/1 removes a
# temporary name and then raises existence_error(file, Name) as for any other name (also for a name nobody created), the errors (formal term only) and
# an invalid tmp_dir (the formal term only: the errno text there is whatever the warning's printing leaves, swipl answers 'No such file or directory'
# once and 'Invalid argument' another time). THE HALT: the names still in the registry at the end are removed by PL_cleanup (the kernel) and by exit
# (swipl, run live); the registry is the database's `os_tmp_files`. The warnings of the invalid tmp_dir rows go to stderr (swipl's are discarded).
# UNVERIFIED on the kernel: gate decides (every pin is swipl's; the rows were not run on the kernel)
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
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

const _TMP_PL = joinpath(@__DIR__, "test_tmp_files_swipl.pl")
const _TMP_OUT = joinpath(@__DIR__, "test_tmp_files_swipl.out")

# the rows' names, in the order of the program
_tmp_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_TMP_PL, String))])

# the solutions of the row `name`/1, as `enc` lines (a Julia exception, a refusal included, is not caught here)
function _tmp_row(gd, ld, name::String)::Vector{String}
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
    if proc === nothing || !LK.isDefinedProcedure(gd, proc)
        return String["$name undefined"]
    end
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    try
        n = 0
        while (n += 1) <= 100
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
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return String["$name" * join(" " .* sols)]
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions; the database stays for the checks after the run
function kernel_lines(path::String, names::Vector{String})
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    gd.halt_exit = false
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        append!(out, _tmp_row(gd, ld, name))
    end
    return out, gd, ld
end

# the driver swipl runs to print its lines (the .out is its output)
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the file names a registry holds that exist as files now
_tmp_existing(gd) = sort!(filter(isfile, collect(gd.os_tmp_files)))

@testset "tmp files: the rows == swipl's answers (the .out), through a program; the halt removes what is left" begin
    names = _tmp_names()
    expected = String.(readlines(_TMP_OUT))
    # not a vacuous agreement: a line per row, the answers carry both outcomes and the errors
    @test length(names) >= 30
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(l -> occursin("(a" * _codes("ok") * ")", l), expected) >= 9
    @test !any(l -> occursin(_codes("bad"), l), expected)                 # no row's shape check failed in swipl
    @test any(l -> occursin(_codes("instantiation_error"), l), expected)
    @test any(l -> occursin(_codes("domain_error"), l), expected)         # an unknown encoding
    @test any(l -> occursin(_codes("uninstantiation_error"), l), expected)
    @test any(l -> occursin(_codes("max_path_length"), l), expected)
    @test any(l -> occursin(_codes("temporary_file"), l), expected)       # an invalid tmp_dir
    @test any(l -> occursin(_codes("existence_error_of_name"), l), expected)

    mktempdir() do d
        cd(d) do
            kl, gd, ld = kernel_lines(_TMP_PL, names)
            @test length(kl) == length(expected)
            for i in eachindex(kl)
                @test (i, kl[i]) == (i, expected[i])
            end
            @test !isdir("lk_tmpf_dir")                                   # t14 removed its directory
            # the last row left three files behind: one at a `tmp_file/2` name (made by open/3), two made by `$tmp_file_stream`/4
            # (t99's, and t31's, whose answer was the uninstantiation error); the registry still has them, and the halt removes them
            left = _tmp_existing(gd)
            @test length(left) == 3
            @test all(n -> startswith(basename(n), "swipl_"), left)
            @test count(n -> occursin("swipl_lk_left_", n), left) == 1
            @test count(n -> endswith(n, ".txt"), left) == 1 &&
                count(n -> endswith(n, ".left"), left) == 1
            @test length(gd.os_tmp_files) > length(left)                  # the names of files nobody made stay in the registry
            # delete_file/1 forgot the names of t12 and t13 (Id lk_del): the registry is tried first, not only the file
            @test !any(n -> occursin("swipl_lk_del_", n), gd.os_tmp_files)
            @test LK.PL_cleanup(gd, ld, 0 | LK.PL_CLEANUP_NO_CANCEL) ==
                LK.PL_CLEANUP_SUCCESS
            @test all(!ispath, left)
            @test isempty(gd.os_tmp_files)
        end
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "tmp files: DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        sw = mktempdir() do d
            cd(d) do
                swipl_lines(_TMP_PL, names)
            end
        end
        @test sw == expected                                              # the .out is swipl's, still
        # swipl's halt removes the names of its registry: a file made at a tmp_file/2 name and one `$tmp_file_stream`/4 made
        goal =
            "tmp_file(lk_halt, N), open(N, write, S), close(S), '\$tmp_file_stream'(h, utf8, F, S2), close(S2), " *
            "writeln(N), writeln(F), exists_file(N), exists_file(F)"
        names2 = String.(
            split(
                read(
                    pipeline(
                        addenv(`swipl -q -g $goal -t halt`, "LC_ALL" => "C"); stdin=devnull,
                        stderr=devnull
                    ), String
                ), '\n'; keepempty=false
            )
        )
        @test length(names2) == 2
        @test all(startswith(basename(n), "swipl_") for n in names2)
        @test all(!ispath, names2)
    end
end

@testset "tmp files: TemporaryFile, DeleteTemporaryFile, RemoveTemporaryFiles on one database (white box)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    dir = LK.tmp_dir(ld)
    pid = Libc.getpid()
    @test isempty(gd.os_tmp_files) && gd.os_temp_counter == 0
    # a name only: no file, the registry holds it, the counter went up
    n1, f1 = LK.TemporaryFile(ld, "wb", "", false)
    @test n1 == string(dir, "/swipl_wb_", pid, "_1") && f1 === nothing
    @test !ispath(n1) && n1 in gd.os_tmp_files && gd.os_temp_counter == 1
    # an empty id and an extension: no `_` for the id, a `.` for the extension
    n2, _ = LK.TemporaryFile(ld, "", "txt", false)
    @test n2 == string(dir, "/swipl_", pid, "_2.txt")
    n3, _ = LK.TemporaryFile(ld, "", "", false)
    @test n3 == string(dir, "/swipl_", pid, "_3")
    @test length(gd.os_tmp_files) == 3
    # with a file: created, 0600 (less the umask), open for writing
    n4, f4 = LK.TemporaryFile(ld, "w", "dat", true)
    @test n4 == string(dir, "/swipl_w_", pid, "_4.dat") && f4 isa Base.Filesystem.File
    @test isfile(n4) && (filemode(n4) & 0o600) == 0o600 && (filemode(n4) & 0o077) == 0
    write(f4, "abc")
    close(f4)
    @test filesize(n4) == 3
    # the name a retry would take exists already: TemporaryFile goes on to the next counter and leaves that file alone
    taken = string(dir, "/swipl_x_", pid, "_5")
    write(taken, "keep")
    try
        n5, f5 = LK.TemporaryFile(ld, "x", "", true)
        @test n5 == string(dir, "/swipl_x_", pid, "_6") && isfile(n5)
        @test read(taken, String) == "keep" && !(taken in gd.os_tmp_files)
        close(f5)
        @test LK.DeleteTemporaryFile(gd, n5)
    finally
        rm(taken; force=true)
    end
    # DeleteTemporaryFile: a registered file is removed and forgotten; a name never registered, or one whose file is gone, answers false
    @test LK.DeleteTemporaryFile(gd, n4) && !ispath(n4) && !(n4 in gd.os_tmp_files)
    @test !LK.DeleteTemporaryFile(gd, n4)                                 # no longer registered
    @test !LK.DeleteTemporaryFile(gd, "/nonexistent_lk_dir/x")
    # a file that exists but was never registered is left alone
    unregistered = joinpath(dir, string("lk_tmp_unregistered_", pid))
    write(unregistered, "u")
    try
        @test !LK.DeleteTemporaryFile(gd, unregistered) && isfile(unregistered)
    finally
        rm(unregistered; force=true)
    end
    @test !LK.DeleteTemporaryFile(gd, n1) && !(n1 in gd.os_tmp_files)      # registered, but nobody made the file: forgotten, false
    # a name of PATH_MAX bytes or more: ENAMETOOLONG, nothing registered
    before = length(gd.os_tmp_files)
    @test LK.TemporaryFile(ld, "a"^5000, "", false) === LK.ENAMETOOLONG
    @test length(gd.os_tmp_files) == before
    # the limit: PATH_MAX (4096) bytes with the terminating NUL — 4095 characters are made, 4096 refused (swipl's pin: row t16)
    c = gd.os_temp_counter + 1
    fixed = ncodeunits(string(dir, "/swipl_", "_", pid, "_", c))
    r = LK.TemporaryFile(ld, "a"^(4095 - fixed), "", false)
    @test r isa Tuple && ncodeunits(r[1]) == 4095
    c = gd.os_temp_counter + 1
    fixed = ncodeunits(string(dir, "/swipl_", "_", pid, "_", c))
    @test LK.TemporaryFile(ld, "a"^(4096 - fixed), "", false) === LK.ENAMETOOLONG
    @test gd.os_temp_counter == c                                         # the counter goes up before the length is checked
    delete!(gd.os_tmp_files, r[1])
    before = length(gd.os_tmp_files)
    # RemoveTemporaryFiles: the files go, the names of files nobody made are skipped, the registry is empty
    made = String[]
    for i in 1:3
        n, f = LK.TemporaryFile(ld, "r", "", true)
        close(f)
        push!(made, n)
    end
    @test all(isfile, made) && length(gd.os_tmp_files) == before + 3
    LK.RemoveTemporaryFiles(gd)
    @test all(!ispath, made) && isempty(gd.os_tmp_files)
    LK.RemoveTemporaryFiles(gd)                                           # on an empty registry: nothing
    @test isempty(gd.os_tmp_files)
end

@testset "tmp files: two databases keep their own registry and counter" begin
    gd1 = LK.PL_global_data{_TL}()
    ld1 = LK.PL_local_data{_TL}(gd1)
    gd2 = LK.PL_global_data{_TL}()
    a, _ = LK.TemporaryFile(ld1, "d", "", false)
    @test a in gd1.os_tmp_files && isempty(gd2.os_tmp_files)
    @test gd1.os_temp_counter == 1 && gd2.os_temp_counter == 0
end

@testset "tmp files: Sfdopen — a stream on an open descriptor" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    @test LK.Sfdopen(-1, "w") == (nothing, LK.EINVAL)
    @test LK.Sfdopen(1_000_000, "w") == (nothing, 9)                      # EBADF: no such descriptor
    mktempdir() do d
        p = joinpath(d, "f")
        file = Base.Filesystem.open(
            p, Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_WRONLY, 0o600
        )
        fd = Int(Base.cconvert(Cint, file.handle))
        @test LK.Sfdopen(fd, "") == (nothing, LK.EINVAL)                  # an unknown type letter
        @test LK.Sfdopen(fd, "x") == (nothing, LK.EINVAL)
        s, errno = LK.Sfdopen(fd, "w")
        @test s isa LK.IOSTREAM && errno == 0
        @test (s.flags & LK.SIO_OUTPUT) != 0 && (s.flags & LK.SIO_INPUT) == 0 &&
            (s.flags & LK.SIO_TEXT) != 0
        @test LK.Sputc(Int('h'), s) == Int('h')
        @test LK.Sclose(s) == 0                                           # the stream owns the descriptor: this closes it
        @test read(p, String) == "h"
        @test_throws Base.IOError stat(RawFD(fd))                         # closed (EBADF)
        file2 = Base.Filesystem.open(p, Base.Filesystem.JL_O_RDONLY, 0)
        fd2 = Int(Base.cconvert(Cint, file2.handle))
        s2, _ = LK.Sfdopen(fd2, "rb")
        @test (s2.flags & LK.SIO_INPUT) != 0 && (s2.flags & LK.SIO_TEXT) == 0
        LK.Sclose(s2)
    end
end
