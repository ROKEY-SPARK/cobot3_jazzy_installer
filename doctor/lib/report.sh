# shellcheck shell=bash
# lib/report.sh · source 전용 점검 엔진
#   check 하나 = 명령 하나 실행 → PASS / WARN / FAIL / SKIP 한 줄
#   명령 종료 코드 규약: 0 = 정상 / RC_SKIP = 판정 불가 (권한·하드웨어 없음) / 그 외 = 문제
#   점검은 시스템을 바꾸지 않는다 → 이 파일에도 sudo · 쓰기 명령이 없다

readonly RC_SKIP=3
# timeout(1) 이 명령을 끊었을 때의 종료 코드
readonly RC_TIMEOUT=124
# FAIL · WARN · SKIP 아래에 보여 줄 명령 출력 줄 수
: "${DETAIL_LINES:=4}"
: "${DOCTOR_TIMEOUT:=30}"

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_SKIP=0

section() { printf '\n== %s\n' "$*"; }

# skip_because <이유> · 점검 함수 안에서 "판정 불가" 로 끝낼 때
#   반환만 할 뿐 호출 함수를 끝내지 않는다 → `|| { skip_because "..."; return; }` 로 쓴다
skip_because() { echo "$*"; return "${RC_SKIP}"; }

# run_t <명령...> · 멈출 수 있는 외부 명령 (docker · nvidia-smi · ros2) 에 시간 상한
run_t() { timeout "${DOCTOR_TIMEOUT}" "$@"; }

# python traceback 은 마지막 줄이 오류 이름 → 끝부분을, 그 외는 앞부분을 보여 준다
_print_detail() {
    [[ -n "$1" ]] || return 0
    local cut='head'
    grep -q '^Traceback (most recent call last)' <<<"$1" && cut='tail'
    "${cut}" -n "${DETAIL_LINES}" <<<"$1" | sed 's/^/         | /'
}

# check <fail|warn> <설명> <복구 안내> <명령...>
#   fail = 문제가 있으면 FAIL (종료 코드에 반영) / warn = WARN (종료 코드에 반영 안 함)
#   복구 안내가 빈 문자열이면 안내 줄을 찍지 않는다
check() {
    local level="$1" desc="$2" hint="$3"; shift 3
    local out rc
    # `|| rc=$?` = 호출자가 set -e 여도 실패한 명령이 셸을 끝내지 않게 한다
    rc=0
    out="$("$@" 2>&1)" || rc=$?
    if [[ ${rc} -eq 0 ]]; then
        COUNT_PASS=$((COUNT_PASS + 1)); echo "  [PASS] ${desc}"; return 0
    fi
    if [[ ${rc} -eq ${RC_SKIP} ]]; then
        COUNT_SKIP=$((COUNT_SKIP + 1)); echo "  [SKIP] ${desc}"; _print_detail "${out}"; return 0
    fi
    [[ ${rc} -eq ${RC_TIMEOUT} ]] && out="시간 초과 (${DOCTOR_TIMEOUT}초) — 명령이 응답하지 않음"$'\n'"${out}"
    if [[ "${level}" == warn ]]; then
        COUNT_WARN=$((COUNT_WARN + 1)); echo "  [WARN] ${desc}"
    else
        COUNT_FAIL=$((COUNT_FAIL + 1)); echo "  [FAIL] ${desc}"
    fi
    _print_detail "${out}"
    [[ -z "${hint}" ]] || echo "         → ${hint}"
    return 0
}

# report_summary · 집계 한 줄. FAIL 이 있으면 1 반환 (호출자가 종료 코드로 바꾼다)
report_summary() {
    printf '\n---- PASS %d · WARN %d · FAIL %d · SKIP %d\n' \
        "${COUNT_PASS}" "${COUNT_WARN}" "${COUNT_FAIL}" "${COUNT_SKIP}"
    [[ ${COUNT_FAIL} -eq 0 ]]
}
