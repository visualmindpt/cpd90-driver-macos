/*
 * rastertomitsud90 — filtro CUPS para a Mitsubishi CP-D90DW.
 *
 * Converte application/vnd.cups-raster (RGB, 8 bits, 300 dpi) no fluxo de
 * comandos da impressora. Ver docs/PROTOCOL.md; as
 * referências "§n" apontam para as secções desse documento.
 *
 * Uso (pelo CUPS): rastertomitsud90 job user title copies options [file]
 *
 * Copyright (C) 2026 Nelson Silva. Licença: GPL-3.0-or-later.
 */
#include <cups/cups.h>
#include <cups/ppd.h>
#include <cups/raster.h>
#include <cups/sidechannel.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "mitsud90_common.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"


/* ---------------------------------------------------------------- §2 */

typedef struct {
    const char *name;
    uint16_t page_w, page_h;   /* cabeçalho SP0 */
    uint16_t img_w, img_h;     /* cabeçalho ZT e dados enviados */
    uint16_t org_x, org_y;     /* origem da imagem (formatos _WB) */
    uint16_t cut;              /* posição do corte, 0 = sem corte */
    uint8_t strip;             /* SP0[0x12]: tiras de 2" */
    uint8_t combine;           /* §3: duas páginas por folha */
} media_t;

static const media_t kMedia[] = {
    {"ME_9x13", 1550, 1076, 1550, 1076, 0, 0, 0, 0, 0},
    {"ME_10x15", 1852, 1226, 1852, 1226, 0, 0, 0, 0, 0},
    {"ME_13x18", 1550, 2128, 1550, 2128, 0, 0, 0, 0, 0},
    {"ME_15x20", 1852, 2428, 1852, 2428, 0, 0, 0, 0, 0},
    {"ME_15x21", 1852, 2568, 1852, 2568, 0, 0, 0, 0, 0},
    {"ME_15x23", 1852, 2729, 1852, 2729, 0, 0, 0, 0, 0},
    {"ME_10x15x2", 1852, 2488, 1852, 2488, 0, 0, 1214, 0, 0},
    {"ME_5x15x2_1", 1852, 1226, 1852, 1226, 0, 0, 613, 1, 0},
    {"ME_5x15x2_2", 1852, 1226, 1852, 1226, 0, 0, 613, 1, 1},
    {"ME_5x15", 1852, 625, 1852, 625, 0, 0, 0, 0, 0},
    {"ME_15x15", 1852, 1827, 1852, 1827, 0, 0, 0, 0, 0},
    {"ME_13x13", 1550, 1527, 1550, 1527, 0, 0, 0, 0, 0},
    {"ME_9x13_WB", 1550, 1076, 1382, 934, 84, 71, 0, 0, 0},
    {"ME_10x15_WB", 1852, 1226, 1684, 1084, 84, 71, 0, 0, 0},
    {"ME_13x18_WB", 1550, 2128, 1382, 1986, 84, 71, 0, 0, 0},
    {"ME_15x20_WB", 1852, 2428, 1684, 2286, 84, 71, 0, 0, 0},
    {"ME_15x23_WB", 1852, 2729, 1684, 2587, 84, 71, 0, 0, 0},
};
#define COMBINE_HALF_H 613 /* §3 */

/* ---------------------------------------------------------------- §5 */

typedef struct {
    const media_t *media;
    uint8_t margin_cut, finish, mode, color_off, sharp_h, sharp_v;
    uint8_t wait; /* byte final do ESC B Q 1 (§1.5) */
    int gamma[3], contrast[3], brightness[3];
    int cal[3]; /* calibração do acabamento da tarefa: luz, magenta, calor (§12) */
} settings_t;

static const char *choice(ppd_file_t *ppd, const char *opt, const char *def) {
    ppd_choice_t *c = ppd ? ppdFindMarkedChoice(ppd, opt) : NULL;
    return c ? c->choice : def;
}

static int choice_int(ppd_file_t *ppd, const char *opt, int lo, int hi) {
    int v = atoi(choice(ppd, opt, "0"));
    return v < lo ? lo : v > hi ? hi : v;
}

static uint8_t sharpness(const char *v) {
    static const struct { const char *n; uint8_t v; } k[] = {
        {"None", 0}, {"Minus3", 1}, {"Minus2", 2}, {"Minus1", 3},
        {"Normal", 4}, {"Plus1", 5}, {"Plus2", 6}, {"Plus3", 8}};
    for (size_t i = 0; i < sizeof k / sizeof *k; i++)
        if (!strcasecmp(v, k[i].n)) return k[i].v;
    return 4;
}

static int read_settings(ppd_file_t *ppd, const char *page_size,
                         settings_t *s) {
    memset(s, 0, sizeof *s);
    for (size_t i = 0; i < sizeof kMedia / sizeof *kMedia; i++)
        if (!strcasecmp(page_size, kMedia[i].name)) s->media = &kMedia[i];
    if (!s->media) return -1;

    s->margin_cut = !strcasecmp(choice(ppd, "MEMarginCutOff", "False"), "True");
    s->finish = !strcasecmp(choice(ppd, "MEPrintFinish", "Gloss"), "Matte") ? 2 : 0;
    const char *mode = choice(ppd, "MEPrintMode", "Auto");
    s->mode = !strcasecmp(mode, "Fine") ? 3 : !strcasecmp(mode, "UltraFine") ? 2 : 0;
    s->color_off =
        !strcasecmp(choice(ppd, "MEColorConversion", "Enabled"), "Disabled");
    if (!strcasecmp(choice(ppd, "MESharpnessDetail", "False"), "True")) {
        s->sharp_h = sharpness(choice(ppd, "MESharpness_H", "Normal"));
        s->sharp_v = sharpness(choice(ppd, "MESharpness_V", "Normal"));
    } else {
        s->sharp_h = s->sharp_v =
            sharpness(choice(ppd, "MESharpness_Common", "Normal"));
    }
    if (!strcasecmp(choice(ppd, "MEWaitingNextImage", "True"), "False"))
        s->wait = 0xff;
    else
        s->wait = (uint8_t)choice_int(ppd, "MEWaitTime", 0, 0xfe);
    static const char *const ch = "RGB";
    for (int c = 0; c < 3; c++) {
        char n[32];
        snprintf(n, sizeof n, "MEGamma%c", ch[c]);
        s->gamma[c] = choice_int(ppd, n, -5, 5);
        snprintf(n, sizeof n, "MEContrast%c", ch[c]);
        s->contrast[c] = choice_int(ppd, n, -128, 128);
        snprintf(n, sizeof n, "MEBrightness%c", ch[c]);
        s->brightness[c] = choice_int(ppd, n, -128, 128);
    }
    /* Calibração (§12): o conjunto é escolhido pelo acabamento da tarefa. */
    static const char *const axis[3] = {"L", "M", "W"};
    for (int a = 0; a < 3; a++) {
        char n[32];
        snprintf(n, sizeof n, "MECal%s%s", s->finish == 2 ? "Matte" : "Gloss", axis[a]);
        s->cal[a] = choice_int(ppd, n, -10, 10);
    }
    return 0;
}

/* ---------------------------------------------------------------- §4 */

/*
 * Curvas de calibração (§12). Cada eixo em passos de −10 a +10:
 *   L luminosidade (+ mais clara), M magenta (+ menos magenta, mais verde),
 *   W calor (+ mais quente: mais vermelho, menos azul).
 * Por canal, uma curva de potência out = 255·(i/255)^e com
 *   e = 2^(−0,04·t),  tR = L + W,  tG = L + M,  tB = L − W.
 * Um passo desloca os meios-tons ~2,5 níveis. É a única implementação desta
 * fórmula: a cpd90-print obtém as curvas com `rastertomitsud90 --curva`.
 */
#define CAL_STEP 0.04
static int cal_lut(const int cal[3], uint8_t lut[3][256]) {
    const int t[3] = {cal[0] + cal[2], cal[0] + cal[1], cal[0] - cal[2]};
    for (int c = 0; c < 3; c++) {
        double e = pow(2.0, -CAL_STEP * t[c]);
        for (int i = 0; i < 256; i++)
            lut[c][i] = (uint8_t)floor(255.0 * pow(i / 255.0, e) + 0.5);
    }
    return cal[0] || cal[1] || cal[2];
}

/* Devolve 0 se não há ajustes (os pixels passam intactos). Ordem: gama,
   contraste e brilho (§4), depois a calibração do acabamento (§12). */
static int build_lut(const settings_t *s, uint8_t lut[3][256]) {
    static const double kGammaExp[11] = {
        2.6138, 1.7034, 1.4528, 1.2516, 1.1004, 1.0,
        0.899, 0.799, 0.6987, 0.5983, 0.3976};
    int any = 0;
    for (int c = 0; c < 3; c++) {
        any |= s->gamma[c] | s->contrast[c] | s->brightness[c];
        double e = kGammaExp[s->gamma[c] + 5];
        double k = s->contrast[c] * (s->contrast[c] >= 0 ? 1.0 / 128 : 1.0 / 256);
        for (int i = 0; i < 256; i++) {
            double t = s->gamma[c] ? floor(255.0 * pow(i / 255.0, e) + 0.5) : i;
            double v = t + i * k + s->brightness[c];
            v = v > 255.0 ? 255.0 : v < 0.0 ? 0.0 : v;
            lut[c][i] = (uint8_t)v;
        }
    }
    uint8_t cal[3][256];
    if (cal_lut(s->cal, cal)) {
        for (int c = 0; c < 3; c++)
            for (int i = 0; i < 256; i++) lut[c][i] = cal[c][lut[c][i]];
        any = 1;
    }
    return any;
}

/* ---------------------------------------------------------------- §1 */

static int g_bidi;
static ppd_file_t *g_ppd;
#define put mitsud90_put

/* Termina a tarefa se a impressora devolver um código de erro. */
static void check_printer(size_t min, const char *what) {
    mitsud90_resp_t r;
    mitsud90_read(g_bidi, min, &r);
    if (!r.ok) {
        if (g_bidi)
            fprintf(stderr, "WARNING: Sem resposta de estado da impressora; "
                            "a continuar.\n");
        return;
    }
    int code = mitsud90_code(&r);
    if (code) {
        mitsud90_report_state(g_ppd, code);
        fprintf(stderr, "ERROR: A impressora recusou %s (código %04x).\n",
                what, code);
        exit(1);
    }
}

static void status_query(void) {
    static const uint8_t q[8] = {0x1b, 0x47, 0x44, 0x30, 0x00, 0x00, 0x01, 0x16};
    put(q, sizeof q);
    check_printer(15, "a tarefa");
}

static void sp_body(uint8_t b[512], const settings_t *s) {
    const media_t *m = s->media;
    memset(b, 0, 512);
    b[5] = 0x33;
    b[6] = m->page_w >> 8, b[7] = m->page_w & 0xff;
    b[8] = m->page_h >> 8, b[9] = m->page_h & 0xff;
    b[0x0a] = 0x64;
    b[0x0e] = s->margin_cut;
    if (m->cut) {
        b[0x0f] = 1;
        b[0x10] = m->cut >> 8, b[0x11] = m->cut & 0xff;
    }
    b[0x12] = m->strip;
    b[0x30] = s->finish;
    b[0x31] = s->mode;
    b[0x32] = s->color_off;
    b[0x33] = s->sharp_h;
    b[0x34] = s->sharp_v;
}

static void job_check(const settings_t *s) {
    uint8_t b[512];
    sp_body(b, s);
    memcpy(b, "\x1bGD3", 4);
    put(b, sizeof b);
    check_printer(6, "o formato de impressão");
}

static void print_image(const settings_t *s, const uint8_t *img, int page) {
    const media_t *m = s->media;
    uint8_t b[512];
    sp_body(b, s);
    memcpy(b, "\x1bSP0", 4);
    put(b, sizeof b);

    memset(b, 0, sizeof b);
    memcpy(b, "\x1bZT\x01", 4);
    b[5] = 0x09;
    b[6] = m->org_x >> 8, b[7] = m->org_x & 0xff;
    b[8] = m->org_y >> 8, b[9] = m->org_y & 0xff;
    b[10] = m->img_w >> 8, b[11] = m->img_w & 0xff;
    b[12] = m->img_h >> 8, b[13] = m->img_h & 0xff;
    put(b, sizeof b);

    put(img, (size_t)m->img_w * m->img_h * 3);
    fprintf(stderr, "INFO: Página %d enviada\n", page);
    fflush(stdout);
}

/* ------------------------------------------------------------- main */

static volatile sig_atomic_t g_cancel;
static void on_term(int sig) { (void)sig; g_cancel = 1; }

int main(int argc, char **argv) {
    /* Tabela de tamanhos para outras ferramentas (cpd90-print): é a única
       fonte da geometria de cada formato.
       Colunas: nome largura altura combina(0/1) altura_por_página */
    /* Curvas de calibração para a folha de teste da cpd90-print:
       `--curva L M W` -> 3 linhas (R, G, B) de 256 valores. */
    if (argc == 5 && !strcmp(argv[1], "--curva")) {
        int cal[3] = {atoi(argv[2]), atoi(argv[3]), atoi(argv[4])};
        uint8_t lut[3][256];
        cal_lut(cal, lut);
        for (int c = 0; c < 3; c++)
            for (int i = 0; i < 256; i++) printf("%u%c", lut[c][i], i == 255 ? '\n' : ' ');
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--media")) {
        for (size_t i = 0; i < sizeof kMedia / sizeof *kMedia; i++)
            printf("%s %u %u %u %u\n", kMedia[i].name, kMedia[i].img_w,
                   kMedia[i].img_h, kMedia[i].combine,
                   kMedia[i].combine ? COMBINE_HALF_H : kMedia[i].img_h);
        return 0;
    }
    if (argc < 6 || argc > 7) {
        fputs("Uso: rastertomitsud90 job user title copies options [file]\n",
              stderr);
        return 1;
    }
    setbuf(stderr, NULL);
    fprintf(stderr, "DEBUG: rastertomitsud90 " DRIVER_VERSION "\n");
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, on_term);

    int fd = 0;
    if (argc == 7 && (fd = open(argv[6], O_RDONLY)) < 0) {
        fprintf(stderr, "ERROR: Não foi possível abrir a raster: %s\n",
                strerror(errno));
        return 1;
    }

    ppd_file_t *ppd = g_ppd = ppdOpenFile(getenv("PPD"));
    mitsud90_report_state(ppd, 0);
    cups_option_t *opts = NULL;
    int nopts = cupsParseOptions(argv[5], 0, &opts);
    if (ppd) {
        ppdMarkDefaults(ppd);
        cupsMarkOptions(ppd, nopts, opts);
    }

    settings_t s;
    const char *page_size = choice(ppd, "PageSize", NULL);
    if (!page_size) page_size = cupsGetOption("PageSize", nopts, opts);
    if (!page_size || read_settings(ppd, page_size, &s)) {
        fprintf(stderr, "ERROR: Tamanho de papel não suportado: %s\n",
                page_size ? page_size : "(nenhum)");
        return 1;
    }
    uint8_t lut[3][256];
    int use_lut = build_lut(&s, lut);

    g_bidi = mitsud90_bidi();
    if (!g_bidi)
        fprintf(stderr, "WARNING: Ligação sem canal bidireccional; o estado "
                        "da impressora não será verificado.\n");

    /* §13: confirmar, antes de enviar qualquer imagem, que o formato cabe na
       fita instalada, e avisar se a fita estiver a acabar. */
    mitsud90_media_t fita;
    mitsud90_query_media(g_bidi, &fita);
    if (!mitsud90_media_fits(&fita, s.media->page_w, s.media->page_h)) {
        mitsud90_report_state(ppd, 0x0005);
        fprintf(stderr, "ERROR: O formato %s não cabe na fita instalada (%s%s%s). "
                        "Escolha um formato para fita %s.\n", s.media->name + 3,
                fita.name ? fita.name : "", fita.name ? ", " : "", fita.size, fita.size);
        return 1;
    }
    if (fita.ok && fita.capacity && fita.remain * 100u / fita.capacity <= 5)
        fprintf(stderr, "WARNING: A fita está a acabar: restam %u impressões.\n", fita.remain);

    const media_t *m = s.media;
    const size_t img_bytes = (size_t)m->img_w * m->img_h * 3;
    const size_t half_bytes = (size_t)m->img_w * COMBINE_HALF_H * 3;
    uint8_t *img = malloc(img_bytes);
    uint8_t *pending = m->combine ? malloc(half_bytes) : NULL;
    int have_pending = 0;

    cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
    cups_page_header2_t h;
    int page = 0;
    uint8_t *line = NULL;
    size_t line_cap = 0;

    while (!g_cancel && cupsRasterReadHeader2(ras, &h)) {
        page++;
        fprintf(stderr, "PAGE: %d 1\n", page);
        if (h.cupsBitsPerPixel != 24 || h.cupsColorOrder != CUPS_ORDER_CHUNKED) {
            fprintf(stderr, "ERROR: Formato de raster não suportado "
                            "(%u bpp, ordem %d)\n", h.cupsBitsPerPixel,
                    h.cupsColorOrder);
            return 1;
        }
        status_query();
        job_check(&s);

        /* Recorte a partir do canto superior esquerdo; o que faltar na
           raster fica branco (§2). */
        unsigned rows = m->combine ? COMBINE_HALF_H : m->img_h;
        size_t row_bytes = (size_t)m->img_w * 3;
        size_t copy = h.cupsWidth < m->img_w ? (size_t)h.cupsWidth * 3 : row_bytes;
        if (h.cupsBytesPerLine > line_cap)
            line = realloc(line, line_cap = h.cupsBytesPerLine);
        memset(img, 0xff, img_bytes);
        for (unsigned y = 0; y < h.cupsHeight; y++) {
            if (!cupsRasterReadPixels(ras, line, h.cupsBytesPerLine)) break;
            if (y < rows) memcpy(img + y * row_bytes, line, copy);
        }
        if (use_lut)
            for (size_t i = 0; i < (size_t)rows * row_bytes; i += 3) {
                img[i] = lut[0][img[i]];
                img[i + 1] = lut[1][img[i + 1]];
                img[i + 2] = lut[2][img[i + 2]];
            }

        if (!m->combine) {
            print_image(&s, img, page);
        } else if (!have_pending) {
            memcpy(pending, img, half_bytes);
            have_pending = 1;
        } else {
            /* §3: a página nova em cima, a anterior em baixo. */
            memcpy(img + half_bytes, pending, half_bytes);
            print_image(&s, img, page);
            have_pending = 0;
        }
    }
    cupsRasterClose(ras);
    if (fd) close(fd);

    if (page == 0) {
        fputs("ERROR: Nenhuma página encontrada.\n", stderr);
        return 1;
    }
    status_query();
    if (have_pending) {
        memset(img, 0xff, half_bytes);
        memcpy(img + half_bytes, pending, half_bytes);
        print_image(&s, img, page);
    }
    uint8_t end[6] = {0x1b, 0x42, 0x51, 0x31, 0x00, s.wait};
    put(end, sizeof end);
    fflush(stdout);

    free(img);
    free(pending);
    free(line);
    cupsFreeOptions(nopts, opts);
    if (ppd) ppdClose(ppd);
    return g_cancel ? 1 : 0;
}
