---
name: rk3588-remote-ssh
description: RK3588 远程 SSH 系统调试。当用户要求诊断 RK3588 板子系统问题、检查网络/磁盘/权限/服务/内核模块、查看设备日志、做系统健康检查、修复板子系统故障时触发。
compatibility: Requires ssh, sshpass. Designed for RK3588 (Rockchip) boards running Linux.
license: MIT
metadata:
  version: "1.1.0"
  author: rk3588-skills
---

# RK3588 远程 SSH 系统调试

通过 SSH 远程诊断和修复 RK3588 板子的任何系统问题。

## 设备连接

**使用此 skill 前，必须先获取设备连接信息。** 按以下优先级获取：

1. 读取项目根目录下 `config/device.conf`
2. 读取全局配置 `~/.config/rk3588-skills/device.conf`
3. 如果配置文件均不存在，**向用户询问** IP、用户名、密码

### 连接命令模板

```bash
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} '命令'

sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
命令1; 命令2
EOF
```

## 诊断协议

接到问题后，按 **信息收集 -> 根因定位 -> 修复 -> 验证** 四步走。

### 第一步：全面信息收集

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

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
PASS=0; WARN=0; FAIL=0
report() { if [ "$1" = "ok" ]; then PASS=$((PASS+1)); echo "  [OK]   $2"; elif [ "$1" = "warn" ]; then WARN=$((WARN+1)); echo "  [WARN] $2"; else FAIL=$((FAIL+1)); echo "  [FAIL] $2"; fi; }
echo "╔══════════════════════════════════════╗"
echo "║   RK3588 系统健康检查               ║"
echo "╚══════════════════════════════════════╝"
echo "[网络]"
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && report ok "外网连通" || report fail "外网不通"
ip addr show | grep -q "192.168" && report ok "局域网 IP 正常" || report warn "未检测到局域网 IP"
echo "[存储]"
USE=$(df / | awk 'NR==2{gsub("%","",$5); print $5}')
[ "$USE" -lt 90 ] && report ok "根分区使用 ${USE}%" || report fail "根分区已满 ${USE}%"
echo "[内存]"
MEM_AVAIL=$(free | awk '/Mem:/{printf "%.0f", $7/$2*100}')
[ "$MEM_AVAIL" -gt 15 ] && report ok "可用内存 ${MEM_AVAIL}%" || report warn "可用内存仅 ${MEM_AVAIL}%"
echo "[温度]"
TEMP=$(awk '{printf "%.0f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 999)
[ "$TEMP" -lt 75 ] && report ok "CPU ${TEMP}C" || [ "$TEMP" -lt 85 ] && report warn "偏高 ${TEMP}C" || report fail "过热 ${TEMP}C"
echo "[SSH]"
systemctl is-active sshd >/dev/null 2>&1 && report ok "SSH 运行" || report fail "SSH 未运行"
echo "[串口]"
[ -c /dev/ttyS9 ] && report ok "ttyS9 存在" || report warn "ttyS9 不存在"
groups {user} | grep -q dialout && report ok "dialout 权限" || report warn "无 dialout 权限"
echo "[GPIO]"
gpiodetect >/dev/null 2>&1 && report ok "libgpiod 可用" || report warn "libgpiod 不可用"
groups {user} | grep -q gpio && report ok "GPIO 权限" || report warn "无 gpio 权限"
echo "═══════════════════════════════════════"
echo "  通过: ${PASS}  警告: ${WARN}  失败: ${FAIL}"
echo "═══════════════════════════════════════"
EOF
```

## 修复验证汇报格式

```
[问题] {用户描述的问题}
[诊断] {根因分析}
[修复] {执行了什么操作}
[验证] {修复后状态}
[建议] {后续注意事项}
```
