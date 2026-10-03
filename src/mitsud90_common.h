/*
 * Código partilhado pelos filtros CP-D90: pedidos de estado à impressora e
 * razões de estado do CUPS (docs/PROTOCOL.md).
 *
 * Copyright (C) 2026 Nelson Silva. Licença: GPL-3.0-or-later.
 */
#ifndef MITSUD90_COMMON_H
#define MITSUD90_COMMON_H

#include <cups/ppd.h>
#include <stddef.h>
#include <stdint.h>

/* Única definição da versão; lida por tools/gen_ppd.py, pelo Makefile (cpd90-print),
   build_pkg.sh e verify_pkg.sh. */
#define DRIVER_VERSION "1.4.1"

/* Resposta da impressora a um pedido ESC G D 0. */
typedef struct {
    int ok;               /* 1 se a resposta foi lida */
    uint8_t raw[512];
    size_t len;
} mitsud90_resp_t;

/* 1 se o backend tem canal bidireccional (CUPS_SC_CMD_GET_BIDI). */
int mitsud90_bidi(void);

/* Escreve n bytes para a impressora (stdout); termina o processo em erro. */
void mitsud90_put(const void *buf, size_t n);

/*
 * Esvazia a saída (CUPS_SC_CMD_DRAIN_OUTPUT) e lê pelo menos `min` bytes do
 * back channel. Sem canal bidireccional devolve com ok=0 sem ler.
 */
void mitsud90_read(int bidi, size_t min, mitsud90_resp_t *r);

/* Código de estado de uma resposta: resp[4]<<8 | resp[5]. */
static inline int mitsud90_code(const mitsud90_resp_t *r) {
    return r->raw[4] << 8 | r->raw[5];
}

/*
 * Publica o estado da impressora como razões `com.mitsubishi-error*`
 * declaradas no PPD: retira todas as outras e acrescenta a do código
 * (0 = sem erro). Um código desconhecido dá error0004.
 * Devolve 1 se foi acrescentada alguma razão de erro.
 */
int mitsud90_report_state(ppd_file_t *ppd, int code);

/* ---- Fita e papel (docs/PROTOCOL.md) ------------------------------------------ */

typedef struct {
    int ok;                 /* 1 se a impressora respondeu */
    uint8_t brand, type;    /* resp[0x10], resp[0x11] */
    unsigned capacity;      /* resp[0x14..15] */
    unsigned remain;        /* resp[0x16..17] */
    const char *name;       /* ex.: "CK-D768/CK-D868", NULL se desconhecida */
    const char *size;       /* classe de tamanho: "15×20", "10×15", ... ou NULL */
    int width_px;           /* largura do papel (1550 = 5", 1852 = 6"), 0 se desconhecida */
    int max_len_px;         /* comprimento máximo da imagem, 0 se desconhecido */
} mitsud90_media_t;

/* Pede e interpreta o estado da fita (ESC G D 0, itens 1e/16/2a). */
void mitsud90_query_media(int bidi, mitsud90_media_t *m);

/* 1 se um formato (largura × altura da página, em píxeis) cabe na fita;
   também 1 se a fita for desconhecida (não se bloqueia sem saber). */
int mitsud90_media_fits(const mitsud90_media_t *m, int page_w, int page_h);

#endif
