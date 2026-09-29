# CP-D90DW data stream and driver behaviour

**[English](#english) · [Português](#português)**

---

## English

This document describes the USB data stream of the Mitsubishi CP-D90DW as
implemented by this driver. The protocol is documented publicly by the
selphy_print / Gutenprint project (`backend_mitsud90.c`); the field values
below were verified by printing on a real CP-D90DW. Integers are big-endian.

### 1. Job sequence

For each page:

```
ESC G D 0   (8 bytes)    status query          -> response on the back channel
ESC G D 3   (512 bytes)  job check             -> response on the back channel
ESC S P 0   (512 bytes)  job header
ESC Z T 01  (512 bytes)  image header
RGB         (W*H*3)      pixels, 8 bits per channel, top to bottom
```

At the end of the job: a final status query, then `ESC B Q 1` (6 bytes,
print). This driver also sends a ribbon query (§6) at the start of each job.

- **Status query** `1b 47 44 30 00 00 01 16`: after `CUPS_SC_CMD_DRAIN_OUTPUT`,
  read ≥ 15 bytes; the status code is `resp[4..5]` (0 = ready).
- **Job check** `1b 47 44 33` + the same 508-byte body as the job header;
  read ≥ 6 bytes, `resp[4..5] ≠ 0` means the job is refused.

### 2. Job header (`1b 53 50 30` + 508 bytes, zero unless listed)

| Offset | Value | Meaning |
|---|---|---|
| 05 | 0x33 | constant |
| 06–07 | u16 | page width (1852 for 6" paper, 1550 for 5") |
| 08–09 | u16 | page height |
| 0a | 0x64 | constant |
| 0e | 0/1 | margin cut-off |
| 0f | 0/1 | multi-cut (×2 formats) |
| 10–11 | u16 | cut position (1214 for 10x15x2, 613 for 5x15x2) |
| 12 | 0/1 | 1 for 2" strip formats |
| 30 | 0/2 | finish: 0 glossy, 2 matte |
| 31 | 0/2/3 | mode: 0 auto, 2 ultra fine, 3 fine |
| 32 | 0/1 | 1 = printer colour conversion off |
| 33, 34 | 0–8 | horizontal / vertical sharpness (off 0, −3 1 … normal 4, +1 5, +2 6, +3 8) |

### 3. Image header (`1b 5a 54 01` + 508 bytes)

| Offset | Meaning |
|---|---|
| 05 | 0x09 |
| 06–07, 08–09 | image origin X, Y (84, 71 for white-border formats; else 0) |
| 0a–0b, 0c–0d | image width, height |

### 4. Formats (300 dpi)

The image is the CUPS raster cropped from the top-left corner.

| PageSize | Page | Image | Origin | Cut |
|---|---|---|---|---|
| ME_9x13 | 1550×1076 | 1550×1076 | 0,0 | — |
| ME_10x15 | 1852×1226 | 1852×1226 | 0,0 | — |
| ME_13x18 | 1550×2128 | 1550×2128 | 0,0 | — |
| ME_15x20 | 1852×2428 | 1852×2428 | 0,0 | — |
| ME_15x21 | 1852×2568 | 1852×2568 | 0,0 | — |
| ME_15x23 | 1852×2729 | 1852×2729 | 0,0 | — |
| ME_10x15x2 | 1852×2488 | 1852×2488 | 0,0 | 1214 |
| ME_5x15x2_1 | 1852×1226 | 1852×1226 | 0,0 | 613 (one page = two strips) |
| ME_5x15x2_2 | 1852×1226 | 1852×1226 | 0,0 | 613 (two pages per sheet, §5) |
| ME_5x15 | 1852×625 | 1852×625 | 0,0 | — |
| ME_15x15 | 1852×1827 | 1852×1827 | 0,0 | — |
| ME_13x13 | 1550×1527 | 1550×1527 | 0,0 | — |
| ME_9x13_WB | 1550×1076 | 1382×934 | 84,71 | — |
| ME_10x15_WB | 1852×1226 | 1684×1084 | 84,71 | — |
| ME_13x18_WB | 1550×2128 | 1382×1986 | 84,71 | — |
| ME_15x20_WB | 1852×2428 | 1684×2286 | 84,71 | — |
| ME_15x23_WB | 1852×2729 | 1684×2587 | 84,71 | — |

### 5. Two strips per sheet (ME_5x15x2_2)

Each page is a 2×6" strip (1852×613). Two pages make one 1852×1226 image:
rows 0–612 = the second page, rows 613–1225 = the first. With an odd number
of pages the last one is sent at the end with rows 0–612 white.

### 6. Ribbon and status

- **Ribbon query** `1b 47 44 30 00 00 03 1e 16 2a` (≥ 26 bytes): brand 0x10,
  type 0x11, capacity 0x14–15, remaining 0x16–17. The low nibble of the type
  is the size class: 1 = 9×13, 2 = 10×15, 4 = 13×18, 5 = 15×23, f = 15×20.
  The ribbon names follow selphy_print's media table (e.g. brand 0xff type
  0x0f = CK-D768/CK-D868). On the CK-D868, capacity is counted in 10×15
  prints (430 per roll).
- **Status codes** map to the PPD reasons `com.mitsubishi-errorCCCC_XXXX`
  (XXXX = code in hex), or `errorNNNN` for codes 0x0001–0x0005, 0x0032,
  0x0033; unknown codes give `error0004`.
- This driver refuses a job **before sending any image** if the format does
  not fit the loaded ribbon (paper width 5"/6", or longer than the class
  maximum 1076 / 1226 / 2128 / 2729 / 2488 lines), and warns at ≤ 5 %.

### 7. Colour

By default the driver sends the pixels unchanged; colour conversion,
sharpening, fine modes and matte are done by the printer. Optional
adjustments (PPD options, all 0 by default), applied as a per-channel LUT:

1. gamma −5…+5: `out = floor(255·(i/255)^e + 0.5)`, e = 2.6138, 1.7034,
   1.4528, 1.2516, 1.1004 (−5…−1) and 0.899, 0.799, 0.6987, 0.5983, 0.3976
   (+1…+5);
2. contrast c and brightness b: `out = clamp(t + i·c·k + b, 0, 255)`,
   k = 1/128 (c ≥ 0) or 1/256 (c < 0);
3. calibration per finish (this driver): axes L (lightness), M (magenta),
   W (warmth), −10…+10; `e = 2^(−0.04·t)` with tR = L+W, tG = L+M, tB = L−W.

---

## Português

Este documento descreve o fluxo de dados USB da Mitsubishi CP-D90DW tal como
este driver o implementa. O protocolo está documentado publicamente pelo
projeto selphy_print / Gutenprint (`backend_mitsud90.c`); os valores foram
verificados a imprimir numa CP-D90DW real.

- **Sequência** (§1): por página, pedido de estado (`ESC G D 0`), verificação
  da tarefa (`ESC G D 3`), cabeçalho da tarefa (`ESC S P 0`), cabeçalho da
  imagem (`ESC Z T`) e os píxeis RGB; no fim, pedido de estado e `ESC B Q 1`.
  O driver envia também um pedido de estado da fita no início de cada tarefa.
- **Cabeçalhos** (§2, §3): tamanho da página e da imagem, corte, acabamento
  (brilhante/mate), modo (auto/fine/ultra fine), conversão de cor da
  impressora e nitidez, com os valores da tabela em inglês.
- **Formatos** (§4) e **duas tiras por folha** (§5): ver as tabelas acima.
- **Fita e estado** (§6): nome e classe de tamanho da fita, capacidade e
  restantes (na CK-D868, em fotos 10×15), razões de erro do PPD, e recusa de
  formatos que não cabem na fita antes de enviar qualquer imagem.
- **Cor** (§7): por omissão os píxeis passam intactos; gama, contraste,
  brilho e a calibração por acabamento são ajustes opcionais, a 0 por
  omissão.
