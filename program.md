# Experiment Program

Use this as the default decision rule for automated or semi-automated experimentation.

## Core Rule

Optimize for the best exact final roundtrip `val_bpb` that still fits the challenge rules. Do not keep runs just because pre-quant loss looked good.

## Status Semantics

- `keep`: valid, comparable run that is a new best or clearly changes the next search direction
- `discard`: valid, comparable run with no clear follow-up value
- `invalid`: completed run but metric is not trustworthy or not challenge-comparable
- `crash`: command failed or the output is too broken to score

## Mark A Run `invalid` When

- `final_int8_zlib_roundtrip_exact` is missing
- artifact bytes exceed `16,000,000`
- dataset, tokenizer, or eval regime is not comparable
- the log is incomplete enough that score or artifact accounting cannot be trusted

## Keep / Discard Heuristic

- Keep clear improvements in exact final `val_bpb`
- Keep near-ties only when they buy byte headroom, stability, or a useful new search branch
- Discard clean negative results once the hypothesis is answered

## Run Hygiene

- Write one short hypothesis before each run
- Change one axis at a time unless the run is intentionally bundled
- Record one short note after each run: what changed, what happened, what to try next
- Prefer three decisive cheap runs over one expensive ambiguous run
