#!/bin/bash
# RK3588 一键系统健康检查
# 用法: 在 SSH 会话中直接执行，或通过 sshpass 远程调用

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
groups ${USER} | grep -q dialout && report ok "dialout 权限" || report warn "无 dialout 权限"

echo "[GPIO]"
gpiodetect >/dev/null 2>&1 && report ok "libgpiod 可用" || report warn "libgpiod 不可用"
groups ${USER} | grep -q gpio && report ok "GPIO 权限" || report warn "无 gpio 权限"

echo "═══════════════════════════════════════"
echo "  通过: ${PASS}  警告: ${WARN}  失败: ${FAIL}"
echo "═══════════════════════════════════════"
