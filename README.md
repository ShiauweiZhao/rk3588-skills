# RK3588 Skills

RK3588 开发板的调试技能集合。

## Skills

| Skill | 说明 |
|-------|------|
| [rk3588-ros-debug](rk3588-ros-debug-1.0.0/) | ROS 应用远程调试循环：编译 → 部署 → 运行 → 抓日志 → 分析 → 修复 |
| [rk3588-remote-ssh](rk3588-remote-ssh-1.0.0/) | 系统级远程调试：网络、磁盘、权限、服务、内核模块、日志等 |

## 使用

安装到 agents skills 目录：

```bash
cp -r rk3588-ros-debug-1.0.0 ~/.agents/skills/
cp -r rk3588-remote-ssh-1.0.0 ~/.agents/skills/
```

## 设备信息

默认板子配置（在 skill 中引用）：

```
IP:   192.168.8.105
用户: firefly
密码: firefly
端口: 22
```
