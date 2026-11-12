import AppKit
let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let edge = CGFloat(pixels)
        let tile = NSRect(x: edge * 0.05, y: edge * 0.05, width: edge * 0.90, height: edge * 0.90)
        NSBezierPath(roundedRect: tile, xRadius: edge * 0.20, yRadius: edge * 0.20).addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.27, green: 0.29, blue: 0.46, alpha: 1),
            NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.29, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.20, alpha: 1)
        ])!.draw(in: tile, angle: -70)
        let glow = NSGradient(starting: NSColor(calibratedRed: 0.52, green: 0.43, blue: 0.70, alpha: 0.22), ending: .clear)!
        glow.draw(fromCenter: NSPoint(x: edge*0.35, y: edge*0.72), radius: 0,
                  toCenter: NSPoint(x: edge*0.35, y: edge*0.72), radius: edge*0.65, options: [])
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let rim = NSBezierPath(roundedRect: tile.insetBy(dx: edge*0.003, dy: edge*0.003), xRadius: edge*0.20, yRadius: edge*0.20)
        rim.lineWidth = edge*0.003
        rim.stroke()
        let source = NSImage(contentsOfFile: CommandLine.arguments[2])!
        let scaleFactor = edge * 1.45 / max(source.size.width, source.size.height)
        let renderedSize = NSSize(width: source.size.width * scaleFactor, height: source.size.height * scaleFactor)
        source.draw(in: NSRect(x: (edge-renderedSize.width)/2, y: edge * 0.925 - renderedSize.height, width: renderedSize.width, height: renderedSize.height))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
// Write the standard PNG-backed ICNS container without relying on iconutil.
func uint32(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var chunks = Data()
for (type, file) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(file))
    chunks.append(Data(type.utf8))
    chunks.append(uint32(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(uint32(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: directory).appendingPathExtension("icns"))
