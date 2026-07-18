"""Apply fp8 embedding fix after ComfyUI has imported torch (prestartup hook)."""
import sys
from pathlib import Path

fix_DIR = Path("/opt/comfyui-fixes")
if FIX_DIR.is_dir():
    sys.path.insert(0, str(FIX_DIR))
try:
    import fp8_embed_fix  # noqa: F401
    print("[00_fp8_embed_fix] prestartup applied", flush=True)
except Exception as e:
    print(f"[00_fp8_embed_fix] prestartup failed: {e}", flush=True)
