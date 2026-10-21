#!/usr/bin/env bash
# tests/test_cli.sh · install.sh 인자 처리 · 종료 코드 · dry-run 단계 목록
#   sudo · 네트워크 · apt 를 쓰지 않는 경로만 실행 (--help / 잘못된 인자 / --dry-run / --status)

_cli() { bash "${INSTALLER_ROOT}/install.sh" "$@"; }

test_help_exits_0_and_describes_cobot3_only() {
    out="$(_cli --help)"
    assert_contains "${out}" "Usage: bash install.sh [options]"
    assert_contains "${out}" "Isaac Sim 5.1.0"
    if grep -qE -- '--no-static-ip|--discovery|--no-reboot' <<<"${out}"; then echo "help lists options of other courses"; return 1; fi
}

test_unknown_option_is_user_error() {
    rc=0; _cli --bogus >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_other_course_names_point_to_their_repos() {
    rc=0; out="$(_cli cobot1 --dry-run 2>&1)" || rc=$?
    assert_eq "${rc}" "1"
    assert_contains "${out}" "https://github.com/ROKEY-SPARK/cobot1_jazzy_installer"
    for c in intel1 int1; do
        rc=0; out="$(_cli "${c}" 2>&1)" || rc=$?
        assert_eq "${rc}" "1"
        assert_contains "${out}" "https://github.com/ROKEY-SPARK/int1_jazzy_installer"
    done
}

test_options_of_other_courses_are_user_errors() {
    for o in --no-static-ip --no-reboot --no-kernel --discovery; do
        rc=0; _cli "${o}" --dry-run >/dev/null 2>&1 || rc=$?
        assert_eq "${rc}" "1" "${o}"
    done
}

test_domain_id_must_be_integer_in_range() {
    rc=0; _cli --domain-id abc --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
    rc=0; _cli --domain-id 999 --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_domain_id_without_value_is_user_error() {
    rc=0; _cli --domain-id --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_missing_isaac_zip_is_user_error() {
    rc=0; _cli --isaac-zip /nonexistent.zip --dry-run >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_dry_run_lists_steps_in_order_and_changes_nothing() {
    out="$(_cli --dry-run --isaac-download)"
    order="$(grep -oE 'would run: [a-z0-9_]+' <<<"${out}" | awk '{print $3}' | tr '\n' ' ')"
    assert_eq "${order}" "kernel_hold no_release_upgrade nvidia_driver xorg ros2_jazzy vscode isaacsim nav2 isaac_ros_ws cobot3_workspace fastdds_profile cobot3_bashrc verify "
    [[ ! -e "${BASHRC}" ]]
    [[ ! -e "${STATE_DIR}/cobot3.state" ]]
}

test_legacy_course_argument_still_works() {
    out="$(_cli cobot3 --dry-run --isaac-download)"
    assert_contains "${out}" "would run: isaac_ros_ws"
}

test_dry_run_passes_isaac_zip_and_pins_driver() {
    touch "${HOME}/isaac.zip"
    out="$(_cli --dry-run --isaac-zip "${HOME}/isaac.zip")"
    assert_contains "${out}" "isaacsim --zip ${HOME}/isaac.zip"
    assert_contains "${out}" "nvidia --open --pin 580.173.02-0ubuntu0.24.04.1 --hold-all"
}

test_dry_run_skip_flags() {
    out="$(_cli --dry-run --no-kernel-hold --no-nvidia --isaac-download --domain-id 12)"
    assert_contains "${out}" "skip: kernel_hold (--no-kernel-hold)"
    assert_contains "${out}" "skip: nvidia_driver (--no-nvidia)"
    assert_contains "${out}" "isaacsim --download"
    assert_contains "${out}" "cobot3_bashrc -> bash"
    assert_contains "${out}" "bashrc 12"
}

test_status_prints_state_file() {
    out="$(_cli --status)"
    assert_contains "${out}" "cobot3.state"
}

test_rerun_skips_steps_recorded_done() {
    mkdir -p "${STATE_DIR}"
    printf 'step_ros2_jazzy=DONE\nstep_nav2=DONE\n' > "${STATE_DIR}/cobot3.state"
    out="$(_cli --dry-run --isaac-download)"
    assert_contains "${out}" "skip: ros2_jazzy (already DONE)"
    assert_contains "${out}" "skip: nav2 (already DONE)"
}
