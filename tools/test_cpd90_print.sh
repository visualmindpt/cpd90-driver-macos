#!/bin/bash
# Testes da cpd90-print (arm64 e x86_64), sem imprimir:
#   1. sem gestão de cor e tamanho exato: píxeis intactos
#   2. paisagem num formato em retrato: rodada como no Lightroom, preenchida
#   3. conversão ICC igual à de referência do sistema (sips), ≤ 3 níveis
#   4. caminho completo: raster -> rastertomitsud90 -> os mesmos píxeis no ZT
#   5. várias imagens numa tarefa (5x15x2_2 combina duas por folha)
#   6. (CPD90_TEST_LP=1) envio real ao CUPS com a tarefa retida e cancelada
set -uo pipefail
cd "$(dirname "$0")/.."
export CPD90_FILTER=$PWD/build/rastertomitsud90
T=build/cp-tests; rm -rf "$T"; mkdir -p "$T"
UF=/Library/Printers/CPD90Universal/Profiles/CPD90_UF.icc
[ -f "$UF" ] || UF="${CPD90_UF_ICC:-}"   # ou um CPD90_UF.icc indicado à mão
HAVE_UF=0; [ -f "$UF" ] && HAVE_UF=1
[ $HAVE_UF = 1 ] || echo "--  sem o perfil CPD90_UF: teste de conversão ICC saltado"
fail=0
ok() { echo "ok  $*"; }; bad() { echo "ERRO $*"; fail=1; }

python3 - "$T" <<'EOF'
import sys
T=sys.argv[1]
def ppm(name,w,h,f):
    with open(f'{T}/{name}.ppm','wb') as o:
        o.write(b'P6 %d %d 255\n'%(w,h))
        for y in range(h): o.write(bytes(v for x in range(w) for v in f(x,y)))
ppm('exata',1852,2428,lambda x,y:((x*7+y)&255,(x^y)&255,(x*y>>6)&255))
ppm('paisagem',3000,2000,lambda x,y:(255,0,0) if x<300 and y<200 else ((x*255)//2999,(y*255)//1999,128))
ppm('tira1',1852,613,lambda x,y:(10,200,30))
ppm('tira2',1852,613,lambda x,y:(200,10,30))
EOF
for f in exata paisagem tira1 tira2; do sips -s format png "$T/$f.ppm" --out "$T/$f.png" >/dev/null; done
[ $HAVE_UF = 1 ] && sips -m "$UF" "$T/exata.png" --out "$T/exata_sips.png" >/dev/null 2>&1

for arch in arm64 x86_64; do
    P="arch -$arch build/cpd90-print"
    $P --sem-gestao-cor --raster "$T/t1.ras" "$T/exata.png" 2>/dev/null
    $P --sem-gestao-cor -n nenhuma --raster "$T/t2.ras" "$T/paisagem.png" 2>/dev/null
    if [ $HAVE_UF = 1 ]; then
        $P -n nenhuma -p "$UF" --raster "$T/t3.ras" "$T/exata.png" 2>/dev/null
        $P --sem-gestao-cor -n nenhuma --raster "$T/t3s.ras" "$T/exata_sips.png" 2>/dev/null
    fi
    $P --sem-gestao-cor -t 5x15x2_2 --raster "$T/t5.ras" "$T/tira1.png" "$T/tira2.png" 2>/dev/null
    python3 - "$T" "$arch" <<'EOF' || fail=1
import struct, sys
T, arch = sys.argv[1], sys.argv[2]
def ras(f):
    d = open(f, 'rb').read(); pages = []; pos = 4
    while pos < len(d):
        w, h = struct.unpack_from('<II', d, pos + 372); pos += 1796
        pages.append((w, h, d[pos:pos + w * h * 3])); pos += w * h * 3
    return pages
bad = 0
def check(cond, msg):
    global bad
    print(('ok  ' if cond else 'ERRO ') + f'[{arch}] ' + msg); bad |= not cond
src = open(f'{T}/exata.ppm', 'rb').read(); src = src[src.index(b'255\n') + 4:]
w, h, px = ras(f'{T}/t1.ras')[0]
check((w, h) == (1852, 2428) and px == src, '1. sem gestão de cor: píxeis intactos (1852x2428)')
w, h, px = ras(f'{T}/t2.ras')[0]
p = lambda x, y: tuple(px[3 * (y * w + x):3 * (y * w + x) + 3])
check((w, h) == (1852, 2428) and p(5, h - 6) == (255, 0, 0) and p(5, 5) != (255, 0, 0),
      '2. paisagem rodada (canto sup-esq da foto -> inf-esq da folha) e preenchida')
import os
if os.path.exists(f'{T}/t3.ras'):
    o = ras(f'{T}/t3.ras')[0][2]; s = ras(f'{T}/t3s.ras')[0][2]
    diff = [abs(o[k] - s[k]) for k in range(0, len(o), 7)]
    check(max(diff) <= 3 and sum(diff) / len(diff) < 0.2,
          f'3. conversão ICC vs sips: média {sum(diff)/len(diff):.3f}, máx {max(diff)}')
pages = ras(f'{T}/t5.ras')
check(len(pages) == 2 and all((w, h) == (1852, 613) for w, h, _ in pages),
      '5. duas tiras 5x15x2_2 -> duas páginas de 1852x613')
sys.exit(bad)
EOF
done

# 7. Folha de calibração: com o centro em 0,0,0 a célula central é a foto
#    sem curva; cada célula tem de ser exatamente essa célula transformada
#    pela curva do filtro (rastertomitsud90 --curva) para os seus valores.
build/cpd90-print --sem-gestao-cor --folha-calibracao --eixos luz-calor --centro 0,0,0 \
    --passo 3 --raster "$T/t7.ras" "$T/exata.png" 2>/dev/null
python3 - "$T" <<'PYEOF' || fail=1
import struct, subprocess, sys
T = sys.argv[1]; d = open(f'{T}/t7.ras', 'rb').read()
w, h = struct.unpack_from('<II', d, 4 + 372); px = d[1800:1800 + w * h * 3]
g, lab = 8, 64; cw, ch = w // 3, h // 3; iw, ih = cw - 2 * g, ch - 2 * g - lab
def cell(r, c):
    x0, y0 = c * cw + g, r * ch + g
    return b''.join(px[((y0 + y) * w + x0) * 3:((y0 + y) * w + x0 + iw) * 3] for y in range(ih))
def curve(v):
    out = subprocess.run(['build/rastertomitsud90', '--curva', *map(str, v)],
                         capture_output=True, text=True).stdout.split('\n')
    return [list(map(int, l.split())) for l in out[:3]]
base = cell(1, 1); bad = []
for r in range(3):
    for c in range(3):
        v = [3 * (1 - r), 0, 3 * (c - 1)]            # linhas: L; colunas: W
        lut = curve(v); exp = bytearray(base)
        for k in range(3):
            exp[k::3] = bytes(lut[k][b] for b in exp[k::3])
        if cell(r, c) != bytes(exp): bad.append(v)
print(('ok  ' if not bad else f'ERRO {bad} ') + '7. folha de calibração: 9 células = curva do filtro aplicada à central')
sys.exit(1 if bad else 0)
PYEOF

# 8. URF (AirPrint): codificador independente com todos os códigos
#    (repetição, literais, 128 = resto a branco, linhas repetidas); a
#    descodificação tem de devolver os píxeis exatos. Página 1852x2428 a
#    300 ppp -> formato 15x20 escolhido pelo tamanho, sem reamostragem.
python3 - "$T" <<'PYEOF'
import struct, sys
T = sys.argv[1]; w, h = 1852, 2428
def px(x, y):
    if y % 50 == 0 and x > w // 2: return (255, 255, 255)        # resto a branco
    if (y // 7) % 2 == 0: return ((x // 13) & 255, 90, 200)         # repetições
    return ((x * 7 + y) & 255, (x ^ y) & 255, (x * y >> 5) & 255)   # literais
rows = [bytes(v for x in range(w) for v in px(x, y)) for y in range(h)]
def enc_line(row):
    pix = [row[3 * i:3 * i + 3] for i in range(w)]; out = bytearray(); i = 0
    while i < w:
        if all(p == b'\xff\xff\xff' for p in pix[i:]) and i > 0:
            out.append(128); break
        j = i
        while j + 1 < w and pix[j + 1] == pix[i] and j - i < 127: j += 1
        if j > i:
            out.append(j - i); out += pix[i]; i = j + 1
        else:
            k = i
            while k + 1 < w and pix[k + 1] != pix[k] and k - i < 127: k += 1
            n = k - i + 1; out.append(257 - n)
            for p in pix[i:i + n]: out += p
            i += n
    return bytes(out)
body = bytearray(); y = 0
while y < h:
    rep = 1
    while y + rep < h and rows[y + rep] == rows[y] and rep < 256: rep += 1
    body.append(rep - 1); body += enc_line(rows[y]); y += rep
hdr = bytes([24, 1, 1, 5]) + b'\0' * 8 + struct.pack('>III', w, h, 300) + b'\0' * 8
open(f'{T}/t8.urf', 'wb').write(b'UNIRAST\0' + struct.pack('>I', 1) + hdr + bytes(body))
open(f'{T}/t8.rgb', 'wb').write(b''.join(rows))
PYEOF
out8=$(build/cpd90-print --airprint --sem-gestao-cor -n nenhuma --raster "$T/t8.ras" "$T/t8.urf" 2>&1)
python3 - "$T" "$out8" <<'PYEOF' || fail=1
import struct, sys
T, log = sys.argv[1], sys.argv[2]
d = open(f'{T}/t8.ras', 'rb').read(); w, h = struct.unpack_from('<II', d, 4 + 372)
ok = 'ME_15x20' in log and (w, h) == (1852, 2428) and d[1800:1800 + w * h * 3] == open(f'{T}/t8.rgb', 'rb').read()
print(('ok  ' if ok else 'ERRO ') + '8. URF: descodificação exata e formato 15x20 escolhido pelo tamanho (6x8")')
sys.exit(0 if ok else 1)
PYEOF

# 4. Caminho completo pelo filtro: os píxeis que saem no ZT são os da raster.
build/printer_emulator build/rastertomitsud90 ppd/CPD90Universal.ppd "$T/t1.ras" \
    PageSize=ME_15x20 "$T/t4.bin" "$T/t4.log" 2>/dev/null
python3 - "$T" <<'EOF' || fail=1
import sys; sys.path.insert(0, 'tools'); from parse_stream import parse
T = sys.argv[1]; d = open(f'{T}/t4.bin', 'rb').read()
zt = [(o, v) for k, o, v in parse(d) if k == 'ZT'][0]
r = open(f'{T}/t1.ras', 'rb').read()[1800:]
ok = zt[1]['w'] == 1852 and zt[1]['h'] == 2428 and d[zt[0] + 512: zt[0] + 512 + len(r)] == r
print(('ok  ' if ok else 'ERRO ') + '4. raster -> rastertomitsud90: ZT 1852x2428 com os mesmos píxeis')
sys.exit(0 if ok else 1)
EOF
build/printer_emulator build/rastertomitsud90 ppd/CPD90Universal.ppd "$T/t5.ras" \
    PageSize=ME_5x15x2_2 "$T/t5.bin" "$T/t5.log" 2>/dev/null
python3 - "$T" <<'EOF' || fail=1
import sys; sys.path.insert(0, 'tools'); from parse_stream import parse
T = sys.argv[1]; d = open(f'{T}/t5.bin', 'rb').read()
zts = [(o, v) for k, o, v in parse(d) if k == 'ZT']
o = zts[0][0] + 512; w = 1852
top = d[o:o + 3]; bottom = d[o + 613 * w * 3: o + 613 * w * 3 + 3]
ok = len(zts) == 1 and top == bytes((200, 10, 30)) and bottom == bytes((10, 200, 30))
print(('ok  ' if ok else 'ERRO ') + '5b. 5x15x2_2: uma folha, tira 2 em cima e tira 1 em baixo')
sys.exit(0 if ok else 1)
EOF

# 6. Envio real ao CUPS (opcional): tarefa retida e cancelada, nada é impresso.
if [ "${CPD90_TEST_LP:-}" = 1 ]; then
    out=$(build/cpd90-print --reter -n nenhuma "$T/exata.png" 2>/dev/null)
    job=$(echo "$out" | grep -oE '[A-Za-z0-9_]+-[0-9]+' | head -1)
    if [ -n "$job" ] && lpstat -o | grep -q "^$job "; then
        cancel "$job" && ok "6. envio ao CUPS aceite ($job, retida e cancelada)"
    else bad "6. envio ao CUPS: $out"; fi
fi
exit $fail
