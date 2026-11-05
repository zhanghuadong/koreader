#!/usr/bin/env bash
# Ensure koreader/test at the superproject gitlink (offline via codeload.github.com).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

TEST_REV="$(git ls-tree HEAD test | awk '{print $3}')"
[[ -n "${TEST_REV}" ]] || { echo "no test gitlink in HEAD" >&2; exit 1; }

if git submodule status test 2>/dev/null | grep -qE "^ ${TEST_REV} "; then
  exit 0
fi
if [[ -d test ]] && cur="$(git -C test rev-parse HEAD 2>/dev/null)" && [[ "${cur}" == "${TEST_REV}" ]]; then
  exit 0
fi

echo "[*] Restoring test/ (${TEST_REV}) from codeload.github.com ..."
git submodule deinit -f test 2>/dev/null || true
rm -rf test "${ROOT}/.git/modules/test"

tmp="$(mktemp -d)"
cleanup() { rm -rf "${tmp}"; }
trap cleanup EXIT

curl -fsSL --connect-timeout 60 --retry 3 \
  "https://codeload.github.com/koreader/test-data/tar.gz/${TEST_REV}" \
  -o "${tmp}/test.tar.gz"
tar xzf "${tmp}/test.tar.gz" -C "${tmp}"
src="$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | head -1)"
[[ -d "${src}" ]] || { echo "extract failed" >&2; exit 1; }

mkdir -p .git/modules/test
git init -q .git/modules/test
mv "${src}" test
echo "gitdir: ../.git/modules/test" > test/.git
git config -f .git/config submodule.test.active true
git config -f .git/config submodule.test.url https://github.com/koreader/test-data.git

git --git-dir=.git/modules/test --work-tree=test add -A
git --git-dir=.git/modules/test --work-tree=test \
  -c user.email=build@local -c user.name=build \
  commit -q -m "import test-data ${TEST_REV}"

git config submodule.test.update none
echo "[*] test/ restored; submodule.test.update=none (skip network fetch)"
