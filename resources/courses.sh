#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# shellcheck shell=bash
# resources/courses.sh · source 전용 · 협동3 단계 순서 (install.sh 가 호출)
#   선행 조건 = config.sh · lib.sh source + RESOURCE_DIR · 옵션 변수(OPT_*) 설정
#   단계 이름 = state 키 → 이름을 바꾸면 기존 설치의 재개 기록이 끊긴다

# shellcheck disable=SC2034  # STEPS_TOTAL = lib.sh run_step 이 읽는다
R() { echo "${RESOURCE_DIR}/$1"; }

# 드라이버를 새로 깔았는데 모듈이 아직 안 올라왔으면 재부팅 후 같은 명령으로 재개
reboot_gate() {
    [[ "${DRY_RUN:-0}" == 1 ]] && { echo "[gate] would check for a pending reboot"; return 0; }
    [[ "${OPT_NO_NVIDIA}" == 1 ]] && return 0
    bash "$(R base.sh)" needs-reboot || return 0
    echo
    echo ">>> REBOOT REQUIRED: NVIDIA driver installed but not loaded yet."
    echo ">>> After reboot, run the SAME command again; finished steps are skipped."
    # 재부팅은 --yes 로 자동 동의하지 않는다 → 터미널에서 직접 답할 때만
    local reply=""
    if [[ -t 0 ]]; then
        read -r -p "Reboot now? (y/N): " reply
        [[ "${reply}" =~ ^[yY]$ ]] && as_root reboot
    fi
    exit 0
}

nvidia_step() {
    local n="$1"; shift
    if [[ "${OPT_NO_NVIDIA}" == 1 ]]; then
        run_step_skip "${n}" nvidia_driver "--no-nvidia"
    else
        run_step "${n}" nvidia_driver bash "$(R base.sh)" nvidia "$@"
    fi
}

domain_args() { [[ -n "${OPT_DOMAIN_ID}" ]] && echo "${OPT_DOMAIN_ID}"; return 0; }

plan_cobot3() {
    STEPS_TOTAL=13
    if [[ "${OPT_NO_KERNEL_HOLD}" == 1 ]]; then
        run_step_skip 1 kernel_hold "--no-kernel-hold"
    else
        run_step 1 kernel_hold bash "$(R cobot3.sh)" kernel-hold
    fi
    run_step 2 no_release_upgrade bash "$(R cobot3.sh)" no-release-upgrade
    nvidia_step 3 --open --pin "${NVIDIA_DRIVER_PIN_COBOT3}" --hold-all
    run_step 4 xorg               bash "$(R cobot3.sh)" xorg
    run_step 5 ros2_jazzy         bash "$(R base.sh)" ros2
    reboot_gate
    run_step 6 vscode             bash "$(R base.sh)" vscode
    local -a isaac=()
    [[ -n "${OPT_ISAAC_ZIP}" ]] && isaac+=(--zip "${OPT_ISAAC_ZIP}")
    [[ "${OPT_ISAAC_DOWNLOAD}" == 1 ]] && isaac+=(--download)
    run_step 7 isaacsim           bash "$(R cobot3.sh)" isaacsim "${isaac[@]}"
    run_step 8 nav2               bash "$(R cobot3.sh)" nav2
    run_step 9 isaac_ros_ws       bash "$(R cobot3.sh)" isaac-ros-ws
    run_step 10 cobot3_workspace  bash "$(R cobot3.sh)" workspace
    run_step --always 11 fastdds_profile bash "$(R cobot3.sh)" dds
    # shellcheck disable=SC2046
    run_step --always 12 cobot3_bashrc   bash "$(R cobot3.sh)" bashrc $(domain_args)
    run_step --always --interactive 13 verify bash "$(R verify.sh)"
}
