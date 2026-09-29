# cpd90-print — impressão direta na CP-D90DW

> **English summary.** `cpd90-print` prints images (JPEG, HEIC, TIFF, PNG,
> AirPrint URF) at the exact pixel size of each CP-D90 format: EXIF
> orientation, rotation to the paper, Lanczos resize and centre crop, output
> sharpening, ICC conversion (ColorSync float32, CPD90_UF by default) and a
> CUPS raster sent straight to the driver filter. Options are in Portuguese
> (`--ajuda`).

Instalada em `/Library/Printers/CPD90Universal/bin/cpd90-print`, Universal
(arm64 + x86_64), macOS 11 ou superior.

Imprime imagens (JPEG, HEIC, TIFF, PNG, …) com o **tamanho exato** de cada
formato e **sem passar pela paginação nem pela gestão de cor do macOS**:

1. lê os píxeis no espaço de cor da própria imagem, sem conversão, e aplica
   a orientação EXIF;
2. roda a imagem para a orientação do papel, no mesmo sentido do "Girar para
   ajustar" do Lightroom;
3. redimensiona (Lanczos) e corta ao centro (preencher), ou encaixa com
   branco (`--ajustar`). Se a imagem já tiver o tamanho exato, não é
   reamostrada;
4. aplica nitidez de saída (máscara de desfocagem, raio ≈ 1 px a 300 ppp),
   exceto quando não há redimensionamento;
5. converte do perfil da imagem para o perfil da impressora com a ColorSync
   (percetual ou relativa, com compensação de ponto negro), ou não converte
   (`--sem-gestao-cor`);
6. gera uma raster CUPS e envia-a à fila. O CUPS passa-a diretamente ao
   filtro `rastertomitsud90`, sem mais nenhuma etapa.

A geometria dos formatos vem do próprio filtro (`rastertomitsud90 --media`),
que é a única fonte dessa tabela.

## Uso

```bash
B=/Library/Printers/CPD90Universal/bin/cpd90-print
$B foto.jpg                                  # 15x20, Ultra Fine conforme a fila
$B -t 10x15 *.jpg                            # várias fotos numa só tarefa
$B -t 5x15x2_2 tira1.jpg tira2.jpg           # duas tiras 2x6" por folha
$B --ajustar -t 15x20 panorama.jpg           # imagem inteira, com branco
$B --sem-gestao-cor -n nenhuma alvo.tif      # alvo de perfilagem (Fase E)
$B --simular foto.jpg                        # mostra o que faria
$B --raster saida.ras foto.jpg               # grava a raster, não imprime
```

Por omissão:
- imprime em **Ultra Fine** com o perfil **CPD90_UF**, independentemente
  das predefinições da fila. Na impressora real, o perfil ST deu fotos
  avermelhadas. Para outro modo ou perfil: `-o MEPrintMode=…` e `--perfil`;
- envia `MEColorConversion=Disabled`, o fluxo validado na impressora real
  (a conversão é feita aqui com o perfil ICC);
- a fila é a primeira que use o driver CP-D90DW Universal (`-d FILA` para
  escolher outra).

## Folha de calibração (docs/PROTOCOL.md)

```bash
$B --folha-calibracao --acabamento mate --eixos magenta-calor foto.jpg
```

Imprime numa folha 15x20 a mesma foto em 3×3 variantes, cada uma com os
valores na legenda. Linhas = 1.º eixo (+passo / 0 / −passo, de cima para
baixo); colunas = 2.º eixo (−passo / 0 / +passo). O centro é a calibração
atual da fila para esse acabamento (ou `--centro L,M,W`), e o passo é 3 por
omissão (`--passo N`). A folha vai com a calibração do driver desligada, para
não ser aplicada duas vezes. No fim, a ferramenta mostra o comando `lpadmin`
que grava os valores escolhidos na fila.

A folha é composta na orientação da foto tal como o macOS a mostra, com as
legendas alinhadas com ela, e é rodada inteira para o papel. Se a foto
aparecer deitada no Finder, também aparece deitada na folha.

## Orientação das fotos

A orientação EXIF é aplicada pelo ImageIO do macOS (a mesma do Finder, da
Pré-visualização e do Lightroom). Numa impressão normal, uma foto cuja
orientação não coincida com a do papel é rodada 90° no sentido anti-horário,
como no "Girar para ajustar" do Lightroom.

## Verificação (`tools/test_cpd90_print.sh`, em `make test`)

| Teste | Resultado (arm64 e x86_64) |
|---|---|
| Sem gestão de cor, tamanho exato | píxeis byte a byte iguais à imagem |
| Paisagem num formato em retrato | rodada no sentido do Lightroom, preenchida |
| Conversão ICC (CPD90_UF, percetual) vs `sips -m` | média 0,09 níveis, máx 3; 91 % iguais |
| Raster → `rastertomitsud90` | ZT 1852×2428 com os mesmos píxeis |
| 5x15x2_2 com duas imagens | uma folha, 2.ª tira em cima e 1.ª em baixo (docs/PROTOCOL.md) |
| Folha de calibração | as 9 células são a central transformada pelas curvas do filtro |
| Envio ao CUPS (`CPD90_TEST_LP=1`) | tarefa aceite, retida e cancelada |

Nota sobre a conversão: o caminho de 8 bits inteiros da ColorSync quantiza as
tabelas do perfil e afastava-se até 33 níveis do `sips` (média 2,5). A
conversão é feita em vírgula flutuante de 32 bits.
