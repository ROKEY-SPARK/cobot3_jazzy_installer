#!/usr/bin/env bash
# tests/test_templates.sh · 협동3 ~/.bashrc 블록 · FastDDS 프로파일 렌더 결과 검사
#   cobot3.sh 의 bashrc/dds 서브커맨드를 격리된 HOME 에서 실제로 실행한다

_block() { sed -n "/^# >>> rokey $1 >>>\$/,/^# <<< rokey $1 <<<\$/p" "${BASHRC}"; }

test_cobot3_block_defaults_domain_50_and_survives_existing_alias() {
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc >/dev/null
    blk="$(_block cobot3)"
    bash -n <<<"${blk}"
    assert_contains "${blk}" "export ROS_DOMAIN_ID=50"
    assert_contains "${blk}" "alias isaac_python='${HOME}/isaacsim/python.sh'"
    # 기존 alias jazzy 가 있는 셸에서 source 해도 문법 오류 없이 함수로 바뀌어야 한다
    kind="$(bash -c 'shopt -s expand_aliases; alias jazzy="echo old"; alias isaac_ros="echo old"
                     source "$1"; type -t jazzy; type -t isaac_ros' _ "${BASHRC}")"
    assert_eq "${kind}" $'function\nfunction'
}

test_cobot3_isaac_ros_sets_lecture_env_and_bridge_lib_once() {
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc 42 >/dev/null
    out="$(env -u AMENT_PREFIX_PATH -u LD_LIBRARY_PATH bash -c '
        source "$1" >/dev/null; isaac_ros >/dev/null; isaac_ros >/dev/null
        echo "$ROS_DOMAIN_ID|$ROS_DISTRO|$RMW_IMPLEMENTATION|$FASTRTPS_DEFAULT_PROFILES_FILE|$LD_LIBRARY_PATH"' _ "${BASHRC}")"
    assert_eq "${out}" "42|jazzy|rmw_fastrtps_cpp|${HOME}/.ros/fastdds_whitelist.xml|${HOME}/isaacsim/exts/isaacsim.ros2.bridge/jazzy/lib"
}

test_cobot3_fastdds_profile_is_valid_xml_with_optional_whitelist() {
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" dds >/dev/null
    assert_contains "$(cat "${HOME}/.ros/fastdds_whitelist.xml")" "<type>UDPv4</type>"
    FASTDDS_WHITELIST="127.0.0.1,192.168.0.7" bash "${INSTALLER_ROOT}/resources/cobot3.sh" dds >/dev/null
    assert_contains "$(cat "${HOME}/.ros/fastdds_whitelist.xml")" "<address>192.168.0.7</address>"
}

test_cobot3_rerun_without_domain_id_keeps_previous_value() {
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc 61 >/dev/null
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc >/dev/null
    assert_contains "$(_block cobot3)" "export ROS_DOMAIN_ID=61"
}

# 같은 PC 에 다른 강의 설치기의 블록이 있어도 cobot3 블록만 바뀐다
test_cobot3_block_leaves_other_installer_blocks_intact() {
    printf '# >>> rokey cobot1 >>>\nexport ROS_DOMAIN_ID=20\n# <<< rokey cobot1 <<<\n' > "${BASHRC}"
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc >/dev/null
    bash "${INSTALLER_ROOT}/resources/cobot3.sh" bashrc 51 >/dev/null
    assert_eq "$(grep -c '^# >>> rokey ' "${BASHRC}")" "2"
    assert_contains "$(_block cobot1)" "export ROS_DOMAIN_ID=20"
    assert_contains "$(_block cobot3)" "export ROS_DOMAIN_ID=51"
}
