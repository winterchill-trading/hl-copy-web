# ui/ (AGENTS.md)

`copy_web_ui`: the backends (live HTTP with any method, or the mock fixtures), the wallet, the
remote-data helper, navigation, the pages and the root app.

- Do not read the DOM or the wallet at module initialisation. Read them inside an effect.
- A new endpoint needs a live call and a mock response in `dev/`, so the app runs without a server.
- Build from the repository root with `opam exec --switch 5.2.0+ox -- dune build --root .. @hl-copy-web/all`.
