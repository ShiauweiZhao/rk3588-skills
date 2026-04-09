# Board Skills

嵌入式开发板的 AI Agent Skills，遵循 [Agent Skills 开放标准](https://agentskills.io)，参考 [superpowers](https://github.com/obra/superpowers) 架构设计。

适用于 **30+ AI Agent 产品**：OpenAI Codex、Cursor、GitHub Copilot、VS Code、Windsurf、Gemini CLI 等。

**支持所有可通过 SSH 访问的 Linux 嵌入式板子**：RK3588、Jetson、树莓派、STM32MP、全志、BeagleBone 等。

## Skills

| Skill | 说明 |
|-------|------|
| [using-board-skills](skills/using-board-skills/) | 入口 skill — 会话启动时自动注入，告诉 agent 如何使用所有 skills |
| [board-ros-debug](skills/board-ros-debug/) | ROS 应用远程调试循环：编译 -> 部署 -> 运行 -> 抓日志 -> 分析 -> 修复（通用，适用于任意 ROS 功能包） |
| [board-remote-ssh](skills/board-remote-ssh/) | 系统级远程调试：网络、磁盘、权限、服务、内核模块、日志、健康检查等 |

## 快速开始

### 1. 安装

```bash
chmod +x setup.sh && ./setup.sh
```

安装脚本使用 **symlink** 方式，将 `skills/` 目录链接到各 AI agent 的发现路径。支持 git pull 即时更新。

### 2. 配置设备连接

```bash
cp config/device.conf.example config/device.conf
# 编辑填入实际值
```

## 目录结构

```
board-skills/
├── skills/                              # Agent Skills 标准目录
│   ├── using-board-skills/             # 入口 skill（hooks 自动注入）
│   │   └── SKILL.md
│   ├── board-ros-debug/                # ROS 远程调试
│   │   ├── SKILL.md
│   │   └── scripts/
│   └── board-remote-ssh/               # 系统诊断
│       ├── SKILL.md
│       └── scripts/
├── hooks/                              # 会话 hooks
│   ├── hooks.json                      # Hook 配置（SessionStart）
│   └── session-start                   # 注入入口 skill 到会话上下文
├── config/
│   └── device.conf.example             # 设备连接配置模板
├── .codex/INSTALL.md                   # Codex 安装说明
├── .cursor-plugin/plugin.json          # Cursor 插件清单
├── GEMINI.md                           # Gemini CLI 入口
├── gemini-extension.json               # Gemini 扩展清单
├── setup.sh                            # 一键安装脚本
├── LICENSE
└── README.md
```

## 架构设计（参考 superpowers）

- **入口 skill** (`using-board-skills`) — 通过 `hooks/session-start` 在每次会话启动时自动注入，确保 agent 知道如何使用所有 skills
- **symlink 安装** — 不复制文件，用软链接指向仓库，`git pull` 即时更新
- **跨平台 hooks** — `session-start` 脚本自动适配 Claude Code (`CLAUDE_PLUGIN_ROOT`) 和 Cursor (`additional_context`)
- **平台适配文件** — `.cursor-plugin/plugin.json`、`.codex/INSTALL.md`、`GEMINI.md`、`gemini-extension.json`

## Agent Skills 开放标准

本仓库遵循 [agentskills.io](https://agentskills.io) 标准：

- `SKILL.md` YAML frontmatter + Markdown 指令
- `skills/` 目录为所有主流 agent 的通用发现路径
- 渐进式加载：metadata 先加载，按需加载详细指令
