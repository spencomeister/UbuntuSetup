#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 00_preflight.sh - 前提チェック
# =============================================================================

echo "[INFO] 前提チェックを開始します..."

# --------------------------------------------------------------------------
# root 権限確認
# --------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] このスクリプトは root 権限で実行してください。"
  echo "        sudo bash setup.sh"
  exit 1
fi

# --------------------------------------------------------------------------
# OS バージョン確認
# --------------------------------------------------------------------------
if [[ ! -f /etc/os-release ]]; then
  echo "[ERROR] /etc/os-release が見つかりません。Ubuntu 環境で実行してください。"
  exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]] || [[ "${VERSION_ID:-}" != "26.04" ]]; then
  echo "[ERROR] このスクリプトは Ubuntu 26.04 LTS 専用です。"
  echo "        検出された OS: ${PRETTY_NAME:-不明}"
  exit 1
fi

echo "[INFO] OS 確認 OK: ${PRETTY_NAME}"

# --------------------------------------------------------------------------
# .env 存在確認（setup.sh から export 済みだが、ファイル自体の存在も確認）
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] .env が見つかりません: ${ENV_FILE}"
  echo "        cp .env.sample .env を実行して設定してください。"
  exit 1
fi

echo "[INFO] .env 確認 OK: ${ENV_FILE}"

# --------------------------------------------------------------------------
# 必須環境変数の確認
# --------------------------------------------------------------------------
REQUIRED_VARS=(
  CF_API_TOKEN
  CF_ZONE_ID
  FORGEJO_SECRET_KEY
  ZABBIX_DB_PASSWORD
)

for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR:-}" ]]; then
    echo "[ERROR] 必須環境変数が未設定です: ${VAR}"
    echo "        .env を確認してください。"
    exit 1
  fi
done

echo "[INFO] 必須環境変数の確認 OK"

# --------------------------------------------------------------------------
# unattended-upgrades の一時停止
# --------------------------------------------------------------------------
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
  echo "[INFO] unattended-upgrades を一時停止します..."
  systemctl stop unattended-upgrades
  systemctl disable unattended-upgrades
  echo "[WARN] unattended-upgrades を無効化しました。"
  echo "[WARN] セットアップ完了後に必要であれば再度有効化してください:"
  echo "       sudo systemctl enable --now unattended-upgrades"
else
  echo "[INFO] unattended-upgrades は既に停止しています。"
fi

# --------------------------------------------------------------------------
# APT ロック解放待ち
# --------------------------------------------------------------------------
echo "[INFO] APT ロックを確認します..."
for i in $(seq 1 12); do
  if ! fuser /var/lib/dpkg/lock-frontend > /dev/null 2>&1; then
    break
  fi
  echo "[INFO] APT ロック待ち... (${i}/12)"
  sleep 5
done

DEBIAN_FRONTEND=noninteractive apt-get update -qq
echo "[INFO] APT パッケージリスト更新 OK"

echo "[INFO] 前提チェック完了。"
