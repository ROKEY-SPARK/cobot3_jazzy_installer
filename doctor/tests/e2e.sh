#!/usr/bin/env bash
# shellcheck disable=SC2016  # break_it 안의 $d 등은 컨테이너 셸이 펼친다
# tests/e2e.sh · 설치기 Docker 이미지 안에서 진단기 실행 (docker · 이미지 필요, 네트워크 불필요)
#   성공 경로 = 설치가 끝난 이미지 → 강의 지정 · 자동 감지 둘 다 FAIL 0 (종료 코드 0)
#   실패 경로 = 같은 이미지에서 흔한 고장을 일부러 만든 뒤 → 종료 코드 2 + 해당 FAIL 줄
#   사용: bash tests/e2e.sh [cobot1|cobot3|intel1 ...]  (생략 = 셋 다)
#   이미지 = 설치기 저장소 docker/build.sh 산출물 rokey/jazzy-<course>:latest
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${IMAGE_PREFIX:=rokey/jazzy-}"
# 컨테이너 = 커널 · GPU · docker 데몬 · Isaac Sim 본체가 없는 환경 (설치기 이미지 빌드 게이트와 같은 범위)
readonly FLAGS=(--no-host --no-gpu --no-docker --no-isaac)
PASS=0
FAIL=0

# in_image <course> <셸 명령> · 진단기를 읽기 전용으로 붙여 실행. 출력 마지막 줄 = RC=<종료 코드>
in_image() {
    docker run --rm -i -u rokey -v "${ROOT}:/doctor:ro" "${IMAGE_PREFIX}$1:latest" \
        bash -c "$2; echo RC=\$?" 2>&1
}

expect() {
    local name="$1" out="$2" rc="$3"; shift 3
    local ok=1 want
    grep -qx "RC=${rc}" <<<"${out}" || ok=0
    for want in "$@"; do grep -qF -- "${want}" <<<"${out}" || ok=0; done
    if [[ ${ok} == 1 ]]; then
        PASS=$((PASS + 1)); echo "  ok   ${name}"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL ${name} (기대 RC=${rc}, 문구: $*)"; grep -E 'FAIL|RC=|강의' <<<"${out}" | sed 's/^/       | /'
    fi
}

e2e_course() {
    local c="$1" out
    docker image inspect "${IMAGE_PREFIX}${c}:latest" >/dev/null 2>&1 || { echo "  skip ${c}: 이미지 없음"; return 0; }
    echo "== ${c}"
    out="$(in_image "${c}" "bash /doctor/doctor.sh ${c} ${FLAGS[*]}")"
    expect "${c} 설치 완료 이미지 = FAIL 0" "${out}" 0 "FAIL 0"
    out="$(in_image "${c}" "bash /doctor/doctor.sh ${FLAGS[*]}")"
    expect "${c} 자동 감지" "${out}" 0 "강의 (자동 감지): ${c}"

    # 흔한 고장 셋: 다른 distro source · pip 로 올라간 numpy 2 · 중단된 설치 기록
    local break_it='echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
        d="$(python3 -c "import site; print(site.getusersitepackages())")/numpy"; mkdir -p "$d"
        echo "__version__ = \"2.1.0\"" > "$d/__init__.py"
        mkdir -p ~/.rokey_jazzy_installer; echo "step_x=FAIL" >> ~/.rokey_jazzy_installer/'"${c}"'.state'
    out="$(in_image "${c}" "${break_it}; bash /doctor/doctor.sh ${c} ${FLAGS[*]}")"
    expect "${c} 고장 3종 감지" "${out}" 2 \
        "[FAIL] ~/.bashrc 가 jazzy 외 ROS 를 source 하지 않음" \
        "[FAIL] 시스템 python numpy 1.x" \
        "[FAIL] 설치기 진행 기록에 실패 · 중단 단계 없음"
}

courses=("$@")
[[ ${#courses[@]} -gt 0 ]] || courses=(cobot1 cobot3 intel1)
command -v docker >/dev/null || { echo "e2e: docker 없음" >&2; exit 2; }
for c in "${courses[@]}"; do e2e_course "${c}"; done
echo "---- ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] || exit 1
