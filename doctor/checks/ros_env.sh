# shellcheck shell=bash
# shellcheck disable=SC2088  # "~/.bashrc" 는 화면에 보일 문구 (경로 확장 아님)
# checks/ros_env.sh · 강의 공통 ROS 환경 점검 (ROS 설치 · ~/.bashrc · 시스템 python · 설치기 기록)
#   선행 = lib/report.sh · lib/pins.sh · lib/probes.sh
#   ~/.bashrc 는 실행하지 않고 글자로만 읽는다 (대화형 셸을 띄우면 학생 설정이 부수효과를 낼 수 있음)

# 주석이 아닌 줄만 (앞 공백 허용)
_bashrc_active() { grep -nvE '^\s*(#|$)' "${BASHRC}" 2>/dev/null; }

bashrc_syntax_ok() {
    [[ -f "${BASHRC}" ]] || { skip_because "${BASHRC} 없음"; return; }
    bash -n "${BASHRC}"
}

# 다른 ROS distro 를 source 하는 줄 → jazzy 와 섞여 패키지 · python 경로가 엉킴
bashrc_single_distro() {
    # 줄마다 /opt/ros/<이름> 을 전부 뽑아 본다 → "humble; jazzy" 처럼 한 줄에 섞여도 잡힘
    local line name bad=0
    while IFS= read -r line; do
        while IFS= read -r name; do
            [[ "${name}" == "/opt/ros/${ROS_DISTRO}" ]] || { echo "${line}"; bad=1; break; }
        done < <(grep -oE '/opt/ros/[a-z]+' <<<"${line}")
    done < <(_bashrc_active | grep -E '/opt/ros/[a-z]+')
    return "${bad}"
}

# bashrc_export_consistent <변수> · 최상위 export 값이 하나뿐 (여러 개면 마지막 줄이 조용히 이김)
#   들여쓴 export = 함수 · if 안 (예: 협동3 isaac_ros/jazzy 함수의 터미널별 RMW) → 의도한 덮어쓰기라 제외
bashrc_export_consistent() {
    local lines values
    lines="$(_bashrc_active | grep -E "^[0-9]+:export $1=")"
    # 값 = 줄 끝 주석 (" # ...") 과 따옴표 · 공백을 뺀 것
    values="$(sed -E "s/^[0-9]+:\s*export $1=//; s/\s+#.*$//; s/[\"' ]//g" <<<"${lines}" | sort -u | grep -c .)"
    [[ "${values}" -le 1 ]] || { echo "${lines}"; return 1; }
}

# bashrc 의 CYCLONEDDS_URI 파일 경로 (~ · $HOME · ${HOME} 만 펼침, 다른 변수는 그대로 남김)
_bashrc_cyclonedds_paths() {
    local path
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        path="${path/#\~/${HOME}}"; path="${path//\$\{HOME\}/${HOME}}"; path="${path//\$HOME/${HOME}}"
        echo "${path}"
    done < <(_bashrc_active | sed -nE 's|.*CYCLONEDDS_URI=["'\'']?file://([^"'\'' ]+).*|\1|p')
}

# CYCLONEDDS_URI 가 가리키는 파일이 있음 (없으면 모든 노드가 "rmw handle is invalid")
cyclonedds_uri_files_exist() {
    local path bad=0 unknown=0
    while IFS= read -r path; do
        # HOME 외 변수가 남으면 글자만으로는 경로를 알 수 없음
        [[ "${path}" != *'$'* ]] || { echo "판정 불가 (변수 포함): ${path}"; unknown=1; continue; }
        [[ -f "${path}" ]] || { echo "없음: ${path}"; bad=1; }
    done < <(_bashrc_cyclonedds_paths)
    [[ ${bad} == 1 || ${unknown} == 0 ]] || return "${RC_SKIP}"
    return "${bad}"
}

# PDF 강의자료에서 복사하면 따옴표 · 대시 · 공백이 다른 문자로 바뀐다 → 문법은 맞아도 명령이 깨짐
bashrc_plain_punctuation() {
    local out
    # UTF-8 바이트: 왼/오른 큰따옴표 · 왼/오른 작은따옴표 · en/em 대시 · 줄바꿈 없는 공백
    out="$(_bashrc_active | LC_ALL=C grep -F -e $'\xe2\x80\x9c' -e $'\xe2\x80\x9d' -e $'\xe2\x80\x98' \
        -e $'\xe2\x80\x99' -e $'\xe2\x80\x93' -e $'\xe2\x80\x94' -e $'\xc2\xa0')"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

# setuptools 80 이상 (pip 로 올림) → colcon build 의 ament_python 패키지가 실패
setuptools_below_80() {
    py_check 'import setuptools, sys
v = setuptools.__version__
print(v, setuptools.__file__)
sys.exit(0 if int(v.split(".")[0]) < 80 else 1)'
}

# conda base 자동 활성 → python3 가 conda 것으로 바뀌어 rclpy import 실패
conda_base_not_auto() {
    grep -qF '>>> conda initialize >>>' "${BASHRC}" 2>/dev/null || return 0
    grep -qE '^\s*auto_activate_base:\s*false' "${HOME}/.condarc" 2>/dev/null && return 0
    echo "~/.bashrc 에 conda initialize 블록, auto_activate_base 꺼지지 않음"; return 1
}

# ROS 2 Jazzy (apt) 는 numpy 1.x 기준 빌드 → pip 로 2.x 가 들어오면 cv_bridge · scipy 등이 깨짐
system_numpy_below_2() {
    py_check 'import numpy, sys
v = numpy.__version__
print(v, numpy.__file__)
sys.exit(0 if int(v.split(".")[0]) < 2 else 1)'
}

installer_states_clean() {
    local f out line found=0 bad=0
    for f in "${ROKEY_STATE_DIR}"/*.state "${COBOT2_STATE_FILE}"; do
        [[ -f "${f}" ]] || continue
        found=1
        out="$(installer_state_clean "${f}")" && continue
        bad=1
        while IFS= read -r line; do echo "${f}: ${line}"; done <<<"${out}"
    done
    [[ ${found} == 1 ]] || { skip_because "설치기 진행 기록 없음"; return; }
    return "${bad}"
}

# 재부팅 재개용 autostart 가 남아 있음 = 설치가 끝나지 않았거나 정리되지 않음
no_resume_autostart() {
    local out
    out="$(find "${AUTOSTART_DIR}" -maxdepth 1 \( -name 'rokey-jazzy-install-resume-*.desktop' \
        -o -name 'ros2-jazzy-install-resume.desktop' \) -printf '%f\n' 2>/dev/null)"
    [[ -z "${out}" ]] || { echo "${out}"; return 1; }
}

check_ros_env() {
    section "공통 · ROS 환경"
    check fail "ROS 2 ${ROS_DISTRO} desktop 설치" "강의 설치기 재실행 (ROS 단계)" pkg_installed "ros-${ROS_DISTRO}-desktop"
    check fail "ROS 2 기본 환경 source · ros2 CLI 동작" "sudo apt install --reinstall ros-${ROS_DISTRO}-ros2cli" ros_has_pkg "" rclpy
    check fail "rosdep 초기화" "sudo rosdep init && rosdep update" path_exists /etc/ros/rosdep/sources.list.d/20-default.list
    check warn "rosdep update 완료" "rosdep update" path_exists "${HOME}/.ros/rosdep/sources.cache"
    check fail "~/.bashrc 문법 오류 없음" "표시된 줄을 고친다 (새 터미널마다 오류)" bashrc_syntax_ok
    check fail "~/.bashrc 가 ${ROS_DISTRO} 외 ROS 를 source 하지 않음" "표시된 줄을 지우거나 주석 처리" bashrc_single_distro
    check warn "~/.bashrc ROS_DOMAIN_ID 값 하나" "강의 · 조 번호에 맞는 줄 하나만 남김 (마지막 줄이 이김)" bashrc_export_consistent ROS_DOMAIN_ID
    check warn "~/.bashrc RMW_IMPLEMENTATION 값 하나" "강의에 맞는 줄 하나만 남김 (마지막 줄이 이김)" bashrc_export_consistent RMW_IMPLEMENTATION
    check fail "CYCLONEDDS_URI 파일 존재" "강의 설치기의 DDS 단계 재실행" cyclonedds_uri_files_exist
    check warn "~/.bashrc 에 PDF 복사 특수문자 없음 (둥근 따옴표, 긴 대시 등)" "표시된 줄의 따옴표 · 대시를 키보드로 다시 입력" bashrc_plain_punctuation
    check warn "setuptools 80 미만 (colcon build)" "python3 -m pip uninstall --break-system-packages setuptools (pip 로 올린 것 제거 → apt 판 사용)" setuptools_below_80
    check warn "conda base 자동 활성 꺼짐" "conda config --set auto_activate_base false" conda_base_not_auto
    check fail "시스템 python numpy 1.x" "python3 -m pip uninstall numpy (pip 로 올린 2.x 제거) 후 다시 확인" system_numpy_below_2
    check fail "설치기 진행 기록에 실패 · 중단 단계 없음" "같은 설치 명령 다시 실행 (끝난 단계는 건너뜀). RUNNING 은 설치가 지금 진행 중일 수도 있음" installer_states_clean
    check warn "설치 재개 autostart 남지 않음" "설치를 끝까지 실행하거나 표시된 파일 삭제 (${AUTOSTART_DIR})" no_resume_autostart
}
