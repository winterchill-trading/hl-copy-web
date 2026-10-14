# smoke/ (AGENTS.md)

Node smoke tests of the compiled app with a fake DOM (`fake_dom.js`) and a fake wallet.

- `run.js` walks every page on mock data (about a second). `live.js` runs the app against a fake
  `hl-copy-api` and checks method, path, bearer token, body and reply handling.
- `live.js` also runs against a real `hl-copy-api`: `node smoke/live.js <main.bc.js> . <API URL>`.
- Node 22 or later is required for the global `WebSocket`.
