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
cat > "$OUT_DIR/frontier_digest.md" <<'HEADER'
# Frontier Digest
HEADER
echo "Generated at $(date -u)" >> "$OUT_DIR/frontier_digest.md"
echo "" >> "$OUT_DIR/frontier_digest.md"

# Pull the upstream README leaderboard table
echo "## Official Leaderboard (from README)" >> "$OUT_DIR/frontier_digest.md"
gh api "repos/$REPO/contents/README.md" --jq '.content' 2>/dev/null \
  | base64 -d 2>/dev/null \
  | sed -n '/^## Leaderboard/,/^## /p' \
  | head -30 >> "$OUT_DIR/frontier_digest.md" || true

# Summarize key techniques from top merged record PRs
echo "" >> "$OUT_DIR/frontier_digest.md"
echo "## Key Techniques from Recent Records" >> "$OUT_DIR/frontier_digest.md"
gh pr list --state merged --limit 10 -R "$REPO" \
  --search "Record in:title" \
  --json number,title,url,mergedAt,body \
  --jq '.[] | "### PR #\(.number): \(.title)\nMerged: \(.mergedAt)\nURL: \(.url)\n\(.body[0:500])\n---"' \
  >> "$OUT_DIR/frontier_digest.md" 2>/dev/null || true

echo "Upstream sync complete."
