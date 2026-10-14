# AGENTS.md (hl-copy-web)

## Purpose

The browser frontend of the copy-trading platform, a Bonsai app compiled with js_of_ocaml, and the
owner of `Api_types`, the wire types of the HTTP API that `hl-copy-api` serves. The app runs on mock
data out of the box, so every page can be walked without a server or a wallet extension.

Workspace-wide rules, the repository map and the CI model are in
`../oxcaml-claude-skills/AGENTS.md`. Read that first.

## Layout

| Path | Holds |
| --- | --- |
| `api/` | `hl-copy-api-types` (the `Api_types` library): request and reply types, JSON codecs, EIP-712 typed data ([api/AGENTS.md](api/AGENTS.md)) |
| `model/` | `copy_web_model`: routes, formatting, table sort and filter, chart geometry, form validation, mock account; tested natively ([model/AGENTS.md](model/AGENTS.md)) |
| `ethereum/` | `ethereum`: the generated binding of `window.ethereum` and deferred wrappers ([ethereum/AGENTS.md](ethereum/AGENTS.md)) |
| `ui/` | `copy_web_ui`: backends (live HTTP or mock), wallet, pages, the app ([ui/AGENTS.md](ui/AGENTS.md)) |
| `bin/` | `main.bc.js`, which mounts the app on `#app` |
| `static/` | `index.html` and the stylesheet (light and dark) |
| `dev/` | Mock API responses used when the app runs without a server ([dev/AGENTS.md](dev/AGENTS.md)) |
| `smoke/` | Node smoke tests with a fake DOM and a fake wallet ([smoke/AGENTS.md](smoke/AGENTS.md)) |
| `scripts/` | `dev.sh` (build, assemble `_site/`, serve on port 8000) and the fixture generator |
| `.github/` | CI workflow ([.github/AGENTS.md](.github/AGENTS.md)) |
| `README.md` | Pages, flows, `Api_types` conventions, tests |

## Build and test

From this repository, inside the workspace:

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @hl-copy-web/all @hl-copy-web/runtest
```

For parallel work give the build its own directory, relative to the workspace root:
`DUNE_BUILD_DIR=_build-hl-copy-web` in front of the same command.

Standalone: `opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`,
then `opam install . --deps-only --with-test` and `dune build && dune test`. The smoke tests need
Node 22 or later on `PATH`.

Run the app: `scripts/dev.sh` (add `-r -p 9000` for a release build on another port).

Format only this repository, after the tests pass:
`dune build --root .. @hl-copy-web/fmt --auto-promote`. Never run `dune fmt` at the workspace root.

## Conventions

- Core style: `open! Core`, an `.mli` for every module, labelled arguments, expect tests.
- `api/api_types.mli` is the contract with `hl-copy-api`. A change there is a change to both
  repositories; land the server side first or in the same session, and keep the expect tests of
  every fixture in `dev/` passing.
- Timestamps are `Time_ms.t` (a float of milliseconds encoded as a JSON integer). Money is a USD
  float. `Address.t` is validated and lowercased.
- Records accept unknown fields and optional fields accept `null`. Keep both when you add a field.
- Pure logic goes in `model/` and is tested natively; `ui/` holds only the wiring.
- Odoc on every public value.

## Dependencies and dependents

- `hl-copy-api-types` depends only on `core`, `ppx_jane`, `ppx_yojson_conv` and `yojson`, so the
  server links it without the web stack.
- `hl-copy-web` depends on `bonsai_web` (v0.18 preview, installed by `ox-setup`, not in the base
  image) and on `hl-copy-api-types` at the same version.
- Used by `../hl-copy-api`, which pins `hl-copy-api-types` from this repository, and whose live
  smoke test (`smoke/live.js`) runs this app against it.
- Spec: `../specs/repos/hl-copy-web.md`; the frontend decision is `../specs/adr/0008-bonsai-web-frontend.md`.

## CI

`.github/workflows/ci.yml` runs `ox-setup` (which installs and caches `bonsai_web` with the other
dependencies, and a guarded step covers an older restored switch), then `dune build`, `dune test`
and the smoke tests with Node. `obj-magic` calls the shared reusable workflow from `infra`.

Check a run with one `gh run list --limit 1` and at most one
`gh run watch <id> --exit-status`. Never poll in a loop.

## Pitfalls

- Bonsai here is the v0.18 preview. `let%arr` and `let%sub` need `bonsai.ppx_bonsai`, which
  `ppx_jane` does not include. Use `let%map` with `Bonsai.Let_syntax`.
- `hl-copy-web.opam` keeps dune below 3.23. Newer dune breaks `bonsai_web`'s CSS inliner, and a
  fresh switch would otherwise pick it.
- `Bonsai_web` exports a `View` module that shadows a local one; the shared helpers are named
  `Widgets` for that reason.
- js_of_ocaml `int` is 32 bits. Keep millisecond timestamps as floats.
- `Async_js.Http` only does GET and POST. PATCH and DELETE need a raw XMLHttpRequest.
- Read `window.ethereum` inside `Effect.of_thunk`, never at render time.
- The root `dune` file silences a link-time warning about OCaml 5 effect handlers in a library the
  app never runs. Do not widen that flag.

## Where to read more

- `README.md`, `../specs/repos/hl-copy-web.md`, `../specs/design/copytrading.md`
- `../oxcaml-claude-skills/AGENTS.md`, `../oxcaml-claude-skills/GOTCHAS.md` (the Bonsai and copy-trading sections)
- Skill: `../oxcaml-claude-skills/skills/async-http-websocket` for the websocket client

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Point the app at a mainnet exchange, or sign an approval for any chain but the testnet.
- Publish, tag or release.
- Commit wallet keys or tokens. The dev wallet key comes from the environment only.
- Print session tokens or signatures.
