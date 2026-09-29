#!/usr/bin/env python3
"""Descodifica um fluxo de dados CP-D90 (gravado pelo printer_emulator).

Blocos conhecidos:
  1b 47 44 30  (8 bytes)    ESC G D 0  pedido de estado
  1b 47 44 33  (512 bytes)  ESC G D 3  "enable"/verificação da tarefa
  1b 53 50 30  (512 bytes)  ESC S P 0  cabeçalho da tarefa
  1b 5a 54 xx  (512 bytes)  ESC Z T    cabeçalho do plano de imagem
               + W*H*3 bytes RGB
  1b 42 51 31  (6 bytes)    ESC B Q 1  imprimir / fim de tarefa

Uso: parse_stream.py <fluxo.bin> [...]
"""
import hashlib
import sys


# Pedido do estado da fita (docs/PROTOCOL.md), enviado no início de cada tarefa.
LEVELS_QUERY = bytes.fromhex('1b474430000003 1e162a'.replace(' ', ''))


def strip_levels(data):
    """Fluxo sem os pedidos do estado da fita.
    Só retira blocos reconhecidos pelo parse, nunca bytes dentro das imagens."""
    cuts = [o for k, o, _ in parse(data) if k == 'LVL']
    out, last = bytearray(), 0
    for o in cuts:
        out += data[last:o]
        last = o + len(LEVELS_QUERY)
    return bytes(out + data[last:])


def nz(block, start=4):
    """Bytes não nulos de um bloco de 512 bytes, como {offset: valor}."""
    return {i: block[i] for i in range(start, len(block)) if block[i]}


def parse(data):
    out, i, pending = [], 0, None
    while i < len(data):
        tag = data[i:i + 4]
        if data[i:i + 10] == LEVELS_QUERY:
            out.append(('LVL', i, data[i + 4:i + 10].hex(' ')))
            i += 10
        elif tag == b'\x1bGD0':
            out.append(('GD0', i, data[i + 4:i + 8].hex(' ')))
            i += 8
        elif tag == b'\x1bGD3':
            out.append(('GD3', i, nz(data[i:i + 512])))
            i += 512
        elif tag == b'\x1bSP0':
            out.append(('SP0', i, nz(data[i:i + 512])))
            i += 512
        elif tag[:3] == b'\x1bZT':
            blk = data[i:i + 512]
            w = blk[10] << 8 | blk[11]
            h = blk[12] << 8 | blk[13]
            n = w * h * 3
            img = data[i + 512:i + 512 + n]
            out.append(('ZT', i, {'arg': blk[3], 'fields': nz(blk),
                                  'w': w, 'h': h,
                                  'sha': hashlib.sha256(img).hexdigest()[:16]}))
            i += 512 + n
        elif tag == b'\x1bBQ1':
            out.append(('BQ1', i, data[i + 4:i + 6].hex(' ')))
            i += 6
        else:
            out.append(('???', i, data[i:i + 16].hex(' ')))
            break
    return out


def main():
    for path in sys.argv[1:]:
        data = open(path, 'rb').read()
        print(f'== {path} ({len(data)} bytes)')
        for kind, off, val in parse(data):
            if isinstance(val, dict) and 'fields' not in val:
                val = ' '.join(f'{k:#05x}={v:#04x}' for k, v in val.items())
            print(f'  {off:>9}  {kind}  {val}')


if __name__ == '__main__':
    main()
