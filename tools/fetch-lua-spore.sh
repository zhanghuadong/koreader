#!/usr/bin/env bash
set -euo pipefail
DEST="/mnt/e/koreader/base/thirdparty/lua-Spore/build/downloads/source"
TAG="0.4.2"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"

try_clone() {
  local url="$1"
  echo "Trying $url ..."
  if git clone --depth 1 --branch "$TAG" "$url" "$DEST" 2>/dev/null; then
    return 0
  fi
  rm -rf "$DEST"
  if git clone --depth 50 "$url" "$DEST" 2>/dev/null && git -C "$DEST" checkout "$TAG" 2>/dev/null; then
    return 0
  fi
  rm -rf "$DEST"
  return 1
}

for url in \
  "https://github.com/fperrad/lua-Spore.git" \
  "https://framagit.org/fperrad/lua-Spore.git"
do
  if try_clone "$url"; then
    echo "OK from $url"
    exit 0
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROCK="$TMP/lua-spore.src.rock"
curl -fsSL --connect-timeout 30 -o "$ROCK" \
  "https://luarocks.org/manifests/fperrad/lua-spore-0.4.2-1.src.rock" || \
curl -fsSL --connect-timeout 30 -o "$ROCK" \
  "https://raw.githubusercontent.com/luarocks/luarocks-site/master/manifests/fperrad/lua-spore-0.4.2-1.src.rock" || true

if [[ -s "$ROCK" ]]; then
  (cd "$TMP" && unzip -q "$ROCK" 2>/dev/null || tar xf "$ROCK" 2>/dev/null || true)
  SRC="$(find "$TMP" -maxdepth 2 -type d -name 'lua-Spore*' | head -1)"
  if [[ -n "$SRC" && -f "$SRC/src/Spore.lua" ]]; then
    cp -a "$SRC" "$DEST"
    echo "OK from LuaRocks src.rock"
    exit 0
  fi
fi

echo "All download methods failed" >&2
exit 1
