#!/bin/bash
#
# build_pkg.sh — constrói dist/CPD90Universal-<versão>.pkg.
#
# Por omissão o pacote não inclui nenhum ficheiro da Mitsubishi: os perfis
# ICC instalam-se depois com instalar-perfis.sh. Para uso pessoal, ICC_DIR
# pode apontar para uma pasta com os CPD90_UF.icc e CPD90_ST.icc que o próprio
# utilizador descarregou, e eles são incluídos no pacote.
#
# Uso: packaging/build_pkg.sh   (chamado por `make pkg`)
set -euo pipefail
cd "$(dirname "$0")/.."
export COPYFILE_DISABLE=1

VERSION=$(sed -n 's/^#define DRIVER_VERSION "\(.*\)"/\1/p' src/mitsud90_common.h)
ID=pt.nelsonsilva.cpd90universal
ICC_DIR=${ICC_DIR:-}
PUBLIC=${PUBLIC:-$([ -n "$ICC_DIR" ] && echo 0 || echo 1)}

ROOT=build/pkgroot
DEST=$ROOT/Library/Printers/CPD90Universal
rm -rf "$ROOT" build/pkg && mkdir -p "$DEST/filter" "$DEST/bin" "$DEST/Profiles" "$DEST/Icons" \
    "$ROOT/Library/Printers/PPDs/Contents/Resources" build/pkg dist

# Filtros: root:wheel 0755 (o CUPS recusa filtros com escrita para grupo/outros).
install -m 0755 build/rastertomitsud90 build/commandtomitsud90 "$DEST/filter/"
mkdir -p "$DEST/bin" && install -m 0755 build/cpd90-print "$DEST/bin/"
install -m 0755 packaging/payload-scripts/migrar-filas.sh \
    packaging/payload-scripts/desinstalar.sh packaging/payload-scripts/instalar-perfis.sh "$DEST/"
install -m 0644 LICENSE "$DEST/LICENSE.txt"
# Impressora AirPrint para o iPhone (ativada à parte com airprint.sh ativar).
mkdir -p "$DEST/airprint"
install -m 0755 packaging/airprint/airprint.sh packaging/airprint/cpd90-airprint-job "$DEST/airprint/"
install -m 0644 packaging/airprint/cpd90-airprint.conf "$DEST/airprint/"
# Ações Rápidas do Finder ("Imprimir na CP-D90 (15×20)" e "(10×15)").
python3 packaging/gen_quick_actions.py "$ROOT/Library/Services" >/dev/null
find "$ROOT/Library/Services" -type d -exec chmod 0755 {} + && find "$ROOT/Library/Services" -type f -exec chmod 0644 {} +
gzip -9n -c ppd/CPD90Universal.ppd > "$ROOT/Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz"
chmod 0644 "$ROOT/Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz"

# Ícone próprio do projeto (packaging/icon/make_icon.swift).
install -m 0644 packaging/icon/CPD90.icns "$DEST/Icons/CPD90.icns"
if [ "$PUBLIC" = 1 ]; then
    echo "Pacote público: sem perfis ICC da Mitsubishi (instalar-perfis.sh)."
else
    for f in CPD90_ST.icc CPD90_UF.icc; do
        if [ -f "$ICC_DIR/$f" ]; then install -m 0644 "$ICC_DIR/$f" "$DEST/Profiles/"
        else echo "AVISO: em falta (o pacote é construído sem): $ICC_DIR/$f"; fi
    done
fi

# Cada caminho referido pelo PPD tem de existir no payload.
for p in $(grep -oE '"(application/vnd.cups-[a-z]+ 0 )?/Library/Printers/CPD90Universal/[^"]+"' ppd/CPD90Universal.ppd \
           | sed -E 's/"//g; s/^application[^ ]+ 0 //'); do
    case "$p" in */Profiles/*.icc) continue ;; esac   # perfis: opcionais (instalar-perfis.sh)
    [ -e "$ROOT$p" ] || { echo "ERRO: o PPD refere $p, que não está no payload"; exit 1; }
done

find "$ROOT" \( -name '.DS_Store' -o -name '._*' \) -delete

# Componente construído à mão (ver write_payload.py): Payload cpio sem
# atributos estendidos, Bom root:wheel e PackageInfo. overwrite-permissions
# fica a false para não alterar /Library/Printers (root:admin 0775).
COMP=build/pkg/component; mkdir -p "$COMP"
read -r nfiles kbytes < <(python3 packaging/write_payload.py "$ROOT" "$COMP/Payload")
# Bom com dono root:wheel (0/0): gera-se a listagem e troca-se o dono.
mkbom "$ROOT" build/pkg/tmp.bom
lsbom build/pkg/tmp.bom | awk -F'\t' 'BEGIN{OFS="\t"} {$3="0/0"; print}' > build/pkg/bom.txt
mkbom -i build/pkg/bom.txt "$COMP/Bom"
rm build/pkg/tmp.bom
cat > "$COMP/PackageInfo" <<XML
<?xml version="1.0" encoding="utf-8"?>
<pkg-info format-version="2" identifier="$ID" version="$VERSION" install-location="/" auth="root" overwrite-permissions="false" relocatable="false" postinstall-action="none">
    <payload numberOfFiles="$nfiles" installKBytes="$kbytes"/>
</pkg-info>
XML
pkgutil --flatten "$COMP" build/pkg/CPD90Universal-component.pkg

sed "s/@VERSION@/$VERSION/" packaging/Distribution.xml > build/pkg/Distribution.xml
mkdir -p build/pkg/resources
cp packaging/resources/*.html build/pkg/resources/
cp LICENSE build/pkg/resources/LICENSE.txt
OUT=dist/CPD90Universal-$VERSION$([ "$PUBLIC" = 1 ] && echo -public || true).pkg
productbuild --distribution build/pkg/Distribution.xml \
    --resources build/pkg/resources --package-path build/pkg "$OUT"
echo "Pacote: $OUT ($(du -h "$OUT" | cut -f1))"
