/*
 * mkraster — gera um ficheiro CUPS raster determinístico com N páginas,
 * copiando o cabeçalho de uma raster modelo (produzida pelo cupsfilter do
 * sistema para o tamanho de página pretendido). Cada página tem um padrão
 * diferente, para que trocas de ordem ou de página sejam visíveis na
 * comparação byte a byte.
 *
 * Uso: mkraster <modelo.ras> <saida.ras> <paginas>
 */
#define _CUPS_NO_DEPRECATED 0
#include <cups/raster.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "uso: %s <modelo.ras> <saida.ras> <paginas>\n", argv[0]);
        return 2;
    }
    int in = open(argv[1], O_RDONLY);
    int out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (in < 0 || out < 0) {
        perror("open");
        return 1;
    }
    cups_raster_t *rin = cupsRasterOpen(in, CUPS_RASTER_READ);
    cups_page_header2_t h;
    if (!cupsRasterReadHeader2(rin, &h)) {
        fprintf(stderr, "modelo sem cabeçalho\n");
        return 1;
    }
    cupsRasterClose(rin);
    close(in);

    int pages = atoi(argv[3]);
    cups_raster_t *rout = cupsRasterOpen(out, CUPS_RASTER_WRITE);
    unsigned char *line = malloc(h.cupsBytesPerLine);
    unsigned w = h.cupsWidth, hh = h.cupsHeight;
    for (int p = 0; p < pages; p++) {
        cupsRasterWriteHeader2(rout, &h);
        for (unsigned y = 0; y < hh; y++) {
            for (unsigned x = 0; x < w; x++) {
                unsigned char *px = line + 3 * x;
                px[0] = (unsigned char)((x * 255) / (w - 1));
                px[1] = (unsigned char)((y * 255) / (hh - 1));
                px[2] = (unsigned char)(((x + y) / 7 + 97 * p) & 255);
                /* Marcas de canto e de página para detectar cortes/rotação. */
                if ((x < 40 && y < 40) || (x + 40 >= w && y + 40 >= hh))
                    px[0] = px[1] = px[2] = (unsigned char)(p * 60);
                if (x > 60 && x < 60 + 20 * (p + 1) && y > 60 && y < 80)
                    px[0] = px[1] = px[2] = 0;
            }
            cupsRasterWritePixels(rout, line, h.cupsBytesPerLine);
        }
    }
    cupsRasterClose(rout);
    close(out);
    printf("%s: %ux%u, %u bpl, %d página(s), PageSize=%ux%u, name=%s\n",
           argv[2], w, hh, h.cupsBytesPerLine, pages, h.PageSize[0],
           h.PageSize[1], h.cupsPageSizeName);
    return 0;
}
