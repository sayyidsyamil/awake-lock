import AppKit

let output = CommandLine.arguments[1]
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 25
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        rounded(NSRect(x: 62, y: 62, width: 900, height: 900), 202,
                NSColor(calibratedRed: 0.97, green: 0.95, blue: 1, alpha: 1))
        NSShadow().set()
        rounded(NSRect(x: 104, y: 104, width: 816, height: 816), 164,
                NSColor(calibratedRed: 0.92, green: 0.88, blue: 0.98, alpha: 1))
        let lilac = NSColor(calibratedRed: 0.49, green: 0.40, blue: 0.78, alpha: 1)
        let shackle = NSBezierPath(roundedRect: NSRect(x: 355, y: 460, width: 314, height: 330), xRadius: 150, yRadius: 150)
        lilac.setStroke(); shackle.lineWidth = 55; shackle.stroke()
        let body = NSBezierPath(roundedRect: NSRect(x: 250, y: 225, width: 524, height: 393), xRadius: 116, yRadius: 116)
        NSGradient(starting: NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.94, alpha: 1), ending: lilac)!
            .draw(in: body, angle: -65)
        for x in [416.0, 575.0] { rounded(NSRect(x: x, y: 414, width: 34, height: 52), 17, .white) }
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 452, y: 358))
        smile.curve(to: NSPoint(x: 572, y: 358), controlPoint1: NSPoint(x: 482, y: 315), controlPoint2: NSPoint(x: 542, y: 315))
        smile.lineWidth = 22; smile.lineCapStyle = .round; smile.stroke()
        NSColor(calibratedRed: 0.68, green: 0.84, blue: 0.74, alpha: 1).setFill()
        let star = NSBezierPath()
        star.move(to: NSPoint(x: 781, y: 803))
        for point in [NSPoint(x: 799, y: 750), NSPoint(x: 852, y: 732), NSPoint(x: 799, y: 714),
                      NSPoint(x: 781, y: 661), NSPoint(x: 763, y: 714), NSPoint(x: 710, y: 732), NSPoint(x: 763, y: 750)] {
            star.line(to: point)
        }
        star.close(); star.fill()
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
