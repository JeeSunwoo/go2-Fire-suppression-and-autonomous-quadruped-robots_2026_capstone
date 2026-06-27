#!/usr/bin/env bash
# =============================================================================
# run_vlm_stack.sh
#   VLM(vlfm_nav) 실행에 필요한 스택을 한 번에 기동 (mapping 모드)
#   포함: Hesai LiDAR + RealSense + go2_mapping(센서처리/odom/SLAM/cmd_vel 브릿지) + nav2 + VLM(vlfm_nav)
#
#   실행: ./run_vlm_stack.sh
#   종료: 이 창에서 Ctrl-C  → 모든 백그라운드 프로세스 일괄 정리
#   로그: $WS/run_logs/<이름>.log
# =============================================================================
set -u

# ---- 경로/환경 설정 (젯슨 기준) ------------------------------------------------
# WS 는 이 스크립트 위치 기준으로 자동 인식 (capstone 워크스페이스 루트)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${SCRIPT_DIR}"

export CYCLONEDDS_URI="file:///home/unitree/cyclonedds_ws/cyclonedds_eth1.xml"

# Anthropic API 키 (VLM 용). ※ 평문 저장이므로 외부 공유/깃 커밋 금지
export ANTHROPIC_API_KEY=""

NAV2_PARAMS="${WS}/nav2/nav2_params_go2.yaml"
MAP_YAML="${WS}/maps/demo.yaml.yaml"
LOG_DIR="${WS}/run_logs"
mkdir -p "${LOG_DIR}"

# ---- ROS 환경 소싱 ------------------------------------------------------------
source /opt/ros/foxy/setup.bash
source "${WS}/install/setup.bash"

# ---- 백그라운드 프로세스 추적 + 정리 ------------------------------------------
PIDS=()
CLEANED=0
cleanup() {
  [ "${CLEANED}" = "1" ] && return
  CLEANED=1
  echo
  echo "[stack] 종료 중... 모든 프로세스 정리"
  if [ ${#PIDS[@]} -gt 0 ]; then
    # 먼저 SIGINT 으로 ros2 launch 가 자식 노드를 정상 종료하도록
    for pid in "${PIDS[@]}"; do kill -INT "${pid}" 2>/dev/null; done
    sleep 3
    # 남은 것은 강제 종료
    for pid in "${PIDS[@]}"; do kill -9 "${pid}" 2>/dev/null; done
  fi
  wait 2>/dev/null
  echo "[stack] 완료"
}
trap cleanup INT TERM EXIT

# launch <이름> <기동후_대기초> <명령...>
launch() {
  local name="$1"; shift
  local wait_s="$1"; shift
  echo "[stack] ${name} 기동..."
  "$@" > "${LOG_DIR}/${name}.log" 2>&1 &
  PIDS+=("$!")
  sleep "${wait_s}"
}

# ---- 순차 기동 ----------------------------------------------------------------
# 1) Hesai LiDAR 드라이버  → /lidar_points
launch hesai 5 \
  ros2 launch hesai_ros_driver norviz_start.py

# 2) RealSense 카메라      → /camera/color/*, /camera/depth/*
launch realsense 5 \
  ros2 launch realsense2_camera rs_launch.py

# 3) 센서처리 + odom + SLAM (cmd_vel 브릿지는 끔 → 아래 5)에서 직접 실행)
launch go2_mapping 8 \
  ros2 launch my_go2_nav_bringup go2_mapping.launch.py cmd_bridge:=true

# 4) nav2  → /navigate_to_pose (VLM 이 호출하는 액션)
launch nav2 3 \
  ros2 launch nav2_bringup bringup_launch.py \
    use_sim_time:=false \
    params_file:="${NAV2_PARAMS}" \
    autostart:=true \
    map:="${MAP_YAML}"

# 5) cmd_vel → /api/sport/request 브릿지 (직접 실행; go2_mapping 내장은 끔)
#    src본 기본 파라미터: max_vx=0.42, max_vy=0.3, max_vyaw=1.5
launch cmd_vel_bridge 3 \
  python3 "${WS}/src/my_go2_nav_bringup/scripts/cmd_vel_to_sport.py"

# 6) VLM 본체 (vlfm_nav 패키지)  → /navigate_to_pose 액션 호출
#    ※ ANTHROPIC_API_KEY 환경변수 필요 (위 line 22). --execute = 실제 Nav2 goal 전송
if [ -z "${ANTHROPIC_API_KEY}" ]; then
  echo "[stack] ⚠ ANTHROPIC_API_KEY 비어있음 → VLM 이 Claude 호출 불가. line 22 설정 필요."
fi
launch vlm 0 \
  ros2 run vlfm_nav vlfm_source_nav --execute --save-debug

# ---- 안내 --------------------------------------------------------------------
echo
echo "[stack] 전체 기동 완료 (VLM 포함). 로그: ${LOG_DIR}/"
echo "[stack] VLM 실시간 로그: tail -f ${LOG_DIR}/vlm.log"
echo "[stack] 종료하려면 이 창에서 Ctrl-C"
echo

# 포그라운드 유지 (Ctrl-C 대기)
wait
