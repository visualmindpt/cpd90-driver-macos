/*
 * commandtomitsud90 — filtro de comandos CUPS (application/vnd.cups-command)
 * para a Mitsubishi CP-D90DW. Responde a:
 *
 *   ReportLevels  níveis da fita: marker-levels, marker-message, ...
 *   ReportStatus  estado da impressora como razões com.mitsubishi-error*
 *
 * Ver docs/PROTOCOL.md §10.
 *
 * Copyright (C) 2026 Nelson Silva. Licença: GPL-3.0-or-later.
 */
#include <cups/cups.h>
#include <cups/file.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "mitsud90_common.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* Abaixo desta percentagem, o painel avisa que a fita está a acabar. */
#define LOW_LEVEL_PERCENT 5

/* Mensagem da fita para o painel, em fotos do tamanho de referência. Na
   CK-D868 (15x20) a capacidade vem em unidades 10x15 (430 por rolo de 215
   folhas 15x20), confirmado na impressora real (docs/PROTOCOL.md). */
static void report_levels(int bidi) {
    mitsud90_media_t m;
    mitsud90_query_media(bidi, &m);
    int level = -2; /* IPP: "desconhecido" */
    if (m.ok && m.capacity) {
        level = (int)(m.remain * 100u / m.capacity);
        if (level > 100) level = 100;
    }
    fputs("ATTR: marker-colors=#FFFF00#FF00FF#00FFFF\n", stderr);
    fputs("ATTR: marker-types=ink-ribbon\n", stderr);
    if (m.name && m.size)
        fprintf(stderr, "ATTR: marker-names=\"%s (%s)\"\n", m.name, m.size);
    else if (m.size)
        fprintf(stderr, "ATTR: marker-names=\"Fita %s\"\n", m.size);
    else
        fputs("ATTR: marker-names=\"Ink Ribbon\"\n", stderr);
    fprintf(stderr, "ATTR: marker-low-levels=%d\n", LOW_LEVEL_PERCENT);
    fputs("ATTR: marker-high-levels=100\n", stderr);
    fprintf(stderr, "ATTR: marker-levels=%d\n", level);
    if (level < 0) return;
    if ((m.type & 0xf) == 0xf)
        fprintf(stderr, "ATTR: marker-message=\"Restam %u fotos 10x15 (%u em 15x20)\"\n",
                m.remain, m.remain / 2);
    else
        fprintf(stderr, "ATTR: marker-message=\"Restam %u de %u impressões\"\n",
                m.remain, m.capacity);
    /* Avisos normalizados do IPP, que o macOS mostra no painel. */
    fprintf(stderr, "STATE: %cmarker-supply-low-warning\n",
            level <= LOW_LEVEL_PERCENT && m.remain ? '+' : '-');
    fprintf(stderr, "STATE: %cmarker-supply-empty-warning\n", m.remain ? '-' : '+');
}

static void report_status(int bidi, ppd_file_t *ppd) {
    static const uint8_t q[8] = {0x1b, 0x47, 0x44, 0x30, 0x00, 0x00, 0x01, 0x16};
    mitsud90_resp_t r;
    if (!bidi) {
        fputs("DEBUG: sem canal bidireccional; estado desconhecido\n", stderr);
        return;
    }
    mitsud90_put(q, sizeof q);
    mitsud90_read(bidi, 15, &r);
    if (!r.ok) {
        mitsud90_report_state(ppd, 0x0003); /* a impressora não responde */
        return;
    }
    mitsud90_report_state(ppd, mitsud90_code(&r));
}

int main(int argc, char **argv) {
    if (argc < 6 || argc > 7) {
        fputs("Uso: commandtomitsud90 job user title copies options [file]\n",
              stderr);
        return 1;
    }
    setbuf(stderr, NULL);
    fprintf(stderr, "DEBUG: commandtomitsud90 " DRIVER_VERSION "\n");

    cups_file_t *fp = argc == 7 ? cupsFileOpen(argv[6], "r") : cupsFileStdin();
    if (!fp) {
        perror("ERROR: Não foi possível abrir o ficheiro de comandos");
        return 1;
    }
    ppd_file_t *ppd = ppdOpenFile(getenv("PPD"));
    int bidi = mitsud90_bidi();
    if (!bidi)
        fputs("DEBUG: sem canal bidireccional; níveis indisponíveis\n", stderr);

    char line[1024], *value;
    int linenum = 0;
    while (cupsFileGetConf(fp, line, sizeof line, &value, &linenum)) {
        fprintf(stderr, "DEBUG: comando \"%s\"\n", line);
        if (!strcasecmp(line, "ReportLevels"))
            report_levels(bidi);
        else if (!strcasecmp(line, "ReportStatus"))
            report_status(bidi, ppd);
        else
            fprintf(stderr, "DEBUG: comando não suportado: %s\n", line);
    }
    cupsFileClose(fp);
    if (ppd) ppdClose(ppd);
    return 0;
}
