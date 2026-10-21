# 협동3 강의 alias / env (install.sh cobot3 가 관리 — 직접 고치면 다음 실행 때 덮어씀)
# 시스템 ROS 는 여기서 source 하지 않는다 — Isaac Sim 터미널에 시스템 Jazzy 가 섞이면
# 내장 Python 3.11 과 시스템 rclpy(3.12) 가 충돌한다. ROS 터미널에서는 `jazzy` 를 먼저 친다.
export ISAACSIM_DIR=__ISAAC__
alias isaac='__ISAAC__/isaac-sim.sh'
alias isaac_python='__ISAAC__/python.sh'

# 같은 이름의 기존 alias 가 있으면 함수 정의가 alias 로 펼쳐져 문법 오류 → 먼저 제거
unalias isaac_ros jazzy 2>/dev/null || true

# Isaac Sim 쪽 터미널 env (강의: isaac_ros → isaac / isaac_python 순서로 실행)
function isaac_ros {
    export ROS_DOMAIN_ID=__DOMAIN__
    export ROS_DISTRO=jazzy
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    export FASTRTPS_DEFAULT_PROFILES_FILE=__PROFILE__
    # ROS_DISTRO 를 미리 export 하면 isaac-sim.sh 가 내장 ROS 라이브러리를 붙이지 않고,
    # python.sh 는 원래 붙이지 않는다 → 시스템 ROS 를 source 하지 않은 셸에서만 직접 붙인다
    local lib="__ISAAC__/exts/isaacsim.ros2.bridge/jazzy/lib"
    if [ -z "${AMENT_PREFIX_PATH:-}" ] && [[ ":${LD_LIBRARY_PATH:-}:" != *":${lib}:"* ]]; then
        export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}${lib}"
    fi
    echo "isaac_ros: ROS_DOMAIN_ID=${ROS_DOMAIN_ID} RMW=${RMW_IMPLEMENTATION}"
}

# ROS 쪽 터미널 (Nav2 · rviz2 · colcon) = 시스템 Jazzy + Isaac ROS ws + cobot3_ws
function jazzy {
    export ROS_DOMAIN_ID=__DOMAIN__
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    export FASTRTPS_DEFAULT_PROFILES_FILE=__PROFILE__
    source /opt/ros/jazzy/setup.bash
    [ -f __ISAAC_ROS_WS__/install/setup.bash ] && source __ISAAC_ROS_WS__/install/setup.bash
    [ -f __WS__/install/setup.bash ] && source __WS__/install/setup.bash
    echo "jazzy: ROS 2 jazzy + Isaac ROS ws + cobot3_ws sourced (ROS_DOMAIN_ID=${ROS_DOMAIN_ID})"
}