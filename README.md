<div align="center">
  <img width="250" height="250" alt="image" src="https://github.com/user-attachments/assets/e77cd3aa-2df5-48d4-8e23-a952c47276be" />

  # Fire Suppression & Autonomous Quadruped Robot

  **Team R.O.I** · Kwangwoon University<br>
  Seonwoo Ji · Jiseong Kim · Seongwoo Lim · Jaewon Cha · Prof. Yonghoon Choi

</div>

---

## Overview

In real fire scenes, every second before rescue teams arrive matters, and the effectiveness of the initial response largely determines the scale of the damage. This project develops a **quadruped firefighting robot that stays on standby inside a building, autonomously approaches the scene when a fire breaks out, and performs initial suppression by launching a throwable extinguisher.**

Conventional navigation only works in pre-mapped environments. To overcome this, we use a **Vision-Language Model (VLM) as the navigation decision module**, so the robot can recognize a fire's light source and move toward its origin on its own. The key idea is that semantic reasoning lets the robot reach the source even in an unknown environment.

The platform is the Unitree **Go2** quadruped, with a custom launcher mounted on top.

---

## System Architecture

<div align="center">
  <img width="2160" height="1350" alt="system_architecture" src="https://github.com/user-attachments/assets/055e2a67-4288-4d08-94af-10c76efcabf3" />


The full pipeline runs in three stages.

1. **Perception → Decision → Navigation** — The RealSense camera and Hesai LiDAR perceive the environment, and SLAM builds the map. The VLM recognizes the fire's light source and infers the next heading, after which Nav2 generates an autonomous path via `cmd_vel`.
2. **ROS2 command relay** — Once the robot reaches the source, the Go2 publishes a command on the `/fire_command` topic, and the `FireCommandSubscriber` node subscribes to it and runs the firing sequence. A PWM thread outputs the stopper-control signal over GPIO.
3. **Hardware actuation** — Power from the battery passes through the BTS7960 driver to drive the motors, ultimately launching the throwable extinguisher to suppress the fire.

---

## Robot Hardware

<div align="center">
  <img width="280" height="400" alt="robot_hardware" src="https://github.com/user-attachments/assets/7332857d-b679-4eca-a46d-15f1e04cc2f7" /><div align="center">
  

The launcher is designed to store and release a throwable extinguisher. By combining a **gravity-drop** mechanism with a **mechanical push-out**, it achieves stable, reliable deployment with a simple structure. The compact design is built with Go2 mounting in mind.

| Component | Spec |
|-----------|------|
| Platform | Unitree Go2 (quadruped) |
| Camera | Intel RealSense D435i |
| LiDAR | Hesai XT-16 |
| Motor driver | BTS7960 (R_EN / L_EN) |
| Power | 11.1V LiPo × 2 |
| Payload | Throwable extinguisher |

---

## Fire Search — VLFM (Vision-Language Frontier Map)

<div align="center">
  <img src="assets/vlfm_input.png" width="100%" alt="VLFM Input Panels"/>
  <br>
  <sub>Left: brightest frame seen while moving · Center: current camera view · Right: current map state</sub>
</div>

The VLM combines three inputs to decide the next heading. The map overlays the **robot's current pose (blue)**, the **direction in which light was observed (yellow)**, the **traversed path (green)**, and **unexplored candidate points (letters)**, so the model can reason over the full spatial context.

#### Decision Logic

- **When fire is visible** — Compute distance and bearing, then approach toward the source.
- **When fire is not visible** — Based on accumulated observation directions and the traversed path, pick the unexplored region with the highest likelihood of fire.
- **Re-planning** — Even while driving toward a goal, re-evaluate the visual input, cancel the existing path, and reset the target.

#### Operating Modes (`vlfm_source_nav`)

| Mode | Condition | Handling |
|------|-----------|----------|
| **DIRECT** | Fire visible in the current frame | Precise approach using current camera + LiDAR |
| **PASSED** | Was visible before, not visible now | Back-compute relative coordinates from the (image+depth+scan+pose) saved at the brightest moment and re-approach |

The light source can have broken depth in simulation, so a fallback is in place: **if the depth ROI median is invalid, the LiDAR range in that bearing (±2-beam median) is used instead.** The pixel→angle conversion is always computed from the camera intrinsics (`cx`, `fx`), even without depth. To account for throw distance, the target is set **1.5 m in front of the source.**

---

## Autonomous Navigation — Nav2 Tuning

Nav2 parameters were tuned to reflect the Go2's gait characteristics and real indoor driving conditions.

- Velocity/acceleration limits tuned for gait stability and turning response
- Costmap parameters adjusted to improve obstacle-avoidance performance
- Planner settings refined to reduce wall-proximity drift and unnecessary oscillation

Together these enable stable, natural autonomous driving even in tight indoor spaces.

---

## Software Structure

```
go2/
├── run_vlm_stack.sh              # one-shot launcher for the full stack
├── vlm/
│   └── vlfm_source_nav_v20.py    # VLFM fire-search main (VLM inference + Nav2)
└── src/
    ├── my_go2_controller/        # Go2 control · safety · teleop
    │   ├── safety_gate.py        #   per-direction distance-based emergency stop
    │   ├── gap_finder.py         #   LiDAR-based gap (passage) finder
    │   ├── teleop_keyboard.py    #   manual keyboard control
    │   └── launch/               #   sensor / Nav2 / safety stack launch
    ├── my_go2_nav_bringup/       # SLAM · Nav2 · motion bridge
    │   ├── scripts/
    │   │   └── cmd_vel_to_sport.py  # cmd_vel → Unitree Sport API bridge
    │   ├── config/slam_toolbox.yaml
    │   └── launch/go2_mapping.launch.py
    ├── my_go2_odom_relay/        # /utlidar/robot_odom → /odom + TF broadcast
    ├── vlfm_nav/                 # VLFM search node (ros2 run vlfm_nav vlfm_source_nav)
    ├── HesaiLidar_ROS_2.0/       # (external) Hesai LiDAR driver
    ├── realsense-ros/            # (external) RealSense driver
    └── unitree_ros2/             # (external) Unitree ROS2 interface
```

#### Key Nodes

- **`cmd_vel_to_sport`** — Converts the `/cmd_vel` from Nav2 into Unitree Sport API requests (`/api/sport/request`). Default velocity limits are `max_vx=0.42`, `max_vy=0.3`, `max_vyaw=1.5`.
- **`safety_gate`** — Monitors per-direction obstacle distances (front 0.50 m / back 0.70 m / left·right 0.40 m) and blocks motion commands when a collision risk is detected.
- **`odom_relay`** — Relays the Go2's internal odometry to `/odom` and broadcasts the `odom → base_link` TF.

---

## Tech Stack

| Area | Technology |
|------|------------|
| Middleware | ROS2 Foxy, Cyclone DDS |
| Navigation | Nav2, SLAM Toolbox |
| Perception | Intel RealSense, Hesai LiDAR |
| Decision (VLM) | VLFM powered by the Anthropic Claude API |
| Robot control | Unitree Sport API |
| Deployment | NVIDIA Jetson (offboard VLM inference) |

---

## How to Run

Bring up the full sensor + navigation stack in one shot.

```bash
# 1) Launch the stack (Hesai LiDAR + RealSense + SLAM/odom + Nav2 + cmd_vel bridge)
./run_vlm_stack.sh
```

The launch order is:

1. **Hesai LiDAR driver** → `/lidar_points`
2. **RealSense camera** → `/camera/color/*`, `/camera/depth/*`
3. **Sensor processing + odom + SLAM** (`my_go2_nav_bringup go2_mapping`)
4. **Nav2** → `/navigate_to_pose` action server
5. **cmd_vel → Sport API bridge** (`cmd_vel_to_sport.py`)

After the stack is up, **run the VLM itself in a separate terminal.**

```bash
# 2) Run the VLM fire-search node
export ANTHROPIC_API_KEY="<your-api-key>"
ros2 run vlfm_nav vlfm_source_nav --execute --save-debug
```

> To shut down, press `Ctrl-C` in the terminal running `run_vlm_stack.sh`; all background processes are cleaned up at once. Logs are saved under `run_logs/`.

---

<div align="center">
  <sub>© Team R.O.I, Kwangwoon University</sub>
</div>
# go2-화재 진압 및 자율 사족 로봇_2026_캡스톤
