#!/usr/bin/env bash
# tests/test_lib.sh · lib.sh / sys.sh 단위 테스트 (run.sh 가 함수별 격리 실행)
# shellcheck disable=SC2034  # COURSE 등은 source 된 라이브러리가 읽는다

_load() {
    # shellcheck source=../resources/config.sh
    source "${INSTALLER_ROOT}/resources/config.sh"
    # shellcheck source=../resources/lib.sh
    source "${INSTALLER_ROOT}/resources/lib.sh"
    # shellcheck source=../resources/sys.sh
    source "${INSTALLER_ROOT}/resources/sys.sh"
    COURSE=testcourse
    STEPS_TOTAL=3
}

test_state_set_get_overwrites_single_line() {
    _load
    state_set foo RUNNING
    state_set foo DONE
    assert_eq "$(state_get foo)" "DONE"
    assert_eq "$(grep -c '^step_foo=' "$(state_file)")" "1"
}

test_step_is_done_only_for_done_or_skipped() {
    _load
    state_set a DONE; state_set b SKIPPED; state_set c FAIL
    step_is_done a
    step_is_done b
    # `! cmd` 는 errexit 를 일으키지 않으므로 if 로 명시 판정
    if step_is_done c; then echo "FAIL counted as done"; return 1; fi
    if step_is_done missing; then echo "missing counted as done"; return 1; fi
}

test_run_step_records_done_and_skips_rerun() {
    _load
    run_step 1 touch_marker touch "${HOME}/marker" >/dev/null
    assert_eq "$(state_get touch_marker)" "DONE"
    rm "${HOME}/marker"
    out="$(run_step 1 touch_marker touch "${HOME}/marker")"
    assert_contains "${out}" "skip: touch_marker"
    [[ ! -e "${HOME}/marker" ]]
}

test_run_step_always_reruns() {
    _load
    run_step --always 1 cnt bash -c "echo x >> '${HOME}/cnt'" >/dev/null
    run_step --always 1 cnt bash -c "echo x >> '${HOME}/cnt'" >/dev/null
    assert_eq "$(wc -l < "${HOME}/cnt")" "2"
}

test_run_step_failure_exits_2_and_records_fail() {
    _load
    rc=0
    ( run_step 2 broken false ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_eq "$(state_get broken)" "FAIL"
}

test_run_step_dry_run_does_not_execute() {
    _load
    DRY_RUN=1
    out="$(run_step 1 nope touch "${HOME}/should_not_exist")"
    assert_contains "${out}" "would run: nope"
    [[ ! -e "${HOME}/should_not_exist" ]]
    assert_eq "$(state_get nope)" ""
}

test_run_step_logs_output_to_log_file() {
    _load
    run_step 1 say echo hello-log >/dev/null
    assert_contains "$(cat "${LOG_FILE}")" "hello-log"
}

test_run_step_verbose_propagates_failure() {
    _load
    VERBOSE=1
    rc=0
    ( run_step 1 vfail bash -c 'echo boom; exit 3' ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_eq "$(state_get vfail)" "FAIL"
}

test_confirm_assume_yes_passes_without_tty() {
    _load
    ASSUME_YES=1
    out="$(confirm_or_abort "do it?" </dev/null)"
    assert_contains "${out}" "auto-confirmed"
}

test_confirm_without_tty_exits_user_error() {
    _load
    rc=0
    ( confirm_or_abort "do it?" </dev/null ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_bashrc_block_is_idempotent_and_replaces() {
    _load
    printf 'line-before\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c1"
    printf 'export A=2\n' > "${HOME}/c2"
    bashrc_block_write cobot3 "${HOME}/c1"
    bashrc_block_write cobot3 "${HOME}/c1"
    assert_eq "$(grep -c '^# >>> rokey cobot3 >>>$' "${BASHRC}")" "1"
    bashrc_block_write cobot3 "${HOME}/c2"
    assert_eq "$(grep -c 'export A=' "${BASHRC}")" "1"
    assert_contains "$(cat "${BASHRC}")" "export A=2"
    assert_contains "$(cat "${BASHRC}")" "line-before"
}

test_bashrc_blocks_of_other_courses_survive() {
    _load
    printf 'X=1\n' > "${HOME}/c"
    bashrc_block_write cobot3 "${HOME}/c"
    bashrc_block_write other "${HOME}/c"
    bashrc_block_remove cobot3
    assert_eq "$(grep -c '^# >>> rokey other >>>$' "${BASHRC}")" "1"
    assert_eq "$(grep -c 'rokey cobot3' "${BASHRC}")" "0"
}

test_render_template_replaces_and_keeps_ampersand() {
    _load
    printf 'a=__A__\nb=__B__\n' > "${HOME}/t.in"
    render_template "${HOME}/t.in" "${HOME}/out/t" "A=x&y" "B=/p/q"
    assert_eq "$(cat "${HOME}/out/t")" $'a=x&y\nb=/p/q'
}

test_render_template_fails_on_unresolved_placeholder() {
    _load
    printf 'a=__MISSING__\n' > "${HOME}/t.in"
    rc=0
    ( render_template "${HOME}/t.in" "${HOME}/t" ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
}

test_git_clone_pinned_checks_out_ref_and_respects_local_changes() {
    _load
    git init -q "${HOME}/up"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    first="$(git -C "${HOME}/up" rev-parse HEAD)"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
    git_clone_pinned "${HOME}/up" "${HOME}/clone" "${first}" >/dev/null
    assert_eq "$(git -C "${HOME}/clone" rev-parse HEAD)" "${first}"
    # 재실행 = 그대로 유지 (멱등)
    git_clone_pinned "${HOME}/up" "${HOME}/clone" "${first}" >/dev/null
    assert_eq "$(git -C "${HOME}/clone" rev-parse HEAD)" "${first}"
}

test_git_clone_pinned_refuses_non_repo_dir() {
    _load
    mkdir -p "${HOME}/notrepo" && touch "${HOME}/notrepo/student_code.py"
    rc=0
    ( git_clone_pinned "${HOME}/up" "${HOME}/notrepo" main ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_bashrc_block_missing_end_marker_does_not_truncate() {
    _load
    printf 'keep-1\n# >>> rokey cobot3 >>>\nexport X=1\nkeep-2\nkeep-3\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    rc=0
    ( bashrc_block_write cobot3 "${HOME}/c" ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_contains "$(cat "${BASHRC}")" "keep-3"
}

test_bashrc_block_appends_on_new_line_when_file_lacks_trailing_newline() {
    _load
    printf 'export OLD=1' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    bashrc_block_write cobot3 "${HOME}/c"
    bashrc_block_write cobot3 "${HOME}/c"
    # 마커가 줄 중간에 붙으면 매칭 실패 → 블록이 쌓인다. 줄 위치까지 정확히 본다
    assert_eq "$(grep -c 'rokey cobot3 >>>' "${BASHRC}")" "1"
    assert_eq "$(sed -n 1p "${BASHRC}")" "export OLD=1"
    assert_eq "$(sed -n 2p "${BASHRC}")" "# >>> rokey cobot3 >>>"
}

test_bashrc_block_keeps_backup_of_original() {
    _load
    printf 'original\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    bashrc_block_write cobot3 "${HOME}/c"
    assert_eq "$(cat "${BASHRC}.rokey.bak")" "original"
}

test_bashrc_block_get_reads_value_inside_block_only() {
    _load
    printf 'export ROS_DOMAIN_ID=99\n' > "${BASHRC}"
    printf 'export ROS_DOMAIN_ID=12\n' > "${HOME}/c"
    bashrc_block_write cobot3 "${HOME}/c"
    assert_eq "$(bashrc_block_domain_id cobot3)" "12"
    assert_eq "$(bashrc_block_domain_id other)" ""
}

test_state_reads_do_not_create_files() {
    _load
    step_is_done anything || true
    state_get anything >/dev/null
    [[ ! -e "${STATE_DIR}" ]]
}

test_git_clone_pinned_accepts_empty_existing_dir() {
    _load
    git init -q "${HOME}/up"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    mkdir -p "${HOME}/empty"
    git_clone_pinned "${HOME}/up" "${HOME}/empty" HEAD >/dev/null
    [[ -d "${HOME}/empty/.git" ]]
}
