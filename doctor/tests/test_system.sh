#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_system.sh · checks/system.sh 단위 테스트

_load() {
    # shellcheck source=../lib/report.sh
    source "${DOCTOR_ROOT}/lib/report.sh"
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    # shellcheck source=../lib/probes.sh
    source "${DOCTOR_ROOT}/lib/probes.sh"
    # shellcheck source=../checks/system.sh
    source "${DOCTOR_ROOT}/checks/system.sh"
}
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "${r}"; }

test_apt_sources_clean_splits_errors_and_warnings() {
    _load
    stub apt-cache 'echo "E: Conflicting values set for option Signed-By regarding source http://packages.ros.org/ros2/ubuntu/ noble" >&2
echo "W: Target Packages is configured multiple times" >&2'
    assert_contains "$(apt_sources_clean E || true)" "Conflicting values set for option Signed-By"
    assert_not_contains "$(apt_sources_clean E || true)" "configured multiple times"
    assert_contains "$(apt_sources_clean W || true)" "configured multiple times"
    stub apt-cache 'echo "packages.ros.org 500"'
    assert_eq "$(rc apt_sources_clean E)" "0"
}

test_booted_newest_kernel_uses_boot_images_only() {
    _load
    BOOT_DIR="${PWD}/boot"; mkdir -p boot
    stub uname 'echo 6.8.0-147-generic'
    touch boot/vmlinuz-6.8.0-142-generic boot/vmlinuz-6.8.0-147-generic
    assert_eq "$(rc booted_newest_kernel)" "0"
    touch boot/vmlinuz-6.8.0-150-generic
    assert_contains "$(booted_newest_kernel || true)" "최신 6.8.0-150-generic"
    rm boot/vmlinuz-*
    assert_eq "$(rc booted_newest_kernel)" "${RC_SKIP}"
}

test_nvidia_module_missing_for_newest_kernel_fails() {
    _load
    BOOT_DIR="${PWD}/boot"; mkdir -p boot
    touch boot/vmlinuz-0.0.0-zz-doctor-test
    assert_contains "$(nvidia_module_for_newest_kernel || true)" "0.0.0-zz-doctor-test 에 nvidia.ko 없음"
}

test_check_system_skips_host_and_gpu_items_in_container_mode() {
    _load
    SKIP_HOST=1; SKIP_GPU=1; SKIP_DOCKER=1
    stub docker 'exit 0'
    out="$(check_system)"
    assert_not_contains "${out}" "docker 그룹 소속"
    assert_not_contains "${out}" "modules-extra"
    assert_not_contains "${out}" "NVIDIA"
    assert_contains "${out}" "dpkg 중단된 설치 없음"
}

test_nvidia_smi_exit_3_is_fail_not_skip() {
    _load
    stub nvidia-smi 'exit 3'
    assert_eq "$(rc nvidia_driver_loaded)" "1"
    stub nvidia-smi 'echo "GPU 0: x"'
    assert_eq "$(rc nvidia_driver_loaded)" "0"
}

test_secure_boot_enabled_warns() {
    _load
    stub mokutil 'echo "SecureBoot enabled"'
    assert_eq "$(rc secure_boot_off)" "1"
    stub mokutil 'echo "SecureBoot disabled"'
    assert_eq "$(rc secure_boot_off)" "0"
}

test_apt_idle_flags_running_dpkg_but_not_shutdown_waiter() {
    _load
    stub pgrep 'case "$*" in *-x*) echo "4242 dpkg";; *) exit 1;; esac'
    assert_contains "$(apt_idle || true)" "4242 dpkg"
    stub pgrep 'exit 1'
    assert_eq "$(rc apt_idle)" "0"
}

test_unattended_upgrade_shutdown_is_not_busy() {
    _load
    # 실제 pgrep 패턴이 대기 프로세스 이름과 맞지 않는지 확인
    if grep -qE 'bin/unattended-upgrade($| )' <<<"/usr/share/unattended-upgrades/unattended-upgrade-shutdown --wait-for-signal"; then
        echo "shutdown waiter matched"; return 1
    fi
    grep -qE 'bin/unattended-upgrade($| )' <<<"/usr/bin/python3 /usr/bin/unattended-upgrade --download-only"
}

test_nvme_apst_reports_missing_param() {
    _load
    CMDLINE_FILE="${PWD}/cmdline"; echo "quiet splash" > cmdline
    stub id 'case "$1" in -nG) echo "rokey adm";; *) command id "$@";; esac'
    stub journalctl 'echo "kernel: nvme nvme0: I/O tag 12 QID 3 timeout, completion polled"'
    assert_eq "$(rc nvme_apst_ok)" "0"
    stub journalctl 'printf "kernel: nvme nvme0: I/O tag 12 QID 3 timeout, completion polled\nkernel: nvme nvme0: I/O tag 40 QID 1 timeout, completion polled\nKernel command line: nvme timeout x\n"'
    assert_contains "$(nvme_apst_ok || true)" "timeout 2건, nvme_core.default_ps_max_latency_us=0 미적용"
    echo "quiet nvme_core.default_ps_max_latency_us=0" > cmdline
    assert_contains "$(nvme_apst_ok || true)" "이미 적용됨"
    stub journalctl 'echo "kernel: all fine"'
    assert_eq "$(rc nvme_apst_ok)" "0"
}

test_nvme_apst_skips_without_log_permission() {
    _load
    [[ ${EUID} -ne 0 ]] || { echo "skip: root"; return 0; }
    stub id 'case "$1" in -nG) echo "student";; *) command id "$@";; esac'
    stub journalctl 'exit 0'
    assert_eq "$(rc nvme_apst_ok)" "${RC_SKIP}"
}

test_nvme_apst_journal_timeout_is_skip() {
    _load
    stub id 'case "$1" in -nG) echo "rokey adm";; *) command id "$@";; esac'
    stub journalctl 'exit 124'
    assert_eq "$(rc nvme_apst_ok)" "${RC_SKIP}"
}
