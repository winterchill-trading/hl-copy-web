# smoke/ (AGENTS.md)

Node smoke tests of the compiled app with a fake DOM (`fake_dom.js`) and a fake wallet.

- `run.js` walks every page on mock data (about a second). `live.js` runs the app against a fake
  `hl-copy-api` and checks method, path, bearer token, body and reply handling.
- `live.js` also runs against a real `hl-copy-api`: `node smoke/live.js <main.bc.js> . <API URL>`.
- `leader_live.js` opens one leader page against a real `hl-copy-api` and checks the
  leader-scoring sections: `node smoke/leader_live.js <main.bc.js> . <API URL> [address]`.
- The fake DOM matches one simple selector at a time (`#id`, `tag`, `.class`); descend with
  repeated `querySelector` calls instead of descendant selectors.
- Node 22 or later is required for the global `WebSocket`.
