#!/usr/bin/env python3
from __future__ import annotations

import math
import sys
from pathlib import Path
from types import SimpleNamespace

import torch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from train_gpt import GPT, eval_val, eval_val_sliding


def sliding_coverage(total_tokens: int, seq_len: int, stride: int) -> list[int]:
    covered = []
    for ws in range(0, total_tokens, stride):
        wlen = min(ws + seq_len, total_tokens) - ws
        start = 0 if ws == 0 else max(wlen - stride, 0)
        covered.extend(range(ws + start, ws + wlen))
    return covered


def assert_cover_all(total_tokens: int, seq_len: int, stride: int) -> None:
    covered = sliding_coverage(total_tokens, seq_len, stride)
    if len(covered) != total_tokens:
        raise AssertionError(f"covered {len(covered)} tokens, expected {total_tokens}")
    unique = sorted(set(covered))
    if unique != list(range(total_tokens)):
        raise AssertionError("sliding coverage is missing or duplicates tokens")


def main() -> None:
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required for this smoke check (it uses train_gpt eval path).")

    device = torch.device("cuda")
    torch.manual_seed(42)

    args = SimpleNamespace(train_seq_len=16, val_batch_size=16)
    base_bytes = torch.tensor([1, 1, 1, 1, 1], dtype=torch.int16, device=device)
    has_space = torch.zeros((5,), dtype=torch.bool, device=device)
    boundary = torch.zeros((5,), dtype=torch.bool, device=device)
    model = GPT(
        vocab_size=5,
        num_layers=2,
        model_dim=32,
        num_heads=4,
        num_kv_heads=2,
        mlp_mult=2,
        tie_embeddings=True,
        tied_embed_init_std=0.005,
        logit_softcap=30.0,
        rope_base=10000.0,
        qk_gain_init=1.5,
    ).to(device).bfloat16()

    val_tokens = torch.arange(16 * 4 + 1, device=device, dtype=torch.long) % 5
    val_loss_std, val_bpb_std = eval_val(
        args,
        model,
        rank=0,
        world_size=1,
        device=device,
        grad_accum_steps=1,
        val_tokens=val_tokens,
        base_bytes_lut=base_bytes,
        has_leading_space_lut=has_space,
        is_boundary_token_lut=boundary,
    )
    val_loss_slide, val_bpb_slide = eval_val_sliding(
        args,
        model,
        rank=0,
        world_size=1,
        device=device,
        val_tokens=val_tokens,
        base_bytes_lut=base_bytes,
        has_leading_space_lut=has_space,
        is_boundary_token_lut=boundary,
        stride=args.train_seq_len,
        batch_seqs=8,
    )
    if not math.isclose(val_loss_std, val_loss_slide, rel_tol=1e-7, abs_tol=1e-7):
        raise AssertionError("sliding stride==seq_len must match non-overlap eval")
    if not math.isclose(val_bpb_std, val_bpb_slide, rel_tol=1e-7, abs_tol=1e-7):
        raise AssertionError("sliding stride==seq_len must match non-overlap eval")

    assert_cover_all(total_tokens=val_tokens.numel() - 1, seq_len=args.train_seq_len, stride=4)
    print("smoke_sliding_eval: PASS")


if __name__ == "__main__":
    main()
