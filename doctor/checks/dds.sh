# shellcheck shell=bash
# shellcheck disable=SC2088  # "~/.bashrc" 는 화면에 보일 문구 (경로 확장 아님)
# checks/dds.sh · 강의 공통 DDS 통신 설정 점검 (PC 사이 토픽이 안 보이거나 남의 토픽이 보이는 원인)
#   선행 = lib/report.sh · lib/pins.sh · lib/probes.sh · checks/ros_env.sh (_bashrc_active · _bashrc_cyclonedds_paths)
#   근거 = 교육 운영팀 오류 대응 매뉴얼 DB (ROS2 통신·네트워크(DDS) 관련 오류)

: "${SYS_NET_DIR:=/sys/class/net}"
: "${UFW_CONF:=/etc/ufw/ufw.conf}"

# 원격 통신을 막는 설정. Jazzy 는 ROS_LOCALHOST_ONLY 대신 ROS_AUTOMATIC_DISCOVERY_RANGE 를 쓴다
discovery_not_localhost_only() {
    local out
    out="$(_bashrc_active | grep -E "export (ROS_LOCALHOST_ONLY=[\"']?1|ROS_AUTOMATIC_DISCOVERY_RANGE=[\"']?(LOCALHOST|OFF))([^0-9A-Za-z_]|$)")"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

# ROS_DOMAIN_ID 미설정 · 0 = 같은 강의실의 다른 조와 같은 도메인 → 남의 토픽 · "dsr_controller 이미 실행 중"
#   들여쓴 export (협동3 isaac_ros/jazzy 함수) 도 설정으로 본다. 변수로 읽는 값은 0 이 아니라고 본다
domain_id_assigned() {
    local lines values
    lines="$(_bashrc_active | grep -E "^[0-9]+:\s*export ROS_DOMAIN_ID=")"
    [[ -n "${lines}" ]] || { echo "~/.bashrc 에 ROS_DOMAIN_ID 없음 → 기본값 0"; return 1; }
    values="$(sed -E 's/^[0-9]+:\s*export ROS_DOMAIN_ID=//; s/\s+#.*$//; s/["'\'' ]//g' <<<"${lines}" | sort -u)"
    grep -qvx '0' <<<"${values}" || { echo "ROS_DOMAIN_ID=0 (기본값과 같음)"; return 1; }
}

# Discovery Server 는 Fast DDS 전용 → 최상위 RMW 가 CycloneDDS 면 서버 설정이 무시됨
discovery_server_matches_rmw() {
    local ds rmw
    ds="$(_bashrc_active | grep -E '^[0-9]+:export ROS_DISCOVERY_SERVER=')"
    [[ -n "${ds}" ]] || return 0
    rmw="$(_bashrc_active | grep -E '^[0-9]+:export RMW_IMPLEMENTATION=' | tail -n1)"
    [[ "${rmw}" != *rmw_cyclonedds_cpp* ]] || { echo "${ds}"; echo "${rmw}"; return 1; }
}

# CycloneDDS XML 의 NetworkInterface name 이 실제 NIC 에 있음
#   presence_required="false" 면 이름이 틀려도 오류 없이 기동하고 통신만 조용히 실패한다
#   USB 랜카드를 뺀 노트북처럼 일부러 비워 둔 경우도 있어 warn
cyclonedds_interfaces_exist() {
    local f files=() bad=0 name
    [[ -f "${CYCLONEDDS_XML}" ]] && files+=("${CYCLONEDDS_XML}")
    while IFS= read -r f; do
        [[ -f "${f}" && "${f}" != "${CYCLONEDDS_XML}" ]] && files+=("${f}")
    done < <(_bashrc_cyclonedds_paths)
    [[ ${#files[@]} -gt 0 ]] || { skip_because "CycloneDDS XML 없음"; return; }
    for f in "${files[@]}"; do
        while IFS= read -r name; do
            # CycloneDDS 는 속성 안의 ${VAR} 를 펼친다 → 글자만으로는 이름을 알 수 없음
            [[ "${name}" != *'$'* ]] || continue
            [[ -e "${SYS_NET_DIR}/${name}" ]] || { echo "${f}: 없는 인터페이스 '${name}'"; bad=1; }
        done < <(run_t "${SYSTEM_PYTHON}" -c '
import sys, xml.dom.minidom as m
try:
    doc = m.parse(sys.argv[1])
except Exception:
    sys.exit(0)  # 파싱 오류는 cyclonedds.xml 점검이 따로 본다
for el in doc.getElementsByTagName("NetworkInterface"):
    if el.getAttribute("name"):
        print(el.getAttribute("name"))' "${f}")
    done
    return "${bad}"
}

# 방화벽이 켜져 있으면 DDS UDP (7400 + 250 × ROS_DOMAIN_ID 부근) 가 막힐 수 있음. 규칙은 root 만 읽힘
firewall_off() {
    [[ -r "${UFW_CONF}" ]] || { skip_because "${UFW_CONF} 없음"; return; }
    ! grep -qx 'ENABLED=yes' "${UFW_CONF}" || { echo "ufw ENABLED=yes"; return 1; }
}

check_dds() {
    section "공통 · DDS 통신"
    check warn "원격 탐색 허용 (LOCALHOST 전용 아님)" "~/.bashrc 의 표시된 줄 삭제 (Jazzy = ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET)" discovery_not_localhost_only
    check warn "ROS_DOMAIN_ID 조별 번호 설정 (0 아님)" "~/.bashrc 에 export ROS_DOMAIN_ID=<조별 번호>, 같은 조 장비는 같은 번호" domain_id_assigned
    check fail "Discovery Server 와 RMW 일치 (Fast DDS)" "Discovery Server 를 쓰면 RMW_IMPLEMENTATION=rmw_fastrtps_cpp, 아니면 ROS_DISCOVERY_SERVER 줄 삭제" discovery_server_matches_rmw
    check warn "CycloneDDS XML 인터페이스 이름 실재" "ip -4 addr show 로 실제 이름 확인 후 XML 의 NetworkInterface name 수정" cyclonedds_interfaces_exist
    check warn "방화벽 (ufw) 꺼짐" "sudo ufw status 로 DDS UDP 포트 허용 확인 (수업 중 임시: sudo ufw disable)" firewall_off
}
