#!/usr/bin/env python3
"""List models actually usable on this machine (authenticated providers only).

Reads pi's local model catalog and auth store — no network, no secrets printed.
By default only curated model families are shown (glm, gpt, claude, deepseek,
grok, gemini, solar) so the decision set stays small; pass --all to list every
usable model. Output is sorted cheapest-first so an agent can map tiers per the
delegation skill's lookup table onto whatever providers exist on THIS machine.

Usage:
  discover-models.py                # curated families, top 40 cheapest
  discover-models.py --all         # full catalog, no family filter
  discover-models.py --limit 20    # fewer results
  discover-models.py --provider openrouter   # filter to one provider
  discover-models.py --min-out 1   # only premium output quality (out >= $1/M)
"""

from __future__ import annotations

import argparse
import json
import os
import sys

AGENT_DIR = os.environ.get("PI_CODING_AGENT_DIR") or os.path.expanduser("~/.pi/agent")

# Curated families (case-insensitive substring match on the model id).
FAMILIES = ("glm", "gpt", "claude", "deepseek", "grok", "gemini", "solar")


def human_ctx(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.0f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}K"
    return str(n)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="list all usable models, not just curated families")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--provider", default=None, help="store provider key (e.g. openrouter), not an id prefix")
    parser.add_argument("--min-out", type=float, default=None, metavar="USD", help="only models with output cost >= this per M")
    args = parser.parse_args()

    auth_path = os.path.join(AGENT_DIR, "auth.json")
    store_path = os.path.join(AGENT_DIR, "models-store.json")
    settings_path = os.path.join(AGENT_DIR, "settings.json")

    try:
        with open(auth_path) as f:
            authed = set(json.load(f).keys())
    except FileNotFoundError:
        print(f"No auth store at {auth_path} — no providers configured on this machine.", file=sys.stderr)
        return 1
    try:
        with open(store_path) as f:
            store = json.load(f)
    except FileNotFoundError:
        print(f"No model catalog at {store_path}. Run 'pi' once or 'pi update model-catalogs' to refresh it.", file=sys.stderr)
        return 1

    try:
        with open(settings_path) as f:
            enabled = set(json.load(f).get("enabledModels", []))
    except (FileNotFoundError, json.JSONDecodeError):
        enabled = set()

    rows = []
    for provider, pdata in store.items():
        if provider not in authed:
            continue
        if args.provider and provider != args.provider:
            continue
        for m in pdata.get("models", []):
            mid = m.get("id", "")
            if mid.startswith("~") or mid.endswith(":batch") or mid in ("auto", "auto-beta"):
                continue  # aliases, async batch variants, and auto-router placeholders
            ref = f"{provider}/{mid}"
            mark = "*" if ref in enabled else " "
            # Curated families by default, but this machine's enabledModels picks always show.
            if not args.all and ref not in enabled and not any(f in mid.lower() for f in FAMILIES):
                continue
            cost = m.get("cost", {}) or {}
            cin, cout = float(cost.get("input", 0) or 0), float(cost.get("output", 0) or 0)
            sentinel = cin < 0 or cout < 0
            price = "?price" if sentinel else f"${cin:g}/${cout:g}"
            if args.min_out is not None and cout < args.min_out:
                continue
            flags = ""
            if m.get("reasoning"):
                flags += "R"
            if "image" in (m.get("input") or []):
                flags += "I"
            sort_key = (1, 0.0) if sentinel else (0, cin + cout)
            rows.append((sort_key, f"{price:<16} {human_ctx(m.get('contextWindow') or 0):>4} {flags:<2} {ref}{mark}"))

    rows.sort(key=lambda r: r[0])
    valid_providers = sorted(p for p in store if p in authed)
    if not rows:
        target = f" for provider '{args.provider}'" if args.provider else ""
        print(
            f"No usable models found{target} with the current filters. "
            f"Valid provider keys on this machine: {', '.join(valid_providers) or '(none)'}.",
            file=sys.stderr,
        )
        if args.provider and args.provider not in valid_providers:
            print(
                "Note: --provider takes store provider keys (e.g. 'openrouter'), not id prefixes like 'gemini' — those live inside a provider key.",
                file=sys.stderr,
            )
        return 1

    # Starred picks (settings enabledModels) always lead the first page.
    starred = [r for r in rows if r[1].endswith("*")]
    others = [r for r in rows if not r[1].endswith("*")]
    shown = starred + others[: max(0, args.limit - len(starred))]

    for _, line in shown:
        print(line)
    if len(rows) > len(shown):
        print(f"... ({len(rows) - len(shown)} more; use --limit or --provider)")
    print("\nLegend: cost in$/out$ per M tokens | ctx window | R=reasoning I=image input | *=enabledModels pick (always shown first)", file=sys.stderr)
    if not args.all:
        print("(curated families: glm, gpt, claude, deepseek, grok, gemini, solar, plus enabledModels picks — use --all for everything)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
