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
    try:
        import torch
        import torch.nn.functional as F
        from comfy import ops  # type: ignore
    except Exception as exc:
        log.warning("fp8 embed fix skipped (import): %s", exc)
        return False

    _collect_fp8_types()
    if not _FP8_TYPES:
        log.info("fp8 embed fix: no fp8 dtypes in this torch build")
        return False

    # --- Patch Embedding.forward_comfy_cast_weights if present ---
    emb_cls = getattr(ops, "Embedding", None) or getattr(getattr(ops, "manual_cast", None), "Embedding", None)
    patched = False

    if emb_cls is not None and hasattr(emb_cls, "forward_comfy_cast_weights"):
        _orig = emb_cls.forward_comfy_cast_weights

        def _forward_cast(self, input, out_dtype=None, *args, **kwargs):  # noqa: ANN001
            weight = self.weight
            if weight is not None and weight.dtype in _FP8_TYPES:
                target = out_dtype or torch.float16
                if target is None or target in _FP8_TYPES:
                    target = torch.float16
                # Keep on same device; cast for index_select
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

    # --- Also wrap F.embedding as a belt-and-suspenders fallback ---
    if not getattr(F.embedding, "_fp8_embed_fixed", False):
        _orig_emb = F.embedding

        def _embedding(input, weight, *args, **kwargs):  # noqa: ANN001
            if weight is not None and getattr(weight, "dtype", None) in _FP8_TYPES:
                target = torch.float16 if weight.is_cuda else torch.float32
                weight = weight.to(dtype=target)
            return _orig_emb(input, weight, *args, **kwargs)

        _embedding._fp8_embed_fixed = True  # type: ignore[attr-defined]
        F.embedding = _embedding  # type: ignore[assignment]
        torch.nn.functional.embedding = _embedding  # type: ignore[assignment]
        patched = True
        log.info("fp8 embed fix: wrapped torch.nn.functional.embedding")

    return patched


# Auto-apply when imported as sitecustomize companion
try:
    if apply():
        print("[fp8_embed_fix] applied", flush=True)
    else:
        print("[fp8_embed_fix] not applied", flush=True)
except Exception as e:  # never block ComfyUI boot
    print(f"[fp8_embed_fix] error: {e}", flush=True)
