#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup.sh - メインセットアップスクリプト
# 使い方: sudo bash setup.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# .env の存在確認と読み込み
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] .env が見つかりません。.env.sample をコピーして設定してください。"
  echo "        cp .env.sample .env"
  exit 1
fi

# shellcheck source=.env.sample
# set -a で全変数を自動 export → 各モジュールのサブシェルから参照可能にする
set -a
source "${ENV_FILE}"
set +a

# モジュール実行関数
run_module() {
  local module="$1"
  local module_path="${MODULES_DIR}/${module}"

  if [[ ! -f "${module_path}" ]]; then
    echo "[ERROR] モジュールが見つかりません: ${module_path}"
    exit 1
  fi

  echo ""
  echo "========================================"
  echo "[INFO] 実行中: ${module}"
  echo "========================================"

  bash "${module_path}" || {
    echo "[ERROR] ${module} が失敗しました。セットアップを中断します。"
    exit 1
  }
}

# 各モジュールを順番に実行
run_module "00_preflight.sh"
run_module "01_locale_tz.sh"
run_module "02_base_packages.sh"
run_module "03_security.sh"
run_module "04_docker.sh"
run_module "05_tailscale.sh"
run_module "06a_swap.sh"          # ← 06_forgejo.sh の前に追加
run_module "06_forgejo.sh"
run_module "06b_forgejo_runner.sh" # ← 06_forgejo.sh の直後に追加
run_module "07_cloudflare_dns.sh"
run_module "08_zabbix.sh"
run_module "09_caddy.sh"

echo ""
echo "========================================"
echo "[INFO] すべてのセットアップが完了しました。"
echo "       README.md を参照し、事後手動設定を行ってください。"
echo "========================================"
