// Smoke test: runs the compiled app under node with fake_dom.js and a fake EIP-1193
// wallet, and walks every page against the dev/ fixtures.
//
//   node run.js <path to main.bc.js> <directory holding dev/>
"use strict";
const path = require("path");
const { install, makeEvent } = require("./fake_dom.js");

const [, , appJs, root] = process.argv;
const env = install({ root, hash: "" });
const { document } = env;
const t0 = Date.now();
const steps = [];

// Errors the app logs (Async unhandled exceptions end up here) fail the run.
const consoleErrors = [];
const origError = console.error;
console.error = (...args) => { consoleErrors.push(args.map(String).join(" ")); origError(...args); };
console.log = () => {}; // Bonsai prints a console banner at startup.
const print = (s) => process.stdout.write(s + "\n");

// A wallet that approves everything and records what it was asked to sign.
const wallet = {
  account: "0xAbCdEf0000000000000000000000000000000001",
  calls: [],
  request({ method, params }) {
    this.calls.push({ method, params });
    switch (method) {
      case "eth_requestAccounts": return Promise.resolve([this.account]);
      case "eth_chainId": return Promise.resolve("0x66eee");
      case "personal_sign": return Promise.resolve("0x" + "11".repeat(65));
      case "eth_signTypedData_v4": return Promise.resolve("0x" + "22".repeat(65));
      default: return Promise.reject({ code: 4200, message: "unsupported " + method });
    }
  },
};

const all = (sel) => document.querySelectorAll(sel);
const text = (el) => (el ? el.textContent : "");
const bodyText = () => text(document.body);
const byText = (sel, s) => all(sel).find((el) => text(el).trim().startsWith(s));

function fail(msg) {
  print("FAIL: " + msg);
  print("hash: " + location.hash);
  print("page: " + bodyText().slice(0, 1500));
  print("requests: " + XMLHttpRequest.log.join(", "));
  print("wallet calls: " + JSON.stringify(wallet.calls));
  print("console errors: " + consoleErrors.join(" | "));
  process.exit(1);
}

function waitFor(what, pred, timeoutMs = 4000) {
  return new Promise((resolve) => {
    const start = Date.now();
    const tick = () => {
      let v;
      try { v = pred(); } catch (e) { v = undefined; }
      if (v) return resolve(v);
      if (Date.now() - start > timeoutMs) fail("timed out waiting for " + what);
      setTimeout(tick, 10);
    };
    tick();
  });
}

function click(el, what) {
  if (!el) fail("nothing to click: " + what);
  el.dispatchEvent(makeEvent("click"));
}

function type(el, value) {
  el.value = value;
  el.dispatchEvent(makeEvent("input"));
}

function step(name) { steps.push(name); print(`ok ${steps.length} - ${name}`); }

async function main() {
  require(path.resolve(appJs));

  // Leaderboard
  const rows = () => all("#leaders-table").length && document.querySelector("#leaders-table").querySelectorAll("tr").slice(1);
  await waitFor("8 leader rows", () => rows() && rows().length === 8);
  if (!text(rows()[0]).includes("meanrev")) fail("rank 1 should be meanrev");
  step("leaderboard renders 8 leaders from dev/leaders.json");

  const check = document.querySelector("#ranking-check");
  if (!check || !text(check).includes("The ranking does not persist")) fail("ranking check missing above the table");
  if (!bodyText().includes("1 integrity flag")) fail("integrity badge missing on the flagged row");
  step("the ranking check says the order does not persist; the flagged leader carries a badge");

  click(byText("span.sortable", "ROI"), "ROI header");
  await waitFor("ROI sort", () => text(rows()[0]).includes("trend-desk"));
  step("clicking ROI sorts by ROI, best first");

  const search = all("input").find((i) => i.getAttribute("placeholder") === "name or 0x address");
  type(search, "basis");
  await waitFor("filtered rows", () => rows() && rows().length === 1 && text(rows()[0]).includes("basis-hunter"));
  type(search, "");
  await waitFor("unfiltered rows", () => rows().length === 8);
  step("search filters the table");

  // Leader detail
  const leader = rows().find((r) => text(r).includes("meanrev")).querySelector("a").getAttribute("href");
  location.hash = leader;
  await waitFor("equity polyline", () => document.querySelector("polyline"));
  const points = document.querySelector("polyline").getAttribute("points").split(" ");
  if (points.length !== 91) fail("expected 91 curve points, got " + points.length);
  if (!bodyText().includes("Recent fills (latest 25)")) fail("fills table missing");
  if (!document.querySelector("#follow-button")) fail("follow button missing");
  step("leader page draws a 91 point equity curve and the fills table");

  // leader-scoring sections on the same page
  // the fake DOM matches one simple selector at a time, so descend step by step
  const bodyRows = (id) => {
    const table = document.querySelector(id);
    const tbody = table && table.querySelector("tbody");
    return tbody ? tbody.querySelectorAll("tr") : [];
  };
  const metricRows = bodyRows("#leader-metrics");
  if (metricRows.length !== 14) fail("expected 14 metric rows, got " + metricRows.length);
  const components = bodyRows("#score-components");
  if (components.length !== 3) fail("expected 3 score components, got " + components.length);
  const chart = document.querySelector("#capacity-chart");
  const cost = chart && chart.querySelector("polyline");
  if (!cost || cost.getAttribute("points").split(" ").length !== 5) fail("capacity curve missing");
  if (!bodyText().includes("Composite score")) fail("composite score missing");
  if (!document.querySelector("#leader-alerts") && !bodyText().includes("No behaviour changes detected.")) fail("alerts section missing");
  step("leader page shows the score components, 14 metrics, the capacity curve and alerts");

  if (!document.querySelector("#leader-integrity")) fail("integrity section missing");
  if (!document.querySelector("#leader-persistence") || !bodyText().includes("Ranking windows")) fail("persistence section missing");
  if (!document.querySelector("#leader-stats") || !bodyText().includes("statistical gate")) fail("selection statistics missing");
  step("leader page shows integrity, persistence and the selection statistics");

  // Dashboard before login
  location.hash = "#/dashboard";
  await waitFor("login prompt", () => bodyText().includes("Connect your wallet to see your follows."));
  step("dashboard asks to connect when signed out");

  // Login without a wallet extension, then with one
  location.hash = "#/login";
  await waitFor("login page", () => byText("button", "Connect wallet"));
  click(byText("button", "Connect wallet"), "connect");
  await waitFor("no-wallet error", () => bodyText().includes("No browser wallet found"));
  step("connect without a wallet extension explains what to do");

  window.ethereum = wallet;
  click(byText("button", "Connect wallet"), "connect");
  await waitFor("dashboard after login", () => location.hash === "#/dashboard" && document.querySelector("#follow-f-1"));
  const signed = wallet.calls.find((c) => c.method === "personal_sign");
  const message = Buffer.from(signed.params[0].slice(2), "hex").toString("utf8");
  if (!message.includes("Nonce: 7f3a91c2")) fail("personal_sign got " + message);
  if (signed.params[1] !== wallet.account.toLowerCase()) fail("personal_sign address " + signed.params[1]);
  if (!bodyText().includes("0xabcd...0001")) fail("header should show the wallet address");
  if (!bodyText().includes("approval expired on 2025-10-13 08:30 UTC")) fail("expired agent notice missing");
  step("wallet login: eth_requestAccounts, personal_sign of the hex-encoded challenge");

  // Dashboard commands
  const badge = (id) => text(document.querySelector("#follow-" + id).querySelector("span.badge"));
  if (badge("f-1") !== "running") fail("f-1 should start running");
  click(document.querySelector("#follow-f-1").querySelectorAll("button").find((b) => text(b) === "Pause"), "pause");
  await waitFor("f-1 paused", () => document.querySelector("#follow-f-1") && badge("f-1") === "paused");
  click(document.querySelector("#follow-f-2").querySelectorAll("button").find((b) => text(b) === "Stop"), "stop");
  await waitFor("f-2 stopped", () => document.querySelector("#follow-f-2") && badge("f-2") === "stopped");
  step("pause and stop update the follow state");

  // Follow flow
  location.hash = "#/follow/" + leader.split("/").pop();
  await waitFor("follow form", () => all("input").find((i) => i.getAttribute("name") === "Max_leverage"));
  const leverage = all("input").find((i) => i.getAttribute("name") === "Max_leverage");
  type(leverage, "x");
  await waitFor("validation error", () => bodyText().includes("must be a number"));
  await waitFor("review button", () => byText("button", "Review agent approval"));
  if (!byText("button", "Review agent approval").disabled) fail("review should be disabled while invalid");
  type(leverage, "2");
  await waitFor("valid form", () => !bodyText().includes("must be a number"));
  step("follow form validates its fields");

  click(byText("button", "Review agent approval"), "review");
  await waitFor("typed data", () => all("pre").some((p) => text(p).includes("HyperliquidTransaction:ApproveAgent")));
  if (!all("pre").some((p) => text(p).includes("HyperliquidTransaction:ApproveBuilderFee"))) fail("builder fee typed data missing");
  step("agent approval shows the approveAgent and approveBuilderFee typed data");

  click(byText("button", "Sign and follow"), "sign");
  await waitFor("new follow on dashboard", () => location.hash === "#/dashboard" && document.querySelector("#follow-f-3"));
  const typed = wallet.calls.filter((c) => c.method === "eth_signTypedData_v4").map((c) => JSON.parse(c.params[1]));
  if (typed.length !== 2) fail("expected two typed-data signatures, got " + typed.length);
  if (typed[0].primaryType !== "HyperliquidTransaction:ApproveAgent") fail("first signature should be approveAgent");
  if (typed[0].domain.chainId !== 421614) fail("approveAgent chainId " + typed[0].domain.chainId);
  if (typeof typed[0].message.nonce !== "number") fail("nonce must be a JSON number");
  if (typed[1].primaryType !== "HyperliquidTransaction:ApproveBuilderFee") fail("second signature should be approveBuilderFee");
  step("sign and follow: two eth_signTypedData_v4 calls, then the follow shows on the dashboard");

  // A second leader: the agent is active now, so no new signature is needed.
  if (bodyText().includes("approval expired")) fail("agent should be active after approval");
  const other = (await (async () => { location.hash = "#/leaders"; await waitFor("leaders again", () => rows() && rows().length === 8); return rows()[1]; })())
    .querySelector("a").getAttribute("href").split("/").pop();
  location.hash = "#/follow/" + other;
  await waitFor("direct follow button", () => byText("button", "Follow"));
  if (!bodyText().includes("Your trading agent is approved.")) fail("agent status line missing");
  const algo = all("select").find((el) => el.getAttribute("name") === "algo");
  if (!algo) fail("execution select missing");
  algo.value = "twap";
  algo.dispatchEvent(makeEvent("change"));
  await waitFor("TWAP fields", () => all("input").find((i) => i.getAttribute("name") === "Algo_slices"));
  if (!bodyText().includes("Execution: TWAP 60 s in 6 slices.")) fail("TWAP summary missing");
  click(byText("button", "Follow"), "follow");
  await waitFor("fourth follow", () => location.hash === "#/dashboard" && document.querySelector("#follow-f-4"));
  if (wallet.calls.filter((c) => c.method === "eth_signTypedData_v4").length !== 2) fail("no new signature expected");
  if (!text(document.querySelector("#follow-f-4")).includes("TWAP 60 s in 6 slices")) fail("follow card should show the algorithm");
  step("with an active agent, following needs no signature; TWAP picked on the form shows on the card");

  if (consoleErrors.length) fail("console errors: " + consoleErrors.join(" | "));
  print(`all ${steps.length} steps passed in ${Date.now() - t0} ms; ${XMLHttpRequest.log.length} fixture requests`);
  process.exit(0);
}

process.on("uncaughtException", (e) => fail("uncaught " + (e && e.stack ? e.stack : e)));
setTimeout(() => fail("smoke test took longer than 60 s"), 60_000).unref();
main();
