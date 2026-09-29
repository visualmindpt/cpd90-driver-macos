#!/bin/bash
#
# migrar-filas.sh — muda as filas de impressão da CP-D90 criadas com o driver
# da Mitsubishi para o CP-D90DW Universal, ou volta atrás.
#
# Por omissão só mostra o que faria. Para aplicar:
#   sudo /Library/Printers/CPD90Universal/migrar-filas.sh --aplicar
# Para voltar ao driver da Mitsubishi (se ainda estiver instalado):
#   sudo /Library/Printers/CPD90Universal/migrar-filas.sh --reverter --aplicar
#
# As predefinições de cada fila (tamanho, modo, acabamento, ...) são
# mantidas: os dois PPD usam as mesmas palavras-chave e o CUPS copia os
# valores da fila para o PPD novo. Antes de mudar, guarda uma cópia do PPD
# de cada fila em /Library/Printers/CPD90Universal/backup/.
set -euo pipefail

NEW_MODEL="Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz"
OLD_MODEL="Library/Printers/PPDs/Contents/Resources/CP90.ppd.gz"
BACKUP="/Library/Printers/CPD90Universal/backup"
# Só para testes: raiz alternativa onde procurar os modelos instalados.
ROOT_PREFIX=${CPD90_ROOT:-}

apply=0 revert=0
for a in "$@"; do
    case "$a" in
        --aplicar) apply=1 ;;
        --reverter) revert=1 ;;
        -h|--help) sed -n '3,15p' "$0"; exit 0 ;;
        *) echo "Opção desconhecida: $a" >&2; exit 2 ;;
    esac
done

if [ $revert = 1 ]; then
    from_mark='rastertomitsud90' to_model=$OLD_MODEL to_name="driver da Mitsubishi"
    [ -f "$ROOT_PREFIX/$OLD_MODEL" ] || { echo "O driver da Mitsubishi não está instalado (/$OLD_MODEL)." >&2; exit 1; }
else
    from_mark='CP90Filter' to_model=$NEW_MODEL to_name="CP-D90DW Universal"
    [ -f "$ROOT_PREFIX/$NEW_MODEL" ] || { echo "O CP-D90DW Universal não está instalado (/$NEW_MODEL)." >&2; exit 1; }
fi

queues=()
for q in $(lpstat -e 2>/dev/null); do
    ppd="/etc/cups/ppd/$q.ppd"
    [ -r "$ppd" ] && grep -q "$from_mark" "$ppd" && queues+=("$q")
done

if [ ${#queues[@]} -eq 0 ]; then
    echo "Nenhuma fila a mudar para o $to_name."
    exit 0
fi

echo "Filas a mudar para o $to_name:"
for q in "${queues[@]}"; do
    defaults=$(grep -E '^\*Default(PageSize|MEPrintMode|MEPrintFinish|MESharpness_Common): ' \
        "/etc/cups/ppd/$q.ppd" | sed 's/^\*Default//' | tr '\n' ' ')
    echo "  $q  ($defaults)"
done

if [ $apply = 0 ]; then
    echo
    extra=""; [ $revert = 1 ] && extra="--reverter "
    echo "Nada foi alterado. Para aplicar: sudo $0 ${extra}--aplicar"
    exit 0
fi

[ "$(id -u)" = 0 ] || { echo "É preciso correr com sudo para aplicar." >&2; exit 1; }
mkdir -p "$BACKUP"
stamp=$(date +%Y%m%d-%H%M%S)
for q in "${queues[@]}"; do
    cp "/etc/cups/ppd/$q.ppd" "$BACKUP/$q-$stamp.ppd"
    lpadmin -p "$q" -m "$to_model"
    echo "  $q: mudada (cópia do PPD anterior em $BACKUP/$q-$stamp.ppd)"
done
echo "Concluído."
