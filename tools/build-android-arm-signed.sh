#!/usr/bin/env bash
# Signed 32-bit KOReader APK (android-arm / armeabi-v7a), platform keystore in luajit-launcher/app/
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

unset ANDROID_SDK_LINUX ANDROID_HOME ANDROID_SDK_ROOT

for f in bootstrap-gettext-wsl.sh fetchthirdparty-wsl.sh ensure-test-submodule.sh; do
  sed -i 's/\r$//' "${ROOT}/tools/${f}" 2>/dev/null || true
done
bash "${ROOT}/tools/bootstrap-gettext-wsl.sh" 2>/dev/null || true
bash "${ROOT}/tools/fetchthirdparty-wsl.sh"
unset CI
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/mnt/d/ko-toolchain/android-ndk-r23c}"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
if mkdir -p "${HOME}/ko-build/.probe" 2>/dev/null; then
  export OUTPUT_DIR="${OUTPUT_DIR:-${HOME}/ko-build/koreader-base}"
  export INSTALL_DIR="${INSTALL_DIR:-${HOME}/ko-build/koreader-install}"
  GETTEXT_BIN="${HOME}/ko-build/gettext/bin"
  GETTEXT_LIB="${HOME}/ko-build/gettext/lib"
else
  export OUTPUT_DIR="/mnt/d/ko-build/koreader-base"
  export INSTALL_DIR="/mnt/d/ko-build/koreader-install"
  GETTEXT_BIN="/mnt/d/ko-build/gettext/bin"
  GETTEXT_LIB="/mnt/d/ko-build/gettext/lib"
fi
mkdir -p "${OUTPUT_DIR}" "${INSTALL_DIR}"
export PATH="/usr/bin:/usr/local/bin:${GETTEXT_BIN}:${HOME}/.local/bin:${ROOT}/.build-venv/bin:/mnt/d/ko-toolchain/android-ndk-r23c/toolchains/llvm/prebuilt/linux-x86_64/bin"
export LD_LIBRARY_PATH="${GETTEXT_LIB}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# shellcheck source=/dev/null
source "${ROOT}/tools/ensure-android-local-properties.sh"
# shellcheck source=/dev/null
source "${ROOT}/tools/ensure-gradle-wsl.sh"
mkdir -p "${GRADLE_USER_HOME}"
if [[ -z "${ANDROID_HOME:-}" ]]; then
  ANDROID_HOME="$(grep '^sdk.dir=' "${ROOT}/platform/android/luajit-launcher/local.properties" | cut -d= -f2-)"
  export ANDROID_HOME ANDROID_SDK_ROOT
fi
: "${ANDROID_HOME:?ensure-android-local-properties.sh did not set ANDROID_HOME (bootstrap Linux SDK under /mnt/d/ko-build/android-sdk-linux)}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export PATH="$(echo "${PATH}" | tr ':' '\n' | grep -v '/mnt/d/android_sdk' | paste -sd: -)"
export PATH="${ANDROID_HOME}/platform-tools:${PATH}"
export GRADLE_FLAGS="${GRADLE_FLAGS:--x lintVitalArmRocksRelease -x lintVitalReportArmRocksRelease}"
export PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
export NINJAFLAGS="${NINJAFLAGS:--j1}"
export MAKEFLAGS="${MAKEFLAGS:--j1}"

if ! command -v clang >/dev/null; then
  echo "Install host clang (needed for LuaJIT minilua): sudo apt install -y clang gcc-multilib pkg-config"
  exit 1
fi

if ! command -v msgfmt >/dev/null; then
  echo "Install gettext (l10n .mo files): sudo apt install -y gettext"
  exit 1
fi

if [[ ! -f platform/android/luajit-launcher/app/platform.keystore ]]; then
  echo "Missing platform.keystore — copy from WeWallPaper app/platform.keystore"
  exit 1
fi

exec ./kodev release -i android-arm "$@"
