import AppKit
import Foundation

// Original Melicum artwork. Shared geometry for SVG masters and PNG assets.
// A lyre drawn as an equalizer: the yoke is an EQ curve with three hollow nodes,
// the strings end on that curve, and the sound box is an HDMI receptacle profile.
// Construction follows Gitdeck: flat two-tone fills carved by clear space around
// every stroke and node. Palette: "Vinyl and VU", graphite with a VU-needle red.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
let brand = root.appendingPathComponent("brand", isDirectory: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

struct VectorPath {
    let data: String
    func bezier() -> NSBezierPath {
        let tokens = data.split(separator: " ").map(String.init)
        let result = NSBezierPath()
        var index = 0
        func number() -> CGFloat { defer { index += 1 }; return CGFloat(Double(tokens[index])!) }
        func point() -> NSPoint { NSPoint(x: number(), y: number()) }
        while index < tokens.count {
            let command = tokens[index]; index += 1
            switch command {
            case "M": result.move(to: point())
            case "L": result.line(to: point())
            case "C": let c1 = point(), c2 = point(), end = point(); result.curve(to: end, controlPoint1: c1, controlPoint2: c2)
            case "Z": result.close()
            default: fatalError("Unsupported artwork command: \(command)")
            }
        }
        return result
    }
}

struct Fill { let path: VectorPath; let accent: Bool }
struct Stroke { let path: VectorPath; let width: CGFloat }

func mirrored(_ data: String) -> String {
    let tokens = data.split(separator: " ").map(String.init)
    var output: [String] = [], numeric = 0
    for token in tokens {
        if Double(token) == nil { output.append(token); numeric = 0; continue }
        output.append(numeric % 2 == 0 ? String(format: "%g", 1024 - Double(token)!) : token)
        numeric += 1
    }
    return output.joined(separator: " ")
}

// The yoke is a cubic curve; each string ends exactly on it.
let yoke: [(Double, Double)] = [(300, 262), (400, 230), (450, 300), (512, 300)]
func yokeY(atX x: Double) -> Double {
    func at(_ t: Double, _ k: KeyPath<(Double, Double), Double>) -> Double {
        let u = 1 - t
        return u * u * u * yoke[0][keyPath: k] + 3 * u * u * t * yoke[1][keyPath: k] + 3 * u * t * t * yoke[2][keyPath: k] + t * t * t * yoke[3][keyPath: k]
    }
    var t = 0.5
    for _ in 0..<30 { t += (x - at(t, \.0)) / 600 }
    return (at(t, \.1) * 10).rounded() / 10
}

let leftArm = "M 384 712 C 276 660 222 556 230 430 C 236 352 262 292 256 236 C 252 206 236 186 214 172 C 262 170 300 200 314 246 C 324 284 304 360 304 436 C 304 540 352 640 440 712 Z"
let fills = [
    Fill(path: VectorPath(data: leftArm), accent: false),
    Fill(path: VectorPath(data: mirrored(leftArm)), accent: true),
    Fill(path: VectorPath(data: "M 348 740 L 676 740 L 676 784 L 630 834 L 394 834 L 348 784 Z"), accent: false),
]
let strings = [444.0, 478.0].flatMap { x -> [Stroke] in
    let y = yokeY(atX: x)
    return [Stroke(path: VectorPath(data: "M \(x) \(y) L \(x) 712"), width: 11),
            Stroke(path: VectorPath(data: "M \(1024 - x) \(y) L \(1024 - x) 712"), width: 11)]
}
let strokes = [
    Stroke(path: VectorPath(data: "M 300 262 C 400 230 450 300 512 300 C 574 300 624 230 724 262"), width: 18),
    Stroke(path: VectorPath(data: "M 300 712 L 724 712"), width: 18),
] + strings + [
    Stroke(path: VectorPath(data: "M 512 300 L 512 712"), width: 11),
    Stroke(path: VectorPath(data: "M 430 788 L 594 788"), width: 9),
]
let nodes: [(CGFloat, CGFloat)] = [(300, 262), (512, 300), (724, 262)]
let gap: CGFloat = 13, nodeRadius: CGFloat = 30, nodeWidth: CGFloat = 15

let ink = "#F3EDE2", red = "#FF5A47", inkOnLight = "#1E1E24", redOnLight = "#DE3B29"
let tileStops: [(String, CGFloat)] = [("#3D3D46", 0), ("#26262D", 0.55), ("#111114", 1)]
// The icon sits on the macOS grid: an 824 px tile inset 100 px on a 1024 px canvas.
let tile = (origin: CGFloat(100), size: CGFloat(824), radius: CGFloat(185))
let artTransform = "translate(512 516) scale(0.86) translate(-512 -503)"
let markBox = (x: CGFloat(190), y: CGFloat(150), width: CGFloat(644), height: CGFloat(710))

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}

func markSVG(id: String, ink: String, accent: String) -> String {
    let big = "x=\"-200\" y=\"-200\" width=\"1424\" height=\"1424\""
    let halo = strokes.map { "<path d=\"\($0.path.data)\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(Int($0.width + gap * 2))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" }.joined()
        + nodes.map { "<circle cx=\"\(Int($0.0))\" cy=\"\(Int($0.1))\" r=\"\(nodeRadius + nodeWidth / 2 + gap)\" fill=\"#000\"/>" }.joined()
    let holes = nodes.map { "<circle cx=\"\(Int($0.0))\" cy=\"\(Int($0.1))\" r=\"\(nodeRadius - nodeWidth / 2)\" fill=\"#000\"/>" }.joined()
    return """
    <defs><mask id="\(id)-fill" maskUnits="userSpaceOnUse" \(big)><rect \(big) fill="#fff"/>\(halo)</mask>
    <mask id="\(id)-line" maskUnits="userSpaceOnUse" \(big)><rect \(big) fill="#fff"/>\(holes)</mask></defs>
    <g mask="url(#\(id)-fill)">\(fills.map { "<path d=\"\($0.path.data)\" fill=\"\($0.accent ? accent : ink)\"/>" }.joined(separator: "\n  "))</g>
    <g mask="url(#\(id)-line)" fill="none" stroke="\(ink)" stroke-linecap="round" stroke-linejoin="round">
      \(strokes.map { "<path d=\"\($0.path.data)\" stroke-width=\"\(Int($0.width))\"/>" }.joined(separator: "\n  "))
      \(nodes.map { "<circle cx=\"\(Int($0.0))\" cy=\"\(Int($0.1))\" r=\"\(Int(nodeRadius))\" stroke-width=\"\(Int(nodeWidth))\"/>" }.joined(separator: "\n  "))
    </g>
    """
}

for (name, markInk, accent) in [("melicum-mark", inkOnLight, redOnLight), ("melicum-mark-dark", ink, red)] {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(Int(markBox.x)) \(Int(markBox.y)) \(Int(markBox.width)) \(Int(markBox.height))\" role=\"img\" aria-label=\"Melicum\">\n\(markSVG(id: name, ink: markInk, accent: accent))\n</svg>\n"
    try svg.write(to: brand.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
let tileRect = "x=\"\(Int(tile.origin))\" y=\"\(Int(tile.origin))\" width=\"\(Int(tile.size))\" height=\"\(Int(tile.size))\" rx=\"\(Int(tile.radius))\""
let iconSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Melicum">
<defs><radialGradient id="tile" cx="0.5" cy="0.28" r="0.95">\(tileStops.map { "<stop offset=\"\($0.1)\" stop-color=\"\($0.0)\"/>" }.joined())</radialGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.1"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>
<rect \(tileRect) fill="url(#tile)"/>
<rect \(tileRect) fill="url(#sheen)"/>
<rect x="101" y="101" width="822" height="822" rx="184" fill="none" stroke="#fff" stroke-opacity="0.08" stroke-width="2"/>
<g transform="\(artTransform)">
\(markSVG(id: "icon", ink: ink, accent: red))
</g>
</svg>
"""
try iconSVG.write(to: brand.appendingPathComponent("melicum-icon.svg"), atomically: true, encoding: .utf8)

func bitmap(width: Int, height: Int) -> (NSBitmapImageRep, NSGraphicsContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    context.imageInterpolation = .high
    context.shouldAntialias = true
    return (rep, context)
}

// Draws the mark in artwork coordinates. Clear space is erased with the clear blend mode,
// so the mark must be drawn into its own transparent layer before compositing.
func drawMark(in context: NSGraphicsContext, ink: NSColor, accent: NSColor) {
    let cg = context.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    for fill in fills { (fill.accent ? accent : ink).setFill(); fill.path.bezier().fill() }
    cg.setBlendMode(.clear)
    for stroke in strokes {
        let halo = stroke.path.bezier(); halo.lineWidth = stroke.width + gap * 2; halo.lineCapStyle = .round; halo.lineJoinStyle = .round; halo.stroke()
    }
    let outer = nodeRadius + nodeWidth / 2 + gap
    for (x, y) in nodes { NSBezierPath(ovalIn: NSRect(x: x - outer, y: y - outer, width: outer * 2, height: outer * 2)).fill() }
    cg.setBlendMode(.normal)
    ink.setStroke()
    for stroke in strokes {
        let line = stroke.path.bezier(); line.lineWidth = stroke.width; line.lineCapStyle = .round; line.lineJoinStyle = .round; line.stroke()
    }
    cg.setBlendMode(.clear)
    let inner = nodeRadius - nodeWidth / 2
    for (x, y) in nodes { NSBezierPath(ovalIn: NSRect(x: x - inner, y: y - inner, width: inner * 2, height: inner * 2)).fill() }
    cg.setBlendMode(.normal)
    for (x, y) in nodes {
        let ring = NSBezierPath(ovalIn: NSRect(x: x - nodeRadius, y: y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)); ring.lineWidth = nodeWidth; ring.stroke()
    }
    cg.endTransparencyLayer()
}

func renderIcon() throws {
    let (rep, context) = bitmap(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let rect = NSRect(x: tile.origin, y: tile.origin, width: tile.size, height: tile.size)
    let shape = NSBezierPath(roundedRect: rect, xRadius: tile.radius, yRadius: tile.radius)
    cg.saveGState()
    shape.addClip()
    let radial = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: tileStops.map { color($0.0).cgColor } as CFArray, locations: tileStops.map { $0.1 })!
    let center = CGPoint(x: tile.origin + tile.size * 0.5, y: tile.origin + tile.size * 0.28)
    cg.drawRadialGradient(radial, startCenter: center, startRadius: 0, endCenter: center, endRadius: tile.size * 0.95, options: [.drawsAfterEndLocation])
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [NSColor.white.withAlphaComponent(0.1).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: 0, y: tile.origin), end: CGPoint(x: 0, y: tile.origin + tile.size * 0.5), options: [])
    cg.restoreGState()
    let hairline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: tile.radius - 1, yRadius: tile.radius - 1)
    hairline.lineWidth = 2; NSColor.white.withAlphaComponent(0.08).setStroke(); hairline.stroke()
    cg.translateBy(x: 512, y: 516); cg.scaleBy(x: 0.86, y: 0.86); cg.translateBy(x: -512, y: -503)
    drawMark(in: context, ink: color(ink), accent: color(red))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("BrandIcon.png"))
}

// The header mark sits on the app's dark window background.
func renderMark() throws {
    let width = 1024, height = Int((CGFloat(width) * markBox.height / markBox.width).rounded())
    let (rep, context) = bitmap(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(width) / markBox.width
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.translateBy(x: -markBox.x, y: -markBox.y)
    drawMark(in: context, ink: color(ink), accent: color(red))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("BrandMark.png"))
}

try renderIcon()
try renderMark()
print("Melicum SVG masters, BrandIcon.png and BrandMark.png generated.")
