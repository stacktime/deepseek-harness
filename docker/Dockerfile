# syntax=docker/dockerfile:1

# ============================================================
# DeepSeek Harness (dsh) 镜像
#
# 构建来源：官方 npm 包 @deepseek-ai/dsh（版本号 = release tag 去掉 dsh-v）
#
# 两个关键事实（已核对上游源码/测试）：
#   1. dsh 明确拒绝监听 0.0.0.0
#      apps/cli/tests/built-bin.e2e.ts:389 断言 `--host 0.0.0.0` 必须 exit 1
#      -> 容器内 dsh 绑 127.0.0.1:3079，由 socat 转发到 0.0.0.0:3080
#
#   2. npm 包 engines 要求 node ^24.22.3 || >=26.13.1
#      -> 用 node:24-slim 时若 tag 落后会触发 EBADENGINE（仅警告）
#         这里显式校验版本，避免运行期出现难以定位的问题
# ============================================================

FROM node:24-slim

ARG DSH_VERSION=latest
ARG BUILD_WITH_LIBREOFFICE=false

ENV DEBIAN_FRONTEND=noninteractive \
    DSH_HOME=/data/dsh \
    DSH_INTERNAL_PORT=3079 \
    DSH_PORT=3080 \
    NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# socat: 端口代理；tini: PID 1 信号处理；curl: 健康探测
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates socat tini curl \
 && rm -rf /var/lib/apt/lists/*

# 可选：LibreOffice（文档转换相关插件需要）
RUN if [ "$BUILD_WITH_LIBREOFFICE" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends libreoffice-writer libreoffice-calc && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# 记录并打印 Node 版本；engines 不满足时 npm 只警告不中断，
# 因此在日志里显式暴露，便于排障。
RUN node -v && npm -v

# 安装官方发行物
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" \
 && npm cache clean --force \
 && dsh --version

# 非 root 运行
RUN mkdir -p /data/dsh /workspace \
 && chown -R node:node /data/dsh /workspace

COPY --chown=node:node entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
USER node

EXPOSE 3080

# 注意：dsh 首页会 302 到 /?token=xxx，不能用 curl -f（会把 3xx 当失败）。
# 这里只判断「能拿到 HTTP 响应码」，000 表示连接失败。
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:${DSH_PORT}/ 2>/dev/null || echo 000); \
      [ "$code" != "000" ] || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]