// Gera a imagem de pré-visualização do repositório e do site (1280x640),
// a partir do ícone do projeto.
// Uso: swift packaging/icon/make_social_preview.swift docs/icon.png docs/social-preview.png
import AppKit

let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let w: CGFloat = 1280, h: CGFloat = 640

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Fundo escuro com a faixa de acento do site.
NSColor(calibratedRed: 0.082, green: 0.078, blue: 0.071, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
NSColor(calibratedRed: 0.937, green: 0.416, blue: 0.369, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: 10).fill()

icon.draw(in: NSRect(x: 80, y: 170, width: 300, height: 300))

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, _ y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        .kern: size > 50 ? -1.0 : 0.0]
    (s as NSString).draw(at: NSPoint(x: 440, y: y), withAttributes: attrs)
}
let ink = NSColor(calibratedRed: 0.941, green: 0.929, blue: 0.902, alpha: 1)
let muted = NSColor(calibratedRed: 0.659, green: 0.639, blue: 0.600, alpha: 1)
let accent = NSColor(calibratedRed: 0.937, green: 0.416, blue: 0.369, alpha: 1)
text("OPEN-SOURCE macOS DRIVER", 26, .semibold, accent, 440)
text("Mitsubishi", 76, .bold, ink, 340)
text("CP-D90DW", 76, .bold, ink, 252)
text("Native on Apple Silicon and Intel", 34, .regular, muted, 180)
text("No Rosetta 2  ·  macOS 11 or later", 34, .regular, muted, 132)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
