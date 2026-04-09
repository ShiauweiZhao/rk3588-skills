# Jetson Nano ROS 编译部署调试

好的，我来帮你在 Jetson Nano 上完成 `obstacle_detector` 包的完整编译、部署、运行和验证循环。

## 设备信息确认

| 参数 | 值 |
|------|-----|
| 设备 | Jetson Nano |
| IP | 192.168.1.100 |
| 用户名 | jetson |
| 密码 | jetson |
| SSH 端口 | 22（默认） |
| ROS 包名 | `obstacle_detector` |
| launch 文件 | `detect.launch` |
| 板子上 workspace | `~/catkin_ws` |

## 任务列表

- [ ] **STEP 1**: 编译 catkin_ws
- [ ] **STEP 2**: 部署到 Jetson Nano 板子
- [ ] **STEP 3**: 在板子上远程运行 launch 文件
- [ ] **STEP 4**: 拉取日志并分析
- [ ] **STEP 5**: 根据分析结果修复（如有问题）

---

### STEP 1: 编译

首先 SSH 到 Jetson Nano 上进行编译，因为这是 ARM64 平台，需要在板子上本地编译：

```bash
sshpass -p 'jetson' ssh -o StrictHostKeyChecking=no jetson@192.168.1.100 << 'EOF'
cd ~/catkin_ws
source /opt/ros/noetic/setup.bash
catkin_make 2>&1 | tail -50
EOF
```

**如果编译失败，会根据错误类型进行针对性修复：**
- `fatal error: xxx.h` → 安装缺失依赖：`sudo apt-get install ros-noetic-xxx libxxx-dev`
- `undefined reference` → 检查 CMakeLists.txt 的链接依赖配置
- `Could not find package` → 检查 package.xml 依赖声明
- 编译错误修复后，重新执行编译命令直到成功

**编译成功标志：**
```
[100%] Built target obstacle_detector
```

编译完成后会向你汇报结果，并询问是否继续部署。

---

### STEP 2: 部署到板子

由于我们直接在板子上编译，这步主要确认编译产物（devel 和 build 目录）是否正常生成。如果是从开发机交叉编译的场景，则使用以下命令部署：

```bash
sshpass -p 'jetson' rsync -avz -e "ssh -p 22" --delete \
  --exclude='build' --exclude='.git' \
  /workspace/devel/ jetson@192.168.1.100:~/catkin_ws/devel/ 2>&1 | tail -10

sshpass -p 'jetson' rsync -avz -e "ssh -p 22" \
  /workspace/src/obstacle_detector/ jetson@192.168.1.100:~/catkin_ws/src/obstacle_detector/ 2>&1 | tail -10
```

**部署失败处理：**
- SSH 不通 → `ping 192.168.1.100` 检查网络连通性
- 设备磁盘满 → `sshpass -p 'jetson' ssh jetson@192.168.1.100 'df -h /'`

部署完成后会汇报结果，并询问是否在板子上启动节点。

---

### STEP 3: 远程运行

这是最关键的一步——在板子上实际启动 launch 文件，观察运行状态：

```bash
sshpass -p 'jetson' ssh -o StrictHostKeyChecking=no jetson@192.168.1.100 << 'EOF'
pkill -f obstacle_detector 2>/dev/null; sleep 1
source /home/jetson/catkin_ws/devel/setup.bash

# 先确保 roscore 已启动
pgrep -f roscore > /dev/null || (roscore &>/dev/null & sleep 3)

timeout 30 roslaunch obstacle_detector detect.launch 2>&1 | tee /tmp/ros_node.log &
LAUNCH_PID=$!
sleep 5
echo "===== LOG OUTPUT (5s) ====="
cat /tmp/ros_node.log
sleep 10
echo "===== MORE LOG (15s) ====="
tail -80 /tmp/ros_node.log
kill $LAUNCH_PID 2>/dev/null; wait $LAUNCH_PID 2>/dev/null
echo "===== DONE ====="
EOF
```

运行完成后直接进入 STEP 4 分析，无需额外确认。

---

### STEP 4: 日志分析

从板子拉取完整日志进行系统分析：

```bash
sshpass -p 'jetson' ssh jetson@192.168.1.100 'cat /tmp/ros_node.log'
```

**5 个维度检查：**

| 维度 | 检查内容 |
|------|---------|
| 启动检查 | 节点是否初始化成功？参数是否正常加载？ |
| 设备/驱动 | 串口、USB 设备是否正常打开？权限是否足够？ |
| 数据流 | topic 是否有数据发布？频率是否正常？ |
| 错误/异常 | 是否有 Exception、Error、Fatal、Failed？ |
| 资源 | 内存、CPU 使用是否正常？ |

**ROS 诊断命令：**

```bash
sshpass -p 'jetson' ssh jetson@192.168.1.100 << 'EOF'
source /home/jetson/catkin_ws/devel/setup.bash
echo "=== 节点列表 ==="; rosnode list 2>/dev/null || echo "无节点运行"
echo "=== Topic 列表 ==="; rostopic list 2>/dev/null
echo "=== 关键 topic 频率 ==="; timeout 5 rostopic hz /obstacle_detector/obstacles --window 10 2>&1 || echo "无数据"
echo "=== 关键 topic 内容 ==="; rostopic echo /obstacle_detector/obstacles -n 3 2>/dev/null || echo "无数据"
EOF
```

**设备诊断（按需执行）：**

```bash
sshpass -p 'jetson' ssh jetson@192.168.1.100 << 'EOF'
echo "=== 串口设备 ==="; ls -la /dev/ttyS* /dev/ttyUSB* 2>/dev/null
groups jetson | grep -o dialout && echo "有 dialout 权限" || echo "无 dialout 权限"
echo "=== USB 设备 ==="; lsusb 2>/dev/null || echo "lsusb 不可用"
echo "=== 系统资源 ==="; free -h | head -2; uptime
echo "=== 磁盘 ==="; df -h / | tail -1
EOF
```

---

### STEP 5: 修复代码

只有当日志分析发现问题时才执行。根据 STEP 4 的分析结果：

- 如果是编译/依赖问题 → 修复源码或安装依赖后回到 STEP 1
- 如果是配置/权限问题 → 远程修复后回到 STEP 3
- 如果运行正常 → 输出最终报告

---

## 循环状态报告模板

每轮循环结束时，会使用以下格式汇报：

```
--- 循环 #1 ---

[编译] ✅ 通过 / ❌ 失败: {错误摘要}
[部署] ✅ 完成 / ❌ 失败: {错误摘要}
[运行] ✅ 启动 / ❌ 崩溃: {错误摘要}
[日志] 关键发现:
  - {发现1}
  - {发现2}
[分析] {问题根因判断}
[动作] {下一步: 修复XXX / 继续观察 / 已解决问题}
```

---

现在开始执行 STEP 1，SSH 到 Jetson Nano 进行 catkin_make 编译。是否确认开始？
