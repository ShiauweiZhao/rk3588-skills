---
name: rk3588-ros-debug
description: RK3588 远程开发调试循环。自动完成 容器编译 → 板子部署 → 远程运行 → 日志抓取 → 问题分析 → 代码修复 → 重新编译 的完整闭环。
metadata: {"clawdbot":{"emoji":"🔧","os":["darwin","linux"],"requires":{"bins":["ssh","rsync"]}}}
---

# RK3588 远程开发调试循环

在 VSCode Dev Container 内完成 **编译 → 部署 → 运行 → 调试 → 修复** 的完整闭环。

---

## 环境上下文

```
┌─────────────────────────────────────────────────┐
│ macOS 宿主机                                     │
│ └── VSCode Dev Container (ARM64, /workspace)    │
│       ├── 编译: catkin_make → /workspace/devel   │
│       └── 部署: rsync → firefly@192.168.8.105    │
│                                                 │
│ RK3588 板子 (192.168.8.105, firefly/firefly)    │
│   └── ~/ros_ws (部署目标, 运行 timesync_node)    │
└─────────────────────────────────────────────────┘
```

### 关键路径

| 位置 | 路径 |
|------|------|
| 容器工作区 | `/workspace` |
| 容器编译产物 | `/workspace/devel` |
| 板子部署目标 | `/home/firefly/ros_ws` |
| 板子节点日志 | `/tmp/timesync.log` |
| 设备配置 | `/workspace/config/device.conf` |

### 项目源码结构

```
/workspace/src/timesync/
├── src/
│   ├── TimeSyncNode.cpp       # 主节点 (main, 参数加载, 回调, 发布)
│   ├── PpsCapture.cpp         # GPIO 1PPS 信号捕获 (libgpiod)
│   ├── MavlinkReceiver.cpp    # 串口 MAVLink 解析
│   └── TimeSynchronizer.cpp   # 时间偏移平滑滤波
├── include/timesync/
│   ├── TimeSyncNode.hpp
│   ├── PpsCapture.hpp
│   ├── MavlinkReceiver.hpp
│   └── TimeSynchronizer.hpp
├── launch/timesync.launch     # ROS launch 配置
└── CMakeLists.txt
```

---

## 调试循环协议

遵循以下 5 步循环，每次迭代前向用户汇报状态，遇到需要用户决策时停止询问。

### STEP 1: 编译

在容器内编译项目，检查编译是否通过。

```bash
cd /workspace && source /opt/ros/noetic/setup.bash && catkin_make 2>&1 | tail -30
```

**编译失败处理:**
- 分析编译错误信息（缺少头文件、类型不匹配、链接错误等）
- 直接修复源码，然后重新编译
- 常见问题速查:
  - `fatal error: mavlink.h` → 检查 mavlink 子模块: `git submodule update --init --recursive`
  - `undefined reference` → 检查 CMakeLists.txt 的链接依赖
  - `gpiod.h not found` → 容器内执行: `sudo apt-get install libgpiod-dev`

**编译成功标志:**
```
[100%] Built target timesync_node
```

### STEP 2: 部署

将编译产物 rsync 到 RK3588 板子。

```bash
cd /workspace && ./scripts/deploy.sh 2>&1 | tail -20
```

**部署失败处理:**
- SSH 不通 → `ping 192.168.8.105`，检查网线/USB
- sshpass 缺失 → `sudo apt-get install sshpass`（容器内）
- rsync 权限问题 → 检查板子目标目录权限
- 板子磁盘满 → `ssh firefly@192.168.8.105 'df -h /'`

### STEP 3: 远程运行

SSH 到板子，停掉旧节点，启动新节点，捕获日志。

```bash
sshpass -p 'firefly' ssh -o StrictHostKeyChecking=no firefly@192.168.8.105 << 'EOF'
# 杀掉旧进程
pkill -f timesync_node 2>/dev/null; sleep 1

# source 环境
source /home/firefly/ros_ws/devel/setup.bash

# 启动节点，日志写入文件（后台运行 15 秒自动终止）
timeout 15 roslaunch timesync timesync.launch 2>&1 | tee /tmp/timesync.log &
LAUNCH_PID=$!

# 等待启动
sleep 5

# 输出当前日志
echo ""
echo "===== LOG OUTPUT ====="
cat /tmp/timesync.log

# 等待更多数据
sleep 10

# 补充新日志
echo ""
echo "===== MORE LOG ====="
tail -50 /tmp/timesync.log

# 确保进程结束
kill $LAUNCH_PID 2>/dev/null
wait $LAUNCH_PID 2>/dev/null

echo ""
echo "===== DONE ====="
EOF
```

**运行时长调整:**
- 快速检查（10 秒）: 适合验证节点是否启动、参数是否正确
- 中等（30 秒）: 适合检查 PPS 脉冲捕获、MAVLink 通信
- 长时间（120 秒）: 适合检查时间同步稳定性、IMU 数据连续性

### STEP 4: 日志分析

从板子拉取完整日志并分析。根据日志中的关键模式判断状态：

```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 'cat /tmp/timesync.log'
```

#### 日志模式识别表

| 日志模式 | 含义 | 状态 |
|---------|------|------|
| `PPS: GPIO capture started on /dev/gpiochip3 line 28` | GPIO 初始化成功 | ✅ 正常 |
| `PPS: *** FIRST PULSE CAPTURED ***` | 收到第一个 PPS 脉冲 | ✅ 正常 |
| `PPS: Pulse #   N \| RISING edge \| interval=1.0000XX sec` | PPS 信号稳定 | ✅ 正常 |
| `MAVLink: Serial port /dev/ttyS9 opened at 230400 baud` | 串口打开成功 | ✅ 正常 |
| `MAVLink TIMESYNC: tc1=XXXXXX us` | 收到 TIMESYNC 消息 | ✅ 正常 |
| `has_sync: 1` | 时间同步已建立 | ✅ 正常 |
| `IMU: Not synchronized yet, using ROS time` | PPS 未同步，用 ROS 时间 | ⚠️ 等待 |
| `PPS: Failed to open GPIO chip` | GPIO 设备打开失败 | ❌ 需修复 |
| `MAVLink: Failed to open serial port` | 串口打开失败 | ❌ 需修复 |
| `Exception: XXX` | 程序异常崩溃 | ❌ 需修复 |
| `PPS interval` 偏离 1.0 秒较多（>0.01s） | PPS 信号不稳定 | ⚠️ 检查接线 |
| `Raw offset` 持续跳变 >100us | 时间同步不稳定 | ⚠️ 检查算法 |

#### 详细诊断命令

当发现问题后，执行针对性诊断：

**GPIO 问题诊断:**
```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 << 'EOF'
echo "=== GPIO 诊断 ==="
gpiodetect
echo ""
gpioinfo gpiochip3 2>/dev/null | grep -A1 "line 28"
echo ""
echo "GPIO 设备权限:"
ls -la /dev/gpiochip3
echo ""
echo "用户组:"
groups firefly
echo ""
echo "实时监控 3 秒:"
timeout 3 sudo gpiomon --format="%s.%n %e" gpiochip3 28 2>&1 || echo "监控失败"
EOF
```

**串口问题诊断:**
```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 << 'EOF'
echo "=== 串口诊断 ==="
ls -l /dev/ttyS9 2>/dev/null || echo "ttyS9 不存在"
echo ""
echo "串口设备列表:"
ls /dev/ttyS* 2>/dev/null
echo ""
echo "串口权限:"
groups firefly | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo ""
echo "串口占用:"
fuser /dev/ttyS9 2>/dev/null || echo "串口空闲"
echo ""
echo "原始数据采样 (3 秒):"
timeout 3 sudo hexdump -C /dev/ttyS9 2>&1 | head -20 || echo "无数据"
EOF
```

**ROS Topic 检查:**
```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 << 'EOF'
source /home/firefly/ros_ws/devel/setup.bash
echo "=== ROS Topics ==="
rostopic list 2>/dev/null
echo ""
echo "=== IMU 频率 (5 秒采样) ==="
timeout 5 rostopic hz /timesync/imu/data --window 10 2>&1 || echo "无 IMU 数据"
echo ""
echo "=== 时间偏移 ==="
rostopic echo /timesync/sync_offset_us -n 3 2>/dev/null || echo "无偏移数据"
EOF
```

**系统资源检查:**
```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 << 'EOF'
echo "=== 系统状态 ==="
free -h | head -2
echo ""
uptime
echo ""
echo "timesync_node 进程:"
ps aux | grep timesync | grep -v grep || echo "未运行"
echo ""
echo "CPU 温度:"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C\n", $1/1000}' || echo "N/A"
EOF
```

### STEP 5: 修复代码

根据日志分析结果，定位问题并修改代码。

#### 问题 → 代码定位映射

| 问题类型 | 关键文件 | 修改点 |
|---------|---------|--------|
| GPIO 打开失败 | `src/PpsCapture.cpp` | chip_device 或 line_offset |
| PPS 信号未捕获 | `src/PpsCapture.cpp` | captureLoop() 事件监听 |
| 串口打开失败 | `src/MavlinkReceiver.cpp` | 串口设备路径、波特率 |
| MAVLink 解析错误 | `src/MavlinkReceiver.cpp` | 消息解析逻辑 |
| 时间偏移过大 | `src/TimeSynchronizer.cpp` | 平滑算法 alpha 参数 |
| IMU 时间戳不准 | `src/TimeSyncNode.cpp:142-150` | `getSynchronizedTimestamp()` |
| 参数配置错误 | `launch/timesync.launch` | param 值 |
| 编译链接错误 | `CMakeLists.txt` | 依赖、库路径 |

#### 修复后回到 STEP 1

修改代码后立即执行 `catkin_make` 重新编译，进入下一轮循环。

---

## 快速命令参考

### 一键诊断（不运行节点）

```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 << 'EOF'
echo "[GPIO] $(gpiodetect 2>/dev/null | grep gpiochip3 && echo 'OK' || echo 'FAIL')"
echo "[TTY]  $(ls /dev/ttyS9 2>/dev/null && echo 'OK' || echo 'FAIL')"
echo "[WS]   $(test -f ~/ros_ws/devel/setup.bash && echo 'OK' || echo 'FAIL')"
echo "[MEM]  $(free -h | awk '/Mem:/{print $3"/"$2}')"
echo "[TEMP] $(awk '{printf "%.0f°C",$1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 'N/A')"
EOF
```

### 仅拉取日志

```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 'cat /tmp/timesync.log 2>/dev/null || echo "无日志文件"'
```

### 在板子上交互运行（保持前台）

```bash
sshpass -p 'firefly' ssh -t firefly@192.168.8.105 << 'EOF'
source /home/firefly/ros_ws/devel/setup.bash
roslaunch timesync timesync.launch
EOF
```

### 停止板子上的节点

```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 'pkill -f timesync_node; echo "已停止"'
```

### 板子上查看 GPIO 实时信号

```bash
sshpass -p 'firefly' ssh firefly@192.168.8.105 \
  'timeout 5 sudo gpiomon --format="%s.%n %e" gpiochip3 28 2>&1'
```

---

## 循环状态报告模板

每轮循环结束时，用以下格式向用户汇报：

```
--- 循环 #N ---

[编译] ✅ 通过 / ❌ 失败: {错误摘要}
[部署] ✅ 完成 / ❌ 失败: {错误摘要}
[运行] ✅ 启动 / ❌ 崩溃: {错误摘要}
[日志] 关键发现:
  - {发现1}
  - {发现2}
[分析] {问题根因判断}
[动作] {下一步: 修复XXX / 继续观察 / 已解决问题}
```
