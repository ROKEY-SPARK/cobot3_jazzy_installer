#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# docker/build.sh · 협동3 ROS 이미지 빌드 (base → cobot3 순서)
#   사용: bash docker/build.sh [--no-cache]
#   태그 = rokey/jazzy-base · rokey/jazzy-cobot3 의 :latest + :<git short SHA> (재현 추적용)
#   각 이미지 마지막 단계에서 resources/verify.sh 가 돌아 실패하면 이미지가 만들어지지 않음
#   UBUNTU_MIRROR = apt 미러. 비우면 호스트 /etc/apt 설정에서 찾아 씀 (예: kr.archive.ubuntu.com)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
: "${IMAGE_PREFIX:=rokey/jazzy}"

usage() { echo "usage: bash docker/build.sh [--no-cache]"; }

# 호스트가 쓰는 ubuntu 미러 (deb822 형식 우선, 없으면 sources.list)
host_mirror() {
    grep -hoE 'https?://[a-z0-9.-]*archive\.ubuntu\.com/ubuntu/?' \
        /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null | head -n1 || true
}

build_one() {
    local name="$1" rev="$2"; shift 2
    echo "== building ${IMAGE_PREFIX}-${name} (rev ${rev})"
    docker build "$@" \
        -f "${SCRIPT_DIR}/images/${name}.Dockerfile" \
        --label "org.opencontainers.image.revision=${rev}" \
        -t "${IMAGE_PREFIX}-${name}:latest" -t "${IMAGE_PREFIX}-${name}:${rev}" \
        "${ROOT}" || exit 2
}

extra=()
for a in "$@"; do
    case "${a}" in
        cobot3) ;;   # 예전 형식 (bash docker/build.sh cobot3) 호환
        --no-cache) extra+=(--no-cache) ;;
        -h|--help) usage; exit 0 ;;
        *) echo "build: unknown option ${a}" >&2; usage >&2; exit 1 ;;
    esac
done
command -v docker >/dev/null || { echo "build: docker not found — run 'bash docker/setup-host.sh' first." >&2; exit 1; }

rev="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo nogit)"
# 커밋 안 된 수정이 있으면 표시 → 같은 태그가 다른 내용을 가리키지 않게
if [[ "${rev}" != nogit && -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]]; then rev="${rev}-dirty"; fi
mirror="${UBUNTU_MIRROR:-$(host_mirror)}"
[[ -n "${mirror}" ]] && echo "build: apt mirror ${mirror}"
build_one base "${rev}" "${extra[@]}" --build-arg "UBUNTU_MIRROR=${mirror}"
build_one cobot3 "${rev}" "${extra[@]}" --build-arg "BASE_IMAGE=${IMAGE_PREFIX}-base:latest"
docker images --filter "reference=${IMAGE_PREFIX}-*"
