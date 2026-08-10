# ============================================================
# server-services-manager 服务管理器镜像
# 运行时：Python 3.14（依赖隔离于 /opt/venv）+ Node.js 24 LTS + uv/uvx
# 构建参数：UPSTREAM_REPO / UPSTREAM_REF / NODE_VERSION
# 运行配置（环境变量，支持 .env 文件）：PASSWORD（默认 admin）/ SECRET_KEY / CORS_ORIGIN
# 持久化：/root 家目录已声明 VOLUME，可 -v 直接挂载（覆盖工具缓存、服务状态及未来其他 app 数据）
# 服务端口：8881
# ============================================================
# syntax=docker/dockerfile:1

# ---- 阶段 1: 拉取上游源码（git 不进最终镜像）----
FROM alpine/git:latest AS source
ARG UPSTREAM_REPO=https://github.com/samosa-ai-com/server-services-manager
ARG UPSTREAM_REF=main
RUN git clone --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" /src

# ---- 阶段 2: Python 虚拟环境 ----
FROM python:3.14-slim AS deps
COPY --from=source /src/requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

# ---- 阶段 3: Node.js LTS ----
FROM python:3.14-slim AS node
ARG NODE_VERSION=24.19.0
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && NODE_ARCH="$( [ "$TARGETARCH" = "amd64" ] && echo x64 || echo "$TARGETARCH" )" \
    && python3 -c "import urllib.request; urllib.request.urlretrieve('https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz', '/tmp/node.tar.xz')" \
    && mkdir -p /opt/node \
    && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 \
    && rm -f /tmp/node.tar.xz \
    && rm -rf /opt/node/include /opt/node/share

# ---- 阶段 4: 精简运行镜像 ----
FROM python:3.14-slim AS runtime
# glibc 依赖（Node 二进制）+ ca-certificates + curl（装 uv 用，装完即清）
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libstdc++6 curl \
    && curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
    && rm -rf /var/lib/apt/lists/*

COPY --from=deps /opt/venv /opt/venv
COPY --from=node /opt/node /opt/node

# 工具/缓存目录收敛到 root 家目录（均为 VOLUME 挂载点）
ENV UV_CACHE_DIR=/root/.cache/uv \
    UV_TOOL_DIR=/root/.local/share/uv/tools \
    UV_TOOL_BIN_DIR=/root/.local/bin \
    npm_config_cache=/root/.npm \
    NPM_CONFIG_PREFIX=/root/.npm-global \
    PATH="/opt/venv/bin:/opt/node/bin:/root/.local/bin:/root/.npm-global/bin:${PATH}" \
    NODE_PATH="/opt/node/lib/node_modules:/root/.npm-global/lib/node_modules"

WORKDIR /app
COPY --from=source --chown=root:root /src/server.py ./server.py
COPY --from=source --chown=root:root /src/app ./app
COPY --from=source --chown=root:root /src/templates ./templates
COPY --from=source --chown=root:root /src/mock_program.py ./mock_program.py

# 运行配置默认值（生产环境务必用 -e 覆盖）
ENV PASSWORD=admin \
    SECRET_KEY=change-me \
    CORS_ORIGIN=*

EXPOSE 8881

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD /opt/venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8881/health', timeout=3)" || exit 1

# 直接挂载整个 /root 家目录：工具缓存、服务状态及后续其他 app 数据全部持久化
VOLUME ["/root"]

CMD ["/opt/venv/bin/python", "server.py"]
