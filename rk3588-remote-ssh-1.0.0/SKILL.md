---
name: rk3588-remote-ssh
description: 通过 SSH 远程连接 RK3588 板子，诊断和修复系统级问题：网络、磁盘、权限、服务、包管理、内核模块、设备树、日志等。
metadata: {"clawdbot":{"emoji":"🖥️","os":["darwin","linux"],"requires":{"bins":["ssh"]}}}
---

# RK3588 远程 SSH 系统调试

通过 SSH 远程诊断和修复 RK3588 (Firefly) 板子的任何系统问题。

---

## 设备连接

**使用此 skill 前，必须先获取设备连接信息。** 按以下优先级获取：

1. 读取配置文件 `/workspace/config/device.conf`（格式见下文）
2. 如果配置文件不存在，**向用户询问** IP、用户名、密码

### 配置文件格式 (`/workspace/config/device.conf`)

```
HOST=192.168.8.105
USER=firefly
PASS=firefly
PORT=22
```

### 连接信息占位符

本 skill 中所有命令使用以下占位符，AI 在执行前**必须替换为实际值**：

| 占位符 | 含义 | 示例 |
|--------|------|------|
| `{host}` | 设备 IP 地址 | `192.168.8.105` |
| `{user}` | SSH 用户名 | `firefly` |
| `{pass}` | SSH 密码 | `firefly` |
| `{port}` | SSH 端口（默认 22） | `22` |

### 快速连接模板

```bash
# 单条命令
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} '命令'

# 多条命令（heredoc）
sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
命令1
命令2
EOF

# 交互式会话（需保留终端时）
sshpass -p '{pass}' ssh -t -p {port} {user}@{host}
```

---

## 诊断协议

接到问题后，按 **信息收集 → 根因定位 → 修复 → 验证** 四步走。

### 第一步：全面信息收集

```bash
sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
echo "========== 系统概览 =========="
echo "主机: $(hostname)"
echo "内核: $(uname -r) $(uname -m)"
echo "发行版: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "运行时间: $(uptime -p)"
echo "负载: $(cat /proc/loadavg)"
echo ""
echo "========== CPU =========="
lscpu | grep -E "^(Architecture|CPU\(s\)|Model name|CPU MHz)"
echo ""
echo "========== 内存 =========="
free -h
echo ""
echo "========== 磁盘 =========="
df -h / /boot /data 2>/dev/null
echo ""
echo "========== 网络 =========="
ip -4 addr show | grep -E "inet |^[0-9]" | head -20
echo ""
echo "========== CPU 温度 =========="
for z in /sys/class/thermal/thermal_zone*/; do
  type=$(cat ${z}type 2>/dev/null)
  temp=$(cat ${z}temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}')
  echo "  ${type##*/}: $temp"
done
echo ""
echo "========== 运行中的服务 =========="
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20
echo ""
echo "========== 高资源进程 TOP10 =========="
ps aux --sort=-%mem | head -11
echo ""
echo "========== 最近系统日志 (错误) =========="
journalctl -p err --no-pager -n 20 2>/dev/null || tail -20 /var/log/syslog 2>/dev/null
echo ""
echo "========== dmesg 最近错误 =========="
dmesg -T --level=err,warn 2>/dev/null | tail -20
echo ""
echo "========== USB 设备 =========="
lsusb 2>/dev/null
echo ""
echo "========== 设备树覆盖 =========="
ls /sys/kernel/config/device-tree/overlays/ 2>/dev/null || echo "无 overlay 信息"
echo ""
echo "========== 已加载内核模块 =========="
lsmod | grep -E "rk|mipi|gpu|vpu|cec|ion" || echo "无 RK 特殊模块"
echo ""
echo "========== 开机启动项 =========="
systemctl list-unit-files --state=enabled --no-pager 2>/dev/null | head -20
EOF
```

### 第二步：根据问题类别深入诊断

按用户描述的问题，跳到对应章节执行诊断命令。

---

## 1. 网络问题

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 网络接口 ==="
ip link show
echo ""
echo "=== IP 地址 ==="
ip addr show
echo ""
echo "=== 路由表 ==="
ip route
echo ""
echo "=== DNS ==="
cat /etc/resolv.conf
echo ""
echo "=== 防火墙 ==="
sudo iptables -L -n 2>/dev/null | head -20
sudo ufw status 2>/dev/null
echo ""
echo "=== 网络连通性测试 ==="
ping -c 2 -W 2 8.8.8.8 2>&1 | tail -3
ping -c 2 -W 2 baidu.com 2>&1 | tail -3
echo ""
echo "=== 端口监听 ==="
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
echo ""
echo "=== WiFi (如果有) ==="
iwconfig 2>/dev/null || echo "无 WiFi 接口"
nmcli device status 2>/dev/null || echo "NetworkManager 未运行"
echo ""
echo "=== 以太网 ==="
ethtool eth0 2>/dev/null | grep -E "Speed|Link detected|Duplex" || echo "eth0 不存在"
EOF
```

### 常见修复

```bash
# 重启网络
sudo systemctl restart NetworkManager 2>/dev/null || sudo systemctl restart networking
# 或重启特定接口
sudo ip link set eth0 down && sudo ip link set eth0 up

# 修改静态 IP
sudo tee /etc/network/interfaces.d/eth0 > /dev/null << 'NET'
auto eth0
iface eth0 inet static
    address {host}
    netmask 255.255.255.0
    gateway 192.168.8.1
    dns-nameservers 8.8.8.8
NET
sudo systemctl restart networking

# 清除 DNS 缓存
sudo systemd-resolve --flush-caches 2>/dev/null

# 修改 DNS
sudo tee /etc/resolv.conf > /dev/null << 'DNS'
nameserver 8.8.8.8
nameserver 8.8.4.4
DNS
```

---

## 2. 磁盘/存储问题

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 磁盘使用 ==="
df -h
echo ""
echo "=== inode 使用 ==="
df -i | grep -v "^tmpfs"
echo ""
echo "=== 大文件 TOP20 ==="
sudo find / -xdev -type f -size +50M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h | tail -20
echo ""
echo "=== 分区信息 ==="
lsblk -f
echo ""
echo "=== 挂载点 ==="
mount | column -t
echo ""
echo "=== eMMC/SD 信息 ==="
sudo fdisk -l /dev/mmcblk* 2>/dev/null | head -30
echo ""
echo "=== U盘/外接存储 ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "sd|usb"
EOF
```

### 常见修复

```bash
# 清理 apt 缓存
sudo apt-get clean && sudo apt-get autoremove -y

# 清理日志
sudo journalctl --vacuum-time=3d
sudo truncate -s 0 /var/log/syslog

# 清理 ROS log
rm -rf ~/.ros/log/*

# 清理编译缓存
rm -rf ~/ros_ws/build ~/ros_ws/devel

# 修复磁盘（只读模式）
sudo mount -o remount,rw /
sudo fsck -y /dev/mmcblk2p2  # 根据实际分区调整
```

---

## 3. 权限问题

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 当前用户 ==="
id
echo ""
echo "=== 用户组 ==="
groups
echo ""
echo "=== sudo 权限 ==="
sudo -l 2>&1 | head -10
echo ""
echo "=== 指定文件权限 ==="
# 以下根据实际问题替换文件路径
ls -la /dev/ttyS9 /dev/gpiochip3 /dev/video0 2>/dev/null
echo ""
echo "=== udev 规则 ==="
ls /etc/udev/rules.d/
cat /etc/udev/rules.d/*.rules 2>/dev/null
echo ""
echo "=== 特殊文件权限 ==="
find /dev -maxdepth 1 -type c -o -type b 2>/dev/null | head -20
EOF
```

### 常见修复

```bash
# 添加串口权限
sudo usermod -a -G dialout {user}

# 添加 GPIO 权限
sudo groupadd gpio 2>/dev/null
sudo usermod -a -G gpio {user}
sudo tee /etc/udev/rules.d/99-gpio.rules > /dev/null << 'UDEV'
KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
KERNEL=="gpio*", GROUP="gpio", MODE="0660"
UDEV
sudo udevadm control --reload-rules && sudo udevadm trigger

# 添加视频设备权限
sudo usermod -a -G video {user}

# 修复 sudoers
sudo visudo -c  # 先检查语法

# 修复文件权限
sudo chmod 666 /dev/ttyS9
sudo chown {user}:{user} /path/to/file
```

---

## 4. 服务管理

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
SERVICE_NAME="目标服务名"  # 替换为实际服务名

echo "=== 服务状态 ==="
systemctl status $SERVICE_NAME 2>/dev/null || echo "服务不存在"

echo "=== 最近日志 ==="
journalctl -u $SERVICE_NAME --no-pager -n 50 2>/dev/null

echo "=== 服务配置 ==="
systemctl cat $SERVICE_NAME 2>/dev/null

echo "=== 开机自启 ==="
systemctl is-enabled $SERVICE_NAME 2>/dev/null
EOF
```

### 服务操作

```bash
# 启动/停止/重启
sudo systemctl restart 服务名
sudo systemctl stop 服务名
sudo systemctl start 服务名

# 设置开机自启
sudo systemctl enable 服务名

# 查看日志（实时跟踪）
sudo journalctl -u 服务名 -f

# 查看最近失败的服务
systemctl --failed
```

---

## 5. 内核模块 / 设备树

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 内核版本 ==="
uname -r
echo ""
echo "=== 已加载模块（RK 相关）==="
lsmod | grep -iE "rk|mipi|gpu|vpu|rockchip|v4l2|i2c|spi"
echo ""
echo "=== GPIO 控制器 ==="
ls -la /dev/gpiochip* 2>/dev/null
gpiodetect 2>/dev/null
echo ""
echo "=== I2C 总线 ==="
ls -la /dev/i2c-* 2>/dev/null
for i in /dev/i2c-*; do echo "--- $i ---"; i2cdetect -y ${i##*-} 2>/dev/null; done
echo ""
echo "=== SPI 总线 ==="
ls -la /dev/spidev* 2>/dev/null
echo ""
echo "=== 串口设备 ==="
ls -la /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
echo ""
echo "=== USB 设备 ==="
lsusb
echo ""
echo "=== PCI/PCIe ==="
lspci 2>/dev/null | head -20
echo ""
echo "=== dmesg 设备探测 ==="
dmesg -T | grep -iE "rk3588|rockchip|gpio|i2c|spi|uart|mipi" | tail -30
echo ""
echo "=== 设备树 ==="
ls /sys/firmware/devicetree/base/ 2>/dev/null | head -30
echo ""
echo "=== overlay ==="
ls /sys/kernel/config/device-tree/overlays/ 2>/dev/null
cat /boot/config-* 2>/dev/null | grep -i "CONFIG_PINCTRL\|CONFIG_GPIO\|CONFIG_SERIAL" | head -20
EOF
```

### 内核模块操作

```bash
# 加载模块
sudo modprobe 模块名

# 卸载模块
sudo modprobe -r 模块名

# 查看模块信息
modinfo 模块名

# 查看模块参数
systool -v -m 模块名 2>/dev/null

# 设置模块开机自动加载
echo "模块名" | sudo tee /etc/modules-load.d/自定义.conf
```

---

## 6. 进程 / 性能

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== CPU 使用 TOP15 ==="
top -bn1 -o %CPU | head -20
echo ""
echo "=== 内存使用 TOP15 ==="
top -bn1 -o %MEM | head -20
echo ""
echo "=== 僵尸进程 ==="
ps aux | awk '$8 ~ /Z/ {print}'
echo ""
echo "=== CPU 各核心使用率 ==="
mpstat -P ALL 1 1 2>/dev/null || cat /proc/stat | grep ^cpu
echo ""
echo "=== 内存详情 ==="
cat /proc/meminfo | head -10
echo ""
echo "=== IO 等待 ==="
iostat -x 1 2 2>/dev/null | tail -20 || vmstat 1 3
echo ""
echo "=== 打开的文件数 ==="
lsof 2>/dev/null | wc -l
echo "  用户限制: $(ulimit -n)"
echo ""
echo "=== 网络连接数 ==="
ss -s 2>/dev/null
EOF
```

### 常见修复

```bash
# 杀死僵尸进程的父进程
ps -eo pid,ppid,stat | awk '$3 ~ /Z/ {print $2}' | sort -u | while read ppid; do
  echo "僵尸父进程: $ppid"
  kill -9 $ppid 2>/dev/null
done

# 提高文件描述符限制
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# 设置进程优先级
sudo renice -n -10 -p 进程PID

# 限制 CPU（cgroup）
sudo cgcreate -g cpu:/限制组
echo 50000 | sudo tee /sys/fs/cgroup/cpu/限制组/cpu.cfs_quota_us
sudo cgexec -g cpu:/限制组 命令
```

---

## 7. APT 包管理

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 可更新包 ==="
apt list --upgradable 2>/dev/null | head -20
echo ""
echo "=== 损坏的包 ==="
dpkg -l | grep -E "^..H" | head -10
echo ""
echo "=== 依赖问题 ==="
sudo apt-get check 2>&1 | head -10
echo ""
echo "=== 锁定状态 ==="
sudo lsof /var/lib/dpkg/lock* 2>/dev/null || echo "无锁定"
echo ""
echo "=== 源列表 ==="
grep -r "^deb " /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
EOF
```

### 常见修复

```bash
# 修复损坏的安装
sudo dpkg --configure -a
sudo apt-get install -f

# 清理锁（谨慎，确保没有其他 apt 在运行）
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a

# 更新系统
sudo apt-get update && sudo apt-get upgrade -y

# 安装包
sudo apt-get install -y 包名

# 搜索包
apt-cache search 关键词

# 查看包信息
apt-cache show 包名

# 查看文件属于哪个包
dpkg -S /path/to/file

# 查看包安装了哪些文件
dpkg -L 包名
```

---

## 8. 日志分析

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 系统日志（最近错误）==="
journalctl -p err --no-pager --since "1 hour ago" 2>/dev/null | tail -30

echo ""
echo "=== 内核日志（最近错误）==="
dmesg -T --level=err,warn 2>/dev/null | tail -30

echo ""
echo "=== 登录日志 ==="
last -20 2>/dev/null

echo ""
echo "=== 认证失败 ==="
sudo lastb 2>/dev/null | head -20

echo ""
echo "=== OOM 杀手 ==="
dmesg -T | grep -i "out of memory\|oom\|killed process" | tail -10

echo ""
echo "=== 崩溃记录 ==="
sudo cat /var/crash/*.crash 2>/dev/null | head -50 || echo "无崩溃记录"
EOF
```

### 持续监控

```bash
# 实时跟踪系统日志
sshpass -p '{pass}' ssh {user}@{host} 'sudo journalctl -f'

# 实时跟踪内核日志
sshpass -p '{pass}' ssh {user}@{host} 'sudo dmesg -w'

# 实时跟踪特定服务
sshpass -p '{pass}' ssh {user}@{host} 'sudo journalctl -u 服务名 -f'
```

---

## 9. 开机启动 / 引导

### 诊断

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 开机耗时 ==="
systemd-analyze 2>/dev/null
echo ""
echo "=== 最慢的 10 个服务 ==="
systemd-analyze blame 2>/dev/null | head -11
echo ""
echo "=== 启动目标 ==="
systemctl get-default
echo ""
echo "=== 开机自启服务 ==="
systemctl list-unit-files --state=enabled --no-pager 2>/dev/null
echo ""
echo "=== 开机失败的服务 ==="
systemctl --failed
echo ""
echo "=== Bootloader ==="
cat /boot/extlinux/extlinux.conf 2>/dev/null | head -20
echo ""
echo "=== 内核命令行 ==="
cat /proc/cmdline
EOF
```

### 常见修复

```bash
# 设置图形/文本启动
sudo systemctl set-default multi-user.target   # 文本
sudo systemctl set-default graphical.target     # 图形

# 禁用不必要的服务
sudo systemctl disable 服务名
sudo systemctl mask 服务名  # 彻底禁用

# 添加自定义启动脚本
sudo tee /etc/systemd/system/custom.service > /dev/null << 'SVC'
[Unit]
Description=Custom Service
After=network.target

[Service]
Type=simple
User={user}
ExecStart=/home/{user}/脚本.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVC
sudo systemctl daemon-reload
sudo systemctl enable --now custom
```

---

## 10. 一键系统健康检查

不指定问题时的通用检查脚本：

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
PASS=0; WARN=0; FAIL=0
report() { if [ "$1" = "ok" ]; then PASS=$((PASS+1)); echo "  [OK]   $2"; elif [ "$1" = "warn" ]; then WARN=$((WARN+1)); echo "  [WARN] $2"; else FAIL=$((FAIL+1)); echo "  [FAIL] $2"; fi; }

echo "╔══════════════════════════════════════╗"
echo "║   RK3588 系统健康检查               ║"
echo "╚══════════════════════════════════════╝"
echo ""

echo "[网络]"
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && report ok "外网连通" || report fail "外网不通"
ip addr show | grep -q "192.168" && report ok "局域网 IP 正常" || report warn "未检测到局域网 IP"

echo ""
echo "[存储]"
USE=$(df / | awk 'NR==2{gsub("%","",$5); print $5}')
[ "$USE" -lt 90 ] && report ok "根分区使用 ${USE}%" || report fail "根分区已满 ${USE}%"
[ -w / ] && report ok "根分区可写" || report fail "根分区只读"

echo ""
echo "[内存]"
MEM_AVAIL=$(free | awk '/Mem:/{printf "%.0f", $7/$2*100}')
[ "$MEM_AVAIL" -gt 15 ] && report ok "可用内存 ${MEM_AVAIL}%" || report warn "可用内存仅 ${MEM_AVAIL}%"

echo ""
echo "[CPU]"
LOAD1=$(cat /proc/loadavg | awk '{print $1}')
CPUS=$(nproc)
[ $(echo "$LOAD1 < $CPUS" | bc -l 2>/dev/null || echo 1) -eq 1 ] && report ok "负载 ${LOAD1}/${CPUS} CPU" || report warn "负载过高 ${LOAD1}/${CPUS} CPU"

echo ""
echo "[温度]"
TEMP=$(awk '{printf "%.0f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 999)
[ "$TEMP" -lt 75 ] && report ok "CPU 温度 ${TEMP}°C" || [ "$TEMP" -lt 85 ] && report warn "CPU 温度偏高 ${TEMP}°C" || report fail "CPU 过热 ${TEMP}°C"

echo ""
echo "[进程]"
ZOMBIES=$(ps aux | awk '$8 ~ /Z/' | wc -l)
[ "$ZOMBIES" -eq 0 ] && report ok "无僵尸进程" || report warn "有 ${ZOMBIES} 个僵尸进程"

echo ""
echo "[SSH]"
systemctl is-active sshd >/dev/null 2>&1 && report ok "SSH 服务运行" || report fail "SSH 服务未运行"

echo ""
echo "[串口]"
[ -c /dev/ttyS9 ] && report ok "ttyS9 存在" || report warn "ttyS9 不存在"
groups {user} | grep -q dialout && report ok "串口权限正常" || report warn "无 dialout 权限"

echo ""
echo "[GPIO]"
gpiodetect >/dev/null 2>&1 && report ok "libgpiod 可用" || report warn "libgpiod 不可用"
groups {user} | grep -q gpio && report ok "GPIO 权限正常" || report warn "无 gpio 组权限"

echo ""
echo "═══════════════════════════════════════"
echo "  通过: ${PASS}  警告: ${WARN}  失败: ${FAIL}"
echo "═══════════════════════════════════════"
EOF
```

---

## 修复验证

修复后必须验证：

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
# 替换为验证修复效果的具体命令
echo "验证修复结果..."
EOF
```

向用户汇报格式：

```
[问题] {用户描述的问题}
[诊断] {根因分析}
[修复] {执行了什么操作}
[验证] {修复后状态}
[建议] {后续注意事项}
```
