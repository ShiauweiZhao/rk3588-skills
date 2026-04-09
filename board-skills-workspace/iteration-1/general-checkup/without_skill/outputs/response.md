# RK3588 板子远程诊断方案

**设备信息：** IP `10.0.0.5`，用户 `root`

你提到板子好像有点问题但没说具体症状，我来帮你做一次全面的系统健康检查。先通过 SSH 连上板子收集系统信息，再根据结果定位问题。

## 第一步：连通性测试

先确认板子网络是否通畅：

```bash
ping -c 3 10.0.0.5
```

如果 ping 不通，需要检查：
- 板子是否上电、网线是否插好
- 你本机是否和 10.0.0.5 在同一网段（`ifconfig` 或 `ip addr` 检查本机 IP）
- 是否需要通过跳板机或 VPN 才能访问

## 第二步：全面信息收集

ping 通后，通过 SSH 执行全面系统信息采集：

```bash
sshpass -p 'root' ssh -o StrictHostKeyChecking=no root@10.0.0.5 << 'EOF'
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
echo "=== 内核模块 ==="; lsmod | head -20
EOF
```

这条命令会一次性收集以下关键信息：

| 检查项 | 关注点 |
|--------|--------|
| 内核/发行版 | 确认系统版本是否正常 |
| 运行时间/负载 | 负载均值是否异常高（>CPU核数） |
| CPU | 频率是否正常，是否降频 |
| 内存 | 是否有内存不足（可用低于 10%） |
| 磁盘 | 是否有分区满了（使用率 >90%） |
| 网络 | IP 是否正确，网卡是否 up |
| 温度 | 是否过热（>80°C 需关注） |
| 服务 | 哪些服务在运行 |
| 进程 | 有没有吃资源的异常进程 |
| 系统日志 | 近期有没有错误 |
| dmesg | 内核层面有没有报错 |

## 第三步：根据结果针对性排查

根据第二步的输出，我会判断问题所在并进一步深入。以下是常见问题对应的排查方向：

### 如果内存不足
```bash
sshpass -p 'root' ssh root@10.0.0.5 << 'EOF'
echo "=== 内存详情 ==="; cat /proc/meminfo | head -15
echo "=== 占内存最多的进程 ==="; ps aux --sort=-%mem | head -11
echo "=== OOM 记录 ==="; dmesg -T | grep -i "out of memory\|oom\|killed process" | tail -10
EOF
```

### 如果磁盘满了
```bash
sshpass -p 'root' ssh root@10.0.0.5 << 'EOF'
echo "=== 磁盘使用 ==="; df -h
echo "=== inode 使用 ==="; df -i
echo "=== 大文件 TOP20 ==="; du -ah / 2>/dev/null | sort -rh | head -20
echo "=== 日志大小 ==="; du -sh /var/log/ 2>/dev/null
EOF
```

### 如果有服务异常
```bash
sshpass -p 'root' ssh root@10.0.0.5 << 'EOF'
echo "=== 失败的服务 ==="; systemctl --failed
echo "=== 启动耗时 ==="; systemd-analyze blame 2>/dev/null | head -11
EOF
```

### 如果有内核/硬件错误
```bash
sshpass -p 'root' ssh root@10.0.0.5 << 'EOF'
echo "=== 内核错误 ==="; dmesg -T --level=err,warn | tail -30
echo "=== 平台信息 ==="; cat /sys/firmware/devicetree/base/model 2>/dev/null
echo "=== 设备树 ==="; ls /sys/firmware/devicetree/base/ 2>/dev/null | head -30
EOF
```

### 如果网络有问题
```bash
sshpass -p 'root' ssh root@10.0.0.5 << 'EOF'
echo "=== 网卡状态 ==="; ip link show
echo "=== IP 地址 ==="; ip addr show
echo "=== 路由 ==="; ip route
echo "=== DNS ==="; cat /etc/resolv.conf
echo "=== 外网连通 ==="; ping -c 2 -W 2 8.8.8.8 2>&1 | tail -3
echo "=== 监听端口 ==="; ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
EOF
```

## 第四步：问题修复与验证

根据定位到的根因，执行修复操作，然后再次收集信息确认问题已解决。

最终以如下格式汇报：

```
[问题] {用户描述的问题}
[诊断] {根因分析}
[修复] {执行了什么操作}
[验证] {修复后状态}
[建议] {后续注意事项}
```

---

**总结：** 我需要先 SSH 连上你的板子（10.0.0.5），跑一次全面的系统信息收集，看看 CPU、内存、磁盘、网络、温度、服务、日志这些指标有没有异常。你把上面的第二步命令跑一下，把输出贴给我，我就能帮你定位问题了。
