#!/usr/bin/env bash
set -euo pipefail

DSH_INTERNAL_PORT="${DSH_INTERNAL_PORT:-3079}"
DSH_PORT="${DSH_PORT:-3080}"

log() { echo "[entrypoint] $*"; }

# 数据目录自愈（挂载命名卷时首次为空）
mkdir -p "${DSH_HOME}" /workspace

# 健康探测：
#   dsh web 首页会 302 到 /?token=xxx，curl -f 会把 3xx 当失败，
#   所以这里只要拿到任何 HTTP 响应码（含 3xx）就算就绪。
#   用 -o /dev/null -w '%{http_code}' 判断，避免误判。
probe() {
  local port="$1"
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 \
    "http://127.0.0.1:${port}/" 2>/dev/null || echo "000")
  [ "${code}" != "000" ]
}

# dsh 拒绝监听 0.0.0.0（安全设计，实测 --host 0.0.0.0 会 exit 1）
#   -> dsh 只绑 127.0.0.1:3079
#   -> socat 把 0.0.0.0:3080 转发到 127.0.0.1:3079
log "starting dsh on 127.0.0.1:${DSH_INTERNAL_PORT}"
dsh web --port "${DSH_INTERNAL_PORT}" --host 127.0.0.1 --no-open &
DSH_PID=$!

# 等 dsh 就绪（最多 180 秒）
READY=false
for i in $(seq 1 180); do
  if probe "${DSH_INTERNAL_PORT}"; then
    log "dsh is ready after ${i}s"
    READY=true
    break
  fi
  if ! kill -0 "${DSH_PID}" 2>/dev/null; then
    log "ERROR: dsh exited during startup" >&2
    wait "${DSH_PID}" || true
    exit 1
  fi
  sleep 1
done

if [ "${READY}" != "true" ]; then
  log "ERROR: dsh did not become ready in 180s" >&2
  kill -TERM "${DSH_PID}" 2>/dev/null || true
  exit 1
fi

log "starting socat 0.0.0.0:${DSH_PORT} -> 127.0.0.1:${DSH_INTERNAL_PORT}"
socat "TCP-LISTEN:${DSH_PORT},fork,reuseaddr" "TCP:127.0.0.1:${DSH_INTERNAL_PORT}" &
SOCAT_PID=$!

# 确认代理可用（最多 30 秒）
PROXIED=false
for i in $(seq 1 30); do
  if probe "${DSH_PORT}"; then
    log "proxy is ready after ${i}s"
    PROXIED=true
    break
  fi
  if ! kill -0 "${SOCAT_PID}" 2>/dev/null; then
    log "ERROR: socat exited" >&2
    kill -TERM "${DSH_PID}" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

if [ "${PROXIED}" != "true" ]; then
  log "ERROR: proxy on :${DSH_PORT} did not respond in 30s" >&2
  kill -TERM "${SOCAT_PID}" "${DSH_PID}" 2>/dev/null || true
  exit 1
fi

log "all services up: 0.0.0.0:${DSH_PORT} -> 127.0.0.1:${DSH_INTERNAL_PORT}"

cleanup() {
  log "shutting down"
  kill -TERM "${SOCAT_PID}" "${DSH_PID}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# 任一子进程退出则整体退出（交给容器 restart 策略）
set +e
wait -n "${DSH_PID}" "${SOCAT_PID}"
STATUS=$?
set -e
log "a child process exited (status ${STATUS}), stopping container" >&2
cleanup
exit 1