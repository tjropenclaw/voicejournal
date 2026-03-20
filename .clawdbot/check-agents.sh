#!/usr/bin/env bash
# check-agents.sh — monitoring loop, runs every 10 min via launchd
#
# Checks: tmux alive, PR created, CI status
# Actions: respawn failed agents (max 3x), notify Telegram on PR ready or failure

set -euo pipefail
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_FILE="$REPO_ROOT/.clawdbot/active-tasks.json"
MAX_RETRIES=3

# Telegram — sends to Hex channel (topic 2182)
TELEGRAM_BOT_TOKEN="REDACTED_TOKEN"
TELEGRAM_CHAT_ID="-1003532725632"
TELEGRAM_TOPIC_ID="2182"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "message_thread_id=${TELEGRAM_TOPIC_ID}" \
    -d "text=${msg}" \
    -d "parse_mode=HTML" > /dev/null 2>&1 || log "Telegram notify failed"
}

cd "$REPO_ROOT"

# Load tasks
TASK_COUNT=$(python3 -c "import json; t=json.load(open('$TASKS_FILE')); print(len([x for x in t if x['status'] in ('running','queued')]))")
if [ "$TASK_COUNT" -eq 0 ]; then
  log "No active tasks."
  exit 0
fi
log "Checking $TASK_COUNT active task(s)..."

# Process each task
python3 - <<PYEOF
import json, subprocess, os, time

TASKS_FILE = '$TASKS_FILE'
REPO_ROOT = '$REPO_ROOT'
MAX_RETRIES = $MAX_RETRIES
tasks = json.load(open(TASKS_FILE))
events = []

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

for idx, task in enumerate(tasks):
    if task['status'] not in ('running', 'queued'):
        continue

    task_id = task['id']
    session = task.get('tmuxSession', f'agent-{task_id}')
    branch = task.get('branch', '')

    # Check tmux
    tmux_alive = run(['tmux', 'has-session', '-t', session]).returncode == 0

    # Check for PR
    pr_number = None
    ci_passed = False
    try:
        pr = run(['gh', 'pr', 'view', branch, '--json', 'number,state,statusCheckRollup'],
                 cwd=REPO_ROOT)
        if pr.returncode == 0:
            pr_data = json.loads(pr.stdout)
            pr_number = pr_data.get('number')
            checks = pr_data.get('statusCheckRollup') or []
            ci_passed = bool(checks) and all(
                c.get('conclusion') == 'SUCCESS' or c.get('status') == 'COMPLETED'
                for c in checks
            )
    except:
        pass

    # Update task
    if pr_number:
        tasks[idx]['pr'] = pr_number
    tasks[idx]['lastChecked'] = int(time.time() * 1000)

    # PR ready
    if pr_number and ci_passed and task['status'] == 'running':
        tasks[idx]['status'] = 'done'
        tasks[idx]['completedAt'] = int(time.time() * 1000)
        tasks[idx]['note'] = 'CI passed. Ready to merge.'
        events.append(('READY', task_id, str(pr_number), task.get('description','')))

    # Agent died without PR
    elif not tmux_alive and not pr_number and task['status'] == 'running':
        retries = task.get('retries', 0)
        if retries < MAX_RETRIES:
            tasks[idx]['retries'] = retries + 1
            tasks[idx]['status'] = 'running'  # will be relaunched
            events.append(('RESPAWN', task_id, '', task.get('description','')))
        else:
            tasks[idx]['status'] = 'failed'
            events.append(('FAILED', task_id, '', task.get('description','')))

json.dump(tasks, open(TASKS_FILE, 'w'), indent=2)

for event, task_id, extra, desc in events:
    print(f'{event}:{task_id}:{extra}:{desc}')
PYEOF | while IFS=: read -r event task_id extra desc; do
  case "$event" in
    READY)
      log "✅ PR #$extra ready: $task_id ($desc)"
      notify "✅ <b>PR #${extra} ready for review</b>%0A${desc}%0ACI passed. Go merge it."
      ;;
    RESPAWN)
      log "🔄 Respawning: $task_id"
      "$REPO_ROOT/.clawdbot/run-agent.sh" "$task_id" &
      notify "🔄 Agent respawned: ${task_id}"
      ;;
    FAILED)
      log "❌ Agent failed (max retries): $task_id"
      notify "❌ <b>Agent failed</b>: ${task_id} — max retries hit. Needs attention."
      ;;
  esac
done

log "Check complete."
