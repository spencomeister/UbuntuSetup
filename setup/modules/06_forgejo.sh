#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 06_forgejo.sh - Forgejo のデプロイ（Docker Compose）
# 公開 URL: https://git.seragl.io
# データ: /opt/forgejo/data
# =============================================================================

echo "[INFO] Forgejo のデプロイを開始します..."

FORGEJO_DIR="/opt/forgejo"
DATA_DIR="${FORGEJO_DIR}/data"
COMPOSE_FILE="${FORGEJO_DIR}/docker-compose.yml"

# --------------------------------------------------------------------------
# ディレクトリ作成
# --------------------------------------------------------------------------
echo "[INFO] データディレクトリを作成します: ${DATA_DIR}"
mkdir -p "${DATA_DIR}"

# --------------------------------------------------------------------------
# docker-compose.yml の配置
# --------------------------------------------------------------------------
echo "[INFO] docker-compose.yml を配置します: ${COMPOSE_FILE}"

cat > "${COMPOSE_FILE}" <<EOF
# =============================================================================
# /opt/forgejo/docker-compose.yml
# Forgejo - セルフホスト型 Git サービス
# 公開 URL: https://git.seragl.io（Caddy リバースプロキシ経由）
# =============================================================================

networks:
  forgejo:
    external: false

services:
  forgejo:
    image: ghcr.io/forgejo/forgejo:latest
    container_name: forgejo
    restart: unless-stopped
    networks:
      - forgejo
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - FORGEJO__security__SECRET_KEY=${FORGEJO_SECRET_KEY}
      - FORGEJO__server__DOMAIN=git.seragl.io
      - FORGEJO__server__ROOT_URL=https://git.seragl.io
      - FORGEJO__server__SSH_DOMAIN=git.seragl.io
      - FORGEJO__server__SSH_PORT=222
    ports:
      - "3000:3000"
      - "222:22"
    volumes:
      - ${DATA_DIR}:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
EOF

echo "[INFO] docker-compose.yml を配置しました。"

# --------------------------------------------------------------------------
# Forgejo コンテナの起動
# --------------------------------------------------------------------------
echo "[INFO] Forgejo コンテナを起動します..."
cd "${FORGEJO_DIR}"
docker compose up -d

echo "[INFO] Forgejo の起動状態:"
docker compose ps

echo "[INFO] Forgejo デプロイ完了。"
echo "[INFO] 初回セットアップは https://git.seragl.io にアクセスして Web UI から行ってください。"
echo "[INFO] 管理者アカウントの作成は初回インストール画面で実施してください。"
