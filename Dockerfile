# ============================================
# Stage 1: 构建前端
# ============================================
FROM node:20-alpine AS frontend-builder

WORKDIR /app/web

COPY web/package.json web/pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

COPY web/ ./
RUN pnpm run build

# ============================================
# Stage 2: 构建后端
# ============================================
FROM golang:1.24-alpine AS backend-builder

WORKDIR /app/backend

RUN apk add --no-cache gcc musl-dev

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./

ARG VERSION=dev
RUN go mod tidy && CGO_ENABLED=1 GOOS=linux go build -ldflags="-s -w -X main.Version=${VERSION}" -o /app/server ./cmd/server

# ============================================
# Stage 3: 最终镜像
# ============================================
FROM alpine:3.19

WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata wget

COPY --from=backend-builder /app/server /app/server
COPY --from=frontend-builder /app/web/dist /app/web/dist

RUN mkdir -p /data/uploads /data/backups

# ========== 环境变量配置 ==========
# 服务器配置
ENV LEDGER_SERVER_PORT=8080 \
    LEDGER_SERVER_MODE=release \
    LEDGER_SERVER_WEB_PATH=/app/web/dist \
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
    # 存储配置
    LEDGER_STORAGE_UPLOAD_PATH=/data/uploads \
    LEDGER_STORAGE_BACKUP_PATH=/data/backups \
    LEDGER_STORAGE_MAX_FILE_SIZE=10 \
    LEDGER_STORAGE_ALLOWED_TYPES="jpg,jpeg,png,gif,webp,pdf,doc,docx,xls,xlsx,txt" \
    # 时区
    TZ=Asia/Shanghai

EXPOSE 8080

# 持久化数据目录
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

CMD ["/app/server"]
