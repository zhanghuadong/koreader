#!/usr/bin/env bash
set -eo pipefail
LOG="${HOME}/ko-build/build-android-arm.log"
mkdir -p "${HOME}/ko-build"
echo "=== $(date -Iseconds) full release build ===" >>"${LOG}"
cd /mnt/e/koreade
sed -i 's/\r$//' tools/ensure-test-submodule.sh tools/fetchthirdparty-wsl.sh 2>/dev/null || true
bash tools/fetchthirdparty-wsl.sh
bash tools/bootstrap-gettext-wsl.sh 2>/dev/null || true
bash tools/bootstrap-android-sdk-wsl.sh
source tools/ensure-gradle-wsl.sh
export PATH="/usr/bin:/usr/local/bin:${HOME}/ko-build/gettext/bin:${HOME}/.local/bin:/mnt/e/koreader/.build-venv/bin:/mnt/d/ko-toolchain/android-ndk-r23c/toolchains/llvm/prebuilt/linux-x86_64/bin:${HOME}/android-sdk-linux/platform-tools"
export LD_LIBRARY_PATH="${HOME}/ko-build/gettext/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export MAKEFLAGS=-j1 NINJAFLAGS=-j1 PARALLEL_JOBS=1
unset CI
export ANDROID_NDK_HOME=/mnt/d/ko-toolchain/android-ndk-r23c ANDROID_NDK_ROOT=/mnt/d/ko-toolchain/android-ndk-r23c
export ANDROID_HOME="${HOME}/android-sdk-linux" ANDROID_SDK_ROOT="${HOME}/android-sdk-linux"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-${HOME}/ko-build/gradle-user-home}"
export OUTPUT_DIR="${HOME}/ko-build/koreader-base" INSTALL_DIR="${HOME}/ko-build/koreader-install"
if ! mkdir -p "${OUTPUT_DIR}" 2>/dev/null; then
  export GRADLE_USER_HOME="/mnt/d/ko-build/gradle-user-home"
  export OUTPUT_DIR="/mnt/d/ko-build/koreader-base"
  export INSTALL_DIR="/mnt/d/ko-build/koreader-install"
  mkdir -p "${GRADLE_USER_HOME}" "${OUTPUT_DIR}" "${INSTALL_DIR}"
fi
if ! command -v msgfmt >/dev/null; then
  echo "Missing msgfmt. In WSL run: sudo apt install -y gettext (or re-run after tools/bootstrap-gettext-wsl.sh)" | tee -a "${LOG}"
  exit 1
fi
exec ./kodev release -i android-arm >>"${LOG}" 2>&1
