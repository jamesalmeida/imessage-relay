// Renders App/AppIcon.icns: white SF Symbol "bubble.left.fill" on a blue rounded square.
// Usage (macOS): swift scripts/make-icon.swift App/AppIcon.icns
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let rect = NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1),
                        NSColor(calibratedRed: 0.0, green: 0.35, blue: 0.9, alpha: 1)])!
        .draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let w = symbol.size.width, h = symbol.size.height
        symbol.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let dir = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", dir, "-o", out]
try! task.run()
task.waitUntilExit()
print("wrote \(out) status \(task.terminationStatus)")
