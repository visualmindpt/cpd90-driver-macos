#!/bin/bash
# Testes do estado da impressora, dos níveis da fita e da verificação do
# formato (docs/PROTOCOL.md), com o emulador de impressora.
set -uo pipefail
cd "$(dirname "$0")/.."
T=build/status-tests; mkdir -p "$T"
PPD=ppd/CPD90Universal.ppd
fail=0
ok() { echo "ok  $*"; }; bad() { echo "ERRO $*"; fail=1; }
expect() { if grep -qF -- "$2" "$T/$1.log"; then ok "$3"; else bad "$3 (falta: $2)"; fi; }
cmd() { # nome comandos...
    local n=$1; shift
    printf '#CUPS-COMMAND\n%s\n' "$@" > "$T/$n.cmd"
    build/printer_emulator build/commandtomitsud90 "$PPD" "$T/$n.cmd" "" "$T/$n.bin" "$T/$n.log" 2>/dev/null
}

# Pedidos enviados à impressora (bytes exatos).
HARNESS_LEVELS=350/600/0x0f/0xff cmd q ReportLevels ReportStatus
[ "$(xxd -p "$T/q.bin" | tr -d '\n')" = "1b474430000003 1e162a1b47443000000116" ] || \
[ "$(xxd -p "$T/q.bin" | tr -d '\n')" = "1b4744300000031e162a1b47443000000116" ] \
    && ok "pedidos de níveis (1b 47 44 30 00 00 03 1e 16 2a) e de estado (… 01 16)" \
    || bad "pedidos enviados: $(xxd -p "$T/q.bin" | tr -d '\n')"

# Níveis e estado.
HARNESS_LEVELS=350/600/0x0f/0xff HARNESS_STATUS=0x0000 cmd a ReportLevels ReportStatus
expect a 'marker-levels=58' 'nível 350/600 = 58 %'
grep -q 'STATE: +com.mitsubishi' "$T/a.log" && bad 'estado 0 não deve acrescentar razões' || ok 'estado 0: sem razões de erro'
for c in "0x2190|com.mitsubishi-error0006_2190" "0x2600|com.mitsubishi-error0008_2600" \
         "0x0005|com.mitsubishi-error0005" "0x7054|com.mitsubishi-error0018_7054" \
         "0x2FFF|com.mitsubishi-error0013_2FFF" "0x1234|com.mitsubishi-error0004"; do
    code=${c%|*}; reason=${c#*|}
    HARNESS_LEVELS=10/400/0x0f/0xff HARNESS_STATUS=$code cmd s ReportStatus
    expect s "STATE: +$reason" "estado $code -> $reason"
done

# Erro durante a impressão: a tarefa pára antes de enviar a imagem.
for c in "0x2600|com.mitsubishi-error0008_2600" "0x2190|com.mitsubishi-error0006_2190"; do
    code=${c%|*}; reason=${c#*|}
    HARNESS_STATUS=$code build/printer_emulator build/rastertomitsud90 "$PPD" \
        build/testdata/ras/ME_10x15-1.ras PageSize=ME_10x15 "$T/p.bin" "$T/p.log" 2>/dev/null; rc=$?
    if [ $rc = 1 ] && grep -q "STATE: +$reason" "$T/p.log" && ! grep -q $'\x1bZT' "$T/p.bin"; then
        ok "impressão com erro $code: parada antes da imagem ($reason)"
    else bad "impressão com erro $code"; fi
done

# Sem canal bidireccional: nada é enviado e o nível fica desconhecido.
HARNESS_NO_BIDI=1 cmd nb ReportLevels
[ ! -s "$T/nb.bin" ] && grep -q 'marker-levels=-2' "$T/nb.log" \
    && ok "sem bidi: nada enviado, marker-levels=-2" || bad "sem bidi"

# Nome da fita, mensagem e avisos.
HARNESS_LEVELS=170/430/0x0f/0xff cmd lv ReportLevels
expect lv 'marker-names="CK-D768/CK-D868 (15×20)"' 'fita: nome CK-D768/CK-D868 (15×20)'
expect lv 'Restam 170 fotos 10x15 (85 em 15x20)' 'fita: mensagem em fotos 10x15 e 15x20'
expect lv 'STATE: -marker-supply-low-warning' 'fita a 39 %: sem aviso'
HARNESS_LEVELS=20/430/0x0f/0xff cmd lv ReportLevels;  expect lv 'STATE: +marker-supply-low-warning' 'fita a 4 %: aviso de fita a acabar'
HARNESS_LEVELS=0/430/0x0f/0xff cmd lv ReportLevels;   expect lv 'STATE: +marker-supply-empty-warning' 'fita a 0: aviso de fita esgotada'
HARNESS_LEVELS=100/460/0x02/0xff cmd lv ReportLevels; expect lv 'marker-names="CK-D746 (10×15)"' 'fita CK-D746 reconhecida'
HARNESS_LEVELS=50/200/0x44/0x12 cmd lv ReportLevels;  expect lv 'marker-names="Fita 13×18"' 'fita desconhecida: classe de tamanho'

# Verificação do formato numa fita 15×20.
for c in "ME_15x20|0" "ME_10x15|0" "ME_10x15x2|0" "ME_15x15|0" "ME_15x23|1" "ME_15x21|1" "ME_13x18|1" "ME_9x13|1"; do
    ps=${c%|*}; want=${c#*|}
    HARNESS_LEVELS=170/430/0x0f/0xff build/printer_emulator build/rastertomitsud90 "$PPD" \
        build/testdata/ras/$ps-1.ras "PageSize=$ps" "$T/f.bin" "$T/f.log" 2>/dev/null; rc=$?
    img=$(python3 -c "import sys;sys.path.insert(0,'tools');from parse_stream import parse;print(sum(k=='ZT' for k,_,_ in parse(open('$T/f.bin','rb').read())))")
    if [ $want = 1 ] && [ $rc = 1 ] && [ "$img" = 0 ] && grep -q 'não cabe na fita' "$T/f.log"; then
        ok "fita 15×20: $ps recusado antes de enviar a imagem"
    elif [ $want = 0 ] && [ $rc = 0 ] && [ "$img" = 1 ]; then
        ok "fita 15×20: $ps aceite"
    else bad "fita 15×20: $ps (rc=$rc, imagens=$img)"; fi
done
HARNESS_LEVELS=0/0/0x00/0x00 build/printer_emulator build/rastertomitsud90 "$PPD" \
    build/testdata/ras/ME_15x23-1.ras PageSize=ME_15x23 "$T/f.bin" "$T/f.log" 2>/dev/null \
    && ok "fita desconhecida: nada é bloqueado" || bad "fita desconhecida bloqueou"
exit $fail
