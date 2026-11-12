# shellcheck shell=bash
# shellcheck disable=SC2088,SC2016  # "~/..." = 화면 문구 / bash -c '...' = 안쪽 셸이 펼칠 변수
# checks/cobot2.sh · 협동2 (base install.sh + setup-app.sh 워크스페이스 · 컨테이너)
#   기준 = 협동2 설치기 base-install.sh · app-install.sh · setup-app.sh · docs/TROUBLESHOOTING.md

# m0609_rg2_bringup 은 심볼릭 링크여야 함 (실제 디렉토리면 m0609 저장소 갱신이 반영 안 됨)
m0609_symlink_ok() {
    local l="${DSR_WORKSPACE}/src/m0609_rg2_bringup"
    [[ -L "${l}" ]] || { echo "심볼릭 링크 아님: ${l}"; return 1; }
    [[ -e "${l}" ]] || { echo "깨진 링크: ${l} → $(readlink "${l}")"; return 1; }
}

# 504 오류 페이지가 .tflite 로 저장되는 사고 → 4~8 바이트가 TFL3 인지 확인
wakeword_models_valid() {
    local d f bad=0 n=0
    d="${DSR_WORKSPACE}/install/voice_processing/share/voice_processing/resource"
    for f in "${d}"/*.tflite; do
        [[ -f "${f}" ]] || continue
        n=$((n + 1))
        [[ "$(dd if="${f}" bs=1 skip=4 count=4 2>/dev/null)" == TFL3 ]] || { echo "손상: ${f}"; bad=1; }
    done
    [[ ${n} -gt 0 ]] || { echo "없음: ${d}/*.tflite (colcon build 필요)"; return 1; }
    return "${bad}"
}

# RealSense 키 교체 전 옛 저장소 파일이 남으면 apt update 가 NO_PUBKEY 로 실패
realsense_legacy_repo_absent() {
    local f bad=0
    for f in /etc/apt/sources.list.d/librealsense.list /etc/apt/keyrings/librealsense.pgp; do
        [[ ! -e "${f}" ]] || { echo "남아 있음: ${f}"; bad=1; }
    done
    return "${bad}"
}

docker_nvidia_runtime() {
    command -v docker >/dev/null || { skip_because "docker 미설치"; return; }
    local rt
    rt="$(run_t docker info --format '{{json .Runtimes}}' 2>/dev/null)" || { skip_because "docker 데몬 접근 불가"; return; }
    grep -q '"nvidia"' <<<"${rt}" || { echo "docker 런타임에 nvidia 없음"; return 1; }
}

# 태그 앞부분은 DOCKERHUB_USER 에 따라 달라짐 (기본 docker.io/local) → 저장소 이름 끝 · 태그로 찾는다
yolo_image_present() {
    command -v docker >/dev/null || { skip_because "docker 미설치"; return; }
    local imgs
    imgs="$(run_t docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null)" || { skip_because "docker 데몬 접근 불가"; return; }
    grep -qE "(^|/)${YOLO_IMAGE_SUFFIX}\$" <<<"${imgs}" || { echo "이미지 없음: */${YOLO_IMAGE_SUFFIX}"; return 1; }
}

legacy_paths_absent() {
    local p bad=0
    for p in "${HOME}/M0609_RG2_Integration" "${HOME}/.ros2_jazzy_test"; do
        [[ ! -e "${p}" ]] || { echo "옛 경로 남음: ${p}"; bad=1; }
    done
    grep -nE '^# >>> ros2_jazzy_test .*>>>$' "${BASHRC}" 2>/dev/null && bad=1
    return "${bad}"
}

check_cobot2() {
    local ws="${DSR_WORKSPACE}" ov="${DSR_WORKSPACE}/install/setup.bash" ros="ros-${ROS_DISTRO}"
    local base="bash install.sh (협동2 설치기, 끝난 단계는 건너뜀)" app="bash setup-app.sh (협동2 설치기)"
    check_cobot_laptop
    section "협동2"
    if [[ "${SKIP_GPU}" == 0 ]] && has_nvidia_gpu; then
        check fail "NVIDIA 드라이버 nvidia-driver-${NVIDIA_DRIVER_VERSION} (closed · Optimus 화면 안정)" "${base}" \
            nvidia_driver_is "nvidia-driver-${NVIDIA_DRIVER_VERSION}"
        check fail "드라이버 hold" "sudo apt-mark hold nvidia-driver-${NVIDIA_DRIVER_VERSION}" pkg_held "nvidia-driver-${NVIDIA_DRIVER_VERSION}"
        check fail "HWE 커널용 nvidia 모듈 meta" "${base}" \
            pkg_installed "linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}-generic-hwe-24.04"
        [[ "${SKIP_DOCKER}" == 1 ]] || check fail "docker nvidia 런타임 (yolo 컨테이너 GPU)" \
            "sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker" docker_nvidia_runtime
    fi
    check fail "~/.bashrc 협동2 env 블록 (1개 · 시작/끝 짝)" "협동2 설치기 bash resources/hostcfg.sh dds" \
        bashrc_block_ok "${COBOT2_ENV_MARKER}" "${COBOT2_ENV_MARKER_END}"
    check warn "옛 이름 경로 · bashrc 블록 없음" "${app}" legacy_paths_absent
    check fail "cobot2 소스 배치 (${ws}/src/cobot2)" "강사 안내대로 cobot2 소스를 ${ws}/src/cobot2 에 배치" \
        bash -c 'compgen -G "$1/src/cobot2/*/package.xml" >/dev/null || compgen -G "$1/src/cobot2/*/*/package.xml" >/dev/null || { echo "package.xml 없음"; exit 1; }' _ "${ws}"
    check fail "워크스페이스 패키지 이름 중복 없음" "표시된 중복 중 하나를 지우거나 COLCON_IGNORE" ws_unique_packages "${ws}"
    check fail "m0609_rg2_bringup 심볼릭 링크" "${app}" m0609_symlink_ok
    check fail "doosan-robot2 고정 커밋" "${app}" git_at_ref "${ws}/src/doosan-robot2" "${DSR_COMMIT}"
    check fail "onrobot-ros2 고정 커밋" "${app}" git_at_ref "${ws}/src/onrobot-ros2" "${ONROBOT_COMMIT}"
    check fail "빌드된 패키지 (dsr_bringup2 · m0609_rg2_bringup · od_msg · voice_processing)" "cd ${ws} && colcon build" \
        ros_has_pkg "${ov}" dsr_bringup2 m0609_rg2_bringup od_msg voice_processing
    check fail "RealSense SDK · ROS 래퍼" "${app}" \
        pkg_installed librealsense2-utils librealsense2-dkms "${ros}-realsense2-camera"
    check fail "RealSense 옛 저장소 파일 없음 (NO_PUBKEY 예방)" "표시된 파일 삭제 후 ${app}" realsense_legacy_repo_absent
    check fail "voice python 모듈" "${app}" \
        py_check 'import langchain, langchain_openai, openai, pyaudio, sounddevice, scipy, dotenv, openwakeword, pymodbus'
    # 설치기가 깔지 않음 → 정상 설치 PC 에서도 나올 수 있어 warn (pick_and_place_voice robot_control 이 씀)
    check warn "pyserial (No module named 'serial' 예방)" "sudo apt install python3-serial" py_check 'import serial'
    check fail "wakeword 모델 (.tflite) 정상" "${app}" wakeword_models_valid
    [[ "${SKIP_DOCKER}" == 1 ]] || check fail "yolo 이미지 */${YOLO_IMAGE_SUFFIX}" "${app}" yolo_image_present
}
