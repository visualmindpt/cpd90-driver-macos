#!/usr/bin/env python3
"""Escreve o Payload (cpio odc + gzip) de um componente .pkg a partir de uma
pasta, com dono root:wheel e sem atributos estendidos.

Substitui o pkgbuild porque este transforma o atributo com.apple.provenance
(que não pode ser removido dos ficheiros criados nesta sessão) em ficheiros
AppleDouble ._* dentro do payload.

Uso: write_payload.py <raiz> <Payload> -> imprime "<n.º de ficheiros> <KB>"
"""
import gzip
import os
import stat
import sys


def header(name, mode, size, mtime, ino):
    name_b = name.encode() + b'\0'
    fields = (
        '070707', '%06o' % 0, '%06o' % ino, '%06o' % mode,
        '%06o' % 0, '%06o' % 0,          # uid, gid = root:wheel
        '%06o' % 1, '%06o' % 0, '%011o' % mtime,
        '%06o' % len(name_b), '%011o' % size)
    return ''.join(fields).encode() + name_b


def main():
    root, out = sys.argv[1], sys.argv[2]
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        rel = os.path.relpath(dirpath, root)
        entries.append('.' if rel == '.' else './' + rel)
        for f in sorted(filenames):
            entries.append('./' + os.path.relpath(os.path.join(dirpath, f), root))
    total_kb = 0
    with gzip.open(out, 'wb', compresslevel=9) as z:
        for ino, name in enumerate(entries, 1):
            path = os.path.join(root, name)
            st = os.lstat(path)
            if stat.S_ISDIR(st.st_mode):
                mode, data = stat.S_IFDIR | 0o755, b''
            elif stat.S_ISREG(st.st_mode):
                perm = 0o755 if st.st_mode & 0o111 else 0o644
                mode, data = stat.S_IFREG | perm, open(path, 'rb').read()
            else:
                sys.exit(f'tipo de ficheiro não suportado: {name}')
            total_kb += (len(data) + 1023) // 1024
            z.write(header(name, mode, len(data), int(st.st_mtime), ino))
            z.write(data)
        z.write(header('TRAILER!!!', 0, 0, 0, 0))
    print(len(entries), total_kb)


if __name__ == '__main__':
    main()
