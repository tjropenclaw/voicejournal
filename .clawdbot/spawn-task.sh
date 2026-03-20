#!/usr/bin/env bash
# spawn-task.sh <task-id> <branch> <description> <prompt-file-or-string> [model] [effort]
#
# Registers a task in active-tasks.json and launches the agent.
#
# Examples:
#   spawn-task.sh feat-nav feat/navigation "Bottom tab navigation" prompts/feat-nav.txt claude-opus-4-5 high
#   spawn-task.sh feat-habits feat/habits "Habit tracker screens" "Build habit tracker UI..." codex-mini-latest high

set -euo pipefail
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

TASK_ID="${1:?task-id required}"
BRANCH="${2:?branch required}"
DESCRIPTION="${3:?description required}"
PROMPT_INPUT="${4:?prompt or prompt-file required}"
MODEL="${5:-codex-mini-latest}"
EFFORT="${6:-high}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"

# Read prompt from file or string
if [ -f "$PROMPT_INPUT" ]; then
  PROMPT=$(cat "$PROMPT_INPUT")
else
  PROMPT="$PROMPT_INPUT"
fi

# Register task
python3 - <<PYEOF
import json, os, time

tasks_file = '$TASKS_FILE'
tasks = json.load(open(tasks_file)) if os.path.exists(tasks_file) else []

task = {
    'id': '$TASK_ID',
    'tmuxSession': 'agent-$TASK_ID',
    'agent': '$MODEL',
    'description': '$DESCRIPTION',
    'branch': '$BRANCH',
    'repo': 'voicejournal',
    'worktree': '$TASK_ID',
    'prompt': '''$PROMPT''',
    'startedAt': None,
    'status': 'queued',
    'notifyOnComplete': True,
    'retries': 0,
}

idx = next((i for i,t in enumerate(tasks) if t['id'] == '$TASK_ID'), None)
if idx is not None:
    tasks[idx] = task
else:
    tasks.append(task)

json.dump(tasks, open(tasks_file, 'w'), indent=2)
print(f'Task registered: $TASK_ID')
PYEOF

# Launch
"$REPO_ROOT/.clawdbot/run-agent.sh" "$TASK_ID" "$MODEL" "$EFFORT"
