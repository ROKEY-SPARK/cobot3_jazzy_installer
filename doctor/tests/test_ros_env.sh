#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_ros_env.sh · checks/ros_env.sh 단위 테스트 (가짜 HOME 의 ~/.bashrc)

_load() {
    # shellcheck source=../lib/report.sh
    source "${DOCTOR_ROOT}/lib/report.sh"
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    # shellcheck source=../lib/probes.sh
    source "${DOCTOR_ROOT}/lib/probes.sh"
    # shellcheck source=../checks/ros_env.sh
    source "${DOCTOR_ROOT}/checks/ros_env.sh"
}
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "${r}"; }

test_bashrc_single_distro_flags_humble_but_not_comments() {
    _load
    printf 'source /opt/ros/jazzy/setup.bash\n# source /opt/ros/humble/setup.bash\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_single_distro)" "0"
    printf 'source /opt/ros/jazzy/setup.bash\n  source /opt/ros/humble/setup.bash\n' > "${BASHRC}"
    assert_contains "$(bashrc_single_distro || true)" "2:  source /opt/ros/humble/setup.bash"
}

test_bashrc_export_consistent_detects_two_domain_ids() {
    _load
    printf 'export ROS_DOMAIN_ID=10\n#export ROS_DOMAIN_ID=3\nexport ROS_DOMAIN_ID="10"\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_export_consistent ROS_DOMAIN_ID)" "0"
    printf 'export ROS_DOMAIN_ID=10\nexport ROS_DOMAIN_ID=50\n' > "${BASHRC}"
    out="$(bashrc_export_consistent ROS_DOMAIN_ID || true)"
    assert_contains "${out}" "1:export ROS_DOMAIN_ID=10"
    assert_contains "${out}" "2:export ROS_DOMAIN_ID=50"
    : > "${BASHRC}"
    assert_eq "$(rc bashrc_export_consistent ROS_DOMAIN_ID)" "0"
    # 함수 안의 들여쓴 export 는 터미널별 덮어쓰기 → 충돌 아님
    printf 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\nfunction jazzy {\n    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp\n}\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_export_consistent RMW_IMPLEMENTATION)" "0"
}

test_cyclonedds_uri_missing_file_fails_and_home_expands() {
    _load
    mkdir -p "${HOME}/.config/cyclonedds" && touch "${HOME}/.config/cyclonedds/cyclonedds.xml"
    # shellcheck disable=SC2016  # bashrc 에 적힌 글자 그대로
    printf 'export CYCLONEDDS_URI="file://$HOME/.config/cyclonedds/cyclonedds.xml"\n' > "${BASHRC}"
    assert_eq "$(rc cyclonedds_uri_files_exist)" "0"
    printf '    export CYCLONEDDS_URI="file:///nowhere/c.xml"\n' >> "${BASHRC}"
    assert_eq "$(cyclonedds_uri_files_exist || true)" "없음: /nowhere/c.xml"
}

test_bashrc_syntax_error_fails() {
    _load
    printf 'if true; then\n echo x\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_syntax_ok)" "2"
}

test_system_numpy_below_2_rejects_numpy2_on_path() {
    _load
    mkdir -p fakepy/numpy && echo '__version__ = "2.1.0"' > fakepy/numpy/__init__.py
    out="$(PYTHONPATH="${PWD}/fakepy" system_numpy_below_2 || true)"
    assert_contains "${out}" "2.1.0"
    assert_eq "$(PYTHONPATH="${PWD}/fakepy" rc system_numpy_below_2)" "1"
}

test_installer_states_clean_names_bad_file_and_skips_without_records() {
    _load
    assert_eq "$(rc installer_states_clean)" "${RC_SKIP}"
    mkdir -p "${ROKEY_STATE_DIR}"
    printf 'step_isaacsim=FAIL\n' > "${ROKEY_STATE_DIR}/cobot3.state"
    assert_contains "$(installer_states_clean || true)" "cobot3.state: step_isaacsim=FAIL"
}

test_conda_auto_activate_warns_unless_disabled() {
    _load
    printf '# >>> conda initialize >>>\n' > "${BASHRC}"
    assert_eq "$(rc conda_base_not_auto)" "1"
    printf 'auto_activate_base: false\n' > "${HOME}/.condarc"
    assert_eq "$(rc conda_base_not_auto)" "0"
}

test_bashrc_single_distro_flags_mixed_line() {
    _load
    printf 'source /opt/ros/humble/setup.bash; source /opt/ros/jazzy/setup.bash\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_single_distro)" "1"
}

test_bashrc_export_inline_comment_is_not_a_conflict() {
    _load
    printf 'export ROS_DOMAIN_ID=30 # lab\nexport ROS_DOMAIN_ID=30\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_export_consistent ROS_DOMAIN_ID)" "0"
}

test_cyclonedds_uri_with_unknown_variable_is_skip() {
    _load
    printf 'export CYCLONEDDS_URI="file://$XDG_CONFIG_HOME/cyclonedds/c.xml"\n' > "${BASHRC}"
    assert_eq "$(rc cyclonedds_uri_files_exist)" "${RC_SKIP}"
}

test_unreadable_state_file_is_skip_not_pass() {
    _load
    printf 'step_a=FAIL\n' > s && chmod 000 s
    if [[ -r s ]]; then echo "skip: root 로 실행 중이라 읽기 차단을 만들 수 없음"; return 0; fi
    assert_eq "$(rc installer_state_clean s)" "${RC_SKIP}"
}

test_pdf_punctuation_in_bashrc_warns() {
    _load
    printf 'export ROS_DOMAIN_ID=10\n# “주석”은 괜찮음\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_plain_punctuation)" "0"
    printf 'alias sod=\xe2\x80\x98source ~/ws/install/setup.bash\xe2\x80\x99\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_plain_punctuation)" "1"
    printf 'ros2 launch x y \xe2\x80\x93help\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_plain_punctuation)" "1"
}

test_setuptools_80_warns() {
    _load
    mkdir -p fakepy/setuptools && echo '__version__ = "80.9.0"' > fakepy/setuptools/__init__.py
    assert_eq "$(PYTHONPATH="${PWD}/fakepy" rc setuptools_below_80)" "1"
    assert_eq "$(rc setuptools_below_80)" "0"
}
