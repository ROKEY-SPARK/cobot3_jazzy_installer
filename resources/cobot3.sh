#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/cobot3.sh · 협동3 (Isaac Sim 5.1.0 + Nav2 + Nova Carter + M0609 Standalone)
#   근거 = 협동3 강의자료 "Ubuntu 초기화 & IsaacSim 설치_버전 고정" · "협동3 패키지 생성 및 빌드" ·
#          "Nova Carter 로드 및 Map 제작" · "Foxglove" · "USD Standalone 로드" (alias/env)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

# 신규 커널 차단 = HWE 메타 + 현재 커널 hold → 나머지만 upgrade (강의 2-1 절)
cobot3_kernel_hold() {
    local k pkg
    k="$(uname -r)"
    local -a want=(linux-generic-hwe-24.04 linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04
                   "linux-image-${k}" "linux-headers-${k}" "linux-modules-${k}" "linux-modules-extra-${k}")
    local -a held=()
    for pkg in "${want[@]}"; do pkg_installed "${pkg}" && held+=("${pkg}"); done
    [[ ${#held[@]} -gt 0 ]] && as_root apt-mark hold "${held[@]}"
    apt_update_once
    as_root env DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
    echo "cobot3: kernel ${k} held ($(apt-mark showhold | tr '\n' ' '))"
}

# 배포판 업그레이드 알림 끔 (강의 2-2 절: Prompt=never)
cobot3_no_release_upgrade() {
    local f=/etc/update-manager/release-upgrades
    [[ -f "${f}" ]] || { echo "cobot3: ${f} absent — nothing to change."; return 0; }
    as_root sed -i 's/^Prompt=.*/Prompt=never/' "${f}"
    grep -x 'Prompt=never' "${f}"
}

# 그래픽 서버 = Xorg (강의 2-3 절: WaylandEnable=false 주석 해제)
cobot3_xorg() {
    local f=/etc/gdm3/custom.conf
    [[ -f "${f}" ]] || { echo "cobot3: ${f} absent (no GDM) — skipping."; return 0; }
    if grep -qE '^WaylandEnable=false' "${f}"; then echo "cobot3: Xorg already forced."; return 0; fi
    as_root sed -i 's/^#\s*WaylandEnable=false/WaylandEnable=false/' "${f}"
    grep -qE '^WaylandEnable=false' "${f}" || echo 'WaylandEnable=false' | as_root tee -a "${f}" >/dev/null
    echo "cobot3: Wayland disabled (applies after reboot/re-login)."
}

# zip 위치 탐색 = 명시 경로 → 설치 USB (/media/$USER/*) → ~/Downloads
_find_isaac_zip() {
    local explicit="$1" c
    for c in "${explicit}" /media/"$(id -un)"/*/"${ISAACSIM_ZIP_NAME}" "${HOME}/Downloads/${ISAACSIM_ZIP_NAME}"; do
        [[ -n "${c}" && -f "${c}" ]] && { echo "${c}"; return 0; }
    done
    return 1
}

_isaac_installed() {
    [[ -x "${ISAACSIM_DIR}/isaac-sim.sh" ]] && grep -q "^${ISAACSIM_VERSION}" "${ISAACSIM_DIR}/VERSION" 2>/dev/null
}

# isaacsim [--zip PATH] [--download] · 압축 해제 → post_install.sh → VERSION 확인
cobot3_isaacsim() {
    local zip_arg="" download=0 zip
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --zip) zip_arg="$2"; shift ;;
            --download) download=1 ;;
            *) die "${EXIT_SYSTEM}" "isaacsim: unknown option $1" ;;
        esac
        shift
    done
    if _isaac_installed; then echo "cobot3: Isaac Sim $(cat "${ISAACSIM_DIR}/VERSION") already at ${ISAACSIM_DIR}"; return 0; fi
    # 여유 공간 = 압축 해제본 ~20GB + 여유. 다운로드가 필요하면 zip 9GB 를 더 요구 → 다운로드 전에 확인
    local need_gb=30 free_gb zip=""
    zip="$(_find_isaac_zip "${zip_arg}")" || zip=""
    [[ -n "${zip}" ]] || need_gb=40
    mkdir -p "$(dirname "${ISAACSIM_DIR}")"
    free_gb=$(( $(df --output=avail -k "$(dirname "${ISAACSIM_DIR}")" | tail -1) / 1024 / 1024 ))
    [[ ${free_gb} -ge ${need_gb} ]] || die "${EXIT_USER}" "isaacsim: need >= ${need_gb}GB free next to ${ISAACSIM_DIR} (have ${free_gb}GB)."
    if [[ -z "${zip}" ]]; then
        [[ "${download}" == 1 ]] || die "${EXIT_USER}" "isaacsim: ${ISAACSIM_ZIP_NAME} not found (USB /media/$(id -un)/*, ~/Downloads). Pass --isaac-zip PATH or --isaac-download."
        zip="${HOME}/Downloads/${ISAACSIM_ZIP_NAME}"
        mkdir -p "$(dirname "${zip}")"
        echo "cobot3: downloading ${ISAACSIM_ZIP_URL} (~8.7GB, resumable)"
        apt_install wget unzip
        # wget -c = 이미 다 받은 .part 도 오류 없이 통과 (curl -C - 는 416 으로 실패)
        wget -c --progress=dot:giga -O "${zip}.part" "${ISAACSIM_ZIP_URL}"
        unzip -tq "${zip}.part" >/dev/null || die "${EXIT_SYSTEM}" "isaacsim: downloaded zip is corrupt — delete ${zip}.part and retry."
        mv "${zip}.part" "${zip}"
    fi
    apt_install unzip
    mkdir -p "${ISAACSIM_DIR}"
    echo "cobot3: extracting ${zip} -> ${ISAACSIM_DIR}"
    unzip -q -o "${zip}" -d "${ISAACSIM_DIR}"
    (cd "${ISAACSIM_DIR}" && ./post_install.sh)
    _isaac_installed || die "${EXIT_SYSTEM}" "isaacsim: ${ISAACSIM_DIR}/VERSION is not ${ISAACSIM_VERSION}*"
    echo "cobot3: Isaac Sim $(cat "${ISAACSIM_DIR}/VERSION") ready — first launch compiles shaders (5~10 min)."
}

# Nav2 + Foxglove (강의: Nova Carter / Foxglove 모니터링)
cobot3_nav2() {
    apt_install "ros-${ROS_DISTRO}-navigation2" "ros-${ROS_DISTRO}-nav2-bringup" \
        "ros-${ROS_DISTRO}-pointcloud-to-laserscan" "ros-${ROS_DISTRO}-nav2-simple-commander" \
        "ros-${ROS_DISTRO}-foxglove-bridge" "ros-${ROS_DISTRO}-rmw-fastrtps-cpp"
    if command -v ufw >/dev/null && as_root ufw status 2>/dev/null | grep -q 'Status: active'; then
        as_root ufw allow 8765
    fi
}

# NVIDIA 공식 ROS 워크스페이스 (carter_navigation 등) · 강의 버전 태그로 고정
cobot3_isaac_ros_ws() {
    git_clone_pinned "${ISAAC_ROS_WS_URL}" "${ISAAC_ROS_WS_DIR}" "${ISAAC_ROS_WS_REF}" --recursive
    ros_source
    rosdep_ready
    cd "${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws"
    # topic_based_ros2_control = isaac_moveit 전용 (강의 미사용), rosdep 정의 없음 → 그 키만 건너뜀
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" -y \
        --skip-keys "topic_based_ros2_control"
    ros_source   # rosdep 가 새로 깐 패키지의 env 훅 반영
    colcon build
    [[ -d install/carter_navigation ]] || die "${EXIT_SYSTEM}" "cobot3: carter_navigation not built."
    ls "src/navigation/carter_navigation/maps/"
}

# cobot3_ws = ROS2 패키지(src/, colcon) + Isaac Sim 스크립트(isaacpjt/, python.sh 로 실행)
cobot3_workspace() {
    mkdir -p "${COBOT3_WS}/src" "${COBOT3_WS}/isaacpjt"
    ros_source
    cd "${COBOT3_WS}"
    colcon build
}

# FastDDS 프로파일 = UDPv4 전용 (Isaac Sim 내장 FastDDS ↔ 시스템 ROS 사이 SHM 불일치 회피)
#   FASTDDS_WHITELIST="192.168.0.10,127.0.0.1" 처럼 주면 그 주소로만 통신
cobot3_dds() {
    local wl="" ip
    if [[ -n "${FASTDDS_WHITELIST:-}" ]]; then
        wl="<interfaceWhiteList>"
        for ip in ${FASTDDS_WHITELIST//,/ }; do wl+="<address>${ip}</address>"; done
        wl+="</interfaceWhiteList>"
    fi
    render_template "${SCRIPT_DIR}/templates/fastdds_whitelist.xml" "${FASTDDS_PROFILE}" "WHITELIST=${wl}"
    python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1]); print("cobot3: valid XML", sys.argv[1])' "${FASTDDS_PROFILE}"
}

cobot3_bashrc() {
    local domain="${1:-$(bashrc_block_domain_id cobot3)}" rendered
    domain="${domain:-${COBOT3_DEFAULT_DOMAIN_ID}}"
    rendered="$(mktemp)"
    render_template "${SCRIPT_DIR}/templates/cobot3.bashrc" "${rendered}" \
        "ISAAC=${ISAACSIM_DIR}" "DOMAIN=${domain}" "PROFILE=${FASTDDS_PROFILE}" \
        "ISAAC_ROS_WS=${ISAAC_ROS_WS_DIR}/${ROS_DISTRO}_ws" "WS=${COBOT3_WS}"
    bashrc_block_write cobot3 "${rendered}"
    rm -f "${rendered}"
    echo "cobot3: ~/.bashrc block updated (isaac / isaac_python / isaac_ros / jazzy)."
}

case "${1:?cobot3: subcommand required (kernel-hold|no-release-upgrade|xorg|isaacsim|nav2|isaac-ros-ws|workspace|dds|bashrc)}" in
    kernel-hold)        cobot3_kernel_hold ;;
    no-release-upgrade) cobot3_no_release_upgrade ;;
    xorg)               cobot3_xorg ;;
    isaacsim)           shift; cobot3_isaacsim "$@" ;;
    nav2)               cobot3_nav2 ;;
    isaac-ros-ws)       cobot3_isaac_ros_ws ;;
    workspace)          cobot3_workspace ;;
    dds)                cobot3_dds ;;
    bashrc)             shift; cobot3_bashrc "$@" ;;
    *) die "${EXIT_SYSTEM}" "cobot3: unknown subcommand '$1'" ;;
esac
