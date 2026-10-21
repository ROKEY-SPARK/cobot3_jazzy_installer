#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/verify.sh · 설치 결과 점검 (읽기 전용 — 시스템을 바꾸지 않음)
#   사용: bash resources/verify.sh [--no-gpu] [--no-isaac]
#         --no-* = 그 항목이 없는 환경(컨테이너 이미지 등)에서 해당 점검 생략
#   종료 코드 = 0 전부 통과 / 2 하나 이상 실패
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

PASSED=0
FAILED=0
SKIP_GPU=0
SKIP_ISAAC=0

# check <설명> <명령...> · 명령 출력은 숨기고 결과만 한 줄
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASSED=$((PASSED + 1)); echo "  [PASS] ${desc}"
    else
        FAILED=$((FAILED + 1)); echo "  [FAIL] ${desc}"
    fi
}

# ROS 환경을 올린 새 셸에서 명령 실행 (현재 셸 env 오염 방지)
# ros_has_pkg <overlay-setup.bash|""> <pkg>
ros_has_pkg() {
    bash -c 'set +u; source /opt/ros/jazzy/setup.bash; [ -n "$1" ] && [ -f "$1" ] && source "$1"; ros2 pkg prefix "$2"' _ "$1" "$2"
}

# 고정 ref 와 HEAD 일치 (둘 중 하나라도 못 구하면 실패 — 빈 문자열끼리 같다고 통과시키지 않음)
git_at_ref() {
    local have want
    have="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || return 1
    want="$(git -C "$1" rev-parse "$2^{commit}" 2>/dev/null)" || return 1
    [[ -n "${have}" && "${have}" == "${want}" ]]
}
bashrc_has_block() { grep -qx "# >>> rokey $1 >>>" "${BASHRC}"; }

check_common() {
    echo "== common"
    check "Ubuntu ${UBUNTU_CODENAME}" grep -q "VERSION_CODENAME=${UBUNTU_CODENAME}" /etc/os-release
    check "ROS 2 ${ROS_DISTRO} desktop" pkg_installed "ros-${ROS_DISTRO}-desktop"
    check "rosdep initialized" test -e /etc/ros/rosdep/sources.list.d/20-default.list
    if [[ "${SKIP_GPU}" == 0 ]] && has_nvidia_gpu; then
        check "nvidia-smi works (driver loaded)" nvidia-smi
    fi
}

check_cobot3() {
    local ov="${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws/install/setup.bash"
    echo "== cobot3"
    if [[ "${SKIP_ISAAC}" == 0 ]]; then
        check "Isaac Sim ${ISAACSIM_VERSION} (${ISAACSIM_DIR}/VERSION)" grep -q "^${ISAACSIM_VERSION}" "${ISAACSIM_DIR}/VERSION"
        check "Isaac Sim python.sh" test -x "${ISAACSIM_DIR}/python.sh"
    fi
    check "package nav2_bringup" ros_has_pkg "" nav2_bringup
    check "package nav2_simple_commander" ros_has_pkg "" nav2_simple_commander
    check "package pointcloud_to_laserscan" ros_has_pkg "" pointcloud_to_laserscan
    check "package foxglove_bridge" ros_has_pkg "" foxglove_bridge
    check "package carter_navigation (Isaac ROS ws)" ros_has_pkg "${ov}" carter_navigation
    check "Isaac ROS ws pinned to ${ISAAC_ROS_WS_REF}" git_at_ref "${ISAAC_ROS_WS_DIR}" "${ISAAC_ROS_WS_REF}"
    check "cobot3_ws built" test -d "${COBOT3_WS}/install"
    check "cobot3_ws/isaacpjt" test -d "${COBOT3_WS}/isaacpjt"
    check "FastDDS profile ${FASTDDS_PROFILE}" python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "${FASTDDS_PROFILE}"
    check "bashrc cobot3 block" bashrc_has_block cobot3
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-gpu) SKIP_GPU=1 ;;
            --no-isaac) SKIP_ISAAC=1 ;;
            *) die "${EXIT_USER}" "verify: unknown option $1 (options: --no-gpu --no-isaac)" ;;
        esac
        shift
    done
    check_common
    check_cobot3
    echo "---- ${PASSED} passed, ${FAILED} failed"
    [[ ${FAILED} -eq 0 ]] || exit "${EXIT_SYSTEM}"
}

main "$@"
