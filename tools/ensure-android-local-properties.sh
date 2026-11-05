#!/usr/bin/env bash
# Gradle must use Linux SDK in WSL (not D:\android_sdk with only .exe tools).
set -eo pipefail

_ensure_fail() {
  echo "$1" >&2
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 1
  fi
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_DIR="${1:-${ROOT}/platform/android/luajit-launcher}"

# shellcheck source=/dev/null
source "${ROOT}/tools/bootstrap-android-sdk-wsl.sh"

if [[ -n "${ANDROID_SDK_LINUX:-}" && -x "${ANDROID_SDK_LINUX}/build-tools/34.0.0/aapt" ]]; then
  SDK="${ANDROID_SDK_LINUX}"
elif [[ -x "/mnt/d/ko-build/android-sdk-linux/build-tools/34.0.0/aapt" ]]; then
  SDK="/mnt/d/ko-build/android-sdk-linux"
elif [[ -n "${ANDROID_HOME:-}" && -x "${ANDROID_HOME}/build-tools/34.0.0/aapt" ]]; then
  SDK="${ANDROID_HOME}"
elif [[ -x "${HOME}/android-sdk-linux/build-tools/34.0.0/aapt" ]]; then
  SDK="${HOME}/android-sdk-linux"
else
  SDK="/mnt/d/ko-build/android-sdk-linux"
fi
if [[ ! -x "${SDK}/build-tools/34.0.0/aapt" ]]; then
  _ensure_fail "Missing Linux aapt in ${SDK}; run: bash tools/bootstrap-android-sdk-wsl.sh"
fi

# Gradle sdk.dir (forward slashes).
sdk_dir="${SDK//\\//}"
printf 'sdk.dir=%s\n' "${sdk_dir}" >"${LAUNCHER_DIR}/local.properties"
export ANDROID_HOME="${SDK}"
export ANDROID_SDK_ROOT="${SDK}"
echo "[*] Wrote ${LAUNCHER_DIR}/local.properties -> ${sdk_dir}"
