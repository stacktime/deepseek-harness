# syntax=docker/dockerfile:1

# ============================================================
# DeepSeek Harness (dsh) 镜像
#
# 构建来源：官方 npm 包 @deepseek-ai/dsh（与 GitHub Release tag 一一对应）
#   例：release tag dsh-v0.2.3-alpha.1  ->  npm 版本 0.2.3-alpha.1
#
# 设计要点：
#   1. dsh 出于安全设计拒绝监听 0.0.0.0，只绑回环
#      -> 内部 127.0.0.1:3079，由 socat 代理到 0.0.0.0:3080
#   2. 数据目录固定 /data/dsh，挂卷持久化
#   3. 默认不装 LibreOffice（省 ~500MB）；需要文档转换时用 BUILD_WITH_LIBREOFFICE=true
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

# socat: 端口代理；tini: PID 1 信号处理；curl: HEALTHCHECK
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates socat tini curl \
 && rm -rf /var/lib/apt/lists/*

# 可选：LibreOffice（dsh-libreoffice-kit 相关功能需要）
RUN if [ "$BUILD_WITH_LIBREOFFICE" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends libreoffice-writer libreoffice-calc && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# 安装官方发行物（版本号即 release tag 去掉 dsh-v 前缀）
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

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${DSH_PORT}/" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
