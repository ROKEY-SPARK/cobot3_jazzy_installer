#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh · 협동3 PC 자동 설치 진입점 (Ubuntu 24.04 + ROS 2 Jazzy)
#   협동3 = Isaac Sim 5.1.0 + Nav2 + Isaac ROS 워크스페이스
#   단계 순서 = resources/courses.sh / 단계 구현 = resources/<base|cobot3>.sh
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"
# shellcheck source=resources/sys.sh
source "${RESOURCE_DIR}/sys.sh"
# shellcheck source=resources/courses.sh
source "${RESOURCE_DIR}/courses.sh"

usage() {
    cat <<'EOF'
Usage: bash install.sh [options]

Installs the 협동3 lecture PC: NVIDIA 580-open driver (pinned), ROS 2 Jazzy, Isaac Sim 5.1.0,
Nav2 + Foxglove, IsaacSim-ros_workspaces (IsaacSim-5.1.0 tag), cobot3_ws, FastDDS profile.
(The old form 'bash install.sh cobot3 [options]' still works.)

Options:
  --domain-id N      write 'export ROS_DOMAIN_ID=N' into the ~/.bashrc block (team ID, default 50)
  --no-nvidia        skip the NVIDIA driver step (driver already installed, or no NVIDIA GPU)
  --isaac-zip PATH   Isaac Sim 5.1.0 zip location (default: search USB, ~/Downloads)
  --isaac-download   download the zip (~8.7GB) when it is not found
  --no-kernel-hold   do not hold the running kernel / skip the full apt upgrade
  -y, --yes          answer yes to confirmations (needed in a non-interactive shell)
  -v, --verbose      also print each step's detailed output to the console
  --dry-run          print the steps that would run; change nothing

Commands (instead of installing):
  --status           print which steps are done
  --verify           check the installed result (read-only)
  --reset            forget the install progress (asks first; installed files are kept)
  -h, --help         this help

Finished steps are skipped on a re-run. After the NVIDIA driver step the installer asks for a
reboot; run the same command again afterwards. Detailed log: ./install_log
Other lectures: 협동1 https://github.com/ROKEY-SPARK/cobot1_jazzy_installer
                지능1 https://github.com/ROKEY-SPARK/int1_jazzy_installer
Exit codes: 0 success, 1 user error (bad option, missing input), 2 system error (step failed).
EOF
}

# 이 저장소 = 협동3 전용. COURSE = state 파일 · bashrc 블록 이름 (cobot3.state, rokey cobot3)
COURSE=cobot3
CMD=install
OPT_DOMAIN_ID=""
OPT_NO_NVIDIA=0
OPT_ISAAC_ZIP=""
OPT_ISAAC_DOWNLOAD=0
OPT_NO_KERNEL_HOLD=0
ASSUME_YES=0
VERBOSE="${VERBOSE:-0}"
DRY_RUN=0

need_value() { [[ -n "${2:-}" && "${2}" != -* ]] || die "${EXIT_USER}" "$1 needs a value (see --help)"; }

# 다른 강의 이름 = 저장소를 잘못 받은 경우 → 맞는 저장소 안내
wrong_course() {
    local url
    case "$1" in
        cobot1) url=https://github.com/ROKEY-SPARK/cobot1_jazzy_installer ;;
        cobot2) url=https://github.com/ROKEY-SPARK/cobot2_jazzy_installer ;;
        *)      url=https://github.com/ROKEY-SPARK/int1_jazzy_installer ;;
    esac
    die "${EXIT_USER}" "this repository installs 협동3 (cobot3) only. For '$1' use ${url}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            cobot3) ;;   # 예전 형식 (bash install.sh cobot3 ...) 호환
            cobot1|cobot2|intel1|int1) wrong_course "$1" ;;
            --domain-id)      need_value "$1" "${2:-}"; OPT_DOMAIN_ID="$2"; shift ;;
            --no-nvidia)      OPT_NO_NVIDIA=1 ;;
            --isaac-zip)      need_value "$1" "${2:-}"; OPT_ISAAC_ZIP="$(realpath -m "$2")"; shift ;;
            --isaac-download) OPT_ISAAC_DOWNLOAD=1 ;;
            --no-kernel-hold) OPT_NO_KERNEL_HOLD=1 ;;
            -y|--yes)         ASSUME_YES=1 ;;
            -v|--verbose)     VERBOSE=1 ;;
            --dry-run)        DRY_RUN=1 ;;
            --status|--verify|--reset) CMD="${1#--}" ;;
            -h|--help)        usage; exit 0 ;;
            *) echo "install: unknown argument '$1'" >&2; usage >&2; exit "${EXIT_USER}" ;;
        esac
        shift
    done
    if [[ -n "${OPT_DOMAIN_ID}" ]] && ! [[ "${OPT_DOMAIN_ID}" =~ ^[0-9]+$ && "${OPT_DOMAIN_ID}" -le 232 ]]; then
        die "${EXIT_USER}" "--domain-id must be an integer 0..232 (got '${OPT_DOMAIN_ID}')"
    fi
    if [[ -n "${OPT_ISAAC_ZIP}" && ! -f "${OPT_ISAAC_ZIP}" ]]; then
        die "${EXIT_USER}" "--isaac-zip: file not found: ${OPT_ISAAC_ZIP}"
    fi
    export ASSUME_YES VERBOSE DRY_RUN
}

preflight() {
    [[ "${EUID}" -ne 0 ]] || die "${EXIT_USER}" "do not run with sudo — run 'bash install.sh' as your user (it calls sudo itself)."
    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    # shellcheck disable=SC2031  # os-release 는 서브셸에서만 읽음 → config 의 UBUNTU_CODENAME 은 그대로
    [[ "${codename}" == "${UBUNTU_CODENAME}" ]] \
        || die "${EXIT_USER}" "this installer targets Ubuntu 24.04 (${UBUNTU_CODENAME}); current: '${codename:-unknown}'."
    config_assert_set || die "${EXIT_SYSTEM}" "config incomplete"
    mkdir -p "$(dirname "${LOG_FILE}")"
}

# Isaac Sim zip 을 못 찾으면 시작 전에 한 번만 묻는다 (단계 출력은 로그로 가므로)
preflight_isaac() {
    [[ "${DRY_RUN}" == 0 ]] || return 0
    step_is_done isaacsim && return 0
    [[ -n "${OPT_ISAAC_ZIP}" || "${OPT_ISAAC_DOWNLOAD}" == 1 ]] && return 0
    if compgen -G "/media/$(id -un)/*/${ISAACSIM_ZIP_NAME}" >/dev/null || [[ -f "${HOME}/Downloads/${ISAACSIM_ZIP_NAME}" ]] \
        || [[ -x "${ISAACSIM_DIR}/isaac-sim.sh" ]]; then
        return 0
    fi
    echo "Isaac Sim zip (${ISAACSIM_ZIP_NAME}) not found on a USB stick or in ~/Downloads."
    # --yes 는 8.7GB 다운로드까지 동의한 것으로 보지 않는다 → 명시 플래그 또는 대화형 답만
    [[ "${ASSUME_YES}" == 1 ]] && { echo "  (pass --isaac-download to fetch it, or --isaac-zip PATH)"; return 0; }
    if ask_yes_no "Download it now from NVIDIA (~8.7GB)?"; then OPT_ISAAC_DOWNLOAD=1; fi
}

main() {
    parse_args "$@"
    case "${CMD}" in
        status) state_dump; exit 0 ;;
        verify) exec bash "${RESOURCE_DIR}/verify.sh" ;;
        reset)
            confirm_or_abort "Forget the ${COURSE} progress in $(state_file)? (installed files are kept)"
            rm -f "$(state_file)"; echo "install: ${COURSE} progress reset."; exit 0 ;;
    esac
    preflight
    echo "== ROKEY Jazzy installer: ${COURSE} (log: ${LOG_FILE})"
    if [[ "${DRY_RUN}" == 0 ]]; then
        confirm_or_abort "Install the 협동3 (cobot3) lecture environment (apt packages, Isaac Sim, ~/.bashrc block; may ask to reboot)?"
        sudo_prime
    fi
    preflight_isaac
    trap 'echo "[install] failed at line ${LINENO} — see ${LOG_FILE}" >&2' ERR
    plan_cobot3
    echo
    echo "install: cobot3 done. Open a new terminal (or 'source ~/.bashrc'). Re-check anytime: bash install.sh --verify"
}

main "$@"
