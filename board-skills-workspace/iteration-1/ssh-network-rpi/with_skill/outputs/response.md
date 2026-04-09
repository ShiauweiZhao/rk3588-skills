# 树莓派 4B SSH 连接故障诊断

## 设备信息

- 板子: 树莓派 4B
- IP: 192.168.0.50
- 用户名: pi
- 密码: raspberry
- 端口: 22 (默认)

---

## 第一步: 基础连通性测试

首先确认板子是否在线,从本机执行 ping 测试:

```bash
ping -c 4 -W 2 192.168.0.50
```

**可能的结果:**

- **ping 通但 SSH 不行** -> SSH 服务问题,跳到第二步
- **ping 不通** -> 网络层问题,跳到第三步
- **目标主机不可达** -> 板子离线或 IP 变了,跳到第三步

---

## 第二步: 如果 ping 通但 SSH 连不上

尝试直接 SSH 连接,观察报错信息:

```bash
sshpass -p 'raspberry' ssh -o StrictHostKeyChecking=no -p 22 pi@192.168.0.50 'echo ok'
```

### 情况 2a: Connection refused (连接被拒绝)

说明板子在线但 SSH 服务未运行。通过网络诊断进一步排查:

```bash
sshpass -p 'raspberry' ssh -p 22 pi@192.168.0.50 << 'EOF'
echo "=== SSH 服务状态 ==="
sudo systemctl status sshd 2>/dev/null || sudo systemctl status ssh 2>/dev/null
echo "=== 监听端口 ==="
ss -tlnp | grep -E ":22|ssh"
echo "=== 防火墙 ==="
sudo iptables -L -n 2>/dev/null | head -20
sudo ufw status 2>/dev/null
echo "=== SSH 日志 ==="
sudo journalctl -u ssh -u sshd --no-pager -n 30 2>/dev/null
EOF
```

**常见原因与修复:**

1. SSH 服务未启动: `sudo systemctl start ssh && sudo systemctl enable ssh`
2. 防火墙阻止: `sudo ufw allow 22` 或 `sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT`
3. sshd 配置错误: 检查 `/etc/ssh/sshd_config` 是否被修改

### 情况 2b: Connection timed out (连接超时)

可能是防火墙阻止或 SSH 服务崩溃。需要进一步排查。

### 情况 2c: Permission denied (密码错误)

```bash
# 确认密码是否正确
sshpass -p 'raspberry' ssh -o StrictHostKeyChecking=no -p 22 pi@192.168.0.50 'id'
```

可能需要通过串口或显示器直接登录板子重置密码。

---

## 第三步: 如果 ping 不通 (网络层问题)

### 3a: 确认本机网络正常

```bash
# 检查本机网络
ping -c 2 192.168.0.1
ping -c 2 8.8.8.8
```

### 3b: 扫描局域网,看板子是否换了 IP

```bash
# 用 ARP 扫描查看局域网设备
arp -a | grep -i "b8:27:eb\|dc:a6:32\|e4:5f:01"
# 树莓派 MAC 地址前缀: b8:27:eb (旧款), dc:a6:32 (4B), e4:5f:01 (4B/5)
```

或用 nmap 扫描:

```bash
nmap -sn 192.168.0.0/24 | grep -B 2 "Raspberry\|Pi"
```

### 3c: 如果 IP 没变但 ping 不通

可能原因:

1. **板子死机/内核崩溃** -- 需要物理重启 (拔插电源)
2. **网线松动/WiFi 断连** -- 检查物理连接
3. **路由器 DHCP 重新分配了 IP** -- 检查路由器后台
4. **板子网卡异常** -- 如果有串口可以登录排查

---

## 第四步: 连通后全面信息收集

一旦恢复连接,立即收集系统状态,定位"突然不行"的根因:

```bash
sshpass -p 'raspberry' ssh -p 22 pi@192.168.0.50 << 'EOF'
echo "=== 概览 ==="
echo "内核: $(uname -r) $(uname -m)  发行版: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "运行时间: $(uptime -p)  负载: $(cat /proc/loadavg)"
echo "=== 内存 ==="; free -h
echo "=== 磁盘 ==="; df -h / /boot
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

---

## 诊断流程总结

```
开始
 |
 v
ping 192.168.0.50
 |
 +-- 不通 --> 检查本机网络 --> ARP扫描找IP --> 物理重启?
 |
 +-- 通 --> 尝试 SSH 连接
              |
              +-- refused --> 检查 sshd 服务状态/防火墙
              +-- timeout --> 检查防火墙/iptables
              +-- denied  --> 密码错误,需串口重置
              +-- 成功 --> 全面信息收集,定位根因
```

---

## 注意事项

1. 树莓派 4B 如果使用 WiFi 连接,WiFi 驱动偶尔会掉线,建议改用有线连接更稳定
2. 如果板子 SD 卡老化导致文件系统只读,也会出现 SSH 拒绝连接的情况
3. 如果板子负载过高 (OOM 等),SSH 可能响应极慢但并非完全不可达
4. 建议在板子上设置静态 IP 或 DHCP 保留,避免 IP 突然变化

---

准备好后,请告诉我第一步 ping 的结果,我会根据实际情况继续排查。
