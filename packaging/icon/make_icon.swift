// Gera o ícone próprio do projeto (CPD90.icns), desenhado de raiz:
// uma impressora de sublimação estilizada com uma foto a sair.
// Uso: swift packaging/icon/make_icon.swift <pasta.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 100
    // Foto (a sair da impressora): gradiente pôr-do-sol com margem branca.
    let photo = NSRect(x: 28 * u, y: 46 * u, width: 44 * u, height: 44 * u)
    NSColor.white.setFill(); NSBezierPath(roundedRect: photo, xRadius: 2 * u, yRadius: 2 * u).fill()
    let inner = photo.insetBy(dx: 3 * u, dy: 3 * u)
    NSGradient(colors: [NSColor(calibratedRed: 0.99, green: 0.62, blue: 0.25, alpha: 1),
                        NSColor(calibratedRed: 0.93, green: 0.30, blue: 0.45, alpha: 1),
                        NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.80, alpha: 1)])!
        .draw(in: inner, angle: 90)
    NSColor(calibratedRed: 1, green: 0.93, blue: 0.6, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: inner.midX - 6 * u, y: inner.minY + 12 * u, width: 12 * u, height: 12 * u)).fill()
    NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.25, alpha: 1).setFill()
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: inner.minX, y: inner.minY))
    hill.curve(to: NSPoint(x: inner.maxX, y: inner.minY + 8 * u),
               controlPoint1: NSPoint(x: inner.minX + 12 * u, y: inner.minY + 16 * u),
               controlPoint2: NSPoint(x: inner.midX, y: inner.minY))
    hill.line(to: NSPoint(x: inner.maxX, y: inner.minY)); hill.close(); hill.fill()
    // Corpo da impressora.
    let body = NSRect(x: 10 * u, y: 12 * u, width: 80 * u, height: 40 * u)
    NSGradient(starting: NSColor(calibratedWhite: 0.96, alpha: 1), ending: NSColor(calibratedWhite: 0.78, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: body, xRadius: 9 * u, yRadius: 9 * u), angle: -90)
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.5 * u, dy: 0.5 * u), xRadius: 9 * u, yRadius: 9 * u)
    outline.lineWidth = max(1, 1.2 * u); outline.stroke()
    // Ranhura de saída e luz de estado.
    NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 24 * u, y: 44 * u, width: 52 * u, height: 4 * u), xRadius: 2 * u, yRadius: 2 * u).fill()
    NSColor(calibratedRed: 0.2, green: 0.75, blue: 0.4, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 76 * u, y: 20 * u, width: 6 * u, height: 6 * u)).fill()
    // Texto "D90".
    let font = NSFont.systemFont(ofSize: 15 * u, weight: .heavy)
    let text = NSAttributedString(string: "D90", attributes: [.font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.30, alpha: 1)])
    text.draw(at: NSPoint(x: 18 * u, y: 20 * u))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                     ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                     ("512x512", 512), ("512x512@2x", 1024)] {
    let png = draw(CGFloat(size)).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
