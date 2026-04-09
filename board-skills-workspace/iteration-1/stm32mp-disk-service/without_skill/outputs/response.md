# STM32MP157 磁盘满 + 服务挂掉排查方案

## 板子信息

| 项目 | 值 |
|------|-----|
| 板型 | STM32MP157 |
| IP | 192.168.7.200 |
| 用户名 | root |
| 密码 | 123456 |
| 问题 | my_service 服务挂了，根分区 98% 已满 |

---

## 第一步：SSH 连接并确认磁盘占用

```bash
ssh root@192.168.7.200
```

连接后先看磁盘情况：

```bash
df -h
```

找出根分区下哪些目录占用最多空间：

```bash
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20
```

---

## 第二步：定位大文件 / 大目录

根据上一步结果，逐级深入排查：

```bash
# 常见的空间杀手 —— 日志目录
du -h --max-depth=1 /var/log | sort -hr | head -10

# 临时文件
du -h --max-depth=1 /tmp | sort -hr | head -10

# 用户数据
du -h --max-depth=1 /home | sort -hr | head -10

# 如果 my_service 有自己的数据目录，也检查一下
du -h --max-depth=1 /opt 2>/dev/null | sort -hr | head -10
du -h --max-depth=1 /var/lib | sort -hr | head -10
```

找出超过 10MB 的大文件：

```bash
find / -xdev -type f -size +10M -exec ls -lh {} \; 2>/dev/null | sort -k5 -hr
```

---

## 第三步：清理空间

### 3.1 清理日志（最常见原因）

```bash
# 查看日志文件大小
ls -lh /var/log/

# 清空过大的日志文件（保留文件但清空内容）
> /var/log/syslog
> /var/log/messages
> /var/log/kern.log

# 删除旧的轮转日志
rm -f /var/log/*.gz
rm -f /var/log/*.old
rm -f /var/log/*.1

# journal 日志清理（如果使用 systemd）
journalctl --vacuum-size=10M
```

### 3.2 清理临时文件

```bash
rm -rf /tmp/*
rm -rf /var/tmp/*
```

### 3.3 清理包缓存（如果有包管理器）

```bash
# opkg（OpenWrt/STM32MP 常见）
opkg clean

# 或 apt（Debian-based STM32MP）
apt-get clean
apt-get autoremove -y
```

### 3.4 清理 core dump

```bash
find / -name "core.*" -type f -delete 2>/dev/null
find / -name "core" -type f -delete 2>/dev/null
```

---

## 第四步：检查 my_service 服务状态

```bash
# 查看 my_service 是否存在以及配置
systemctl status my_service

# 如果不是 systemd 管理，检查其他方式
ps aux | grep my_service

# 查看 my_service 的服务文件
find / -name "my_service*" -type f 2>/dev/null
find / -name "*my_service*" 2>/dev/null

# 检查 systemd 配置位置
systemctl cat my_service 2>/dev/null
```

### 查看服务日志，了解崩溃原因

```bash
# systemd 日志
journalctl -u my_service --no-pager -n 100

# 如果有独立日志文件，找到并查看
find /var/log -name "*my_service*" 2>/dev/null
cat /var/log/my_service.log 2>/dev/null | tail -100
```

---

## 第五步：分析崩溃原因

磁盘满是非常常见的进程崩溃原因。常见情况：

1. **my_service 写日志导致磁盘满，然后自己写失败崩溃**
2. **其他进程（如 syslog）把磁盘写满，my_service 无法写入必要文件而崩溃**
3. **my_service 生成了大量数据文件（数据采集场景常见）**

确认是否因为磁盘满导致：

```bash
# 查看崩溃时间和磁盘满的时间关系
journalctl -u my_service --since "1 hour ago"

# 检查 my_service 的数据输出目录
# （根据实际情况调整路径）
du -sh /var/lib/my_service/ 2>/dev/null
du -sh /opt/my_service/ 2>/dev/null
du -sh /data/ 2>/dev/null
```

---

## 第六步：清理完成后重启服务

```bash
# 确认磁盘空间已释放
df -h

# 重启 my_service
systemctl restart my_service

# 确认服务状态
systemctl status my_service

# 实时观察服务日志，确认运行正常
journalctl -u my_service -f
```

如果 systemctl 不可用：

```bash
# 直接启动
/path/to/my_service &

# 检查进程
ps aux | grep my_service
```

---

## 第七步：防止问题复发

### 7.1 配置日志轮转

创建或编辑 `/etc/logrotate.d/my_service`：

```
/var/log/my_service.log {
    daily
    rotate 3
    compress
    missingok
    notifempty
    maxsize 50M
    copytruncate
}
```

### 7.2 限制 journald 日志大小

编辑 `/etc/systemd/journald.conf`：

```ini
SystemMaxUse=50M
RuntimeMaxUse=20M
```

然后重启 journald：

```bash
systemctl restart systemd-journald
```

### 7.3 添加磁盘监控（可选）

创建一个简单的 cron 定时检查脚本：

```bash
# 写入 cron
crontab -e
```

添加：

```
# 每小时检查磁盘使用率，超过 85% 时清理旧日志
0 * * * * df -h / | awk 'NR==2 && int($5) > 85 { system("find /var/log -name \"*.gz\" -delete; find /var/log -name \"*.1\" -delete") }'
```

---

## 预期执行流程总结

```
SSH 连接
  |
  v
df -h 确认磁盘状态
  |
  v
du 定位占用大户
  |
  v
清理日志 / 临时文件 / core dump
  |
  v
df -h 确认空间已释放（目标降到 70% 以下）
  |
  v
systemctl status my_service 确认当前状态
  |
  v
journalctl -u my_service 查看崩溃日志
  |
  v
systemctl restart my_service 重启服务
  |
  v
systemctl status my_service 确认服务恢复
  |
  v
配置日志轮转防止复发
```

---

## 注意事项

- STM32MP157 的 eMMC/SD 卡存储空间通常较小（1GB-8GB），日志管理至关重要
- 清理前建议先确认哪些文件是重要的，不要盲目删除
- 如果根分区是只读文件系统（某些嵌入式配置），可能需要重新挂载为读写：`mount -o remount,rw /`
- STM32MP157 可能使用 Buildroot 或 Yocto 构建的系统，包管理器可能是 opkg 或不存在
