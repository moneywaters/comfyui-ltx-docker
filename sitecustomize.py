"""Intentionally minimal.

Importing torch before ComfyUI configures CUDA causes:
  Allocator backend parsed at runtime != allocator backend parsed at load time

The fp8 fix is applied via custom_nodes/00_fp8_embed_fix/prestartup_script.py
after ComfyUI's normal torch bootstrap.
"""
