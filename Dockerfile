# ============================================
# Stage 1: 构建前端
# ============================================
FROM node:24.18.1-alpine3.24@sha256:f70403e87646dc51b45295f4b8b70cdad0b63d2297c4c9899119b03f7af7a6b3 AS frontend-builder

WORKDIR /app/web

COPY web/package.json web/pnpm-lock.yaml web/pnpm-workspace.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

COPY web/ ./
RUN pnpm run build

# ============================================
# Stage 2: 构建后端
# ============================================
FROM golang:1.27.0-alpine3.24@sha256:4c9fe60190a2a3350ddc51de80d0224b8a6698d12bdfc999fee45ea9d6c46dbc AS backend-builder

WORKDIR /app/backend

RUN apk add --no-cache gcc musl-dev

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./

ARG VERSION=dev
RUN CGO_ENABLED=1 GOOS=linux go build -mod=readonly -ldflags="-s -w -X main.Version=${VERSION}" -o /app/server ./cmd/server

# ============================================
# Stage 3: 最终镜像
# ============================================
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

WORKDIR /app

RUN apk add --no-cache ca-certificates su-exec tzdata wget \
    && addgroup -S -g 10001 ledger \
    && adduser -S -D -H -u 10001 -G ledger ledger

COPY --from=backend-builder /app/server /app/server
COPY --from=frontend-builder /app/web/dist /app/web/dist
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /data/uploads /data/backups \
    && chown -R ledger:ledger /app /data

# ========== 环境变量配置 ==========
# 服务器配置
ENV LEDGER_SERVER_PORT=8080 \
    LEDGER_SERVER_MODE=release \
    LEDGER_SERVER_WEB_PATH=/app/web/dist \
    LEDGER_SERVER_TRUSTED_PROXIES="" \
    LEDGER_SERVER_MAX_JSON_BODY_BYTES=1048576 \
    # 数据库配置
    LEDGER_DATABASE_DRIVER=sqlite \
    LEDGER_DATABASE_PATH=/data/ledger.db \
    LEDGER_DATABASE_DSN="" \
    LEDGER_DATABASE_MAX_OPEN_CONNS=0 \
    LEDGER_DATABASE_MAX_IDLE_CONNS=0 \
    LEDGER_SETUP_CONFIG_PATH=/data/config.yaml \
    # JWT 配置。必须在部署时显式设置 LEDGER_JWT_SECRET。
    LEDGER_JWT_ACCESS_EXPIRE=15 \
    LEDGER_JWT_REFRESH_EXPIRE=43200 \
    # 日志配置
    LEDGER_LOG_LEVEL=info \
    LEDGER_LOG_FORMAT=json \
    # 安全配置
    LEDGER_SECURITY_BASE_PATH="" \
    LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND=false \
    # 存储配置
    LEDGER_STORAGE_UPLOAD_PATH=/data/uploads \
    LEDGER_STORAGE_BACKUP_PATH=/data/backups \
    LEDGER_STORAGE_MAX_FILE_SIZE=10 \
    LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE=64 \
    LEDGER_STORAGE_ALLOWED_TYPES="jpg,jpeg,png,gif,webp,pdf,doc,docx,xls,xlsx,txt" \
    LEDGER_OBSERVABILITY_METRICS_ENABLED=false \
    # 时区
    TZ=Asia/Shanghai

EXPOSE 8080

# 持久化数据目录
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --output-document=/dev/null http://localhost:8080/api/v1/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/app/server"]
