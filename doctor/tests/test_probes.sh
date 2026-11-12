#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016,SC2034  # stub 본문 = 가짜 명령이 펼칠 변수 / 설정값은 source 한 코드가 읽음
# tests/test_probes.sh · lib/probes.sh 단위 테스트 (가짜 명령 = STUB_BIN)

_load() {
    # shellcheck source=../lib/report.sh
    source "${DOCTOR_ROOT}/lib/report.sh"
    # shellcheck source=../lib/pins.sh
    source "${DOCTOR_ROOT}/lib/pins.sh"
    # shellcheck source=../lib/probes.sh
    source "${DOCTOR_ROOT}/lib/probes.sh"
}

# rc <명령...> · set -e 셸에서 종료 코드만 받아 출력
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "${r}"; }

test_docker_image_present_skips_when_daemon_unreachable() {
    _load
    stub docker 'exit 1'
    assert_eq "$(rc docker_image_present foo:1)" "${RC_SKIP}"
}

test_pkg_installed_accepts_held_and_lists_missing() {
    _load
    stub dpkg-query 'case "${@: -1}" in held) printf "hi ";; ok) printf "ii ";; rc) printf "rc ";; *) exit 1;; esac'
    assert_eq "$(rc pkg_installed held ok)" "0"
    out="$(pkg_installed ok rc gone || true)"
    assert_eq "${out}" "미설치: rc gone"
}

test_pkg_held_reports_loose_packages() {
    _load
    stub apt-mark 'printf "docker-ce\ncontainerd.io\n"'
    assert_eq "$(rc pkg_held docker-ce containerd.io)" "0"
    assert_eq "$(pkg_held docker-ce docker-ce-cli || true)" "hold 풀림: docker-ce-cli"
}

test_bashrc_block_ok_rejects_duplicate_and_reversed_markers() {
    _load
    printf 'B\nx\nE\n' > "${BASHRC}"
    assert_eq "$(rc bashrc_block_ok B E)" "0"
    printf 'B\nE\nB\nE\n' > "${BASHRC}"
    assert_contains "$(bashrc_block_ok B E || true)" "시작 마커 2개"
    printf 'E\nB\n' > "${BASHRC}"
    assert_contains "$(bashrc_block_ok B E || true)" "끝 마커가 시작 마커보다 앞"
}

test_git_at_ref_fails_on_other_commit() {
    _load
    git init -q repo && git -C repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
    first="$(git -C repo rev-parse HEAD)"
    git -C repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
    assert_contains "$(git_at_ref repo "${first}" || true)" "≠ ${first}"
    assert_eq "$(rc git_at_ref repo HEAD)" "0"
    assert_eq "$(rc git_at_ref nowhere HEAD)" "1"
}

test_has_nvidia_gpu_reads_pci_class() {
    _load
    SYSFS_PCI_DIR="${PWD}/pci"
    mkdir -p pci/a && echo 0x8086 > pci/a/vendor && echo 0x030000 > pci/a/class
    assert_eq "$(rc has_nvidia_gpu)" "1"
    mkdir -p pci/b && echo 0x10de > pci/b/vendor && echo 0x030200 > pci/b/class
    assert_eq "$(rc has_nvidia_gpu)" "0"
}

test_installer_state_clean_flags_fail_and_running() {
    _load
    printf 'step_a=DONE\nstep_b=SKIPPED\n' > s
    assert_eq "$(rc installer_state_clean s)" "0"
    printf 'step_a=DONE\nstep_b=FAIL\nstep_c=RUNNING\n' > s
    out="$(installer_state_clean s || true)"
    assert_contains "${out}" "step_b=FAIL"
    assert_contains "${out}" "step_c=RUNNING"
}

test_nvidia_driver_is_distinguishes_open_flavor() {
    _load
    stub dpkg-query 'printf "ii |nvidia-driver-580-open\nun |nvidia-driver-595\nhi |nvidia-driver-580-server-x\n"'
    assert_eq "$(installed_driver_pkg)" "nvidia-driver-580-open"
    assert_eq "$(rc nvidia_driver_is nvidia-driver-580-open)" "0"
    assert_eq "$(nvidia_driver_is nvidia-driver-580 || true)" "설치됨: nvidia-driver-580-open / 강의 기준: nvidia-driver-580"
}

test_ws_unique_packages_finds_duplicates_and_respects_colcon_ignore() {
    _load
    mkdir -p ws/src/a ws/src/b ws/src/old/c
    printf '<package><name>foo</name></package>\n' > ws/src/a/package.xml
    printf '<package>\n  <name> bar </name>\n</package>\n' > ws/src/b/package.xml
    printf '<package><name>foo</name></package>\n' > ws/src/old/c/package.xml
    assert_contains "$(ws_unique_packages ws || true)" "foo:  a/package.xml  old/c/package.xml"
    touch ws/src/old/COLCON_IGNORE
    assert_eq "$(rc ws_unique_packages ws)" "0"
    assert_eq "$(rc ws_unique_packages nowhere)" "${RC_SKIP}"
}

test_ws_unique_packages_ignores_package_xml_nested_in_a_package() {
    _load
    mkdir -p ws/src/b/test/fixture
    printf '<package><name>x</name></package>\n' > ws/src/b/package.xml
    printf '<package><name>x</name></package>\n' > ws/src/b/test/fixture/package.xml
    assert_eq "$(rc ws_unique_packages ws)" "0"
}

test_ws_unique_packages_timeout_is_skip_not_pass() {
    _load
    mkdir -p ws/src
    stub find 'exit 124'
    assert_eq "$(rc ws_unique_packages ws)" "${RC_SKIP}"
}

test_ws_unique_packages_respects_colcon_ignore_in_src_root() {
    _load
    mkdir -p ws/src/a ws/src/b
    printf '<package><name>x</name></package>\n' | tee ws/src/a/package.xml > ws/src/b/package.xml
    touch ws/src/COLCON_IGNORE
    assert_eq "$(rc ws_unique_packages ws)" "0"
}
