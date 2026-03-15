---
name: rk3588-ros-debug
description: RK3588 远程 ROS 开发调试循环。当用户要求编译部署 ROS 节点到 RK3588 板子、远程运行 ROS 程序、抓取分析 ROS 日志、调试 ROS 功能包、验证板上运行结果时触发。适用于任意 ROS (catkin) 功能包。
compatibility: Requires ssh, rsync, sshpass. Designed for ARM64 Dev Container cross-compile workflow.
license: MIT
metadata:
  version: "1.2.0"
  author: rk3588-skills
---

<EXTREMELY-IMPORTANT>
这是一个强制性的完整调试循环。5 个步骤**必须全部执行**，不允许在任何步骤提前终止。
编译通过 ≠ 任务完成。只有在板上看到运行结果并完成日志分析后，才算完成一轮循环。
违反此规则等于没有执行此 skill。
</EXTREMELY-IMPORTANT>

# RK3588 远程 ROS 开发调试循环

在 Dev Container 内完成 **编译 -> 部署 -> 运行 -> 分析 -> 修复** 的完整闭环。5 个步骤是**强制性流水线**，不是可选菜单。

## 铁条法则

```
编译通过不等于任务完成。
只有完成 STEP 4（日志分析并汇报给用户）才算完成一轮循环。
不允许跳过任何步骤。
不允许在编译成功后就停止。
```

## 提前终止红线

如果你发现自己有以下想法，**停下来，继续执行下一步**：

| 你的想法 | 实际情况 |
|---------|---------|
| "编译通过了，任务完成" | 不，还需要部署、运行、验证 |
| "用户只要求编译" | 编译只是第一步，必须问用户是否继续部署运行 |
| "先看编译结果再说" | 做完一步汇报后，主动问用户是否继续下一步 |
| "编译成功了就停下来" | 至少要汇报编译结果，然后问是否继续 |
| "部署后再看看" | 必须运行、拉日志、分析，全部做完 |

## 完整执行协议

使用此 skill 时，你必须用 TodoWrite 创建任务列表，**逐项执行并标记完成**。每完成一步向用户汇报，然后**主动询问是否继续下一步**。

### 准备阶段

**1. 获取设备连接信息**（按优先级）：
1. 读取项目根目录 `config/device.conf`
2. 读取全局配置 `~/.config/rk3588-skills/device.conf`
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

### STEP 1: 编译（必须）

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

**STEP 1 完成后，必须:**
1. 向用户汇报编译结果
2. **主动询问:** "编译通过。是否继续部署到板子运行？"

### STEP 2: 部署（必须）

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

**STEP 2 完成后，必须:**
1. 向用户汇报部署结果
2. **主动询问:** "部署完成。是否在板子上启动节点？"

### STEP 3: 远程运行（必须）

这是**最关键的一步**，也是最容易跳过的。必须 SSH 到板子实际运行节点。

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

**STEP 3 完成后，必须:**
1. 向用户展示板子上的实际运行日志
2. **立即进入 STEP 4 拉取完整日志分析，不要停下来问用户**

### STEP 4: 日志分析（必须）

**这是不可跳过的验证步骤。** 必须从板子拉取日志并给出分析结论。

```bash
sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'
```

**必须检查的 5 个维度:**
1. **启动检查** — 节点是否成功初始化？参数是否正确加载？
2. **设备/驱动** — 串口、GPIO、USB 等设备打开是否成功？
3. **数据流** — topic 是否有数据发布？频率是否正常？
4. **错误/异常** — 是否有 Exception、Error、Fatal、Failed？
5. **资源** — 是否有内存泄漏、CPU 过载？

**ROS 诊断（必须执行）:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
source /home/{user}/ros_ws/devel/setup.bash
echo "=== 节点 ==="; rosnode list 2>/dev/null || echo "无节点运行"
echo "=== Topics ==="; rostopic list 2>/dev/null
echo "=== 关键 topic 频率 ==="; timeout 5 rostopic hz {topic} --window 10 2>&1 || echo "无数据"
echo "=== 关键 topic 内容 ==="; rostopic echo {topic} -n 3 2>/dev/null || echo "无数据"
EOF
```

**根据发现的问题，选择性执行设备诊断:**
```bash
sshpass -p '{pass}' ssh {user}@{host} << 'EOF'
echo "=== 串口 ==="; ls -la /dev/ttyS* /dev/ttyUSB* 2>/dev/null
groups {user} | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo "=== GPIO ==="; ls -la /dev/gpiochip* 2>/dev/null; gpiodetect 2>/dev/null || echo "libgpiod 不可用"
echo "=== 系统 ==="; free -h | head -2; uptime
EOF
```

**STEP 4 完成后，必须:**
1. 使用下方的报告模板向用户**正式汇报分析结果**
2. 明确指出：是否发现问题？下一步建议是什么？

### STEP 5: 修复代码

只有当日志分析发现问题时才执行。修复后**回到 STEP 1** 重新走完整循环。

---

## 快速命令参考

**一键诊断:** `sshpass -p '{pass}' ssh {user}@{host} << 'EOF'` + 网络/WS/内存/温度/SSH/磁盘

**仅拉取日志:** `sshpass -p '{pass}' ssh {user}@{host} 'cat /tmp/ros_node.log'`

**交互运行:** `sshpass -p '{pass}' ssh -t -p {port} {user}@{host}` + source + roslaunch

**停止节点:** `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f {nodes}'`

**ROS bag 录制:** `sshpass -p '{pass}' ssh {user}@{host}` + rosbag record

**停止 ROS bag:** `sshpass -p '{pass}' ssh {user}@{host} 'pkill -f rosbag'`

---

## 循环状态报告模板

**每轮循环结束时必须使用此模板向用户汇报，这是强制性的。**

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
