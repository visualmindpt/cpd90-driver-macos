#!/bin/bash
#
# desinstalar.sh — remove o CP-D90DW Universal.
#
#   sudo /Library/Printers/CPD90Universal/desinstalar.sh
#
# Se alguma fila ainda usar este driver e o driver da Mitsubishi estiver
# instalado, a fila volta a ele. Caso contrário a fila é mantida mas deixa
# de imprimir até lhe ser atribuído outro driver.
set -euo pipefail

DIR="/Library/Printers/CPD90Universal"
PPD="/Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz"
OLD="/Library/Printers/PPDs/Contents/Resources/CP90.ppd.gz"

[ "$(id -u)" = 0 ] || { echo "Corra com sudo: sudo $0" >&2; exit 1; }

in_use=()
for q in $(lpstat -e 2>/dev/null); do
    grep -qs rastertomitsud90 "/etc/cups/ppd/$q.ppd" && in_use+=("$q")
done
if [ ${#in_use[@]} -gt 0 ]; then
    if [ -f "$OLD" ]; then
        "$DIR/migrar-filas.sh" --reverter --aplicar
    else
        echo "Atenção: estas filas usam o CP-D90DW Universal e vão deixar de imprimir:"
        printf '  %s\n' "${in_use[@]}"
        read -r -p "Continuar? (s/N) " r
        [ "$r" = s ] || [ "$r" = S ] || exit 1
    fi
fi

# Guarda as cópias de segurança dos PPD, se existirem.
if [ -d "$DIR/backup" ] && [ -n "$(ls -A "$DIR/backup")" ]; then
    dest="/Users/Shared/CPD90Universal-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$DIR/backup" "$dest"
    echo "Cópias dos PPD anteriores guardadas em $dest"
fi

# Impressora AirPrint da sessão de quem corre o sudo.
if [ -n "${SUDO_USER:-}" ]; then
    uid=$(id -u "$SUDO_USER"); home=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{print $2}')
    launchctl bootout "gui/$uid/pt.nelsonsilva.cpd90-airprint" 2>/dev/null || true
    rm -f "$home/Library/LaunchAgents/pt.nelsonsilva.cpd90-airprint.plist"
fi
rm -f "$PPD"
rm -rf "/Library/Services/Imprimir na CP-D90 ("*").workflow"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
rm -rf "$DIR"
pkgutil --forget pt.nelsonsilva.cpd90universal >/dev/null 2>&1 || true
echo "CP-D90DW Universal removido."
