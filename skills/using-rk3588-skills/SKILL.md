---
name: using-rk3588-skills
description: Use when starting any conversation about RK3588 development, ROS debugging, or remote board management - establishes how to find and use RK3588 skills
---

<EXTREMELY-IMPORTANT>
If you are working on anything related to RK3588, ROS, or remote embedded board development, you MUST check for relevant skills before responding.

IF AN RK3588 SKILL APPLIES TO YOUR TASK, YOU MUST USE IT.
</EXTREMELY-IMPORTANT>

# Using RK3588 Skills

## Available Skills

| Skill | Trigger |
|-------|---------|
| **rk3588-ros-debug** | 编译/部署/运行/调试 ROS 节点到 RK3588，远程抓取 ROS 日志 |
| **rk3588-remote-ssh** | 诊断 RK3588 系统问题（网络/磁盘/权限/服务/内核/日志） |

## Device Connection

**Before using any RK3588 skill**, read device connection info:

1. Project config: `config/device.conf` (in project root)
2. Global config: `~/.config/rk3588-skills/device.conf`
3. If neither exists, **ask the user** for IP, username, password

Config format:
```
HOST=192.168.8.105
USER=firefly
PASS=firefly
PORT=22
```

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. Never use Read on skill files.

**In Codex:** Skills are loaded via native skill discovery from `~/.agents/skills/`.

**In Cursor/Gemini CLI:** Skills activate from `.cursor/skills/` or `.gemini/`.

## Placeholder Convention

All commands use these placeholders (AI must substitute before executing):
- `{host}` = device IP
- `{user}` = SSH username
- `{pass}` = SSH password
- `{port}` = SSH port (default 22)

## The Rule

**Invoke relevant skills BEFORE any response or action.** Even a 1% chance a skill applies means you should check.
