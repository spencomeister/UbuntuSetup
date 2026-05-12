#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 04_docker.sh - Docker のインストール
# Docker 公式リポジトリ（keyrings 方式）を使用
# =============================================================================

echo "[INFO] Docker のインストールを開始します..."

# --------------------------------------------------------------------------
# 既にインストール済みの場合は docker グループへの追加のみ確認
# --------------------------------------------------------------------------
if command -v docker > /dev/null 2>&1; then
  echo "[INFO] Docker は既にインストールされています: $(docker --version)"
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "${SUDO_USER}"
    echo "[INFO] ${SUDO_USER} を docker グループに追加しました。"
  fi
  exit 0
fi

# --------------------------------------------------------------------------
# 旧バージョンの Docker を削除
# --------------------------------------------------------------------------
echo "[INFO] 旧バージョンの Docker を削除します（存在する場合）..."
DEBIAN_FRONTEND=noninteractive apt-get remove -y \
  docker docker-engine docker.io containerd runc 2>/dev/null || true

# --------------------------------------------------------------------------
# 依存パッケージのインストール
# --------------------------------------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# --------------------------------------------------------------------------
# Docker 公式 GPG キーの配置（keyrings 方式）
# --------------------------------------------------------------------------
echo "[INFO] Docker 公式 GPG キーを配置します..."
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# --------------------------------------------------------------------------
# Docker 公式 APT リポジトリを追加
# --------------------------------------------------------------------------
echo "[INFO] Docker 公式 APT リポジトリを追加します..."

# Ubuntu コードネームを取得（os-release の UBUNTU_CODENAME を優先）
UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
if [[ -z "${UBUNTU_CODENAME}" ]]; then
  echo "[ERROR] Ubuntu コードネームを取得できませんでした。"
  exit 1
fi

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  ${UBUNTU_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

DEBIAN_FRONTEND=noninteractive apt-get update -qq

# --------------------------------------------------------------------------
# Docker CE のインストール
# --------------------------------------------------------------------------
echo "[INFO] Docker CE をインストールします..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# --------------------------------------------------------------------------
# 自動起動の有効化
# --------------------------------------------------------------------------
systemctl enable --now docker
echo "[INFO] Docker の自動起動を有効化しました。"

# --------------------------------------------------------------------------
# 実行ユーザーを docker グループに追加
# --------------------------------------------------------------------------
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "${SUDO_USER}"
  echo "[INFO] ${SUDO_USER} を docker グループに追加しました。"
  echo "[INFO] 反映にはログアウト・ログインが必要です。"
else
  echo "[WARN] SUDO_USER が設定されていません。docker グループへの追加をスキップします。"
  echo "[WARN] 必要なユーザーを手動で追加してください: usermod -aG docker <username>"
fi

echo "[INFO] Docker インストール完了: $(docker --version)"
