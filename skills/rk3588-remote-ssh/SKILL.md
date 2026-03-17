---
name: rk3588-remote-ssh
description: >-
  Diagnose and resolve RK3588 board problems through remote SSH. Triggered when user reports board
  connectivity issues, service crashes, system resource exhaustion, device access failures, boot
  performance problems, kernel errors, or package management issues. Handles: network failures
  (ping不通, 板子连不上), memory leaks, disk full errors, permission denied on /dev devices, slow
  boot times, systemd service failures, dmesg error analysis, USB/serial/GPIO device issues, APT
  dependency repair, and comprehensive system health checks. NOT for application development or NPU.
compatibility: Requires ssh, sshpass. Designed for RK3588 (Rockchip) boards running Linux.
license: MIT
metadata:
  version: "1.2.0"
  author: rk3588-skills
---

# RK3588 远程 SSH 系统调试

通过 SSH 远程诊断和修复 RK3588 板子的系统问题。

## 设备连接

**使用此 skill 前，必须先获取设备连接信息。** 按以下优先级获取：

1. 读取项目根目录下 `config/device.conf`
2. 读取全局配置 `~/.config/rk3588-skills/device.conf`
3. 如果配置文件均不存在，**向用户询问** IP、用户名、密码

### 连接命令模板

```bash
# 单条命令
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} '命令'

# 多条命令（heredoc）
sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
命令1; 命令2
EOF
```

## 诊断协议

接到问题后，按 **信息收集 → 根因定位 → 修复 → 验证** 四步走。先收集足够的系统信息再下结论，避免基于猜测做修复。

### 全面信息收集

不确定问题出在哪里时，先跑一次全面收集：

```bash
sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
echo "=== 概览 ==="
echo "内核: $(uname -r) $(uname -m)  发行版: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "运行时间: $(uptime -p)  负载: $(cat /proc/loadavg)"
echo "=== CPU ==="; lscpu | grep -E "^(Architecture|CPU\(s\)|Model name|CPU MHz)"
echo "=== 内存 ==="; free -h
echo "=== 磁盘 ==="; df -h / /boot /data 2>/dev/null
echo "=== 网络 ==="; ip -4 addr show | grep -E "inet |^[0-9]" | head -20
echo "=== 温度 ==="
for z in /sys/class/thermal/thermal_zone*/; do
  type=$(cat ${z}type 2>/dev/null); temp=$(cat ${z}temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}')
  echo "  ${type##*/}: $temp"
done
echo "=== 服务 ==="; systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20
echo "=== 高资源进程 ==="; ps aux --sort=-%mem | head -11
echo "=== 系统日志错误 ==="; journalctl -p err --no-pager -n 20 2>/dev/null || tail -20 /var/log/syslog 2>/dev/null
echo "=== dmesg 错误 ==="; dmesg -T --level=err,warn 2>/dev/null | tail -20
echo "=== USB ==="; lsusb 2>/dev/null
echo "=== 内核模块 ==="; lsmod | grep -E "rk|mipi|gpu|vpu|cec|ion" || echo "无 RK 特殊模块"
EOF
```

## 诊断模块索引

根据用户描述的问题，选择对应的模块执行。如果不确定，先跑上面的全面信息收集。

| 用户症状 | 使用模块 |
|---------|---------|
| 板子连不上、网络不通、ping 失败 | [1. 网络](#1-网络) |
| 磁盘满了、空间不足、写入失败 | [2. 磁盘/存储](#2-磁盘存储) |
| 权限不足、Permission denied、无法访问设备 | [3. 权限](#3-权限) |
| 服务挂了、启动失败、某个程序不运行 | [4. 服务管理](#4-服务管理) |
| 串口/GPIO/USB/摄像头等设备不工作 | [5. 内核模块/设备树](#5-内核模块设备树) |
| CPU 占用高、内存不够、系统卡顿 | [6. 进程/性能](#6-进程性能) |
| apt 报错、依赖损坏、包安装失败 | [7. APT 包管理](#7-apt-包管理) |
| 看系统日志、找错误原因 | [8. 日志分析](#8-日志分析) |
| 开机慢、启动失败的服务 | [9. 开机启动/引导](#9-开机启动引导) |
| 全面检查板子状态 | [10. 一键健康检查](#10-一键系统健康检查) |

---

## 1. 网络

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
ip link show; echo ""; ip addr show; echo ""; ip route
echo "=== DNS ==="; cat /etc/resolv.conf
echo "=== 连通性 ==="; ping -c 2 -W 2 8.8.8.8 2>&1 | tail -3
echo "=== 端口 ==="; ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
echo "=== 以太网 ==="; ethtool eth0 2>/dev/null | grep -E "Speed|Link detected" || echo "eth0 不存在"
EOF
```
修复: `sudo systemctl restart NetworkManager` 或 `sudo systemctl restart networking`

## 2. 磁盘/存储

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
df -h; echo ""; df -i | grep -v "^tmpfs"; echo ""; lsblk -f
EOF
```
修复: `sudo apt-get clean && sudo apt-get autoremove -y` / `sudo journalctl --vacuum-time=3d`

## 3. 权限

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
id; echo ""; groups; echo ""; sudo -l 2>&1 | head -10
ls -la /dev/ttyS9 /dev/gpiochip3 /dev/video0 2>/dev/null
EOF
```
修复: `sudo usermod -a -G dialout {user}` / `sudo usermod -a -G gpio {user}` + udev 规则

## 4. 服务管理

```bash
SERVICE_NAME="目标服务名"
systemctl status $SERVICE_NAME; journalctl -u $SERVICE_NAME --no-pager -n 50
```

## 5. 内核模块/设备树

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 内核 ==="; uname -r
echo "=== 模块 ==="; lsmod | grep -iE "rk|mipi|gpu|vpu|rockchip|v4l2|i2c|spi"
echo "=== GPIO ==="; ls -la /dev/gpiochip* 2>/dev/null; gpiodetect 2>/dev/null
echo "=== 串口 ==="; ls -la /dev/ttyS* /dev/ttyUSB* 2>/dev/null
echo "=== USB ==="; lsusb
echo "=== dmesg ==="; dmesg -T | grep -iE "rk3588|rockchip|gpio|i2c|spi|uart" | tail -30
echo "=== 设备树 ==="; ls /sys/firmware/devicetree/base/ 2>/dev/null | head -30
EOF
```

## 6. 进程/性能

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== CPU ==="; top -bn1 -o %CPU | head -20
echo "=== 内存 ==="; top -bn1 -o %MEM | head -20
echo "=== 僵尸 ==="; ps aux | awk '$8 ~ /Z/ {print}'
echo "=== IO ==="; iostat -x 1 2 2>/dev/null | tail -20 || vmstat 1 3
echo "=== 网络连接 ==="; ss -s 2>/dev/null
EOF
```

## 7. APT 包管理

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
apt list --upgradable 2>/dev/null | head -20
dpkg -l | grep -E "^..H" | head -10
sudo apt-get check 2>&1 | head -10
EOF
```
修复: `sudo dpkg --configure -a && sudo apt-get install -f`

## 8. 日志分析

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
journalctl -p err --no-pager --since "1 hour ago" 2>/dev/null | tail -30
dmesg -T --level=err,warn 2>/dev/null | tail -30
dmesg -T | grep -i "out of memory\|oom\|killed process" | tail -10
EOF
```

## 9. 开机启动/引导

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
systemd-analyze 2>/dev/null
systemd-analyze blame 2>/dev/null | head -11
systemctl --failed
EOF
```

## 10. 一键系统健康检查

将 `scripts/health-check.sh` 传输到板子上执行，或直接通过 SSH 内联运行：

```bash
sshpass -p '{pass}' ssh {user}@{host} 'bash -s' < scripts/health-check.sh
```

或直接通过 SSH 远程调用（脚本已内嵌所有逻辑，会输出结构化的健康报告）。

## 修复验证汇报格式

```
[问题] {用户描述的问题}
[诊断] {根因分析}
[修复] {执行了什么操作}
[验证] {修复后状态}
[建议] {后续注意事项}
```
