#!/usr/bin/env bash
# review-pr.sh <pr-number>
#
# Runs automated code review on a PR using Codex + Claude Code.
# Posts review comments directly on the PR.
# Called by check-agents.sh when a PR is created.

set -euo pipefail
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

PR_NUMBER="${1:?PR number required}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Reviewing PR #$PR_NUMBER..."

# Get PR diff
PR_DIFF=$(gh pr diff "$PR_NUMBER" 2>/dev/null | head -500)
PR_TITLE=$(gh pr view "$PR_NUMBER" --json title -q .title)
PR_BODY=$(gh pr view "$PR_NUMBER" --json body -q .body)

REVIEW_PROMPT="You are a senior engineer doing a code review. Be direct and concise.

PR Title: $PR_TITLE
PR Description: $PR_BODY

Diff:
$PR_DIFF

Review this PR. Focus on:
1. Logic errors, edge cases, race conditions
2. Missing error handling
3. TypeScript type safety issues
4. Performance problems
5. Security issues

Format your response as:
VERDICT: APPROVE or REQUEST_CHANGES
ISSUES:
- [CRITICAL] description (only if blocking)
- [WARNING] description (non-blocking)
SUMMARY: one sentence

Only mark CRITICAL if it would cause a bug in production. Be brief."

# Codex review
log "Running Codex review..."
CODEX_REVIEW=$(cd "$REPO_ROOT" && codex exec "$REVIEW_PROMPT" 2>/dev/null | tail -20)

# Claude Code review  
log "Running Claude Code review..."
CLAUDE_REVIEW=$(cd "$REPO_ROOT" && claude --dangerously-skip-permissions -p "$REVIEW_PROMPT" 2>/dev/null | tail -20)

# Post combined review as PR comment
COMMENT="## 🤖 Automated Code Review

### Codex Review
\`\`\`
$CODEX_REVIEW
\`\`\`

### Claude Code Review
\`\`\`
$CLAUDE_REVIEW
\`\`\`

---
*Reviews by Codex + Claude Code via .clawdbot/review-pr.sh*"

gh pr comment "$PR_NUMBER" --body "$COMMENT" 2>/dev/null && log "Review posted on PR #$PR_NUMBER"

# Check if any CRITICAL issues
if echo "$CODEX_REVIEW $CLAUDE_REVIEW" | grep -qi "\[CRITICAL\]"; then
  log "⚠️ Critical issues found — PR not ready"
  exit 1
fi

log "✅ Review passed — no critical issues"
exit 0
