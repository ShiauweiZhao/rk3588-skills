---
name: rk3588-ros-debug
description: RK3588 远程 ROS 开发调试循环。当用户要求编译部署 ROS 节点到 RK3588 板子、远程运行 ROS 程序、抓取分析 ROS 日志、调试 ROS 功能包时触发。适用于任意 ROS (catkin) 功能包。
compatibility: Requires ssh, rsync, sshpass. Designed for ARM64 Dev Container cross-compile workflow.
license: MIT
metadata:
  version: "1.1.0"
  author: rk3588-skills
---

# RK3588 远程 ROS 开发调试循环

在 Dev Container 内完成 **编译 -> 部署 -> 运行 -> 调试 -> 修复** 的完整闭环，适用于任意 ROS (catkin) 功能包。

## 设备连接

**使用此 skill 前，必须先获取设备连接信息。** 按以下优先级获取：

1. 读取项目根目录下 `config/device.conf`
2. 读取全局配置 `~/.config/rk3588-skills/device.conf`
3. 如果配置文件均不存在，**向用户询问** IP、用户名、密码

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

## ROS 项目参数

每次调试会话前，**还需确认**以下信息（从项目代码、launch 文件或用户输入中获取）：

| 参数 | 说明 | 示例 |
|------|------|------|
| `{package}` | ROS 功能包名 | `my_robot` |
| `{launch_file}` | launch 文件相对路径 | `my_robot.launch` |
| `{nodes}` | 节点可执行文件名 | `my_node`、`driver_node` |
| `{topics}` | 关键 topic（用于验证） | `/sensor/data`、`/cmd_vel` |

## 调试循环协议

遵循以下 5 步循环，每次迭代前向用户汇报状态，遇到需要用户决策时停止询问。

### STEP 1: 编译

```bash
cd /workspace && source /opt/ros/noetic/setup.bash && catkin_make 2>&1 | tail -30
```

**编译失败处理:**
- 分析编译错误信息（缺少头文件、类型不匹配、链接错误等）
- 直接修复源码，然后重新编译
- 常见问题速查:
  - `fatal error: xxx.h` → 安装缺失依赖: `sudo apt-get install ros-noetic-xxx libxxx-dev`
  - `undefined reference` → 检查 CMakeLists.txt 的链接依赖
  - `Could not find package` → 检查 `package.xml` 依赖声明
  - 子模块缺失 → `git submodule update --init --recursive`

### STEP 2: 部署

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
- sshpass 缺失 → `sudo apt-get install sshpass`
- 设备磁盘满 → `sshpass -p '{pass}' ssh {user}@{host} 'df -h /'`

### STEP 3: 远程运行

```bash
sshpass -p '{pass}' ssh -o StrictHostKeyChecking=no -p {port} {user}@{host} << 'EOF'
pkill -f {nodes} 2>/dev/null; sleep 1
source /home/{user}/ros_ws/devel/setup.bash
timeout 15 roslaunch {package} {launch_file} 2>&1 | tee /tmp/ros_node.log &
LAUNCH_PID=$!
sleep 5
echo "===== LOG OUTPUT ====="
cat /tmp/ros_node.log
sleep 10
echo "===== MORE LOG ====="
tail -50 /tmp/ros_node.log
kill $LAUNCH_PID 2>/dev/null; wait $LAUNCH_PID 2>/dev/null
echo "===== DONE ====="
EOF
```

**运行时长调整:** 快速检查 10s / 中等 30s / 长时间 120s

**直接运行单个节点:**
```bash
timeout 15 rosrun {package} {node_executable} _param1:=value1 2>&1 | tee /tmp/ros_node.log
```

### STEP 4: 日志分析

```bash
sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'
```

**分析要点:** 启动检查 / 设备驱动 / 数据流 / 错误异常 / 资源泄漏

**ROS 诊断:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
echo "=== 节点 ==="; rosnode list 2>/dev/null || echo "无节点运行"
echo "=== Topics ==="; rostopic list 2>/dev/null
echo "=== 关键 topic 频率 ==="; timeout 5 rostopic hz {topic} --window 10 2>&1 || echo "无数据"
echo "=== 关键 topic 内容 ==="; rostopic echo {topic} -n 3 2>/dev/null || echo "无数据"
echo "=== 节点详情 ==="; rosnode info /{node_name} 2>/dev/null || echo "节点未运行"
EOF
```

**设备诊断:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 串口 ==="; ls -la /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
groups {user} | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo "=== GPIO ==="; ls -la /dev/gpiochip* 2>/dev/null; gpiodetect 2>/dev/null || echo "libgpiod 不可用"
echo "=== USB ==="; lsusb 2>/dev/null
echo "=== 视频 ==="; ls -la /dev/video* 2>/dev/null || echo "无视频设备"
echo "=== 网络 ==="; ip -4 addr show | grep -E "inet |^[0-9]" | head -10
EOF
```

**系统资源:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
free -h | head -2; echo ""; uptime
echo "节点进程:"; ps aux | grep -E "{nodes}" | grep -v grep || echo "未运行"
echo "CPU 温度:"; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C\n", $1/1000}' || echo "N/A"
echo "磁盘:"; df -h / | tail -1
EOF
```

### STEP 5: 修复代码

根据日志分析结果定位问题并修改代码。修复后回到 STEP 1。

## 快速命令参考

**一键诊断:** `sshpass -p '{pass}' ssh {user}@{host} << 'EOF'` + 网络/WS/内存/温度/SSH/磁盘检查

**仅拉取日志:** `sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'`

**交互运行:** `sshpass -p '{pass}' ssh -t -p {port} {user}@{host}` + source + roslaunch

**停止节点:** `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f {nodes}'`

**ROS bag 录制:** `sshpass -p '{pass}' ssh {user}@{host}` + rosbag record

**停止 ROS bag:** `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f rosbag'`

## 循环状态报告模板

```
--- 循环 #N ---
[编译] ✅ 通过 / ❌ 失败: {错误摘要}
[部署] ✅ 完成 / ❌ 失败: {错误摘要}
[运行] ✅ 启动 / ❌ 崩溃: {错误摘要}
[日志] 关键发现: {发现1}, {发现2}
[分析] {问题根因判断}
[动作] {下一步}
```
