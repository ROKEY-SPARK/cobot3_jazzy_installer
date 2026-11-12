#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2034  # SKIP_* 는 checks/*.sh 가 읽는다
# =============================================================
#  ROKEY Jazzy 강의 PC 진단기 (협동1 · 협동2 · 협동3 · 지능1)
# =============================================================
#
# 읽기 전용 — 시스템을 바꾸지 않고 sudo 도 부르지 않는다. 결과 = stdout, 사용법 오류 = stderr
# 종료 코드: 0 = FAIL 없음 (WARN · SKIP 은 허용) / 1 = 잘못된 인자 / 2 = FAIL 하나 이상
set -uo pipefail

DOCTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly EXIT_USER=1
readonly EXIT_FAIL=2
readonly COURSES=(cobot1 cobot2 cobot3 intel1)

# shellcheck source=lib/report.sh
source "${DOCTOR_ROOT}/lib/report.sh"
# shellcheck source=lib/pins.sh
source "${DOCTOR_ROOT}/lib/pins.sh"
# shellcheck source=lib/probes.sh
source "${DOCTOR_ROOT}/lib/probes.sh"
for f in "${DOCTOR_ROOT}"/checks/*.sh; do
    # shellcheck source=/dev/null
    source "${f}"
done

usage() {
    cat <<'EOF'
사용: bash doctor.sh [강의...] [옵션]

강의 PC 의 설치 누락 · 패키지 깨짐 · 공통 시스템 오류를 점검한다 (읽기 전용, sudo 불필요).

강의 (여러 개 가능, 생략하면 설치 흔적으로 자동 감지):
  cobot1   협동1 (M0609 + RG2, ~/ws_cobot_pjt/ws_dsr)
  cobot2   협동2 (~/cobot2_ws, yolo · voice)
  cobot3   협동3 (Isaac Sim 5.1.0 + Nav2)
  intel1   지능1 (TurtleBot4 + YOLO)

옵션:
  --no-host     커널 · 부팅 · sysctl · 정적 IP · 시간 점검 생략 (컨테이너 안에서 실행할 때)
  --no-gpu      NVIDIA 드라이버 · GPU 점검 생략
  --no-docker   docker 그룹 · 데몬 · 이미지 · 런타임 점검 생략
  --no-isaac    Isaac Sim 본체 점검 생략 (협동3)
  -h, --help    이 도움말

결과: [PASS] 정상 · [WARN] 확인 권장 · [FAIL] 고쳐야 함 (→ 뒤에 복구 방법) · [SKIP] 판정 불가
종료 코드: 0 = FAIL 없음 · 1 = 잘못된 인자 · 2 = FAIL 있음
EOF
}

# 설치 흔적 = state 파일 · bashrc 마커 · 워크스페이스 중 하나 (--reset 은 state 만 지우므로 셋 다 본다)
course_installed() {
    local marker
    case "$1" in
        cobot1) [[ -f "${ROKEY_STATE_DIR}/cobot1.state" || -d "${COBOT1_WS}/src" ]] && return 0
                marker="# >>> rokey cobot1 >>>" ;;
        cobot2) [[ -f "${COBOT2_STATE_FILE}" || -d "${DSR_WORKSPACE}/src" ]] && return 0
                marker="${COBOT2_ENV_MARKER}" ;;
        cobot3) [[ -f "${ROKEY_STATE_DIR}/cobot3.state" || -d "${ISAACSIM_DIR}" ]] && return 0
                marker="# >>> rokey cobot3 >>>" ;;
        intel1) [[ -f "${ROKEY_STATE_DIR}/intel1.state" || -d "${TB4_WS}/src" ]] && return 0
                marker="# >>> rokey intel1 >>>" ;;
    esac
    grep -qxF "${marker}" "${BASHRC}" 2>/dev/null
}

detect_courses() {
    local c
    for c in "${COURSES[@]}"; do course_installed "${c}" && echo "${c}"; done
}

# 드라이버를 까는 강의가 하나라도 있으면 fail, 협동1 만이거나 강의가 없으면 warn
gpu_driver_level() {
    local c
    for c in "$@"; do
        case "${c}" in cobot2|cobot3|intel1) echo fail; return 0 ;; esac
    done
    echo warn
}

is_course() { local c; for c in "${COURSES[@]}"; do [[ "$1" == "${c}" ]] && return 0; done; return 1; }

main() {
    local -a selected=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-host) SKIP_HOST=1 ;;
            --no-gpu) SKIP_GPU=1 ;;
            --no-docker) SKIP_DOCKER=1 ;;
            --no-isaac) SKIP_ISAAC=1 ;;
            -h|--help) usage; return 0 ;;
            *) is_course "$1" || { echo "doctor: 알 수 없는 인자 '$1' (bash doctor.sh --help)" >&2; return "${EXIT_USER}"; }
               [[ " ${selected[*]} " == *" $1 "* ]] || selected+=("$1") ;;
        esac
        shift
    done
    local how="지정"
    if [[ ${#selected[@]} -eq 0 ]]; then
        mapfile -t selected < <(detect_courses)
        how="자동 감지"
    fi

    # root 로 돌리면 HOME · 그룹이 학생 계정 것이 아니게 된다
    [[ ${EUID} -ne 0 ]] || echo "doctor: root 로 실행 중 → ~/.bashrc · docker 그룹 결과가 학생 계정과 다를 수 있음 (sudo 없이 실행)" >&2
    GPU_DRIVER_LEVEL="$(gpu_driver_level "${selected[@]}")"

    echo "ROKEY 강의 PC 진단 · $(date '+%Y-%m-%d %H:%M %Z') · $(hostname) · 커널 $(uname -r)"
    if [[ ${#selected[@]} -gt 0 ]]; then
        echo "강의 (${how}): ${selected[*]}"
    else
        echo "강의: 설치 흔적 없음 → 공통 점검만 실행 (강의를 지정하려면: bash doctor.sh cobot1)"
    fi

    check_system
    check_ros_env
    check_dds
    local c
    for c in "${selected[@]}"; do "check_${c}"; done
    report_summary || return "${EXIT_FAIL}"
}

# source 하면 (테스트) 함수만 정의하고 끝난다
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
    exit $?
fi
