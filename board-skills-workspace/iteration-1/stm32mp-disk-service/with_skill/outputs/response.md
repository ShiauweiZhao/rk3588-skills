# STM32MP157 板子诊断与修复方案

**设备信息:** 192.168.7.200, 用户 root, 密码 123456
**问题:** my_service 服务挂了 + 根分区 98% 已满
**诊断策略:** 信息收集 -> 根因定位 -> 修复 -> 验证（四步走）

---

## 第一步：全面信息收集

用户报告了两个问题（服务挂掉 + 磁盘满），且磁盘满极可能是服务崩溃的根因。按照诊断协议，先收集系统信息，再针对磁盘和服务做深入诊断。

### 1.1 连接并收集全面系统信息

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
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
EOF
```

### 1.2 磁盘深度诊断（模块 2）

由于根分区 98% 已满，需要精确定位大文件和占用来源：

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
echo "=== 磁盘使用概览 ==="; df -h; echo ""
echo "=== inode 使用 ==="; df -i | grep -v "^tmpfs"; echo ""
echo "=== 块设备 ==="; lsblk -f
echo "=== 根分区大目录 TOP 15 ==="
du -h --max-depth=1 / 2>/dev/null | sort -rh | head -15
echo "=== /var 大目录 ==="
du -h --max-depth=1 /var 2>/dev/null | sort -rh | head -10
echo "=== /tmp 大文件 ==="
du -h --max-depth=1 /tmp 2>/dev/null | sort -rh | head -10
echo "=== /var/log 大小 ==="
du -sh /var/log 2>/dev/null
ls -lhS /var/log/ 2>/dev/null | head -15
echo "=== journal 日志大小 ==="
journalctl --disk-usage 2>/dev/null
echo "=== apt 缓存大小 ==="
du -sh /var/cache/apt/ 2>/dev/null
echo "=== 大文件 TOP 20 (>10M) ==="
find / -xdev -type f -size +10M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -20
echo "=== 已删除但未释放空间的文件 ==="
lsof 2>/dev/null | grep deleted | head -10
EOF
```

### 1.3 服务诊断（模块 4）

检查 my_service 的状态和崩溃原因：

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
echo "=== 服务状态 ==="
systemctl status my_service 2>/dev/null; echo ""
echo "=== 服务最近日志 ==="
journalctl -u my_service --no-pager -n 50 2>/dev/null; echo ""
echo "=== 服务配置 ==="
systemctl cat my_service 2>/dev/null; echo ""
echo "=== 服务是否开机自启 ==="
systemctl is-enabled my_service 2>/dev/null
echo "=== OOM 记录 ==="
dmesg -T | grep -i "out of memory\|oom\|killed process" | tail -10
echo "=== coredump ==="
coredumpctl list 2>/dev/null | tail -5
EOF
```

---

## 第二步：根因定位（预期分析）

根据信息收集结果，预期会出现以下情况：

1. **根分区被占满的原因** — 最可能的几个：
   - `/var/log/` 下的日志文件未做轮转，不断增长
   - `journald` 日志未限制大小
   - apt 缓存（`/var/cache/apt/`）过大
   - my_service 自身写入了大量数据/日志到根分区
   - `/tmp` 或 `/var/tmp` 下有残留的大文件

2. **my_service 崩溃的原因** — 最可能：
   - 磁盘空间不足导致服务无法写入必要文件（日志、PID 文件、socket）而异常退出
   - 也可能被内核 OOM Killer 杀掉（如果内存也不足）

---

## 第三步：修复操作

根据根因分析结果，按顺序执行修复。以下是按"最常见场景"准备的修复命令：

### 3.1 清理磁盘空间

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
echo ">>> Step 1: 清理 apt 缓存"
apt-get clean
apt-get autoremove -y
echo ">>> Step 2: 清理旧日志"
journalctl --vacuum-time=3d
echo ">>> Step 3: 清理系统日志文件（保留最近3天的）"
find /var/log -type f -name "*.gz" -mtime +3 -delete 2>/dev/null
find /var/log -type f -name "*.old" -delete 2>/dev/null
find /var/log -type f -name "*.[0-9]" -delete 2>/dev/null
truncate -s 0 /var/log/syslog.1 2>/dev/null
echo ">>> Step 4: 清理 tmp 文件"
find /tmp -type f -atime +7 -delete 2>/dev/null
find /var/tmp -type f -atime +7 -delete 2>/dev/null
echo ">>> Step 5: 释放已删除但未关闭的文件"
# 如果 lsof 发现有 deleted 文件，需要重启相关进程
echo ">>> 磁盘使用率检查"
df -h /
EOF
```

### 3.2 配置日志轮转（防止再次占满）

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
# 限制 journald 日志大小
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/size-limit.conf << 'CONF'
[Journal]
SystemMaxUse=50M
SystemKeepFree=100M
CONF
systemctl restart systemd-journald

# 确认 logrotate 配置存在
ls -la /etc/logrotate.d/
logrotate -d /etc/logrotate.conf 2>&1 | head -20
EOF
```

### 3.3 重启 my_service

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
echo ">>> 重启 my_service"
systemctl restart my_service
sleep 3
echo ">>> 检查服务状态"
systemctl status my_service
EOF
```

---

## 第四步：验证

### 4.1 综合验证

```bash
sshpass -p '123456' ssh -o StrictHostKeyChecking=no root@192.168.7.200 << 'EOF'
echo "=== 磁盘空间 ==="; df -h /
echo "=== 服务状态 ==="; systemctl is-active my_service 2>/dev/null
echo "=== 服务运行时间 ==="; systemctl show my_service --property=ActiveEnterTimestamp 2>/dev/null
echo "=== 最近服务日志 ==="; journalctl -u my_service --no-pager -n 10 2>/dev/null
echo "=== 内存状态 ==="; free -h
echo "=== 系统负载 ==="; cat /proc/loadavg
EOF
```

---

## 预期修复汇报

```
[问题] STM32MP157 板子上 my_service 服务挂了，根分区 98% 已满
[诊断] 根分区被日志/缓存文件占满，导致 my_service 无法写入必要文件而异常退出
[修复]
  1. 清理 apt 缓存（apt-get clean + autoremove）
  2. 清理 journald 日志（--vacuum-time=3d）
  3. 清理 /var/log 和 /tmp 下的旧文件
  4. 配置 journald 日志大小限制（SystemMaxUse=50M）
  5. 重启 my_service
[验证]
  - 根分区使用率降至 70% 以下
  - my_service 状态为 active (running)
  - 系统负载和内存正常
[建议]
  1. 配置 logrotate 对 my_service 日志做自动轮转
  2. 在 my_service 的 systemd unit 中添加日志输出限制
  3. 考虑将 my_service 的数据写入独立分区（如 /data），避免占满根分区
  4. 设置磁盘使用率告警（>85% 时通知）
```

---

## 注意事项

- 所有命令通过 `sshpass -p '123456' ssh root@192.168.7.200` 远程执行，无需交互输入密码
- `-o StrictHostKeyChecking=no` 首次连接时跳过主机密钥确认
- 实际执行时需要根据第一步信息收集的结果调整修复策略，磁盘满的原因可能和预期不同
- 如果 my_service 不是 systemd 管理的服务，需要改用 `ps` / `kill` 方式管理
- STM32MP157 的 eMMC/SD 卡存储空间通常有限（4GB-16GB），日志管理尤为重要
