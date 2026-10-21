#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck shell=bash
# resources/sys.sh · source 전용 시스템 보조 함수
#   root 실행 · apt · 외부 저장소 등록 · bashrc 관리 블록 · 커밋 고정 clone
#   선행 조건 = config.sh + lib.sh source

# root 면 그대로, 아니면 sudo (Docker 빌드 = root / 호스트 = 일반 사용자)
as_root() {
    if [[ "${EUID}" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# apt update = 프로세스당 1회 (단계 안에서 반복 호출 비용 절감)
apt_update_once() {
    [[ "${__APT_UPDATED:-0}" == 1 ]] && return 0
    as_root apt-get update
    __APT_UPDATED=1
}

apt_install() {
    apt_update_once
    # conffile 질문이 로그 뒤에 숨어 멈추지 않도록 기존 설정 유지로 고정
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# 패키지 설치 여부 (0 = 설치됨)
pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

# add_apt_repo <key_url> <key_file> <list_file> <deb_line> [raw|dearmor]
#   멱등 = 키 파일 없을 때만 받음, list 내용이 같으면 다시 쓰지 않음
add_apt_repo() {
    local key_url="$1" key_file="$2" list_file="$3" line="$4" mode="${5:-raw}"
    as_root install -m 0755 -d "$(dirname "${key_file}")"
    if [[ ! -s "${key_file}" ]]; then
        # 임시 파일에 받은 뒤 이동 → 중간에 끊긴 다운로드가 "키 있음" 으로 남지 않음
        local tmp
        tmp="$(mktemp)"
        if [[ "${mode}" == dearmor ]]; then
            curl -fsSL "${key_url}" | gpg --dearmor > "${tmp}"
        else
            curl -fsSL "${key_url}" -o "${tmp}"
        fi
        as_root install -m 0644 "${tmp}" "${key_file}"
        rm -f "${tmp}"
    fi
    if [[ ! -f "${list_file}" ]] || ! grep -qxF "${line}" "${list_file}"; then
        echo "${line}" | as_root tee "${list_file}" >/dev/null
        __APT_UPDATED=0
    fi
}

# NVIDIA GPU 존재 여부 (PCI vendor 10de, class 03xx = display)
has_nvidia_gpu() {
    local dev
    for dev in /sys/bus/pci/devices/*; do
        [[ -r "${dev}/vendor" && -r "${dev}/class" ]] || continue
        [[ "$(cat "${dev}/vendor")" == 0x10de && "$(cat "${dev}/class")" == 0x03* ]] && return 0
    done
    return 1
}

# ROS 환경 source (setup.bash 는 미설정 변수 참조 → -u 잠시 해제)
ros_source() {
    local f
    set +u
    for f in "/opt/ros/${ROS_DISTRO}/setup.bash" "$@"; do
        # shellcheck disable=SC1090
        [[ -f "${f}" ]] && source "${f}"
    done
    set -u
}

# rosdep init = 머신당 1회만 가능
rosdep_ready() {
    pkg_installed python3-rosdep || apt_install python3-rosdep
    [[ -e /etc/ros/rosdep/sources.list.d/20-default.list ]] || as_root rosdep init
    rosdep update --rosdistro "${ROS_DISTRO}"
}

# ============================================================================
# bashrc 관리 블록 · `# >>> rokey <name> >>>` ~ `# <<< rokey <name> <<<`
# ============================================================================

# bashrc_block_write <name> <content-file> · 기존 블록 삭제 후 파일 끝에 다시 씀 (멱등)
#   첫 수정 전 원본을 ~/.bashrc.rokey.bak 로 1회 백업
bashrc_block_write() {
    local name="$1" content="$2"
    [[ -f "${content}" ]] || die "${EXIT_SYSTEM}" "bashrc: content file missing: ${content}"
    touch "${BASHRC}"
    [[ -e "${BASHRC}.rokey.bak" ]] || cp -p "${BASHRC}" "${BASHRC}.rokey.bak"
    bashrc_block_remove "${name}"
    # 마지막 줄에 개행이 없으면 시작 마커가 그 줄 뒤에 붙어 다음 실행에서 못 찾음 → 개행 보충
    if [[ -s "${BASHRC}" && -n "$(tail -c1 "${BASHRC}")" ]]; then echo >> "${BASHRC}"; fi
    { echo "# >>> rokey ${name} >>>"; cat "${content}"; echo "# <<< rokey ${name} <<<"; } >> "${BASHRC}"
}

# 시작·끝 마커가 둘 다 있을 때만 지움. 한쪽만 있으면 sed 범위가 파일 끝까지 번짐 → 거부
bashrc_block_remove() {
    local name="$1"
    local begin="# >>> rokey ${name} >>>" end="# <<< rokey ${name} <<<"
    [[ -f "${BASHRC}" ]] || return 0
    local has_begin=0 has_end=0
    grep -qxF "${begin}" "${BASHRC}" && has_begin=1
    grep -qxF "${end}" "${BASHRC}" && has_end=1
    if [[ ${has_begin} != "${has_end}" ]]; then
        die "${EXIT_SYSTEM}" "bashrc: '${name}' block in ${BASHRC} has only one marker — fix it by hand (backup: ${BASHRC}.rokey.bak)."
    fi
    [[ ${has_begin} == 1 ]] || return 0
    sed -i "\\|^${begin}\$|,\\|^${end}\$|d" "${BASHRC}"
}

# 블록 안의 ROS_DOMAIN_ID 값 (없으면 빈 문자열) · --domain-id 없이 재실행해도 값을 유지하는 데 씀
bashrc_block_domain_id() {
    local name="$1"
    [[ -f "${BASHRC}" ]] || return 0
    sed -n "\\|^# >>> rokey ${name} >>>\$|,\\|^# <<< rokey ${name} <<<\$|p" "${BASHRC}" \
        | sed -n 's/^\s*export ROS_DOMAIN_ID=\([0-9][0-9]*\)\s*$/\1/p' | tail -n1
}

# render_template <src> <dst> [KEY=VALUE ...] · __KEY__ 자리표시자 치환
render_template() {
    local src="$1" dst="$2"; shift 2
    local kv key val content
    [[ -f "${src}" ]] || die "${EXIT_SYSTEM}" "template missing: ${src}"
    # bash 5.2 기본값 = 치환 문자열의 & 를 매칭 문자열로 바꿈 → 값 그대로 넣도록 끔
    shopt -u patsub_replacement 2>/dev/null || true
    content="$(cat "${src}")"
    for kv in "$@"; do
        key="${kv%%=*}"; val="${kv#*=}"
        content="${content//__${key}__/${val}}"
    done
    if grep -qE '__[A-Z0-9_]+__' <<<"${content}"; then
        die "${EXIT_SYSTEM}" "template ${src}: unresolved placeholder(s): $(grep -oE '__[A-Z0-9_]+__' <<<"${content}" | sort -u | tr '\n' ' ')"
    fi
    mkdir -p "$(dirname "${dst}")"
    printf '%s\n' "${content}" > "${dst}"
}

# ============================================================================
# git · 커밋/태그 고정 clone (재실행 시 핀으로 맞춤, 수정본은 건드리지 않음)
# ============================================================================

# git_clone_pinned <url> <dir> <ref> [--recursive]
git_clone_pinned() {
    local url="$1" dir="$2" ref="$3" recursive="${4:-}"
    if [[ ! -d "${dir}/.git" ]]; then
        if [[ -e "${dir}" ]] && [[ -n "$(ls -A "${dir}" 2>/dev/null)" ]]; then
            die "${EXIT_USER}" "git: ${dir} exists, is not empty and is not a git repo — move it away and re-run."
        fi
        git clone "${url}" "${dir}"
    fi
    local want have
    git -C "${dir}" fetch --quiet --tags origin 2>/dev/null || warn "git: fetch failed for ${dir} (offline?)"
    want="$(git -C "${dir}" rev-parse --verify --quiet "${ref}^{commit}")" \
        || die "${EXIT_SYSTEM}" "git: ref ${ref} not found in ${url}"
    have="$(git -C "${dir}" rev-parse HEAD)"
    if [[ "${have}" != "${want}" ]]; then
        if [[ -n "$(git -C "${dir}" status --porcelain --untracked-files=no)" ]]; then
            warn "git: ${dir} has local changes — keeping ${have:0:8} (pin ${want:0:8} not applied)."
        else
            git -C "${dir}" checkout --quiet --detach "${want}"
        fi
    fi
    if [[ "${recursive}" == --recursive ]]; then
        git -C "${dir}" submodule update --init --recursive
    fi
    echo "git: ${dir} @ $(git -C "${dir}" rev-parse --short HEAD)"
}
