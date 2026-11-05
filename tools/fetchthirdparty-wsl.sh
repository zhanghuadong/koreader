#!/usr/bin/env bash
# fetchthirdparty for WSL / offline-friendly (no github git for test-data).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

git submodule sync --recursive

# Shallow only (never test — it is handled offline below).
git submodule update --jobs 3 --depth 1 --init l10n resources/fonts

git submodule update --jobs 3 --init base platform/android/luajit-launcher

bash "${ROOT}/tools/ensure-test-submodule.sh"

echo "[*] fetchthirdparty done"
