#!/usr/bin/env bash
# msgfmt without sudo (extract from Ubuntu gettext .deb).
set -euo pipefail
if command -v msgfmt >/dev/null; then
  exit 0
fi
dest="${HOME}/ko-build/gettext"
mkdir -p "${dest}/bin" "${dest}/lib"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
cd "${tmp}"
apt-get download gettext
dpkg-deb -x gettext_*.deb extract
cp extract/usr/bin/msgfmt "${dest}/bin/"
cp extract/usr/lib/x86_64-linux-gnu/libgettextsrc-0.21.so \
   extract/usr/lib/x86_64-linux-gnu/libgettextlib-0.21.so "${dest}/lib/"
echo "Installed msgfmt to ${dest}/bin (set PATH/LD_LIBRARY_PATH in build scripts)"
