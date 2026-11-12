# shellcheck shell=bash
# shellcheck disable=SC2088,SC2016  # "~/..." = 화면 문구 / bash -c '...' = 안쪽 셸이 펼칠 변수
# checks/cobot3.sh · 협동3 (Isaac Sim 5.1.0 + Nav2)
#   기준 = 협동3 설치기 resources/verify.sh 항목 + 커널 · 드라이버 고정 · Xorg 설정

: "${SKIP_ISAAC:=0}"
: "${GDM_CONF:=/etc/gdm3/custom.conf}"
: "${RELEASE_UPGRADES_CONF:=/etc/update-manager/release-upgrades}"

# 강의 2-1 절: 현재 커널을 hold 해 새 커널이 드라이버를 깨지 않게 함
running_kernel_held() { pkg_held "linux-image-$(uname -r)"; }

xorg_forced() {
    [[ -f "${GDM_CONF}" ]] || { skip_because "${GDM_CONF} 없음 (gdm 미사용)"; return; }
    grep -qE '^WaylandEnable=false' "${GDM_CONF}" || { echo "${GDM_CONF}: WaylandEnable=false 없음"; return 1; }
}

release_upgrade_prompt_never() {
    [[ -f "${RELEASE_UPGRADES_CONF}" ]] || { skip_because "${RELEASE_UPGRADES_CONF} 없음"; return; }
    grep -qx 'Prompt=never' "${RELEASE_UPGRADES_CONF}" || { grep '^Prompt=' "${RELEASE_UPGRADES_CONF}"; return 1; }
}

# 그래픽 세션이 실제로 Xorg 인지 (설정 후 재로그인 전이면 아직 wayland)
session_is_x11() {
    case "${XDG_SESSION_TYPE:-}" in
        x11) return 0 ;;
        wayland) echo "현재 세션 wayland"; return 1 ;;
        *) skip_because "그래픽 세션 밖에서 실행 (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-없음})" ;;
    esac
}

isaacsim_version_ok() {
    local f="${ISAACSIM_DIR}/VERSION"
    path_exists "${f}" || return 1
    grep -q "^${ISAACSIM_VERSION}" "${f}" || { echo "VERSION: $(head -n1 "${f}")"; return 1; }
}

# cobot3_ws · Isaac ROS ws 둘 다 중복 패키지 없음. 한쪽이 없으면 (판정 불가) 다른 쪽만 본다
cobot3_ws_unique() {
    local w out rc line bad=0 judged=0
    for w in "${COBOT3_WS}" "${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws"; do
        rc=0
        out="$(ws_unique_packages "${w}")" || rc=$?
        [[ ${rc} -eq ${RC_SKIP} ]] && continue
        judged=1
        [[ ${rc} -eq 0 ]] && continue
        bad=1
        while IFS= read -r line; do echo "${w}: ${line}"; done <<<"${out}"
    done
    [[ ${judged} == 1 ]] || { skip_because "워크스페이스 없음"; return; }
    return "${bad}"
}

check_cobot3() {
    local ov="${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws/install/setup.bash" ros="ros-${ROS_DISTRO}"
    local fix="bash install.sh cobot3 (협동3 설치기, 끝난 단계는 건너뜀)"
    section "협동3"
    if [[ "${SKIP_GPU}" == 0 ]] && has_nvidia_gpu; then
        check fail "NVIDIA 드라이버 nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open" "${fix}" \
            nvidia_driver_is "nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open"
        check fail "드라이버 hold (버전 고정)" "sudo apt-mark hold nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open" \
            pkg_held "nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open"
    fi
    if [[ "${SKIP_HOST}" == 0 ]]; then
        check warn "부팅 커널 hold" "sudo apt-mark hold linux-image-\$(uname -r)" running_kernel_held
        check fail "Xorg 강제 (WaylandEnable=false)" "${fix}" xorg_forced
        check warn "현재 세션 Xorg (설정 후 재로그인)" "로그아웃 후 다시 로그인" session_is_x11
        check warn "배포판 업그레이드 알림 끔 (Prompt=never)" "${fix}" release_upgrade_prompt_never
    fi
    if [[ "${SKIP_ISAAC}" == 0 ]]; then
        check fail "Isaac Sim ${ISAACSIM_VERSION} (${ISAACSIM_DIR}/VERSION)" "${fix} --isaac-zip <zip 경로>" \
            isaacsim_version_ok
        # isaac_ros 가 시스템 ROS 없이 붙이는 내장 Jazzy 라이브러리 (Isaac Sim 5.1.0 문서의 경로)
        check fail "Isaac Sim 내장 ROS 2 라이브러리 (ros2 bridge)" "${fix} --isaac-zip <zip 경로> (압축이 덜 풀렸을 수 있음)" \
            path_exists "${ISAACSIM_DIR}/exts/isaacsim.ros2.bridge/${ROS_DISTRO}/lib"
        check fail "Isaac Sim python.sh 실행 권한" "${fix}" bash -c '[ -x "$1" ] || { echo "실행 불가 또는 없음: $1"; exit 1; }' _ "${ISAACSIM_DIR}/python.sh"
    fi
    check fail "Nav2 · foxglove 패키지" "${fix}" pkg_installed "${ros}-navigation2" "${ros}-nav2-bringup" \
        "${ros}-pointcloud-to-laserscan" "${ros}-nav2-simple-commander" "${ros}-foxglove-bridge"
    check fail "Isaac ROS ws ${ISAAC_ROS_WS_REF} 고정" "${fix}" git_at_ref "${ISAAC_ROS_WS_DIR}" "${ISAAC_ROS_WS_REF}"
    check fail "Isaac ROS ws 빌드 (carter_navigation)" "cd ${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws && colcon build" \
        ros_has_pkg "${ov}" carter_navigation
    check fail "워크스페이스 패키지 이름 중복 없음 (cobot3_ws · Isaac ROS ws)" "표시된 중복 중 하나를 지우거나 COLCON_IGNORE" \
        cobot3_ws_unique
    check fail "cobot3_ws 빌드 · isaacpjt" "${fix}" bash -c '[ -d "$1/install" ] && [ -d "$1/isaacpjt" ] || { echo "install 또는 isaacpjt 없음: $1"; exit 1; }' _ "${COBOT3_WS}"
    check fail "FastDDS 프로필 ${FASTDDS_PROFILE}" "${fix}" xml_valid "${FASTDDS_PROFILE}"
    check fail "~/.bashrc 협동3 블록" "${fix}" bashrc_block_ok "# >>> rokey cobot3 >>>" "# <<< rokey cobot3 <<<"
}
