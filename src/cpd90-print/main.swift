// cpd90-print — imprime imagens na CP-D90DW com o tamanho exato do formato,
// sem passar pela paginação nem pela gestão de cor do macOS.
//
// Pipeline por imagem:
//   ImageIO (píxeis no espaço de cor da própria imagem, sem conversão)
//   -> orientação EXIF -> rodar para a orientação do papel
//   -> redimensionar (Lanczos, vImage) e cortar ao centro ("preencher")
//      ou encaixar com branco ("ajustar")
//   -> nitidez de saída (máscara de desfocagem)
//   -> conversão ICC (ColorSync: perfil da imagem -> perfil da impressora,
//      intenção + compensação de ponto negro), ou nenhuma (--sem-gestao-cor)
//   -> CUPS raster (RGB 8 bits, 300 ppp) -> lp -> filtro rastertomitsud90
//
// A geometria de cada formato vem do próprio filtro (`rastertomitsud90
// --media`), que é a única fonte dessa tabela.
//
// Copyright (C) 2026 Nelson Silva. Licença: GPL-3.0-or-later.

import Accelerate
import ColorSync
import CoreGraphics
import CoreText
import Foundation
import ImageIO

// `version` vem de build/Version.swift, gerado pelo Makefile a partir de
// src/mitsud90_common.h (única definição da versão).
let installDir = "/Library/Printers/CPD90Universal"

// MARK: - Erros e mensagens

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func info(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// MARK: - Opções

struct Options {
    var files: [String] = []
    var size = "ME_15x20"
    var fit = "preencher"            // preencher | ajustar
    var rotate = true
    var sharpen = "normal"           // nenhuma | suave | normal | forte
    var colorManagement = true
    var profile: String?             // nil = automático pelo modo de impressão
    var intent = "percetual"         // percetual | relativa
    var queue: String?
    var output: String?              // grava a raster em vez de imprimir
    var copies = 1
    var cupsOptions: [String] = []   // -o K=V para o PPD
    var dryRun = false
    var hold = false                 // deixar a tarefa retida no CUPS (testes)
    var airprint = false             // trabalho recebido do iPhone (ippeveprinter)
    var sizeGiven = false
    // Folha de calibração (docs/PROTOCOL.md)
    var calSheet = false
    var finish = "brilhante"         // brilhante | mate
    var axes = "luz-magenta"         // luz-magenta | luz-calor | magenta-calor
    var center: [Int]?               // L,M,W; omissão: predefinições da fila
    var step = 3
}

let usage = """
cpd90-print \(version) — imprimir na Mitsubishi CP-D90DW com o tamanho exato

Uso: cpd90-print [opções] imagem [imagem ...]

  -t, --tamanho FORMATO   15x20 (omissão), 10x15, 13x18, 15x15, 15x23, 5x15,
                          10x15x2, ... ou o nome do PPD (ME_15x20)
      --ajustar           encaixar a imagem inteira com branco (omissão: preencher e cortar)
      --sem-rodar         não rodar a imagem para a orientação do papel
  -n, --nitidez NÍVEL     nenhuma | suave | normal (omissão) | forte
  -p, --perfil FICHEIRO   perfil ICC da impressora (omissão: CPD90_UF)
  -i, --intencao I        percetual (omissão) | relativa  (sempre com compensação de ponto negro)
      --sem-gestao-cor    enviar os píxeis sem conversão de cor (alvos de perfilagem)
  -d, --fila FILA         fila CUPS (omissão: a primeira com o driver CP-D90DW Universal)
  -c, --copias N          número de cópias
  -o OPÇÃO=VALOR          opção do driver (ex.: -o MEPrintMode=Fine); pode repetir
      --raster FICHEIRO   gravar a raster CUPS em vez de imprimir
      --simular           mostrar o que seria feito, sem imprimir
      --reter             enviar a tarefa retida (não imprime até ser libertada)
      --airprint          trabalho do iPhone (URF): o formato é escolhido pelo
                          tamanho da página (6×8" → 15x20, 4×6" → 10x15)

Folha de calibração (3×3 variantes de uma foto numa folha 15x20):
      --folha-calibracao  imprimir a folha em vez da foto
      --acabamento A      brilhante (omissão) | mate
      --eixos E           luz-magenta (omissão) | luz-calor | magenta-calor
      --centro L,M,W      valores ao centro (omissão: a calibração atual da fila)
      --passo N           diferença entre variantes (omissão 3; 1 passo ≈ 2,5 níveis)
  -h, --ajuda

Por omissão imprime em Ultra Fine com o perfil CPD90_UF e envia
MEColorConversion=Disabled (fluxo validado: a conversão é feita aqui com o
perfil ICC). Estas predefinições não dependem das da fila.
"""

func parseArgs() throws -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next(_ flag: String) throws -> String {
        guard !args.isEmpty else { throw Failure("falta o valor de \(flag)") }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "-t", "--tamanho": o.size = try next(a); o.sizeGiven = true
        case "--airprint": o.airprint = true
        case "--ajustar": o.fit = "ajustar"
        case "--sem-rodar": o.rotate = false
        case "-n", "--nitidez": o.sharpen = try next(a)
        case "-p", "--perfil": o.profile = try next(a)
        case "-i", "--intencao": o.intent = try next(a)
        case "--sem-gestao-cor": o.colorManagement = false
        case "-d", "--fila": o.queue = try next(a)
        case "-c", "--copias":
            guard let n = Int(try next(a)), n >= 1 else { throw Failure("número de cópias inválido") }
            o.copies = n
        case "-o": o.cupsOptions.append(try next(a))
        case "--raster": o.output = try next(a)
        case "--simular": o.dryRun = true
        case "--reter": o.hold = true
        case "--folha-calibracao": o.calSheet = true
        case "--acabamento": o.finish = try next(a)
        case "--eixos": o.axes = try next(a)
        case "--passo":
            guard let n = Int(try next(a)), (1...10).contains(n) else { throw Failure("passo inválido (1–10)") }
            o.step = n
        case "--centro":
            let v = try next(a).split(separator: ",").compactMap { Int($0) }
            guard v.count == 3, v.allSatisfy({ (-10...10).contains($0) }) else {
                throw Failure("--centro espera L,M,W entre -10 e 10")
            }
            o.center = v
        case "-h", "--ajuda": print(usage); exit(0)
        case "--versao", "--version": print(version); exit(0)
        default:
            if a.hasPrefix("-") { throw Failure("opção desconhecida: \(a)") }
            o.files.append(a)
        }
    }
    guard !o.files.isEmpty else { throw Failure("indique pelo menos uma imagem (ver --ajuda)") }
    guard ["nenhuma", "suave", "normal", "forte"].contains(o.sharpen) else {
        throw Failure("nitidez inválida: \(o.sharpen)")
    }
    guard ["percetual", "relativa"].contains(o.intent) else { throw Failure("intenção inválida: \(o.intent)") }
    if !o.size.hasPrefix("ME_") { o.size = "ME_" + o.size }
    guard ["brilhante", "mate"].contains(o.finish) else { throw Failure("acabamento inválido: \(o.finish)") }
    guard ["luz-magenta", "luz-calor", "magenta-calor"].contains(o.axes) else { throw Failure("eixos inválidos: \(o.axes)") }
    if o.calSheet && o.files.count != 1 { throw Failure("a folha de calibração usa exatamente uma foto") }
    return o
}

// MARK: - Utilitários de processos

@discardableResult
func run(_ path: String, _ args: [String]) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let edata = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw Failure("\(path) falhou: \(String(decoding: edata, as: UTF8.self))")
    }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Formatos (do filtro)

struct Media { let name: String; let width: Int; let height: Int; let combine: Bool; let pageHeight: Int }

func loadMedia(_ name: String) throws -> Media {
    let filter = ProcessInfo.processInfo.environment["CPD90_FILTER"] ?? "\(installDir)/filter/rastertomitsud90"
    let table = try run(filter, ["--media"])
    for line in table.split(separator: "\n") {
        let f = line.split(separator: " ")
        guard f.count == 5, let w = Int(f[1]), let h = Int(f[2]), let hp = Int(f[4]) else { continue }
        if String(f[0]).caseInsensitiveCompare(name) == .orderedSame {
            return Media(name: String(f[0]), width: w, height: h, combine: f[3] == "1", pageHeight: hp)
        }
    }
    let names = table.split(separator: "\n").compactMap { $0.split(separator: " ").first }.joined(separator: ", ")
    throw Failure("formato desconhecido: \(name). Disponíveis: \(names)")
}

// MARK: - Fila e opções do driver

func findQueue() throws -> String {
    for q in try run("/usr/bin/lpstat", ["-e"]).split(separator: "\n").map(String.init) {
        if let ppd = try? String(contentsOfFile: "/etc/cups/ppd/\(q).ppd", encoding: .isoLatin1),
           ppd.contains("rastertomitsud90") { return q }
    }
    throw Failure("nenhuma fila usa o driver CP-D90DW Universal (indique uma com --fila)")
}

// MARK: - Imagem em memória (XRGB 8 bits, no espaço de cor de origem)

final class Pixels {
    var buffer: vImage_Buffer
    init(width: Int, height: Int) throws {
        buffer = vImage_Buffer()
        let e = vImageBuffer_Init(&buffer, vImagePixelCount(height), vImagePixelCount(width), 32, vImage_Flags(kvImageNoFlags))
        guard e == kvImageNoError else { throw Failure("sem memória (\(e))") }
    }
    init(adopting b: vImage_Buffer) { buffer = b }
    deinit { free(buffer.data) }
    var width: Int { Int(buffer.width) }
    var height: Int { Int(buffer.height) }
}

struct Loaded {
    let pixels: Pixels; let colorSpace: CGColorSpace; let iccName: String
    var dpi: Int = 0                  // resolução declarada (URF); 0 = desconhecida
}

// MARK: - URF (Apple Raster, AirPrint)

/// Lê um ficheiro URF ("UNIRAST"), o formato que o iPhone envia por AirPrint.
/// Cada página: cabeçalho de 32 bytes (bpp, espaço de cor, …, largura,
/// altura e resolução em big-endian) e linhas comprimidas: um byte de
/// repetição da linha, depois códigos 0–127 (repetir o píxel seguinte n+1
/// vezes), 129–255 (257−n píxeis literais) e 128 (resto da linha a branco).
func loadURF(_ data: Data, _ name: String) throws -> [Loaded] {
    let b = [UInt8](data)
    func be32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
    guard b.count >= 12, b.starts(with: Array("UNIRAST".utf8) + [0]) else { throw Failure("\(name): não é URF") }
    let pages = be32(8)
    var pos = 12, out: [Loaded] = []
    func need(_ n: Int) throws { if pos + n > b.count { throw Failure("\(name): URF truncado") } }
    for _ in 0..<pages {
        try need(32)
        let bpp = Int(b[pos]), cs = b[pos + 1]
        let w = be32(pos + 12), h = be32(pos + 16), dpi = be32(pos + 20)
        pos += 32
        guard bpp == 24 || bpp == 8, w > 0, h > 0, w <= 20000, h <= 20000 else {
            throw Failure("\(name): URF não suportado (\(bpp) bpp, \(w)×\(h))")
        }
        let bytes = bpp / 8
        let px = try Pixels(width: w, height: h)
        var line = [UInt8](repeating: 255, count: w * 4)
        var y = 0
        while y < h {
            try need(1)
            let rep = Int(b[pos]) + 1; pos += 1
            for i in stride(from: 0, to: line.count, by: 1) { line[i] = 255 }
            var x = 0
            func put(_ at: Int, _ p: Int) {         // p = posição do píxel em b
                let o = at * 4
                if bytes == 3 { line[o + 1] = b[p]; line[o + 2] = b[p + 1]; line[o + 3] = b[p + 2] }
                else { line[o + 1] = b[p]; line[o + 2] = b[p]; line[o + 3] = b[p] }
            }
            while x < w {
                try need(1)
                let c = Int(b[pos]); pos += 1
                if c == 128 { x = w; break }
                if c < 128 {
                    try need(bytes)
                    for _ in 0..<(c + 1) where x < w { put(x, pos); x += 1 }
                    pos += bytes
                } else {
                    let n = 257 - c
                    try need(n * bytes)
                    for k in 0..<n where x < w { put(x, pos + k * bytes); x += 1 }
                    pos += n * bytes
                }
            }
            for r in 0..<rep where y + r < h {
                let row = px.buffer.data.advanced(by: (y + r) * px.buffer.rowBytes)
                _ = line.withUnsafeBytes { memcpy(row, $0.baseAddress!, w * 4) }
            }
            y += rep
        }
        // Espaço de cor: 1 = sRGB (e o cinzento sGray é tratado como sRGB neutro).
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        out.append(Loaded(pixels: px, colorSpace: space, iccName: cs == 1 ? "sRGB (URF)" : "sGray (URF)", dpi: dpi))
    }
    return out
}

/// Todas as páginas de um ficheiro: URF pode ter várias; as outras imagens, uma.
func loadImages(_ path: String) throws -> [Loaded] {
    if let fh = FileHandle(forReadingAtPath: path) {
        let head = fh.readData(ofLength: 8); fh.closeFile()
        if head == Data("UNIRAST".utf8) + Data([0]) {
            return try loadURF(try Data(contentsOf: URL(fileURLWithPath: path)), path)
        }
    }
    return [try loadImage(path)]
}

func loadImage(_ path: String) throws -> Loaded {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { throw Failure("não foi possível ler \(path)") }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0, ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
    // Imagem inteira já com a orientação EXIF aplicada pelo ImageIO (a
    // referência do sistema), sem reamostragem: tamanho máximo = lado maior.
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: max(pw, ph)]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        throw Failure("não foi possível ler \(path)")
    }

    // Espaço de cor da própria imagem (sem conversão); imagens sem perfil ou
    // não-RGB são tratadas como sRGB.
    var cs = img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    if cs.model != .rgb { cs = CGColorSpace(name: CGColorSpace.sRGB)! }
    let name = (cs.name as String?) ?? (cs.copyICCData() != nil ? "perfil embutido" : "sRGB")

    var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32,
        colorSpace: Unmanaged.passUnretained(cs),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
        version: 0, decode: nil, renderingIntent: .defaultIntent)
    var buf = vImage_Buffer()
    let e = vImageBuffer_InitWithCGImage(&buf, &format, nil, img, vImage_Flags(kvImageNoFlags))
    guard e == kvImageNoError else { throw Failure("não foi possível descodificar \(path) (\(e))") }
    return Loaded(pixels: Pixels(adopting: buf), colorSpace: cs, iccName: name)
}

func rotate90(_ p: Pixels, clockwise: Bool) throws -> Pixels {
    let out = try Pixels(width: p.height, height: p.width)
    var bg: [UInt8] = [255, 255, 255, 255]
    let k = UInt8(clockwise ? kRotate90DegreesClockwise : kRotate90DegreesCounterClockwise)
    vImageRotate90_ARGB8888(&p.buffer, &out.buffer, k, &bg, vImage_Flags(kvImageNoFlags))
    return out
}

// MARK: - Geometria

/// Redimensiona e corta/encaixa para exatamente w×h.
func fitTo(_ p: Pixels, _ w: Int, _ h: Int, fill: Bool) throws -> Pixels {
    if p.width == w && p.height == h { return p }
    let sx = Double(w) / Double(p.width), sy = Double(h) / Double(p.height)
    let s = fill ? max(sx, sy) : min(sx, sy)
    let sw = max(1, Int((Double(p.width) * s).rounded())), sh = max(1, Int((Double(p.height) * s).rounded()))
    let scaled = try Pixels(width: sw, height: sh)
    let e = vImageScale_ARGB8888(&p.buffer, &scaled.buffer, nil, vImage_Flags(kvImageHighQualityResampling))
    guard e == kvImageNoError else { throw Failure("falha ao redimensionar (\(e))") }

    let out = try Pixels(width: w, height: h)
    var white: [UInt8] = [255, 255, 255, 255]
    vImageBufferFill_ARGB8888(&out.buffer, &white, vImage_Flags(kvImageNoFlags))
    // Copiar a zona central comum.
    let cw = min(sw, w), ch = min(sh, h)
    let srcX = (sw - cw) / 2, srcY = (sh - ch) / 2, dstX = (w - cw) / 2, dstY = (h - ch) / 2
    for y in 0..<ch {
        let s = scaled.buffer.data.advanced(by: (srcY + y) * scaled.buffer.rowBytes + srcX * 4)
        let d = out.buffer.data.advanced(by: (dstY + y) * out.buffer.rowBytes + dstX * 4)
        memcpy(d, s, cw * 4)
    }
    return out
}

// MARK: - Nitidez de saída (máscara de desfocagem, raio ≈ 1 px a 300 ppp)

func sharpen(_ p: Pixels, amount: Float) throws -> Pixels {
    guard amount > 0 else { return p }
    let blurred = try Pixels(width: p.width, height: p.height)
    // Núcleo gaussiano 5×5 (σ ≈ 1), soma 256.
    let k: [Int16] = [1, 4, 6, 4, 1, 4, 16, 24, 16, 4, 6, 24, 36, 24, 6, 4, 16, 24, 16, 4, 1, 4, 6, 4, 1]
    var bg: [UInt8] = [0, 0, 0, 0]
    let e = vImageConvolve_ARGB8888(&p.buffer, &blurred.buffer, nil, 0, 0, k, 5, 5, 256, &bg,
                                    vImage_Flags(kvImageEdgeExtend))
    guard e == kvImageNoError else { throw Failure("falha na nitidez (\(e))") }
    let n = p.buffer.rowBytes * p.height
    let o = p.buffer.data.assumingMemoryBound(to: UInt8.self)
    let b = blurred.buffer.data.assumingMemoryBound(to: UInt8.self)
    for i in 0..<n where i % 4 != 0 {  // byte 0 de cada píxel é o X (ignorado)
        let v = Float(o[i]) + amount * (Float(o[i]) - Float(b[i]))
        o[i] = UInt8(max(0, min(255, v.rounded())))
    }
    return p
}

// MARK: - Cor

/// XRGB8888 -> RGB888 compacto (sem conversão de cor).
func packRGB(_ p: Pixels) throws -> [UInt8] {
    var rgb = [UInt8](repeating: 0, count: p.width * p.height * 3)
    try rgb.withUnsafeMutableBytes { raw in
        var dst = vImage_Buffer(data: raw.baseAddress, height: p.buffer.height, width: p.buffer.width, rowBytes: p.width * 3)
        let e = vImageConvert_ARGB8888toRGB888(&p.buffer, &dst, vImage_Flags(kvImageNoFlags))
        guard e == kvImageNoError else { throw Failure("falha na conversão de formato (\(e))") }
    }
    return rgb
}

func iccTransform(_ rgb: inout [UInt8], width: Int, height: Int,
                  source: CGColorSpace, printerProfile: String, intent: String) throws {
    guard let srcData = source.copyICCData(),
          let srcProf = ColorSyncProfileCreate(srcData, nil)?.takeRetainedValue() else {
        throw Failure("não foi possível obter o perfil de cor da imagem")
    }
    guard let dstProf = ColorSyncProfileCreateWithURL(URL(fileURLWithPath: printerProfile) as CFURL, nil)?
            .takeRetainedValue() else {
        throw Failure("não foi possível abrir o perfil \(printerProfile)")
    }
    let ri = (intent == "relativa" ? kColorSyncRenderingIntentRelative : kColorSyncRenderingIntentPerceptual)!
    let seq: [[String: Any]] = [
        [kColorSyncProfile.takeUnretainedValue() as String: srcProf,
         kColorSyncRenderingIntent.takeUnretainedValue() as String: ri.takeUnretainedValue(),
         kColorSyncTransformTag.takeUnretainedValue() as String: kColorSyncTransformDeviceToPCS.takeUnretainedValue()],
        [kColorSyncProfile.takeUnretainedValue() as String: dstProf,
         kColorSyncRenderingIntent.takeUnretainedValue() as String: ri.takeUnretainedValue(),
         kColorSyncTransformTag.takeUnretainedValue() as String: kColorSyncTransformPCSToDevice.takeUnretainedValue()],
    ]
    let opts: [String: Any] = [kColorSyncBlackPointCompensation.takeUnretainedValue() as String: true]
    guard let t = ColorSyncTransformCreate(seq as CFArray, opts as CFDictionary)?.takeRetainedValue() else {
        throw Failure("não foi possível criar a transformação de cor")
    }
    // Conversão em vírgula flutuante: o caminho de 8 bits da ColorSync quantiza
    // as tabelas do perfil e afasta-se até ~30 níveis do resultado de
    // referência (sips); em float coincide (ver docs/CPD90-PRINT.md).
    let layout = ColorSyncDataLayout(kColorSyncAlphaNone.rawValue)
    let n = width * height * 3
    var fin = [Float](repeating: 0, count: n), fout = [Float](repeating: 0, count: n)
    for i in 0..<n { fin[i] = Float(rgb[i]) / 255 }
    let ok = fout.withUnsafeMutableBytes { d in
        fin.withUnsafeBytes { s in
            ColorSyncTransformConvert(t, width, height, d.baseAddress!, kColorSync32BitFloat, layout, width * 12,
                                      s.baseAddress!, kColorSync32BitFloat, layout, width * 12, nil)
        }
    }
    for i in 0..<n { rgb[i] = UInt8(max(0, min(255, (fout[i] * 255).rounded()))) }
    guard ok else { throw Failure("a conversão de cor falhou") }
}


// MARK: - Calibração (docs/PROTOCOL.md)

let calAxisNames = ["L", "M", "W"]

/// Valor predefinido de uma opção da fila (a escolha marcada com * no lpoptions -l).
func queueDefault(_ queue: String, _ option: String) -> String? {
    guard let out = try? run("/usr/bin/lpoptions", ["-p", queue, "-l"]) else { return nil }
    for line in out.split(separator: "\n") where line.hasPrefix(option + "/") {
        return line.split(separator: " ").first(where: { $0.hasPrefix("*") }).map { String($0.dropFirst()) }
    }
    return nil
}

/// Curvas R, G, B de uma calibração, calculadas pelo próprio filtro
/// (`rastertomitsud90 --curva`), que é a única implementação da fórmula.
func calibrationCurves(_ v: [Int]) throws -> [[UInt8]] {
    let filter = ProcessInfo.processInfo.environment["CPD90_FILTER"] ?? "\(installDir)/filter/rastertomitsud90"
    let lines = try run(filter, ["--curva"] + v.map(String.init)).split(separator: "\n")
    let curves = lines.prefix(3).map { $0.split(separator: " ").compactMap { UInt8($0) } }
    guard curves.count == 3, curves.allSatisfy({ $0.count == 256 }) else { throw Failure("curva inválida do filtro") }
    return curves
}

func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "−\(-n)" : "0" }

/// Texto preto sobre branco, RGB compacto w×h.
func renderLabel(_ text: String, width: Int, height: Int) -> [UInt8] {
    var rgbx = [UInt8](repeating: 255, count: width * height * 4)
    rgbx.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(height) * 0.55, nil)
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: CGFloat(height) * 0.28)
        CTLineDraw(line, ctx)
    }
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for i in 0..<(width * height) {
        rgb[3 * i] = rgbx[4 * i]; rgb[3 * i + 1] = rgbx[4 * i + 1]; rgb[3 * i + 2] = rgbx[4 * i + 2]
    }
    return rgb
}

func blit(_ page: inout [UInt8], _ pageW: Int, _ src: [UInt8], _ w: Int, _ h: Int, _ x0: Int, _ y0: Int) {
    for y in 0..<h {
        let d = ((y0 + y) * pageW + x0) * 3, s = y * w * 3
        page.replaceSubrange(d..<d + w * 3, with: src[s..<s + w * 3])
    }
}

struct Sheet { let rgb: [UInt8]; let variants: [[Int]] }

/// Roda um buffer RGB compacto 90° no sentido anti-horário (como rotate90).
func rotateRGBCounterClockwise(_ src: [UInt8], width w: Int, height h: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: src.count)
    // Destino h×w: o píxel (x, y) da origem vai para (y, w − 1 − x).
    for y in 0..<h {
        for x in 0..<w {
            let s = (y * w + x) * 3, d = ((w - 1 - x) * h + y) * 3
            out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]
        }
    }
    return out
}

/// Folha 3×3: linhas = 1.º eixo (+passo, 0, −passo, de cima para baixo),
/// colunas = 2.º eixo (−passo, 0, +passo, da esquerda para a direita).
/// A folha é composta na orientação da foto (tal como o macOS a mostra), com
/// as legendas alinhadas com ela, e só no fim é rodada inteira para o papel.
func calibrationSheet(_ img: Loaded, pageW: Int, pageH: Int, o: Options, profile: String,
                      center: [Int], axes: (Int, Int)) throws -> Sheet {
    let p0 = img.pixels
    let turn = (p0.width > p0.height) != (pageW > pageH) && p0.width != p0.height
    let sw = turn ? pageH : pageW, sh = turn ? pageW : pageH
    let gutter = 8, labelH = 64
    let cw = sw / 3, ch = sh / 3
    let iw = cw - 2 * gutter, ih = ch - 2 * gutter - labelH
    var p = try fitTo(p0, iw, ih, fill: true)
    p = try sharpen(p, amount: 0.7)
    var cell = try packRGB(p)
    if o.colorManagement {
        try iccTransform(&cell, width: iw, height: ih, source: img.colorSpace, printerProfile: profile, intent: o.intent)
    }
    var sheet = [UInt8](repeating: 255, count: sw * sh * 3)
    var variants: [[Int]] = []
    for r in 0..<3 {
        for c in 0..<3 {
            var v = center
            v[axes.0] = max(-10, min(10, v[axes.0] + (1 - r) * o.step))
            v[axes.1] = max(-10, min(10, v[axes.1] + (c - 1) * o.step))
            variants.append(v)
            let lut = try calibrationCurves(v)
            var px = cell
            for i in stride(from: 0, to: px.count, by: 3) {
                px[i] = lut[0][Int(px[i])]; px[i + 1] = lut[1][Int(px[i + 1])]; px[i + 2] = lut[2][Int(px[i + 2])]
            }
            let x0 = c * cw + gutter, y0 = r * ch + gutter
            blit(&sheet, sw, px, iw, ih, x0, y0)
            let text = zip(calAxisNames, v).map { "\($0) \(signed($1))" }.joined(separator: "   ")
                + (r == 1 && c == 1 ? "   (atual)" : "")
            blit(&sheet, sw, renderLabel(text, width: iw, height: labelH), iw, labelH, x0, y0 + ih)
        }
    }
    let page = turn ? rotateRGBCounterClockwise(sheet, width: sw, height: sh) : sheet
    return Sheet(rgb: page, variants: variants)
}

// MARK: - CUPS raster v3 (little-endian, sem compressão)

func rasterHeader(width: Int, height: Int, pageSizeName: String) -> Data {
    var h = Data(count: 1796)
    func u32(_ off: Int, _ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { h.replaceSubrange(off..<off + 4, with: $0) } }
    func f32(_ off: Int, _ v: Float) { u32(off, v.bitPattern) }
    let wpt = UInt32((Double(width) * 72 / 300).rounded()), hpt = UInt32((Double(height) * 72 / 300).rounded())
    u32(276, 300); u32(280, 300)                  // HWResolution
    u32(284, 0); u32(288, 0); u32(292, wpt); u32(296, hpt)  // ImagingBoundingBox
    u32(340, 1)                                    // NumCopies
    u32(352, wpt); u32(356, hpt)                   // PageSize
    u32(372, UInt32(width)); u32(376, UInt32(height))
    u32(384, 8); u32(388, 24); u32(392, UInt32(width * 3))  // bits/cor, bits/píxel, bytes/linha
    u32(396, 0); u32(400, 1)                       // CUPS_ORDER_CHUNKED, CUPS_CSPACE_RGB
    u32(420, 3)                                    // cupsNumColors
    f32(428, Float(wpt)); f32(432, Float(hpt))     // cupsPageSize
    f32(444, Float(wpt)); f32(448, Float(hpt))     // cupsImagingBBox (direita, topo)
    let name = Array(pageSizeName.utf8.prefix(63))
    h.replaceSubrange(1732..<1732 + name.count, with: name)
    return h
}

// MARK: - Principal

/// Formato da CP-D90 para uma página AirPrint, pelo tamanho físico: o lado
/// maior ≥ 7" é 6×8" (15x20); o resto é 4×6" (10x15).
func airprintSize(_ img: Loaded) -> String {
    let dpi = Double(img.dpi > 0 ? img.dpi : 300)
    let longSide = Double(max(img.pixels.width, img.pixels.height)) / dpi
    return longSide >= 7 ? "ME_15x20" : "ME_10x15"
}

func main() throws {
    var o = try parseArgs()
    let pages = o.calSheet ? [] : try o.files.flatMap { f in try loadImages(f).map { (f, $0) } }
    if o.airprint && !o.sizeGiven, let first = pages.first?.1 {
        o.size = airprintSize(first)
    }
    let media = try loadMedia(o.size)
    let pageW = media.width, pageH = media.pageHeight
    let queue = o.output == nil ? try (o.queue ?? findQueue()) : (o.queue ?? "")

    // Modo de impressão e perfil: Ultra Fine com o perfil UF, sempre, salvo
    // pedido explícito (-o MEPrintMode=…, --perfil). Com o perfil ST as fotos
    // saem avermelhadas (teste na impressora real, 2026-09-29); por isso o
    // perfil não segue o modo da fila.
    let modeOpt = o.cupsOptions.first { $0.hasPrefix("MEPrintMode=") }?.split(separator: "=").last.map(String.init)
    let mode = modeOpt ?? "UltraFine"
    let profile = o.profile ?? "\(installDir)/Profiles/CPD90_UF.icc"
    if o.colorManagement && !FileManager.default.fileExists(atPath: profile) {
        throw Failure("""
        perfil ICC não encontrado / ICC profile not found: \(profile)
        Instale os perfis da Mitsubishi / Install Mitsubishi's profiles:
          sudo /Library/Printers/CPD90Universal/instalar-perfis.sh <pasta ou .zip do download>
        ou use --perfil FICHEIRO ou --sem-gestao-cor.
        """)
    }
    let amount: Float = ["nenhuma": 0, "suave": 0.35, "normal": 0.7, "forte": 1.1][o.sharpen]!

    info("Formato \(media.name): \(pageW)×\(pageH) px por página, \(o.fit), nitidez \(o.sharpen)")
    info(o.colorManagement
         ? "Cor: perfil da imagem -> \((profile as NSString).lastPathComponent) (\(o.intent), compensação de ponto negro), modo \(mode)"
         : "Cor: sem gestão de cor (píxeis enviados como estão)")

    var raster = Data("3SaR".utf8)
    let finKey = o.finish == "mate" ? "Matte" : "Gloss"
    if o.calSheet {
        let axes: (Int, Int) = ["luz-magenta": (0, 1), "luz-calor": (0, 2), "magenta-calor": (1, 2)][o.axes]!
        let center = o.center ?? calAxisNames.map { ax in
            queue.isEmpty ? 0 : Int(queueDefault(queue, "MECal\(finKey)\(ax)") ?? "0") ?? 0
        }
        let img = try loadImage(o.files[0])
        let sheet = try calibrationSheet(img, pageW: pageW, pageH: pageH, o: o, profile: profile,
                                         center: center, axes: axes)
        let a = calAxisNames[axes.0], b = calAxisNames[axes.1]
        info("Folha de calibração \(o.finish): centro L \(signed(center[0])), M \(signed(center[1])), W \(signed(center[2]))")
        info("  linhas (de cima para baixo): \(a) +\(o.step) / 0 / −\(o.step); colunas (da esquerda para a direita): \(b) −\(o.step) / 0 / +\(o.step)")
        info("  L = luminosidade (+ mais clara), M = magenta (+ menos magenta), W = calor (+ mais quente)")
        raster.append(rasterHeader(width: pageW, height: pageH, pageSizeName: media.name))
        raster.append(contentsOf: sheet.rgb)
    }
    for (f, img) in pages {
        var p = img.pixels
        let landscapeImg = p.width > p.height, landscapePage = pageW > pageH
        var rotated = false
        if o.rotate && landscapeImg != landscapePage && p.width != p.height {
            p = try rotate90(p, clockwise: false)   // como o Lightroom ("Girar para ajustar")
            rotated = true
        }
        let srcW = p.width, srcH = p.height
        p = try fitTo(p, pageW, pageH, fill: o.fit == "preencher")
        p = try sharpen(p, amount: srcW == pageW && srcH == pageH ? 0 : amount)
        var rgb = try packRGB(p)
        if o.colorManagement {
            try iccTransform(&rgb, width: pageW, height: pageH, source: img.colorSpace,
                             printerProfile: profile, intent: o.intent)
        }
        info("  \((f as NSString).lastPathComponent): \(img.pixels.width)×\(img.pixels.height) (\(img.iccName))"
             + (rotated ? ", rodada" : "") + " -> \(pageW)×\(pageH)")
        raster.append(rasterHeader(width: pageW, height: pageH, pageSizeName: media.name))
        raster.append(contentsOf: rgb)
    }

    if let out = o.output {
        try raster.write(to: URL(fileURLWithPath: out))
        info("Raster gravada em \(out)")
        return
    }
    var lpArgs = ["-d", queue, "-n", String(o.copies), "-t", o.airprint ? "iPhone (AirPrint)" : "cpd90-print",
                  "-o", "document-format=application/vnd.cups-raster", "-o", "PageSize=\(media.name)"]
    if modeOpt == nil { lpArgs += ["-o", "MEPrintMode=UltraFine"] }
    if !o.cupsOptions.contains(where: { $0.hasPrefix("MEColorConversion=") }) {
        lpArgs += ["-o", "MEColorConversion=Disabled"]
    }
    if o.calSheet {
        // A folha já leva as variantes: o filtro não aplica mais calibração.
        lpArgs += ["-o", "MEPrintFinish=\(finKey)"]
        for fin in ["Gloss", "Matte"] { for ax in calAxisNames { lpArgs += ["-o", "MECal\(fin)\(ax)=0"] } }
    }
    for c in o.cupsOptions { lpArgs += ["-o", c] }
    if o.hold { lpArgs += ["-H", "hold"] }
    if o.dryRun {
        info("Simulação: lp \(lpArgs.joined(separator: " ")) <raster de \(raster.count) bytes>")
        return
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cpd90-print-\(getpid()).ras")
    try raster.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    print(try run("/usr/bin/lp", lpArgs + [tmp.path]).trimmingCharacters(in: .whitespacesAndNewlines))
    if o.calSheet {
        info("""

        Escolha a variante mais parecida com o ecrã e aplique os valores dela à fila
        (passam a valer para tudo o que for impresso em \(o.finish), incluindo o Lightroom):
          sudo lpadmin -p \(queue) -o MECal\(finKey)L-default=<L> -o MECal\(finKey)M-default=<M> -o MECal\(finKey)W-default=<W>
        """)
    }
}

do { try main() } catch { info("cpd90-print: \(error)"); exit(1) }
