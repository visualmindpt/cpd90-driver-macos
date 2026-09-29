/*
 * printer_emulator — corre um filtro CUPS fora do CUPS, fazendo de
 * impressora CP-D90 para testes: responde ao side channel (fd 4) e, a cada
 * CUPS_SC_CMD_DRAIN_OUTPUT, devolve no back channel (fd 3) uma resposta de
 * estado (docs/PROTOCOL.md). Guarda os bytes que o filtro enviaria à
 * impressora.
 *
 * Variáveis: HARNESS_NO_BIDI=1 (sem canal bidireccional),
 * HARNESS_STATUS=0xNNNN (código de erro), HARNESS_LEVELS=rest/total/tipo/marca.
 *
 * Uso: printer_emulator <filtro> <ppd> <entrada> <opcoes> <saida.bin> <log>
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

enum { SC_GET_BIDI = 3, SC_DRAIN_OUTPUT = 2, SC_GET_DEVICE_ID = 4,
       SC_GET_STATE = 5, SC_SOFT_RESET = 1 };
enum { SC_STATUS_OK = 1, SC_STATUS_NOT_IMPLEMENTED = 7 };

/* Resposta de estado (32 bytes): [4..5] código; para o pedido de níveis,
   [0x11] tipo de fita, [0x14..15] total e [0x16..17] restantes. */
static const unsigned char kStatusOk[32] = {0xe4, 0x47, 0x44, 0x30};

static int write_all(int fd, const void *buf, size_t n) {
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr,
                "uso: %s <filtro> <ppd> <raster> <opcoes> <saida> <log>\n",
                argv[0]);
        return 2;
    }
    const char *filter = argv[1], *ppd = argv[2], *raster = argv[3],
               *options = argv[4], *out = argv[5], *log = argv[6];

    int sc[2], bc[2];
    if (socketpair(AF_LOCAL, SOCK_STREAM, 0, sc) || pipe(bc)) {
        perror("socketpair/pipe");
        return 1;
    }
    int outfd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int logfd = open(log, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (outfd < 0 || logfd < 0) {
        perror("open");
        return 1;
    }

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&fa, outfd, 1);
    posix_spawn_file_actions_adddup2(&fa, logfd, 2);
    posix_spawn_file_actions_adddup2(&fa, bc[0], 3);
    posix_spawn_file_actions_adddup2(&fa, sc[1], 4);

    char ppdenv[4096];
    snprintf(ppdenv, sizeof ppdenv, "PPD=%s", ppd);
    char *envp[] = {ppdenv, "CUPS_SERVERROOT=/etc/cups",
                    "LANG=C", "PATH=/usr/bin:/bin",
                    NULL};
    /* HARNESS_NO_BIDI=1 simula uma ligação sem canal bidireccional;
       HARNESS_STATUS=0xNNNN faz a impressora responder com esse erro. */
    const int no_bidi = getenv("HARNESS_NO_BIDI") != NULL;
    unsigned status_code = getenv("HARNESS_STATUS")
                               ? (unsigned)strtoul(getenv("HARNESS_STATUS"), NULL, 0)
                               : 0;
    unsigned char status_resp[32];
    memcpy(status_resp, kStatusOk, sizeof status_resp);
    status_resp[4] = (unsigned char)(status_code >> 8);
    status_resp[5] = (unsigned char)status_code;
    /* HARNESS_LEVELS=restantes/total/tipo[/marca], ex.: 170/430/0x0f/0xff */
    if (getenv("HARNESS_LEVELS")) {
        unsigned rem = 0, tot = 0;
        int typ = 0, brand = 0;
        sscanf(getenv("HARNESS_LEVELS"), "%u/%u/%i/%i", &rem, &tot, &typ, &brand);
        status_resp[0x10] = (unsigned char)brand;
        status_resp[0x11] = (unsigned char)typ;
        status_resp[0x14] = (unsigned char)(tot >> 8);
        status_resp[0x15] = (unsigned char)tot;
        status_resp[0x16] = (unsigned char)(rem >> 8);
        status_resp[0x17] = (unsigned char)rem;
    }
    char *args[] = {(char *)filter, "1", "user", "teste", "1",
                    (char *)options, (char *)raster, NULL};

    pid_t pid;
    int rc = posix_spawn(&pid, filter, &fa, NULL, args, envp);
    if (rc) {
        fprintf(stderr, "posix_spawn: %s\n", strerror(rc));
        return 1;
    }
    close(sc[1]);
    close(bc[0]);
    close(outfd);
    close(logfd);

    int drains = 0, requests = 0;
    for (;;) {
        struct pollfd p = {.fd = sc[0], .events = POLLIN};
        int n = poll(&p, 1, 200);
        if (n == 0) {
            int st;
            if (waitpid(pid, &st, WNOHANG) == pid) {
                fprintf(stderr, "filtro terminou: %s %d | pedidos=%d drains=%d\n",
                        WIFEXITED(st) ? "exit" : "sinal",
                        WIFEXITED(st) ? WEXITSTATUS(st) : WTERMSIG(st),
                        requests, drains);
                return WIFEXITED(st) ? WEXITSTATUS(st) : 128;
            }
            continue;
        }
        unsigned char req[4 + 65540];
        ssize_t r = read(sc[0], req, sizeof req);
        if (r <= 0) {
            int st;
            waitpid(pid, &st, 0);
            fprintf(stderr, "filtro terminou: %s %d | pedidos=%d drains=%d\n",
                    WIFEXITED(st) ? "exit" : "sinal",
                    WIFEXITED(st) ? WEXITSTATUS(st) : WTERMSIG(st),
                    requests, drains);
            return WIFEXITED(st) ? WEXITSTATUS(st) : 128;
        }
        requests++;
        fprintf(stderr, "sc req (%zd):", r);
        for (ssize_t i = 0; i < r && i < 16; i++) fprintf(stderr, " %02x", req[i]);
        fprintf(stderr, "\n");
        unsigned char resp[5] = {req[0], SC_STATUS_OK, 0, 0, 0};
        size_t rlen = 4;
        switch (req[0]) {
        case SC_GET_BIDI:
            resp[3] = 1;
            resp[4] = no_bidi ? 0 : 1; /* CUPS_SC_BIDI_SUPPORTED */
            rlen = 5;
            break;
        case SC_DRAIN_OUTPUT:
            drains++;
            if (!no_bidi) write_all(bc[1], status_resp, sizeof status_resp);
            break;
        default:
            resp[1] = SC_STATUS_NOT_IMPLEMENTED;
            break;
        }
        write_all(sc[0], resp, rlen);
    }
}
