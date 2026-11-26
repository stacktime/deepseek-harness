#!/usr/bin/env bash
set -euo pipefail

DSH_INTERNAL_PORT="${DSH_INTERNAL_PORT:-3079}"
DSH_PORT="${DSH_PORT:-3080}"

# 数据目录自愈（挂载命名卷时首次为空）
mkdir -p "${DSH_HOME}" /workspace

# dsh 拒绝监听 0.0.0.0（安全设计），因此：
#   容器内 dsh 只绑 127.0.0.1:3079
#   socat 把 0.0.0.0:3080 转发到 127.0.0.1:3079
echo "[entrypoint] starting dsh on 127.0.0.1:${DSH_INTERNAL_PORT}"
dsh web --port "${DSH_INTERNAL_PORT}" --host 127.0.0.1 &
DSH_PID=$!

# 等 dsh 就绪再起代理，避免客户端拿到 connection refused
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${DSH_INTERNAL_PORT}/" >/dev/null 2>&1; then
    echo "[entrypoint] dsh is ready"
    break
  fi
  if ! kill -0 "${DSH_PID}" 2>/dev/null; then
    echo "[entrypoint] ERROR: dsh exited during startup" >&2
    wait "${DSH_PID}"
    exit 1
  fi
  sleep 1
done

echo "[entrypoint] starting socat 0.0.0.0:${DSH_PORT} -> 127.0.0.1:${DSH_INTERNAL_PORT}"
socat "TCP-LISTEN:${DSH_PORT},fork,reuseaddr" "TCP:127.0.0.1:${DSH_INTERNAL_PORT}" &
SOCAT_PID=$!

# 任一进程退出则整体退出，交给容器 restart 策略
cleanup() {
  echo "[entrypoint] shutting down"
  kill -TERM "${SOCAT_PID}" "${DSH_PID}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

wait -n "${DSH_PID}" "${SOCAT_PID}"
echo "[entrypoint] a child process exited, stopping container" >&2
cleanup
exit 1
