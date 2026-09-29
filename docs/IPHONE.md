# Imprimir a partir do iPhone/iPad (AirPrint)

> **English summary.** Printing from iPhone/iPad. Sharing the CUPS queue is not
> enough (iOS needs AirPrint: `_universal`, `URF`, `image/urf`). The driver
> runs `ippeveprinter` from CUPS 2.4 (Homebrew; the macOS 2.3.4 one rejects
> iOS `Create-Job`), advertising 4×6" and 6×8" borderless sRGB at 300 dpi;
> each job is converted by `cpd90-print --airprint` and printed on the
> CP-D90 queue. Enable with `airprint/airprint.sh ativar`.

## Porque não basta partilhar a fila

O CUPS do macOS anuncia as filas partilhadas sem o subtipo `_universal` e
sem a chave `URF`, e a fila não aceita `image/urf`. O iOS não mostra uma
impressora nessas condições. Testado em 2026-09-29: com partilha ligada, e
mesmo com um anúncio Bonjour manual com `_universal`/`URF`, o iPhone não a
mostrou.

## Solução: servidor AirPrint próprio (ippeveprinter)

`ippeveprinter` é o servidor IPP Everywhere/AirPrint do CUPS. O do macOS
(CUPS 2.3.4) recusa o `Create-Job` do iOS ("Unexpected document data
following request"), por isso usa-se o do **CUPS 2.4 do Homebrew**
(`brew install cups`, keg-only, não substitui o CUPS do sistema).

```
iPhone --AirPrint (URF, sRGB, 300 ppp)--> ippeveprinter (Mac, porta 8632)
       --> cpd90-airprint-job --> cpd90-print --airprint --> fila CP-D90 --> rastertomitsud90
```

- `airprint/cpd90-airprint.conf`: 4×6" (`na_index-4x6_4x6in`) e 6×8"
  (`oe_photo-6x8_6x8in`) sem margens; só cor sRGB a 300 ppp. Com cinzento
  anunciado, o iOS escolheu `W8` e a pré-visualização ficou a preto e branco.
- `cpd90-print --airprint`: lê URF (`UNIRAST`), escolhe o formato pelo
  tamanho físico da página (lado maior ≥ 7" → 15x20, senão 10x15) e segue o
  caminho normal: sangria da CP-D90, nitidez, perfil CPD90_UF, Ultra Fine e
  conversão de cor da impressora desligada.
- `airprint/airprint.sh ativar|desativar|estado`: agente launchd da sessão
  (`~/Library/LaunchAgents/pt.nelsonsilva.cpd90-airprint.plist`, KeepAlive,
  registo em `~/Library/Logs/cpd90-airprint.log`). Não precisa de sudo.

## Observado com o iPhone real

| Teste | Resultado |
|---|---|
| Partilha da fila CUPS | não aparece no iPhone |
| ippeveprinter do macOS (2.3.4) | aparece; `Create-Job` recusado |
| ippeveprinter 2.4.19 | aparece; recebe `image/urf` (gzip) |
| Com cinzento disponível | iOS envia `W8` a 600 ppp (4×6) |
| Só `SRGB24`, `RS300` | iOS envia sRGB 1800×2400 @ 300 ppp (6×8) |
| **Serviço final (1.4.0), impressão real** | **impressa corretamente na CP-D90 (2026-09-29)** |
| Mesmo porto em testes sucessivos | o iOS reutiliza a entrada guardada; mudar de porta resolve |

## Testes

- `tools/test_cpd90_print.sh` teste 8: codificador URF independente (repetição,
  literais, 128 = resto a branco, linhas repetidas) → descodificação exata.
- Serviço local: `ippeveprinter` com a configuração final + Print-Job IPP com
  a foto real do iPhone → a cpd90-print produz a imagem 15x20 (1852×2428).
