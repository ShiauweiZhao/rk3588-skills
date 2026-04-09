---
name: using-board-skills
description: >-
  Embedded board remote operations via SSH. Use for board management, ROS deployment, debugging,
  and diagnostics. Triggers on embedded board, ARM board, development board, "板子" (board),
  ROS/catkin_make/roslaunch, remote SSH, system health checks, service restart, network diagnostics,
  driver development, cross-compilation, embedded Linux troubleshooting, or deploying to embedded boards.
  Supports RK3588, Jetson, Raspberry Pi, STM32MP, Allwinner, and any Linux-based embedded board.
---

# Embedded Board Skills 使用指南

本技能集帮助你通过 SSH 远程管理各类嵌入式开发板（RK3588、Jetson、树莓派、STM32MP 等），覆盖 ROS 开发调试和系统运维两大场景。

## 可用技能

| 技能 | 适用场景 | 触发关键词 |
|------|---------|-----------|
| **board-ros-debug** | 编译、部署、运行、调试 ROS 节点到板子 | catkin_make、roslaunch、部署、编译、运行节点、抓日志、topic、ROS |
| **board-remote-ssh** | 诊断板子系统问题 | 网络、磁盘、权限、服务、内核模块、日志、健康检查、温度、串口、GPIO、USB |

**如何选择：** 如果任务涉及 ROS 编译/部署/运行 → 用 `board-ros-debug`。如果是系统层面的问题（网络不通、磁盘满了、权限不对、服务挂了）→ 用 `board-remote-ssh`。两者可以组合使用。

## 设备连接

所有技能都需要设备连接信息。按以下优先级获取：

1. 项目配置：`config/device.conf`（项目根目录下）
2. 全局配置：`~/.config/board-skills/device.conf`
3. 都没有 → **向用户询问** IP、用户名、密码

配置格式：
```
HOST=192.168.8.105
USER=firefly
PASS=firefly
PORT=22
```

## 占位符约定

所有命令中的占位符（AI 执行前必须替换为实际值）：
- `{host}` = 设备 IP 地址
- `{user}` = SSH 用户名
- `{pass}` = SSH 密码
- `{port}` = SSH 端口（默认 22）

## 如何访问技能

**Claude Code:** 使用 `Skill` 工具调用，不要直接 Read skill 文件。

**Codex:** 通过 `~/.agents/skills/` 原生发现。

**Cursor / Gemini CLI:** 从 `.cursor/skills/` 或 `.gemini/` 激活。
