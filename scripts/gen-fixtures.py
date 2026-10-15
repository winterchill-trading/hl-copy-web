#!/usr/bin/env python3
"""Writes the mock API responses under dev/ (deterministic; rerun after a type change).

The shapes follow api/api_types.mli. Addresses are hashes of made-up labels, numbers
come from a seeded random walk; nothing here is a real account.
"""
import hashlib
import json
import math
import os
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "dev")
AS_OF = 1_760_257_800_000  # 2025-10-12 08:30 UTC
DAY = 86_400_000
COINS = ["BTC", "ETH", "SOL", "HYPE", "ARB", "DOGE"]
NAMES = ["slow-carry", None, "basis-hunter", None, "trend-desk", "meanrev", None, "scalper-07"]


def address(label):
    return "0x" + hashlib.sha256(label.encode()).hexdigest()[:40]


def write(path, value):
    full = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


def equity_curve(rng, start, drift, vol, days=90):
    points, equity = [], start
    for d in range(days + 1):
        points.append({"time": AS_OF - (days - d) * DAY, "equity": round(equity, 2)})
        equity *= math.exp(rng.gauss(drift, vol))
    return points


def max_drawdown(points):
    peak, worst = points[0]["equity"], 0.0
    for p in points:
        peak = max(peak, p["equity"])
        worst = max(worst, (peak - p["equity"]) / peak)
    return worst


def fills(rng, n):
    out, t = [], AS_OF
    for i in range(n):
        coin = rng.choice(COINS[:4])
        px = {"BTC": 112_000, "ETH": 4_100, "SOL": 190, "HYPE": 45}[coin] * rng.uniform(0.97, 1.03)
        side = rng.choice(["buy", "sell"])
        closing = i % 2 == 0
        direction = ("Close " if closing else "Open ") + ("Short" if (side == "buy") == closing else "Long")
        out.append({
            "time": t, "coin": coin, "side": side, "px": round(px, 2),
            "sz": round(rng.uniform(0.1, 3.0) * 4_000 / px, 4),
            "closed_pnl": round(rng.gauss(40, 160), 2) if closing else 0.0,
            "fee": round(rng.uniform(0.2, 3.0), 2), "dir": direction,
        })
        t -= int(rng.uniform(0.2, 9) * 3_600_000)
    return out


def positions(rng, k, equity):
    out = []
    for coin in rng.sample(COINS[:4], k):
        px = {"BTC": 112_000, "ETH": 4_100, "SOL": 190, "HYPE": 45}[coin]
        notional = equity * rng.uniform(0.2, 1.2)
        out.append({
            "coin": coin, "size": round(rng.choice([1, -1]) * notional / px, 4),
            "entry_px": round(px * rng.uniform(0.95, 1.05), 2),
            "unrealized_pnl": round(rng.gauss(0, notional * 0.02), 2),
            "leverage": round(rng.uniform(1, 5), 1),
        })
    return out


METRICS = [  # name, label, unit, better (leader-scoring's Metric)
    ("total_return", "Return", "ratio", "higher"),
    ("volatility", "Volatility", "ratio", "lower"),
    ("sharpe", "Sharpe", "number", "higher"),
    ("sortino", "Sortino", "number", "higher"),
    ("max_drawdown", "Max drawdown", "ratio", "lower"),
    ("max_drawdown_duration_days", "Longest drawdown", "days", "lower"),
    ("win_rate", "Win rate", "ratio", "higher"),
    ("trades", "Trades", "count", "neither"),
    ("leverage_p95", "Leverage (p95)", "multiple", "lower"),
    ("top_coin_share", "Top coin share", "ratio", "lower"),
    ("var_95", "VaR 95%", "ratio", "lower"),
    ("cvar_95", "CVaR 95%", "ratio", "lower"),
    ("time_in_market", "Time in market", "ratio", "neither"),
    ("long_bias", "Long bias", "number", "neither"),
]
WEIGHTS = {"sharpe": 0.4, "max_drawdown": 0.35, "win_rate": 0.25}


def curve_metrics(curve, breakdown, rng):
    e = [p["equity"] for p in curve]
    r = [e[i + 1] / e[i] - 1 for i in range(len(e) - 1)]
    mean = sum(r) / len(r)
    sd = math.sqrt(sum((x - mean) ** 2 for x in r) / (len(r) - 1))
    down = math.sqrt(sum(min(x, 0) ** 2 for x in r) / len(r))
    tail = sorted(r)[: max(1, len(r) // 20)]
    peak, start, longest = e[0], 0, 0
    for i, x in enumerate(e):
        if x >= peak:
            longest, peak, start = max(longest, i - start), x, i
    return {
        "total_return": e[-1] / e[0] - 1, "volatility": sd * math.sqrt(365),
        "sharpe": mean / sd * math.sqrt(365), "sortino": mean / down * math.sqrt(365) if down else None,
        "max_drawdown": max_drawdown(curve), "max_drawdown_duration_days": float(max(longest, len(e) - 1 - start)),
        "win_rate": breakdown["win_rate"], "trades": float(breakdown["trade_count"]),
        "leverage_p95": rng.uniform(0.8, 6.0), "top_coin_share": rng.uniform(0.3, 0.95),
        "var_95": -sorted(r)[int(0.05 * (len(r) - 1))], "cvar_95": -sum(tail) / len(tail),
        "time_in_market": rng.uniform(0.4, 1.0), "long_bias": rng.uniform(-0.6, 0.9),
    }


def scoring(leaders, details, rng):
    """leader-scoring's summary and detail per leader (mock: three weighted metrics)."""
    values = {l["address"]: curve_metrics(c, l["breakdown"], rng) for l, c in details}

    def pct(name, x):
        xs = [v[name] for v in values.values()]
        p = (sum(y < x for y in xs) + (sum(y == x for y in xs) - 1) / 2) / (len(xs) - 1)
        return 1 - p if name == "max_drawdown" else p

    scores = {}
    for addr, v in values.items():
        comps = [{"metric": m, "label": next(lab for n, lab, _, _ in METRICS if n == m),
                  "value": round(v[m], 6), "percentile": round(pct(m, v[m]), 6), "weight": w,
                  "contribution": round(100 * w * pct(m, v[m]), 4)} for m, w in WEIGHTS.items()]
        scores[addr] = (round(sum(c["contribution"] for c in comps), 2), comps)
    order = sorted(scores, key=lambda a: -scores[a][0])
    out = {}
    for leader, curve in details:
        addr = leader["address"]
        v, (score, comps) = values[addr], scores[addr]
        rank = order.index(addr) + 1
        capacity = round(rng.uniform(2e4, 3e6), 2)
        curve_pts = [{"follower_equity": x, "orders": 120,
                      "mean_cost_bps": round(2 + 8 * x / capacity, 3),
                      "median_cost_bps": round(1.5 + 7 * x / capacity, 3),
                      "p90_cost_bps": round(4 + 14 * x / capacity, 3),
                      "unfilled_share": round(max(0.0, min(1.0, (x / capacity - 1) * 0.3)), 4)}
                     for x in (1e3, 1e4, 1e5, 1e6, 1e7)]
        alerts = []
        if v["max_drawdown"] > 0.25:
            alerts.append({"kind": "drawdown_breach", "severity": "warning", "time": AS_OF - 3 * DAY,
                           "message": f"{100 * v['max_drawdown']:.1f}% below the peak"})
        if v["leverage_p95"] > 4:
            alerts.append({"kind": "leverage_spike", "severity": "warning", "time": AS_OF - DAY,
                           "message": f"leverage reached {v['leverage_p95'] * 1.6:.1f}x; baseline p95 {v['leverage_p95']:.1f}x"})
        predicted = round(rng.gauss(0.1, 0.4), 4)
        summary = {"score": score, "rank": rank, "percentile": round((len(order) - rank) / (len(order) - 1), 4),
                   "eligible": True, "predicted_forward_sharpe": predicted, "capacity_usd": capacity,
                   "alerts": len(alerts), "worst_alert": alerts[0]["severity"] if alerts else None,
                   "sharpe": round(v["sharpe"], 6), "max_drawdown": round(v["max_drawdown"], 6),
                   "leverage_p95": round(v["leverage_p95"], 6)}
        detail = {"score": score, "rank": rank, "percentile": summary["percentile"], "eligible": True,
                  "reasons": [], "components": comps, "predicted_forward_sharpe": predicted,
                  "metrics": [{"name": n, "label": lab, "value": None if v[n] is None else round(v[n], 6),
                               "unit": u, "better": b} for n, lab, u, b in METRICS],
                  "equity_source": "venue", "bar_seconds": 86400.0, "equity_curve": curve,
                  "capacity": {"max_cost_bps": 10.0, "capacity_usd": capacity, "curve": curve_pts,
                               "coins_without_book": []},
                  "alerts": alerts}
        out[addr] = (summary, detail)
    return out


def main():
    rng = random.Random(7)
    leaders, details = [], []
    for i, name in enumerate(NAMES):
        start = rng.uniform(40_000, 900_000)
        curve = equity_curve(rng, start, rng.uniform(-0.002, 0.006), rng.uniform(0.01, 0.04))
        end = curve[-1]["equity"]
        pnl = end - start
        trades = rng.randint(25, 900)
        breakdown = {
            "pnl": round(pnl, 2), "roi": round(pnl / start, 4),
            "max_drawdown": round(max_drawdown(curve), 4),
            "win_rate": round(rng.uniform(0.38, 0.72), 4), "trade_count": trades,
            "avg_hold_secs": round(rng.uniform(600, 4 * 86_400)),
            "consistency": round(rng.uniform(0.3, 0.95), 4),
        }
        leader = {
            "address": address(f"fixture-leader-{i}"),
            **({"display_name": name} if name else {}),
            "rank": 0, "score": 0.0, "breakdown": breakdown, "account_value": round(end, 2),
            "window_pnl": {
                "day": round(end - curve[-2]["equity"], 2), "week": round(end - curve[-8]["equity"], 2),
                "month": round(end - curve[-31]["equity"], 2), "all_time": round(pnl, 2),
            },
            "followers": rng.randint(0, 40),
        }
        dd = breakdown["max_drawdown"]
        leader["score"] = round(max(0.0, min(100.0, 50 + 30 * math.tanh(breakdown["roi"]) - 60 * dd
                                             + 30 * (breakdown["win_rate"] - 0.5)
                                             + 20 * (breakdown["consistency"] - 0.5))), 1)
        leaders.append(leader)
        details.append((leader, curve))
    leaders.sort(key=lambda l: -l["score"])
    for rank, leader in enumerate(leaders, 1):
        leader["rank"] = rank
    # a separate generator, so adding scoring left every other mock value unchanged
    scored = scoring(leaders, details, random.Random(11))
    for leader in leaders:
        leader["scoring"] = scored[leader["address"]][0]
    write("leaders.json", {"as_of": AS_OF, "leaders": leaders})
    for leader, curve in details:
        write(f"leaders/{leader['address']}.json", {
            "leader": leader, "equity_curve": curve, "fills": fills(rng, 40),
            "positions": positions(rng, rng.randint(1, 3), leader["account_value"]),
            "scoring": scored[leader["address"]][1],
        })

    me = address("fixture-follower")
    write("auth-challenge.json", {
        "message": "hl-copy wants you to sign in with your wallet.\n\nNonce: 7f3a91c2\nIssued: 2025-10-12T08:30:00Z",
        "nonce": "7f3a91c2", "expires_at": AS_OF + 300_000,
    })
    write("session.json", {"token": "dev-session-token", "address": me, "expires_at": AS_OF + DAY})
    write("agent-offer.json", {
        "approve_agent": {
            "hyperliquid_chain": "Testnet", "signature_chain_id": "0x66eee",
            "agent_address": address("fixture-agent"), "agent_name": "hl-copy", "nonce": AS_OF,
        },
        "approve_builder_fee": {
            "hyperliquid_chain": "Testnet", "signature_chain_id": "0x66eee",
            "max_fee_rate": "0.01%", "builder": address("fixture-builder"), "nonce": AS_OF + 1,
        },
    })
    caps = {"max_leverage": 3.0, "max_notional_per_symbol": 5000.0, "max_daily_loss": 500.0,
            "allowlist": [], "min_order_notional": 10.0}
    follows = []
    for i, (state, scale) in enumerate([
        ("running", {"kind": "equity_ratio"}),
        ("paused", {"kind": "multiplier", "value": 0.25}),
    ]):
        leader = leaders[i]
        follows.append({
            "id": f"f-{i + 1}", "leader": leader["address"], "scale": scale,
            "caps": {**caps, "allowlist": ["BTC", "ETH"] if i else []}, "state": state,
            "created_at": AS_OF - (12 - 5 * i) * DAY, "pnl": round(rng.gauss(150, 300), 2),
            "positions": positions(rng, 2 - i, 8_000),
        })
    # The agent's approval ran out a day after the snapshot, so against any current
    # clock the follow page asks for a new approveAgent signature first.
    write("me.json", {
        "address": me, "account_value": 12_480.55,
        "total_pnl": round(sum(f["pnl"] for f in follows), 2),
        "agent": {
            "agent_address": address("fixture-old-agent"), "agent_name": "hl-copy",
            "approved": True, "valid_until": AS_OF + DAY, "builder_fee": "0.01%",
        },
        "follows": follows,
    })


if __name__ == "__main__":
    main()
