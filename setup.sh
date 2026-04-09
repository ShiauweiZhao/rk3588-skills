#!/usr/bin/env bash
# Board Skills 安装脚本
# 使用 symlink 方式安装，与 superpowers 风格一致

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Symlink targets (主流 AI agent 发现路径)
TARGETS=(
  "$HOME/.agents/skills/board-skills"
  "$HOME/.cursor/skills/board-skills"
  "$HOME/.copilot/skills/board-skills"
  "$HOME/.codex/skills/board-skills"
  "$HOME/.gemini/skills/board-skills"
  "$HOME/.windsurf/rules/board-skills"
)

echo "=============================="
echo "  Board Skills 安装 (symlink)"
echo "=============================="
echo ""

for target in "${TARGETS[@]}"; do
  mkdir -p "$(dirname "$target")"
  if [ -L "$target" ]; then
    rm "$target"
    echo "  更新: $target"
  elif [ -d "$target" ]; then
    mv "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
    echo "  备份旧版本: ${target}.bak.*"
  fi
  ln -s "${SCRIPT_DIR}/skills" "$target"
  echo "  已链接: $target -> ${SCRIPT_DIR}/skills"
done

echo ""
echo "=============================="
echo "  安装完成!"
echo ""
echo "  Skills:"
echo "    - board-ros-debug     (ROS 远程调试循环)"
echo "    - board-remote-ssh    (系统诊断)"
echo "    - using-board-skills  (入口 skill，自动注入)"
echo ""
echo "  配置设备连接:"
echo "    cp config/device.conf.example config/device.conf"
echo "    # 编辑 device.conf 填入实际 IP、用户名、密码"
echo ""
echo "  全局配置（可选）:"
echo "    mkdir -p ~/.config/board-skills"
echo "    cp config/device.conf.example ~/.config/board-skills/device.conf"
echo ""
echo "  更新: cd $(dirname "$SCRIPT_DIR") && git pull"
echo "=============================="
