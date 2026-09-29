#!/usr/bin/env python3
"""Gera ppd/CPD90Universal.ppd.

As palavras-chave das opções, as escolhas e os tamanhos são compatíveis com
as filas CP-D90 existentes, para que os presets continuem a funcionar. Os textos (inglês e português) e a tabela de razões de erro
foram escritos para este projeto.

Uso: gen_ppd.py [saida.ppd]
"""
import os
import re
import sys
import urllib.parse

# Versão: definida só em src/mitsud90_common.h.
VERSION = re.search(r'#define DRIVER_VERSION "([^"]+)"',
                    open(os.path.join(os.path.dirname(__file__), '..', 'src',
                                      'mitsud90_common.h')).read()).group(1)
import os
# CPD90_PPD_PREFIX permite gerar um PPD de teste apontado para build/.
PREFIX = os.environ.get('CPD90_PPD_PREFIX', '/Library/Printers/CPD90Universal')
FILTER = os.environ.get('CPD90_PPD_FILTER', f'{PREFIX}/filter/rastertomitsud90')
CMDFILTER = os.environ.get('CPD90_PPD_CMDFILTER', f'{PREFIX}/filter/commandtomitsud90')
ICC_ST = f'{PREFIX}/Profiles/CPD90_ST.icc'
ICC_UF = f'{PREFIX}/Profiles/CPD90_UF.icc'
ICON = f'{PREFIX}/Icons/CPD90.icns'

# (keyword, en, pt, largura pt, altura pt) — dimensões PostScript de cada formato
PAGE_SIZES = [
    ('ME_9x13', '9x13 (3.5x5")', '9x13 cm (3,5x5")', 372, 259),
    ('ME_10x15', '10x15 (4x6")', '10x15 cm (4x6")', 445, 295),
    ('ME_13x18', '13x18 (5x7")', '13x18 cm (5x7")', 372, 511),
    ('ME_15x20', '15x20 (6x8")', '15x20 cm (6x8")', 445, 583),
    ('ME_15x21', '15x21 (6x8.5")', '15x21 cm (6x8,5")', 445, 617),
    ('ME_15x23', '15x23 (6x9")', '15x23 cm (6x9")', 445, 655),
    ('ME_10x15x2', '10x15 x2 (4x6" x2)', '10x15 cm x2 (4x6" x2)', 445, 598),
    ('ME_5x15x2_1', '5x15 x2 Type 1 (2x6" x2, one page)',
     '5x15 cm x2 Tipo 1 (2x6" x2, uma página)', 445, 295),
    ('ME_5x15x2_2', '5x15 x2 Type 2 (2x6" x2, two pages)',
     '5x15 cm x2 Tipo 2 (2x6" x2, duas páginas)', 445, 148),
    ('ME_5x15', '5x15 (2x6")', '5x15 cm (2x6")', 445, 150),
    ('ME_15x15', '15x15 (6x6")', '15x15 cm (6x6")', 445, 439),
    ('ME_13x13', '13x13 (5x5")', '13x13 cm (5x5")', 372, 367),
    ('ME_9x13_WB', '9x13 (3.5x5") white border', '9x13 cm (3,5x5") margem branca', 332, 225),
    ('ME_10x15_WB', '10x15 (4x6") white border', '10x15 cm (4x6") margem branca', 405, 261),
    ('ME_13x18_WB', '13x18 (5x7") white border', '13x18 cm (5x7") margem branca', 332, 477),
    ('ME_15x20_WB', '15x20 (6x8") white border', '15x20 cm (6x8") margem branca', 405, 549),
    ('ME_15x23_WB', '15x23 (6x9") white border', '15x23 cm (6x9") margem branca', 405, 621),
]

SHARP = [('None', 'Off', 'Desligada'), ('Minus3', '-3 Soft', '-3 Suave'),
         ('Minus2', '-2', '-2'), ('Minus1', '-1', '-1'),
         ('Normal', '0 Normal', '0 Normal'), ('Plus1', '+1', '+1'),
         ('Plus2', '+2', '+2'), ('Plus3', '+3 Hard', '+3 Forte')]
LEVELS = [-64, -60, -56, -52, -48, -44, -40, -36, -32, -30, -28, -26, -24,
          -22, -20, -18, -16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6,
          -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
          14, 15, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 44, 48, 52, 56,
          60, 64]

# (grupo, [(opção, en, pt, tipo, predefinição, [(escolha, en, pt)])])
GROUPS = [
    ('Options', 'Printer Options', 'Opções da impressora', [
        ('MEPrintMode', 'Print Mode', 'Modo de impressão', 'PickOne', 'Auto',
         [('Fine', 'Fine', 'Fine'), ('Auto', 'Auto', 'Automático'),
          ('UltraFine', 'Ultra Fine', 'Ultra Fine')]),
        ('MEPrintFinish', 'Finish', 'Acabamento', 'PickOne', 'Gloss',
         [('Gloss', 'Glossy', 'Brilhante'), ('Matte', 'Matte', 'Mate')]),
        ('MESharpness_Common', 'Sharpness', 'Nitidez', 'PickOne', 'Normal', SHARP),
        ('MEColorConversion', 'Printer color conversion',
         'Conversão de cor na impressora', 'PickOne', 'Enabled',
         [('Enabled', 'On', 'Ligada'), ('Disabled', 'Off', 'Desligada')]),
        ('MEMarginCutOff', 'Trim white margins', 'Cortar margens brancas',
         'Boolean', 'False', [('False', 'No', 'Não'), ('True', 'Yes', 'Sim')]),
    ]),
    ('SharpnessDetail', 'Sharpness Details', 'Nitidez detalhada', [
        ('MESharpnessDetail', 'Separate horizontal/vertical sharpness',
         'Nitidez horizontal/vertical separada', 'Boolean', 'False',
         [('False', 'No', 'Não'), ('True', 'Yes', 'Sim')]),
        ('MESharpness_H', 'Horizontal sharpness', 'Nitidez horizontal',
         'PickOne', 'Normal', SHARP),
        ('MESharpness_V', 'Vertical sharpness', 'Nitidez vertical',
         'PickOne', 'Normal', SHARP),
    ]),
    ('WaitSetting', 'Wait Time', 'Tempo de espera', [
        ('MEWaitingNextImage', 'Wait for next image', 'Esperar pela imagem seguinte',
         'Boolean', 'True', [('False', 'No', 'Não'), ('True', 'Yes', 'Sim')]),
        ('MEWaitTime', 'Wait time', 'Tempo de espera', 'PickOne', '5',
         [(str(i), f'{i} s', f'{i} s') for i in range(1, 101)]),
    ]),
    ('Gamma', 'Gamma', 'Gama', [
        (f'MEGamma{c}', f'Gamma {c}', f'Gama {c}', 'PickOne', '0',
         [(str(i), f'{i:+d}' if i else '0', f'{i:+d}' if i else '0')
          for i in range(-5, 6)]) for c in 'RGB']),
    ('Brightness', 'Brightness', 'Brilho', [
        (f'MEBrightness{c}', f'Brightness {c}', f'Brilho {c}', 'PickOne', '0',
         [(str(i), f'{i:+d}' if i else '0', f'{i:+d}' if i else '0')
          for i in LEVELS]) for c in 'RGB']),
    ('Contrast', 'Contrast', 'Contraste', [
        (f'MEContrast{c}', f'Contrast {c}', f'Contraste {c}', 'PickOne', '0',
         [(str(i), f'{i:+d}' if i else '0', f'{i:+d}' if i else '0')
          for i in LEVELS]) for c in 'RGB']),
    ('Calibration', 'Calibration', 'Calibração', [
        (f'MECal{fin}{ax}', f'{fen} - {aen}', f'{fpt} - {apt}', 'PickOne', '0',
         [(str(i), f'{i:+d}' if i else '0', f'{i:+d}' if i else '0') for i in range(-10, 11)])
        for fin, fen, fpt in (('Gloss', 'Glossy', 'Brilhante'), ('Matte', 'Matte', 'Mate'))
        for ax, aen, apt in (('L', 'lightness (+ lighter)', 'luminosidade (+ mais clara)'),
                             ('M', 'magenta (+ less magenta)', 'magenta (+ menos magenta)'),
                             ('W', 'warmth (+ warmer)', 'calor (+ mais quente)'))]),
]

# Razões de erro: grupo -> (códigos da impressora, en, pt).
# Os códigos vêm da tabela de estados da impressora (docs/PROTOCOL.md); os textos são
# deste projeto.
TURN_OFF_EN = 'Turn the printer off and on again.'
TURN_OFF_PT = 'Desligue e volte a ligar a impressora.'
RELOAD_EN = 'Check the ink ribbon and reload the paper.'
RELOAD_PT = 'Verifique a fita e volte a colocar o papel.'
REASONS = [
    ('0001', [], 'The printer is not connected.', 'A impressora não está ligada.'),
    ('0002', [], 'Data transfer error.', 'Erro na transferência de dados.'),
    ('0003', [], f'The printer is not responding. {TURN_OFF_EN}',
     f'A impressora não responde. {TURN_OFF_PT}'),
    ('0004', [], f'Printer error. {TURN_OFF_EN}', f'Erro na impressora. {TURN_OFF_PT}'),
    ('0005', [], 'The selected paper size does not match the loaded ink ribbon.',
     'O tamanho de papel escolhido não corresponde à fita instalada.'),
    ('0006', ['2190'], 'Ink ribbon empty ({c}).', 'Fita esgotada ({c}).'),
    ('0007', ['2100', '2110', '2120', '2130'], 'Ink ribbon end ({c}).',
     'Fim da fita ({c}).'),
    ('0008', ['2600', '2601', '2602', '2610', '2611', '2620', '2621', '2622',
              '2623', '2624', '2625', '2626'] +
     [str(c) for c in range(2660, 2691)],
     'Ink ribbon error ({c}). Check the ink ribbon.',
     'Erro na fita ({c}). Verifique a fita.'),
    ('0009', ['3290', '3390', '3490', '3690', '3190', '3590', '3790'],
     f'Ink ribbon error ({{c}}). {RELOAD_EN}', f'Erro na fita ({{c}}). {RELOAD_PT}'),
    ('0010', ['2800', '2810'], 'Paper strip bin not installed ({c}).',
     'Caixa de recortes não instalada ({c}).'),
    ('0011', ['2200'], 'Out of paper ({c}).', 'Sem papel ({c}).'),
    ('0012', ['2900', '2910'], 'The printing unit is open ({c}).',
     'A unidade de impressão está aberta ({c}).'),
    ('0013', ['2FFF'], 'The printer was switched off while printing ({c}).',
     'A impressora foi desligada durante a impressão ({c}).'),
    ('0014', ['2300', '2390'], 'Ink ribbon and paper do not match ({c}).',
     'A fita e o papel não correspondem ({c}).'),
    ('0015', ['2202'], 'Paper end ({c}).', 'Fim do papel ({c}).'),
    ('0016', ['4291', '4293', '4493', '4491', '4492', '4391', '4393', '4191', '4091'],
     f'Paper jam ({{c}}). {RELOAD_EN}', f'Papel encravado ({{c}}). {RELOAD_PT}'),
    ('0017', ['7194', '7192', '7092', '7392'],
     f'Mechanical error ({{c}}). {RELOAD_EN}', f'Erro mecânico ({{c}}). {RELOAD_PT}'),
    ('0018', ['7054', '7452', '7552'],
     f'Mechanical error ({{c}}). {TURN_OFF_EN}', f'Erro mecânico ({{c}}). {TURN_OFF_PT}'),
    ('0019', ['6800'], f'Fan error ({{c}}). {TURN_OFF_EN}',
     f'Erro na ventoinha ({{c}}). {TURN_OFF_PT}'),
    ('0020', ['6000', '6001', '6002', '6003', '6005', '6006', '6007', '6008',
              '6009', '6010', '6011', '6012', '6013', '6014', '6015', '6016',
              '6017', '6018', '6019'],
     f'Temperature sensor error ({{c}}). {TURN_OFF_EN}',
     f'Erro no sensor de temperatura ({{c}}). {TURN_OFF_PT}'),
    ('0021', ['6100'], f'Color sensor error ({{c}}). {TURN_OFF_EN}',
     f'Erro no sensor de cor ({{c}}). {TURN_OFF_PT}'),
    ('0022', ['6110', '6111'], f'Matte unit error ({{c}}). {TURN_OFF_EN}',
     f'Erro na unidade de acabamento mate ({{c}}). {TURN_OFF_PT}'),
    ('0023', ['6004'], f'Humidity sensor error ({{c}}). {TURN_OFF_EN}',
     f'Erro no sensor de humidade ({{c}}). {TURN_OFF_PT}'),
    ('0024', ['6300', '6310', '6320'], f'Memory error ({{c}}). {TURN_OFF_EN}',
     f'Erro de memória ({{c}}). {TURN_OFF_PT}'),
    ('0025', ['6400'], f'Flash memory error ({{c}}). {TURN_OFF_EN}',
     f'Erro na memória flash ({{c}}). {TURN_OFF_PT}'),
    ('0026', ['6890'], f'Internal error ({{c}}). {TURN_OFF_EN}',
     f'Erro interno ({{c}}). {TURN_OFF_PT}'),
    ('0027', ['6540', '6600', '6610', '6620'], f'Power supply error ({{c}}). {TURN_OFF_EN}',
     f'Erro na alimentação ({{c}}). {TURN_OFF_PT}'),
    ('0028', ['6020'], f'Preheat error ({{c}}). {TURN_OFF_EN}',
     f'Erro de pré-aquecimento ({{c}}). {TURN_OFF_PT}'),
    ('0029', ['6200', '6210', '6220'], f'Internal data transfer error ({{c}}). {TURN_OFF_EN}',
     f'Erro interno de transferência ({{c}}). {TURN_OFF_PT}'),
    ('0030', ['6910'], f'Memory error ({{c}}). {TURN_OFF_EN}',
     f'Erro de memória ({{c}}). {TURN_OFF_PT}'),
    ('0031', ['6500', '6510', '6520', '6530'], f'Internal error ({{c}}). {TURN_OFF_EN}',
     f'Erro interno ({{c}}). {TURN_OFF_PT}'),
    ('0032', [], 'The print settings are not valid for this printer.',
     'As definições de impressão não são válidas para esta impressora.'),
    ('0033', [], 'The image size is out of range.', 'O tamanho da imagem está fora dos limites.'),
    ('0034', ['6700', '6900'], f'Printer error ({{c}}). {TURN_OFF_EN}',
     f'Erro na impressora ({{c}}). {TURN_OFF_PT}'),
    ('0035', ['2990'], f'The printing unit was opened while printing ({{c}}). {RELOAD_EN}',
     f'A unidade de impressão foi aberta durante a impressão ({{c}}). {RELOAD_PT}'),
]


def reasons():
    for group, codes, en, pt in REASONS:
        for code in codes or [None]:
            key = f'com.mitsubishi-error{group}' + (f'_{code}' if code else '')
            yield key, en.format(c=code), pt.format(c=code)


def ppd():
    L = []
    a = L.append
    a('*PPD-Adobe: "4.3"')
    a('*%')
    a('*% CP-D90DW Universal — driver independente para a Mitsubishi CP-D90DW.')
    a('*% Não é um produto da Mitsubishi Electric. GPL-3.0-or-later.')
    a('*%')
    a('*FormatVersion: "4.3"')
    a(f'*FileVersion: "{VERSION}"')
    a('*LanguageVersion: English')
    a('*LanguageEncoding: ISOLatin1')
    a('*PCFileName: "CPD90UNI.PPD"')
    a('*Manufacturer: "MITSUBISHI"')
    a('*Product: "(MITSUBISHI CPD90D)"')
    a('*ModelName: "MITSUBISHI CP-D90D"')
    a('*ShortNickName: "MITSUBISHI CP-D90D Universal"')
    a(f'*NickName: "MITSUBISHI CP-D90D Universal {VERSION}"')
    a('*1284DeviceID: "MFG:MITSUBISHI;MDL:CPD90D;"')
    a('*PSVersion: "(3010.000) 0"')
    a('*LanguageLevel: "3"')
    a('*ColorDevice: True')
    a('*DefaultColorSpace: RGB')
    a('*FileSystem: False')
    a('*Throughput: "1"')
    a('*LandscapeOrientation: Minus90')
    a('*TTRasterizer: Type42')
    a('*cupsVersion: 2.2')
    a('*cupsManualCopies: True')
    a('*cupsModelNumber: 0')
    a('*cupsLanguages: "pt_PT pt"')
    a(f'*cupsFilter: "application/vnd.cups-raster 0 {FILTER}"')
    a(f'*cupsFilter: "application/vnd.cups-command 0 {CMDFILTER}"')
    a('*cupsCommands: "ReportLevels ReportStatus"')
    a(f'*APPrinterIconPath: "{ICON}"')
    a('')
    a('*% Perfis ICC: ST para Auto/Fine, UF para Ultra Fine.')
    a('*cupsICCQualifier2: MEPrintMode')
    for mode, path, desc in (('Auto', ICC_ST, 'CP-D90 Standard'),
                             ('Fine', ICC_ST, 'CP-D90 Standard'),
                             ('UltraFine', ICC_UF, 'CP-D90 Ultra Fine')):
        a(f'*cupsICCProfile RGB.{mode}.300dpi/{desc}: "{path}"')
    a('')

    def sizes(kw):
        a(f'*OpenUI *{kw}: PickOne')
        a(f'*OrderDependency: 10 AnySetup *{kw}')
        a(f'*Default{kw}: ME_9x13')
        for k, en, _, w, h in PAGE_SIZES:
            a(f'*{kw} {k}/{en}: "<</PageSize[{w} {h}]/ImagingBBox null>>setpagedevice"')
        a(f'*CloseUI: *{kw}')
    sizes('PageSize')
    sizes('PageRegion')
    a('*DefaultImageableArea: ME_9x13')
    for k, en, _, w, h in PAGE_SIZES:
        a(f'*ImageableArea {k}/{en}: "0 0 {w} {h}"')
    a('*DefaultPaperDimension: ME_9x13')
    for k, en, _, w, h in PAGE_SIZES:
        a(f'*PaperDimension {k}/{en}: "{w} {h}"')
    a('')
    a('*OpenUI *Resolution/Resolution: PickOne')
    a('*OrderDependency: 20 AnySetup *Resolution')
    a('*DefaultResolution: 300dpi')
    a('*Resolution 300dpi/300 dpi: "<</HWResolution[300 300]>>setpagedevice"')
    a('*CloseUI: *Resolution')
    a('*OpenUI *ColorModel/Color Mode: PickOne')
    a('*OrderDependency: 10 AnySetup *ColorModel')
    a('*DefaultColorModel: RGB')
    a('*ColorModel RGB/RGB Color: "<</cupsColorOrder 0/cupsColorSpace 1/cupsBitsPerColor 8>>setpagedevice"')
    a('*CloseUI: *ColorModel')
    order = 30
    for gk, gen, _, opts in GROUPS:
        a('')
        a(f'*OpenGroup: {gk}/{gen}')
        for ok, oen, _, typ, default, choices in opts:
            a(f'*OpenUI *{ok}/{oen}: {typ}')
            a(f'*OrderDependency: {order} AnySetup *{ok}')
            order += 1
            a(f'*Default{ok}: {default}')
            for ck, cen, _ in choices:
                a(f'*{ok} {ck}/{cen}: ""')
            a(f'*CloseUI: *{ok}')
        a(f'*CloseGroup: {gk}')
    a('')
    for key, en, _ in reasons():
        a(f'*cupsIPPReason {key}/{key[14:]}: "text:{urllib.parse.quote(en)}"')

    # Tradução portuguesa (CUPS: *<lang>.Translation / *<lang>.<Opção>).
    a('')
    a('*% ---- Português')
    for lang in ('pt_PT', 'pt'):
        a(f'*{lang}.Translation PageSize/Tamanho do papel: ""')
        a(f'*{lang}.Translation PageRegion/Tamanho do papel: ""')
        for k, _, pt, _, _ in PAGE_SIZES:
            a(f'*{lang}.PageSize {k}/{pt}: ""')
            a(f'*{lang}.PageRegion {k}/{pt}: ""')
        a(f'*{lang}.Translation Resolution/Resolução: ""')
        a(f'*{lang}.Resolution 300dpi/300 ppp: ""')
        a(f'*{lang}.Translation ColorModel/Modo de cor: ""')
        a(f'*{lang}.ColorModel RGB/Cor RGB: ""')
        for gk, _, gpt, opts in GROUPS:
            a(f'*{lang}.Translation {gk}/{gpt}: ""')
            for ok, _, opt, _, _, choices in opts:
                a(f'*{lang}.Translation {ok}/{opt}: ""')
                for ck, _, cpt in choices:
                    a(f'*{lang}.{ok} {ck}/{cpt}: ""')
        for key, _, pt in reasons():
            a(f'*{lang}.cupsIPPReason {key}/{key[14:]}: "text:{urllib.parse.quote(pt)}"')
    a('')
    a('*DefaultFont: Courier')
    a('*% Fim do ficheiro')
    return '\n'.join(L) + '\n'


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'ppd/CPD90Universal.ppd'
    # PPD 4.3 exige ISO-8859-1 no texto base; as traduções são UTF-8 (CUPS).
    open(out, 'wb').write(ppd().encode('utf-8'))
    print(f'{out}: {sum(1 for _ in reasons())} razões, '
          f'{len(PAGE_SIZES)} tamanhos')
