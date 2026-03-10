#!/usr/bin/env bash
# Monitoring loop — runs every 10 min via cron.
# Checks tmux sessions, PR status, CI status.
# Notifies via OpenClaw/Telegram when PRs are ready or agents need attention.

set -euo pipefail

export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"
MAX_RETRIES=3

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  local msg="$1"
  # Send via OpenClaw CLI to Hex's Telegram channel (topic 2182)
  openclaw message send \
    --channel telegram \
    --account hex \
    --group -1003532725632 \
    --topic 2182 \
    --text "$msg" 2>/dev/null || log "Notify failed: $msg"
}

cd "$REPO_ROOT"

# Load tasks
TASKS=$(cat "$TASKS_FILE")
TASK_COUNT=$(echo "$TASKS" | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).length))")

if [ "$TASK_COUNT" -eq 0 ]; then
  log "No active tasks."
  exit 0
fi

# Process each running task
echo "$TASKS" | node -e "
const fs = require('fs');
const tasks = JSON.parse(require('fs').readFileSync('$TASKS_FILE'));

tasks.forEach((task, idx) => {
  if (task.status !== 'running') return;

  const checks = {
    tmuxAlive: false,
    prCreated: false,
    ciPassed: false,
    prNumber: null,
  };

  // Check tmux session
  const { execSync } = require('child_process');
  try {
    execSync('tmux has-session -t ' + task.tmuxSession, { stdio: 'ignore' });
    checks.tmuxAlive = true;
  } catch {}

  // Check for open PR on branch
  try {
    const pr = execSync('gh pr view ' + task.branch + ' --json number,state,statusCheckRollup 2>/dev/null', { cwd: '$REPO_ROOT' }).toString();
    const prData = JSON.parse(pr);
    checks.prCreated = true;
    checks.prNumber = prData.number;

    // Check CI
    if (prData.statusCheckRollup) {
      const allPassed = prData.statusCheckRollup.every(c => c.conclusion === 'SUCCESS' || c.status === 'COMPLETED');
      checks.ciPassed = allPassed;
    }
  } catch {}

  // Write back updated checks
  tasks[idx].checks = { ...tasks[idx].checks, ...checks };
  if (checks.prCreated) tasks[idx].pr = checks.prNumber;

  // If PR exists and CI passed — mark done
  if (checks.prCreated && checks.ciPassed) {
    tasks[idx].status = 'done';
    tasks[idx].completedAt = Date.now();
    tasks[idx].note = 'CI passed. Ready to merge.';
    console.log('READY:' + task.id + ':' + checks.prNumber);
  }

  // If tmux died and no PR — flag for respawn
  if (!checks.tmuxAlive && !checks.prCreated) {
    const retries = task.retries || 0;
    if (retries < $MAX_RETRIES) {
      tasks[idx].retries = retries + 1;
      tasks[idx].status = 'respawn';
      console.log('RESPAWN:' + task.id);
    } else {
      tasks[idx].status = 'failed';
      console.log('FAILED:' + task.id);
    }
  }
});

fs.writeFileSync('$TASKS_FILE', JSON.stringify(tasks, null, 2));
" | while IFS=: read -r event task_id pr_or_empty; do
  case "$event" in
    READY)
      log "PR ready: $task_id (PR #$pr_or_empty)"
      notify "✅ PR #$pr_or_empty ready for review — $task_id. CI passed. Go merge it."
      ;;
    RESPAWN)
      log "Respawning agent: $task_id"
      "$REPO_ROOT/.clawdbot/run-agent.sh" "$task_id" &
      notify "🔄 Agent respawned: $task_id"
      ;;
    FAILED)
      log "Agent failed after max retries: $task_id"
      notify "❌ Agent failed (max retries): $task_id — needs your attention."
      ;;
  esac
done

log "Check complete."
