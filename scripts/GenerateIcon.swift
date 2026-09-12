import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("App/Assets.xcassets")
let icons = root.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
func json(_ object: Any, at url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
try json(["info": ["author": "xcode", "version": 1]], at: root.appendingPathComponent("Contents.json"))
func drawIcon(pixels: Int, file: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(calibratedRed: 0.045, green: 0.064, blue: 0.077, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    let mint = NSColor(calibratedRed: 0.57, green: 0.98, blue: 0.76, alpha: 1)
    mint.withAlphaComponent(0.15).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 180, y: 250, width: 664, height: 664)); ring.lineWidth = 35; ring.stroke()
    mint.setStroke()
    let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x: 512, y: 582), radius: 332, startAngle: 20, endAngle: 100)
    arc.lineWidth = 35; arc.lineCapStyle = .round; arc.stroke()
    let hands = NSBezierPath(); hands.move(to: NSPoint(x: 512, y: 800)); hands.line(to: NSPoint(x: 512, y: 582)); hands.line(to: NSPoint(x: 665, y: 495))
    hands.lineWidth = 42; hands.lineCapStyle = .round; hands.lineJoinStyle = .round; hands.stroke()
    NSColor(calibratedRed: 0.085, green: 0.115, blue: 0.125, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 174, y: 120, width: 676, height: 215), xRadius: 55, yRadius: 55).fill()
    let value = NSAttributedString(string: ".123", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 155, weight: .semibold), .foregroundColor: mint])
    value.draw(at: NSPoint(x: (1024 - value.size().width) / 2, y: 129))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: icons.appendingPathComponent(file))
}
var entries: [[String: String]] = []
let slots: [(String, Double, [Int])] = [
    ("iphone", 20, [2, 3]), ("iphone", 29, [2, 3]), ("iphone", 40, [2, 3]), ("iphone", 60, [2, 3]),
    ("ipad", 20, [1, 2]), ("ipad", 29, [1, 2]), ("ipad", 40, [1, 2]), ("ipad", 76, [1, 2]), ("ipad", 83.5, [2]),
    ("ios-marketing", 1024, [1])
]
for (idiom, size, scales) in slots {
    for scale in scales {
        let pixels = Int(size * Double(scale)), file = "icon-\(pixels).png"
        try drawIcon(pixels: pixels, file: file)
        let dimension = size == floor(size) ? String(Int(size)) : String(size)
        entries.append(["idiom": idiom, "size": "\(dimension)x\(dimension)", "scale": "\(scale)x", "filename": file])
    }
}
try json(["images": entries, "info": ["author": "xcode", "version": 1]], at: icons.appendingPathComponent("Contents.json"))
let launch = root.appendingPathComponent("LaunchBackground.colorset")
try FileManager.default.createDirectory(at: launch, withIntermediateDirectories: true)
try json(["colors": [["idiom": "universal", "color": ["color-space": "srgb", "components": ["red": "0.035", "green": "0.047", "blue": "0.060", "alpha": "1.000"]]]], "info": ["author": "xcode", "version": 1]], at: launch.appendingPathComponent("Contents.json"))
