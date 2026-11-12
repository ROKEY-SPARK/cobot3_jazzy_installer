# shellcheck shell=bash
# shellcheck disable=SC2016  # bash -c '...' = 안쪽 셸이 펼칠 변수
# lib/probes.sh · source 전용 · 읽기 전용 점검 함수
#   반환: 0 = 정상 / 1 = 문제 (stdout = 이유) / RC_SKIP = 판정 불가 (stdout = 이유)
#   선행 조건 = lib/report.sh (RC_SKIP · skip_because · run_t)
#   root 권한이 필요한 명령은 쓰지 않는다

# ros2 run · 강의 pip --user 가 쓰는 인터프리터. PATH 의 conda · venv python 을 보지 않게 고정
: "${SYSTEM_PYTHON:=/usr/bin/python3}"
# import 가 __pycache__ 를 쓰지 않게 (읽기 전용 약속)
export PYTHONDONTWRITEBYTECODE=1

# --- apt / dpkg --------------------------------------------------------------

# 설치 여부. Status-Abbrev 두 번째 글자 i = 설치됨 (hold 된 패키지 "hi" 도 설치됨)
pkg_installed() {
    local p st missing=()
    for p in "$@"; do
        st="$(dpkg-query -W -f='${db:Status-Abbrev}' "${p}" 2>/dev/null)"
        [[ "${st:1:1}" == i ]] || missing+=("${p}")
    done
    [[ ${#missing[@]} -eq 0 ]] || { echo "미설치: ${missing[*]}"; return 1; }
}

pkg_held() {
    local held p loose=()
    held="$(apt-mark showhold 2>/dev/null)"
    for p in "$@"; do grep -qxF "${p}" <<<"${held}" || loose+=("${p}"); done
    [[ ${#loose[@]} -eq 0 ]] || { echo "hold 풀림: ${loose[*]}"; return 1; }
}

# --- 파일 · 디렉토리 ------------------------------------------------------------

path_exists() { [[ -e "$1" ]] || { echo "없음: $1"; return 1; }; }

xml_valid() {
    path_exists "$1" || return 1
    run_t "${SYSTEM_PYTHON}" -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$1"
}

# python 표현식 실행. 사용자 site (pip --user) 도 보이게 -I 를 쓰지 않는다 → 현재 디렉토리만 / 로 옮김
py_check() { (cd / && run_t "${SYSTEM_PYTHON}" -c "$1"); }

# --- git -------------------------------------------------------------------

# 고정 ref 와 HEAD 일치. 둘 중 하나라도 못 구하면 실패 (빈 문자열끼리 같다고 통과시키지 않음)
git_at_ref() {
    local have want
    [[ -d "$1/.git" || -f "$1/.git" ]] || { echo "git 저장소 아님: $1"; return 1; }
    have="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || { echo "HEAD 읽기 실패: $1"; return 1; }
    want="$(git -C "$1" rev-parse "$2^{commit}" 2>/dev/null)" || { echo "ref 없음: $2"; return 1; }
    [[ "${have}" == "${want}" ]] || { echo "HEAD ${have:0:12} ≠ $2 (${want:0:12})"; return 1; }
}

# --- ROS ---------------------------------------------------------------------

# ros_has_pkg <overlay setup.bash | ""> <pkg...> · 새 셸에서 ROS 를 올려 확인
#   터미널에서 다른 워크스페이스를 source 한 상태로 실행해도 그 overlay 로 통과하지 않게 ROS 경로 변수를 지운다
ros_has_pkg() {
    local overlay="$1"; shift
    [[ -z "${overlay}" || -f "${overlay}" ]] || { echo "overlay 없음 (빌드 안 됨?): ${overlay}"; return 1; }
    run_t env -u AMENT_PREFIX_PATH -u CMAKE_PREFIX_PATH -u COLCON_PREFIX_PATH -u PYTHONPATH \
        -u AMENT_CURRENT_PREFIX -u LD_LIBRARY_PATH bash -c '
        set +u
        source "/opt/ros/$1/setup.bash" || exit 1
        [ -n "$2" ] && { source "$2" || exit 1; }
        shift 2; bad=0
        for p in "$@"; do ros2 pkg prefix "$p" >/dev/null 2>&1 || { echo "패키지 못 찾음: $p"; bad=1; }; done
        exit $bad' _ "${ROS_DISTRO}" "${overlay}" "$@"
}

# --- bashrc ------------------------------------------------------------------

# bashrc_block_ok <시작 마커> [끝 마커] · 시작 마커 정확히 1개, 끝 마커도 1개이고 시작보다 뒤
bashrc_block_ok() {
    local begin="$1" end="${2:-}" nb ne lb le
    [[ -f "${BASHRC}" ]] || { echo "없음: ${BASHRC}"; return 1; }
    nb="$(grep -cxF -- "${begin}" "${BASHRC}")"
    [[ "${nb}" -eq 1 ]] || { echo "시작 마커 ${nb}개 (1개여야 함): ${begin}"; return 1; }
    [[ -n "${end}" ]] || return 0
    ne="$(grep -cxF -- "${end}" "${BASHRC}")"
    [[ "${ne}" -eq 1 ]] || { echo "끝 마커 ${ne}개 (1개여야 함): ${end}"; return 1; }
    lb="$(grep -nxF -- "${begin}" "${BASHRC}" | cut -d: -f1)"
    le="$(grep -nxF -- "${end}" "${BASHRC}" | cut -d: -f1)"
    [[ "${lb}" -lt "${le}" ]] || { echo "끝 마커가 시작 마커보다 앞 (${lb}행 / ${le}행)"; return 1; }
}

# --- 하드웨어 · 서비스 -------------------------------------------------------------

: "${SYSFS_PCI_DIR:=/sys/bus/pci/devices}"

# NVIDIA GPU 존재 (PCI vendor 10de, class 03xx = display)
has_nvidia_gpu() {
    local dev
    for dev in "${SYSFS_PCI_DIR}"/*; do
        [[ -r "${dev}/vendor" && -r "${dev}/class" ]] || continue
        [[ "$(cat "${dev}/vendor")" == 0x10de && "$(cat "${dev}/class")" == 0x03* ]] && return 0
    done
    return 1
}

# 이미지 존재. docker 를 못 쓰는 상황 (미설치 · 데몬 접근 불가) 은 판정 불가 — 그 원인은 공통 점검이 따로 본다
docker_image_present() {
    command -v docker >/dev/null || { skip_because "docker 미설치"; return; }
    run_t docker info >/dev/null 2>&1 || { skip_because "docker 데몬 접근 불가 (공통 점검의 docker 항목 참고)"; return; }
    run_t docker image inspect "$1" >/dev/null 2>&1 || { echo "이미지 없음: $1"; return 1; }
}

user_in_group() {
    local groups
    groups="$(id -nG)"
    grep -qxF "$1" <<<"${groups// /$'\n'}" || { echo "$(id -un) 가 $1 그룹에 없음"; return 1; }
}

# 설치기 state 파일에 끝나지 않은 단계 (FAIL · RUNNING) 가 없음
installer_state_clean() {
    local bad rc=0
    path_exists "$1" || return 1
    bad="$(grep -E '=(FAIL|RUNNING)$' "$1" 2>&1)" || rc=$?
    [[ ${rc} -le 1 ]] || { skip_because "읽기 실패: $1"; return; }
    [[ -z "${bad}" ]] || { echo "${bad}"; return 1; }
}

# 설치된 nvidia-driver-NNN[-open] 메타 패키지 (없으면 빈 문자열) · 설치기 base.sh 와 같은 판정
installed_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open)?$' | sort -V | tail -n1
}

# nvidia_driver_is <패키지> · 강의가 정한 드라이버 메타 패키지가 설치돼 있음
nvidia_driver_is() {
    local have
    have="$(installed_driver_pkg)"
    [[ "${have}" == "$1" ]] || { echo "설치됨: ${have:-없음} / 강의 기준: $1"; return 1; }
}

# colcon 이 패키지로 보는 package.xml 인지. 위쪽 (src 포함) 에 COLCON_IGNORE 가 있거나
#   위쪽 디렉토리가 이미 패키지면 (package.xml 보유) colcon 은 그 아래로 내려가지 않는다
_colcon_visible() {
    local src="$1" dir
    dir="$(dirname "$2")"
    [[ -e "${dir}/COLCON_IGNORE" ]] && return 1
    while [[ "${dir}" != "${src}" && "${dir}" != / ]]; do
        dir="$(dirname "${dir}")"
        [[ -e "${dir}/COLCON_IGNORE" || ( "${dir}" != "${src}" && -e "${dir}/package.xml" ) ]] && return 1
    done
    return 0
}

# 워크스페이스 src 안에 같은 이름 패키지가 둘 → colcon build 실패
#   colcon 처럼 심볼릭 링크를 따라간다. 목록을 다 못 받으면 (시간 초과) 판정 불가
ws_unique_packages() {
    local src="$1/src" list rc=0 xml name dups
    [[ -d "${src}" ]] || { skip_because "없음: ${src}"; return; }
    list="$(run_t find -L "${src}" -name package.xml 2>/dev/null)" || rc=$?
    # find -L 은 링크 고리 · 읽기 거부에도 1 을 낸다 → 시간 초과만 판정 불가로 본다
    [[ ${rc} -ne ${RC_TIMEOUT} ]] || { skip_because "패키지 목록 시간 초과: ${src}"; return; }
    dups="$(while IFS= read -r xml; do
        [[ -n "${xml}" ]] || continue
        _colcon_visible "${src}" "${xml}" || continue
        name="$(sed -n 's:.*<name>[[:space:]]*\([^<[:space:]]*\)[[:space:]]*</name>.*:\1:p' "${xml}" | head -n1)"
        [[ -n "${name}" ]] && printf '%s\t%s\n' "${name}" "${xml#"${src}"/}"
    done <<<"${list}" | sort | awk -F'\t' '
        { paths[$1] = paths[$1] "  " $2; n[$1]++ }
        END { for (k in n) if (n[k] > 1) print k ":" paths[k] }' | sort)"
    [[ -z "${dups}" ]] || { echo "${dups}"; return 1; }
}
