# ORIGINAL: S2A3's mutant list — no swipl-devel counterpart.
# tools/mutants/PSTREAM.py — the mutation battery of S2a3 (the three process streams bound when an engine is made: pl-file.c initIO,
# pl-stream.c S__iob0, pl-setup.c setupProlog's start-up call; the booted template keeps an empty stream table), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: one mutant at a time, by hand).
# Format: tools/mutate_drive.py's (as MOD2u.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Killed by test/files/test_process_streams_swipl.jl (rows named in each id's KILL: "stream rows" = the 34-line "a row per stream" testset,
# "wb" = the "engine's own three streams" testset, "finding" = the autoloader testset), and by the landed rows S2a3 rewrote
# (test_qlf_swipl.jl, test_write_family_swipl.jl, test_lb5b_prompt.jl, test/db/test_gd_template.jl).
# TARGETS (audit D-0238 item 4): the step's own file first, then every file that reaches an engine's standard streams: the rewritten
# landed rows, the template, the type discipline, and the MOD2u TSTD list (the files that reach initIO through a standard stream alias).
TP = ["test/files/test_process_streams_swipl.jl"]
TQ = ["test/files/test_qlf_swipl.jl", "test/core_text/test_write_family_swipl.jl", "test/core_lang/test_lb5b_prompt.jl",
      "test/files/test_open_close_swipl.jl"]
TG = ["test/db/test_gd_template.jl", "test/db/test_boot_image_readers.jl"]   # both copy a database (the copy policy refuses a template holding a stream)
TD = ["test/test_type_discipline.jl"]
TSTD = ["test/core_lang/test_blob.jl", "test/foreign/test_exceptions_swipl.jl", "test/core_lang/test_context_module_swipl.jl",
        "test/core_text/test_read_positions_swipl.jl", "test/core_text/test_canonical_readatom_swipl.jl",
        "test/core_lang/test_write_cells.jl", "test/core_lang/test_numbervars_cells.jl"]
TARGETS = TP + TQ + TG + TD + TSTD   # the baseline's (mutate_ci.py plan reads TARGETS)
G = "src/pl-global.jl"
O = "src/os/pl-file.jl"
F = "src/os/pl-prologflag.jl"
MUTANTS = [
    # ── the constructor ──
    dict(id="PSTREAM-1 PL_local_data{T}(gd) does not call initIO: an engine opens no stream (KILL stream rows, wb, finding)", file=G, targets=TARGETS,
         old="    initIO(ld)              # Suser_input, Suser_output, Suser_error, Scurin, Scurout: open when the engine exists (pl-file.c initIO)\n",
         new="    nothing\n"),
    dict(id="PSTREAM-2 initIO's last line leaves IO_initialised false (KILL wb: ld.IO_initialised, test_qlf, test_write_family)", file=O, targets=TARGETS,
         old="    ld.IO_initialised = true\n",
         new="    ld.IO_initialised = false\n"),
    dict(id="PSTREAM-3 the flag record's engine is made by PL_local_data{T}(gd) again: the booted template holds three streams (KILL test_open_close_swipl.jl:521, hand-run 2026-11-06; the stream table of the booted template is non-empty)", file=F, targets=TARGETS,
         old="    ld = _bare_local_data(gd)                           # (no stream: the template holds none)\n",
         new="    ld = PL_local_data{T}(gd)\n"),
    # PSTREAM-4 removed with the code it mutated (WHEN2: `_boot_when!`, whose engine it made); ledger: evidence/MUTREFIT/deleted_mutants.tsv
    # ── initIO: the streams ──
    dict(id="PSTREAM-5 user_input reads file descriptor 1 (KILL the descriptor-fallback testset: devnull stdin, name \"<fd 0>\"; no other target: with a real stdin `_std_io` returns it and ignores fd, and file_no is a known difference)", file=O, targets=TARGETS,
         old="    sin = _std_stream(_std_io(Base.stdin, 0), SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF)\n",
         new="    sin = _std_stream(_std_io(Base.stdin, 1), SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF)\n"),
    dict(id="PSTREAM-6 user_output without SIO_REPPLU (KILL stream rows 18: representation_errors(unicode), wb flags)", file=O, targets=TARGETS,
         old="        _std_io(Base.stdout, 1), SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU\n",
         new="        _std_io(Base.stdout, 1), SIO_STDIO | SIO_LBUF | SIO_OUTPUT\n"),
    dict(id="PSTREAM-7 user_error line-buffered, not unbuffered (KILL stream rows 26: buffer(false), wb flags)", file=O, targets=TARGETS,
         old="        _std_io(Base.stderr, 2), SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU\n",
         new="        _std_io(Base.stderr, 2), SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU\n"),
    # ── initIO: the slots and the table ──
    dict(id="PSTREAM-8 Scurin is Soutput (KILL stream rows 31: current_input vs user_input; wb Scurin; finding's pop check)", file=O, targets=TARGETS,
         old="    ld.IO_streams[SNO_CURRENT_INPUT + 1] = sin      # Scurin       = Sinput\n",
         new="    ld.IO_streams[SNO_CURRENT_INPUT + 1] = sout     # Scurin       = Sinput\n"),
    dict(id="PSTREAM-9 Scurout is Serror (KILL stream rows 32-33; wb Scurout)", file=O, targets=TARGETS,
         old="    ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = sout    # Scurout      = Soutput\n",
         new="    ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = serr    # Scurout      = Soutput\n"),
    dict(id="PSTREAM-10 the Suser_error slot holds Soutput (KILL stream rows 21-30: user_error's alias and file_no; wb)", file=O, targets=TARGETS,
         old="    ld.IO_streams[SNO_USER_ERROR + 1] = serr        # Suser_error  = Serror\n",
         new="    ld.IO_streams[SNO_USER_ERROR + 1] = sout        # Suser_error  = Serror\n"),
    dict(id="PSTREAM-11 Serror is not made known to Prolog: no table entry (KILL wb: the table holds live0 + 3; stream rows for user_error)", file=O, targets=TARGETS,
         old="    getStreamContext(gd, serr)\n",
         new="    nothing\n"),
    dict(id="PSTREAM-12 Serror keeps its own position record (KILL wb: serr.position === sin.posbuf)", file=O, targets=TARGETS,
         old="    serr.position = sin.posbuf\n",
         new="    serr.position = serr.posbuf\n"),
]
