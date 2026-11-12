# shellcheck shell=bash
# shellcheck disable=SC2088,SC2016  # "~/..." = 화면 문구 / bash -c '...' = 안쪽 셸이 펼칠 변수
# checks/cobot1.sh · 협동1 (Doosan M0609 + RG2, cobot_rg2 워크스페이스)
#   기준 = 협동1 설치기 resources/verify.sh 항목 + 고정 커밋

check_cobot1() {
    local ov="${COBOT1_WS}/install/setup.bash"
    local fix="bash install.sh cobot1 (협동1 설치기, 끝난 단계는 건너뜀)"
    check_cobot_laptop
    section "협동1"
    check fail "워크스페이스 clone (${COBOT1_WS}/src)" "${fix}" path_exists "${COBOT1_WS}/src/rg2/m0609_rg2_bringup/package.xml"
    check fail "워크스페이스 패키지 이름 중복 없음" "표시된 중복 중 하나를 지우거나 COLCON_IGNORE" ws_unique_packages "${COBOT1_WS}"
    check warn "cobot_rg2 고정 커밋" "git -C ${COBOT1_WS}/src checkout --detach ${COBOT1_REPO_REF}" git_at_ref "${COBOT1_WS}/src" "${COBOT1_REPO_REF}"
    check fail "빌드된 패키지 (m0609_rg2_bringup · dsr_bringup2 · dsr_example · rokey)" \
        "cd ${COBOT1_WS} && colcon build" ros_has_pkg "${ov}" m0609_rg2_bringup dsr_bringup2 dsr_example rokey
    check fail "DSR_ROBOT2 import 경로 (PYTHONPATH imp)" "cd ${COBOT1_WS} && colcon build" \
        path_exists "${COBOT1_WS}/install/dsr_common2/lib/dsr_common2/imp/DSR_ROBOT2.py"
    check fail "python 모듈 (pymodbus · PyQt5 uic)" "${fix}" py_check 'import pymodbus; from PyQt5 import uic'
    check fail "강의 도구 (designer · fastdds · terminator)" "${fix}" bash -c \
        'for c in designer fastdds terminator; do command -v "$c" >/dev/null || { echo "없음: $c"; bad=1; }; done; exit ${bad:-0}'
    [[ "${SKIP_HOST}" == 1 ]] || check fail "RealSense udev rule" "${fix}" path_exists /etc/udev/rules.d/99-realsense-libusb.rules
    check fail "~/.bashrc 협동1 블록" "${fix}" bashrc_block_ok "# >>> rokey cobot1 >>>" "# <<< rokey cobot1 <<<"
    check fail "~/.bashrc 협동1 DDS 블록" "${fix}" bashrc_block_ok "${COBOT1_DDS_MARKER}"
}
