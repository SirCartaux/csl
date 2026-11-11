import AppKit
import CoreText

// Publication layout: exact text and native typography over decorative art.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fontURL = root.appendingPathComponent("Resources/Fonts/Silkscreen-Bold.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let art = NSImage(contentsOf: root.appendingPathComponent("docs/readme/brand-art.png"))!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
let cream = color(237, 230, 214), amber = color(255, 194, 75)
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
           tint: NSColor, font: NSFont? = nil) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: font ?? NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: tint
    ])
}
func render(width: Int, height: Int, path: String) throws {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocusFlipped(true)
    let scale = CGFloat(width) / 1440
    NSAffineTransform(scaleBy: scale).concat()
    color(6, 8, 17).setFill()
    NSRect(x: 0, y: 0, width: 1440, height: 720).fill()
    art.draw(in: NSRect(x: 300, y: -80, width: 1280, height: 854),
        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    let fade = NSGradient(colors: [color(6, 8, 17), color(6, 8, 17), color(6, 8, 17).withAlphaComponent(0)])!
    fade.draw(in: NSRect(x: 0, y: 0, width: 960, height: 720), angle: 0)
    label("CSL", x: 78, y: 55, size: 45, tint: amber, font: NSFont(name: "Silkscreen-Bold", size: 45))
    label("COMMAND SEARCH LAUNCHER", x: 82, y: 127, size: 15,
          tint: color(160, 169, 191), font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium))
    label("Your Mac.", x: 76, y: 201, size: 89, tint: cream)
    label("Within reach.", x: 76, y: 296, size: 89, tint: cream)
    label("Search. Launch. Keep moving.", x: 82, y: 422, size: 25,
          tint: color(160, 169, 191), font: NSFont.systemFont(ofSize: 25, weight: .regular))
    let key = NSBezierPath(roundedRect: NSRect(x: 82, y: 520, width: 195, height: 57), xRadius: 12, yRadius: 12)
    color(22, 25, 37).setFill(); key.fill()
    color(61, 69, 91).setStroke(); key.lineWidth = 1; key.stroke()
    label("⌘ SPACE", x: 107, y: 534, size: 23, tint: amber,
          font: NSFont.monospacedSystemFont(ofSize: 23, weight: .semibold))
    label("NATIVE MACOS  /  SWIFT + APPKIT", x: 305, y: 541, size: 13,
          tint: color(160, 169, 191), font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium))
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(path))
}
// NSAffineTransform convenience without an external graphics dependency.
extension NSAffineTransform {
    convenience init(scaleBy scale: CGFloat) { self.init(); self.scale(by: scale) }
}
try render(width: 1440, height: 640, path: "docs/readme/hero.png")
try render(width: 1280, height: 640, path: "docs/social-preview.png")
