#!/usr/bin/env bash
# run-agent.sh <task-id> [model] [effort]
#
# Spawns a Claude Code or Codex agent in a tmux session with its own worktree.
# Task must already be registered in active-tasks.json.
#
# Agent selection:
#   claude-*  → Claude Code (claude --dangerously-skip-permissions -p)
#   codex-*   → Codex CLI   (codex exec)
#   Default   → Codex

set -euo pipefail

export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

TASK_ID="${1:?task-id required}"
MODEL="${2:-codex-mini-latest}"
EFFORT="${3:-high}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREES_DIR="$(dirname "$REPO_ROOT")/voicejournal-worktrees"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"
SESSION_NAME="agent-$TASK_ID"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Read task
TASK=$(node -e "
  const fs = require('fs');
  const tasks = JSON.parse(fs.readFileSync('$TASKS_FILE'));
  const t = tasks.find(t => t.id === '$TASK_ID');
  if (!t) { console.error('Task not found: $TASK_ID'); process.exit(1); }
  console.log(JSON.stringify(t));
")

BRANCH=$(node -e "process.stdout.write(JSON.parse('$TASK'.replace(/'/g,\"'\")).branch || '')" 2>/dev/null || \
  echo "$TASK" | python3 -c "import json,sys; print(json.load(sys.stdin)['branch'])")
PROMPT_FILE="/tmp/clawdbot-prompt-$TASK_ID.txt"
echo "$TASK" | python3 -c "import json,sys; print(json.load(sys.stdin)['prompt'])" > "$PROMPT_FILE"

WORKTREE_PATH="$WORKTREES_DIR/$TASK_ID"

# Create worktree
if [ ! -d "$WORKTREE_PATH" ]; then
  log "Creating worktree: $WORKTREE_PATH (branch: $BRANCH)"
  mkdir -p "$WORKTREES_DIR"
  git -C "$REPO_ROOT" fetch origin
  git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/main
  cd "$WORKTREE_PATH" && npm ci --silent
  log "Worktree ready"
fi

# Kill existing tmux session
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME" && log "Killed existing session"

# Update status to running
python3 - <<PYEOF
import json, time
tasks = json.load(open('$TASKS_FILE'))
idx = next(i for i,t in enumerate(tasks) if t['id'] == '$TASK_ID')
tasks[idx].update({'status': 'running', 'tmuxSession': '$SESSION_NAME', 'startedAt': int(time.time()*1000)})
json.dump(tasks, open('$TASKS_FILE','w'), indent=2)
PYEOF

# Build agent command — interactive mode in tmux for mid-task steering
PROMPT_CONTENT=$(cat "$PROMPT_FILE")

if echo "$MODEL" | grep -qi "claude\|anthropic\|opus\|sonnet\|haiku"; then
  # Claude Code — interactive mode, skip permissions
  CMD="claude --model $MODEL --dangerously-skip-permissions -p $(printf '%q' "$PROMPT_CONTENT")"
  log "Launching Claude Code (model: $MODEL)"
else
  # Codex — interactive mode, bypass approvals
  CMD="codex --model $MODEL -c 'model_reasoning_effort=$EFFORT' --dangerously-bypass-approvals-and-sandbox $(printf '%q' "$PROMPT_CONTENT")"
  log "Launching Codex (model: $MODEL, effort: $EFFORT)"
fi

# Launch in tmux — interactive so we can steer mid-task with tmux send-keys
tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH" \
  "export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH; $CMD; echo '[agent-done]'; read"

log "To steer: tmux send-keys -t $SESSION_NAME 'your message here' Enter"
log "To watch: tmux attach -t $SESSION_NAME"

log "Agent launched: session=$SESSION_NAME worktree=$WORKTREE_PATH"
rm -f "$PROMPT_FILE"
