"""Auto-loaded by Python if this directory is on PYTHONPATH / site-packages.

Applies ComfyUI runtime fixes before any user code runs.
"""
try:
    import fp8_embed_fix  # noqa: F401
except Exception as exc:
    print(f"[sitecustomize] fp8_embed_fix import failed: {exc}", flush=True)
