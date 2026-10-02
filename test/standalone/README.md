# `test/standalone/` — the standalone consumer

A small client program (a few benchmark programs or a small Datalog example) that uses ONLY the
default term type and the kernel's public API. Without it "standalone" is a claim about
`Project.toml`, and the term interface rots first: whichever single client exercises it would
quietly become its definition.

Arrives with the first extracted subsystem — there is nothing for it to consume yet.
