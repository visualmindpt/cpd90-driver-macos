#!/bin/bash
# Testes da calibração por acabamento (docs/PROTOCOL.md) no filtro rastertomitsud90.
# O resultado esperado é calculado em Python a partir da fórmula de docs/PROTOCOL.md
# (implementação independente da do filtro).
set -uo pipefail
cd "$(dirname "$0")/.."
T=build/cal-tests; rm -rf "$T"; mkdir -p "$T"
RAS=build/testdata/ras/ME_15x20-1.ras
[ -f "$RAS" ] || tools/make_rasters.sh >/dev/null
fail=0

run() { # nome opções...
    local name=$1; shift
    build/printer_emulator build/rastertomitsud90 ppd/CPD90Universal.ppd "$RAS" \
        "PageSize=ME_15x20 $*" "$T/$name.bin" "$T/$name.log" 2>/dev/null
}
run base
run gloss_L3        MECalGlossL=3
run gloss_mix       MECalGlossM=-2 MECalGlossW=4
run matte           MEPrintFinish=Matte MECalMatteW=5 MECalGlossL=7
run gloss_ignores   MECalMatteL=9
run compose         MEGammaR=2 MECalGlossL=3

python3 - "$T" "$RAS" <<'EOF' || fail=1
import math, struct, subprocess, sys
sys.path.insert(0, 'tools')
from parse_stream import parse
# Expoentes das curvas de gama (docs/PROTOCOL.md) e leitor de raster CUPS v3.
GAMMA_EXP = {-5: 2.6138, -4: 1.7034, -3: 1.4528, -2: 1.2516, -1: 1.1004,
             1: 0.899, 2: 0.799, 3: 0.6987, 4: 0.5983, 5: 0.3976}

def read_raster(path):
    data = open(path, 'rb').read(); pos, pages = 4, []
    while pos < len(data):
        w, h = struct.unpack_from('<II', data, pos + 372)
        bpl = struct.unpack_from('<I', data, pos + 392)[0]; pos += 1796
        pages.append((w, h, [data[pos + y * bpl: pos + (y + 1) * bpl] for y in range(h)]))
        pos += h * bpl
    return pages
T, RAS = sys.argv[1], sys.argv[2]

def cal(L, M, W):
    t = (L + W, L + M, L - W)
    return [[int(math.floor(255 * (i / 255) ** (2 ** (-0.04 * tc)) + 0.5)) for i in range(256)] for tc in t]

def gamma(g):
    return [int(255 * (i / 255) ** GAMMA_EXP[g] + 0.5) for i in range(256)] if g else list(range(256))

w0, h0, rows = read_raster(RAS)[0]
src = b''.join(r[:1852 * 3] for r in rows[:2428])

def expected(luts):
    out = bytearray(src)
    for c in range(3):
        out[c::3] = bytes(luts[c][v] for v in out[c::3])
    return bytes(out)

def zt(name):
    d = open(f'{T}/{name}.bin', 'rb').read()
    (o, v), = [(o, v) for k, o, v in parse(d) if k == 'ZT']
    return d[o + 512:o + 512 + v['w'] * v['h'] * 3], d

bad = 0
def check(cond, msg):
    global bad
    print(('ok  ' if cond else 'ERRO ') + msg); bad |= not cond

ident = [list(range(256))] * 3
base, _ = zt('base')
check(base == src, 'sem calibração: píxeis intactos')
for name, luts, msg in [
        ('gloss_L3', cal(3, 0, 0), 'brilhante L=+3'),
        ('gloss_mix', cal(0, -2, 4), 'brilhante M=-2 W=+4'),
        ('matte', cal(0, 0, 5), 'mate usa MECalMatte* (W=+5) e ignora MECalGloss*'),
        ('gloss_ignores', ident, 'brilhante ignora MECalMatte*'),
        ('compose', [[cal(3, 0, 0)[0][v] for v in gamma(2)], cal(3, 0, 0)[1], cal(3, 0, 0)[2]],
         'MEGammaR=+2 seguido da calibração L=+3')]:
    px, d = zt(name)
    check(px == expected(luts), msg)
# Cabeçalhos: a calibração não mexe no SP0 (só o acabamento, no caso mate).
sp = lambda d: [v for k, o, v in parse(d) if k == 'SP0'][0]
check(sp(zt('gloss_L3')[1]) == sp(zt('base')[1]), 'cabeçalho SP0 igual com calibração')
# --curva do filtro = fórmula de docs/PROTOCOL.md
for L, M, W in [(0, 0, 0), (3, 0, 0), (-10, 10, -10), (2, -3, 7)]:
    out = subprocess.run(['build/rastertomitsud90', '--curva', str(L), str(M), str(W)],
                         capture_output=True, text=True).stdout.split('\n')
    got = [list(map(int, l.split())) for l in out[:3]]
    check(got == cal(L, M, W), f'--curva {L} {M} {W} = fórmula')
sys.exit(bad)
EOF
exit $fail
