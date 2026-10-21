#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# docker/run.sh · 협동3 컨테이너 실행 (X11 GUI · GPU · 호스트 네트워크)
#   사용: bash docker/run.sh cobot3 [명령...]           ROS 쪽 (Nav2 · rviz2 · colcon), 기본 명령 = bash
#         bash docker/run.sh isaac-sim [--gui]           공식 Isaac Sim 5.1.0 컨테이너
#   작업 폴더 = 호스트 ~/rokey_docker/<cobot3|isaac-sim> ↔ 컨테이너 (컨테이너를 지워도 남음)
#   네트워크 = host → 같은 ROS_DOMAIN_ID 의 호스트·로봇·다른 컨테이너와 그대로 통신
set -euo pipefail

: "${IMAGE_PREFIX:=rokey/jazzy}"
: "${ISAACSIM_IMAGE:=nvcr.io/nvidia/isaac-sim:5.1.0}"
: "${WORK_ROOT:=${HOME}/rokey_docker}"

usage() {
    sed -n '7,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

[[ $# -ge 1 ]] || { usage >&2; exit 1; }
course="$1"; shift
case "${course}" in
    cobot3|isaac-sim) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac

args=(--rm --network host --ipc host -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}")
# TTY 가 있을 때만 -t (스크립트·CI 에서 호출해도 "not a TTY" 로 죽지 않게)
if [[ -t 0 ]]; then args+=(-it); else args+=(-i); fi

# GPU = nvidia runtime 이 등록된 호스트에서만
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    args+=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all)
else
    echo "run: no nvidia runtime in docker — starting without GPU (bash docker/setup-host.sh adds it)." >&2
fi

# X11 = 컨테이너 사용자 uid 1000 → 같은 uid 의 호스트 사용자만 허용, 아니면 local 전체 허용
if [[ -n "${DISPLAY:-}" ]] && command -v xhost >/dev/null; then
    if [[ "$(id -u)" == 1000 ]]; then xhost "+SI:localuser:$(id -un)" >/dev/null; else xhost +local: >/dev/null; fi
    args+=(-e DISPLAY -e QT_X11_NO_MITSHM=1 -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
fi

case "${course}" in
    isaac-sim)
        # 공식 이미지 = 사용자 isaac-sim (uid 1234), entrypoint runheadless.sh (WebRTC 스트리밍)
        #   --gui = runapp.sh (로컬 창, 에셋 서버 경로 포함)
        # 캐시 폴더는 이미지에 없음 → named volume 이 root 소유로 생겨 쓰기 실패 → 먼저 소유권 지정
        local_vols=(cache:/isaac-sim/.cache computecache:/isaac-sim/.nv/ComputeCache
                    logs:/isaac-sim/.nvidia-omniverse/logs data:/isaac-sim/.local/share/ov/data
                    pkg:/isaac-sim/.local/share/ov/pkg)
        init=(--rm -u 0 --entrypoint chown)
        for v in "${local_vols[@]}"; do
            args+=(-v "isaac-sim-${v%%:*}:${v#*:}")
            init+=(-v "isaac-sim-${v%%:*}:${v#*:}")
        done
        docker run "${init[@]}" "${ISAACSIM_IMAGE}" 1234:1234 "${local_vols[@]#*:}"
        mkdir -p "${WORK_ROOT}/isaac-sim/isaacpjt"
        args+=(-e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp
               -v "${WORK_ROOT}/isaac-sim/isaacpjt:/isaac-sim/isaacpjt")
        if [[ "${1:-}" == --gui ]]; then
            shift
            # 컨테이너 uid 1234 ≠ 호스트 사용자 → X 서버 접근은 local 전체 허용 필요
            [[ -n "${DISPLAY:-}" ]] && command -v xhost >/dev/null && xhost +local: >/dev/null
            args+=(--entrypoint /isaac-sim/runapp.sh)
        fi
        exec docker run "${args[@]}" "${ISAACSIM_IMAGE}" "$@"
        ;;
esac

mkdir -p "${WORK_ROOT}/${course}"
args+=(-v "${WORK_ROOT}/${course}:/home/rokey/work" --name "rokey-${course}-$$")
exec docker run "${args[@]}" "${IMAGE_PREFIX}-${course}:latest" "${@:-bash}"
