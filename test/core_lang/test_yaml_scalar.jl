# ORIGINAL: YAML1 piece 1's gate - the scalar classifier of packages/yaml/yaml4pl.c (is_number, is_null, is_true, is_false, is_special_float, implicit_tag),
# src/pl-yaml.jl. NO oracle and no term layer: every expected value is read off yaml4pl.c (packages-yaml 0ce45ecf, lines 154-342) by hand, and each row
# names the branch it exercises. Nothing here has run (no Julia process was started to write this file).
# KERNEL-ONLY: the whole file (pure functions on bytes; the table rows are the same on every term type, there is none).
using Test, LogicKernel
const LK = LogicKernel

_b(s::AbstractString) = Vector{UInt8}(codeunits(s))

# (text, expected ntype, the branch of is_number)
const _NUMBER_ROWS = Tuple{String, Int, String}[
    ("0", LK.YAML_N_INT, "0 alone"),
    ("-0", LK.YAML_N_INT, "sign, then 0"),
    ("123", LK.YAML_N_INT, "[1-9] [0-9]*"),
    ("-123", LK.YAML_N_INT, "sign, digits"),
    ("-1", LK.YAML_N_INT, "sign, one digit (e-s < 3: the 0o/0x test is skipped)"),
    ("0o17", LK.YAML_N_INT, "0o octal"),
    ("0o", LK.YAML_N_NONE, "0o with no digit (e-s == 2: falls to the plain branch, '0' then 'o')"),
    ("0o8", LK.YAML_N_NONE, "0o with a non-octal digit"),
    ("0x1F", LK.YAML_N_INT, "0x hex"),
    ("0xg", LK.YAML_N_NONE, "0x with a non-hex digit"),
    ("-0x1f", LK.YAML_N_INT, "sign, 0x"),
    ("0b1", LK.YAML_N_NONE, "0b is not a YAML 1.2 core integer"),
    ("1.5", LK.YAML_N_FLOAT, "fraction"),
    ("0.5", LK.YAML_N_FLOAT, "0 then fraction"),
    ("1.", LK.YAML_N_NONE, "'1.' is refused (upstream's comment: official YAML allows it, we do not)"),
    (".5", LK.YAML_N_NONE, "no integer part"),
    ("-.5", LK.YAML_N_NONE, "sign, no integer part"),
    ("1e5", LK.YAML_N_FLOAT, "exponent"),
    ("1E+5", LK.YAML_N_FLOAT, "E and a plus sign"),
    ("1e-5", LK.YAML_N_FLOAT, "e and a minus sign"),
    ("1.5e-3", LK.YAML_N_FLOAT, "fraction and exponent"),
    ("0e0", LK.YAML_N_FLOAT, "0 then exponent"),
    ("1e", LK.YAML_N_NONE, "exponent with no digit"),
    ("1e+", LK.YAML_N_NONE, "exponent, sign, no digit"),
    ("1.e5", LK.YAML_N_NONE, "dot, no digit, exponent"),
    ("01", LK.YAML_N_NONE, "leading zero"),
    ("00", LK.YAML_N_NONE, "two zeros"),
    ("+1", LK.YAML_N_NONE, "a plus sign is not accepted"),
    ("-", LK.YAML_N_NONE, "sign only (e == s)"),
    ("", LK.YAML_N_NONE, "empty (len == 0)"),
    ("abc", LK.YAML_N_NONE, "letters"),
    ("12a", LK.YAML_N_NONE, "trailing letter"),
    ("1 ", LK.YAML_N_NONE, "trailing blank"),
    ("1_000", LK.YAML_N_NONE, "underscore"),
]

@testset "yaml_is_number (yaml4pl.c is_number)" begin
    @test !isempty(_NUMBER_ROWS)
    for (txt, want, why) in _NUMBER_ROWS
        @test LK.yaml_is_number(_b(txt)) == want         # why: row's third column
    end
    # NON-VACUITY: each class has rows (a table of one class could not tell the classes apart)
    @test count(r -> r[2] == LK.YAML_N_INT, _NUMBER_ROWS) >= 8
    @test count(r -> r[2] == LK.YAML_N_FLOAT, _NUMBER_ROWS) >= 6
    @test count(r -> r[2] == LK.YAML_N_NONE, _NUMBER_ROWS) >= 15
    # MUST-FAIL: the checker reports a wrong expectation
    @test LK.yaml_is_number(_b("12")) != LK.YAML_N_FLOAT
    @test LK.yaml_is_number(_b("1.5")) != LK.YAML_N_INT
    # a view is read like a vector (the reader hands libyaml's buffer in slices)
    @test LK.yaml_is_number(view(_b("x123y"), 2:4)) == LK.YAML_N_INT
end

@testset "yaml_is_null / yaml_is_true / yaml_is_false" begin
    for t in ("null", "Null", "NULL", "~")
        @test LK.yaml_is_null(_b(t))
    end
    for t in ("", "nULL", "nul", "nulll", "~~", "null ", "None", "NuLL")
        @test !LK.yaml_is_null(_b(t))
    end
    for t in ("true", "True", "TRUE")
        @test LK.yaml_is_true(_b(t))
        @test !LK.yaml_is_false(_b(t))
    end
    for t in ("false", "False", "FALSE")
        @test LK.yaml_is_false(_b(t))
        @test !LK.yaml_is_true(_b(t))
    end
    for t in ("", "tRUE", "tru", "yes", "on", "fAlse", "fals", "falsey")
        @test !LK.yaml_is_true(_b(t))
        @test !LK.yaml_is_false(_b(t))
    end
end

@testset "yaml_is_special_float (yaml4pl.c is_special_float)" begin
    for t in (".nan", ".NaN", ".NAN")
        v = LK.yaml_is_special_float(_b(t))
        @test v !== nothing && isnan(v)
    end
    @test LK.yaml_is_special_float(_b(".inf")) === Inf
    @test LK.yaml_is_special_float(_b(".Inf")) === Inf
    @test LK.yaml_is_special_float(_b(".INF")) === Inf
    @test LK.yaml_is_special_float(_b("+.inf")) === Inf
    @test LK.yaml_is_special_float(_b("+.INF")) === Inf
    @test LK.yaml_is_special_float(_b("-.inf")) === -Inf
    @test LK.yaml_is_special_float(_b("-.Inf")) === -Inf
    # a sign is tested after `.nan` only: a signed NaN is not special (upstream)
    @test LK.yaml_is_special_float(_b("+.nan")) === nothing
    @test LK.yaml_is_special_float(_b("-.nan")) === nothing
    for t in ("", "-", "+", "inf", ".infx", ".Nan", ".iNf", "--.inf", ".in", "1.0")
        @test LK.yaml_is_special_float(_b(t)) === nothing
    end
end

@testset "yaml_implicit_tag (yaml4pl.c implicit_tag)" begin
    for (t, want) in (
            ("12", "int"), ("-7", "int"), ("0x1f", "int"), ("1.5", "float"), ("1e3", "float"),
            ("null", "null"), ("~", "null"), ("true", "bool"), ("False", "bool"),
            (".inf", "float"), ("-.INF", "float"), (".nan", "float"),
            ("abc", nothing), ("", nothing), ("yes", nothing), ("+.nan", nothing), ("1.", nothing)
        )
        @test LK.yaml_implicit_tag(_b(t)) === want
    end
    # strlen: the text ends at the first NUL (the C argument is a NUL-terminated string)
    @test LK.yaml_implicit_tag(UInt8[UInt8('1'), UInt8('2'), 0x00, UInt8('a'), UInt8('b')]) === "int"
    @test LK.yaml_implicit_tag(UInt8[0x00, UInt8('1')]) === nothing
end
