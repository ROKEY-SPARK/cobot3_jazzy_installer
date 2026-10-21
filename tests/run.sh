#!/usr/bin/env bash
# tests/run.sh · 단위 테스트 실행기 (외부 의존 없음, 네트워크·sudo 불필요)
#   사용: bash tests/run.sh            → tests/test_*.sh 전부
#         bash tests/run.sh test_lib   → 지정 파일만
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export INSTALLER_ROOT
PASS=0
FAIL=0
FAILED=()

# 각 테스트 = 새 서브셸 + 격리된 HOME (실제 ~/.bashrc · state 를 건드리지 않음)
#   서브셸을 if 조건 · || 목록에 두지 않는다 — 그 문맥에서는 안쪽 set -e 가 무시되어 실패가 묻힌다
run_case() {
    local file="$1" fn="$2" tmp rc=0
    tmp="$(mktemp -d)"
    ( set -e
      export HOME="${tmp}/home" STATE_DIR="${tmp}/state" LOG_FILE="${tmp}/log" BASHRC="${tmp}/home/.bashrc"
      mkdir -p "${HOME}"
      cd "${tmp}"
      # shellcheck source=/dev/null
      source "${file}"
      "${fn}" ) >"${tmp}/out" 2>&1
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        PASS=$((PASS + 1)); echo "  ok   ${fn}"
    else
        FAIL=$((FAIL + 1)); FAILED+=("${fn}"); echo "  FAIL ${fn}"; sed 's/^/       | /' "${tmp}/out"
    fi
    rm -rf "${tmp}"
}

assert_eq() {
    [[ "$1" == "$2" ]] || { echo "assert_eq failed: expected [$2] got [$1] ${3:-}"; return 1; }
}
assert_contains() {
    grep -qF -- "$2" <<<"$1" || { echo "assert_contains failed: [$2] not in output:"; echo "$1"; return 1; }
}
export -f assert_eq assert_contains

files=()
if [[ $# -gt 0 ]]; then
    for a in "$@"; do files+=("${TEST_DIR}/${a%.sh}.sh"); done
else
    files=("${TEST_DIR}"/test_*.sh)
fi

for f in "${files[@]}"; do
    echo "== $(basename "${f}")"
    while read -r fn; do run_case "${f}" "${fn}"; done < <(grep -oE '^test_[a-z0-9_]+' "${f}")
done

echo "---- ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] || { printf '  - %s\n' "${FAILED[@]}"; exit 1; }
