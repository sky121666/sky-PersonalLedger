# ============================================
# Stage 1: 构建前端
# ============================================
FROM node:20-alpine AS frontend-builder

WORKDIR /app/web

COPY web/package*.json ./
RUN npm ci

COPY web/ ./
RUN npm run build

# ============================================
# Stage 2: 构建后端
# ============================================
FROM golang:1.23-alpine AS backend-builder

WORKDIR /app/backend

# CGO 需要 gcc
RUN apk add --no-cache gcc musl-dev

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ ./
RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-s -w" -o /app/server ./cmd/server

# ============================================
# Stage 3: 最终镜像
# ============================================
FROM alpine:3.19

WORKDIR /app

# 运行时依赖
RUN apk add --no-cache ca-certificates tzdata wget

# 复制构建产物
COPY --from=backend-builder /app/server /app/server
COPY --from=frontend-builder /app/web/dist /app/web/dist

# 创建数据目录（运行时会被 volume 覆盖）
RUN mkdir -p /data/uploads /data/backups && \
    chown -R nobody:nobody /data

# 默认环境变量
ENV LEDGER_SERVER_PORT=8080 \
    LEDGER_SERVER_MODE=release \
    LEDGER_SERVER_WEB_PATH=/app/web/dist \
    LEDGER_DATABASE_PATH=/data/ledger.db \
    LEDGER_STORAGE_UPLOAD_PATH=/data/uploads \
    LEDGER_STORAGE_BACKUP_PATH=/data/backups \
    LEDGER_LOG_LEVEL=info \
    LEDGER_LOG_FORMAT=json \
    TZ=Asia/Shanghai

EXPOSE 8080

# 数据持久化目录
VOLUME ["/data"]

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/api/v1/auth/status || exit 1

# 使用非 root 用户运行（可选，需要确保 /data 权限正确）
# USER nobody

CMD ["/app/server"]
