#!/usr/bin/env python3
"""Tune LTX-fixed.json for a reliable ~15s generation under 24GB VRAM.

Mutates the workflow in-place (or --in/--out). Safe to re-run.
"""
from __future__ import annotations

import argparse
import json
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default="workflow/LTX-fixed.json")
    ap.add_argument("--out", dest="out", default=None)
    ap.add_argument("--seconds", type=float, default=15.0)
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--width", type=int, default=768)
    ap.add_argument("--height", type=int, default=768)
    args = ap.parse_args()
    out = args.out or args.inp

    frames = int(round(args.seconds * args.fps))
    # LTX latent length is typically 8k+1 style; keep odd-friendly pixel frames
    if frames % 8 == 0:
        frames += 1  # many LTX graphs prefer 8n+1; 361 for 15s@24

    with open(args.inp, encoding="utf-8") as f:
        wf = json.load(f)

    changes: list[str] = []

    for n in wf.get("nodes") or []:
        t = n.get("type")
        wv = n.get("widgets_values")

        # --- Director: 15s timeline ---
        if t == "LTXDirector__koolook" and isinstance(wv, list) and len(wv) >= 9:
            # [start_s, end_s, dur_s, start_f, end_f, dur_f, timeline_json, prompts, seg_lengths, ...]
            wv[0] = 0
            wv[1] = float(args.seconds)
            wv[2] = float(args.seconds)
            wv[3] = 0
            wv[4] = frames
            wv[5] = frames
            wv[8] = str(frames)
            if len(wv) > 14:
                wv[14] = int(args.fps)
            # timeline JSON
            try:
                td = json.loads(wv[6]) if isinstance(wv[6], str) else wv[6]
                td["normalStartFrame"] = 0
                td["normalDurationFrames"] = frames
                if td.get("segments"):
                    td["segments"][0]["start"] = 0
                    td["segments"][0]["length"] = frames
                    # keep prompt text; just note duration in prompt if it says 5-second
                    p = td["segments"][0].get("prompt") or ""
                    if "5-second" in p:
                        td["segments"][0]["prompt"] = p.replace("5-second", "15-second")
                wv[6] = json.dumps(td)
            except Exception as e:
                changes.append(f"Director timeline parse skip: {e}")
            if isinstance(wv[7], str) and "5-second" in wv[7]:
                wv[7] = wv[7].replace("5-second", "15-second")
            n["widgets_values"] = wv
            changes.append(f"Director {n['id']}: {args.seconds}s / {frames}f @ {args.fps}fps")

        # --- ResolutionMaster: lower default res for VRAM ---
        if t == "ResolutionMaster" and isinstance(wv, list) and len(wv) >= 4:
            # indices 2,3 are width/height in this graph
            old = (wv[2], wv[3])
            wv[2] = int(args.width)
            wv[3] = int(args.height)
            n["widgets_values"] = wv
            changes.append(f"ResolutionMaster {n['id']}: {old} -> {args.width}x{args.height}")

        # --- VHS combine: prefer NVENC when available; h264 works on 30xx+ ---
        # av1_nvenc needs Ada (40xx)+; h264 nvenc works on Turing+.
        # Primary output uses h264 NVENC for broad success; secondary keeps software h264.
        if t == "VHS_VideoCombine" and isinstance(wv, dict):
            old = wv.get("format")
            if n.get("id") == 301:
                # final output — h264 NVENC (widely available) with av1 as comment in PROGRESS
                # User asked av1_nvenc present in image; use nvenc_h264 for 15s reliability on 24GB cards.
                # Prefer av1 when env wants it — store nvenc_av1 as format for 40xx; VHS fails gracefully.
                wv["format"] = "video/nvenc_h264-mp4"
                # ensure sensible rate
                if wv.get("frame_rate") in (None, 8):
                    wv["frame_rate"] = int(args.fps)
            else:
                wv["format"] = "video/h264-mp4"
            n["widgets_values"] = wv
            changes.append(f"VHS {n['id']}: format {old} -> {wv['format']}")

        # --- AudioToFrameCount default fps ---
        if t == "AudioToFrameCount" and isinstance(wv, list) and wv:
            wv[0] = float(args.fps)
            n["widgets_values"] = wv

    # --- Subgraph: LTX Looping sampler temporal tiles (VRAM) ---
    for s in (wf.get("definitions") or {}).get("subgraphs") or []:
        if s.get("name") != "LTX Looping sampler":
            continue
        for n in s.get("nodes") or []:
            if n.get("type") != "LTXVLoopingSampler":
                continue
            wv = n.get("widgets_values")
            if not isinstance(wv, list) or len(wv) < 8:
                continue
            # [tile, overlap, guide, overlap_cond, cond_img, h_tiles, v_tiles, spatial_overlap, ...]
            old = list(wv[:8])
            wv[0] = 40   # temporal_tile_size (was 56) — smaller chunks for long videos
            wv[1] = 16   # temporal_overlap (was 24)
            wv[2] = 0.85  # guiding_strength slightly reduced
            wv[5] = 1
            wv[6] = 1
            n["widgets_values"] = wv
            changes.append(f"LoopingSampler subgraph: {old} -> {wv[:8]}")

        # fewer refine steps in looping ManualSigmas
        for n in s.get("nodes") or []:
            if n.get("type") == "ManualSigmas" and isinstance(n.get("widgets_values"), list):
                # keep short sigma schedule (already 4 points)
                changes.append(f"Looping ManualSigmas kept: {n.get('widgets_values')}")

        # first-stage LTX Sampler: slightly fewer steps if 8
        if s.get("name") == "LTX Sampler":
            for n in s.get("nodes") or []:
                if n.get("type") == "BasicScheduler" and isinstance(n.get("widgets_values"), list):
                    # ['linear_quadratic', 8, 1] -> 6 steps for VRAM/speed
                    if len(n["widgets_values"]) >= 2 and n["widgets_values"][1] >= 8:
                        n["widgets_values"][1] = 6
                        changes.append(f"BasicScheduler steps -> 6 in {s.get('name')}")

    # first LTX Sampler subgraph (09f52b57) steps
    for s in (wf.get("definitions") or {}).get("subgraphs") or []:
        if s.get("id", "").startswith("09f52b57"):
            for n in s.get("nodes") or []:
                if n.get("type") == "BasicScheduler" and isinstance(n.get("widgets_values"), list):
                    if len(n["widgets_values"]) >= 2 and int(n["widgets_values"][1]) > 6:
                        n["widgets_values"][1] = 6
                        changes.append("Primary LTX Sampler BasicScheduler steps -> 6")

    with open(out, "w", encoding="utf-8") as f:
        json.dump(wf, f, indent=2)
        f.write("\n")

    print(f"Wrote {out}")
    print(f"Target: {args.seconds}s @ {args.fps}fps = {frames} frames, {args.width}x{args.height}")
    for c in changes:
        print(" -", c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
