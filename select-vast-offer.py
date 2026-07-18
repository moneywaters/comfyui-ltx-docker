#!/usr/bin/env python3
"""Pick a Vast.ai offer optimized for large HuggingFace model downloads.

Models for this image are ~48GB. A 200 Mbps host takes ~30+ minutes;
a 3000+ Mbps host finishes in a few minutes. Always weight inet_down first.

Usage:
  vastai search offers '...' --raw | python3 select-vast-offer.py
  vastai search offers '...' --raw | python3 select-vast-offer.py --mode full
  vastai search offers '...' --raw | python3 select-vast-offer.py --mode smoke --print-table

Exit 0 prints only the offer id on stdout (for shell capture).
Ranking details go to stderr.
"""
from __future__ import annotations

import argparse
import json
import sys

# Newer / workstation GPUs as a soft proxy for AVX2 host CPUs (PyTorch 2.5 needs AVX2).
GPU_PREFER = (
    "RTX 5090",
    "RTX 5080",
    "RTX 5070",
    "RTX 5060",
    "RTX 4090",
    "RTX 4080",
    "RTX 4070",
    "RTX 4060",
    "RTX 3090",
    "RTX 3080",
    "RTX 3070",
    "RTX 3060",
    "RTX A6000",
    "RTX A5000",
    "RTX A4000",
    "RTX PRO",
    "L40",
    "A40",
    "A6000",
)

# CPUs that often lack AVX2 — reject when cpu_name is present.
CPU_REJECT_SUBSTR = (
    "pentium",
    "celeron",
    "atom",
    "e3-12",  # very old xeons sometimes lack avx2; keep soft — not all do
)


def gpu_rank(name: str | None) -> int:
    name = name or ""
    for i, p in enumerate(GPU_PREFER):
        if p in name:
            return i
    return 80


def cpu_ok(name: str | None) -> bool:
    n = (name or "").lower()
    if not n:
        return True
    return not any(s in n for s in ("pentium", "celeron", "atom"))


def dl_hours(mbps: float, gigabytes: float = 50.0) -> float:
    """Rough wall time for gigabytes over megabit/s link (payload only)."""
    if mbps <= 0:
        return 999.0
    return (gigabytes * 8 * 1000.0) / mbps / 3600.0


def dl_eta(mbps: float, gigabytes: float = 50.0) -> str:
    h = dl_hours(mbps, gigabytes)
    if h >= 900:
        return "n/a"
    if h < 1.0:
        return f"{h * 60:.0f}m"
    return f"{h:.1f}h"


def score_offer(o: dict, mode: str) -> tuple:
    """Lower is better."""
    dl = float(o.get("inet_down") or 0)
    dph = float(o.get("dph_total") or 99)
    gr = gpu_rank(o.get("gpu_name"))
    rel = float(o.get("reliability") or 0)

    if mode == "full":
        # Primary: download speed (negate so higher dl sorts first via lower score).
        # Secondary: modern GPU. Tertiary: price. Reliability as soft bonus.
        return (-dl, gr, dph, -rel)
    # smoke: still prefer decent DL for the ~8GB image pull, then price
    return (-min(dl, 2000.0), dph, gr, -rel)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=("full", "smoke"), default="full")
    ap.add_argument("--min-dl", type=float, default=None, help="Min inet_down Mbps")
    ap.add_argument("--max-dph", type=float, default=None)
    ap.add_argument("--min-gpu-ram", type=float, default=None)
    ap.add_argument("--print-table", action="store_true")
    ap.add_argument("--top", type=int, default=12)
    args = ap.parse_args()

    if args.min_dl is None:
        args.min_dl = 800.0 if args.mode == "full" else 200.0
    if args.max_dph is None:
        args.max_dph = 0.35 if args.mode == "full" else 0.15
    if args.min_gpu_ram is None:
        args.min_gpu_ram = 12.0 if args.mode == "full" else 10.0

    raw = sys.stdin.read()
    if not raw.strip():
        print("No offers on stdin", file=sys.stderr)
        return 2
    offers = json.loads(raw)
    if not isinstance(offers, list):
        print("Expected JSON list of offers", file=sys.stderr)
        return 2

    filtered = []
    for o in offers:
        dl = float(o.get("inet_down") or 0)
        dph = float(o.get("dph_total") or 99)
        gram = float(o.get("gpu_ram") or 0)
        if dl < args.min_dl:
            continue
        if dph > args.max_dph:
            continue
        if gram and gram < args.min_gpu_ram:
            continue
        if not cpu_ok(o.get("cpu_name")):
            continue
        filtered.append(o)

    if not filtered:
        print(
            f"No offers after filters (min_dl={args.min_dl} max_dph={args.max_dph} min_gpu_ram={args.min_gpu_ram}). "
            "Relax --min-dl or raise --max-dph.",
            file=sys.stderr,
        )
        return 1

    ranked = sorted(filtered, key=lambda o: score_offer(o, args.mode))

    if args.print_table or True:
        print(
            f"# mode={args.mode} candidates={len(filtered)}/{len(offers)} "
            f"min_dl>={args.min_dl} max_dph<={args.max_dph}",
            file=sys.stderr,
        )
        print(
            f"{'id':>10} | {'gpu':22} | {'dl_Mbps':>8} | {'~50GB':>7} | {'$/hr':>7} | {'rel':>5} | location | cpu",
            file=sys.stderr,
        )
        for o in ranked[: args.top]:
            dl = float(o.get("inet_down") or 0)
            print(
                "%10s | %-22s | %8.0f | %7s | $%5.3f | %5.2f | %s | %s"
                % (
                    o.get("id"),
                    (o.get("gpu_name") or "")[:22],
                    dl,
                    dl_eta(dl),
                    float(o.get("dph_total") or 0),
                    float(o.get("reliability") or 0),
                    (o.get("geolocation") or "")[:18],
                    (o.get("cpu_name") or "")[:32],
                ),
                file=sys.stderr,
            )

    best = ranked[0]
    dl = float(best.get("inet_down") or 0)
    print(
        "# SELECTED id=%s gpu=%s inet_down=%.0fMbps (~50GB ~%s) dph=$%.4f loc=%s cpu=%s"
        % (
            best.get("id"),
            best.get("gpu_name"),
            dl,
            dl_eta(dl),
            float(best.get("dph_total") or 0),
            best.get("geolocation"),
            best.get("cpu_name"),
        ),
        file=sys.stderr,
    )
    print(best["id"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
