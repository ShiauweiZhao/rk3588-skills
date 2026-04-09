---
name: board-ros-debug
description: >-
  Use for compiling, deploying, and debugging ROS on embedded boards (RK3588, Jetson, Raspberry Pi,
  STM32MP, etc.). Trigger when user mentions "板子", "部署", "串口", or needs the full
  compile→deploy→run→verify cycle on embedded hardware.
  Essential for verifying code actually runs on the device, not just building. Covers: cross-compile errors,
  deployment from dev container to board, runtime crashes, missing topics, serial port permissions,
  roslaunch/roscore failures, log analysis, and device-specific issues (disk space, port conflicts).
  Use even for "compile" requests—code that builds on x86 must be verified on ARM.
compatibility: Requires ssh, rsync, sshpass. Designed for cross-compile workflow on any Linux-based embedded board.
license: MIT
metadata:
  version: "2.0.0"
  author: board-skills
---

# 嵌入式板子远程 ROS 开发调试循环

在 Dev Container 内完成 **编译 → 部署 → 运行 → 分析 → 修复** 的完整闭环。

## 为什么需要完整循环

嵌入式 ROS 开发和普通桌面开发有一个关键区别：**代码在 x86 上编译通过，不等于在 ARM64 板子上能跑起来。** 常见的坑包括：交叉编译的依赖库版本不匹配、板子上缺少设备驱动权限、串口/GPIO 设备路径不同、launch 文件参数引用了错误的话题名。

正因为如此，这个 skill 要求走完 5 步循环。如果只编译就停下来，等于只做了一半的工作——用户拿到板子上还是会发现问题，到时候又要回来改。**完整跑一遍，把问题暴露出来，比反复来回要高效得多。**

## 执行协议

使用此 skill 时，创建任务列表逐项执行，每完成一步向用户汇报并询问是否继续下一步。

### 准备阶段

**1. 获取设备连接信息**（按优先级）：
1. 读取项目根目录 `config/device.conf`
2. 读取全局配置 `~/.config/board-skills/device.conf`
3. 向用户询问 IP、用户名、密码

**2. 确认 ROS 项目参数**（从代码、launch 文件或用户输入获取）：

| 参数 | 说明 | 示例 |
|------|------|------|
| `{package}` | ROS 功能包名 | `my_robot` |
| `{launch_file}` | launch 文件路径 | `my_robot.launch` |
| `{nodes}` | 节点可执行文件名 | `my_node` |
| `{topics}` | 关键 topic（验证用） | `/sensor/data` |

**3. 创建任务列表:**

```
- [ ] STEP 1: 编译
- [ ] STEP 2: 部署到板子
- [ ] STEP 3: 板子上远程运行
- [ ] STEP 4: 拉取日志并分析
- [ ] STEP 5: 根据分析结果修复（如有问题）
```

---

### STEP 1: 编译

```bash
cd /workspace && source /opt/ros/noetic/setup.bash && catkin_make 2>&1 | tail -30
```

**编译失败处理:**
- 分析编译错误信息（缺少头文件、类型不匹配、链接错误等）
- 直接修复源码，然后重新编译
- 常见问题速查:
  - `fatal error: xxx.h` → `sudo apt-get install ros-noetic-xxx libxxx-dev`
  - `undefined reference` → 检查 CMakeLists.txt 链接依赖
  - `Could not find package` → 检查 `package.xml` 依赖声明
  - 子模块缺失 → `git submodule update --init --recursive`

**编译成功标志:**
```
[100%] Built target {node_name}
```

**完成后:** 汇报编译结果，询问用户 "编译通过。是否继续部署到板子运行？"

### STEP 2: 部署

```bash
cd /workspace && ./scripts/deploy.sh 2>&1 | tail -20
```

**没有 deploy 脚本时，使用通用部署:**
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

**完成后:** 汇报部署结果，询问用户 "部署完成。是否在板子上启动节点？"

### STEP 3: 远程运行

**这是最关键的一步** — 必须实际在板子上跑起来看结果，SSH 到板子执行：

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

**完成后:** 向用户展示板子上的实际运行日志，然后直接进入 STEP 4 分析（不需要问用户）。

### STEP 4: 日志分析

从板子拉取日志，分析是否正常运行。这是验证代码是否真正在板子上工作的关键步骤。

```bash
sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'
```

**检查 5 个维度:**

| 维度 | 检查内容 | 常见问题 |
|------|---------|---------|
| 启动检查 | 节点是否初始化成功？参数是否加载？ | 参数文件找不到、命名空间错误 |
| 设备/驱动 | 串口、GPIO、USB 设备是否打开？ | 权限不足、设备路径不存在 |
| 数据流 | topic 是否有数据？频率是否正常？ | 传感器未连接、驱动未加载 |
| 错误/异常 | Exception、Error、Fatal、Failed？ | 段错误、超时、连接拒绝 |
| 资源 | 内存泄漏？CPU 过载？ | 长时间运行后 OOM |

**ROS 诊断命令:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
echo "=== 节点 ==="; rosnode list 2>/dev/null || echo "无节点运行"
echo "=== Topics ==="; rostopic list 2>/dev/null
echo "=== 关键 topic 频率 ==="; timeout 5 rostopic hz {topic} --window 10 2>&1 || echo "无数据"
echo "=== 关键 topic 内容 ==="; rostopic echo {topic} -n 3 2>/dev/null || echo "无数据"
EOF
```

**设备诊断（根据问题选择性执行）:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 串口 ==="; ls -la /dev/ttyS* /dev/ttyUSB* 2>/dev/null
groups {user} | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo "=== GPIO ==="; ls -la /dev/gpiochip* 2>/dev/null; gpiodetect 2>/dev/null || echo "libgpiod 不可用"
echo "=== 系统 ==="; free -h | head -2; uptime
EOF
```

**完成后:** 使用下方的报告模板向用户正式汇报分析结果。

### STEP 5: 修复代码

只有当日志分析发现问题时才执行。修复后**回到 STEP 1** 重新走完整循环。

---

## 快速命令参考

| 场景 | 命令 |
|------|------|
| 拉取日志 | `sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'` |
| 交互运行 | `sshpass -p '{pass}' ssh -t -p {port} {user}@{host}` + source + roslaunch |
| 停止节点 | `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f {nodes}'` |
| ROS bag 录制 | `sshpass -p '{pass}' ssh {user}@{host}` + `rosbag record -a` |
| 停止 ROS bag | `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f rosbag'` |
| 检查节点 | `sshpass -p '{pass}' ssh {user}@{host}` + `source setup.bash && rosnode list` |
| 查看 topic | `sshpass -p '{pass}' ssh {user}@{host}` + `source setup.bash && rostopic echo {topic} -n 1` |

---

## 循环状态报告模板

每轮循环结束时使用此模板向用户汇报：

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
