#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# 06a_swap.sh - Swap 領域の拡張（2GB → 4GB）
# Android/Java 等の重いビルドに備えたメモリ確保
# =============================================================================
echo "[INFO] Swap 領域の設定を開始します..."

TARGET_SWAP_GB=4
SWAP_FILE="/swapfile"

# --------------------------------------------------------------------------
# 現在の Swap 確認
# --------------------------------------------------------------------------
CURRENT_SWAP=$(free -m | awk '/^Swap:/ {print $2}')
echo "[INFO] 現在の Swap サイズ: ${CURRENT_SWAP}MB"

if [[ "${CURRENT_SWAP}" -ge $((TARGET_SWAP_GB * 1024)) ]]; then
  echo "[INFO] すでに ${TARGET_SWAP_GB}GB 以上の Swap が存在します。スキップします。"
  exit 0
fi

# --------------------------------------------------------------------------
# 既存 Swap を無効化
# --------------------------------------------------------------------------
if [[ "${CURRENT_SWAP}" -gt 0 ]]; then
  echo "[INFO] 既存の Swap を無効化します..."
  swapoff "${SWAP_FILE}" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# 新しい Swap ファイルを作成
# --------------------------------------------------------------------------
echo "[INFO] ${TARGET_SWAP_GB}GB の Swap ファイルを作成します..."
fallocate -l "${TARGET_SWAP_GB}G" "${SWAP_FILE}"
chmod 600 "${SWAP_FILE}"
mkswap "${SWAP_FILE}"
swapon "${SWAP_FILE}"

# --------------------------------------------------------------------------
# 永続化（/etc/fstab）
# --------------------------------------------------------------------------
if ! grep -q "${SWAP_FILE}" /etc/fstab; then
  echo "[INFO] /etc/fstab に永続設定を追記します..."
  echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
fi

# --------------------------------------------------------------------------
# swappiness を調整（CI サーバー向け：Swap を使いすぎないよう抑制）
# --------------------------------------------------------------------------
echo "[INFO] vm.swappiness を 10 に設定します..."
sysctl vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
  echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo ""
echo "[INFO] Swap 設定完了:"
free -h
