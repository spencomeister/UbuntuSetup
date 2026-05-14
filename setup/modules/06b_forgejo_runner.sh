#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# 06b_forgejo_runner.sh - Forgejo act_runner のデプロイ
# 依存: 06_forgejo.sh 実行済みであること
# ランナートークンは .env の FORGEJO_RUNNER_TOKEN から取得
# =============================================================================
echo "[INFO] Forgejo act_runner のデプロイを開始します..."

FORGEJO_DIR="/opt/forgejo"
COMPOSE_FILE="${FORGEJO_DIR}/docker-compose.yml"
RUNNER_DATA_DIR="${FORGEJO_DIR}/runner_data"
RUNNER_VERSION="12"

# --------------------------------------------------------------------------
# 事前確認
# --------------------------------------------------------------------------
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "[ERROR] docker-compose.yml が見つかりません: ${COMPOSE_FILE}"
  echo "        先に 06_forgejo.sh を実行してください。"
  exit 1
fi

if [[ -z "${FORGEJO_RUNNER_TOKEN:-}" ]]; then
  echo "[ERROR] FORGEJO_RUNNER_TOKEN が .env に設定されていません。"
  echo "        Forgejo 管理画面 ( https://git.seragl.io/-/admin/runners ) で"
  echo "        トークンを取得し、.env に追記してください。"
  exit 1
fi

# --------------------------------------------------------------------------
# ランナーデータディレクトリ作成
# --------------------------------------------------------------------------
echo "[INFO] ランナーデータディレクトリを作成します: ${RUNNER_DATA_DIR}"
mkdir -p "${RUNNER_DATA_DIR}"

# --------------------------------------------------------------------------
# すでに act_runner が追記済みか確認
# --------------------------------------------------------------------------
if grep -q "act_runner" "${COMPOSE_FILE}"; then
  echo "[INFO] act_runner はすでに docker-compose.yml に存在します。スキップします。"
else
  echo "[INFO] docker-compose.yml に act_runner を追記します..."
  cat >> "${COMPOSE_FILE}" <<EOF

  act_runner:
    image: code.forgejo.org/forgejo/runner:${RUNNER_VERSION}
    container_name: forgejo_runner
    restart: unless-stopped
    networks:
      - forgejo
    depends_on:
      - forgejo
    volumes:
      - ${RUNNER_DATA_DIR}:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - FORGEJO_INSTANCE_URL=http://forgejo:3000
      - FORGEJO_RUNNER_TOKEN=${FORGEJO_RUNNER_TOKEN}
      - FORGEJO_RUNNER_NAME=self-hosted-runner
      - FORGEJO_RUNNER_LABELS=ubuntu-latest:docker://node:20-bookworm,ubuntu-22.04:docker://node:20-bookworm,debian:docker://debian:bookworm
      - FORGEJO_RUNNER_MAX_JOB_CONCURRENCY=2
EOF
  echo "[INFO] 追記完了。"
fi

# --------------------------------------------------------------------------
# Forgejo 再起動（Actions 有効化）→ act_runner 起動
# --------------------------------------------------------------------------
echo "[INFO] Forgejo を再起動します..."
cd "${FORGEJO_DIR}"
docker compose up -d --force-recreate forgejo

echo "[INFO] act_runner を起動します..."
docker compose up -d act_runner

echo ""
echo "[INFO] 起動状態:"
docker compose ps

echo ""
echo "[INFO] ========================================="
echo "[INFO] act_runner デプロイ完了！"
echo "[INFO] ランナー確認: https://git.seragl.io/-/admin/runners"
echo "[INFO] ワークフロー: リポジトリ内 .forgejo/workflows/xxx.yml"
echo "[INFO] ========================================="
