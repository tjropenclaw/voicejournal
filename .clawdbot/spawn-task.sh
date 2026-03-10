#!/usr/bin/env bash
# Usage: spawn-task.sh <task-id> <branch> <description> <prompt> [model] [effort]
# Registers a task in active-tasks.json and launches the agent.
#
# Example:
#   spawn-task.sh feat-voice-ui feat/voice-ui "Voice call UI screen" "Build the call screen..." codex high

set -euo pipefail

export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

TASK_ID="${1:?task-id required}"
BRANCH="${2:?branch required}"
DESCRIPTION="${3:?description required}"
PROMPT="${4:?prompt required}"
MODEL="${5:-codex}"
EFFORT="${6:-high}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"

# Add task to registry
node -e "
  const fs = require('fs');
  const tasks = JSON.parse(fs.readFileSync('$TASKS_FILE'));
  const existing = tasks.findIndex(t => t.id === '$TASK_ID');
  const task = {
    id: '$TASK_ID',
    tmuxSession: 'agent-$TASK_ID',
    agent: '$MODEL',
    description: '$DESCRIPTION',
    branch: '$BRANCH',
    repo: 'voicejournal',
    worktree: '$TASK_ID',
    prompt: $(echo "$PROMPT" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.stringify(d.trim())))"),
    startedAt: null,
    status: 'queued',
    notifyOnComplete: true,
    retries: 0,
  };
  if (existing >= 0) tasks[existing] = task;
  else tasks.push(task);
  fs.writeFileSync('$TASKS_FILE', JSON.stringify(tasks, null, 2));
  console.log('Task registered: $TASK_ID');
"

# Launch the agent
"$REPO_ROOT/.clawdbot/run-agent.sh" "$TASK_ID" "$MODEL" "$EFFORT"
