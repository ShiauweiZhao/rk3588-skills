# Jetson Nano ROS 节点编译部署指南

## 环境信息

| 项目 | 值 |
|---|---|
| 板子 | Jetson Nano |
| IP | 192.168.1.100 |
| 用户名 | jetson |
| 密码 | jetson |
| ROS 包名 | obstacle_detector |
| launch 文件 | detect.launch |
| workspace | ~/catkin_ws |

---

## 第一步：SSH 连接到板子并查看环境

```bash
ssh jetson@192.168.1.100
```

连接后先确认 ROS 环境和 workspace 结构：

```bash
# 检查 ROS 版本
source /opt/ros/melodic/setup.bash  # Jetson Nano 通常跑 Melodic
rosversion -d

# 查看 workspace 目录结构
ls -la ~/catkin_ws/src/
ls -la ~/catkin_ws/src/obstacle_detector/
```

---

## 第二步：查看包的源码和编译错误

```bash
# 查看包结构
find ~/catkin_ws/src/obstacle_detector -type f

# 查看 package.xml 和 CMakeLists.txt
cat ~/catkin_ws/src/obstacle_detector/package.xml
cat ~/catkin_ws/src/obstacle_detector/CMakeLists.txt

# 查看 launch 文件内容
cat ~/catkin_ws/src/obstacle_detector/launch/detect.launch
```

---

## 第三步：尝试编译并捕获错误

```bash
cd ~/catkin_ws
source /opt/ros/melodic/setup.bash
catkin_make 2>&1 | tee build_log.txt
```

如果 catkin_make 报错，查看错误信息：

```bash
# 只看错误行
cat build_log.txt | grep -i "error"
```

---

## 第四步：根据常见错误类型进行修复

### 常见错误 1 - 缺少依赖包

```bash
# 查看缺少哪些依赖
source /opt/ros/melodic/setup.bash
rosdep install --from-paths src --ignore-src -r -y
```

如果 rosdep 没有初始化：

```bash
sudo rosdep init
rosdep update
```

### 常见错误 2 - CMakeLists.txt 配置问题

检查 CMakeLists.txt 中的关键配置项：

```cmake
cmake_minimum_required(VERSION 3.0.2)
project(obstacle_detector)

# 确保依赖声明正确
find_package(catkin REQUIRED COMPONENTS
  roscpp
  rospy
  std_msgs
  sensor_msgs
  # 其他需要的包...
)

# 确保 catkin_package 声明正确
catkin_package(
  INCLUDE_DIRS include
  LIBRARIES obstacle_detector
  CATKIN_DEPENDS roscpp rospy std_msgs sensor_msgs
)

# 确保可执行文件正确链接
add_executable(obstacle_detector_node src/obstacle_detector_node.cpp)
target_link_libraries(obstacle_detector_node ${catkin_LIBRARIES})
```

### 常见错误 3 - 编译缓存问题

```bash
# 清理编译产物重新编译
cd ~/catkin_ws
rm -rf build/ devel/
catkin_make
```

---

## 第五步：编译成功后 source 环境并启动

```bash
cd ~/catkin_ws
source devel/setup.bash

# 先检查 launch 文件是否存在
rospack find obstacle_detector
cat $(rospack find obstacle_detector)/launch/detect.launch

# 启动 roscore（如果还没有运行）
roscore &

# 等 roscore 启动完成
sleep 3

# 启动节点
roslaunch obstacle_detector detect.launch
```

---

## 第六步：验证节点是否正常运行

```bash
# 在另一个 SSH 终端中执行
source /opt/ros/melodic/setup.bash
source ~/catkin_ws/devel/setup.bash

# 检查节点是否在运行
rosnode list

# 检查话题是否发布
rostopic list

# 查看节点信息
rosnode info /obstacle_detector_node
```

---

## 完整的一键部署脚本

如果手动操作太繁琐，可以用以下脚本一次性完成（在本地 Mac 上执行）：

```bash
#!/bin/bash

# 配置
REMOTE_HOST="192.168.1.100"
REMOTE_USER="jetson"
REMOTE_PASS="jetson"
WORKSPACE="catkin_ws"
PACKAGE="obstacle_detector"
LAUNCH="detect.launch"

echo "=== [1/6] 连接到板子检查环境 ==="
sshpass -p "$REMOTE_PASS" ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  source /opt/ros/melodic/setup.bash 2>/dev/null || source /opt/ros/noetic/setup.bash 2>/dev/null
  echo "ROS 版本: $(rosversion -d)"
  echo "Workspace 内容:"
  ls ~/catkin_ws/src/ 2>/dev/null || echo "catkin_ws/src 不存在"
EOF

echo "=== [2/6] 安装缺失依赖 ==="
sshpass -p "$REMOTE_PASS" ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  source /opt/ros/melodic/setup.bash 2>/dev/null || source /opt/ros/noetic/setup.bash 2>/dev/null
  cd ~/catkin_ws
  rosdep install --from-paths src --ignore-src -r -y 2>/dev/null || echo "rosdep 跳过"
EOF

echo "=== [3/6] 清理并重新编译 ==="
sshpass -p "$REMOTE_PASS" ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  source /opt/ros/melodic/setup.bash 2>/dev/null || source /opt/ros/noetic/setup.bash 2>/dev/null
  cd ~/catkin_ws
  rm -rf build/ devel/
  catkin_make 2>&1
  BUILD_EXIT=$?
  if [ $BUILD_EXIT -ne 0 ]; then
    echo "编译失败！请查看上方错误信息。"
    exit 1
  fi
  echo "编译成功！"
EOF

echo "=== [4/6] 启动 roscore ==="
sshpass -p "$REMOTE_PASS" ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
  source /opt/ros/melodic/setup.bash 2>/dev/null || source /opt/ros/noetic/setup.bash 2>/dev/null
  if ! pgrep -x roscore > /dev/null; then
    roscore &
    sleep 3
    echo "roscore 已启动"
  else
    echo "roscore 已在运行"
  fi
EOF

echo "=== [5/6] 启动 launch 文件 ==="
sshpass -p "$REMOTE_PASS" ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
  source /opt/ros/melodic/setup.bash 2>/dev/null || source /opt/ros/noetic/setup.bash 2>/dev/null
  source ~/${WORKSPACE}/devel/setup.bash
  roslaunch ${PACKAGE} ${LAUNCH}
EOF

echo "=== [6/6] 节点运行结束 ==="
```

---

## 调试技巧

1. **编译错误看最后 20 行**：错误信息通常在输出的末尾，前面的 Warning 可以先忽略
2. **单独编译一个包**：`catkin_make --only-pkg-with-deps obstacle_detector` 可以加快编译速度
3. **查看详细编译输出**：`catkin_make -DCMAKE_VERBOSE_MAKEFILE=ON`
4. **检查 roslaunch 参数**：launch 文件可能引用了不存在的 topic 或参数，用 `rosrun rqt_graph rqt_graph` 可视化节点关系

## 注意事项

- Jetson Nano 性能有限，编译可能较慢，属于正常现象
- 确保板子存储空间充足：`df -h` 查看剩余空间
- 如果是交叉编译问题（ARM vs x86），需要在板子上直接编译，不要在开发机上编译后拷贝
- 编译过程中如果内存不足（OOM），尝试减少并行任务：`catkin_make -j1`（单线程编译）
