// Smoke test of the live backend: the app runs with ?api=http://api.test against an
// in-memory fake of hl-copy-api, and every request is checked against the HTTP contract
// in api/api_types.mli (methods, paths, bearer token, JSON bodies).
//
//   node live.js <path to main.bc.js> <directory holding dev/>
//
// With a third argument, the same app runs against a real hl-copy-api at that URL (on
// hl-sim or testnet), with a wallet that really signs: DEV_WALLET names hl-copy-api's
// tools/dev_wallet.exe and HL_COPY_WALLET_KEY a throwaway key (never printed). That run
// logs in, approves an agent and the builder fee, follows the first leader, pauses and
// stops, and reports every non-2xx reply as a contract mismatch. hl-copy-api's
// scripts/e2e-stack.sh runs it.
//
//   node live.js <main.bc.js> <directory holding dev/> http://localhost:8080
"use strict";
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { install, makeEvent } = require("./fake_dom.js");

const [, , appJs, root, liveApi] = process.argv;
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(root, "dev", name), "utf8"));
const API = liveApi ? liveApi.replace(/\/$/, "") : "http://api.test";
const TOKEN = "t-1";

const requests = [];
const me = { ...fixture("me.json"), agent: undefined };
delete me.agent;
let deleteAttempts = 0;

function json(status, body) { return { status, body }; }

function api(method, url, headers, body) {
  if (!url.startsWith(API)) return null;
  const p = url.slice(API.length);
  const parsed = body ? JSON.parse(body) : undefined;
  requests.push({ method, path: p, auth: headers.Authorization, body: parsed });
  const authed = headers.Authorization === "Bearer " + TOKEN;
  const need = (ok) => (authed ? ok() : json(401, { error: "no session" }));
  const follow = (id) => me.follows.find((f) => f.id === id);
  let m;
  if (method === "GET" && p === "/leaders") return json(200, fixture("leaders.json"));
  if (method === "GET" && (m = /^\/leaders\/(0x[0-9a-f]{40})$/.exec(p))) return json(200, fixture(`leaders/${m[1]}.json`));
  if (method === "POST" && p === "/auth/challenge") return json(200, { message: "sign in " + parsed.address, nonce: "n-1", expires_at: Date.now() + 300000 });
  if (method === "POST" && p === "/auth/verify") return json(200, { token: TOKEN, address: parsed.address, expires_at: Date.now() + 3600000 });
  if (method === "GET" && p === "/me") return need(() => json(200, me));
  if (method === "POST" && p === "/agent/new") return need(() => json(200, fixture("agent-offer.json")));
  if (method === "POST" && p === "/agent/approved")
    return need(() => {
      me.agent = { agent_address: parsed.approve_agent.agent_address, agent_name: parsed.approve_agent.agent_name, approved: true };
      return json(200, me.agent);
    });
  if (method === "POST" && p === "/builder-fee")
    return need(() => { me.agent.builder_fee = parsed.approve_builder_fee.max_fee_rate; return json(200, me.agent); });
  if (method === "POST" && p === "/follows")
    return need(() => {
      const f = { id: "f-" + (me.follows.length + 1), ...parsed, state: "running", created_at: Date.now(), pnl: 0, positions: [] };
      me.follows.push(f);
      return json(200, f);
    });
  if ((m = /^\/follows\/(f-\d+)$/.exec(p))) {
    const f = follow(m[1]);
    if (!f) return json(404, { error: "no such follow" });
    if (method === "PATCH") return need(() => { f.state = parsed.state; return json(200, f); });
    if (method === "DELETE")
      return need(() => {
        if (deleteAttempts++ === 0) return json(409, { error: "engine busy, retry" });
        f.state = "stopped";
        return json(200, f);
      });
  }
  return json(404, { error: `no route ${method} ${p}` });
}

// The real server: every request goes over HTTP; replies are recorded like the fake's.
async function real(method, url, headers, body) {
  if (!url.startsWith(API)) return null;
  const p = url.slice(API.length);
  const record = { method, path: p, auth: headers.Authorization, body: body ? JSON.parse(body) : undefined };
  requests.push(record);
  const r = await fetch(url, { method, headers, body: body || undefined });
  record.status = r.status;
  record.reply = await r.text();
  return { status: r.status, body: record.reply };
}

const env = install({ root, hash: "", search: "?api=" + encodeURIComponent(API), handler: liveApi ? real : api });
const { document } = env;
const print = (s) => process.stdout.write(s + "\n");
console.log = () => {};
const consoleErrors = [];
const origError = console.error;
console.error = (...a) => { consoleErrors.push(a.map(String).join(" ")); origError(...a); };

// Signs with hl-copy-api's dev_wallet (the key stays in the environment).
const devWallet = (args, input) =>
  execFileSync(process.env.DEV_WALLET, args, { input, encoding: "utf8" }).trim();
const realWallet = {
  calls: [],
  request({ method, params }) {
    this.calls.push(method);
    try {
      switch (method) {
        case "eth_requestAccounts": return Promise.resolve([devWallet(["address"])]);
        case "eth_chainId": return Promise.resolve("0x66eee");
        case "personal_sign": return Promise.resolve(devWallet(["personal-sign"], Buffer.from(params[0].slice(2), "hex")));
        case "eth_signTypedData_v4": return Promise.resolve(devWallet(["sign-typed-data"], params[1]));
        default: return Promise.reject(new Error("wallet: unsupported " + method));
      }
    } catch (e) { return Promise.reject(e); }
  },
};

window.ethereum = liveApi ? realWallet : {
  calls: [],
  request({ method, params }) {
    this.calls.push(method);
    return Promise.resolve(
      { eth_requestAccounts: ["0x00000000000000000000000000000000000000aa"], eth_chainId: "0x66eee",
        personal_sign: "0x" + "33".repeat(65), eth_signTypedData_v4: "0x" + "44".repeat(65) }[method]);
  },
};

const all = (sel) => document.querySelectorAll(sel);
const text = (el) => (el ? el.textContent : "");
const bodyText = () => text(document.body);
const byText = (sel, s) => all(sel).find((el) => text(el).trim().startsWith(s));
let n = 0;
const step = (name) => print(`ok ${++n} - ${name}`);

function fail(msg) {
  print("FAIL: " + msg);
  print("page: " + bodyText().slice(0, 1200));
  print("requests: " + JSON.stringify(requests.map((r) => `${r.method} ${r.path}`)));
  process.exit(1);
}

function waitFor(what, pred, ms = 4000) {
  return new Promise((resolve) => {
    const start = Date.now();
    const tick = () => {
      let v;
      try { v = pred(); } catch (e) { v = undefined; }
      if (v) return resolve(v);
      if (Date.now() - start > ms) fail("timed out waiting for " + what);
      setTimeout(tick, 10);
    };
    tick();
  });
}

const click = (el, what) => { if (!el) fail("nothing to click: " + what); el.dispatchEvent(makeEvent("click")); };
const last = (method, p) => [...requests].reverse().find((r) => r.method === method && r.path === p);
const expectRequest = (method, p, check = () => true) => {
  const r = last(method, p);
  if (!r) fail(`expected ${method} ${p}`);
  if (!check(r)) fail(`unexpected ${method} ${p}: ${JSON.stringify(r)}`);
  return r;
};
const bearer = (r) => r.auth === "Bearer " + TOKEN;

async function main() {
  require(path.resolve(appJs));
  const table = () => document.querySelector("#leaders-table");
  await waitFor("leaders table", () => table() && table().querySelectorAll("tr").length === 9);
  if (!bodyText().includes(API)) fail("header should name the API");
  expectRequest("GET", "/leaders");
  step("GET /leaders renders the leaderboard");

  window.location.hash = "#/login";
  await waitFor("login page", () => byText("button", "Connect wallet"));
  click(byText("button", "Connect wallet"), "connect");
  await waitFor("dashboard", () => location.hash === "#/dashboard" && document.querySelector("#follow-f-1"));
  expectRequest("POST", "/auth/challenge", (r) => r.body.address === "0x00000000000000000000000000000000000000aa");
  expectRequest("POST", "/auth/verify", (r) => r.body.nonce === "n-1" && r.body.signature.startsWith("0x3333"));
  expectRequest("GET", "/me", bearer);
  if (!bodyText().includes("You have no trading agent yet")) fail("missing-agent notice");
  step("POST /auth/challenge, POST /auth/verify, GET /me with the bearer token");

  const card = (id) => document.querySelector("#follow-" + id);
  click(card("f-1").querySelectorAll("button").find((b) => text(b) === "Pause"), "pause");
  await waitFor("paused", () => card("f-1") && text(card("f-1").querySelector("span.badge")) === "paused");
  expectRequest("PATCH", "/follows/f-1", (r) => bearer(r) && JSON.stringify(r.body) === '{"state":"paused"}');
  step("pause is PATCH /follows/f-1 {state: paused}");

  click(card("f-2").querySelectorAll("button").find((b) => text(b) === "Stop"), "stop");
  await waitFor("409 error", () => bodyText().includes("HTTP 409: engine busy, retry"));
  click(card("f-2").querySelectorAll("button").find((b) => text(b) === "Stop"), "stop again");
  await waitFor("stopped", () => card("f-2") && text(card("f-2").querySelector("span.badge")) === "stopped");
  if (bodyText().includes("HTTP 409")) fail("error should clear after success");
  expectRequest("DELETE", "/follows/f-2", (r) => bearer(r) && r.body === undefined);
  step("stop is DELETE /follows/f-2; an error reply is shown, then cleared");

  const leader = fixture("leaders.json").leaders[0].address;
  window.location.hash = "#/follow/" + leader;
  await waitFor("review button", () => byText("button", "Review agent approval") && !byText("button", "Review agent approval").disabled);
  click(byText("button", "Review agent approval"), "review");
  await waitFor("sign button", () => byText("button", "Sign and follow"));
  click(byText("button", "Sign and follow"), "sign");
  await waitFor("follow created", () => location.hash === "#/dashboard" && card("f-3"));
  expectRequest("POST", "/agent/new", bearer);
  expectRequest("POST", "/agent/approved", (r) => bearer(r) && r.body.approve_agent.signature_chain_id === "0x66eee" && r.body.signature.startsWith("0x4444"));
  expectRequest("POST", "/builder-fee", (r) => bearer(r) && r.body.approve_builder_fee.max_fee_rate === "0.01%");
  // immediate execution sends no algo at all: the request is the same as before algorithms
  expectRequest("POST", "/follows", (r) => bearer(r) && r.body.leader === leader && r.body.scale.kind === "equity_ratio" && r.body.caps.max_leverage === 3 && !("algo" in r.body));
  const order = requests.map((r) => `${r.method} ${r.path}`).filter((s) => /agent|builder|POST \/follows/.test(s));
  if (order.join(",") !== "POST /agent/new,POST /agent/approved,POST /builder-fee,POST /follows") fail("order " + order);
  step("follow: POST /agent/new, /agent/approved, /builder-fee, then /follows");

  if (consoleErrors.length) fail("console errors: " + consoleErrors.join(" | "));
  print(`all ${n} steps passed; ${requests.length} API requests`);
  process.exit(0);
}

// Against the real API: a fresh wallet, so no agent and no follows to begin with.
async function mainReal() {
  if (!process.env.DEV_WALLET || !process.env.HL_COPY_WALLET_KEY) fail("set DEV_WALLET and HL_COPY_WALLET_KEY");
  const wallet = devWallet(["address"]);
  const leaders = (await (await fetch(API + "/leaders")).json()).leaders;
  if (!leaders.length) fail("the API lists no leaders");
  require(path.resolve(appJs));
  const table = () => document.querySelector("#leaders-table");
  await waitFor("leaders table", () => table() && table().querySelectorAll("tr").length === leaders.length + 1, 10000);
  expectRequest("GET", "/leaders", (r) => r.status === 200);
  step(`GET /leaders renders all ${leaders.length} leaders of the real API`);

  window.location.hash = "#/login";
  await waitFor("login page", () => byText("button", "Connect wallet"));
  click(byText("button", "Connect wallet"), "connect");
  await waitFor("dashboard", () => location.hash === "#/dashboard" && bodyText().includes("You have no trading agent yet"), 10000);
  expectRequest("POST", "/auth/verify", (r) => r.status === 200 && r.body.address === wallet);
  expectRequest("GET", "/me", (r) => r.status === 200 && r.auth && r.auth.startsWith("Bearer "));
  step("wallet login: the real server accepts the personal_sign of its challenge");

  const leader = leaders[0].address;
  window.location.hash = "#/follow/" + leader;
  await waitFor("review button", () => byText("button", "Review agent approval") && !byText("button", "Review agent approval").disabled, 10000);
  click(byText("button", "Review agent approval"), "review");
  await waitFor("sign button", () => byText("button", "Sign and follow"));
  click(byText("button", "Sign and follow"), "sign");
  const followed = () => requests.find((r) => r.method === "POST" && r.path === "/follows" && r.status);
  await waitFor("POST /follows answered", followed, 15000);
  if (followed().status >= 300) fail("POST /follows: " + followed().status + " " + followed().reply);
  const id = JSON.parse(followed().reply).id;
  const card = () => document.querySelector("#follow-" + id);
  await waitFor("follow card", () => location.hash === "#/dashboard" && card(), 10000);
  for (const [m, p] of [["POST", "/agent/new"], ["POST", "/agent/approved"], ["POST", "/builder-fee"]])
    expectRequest(m, p, (r) => r.status === 200);
  step(`follow: agent and builder fee approved on the exchange, follow ${id} created`);

  click(card().querySelectorAll("button").find((b) => text(b) === "Pause"), "pause");
  await waitFor("paused", () => card() && text(card().querySelector("span.badge")) === "paused", 10000);
  expectRequest("PATCH", "/follows/" + id, (r) => r.status === 200);
  click(card().querySelectorAll("button").find((b) => text(b) === "Stop"), "stop");
  await waitFor("stopped", () => card() && text(card().querySelector("span.badge")) === "stopped", 10000);
  expectRequest("DELETE", "/follows/" + id, (r) => r.status === 200);
  step("pause and stop through the real API");

  const mismatches = requests.filter((r) => r.status >= 300);
  if (mismatches.length) fail("non-2xx replies: " + JSON.stringify(mismatches.map((r) => `${r.method} ${r.path} ${r.status} ${r.reply}`)));
  if (consoleErrors.length) fail("console errors: " + consoleErrors.join(" | "));
  print(`all ${n} steps passed against ${API}; ${requests.length} API requests`);
  process.exit(0);
}

process.on("uncaughtException", (e) => fail("uncaught " + (e && e.stack ? e.stack : e)));
setTimeout(() => fail("took longer than 60 s"), 60_000).unref();
if (liveApi) mainReal(); else main();
