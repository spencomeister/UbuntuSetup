#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 05_tailscale.sh - Tailscale のインストール
# TAILSCALE_AUTHKEY が設定されている場合は自動認証を行う（Option A）
# =============================================================================

echo "[INFO] Tailscale のインストールを開始します..."

# --------------------------------------------------------------------------
# 既にインストール済みの場合は tailscaled の有効化のみ確認
# --------------------------------------------------------------------------
if command -v tailscale > /dev/null 2>&1; then
  echo "[INFO] Tailscale は既にインストールされています: $(tailscale --version | head -1)"
  systemctl enable --now tailscaled
else
  # --------------------------------------------------------------------------
  # インストールスクリプトをダウンロードして検証・実行
  # --------------------------------------------------------------------------
  INSTALL_SCRIPT="$(mktemp /tmp/tailscale-install.XXXXXX.sh)"

  echo "[INFO] Tailscale インストールスクリプトをダウンロードします..."
  curl -fsSL https://tailscale.com/install.sh -o "${INSTALL_SCRIPT}"

  # ファイルが空でないことを確認
  if [[ ! -s "${INSTALL_SCRIPT}" ]]; then
    echo "[ERROR] インストールスクリプトのダウンロードに失敗しました（空ファイル）。"
    rm -f "${INSTALL_SCRIPT}"
    exit 1
  fi

  # シバン行の簡易検証（不正なコンテンツでないことを確認）
  if ! head -1 "${INSTALL_SCRIPT}" | grep -q "^#!"; then
    echo "[ERROR] ダウンロードしたファイルが不正です（シバン行なし）。"
    rm -f "${INSTALL_SCRIPT}"
    exit 1
  fi

  chmod +x "${INSTALL_SCRIPT}"
  bash "${INSTALL_SCRIPT}"
  rm -f "${INSTALL_SCRIPT}"

  systemctl enable --now tailscaled
  echo "[INFO] Tailscale インストール・自動起動を有効化しました。"
fi

# --------------------------------------------------------------------------
# 認証（Option A: TAILSCALE_AUTHKEY が設定されていれば自動実行）
# --------------------------------------------------------------------------
if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
  echo "[INFO] TAILSCALE_AUTHKEY が設定されています。tailscale up を実行します..."
  tailscale up --authkey "${TAILSCALE_AUTHKEY}" --accept-routes
  echo "[INFO] Tailscale の認証が完了しました。"
  echo "[INFO] Tailscale IP: $(tailscale ip -4 2>/dev/null || echo '取得中...')"
else
  echo "[INFO] TAILSCALE_AUTHKEY が設定されていません。"
  echo "[INFO] Tailscale の認証は以下のコマンドで手動実行してください:"
  echo "       sudo tailscale up"
fi

echo "[INFO] Tailscale インストール完了。"
