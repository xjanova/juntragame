#!/bin/bash
# ===================================================================
# juntragame / แม่หมอจันทรา (เกม) — Server-side Deploy Script
# Static site (Phaser loaded from CDN). No composer / migrations / cache.
# Run on the DirectAdmin server at the subdomain document root, e.g.
#   /home/admin/domains/xn--82c4af5bzdj.online/public_html/game
# ===================================================================
set -uo pipefail
set -o errtrace

BRANCH="${1:-main}"
LOG="deploy.log"

ts() { date -u +'%Y-%m-%d %H:%M:%S UTC'; }

echo "" >> "$LOG"
echo "============================================================" >> "$LOG"
echo "[$(ts)] Deploy start (branch: $BRANCH)" >> "$LOG"

log()  { echo "$1" | tee -a "$LOG"; }
warn() { echo "⚠️ $1" | tee -a "$LOG"; }
fail() { echo "❌ $1" | tee -a "$LOG"; exit 1; }

# ---------- 1. Disk-space sanity ----------
AVAIL_KB=$(df . | awk 'NR==2 {print $4}')
[ "${AVAIL_KB:-0}" -lt 20480 ] && warn "Low disk space (${AVAIL_KB}KB)"

# ---------- 2. Backup deploy.log itself (rotate if huge) ----------
if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 524288 ]; then
  mv "$LOG" "${LOG}.1"
  echo "[$(ts)] log rotated" > "$LOG"
fi

# ---------- 3. Git sync ----------
log "📥 Syncing code from origin/$BRANCH..."
# Same lesson as juntraweb: NO `git stash -u` — it eats untracked files
# (deploy.log, .htpasswd, operator shims). `reset --hard` only touches tracked.
git fetch --all --prune 2>&1 | tee -a "$LOG" || fail "git fetch failed"
git reset --hard "origin/$BRANCH" 2>&1 | tee -a "$LOG" || fail "git reset failed"

# ---------- 4. Permissions (DirectAdmin shared host) ----------
log "🔐 Fixing permissions..."
find . -type d -not -path './.git*' -exec chmod 755 {} \; 2>/dev/null || true
find . -type f -not -path './.git*' -exec chmod 644 {} \; 2>/dev/null || true
chmod +x deploy.sh 2>/dev/null || true

# ---------- 5. Health check (just verify index.html parses) ----------
if [ ! -f index.html ]; then
  fail "index.html missing after deploy"
fi
SIZE=$(stat -c%s index.html 2>/dev/null || echo 0)
if [ "$SIZE" -lt 1000 ]; then
  warn "index.html unexpectedly small (${SIZE} bytes)"
fi

log "🎉 Deployment finished ($(ts))"
log "Latest commit: $(git log -1 --pretty=format:'%h %s')"
