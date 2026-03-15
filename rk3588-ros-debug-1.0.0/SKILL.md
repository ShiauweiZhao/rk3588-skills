---
name: rk3588-ros-debug
description: RK3588 远程开发调试循环（通用 ROS）。自动完成 容器编译 → 板子部署 → 远程运行 → 日志抓取 → 问题分析 → 代码修复 → 重新编译 的完整闭环。适用于任意 ROS 功能包。
metadata: {"clawdbot":{"emoji":"🔧","os":["darwin","linux"],"requires":{"bins":["ssh","rsync"]}}}
---

# RK3588 远程开发调试循环（通用 ROS）

在 VSCode Dev Container 内完成 **编译 → 部署 → 运行 → 调试 → 修复** 的完整闭环，适用于任意 ROS (catkin) 功能包。

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

### 连接命令模板

```bash
# 单条命令
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} '命令'

# 多条命令（heredoc）
sshpass -p '{pass}' ssh -p {port} {user}@{host} << 'EOF'
命令1
命令2
EOF

# rsync 部署
sshpass -p '{pass}' rsync -avz -e "ssh -p {port}" 源路径 {user}@{host}:目标路径
```

---

## 环境上下文

```
┌─────────────────────────────────────────────────┐
│ macOS 宿主机                                     │
│ └── VSCode Dev Container (ARM64, /workspace)    │
│       ├── 编译: catkin_make → /workspace/devel   │
│       └── 部署: rsync → {user}@{host}            │
│                                                 │
│ 目标设备 ({host}, {user}/{pass})                │
│   └── ~/ros_ws (部署目标)                        │
└─────────────────────────────────────────────────┘
```

### 关键路径

| 位置 | 路径 |
|------|------|
| 容器工作区 | `/workspace` |
| 容器编译产物 | `/workspace/devel` |
| 板子部署目标 | `/home/{user}/ros_ws` |
| 板子运行日志 | `/tmp/ros_node.log` |
| 设备配置 | `/workspace/config/device.conf` |

### ROS 项目参数

每次调试会话前，**还需确认**以下信息（从项目代码、launch 文件或用户输入中获取）：

| 参数 | 说明 | 示例 |
|------|------|------|
| `{package}` | ROS 功能包名 | `my_robot` |
| `{launch_file}` | launch 文件相对路径 | `my_robot.launch` |
| `{nodes}` | 节点可执行文件名 | `my_node`、`driver_node` |
| `{topics}` | 关键 topic（用于验证） | `/sensor/data`、`/cmd_vel` |
| `{log_file}` | 日志输出路径 | `/tmp/ros_node.log` |

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
  - `fatal error: xxx.h` → 安装缺失依赖: `sudo apt-get install ros-noetic-xxx libxxx-dev`
  - `undefined reference` → 检查 CMakeLists.txt 的链接依赖
  - `Could not find package` → 检查 `package.xml` 依赖声明、`catkin_pkg` 配置
  - 子模块缺失 → `git submodule update --init --recursive`

**编译成功标志:**
```
[100%] Built target {node_name}
```

### STEP 2: 部署

将编译产物 rsync 到目标设备。

```bash
cd /workspace && ./scripts/deploy.sh 2>&1 | tail -20
```

**如果项目没有 deploy 脚本，使用通用部署命令:**
```bash
sshpass -p '{pass}' rsync -avz -e "ssh -p {port}" --delete \
  --exclude='build' --exclude='.git' \
  /workspace/devel/ {user}@{host}:~/ros_ws/devel/ 2>&1 | tail -10

sshpass -p '{pass}' rsync -avz -e "ssh -p {port}" \
  /workspace/src/{package}/ {user}@{host}:~/ros_ws/src/{package}/ 2>&1 | tail -10
```

**部署失败处理:**
- SSH 不通 → `ping {host}`，检查网线/USB
- sshpass 缺失 → `sudo apt-get install sshpass`（容器内）
- rsync 权限问题 → 检查设备目标目录权限
- 设备磁盘满 → `sshpass -p '{pass}' ssh {user}@{host} 'df -h /'`

### STEP 3: 远程运行

SSH 到设备，停掉旧节点，启动新节点，捕获日志。

```bash
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} << 'EOF'
# 杀掉旧进程（替换 {nodes} 为实际节点名）
pkill -f {nodes} 2>/dev/null; sleep 1

# source 环境
source /home/{user}/ros_ws/devel/setup.bash

# 启动节点，日志写入文件（后台运行 15 秒自动终止）
timeout 15 roslaunch {package} {launch_file} 2>&1 | tee /tmp/ros_node.log &
LAUNCH_PID=$!

# 等待启动
sleep 5

# 输出当前日志
echo ""
echo "===== LOG OUTPUT ====="
cat /tmp/ros_node.log

# 等待更多数据
sleep 10

# 补充新日志
echo ""
echo "===== MORE LOG ====="
tail -50 /tmp/ros_node.log

# 确保进程结束
kill $LAUNCH_PID 2>/dev/null
wait $LAUNCH_PID 2>/dev/null

echo ""
echo "===== DONE ====="
EOF
```

**运行时长调整:**
- 快速检查（10 秒）: 验证节点启动、参数加载
- 中等（30 秒）: 检查传感器数据、通信稳定性
- 长时间（120 秒）: 检查长时间运行的稳定性、数据连续性

**直接运行单个节点（不使用 launch 文件）:**
```bash
timeout 15 rosrun {package} {node_executable} _param1:=value1 2>&1 | tee /tmp/ros_node.log
```

### STEP 4: 日志分析

从设备拉取完整日志并分析。

```bash
sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'
```

#### 通用日志分析要点

1. **启动检查**: 节点是否成功初始化，参数是否正确加载
2. **设备/驱动**: 串口、GPIO、USB、网络等设备是否打开成功
3. **数据流**: topic 是否有数据发布，频率是否正常
4. **错误/异常**: Exception、Error、Fatal、Failed 等关键字
5. **资源**: 内存泄漏、CPU 过载、文件描述符耗尽

#### ROS 诊断命令

**查看节点和 topic 状态:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
echo "=== 运行中的节点 ==="
rosnode list 2>/dev/null || echo "无节点运行"
echo ""
echo "=== Topic 列表 ==="
rostopic list 2>/dev/null || echo "无 topic"
echo ""
echo "=== 关键 topic 频率 ==="
timeout 5 rostopic hz {topic} --window 10 2>&1 || echo "无数据"
echo ""
echo "=== 关键 topic 内容 ==="
rostopic echo {topic} -n 3 2>/dev/null || echo "无数据"
echo ""
echo "=== 节点详情 ==="
rosnode info /{node_name} 2>/dev/null || echo "节点未运行"
EOF
```

**设备诊断（根据项目实际使用的设备选择）:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 串口设备 ==="
ls -la /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
groups {user} | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo ""

echo "=== GPIO 设备 ==="
ls -la /dev/gpiochip* 2>/dev/null
gpiodetect 2>/dev/null || echo "libgpiod 不可用"
echo ""

echo "=== USB 设备 ==="
lsusb 2>/dev/null
echo ""

echo "=== 视频设备 ==="
ls -la /dev/video* 2>/dev/null || echo "无视频设备"
echo ""

echo "=== 网络设备 ==="
ip -4 addr show | grep -E "inet |^[0-9]" | head -10
EOF
```

**系统资源检查:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 系统状态 ==="
free -h | head -2
echo ""
uptime
echo ""
echo "节点进程:"
ps aux | grep -E "{nodes}" | grep -v grep || echo "未运行"
echo ""
echo "CPU 温度:"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C\n", $1/1000}' || echo "N/A"
echo ""
echo "磁盘空间:"
df -h / | tail -1
EOF
```

### STEP 5: 修复代码

根据日志分析结果，定位问题并修改代码。

修复后回到 STEP 1，重新编译部署。

---

## 快速命令参考

### 一键诊断（不运行节点）

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "[网络] $(ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
echo "[WS]   $(test -f ~/ros_ws/devel/setup.bash && echo 'OK' || echo 'FAIL')"
echo "[MEM]  $(free -h | awk '/Mem:/{print $3"/"$2}')"
echo "[TEMP] $(awk '{printf "%.0f°C",$1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 'N/A')"
echo "[SSH]  $(systemctl is-active sshd >/dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
echo "[DISK] $(df -h / | awk 'NR==2{print $5}')"
EOF
```

### 仅拉取日志

```bash
sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log 2>/dev/null || echo "无日志文件"'
```

### 在设备上交互运行（保持前台）

```bash
sshpass -p '{pass}' ssh -t -p {port} {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
roslaunch {package} {launch_file}
EOF
```

### 停止设备上的节点

```bash
sshpass -p '{pass}' ssh {user}@{host} 'pkill -f {nodes}; echo "已停止"'
```

### ROS bag 录制

```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
mkdir -p ~/bags
rosbag record -O ~/bags/session_$(date +%Y%m%d_%H%M%S).bag {topics} __name:=rosbag_recorder &
echo "bag 录制中, PID: $!"
EOF
```

### 停止 ROS bag 录制

```bash
sshpass -p '{pass}' ssh {user}@{host} 'pkill -f rosbag; echo "录制已停止"'
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
