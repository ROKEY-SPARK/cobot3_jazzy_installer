# shellcheck shell=bash
# shellcheck disable=SC2088,SC2016  # "~/..." = 화면 문구 / bash -c '...' = 안쪽 셸이 펼칠 변수
# checks/intel1.sh · 지능1 (TurtleBot4 + YOLO) PC 셋업
#   기준 = 지능1 설치기 resources/verify.sh 항목

# 강의 고정 버전 (pip --user). numpy 2 / opencv 4.10+ 가 들어오면 cv_bridge · 강의 코드가 깨짐
yolo_stack_pinned() {
    py_check "import numpy, cv2, torch, ultralytics
print('numpy', numpy.__version__, '/ cv2', cv2.__version__, '/ torch', torch.__version__)
assert numpy.__version__ == '${INTEL1_NUMPY_VERSION}', 'numpy ' + numpy.__version__
assert cv2.__version__.startswith('${INTEL1_OPENCV_PREFIX}'), 'cv2 ' + cv2.__version__"
}

torch_sees_gpu() { py_check 'import torch, sys; print(sys.executable, torch.__version__, torch.version.cuda); sys.exit(0 if torch.cuda.is_available() else 1)'; }

check_intel1() {
    local ov="${TB4_WS}/install/setup.bash"
    local fix="bash install.sh intel1 (지능1 설치기, 끝난 단계는 건너뜀)"
    section "지능1"
    if [[ "${SKIP_GPU}" == 0 ]] && has_nvidia_gpu; then
        check warn "NVIDIA 드라이버 nvidia-driver-${NVIDIA_DRIVER_BRANCH}" "${fix}" nvidia_driver_is "nvidia-driver-${NVIDIA_DRIVER_BRANCH}"
        check fail "torch 가 GPU 사용 (CUDA wheel)" "${fix} — CPU wheel 이 깔렸으면 YOLO 단계 재실행" torch_sees_gpu
    fi
    check fail "워크스페이스 패키지 이름 중복 없음" "표시된 중복 중 하나를 지우거나 COLCON_IGNORE" ws_unique_packages "${TB4_WS}"
    check fail "turtlebot4 워크스페이스 빌드" "cd ${TB4_WS} && colcon build --symlink-install" \
        ros_has_pkg "${ov}" turtlebot4_navigation turtlebot4_viz turtlebot4_gz_bringup explore_lite
    check fail "YOLO 스택 고정 버전 (numpy ${INTEL1_NUMPY_VERSION} · opencv ${INTEL1_OPENCV_PREFIX})" "${fix}" yolo_stack_pinned
    check fail "LabelImg 빌드 (resources.py)" "${fix}" path_exists "${LABELIMG_DIR}/libs/resources.py"
    check fail "강의록 저장소 to_students" "${fix}" path_exists "${INTEL1_MATERIALS_DIR}/.git"
    check fail "terminator" "${fix}" bash -c 'command -v terminator >/dev/null || { echo "없음: terminator"; exit 1; }'
    check fail "~/.bashrc 지능1 블록" "${fix}" bashrc_block_ok "# >>> rokey intel1 >>>" "# <<< rokey intel1 <<<"
}
