#!/usr/bin/env bash
# Force rebuild crengine after corrupt zero-byte lvtinydom.cpp.o (undefined ldomNode symbols).
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if mkdir -p "${HOME}/ko-build/.probe" 2>/dev/null; then
  BASE="${HOME}/ko-build/koreader-base"
else
  BASE="/mnt/d/ko-build/koreader-base"
fi
CRE="${BASE}/thirdparty/crengine/build"
LVTO="${CRE}/CMakeFiles/crengine.dir/crengine/src/lvtinydom.cpp.o"
rm -f "${LVTO}" "${CRE}/libcrengine.a"
find "${BASE}" -path '*koreader-monolibtic*' \( -name '*.so' -o -name '*.o' -o -name 'build.stamp' \) -delete 2>/dev/null || true
echo "[*] Removed corrupt crengine artifacts under ${BASE}"
unset ANDROID_SDK_LINUX ANDROID_HOME ANDROID_SDK_ROOT CI
exec "${ROOT}/tools/build-android-arm-signed.sh"
