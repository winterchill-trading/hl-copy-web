# .github/ (AGENTS.md)

`workflows/ci.yml` runs `ox-setup` (which installs `bonsai_web` and caches the switch), `dune build`,
`dune test` with Node for the smoke tests, and calls the `obj-magic` reusable workflow from `infra`.

- The `bonsai_web` install is part of the opam dependencies of `hl-copy-web.opam`; keep it there, not
  in a CI step.
- Keep the `concurrency` block.
- Check a run with one `gh run list --limit 1`, and at most one `gh run watch <id> --exit-status`.
