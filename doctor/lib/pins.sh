# shellcheck shell=bash
# shellcheck disable=SC2034  # 값은 checks/*.sh 가 읽는다
# lib/pins.sh · source 전용 · 강의별 버전 핀과 경로
#   출처 = 각 설치기 resources/config.sh. 진단기는 설치기 저장소 없이도 돌아야 해서 값을 옮겨 둔다
#   어긋남 검사 = tests/test_pins.sh (설치기 저장소가 있는 개발 PC 에서 대조)
#   변수 이름은 설치기와 같게 둔다 → 대조 테스트가 이름으로 비교한다

# --- 공통 -----------------------------------------------------------------
ROS_DISTRO=jazzy
UBUNTU_CODENAME=noble
: "${BASHRC:=${HOME}/.bashrc}"

# --- 설치기 진행 기록 · 재부팅 재개 파일 ---------------------------------------
ROKEY_STATE_DIR="${HOME}/.rokey_jazzy_installer"          # 협동1 · 협동3 · 지능1 (<course>.state)
COBOT2_STATE_FILE="${HOME}/.cobot2_jazzy_installer/state"  # 협동2
AUTOSTART_DIR="${HOME}/.config/autostart"

# --- 협동1 · 협동2 공통 노트북 (출처 = 협동2 config.sh, 협동1 이 그대로 따름) --------
KERNEL_META=linux-generic-hwe-24.04
CYCLONEDDS_XML="${HOME}/.config/cyclonedds/cyclonedds.xml"
HOST_ETH_IP=192.168.1.30
HOST_ETH_PREFIX=24
# 협동2 templates sysctl-cyclonedds.conf 값 (협동1 템플릿도 같음)
SYSCTL_RMEM_MAX=2147483647
DSR_EMULATOR_IMAGE=doosanrobot/dsr_emulator:3.0.1
DOCKER_HELD_PKGS="docker-ce docker-ce-cli containerd.io"

# --- 협동1 -----------------------------------------------------------------
COBOT1_WS="${HOME}/ws_cobot_pjt/ws_dsr"
COBOT1_REPO_REF=4d5657f36a160eedb533ab1c975cd8a30c3e53b2
COBOT1_DDS_MARKER="# >>> cobot2_jazzy_installer cyclonedds env >>>"  # hostcfg.sh DDS_BEGIN · main 협동2 블록과 같은 이름

# --- 협동2 -----------------------------------------------------------------
NVIDIA_DRIVER_VERSION=595
DSR_WORKSPACE="${HOME}/cobot2_ws"
DSR_COMMIT=31750d68ed2855c780a8169c39aadb0a2cd80e1f
ONROBOT_COMMIT=c6e390313e831a2e54a0ad5894b2911cc360a16a
M0609_REPO_DIR="${HOME}/m0609_rg2_integration"
COBOT2_ENV_MARKER="# >>> cobot2_jazzy_installer env >>>"            # dev 설치기 (lib.sh bashrc_sync_block)
COBOT2_ENV_MARKER_END="# <<< cobot2_jazzy_installer env <<<"
COBOT2_DDS_MARKER="# >>> cobot2_jazzy_installer cyclonedds env >>>"  # main 설치기 (hostcfg.sh dds) · 협동1 과 같은 블록
COBOT2_DDS_MARKER_END="# <<< cobot2_jazzy_installer cyclonedds env <<<"
YOLO_IMAGE_SUFFIX=ros2-jazzy-yolo:dev-builder   # 앞부분 = docker.io/<DOCKERHUB_USER 또는 local>

# --- 협동3 · 지능1 공통 -------------------------------------------------------
NVIDIA_DRIVER_BRANCH=580

# --- 협동3 -----------------------------------------------------------------
ISAACSIM_VERSION=5.1.0
ISAACSIM_DIR="${HOME}/isaacsim"
ISAAC_ROS_WS_REF="IsaacSim-${ISAACSIM_VERSION}"
ISAAC_ROS_WS_DIR="${HOME}/IsaacSim-ros_workspaces"
COBOT3_WS="${HOME}/cobot3_ws"
FASTDDS_PROFILE="${HOME}/.ros/fastdds_whitelist.xml"

# --- 지능1 -----------------------------------------------------------------
TB4_WS="${HOME}/turtlebot4_ws"
LABELIMG_DIR="${HOME}/labelImg"
INTEL1_MATERIALS_DIR="${HOME}/Documents/to_students"
INTEL1_NUMPY_VERSION=1.26.4
INTEL1_OPENCV_PREFIX=4.9.0
