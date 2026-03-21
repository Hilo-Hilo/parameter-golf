#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

FIELDS = [
    "ts_utc",
    "experiment_id",
    "run_id",
    "track",
    "trainer",
    "branch",
    "commit",
    "status",
    "exit_code",
    "exact_final_val_bpb",
    "pre_quant_val_bpb",
    "final_val_loss",
    "pre_quant_val_loss",
    "bytes_total",
    "bytes_code",
    "bytes_model",
    "wallclock_seconds",
    "step_stop",
    "log_path",
    "submission_path",
    "notes",
]

STEP_VAL_RE = re.compile(r"step:(\d+)/(\d+)\s+val_loss:([0-9.]+)\s+val_bpb:([0-9.]+)")
STEP_TRAIN_RE = re.compile(r"step:(\d+)/(\d+)\s+train_loss:([0-9.]+)\s+train_time:(\d+)ms")
TRAIN_TIME_RE = re.compile(r"train_time:(\d+)ms")
STOP_RE = re.compile(r"stopping_early:\s+wallclock_cap\s+train_time:(\d+)ms\s+step:(\d+)/(\d+)")
FINAL_RE = re.compile(r"final_int8_zlib_roundtrip\s+val_loss:([0-9.]+)\s+val_bpb:([0-9.]+)")
FINAL_EXACT_RE = re.compile(r"final_int8_zlib_roundtrip_exact\s+val_loss:([0-9.]+)\s+val_bpb:([0-9.]+)")
RUN_ID_RE = re.compile(r"run_id:(\S+)")
CODE_SIZE_RE = re.compile(r"Code size:\s*(\d+)\s+bytes", re.IGNORECASE)
TOTAL_SIZE_RE = re.compile(r"Total submission size int8\+zlib:\s*(\d+)\s+bytes", re.IGNORECASE)
MODEL_BYTES_RE = re.compile(
    r"(?:Serialized model int8\+zlib|serialized_model_int8_zlib:)\s*:?\s*(\d+)\s+bytes",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Parse Parameter Golf train logs into JSON or TSV.")
    parser.add_argument("log_path", help="Path to the train log to parse.")
    parser.add_argument("--submission", help="Optional submission.json path.")
    parser.add_argument("--code-path", help="Optional trainer path for code byte accounting.")
    parser.add_argument("--ts-utc", help="UTC timestamp to write into the output row.")
    parser.add_argument("--experiment-id", help="Experiment identifier.")
    parser.add_argument("--run-id", help="Run identifier. Overrides parsed run_id.")
    parser.add_argument("--track", default="", help="Track label.")
    parser.add_argument("--trainer", default="", help="Trainer path or label.")
    parser.add_argument("--branch", default="", help="Git branch name.")
    parser.add_argument("--commit", default="", help="Git commit hash.")
    parser.add_argument("--status", default="discard", choices=["keep", "discard", "invalid", "crash"])
    parser.add_argument("--exit-code", type=int, default=0, help="Exit code from the wrapped training command.")
    parser.add_argument(
        "--process-wallclock-seconds",
        type=float,
        help="Actual elapsed wallclock for the wrapped process, captured by the experiment runner.",
    )
    parser.add_argument("--notes", default="", help="Free-form notes for the ledger row.")
    parser.add_argument("--max-bytes", type=int, default=16_000_000, help="Artifact size cap for invalidation.")
    parser.add_argument("--format", choices=["json", "tsv"], default="json")
    return parser.parse_args()


def load_json(path_str: str | None) -> dict:
    if not path_str:
        return {}
    path = Path(path_str)
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


def maybe_file_size(path_str: str | None) -> int | None:
    if not path_str:
        return None
    path = Path(path_str)
    if not path.is_file():
        return None
    return path.stat().st_size


def to_float(value) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def to_int(value) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def choose(*values):
    for value in values:
        if value not in (None, ""):
            return value
    return None


def parse_log(path: Path) -> dict[str, object]:
    metrics: dict[str, object] = {}
    max_train_time_ms = 0
    max_step = 0

    for raw_line in path.read_text(errors="replace").splitlines():
        if match := RUN_ID_RE.search(raw_line):
            metrics["run_id"] = match.group(1)
        if match := STEP_VAL_RE.search(raw_line):
            step = int(match.group(1))
            max_step = max(max_step, step)
            metrics["pre_quant_val_loss"] = float(match.group(3))
            metrics["pre_quant_val_bpb"] = float(match.group(4))
        if match := STEP_TRAIN_RE.search(raw_line):
            step = int(match.group(1))
            max_step = max(max_step, step)
            max_train_time_ms = max(max_train_time_ms, int(match.group(4)))
        if match := TRAIN_TIME_RE.search(raw_line):
            max_train_time_ms = max(max_train_time_ms, int(match.group(1)))
        if match := STOP_RE.search(raw_line):
            max_train_time_ms = max(max_train_time_ms, int(match.group(1)))
            max_step = max(max_step, int(match.group(2)))
        if match := FINAL_RE.search(raw_line):
            metrics["final_val_loss"] = float(match.group(1))
            metrics["final_val_bpb"] = float(match.group(2))
        if match := FINAL_EXACT_RE.search(raw_line):
            metrics["final_val_loss"] = float(match.group(1))
            metrics["exact_final_val_bpb"] = float(match.group(2))
        if match := CODE_SIZE_RE.search(raw_line):
            metrics["bytes_code"] = int(match.group(1))
        if match := TOTAL_SIZE_RE.search(raw_line):
            metrics["bytes_total"] = int(match.group(1))
        if match := MODEL_BYTES_RE.search(raw_line):
            metrics["bytes_model"] = int(match.group(1))

    if max_train_time_ms > 0:
        metrics["wallclock_seconds"] = max_train_time_ms / 1000.0
    if max_step > 0:
        metrics["step_stop"] = max_step
    return metrics


def finalize_status(
    requested_status: str,
    exit_code: int,
    exact_final_val_bpb: float | None,
    bytes_total: int | None,
    max_bytes: int,
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    if exit_code != 0:
        reasons.append(f"exit_code={exit_code}")
        return "crash", reasons
    if exact_final_val_bpb is None:
        reasons.append("missing_exact_final_val_bpb")
    if bytes_total is not None and bytes_total > max_bytes:
        reasons.append(f"bytes_total>{max_bytes}")
    if reasons:
        return "invalid", reasons
    return requested_status, reasons


def build_row(args: argparse.Namespace) -> dict[str, object]:
    log_path = Path(args.log_path)
    parsed = parse_log(log_path)
    submission = load_json(args.submission)

    exact_final_val_bpb = choose(
        to_float(submission.get("val_bpb")),
        to_float(parsed.get("exact_final_val_bpb")),
    )
    final_val_loss = choose(
        to_float(submission.get("val_loss")),
        to_float(parsed.get("final_val_loss")),
    )
    pre_quant_val_bpb = choose(
        to_float(submission.get("pre_quant_val_bpb")),
        to_float(parsed.get("pre_quant_val_bpb")),
    )
    pre_quant_val_loss = choose(
        to_float(submission.get("pre_quant_val_loss")),
        to_float(parsed.get("pre_quant_val_loss")),
    )
    bytes_model = choose(
        to_int(submission.get("bytes_model_int8_zlib")),
        to_int(parsed.get("bytes_model")),
    )
    bytes_code = choose(
        to_int(submission.get("bytes_code")),
        to_int(parsed.get("bytes_code")),
        maybe_file_size(args.code_path),
    )
    bytes_total = choose(
        to_int(submission.get("bytes_total")),
        to_int(parsed.get("bytes_total")),
        bytes_model + bytes_code if bytes_model is not None and bytes_code is not None else None,
    )
    wallclock_seconds = choose(
        to_float(args.process_wallclock_seconds),
        to_float(submission.get("wallclock_seconds")),
        to_float(parsed.get("wallclock_seconds")),
    )
    step_stop = choose(
        to_int(submission.get("step_stop")),
        to_int(parsed.get("step_stop")),
    )

    status, reasons = finalize_status(
        requested_status=args.status,
        exit_code=args.exit_code,
        exact_final_val_bpb=to_float(exact_final_val_bpb),
        bytes_total=to_int(bytes_total),
        max_bytes=args.max_bytes,
    )

    notes_parts = [part for part in [args.notes, ", ".join(reasons) if reasons else ""] if part]

    row = {
        "ts_utc": args.ts_utc or "",
        "experiment_id": args.experiment_id or "",
        "run_id": args.run_id or parsed.get("run_id") or "",
        "track": args.track,
        "trainer": args.trainer,
        "branch": args.branch,
        "commit": args.commit,
        "status": status,
        "exit_code": args.exit_code,
        "exact_final_val_bpb": exact_final_val_bpb,
        "pre_quant_val_bpb": pre_quant_val_bpb,
        "final_val_loss": final_val_loss,
        "pre_quant_val_loss": pre_quant_val_loss,
        "bytes_total": bytes_total,
        "bytes_code": bytes_code,
        "bytes_model": bytes_model,
        "wallclock_seconds": wallclock_seconds,
        "step_stop": step_stop,
        "log_path": str(log_path),
        "submission_path": args.submission or "",
        "notes": " | ".join(notes_parts),
    }
    return row


def write_json(row: dict[str, object]) -> None:
    json.dump(row, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def write_tsv(row: dict[str, object]) -> None:
    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(["" if row.get(field) is None else row.get(field) for field in FIELDS])


def main() -> int:
    args = parse_args()
    row = build_row(args)
    if args.format == "json":
        write_json(row)
    else:
        write_tsv(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
