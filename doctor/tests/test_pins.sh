#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # 설정값은 source 한 코드가 읽음
# tests/test_pins.sh · lib/pins.sh 값이 설치기 config.sh 와 같은지 대조
#   진단기 = 설치기 저장소의 doctor/ → 자기 저장소 config.sh 는 반드시 대조
#   다른 강의 설치기 = 같은 상위 폴더에 clone 돼 있으면 함께 대조 (없으면 건너뜀)
#   이 테스트가 깨지면 = 설치기 핀이 바뀌었는데 진단기가 옛 값을 보고 있다

# 협동1 · 협동3 · 지능1 설치기 (rokey 계열) 와 협동2 설치기는 변수 이름이 다르다
readonly ROKEY_PAIRS=(ROKEY_STATE_DIR=STATE_DIR KERNEL_META=KERNEL_META CYCLONEDDS_XML=CYCLONEDDS_XML
    HOST_ETH_IP=HOST_ETH_IP HOST_ETH_PREFIX=HOST_ETH_PREFIX COBOT1_WS=COBOT1_WS
    COBOT1_REPO_REF=COBOT1_REPO_REF DSR_EMULATOR_IMAGE=DSR_EMULATOR_IMAGE
    NVIDIA_DRIVER_BRANCH=NVIDIA_DRIVER_BRANCH ISAACSIM_VERSION=ISAACSIM_VERSION ISAACSIM_DIR=ISAACSIM_DIR
    ISAAC_ROS_WS_REF=ISAAC_ROS_WS_REF ISAAC_ROS_WS_DIR=ISAAC_ROS_WS_DIR COBOT3_WS=COBOT3_WS
    FASTDDS_PROFILE=FASTDDS_PROFILE TB4_WS=TB4_WS LABELIMG_DIR=LABELIMG_DIR
    INTEL1_MATERIALS_DIR=INTEL1_MATERIALS_DIR)
readonly COBOT2_PAIRS=(COBOT2_STATE_FILE=STATE_FILE KERNEL_META=KERNEL_META CYCLONEDDS_XML=CYCLONEDDS_XML
    HOST_ETH_IP=HOST_ETH_IP HOST_ETH_PREFIX=HOST_ETH_PREFIX NVIDIA_DRIVER_VERSION=NVIDIA_DRIVER_VERSION
    DSR_WORKSPACE=DSR_WORKSPACE DSR_COMMIT=DSR_COMMIT ONROBOT_COMMIT=ONROBOT_COMMIT M0609_REPO_DIR=M0609_REPO_DIR)

# 설치기 config.sh 를 깨끗한 셸에서 읽어 변수 하나를 돌려준다 (두 config 를 한 셸에 섞지 않음)
_installer_var() {
    env -i HOME="${HOME}" PATH="${PATH}" bash -c \
        'source "$1" >/dev/null 2>&1; printf "%s" "${!2}"' _ "$1" "$2"
}

# 대조할 설치기 루트 목록: 자기 저장소 + 상위 두 단계의 *_jazzy_installer (INSTALLER_ROOTS 로 덮어쓰기)
_installer_roots() {
    if [[ -n "${INSTALLER_ROOTS:-}" ]]; then tr ':' '\n' <<<"${INSTALLER_ROOTS}"; return; fi
    local d
    for d in "${DOCTOR_ROOT}/.." "${DOCTOR_ROOT}"/../../*_jazzy_installer "${DOCTOR_ROOT}"/../../../*_jazzy_installer; do
        [[ -f "${d}/resources/config.sh" ]] && (cd "${d}" && pwd)
    done | sort -u
}

# _compare_root <설치기 루트> · 그 config 가 정의한 변수만 대조. 어긋남을 모두 출력, 대조 0개면 실패
_compare_root() {
    local cfg="$1/resources/config.sh" pair ours theirs want bad=0 n=0
    local -a pairs=("${ROKEY_PAIRS[@]}")
    [[ -n "$(_installer_var "${cfg}" DSR_WORKSPACE)" ]] && pairs=("${COBOT2_PAIRS[@]}")
    for pair in "${pairs[@]}"; do
        ours="${pair%%=*}"; theirs="${pair#*=}"
        want="$(_installer_var "${cfg}" "${theirs}")"
        [[ -n "${want}" ]] || continue
        n=$((n + 1))
        [[ "${!ours}" == "${want}" ]] || { echo "drift: ${ours}=[${!ours}] / ${cfg}: ${theirs}=[${want}]"; bad=1; }
    done
    [[ ${n} -gt 0 ]] || { echo "대조한 값 없음: ${cfg}"; return 1; }
    return "${bad}"
}

test_pins_match_own_installer_config() {
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    local own="${DOCTOR_ROOT}/.."
    if [[ ! -f "${own}/resources/config.sh" ]]; then echo "skip: 설치기 저장소 밖 (${own})"; return 0; fi
    _compare_root "${own}"
}

test_pins_match_sibling_installer_configs() {
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    local root bad=0
    while IFS= read -r root; do
        _compare_root "${root}" || bad=1
    done < <(_installer_roots)
    return "${bad}"
}

test_pins_match_markers_and_templates() {
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    local root
    while IFS= read -r root; do
        if [[ -f "${root}/resources/templates/sysctl-cyclonedds.conf" ]]; then
            assert_eq "$(sed -n 's/^net.core.rmem_max *= *//p' "${root}/resources/templates/sysctl-cyclonedds.conf")" "${SYSCTL_RMEM_MAX}"
        fi
        if grep -q '^DDS_BEGIN=' "${root}/resources/hostcfg.sh" 2>/dev/null; then
            grep -qF "DDS_BEGIN=\"${COBOT1_DDS_MARKER}\"" "${root}/resources/hostcfg.sh"
        fi
        # main 협동2 설치기 = hostcfg.sh dds 가 블록을 직접 씀
        if grep -q '^ *BEGIN_MARK=' "${root}/resources/hostcfg.sh" 2>/dev/null; then
            grep -qF "BEGIN_MARK=\"${COBOT2_DDS_MARKER}\"" "${root}/resources/hostcfg.sh"
            grep -qF "END_MARK=\"${COBOT2_DDS_MARKER_END}\"" "${root}/resources/hostcfg.sh"
        fi
        if grep -q 'bashrc_sync_block()' "${root}/resources/lib.sh" 2>/dev/null; then
            grep -qF "local begin=\"${COBOT2_ENV_MARKER}\"" "${root}/resources/lib.sh"
            assert_eq "doosanrobot/dsr_emulator:$(_installer_var "${root}/resources/config.sh" DSR_EMULATOR_VERSION)" \
                "${DSR_EMULATOR_IMAGE}"
        fi
    done < <(_installer_roots)
}

test_compare_root_catches_drift() {
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    mkdir -p fake/resources
    printf ': "${TB4_WS:=${HOME}/other_ws}"\n: "${STATE_DIR:=${HOME}/.rokey_jazzy_installer}"\n' > fake/resources/config.sh
    assert_contains "$(_compare_root fake || true)" "drift: TB4_WS="
    printf ': "${TB4_WS:=${HOME}/turtlebot4_ws}"\n' > fake/resources/config.sh
    _compare_root fake
}
