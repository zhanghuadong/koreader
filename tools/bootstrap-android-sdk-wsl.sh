#!/usr/bin/env bash
# Linux Android SDK for Gradle in WSL (D:\android_sdk is Windows-only .exe).
set -eo pipefail

# Pick a Linux SDK tree that actually has aapt (ignore stale ANDROID_SDK_LINUX / ANDROID_HOME).
_sdk_aapt() { [[ -x "$1/build-tools/34.0.0/aapt" ]]; }
if _sdk_aapt "/mnt/d/ko-build/android-sdk-linux"; then
  SDK="/mnt/d/ko-build/android-sdk-linux"
elif _sdk_aapt "${HOME}/android-sdk-linux"; then
  SDK="${HOME}/android-sdk-linux"
elif [[ -n "${ANDROID_SDK_LINUX:-}" ]] && _sdk_aapt "${ANDROID_SDK_LINUX}"; then
  SDK="${ANDROID_SDK_LINUX}"
elif [[ -n "${ANDROID_HOME:-}" ]] && _sdk_aapt "${ANDROID_HOME}"; then
  SDK="${ANDROID_HOME}"
else
  SDK="/mnt/d/ko-build/android-sdk-linux"
  if [[ -n "${ANDROID_SDK_LINUX:-}" ]] && ! _sdk_aapt "${ANDROID_SDK_LINUX}"; then
    echo "[*] Ignoring ANDROID_SDK_LINUX=${ANDROID_SDK_LINUX} (no Linux aapt); using ${SDK}" >&2
  fi
fi
MARK="${SDK}/.koreader-bootstrap-ok"
export ANDROID_SDK_LINUX="${SDK}"

if [[ -x "${SDK}/build-tools/34.0.0/aapt" ]]; then
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
  fi
  exit 0
fi

mkdir -p "${SDK}/cmdline-tools"
if [[ ! -x "${SDK}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  tmp="/mnt/d/ko-build/tmp/cmdline-bootstrap"
  rm -rf "${tmp}"
  mkdir -p "${tmp}"
  curl -fsSL --connect-timeout 120 --retry 3 \
    -o "${tmp}/cmdline.zip" \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -q "${tmp}/cmdline.zip" -d "${tmp}"
  rm -rf "${SDK}/cmdline-tools/latest"
  mv "${tmp}/cmdline-tools" "${SDK}/cmdline-tools/latest"
  rm -rf "${tmp}"
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
set +o pipefail
yes | "${SDK}/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${SDK}" \
  "platform-tools" \
  "build-tools;34.0.0" \
  "platforms;android-30" \
  "platforms;android-34" \
  >/dev/null || true
set -o pipefail

touch "${MARK}"
echo "Linux SDK ready: ${SDK}"
