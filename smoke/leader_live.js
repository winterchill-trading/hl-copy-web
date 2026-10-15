// The leader page against a running hl-copy-api: loads the compiled app with
// ?api=<API>, opens #/leader/<address> and checks the leader-scoring sections (score
// components, metrics, capacity curve, alerts) rendered from the live response.
//
//   node leader_live.js <path to main.bc.js> <directory holding dev/> <API URL> [address]
//
// Without an address the first leader of GET /leaders is used. Read-only: no wallet,
// no login, no follow.
"use strict";
const { install } = require("./fake_dom.js");

const [, , appJs, root, API, wanted] = process.argv;
const print = (s) => process.stdout.write(s + "\n");

async function real(method, url, headers, body) {
  if (!url.startsWith(API)) return null;
  const r = await fetch(url, { method, headers, body: body || undefined });
  return { status: r.status, body: await r.text() };
}

const env = install({ root, hash: "", search: "?api=" + encodeURIComponent(API), handler: real });
const { document } = env;
console.log = () => {};
const text = (el) => (el ? el.textContent : "");

function fail(msg) {
  print("FAIL: " + msg);
  print("page: " + text(document.body).slice(0, 1500));
  process.exit(1);
}

function waitFor(what, pred, timeoutMs = 15000) {
  return new Promise((resolve) => {
    const start = Date.now();
    const tick = () => {
      let v;
      try { v = pred(); } catch (e) { v = undefined; }
      if (v) return resolve(v);
      if (Date.now() - start > timeoutMs) fail("timed out waiting for " + what);
      setTimeout(tick, 20);
    };
    tick();
  });
}

const bodyRows = (id) => {
  const table = document.querySelector(id);
  const tbody = table && table.querySelector("tbody");
  return tbody ? tbody.querySelectorAll("tr") : [];
};

(async () => {
  const leaders = (await (await fetch(API + "/leaders")).json()).leaders;
  const address = wanted || leaders[0].address;
  require(appJs);
  window.location.hash = "#/leader/" + address;
  await waitFor("metrics table", () => bodyRows("#leader-metrics").length > 0);
  const metrics = bodyRows("#leader-metrics").map((r) => r.querySelectorAll("td").map(text));
  const components = bodyRows("#score-components").length;
  const chart = document.querySelector("#capacity-chart");
  const cost = chart && chart.querySelector("polyline");
  const alerts = document.querySelector("#leader-alerts");
  const score = text(document.querySelector("#leader-score")).replace(/\s+/g, " ").slice(0, 160);
  print("leader " + address);
  print("score section: " + score);
  print("score components: " + components);
  print("metric rows: " + metrics.length);
  for (const [label, value] of metrics.slice(0, 6)) print("  " + label + ": " + value);
  print("capacity curve points: " + (cost ? cost.getAttribute("points").split(" ").length : 0));
  print("alerts: " + (alerts ? alerts.querySelectorAll("li").length : 0));
  if (components === 0 || metrics.length === 0) fail("scoring sections missing");
  print("ok");
  process.exit(0);
})();
