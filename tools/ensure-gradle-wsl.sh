#!/usr/bin/env bash
# Reuse Windows Gradle wrapper cache or a local zip (no download from services.gradle.org).
set -eo pipefail

GRADLE_VER="${GRADLE_VER:-8.6}"
DIST_NAME="gradle-${GRADLE_VER}-bin"

win_user="${WIN_USER:-${USER:-zhang}}"
WIN_GRADLE="/mnt/c/Users/${win_user}/.gradle"
LOCAL_ZIP="/mnt/d/ko-build/${DIST_NAME}.zip"

resolve_dist_hash() {
  local home="$1"
  if [[ -n "${GRADLE_DIST_HASH:-}" ]]; then
    echo "${GRADLE_DIST_HASH}"
    return 0
  fi
  local base="${home}/wrapper/dists/${DIST_NAME}"
  if [[ -d "${base}" ]]; then
    local d name
    for d in "${base}"/*/; do
      [[ -d "${d}" ]] || continue
      name="$(basename "${d}")"
      if [[ -x "${d}${DIST_NAME}/bin/gradle" ]]; then
        echo "${name}"
        return 0
      fi
    done
    for d in "${base}"/*/; do
      [[ -d "${d}" ]] || continue
      echo "$(basename "${d}")"
      return 0
    done
  fi
  echo ""
}

gradle_ready() {
  local home="$1" hash="$2"
  [[ -n "${hash}" && -x "${home}/wrapper/dists/${DIST_NAME}/${hash}/${DIST_NAME}/bin/gradle" ]]
}

pick_gradle_home() {
  local h hash
  hash="$(resolve_dist_hash "${WIN_GRADLE}")"
  if gradle_ready "${WIN_GRADLE}" "${hash}"; then
    echo "${WIN_GRADLE}"
    return 0
  fi
  if [[ -n "${GRADLE_USER_HOME:-}" ]]; then
    hash="$(resolve_dist_hash "${GRADLE_USER_HOME}")"
    if gradle_ready "${GRADLE_USER_HOME}" "${hash}"; then
      echo "${GRADLE_USER_HOME}"
      return 0
    fi
  fi
  echo "/mnt/d/ko-build/gradle-user-home"
}

install_from_zip() {
  local home="$1" zip="$2" hash="$3"
  local dest="${home}/wrapper/dists/${DIST_NAME}/${hash}"
  mkdir -p "${dest}"
  if [[ -f "${dest}/${DIST_NAME}.zip.ok" ]] && [[ -x "${dest}/${DIST_NAME}/bin/gradle" ]]; then
    return 0
  fi
  echo "[*] Installing Gradle ${GRADLE_VER} from ${zip} -> ${dest}"
  cp -f "${zip}" "${dest}/${DIST_NAME}.zip"
  (cd "${dest}" && unzip -qo "${DIST_NAME}.zip" && touch "${DIST_NAME}.zip.ok")
}

GRADLE_USER_HOME="$(pick_gradle_home)"
export GRADLE_USER_HOME
DIST_HASH="$(resolve_dist_hash "${GRADLE_USER_HOME}")"

if gradle_ready "${GRADLE_USER_HOME}" "${DIST_HASH}"; then
  echo "[*] Gradle ${GRADLE_VER} OK (GRADLE_USER_HOME=${GRADLE_USER_HOME})"
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
  fi
  exit 0
fi

if [[ -f "${LOCAL_ZIP}" ]]; then
  if [[ -z "${DIST_HASH}" ]]; then
    echo "Set GRADLE_DIST_HASH to match wrapper (see ${WIN_GRADLE}/wrapper/dists/${DIST_NAME}/)" >&2
    echo "Or run gradlew once on Windows so the hash folder is created." >&2
    exit 1
  fi
  install_from_zip "${GRADLE_USER_HOME}" "${LOCAL_ZIP}" "${DIST_HASH}"
elif [[ -n "${DIST_HASH}" ]] && [[ -f "${WIN_GRADLE}/wrapper/dists/${DIST_NAME}/${DIST_HASH}/${DIST_NAME}.zip" ]]; then
  install_from_zip "${GRADLE_USER_HOME}" "${WIN_GRADLE}/wrapper/dists/${DIST_NAME}/${DIST_HASH}/${DIST_NAME}.zip" "${DIST_HASH}"
else
  cat >&2 <<EOF
Gradle ${GRADLE_VER} not found offline.

Option A — Windows: run gradlew once (creates hash folder under):
  ${WIN_GRADLE}/wrapper/dists/${DIST_NAME}/

Option B — copy zip to:
  ${LOCAL_ZIP}
  then export GRADLE_DIST_HASH=<folder name under dists/${DIST_NAME}/>

Wrapper expects: gradle-${GRADLE_VER}-bin.zip
EOF
  exit 1
fi

echo "[*] Gradle ${GRADLE_VER} ready (GRADLE_USER_HOME=${GRADLE_USER_HOME})"
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi
exit 0
