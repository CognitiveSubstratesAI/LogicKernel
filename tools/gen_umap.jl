# ORIGINAL: generates src/pl-umap.jl from swipl-devel's src/pl-umap.c, byte for byte.
# tools/gen_umap.jl — upstream's Unicode map is a GENERATED C file (Unicode/prolog_syntax_map.pl
# writes it from the Unicode data files). Its tables are data, so they are carried over as data:
# this tool reads them out of pl-umap.c at the pinned commit and writes src/pl-umap.jl, whose
# functions are ported by hand. Regenerate after moving the pin; test/core_text/test_umap.jl
# checks the generated tables against the C file whenever a checkout is present.
#
#   julia --project=. tools/gen_umap.jl [--check] [path/to/swipl-devel]   # default ~/dev-zone/…
#   (--check: exit 1 if src/pl-umap.jl differs from what the C file gives; write nothing)

const _PATHS = filter(a -> !startswith(a, "--"), ARGS)
const _UPSTREAM = if !isempty(_PATHS)
    _PATHS[1]
else
    get(ENV, "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL",
        joinpath(homedir(), "dev-zone", "swipl-devel"))
end

"A two-level map of the C source: its pages (prefix `pfx`) and its index `name`."
function parse_map(src::String, pfx::String, name::String, mapsize::Int)
    pages = Dict{String, Vector{UInt8}}()
    rx = Regex(
        "static const unsigned char (" * pfx * "0x[0-9a-f]+)\\[256\\] =\\s*\\{([^}]*)\\};",
        "s"
    )
    for pm in eachmatch(rx, src)
        body = replace(pm[2], r"/\*.*?\*/"s => "")
        bytes = [parse(UInt8, x[1]; base=16) for x in eachmatch(r"0x([0-9a-f]{2})", body)]
        length(bytes) == 256 || error("$(pm[1]): $(length(bytes)) entries")
        pages[pm[1]] = bytes
    end
    im = match(Regex(name * "\\[UNICODE_MAP_SIZE\\] =\\s*\\{([^}]*)\\};", "s"), src)
    im === nothing && error("$name not found")
    index = Union{String, UInt8}[]
    for e in eachmatch(Regex("(" * pfx * "0x[0-9a-f]+)|F\\(0x([0-9a-f]+)\\)"), im[1])
        push!(index, e[1] !== nothing ? String(e[1]) : parse(UInt8, e[2]; base=16))
    end
    length(index) == mapsize || error("$name: $(length(index)) of $mapsize entries")
    all(e -> !(e isa String) || haskey(pages, e), index) || error("$name: an unknown page")
    return (; pages, index)
end

"An enum's members, in order, from `typedef enum { … } name;`."
function parse_enum(src::String, name::String, pfx::String)
    em = match(Regex("typedef enum\\s*\\{([^}]*)\\}\\s*" * name * ";", "s"), src)
    em === nothing && error("$name not found")
    return [
        (String(x[1]), parse(Int, x[2]))
        for x in eachmatch(Regex("(" * pfx * "[A-Z_]+)\\s*=\\s*(\\d+)"), em[1])
    ]
end

"The C source's tables: the map size, both maps, the classes, decimal_bases, the pairs."
function parse_umap(path::AbstractString)
    src = read(path, String)
    m = match(r"#define UNICODE_MAP_SIZE (\d+)", src)
    m === nothing && error("UNICODE_MAP_SIZE not found")
    mapsize = parse(Int, m[1])
    cats = parse_enum(src, "u_category", "U_CAT_")
    ctypes = parse_enum(src, "u_ctype", "U_CTYPE_")
    uflags = parse_map(src, "ucp", "uflags_map", mapsize)
    uctype = parse_map(src, "uct", "uctype_map", mapsize)
    fm = match(r"static const unsigned short ctype_to_flags\[16\] =\s*\{([^}]*)\};"s, src)
    fm === nothing && error("ctype_to_flags not found")
    c2f = [parse(Int, x[1]; base=16) for x in eachmatch(r"0x([0-9a-f]+)", fm[1])]
    length(c2f) == 16 || error("ctype_to_flags: $(length(c2f)) entries")
    ucbits = [
        (String(x[1]), parse(Int, x[2]; base=16))
        for x in eachmatch(r"#define (UC_[A-Z]+)\s+0x([0-9a-f]+)", src)
    ]
    dm = match(r"static const int decimal_bases\[\] =\s*\{([^}]*)\};"s, src)
    dm === nothing && error("decimal_bases not found")
    bases = [parse(Int, x[1]; base=16) for x in eachmatch(r"0x([0-9a-f]+)", dm[1])]
    pz = match(r"#define PL_PAIR_TABLE_SIZE (\d+)", src)
    pz === nothing && error("PL_PAIR_TABLE_SIZE not found")
    tm = match(r"pl_pair_table\[PL_PAIR_TABLE_SIZE\] =\s*\{(.*?)\n\};"s, src)
    tm === nothing && error("pl_pair_table not found")
    pairs = [
        (parse(Int, x[1]; base=16), parse(Int, x[2]; base=16), x[3] == "true")
        for
        x in eachmatch(r"\{\s*0x([0-9a-f]+),\s*0x([0-9a-f]+),\s*(true|false)\s*\}", tm[1])
    ]
    length(pairs) == parse(Int, pz[1]) || error("pl_pair_table: $(length(pairs)) entries")
    return (; mapsize, cats, ctypes, uflags, uctype, c2f, ucbits, bases, pairs)
end

"Write one two-level map: its pages as `_<name>_pages` and its index as `<name>`, both Strings."
function write_map(io::IO, m, name::String, what::String)
    names = sort!(collect(keys(m.pages)); by=n -> parse(Int, n[6:end]; base=16))
    slot = Dict(n => i - 1 for (i, n) in enumerate(names))
    println(io, "# The pages of `", name, "` (", what,
        "), 256 entries each, in code-point order: ",
        length(names), " pages; a String (frozen: no module-level mutable state).")
    println(io, "const _", name, "_pages = String(hex2bytes(")
    for (i, n) in enumerate(names)
        println(
            io,
            "    \"",
            bytes2hex(m.pages[n]),
            "\"",
            i < length(names) ? " *" : "",
            "  # ",
            n
        )
    end
    println(io, "))")
    println(io)
    println(
        io,
        "# `",
        name,
        "`: per 256 code points, an Int16, little-endian (`_map_entry`): the page's 0-based"
    )
    println(
        io,
        "# number in `_",
        name,
        "_pages`, or -1 - b for a page whose every entry is the byte b"
    )
    println(io, "# (upstream's `F(b)`).")
    vals = [e isa String ? slot[e] : -1 - Int(e) for e in m.index]
    bytes = UInt8[]
    for v in vals
        u = reinterpret(UInt16, Int16(v))
        push!(bytes, u % UInt8, (u >> 8) % UInt8)
    end
    print(io, "const ", name, " = String(hex2bytes(")
    hx = bytes2hex(bytes)
    for (k, i) in enumerate(1:128:length(hx))
        print(
            io, "\n    \"", hx[i:min(end, i + 127)], "\"", i + 127 < length(hx) ? " *" : ""
        )
    end
    println(io, "\n))")
    println(io)
    return nothing
end

"Write an enum's members."
function write_enum(io::IO, name::String, members, what::String)
    println(io, "# ", what, " (pl-umap.c `", name, "`).")
    println(io, "@enum ", name, "::UInt8 begin")
    for (n, v) in members
        println(io, "    ", n, " = ", v)
    end
    println(io, "end")
    println(io)
    return nothing
end

"Write src/pl-umap.jl's generated section from the parsed tables."
function write_umap(io::IO, u)
    println(io, "#! format: off")
    println(io, "const UNICODE_MAP_SIZE = ", u.mapsize)
    println(io)
    write_enum(
        io, "u_category", u.cats, "The syntax category in bits 0..3 of a `uflags_map` entry"
    )
    write_map(io, u.uflags, "uflags_map", "the syntax category and the display width")
    write_enum(
        io, "u_ctype", u.ctypes, "The POSIX class in bits 0..3 of a `uctype_map` entry"
    )
    for (n, v) in u.ucbits
        println(io, "const ", n, " = 0x", string(v; base=16, pad=4))
    end
    println(io)
    println(io, "# The `UC_*` bits of each `u_ctype` (pl-umap.c `ctype_to_flags`).")
    print(io, "const ctype_to_flags = (")
    for (i, f) in enumerate(u.c2f)
        (i - 1) % 8 == 0 && print(io, "\n    ")
        print(io, "0x", string(f; base=16, pad=4), ", ")
    end
    println(io, "\n)")
    println(io)
    write_map(io, u.uctype, "uctype_map", "the POSIX class")
    println(
        io,
        "# The first code point of every run of ten decimal digits (pl-umap.c `decimal_bases`)."
    )
    print(io, "const decimal_bases = (")
    for (i, b) in enumerate(u.bases)
        (i - 1) % 8 == 0 && print(io, "\n    ")
        print(io, b, ", ")
    end
    println(io, "\n)")
    println(io)
    println(io, "const PL_PAIR_TABLE_SIZE = ", length(u.pairs))
    println(io)
    println(
        io, "# Paired brackets and quotes, sorted by code: (code, mate, is_open) (pl-umap.c"
    )
    println(io, "# `pl_pair_table`).")
    print(io, "const pl_pair_table = (")
    for (i, (c, m, o)) in enumerate(u.pairs)
        (i - 1) % 4 == 0 && print(io, "\n    ")
        print(io, "(", c, ", ", m, ", ", o, "), ")
    end
    println(io, "\n)")
    println(io, "#! format: on")
    return nothing
end

const GEN_BEGIN = "# ── GENERATED by tools/gen_umap.jl from pl-umap.c — do not edit up to END GENERATED ──"
const GEN_END = "# ── END GENERATED ──"

"The generated region of `dst` replaced by the tables of `src` (the upstream C file)."
function regenerate(src::AbstractString, dst::AbstractString)::String
    text = read(dst, String)
    b = findfirst(GEN_BEGIN, text)
    e = findfirst(GEN_END, text)
    (b === nothing || e === nothing || first(e) < last(b)) &&
        error("$dst: the generated region's markers are missing")
    io = IOBuffer()
    write_umap(io, parse_umap(src))
    return string(text[1:last(b)], "\n", String(take!(io)), text[first(e):end])
end

if abspath(PROGRAM_FILE) == @__FILE__
    dst = joinpath(@__DIR__, "..", "src", "pl-umap.jl")
    new = regenerate(joinpath(_UPSTREAM, "src", "pl-umap.c"), dst)
    if "--check" in ARGS
        new == read(dst, String) || (println(stderr, "src/pl-umap.jl is stale"); exit(1))
    else
        write(dst, new)
    end
end
