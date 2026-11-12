#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_courses.sh · checks/cobot2.sh · cobot3.sh 판정 함수 (가짜 HOME 워크스페이스)

_load() {
    # shellcheck source=../doctor.sh
    source "${DOCTOR_ROOT}/doctor.sh"
}
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "${r}"; }

test_wakeword_models_detects_html_saved_as_tflite() {
    _load
    local d="${DSR_WORKSPACE}/install/voice_processing/share/voice_processing/resource"
    assert_contains "$(wakeword_models_valid || true)" "colcon build 필요"
    mkdir -p "${d}"
    printf '\x1c\x00\x00\x00TFL3rest' > "${d}/good.tflite"
    assert_eq "$(rc wakeword_models_valid)" "0"
    printf '<html>504 Gateway</html>' > "${d}/bad.tflite"
    assert_eq "$(wakeword_models_valid || true)" "손상: ${d}/bad.tflite"
}

test_m0609_symlink_rejects_real_dir_and_dangling_link() {
    _load
    local l="${DSR_WORKSPACE}/src/m0609_rg2_bringup"
    mkdir -p "${l}"
    assert_contains "$(m0609_symlink_ok || true)" "심볼릭 링크 아님"
    rmdir "${l}" && ln -s "${HOME}/nowhere" "${l}"
    assert_contains "$(m0609_symlink_ok || true)" "깨진 링크"
    mkdir -p "${HOME}/pkg" && ln -sfn "${HOME}/pkg" "${l}"
    assert_eq "$(rc m0609_symlink_ok)" "0"
}

test_yolo_image_matches_any_registry_prefix() {
    _load
    stub docker 'case "$1" in images) printf "rokey/jazzy-base:latest\nmyhub/ros2-jazzy-yolo:dev-builder\n";; *) exit 0;; esac'
    assert_eq "$(rc yolo_image_present)" "0"
    stub docker 'case "$1" in images) printf "local/ros2-jazzy-yolo:old\n";; *) exit 0;; esac'
    assert_eq "$(rc yolo_image_present)" "1"
}

test_session_is_x11_skips_outside_graphical_session() {
    _load
    XDG_SESSION_TYPE='tty';     assert_eq "$(rc session_is_x11)" "${RC_SKIP}"
    XDG_SESSION_TYPE=wayland; assert_eq "$(rc session_is_x11)" "1"
    XDG_SESSION_TYPE=x11;     assert_eq "$(rc session_is_x11)" "0"
}

test_cobot_laptop_base_runs_once_for_cobot1_and_cobot2() {
    _load
    SKIP_HOST=1; SKIP_DOCKER=1
    out="$(check_cobot_laptop; check_cobot_laptop)"
    assert_eq "$(grep -c '노트북 base' <<<"${out}")" "1"
}

test_cobot3_ws_unique_checks_both_workspaces() {
    _load
    mkdir -p "${COBOT3_WS}/src/a" "${COBOT3_WS}/src/b"
    printf '<package><name>dup</name></package>\n' | tee "${COBOT3_WS}/src/a/package.xml" > "${COBOT3_WS}/src/b/package.xml"
    assert_contains "$(cobot3_ws_unique || true)" "${COBOT3_WS}: dup:"
    rm -r "${COBOT3_WS}/src/b"
    assert_eq "$(rc cobot3_ws_unique)" "0"
    rm -r "${COBOT3_WS}"
    assert_eq "$(rc cobot3_ws_unique)" "${RC_SKIP}"
}

test_robot_lan_default_route_warns_only_with_gateway() {
    _load
    _nmcli_stub() {
        stub nmcli "case \"\$*\" in
  '-g UUID con show') echo u-1;;
  *'ipv4.addresses con show uuid u-1') echo '192.168.1.30/24';;
  *'ipv4.gateway con show uuid u-1') echo '$1';;
  *'ipv4.never-default con show uuid u-1') echo '$2';;
  *'connection.id con show uuid u-1') echo 'a:b';;
esac"
    }
    _nmcli_stub 192.168.1.1 no
    assert_contains "$(robot_lan_not_default_route || true)" "a:b: gateway=192.168.1.1 never-default=no"
    _nmcli_stub "" no
    assert_eq "$(rc robot_lan_not_default_route)" "0"
    _nmcli_stub 192.168.1.1 yes
    assert_eq "$(rc robot_lan_not_default_route)" "0"
    assert_eq "$(rc static_ip_configured)" "0"
}

test_cobot_laptop_checks_libpoco_dev_by_exact_name() {
    _load
    SKIP_HOST=1; SKIP_DOCKER=1
    stub dpkg-query 'case "${@: -1}" in libpoco-dev) exit 1;; *) printf "ii ";; esac'
    out="$(check_cobot_laptop)"
    assert_contains "${out}" "[FAIL] DSR 빌드 의존 (libpoco-dev · libyaml-cpp-dev)"
    assert_contains "${out}" "미설치: libpoco-dev"
}

test_cobot2_pyserial_is_warn_level() {
    _load
    SKIP_GPU=1; SKIP_DOCKER=1; COBOT_LAPTOP_DONE=1
    SYSTEM_PYTHON="${STUB_BIN}/py"
    stub py 'case "$*" in *"import serial"*) echo "ModuleNotFoundError: No module named serial"; exit 1;; *) exit 0;; esac'
    out="$(check_cobot2)"
    assert_contains "${out}" "[WARN] pyserial (No module named 'serial' 예방)"
    assert_contains "${out}" "→ sudo apt install python3-serial"
}

test_cobot3_bridge_lib_path_matches_isaac_sim_5_1_layout() {
    _load
    SKIP_GPU=1; SKIP_HOST=1
    mkdir -p "${ISAACSIM_DIR}/exts/isaacsim.ros2.bridge/jazzy/lib"
    out="$(check_cobot3)"
    assert_contains "${out}" "[PASS] Isaac Sim 내장 ROS 2 라이브러리 (ros2 bridge)"
    rm -r "${ISAACSIM_DIR}/exts"
    assert_contains "$(check_cobot3)" "없음: ${ISAACSIM_DIR}/exts/isaacsim.ros2.bridge/jazzy/lib"
}
