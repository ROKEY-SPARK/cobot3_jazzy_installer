#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # 설정값은 source 한 코드가 읽음
# tests/test_dds.sh · checks/dds.sh 단위 테스트 (가짜 HOME 의 ~/.bashrc · 가짜 NIC 목록)

_load() {
    # shellcheck source=../doctor.sh
    source "${DOCTOR_ROOT}/doctor.sh"
}
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "${r}"; }

test_localhost_only_flags_jazzy_and_legacy_variables() {
    _load
    printf 'export ROS_LOCALHOST_ONLY=0\n# export ROS_LOCALHOST_ONLY=1\n' > "${BASHRC}"
    assert_eq "$(rc discovery_not_localhost_only)" "0"
    printf 'export ROS_LOCALHOST_ONLY=1\n' > "${BASHRC}"
    assert_eq "$(rc discovery_not_localhost_only)" "1"
    printf 'export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST\n' > "${BASHRC}"
    assert_eq "$(rc discovery_not_localhost_only)" "1"
}

test_domain_id_missing_or_zero_warns_and_function_scope_counts() {
    _load
    : > "${BASHRC}"
    assert_contains "$(domain_id_assigned || true)" "기본값 0"
    printf 'export ROS_DOMAIN_ID=0\n' > "${BASHRC}"
    assert_eq "$(rc domain_id_assigned)" "1"
    printf 'function jazzy {\n    export ROS_DOMAIN_ID=50\n}\n' > "${BASHRC}"
    assert_eq "$(rc domain_id_assigned)" "0"
}

test_discovery_server_with_cyclonedds_fails() {
    _load
    printf 'export ROS_DISCOVERY_SERVER=172.24.3.241:11811\nexport RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\n' > "${BASHRC}"
    assert_eq "$(rc discovery_server_matches_rmw)" "1"
    printf 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\nexport ROS_DISCOVERY_SERVER=x:11811\nexport RMW_IMPLEMENTATION=rmw_fastrtps_cpp\n' > "${BASHRC}"
    assert_eq "$(rc discovery_server_matches_rmw)" "0"
    printf 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp\n' > "${BASHRC}"
    assert_eq "$(rc discovery_server_matches_rmw)" "0"
}

test_cyclonedds_missing_interface_name_fails() {
    _load
    SYS_NET_DIR="${PWD}/net"; mkdir -p net/lo net/wlp5s0
    printf 'export CYCLONEDDS_URI=file://$HOME/peers.xml\n' > "${BASHRC}"
    printf '<CycloneDDS><Domain><General><Interfaces><NetworkInterface name="wlo1" presence_required="false"/><NetworkInterface name="lo"/></Interfaces></General></Domain></CycloneDDS>\n' > "${HOME}/peers.xml"
    assert_eq "$(cyclonedds_interfaces_exist || true)" "${HOME}/peers.xml: 없는 인터페이스 'wlo1'"
    sed -i 's/wlo1/wlp5s0/' "${HOME}/peers.xml"
    assert_eq "$(rc cyclonedds_interfaces_exist)" "0"
}

test_cyclonedds_interfaces_skip_without_xml() {
    _load
    : > "${BASHRC}"
    assert_eq "$(rc cyclonedds_interfaces_exist)" "${RC_SKIP}"
}

test_firewall_enabled_warns() {
    _load
    UFW_CONF="${PWD}/ufw.conf"
    printf 'ENABLED=no\n' > ufw.conf
    assert_eq "$(rc firewall_off)" "0"
    printf 'ENABLED=yes\n' > ufw.conf
    assert_eq "$(rc firewall_off)" "1"
}

test_localhost_only_does_not_match_ten() {
    _load
    printf 'export ROS_LOCALHOST_ONLY=10\n' > "${BASHRC}"
    assert_eq "$(rc discovery_not_localhost_only)" "0"
}

test_cyclonedds_interface_with_variable_is_not_judged() {
    _load
    SYS_NET_DIR="${PWD}/net"; mkdir -p net/lo
    printf '<CycloneDDS><NetworkInterface name="${ETH}"/><NetworkInterface name="lo"/></CycloneDDS>\n' > "${CYCLONEDDS_XML_TEST:=${PWD}/c.xml}"
    printf 'export CYCLONEDDS_URI=file://%s\n' "${CYCLONEDDS_XML_TEST}" > "${BASHRC}"
    assert_eq "$(rc cyclonedds_interfaces_exist)" "0"
}
