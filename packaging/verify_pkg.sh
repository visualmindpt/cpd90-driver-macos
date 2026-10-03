#!/bin/bash
# Verifica o pacote construído sem o instalar: payload, donos/permissões,
# binários Universal assinados, PPD válido contra o próprio payload e
# scripts sem erros de sintaxe.
set -uo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^#define DRIVER_VERSION "\(.*\)"/\1/p' src/mitsud90_common.h)
PUBLIC=${PUBLIC:-0}
PKG=dist/CPD90Universal-$VERSION$([ "$PUBLIC" = 1 ] && echo -public || true).pkg
X=build/pkg-verify; rm -rf "$X"
fail=0; ok() { echo "ok  $*"; }; bad() { echo "ERRO $*"; fail=1; }

pkgutil --check-signature "$PKG" >/dev/null 2>&1 && ok "pacote assinado" || echo "--  pacote sem assinatura de programador (esperado; ver README)"
pkgutil --expand "$PKG" "$X" || { bad "pkgutil --expand"; exit 1; }
grep -q 'hostArchitectures="arm64,x86_64"' "$X/Distribution" && ok "Distribution: arm64 + x86_64, macOS >= 11"
grep -q 'postinstall file="./postinstall"' "$X/CPD90Universal-component.pkg/PackageInfo" \
    && [ -x "$X/CPD90Universal-component.pkg/Scripts/postinstall" ] && bash -n "$X/CPD90Universal-component.pkg/Scripts/postinstall" \
    && ok "postinstall incluído (fila automática, Ações Rápidas, AirPrint)" || bad "postinstall"
grep -q 'overwrite-permissions="false"' "$X/CPD90Universal-component.pkg/PackageInfo" && ok "PackageInfo: não altera permissões de pastas existentes" || bad "overwrite-permissions"
# O Bom e o Payload têm de listar exatamente os mesmos caminhos.
diff <(lsbom -s "$X/CPD90Universal-component.pkg/Bom" | sort) <(gunzip -dc "$X/CPD90Universal-component.pkg/Payload" | cpio -it --quiet 2>/dev/null | sort) >/dev/null && ok "Bom e Payload coincidem" || bad "Bom e Payload diferem"

echo "--- payload (modo dono/grupo caminho)"
lsbom -p MUGf "$X/CPD90Universal-component.pkg/Bom" | grep -E 'CPD90Universal' | sed 's/^/    /'
if lsbom -s "$X/CPD90Universal-component.pkg/Bom" | grep -q '/\._'; then bad "payload contém ficheiros AppleDouble ._*"; else ok "sem ficheiros ._* no payload"; fi
while read -r mode uid gid path; do
    case "$path" in *.workflow*) [ -d "$X/../pkgroot/$path" ] || [ "$mode" = 100644 ] || bad "$path: modo $mode"; continue ;; esac
    [ "$uid" = 0 ] && [ "$gid" = 0 ] || bad "$path: dono $uid:$gid (esperado root:wheel)"
    case "$path" in
        *.sh|*/filter/*|*/bin/*|*/cpd90-airprint-job) [ "$mode" = 100755 ] || bad "$path: modo $mode (esperado 0755)" ;;
        *.icc|*.icns|*.gz|*.txt|*.conf) [ "$mode" = 100644 ] || bad "$path: modo $mode" ;;
    esac
done < <(lsbom -p mugf "$X/CPD90Universal-component.pkg/Bom" | grep -E 'CPD90Universal/|CPD90Universal.ppd|/Services/Imprimir')
[ $fail = 0 ] && ok "donos root:wheel; filtros e scripts 0755, dados 0644"

mkdir -p "$X/root" && (cd "$X/root" && gunzip -dc ../CPD90Universal-component.pkg/Payload | cpio -id --quiet)
# Donos no próprio Payload (é o que o installer aplica).
if gunzip -dc "$X/CPD90Universal-component.pkg/Payload" | cpio -itv --quiet 2>/dev/null | awk '{print $3":"$4}' | sort -u | grep -qv '^root:wheel$'; then bad "Payload com donos diferentes de root:wheel"; else ok "Payload: todos os ficheiros root:wheel"; fi
for b in filter/rastertomitsud90 filter/commandtomitsud90 bin/cpd90-print; do
    f="$X/root/Library/Printers/CPD90Universal/$b"
    lipo -info "$f" | grep -q 'x86_64 arm64' && codesign -v "$f" 2>/dev/null \
        && ok "$b: Universal (x86_64 + arm64), assinatura ad-hoc válida" || bad "$b"
    cmp -s "$f" "build/$(basename $b)" || bad "$b no pacote difere de build/$(basename $b)"
done
"$X/root/Library/Printers/CPD90Universal/bin/cpd90-print" --versao | grep -qx "$VERSION" \
    && ok "cpd90-print --versao = $VERSION" || bad "versão da cpd90-print"
n=0
for w in "$X/root/Library/Services/"*.workflow; do
    for f in "$w/Contents/Info.plist" "$w/Contents/document.wflow"; do
        plutil -lint "$f" >/dev/null || bad "plist inválido: $f"
    done
    grep -q -- '--simular' "$w/Contents/document.wflow" && bad "$(basename "$w") está em modo de simulação"
    n=$((n + 1))
done
[ $n = 4 ] && ok "4 Ações Rápidas do Finder (15×20, 10×15; brilhante e mate), plists válidos" || bad "Ações Rápidas: $n encontradas"
for s in migrar-filas.sh desinstalar.sh instalar-perfis.sh airprint/airprint.sh airprint/cpd90-airprint-job; do
    bash -n "$X/root/Library/Printers/CPD90Universal/$s" && ok "$s: sintaxe" || bad "$s"
done
gunzip -c "$X/root/Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz" > "$X/test.ppd"
cmp -s "$X/test.ppd" ppd/CPD90Universal.ppd && ok "PPD no pacote = ppd/CPD90Universal.ppd"
out=$(cupstestppd -W all -R "$X/root" "$X/test.ppd" 2>&1)
echo "$out" | head -1 | grep -q ': OK' || { bad "cupstestppd"; echo "$out"; }
missing=$(echo "$out" | grep -E 'Falta ficheiro|Missing' | grep -v '/Profiles/' || true)
if [ -n "$missing" ]; then bad "cupstestppd: ficheiros em falta no payload"; echo "$missing"
else ok "cupstestppd -R <payload>: OK (perfis ICC opcionais)"; fi
icc=$(ls "$X/root/Library/Printers/CPD90Universal/Profiles" 2>/dev/null | wc -l | tr -d ' ')
if [ "$PUBLIC" = 1 ]; then
    [ "$icc" = 0 ] && ok "pacote público: nenhum perfil ICC da Mitsubishi" || bad "pacote público contém perfis ICC"
    cmp -s "$X/root/Library/Printers/CPD90Universal/Icons/CPD90.icns" packaging/icon/CPD90.icns \
        && ok "pacote público: ícone próprio" || bad "ícone"
fi
exit $fail
