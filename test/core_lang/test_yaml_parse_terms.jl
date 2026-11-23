# ORIGINAL: YAML1 piece B1's gate - the parse-side term layer of packages/yaml/yaml4pl.c (the node stack push/pop, extend, put_scalar,
# create_mapping, get_mapping_mapping, create_sequence, get_sequence_list), src/pl-yaml.jl. NO oracle and no libyaml: the events are built by
# hand (`yaml_event`), every expected value is read off yaml4pl.c (packages-yaml 0ce45ecf, lines 62-152, 344-376, 562-610) and each row names the
# branch it exercises. The result terms are compared through `_yp_shape`, a plain Julia value (an integer, a float, ("a", atom text), ("s", string
# text), ("v",) for a variable, ("c", name, args...) for a compound, a Vector for a proper list). Nothing here has run (no Julia process was started
# to write this file): BLIND RISKS the lane settles are named where they bear (the text forms `1e5`/`0o17`/`0x1F` that PL_put_term_from_chars must
# read, the NUL byte of `a<NUL>b` through PL_get_text, `1e400` under the kernel's float_overflow handling).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _YP_DB = _rdb(Tuple{_R, Union{Nothing, _R}}[])
const _YP_LD = _YP_DB.ld

# The term the text reads as, in a new term reference.
function _yp_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
    return t
end

# A plain Julia value of the term `t` holds (see the header of this file).
function _yp_shape(ld, t::Int)
    if LK.PL_is_variable(ld, t)
        return ("v",)
    elseif LK.PL_is_integer(ld, t)
        return LK.PL_get_integer(ld, t)
    elseif LK.PL_is_float(ld, t)
        return LK.PL_get_float(ld, t)
    elseif LK.PL_is_string(ld, t)
        return ("s", LK.text_string(LK.PL_get_text(ld, t, LK.CVT_STRING)))
    elseif LK.PL_get_nil(ld, t)
        return Any[]
    elseif LK.PL_is_atom(ld, t)
        return ("a", LK.text_string(LK.PL_get_text(ld, t, LK.CVT_ATOM)))
    elseif LK.PL_is_compound(ld, t)
        h = LK.PL_new_term_ref(ld)
        tl = LK.PL_new_term_ref(ld)
        if LK.PL_get_list(ld, t, h, tl)                       # a list: its elements while it is proper, else the cells
            first = _yp_shape(ld, h)
            rest = _yp_shape(ld, tl)
            return rest isa Vector ? vcat(Any[first], rest) : ("c", "[|]", first, rest)
        end
        na = LK.PL_get_name_arity(ld, t)
        a = LK.PL_new_term_ref(ld)
        args = Any[]
        for i in 1:na[2]
            LK._PL_get_arg(ld, i, t, a)
            push!(args, _yp_shape(ld, a))
        end
        return ("c", LK.sym_text(na[1]), args...)
    end
    error("_yp_shape: unknown term")
end

# put_scalar of a scalar event: (the answer, the shape of the term or nothing, whether an exception is left pending).
function _yp_scalar(
    value::Union{Nothing, String}; tag::Union{Nothing, String}=nothing, iskey::Bool=false
)
    ld = _YP_LD
    fid = LK.PL_open_foreign_frame(ld)
    ev = LK.yaml_event(LK.YAML_SCALAR_EVENT)
    ev.value = value
    ev.tag = tag
    t = LK.PL_new_term_ref(ld)
    LK.PL_put_variable(ld, t)
    rc = LK.yaml_put_scalar(ld, t, iskey, ev)
    shape = rc ? _yp_shape(ld, t) : nothing
    pending = LK.PL_exception(ld, 0) != 0
    LK.PL_clear_exception(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, shape, pending)
end

# The shape of put_scalar's term, for the rows that must succeed.
_yp_val(value; kw...) = (r=_yp_scalar(value; kw...); r[1] ? r[2] : :failed)

@testset "yaml_put_scalar: numbers (yaml4pl.c put_scalar, is_number branch)" begin
    @test _yp_scalar("42") == (true, 42, false)
    @test _yp_scalar("-7") == (true, -7, false)
    @test _yp_scalar("0") == (true, 0, false)
    @test _yp_scalar("3.14") == (true, 3.14, false)
    @test _yp_scalar("-2.5") == (true, -2.5, false)
    # BLIND: the text forms the kernel's reader must accept (swipl reads 1e5, 0o17 and 0x1F as numbers)
    @test _yp_scalar("1e5") == (true, 100000.0, false)
    @test _yp_scalar("1.5e-3") == (true, 0.0015, false)
    @test _yp_scalar("0o17") == (true, 15, false)
    @test _yp_scalar("0x1F") == (true, 31, false)
    # a key that is a number stays a number (the key flag only chooses atom or string for TEXT)
    @test _yp_scalar("42"; iskey=true) == (true, 42, false)
    # not a number: is_number says NONE for these, so they are text
    @test _yp_val("007") == ("s", "007")
    @test _yp_val("1.") == ("s", "1.")
    @test _yp_val("-") == ("s", "-")
    @test _yp_val("1 2") == ("s", "1 2")
end

@testset "yaml_put_scalar: float overflow reads as inf (yaml4pl.c 360-365)" begin
    # the reader refuses the text or reads it as inf; either way the answer is inf and no exception is left behind
    @test _yp_scalar("1e400") == (true, Inf, false)
    @test _yp_scalar("-1e400") == (true, -Inf, false)
    @test _yp_scalar("-1.5e999") == (true, -Inf, false)
    @test _yp_scalar("2.5e999") == (true, Inf, false)
end

@testset "yaml_put_scalar: null, true, false, special floats" begin
    for s in ("null", "Null", "NULL", "~")
        @test _yp_scalar(s) == (true, ("a", "null"), false)
        @test _yp_scalar(s; iskey=true) == (true, ("a", "null"), false)
    end
    for s in ("true", "True", "TRUE")
        @test _yp_scalar(s) == (true, ("a", "true"), false)
    end
    for s in ("false", "False", "FALSE")
        @test _yp_scalar(s) == (true, ("a", "false"), false)
    end
    @test _yp_val("nulL") == ("s", "nulL")
    @test _yp_val("TRUe") == ("s", "TRUe")
    @test _yp_val("falsE") == ("s", "falsE")
    @test _yp_scalar(".inf") == (true, Inf, false)
    @test _yp_scalar(".Inf") == (true, Inf, false)
    @test _yp_scalar(".INF") == (true, Inf, false)
    @test _yp_scalar("-.inf") == (true, -Inf, false)
    @test _yp_scalar("+.inf") == (true, Inf, false)
    for s in (".nan", ".NaN", ".NAN")
        r = _yp_scalar(s)
        @test r[1] === true && r[2] isa Float64 && isnan(r[2]) && r[3] === false
    end
    @test _yp_val("-.nan") == ("s", "-.nan")
    @test _yp_val(".infx") == ("s", ".infx")
end

@testset "yaml_put_scalar: text is a string, a key an atom; UTF-8; the NUL byte survives" begin
    @test _yp_scalar("hello") == (true, ("s", "hello"), false)
    @test _yp_scalar("hello"; iskey=true) == (true, ("a", "hello"), false)
    @test _yp_scalar("") == (true, ("s", ""), false)
    @test _yp_scalar(""; iskey=true) == (true, ("a", ""), false)
    @test _yp_val("nullx"; iskey=true) == ("a", "nullx")
    @test _yp_val("café") == ("s", "café")
    @test _yp_val("café"; iskey=true) == ("a", "café")
    @test _yp_val("日本"; iskey=true) == ("a", "日本")
    # DIVERGES 14: len is the byte count, so a NUL byte inside the text is kept (BLIND: PL_get_text of a string with a NUL)
    @test _yp_val("a\0b") == ("s", "a\0b")
    # a missing value reads as ""
    @test _yp_val(nothing) == ("s", "")
end

@testset "yaml_put_scalar: a tagged scalar is tag(Tag, Text) (yaml4pl.c 346-356)" begin
    str = "tag:yaml.org,2002:str"
    @test _yp_scalar("42"; tag=str) == (true, ("c", "tag", ("a", str), ("s", "42")), false)
    @test _yp_scalar("42"; tag=str, iskey=true) ==
        (true, ("c", "tag", ("a", str), ("a", "42")), false)
    # the classifier is not applied: null stays text
    @test _yp_val("null"; tag="!foo") == ("c", "tag", ("a", "!foo"), ("s", "null"))
    @test _yp_val(""; tag="!e") == ("c", "tag", ("a", "!e"), ("s", ""))
    # DIVERGES 14: the value is UTF-8 text
    @test _yp_val("é"; tag="!u") == ("c", "tag", ("a", "!u"), ("s", "é"))
    # DIVERGES 15: the tag is read as ISO Latin-1 bytes and ends at the first NUL
    @test _yp_val("x"; tag="!é") == ("c", "tag", ("a", "!Ã©"), ("s", "x"))
    @test _yp_val("x"; tag="ab\0cd") == ("c", "tag", ("a", "ab"), ("s", "x"))
end

@testset "yaml_put_scalar overwrites the term it is given (tag branch: PL_put_functor)" begin
    ld = _YP_LD
    fid = LK.PL_open_foreign_frame(ld)
    ev = LK.yaml_event(LK.YAML_SCALAR_EVENT)
    ev.value = "x"
    ev.tag = "!t"
    t = _yp_term(ld, "foo")
    @test LK.yaml_put_scalar(ld, t, false, ev) === true
    @test _yp_shape(ld, t) == ("c", "tag", ("a", "!t"), ("s", "x"))
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "yaml_create_mapping / yaml_create_sequence and the two readers (yaml4pl.c 562-610)" begin
    ld = _YP_LD
    fid = LK.PL_open_foreign_frame(ld)
    for (create, getter, name) in
        ((LK.yaml_create_mapping, LK.yaml_get_mapping_mapping, "mapping"),
        (LK.yaml_create_sequence, LK.yaml_get_sequence_list, "sequence"))
        plain = ("c", name, ("v",), ("v",), ("v",))
        # no tag: name(_, _, _)
        t = LK.PL_new_term_ref(ld)
        @test create(ld, t, LK.yaml_event(LK.YAML_NO_EVENT)) === true
        @test _yp_shape(ld, t) == plain
        # C's PL_put_functor overwrites whatever `t` held
        t0 = _yp_term(ld, "foo")
        @test create(ld, t0, LK.yaml_event(LK.YAML_NO_EVENT)) === true
        @test _yp_shape(ld, t0) == plain
        # a tag: tag(Tag, name(_, _, _)); the event type does not matter, the tag field does
        ev = LK.yaml_event(LK.YAML_NO_EVENT)
        ev.tag = "!t"
        t2 = LK.PL_new_term_ref(ld)
        @test create(ld, t2, ev) === true
        @test _yp_shape(ld, t2) == ("c", "tag", ("a", "!t"), plain)
        # DIVERGES 15: Latin-1 and the first NUL
        ev.tag = "!é\0z"
        t3 = LK.PL_new_term_ref(ld)
        @test create(ld, t3, ev) === true
        @test _yp_shape(ld, t3) == ("c", "tag", ("a", "!Ã©"), plain)
        # the reader finds ARGUMENT 1 itself (not a copy, not argument 2 or 3): binding it changes the term
        for (term, tagged) in ((t, false), (t2, true))
            r = LK.PL_new_term_ref(ld)
            LK.PL_put_term(ld, r, term)
            @test getter(ld, r) === true
            @test LK.PL_unify(ld, r, _yp_term(ld, "[x]")) === true
            @test _yp_shape(ld, term) ==
                (
                if tagged
                    ("c", "tag", ("a", "!t"), ("c", name, [("a", "x")], ("v",), ("v",)))
                else
                    ("c", name, [("a", "x")], ("v",), ("v",))
                end
            )
        end
    end
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "yaml_push, yaml_pop (yaml4pl.c push, pop)" begin
    stack = Ref{Union{Nothing, LK.yaml_node}}(nothing)
    out = LK.yaml_node(nothing, 0, 0, 0)
    @test LK.yaml_pop(stack, out) === false                      # the empty stack: C's assert(0) branch, answered false
    @test (out.type, out.key, out.doc) == (0, 0, 0)
    old = LK.yaml_node(nothing, LK.YAML_NODE_SEQUENCE, 3, 4)
    n1 = LK.yaml_push(stack, old)
    @test n1 !== old                                             # a copy
    @test (n1.type, n1.key, n1.doc) == (LK.YAML_NODE_SEQUENCE, 3, 4)
    @test n1.parent === nothing && stack[] === n1
    old.key = 99                                                 # the copy does not follow `old`
    @test n1.key == 3
    old.type = LK.YAML_NODE_MAPPING
    old.key = 5
    old.doc = 6
    n2 = LK.yaml_push(stack, old)
    @test n2.parent === n1 && stack[] === n2                     # the parent is the old top
    @test (n2.type, n2.key, n2.doc) == (LK.YAML_NODE_MAPPING, 5, 6)
    @test LK.yaml_pop(stack, out) === true
    @test (out.type, out.key, out.doc) == (LK.YAML_NODE_MAPPING, 5, 6)
    @test out.parent === n1                                      # *old = *n: the parent comes along
    @test stack[] === n1
    @test LK.yaml_pop(stack, out) === true
    @test (out.type, out.key, out.doc) == (LK.YAML_NODE_SEQUENCE, 3, 4)
    @test out.parent === nothing && stack[] === nothing
    @test LK.yaml_pop(stack, out) === false
end

@testset "yaml_extend (yaml4pl.c extend)" begin
    ld = _YP_LD
    fid = LK.PL_open_foreign_frame(ld)
    tmp = LK.PL_new_term_ref(ld)

    # N_TOP: unify the document with the value
    d = LK.PL_new_term_ref(ld)
    top = LK.yaml_node(nothing, LK.YAML_NODE_TOP, 0, d)
    @test LK.yaml_extend(ld, top, tmp, _yp_term(ld, "5")) === true
    @test _yp_shape(ld, d) == 5
    @test LK.yaml_extend(ld, top, tmp, _yp_term(ld, "6")) === false      # a second value of another content does not unify

    # N_SEQUENCE: each value is appended to the list; the node's `doc` is the open tail
    head = LK.PL_new_term_ref(ld)
    doc = LK.PL_new_term_ref(ld)
    LK.PL_put_term(ld, doc, head)
    seq = LK.yaml_node(nothing, LK.YAML_NODE_SEQUENCE, 0, doc)
    for v in ("1", "foo", "bar")
        @test LK.yaml_extend(ld, seq, tmp, _yp_term(ld, v)) === true
    end
    @test seq.key == 0 && seq.doc == doc                         # the reference is kept; its slot became the tail
    @test LK.PL_unify_nil(ld, seq.doc) === true
    @test _yp_shape(ld, head) == Any[1, ("a", "foo"), ("a", "bar")]
    # the list is closed: a further value does not fit
    @test LK.yaml_extend(ld, seq, tmp, _yp_term(ld, "9")) === false
    # a doc that is no list
    bad = LK.yaml_node(nothing, LK.YAML_NODE_SEQUENCE, 0, _yp_term(ld, "foo"))
    @test LK.yaml_extend(ld, bad, tmp, _yp_term(ld, "1")) === false

    # N_MAPPING: the first value is held as the key, the second completes Key=Value
    mhead = LK.PL_new_term_ref(ld)
    mdoc = LK.PL_new_term_ref(ld)
    LK.PL_put_term(ld, mdoc, mhead)
    map = LK.yaml_node(nothing, LK.YAML_NODE_MAPPING, 0, mdoc)
    k1 = _yp_term(ld, "a")
    @test LK.yaml_extend(ld, map, tmp, k1) === true
    @test map.key == k1                                          # held, nothing added to the list yet
    @test _yp_shape(ld, mhead) == ("v",)
    @test LK.yaml_extend(ld, map, tmp, _yp_term(ld, "1")) === true
    @test map.key == 0                                           # the key is consumed
    @test LK.yaml_extend(ld, map, tmp, _yp_term(ld, "b")) === true
    @test LK.yaml_extend(ld, map, tmp, _yp_term(ld, "two")) === true
    @test map.key == 0
    @test LK.PL_unify_nil(ld, map.doc) === true
    @test _yp_shape(ld, mhead) ==
        Any[("c", "=", ("a", "a"), 1), ("c", "=", ("a", "b"), ("a", "two"))]

    # a mapping whose doc is no list: the pair is refused and the key is gone all the same (C resets it before the unify)
    mbad = LK.yaml_node(
        nothing, LK.YAML_NODE_MAPPING, _yp_term(ld, "k"), _yp_term(ld, "foo")
    )
    @test LK.yaml_extend(ld, mbad, LK.PL_new_term_ref(ld), _yp_term(ld, "v")) === false
    @test mbad.key == 0

    # an unknown node type: C's assert(0) branch, answered false
    @test LK.yaml_extend(ld, LK.yaml_node(nothing, 7, 0, d), tmp, _yp_term(ld, "1")) ===
        false
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "term refs: extend leaves none behind in the mapping pair case" begin
    ld = _YP_LD
    fid = LK.PL_open_foreign_frame(ld)
    mhead = LK.PL_new_term_ref(ld)
    mdoc = LK.PL_new_term_ref(ld)
    LK.PL_put_term(ld, mdoc, mhead)
    tmp = LK.PL_new_term_ref(ld)
    map = LK.yaml_node(nothing, LK.YAML_NODE_MAPPING, _yp_term(ld, "k"), mdoc)
    v = _yp_term(ld, "7")
    next = LK.PL_new_term_ref(ld)                                 # the next reference number before and after
    @test LK.yaml_extend(ld, map, tmp, v) === true
    after = LK.PL_new_term_ref(ld)
    @test after == next + 1                                       # the pair's reference was reset (PL_reset_term_refs)
    LK.PL_discard_foreign_frame(ld, fid)
end
