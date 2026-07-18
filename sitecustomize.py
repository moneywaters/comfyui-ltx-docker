"""Auto-loaded from site-packages (and optionally PYTHONPATH).

Applies ComfyUI runtime fixes before any user code runs.
Logs go to stderr only — never pollute stdout (breaks Docker $(python -c) captures).
"""
import sys

try:
    import fp8_embed_fix  # noqa: F401
except Exception as exc:
    print(f"[sitecustomize] fp8_embed_fix import failed: {exc}", flush=True, file=sys.stderr)
