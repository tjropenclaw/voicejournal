#!/usr/bin/env bash
# Usage: run-agent.sh <task-id> <model> <effort>
# Example: run-agent.sh feat-voice-ui gpt-4o high
#
# Spawns a coding agent (codex or claude) in a tmux session with a worktree.
# Task must already exist in active-tasks.json before calling this.

set -euo pipefail

TASK_ID="${1:?task-id required}"
MODEL="${2:-gpt-4o}"
EFFORT="${3:-medium}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREES_DIR="$(dirname "$REPO_ROOT")/voicejournal-worktrees"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"
SESSION_NAME="agent-$TASK_ID"

# Read task from registry
TASK=$(node -e "
  const tasks = require('$TASKS_FILE');
  const t = tasks.find(t => t.id === '$TASK_ID');
  if (!t) { console.error('Task not found: $TASK_ID'); process.exit(1); }
  console.log(JSON.stringify(t));
")

BRANCH=$(echo "$TASK" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).branch))")
PROMPT=$(echo "$TASK" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).prompt))")

WORKTREE_PATH="$WORKTREES_DIR/$TASK_ID"

# Create worktree if it doesn't exist
if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Creating worktree at $WORKTREE_PATH..."
  git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/main
  cd "$WORKTREE_PATH" && npm ci --silent
fi

# Kill existing session if running
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME"

# Update task status to running
node -e "
  const fs = require('fs');
  const tasks = JSON.parse(fs.readFileSync('$TASKS_FILE'));
  const idx = tasks.findIndex(t => t.id === '$TASK_ID');
  tasks[idx].status = 'running';
  tasks[idx].tmuxSession = '$SESSION_NAME';
  tasks[idx].startedAt = Date.now();
  fs.writeFileSync('$TASKS_FILE', JSON.stringify(tasks, null, 2));
"

# Detect agent type from model name and launch
if echo "$MODEL" | grep -qi "codex\|gpt"; then
  CMD="codex --model $MODEL -c model_reasoning_effort=$EFFORT --dangerously-bypass-approvals-and-sandbox \"$PROMPT\""
else
  CMD="claude --model $MODEL --dangerously-skip-permissions -p \"$PROMPT\""
fi

tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH" "$CMD"

echo "Agent launched: session=$SESSION_NAME worktree=$WORKTREE_PATH"
