#!/usr/bin/env bash
set -euo pipefail

# scripts/sync_upstream_context.sh
# Syncs live frontier context from the official parameter-golf repo via gh CLI

REPO="openai/parameter-golf"
OUT_DIR="context/upstream"

mkdir -p "$OUT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh (GitHub CLI) is required but not installed." >&2
  exit 1
fi

echo "Fetching Issue #140 (The live frontier)..."
gh issue view 140 -R "$REPO" > "$OUT_DIR/issue_140.md" 2>/dev/null || true
# Sometimes issues have comments with important rules or updates
gh issue view 140 -R "$REPO" --comments >> "$OUT_DIR/issue_140.md" 2>/dev/null || true

echo "Fetching recent merged PRs..."
echo "# Recent Merged PRs" > "$OUT_DIR/pr_digest.md"
gh pr list --state merged --limit 15 -R "$REPO" --json number,title,url,mergedAt \
  --jq '.[] | "- [\(.title)](\(.url)) (Merged: \(.mergedAt))"' >> "$OUT_DIR/pr_digest.md" || true

echo "Fetching recent open PRs (proposals)..."
echo -e "\n# Recent Open PRs" >> "$OUT_DIR/pr_digest.md"
gh pr list --state open --limit 10 -R "$REPO" --json number,title,url,createdAt \
  --jq '.[] | "- [\(.title)](\(.url)) (Created: \(.createdAt))"' >> "$OUT_DIR/pr_digest.md" || true

echo "Extracting frontier digest..."
# We can just copy the leaderboard part from README or issue 140
echo "# Frontier Digest" > "$OUT_DIR/frontier_digest.md"
echo "Generated at $(date -u)" >> "$OUT_DIR/frontier_digest.md"
echo "" >> "$OUT_DIR/frontier_digest.md"
echo "Please refer to issue_140.md for the canonical, live SOTA rules and leaderboard." >> "$OUT_DIR/frontier_digest.md"

echo "Upstream sync complete."
