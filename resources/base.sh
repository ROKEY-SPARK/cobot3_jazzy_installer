#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/base.sh · 시스템 계층 (NVIDIA · ROS 2 · VS Code · Docker)
#   서브커맨드마다 별도 프로세스 → 한 단계 실패가 다른 단계 상태에 무영향
#   ROS2 설치 = 강의자료의 ros2-apt-source 방식 (docs.ros.org Jazzy 공식 절차)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

# 설치된 nvidia-driver-NNN 메타 패키지 이름 (없으면 빈 문자열)
_installed_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open)?$' | sort -V | tail -n1 || true
}

# nvidia [--open] [--pin <version>] [--hold-all]
#   --open     = open 커널 모듈 (협동3 강의)
#   --pin      = 그 버전을 우선 설치, 저장소에 없으면 같은 브랜치 최신으로 대체
#   --hold-all = 설치 후 nvidia 관련 패키지 전부 hold (협동3 강의의 버전 고정)
base_nvidia() {
    local flavor="" pin="" hold_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --open) flavor="-open" ;;
            --pin) pin="$2"; shift ;;
            --hold-all) hold_all=1 ;;
            *) die "${EXIT_SYSTEM}" "nvidia: unknown option $1" ;;
        esac
        shift
    done
    if ! has_nvidia_gpu; then
        echo "nvidia: no NVIDIA GPU on the PCI bus — nothing to install."
        return 0
    fi
    local pkg="nvidia-driver-${NVIDIA_DRIVER_BRANCH}${flavor}" have
    have="$(_installed_driver_pkg)"
    if [[ -n "${have}" ]]; then
        echo "nvidia: already installed (${have}) — keeping it."
    else
        apt_install ubuntu-drivers-common build-essential dkms
        if [[ -n "${pin}" ]] && apt-cache madison "${pkg}" | awk '{print $3}' | grep -qx "${pin}"; then
            apt_install "${pkg}=${pin}"
        else
            [[ -n "${pin}" ]] && warn "nvidia: pinned ${pkg}=${pin} is no longer in the archive — installing the newest ${pkg} instead."
            apt_install "${pkg}"
        fi
    fi
    if [[ "${hold_all}" == 1 ]]; then
        # 설치된 것만 (dpkg 가 아는 미설치 항목 제외) = 강의의 `dpkg -l | grep -i nvidia` 와 같은 범위
        local -a held
        mapfile -t held < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' '*nvidia*' 2>/dev/null \
            | awk '$1 ~ /^.i/ {print $2}' | sort -u)
        as_root apt-mark hold "${held[@]}"
    else
        as_root apt-mark hold "$(_installed_driver_pkg)"
    fi
    echo "nvidia: $(_installed_driver_pkg) installed + held (applies after reboot)."
}

# Docker 엔진 (강의 컨테이너용, docker/setup-host.sh 가 호출) + docker 그룹
base_docker() {
    local arch key="${KEYRING_DIR}/docker.asc"
    arch="$(dpkg --print-architecture)"
    apt_install ca-certificates curl
    add_apt_repo https://download.docker.com/linux/ubuntu/gpg "${key}" \
        /etc/apt/sources.list.d/docker.list \
        "deb [arch=${arch} signed-by=${key}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
    if pkg_installed docker-ce; then
        echo "docker: docker-ce already installed."
    else
        apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    # 엔진 버전 고정 (자동 업그레이드로 강의 컨테이너 동작이 바뀌지 않게)
    as_root apt-mark hold docker-ce docker-ce-cli containerd.io >/dev/null
    local user
    user="$(id -un)"
    if [[ "${user}" != root ]] && ! id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
        as_root usermod -aG docker "${user}"
        echo "docker: added ${user} to the docker group (active after re-login/reboot)."
    fi
    as_root docker run --rm hello-world >/dev/null
    docker --version
}

# 강의자료 방식 = ros2-apt-source 패키지 (버전 고정)
_ros_source_apt_source_pkg() {
    local ver="${ROS_APT_SOURCE_VERSION}" deb
    deb="$(mktemp --suffix=.deb)"
    curl -fsSL -o "${deb}" "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ver}/ros2-apt-source_${ver}.${UBUNTU_CODENAME}_all.deb"
    as_root dpkg -i "${deb}"
    rm -f "${deb}"
}

# ROS2 Jazzy desktop + 개발 도구 (ros-dev-tools = colcon · rosdep · vcstool)
#   이미 ROS 저장소가 잡혀 있으면 (예: 협동2 설치기의 ros2.list) 새로 추가하지 않음
#   → ros2-apt-source 의 ros2.sources 와 겹치면 apt 가 "Conflicting values set for option Signed-By" 로 실패
base_ros2() {
    apt_install locales software-properties-common curl
    as_root locale-gen en_US en_US.UTF-8
    as_root update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    as_root add-apt-repository -y universe
    __APT_UPDATED=0
    apt_update_once
    if ! pkg_installed ros2-apt-source && ! apt-cache policy "ros-${ROS_DISTRO}-ros-base" | grep -q 'Candidate: [0-9]'; then
        _ros_source_apt_source_pkg
        __APT_UPDATED=0
    fi
    apt_install "ros-${ROS_DISTRO}-desktop" ros-dev-tools python3-colcon-common-extensions \
        python3-rosdep python3-argcomplete python3-pip git build-essential \
        "ros-${ROS_DISTRO}-ament-package" "ros-${ROS_DISTRO}-ament-cmake" python3-pyqt5 libzmq3-dev python3-colcon-clean
    rosdep_ready
    echo "ros2: ROS 2 ${ROS_DISTRO} desktop installed ($(dpkg-query -W -f='${Version}' "ros-${ROS_DISTRO}-desktop"))."
}

base_vscode() {
    local key="${KEYRING_DIR}/packages.microsoft.gpg" arch
    arch="$(dpkg --print-architecture)"
    apt_install wget gpg apt-transport-https
    add_apt_repo https://packages.microsoft.com/keys/microsoft.asc "${key}" \
        /etc/apt/sources.list.d/vscode.list \
        "deb [arch=${arch} signed-by=${key}] https://packages.microsoft.com/repos/code stable main" dearmor
    apt_install code
    echo "vscode: $(dpkg-query -W -f='${Version}' code)"
}

# NVIDIA Container Toolkit · 강의 Docker 이미지에서 GPU 사용
base_toolkit() {
    if ! has_nvidia_gpu; then echo "toolkit: no NVIDIA GPU — skipping."; return 0; fi
    local key="${KEYRING_DIR}/nvidia-container-toolkit.gpg"
    local list=/etc/apt/sources.list.d/nvidia-container-toolkit.list line
    apt_install ca-certificates curl gnupg
    line="$(curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed "s#deb https://#deb [signed-by=${key}] https://#g")"
    add_apt_repo https://nvidia.github.io/libnvidia-container/gpgkey "${key}" "${list}" "${line}" dearmor
    apt_install nvidia-container-toolkit
    as_root nvidia-ctk runtime configure --runtime=docker
    as_root systemctl restart docker
    docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
        || as_root docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"' \
        || die "${EXIT_SYSTEM}" "toolkit: nvidia runtime not visible to docker."
    echo "toolkit: docker nvidia runtime registered."
}

# 재부팅 필요 여부 (0 = 필요) · 드라이버는 깔렸는데 모듈이 아직 안 올라온 상태
needs_reboot() {
    [[ -n "$(_installed_driver_pkg)" ]] && ! nvidia-smi >/dev/null 2>&1 && return 0
    [[ -f /var/run/reboot-required ]] && grep -qi nvidia /var/run/reboot-required.pkgs 2>/dev/null && return 0
    return 1
}

case "${1:?base: subcommand required (nvidia|docker|ros2|vscode|toolkit|needs-reboot)}" in
    nvidia)       shift; base_nvidia "$@" ;;
    docker)       base_docker ;;
    ros2)         base_ros2 ;;
    vscode)       base_vscode ;;
    toolkit)      base_toolkit ;;
    needs-reboot) needs_reboot ;;
    *) die "${EXIT_SYSTEM}" "base: unknown subcommand '$1'" ;;
esac
