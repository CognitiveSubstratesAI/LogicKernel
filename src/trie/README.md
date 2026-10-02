# `src/trie/` — term tries

Tries keyed on TERM structure (not bytes): symbols, grounded keys, expressions by arity, and
variables by FIRST-OCCURRENCE index, so two variants of a term reach the same node. They are the
answer and variant tables that tabling stores into, and they give duplicate detection structurally.

Port class: **as code** (SWI-Prolog `src/pl-trie.c`).

Depends on: `terms`, `unify`. Entry file when it lands: `trie.jl`.
