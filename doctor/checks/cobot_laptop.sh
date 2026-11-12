# shellcheck shell=bash
# checks/cobot_laptop.sh · 협동1 · 협동2 공통 노트북 base (협동2 install.sh 9단계 기준)
#   협동1 · 협동2 를 함께 점검해도 한 번만 실행 (COBOT_LAPTOP_DONE)

: "${SKIP_DOCKER:=0}"
COBOT_LAPTOP_DONE=0

sysctl_rmem_applied() {
    local v
    v="$(sysctl -n net.core.rmem_max 2>/dev/null)" || { skip_because "sysctl 읽기 실패"; return; }
    [[ "${v}" -ge "${SYSCTL_RMEM_MAX}" ]] || { echo "net.core.rmem_max=${v} (기준 ${SYSCTL_RMEM_MAX})"; return 1; }
}

# 로봇 LAN 주소를 가진 NetworkManager 프로필 UUID (이름은 ':' 가 escape 되어 조회가 틀어질 수 있음)
#   주소 여러 개 = "," 구분 (가정 · 실제 PC 에서 미확인)
_robot_lan_profiles() {
    local uuid addrs
    while IFS= read -r uuid; do
        addrs="$(run_t nmcli -g ipv4.addresses con show uuid "${uuid}" 2>/dev/null)"
        addrs="${addrs//,/$'\n'}"
        grep -qxF "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" <<<"${addrs// /}" && echo "${uuid}"
    done < <(run_t nmcli -g UUID con show 2>/dev/null)
}

static_ip_configured() {
    command -v nmcli >/dev/null || { skip_because "nmcli 없음"; return; }
    [[ -n "$(_robot_lan_profiles)" ]] || { echo "${HOST_ETH_IP}/${HOST_ETH_PREFIX} 를 가진 연결 프로필 없음"; return 1; }
}

# 로봇 LAN 프로필에 gateway 가 있고 never-default 가 꺼져 있으면 기본 경로를 가져가 wifi 인터넷이 끊긴다
#   gateway 가 비어 있으면 기본 경로가 생기지 않는다 (프로필 설정을 읽을 뿐 ip route 는 보지 않음)
robot_lan_not_default_route() {
    command -v nmcli >/dev/null || { skip_because "nmcli 없음"; return; }
    local uuid gw nd bad=0 found=0
    while IFS= read -r uuid; do
        found=1
        gw="$(run_t nmcli -g ipv4.gateway con show uuid "${uuid}" 2>/dev/null)"
        nd="$(run_t nmcli -g ipv4.never-default con show uuid "${uuid}" 2>/dev/null)"
        [[ -n "${gw}" && "${nd}" != yes ]] || continue
        echo "$(run_t nmcli -g connection.id con show uuid "${uuid}" 2>/dev/null): gateway=${gw} never-default=${nd}"
        bad=1
    done < <(_robot_lan_profiles)
    [[ ${found} == 1 ]] || { skip_because "로봇 LAN 프로필 없음 (위 항목 참고)"; return; }
    return "${bad}"
}

check_cobot_laptop() {
    [[ "${COBOT_LAPTOP_DONE}" == 0 ]] || return 0
    COBOT_LAPTOP_DONE=1
    section "협동1 · 협동2 노트북 base"
    local ros="ros-${ROS_DISTRO}"
    if [[ "${SKIP_HOST}" == 0 ]]; then
        check fail "HWE 커널 meta ${KERNEL_META}" "설치기 커널 단계 재실행" pkg_installed "${KERNEL_META}"
        check fail "sysctl 60-cyclonedds.conf" "설치기 DDS 단계 재실행" path_exists /etc/sysctl.d/60-cyclonedds.conf
        check fail "소켓 버퍼 적용 (큰 토픽 0 Hz 예방)" "sudo sysctl --system" sysctl_rmem_applied
        check fail "로봇 LAN ${HOST_ETH_IP}/${HOST_ETH_PREFIX} 프로필" "유선 NIC 연결 후 설치기 network 단계 재실행" static_ip_configured
        check warn "로봇 LAN 프로필이 기본 경로를 가져가지 않음 (wifi 인터넷 유지)" "nmcli con mod <프로필> ipv4.gateway '' ipv4.never-default yes" robot_lan_not_default_route
    fi
    check fail "ros2_control · controllers · ros_gz" "설치기 ROS extras 단계 재실행" \
        pkg_installed "${ros}-ros2-control" "${ros}-ros2-controllers" "${ros}-ros-gz" "${ros}-xacro"
    check fail "DSR 빌드 의존 (libpoco-dev · libyaml-cpp-dev)" "sudo apt install libpoco-dev libyaml-cpp-dev" \
        pkg_installed libpoco-dev libyaml-cpp-dev
    check fail "CycloneDDS RMW" "sudo apt install ${ros}-rmw-cyclonedds-cpp" pkg_installed "${ros}-rmw-cyclonedds-cpp"
    check fail "cyclonedds.xml (${CYCLONEDDS_XML})" "설치기 DDS 단계 재실행" xml_valid "${CYCLONEDDS_XML}"
    if [[ "${SKIP_DOCKER}" == 0 ]]; then
        # shellcheck disable=SC2086  # 공백 구분 목록을 인자로 펼침
        check fail "docker 엔진 설치 · 버전 hold" "설치기 docker 단계 재실행" pkg_held ${DOCKER_HELD_PKGS}
        check fail "DSR 에뮬레이터 이미지 ${DSR_EMULATOR_IMAGE}" "docker pull ${DSR_EMULATOR_IMAGE}" docker_image_present "${DSR_EMULATOR_IMAGE}"
    fi
}
