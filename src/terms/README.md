# `src/terms/` — the term interface and the default term type

**First subsystem to land; everything else depends on it.**

The term interface was settled on 2026-10-02 and it is **not** Prolog's `functor`/`arity` shape. A
compound term is a **sequence of children with the head as child 1**, because a head may itself be a
variable or a compound (`($h a b)`, `((curry f) x)`). Prolog's `f(a, b)` is `[f, a, b]`.

| function | returns |
|---|---|
| `kind(t)` | `VAR`, `SYM`, `GND` or `EXPR` |
| `nchildren(t)`, `child(t, i)` | `Int`, a term (the head is `child(t, 1)`) |
| `sym_key(t)` | `UInt64` (interned id) |
| `var_key(t)` | `UInt64` (variable identity) |
| `gnd_key(t)` | `UInt64`, or `nothing` = WILDCARD (never a shared bucket) |
| `gnd_equal(a, b)` | strict `Bool` — the ONLY place a grounded comparison happens |
| `mk_var(T, key)`, `mk_expr(T, children)` | a term — constructors, because renaming, substitution and answer tries build terms |
| `is_ground(t)` | `Bool`, optional (computed by default) |

Rules: every function returns a **concrete** type and is defined on the **concrete** term types;
the standard order of terms gets no entry (derive it from `kind` + the keys). Two implementations,
one conformance suite (`test/conformance/`): the default term type here is the reference, MeTTaCore's
`Atom` is the second.

Entry file when it lands: `terms.jl`.
