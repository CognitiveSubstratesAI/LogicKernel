# ORIGINAL: LB7's mutant list — the command line and the start-up of the Prolog part of pl-init.c (optcmp, is_bool_opt, find_define, memarea_limit, parseCommandLineOptions, usage, defaultSystemInitFile, initDefaultOptions) and the option predicates of pl-prims.c ($cmd_option_val/2, $cmd_option_set/2), swipl-devel cbf4e189; the ported pieces cite their upstream lines in src.
# tools/mutants/LB7.py — the mutation battery of LB7, run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as CT1A.py).
# NOTHING here has run on the kernel: each KILL names the row EXPECTED to kill the mutant. Rows o01-o16, u01-u12, f01-f10, k01-k05 are the oracle rows
# of test/core_lang/test_lb7_swipl.jl; `H-<testset>[<row>]` is a hand-written row of the same file; rt87-rt189 are rows of test/core_text/test_read_stream_swipl.jl.
# The `old` strings are in the repo's formatted style BEFORE `tools/warm.sh fmt`: RE-FIT any that fmt rewraps. Every `old` was checked (python3 -I text count) to occur
# EXACTLY once in its file at wip/lb7 40f7781f, ids unique, new != old, every TARGETS file present with @test. Cut from a 112-mutant draft to one mutant per branch of the logic.
# NOT LISTED (each with its reason):
#   * PL_initialise!, PL_initialise_tail!, usage(ld)'s write to user_error, the `argv` flag after `$initialise`, the effect of -p/-D on file_search_path: they need the
#     booted `$initialise` or a capture of user_error; the first-boot rows of the gate agent come first, their mutants after.
#   * apply_options_to_flags!'s setPrologFlagMask!/clearPrologFlagMask! on `ld`: every row opens its query on a fresh local data copied from the database
#     (`_lb7_query`), so nothing reads the mask of the `ld` that was given; the flags (set with the bit on the database) are pinned by f01-f10 (LB7-E1..E12).
#   * the --tty=... / -tty branches: PL_set_prolog_flag("tty_control", ...) raises where the value changes (STOP 2 of the handoff); no row takes it.
#   * unify_location: linepos and charno are both 0 in every row that shows them (rt113, rt187: stream(_, 1, 0, 0)), so swapping the two is not told apart;
#     the stream argument is masked by rt_serr (the blob prints differently per run), so _stream_or_alias_term is not mutated either. A row with a syntax error
#     behind the first character would close both holes (left to the gate agent).
#   * --sigalert=N beyond the range check (DIVERGES 4), -d topic apart from its word (DIVERGES 2).
# TARGETS (audit D-0238): the option code of pl-init.jl is read by test_lb7_swipl.jl only; `$cmd_option_*` registration in PL_predicates_from_prims is walked by
# test/foreign/test_builtins_swipl.jl (_FOREIGN_VA) and shared with test/core_lang/test_style_check_swipl.jl; the constructor and copy of PL_global_data{T} are
# exercised by test/db/test_gd_template.jl; unify_location's stream branch is reached only by test_read_stream_swipl.jl (git grep unify_location test/).
LB7T = "test/core_lang/test_lb7_swipl.jl"
RST = "test/core_text/test_read_stream_swipl.jl"
TARGETS = [LB7T, RST]
OPT = [LB7T]
PRIMS = [LB7T, "test/foreign/test_builtins_swipl.jl", "test/core_lang/test_style_check_swipl.jl"]
STRUCT = [LB7T, "test/db/test_gd_template.jl"]
READ = [RST]
I = "src/pl-init.jl"
P = "src/pl-prims.jl"
G = "src/pl-global.jl"
R = "src/pl-read.jl"
MUTANTS = [
    dict(id="LB7-A1 a `-` of the word no longer matches a `_` of the name (KILL o12, o14, f08; H-optcmp[stack-limit=10k|stack_limit])",
         file=I, targets=OPT, old="(a[i] == UInt8('-') && o[j] == UInt8('_')) ||", new="false ||"),
    dict(id="LB7-A5 the name need not be consumed: `qui` is `quiet` (KILL H-optcmp[qui|quiet], [stackx|stack_limit])",
         file=I, targets=OPT, old="if j > length(o)", new="if true"),
    dict(id="LB7-A6 `n` is no false (KILL H-is_bool_opt[quiet=n])",
         file=I, targets=OPT, old="(lv == \"false\" || lv == \"no\" || lv == \"n\") && return (1, false)", new="(lv == \"false\" || lv == \"no\") && return (1, false)"),
    dict(id="LB7-A9 `--no-NAME` sets true (KILL o09, o16, f05; H-is_bool_opt[noquiet], [no-quiet], [no_quiet])",
         file=I, targets=OPT, old="isempty(optval) && return (1, false)", new="isempty(optval) && return (1, true)"),
    dict(id="LB7-A11 a value that is no boolean answers 0 (KILL u01, u11; H-is_bool_opt[quiet=maybe]; H-parseCommandLineOptions[--quiet=maybe])",
         file=I, targets=OPT, old="        return (-1, false)\n    elseif startswith(opt, \"no\")", new="        return (0, false)\n    elseif startswith(opt, \"no\")"),
    dict(id="LB7-A16 no -D is an early define (KILL o08; H-find_define[is_early_define x3]; H-parseCommandLineOptions[-Dfoo -D a=b -Dfile_name_case_handling=x])",
         file=I, targets=OPT, old="any(n -> optcmp(def, n) !== nothing, EARLY_DEFINES)", new="false"),
    dict(id="LB7-A17 the first -Dname wins (KILL H-find_define[-Dfoo=bar -Dfoo=baz])",
         file=I, targets=OPT, old="v === nothing || (value = v)", new="v === nothing || value !== nothing || (value = v)"),
    dict(id="LB7-A18 find_define does not stop at `--` (KILL H-find_define[-Dfoo=1 -- -Dfoo=2], [-- -Dfoo=2])",
         file=I, targets=OPT, old="a == \"--\" && break", new="false && break"),
    dict(id="LB7-A19 find_define has no two-word `-D name=value` (KILL H-find_define[-D foo=bar])",
         file=I, targets=OPT, old="elseif k < length(argv)", new="elseif false"),
    dict(id="LB7-B1 `k` is 1000 (KILL o14; H-memarea_limit[10k], [10K])",
         file=I, targets=OPT, old="(c == UInt8('k') || c == UInt8('K')) && return n.i * 1024", new="(c == UInt8('k') || c == UInt8('K')) && return n.i * 1000"),
    dict(id="LB7-B5 a negative number is a size (the DIVERGES pinned) (KILL H-memarea_limit[-5])",
         file=I, targets=OPT, old="n.type === V_INTEGER && n.i >= 0", new="n.type === V_INTEGER"),
    dict(id="LB7-B6 a trailing letter after the number is ignored (KILL u05; H-memarea_limit[5x])",
         file=I, targets=OPT, old="        return nothing\n    end\n    clearNumber(n)", new="        return n.i\n    end\n    clearNumber(n)"),
    dict(id="LB7-C1 `-g` goes to the script files (KILL o02)",
         file=I, targets=OPT, old="push!(o.goals, String(argv0[k]))", new="push!(o.scriptFiles, String(argv0[k]))"),
    dict(id="LB7-C8 `-D name=value` takes no next word (KILL o07)",
         file=I, targets=OPT, old="                def = argv0[k + 1]\n                k += 1\n", new="                def = argv0[k + 1]\n"),
    dict(id="LB7-C12 `--` does not end the options (KILL H-parseCommandLineOptions[the arguments left: `-- -q`, `-g t -- -z`], rows added in efd5abbb)",
         file=I, targets=OPT, old="isempty(s) && break", new="false && break"),
    dict(id="LB7-C16 the `-c` line sets nothing: o.compile ignored (KILL H-parseCommandLineOptions[-c])",
         file=I, targets=OPT, old="o.compile = true", new="nothing"),
    dict(id="LB7-C17 `-b` sets nothing (KILL H-parseCommandLineOptions[-b])",
         file=I, targets=OPT, old="gd.bootsession = true", new="nothing"),
    dict(id="LB7-C18 `-d topic` takes no word (KILL H-parseCommandLineOptions[-d topic -q])",
         file=I, targets=OPT, old="# -d topic (ignored: DIVERGES 2)\n                k += 1\n", new="# -d topic (ignored: DIVERGES 2)\n"),
    dict(id="LB7-C31 `--traditional` is not refused by name (KILL H-parseCommandLineOptions[--traditional])",
         file=I, targets=OPT, old="if is_longopt(s, \"traditional\") !== nothing", new="if false"),
    dict(id="LB7-E1 the flag optimise is not fed from -O (KILL f02)",
         file=I, targets=OPT, old="(\"optimise\", PLFLAG_OPTIMISE, cmd.optimise),", new="(\"optimise\", PLFLAG_OPTIMISE, false),"),
    dict(id="LB7-E4 signals is always true (KILL f05)",
         file=I, targets=OPT, old="(\"signals\", PLFLAG_SIGNALS, truePrologFlag(ld, PLFLAG_SIGNALS)),", new="(\"signals\", PLFLAG_SIGNALS, true),"),
    dict(id="LB7-E7 the local data's stack limit is in bytes, not words (KILL H-apply_options_to_flags![the stack limit in words])",
         file=I, targets=OPT, old="ld.stacks_limit = o.stackLimit ÷ 8", new="ld.stacks_limit = o.stackLimit"),
    dict(id="LB7-E8 the flag on_error is fed from the on_warning option (KILL f07, f10)",
         file=I, targets=OPT, old="setPrologFlag(gd, \"on_error\", FT_ATOM, o.on_error::String)", new="setPrologFlag(gd, \"on_error\", FT_ATOM, o.on_warning::String)"),
    dict(id="LB7-E10 verbose is silent for NOT -q (KILL f03, f01, f10)",
         file=I, targets=OPT, old="o.silent && setPrologFlag(gd, \"verbose\", FT_ATOM, \"silent\")", new="!o.silent && setPrologFlag(gd, \"verbose\", FT_ATOM, \"silent\")"),
    dict(id="LB7-F1 a line of the usage text is cut (KILL 'usage text is swipl --help's'; the live `swipl --help` row)",
         file=I, targets=OPT, old="6) %s --abi-version  Display ABI version key", new="6) %s --abi-version  Display ABI version"),
    dict(id="LB7-F4 a `-` ends the system init file name (KILL H-defaultSystemInitFile[swipl-9x], [my-swipl.exe], [sw-pl.1x])",
         file=I, targets=OPT, old="(isAlpha(Int(c)) || c == UInt8('-')) || break", new="isAlpha(Int(c)) || break"),
    dict(id="LB7-P1 an unset STRING option unifies [] (KILL o01: config and pldoc_server absent; 'the oracle rows are not vacuous')",
         file=P, targets=PRIMS, old="v === nothing && return FFALSE          # if ( *sp ) ... return false", new="v === nothing && return (PL_unify_nil(ld, val) ? FTRUE : FFALSE)"),
    dict(id="LB7-P2 an unknown key fails, no existence_error (KILL k01, k02)",
         file=P, targets=PRIMS, old="return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :cmd_option), key) ? FTRUE : FFALSE", new="return FFALSE"),
    dict(id="LB7-P4 a LIST option is answered reversed (KILL o02, o05, o06, o07)",
         file=P, targets=PRIMS, old="for item in v::Vector{String}", new="for item in reverse(v::Vector{String})"),
    dict(id="LB7-P15 an unknown option is set (KILL k04, k05: bogus)",
         file=P, targets=PRIMS, old="    return false\nend\n\n# PORT: pl-prims.c cmd_option_set as pl_cmd_option_set2_va", new="    return true\nend\n\n# PORT: pl-prims.c cmd_option_set as pl_cmd_option_set2_va"),
    dict(id="LB7-R1 the location of a stream is not stream(..) (KILL rt113, rt187; rt87-rt89, rt120-rt124 by their answers)",
         file=R, targets=READ, old="T[mk_sym(T, :stream), _stream_or_alias_term(rd.ld, rd._rb.stream),", new="T[mk_sym(T, :streams), _stream_or_alias_term(rd.ld, rd._rb.stream),"),
    dict(id="LB7-Q1 the default of xpce is 0, not -1: no reader sees it",
         file=G, targets=STRUCT,
         equivalent="src/pl-init.jl:301 — parseCommandLineOptions stores `o.xpce = -1` before it reads a word, and nothing reads xpce between the construction and a parse ($cmd_option_val has no xpce entry: OPTDEFS)",
         old="xpce::Int = -1", new="xpce::Int = 0"),
]
