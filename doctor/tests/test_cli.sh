#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_cli.sh · doctor.sh 인자 처리 · 강의 자동 감지

_load() {
    # shellcheck source=../doctor.sh
    source "${DOCTOR_ROOT}/doctor.sh"
}

test_unknown_argument_exits_1_on_stderr() {
    local rc=0 out err
    out="$(bash "${DOCTOR_ROOT}/doctor.sh" cobot9 2>err)" || rc=$?
    err="$(cat err)"
    assert_eq "${rc}" "1"
    assert_eq "${out}" ""
    assert_contains "${err}" "알 수 없는 인자 'cobot9'"
}

test_help_lists_every_course_and_flag() {
    out="$(bash "${DOCTOR_ROOT}/doctor.sh" --help)"
    for word in cobot1 cobot2 cobot3 intel1 --no-host --no-gpu --no-docker --no-isaac "종료 코드"; do
        assert_contains "${out}" "${word}"
    done
}

test_detect_courses_none_on_clean_home() {
    _load
    assert_eq "$(detect_courses)" ""
}

test_detect_courses_from_state_marker_and_workspace() {
    _load
    mkdir -p "${ROKEY_STATE_DIR}" && touch "${ROKEY_STATE_DIR}/intel1.state"
    echo "${COBOT2_ENV_MARKER}" > "${BASHRC}"
    mkdir -p "${COBOT1_WS}/src"
    assert_eq "$(detect_courses | tr '\n' ' ')" "cobot1 cobot2 intel1 "
}

test_detect_courses_survives_installer_reset() {
    _load
    # --reset 은 state 만 지운다 → bashrc 블록만 남아도 감지
    printf '# >>> rokey cobot3 >>>\nx\n# <<< rokey cobot3 <<<\n' > "${BASHRC}"
    assert_eq "$(detect_courses)" "cobot3"
}

test_gpu_driver_level_is_warn_for_cobot1_only() {
    _load
    assert_eq "$(gpu_driver_level cobot1)" "warn"
    assert_eq "$(gpu_driver_level)" "warn"
    assert_eq "$(gpu_driver_level cobot1 cobot2)" "fail"
    assert_eq "$(gpu_driver_level intel1)" "fail"
}

test_duplicate_course_argument_runs_once() {
    _load
    check_system() { :; }
    check_ros_env() { :; }
    check_dds() { :; }
    # shellcheck disable=SC2317  # main 이 간접 호출
    check_cobot3() { echo "RAN_COBOT3"; }
    out="$(main cobot3 cobot3 2>&1 || true)"
    assert_eq "$(grep -c RAN_COBOT3 <<<"${out}")" "1"
}
