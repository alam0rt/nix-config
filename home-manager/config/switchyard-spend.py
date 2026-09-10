"""Report true OpenRouter spend for the Switchyard advisor gate.

Switchyard has no cost concept: /v1/stats and the routing log count tokens only,
and the advisor's consults never reach a client, so nothing downstream (OMP
included) can see what the gate actually costs.

Two numbers are printed, and they answer different questions:

  * Account spend, straight from OpenRouter's own accounting for this key. This
    is authoritative and covers every call made with the key, gate consults and
    ordinary OMP turns alike -- it does not isolate Switchyard.

  * A per-model breakdown derived from Switchyard's routing log priced against
    OpenRouter's live rate card. This isolates Switchyard traffic and splits
    client-visible turns from gate consults, but it is arithmetic on token
    counts, not billing data, so treat it as an estimate.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone

API = "https://openrouter.ai/api/v1"
DEFAULT_LOG = os.path.expanduser("~/.local/state/switchyard/routing.jsonl")
# Switchyard tags every non-client-visible call -- gate consults and the turns a
# REDO discarded -- as "classifier", whatever the route type.
GATE_TIER = "classifier"


def read_key() -> str:
    """Pull the OpenRouter key back out of OMP's credential store."""
    db = os.path.expanduser("~/.omp/agent/agent.db")
    out = subprocess.run(
        [
            "sqlite3",
            "-readonly",
            f"file:{db}?mode=ro",
            "select data ->> 'key' from auth_credentials "
            "where provider='openrouter' and credential_type='api_key' limit 1",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    key = out.stdout.strip()
    if out.returncode != 0 or not key:
        sys.exit(f"could not read the OpenRouter key from {db}: {out.stderr.strip()}")
    return key


def get(path: str, key: str) -> dict:
    req = urllib.request.Request(f"{API}{path}", headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)["data"]


def rates(pricing: dict, when: datetime) -> tuple[float, float, float]:
    """Resolve prompt/completion/cache-read rates for a moment in time.

    DeepSeek bills roughly double during weekday UTC peak windows, so a flat
    rate would silently misprice half the advisor's consults. Overrides are
    keyed by UTC weekday and an HHMM window; a window whose end is at or before
    its start wraps past midnight.
    """
    chosen = pricing
    hhmm = when.hour * 100 + when.minute
    for override in pricing.get("overrides", []):
        if when.strftime("%A").lower() not in override.get("utc_days", []):
            continue
        start, end = override.get("utc_start"), override.get("utc_end")
        if start is None or end is None:
            chosen = override
            break
        inside = start <= hhmm < end if start < end else (hhmm >= start or hhmm < end)
        if inside:
            chosen = override
            break
    return (
        float(chosen.get("prompt", 0) or 0),
        float(chosen.get("completion", 0) or 0),
        float(chosen.get("input_cache_read", 0) or 0),
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--log", default=DEFAULT_LOG, help=f"routing log (default: {DEFAULT_LOG})")
    ap.add_argument("--since", metavar="YYYY-MM-DD", help="only price records on or after this UTC date")
    args = ap.parse_args()

    key = read_key()

    acct = get("/key", key)
    limit = acct.get("limit")
    print("OpenRouter account (authoritative, every call made with this key)")
    print(f"  today      ${acct.get('usage_daily', 0):.4f}")
    print(f"  this week  ${acct.get('usage_weekly', 0):.4f}")
    print(f"  this month ${acct.get('usage_monthly', 0):.4f}")
    print(f"  all time   ${acct.get('usage', 0):.4f}")
    if limit is not None:
        print(f"  limit      ${acct.get('limit_remaining', 0):.4f} left of ${limit:.2f} ({acct.get('limit_reset')})")

    if not os.path.exists(args.log):
        print(f"\nNo routing log at {args.log}; skipping the per-model breakdown.")
        return

    pricing = {m["id"]: m.get("pricing", {}) for m in get("/models", key)}
    # (model, is_gate_consult) -> totals
    agg: dict[tuple[str, bool], dict[str, float]] = defaultdict(
        lambda: {"calls": 0, "prompt": 0, "cached": 0, "completion": 0, "cost": 0.0}
    )
    unpriced = set()

    for line in open(args.log):
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        when = datetime.fromisoformat(rec["ts"].replace("Z", "+00:00")).astimezone(timezone.utc)
        if args.since and when.date().isoformat() < args.since:
            continue
        model = rec["model"]
        bucket = agg[(model, rec.get("tier") == GATE_TIER)]
        cached = rec.get("cached_tokens", 0)
        fresh = max(rec.get("prompt_tokens", 0) - cached, 0)
        completion = rec.get("completion_tokens", 0)
        bucket["calls"] += 1
        bucket["prompt"] += rec.get("prompt_tokens", 0)
        bucket["cached"] += cached
        bucket["completion"] += completion
        if model in pricing:
            p_rate, c_rate, cache_rate = rates(pricing[model], when)
            bucket["cost"] += fresh * p_rate + cached * cache_rate + completion * c_rate
        else:
            unpriced.add(model)

    print(f"\nSwitchyard traffic (estimated from {args.log})")
    print(f"  {'model':<40} {'role':<9} {'calls':>6} {'tokens':>10} {'est. $':>10}")
    total = 0.0
    for (model, is_gate), b in sorted(agg.items(), key=lambda kv: -kv[1]["cost"]):
        total += b["cost"]
        role = "gate" if is_gate else "served"
        tokens = int(b["prompt"] + b["completion"])
        print(f"  {model:<40} {role:<9} {b['calls']:>6} {tokens:>10,} {b['cost']:>10.4f}")
    print(f"  {'':<40} {'total':<9} {'':>6} {'':>10} {total:>10.4f}")
    print("  served = turns the client saw; gate = advisor consults plus turns a REDO discarded")
    if unpriced:
        print(f"  not on the rate card, excluded: {', '.join(sorted(unpriced))}")


if __name__ == "__main__":
    main()
