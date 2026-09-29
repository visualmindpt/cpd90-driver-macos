# Lightroom Classic → CP-D90DW (15x20, Ultra Fine)

> **English summary.** Lightroom Classic settings for the CP-D90DW, measured on
> the actual output: use the CP-D90's own 15x20 paper (not a generic 15x20),
> margins 0, cell at full size, print resolution 300 ppi, profile CPD90_UF,
> and turn off "scale to fit paper" in the macOS print dialog. With a generic
> paper size, macOS enlarged the image ~2.8% and left 1.4 mm white strips.

Configuração validada em 2026-09-29 por medição. A PDF exportada pelo
diálogo de impressão foi passada pela mesma cadeia do macOS
(`cupsfilter … -m application/vnd.cups-raster`) e a raster resultante foi
analisada.

## Módulo Imprimir

| Onde | Definição |
|---|---|
| Configuração de página… | Impressora `CPD90_Universal_Teste` (ou a fila migrada); papel **15x20 da CP-D90** (`ME_15x20`, 15,70 × 20,57 cm), **não** um 15x20 genérico; escala 100 % |
| Estilo de layout | Imagem única / Folha de contacto; Zoom para preencher ✓; Girar para ajustar ✓ |
| Layout | Margens 0; célula no máximo (≈ 20,57 × 15,70 cm). No Pacote personalizado: desativar "Bloquear proporção da foto" |
| Trabalho de impressão | Rascunho ✗; Resolução de impressão **300 ppi** ✓; Nitidez Padrão, Brilhante; 16 bits ✗; Perfil **CPD90_UF** (aparece como "CPD70_UF.icc", o nome interno da Mitsubishi); Perceptivo; Ajuste de impressão Brilho +10 |
| Diálogo Imprimir → Gestão de papel | **"Ajustar proporcionalmente ao papel" desativado** |
| Diálogo Imprimir → Opções da impressora | Ultra Fine; Conversão de cor na impressora **desligada**; Nitidez Normal (0), porque o Lightroom já aplica nitidez |

## Medições

| Teste | Imagem enviada pelo Lightroom | Colocação na página 445×583 pt | Raster (1854×2429) |
|---|---|---|---|
| 1 e 2: papel 15x20 genérico + "Ajustar ao papel" | 2361×1771 px (20×15 cm @300) | ampliada ~2,8 % para 437×583 pt | faixas brancas de 16/15 px dos lados |
| 3: papel ME_15x20, sem ajuste | **2428×1853 px** | 444,8×582,8 pt → **300,0 ppi** | **sem faixas brancas**; 1:1, sem reamostragem relevante |

Causa: com o papel genérico de 15×20 cm, o Lightroom paginava para uma
folha mais pequena do que a da CP-D90 (que imprime para além da borda do
papel), e o macOS ampliava a imagem para a encaixar. Isso tirava nitidez e
deixava margens.
