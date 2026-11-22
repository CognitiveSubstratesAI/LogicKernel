# ORIGINAL: ENCFLAG1's mutant list — the `encoding` and `unicode_atoms` flag setters and the sites that read LD->encoding / LD->unicode_atoms
# (pl-prologflag.c setEncoding :768-781, setUnicodeAtoms :891-901; pl-file.c:2303, :4173; pl-stream.c:3544-3545, :4441); no swipl-devel counterpart.
# tools/mutants/ENCFLAG1.py — the format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Run ONCE, in CI (.github/workflows/mutation.yml). UNTESTED when written: nothing compiled.
# TARGETS (D-0238): every test file that exercises the mutated code: the two flag files (the rows enc01-enc07, uni01-uni06, t_pe), the open/close
# and ENC_ANSI files (a text stream's default encoding through openStream / set_stream), the lane D stream file and the read-stream file
# (Sopen_text / Sopen_string through read_term_from_atom).
T = ["test/core_lang/test_set_flag_swipl.jl", "test/core_lang/test_push_flag_swipl.jl"]
U = T + ["test/files/test_open_close_swipl.jl", "test/core_lang/test_enc_ansi_swipl.jl", "test/core_lang/test_lane_d_swipl.jl"]
R = T + ["test/core_text/test_read_stream_swipl.jl"]
TARGETS = sorted(set(U + R))                                # the baseline job's list: the union of every mutant's targets
PF = "src/os/pl-prologflag.jl"
FI = "src/os/pl-file.jl"
ST = "src/os/pl-stream.jl"
TX = "src/os/pl-text.jl"
RD = "src/pl-read.jl"
MUTANTS = [
    dict(id="ENCFLAG1-1 setEncoding accepts an unknown encoding name", file=PF, targets=T,
         old='''    if enc == ENC_UNKNOWN
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :encoding), _flag_atom_ref(ld, a))
    end
    ld.encoding = enc''',
         new='''    ld.encoding = enc'''),
    dict(id="ENCFLAG1-2 setEncoding does not store the encoding", file=PF, targets=U,
         old='''    ld.encoding = enc
    return true''',
         new='''    return true'''),
    dict(id="ENCFLAG1-3 setEncoding raises the wrong domain", file=PF, targets=T,
         old='''        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :encoding), _flag_atom_ref(ld, a))''',
         new='''        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :unicode_atoms), _flag_atom_ref(ld, a))'''),
    dict(id="ENCFLAG1-4 the encoding arm of set_flag_value does not call the setter", file=PF, targets=T,
         old='''            setEncoding(ld, a) || return false''',
         new='''            true'''),
    dict(id="ENCFLAG1-5 setUnicodeAtoms does not store the mode", file=PF, targets=R,
         old='''    ld.unicode_atoms = mode
    return true''',
         new='''    return true'''),
    dict(id="ENCFLAG1-6 setUnicodeAtoms does not stop at a refused mode", file=PF, targets=T,
         old='''    mode === nothing && return false
    ld.unicode_atoms = mode''',
         new='''    ld.unicode_atoms = something(mode, S_UATOMS_ACCEPT)'''),
    dict(id="ENCFLAG1-7 the unicode_atoms arm of set_flag_value does not call the setter", file=PF, targets=T,
         old='''            setUnicodeAtoms(ld, a) || return false''',
         new='''            true'''),
    dict(id="ENCFLAG1-8 open/4's type(text) default ignores the flag", file=FI, targets=U,
         old='''        return (ld.encoding, bom)                   # LD->encoding (pl-file.c:4173)''',
         new='''        return (ENC_UTF8, bom)                      # LD->encoding (pl-file.c:4173)'''),
    dict(id="ENCFLAG1-9 set_stream type(text) ignores the flag", file=FI, targets=U,
         old='''Ssetenc(s, ld.encoding) != 0    # LD->encoding (pl-file.c:2303)''',
         new='''Ssetenc(s, ENC_UTF8) != 0       # LD->encoding (pl-file.c:2303)'''),
    dict(id="ENCFLAG1-10 Snew does not take the encoding it is given", file=ST, targets=U,
         old='''        s.encoding = enc                            # initEncoding()''',
         new='''        s.encoding = ENC_UTF8                       # initEncoding()'''),
    dict(id="ENCFLAG1-11 Snew does not take the unicode_atoms mode it is given", file=ST, targets=R,
         old='''        s.unicode_atoms = uatoms                    # initUnicodeAtoms()
''',
         new='''        s.unicode_atoms = S_UATOMS_ACCEPT           # initUnicodeAtoms()
'''),
    dict(id="ENCFLAG1-12 Sopen_string does not take the unicode_atoms mode it is given", file=ST, targets=R,
         old='''    s.unicode_atoms = uatoms                    # initUnicodeAtoms() (pl-stream.c:4441)''',
         new='''    s.unicode_atoms = S_UATOMS_ACCEPT           # initUnicodeAtoms() (pl-stream.c:4441)'''),
    dict(id="ENCFLAG1-13 openStream's file does not get the flag's encoding", file=FI, targets=U,
         old='''Sopen_file(path, String(how), ld.encoding, ld.unicode_atoms)''',
         new='''Sopen_file(path, String(how), ENC_UTF8, ld.unicode_atoms)'''),
    dict(id="ENCFLAG1-14 openStream's file does not get the flag's unicode_atoms", file=FI, targets=R,
         old='''Sopen_file(path, String(how), ld.encoding, ld.unicode_atoms)''',
         new='''Sopen_file(path, String(how), ld.encoding, S_UATOMS_ACCEPT)'''),
    dict(id="ENCFLAG1-15 openStream's pipe does not get the flag's encoding", file=FI, targets=U,
         old='''Sopen_pipe(text_string(txt), String(how), ld.encoding, ld.unicode_atoms)''',
         new='''Sopen_pipe(text_string(txt), String(how), ENC_UTF8, ld.unicode_atoms)'''),
    dict(id="ENCFLAG1-16 Sopen_text drops the unicode_atoms mode", file=TX, targets=R,
         old='''    stream = Sopen_string(txt.text, length(txt.text), mode, uatoms)''',
         new='''    stream = Sopen_string(txt.text, length(txt.text), mode)'''),
    dict(id="ENCFLAG1-17 atom_to_term (term_to_atom) does not pass the flag's unicode_atoms", file=RD, targets=R,
         old='''    stream = Sopen_text(txt, "r", ld.unicode_atoms)
    stream === nothing && error("atom_to_term: Sopen_text")''',
         new='''    stream = Sopen_text(txt, "r")
    stream === nothing && error("atom_to_term: Sopen_text")'''),
    dict(id="ENCFLAG1-18 read_term_from_atom does not pass the flag's unicode_atoms", file=RD, targets=R,
         old='''    oldsrc = ld.read_source
    stream = Sopen_text(txt, "r", ld.unicode_atoms)''',
         new='''    oldsrc = ld.read_source
    stream = Sopen_text(txt, "r")'''),
    dict(id="ENCFLAG1-19 a new engine starts with ISO Latin-1 as its encoding", file="src/pl-global.jl", targets=T,
         old='''        ENC_UTF8,                               # encoding: DIVERGES''',
         new='''        ENC_ISO_LATIN_1,                        # encoding: DIVERGES'''),
]
