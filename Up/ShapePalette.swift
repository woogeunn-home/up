import AppKit
import CoreGraphics

enum ShapeKind {
    case circle(radius: CGFloat)
    case rect(side: CGFloat)
    case rounded(side: CGFloat, cornerRadius: CGFloat)
    case polygon(sides: Int, circumradius: CGFloat)
}

struct ShapeDefinition {
    let kind: ShapeKind
    let originalHeight: CGFloat
    let visualWidth: CGFloat
}

struct ShapeColor {
    let fill: NSColor
    let icon: NSColor
}

enum ShapePalette {
    static let shapeDefinitions: [ShapeDefinition] = [
        ShapeDefinition(kind: .circle(radius: 20),                     originalHeight: 40, visualWidth: 40),
        ShapeDefinition(kind: .rect(side: 36),                         originalHeight: 36, visualWidth: 36),
        ShapeDefinition(kind: .rounded(side: 36, cornerRadius: 8),     originalHeight: 36, visualWidth: 36),
        ShapeDefinition(kind: .polygon(sides: 3, circumradius: 26),    originalHeight: 52, visualWidth: 52),
        ShapeDefinition(kind: .polygon(sides: 5, circumradius: 22),    originalHeight: 44, visualWidth: 44),
        ShapeDefinition(kind: .polygon(sides: 6, circumradius: 22),    originalHeight: 44, visualWidth: 44)
    ]

    static let colors: [ShapeColor] = [
        ShapeColor(fill: rgb(0xF4, 0xA2, 0x61), icon: rgb(0x1A, 0x1A, 0x1A)),
        ShapeColor(fill: rgb(0xE7, 0x6F, 0x51), icon: .white),
        ShapeColor(fill: rgb(0x2A, 0x9D, 0x8F), icon: .white),
        ShapeColor(fill: rgb(0xE9, 0xC4, 0x6A), icon: rgb(0x1A, 0x1A, 0x1A)),
        ShapeColor(fill: rgb(0x26, 0x46, 0x53), icon: .white),
        ShapeColor(fill: rgb(0xF2, 0x6A, 0x8D), icon: .white),
        ShapeColor(fill: rgb(0x8E, 0x7D, 0xBE), icon: .white)
    ]

    private static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> NSColor {
        NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
