#!/bin/bash
# Gera as rasters de teste em build/testdata/ras/: para cada PageSize, uma
# raster modelo produzida pelo cupsfilter do sistema a partir do nosso PPD
# (dá as dimensões exatas do CUPS) e rasters determinísticas de 1 e 2
# páginas (mkraster).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/testdata/ras build
[ -x build/mkraster ] || clang -O2 -o build/mkraster tools/mkraster.c -lcups
python3 -c "
w,h=1200,1800
f=open('build/testdata/test.ppm','wb');f.write(b'P6 %d %d 255\n'%(w,h))
for y in range(h): f.write(bytes(b for x in range(w) for b in ((x*255)//(w-1),(y*255)//(h-1),((x+y)//7)&255)))
"
sips -s format png build/testdata/test.ppm --out build/testdata/test.png >/dev/null
for s in $(grep -E '^\*PageSize ME_' ppd/CPD90Universal.ppd | awk '{print $2}' | cut -d/ -f1); do
    cupsfilter -p ppd/CPD90Universal.ppd -o PageSize="$s" \
        -m application/vnd.cups-raster build/testdata/test.png \
        > "build/testdata/ras/tpl_$s.ras" 2>/dev/null
    build/mkraster "build/testdata/ras/tpl_$s.ras" "build/testdata/ras/$s-1.ras" 1
    build/mkraster "build/testdata/ras/tpl_$s.ras" "build/testdata/ras/$s-2.ras" 2 >/dev/null
done
