好的，我来帮你检查板子的状态。你提供的信息：

- **IP:** 10.0.0.5
- **用户名:** root
- **密码:** root
- **端口:** 22（默认）

你说的问题描述比较模糊，我先跑一次全面信息收集，看看板子的整体状况，再定位具体问题。

---

## 第一步：全面信息收集

```bash
sshpass -p 'root' ssh -o StrictHostKeyChecking=no -p 22 root@10.0.0.5 << 'EOF'
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

---

## 后续流程

根据全面信息收集的输出，我会按以下逻辑进行分析：

### 可能的情况和处理方式

| 发现的异常 | 下一步操作 |
|-----------|-----------|
| 磁盘使用率 > 90% | 进入**磁盘/存储**模块，清理日志和缓存 |
| 内存几乎用完 / 有 OOM 记录 | 进入**进程/性能**模块，找出内存泄漏进程 |
| CPU 负载过高 | 进入**进程/性能**模块，定位高占用进程 |
| 温度异常高（> 80°C） | 检查散热，排查是否有进程死循环 |
| 有服务启动失败 | 进入**服务管理**模块，查看失败原因并修复 |
| dmesg 有硬件错误 | 进入**内核模块/设备树**模块，排查驱动问题 |
| 网络配置异常 | 进入**网络**模块，修复网络配置 |
| 系统日志有异常 | 进入**日志分析**模块，深入排查 |

### 诊断流程

```
全面信息收集（第一步）
    |
    v
发现异常？
    |
    +-- 是 --> 进入对应专项模块深入排查
    |              |
    |              v
    |          定位根因
    |              |
    |              v
    |          执行修复操作
    |              |
    |              v
    |          验证修复结果
    |
    +-- 否 --> 报告板子状态正常，询问用户具体症状
```

### 最终汇报格式

诊断完成后，会以如下格式汇报：

```
[问题] {用户描述的问题}
[诊断] {根因分析}
[修复] {执行了什么操作}
[验证] {修复后状态}
[建议] {后续注意事项}
```

---

请稍等，我正在执行全面信息收集命令，拿到输出后立即为你分析。
