#!/usr/bin/env bash
# cleanup.sh — daily cron job
# Removes orphaned worktrees for merged/closed PRs
# Cleans up done/failed tasks from active-tasks.json older than 7 days

set -euo pipefail
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREES_DIR="$(dirname "$REPO_ROOT")/voicejournal-worktrees"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting cleanup..."

# Remove worktrees for merged/closed PRs
if [ -d "$WORKTREES_DIR" ]; then
  for worktree in "$WORKTREES_DIR"/*/; do
    [ -d "$worktree" ] || continue
    branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [ -z "$branch" ] && continue

    pr_state=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")
    if [ "$pr_state" = "MERGED" ] || [ "$pr_state" = "CLOSED" ]; then
      log "Removing worktree for $branch (PR $pr_state)"
      git -C "$REPO_ROOT" worktree remove "$worktree" --force 2>/dev/null || rm -rf "$worktree"
    fi
  done
fi

# Prune stale worktree refs
git -C "$REPO_ROOT" worktree prune

# Archive old done/failed tasks (keep last 50)
python3 - <<PYEOF
import json, time, os

tasks_file = '$TASKS_FILE'
tasks = json.load(open(tasks_file))

active = [t for t in tasks if t['status'] in ('running', 'queued')]
done = [t for t in tasks if t['status'] not in ('running', 'queued')]

# Keep only last 50 completed
done_trimmed = sorted(done, key=lambda t: t.get('completedAt', 0), reverse=True)[:50]
tasks_new = active + done_trimmed

removed = len(tasks) - len(tasks_new)
json.dump(tasks_new, open(tasks_file, 'w'), indent=2)
print(f'Cleaned {removed} old tasks. Active: {len(active)}, Archived: {len(done_trimmed)}')
PYEOF

log "Cleanup complete."
