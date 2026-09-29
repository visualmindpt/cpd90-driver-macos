#!/bin/bash
#
# instalar-perfis.sh — install Mitsubishi's CP-D90DW ICC profiles (and,
# optionally, the printer icon) from the official Mitsubishi download.
# Instala os perfis ICC da CP-D90DW a partir do download oficial.
#
#   sudo /Library/Printers/CPD90Universal/instalar-perfis.sh <folder|file.zip>
#
# The profiles are Mitsubishi's files and are not distributed with this
# driver. Download them from Mitsubishi Electric (see README), then point
# this script at the downloaded folder or zip. It looks for CPD90_UF.icc and
# CPD90_ST.icc anywhere inside it.
set -euo pipefail
DEST=/Library/Printers/CPD90Universal/Profiles
src=${1:-}
[ -n "$src" ] && [ -e "$src" ] || { sed -n '3,14p' "$0"; exit 2; }
[ "$(id -u)" = 0 ] || { echo "Run with sudo / Corra com sudo." >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
case "$src" in
    *.zip) /usr/bin/ditto -x -k "$src" "$tmp/x" ;;
    *) tmp="$src" ;;
esac
found=0
mkdir -p "$DEST"
for f in CPD90_UF.icc CPD90_ST.icc; do
    p=$(find "${tmp%/}" -type f -iname "$f" -print -quit 2>/dev/null || true)
    if [ -n "$p" ]; then
        install -m 0644 -o root -g wheel "$p" "$DEST/$f"; echo "ok  $f"; found=$((found + 1))
    else
        echo "--  $f não encontrado / not found"
    fi
done
[ $found -gt 0 ] || { echo "Nenhum perfil encontrado / No profile found." >&2; exit 1; }
echo "Perfis instalados em / Profiles installed in $DEST"
