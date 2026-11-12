#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_report.sh · 점검 엔진 (lib/report.sh) 단위 테스트

_load() {
    # shellcheck source=../lib/report.sh
    source "${DOCTOR_ROOT}/lib/report.sh"
}

test_check_pass_counts_and_prints_pass() {
    _load
    out="$(check fail "true 는 성공" "안내" true; echo "pass=${COUNT_PASS} fail=${COUNT_FAIL}")"
    assert_contains "${out}" "[PASS] true 는 성공"
    assert_contains "${out}" "pass=1 fail=0"
}

test_check_fail_shows_output_head_and_hint() {
    _load
    DETAIL_LINES=2
    out="$(check fail "깨짐" "sudo dpkg --configure -a" bash -c 'printf "l1\nl2\nl3\n"; exit 1'; echo "fail=${COUNT_FAIL}")"
    assert_contains "${out}" "[FAIL] 깨짐"
    assert_contains "${out}" "| l2"
    assert_not_contains "${out}" "| l3"
    assert_contains "${out}" "→ sudo dpkg --configure -a"
    assert_contains "${out}" "fail=1"
}

test_check_warn_does_not_count_as_fail() {
    _load
    out="$(check warn "디스크" "" false; echo "warn=${COUNT_WARN} fail=${COUNT_FAIL}")"
    assert_contains "${out}" "[WARN] 디스크"
    assert_contains "${out}" "warn=1 fail=0"
    assert_not_contains "${out}" "→"
}

test_check_skip_rc_is_skip_not_fail() {
    _load
    # shellcheck disable=SC2317  # check 가 간접 호출
    probe() { skip_because "docker 그룹 아님"; }
    out="$(check fail "이미지" "안내" probe; echo "skip=${COUNT_SKIP} fail=${COUNT_FAIL}")"
    assert_contains "${out}" "[SKIP] 이미지"
    assert_contains "${out}" "| docker 그룹 아님"
    assert_contains "${out}" "skip=1 fail=0"
    assert_not_contains "${out}" "→ 안내"
}

test_check_timeout_is_fail_with_message() {
    _load
    DOCTOR_TIMEOUT=1
    out="$(check fail "멈춤" "" run_t sleep 5)"
    assert_contains "${out}" "[FAIL] 멈춤"
    assert_contains "${out}" "시간 초과 (1초)"
}

test_report_summary_returns_nonzero_only_on_fail() {
    _load
    check warn "w" "" false >/dev/null
    report_summary >/dev/null
    check fail "f" "" false >/dev/null
    if report_summary >/dev/null; then echo "summary passed despite FAIL"; return 1; fi
}

test_traceback_detail_shows_error_line() {
    _load
    DETAIL_LINES=2
    out="$(check fail "xml" "" python3 -c 'import xml.dom.minidom as m; m.parseString("<a><b></a>")')"
    assert_contains "${out}" "mismatched tag"
}
