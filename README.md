# RK3588 Skills

RK3588 开发板的调试技能集合。

## Skills

| Skill | 说明 |
|-------|------|
| [rk3588-ros-debug](rk3588-ros-debug-1.0.0/) | ROS 应用远程调试循环：编译 → 部署 → 运行 → 抓日志 → 分析 → 修复（通用，适用于任意 ROS 功能包） |
| [rk3588-remote-ssh](rk3588-remote-ssh-1.0.0/) | 系统级远程调试：网络、磁盘、权限、服务、内核模块、日志等 |

## 使用

安装到 agents skills 目录：

```bash
cp -r rk3588-ros-debug-1.0.0 ~/.agents/skills/
cp -r rk3588-remote-ssh-1.0.0 ~/.agents/skills/
```

## 设备配置

两个 skill 共享设备连接信息。优先从配置文件读取，未找到则向用户询问。

### 配置文件 (`/workspace/config/device.conf`)

```
HOST=192.168.8.105
USER=firefly
PASS=firefly
PORT=22
```

将此文件放在项目的 `config/device.conf` 路径下即可，两个 skill 都会自动读取。
