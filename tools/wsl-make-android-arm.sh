#!/usr/bin/env bash
# make update/release with NDK on PATH (avoids armv7a-*-clang not found).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

bash "${ROOT}/tools/bootstrap-gettext-wsl.sh" 2>/dev/null || true
bash "${ROOT}/tools/bootstrap-android-sdk-wsl.sh"
export PATH="/usr/bin:/usr/local/bin:${HOME}/ko-build/gettext/bin:${HOME}/.local/bin:${ROOT}/.build-venv/bin:/mnt/d/ko-toolchain/android-ndk-r23c/toolchains/llvm/prebuilt/linux-x86_64/bin:${HOME}/android-sdk-linux/platform-tools"
export LD_LIBRARY_PATH="${HOME}/ko-build/gettext/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export ANDROID_NDK_HOME=/mnt/d/ko-toolchain/android-ndk-r23c
export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME}"
export ANDROID_HOME="${HOME}/android-sdk-linux"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export OUTPUT_DIR="${OUTPUT_DIR:-${HOME}/ko-build/koreader-base}"
export INSTALL_DIR="${INSTALL_DIR:-${HOME}/ko-build/koreader-install}"
export MAKEFLAGS=-j1
export NINJAFLAGS=-j1
export PARALLEL_JOBS=1
unset CI

if ! command -v msgfmt >/dev/null; then
  echo "Missing msgfmt. Run in WSL: sudo apt install -y gettext" >&2
  exit 1
fi

for f in ensure-test-submodule.sh fetchthirdparty-wsl.sh bootstrap-gettext-wsl.sh; do
  sed -i 's/\r$//' "${ROOT}/tools/${f}" 2>/dev/null || true
done
make TARGET= KODEBUG= VERBOSE= fetchthirdparty
exec make "$@"
