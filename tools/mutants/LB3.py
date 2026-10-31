# ORIGINAL: LB3's mutant list — no swipl-devel counterpart.
# tools/mutants/LB3.py — the mutation battery of LB3 (src/pl-qlf.jl: pl-qlf.c directiveClause, iftrue, MAX_IFDEF_NEST, condc,
# cond_true, update_conditional_compilation, compileFile, compileFileList, the write-side predicates; the boot entry
# `boot_from_source!`; src/os/pl-file.jl push_input_context, pop_input_context, pl_see, pl_seen), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by test/files/test_qlf_swipl.jl: the
# testsets are named in each id's KILL (loadable = the program against swipl's pins; seen = the state after a file; dollar =
# '$:-'; nest = the bound and endif; elif = elif, failing directive, syntax error, a file that cannot be opened; boot = compileFileList and the
# boot entry; tbl = the 22-entry table; fail = Failed to compile). Verdicts: written by the battery at its first run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was
# checked to occur exactly once in the source at wip/lb3 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * `eof` ends compileFile's loop (`&& break`): with the break gone the loop reads end_of_file forever, a HANG, not a verdict.
#   * `!pl_see(ld, f)` failing branch: with it gone the loop reads the user's input stream (a hang on stdin).
#   * pl_seen's `closeStream`: no row sees the stream table, so a mutant that leaves the stream open would survive; the gate
#     adds a row if the kernel has an open-streams accessor by then.
#   * qlfStartFile, qlfEndPart, addDirectiveWic (state::Nothing): `true` bodies, the state file's writes are left out (LD2).
#   * addClauseWic's `sourceloc` line: no row reads a clause's source line.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. src/pl-qlf.jl is exercised by
# test/files/test_qlf_swipl.jl only (nothing else calls compileFile, the boot entry or the table's predicates); the
# registration table is also read by test/foreign/test_builtins_swipl.jl (the dispatch tables), so a mutant of the table's
# flags lists it too.
TQ = ["test/files/test_qlf_swipl.jl"]
TT = TQ + ["test/foreign/test_builtins_swipl.jl"]
TARGETS = TT          # also the baseline's (mutation.yml reads it from here): every file that exercises the mutated code
Q = "src/pl-qlf.jl"
F = "src/os/pl-file.jl"
X = "src/pl-ext.jl"
MUTANTS = [
    # ── directiveClause (pl-qlf.c:4582-4608) ──
    dict(id="LB3-D1 a directive is a unary :- term no more: arity 2 (KILL loadable, dollar)", file=Q, targets=TQ,
         old="na[2] != 1", new="na[2] != 2"),
    dict(id="LB3-D2 the functor name is not compared: every unary term is a directive (KILL loadable)", file=Q, targets=TQ,
         old="sym_key(na[1]) != sym_key(mk_sym(T, functor))", new="false"),
    dict(id="LB3-D3 the directive is qualified with system, not the source module (KILL loadable)", file=Q, targets=TQ,
         old="PL_put_atom(ld, m, gd.modules[ld.modules_source].atom)", new="PL_put_atom(ld, m, mk_sym(T, :system))"),
    dict(id="LB3-D4 an M:G directive is qualified again with the source module",
         file=Q, targets=TQ,
         old="if PL_is_functor(ld, d0, mk_sym(T, :(:)), 2)",
         new="if false",
         equivalent="src/pl-qlf.jl:41 (directiveClause) with src/pl-pro.jl:34 (callProlog) — read, not run: `user:(M:G)` and `M:G` run the same goal, `PL_strip_module` strips every qualifier before the call, and no row reads the directive term itself (addDirectiveWic has no state)"),
    dict(id="LB3-D5 '$:-' is not told from a clause: it is asserted (KILL dollar)", file=Q, targets=TQ,
         old='directiveClause(gd, ld, directive, t, Symbol("\\$:-"))', new="directiveClause(gd, ld, directive, t, Symbol(\":-\"))"),
    dict(id="LB3-D6 a '$:-' term is recognised but its goal never runs (KILL dollar)", file=Q, targets=TQ,
         old='Symbol("\\$:-"))\n                callProlog(gd, ld, MODULE_user(gd).index, directive, PL_Q_NODEBUG)\n',
         new='Symbol("\\$:-"))\n                nothing\n'),
    # ── cond_true, condc, MAX_IFDEF_NEST, update_conditional_compilation (pl-qlf.c:4611-4689) ──
    dict(id="LB3-C1 the bound is one level too far: > for >= (KILL nest)", file=Q, targets=TQ,
         old="cond.depth + 1 >= MAX_IFDEF_NEST", new="cond.depth + 1 > MAX_IFDEF_NEST"),
    dict(id="LB3-C2 MAX_IFDEF_NEST is 4 (KILL nest)", file=Q, targets=TQ,
         old="const MAX_IFDEF_NEST = 3", new="const MAX_IFDEF_NEST = 4"),
    dict(id="LB3-C3 an :- if in a part not compiled runs its goal (KILL loadable: hidden_if_goal)", file=Q, targets=TQ,
         old="        if ctrue\n", new="        if true\n"),
    dict(id="LB3-C4 the if goal runs in system, not user (KILL loadable: goal_if)", file=Q, targets=TQ,
         old="if callProlog(gd, ld, MODULE_user(gd).index, arg, PL_Q_NODEBUG)",
         new="if callProlog(gd, ld, MODULE_system(gd).index, arg, PL_Q_NODEBUG)"),
    dict(id="LB3-C5 a true if goal opens a part not compiled (KILL loadable)", file=Q, targets=TQ,
         old="arg, PL_Q_NODEBUG)\n                new = IF_TRUE\n", new="arg, PL_Q_NODEBUG)\n                new = IF_FALSE\n"),
    dict(id="LB3-C6 an if inside a part not compiled opens a part that an else enables (KILL loadable)", file=Q, targets=TQ,
         old="            new = IF_ELSE_FALSE\n        end\n\n        cond.depth += 1",
         new="            new = IF_FALSE\n        end\n\n        cond.depth += 1"),
    dict(id="LB3-C7 else of a compiled part stays compiled (KILL loadable)", file=Q, targets=TQ,
         old="if cur == IF_TRUE\n                    new = IF_FALSE", new="if cur == IF_TRUE\n                    new = IF_TRUE"),
    dict(id="LB3-C8 else of a part not yet compiled stays off (KILL loadable)", file=Q, targets=TQ,
         old="elseif cur == IF_FALSE\n                    new = IF_TRUE", new="elseif cur == IF_FALSE\n                    new = IF_FALSE"),
    dict(id="LB3-C9 else of a part that is never compiled enables it (KILL loadable)", file=Q, targets=TQ,
         old="else\n                    new = IF_ELSE_FALSE", new="else\n                    new = IF_TRUE"),
    dict(id="LB3-C10 endif does not pop the level (KILL loadable, nest)", file=Q, targets=TQ,
         old="                cond.depth -= 1\n", new="                nothing\n"),
    dict(id="LB3-C11 endif at the file's own level is not an error (KILL nest)", file=Q, targets=TQ,
         old='cond.depth == 0 && error("Too many', new='cond.depth < 0 && error("Too many'),
    dict(id="LB3-C12 else is not taken as a conditional: it runs as a directive (KILL loadable, seen)", file=Q, targets=TQ,
         old="                cond.ctrue[cond.depth + 1] = new\n                rc = true",
         new="                cond.ctrue[cond.depth + 1] = new\n                rc = false"),
    dict(id="LB3-C13 a part is compiled when it is not IF_TRUE: IF_ELSE_FALSE counts (KILL loadable)", file=Q, targets=TQ,
         old="cond.ctrue[cond.depth + 1] == IF_TRUE", new="cond.ctrue[cond.depth + 1] != IF_FALSE"),
    dict(id="LB3-C14 the file's own level is not compiled (KILL loadable)", file=Q, targets=TQ,
         old="condc() = condc(0, iftrue[IF_TRUE, IF_FALSE, IF_FALSE])", new="condc() = condc(0, iftrue[IF_FALSE, IF_FALSE, IF_FALSE])"),
    # ── compileFile (pl-qlf.c:4691-4780) ──
    dict(id="LB3-F1 the conditional directives are not consulted: they run as directives (KILL loadable)", file=Q, targets=TQ,
         old="if !update_conditional_compilation(gd, ld, directive, cond)", new="if true"),
    dict(id="LB3-F2 a directive in a part not compiled runs (KILL loadable: hidden_directive)", file=Q, targets=TQ,
         old="                if cond_true(cond)\n                    addDirectiveWic(state, directive)",
         new="                if true\n                    addDirectiveWic(state, directive)"),
    dict(id="LB3-F3 a clause in a part not compiled is asserted (KILL loadable)", file=Q, targets=TQ,
         old="        elseif cond_true(cond)\n", new="        elseif true\n"),
    dict(id="LB3-F4 a failed directive leaves no message (KILL loadable, elif)", file=Q, targets=TQ,
         old=': directive failed\\n"', new=': directive passed\\n"'),
    dict(id="LB3-F5 a syntax error ends the file (KILL elif)", file=Q, targets=TQ,
         old="            continue\n        end\n        eof = PL_get_atom(ld, t)\n",
         new="            break\n        end\n        eof = PL_get_atom(ld, t)\n",
         equivalent="src/pl-read.jl:4099 (read_clause fixes syntax_errors to dec10) with :4030 (reportReadError returns true for dec10, the loop at :4098 reads again): a syntax error never makes read_clause return false, so src/pl-qlf.jl's failing branch is reached by a stream error only, which no row can produce"),
    dict(id="LB3-F6 pl_seen is not called: the input stays on the file (KILL loadable)", file=Q, targets=TQ,
         old="    qlfEndPart(state)\n    pl_seen(ld)\n", new="    qlfEndPart(state)\n    nothing\n"),
    dict(id="LB3-F7 the modification time is not recorded (KILL loadable)", file=Q, targets=TQ,
         old="        sf.mtime = st.mtime\n", new="        nothing\n"),
    dict(id="LB3-F8 startConsult is not called (KILL loadable)", file=Q, targets=TQ,
         old="    startConsult(sf)\n", new="    nothing\n"),
    dict(id="LB3-F9 the missing-file message omits the path (KILL elif)", file=Q, targets=TQ,
         old='"Failed to open $path\\n"', new='"Failed to open\\n"'),
    dict(id="LB3-F10 clauses are asserted at the start of the predicate (KILL loadable)", file=Q, targets=TQ,
         old="assert_term!(gd, ld, term, 0, CL_END, file, loc, 0)", new="assert_term!(gd, ld, term, 0, CL_START, file, loc, 0)"),
    dict(id="LB3-F11 the failure of addClauseWic is not reported (KILL fail)", file=Q, targets=TQ,
         old='_qlf_Sdprintf!(ld, "Failed to compile: ")', new='_qlf_Sdprintf!(ld, "Failed: ")'),
    # ── compileFileList (pl-qlf.c:4783-4820) and the boot entry ──
    dict(id="LB3-L1 the -c argument does not end the list (KILL boot)", file=Q, targets=TQ,
         old='file == "-c" && break', new='file == "-c" && continue'),
    dict(id="LB3-L2 a file that does not compile does not end the list (KILL boot)", file=Q, targets=TQ,
         old="compileFile(gd, ld, state, file) || return false", new="compileFile(gd, ld, state, file)"),
    dict(id="LB3-L3 autoload stays on while compiling (KILL boot: autoload_off)", file=Q, targets=TQ,
         old='setPrologFlag(gd, "autoload", FT_ATOM, "false")', new='setPrologFlag(gd, "autoload", FT_ATOM, "true")'),
    dict(id="LB3-L4 autoload stays off after the list (KILL boot)", file=Q, targets=TQ,
         old='setPrologFlag(gd, "autoload", FT_ATOM, "true")\n    setAccessLevel!', new='setPrologFlag(gd, "autoload", FT_ATOM, "false")\n    setAccessLevel!'),
    dict(id="LB3-L5 the access level is not restored by compileFileList (KILL boot)", file=Q, targets=TQ,
         old="    setAccessLevel!(ld, alevel)\n", new="    nothing\n"),
    dict(id="LB3-L6 $load_additional_boot_files is not called (KILL boot)", file=Q, targets=TQ,
         old="PL_call_predicate(gd, ld, MODULE_user(gd), PL_Q_DEBUG, pred, 0)", new="true"),
    dict(id="LB3-L7 $load_additional_boot_files is looked up in system (KILL boot)", file=Q, targets=TQ,
         old='Symbol("\\$load_additional_boot_files")), 0, MODULE_user(gd)', new='Symbol("\\$load_additional_boot_files")), 0, MODULE_system(gd)'),
    dict(id="LB3-L8 the boot flag is not reset after the list (KILL boot)", file=Q, targets=TQ,
         old="    gd.bootsession = false\n    rc || return false", new="    rc || return false"),
    dict(id="LB3-L9 the boot flag is never set: the files are not system files (KILL boot)", file=Q, targets=TQ,
         old="    gd.bootsession = true\n", new="    nothing\n"),
    dict(id="LB3-L10 the style checks are not set after the boot (KILL boot)", file=Q, targets=TQ,
         old="    ld.debugstatus_styleCheck =\n", new="    _ =\n"),
    dict(id="LB3-L11 the access level is not USER after the boot (KILL boot)", file=Q, targets=TQ,
         old="    setAccessLevel!(ld, ACCESS_LEVEL_USER)\n", new="    nothing\n"),
    dict(id="LB3-L12 a failed list is a success of the boot entry (KILL boot)", file=Q, targets=TQ,
         old="    rc || return false\n", new="    nothing\n"),
    # ── the predicates (pl-qlf.c:4953-4976) ──
    dict(id="LB3-P1 $qlf_include/5 succeeds with no state (KILL tbl)", file=Q, targets=TQ,
         old="return FFALSE                                               # (state=LD->qlf.write_state): NULL",
         new="return FTRUE                                                # (state=LD->qlf.write_state): NULL"),
    dict(id="LB3-P2 $qlf_include/5 does not check its first argument (KILL tbl)", file=Q, targets=TQ,
         old="    PL_get_atom_ex(ld, A1) === nothing && return FFALSE         # owner\n", new=""),
    dict(id="LB3-P3 $qlf_include/5 does not check its float argument",
         file=Q, targets=TQ,
         old="    PL_get_float(ld, A5) === nothing && return FFALSE           # time\n", new="",
         equivalent="src/pl-qlf.jl:396-397 (pl_qlf_include5_va) — read, not run: the check returns false and the function ends with `return FFALSE` too; PL_get_float is the non-raising form, so dropping it changes nothing observable"),
    dict(id="LB3-P4 $import_wic/3 fails with no state (the brief's refusal read as failure) (KILL tbl)", file=Q, targets=TQ,
         old="function pl_import_wic3_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return FTRUE\n",
         new="function pl_import_wic3_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return FFALSE\n"),
    dict(id="LB3-P5 $qlf_load/2 succeeds instead of being refused by name (KILL tbl)", file=Q, targets=TQ,
         old='_qlf_refused(T, "\\$qlf_load", 2)', new="FTRUE"),
    dict(id="LB3-P6 $add_directive_wic/1 is not transparent (KILL tbl)", file=Q, targets=TT,
         old='pl_add_directive_wic1_va,\n        PL_FA_TRANSPARENT | PL_FA_VARARGS',
         new='pl_add_directive_wic1_va,\n        PL_FA_VARARGS'),
    # ── src/os/pl-file.jl push_input_context, pop_input_context, pl_see, pl_seen ──
    dict(id="LB3-S1 pl_see saves no input context (KILL loadable: the source location is not restored)", file=F, targets=TQ,
         old="    push_input_context(ld, mk_sym(T, :see))         # push_input_context(ATOM_see)\n", new="    nothing\n"),
    dict(id="LB3-S2 pop_input_context does not restore the source file (KILL loadable)", file=F, targets=TQ,
         old="        ld.read_source.file = c.term_file                   # source_file_name = c->term_file\n", new="        nothing\n"),
    dict(id="LB3-S3 pop_input_context does not restore the line (KILL loadable)", file=F, targets=TQ,
         old="        ld.read_source.position.lineno = c.term_line        # source_line_no   = c->term_line\n", new="        nothing\n"),
    dict(id="LB3-S4 pop_input_context does not restore the input stream (KILL loadable)", file=F, targets=TQ,
         old="        ld.IO_streams[SNO_CURRENT_INPUT + 1] = c.stream    # Scurin           = c->stream\n", new="        nothing\n"),
    dict(id="LB3-S5 pop_input_context leaves the context on the stack (KILL loadable)", file=F, targets=TQ,
         old="        c = pop!(ld.input_context_stack)\n", new="        c = last(ld.input_context_stack)\n"),
]
