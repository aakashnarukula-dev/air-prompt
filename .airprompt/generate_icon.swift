import Cocoa

let size = CGSize(width: 22, height: 22)
let image = NSImage(size: size)
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Clear background completely
ctx.clear(CGRect(origin: .zero, size: size))

// Use purely black color to act as a proper template mask
ctx.setStrokeColor(NSColor.black.cgColor)
ctx.setLineWidth(2.0)
ctx.setLineCap(.round)

let wave1 = CGMutablePath()
wave1.move(to: CGPoint(x: 2, y: 11))
wave1.addCurve(to: CGPoint(x: 20, y: 11), control1: CGPoint(x: 8, y: 20), control2: CGPoint(x: 14, y: 2))

let wave2 = CGMutablePath()
wave2.move(to: CGPoint(x: 2, y: 11))
wave2.addCurve(to: CGPoint(x: 20, y: 11), control1: CGPoint(x: 8, y: 2), control2: CGPoint(x: 14, y: 20))

ctx.addPath(wave1)
ctx.strokePath()

ctx.addPath(wave2)
ctx.strokePath()

image.unlockFocus()

if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
    if let png = rep.representation(using: .png, properties: [:]) {
        let path = "assets/icon/MenuBarTemplateIcon.png"
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Successfully created MenuBarTemplateIcon.png")
        } catch {
            print("Error writing png: \(error)")
        }
    }
}
