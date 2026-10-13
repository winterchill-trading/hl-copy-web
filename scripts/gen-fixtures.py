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
    write("leaders.json", {"as_of": AS_OF, "leaders": leaders})
    for leader, curve in details:
        write(f"leaders/{leader['address']}.json", {
            "leader": leader, "equity_curve": curve, "fills": fills(rng, 40),
            "positions": positions(rng, rng.randint(1, 3), leader["account_value"]),
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
    write("dashboard.json", {
        "address": me, "account_value": 12_480.55,
        "total_pnl": round(sum(f["pnl"] for f in follows), 2), "follows": follows,
    })


if __name__ == "__main__":
    main()
