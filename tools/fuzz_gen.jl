# ORIGINAL: the fuzzer's program generator, split from tools/fuzz.jl so a test can count what it produces (audit D-0267) — no swipl-devel counterpart.
# tools/fuzz_gen.jl — module FuzzGen: `program(seed, ncases[, pct])` = the text of one seed's program (CASES predicates
# t0..tN) and the predicate names. It needs Random only (no kernel, no oracle): tools/fuzz.jl includes it, and
# test/test_fuzz_shapes.jl counts the shapes it emits.
#
# TWO STREAMS. The generic goals (kinds 1-25) come from Xoshiro(seed) exactly as before this file existed; the SHAPE cases
# (below) come from a second stream, Xoshiro(seed xor SHAPE_SALT), and replace `pct` percent of the 40 cases. So a seed's
# remaining cases are the old ones, and `pct = 0` gives the old program byte for byte.
#
# THE SHAPE CASES aim at the class that found fuzz seed 300945 (B_ARGVAR/H_VAR link direction): a variable first met
# inside a NESTED compound of an outer one and later as a DIRECT argument of that outer one (`nd`), the reverse (`dn`), and
# both orders for different variables of one outer term (`inter`) — in a goal's body and in a clause HEAD (`fzhN(T1,T2).`,
# called with unbound arguments, which is H_VAR's write mode) — under compare/3, msort/2, sort/4, @<, ==, copy_term/2,
# term_variables/2, bagof/setof with free variables (Q4's shape), and with put_attr/3 on a variable of the terms (before the
# terms are built, or after). Each shape case line ends with a comment `%fz ctx=… shape=… shape2=… pred=… attr=… terms=T1;T2`
# that `fz_tags` reads back: ONE extractor for the generator's own count and the test's.
module FuzzGen
using Random
export program, fz_tags, av_classes, SHAPE_PCT, AV_SHAPES, AV_FAMILIES

const ATOMS = ["a", "b", "c", "[]", "'A b'", "'é'", "foo", "'\\n'"]
const FUNCS = [("f", 1), ("g", 2), ("h", 3), ("k", 1)]
const INTS = [
    "0",
    "1",
    "-1",
    "2",
    "7",
    "255",
    "9223372036854775807",
    "9223372036854775808",
    "-9223372036854775809",
    "100000000000000000000"
]
const STRS = ["\"\"", "\"a\"", "\"ab c\""]
const VARS = ["Va", "Vb", "Vc", "Vd"]   # never the goal templates' own X, Y, Z, L, R, …: a clash builds cyclic terms
# no "**", "^", "<<": a huge operand makes either engine allocate without bound (the first smoke run hung on one)
const ARITH = ["+", "-", "*", "//", "mod", "rem", "div", "/\\", "\\/", "xor"]   # infix operators; min/max/gcd are not: see ARITHF
# a shift count is small: `X >> -(2^63-1)` kills swipl's run (resource_error) and makes the kernel throw a Julia InexactError
# (`1 >> -9223372036854775808`; reported in A-0082, not fixed)
const ARITHF = ["min", "max", "gcd"]
pick(r, v) = v[rand(r, 1:length(v))]
function term(r, d)
    d <= 0 && return if rand(r) < 0.4
        pick(r, VARS)
    elseif rand(r) < 0.5
        pick(r, ATOMS)
    elseif rand(r) < 0.8
        pick(r, INTS)
    else
        pick(r, STRS)
    end
    c = rand(r)
    if c < 0.35
        return term(r, 0)
    elseif c < 0.75
        f, n = pick(r, FUNCS)
        return f * "(" * join([term(r, d - 1) for _ in 1:n], ",") * ")"
    else
        n = rand(r, 0:3)
        return "[" * join([term(r, d - 1) for _ in 1:n], ",") *
               (n > 0 && rand(r) < 0.2 ? "|" * term(r, 0) : "") * "]"
    end
end
function arith(r, d)
    (d <= 0 || rand(r) < 0.3) && return rand(r) < 0.85 ? pick(r, INTS[1:8]) : pick(r, VARS)
    rand(r) < 0.1 &&
        return pick(r, ["abs", "sign", "-", "msb", "\\"]) * "(" * arith(r, d - 1) * ")"
    rand(r) < 0.1 && return "(" * arith(r, d - 1) * " " * pick(r, [">>", "<<"]) * " " *
           string(rand(r, 0:70)) * ")"
    rand(r) < 0.2 &&
        return pick(r, ARITHF) * "(" * arith(r, d - 1) * "," * arith(r, d - 1) * ")"
    return "(" * arith(r, d - 1) * " " * pick(r, ARITH) * " " * arith(r, d - 1) * ")"
end
function goal(r)
    t1, t2, t3 = term(r, 3), term(r, 3), term(r, 2)
    kind = rand(r, 1:25)
    kind == 1 &&
        return "A = $t1, B = $t2, ( unify_with_occurs_check(A, B) -> R = yes(A,B) ; R = no )"
    kind == 2 && return "unify_with_occurs_check($t1, $t2), R = u($t1,$t2)"
    kind == 3 && return "compare(O, $t1, $t2), R = O"
    kind == 4 && return "( $t1 == $t2 -> R = eq ; $t1 \\== $t2 -> R = ne )"
    kind == 5 && return "( $t1 @< $t2 -> R = lt ; $t1 @> $t2 -> R = gt ; R = eq )"
    kind == 6 && return "V is $(arith(r, 3)), R = V"
    kind == 7 && return "( $(arith(r, 2)) =:= $(arith(r, 2)) -> R = t ; R = f )"
    kind == 8 && return "( $(arith(r, 2)) < $(arith(r, 2)) -> R = t ; R = f )"
    kind == 9 && return "copy_term($t1, C), R = C"
    kind == 10 && return "findall(X, fz_member(X, [$t1,$t2,$t3]), L), R = L"
    kind == 11 &&
        return "findall(X-Y, ( fz_member(X, [1,2,3]), fz_member(Y, [a,b]), X \\== 2 ), L), R = L"
    kind == 12 && return "( bagof(X, fz_member(X-Y, [1-a,2-b,3-a,4-Z]), L), R = b(Y,L) )"
    kind == 13 && return "setof(X-Y, fz_member(X-Y, [$t1-1,$t2-2,$t1-1,$t3-0]), L), R = L"
    kind == 14 && return "msort([$t1,$t2,$t3,$t1], L), R = L"
    kind == 15 && return "sort(0, @>=, [$t3,$t1,$t2,$t1], L), R = L"
    kind == 16 && return "term_variables(f($t1,$t2,$t3), Vs), length(Vs, N), R = N"
    kind == 17 && return "T = $t1, ( compound(T) -> T =.. L, R = L ; R = atomic_or_var )"
    kind == 18 && return "functor($t1, N, A), R = N/A"
    kind == 19 &&
        return "assertz(q($t1)), assertz(q($t2)), asserta(q($t3)), findall(Q, q(Q), L), R = L"
    kind == 21 &&
        return "sort(1, @<, [k($t1, a), k($t2, b), k($t3, c), k($t1, d)], L), R = L"
    kind == 22 && return "sort(2, @>=, [k(a, $t1), k(b, $t2), k(c, $t3)], L), R = L"
    kind == 23 && return "T = $t1, ( acyclic_term(T) -> R = y ; R = n )"
    kind == 24 && return "( cyclic_term($t1) -> R = c ; R = a )"
    kind == 25 &&
        return "retractall(q(_)), assertz(q($t1)), assertz(q($t2)), asserta(q($t3)), retractall(q(f(_))), findall(Q, q(Q), L), R = L"
    return "( length(L, N), N >= 2 -> R = L-N ; R = no )"   # once: length/2 enumerates forever
end
"""
`program(seed, ncases, pct = SHAPE_PCT)` — the program text and the names t0..t(ncases-1). `pct` percent of the cases (drawn
from the second stream) are shape cases (`shape_case`); `pct = 0` is the generic program only.
"""
function program(seed, ncases, pct=SHAPE_PCT)
    r = Xoshiro(seed)
    r2 = Xoshiro(seed ⊻ SHAPE_SALT)
    io = IOBuffer()
    println(io, ":- dynamic q/1.")
    println(
        io,
        "fz_member(X, [X|_]).\nfz_member(X, [_|T]) :- fz_member(X, T).\nfz_rev([], A, A).\nfz_rev([H|T], A, R) :- fz_rev(T, [H|A], R)."
    )
    names = String[]
    for i in 0:(ncases - 1)
        push!(names, "t$i")
        g = goal(r)                                   # always drawn: the generic stream is the old one
        if rand(r2, 1:100) <= pct
            pre, g, tag = shape_case(r2, i)
            print(io, pre)
            println(io, "t$i(R) :- catch((", g, "), E, R = ex(E)).  ", tag)
        else
            println(io, "t$i(R) :- catch((", g, "), E, R = ex(E)).")
        end
    end
    return String(take!(io)), names
end

# ── the shape cases (audit D-0267) ──────────────────────────────────────────────────────────────
const SHAPE_PCT = 25                    # percent of the 40 cases of a seed
const SHAPE_SALT = 0x5a17f00d00c0ffee   # the second stream's seed offset
"nd: nested first, direct later; dn: direct first, nested later; inter: both orders, for two variables of one term."
const AV_SHAPES = ["nd", "dn", "inter"]
const AV_FAMILIES = [
    "compare",
    "compare_vars",
    "msort",
    "sort4",
    "order",
    "eq",
    "copy_term",
    "term_variables",
    "bagof",
    "setof"
]
# bagof/setof unify the witnesses of two solutions: two attributed variables would call a hook the program does not define
const AV_ATTR_FAMILIES = filter(f -> f ∉ ("bagof", "setof"), AV_FAMILIES)
const AV_ORDS = ["@<", "@>", "@=<", "@>="]

"A variable wrapped one level (or two) deep: the nested occurrence."
function av_wrap(r, v)
    w = rand(r, 1:6)
    w == 1 && return "k($v)"
    w == 2 && return "g($v,$(pick(r, ["a", "b", "1"])))"
    w == 3 && return "g($(pick(r, ["a", "c", "2"])),$v)"
    w == 4 && return "[$v]"
    w == 5 && return "h(a,$v,b)"
    return "k(g($v,c))"
end

"A term of the given shape: the outer compound's arguments, a filler atom now and then between them."
function av_term(r, shape)
    nv = shape == "inter" ? rand(r, 2:3) : rand(r, 1:3)
    vs = shuffle(r, VARS)[1:nv]
    nested = [av_wrap(r, v) for v in vs]
    direct = [v for v in vs if rand(r) < 0.6]
    isempty(direct) && (direct = [vs[end]])
    shuffle!(r, direct)
    args = if shape == "nd"
        vcat(nested, direct)
    elseif shape == "dn"
        vcat(direct, nested)
    else   # v1 nested then direct, v2 direct then nested (the seed's `f(g(Vb), g(Va), Va)` is the first half)
        a = [nested[1], vs[2], vs[1], nested[2]]
        nv == 3 ? vcat(a, [nested[3], vs[3]]) : a
    end
    out = String[]
    for a in args
        rand(r) < 0.25 && push!(out, pick(r, ["a", "b", "0", "[]"]))
        push!(out, a)
    end
    return if rand(r) < 0.2
        "[" * join(out, ",") * "]"
    else
        pick(r, ["f", "g", "h", "k"]) * "(" * join(out, ",") * ")"
    end
end

"The goal of one family over the two term expressions e1 and e2 (inline terms, or the head clause's T1 and T2)."
function av_family(fam, e1, e2, ord)
    fam == "compare" && return "compare(O, $e1, $e2), R = O"
    fam == "compare_vars" &&
        return "T = $e1-$e2, term_variables(T, Vs), ( Vs = [A,B|_] -> compare(O, A, B) ; O = none ), R = T-O"
    fam == "msort" && return "msort([$e1,$e2,$e1], L), R = L"
    fam == "sort4" && return "sort(0, $ord, [$e1,$e2,$e1], L), R = L"
    fam == "order" &&
        return "( $e1 @< $e2 -> R = lt ; $e1 @> $e2 -> R = gt ; R = eq )"
    fam == "eq" && return "( $e1 == $e2 -> R = eq ; $e1 == $e1 -> R = self ; R = ne )"
    fam == "copy_term" && return "copy_term($e1-$e2, C), R = C"
    fam == "term_variables" && return "term_variables($e1-$e2, Vs), R = Vs-$e1"
    fam == "bagof" &&
        return "bagof(X, fz_member(X-Y, [1-$e1,2-$e2,3-$e1]), L), R = b(Y,L)"
    fam == "setof" &&
        return "setof(X, Y^fz_member(X-Y, [$e1-1,$e2-2,$e1-3]), L), R = s(L)"
    error("unknown family $fam")
end

"""
One shape case: `(clauses before the tI clause, the goal, the comment tag)`. The terms sit in the goal (ctx=goal) or in the
head of `fzhI(T1,T2).` that the goal calls with unbound arguments (ctx=head: H_VAR in write mode). attr=before: a variable
of the terms gets put_attr/3 before they are built; mid: after they are built (T1, T2); head: after the head call.
"""
function shape_case(r, i)
    s1, s2 = pick(r, AV_SHAPES), pick(r, AV_SHAPES)
    t1, t2 = av_term(r, s1), av_term(r, s2)
    fam = pick(r, AV_FAMILIES)
    ctx = rand(r) < 0.4 ? "head" : "goal"
    attr = fam in AV_ATTR_FAMILIES && rand(r) < 0.35 ? true : false
    ord = pick(r, AV_ORDS)
    pre = ""
    e1, e2, lead, mode = t1, t2, "", "none"
    if ctx == "head"
        pre = "fzh$i($t1,$t2).\n"
        e1, e2, lead = "T1", "T2", "fzh$i(T1,T2), "
        if attr
            lead *= "term_variables(T1-T2, [P|_]), put_attr(P, fz, 1), "
            mode = "head"
        end
    elseif attr
        vs = unique([m.match for m in eachmatch(r"V[a-d]", t1 * t2)])
        put = "put_attr($(pick(r, vs)), fz, 1), "
        if rand(r) < 0.5
            lead, mode = put, "before"
        else
            lead, mode = "T1 = $t1, T2 = $t2, " * put, "mid"
            e1, e2 = "T1", "T2"
        end
    end
    g = lead * av_family(fam, e1, e2, ord)
    tag = "%fz ctx=$ctx shape=$s1 shape2=$s2 pred=$fam attr=$mode ord=$(fam == "sort4" ? ord : "-") terms=$t1;$t2"
    return pre, g, tag
end

# ── the extractor: one reader of the tags, for the generator's count and the test's ────────────
"A parsed AV term (variables `V…`, atoms/integers, `name(args)`, `[args]`): (:var, name) | (:atom, text) | (:cmp, name, args) | (:list, args)."
function av_parse(s::AbstractString)
    pos = 1
    function arglist(close)
        args = Any[]
        while true
            push!(args, node())
            c = s[pos]
            pos += 1
            c == close && return args
            c == ',' || error("av_parse: expected , or $close at $pos in $s")
        end
    end
    function node()
        if s[pos] == '['
            pos += 1
            s[pos] == ']' && (pos += 1; return (:atom, "[]"))
            return (:list, arglist(']'))
        end
        m = match(r"^[A-Za-z0-9_]+", SubString(s, pos))
        m === nothing && error("av_parse: no token at $pos in $s")
        name = m.match
        pos += length(name)
        if pos <= lastindex(s) && s[pos] == '('
            pos += 1
            return (:cmp, name, arglist(')'))
        end
        return isuppercase(name[1]) ? (:var, name) : (:atom, name)
    end
    t = node()
    pos > lastindex(s) || error("av_parse: trailing text at $pos in $s")
    return t
end
av_occurs(n, v) =
    if n[1] === :var
        n[2] == v
    elseif n[1] === :atom
        false
    else
        any(a -> av_occurs(a, v), n[end])
    end

"""
The classes the OUTER compound of a term has: \"nd\" if some variable occurs first inside a nested argument and later as a direct
argument, \"dn\" if first direct and later nested. (A list's elements are its arguments.)
"""
function av_classes(term::AbstractString)::Set{String}
    n = av_parse(term)
    out = Set{String}()
    n[1] in (:cmp, :list) || return out
    args = n[end]
    for (j, a) in enumerate(args)
        a[1] === :var || continue
        for (i, b) in enumerate(args)
            b[1] in (:cmp, :list) && av_occurs(b, a[2]) && push!(out, i < j ? "nd" : "dn")
        end
    end
    return out
end

"""
Every shape case of a program text, as named tuples, read from the `%fz` comments. A tag whose claim the program does
not bear out (the terms are not in the goal, or in the `fzhI` head; a declared shape the term does not have; the family's
predicate absent from the goal) has `ok = false`.
"""
function fz_tags(text::AbstractString)
    lines = split(text, '\n')
    heads = Dict(
        m.captures[1] => m.match for l in lines for
        m in (match(r"^(fzh\d+)\(.*\)\.$", l),) if m !== nothing
    )
    out = NamedTuple[]
    for l in lines
        m = match(r"^(t\d+)\(R\) :- (.*)  %fz (.*)$", l)
        m === nothing && continue
        kv = Dict(
            String(a) => String(b) for
            (a, b) in (split(x, '='; limit=2) for x in split(m.captures[3], ' '))
        )
        t1, t2 = String.(split(kv["terms"], ';'))
        cs1, cs2 = av_classes(t1), av_classes(t2)
        shape_ok(sh, cs) =
            sh == "inter" ? cs == Set(["nd", "dn"]) || (cs ⊇ Set(["nd", "dn"])) : sh in cs
        body = m.captures[2]
        where_ = kv["ctx"] == "head" ? get(heads, "fzh" * m.captures[1][2:end], "") : body
        pred = Dict(
            "compare" => "compare(O",
            "compare_vars" => "compare(O, A, B)",
            "msort" => "msort(",
            "sort4" => "sort(0, " * kv["ord"],
            "order" => " @< ",
            "eq" => " == ",
            "copy_term" => "copy_term(",
            "term_variables" => "term_variables(",
            "bagof" => "bagof(",
            "setof" => "setof("
        )[kv["pred"]]
        ok =
            occursin(t1 * "," * t2, where_) ||
            (kv["ctx"] == "goal" && occursin(t1, where_) && occursin(t2, where_))
        ok &= shape_ok(kv["shape"], cs1) && shape_ok(kv["shape2"], cs2)
        ok &= occursin(pred, body) && (kv["attr"] == "none") == !occursin("put_attr(", body)
        push!(
            out,
            (;
                case=m.captures[1],
                ctx=kv["ctx"],
                shape=kv["shape"],
                shape2=kv["shape2"],
                pred=kv["pred"],
                attr=kv["attr"],
                ok
            )
        )
    end
    return out
end

end # module FuzzGen
