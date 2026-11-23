# CLASS: test
# ORIGINAL: YAML1 piece A's gate - the typed ccall wrappers of libyaml (LibYAML_jll, D-1004) that src/pl-yaml.jl binds for packages/yaml/yaml4pl.c
# (packages-yaml 0ce45ecf; the C line numbers are in the wrappers' comments). Every expectation is derived, none invented: from yaml.h (the enum
# numbers, the signatures), from the C (the order of events `emit_event` sends, the error branches `parse_document`/`emit_event` read), from the
# plan's measured numbers (evidence/R2/yaml_plan.md section 1: the gcc probe of the struct sizes and field offsets; section 3: the three parser error
# texts and the two emitter error texts, measured through yaml_read/yaml:yaml_emit_event on a secondary oracle with libyaml 0.2.5) and, where the row
# says "libyaml source", from libyaml's own parser.c/emitter.c as remembered (no copy of it is read here): those rows are the ones to look at first when
# the file runs. NO CALLBACK is used: the parser reads a string (`yaml_parser_set_input_string`) and the emitter writes into a fixed buffer
# (`yaml_emitter_set_output_string`), both TEST-LOCAL ccalls (not among the 23 wrappers); the read/write handlers belong to the parse driver (B2)
# and the emitter piece (D). No term type is used. NOTHING HERE HAS RUN: no Julia process was started to write this file, and LibYAML_jll is not in
# the depot yet (the first `Pkg.instantiate` needs the network once: the dispatcher runs it before the first `check`), so no test of this file can
# run before that.
using Test, LogicKernel
import LibYAML_jll
const LK = LogicKernel
const DL = Base.Libc.Libdl

# --- test-local helpers -------------------------------------------------------------------------------------------------------------------

# what one parsed event shows through the wrappers' readers, by type (a NamedTuple; the fields are the ones yaml4pl.c reads)
function _ev_info(ev::Ptr{Cvoid})
    t = LK.yaml_cev_type(ev)
    if t == LK.YAML_SCALAR_EVENT
        return (;
            type = t, anchor = LK.yaml_cev_anchor(ev), tag = LK.yaml_cev_tag(ev), value = LK.yaml_cev_value(ev),
            length = LK.yaml_cev_scalar_length(ev), plain = LK.yaml_cev_plain_implicit(ev),
            quoted = LK.yaml_cev_quoted_implicit(ev), style = LK.yaml_cev_scalar_style(ev),
        )
    elseif t == LK.YAML_ALIAS_EVENT
        return (; type = t, anchor = LK.yaml_cev_anchor(ev))
    elseif t == LK.YAML_SEQUENCE_START_EVENT || t == LK.YAML_MAPPING_START_EVENT
        return (;
            type = t, anchor = LK.yaml_cev_anchor(ev), tag = LK.yaml_cev_tag(ev),
            implicit = LK.yaml_cev_collection_implicit(ev), style = LK.yaml_cev_collection_style(ev),
        )
    elseif t == LK.YAML_STREAM_START_EVENT
        return (; type = t, encoding = LK.yaml_cev_encoding(ev))
    elseif t == LK.YAML_DOCUMENT_START_EVENT
        return (; type = t, implicit = LK.yaml_cev_document_start_implicit(ev))
    elseif t == LK.YAML_DOCUMENT_END_EVENT
        return (; type = t, implicit = LK.yaml_cev_document_end_implicit(ev))
    end
    return (; type = t)
end

# parse `input` through the raw wrappers (no callback: the string input): (events, ok, err, problem); stops at STREAM-END or at the first error
function _parse_all(input::Vector{UInt8})
    parser = LK.yaml_parser_alloc()
    event = LK.yaml_event_alloc()
    infos = Any[]
    ok = true
    err = -1
    problem = nothing
    GC.@preserve input begin
        @test LK.yaml_parser_initialize(parser) == 1
        ccall(
            (:yaml_parser_set_input_string, LK.libyaml), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t),
            parser, input, length(input)
        )
        for _ in 1:1000                                    # a bound: libyaml answers STREAM-END events forever once it is past the end
            if LK.yaml_parser_parse(parser, event) != 1
                ok = false
                break
            end
            push!(infos, _ev_info(event))
            t = LK.yaml_cev_type(event)
            LK.yaml_event_delete(event)
            t == LK.YAML_STREAM_END_EVENT && break
        end
        err = LK.yaml_parser_error(parser)         # read BEFORE the delete: yaml_parser_delete zeroes the struct
        problem = LK.yaml_parser_problem(parser)
        LK.yaml_parser_delete(parser)
    end
    LK.yaml_free(event)
    LK.yaml_free(parser)
    return (; events = infos, ok, err, problem)
end
_parse_all(s::String) = _parse_all(Vector{UInt8}(codeunits(s)))

_types(r) = Int[e.type for e in r.events]

# emit the mapping `pairs` (String => String, plain scalars) as ONE document into a fixed 512-byte buffer through the raw wrappers, the order of events
# `emit_event` sends (C 1125-1201): (rcs of every emit, the text written)
function _emit_map(pairs; canonical::Bool = false, unicode::Bool = true)
    em = LK.yaml_emitter_alloc()
    ev = LK.yaml_event_alloc()
    out = zeros(UInt8, 512)
    written = Ref{Csize_t}(0)
    rcs = Cint[]
    GC.@preserve out written begin
        @test LK.yaml_emitter_initialize(em) == 1
        ccall(
            (:yaml_emitter_set_output_string, LK.libyaml), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}),
            em, out, length(out), written
        )
        LK.yaml_emitter_set_canonical(em, canonical)
        LK.yaml_emitter_set_unicode(em, unicode)
        step(initrc) = push!(rcs, initrc == 1 ? LK.yaml_emitter_emit(em, ev) : Cint(-1))
        step(LK.yaml_stream_start_event_initialize(ev, LK.YAML_UTF8_ENCODING))
        step(LK.yaml_document_start_event_initialize(ev, true))
        step(LK.yaml_mapping_start_event_initialize(ev, nothing, nothing, false, LK.YAML_BLOCK_MAPPING_STYLE))
        for (k, v) in pairs
            step(LK.yaml_scalar_event_initialize(ev, nothing, nothing, k, -1, true, true, LK.YAML_PLAIN_SCALAR_STYLE))
            step(LK.yaml_scalar_event_initialize(ev, nothing, nothing, v, -1, true, true, LK.YAML_PLAIN_SCALAR_STYLE))
        end
        step(LK.yaml_mapping_end_event_initialize(ev))
        step(LK.yaml_document_end_event_initialize(ev, true))
        step(LK.yaml_stream_end_event_initialize(ev))
        LK.yaml_emitter_delete(em)
    end
    LK.yaml_free(ev)
    LK.yaml_free(em)
    return (rcs, String(out[1:Int(written[])]))
end

# the first emit of ONE event on a fresh emitter: (rc, error, problem); `mk` initializes the zeroed event
function _emit_first(mk)
    em = LK.yaml_emitter_alloc()
    ev = LK.yaml_event_alloc()
    out = zeros(UInt8, 64)
    written = Ref{Csize_t}(0)
    rc = Cint(-1)
    err = -1
    problem = nothing
    GC.@preserve out written begin
        LK.yaml_emitter_initialize(em)
        ccall(
            (:yaml_emitter_set_output_string, LK.libyaml), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}),
            em, out, length(out), written
        )
        @test mk(ev) == 1
        rc = LK.yaml_emitter_emit(em, ev)
        err = LK.yaml_emitter_error(em)
        problem = LK.yaml_emitter_problem(em)
        LK.yaml_emitter_delete(em)
    end
    LK.yaml_free(ev)
    LK.yaml_free(em)
    return (rc, err, problem)
end

# --- the library, its version, its entry points --------------------------------------------------------------------------------------------

@testset "one libyaml in the process, the one LibYAML_jll names, version 0.2.5" begin
    loaded = filter(contains("libyaml"), DL.dllist())
    @test length(loaded) == 1                        # a system libyaml winning the dlopen by soname would change the version silently
    @test LibYAML_jll.libyaml_path == loaded[1]
    @test contains(loaded[1], "artifacts")            # the JLL's own copy, not the system's
    @test LK.libyaml == LibYAML_jll.libyaml
    @test LibYAML_jll.libyaml_handle == DL.dlopen(LibYAML_jll.libyaml)

    # the oracle's libyaml (evidence/R2/yaml_plan.md F2: `yaml_get_version_string()` of the system libyaml-0.so.2.0.9 = "0.2.5")
    @test LK.yaml_get_version_string() == "0.2.5"
    @test LK.yaml_get_version() == (Cint(0), Cint(2), Cint(5))
end

@testset "the 23 entry points are exported by the library" begin
    names = (
        :yaml_get_version_string, :yaml_get_version,
        :yaml_parser_initialize, :yaml_parser_set_input, :yaml_parser_parse, :yaml_parser_delete, :yaml_event_delete,
        :yaml_emitter_initialize, :yaml_emitter_set_output, :yaml_emitter_set_canonical, :yaml_emitter_set_unicode,
        :yaml_emitter_delete, :yaml_emitter_emit,
        :yaml_stream_start_event_initialize, :yaml_stream_end_event_initialize,
        :yaml_document_start_event_initialize, :yaml_document_end_event_initialize,
        :yaml_mapping_start_event_initialize, :yaml_mapping_end_event_initialize,
        :yaml_sequence_start_event_initialize, :yaml_sequence_end_event_initialize,
        :yaml_scalar_event_initialize, :yaml_alias_event_initialize,
    )
    @test length(names) == 23
    @test length(unique(names)) == 23
    for n in names
        @test DL.dlsym_e(LibYAML_jll.libyaml_handle, n) != C_NULL
    end
end

# --- sizes and offsets (the plan's gcc probe) -------------------------------------------------------------------------------------------------

@testset "struct sizes: libyaml's own initialisers clear exactly sizeof (a canary behind the block survives)" begin
    pad = 64
    # a block of size + pad bytes filled with 0xAA; `init` makes libyaml clear/fill its struct at the start of it
    function canary(size::Int, init)
        p = Libc.malloc(size + pad)
        for i in 0:(size + pad - 1)
            unsafe_store!(Ptr{UInt8}(p), 0xaa, i + 1)
        end
        init(p)
        body_tail = UInt8[unsafe_load(Ptr{UInt8}(p), i + 1) for i in (size - 8):(size - 1)]
        behind = UInt8[unsafe_load(Ptr{UInt8}(p), i + 1) for i in size:(size + pad - 1)]
        return (p, body_tail, behind)
    end

    # doc-only numbers (plan section 1, MEASURED by a gcc probe against yaml.h 0.2.5, x86-64)
    @test LK.YAML_EVENT_SIZE == 104
    @test LK.YAML_PARSER_SIZE == 480
    @test LK.YAML_EMITTER_SIZE == 432

    # the event: every `_initialize` memsets sizeof(yaml_event_t); its last field (end_mark.column) is then zero, and nothing behind it is touched
    (p, tail, behind) = canary(LK.YAML_EVENT_SIZE, p -> LK.yaml_stream_end_event_initialize(p))
    @test all(==(0x00), tail)
    @test all(==(0xaa), behind)
    Libc.free(p)

    # the parser and the emitter: `_initialize` memsets sizeof, their last field (`document`) stays NULL
    (p, tail, behind) = canary(LK.YAML_PARSER_SIZE, p -> LK.yaml_parser_initialize(p))
    @test all(==(0x00), tail)
    @test all(==(0xaa), behind)
    LK.yaml_parser_delete(p)
    Libc.free(p)

    (p, tail, behind) = canary(LK.YAML_EMITTER_SIZE, p -> LK.yaml_emitter_initialize(p))
    @test all(==(0x00), tail)
    @test all(==(0xaa), behind)
    LK.yaml_emitter_delete(p)
    Libc.free(p)

    # calloc helpers: zeroed, distinct, freeable
    a = LK.yaml_event_alloc()
    b = LK.yaml_event_alloc()
    @test a != C_NULL && b != C_NULL && a != b
    @test all(i -> unsafe_load(Ptr{UInt8}(a), i) == 0x00, 1:LK.YAML_EVENT_SIZE)
    pp = LK.yaml_parser_alloc()
    @test pp != C_NULL
    @test all(i -> unsafe_load(Ptr{UInt8}(pp), i) == 0x00, 1:LK.YAML_PARSER_SIZE)
    LK.yaml_free(pp)
    pe = LK.yaml_emitter_alloc()
    @test pe != C_NULL
    @test all(i -> unsafe_load(Ptr{UInt8}(pe), i) == 0x00, 1:LK.YAML_EMITTER_SIZE)
    LK.yaml_free(pe)
    LK.yaml_free(a)
    LK.yaml_free(b)
    LK.yaml_free(Ptr{Cvoid}(C_NULL))                 # free(NULL) is a no-op
    @test LK.yaml_alloc(16) != C_NULL
end

@testset "error code names are yaml.h's yaml_error_type_t (doc-only numbers)" begin
    @test (
        LK.YAML_NO_ERROR, LK.YAML_MEMORY_ERROR, LK.YAML_READER_ERROR, LK.YAML_SCANNER_ERROR,
        LK.YAML_PARSER_ERROR, LK.YAML_COMPOSER_ERROR, LK.YAML_WRITER_ERROR, LK.YAML_EMITTER_ERROR,
    ) == (0, 1, 2, 3, 4, 5, 6, 7)
end

# --- event initialisers fill the measured offsets -------------------------------------------------------------------------------------------

@testset "scalar event: anchor 8, tag 16, value 24, length 32, plain 40, quoted 44, style 48" begin
    ev = LK.yaml_event_alloc()
    @test LK.yaml_scalar_event_initialize(ev, "anc", "tg", "hello", -1, true, false, LK.YAML_DOUBLE_QUOTED_SCALAR_STYLE) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_SCALAR_EVENT
    @test LK.yaml_cev_anchor(ev) == "anc"
    @test LK.yaml_cev_tag(ev) == "tg"
    @test LK.yaml_cev_value(ev) == "hello"
    @test LK.yaml_cev_scalar_length(ev) == 5          # -1 means strlen
    @test LK.yaml_cev_plain_implicit(ev) == true
    @test LK.yaml_cev_quoted_implicit(ev) == false
    @test LK.yaml_cev_scalar_style(ev) == LK.YAML_DOUBLE_QUOTED_SCALAR_STYLE
    LK.yaml_event_delete(ev)
    @test LK.yaml_cev_type(ev) == LK.YAML_NO_EVENT     # yaml_event_delete clears the struct
    @test LK.yaml_cev_anchor(ev) === nothing           # ... so every pointer field reads as NULL
    @test LK.yaml_cev_tag(ev) === nothing
    @test LK.yaml_cev_value(ev) === nothing
    @test LK.yaml_cev_scalar_length(ev) == 0

    # the two flags the other way round, another style, no anchor, no tag
    @test LK.yaml_scalar_event_initialize(ev, nothing, nothing, "x", -1, false, true, LK.YAML_LITERAL_SCALAR_STYLE) == 1
    @test LK.yaml_cev_anchor(ev) === nothing
    @test LK.yaml_cev_tag(ev) === nothing
    @test LK.yaml_cev_value(ev) == "x"
    @test LK.yaml_cev_plain_implicit(ev) == false
    @test LK.yaml_cev_quoted_implicit(ev) == true
    @test LK.yaml_cev_scalar_style(ev) == LK.YAML_LITERAL_SCALAR_STYLE
    LK.yaml_event_delete(ev)

    # an explicit length shorter than the text takes a prefix; an embedded NUL counts (libyaml source: the value is copied with `length`)
    @test LK.yaml_scalar_event_initialize(ev, nothing, nothing, "abcdef", 3, true, true, LK.YAML_PLAIN_SCALAR_STYLE) == 1
    @test LK.yaml_cev_value(ev) == "abc"
    @test LK.yaml_cev_scalar_length(ev) == 3
    LK.yaml_event_delete(ev)
    @test LK.yaml_scalar_event_initialize(ev, nothing, nothing, "a\0b", 3, true, true, LK.YAML_PLAIN_SCALAR_STYLE) == 1
    @test LK.yaml_cev_scalar_length(ev) == 3
    @test LK.yaml_cev_value(ev) == "a\0b"
    LK.yaml_event_delete(ev)

    # a UTF-8 value keeps its bytes (length counts bytes), an invalid UTF-8 one is refused by the initialiser (returns 0; libyaml source: yaml_check_utf8)
    @test LK.yaml_scalar_event_initialize(ev, nothing, nothing, "\u00e9\u20ac", -1, true, true, LK.YAML_PLAIN_SCALAR_STYLE) == 1
    @test LK.yaml_cev_scalar_length(ev) == ncodeunits("\u00e9\u20ac")
    @test LK.yaml_cev_value(ev) == "\u00e9\u20ac"
    LK.yaml_event_delete(ev)
    bad = String(UInt8[0x61, 0xff])
    @test LK.yaml_scalar_event_initialize(ev, nothing, nothing, bad, -1, true, true, LK.YAML_PLAIN_SCALAR_STYLE) == 0
    LK.yaml_free(ev)
end

@testset "sequence and mapping start events: anchor 8, tag 16, implicit 24, style 28" begin
    ev = LK.yaml_event_alloc()
    @test LK.yaml_sequence_start_event_initialize(ev, "sa", "st", true, LK.YAML_BLOCK_SEQUENCE_STYLE) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_SEQUENCE_START_EVENT
    @test LK.yaml_cev_anchor(ev) == "sa"
    @test LK.yaml_cev_tag(ev) == "st"
    @test LK.yaml_cev_collection_implicit(ev) == true
    @test LK.yaml_cev_collection_style(ev) == LK.YAML_BLOCK_SEQUENCE_STYLE
    LK.yaml_event_delete(ev)

    @test LK.yaml_mapping_start_event_initialize(ev, "ma", "mt", false, LK.YAML_BLOCK_MAPPING_STYLE) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_MAPPING_START_EVENT
    @test LK.yaml_cev_anchor(ev) == "ma"
    @test LK.yaml_cev_tag(ev) == "mt"
    @test LK.yaml_cev_collection_implicit(ev) == false
    @test LK.yaml_cev_collection_style(ev) == LK.YAML_BLOCK_MAPPING_STYLE
    LK.yaml_event_delete(ev)

    @test LK.yaml_sequence_start_event_initialize(ev, nothing, nothing, false, LK.YAML_BLOCK_SEQUENCE_STYLE) == 1
    @test LK.yaml_cev_anchor(ev) === nothing
    @test LK.yaml_cev_tag(ev) === nothing
    @test LK.yaml_cev_collection_implicit(ev) == false
    LK.yaml_event_delete(ev)
    @test LK.yaml_mapping_start_event_initialize(ev, nothing, nothing, true, LK.YAML_BLOCK_MAPPING_STYLE) == 1
    @test LK.yaml_cev_anchor(ev) === nothing
    @test LK.yaml_cev_tag(ev) === nothing
    @test LK.yaml_cev_collection_implicit(ev) == true
    LK.yaml_free(ev)
end

@testset "the other initialisers: stream, document, alias, ends" begin
    ev = LK.yaml_event_alloc()
    @test LK.yaml_stream_start_event_initialize(ev, LK.YAML_UTF8_ENCODING) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_STREAM_START_EVENT
    @test LK.yaml_cev_encoding(ev) == LK.YAML_UTF8_ENCODING
    LK.yaml_event_delete(ev)
    @test LK.yaml_stream_start_event_initialize(ev, LK.YAML_ANY_ENCODING) == 1
    @test LK.yaml_cev_encoding(ev) == LK.YAML_ANY_ENCODING
    LK.yaml_event_delete(ev)

    @test LK.yaml_stream_end_event_initialize(ev) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_STREAM_END_EVENT
    LK.yaml_event_delete(ev)

    @test LK.yaml_document_start_event_initialize(ev, true) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_DOCUMENT_START_EVENT
    @test LK.yaml_cev_document_start_implicit(ev) == true
    LK.yaml_event_delete(ev)
    @test LK.yaml_document_start_event_initialize(ev, false) == 1
    @test LK.yaml_cev_document_start_implicit(ev) == false
    LK.yaml_event_delete(ev)

    @test LK.yaml_document_end_event_initialize(ev, true) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_DOCUMENT_END_EVENT
    @test LK.yaml_cev_document_end_implicit(ev) == true
    LK.yaml_event_delete(ev)
    @test LK.yaml_document_end_event_initialize(ev, false) == 1
    @test LK.yaml_cev_document_end_implicit(ev) == false
    LK.yaml_event_delete(ev)

    @test LK.yaml_alias_event_initialize(ev, "al") == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_ALIAS_EVENT
    @test LK.yaml_cev_anchor(ev) == "al"
    LK.yaml_event_delete(ev)

    @test LK.yaml_sequence_end_event_initialize(ev) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_SEQUENCE_END_EVENT
    LK.yaml_event_delete(ev)
    @test LK.yaml_mapping_end_event_initialize(ev) == 1
    @test LK.yaml_cev_type(ev) == LK.YAML_MAPPING_END_EVENT
    LK.yaml_event_delete(ev)
    LK.yaml_free(ev)
end

# --- the parser, through the raw wrappers, without a callback --------------------------------------------------------------------------------

@testset "parser: the event types of a clean document, in order (plan section 4)" begin
    r = _parse_all("a: 1\n")
    @test r.ok
    @test r.err == LK.YAML_NO_ERROR
    # STREAM-START, DOCUMENT-START, MAPPING-START, SCALAR, SCALAR, MAPPING-END, DOCUMENT-END, STREAM-END
    @test _types(r) == [1, 3, 9, 6, 6, 10, 4, 2]
    @test _types(r) == [
        LK.YAML_STREAM_START_EVENT, LK.YAML_DOCUMENT_START_EVENT, LK.YAML_MAPPING_START_EVENT, LK.YAML_SCALAR_EVENT,
        LK.YAML_SCALAR_EVENT, LK.YAML_MAPPING_END_EVENT, LK.YAML_DOCUMENT_END_EVENT, LK.YAML_STREAM_END_EVENT,
    ]
    @test r.events[1].encoding == LK.YAML_UTF8_ENCODING
    @test r.events[2].implicit == true                       # no `---`
    @test r.events[3].anchor === nothing
    @test r.events[3].tag === nothing
    @test r.events[3].implicit == true                       # no tag
    @test r.events[4].value == "a"
    @test r.events[5].value == "1"
    @test r.events[4].length == 1
    @test r.events[7].implicit == true                       # no `...`

    # a sequence: STREAM-START, DOCUMENT-START, SEQUENCE-START, SCALAR x2, SEQUENCE-END, DOCUMENT-END, STREAM-END
    r = _parse_all("- x\n- y\n")
    @test _types(r) == [1, 3, 7, 6, 6, 8, 4, 2]
    @test [e.value for e in r.events if e.type == LK.YAML_SCALAR_EVENT] == ["x", "y"]

    # an empty stream has no document
    r = _parse_all("")
    @test r.ok
    @test _types(r) == [1, 2]
end

@testset "parser: fields at the measured offsets - anchors, tags, styles, implicit flags, aliases" begin
    # a tagged and anchored scalar document: `!!str` is expanded to the full tag (libyaml source: the default %TAG)
    r = _parse_all("&a1 !!str x\n")
    @test r.ok
    s = r.events[3]
    @test s.type == LK.YAML_SCALAR_EVENT
    @test s.anchor == "a1"
    @test s.tag == "tag:yaml.org,2002:str"
    @test s.value == "x"
    @test s.plain == false && s.quoted == false              # a tagged scalar is neither plain- nor quoted-implicit (libyaml source: parser.c)
    @test s.style == LK.YAML_PLAIN_SCALAR_STYLE

    # the three scalar styles and their implicit flags: plain -> plain_implicit, quoted -> quoted_implicit (libyaml source: parser.c)
    r = _parse_all("[a, 'b', \"c\"]\n")
    sc = [e for e in r.events if e.type == LK.YAML_SCALAR_EVENT]
    @test [e.value for e in sc] == ["a", "b", "c"]
    @test [e.style for e in sc] == [LK.YAML_PLAIN_SCALAR_STYLE, LK.YAML_SINGLE_QUOTED_SCALAR_STYLE, LK.YAML_DOUBLE_QUOTED_SCALAR_STYLE]
    @test [e.plain for e in sc] == [true, false, false]
    @test [e.quoted for e in sc] == [false, true, true]

    # literal and folded block scalars
    r = _parse_all("- |\n  l1\n- >\n  f1\n")
    sc = [e for e in r.events if e.type == LK.YAML_SCALAR_EVENT]
    @test [e.style for e in sc] == [LK.YAML_LITERAL_SCALAR_STYLE, LK.YAML_FOLDED_SCALAR_STYLE]

    # an anchored and tagged flow sequence and mapping: the anchor and tag of a collection-start are at the same offsets (8, 16) as a scalar's;
    # with a tag the event is not `implicit`; the flow style is 2 (yaml.h: FLOW follows BLOCK)
    r = _parse_all("&s !!seq [1]\n")
    q = r.events[3]
    @test q.type == LK.YAML_SEQUENCE_START_EVENT
    @test q.anchor == "s"
    @test q.tag == "tag:yaml.org,2002:seq"
    @test q.implicit == false
    @test q.style == 2
    r = _parse_all("&m {a: 1}\n")
    m = r.events[3]
    @test m.type == LK.YAML_MAPPING_START_EVENT
    @test m.anchor == "m"
    @test m.tag === nothing
    @test m.implicit == true
    @test m.style == 2

    # block collections have style 1
    @test _parse_all("- x\n").events[3].style == LK.YAML_BLOCK_SEQUENCE_STYLE
    @test _parse_all("a: 1\n").events[3].style == LK.YAML_BLOCK_MAPPING_STYLE

    # an alias carries its anchor at offset 8, the same offset as every other anchor
    r = _parse_all("[&x 1, *x]\n")
    @test _types(r) == [1, 3, 7, 6, 5, 8, 4, 2]
    @test r.events[4].anchor == "x"
    @test r.events[5].type == LK.YAML_ALIAS_EVENT
    @test r.events[5].anchor == "x"

    # explicit document start and end markers clear the two implicit flags
    r = _parse_all("--- a\n...\n")
    @test r.events[2].implicit == false
    @test r.events[4].implicit == false

    # two documents in one stream
    r = _parse_all("a\n---\nb\n")
    @test _types(r) == [1, 3, 6, 4, 3, 6, 4, 2]

    # an embedded NUL byte survives in the value, counted by `length` (the C reads `scalar.length`, not strlen)
    r = _parse_all(UInt8[0x22, 0x61, 0x5c, 0x30, 0x62, 0x22, 0x0a])   # "a\0b" with a YAML escape \0
    @test r.ok
    @test r.events[3].value == "a\0b"
    @test r.events[3].length == 3
end

@testset "parser: error codes and problem texts (plan section 3, measured on libyaml 0.2.5)" begin
    # PARSER error (4)
    r = _parse_all("a: [1, 2")
    @test !r.ok
    @test r.err == LK.YAML_PARSER_ERROR
    @test r.problem == "did not find expected ',' or ']'"

    # SCANNER error (3)
    r = _parse_all("a: \"\\q\"")
    @test !r.ok
    @test r.err == LK.YAML_SCANNER_ERROR
    @test r.problem == "found unknown escape character"

    # READER error (2): a byte that cannot start a UTF-8 sequence
    r = _parse_all(UInt8[0x61, 0x3a, 0x20, 0xff])
    @test !r.ok
    @test r.err == LK.YAML_READER_ERROR
    @test r.problem == "invalid leading UTF-8 octet"

    # the events before the error were delivered: a bad second entry still parsed STREAM-START and DOCUMENT-START
    r = _parse_all("- a\n- [b\n")
    @test !r.ok
    @test _types(r)[1:2] == [LK.YAML_STREAM_START_EVENT, LK.YAML_DOCUMENT_START_EVENT]
end

# --- the emitter, through the raw wrappers, into a fixed buffer (no callback) ----------------------------------------------------------------

@testset "emitter: a one-pair mapping becomes \"a: 1\\n\"" begin
    (rcs, text) = _emit_map(["a" => "1"])
    @test rcs == fill(Cint(1), 8)                            # stream-start, document-start, mapping-start, 2 scalars, mapping-end, document-end, stream-end
    @test text == "a: 1\n"
end

@testset "emitter: two pairs, the order of the keys" begin
    (rcs, text) = _emit_map(["a" => "1", "b" => "x"])
    @test all(==(Cint(1)), rcs)
    @test text == "a: 1\nb: x\n"
end

@testset "emitter: canonical and unicode flags reach the emitter (offsets 124 and 136 by libyaml's own setters)" begin
    (_, plain) = _emit_map(["a" => "1"])
    (rcs, canon) = _emit_map(["a" => "1"]; canonical = true)
    @test all(==(Cint(1)), rcs)
    @test canon != plain
    @test startswith(canon, "---")                           # libyaml source: canonical output always writes the document-start marker

    # non-ASCII: with unicode the character is written as is, without it a double-quoted \xE9 escape (libyaml source: emitter.c write_double_quoted)
    (_, with_u) = _emit_map(["a" => "\u00e9"]; unicode = true)
    (_, without_u) = _emit_map(["a" => "\u00e9"]; unicode = false)
    @test with_u == "a: \u00e9\n"
    @test without_u == "a: \"\\xE9\"\n"
end

@testset "emitter: error code 7 and the problem text (plan section 3)" begin
    # MAPPING-END as the first event
    (rc, err, problem) = _emit_first(LK.yaml_mapping_end_event_initialize)
    @test rc == 0
    @test err == LK.YAML_EMITTER_ERROR
    @test problem == "expected STREAM-START"

    # a STREAM-START first is accepted
    (rc, err, problem) = _emit_first(ev -> LK.yaml_stream_start_event_initialize(ev, LK.YAML_UTF8_ENCODING))
    @test rc == 1
    @test err == LK.YAML_NO_ERROR
    @test problem === nothing

    # two STREAM-STARTs in a row: the second one is judged at once (libyaml source: only DOCUMENT-START and the collection starts wait for look-ahead events)
    em = LK.yaml_emitter_alloc()
    ev = LK.yaml_event_alloc()
    out = zeros(UInt8, 64)
    written = Ref{Csize_t}(0)
    GC.@preserve out written begin
        LK.yaml_emitter_initialize(em)
        ccall(
            (:yaml_emitter_set_output_string, LK.libyaml), Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ref{Csize_t}),
            em, out, length(out), written
        )
        @test LK.yaml_stream_start_event_initialize(ev, LK.YAML_UTF8_ENCODING) == 1
        @test LK.yaml_emitter_emit(em, ev) == 1
        @test LK.yaml_stream_start_event_initialize(ev, LK.YAML_UTF8_ENCODING) == 1
        @test LK.yaml_emitter_emit(em, ev) == 0
        @test LK.yaml_emitter_error(em) == LK.YAML_EMITTER_ERROR
        @test LK.yaml_emitter_problem(em) == "expected DOCUMENT-START or STREAM-END"
        LK.yaml_emitter_delete(em)
    end
    LK.yaml_free(ev)
    LK.yaml_free(em)
end
