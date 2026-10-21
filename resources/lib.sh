#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck shell=bash
# resources/lib.sh · source 전용 단계 엔진
#   state 파일 (끊긴 지점부터 재개) + run_step (로그 라우팅) + confirm + sudo 캐시
#   선행 조건 = config.sh 먼저 source / COURSE · STEPS_TOTAL = 호출자 설정

# 종료 코드 규약: 0 성공 / 1 사용자 오류 / 2 시스템 오류
readonly EXIT_USER=1
readonly EXIT_SYSTEM=2

info() { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[warn] $*" >&2; }
die()  { local code="$1"; shift; echo "[error] $*" >&2; exit "${code}"; }

# ============================================================================
# 1) state · 단계 진행 상태 (step_<이름>=DONE|FAIL|SKIPPED|RUNNING)
# ============================================================================

state_file() { echo "${STATE_DIR}/${COURSE:?COURSE not set}.state"; }

_state_ensure() {
    local f
    f="$(state_file)"
    mkdir -p "$(dirname "${f}")"
    [[ -f "${f}" ]] || : > "${f}"
}

state_set() {
    local name="$1" status="$2" f
    _state_ensure
    f="$(state_file)"
    if grep -qE "^step_${name}=" "${f}"; then
        sed -i "s|^step_${name}=.*|step_${name}=${status}|" "${f}"
    else
        echo "step_${name}=${status}" >> "${f}"
    fi
}

# 읽기 함수는 파일을 만들지 않는다 (--dry-run · --status 가 아무것도 바꾸지 않게)
state_get() {
    [[ -f "$(state_file)" ]] || return 0
    sed -n "s|^step_${1}=||p" "$(state_file)" | tail -n1
}

step_is_done() {
    [[ -f "$(state_file)" ]] || return 1
    grep -qE "^step_${1}=(DONE|SKIPPED)$" "$(state_file)"
}

state_dump() {
    echo "--- state: $(state_file) ---"
    if [[ -f "$(state_file)" ]]; then cat "$(state_file)"; else echo "(no progress recorded yet)"; fi
    echo "----------------------------"
}

# ============================================================================
# 2) run_step · 단계 실행 래퍼
# ============================================================================

# 경과 시간 제자리 갱신 → 긴 apt/colcon 동안 멈춘 것처럼 보이지 않게 함
#   부모($$)가 죽으면(Ctrl-C 등) 스스로 끝남 — 비대화형 셸의 백그라운드 작업은 SIGINT 를 무시하므로
_heartbeat() {
    local name="$1" start="${SECONDS}" e
    while kill -0 "$$" 2>/dev/null; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ... %s (%02d:%02d)\033[K' "${name}" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# 명령 실행 + 출력 라우팅 (기본 = 로그 전용 / VERBOSE=1 = 콘솔에도 tee)
_run_logged() {
    local name="$1" interactive="$2"; shift 2
    local rc=0 hb=""
    if [[ "${VERBOSE:-0}" == 1 || "${interactive}" == 1 ]]; then
        # `|| true` 로 묶음 = errexit 해제 → 명령 쪽 종료 코드를 PIPESTATUS 로 회수
        { "$@" 2>&1 | tee -a "${LOG_FILE}"; rc=${PIPESTATUS[0]}; } || true
        return "${rc}"
    fi
    if [[ -t 2 ]]; then _heartbeat "${name}" & hb=$!; fi
    # stdin 차단 = 숨은 대화형 질문이 로그 뒤에서 무한 대기하지 않고 바로 실패
    "$@" >>"${LOG_FILE}" 2>&1 </dev/null || rc=$?
    if [[ -n "${hb}" ]]; then
        kill "${hb}" 2>/dev/null || true
        wait "${hb}" 2>/dev/null || true
        printf '\r\033[K' >&2
    fi
    return "${rc}"
}

# run_step [--always] [--interactive] <n> <name> <cmd...>
#   --always      = state 에 DONE 이어도 다시 실행 (멱등 설정 단계용)
#   --interactive = 사용자 입력을 받는 단계 (heartbeat off, 콘솔 출력)
run_step() {
    local always=0 interactive=0
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --always) always=1 ;;
            --interactive) interactive=1 ;;
            *) die "${EXIT_SYSTEM}" "run_step: unknown flag $1" ;;
        esac
        shift
    done
    local n="$1" name="$2"; shift 2
    [[ $# -gt 0 ]] || die "${EXIT_SYSTEM}" "run_step: no command for '${name}'"
    local total="${STEPS_TOTAL:-?}"

    if [[ "${always}" == 0 ]] && step_is_done "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(state_get "${name}"))"
        return 0
    fi
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
        echo "[${n}/${total}] would run: ${name} -> $*"
        return 0
    fi

    mkdir -p "$(dirname "${LOG_FILE}")"
    { echo; echo "===== [${COURSE}] [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"${LOG_FILE}"
    echo "[${n}/${total}] ${name}"
    state_set "${name}" RUNNING
    local start="${SECONDS}"
    if _run_logged "${name}" "${interactive}" "$@"; then
        state_set "${name}" DONE
        echo "  [OK] ${name} ($(( SECONDS - start ))s)"
    else
        state_set "${name}" FAIL
        echo "  [FAIL] ${name} — detailed log: ${LOG_FILE}" >&2
        exit "${EXIT_SYSTEM}"
    fi
}

# 명령 미실행 + SKIPPED 기록
run_step_skip() {
    local n="$1" name="$2" reason="${3:-}"
    echo "[${n}/${STEPS_TOTAL:-?}] skip: ${name}${reason:+ (${reason})}"
    [[ "${DRY_RUN:-0}" == 1 ]] || state_set "${name}" SKIPPED
}

# ============================================================================
# 3) confirm · 비가역 작업 전 동의 (기본값 N, ASSUME_YES=1 이면 자동 동의)
# ============================================================================

confirm_or_abort() {
    local msg="$1" reply=""
    if [[ "${ASSUME_YES:-0}" == 1 ]]; then
        echo "${msg} (auto-confirmed: --yes)"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        die "${EXIT_USER}" "non-interactive shell needs --yes to confirm: ${msg}"
    fi
    read -r -p "${msg} (y/N): " reply
    [[ "${reply}" =~ ^[yY]$ ]] || { echo "Aborted by user."; exit 0; }
}

# 질문 없이 결과만 돌려줌 (0 = yes). TTY 없으면 기본 no
ask_yes_no() {
    local msg="$1" reply=""
    [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
    [[ -t 0 ]] || return 1
    read -r -p "${msg} (y/N): " reply
    [[ "${reply}" =~ ^[yY]$ ]]
}

# ============================================================================
# 4) sudo · 비밀번호 1회 수령 + 백그라운드 캐시 유지
# ============================================================================

sudo_prime() {
    [[ "${EUID}" -eq 0 ]] && return 0
    # 비밀번호 없는 sudo(NOPASSWD) 면 -v 를 건너뜀 — 다른 sudoers 항목이 있으면 -v 가 비밀번호를 요구함
    sudo -n true 2>/dev/null || sudo -v || die "${EXIT_USER}" "cannot verify sudo privileges — run as a sudo-capable user."
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT
}
