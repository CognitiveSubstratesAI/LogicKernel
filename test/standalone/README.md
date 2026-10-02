# `test/standalone/` — the standalone consumer

A small client program (a few benchmark programs or a small Datalog example) that uses ONLY the
default term type and the kernel's public API. Without it "standalone" is a claim about
`Project.toml`, and the term interface rots first: Core would be its only exerciser, and Core's
`Atom` would quietly become the interface.

Arrives with the first extracted subsystem — there is nothing for it to consume yet.
