"""Fix fp8 text-encoder embeddings on CUDA (Gemma / DualCLIPLoader).

ComfyUI's Embedding path can leave Float8_e4m3fn weights uncast when
encode_from_tokens requests out_dtype=float32, which then fails with:

  RuntimeError: "index_select_cuda" not implemented for 'Float8_e4m3fn'

This patch casts embedding weights to a CUDA-friendly dtype before
torch.embedding runs. Safe no-op for non-fp8 weights.

Loaded via PYTHONPATH / sitecustomize from start.sh before main.py.
"""
from __future__ import annotations

import logging

log = logging.getLogger("fp8_embed_fix")

_FP8_TYPES = set()


def _collect_fp8_types():
    import torch
    for name in ("float8_e4m3fn", "float8_e4m3fnuz", "float8_e5m2", "float8_e5m2fnuz"):
        dt = getattr(torch, name, None)
        if dt is not None:
            _FP8_TYPES.add(dt)


def apply() -> bool:
    """Patch torch.nn.functional.embedding (always available) and comfy.ops if loaded."""
    try:
        import torch
        import torch.nn.functional as F
    except Exception as exc:
        log.warning("fp8 embed fix skipped (torch import): %s", exc)
        return False

    _collect_fp8_types()
    if not _FP8_TYPES:
        log.info("fp8 embed fix: no fp8 dtypes in this torch build")
        return False

    patched = False

    # Primary fix: wrap F.embedding so any caller (ComfyUI or torch) is safe
    if not getattr(F.embedding, "_fp8_embed_fixed", False):
        _orig_emb = F.embedding

        def _embedding(input, weight, *args, **kwargs):  # noqa: ANN001
            if weight is not None and getattr(weight, "dtype", None) in _FP8_TYPES:
                target = torch.float16 if getattr(weight, "is_cuda", False) else torch.float32
                weight = weight.to(dtype=target)
            return _orig_emb(input, weight, *args, **kwargs)

        _embedding._fp8_embed_fixed = True  # type: ignore[attr-defined]
        F.embedding = _embedding  # type: ignore[assignment]
        torch.nn.functional.embedding = _embedding  # type: ignore[assignment]
        patched = True
        log.info("fp8 embed fix: wrapped torch.nn.functional.embedding")

    # Optional: also patch comfy.ops.Embedding if ComfyUI is already importable
    try:
        from comfy import ops  # type: ignore

        emb_cls = getattr(ops, "Embedding", None) or getattr(
            getattr(ops, "manual_cast", None), "Embedding", None
        )
        if emb_cls is not None and hasattr(emb_cls, "forward_comfy_cast_weights"):
            _orig = emb_cls.forward_comfy_cast_weights

            def _forward_cast(self, input, out_dtype=None, *args, **kwargs):  # noqa: ANN001
                weight = self.weight
                if weight is not None and weight.dtype in _FP8_TYPES:
                    target = out_dtype or torch.float16
                    if target is None or target in _FP8_TYPES:
                        target = torch.float16
                    weight = weight.to(dtype=target)
                    return F.embedding(
                        input,
                        weight,
                        self.padding_idx,
                        self.max_norm,
                        self.norm_type,
                        self.scale_grad_by_freq,
                        self.sparse,
                    )
                return _orig(self, input, out_dtype, *args, **kwargs)

            emb_cls.forward_comfy_cast_weights = _forward_cast  # type: ignore[method-assign]
            patched = True
            log.info("fp8 embed fix: patched comfy.ops.Embedding.forward_comfy_cast_weights")
    except Exception:
        # ComfyUI package not on sys.path until runtime cwd=/opt/ComfyUI — OK
        pass

    return patched


# Auto-apply when imported as sitecustomize companion.
# Always print to stderr so shell $(python -c ...) stdout stays clean.
try:
    if apply():
        print("[fp8_embed_fix] applied", flush=True, file=__import__("sys").stderr)
    else:
        print("[fp8_embed_fix] not applied", flush=True, file=__import__("sys").stderr)
except Exception as e:  # never block ComfyUI boot
    print(f"[fp8_embed_fix] error: {e}", flush=True, file=__import__("sys").stderr)
