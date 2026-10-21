#!/usr/bin/env bash
# tests/e2e.sh · install.sh 전체 흐름을 깨끗한 컨테이너 안에서 실행 (호스트는 바꾸지 않음)
#   성공 경로 = Isaac Sim stub zip 으로 전 단계 → verify 통과 → 재실행 시 전부 skip
#              stub = isaacsim 단계가 보는 것만 든 작은 zip (VERSION · isaac-sim.sh · python.sh · post_install.sh)
#              → 압축 해제 · post_install · 버전 확인 흐름만 검증. 실제 Isaac Sim 실행은 검증하지 않음
#   실패 경로 = Isaac Sim zip 없음 → 종료 코드 2 + isaacsim=FAIL 기록 + 안내 메시지
#   전제 = rokey/jazzy-base 이미지 (bash docker/build.sh 가 만듦) · 호스트 docker 소켓
#   사용: bash tests/e2e.sh [success|failure|all]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${E2E_IMAGE:-rokey/jazzy-base:latest}"
which="${1:-all}"
rc_total=0

# 저장소를 읽기 전용으로 마운트 → 컨테이너 안에서 사본을 만들어 실행 (install_log 가 저장소에 안 남음)
#   컨테이너도 /sys 로 호스트 GPU 를 본다 → GPU 를 주지 않으면 verify 의 nvidia-smi 점검이 실패
run_in_container() {
    local -a gpu=()
    docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' && gpu=(--gpus all)
    docker run --rm -i -u rokey "${gpu[@]}" -v "${ROOT}:/src:ro" \
        "${IMAGE}" bash -c "cp -r /src ~/installer && cd ~/installer && $1"
}

# shellcheck disable=SC2016  # 컨테이너 안의 셸이 펼칠 식
STUB_ZIP='
    mkdir -p /tmp/stub && cd /tmp/stub
    echo "5.1.0-e2e-stub" > VERSION
    for f in isaac-sim.sh python.sh post_install.sh; do printf "#!/bin/bash\nexit 0\n" > "$f"; chmod +x "$f"; done
    sudo apt-get update -qq && sudo apt-get install -y -qq zip >/dev/null
    zip -q /tmp/isaac-stub.zip VERSION isaac-sim.sh python.sh post_install.sh && cd ~/installer'

e2e_success() {
    echo "== e2e success: bash install.sh (Isaac Sim stub zip) + rerun"
    local out rc
    # shellcheck disable=SC2016
    out="$(run_in_container "${STUB_ZIP}"'
        F="--yes --no-nvidia --no-kernel-hold --isaac-zip /tmp/isaac-stub.zip --domain-id 10"
        bash install.sh $F; echo "RC1=$?"
        bash install.sh $F; echo "RC2=$?"
        grep -c "^# >>> rokey cobot3 >>>$" ~/.bashrc | sed "s/^/BLOCKS=/"
        grep -cE "^ +export ROS_DOMAIN_ID=10$" ~/.bashrc | sed "s/^/DOMAIN_LINES=/"
        bash install.sh --status' 2>&1)"; rc=$?
    grep -E '^(RC[12]|BLOCKS|DOMAIN_LINES)=' <<<"${out}"
    echo "${out}" | tail -25
    grep -q '^RC1=0$' <<<"${out}" || { echo "FAIL: first run did not exit 0"; return 1; }
    grep -q '^RC2=0$' <<<"${out}" || { echo "FAIL: rerun did not exit 0"; return 1; }
    grep -q 'skip: isaac_ros_ws (already DONE)' <<<"${out}" || { echo "FAIL: rerun did not skip finished steps"; return 1; }
    grep -q '^BLOCKS=1$' <<<"${out}" || { echo "FAIL: bashrc block duplicated or missing"; return 1; }
    # isaac_ros · jazzy 두 함수가 각각 ROS_DOMAIN_ID 를 export → 2줄
    grep -q '^DOMAIN_LINES=2$' <<<"${out}" || { echo "FAIL: --domain-id not written to both functions"; return 1; }
    grep -q -- '---- [0-9]* passed, 0 failed' <<<"${out}" || { echo "FAIL: verify did not pass"; return 1; }
    echo "PASS e2e success (container rc ${rc})"
}

e2e_failure() {
    echo "== e2e failure: bash install.sh without the Isaac Sim zip"
    local out
    # shellcheck disable=SC2016
    out="$(run_in_container '
        bash install.sh --yes --no-nvidia --no-kernel-hold; echo "RC=$?"
        bash install.sh --status
        grep -h "isaacsim:" "${LOG_FILE:-install_log}" | tail -1' 2>&1)"
    echo "${out}" | tail -25
    grep -q '^RC=2$' <<<"${out}" || { echo "FAIL: expected exit code 2"; return 1; }
    grep -q '^step_isaacsim=FAIL$' <<<"${out}" || { echo "FAIL: isaacsim not recorded as FAIL"; return 1; }
    grep -q -- '--isaac-zip PATH or --isaac-download' <<<"${out}" || { echo "FAIL: no actionable message in log"; return 1; }
    grep -q '^step_ros2_jazzy=DONE$' <<<"${out}" || { echo "FAIL: earlier steps not recorded DONE"; return 1; }
    echo "PASS e2e failure"
}

case "${which}" in
    success) e2e_success || rc_total=1 ;;
    failure) e2e_failure || rc_total=1 ;;
    all) e2e_success || rc_total=1; e2e_failure || rc_total=1 ;;
    *) echo "usage: bash tests/e2e.sh [success|failure|all]" >&2; exit 1 ;;
esac
exit "${rc_total}"
