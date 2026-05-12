#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 08_zabbix.sh - Zabbix のデプロイ（Docker Compose）
# 構成: zabbix-server-pgsql + zabbix-web-nginx-pgsql + postgresql
# 公開 URL: https://zbx.seragl.io（Caddy リバースプロキシ経由）
# Web UI ポート: ホスト側 8080
# =============================================================================

echo "[INFO] Zabbix のデプロイを開始します..."

ZABBIX_DIR="/opt/zabbix"
DATA_DIR="${ZABBIX_DIR}/data"
COMPOSE_FILE="${ZABBIX_DIR}/docker-compose.yml"

# --------------------------------------------------------------------------
# ディレクトリ作成
# --------------------------------------------------------------------------
echo "[INFO] データディレクトリを作成します: ${DATA_DIR}"
mkdir -p "${DATA_DIR}/postgresql"

# --------------------------------------------------------------------------
# docker-compose.yml の配置
# ZABBIX_DB_PASSWORD は .env から展開して埋め込む
# --------------------------------------------------------------------------
echo "[INFO] docker-compose.yml を配置します: ${COMPOSE_FILE}"

cat > "${COMPOSE_FILE}" <<EOF
# =============================================================================
# /opt/zabbix/docker-compose.yml
# Zabbix 監視プラットフォーム
# 公開 URL: https://zbx.seragl.io（Caddy リバースプロキシ経由）
# 初期管理者: Admin / zabbix（初回ログイン後に必ず変更すること）
# =============================================================================

networks:
  zabbix:
    external: false

services:
  zabbix-db:
    image: postgres:15
    container_name: zabbix-db
    restart: unless-stopped
    networks:
      - zabbix
    environment:
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: ${ZABBIX_DB_PASSWORD}
      POSTGRES_DB: zabbix
    volumes:
      - ${DATA_DIR}/postgresql:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U zabbix"]
      interval: 10s
      timeout: 5s
      retries: 5

  zabbix-server:
    image: zabbix/zabbix-server-pgsql:latest
    container_name: zabbix-server
    restart: unless-stopped
    networks:
      - zabbix
    depends_on:
      zabbix-db:
        condition: service_healthy
    environment:
      DB_SERVER_HOST: zabbix-db
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: ${ZABBIX_DB_PASSWORD}
      POSTGRES_DB: zabbix
    ports:
      - "10051:10051"

  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:latest
    container_name: zabbix-web
    restart: unless-stopped
    networks:
      - zabbix
    depends_on:
      - zabbix-server
      - zabbix-db
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: zabbix-db
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: ${ZABBIX_DB_PASSWORD}
      POSTGRES_DB: zabbix
      PHP_TZ: Asia/Tokyo
    ports:
      - "8080:8080"
EOF

echo "[INFO] docker-compose.yml を配置しました。"

# --------------------------------------------------------------------------
# Zabbix コンテナの起動
# --------------------------------------------------------------------------
echo "[INFO] Zabbix コンテナを起動します..."
cd "${ZABBIX_DIR}"
docker compose up -d

echo "[INFO] Zabbix の起動状態:"
docker compose ps

echo "[INFO] Zabbix デプロイ完了。"
echo "[INFO] Web UI は https://zbx.seragl.io （Caddy 起動後）からアクセスしてください。"
echo "[INFO] 初期ログイン情報: Admin / zabbix（初回ログイン後に必ず変更してください）"
