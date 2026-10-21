#!/usr/bin/env bash
# tests/nav2_smoke.sh · 협동3 ROS 쪽 기능 확인 (GPU · Isaac Sim 없이)
#   tests/nav2/fake_carter.py = Isaac Sim 대역 (/clock · TF · odom · 라이다, cmd_vel 적분)
#   강의 런치 carter_navigation.launch.py 를 그대로 띄우고 NavigateToPose 가 SUCCEEDED 인지 본다
#   전제 = rokey/jazzy-cobot3 이미지 (bash docker/build.sh)
#   사용: bash tests/nav2_smoke.sh   종료 코드 0 = 성공 / 1 = 실패
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${NAV2_IMAGE:-rokey/jazzy-cobot3:latest}"

out="$(timeout 480 docker run --rm --network host -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-91}" \
    -v "${ROOT}/tests/nav2:/navtest:ro" "${IMAGE}" bash -c '
    sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq xvfb >/dev/null 2>&1
    set +u; source /opt/ros/jazzy/setup.bash; source ~/IsaacSim-ros_workspaces/jazzy_ws/install/setup.bash
    python3 /navtest/fake_carter.py > /tmp/fake.log 2>&1 &
    xvfb-run -a ros2 launch carter_navigation carter_navigation.launch.py > /tmp/nav.log 2>&1 &
    sleep 10
    timeout 330 python3 /navtest/nav_goal.py -8.0 -1.0 2>&1 | grep -E "LIFECYCLE|PATH_POSES|NAV_"' 2>&1)"
echo "${out}"
grep -q 'NAV_STATUS 4' <<<"${out}" && { echo "PASS nav2 smoke"; exit 0; }
echo "FAIL nav2 smoke"; exit 1
