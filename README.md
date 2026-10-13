# hl-copy-web

The browser frontend of the copy-trading platform: a [Bonsai](https://github.com/janestreet/bonsai)
app written in OCaml and compiled to JavaScript with js_of_ocaml. Users connect a wallet,
browse ranked leaders, approve a trading-only Hyperliquid agent key, follow a leader with
their own scale and risk caps, and pause or stop follows from a dashboard.

The repository also owns `Api_types`, the request and response types of the HTTP API
that `hl-copy-api` serves, in a small opam package of its own (`hl-copy-api-types`) so the
server can depend on it without pulling in the web stack.

## Running it

```sh
scripts/dev.sh            # build, assemble _site/ and serve it on http://localhost:8000/
scripts/dev.sh -r -p 9000 # release build (1.6 MB of JavaScript instead of 49 MB)
```

Without a query string the app runs on mock data: every response comes from the JSON
files under [`dev/`](dev), and an in-memory account remembers agent approvals, new
follows, pauses and stops until the page reloads. Login offers a demo signer next to the
browser wallet, so every page works without a wallet extension or a server.

To talk to a running `hl-copy-api`, add `?api=<base url>`:

```text
http://localhost:8000/?api=http://localhost:8080
```

The API must allow the page's origin (CORS) and accept `PATCH` and `DELETE` on
`/follows/<id>`. Nothing in the app picks a network: the agent offer from the API carries
`hyperliquidChain` (`Testnet` for hl-sim and testnet), and the wallet signs whatever the
page shows it, so point it at a server configured for hl-sim or testnet only.

`scripts/gen-fixtures.py` regenerates `dev/` deterministically (seeded random walks,
addresses hashed from made-up labels; no real accounts).

## Pages

What a visitor sees, page by page:

- **Header.** The app name, links to Leaders and Dashboard, a badge saying "mock data" or
  the API URL, and either a "Connect wallet" button or the short address of the signed-in
  wallet with "Sign out".
- **Leaders** (`#/leaders`). A filter row (search by name or address, minimum score,
  maximum drawdown in percent, minimum trades) above a table of every ranked leader: rank,
  name and short address, a score bar out of 100, pnl, ROI, max drawdown, win rate, trade
  count, average hold time, consistency and equity. Gains are green, losses red. Clicking
  a column header sorts by it, best first, and clicking again flips the order; an arrow
  marks the sorted column. A line above the table says how many leaders match and when
  the ranking was computed.
- **Leader** (`#/leader/<address>`). The leader's name and full address with eleven
  headline figures (rank, score, equity, pnl, ROI, drawdown, win rate, trades, average
  hold, consistency, followers), a "Follow this leader" button, 24 hour, 7 day, 30 day and
  all-time pnl, and an SVG equity curve: a green line (red when the curve ends below
  where it started) over horizontal grid lines labelled in round dollar amounts, a dashed
  line at the starting equity, and dates under the first, middle and last points. Below
  it, the open positions (coin, long or short, size, entry, leverage, unrealized pnl) and
  the 25 most recent fills.
- **Follow** (`#/follow/<address>`). The leader summary, then a form: scale mode (equity
  ratio, a fixed multiplier, or a fixed USD notional per position) with its value, max
  leverage, max notional per symbol, max daily loss, minimum order notional and the coins
  to copy. Invalid fields turn red with a message under them and the button stays
  disabled. A line under the form says which agent state applies. With an approved agent
  the button just says "Follow". Otherwise it says "Review agent approval" and leads to a
  second step that prints the exact `approveAgent` EIP-712 typed data the wallet will
  sign, explains that the agent can trade but not withdraw, and offers a checkbox (on by
  default) to also approve the platform's builder fee, with that typed data shown too.
  "Sign and follow" asks the wallet for the signatures and lands on the dashboard.
- **Dashboard** (`#/dashboard`). Account address, equity, total copy pnl and how many
  follows are running; a notice when the agent is missing or its approval expired; then
  one card per follow with the leader, a running, paused or stopped badge, start time,
  attributed pnl, scale, caps and the positions it opened, with Pause, Resume and Stop
  buttons as the state allows.
- **Connect wallet** (`#/login`). One paragraph on what signing in means, "Connect wallet"
  and (with mock data) "Use demo signer", and progress or error lines underneath.

## Flows and the API

Every request path and body is a type in [`api/api_types.mli`](api/api_types.mli);
`smoke/live.js` checks each of them against a fake server.

| Step | Request | Body | Reply |
| --- | --- | --- | --- |
| Leaderboard | `GET /leaders` | | `Leaders_response` |
| Leader | `GET /leaders/<address>` | | `Leader_detail` |
| Login challenge | `POST /auth/challenge` | `Auth.Challenge_request` | `Auth.Challenge` |
| Login | `POST /auth/verify` | `Auth.Verify_request` (signature of `message` by `personal_sign`) | `Auth.Session` |
| Account | `GET /me` | | `Me` (includes `Agent_status`) |
| New agent | `POST /agent/new` | `{}` | `Agent_offer` |
| Agent approved | `POST /agent/approved` | `Agent_approval` | `Agent_status` |
| Builder fee | `POST /builder-fee` | `Builder_fee_approval` | `Agent_status` |
| Follow | `POST /follows` | `Follow_request` | `Follow` |
| Pause, resume | `PATCH /follows/<id>` | `Follow_update` | `Follow` |
| Stop | `DELETE /follows/<id>` | | `Follow` |

Everything after login sends `Authorization: Bearer <token>`. A non-2xx reply carries
`Api_error` (`{"error": "..."}`), which the page shows as `HTTP <code>: <error>`.

Wallet calls go through a [gen_js_api](https://github.com/LexiFi/gen_js_api) binding of the
EIP-1193 provider (`ethereum/eip1193.mli`, `window.ethereum`): `eth_requestAccounts`,
`personal_sign` (the challenge, hex-encoded), `eth_chainId` and `eth_signTypedData_v4`.
Wallets refuse typed data whose domain `chainId` differs from the connected chain, so the
page replaces the offer's `signature_chain_id` with the wallet's chain before signing and
sends the action back exactly as signed.

### Using `Api_types` from another repository

```sh
opam pin add hl-copy-api-types https://github.com/winterchill-trading/hl-copy-web.git
```

```lisp
(libraries hl-copy-api-types)
```

The package depends only on `core`, `ppx_jane`, `ppx_yojson_conv` and `yojson`. Two
conventions come from the browser: timestamps and nonces are `float` milliseconds
(`Time_ms`, encoded as JSON integers) because js_of_ocaml's `int` is 32 bits, and money
is USD `float` for display and form input. Records accept unknown fields, and optional
fields accept a missing field or `null`, so the server can add fields without breaking
deployed pages.

## Layout

| Directory | Library | Contents |
| --- | --- | --- |
| `api/` | `hl-copy-api-types` (`Api_types`) | Wire types, JSON codecs, EIP-712 typed data for `approveAgent` and `approveBuilderFee`, endpoint paths |
| `model/` | `copy_web_model` | Pure logic, tested natively: routes, formatting, table sort and filter, chart geometry, form validation, agent state, the mock account |
| `ethereum/` | `ethereum` | gen_js_api binding of `window.ethereum` and deferred wrappers |
| `ui/` | `copy_web_ui` | Backends (live HTTP and mock), wallet, pages, app |
| `bin/` | | `main.bc.js`, mounts the app on `#app` |
| `static/` | | `index.html` with the stylesheet (light and dark) |
| `dev/` | | Mock API responses |
| `smoke/` | | Node smoke tests with a fake DOM |

`opam install hl-copy-web` installs the built site as `share/hl-copy-web/index.html` and
`main.js`.

## Tests

`dune test` runs

- expect tests for `Api_types` (JSON shapes, typed data, every fixture decodes and round
  trips) and the model (routes, formatting, sorting and filtering, chart ticks, form
  validation, agent check, mock account);
- `smoke/run.js`: the compiled app under node with a minimal fake DOM (`smoke/fake_dom.js`)
  and a fake wallet, walking every page on mock data: 12 steps from the leaderboard
  through login, pause and stop, form validation, the typed data, signing and following
  (about a second);
- `smoke/live.js`: the same app with `?api=` against an in-memory fake of `hl-copy-api`,
  checking method, path, bearer token and body of every request, the request order of the
  approval flow, and how an error reply is shown.

Node must be on `PATH` for the smoke tests.

## CI

`.github/workflows/ci.yml` uses the org's `ox-setup` action. `bonsai_web` is not in the
OxCaml base image; it is an opam dependency of `hl-copy-web`, so the action installs it
with the other dependencies and caches the switch, and a guarded step installs it if a
restored switch predates the dependency. `actions/setup-node` provides node for the
smoke tests.

## Notes

- Bonsai here is the `v0.18~preview` release on the OxCaml switch. There is no
  `ppx_bonsai` on that switch, so the code uses `let%map` with `Bonsai.Let_syntax`
  instead of `let%arr` and `let%sub`.
- `Bonsai_web` exports a `View` module, so the shared view helpers are `Widgets`.
- Some library in the closure contains OCaml 5 effect handlers that the app never runs;
  the root `dune` file turns off js_of_ocaml's link-time warning about them.
