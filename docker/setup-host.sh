#!/usr/bin/env bash
# =============================================================
#  ROKEY 협동3 (cobot3) Jazzy Installer
# =============================================================
#
# docker/setup-host.sh · 강의 컨테이너를 돌릴 호스트 준비 (Docker 엔진 + NVIDIA Container Toolkit)
#   사용: bash docker/setup-host.sh [--yes]
#   NVIDIA 드라이버는 따로 필요 (bash install.sh 의 NVIDIA 단계, 또는 이미 설치된 드라이버)
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=resources/config.sh
source "${ROOT}/resources/config.sh"
# shellcheck source=resources/lib.sh
source "${ROOT}/resources/lib.sh"

case "${1:-}" in
    -y|--yes) export ASSUME_YES=1 ;;
    -h|--help) sed -n '6,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) die "${EXIT_USER}" "setup-host: unknown option $1" ;;
esac
[[ "${EUID}" -ne 0 ]] || die "${EXIT_USER}" "run as your user (sudo is called when needed)."
confirm_or_abort "Install Docker Engine + NVIDIA Container Toolkit on this host (restarts the docker daemon)?"
sudo_prime
bash "${ROOT}/resources/base.sh" docker || exit "${EXIT_SYSTEM}"
bash "${ROOT}/resources/base.sh" toolkit || exit "${EXIT_SYSTEM}"
echo "setup-host: done. Re-login once so the docker group applies, then: bash docker/build.sh"
