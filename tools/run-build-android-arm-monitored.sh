#!/usr/bin/env bash
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if mkdir -p "${HOME}/ko-build/.probe" 2>/dev/null; then
  LOG="${HOME}/ko-build/build-android-arm.log"
else
  LOG="/mnt/d/ko-build/build-android-arm.log"
  mkdir -p /mnt/d/ko-build
fi
echo "=== $(date -Iseconds) monitored build start ===" | tee -a "${LOG}"
unset ANDROID_SDK_LINUX ANDROID_HOME ANDROID_SDK_ROOT CI
sed -i 's/\r$//' "${ROOT}/tools/"*.sh 2>/dev/null || true
exec "${ROOT}/tools/build-android-arm-signed.sh" >>"${LOG}" 2>&1
