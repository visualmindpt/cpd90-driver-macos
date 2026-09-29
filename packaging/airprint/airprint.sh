#!/bin/bash
#
# airprint.sh — impressora AirPrint para o iPhone/iPad, que imprime na CP-D90.
#
#   /Library/Printers/CPD90Universal/airprint/airprint.sh ativar ["Nome"]
#   /Library/Printers/CPD90Universal/airprint/airprint.sh desativar
#   /Library/Printers/CPD90Universal/airprint/airprint.sh estado
#
# Usa o ippeveprinter do CUPS 2.4 do Homebrew (brew install cups); o do
# macOS (CUPS 2.3.4) recusa os trabalhos do iOS. Corre como agente da sessão
# do utilizador (arranca com a sessão; o Mac tem de estar acordado e na mesma
# rede). Cada foto segue para a fila CP-D90 pela cpd90-print (tamanho exato,
# perfil CPD90_UF). Não precisa de sudo.
set -euo pipefail

DIR=/Library/Printers/CPD90Universal/airprint
LABEL=pt.nelsonsilva.cpd90-airprint
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SPOOL="$HOME/Library/Caches/cpd90-airprint"
LOG="$HOME/Library/Logs/cpd90-airprint.log"
PORT=8632

find_ipp() {
    for p in /opt/homebrew/opt/cups/bin/ippeveprinter /usr/local/opt/cups/bin/ippeveprinter; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

case "${1:-estado}" in
ativar)
    name=${2:-"CP-D90 (iPhone)"}
    ipp=$(find_ipp) || { echo "Falta o CUPS 2.4 do Homebrew. Instale com: brew install cups" >&2; exit 1; }
    mkdir -p "$SPOOL" "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$ipp</string>
    <string>-a</string><string>$DIR/cpd90-airprint.conf</string>
    <string>-c</string><string>$DIR/cpd90-airprint-job</string>
    <string>-d</string><string>$SPOOL</string>
    <string>-r</string><string>_print,_universal</string>
    <string>-p</string><string>$PORT</string>
    <string>$name</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>StandardOutPath</key><string>$LOG</string>
</dict></plist>
XML
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Impressora AirPrint \"$name\" ativada (porta $PORT). Registo: $LOG"
    ;;
desativar)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Impressora AirPrint desativada."
    ;;
estado)
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        echo "Ativa: $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:11' "$PLIST" 2>/dev/null) (porta $PORT)"
    else
        echo "Desativada."
    fi
    ;;
*) sed -n '3,12p' "$0"; exit 2 ;;
esac
