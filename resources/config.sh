#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# resources/config.sh · source 전용
#   버전 핀 · 경로의 단일 진실 소스
#   distro/OS 핀 = `=` 강제 / 나머지 = `:=` 로 환경변수 override 가능

# --- distro / OS (강제) --------------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble
export DEBIAN_FRONTEND=noninteractive

# --- 레포 / 상태 / 로그 ----------------------------------------------------
: "${INSTALLER_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${STATE_DIR:=${HOME}/.rokey_jazzy_installer}"
# 상세 로그 = append-only, 레포 루트 install_log (git 추적 제외)
: "${LOG_FILE:=${INSTALLER_ROOT}/install_log}"
: "${KEYRING_DIR:=/etc/apt/keyrings}"
: "${BASHRC:=${HOME}/.bashrc}"

# --- NVIDIA ---------------------------------------------------------------
# 강의 = 580 계열 open 커널 모듈 + 버전 고정 + hold
: "${NVIDIA_DRIVER_BRANCH:=580}"
# 협동3 강의가 고정한 버전. 저장소에서 빠졌으면 같은 브랜치 최신으로 대체 (경고 출력)
: "${NVIDIA_DRIVER_PIN_COBOT3:=580.173.02-0ubuntu0.24.04.1}"

# --- ROS 2 apt 저장소 설정 패키지 ----------------------------------------
# 강의 = GitHub API 로 latest 조회 → 강의실 한 IP 에서 60회/시간 제한에 걸림 → 버전 고정
: "${ROS_APT_SOURCE_VERSION:=1.3.0}"

# --- 협동3 (Isaac Sim 5.1.0 + Nav2) ---------------------------------------
: "${ISAACSIM_VERSION:=5.1.0}"
: "${ISAACSIM_DIR:=${HOME}/isaacsim}"
: "${ISAACSIM_ZIP_NAME:=isaac-sim-standalone-${ISAACSIM_VERSION}-linux-x86_64.zip}"
: "${ISAACSIM_ZIP_URL:=https://download.isaacsim.omniverse.nvidia.com/${ISAACSIM_ZIP_NAME}}"
: "${ISAAC_ROS_WS_URL:=https://github.com/isaac-sim/IsaacSim-ros_workspaces.git}"
# main 브랜치 = 이미 6.x 용 → 강의 버전 태그로 고정
: "${ISAAC_ROS_WS_REF:=IsaacSim-${ISAACSIM_VERSION}}"
: "${ISAAC_ROS_WS_DIR:=${HOME}/IsaacSim-ros_workspaces}"
: "${COBOT3_WS:=${HOME}/cobot3_ws}"
: "${COBOT3_DEFAULT_DOMAIN_ID:=50}"
: "${FASTDDS_PROFILE:=${HOME}/.ros/fastdds_whitelist.xml}"

# --- 자체 점검 --------------------------------------------------------------
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_DIR LOG_FILE KEYRING_DIR BASHRC; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '${var}' is empty" >&2
            missing=1
        fi
    done
    return "${missing}"
}
