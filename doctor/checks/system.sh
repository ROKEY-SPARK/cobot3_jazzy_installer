# shellcheck shell=bash
# checks/system.sh · 강의 공통 시스템 점검 (OS · 디스크 · apt/dpkg · 커널 · NVIDIA · 시간 · docker)
#   선행 = lib/report.sh · lib/pins.sh · lib/probes.sh
#   SKIP_HOST=1 = 컨테이너처럼 커널 · 부팅 · 시간 설정이 없는 환경 / SKIP_GPU=1 = GPU 점검 생략

: "${MIN_FREE_GB:=20}"       # 강의 워크스페이스 빌드 · docker 이미지에 필요한 여유 (협동3 Isaac Sim 은 강의 점검이 따로 봄)
: "${DNS_TIMEOUT:=5}"
: "${SKIP_HOST:=0}"
: "${SKIP_GPU:=0}"
: "${SKIP_DOCKER:=0}"
: "${OS_RELEASE:=/etc/os-release}"
: "${BOOT_DIR:=/boot}"
# 드라이버를 까는 강의 (협동2 · 협동3 · 지능1) 가 없으면 doctor.sh 가 warn 으로 낮춘다 (협동1 은 드라이버를 깔지 않음)
: "${GPU_DRIVER_LEVEL:=fail}"
: "${CMDLINE_FILE:=/proc/cmdline}"
# SN5xx 계열 NVMe SSD 의 깊은 절전 (APST) 복귀 실패를 막는 커널 파라미터
readonly NVME_APST_PARAM='nvme_core.default_ps_max_latency_us=0'
: "${NVME_TIMEOUT_MIN:=2}"   # 이번 부팅 nvme timeout 이 이 횟수 이상이면 반복으로 본다

os_codename_ok() {
    grep -qx "VERSION_CODENAME=${UBUNTU_CODENAME}" "${OS_RELEASE}" \
        || { grep '^PRETTY_NAME=' "${OS_RELEASE}"; return 1; }
}

disk_free_ok() {
    local gb
    gb="$(run_t df -BG --output=avail "$1" | tail -n1 | tr -dc '0-9')"
    [[ -n "${gb}" ]] || { skip_because "df 실패: $1"; return; }
    [[ "${gb}" -ge "${MIN_FREE_GB}" ]] || { echo "$1 여유 ${gb}GB (권장 ${MIN_FREE_GB}GB 이상)"; return 1; }
}

dpkg_audit_clean() {
    local out
    out="$(run_t dpkg --audit 2>&1)"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

# 다른 apt · dpkg 작업 (자동 업데이트 포함) 이 돌고 있으면 설치가 lock · dpkg 오류로 실패한다
#   unattended-upgrade-shutdown 은 늘 떠 있는 대기 프로세스라 제외
apt_idle() {
    local out
    out="$(pgrep -a -x 'apt|apt-get|aptitude|dpkg' 2>/dev/null; pgrep -af 'bin/unattended-upgrade($| )' 2>/dev/null)"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

# 부팅 로그에 nvme I/O timeout 반복 = SSD APST 버그 (디스크 고장 아님). 커널 로그는 adm · systemd-journal 그룹만 읽힘
nvme_apst_ok() {
    command -v journalctl >/dev/null || { skip_because "journalctl 없음"; return; }
    local groups n
    groups=" $(id -nG) "
    [[ ${EUID} -eq 0 || "${groups}" == *" adm "* || "${groups}" == *" systemd-journal "* ]] \
        || { skip_because "커널 로그 읽기 권한 없음 (adm 그룹 아님)"; return; }
    local log rc=0
    log="$(run_t journalctl -k -b -q --no-pager 2>/dev/null)" || rc=$?
    [[ ${rc} -eq 0 ]] || { skip_because "커널 로그 읽기 실패 (종료 코드 ${rc})"; return; }
    # 장치 줄만 ("nvme0: ... timeout"). 한 번은 일시적일 수 있어 반복 (기준 이상) 일 때만
    n="$(grep -cE 'nvme[0-9]+: .*timeout' <<<"${log}")"
    [[ "${n}" -ge "${NVME_TIMEOUT_MIN}" ]] || return 0
    if grep -qF "${NVME_APST_PARAM}" "${CMDLINE_FILE}"; then
        echo "이번 부팅 nvme timeout ${n}건, APST 파라미터는 이미 적용됨 → SSD 수명 · 미디어 오류 점검"
    else
        echo "이번 부팅 nvme timeout ${n}건, ${NVME_APST_PARAM} 미적용"
    fi
    return 1
}

# lock 없이 의존성만 계산 (root 불필요)
apt_deps_ok() {
    local out
    out="$(run_t apt-get -o Debug::NoLocking=1 -qq check 2>&1)" || { echo "${out}"; return 1; }
}

# apt_sources_clean <E|W> · apt 소스 설정 오류 (E:) · 경고 (W:) 메시지가 없음
#   예: "E: Conflicting values set for option Signed-By" = 같은 저장소를 다른 키링으로 두 번 등록
apt_sources_clean() {
    local out
    out="$(run_t apt-cache policy 2>&1 >/dev/null)"
    out="$(grep "^$1:" <<<"${out}")"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

# /boot 에 이미지가 있는 커널 중 가장 새 버전 (지워진 커널의 /lib/modules 찌꺼기는 무시)
newest_kernel() {
    find "${BOOT_DIR}" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null \
        | sed 's/^vmlinuz-//' | sort -V | tail -n1
}

booted_newest_kernel() {
    local newest
    newest="$(newest_kernel)"
    [[ -n "${newest}" ]] || { skip_because "${BOOT_DIR} 에 커널 이미지 없음"; return; }
    [[ "$(uname -r)" == "${newest}" ]] || { echo "부팅 $(uname -r) / 설치된 최신 ${newest}"; return 1; }
}

# 반쪽 HWE 커널 = modules-extra 없음 → wifi · 일부 USB 입력이 사라짐
modules_extra_present() {
    local k="${1:-$(uname -r)}"
    [[ -d "/lib/modules/${k}/kernel/drivers/net/wireless" ]] || { echo "${k}: modules-extra 없음"; return 1; }
}

no_reboot_pending() {
    [[ ! -e /var/run/reboot-required ]] || { head -n3 /var/run/reboot-required.pkgs 2>/dev/null; return 1; }
}

# nvidia-smi 종료 코드 3 ("장치에서 지원 안 함") 이 판정 불가로 읽히지 않게 1 로 바꾼다 (시간 초과는 유지)
nvidia_driver_loaded() {
    local rc=0
    run_t nvidia-smi -L || rc=$?
    [[ ${rc} -eq 0 || ${rc} -eq ${RC_TIMEOUT} ]] && return "${rc}"
    return 1
}

# 다음 부팅 커널에 nvidia 모듈이 있어야 검은 화면이 안 난다
nvidia_module_for_newest_kernel() {
    local k
    k="$(newest_kernel)"
    [[ -n "${k}" ]] || { skip_because "${BOOT_DIR} 에 커널 이미지 없음"; return; }
    [[ -n "$(find "/lib/modules/${k}" -name 'nvidia.ko*' -print -quit 2>/dev/null)" ]] \
        || { echo "${k} 에 nvidia.ko 없음 → 이 커널로 부팅하면 그래픽 드라이버가 없음"; return 1; }
}

secure_boot_off() {
    command -v mokutil >/dev/null || { skip_because "mokutil 없음"; return; }
    local st
    st="$(run_t mokutil --sb-state 2>&1)"
    ! grep -q 'SecureBoot enabled' <<<"${st}" || { echo "SecureBoot enabled"; return 1; }
}

clock_synced() {
    command -v timedatectl >/dev/null || { skip_because "timedatectl 없음"; return; }
    local v
    v="$(run_t timedatectl show -p NTPSynchronized --value 2>/dev/null)" || { skip_because "systemd 시간 서비스 접근 불가"; return; }
    [[ "${v}" == yes ]] || { echo "NTPSynchronized=${v}"; return 1; }
}

dns_resolves() { timeout "${DNS_TIMEOUT}" getent hosts "$1" >/dev/null || { echo "$1 이름 풀이 실패"; return 1; }; }

# stdout (버전) 은 버리고 오류 메시지만 남긴다 → check 가 stderr 를 상세 줄로 보여 줌
docker_daemon_ok() { run_t docker info --format '{{.ServerVersion}}' >/dev/null; }

check_system() {
    section "공통 · 시스템"
    check fail "Ubuntu ${UBUNTU_CODENAME} (24.04)" "강의 PC 는 Ubuntu 24.04 만 지원" os_codename_ok
    check warn "홈 디스크 여유 ${MIN_FREE_GB}GB 이상" "필요 없는 파일 · docker image prune 으로 공간 확보" disk_free_ok "${HOME}"
    check warn "다른 apt · dpkg 작업 없음 (lock 충돌 예방)" "끝날 때까지 기다린 뒤 설치 (강제 종료하면 패키지가 반쯤 설치된 채 남음)" apt_idle
    check fail "dpkg 중단된 설치 없음" "sudo dpkg --configure -a" dpkg_audit_clean
    check fail "apt 의존성 깨짐 없음" "sudo apt --fix-broken install" apt_deps_ok
    check fail "apt 저장소 설정 오류 없음" "메시지의 .list 파일 중복 · 키링 경로 충돌을 정리 (/etc/apt/sources.list.d)" apt_sources_clean E
    check warn "apt 저장소 설정 경고 없음" "메시지의 .list 파일 중복을 정리" apt_sources_clean W
    check warn "패키지 서버 이름 풀이 (packages.ros.org)" "네트워크 · DNS 확인 (설치 · 업데이트에만 필요)" dns_resolves packages.ros.org

    if [[ "${SKIP_HOST}" == 0 ]]; then
        check fail "부팅 커널 modules-extra (wifi · USB 입력)" "sudo apt install linux-modules-extra-\$(uname -r)" modules_extra_present
        check warn "설치된 최신 커널로 부팅됨" "재부팅" booted_newest_kernel
        check warn "재부팅 대기 없음" "재부팅" no_reboot_pending
        check warn "NVMe SSD timeout 없음 (APST 절전 버그)" "GRUB_CMDLINE_LINUX_DEFAULT 에 ${NVME_APST_PARAM} 추가 → sudo update-grub → 재부팅" nvme_apst_ok
        check warn "시간 동기화 (apt · TLS 인증서 검증)" "sudo timedatectl set-ntp true" clock_synced
    fi

    if [[ "${SKIP_GPU}" == 0 ]] && has_nvidia_gpu; then
        check "${GPU_DRIVER_LEVEL}" "NVIDIA 드라이버 동작 (nvidia-smi)" "재부팅 후 다시 확인 → 계속 실패하면 강의 설치기의 드라이버 단계 재실행" nvidia_driver_loaded
        if [[ "${SKIP_HOST}" == 0 ]]; then
            check "${GPU_DRIVER_LEVEL}" "최신 커널에 nvidia 모듈 있음 (다음 부팅 검은 화면 예방)" \
                "sudo apt install --reinstall linux-modules-nvidia-<버전>-generic-hwe-24.04 또는 dkms status 확인" \
                nvidia_module_for_newest_kernel
            check warn "Secure Boot 꺼짐 (서명 안 된 dkms 모듈 거부 방지)" "BIOS 에서 Secure Boot 끄기" secure_boot_off
        fi
    fi

    if [[ "${SKIP_DOCKER}" == 0 ]] && command -v docker >/dev/null; then
        check fail "docker 그룹 소속" "sudo usermod -aG docker \$USER 후 로그아웃 · 재로그인" user_in_group docker
        check fail "docker 데몬 응답" "sudo systemctl restart docker" docker_daemon_ok
    fi
}
