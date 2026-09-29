/*
 * Código partilhado pelos filtros CP-D90. Ver mitsud90_common.h.
 *
 * Copyright (C) 2026 Nelson Silva. Licença: GPL-3.0-or-later.
 */
#include "mitsud90_common.h"

#include <cups/sidechannel.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define REASON_PREFIX "com.mitsubishi-error"

int mitsud90_bidi(void) {
    char bidi = 0;
    int len = 1;
    return cupsSideChannelDoRequest(CUPS_SC_CMD_GET_BIDI, &bidi, &len, 30.0) ==
               CUPS_SC_STATUS_OK &&
           len == 1 && bidi == CUPS_SC_BIDI_SUPPORTED;
}

void mitsud90_put(const void *buf, size_t n) {
    if (n && fwrite(buf, 1, n, stdout) != n) {
        fprintf(stderr, "ERROR: Falha ao escrever para a impressora: %s\n",
                strerror(errno));
        exit(1);
    }
}

void mitsud90_read(int bidi, size_t min, mitsud90_resp_t *r) {
    memset(r, 0, sizeof *r);
    fflush(stdout);
    if (!bidi) return;
    char dummy[16];
    int dlen = sizeof dummy;
    cups_sc_status_t st =
        cupsSideChannelDoRequest(CUPS_SC_CMD_DRAIN_OUTPUT, dummy, &dlen, 30.0);
    fprintf(stderr, "DEBUG: DRAIN_OUTPUT=%d\n", st);
    while (r->len < min) {
        ssize_t n = cupsBackChannelRead((char *)r->raw + r->len,
                                        sizeof r->raw - r->len, 10.0);
        if (n <= 0) {
            fprintf(stderr, "DEBUG: cupsBackChannelRead falhou (%zd, %zu bytes)\n",
                    n, r->len);
            return;
        }
        r->len += (size_t)n;
    }
    r->ok = 1;
}

/* Razão do PPD para um código: sufixo "_XXXX" (hex) ou, para os códigos
   baixos (0x0001–0x00ff), "errorNNNN" sem sufixo. */
static const char *reason_for(ppd_file_t *ppd, int code) {
    char suffix[8], exact[32];
    snprintf(suffix, sizeof suffix, "_%04x", code);
    snprintf(exact, sizeof exact, REASON_PREFIX "%04x", code);
    for (ppd_attr_t *a = ppdFindAttr(ppd, "cupsIPPReason", NULL); a;
         a = ppdFindNextAttr(ppd, "cupsIPPReason", NULL)) {
        size_t n = strlen(a->spec);
        if (strncmp(a->spec, REASON_PREFIX, strlen(REASON_PREFIX))) continue;
        if (n > 5 && !strcasecmp(a->spec + n - 5, suffix)) return a->spec;
        if (code < 0x100 && !strcmp(a->spec, exact)) return a->spec;
    }
    return NULL;
}

int mitsud90_report_state(ppd_file_t *ppd, int code) {
    const char *add = NULL;
    if (code) {
        add = ppd ? reason_for(ppd, code) : NULL;
        if (!add) add = REASON_PREFIX "0004";
    }
    if (ppd)
        for (ppd_attr_t *a = ppdFindAttr(ppd, "cupsIPPReason", NULL); a;
             a = ppdFindNextAttr(ppd, "cupsIPPReason", NULL))
            if (!strncmp(a->spec, REASON_PREFIX, strlen(REASON_PREFIX)) &&
                (!add || strcmp(a->spec, add)))
                fprintf(stderr, "STATE: -%s\n", a->spec);
    if (add) {
        fprintf(stderr, "STATE: +%s\n", add);
        fprintf(stderr, "DEBUG: estado da impressora %04x -> %s\n", code, add);
    }
    return add != NULL;
}

/* ---- Fita e papel (docs/PROTOCOL.md) ------------------------------------------ */

/* Nomes das fitas por (marca, tipo), da tabela do selphy_print
   (backend_mitsu.c, mitsu_media_types) para a CP-D90. */
static const struct { uint8_t brand, type; const char *name; } kRibbons[] = {
    {0xff, 0x01, "CK-D735"}, {0xff, 0x02, "CK-D746"}, {0xff, 0x04, "CK-D757"},
    {0xff, 0x05, "CK-D769"}, {0xff, 0x0f, "CK-D768/CK-D868"},
    {0xe0, 0x0f, "CK-D868 SL"},
    {0xd1, 0x02, "CK-D715"}, {0xd1, 0x04, "CK-D718"}, {0xd1, 0x05, "CK-D723"},
    {0xd1, 0x0f, "CK-D720"},
    {0xd5, 0x02, "CK-D746-U"}, {0xd5, 0x04, "CK-D757-U"}, {0xd5, 0x05, "CK-D769-U"},
    {0xd5, 0x0f, "CK-D768-U"},
    {0x7a, 0x01, "Fujifilm RL-CF900"}, {0x7a, 0x02, "Fujifilm RK-CF800"},
    {0x7a, 0x04, "Fujifilm R2L-CF460"}, {0x7a, 0x0f, "Fujifilm R68-CF400"},
    {0xda, 0x01, "Fujifilm RL-CF900"}, {0xda, 0x02, "Fujifilm RK-CF800"},
    {0xda, 0x04, "Fujifilm R2L-CF460"}, {0xda, 0x0f, "Fujifilm R68-CF400"},
};

/* Classe de tamanho pelo nibble baixo do tipo: largura do papel e
   comprimento máximo em píxeis a 300 ppp (tabela de formatos, PROTOCOL.md).
   O 15x20 aceita o 10x15x2 (2488 linhas: duas fotos 10x15 com corte). */
static const struct { uint8_t cls; const char *size; int width, max_len; } kClasses[] = {
    {0x1, "9×13", 1550, 1076},
    {0x2, "10×15", 1852, 1226},
    {0x4, "13×18", 1550, 2128},
    {0x5, "15×23", 1852, 2729},
    {0xf, "15×20", 1852, 2488},
};

void mitsud90_query_media(int bidi, mitsud90_media_t *m) {
    static const uint8_t q[10] = {0x1b, 0x47, 0x44, 0x30, 0x00, 0x00,
                                  0x03, 0x1e, 0x16, 0x2a};
    mitsud90_resp_t r;
    memset(m, 0, sizeof *m);
    if (!bidi) return;
    mitsud90_put(q, sizeof q);
    mitsud90_read(bidi, 26, &r);
    if (!r.ok) return;
    m->ok = 1;
    m->brand = r.raw[0x10];
    m->type = r.raw[0x11];
    m->capacity = r.raw[0x14] << 8 | r.raw[0x15];
    m->remain = r.raw[0x16] << 8 | r.raw[0x17];
    for (size_t i = 0; i < sizeof kRibbons / sizeof *kRibbons; i++)
        if (kRibbons[i].brand == m->brand && kRibbons[i].type == m->type)
            m->name = kRibbons[i].name;
    for (size_t i = 0; i < sizeof kClasses / sizeof *kClasses; i++)
        if (kClasses[i].cls == (m->type & 0xf) && (m->type || m->brand)) {
            m->size = kClasses[i].size;
            m->width_px = kClasses[i].width;
            m->max_len_px = kClasses[i].max_len;
        }
    fprintf(stderr, "DEBUG: fita marca 0x%02x tipo 0x%02x (%s, %s), %u / %u\n", m->brand,
            m->type, m->name ? m->name : "?", m->size ? m->size : "?", m->remain, m->capacity);
}

int mitsud90_media_fits(const mitsud90_media_t *m, int page_w, int page_h) {
    if (!m->ok || !m->width_px) return 1;
    return page_w == m->width_px && page_h <= m->max_len_px;
}
