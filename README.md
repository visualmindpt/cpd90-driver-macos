# CP-D90DW Universal — macOS driver for the Mitsubishi CP-D90DW

**[English](#english) · [Português](#português)**

---

## English

A modern, open-source macOS driver for the **Mitsubishi CP-D90DW** dye-sublimation
photo printer. It runs natively on **Apple Silicon and Intel Macs** (Universal
binaries, macOS 11 or later) and does **not** need Rosetta 2.

The official Mitsubishi driver for macOS (v3.00, 2019) ships Intel-only
(x86_64) filters that run through Rosetta 2. Apple has announced that macOS 27
is the last release with full Rosetta 2 support, so the official driver will
stop working. This project keeps the printer usable.

> **Not affiliated with Mitsubishi Electric.** "Mitsubishi" and "CP-D90DW" are
> trademarks of their owners and are used here only to identify the printer
> this driver is compatible with. No Mitsubishi software or data is included.

### Status

Tested on a real CP-D90DW with the **CK-D868 (6×8")** media kit, macOS 26
(Apple Silicon). Validated on paper: 15×20 (6×8"), 10×15 (4×6"), 10×15 ×2,
2×6" ×2 strips, multi-photo jobs, glossy and matte, ribbon levels, and
printing from an iPhone.

Not tested on paper: 5" media (9×13, 13×18, 13×13), 6×9" media (15×21,
15×23), other printer variants (e.g. CP-D90DW-P). Messages are in Portuguese.

### Features

- CUPS driver (PPD + raster filter) with the same options and paper-size names
  as the official driver, so existing presets keep working.
- **Ribbon status** in System Settings: ribbon name and remaining prints, plus
  "almost empty" and "empty" warnings. Sizes that don't fit the loaded ribbon
  are rejected **before** anything is printed.
- **`cpd90-print`**: prints photos at the exact pixel size of each format, with
  ICC colour conversion (ColorSync, 32-bit float) and output sharpening,
  bypassing macOS pagination and colour management.
- **Finder Quick Actions**: right-click photos → *Imprimir na CP-D90 (15×20)*,
  *(10×15)* and *matte* variants.
- **Calibration** per finish (glossy/matte: lightness, magenta, warmth) with a
  printed 3×3 calibration sheet.
- **AirPrint for iPhone/iPad**: the Mac publishes an AirPrint printer (4×6" and
  6×8", borderless, colour) that prints to the CP-D90DW.

### Install

1. Download `CPD90Universal-<version>-public.pkg` and its `.sha256` from
   [Releases](https://github.com/visualmindpt/cpd90-driver-macos/releases).
   The package is not signed with an Apple Developer ID, so install it from
   Terminal:
   ```bash
   shasum -a 256 -c CPD90Universal-*-public.pkg.sha256
   sudo installer -pkg CPD90Universal-*-public.pkg -target /
   ```
2. Add the printer in **System Settings › Printers & Scanners** and choose the
   driver **MITSUBISHI CP-D90D Universal**, or from Terminal:
   ```bash
   sudo lpinfo -v | grep -i mitsubishi    # exact USB address of the printer
   sudo lpadmin -p CPD90 -D "CP-D90" -E -v "usb://MITSUBISHI/CPD90D?location=…" \
     -m Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz \
     -o MEPrintMode-default=UltraFine -o MEColorConversion-default=Disabled
   ```
   To switch existing queues from the Mitsubishi driver, keeping their
   defaults: `sudo /Library/Printers/CPD90Universal/migrar-filas.sh --aplicar`
   (run without `--aplicar` first to see what would change).

### ICC profiles (from Mitsubishi)

The ICC profiles are Mitsubishi's files and are **not** distributed here. Get
them from Mitsubishi Electric's official website, in the downloads / support
section for dye-sublimation photo printers:

- search for **"Mitsubishi Electric CP-D90DW ICC profile"** (or "CP-D90DW
  download");
- the files you need are **`CPD90_UF.icc`** (Ultra Fine) and
  **`CPD90_ST.icc`** (Standard / Fine), usually in a folder or `.zip` named
  like *"CPD90 ICC Profile"*;
- Mitsubishi also publishes a guide called *"CP-D90DW(-P) instructions to use
  ICC profile"*, which you can find with the same search.

Then install them (folder or `.zip`):
```bash
sudo /Library/Printers/CPD90Universal/instalar-perfis.sh ~/Downloads/<download>
```

**Recommended colour workflow** (validated on real prints): let the
application manage colours with profile **CPD90_UF**, print mode **Ultra
Fine**, and **printer colour conversion off**. With colour conversion on, the
two conversions add up and prints get worse.

### Usage

- **Lightroom Classic:** see [docs/LIGHTROOM.md](docs/LIGHTROOM.md). Use the
  CP-D90's own 15x20 paper size and turn off "scale to fit paper", otherwise
  macOS enlarges the image by ~3% and adds thin white margins.
- **Quick Actions:** select photos in Finder → right-click → Quick Actions.
- **Command line:** `/Library/Printers/CPD90Universal/bin/cpd90-print --ajuda`
  (see [docs/CPD90-PRINT.md](docs/CPD90-PRINT.md)).
  ```bash
  cpd90-print photo.jpg                 # 15x20, Ultra Fine, CPD90_UF
  cpd90-print -t 10x15 *.jpg            # several photos, one job
  cpd90-print --folha-calibracao --acabamento mate photo.jpg
  ```
- **iPhone/iPad:** requires `brew install cups` (CUPS 2.4, installed alongside
  macOS's CUPS; the `ippeveprinter` shipped with macOS rejects iOS jobs). Then:
  ```bash
  /Library/Printers/CPD90Universal/airprint/airprint.sh ativar "CP-D90 (iPhone)"
  ```
  The Mac must be awake and on the same Wi-Fi network. See
  [docs/IPHONE.md](docs/IPHONE.md).

### Uninstall

```bash
sudo /Library/Printers/CPD90Universal/desinstalar.sh
```

### Building from source

Requires the Xcode Command Line Tools.
```bash
make            # filters, cpd90-print, PPD (Universal, ad-hoc signed)
make pkg-public # dist/CPD90Universal-<version>-public.pkg
make test       # tests with a built-in printer emulator (no printer needed)
```
Data stream and driver behaviour: [docs/PROTOCOL.md](docs/PROTOCOL.md).

### Credits and acknowledgements

- **selphy_print / Gutenprint** — Solomon Peachy and contributors, for the
  public documentation of the Mitsubishi CP-D90 protocol, on which this
  driver is based, and the ribbon (media) type table used here. <https://git.shaftnet.org/gitea/slp/selphy_print>,
  <https://gimp-print.sourceforge.io>
- **CUPS / OpenPrinting** — the printing system, the raster format and
  `ippeveprinter`, which makes AirPrint possible. <https://openprinting.github.io/cups/>
- **Homebrew** — for the CUPS 2.4 package. <https://brew.sh>
- **Apple** — ColorSync, ImageIO and the macOS printing system.
- **Mitsubishi Electric** — for the CP-D90DW printer and its ICC profiles.
- Developed by Nelson Silva ([VisualMind](https://github.com/visualmindpt)).

See [NOTICE](NOTICE) for details.

### Legal

- License: **GNU GPL v3.0 or later** ([LICENSE](LICENSE)). Provided **as is,
  without warranty**; community support on a best-effort basis.
- Independent implementation of the printer protocol documented publicly by
  the selphy_print / Gutenprint project.
- No Mitsubishi software, ICC profiles, icons or other files are distributed
  in this repository or in its packages.

---

## Português

Um driver moderno e open source para macOS para a impressora fotográfica de
sublimação **Mitsubishi CP-D90DW**. Corre nativamente em **Macs Apple Silicon e
Intel** (binários Universal, macOS 11 ou superior) e **não** precisa do
Rosetta 2.

O driver oficial da Mitsubishi para macOS (v3.00, 2019) só tem filtros Intel
(x86_64), que correm através do Rosetta 2. A Apple anunciou que o macOS 27 é a
última versão com suporte completo ao Rosetta 2, por isso o driver oficial vai
deixar de funcionar. Este projeto mantém a impressora utilizável.

> **Sem qualquer ligação à Mitsubishi Electric.** "Mitsubishi" e "CP-D90DW" são
> marcas dos respetivos titulares e são usadas aqui apenas para identificar a
> impressora com que este driver é compatível. Não inclui software nem dados
> da Mitsubishi.

### Estado

Testado numa CP-D90DW real com o kit **CK-D868 (15×20)**, macOS 26 (Apple
Silicon). Validado em papel: 15×20, 10×15, 10×15 ×2, tiras 2×6" ×2, tarefas
com várias fotos, brilhante e mate, níveis da fita e impressão a partir do
iPhone.

Não testado em papel: papel de 5" (9×13, 13×18, 13×13), papel de 6×9"
(15×21, 15×23) e outras variantes da impressora (por exemplo, CP-D90DW-P). As
mensagens estão em português.

### Funcionalidades

- Driver CUPS (PPD + filtro raster) com as mesmas opções e nomes de tamanhos do
  driver oficial, para os presets existentes continuarem a funcionar.
- **Estado da fita** nas Definições do Sistema: nome da fita e impressões
  restantes, com avisos de fita a acabar e esgotada. Os formatos que não cabem
  na fita instalada são recusados **antes** de imprimir.
- **`cpd90-print`**: imprime fotos com o tamanho exato de cada formato, com
  conversão ICC (ColorSync, vírgula flutuante de 32 bits) e nitidez de saída,
  sem a paginação nem a gestão de cor do macOS.
- **Ações Rápidas do Finder**: botão direito nas fotos → *Imprimir na CP-D90
  (15×20)*, *(10×15)* e as versões *mate*.
- **Calibração** por acabamento (brilhante/mate: luminosidade, magenta, calor)
  com uma folha de calibração 3×3 impressa.
- **AirPrint para iPhone/iPad**: o Mac publica uma impressora AirPrint (4×6" e
  6×8", sem margens, a cores) que imprime na CP-D90DW.

### Instalar

1. Descarregue o `CPD90Universal-<versão>-public.pkg` e o `.sha256` das
   [Releases](https://github.com/visualmindpt/cpd90-driver-macos/releases).
   O pacote não tem assinatura de programador da Apple, por isso instale-o
   pelo Terminal:
   ```bash
   shasum -a 256 -c CPD90Universal-*-public.pkg.sha256
   sudo installer -pkg CPD90Universal-*-public.pkg -target /
   ```
2. Adicione a impressora em **Definições do Sistema › Impressoras e scanners**
   com o driver **MITSUBISHI CP-D90D Universal**, ou no Terminal:
   ```bash
   sudo lpinfo -v | grep -i mitsubishi    # endereço USB exato da impressora
   sudo lpadmin -p CPD90 -D "CP-D90" -E -v "usb://MITSUBISHI/CPD90D?location=…" \
     -m Library/Printers/PPDs/Contents/Resources/CPD90Universal.ppd.gz \
     -o MEPrintMode-default=UltraFine -o MEColorConversion-default=Disabled
   ```
   Para passar filas existentes do driver da Mitsubishi para este, mantendo as
   predefinições: `sudo /Library/Printers/CPD90Universal/migrar-filas.sh --aplicar`
   (corra primeiro sem `--aplicar` para ver o que muda).

### Perfis ICC (da Mitsubishi)

Os perfis ICC são ficheiros da Mitsubishi e **não** são distribuídos aqui.
Obtenha-os no site oficial da Mitsubishi Electric, na secção de downloads /
suporte das impressoras fotográficas de sublimação:

- pesquise **"Mitsubishi Electric CP-D90DW ICC profile"** (ou "CP-D90DW
  download");
- os ficheiros necessários são **`CPD90_UF.icc`** (Ultra Fine) e
  **`CPD90_ST.icc`** (Standard / Fine), normalmente numa pasta ou `.zip` com
  um nome como *"CPD90 ICC Profile"*;
- a Mitsubishi publica também um guia chamado *"CP-D90DW(-P) instructions to
  use ICC profile"*, que se encontra com a mesma pesquisa.

Depois instale-os (pasta ou `.zip`):
```bash
sudo /Library/Printers/CPD90Universal/instalar-perfis.sh ~/Downloads/<download>
```

**Fluxo de cor recomendado** (validado em impressões reais): a aplicação gere
as cores com o perfil **CPD90_UF**, modo de impressão **Ultra Fine** e
**conversão de cor na impressora desligada**. Com a conversão ligada, as duas
conversões somam-se e as fotos saem piores.

### Utilização

- **Lightroom Classic:** ver [docs/LIGHTROOM.md](docs/LIGHTROOM.md). Use o
  papel 15x20 da própria CP-D90 e desligue "Ajustar proporcionalmente ao
  papel"; caso contrário o macOS amplia a imagem ~3% e deixa margens brancas.
- **Ações Rápidas:** selecione fotos no Finder → botão direito → Ações Rápidas.
- **Linha de comandos:** `/Library/Printers/CPD90Universal/bin/cpd90-print --ajuda`
  (ver [docs/CPD90-PRINT.md](docs/CPD90-PRINT.md)).
- **iPhone/iPad:** requer `brew install cups` (CUPS 2.4, instalado à parte do
  CUPS do macOS; o `ippeveprinter` do macOS recusa os trabalhos do iOS).
  Depois:
  ```bash
  /Library/Printers/CPD90Universal/airprint/airprint.sh ativar "CP-D90 (iPhone)"
  ```
  O Mac tem de estar acordado e na mesma rede Wi-Fi. Ver
  [docs/IPHONE.md](docs/IPHONE.md).

### Desinstalar

```bash
sudo /Library/Printers/CPD90Universal/desinstalar.sh
```

### Compilar

Requer as Xcode Command Line Tools: `make`, `make pkg-public`, `make test`
(ver a secção em inglês). O fluxo de dados e o comportamento do driver estão
em [docs/PROTOCOL.md](docs/PROTOCOL.md).

### Créditos e agradecimentos

- **selphy_print / Gutenprint** — Solomon Peachy e contribuidores, pela
  documentação pública do protocolo da Mitsubishi CP-D90, na qual este driver
  se baseia, e pela tabela de tipos de fita usada aqui.
- **CUPS / OpenPrinting** — o sistema de impressão, o formato raster e o
  `ippeveprinter`, que torna o AirPrint possível.
- **Homebrew** — pelo pacote do CUPS 2.4.
- **Apple** — ColorSync, ImageIO e o sistema de impressão do macOS.
- **Mitsubishi Electric** — pela impressora CP-D90DW e pelos seus perfis ICC.
- Desenvolvido por Nelson Silva ([VisualMind](https://github.com/visualmindpt)).

Ver [NOTICE](NOTICE).

### Aspetos legais

- Licença: **GNU GPL v3.0 ou posterior** ([LICENSE](LICENSE)). Fornecido **tal
  como está, sem garantia**; suporte comunitário conforme a disponibilidade.
- Implementação independente do protocolo da impressora documentado
  publicamente pelo projeto selphy_print / Gutenprint.
- Não é distribuído software, perfis ICC, ícones nem outros ficheiros da
  Mitsubishi, nem neste repositório nem nos pacotes.
